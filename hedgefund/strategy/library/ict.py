"""The operator's two MT5 Expert Advisors, ported as platform strategies.

- ``IctProV620``: ICT Ultimate Pro v6.20 (all-in-one): Silver Bullet (M5, NY windows 03-04 /
  10-11 / 14-15) and Macro Breaker (M1, ICT macros) in one pipeline, strict pass then relaxed
  pass, arbitration strict > score > Unicorn, EA position management (break-even, one partial,
  ATR/swing trailing, time stop). Runs on 1-minute bars with 5m / 1h / 1d context.
- ``IctV6``: ICT Ultimate Pro v6: EMA 7/21 cross with EMA 50 filter, plus the v6 Silver Bullet
  (displacement + limited retracement + FVG in server-hour windows), AMD phase filter, ATR spike
  filter, SL clamped to 0.8-2.5 ATR, TP at RR <= 3 or the nearest liquidity pool, and v6
  management (break-even, 50 % partial at 1R, ATR trailing).

How an EA trade maps onto the platform:
- The strategy plans entry, stop and target like the EA. Sizing stays with the platform policy
  (risk % of NAV / stop distance, capped by the bot's max position), and every entry still goes
  through Jev, the risk engine and execution.
- Stops and targets are *virtual*: nothing is placed at the broker. They are checked at every
  bar close against the bar's high/low, and between bars against live quotes (the engine polls
  ``intrabar_exit`` every loop). Exits are market orders, so a fast market can fill past the stop.
- Limit entries (FVG edge, breaker edge) become a pending entry that is taken at market on the
  first bar that trades through the level.
- One position per bot. Trades, pending entries, counters and consumed setups are persisted by
  the platform (``export_state``) so a restart resumes the same plan.
"""

from __future__ import annotations

from typing import Any

from hedgefund.core.timeutil import MINUTE_MS
from hedgefund.core.types import Direction
from hedgefund.data.features import standard_features
from hedgefund.portfolio.book import PositionInfo
from hedgefund.strategy.base import Strategy, StrategyContext
from hedgefund.strategy.library import ict_clock as clk
from hedgefund.strategy.library.ict_core import (
    BUY,
    SELL,
    LiquidityMap,
    Market,
    MBParams,
    Rates,
    ReferenceLevels,
    SBParams,
    dir_str,
    last_swing_high_above,
    last_swing_low_below,
    macro_breaker,
    silver_bullet,
    structure_bias,
)
from hedgefund.strategy.spec import Package

MAX_CONSUMED = 60


def _dir(sign: int) -> Direction:
    return Direction.LONG if sign > 0 else Direction.SHORT


class ManagedTradeStrategy(Strategy):
    """Plans trades with a fixed stop and target and manages them like an EA."""

    def __init__(self, spec):
        super().__init__(spec)
        self.st: dict[str, Any] = {"trade": None, "proposal": None, "pending": None, "consumed": [], "day": [0, 0], "windows": {}, "last_entry_ts": 0, "flattened_day": 0}

    # ---- parameters ----
    def pf(self, key: str, default: float) -> float:
        v = self.p.get(key)
        return float(default if v is None else v)

    def pb(self, key: str, default: bool) -> bool:
        return self.pf(key, 1.0 if default else 0.0) >= 0.5

    @property
    def point(self) -> float:
        return self.pf("point", 0.01) or 0.01

    def spread(self, price: float) -> float:
        return self.spec.costs.slippage_bps_roundtrip / 1e4 * price

    # ---- state ----
    def export_state(self) -> dict[str, Any]:
        return self.st

    def import_state(self, state: dict[str, Any]) -> None:
        if isinstance(state, dict):
            self.st.update({k: v for k, v in state.items() if k in self.st})

    # ---- subclass hooks ----
    def plan_entry(self, ctx: StrategyContext, sym: str, dirs: tuple[int, ...]) -> tuple[dict | None, str, dict[str, float]]:
        raise NotImplementedError

    def manage_config(self) -> dict[str, float]:
        raise NotImplementedError

    def trail_context(self, ctx: StrategyContext, sym: str) -> tuple[float, Rates | None]:
        """(ATR used for trailing, bars used for swing trailing)."""
        raise NotImplementedError

    def context_features(self, ctx: StrategyContext, sym: str) -> dict[str, float]:
        d1 = ctx.view.aux("1d")
        return standard_features(d1, sym, 1) if d1 is not None else {}

    # ---- the bar loop ----
    def evaluate(self, ctx: StrategyContext, pkg: Package):
        sym = pkg.legs[0].symbol
        held = self.held_direction(ctx, pkg)
        if held is not Direction.FLAT:
            return self._manage(ctx, pkg, sym, held)
        self.st["trade"] = None
        self.st["proposal"] = None
        dirs = tuple(d for d, x in ((BUY, Direction.LONG), (SELL, Direction.SHORT)) if x in self.spec.allowed_directions)
        feats = self.context_features(ctx, sym)
        price = ctx.view.last_close(sym)
        if price is None:
            return None, 1.0, "", feats
        pend = self.st.get("pending")
        if pend:
            res = self._pending(ctx, sym, pend, price, feats)
            if res is not None:
                return res
            if self.st.get("pending"):
                return None, 1.0, f"entrée en attente à {pend['entry']:.5g} ({pend['desc']})", feats
        why = self._gates(ctx.ts)
        if why:
            return None, 1.0, why, feats
        plan, why, extra = self.plan_entry(ctx, sym, dirs)
        feats.update(extra)
        if plan is None:
            return None, 1.0, why, feats
        if plan["id"] in self.st["consumed"]:
            return None, 1.0, "setup déjà traité", feats
        wk = plan.get("window_key")
        if wk and self.pf("max_trades_per_window", 1) > 0 and self.st["windows"].get(wk, 0) >= self.pf("max_trades_per_window", 1):
            return None, 1.0, "plafond de trades de la fenêtre atteint", feats
        if not plan["market"]:
            plan["expiry"] = plan["window_end"] + int(plan.get("expiry_min", 45)) * MINUTE_MS
            self.st["pending"] = plan
            self._consume(plan["id"])
            return None, 1.0, f"entrée limite armée à {plan['entry']:.5g} : {plan['desc']}", feats
        return self._propose(ctx, plan, price, feats)

    def _gates(self, now: int) -> str:
        day = clk.ny_day_key(now)
        if self.st["day"][0] != day:
            self.st["day"] = [day, 0]
        cap = self.pf("max_trades_per_day", 0)
        if cap > 0 and self.st["day"][1] >= cap:
            return "plafond de trades du jour atteint"
        fri = self.pf("friday_last_entry_hour", 0)
        if fri > 0 and clk.ny_day_of_week(now) == 5 and clk.ny_minute_of_day(now) >= fri * 60:
            return "vendredi après l'heure limite (NY)"
        gap = self.pf("min_minutes_between_trades", 0)
        if gap > 0 and now - int(self.st.get("last_entry_ts") or 0) < gap * MINUTE_MS:
            return "délai minimum entre deux entrées"
        return ""

    def _consume(self, sid: str) -> None:
        c = self.st["consumed"]
        if sid not in c:
            c.append(sid)
            del c[:-MAX_CONSUMED]

    def _propose(self, ctx: StrategyContext, plan: dict, price: float, feats: dict[str, float]):
        stop_pct = abs(price - plan["sl"]) / price if price else 0.0
        if stop_pct <= 0 or (plan["dir"] == BUY and price <= plan["sl"]) or (plan["dir"] == SELL and price >= plan["sl"]):
            return None, 1.0, "prix déjà au-delà du stop", feats
        plan = {**plan, "ts": ctx.ts, "entry_ref": price}
        self.st["proposal"] = plan
        feats.update({"ict_dir": float(plan["dir"]), "ict_setup": float(plan.get("strength", 0.8)), "ict_rr": float(plan.get("rr", 0.0))})
        return _dir(plan["dir"]), stop_pct, plan["desc"], feats

    def _pending(self, ctx: StrategyContext, sym: str, pend: dict, price: float, feats: dict[str, float]):
        now = ctx.ts
        bar = ctx.view.last_bar(sym)
        d = pend["dir"]
        if now >= pend["expiry"]:
            self.st["pending"] = None
            return None, 1.0, "entrée limite expirée", feats
        if bar is None or bar.ts <= pend["armed_ts"]:
            return None
        if (d == BUY and bar.close < pend["invalid"]) or (d == SELL and bar.close > pend["invalid"]):
            self.st["pending"] = None
            return None, 1.0, "entrée limite invalidée (clôture au-delà de la zone)", feats
        if (d == BUY and bar.high >= pend["tp"]) or (d == SELL and bar.low <= pend["tp"]):
            self.st["pending"] = None
            return None, 1.0, "cible atteinte avant l'entrée", feats
        if (d == BUY and bar.low <= pend["entry"]) or (d == SELL and bar.high >= pend["entry"]):
            self.st["pending"] = None
            risk = abs(price - pend["sl"])
            rr = abs(pend["tp"] - price) / risk if risk > 0 else 0.0
            if rr < 1.0 or (d == BUY and price >= pend["tp"]) or (d == SELL and price <= pend["tp"]):
                return None, 1.0, f"entrée limite touchée mais prix reparti (RR {rr:.2f} < 1)", feats
            return self._propose(ctx, {**pend, "rr": rr, "desc": pend["desc"] + " [limite touchée]"}, price, feats)
        return None

    # ---- open trade ----
    def _sync(self, ctx: StrategyContext, pkg: Package, sym: str, held: Direction) -> dict:
        info = self.entry_info(ctx, pkg)
        sign = held.sign
        trade = self.st.get("trade")
        if trade and info is not None and trade["opened_ts"] == info.opened_ts and trade["dir"] == sign:
            return trade
        prop = self.st.get("proposal")
        entry = info.avg_price if info is not None else (ctx.view.last_close(sym) or 0.0)
        opened = info.opened_ts if info is not None and info.opened_ts is not None else ctx.ts
        if prop and prop["dir"] == sign and opened >= prop["ts"]:
            trade = {k: prop[k] for k in ("id", "kind", "dir", "sl", "tp", "window_end", "desc") if k in prop}
            trade.update(entry=entry, opened_ts=opened, checked_ts=prop["ts"], window_key=prop.get("window_key"), strength=prop.get("strength", 0.8))
            day = clk.ny_day_key(opened)
            self.st["day"] = [day, (self.st["day"][1] if self.st["day"][0] == day else 0) + 1]
            wk = prop.get("window_key")
            if wk:
                w = self.st["windows"]
                w[wk] = w.get(wk, 0) + 1
                for k in list(w)[:-20]:
                    del w[k]
            self.st["last_entry_ts"] = opened
            self._consume(prop["id"])
        else:
            # A position without a plan (state lost, or opened before this version): protect it
            # with the EA's automatic stop (1.5 ATR) and a 2R target rather than leave it naked.
            atr, _ = self.trail_context(ctx, sym)
            dist = 1.5 * atr if atr > 0 else 0.01 * entry
            trade = {"id": "reprise", "kind": "reprise", "dir": sign, "sl": entry - sign * dist, "tp": entry + sign * 2 * dist, "window_end": ctx.ts,
                     "desc": "position reprise sans plan : stop 1,5 ATR, objectif 2R", "entry": entry, "opened_ts": opened, "checked_ts": ctx.ts, "strength": 0.5}
        trade.update(sl0=trade["sl"], risk0=abs(trade["entry"] - trade["sl"]), be_done=False, partial_done=False, mfe_r=0.0, exit_reason=None)
        trade["stop_pct"] = trade["risk0"] / trade["entry"] if trade["entry"] else 0.01
        self.st["trade"] = trade
        self.st["proposal"] = None
        return trade

    def _manage(self, ctx: StrategyContext, pkg: Package, sym: str, held: Direction):
        t = self._sync(ctx, pkg, sym, held)
        feats = self.context_features(ctx, sym)
        feats.update({"ict_dir": float(t["dir"]), "ict_setup": float(t.get("strength", 0.8))})
        stop = max(t["stop_pct"], 1e-6)

        def out(reason: str):
            t["exit_reason"] = reason
            return Direction.FLAT, stop, f"sortie : {reason}", feats

        if t.get("exit_reason"):
            return out(t["exit_reason"])
        d, entry, risk = t["dir"], t["entry"], t["risk0"]
        if risk <= 0 or (entry - t["sl0"]) * d <= 0:
            return out("entrée exécutée au-delà du stop initial")
        cfg = self.manage_config()
        trail_atr, swing_rates = self.trail_context(ctx, sym)
        offset = max(self.spread(entry), cfg.get("be_offset", 0.0))
        step = max(self.spread(entry), cfg.get("trail_min_step", 0.0))
        partial_now = False
        ser, n = ctx.view.series(sym)
        start = n
        while start > 0 and ser.ts[start - 1] > t["checked_ts"]:
            start -= 1
        for i in range(start, n):
            h, lo = ser.high[i], ser.low[i]
            if d == BUY:
                if lo <= t["sl"]:
                    return out(f"stop touché à {t['sl']:.5g}" + (" (break-even / suiveur)" if t["be_done"] else ""))
                if h >= t["tp"]:
                    return out(f"objectif atteint à {t['tp']:.5g}")
                best = h
            else:
                if h >= t["sl"]:
                    return out(f"stop touché à {t['sl']:.5g}" + (" (break-even / suiveur)" if t["be_done"] else ""))
                if lo <= t["tp"]:
                    return out(f"objectif atteint à {t['tp']:.5g}")
                best = lo
            r_best = (best - entry) * d / risk
            t["mfe_r"] = max(t["mfe_r"], r_best)
            if not t["be_done"] and cfg["be_at_r"] > 0 and r_best >= cfg["be_at_r"]:
                be = entry + d * offset
                if (d == BUY and t["sl"] < be) or (d == SELL and t["sl"] > be):
                    t["sl"] = be
                t["be_done"] = True
            if cfg["partial_pct"] > 0 and not t["partial_done"] and r_best >= cfg["partial_at_r"]:
                t["partial_done"] = True
                partial_now = True
            if cfg["trail_start_r"] > 0 and r_best >= cfg["trail_start_r"] and trail_atr > 0:
                cand = best - d * cfg["trail_atr_mult"] * trail_atr
                if cfg.get("trail_by_swing") and swing_rates is not None:
                    sw = (last_swing_low_below if d == BUY else last_swing_high_above)(swing_rates, int(cfg.get("swing_strength", 2)), best, 60)
                    if sw > 0:
                        cand = max(cand, sw - offset) if d == BUY else min(cand, sw + offset)
                beyond_entry = (cand > entry if d == BUY else cand < entry) or not cfg.get("trail_beyond_entry_only", True)
                if beyond_entry and ((d == BUY and cand > t["sl"] + step) or (d == SELL and cand < t["sl"] - step)):
                    t["sl"] = cand
            t["checked_ts"] = ser.ts[i]
        now = ctx.ts
        price = ser.close[n - 1]
        r_now = (price - entry) * d / risk
        if cfg.get("time_stop_min", 0) > 0 and now >= t["window_end"] + cfg["time_stop_min"] * MINUTE_MS and r_now < cfg.get("time_stop_min_r", 0.3):
            return out(f"time stop ({r_now:+.2f}R, {cfg['time_stop_min']:.0f} min après la fin de fenêtre)")
        if cfg.get("max_hold_min", 0) > 0 and now - t["opened_ts"] >= cfg["max_hold_min"] * MINUTE_MS:
            return out("durée maximale atteinte")
        fm = cfg.get("flatten_at_ny_minute", 0)
        if fm > 0 and clk.ny_minute_of_day(now) >= fm and self.st.get("flattened_day") != clk.ny_day_key(now):
            self.st["flattened_day"] = clk.ny_day_key(now)
            return out("fermeture programmée (heure NY)")
        thesis = f"{t['desc']} | {r_now:+.2f}R, SL {t['sl']:.5g}, TP {t['tp']:.5g}" + (", break-even fait" if t["be_done"] else "")
        if partial_now:
            keep = 1.0 - cfg["partial_pct"] / 100.0
            return held, stop, f"allègement partiel ({cfg['partial_pct']:.0f} %) à {cfg['partial_at_r']:.1f}R | " + thesis, feats, keep
        return held, stop, thesis, feats

    def intrabar_exit(self, pkg: Package, book: dict[str, PositionInfo], bid: float, ask: float, ts: int) -> str | None:
        info = book.get(pkg.legs[0].symbol)
        if info is None or not info.qty:
            return None
        t = self.st.get("trade")
        if not t or t["opened_ts"] != info.opened_ts:
            # Filled since the last bar close and not adopted yet: protect it with the plan's levels.
            p = self.st.get("proposal")
            sign = 1 if info.qty > 0 else -1
            t = p if p and p["dir"] == sign and info.opened_ts is not None and info.opened_ts >= p["ts"] else None
        if not t or t.get("exit_reason"):
            return None
        reason = None
        if t["dir"] == BUY:
            if bid <= t["sl"]:
                reason = f"stop touché à {t['sl']:.5g} (prix live {bid:.5g})"
            elif bid >= t["tp"]:
                reason = f"objectif atteint à {t['tp']:.5g} (prix live {bid:.5g})"
        else:
            if ask >= t["sl"]:
                reason = f"stop touché à {t['sl']:.5g} (prix live {ask:.5g})"
            elif ask <= t["tp"]:
                reason = f"objectif atteint à {t['tp']:.5g} (prix live {ask:.5g})"
        if reason:
            t["exit_reason"] = reason
        return reason


# ======================================================================
# ICT Ultimate Pro v6.20: Silver Bullet (M5) + Macro Breaker (M1)
# ======================================================================
class IctProV620(ManagedTradeStrategy):
    LTF_BARS, M1_BARS, HTF_BARS, D1_BARS = 400, 420, 400, 80

    @property
    def warmup_bars(self) -> int:
        return self.M1_BARS

    @property
    def aux_timeframes(self) -> dict[str, int]:
        return {"5m": self.LTF_BARS, "1h": self.HTF_BARS, "1d": self.D1_BARS}

    def sb_params(self) -> SBParams:
        return SBParams(
            min_score=int(self.pf("sb_min_score", 3)), min_rr=self.pf("min_rr", 2.0), min_retrace=self.pf("sb_min_retrace", 0.35),
            sl_buffer_atr=self.pf("sb_sl_buffer_atr", 0.10), max_stop_atr=self.pf("sb_max_stop_atr", 6.0), take_first_fvg=self.pb("sb_take_first_fvg", True),
            require_htf_align=self.pb("require_htf_align", False), disp_body_atr=self.pf("sb_disp_body_atr", 0.8), fvg_min_size_atr=self.pf("sb_fvg_min_atr", 0.12),
            entry_mode=int(self.pf("sb_entry_mode", 0)),
        )

    def mb_params(self) -> MBParams:
        return MBParams(
            min_score=int(self.pf("mb_min_score", 2)), min_rr=self.pf("min_rr", 2.0), sl_buffer_atr=self.pf("mb_sl_buffer_atr", 0.2),
            max_stop_atr=self.pf("mb_max_stop_atr", 12.0), allow_retested=self.pb("mb_allow_retested", True), require_unicorn=self.pb("mb_require_unicorn", False),
            require_htf_align=self.pb("require_htf_align", False), disp_body_atr=self.pf("mb_disp_body_atr", 0.8),
        )

    def manage_config(self) -> dict[str, float]:
        return {
            "be_at_r": self.pf("be_at_r", 1.0), "partial_pct": self.pf("partial_pct", 40), "partial_at_r": self.pf("partial_at_r", 2.0),
            "trail_start_r": self.pf("trailing_start_r", 2.0), "trail_atr_mult": self.pf("trailing_atr_mult", 2.5), "trail_by_swing": self.pb("trail_by_swing", True),
            "swing_strength": 2, "time_stop_min": self.pf("time_stop_min", 75), "time_stop_min_r": self.pf("time_stop_min_r", 0.3),
            "max_hold_min": self.pf("max_hold_min", 0), "flatten_at_ny_minute": self.pf("flatten_at_ny_minute", 0),
            "be_offset": 15 * self.point, "trail_min_step": 20 * self.point, "trail_beyond_entry_only": True,
        }

    def trail_context(self, ctx: StrategyContext, sym: str) -> tuple[float, Rates | None]:
        ltf = Rates.from_view(ctx.view.aux("5m"), sym, self.LTF_BARS)
        return (ltf.atr(1) if ltf else 0.0), ltf

    def _windows(self) -> set[str]:
        return {k for k, p in (("london", "sb_london"), ("ny_am", "sb_ny_am"), ("ny_pm", "sb_ny_pm")) if self.pb(p, True)}

    def _macros(self) -> set[int]:
        groups = {g for g, p in (("london", "mb_london"), ("ny_am", "mb_ny_am"), ("ny_pm", "mb_ny_pm")) if self.pb(p, True)}
        return {m.id for m in clk.MACROS if m.group in groups and m.id in clk.DEFAULT_MACROS}

    def _active(self, now: int) -> tuple[tuple | None, clk.Macro | None]:
        window = clk.window_at(now, self._windows()) if self.pb("enable_sb", True) else None
        macro = None
        if self.pb("enable_mb", True):
            enabled = self._macros()
            macro = clk.macro_at(now)
            if macro is None or macro.id not in enabled:
                rec = clk.macro_recent(now, int(self.pf("mb_retest_grace_min", 25)))
                macro = rec if rec is not None and rec.id in enabled else None
        return window, macro

    def plan_entry(self, ctx: StrategyContext, sym: str, dirs: tuple[int, ...]):
        now = ctx.ts
        window, macro = self._active(now)
        if window is None and macro is None:
            return None, "hors fenêtre Silver Bullet et hors macro", {}
        view = ctx.view
        ltf = Rates.from_view(view.aux("5m"), sym, self.LTF_BARS)
        m1 = Rates.from_view(view, sym, self.M1_BARS)
        htf = Rates.from_view(view.aux("1h"), sym, self.HTF_BARS)
        d1 = Rates.from_view(view.aux("1d"), sym, self.D1_BARS)
        if ltf is None or m1 is None or htf is None or d1 is None or ltf.n < 60 or htf.n < 50 or d1.n < 6:
            return None, "données M5/H1/D1 insuffisantes", {}
        atr, atr_m1, atr_d1 = ltf.atr(1), (m1.atr(1) if m1.n > 20 else 0.0), d1.atr(1)
        if atr <= 0:
            return None, "ATR M5 indisponible", {}
        price = m1.c[1]
        spread = self.spread(price)
        extra = {"ict_atr_ratio": self._atr_ratio(ltf)}
        cap = self.pf("max_spread_atr", 0.15)
        if cap > 0 and spread > cap * atr:
            return None, f"spread {spread:.5g} > {cap:.2f} ATR M5", extra
        liq = LiquidityMap()
        liq.build(now, ltf, htf, d1, atr, (20, 40, 60), 2, 0.10, self.point)
        ref = ReferenceLevels()
        ref.build(now, ltf, m1, htf, d1)
        ref.push_to(liq)
        if m1.n > 60:
            liq.add_swings(m1, 3, 12, "M1")
        adr_cap = self.pf("max_adr_used_pct", 0)
        if adr_cap > 0 and clk.ny_minute_of_day(now) >= 420 and ref.adr_used_pct() >= adr_cap:
            return None, f"ADR déjà utilisé à {ref.adr_used_pct():.0f} %", extra
        bias = structure_bias(htf, 2)
        mk = Market(now, price + spread / 2, price - spread / 2, spread, liq, ref, bias, atr_d1)
        sb = mb = None
        rej_sb = rej_mb = ""
        if window is not None:
            name, ws, we = window
            sb, rej_sb = silver_bullet(ltf, mk, name, ws, we, atr, self.sb_params(), dirs)
            relax = self.pf("sb_relax_after_min", 30)
            if sb is None and relax > 0 and now >= ws + relax * MINUTE_MS:
                sb, _ = silver_bullet(ltf, mk, name, ws, we, atr, self.sb_params().relaxed(), dirs)
                if sb is not None:
                    sb.relaxed, sb.id = True, sb.id + "_RLX"
        if macro is not None and atr_m1 > 0:
            ms, me = clk.macro_range_utc(now, macro)
            mb, rej_mb = macro_breaker(m1, mk, macro, ms, me, atr_m1, atr, self.mb_params(), dirs)
            relax = self.pf("mb_relax_after_min", 8)
            if mb is None and relax > 0 and now >= ms + relax * MINUTE_MS:
                mb, _ = macro_breaker(m1, mk, macro, ms, me, atr_m1, atr, self.mb_params().relaxed(), dirs)
                if mb is not None:
                    mb.relaxed, mb.id = True, mb.id + "_RLX"
        consumed = set(self.st["consumed"])
        if sb is not None and sb.id in consumed:
            sb = None
        if mb is not None and mb.id in consumed:
            mb = None
        if sb is None and mb is None:
            ctx_s = " ".join(x for x in ((window[0] if window else ""), (macro.name if macro else "")) if x)
            return None, f"{ctx_s} | biais H1 {dir_str(bias)} | SB: {rej_sb or '-'} | MB: {rej_mb or '-'}", extra
        if sb is not None and mb is not None:
            if sb.relaxed != mb.relaxed:
                best = mb if sb.relaxed else sb
            elif mb.score > sb.score or (mb.score == sb.score and mb.unicorn):
                best = mb
            else:
                best = sb
        else:
            best = sb or mb
        min_score = self.sb_params().min_score if best.kind == "SB" else self.mb_params().min_score
        strength = min(1.2, 0.75 + 0.1 * (best.score - min_score))
        extra.update({"ict_score": float(best.score), "ict_htf_bias": float(bias * best.dir), "ict_relaxed": float(best.relaxed)})
        plan = {
            "id": best.id, "kind": best.kind, "dir": best.dir, "entry": best.entry, "sl": best.sl, "tp": best.tp, "rr": best.rr,
            "market": best.market_entry, "invalid": best.invalid_level, "window_end": best.window_end, "armed_ts": now,
            "window_key": f"{best.kind}_{best.window_start}", "expiry_min": self.pf("mb_order_expiry_min", 35) if best.kind == "MB" else self.pf("sb_order_expiry_min", 45),
            "desc": best.describe(), "strength": strength, "score": best.score,
        }
        return plan, "", extra

    @staticmethod
    def _atr_ratio(r: Rates) -> float:
        vals = [r.atr(i) for i in range(1, 51)]
        vals = [v for v in vals if v > 0]
        return r.atr(1) / (sum(vals) / len(vals)) if vals and r.atr(1) > 0 else 1.0


# ======================================================================
# ICT Ultimate Pro v6: EMA cross + simple Silver Bullet
# ======================================================================
def _ema(values: list[float], period: int) -> list[float]:
    """EMA seeded with the SMA of the first ``period`` values (chronological order)."""
    if len(values) < period:
        return []
    k = 2.0 / (period + 1)
    e = sum(values[:period]) / period
    out = [e]
    for v in values[period:]:
        e = v * k + e * (1 - k)
        out.append(e)
    return out


class IctV6(ManagedTradeStrategy):
    """ICT Ultimate Pro v6 on the bot's timeframe (5m to 1h)."""

    BARS = 400

    @property
    def warmup_bars(self) -> int:
        return max(200, int(self.pf("ema_filter", 50)) * 4)

    @property
    def aux_timeframes(self) -> dict[str, int]:
        return {"5m": 60, "15m": 25, "4h": 25, "1d": 80}

    def manage_config(self) -> dict[str, float]:
        return {
            "be_at_r": self.pf("be_at_r", 1.0), "partial_pct": self.pf("partial_pct", 50), "partial_at_r": self.pf("partial_at_r", 1.0),
            "trail_start_r": self.pf("trailing_start_r", 1.5), "trail_atr_mult": self.pf("trailing_atr_mult", 1.5), "trail_by_swing": False,
            "be_offset": 30 * self.point, "trail_min_step": self.point, "trail_beyond_entry_only": False,
        }

    def trail_context(self, ctx: StrategyContext, sym: str) -> tuple[float, Rates | None]:
        r = Rates.from_view(ctx.view, sym, 40)
        return (r.atr(1) if r else 0.0), None

    def _server_window(self, now: int) -> tuple[str, int] | None:
        """v6 IsInSilverWindow: server hours 02-05, 09-12, 13-16, 18-21, weekdays (server clock
        UTC+2, UTC+3 in EU summer). Returns (window key, window end)."""
        if clk.server_day_of_week(now) in (0, 6):
            return None
        h = clk.server_hour(now)
        for k, (a, b) in enumerate(((2, 5), (9, 12), (13, 16), (18, 21)), 1):
            if a <= h < b and self.pb(f"sb_window_{k}", True):
                start = now - ((h - a) * 60 + (now // MINUTE_MS) % 60) * MINUTE_MS
                return f"SBv6_{k}_{start}", start + (b - a) * 60 * MINUTE_MS
        return None

    def plan_entry(self, ctx: StrategyContext, sym: str, dirs: tuple[int, ...]):
        now = ctx.ts
        r = Rates.from_view(ctx.view, sym, self.BARS)
        if r is None or r.n < 70:
            return None, "historique insuffisant", {}
        atr = r.atr(1)
        if atr <= 0:
            return None, "ATR indisponible", {}
        price = r.c[1]
        spread = self.spread(price)
        atrs = [r.atr(i) for i in range(1, 51)]
        avg = sum(atrs) / len(atrs) if all(atrs) else 0.0
        extra = {"ict_atr_ratio": atr / avg if avg > 0 else 1.0}
        cap = self.pf("max_spread_atr", 0.25)
        if cap > 0 and spread > cap * atr:
            return None, f"spread {spread:.5g} > {cap:.2f} ATR", extra
        if avg > 0 and atr > avg * self.pf("atr_max_mult", 2.5):
            return None, "volatilité anormale (ATR > moyenne x 2,5)", extra
        if self.pb("use_phase_filter", True):
            m15 = Rates.from_view(ctx.view.aux("15m"), sym, 21)
            if m15 is None or m15.n < 21:
                return None, "données M15 insuffisantes (filtre AMD)", extra
            rng = max(m15.h[1:21]) - min(m15.l[1:21])
            if rng < atr:
                return None, "phase d'accumulation (filtre AMD)", extra
        plan = None
        why = ""
        win = self._server_window(now) if self.pb("use_silver_bullet", True) else None
        if win is not None:
            plan, why = self._silver_bullet(ctx, sym, r, atr, price, spread, dirs, win)
        if plan is None and self.pb("use_ema_cross", True):
            plan, why2 = self._ema_cross(r, atr, price, dirs, now)
            why = why2 if not why else f"SB: {why} | EMA: {why2}"
        if plan is None:
            return None, why, extra
        extra.update({"ict_score": 0.0, "ict_htf_bias": 0.0, "ict_relaxed": 0.0})
        plan.update(market=True, armed_ts=now, strength=0.8)
        return plan, "", extra

    def _build_sltp(self, d: int, entry: float, atr: float, raw_sl: float, raw_tp: float) -> tuple[float, float]:
        """BuildSLTP: stop clamped to [0.8, 2.5] ATR, target at min(RR, max RR) or the nearer pool."""
        min_dist = max(self.spread(entry), atr * self.pf("min_sl_atr", 0.8))
        max_dist = max(min_dist, atr * self.pf("max_sl_atr", 2.5))
        dist = abs(entry - raw_sl) if raw_sl > 0 else atr * 1.5
        dist = max(min_dist, min(max_dist, dist))
        tp_dist = dist * min(self.pf("reward_ratio", 2.0), self.pf("max_tp_rr", 3.0))
        if raw_tp > 0 and abs(raw_tp - entry) > 0:
            tp_dist = max(min(tp_dist, abs(raw_tp - entry)), dist)
        return entry - d * dist, entry + d * tp_dist

    def _ema_cross(self, r: Rates, atr: float, price: float, dirs: tuple[int, ...], now: int):
        closes = r.c[1:][::-1]  # chronological closed bars
        fast, slow, filt = (_ema(closes, int(self.pf(k, v))) for k, v in (("ema_fast", 7), ("ema_slow", 21), ("ema_filter", 50)))
        if len(fast) < 2 or len(slow) < 2 or not filt:
            return None, "EMA indisponibles"
        up = fast[-2] <= slow[-2] and fast[-1] > slow[-1]
        down = fast[-2] >= slow[-2] and fast[-1] < slow[-1]
        if not up and not down:
            return None, "pas de croisement EMA"
        c1 = r.c[1]
        if self.pb("use_ema_filter", True) and ((up and c1 <= filt[-1]) or (down and c1 >= filt[-1])):
            return None, "croisement contre la EMA de tendance"
        d = BUY if up else SELL
        if d not in dirs:
            return None, f"sens {dir_str(d)} non autorisé"
        raw_sl = min(r.l[1], r.l[2]) - 0.25 * atr if d == BUY else max(r.h[1], r.h[2]) + 0.25 * atr
        sl, tp = self._build_sltp(d, price, atr, raw_sl, 0.0)
        rr = abs(tp - price) / abs(price - sl)
        return {"id": f"EMA_{r.t[1]}_{d}", "kind": "EMA", "dir": d, "entry": price, "sl": sl, "tp": tp, "rr": rr, "window_end": now, "window_key": None,
                "desc": f"Croisement EMA {int(self.pf('ema_fast', 7))}/{int(self.pf('ema_slow', 21))} {dir_str(d)} : SL {sl:.5g}, TP {tp:.5g} (RR {rr:.1f})"}, ""

    def _silver_bullet(self, ctx: StrategyContext, sym: str, r: Rates, atr: float, price: float, spread: float, dirs: tuple[int, ...], win: tuple[str, int]):
        d1 = Rates.from_view(ctx.view.aux("1d"), sym, 12)
        ltf = Rates.from_view(ctx.view.aux("5m"), sym, 20)
        if d1 is None or d1.n < 3 or ltf is None or ltf.n < 20:
            return None, "données D1/M5 insuffisantes"
        prev_h, prev_l = d1.h[1], d1.l[1]
        d = BUY if (price > prev_h or (price >= prev_l and price > (prev_h + prev_l) / 2)) else SELL
        if d not in dirs:
            return None, f"liquidité visée côté {dir_str(d)}, sens non autorisé"
        disp = ltf.h[1] - ltf.l[6] if d == BUY else ltf.h[6] - ltf.l[1]
        if disp < atr * self.pf("sb_displacement_atr", 1.2):
            return None, "displacement insuffisant"
        bars = int(self.pf("sb_retracement_bars", 3))
        sh, slo = max(ltf.h[1 : bars + 2]), min(ltf.l[1 : bars + 2])
        amp = sh - slo
        if amp <= 0:
            return None, "amplitude nulle"
        bid = price - spread / 2
        retr = (sh - bid) / amp if d == BUY else (bid - slo) / amp
        if retr > self.pf("sb_retracement_max", 0.618):
            return None, f"retracement {retr:.2f} trop profond"
        gap = self.pf("fvg_min_gap_points", 30) * self.point
        fvg = None
        for i in range(1, 7):  # v6 DetectFVG: first gap found among the last 6 bars, either side
            if ltf.l[i] - ltf.h[i + 2] > gap:
                fvg = (BUY, ltf.l[i], ltf.h[i + 2])
                break
            if ltf.l[i + 2] - ltf.h[i] > gap:
                fvg = (SELL, ltf.l[i + 2], ltf.h[i])
                break
        if fvg is None or fvg[0] != d:
            return None, "pas de FVG dans le sens de la liquidité"
        _, top, bottom = fvg
        raw_sl = min(bottom, slo) - 0.25 * atr if d == BUY else max(top, sh) + 0.25 * atr
        h4 = Rates.from_view(ctx.view.aux("4h"), sym, 21)
        week = [d1.h[i] if d == BUY else d1.l[i] for i in range(1, d1.n) if clk.ny_week_key(d1.t[i] + d1.step - 1) == clk.ny_week_key(ctx.ts)]
        cands = [prev_h if d == BUY else prev_l]
        if week:
            cands.append(max(week) if d == BUY else min(week))
        if h4 is not None and h4.n > 2:
            cands.append(max(h4.h[1:21]) if d == BUY else min(h4.l[1:21]))
        pool = [c for c in cands if (c > price if d == BUY else 0 < c < price)]
        raw_tp = (min(pool) if d == BUY else max(pool)) if pool else 0.0
        sl, tp = self._build_sltp(d, price, atr, raw_sl, raw_tp)
        rr = abs(tp - price) / abs(price - sl)
        key, end = win
        return {"id": f"SBv6_{ltf.t[1]}_{d}", "kind": "SBv6", "dir": d, "entry": price, "sl": sl, "tp": tp, "rr": rr, "window_end": end, "window_key": key,
                "desc": f"Silver Bullet v6 {dir_str(d)} : displacement {disp / atr:.1f} ATR, retracement {retr:.2f}, SL {sl:.5g}, TP {tp:.5g} (RR {rr:.1f})"}, ""


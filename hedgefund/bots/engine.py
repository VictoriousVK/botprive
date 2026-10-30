"""Live bot engine behind the web platform.

One shared stack (portfolio, risk engine, kill switch, execution, ledger) serves every running
bot, so global limits apply across all of them. Each bot gets its own decision pipeline and
runs when a new bar of its timeframe closes. Modes:

  simulation  no MT5 terminal: simulated prices, simulated fills (labelled everywhere)
  paper       MT5 prices, simulated fills: nothing is sent to the broker
  mt5         orders sent to the connected MT5 account. Demo accounts are allowed; a
              real-money account additionally needs HF_ALLOW_REAL_TRADING=1 on the server
              AND an explicit unlock in the UI (password + typed confirmation).

Each mode has its own ledger file, so simulated results never mix with broker results.
"""

from __future__ import annotations

import threading
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any

from hedgefund.backtest.engine import BacktestConfig, run_backtest
from hedgefund.bots.templates import TEMPLATES, build_spec, min_trade_notional, validate_bot
from hedgefund.config import FundConfig, Instrument
from hedgefund.core.clock import Clock, SystemClock
from hedgefund.core.ledger import Kind, Ledger
from hedgefund.core.timeutil import DAY_MS, MINUTE_MS, interval_ms, utc_iso
from hedgefund.data.quality import check_market_data
from hedgefund.data.series import MarketData
from hedgefund.execution.paper import PaperVenue
from hedgefund.jev.reference import ReferenceJev
from hedgefund.monitoring.alerts import AlertSink
from hedgefund.mt5.catalog import CATEGORY_LABELS, instrument_from_spec
from hedgefund.mt5.venue import MT5Venue
from hedgefund.ops.assembly import build_stack
from hedgefund.ops.runner import replay_books
from hedgefund.pipeline import DecisionPipeline, StrategyRuntime
from hedgefund.policy.engine import Action
from hedgefund.strategy.base import Strategy
from hedgefund.strategy.monitor import evaluate_invalidation, strategy_metrics

MODES = ("simulation", "paper", "mt5")
UNLIMITED_LIQUIDITY = 1e12  # retail CFD sizes: participation is not the binding constraint


class EngineError(RuntimeError):
    pass


@dataclass
class _BotRuntime:
    bot: dict[str, Any]
    pipeline: DecisionPipeline
    warmup: int
    message: str = "En attente de la prochaine bougie"
    halted_reason: str | None = None


class BotEngine:
    LOOP_S = 15.0
    NAV_EVERY_MS = 5 * MINUTE_MS

    def __init__(self, base_config: FundConfig, store: Any, feed: Any, clock: Clock | None = None, mt5_client: Any = None, data_dir: Path | None = None, allow_real_env: bool = False):
        self.base = base_config
        self.store = store
        self.feed = feed
        self.clock = clock or SystemClock()
        self.client = mt5_client
        if getattr(feed, "synthetic", False) and hasattr(feed, "clock"):
            feed.clock = self.clock  # simulated quotes follow the engine's time
        self.data_dir = Path(data_dir or base_config.var_dir)
        self.allow_real_env = allow_real_env
        self.lock = threading.RLock()
        self.instruments: dict[str, Instrument] = {}
        self.units_per_lot: dict[str, float] = dict(store.get_setting("units_per_lot", {}) or {})
        self.runtimes: dict[str, _BotRuntime] = {}
        self.stop_event = threading.Event()
        self.thread: threading.Thread | None = None
        self.last_loop_ms: int | None = None
        self.last_error: str | None = None
        self._last_nav_ms = 0
        self._last_invalidation_ms = 0
        self._kill_alerted = False
        self._status_cache: tuple[int, dict] | None = None
        mode = store.get_setting("mode") or ("simulation" if feed.synthetic else "paper")
        self.mode = "simulation" if feed.synthetic else (mode if mode in ("paper", "mt5") else "paper")
        self._build()
        for bot in store.list_bots():
            if bot.get("status") == "running":
                try:
                    self.start_bot(bot["id"], operator="system", resume=True)
                except Exception as e:  # noqa: BLE001
                    bot.update(status="error", last_error=f"reprise impossible: {e}")
                    store.save_bot(bot)

    # ---------------- construction ----------------
    def _build(self) -> None:
        self.ledger = Ledger(self.data_dir / f"platform_{self.mode}.db")
        capital = self.store.get_setting(f"capital_{self.mode}")
        if capital is None:
            capital = self._default_capital()
            self.store.set_setting(f"capital_{self.mode}", capital)
        self.cfg: FundConfig = replace(self.base, instruments=self.instruments, starting_nav=float(capital))
        if self.mode == "mt5":
            venue: Any = MT5Venue(self.client, self.clock, allow_real=self.real_trading_enabled(), units_per_lot=self.units_per_lot)
        else:
            venue = PaperVenue(self.instruments, self.clock)
        self.stack = build_stack(self.cfg, [], self.clock, self.ledger, venue, jev=ReferenceJev(), kill_switch_path=self.data_dir / "KILL_SWITCH", order_ttl_ms=15 * MINUTE_MS)
        replay_books(self.ledger, self.stack.portfolio)
        for sym in self.stack.portfolio.positions():
            self.ensure_instrument(sym)
        if isinstance(venue, PaperVenue):
            venue.restore_positions(self.stack.portfolio.positions())
        self.alerts = AlertSink.from_env(self.ledger, self.clock)

    def _default_capital(self) -> float:
        if self.mode == "mt5":
            eq = self.account_status().get("equity")
            if eq:
                return float(eq)
        return 100_000.0

    def real_trading_enabled(self) -> bool:
        return self.allow_real_env and bool(self.store.get_setting("real_trading_unlocked", False))

    def ensure_instrument(self, symbol: str) -> Instrument:
        if symbol not in self.instruments:
            spec = self.feed.spec(symbol)
            q = self.feed.quote(symbol)
            price = (q[0] + q[1]) / 2 if q else 0.0
            self.instruments[symbol] = instrument_from_spec(spec, price)
        return self.instruments[symbol]

    def _log(self, action: str, operator: str, **details: Any) -> None:
        self.ledger.append(Kind.OPERATOR, {"action": action, "operator": operator, **details}, ts=self.clock.now_ms())

    # ---------------- status ----------------
    def account_status(self) -> dict[str, Any]:
        now = self.clock.now_ms()
        if self._status_cache and now - self._status_cache[0] < 10_000:
            return self._status_cache[1]
        st = self.feed.status()
        self._status_cache = (now, st)
        return st

    # ---------------- bot control ----------------
    def start_bot(self, bot_id: str, operator: str, resume: bool = False) -> dict:
        with self.lock:
            bot = self.store.get_bot(bot_id)
            if bot is None:
                raise EngineError("bot introuvable")
            if bot_id in self.runtimes:
                return bot
            if self.stack.kill_switch.engaged:
                raise EngineError("arrêt d'urgence actif : réarmez-le avant de démarrer un bot")
            catalog = self.feed.specs()
            problems = validate_bot(bot, catalog)
            if problems:
                raise EngineError("; ".join(problems))
            if self.mode == "mt5":
                acc = self.account_status()
                if not acc.get("connected"):
                    raise EngineError(f"MT5 non connecté : {acc.get('error', '')}")
                if not acc.get("algo_trading_enabled", False):
                    raise EngineError("Activez le bouton « Algo Trading » dans MT5")
                if acc.get("account_type") == "real" and not self.real_trading_enabled():
                    raise EngineError("compte réel verrouillé : utilisez un compte démo ou déverrouillez explicitement le trading réel")
            prices = {}
            for s in bot["symbols"]:
                self.ensure_instrument(s)
                q = self.feed.quote(s)
                prices[s] = (q[0] + q[1]) / 2 if q else 0.0
            spec = build_spec(bot, catalog, prices)
            problems = spec.validate(set(self.instruments))
            if problems:
                raise EngineError("; ".join(problems))
            rt = StrategyRuntime.from_spec(spec)
            saved = self.store.get_setting(self._state_key(bot_id))
            if saved:
                rt.strategy.import_state(saved)
            pipe = DecisionPipeline([rt], self.stack.pipeline.jev, self.stack.policy, self.stack.portfolio, self.ledger, self.stack.calibration)
            self.runtimes[bot_id] = _BotRuntime(bot, pipe, rt.strategy.warmup_bars)
            bot.update(status="running", last_error=None)
            self.store.save_bot(bot)
            self._log("bot_resume" if resume else "bot_start", operator, bot_id=bot_id, bot=bot, spec_hash=spec.spec_hash)
            return bot

    def _state_key(self, bot_id: str) -> str:
        return f"strategy_state:{self.mode}:{bot_id}"

    def _save_state(self, bot_id: str, rt: "_BotRuntime") -> None:
        state = rt.pipeline.runtimes[0].strategy.export_state()
        if state is not None:
            self.store.set_setting(self._state_key(bot_id), state)

    def stop_bot(self, bot_id: str, operator: str, close_positions: bool = True) -> dict:
        with self.lock:
            bot = self.store.get_bot(bot_id)
            if bot is None:
                raise EngineError("bot introuvable")
            self.runtimes.pop(bot_id, None)
            if close_positions and self.stack.portfolio.book_positions(bot_id):
                self._refresh_marks(self.clock.now_ms())
                self.stack.execution.flatten_books([bot_id], f"stop by {operator}", self._liquidity())
            bot.update(status="stopped")
            self.store.save_bot(bot)
            self._log("bot_stop", operator, bot_id=bot_id, close_positions=close_positions)
            return bot

    def kill(self, operator: str, reason: str) -> None:
        with self.lock:
            self.stack.kill_switch.engage(reason, f"web:{operator}")
            self._refresh_marks(self.clock.now_ms())
            if self.stack.portfolio.positions():
                self.stack.execution.flatten_all(f"kill switch: {reason}", self._liquidity())
            self._log("kill_switch", operator, reason=reason)

    def reset_kill(self, operator: str, reason: str) -> None:
        with self.lock:
            self.stack.kill_switch.reset(operator, reason)
            self._kill_alerted = False
            self._log("kill_switch_reset", operator, reason=reason)

    def _assert_idle(self) -> None:
        if self.runtimes:
            raise EngineError("arrêtez d'abord tous les bots")
        if self.stack.portfolio.positions():
            raise EngineError("des positions sont ouvertes : fermez-les d'abord")

    def set_mode(self, mode: str, operator: str) -> None:
        with self.lock:
            if mode not in MODES:
                raise EngineError("mode inconnu")
            if self.feed.synthetic and mode != "simulation":
                raise EngineError("aucun terminal MT5 connecté : seul le mode simulation est disponible")
            if not self.feed.synthetic and mode == "simulation":
                raise EngineError("le mode simulation n'est disponible que sans terminal MT5")
            self._assert_idle()
            self._log("mode_change", operator, frm=self.mode, to=mode)
            self.mode = mode
            self.store.set_setting("mode", mode)
            self._build()
            self._log("mode_change", operator, frm=None, to=mode)

    def set_capital(self, capital: float, operator: str) -> None:
        with self.lock:
            if not 100 <= capital <= 1e9:
                raise EngineError("capital invalide")
            self._assert_idle()
            self.store.set_setting(f"capital_{self.mode}", float(capital))
            self._log("capital_change", operator, capital=capital)
            self._build()

    def set_real_trading(self, enabled: bool, operator: str) -> None:
        with self.lock:
            if enabled and not self.allow_real_env:
                raise EngineError("le serveur n'autorise pas le trading réel (HF_ALLOW_REAL_TRADING=1 requis)")
            self.store.set_setting("real_trading_unlocked", bool(enabled))
            if isinstance(self.stack.venue, MT5Venue):
                self.stack.venue.allow_real = self.real_trading_enabled()
            self._log("real_trading_unlock" if enabled else "real_trading_lock", operator)

    # ---------------- loop ----------------
    def start(self) -> None:
        if self.thread and self.thread.is_alive():
            return
        self.stop_event.clear()
        self.thread = threading.Thread(target=self._run, name="bot-engine", daemon=True)
        self.thread.start()

    def shutdown(self) -> None:
        self.stop_event.set()
        if self.thread:
            self.thread.join(timeout=30)

    def _run(self) -> None:
        backoff = self.LOOP_S
        while not self.stop_event.is_set():
            try:
                self.step()
                backoff = self.LOOP_S
            except Exception as e:  # noqa: BLE001 - the loop must survive; alert and back off
                self.last_error = f"{type(e).__name__}: {e}"
                self.alerts.alert("high", f"engine loop error: {self.last_error}")
                backoff = min(backoff * 2, 300.0)
            self.stop_event.wait(backoff)

    def _symbols(self) -> set[str]:
        syms = set(self.stack.portfolio.positions())
        for rt in self.runtimes.values():
            syms.update(rt.bot["symbols"])
        return syms

    def _liquidity(self) -> dict[str, float]:
        return {s: UNLIMITED_LIQUIDITY for s in self.instruments}

    def _refresh_marks(self, now: int) -> dict[str, float]:
        marks = {}
        for s in self._symbols():
            q = self.feed.quote(s)
            if q:
                marks[s] = (q[0] + q[1]) / 2
                if isinstance(self.stack.venue, PaperVenue):
                    self.stack.venue.set_market(s, marks[s], UNLIMITED_LIQUIDITY)
        self.stack.portfolio.mark(marks)
        return marks

    def step(self) -> None:
        with self.lock:
            st = self.stack
            now = self.clock.now_ms()
            marks = self._refresh_marks(now)
            if isinstance(st.venue, PaperVenue):
                st.venue.step()
            st.execution.sync()
            st.risk.update_nav(st.portfolio.nav(), now)
            traded = False
            if st.kill_switch.engaged:
                if not self._kill_alerted:
                    self.alerts.alert("critical", f"ARRÊT D'URGENCE: {st.kill_switch.reason}")
                    self._kill_alerted = True
                if st.portfolio.positions():
                    st.execution.flatten_all(f"kill switch: {st.kill_switch.reason}", self._liquidity())
                    traded = True
            else:
                self._kill_alerted = False
                for bot_id, rt in list(self.runtimes.items()):
                    try:
                        traded |= self._intrabar_exits(bot_id, rt, now)
                        traded |= self._step_bot(rt, now)
                    except Exception as e:  # noqa: BLE001 - one bot's failure must not stop the others
                        rt.message = f"Erreur : {type(e).__name__}: {e}"
                        self.alerts.alert("high", f"{bot_id}: {rt.message}")
            st.execution.expire_stale()
            if st.portfolio.positions() or self.mode == "mt5":
                recon = st.execution.reconcile()
                if not recon.ok:
                    self.alerts.alert("critical", f"positions internes ≠ broker : {recon.mismatches}")
            if now - self._last_invalidation_ms >= 60 * MINUTE_MS:
                self._check_invalidation(now)
                self._last_invalidation_ms = now
            if traded or now - self._last_nav_ms >= self.NAV_EVERY_MS:
                self._snapshot_nav(now, marks)
            if self.units_per_lot != self.store.get_setting("units_per_lot", {}):
                self.store.set_setting("units_per_lot", self.units_per_lot)
            self.last_loop_ms = now

    def _intrabar_exits(self, bot_id: str, rt: _BotRuntime, now: int) -> bool:
        """Between bar closes, let strategies with a stop/target (the ICT EAs) exit on live quotes."""
        strat = rt.pipeline.runtimes[0].strategy
        if type(strat).intrabar_exit is Strategy.intrabar_exit:
            return False
        book = self.stack.portfolio.book_positions(bot_id)
        if not book:
            return False
        traded = False
        for pkg in rt.pipeline.runtimes[0].spec.packages:
            sym = pkg.legs[0].symbol
            if sym not in book or not self.feed.market_open(sym, now):
                continue  # a closed market has no live price to act on
            q = self.feed.quote(sym)
            if not q:
                continue
            reason = strat.intrabar_exit(pkg, book, q[0], q[1], now)
            if not reason:
                continue
            for r in rt.pipeline.force_exit(bot_id, pkg.key, reason, now):
                if r.action.trades:
                    self.stack.execution.execute(r, self._liquidity())
                    traded = True
            rt.message = f"{utc_iso(now)[11:16]} UTC : sortie — {reason}"
            self._save_state(bot_id, rt)
        return traded

    def _market_data(self, syms: list[str], timeframe: str, count: int, now: int, aux: dict[str, int], extra_ms: int = 0) -> MarketData:
        data = self.feed.market_data(syms, timeframe, count, now)
        for tf, n in aux.items():
            data.aux[tf] = self.feed.market_data(syms, tf, n + extra_ms // interval_ms(tf) + 2, now)
        return data

    def _opposite_holder(self, bot_id: str, r: Any) -> str | None:
        """Anti-hedge (as in the EAs): no new position against another bot's open position."""
        for sym, target in r.leg_targets.items():
            for sid, book in self.stack.portfolio.books.items():
                p = book.positions.get(sym)
                if sid != bot_id and p is not None and abs(p.qty) > 1e-12 and p.qty * target < 0:
                    return sid
        return None

    def _step_bot(self, rt: _BotRuntime, now: int) -> bool:
        bot = rt.bot
        syms = bot["symbols"]
        if not all(self.feed.market_open(s, now) for s in syms):
            rt.message = "Marché fermé"
            return False
        probe = self.feed.market_data(syms, bot["timeframe"], 3, now).timeline(syms)
        if not probe or (bot.get("last_bar_ts") and probe[-1] <= bot["last_bar_ts"]):
            if not probe:
                rt.message = "Pas de données"
            return False
        strat = rt.pipeline.runtimes[0].strategy
        data = self._market_data(syms, bot["timeframe"], rt.warmup + 20, now, strat.aux_timeframes)
        timeline = data.timeline(syms)
        if not timeline:
            rt.message = "Pas de données"
            return False
        t = timeline[-1]
        if bot.get("last_bar_ts") and t <= bot["last_bar_ts"]:
            return False
        if len(timeline) < rt.warmup:
            rt.message = f"Historique insuffisant ({len(timeline)}/{rt.warmup} bougies)"
            return False
        quality = check_market_data(data, now, syms, max_staleness_bars=2, max_gap_bars=10**6)
        halted = {bot["id"]} if rt.halted_reason else set()
        results = rt.pipeline.decide(data.view(t), t, quality.blocked_symbols, halted)
        # Persist the strategy's plan before sending orders: after a crash, a partial exit is
        # skipped rather than repeated.
        self._save_state(bot["id"], rt)
        traded = False
        acts, why = [], strat.note
        for r in results:
            if r.action is Action.ENTER and (other := self._opposite_holder(bot["id"], r)):
                name = (self.store.get_bot(other) or {}).get("name", other)
                acts.append("entrée bloquée")
                why = f"anti-couverture : « {name} » tient la position inverse"
                continue
            acts.append(r.action.value)
            if r.action is Action.NO_TRADE and r.reasons:
                why = f"{r.reasons[0]} ({strat.note})" if strat.note else r.reasons[0]
            elif not strat.note and r.reasons:
                why = r.reasons[0]
            if r.action.trades:
                self.stack.execution.execute(r, self._liquidity())
                traded = True
        acts = ", ".join(acts) or "aucun signal"
        rt.message = f"Bougie du {utc_iso(t)[:16].replace('T', ' ')} UTC : {acts}" + (f" — {why}" if why else "")
        bot["last_bar_ts"] = t
        self.store.save_bot(bot)
        return traded

    def _check_invalidation(self, now: int) -> None:
        for bot_id, rt in self.runtimes.items():
            if rt.halted_reason:
                continue
            spec = rt.pipeline.runtimes[0].spec
            breaches = evaluate_invalidation(spec, strategy_metrics(self.ledger, bot_id, now))
            if breaches:
                b = breaches[0]
                rt.halted_reason = f"{b['metric']} {b['value']:.4g} {b['op']} {b['threshold']}"
                rt.bot["last_error"] = f"suspendu (nouvelles entrées bloquées) : {rt.halted_reason}"
                self.store.save_bot(rt.bot)
                self.alerts.alert("high", f"{bot_id} suspendu : {rt.halted_reason}")

    def _snapshot_nav(self, now: int, marks: dict[str, float]) -> None:
        pf = self.stack.portfolio
        acc = self.account_status() if self.mode == "mt5" else {}
        self.ledger.append(
            Kind.NAV,
            {
                "nav": pf.nav(),
                "bar_ts": now,
                "hwm": self.stack.risk.hwm,
                "drawdown": self.stack.risk.drawdown(pf.nav()),
                "books": {sid: pf.book_equity(sid) for sid in pf.books},
                "positions": pf.positions(),
                "marks": marks,
                "exposures": pf.exposures(),
                "broker_equity": acc.get("equity"),
            },
            ts=now,
        )
        self._last_nav_ms = now

    # ---------------- read models for the API ----------------
    def snapshot(self) -> dict[str, Any]:
        with self.lock:
            st = self.stack
            pf = st.portfolio
            nav = pf.nav()
            capital = self.cfg.starting_nav
            exp = pf.exposures()
            day_start = st.risk.day_start_nav or nav
            positions = []
            for sid, book in pf.books.items():
                for sym, p in book.positions.items():
                    if abs(p.qty) < 1e-12:
                        continue
                    mark = pf.marks.get(sym, p.avg_price)
                    upl = self.units_per_lot.get(sym) or (self.feed.spec(sym).multiplier if sym in self.instruments else 1.0)
                    positions.append({
                        "bot_id": sid, "symbol": sym, "side": "achat" if p.qty > 0 else "vente", "lots": round(abs(p.qty) / upl, 4),
                        "avg_price": p.avg_price, "mark": mark, "notional": abs(p.qty) * mark, "unrealized": p.qty * (mark - p.avg_price),
                    })
            bots = []
            for bot in self.store.list_bots():
                rt = self.runtimes.get(bot["id"])
                b = pf.books.get(bot["id"])
                bots.append({
                    **bot,
                    "strategy_label": TEMPLATES[bot["strategy"]].label if bot["strategy"] in TEMPLATES else bot["strategy"],
                    "running": rt is not None,
                    "message": rt.message if rt else ("Arrêté" if bot.get("status") != "error" else bot.get("last_error")),
                    "halted_reason": rt.halted_reason if rt else None,
                    "pnl": pf.book_equity(bot["id"]),
                    "fees": b.fees if b else 0.0,
                    "closed_trades": len(b.realized_events) if b else 0,
                    "win_rate": (sum(1 for *_, x in b.realized_events if x > 0) / len(b.realized_events)) if b and b.realized_events else None,
                })
            return {
                "mode": self.mode,
                "synthetic": self.feed.synthetic,
                "feed": self.feed.name,
                "account": self.account_status(),
                "real_trading": {"server_allows": self.allow_real_env, "unlocked": self.real_trading_enabled()},
                "engine": {"alive": bool(self.thread and self.thread.is_alive()), "last_loop": utc_iso(self.last_loop_ms) if self.last_loop_ms else None, "last_error": self.last_error},
                "kill_switch": {"engaged": st.kill_switch.engaged, "reason": st.kill_switch.reason},
                "capital": capital,
                "nav": nav,
                "pnl_total": nav - capital,
                "pnl_today": nav - day_start,
                "drawdown": st.risk.drawdown(nav),
                "gross_exposure": exp["gross"] / nav if nav else 0.0,
                "net_exposure": exp["net"] / nav if nav else 0.0,
                "positions": positions,
                "bots": bots,
                "limits": vars(self.cfg.risk),
            }

    def equity_series(self, days: int = 30, max_points: int = 400) -> list[dict]:
        since = self.clock.now_ms() - days * DAY_MS
        pts = [(e.ts, e.payload["nav"], e.payload.get("drawdown", 0.0), e.payload.get("broker_equity")) for e in self.ledger.query(kind=Kind.NAV, since_ts=since)]
        if len(pts) > max_points:
            step = len(pts) / max_points
            pts = [pts[int(i * step)] for i in range(max_points - 1)] + [pts[-1]]
        return [{"t": t, "nav": n, "drawdown": d, "broker_equity": b} for t, n, d, b in pts]

    def recent(self, kind: str, limit: int = 50) -> list[dict]:
        return [{"t": e.ts, "kind": e.kind, **e.payload} for e in self.ledger.query(kind=kind, newest_first=True, limit=limit)]

    def symbols(self, query: str = "", category: str = "") -> list[dict]:
        q = query.strip().lower()
        out = []
        for spec in self.feed.specs().values():
            if category and spec.category != category:
                continue
            if q and q not in spec.name.lower() and q not in spec.description.lower():
                continue
            out.append({"name": spec.name, "description": spec.description, "category": spec.category, "category_label": CATEGORY_LABELS[spec.category]})
        return sorted(out, key=lambda s: (s["category"], s["name"]))[:300]

    def symbol_detail(self, symbol: str) -> dict:
        spec = self.feed.spec(symbol)
        q = self.feed.quote(symbol)
        price = (q[0] + q[1]) / 2 if q else 0.0
        return {**spec.to_dict(), "price": price, "min_trade_notional": min_trade_notional(spec, price), "spread_bps": spec.half_spread_bps(price) * 2}

    def backtest(self, bot: dict, bars: int | None = None) -> dict:
        catalog = self.feed.specs()
        problems = validate_bot(bot, catalog)
        if problems:
            raise EngineError("; ".join(problems))
        prices = {}
        instruments = {}
        for s in bot["symbols"]:
            spec = self.feed.spec(s)
            q = self.feed.quote(s)
            prices[s] = (q[0] + q[1]) / 2 if q else 0.0
            instruments[s] = instrument_from_spec(spec, prices[s])
        spec = build_spec(bot, catalog, prices)
        strat = StrategyRuntime.from_spec(spec).strategy
        warmup = strat.warmup_bars
        bars = bars or TEMPLATES[bot["strategy"]].backtest_bars
        span = (warmup + bars) * interval_ms(bot["timeframe"])
        data = self._market_data(bot["symbols"], bot["timeframe"], warmup + bars, self.clock.now_ms(), strat.aux_timeframes, extra_ms=span)
        cfg = replace(self.base, instruments=instruments, starting_nav=self.cfg.starting_nav)
        timeline = data.timeline(bot["symbols"])
        if len(timeline) < warmup + 50:
            raise EngineError(f"historique insuffisant : {len(timeline)} bougies pour {warmup} de préchauffage")
        # Views still see the warm-up history; metrics only cover the tradable period.
        res = run_backtest(data, [spec], cfg, BacktestConfig(start_ts=timeline[warmup]))
        eq = res.equity
        step = max(1, len(eq) // 300)
        m = res.strategy_metrics[bot["id"]]
        return {
            "synthetic": data.synthetic,
            "bars": len(eq),
            "from": utc_iso(eq[0][0]) if eq else None,
            "to": utc_iso(eq[-1][0]) if eq else None,
            "metrics": {k: res.metrics[k] for k in ("total_return", "cagr", "sharpe", "sortino", "max_drawdown", "psr")},
            "pnl": m["pnl"],
            "fees": m["fees"],
            "closed_trades": m["closing_fills"],
            "win_rate": m["hit_rate"],
            "orders": res.trades["orders"],
            "rejected_orders": res.trades["rejected_orders"],
            "equity": [{"t": t, "nav": v} for t, v in eq[::step]],
            "min_trade_notional": {s: min_trade_notional(self.feed.spec(s), prices[s]) for s in bot["symbols"]},
        }

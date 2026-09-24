"""The two MT5 EAs ported as platform strategies (ICT Ultimate Pro v6 and v6.20)."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

import pytest

from hedgefund.bots.engine import BotEngine
from hedgefund.bots.simfeed import SimulatedFeed
from hedgefund.bots.store import PlatformStore
from hedgefund.bots.templates import TEMPLATES, build_spec, validate_bot
from hedgefund.config import load_config
from hedgefund.core.clock import SimClock
from hedgefund.core.types import Bar, Direction, Leg, Signal
from hedgefund.data.series import BarSeries, MarketData
from hedgefund.jev.reference import ReferenceJev
from hedgefund.jev.schema import JevState, compile_jev_schema
from hedgefund.mt5.data import TIMEFRAMES as MT5_TIMEFRAMES
from hedgefund.policy.engine import Action, PolicyEngine
from hedgefund.portfolio.book import PositionInfo
from hedgefund.strategy.base import StrategyContext, load_strategy
from hedgefund.strategy.library import ict_clock as clk
from hedgefund.strategy.library.ict import IctProV620
from hedgefund.strategy.library.ict_core import (
    BUY,
    LiquidityMap,
    Market,
    MBParams,
    Rates,
    ReferenceLevels,
    SBParams,
    fvgs_in_leg,
    is_swing_high,
    is_swing_low,
    macro_breaker,
    silver_bullet,
)

M1, M5 = 60_000, 300_000
NOW = 1_790_000_000_000


def utc(y, mo, d, h, mi=0) -> int:
    return int(datetime(y, mo, d, h, mi, tzinfo=timezone.utc).timestamp() * 1000)


def bot(strategy="ict_pro", tf="1m", **kw) -> dict:
    return {"id": "bot_1c7a0001", "name": "Or ICT", "strategy": strategy, "symbols": ["XAUUSD"], "timeframe": tf, "direction": "both",
            "risk_per_trade_pct": 0.5, "max_position_pct": 20, "params": {}, "status": "stopped", **kw}


def spec_for(b: dict):
    feed = SimulatedFeed()
    return build_spec(b, feed.specs(), {"XAUUSD": 2400.0})


# ---------------- New York clock ----------------
def test_ny_clock_follows_us_and_eu_daylight_saving():
    assert not clk.is_us_dst(utc(2026, 3, 8, 6, 59)) and clk.is_us_dst(utc(2026, 3, 8, 7))
    assert clk.is_us_dst(utc(2026, 11, 1, 5, 59)) and not clk.is_us_dst(utc(2026, 11, 1, 6))
    assert not clk.is_eu_dst(utc(2026, 3, 29, 0, 59)) and clk.is_eu_dst(utc(2026, 3, 29, 1))
    # 10:00 New York is 14:00 UTC in summer and 15:00 UTC in winter.
    assert clk.ny_minute_of_day(utc(2026, 7, 15, 14)) == 600 == clk.ny_minute_of_day(utc(2026, 1, 15, 15))
    assert clk.ny_day_of_week(utc(2026, 9, 24, 12)) == 4  # Thursday
    name, start, end = clk.window_at(utc(2026, 7, 15, 14, 30), {"ny_am"})
    assert name == "ny_am" and (start, end) == (utc(2026, 7, 15, 14), utc(2026, 7, 15, 15))
    assert clk.window_at(utc(2026, 7, 15, 14, 30), {"london", "ny_pm"}) is None
    assert clk.macro_at(utc(2026, 7, 15, 13, 25)).id == 920
    assert clk.macro_recent(utc(2026, 7, 15, 13, 45), 25).id == 920
    assert clk.server_hour(utc(2026, 7, 15, 10)) == 13 and clk.server_hour(utc(2026, 1, 15, 10)) == 12


# ---------------- structure primitives ----------------
def rates(rows: list[tuple[float, float, float, float]], step=M5, t0=NOW) -> Rates:
    """Chronological (o, h, l, c) rows -> MQL5 series order through a real MarketView."""
    bars = [Bar(t0 + (i + 1) * step, *row, 100) for i, row in enumerate(rows)]
    data = MarketData(step, {"X": BarSeries("X", bars)})
    return Rates.from_view(data.view(bars[-1].ts), "X", 1000)


def test_series_order_swings_fvg_and_atr():
    rows = [(10, 11, 9, 10)] * 20 + [(10, 10.5, 9.5, 10), (10, 12, 9.8, 11.8), (11.8, 13, 11.5, 12.8), (12.8, 13.2, 12.4, 13)]
    r = rates(rows)
    assert r.c[1] == 13 and r.c[0] == 13 and r.t[0] == NOW + len(rows) * M5  # placeholder forming bar
    assert r.atr(1) > 0
    f = fvgs_in_leg(BUY, r, 1, 4, 0.1)
    assert [(x.bottom, x.top) for x in f] == [(12, 12.4), (10.5, 11.5)]  # newest first; f[-1] is the first FVG of the leg
    peaks = rates([(1, 2, 0.5, 1), (1, 3, 0.5, 1), (1, 5, 0.5, 1), (1, 3, 0.5, 1), (1, 2, 0.5, 1), (1, 2, 0.5, 1)])
    assert is_swing_high(peaks, 4, 2) and not is_swing_low(peaks, 4, 2)


# ---------------- Silver Bullet (M5) ----------------
def sb_bars(pullback_low: float = 2398.2) -> list[Bar]:
    """Wed 2026-07-15 (EDT): London low, NY range, sweep at 09:50 NY, MSS at 10:00, FVG, retrace."""
    out, t = [], utc(2026, 7, 15, 6)  # 02:00 NY
    k = 0
    while t < utc(2026, 7, 15, 13, 50):
        ny = clk.ny_minute_of_day(t)
        if ny == 480:
            o, h, l, c = 2396.5, 2397.0, 2395.0, 2396.2  # 08:00 swing low
        elif ny == 560:
            o, h, l, c = 2398.5, 2399.5, 2398.2, 2398.8  # 09:20 swing high (MSS level)
        else:
            base = 2397.5 + (0.6 if 540 <= ny < 580 else 0.0) + (0.2 if k % 3 == 0 else -0.1 if k % 3 == 1 else 0.0)
            o, c = base - 0.1, base + 0.1
            h, l = c + 0.4, o - 0.4
        out.append((t, o, h, l, c))
        t += M5
        k += 1
    out += [(t, 2397.0, 2397.2, 2393.5, 2395.6), (t + M5, 2395.6, 2396.4, 2395.3, 2396.2), (t + 2 * M5, 2396.2, 2400.8, 2396.0, 2400.5),
            (t + 3 * M5, 2400.5, 2402.5, 2398.4, 2402.0), (t + 4 * M5, 2402.0, 2402.2, pullback_low, max(pullback_low + 0.1, 2398.3))]
    return [Bar(ts + M5, o, h, l, c, 100) for ts, o, h, l, c in out]


def sb_market(bars: list[Bar], spread: float = 0.2):
    data = MarketData(M5, {"XAUUSD": BarSeries("XAUUSD", bars)})
    now = bars[-1].ts
    ltf = Rates.from_view(data.view(now), "XAUUSD", 400)
    atr = ltf.atr(1)
    liq = LiquidityMap()
    liq.build(now, ltf, None, None, atr, (20, 40, 60), 2, 0.10, 0.01)
    ref = ReferenceLevels()
    ref.build(now, ltf, None, None, None)
    ref.push_to(liq)
    price = ltf.c[1]
    return ltf, atr, Market(now, price + spread / 2, price - spread / 2, spread, liq, ref, 0, 30.0), now


def test_silver_bullet_sweep_mss_fvg_entry():
    ltf, atr, mk, now = sb_market(sb_bars())
    _, ws, we = clk.window_at(now, {"ny_am"})
    s, why = silver_bullet(ltf, mk, "ny_am", ws, we, atr, SBParams(), (BUY, -1))
    assert s is not None, why
    assert s.kind == "SB" and s.dir == BUY and s.market_entry
    assert s.sweep.extreme == 2393.5 and s.sl < 2393.5  # stop behind the sweep extreme + buffer
    lo, hi = s.details["fvg"]
    assert lo <= s.entry <= hi + 0.2 and s.rr >= 2.0 and s.tp > s.entry
    assert s.score >= 3
    # Only short setups allowed: nothing.
    assert silver_bullet(ltf, mk, "ny_am", ws, we, atr, SBParams(), (-1,))[0] is None


def test_silver_bullet_price_above_fvg_arms_a_limit_entry():
    bars = sb_bars(pullback_low=2399.6)  # pullback has not reached the FVG yet (top 2398.4)
    ltf, atr, mk, now = sb_market(bars)
    _, ws, we = clk.window_at(now, {"ny_am"})
    s, why = silver_bullet(ltf, mk, "ny_am", ws, we, atr, SBParams(min_retrace=0.0), (BUY,))
    assert s is not None, why
    assert not s.market_entry and s.entry == pytest.approx(2398.4) and s.invalid_level == pytest.approx(2396.4)


# ---------------- Macro Breaker (M1) ----------------
def mb_bars() -> list[Bar]:
    special = {
        590: (2401.0, 2401.1, 2400.0, 2400.4),  # 09:50 swing low 2400
        605: (2402.4, 2403.0, 2402.0, 2402.2),  # 10:05 swing high, down-close breaker candle
        615: (2401.2, 2401.3, 2399.2, 2400.6),  # 10:15 stop hunt under 2400
        616: (2400.6, 2401.9, 2400.5, 2401.8),
        617: (2401.8, 2403.6, 2401.7, 2403.5),  # body close above the breaker body, new high
        618: (2403.5, 2404.2, 2403.1, 2403.9),
        619: (2403.9, 2404.0, 2403.2, 2403.3),
        620: (2403.3, 2403.4, 2402.7, 2402.8),  # 10:20 retest of the breaker
    }
    out, t = [], utc(2026, 7, 15, 12)
    while (ny := clk.ny_minute_of_day(t)) <= 620:
        if ny in special:
            o, h, l, c = special[ny]
        elif ny < 590:
            o = c = 2401.5
            h, l = 2401.9, 2401.1
        elif ny < 605:
            o = 2401.2 + (ny - 590) * 0.08
            c = o + 0.05
            h, l = c + 0.2, o - 0.2
        else:
            o = 2402.1 - (ny - 605) * 0.1
            c = o - 0.08
            h, l = o + 0.15, c - 0.15
        out.append(Bar(t + M1, o, h, l, c, 100))
        t += M1
    return out


def test_macro_breaker_stop_hunt_breaker_retest():
    bars = mb_bars()
    data = MarketData(M1, {"XAUUSD": BarSeries("XAUUSD", bars)})
    now = bars[-1].ts
    m1 = Rates.from_view(data.view(now), "XAUUSD", 420)
    atr = m1.atr(1)
    liq = LiquidityMap()
    liq.merge_tol = atr * 0.05
    liq.add_swings(m1, 3, 12, "M1")
    price = m1.c[1]
    mk = Market(now, price + 0.05, price - 0.05, 0.1, liq, ReferenceLevels(), 0, 30.0)
    macro = clk.macro_at(now)
    assert macro.id == 1020
    ms, me = clk.macro_range_utc(now, macro)
    s, why = macro_breaker(m1, mk, macro, ms, me, atr, atr * 2, MBParams(), (BUY, -1))
    assert s is not None, why
    assert s.kind == "MB" and s.dir == BUY and s.macro_id == 1020 and s.unicorn
    assert s.details["breaker"] == (2402.0, 2403.0) and s.sl < 2402.0 and s.rr >= 2.0
    assert s.score >= MBParams().min_score


# ---------------- trade management (EA position manager) ----------------
class Scripted(IctProV620):
    """ICT Pro management with a fixed plan, fixed trailing ATR and no swing trailing."""

    plan: dict | None = None

    def plan_entry(self, ctx, sym, dirs):
        return (dict(self.plan) if self.plan else None), "pas de setup", {}

    def trail_context(self, ctx, sym):
        return 0.5, None

    def context_features(self, ctx, sym):
        return {}


def ctx_at(rows: list[tuple[int, float, float, float, float]], book: dict | None = None) -> StrategyContext:
    bars = [Bar(t, o, h, l, c, 100) for t, o, h, l, c in rows]
    data = MarketData(M1, {"XAUUSD": BarSeries("XAUUSD", bars)})
    return StrategyContext(data.view(bars[-1].ts), bars[-1].ts, book or {})


def test_break_even_partial_trailing_and_stop():
    spec = spec_for(bot(params={"partial_pct": 40, "partial_at_r": 2.0, "trailing_start_r": 2.0, "trailing_atr_mult": 1.0, "time_stop_min": 0}))
    s = Scripted(spec)
    pkg = spec.packages[0]
    t0 = utc(2026, 7, 15, 14, 5)
    s.plan = {"id": "SB_x", "kind": "SB", "dir": BUY, "entry": 100.0, "sl": 99.0, "tp": 104.0, "rr": 4.0, "market": True, "invalid": 99.5,
              "window_end": t0 + 55 * M1, "window_key": "SB_1", "armed_ts": t0, "desc": "test", "strength": 0.9}
    rows = [(t0 - i * M1, 100, 100.2, 99.8, 100) for i in range(30, 0, -1)] + [(t0, 100, 100.1, 99.9, 100.0)]
    d, stop, thesis, _ = s.evaluate(ctx_at(rows), pkg)[:4]
    assert d is Direction.LONG and stop == pytest.approx(0.01)  # 1 point stop on a 100 entry
    book = {"XAUUSD": PositionInfo(qty=10, notional=1000, avg_price=100.0, opened_ts=t0)}
    rows.append((t0 + M1, 100.0, 101.2, 99.95, 101.0))  # +1.2R: break-even
    res = s.evaluate(ctx_at(rows, book), pkg)
    assert res[0] is Direction.LONG and len(res) == 4 and s.st["trade"]["be_done"] and s.st["trade"]["sl"] > 100.0
    assert s.st["consumed"] == ["SB_x"] and s.st["day"][1] == 1 and s.st["windows"]["SB_1"] == 1
    rows.append((t0 + 2 * M1, 101.0, 102.3, 100.9, 102.1))  # +2.3R: one partial, trailing starts
    res = s.evaluate(ctx_at(rows, book), pkg)
    assert res[0] is Direction.LONG and res[4] == pytest.approx(0.6)
    assert s.st["trade"]["sl"] == pytest.approx(102.3 - 0.5)
    rows.append((t0 + 3 * M1, 102.1, 102.4, 101.95, 102.2))  # no second partial
    assert len(s.evaluate(ctx_at(rows, book), pkg)) == 4
    # State survives a restart and keeps managing the same trade.
    s2 = Scripted(spec)
    s2.import_state(__import__("json").loads(__import__("json").dumps(s.export_state())))
    assert s2.intrabar_exit(pkg, book, 101.7, 101.9, t0 + 4 * M1) is not None  # live bid under the trailed stop
    rows.append((t0 + 4 * M1, 102.2, 102.3, 101.5, 101.6))
    d, _, thesis, _ = s.evaluate(ctx_at(rows, book), pkg)[:4]
    assert d is Direction.FLAT and "stop touché" in thesis
    rows.append((t0 + 5 * M1, 101.6, 101.7, 101.4, 101.5))
    assert s.evaluate(ctx_at(rows, {}), pkg)[0] is None and s.st["trade"] is None  # flat: setup consumed, no re-entry


def test_target_and_time_stop():
    spec = spec_for(bot(params={"time_stop_min": 10, "time_stop_min_r": 0.3, "be_at_r": 0, "partial_pct": 0, "trailing_start_r": 0}))
    s = Scripted(spec)
    pkg = spec.packages[0]
    t0 = utc(2026, 7, 15, 14, 5)
    s.plan = {"id": "MB_y", "kind": "MB", "dir": -1, "entry": 100.0, "sl": 101.0, "tp": 97.0, "rr": 3.0, "market": True, "invalid": 100.5,
              "window_end": t0, "window_key": "MB_1", "armed_ts": t0, "desc": "test", "strength": 0.9}
    rows = [(t0 - i * M1, 100, 100.2, 99.8, 100) for i in range(30, -1, -1)]
    assert s.evaluate(ctx_at(rows), pkg)[0] is Direction.SHORT
    book = {"XAUUSD": PositionInfo(qty=-10, notional=-1000, avg_price=100.0, opened_ts=t0)}
    rows += [(t0 + i * M1, 100, 100.3, 99.7, 100.0) for i in range(1, 11)]
    d, _, thesis, _ = s.evaluate(ctx_at(rows, book), pkg)[:4]
    assert d is Direction.FLAT and "time stop" in thesis
    s2 = Scripted(spec)
    s2.plan = s.plan
    s2.evaluate(ctx_at(rows[:31]), pkg)
    rows2 = rows[:31] + [(t0 + M1, 100, 100.2, 96.9, 97.2)]
    d, _, thesis, _ = s2.evaluate(ctx_at(rows2, book), pkg)[:4]
    assert d is Direction.FLAT and "objectif" in thesis


def test_limit_entry_waits_for_price_then_enters_or_expires():
    spec = spec_for(bot())
    s = Scripted(spec)
    pkg = spec.packages[0]
    t0 = utc(2026, 7, 15, 14, 5)
    s.plan = {"id": "SB_z", "kind": "SB", "dir": BUY, "entry": 99.0, "sl": 98.0, "tp": 103.0, "rr": 4.0, "market": False, "invalid": 98.5,
              "window_end": t0 + 10 * M1, "window_key": "SB_2", "armed_ts": t0, "desc": "limite", "strength": 0.9, "expiry_min": 5}
    rows = [(t0 - i * M1, 100, 100.2, 99.8, 100) for i in range(30, -1, -1)]
    assert s.evaluate(ctx_at(rows), pkg)[0] is None and s.st["pending"]["entry"] == 99.0
    s.plan = None
    rows.append((t0 + M1, 100, 100.1, 99.5, 99.6))  # not reached yet
    assert s.evaluate(ctx_at(rows), pkg)[0] is None and s.st["pending"]
    rows.append((t0 + 2 * M1, 99.6, 99.7, 98.9, 99.2))  # trades through 99.0: enter at market
    d, stop, thesis, _ = s.evaluate(ctx_at(rows), pkg)[:4]
    assert d is Direction.LONG and "limite touchée" in thesis and stop == pytest.approx((99.2 - 98.0) / 99.2)
    assert s.st["pending"] is None and s.st["consumed"] == ["SB_z"]


def test_pending_invalidation_by_close_beyond_zone():
    spec = spec_for(bot())
    s = Scripted(spec)
    pkg = spec.packages[0]
    t0 = utc(2026, 7, 15, 14, 5)
    s.plan = {"id": "SB_v", "kind": "SB", "dir": BUY, "entry": 99.0, "sl": 98.0, "tp": 103.0, "rr": 4.0, "market": False, "invalid": 98.5,
              "window_end": t0 + 10 * M1, "window_key": "SB_3", "armed_ts": t0, "desc": "limite", "strength": 0.9, "expiry_min": 5}
    rows = [(t0 - i * M1, 100, 100.2, 99.8, 100) for i in range(30, -1, -1)]
    s.evaluate(ctx_at(rows), pkg)
    s.plan = None
    rows.append((t0 + M1, 100, 100.1, 98.2, 98.3))  # closes under the FVG bottom: cancelled
    assert s.evaluate(ctx_at(rows), pkg)[0] is None and s.st["pending"] is None
    s.plan = {"id": "SB_u", "kind": "SB", "dir": BUY, "entry": 97.0, "sl": 96.0, "tp": 103.0, "rr": 4.0, "market": False, "invalid": 96.5,
              "window_end": t0 + 2 * M1, "window_key": "SB_4", "armed_ts": t0 + M1, "desc": "limite", "strength": 0.9, "expiry_min": 1}
    s.evaluate(ctx_at(rows), pkg)
    s.plan = None
    rows += [(t0 + i * M1, 98.3, 98.5, 98.1, 98.3) for i in range(2, 5)]
    assert s.evaluate(ctx_at(rows), pkg)[0] is None and s.st["pending"] is None  # expired


# ---------------- policy: partial exits and no scale-in ----------------
def test_policy_partial_reduce_and_no_scale_in():
    spec = spec_for(bot())
    assert spec.risk.allow_scale_in is False
    legs = (Leg("XAUUSD", 1.0),)
    pol = PolicyEngine(load_config().risk)
    sig = Signal(spec.id, "XAUUSD", legs, Direction.LONG, 0.002, NOW, "partiel", {}, reduce_to=0.6)
    r = pol.evaluate(sig, None, spec, {"XAUUSD": 10_000.0}, 100_000.0)
    assert r.action is Action.REDUCE and r.leg_targets["XAUUSD"] == pytest.approx(6_000.0)  # no Jev needed
    schema = compile_jev_schema(spec)
    daily = {"rv_ratio": 1.0, "dd_6d": -0.01, "ret_1d": 0.002, "volume_ratio": 1.0, "range_pct": 0.012, "bar_ret_z": 0.3}
    state = JevState(spec.id, "XAUUSD", "XAUUSD", NOW, "ict", Direction.LONG, {**daily, "ict_dir": 1.0, "ict_setup": 0.9, "ict_atr_ratio": 1.0, "ict_htf_bias": 1.0}, {})
    dec = ReferenceJev().decide(state, schema)
    assert dec.regime.value == "trending" and dec.direction is Direction.LONG and dec.confidence >= spec.jev.min_confidence
    hold = pol.evaluate(Signal(spec.id, "XAUUSD", legs, Direction.LONG, 0.002, NOW, "tenir", {}), dec, spec, {"XAUUSD": 6_000.0}, 100_000.0)
    assert hold.action is Action.HOLD  # below target size, but never adds to an ICT trade
    spike = ReferenceJev().decide(JevState(spec.id, "XAUUSD", "XAUUSD", NOW, "ict", Direction.LONG, {**daily, "ict_dir": 1.0, "ict_setup": 0.9, "ict_atr_ratio": 4.0}, {}), schema)
    assert spike.regime.value == "high_vol"  # the EA's ATR spike filter


# ---------------- templates, feeds, engine ----------------
def test_templates_restrict_timeframes_and_validate_flags():
    feed = SimulatedFeed()
    assert validate_bot(bot(), feed.specs()) == []
    assert any("unité de temps" in p for p in validate_bot(bot(tf="15m"), feed.specs()))
    assert validate_bot(bot("ict_v6", "15m"), feed.specs()) == []
    assert any("0 ou 1" in p for p in validate_bot(bot(params={"enable_sb": 0.5}), feed.specs()))
    assert TEMPLATES["ict_pro"].public()["params"]["enable_sb"]["kind"] == "bool"
    spec = spec_for(bot())
    assert spec.params["point"] == feed.spec("XAUUSD").point and spec.timeframe == "1m" and spec.jev.profile == "ict"
    assert {"1m", "5m"} <= set(MT5_TIMEFRAMES)
    for key in ("ict_pro", "ict_v6"):
        st = load_strategy(spec_for(bot(key, TEMPLATES[key].default_timeframe)))
        assert set(st.aux_timeframes) <= set(MT5_TIMEFRAMES)


def test_simulated_timeframes_are_one_consistent_market():
    feed = SimulatedFeed(SimClock(NOW + 123_456))
    now = NOW + 123_456
    m1 = feed.market_data(["XAUUSD"], "1m", 60, now).bars["XAUUSD"]
    m5 = feed.market_data(["XAUUSD"], "5m", 20, now).bars["XAUUSD"]
    h1 = feed.market_data(["XAUUSD"], "1h", 5, now).bars["XAUUSD"]
    assert m1.ts[-1] <= now < m1.ts[-1] + M1 and m5.ts[-1] <= now
    idx = [i for i in range(len(m1)) if m5.ts[-1] - M5 < m1.ts[i] <= m5.ts[-1]]
    assert len(idx) == 5
    assert max(m1.high[i] for i in idx) == m5.high[-1] and min(m1.low[i] for i in idx) == m5.low[-1]
    assert m1.open[idx[0]] == m5.open[-1] and m1.close[idx[-1]] == m5.close[-1]
    j = [i for i in range(len(m5)) if h1.ts[-1] - 3_600_000 < m5.ts[i] <= h1.ts[-1]]
    assert len(j) == 12 and max(m5.high[i] for i in j) == h1.high[-1]
    bid, ask = SimulatedFeed(SimClock(now)).quote("XAUUSD")  # a fresh instance (restart) quotes the same market
    assert bid < m1.close[-1] < ask


def _engine(tmp: Path) -> BotEngine:
    return BotEngine(load_config(), PlatformStore(tmp / "p.db"), SimulatedFeed(), clock=SimClock(NOW - 2 * 3_600_000), data_dir=tmp)


def test_engine_backtests_both_eas(tmp_path):
    eng = _engine(tmp_path)
    for key in ("ict_pro", "ict_v6"):
        res = eng.backtest(bot(key, TEMPLATES[key].default_timeframe), bars=2500)
        assert res["synthetic"] and res["bars"] > 2000 and res["orders"] > 0


def test_engine_runs_restores_state_and_blocks_hedges(tmp_path):
    eng = _engine(tmp_path)
    a, b = bot(id="bot_1c7a000a", name="SB+MB"), bot("ict_v6", "5m", id="bot_1c7a000b", name="v6")
    for x in (a, b):
        eng.store.save_bot(x)
        eng.start_bot(x["id"], "vic")
    held = None
    for _ in range(6 * 60 * 4):
        eng.clock.advance(15_000)
        eng.step()
        held = eng.stack.portfolio.book_positions(a["id"])
        strat = eng.runtimes[a["id"]].pipeline.runtimes[0].strategy
        if held and strat.st["proposal"]:
            # Filled but not yet adopted (next bar close): the live stop already protects it.
            p = strat.st["proposal"]
            far = p["sl"] - 5.0 * p["dir"]  # beyond the stop
            reason = strat.intrabar_exit(eng.runtimes[a["id"]].pipeline.runtimes[0].spec.packages[0], held, far, far, eng.clock.now_ms())
            assert reason and "stop touché" in reason
            strat.st["proposal"]["exit_reason"] = None
        if held and strat.st["trade"]:
            break
    assert held, "the ICT bot never traded on the simulated market"
    trade = strat.st["trade"]
    assert trade and eng.store.get_setting(f"strategy_state:simulation:{a['id']}")["trade"]["id"] == trade["id"]
    # Restart: same trade plan, same position.
    eng2 = BotEngine(load_config(), eng.store, SimulatedFeed(), clock=SimClock(eng.clock.now_ms()), data_dir=tmp_path)
    strat2 = eng2.runtimes[a["id"]].pipeline.runtimes[0].strategy
    assert strat2.st["trade"]["id"] == trade["id"] and eng2.stack.portfolio.book_positions(a["id"])
    # A live quote through the stop closes the position between bar closes.
    sign = 1 if list(eng2.stack.portfolio.book_positions(a["id"]).values())[0].qty > 0 else -1
    bid, ask = eng2.feed.quote("XAUUSD")
    strat2.st["trade"]["sl"] = bid + 1.0 if sign > 0 else ask - 1.0
    eng2.step()  # same bar: only the live-quote check runs
    assert not eng2.stack.portfolio.book_positions(a["id"]) and "stop touché" in eng2.runtimes[a["id"]].message
    # Anti-hedge: another bot cannot open against an open position.
    from hedgefund.policy.engine import PolicyResult
    fake = PolicyResult(Action.ENTER, b["id"], "XAUUSD", Direction.SHORT, {"XAUUSD": -1000.0}, NOW, None, None)
    eng2.stack.portfolio.book(a["id"]).pos("XAUUSD").apply(1.0, 2400.0, NOW)
    assert eng2._opposite_holder(b["id"], fake) == a["id"]

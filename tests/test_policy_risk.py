import pytest

from hedgefund.core.types import Direction, Leg, Regime, RiskState, Signal
from hedgefund.jev.schema import JevDecision
from hedgefund.policy.engine import Action, PolicyEngine
from hedgefund.risk.engine import OrderRequest, RiskEngine
from hedgefund.risk.kill_switch import KillSwitch

NAV = 1_000_000.0


def decision(**over):
    base = dict(
        decision_id="d1", strategy_id="tsmom_majors", package="BTC-trend", ts=0, regime=Regime.TRENDING, direction=Direction.LONG,
        setup_quality=3, liquidity_quality=3, toxic_flow=0, expected_edge=80.0, risk_state=RiskState.SAFE, should_trade=True,
        confidence=0.85, p_trade=0.8, probabilities={}, model_version="ref", latency_ms=1.0, state_hash="h", schema_hash="h",
    )
    return JevDecision(**(base | over))


def signal(direction=Direction.LONG, stop=0.08, legs=(Leg("BTCUSDT-PERP", 1.0),)):
    return Signal("tsmom_majors", "BTC-trend", legs, direction, stop, 0, "test")


@pytest.fixture
def policy(cfg):
    return PolicyEngine(cfg.risk)


# ---------------- policy ----------------
def test_exit_never_waits_for_jev(policy, specs):
    r = policy.evaluate(signal(Direction.FLAT), None, specs["tsmom_majors"], {"BTCUSDT-PERP": 50_000}, NAV)
    assert r.action is Action.EXIT and r.leg_targets == {"BTCUSDT-PERP": 0.0}


def test_jev_unavailable_blocks_new_risk_but_holds(policy, specs):
    spec = specs["tsmom_majors"]
    assert policy.evaluate(signal(), None, spec, {}, NAV).action is Action.NO_TRADE
    held = policy.evaluate(signal(), None, spec, {"BTCUSDT-PERP": 50_000}, NAV)
    assert held.action is Action.HOLD and held.leg_targets == {"BTCUSDT-PERP": 50_000}


def test_entry_sizing_is_deterministic(policy, specs, cfg):
    spec = specs["tsmom_majors"]
    r = policy.evaluate(signal(stop=0.08), decision(), spec, {}, NAV)
    assert r.action is Action.ENTER
    expected = min(NAV * min(spec.risk.risk_per_trade_pct_nav, cfg.risk.max_risk_per_trade_pct_nav) / 0.08, NAV * spec.risk.max_package_notional_pct_nav)
    assert r.leg_targets["BTCUSDT-PERP"] == pytest.approx(expected)
    weaker = policy.evaluate(signal(stop=0.08), decision(setup_quality=2, confidence=0.72), spec, {}, NAV)
    assert weaker.leg_targets["BTCUSDT-PERP"] == pytest.approx(expected * 0.6 * 0.75)


def test_short_package_signs_and_hedged_legs(policy, specs):
    spec = specs["ethbtc_rv"]
    legs = (Leg("ETHUSDT-PERP", 1.0), Leg("BTCUSDT-PERP", -1.0))
    sig = Signal("ethbtc_rv", "ETHBTC", legs, Direction.SHORT, 0.08, 0, "t")
    r = policy.evaluate(sig, decision(strategy_id="ethbtc_rv", direction=Direction.SHORT, regime=Regime.MEAN_REVERTING), spec, {}, NAV)
    assert r.action is Action.ENTER
    assert r.leg_targets["ETHUSDT-PERP"] < 0 < r.leg_targets["BTCUSDT-PERP"]
    assert r.leg_targets["ETHUSDT-PERP"] == pytest.approx(-r.leg_targets["BTCUSDT-PERP"])


def test_low_confidence_escalates_and_blocks(policy, specs):
    r = policy.evaluate(signal(), decision(confidence=0.55), specs["tsmom_majors"], {}, NAV)
    assert r.action is Action.NO_TRADE and r.escalate and "0.55" in r.escalation_reason
    # Between the 0.60 floor and the spec's stricter minimum: blocked, but not an escalation.
    r2 = policy.evaluate(signal(), decision(confidence=0.61), specs["tsmom_majors"], {}, NAV)
    assert r2.action is Action.NO_TRADE and not r2.escalate


def test_crisis_escalates_and_exits(policy, specs):
    r = policy.evaluate(signal(), decision(regime=Regime.CRISIS), specs["tsmom_majors"], {"BTCUSDT-PERP": 80_000}, NAV)
    assert r.action is Action.EXIT and r.escalate
    r2 = policy.evaluate(signal(), decision(regime=Regime.CRISIS), specs["tsmom_majors"], {}, NAV)
    assert r2.action is Action.NO_TRADE and r2.escalate


def test_risk_state_flat_and_reduce(policy, specs):
    spec = specs["tsmom_majors"]
    assert policy.evaluate(signal(), decision(risk_state=RiskState.FLAT), spec, {"BTCUSDT-PERP": 100_000}, NAV).action is Action.EXIT
    r = policy.evaluate(signal(), decision(risk_state=RiskState.REDUCE), spec, {"BTCUSDT-PERP": 125_000}, NAV)
    assert r.action is Action.REDUCE and 0 < r.leg_targets["BTCUSDT-PERP"] < 125_000
    # Already reduced -> no repeated halving.
    again = policy.evaluate(signal(), decision(risk_state=RiskState.REDUCE), spec, r.leg_targets, NAV)
    assert again.action is Action.HOLD
    assert policy.evaluate(signal(), decision(risk_state=RiskState.REDUCE), spec, {}, NAV).action is Action.NO_TRADE


@pytest.mark.parametrize(
    "over, reason",
    [
        ({"direction": Direction.SHORT}, "jev direction"),
        ({"should_trade": False, "p_trade": 0.3}, "should_trade"),
        ({"setup_quality": 1}, "setup_quality"),
        ({"liquidity_quality": 1}, "liquidity_quality"),
        ({"toxic_flow": 3}, "toxic_flow"),
        ({"expected_edge": 40.0}, "expected_edge"),
        ({"regime": Regime.MEAN_REVERTING}, "regime"),
    ],
)
def test_every_entry_gate(policy, specs, over, reason):
    r = policy.evaluate(signal(), decision(**over), specs["tsmom_majors"], {}, NAV)
    assert r.action is Action.NO_TRADE and any(reason in x for x in r.reasons)


def test_disallowed_direction(policy, specs):
    spec = specs["liq_cascade_reversion"]  # long only
    r = policy.evaluate(signal(Direction.SHORT), decision(direction=Direction.SHORT, regime=Regime.MEAN_REVERTING), spec, {}, NAV)
    assert r.action is Action.NO_TRADE and any("not allowed" in x for x in r.reasons)


def test_hysteresis_prevents_churn(policy, specs):
    spec = specs["tsmom_majors"]
    full = policy.evaluate(signal(), decision(), spec, {}, NAV).leg_targets["BTCUSDT-PERP"]
    # Held at full size; quality multiplier drops -> no downsize churn.
    assert policy.evaluate(signal(), decision(setup_quality=2), spec, {"BTCUSDT-PERP": full}, NAV).action is Action.HOLD
    # Held at a small size; quality is high -> grow.
    assert policy.evaluate(signal(), decision(), spec, {"BTCUSDT-PERP": full * 0.4}, NAV).action is Action.ADJUST
    # NAV fell: position is now far above the risk budget -> shrink even though Jev is happy.
    assert policy.evaluate(signal(), decision(), spec, {"BTCUSDT-PERP": full * 2}, NAV).action is Action.ADJUST


# ---------------- risk ----------------
@pytest.fixture
def risk(cfg, ledger, clock):
    ks = KillSwitch(None, ledger, clock)
    return RiskEngine(cfg.risk, cfg.instruments, ks, ledger, clock)


MARKS = {"BTCUSDT": 50_000.0, "BTCUSDT-PERP": 50_000.0, "ETHUSDT": 3_000.0, "ETHUSDT-PERP": 3_000.0}
LIQ = {s: 1e9 for s in MARKS}


def req(sym, qty, strat="s"):
    return OrderRequest(strat, "p", sym, qty, MARKS[sym], "d")


def test_risk_approves_within_limits(risk):
    v = risk.check([req("BTCUSDT-PERP", 2.0)], {}, MARKS, NAV, LIQ)
    assert v.approved and v.scale == 1.0


def test_risk_clips_to_position_cap(risk, cfg):
    v = risk.check([req("BTCUSDT-PERP", 10.0)], {}, MARKS, NAV, LIQ)  # 50% NAV requested
    assert v.approved and v.requests[0].qty * 50_000 == pytest.approx(cfg.risk.max_position_pct_nav * NAV, rel=1e-6)
    assert any("clipped" in x for x in v.violations)


def test_risk_rejects_tiny_residual(risk):
    pos = {"BTCUSDT-PERP": 4.95}  # 24.75% NAV already
    v = risk.check([req("BTCUSDT-PERP", 2.0)], pos, MARKS, NAV, LIQ)
    assert not v.approved


def test_spot_cannot_go_short(risk):
    v = risk.check([req("BTCUSDT", -1.0)], {}, MARKS, NAV, LIQ)
    assert not v.approved and "cannot go short" in v.violations[0]


def test_package_scaled_uniformly(risk):
    reqs = [req("ETHUSDT-PERP", 150.0), req("BTCUSDT-PERP", -9.0)]  # 45% NAV per leg
    v = risk.check(reqs, {}, MARKS, NAV, LIQ)
    assert v.approved and 0 < v.scale < 1
    assert v.requests[0].qty / 150.0 == pytest.approx(v.requests[1].qty / -9.0)


def test_participation_and_liquidity(risk):
    v = risk.check([req("BTCUSDT-PERP", 2.0)], {}, MARKS, NAV, {"BTCUSDT-PERP": 1e6})
    assert not v.approved or v.requests[0].qty < 2.0
    v2 = risk.check([req("BTCUSDT-PERP", 1.0)], {}, MARKS, NAV, {})
    assert not v2.approved and "no liquidity" in v2.violations[0]


def test_kill_switch_blocks_risk_but_allows_exits(risk):
    risk.kill_switch.engage("test", "test")
    assert not risk.check([req("BTCUSDT-PERP", 1.0)], {}, MARKS, NAV, LIQ).approved
    v = risk.check([req("BTCUSDT-PERP", -1.0)], {"BTCUSDT-PERP": 1.0}, MARKS, NAV, LIQ)
    assert v.approved and v.reduce_only
    # Flipping through zero is not "reducing".
    assert not risk.check([req("BTCUSDT-PERP", -2.0)], {"BTCUSDT-PERP": 1.0}, MARKS, NAV, LIQ).approved


def test_drawdown_triggers_reduce_only_then_kill(risk, cfg):
    risk.update_nav(NAV, 0)
    risk.update_nav(NAV * (1 - cfg.risk.drawdown_reduce_only_pct - 0.001), 1)
    assert risk.reduce_only_mode and not risk.kill_switch.engaged
    assert not risk.check([req("BTCUSDT-PERP", 1.0)], {}, MARKS, NAV, LIQ).approved
    risk.update_nav(NAV * (1 - cfg.risk.max_drawdown_pct - 0.001), 2)
    assert risk.kill_switch.engaged


def test_daily_loss_halt_lifts_next_day(risk, cfg):
    day = 86_400_000
    risk.update_nav(NAV, 10 * day)
    risk.update_nav(NAV * (1 - cfg.risk.max_daily_loss_pct - 0.001), 10 * day + 1000)
    assert risk.new_risk_block() and "daily loss" in risk.new_risk_block()
    risk.update_nav(NAV * (1 - cfg.risk.max_daily_loss_pct - 0.001), 11 * day + 1000)
    assert risk.new_risk_block() is None


def test_order_rate_limit(risk, cfg):
    for _ in range(cfg.risk.max_orders_per_minute):
        assert risk.check([req("ETHUSDT-PERP", 1.0)], {}, MARKS, NAV, LIQ).approved
    v = risk.check([req("ETHUSDT-PERP", 1.0)], {}, MARKS, NAV, LIQ)
    assert not v.approved and "rate" in v.violations[0]


def test_breached_limit_blocks_only_worsening_orders(risk):
    pos = {"BTCUSDT-PERP": 6.0}  # 30% NAV: over the 25% cap after a price move
    assert not risk.check([req("BTCUSDT-PERP", 0.5)], pos, MARKS, NAV, LIQ).approved
    assert risk.check([req("ETHUSDT-PERP", 10.0)], pos, MARKS, NAV, LIQ).approved


def test_kill_switch_reset_requires_operator(risk, ledger):
    risk.kill_switch.engage("x", "y")
    with pytest.raises(PermissionError):
        risk.kill_switch.reset("", "because")
    risk.kill_switch.reset("vic", "reviewed incident")
    assert not risk.kill_switch.engaged
    assert ledger.query(kind="approval")[-1].payload["operator"] == "vic"


def test_kill_switch_flag_file(tmp_path, ledger, clock):
    ks = KillSwitch(tmp_path / "KILL", ledger, clock)
    assert not ks.engaged
    (tmp_path / "KILL").write_text("")
    assert ks.engaged

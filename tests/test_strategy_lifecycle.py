from dataclasses import replace

import pytest

from hedgefund.core.types import Direction
from hedgefund.data.series import BarSeries, MarketData, Series
from hedgefund.portfolio.book import PositionInfo
from hedgefund.strategy.base import StrategyContext, load_strategy
from hedgefund.strategy.lifecycle import Approval, current_stage, evaluate_gate, transition
from hedgefund.strategy.monitor import evaluate_invalidation
from hedgefund.strategy.spec import Stage, spec_from_dict, spec_to_dict


def truncate(data: MarketData, t: int) -> MarketData:
    def cut(s: Series) -> Series:
        i = s.upto(t)
        return Series(s.ts[:i], s.values[:i])

    return MarketData(
        data.interval_ms,
        {k: BarSeries(k, [b.bar(i) for i in range(b.upto(t))]) for k, b in data.bars.items()},
        {k: cut(v) for k, v in data.funding.items()},
        {k: cut(v) for k, v in data.open_interest.items()},
        {k: cut(v) for k, v in data.macro.items()},
    )


@pytest.mark.parametrize("sid", ["carry_btc_basis", "tsmom_majors", "liq_cascade_reversion", "stablecoin_liquidity_tilt", "ethbtc_rv"])
def test_no_lookahead(sid, specs, data):
    """Signals at t must be identical whether or not data after t exists."""
    strat = load_strategy(specs[sid])
    ts = data.bars["BTCUSDT"].ts
    for i in (1250, 1400, 1590):
        t = ts[i]
        legs = specs[sid].packages[0].legs
        held = {l.symbol: PositionInfo(l.weight, l.weight * 1000.0, 100.0, ts[i - 20]) for l in legs}
        for book in ({}, held):
            full = strat.signals(StrategyContext(data.view(t), t, book))
            cut = strat.signals(StrategyContext(truncate(data, t).view(t), t, book))
            assert [(s.package, s.direction, round(s.stop_distance_pct, 12), s.thesis) for s in full] == [
                (s.package, s.direction, round(s.stop_distance_pct, 12), s.thesis) for s in cut
            ]


def test_strategies_emit_valid_signals(specs, data):
    seen = {sid: set() for sid in specs}
    for sid, spec in specs.items():
        strat = load_strategy(spec)
        for t in data.bars["BTCUSDT"].ts[1210::5]:
            for sig in strat.signals(StrategyContext(data.view(t), t, {})):
                assert sig.direction in spec.allowed_directions  # flat book: entries only
                assert sig.stop_distance_pct > 0
                seen[sid].add(sig.direction)
    assert seen["tsmom_majors"] or seen["ethbtc_rv"] or seen["carry_btc_basis"]


def test_exit_signal_when_data_missing_while_holding(specs, data):
    strat = load_strategy(specs["tsmom_majors"])
    t = data.bars["BTCUSDT"].ts[100]  # far below warmup
    held = {"BTCUSDT-PERP": PositionInfo(1.0, 1000.0, 100.0, t)}
    sigs = strat.signals(StrategyContext(data.view(t), t, held))
    assert sigs and sigs[0].direction is Direction.FLAT


def test_spec_roundtrip_and_validation(specs, cfg):
    for spec in specs.values():
        assert spec_from_dict(spec_to_dict(spec)) == spec
        assert spec.validate(set(cfg.instruments)) == []
    bad = replace(specs["tsmom_majors"], jev=replace(specs["tsmom_majors"].jev, min_confidence=0.5), invalidation=())
    problems = bad.validate(set(cfg.instruments))
    assert any("floor" in p for p in problems) and any("invalidation" in p for p in problems)


# ---------------- lifecycle ----------------
REAL = {"synthetic": False}


def test_promotion_one_step_with_evidence(ledger, specs):
    spec = replace(specs["ethbtc_rv"], stage=Stage.HYPOTHESIS)
    r = transition(spec, Stage.SIGNAL, {}, ledger, 1)
    assert not r.ok and "one step" in r.failures[0]
    r = transition(spec, Stage.DATA, {"hypothesis.testable_prediction": "ratio reverts", "hypothesis.spec_valid": True}, ledger, 2)
    assert r.ok and current_stage(spec, ledger) is Stage.DATA


def test_synthetic_evidence_never_promotes(ledger, specs):
    spec = replace(specs["ethbtc_rv"], stage=Stage.DATA)
    ev = {"data.quality_ok": True, "data.history_days": 800, "data.point_in_time": True, "synthetic": True}
    r = transition(spec, Stage.SIGNAL, ev, ledger, 1)
    assert not r.ok and any("real market data" in f for f in r.failures)
    assert transition(spec, Stage.SIGNAL, ev | REAL, ledger, 2).ok


def test_live_requires_named_human(ledger, specs):
    spec = replace(specs["ethbtc_rv"], stage=Stage.SHADOW_MODE)
    ev = {"shadow.days": 10, "shadow.decision_parity": 0.99, "shadow.fill_deviation_bps": 3, "shadow.venue_adapter_verified": True} | REAL
    r = transition(spec, Stage.LIVE, ev, ledger, 1)
    assert not r.ok and "human" in r.failures[-1]
    r = transition(spec, Stage.LIVE, ev, ledger, 2, approval=Approval("vic", "reviewed shadow results", 2))
    assert r.ok and ledger.query(kind="stage_transition")[-1].payload["approval"]["operator"] == "vic"


def test_demotion_always_allowed_and_retired_is_final(ledger, specs):
    spec = replace(specs["ethbtc_rv"], stage=Stage.LIVE)
    assert not transition(spec, Stage.PAPER_TRADE, {}, ledger, 1).ok  # reason required
    assert transition(spec, Stage.PAPER_TRADE, {}, ledger, 2, reason="sharpe decay").ok
    assert transition(spec, Stage.RETIRED, {}, ledger, 3, reason="edge gone").ok
    assert not transition(spec, Stage.SHADOW_MODE, {}, ledger, 4).ok


def test_backtest_gate_thresholds():
    good = {"backtest.trades": 40, "backtest.sharpe": 0.9, "backtest.psr": 0.95, "backtest.dsr": 0.7, "backtest.max_drawdown": 0.1, "backtest.fold_positive_frac": 0.75} | REAL
    assert evaluate_gate(Stage.COST_MODEL, good) == []
    assert evaluate_gate(Stage.COST_MODEL, good | {"backtest.dsr": 0.2})


def test_invalidation_rules(specs):
    spec = specs["carry_btc_basis"]
    breaches = evaluate_invalidation(spec, {"strategy_drawdown": (0.06, 100), "avg_slippage_bps": (9.0, 5), "rolling_sharpe_90d": (-1.0, 600)})
    got = {b["metric"]: b["action"] for b in breaches}
    assert got == {"strategy_drawdown": "halt", "rolling_sharpe_90d": "demote"}  # slippage: too few observations

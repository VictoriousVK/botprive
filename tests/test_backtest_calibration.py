import math
import random

import pytest

from hedgefund.backtest.engine import BacktestConfig, run_backtest
from hedgefund.backtest.metrics import deflated_sharpe, max_drawdown, probabilistic_sharpe, sharpe
from hedgefund.backtest.stress import inject_crash, run_scenarios
from hedgefund.calibration.metrics import brier, brier_skill_score, ece
from hedgefund.calibration.recalibrate import CalibrationBundle, PlattMap, RecalibratedJev, fit_platt, propose_bundle
from hedgefund.calibration.tracker import Prediction, package_forward_return
from hedgefund.jev.reference import ReferenceJev
from hedgefund.jev.schema import JevState, compile_jev_schema
from hedgefund.core.types import Direction


@pytest.fixture(scope="module")
def bt_result(cfg, specs, data):
    return run_backtest(data, list(specs.values()), cfg, BacktestConfig(record_ledger=True))


def test_backtest_runs_full_stack(bt_result):
    r = bt_result
    assert r.synthetic and len(r.equity) > 1000
    assert r.trades["filled_orders"] > 0 and r.decisions > 0
    assert r.ledger.verify_chain() == (True, None)
    kinds = {e.kind for e in r.ledger.query()}
    assert {"jev_decision", "policy", "risk_verdict", "order", "fill", "calibration_outcome"} <= kinds
    assert not r.risk_events  # modest sizes on this path should never hit the kill switch


def test_backtest_is_deterministic(cfg, specs, data, bt_result):
    again = run_backtest(data, list(specs.values()), cfg, BacktestConfig())
    assert again.equity == bt_result.equity


def test_costs_hurt(cfg, specs, data):
    s = [specs["ethbtc_rv"]]
    base = run_backtest(data, s, cfg, BacktestConfig())
    costly = run_backtest(data, s, cfg, BacktestConfig(fee_mult=5.0, slippage_mult=5.0))
    assert costly.trades["fees"] > base.trades["fees"]
    assert costly.equity[-1][1] < base.equity[-1][1]


def test_crash_injection_and_scenarios(cfg, specs, data):
    crashed = inject_crash(data, at_frac=0.9, drop=0.3)
    s = data.bars["BTCUSDT"]
    k = int(len(s) * 0.9)
    assert crashed.bars["BTCUSDT"].close[k + 5] == pytest.approx(s.close[k + 5] * 0.7)
    out = run_scenarios(data, [specs["liq_cascade_reversion"]], cfg)
    assert set(out) == {"base", "fees_2x", "slippage_3x", "delay_2", "crash_30pct"}


def test_sharpe_family():
    rng = random.Random(1)
    good = [0.001 + rng.gauss(0, 0.01) for _ in range(2000)]
    noise = [rng.gauss(0, 0.01) for _ in range(2000)]
    assert sharpe(good, 365) > sharpe(noise, 365)
    assert probabilistic_sharpe(good) > 0.95
    assert deflated_sharpe(good, 1000) < probabilistic_sharpe(good)  # multiple testing costs
    assert max_drawdown([100, 120, 90, 130]) == pytest.approx(0.25)


def test_calibration_metrics():
    assert brier([1.0, 0.0], [1, 0]) == 0.0 and brier([0.5, 0.5], [1, 0]) == 0.25
    assert brier_skill_score([0.9, 0.1, 0.9, 0.1], [1, 0, 1, 0]) > 0.9
    assert ece([0.9] * 10, [1] * 9 + [0]) == pytest.approx(0.0, abs=1e-9)


def test_forward_return_includes_funding(data):
    t0 = data.bars["BTCUSDT"].ts[1000]
    t1 = data.bars["BTCUSDT"].ts[1042]
    carry = package_forward_return(data, (("BTCUSDT", 1.0), ("BTCUSDT-PERP", -1.0)), 1, t0, t1)
    fund = sum(v for _, v in data.funding["BTCUSDT-PERP"].between(t0, t1))
    spot = data.bars["BTCUSDT"].close[1042] / data.bars["BTCUSDT"].close[1000] - 1
    perp = data.bars["BTCUSDT-PERP"].close[1042] / data.bars["BTCUSDT-PERP"].close[1000] - 1
    assert carry == pytest.approx(spot - perp + fund)


def test_platt_recovers_overconfidence():
    rng = random.Random(3)
    probs, outs = [], []
    for _ in range(3000):
        true_p = rng.uniform(0.2, 0.8)
        z = math.log(true_p / (1 - true_p)) * 3  # model is 3x overconfident in logit space
        probs.append(1 / (1 + math.exp(-z)))
        outs.append(int(rng.random() < true_p))
    m = fit_platt(probs, outs, l2=1.0)
    assert m.a == pytest.approx(1 / 3, abs=0.07)
    assert brier([m.apply(p) for p in probs], outs) < brier(probs, outs)


def _preds(key_strategy, q, probs, outs):
    return [(Prediction(f"d{i}", key_strategy, "ref", q, "yes", p, i, 10, (("X", 1.0),), 1, 0.0), o) for i, (p, o) in enumerate(zip(probs, outs))]


def test_bundle_rejects_no_skill_and_accepts_improvement():
    rng = random.Random(5)
    over = [(0.95 if rng.random() < 0.5 else 0.05) for _ in range(400)]
    outs = [int(rng.random() < (0.7 if p > 0.5 else 0.3)) for p in over]
    inverted = [1 - p for p in over]
    rows = _preds("s1", "should_trade", over, outs) + _preds("s2", "should_trade", inverted, outs)
    b = propose_bundle(rows, "ref")
    assert "s1|should_trade" in b.maps
    assert b.report["s2|should_trade"]["accepted"] is False and "skill" in b.report["s2|should_trade"]["why"]


def test_recalibrated_engine_versioning(tmp_path, specs):
    bundle = CalibrationBundle({"tsmom_majors|should_trade": PlattMap(0.5, -0.2)}, "reference-jev-1.0", {})
    path = bundle.save(tmp_path)
    loaded = CalibrationBundle.load(path)
    eng = RecalibratedJev(ReferenceJev(), loaded)
    assert eng.model_version == f"reference-jev-1.0+cal-{bundle.version}"
    st = JevState("tsmom_majors", "BTC-trend", "BTCUSDT-PERP", 0, "directional", Direction.LONG, {"rv_ratio": 1.0, "er_10d": 0.5, "daily_vol": 0.03, "mom_20d": 0.2, "mom_60d": 0.4})
    raw = ReferenceJev().decide(st, compile_jev_schema(specs["tsmom_majors"]))
    cal = eng.decide(st, compile_jev_schema(specs["tsmom_majors"]))
    assert cal.p_trade == pytest.approx(PlattMap(0.5, -0.2).apply(raw.p_trade), abs=1e-6)
    path.write_text(path.read_text().replace("-0.2", "-0.3"))
    with pytest.raises(ValueError, match="integrity"):
        CalibrationBundle.load(path)

import pytest
import requests

from hedgefund.core.types import Direction, Regime, RiskState
from hedgefund.data.features import standard_features
from hedgefund.jev.engine import BudgetedJev, JevUnavailable, ShadowJev
from hedgefund.jev.reference import ReferenceJev
from hedgefund.jev.remote import JevConfigError, ProvisionalCodec, RemoteJev
from hedgefund.jev.schema import (
    EDGE_LEVELS,
    QUALITY_LEVELS,
    TOXIC_LEVELS,
    JevDecision,
    JevSchemaError,
    JevState,
    compile_jev_schema,
    decision_from_answers,
)


def _state(features, profile="directional", cand=Direction.LONG):
    return JevState("s", "pkg", "BTCUSDT-PERP", 1_700_000_000_000, profile, cand, features)


def _answers(**over):
    a = {
        "regime": {"probabilities": {"trending": 0.7, "mean_reverting": 0.2, "high_vol": 0.1}},
        "direction": {"probabilities": {"long": 0.8, "short": 0.1, "flat": 0.1}},
        "setup_quality": {"probabilities": {QUALITY_LEVELS[3]: 0.9, QUALITY_LEVELS[2]: 0.1}},
        "liquidity_quality": {"probabilities": {QUALITY_LEVELS[2]: 1.0}},
        "toxic_flow": {"probabilities": {TOXIC_LEVELS[0]: 0.8, TOXIC_LEVELS[1]: 0.2}},
        "expected_edge": {"probabilities": {EDGE_LEVELS[3]: 0.5, EDGE_LEVELS[4]: 0.5}},
        "risk_state": {"probabilities": {"safe": 0.9, "reduce": 0.1}},
        "should_trade": {"p_yes": 0.75},
    }
    a.update(over)
    return a


def test_decision_from_answers_maps_types(specs):
    schema = compile_jev_schema(specs["tsmom_majors"])
    d = decision_from_answers("d1", _state({}), schema, _answers(), "m", 5.0)
    assert d.regime is Regime.TRENDING and d.direction is Direction.LONG
    assert (d.setup_quality, d.liquidity_quality, d.toxic_flow) == (3, 2, 0)
    assert d.expected_edge == pytest.approx(87.5)  # probability-weighted position of levels 75/100
    assert d.should_trade and d.p_trade == 0.75
    assert d.confidence == pytest.approx(0.7)  # min of gating confidences (regime 0.7)
    assert d.state_hash and d.schema_hash == schema.schema_hash


@pytest.mark.parametrize(
    "bad",
    [
        {"regime": {"probabilities": {"sideways": 1.0}}},
        {"should_trade": {"p_yes": 1.3}},
        {"direction": {"probabilities": {}}},
    ],
)
def test_invalid_answers_rejected(specs, bad):
    schema = compile_jev_schema(specs["tsmom_majors"])
    with pytest.raises(JevSchemaError):
        decision_from_answers("d1", _state({}), schema, _answers(**bad), "m", 5.0)


def test_decision_validation_rejects_out_of_range():
    kw = dict(decision_id="d", strategy_id="s", package="p", ts=0, regime=Regime.TRENDING, direction=Direction.LONG, setup_quality=4, liquidity_quality=1, toxic_flow=0, expected_edge=50.0, risk_state=RiskState.SAFE, should_trade=True, confidence=0.7, p_trade=0.6, probabilities={}, model_version="m", latency_ms=1.0, state_hash="h", schema_hash="h")
    with pytest.raises(JevSchemaError):
        JevDecision(**kw)
    with pytest.raises(JevSchemaError):
        JevDecision(**(kw | {"setup_quality": 2, "confidence": 1.5}))


def test_reference_jev_valid_and_deterministic(data, specs):
    jev = ReferenceJev()
    t = data.bars["BTCUSDT-PERP"].ts[1200]
    for spec in specs.values():
        schema = compile_jev_schema(spec)
        f = standard_features(data.view(t), spec.packages[0].legs[0].symbol, 6)
        f |= {"ratio_z": 2.3, "ratio_er": 0.1, "stable_growth_30d": 0.02, "close_vs_sma200": 0.05}
        cand = spec.allowed_directions[0]
        a = jev.decide(_state(f, spec.jev.profile, cand), schema)
        b = jev.decide(_state(f, spec.jev.profile, cand), schema)
        assert a.to_dict() | {"latency_ms": 0} == b.to_dict() | {"latency_ms": 0}
        assert 0 <= a.confidence <= 1 and 0 <= a.expected_edge <= 100
        assert abs(sum(a.probabilities["regime"].values()) - 1) < 1e-9


def test_reference_jev_unknown_state_is_low_confidence(specs):
    d = ReferenceJev().decide(_state({}), compile_jev_schema(specs["tsmom_majors"]))
    assert d.confidence < 0.6


def test_reference_jev_flags_crisis(specs):
    f = {"rv_ratio": 3.5, "er_10d": 0.2, "dd_6d": -0.25, "ret_1d": -0.2, "daily_vol": 0.03, "mom_20d": -0.3, "mom_60d": -0.3}
    d = ReferenceJev().decide(_state(f), compile_jev_schema(specs["tsmom_majors"]))
    assert d.regime is Regime.CRISIS and d.risk_state.value == "flat" and not d.should_trade


class _SlowEngine:
    model_version = "slow"

    def decide(self, state, schema):
        d = ReferenceJev().decide(state, schema)
        from dataclasses import replace

        return replace(d, latency_ms=900.0)


def test_budgeted_jev_fails_closed(specs):
    with pytest.raises(JevUnavailable):
        BudgetedJev(_SlowEngine(), 250).decide(_state({}), compile_jev_schema(specs["tsmom_majors"]))


def test_shadow_errors_never_reach_primary(specs):
    seen = []

    class Boom:
        model_version = "boom"

        def decide(self, *a):
            raise RuntimeError("shadow down")

    eng = ShadowJev(ReferenceJev(), Boom(), lambda p, s, e: seen.append(e))
    d = eng.decide(_state({}), compile_jev_schema(specs["tsmom_majors"]))
    assert d.model_version == "reference-jev-1.0" and "shadow down" in seen[0]


def test_remote_jev_refuses_unverified_wire_format(monkeypatch):
    monkeypatch.delenv("JEV_WIRE_FORMAT_VERIFIED", raising=False)
    with pytest.raises(JevConfigError, match="unverified"):
        RemoteJev("https://example.invalid/decide", "k", "jev")


class _Resp:
    def __init__(self, status, body):
        self.status_code, self._body, self.text = status, body, str(body)

    def json(self):
        return self._body


class _Session:
    def __init__(self, resp=None, exc=None):
        self.resp, self.exc, self.sent = resp, exc, None

    def post(self, url, json=None, headers=None, timeout=None):
        self.sent = (url, json, headers, timeout)
        if self.exc:
            raise self.exc
        return self.resp


def test_remote_jev_round_trip_and_failures(specs):
    schema = compile_jev_schema(specs["tsmom_majors"])
    body = {"answers": {k: ({"probability": v["p_yes"]} if "p_yes" in v else v) for k, v in _answers().items()}}
    sess = _Session(_Resp(200, body))
    eng = RemoteJev("https://jev.example/decide", "key", "jev-1", timeout_ms=250, session=sess, wire_format_verified=True)
    d = eng.decide(_state({"x": 1.0}), schema)
    assert d.model_version == "jev:jev-1" and d.should_trade
    url, sent, headers, timeout = sess.sent
    assert headers["Authorization"] == "Bearer key" and timeout == 0.25
    assert {q["type"] for q in sent["questions"]} == {"choice", "score", "noul"}
    with pytest.raises(JevUnavailable):
        RemoteJev("u", "k", "m", session=_Session(_Resp(503, {})), wire_format_verified=True).decide(_state({}), schema)
    with pytest.raises(JevUnavailable):
        RemoteJev("u", "k", "m", session=_Session(exc=requests.Timeout("t")), wire_format_verified=True).decide(_state({}), schema)
    with pytest.raises(JevSchemaError):
        RemoteJev("u", "k", "m", session=_Session(_Resp(200, {"nope": 1})), wire_format_verified=True).decide(_state({}), schema)


def test_codec_degrades_point_answers(specs):
    schema = compile_jev_schema(specs["tsmom_majors"])
    body = {"answers": {"regime": {"value": "trending", "confidence": 0.7}}}
    for q in schema.questions:
        if q.key != "regime":
            body["answers"][q.key] = {"probability": 0.6} if q.kind == "binary" else {"value": (q.options or q.levels)[0], "confidence": 0.9}
    out = ProvisionalCodec().decode(body, schema)
    assert out["regime"]["probabilities"]["trending"] == 0.7

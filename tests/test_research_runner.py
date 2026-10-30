import json
from types import SimpleNamespace

import pytest

from hedgefund.core.clock import SimClock
from hedgefund.core.ledger import Ledger
from hedgefund.ops.runner import FundRunner, ReplayDataProvider
from hedgefund.research import schemas
from hedgefund.research.opus import OpusResearcher, ResearchError, ResearchRefused
from hedgefund.research.pipeline import coalesce_escalations, market_evidence, run_overnight_research, spec_from_draft


# ---------------- Opus research layer (fake client; no network) ----------------
class FakeStream:
    def __init__(self, msg):
        self.msg = msg

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def get_final_message(self):
        return self.msg


class FakeClient:
    def __init__(self, payloads, stop_reason="end_turn"):
        self.payloads = list(payloads)
        self.stop_reason = stop_reason
        self.calls = []
        self.messages = self

    def stream(self, **kw):
        self.calls.append(kw)
        body = self.payloads.pop(0) if self.payloads else {}
        msg = SimpleNamespace(
            stop_reason=self.stop_reason,
            content=[SimpleNamespace(type="thinking", thinking=""), SimpleNamespace(type="text", text=json.dumps(body))],
            usage=SimpleNamespace(input_tokens=10, output_tokens=20, cache_read_input_tokens=5, cache_creation_input_tokens=0),
            model="claude-opus-5-5",
            stop_details=SimpleNamespace(category="cyber"),
        )
        return FakeStream(msg)


def test_opus_request_shape_and_parsing():
    client = FakeClient([{"summary": "ok"}])
    r = OpusResearcher(client=client).write_memo("BTC funding", [{"metric": "x", "value": 1}])
    kw = client.calls[0]
    assert kw["model"] == "claude-opus-5-5"
    assert kw["output_config"]["effort"] == "high"
    assert kw["output_config"]["format"] == {"type": "json_schema", "schema": schemas.RESEARCH_MEMO}
    assert kw["system"][0]["cache_control"] == {"type": "ephemeral"}
    assert "thinking" not in kw and "tool_choice" not in kw  # Opus 5.5: thinking is always on; no forced tools
    assert "<evidence>" in kw["messages"][0]["content"]
    assert r.data == {"summary": "ok"} and r.usage["cache_read_input_tokens"] == 5


def test_opus_refusal_and_truncation():
    with pytest.raises(ResearchRefused):
        OpusResearcher(client=FakeClient([{}], stop_reason="refusal")).market_scan([], "2026-09-24")
    with pytest.raises(ResearchError, match="truncated"):
        OpusResearcher(client=FakeClient([{}], stop_reason="max_tokens")).market_scan([], "2026-09-24")


def _closed(schema, path="$"):
    if schema.get("type") == "object":
        assert schema.get("additionalProperties") is False, path
        assert set(schema["required"]) == set(schema["properties"]), path
        for k, v in schema["properties"].items():
            _closed(v, f"{path}.{k}")
    if schema.get("type") == "array":
        _closed(schema["items"], f"{path}[]")


@pytest.mark.parametrize("name", ["MARKET_SCAN", "RESEARCH_MEMO", "STRATEGY_DRAFT", "ESCALATION_REVIEW", "OVERNIGHT_REVIEW"])
def test_schemas_are_closed(name):
    _closed(getattr(schemas, name))


DRAFT = {
    "id": "btc_weekend_gap", "name": "Weekend gap fade", "hypothesis": "Thin weekend liquidity overshoots.",
    "edge_source": "liquidity_provision", "universe": ["BTCUSDT-PERP"],
    "packages": [{"key": "BTC-wg", "legs": [{"symbol": "BTCUSDT-PERP", "weight": 1.0}]}],
    "timeframe": "4h", "allowed_directions": ["long", "short"], "features": ["ret_z_1d"],
    "entry_rules": ["|weekend return z| > 2"], "exit_rules": ["Monday close"], "expected_holding": "1-2 days",
    "parameters": [{"name": "entry_z", "value": 2.0}],
    "risk": {"risk_per_trade_pct_nav": 0.004, "max_package_notional_pct_nav": 0.1},
    "costs": {"fee_bps_roundtrip": 10, "slippage_bps_roundtrip": 6, "funding_note": "small"},
    "jev": {"profile": "reversion", "allowed_regimes": ["mean_reverting"], "min_setup_quality": 2, "min_liquidity_quality": 1,
            "max_toxic_flow": 1, "min_expected_edge": 55, "min_confidence": 0.65, "calibration_horizon_bars": 12,
            "instructions": [{"question": "should_trade", "text": "only fade forced moves"}]},
    "invalidation": [{"metric": "strategy_drawdown", "op": ">", "threshold": 0.03, "min_observations": 0, "action": "halt"}],
    "data_sources": ["binance_usdm_klines"], "failure_modes": ["news-driven weekend moves"], "capacity_usd": 5e6,
    "what_could_i_be_wrong_about": ["everything"],
}


def test_spec_from_draft(cfg):
    spec, problems = spec_from_draft(DRAFT, "memo_1", set(cfg.instruments))
    assert problems == [] and spec.stage.value == "hypothesis" and spec.impl is None and spec.research_memo == "memo_1"
    bad = DRAFT | {"universe": ["DOGEUSDT"], "jev": DRAFT["jev"] | {"min_confidence": 0.4}}
    spec, problems = spec_from_draft(bad, None, set(cfg.instruments))
    assert spec is None and any("floor" in p for p in problems)


def test_market_evidence_is_dated_and_labelled(data):
    ev = market_evidence(data, data.bars["BTCUSDT"].ts[-1])
    assert ev and all(e["as_of"] and "SYNTHETIC" in e["source"] for e in ev)
    assert any("stablecoin" in e["metric"] for e in ev)


def test_overnight_research_writes_only_advisory_records(data, ledger):
    t = data.bars["BTCUSDT"].ts[-1]
    ledger.append("escalation", {"strategy_id": "s", "package": "p", "reason": "jev confidence 0.41 < 0.60", "decision_id": "d", "action_taken": "no_trade"}, ts=t - 1000)
    client = FakeClient([
        {"as_of": "x", "regime_view": {"summary": "s", "confidence": "low"}, "opportunities": [], "what_could_i_be_wrong_about": []},
        {"assessment": "a", "likely_cause": "model_uncertainty", "recommended_action": "human_review", "rationale": "r", "facts": [], "what_could_i_be_wrong_about": []},
        {"summary": "s", "performance_attribution": [], "anomalies": [], "calibration_concerns": [], "failure_analysis": [],
         "proposals": [{"kind": "retire_strategy", "target": "s", "description": "d", "expected_benefit": "b", "risk": "r"}], "what_could_i_be_wrong_about": []},
    ])
    out = run_overnight_research(OpusResearcher(client=client), ledger, data, "# report", {}, t)
    assert len(out["memos"]) == 3 and len(out["approval_requests"]) == 1 and not out["errors"]
    kinds = {e.kind for e in ledger.query()}
    assert "approval_request" in kinds and "stage_transition" not in kinds and "order" not in kinds
    assert coalesce_escalations(ledger, t - 86_400_000, t)[0]["count"] == 1


# ---------------- 24/7 runner ----------------
def _runner(cfg, data, ledger, clock):
    return FundRunner(cfg, ReplayDataProvider(data), clock=clock, ledger=ledger, include_all_stages=True, persist_files=False)


def test_runner_is_idempotent_per_bar_and_restart_safe(cfg, data, tmp_path):
    ledger = Ledger(tmp_path / "ledger.db")
    ts = data.timeline()
    clock = SimClock(ts[0])
    r1 = _runner(cfg, data, ledger, clock)
    for t in ts[1200:1400]:
        clock.set(t + 1000)
        r1.run_once()
    assert r1.run_once().status == "no_new_bar"
    nav1, pos1 = r1.stack.portfolio.nav(), r1.stack.portfolio.positions()
    # Restart from the same ledger: books, NAV and high-water mark are rebuilt.
    r2 = _runner(cfg, data, ledger, clock)
    assert r2.stack.portfolio.nav() == pytest.approx(nav1, rel=1e-9)
    assert r2.stack.portfolio.positions() == pytest.approx(pos1)
    assert r2.last_bar_ts == r1.last_bar_ts and r2.stack.risk.hwm == pytest.approx(r1.stack.risk.hwm)
    assert r2.stack.execution.reconcile().ok
    assert len(r2.stack.calibration.pending) == len(r1.stack.calibration.pending)


def test_runner_data_outage_fails_closed(cfg, data, ledger):
    class Down:
        def load(self, now):
            raise ConnectionError("exchange unreachable")

    clock = SimClock(data.timeline()[1300])
    r = FundRunner(cfg, Down(), clock=clock, ledger=ledger, include_all_stages=True, persist_files=False)
    assert r.run_once().status == "data_unavailable"
    assert not ledger.query(kind="order") and ledger.query(kind="alert")


def test_runner_kill_switch_flattens(cfg, data, ledger):
    ts = data.timeline()
    clock = SimClock(ts[0])
    r = _runner(cfg, data, ledger, clock)
    for t in ts[1200:1500]:
        clock.set(t + 1000)
        r.run_once()
        if r.stack.portfolio.positions():
            break
    assert r.stack.portfolio.positions(), "expected some position on this synthetic path"
    r.stack.kill_switch.engage("operator test", "test")
    clock.set(ts[ts.index(t) + 1] + 1000)
    r.run_once()
    assert r.stack.portfolio.positions() == {}
    assert any(a["severity"] == "critical" for a in r.alerts.sent)


def test_runner_idle_when_nothing_runnable(cfg, data, ledger):
    r = FundRunner(cfg, ReplayDataProvider(data), clock=SimClock(data.timeline()[-1]), ledger=ledger, persist_files=False)
    assert r.run_once().status == "idle"  # all specs are below paper_trade: nothing trades by default

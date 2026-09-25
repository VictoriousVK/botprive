"""JSON schemas for Opus 5.5 structured outputs. Every object is closed
(additionalProperties: false) and every property required, so parsed output is complete."""

from __future__ import annotations

from typing import Any


def obj(props: dict[str, Any]) -> dict[str, Any]:
    return {"type": "object", "properties": props, "required": list(props), "additionalProperties": False}


def arr(items: dict[str, Any]) -> dict[str, Any]:
    return {"type": "array", "items": items}


def enum(*values: str) -> dict[str, Any]:
    return {"type": "string", "enum": list(values)}


STR = {"type": "string"}
NUM = {"type": "number"}
INT = {"type": "integer"}
BOOL = {"type": "boolean"}
CONFIDENCE = enum("low", "medium", "high")

FACT = obj({"statement": STR, "source": STR, "source_date": STR})
CATALYST = obj({"event": STR, "expected_timing": STR, "priced_in_assessment": STR})

OPPORTUNITY = obj({
    "title": STR,
    "asset_or_theme": STR,
    "thesis": STR,
    "why_mispriced": STR,
    "facts": arr(FACT),
    "interpretation": arr(STR),
    "catalysts": arr(CATALYST),
    "competition": arr(STR),
    "bear_case": arr(STR),
    "invalidation_conditions": arr(STR),
    "asymmetry": STR,
    "time_horizon": STR,
    "confidence": CONFIDENCE,
    "testable_hypothesis": STR,
    "data_required": arr(STR),
})

MARKET_SCAN = obj({
    "as_of": STR,
    "regime_view": obj({"summary": STR, "confidence": CONFIDENCE}),
    "opportunities": arr(OPPORTUNITY),
    "what_could_i_be_wrong_about": arr(STR),
})

RESEARCH_MEMO = obj({
    "title": STR,
    "as_of": STR,
    "summary": STR,
    "facts": arr(FACT),
    "interpretation": arr(STR),
    "catalysts": arr(CATALYST),
    "competition": arr(STR),
    "bear_case": arr(STR),
    "invalidation_conditions": arr(STR),
    "valuation_or_pricing_disconnect": STR,
    "proposed_hypotheses": arr(obj({"hypothesis": STR, "testable_prediction": STR, "data_required": arr(STR), "horizon": STR})),
    "confidence": CONFIDENCE,
    "what_could_i_be_wrong_about": arr(STR),
})

QUESTION_KEYS = ("regime", "direction", "setup_quality", "liquidity_quality", "toxic_flow", "expected_edge", "risk_state", "should_trade")

STRATEGY_DRAFT = obj({
    "id": STR,
    "name": STR,
    "hypothesis": STR,
    "edge_source": enum("structural", "behavioral", "risk_premium", "informational", "liquidity_provision"),
    "universe": arr(STR),
    "packages": arr(obj({"key": STR, "legs": arr(obj({"symbol": STR, "weight": NUM}))})),
    "timeframe": enum("1h", "4h", "1d"),
    "allowed_directions": arr(enum("long", "short")),
    "features": arr(STR),
    "entry_rules": arr(STR),
    "exit_rules": arr(STR),
    "expected_holding": STR,
    "parameters": arr(obj({"name": STR, "value": NUM})),
    "risk": obj({"risk_per_trade_pct_nav": NUM, "max_package_notional_pct_nav": NUM}),
    "costs": obj({"fee_bps_roundtrip": NUM, "slippage_bps_roundtrip": NUM, "funding_note": STR}),
    "jev": obj({
        "profile": enum("directional", "carry", "reversion", "macro", "relative_value"),
        "allowed_regimes": arr(enum("trending", "mean_reverting", "high_vol")),
        "min_setup_quality": INT,
        "min_liquidity_quality": INT,
        "max_toxic_flow": INT,
        "min_expected_edge": NUM,
        "min_confidence": NUM,
        "calibration_horizon_bars": INT,
        "instructions": arr(obj({"question": enum(*QUESTION_KEYS), "text": STR})),
    }),
    "invalidation": arr(obj({"metric": STR, "op": enum("<", ">"), "threshold": NUM, "min_observations": INT, "action": enum("demote", "halt", "retire")})),
    "data_sources": arr(STR),
    "failure_modes": arr(STR),
    "capacity_usd": NUM,
    "what_could_i_be_wrong_about": arr(STR),
})

ESCALATION_REVIEW = obj({
    "assessment": STR,
    "likely_cause": enum("regime_shift", "data_issue", "model_uncertainty", "event_risk", "liquidity_stress", "unknown"),
    "recommended_action": enum("no_action", "keep_reduced_risk", "halt_strategy", "flatten_strategy", "flatten_all", "human_review"),
    "rationale": STR,
    "facts": arr(FACT),
    "what_could_i_be_wrong_about": arr(STR),
})

OVERNIGHT_REVIEW = obj({
    "summary": STR,
    "performance_attribution": arr(STR),
    "anomalies": arr(STR),
    "calibration_concerns": arr(STR),
    "failure_analysis": arr(STR),
    "proposals": arr(obj({
        "kind": enum("new_strategy", "retire_strategy", "parameter_change", "jev_schema_change", "data_source", "risk_limit_change", "investigation"),
        "target": STR,
        "description": STR,
        "expected_benefit": STR,
        "risk": STR,
    })),
    "what_could_i_be_wrong_about": arr(STR),
})

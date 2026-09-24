"""Jev decision schema.

Each strategy compiles a schema of typed questions. Jev answers them from a rendered market
state; deterministic code validates the answers into a JevDecision. Jev never sees NAV,
positions or limits and its output contains no size: it judges the state, nothing more.

Question types mirror Jev's three primitives: choice (pick one option), score (ordered
rubric levels), and a yes/no probability ("Noul").
"""

from __future__ import annotations

import math
from dataclasses import asdict, dataclass, field
from typing import Any

from hedgefund.core.ids import content_hash
from hedgefund.core.timeutil import utc_iso
from hedgefund.core.types import Direction, Regime, RiskState


class JevSchemaError(ValueError):
    pass


@dataclass(frozen=True)
class JevQuestion:
    key: str
    kind: str  # "choice" | "score" | "binary"
    prompt: str
    options: tuple[str, ...] = ()  # choice
    levels: tuple[str, ...] = ()  # score, ordered low -> high


_DEFAULT_PROMPTS = {
    "regime": "Which market regime best describes the current state of the primary instrument?",
    "direction": "Given the state and the candidate setup, which package direction is supported?",
    "setup_quality": "How strong and clean is the candidate setup described in the state?",
    "liquidity_quality": "How good is current liquidity for entering and exiting this package at size?",
    "toxic_flow": "How much one-sided, informed or forced flow is present right now?",
    "expected_edge": "How large is the expected edge of taking the candidate trade now, after costs?",
    "risk_state": "What risk posture does the current state call for?",
    "should_trade": "Should the candidate trade be taken now?",
}

QUALITY_LEVELS = ("0 - absent/poor", "1 - weak", "2 - adequate", "3 - strong")
TOXIC_LEVELS = ("0 - benign two-way flow", "1 - mild imbalance", "2 - heavy one-sided flow", "3 - forced/liquidation flow")
EDGE_LEVELS = ("0 - negative", "25 - marginal", "50 - neutral", "75 - positive", "100 - exceptional")

STANDARD_KEYS = ("regime", "direction", "setup_quality", "liquidity_quality", "toxic_flow", "expected_edge", "risk_state", "should_trade")


def standard_questions(instructions: dict[str, str] | None = None) -> tuple[JevQuestion, ...]:
    ins = instructions or {}

    def p(key: str) -> str:
        extra = ins.get(key)
        return f"{_DEFAULT_PROMPTS[key]} {extra}".strip() if extra else _DEFAULT_PROMPTS[key]

    return (
        JevQuestion("regime", "choice", p("regime"), options=tuple(r.value for r in Regime)),
        JevQuestion("direction", "choice", p("direction"), options=tuple(d.value for d in Direction)),
        JevQuestion("setup_quality", "score", p("setup_quality"), levels=QUALITY_LEVELS),
        JevQuestion("liquidity_quality", "score", p("liquidity_quality"), levels=QUALITY_LEVELS),
        JevQuestion("toxic_flow", "score", p("toxic_flow"), levels=TOXIC_LEVELS),
        JevQuestion("expected_edge", "score", p("expected_edge"), levels=EDGE_LEVELS),
        JevQuestion("risk_state", "choice", p("risk_state"), options=tuple(r.value for r in RiskState)),
        JevQuestion("should_trade", "binary", p("should_trade")),
    )


@dataclass(frozen=True)
class JevSchema:
    strategy_id: str
    profile: str
    questions: tuple[JevQuestion, ...]

    @property
    def schema_hash(self) -> str:
        return content_hash([asdict(q) for q in self.questions] + [self.profile])

    def question(self, key: str) -> JevQuestion:
        for q in self.questions:
            if q.key == key:
                return q
        raise KeyError(key)


def compile_jev_schema(spec: Any) -> JevSchema:
    """spec: StrategySpec (duck-typed to avoid an import cycle)."""
    return JevSchema(spec.id, spec.jev.profile, standard_questions(spec.jev.instructions))


@dataclass(frozen=True)
class JevState:
    strategy_id: str
    package: str
    symbol: str
    ts: int
    profile: str
    candidate_direction: Direction
    features: dict[str, float]
    context: dict[str, str] = field(default_factory=dict)

    def text(self) -> str:
        """Deterministic rendering sent to Jev (stable key order, fixed precision)."""
        lines = [
            f"time_utc: {utc_iso(self.ts)}",
            f"strategy: {self.strategy_id} (profile: {self.profile})",
            f"package: {self.package} primary: {self.symbol}",
            f"candidate_direction: {self.candidate_direction.value}",
        ]
        lines += [f"context.{k}: {v}" for k, v in sorted(self.context.items())]
        lines += [f"feature.{k}: {v:.6g}" for k, v in sorted(self.features.items()) if math.isfinite(v)]
        return "\n".join(lines)

    @property
    def state_hash(self) -> str:
        return content_hash(self.text())


@dataclass(frozen=True)
class JevDecision:
    decision_id: str
    strategy_id: str
    package: str
    ts: int
    regime: Regime
    direction: Direction
    setup_quality: int
    liquidity_quality: int
    toxic_flow: int
    expected_edge: float
    risk_state: RiskState
    should_trade: bool
    confidence: float
    p_trade: float
    probabilities: dict[str, dict[str, float]]
    model_version: str
    latency_ms: float
    state_hash: str
    schema_hash: str

    def __post_init__(self) -> None:
        for name in ("setup_quality", "liquidity_quality", "toxic_flow"):
            v = getattr(self, name)
            if not isinstance(v, int) or not 0 <= v <= 3:
                raise JevSchemaError(f"{name} must be an int in 0-3, got {v!r}")
        if not 0.0 <= self.expected_edge <= 100.0:
            raise JevSchemaError(f"expected_edge must be in 0-100, got {self.expected_edge!r}")
        if not 0.0 <= self.confidence <= 1.0 or not math.isfinite(self.confidence):
            raise JevSchemaError(f"confidence must be in [0, 1], got {self.confidence!r}")
        if not 0.0 <= self.p_trade <= 1.0:
            raise JevSchemaError(f"p_trade must be in [0, 1], got {self.p_trade!r}")
        if not isinstance(self.regime, Regime) or not isinstance(self.direction, Direction) or not isinstance(self.risk_state, RiskState):
            raise JevSchemaError("regime/direction/risk_state must be enum members")

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["regime"], d["direction"], d["risk_state"] = self.regime.value, self.direction.value, self.risk_state.value
        return d


def _argmax(p: dict[str, float]) -> str:
    return max(sorted(p), key=lambda k: p[k])


def decision_from_answers(
    decision_id: str,
    state: JevState,
    schema: JevSchema,
    answers: dict[str, dict[str, Any]],
    model_version: str,
    latency_ms: float,
) -> JevDecision:
    """Map typed answers {key: {"probabilities": {...}} | {"p_yes": float}} to a JevDecision.

    Choice and score answers carry a probability per option/level; the chosen answer is the
    argmax. Score values are the index of the chosen level; expected_edge uses the
    probability-weighted level position scaled to 0-100. Overall confidence is the minimum
    of the per-question confidences of the gating questions (conservative by design).
    """
    missing = [k for k in STANDARD_KEYS if k not in answers]
    if missing:
        raise JevSchemaError(f"missing answers: {missing}")

    def probs(key: str) -> dict[str, float]:
        raw = answers[key].get("probabilities")
        if not isinstance(raw, dict) or not raw:
            raise JevSchemaError(f"{key}: probabilities missing")
        q = schema.question(key)
        allowed = q.options if q.kind == "choice" else q.levels
        if set(raw) - set(allowed):
            raise JevSchemaError(f"{key}: unknown options {sorted(set(raw) - set(allowed))}")
        total = sum(float(v) for v in raw.values())
        if total <= 0 or any(float(v) < 0 for v in raw.values()):
            raise JevSchemaError(f"{key}: invalid probabilities")
        return {k: float(raw.get(k, 0.0)) / total for k in allowed}

    def level_index(key: str) -> tuple[int, dict[str, float]]:
        p = probs(key)
        levels = schema.question(key).levels
        return levels.index(_argmax(p)), p

    regime_p, dir_p, risk_p = probs("regime"), probs("direction"), probs("risk_state")
    setup, setup_p = level_index("setup_quality")
    liq, liq_p = level_index("liquidity_quality")
    tox, tox_p = level_index("toxic_flow")
    edge_p = probs("expected_edge")
    edge_levels = schema.question("expected_edge").levels
    edge = sum(edge_p[l] * i for i, l in enumerate(edge_levels)) * 100.0 / (len(edge_levels) - 1)
    p_yes = answers["should_trade"].get("p_yes")
    if not isinstance(p_yes, (int, float)) or not 0.0 <= float(p_yes) <= 1.0:
        raise JevSchemaError("should_trade.p_yes must be a probability")
    p_yes = float(p_yes)
    confidence = min(max(regime_p.values()), max(dir_p.values()), max(risk_p.values()), max(p_yes, 1 - p_yes))
    return JevDecision(
        decision_id=decision_id,
        strategy_id=state.strategy_id,
        package=state.package,
        ts=state.ts,
        regime=Regime(_argmax(regime_p)),
        direction=Direction(_argmax(dir_p)),
        setup_quality=setup,
        liquidity_quality=liq,
        toxic_flow=tox,
        expected_edge=round(min(100.0, max(0.0, edge)), 4),
        risk_state=RiskState(_argmax(risk_p)),
        should_trade=p_yes >= 0.5,
        confidence=round(confidence, 6),
        p_trade=round(p_yes, 6),
        probabilities={
            "regime": regime_p,
            "direction": dir_p,
            "setup_quality": setup_p,
            "liquidity_quality": liq_p,
            "toxic_flow": tox_p,
            "expected_edge": edge_p,
            "risk_state": risk_p,
            "should_trade": {"yes": p_yes, "no": 1 - p_yes},
        },
        model_version=model_version,
        latency_ms=round(latency_ms, 3),
        state_hash=state.state_hash,
        schema_hash=schema.schema_hash,
    )

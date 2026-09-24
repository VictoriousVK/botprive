"""Deterministic policy: (strategy signal, Jev decision, spec, current book) -> action + targets.

Precedence (first match wins):
  1. Strategy exit signal (FLAT)            -> EXIT. Exits never wait for Jev.
  2. Jev unavailable / invalid              -> no new risk; hold existing.
  3. Regime = crisis                        -> no new risk, escalate; EXIT if spec.exit_on_crisis.
  4. Jev confidence < max(floor, spec min)  -> no new risk, escalate; hold existing.
  5. risk_state = flat                      -> EXIT.   risk_state = reduce -> REDUCE (halve), no adds.
  6. Entry gates (all must pass)            -> ENTER / ADJUST; otherwise HOLD existing or NO_TRADE.

Sizing is computed here, never by a model:
  package_notional = min(NAV * risk_per_trade / stop_distance * m_setup * m_liq * m_conf,
                         NAV * max_package_notional_pct_nav)
The risk engine may clip it further; nothing downstream can increase it.
"""

from __future__ import annotations

import enum
from dataclasses import dataclass, field

from hedgefund.config import JEV_CONFIDENCE_FLOOR, RiskLimits
from hedgefund.core.types import Direction, Regime, RiskState, Signal
from hedgefund.jev.schema import JevDecision
from hedgefund.strategy.spec import StrategySpec

QUALITY_MULT = {0: 0.0, 1: 0.25, 2: 0.6, 3: 1.0}


def confidence_mult(c: float) -> float:
    return 1.0 if c >= 0.8 else 0.75 if c >= 0.7 else 0.5


class Action(str, enum.Enum):
    ENTER = "enter"
    ADJUST = "adjust"
    EXIT = "exit"
    REDUCE = "reduce"
    HOLD = "hold"
    NO_TRADE = "no_trade"

    @property
    def trades(self) -> bool:
        return self in (Action.ENTER, Action.ADJUST, Action.EXIT, Action.REDUCE)


@dataclass(frozen=True)
class PolicyResult:
    action: Action
    strategy_id: str
    package: str
    direction: Direction
    leg_targets: dict[str, float]  # signed target notional per symbol for this strategy's book
    ts: int
    decision_id: str | None
    model_version: str | None
    reasons: tuple[str, ...] = ()
    escalate: bool = False
    escalation_reason: str = ""
    package_notional: float = 0.0
    sizing: dict[str, float] = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "action": self.action.value,
            "strategy_id": self.strategy_id,
            "package": self.package,
            "direction": self.direction.value,
            "leg_targets": self.leg_targets,
            "ts": self.ts,
            "decision_id": self.decision_id,
            "model_version": self.model_version,
            "reasons": list(self.reasons),
            "escalate": self.escalate,
            "escalation_reason": self.escalation_reason,
            "package_notional": self.package_notional,
            "sizing": self.sizing,
        }


class PolicyEngine:
    def __init__(self, limits: RiskLimits):
        self.limits = limits

    def _min_conf(self, spec: StrategySpec) -> float:
        return max(JEV_CONFIDENCE_FLOOR, self.limits.jev_min_confidence, spec.jev.min_confidence)

    def evaluate(
        self,
        signal: Signal,
        decision: JevDecision | None,
        spec: StrategySpec,
        book_notional: dict[str, float],
        nav: float,
        unavailable_reason: str = "jev unavailable",
    ) -> PolicyResult:
        legs = {leg.symbol for leg in signal.legs}
        current = {s: book_notional.get(s, 0.0) for s in legs}
        holding = any(abs(v) > 1e-9 for v in current.values())
        cur_dir = self._current_direction(signal, current)
        did = decision.decision_id if decision else None
        mv = decision.model_version if decision else None

        def result(action: Action, targets: dict[str, float], *reasons: str, direction: Direction | None = None, escalate: str = "", notional: float = 0.0, sizing: dict | None = None) -> PolicyResult:
            return PolicyResult(
                action=action,
                strategy_id=signal.strategy_id,
                package=signal.package,
                direction=direction or signal.direction,
                leg_targets=targets,
                ts=signal.ts,
                decision_id=did,
                model_version=mv,
                reasons=tuple(reasons),
                escalate=bool(escalate),
                escalation_reason=escalate,
                package_notional=notional,
                sizing=sizing or {},
            )

        flat_targets = {s: 0.0 for s in legs}
        hold = lambda *r, esc="": result(Action.HOLD if holding else Action.NO_TRADE, dict(current), *r, direction=cur_dir, escalate=esc)  # noqa: E731

        # 1. Strategy exit
        if signal.is_exit:
            return result(Action.EXIT, flat_targets, "strategy exit signal") if holding else result(Action.NO_TRADE, flat_targets, "exit signal, nothing held")

        # 2. Jev unavailable
        if decision is None:
            return hold(f"{unavailable_reason}: no new risk")

        # 3. Crisis
        if decision.regime is Regime.CRISIS:
            esc = f"jev regime=crisis (confidence {decision.confidence:.2f})"
            if holding and spec.risk.exit_on_crisis:
                return result(Action.EXIT, flat_targets, "crisis regime: exit per spec", escalate=esc)
            return hold("crisis regime: no new risk", esc=esc)

        # 4. Low confidence
        min_conf = self._min_conf(spec)
        if decision.confidence < min_conf:
            esc = f"jev confidence {decision.confidence:.2f} < {min_conf:.2f}" if decision.confidence < JEV_CONFIDENCE_FLOOR else ""
            return hold(f"confidence {decision.confidence:.2f} < required {min_conf:.2f}", esc=esc)

        risk_pct = min(spec.risk.risk_per_trade_pct_nav, self.limits.max_risk_per_trade_pct_nav)
        stop = max(signal.stop_distance_pct, 1e-9)
        base_notional = min(nav * risk_pct / stop, nav * spec.risk.max_package_notional_pct_nav)

        # 5. Risk state
        if decision.risk_state is RiskState.FLAT:
            return result(Action.EXIT, flat_targets, "jev risk_state=flat") if holding else result(Action.NO_TRADE, flat_targets, "jev risk_state=flat")
        if decision.risk_state is RiskState.REDUCE:
            if not holding:
                return result(Action.NO_TRADE, flat_targets, "jev risk_state=reduce: no new risk")
            # Stateless: cap the package at half its unmultiplied size; no repeated halving.
            cur_size = max(abs(v) for v in current.values())
            cap = 0.5 * base_notional
            if cur_size <= cap * 1.05:
                return hold("jev risk_state=reduce: already at or below reduced size")
            scale = cap / cur_size
            return result(Action.REDUCE, {s: v * scale for s, v in current.items()}, "jev risk_state=reduce: cut to half size", direction=cur_dir)

        # 6. Entry gates
        j = spec.jev
        failures = []
        if signal.direction not in spec.allowed_directions:
            failures.append(f"direction {signal.direction.value} not allowed by spec")
        if decision.regime not in j.allowed_regimes:
            failures.append(f"regime {decision.regime.value} not in {[r.value for r in j.allowed_regimes]}")
        if decision.direction is not signal.direction:
            failures.append(f"jev direction {decision.direction.value} != signal {signal.direction.value}")
        if not decision.should_trade:
            failures.append(f"jev should_trade=no (p={decision.p_trade:.2f})")
        if decision.setup_quality < j.min_setup_quality:
            failures.append(f"setup_quality {decision.setup_quality} < {j.min_setup_quality}")
        if decision.liquidity_quality < j.min_liquidity_quality:
            failures.append(f"liquidity_quality {decision.liquidity_quality} < {j.min_liquidity_quality}")
        if decision.toxic_flow > j.max_toxic_flow:
            failures.append(f"toxic_flow {decision.toxic_flow} > {j.max_toxic_flow}")
        if decision.expected_edge < j.min_expected_edge:
            failures.append(f"expected_edge {decision.expected_edge:.1f} < {j.min_expected_edge:.1f}")
        if signal.stop_distance_pct <= 0:
            failures.append("non-positive stop distance")
        if failures:
            if holding and cur_dir is signal.direction:
                return hold("entry gates not met; keeping existing position", *failures)
            if holding:
                # Held against the signal and gates fail: flatten rather than keep a stale view.
                return result(Action.EXIT, flat_targets, "held position contradicts signal", *failures)
            return result(Action.NO_TRADE, flat_targets, *failures)

        m_setup = QUALITY_MULT[decision.setup_quality]
        m_liq = QUALITY_MULT[decision.liquidity_quality]
        m_conf = confidence_mult(decision.confidence)
        raw = nav * risk_pct / stop
        notional = min(raw * m_setup * m_liq * m_conf, nav * spec.risk.max_package_notional_pct_nav)
        sizing = {"risk_pct": risk_pct, "stop": signal.stop_distance_pct, "m_setup": m_setup, "m_liq": m_liq, "m_conf": m_conf, "raw": raw, "cap": nav * spec.risk.max_package_notional_pct_nav}
        sign = signal.direction.sign
        targets = {leg.symbol: sign * leg.weight * notional for leg in signal.legs}

        if holding and cur_dir is signal.direction:
            # Hysteresis: shrink only when the position exceeds the full-quality risk budget
            # (NAV fell or the stop widened); grow only when the quality-adjusted target is
            # materially larger. Transient multiplier flips never cause round-trip churn.
            cur_size = max(abs(v) for v in current.values())
            thr = spec.risk.rebalance_threshold
            if cur_size > base_notional * (1 + thr):
                shrink = {leg.symbol: sign * leg.weight * base_notional for leg in signal.legs}
                return result(Action.ADJUST, shrink, "position above risk budget: shrink", notional=base_notional, sizing=sizing)
            if notional > cur_size * (1 + thr):
                return result(Action.ADJUST, targets, "quality-adjusted target materially larger: grow", notional=notional, sizing=sizing)
            return result(Action.HOLD, dict(current), "within rebalance band", notional=notional, sizing=sizing)
        return result(Action.ENTER, targets, "all entry gates passed", notional=notional, sizing=sizing)

    @staticmethod
    def _current_direction(signal: Signal, current: dict[str, float]) -> Direction:
        """Infer package direction from the first leg's sign relative to its weight."""
        for leg in signal.legs:
            v = current.get(leg.symbol, 0.0)
            if abs(v) > 1e-9:
                return Direction.LONG if v * leg.weight > 0 else Direction.SHORT
        return Direction.FLAT

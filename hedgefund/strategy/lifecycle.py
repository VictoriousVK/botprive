"""Strategy lifecycle: observation -> hypothesis -> data -> signal -> backtest -> cost model
-> stress test -> risk review -> paper trade -> shadow mode -> live.

Promotion is one step at a time and requires evidence that clears the gate for the target
stage. Evidence produced from synthetic data never clears a gate. LIVE additionally requires
a named human approval. Demotion (to paper_trade or retired) is always allowed, never blocked,
and is triggered automatically by invalidation rules.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from hedgefund.core.ledger import Kind
from hedgefund.strategy.spec import STAGE_ORDER, Stage, StrategySpec


@dataclass(frozen=True)
class Check:
    key: str
    op: str  # ">=", "<=", "==", "present"
    threshold: Any = None
    why: str = ""

    def passes(self, evidence: dict[str, Any]) -> bool:
        if self.key not in evidence or evidence[self.key] is None:
            return False
        v = evidence[self.key]
        if self.op == "present":
            return v != ""
        if self.op == "==":
            return v == self.threshold
        try:
            return float(v) >= self.threshold if self.op == ">=" else float(v) <= self.threshold
        except (TypeError, ValueError):
            return False


@dataclass(frozen=True)
class Gate:
    target: Stage
    checks: tuple[Check, ...]
    requires_human: bool = False
    real_data_required: bool = False


GATES: dict[Stage, Gate] = {
    Stage.HYPOTHESIS: Gate(Stage.HYPOTHESIS, (Check("observation.memo_id", "present", why="observation documented in a research memo"),)),
    Stage.DATA: Gate(
        Stage.DATA,
        (
            Check("hypothesis.testable_prediction", "present", why="falsifiable prediction stated"),
            Check("hypothesis.spec_valid", "==", True, why="StrategySpec validates"),
        ),
    ),
    Stage.SIGNAL: Gate(
        Stage.SIGNAL,
        (
            Check("data.quality_ok", "==", True, why="data quality gate passes"),
            Check("data.history_days", ">=", 365, why="at least one year of point-in-time history"),
            Check("data.point_in_time", "==", True, why="no revised/backfilled data used as if known"),
        ),
        real_data_required=True,
    ),
    Stage.BACKTEST: Gate(
        Stage.BACKTEST,
        (
            Check("signal.impl_registered", "==", True),
            Check("signal.tests_passed", "==", True),
            Check("signal.lookahead_test_passed", "==", True, why="signals identical when future data is truncated"),
        ),
    ),
    Stage.COST_MODEL: Gate(
        Stage.COST_MODEL,
        (
            Check("backtest.trades", ">=", 30, why="enough trades to say anything"),
            Check("backtest.sharpe", ">=", 0.5, why="net-of-cost Sharpe"),
            Check("backtest.psr", ">=", 0.80, why="probabilistic Sharpe vs 0"),
            Check("backtest.dsr", ">=", 0.50, why="deflated for number of trials"),
            Check("backtest.max_drawdown", "<=", 0.25),
            Check("backtest.fold_positive_frac", ">=", 0.6, why="stable across time folds"),
        ),
        real_data_required=True,
    ),
    Stage.STRESS_TEST: Gate(
        Stage.STRESS_TEST,
        (
            Check("cost.sharpe_2x_fees", ">=", 0.3, why="survives doubled fees"),
            Check("cost.sharpe_3x_slippage", ">=", 0.2, why="survives tripled slippage"),
            Check("cost.sharpe_delay_2", ">=", 0.2, why="survives an extra bar of latency"),
        ),
        real_data_required=True,
    ),
    Stage.RISK_REVIEW: Gate(
        Stage.RISK_REVIEW,
        (
            Check("stress.passed", "==", True),
            Check("stress.worst_drawdown", "<=", 0.35),
            Check("stress.param_sharpe_min", ">=", 0.0, why="no cliff under +/-20% parameter changes"),
        ),
        real_data_required=True,
    ),
    Stage.PAPER_TRADE: Gate(
        Stage.PAPER_TRADE,
        (
            Check("risk.limits_compatible", "==", True),
            Check("risk.max_corr_to_book", "<=", 0.7, why="adds diversification"),
            Check("risk.capacity_ok", "==", True),
        ),
    ),
    Stage.SHADOW_MODE: Gate(
        Stage.SHADOW_MODE,
        (
            Check("paper.days", ">=", 14),
            Check("paper.trades", ">=", 10),
            Check("paper.slippage_ratio", "<=", 1.5, why="realized slippage within 1.5x of model"),
            Check("paper.brier_should_trade", "<=", 0.25, why="Jev calibrated on this strategy"),
            Check("paper.incidents", "==", 0),
        ),
    ),
    Stage.LIVE: Gate(
        Stage.LIVE,
        (
            Check("shadow.days", ">=", 7),
            Check("shadow.decision_parity", ">=", 0.95, why="shadow decisions match paper decisions"),
            Check("shadow.fill_deviation_bps", "<=", 10),
            Check("shadow.venue_adapter_verified", "==", True, why="venue adapter tested against the real venue"),
        ),
        requires_human=True,
        real_data_required=True,
    ),
}


@dataclass(frozen=True)
class Approval:
    operator: str
    reason: str
    ts: int


@dataclass
class TransitionResult:
    ok: bool
    strategy_id: str
    from_stage: Stage
    to_stage: Stage
    failures: list[str] = field(default_factory=list)


def evaluate_gate(target: Stage, evidence: dict[str, Any]) -> list[str]:
    gate = GATES.get(target)
    if gate is None:
        return []
    failures = [f"{c.key} {c.op} {c.threshold!r} failed (got {evidence.get(c.key)!r}) {c.why}".strip() for c in gate.checks if not c.passes(evidence)]
    if gate.real_data_required and evidence.get("synthetic", True):
        failures.append("evidence must come from real market data (evidence.synthetic must be False)")
    return failures


def current_stage(spec: StrategySpec, ledger: Any) -> Stage:
    events = ledger.query(kind=Kind.STAGE_TRANSITION, ref=spec.id, newest_first=True, limit=1)
    return Stage(events[0].payload["to"]) if events else spec.stage


def transition(
    spec: StrategySpec,
    target: Stage,
    evidence: dict[str, Any],
    ledger: Any,
    ts: int,
    approval: Approval | None = None,
    reason: str = "",
) -> TransitionResult:
    cur = current_stage(spec, ledger)
    res = TransitionResult(False, spec.id, cur, target)
    demotion = target is Stage.RETIRED or (target is Stage.PAPER_TRADE and cur.order > Stage.PAPER_TRADE.order)
    if demotion:
        if not reason:
            res.failures.append("demotion requires a reason")
    elif cur is Stage.RETIRED:
        res.failures.append("retired strategies cannot be promoted; create a new version")
    elif target.order != cur.order + 1:
        res.failures.append(f"promotion must be one step: {cur.value} -> {STAGE_ORDER[cur.order + 1].value}")
    else:
        res.failures.extend(evaluate_gate(target, evidence))
        if GATES[target].requires_human and (approval is None or not approval.operator.strip()):
            res.failures.append(f"{target.value} requires a named human approval")
    if res.failures:
        return res
    res.ok = True
    ledger.append(
        Kind.STAGE_TRANSITION,
        {
            "from": cur.value,
            "to": target.value,
            "evidence": evidence,
            "approval": vars(approval) if approval else None,
            "reason": reason,
            "spec_hash": spec.spec_hash,
            "version": spec.version,
        },
        ts=ts,
        ref=spec.id,
    )
    return res

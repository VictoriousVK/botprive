"""The fast decision path, shared by backtest, paper, shadow and (eventually) live:

  market view -> strategy signals -> Jev typed judgment -> deterministic policy -> PolicyResult

Execution is deliberately not here: callers pass the results to the ExecutionEngine (which
routes every order through the RiskEngine). Using one pipeline everywhere is what makes
backtest, paper and live behaviour comparable.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

from hedgefund.calibration.tracker import CalibrationTracker
from hedgefund.core.ledger import Kind
from hedgefund.core.types import Direction, Signal
from hedgefund.data.series import MarketView
from hedgefund.jev.engine import JevEngine, JevUnavailable
from hedgefund.jev.schema import JevSchema, JevSchemaError, JevState, compile_jev_schema
from hedgefund.policy.engine import PolicyEngine, PolicyResult
from hedgefund.portfolio.book import Portfolio
from hedgefund.strategy.base import Strategy, StrategyContext, load_strategy
from hedgefund.strategy.spec import StrategySpec

MAX_CONSECUTIVE_STRATEGY_ERRORS = 3


@dataclass
class StrategyRuntime:
    spec: StrategySpec
    strategy: Strategy
    schema: JevSchema
    errors: int = 0

    @classmethod
    def from_spec(cls, spec: StrategySpec) -> "StrategyRuntime":
        return cls(spec, load_strategy(spec), compile_jev_schema(spec))


class DecisionPipeline:
    def __init__(
        self,
        runtimes: list[StrategyRuntime],
        jev: JevEngine,
        policy: PolicyEngine,
        portfolio: Portfolio,
        ledger: Any,
        calibration: CalibrationTracker | None = None,
    ):
        self.runtimes = runtimes
        self.jev = jev
        self.policy = policy
        self.portfolio = portfolio
        self.ledger = ledger
        self.calibration = calibration
        self.jev_latencies_ms: list[float] = []
        self.escalations_emitted = 0
        # Escalation is edge-triggered per package: it fires when confidence *drops* below the
        # floor (or the regime turns crisis), not on every bar that it stays there.
        self._escalated: dict[tuple[str, str], bool] = {}

    def decide(
        self,
        view: MarketView,
        ts: int,
        blocked_symbols: set[str] | frozenset = frozenset(),
        halted: set[str] | frozenset = frozenset(),
    ) -> list[PolicyResult]:
        nav = self.portfolio.nav()
        results: list[PolicyResult] = []
        for rt in self.runtimes:
            book = self.portfolio.book_positions(rt.spec.id)
            try:
                signals = rt.strategy.signals(StrategyContext(view, ts, book))
                rt.errors = 0
            except Exception as e:  # noqa: BLE001 - a strategy bug must not take down the loop
                rt.errors += 1
                self.ledger.append(Kind.ALERT, {"severity": "high", "message": f"{rt.spec.id} crashed: {type(e).__name__}: {e}", "consecutive": rt.errors}, ts=ts, ref=rt.spec.id)
                if rt.errors < MAX_CONSECUTIVE_STRATEGY_ERRORS or not book:
                    continue
                # Repeated failures while holding: exit rather than run unmanaged risk.
                signals = [Signal(rt.spec.id, p.key, p.legs, Direction.FLAT, 1.0, ts, "strategy failing repeatedly") for p in rt.spec.packages]
            for sig in signals:
                results.append(self._decide_one(rt, sig, view, ts, nav, blocked_symbols, rt.spec.id in halted))
        return results

    def _decide_one(self, rt: StrategyRuntime, sig: Signal, view: MarketView, ts: int, nav: float, blocked: set[str] | frozenset, halted: bool = False) -> PolicyResult:
        book_notional = {s: info.notional for s, info in self.portfolio.book_positions(rt.spec.id).items()}
        decision = None
        unavailable = "jev unavailable"
        if not sig.is_exit:
            bad = [l.symbol for l in sig.legs if l.symbol in blocked]
            thin = [l.symbol for l in sig.legs if (view.notional_volume(l.symbol, 1) or 0.0) < rt.spec.min_bar_notional_volume]
            if halted:
                unavailable = "strategy halted by an invalidation rule"
            elif bad:
                unavailable = f"data quality gate failed for {bad}"
            elif thin:
                unavailable = f"bar volume below spec minimum for {thin}"
            else:
                state = JevState(
                    strategy_id=rt.spec.id,
                    package=sig.package,
                    symbol=sig.legs[0].symbol,
                    ts=ts,
                    profile=rt.spec.jev.profile,
                    candidate_direction=sig.direction,
                    features={k: float(v) for k, v in sig.features.items() if isinstance(v, (int, float)) and math.isfinite(v)},
                    context={"thesis": sig.thesis},
                )
                try:
                    decision = self.jev.decide(state, rt.schema)
                    self.jev_latencies_ms.append(decision.latency_ms)
                    self.ledger.append(Kind.JEV_DECISION, {**decision.to_dict(), "state": state.text()}, ts=ts, ref=decision.decision_id)
                    if self.calibration is not None:
                        cost = rt.spec.costs.fee_bps_roundtrip + rt.spec.costs.slippage_bps_roundtrip
                        self.calibration.record(decision, sig, rt.spec.jev.calibration_horizon_bars, cost)
                except (JevUnavailable, JevSchemaError) as e:
                    unavailable = f"jev error ({type(e).__name__})"
                    self.ledger.append(Kind.JEV_ERROR, {"strategy_id": rt.spec.id, "package": sig.package, "error": str(e)}, ts=ts, ref=rt.spec.id)
        res = self.policy.evaluate(sig, decision, rt.spec, book_notional, nav, unavailable_reason=unavailable)
        self.ledger.append(Kind.POLICY, {**res.to_dict(), "thesis": sig.thesis}, ts=ts, ref=res.decision_id)
        key = (rt.spec.id, sig.package)
        was = self._escalated.get(key, False)
        self._escalated[key] = res.escalate
        if res.escalate and not was:
            self.escalations_emitted += 1
            self.ledger.append(
                Kind.ESCALATION,
                {"strategy_id": rt.spec.id, "package": sig.package, "reason": res.escalation_reason, "decision_id": res.decision_id, "action_taken": res.action.value},
                ts=ts,
                ref=rt.spec.id,
            )
        return res

"""Builds the trading stack. Backtest, paper and shadow all go through ``build_stack`` so the
code that is tested is the code that runs."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from hedgefund.calibration.recalibrate import CalibrationBundle, RecalibratedJev
from hedgefund.calibration.tracker import CalibrationTracker
from hedgefund.config import FundConfig
from hedgefund.core.clock import Clock
from hedgefund.core.ledger import Kind
from hedgefund.execution.engine import ExecutionEngine
from hedgefund.execution.venue import Venue
from hedgefund.jev.engine import BudgetedJev, JevEngine, ShadowJev
from hedgefund.jev.reference import ReferenceJev
from hedgefund.jev.remote import RemoteJev
from hedgefund.pipeline import DecisionPipeline, StrategyRuntime
from hedgefund.policy.engine import PolicyEngine
from hedgefund.portfolio.book import Portfolio
from hedgefund.risk.engine import RiskEngine
from hedgefund.risk.kill_switch import KillSwitch
from hedgefund.strategy.spec import StrategySpec


@dataclass
class Stack:
    config: FundConfig
    clock: Clock
    ledger: Any
    portfolio: Portfolio
    kill_switch: KillSwitch
    risk: RiskEngine
    policy: PolicyEngine
    execution: ExecutionEngine
    pipeline: DecisionPipeline
    calibration: CalibrationTracker
    venue: Venue


def make_jev(config: FundConfig, ledger: Any, clock: Clock) -> JevEngine:
    """Engine selection from config. Remote Jev is wrapped in a latency budget; if a shadow
    engine is configured, disagreements are logged to the ledger."""
    timeout = float(config.jev.get("timeout_ms", 250))

    def build(name: str | None) -> JevEngine | None:
        if name in (None, "", "none"):
            return None
        if name == "reference":
            return ReferenceJev()
        if name == "remote":
            return BudgetedJev(RemoteJev.from_env(timeout_ms=timeout), timeout)
        raise ValueError(f"unknown jev engine {name!r}")

    primary = build(config.jev.get("engine", "reference"))
    bundle_path = config.jev.get("calibration_bundle")
    if bundle_path:
        primary = RecalibratedJev(primary, CalibrationBundle.load(Path(bundle_path)))
    shadow = build(config.jev.get("shadow_engine"))
    if shadow is None:
        return primary

    def on_shadow(p, s, err):
        payload = {"primary": p.decision_id, "primary_version": p.model_version, "error": err}
        if s is not None:
            payload.update(
                shadow_version=s.model_version,
                agree_direction=p.direction == s.direction,
                agree_trade=p.should_trade == s.should_trade,
                agree_regime=p.regime == s.regime,
                confidence_delta=s.confidence - p.confidence,
            )
        ledger.append(Kind.JEV_SHADOW, payload, ts=clock.now_ms(), ref=p.decision_id)

    return ShadowJev(primary, shadow, on_shadow)


def build_stack(
    config: FundConfig,
    specs: list[StrategySpec],
    clock: Clock,
    ledger: Any,
    venue: Venue,
    jev: JevEngine | None = None,
    kill_switch_path: Path | None = None,
    order_ttl_ms: int | None = None,
) -> Stack:
    portfolio = Portfolio(config.starting_nav, config.instruments)
    ks = KillSwitch(kill_switch_path, ledger, clock)
    risk = RiskEngine(config.risk, config.instruments, ks, ledger, clock)
    policy = PolicyEngine(config.risk)
    execution = ExecutionEngine(
        venue,
        portfolio,
        risk,
        ledger,
        clock,
        config.instruments,
        ks,
        order_ttl_ms=order_ttl_ms,
        reconciliation_tolerance_pct=config.risk.reconciliation_tolerance_pct,
    )
    calibration = CalibrationTracker(ledger)
    known = set(config.instruments)
    runtimes = []
    for spec in specs:
        problems = spec.validate(known)
        if problems:
            raise ValueError(f"strategy {spec.id} invalid: {problems}")
        runtimes.append(StrategyRuntime.from_spec(spec))
    pipeline = DecisionPipeline(runtimes, jev or make_jev(config, ledger, clock), policy, portfolio, ledger, calibration)
    return Stack(config, clock, ledger, portfolio, ks, risk, policy, execution, pipeline, calibration, venue)

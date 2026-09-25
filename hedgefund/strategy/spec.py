"""Machine-readable strategy specification.

Every idea - whether drafted by Opus 5.5 or by the operator - must become a StrategySpec
before any code trades it. The spec states universe, timeframe, features, entry/exit rules,
expected holding period, risk budget, cost assumptions, liquidity requirements, the Jev
questions it needs, and the conditions under which it is invalidated.
"""

from __future__ import annotations

import enum
from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Any

import yaml

from hedgefund.config import JEV_CONFIDENCE_FLOOR
from hedgefund.core.ids import content_hash
from hedgefund.core.types import Direction, Leg, Regime


class Stage(str, enum.Enum):
    OBSERVATION = "observation"
    HYPOTHESIS = "hypothesis"
    DATA = "data"
    SIGNAL = "signal"
    BACKTEST = "backtest"
    COST_MODEL = "cost_model"
    STRESS_TEST = "stress_test"
    RISK_REVIEW = "risk_review"
    PAPER_TRADE = "paper_trade"
    SHADOW_MODE = "shadow_mode"
    LIVE = "live"
    RETIRED = "retired"

    @property
    def order(self) -> int:
        return STAGE_ORDER.index(self)


STAGE_ORDER = [
    Stage.OBSERVATION,
    Stage.HYPOTHESIS,
    Stage.DATA,
    Stage.SIGNAL,
    Stage.BACKTEST,
    Stage.COST_MODEL,
    Stage.STRESS_TEST,
    Stage.RISK_REVIEW,
    Stage.PAPER_TRADE,
    Stage.SHADOW_MODE,
    Stage.LIVE,
    Stage.RETIRED,
]

# Stages at which a strategy runs in the production loop (orders simulated or real).
RUNNABLE_STAGES = {Stage.PAPER_TRADE, Stage.SHADOW_MODE, Stage.LIVE}

EDGE_SOURCES = {"structural", "behavioral", "risk_premium", "informational", "liquidity_provision"}


@dataclass(frozen=True)
class Package:
    key: str
    legs: tuple[Leg, ...]


@dataclass(frozen=True)
class StrategyRisk:
    risk_per_trade_pct_nav: float
    max_package_notional_pct_nav: float
    rebalance_threshold: float = 0.25
    exit_on_crisis: bool = True
    # False: never add to an open position (setups with a fixed stop and target, partial exits).
    allow_scale_in: bool = True


@dataclass(frozen=True)
class CostAssumptions:
    fee_bps_roundtrip: float
    slippage_bps_roundtrip: float
    funding_note: str = ""


@dataclass(frozen=True)
class JevRequirements:
    profile: str
    allowed_regimes: tuple[Regime, ...]
    min_setup_quality: int
    min_liquidity_quality: int
    max_toxic_flow: int
    min_expected_edge: float
    min_confidence: float
    calibration_horizon_bars: int
    instructions: dict[str, str] = field(default_factory=dict)


@dataclass(frozen=True)
class InvalidationRule:
    metric: str
    op: str  # "<" | ">"
    threshold: float
    min_observations: int = 0
    action: str = "demote"  # demote -> back to paper_trade; halt -> stop new risk; retire

    def breached(self, value: float | None, observations: int) -> bool:
        if value is None or observations < self.min_observations:
            return False
        return value < self.threshold if self.op == "<" else value > self.threshold


@dataclass(frozen=True)
class StrategySpec:
    id: str
    name: str
    version: int
    owner_desk: str
    stage: Stage
    impl: str | None
    hypothesis: str
    edge_source: str
    universe: tuple[str, ...]
    packages: tuple[Package, ...]
    timeframe: str
    allowed_directions: tuple[Direction, ...]
    features: tuple[str, ...]
    entry_rules: tuple[str, ...]
    exit_rules: tuple[str, ...]
    expected_holding: str
    params: dict[str, float]
    risk: StrategyRisk
    costs: CostAssumptions
    min_bar_notional_volume: float
    jev: JevRequirements
    invalidation: tuple[InvalidationRule, ...]
    data_sources: tuple[str, ...] = ()
    failure_modes: tuple[str, ...] = ()
    capacity_usd: float = 0.0
    research_memo: str | None = None

    @property
    def spec_hash(self) -> str:
        return content_hash(spec_to_dict(self))

    def validate(self, known_symbols: set[str] | None = None) -> list[str]:
        p: list[str] = []
        if not self.id or not self.id.replace("_", "").isalnum():
            p.append("id must be alphanumeric/underscore")
        if self.edge_source not in EDGE_SOURCES:
            p.append(f"edge_source must be one of {sorted(EDGE_SOURCES)}")
        if not self.packages:
            p.append("at least one package required")
        for pkg in self.packages:
            if not pkg.legs:
                p.append(f"package {pkg.key}: no legs")
            for leg in pkg.legs:
                if leg.symbol not in self.universe:
                    p.append(f"package {pkg.key}: leg {leg.symbol} not in universe")
                if leg.weight == 0:
                    p.append(f"package {pkg.key}: zero-weight leg {leg.symbol}")
        if known_symbols is not None:
            unknown = set(self.universe) - known_symbols
            if unknown:
                p.append(f"unknown instruments: {sorted(unknown)}")
        if not self.allowed_directions or Direction.FLAT in self.allowed_directions:
            p.append("allowed_directions must be a non-empty subset of {long, short}")
        if not self.entry_rules or not self.exit_rules:
            p.append("entry_rules and exit_rules are required")
        if not 0 < self.risk.risk_per_trade_pct_nav <= 0.05:
            p.append("risk_per_trade_pct_nav must be in (0, 0.05]")
        if not 0 < self.risk.max_package_notional_pct_nav <= 1.0:
            p.append("max_package_notional_pct_nav must be in (0, 1]")
        j = self.jev
        if j.min_confidence < JEV_CONFIDENCE_FLOOR:
            p.append(f"jev.min_confidence below the {JEV_CONFIDENCE_FLOOR} floor")
        if not 0 <= j.min_setup_quality <= 3 or not 0 <= j.min_liquidity_quality <= 3 or not 0 <= j.max_toxic_flow <= 3:
            p.append("jev quality thresholds must be within 0-3")
        if not 0 <= j.min_expected_edge <= 100:
            p.append("jev.min_expected_edge must be within 0-100")
        if not j.allowed_regimes:
            p.append("jev.allowed_regimes required")
        if Regime.CRISIS in j.allowed_regimes:
            p.append("crisis may not be an allowed regime for new risk")
        if j.calibration_horizon_bars <= 0:
            p.append("jev.calibration_horizon_bars must be positive")
        if not self.invalidation:
            p.append("at least one invalidation rule is required")
        for rule in self.invalidation:
            if rule.op not in ("<", ">"):
                p.append(f"invalidation {rule.metric}: op must be < or >")
            if rule.action not in ("demote", "halt", "retire"):
                p.append(f"invalidation {rule.metric}: unknown action {rule.action}")
        if self.costs.fee_bps_roundtrip <= 0:
            p.append("costs.fee_bps_roundtrip must be positive (no free lunches)")
        return p


def spec_from_dict(raw: dict[str, Any]) -> StrategySpec:
    j = raw["jev"]
    return StrategySpec(
        id=raw["id"],
        name=raw["name"],
        version=int(raw.get("version", 1)),
        owner_desk=raw.get("owner_desk", "quant"),
        stage=Stage(raw.get("stage", "hypothesis")),
        impl=raw.get("impl"),
        hypothesis=" ".join(str(raw["hypothesis"]).split()),
        edge_source=raw["edge_source"],
        universe=tuple(raw["universe"]),
        packages=tuple(
            Package(p["key"], tuple(Leg(l["symbol"], float(l["weight"])) for l in p["legs"])) for p in raw["packages"]
        ),
        timeframe=raw["timeframe"],
        allowed_directions=tuple(Direction(d) for d in raw["allowed_directions"]),
        features=tuple(raw.get("features", ())),
        entry_rules=tuple(raw["entry_rules"]),
        exit_rules=tuple(raw["exit_rules"]),
        expected_holding=raw["expected_holding"],
        params={k: float(v) for k, v in (raw.get("params") or {}).items()},
        risk=StrategyRisk(**raw["risk"]),
        costs=CostAssumptions(**raw["costs"]),
        min_bar_notional_volume=float(raw.get("liquidity", {}).get("min_bar_notional_volume", 0.0)),
        jev=JevRequirements(
            profile=j["profile"],
            allowed_regimes=tuple(Regime(r) for r in j["allowed_regimes"]),
            min_setup_quality=int(j["min_setup_quality"]),
            min_liquidity_quality=int(j["min_liquidity_quality"]),
            max_toxic_flow=int(j["max_toxic_flow"]),
            min_expected_edge=float(j["min_expected_edge"]),
            min_confidence=float(j["min_confidence"]),
            calibration_horizon_bars=int(j["calibration_horizon_bars"]),
            instructions=dict(j.get("instructions") or {}),
        ),
        invalidation=tuple(InvalidationRule(**r) for r in raw["invalidation"]),
        data_sources=tuple(raw.get("data_sources", ())),
        failure_modes=tuple(" ".join(str(f).split()) for f in raw.get("failure_modes", ())),
        capacity_usd=float(raw.get("capacity_usd", 0.0)),
        research_memo=raw.get("research_memo"),
    )


def spec_to_dict(spec: StrategySpec) -> dict[str, Any]:
    return {
        "id": spec.id,
        "name": spec.name,
        "version": spec.version,
        "owner_desk": spec.owner_desk,
        "stage": spec.stage.value,
        "impl": spec.impl,
        "hypothesis": spec.hypothesis,
        "edge_source": spec.edge_source,
        "universe": list(spec.universe),
        "packages": [{"key": p.key, "legs": [{"symbol": l.symbol, "weight": l.weight} for l in p.legs]} for p in spec.packages],
        "timeframe": spec.timeframe,
        "allowed_directions": [d.value for d in spec.allowed_directions],
        "features": list(spec.features),
        "entry_rules": list(spec.entry_rules),
        "exit_rules": list(spec.exit_rules),
        "expected_holding": spec.expected_holding,
        "params": dict(spec.params),
        # allow_scale_in is omitted at its default so existing spec hashes are unchanged.
        "risk": {k: v for k, v in vars(spec.risk).items() if not (k == "allow_scale_in" and v)},
        "costs": vars(spec.costs).copy(),
        "liquidity": {"min_bar_notional_volume": spec.min_bar_notional_volume},
        "jev": {
            "profile": spec.jev.profile,
            "allowed_regimes": [r.value for r in spec.jev.allowed_regimes],
            "min_setup_quality": spec.jev.min_setup_quality,
            "min_liquidity_quality": spec.jev.min_liquidity_quality,
            "max_toxic_flow": spec.jev.max_toxic_flow,
            "min_expected_edge": spec.jev.min_expected_edge,
            "min_confidence": spec.jev.min_confidence,
            "calibration_horizon_bars": spec.jev.calibration_horizon_bars,
            "instructions": dict(spec.jev.instructions),
        },
        "invalidation": [vars(r).copy() for r in spec.invalidation],
        "data_sources": list(spec.data_sources),
        "failure_modes": list(spec.failure_modes),
        "capacity_usd": spec.capacity_usd,
        "research_memo": spec.research_memo,
    }


def load_spec(path: str | Path) -> StrategySpec:
    return spec_from_dict(yaml.safe_load(Path(path).read_text()))


def load_specs(directory: str | Path) -> list[StrategySpec]:
    return [load_spec(p) for p in sorted(Path(directory).glob("*.yaml"))]


def with_params(spec: StrategySpec, **overrides: float) -> StrategySpec:
    return replace(spec, params={**spec.params, **overrides})

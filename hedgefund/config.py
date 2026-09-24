"""Fund configuration. Risk limits live in their own file owned by the Risk Committee;
changing them requires a human approval recorded in the ledger (see ``ops.cli``)."""

from __future__ import annotations

from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Any

import yaml

from hedgefund.core.ids import content_hash
from hedgefund.core.types import Mode

# Hard floor: Jev confidence below this is never tradable and always escalates to Opus.
# Config may raise it, never lower it.
JEV_CONFIDENCE_FLOOR = 0.60

REPO_ROOT = Path(__file__).resolve().parent.parent


class ConfigError(ValueError):
    pass


@dataclass(frozen=True)
class Instrument:
    symbol: str
    kind: str  # "spot" | "perp"
    base: str
    quote: str
    cluster: str
    taker_fee_bps: float
    maker_fee_bps: float
    half_spread_bps: float
    impact_k_bps: float  # impact at 1% participation; scales with sqrt(participation / 1%)
    min_notional: float = 10.0
    venue_symbol: str | None = None

    @property
    def can_short(self) -> bool:
        return self.kind == "perp"

    @property
    def is_perp(self) -> bool:
        return self.kind == "perp"

    def estimated_slippage_bps(self, participation: float) -> float:
        participation = max(participation, 0.0)
        return self.half_spread_bps + self.impact_k_bps * (participation / 0.01) ** 0.5


@dataclass(frozen=True)
class RiskLimits:
    max_drawdown_pct: float
    drawdown_reduce_only_pct: float
    max_daily_loss_pct: float
    max_position_pct_nav: float
    max_gross_leverage: float
    max_net_leverage: float
    max_cluster_net_pct_nav: float
    max_participation: float
    max_slippage_bps: float
    max_orders_per_minute: int
    max_risk_per_trade_pct_nav: float
    reconciliation_tolerance_pct: float
    jev_min_confidence: float = JEV_CONFIDENCE_FLOOR
    min_order_fraction: float = 0.10

    def __post_init__(self) -> None:
        problems = []
        if not 0 < self.drawdown_reduce_only_pct < self.max_drawdown_pct < 1:
            problems.append("require 0 < drawdown_reduce_only_pct < max_drawdown_pct < 1")
        if not 0 < self.max_daily_loss_pct < 1:
            problems.append("max_daily_loss_pct must be in (0, 1)")
        if not 0 < self.max_position_pct_nav <= 1:
            problems.append("max_position_pct_nav must be in (0, 1]")
        if not 0 < self.max_net_leverage <= self.max_gross_leverage <= 5:
            problems.append("require 0 < max_net_leverage <= max_gross_leverage <= 5")
        if not 0 < self.max_participation <= 0.25:
            problems.append("max_participation must be in (0, 0.25]")
        if self.max_slippage_bps <= 0 or self.max_orders_per_minute <= 0:
            problems.append("slippage and order-rate limits must be positive")
        if not 0 < self.max_risk_per_trade_pct_nav <= 0.05:
            problems.append("max_risk_per_trade_pct_nav must be in (0, 0.05]")
        if self.jev_min_confidence < JEV_CONFIDENCE_FLOOR:
            problems.append(f"jev_min_confidence may not be below the {JEV_CONFIDENCE_FLOOR} floor")
        if problems:
            raise ConfigError("invalid risk limits: " + "; ".join(problems))


@dataclass(frozen=True)
class FundConfig:
    name: str
    mode: Mode
    base_currency: str
    starting_nav: float
    bar_interval: str
    instruments: dict[str, Instrument]
    risk: RiskLimits
    strategy_dir: Path
    var_dir: Path
    jev: dict[str, Any] = field(default_factory=dict)
    research: dict[str, Any] = field(default_factory=dict)
    schedule: dict[str, Any] = field(default_factory=dict)
    monitoring: dict[str, Any] = field(default_factory=dict)
    data: dict[str, Any] = field(default_factory=dict)
    source_hash: str = ""

    @property
    def ledger_path(self) -> Path:
        return self.var_dir / "ledger.db"

    @property
    def kill_switch_path(self) -> Path:
        return self.var_dir / "KILL_SWITCH"

    @property
    def reports_dir(self) -> Path:
        return self.var_dir / "reports"

    def instrument(self, symbol: str) -> Instrument:
        try:
            return self.instruments[symbol]
        except KeyError:
            raise ConfigError(f"unknown instrument {symbol!r}") from None

    def cluster_members(self) -> dict[str, list[str]]:
        out: dict[str, list[str]] = {}
        for inst in self.instruments.values():
            out.setdefault(inst.cluster, []).append(inst.symbol)
        return out

    def with_cost_multipliers(self, fee_mult: float = 1.0, slippage_mult: float = 1.0) -> "FundConfig":
        insts = {
            s: replace(
                i,
                taker_fee_bps=i.taker_fee_bps * fee_mult,
                maker_fee_bps=i.maker_fee_bps * fee_mult,
                half_spread_bps=i.half_spread_bps * slippage_mult,
                impact_k_bps=i.impact_k_bps * slippage_mult,
            )
            for s, i in self.instruments.items()
        }
        return replace(self, instruments=insts)


def _resolve(base: Path, p: str | Path) -> Path:
    p = Path(p)
    return p if p.is_absolute() else (base / p).resolve()


def load_risk_limits(path: str | Path) -> RiskLimits:
    raw = yaml.safe_load(Path(path).read_text())
    try:
        return RiskLimits(**raw)
    except TypeError as e:
        raise ConfigError(f"risk limits file {path}: {e}") from None


def load_config(path: str | Path | None = None) -> FundConfig:
    path = Path(path) if path else REPO_ROOT / "config" / "fund.yaml"
    raw = yaml.safe_load(path.read_text())
    base = path.parent.parent if path.parent.name == "config" else path.parent
    risk_path = _resolve(base, raw.get("risk_limits_file", "config/risk_limits.yaml"))
    risk = load_risk_limits(risk_path)
    instruments = {}
    for sym, spec in raw["instruments"].items():
        instruments[sym] = Instrument(symbol=sym, **spec)
    mode = Mode(raw.get("mode", "paper"))
    if mode is Mode.LIVE:
        raise ConfigError(
            "mode: live is not enabled in this codebase. Live trading requires a verified venue "
            "adapter, a completed shadow period and a recorded human approval (docs/BLUEPRINT.md §18)."
        )
    source_hash = content_hash({"fund": raw, "risk": yaml.safe_load(risk_path.read_text())})
    return FundConfig(
        name=raw["name"],
        mode=mode,
        base_currency=raw.get("base_currency", "USDT"),
        starting_nav=float(raw["starting_nav"]),
        bar_interval=raw.get("bar_interval", "4h"),
        instruments=instruments,
        risk=risk,
        strategy_dir=_resolve(base, raw.get("strategy_dir", "config/strategies")),
        var_dir=_resolve(base, raw.get("var_dir", "var")),
        jev=raw.get("jev", {}),
        research=raw.get("research", {}),
        schedule=raw.get("schedule", {}),
        monitoring=raw.get("monitoring", {}),
        data=raw.get("data", {}),
        source_hash=source_hash,
    )

"""Shared vocabulary. Every timestamp in the system is UTC epoch milliseconds."""

from __future__ import annotations

import enum
from dataclasses import dataclass, field


class Regime(str, enum.Enum):
    TRENDING = "trending"
    MEAN_REVERTING = "mean_reverting"
    HIGH_VOL = "high_vol"
    CRISIS = "crisis"


class Direction(str, enum.Enum):
    LONG = "long"
    SHORT = "short"
    FLAT = "flat"

    @property
    def sign(self) -> int:
        return {"long": 1, "short": -1, "flat": 0}[self.value]


class RiskState(str, enum.Enum):
    SAFE = "safe"
    REDUCE = "reduce"
    FLAT = "flat"


class Side(str, enum.Enum):
    BUY = "buy"
    SELL = "sell"

    @property
    def sign(self) -> int:
        return 1 if self is Side.BUY else -1


class Mode(str, enum.Enum):
    BACKTEST = "backtest"
    PAPER = "paper"
    SHADOW = "shadow"
    LIVE = "live"


@dataclass(frozen=True)
class Bar:
    """One OHLCV bar. ``ts`` is the bar CLOSE time: the bar is knowable at ``ts``."""

    ts: int
    open: float
    high: float
    low: float
    close: float
    volume: float  # base-asset units


@dataclass(frozen=True)
class Leg:
    symbol: str
    weight: float  # +1 = long when the package is long, -1 = short when the package is long


@dataclass(frozen=True)
class Signal:
    """A strategy's proposal for one package (a set of legs traded together).

    ``direction`` is the desired package direction. FLAT means "exit / do not hold".
    ``stop_distance_pct`` is the adverse package move the strategy treats as its stop;
    policy uses it for risk-based sizing. ``reduce_to`` (0 < x < 1), on a signal in the held
    direction, asks to keep only that fraction of the current position (partial take-profit);
    like an exit it is risk-reducing, so it never waits for Jev.
    """

    strategy_id: str
    package: str
    legs: tuple[Leg, ...]
    direction: Direction
    stop_distance_pct: float
    ts: int
    thesis: str
    features: dict[str, float] = field(default_factory=dict)
    reduce_to: float | None = None

    @property
    def is_exit(self) -> bool:
        return self.direction is Direction.FLAT

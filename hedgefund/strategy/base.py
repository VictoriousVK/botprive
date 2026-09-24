"""Strategy interface. A strategy only proposes (Signal); it never sizes, never sees limits,
and never talks to a venue. Exit logic must not depend on Jev."""

from __future__ import annotations

import importlib
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any

from hedgefund.core.timeutil import bars_per_day
from hedgefund.core.types import Direction, Signal
from hedgefund.data.series import MarketView
from hedgefund.portfolio.book import PositionInfo
from hedgefund.strategy.spec import Package, StrategySpec


@dataclass(frozen=True)
class StrategyContext:
    view: MarketView
    ts: int
    book: dict[str, PositionInfo]  # this strategy's open positions


class Strategy(ABC):
    def __init__(self, spec: StrategySpec):
        self.spec = spec
        self.p = spec.params
        self.bpd = bars_per_day(spec.timeframe)
        self.note = ""  # thesis of the last evaluation (shown on the dashboard)

    @property
    @abstractmethod
    def warmup_bars(self) -> int: ...

    @property
    def aux_timeframes(self) -> dict[str, int]:
        """Extra timeframes this strategy reads through ``view.aux(tf)``: {interval: bars}."""
        return {}

    @abstractmethod
    def evaluate(self, ctx: StrategyContext, pkg: Package) -> tuple:
        """Return (direction or None for 'no opinion while flat', stop_distance_pct, thesis, features)
        and optionally a fifth item, ``reduce_to``, for a partial exit of the held position."""

    # ---- optional hooks for strategies that manage a trade (stop/target levels, counters) ----
    def export_state(self) -> dict[str, Any] | None:
        """JSON-serialisable state the platform persists after every decision (None = stateless)."""
        return None

    def import_state(self, state: dict[str, Any]) -> None:  # noqa: B027 - optional hook
        """Restore what ``export_state`` returned (after a restart)."""
        return None

    def intrabar_exit(self, pkg: Package, book: dict[str, PositionInfo], bid: float, ask: float, ts: int) -> str | None:
        """Checked against live quotes between bar closes: a reason to exit now (stop or target
        touched), or None. Only called while this strategy holds the package."""
        return None

    def signals(self, ctx: StrategyContext) -> list[Signal]:
        out = []
        for pkg in self.spec.packages:
            if not all(ctx.view.has(l.symbol, self.warmup_bars) for l in pkg.legs):
                if self.holding(ctx, pkg):
                    # Data gap while holding: exit is the safe default.
                    out.append(self._signal(ctx, pkg, Direction.FLAT, 1.0, "insufficient data while holding", {}))
                continue
            res = self.evaluate(ctx, pkg)
            direction, stop, thesis, feats = res[:4]
            reduce_to = res[4] if len(res) > 4 else None
            self.note = thesis
            if direction is None:
                continue
            if direction is Direction.FLAT and not self.holding(ctx, pkg):
                continue
            out.append(self._signal(ctx, pkg, direction, stop, thesis, feats, reduce_to))
        return out

    def _signal(self, ctx: StrategyContext, pkg: Package, direction: Direction, stop: float, thesis: str, feats: dict[str, float], reduce_to: float | None = None) -> Signal:
        return Signal(self.spec.id, pkg.key, pkg.legs, direction, stop, ctx.ts, thesis, feats, reduce_to)

    # ---- helpers for subclasses ----
    @staticmethod
    def holding(ctx: StrategyContext, pkg: Package) -> bool:
        return any(l.symbol in ctx.book for l in pkg.legs)

    @staticmethod
    def held_direction(ctx: StrategyContext, pkg: Package) -> Direction:
        for l in pkg.legs:
            info = ctx.book.get(l.symbol)
            if info and info.qty:
                return Direction.LONG if info.qty * l.weight > 0 else Direction.SHORT
        return Direction.FLAT

    @staticmethod
    def entry_info(ctx: StrategyContext, pkg: Package) -> PositionInfo | None:
        return ctx.book.get(pkg.legs[0].symbol)

    def bars_held(self, ctx: StrategyContext, pkg: Package) -> int:
        info = self.entry_info(ctx, pkg)
        if info is None or info.opened_ts is None:
            return 0
        return int((ctx.ts - info.opened_ts) // ctx.view.data.interval_ms)


def load_strategy(spec: StrategySpec) -> Strategy:
    if not spec.impl:
        raise ValueError(f"{spec.id}: no implementation registered (impl is empty)")
    module, _, cls = spec.impl.partition(":")
    klass = getattr(importlib.import_module(module), cls)
    if not issubclass(klass, Strategy):
        raise TypeError(f"{spec.impl} is not a Strategy")
    return klass(spec)

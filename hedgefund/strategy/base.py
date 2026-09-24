"""Strategy interface. A strategy only proposes (Signal); it never sizes, never sees limits,
and never talks to a venue. Exit logic must not depend on Jev."""

from __future__ import annotations

import importlib
from abc import ABC, abstractmethod
from dataclasses import dataclass

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

    @property
    @abstractmethod
    def warmup_bars(self) -> int: ...

    @abstractmethod
    def evaluate(self, ctx: StrategyContext, pkg: Package) -> tuple[Direction | None, float, str, dict[str, float]]:
        """Return (direction or None for 'no opinion while flat', stop_distance_pct, thesis, features)."""

    def signals(self, ctx: StrategyContext) -> list[Signal]:
        out = []
        for pkg in self.spec.packages:
            if not all(ctx.view.has(l.symbol, self.warmup_bars) for l in pkg.legs):
                if self.holding(ctx, pkg):
                    # Data gap while holding: exit is the safe default.
                    out.append(self._signal(ctx, pkg, Direction.FLAT, 1.0, "insufficient data while holding", {}))
                continue
            direction, stop, thesis, feats = self.evaluate(ctx, pkg)
            if direction is None:
                continue
            if direction is Direction.FLAT and not self.holding(ctx, pkg):
                continue
            out.append(self._signal(ctx, pkg, direction, stop, thesis, feats))
        return out

    def _signal(self, ctx: StrategyContext, pkg: Package, direction: Direction, stop: float, thesis: str, feats: dict[str, float]) -> Signal:
        return Signal(self.spec.id, pkg.key, pkg.legs, direction, stop, ctx.ts, thesis, feats)

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

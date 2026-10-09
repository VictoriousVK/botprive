"""Generic single-asset mean reversion: fade stretched moves away from the rolling mean when
the price path is not trending. Works on any OHLC series (metals, indices, FX, crypto CFDs)."""

from __future__ import annotations

import math

from hedgefund.core.types import Direction
from hedgefund.data.features import standard_features
from hedgefund.strategy.base import Strategy, StrategyContext
from hedgefund.strategy.spec import Package


def price_zscore(closes: list[float]) -> tuple[float, float] | None:
    """z-score of ln(price) vs its window mean, and the path's efficiency ratio."""
    n = len(closes)
    if n < 10:
        return None
    lp = [math.log(c) for c in closes]
    mean = sum(lp) / n
    var = sum((x - mean) ** 2 for x in lp) / (n - 1)
    if var <= 0:
        return None
    path = sum(abs(lp[i] - lp[i - 1]) for i in range(1, n))
    er = abs(lp[-1] - lp[0]) / path if path > 0 else 0.0
    return (lp[-1] - mean) / math.sqrt(var), er


class ZScoreReversion(Strategy):
    @property
    def warmup_bars(self) -> int:
        return max(int(self.p["z_window_days"]), 60) * self.bpd + 2

    def evaluate(self, ctx: StrategyContext, pkg: Package):
        sym = pkg.legs[0].symbol
        f = standard_features(ctx.view, sym, self.bpd)
        zr = price_zscore(ctx.view.closes(sym, int(self.p["z_window_days"]) * self.bpd))
        if zr is None or "daily_vol" not in f:
            return (Direction.FLAT if self.holding(ctx, pkg) else None), 1.0, "insufficient history", f
        z, er = zr
        f["price_z"], f["price_er"] = z, er
        stop = max(self.p["min_stop_pct"], self.p["stop_vol_mult"] * f["daily_vol"])
        held = self.held_direction(ctx, pkg)
        if held is not Direction.FLAT:
            reverted = (held is Direction.LONG and z >= -self.p["exit_z"]) or (held is Direction.SHORT and z <= self.p["exit_z"])
            blown = abs(z) >= self.p["stop_z"]
            timed_out = self.bars_held(ctx, pkg) >= self.p["max_hold_days"] * self.bpd
            if reverted or blown or timed_out:
                why = "reverted" if reverted else "z stop" if blown else "time stop"
                return Direction.FLAT, stop, f"exit ({why}): z {z:+.2f}", f
            return held, stop, f"hold reversion: z {z:+.2f}", f
        if er < self.p["max_er"] and self.p["entry_z"] <= abs(z) < self.p["stop_z"]:
            d = Direction.SHORT if z > 0 else Direction.LONG
            return d, stop, f"enter {d.value}: z {z:+.2f}, ER {er:.2f}", f
        return None, stop, "", f

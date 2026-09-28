"""S4 - Stablecoin-liquidity regime tilt: hold spot BTC while stablecoin supply expands and
price is above its 200-day average."""

from __future__ import annotations

from hedgefund.core.types import Direction
from hedgefund.data.features import stablecoin_growth, standard_features
from hedgefund.strategy.base import Strategy, StrategyContext
from hedgefund.strategy.spec import Package


class StablecoinLiquidityTilt(Strategy):
    @property
    def warmup_bars(self) -> int:
        return int(self.p["sma_days"]) * self.bpd + 2

    def evaluate(self, ctx: StrategyContext, pkg: Package):
        sym = pkg.legs[0].symbol
        f = standard_features(ctx.view, sym, self.bpd)
        g = stablecoin_growth(ctx.view, int(self.p["growth_days"]))
        sma = ctx.view.sma(sym, int(self.p["sma_days"]) * self.bpd)
        if g is None or sma is None:
            return (Direction.FLAT if self.holding(ctx, pkg) else None), 1.0, "stablecoin/sma data unavailable", f
        f["stable_growth_30d"] = g
        f["close_vs_sma200"] = f["close"] / sma - 1.0
        stop = self.p["stop_distance_pct"]
        if self.holding(ctx, pkg):
            if g < self.p["exit_growth"] or f["close_vs_sma200"] < -self.p["sma_buffer"]:
                return Direction.FLAT, stop, f"exit: supply growth {g:+.2%}, vs SMA {f['close_vs_sma200']:+.1%}", f
            return Direction.LONG, stop, f"hold: supply growth {g:+.2%}", f
        if g >= self.p["entry_growth"] and f["close_vs_sma200"] > 0:
            return Direction.LONG, stop, f"enter: 30d stablecoin growth {g:+.2%}, above 200d SMA", f
        return None, stop, "", f

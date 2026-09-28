"""S5 - ETH/BTC relative value: fade stretched log-ratio deviations when the ratio is not trending."""

from __future__ import annotations

from hedgefund.core.types import Direction
from hedgefund.data.features import log_ratio_zscore, standard_features
from hedgefund.strategy.base import Strategy, StrategyContext
from hedgefund.strategy.spec import Package


class EthBtcRelativeValue(Strategy):
    @property
    def warmup_bars(self) -> int:
        return max(int(self.p["z_window_days"]) * self.bpd, 60 * self.bpd) + 2

    def evaluate(self, ctx: StrategyContext, pkg: Package):
        num, den = pkg.legs[0].symbol, pkg.legs[1].symbol
        f = standard_features(ctx.view, num, self.bpd)
        zr = log_ratio_zscore(ctx.view, num, den, int(self.p["z_window_days"]) * self.bpd)
        if zr is None:
            return (Direction.FLAT if self.holding(ctx, pkg) else None), 1.0, "ratio unavailable", f
        z, er = zr
        f["ratio_z"], f["ratio_er"] = z, er
        stop = self.p["stop_distance_pct"]
        held = self.held_direction(ctx, pkg)
        if held is not Direction.FLAT:
            # LONG package = long ETH / short BTC, entered when z is very negative.
            reverted = (held is Direction.LONG and z >= -self.p["exit_z"]) or (held is Direction.SHORT and z <= self.p["exit_z"])
            blown = abs(z) >= self.p["stop_z"]
            timed_out = self.bars_held(ctx, pkg) >= self.p["max_hold_days"] * self.bpd
            if reverted or blown or timed_out:
                why = "reverted" if reverted else "z stop" if blown else "time stop"
                return Direction.FLAT, stop, f"exit ({why}): z {z:+.2f}", f
            return held, stop, f"hold RV: z {z:+.2f}", f
        if er < self.p["max_ratio_er"] and abs(z) >= self.p["entry_z"] and abs(z) < self.p["stop_z"]:
            d = Direction.SHORT if z > 0 else Direction.LONG
            return d, stop, f"enter {d.value}: ratio z {z:+.2f}, ratio ER {er:.2f}", f
        return None, stop, "", f

"""S2 - Multi-horizon time-series momentum on BTC/ETH perps, volatility-scaled stops."""

from __future__ import annotations

from hedgefund.core.types import Direction
from hedgefund.data.features import standard_features
from hedgefund.strategy.base import Strategy, StrategyContext
from hedgefund.strategy.spec import Package


def _sgn(x: float) -> int:
    return 1 if x > 0 else -1 if x < 0 else 0


class TimeSeriesMomentum(Strategy):
    @property
    def warmup_bars(self) -> int:
        return int(self.p["lookback_long_days"]) * self.bpd + 2

    def evaluate(self, ctx: StrategyContext, pkg: Package):
        sym = pkg.legs[0].symbol
        f = standard_features(ctx.view, sym, self.bpd)
        moms = [ctx.view.momentum(sym, int(self.p[k]) * self.bpd) for k in ("lookback_short_days", "lookback_mid_days", "lookback_long_days")]
        if any(m is None for m in moms) or "daily_vol" not in f:
            return (Direction.FLAT if self.holding(ctx, pkg) else None), 1.0, "insufficient history", f
        votes = sum(_sgn(m) for m in moms)
        f["trend_votes"] = float(votes)
        stop = max(self.p["min_stop_pct"], self.p["stop_vol_mult"] * f["daily_vol"] * self.p["stop_horizon_days"] ** 0.5)
        held = self.held_direction(ctx, pkg)
        if held is not Direction.FLAT:
            if _sgn(votes) != held.sign:
                return Direction.FLAT, stop, f"exit: trend votes {votes:+d} against {held.value}", f
            return held, stop, f"hold trend: votes {votes:+d}", f
        if abs(votes) == 3 and f.get("er_10d", 0.0) >= self.p["min_efficiency"]:
            d = Direction.LONG if votes > 0 else Direction.SHORT
            return d, stop, f"enter {d.value}: all horizons agree, ER {f['er_10d']:.2f}", f
        return None, stop, "", f

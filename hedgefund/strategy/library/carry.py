"""S1 - Delta-neutral perpetual funding carry (long spot / short perp)."""

from __future__ import annotations

from hedgefund.core.types import Direction
from hedgefund.data.features import standard_features
from hedgefund.strategy.base import Strategy, StrategyContext
from hedgefund.strategy.spec import Package


class FundingCarry(Strategy):
    @property
    def warmup_bars(self) -> int:
        return 60 * self.bpd + 2

    def evaluate(self, ctx: StrategyContext, pkg: Package):
        spot, perp = pkg.legs[0].symbol, pkg.legs[1].symbol
        f = standard_features(ctx.view, spot, self.bpd)
        s_px, p_px = ctx.view.last_close(spot), ctx.view.last_close(perp)
        if "funding_avg_3d_ann" not in f or not s_px or not p_px:
            return (Direction.FLAT if self.holding(ctx, pkg) else None), 1.0, "funding data unavailable", f
        f["basis"] = p_px / s_px - 1.0
        fa, streak, basis = f["funding_avg_3d_ann"], f["funding_neg_streak"], f["basis"]
        stop = self.p["stop_distance_pct"]
        if self.holding(ctx, pkg):
            if fa <= self.p["exit_funding_ann"] or streak >= self.p["exit_neg_prints"] or abs(basis) >= self.p["basis_stop"]:
                return Direction.FLAT, stop, f"exit: funding {fa:.1%} ann, neg streak {streak:.0f}, basis {basis:.2%}", f
            return Direction.LONG, stop, f"hold carry: funding {fa:.1%} ann", f
        if fa >= self.p["entry_funding_ann"] and f["funding_last_ann"] > 0 and abs(basis) < self.p["basis_stop"] / 2:
            return Direction.LONG, stop, f"enter carry: 3d funding {fa:.1%} ann, basis {basis:.2%}", f
        return None, stop, "", f

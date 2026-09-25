"""S3 - Liquidation-cascade reversion: buy forced selling after the flow has cleared."""

from __future__ import annotations

from hedgefund.core.types import Direction
from hedgefund.data.features import standard_features
from hedgefund.strategy.base import Strategy, StrategyContext
from hedgefund.strategy.spec import Package


class LiquidationReversion(Strategy):
    @property
    def warmup_bars(self) -> int:
        return 60 * self.bpd + 2

    def evaluate(self, ctx: StrategyContext, pkg: Package):
        sym = pkg.legs[0].symbol
        f = standard_features(ctx.view, sym, self.bpd)
        if "daily_vol" not in f or "ret_z_1d" not in f:
            return (Direction.FLAT if self.holding(ctx, pkg) else None), 1.0, "insufficient history", f
        dv = f["daily_vol"]
        stop = self.p["stop_vol_mult"] * dv
        if self.holding(ctx, pkg):
            info = self.entry_info(ctx, pkg)
            px = f["close"]
            move = px / info.avg_price - 1.0 if info and info.avg_price else 0.0
            held = self.bars_held(ctx, pkg)
            if move >= self.p["take_profit_vol_mult"] * dv:
                return Direction.FLAT, stop, f"take profit {move:+.2%}", f
            if move <= -stop:
                return Direction.FLAT, stop, f"stop loss {move:+.2%}", f
            if held >= self.p["max_hold_bars"]:
                return Direction.FLAT, stop, f"time stop after {held} bars", f
            return Direction.LONG, stop, f"hold reversion {move:+.2%}", f
        oi = f.get("oi_chg_1d")
        fund = f.get("funding_last_ann")
        if oi is None or fund is None:
            return None, stop, "", f
        if f["ret_z_1d"] <= -self.p["min_drop_z"] and oi <= -self.p["min_oi_flush"] and fund <= self.p["max_funding_ann"]:
            return Direction.LONG, stop, f"cascade: 1d z {f['ret_z_1d']:.1f}, OI {oi:+.1%}, funding {fund:.1%}", f
        return None, stop, "", f

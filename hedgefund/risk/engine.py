"""Hard risk layer. Deterministic; inputs are proposed orders and portfolio state only.

Guarantees:
  * Orders that strictly reduce exposure are always allowed (even with the kill switch on).
  * Anything that adds risk must satisfy every limit; otherwise the whole package is scaled
    down uniformly (legs stay hedged) to the largest compliant size, or rejected if that is
    below ``min_order_fraction`` of the request.
  * A limit that is already breached (e.g. after a price move) blocks any order that would
    worsen it, but does not block orders that leave it unchanged or improve it.
  * Drawdown >= max -> kill switch (latching). Drawdown >= soft limit -> reduce-only mode.
    Daily loss >= max -> no new risk until the next UTC day.
"""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from typing import Any

from hedgefund.config import Instrument, RiskLimits
from hedgefund.core.clock import Clock
from hedgefund.core.ledger import Kind
from hedgefund.core.timeutil import utc_day
from hedgefund.risk.kill_switch import KillSwitch

EPS = 1e-9


@dataclass(frozen=True)
class OrderRequest:
    strategy_id: str
    package: str
    symbol: str
    qty: float  # signed: + buy, - sell
    ref_price: float
    decision_id: str | None = None

    @property
    def notional(self) -> float:
        return abs(self.qty * self.ref_price)


@dataclass(frozen=True)
class RiskVerdict:
    approved: bool
    scale: float
    requests: tuple[OrderRequest, ...]
    violations: tuple[str, ...]
    reduce_only: bool

    def to_dict(self) -> dict:
        return {
            "approved": self.approved,
            "scale": self.scale,
            "reduce_only": self.reduce_only,
            "violations": list(self.violations),
            "orders": [{"symbol": r.symbol, "qty": r.qty, "ref_price": r.ref_price} for r in self.requests],
        }


class RiskEngine:
    def __init__(self, limits: RiskLimits, instruments: dict[str, Instrument], kill_switch: KillSwitch, ledger: Any, clock: Clock):
        self.limits = limits
        self.instruments = instruments
        self.kill_switch = kill_switch
        self.ledger = ledger
        self.clock = clock
        self.hwm: float | None = None
        self.day: int | None = None
        self.day_start_nav: float | None = None
        self.halted_day: int | None = None
        self.reduce_only_mode = False
        self._order_times: deque[int] = deque()

    # ---------------- portfolio-level state ----------------
    def update_nav(self, nav: float, ts: int) -> None:
        L = self.limits
        if nav <= 0:
            self.kill_switch.engage(f"NAV non-positive ({nav:.2f})", "risk_engine")
            return
        self.hwm = nav if self.hwm is None else max(self.hwm, nav)
        day = utc_day(ts)
        if day != self.day:
            if self.halted_day is not None and self.halted_day != day:
                self._event("daily_halt_lifted", {"day": day}, ts)
                self.halted_day = None
            self.day, self.day_start_nav = day, nav
        dd = 1.0 - nav / self.hwm
        if dd >= L.max_drawdown_pct and not self.kill_switch.engaged:
            self.kill_switch.engage(f"drawdown {dd:.2%} >= max {L.max_drawdown_pct:.2%}", "risk_engine")
        ro = dd >= L.drawdown_reduce_only_pct
        if ro != self.reduce_only_mode:
            self.reduce_only_mode = ro
            self._event("reduce_only_mode", {"on": ro, "drawdown": dd}, ts)
        daily = nav / self.day_start_nav - 1.0 if self.day_start_nav else 0.0
        if daily <= -L.max_daily_loss_pct and self.halted_day != day:
            self.halted_day = day
            self._event("daily_loss_halt", {"daily_return": daily}, ts)

    def drawdown(self, nav: float) -> float:
        return 1.0 - nav / self.hwm if self.hwm else 0.0

    def new_risk_block(self) -> str | None:
        if self.kill_switch.engaged:
            return f"kill switch engaged: {self.kill_switch.reason}"
        if self.halted_day is not None:
            return "daily loss limit hit: no new risk until next UTC day"
        if self.reduce_only_mode:
            return "drawdown soft limit: reduce-only mode"
        return None

    # ---------------- order checks ----------------
    def check(
        self,
        requests: list[OrderRequest],
        positions: dict[str, float],
        marks: dict[str, float],
        nav: float,
        liquidity: dict[str, float],
    ) -> RiskVerdict:
        now = self.clock.now_ms()
        if not requests:
            return RiskVerdict(True, 1.0, (), (), True)
        unknown = [r.symbol for r in requests if r.symbol not in self.instruments]
        if unknown:
            return self._record(RiskVerdict(False, 0.0, (), (f"unknown instruments {unknown}",), False), requests, now)

        if self._reduces(requests, positions):
            v = RiskVerdict(True, 1.0, tuple(requests), (), True)
            self._note_orders(now, len(requests))
            return self._record(v, requests, now)

        block = self.new_risk_block()
        if block:
            return self._record(RiskVerdict(False, 0.0, (), (block,), False), requests, now)

        while self._order_times and now - self._order_times[0] > 60_000:
            self._order_times.popleft()
        if len(self._order_times) + len(requests) > self.limits.max_orders_per_minute:
            return self._record(RiskVerdict(False, 0.0, (), ("order rate limit",), False), requests, now)

        prices = {r.symbol: marks.get(r.symbol) or r.ref_price for r in requests}
        base = self._metrics(0.0, requests, positions, marks, prices)

        def violations(s: float) -> list[str]:
            return self._violations(s, requests, positions, marks, prices, nav, liquidity, base)

        v1 = violations(1.0)
        scale = 1.0
        if v1:
            lo, hi = 0.0, 1.0
            for _ in range(30):
                mid = (lo + hi) / 2
                if violations(mid):
                    hi = mid
                else:
                    lo = mid
            scale = lo
            if scale < self.limits.min_order_fraction:
                return self._record(RiskVerdict(False, 0.0, (), tuple(v1), False), requests, now)
        scaled = tuple(
            OrderRequest(r.strategy_id, r.package, r.symbol, r.qty * scale, r.ref_price, r.decision_id) for r in requests
        )
        small = [r.symbol for r in scaled if r.notional < self.instruments[r.symbol].min_notional]
        if small:
            return self._record(RiskVerdict(False, 0.0, (), (f"below min notional: {small}",) + tuple(v1), False), requests, now)
        self._note_orders(now, len(scaled))
        notes = tuple(f"clipped to {scale:.2%}: {v}" for v in v1)
        return self._record(RiskVerdict(True, scale, scaled, notes, False), requests, now)

    # ---------------- internals ----------------
    @staticmethod
    def _reduces(requests: list[OrderRequest], positions: dict[str, float]) -> bool:
        for r in requests:
            p = positions.get(r.symbol, 0.0)
            q = p + r.qty
            if abs(q) > abs(p) + EPS or q * p < -EPS:
                return False
        return True

    def _metrics(self, s: float, requests: list[OrderRequest], positions: dict[str, float], marks: dict[str, float], prices: dict[str, float]) -> dict[str, float]:
        proj = dict(positions)
        for r in requests:
            proj[r.symbol] = proj.get(r.symbol, 0.0) + s * r.qty
        m: dict[str, float] = {}
        gross = net = 0.0
        clusters: dict[str, float] = {}
        for sym, q in proj.items():
            px = prices.get(sym) or marks.get(sym, 0.0)
            n = q * px
            gross += abs(n)
            net += n
            c = self.instruments[sym].cluster if sym in self.instruments else "unknown"
            clusters[c] = clusters.get(c, 0.0) + n
            m[f"qty:{sym}"] = q
            m[f"pos:{sym}"] = abs(n)
        m["gross"], m["net"] = gross, abs(net)
        for c, v in clusters.items():
            m[f"cluster:{c}"] = abs(v)
        return m

    def _violations(self, s, requests, positions, marks, prices, nav, liquidity, base) -> list[str]:
        L = self.limits
        m = self._metrics(s, requests, positions, marks, prices)
        out: list[str] = []

        def worsens(key: str, cap: float) -> bool:
            return m.get(key, 0.0) > cap + EPS and m.get(key, 0.0) > base.get(key, 0.0) + EPS

        for r in requests:
            inst = self.instruments[r.symbol]
            if m[f"qty:{r.symbol}"] < -EPS and not inst.can_short and m[f"qty:{r.symbol}"] < base.get(f"qty:{r.symbol}", 0.0) - EPS:
                out.append(f"{r.symbol}: spot instrument cannot go short")
            if worsens(f"pos:{r.symbol}", L.max_position_pct_nav * nav):
                out.append(f"{r.symbol}: position {m[f'pos:{r.symbol}'] / nav:.1%} NAV > {L.max_position_pct_nav:.0%}")
            liq = liquidity.get(r.symbol, 0.0)
            order_notional = abs(s * r.qty) * prices[r.symbol]
            if liq <= 0:
                out.append(f"{r.symbol}: no liquidity estimate")
                continue
            part = order_notional / liq
            if part > L.max_participation + EPS:
                out.append(f"{r.symbol}: participation {part:.2%} > {L.max_participation:.2%}")
            slip = inst.estimated_slippage_bps(part)
            if slip > L.max_slippage_bps + EPS:
                out.append(f"{r.symbol}: est. slippage {slip:.1f}bps > {L.max_slippage_bps}bps")
        if worsens("gross", L.max_gross_leverage * nav):
            out.append(f"gross leverage {m['gross'] / nav:.2f}x > {L.max_gross_leverage}x")
        if worsens("net", L.max_net_leverage * nav):
            out.append(f"net leverage {m['net'] / nav:.2f}x > {L.max_net_leverage}x")
        for key in [k for k in m if k.startswith("cluster:")]:
            if worsens(key, L.max_cluster_net_pct_nav * nav):
                out.append(f"{key} net {m[key] / nav:.1%} NAV > {L.max_cluster_net_pct_nav:.0%}")
        return out

    def _note_orders(self, now: int, n: int) -> None:
        self._order_times.extend([now] * n)

    def _event(self, kind: str, payload: dict, ts: int) -> None:
        self.ledger.append(Kind.RISK_EVENT, {"event": kind, **payload}, ts=ts)

    def _record(self, verdict: RiskVerdict, requests: list[OrderRequest], ts: int) -> RiskVerdict:
        ref = requests[0].decision_id if requests else None
        self.ledger.append(
            Kind.RISK_VERDICT,
            {**verdict.to_dict(), "requested": [{"symbol": r.symbol, "qty": r.qty, "strategy": r.strategy_id, "package": r.package} for r in requests]},
            ts=ts,
            ref=ref,
        )
        return verdict

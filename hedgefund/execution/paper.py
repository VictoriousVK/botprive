"""Paper venue: realistic-enough fills for paper trading and backtests.

Fill model (assumptions, documented so they can be falsified in shadow mode):
  * Market orders fill at the reference price +/- (half spread + impact), where impact grows
    with sqrt(participation) - see Instrument.estimated_slippage_bps.
  * Per step, at most ``max_participation_per_step`` of the liquidity estimate can fill;
    the rest remains open and continues filling on later steps (partial fills).
  * Limit orders fill only when marketable against the reference price +/- half spread.
  * Optional fault injection (transient errors, lost acks, rejects) exercises the retry,
    query-before-resubmit and reconciliation paths.
Submission is idempotent on client_order_id, as on real venues.
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field

from hedgefund.config import Instrument
from hedgefund.core.clock import Clock
from hedgefund.core.types import Side
from hedgefund.execution.orders import TERMINAL, Fill, Order, OrderStatus
from hedgefund.execution.venue import PermanentVenueError, TransientVenueError, VenueOrderState, VenueTimeout


@dataclass
class _PaperOrder:
    cid: str
    symbol: str
    side: Side
    qty: float
    order_type: str
    limit_price: float | None
    status: OrderStatus = OrderStatus.ACKED
    filled: float = 0.0
    avg: float = 0.0
    reason: str | None = None
    fills: list[Fill] = field(default_factory=list)

    @property
    def remaining(self) -> float:
        return max(self.qty - self.filled, 0.0)


class PaperVenue:
    name = "paper"

    def __init__(
        self,
        instruments: dict[str, Instrument],
        clock: Clock,
        seed: int = 0,
        max_participation_per_step: float = 0.05,
        transient_error_prob: float = 0.0,
        timeout_prob: float = 0.0,
        reject_prob: float = 0.0,
    ):
        self.instruments = instruments
        self.clock = clock
        self.rng = random.Random(seed)
        self.max_participation_per_step = max_participation_per_step
        self.transient_error_prob = transient_error_prob
        self.timeout_prob = timeout_prob
        self.reject_prob = reject_prob
        self._orders: dict[str, _PaperOrder] = {}
        self._market: dict[str, tuple[float, float]] = {}
        self._budget: dict[str, float] = {}
        self._positions: dict[str, float] = {}
        self._outbox: list[Fill] = []
        self._seq = 0

    # ---- market data ----
    def set_market(self, symbol: str, price: float, liquidity_notional: float) -> None:
        self._market[symbol] = (price, liquidity_notional)
        self._budget[symbol] = max(liquidity_notional, 0.0) * self.max_participation_per_step

    def step(self) -> None:
        for o in list(self._orders.values()):
            if o.status not in TERMINAL:
                self._try_fill(o)

    # ---- venue API ----
    def submit(self, order: Order) -> VenueOrderState:
        existing = self._orders.get(order.client_order_id)
        if existing is not None:
            return self._state(existing)
        if order.symbol not in self.instruments:
            raise PermanentVenueError(f"unknown symbol {order.symbol}")
        if order.symbol not in self._market:
            raise TransientVenueError(f"no market for {order.symbol}")
        if self.rng.random() < self.transient_error_prob:
            raise TransientVenueError("simulated HTTP 503")
        o = _PaperOrder(order.client_order_id, order.symbol, order.side, order.qty, order.order_type, order.limit_price)
        self._orders[o.cid] = o
        if self.rng.random() < self.reject_prob:
            o.status, o.reason = OrderStatus.REJECTED, "simulated venue reject"
            return self._state(o)
        self._try_fill(o)
        if self.rng.random() < self.timeout_prob:
            raise VenueTimeout("simulated lost acknowledgement (order IS live at venue)")
        return self._state(o)

    def cancel(self, client_order_id: str) -> VenueOrderState | None:
        o = self._orders.get(client_order_id)
        if o is None:
            return None
        if o.status not in TERMINAL:
            o.status = OrderStatus.CANCELED
        return self._state(o)

    def get_order(self, client_order_id: str) -> VenueOrderState | None:
        o = self._orders.get(client_order_id)
        return self._state(o) if o else None

    def positions(self) -> dict[str, float]:
        return {s: q for s, q in self._positions.items() if abs(q) > 1e-12}

    def drain_fills(self) -> list[Fill]:
        out, self._outbox = self._outbox, []
        return out

    def restore_positions(self, positions: dict[str, float]) -> None:
        self._positions = dict(positions)

    # ---- internals ----
    def _state(self, o: _PaperOrder) -> VenueOrderState:
        return VenueOrderState(o.cid, o.status, o.filled, o.avg, venue_order_id=f"paper-{o.cid}", reason=o.reason, fills=list(o.fills))

    def _try_fill(self, o: _PaperOrder) -> None:
        price, liq = self._market.get(o.symbol, (0.0, 0.0))
        budget = self._budget.get(o.symbol, 0.0)
        if price <= 0 or budget <= 0 or o.remaining <= 0:
            return
        inst = self.instruments[o.symbol]
        sign = o.side.sign
        if o.order_type == "limit" and o.limit_price is not None:
            touch = price * (1 + sign * inst.half_spread_bps / 1e4)
            if (sign > 0 and o.limit_price < touch) or (sign < 0 and o.limit_price > touch):
                return  # resting
        q = min(o.remaining, budget / price)
        if q <= 0:
            return
        participation = q * price / liq if liq > 0 else 1.0
        px = price * (1 + sign * inst.estimated_slippage_bps(participation) / 1e4)
        if o.order_type == "limit" and o.limit_price is not None:
            px = min(px, o.limit_price) if sign > 0 else max(px, o.limit_price)
        fee_bps = inst.taker_fee_bps if o.order_type == "market" else inst.maker_fee_bps
        self._seq += 1
        fill = Fill(f"pf-{self._seq}", o.cid, o.symbol, o.side, q, px, q * px * fee_bps / 1e4, self.clock.now_ms(), "taker" if o.order_type == "market" else "maker")
        o.avg = (o.avg * o.filled + px * q) / (o.filled + q)
        o.filled += q
        o.fills.append(fill)
        o.status = OrderStatus.FILLED if o.remaining <= 1e-12 * max(1.0, o.qty) else OrderStatus.PARTIALLY_FILLED
        self._budget[o.symbol] = budget - q * price
        self._positions[o.symbol] = self._positions.get(o.symbol, 0.0) + sign * q
        self._outbox.append(fill)

"""Order model and state machine. Illegal transitions raise - they indicate a bug or a venue
inconsistency and must never be silently absorbed."""

from __future__ import annotations

import enum
from dataclasses import dataclass, field

from hedgefund.core.types import Side


class OrderStatus(str, enum.Enum):
    NEW = "new"
    SUBMITTED = "submitted"
    ACKED = "acked"
    PARTIALLY_FILLED = "partially_filled"
    FILLED = "filled"
    CANCELED = "canceled"
    REJECTED = "rejected"
    EXPIRED = "expired"


TERMINAL = {OrderStatus.FILLED, OrderStatus.CANCELED, OrderStatus.REJECTED, OrderStatus.EXPIRED}

_ALLOWED: dict[OrderStatus, set[OrderStatus]] = {
    OrderStatus.NEW: {OrderStatus.SUBMITTED, OrderStatus.REJECTED},
    OrderStatus.SUBMITTED: {OrderStatus.ACKED, OrderStatus.PARTIALLY_FILLED, OrderStatus.FILLED, OrderStatus.REJECTED, OrderStatus.CANCELED, OrderStatus.EXPIRED},
    OrderStatus.ACKED: {OrderStatus.PARTIALLY_FILLED, OrderStatus.FILLED, OrderStatus.CANCELED, OrderStatus.EXPIRED},
    OrderStatus.PARTIALLY_FILLED: {OrderStatus.PARTIALLY_FILLED, OrderStatus.FILLED, OrderStatus.CANCELED, OrderStatus.EXPIRED},
}


class IllegalTransition(RuntimeError):
    pass


@dataclass(frozen=True)
class Fill:
    fill_id: str
    client_order_id: str
    symbol: str
    side: Side
    qty: float  # positive
    price: float
    fee: float
    ts: int
    liquidity: str = "taker"

    @property
    def signed_qty(self) -> float:
        return self.qty * self.side.sign


@dataclass
class Order:
    client_order_id: str
    strategy_id: str
    package: str
    decision_id: str | None
    model_version: str | None
    symbol: str
    side: Side
    qty: float  # positive
    order_type: str  # "market" | "limit"
    expected_price: float
    created_ts: int
    limit_price: float | None = None
    reduce_only: bool = False
    status: OrderStatus = OrderStatus.NEW
    filled_qty: float = 0.0
    avg_fill_price: float = 0.0
    fees: float = 0.0
    venue_order_id: str | None = None
    reject_reason: str | None = None
    history: list[tuple[int, str, str]] = field(default_factory=list)

    @property
    def remaining(self) -> float:
        return max(self.qty - self.filled_qty, 0.0)

    @property
    def is_terminal(self) -> bool:
        return self.status in TERMINAL

    @property
    def slippage_bps(self) -> float | None:
        if self.filled_qty <= 0 or self.expected_price <= 0:
            return None
        return (self.avg_fill_price / self.expected_price - 1.0) * 1e4 * self.side.sign

    def transition(self, new: OrderStatus, ts: int, note: str = "") -> None:
        if new == self.status and new is not OrderStatus.PARTIALLY_FILLED:
            return
        if new not in _ALLOWED.get(self.status, set()):
            raise IllegalTransition(f"{self.client_order_id}: {self.status.value} -> {new.value}")
        self.status = new
        self.history.append((ts, new.value, note))

    def apply_fill(self, fill: Fill) -> None:
        if fill.qty <= 0 or fill.qty > self.remaining + 1e-9:
            raise IllegalTransition(f"{self.client_order_id}: fill {fill.qty} exceeds remaining {self.remaining}")
        new_filled = self.filled_qty + fill.qty
        self.avg_fill_price = (self.avg_fill_price * self.filled_qty + fill.price * fill.qty) / new_filled
        self.filled_qty = new_filled
        self.fees += fill.fee
        done = self.remaining <= 1e-9 * max(1.0, self.qty)
        self.transition(OrderStatus.FILLED if done else OrderStatus.PARTIALLY_FILLED, fill.ts)

    def to_dict(self) -> dict:
        return {
            "client_order_id": self.client_order_id,
            "strategy_id": self.strategy_id,
            "package": self.package,
            "decision_id": self.decision_id,
            "model_version": self.model_version,
            "symbol": self.symbol,
            "side": self.side.value,
            "qty": self.qty,
            "order_type": self.order_type,
            "limit_price": self.limit_price,
            "reduce_only": self.reduce_only,
            "expected_price": self.expected_price,
            "status": self.status.value,
            "filled_qty": self.filled_qty,
            "avg_fill_price": self.avg_fill_price,
            "actual_price": self.avg_fill_price if self.filled_qty else None,
            "slippage_bps": self.slippage_bps,
            "fees": self.fees,
            "venue_order_id": self.venue_order_id,
            "reject_reason": self.reject_reason,
            "created_ts": self.created_ts,
        }

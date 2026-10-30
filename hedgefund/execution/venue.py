"""Venue interface. A live adapter must implement exactly this surface and pass
tests/test_execution.py's contract tests against the real venue's testnet before the
LIVE gate can be cleared (``shadow.venue_adapter_verified``)."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol

from hedgefund.execution.orders import Fill, Order, OrderStatus


class VenueError(RuntimeError):
    pass


class TransientVenueError(VenueError):
    """Safe to retry with the same client order id (e.g. 5xx, 429, connection reset)."""


class VenueTimeout(TransientVenueError):
    """Outcome unknown: the order may or may not exist. Query before resubmitting."""


class PermanentVenueError(VenueError):
    """Do not retry (e.g. insufficient balance, invalid symbol, filter violation)."""


@dataclass
class VenueOrderState:
    client_order_id: str
    status: OrderStatus
    filled_qty: float
    avg_price: float
    venue_order_id: str | None = None
    reason: str | None = None
    fills: list[Fill] = field(default_factory=list)


class Venue(Protocol):
    name: str

    def submit(self, order: Order) -> VenueOrderState: ...

    def cancel(self, client_order_id: str) -> VenueOrderState | None: ...

    def get_order(self, client_order_id: str) -> VenueOrderState | None: ...

    def positions(self) -> dict[str, float]: ...

    def drain_fills(self) -> list[Fill]: ...

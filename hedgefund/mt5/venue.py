"""MT5 execution venue (implements ``hedgefund.execution.venue.Venue``).

Safety properties:
  * Only positions carrying this platform's magic number are read or touched: other EAs and
    manual trades on the same account are invisible to reconciliation and never closed.
  * Real accounts are refused unless ``allow_real`` is set (server env flag + UI unlock).
  * "Algo Trading" disabled in the terminal is a hard error, surfaced to the dashboard.
  * Idempotent on client order id: a resubmission returns the recorded state. After an
    unknown outcome (no reply / timeout) the deal history is searched by magic + comment
    before anything is resent.
  * Volumes are rounded DOWN to the broker's volume step; below the minimum lot is rejected.
  * Hedging accounts: a reducing order closes this platform's opposite positions (FIFO, by
    ticket) before opening anything new. Netting accounts: plain deals.
"""

from __future__ import annotations

import time
from datetime import datetime, timedelta, timezone
from typing import Any

from hedgefund.core.clock import Clock
from hedgefund.core.types import Side
from hedgefund.execution.orders import Fill, Order, OrderStatus
from hedgefund.execution.venue import PermanentVenueError, TransientVenueError, VenueOrderState, VenueTimeout
from hedgefund.mt5.catalog import SymbolSpec, spec_from_info
from hedgefund.mt5.client import MT5Client

RC = {  # MQL5 trade server return codes (names resolved from the module when available)
    "TRADE_RETCODE_REQUOTE": 10004,
    "TRADE_RETCODE_PLACED": 10008,
    "TRADE_RETCODE_DONE": 10009,
    "TRADE_RETCODE_DONE_PARTIAL": 10010,
    "TRADE_RETCODE_TIMEOUT": 10012,
    "TRADE_RETCODE_PRICE_CHANGED": 10020,
    "TRADE_RETCODE_PRICE_OFF": 10021,
    "TRADE_RETCODE_TOO_MANY_REQUESTS": 10024,
    "TRADE_RETCODE_INVALID_FILL": 10030,
    "TRADE_RETCODE_CONNECTION": 10031,
}
_FILL_BITS = ((1, "ORDER_FILLING_FOK", 0), (2, "ORDER_FILLING_IOC", 1))  # SYMBOL_FILLING_* bitmask -> order filling


class MT5Venue:
    name = "mt5"

    def __init__(
        self,
        client: MT5Client,
        clock: Clock,
        magic: int = 770077,
        deviation_points: int = 30,
        allow_real: bool = False,
        comment_prefix: str = "hf",
        units_per_lot: dict[str, float] | None = None,
    ):
        self.client = client
        self.clock = clock
        self.magic = magic
        self.deviation = deviation_points
        self.allow_real = allow_real
        self.prefix = comment_prefix
        self._orders: dict[str, VenueOrderState] = {}
        self._outbox: list[Fill] = []
        self._specs: dict[str, SymbolSpec] = {}
        self._rc: dict[str, int] = {}
        # Units-per-lot is frozen per symbol at first use (and persisted by the caller) so that
        # internal books and venue positions always convert lots the same way, even when the
        # broker's tick value drifts with FX rates.
        self.units_per_lot = units_per_lot if units_per_lot is not None else {}

    # ---------------- helpers ----------------
    def _c(self, name: str, default: int) -> int:
        return self.client.const(name, default)

    def rc(self, name: str) -> int:
        if name not in self._rc:
            self._rc[name] = self._c(name, RC[name])
        return self._rc[name]

    def spec(self, symbol: str) -> SymbolSpec:
        info = self.client.call("symbol_info", symbol)
        if info is None:
            raise PermanentVenueError(f"unknown symbol {symbol}")
        if not getattr(info, "visible", True):
            self.client.call("symbol_select", symbol, True)
        s = spec_from_info(info)
        self._specs[symbol] = s
        return s

    def upl(self, spec: SymbolSpec) -> float:
        if spec.name not in self.units_per_lot:
            self.units_per_lot[spec.name] = spec.multiplier
        return self.units_per_lot[spec.name]

    def to_lots(self, spec: SymbolSpec, units: float) -> float:
        step = spec.volume_step or 0.01
        lots = int(abs(units) / self.upl(spec) / step + 1e-9) * step
        return round(min(lots, spec.volume_max or lots), 8)

    def to_units(self, spec: SymbolSpec, lots: float) -> float:
        return lots * self.upl(spec)

    def comment(self, cid: str) -> str:
        return f"{self.prefix}{cid}"[:31]

    def account_guard(self) -> Any:
        if not self.client.ensure():
            raise TransientVenueError(f"MT5 not connected: {self.client.last_error}")
        term = self.client.call("terminal_info")
        if term is not None and not getattr(term, "trade_allowed", True):
            raise PermanentVenueError("Algo Trading is disabled in the MT5 terminal")
        acc = self.client.call("account_info")
        if acc is None:
            raise TransientVenueError(f"no account info: {self.client.error()}")
        if acc.trade_mode == self._c("ACCOUNT_TRADE_MODE_REAL", 2) and not self.allow_real:
            raise PermanentVenueError("real-money account: trading is locked (enable explicitly in the platform)")
        return acc

    def _filling_modes(self, spec: SymbolSpec) -> list[int]:
        modes = [self._c(name, default) for bit, name, default in _FILL_BITS if spec.filling_mode & bit]
        modes.append(self._c("ORDER_FILLING_RETURN", 2))
        return modes

    def _my_positions(self, symbol: str | None = None) -> list[Any]:
        pos = self.client.call("positions_get", symbol=symbol) if symbol else self.client.call("positions_get")
        return [p for p in (pos or ()) if p.magic == self.magic]

    # ---------------- venue API ----------------
    def submit(self, order: Order) -> VenueOrderState:
        cid = order.client_order_id
        if cid in self._orders:
            return self._orders[cid]
        acc = self.account_guard()
        spec = self.spec(order.symbol)
        lots = self.to_lots(spec, order.qty)
        if lots < spec.volume_min - 1e-12:
            raise PermanentVenueError(f"{order.symbol}: {lots} lots below broker minimum {spec.volume_min}")
        state = VenueOrderState(cid, OrderStatus.ACKED, 0.0, 0.0, venue_order_id=None)
        self._orders[cid] = state
        remaining = lots
        if acc.margin_mode == self._c("ACCOUNT_MARGIN_MODE_RETAIL_HEDGING", 2):
            opposite = self._c("POSITION_TYPE_SELL", 1) if order.side is Side.BUY else self._c("POSITION_TYPE_BUY", 0)
            for p in sorted((p for p in self._my_positions(order.symbol) if p.type == opposite), key=lambda p: p.time):
                if remaining < spec.volume_min - 1e-12:
                    break
                vol = min(p.volume, remaining)
                self._deal(order, spec, vol, state, position_ticket=p.ticket)
                remaining = round(remaining - vol, 8)
        if remaining >= spec.volume_min - 1e-12:
            self._deal(order, spec, remaining, state)
        state.status = OrderStatus.FILLED if state.filled_qty >= self.to_units(spec, lots) - 1e-9 else OrderStatus.PARTIALLY_FILLED
        return state

    def _deal(self, order: Order, spec: SymbolSpec, lots: float, state: VenueOrderState, position_ticket: int | None = None) -> None:
        buy = order.side is Side.BUY
        tick = self.client.call("symbol_info_tick", order.symbol)
        if tick is None:
            raise TransientVenueError(f"no quote for {order.symbol}")
        price = tick.ask if buy else tick.bid
        request = {
            "action": self._c("TRADE_ACTION_DEAL", 1),
            "symbol": order.symbol,
            "volume": float(lots),
            "type": self._c("ORDER_TYPE_BUY", 0) if buy else self._c("ORDER_TYPE_SELL", 1),
            "price": float(price),
            "deviation": self.deviation,
            "magic": self.magic,
            "comment": self.comment(order.client_order_id),
            "type_time": self._c("ORDER_TIME_GTC", 0),
        }
        if position_ticket is not None:
            request["position"] = position_ticket
        sent_at = time.time()
        res = None
        for filling in self._filling_modes(spec):
            request["type_filling"] = filling
            res = self.client.call("order_send", request)
            if res is None or res.retcode != self.rc("TRADE_RETCODE_INVALID_FILL"):
                break
        if res is None:
            if self._recover(order, spec, state, sent_at):
                return
            raise VenueTimeout(f"order_send returned no result: {self.client.error()}")
        rc = res.retcode
        if rc in (self.rc("TRADE_RETCODE_DONE"), self.rc("TRADE_RETCODE_DONE_PARTIAL"), self.rc("TRADE_RETCODE_PLACED")):
            vol = float(res.volume or lots)
            px = float(res.price or price)
            fee = self._deal_costs(res.deal)
            self._record_fill(order, spec, state, vol, px, fee, str(res.deal or res.order))
            return
        if rc in (self.rc("TRADE_RETCODE_TIMEOUT"), self.rc("TRADE_RETCODE_CONNECTION")):
            if self._recover(order, spec, state, sent_at):
                return
            raise VenueTimeout(f"retcode {rc}: {res.comment}")
        if rc in (self.rc("TRADE_RETCODE_REQUOTE"), self.rc("TRADE_RETCODE_PRICE_CHANGED"), self.rc("TRADE_RETCODE_PRICE_OFF"), self.rc("TRADE_RETCODE_TOO_MANY_REQUESTS")):
            if state.filled_qty > 0:
                return  # keep what filled; the next decision re-targets
            del self._orders[order.client_order_id]
            raise TransientVenueError(f"retcode {rc}: {res.comment}")
        if state.filled_qty > 0:
            state.reason = f"retcode {rc}: {res.comment}"
            return
        del self._orders[order.client_order_id]
        raise PermanentVenueError(f"retcode {rc}: {res.comment}")

    def _deal_costs(self, deal_ticket: Any) -> float:
        if not deal_ticket:
            return 0.0
        deals = self.client.call("history_deals_get", ticket=deal_ticket) or ()
        return sum(abs(getattr(d, "commission", 0.0)) + abs(getattr(d, "fee", 0.0)) for d in deals)

    def _record_fill(self, order: Order, spec: SymbolSpec, state: VenueOrderState, lots: float, price: float, fee: float, deal_id: str) -> None:
        units = self.to_units(spec, lots)
        fill = Fill(f"mt5-{deal_id}", order.client_order_id, order.symbol, order.side, units, price, fee, self.clock.now_ms(), "taker")
        state.avg_price = (state.avg_price * state.filled_qty + price * units) / (state.filled_qty + units)
        state.filled_qty += units
        state.venue_order_id = deal_id
        state.fills.append(fill)
        self._outbox.append(fill)

    def _find_deals(self, comment: str, since_s: float) -> list[Any]:
        start = datetime.fromtimestamp(since_s - 3 * 86_400, tz=timezone.utc)
        end = datetime.now(tz=timezone.utc) + timedelta(days=2)
        deals = self.client.call("history_deals_get", start, end) or ()
        return [d for d in deals if d.magic == self.magic and d.comment == comment]

    def _recover(self, order: Order, spec: SymbolSpec, state: VenueOrderState, sent_at: float) -> bool:
        """After an unknown outcome, look for the deal before anything is resent."""
        seen = {f.fill_id for f in state.fills}
        found = [d for d in self._find_deals(self.comment(order.client_order_id), sent_at) if f"mt5-{d.ticket}" not in seen]
        for d in found:
            self._record_fill(order, spec, state, float(d.volume), float(d.price), abs(getattr(d, "commission", 0.0)) + abs(getattr(d, "fee", 0.0)), str(d.ticket))
        return bool(found)

    def cancel(self, client_order_id: str) -> VenueOrderState | None:
        """Market deals complete synchronously, so 'cancel' closes out an order whose outcome
        was unknown or partial: pick up any late deal first, then mark the rest cancelled."""
        state = self._orders.get(client_order_id)
        if state is None or state.status in (OrderStatus.FILLED, OrderStatus.CANCELED, OrderStatus.REJECTED):
            return state
        seen = {f.fill_id for f in state.fills}
        for d in self._find_deals(self.comment(client_order_id), time.time() - 86_400):
            if f"mt5-{d.ticket}" not in seen:
                side = Side.BUY if d.type == self._c("DEAL_TYPE_BUY", 0) else Side.SELL
                spec = self._specs.get(d.symbol) or self.spec(d.symbol)
                probe = Order(client_order_id, "", "", None, None, d.symbol, side, 0.0, "market", 0.0, 0)
                self._record_fill(probe, spec, state, float(d.volume), float(d.price), abs(getattr(d, "commission", 0.0)) + abs(getattr(d, "fee", 0.0)), str(d.ticket))
        state.status = OrderStatus.CANCELED
        return state

    def get_order(self, client_order_id: str) -> VenueOrderState | None:
        if client_order_id in self._orders:
            return self._orders[client_order_id]
        deals = self._find_deals(self.comment(client_order_id), time.time() - 86_400)
        if not deals:
            return None
        state = VenueOrderState(client_order_id, OrderStatus.FILLED, 0.0, 0.0)
        self._orders[client_order_id] = state
        return state

    def positions(self) -> dict[str, float]:
        out: dict[str, float] = {}
        for p in self._my_positions():
            spec = self._specs.get(p.symbol) or self.spec(p.symbol)
            sign = 1.0 if p.type == self._c("POSITION_TYPE_BUY", 0) else -1.0
            out[p.symbol] = out.get(p.symbol, 0.0) + sign * self.to_units(spec, p.volume)
        return {s: q for s, q in out.items() if abs(q) > 1e-12}

    def position_details(self) -> list[dict[str, Any]]:
        return [
            {"ticket": p.ticket, "symbol": p.symbol, "side": "buy" if p.type == self._c("POSITION_TYPE_BUY", 0) else "sell", "lots": p.volume,
             "price_open": p.price_open, "price_current": p.price_current, "profit": p.profit, "swap": p.swap, "comment": p.comment}
            for p in self._my_positions()
        ]

    def drain_fills(self) -> list[Fill]:
        out, self._outbox = self._outbox, []
        return out

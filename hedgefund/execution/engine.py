"""Execution engine: turns approved policy targets into orders, safely.

Separation of duties: policy produces targets -> risk approves/clips order requests ->
this engine submits. It never changes sizes upward and never bypasses risk.

Safety properties:
  * Idempotency: client order ids are derived from (strategy, package, decision time,
    action, decision id, symbol); re-running a step cannot double-submit.
  * Unknown outcomes: on a timeout the engine queries the order by client id before any
    resubmission, and resubmits only with the same id.
  * Retries: bounded, exponential backoff, transient errors only.
  * Rate limits: optional token bucket in front of every venue request.
  * Cancel/replace: a new decision for a package cancels that package's open orders first;
    orders older than the TTL are cancelled and re-decided on the next bar.
  * Reconciliation: internal books vs venue positions; mismatch -> kill switch.
  * Audit: every order and fill is logged with strategy_id, decision_id, model_version,
    expected price, actual price and slippage.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from hedgefund.config import Instrument
from hedgefund.core.clock import Clock
from hedgefund.core.ids import stable_id
from hedgefund.core.ledger import Kind
from hedgefund.core.types import Side
from hedgefund.execution.orders import Order, OrderStatus
from hedgefund.execution.ratelimit import TokenBucket
from hedgefund.execution.venue import PermanentVenueError, TransientVenueError, Venue, VenueOrderState, VenueTimeout
from hedgefund.policy.engine import Action, PolicyResult
from hedgefund.portfolio.book import Portfolio
from hedgefund.risk.engine import OrderRequest, RiskEngine, RiskVerdict
from hedgefund.risk.kill_switch import KillSwitch


@dataclass
class ExecutionReport:
    key: str
    submitted: list[str] = field(default_factory=list)
    verdict: RiskVerdict | None = None
    skipped: str | None = None
    errors: list[str] = field(default_factory=list)


@dataclass
class ReconciliationReport:
    ok: bool
    mismatches: dict[str, tuple[float, float]]


class ExecutionEngine:
    def __init__(
        self,
        venue: Venue,
        portfolio: Portfolio,
        risk: RiskEngine,
        ledger: Any,
        clock: Clock,
        instruments: dict[str, Instrument],
        kill_switch: KillSwitch,
        rate_limiter: TokenBucket | None = None,
        max_retries: int = 3,
        backoff_s: float = 0.25,
        order_ttl_ms: int | None = None,
        reconciliation_tolerance_pct: float = 0.001,
    ):
        self.venue = venue
        self.portfolio = portfolio
        self.risk = risk
        self.ledger = ledger
        self.clock = clock
        self.instruments = instruments
        self.kill_switch = kill_switch
        self.rate_limiter = rate_limiter
        self.max_retries = max_retries
        self.backoff_s = backoff_s
        self.order_ttl_ms = order_ttl_ms
        self.recon_tol = reconciliation_tolerance_pct
        self.orders: dict[str, Order] = {}
        self._seen_fills: set[str] = set()
        self._executed: set[str] = set()

    # ---------------- policy -> orders ----------------
    def execute(self, result: PolicyResult, liquidity: dict[str, float]) -> ExecutionReport:
        key = stable_id("exec", result.strategy_id, result.package, result.ts, result.action.value, result.decision_id)
        rep = ExecutionReport(key)
        if key in self._executed:
            rep.skipped = "duplicate policy result"
            return rep
        self._executed.add(key)
        if not result.action.trades:
            rep.skipped = f"action {result.action.value}"
            return rep

        self.cancel_open(result.strategy_id, result.package, "replaced by new decision")
        self.sync()
        book = self.portfolio.book_positions(result.strategy_id)
        requests: list[OrderRequest] = []
        for sym, target_notional in sorted(result.leg_targets.items()):
            mark = self.portfolio.marks.get(sym)
            if not mark:
                rep.errors.append(f"{sym}: no mark price")
                continue
            cur = book[sym].qty if sym in book else 0.0
            target_qty = target_notional / mark
            dq = target_qty - cur
            closing = target_notional == 0 and cur != 0
            if not closing and abs(dq * mark) < self.instruments[sym].min_notional:
                continue
            requests.append(OrderRequest(result.strategy_id, result.package, sym, dq, mark, result.decision_id))
        if rep.errors and result.action in (Action.ENTER, Action.ADJUST):
            rep.skipped = "missing marks for a leg; package not traded"
            return rep
        if not requests:
            rep.skipped = "already at target"
            return rep

        verdict = self.risk.check(requests, self.portfolio.positions(), self.portfolio.marks, self.portfolio.nav(), liquidity)
        rep.verdict = verdict
        if not verdict.approved:
            return rep
        for r in verdict.requests:
            order = Order(
                client_order_id=stable_id(key, r.symbol),
                strategy_id=r.strategy_id,
                package=r.package,
                decision_id=r.decision_id,
                model_version=result.model_version,
                symbol=r.symbol,
                side=Side.BUY if r.qty > 0 else Side.SELL,
                qty=abs(r.qty),
                order_type="market",
                expected_price=r.ref_price,
                created_ts=self.clock.now_ms(),
                reduce_only=verdict.reduce_only,
            )
            self._submit(order)
            rep.submitted.append(order.client_order_id)
        self.sync()
        self._check_leg_balance(rep.submitted)
        return rep

    def flatten_all(self, reason: str, liquidity: dict[str, float]) -> list[str]:
        """Reduce-only market orders closing every book. Always passes risk (reduces exposure)."""
        self.sync()
        ts = self.clock.now_ms()
        submitted = []
        for sid in list(self.portfolio.books):
            for sym, info in self.portfolio.book_positions(sid).items():
                for o in list(self.orders.values()):
                    if o.strategy_id == sid and o.symbol == sym and not o.is_terminal:
                        self._cancel(o, "flatten")
                req = OrderRequest(sid, "flatten", sym, -info.qty, self.portfolio.marks.get(sym, info.avg_price), None)
                verdict = self.risk.check([req], self.portfolio.positions(), self.portfolio.marks, self.portfolio.nav(), liquidity)
                if not verdict.approved:
                    continue
                order = Order(
                    client_order_id=stable_id("flatten", sid, sym, ts),
                    strategy_id=sid,
                    package="flatten",
                    decision_id=None,
                    model_version=None,
                    symbol=sym,
                    side=Side.SELL if info.qty > 0 else Side.BUY,
                    qty=abs(info.qty),
                    order_type="market",
                    expected_price=req.ref_price,
                    created_ts=ts,
                    reduce_only=True,
                )
                self._submit(order)
                submitted.append(order.client_order_id)
        self.ledger.append(Kind.RISK_EVENT, {"event": "flatten_all", "reason": reason, "orders": submitted}, ts=ts)
        self.sync()
        return submitted

    # ---------------- venue interaction ----------------
    def _submit(self, order: Order) -> None:
        self.orders[order.client_order_id] = order
        self.ledger.append(Kind.ORDER, order.to_dict(), ts=order.created_ts, ref=order.decision_id)
        last_err = ""
        for attempt in range(self.max_retries + 1):
            if self.rate_limiter:
                self.rate_limiter.acquire()
            try:
                st = self.venue.submit(order)
                self._apply_state(order, st)
                return
            except VenueTimeout as e:
                last_err = str(e)
                st = self._query(order.client_order_id)
                if st is not None:
                    self._apply_state(order, st)
                    return
            except TransientVenueError as e:
                last_err = str(e)
            except PermanentVenueError as e:
                self._reject(order, str(e))
                return
            self.clock.sleep(self.backoff_s * 2**attempt)
        self._reject(order, f"retries exhausted: {last_err}")
        self.ledger.append(Kind.ALERT, {"severity": "high", "message": f"order {order.client_order_id} failed: {last_err}"}, ts=self.clock.now_ms())

    def _query(self, cid: str) -> VenueOrderState | None:
        for attempt in range(self.max_retries + 1):
            try:
                return self.venue.get_order(cid)
            except TransientVenueError:
                self.clock.sleep(self.backoff_s * 2**attempt)
        return None

    def _apply_state(self, order: Order, st: VenueOrderState) -> None:
        ts = self.clock.now_ms()
        if order.status is OrderStatus.NEW:
            order.transition(OrderStatus.SUBMITTED, ts)
        order.venue_order_id = st.venue_order_id
        if st.status is OrderStatus.REJECTED:
            order.reject_reason = st.reason
            order.transition(OrderStatus.REJECTED, ts, st.reason or "")
            self._log_update(order)
        elif st.status in (OrderStatus.CANCELED, OrderStatus.EXPIRED):
            order.transition(st.status, ts)
            self._log_update(order)
        elif order.status is OrderStatus.SUBMITTED:
            order.transition(OrderStatus.ACKED, ts)

    def _reject(self, order: Order, reason: str) -> None:
        ts = self.clock.now_ms()
        order.reject_reason = reason
        if order.status is OrderStatus.NEW:
            order.transition(OrderStatus.REJECTED, ts, reason)
        elif not order.is_terminal:
            order.transition(OrderStatus.CANCELED if order.status is not OrderStatus.SUBMITTED else OrderStatus.REJECTED, ts, reason)
        self._log_update(order)

    def _cancel(self, order: Order, reason: str) -> None:
        try:
            st = self.venue.cancel(order.client_order_id)
        except TransientVenueError:
            return  # retried on the next sync/TTL pass
        self.sync()
        if st is not None and not order.is_terminal and st.status is OrderStatus.CANCELED:
            order.transition(OrderStatus.CANCELED, self.clock.now_ms(), reason)
            self._log_update(order)

    def cancel_open(self, strategy_id: str, package: str, reason: str) -> None:
        for o in list(self.orders.values()):
            if o.strategy_id == strategy_id and o.package == package and not o.is_terminal:
                self._cancel(o, reason)

    def expire_stale(self) -> None:
        if self.order_ttl_ms is None:
            return
        now = self.clock.now_ms()
        for o in list(self.orders.values()):
            if not o.is_terminal and now - o.created_ts >= self.order_ttl_ms:
                self._cancel(o, "ttl expired")

    def sync(self) -> int:
        n = 0
        for f in self.venue.drain_fills():
            if f.fill_id in self._seen_fills:
                continue
            self._seen_fills.add(f.fill_id)
            order = self.orders.get(f.client_order_id)
            sid = order.strategy_id if order else "_unattributed"
            if order is None:
                self.ledger.append(Kind.ALERT, {"severity": "high", "message": f"fill for unknown order {f.client_order_id}"}, ts=f.ts)
            else:
                if order.status is OrderStatus.NEW:
                    order.transition(OrderStatus.SUBMITTED, f.ts)
                order.apply_fill(f)
            realized = self.portfolio.apply_fill(sid, f.symbol, f.signed_qty, f.price, f.fee, f.ts)
            exp = order.expected_price if order else None
            self.ledger.append(
                Kind.FILL,
                {
                    "fill_id": f.fill_id,
                    "client_order_id": f.client_order_id,
                    "strategy_id": sid,
                    "decision_id": order.decision_id if order else None,
                    "model_version": order.model_version if order else None,
                    "symbol": f.symbol,
                    "side": f.side.value,
                    "qty": f.qty,
                    "expected_price": exp,
                    "actual_price": f.price,
                    "slippage_bps": (f.price / exp - 1) * 1e4 * f.side.sign if exp else None,
                    "fee": f.fee,
                    "liquidity": f.liquidity,
                    "realized_pnl": realized,
                    "signed_qty": f.signed_qty,
                },
                ts=f.ts,
                ref=order.decision_id if order else None,
            )
            if order is not None and order.is_terminal:
                self._log_update(order)
            n += 1
        return n

    def reconcile(self) -> ReconciliationReport:
        self.sync()
        internal = self.portfolio.positions()
        venue = self.venue.positions()
        nav = max(self.portfolio.nav(), 1e-9)
        mismatches = {}
        for sym in set(internal) | set(venue):
            i, v = internal.get(sym, 0.0), venue.get(sym, 0.0)
            mark = self.portfolio.marks.get(sym, 0.0)
            if abs(i - v) * mark > self.recon_tol * nav:
                mismatches[sym] = (i, v)
        rep = ReconciliationReport(not mismatches, mismatches)
        ts = self.clock.now_ms()
        self.ledger.append(Kind.RECONCILIATION, {"ok": rep.ok, "mismatches": {k: list(v) for k, v in mismatches.items()}}, ts=ts)
        if not rep.ok:
            self.kill_switch.engage(f"reconciliation mismatch: {sorted(mismatches)}", "execution_engine")
        return rep

    # ---------------- helpers ----------------
    def open_orders(self) -> list[Order]:
        return [o for o in self.orders.values() if not o.is_terminal]

    def _log_update(self, order: Order) -> None:
        self.ledger.append(Kind.ORDER_UPDATE, order.to_dict(), ts=self.clock.now_ms(), ref=order.decision_id)

    def _check_leg_balance(self, cids: list[str]) -> None:
        orders = [self.orders[c] for c in cids if c in self.orders]
        if len(orders) < 2:
            return
        fracs = [o.filled_qty / o.qty if o.qty else 1.0 for o in orders]
        if max(fracs) - min(fracs) > 0.2:
            self.ledger.append(
                Kind.RISK_EVENT,
                {"event": "leg_imbalance", "orders": {o.symbol: round(f, 4) for o, f in zip(orders, fracs)}},
                ts=self.clock.now_ms(),
            )

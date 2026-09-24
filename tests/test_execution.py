import pytest

from hedgefund.core.types import Direction, Side
from hedgefund.execution.engine import ExecutionEngine
from hedgefund.execution.orders import Fill, IllegalTransition, Order, OrderStatus
from hedgefund.execution.paper import PaperVenue
from hedgefund.execution.venue import PermanentVenueError, TransientVenueError, VenueTimeout
from hedgefund.policy.engine import Action, PolicyResult
from hedgefund.portfolio.book import Portfolio
from hedgefund.risk.engine import RiskEngine
from hedgefund.risk.kill_switch import KillSwitch

NAV = 1_000_000.0
PX = {"BTCUSDT": 50_000.0, "BTCUSDT-PERP": 50_050.0, "ETHUSDT": 3_000.0, "ETHUSDT-PERP": 3_001.0}
LIQ = {s: 5e8 for s in PX}


def make(cfg, ledger, clock, venue=None):
    pf = Portfolio(NAV, cfg.instruments)
    ks = KillSwitch(None, ledger, clock)
    risk = RiskEngine(cfg.risk, cfg.instruments, ks, ledger, clock)
    venue = venue or PaperVenue(cfg.instruments, clock)
    for s, p in PX.items():
        venue.set_market(s, p, LIQ[s])
    pf.mark(PX)
    ex = ExecutionEngine(venue, pf, risk, ledger, clock, cfg.instruments, ks, backoff_s=0.01, order_ttl_ms=3_600_000)
    return ex, pf, venue, ks


def result(targets, action=Action.ENTER, ts=1, did="dec-1", strat="carry_btc_basis", pkg="BTC-carry"):
    return PolicyResult(action, strat, pkg, Direction.LONG, targets, ts, did, "ref-1.0")


def test_order_state_machine():
    o = Order("c", "s", "p", "d", "m", "BTCUSDT", Side.BUY, 1.0, "market", 100.0, 0)
    with pytest.raises(IllegalTransition):
        o.transition(OrderStatus.FILLED, 1)
    o.transition(OrderStatus.SUBMITTED, 1)
    o.transition(OrderStatus.ACKED, 2)
    o.apply_fill(Fill("f1", "c", "BTCUSDT", Side.BUY, 0.4, 101.0, 0.1, 3))
    assert o.status is OrderStatus.PARTIALLY_FILLED
    with pytest.raises(IllegalTransition):
        o.apply_fill(Fill("f2", "c", "BTCUSDT", Side.BUY, 0.7, 101.0, 0.1, 4))
    o.apply_fill(Fill("f3", "c", "BTCUSDT", Side.BUY, 0.6, 102.0, 0.1, 4))
    assert o.status is OrderStatus.FILLED and o.avg_fill_price == pytest.approx(101.6)
    assert o.slippage_bps == pytest.approx(160.0)
    with pytest.raises(IllegalTransition):
        o.transition(OrderStatus.CANCELED, 5)


def test_package_executes_and_logs_everything(cfg, ledger, clock):
    ex, pf, venue, _ = make(cfg, ledger, clock)
    rep = ex.execute(result({"BTCUSDT": 100_000.0, "BTCUSDT-PERP": -100_000.0}), LIQ)
    assert rep.verdict.approved and len(rep.submitted) == 2
    pos = pf.positions()
    assert pos["BTCUSDT"] == pytest.approx(2.0) and pos["BTCUSDT-PERP"] == pytest.approx(-100_000 / 50_050)
    fills = ledger.query(kind="fill")
    assert len(fills) == 2
    for f in fills:
        for k in ("strategy_id", "decision_id", "model_version", "expected_price", "actual_price", "slippage_bps", "fee"):
            assert f.payload[k] is not None
        assert f.payload["slippage_bps"] > 0  # paid spread + impact
    assert ex.reconcile().ok


def test_execute_is_idempotent(cfg, ledger, clock):
    ex, pf, venue, _ = make(cfg, ledger, clock)
    r = result({"BTCUSDT": 100_000.0})
    ex.execute(r, LIQ)
    again = ex.execute(r, LIQ)
    assert again.skipped == "duplicate policy result"
    assert len(ledger.query(kind="order")) == 1


def test_partial_fills_continue_and_ttl_cancels(cfg, ledger, clock):
    venue = PaperVenue(cfg.instruments, clock, max_participation_per_step=0.0001)
    ex, pf, venue, _ = make(cfg, ledger, clock, venue)
    venue.set_market("BTCUSDT", PX["BTCUSDT"], 5e8)  # 0.01% of 5e8 = 50k per step
    ex.execute(result({"BTCUSDT": 120_000.0}), {"BTCUSDT": 1e10})
    o = next(iter(ex.orders.values()))
    assert o.status is OrderStatus.PARTIALLY_FILLED and o.filled_qty == pytest.approx(1.0)
    venue.set_market("BTCUSDT", PX["BTCUSDT"], 5e8)
    venue.step()
    ex.sync()
    assert o.filled_qty == pytest.approx(2.0)
    clock.advance(3_600_000)
    ex.expire_stale()
    assert o.status is OrderStatus.CANCELED
    assert pf.positions()["BTCUSDT"] == pytest.approx(2.0)
    assert ex.reconcile().ok


class FlakyVenue(PaperVenue):
    """Fails the first N submissions in a chosen way."""

    def __init__(self, *a, mode="transient", fail_times=1, **kw):
        super().__init__(*a, **kw)
        self.mode, self.fail_times, self.calls = mode, fail_times, 0

    def submit(self, order):
        self.calls += 1
        if self.calls <= self.fail_times:
            if self.mode == "transient":
                raise TransientVenueError("503")
            if self.mode == "permanent":
                raise PermanentVenueError("insufficient balance")
            if self.mode == "lost_ack":
                super().submit(order)  # order reaches the venue ...
                raise VenueTimeout("... but the ack is lost")
        return super().submit(order)


def test_transient_errors_are_retried(cfg, ledger, clock):
    v = FlakyVenue(cfg.instruments, clock, mode="transient", fail_times=2)
    ex, pf, _, _ = make(cfg, ledger, clock, v)
    ex.execute(result({"BTCUSDT": 50_000.0}), LIQ)
    assert pf.positions()["BTCUSDT"] == pytest.approx(1.0) and v.calls == 3


def test_lost_ack_is_queried_not_duplicated(cfg, ledger, clock):
    v = FlakyVenue(cfg.instruments, clock, mode="lost_ack", fail_times=1)
    ex, pf, _, _ = make(cfg, ledger, clock, v)
    ex.execute(result({"BTCUSDT": 50_000.0}), LIQ)
    assert v.calls == 1  # queried via get_order, never resubmitted
    assert pf.positions()["BTCUSDT"] == pytest.approx(1.0)
    assert venue_positions_match(ex)


def venue_positions_match(ex):
    return ex.reconcile().ok


def test_permanent_error_rejects_without_retry(cfg, ledger, clock):
    v = FlakyVenue(cfg.instruments, clock, mode="permanent", fail_times=5)
    ex, pf, _, _ = make(cfg, ledger, clock, v)
    ex.execute(result({"BTCUSDT": 50_000.0}), LIQ)
    o = next(iter(ex.orders.values()))
    assert v.calls == 1 and o.status is OrderStatus.REJECTED and not pf.positions()


def test_retries_exhausted_alerts(cfg, ledger, clock):
    v = FlakyVenue(cfg.instruments, clock, mode="transient", fail_times=99)
    ex, pf, _, _ = make(cfg, ledger, clock, v)
    ex.execute(result({"BTCUSDT": 50_000.0}), LIQ)
    assert next(iter(ex.orders.values())).status is OrderStatus.REJECTED
    assert any("failed" in a.payload["message"] for a in ledger.query(kind="alert"))


def test_reconciliation_mismatch_engages_kill_switch(cfg, ledger, clock):
    ex, pf, venue, ks = make(cfg, ledger, clock)
    ex.execute(result({"BTCUSDT": 100_000.0}), LIQ)
    venue.restore_positions({"BTCUSDT": 1.0})  # venue disagrees with our books
    rep = ex.reconcile()
    assert not rep.ok and ks.engaged


def test_flatten_all_closes_every_book(cfg, ledger, clock):
    ex, pf, venue, ks = make(cfg, ledger, clock)
    ex.execute(result({"BTCUSDT": 100_000.0, "BTCUSDT-PERP": -100_000.0}), LIQ)
    ex.execute(result({"ETHUSDT-PERP": 60_000.0}, strat="tsmom_majors", pkg="ETH-trend", did="dec-2"), LIQ)
    ks.engage("test", "test")
    ex.flatten_all("test", LIQ)
    assert pf.positions() == {}
    assert ex.reconcile().ok


def test_fault_injection_run_stays_consistent(cfg, ledger, clock):
    v = PaperVenue(cfg.instruments, clock, seed=3, transient_error_prob=0.3, timeout_prob=0.3)
    ex, pf, _, _ = make(cfg, ledger, clock, v)
    for i in range(30):
        clock.advance(120_000)
        tgt = 50_000.0 * (1 + (i % 3))
        ex.execute(result({"ETHUSDT-PERP": tgt if i % 2 else -tgt}, ts=i, did=f"d{i}", strat="tsmom_majors", pkg="ETH-trend"), LIQ)
    assert ex.reconcile().ok  # books == venue despite lost acks and 503s

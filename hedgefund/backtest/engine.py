"""Event-driven backtester that runs the production stack bar by bar.

Timing (no look-ahead): decisions are made at bar close t using data <= t; orders execute at
the next bar's open with liquidity estimated from the previous completed bar; funding
accrues on the prints that occur in (t-1, t]. Costs, partial fills, risk clipping, the kill
switch and Jev gating are all live - nothing is simplified away for the backtest.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from hedgefund.backtest.metrics import summarize
from hedgefund.config import FundConfig
from hedgefund.core.clock import SimClock
from hedgefund.core.ledger import Kind, Ledger, NullLedger
from hedgefund.core.timeutil import DAY_MS
from hedgefund.data.series import MarketData
from hedgefund.execution.paper import PaperVenue
from hedgefund.jev.engine import JevEngine
from hedgefund.jev.reference import ReferenceJev
from hedgefund.ops.assembly import build_stack
from hedgefund.policy.engine import PolicyResult
from hedgefund.strategy.spec import StrategySpec


@dataclass
class BacktestConfig:
    fee_mult: float = 1.0
    slippage_mult: float = 1.0
    delay_bars: int = 1
    seed: int = 0
    n_trials: int = 1
    record_ledger: bool = False
    start_ts: int | None = None
    end_ts: int | None = None
    reconcile_every: int = 50


@dataclass
class BacktestResult:
    equity: list[tuple[int, float]]
    strategy_equity: dict[str, list[float]]
    metrics: dict[str, Any]
    strategy_metrics: dict[str, dict[str, Any]]
    trades: dict[str, Any]
    calibration: dict[str, dict]
    risk_events: list[dict]
    escalations: int
    decisions: int
    synthetic: bool
    ledger: Any = field(repr=False, default=None)


def run_backtest(
    data: MarketData,
    specs: list[StrategySpec],
    config: FundConfig,
    bt: BacktestConfig | None = None,
    jev: JevEngine | None = None,
) -> BacktestResult:
    bt = bt or BacktestConfig()
    cfg = config.with_cost_multipliers(bt.fee_mult, bt.slippage_mult)
    clock = SimClock()
    ledger: Any = Ledger(":memory:") if bt.record_ledger else NullLedger()
    venue = PaperVenue(cfg.instruments, clock, seed=bt.seed)
    stack = build_stack(cfg, specs, clock, ledger, venue, jev=jev or ReferenceJev(), order_ttl_ms=data.interval_ms)
    pf, ex, risk, ks = stack.portfolio, stack.execution, stack.risk, stack.kill_switch

    symbols = sorted({s for spec in specs for s in spec.universe})
    timeline = [t for t in data.timeline(symbols) if (bt.start_ts is None or t >= bt.start_ts) and (bt.end_ts is None or t <= bt.end_ts)]
    if len(timeline) < 3:
        raise ValueError("not enough data for a backtest")
    step = data.interval_ms
    bpy = 365 * DAY_MS / step

    pending: dict[int, list[PolicyResult]] = {}
    equity: list[tuple[int, float]] = []
    strat_eq: dict[str, list[float]] = {s.id: [] for s in specs}
    decisions = 0
    risk_events: list[dict] = []
    prev_t = timeline[0] - step

    for i, t in enumerate(timeline):
        # ---- execution at this bar's open ----
        clock.set(t - step)
        opens, liq = {}, {}
        for s in symbols:
            ser = data.bars[s]
            j = ser.upto(t) - 1
            opens[s] = ser.open[j]
            liq[s] = ser.volume[j - 1] * ser.close[j - 1] if j >= 1 else 0.0
            venue.set_market(s, opens[s], liq[s])
        pf.mark(opens)
        venue.step()
        ex.sync()
        if ks.engaged:
            pending.clear()
            if pf.positions():
                ex.flatten_all(f"kill switch: {ks.reason}", liq)
        else:
            for res in pending.pop(i, []):
                ex.execute(res, liq)
        ex.expire_stale()

        # ---- mark, funding, risk state at this bar's close ----
        clock.set(t)
        closes = {s: data.bars[s].close[data.bars[s].upto(t) - 1] for s in symbols}
        pf.mark(closes)
        for s in symbols:
            f = data.funding.get(s)
            if f is None:
                continue
            for ft, rate in f.between(prev_t, t):
                paid = pf.apply_funding(s, rate, closes[s])
                if paid:
                    ledger.append(Kind.FUNDING, {"symbol": s, "rate": rate, "paid": paid}, ts=ft)
        nav = pf.nav()
        was_engaged = ks.engaged
        risk.update_nav(nav, t)
        if ks.engaged and not was_engaged:
            risk_events.append({"ts": t, "event": "kill_switch", "reason": ks.reason})
        equity.append((t, nav))
        for sid in strat_eq:
            strat_eq[sid].append(pf.book_equity(sid))

        # ---- decide at close ----
        if not ks.engaged:
            results = stack.pipeline.decide(data.view(t), t)
            decisions += len(results)
            trades = [r for r in results if r.action.trades]
            if trades:
                pending.setdefault(i + max(1, bt.delay_bars), []).extend(trades)
        if bt.reconcile_every and i % bt.reconcile_every == 0:
            ex.reconcile()
        prev_t = t

    stack.calibration.resolve(data, timeline[-1])
    values = [v for _, v in equity]
    metrics = summarize(values, bpy, n_trials=bt.n_trials)
    strategy_metrics = {}
    for sid, eq in strat_eq.items():
        series = [config.starting_nav + x for x in eq]
        m = summarize(series, bpy, n_trials=bt.n_trials)
        b = pf.books.get(sid)
        m["pnl"] = eq[-1] if eq else 0.0
        m["fees"] = b.fees if b else 0.0
        m["funding_paid"] = b.funding if b else 0.0
        wins = [x for _, _, x in (b.realized_events if b else []) if x > 0]
        n_real = len(b.realized_events) if b else 0
        m["closing_fills"] = n_real
        m["hit_rate"] = len(wins) / n_real if n_real else None
        strategy_metrics[sid] = m
    filled = [o for o in ex.orders.values() if o.filled_qty > 0]
    slips = [o.slippage_bps for o in filled if o.slippage_bps is not None]
    years = len(values) / bpy
    avg_nav = sum(values) / len(values)
    trades = {
        "orders": len(ex.orders),
        "filled_orders": len(filled),
        "rejected_orders": sum(1 for o in ex.orders.values() if o.status.value == "rejected"),
        "avg_slippage_bps": sum(slips) / len(slips) if slips else None,
        "turnover_per_year": pf.fill_notional / avg_nav / years if years > 0 else 0.0,
        "fees": sum(b.fees for b in pf.books.values()),
        "funding_paid": sum(b.funding for b in pf.books.values()),
    }
    return BacktestResult(
        equity=equity,
        strategy_equity=strat_eq,
        metrics=metrics,
        strategy_metrics=strategy_metrics,
        trades=trades,
        calibration=stack.calibration.report(("model_version", "strategy_id", "question")),
        risk_events=risk_events,
        escalations=stack.pipeline.escalations_emitted,
        decisions=decisions,
        synthetic=data.synthetic,
        ledger=ledger if bt.record_ledger else None,
    )

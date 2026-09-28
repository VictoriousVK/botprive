"""24/7 runner: the per-bar fast loop plus scheduled evening and overnight workflows.

Restart-safe: books, funding, high-water mark, pending calibration predictions and strategy
halts are rebuilt from the ledger on start, so a crash or redeploy resumes where it stopped.
Idempotent per bar: re-running the same bar is a no-op.

Only paper/shadow execution is wired. Live execution requires a venue adapter that passes the
Venue contract tests against the real venue's testnet plus a recorded human approval.
"""

from __future__ import annotations

import json
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

from hedgefund.calibration.tracker import Prediction
from hedgefund.config import FundConfig
from hedgefund.core.clock import Clock, SystemClock
from hedgefund.core.ledger import Kind, Ledger
from hedgefund.core.timeutil import DAY_MS, MINUTE_MS, interval_ms, utc_date, utc_iso
from hedgefund.data.quality import check_market_data
from hedgefund.data.series import MarketData
from hedgefund.data.sources import load_live_market_data
from hedgefund.execution.paper import PaperVenue
from hedgefund.monitoring.alerts import AlertSink
from hedgefund.monitoring.health import health_check
from hedgefund.monitoring.report import daily_report
from hedgefund.ops.assembly import build_stack
from hedgefund.strategy.lifecycle import current_stage, transition
from hedgefund.strategy.monitor import evaluate_invalidation, strategy_metrics
from hedgefund.strategy.spec import RUNNABLE_STAGES, Stage, load_specs


class DataProvider(Protocol):
    def load(self, now_ms: int) -> MarketData: ...


class LiveDataProvider:
    def __init__(self, symbols: list[str], interval: str, lookback_days: int):
        self.symbols, self.interval, self.lookback_days = symbols, interval, lookback_days

    def load(self, now_ms: int) -> MarketData:
        return load_live_market_data(self.symbols, self.interval, self.lookback_days, end_ms=now_ms)


class ReplayDataProvider:
    """Serves a fixed dataset as if live (views are cut at ``now``). For paper replay and tests."""

    def __init__(self, data: MarketData):
        self.data = data

    def load(self, now_ms: int) -> MarketData:
        return self.data


@dataclass
class StepSummary:
    status: str
    bar_ts: int | None = None
    nav: float | None = None
    actions: dict[str, int] | None = None
    health: str | None = None


def replay_books(ledger: Any, pf: Any) -> dict | None:
    """Rebuild books from FILL and FUNDING events in ledger order; returns the last NAV payload."""
    last_nav = None
    for e in ledger.query(kind=[Kind.FILL, Kind.FUNDING, Kind.NAV]):
        p = e.payload
        if e.kind == Kind.FILL and "signed_qty" in p:
            pf.apply_fill(p["strategy_id"], p["symbol"], p["signed_qty"], p["actual_price"], p["fee"], e.ts)
        elif e.kind == Kind.FUNDING and "mark" in p:
            pf.apply_funding(p["symbol"], p["rate"], p["mark"])
        elif e.kind == Kind.NAV:
            last_nav = p
    if last_nav:
        pf.mark(last_nav.get("marks", {}))
    return last_nav


class FundRunner:
    def __init__(
        self,
        config: FundConfig,
        provider: DataProvider,
        clock: Clock | None = None,
        ledger: Any = None,
        include_all_stages: bool = False,
        researcher: Any = None,
        alerts: AlertSink | None = None,
        venue: Any = None,
        persist_files: bool = True,
    ):
        self.config = config
        self.provider = provider
        self.clock = clock or SystemClock()
        self.ledger = ledger if ledger is not None else Ledger(config.ledger_path)
        self.persist_files = persist_files
        self.specs = load_specs(config.strategy_dir)
        self.stages = {s.id: current_stage(s, self.ledger) for s in self.specs}
        runnable = [s for s in self.specs if include_all_stages or self.stages[s.id] in RUNNABLE_STAGES]
        self.interval_ms = interval_ms(config.bar_interval)
        self.venue = venue or PaperVenue(config.instruments, self.clock)
        self.stack = build_stack(
            config,
            runnable,
            self.clock,
            self.ledger,
            self.venue,
            kill_switch_path=config.kill_switch_path if persist_files else None,
            order_ttl_ms=self.interval_ms,
        )
        self.alerts = alerts or AlertSink.from_env(self.ledger, self.clock, config.monitoring.get("alert_webhook_env", "ALERT_WEBHOOK_URL"))
        self.researcher = researcher
        self.last_bar_ts: int | None = None
        self.halted: set[str] = set()
        self.last_data: MarketData | None = None
        self._done: set[tuple[str, str]] = set()
        self._kill_alerted = False
        self._restore()
        self.ledger.append(
            Kind.CONFIG,
            {
                "event": "runner_start",
                "config_hash": config.source_hash,
                "mode": config.mode.value,
                "jev": self.stack.pipeline.jev.model_version,
                "strategies": {s.id: {"stage": self.stages[s.id].value, "spec_hash": s.spec_hash, "running": s in runnable} for s in self.specs},
                "include_all_stages": include_all_stages,
            },
            ts=self.clock.now_ms(),
        )

    # ---------------- restart safety ----------------
    def _restore(self) -> None:
        pf = self.stack.portfolio
        last_nav = replay_books(self.ledger, pf)
        if last_nav:
            self.last_bar_ts = last_nav.get("bar_ts")
            self.stack.risk.hwm = last_nav.get("hwm")
            pf.mark(last_nav.get("marks", {}))
        if isinstance(self.venue, PaperVenue):
            self.venue.restore_positions(pf.positions())
        for e in self.ledger.query(kind=Kind.STRATEGY_HALT):
            (self.halted.add if e.payload["halted"] else self.halted.discard)(e.payload["strategy_id"])
        resolved = {(e.payload["decision_id"], e.payload["question"]) for e in self.ledger.query(kind=Kind.CALIBRATION_OUTCOME)}
        for e in self.ledger.query(kind=Kind.CALIBRATION_PREDICTION):
            p = e.payload
            if (p["decision_id"], p["question"]) not in resolved:
                p = {**p, "legs": tuple(tuple(x) for x in p["legs"])}
                self.stack.calibration.pending.append(Prediction(**p))

    # ---------------- fast loop ----------------
    def run_once(self) -> StepSummary:
        now = self.clock.now_ms()
        st = self.stack
        symbols = sorted({s for rt in st.pipeline.runtimes for s in rt.spec.universe})
        if not symbols:
            self._heartbeat(now, "idle: no strategy at a runnable stage (paper_trade/shadow_mode/live)")
            return StepSummary("idle")
        try:
            data = self.provider.load(now)
        except Exception as e:  # noqa: BLE001 - data outage: no trading, alert, retry next loop
            self.alerts.alert("high", f"market data unavailable: {type(e).__name__}: {e}")
            self._heartbeat(now, "data unavailable")
            return StepSummary("data_unavailable")
        self.last_data = data
        timeline = [t for t in data.timeline(symbols) if t <= now]
        if not timeline:
            self.alerts.alert("high", "no complete bars available")
            return StepSummary("no_bars")
        t = timeline[-1]
        if self.last_bar_ts is not None and t <= self.last_bar_ts:
            return StepSummary("no_new_bar", t)
        quality = check_market_data(data, now, symbols, int(self.config.data.get("max_staleness_bars", 2)))
        if not quality.ok:
            self.ledger.append(Kind.DATA_QUALITY, quality.to_dict(), ts=now)
            self.alerts.alert("high", "data quality gate failed", errors=quality.errors[:5])

        view = data.view(t)
        prices = {s: view.last_close(s) for s in symbols}
        liquidity = {s: view.notional_volume(s, 1) or 0.0 for s in symbols}
        if hasattr(self.venue, "set_market"):
            for s in symbols:
                self.venue.set_market(s, prices[s], liquidity[s])
        st.portfolio.mark(prices)
        prev = self.last_bar_ts if self.last_bar_ts is not None else t - data.interval_ms
        for s in symbols:
            f = data.funding.get(s)
            for ft, rate in (f.between(prev, t) if f else []):
                paid = st.portfolio.apply_funding(s, rate, prices[s])
                self.ledger.append(Kind.FUNDING, {"symbol": s, "rate": rate, "mark": prices[s], "paid": paid}, ts=ft)
        if hasattr(self.venue, "step"):
            self.venue.step()
        st.execution.sync()
        st.risk.update_nav(st.portfolio.nav(), t)
        actions: dict[str, int] = {}
        if st.kill_switch.engaged:
            # Alert once per engagement, however it was engaged (risk engine, CLI, flag file).
            if not self._kill_alerted:
                self.alerts.alert("critical", f"KILL SWITCH ENGAGED: {st.kill_switch.reason}")
                self._kill_alerted = True
            if st.portfolio.positions():
                st.execution.flatten_all(f"kill switch: {st.kill_switch.reason}", liquidity)
        else:
            self._kill_alerted = False
            for res in st.pipeline.decide(view, t, quality.blocked_symbols, self.halted):
                actions[res.action.value] = actions.get(res.action.value, 0) + 1
                if res.action.trades:
                    st.execution.execute(res, liquidity)
        st.execution.expire_stale()
        recon = st.execution.reconcile()
        if not recon.ok:
            self.alerts.alert("critical", f"reconciliation mismatch: {recon.mismatches}")
        nav = st.portfolio.nav()
        self.ledger.append(
            Kind.NAV,
            {
                "nav": nav,
                "bar_ts": t,
                "hwm": st.risk.hwm,
                "drawdown": st.risk.drawdown(nav),
                "books": {sid: st.portfolio.book_equity(sid) for sid in st.portfolio.books},
                "positions": st.portfolio.positions(),
                "marks": prices,
                "exposures": st.portfolio.exposures(),
            },
            ts=t,
        )
        health = health_check(st, now, quality, float(self.config.monitoring.get("jev_latency_p99_ms", 500)), t, data.interval_ms)
        for failure in health.failures():
            self.alerts.alert("high", f"health: {failure}")
        self.last_bar_ts = t
        self._heartbeat(now, f"bar {utc_iso(t)} nav {nav:,.2f} health {health.status}")
        return StepSummary("ok", t, nav, actions, health.status)

    # ---------------- scheduled workflows ----------------
    def evening_review(self, now: int) -> Path | None:
        md = daily_report(self.ledger, self.stack.portfolio, {k: v.value for k, v in self.stages.items()}, now, synthetic=bool(self.last_data and self.last_data.synthetic))
        self.ledger.append(Kind.RESEARCH_REVIEW, {"task": "daily_report", "markdown": md}, ts=now)
        if not self.persist_files:
            return None
        path = self.config.reports_dir / f"{utc_date(now)}.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(md)
        return path

    def overnight(self, now: int) -> dict[str, Any]:
        out: dict[str, Any] = {}
        if self.last_data is not None:
            out["calibration_resolved"] = self.stack.calibration.resolve(self.last_data, now)
        out["invalidation"] = self.check_invalidation(now)
        ok, bad = self.ledger.verify_chain()
        out["ledger_ok"] = ok
        if not ok:
            self.alerts.alert("critical", f"ledger hash chain broken at seq {bad}")
        if self.researcher is not None and self.last_data is not None:
            from hedgefund.calibration.tracker import CalibrationTracker
            from hedgefund.research.pipeline import run_overnight_research

            report = daily_report(self.ledger, self.stack.portfolio, {k: v.value for k, v in self.stages.items()}, now, synthetic=self.last_data.synthetic)
            out["research"] = run_overnight_research(self.researcher, self.ledger, self.last_data, report, CalibrationTracker.from_ledger_outcomes(self.ledger, now - 30 * DAY_MS), now)
        return out

    def check_invalidation(self, now: int) -> list[dict[str, Any]]:
        actions = []
        for spec in self.specs:
            stage = current_stage(spec, self.ledger)
            if stage not in RUNNABLE_STAGES:
                continue
            for b in evaluate_invalidation(spec, strategy_metrics(self.ledger, spec.id, now)):
                reason = f"invalidation: {b['metric']} {b['value']:.4g} {b['op']} {b['threshold']}"
                if b["action"] in ("halt", "retire") and spec.id not in self.halted:
                    self.halted.add(spec.id)
                    self.ledger.append(Kind.STRATEGY_HALT, {"strategy_id": spec.id, "halted": True, "reason": reason}, ts=now, ref=spec.id)
                if b["action"] == "retire":
                    transition(spec, Stage.RETIRED, {}, self.ledger, now, reason=reason)
                elif b["action"] == "demote" and stage.order > Stage.PAPER_TRADE.order:
                    transition(spec, Stage.PAPER_TRADE, {}, self.ledger, now, reason=reason)
                self.alerts.alert("high", f"{spec.id}: {reason} -> {b['action']}")
                actions.append({"strategy_id": spec.id, **b})
        return actions

    def run_scheduled(self, now: int) -> None:
        hhmm = lambda key, default: self.config.schedule.get(key, default)  # noqa: E731
        today = utc_date(now)
        minute_of_day = (now % DAY_MS) // MINUTE_MS
        for task, key, default, fn in (("evening_review", "evening_review", "20:00", self.evening_review), ("overnight", "overnight_research", "02:00", self.overnight)):
            h, m = (int(x) for x in hhmm(key, default).split(":"))
            if minute_of_day >= h * 60 + m and (task, today) not in self._done:
                self._done.add((task, today))
                try:
                    fn(now)
                except Exception as e:  # noqa: BLE001
                    self.alerts.alert("high", f"{task} failed: {type(e).__name__}: {e}")

    def run_forever(self, stop: threading.Event | None = None, settle_s: float = 20.0) -> None:
        stop = stop or threading.Event()
        backoff = 5.0
        while not stop.is_set():
            try:
                self.run_once()
                backoff = 5.0
            except Exception as e:  # noqa: BLE001 - the loop must survive; alert and back off
                self.alerts.alert("critical", f"fast loop error: {type(e).__name__}: {e}")
                stop.wait(backoff)
                backoff = min(backoff * 2, 300.0)
                continue
            now = self.clock.now_ms()
            self.run_scheduled(now)
            next_bar = (now // self.interval_ms + 1) * self.interval_ms
            health_every = int(self.config.schedule.get("health_check_minutes", 15)) * MINUTE_MS
            wake = min(next_bar + int(settle_s * 1000), now + health_every)
            stop.wait(max(1.0, (wake - now) / 1000.0))

    def _heartbeat(self, now: int, status: str) -> None:
        if not self.persist_files:
            return
        path = self.config.var_dir / "heartbeat.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"at": utc_iso(now), "status": status}))

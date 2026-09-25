"""Health checks run every loop and on a schedule. Each check returns ok/warn/fail with a
reason; any fail raises a high-severity alert."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from hedgefund.core.ledger import Kind
from hedgefund.core.timeutil import DAY_MS


@dataclass
class HealthReport:
    checks: dict[str, tuple[str, str]] = field(default_factory=dict)

    def add(self, name: str, status: str, detail: str) -> None:
        self.checks[name] = (status, detail)

    @property
    def status(self) -> str:
        states = {s for s, _ in self.checks.values()}
        return "fail" if "fail" in states else "warn" if "warn" in states else "ok"

    def failures(self) -> list[str]:
        return [f"{k}: {d}" for k, (s, d) in self.checks.items() if s == "fail"]

    def to_dict(self) -> dict:
        return {"status": self.status, "checks": {k: {"status": s, "detail": d} for k, (s, d) in self.checks.items()}}


def _pct(values: list[float], q: float) -> float | None:
    if not values:
        return None
    v = sorted(values)
    return v[min(len(v) - 1, int(q * len(v)))]


def health_check(stack: Any, now: int, data_quality: Any | None = None, latency_budget_ms: float = 500.0, last_bar_ts: int | None = None, interval_ms: int | None = None, verify_ledger: bool = False) -> HealthReport:
    rep = HealthReport()
    ks = stack.kill_switch
    rep.add("kill_switch", "fail" if ks.engaged else "ok", ks.reason or "not engaged")

    nav = stack.portfolio.nav()
    dd = stack.risk.drawdown(nav)
    L = stack.config.risk
    rep.add("drawdown", "fail" if dd >= L.max_drawdown_pct else "warn" if dd >= L.drawdown_reduce_only_pct * 0.75 else "ok", f"{dd:.2%} from high-water mark")
    rep.add("daily_loss_halt", "warn" if stack.risk.halted_day is not None else "ok", "halted until next UTC day" if stack.risk.halted_day is not None else "trading")

    if data_quality is not None:
        rep.add("data_quality", "ok" if data_quality.ok else "fail", "; ".join(data_quality.errors[:3]) or "ok")
    if last_bar_ts is not None and interval_ms:
        lag = (now - last_bar_ts) / interval_ms
        rep.add("loop_freshness", "fail" if lag > 2.5 else "ok", f"last processed bar {lag:.1f} bars ago")

    lat = stack.pipeline.jev_latencies_ms[-500:]
    p50, p99 = _pct(lat, 0.5), _pct(lat, 0.99)
    if p99 is None:
        rep.add("jev_latency", "warn", "no decisions yet")
    else:
        rep.add("jev_latency", "fail" if p99 > latency_budget_ms else "ok", f"p50 {p50:.1f}ms p99 {p99:.1f}ms (budget {latency_budget_ms:.0f}ms)")

    day_ago = now - DAY_MS
    errs = len(stack.ledger.query(kind=Kind.JEV_ERROR, since_ts=day_ago))
    decs = len(stack.ledger.query(kind=Kind.JEV_DECISION, since_ts=day_ago))
    rate = errs / (errs + decs) if errs + decs else 0.0
    rep.add("jev_errors", "fail" if rate > 0.2 else "warn" if rate > 0.05 else "ok", f"{errs} errors / {errs + decs} calls (24h)")

    recon = stack.ledger.query(kind=Kind.RECONCILIATION, newest_first=True, limit=1)
    if recon:
        rep.add("reconciliation", "ok" if recon[0].payload["ok"] else "fail", "last check ok" if recon[0].payload["ok"] else str(recon[0].payload["mismatches"]))
    stale = [o.client_order_id for o in stack.execution.open_orders() if interval_ms and now - o.created_ts > 2 * interval_ms]
    rep.add("open_orders", "warn" if stale else "ok", f"{len(stale)} stale open orders" if stale else "none stale")
    esc = len(stack.ledger.query(kind=Kind.ESCALATION, since_ts=day_ago))
    rep.add("escalations_24h", "warn" if esc > 20 else "ok", f"{esc} escalations to research")
    if verify_ledger:  # O(ledger size): run on the nightly schedule, not every loop
        ok, bad = stack.ledger.verify_chain()
        rep.add("ledger_integrity", "ok" if ok else "fail", "hash chain intact" if ok else f"broken at seq {bad}")
    return rep

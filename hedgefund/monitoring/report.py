"""Daily operator report (markdown). Written every evening and fed to the overnight review."""

from __future__ import annotations

from collections import Counter
from typing import Any

from hedgefund.calibration.tracker import CalibrationTracker
from hedgefund.core.ledger import Kind
from hedgefund.core.timeutil import DAY_MS, utc_date, utc_iso


def _fmt(x: Any, pct: bool = False) -> str:
    if x is None:
        return "-"
    if isinstance(x, float):
        return f"{x:.2%}" if pct else f"{x:,.2f}"
    return str(x)


def daily_report(ledger: Any, portfolio: Any, stages: dict[str, str], now: int, synthetic: bool = False) -> str:
    since = now - DAY_MS
    navs = ledger.query(kind=Kind.NAV, since_ts=since)
    nav_now = portfolio.nav()
    nav_open = navs[0].payload["nav"] if navs else nav_now
    lines = [f"# Daily report - {utc_date(now)}", ""]
    if synthetic:
        lines += ["> **SYNTHETIC DATA** - this report exercises the system; numbers say nothing about real markets.", ""]
    lines += [
        f"- NAV: **{nav_now:,.2f}** ({(nav_now / nav_open - 1) if nav_open else 0:+.2%} over 24h)",
        f"- Gross / net exposure: {portfolio.exposures()['gross'] / nav_now:.2f}x / {portfolio.exposures()['net'] / nav_now:+.2f}x" if nav_now > 0 else "- Exposure: n/a",
        f"- Generated: {utc_iso(now)}",
        "",
        "## Books",
        "",
        "| strategy | stage | equity | fees | funding paid | positions |",
        "|---|---|---:|---:|---:|---|",
    ]
    for sid in sorted(set(stages) | set(portfolio.books)):
        b = portfolio.books.get(sid)
        pos = ", ".join(f"{s} {p.qty:+.4f}" for s, p in (b.positions.items() if b else []) if abs(p.qty) > 1e-12) or "flat"
        lines.append(f"| {sid} | {stages.get(sid, '-')} | {_fmt(portfolio.book_equity(sid))} | {_fmt(b.fees if b else 0.0)} | {_fmt(b.funding if b else 0.0)} | {pos} |")

    pol = Counter(e.payload["action"] for e in ledger.query(kind=Kind.POLICY, since_ts=since))
    fills = [e.payload for e in ledger.query(kind=Kind.FILL, since_ts=since)]
    slips = [f["slippage_bps"] for f in fills if f.get("slippage_bps") is not None]
    rejected = [e.payload for e in ledger.query(kind=Kind.RISK_VERDICT, since_ts=since) if not e.payload["approved"]]
    lines += [
        "",
        "## Activity (24h)",
        "",
        f"- Policy actions: {dict(pol) or 'none'}",
        f"- Fills: {len(fills)}; avg slippage {sum(slips) / len(slips):.2f} bps" if slips else f"- Fills: {len(fills)}",
        f"- Risk rejections: {len(rejected)}" + (f" (e.g. {rejected[0]['violations'][:2]})" if rejected else ""),
        f"- Escalations to research: {len(ledger.query(kind=Kind.ESCALATION, since_ts=since))}",
        f"- Jev errors: {len(ledger.query(kind=Kind.JEV_ERROR, since_ts=since))}",
    ]
    risk_events = ledger.query(kind=[Kind.RISK_EVENT, Kind.KILL_SWITCH], since_ts=since)
    alerts = ledger.query(kind=Kind.ALERT, since_ts=since)
    if risk_events or alerts:
        lines += ["", "## Risk events and alerts", ""]
        lines += [f"- {utc_iso(e.ts)} `{e.kind}` {e.payload}" for e in (risk_events + alerts)[-20:]]
    cal = CalibrationTracker.from_ledger_outcomes(ledger, since_ts=now - 30 * DAY_MS)
    if cal:
        lines += ["", "## Jev calibration (30d, resolved predictions)", "", "| model / strategy / question | n | brier | brier skill | ECE |", "|---|---:|---:|---:|---:|"]
        for k, m in cal.items():
            lines.append(f"| {k} | {m['n']} | {_fmt(m['brier'])} | {_fmt(m['brier_skill'])} | {_fmt(m['ece'])} |")
    pending = [e.payload for e in ledger.query(kind=Kind.APPROVAL_REQUEST) if e.payload.get("status") == "pending"]
    decided = {e.payload.get("request_id") for e in ledger.query(kind=Kind.APPROVAL)}
    pending = [p for p in pending if p["request_id"] not in decided]
    if pending:
        lines += ["", "## Awaiting your approval", ""]
        lines += [f"- `{p['request_id']}` {p.get('kind')}: {p.get('target')} - {p.get('description', '')[:160]}" for p in pending[:20]]
    return "\n".join(lines) + "\n"

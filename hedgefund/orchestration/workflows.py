"""Workflow catalogue: what runs, when, in which layer, producing what. The local runner
(hedgefund/ops/runner.py) implements each by name; an AgentKit deployment must implement the
same names with the same inputs/outputs so the two are interchangeable."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Workflow:
    name: str
    owner: str
    cadence: str  # "per_bar" | "every 15m" | "daily HH:MM UTC" | "weekly" | "on_demand"
    layer: str
    steps: tuple[str, ...]
    outputs: tuple[str, ...]
    failure_policy: str


WORKFLOWS: tuple[Workflow, ...] = (
    Workflow(
        "fast_loop",
        "Portfolio Manager",
        "per_bar",
        "deterministic + jev",
        (
            "load market data (live or replay)",
            "data quality gate (block symbols that fail)",
            "mark portfolio, accrue funding, update risk state (drawdown, daily loss, kill switch)",
            "strategies -> signals (exits never wait for Jev)",
            "Jev typed decision per entry/hold signal (latency budget, fail closed)",
            "deterministic policy -> targets; risk engine -> approve/clip/reject",
            "execution -> orders/fills; reconcile; NAV snapshot",
        ),
        ("ledger: data_quality, jev_decision, policy, risk_verdict, order, fill, nav, escalation",),
        "any exception: alert, no new orders this bar, retry next bar; 3 consecutive strategy crashes while holding -> exit that strategy",
    ),
    Workflow(
        "health_check",
        "Engineering Desk",
        "every 15m",
        "deterministic",
        ("kill switch", "drawdown", "data freshness", "Jev latency p99 and error rate", "reconciliation", "stale orders", "escalation volume"),
        ("alerts",),
        "fail -> high-severity alert to operator",
    ),
    Workflow(
        "evening_review",
        "CIO",
        "daily 20:00 UTC",
        "deterministic",
        ("daily report (NAV, books, activity, risk events, calibration, approvals)",),
        ("var/reports/YYYY-MM-DD.md",),
        "report failure -> alert",
    ),
    Workflow(
        "overnight_research",
        "Research Desk",
        "daily 02:00 UTC",
        "opus",
        (
            "resolve calibration predictions against realized data",
            "evaluate invalidation rules -> demote / halt / retire (risk-reducing only)",
            "verify ledger hash chain",
            "Opus: market scan (5-10 opportunities), escalation reviews, overnight review",
            "file proposals in the approval queue (nothing is applied automatically)",
        ),
        ("research memos", "approval requests", "stage transitions (demotions only)"),
        "research failures never affect trading; logged and retried next night",
    ),
    Workflow(
        "strategy_pipeline",
        "Investment Committee",
        "on_demand",
        "orchestration + deterministic",
        ("spec -> data gate -> signal code + tests -> backtest -> cost model -> stress -> risk review -> paper -> shadow -> live",),
        ("evidence bundles", "stage transitions"),
        "gate failure leaves the strategy where it is; LIVE needs a named human",
    ),
    Workflow(
        "recalibration",
        "Quant Desk",
        "weekly",
        "deterministic",
        ("fit Platt maps on older resolved predictions", "accept only maps that improve holdout Brier", "replay backtest with the new bundle", "operator enables bundle in config"),
        ("var/calibration/calibration-<version>.json",),
        "rejected bundles are recorded, never deployed",
    ),
)

"""Live strategy health: computes each spec's invalidation metrics from the ledger and
reports breaches. Breaches demote, halt or retire automatically - reducing risk never
waits for a human; restoring it always does."""

from __future__ import annotations

import math
from typing import Any

from hedgefund.calibration.metrics import brier
from hedgefund.core.ledger import Kind
from hedgefund.core.timeutil import DAY_MS
from hedgefund.strategy.spec import StrategySpec


def strategy_metrics(ledger: Any, strategy_id: str, now: int, window_days: int = 90) -> dict[str, tuple[float | None, int]]:
    since = now - window_days * DAY_MS
    navs = ledger.query(kind=Kind.NAV, since_ts=since)
    eq = [(e.payload["books"].get(strategy_id, 0.0), e.payload["nav"]) for e in navs if "books" in e.payload]
    out: dict[str, tuple[float | None, int]] = {}
    if len(eq) >= 3:
        rets = [(eq[i][0] - eq[i - 1][0]) / eq[i - 1][1] for i in range(1, len(eq)) if eq[i - 1][1] > 0]
        mean = sum(rets) / len(rets)
        sd = math.sqrt(sum((r - mean) ** 2 for r in rets) / max(len(rets) - 1, 1))
        span_days = max((navs[-1].ts - navs[0].ts) / DAY_MS, 1e-9)
        per_year = len(rets) / span_days * 365
        out["rolling_sharpe_90d"] = (mean / sd * math.sqrt(per_year) if sd > 0 else 0.0, len(rets))
        peak, mdd = -math.inf, 0.0
        for e, nav in eq:
            peak = max(peak, e)
            mdd = max(mdd, (peak - e) / nav if nav > 0 else 0.0)
        out["strategy_drawdown"] = (mdd, len(eq))
    fills = [e.payload for e in ledger.query(kind=Kind.FILL, since_ts=since) if e.payload.get("strategy_id") == strategy_id]
    slips = [f["slippage_bps"] for f in fills if f.get("slippage_bps") is not None]
    out["avg_slippage_bps"] = (sum(slips) / len(slips) if slips else None, len(slips))
    closes = [f["realized_pnl"] for f in fills if f.get("realized_pnl")]
    out["hit_rate"] = (sum(1 for x in closes if x > 0) / len(closes) if closes else None, len(closes))
    outcomes = [e.payload for e in ledger.query(kind=Kind.CALIBRATION_OUTCOME, since_ts=since) if e.payload.get("strategy_id") == strategy_id]
    for q in ("should_trade", "direction", "regime"):
        rows = [o for o in outcomes if o["question"] == q]
        out[f"brier_{q}"] = (brier([r["prob"] for r in rows], [r["outcome"] for r in rows]), len(rows))
    return out


def evaluate_invalidation(spec: StrategySpec, metrics: dict[str, tuple[float | None, int]]) -> list[dict[str, Any]]:
    breaches = []
    for rule in spec.invalidation:
        value, n = metrics.get(rule.metric, (None, 0))
        if rule.breached(value, n):
            breaches.append({"metric": rule.metric, "value": value, "op": rule.op, "threshold": rule.threshold, "observations": n, "action": rule.action})
    return breaches

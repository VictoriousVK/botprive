"""Research workflow glue: dated evidence from our own data, escalation queue, and conversion
of Opus strategy drafts into validated StrategySpecs at the HYPOTHESIS stage.

Every number handed to Opus comes from the fund's own data pipeline with a source and an
as-of timestamp, so memo facts are traceable to ledger records.
"""

from __future__ import annotations

import math
from typing import Any

from hedgefund.core.ids import new_id
from hedgefund.core.ledger import Kind
from hedgefund.core.timeutil import DAY_MS, utc_date, utc_iso
from hedgefund.data.features import FUNDING_PERIODS_PER_YEAR, annualized_vol, stablecoin_growth
from hedgefund.data.series import MarketData
from hedgefund.research.opus import OpusResearcher, OpusResult
from hedgefund.strategy.spec import Stage, StrategySpec, spec_from_dict


def market_evidence(data: MarketData, t: int) -> list[dict[str, Any]]:
    view = data.view(t)
    bpd = int(DAY_MS // data.interval_ms)
    ev: list[dict[str, Any]] = []

    def src(key: str) -> str:
        p = data.provenance.get(key) or {}
        s = p.get("source", "unknown")
        return f"{s} (SYNTHETIC)" if p.get("synthetic") else s

    for sym in data.symbols():
        if not view.has(sym, 2):
            continue
        close = view.last_close(sym)
        item = {"metric": f"{sym} close", "value": close, "as_of": utc_iso(t), "source": src(sym)}
        ev.append(item)
        for days in (7, 30, 90):
            m = view.momentum(sym, days * bpd)
            if m is not None:
                ev.append({"metric": f"{sym} {days}d return", "value": round(m, 4), "as_of": utc_iso(t), "source": src(sym)})
        rv = annualized_vol(view, sym, 30, bpd)
        if rv is not None:
            ev.append({"metric": f"{sym} 30d realized vol (annualized)", "value": round(rv, 4), "as_of": utc_iso(t), "source": src(sym)})
        f = view.funding(sym, 21)
        if f:
            ev.append({"metric": f"{sym} 7d avg funding (annualized)", "value": round(sum(f) / len(f) * FUNDING_PERIODS_PER_YEAR, 4), "as_of": utc_iso(t), "source": src(sym)})
        oi_now, oi_then = view.open_interest_at(sym, t), view.open_interest_at(sym, t - 7 * DAY_MS)
        if oi_now and oi_then:
            ev.append({"metric": f"{sym} open interest 7d change", "value": round(oi_now / oi_then - 1, 4), "as_of": utc_iso(t), "source": src(sym)})
    if view.has("ETHUSDT", 30 * bpd) and view.has("BTCUSDT", 30 * bpd):
        r_now = view.last_close("ETHUSDT") / view.last_close("BTCUSDT")
        r_then = view.close_ago("ETHUSDT", 30 * bpd) / view.close_ago("BTCUSDT", 30 * bpd)
        ev.append({"metric": "ETH/BTC 30d change", "value": round(r_now / r_then - 1, 4), "as_of": utc_iso(t), "source": src("ETHUSDT")})
    for days in (30, 90):
        g = stablecoin_growth(view, days)
        if g is not None:
            ev.append({"metric": f"stablecoin supply {days}d growth", "value": round(g, 4), "as_of": utc_iso(t), "source": src("stablecoin_supply_usd")})
    return [e for e in ev if not (isinstance(e["value"], float) and not math.isfinite(e["value"]))]


def coalesce_escalations(ledger: Any, since_ts: int, until_ts: int) -> list[dict[str, Any]]:
    """Group raw escalation events into review tasks: one per (strategy, package, cause)."""
    tasks: dict[tuple[str, str, str], dict[str, Any]] = {}
    for e in ledger.query(kind=Kind.ESCALATION, since_ts=since_ts, until_ts=until_ts):
        p = e.payload
        cause = "crisis" if "crisis" in p["reason"] else "low_confidence"
        key = (p["strategy_id"], p["package"], cause)
        t = tasks.setdefault(key, {"strategy_id": key[0], "package": key[1], "cause": cause, "count": 0, "first": utc_iso(e.ts), "last": None, "samples": []})
        t["count"] += 1
        t["last"] = utc_iso(e.ts)
        if len(t["samples"]) < 5:
            t["samples"].append({"at": utc_iso(e.ts), "reason": p["reason"], "action_taken": p["action_taken"], "decision_id": p["decision_id"]})
    return list(tasks.values())


def spec_from_draft(draft: dict[str, Any], memo_id: str | None, known_symbols: set[str]) -> tuple[StrategySpec | None, list[str]]:
    raw = {
        "id": draft["id"],
        "name": draft["name"],
        "version": 1,
        "owner_desk": "research",
        "stage": Stage.HYPOTHESIS.value,
        "impl": None,  # Engineering desk implements and registers code before the SIGNAL gate
        "hypothesis": draft["hypothesis"],
        "edge_source": draft["edge_source"],
        "universe": draft["universe"],
        "packages": draft["packages"],
        "timeframe": draft["timeframe"],
        "allowed_directions": draft["allowed_directions"],
        "features": draft["features"],
        "entry_rules": draft["entry_rules"],
        "exit_rules": draft["exit_rules"],
        "expected_holding": draft["expected_holding"],
        "params": {p["name"]: p["value"] for p in draft["parameters"]},
        "risk": {**draft["risk"], "rebalance_threshold": 0.35, "exit_on_crisis": True},
        "costs": draft["costs"],
        "liquidity": {"min_bar_notional_volume": 50_000_000},
        "jev": {**{k: v for k, v in draft["jev"].items() if k != "instructions"}, "instructions": {i["question"]: i["text"] for i in draft["jev"]["instructions"]}},
        "invalidation": draft["invalidation"],
        "data_sources": draft["data_sources"],
        "failure_modes": draft["failure_modes"],
        "capacity_usd": draft["capacity_usd"],
        "research_memo": memo_id,
    }
    try:
        spec = spec_from_dict(raw)
    except (KeyError, ValueError, TypeError) as e:
        return None, [f"draft could not be parsed: {e}"]
    problems = spec.validate(known_symbols)
    return (None if problems else spec), problems


def record_result(ledger: Any, result: OpusResult, ts: int, kind: str = Kind.RESEARCH_MEMO) -> str:
    memo_id = new_id("memo")
    ledger.append(kind, {"memo_id": memo_id, "task": result.task, "model": result.model, "usage": result.usage, "request_id": result.request_id, "data": result.data}, ts=ts, ref=memo_id)
    return memo_id


def request_approvals(ledger: Any, proposals: list[dict[str, Any]], source_memo: str, ts: int) -> list[str]:
    ids = []
    for p in proposals:
        rid = new_id("req")
        ledger.append(Kind.APPROVAL_REQUEST, {"request_id": rid, "status": "pending", "source_memo": source_memo, **p}, ts=ts, ref=rid)
        ids.append(rid)
    return ids


def run_overnight_research(researcher: OpusResearcher, ledger: Any, data: MarketData, report_md: str, calibration: dict[str, Any], t: int, max_escalation_reviews: int = 5) -> dict[str, Any]:
    """Overnight Layer-1 workflow. Returns ids of everything it wrote. Nothing is applied."""
    out: dict[str, Any] = {"memos": [], "approval_requests": [], "errors": []}
    evidence = market_evidence(data, t)

    def attempt(fn, *args, kind=Kind.RESEARCH_MEMO):
        try:
            res = fn(*args)
        except Exception as e:  # noqa: BLE001 - research failures must not affect trading
            out["errors"].append(f"{getattr(fn, '__name__', 'task')}: {type(e).__name__}: {e}")
            ledger.append(Kind.ALERT, {"severity": "low", "message": f"research task failed: {e}"}, ts=t)
            return None, None
        return res, record_result(ledger, res, t, kind)

    scan, scan_id = attempt(researcher.market_scan, evidence, utc_date(t))
    if scan_id:
        out["memos"].append(scan_id)
    for task in coalesce_escalations(ledger, t - DAY_MS, t)[:max_escalation_reviews]:
        _, rid = attempt(researcher.review_escalation, task, evidence, kind=Kind.RESEARCH_REVIEW)
        if rid:
            out["memos"].append(rid)
    review, review_id = attempt(researcher.overnight_review, report_md, calibration, kind=Kind.RESEARCH_REVIEW)
    if review is not None:
        out["memos"].append(review_id)
        out["approval_requests"] = request_approvals(ledger, review.data.get("proposals", []), review_id, t)
    return out

"""Journal statistics in R multiples, with honest uncertainty, and measurable behaviours.

- Win rate with a Wilson 95 % interval; expectancy in R with a seeded bootstrap interval.
- Breakdowns by killzone, setup, weekday, symbol, session and direction.
- Behaviour flags computed from the trades and the member's declared plan: overtrading, revenge
  trading, size increase after a loss, plan violations, trades outside the plan's killzones, risk
  above the plan, daily loss limit, exits well before the planned target. No psychology is
  inferred: only what the data and the plan show.
"""

from __future__ import annotations

import math
import random
import statistics
from collections import defaultdict
from collections.abc import Iterable
from datetime import datetime, timezone
from typing import Any

from hedgefund.strategy.library import ict_clock as clk

Z95 = 1.959963984540054
WEEKDAYS = ("dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi")


def wilson(wins: int, n: int, z: float = Z95) -> tuple[float, float] | None:
    if n <= 0:
        return None
    p = wins / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return (max(0.0, centre - half), min(1.0, centre + half))


def bootstrap_mean_ci(values: list[float], samples: int = 2000, seed: int = 7, level: float = 0.95) -> tuple[float, float] | None:
    if len(values) < 2:
        return None
    rng = random.Random(seed)
    n = len(values)
    means = sorted(sum(values[rng.randrange(n)] for _ in range(n)) / n for _ in range(samples))
    lo = means[int((1 - level) / 2 * samples)]
    hi = means[min(samples - 1, int((1 + level) / 2 * samples))]
    return (lo, hi)


def _closed(trades: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    return sorted((t for t in trades if t.get("close_utc")), key=lambda t: t["close_utc"])


def _group_stats(rows: list[dict[str, Any]]) -> dict[str, Any]:
    n = len(rows)
    wins = sum(1 for t in rows if (t.get("net") or 0) > 0)
    rs = [t["r_multiple"] for t in rows if t.get("r_multiple") is not None]
    return {
        "n": n, "wins": wins, "win_rate": round(wins / n, 4) if n else None, "net": round(sum(t.get("net") or 0 for t in rows), 2),
        "expectancy_r": round(statistics.fmean(rs), 3) if rs else None, "r_count": len(rs),
    }


def breakdown(rows: list[dict[str, Any]], key: str, label=None) -> list[dict[str, Any]]:
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for t in rows:
        k = t.get(key)
        groups["—" if k is None else (label(k) if label else str(k))].append(t)
    out = [{"key": k, **_group_stats(v)} for k, v in groups.items()]
    return sorted(out, key=lambda g: (-g["n"], g["key"]))


def max_drawdown_series(values: list[float]) -> float:
    peak = 0.0
    cum = 0.0
    dd = 0.0
    for v in values:
        cum += v
        peak = max(peak, cum)
        dd = max(dd, peak - cum)
    return dd


def kpis(trades: Iterable[dict[str, Any]], min_trades: int = 20, warn_below: int = 30, bootstrap_samples: int = 2000) -> dict[str, Any]:
    rows = _closed(trades)
    n = len(rows)
    wins = [t for t in rows if (t.get("net") or 0) > 0]
    losses = [t for t in rows if (t.get("net") or 0) < 0]
    rs = [t["r_multiple"] for t in rows if t.get("r_multiple") is not None]
    gross_win = sum(t["net"] for t in wins)
    gross_loss = -sum(t["net"] for t in losses)
    streak = worst = 0
    for t in rows:
        streak = streak + 1 if (t.get("net") or 0) < 0 else 0
        worst = max(worst, streak)
    wr = len(wins) / n if n else None
    ci = wilson(len(wins), n)
    exp_ci = bootstrap_mean_ci(rs, bootstrap_samples)
    return {
        "n": n,
        "open_positions": sum(1 for t in trades if not t.get("close_utc")) if isinstance(trades, list) else None,
        "wins": len(wins), "losses": len(losses), "breakeven": n - len(wins) - len(losses),
        "win_rate": round(wr, 4) if wr is not None else None,
        "win_rate_ci95": [round(ci[0], 4), round(ci[1], 4)] if ci else None,
        "expectancy_r": round(statistics.fmean(rs), 3) if rs else None,
        "expectancy_r_ci95": [round(exp_ci[0], 3), round(exp_ci[1], 3)] if exp_ci else None,
        "r_coverage": round(len(rs) / n, 4) if n else None,
        "avg_win_r": round(statistics.fmean([r for r in rs if r > 0]), 3) if any(r > 0 for r in rs) else None,
        "avg_loss_r": round(statistics.fmean([r for r in rs if r < 0]), 3) if any(r < 0 for r in rs) else None,
        "profit_factor": round(gross_win / gross_loss, 3) if gross_loss > 0 else None,
        "net_total": round(sum(t.get("net") or 0 for t in rows), 2),
        "max_drawdown": round(max_drawdown_series([t.get("net") or 0 for t in rows]), 2),
        "max_drawdown_r": round(max_drawdown_series([t["r_multiple"] for t in rows if t.get("r_multiple") is not None]), 3) if rs else None,
        "max_consecutive_losses": worst,
        "insufficient": n < min_trades,
        "sample_warning": n < warn_below,
        "min_trades": min_trades,
        "by_killzone": breakdown(rows, "killzone"),
        "by_setup": breakdown(rows, "setup_model"),
        "by_weekday": breakdown(rows, "weekday", lambda d: WEEKDAYS[int(d) % 7]),
        "by_symbol": breakdown(rows, "symbol"),
        "by_session": breakdown(rows, "session"),
        "by_direction": breakdown(rows, "side"),
    }


def equity_curve(trades: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    cum = cum_r = 0.0
    out = []
    for t in _closed(trades):
        cum += t.get("net") or 0
        cum_r += t.get("r_multiple") or 0
        out.append({"t": t["close_utc"], "net": round(cum, 2), "r": round(cum_r, 3), "trade_id": t.get("id")})
    return out


def setup_stats(trades: Iterable[dict[str, Any]], model: str, warn_below: int = 30) -> dict[str, Any]:
    rows = [t for t in _closed(trades) if t.get("setup_model") == model]
    n = len(rows)
    wins = sum(1 for t in rows if (t.get("net") or 0) > 0)
    rs = [t["r_multiple"] for t in rows if t.get("r_multiple") is not None]
    ci = wilson(wins, n)
    eci = bootstrap_mean_ci(rs)
    return {
        "model": model, "n": n, "win_rate": round(wins / n, 4) if n else None, "win_rate_ci95": [round(ci[0], 4), round(ci[1], 4)] if ci else None,
        "expectancy_r": round(statistics.fmean(rs), 3) if rs else None, "expectancy_r_ci95": [round(eci[0], 3), round(eci[1], 3)] if eci else None,
        "sample_warning": n < warn_below,
    }


def _day(ms: int) -> str:
    return datetime.fromtimestamp(clk.utc_to_ny(ms) / 1000, tz=timezone.utc).strftime("%Y-%m-%d")


def behavior_flags(trades: Iterable[dict[str, Any]], plan: dict[str, Any], balance: float | None = None, events: list[dict[str, Any]] | None = None) -> list[dict[str, Any]]:
    """Measurable behaviours, each with the trades concerned, the metric, the value and the
    threshold it crossed (declared in the plan, or the plan's defaults)."""
    rows = sorted((t for t in trades if t.get("open_utc")), key=lambda t: t["open_utc"])
    flags: list[dict[str, Any]] = []
    max_day = int(plan.get("max_trades_per_day") or 0)
    revenge_min = int(plan.get("revenge_minutes") or 15)
    size_factor = float(plan.get("size_up_factor") or 1.5)
    kz_plan = set(plan.get("killzones") or [])
    risk_pct = float(plan.get("risk_per_trade_pct") or 0)
    max_daily_loss = float(plan.get("max_daily_loss_pct") or 0)

    by_day: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for t in rows:
        by_day[_day(t["open_utc"])].append(t)
    if max_day:
        for day, ts in sorted(by_day.items()):
            if len(ts) > max_day:
                flags.append({"kind": "overtrading", "trade_ids": [t["id"] for t in ts], "metric": "trades_par_jour", "value": float(len(ts)), "threshold": float(max_day),
                              "detail": f"{day} : {len(ts)} trades pour {max_day} prévus au plan"})
    if max_daily_loss and balance:
        for day, ts in sorted(by_day.items()):
            loss = -sum(t.get("net") or 0 for t in ts if t.get("close_utc"))
            pct = loss / balance * 100
            if pct > max_daily_loss:
                flags.append({"kind": "plan_violation", "trade_ids": [t["id"] for t in ts], "metric": "perte_journaliere_pct", "value": round(pct, 2), "threshold": max_daily_loss,
                              "detail": f"{day} : perte de {pct:.2f} % pour une limite de {max_daily_loss:.2f} %"})

    closed = [t for t in rows if t.get("close_utc")]
    for t in rows:
        prev_losses = [p for p in closed if p["close_utc"] <= t["open_utc"] and p["id"] != t["id"] and p.get("account_id") == t.get("account_id")]
        if not prev_losses:
            continue
        last = max(prev_losses, key=lambda p: p["close_utc"])
        if (last.get("net") or 0) >= 0:
            continue
        gap_min = (t["open_utc"] - last["close_utc"]) / 60_000
        if gap_min <= revenge_min:
            flags.append({"kind": "revenge_trade", "trade_ids": [last["id"], t["id"]], "metric": "minutes_apres_perte", "value": round(gap_min, 1), "threshold": float(revenge_min),
                          "detail": f"trade ouvert {gap_min:.0f} min après une perte (seuil du plan : {revenge_min} min)"})
        if last.get("symbol") == t.get("symbol") and last.get("volume") and t.get("volume") and t["volume"] >= size_factor * last["volume"] - 1e-12:
            flags.append({"kind": "size_up_after_loss", "trade_ids": [last["id"], t["id"]], "metric": "ratio_volume", "value": round(t["volume"] / last["volume"], 2),
                          "threshold": size_factor, "detail": f"volume {last['volume']:g} → {t['volume']:g} juste après une perte"})

    viol = [t for t in rows if t.get("plan_respected") is False]
    if viol:
        flags.append({"kind": "plan_violation", "trade_ids": [t["id"] for t in viol], "metric": "trades_hors_plan", "value": float(len(viol)), "threshold": 0.0,
                      "detail": f"{len(viol)} trade(s) marqué(s) hors plan"})
    if kz_plan:
        out_kz = [t for t in rows if t.get("killzone") not in kz_plan]
        if out_kz:
            flags.append({"kind": "outside_killzone", "trade_ids": [t["id"] for t in out_kz], "metric": "trades_hors_killzones", "value": float(len(out_kz)), "threshold": 0.0,
                          "detail": f"{len(out_kz)} trade(s) hors des killzones du plan ({', '.join(sorted(kz_plan))})"})
    if risk_pct and balance:
        risky = [t for t in rows if t.get("r_source") == "sl" and t.get("risk_amount") and t["risk_amount"] / balance * 100 > risk_pct * 1.25]
        if risky:
            worst = max(t["risk_amount"] / balance * 100 for t in risky)
            flags.append({"kind": "risk_above_plan", "trade_ids": [t["id"] for t in risky], "metric": "risque_max_pct", "value": round(worst, 2), "threshold": risk_pct,
                          "detail": f"{len(risky)} trade(s) au-delà du risque prévu ({risk_pct:.2f} %)"})
    early = []
    for t in closed:
        tp, sl, op, cp, r = t.get("tp"), t.get("sl"), t.get("open_price"), t.get("close_price"), t.get("r_multiple")
        if tp and sl and op and cp and r is not None and t.get("r_source") == "sl":
            planned = abs(tp - op) / max(1e-12, abs(op - sl))
            if planned >= 1.5 and 0 < r < 0.5 * planned:
                early.append(t)
    if early:
        flags.append({"kind": "early_exit", "trade_ids": [t["id"] for t in early], "metric": "sorties_avant_objectif", "value": float(len(early)), "threshold": 0.0,
                      "detail": f"{len(early)} trade(s) gagnant(s) fermé(s) avant la moitié de l'objectif prévu"})
    if events:
        hits = []
        for t in rows:
            for e in events:
                if e.get("impact") == "high" and abs(t["open_utc"] - e["time_utc"]) <= 15 * 60_000:
                    hits.append(t)
                    break
        if hits:
            flags.append({"kind": "news_window", "trade_ids": [t["id"] for t in hits], "metric": "trades_pres_annonces", "value": float(len(hits)), "threshold": 0.0,
                          "detail": f"{len(hits)} trade(s) ouvert(s) à moins de 15 min d'une annonce à fort impact"})
    return flags

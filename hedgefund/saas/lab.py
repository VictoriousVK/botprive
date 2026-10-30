"""Validation lab: honest answers to "is this luck?" and "why does real differ from demo?".

- Monte Carlo on the member's R multiples: drawdown distribution and the chance of breaching a
  loss limit, by reshuffling the order of the trades (seeded, reproducible).
- Demo vs real: trades of two accounts matched by symbol, direction and time; entry and exit
  slippage, costs, R and timing differences, with the likely causes.
- Robustness of a platform strategy: one backtest cut into consecutive windows (stability
  across windows; the templates have fixed parameters, so no re-optimisation), and the deflated
  Sharpe ratio counting every configuration the member has tried (multiple testing).
"""

from __future__ import annotations

import random
import statistics
from typing import Any

from fastapi import Depends
from pydantic import BaseModel, Field
from sqlalchemy import desc

from hedgefund.saas.api import ROUTERS, ApiContext, guard
from hedgefund.saas.db import lab_reports, new_id, now_ms
from hedgefund.saas.engines.perf import max_drawdown_series
from hedgefund.saas.service import Access, SaaS


def monte_carlo(rs: list[float], risk_pct: float, limit_pct: float | None, sims: int = 2000, seed: int = 11, horizon: int | None = None) -> dict[str, Any]:
    """``rs``: R multiples; ``risk_pct``: risk per trade in % of capital; ``limit_pct``: maximum
    loss (% of capital) whose breach is counted."""
    if len(rs) < 10:
        raise ValueError("au moins 10 trades avec un R connu sont nécessaires")
    rng = random.Random(seed)
    n = horizon or len(rs)
    dds, finals, breaches = [], [], 0
    for _ in range(sims):
        seq = [rs[rng.randrange(len(rs))] for _ in range(n)]
        dd = max_drawdown_series(seq) * risk_pct
        dds.append(dd)
        finals.append(sum(seq) * risk_pct)
        if limit_pct is not None and dd >= limit_pct:
            breaches += 1
    dds.sort()
    finals.sort()
    q = lambda xs, p: round(xs[min(len(xs) - 1, int(p * len(xs)))], 2)  # noqa: E731
    return {
        "trades": len(rs), "horizon": n, "sims": sims, "seed": seed, "risk_pct": risk_pct,
        "max_drawdown_pct": {"p50": q(dds, 0.5), "p95": q(dds, 0.95), "p99": q(dds, 0.99)},
        "final_return_pct": {"p05": q(finals, 0.05), "p50": q(finals, 0.5), "p95": q(finals, 0.95)},
        "breach_probability": round(breaches / sims, 4) if limit_pct is not None else None, "limit_pct": limit_pct,
        "expectancy_r": round(statistics.fmean(rs), 3),
    }


def match_trades(demo: list[dict[str, Any]], real: list[dict[str, Any]], window_ms: int = 5 * 60_000) -> list[tuple[dict[str, Any], dict[str, Any]]]:
    pairs = []
    used: set[str] = set()
    for d in sorted(demo, key=lambda t: t["open_utc"]):
        best = None
        for r in real:
            if r["id"] in used or r["symbol"] != d["symbol"] or r["side"] != d["side"]:
                continue
            if d.get("magic") and r.get("magic") and d["magic"] != r["magic"]:
                continue
            gap = abs(r["open_utc"] - d["open_utc"])
            if gap <= window_ms and (best is None or gap < abs(best["open_utc"] - d["open_utc"])):
                best = r
        if best is not None:
            used.add(best["id"])
            pairs.append((d, best))
    return pairs


def demo_vs_real(demo: list[dict[str, Any]], real: list[dict[str, Any]]) -> dict[str, Any]:
    demo = [t for t in demo if t.get("close_utc")]
    real = [t for t in real if t.get("close_utc")]
    pairs = match_trades(demo, real)
    if not pairs:
        return {"matched": 0, "demo_only": len(demo), "real_only": len(real), "causes": ["aucun trade apparié (même symbole, même sens, à moins de 5 minutes)"]}
    sign = lambda t: 1 if t["side"] == "long" else -1  # noqa: E731
    entry_slip = [(r["open_price"] - d["open_price"]) * sign(d) for d, r in pairs]
    exit_slip = [(d["close_price"] - r["close_price"]) * sign(d) for d, r in pairs if d.get("close_price") and r.get("close_price")]
    r_diff = [(r["r_multiple"] - d["r_multiple"]) for d, r in pairs if d.get("r_multiple") is not None and r.get("r_multiple") is not None]
    cost_diff = [((r["commission"] or 0) + (r["swap"] or 0)) - ((d["commission"] or 0) + (d["swap"] or 0)) for d, r in pairs]
    timing = [(r["open_utc"] - d["open_utc"]) / 1000 for d, r in pairs]
    out = {
        "matched": len(pairs), "demo_only": len(demo) - len(pairs), "real_only": len(real) - len(pairs),
        "entry_slippage_avg": round(statistics.fmean(entry_slip), 5), "exit_slippage_avg": round(statistics.fmean(exit_slip), 5) if exit_slip else None,
        "r_diff_avg": round(statistics.fmean(r_diff), 3) if r_diff else None, "cost_diff_avg": round(statistics.fmean(cost_diff), 2),
        "timing_diff_avg_s": round(statistics.fmean(timing), 1), "net_demo": round(sum(d["net"] for d, _ in pairs), 2), "net_real": round(sum(r["net"] for _, r in pairs), 2),
    }
    causes = []
    if out["entry_slippage_avg"] > 0:
        causes.append("entrées moins bonnes en réel (spread plus large, slippage ou exécution plus lente)")
    if out["exit_slippage_avg"] is not None and out["exit_slippage_avg"] > 0:
        causes.append("sorties moins bonnes en réel (stops glissés, spread à la sortie)")
    if out["cost_diff_avg"] < 0:
        causes.append("frais plus élevés en réel (commission, swap)")
    if out["demo_only"] > 0:
        causes.append(f"{out['demo_only']} trade(s) pris en démo sans équivalent en réel (ordre rejeté, filtre de spread, requote, EA arrêté)")
    if abs(out["timing_diff_avg_s"]) > 30:
        causes.append("décalage de timing entre les deux comptes (heure serveur, latence du VPS, file d'ordres)")
    out["causes"] = causes or ["pas d'écart d'exécution notable sur les trades appariés"]
    return out


def robustness(saas: SaaS, bot: dict[str, Any], folds: int, n_trials: int) -> dict[str, Any]:
    from hedgefund.backtest import metrics as M

    engine = saas.platform
    if engine is None:
        raise ValueError("laboratoire indisponible : plateforme de trading non chargée")
    from hedgefund.bots.engine import EngineError

    try:
        bt = engine.backtest(bot)
    except EngineError as e:
        raise ValueError(str(e)) from e
    nav = [p["nav"] for p in bt["equity"]]
    if len(nav) < folds * 10:
        raise ValueError("historique trop court pour ce découpage")
    rets = M.simple_returns(nav)
    per = len(rets) // folds
    windows = []
    for k in range(folds):
        seg = rets[k * per: (k + 1) * per]
        windows.append({"window": k + 1, "return_pct": round((M.fold_returns(nav, folds)[k]) * 100, 2), "sharpe_per_period": round(statistics.fmean(seg) / statistics.pstdev(seg), 4) if len(seg) > 1 and statistics.pstdev(seg) > 0 else None})
    positive = sum(1 for w in windows if w["return_pct"] > 0)
    dsr = M.deflated_sharpe(rets, max(1, n_trials))
    return {"synthetic": bt["synthetic"], "bars": bt["bars"], "from": bt["from"], "to": bt["to"], "metrics": bt["metrics"], "closed_trades": bt["closed_trades"],
            "windows": windows, "positive_windows": positive, "folds": folds, "n_trials": n_trials, "deflated_sharpe": round(dsr, 4),
            "verdict": "robuste selon ce test" if dsr >= 0.5 and positive >= max(1, folds - 1) else "non démontré : probablement du bruit ou du sur-ajustement",
            "caveats": ["prix simulés : test de démonstration"] if bt["synthetic"] else []}


# ---------------------------------------------------------------- routes
class MonteCarloIn(BaseModel):
    days: int = Field(default=180, ge=7, le=3660)
    risk_pct: float | None = Field(default=None, gt=0, le=10)
    limit_pct: float | None = Field(default=10.0, gt=0, le=100)
    sims: int = Field(default=2000, ge=200, le=20_000)


class DemoRealIn(BaseModel):
    demo_account_id: str = Field(min_length=4, max_length=40)
    real_account_id: str = Field(min_length=4, max_length=40)
    days: int = Field(default=90, ge=7, le=3660)


class RobustIn(BaseModel):
    strategy: str = Field(min_length=2, max_length=30)
    symbol: str = Field(min_length=2, max_length=20)
    timeframe: str = Field(default="5m", pattern=r"^(1m|5m|15m|1h|4h|1d)$")
    params: dict[str, float] = Field(default_factory=dict)
    folds: int = Field(default=4, ge=2, le=10)


class Lab:
    def __init__(self, saas: SaaS):
        self.saas = saas

    def _save(self, acc: Access, kind: str, title: str, body: dict[str, Any]) -> dict[str, Any]:
        rid = new_id("lab")
        with self.saas.db.tenant(acc.tenant_id) as s:
            s.insert(lab_reports, {"id": rid, "user_id": acc.member_id, "kind": kind, "title": title[:160], "body": body, "created_at": now_ms()})
        return {"id": rid, "kind": kind, "title": title, **body}

    def monte_carlo(self, acc: Access, body: MonteCarloIn) -> dict[str, Any]:
        acc.require("lab", "Laboratoire")
        journal = self.saas.modules["journal"]
        with self.saas.db.tenant(acc.tenant_id) as s:
            rows = journal.list_trades(s, acc.member_id, since=now_ms() - body.days * 86_400_000, closed_only=True, limit=20_000)
            plan = journal.plan(s, acc.member_id)
        rs = [t["r_multiple"] for t in rows if t.get("r_multiple") is not None]
        res = monte_carlo(rs, body.risk_pct or float(plan.get("risk_per_trade_pct") or 1.0), body.limit_pct, body.sims)
        return self._save(acc, "monte_carlo", f"Monte Carlo sur {len(rs)} trades", res)

    def demo_vs_real(self, acc: Access, body: DemoRealIn) -> dict[str, Any]:
        acc.require("lab", "Laboratoire")
        journal = self.saas.modules["journal"]
        since = now_ms() - body.days * 86_400_000
        with self.saas.db.tenant(acc.tenant_id) as s:
            journal.account(s, acc.member_id, body.demo_account_id)
            journal.account(s, acc.member_id, body.real_account_id)
            demo = journal.list_trades(s, acc.member_id, since=since, account_id=body.demo_account_id, limit=20_000)
            real = journal.list_trades(s, acc.member_id, since=since, account_id=body.real_account_id, limit=20_000)
        return self._save(acc, "demo_vs_real", "Rapport démo / réel", demo_vs_real(demo, real))

    def robustness(self, acc: Access, body: RobustIn) -> dict[str, Any]:
        acc.require("lab", "Laboratoire")
        from hedgefund.bots.templates import TEMPLATES

        if body.strategy not in TEMPLATES:
            raise LookupError("stratégie inconnue")
        self.saas.consume(acc, "backtest")
        with self.saas.db.tenant(acc.tenant_id) as s:
            n_trials = 1 + sum(1 for r in s.select(lab_reports, {"user_id": acc.member_id, "kind": "robustness"}) if (r["body"] or {}).get("strategy") == body.strategy)
        from hedgefund.bots.templates import new_bot_id

        bot = {"id": new_bot_id(), "name": "lab", "strategy": body.strategy, "symbols": [body.symbol], "timeframe": body.timeframe, "direction": "both",
               "risk_per_trade_pct": 0.5, "max_position_pct": 10, "params": body.params, "status": "stopped"}
        res = robustness(self.saas, bot, body.folds, n_trials)
        return self._save(acc, "robustness", f"Robustesse {body.strategy} {body.symbol} {body.timeframe}", {**res, "strategy": body.strategy, "params": body.params})

    def reports(self, acc: Access) -> list[dict[str, Any]]:
        with self.saas.db.tenant(acc.tenant_id) as s:
            return s.select(lab_reports, {"user_id": acc.member_id}, order_by=desc(lab_reports.c.created_at), limit=50)


def mount(ctx: ApiContext) -> None:
    app, saas = ctx.app, ctx.saas
    lab: Lab = saas.modules["lab"]
    acc_dep = ctx.acc()

    @app.post("/api/app/lab/monte-carlo")
    def mc(body: MonteCarloIn, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: lab.monte_carlo(acc, body))

    @app.post("/api/app/lab/demo-vs-real")
    def dvr(body: DemoRealIn, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: lab.demo_vs_real(acc, body))

    @app.post("/api/app/lab/robustness")
    def rob(body: RobustIn, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: lab.robustness(acc, body))

    @app.get("/api/app/lab/reports")
    def reports(acc: Access = Depends(acc_dep)) -> list[dict]:  # noqa: B008
        return lab.reports(acc)


def install(saas: SaaS) -> Lab:
    lab = Lab(saas)
    saas.modules["lab"] = lab
    return lab


ROUTERS.append(mount)

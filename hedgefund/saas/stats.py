"""Stats module: journal KPIs, equity curve, behaviour flags and per-setup statistics, as a
member route and as tools for the agents (``perf.kpis``, ``perf.behavior_flags``,
``perf.setup_stats``)."""

from __future__ import annotations

from typing import Any

from fastapi import Depends
from pydantic import BaseModel, Field
from sqlalchemy import desc

from hedgefund.saas.api import ROUTERS, ApiContext, guard
from hedgefund.saas.db import account_snapshots, broker_accounts, economic_events, now_ms
from hedgefund.saas.engines import perf
from hedgefund.saas.service import Access, SaaS
from hedgefund.saas.tools import Tool, ToolContext


class Stats:
    def __init__(self, saas: SaaS):
        self.saas = saas
        self.cfg = saas.config.get("journal", {})

    def balance(self, s: Any, user_id: int, account_id: str | None = None) -> float | None:
        accts = [a for a in s.select(broker_accounts, {"user_id": user_id, "archived": False}) if not account_id or a["id"] == account_id]
        total = 0.0
        found = False
        for a in accts:
            snap = s.select(account_snapshots, {"account_id": a["id"]}, order_by=desc(account_snapshots.c.time_utc), limit=1)
            if snap:
                total += float(snap[0]["balance"])
                found = True
            elif a.get("starting_balance"):
                total += float(a["starting_balance"])
                found = True
        return total if found else None

    def events(self, since: int, until: int) -> list[dict[str, Any]]:
        from sqlalchemy import and_, select

        with self.saas.db.system() as conn:
            rows = conn.execute(select(economic_events).where(and_(economic_events.c.time_utc >= since, economic_events.c.time_utc <= until)))
            return [dict(r._mapping) for r in rows]

    def compute(self, tenant_id: str, user_id: int, days: int = 90, account_id: str | None = None) -> dict[str, Any]:
        journal = self.saas.modules["journal"]
        since = now_ms() - days * 86_400_000
        with self.saas.db.tenant(tenant_id) as s:
            rows = journal.list_trades(s, user_id, since=since, account_id=account_id, limit=20_000)
            plan = journal.plan(s, user_id)
            bal = self.balance(s, user_id, account_id)
        k = perf.kpis(rows, int(self.cfg.get("min_trades_for_stats", 20)), int(self.cfg.get("sample_warning_below", 30)), int(self.cfg.get("bootstrap_samples", 2000)))
        flags = perf.behavior_flags(rows, plan, bal, self.events(since, now_ms()))
        return {"period": [since, now_ms()], "days": days, "balance": bal, "kpis": k, "flags": flags, "equity": perf.equity_curve(rows), "plan": plan}


# ---------------------------------------------------------------- tools
class PeriodIn(BaseModel):
    days: int = Field(default=30, ge=1, le=366)


class SetupStatsIn(BaseModel):
    model: str = Field(min_length=2, max_length=30)
    days: int = Field(default=365, ge=7, le=3660)


def _kpis(ctx: ToolContext, p: PeriodIn) -> dict[str, Any]:
    out = ctx.services.modules["stats"].compute(ctx.tenant_id, ctx.user_id, p.days)
    k = dict(out["kpis"])
    for key in ("by_weekday", "by_symbol", "by_session", "by_direction"):
        k.pop(key, None)  # the agent gets the essentials; the member sees the full tables
    return {"days": p.days, "kpis": k}


def _flags(ctx: ToolContext, p: PeriodIn) -> dict[str, Any]:
    out = ctx.services.modules["stats"].compute(ctx.tenant_id, ctx.user_id, p.days)
    return {"days": p.days, "flags": out["flags"]}


def _setup_stats(ctx: ToolContext, p: SetupStatsIn) -> dict[str, Any]:
    journal = ctx.services.modules["journal"]
    with ctx.db.tenant(ctx.tenant_id) as s:
        rows = journal.list_trades(s, ctx.user_id, since=now_ms() - p.days * 86_400_000, closed_only=True, limit=20_000)
    return perf.setup_stats(rows, p.model)


def mount(ctx: ApiContext) -> None:
    app, saas = ctx.app, ctx.saas
    st: Stats = saas.modules["stats"]
    acc_dep = ctx.acc()

    @app.get("/api/app/stats")
    def stats(days: int = 90, account: str = "", acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: st.compute(acc.tenant_id, acc.member_id, max(1, min(days, 3660)), account[:40] or None))


def install(saas: SaaS) -> Stats:
    st = Stats(saas)
    saas.modules["stats"] = st
    saas.tools.register(Tool("perf.kpis", "KPIs du journal sur N jours : nombre de trades, taux de réussite et intervalle de Wilson, espérance en R et intervalle bootstrap, drawdown, découpage par killzone et setup.", PeriodIn, _kpis))
    saas.tools.register(Tool("perf.behavior_flags", "Comportements mesurés sur N jours (overtrading, revenge, lot augmenté après perte, hors plan, hors killzone, risque au-delà du plan, sorties précoces), avec les trades concernés.", PeriodIn, _flags))
    saas.tools.register(Tool("perf.setup_stats", "Statistiques d'un modèle de setup (SilverBullet, MacroBreaker…) sur l'historique du membre.", SetupStatsIn, _setup_stats))
    return st


ROUTERS.append(mount)

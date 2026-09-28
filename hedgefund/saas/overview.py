"""Dashboard in one call: plan and usage, 30-day statistics, behaviours, last review, active
lessons, prop-firm guard, latest briefing and analyses, unread notifications. Each block is
optional: a missing feature or an empty journal never breaks the page."""

from __future__ import annotations

from typing import Any

from fastapi import Depends

from hedgefund.saas.api import ROUTERS, ApiContext
from hedgefund.saas.service import Access, SaaS, month_key


def overview(saas: SaaS, acc: Access) -> dict[str, Any]:
    out: dict[str, Any] = {"plan": acc.plan, "limits": saas.limits(acc.plan), "usage": saas.usage_of(acc), "month": month_key(), "features": {f: acc.can(f) for f in saas.features},
                           "ai": saas.llm.available, "market": {"source": saas.market.source if saas.market else None, "synthetic": saas.market.synthetic if saas.market else None}}
    m = saas.modules

    def safe(key: str, fn: Any) -> None:
        try:
            out[key] = fn()
        except Exception:  # noqa: BLE001 - one block failing must not hide the others
            out[key] = None

    def stats() -> dict[str, Any]:
        st = m["stats"].compute(acc.tenant_id, acc.member_id, 30)
        k = st["kpis"]
        return {"kpis": {x: k.get(x) for x in ("n", "wins", "losses", "win_rate", "win_rate_ci95", "expectancy_r", "profit_factor", "net_total", "max_drawdown_r", "insufficient", "sample_warning", "open_positions")},
                "flags": st["flags"][:5], "equity": st["equity"][-200:], "by_killzone": k["by_killzone"][:5]}

    safe("stats", stats)
    safe("accounts", lambda: m["journal"].accounts(acc))
    safe("last_review", lambda: next(iter(m["coach"].reviews(acc, limit=1)), None))
    safe("lessons", lambda: [x for x in m["coach"].list_lessons(acc) if x["status"] in ("accepted", "edited", "proposed")][:7])
    safe("analyses", lambda: m["analyste"].list(acc, limit=3) if acc.can("analysis") else [])
    safe("briefing", lambda: (m["research"].latest(1) or [None])[0]["body"] if acc.can("briefing") and m["research"].latest(1) else None)
    safe("guard", lambda: m["risk"].status(acc, None) if out.get("accounts") else None)
    safe("notifications", lambda: sum(1 for n in m["notify"].list(acc) if not n["read_at"]))
    return out


def mount(ctx: ApiContext) -> None:
    app, saas = ctx.app, ctx.saas
    acc_dep = ctx.acc()

    @app.get("/api/app/overview")
    def get_overview(acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return overview(saas, acc)


def install(saas: SaaS) -> dict[str, Any]:
    return {}


ROUTERS.append(mount)

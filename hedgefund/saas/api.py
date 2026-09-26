"""HTTP routes of the SaaS, mounted into the platform app.

  /api/app/*          member routes (member session cookie, CSRF + Origin on writes)
  /api/admin/saas/*   operator routes (console session)
  /api/ingest/*, /api/hooks/*, /api/jobs/*   machine routes (tokens / shared secret)

Feature modules add their own routers through ``ROUTERS``; this module holds the shared
plumbing (access, errors, run status and the live step stream).
"""

from __future__ import annotations

import json
import time
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse
from sqlalchemy import func, select

from hedgefund.saas.db import TenantError, agent_runs, spans, usage
from hedgefund.saas.harness import HarnessError
from hedgefund.saas.service import Access, AccessDenied, QuotaExceeded, SaaS, month_key

ROUTERS: list[Callable[["ApiContext"], None]] = []  # feature modules append their mount functions


@dataclass
class ApiContext:
    app: FastAPI
    saas: SaaS
    member: Callable[..., Any]  # dependency -> (Session, member dict)
    operator: Callable[..., Any]  # dependency -> console Session
    profile: Callable[[dict[str, Any]], dict[str, Any]]  # member dict -> public profile (offer, entitlements)
    client_ip: Callable[[Request], str]
    member_by_id: Callable[[int], dict[str, Any] | None] = lambda _id: None

    def plan_of(self, member_id: int) -> str:
        """Main offer of a member, for machine routes that act on the member's behalf."""
        m = self.member_by_id(member_id)
        if not m or m.get("status") != "active":
            return "gratuit"
        return self.profile(m).get("offer", "gratuit")

    def access(self, sm: Any) -> Access:
        _s, m = sm
        p = self.profile(m)
        return self.saas.access(m, p.get("offer", "gratuit"), set(p.get("entitlements", [])))

    def acc(self) -> Callable[..., Access]:
        def dep(sm=Depends(self.member)) -> Access:  # noqa: B008
            return self.access(sm)

        return dep


def http_error(e: Exception) -> HTTPException:
    if isinstance(e, AccessDenied):
        return HTTPException(403, str(e))
    if isinstance(e, QuotaExceeded):
        return HTTPException(429, str(e))
    if isinstance(e, (TenantError,)):
        return HTTPException(403, "accès refusé")
    if isinstance(e, (ValueError, HarnessError)):
        return HTTPException(400, str(e))
    if isinstance(e, LookupError):
        return HTTPException(404, str(e) or "introuvable")
    return HTTPException(500, "erreur interne")


def guard(fn: Callable[[], Any]) -> Any:
    try:
        return fn()
    except HTTPException:
        raise
    except Exception as e:  # noqa: BLE001
        raise http_error(e) from e


def run_view(saas: SaaS, tenant_id: str, trace_id: str, since: int = 0) -> dict[str, Any]:
    with saas.db.tenant(tenant_id) as s:
        run = s.one(agent_runs, {"id": trace_id})
        if run is None:
            raise LookupError("exécution introuvable")
        rows = s.select(spans, {"trace_id": trace_id}, spans.c.started_ms >= since, order_by=[spans.c.started_ms, spans.c.id])
    steps = [{"id": r["id"], "name": r["name"], "kind": r["kind"], "status": r["status"], "t": r["started_ms"], "ms": (r["ended_ms"] - r["started_ms"]) if r["ended_ms"] else None} for r in rows if r["kind"] in ("node", "step", "tool", "llm", "guardrail")]
    return {
        "id": run["id"], "graph": run["graph"], "status": run["status"], "output": run["output"], "error": run["error"],
        "cost_usd": run["cost_usd"], "llm_calls": run["llm_calls"], "manifest": run["manifest"], "created_at": run["created_at"], "steps": steps,
    }


def mount_saas(ctx: ApiContext) -> None:
    app, saas = ctx.app, ctx.saas
    acc_dep = ctx.acc()

    @app.get("/api/app/me")
    def me(acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        limits = saas.limits(acc.plan)
        return {
            "tenant": acc.tenant_id, "plan": acc.plan, "limits": limits, "usage": saas.usage_of(acc), "month": month_key(),
            "features": {f: acc.can(f) for f in saas.features}, "ai": saas.llm.available,
            "market": {"source": saas.market.source if saas.market else None, "synthetic": saas.market.synthetic if saas.market else None},
            "manifest": saas.manifest.fingerprint,
        }

    @app.get("/api/app/runs/{trace_id}")
    def run(trace_id: str, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: run_view(saas, acc.tenant_id, trace_id[:40]))

    @app.get("/api/app/runs/{trace_id}/stream")
    def stream(trace_id: str, acc: Access = Depends(acc_dep)) -> StreamingResponse:  # noqa: B008
        guard(lambda: run_view(saas, acc.tenant_id, trace_id[:40]))

        def events() -> Iterator[str]:
            seen: set[str] = set()
            deadline = time.monotonic() + 180
            while time.monotonic() < deadline:
                v = run_view(saas, acc.tenant_id, trace_id[:40])
                for st in v["steps"]:
                    key = f"{st['id']}:{st['status']}:{st['ms']}"
                    if key not in seen:
                        seen.add(key)
                        yield f"event: step\ndata: {json.dumps(st, ensure_ascii=False)}\n\n"
                if v["status"] in ("done", "failed", "waiting"):
                    yield f"event: end\ndata: {json.dumps({'status': v['status']})}\n\n"
                    return
                yield ": ping\n\n"
                time.sleep(0.5)
            yield "event: end\ndata: {\"status\": \"timeout\"}\n\n"

        return StreamingResponse(events(), media_type="text/event-stream", headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"})

    # ---- operator ----
    @app.get("/api/admin/saas/overview")
    def overview(s=Depends(ctx.operator)) -> dict:  # noqa: B008
        since = int(time.time() * 1000) - 86_400_000
        with saas.db.system() as conn:
            runs = {r.status: r.n for r in conn.execute(select(agent_runs.c.status, func.count().label("n")).where(agent_runs.c.created_at >= since).group_by(agent_runs.c.status))}
            by_graph = [dict(r._mapping) for r in conn.execute(select(agent_runs.c.graph, func.count().label("runs"), func.sum(agent_runs.c.cost_usd).label("cost_usd"), func.sum(agent_runs.c.llm_calls).label("llm_calls")).where(agent_runs.c.created_at >= since).group_by(agent_runs.c.graph))]
            month = [dict(r._mapping) for r in conn.execute(select(usage.c.key, func.sum(usage.c.count).label("count"), func.sum(usage.c.cost_usd).label("cost_usd")).where(usage.c.month == month_key()).group_by(usage.c.key))]
        return {"jobs": saas.queue.counts(), "runs_24h": runs, "by_graph_24h": by_graph, "usage_month": month, "manifest": saas.manifest.model_dump(), "ai": saas.llm.available,
                "database": "postgresql" if saas.db.is_postgres else "sqlite"}

    for mount in ROUTERS:
        mount(ctx)

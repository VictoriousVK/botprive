"""Machine routes for the event loop (n8n, cron): each call carries the shared secret
(X-Jobs-Secret) and, optionally, an Idempotency-Key. n8n only triggers; the backend decides
(ADR-008): every rule lives here, tested, not in the workflows."""

from __future__ import annotations

import hmac
import time
from datetime import datetime, timezone
from typing import Any

from fastapi import HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy import and_, select

from hedgefund.saas.api import ROUTERS, ApiContext
from hedgefund.saas.coach import iso_week
from hedgefund.saas.db import broker_accounts, notifications, now_ms, tenant_members, trades
from hedgefund.saas.service import SaaS


class BriefingIn(BaseModel):
    session: str = Field(default="new_york", pattern=r"^(london|new_york)$")


def _check(saas: SaaS, request: Request) -> None:
    secret = saas.settings.jobs_secret
    got = request.headers.get("x-jobs-secret", "")
    if not secret or not hmac.compare_digest(got, secret):
        raise HTTPException(401, "secret des tâches invalide")


def weekly_reviews(saas: SaaS, access_for: Any) -> dict[str, int]:
    """One review per member with trades in the last seven days, at batch priority."""
    since = now_ms() - 7 * 86_400_000
    week = iso_week(now_ms())
    with saas.db.system() as conn:
        pairs = {(r.tenant_id, r.user_id) for r in conn.execute(select(trades.c.tenant_id, trades.c.user_id).where(trades.c.open_utc >= since))}
    queued = skipped = 0
    for tenant, user in sorted(pairs):
        acc = access_for(user)
        if acc is None or acc.tenant_id != tenant or not acc.can("coach"):
            skipped += 1
            continue
        payload = {"tenant_id": tenant, "user_id": user, "days": 7, "question": None, "trace_id": f"tr_w{week.replace('-', '')}_{user}", "plan": acc.plan, "entitlements": sorted(acc.entitlements)}
        saas.queue.enqueue("g3_review", payload, tenant_id=tenant, priority=2, idem_key=f"g3w:{tenant}:{week}")
        queued += 1
    return {"queued": queued, "skipped": skipped}


def guard_check(saas: SaaS, access_for: Any) -> dict[str, int]:
    """Risk status of every account with a starting balance; one notification per level and day."""
    with saas.db.system() as conn:
        accts = [dict(r._mapping) for r in conn.execute(select(broker_accounts).where(and_(broker_accounts.c.archived.is_(False), broker_accounts.c.starting_balance.is_not(None))))]
    risk, notify = saas.modules["risk"], saas.modules["notify"]
    sent = checked = 0
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    for a in accts:
        acc = access_for(a["user_id"])
        if acc is None or acc.tenant_id != a["tenant_id"]:
            continue
        try:
            st = risk.status(acc, a["id"])
        except Exception:  # noqa: BLE001 - an account without data is skipped
            continue
        checked += 1
        if not st["alerts"]:
            continue
        top = max(st["alerts"], key=lambda x: x["level"])
        title = f"Garde-fou : {top['level']} % de la limite de perte {'journalière' if top['kind'] == 'daily_loss' else 'maximale'} ({a['label']})"
        with saas.db.tenant(a["tenant_id"]) as s:
            already = any(n["title"] == title and datetime.fromtimestamp(n["created_at"] / 1000, tz=timezone.utc).strftime("%Y-%m-%d") == day
                          for n in s.select(notifications, {"user_id": a["user_id"], "kind": "risk_alert"}))
        if not already:
            notify.notify(a["tenant_id"], a["user_id"], "risk_alert", title, "Vérifiez vos positions ouvertes et votre plan avant tout nouveau trade.", "/app/risque/")
            sent += 1
    return {"checked": checked, "alerts_sent": sent}


def renewals(saas: SaaS) -> dict[str, int]:
    """In-app reminder three days before a subscription ends (payments stay manual with Wave)."""
    store = getattr(saas.platform, "store", None)
    if store is None:
        return {"reminded": 0}
    now = int(time.time())
    rows = store.execute("SELECT member_id, product, expires_at FROM member_access WHERE expires_at IS NOT NULL AND expires_at BETWEEN ? AND ?", (now, now + 3 * 86_400))
    n = 0
    for r in rows:
        with saas.db.system() as conn:
            t = conn.execute(select(tenant_members.c.tenant_id).where(tenant_members.c.member_id == r["member_id"])).first()
        if t is None:
            continue
        title = f"Votre accès « {r['product']} » se termine bientôt"
        with saas.db.tenant(t.tenant_id) as s:
            if any(x["title"] == title for x in s.select(notifications, {"user_id": r["member_id"], "kind": "billing"})):
                continue
        saas.modules["notify"].notify(t.tenant_id, r["member_id"], "billing", title, "Renouvelez depuis votre espace membre (paiement Wave).", "/compte/")
        n += 1
    return {"reminded": n}


def mount(ctx: ApiContext) -> None:
    app, saas = ctx.app, ctx.saas

    def key(request: Request, default: str) -> str:
        return (request.headers.get("idempotency-key") or default)[:120]

    @app.post("/api/jobs/briefing")
    def briefing(body: BriefingIn, request: Request) -> dict:
        _check(saas, request)
        day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        jid = saas.queue.enqueue("g4_briefing", {"session": body.session}, priority=1, idem_key=key(request, f"g4:{body.session}:{day}"))
        return {"job": jid}

    @app.post("/api/jobs/weekly-reviews")
    def weekly(request: Request) -> dict:
        _check(saas, request)
        return weekly_reviews(saas, ctx.access_for_member)

    @app.post("/api/jobs/guard-check")
    def guard_(request: Request) -> dict:
        _check(saas, request)
        return guard_check(saas, ctx.access_for_member)

    @app.post("/api/jobs/sources-refresh")
    def sources(request: Request) -> dict:
        _check(saas, request)
        return {"job": saas.queue.enqueue("sources_refresh", {}, priority=2, idem_key=key(request, f"src:{int(time.time() // 900)}"))}

    @app.post("/api/jobs/renewals")
    def renew(request: Request) -> dict:
        _check(saas, request)
        return renewals(saas)

    @app.get("/api/jobs/status")
    def status(request: Request) -> dict:
        _check(saas, request)
        return {"jobs": saas.queue.counts(), "manifest": saas.manifest.fingerprint}


def install(saas: SaaS) -> dict[str, Any]:
    return {}


ROUTERS.append(mount)

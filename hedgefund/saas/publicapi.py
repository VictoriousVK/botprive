"""Public API, read only (P2): the member's own trades, statistics and lessons, with a personal
token (scopes, revocable, rate-limited). Nothing can be written or traded through it."""

from __future__ import annotations

import secrets
from typing import Any

from fastapi import Depends, HTTPException, Request
from pydantic import BaseModel, Field

from hedgefund.saas.api import ROUTERS, ApiContext, guard
from hedgefund.saas.db import api_tokens, new_id, now_ms
from hedgefund.saas.journal import token_hash
from hedgefund.saas.service import Access, SaaS

SCOPES = ("read:trades", "read:stats", "read:lessons")


class TokenIn(BaseModel):
    label: str = Field(min_length=2, max_length=80)
    scopes: list[str] = Field(default_factory=lambda: list(SCOPES), min_length=1, max_length=3)


class PublicApi:
    def __init__(self, saas: SaaS):
        self.saas = saas

    def create(self, acc: Access, body: TokenIn) -> dict[str, Any]:
        acc.require("public_api", "API")
        bad = [x for x in body.scopes if x not in SCOPES]
        if bad:
            raise ValueError("portée inconnue : " + ", ".join(bad))
        token = "aeapi_" + secrets.token_urlsafe(28)
        with self.saas.db.tenant(acc.tenant_id) as s:
            if s.count(api_tokens, {"user_id": acc.member_id, "kind": "public_api", "revoked_at": None}) >= 5:
                raise ValueError("5 jetons d'API au plus")
            s.insert(api_tokens, {"id": new_id("tok"), "user_id": acc.member_id, "kind": "public_api", "label": body.label, "token_hash": token_hash(token),
                                  "account_id": None, "scopes": body.scopes, "created_at": now_ms()})
        return {"token": token, "scopes": body.scopes, "shown_once": True}

    def resolve(self, request: Request, scope: str, access_for: Any) -> Access:
        auth = request.headers.get("authorization", "")
        token = auth[7:].strip() if auth.lower().startswith("bearer ") else ""
        j = self.saas.modules["journal"]
        try:
            tok = j.resolve_token(token, scope)
        except PermissionError as e:
            raise HTTPException(401, str(e)) from e
        if tok["kind"] != "public_api":
            raise HTTPException(401, "jeton non valable pour l'API")
        if not j.rate_ok("api:" + tok["id"], per_minute=60):
            raise HTTPException(429, "60 requêtes par minute au plus")
        acc = access_for(tok["user_id"])
        if acc is None or acc.tenant_id != tok["tenant_id"] or not acc.can("public_api"):
            raise HTTPException(403, "API non incluse dans l'offre actuelle")
        with self.saas.db.tenant(tok["tenant_id"]) as s:
            s.update(api_tokens, {"id": tok["id"]}, {"last_used_at": now_ms()})
        return acc


def mount(ctx: ApiContext) -> None:
    app, saas = ctx.app, ctx.saas
    api: PublicApi = saas.modules["publicapi"]
    acc_dep = ctx.acc()

    @app.post("/api/app/tokens/api")
    def create(body: TokenIn, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: api.create(acc, body))

    @app.get("/api/v1/trades")
    def trades(request: Request, days: int = 30, limit: int = 500) -> dict:
        acc = api.resolve(request, "read:trades", ctx.access_for_member)
        rows = saas.modules["journal"].trades_with_entries(acc, since=now_ms() - max(1, min(days, 3660)) * 86_400_000, limit=max(1, min(limit, 2000)))
        keep = ("id", "account_id", "symbol", "side", "volume", "open_utc", "close_utc", "open_price", "close_price", "sl", "tp", "net", "r_multiple", "killzone", "session", "setup_model", "plan_respected", "journal")
        return {"trades": [{k: r.get(k) for k in keep} for r in rows]}

    @app.get("/api/v1/stats")
    def stats(request: Request, days: int = 90) -> dict:
        acc = api.resolve(request, "read:stats", ctx.access_for_member)
        out = saas.modules["stats"].compute(acc.tenant_id, acc.member_id, max(1, min(days, 3660)))
        return {k: out[k] for k in ("period", "kpis", "flags")}

    @app.get("/api/v1/lessons")
    def lessons(request: Request) -> dict:
        acc = api.resolve(request, "read:lessons", ctx.access_for_member)
        return {"lessons": [{k: x[k] for k in ("id", "text", "behavior", "status", "created_at")} for x in saas.modules["coach"].list_lessons(acc)]}


def install(saas: SaaS) -> PublicApi:
    api = PublicApi(saas)
    saas.modules["publicapi"] = api
    return api


ROUTERS.append(mount)

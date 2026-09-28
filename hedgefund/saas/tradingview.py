"""TradingView alerts → graph G1. TradingView cannot sign a webhook nor send a custom header,
so each hook has an unguessable id in the URL AND a secret token in the message; the server
also rejects stale alerts (time placeholder older than two minutes), replays (same alert key)
and bursts. The analysis runs as the member, within their plan and quota."""

from __future__ import annotations

import hashlib
import hmac
import json
import secrets
import threading
import time
from collections import deque
from datetime import datetime
from typing import Any

from fastapi import Depends, HTTPException, Request
from sqlalchemy import select

from hedgefund.saas.api import ROUTERS, ApiContext, guard
from hedgefund.saas.db import new_id, now_ms, tv_alerts_seen, tv_hooks
from hedgefund.saas.schemas import SetupRequest
from hedgefund.saas.service import Access, SaaS

MAX_AGE_MS = 120_000
MESSAGE_TEMPLATE = '{"token": "%s", "symbol": "{{ticker}}", "time": "{{timenow}}", "alert_id": "{{ticker}}-{{interval}}-{{time}}", "tf": "{{interval}}", "note": "{{strategy.order.comment}}"}'


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def parse_tv_time(text: str) -> int | None:
    try:
        return int(datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp() * 1000)
    except (ValueError, AttributeError):
        return None


class TradingView:
    def __init__(self, saas: SaaS):
        self.saas = saas
        self._rate: dict[str, deque] = {}
        self._lock = threading.Lock()

    def create(self, acc: Access) -> dict[str, Any]:
        acc.require("tradingview", "Alertes TradingView")
        with self.saas.db.tenant(acc.tenant_id) as s:
            if s.count(tv_hooks, {"user_id": acc.member_id, "enabled": True}) >= 3:
                raise ValueError("3 webhooks TradingView au plus")
            hid = new_id("tvh") + secrets.token_hex(6)
            token = secrets.token_urlsafe(24)
            s.insert(tv_hooks, {"id": hid, "user_id": acc.member_id, "token_hash": _hash(token), "enabled": True, "created_at": now_ms()})
        base = self.saas.settings.public_url
        return {"hook_id": hid, "url": f"{base}/api/hooks/tv/{hid}" if base else f"/api/hooks/tv/{hid}", "message": MESSAGE_TEMPLATE % token, "shown_once": True}

    def list(self, acc: Access) -> list[dict[str, Any]]:
        with self.saas.db.tenant(acc.tenant_id) as s:
            return [{"id": r["id"], "enabled": r["enabled"], "created_at": r["created_at"]} for r in s.select(tv_hooks, {"user_id": acc.member_id})]

    def delete(self, acc: Access, hook_id: str) -> None:
        with self.saas.db.tenant(acc.tenant_id) as s:
            if s.update(tv_hooks, {"id": hook_id, "user_id": acc.member_id}, {"enabled": False}) == 0:
                raise LookupError("webhook introuvable")

    def receive(self, hook_id: str, body: dict[str, Any], access_for: Any) -> dict[str, Any]:
        with self.saas.db.system() as conn:
            row = conn.execute(select(tv_hooks).where(tv_hooks.c.id == hook_id)).first()
        if row is None or not row.enabled or not hmac.compare_digest(_hash(str(body.get("token", ""))), row.token_hash):
            raise PermissionError("webhook inconnu ou jeton invalide")
        now = now_ms()
        t = parse_tv_time(str(body.get("time", ""))) if body.get("time") else None
        if t is not None and abs(now - t) > MAX_AGE_MS:
            raise ValueError("alerte trop ancienne (plus de 2 minutes)")
        with self._lock:
            q = self._rate.setdefault(hook_id, deque())
            mono = time.monotonic()
            while q and mono - q[0] > 60:
                q.popleft()
            if len(q) >= 10:
                raise OverflowError("trop d'alertes : 10 par minute au plus")
            q.append(mono)
        key = str(body.get("alert_id") or hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest())[:80]
        with self.saas.db.tenant(row.tenant_id) as s:
            if s.one(tv_alerts_seen, {"hook_id": hook_id, "alert_key": key}) is not None:
                return {"ok": True, "duplicate": True}
            s.insert(tv_alerts_seen, {"hook_id": hook_id, "alert_key": key, "received_at": now})
        acc = access_for(row.user_id)
        if acc is None:
            raise PermissionError("membre inactif")
        symbol = str(body.get("symbol", "")).split(":")[-1][:20]
        tf = {"1": "M1", "5": "M5", "15": "M15"}.get(str(body.get("tf", "5")), "M5")
        req = SetupRequest(symbol=symbol or "?", tf_entry=tf, source="tradingview", alert_id=key, note=str(body.get("note", ""))[:500])
        out = self.saas.modules["analyste"].start(acc, req, idem_key=f"tv:{hook_id}:{key}")
        self.saas.modules["notify"].notify(acc.tenant_id, acc.member_id, "tradingview", f"Alerte TradingView : {req.symbol}", "Analyse de setup lancée depuis votre alerte.", f"/app/analyse/?id={out['trace_id']}")
        return {"ok": True, "trace_id": out["trace_id"]}


def mount(ctx: ApiContext) -> None:
    app, saas = ctx.app, ctx.saas
    tv: TradingView = saas.modules["tradingview"]
    acc_dep = ctx.acc()

    @app.post("/api/app/tradingview/hooks")
    def create(acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: tv.create(acc))

    @app.get("/api/app/tradingview/hooks")
    def list_(acc: Access = Depends(acc_dep)) -> list[dict]:  # noqa: B008
        return tv.list(acc)

    @app.delete("/api/app/tradingview/hooks/{hook_id}")
    def delete(hook_id: str, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        guard(lambda: tv.delete(acc, hook_id[:60]))
        return {"ok": True}

    @app.post("/api/hooks/tv/{hook_id}")
    async def receive(hook_id: str, request: Request) -> dict:
        raw = (await request.body())[:8192]
        try:
            body = json.loads(raw.decode("utf-8", errors="replace"))
            if not isinstance(body, dict):
                raise ValueError
        except ValueError:
            raise HTTPException(400, "le message de l'alerte doit être le JSON fourni dans l'espace membre") from None
        try:
            return tv.receive(hook_id[:60], body, ctx.access_for_member)
        except PermissionError as e:
            raise HTTPException(401, str(e)) from e
        except OverflowError as e:
            raise HTTPException(429, str(e)) from e
        except Exception as e:  # noqa: BLE001
            from hedgefund.saas.api import http_error

            raise http_error(e) from e


def install(saas: SaaS) -> TradingView:
    tv = TradingView(saas)
    saas.modules["tradingview"] = tv
    return tv


ROUTERS.append(mount)

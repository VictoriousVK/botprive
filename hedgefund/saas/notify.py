"""Notifications: in-app list, and Telegram when the member has linked their chat with the
platform's bot (``/start CODE``). Telegram delivery is best effort and never blocks the
action that triggered it. The bot token comes from HF_TELEGRAM_BOT_TOKEN."""

from __future__ import annotations

import hmac
import logging
import secrets
from collections.abc import Callable
from typing import Any

import requests
from fastapi import Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy import and_, desc, select, update

from hedgefund.saas.api import ROUTERS, ApiContext, guard
from hedgefund.saas.db import new_id, notifications, notify_channels, now_ms
from hedgefund.saas.service import Access, SaaS

log = logging.getLogger("hedgefund.saas.notify")
KINDS = ("review", "analysis", "tradingview", "risk_alert", "briefing", "lab", "ea_factory", "billing")


def telegram_sender(token: str) -> Callable[[str, str], bool]:
    def send(chat_id: str, text: str) -> bool:
        try:
            r = requests.post(f"https://api.telegram.org/bot{token}/sendMessage", json={"chat_id": chat_id, "text": text[:4000], "disable_web_page_preview": True}, timeout=8)
            return r.status_code == 200
        except requests.RequestException as e:
            log.warning("telegram: %s", e)
            return False

    return send


class Notifier:
    def __init__(self, saas: SaaS, sender: Callable[[str, str], bool] | None = None):
        self.saas = saas
        tok = saas.settings.telegram_bot_token
        self.sender = sender or (telegram_sender(tok) if tok else None)

    def notify(self, tenant_id: str, user_id: int, kind: str, title: str, body: str, link: str | None = None) -> str:
        nid = new_id("ntf")
        with self.saas.db.tenant(tenant_id) as s:
            s.insert(notifications, {"id": nid, "user_id": user_id, "kind": kind, "title": title[:160], "body": body[:2000], "link": link, "created_at": now_ms()})
            ch = s.one(notify_channels, {"user_id": user_id, "kind": "telegram"})
        if ch and ch.get("address") and ch.get("verified_at") and self.sender and (ch.get("prefs") or {}).get(kind, True):
            url = f"{self.saas.settings.public_url}{link}" if link and self.saas.settings.public_url else ""
            self.sender(ch["address"], f"{title}\n\n{body}" + (f"\n\n{url}" if url else ""))
        return nid

    def list(self, acc: Access, limit: int = 50) -> list[dict[str, Any]]:
        with self.saas.db.tenant(acc.tenant_id) as s:
            return s.select(notifications, {"user_id": acc.member_id}, order_by=desc(notifications.c.created_at), limit=limit)

    def mark_read(self, acc: Access) -> int:
        with self.saas.db.tenant(acc.tenant_id) as s:
            return s.update(notifications, {"user_id": acc.member_id, "read_at": None}, {"read_at": now_ms()})

    def link_telegram(self, acc: Access) -> dict[str, Any]:
        if not self.saas.settings.telegram_bot_token:
            raise ValueError("les notifications Telegram ne sont pas encore configurées sur la plateforme")
        code = secrets.token_hex(4).upper()
        with self.saas.db.tenant(acc.tenant_id) as s:
            s.upsert(notify_channels, {"user_id": acc.member_id, "kind": "telegram"}, {"link_code": code, "address": None, "verified_at": None, "prefs": {k: True for k in KINDS}})
        bot = self.saas.settings.telegram_bot_name
        return {"code": code, "link": f"https://t.me/{bot}?start={code}" if bot else None, "instructions": f"Envoyez /start {code} au bot de la plateforme."}

    def channel(self, acc: Access) -> dict[str, Any] | None:
        with self.saas.db.tenant(acc.tenant_id) as s:
            ch = s.one(notify_channels, {"user_id": acc.member_id, "kind": "telegram"})
        return {"linked": bool(ch and ch["verified_at"]), "prefs": ch["prefs"] if ch else {k: True for k in KINDS}} if ch else None

    def set_prefs(self, acc: Access, prefs: dict[str, bool]) -> None:
        with self.saas.db.tenant(acc.tenant_id) as s:
            if s.update(notify_channels, {"user_id": acc.member_id, "kind": "telegram"}, {"prefs": {k: bool(prefs.get(k, True)) for k in KINDS}}) == 0:
                raise LookupError("aucun canal Telegram")

    def unlink(self, acc: Access) -> None:
        with self.saas.db.tenant(acc.tenant_id) as s:
            s.delete(notify_channels, {"user_id": acc.member_id, "kind": "telegram"})

    def on_telegram_update(self, update_: dict[str, Any]) -> bool:
        msg = update_.get("message") or {}
        text = str(msg.get("text") or "").strip()
        chat = (msg.get("chat") or {}).get("id")
        if not text.startswith("/start") or chat is None:
            return False
        code = text.split(maxsplit=1)[1].strip().upper() if len(text.split()) > 1 else ""
        if not code:
            return False
        with self.saas.db.system() as conn:
            row = conn.execute(select(notify_channels).where(and_(notify_channels.c.kind == "telegram", notify_channels.c.link_code == code))).first()
            if row is None:
                return False
            conn.execute(update(notify_channels).where(and_(notify_channels.c.tenant_id == row.tenant_id, notify_channels.c.user_id == row.user_id, notify_channels.c.kind == "telegram"))
                         .values(address=str(chat), verified_at=now_ms(), link_code=None))
        if self.sender:
            self.sender(str(chat), "Notifications Alpha Edge activées. Vous pouvez les régler dans votre espace membre.")
        return True


class PrefsIn(BaseModel):
    prefs: dict[str, bool] = Field(default_factory=dict)


def mount(ctx: ApiContext) -> None:
    app, saas = ctx.app, ctx.saas
    n: Notifier = saas.modules["notify"]
    acc_dep = ctx.acc()

    @app.get("/api/app/notifications")
    def list_(acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        items = n.list(acc)
        return {"items": items, "unread": sum(1 for x in items if not x["read_at"]), "telegram": n.channel(acc), "telegram_available": bool(saas.settings.telegram_bot_token)}

    @app.post("/api/app/notifications/read")
    def read(acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return {"updated": n.mark_read(acc)}

    @app.post("/api/app/notifications/telegram")
    def link(acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: n.link_telegram(acc))

    @app.put("/api/app/notifications/telegram")
    def prefs(body: PrefsIn, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        guard(lambda: n.set_prefs(acc, body.prefs))
        return {"ok": True}

    @app.delete("/api/app/notifications/telegram")
    def unlink(acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        n.unlink(acc)
        return {"ok": True}

    @app.post("/api/hooks/telegram/{secret}")
    async def telegram_hook(secret: str, request: Request) -> dict:
        expected = saas.settings.telegram_webhook_secret
        if not expected or not hmac.compare_digest(secret, expected):
            raise HTTPException(404, "route inconnue")
        try:
            body = await request.json()
        except ValueError:
            return {"ok": True}
        n.on_telegram_update(body if isinstance(body, dict) else {})
        return {"ok": True}


def install(saas: SaaS) -> Notifier:
    n = Notifier(saas)
    saas.modules["notify"] = n
    return n


ROUTERS.append(mount)

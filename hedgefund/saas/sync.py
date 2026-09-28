"""EA telemetry (status of the member's EAs, sent with the Journal Sync token) and the offline
sync API of the GMI Journal mobile app (per-field last-writer-wins merge of journal entries)."""

from __future__ import annotations

from typing import Any, Literal

from fastapi import Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy import desc

from hedgefund.saas.api import ROUTERS, ApiContext, guard, http_error
from hedgefund.saas.db import broker_accounts, ea_telemetry, journal_entries, new_id, notifications, now_ms, trades
from hedgefund.saas.journal import JournalEntryIn
from hedgefund.saas.service import Access, SaaS

ENTRY_FIELDS = ("setup_model", "emotion_before", "emotion_after", "followed_plan", "mistakes", "notes", "rating")


class TelemetryIn(BaseModel):
    ea: str = Field(min_length=1, max_length=60)
    magic: int | None = None
    status: Literal["running", "stopped", "error"]
    spread_points: float | None = None
    last_error: str = Field(default="", max_length=200)
    extra: dict[str, Any] = Field(default_factory=dict)


class SyncEntry(BaseModel):
    trade_id: str = Field(min_length=4, max_length=40)
    fields: dict[str, Any]
    times: dict[str, int]  # field -> client update time (UTC ms)


class SyncIn(BaseModel):
    entries: list[SyncEntry] = Field(max_length=500)


class Sync:
    def __init__(self, saas: SaaS):
        self.saas = saas

    def telemetry(self, token: str, body: TelemetryIn) -> dict[str, Any]:
        j = self.saas.modules["journal"]
        tok = j.resolve_token(token, "ingest:telemetry")
        if not j.rate_ok("tel:" + tok["id"], per_minute=12):
            raise OverflowError("trop d'envois de télémétrie")
        with self.saas.db.tenant(tok["tenant_id"]) as s:
            s.insert(ea_telemetry, {"id": new_id("tel"), "account_id": tok["account_id"], "ea": body.ea, "magic": body.magic, "time_utc": now_ms(), "status": body.status,
                                    "spread_points": body.spread_points, "last_error": body.last_error or None, "body": body.extra})
            acct = s.one(broker_accounts, {"id": tok["account_id"]})
            recent = [n for n in s.select(notifications, {"user_id": tok["user_id"], "kind": "ea_factory"}, order_by=desc(notifications.c.created_at), limit=5)]
        if body.status == "error" and not any(body.ea in n["title"] and n["created_at"] > now_ms() - 3_600_000 for n in recent):
            self.saas.modules["notify"].notify(tok["tenant_id"], tok["user_id"], "ea_factory", f"EA {body.ea} en erreur ({(acct or {}).get('label', '')})", body.last_error or "erreur signalée par l'EA", "/app/reglages/")
        return {"ok": True}

    def status(self, acc: Access) -> list[dict[str, Any]]:
        with self.saas.db.tenant(acc.tenant_id) as s:
            accts = {a["id"]: a["label"] for a in s.select(broker_accounts, {"user_id": acc.member_id})}
            rows = [r for r in s.select(ea_telemetry, order_by=desc(ea_telemetry.c.time_utc), limit=500) if r["account_id"] in accts]
        latest: dict[tuple[str, str], dict[str, Any]] = {}
        for r in rows:
            latest.setdefault((r["account_id"], r["ea"]), {**r, "account": accts[r["account_id"]], "stale": now_ms() - r["time_utc"] > 15 * 60_000})
        return list(latest.values())

    def pull(self, acc: Access, since: int) -> dict[str, Any]:
        with self.saas.db.tenant(acc.tenant_id) as s:
            ts = [t for t in s.select(trades, {"user_id": acc.member_id}, trades.c.imported_at >= since, limit=5000)]
            es = [e for e in s.select(journal_entries, {"user_id": acc.member_id}, journal_entries.c.updated_at >= since, limit=5000)]
        return {"server_time": now_ms(), "trades": ts, "entries": es}

    def push(self, acc: Access, body: SyncIn) -> dict[str, Any]:
        applied = kept = 0
        with self.saas.db.tenant(acc.tenant_id) as s:
            for e in body.entries:
                if s.one(trades, {"id": e.trade_id, "user_id": acc.member_id}) is None:
                    continue
                cur = s.one(journal_entries, {"trade_id": e.trade_id})
                times = dict((cur or {}).get("field_times") or {})
                merged = {k: (cur or {}).get(k) for k in ENTRY_FIELDS}
                for k, v in e.fields.items():
                    if k not in ENTRY_FIELDS:
                        continue
                    if e.times.get(k, 0) > times.get(k, 0):
                        merged[k] = v
                        times[k] = e.times[k]
                        applied += 1
                    else:
                        kept += 1
                valid = JournalEntryIn.model_validate({k: v for k, v in merged.items() if v is not None}).model_dump()
                s.upsert(journal_entries, {"trade_id": e.trade_id}, {**valid, "user_id": acc.member_id, "updated_at": now_ms(), "field_times": times})
        return {"applied": applied, "kept_server": kept, "server_time": now_ms()}


def mount(ctx: ApiContext) -> None:
    app, saas = ctx.app, ctx.saas
    sy: Sync = saas.modules["sync"]
    acc_dep = ctx.acc()

    @app.post("/api/ingest/telemetry")
    def telemetry(body: TelemetryIn, request: Request) -> dict:
        auth = request.headers.get("authorization", "")
        token = auth[7:].strip() if auth.lower().startswith("bearer ") else ""
        try:
            return sy.telemetry(token, body)
        except PermissionError as e:
            raise HTTPException(401, str(e)) from e
        except OverflowError as e:
            raise HTTPException(429, str(e)) from e
        except Exception as e:  # noqa: BLE001
            raise http_error(e) from e

    @app.get("/api/app/telemetry")
    def telemetry_status(acc: Access = Depends(acc_dep)) -> list[dict]:  # noqa: B008
        return sy.status(acc)

    @app.get("/api/app/sync")
    def pull(since: int = 0, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return sy.pull(acc, max(0, since))

    @app.put("/api/app/sync")
    def push(body: SyncIn, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: sy.push(acc, body))


def install(saas: SaaS) -> Sync:
    sy = Sync(saas)
    saas.modules["sync"] = sy
    return sy


ROUTERS.append(mount)

"""Journal module: broker accounts, trade import, trading plan, declared profile, journal
entries, EA Journal Sync ingestion, export and erasure. Read-only toward the broker: nothing
here can send an order."""

from __future__ import annotations

import base64
import hashlib
import secrets
import threading
import time
from collections import deque
from datetime import datetime, timezone
from typing import Any, Literal

from fastapi import Depends, HTTPException, Request
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import desc, select

from hedgefund.saas import ingest as I
from hedgefund.saas.api import ROUTERS, ApiContext, guard
from hedgefund.saas.db import (
    Scoped,
    account_snapshots,
    api_tokens,
    broker_accounts,
    executions,
    import_jobs,
    journal_entries,
    lessons,
    memories_episodic,
    new_id,
    now_ms,
    trades,
    trading_plans,
    user_profiles,
)
from hedgefund.saas.schemas import EmotionDeclared, MistakeKind
from hedgefund.saas.service import Access, SaaS, month_key
from hedgefund.saas.tools import Tool, ToolContext

MAX_FILE_BYTES = 5 * 1024 * 1024
KILLZONE_NAMES = ("Asia", "London", "NY_AM", "NY_Lunch", "NY_PM")
SETUP_NAMES = ("SilverBullet", "MacroBreaker", "DailyOpenSweep", "Venom", "OTE", "Custom")


# ---------------------------------------------------------------- input models
class AccountIn(BaseModel):
    label: str = Field(min_length=2, max_length=80)
    broker: str = Field(default="", max_length=80)
    server: str = Field(default="", max_length=120)
    login: str = Field(default="", max_length=40, pattern=r"^[0-9]*$")
    kind: Literal["demo", "real", "prop"] = "demo"
    server_winter_offset_h: int = Field(default=2, ge=-12, le=14)
    server_dst_rule: Literal["us", "eu", "none"] = "us"
    currency: str = Field(default="USD", min_length=3, max_length=8)
    starting_balance: float | None = Field(default=None, ge=0, le=1e9)
    prop_profile: str | None = Field(default=None, max_length=60)


class TradingPlan(BaseModel):
    markets: list[str] = Field(default_factory=list, max_length=20)
    killzones: list[Literal["Asia", "London", "NY_AM", "NY_Lunch", "NY_PM"]] = Field(default_factory=list)
    risk_per_trade_pct: float = Field(default=1.0, gt=0, le=10)
    max_daily_loss_pct: float = Field(default=3.0, gt=0, le=50)
    max_trades_per_day: int = Field(default=3, ge=1, le=100)
    revenge_minutes: int = Field(default=15, ge=1, le=240)
    size_up_factor: float = Field(default=1.5, ge=1.05, le=10)
    min_rr: float = Field(default=2.0, ge=0, le=20)
    setups: list[str] = Field(default_factory=list, max_length=10)
    rules: list[str] = Field(default_factory=list, max_length=15)  # free-text rules, shown to the Coach

    @field_validator("markets")
    @classmethod
    def _norm_markets(cls, v: list[str]) -> list[str]:
        return sorted({I.normalize_symbol(s) for s in v if s.strip()})

    @field_validator("rules")
    @classmethod
    def _rules(cls, v: list[str]) -> list[str]:
        return [r.strip()[:200] for r in v if r.strip()]


class UserProfile(BaseModel):
    """Declared by the member, corrected by the member; never inferred."""

    level: Literal["debutant", "intermediaire", "confirme", "professionnel"] = "debutant"
    experience_months: int = Field(default=0, ge=0, le=600)
    goals: list[str] = Field(default_factory=list, max_length=5)
    prop_firm: str | None = Field(default=None, max_length=60)
    trades_manually: bool = True
    uses_eas: bool = False
    language: Literal["fr", "en"] = "fr"


class JournalEntryIn(BaseModel):
    setup_model: str | None = Field(default=None, max_length=30)
    emotion_before: EmotionDeclared | None = None
    emotion_after: EmotionDeclared | None = None
    followed_plan: bool | None = None
    mistakes: list[MistakeKind] = Field(default_factory=list, max_length=6)
    notes: str = Field(default="", max_length=4000)
    rating: int | None = Field(default=None, ge=1, le=5)


class ManualTradeIn(BaseModel):
    account_id: str = Field(min_length=4, max_length=40)
    symbol: str = Field(min_length=2, max_length=30)
    side: Literal["long", "short"]
    volume: float = Field(gt=0, le=10_000)
    open_time_utc: int = Field(gt=0)
    open_price: float = Field(gt=0)
    close_time_utc: int | None = None
    close_price: float | None = Field(default=None, gt=0)
    sl: float | None = Field(default=None, gt=0)
    tp: float | None = Field(default=None, gt=0)
    profit: float = 0.0
    commission: float = 0.0
    swap: float = 0.0


class FileImportIn(BaseModel):
    account_id: str = Field(min_length=4, max_length=40)
    filename: str = Field(min_length=1, max_length=200)
    content_base64: str = Field(min_length=4, max_length=MAX_FILE_BYTES * 4 // 3 + 16)
    times_are_utc: bool = False


class SyncDeal(BaseModel):
    ticket: int
    order: int = 0
    position_id: int
    time: int  # server seconds
    time_msc: int = 0
    type: int
    entry: int
    symbol: str = Field(max_length=40)
    volume: float
    price: float
    commission: float = 0.0
    swap: float = 0.0
    profit: float = 0.0
    fee: float = 0.0
    magic: int = 0
    comment: str = Field(default="", max_length=120)


class SyncPosition(BaseModel):
    position_id: int
    initial_sl: float = 0.0
    initial_tp: float = 0.0
    sl: float = 0.0
    tp: float = 0.0


class SyncAccount(BaseModel):
    login: int
    server: str = Field(max_length=120)
    company: str = Field(default="", max_length=120)
    currency: str = Field(default="USD", max_length=8)
    balance: float
    equity: float
    margin: float = 0.0
    server_utc_offset_min: int = Field(ge=-14 * 60, le=14 * 60)
    trade_mode: int = 0  # 0 demo, 1 contest, 2 real


class SyncPayload(BaseModel):
    version: str = Field(default="1", max_length=10)
    account: SyncAccount
    deals: list[SyncDeal] = Field(default_factory=list, max_length=5000)
    positions: list[SyncPosition] = Field(default_factory=list, max_length=2000)


class InvestorIn(BaseModel):
    password: str | None = Field(default=None, min_length=4, max_length=64)


class EraseIn(BaseModel):
    confirmation: str = Field(max_length=40)


# ---------------------------------------------------------------- service
def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


class Journal:
    def __init__(self, saas: SaaS):
        self.saas = saas
        self.db = saas.db
        self.cfg = saas.config.get("journal", {})
        self._rate: dict[str, deque] = {}
        self._rate_lock = threading.Lock()

    # ---- plan and profile ----
    def plan(self, s: Scoped, user_id: int) -> dict[str, Any]:
        row = s.one(trading_plans, {"user_id": user_id})
        return row["body"] if row else TradingPlan(**self.cfg.get("default_plan", {})).model_dump()

    def set_plan(self, acc: Access, body: TradingPlan) -> dict[str, Any]:
        with self.db.tenant(acc.tenant_id) as s:
            s.upsert(trading_plans, {"user_id": acc.member_id}, {"body": body.model_dump(), "updated_at": now_ms()})
        return body.model_dump()

    def profile(self, s: Scoped, user_id: int) -> dict[str, Any]:
        row = s.one(user_profiles, {"user_id": user_id})
        return row["body"] if row else UserProfile().model_dump()

    def set_profile(self, acc: Access, body: UserProfile) -> dict[str, Any]:
        with self.db.tenant(acc.tenant_id) as s:
            s.upsert(user_profiles, {"user_id": acc.member_id}, {"body": body.model_dump(), "updated_at": now_ms()})
        return body.model_dump()

    # ---- accounts ----
    @staticmethod
    def public_account(r: dict[str, Any]) -> dict[str, Any]:
        return {k: r[k] for k in ("id", "label", "broker", "server", "login", "kind", "access_mode", "server_winter_offset_h", "server_dst_rule", "server_utc_offset_min",
                                  "currency", "starting_balance", "prop_profile", "last_sync_at", "created_at")} | {"has_secret": bool(r.get("secret_enc"))}

    def accounts(self, acc: Access) -> list[dict[str, Any]]:
        with self.db.tenant(acc.tenant_id) as s:
            rows = s.select(broker_accounts, {"user_id": acc.member_id, "archived": False}, order_by=broker_accounts.c.created_at)
        return [self.public_account(r) for r in rows]

    def account(self, s: Scoped, user_id: int, account_id: str) -> dict[str, Any]:
        row = s.one(broker_accounts, {"id": account_id, "user_id": user_id, "archived": False})
        if row is None:
            raise LookupError("compte introuvable")
        return row

    def create_account(self, acc: Access, body: AccountIn) -> dict[str, Any]:
        with self.db.tenant(acc.tenant_id) as s:
            if s.count(broker_accounts, {"user_id": acc.member_id, "archived": False}) >= 20:
                raise ValueError("20 comptes maximum")
            row = {"id": new_id("acc"), "user_id": acc.member_id, **body.model_dump(), "access_mode": "csv", "created_at": now_ms(), "archived": False}
            s.insert(broker_accounts, row)
            return self.public_account(s.one(broker_accounts, {"id": row["id"]}))

    def update_account(self, acc: Access, account_id: str, body: AccountIn) -> dict[str, Any]:
        with self.db.tenant(acc.tenant_id) as s:
            self.account(s, acc.member_id, account_id)
            s.update(broker_accounts, {"id": account_id}, body.model_dump())
            return self.public_account(s.one(broker_accounts, {"id": account_id}))

    def archive_account(self, acc: Access, account_id: str) -> None:
        with self.db.tenant(acc.tenant_id) as s:
            self.account(s, acc.member_id, account_id)
            s.update(broker_accounts, {"id": account_id}, {"archived": True, "secret_enc": None})
            s.update(api_tokens, {"account_id": account_id, "revoked_at": None}, {"revoked_at": now_ms()})

    # ---- tokens (EA Journal Sync) ----
    def create_sync_token(self, acc: Access, account_id: str) -> dict[str, Any]:
        acc.require("mt5_sync", "Synchronisation MT5")
        token = "aej_" + secrets.token_urlsafe(24)
        with self.db.tenant(acc.tenant_id) as s:
            self.account(s, acc.member_id, account_id)
            s.update(api_tokens, {"account_id": account_id, "kind": "ea_sync", "revoked_at": None}, {"revoked_at": now_ms()})
            s.insert(api_tokens, {"id": new_id("tok"), "user_id": acc.member_id, "kind": "ea_sync", "label": "EA Journal Sync", "token_hash": token_hash(token),
                                  "account_id": account_id, "scopes": ["ingest:mt5", "ingest:telemetry"], "created_at": now_ms()})
            s.update(broker_accounts, {"id": account_id}, {"access_mode": "sync_ea"})
        base = self.saas.settings.public_url or ""
        return {"token": token, "url": f"{base}/api/ingest/mt5" if base else "/api/ingest/mt5", "shown_once": True}

    def set_investor(self, acc: Access, account_id: str, password: str | None) -> dict[str, Any]:
        """Investor (read-only) password for the MT5 bridge; ``None`` removes it."""
        from hedgefund.saas.vault import Vault

        acc.require("mt5_sync", "Synchronisation MT5")
        with self.db.tenant(acc.tenant_id) as s:
            a = self.account(s, acc.member_id, account_id)
            if password is None:
                s.update(broker_accounts, {"id": account_id}, {"secret_enc": None, "access_mode": "csv" if a["access_mode"] == "investor" else a["access_mode"]})
            else:
                if not a["login"] or not a["server"]:
                    raise ValueError("renseignez d'abord le numéro de compte et le serveur MT5")
                s.update(broker_accounts, {"id": account_id}, {"secret_enc": Vault().encrypt(password), "access_mode": "investor"})
            return self.public_account(s.one(broker_accounts, {"id": account_id}))

    def tokens(self, acc: Access) -> list[dict[str, Any]]:
        with self.db.tenant(acc.tenant_id) as s:
            rows = s.select(api_tokens, {"user_id": acc.member_id, "revoked_at": None}, order_by=api_tokens.c.created_at)
        return [{k: r[k] for k in ("id", "kind", "label", "account_id", "scopes", "created_at", "last_used_at")} for r in rows]

    def revoke_token(self, acc: Access, token_id: str) -> None:
        with self.db.tenant(acc.tenant_id) as s:
            if s.update(api_tokens, {"id": token_id, "user_id": acc.member_id, "revoked_at": None}, {"revoked_at": now_ms()}) == 0:
                raise LookupError("jeton introuvable")

    def resolve_token(self, token: str, scope: str) -> dict[str, Any]:
        with self.db.system() as conn:
            row = conn.execute(select(api_tokens).where(api_tokens.c.token_hash == token_hash(token or ""))).first()
        if row is None or row.revoked_at is not None or scope not in (row.scopes or []):
            raise PermissionError("jeton invalide ou révoqué")
        return dict(row._mapping)

    def rate_ok(self, key: str, per_minute: int = 6) -> bool:
        now = time.monotonic()
        with self._rate_lock:
            q = self._rate.setdefault(key, deque())
            while q and now - q[0] > 60:
                q.popleft()
            if len(q) >= per_minute:
                return False
            q.append(now)
            return True

    # ---- import ----
    def _balance(self, s: Scoped, account: dict[str, Any]) -> float | None:
        snap = s.select(account_snapshots, {"account_id": account["id"]}, order_by=desc(account_snapshots.c.time_utc), limit=1)
        if snap:
            return float(snap[0]["balance"])
        return float(account["starting_balance"]) if account.get("starting_balance") else None

    def import_raw(self, tenant_id: str, user_id: int, plan_key: str, account_id: str, raws: list[I.RawTrade], source: str) -> dict[str, Any]:
        cap = int(self.saas.limits(plan_key).get("trades_per_month") or 0)
        stats = {"parsed": len(raws), "inserted": 0, "updated": 0, "unchanged": 0, "open": 0, "skipped_cap": 0, "errors": []}
        job_id = new_id("imp")
        with self.db.tenant(tenant_id) as s:
            account = self.account(s, user_id, account_id)
            plan = self.plan(s, user_id)
            balance = self._balance(s, account)
            month_counts: dict[str, int] = {}
            existing = {r["position_id"]: r for r in s.select(trades, {"account_id": account_id})}
            for t in sorted(raws, key=lambda x: x.open_server_ms):
                try:
                    sym = I.normalize_symbol(t.symbol_raw)
                    e = I.enrich(t, account, plan, balance)
                except I.ImportError_ as err:
                    stats["errors"].append(f"{t.position_id}: {err}")
                    continue
                old = existing.get(t.position_id)
                row = {
                    "user_id": user_id, "account_id": account_id, "position_id": t.position_id, "symbol_raw": t.symbol_raw[:40], "symbol": sym, "side": t.side, "volume": t.volume,
                    "open_utc": e.open_utc, "close_utc": e.close_utc, "open_price": t.open_price, "close_price": t.close_price, "sl": t.initial_sl or t.sl, "tp": t.tp,
                    "commission": t.commission, "swap": t.swap, "profit": t.profit, "net": e.net, "risk_amount": e.risk_amount, "r_multiple": e.r_multiple, "r_source": e.r_source,
                    "session": e.session, "killzone": e.killzone, "macro": e.macro, "weekday": e.weekday, "plan_respected": e.plan_respected,
                    "magic": t.magic, "comment": t.comment, "source": source, "import_job_id": job_id, "enrichment_version": I.ENRICHMENT_VERSION,
                }
                if old is None:
                    if cap:
                        mk = month_key(e.open_utc)
                        if mk not in month_counts:
                            month_counts[mk] = sum(1 for r in existing.values() if month_key(r["open_utc"]) == mk)
                        if month_counts[mk] >= cap:
                            stats["skipped_cap"] += 1
                            continue
                        month_counts[mk] += 1
                    tid = new_id("trd")
                    s.insert(trades, {"id": tid, **row, "setup_model": e.setup_model, "imported_at": now_ms()})
                    stats["inserted"] += 1
                    existing[t.position_id] = {**row, "id": tid}
                else:
                    tid = old["id"]
                    changed = any(old.get(k) != row[k] for k in ("close_utc", "close_price", "profit", "commission", "swap", "sl", "volume", "r_multiple"))
                    if changed:
                        s.update(trades, {"id": tid}, {k: v for k, v in row.items() if k not in ("user_id", "account_id", "position_id")})
                        stats["updated"] += 1
                    else:
                        stats["unchanged"] += 1
                if e.close_utc is None:
                    stats["open"] += 1
                for d in t.deals:
                    if s.one(executions, {"account_id": account_id, "deal_id": d["deal_id"]}) is None:
                        conv = I.server_to_utc(d["time_server_ms"], int(account.get("server_winter_offset_h") or 2), account.get("server_dst_rule") or "us", account.get("server_utc_offset_min"))
                        s.insert(executions, {"id": new_id("exe"), "account_id": account_id, "position_id": t.position_id, "deal_id": d["deal_id"], "time_utc": conv, "entry": d["entry"],
                                              "side": d["side"], "price": d["price"], "volume": d["volume"], "profit": d["profit"], "commission": d["commission"], "swap": d["swap"]})
            stats["errors"] = stats["errors"][:20]
            s.insert(import_jobs, {"id": job_id, "user_id": user_id, "account_id": account_id, "source": source, "status": "done", "stats": stats, "created_at": now_ms()})
        stats["job_id"] = job_id
        return stats

    def import_file(self, acc: Access, body: FileImportIn) -> dict[str, Any]:
        try:
            raw = base64.b64decode(body.content_base64, validate=True)
        except ValueError as e:
            raise ValueError("fichier illisible (base64 invalide)") from e
        if len(raw) > MAX_FILE_BYTES:
            raise ValueError("fichier trop volumineux (5 Mo maximum)")
        name = body.filename.lower()
        text = I.decode_report(raw)
        try:
            if name.endswith((".htm", ".html")) or "<table" in text[:5000].lower():
                raws, _info = I.parse_mt5_report(text)
                source = "mt5_report"
            elif name.endswith((".csv", ".txt")):
                raws = I.parse_csv(text, body.times_are_utc)
                source = "csv"
            else:
                raise I.ImportError_("format non pris en charge : envoyez un CSV ou le rapport HTML de MT5")
        except I.ImportError_ as e:
            with self.db.tenant(acc.tenant_id) as s:
                self.account(s, acc.member_id, body.account_id)
                s.insert(import_jobs, {"id": new_id("imp"), "user_id": acc.member_id, "account_id": body.account_id, "source": "file", "status": "failed", "stats": {}, "error": str(e), "created_at": now_ms()})
            raise ValueError(str(e)) from e
        return self.import_raw(acc.tenant_id, acc.member_id, acc.plan, body.account_id, raws, source)

    def ingest_sync(self, token: str, body: SyncPayload, plan_key_of: Any) -> dict[str, Any]:
        tok = self.resolve_token(token, "ingest:mt5")
        if not self.rate_ok(tok["id"]):
            raise OverflowError("trop de synchronisations : une par 10 secondes au plus")
        tenant, user_id, account_id = tok["tenant_id"], tok["user_id"], tok["account_id"]
        a = body.account
        with self.db.tenant(tenant) as s:
            account = self.account(s, user_id, account_id)
            if account["login"] and str(account["login"]) != str(a.login):
                raise PermissionError(f"ce jeton est lié au compte {account['login']}, pas au compte {a.login}")
            upd: dict[str, Any] = {"server_utc_offset_min": a.server_utc_offset_min, "last_sync_at": now_ms(), "currency": a.currency[:8], "access_mode": "sync_ea"}
            if not account["login"]:
                upd["login"] = str(a.login)
            if not account["server"]:
                upd["server"] = a.server[:120]
            if not account["broker"]:
                upd["broker"] = a.company[:80]
            s.update(broker_accounts, {"id": account_id}, upd)
            s.insert(account_snapshots, {"id": new_id("snp"), "account_id": account_id, "time_utc": now_ms(), "balance": a.balance, "equity": a.equity, "margin": a.margin, "source": "sync_ea"})
            s.update(api_tokens, {"id": tok["id"]}, {"last_used_at": now_ms()})
        meta = {str(p.position_id): {"initial_sl": p.initial_sl or None, "tp": p.tp or p.initial_tp or None, "sl": p.sl or None} for p in body.positions}
        raws = I.trades_from_deals([d.model_dump() for d in body.deals], meta)
        stats = self.import_raw(tenant, user_id, plan_key_of(user_id), account_id, raws, "sync_ea")
        return {"ok": True, **{k: stats[k] for k in ("inserted", "updated", "unchanged", "open", "skipped_cap")}, "server_time_utc": now_ms()}

    def imports(self, acc: Access, limit: int = 30) -> list[dict[str, Any]]:
        with self.db.tenant(acc.tenant_id) as s:
            return s.select(import_jobs, {"user_id": acc.member_id}, order_by=desc(import_jobs.c.created_at), limit=limit)

    # ---- trades ----
    def list_trades(self, s: Scoped, user_id: int, since: int | None = None, until: int | None = None, account_id: str | None = None, symbol: str | None = None,
                    closed_only: bool = False, limit: int = 500, offset: int = 0) -> list[dict[str, Any]]:
        extra = []
        if since:
            extra.append(trades.c.open_utc >= since)
        if until:
            extra.append(trades.c.open_utc < until)
        if closed_only:
            extra.append(trades.c.close_utc.is_not(None))
        where: dict[str, Any] = {"user_id": user_id}
        if account_id:
            where["account_id"] = account_id
        if symbol:
            where["symbol"] = I.normalize_symbol(symbol)
        q = s.select(trades, where, *extra, order_by=desc(trades.c.open_utc), limit=limit + offset)
        return q[offset:]

    def trades_with_entries(self, acc: Access, **kw: Any) -> list[dict[str, Any]]:
        with self.db.tenant(acc.tenant_id) as s:
            rows = self.list_trades(s, acc.member_id, **kw)
            entries = {e["trade_id"]: e for e in s.select(journal_entries, {"user_id": acc.member_id})}
        for r in rows:
            e = entries.get(r["id"])
            r["journal"] = {k: e[k] for k in ("setup_model", "emotion_before", "emotion_after", "followed_plan", "mistakes", "notes", "rating")} if e else None
            if e and e.get("setup_model"):
                r["setup_model"] = e["setup_model"]
        return rows

    def trade(self, acc: Access, trade_id: str) -> dict[str, Any]:
        with self.db.tenant(acc.tenant_id) as s:
            t = s.one(trades, {"id": trade_id, "user_id": acc.member_id})
            if t is None:
                raise LookupError("trade introuvable")
            t["executions"] = s.select(executions, {"account_id": t["account_id"], "position_id": t["position_id"]}, order_by=executions.c.time_utc)
            e = s.one(journal_entries, {"trade_id": trade_id})
            t["journal"] = e
        return t

    def set_entry(self, acc: Access, trade_id: str, body: JournalEntryIn) -> dict[str, Any]:
        with self.db.tenant(acc.tenant_id) as s:
            if s.one(trades, {"id": trade_id, "user_id": acc.member_id}) is None:
                raise LookupError("trade introuvable")
            vals = {**body.model_dump(), "user_id": acc.member_id, "updated_at": now_ms()}
            s.upsert(journal_entries, {"trade_id": trade_id}, vals)
            if body.setup_model:
                s.update(trades, {"id": trade_id}, {"setup_model": body.setup_model[:30]})
            if body.followed_plan is not None:
                s.update(trades, {"id": trade_id}, {"plan_respected": body.followed_plan})
        return self.trade(acc, trade_id)

    def add_manual(self, acc: Access, body: ManualTradeIn) -> dict[str, Any]:
        raw = I.RawTrade(position_id="man_" + secrets.token_hex(6), symbol_raw=body.symbol, side=body.side, volume=body.volume, open_server_ms=body.open_time_utc,
                         open_price=body.open_price, close_server_ms=body.close_time_utc, close_price=body.close_price, sl=body.sl, tp=body.tp, profit=body.profit,
                         commission=body.commission, swap=body.swap, times_are_utc=True)
        return self.import_raw(acc.tenant_id, acc.member_id, acc.plan, body.account_id, [raw], "manual")

    def delete_trade(self, acc: Access, trade_id: str) -> None:
        with self.db.tenant(acc.tenant_id) as s:
            t = s.one(trades, {"id": trade_id, "user_id": acc.member_id})
            if t is None:
                raise LookupError("trade introuvable")
            if t["source"] != "manual":
                raise ValueError("seuls les trades saisis à la main se suppriment ; un trade importé revient à la prochaine synchronisation")
            s.delete(journal_entries, {"trade_id": trade_id})
            s.delete(trades, {"id": trade_id})

    # ---- data rights ----
    def export(self, acc: Access) -> dict[str, Any]:
        with self.db.tenant(acc.tenant_id) as s:
            out = {"exported_at": datetime.now(timezone.utc).isoformat(), "tenant": acc.tenant_id, "plan": self.plan(s, acc.member_id), "profile": self.profile(s, acc.member_id)}
            out["accounts"] = [self.public_account(r) for r in s.select(broker_accounts, {"user_id": acc.member_id})]
            for name, table in (("trades", trades), ("journal_entries", journal_entries), ("lessons", lessons), ("episodes", memories_episodic)):
                out[name] = s.select(table, {"user_id": acc.member_id})
        return out

    def erase(self, acc: Access) -> dict[str, int]:
        """Deletes every SaaS row of the member's personal tenant (right to erasure). The audit
        records stay: they are the platform's legal trail, and hold redacted requests only."""
        from hedgefund.saas.db import TENANT_TABLES, metadata

        counts = {}
        with self.db.tenant(acc.tenant_id) as s:
            for name in TENANT_TABLES:
                if name in ("audit_records",):
                    continue
                counts[name] = s.conn.execute(metadata.tables[name].delete().where(metadata.tables[name].c.tenant_id == acc.tenant_id)).rowcount
        return {k: v for k, v in counts.items() if v}


# ---------------------------------------------------------------- tools (agents and MCP)
class QueryTradesIn(BaseModel):
    since_days: int = Field(default=30, ge=1, le=366)
    symbol: str | None = Field(default=None, max_length=20)
    killzone: str | None = Field(default=None, max_length=12)
    setup_model: str | None = Field(default=None, max_length=30)
    only_losses: bool = False
    limit: int = Field(default=20, ge=1, le=50)


def _query_trades(ctx: ToolContext, p: QueryTradesIn) -> dict[str, Any]:
    j: Journal = ctx.services.modules["journal"]
    since = now_ms() - p.since_days * 86_400_000
    with ctx.db.tenant(ctx.tenant_id) as s:
        rows = j.list_trades(s, ctx.user_id, since=since, symbol=p.symbol, closed_only=True, limit=500)
    if p.killzone:
        rows = [r for r in rows if r["killzone"] == p.killzone]
    if p.setup_model:
        rows = [r for r in rows if r["setup_model"] == p.setup_model]
    if p.only_losses:
        rows = [r for r in rows if (r["net"] or 0) < 0]
    keep = ("id", "symbol", "side", "open_utc", "close_utc", "volume", "net", "r_multiple", "killzone", "setup_model", "plan_respected")
    return {"count": len(rows), "trades": [{k: r[k] for k in keep} for r in rows[: p.limit]]}


# ---------------------------------------------------------------- routes
def mount(ctx: ApiContext) -> None:
    app, saas = ctx.app, ctx.saas
    j: Journal = saas.modules["journal"]
    acc_dep = ctx.acc()

    @app.get("/api/app/plan")
    def get_plan(acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        with saas.db.tenant(acc.tenant_id) as s:
            return {"plan": j.plan(s, acc.member_id), "killzones": KILLZONE_NAMES, "setups": SETUP_NAMES}

    @app.put("/api/app/plan")
    def put_plan(body: TradingPlan, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: j.set_plan(acc, body))

    @app.get("/api/app/profile")
    def get_profile(acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        with saas.db.tenant(acc.tenant_id) as s:
            return j.profile(s, acc.member_id)

    @app.put("/api/app/profile")
    def put_profile(body: UserProfile, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: j.set_profile(acc, body))

    @app.get("/api/app/accounts")
    def list_accounts(acc: Access = Depends(acc_dep)) -> list[dict]:  # noqa: B008
        return j.accounts(acc)

    @app.post("/api/app/accounts")
    def create_account(body: AccountIn, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: j.create_account(acc, body))

    @app.put("/api/app/accounts/{account_id}")
    def update_account(account_id: str, body: AccountIn, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: j.update_account(acc, account_id[:40], body))

    @app.delete("/api/app/accounts/{account_id}")
    def archive_account(account_id: str, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        guard(lambda: j.archive_account(acc, account_id[:40]))
        return {"ok": True}

    @app.post("/api/app/accounts/{account_id}/sync-token")
    def sync_token(account_id: str, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: j.create_sync_token(acc, account_id[:40]))

    @app.put("/api/app/accounts/{account_id}/investor")
    def set_investor(account_id: str, body: InvestorIn, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        from hedgefund.saas.vault import VaultError

        try:
            return j.set_investor(acc, account_id[:40], body.password)
        except VaultError as e:
            raise HTTPException(400, str(e)) from e
        except Exception as e:  # noqa: BLE001
            from hedgefund.saas.api import http_error

            raise http_error(e) from e

    @app.get("/api/app/tokens")
    def list_tokens(acc: Access = Depends(acc_dep)) -> list[dict]:  # noqa: B008
        return j.tokens(acc)

    @app.delete("/api/app/tokens/{token_id}")
    def revoke_token(token_id: str, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        guard(lambda: j.revoke_token(acc, token_id[:40]))
        return {"ok": True}

    @app.post("/api/app/import")
    def import_file(body: FileImportIn, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: j.import_file(acc, body))

    @app.get("/api/app/imports")
    def list_imports(acc: Access = Depends(acc_dep)) -> list[dict]:  # noqa: B008
        return j.imports(acc)

    @app.get("/api/app/trades")
    def list_trades(days: int = 90, account: str = "", symbol: str = "", limit: int = 200, offset: int = 0, acc: Access = Depends(acc_dep)) -> list[dict]:  # noqa: B008
        since = now_ms() - max(1, min(days, 3660)) * 86_400_000
        return guard(lambda: j.trades_with_entries(acc, since=since, account_id=account[:40] or None, symbol=symbol[:20] or None, limit=max(1, min(limit, 1000)), offset=max(0, offset)))

    @app.post("/api/app/trades")
    def add_trade(body: ManualTradeIn, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: j.add_manual(acc, body))

    @app.get("/api/app/trades/{trade_id}")
    def get_trade(trade_id: str, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: j.trade(acc, trade_id[:40]))

    @app.put("/api/app/trades/{trade_id}/journal")
    def put_entry(trade_id: str, body: JournalEntryIn, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: j.set_entry(acc, trade_id[:40], body))

    @app.delete("/api/app/trades/{trade_id}")
    def delete_trade(trade_id: str, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        guard(lambda: j.delete_trade(acc, trade_id[:40]))
        return {"ok": True}

    @app.get("/api/app/export")
    def export(acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return j.export(acc)

    @app.post("/api/app/erase")
    def erase(body: EraseIn, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        if body.confirmation.strip().upper() != "EFFACER MES DONNEES":
            raise HTTPException(400, "tapez exactement : EFFACER MES DONNEES")
        return {"ok": True, "deleted": j.erase(acc)}

    # ---- machine route: EA Journal Sync ----
    @app.post("/api/ingest/mt5")
    def ingest_mt5(body: SyncPayload, request: Request) -> dict:
        auth = request.headers.get("authorization", "")
        token = auth[7:].strip() if auth.lower().startswith("bearer ") else request.headers.get("x-journal-token", "").strip()
        try:
            return j.ingest_sync(token, body, ctx.plan_of)
        except PermissionError as e:
            raise HTTPException(401, str(e)) from e
        except OverflowError as e:
            raise HTTPException(429, str(e)) from e
        except Exception as e:  # noqa: BLE001
            from hedgefund.saas.api import http_error

            raise http_error(e) from e


def install(saas: SaaS) -> Journal:
    j = Journal(saas)
    saas.modules["journal"] = j
    saas.tools.register(Tool("journal.query_trades", "Trades clôturés du membre (filtres : période, symbole, killzone, setup, pertes). Renvoie au plus 50 lignes résumées.",
                             QueryTradesIn, _query_trades, read_only=True, timeout_s=5.0))
    return j


ROUTERS.append(mount)

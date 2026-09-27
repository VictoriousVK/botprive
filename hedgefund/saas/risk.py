"""Risk module: account state rebuilt from the journal (snapshots from the EA, or the starting
balance plus closed trades), prop firm profiles, the position-size calculator, the guard status
and the ``risk.gate`` / ``risk.status`` tools. Read-only: nothing here places an order."""

from __future__ import annotations

from typing import Any

from fastapi import Depends
from pydantic import BaseModel, Field
from sqlalchemy import asc

from hedgefund.saas.api import ROUTERS, ApiContext, guard
from hedgefund.saas.db import account_snapshots, broker_accounts, now_ms, trades
from hedgefund.saas.engines import risk as R
from hedgefund.saas.ingest import killzone_at, normalize_symbol
from hedgefund.saas.service import Access, SaaS
from hedgefund.saas.tools import Tool, ToolContext


class ProposalIn(BaseModel):
    symbol: str = Field(min_length=2, max_length=20)
    direction: str = Field(pattern=r"^(long|short)$")
    entry: float = Field(gt=0)
    stop: float = Field(gt=0)
    target: float | None = Field(default=None, gt=0)
    requested_lots: float | None = Field(default=None, gt=0, le=1000)
    account_id: str | None = Field(default=None, max_length=40)


class Risk:
    def __init__(self, saas: SaaS):
        self.saas = saas
        self.profiles = R.load_profiles()

    def public_profiles(self) -> list[dict[str, Any]]:
        keep = ("label", "version", "source", "verified_at", "daily_loss_pct", "daily_loss_ref", "daily_loss_base", "max_loss_pct", "max_loss_type", "profit_target_pct", "min_trading_days", "reset", "news_minutes")
        return [{"key": k, **{x: p.get(x) for x in keep}} for k, p in self.profiles.items()]

    def spec(self, symbol: str) -> R.SymbolSpec:
        m = self.saas.market
        if m is not None:
            specs = m.specs()
            if symbol in specs:
                return R.SymbolSpec.from_platform(specs[symbol])
        return R.SymbolSpec()

    def account(self, s: Any, user_id: int, account_id: str | None) -> dict[str, Any] | None:
        rows = s.select(broker_accounts, {"user_id": user_id, "archived": False}, order_by=broker_accounts.c.created_at)
        if account_id:
            rows = [r for r in rows if r["id"] == account_id]
            if not rows:
                raise LookupError("compte introuvable")
        return rows[0] if rows else None

    def state(self, tenant_id: str, user_id: int, account_id: str | None, reset: str) -> tuple[R.AccountState, dict[str, Any] | None]:
        now = now_ms()
        start = R.day_start(now, reset)
        with self.saas.db.tenant(tenant_id) as s:
            a = self.account(s, user_id, account_id)
            if a is None:
                raise LookupError("créez d'abord un compte de trading (avec son solde de départ)")
            snaps = s.select(account_snapshots, {"account_id": a["id"]}, order_by=asc(account_snapshots.c.time_utc))
            rows = s.select(trades, {"account_id": a["id"], "user_id": user_id}, order_by=asc(trades.c.open_utc))
        closed = [t for t in rows if t["close_utc"]]
        open_ = [t for t in rows if not t["close_utc"]]
        realized_today = sum(t["net"] or 0 for t in closed if t["close_utc"] >= start)
        if snaps:
            last = snaps[-1]
            balance, equity, source = float(last["balance"]), float(last["equity"]), "snapshot"
            before = [x for x in snaps if x["time_utc"] <= start]
            sod_eq = float(before[-1]["equity"]) if before else balance - realized_today
            peak = max(float(x["equity"]) for x in snaps)
            initial = float(a["starting_balance"] or snaps[0]["balance"])
        else:
            initial = float(a["starting_balance"] or 0)
            if initial <= 0:
                raise LookupError("renseignez le solde de départ du compte, ou installez l'EA Journal Sync")
            balance = initial + sum(t["net"] or 0 for t in closed)
            equity, source, sod_eq = balance, "journal", balance - realized_today
            cum, peak = initial, initial
            for t in closed:
                cum += t["net"] or 0
                peak = max(peak, cum)
        open_risk = sum(t["risk_amount"] or 0 for t in open_ if t["r_source"] == "sl")
        unknown = sum(1 for t in open_ if not (t["risk_amount"] and t["r_source"] == "sl"))
        st = R.AccountState(balance=balance, equity=equity, initial_balance=initial, start_of_day_balance=balance - realized_today, start_of_day_equity=sod_eq,
                            peak_equity=max(peak, equity), open_risk=open_risk, open_risk_unknown=unknown, trades_today=sum(1 for t in rows if t["open_utc"] >= start), source=source)
        return st, a

    def profile_for(self, acc: Access, a: dict[str, Any] | None) -> tuple[str, dict[str, Any], list[str]]:
        key = (a or {}).get("prop_profile") or "generic"
        notes = []
        if key != "generic" and not acc.can("prop_guard"):
            notes.append("profils prop firm réservés à l'offre Pro Trader : limites de votre plan appliquées")
            key = "generic"
        if key not in self.profiles:
            notes.append(f"profil inconnu ({key}) : limites de votre plan appliquées")
            key = "generic"
        return key, self.profiles[key], notes

    def gate(self, acc: Access, body: ProposalIn, tenant_plan: dict[str, Any] | None = None) -> dict[str, Any]:
        journal = self.saas.modules["journal"]
        symbol = normalize_symbol(body.symbol)
        with self.saas.db.tenant(acc.tenant_id) as s:
            plan = tenant_plan or journal.plan(s, acc.member_id)
            a = self.account(s, acc.member_id, body.account_id)
        key, profile, notes = self.profile_for(acc, a)
        state, a = self.state(acc.tenant_id, acc.member_id, body.account_id or (a or {}).get("id"), profile.get("reset", "ny_17"))
        now = now_ms()
        events = self.saas.modules["stats"].events(now - 3_600_000, now + 3_600_000) if "stats" in self.saas.modules else []
        p = R.Proposal(symbol, body.direction, body.entry, body.stop, body.target, body.requested_lots, killzone_at(now))
        res = R.gate(p, state, plan, key, profile, self.spec(symbol), events, now)
        res.warnings.extend(notes)
        if self.saas.market is None or symbol not in (self.saas.market.specs() if self.saas.market else {}):
            res.warnings.append("spécification du symbole inconnue : valeur du point supposée égale à la taille du contrat")
        else:
            res.warnings.append("valeur du point lue chez le broker de la plateforme : vérifiez-la chez le vôtre")
        return {**res.as_dict(), "account_id": a["id"], "state": state.__dict__, "symbol": symbol}

    def status(self, acc: Access, account_id: str | None) -> dict[str, Any]:
        journal = self.saas.modules["journal"]
        with self.saas.db.tenant(acc.tenant_id) as s:
            plan = journal.plan(s, acc.member_id)
            a = self.account(s, acc.member_id, account_id)
        key, profile, notes = self.profile_for(acc, a)
        state, a = self.state(acc.tenant_id, acc.member_id, account_id or (a or {}).get("id"), profile.get("reset", "ny_17"))
        st = R.status(state, plan, profile)
        return {"account_id": a["id"], "profile": key, "profile_label": profile.get("label"), "profile_verified": bool(profile.get("verified_at")),
                "state": state.__dict__, **st, "notes": notes, "day_start": R.day_start(now_ms(), profile.get("reset", "ny_17"))}


# ---------------------------------------------------------------- tools
class GateIn(BaseModel):
    symbol: str = Field(min_length=2, max_length=20)
    direction: str = Field(pattern=r"^(long|short)$")
    entry: float = Field(gt=0)
    stop: float = Field(gt=0)
    target: float | None = None


def _gate_tool(ctx: ToolContext, p: GateIn) -> dict[str, Any]:
    acc = Access(ctx.user_id, ctx.tenant_id, "gratuit", ctx.entitlements, features=ctx.services.features)
    out = ctx.services.modules["risk"].gate(acc, ProposalIn(symbol=p.symbol, direction=p.direction, entry=p.entry, stop=p.stop, target=p.target))
    out.pop("state", None)
    return out


class StatusIn(BaseModel):
    account_id: str | None = Field(default=None, max_length=40)


def _status_tool(ctx: ToolContext, p: StatusIn) -> dict[str, Any]:
    acc = Access(ctx.user_id, ctx.tenant_id, "gratuit", ctx.entitlements, features=ctx.services.features)
    return ctx.services.modules["risk"].status(acc, p.account_id)


def mount(ctx: ApiContext) -> None:
    app, saas = ctx.app, ctx.saas
    rk: Risk = saas.modules["risk"]
    acc_dep = ctx.acc()

    @app.get("/api/app/risk/profiles")
    def profiles(acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return {"profiles": rk.public_profiles(), "prop_guard": acc.can("prop_guard")}

    @app.post("/api/app/risk/size")
    def size(body: ProposalIn, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: rk.gate(acc, body))

    @app.get("/api/app/risk/status")
    def status(account: str = "", acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: rk.status(acc, account[:40] or None))


def install(saas: SaaS) -> Risk:
    rk = Risk(saas)
    saas.modules["risk"] = rk
    saas.tools.register(Tool("risk.gate", "Risk gate déterministe : taille maximale, risque en devise et en %, règles appliquées, violations (veto). Toujours appelé avant d'afficher une proposition.", GateIn, _gate_tool, retries=0))
    saas.tools.register(Tool("risk.status", "État des limites de perte (journalière, maximale) du compte selon le profil de prop firm ou le plan.", StatusIn, _status_tool))
    return rk


ROUTERS.append(mount)

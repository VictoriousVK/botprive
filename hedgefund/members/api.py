"""HTTP routes of the public site: /api/site/* (public), /api/m/* (members), /api/admin/*
(operators, with their console session) and /api/webhooks/wave.

Members get their own cookie (``lf_session``, SameSite=Lax so that the return from Wave keeps
the member signed in) and the same CSRF + Origin checks as the console.
"""

from __future__ import annotations

import hmac
import json
import time
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, Literal

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from pydantic import BaseModel, Field

from hedgefund import __version__
from hedgefund.bots.templates import TEMPLATES
from hedgefund.core.ledger import Kind
from hedgefund.members.academy import ACCESS, PROVIDERS, STATUSES, Academy, AcademyError
from hedgefund.members.copytrading import LEADER_STATUS, Copytrading, CopyError
from hedgefund.members.service import MemberError, Members
from hedgefund.members.site import ROBOT_STATUSES, MemberSettings, SiteConfig
from hedgefund.members.wave import verify_signature
from hedgefund.web.security import Session

MEMBER_COOKIE = "lf_session"


# ---------------- request models ----------------
class RegisterIn(BaseModel):
    email: str = Field(min_length=5, max_length=254)
    password: str = Field(min_length=1, max_length=200)
    name: str = Field(min_length=2, max_length=80)
    phone: str = Field(default="", max_length=24)
    accept_terms: bool


class MemberLoginIn(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=200)
    totp: str | None = Field(default=None, max_length=10)


class LeadIn(BaseModel):
    email: str = Field(min_length=5, max_length=254)
    interest: Literal["copytrading", "next_bot", "academie", "newsletter"]


class CheckoutIn(BaseModel):
    offer: str = Field(min_length=2, max_length=30)
    months: int = Field(ge=1, le=24)


class DeclareIn(BaseModel):
    transaction_ref: str = Field(min_length=6, max_length=40)


class ProgressIn(BaseModel):
    part_id: str = Field(min_length=4, max_length=40)
    position_s: int = Field(ge=0, le=86_400)
    completed: bool = False


class FollowIn(BaseModel):
    leader_id: str = Field(min_length=4, max_length=40)
    allocation: float = Field(ge=100, le=1_000_000)
    multiplier: float = Field(ge=0.1, le=3.0)
    max_drawdown_pct: float = Field(ge=5, le=50)
    accept_risk: bool
    mode: Literal["demo", "live"] = "demo"


class CourseIn(BaseModel):
    slug: str = Field(min_length=2, max_length=60)
    title: str = Field(min_length=3, max_length=120)
    subtitle: str = Field(default="", max_length=200)
    description: str = Field(default="", max_length=4000)
    level: str = Field(default="", max_length=40)
    access: Literal["academy_free", "academy_member", "academy_advanced"] = "academy_member"
    status: Literal["draft", "soon", "published"] = "draft"
    position: int = Field(default=0, ge=0, le=10_000)


class PartIn(BaseModel):
    title: str = Field(min_length=2, max_length=160)
    summary: str = Field(default="", max_length=2000)
    video: str = Field(min_length=3, max_length=500)
    provider: str = Field(default="", max_length=20)
    duration_s: int = Field(default=0, ge=0, le=4 * 3600)
    chapters: str = Field(default="", max_length=6000)
    free_preview: bool = False


class MoveIn(BaseModel):
    delta: Literal[-1, 1]


class LeaderIn(BaseModel):
    name: str = Field(min_length=3, max_length=80)
    trader: str = Field(min_length=2, max_length=80)
    bio: str = Field(default="", max_length=1000)
    style: str = Field(default="", max_length=120)
    bot_id: str | None = Field(default=None, max_length=40)
    risk_level: int = Field(default=3, ge=1, le=5)
    ref_capital: float = Field(ge=100, le=1e9)
    status: Literal["draft", "open", "paused", "closed"] = "draft"


class RejectIn(BaseModel):
    reason: str = Field(min_length=3, max_length=160)


class GrantIn(BaseModel):
    offer: str = Field(min_length=2, max_length=30)
    months: int = Field(ge=1, le=24)
    reason: str = Field(min_length=3, max_length=160)


class MemberStatusIn(BaseModel):
    status: Literal["active", "suspended"]


@dataclass
class SiteContext:
    engine: Any
    site: SiteConfig
    settings: MemberSettings
    members: Members
    academy: Academy
    copy: Copytrading
    cookie_secure: bool
    client_ip: Callable[[Request], str]
    operator: Callable[..., Session]  # FastAPI dependency: console session (with CSRF check)
    check_write: Callable[[Request, str], None]  # Origin + CSRF check for a state-changing call


def mount_members(app: FastAPI, ctx: SiteContext) -> None:
    members, academy, copy, site, settings, engine = ctx.members, ctx.academy, ctx.copy, ctx.site, ctx.settings, ctx.engine
    quotes_cache: dict[str, Any] = {"t": 0.0, "data": []}

    def fail(e: Exception, code: int = 400) -> HTTPException:
        return HTTPException(code, str(e))

    def audit(action: str, **details: Any) -> None:
        engine.ledger.append(Kind.OPERATOR, {"action": action, **details}, ts=int(time.time() * 1000))

    # ---------------- member session ----------------
    def member_opt(request: Request) -> tuple[Session, dict] | None:
        s = members.auth.session(request.cookies.get(MEMBER_COOKIE))
        if s is None:
            return None
        m = members.get(s.user_id)
        if m is None or m["status"] != "active":
            return None
        if request.method not in ("GET", "HEAD", "OPTIONS"):
            ctx.check_write(request, s.csrf)
        return s, m

    def member(request: Request) -> tuple[Session, dict]:
        sm = member_opt(request)
        if sm is None:
            raise HTTPException(401, "connectez-vous à votre espace membre")
        return sm

    def me_payload(s: Session, m: dict) -> dict:
        return {**members.profile(m), "csrf": s.csrf}

    # ---------------- public ----------------
    @app.get("/api/site")
    def site_info() -> dict:
        wave = "api" if members.wave is not None else ("manual" if site.public()["billing"]["wave_manual"] else "off")
        return {**site.public(), "copytrading": copy.mode, "wave": wave, "registration_open": settings.registration_open, "version": __version__}

    @app.get("/api/site/robots")
    def robots() -> list[dict]:
        out = []
        for r in site.robots:
            t = TEMPLATES.get(r.get("template", ""))
            out.append({
                "key": r["key"], "name": r.get("name", ""), "status": r["status"], "status_label": ROBOT_STATUSES[r["status"]], "headline": r.get("headline", ""),
                "markets": r.get("markets", ""), "access": r.get("access"), "description": t.description if t else "", "timeframes": list(t.timeframes) if t else [],
                "origin": t.origin if t else "", "params": len(t.params) if t else 0,
            })
        return out

    @app.get("/api/site/quotes")
    def quotes() -> dict:
        now = time.monotonic()
        if now - quotes_cache["t"] > 5:
            data = []
            specs = engine.feed.specs()
            for sym in site.ticker:
                if sym not in specs:
                    continue
                try:
                    q = engine.feed.quote(sym)
                    if not q:
                        continue
                    price = (q[0] + q[1]) / 2
                    daily = engine.feed.market_data([sym], "1d", 2, engine.clock.now_ms()).bars[sym]
                    ref = daily.close[-1] if len(daily) else None  # last completed daily close
                    data.append({"symbol": sym, "label": specs[sym].description, "price": price, "digits": specs[sym].digits, "change_pct": (price / ref - 1) * 100 if ref else None})
                except Exception:  # noqa: BLE001 - one broken symbol must not break the banner
                    continue
            quotes_cache.update(t=now, data=data)
        return {"synthetic": bool(engine.feed.synthetic), "source": engine.feed.name, "quotes": quotes_cache["data"]}

    @app.get("/api/site/leaders")
    def leaders() -> dict:
        return {"mode": copy.mode, "leaders": copy.leaders() if copy.enabled else []}

    @app.get("/api/site/courses")
    def courses() -> list[dict]:
        return academy.catalog()

    @app.get("/api/site/courses/{slug}")
    def course(slug: str, request: Request) -> dict:
        sm = member_opt(request)
        ents = members.entitlements(sm[1]) if sm else set()
        c = academy.course(slug[:60], ents, sm[1]["id"] if sm else None)
        if c is None:
            planned = next((p for p in site.academy.get("planned", []) if p.get("slug") == slug), None)
            if planned is None:
                raise HTTPException(404, "cours introuvable")
            return {**planned, "status": "soon", "access": "academy_member", "access_label": ACCESS["academy_member"], "unlocked": False, "parts": [], "description": ""}
        return c

    @app.post("/api/site/leads")
    def lead(body: LeadIn, request: Request) -> dict:
        ip = ctx.client_ip(request)
        key = f"lead:{ip}"
        n = engine.store.execute("SELECT COUNT(*) AS n FROM login_attempts WHERE key = ? AND ts > ?", (key, int(time.time()) - 3600))[0]["n"]
        if n >= 10:
            raise HTTPException(429, "trop de demandes : réessayez plus tard")
        engine.store.execute("INSERT INTO login_attempts (key, ts, ok) VALUES (?, ?, 1)", (key, int(time.time())))
        try:
            members.add_lead(body.email, body.interest)
        except MemberError as e:
            raise fail(e) from e
        return {"ok": True}

    # ---------------- member accounts ----------------
    def set_cookie(response: Response, token: str) -> None:
        response.set_cookie(MEMBER_COOKIE, token, max_age=members.auth.session_s, httponly=True, secure=ctx.cookie_secure, samesite="lax", path="/")

    @app.post("/api/m/register")
    def register(body: RegisterIn, request: Request, response: Response) -> dict:
        if not body.accept_terms:
            raise HTTPException(400, "acceptez les conditions et l'avertissement sur les risques")
        ip = ctx.client_ip(request)
        try:
            members.register(body.email, body.password, body.name, body.phone, ip=ip)
        except (MemberError, ValueError) as e:
            raise fail(e) from e
        res = members.auth.login(body.email.strip().lower(), body.password, None, ip, request.headers.get("user-agent", ""))
        if res is None:
            raise HTTPException(500, "compte créé : connectez-vous")
        token, s = res
        set_cookie(response, token)
        return me_payload(s, members.get(s.user_id))

    @app.post("/api/m/login")
    def login(body: MemberLoginIn, request: Request, response: Response) -> dict:
        ip = ctx.client_ip(request)
        email = body.email.strip().lower()
        if members.auth.locked(email, ip):
            raise HTTPException(429, "trop de tentatives : réessayez dans 15 minutes")
        res = members.auth.login(email, body.password, body.totp, ip, request.headers.get("user-agent", ""))
        if res is None:
            time.sleep(0.5)
            raise HTTPException(401, "e-mail ou mot de passe incorrect (ou code 2FA manquant)")
        token, s = res
        m = members.get(s.user_id)
        if m is None or m["status"] != "active":
            members.auth.logout(token)
            raise HTTPException(403, "compte suspendu : contactez l'équipe")
        set_cookie(response, token)
        return me_payload(s, m)

    @app.post("/api/m/logout")
    def logout(request: Request, response: Response, sm=Depends(member)) -> dict:
        members.auth.logout(request.cookies.get(MEMBER_COOKIE))
        response.delete_cookie(MEMBER_COOKIE, path="/")
        return {"ok": True}

    @app.get("/api/m/me")
    def me(sm=Depends(member)) -> dict:
        return me_payload(*sm)

    @app.get("/api/m/session")
    def session_state(request: Request) -> dict:
        """Like /api/m/me, but answers 200 when signed out (the site calls it on every page)."""
        sm = member_opt(request)
        return {"member": me_payload(*sm) if sm else None}

    # ---------------- payments ----------------
    @app.post("/api/m/checkout")
    def checkout(body: CheckoutIn, sm=Depends(member)) -> dict:
        try:
            return members.checkout(sm[1]["id"], body.offer, body.months)
        except MemberError as e:
            raise fail(e) from e

    @app.get("/api/m/payments")
    def my_payments(sm=Depends(member)) -> list[dict]:
        return members.payments_of(sm[1]["id"])

    @app.get("/api/m/payments/{payment_id}")
    def my_payment(payment_id: str, sm=Depends(member)) -> dict:
        p = members.payment(payment_id[:40])
        if p is None or p["member_id"] != sm[1]["id"]:
            raise HTTPException(404, "paiement introuvable")
        return {"payment": members.public_payment(members.refresh(p["id"])), "me": members.profile(members.get(sm[1]["id"]))}

    @app.post("/api/m/payments/{payment_id}/declare")
    def declare(payment_id: str, body: DeclareIn, sm=Depends(member)) -> dict:
        try:
            p = members.declare(sm[1]["id"], payment_id[:40], body.transaction_ref)
        except MemberError as e:
            raise fail(e) from e
        audit("payment_declared", member=sm[1]["email"], payment=p["id"], transaction_ref=p["transaction_ref"])
        return p

    @app.post("/api/webhooks/wave")
    async def wave_webhook(request: Request) -> dict:
        raw = await request.body()
        if len(raw) > 64_000:
            raise HTTPException(413, "trop volumineux")
        secret = settings.wave_webhook_secret
        sig_ok = verify_signature(secret, request.headers.get("wave-signature"), raw)
        bearer = request.headers.get("authorization", "")
        token_ok = bool(secret) and bearer.startswith("Bearer ") and hmac.compare_digest(bearer[7:].strip(), secret)
        if not (sig_ok or token_ok):
            raise HTTPException(401, "signature invalide")
        try:
            event = json.loads(raw)
        except ValueError as e:
            raise HTTPException(400, "JSON invalide") from e
        pid = members.on_webhook(event if isinstance(event, dict) else {})
        audit("wave_webhook", type=str(event.get("type", ""))[:60] if isinstance(event, dict) else "", payment=pid)
        return {"ok": True}

    # ---------------- academy ----------------
    @app.post("/api/m/progress")
    def progress(body: ProgressIn, sm=Depends(member)) -> dict:
        try:
            academy.save_progress(sm[1]["id"], body.part_id, body.position_s, body.completed, members.entitlements(sm[1]))
        except AcademyError as e:
            raise fail(e) from e
        return {"ok": True}

    # ---------------- copytrading ----------------
    @app.get("/api/m/copy")
    def my_copies(sm=Depends(member)) -> list[dict]:
        return copy.follows_of(sm[1]["id"])

    @app.post("/api/m/copy")
    def start_copy(body: FollowIn, sm=Depends(member)) -> dict:
        if not body.accept_risk:
            raise HTTPException(400, "lisez et acceptez l'avertissement sur les risques")
        try:
            f = copy.follow(sm[1]["id"], members.entitlements(sm[1]), body.leader_id, body.allocation, body.multiplier, body.max_drawdown_pct, body.mode)
        except CopyError as e:
            raise fail(e) from e
        audit("copy_follow", member=sm[1]["email"], follow=f["id"], leader=body.leader_id, mode=f["mode"])
        return f

    @app.get("/api/m/copy/{follow_id}")
    def copy_detail(follow_id: str, sm=Depends(member)) -> dict:
        try:
            return copy.follow_detail(sm[1]["id"], follow_id[:40])
        except CopyError as e:
            raise fail(e, 404) from e

    @app.post("/api/m/copy/{follow_id}/stop")
    def stop_copy(follow_id: str, sm=Depends(member)) -> dict:
        try:
            return copy.stop(sm[1]["id"], follow_id[:40])
        except CopyError as e:
            raise fail(e, 404) from e

    # ---------------- administration (console operators) ----------------
    op = ctx.operator

    @app.get("/api/admin/overview")
    def admin_overview(s: Session = Depends(op)) -> dict:
        return {
            **members.stats(), "wave": "api" if members.wave is not None else "manual", "copytrading": copy.mode,
            "bots": [{"id": b["id"], "name": b["name"], "strategy": b["strategy"]} for b in engine.store.list_bots()],
            "labels": {"access": ACCESS, "course_status": STATUSES, "providers": PROVIDERS, "leader_status": LEADER_STATUS},
            "offers": [o.public() for o in site.offers.values()],
        }

    @app.get("/api/admin/members")
    def admin_members(q: str = "", s: Session = Depends(op)) -> list[dict]:
        return members.list_members(q[:60])

    @app.post("/api/admin/members/{member_id}/grant")
    def admin_grant(member_id: int, body: GrantIn, s: Session = Depends(op)) -> dict:
        try:
            p = members.grant(member_id, body.offer, body.months, s.username, body.reason)
        except MemberError as e:
            raise fail(e) from e
        audit("member_grant", operator=s.username, member_id=member_id, offer=body.offer, months=body.months, reason=body.reason)
        return p

    @app.post("/api/admin/members/{member_id}/status")
    def admin_member_status(member_id: int, body: MemberStatusIn, s: Session = Depends(op)) -> dict:
        try:
            members.set_status(member_id, body.status)
        except MemberError as e:
            raise fail(e) from e
        audit("member_status", operator=s.username, member_id=member_id, status=body.status)
        return {"ok": True}

    @app.get("/api/admin/payments")
    def admin_payments(status: str = "", s: Session = Depends(op)) -> list[dict]:
        return members.list_payments(status[:20])

    @app.post("/api/admin/payments/{payment_id}/approve")
    def admin_approve(payment_id: str, s: Session = Depends(op)) -> dict:
        try:
            members.approve(payment_id[:40], s.username)
        except MemberError as e:
            raise fail(e) from e
        audit("payment_approved", operator=s.username, payment=payment_id)
        return members.public_payment(members.payment(payment_id))

    @app.post("/api/admin/payments/{payment_id}/reject")
    def admin_reject(payment_id: str, body: RejectIn, s: Session = Depends(op)) -> dict:
        try:
            members.reject(payment_id[:40], s.username, body.reason)
        except MemberError as e:
            raise fail(e) from e
        audit("payment_rejected", operator=s.username, payment=payment_id, reason=body.reason)
        return members.public_payment(members.payment(payment_id))

    @app.get("/api/admin/leads")
    def admin_leads(s: Session = Depends(op)) -> list[dict]:
        return members.list_leads()

    @app.get("/api/admin/courses")
    def admin_courses(s: Session = Depends(op)) -> list[dict]:
        return academy.list_admin()

    @app.get("/api/admin/courses/{course_id}")
    def admin_course(course_id: str, s: Session = Depends(op)) -> dict:
        try:
            return academy.course_admin(course_id[:40])
        except AcademyError as e:
            raise fail(e, 404) from e

    def academy_call(fn: Callable[..., dict], *args: Any, action: str, s: Session) -> dict:
        try:
            out = fn(*args)
        except AcademyError as e:
            raise fail(e) from e
        audit(action, operator=s.username, course=out.get("id") if isinstance(out, dict) else None)
        return out

    @app.post("/api/admin/courses")
    def admin_create_course(body: CourseIn, s: Session = Depends(op)) -> dict:
        return academy_call(academy.save_course, body.model_dump(), action="course_create", s=s)

    @app.put("/api/admin/courses/{course_id}")
    def admin_update_course(course_id: str, body: CourseIn, s: Session = Depends(op)) -> dict:
        return academy_call(academy.save_course, body.model_dump(), course_id[:40], action="course_update", s=s)

    @app.delete("/api/admin/courses/{course_id}")
    def admin_delete_course(course_id: str, s: Session = Depends(op)) -> dict:
        academy.delete_course(course_id[:40])
        audit("course_delete", operator=s.username, course=course_id)
        return {"ok": True}

    @app.post("/api/admin/courses/{course_id}/parts")
    def admin_add_part(course_id: str, body: PartIn, s: Session = Depends(op)) -> dict:
        return academy_call(academy.save_part, course_id[:40], body.model_dump(), action="course_part_add", s=s)

    @app.put("/api/admin/courses/{course_id}/parts/{part_id}")
    def admin_update_part(course_id: str, part_id: str, body: PartIn, s: Session = Depends(op)) -> dict:
        return academy_call(academy.save_part, course_id[:40], body.model_dump(), part_id[:40], action="course_part_update", s=s)

    @app.delete("/api/admin/courses/{course_id}/parts/{part_id}")
    def admin_delete_part(course_id: str, part_id: str, s: Session = Depends(op)) -> dict:
        return academy_call(academy.delete_part, course_id[:40], part_id[:40], action="course_part_delete", s=s)

    @app.post("/api/admin/courses/{course_id}/parts/{part_id}/move")
    def admin_move_part(course_id: str, part_id: str, body: MoveIn, s: Session = Depends(op)) -> dict:
        return academy_call(academy.move_part, course_id[:40], part_id[:40], body.delta, action="course_part_move", s=s)

    @app.get("/api/admin/leaders")
    def admin_leaders(s: Session = Depends(op)) -> list[dict]:
        return copy.leaders(include_drafts=True)

    @app.post("/api/admin/leaders")
    def admin_create_leader(body: LeaderIn, s: Session = Depends(op)) -> dict:
        try:
            out = copy.save_leader(body.model_dump())
        except CopyError as e:
            raise fail(e) from e
        audit("leader_create", operator=s.username, leader=out["id"], status=out["status"])
        return out

    @app.put("/api/admin/leaders/{leader_id}")
    def admin_update_leader(leader_id: str, body: LeaderIn, s: Session = Depends(op)) -> dict:
        try:
            out = copy.save_leader(body.model_dump(), leader_id[:40])
        except CopyError as e:
            raise fail(e) from e
        audit("leader_update", operator=s.username, leader=out["id"], status=out["status"])
        return out

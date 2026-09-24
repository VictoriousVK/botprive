"""FastAPI application: authenticated JSON API + static single-page dashboard.

Security model:
  * No default account. Users are created from the server console only
    (``python -m hedgefund.web create-user``).
  * Session cookie: HttpOnly, SameSite=Strict, Secure (unless HF_COOKIE_SECURE=0 for local
    http). CSRF token required in X-CSRF-Token on every state-changing request, plus an Origin
    check. No CORS: other sites cannot call the API with the user's cookie.
  * Sensitive actions (reset kill switch, change mode/capital, unlock real trading, security
    settings) re-verify the password and, if enabled, the 2FA code.
  * Strict security headers (CSP 'self' only, no framing, no referrer, HSTS behind HTTPS).
  * API docs are disabled; the server binds to 127.0.0.1 by default: expose it through a TLS
    reverse proxy or tunnel (docs/PLATFORM.md).
  * Every operator action is written to the append-only ledger.
"""

from __future__ import annotations

import hmac
import os
import threading
import time
from contextlib import asynccontextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from hedgefund.bots.engine import BotEngine, EngineError
from hedgefund import __version__
from hedgefund.bots.templates import DIRECTIONS, TEMPLATES, TIMEFRAMES, new_bot_id, validate_bot
from hedgefund.core.ledger import Kind
from hedgefund.mt5.catalog import CATEGORY_LABELS
from hedgefund.web.security import AuthService, Session, totp_uri

STATIC = Path(__file__).parent / "static"
COOKIE = "hf_session"
REAL_CONFIRMATION = "JE COMPRENDS LE RISQUE"


@dataclass(frozen=True)
class WebSettings:
    cookie_secure: bool = True
    hsts: bool = True
    trust_proxy: bool = False
    allow_real_trading: bool = False
    session_hours: int = 12
    public_host: str = ""  # e.g. "trading.example.com" when served behind a proxy/tunnel

    @classmethod
    def from_env(cls) -> "WebSettings":
        flag = lambda k, d: os.environ.get(k, d).strip().lower() in ("1", "true", "yes")  # noqa: E731
        secure = flag("HF_COOKIE_SECURE", "1")
        return cls(
            cookie_secure=secure,
            hsts=flag("HF_HSTS", "1" if secure else "0"),
            trust_proxy=flag("HF_TRUST_PROXY", "0"),
            allow_real_trading=flag("HF_ALLOW_REAL_TRADING", "0"),
            session_hours=int(os.environ.get("HF_SESSION_HOURS", "12")),
            public_host=os.environ.get("HF_PUBLIC_HOST", "").strip().lower(),
        )


# ---------------- request models ----------------
class LoginIn(BaseModel):
    username: str = Field(min_length=1, max_length=60)
    password: str = Field(min_length=1, max_length=200)
    totp: str | None = Field(default=None, max_length=10)


class ReauthIn(BaseModel):
    password: str = Field(min_length=1, max_length=200)
    totp: str | None = Field(default=None, max_length=10)


class PasswordIn(ReauthIn):
    new_password: str = Field(min_length=12, max_length=200)


class CodeIn(BaseModel):
    code: str = Field(min_length=6, max_length=10)


class BotIn(BaseModel):
    name: str = Field(min_length=1, max_length=60)
    strategy: Literal["trend", "mean_reversion", "pair", "ict_pro", "ict_v6"]
    symbols: list[str] = Field(min_length=1, max_length=2)
    timeframe: Literal["1m", "5m", "15m", "1h", "4h", "1d"]
    direction: Literal["both", "long", "short"] = "both"
    risk_per_trade_pct: float = Field(ge=0.05, le=1.5)
    max_position_pct: float = Field(ge=1, le=25)
    params: dict[str, float] = Field(default_factory=dict)


class StopIn(BaseModel):
    close_positions: bool = True


class KillIn(BaseModel):
    reason: str = Field(min_length=1, max_length=200)


class ResetKillIn(ReauthIn):
    reason: str = Field(min_length=3, max_length=200)


class ModeIn(ReauthIn):
    mode: Literal["simulation", "paper", "mt5"]


class CapitalIn(ReauthIn):
    capital: float = Field(ge=100, le=1e9)


class RealTradingIn(ReauthIn):
    enabled: bool
    confirmation: str = ""


def create_app(engine: BotEngine, auth: AuthService, settings: WebSettings | None = None, start_engine: bool = True) -> FastAPI:
    settings = settings or WebSettings.from_env()

    @asynccontextmanager
    async def lifespan(_app: FastAPI):
        if start_engine:
            engine.start()
        yield
        engine.shutdown()

    app = FastAPI(title="HedgeFund", docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)
    backtest_lock = threading.Lock()

    # ---------------- middleware ----------------
    @app.middleware("http")
    async def security_headers(request: Request, call_next):
        response = await call_next(request)
        h = response.headers
        h["Content-Security-Policy"] = "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'; object-src 'none'"
        h["X-Content-Type-Options"] = "nosniff"
        h["X-Frame-Options"] = "DENY"
        h["Referrer-Policy"] = "no-referrer"
        h["Permissions-Policy"] = "camera=(), microphone=(), geolocation=(), payment=()"
        h["Cross-Origin-Opener-Policy"] = "same-origin"
        if request.url.path.startswith("/api/"):
            h["Cache-Control"] = "no-store"
        elif request.url.path.startswith("/static/") or request.url.path == "/":
            h["Cache-Control"] = "no-cache"  # revalidate, so an update is picked up at once
        if settings.hsts:
            h["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        return response

    def client_ip(request: Request) -> str:
        if settings.trust_proxy:
            fwd = request.headers.get("x-forwarded-for") or request.headers.get("cf-connecting-ip")
            if fwd:
                return fwd.split(",")[0].strip()[:64]
        return request.client.host if request.client else "unknown"

    def session(request: Request) -> Session:
        s = auth.session(request.cookies.get(COOKIE))
        if s is None:
            raise HTTPException(401, "non authentifié")
        if request.method not in ("GET", "HEAD", "OPTIONS"):
            origin = request.headers.get("origin")
            if origin:
                allowed = {request.headers.get("host", "").lower()}
                if settings.public_host:
                    allowed.add(settings.public_host)
                if settings.trust_proxy and request.headers.get("x-forwarded-host"):
                    allowed.add(request.headers["x-forwarded-host"].lower())
                if origin.split("://", 1)[-1].lower() not in allowed:
                    raise HTTPException(403, "origine refusée")
            token = request.headers.get("x-csrf-token", "")
            if not token or not hmac.compare_digest(token, s.csrf):
                raise HTTPException(403, "jeton CSRF invalide")
        return s

    def reauth(s: Session, body: ReauthIn) -> None:
        if not auth.check_password(s.user_id, body.password):
            time.sleep(0.5)
            raise HTTPException(403, "mot de passe incorrect")
        if not auth.check_second_factor(s.user_id, body.totp):
            raise HTTPException(403, "code 2FA requis ou incorrect")

    def run(fn, *args, **kwargs) -> Any:
        try:
            return fn(*args, **kwargs)
        except EngineError as e:
            raise HTTPException(400, str(e)) from e

    @app.exception_handler(HTTPException)
    async def http_error(request: Request, exc: HTTPException):
        return JSONResponse({"detail": exc.detail}, status_code=exc.status_code, headers={"Cache-Control": "no-store"})

    # ---------------- static ----------------
    app.mount("/static", StaticFiles(directory=STATIC), name="static")

    @app.get("/", include_in_schema=False)
    def index() -> FileResponse:
        return FileResponse(STATIC / "index.html")

    @app.get("/api/health")
    def health() -> dict:
        return {"ok": True}

    # ---------------- auth ----------------
    @app.post("/api/auth/login")
    def login(body: LoginIn, request: Request, response: Response) -> dict:
        ip = client_ip(request)
        if auth.locked(body.username, ip):
            raise HTTPException(429, "trop de tentatives : réessayez dans 15 minutes")
        res = auth.login(body.username, body.password, body.totp, ip, request.headers.get("user-agent", ""))
        if res is None:
            time.sleep(0.5)
            engine.ledger.append(Kind.OPERATOR, {"action": "login_failed", "operator": body.username[:60], "ip": ip}, ts=int(time.time() * 1000))
            raise HTTPException(401, "identifiants incorrects (ou code 2FA manquant)")
        token, s = res
        response.set_cookie(COOKIE, token, max_age=settings.session_hours * 3600, httponly=True, secure=settings.cookie_secure, samesite="strict", path="/")
        engine.ledger.append(Kind.OPERATOR, {"action": "login", "operator": s.username, "ip": ip}, ts=int(time.time() * 1000))
        return {"username": s.username, "csrf": s.csrf, "totp_enabled": s.totp_enabled}

    @app.post("/api/auth/logout")
    def logout(request: Request, response: Response, s: Session = Depends(session)) -> dict:
        auth.logout(request.cookies.get(COOKIE))
        response.delete_cookie(COOKIE, path="/")
        return {"ok": True}

    @app.get("/api/auth/me")
    def me(s: Session = Depends(session)) -> dict:
        return {"username": s.username, "csrf": s.csrf, "totp_enabled": s.totp_enabled}

    @app.post("/api/auth/password")
    def change_password(body: PasswordIn, response: Response, s: Session = Depends(session)) -> dict:
        reauth(s, body)
        try:
            auth.set_password(s.user_id, body.new_password)
        except ValueError as e:
            raise HTTPException(400, str(e)) from e
        response.delete_cookie(COOKIE, path="/")
        engine.ledger.append(Kind.OPERATOR, {"action": "password_change", "operator": s.username}, ts=int(time.time() * 1000))
        return {"ok": True, "relogin": True}

    @app.post("/api/auth/totp/begin")
    def totp_begin(body: ReauthIn, s: Session = Depends(session)) -> dict:
        reauth(s, body)
        secret = auth.begin_totp(s.user_id)
        return {"secret": secret, "uri": totp_uri(secret, s.username)}

    @app.post("/api/auth/totp/enable")
    def totp_enable(body: CodeIn, s: Session = Depends(session)) -> dict:
        if not auth.enable_totp(s.user_id, body.code):
            raise HTTPException(400, "code incorrect")
        engine.ledger.append(Kind.OPERATOR, {"action": "totp_enabled", "operator": s.username}, ts=int(time.time() * 1000))
        return {"ok": True}

    # ---------------- read models ----------------
    @app.get("/api/overview")
    def overview(s: Session = Depends(session)) -> dict:
        return engine.snapshot()

    @app.get("/api/equity")
    def equity(days: int = 30, s: Session = Depends(session)) -> list[dict]:
        return engine.equity_series(max(1, min(days, 365)))

    @app.get("/api/fills")
    def fills(limit: int = 50, s: Session = Depends(session)) -> list[dict]:
        return engine.recent(Kind.FILL, max(1, min(limit, 500)))

    @app.get("/api/alerts")
    def alerts(limit: int = 50, s: Session = Depends(session)) -> list[dict]:
        return engine.recent(Kind.ALERT, max(1, min(limit, 500)))

    @app.get("/api/journal")
    def journal(limit: int = 100, s: Session = Depends(session)) -> list[dict]:
        limit = max(1, min(limit, 500))
        rows = [{"t": e.ts, "kind": e.kind, **e.payload} for e in engine.ledger.query(kind=[Kind.OPERATOR, Kind.RISK_EVENT, Kind.KILL_SWITCH, Kind.ALERT], newest_first=True, limit=limit)]
        return rows

    @app.get("/api/strategies")
    def strategies(s: Session = Depends(session)) -> dict:
        return {"strategies": [t.public() for t in TEMPLATES.values()], "timeframes": TIMEFRAMES, "directions": DIRECTIONS, "categories": CATEGORY_LABELS, "version": __version__}

    @app.get("/api/symbols")
    def symbols(q: str = "", category: str = "", s: Session = Depends(session)) -> list[dict]:
        return run(engine.symbols, q[:40], category[:20])

    @app.get("/api/symbols/{name}")
    def symbol(name: str, s: Session = Depends(session)) -> dict:
        if name not in engine.feed.specs():
            raise HTTPException(404, "actif inconnu")
        return run(engine.symbol_detail, name)

    # ---------------- bots ----------------
    def _bot_from(body: BotIn, bot_id: str, existing: dict | None = None) -> dict:
        bot = {
            **(existing or {}),
            "id": bot_id,
            "name": body.name.strip(),
            "strategy": body.strategy,
            "symbols": [x.strip() for x in body.symbols],
            "timeframe": body.timeframe,
            "direction": body.direction,
            "risk_per_trade_pct": body.risk_per_trade_pct,
            "max_position_pct": body.max_position_pct,
            "params": dict(body.params),
            "status": (existing or {}).get("status", "stopped"),
            "created_at": (existing or {}).get("created_at", int(time.time() * 1000)),
            "updated_at": int(time.time() * 1000),
            "last_bar_ts": None,
        }
        problems = validate_bot(bot, engine.feed.specs())
        if problems:
            raise HTTPException(400, "; ".join(problems))
        return bot

    @app.get("/api/bots")
    def list_bots(s: Session = Depends(session)) -> list[dict]:
        return engine.snapshot()["bots"]

    @app.post("/api/bots")
    def create_bot(body: BotIn, s: Session = Depends(session)) -> dict:
        if len(engine.store.list_bots()) >= 50:
            raise HTTPException(400, "50 bots maximum")
        bot = _bot_from(body, new_bot_id())
        engine.store.save_bot(bot)
        engine.ledger.append(Kind.OPERATOR, {"action": "bot_create", "operator": s.username, "bot": bot}, ts=int(time.time() * 1000))
        return bot

    def _existing(bot_id: str) -> dict:
        bot = engine.store.get_bot(bot_id)
        if bot is None:
            raise HTTPException(404, "bot introuvable")
        return bot

    @app.put("/api/bots/{bot_id}")
    def update_bot(bot_id: str, body: BotIn, s: Session = Depends(session)) -> dict:
        existing = _existing(bot_id)
        if bot_id in engine.runtimes:
            raise HTTPException(400, "arrêtez le bot avant de le modifier")
        if engine.stack.portfolio.book_positions(bot_id):
            raise HTTPException(400, "le bot a encore des positions : fermez-les avant de le modifier")
        bot = _bot_from(body, bot_id, existing)
        engine.store.save_bot(bot)
        engine.ledger.append(Kind.OPERATOR, {"action": "bot_update", "operator": s.username, "bot": bot}, ts=int(time.time() * 1000))
        return bot

    @app.delete("/api/bots/{bot_id}")
    def delete_bot(bot_id: str, s: Session = Depends(session)) -> dict:
        _existing(bot_id)
        if bot_id in engine.runtimes or engine.stack.portfolio.book_positions(bot_id):
            raise HTTPException(400, "arrêtez le bot et fermez ses positions avant de le supprimer")
        engine.store.delete_bot(bot_id)
        engine.ledger.append(Kind.OPERATOR, {"action": "bot_delete", "operator": s.username, "bot_id": bot_id}, ts=int(time.time() * 1000))
        return {"ok": True}

    @app.post("/api/bots/{bot_id}/start")
    def start_bot(bot_id: str, s: Session = Depends(session)) -> dict:
        _existing(bot_id)
        return run(engine.start_bot, bot_id, s.username)

    @app.post("/api/bots/{bot_id}/stop")
    def stop_bot(bot_id: str, body: StopIn, s: Session = Depends(session)) -> dict:
        _existing(bot_id)
        return run(engine.stop_bot, bot_id, s.username, body.close_positions)

    def _backtest(bot: dict) -> dict:
        if not backtest_lock.acquire(blocking=False):
            raise HTTPException(429, "un backtest est déjà en cours")
        try:
            return run(engine.backtest, bot)
        finally:
            backtest_lock.release()

    @app.post("/api/backtest")
    def backtest(body: BotIn, s: Session = Depends(session)) -> dict:
        return _backtest(_bot_from(body, "bot_00000000"))

    @app.post("/api/bots/{bot_id}/backtest")
    def backtest_saved(bot_id: str, s: Session = Depends(session)) -> dict:
        return _backtest(_existing(bot_id))

    # ---------------- engine controls ----------------
    @app.post("/api/engine/kill")
    def kill(body: KillIn, s: Session = Depends(session)) -> dict:
        run(engine.kill, s.username, body.reason)
        return {"ok": True}

    @app.post("/api/engine/reset-kill")
    def reset_kill(body: ResetKillIn, s: Session = Depends(session)) -> dict:
        reauth(s, body)
        run(engine.reset_kill, s.username, body.reason)
        return {"ok": True}

    @app.post("/api/engine/mode")
    def mode(body: ModeIn, s: Session = Depends(session)) -> dict:
        reauth(s, body)
        run(engine.set_mode, body.mode, s.username)
        return {"ok": True, "mode": engine.mode}

    @app.post("/api/engine/capital")
    def capital(body: CapitalIn, s: Session = Depends(session)) -> dict:
        reauth(s, body)
        run(engine.set_capital, body.capital, s.username)
        return {"ok": True}

    @app.post("/api/engine/real-trading")
    def real_trading(body: RealTradingIn, s: Session = Depends(session)) -> dict:
        reauth(s, body)
        if body.enabled and body.confirmation.strip().upper() != REAL_CONFIRMATION:
            raise HTTPException(400, f"tapez exactement : {REAL_CONFIRMATION}")
        run(engine.set_real_trading, body.enabled, s.username)
        return {"ok": True, "unlocked": engine.real_trading_enabled()}

    return app

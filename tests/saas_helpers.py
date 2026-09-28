"""Test wiring for the SaaS: the platform app with an in-memory SaaS database, the simulated
feed on a fixed clock, and a scripted (or absent) model."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from fastapi.testclient import TestClient

from hedgefund.bots.engine import BotEngine
from hedgefund.bots.simfeed import SimulatedFeed
from hedgefund.bots.store import PlatformStore
from hedgefund.config import load_config
from hedgefund.core.clock import SimClock
from hedgefund.members.site import MemberSettings, load_site
from hedgefund.saas.db import Database
from hedgefund.saas.llm import AnthropicLLM, NullLLM, ScriptedClient
from hedgefund.saas.modules import install_all
from hedgefund.saas.service import MarketData, SaaS, SaaSSettings
from hedgefund.web.app import WebSettings, create_app
from hedgefund.web.security import AuthService

PW = "motdepasse-solide-123"
NOW = 1_791_900_000_000  # 2026-10-13 ~ 14:40 UTC (a Tuesday)


def make_saas(feed: Any = None, clock: SimClock | None = None, turns: list[Any] | None = None, db_url: str = "sqlite://") -> SaaS:
    llm = AnthropicLLM(ScriptedClient(turns)) if turns is not None else NullLLM()
    saas = SaaS(Database(db_url), SaaSSettings(worker_threads=0, jobs_secret="jobs-secret-test"), llm=llm,
                market=MarketData(feed, clock.now_ms) if feed is not None else None)
    install_all(saas)
    return saas


def make_app(tmp_path: Path, turns: list[Any] | None = None, now: int = NOW, grant: str | None = None, member_settings: MemberSettings | None = None):
    clock = SimClock(now)
    feed = SimulatedFeed(clock)
    eng = BotEngine(load_config(), PlatformStore(Path(tmp_path) / "p.db"), feed, clock=clock, data_dir=Path(tmp_path))
    auth = AuthService(eng.store)
    if auth.user_count() == 0:
        auth.create_user("vic", PW)
    saas = make_saas(feed, clock, turns)
    app = create_app(eng, auth, WebSettings(cookie_secure=False, hsts=False), start_engine=False, site=load_site(),
                     member_settings=member_settings or MemberSettings(), site_dir=Path(tmp_path) / "nosite", saas=saas)
    return TestClient(app), eng, saas, clock


def register(c: TestClient, email: str = "awa@example.com") -> dict[str, str]:
    r = c.post("/api/m/register", json={"email": email, "password": PW, "name": "Awa Ndiaye", "phone": "", "accept_terms": True})
    assert r.status_code == 200, r.text
    return {"X-CSRF-Token": r.json()["csrf"]}


def operator(c: TestClient) -> dict[str, str]:
    r = c.post("/api/auth/login", json={"username": "vic", "password": PW})
    assert r.status_code == 200, r.text
    return {"X-CSRF-Token": r.json()["csrf"]}


def grant(c_op: TestClient, oh: dict[str, str], member_id: int, offer: str) -> None:
    r = c_op.post(f"/api/admin/members/{member_id}/grant", json={"offer": offer, "months": 1, "reason": "test"}, headers=oh)
    assert r.status_code == 200, r.text

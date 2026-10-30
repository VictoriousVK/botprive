# ruff: noqa: F811 - the site_app fixture is imported from test_members
"""Sign-up protection: e-mail confirmation, honeypot, disposable domains, Turnstile, password reset."""

import sqlite3
import time

from fastapi.testclient import TestClient

from hedgefund.bots.store import PlatformStore
from hedgefund.members.antibot import is_blocked_domain
from hedgefund.members.mailer import LogMailer
from hedgefund.members.service import Members, migrate
from hedgefund.members.site import MemberSettings
from hedgefund.web.app import WebSettings, create_app
from hedgefund.web.security import AuthService
from tests.test_members import PW, _engine, _site, last_link, operator, register, site_app  # noqa: F401 - fixture

BODY = {"email": "fatou@example.com", "password": PW, "name": "Fatou Sow", "accept_terms": True}


def test_account_cannot_sign_in_before_confirmation(site_app):
    c, _, _ = site_app()
    r = c.post("/api/m/register", json=BODY)
    assert r.status_code == 200 and r.json()["pending"] and "set-cookie" not in r.headers
    assert c.get("/api/m/me").status_code == 401
    r = c.post("/api/m/login", json={"email": BODY["email"], "password": PW})
    assert r.status_code == 403 and "non confirmé" in r.json()["detail"]
    assert "lf_session" not in r.headers.get("set-cookie", "") and c.get("/api/m/me").status_code == 401
    mail = c.app.state.mailer.outbox[-1]
    assert mail.to == BODY["email"] and "Fatou" in mail.text and "Fatou" in mail.html
    token = last_link(c)
    r = c.post("/api/m/verify", json={"token": token})
    assert r.status_code == 200 and r.json()["email_verified"] and r.json()["csrf"]
    assert c.get("/api/m/me").status_code == 200
    # single use
    c.cookies.clear()
    assert c.post("/api/m/verify", json={"token": token}).status_code == 400
    assert c.post("/api/m/login", json={"email": BODY["email"], "password": PW}).status_code == 200


def test_resend_is_silent_and_rate_limited(site_app):
    c, _, _ = site_app()
    c.post("/api/m/register", json=BODY)
    first = last_link(c)
    assert c.post("/api/m/verify/resend", json={"email": "inconnu@example.com"}).json() == {"ok": True}  # no enumeration
    assert c.post("/api/m/verify/resend", json={"email": BODY["email"]}).status_code == 200
    second = last_link(c)
    assert first != second
    assert c.post("/api/m/verify", json={"token": first}).status_code == 400  # only the newest link works
    n = len(c.app.state.mailer.outbox)
    for _ in range(5):
        c.post("/api/m/verify/resend", json={"email": BODY["email"]})
    assert len(c.app.state.mailer.outbox) <= n + 2  # 4 mails per address per hour, at most
    assert c.post("/api/m/verify", json={"token": last_link(c)}).status_code == 200


def test_honeypot_creates_nothing(site_app):
    c, eng, _ = site_app()
    r = c.post("/api/m/register", json={**BODY, "website": "http://spam.example"})
    assert r.status_code == 200 and r.json()["pending"]  # same answer as a real sign-up
    assert eng.store.execute("SELECT COUNT(*) AS n FROM members")[0]["n"] == 0
    assert c.app.state.mailer.outbox == []


def test_disposable_domains_refused(site_app):
    assert is_blocked_domain("x@yopmail.com") and is_blocked_domain("x@mail.yopmail.fr") and is_blocked_domain("x@MAILINATOR.com")
    assert not is_blocked_domain("x@gmail.com") and not is_blocked_domain("x@orange.sn")
    assert is_blocked_domain("x@spam.example", frozenset({"spam.example"}))
    c, _, _ = site_app()
    r = c.post("/api/m/register", json={**BODY, "email": "bot@yopmail.com"})
    assert r.status_code == 400 and "jetables" in r.json()["detail"]


def test_pending_signup_can_be_replaced_but_confirmed_one_cannot(site_app):
    c, eng, _ = site_app()
    c.post("/api/m/register", json={**BODY, "name": "Faute De Frappe"})
    c.post("/api/m/register", json=BODY)  # same address, never confirmed: replaces it
    assert eng.store.execute("SELECT name FROM members")[0]["name"] == "Fatou Sow"
    c.post("/api/m/verify", json={"token": last_link(c)})
    r = c.post("/api/m/register", json=BODY)
    assert r.status_code == 400 and "existe déjà" in r.json()["detail"]


def test_password_reset(site_app):
    c, _, _ = site_app()
    register(c, email="awa@example.com")
    c.cookies.clear()
    assert c.post("/api/m/password/forgot", json={"email": "personne@example.com"}).json() == {"ok": True}
    n = len(c.app.state.mailer.outbox)
    c.post("/api/m/password/forgot", json={"email": "AWA@example.com"})
    assert len(c.app.state.mailer.outbox) == n + 1
    token = last_link(c, "/compte/mot-de-passe/")
    assert c.post("/api/m/password/reset", json={"token": token, "password": "court"}).status_code == 400
    r = c.post("/api/m/password/reset", json={"token": token, "password": "un-nouveau-mot-de-passe"})
    assert r.status_code == 200 and r.json()["member"]["email"] == "awa@example.com"
    assert c.post("/api/m/password/reset", json={"token": token, "password": "encore-un-autre-mdp"}).status_code == 400  # single use
    c.cookies.clear()
    assert c.post("/api/m/login", json={"email": "awa@example.com", "password": PW}).status_code == 401
    assert c.post("/api/m/login", json={"email": "awa@example.com", "password": "un-nouveau-mot-de-passe"}).status_code == 200


def test_links_never_use_the_host_header(tmp_path):
    eng = _engine(tmp_path)
    auth = AuthService(eng.store)
    app = create_app(eng, auth, WebSettings(cookie_secure=False, hsts=False), start_engine=False, site=_site(tmp_path), member_settings=MemberSettings(), site_dir=tmp_path / "nosite", mailer=LogMailer())
    c = TestClient(app, base_url="http://evil.example")
    r = c.post("/api/m/register", json=BODY)
    assert r.status_code == 503 and "LF_PUBLIC_URL" in r.json()["detail"]
    assert app.state.mailer.outbox == []
    c = TestClient(app, base_url="http://127.0.0.1:8000")  # local use works without configuration
    c.post("/api/m/register", json={**BODY, "email": "local@example.com"})
    assert "http://127.0.0.1:8000/compte/verifier/?jeton=" in app.state.mailer.outbox[-1].text


def test_turnstile_required_when_configured(tmp_path):
    eng = _engine(tmp_path)
    ms = MemberSettings(public_url="https://lf.test", turnstile_site_key="0x4AAA", turnstile_secret="0x4BBB")
    app = create_app(eng, AuthService(eng.store), WebSettings(cookie_secure=False, hsts=False), start_engine=False, site=_site(tmp_path), member_settings=ms, site_dir=tmp_path / "nosite", mailer=LogMailer())
    seen = []
    from hedgefund.members import api as api_mod  # the Cloudflare call is swapped for a fake one

    c = TestClient(app)
    assert c.get("/api/site").json()["turnstile_site_key"] == "0x4AAA"
    orig = api_mod.verify_turnstile
    api_mod.verify_turnstile = lambda secret, token, ip: seen.append(token) or token == "ok"
    try:
        assert c.post("/api/m/register", json=BODY).status_code == 400
        assert c.post("/api/m/register", json={**BODY, "captcha": "faux"}).status_code == 400
        assert c.post("/api/m/register", json={**BODY, "captcha": "ok"}).status_code == 200
    finally:
        api_mod.verify_turnstile = orig
    assert seen == [None, "faux", "ok"]


def test_admin_can_confirm_and_counts(site_app):
    c, _, _ = site_app()
    c.post("/api/m/register", json=BODY)
    H = operator(c)
    ov = c.get("/api/admin/overview").json()
    assert ov["members"] == 0 and ov["unverified"] == 1
    m = c.get("/api/admin/members").json()[0]
    assert m["email_verified"] is False and m["entitlements"] == []
    assert c.post(f"/api/admin/members/{m['id']}/verify-email", headers=H).status_code == 200
    assert c.get("/api/admin/members").json()[0]["email_verified"] is True
    c.cookies.clear()
    assert c.post("/api/m/login", json={"email": BODY["email"], "password": PW}).status_code == 200


def test_migration_keeps_existing_members_confirmed_and_purges_old_pending(tmp_path):
    db = tmp_path / "old.db"
    old = sqlite3.connect(db)
    old.executescript(
        "CREATE TABLE members (id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT UNIQUE NOT NULL, name TEXT NOT NULL, phone TEXT, password_hash TEXT NOT NULL,"
        " totp_secret TEXT, totp_enabled INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'active', terms_version TEXT NOT NULL, created_at INTEGER NOT NULL);"
        "INSERT INTO members (email, name, password_hash, terms_version, created_at) VALUES ('ancien@example.com', 'Ancien Membre', 'x', '2026-10', 1700000000);"
    )
    old.commit()
    old.close()
    store = PlatformStore(db)
    migrate(store)
    assert store.execute("SELECT email_verified_at FROM members")[0]["email_verified_at"] == 1700000000
    migrate(store)  # idempotent
    now = [time.time()]
    m = Members(store, _site(tmp_path), MemberSettings(), now=lambda: now[0])
    mid = m.register("neuf@example.com", PW, "Nouveau Membre")
    assert not m.is_verified(m.get(mid))
    now[0] += 8 * 86_400
    assert m.purge_unverified() == 1 and m.get(mid) is None
    assert store.execute("SELECT COUNT(*) AS n FROM members")[0]["n"] == 1


def test_verification_can_be_switched_off(tmp_path):
    eng = _engine(tmp_path)
    ms = MemberSettings(public_url="https://lf.test", email_verification=False)
    app = create_app(eng, AuthService(eng.store), WebSettings(cookie_secure=False, hsts=False), start_engine=False, site=_site(tmp_path), member_settings=ms, site_dir=tmp_path / "nosite", mailer=LogMailer())
    c = TestClient(app)
    r = c.post("/api/m/register", json=BODY)
    assert r.status_code == 200 and r.json()["email"] == BODY["email"] and r.json()["csrf"]

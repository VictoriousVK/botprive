"""Public site: members, Wave payments, academy, copytrading, site pages."""

import json
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from hedgefund.bots.engine import BotEngine
from hedgefund.bots.simfeed import SimulatedFeed
from hedgefund.bots.store import PlatformStore
from hedgefund.bots.templates import new_bot_id
from hedgefund.config import load_config
from hedgefund.core.clock import SimClock
from hedgefund.members.academy import AcademyError, parse_chapters, parse_video, player
from hedgefund.members.site import MemberSettings, load_site
from hedgefund.members.wave import sign, verify_signature
from hedgefund.web.app import SitePages, WebSettings, create_app
from hedgefund.web.security import AuthService

PW = "motdepasse-solide-123"


class FakeWave:
    """Stands in for the Wave API: sessions are created open, and paid on demand."""

    def __init__(self):
        self.sessions: dict[str, dict] = {}

    def create_checkout(self, amount_xof, client_reference, success_url, error_url, idempotency_key):
        assert success_url.startswith("https://") and error_url.startswith("https://")
        sid = f"cos-{len(self.sessions) + 1}"
        self.sessions[sid] = {"id": sid, "amount": str(amount_xof), "currency": "XOF", "client_reference": client_reference, "checkout_status": "open", "payment_status": "processing", "wave_launch_url": f"https://pay.wave.com/c/{sid}"}
        return dict(self.sessions[sid])

    def get_checkout(self, sid):
        return dict(self.sessions[sid])

    def pay(self, sid, **override):
        self.sessions[sid].update(checkout_status="complete", payment_status="succeeded", transaction_id=f"T_{sid}", **override)


def _engine(tmp):
    return BotEngine(load_config(), PlatformStore(Path(tmp) / "p.db"), SimulatedFeed(), clock=SimClock(1_790_000_000_000), data_dir=Path(tmp))


def _site(tmp, manual=True):
    raw = (Path(__file__).resolve().parent.parent / "config" / "site.yaml").read_text(encoding="utf-8")
    if manual:
        raw = raw.replace('manual_number: ""', 'manual_number: "+221 77 000 00 00"')
    p = Path(tmp) / "site.yaml"
    p.write_text(raw, encoding="utf-8")
    return load_site(p)


@pytest.fixture
def site_app(tmp_path):
    def make(manual=True, wave=False, copytrading="demo", site_dir=None):
        eng = _engine(tmp_path)
        auth = AuthService(eng.store)
        if auth.user_count() == 0:
            auth.create_user("vic", PW)
        ms = MemberSettings(public_url="https://lf.test" if wave else "", wave_api_key="k" if wave else "", wave_webhook_secret="whsec", copytrading=copytrading, media_hosts=("media.lf.test",))
        app = create_app(eng, auth, WebSettings(cookie_secure=False, hsts=False), start_engine=False, site=_site(tmp_path, manual), member_settings=ms, site_dir=site_dir or tmp_path / "nosite")
        fake = None
        if wave:
            fake = app.state.members.wave = FakeWave()
        return TestClient(app), eng, fake
    return make


def register(c, email="awa@example.com", **kw):
    body = {"email": email, "password": PW, "name": "Awa Ndiaye", "phone": "+221 77 123 45 67", "accept_terms": True, **kw}
    r = c.post("/api/m/register", json=body)
    return r, ({"X-CSRF-Token": r.json()["csrf"]} if r.status_code == 200 else {})


def operator(c):
    r = c.post("/api/auth/login", json={"username": "vic", "password": PW})
    return {"X-CSRF-Token": r.json()["csrf"]}


# ---------------- accounts ----------------
def test_register_login_and_isolation_from_console(site_app):
    c, _, _ = site_app()
    assert c.post("/api/m/register", json={"email": "a@b.co", "password": PW, "name": "A B", "accept_terms": False}).status_code == 400
    assert register(c, email="pas-un-email")[0].status_code == 400
    assert register(c, password="court")[0].status_code == 400
    r, H = register(c)
    assert r.status_code == 200 and r.json()["offer"] == "decouverte" and "copy_demo" in r.json()["entitlements"]
    assert "samesite=lax" in r.headers["set-cookie"].lower() and "httponly" in r.headers["set-cookie"].lower()
    assert register(c, email="AWA@example.com")[0].status_code == 400  # e-mails are case-insensitive
    assert c.get("/api/overview").status_code == 401  # a member session never opens the console
    assert c.get("/api/admin/payments").status_code == 401
    assert c.post("/api/m/checkout", json={"offer": "pro", "months": 1}).status_code == 403  # CSRF
    assert c.post("/api/m/checkout", json={"offer": "pro", "months": 1}, headers={**H, "Origin": "https://evil.example"}).status_code == 403
    c.cookies.clear()
    assert c.get("/api/m/me").status_code == 401
    assert c.post("/api/m/login", json={"email": "awa@example.com", "password": "faux"}).status_code == 401
    r = c.post("/api/m/login", json={"email": " Awa@Example.com ", "password": PW})
    assert r.status_code == 200 and c.get("/api/m/me").json()["email"] == "awa@example.com"


def test_registration_rate_limit(site_app):
    c, _, _ = site_app()
    for i in range(5):
        assert register(c, email=f"m{i}@example.com")[0].status_code == 200
    assert "trop d'inscriptions" in register(c, email="m9@example.com")[0].json()["detail"]


# ---------------- Wave: manual transfer ----------------
def test_manual_wave_transfer_validated_by_admin(site_app):
    c, _, _ = site_app(manual=True)
    _, H = register(c)
    assert c.get("/api/site").json()["wave"] == "manual"
    assert c.post("/api/m/checkout", json={"offer": "decouverte", "months": 1}, headers=H).status_code == 400
    assert c.post("/api/m/checkout", json={"offer": "pro", "months": 2}, headers=H).status_code == 400  # duration not offered
    r = c.post("/api/m/checkout", json={"offer": "pro", "months": 12}, headers=H).json()
    assert r["manual"]["amount"] == 450_000 and r["manual"]["number"] == "+221 77 000 00 00"  # 12 months billed 10
    pid = r["payment"]["id"]
    assert c.post(f"/api/m/payments/{pid}/declare", json={"transaction_ref": "bad ref!"}, headers=H).status_code == 400
    assert c.post(f"/api/m/payments/{pid}/declare", json={"transaction_ref": "TXN-000123"}, headers=H).json()["status"] == "declared"
    assert c.get("/api/m/me").json()["offer"] == "decouverte"  # nothing granted before the admin checks
    member_cookie = c.cookies.get("lf_session")

    # a second member cannot reuse the same Wave transaction
    c2 = TestClient(c.app)
    _, H2 = register(c2, email="moussa@example.com")
    pid2 = c2.post("/api/m/checkout", json={"offer": "trader", "months": 1}, headers=H2).json()["payment"]["id"]
    assert "déjà" in c2.post(f"/api/m/payments/{pid2}/declare", json={"transaction_ref": "TXN-000123"}, headers=H2).json()["detail"]

    op = TestClient(c.app)
    OH = operator(op)
    assert [p["id"] for p in op.get("/api/admin/payments?status=declared").json()] == [pid]
    assert op.post(f"/api/admin/payments/{pid}/approve", headers=OH).json()["status"] == "succeeded"
    assert op.post(f"/api/admin/payments/{pid}/approve", headers=OH).status_code == 400  # credited once only
    c.cookies.set("lf_session", member_cookie)
    me = c.get("/api/m/me").json()
    assert me["offer"] == "pro" and "robots" in me["entitlements"]
    assert me["offer_expires_at"] == pytest.approx(time.time() + 360 * 86_400, abs=60)
    assert op.post(f"/api/admin/payments/{pid2}/reject", json={"reason": "introuvable"}, headers=OH).json()["status"] == "rejected"


def test_checkout_refused_when_wave_not_configured(site_app):
    c, _, _ = site_app(manual=False)
    _, H = register(c)
    assert c.get("/api/site").json()["wave"] == "off"
    assert "pas encore configuré" in c.post("/api/m/checkout", json={"offer": "pro", "months": 1}, headers=H).json()["detail"]


# ---------------- Wave: checkout API ----------------
def test_wave_checkout_credited_only_after_api_confirmation(site_app):
    c, _, wave = site_app(wave=True)
    _, H = register(c)
    r = c.post("/api/m/checkout", json={"offer": "trader", "months": 3}, headers=H).json()
    assert r["launch_url"].startswith("https://pay.wave.com/") and r["payment"]["amount"] == 45_000
    pid = r["payment"]["id"]
    sid = next(iter(wave.sessions))
    assert wave.sessions[sid]["client_reference"] == pid
    assert c.get(f"/api/m/payments/{pid}").json()["payment"]["status"] == "pending"  # returning from Wave is not proof
    wave.pay(sid)
    body = c.get(f"/api/m/payments/{pid}").json()
    assert body["payment"]["status"] == "succeeded" and body["me"]["offer"] == "trader" and body["payment"]["transaction_ref"] == "T_cos-1"
    exp = body["me"]["offer_expires_at"]
    c.get(f"/api/m/payments/{pid}")
    assert c.get("/api/m/me").json()["offer_expires_at"] == exp  # idempotent

    # renewal of the same offer extends from the current expiry
    pid2 = c.post("/api/m/checkout", json={"offer": "trader", "months": 1}, headers=H).json()["payment"]["id"]
    wave.pay("cos-2")
    c.get(f"/api/m/payments/{pid2}")
    assert c.get("/api/m/me").json()["offer_expires_at"] == exp + 30 * 86_400


def test_wave_session_with_wrong_amount_is_not_credited(site_app):
    c, _, wave = site_app(wave=True)
    _, H = register(c)
    pid = c.post("/api/m/checkout", json={"offer": "elite", "months": 1}, headers=H).json()["payment"]["id"]
    wave.pay("cos-1", amount="100")
    assert c.get(f"/api/m/payments/{pid}").json()["payment"]["status"] == "failed"
    assert c.get("/api/m/me").json()["offer"] == "decouverte"


def test_wave_webhook_signature_and_refresh(site_app):
    c, _, wave = site_app(wave=True)
    _, H = register(c)
    pid = c.post("/api/m/checkout", json={"offer": "pro", "months": 1}, headers=H).json()["payment"]["id"]
    wave.pay("cos-1")
    raw = json.dumps({"id": "AE_1", "type": "checkout.session.completed", "data": {"id": "cos-1"}}).encode()
    anon = TestClient(c.app)
    assert anon.post("/api/webhooks/wave", content=raw, headers={"Wave-Signature": sign("autre", raw)}).status_code == 401
    assert anon.post("/api/webhooks/wave", content=raw, headers={"Wave-Signature": sign("whsec", raw, ts=int(time.time()) - 3600)}).status_code == 401
    assert anon.post("/api/webhooks/wave", content=raw, headers={"Wave-Signature": sign("whsec", raw)}).status_code == 200
    assert c.get("/api/m/me").json()["offer"] == "pro"
    assert c.get("/api/m/payments").json()[0]["id"] == pid


def test_signature_helper():
    raw = b'{"a":1}'
    h = sign("s3cret", raw, ts=1_700_000_000)
    assert verify_signature("s3cret", h, raw, now=1_700_000_100)
    assert not verify_signature("s3cret", h, raw + b" ", now=1_700_000_100)
    assert not verify_signature("s3cret", h, raw, now=1_700_001_000)
    assert not verify_signature("", h, raw) and not verify_signature("s3cret", "t=abc,v1=00", raw)


def test_subscription_expires(site_app):
    c, eng, _ = site_app()
    _, H = register(c)
    op = TestClient(c.app)
    OH = operator(op)
    mid = op.get("/api/admin/members").json()[0]["id"]
    assert op.post(f"/api/admin/members/{mid}/grant", json={"offer": "elite", "months": 1, "reason": "bêta-testeur"}, headers=OH).status_code == 200
    assert c.get("/api/m/me").json()["offer"] == "elite"
    eng.store.execute("UPDATE members SET offer_expires_at = ? WHERE id = ?", (int(time.time()) - 1, mid))
    assert c.get("/api/m/me").json()["offer"] == "decouverte"
    assert op.post(f"/api/admin/members/{mid}/status", json={"status": "suspended"}, headers=OH).status_code == 200
    assert c.get("/api/m/me").status_code == 401


# ---------------- academy ----------------
@pytest.mark.parametrize("link,provider,ref", [
    ("https://iframe.mediadelivery.net/embed/12345/0b7c2c5e-6a4b-4f6f-9c1e-1234567890ab", "bunny", "12345/0b7c2c5e-6a4b-4f6f-9c1e-1234567890ab"),
    ("https://customer-abcd1234.cloudflarestream.com/0123456789abcdef0123456789abcdef/iframe", "cloudflare", "customer-abcd1234/0123456789abcdef0123456789abcdef"),
    ("https://player.mux.com/Xy12AbCdEf34GhIj", "mux", "Xy12AbCdEf34GhIj"),
    ("https://vimeo.com/123456789/abcdef1234", "vimeo", "123456789/abcdef1234"),
    ("https://player.vimeo.com/video/123456789?h=abcdef12", "vimeo", "123456789/abcdef12"),
    ("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=3", "youtube", "dQw4w9WgXcQ"),
    ("https://youtu.be/dQw4w9WgXcQ", "youtube", "dQw4w9WgXcQ"),
    ("https://media.lf.test/cours/partie-1.mp4", "file", "https://media.lf.test/cours/partie-1.mp4"),
])
def test_parse_video_links(link, provider, ref):
    assert parse_video(link, media_hosts=("media.lf.test",)) == (provider, ref)
    p = player(provider, ref, ("media.lf.test",))
    assert p and p["src"].startswith("https://")


@pytest.mark.parametrize("link", ["http://youtu.be/dQw4w9WgXcQ", "https://evil.example/x.mp4", "https://media.lf.test/x.avi", "https://youtu.be/<script>", "javascript:alert(1)", ""])
def test_parse_video_rejects(link):
    with pytest.raises(AcademyError):
        parse_video(link, media_hosts=("media.lf.test",))


def test_chapters():
    assert parse_chapters("0:00 Introduction\n12:30 Le Silver Bullet\n1:02:03 Conclusion", 4000) == [{"t": 0, "title": "Introduction"}, {"t": 750, "title": "Le Silver Bullet"}, {"t": 3723, "title": "Conclusion"}]
    with pytest.raises(AcademyError):
        parse_chapters("12h Titre", 4000)
    with pytest.raises(AcademyError):
        parse_chapters("50:00 Trop loin", 2400)


def test_course_admin_access_and_progress(site_app):
    c, _, _ = site_app()
    op = TestClient(c.app)
    OH = operator(op)
    assert {x["slug"] for x in c.get("/api/site/courses").json()} >= {"debutant", "gestion-du-risque", "methode-ict"}  # planned tracks
    course = op.post("/api/admin/courses", json={"slug": "methode-ict", "title": "Méthode ICT", "access": "academy_member", "status": "published"}, headers=OH).json()
    cid = course["id"]
    assert op.post("/api/admin/courses", json={"slug": "methode-ict", "title": "Doublon"}, headers=OH).status_code == 400
    assert op.post(f"/api/admin/courses/{cid}/parts", json={"title": "Partie 1", "video": "https://evil.example/v", "duration_s": 2400}, headers=OH).status_code == 400
    op.post(f"/api/admin/courses/{cid}/parts", json={"title": "Partie 1 : la liquidité", "video": "https://youtu.be/dQw4w9WgXcQ", "duration_s": 2400, "free_preview": True, "chapters": "0:00 Intro\n20:00 Exemples"}, headers=OH)
    course = op.post(f"/api/admin/courses/{cid}/parts", json={"title": "Partie 2 : le Silver Bullet", "video": "https://player.mux.com/Xy12AbCdEf34GhIj", "duration_s": 2350}, headers=OH).json()
    p1, p2 = (p["id"] for p in course["parts"])
    moved = op.post(f"/api/admin/courses/{cid}/parts/{p2}/move", json={"delta": -1}, headers=OH).json()
    assert [p["id"] for p in moved["parts"]] == [p2, p1]
    op.post(f"/api/admin/courses/{cid}/parts/{p2}/move", json={"delta": 1}, headers=OH)

    anon = c.get("/api/site/courses/methode-ict").json()
    assert not anon["unlocked"] and anon["parts"][0]["player"]["src"].startswith("https://www.youtube-nocookie.com/embed/")
    assert anon["parts"][1]["locked"] and anon["parts"][1]["player"] is None  # no video link leaks to non-members
    _, H = register(c)
    assert c.post("/api/m/progress", json={"part_id": p2, "position_s": 10}, headers=H).status_code == 400
    assert c.post("/api/m/progress", json={"part_id": p1, "position_s": 99999 % 86_400, "completed": True}, headers=H).status_code == 200
    mid = op.get("/api/admin/members").json()[0]["id"]
    op.post(f"/api/admin/members/{mid}/grant", json={"offer": "trader", "months": 1, "reason": "test"}, headers=OH)
    full = c.get("/api/site/courses/methode-ict").json()
    assert full["unlocked"] and full["parts"][1]["player"]["src"] == "https://player.mux.com/Xy12AbCdEf34GhIj"
    assert full["parts"][0]["progress"] == {"position_s": 2400, "completed": True}  # clamped to the video length
    assert full["parts"][0]["chapters"][1] == {"t": 1200, "title": "Exemples"}
    catalog = {x["slug"]: x for x in c.get("/api/site/courses").json()}
    assert catalog["methode-ict"]["parts"] == 2 and catalog["methode-ict"]["duration_s"] == 4750 and not catalog["methode-ict"].get("planned")
    assert c.get("/api/site/courses/inconnu").status_code == 404


# ---------------- copytrading ----------------
def _run_leader_bot(eng, steps=400):
    bot = {"id": new_bot_id(), "name": "Or ICT", "strategy": "mean_reversion", "symbols": ["XAUUSD"], "timeframe": "1h", "direction": "both", "risk_per_trade_pct": 1.0, "max_position_pct": 25, "params": {"entry_z": 1.0, "max_er": 0.8}, "status": "stopped"}
    eng.store.save_bot(bot)
    eng.start_bot(bot["id"], "vic")
    return bot


def test_copytrading_demo_follow_and_drawdown_stop(site_app):
    c, eng, _ = site_app()
    bot = _run_leader_bot(eng)
    op = TestClient(c.app)
    OH = operator(op)
    assert op.post("/api/admin/leaders", json={"name": "Or intraday", "trader": "Khalifa Diop", "ref_capital": 10_000, "status": "open"}, headers=OH).status_code == 400  # needs a bot
    leader = op.post("/api/admin/leaders", json={"name": "Or intraday", "trader": "Khalifa Diop", "bot_id": bot["id"], "ref_capital": 10_000, "status": "open", "risk_level": 4}, headers=OH).json()
    public = c.get("/api/site/leaders").json()
    assert public["mode"] == "demo" and public["leaders"][0]["record"]["source_mode"] == "simulation" and public["leaders"][0]["record"]["synthetic"]

    _, H = register(c)
    base = {"leader_id": leader["id"], "allocation": 1000, "multiplier": 1.0, "max_drawdown_pct": 5, "accept_risk": True}
    assert c.post("/api/m/copy", json={**base, "accept_risk": False}, headers=H).status_code == 400
    assert "juridique" in c.post("/api/m/copy", json={**base, "mode": "live"}, headers=H).json()["detail"]
    f = c.post("/api/m/copy", json=base, headers=H).json()
    assert f["status"] == "active" and f["equity"] == pytest.approx(1000)
    assert c.post("/api/m/copy", json=base, headers=H).status_code == 400  # already copying

    # the leader trades; the follower sees the scaled result: allocation/ref_capital x multiplier
    start_pnl = eng.stack.portfolio.book_equity(bot["id"])
    for _ in range(300):
        eng.clock.advance(3_600_000)
        eng.step()
        eng._snapshot_nav(eng.clock.now_ms(), eng.stack.portfolio.marks)
    c.app.state.members  # noqa: B018
    d = c.get(f"/api/m/copy/{f['id']}").json()
    lead_move = eng.stack.portfolio.book_equity(bot["id"]) - start_pnl
    if d["status"] == "active":
        assert d["pnl"] == pytest.approx(lead_move * 1000 / 10_000, rel=0.05, abs=0.5)
    else:
        assert "perte maximale" in d["stop_reason"] and d["drawdown_pct"] >= 5 - 1e-9
    stopped = c.post(f"/api/m/copy/{f['id']}/stop", headers=H).json()
    assert stopped["status"] == "stopped"


def test_copytrading_off(site_app):
    c, eng, _ = site_app(copytrading="off")
    assert c.get("/api/site/leaders").json() == {"mode": "off", "leaders": []}


# ---------------- public endpoints and site pages ----------------
def test_public_endpoints(site_app):
    c, _, _ = site_app()
    info = c.get("/api/site").json()
    assert info["brand"]["name"] == "Liberté Financière" and [o["key"] for o in info["offers"]][:2] == ["decouverte", "trader"]
    robots = c.get("/api/site/robots").json()
    assert [r["status"] for r in robots] == ["beta", "beta", "development"] and robots[0]["timeframes"] == ["1m"]
    q = c.get("/api/site/quotes").json()
    assert q["synthetic"] and {x["symbol"] for x in q["quotes"]} >= {"XAUUSD", "NAS100"}
    assert c.post("/api/site/leads", json={"email": "x@example.com", "interest": "next_bot"}).status_code == 200
    assert c.get("/api/unknown").status_code == 404 and c.get("/api/unknown").json()["detail"] == "route inconnue"


def test_site_pages_csp_and_paths(tmp_path, site_app):
    site = tmp_path / "site"
    (site / "robots").mkdir(parents=True)
    (site / "_next" / "static").mkdir(parents=True)
    (site / "index.html").write_text("<html><script>self.a=1</script><script src='/_next/static/x.js'></script></html>")
    (site / "robots" / "index.html").write_text("<html><script>self.b=2</script></html>")
    (site / "404.html").write_text("<html>introuvable</html>")
    (site / "_next" / "static" / "x.js").write_text("1")
    (tmp_path / "secret.txt").write_text("no")
    c, _, _ = site_app(site_dir=site)
    r = c.get("/")
    csp = r.headers["content-security-policy"]
    assert r.status_code == 200 and "'sha256-" in csp and "unsafe-eval" not in csp and "frame-ancestors 'none'" in csp
    assert "https://player.mux.com" in csp and "https://media.lf.test" in csp
    assert c.get("/robots/").status_code == 200 and c.get("/robots").status_code == 200
    assert c.get("/_next/static/x.js").headers["cache-control"].startswith("public, max-age=31536000")
    assert c.get("/../secret.txt").status_code == 404 and c.get("/%2e%2e/secret.txt").status_code == 404
    assert c.get("/nulle-part").status_code == 404
    assert c.get("/console").status_code == 200 and "script-src 'self'" in c.get("/console").headers["content-security-policy"]
    pages = SitePages(site)
    assert pages.csp(site / "index.html").count("'sha256-") == 1
    first = c.get("/").headers["content-security-policy"]
    time.sleep(0.01)
    (site / "index.html").write_text("<html><script>self.a=2</script><script>self.c=3</script></html>")  # site republished
    again = c.get("/").headers["content-security-policy"]
    assert again != first and again.count("'sha256-") == 2

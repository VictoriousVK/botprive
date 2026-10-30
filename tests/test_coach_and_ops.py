"""IA Trading Coach, e-mail sending, Sentry scrubbing, CSP for third-party scripts."""

from types import SimpleNamespace

from fastapi.testclient import TestClient

from hedgefund.coach import Coach, load_knowledge, split_sources, system_prompt
from hedgefund.members.mailer import LogMailer, SmtpMailer, mailer_from_env, verification_mail
from hedgefund.members.site import MemberSettings
from hedgefund.web.app import SitePages, WebSettings, create_app
from hedgefund.web.observability import browser_config, scrub, sentry_browser_hosts
from hedgefund.web.security import AuthService
from tests.test_members import PW, _engine, _site, operator, register


class FakeClaude:
    """Stands in for anthropic.Anthropic: records calls, answers with a fixed text."""

    def __init__(self, text="Un **FVG** est un motif de 3 bougies.\nSOURCES: 05-fvg-et-desequilibres, inconnu"):
        self.calls = []
        self.text = text
        self.messages = self

    def create(self, **kw):
        self.calls.append(kw)
        return SimpleNamespace(stop_reason="end_turn", content=[SimpleNamespace(type="text", text=self.text)], usage=SimpleNamespace(input_tokens=12000, output_tokens=150))


def test_knowledge_base_is_complete():
    fiches = load_knowledge()
    ids = {f.id for f in fiches}
    for needed in ("01-structure-de-marche", "02-liquidite", "04-order-block", "05-fvg-et-desequilibres", "07-temps-sessions-killzones", "11-modeles-entree", "14-glossaire"):
        assert needed in ids
    assert all(f.title and not f.title.startswith("#") for f in fiches)
    prompt = system_prompt(fiches)
    assert "SOURCES:" in prompt and '<fiche id="04-order-block">' in prompt
    for term in ("BISI", "Consequent Encroachment", "Mean threshold", "70,5 %", "03:00–04:00", "Breaker haussier", "SMT"):
        assert term in prompt, term


def test_split_sources():
    ans, ids, out = split_sources("Réponse.\n\nSOURCES: 04-order-block, `02-liquidite`, inventé", {"04-order-block", "02-liquidite"})
    assert ans == "Réponse." and ids == ["04-order-block", "02-liquidite"] and not out
    assert split_sources("Je ne sais pas.\nSOURCES: hors-base", set())[2] is True
    assert split_sources("Sans ligne de sources", set()) == ("Sans ligne de sources", [], False)


def _app(tmp_path, coach):
    eng = _engine(tmp_path)
    auth = AuthService(eng.store)
    auth.create_user("vic", PW)
    ms = MemberSettings(public_url="https://lf.test")
    app = create_app(eng, auth, WebSettings(cookie_secure=False, hsts=False), start_engine=False, site=_site(tmp_path), member_settings=ms, site_dir=tmp_path / "nosite", mailer=LogMailer(), coach=coach)
    return TestClient(app), eng


def test_coach_requires_entitlement_and_enforces_quota(tmp_path):
    fake = FakeClaude()
    coach = Coach(fake, model="claude-test", daily_limit=2)
    c, _ = _app(tmp_path, coach)
    assert c.get("/api/site").json()["coach"] is True
    _, H = register(c)
    st = c.get("/api/m/coach").json()
    assert st["enabled"] and not st["entitled"] and len(st["topics"]) >= 10
    r = c.post("/api/m/coach", json={"question": "C'est quoi un FVG ?"}, headers=H)
    assert r.status_code == 403 and "Quant Elite" in r.json()["detail"]
    me = c.get("/api/m/me").json()
    OH = operator(c)
    c.post(f"/api/admin/members/{me['id']}/grant", json={"offer": "quant_elite", "months": 1, "reason": "test coach"}, headers=OH)
    r = c.post("/api/m/coach", json={"question": "C'est quoi un FVG ?", "history": [{"role": "assistant", "content": "Bonjour"}, {"role": "user", "content": "Salut"}, {"role": "assistant", "content": "Oui ?"}]}, headers=H)
    assert r.status_code == 200, r.text
    out = r.json()
    assert out["answer"].startswith("Un **FVG**") and "SOURCES" not in out["answer"]
    assert out["sources"] == [{"id": "05-fvg-et-desequilibres", "title": "Fair Value Gap (FVG) et autres déséquilibres"}]
    assert out["remaining"] == 1
    call = fake.calls[-1]
    assert call["model"] == "claude-test" and call["system"][0]["cache_control"] == {"type": "ephemeral"}
    assert call["messages"][0]["role"] == "user" and call["messages"][-1] == {"role": "user", "content": "C'est quoi un FVG ?"}
    assert c.post("/api/m/coach", json={"question": "Et un OB ?"}, headers=H).status_code == 200
    r = c.post("/api/m/coach", json={"question": "Encore une ?"}, headers=H)
    assert r.status_code == 429 and "limite" in r.json()["detail"]
    q = c.get("/api/admin/coach").json()
    assert q["enabled"] and len(q["questions"]) == 2 and q["questions"][0]["email"] == "awa@example.com"


def test_coach_failure_is_reported_not_crashed(tmp_path):
    class Broken(FakeClaude):
        def create(self, **kw):
            raise RuntimeError("clé API invalide")

    c, _ = _app(tmp_path, Coach(Broken()))
    _, H = register(c)
    OH = operator(c)
    c.post(f"/api/admin/members/{c.get('/api/m/me').json()['id']}/grant", json={"offer": "quant_elite", "months": 1, "reason": "x x x"}, headers=OH)
    r = c.post("/api/m/coach", json={"question": "C'est quoi un OB ?"}, headers=H)
    assert r.status_code == 503 and "indisponible" in r.json()["detail"]


def test_coach_disabled(tmp_path):
    c, _ = _app(tmp_path, None)
    assert c.get("/api/site").json()["coach"] is False
    _, H = register(c)
    assert c.get("/api/m/coach").json()["enabled"] is False
    assert c.post("/api/m/coach", json={"question": "FVG ?"}, headers=H).status_code == 503


# ---------------- e-mail ----------------
def test_smtp_message_and_env(monkeypatch):
    m = SmtpMailer("smtp.example.com", sender="Liberté Financière <no-reply@lf.test>", background=False)
    msg = m._message(verification_mail("a@b.co", "<script>Awa Ndiaye", "https://lf.test/compte/verifier/?jeton=abc", 48))
    assert msg["To"] == "a@b.co" and "lf.test" in msg["Message-ID"]
    html = msg.get_body(("html",)).get_content()
    assert "&lt;script&gt;" in html and "<script>" not in html
    monkeypatch.delenv("LF_SMTP_HOST", raising=False)
    assert isinstance(mailer_from_env(), LogMailer)
    monkeypatch.setenv("LF_SMTP_HOST", "smtp-relay.brevo.com")
    monkeypatch.setenv("LF_SMTP_SECURITY", "ssl")
    mm = mailer_from_env()
    assert isinstance(mm, SmtpMailer) and mm.port == 465 and mm.security == "ssl"


# ---------------- Sentry ----------------
def test_sentry_scrub_removes_secrets(monkeypatch):
    ev = {
        "request": {"cookies": {"lf_session": "x"}, "data": {"password": "p"}, "headers": {"Cookie": "a", "X-CSRF-Token": "t", "User-Agent": "ua"}, "query_string": "jeton=secret"},
        "user": {"id": "7", "email": "a@b.co", "ip_address": "1.2.3.4"},
    }
    out = scrub(ev)
    assert "cookies" not in out["request"] and "data" not in out["request"]
    assert out["request"]["headers"]["Cookie"] == "[filtré]" and out["request"]["headers"]["User-Agent"] == "ua"
    assert out["request"]["query_string"] == "[filtré]" and out["user"] == {"id": "7"}
    monkeypatch.delenv("SENTRY_BROWSER_DSN", raising=False)
    assert browser_config() is None and sentry_browser_hosts() == ()
    monkeypatch.setenv("SENTRY_BROWSER_DSN", "https://abc@o123.ingest.de.sentry.io/456")
    assert browser_config()["dsn"].endswith("/456") and sentry_browser_hosts() == ("https://o123.ingest.de.sentry.io",)


def test_site_csp_allows_only_configured_third_parties(tmp_path):
    (tmp_path / "index.html").write_text("<html><script>1</script></html>")
    plain = SitePages(tmp_path).csp(tmp_path / "index.html")
    assert "challenges.cloudflare.com" not in plain and "connect-src 'self';" in plain
    pages = SitePages(tmp_path, script_hosts=("https://challenges.cloudflare.com",), frame_hosts=("https://challenges.cloudflare.com",), connect_hosts=("https://o1.ingest.sentry.io",))
    csp = pages.csp(tmp_path / "index.html")
    assert "script-src 'self' https://challenges.cloudflare.com 'sha256-" in csp
    assert "https://challenges.cloudflare.com;" in csp.split("frame-src", 1)[1] and "connect-src 'self' https://o1.ingest.sentry.io;" in csp

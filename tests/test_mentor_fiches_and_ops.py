"""The ICT reference sheets feed the Mentor (one assistant for ICT questions), the team sees the
questions the content does not cover yet; e-mail sending, Sentry scrubbing and the site CSP."""

from fastapi.testclient import TestClient

from hedgefund.members.mailer import LogMailer, SmtpMailer, mailer_from_env, verification_mail
from hedgefund.saas.knowledge import FICHES
from hedgefund.web.app import SitePages
from hedgefund.web.observability import browser_config, scrub, sentry_browser_hosts
from saas_helpers import grant, make_app, operator, register


# ---------------- ICT sheets in the Mentor ----------------
def test_the_ict_sheets_are_complete():
    files = {f.stem: f.read_text(encoding="utf-8") for f in FICHES.glob("[0-9]*.md")}
    for needed in ("01-structure-de-marche", "02-liquidite", "04-order-block", "05-fvg-et-desequilibres", "07-temps-sessions-killzones", "11-modeles-entree", "14-glossaire"):
        assert needed in files
    assert all(t.startswith("# ") for t in files.values())
    text = "\n".join(files.values())
    for term in ("BISI", "Consequent Encroachment", "Mean threshold", "70,5 %", "03:00–04:00", "Breaker haussier", "SMT"):
        assert term in text, term
    # The sheets say what the platform's engine uses (skill ict-definitions, version victor-v0).
    assert "IPDA 20" in files["03-premium-discount-pd-arrays"] and "0,12 ATR" in files["05-fvg-et-desequilibres"]


def _member(tmp_path, offer="starter"):
    c, eng, saas, clock = make_app(tmp_path)
    h = register(c)
    op = TestClient(c.app)
    oh = operator(op)
    if offer:
        grant(op, oh, 1, offer)
    return c, h, saas, op, oh


def test_the_mentor_answers_from_the_sheets_and_keeps_the_teams_documents(tmp_path):
    c, h, saas, op, oh = _member(tmp_path)
    docs = op.get("/api/admin/knowledge", headers=oh).json()
    assert sum(d["source"] == "fiche_ict" for d in docs) == len(list(FICHES.glob("[0-9]*.md")))
    r = c.post("/api/app/mentor/ask", json={"question": "Qu'est-ce qu'un order block et comment le repérer ?"}, headers=h).json()
    assert r["citations"] and any((x["ref"] or "") == "fiche:04-order-block" for x in r["citations"])
    # A sheet written by the team (type « Fiche ») survives every re-indexing of the automatic sources.
    doc = {"title": "Fiche maison : routine du matin", "source": "fiche", "access": "academy_member", "text": "Routine du matin : marquer PDH, PDL et le range asiatique avant Londres. " * 2}
    assert op.post("/api/admin/knowledge", json=doc, headers=oh).status_code == 200
    counts = op.post("/api/admin/knowledge/reindex", headers=oh).json()
    assert counts["fiche_ict"] >= 15
    assert any(d["title"] == doc["title"] for d in op.get("/api/admin/knowledge", headers=oh).json())


def test_the_team_sees_the_questions_the_content_does_not_cover(tmp_path):
    c, h, saas, op, oh = _member(tmp_path)
    c.post("/api/app/mentor/ask", json={"question": "Zorglub et bidulon ?"}, headers=h)
    c.post("/api/app/mentor/ask", json={"question": "Qu'est-ce qu'un FVG ?"}, headers=h)
    qs = op.get("/api/admin/mentor/questions", headers=oh).json()
    assert [q["question"] for q in qs][:2] == ["Qu'est-ce qu'un FVG ?", "Zorglub et bidulon ?"]
    assert qs[1]["label"] == "OUT_OF_CORPUS" and qs[0]["passages"] > 0
    assert all("email" not in q and "name" not in q for q in qs)  # no personal data in the team's view
    assert c.get("/api/admin/mentor/questions").status_code in (401, 403)  # members never see it


def test_the_old_coach_page_and_routes_are_gone(tmp_path):
    c, h, saas, op, oh = _member(tmp_path, offer="quant_elite")
    assert "coach" not in c.get("/api/site").json()
    assert c.post("/api/m/coach", json={"question": "FVG ?"}, headers=h).status_code in (404, 405)


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

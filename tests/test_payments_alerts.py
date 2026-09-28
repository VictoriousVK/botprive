"""After a payment: the team is alerted at once (Discord/Slack webhook, Telegram), the member is
told in their space when access opens or the transfer is refused. And the academy in the trading
space: the member's courses with their progress; the Mentor re-reads a course when it changes."""

from fastapi.testclient import TestClient

from hedgefund.members.alerts import OperatorAlerts
from saas_helpers import grant, make_app, operator, register


class FakePost:
    def __init__(self, status: int = 200):
        self.calls: list[tuple[str, dict]] = []
        self.status = status

    def __call__(self, url, json=None, timeout=None):  # noqa: A002 - same signature as requests.post
        self.calls.append((url, json))
        return type("R", (), {"status_code": self.status})()


def _setup(tmp_path):
    c, eng, saas, clock = make_app(tmp_path)
    post = FakePost()
    alerts: OperatorAlerts = c.app.state.alerts
    alerts.post, alerts.background, alerts.telegram_token = post, False, "123:bot"
    op = TestClient(c.app)
    oh = operator(op)
    return c, op, oh, post, saas


def _declare(c, h, ref="TXN-778899"):
    pid = c.post("/api/m/checkout", json={"offer": "starter", "months": 1}, headers=h).json()["payment"]["id"]
    assert c.post(f"/api/m/payments/{pid}/declare", json={"transaction_ref": ref}, headers=h).json()["status"] == "declared"
    return pid


def test_a_declared_transfer_alerts_the_team_without_personal_details(tmp_path):
    c, op, oh, post, saas = _setup(tmp_path)
    h = register(c)
    _declare(c, h)
    assert post.calls == []  # nothing configured: no alert, no error
    r = op.put("/api/admin/settings", json={"telegram_url": "", "discord_url": "", "alert_webhook_url": "https://discord.com/api/webhooks/1/abc", "alert_telegram_chat": "123456789"}, headers=oh)
    assert r.status_code == 200
    st = r.json()["alerts"]
    assert st == {"webhook_set": True, "webhook_from_env": False, "telegram_chat": "123456789", "telegram_bot": True}
    assert "discord.com/api/webhooks" not in r.text  # the webhook URL is a credential: never sent back
    c2 = TestClient(c.app)
    h2 = register(c2, "moussa@example.com")
    _declare(c2, h2, "TXN-112233")
    urls = [u for u, _ in post.calls]
    assert urls == ["https://discord.com/api/webhooks/1/abc", "https://api.telegram.org/bot123:bot/sendMessage"]
    text = post.calls[0][1]["content"]
    assert "Paiement Wave à valider" in text and "Awa Ndiaye" in text and "Starter" in text and "TXN-112233" in text and "FCFA" in text
    assert "@" not in text and "+221" not in text  # no e-mail, no phone number
    assert post.calls[1][1]["chat_id"] == "123456789"


def test_alert_settings_are_validated_and_testable(tmp_path):
    c, op, oh, post, saas = _setup(tmp_path)
    assert op.post("/api/admin/alerts/test", headers=oh).status_code == 400  # nothing configured yet
    bad = op.put("/api/admin/settings", json={"alert_webhook_url": "http://insecure.example/hook"}, headers=oh)
    assert bad.status_code == 400
    assert op.put("/api/admin/settings", json={"alert_telegram_chat": "moi"}, headers=oh).status_code == 400
    assert op.put("/api/admin/settings", json={"alert_telegram_chat": "-1001234567890"}, headers=oh).status_code == 200
    assert op.post("/api/admin/alerts/test", headers=oh).json() == {"webhook": None, "telegram": True}
    assert "Test des alertes" in post.calls[-1][1]["text"]
    # an empty string removes a channel; an absent field keeps it
    op.put("/api/admin/settings", json={"telegram_url": ""}, headers=oh)
    assert op.get("/api/admin/settings", headers=oh).json()["alerts"]["telegram_chat"] == "-1001234567890"
    op.put("/api/admin/settings", json={"alert_telegram_chat": ""}, headers=oh)
    assert op.get("/api/admin/settings", headers=oh).json()["alerts"]["telegram_chat"] == ""
    assert c.post("/api/admin/alerts/test").status_code == 401  # operators only


def test_the_member_is_told_when_access_opens_or_the_transfer_is_refused(tmp_path):
    c, op, oh, post, saas = _setup(tmp_path)
    h = register(c)
    pid = _declare(c, h)
    assert op.post(f"/api/admin/payments/{pid}/approve", headers=oh).json()["status"] == "succeeded"
    n = c.get("/api/app/notifications").json()
    assert n["unread"] == 1 and n["items"][0]["title"] == "Accès activé : Starter" and n["items"][0]["link"] == "/app/"
    assert "jusqu'au" in n["items"][0]["body"] and "17 000 FCFA" in n["items"][0]["body"]
    assert c.get("/api/app/me").json()["plan"] == "starter"
    pid2 = _declare(c, h, "TXN-445566")
    op.post(f"/api/admin/payments/{pid2}/reject", json={"reason": "transaction introuvable dans Wave"}, headers=oh)
    top = c.get("/api/app/notifications").json()["items"][0]
    assert top["title"] == "Paiement non validé" and "transaction introuvable dans Wave" in top["body"] and "refusé par" not in top["body"]


def test_wave_checkout_success_is_announced_but_team_actions_are_not():
    alerts = OperatorAlerts(store=None, telegram_token="", public_url="https://lf.example")
    base = {"member_name": "Awa Ndiaye", "offer_label": "Pro Trader", "months": 1, "amount": 46000, "transaction_ref": "T_1"}
    assert "confirmé par Wave" in alerts.message("payment_succeeded", {**base, "method": "wave_checkout"})
    assert alerts.message("payment_succeeded", {**base, "method": "wave_manual"}) is None  # the team validated it itself
    assert alerts.message("payment_succeeded", {**base, "method": "grant"}) is None
    assert "https://lf.example/admin/" in alerts.message("payment_declared", {**base, "method": "wave_manual"})


def test_telegram_id_command_gives_the_chat_identifier(tmp_path):
    c, op, oh, post, saas = _setup(tmp_path)
    sent = []
    n = saas.modules["notify"]
    n.sender = lambda chat, text: sent.append((chat, text)) or True
    assert n.on_telegram_update({"message": {"text": "/id", "chat": {"id": -100555}}}) is False
    assert sent and sent[0][0] == "-100555" and "-100555" in sent[0][1]


def test_courses_in_the_trading_space_and_the_mentor_rereads_them(tmp_path):
    c, op, oh, post, saas = _setup(tmp_path)
    h = register(c)
    crs = op.post("/api/admin/courses", json={"slug": "fvg-pratique", "title": "Les FVG en pratique", "access": "academy_member", "status": "published"}, headers=oh).json()
    op.post(f"/api/admin/courses/{crs['id']}/parts", json={"title": "Définition", "video": "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "duration_s": 600, "free_preview": True, "summary": "Un Fair Value Gap est un déséquilibre sur trois bougies."}, headers=oh)
    op.post(f"/api/admin/courses/{crs['id']}/parts", json={"title": "Entrées sur FVG", "video": "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "duration_s": 900}, headers=oh)
    docs = op.get("/api/admin/knowledge", headers=oh).json()
    assert any(d["source"] == "course" and d["title"] == "Les FVG en pratique" for d in docs)  # re-read without pressing "Réindexer"

    mine = {x["slug"]: x for x in c.get("/api/m/courses", headers=h).json()}
    x = mine["fvg-pratique"]
    assert x["unlocked"] is False and x["parts"] == 2 and x["open_parts"] == 1 and x["next"]["title"] == "Définition"  # free preview only
    grant(op, oh, 1, "starter")
    x = {y["slug"]: y for y in c.get("/api/m/courses").json()}["fvg-pratique"]
    assert x["unlocked"] is True and x["open_parts"] == 2 and x["completed"] == 0
    detail = c.get("/api/site/courses/fvg-pratique").json()
    first = detail["parts"][0]["id"]
    assert c.post("/api/m/progress", json={"part_id": first, "position_s": 600, "completed": True}, headers=h).status_code == 200
    x = {y["slug"]: y for y in c.get("/api/m/courses").json()}["fvg-pratique"]
    assert x["completed"] == 1 and x["next"]["title"] == "Entrées sur FVG" and x["last_seen"]
    assert TestClient(c.app).get("/api/m/courses").status_code == 401  # members only

"""P1 modules: Mentor (RAG with access control), TradingView webhooks, notifications and Telegram
linking, briefing graph G4 and the scheduler routes, validation lab, EA telemetry, GMI sync."""

import base64
import random
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from saas_helpers import grant, make_app, operator, register

JOBS = {"X-Jobs-Secret": "jobs-secret-test"}


def _app(tmp_path, offer=None, turns=None, now=None):
    kw = {"now": now} if now else {}
    c, eng, saas, clock = make_app(tmp_path, turns=turns, **kw)
    h = register(c)
    op = TestClient(c.app)
    oh = operator(op)
    if offer:
        grant(op, oh, 1, offer)
    return c, h, saas, op, oh


# ---------------------------------------------------------------- Mentor
def test_mentor_rules_answer_access_filter_and_advice(tmp_path):
    c, h, saas, op, oh = _app(tmp_path)
    assert c.post("/api/app/mentor/ask", json={"question": "C'est quoi un FVG ?"}, headers=h).status_code == 403
    grant(op, oh, 1, "starter")
    r = c.post("/api/app/mentor/ask", json={"question": "Qu'est-ce qu'un FVG et quand est-il mitigé ?"}, headers=h).json()
    assert r["label"] == "PARTIAL" and r["citations"] and r["narrated_by"] == "rules" and "Définitions ICT" in r["citations"][0]["title"]
    adv = c.post("/api/app/mentor/ask", json={"question": "Dois-je acheter l'or maintenant ?"}, headers=h).json()
    assert adv["label"] == "REFUSED_ADVICE"
    doc = {"title": "Module 7 : zorglub", "source": "fiche", "access": "formation_ict", "text": "Le concept zorglub se lit sur le graphique M5 après un sweep de la liquidité. " * 3}
    assert op.post("/api/admin/knowledge", json=doc, headers=oh).status_code == 200
    out = c.post("/api/app/mentor/ask", json={"question": "Explique le zorglub"}, headers=h).json()
    assert out["label"] == "OUT_OF_CORPUS"  # starter does not include the ICT course
    grant(op, oh, 1, "formation_ict")
    assert c.post("/api/app/mentor/ask", json={"question": "Explique le zorglub"}, headers=h).json()["citations"][0]["title"] == "Module 7 : zorglub"


def test_mentor_model_must_cite_passages(tmp_path):
    def cite_first(req):
        content = req["messages"][0]["content"]
        cid = content.split('"chunk_id": "')[1].split('"')[0]
        return {"label": "ANSWERED", "answer": "Un FVG est un déséquilibre sur trois bougies.", "cited_chunk_ids": [cid], "exercise": None}

    uncited = {"label": "ANSWERED", "answer": "Un FVG, c'est simple.", "cited_chunk_ids": ["inventé"], "exercise": None}
    c, h, saas, op, oh = _app(tmp_path, offer="starter", turns=[cite_first, uncited])
    ok = c.post("/api/app/mentor/ask", json={"question": "Définition d'un FVG ?"}, headers=h).json()
    assert ok["label"] == "ANSWERED" and ok["narrated_by"] == "llm" and len(ok["citations"]) == 1
    ko = c.post("/api/app/mentor/ask", json={"question": "Définition d'un FVG ?"}, headers=h).json()
    assert ko["narrated_by"] == "rules" and "écartée" in ko["caveats"][0]


# ---------------------------------------------------------------- TradingView and notifications
def test_tradingview_webhook_starts_g1_once(tmp_path):
    c, h, saas, op, oh = _app(tmp_path, offer="pro_trader")
    c.post("/api/app/accounts", json={"label": "Démo", "starting_balance": 10000}, headers=h)
    hook = c.post("/api/app/tradingview/hooks", headers=h).json()
    token = hook["message"].split('"token": "')[1].split('"')[0]
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    machine = TestClient(c.app)
    body = {"token": token, "symbol": "OANDA:XAUUSD", "time": now_iso, "alert_id": "XAUUSD-5-1", "tf": "5"}
    r = machine.post(f"/api/hooks/tv/{hook['hook_id']}", json=body)
    assert r.status_code == 200 and r.json()["trace_id"], r.text
    assert machine.post(f"/api/hooks/tv/{hook['hook_id']}", json=body).json()["duplicate"] is True
    assert machine.post(f"/api/hooks/tv/{hook['hook_id']}", json={**body, "token": "x"}).status_code == 401
    old = (datetime.now(timezone.utc) - timedelta(minutes=10)).strftime("%Y-%m-%dT%H:%M:%SZ")
    assert machine.post(f"/api/hooks/tv/{hook['hook_id']}", json={**body, "time": old, "alert_id": "b"}).status_code == 400
    assert machine.post(f"/api/hooks/tv/{hook['hook_id']}", content=b"pas du json").status_code == 400
    lst = c.get("/api/app/analyses").json()
    assert lst[0]["source"] == "tradingview" and lst[0]["symbol"] == "XAUUSD"
    assert c.get("/api/app/notifications").json()["items"][0]["kind"] == "tradingview"


def test_telegram_linking_and_delivery(tmp_path):
    c, h, saas, op, oh = _app(tmp_path)
    assert c.post("/api/app/notifications/telegram", headers=h).status_code == 400  # no bot configured
    sent = []
    saas.settings.telegram_bot_token, saas.settings.telegram_bot_name, saas.settings.telegram_webhook_secret = "123:abc", "AlphaEdgeBot", "hook-secret"
    saas.modules["notify"].sender = lambda chat, text: sent.append((chat, text)) or True
    code = c.post("/api/app/notifications/telegram", headers=h).json()["code"]
    machine = TestClient(c.app)
    assert machine.post("/api/hooks/telegram/wrong", json={}).status_code == 404
    machine.post("/api/hooks/telegram/hook-secret", json={"message": {"text": f"/start {code}", "chat": {"id": 4242}}})
    assert c.get("/api/app/notifications").json()["telegram"]["linked"] is True
    saas.modules["notify"].notify("t_m1", 1, "review", "Revue prête", "Votre revue hebdomadaire est prête.")
    assert sent[-1][0] == "4242" and "Revue prête" in sent[-1][1]


# ---------------------------------------------------------------- research, scheduler
def test_briefing_graph_and_scheduler(tmp_path):
    c, h, saas, op, oh = _app(tmp_path, offer="starter")
    soon = (datetime.now(timezone.utc) + timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%SZ")
    csv = f"time,currency,impact,title\n{soon},USD,high,Indice des prix à la consommation\n"
    assert op.post("/api/admin/calendar", json={"csv": csv}, headers=oh).json()["added"] == 1
    now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
    items = [{"time_utc": now_ms - 3_600_000, "publisher": "Agence A", "title": f"La Fed et le dollar {i}", "url": f"https://a.example/{i}"} for i in range(3)]
    assert op.post("/api/admin/news", json={"items": items}, headers=oh).json()["added"] == 3
    assert TestClient(c.app).post("/api/jobs/briefing", json={"session": "london"}).status_code == 401
    assert TestClient(c.app).post("/api/jobs/briefing", json={"session": "london"}, headers=JOBS).status_code == 200
    saas.run_inline()
    b = c.get("/api/app/briefing").json()
    br = b["briefings"][0]
    assert br["session"] == "london" and br["single_publisher_warning"] is True and br["high_impact_events"][0]["currency"] == "USD"
    assert br["label"] in ("RISK_ON", "RISK_OFF", "NEUTRAL") and br["narrated_by"] == "rules"
    assert b["events"][0]["impact"] == "high"


def test_weekly_reviews_and_guard_alerts(tmp_path):
    c, h, saas, op, oh = _app(tmp_path)
    acct = c.post("/api/app/accounts", json={"label": "Démo", "starting_balance": 10000}, headers=h).json()
    now = datetime.now(timezone.utc)
    t0 = (now - timedelta(minutes=50)).strftime("%Y.%m.%d %H:%M:%S")
    t1 = (now - timedelta(minutes=10)).strftime("%Y.%m.%d %H:%M:%S")
    csv = f"Position,Symbol,Type,Volume,Open Time,Open Price,Close Time,Close Price,Profit\n1,XAUUSD,buy,1,{t0},2650,{t1},2647,-290\n"
    c.post("/api/app/import", json={"account_id": acct["id"], "filename": "a.csv", "content_base64": base64.b64encode(csv.encode()).decode(), "times_are_utc": True}, headers=h)
    w = TestClient(c.app).post("/api/jobs/weekly-reviews", headers=JOBS).json()
    assert w == {"queued": 1, "skipped": 0}
    assert TestClient(c.app).post("/api/jobs/weekly-reviews", headers=JOBS).json()["queued"] == 1  # idempotent: same job key
    assert saas.queue.counts().get("queued") == 1
    g = TestClient(c.app).post("/api/jobs/guard-check", headers=JOBS).json()
    assert g["alerts_sent"] == 1  # -290 on a 3 % daily limit (300): past 80 %
    assert TestClient(c.app).post("/api/jobs/guard-check", headers=JOBS).json()["alerts_sent"] == 0  # once per level and day
    assert any(n["kind"] == "risk_alert" for n in c.get("/api/app/notifications").json()["items"])


# ---------------------------------------------------------------- lab
def test_lab_monte_carlo_demo_vs_real_and_robustness(tmp_path):
    c, h, saas, op, oh = _app(tmp_path, offer="pro_trader")
    demo = c.post("/api/app/accounts", json={"label": "Démo", "starting_balance": 10000, "kind": "demo"}, headers=h).json()
    real = c.post("/api/app/accounts", json={"label": "Réel", "starting_balance": 10000, "kind": "real"}, headers=h).json()
    rng = random.Random(3)
    base = datetime.now(timezone.utc) - timedelta(days=20)
    rows_d, rows_r = ["Position,Symbol,Type,Volume,Open Time,Open Price,S/L,Close Time,Close Price,Commission,Profit"], ["Position,Symbol,Type,Volume,Open Time,Open Price,S/L,Close Time,Close Price,Commission,Profit"]
    for i in range(20):
        o = base + timedelta(hours=6 * i)
        win = rng.random() < 0.45
        close = 2660 if win else 2645
        f = lambda d: d.strftime("%Y.%m.%d %H:%M:%S")  # noqa: E731
        rows_d.append(f"{i},XAUUSD,buy,0.1,{f(o)},2650,2645,{f(o + timedelta(minutes=40))},{close},-0.5,{(close - 2650) * 10}")
        rows_r.append(f"{i},XAUUSD,buy,0.1,{f(o + timedelta(seconds=20))},2650.3,2645,{f(o + timedelta(minutes=40))},{close - 0.2},-0.9,{(close - 2650.5) * 10}")
    for acct, rows in ((demo, rows_d), (real, rows_r)):
        c.post("/api/app/import", json={"account_id": acct["id"], "filename": "x.csv", "content_base64": base64.b64encode("\n".join(rows).encode()).decode(), "times_are_utc": True}, headers=h)
    mc = c.post("/api/app/lab/monte-carlo", json={"days": 60, "sims": 500}, headers=h).json()
    assert mc["trades"] == 40 and mc["max_drawdown_pct"]["p95"] >= mc["max_drawdown_pct"]["p50"] and mc["breach_probability"] is not None
    dvr = c.post("/api/app/lab/demo-vs-real", json={"demo_account_id": demo["id"], "real_account_id": real["id"], "days": 60}, headers=h).json()
    assert dvr["matched"] == 20 and dvr["entry_slippage_avg"] > 0 and dvr["cost_diff_avg"] < 0 and len(dvr["causes"]) >= 2
    rob = c.post("/api/app/lab/robustness", json={"strategy": "trend", "symbol": "XAUUSD", "timeframe": "1h", "folds": 4}, headers=h)
    assert rob.status_code == 200, rob.text
    assert len(rob.json()["windows"]) == 4 and rob.json()["caveats"] and rob.json()["n_trials"] == 1
    assert c.post("/api/app/lab/robustness", json={"strategy": "trend", "symbol": "XAUUSD", "timeframe": "1h"}, headers=h).json()["n_trials"] == 2  # every try counts
    assert len(c.get("/api/app/lab/reports").json()) == 4


# ---------------------------------------------------------------- telemetry and GMI sync
def test_telemetry_and_offline_sync(tmp_path):
    c, h, saas, op, oh = _app(tmp_path, offer="pro_trader")
    acct = c.post("/api/app/accounts", json={"label": "VPS", "starting_balance": 10000}, headers=h).json()
    tok = c.post(f"/api/app/accounts/{acct['id']}/sync-token", headers=h).json()["token"]
    m = TestClient(c.app)
    assert m.post("/api/ingest/telemetry", json={"ea": "ICT Pro", "status": "error", "last_error": "requote"}, headers={"Authorization": f"Bearer {tok}"}).status_code == 200
    st = c.get("/api/app/telemetry").json()
    assert st[0]["ea"] == "ICT Pro" and st[0]["status"] == "error"
    assert any(n["kind"] == "ea_factory" for n in c.get("/api/app/notifications").json()["items"])
    now = datetime.now(timezone.utc)
    csv = f"Position,Symbol,Type,Volume,Open Time,Open Price,Close Time,Close Price,Profit\n9,XAUUSD,buy,0.1,{(now - timedelta(hours=2)):%Y.%m.%d %H:%M:%S},2650,{(now - timedelta(hours=1)):%Y.%m.%d %H:%M:%S},2655,50\n"
    c.post("/api/app/import", json={"account_id": acct["id"], "filename": "s.csv", "content_base64": base64.b64encode(csv.encode()).decode(), "times_are_utc": True}, headers=h)
    tid = c.get("/api/app/trades").json()[0]["id"]
    c.put(f"/api/app/trades/{tid}/journal", json={"notes": "version web"}, headers=h)
    t = int(now.timestamp() * 1000)
    r = c.put("/api/app/sync", json={"entries": [{"trade_id": tid, "fields": {"notes": "version mobile ancienne", "rating": 4}, "times": {"notes": t - 10**9, "rating": t + 1000}}]}, headers=h).json()
    assert r["applied"] == 1 and r["kept_server"] == 1  # the web note is newer than the offline one
    r = c.put("/api/app/sync", json={"entries": [{"trade_id": tid, "fields": {"notes": "note mobile récente"}, "times": {"notes": t + 5000}}]}, headers=h).json()
    assert r["applied"] == 1
    e = c.get("/api/app/sync?since=0").json()["entries"][0]
    assert e["rating"] == 4 and e["notes"] == "note mobile récente"
    c.put(f"/api/app/trades/{tid}/journal", json={"rating": 2}, headers=h)  # a partial web edit keeps the other fields
    e = c.get("/api/app/sync?since=0").json()["entries"][0]
    assert e["rating"] == 2 and e["notes"] == "note mobile récente"

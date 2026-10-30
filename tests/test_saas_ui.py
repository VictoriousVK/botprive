"""Routes written for the member interface: the dashboard in one call, and the candles behind
the analysis chart."""

import base64

from fastapi.testclient import TestClient

from saas_helpers import grant, make_app, operator, register

CSV = "\n".join([
    "Position,Symbol,Type,Volume,Open Time,Open Price,S/L,T/P,Close Time,Close Price,Profit",
    "4001,XAUUSD,buy,0.10,2026.10.12 13:30:00,2650,2645,2665,2026.10.12 13:50:00,2645,-50",
    "4002,XAUUSD,sell,0.10,2026.10.12 14:30:00,2640,2645,2625,2026.10.12 15:00:00,2630,100",
])


def test_overview_blocks_follow_the_plan(tmp_path):
    c, eng, saas, clock = make_app(tmp_path)
    h = register(c)
    o = c.get("/api/app/overview").json()
    assert o["plan"] == "gratuit" and o["accounts"] == [] and o["guard"] is None and o["analyses"] == [] and o["briefing"] is None
    assert o["stats"]["kpis"]["n"] == 0 and o["last_review"] is None and o["notifications"] == 0
    acct = c.post("/api/app/accounts", json={"label": "Démo", "starting_balance": 10000}, headers=h).json()
    r = c.post("/api/app/import", json={"account_id": acct["id"], "filename": "t.csv", "content_base64": base64.b64encode(CSV.encode()).decode(), "times_are_utc": True}, headers=h)
    assert r.json()["inserted"] == 2
    op = TestClient(c.app)
    grant(op, operator(op), 1, "pro_trader")
    o = c.get("/api/app/overview").json()
    assert o["plan"] == "pro_trader" and [a["id"] for a in o["accounts"]] == [acct["id"]]
    assert o["guard"]["account_id"] == acct["id"] and o["guard"]["profile"] == "generic"
    assert set(o["stats"]["kpis"]) >= {"n", "win_rate", "expectancy_r", "insufficient"}  # a subset: the full tables stay in /stats


def test_bars_need_the_analysis_feature(tmp_path):
    c, eng, saas, clock = make_app(tmp_path)
    register(c)
    assert c.get("/api/app/bars/XAUUSD?tf=M5").status_code == 403
    op = TestClient(c.app)
    grant(op, operator(op), 1, "starter")
    r = c.get("/api/app/bars/XAUUSD?tf=M5&n=60").json()
    assert r["symbol"] == "XAUUSD" and r["synthetic"] is True and len(r["bars"]) == 60
    t, o, hi, lo, cl = r["bars"][-1]
    assert lo <= min(o, cl) <= max(o, cl) <= hi and t < r["as_of"]
    assert all(b[0] < n[0] for b, n in zip(r["bars"], r["bars"][1:], strict=False))
    assert c.get("/api/app/bars/XAUUSD?tf=D1").status_code == 400

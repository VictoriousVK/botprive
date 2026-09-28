"""Sprint S1: import (CSV, MT5 report, EA Journal Sync, investor bridge), normalisation,
enrichment, journal API, caps, data rights and tenant isolation."""

import base64
from types import SimpleNamespace as NS

import pytest
from fastapi.testclient import TestClient

from hedgefund.saas import ingest as I
from hedgefund.saas.bridge import ReadOnlyMT5, run_once
from hedgefund.saas.vault import Vault
from saas_helpers import grant, make_app, operator, register

CSV = """Position;Symbol;Type;Volume;Open Time;Open Price;S/L;T/P;Close Time;Close Price;Commission;Swap;Profit;Comment
1001;XAUUSD.a;buy;0,10;2026.10.06 16:30:00;2650,00;2645,00;2665,00;2026.10.06 17:10:00;2660,00;-0,70;0;100,00;SB NY
1002;XAUUSD.a;sell;0,10;2026.10.06 17:20:00;2661,00;2666,00;2646,00;2026.10.06 17:25:00;2666,00;-0,70;0;-50,00;revenge
1003;USTEC;buy;1,00;2026.10.07 10:05:00;20100,0;20080,0;20160,0;2026.10.07 11:00:00;20160,0;-1,00;0;60,00;
;;balance;;2026.10.01 00:00:00;;;;;;;;10000;depot
"""


def b64(text: str, enc: str = "utf-8") -> str:
    return base64.b64encode(text.encode(enc)).decode()


# ---------------------------------------------------------------- pure functions
@pytest.mark.parametrize("raw,norm", [("XAUUSD.a", "XAUUSD"), ("GOLD", "XAUUSD"), ("USTEC", "NAS100"), ("NAS100.cash", "NAS100"), ("EURUSDm", "EURUSD"), ("US30Cash", "US30"), ("gbpjpy.pro", "GBPJPY"), ("XAU/USD", "XAUUSD")])
def test_normalize_symbol(raw, norm):
    assert I.normalize_symbol(raw) == norm


def test_server_time_to_utc_follows_us_daylight_saving():
    summer = I.server_to_utc(I.parse_time("2026.10.06 16:30:00"))  # server UTC+3
    winter = I.server_to_utc(I.parse_time("2026.12.08 16:30:00"))  # server UTC+2
    assert I.killzone_at(summer) == I.killzone_at(winter) == "NY_AM"
    assert summer == I.parse_time("2026-10-06T13:30:00Z") and winter == I.parse_time("2026-12-08T14:30:00Z")
    assert I.server_to_utc(I.parse_time("2026.10.06 16:30"), measured_offset_min=120) == I.parse_time("2026-10-06 14:30")


def test_parse_csv_french_decimals_and_skips_balance_rows():
    rows = I.parse_csv(CSV)
    assert [r.position_id for r in rows] == ["1001", "1002", "1003"]
    assert rows[0].volume == 0.1 and rows[0].open_price == 2650.0 and rows[0].commission == -0.7
    with pytest.raises(I.ImportError_, match="colonnes manquantes"):
        I.parse_csv("a,b\n1,2\n")


def _report_html() -> str:
    head = "<tr><td colspan=13><b>Positions</b></td></tr><tr><td>Time</td><td>Position</td><td>Symbol</td><td>Type</td><td>Volume</td><td>Price</td><td>S / L</td><td>T / P</td><td>Time</td><td>Price</td><td>Commission</td><td>Swap</td><td>Profit</td></tr>"
    row = "<tr><td>2026.10.06 16:30:00</td><td>555</td><td>XAUUSD</td><td>buy</td><td>0.10</td><td>2 650.00</td><td>2 645.00</td><td>2 665.00</td><td>2026.10.06 17:10:00</td><td>2 660.00</td><td>-0.70</td><td>0.00</td><td>100.00</td></tr>"
    tail = "<tr><td colspan=13><b>Orders</b></td></tr><tr><td>2026.10.06 16:30:00</td><td>9</td><td>XAUUSD</td><td>buy</td><td>0.10 / 0.10</td><td>market</td><td></td><td></td><td>2026.10.06 16:30:00</td><td>filled</td><td></td><td></td><td></td></tr>"
    return f"<html><body><table><tr><td>Account:</td><td>123 (USD, Broker-Demo)</td></tr>{head}{row}{tail}</table></body></html>"


def test_parse_mt5_html_report_in_utf16():
    raw = _report_html().encode("utf-16")
    trades, info = I.parse_mt5_report(I.decode_report(raw))
    assert len(trades) == 1 and trades[0].position_id == "555" and trades[0].open_price == 2650.0 and trades[0].sl == 2645.0
    assert "Broker-Demo" in info["account"]


def _deal(ticket, pid, t, typ, entry, vol, price, profit=0.0, commission=-0.35):
    return {"ticket": ticket, "order": ticket, "position_id": pid, "time": t, "time_msc": 0, "type": typ, "entry": entry, "symbol": "XAUUSD", "volume": vol,
            "price": price, "commission": commission, "swap": 0.0, "profit": profit, "fee": 0.0, "magic": 0, "comment": ""}


def test_trades_from_deals_with_partial_close_and_open_position():
    t0 = 1_790_000_000
    deals = [_deal(1, 7, t0, 0, 0, 0.2, 2650), _deal(2, 7, t0 + 600, 1, 1, 0.1, 2660, 100), _deal(3, 7, t0 + 1200, 1, 1, 0.1, 2670, 200),
             _deal(4, 8, t0 + 1300, 1, 0, 0.1, 2668), {"ticket": 5, "position_id": 0, "type": 2, "entry": 0, "time": t0, "price": 0, "volume": 0}]
    out = {t.position_id: t for t in I.trades_from_deals(deals, {"7": {"initial_sl": 2640}})}
    assert out["7"].close_price == pytest.approx(2665) and out["7"].profit == 300 and out["7"].commission == pytest.approx(-1.05) and out["7"].initial_sl == 2640
    assert out["8"].close_server_ms is None and out["8"].side == "short"


def test_enrich_r_multiple_and_plan_checks():
    plan = {"markets": ["XAUUSD"], "killzones": ["NY_AM"], "risk_per_trade_pct": 1.0, "min_rr": 2.0}
    acct = {"server_winter_offset_h": 2, "server_dst_rule": "us"}
    t = I.parse_csv(CSV)[0]
    e = I.enrich(t, acct, plan, 10_000)
    assert e.r_multiple == pytest.approx(2.0) and e.r_source == "sl" and e.killzone == "NY_AM" and e.setup_model == "SilverBullet"
    assert e.plan_respected is True and e.risk_amount == pytest.approx(50.0)
    be = I.RawTrade("x", "XAUUSD", "long", 0.1, t.open_server_ms, 2650, t.close_server_ms, 2660, sl=2650.0, profit=100)
    e2 = I.enrich(be, acct, plan, 10_000)
    assert e2.r_source == "plan" and e2.r_multiple == pytest.approx(1.0)  # stop at break-even: R from the plan's risk
    nas = I.enrich(I.parse_csv(CSV)[2], acct, plan, 10_000)
    assert nas.plan_respected is False and any("hors plan" in i for i in nas.plan_issues)


# ---------------------------------------------------------------- API
def _setup(tmp_path):
    c, eng, saas, clock = make_app(tmp_path)
    h = register(c)
    acct = c.post("/api/app/accounts", json={"label": "Démo IC", "broker": "IC", "login": "123", "server": "Broker-Demo", "starting_balance": 10000}, headers=h).json()
    return c, h, saas, acct


def test_csv_import_enriches_and_deduplicates(tmp_path):
    c, h, saas, acct = _setup(tmp_path)
    r = c.post("/api/app/import", json={"account_id": acct["id"], "filename": "h.csv", "content_base64": b64(CSV)}, headers=h)
    assert r.status_code == 200, r.text
    assert r.json()["inserted"] == 3
    again = c.post("/api/app/import", json={"account_id": acct["id"], "filename": "h.csv", "content_base64": b64(CSV)}, headers=h).json()
    assert again["inserted"] == 0 and again["unchanged"] == 3
    trades = {t["position_id"]: t for t in c.get("/api/app/trades?days=3650").json()}
    assert trades["1001"]["killzone"] == "NY_AM" and trades["1001"]["r_multiple"] == pytest.approx(2.0) and trades["1001"]["symbol"] == "XAUUSD"
    assert trades["1003"]["symbol"] == "NAS100"
    bad = c.post("/api/app/import", json={"account_id": acct["id"], "filename": "x.csv", "content_base64": b64("foo,bar\n1,2\n")}, headers=h)
    assert bad.status_code == 400 and "colonnes" in bad.json()["detail"]
    assert [j["status"] for j in c.get("/api/app/imports").json()][:1] == ["failed"]


def test_mt5_report_import(tmp_path):
    c, h, saas, acct = _setup(tmp_path)
    content = base64.b64encode(_report_html().encode("utf-16")).decode()
    r = c.post("/api/app/import", json={"account_id": acct["id"], "filename": "ReportHistory.html", "content_base64": content}, headers=h)
    assert r.status_code == 200 and r.json()["inserted"] == 1


def test_journal_entry_manual_trade_export_and_erase(tmp_path):
    c, h, saas, acct = _setup(tmp_path)
    c.post("/api/app/import", json={"account_id": acct["id"], "filename": "h.csv", "content_base64": b64(CSV)}, headers=h)
    tid = next(t["id"] for t in c.get("/api/app/trades?days=3650").json() if t["position_id"] == "1002")
    r = c.put(f"/api/app/trades/{tid}/journal", json={"emotion_before": "frustre", "mistakes": ["revenge"], "followed_plan": False, "notes": "après la perte", "setup_model": "Custom"}, headers=h)
    assert r.status_code == 200 and r.json()["journal"]["emotion_before"] == "frustre" and r.json()["plan_respected"] is False
    assert c.put(f"/api/app/trades/{tid}/journal", json={"emotion_before": "anxieux-clinique"}, headers=h).status_code == 422  # closed vocabulary
    m = c.post("/api/app/trades", json={"account_id": acct["id"], "symbol": "EURUSD", "side": "long", "volume": 1, "open_time_utc": 1_791_000_000_000, "open_price": 1.1, "close_time_utc": 1_791_000_600_000, "close_price": 1.101, "profit": 100}, headers=h)
    assert m.status_code == 200 and m.json()["inserted"] == 1
    manual = next(t for t in c.get("/api/app/trades?days=3650").json() if t["source"] == "manual")
    assert c.delete(f"/api/app/trades/{tid}", headers=h).status_code == 400  # imported trades come back on the next sync
    assert c.delete(f"/api/app/trades/{manual['id']}", headers=h).status_code == 200
    exp = c.get("/api/app/export").json()
    assert len(exp["trades"]) == 3 and exp["journal_entries"][0]["notes"] == "après la perte"
    assert c.post("/api/app/erase", json={"confirmation": "oui"}, headers=h).status_code == 400
    assert c.post("/api/app/erase", json={"confirmation": "EFFACER MES DONNEES"}, headers=h).json()["deleted"]["trades"] == 3
    assert c.get("/api/app/trades?days=3650").json() == []


def test_free_plan_monthly_trade_cap(tmp_path):
    c, h, saas, acct = _setup(tmp_path)
    lines = ["Position,Symbol,Type,Volume,Open Time,Open Price,Close Time,Close Price,Profit"]
    for i in range(110):
        lines.append(f"{5000 + i},EURUSD,buy,0.1,2026.10.{1 + i % 20:02d} 10:{i % 60:02d}:00,1.1,2026.10.{1 + i % 20:02d} 11:00:00,1.1010,10")
    r = c.post("/api/app/import", json={"account_id": acct["id"], "filename": "m.csv", "content_base64": b64("\n".join(lines))}, headers=h).json()
    assert r["inserted"] == 100 and r["skipped_cap"] == 10


def test_plan_and_profile_are_declared_and_validated(tmp_path):
    c, h, saas, acct = _setup(tmp_path)
    assert c.get("/api/app/plan").json()["plan"]["risk_per_trade_pct"] == 1.0
    r = c.put("/api/app/plan", json={"markets": ["gold", "USTEC"], "killzones": ["London"], "risk_per_trade_pct": 0.5}, headers=h)
    assert r.json()["markets"] == ["NAS100", "XAUUSD"]
    assert c.put("/api/app/plan", json={"risk_per_trade_pct": 50}, headers=h).status_code == 422
    assert c.put("/api/app/profile", json={"level": "intermediaire", "experience_months": 18}, headers=h).json()["level"] == "intermediaire"


def test_ea_sync_token_flow(tmp_path):
    c, h, saas, acct = _setup(tmp_path)
    assert c.post(f"/api/app/accounts/{acct['id']}/sync-token", headers=h).status_code == 403  # free plan: CSV only
    op = TestClient(c.app)
    grant(op, operator(op), 1, "pro_trader")
    tok = c.post(f"/api/app/accounts/{acct['id']}/sync-token", headers=h).json()
    assert tok["token"].startswith("aej_") and tok["shown_once"]
    t0 = 1_791_000_000
    body = {"account": {"login": 123, "server": "Broker-Demo", "company": "IC", "currency": "USD", "balance": 10100, "equity": 10150, "server_utc_offset_min": 180},
            "deals": [_deal(1, 70, t0, 0, 0, 0.1, 2650), _deal(2, 70, t0 + 900, 1, 1, 0.1, 2660, 100)],
            "positions": [{"position_id": 70, "initial_sl": 2645, "initial_tp": 2665}]}
    machine = TestClient(c.app)
    assert machine.post("/api/ingest/mt5", json=body, headers={"Authorization": "Bearer faux"}).status_code == 401
    r = machine.post("/api/ingest/mt5", json=body, headers={"Authorization": f"Bearer {tok['token']}"})
    assert r.status_code == 200 and r.json()["inserted"] == 1, r.text
    t = c.get("/api/app/trades?days=3650").json()[0]
    assert t["source"] == "sync_ea" and t["r_multiple"] == pytest.approx(2.0)
    detail = c.get(f"/api/app/trades/{t['id']}").json()
    assert len(detail["executions"]) == 2
    wrong = {**body, "account": {**body["account"], "login": 999}}
    assert machine.post("/api/ingest/mt5", json=wrong, headers={"Authorization": f"Bearer {tok['token']}"}).status_code == 401
    tid = c.get("/api/app/tokens").json()[0]["id"]
    assert c.delete(f"/api/app/tokens/{tid}", headers=h).status_code == 200
    assert machine.post("/api/ingest/mt5", json=body, headers={"Authorization": f"Bearer {tok['token']}"}).status_code == 401


def test_tenants_cannot_see_each_other(tmp_path):
    c, h, saas, acct = _setup(tmp_path)
    c.post("/api/app/import", json={"account_id": acct["id"], "filename": "h.csv", "content_base64": b64(CSV)}, headers=h)
    tid = c.get("/api/app/trades?days=3650").json()[0]["id"]
    other = TestClient(c.app)
    h2 = register(other, "bob@example.com")
    assert other.get("/api/app/trades?days=3650").json() == [] and other.get("/api/app/accounts").json() == []
    assert other.get(f"/api/app/trades/{tid}").status_code == 404
    assert other.put(f"/api/app/trades/{tid}/journal", json={"notes": "x"}, headers=h2).status_code == 404
    assert other.post("/api/app/import", json={"account_id": acct["id"], "filename": "h.csv", "content_base64": b64(CSV)}, headers=h2).status_code == 404


# ---------------------------------------------------------------- investor bridge
class FakeReadMT5:
    def __init__(self):
        self.calls = []
        t0 = 1_791_000_000
        self.deals = [NS(**_deal(11, 90, t0, 1, 0, 0.2, 2650)), NS(**_deal(12, 90, t0 + 600, 0, 1, 0.2, 2640, 200))]
        self.orders = [NS(ticket=11, sl=2655.0, tp=2630.0)]

    def initialize(self, **kw):
        self.calls.append(("initialize", kw.get("login"), kw.get("password")))
        return True

    def shutdown(self):
        self.calls.append(("shutdown",))

    def last_error(self):
        return (0, "")

    def account_info(self):
        return NS(login=123, balance=10000.0, equity=10000.0, currency="USD")

    def history_deals_get(self, a, b):
        return tuple(self.deals)

    def history_orders_get(self, a, b):
        return tuple(self.orders)

    def order_send(self, req):  # must never be reached
        raise AssertionError("ordre envoyé par le pont en lecture seule")


def test_investor_bridge_reads_history_and_cannot_trade(tmp_path, monkeypatch):
    from cryptography.fernet import Fernet

    c, h, saas, acct = _setup(tmp_path)
    op = TestClient(c.app)
    grant(op, operator(op), 1, "pro_trader")
    assert c.put(f"/api/app/accounts/{acct['id']}/investor", json={"password": "lecture123"}, headers=h).status_code == 400  # no key configured
    key = Fernet.generate_key().decode()
    monkeypatch.setenv("HF_SECRET_KEY", key)
    a = c.put(f"/api/app/accounts/{acct['id']}/investor", json={"password": "lecture123"}, headers=h).json()
    assert a["access_mode"] == "investor" and a["has_secret"] and "lecture123" not in str(a)
    fake = FakeReadMT5()
    report = run_once(saas, fake, Vault(key), sleep_s=0)
    assert report == [{"account": acct["id"], "ok": True, "inserted": 1, "updated": 0}]
    assert fake.calls[0] == ("initialize", 123, "lecture123") and fake.calls[-1] == ("shutdown",)
    t = c.get("/api/app/trades?days=3650").json()[0]
    assert t["side"] == "short" and t["r_multiple"] == pytest.approx(2.0) and t["source"] == "investor"
    with pytest.raises(PermissionError):
        ReadOnlyMT5(fake).order_send({})

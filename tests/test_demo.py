"""Demonstration mode: fictitious data created through the platform's own routes, in a folder
of its own, with the mistakes the Coach is meant to find, and a banner on the site."""

import os

import pytest
from fastapi.testclient import TestClient

from hedgefund.members.site import MemberSettings
from hedgefund.web import demo
from hedgefund.web.security import AuthService
from saas_helpers import NOW, make_app, operator


def _seeded(tmp_path):
    c, eng, saas, clock = make_app(tmp_path)
    data = tmp_path / "demo"
    data.mkdir()
    creds = demo.seed(c.app, AuthService(eng.store), data, NOW)
    return c, creds, data


def test_demo_seeds_members_accounts_trades_and_a_pending_payment(tmp_path):
    c, creds, data = _seeded(tmp_path)
    assert (data / demo.MARKER).exists() and creds["trader"]["password"] in (data / demo.CREDENTIALS).read_text(encoding="utf-8")
    assert len({creds["operator"]["password"], creds["trader"]["password"], creds["prospect"]["password"]}) == 3  # random, never a default

    m = TestClient(c.app)
    assert m.post("/api/m/login", json={"email": creds["trader"]["email"], "password": creds["trader"]["password"]}).status_code == 200
    assert m.get("/api/app/me").json()["plan"] == "quant_elite"
    accounts = {a["label"]: a for a in m.get("/api/app/accounts").json()}
    assert accounts["FTMO 100K (démo)"]["prop_profile"] == "ftmo_2step" and accounts["Topstep 50K (démo)"]["prop_profile"] == "topstep_combine"
    trades = m.get("/api/app/trades?days=90&limit=500").json()
    assert len(trades) == creds["trades"]["ftmo"] + creds["trades"]["topstep"] and 30 <= creds["trades"]["ftmo"] <= 60
    assert all(t["r_multiple"] is not None for t in trades if t["account_id"] == accounts["FTMO 100K (démo)"]["id"])

    # The mistakes the Coach is built to find are in the last 30 days.
    stats = m.get(f"/api/app/stats?days=30&account={accounts['FTMO 100K (démo)']['id']}").json()
    kinds = {f["kind"] for f in stats["flags"]}
    assert {"overtrading", "revenge_trade", "size_up_after_loss", "outside_killzone", "risk_above_plan", "early_exit"} <= kinds
    assert any(t["journal"] for t in trades)

    o = TestClient(c.app)
    oh = {"X-CSRF-Token": o.post("/api/auth/login", json={"username": creds["operator"]["username"], "password": creds["operator"]["password"]}).json()["csrf"]}
    assert oh["X-CSRF-Token"]
    assert any(p["status"] == "declared" for p in o.get("/api/admin/payments").json())
    operator(c)  # the test operator still works: the demo only adds its own


def test_demo_reset_only_deletes_a_demo_folder(tmp_path):
    real = tmp_path / "var"
    real.mkdir()
    (real / "platform.db").write_text("real data")
    with pytest.raises(SystemExit):
        demo.reset(real)
    assert (real / "platform.db").exists()
    d = tmp_path / "demo"
    d.mkdir()
    (d / demo.MARKER).write_text("{}")
    demo.reset(d)
    assert not d.exists()


def test_demo_environment_never_points_at_real_data(tmp_path, monkeypatch):
    monkeypatch.setenv("HF_SAAS_DB", "postgresql+psycopg://real/db")
    monkeypatch.setenv("HF_DATA_DIR", str(tmp_path / "real"))
    monkeypatch.setenv("HF_ALLOW_REAL_TRADING", "1")
    monkeypatch.setenv("LF_WAVE_API_KEY", "x")
    monkeypatch.setenv("HF_COOKIE_SECURE", "1")
    monkeypatch.setenv("HF_PUBLIC_HOST", "trading.example.com")
    d = demo.demo_dir(tmp_path / "var")
    demo.prepare_environment(d)
    assert "HF_SAAS_DB" not in os.environ and "LF_WAVE_API_KEY" not in os.environ and "HF_PUBLIC_HOST" not in os.environ
    assert os.environ["HF_COOKIE_SECURE"] == "0"  # served over http: a secure cookie would never come back
    assert os.environ["HF_DATA_DIR"] == str(d) and os.environ["HF_FEED"] == "simulation" and os.environ["HF_ALLOW_REAL_TRADING"] == "0"
    assert MemberSettings.from_env().demo is True


def test_site_says_when_it_runs_on_demo_data(tmp_path):
    c, *_ = make_app(tmp_path)
    assert c.get("/api/site").json()["demo"] is False
    c, *_ = make_app(tmp_path / "b", member_settings=MemberSettings(demo=True))
    assert c.get("/api/site").json()["demo"] is True

"""MT5 connector (against a fake terminal), bot engine, and web platform security."""

import time
from pathlib import Path
from types import SimpleNamespace as NS

import pytest
from fastapi.testclient import TestClient

from hedgefund.bots.engine import BotEngine, EngineError
from hedgefund.bots.simfeed import SimulatedFeed
from hedgefund.bots.store import PlatformStore
from hedgefund.bots.templates import build_spec, new_bot_id, validate_bot
from hedgefund.core.clock import SimClock, SystemClock
from hedgefund.core.types import Side
from hedgefund.execution.orders import Order
from hedgefund.execution.venue import PermanentVenueError, TransientVenueError
from hedgefund.mt5.catalog import categorize
from hedgefund.mt5.client import MT5Client
from hedgefund.mt5.data import MT5Feed
from hedgefund.mt5.venue import MT5Venue
from hedgefund.web.app import WebSettings, create_app
from hedgefund.web.security import AuthService, hash_password, totp, verify_password, verify_totp
from fake_mt5 import FakeMT5  # noqa: E402  (tests/ is on sys.path under pytest)


def order(symbol="XAUUSD", side=Side.BUY, units=100.0, cid="c1"):
    return Order(cid, "bot_x", "pkg", "d", "m", symbol, side, units, "market", 2400.0, 0)


def venue(**kw):
    mt5 = FakeMT5(**kw)
    return mt5, MT5Venue(MT5Client(module=mt5), SystemClock())


# ---------------- catalogue ----------------
@pytest.mark.parametrize("name,path,cat", [
    ("XAUUSD", "", "metals"), ("GOLD.m", "", "metals"), ("NAS100", "", "indices"), ("USTEC", "", "indices"), ("US500.cash", "", "indices"),
    ("BTCUSD", "", "crypto"), ("EURUSD", "", "forex"), ("USOIL", "", "energy"), ("AAPL", "Stocks\\US", "stocks"), ("XYZ", "", "other"),
])
def test_categorize(name, path, cat):
    assert categorize(name, path) == cat


def test_lot_conversion_rounds_down():
    mt5, v = venue()
    spec = v.spec("XAUUSD")  # 1 lot = 100 oz -> 100 units per lot
    assert v.to_lots(spec, 157.0) == pytest.approx(1.57)
    assert v.to_lots(spec, 1.999) == pytest.approx(0.01)  # never rounds up
    assert v.to_units(spec, 0.5) == pytest.approx(50.0)


# ---------------- venue ----------------
def test_netting_buy_then_sell_and_magic_isolation():
    mt5, v = venue()
    mt5.positions.append(NS(ticket=1, time=0, type=0, magic=999, volume=5.0, price_open=1, price_current=1, profit=0, swap=0, symbol="XAUUSD", comment="other EA"))
    st = v.submit(order(units=150.0))
    assert st.status.value == "filled" and st.filled_qty == pytest.approx(150.0)
    fills = v.drain_fills()
    assert fills[0].qty == pytest.approx(150.0) and fills[0].fee == pytest.approx(0.75)
    assert v.positions() == {"XAUUSD": pytest.approx(150.0)}  # the other EA's 5 lots are invisible
    v.submit(order(side=Side.SELL, units=150.0, cid="c2"))
    assert v.positions() == {}
    assert mt5.sent[0]["magic"] == 770077 and mt5.sent[0]["comment"].startswith("hfc1")
    assert mt5.sent[0]["type_filling"] == 1  # IOC from the symbol's filling bitmask


def test_hedging_closes_opposite_tickets_first():
    mt5, v = venue(hedging=True)
    v.submit(order(units=200.0, cid="a"))
    v.submit(order(side=Side.SELL, units=300.0, cid="b"))  # close 2 lots long, open 1 lot short
    assert "position" in mt5.sent[1]
    assert v.positions() == {"XAUUSD": pytest.approx(-100.0)}


def test_idempotent_resubmission():
    mt5, v = venue()
    a = v.submit(order(cid="same"))
    b = v.submit(order(cid="same"))
    assert a is b and len(mt5.sent) == 1


def test_below_min_lot_and_errors():
    mt5, v = venue()
    with pytest.raises(PermanentVenueError, match="minimum"):
        v.submit(order(units=0.5))
    mt5.script = [mt5.TRADE_RETCODE_REQUOTE]
    with pytest.raises(TransientVenueError):
        v.submit(order(cid="r"))
    assert v.submit(order(cid="r")).status.value == "filled"  # retry with the same id succeeds
    mt5.script = [mt5.TRADE_RETCODE_NO_MONEY]
    with pytest.raises(PermanentVenueError, match="10019"):
        v.submit(order(cid="nm"))


def test_unknown_outcome_recovers_from_deal_history():
    mt5, v = venue()
    mt5.script = ["timeout_filled"]
    st = v.submit(order(cid="t"))
    assert st.filled_qty == pytest.approx(100.0) and len(mt5.sent) == 1  # found by comment, not resent


def test_real_account_and_algo_trading_guards():
    mt5, v = venue(real=True)
    with pytest.raises(PermanentVenueError, match="real"):
        v.submit(order())
    v.allow_real = True
    assert v.submit(order()).status.value == "filled"
    mt5.terminal.trade_allowed = False
    with pytest.raises(PermanentVenueError, match="Algo Trading"):
        v.submit(order(cid="z"))


# ---------------- data ----------------
def test_mt5_feed_converts_server_time_and_drops_forming_bar():
    mt5 = FakeMT5(server_offset_h=3)
    feed = MT5Feed(MT5Client(module=mt5))
    now = int(time.time() * 1000)
    data = feed.market_data(["XAUUSD"], "1h", 50, now)
    s = data.bars["XAUUSD"]
    assert len(s) == 49 and s.ts[-1] <= now and now - s.ts[-1] < 3_600_000
    assert feed._offset_s == 3 * 3600
    assert feed.market_open("XAUUSD", now)
    assert set(feed.specs()) == {"XAUUSD", "NAS100"}


# ---------------- bots ----------------
def _engine(tmp, feed=None, **kw):
    return BotEngine(__import__("hedgefund.config", fromlist=["load_config"]).load_config(), PlatformStore(Path(tmp) / "p.db"), feed or SimulatedFeed(), clock=SimClock(1_790_000_000_000), data_dir=Path(tmp), **kw)


def test_bot_validation_and_spec(cfg):
    feed = SimulatedFeed()
    bot = {"id": new_bot_id(), "name": "x", "strategy": "pair", "symbols": ["XAUUSD", "XAUUSD"], "timeframe": "4h", "direction": "long", "risk_per_trade_pct": 5, "max_position_pct": 40, "params": {"entry_z": 99}}
    problems = " ".join(validate_bot(bot, feed.specs()))
    for bit in ("différents", "sens", "risque", "position", "Écart"):
        assert bit in problems
    ok = {**bot, "symbols": ["XAUUSD", "XAGUSD"], "direction": "both", "risk_per_trade_pct": 0.5, "max_position_pct": 10, "params": {}}
    assert validate_bot(ok, feed.specs()) == []
    spec = build_spec(ok, feed.specs(), {"XAUUSD": 2400, "XAGUSD": 29})
    assert spec.validate({"XAUUSD", "XAGUSD"}) == [] and spec.jev.min_confidence >= 0.6


def test_engine_modes_are_isolated_and_restart_safe(tmp_path):
    eng = _engine(tmp_path)
    assert eng.mode == "simulation"
    with pytest.raises(EngineError):
        eng.set_mode("mt5", "vic")
    bot = {"id": new_bot_id(), "name": "Or", "strategy": "mean_reversion", "symbols": ["XAUUSD"], "timeframe": "1h", "direction": "both", "risk_per_trade_pct": 0.5, "max_position_pct": 20, "params": {"entry_z": 1.0, "max_er": 0.8}, "status": "stopped"}
    eng.store.save_bot(bot)
    eng.start_bot(bot["id"], "vic")
    for _ in range(300):
        eng.clock.advance(3_600_000)
        eng.step()
    nav, pos = eng.stack.portfolio.nav(), eng.stack.portfolio.positions()
    again = _engine(tmp_path)  # restart: books rebuilt, running bot resumed
    assert again.stack.portfolio.nav() == pytest.approx(nav) and again.stack.portfolio.positions() == pytest.approx(pos)
    assert bot["id"] in again.runtimes
    again.stop_bot(bot["id"], "vic", close_positions=True)
    assert again.stack.portfolio.book_positions(bot["id"]) == {}


def test_engine_refuses_real_account_without_unlock(tmp_path):
    mt5 = FakeMT5(real=True)
    client = MT5Client(module=mt5)
    store = PlatformStore(tmp_path / "p.db")
    store.set_setting("mode", "mt5")
    eng = BotEngine(__import__("hedgefund.config", fromlist=["load_config"]).load_config(), store, MT5Feed(client), mt5_client=client, data_dir=tmp_path)
    bot = {"id": new_bot_id(), "name": "Or", "strategy": "trend", "symbols": ["XAUUSD"], "timeframe": "4h", "direction": "both", "risk_per_trade_pct": 0.5, "max_position_pct": 20, "params": {}, "status": "stopped"}
    store.save_bot(bot)
    with pytest.raises(EngineError, match="réel"):
        eng.start_bot(bot["id"], "vic")
    with pytest.raises(EngineError, match="HF_ALLOW_REAL_TRADING"):
        eng.set_real_trading(True, "vic")


# ---------------- security ----------------
def test_password_hashing_and_totp():
    h = hash_password("un-mot-de-passe-long")
    assert verify_password("un-mot-de-passe-long", h) and not verify_password("autre", h)
    with pytest.raises(ValueError):
        hash_password("court")
    secret = "JBSWY3DPEHPK3PXP"
    assert totp(secret, at=59, digits=6) == totp(secret, at=31)
    assert verify_totp(secret, totp(secret, at=1_000_000), at=1_000_015)  # within the +/-1 step window
    assert not verify_totp(secret, totp(secret, at=1_000_000), at=1_000_200)  # expired
    assert not verify_totp(secret, "abc123")


@pytest.fixture
def web(tmp_path):
    eng = _engine(tmp_path)
    auth = AuthService(eng.store)
    auth.create_user("vic", "motdepasse-solide-123")
    c = TestClient(create_app(eng, auth, WebSettings(cookie_secure=False, hsts=False), start_engine=False))
    return c, eng, auth


def login(c, pw="motdepasse-solide-123", **extra):
    r = c.post("/api/auth/login", json={"username": "vic", "password": pw, **extra})
    return r, ({"X-CSRF-Token": r.json()["csrf"]} if r.status_code == 200 else {})


def test_auth_required_and_headers(web):
    c, _, _ = web
    r = c.get("/")
    assert "default-src 'self'" in r.headers["content-security-policy"] and r.headers["x-frame-options"] == "DENY"
    for path in ("/api/overview", "/api/bots", "/api/journal", "/api/symbols"):
        assert c.get(path).status_code == 401
    assert c.get("/docs").status_code == 404 and c.get("/openapi.json").status_code == 404


def test_login_lockout_and_session(web):
    c, _, _ = web
    for _ in range(5):
        assert login(c, "mauvais")[0].status_code == 401
    assert login(c)[0].status_code == 429  # locked for 15 minutes even with the right password


def test_csrf_origin_and_reauth(web):
    c, eng, _ = web
    r, H = login(c)
    assert r.status_code == 200 and "httponly" in r.headers["set-cookie"].lower() and "samesite=strict" in r.headers["set-cookie"].lower()
    bot = {"name": "Or", "strategy": "trend", "symbols": ["XAUUSD"], "timeframe": "4h", "risk_per_trade_pct": 0.5, "max_position_pct": 20}
    assert c.post("/api/bots", json=bot).status_code == 403
    assert c.post("/api/bots", json=bot, headers={**H, "Origin": "https://evil.example"}).status_code == 403
    assert c.post("/api/bots", json=bot, headers=H).status_code == 200
    assert c.post("/api/engine/kill", json={"reason": "test"}, headers=H).status_code == 200
    assert c.post("/api/engine/reset-kill", json={"reason": "vérifié", "password": "faux"}, headers=H).status_code == 403
    assert eng.stack.kill_switch.engaged
    assert c.post("/api/engine/reset-kill", json={"reason": "vérifié", "password": "motdepasse-solide-123"}, headers=H).status_code == 200
    assert not eng.stack.kill_switch.engaged


def test_totp_flow(web):
    c, _, auth = web
    _, H = login(c)
    secret = c.post("/api/auth/totp/begin", json={"password": "motdepasse-solide-123"}, headers=H).json()["secret"]
    assert c.post("/api/auth/totp/enable", json={"code": totp(secret)}, headers=H).status_code == 200
    c.cookies.clear()
    assert login(c)[0].status_code == 401  # password alone no longer enough
    assert login(c, totp=totp(secret))[0].status_code == 200


def test_bot_lifecycle_over_api(web):
    c, eng, _ = web
    _, H = login(c)
    bot = {"name": "Nasdaq/S&P", "strategy": "pair", "symbols": ["NAS100", "US500"], "timeframe": "1h", "risk_per_trade_pct": 0.5, "max_position_pct": 10}
    b = c.post("/api/bots", json=bot, headers=H).json()
    assert c.post("/api/bots", json={**bot, "symbols": ["NAS100", "INCONNU"]}, headers=H).status_code == 400
    bt = c.post(f"/api/bots/{b['id']}/backtest", json={}, headers=H).json()
    assert bt["synthetic"] and bt["bars"] > 100 and "sharpe" in bt["metrics"]
    assert c.post(f"/api/bots/{b['id']}/start", json={}, headers=H).status_code == 200
    assert c.put(f"/api/bots/{b['id']}", json=bot, headers=H).status_code == 400  # running: no edits
    assert c.delete(f"/api/bots/{b['id']}", headers=H).status_code == 400
    assert c.post(f"/api/bots/{b['id']}/stop", json={"close_positions": True}, headers=H).status_code == 200
    assert c.delete(f"/api/bots/{b['id']}", headers=H).status_code == 200
    actions = [j.get("action") for j in c.get("/api/journal").json()]
    assert {"bot_create", "bot_start", "bot_stop", "bot_delete", "login"} <= set(actions)

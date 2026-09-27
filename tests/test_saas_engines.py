"""Sprint S2: statistics engine, behaviour flags, ICT engine contracts (point in time), golden set."""

from fastapi.testclient import TestClient

from hedgefund.bots.simfeed import SimulatedFeed
from hedgefund.core.clock import SimClock
from hedgefund.saas import golden as G
from hedgefund.saas.engines import perf
from hedgefund.saas.engines.ict import analyze, analyze_data
from hedgefund.saas.service import MarketData
from saas_helpers import grant, make_app, operator, register

H = 3_600_000
T0 = 1_791_300_000_000  # 2026-10-06 ~ 16:00 UTC (a Tuesday)


def trade(i, net, r=None, *, open_min=0, dur_min=30, vol=0.1, kz="NY_AM", setup="SilverBullet", sym="XAUUSD", **kw):
    o = T0 + open_min * 60_000
    return {"id": f"t{i}", "account_id": "a", "symbol": sym, "side": "long", "volume": vol, "open_utc": o, "close_utc": o + dur_min * 60_000, "net": net,
            "r_multiple": r, "killzone": kz, "setup_model": setup, "session": "new_york", "weekday": 2, "plan_respected": True, **kw}


# ---------------------------------------------------------------- statistics
def test_wilson_and_bootstrap_are_exact_and_deterministic():
    lo, hi = perf.wilson(11, 24)
    assert (round(lo, 3), round(hi, 3)) == (0.279, 0.649)
    assert perf.wilson(0, 0) is None
    a = perf.bootstrap_mean_ci([1, -1, 2, -1, 0.5], 500)
    assert a == perf.bootstrap_mean_ci([1, -1, 2, -1, 0.5], 500)


def test_kpis_by_hand():
    rows = [trade(1, 100, 2.0), trade(2, -50, -1.0, open_min=60), trade(3, -50, -1.0, open_min=120), trade(4, 150, 3.0, open_min=180, kz="London"), trade(5, 0, 0.0, open_min=240)]
    rows.append({**trade(6, 0, None, open_min=300), "close_utc": None})  # open position: ignored
    k = perf.kpis(rows, min_trades=20, bootstrap_samples=200)
    assert (k["n"], k["wins"], k["losses"], k["breakeven"]) == (5, 2, 2, 1)
    assert k["win_rate"] == 0.4 and k["expectancy_r"] == 0.6 and k["profit_factor"] == 2.5 and k["net_total"] == 150
    assert k["max_drawdown"] == 100 and k["max_drawdown_r"] == 2.0 and k["max_consecutive_losses"] == 2
    assert k["insufficient"] and k["sample_warning"]
    kz = {g["key"]: g for g in k["by_killzone"]}
    assert kz["London"]["n"] == 1 and kz["NY_AM"]["win_rate"] == 0.25


def test_behavior_flags():
    plan = {"max_trades_per_day": 3, "revenge_minutes": 15, "size_up_factor": 1.5, "killzones": ["NY_AM"], "risk_per_trade_pct": 1.0, "max_daily_loss_pct": 2.0}
    rows = [
        trade(1, -100, -1.0, open_min=0, dur_min=20),
        trade(2, -150, -1.0, open_min=25, dur_min=10, vol=0.2),  # 5 min after a loss, double size
        trade(3, 40, 0.4, open_min=60, sl=2640.0, tp=2680.0, open_price=2650.0, close_price=2654.0, r_source="sl", risk_amount=100),  # early exit (planned 3R)
        trade(4, 10, 0.1, open_min=120, kz="Asia", plan_respected=False, r_source="sl", risk_amount=300),
    ]
    kinds = {f["kind"]: f for f in perf.behavior_flags(rows, plan, balance=10_000)}
    assert kinds["overtrading"]["value"] == 4 and kinds["revenge_trade"]["trade_ids"] == ["t1", "t2"]
    assert kinds["size_up_after_loss"]["value"] == 2.0 and kinds["outside_killzone"]["trade_ids"] == ["t4"]
    assert kinds["early_exit"]["trade_ids"] == ["t3"] and kinds["risk_above_plan"]["value"] == 3.0
    daily = [f for f in perf.behavior_flags(rows, plan, balance=10_000) if f["metric"] == "perte_journaliere_pct"]
    assert not daily  # -200 on 10 000 = 2.0 %: at the limit, not above it
    worse = rows + [trade(5, -60, -0.6, open_min=200)]
    assert [f["value"] for f in perf.behavior_flags(worse, plan, balance=10_000) if f["metric"] == "perte_journaliere_pct"] == [2.6]
    events = [{"impact": "high", "time_utc": T0 + 5 * 60_000}]
    assert any(f["kind"] == "news_window" for f in perf.behavior_flags(rows, plan, 10_000, events))


# ---------------------------------------------------------------- ICT engine
NOW = 1_791_900_000_000 - 7 * H  # 2026-10-13 03:00 NY: London Silver Bullet window


def _market(now):
    clock = SimClock(now)
    return MarketData(SimulatedFeed(clock), clock.now_ms)


def test_ict_analysis_contracts_and_rule_scores():
    a = analyze(_market(NOW), "XAUUSD", now=NOW + 15 * 60_000)
    assert a.time.silver_bullet_window and a.time.killzone == "London" and a.time.ny_time.endswith("(NY)")
    assert a.as_of <= NOW + 15 * 60_000 and a.caveats[0].startswith("PRIX SIMULÉS")
    assert a.setups, a.rejections
    s = a.setups[0]
    assert s.rule_score >= s.min_score and s.rules_passed and s.invalidation != s.entry and s.targets
    assert {d.version for d in a.definitions} == {"victor-v0"}
    assert all(g.status in ("open", "partially_mitigated", "mitigated", "inverted") for g in a.fvgs)
    out = analyze(_market(NOW), "XAUUSD", now=NOW - 4 * H)  # 23:00 NY: no entry model
    assert out.setups == [] and "hors fenêtre" in out.rejections[0]


def test_ict_analysis_never_sees_future_bars():
    now = NOW + 20 * 60_000
    feed = SimulatedFeed(SimClock(now))
    past = feed.market_data(["XAUUSD"], "1m", 600, now)
    for tf, n in (("5m", 400), ("1h", 300), ("1d", 80)):
        past.aux[tf] = feed.market_data(["XAUUSD"], tf, n, now)
    later = now + 2 * H
    fut = feed.market_data(["XAUUSD"], "1m", 600 + 120, later)
    for tf, n in (("5m", 400 + 24), ("1h", 300 + 2), ("1d", 80 + 1)):
        fut.aux[tf] = feed.market_data(["XAUUSD"], tf, n, later)
    assert fut.bars["XAUUSD"].ts[-1] > now  # the data really goes further
    a = analyze_data(past, "XAUUSD", now, spread=0.2).model_dump()
    b = analyze_data(fut, "XAUUSD", now, spread=0.2).model_dump()
    assert a == b


# ---------------------------------------------------------------- golden set
def test_synthetic_golden_set_is_matched_exactly():
    agg = G.aggregate([G.evaluate_case(c) for c in G.synthetic_set(20)])
    assert agg["fvg"]["precision"] == agg["fvg"]["recall"] == 1.0
    assert agg["swings"]["precision"] == agg["swings"]["recall"] == 1.0


def test_golden_evaluation_detects_disagreement():
    case = G.synthetic_case(5)
    case["labels"]["fvg"].append({"kind": "BISI", "t": case["bars"][50][0], "top": 9999.0, "bottom": 9998.0})
    r = G.evaluate_case(case)
    assert r["fvg"]["recall"] < 1.0 and r["fvg"]["missed"][0]["top"] == 9999.0


# ---------------------------------------------------------------- API
def test_stats_ict_and_golden_routes(tmp_path):
    c, eng, saas, clock = make_app(tmp_path, now=NOW + 15 * 60_000)
    register(c)
    assert c.get("/api/app/stats").json()["kpis"]["n"] == 0
    assert c.get("/api/app/ict/XAUUSD").status_code == 403  # free plan: no ICT analysis
    op = TestClient(c.app)
    oh = operator(op)
    grant(op, oh, 1, "starter")
    r = c.get("/api/app/ict/gold")
    assert r.status_code == 200 and r.json()["symbol"] == "XAUUSD" and r.json()["time"]["killzone"] == "London"
    assert c.get("/api/app/ict/NOPE").status_code == 404
    assert "XAUUSD" in c.get("/api/app/symbols").json()["symbols"]
    assert c.post("/api/admin/golden/snapshot", json={"symbol": "XAUUSD", "timeframe": "M5"}).status_code == 401
    snap = op.post("/api/admin/golden/snapshot", json={"symbol": "XAUUSD", "timeframe": "M5", "bars": 80}, headers=oh).json()
    assert len(snap["bars"]) == 80 and snap["synthetic"] is True
    det = G.detect(snap["bars"], "M5")
    body = {"dataset": "golden-test", "symbol": "XAUUSD", "timeframe": "M5", "as_of": snap["as_of"], "bars": snap["bars"],
            "labels": {"fvg": det["fvg"][:2], "swings": det["swings"][:3]}, "annotator": "victor", "rationale": "test"}
    assert op.post("/api/admin/golden", json=body, headers=oh).status_code == 200
    ev = op.get("/api/admin/golden/eval?dataset=golden-test", headers=oh).json()
    assert ev["cases"] == 1 and ev["summary"]["fvg"]["recall"] in (1.0, None)
    syn = op.get("/api/admin/golden/eval?dataset=synthetic-v1", headers=oh).json()
    assert syn["summary"]["fvg"]["precision"] == 1.0

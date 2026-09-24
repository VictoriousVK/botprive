import math
import sqlite3

import pytest

from hedgefund.config import ConfigError, RiskLimits, load_config
from hedgefund.core.ledger import Ledger, NullLedger
from hedgefund.core.types import Bar
from hedgefund.data.quality import check_market_data
from hedgefund.data.series import BarSeries, MarketData, Series
from hedgefund.data.sources import fetch_klines


# ---------------- ledger ----------------
def test_ledger_append_query_and_chain(ledger):
    for i in range(5):
        ledger.append("order", {"i": i}, ts=1000 + i, ref=f"r{i % 2}")
    assert ledger.count() == 5
    assert [e.payload["i"] for e in ledger.query(kind="order", ref="r0")] == [0, 2, 4]
    assert ledger.query(newest_first=True, limit=1)[0].payload["i"] == 4
    assert ledger.verify_chain() == (True, None)


def test_ledger_is_append_only(ledger):
    ledger.append("fill", {"x": 1}, ts=1)
    with pytest.raises(sqlite3.DatabaseError):
        ledger._conn.execute("UPDATE events SET payload = '{}'")
    with pytest.raises(sqlite3.DatabaseError):
        ledger._conn.execute("DELETE FROM events")


def test_ledger_detects_tampering(tmp_path):
    led = Ledger(tmp_path / "l.db")
    for i in range(3):
        led.append("nav", {"nav": 100 + i}, ts=i)
    led._conn.execute("DROP TRIGGER events_no_update")
    led._conn.execute("UPDATE events SET payload = '{\"nav\":999}' WHERE seq = 2")
    assert led.verify_chain() == (False, 2)


def test_ledger_survives_reopen(tmp_path):
    p = tmp_path / "l.db"
    a = Ledger(p)
    a.append("x", {"a": 1}, ts=1)
    a.close()
    b = Ledger(p)
    b.append("x", {"a": 2}, ts=2)
    assert b.verify_chain() == (True, None) and b.count() == 2


def test_null_ledger_interface():
    n = NullLedger()
    n.append("x", {}, ts=0)
    assert n.query() == [] and n.verify_chain() == (True, None)


# ---------------- config ----------------
def test_config_loads_and_refuses_live(tmp_path, cfg):
    assert cfg.risk.jev_min_confidence >= 0.60
    raw = (cfg.strategy_dir.parent / "fund.yaml").read_text().replace("mode: paper", "mode: live")
    (tmp_path / "config").mkdir()
    (tmp_path / "config" / "fund.yaml").write_text(raw)
    (tmp_path / "config" / "risk_limits.yaml").write_text((cfg.strategy_dir.parent / "risk_limits.yaml").read_text())
    with pytest.raises(ConfigError, match="live"):
        load_config(tmp_path / "config" / "fund.yaml")


def test_risk_limits_cannot_lower_confidence_floor(cfg):
    kw = vars(cfg.risk) | {"jev_min_confidence": 0.5}
    with pytest.raises(ConfigError, match="floor"):
        RiskLimits(**kw)


# ---------------- point-in-time data ----------------
def test_view_never_sees_the_future(data):
    s = data.bars["BTCUSDT"]
    t = s.ts[800]
    v = data.view(t)
    assert v.last_bar("BTCUSDT").ts == t
    assert v.n_bars("BTCUSDT") == 801
    assert len(v.closes("BTCUSDT", 10_000)) == 801
    f = data.funding["BTCUSDT-PERP"]
    assert all(ts <= t for ts in f.ts[: f.upto(t)])
    assert v.macro_at("stablecoin_supply_usd", t + 10 * 86_400_000) == v.macro_at("stablecoin_supply_usd", t)


def test_prefix_sum_stats_match_naive(data):
    s = data.bars["ETHUSDT"]
    i, n = 900, 120
    closes = s.close[: i]
    lr = [math.log(closes[k] / closes[k - 1]) for k in range(i - n, i)]
    mean = sum(lr) / n
    sd = math.sqrt(sum((x - mean) ** 2 for x in lr) / (n - 1))
    got = s.logret_stats(i, n)
    assert got[0] == pytest.approx(mean, rel=1e-9) and got[1] == pytest.approx(sd, rel=1e-6)
    assert s.sma(i, n) == pytest.approx(sum(closes[-n:]) / n)
    path = sum(abs(closes[k] - closes[k - 1]) for k in range(i - n, i))
    assert s.efficiency_ratio(i, n) == pytest.approx(abs(closes[-1] - closes[-1 - n]) / path)


def _bars(ts_list, px=100.0):
    return [Bar(t, px, px * 1.01, px * 0.99, px, 10.0) for t in ts_list]


def test_quality_gate_flags_stale_gaps_and_bad_ohlc():
    step = 3_600_000
    ts = [i * step for i in range(1, 60)]
    ts_gap = ts[:40] + ts[45:]
    bad = _bars(ts)
    bad[-3] = Bar(bad[-3].ts, 100, 99, 98, 100, 1)  # high < close
    d = MarketData(step, {"OK": BarSeries("OK", _bars(ts)), "GAP": BarSeries("GAP", _bars(ts_gap)), "BAD": BarSeries("BAD", bad)})
    rep = check_market_data(d, now_ms=ts[-1] + 1000)
    assert rep.blocked_symbols == {"GAP", "BAD"}
    stale = check_market_data(d, now_ms=ts[-1] + 5 * step, symbols=["OK"])
    assert not stale.ok and "stale" in stale.errors[0]


def test_series_rejects_unsorted():
    with pytest.raises(ValueError):
        Series([2, 1], [0.0, 0.0])


def test_kline_parsing_drops_open_bar():
    step = 3_600_000

    def row(open_t, c):
        return [open_t, "1", "2", "0.5", str(c), "10", open_t + step - 1, "0", 0, "0", "0", "0"]

    rows = [row(0, 1.0), row(step, 1.1), row(2 * step, 1.2)]
    calls = []

    def fake(url, params=None):
        calls.append((url, params))
        return rows

    bars = fetch_klines("BTCUSDT-PERP", "1h", 0, 2 * step + 10, fake)
    assert "fapi.binance.com/fapi/v1/klines" in calls[0][0] and calls[0][1]["symbol"] == "BTCUSDT"
    assert [b.ts for b in bars] == [step, 2 * step]  # third bar still open at end_ms
    assert bars[0].close == 1.0

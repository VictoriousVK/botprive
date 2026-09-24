"""Live public market-data sources.

Endpoints below are the publicly documented, unauthenticated REST endpoints of each provider
(as known at time of writing). They can change, rate-limit, or be geo-blocked (e.g. Binance
returns HTTP 451 from restricted jurisdictions). Every fetch records provenance (URL, params,
retrieval time) so research memos can cite "source + date", and any failure is surfaced as a
DataSourceError, which the runner treats as "no trade" (fail closed), never as zeros.

  Binance spot klines           GET https://api.binance.com/api/v3/klines
  Binance USD-M klines          GET https://fapi.binance.com/fapi/v1/klines
  Binance USD-M funding history GET https://fapi.binance.com/fapi/v1/fundingRate
  Binance USD-M OI history      GET https://fapi.binance.com/futures/data/openInterestHist
  DefiLlama stablecoin supply   GET https://stablecoins.llama.fi/stablecoincharts/all
  CoinGecko global market data  GET https://api.coingecko.com/api/v3/global
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any, Callable

import requests

from hedgefund.core.timeutil import DAY_MS, interval_ms, now_ms, utc_iso
from hedgefund.core.types import Bar
from hedgefund.data.series import BarSeries, MarketData, Series

BINANCE_SPOT = "https://api.binance.com"
BINANCE_USDM = "https://fapi.binance.com"
DEFILLAMA_STABLES = "https://stablecoins.llama.fi"
COINGECKO = "https://api.coingecko.com/api/v3"

_OI_PERIODS = {"5m", "15m", "30m", "1h", "2h", "4h", "6h", "12h", "1d"}


class DataSourceError(RuntimeError):
    pass


@dataclass
class HttpGetter:
    """GET with timeout and bounded exponential backoff on transient failures."""

    timeout_s: float = 10.0
    retries: int = 3
    backoff_s: float = 1.0
    session: requests.Session | None = None
    sleep: Callable[[float], None] = time.sleep

    def __call__(self, url: str, params: dict[str, Any] | None = None) -> Any:
        sess = self.session or requests
        last: Exception | None = None
        for attempt in range(self.retries + 1):
            try:
                r = sess.get(url, params=params, timeout=self.timeout_s)
                if r.status_code == 429 or r.status_code >= 500:
                    last = DataSourceError(f"{url} -> HTTP {r.status_code}")
                elif r.status_code != 200:
                    raise DataSourceError(f"{url} -> HTTP {r.status_code}: {r.text[:200]}")
                else:
                    return r.json()
            except requests.RequestException as e:
                last = e
            if attempt < self.retries:
                self.sleep(self.backoff_s * 2**attempt)
        raise DataSourceError(f"{url} failed after {self.retries + 1} attempts: {last}")


def _venue_symbol(symbol: str) -> tuple[str, bool]:
    """'BTCUSDT-PERP' -> ('BTCUSDT', True); 'BTCUSDT' -> ('BTCUSDT', False)."""
    if symbol.endswith("-PERP"):
        return symbol[: -len("-PERP")], True
    return symbol, False


def fetch_klines(symbol: str, interval: str, start_ms: int, end_ms: int, get: HttpGetter) -> list[Bar]:
    """Closed bars only. Bar.ts is set to the close time (Binance closeTime + 1 ms)."""
    venue_sym, perp = _venue_symbol(symbol)
    url = f"{BINANCE_USDM}/fapi/v1/klines" if perp else f"{BINANCE_SPOT}/api/v3/klines"
    limit = 1500 if perp else 1000
    bars: list[Bar] = []
    cursor = start_ms
    while cursor < end_ms:
        rows = get(url, {"symbol": venue_sym, "interval": interval, "startTime": cursor, "limit": limit})
        if not rows:
            break
        for row in rows:
            close_ts = int(row[6]) + 1
            if close_ts > end_ms:
                continue  # still-open bar
            bars.append(Bar(close_ts, float(row[1]), float(row[2]), float(row[3]), float(row[4]), float(row[5])))
        nxt = int(rows[-1][0]) + interval_ms(interval)
        if nxt <= cursor or len(rows) < limit:
            break
        cursor = nxt
    dedup = {b.ts: b for b in bars}
    return [dedup[t] for t in sorted(dedup)]


def fetch_funding(symbol: str, start_ms: int, end_ms: int, get: HttpGetter) -> Series:
    venue_sym, _ = _venue_symbol(symbol)
    out: dict[int, float] = {}
    cursor = start_ms
    while cursor < end_ms:
        rows = get(f"{BINANCE_USDM}/fapi/v1/fundingRate", {"symbol": venue_sym, "startTime": cursor, "endTime": end_ms, "limit": 1000})
        if not rows:
            break
        for row in rows:
            out[int(row["fundingTime"])] = float(row["fundingRate"])
        last = int(rows[-1]["fundingTime"])
        if last <= cursor or len(rows) < 1000:
            break
        cursor = last + 1
    return Series.from_pairs(out.items())


def fetch_open_interest(symbol: str, period: str, get: HttpGetter) -> Series:
    """Binance serves only the most recent ~30 days of OI history."""
    if period not in _OI_PERIODS:
        period = "4h"
    venue_sym, _ = _venue_symbol(symbol)
    rows = get(f"{BINANCE_USDM}/futures/data/openInterestHist", {"symbol": venue_sym, "period": period, "limit": 500})
    return Series.from_pairs((int(r["timestamp"]), float(r["sumOpenInterestValue"])) for r in rows)


def fetch_stablecoin_supply(get: HttpGetter) -> Series:
    rows = get(f"{DEFILLAMA_STABLES}/stablecoincharts/all")
    pairs = []
    for r in rows:
        total = (r.get("totalCirculatingUSD") or {}).get("peggedUSD")
        if total is None:
            continue
        pairs.append((int(r["date"]) * 1000, float(total)))
    return Series.from_pairs(pairs)


def fetch_global_snapshot(get: HttpGetter) -> dict[str, Any]:
    data = get(f"{COINGECKO}/global")["data"]
    return {
        "btc_dominance_pct": data["market_cap_percentage"].get("btc"),
        "eth_dominance_pct": data["market_cap_percentage"].get("eth"),
        "total_market_cap_usd": data["total_market_cap"].get("usd"),
        "retrieved_at": utc_iso(now_ms()),
        "source": f"{COINGECKO}/global",
    }


def load_live_market_data(
    symbols: list[str],
    interval: str,
    lookback_days: int,
    get: HttpGetter | None = None,
    end_ms: int | None = None,
) -> MarketData:
    get = get or HttpGetter()
    end = end_ms or now_ms()
    start = end - lookback_days * DAY_MS
    retrieved = utc_iso(now_ms())
    data = MarketData(interval_ms=interval_ms(interval), bars={})
    for sym in symbols:
        data.bars[sym] = BarSeries(sym, fetch_klines(sym, interval, start, end, get))
        data.provenance[sym] = {"source": "binance", "interval": interval, "retrieved_at": retrieved, "synthetic": False}
        if sym.endswith("-PERP"):
            data.funding[sym] = fetch_funding(sym, start, end, get)
            data.open_interest[sym] = fetch_open_interest(sym, interval, get)
            data.provenance[f"{sym}:funding"] = {"source": "binance-usdm", "retrieved_at": retrieved, "synthetic": False}
    data.macro["stablecoin_supply_usd"] = fetch_stablecoin_supply(get)
    data.provenance["stablecoin_supply_usd"] = {"source": "defillama", "retrieved_at": retrieved, "synthetic": False}
    return data

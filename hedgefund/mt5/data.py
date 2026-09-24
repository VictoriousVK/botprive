"""Market data from the MT5 terminal.

MT5 timestamps are in the broker's *server* time (often UTC+2/+3), not UTC. The offset is
detected from the freshest tick when a market is open, and otherwise taken from
``MT5_SERVER_UTC_OFFSET_HOURS``. Bars are converted to the platform convention: ``Bar.ts`` is
the UTC close time in ms, and the still-forming bar is dropped.
"""

from __future__ import annotations

import os
import time
from typing import Any

from hedgefund.core.timeutil import interval_ms
from hedgefund.core.types import Bar
from hedgefund.data.series import BarSeries, MarketData
from hedgefund.data.sources import DataSourceError
from hedgefund.mt5.catalog import SymbolSpec, spec_from_info
from hedgefund.mt5.client import MT5Client

TIMEFRAMES = {"15m": ("TIMEFRAME_M15", 15), "1h": ("TIMEFRAME_H1", 16385), "4h": ("TIMEFRAME_H4", 16388), "1d": ("TIMEFRAME_D1", 16408)}
MAX_OFFSET_S = 14 * 3600


class MT5Feed:
    name = "mt5"
    synthetic = False

    def __init__(self, client: MT5Client, fallback_offset_hours: float | None = None):
        self.client = client
        env = os.environ.get("MT5_SERVER_UTC_OFFSET_HOURS")
        self.fallback_offset_s = int(float(fallback_offset_hours if fallback_offset_hours is not None else (env or 0)) * 3600)
        self._offset_s: int | None = None
        self._specs: dict[str, SymbolSpec] = {}
        self._specs_at = 0.0

    # ---- catalogue ----
    def specs(self, refresh_s: float = 600) -> dict[str, SymbolSpec]:
        if not self._specs or time.time() - self._specs_at > refresh_s:
            if not self.client.ensure():
                raise DataSourceError(f"MT5 not connected: {self.client.last_error}")
            infos = self.client.call("symbols_get") or ()
            self._specs = {i.name: spec_from_info(i) for i in infos if int(getattr(i, "trade_mode", 4)) != 0}
            self._specs_at = time.time()
        return self._specs

    def spec(self, symbol: str) -> SymbolSpec:
        info = self.client.call("symbol_info", symbol)
        if info is None:
            raise DataSourceError(f"unknown symbol {symbol}: {self.client.error()}")
        if not getattr(info, "visible", True):
            self.client.call("symbol_select", symbol, True)
        spec = spec_from_info(info)
        self._specs[symbol] = spec
        return spec

    # ---- time ----
    def offset_s(self, symbols: list[str], now_ms: int) -> int:
        """Server-time minus UTC, rounded to 30 minutes, from the freshest tick."""
        now_s = now_ms / 1000
        best = None
        for s in symbols:
            tick = self.client.call("symbol_info_tick", s)
            if tick is not None and getattr(tick, "time", 0):
                best = tick.time if best is None else max(best, tick.time)
        if best is not None:
            est = best - now_s
            if -MAX_OFFSET_S <= est <= MAX_OFFSET_S:
                self._offset_s = int(round(est / 1800.0) * 1800)
        return self._offset_s if self._offset_s is not None else self.fallback_offset_s

    # ---- data ----
    def market_data(self, symbols: list[str], interval: str, count: int, now_ms: int) -> MarketData:
        if not self.client.ensure():
            raise DataSourceError(f"MT5 not connected: {self.client.last_error}")
        const_name, default = TIMEFRAMES[interval]
        tf = self.client.const(const_name, default)
        step_ms = interval_ms(interval)
        offset = self.offset_s(symbols, now_ms)
        data = MarketData(interval_ms=step_ms, bars={})
        for s in symbols:
            self.client.call("symbol_select", s, True)
            rates = self.client.call("copy_rates_from_pos", s, tf, 0, int(count))
            if rates is None or len(rates) == 0:
                raise DataSourceError(f"no MT5 history for {s}: {self.client.error()}")
            bars: list[Bar] = []
            for r in rates:
                close_ms = (int(r["time"]) - offset) * 1000 + step_ms
                if close_ms > now_ms:
                    continue  # still forming
                bars.append(Bar(close_ms, float(r["open"]), float(r["high"]), float(r["low"]), float(r["close"]), float(r["tick_volume"])))
            dedup = {b.ts: b for b in bars}
            data.bars[s] = BarSeries(s, [dedup[t] for t in sorted(dedup)])
            data.provenance[s] = {"source": "mt5", "server_offset_s": offset, "interval": interval, "synthetic": False}
        return data

    def quote(self, symbol: str) -> tuple[float, float] | None:
        tick = self.client.call("symbol_info_tick", symbol)
        if tick is None or not tick.bid or not tick.ask:
            return None
        return float(tick.bid), float(tick.ask)

    def market_open(self, symbol: str, now_ms: int, max_age_s: int = 600) -> bool:
        tick = self.client.call("symbol_info_tick", symbol)
        if tick is None or not getattr(tick, "time", 0):
            return False
        offset = self._offset_s if self._offset_s is not None else self.fallback_offset_s
        return now_ms / 1000 - (tick.time - offset) <= max_age_s

    def status(self) -> dict[str, Any]:
        return self.client.status()

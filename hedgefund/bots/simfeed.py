"""Simulated price feed for SIMULATION mode (no MT5 terminal, e.g. a Linux server or a demo).

Each symbol follows one seeded 5-minute random walk with a slowly drifting trend component and a
weak pull toward its reference price,
anchored at a fixed date and extended bar by bar, so the history is identical whenever it is
requested (point-in-time and reproducible). Every timeframe comes from that single path, as in
a real market: 15m/1h/4h/1d bars aggregate the 5-minute bars, and 1-minute bars subdivide each
5-minute bar with a seeded Brownian bridge that reproduces its open, high, low and close exactly.
Multi-timeframe strategies (ICT levels from H1/D1, entries on M1/M5) therefore see consistent
prices. Clearly labelled synthetic everywhere it is shown.
"""

from __future__ import annotations

import hashlib
import math
import random
import threading
from array import array
from typing import Any

from hedgefund.core.clock import Clock, SystemClock
from hedgefund.core.timeutil import DAY_MS, MINUTE_MS, interval_ms
from hedgefund.core.types import Bar
from hedgefund.data.series import BarSeries, MarketData
from hedgefund.mt5.catalog import SIMULATED, SymbolSpec, simulated_specs

ANCHOR_MS = 1_704_067_200_000  # 2024-01-01T00:00:00Z (day-aligned, so every timeframe aligns)
BASE_MS = 5 * MINUTE_MS
CORRELATION = 0.8  # within a category (e.g. NAS100 vs US500), as in real markets


def _seed(*parts: object) -> int:
    return int(hashlib.sha256("|".join(map(str, parts)).encode()).hexdigest()[:12], 16)


# Weak pull of the log price toward the symbol's reference level (half-life ~60 days), so that
# prices, spreads and ATRs stay in realistic proportions however long the simulation runs.
ANCHOR_PULL = math.log(2) / (60 * DAY_MS / BASE_MS)


class _Shocks:
    """Common shock per category and 5-minute bar, shared by every symbol of that category."""

    def __init__(self, category: str):
        self.rng = random.Random(_seed("common", category))
        self.values = array("d")

    def upto(self, n: int) -> array:
        while len(self.values) < n:
            self.values.append(self.rng.gauss(0, 1))
        return self.values


class _Path:
    def __init__(self, symbol: str, price: float, vol: float, shocks: _Shocks):
        self.symbol = symbol
        self.rng = random.Random(_seed(symbol, "5m"))
        self.shocks = shocks
        self.sigma = vol / math.sqrt(365 * DAY_MS / BASE_MS)
        self.o, self.h, self.l, self.c, self.v = (array("d") for _ in range(5))
        self.price = self.ref = price
        self.drift = 0.0

    def close_ts(self, i: int) -> int:
        return ANCHOR_MS + (i + 1) * BASE_MS

    def extend_to(self, close_ms: int) -> None:
        n = (close_ms - ANCHOR_MS) // BASE_MS
        if n <= len(self.c):
            return
        common = self.shocks.upto(n)
        rng, sigma, idio = self.rng, self.sigma, (1 - CORRELATION**2) ** 0.5
        o_, h_, l_, c_, v_ = self.o, self.h, self.l, self.c, self.v
        price, drift, log_ref = self.price, self.drift, math.log(self.ref)
        for i in range(len(c_), n):
            # Mostly noise: a weak, slowly varying drift (stationary sd ~4% of bar vol).
            drift = 0.995 * drift + rng.gauss(0, 0.004 * sigma)
            z = CORRELATION * common[i] + idio * rng.gauss(0, 1)
            shock = z * (2.5 if rng.random() < 0.03 else 1.0)
            o = price
            c = o * math.exp(drift - ANCHOR_PULL * (math.log(o) - log_ref) + sigma * shock)
            wick = abs(rng.gauss(0, 0.5)) * sigma
            o_.append(o)
            h_.append(max(o, c) * (1 + wick))
            l_.append(min(o, c) * (1 - wick))
            c_.append(c)
            v_.append(1000 * (1 + abs(shock)))
            price = c
        self.price, self.drift = price, drift

    # ---- views of the path in any timeframe ----
    def bars_5m(self, i0: int, i1: int) -> list[Bar]:
        return [Bar(self.close_ts(i), self.o[i], self.h[i], self.l[i], self.c[i], self.v[i]) for i in range(max(0, i0), i1)]

    def aggregate(self, step: int, last_close: int, count: int) -> list[Bar]:
        k = step // BASE_MS
        out = []
        end = (last_close - ANCHOR_MS) // BASE_MS  # 5m bars [end-k, end) form the bucket closing at last_close
        while len(out) < count and end - k >= 0:
            i0 = end - k
            out.append(Bar(self.close_ts(end - 1), self.o[i0], max(self.h[i0:end]), min(self.l[i0:end]), self.c[end - 1], sum(self.v[i0:end])))
            end -= k
        return out[::-1]

    def subdivide(self, i: int) -> list[Bar]:
        """Five 1-minute bars whose aggregate is exactly 5-minute bar i (Brownian bridge)."""
        o, h, l, c, v = self.o[i], self.h[i], self.l[i], self.c[i], self.v[i]
        rng = random.Random(_seed(self.symbol, "1m", i))
        sd = o * self.sigma / math.sqrt(5)
        pts = [o]
        for k in range(1, 5):
            left = 5 - k + 1
            p = pts[-1] + (c - pts[-1]) / left + sd * math.sqrt((left - 1) / left) * rng.gauss(0, 1)
            pts.append(min(max(p, l), h))
        pts.append(c)
        start = self.close_ts(i) - BASE_MS
        subs = []
        for j in range(5):
            a, b = pts[j], pts[j + 1]
            wick = abs(rng.gauss(0, 0.4)) * sd
            subs.append([start + (j + 1) * MINUTE_MS, a, min(h, max(a, b) + wick), max(l, min(a, b) - wick), b, v / 5])
        max(subs, key=lambda s: max(s[1], s[4]))[2] = h
        min(subs, key=lambda s: min(s[1], s[4]))[3] = l
        return [Bar(*s) for s in subs]


_LOCK = threading.RLock()
_PATHS: dict[str, _Path] = {}  # deterministic, so shared by every feed instance in the process
_SHOCKS: dict[str, _Shocks] = {}


class SimulatedFeed:
    name = "simulation"
    synthetic = True

    def __init__(self, clock: Clock | None = None) -> None:
        self._specs = simulated_specs()
        self._ref = {s[0]: (s[3], s[4], s[2]) for s in SIMULATED}
        self.clock = clock or SystemClock()  # the engine hands over its own clock

    def specs(self, refresh_s: float = 0) -> dict[str, SymbolSpec]:
        return dict(self._specs)

    def spec(self, symbol: str) -> SymbolSpec:
        return self._specs[symbol]

    def _path(self, symbol: str) -> _Path:
        p = _PATHS.get(symbol)
        if p is None:
            price, vol, category = self._ref[symbol]
            shocks = _SHOCKS.setdefault(category, _Shocks(category))
            p = _PATHS[symbol] = _Path(symbol, price, vol, shocks)
        return p

    def _bars(self, symbol: str, interval: str, count: int, now_ms: int) -> list[Bar]:
        step = interval_ms(interval)
        p = self._path(symbol)
        if step >= BASE_MS:
            last_close = now_ms // step * step
            p.extend_to(last_close)
            if step == BASE_MS:
                n = (last_close - ANCHOR_MS) // BASE_MS
                return p.bars_5m(n - count, n)
            return p.aggregate(step, last_close, count)
        # 1-minute bars: subdivide the 5-minute bars, including the one still forming (only
        # its sub-bars that have already closed are returned).
        p.extend_to(now_ms // BASE_MS * BASE_MS + BASE_MS)
        n = (now_ms // BASE_MS * BASE_MS + BASE_MS - ANCHOR_MS) // BASE_MS
        per = BASE_MS // step
        out: list[Bar] = []
        for i in range(max(0, n - count // per - 2), n):
            out.extend(b for b in p.subdivide(i) if b.ts <= now_ms)
        return out[-count:]

    def market_data(self, symbols: list[str], interval: str, count: int, now_ms: int) -> MarketData:
        data = MarketData(interval_ms=interval_ms(interval), bars={})
        with _LOCK:
            for s in symbols:
                data.bars[s] = BarSeries(s, self._bars(s, interval, count, now_ms))
                data.provenance[s] = {"source": "simulation", "synthetic": True}
        return data

    def quote(self, symbol: str) -> tuple[float, float] | None:
        """Last closed 1-minute price at the clock's current time."""
        with _LOCK:
            bars = self._bars(symbol, "1m", 1, self.clock.now_ms())
        price = bars[-1].close if bars else self._ref[symbol][0]
        spec = self._specs[symbol]
        half = spec.spread_points * spec.point / 2
        return price - half, price + half

    def market_open(self, symbol: str, now_ms: int, max_age_s: int = 600) -> bool:
        return True

    def status(self) -> dict[str, Any]:
        return {"connected": True, "account_type": "simulation", "server": "simulation", "currency": "USD", "algo_trading_enabled": True, "margin_mode": "netting"}

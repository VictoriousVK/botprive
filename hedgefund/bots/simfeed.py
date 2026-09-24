"""Simulated price feed for SIMULATION mode (no MT5 terminal, e.g. a Linux server or a demo).

Each symbol follows a seeded random walk with a slowly drifting trend component, anchored at
a fixed date and extended bar by bar, so the history is identical whenever it is requested
(point-in-time and reproducible). Clearly labelled synthetic everywhere it is shown.
"""

from __future__ import annotations

import hashlib
import math
import random
from typing import Any

from hedgefund.core.timeutil import DAY_MS, interval_ms
from hedgefund.core.types import Bar
from hedgefund.data.series import BarSeries, MarketData
from hedgefund.mt5.catalog import SIMULATED, SymbolSpec, simulated_specs

ANCHOR_MS = 1_704_067_200_000  # 2024-01-01T00:00:00Z


CORRELATION = 0.8  # within a category (e.g. NAS100 vs US500), as in real markets


def _common_shock(category: str, interval: str, t: int) -> float:
    seed = int(hashlib.sha256(f"{category}|{interval}|{t}".encode()).hexdigest()[:12], 16)
    return random.Random(seed).gauss(0, 1)


class _Path:
    def __init__(self, symbol: str, interval: str, price: float, vol: float, category: str):
        seed = int(hashlib.sha256(f"{symbol}|{interval}".encode()).hexdigest()[:12], 16)
        self.rng = random.Random(seed)
        self.category, self.interval = category, interval
        self.step = interval_ms(interval)
        self.bpy = 365 * DAY_MS / self.step
        self.sigma = vol / math.sqrt(self.bpy)
        self.bars: list[Bar] = []
        self.price = price
        self.drift = 0.0

    def extend_to(self, close_ms: int) -> None:
        t = self.bars[-1].ts if self.bars else ANCHOR_MS
        while t + self.step <= close_ms:
            t += self.step
            # Mostly noise: a weak, slowly varying drift (stationary sd ~4% of bar vol).
            self.drift = 0.995 * self.drift + self.rng.gauss(0, 0.004 * self.sigma)
            z = CORRELATION * _common_shock(self.category, self.interval, t) + (1 - CORRELATION**2) ** 0.5 * self.rng.gauss(0, 1)
            shock = z * (2.5 if self.rng.random() < 0.03 else 1.0)
            o = self.price
            c = o * math.exp(self.drift + self.sigma * shock)
            wick = abs(self.rng.gauss(0, 0.5)) * self.sigma
            self.bars.append(Bar(t, o, max(o, c) * (1 + wick), min(o, c) * (1 - wick), c, 1000 * (1 + abs(shock))))
            self.price = c


class SimulatedFeed:
    name = "simulation"
    synthetic = True

    def __init__(self) -> None:
        self._specs = simulated_specs()
        self._ref = {s[0]: (s[3], s[4], s[2]) for s in SIMULATED}
        self._paths: dict[tuple[str, str], _Path] = {}

    def specs(self, refresh_s: float = 0) -> dict[str, SymbolSpec]:
        return dict(self._specs)

    def spec(self, symbol: str) -> SymbolSpec:
        return self._specs[symbol]

    def _path(self, symbol: str, interval: str) -> _Path:
        key = (symbol, interval)
        if key not in self._paths:
            price, vol, category = self._ref[symbol]
            self._paths[key] = _Path(symbol, interval, price, vol, category)
        return self._paths[key]

    def market_data(self, symbols: list[str], interval: str, count: int, now_ms: int) -> MarketData:
        step = interval_ms(interval)
        last_close = now_ms // step * step
        data = MarketData(interval_ms=step, bars={})
        for s in symbols:
            p = self._path(s, interval)
            p.extend_to(last_close)
            upto = [b for b in p.bars[-(count + 5):] if b.ts <= now_ms][-count:]
            data.bars[s] = BarSeries(s, upto)
            data.provenance[s] = {"source": "simulation", "synthetic": True}
        return data

    def quote(self, symbol: str) -> tuple[float, float] | None:
        paths = [p for (s, _), p in self._paths.items() if s == symbol and p.bars]
        price = paths[0].bars[-1].close if paths else self._ref[symbol][0]
        spec = self._specs[symbol]
        half = spec.spread_points * spec.point / 2
        return price - half, price + half

    def market_open(self, symbol: str, now_ms: int, max_age_s: int = 600) -> bool:
        return True

    def status(self) -> dict[str, Any]:
        return {"connected": True, "account_type": "simulation", "server": "simulation", "currency": "USD", "algo_trading_enabled": True, "margin_mode": "netting"}

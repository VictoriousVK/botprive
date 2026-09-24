"""Point-in-time market data.

``MarketData`` holds full histories. ``MarketView`` is a read-only window that can only see
records with ``ts <= t``; strategies, Jev states and features are built exclusively from views,
which makes look-ahead structurally impossible. Rolling statistics use prefix sums so each
feature is O(1) per bar.
"""

from __future__ import annotations

import math
from bisect import bisect_right
from dataclasses import dataclass, field
from itertools import accumulate
from typing import Iterable

from hedgefund.core.types import Bar


class Series:
    """Sorted (ts, value) series, e.g. funding rates, open interest, stablecoin supply."""

    __slots__ = ("ts", "values")

    def __init__(self, ts: Iterable[int], values: Iterable[float]):
        self.ts = list(ts)
        self.values = list(values)
        if len(self.ts) != len(self.values):
            raise ValueError("ts/values length mismatch")
        if any(b <= a for a, b in zip(self.ts, self.ts[1:])):
            raise ValueError("series timestamps must be strictly increasing")

    @classmethod
    def from_pairs(cls, pairs: Iterable[tuple[int, float]]) -> "Series":
        pairs = sorted(pairs)
        return cls([p[0] for p in pairs], [p[1] for p in pairs])

    def __len__(self) -> int:
        return len(self.ts)

    def upto(self, t: int) -> int:
        return bisect_right(self.ts, t)

    def last(self, t: int) -> tuple[int, float] | None:
        i = self.upto(t)
        return (self.ts[i - 1], self.values[i - 1]) if i else None

    def window(self, t: int, n: int) -> list[float]:
        i = self.upto(t)
        return self.values[max(0, i - n) : i]

    def between(self, t0: int, t1: int) -> list[tuple[int, float]]:
        """Records with t0 < ts <= t1."""
        i0, i1 = self.upto(t0), self.upto(t1)
        return list(zip(self.ts[i0:i1], self.values[i0:i1]))

    def value_at_or_before(self, t: int) -> float | None:
        last = self.last(t)
        return last[1] if last else None


class BarSeries:
    __slots__ = ("symbol", "ts", "open", "high", "low", "close", "volume", "_lr", "_cs1", "_cs2", "_csc", "_csabs", "_cstr", "_csv")

    def __init__(self, symbol: str, bars: Iterable[Bar]):
        bars = list(bars)
        self.symbol = symbol
        self.ts = [b.ts for b in bars]
        if any(b <= a for a, b in zip(self.ts, self.ts[1:])):
            raise ValueError(f"{symbol}: bar timestamps must be strictly increasing")
        self.open = [b.open for b in bars]
        self.high = [b.high for b in bars]
        self.low = [b.low for b in bars]
        self.close = [b.close for b in bars]
        self.volume = [b.volume for b in bars]
        c = self.close
        lr = [0.0] + [math.log(c[i] / c[i - 1]) for i in range(1, len(c))]
        self._lr = lr
        self._cs1 = [0.0, *accumulate(lr)]
        self._cs2 = [0.0, *accumulate(x * x for x in lr)]
        self._csc = [0.0, *accumulate(c)]
        self._csabs = [0.0, *accumulate([0.0] + [abs(c[i] - c[i - 1]) for i in range(1, len(c))])]
        tr = [
            (max(self.high[i], c[i - 1] if i else c[i]) - min(self.low[i], c[i - 1] if i else c[i])) / c[i]
            for i in range(len(c))
        ]
        self._cstr = [0.0, *accumulate(tr)]
        self._csv = [0.0, *accumulate(v * p for v, p in zip(self.volume, c))]

    def __len__(self) -> int:
        return len(self.ts)

    def upto(self, t: int) -> int:
        return bisect_right(self.ts, t)

    def bar(self, i: int) -> Bar:
        return Bar(self.ts[i], self.open[i], self.high[i], self.low[i], self.close[i], self.volume[i])

    def bars(self) -> list[Bar]:
        return [self.bar(i) for i in range(len(self))]

    # ---- O(1) rolling statistics over the n bars ending at index i (exclusive) ----
    def logret_stats(self, i: int, n: int) -> tuple[float, float] | None:
        """Mean and sample std of the last n log returns ending before index i."""
        lo = i - n
        if lo < 1 or n < 2:
            return None
        s1 = self._cs1[i] - self._cs1[lo]
        s2 = self._cs2[i] - self._cs2[lo]
        mean = s1 / n
        var = max((s2 - s1 * s1 / n) / (n - 1), 0.0)
        return mean, math.sqrt(var)

    def sma(self, i: int, n: int) -> float | None:
        if i - n < 0 or n <= 0:
            return None
        return (self._csc[i] - self._csc[i - n]) / n

    def efficiency_ratio(self, i: int, n: int) -> float | None:
        lo = i - n
        if lo < 1:
            return None
        path = self._csabs[i] - self._csabs[lo]
        net = abs(self.close[i - 1] - self.close[lo - 1])
        return net / path if path > 0 else 0.0

    def atr_pct(self, i: int, n: int) -> float | None:
        if i - n < 1:
            return None
        return (self._cstr[i] - self._cstr[i - n]) / n

    def notional_volume(self, i: int, n: int) -> float | None:
        if i - n < 0 or n <= 0:
            return None
        return self._csv[i] - self._csv[i - n]

    def last_logret(self, i: int) -> float | None:
        return self._lr[i - 1] if i >= 2 else None


@dataclass
class MarketData:
    interval_ms: int
    bars: dict[str, BarSeries]
    funding: dict[str, Series] = field(default_factory=dict)  # perp symbol -> funding rate per period
    open_interest: dict[str, Series] = field(default_factory=dict)  # perp symbol -> OI notional (quote)
    macro: dict[str, Series] = field(default_factory=dict)  # e.g. "stablecoin_supply_usd"
    provenance: dict[str, dict] = field(default_factory=dict)

    @property
    def synthetic(self) -> bool:
        return any(p.get("synthetic") for p in self.provenance.values())

    def symbols(self) -> list[str]:
        return sorted(self.bars)

    def timeline(self, symbols: Iterable[str] | None = None) -> list[int]:
        """Bar close timestamps present for every requested symbol."""
        syms = list(symbols) if symbols is not None else self.symbols()
        common = set(self.bars[syms[0]].ts)
        for s in syms[1:]:
            common &= set(self.bars[s].ts)
        return sorted(common)

    def view(self, t: int) -> "MarketView":
        return MarketView(self, t)


class MarketView:
    """Everything knowable at time ``t``."""

    def __init__(self, data: MarketData, t: int):
        self.data = data
        self.t = t
        self._idx: dict[str, int] = {}

    def _i(self, symbol: str) -> int:
        i = self._idx.get(symbol)
        if i is None:
            i = self.data.bars[symbol].upto(self.t)
            self._idx[symbol] = i
        return i

    def has(self, symbol: str, min_bars: int = 1) -> bool:
        return symbol in self.data.bars and self._i(symbol) >= min_bars

    def n_bars(self, symbol: str) -> int:
        return self._i(symbol) if symbol in self.data.bars else 0

    def last_bar(self, symbol: str) -> Bar | None:
        i = self._i(symbol)
        return self.data.bars[symbol].bar(i - 1) if i else None

    def last_close(self, symbol: str) -> float | None:
        i = self._i(symbol)
        return self.data.bars[symbol].close[i - 1] if i else None

    def closes(self, symbol: str, n: int) -> list[float]:
        i = self._i(symbol)
        return self.data.bars[symbol].close[max(0, i - n) : i]

    def highs(self, symbol: str, n: int) -> list[float]:
        i = self._i(symbol)
        return self.data.bars[symbol].high[max(0, i - n) : i]

    def close_ago(self, symbol: str, k: int) -> float | None:
        """Close k bars before the latest (k=0 is the latest)."""
        i = self._i(symbol)
        j = i - 1 - k
        return self.data.bars[symbol].close[j] if j >= 0 else None

    def momentum(self, symbol: str, n: int) -> float | None:
        c0 = self.close_ago(symbol, n)
        c1 = self.last_close(symbol)
        return c1 / c0 - 1.0 if c0 and c1 else None

    def logret_stats(self, symbol: str, n: int) -> tuple[float, float] | None:
        return self.data.bars[symbol].logret_stats(self._i(symbol), n)

    def sma(self, symbol: str, n: int) -> float | None:
        return self.data.bars[symbol].sma(self._i(symbol), n)

    def efficiency_ratio(self, symbol: str, n: int) -> float | None:
        return self.data.bars[symbol].efficiency_ratio(self._i(symbol), n)

    def atr_pct(self, symbol: str, n: int) -> float | None:
        return self.data.bars[symbol].atr_pct(self._i(symbol), n)

    def notional_volume(self, symbol: str, n: int) -> float | None:
        return self.data.bars[symbol].notional_volume(self._i(symbol), n)

    def last_logret(self, symbol: str) -> float | None:
        return self.data.bars[symbol].last_logret(self._i(symbol))

    def funding(self, symbol: str, n: int) -> list[float]:
        s = self.data.funding.get(symbol)
        return s.window(self.t, n) if s else []

    def open_interest(self, symbol: str, n: int) -> list[float]:
        s = self.data.open_interest.get(symbol)
        return s.window(self.t, n) if s else []

    def open_interest_at(self, symbol: str, t: int) -> float | None:
        s = self.data.open_interest.get(symbol)
        return s.value_at_or_before(min(t, self.t)) if s else None

    def macro(self, name: str, n: int) -> list[float]:
        s = self.data.macro.get(name)
        return s.window(self.t, n) if s else []

    def macro_at(self, name: str, t: int) -> float | None:
        s = self.data.macro.get(name)
        return s.value_at_or_before(min(t, self.t)) if s else None

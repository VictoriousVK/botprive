"""Data quality gates. A failed gate blocks new risk for the affected symbols (fail closed)."""

from __future__ import annotations

from dataclasses import dataclass, field

from hedgefund.data.series import MarketData


@dataclass
class QualityReport:
    ok: bool = True
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    blocked_symbols: set[str] = field(default_factory=set)

    def error(self, symbol: str, msg: str) -> None:
        self.ok = False
        self.errors.append(f"{symbol}: {msg}")
        self.blocked_symbols.add(symbol)

    def to_dict(self) -> dict:
        return {"ok": self.ok, "errors": self.errors, "warnings": self.warnings, "blocked": sorted(self.blocked_symbols)}


def check_market_data(
    data: MarketData,
    now_ms: int,
    symbols: list[str] | None = None,
    max_staleness_bars: int = 2,
    max_gap_bars: int = 1,
    outlier_move: float = 0.25,
) -> QualityReport:
    rep = QualityReport()
    step = data.interval_ms
    for sym in symbols or data.symbols():
        s = data.bars.get(sym)
        if s is None or len(s) == 0:
            rep.error(sym, "no bars")
            continue
        if now_ms - s.ts[-1] > max_staleness_bars * step:
            rep.error(sym, f"stale: last bar {(now_ms - s.ts[-1]) / step:.1f} bars old")
        gaps = sum(1 for a, b in zip(s.ts, s.ts[1:]) if b - a > max_gap_bars * step)
        if gaps:
            rep.warnings.append(f"{sym}: {gaps} gap(s) in history")
            # Only a gap in the most recent window blocks trading.
            recent = s.ts[-50:]
            if any(b - a > max_gap_bars * step for a, b in zip(recent, recent[1:])):
                rep.error(sym, "gap in last 50 bars")
        for i in range(max(0, len(s) - 50), len(s)):
            o, h, l, c, v = s.open[i], s.high[i], s.low[i], s.close[i], s.volume[i]
            if min(o, h, l, c) <= 0 or v < 0:
                rep.error(sym, f"non-positive price/volume at {s.ts[i]}")
                break
            if h < max(o, c) - 1e-9 or l > min(o, c) + 1e-9:
                rep.error(sym, f"OHLC inconsistent at {s.ts[i]}")
                break
            if i and abs(c / s.close[i - 1] - 1) > outlier_move:
                rep.warnings.append(f"{sym}: {abs(c / s.close[i - 1] - 1):.0%} single-bar move at {s.ts[i]} (verify)")
        if sym.endswith("-PERP"):
            f = data.funding.get(sym)
            if f is None or len(f) == 0:
                rep.warnings.append(f"{sym}: no funding history")
            elif now_ms - f.ts[-1] > 16 * 3_600_000:
                rep.warnings.append(f"{sym}: funding stale")
    return rep

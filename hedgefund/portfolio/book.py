"""Portfolio accounting with per-strategy sub-books.

Linear instruments are marked as ``cash + qty * mark`` (full collateral, no margin model).
Each strategy has its own book so PnL, fees and funding are attributable; the venue sees the
sum of books, and reconciliation compares that sum with venue positions.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from hedgefund.config import Instrument

EPS = 1e-12


@dataclass
class Position:
    qty: float = 0.0
    avg_price: float = 0.0
    opened_ts: int | None = None

    def apply(self, dq: float, price: float, ts: int) -> float:
        """Apply a signed quantity change; returns realized PnL (before fees)."""
        realized = 0.0
        q = self.qty
        if abs(q) < EPS or q * dq > 0:  # opening or adding
            new_q = q + dq
            self.avg_price = (abs(q) * self.avg_price + abs(dq) * price) / abs(new_q)
            if abs(q) < EPS:
                self.opened_ts = ts
            self.qty = new_q
            return 0.0
        closing = min(abs(dq), abs(q))
        realized = closing * (price - self.avg_price) * (1 if q > 0 else -1)
        new_q = q + dq
        if abs(new_q) < EPS:
            self.qty, self.avg_price, self.opened_ts = 0.0, 0.0, None
        elif new_q * q < 0:  # flipped
            self.qty, self.avg_price, self.opened_ts = new_q, price, ts
        else:
            self.qty = new_q
        return realized


@dataclass
class Book:
    strategy_id: str
    positions: dict[str, Position] = field(default_factory=dict)
    cashflow: float = 0.0
    fees: float = 0.0
    funding: float = 0.0
    realized: float = 0.0
    realized_events: list[tuple[int, str, float]] = field(default_factory=list)

    def pos(self, symbol: str) -> Position:
        return self.positions.setdefault(symbol, Position())


@dataclass(frozen=True)
class PositionInfo:
    qty: float
    notional: float
    avg_price: float
    opened_ts: int | None


class Portfolio:
    def __init__(self, starting_cash: float, instruments: dict[str, Instrument]):
        self.starting_cash = float(starting_cash)
        self.instruments = instruments
        self.books: dict[str, Book] = {}
        self.marks: dict[str, float] = {}
        self.fill_notional = 0.0

    def book(self, strategy_id: str) -> Book:
        b = self.books.get(strategy_id)
        if b is None:
            b = self.books[strategy_id] = Book(strategy_id)
        return b

    # ---- events ----
    def apply_fill(self, strategy_id: str, symbol: str, signed_qty: float, price: float, fee: float, ts: int) -> float:
        b = self.book(strategy_id)
        realized = b.pos(symbol).apply(signed_qty, price, ts)
        b.cashflow -= signed_qty * price + fee
        b.fees += fee
        b.realized += realized
        if realized:
            b.realized_events.append((ts, symbol, realized))
        self.fill_notional += abs(signed_qty * price)
        self.marks.setdefault(symbol, price)
        return realized

    def apply_funding(self, symbol: str, rate: float, mark: float) -> float:
        """Perp funding: longs pay shorts when rate > 0. Returns total paid (+) / received (-)."""
        total = 0.0
        for b in self.books.values():
            p = b.positions.get(symbol)
            if p and abs(p.qty) > EPS:
                pay = p.qty * mark * rate
                b.cashflow -= pay
                b.funding += pay
                total += pay
        return total

    def mark(self, prices: dict[str, float]) -> None:
        self.marks.update({k: v for k, v in prices.items() if v and v > 0})

    # ---- views ----
    def positions(self) -> dict[str, float]:
        agg: dict[str, float] = {}
        for b in self.books.values():
            for s, p in b.positions.items():
                if abs(p.qty) > EPS:
                    agg[s] = agg.get(s, 0.0) + p.qty
        return {s: q for s, q in agg.items() if abs(q) > EPS}

    def book_positions(self, strategy_id: str) -> dict[str, PositionInfo]:
        b = self.books.get(strategy_id)
        if b is None:
            return {}
        return {
            s: PositionInfo(p.qty, p.qty * self.marks.get(s, p.avg_price), p.avg_price, p.opened_ts)
            for s, p in b.positions.items()
            if abs(p.qty) > EPS
        }

    def book_equity(self, strategy_id: str) -> float:
        b = self.books.get(strategy_id)
        if b is None:
            return 0.0
        return b.cashflow + sum(p.qty * self.marks.get(s, p.avg_price) for s, p in b.positions.items())

    def nav(self) -> float:
        return self.starting_cash + sum(self.book_equity(sid) for sid in self.books)

    def notional(self, symbol: str, qty: float) -> float:
        return qty * self.marks.get(symbol, 0.0)

    def exposures(self, positions: dict[str, float] | None = None) -> dict[str, float]:
        pos = self.positions() if positions is None else positions
        gross = net = 0.0
        clusters: dict[str, float] = {}
        for s, q in pos.items():
            n = q * self.marks.get(s, 0.0)
            gross += abs(n)
            net += n
            c = self.instruments[s].cluster if s in self.instruments else "unknown"
            clusters[c] = clusters.get(c, 0.0) + n
        return {"gross": gross, "net": net, **{f"cluster:{k}": v for k, v in clusters.items()}}

    def snapshot(self) -> dict:
        return {
            "nav": self.nav(),
            "positions": self.positions(),
            "books": {
                sid: {
                    "equity": self.book_equity(sid),
                    "fees": b.fees,
                    "funding": b.funding,
                    "realized": b.realized,
                    "positions": {s: p.qty for s, p in b.positions.items() if abs(p.qty) > EPS},
                }
                for sid, b in self.books.items()
            },
        }

"""ICT analysis modules, ported from the ICT Ultimate Pro v6.20 EA (MQL5).

Same algorithms, same defaults: market structure (fractal swings, break-of-structure bias,
market structure shift), fair value gaps (with mitigation and balanced price ranges), the
liquidity map (PDH/PDL, PWH/PWL, IPDA 20/40/60, Asia/London/NY AM sessions, HTF and LTF swings,
equal highs/lows, M1 swings), reference levels (midnight and 07:30 true opens, opening ranges,
TBR, NDOG/NWOG, ADR), and the two setups: Silver Bullet (M5) and Macro Breaker (M1).

Differences from the EA, all forced by the platform (see docs/PLATFORM.md):
- Bars are indexed exactly like MQL5 series (index 1 = last closed bar), but index 0 - the bar
  still forming in MT5 - is a flat placeholder at the last close: decisions happen on closes.
- Times are UTC; New York time comes from ``ict_clock`` (no broker-server offset to guess).
- ask/bid are the last close +/- half the symbol's spread; the broker stops level is the spread.
"""

from __future__ import annotations

from dataclasses import dataclass, field, replace

from hedgefund.core.timeutil import HOUR_MS, MINUTE_MS
from hedgefund.data.series import MarketView
from hedgefund.strategy.library import ict_clock as clk

BUY, SELL = 1, -1


def dir_str(d: int) -> str:
    return "achat" if d == BUY else "vente" if d == SELL else "aucun"


# ======================================================================
# Bars in MQL5 series order
# ======================================================================
class Rates:
    """``t`` = bar OPEN time (UTC ms) like MqlRates.time; index 0 = placeholder forming bar."""

    __slots__ = ("t", "o", "h", "l", "c", "n", "step", "_atr")

    def __init__(self, t: list[int], o: list[float], h: list[float], l: list[float], c: list[float], step: int):
        self.t, self.o, self.h, self.l, self.c = t, o, h, l, c
        self.n = len(t)
        self.step = step
        self._atr: dict[int, list[float]] = {}

    @classmethod
    def from_view(cls, view: MarketView | None, symbol: str, max_bars: int) -> "Rates | None":
        if view is None or not view.has(symbol, 2):
            return None
        ser, n = view.series(symbol)
        lo = max(0, n - max_bars)
        step = view.data.interval_ms
        last = ser.close[n - 1]
        return cls(
            [ser.ts[n - 1]] + [ts - step for ts in reversed(ser.ts[lo:n])],
            [last] + ser.open[lo:n][::-1],
            [last] + ser.high[lo:n][::-1],
            [last] + ser.low[lo:n][::-1],
            [last] + ser.close[lo:n][::-1],
            step,
        )

    def body(self, i: int) -> float:
        return abs(self.c[i] - self.o[i])

    def atr(self, i: int, period: int = 14) -> float:
        """MT5 iATR (simple average of true ranges) at series index i; 0 if not enough bars."""
        s = self._atr.get(period)
        if s is None:
            s = self._atr[period] = _atr_series(self, period)
        return s[i] if 0 <= i < len(s) else 0.0


def _atr_series(r: Rates, period: int) -> list[float]:
    n = r.n
    tr = [0.0] * n
    for j in range(n):
        if j + 1 < n:
            pc = r.c[j + 1]
            tr[j] = max(r.h[j], pc) - min(r.l[j], pc)
        else:
            tr[j] = r.h[j] - r.l[j]
    out = [0.0] * n
    acc = 0.0
    for j in range(n - 1, -1, -1):  # oldest to newest
        acc += tr[j]
        if j + period < n:
            acc -= tr[j + period]
        if n - j >= period:
            out[j] = acc / period
    return out


# ======================================================================
# Market structure (CMarketStructure)
# ======================================================================
def is_swing_high(r: Rates, i: int, s: int) -> bool:
    if i - s < 1 or i + s >= r.n:
        return False
    return all(not (r.h[i] <= r.h[i - k] or r.h[i] < r.h[i + k]) for k in range(1, s + 1))


def is_swing_low(r: Rates, i: int, s: int) -> bool:
    if i - s < 1 or i + s >= r.n:
        return False
    return all(not (r.l[i] >= r.l[i - k] or r.l[i] > r.l[i + k]) for k in range(1, s + 1))


def structure_bias(r: Rates, s: int) -> int:
    """Direction of the last break of structure, iterating chronologically."""
    bias, cur_sh, cur_sl = 0, 0.0, 0.0
    for k in range(r.n - s - 2, 0, -1):
        i = k + s
        if is_swing_high(r, i, s):
            cur_sh = r.h[i]
        if is_swing_low(r, i, s):
            cur_sl = r.l[i]
        if cur_sh > 0 and r.c[k] > cur_sh:
            bias, cur_sh = BUY, 0.0
        if cur_sl > 0 and r.c[k] < cur_sl:
            bias, cur_sl = SELL, 0.0
    return bias


def last_swing_low_below(r: Rates, s: int, price: float, max_look: int) -> float:
    for i in range(s + 1, min(r.n - s - 1, max_look) + 1):
        if is_swing_low(r, i, s) and r.l[i] < price:
            return r.l[i]
    return 0.0


def last_swing_high_above(r: Rates, s: int, price: float, max_look: int) -> float:
    for i in range(s + 1, min(r.n - s - 1, max_look) + 1):
        if is_swing_high(r, i, s) and r.h[i] > price:
            return r.h[i]
    return 0.0


@dataclass
class MSS:
    bar_idx: int
    bar_time: int
    broken_level: float
    disp_body: float
    leg_extreme: float
    leg_extreme_idx: int


def find_mss(d: int, r: Rates, extreme_idx: int, extreme: float, max_bars_after: int, min_range_atr: float, disp_body_atr: float, atr: float, s: int) -> MSS | None:
    """Market structure shift after a sweep: close beyond the last opposite swing before the
    sweep extreme, with a displacement candle."""
    if extreme_idx < 2 or extreme_idx >= r.n - s - 1 or atr <= 0:
        return None
    level = 0.0
    for i in range(extreme_idx + 1, min(r.n - s - 1, extreme_idx + 60) + 1):
        if d == BUY and is_swing_high(r, i, s) and r.h[i] >= extreme + min_range_atr * atr:
            level = r.h[i]
            break
        if d == SELL and is_swing_low(r, i, s) and r.l[i] <= extreme - min_range_atr * atr:
            level = r.l[i]
            break
    if level == 0:
        for i in range(extreme_idx + 1, min(r.n - 1, extreme_idx + 10) + 1):
            if d == BUY:
                level = r.h[i] if level == 0 else max(level, r.h[i])
            else:
                level = r.l[i] if level == 0 else min(level, r.l[i])
        if level == 0:
            return None
        if d == BUY and level < extreme + min_range_atr * atr:
            return None
        if d == SELL and level > extreme - min_range_atr * atr:
            return None
    mss_bar = -1
    for j in range(extreme_idx - 1, max(1, extreme_idx - max_bars_after) - 1, -1):
        if d == BUY and r.l[j] < extreme:
            return None
        if d == SELL and r.h[j] > extreme:
            return None
        if (d == BUY and r.c[j] > level) or (d == SELL and r.c[j] < level):
            mss_bar = j
            break
    if mss_bar < 0:
        return None
    body = max(r.body(j) for j in range(mss_bar, extreme_idx))
    if body < disp_body_atr * atr:
        return None
    leg, leg_idx = (r.h[mss_bar] if d == BUY else r.l[mss_bar]), mss_bar
    for j in range(mss_bar, -1, -1):
        if d == BUY and r.h[j] > leg:
            leg, leg_idx = r.h[j], j
        if d == SELL and r.l[j] < leg:
            leg, leg_idx = r.l[j], j
    return MSS(mss_bar, r.t[mss_bar], level, body, leg, leg_idx)


# ======================================================================
# Fair value gaps (CFVG)
# ======================================================================
@dataclass
class FVG:
    mid_idx: int
    time: int
    top: float
    bottom: float
    touched: bool = False

    @property
    def size(self) -> float:
        return self.top - self.bottom

    @property
    def ce(self) -> float:
        return (self.top + self.bottom) / 2


def _mitigated(d: int, r: Rates, f: FVG) -> bool:
    for k in range(f.mid_idx - 2, -1, -1):
        if d == BUY:
            if r.l[k] < f.bottom:
                return True
            if r.l[k] <= f.top:
                f.touched = True
        else:
            if r.h[k] > f.top:
                return True
            if r.h[k] >= f.bottom:
                f.touched = True
    return False


def fvgs_in_leg(d: int, r: Rates, newest_idx: int, oldest_idx: int, min_size: float, require_body: bool = True) -> list[FVG]:
    """Unmitigated FVGs of the leg, by increasing index: the last one is the OLDEST, i.e. the
    first FVG formed after the sweep (the EA's '1st FVG of the displacement')."""
    out = []
    for m in range(max(2, newest_idx - 1), min(r.n - 2, oldest_idx - 1) + 1):
        if d == BUY:
            if r.l[m - 1] - r.h[m + 1] < min_size or (require_body and r.c[m] <= r.o[m]):
                continue
            f = FVG(m, r.t[m], r.l[m - 1], r.h[m + 1])
        else:
            if r.l[m + 1] - r.h[m - 1] < min_size or (require_body and r.c[m] >= r.o[m]):
                continue
            f = FVG(m, r.t[m], r.l[m + 1], r.h[m - 1])
        if not _mitigated(d, r, f):
            out.append(f)
    return out


def has_opposing_overlap(d: int, r: Rates, f: FVG, lookback: int, min_size: float) -> bool:
    """Balanced price range: an older opposite FVG overlaps this one."""
    for m in range(f.mid_idx + 2, min(r.n - 2, f.mid_idx + lookback) + 1):
        if d == BUY:
            if r.l[m + 1] - r.h[m - 1] < min_size:
                continue
            top, bottom = r.l[m + 1], r.h[m - 1]
        else:
            if r.l[m - 1] - r.h[m + 1] < min_size:
                continue
            top, bottom = r.l[m - 1], r.h[m + 1]
        if bottom <= f.top and top >= f.bottom:
            return True
    return False


# ======================================================================
# Liquidity map (CLiquidityMap)
# ======================================================================
RANK3 = ("PDH", "PDL", "PWH", "PWL", "IPDA_HIGH", "IPDA_LOW")


@dataclass
class Level:
    price: float
    rank: int  # 3 = PDH/PDL/PWH/PWL/IPDA, 2 = session/equal/HTF swing/OPR/NDOG, 1 = LTF swing / SD
    type: str
    time: int  # formation time (bar open time), sweeps must come after it
    is_high: bool


@dataclass
class Sweep:
    level: float
    rank: int
    type: str
    level_time: int
    extreme_idx: int
    extreme: float
    extreme_time: int
    episode_newest_idx: int
    episode_bars: int
    penetration_atr: float


def _range_in(r: Rates, s: int, e: int) -> tuple[float, float, int, int] | None:
    hi = lo = 0.0
    hi_t = lo_t = 0
    any_ = False
    for i in range(r.n):
        if r.t[i] < s or r.t[i] >= e:
            continue
        if not any_ or r.h[i] > hi:
            hi, hi_t = r.h[i], r.t[i]
        if not any_ or r.l[i] < lo:
            lo, lo_t = r.l[i], r.t[i]
        any_ = True
    return (hi, lo, hi_t, lo_t) if any_ else None


class LiquidityMap:
    def __init__(self) -> None:
        self.levels: list[Level] = []
        self.merge_tol = 0.0
        self.dr_low = self.dr_high = 0.0

    def add(self, price: float, rank: int, typ: str, time: int, is_high: bool) -> None:
        if price <= 0:
            return
        for lv in self.levels:
            if lv.is_high == is_high and abs(lv.price - price) <= self.merge_tol:
                if rank > lv.rank:
                    lv.rank, lv.type, lv.price, lv.time = rank, typ, price, time
                return
        self.levels.append(Level(price, rank, typ, time, is_high))

    def premium_discount(self, price: float) -> float:
        return 0.5 if self.dr_high <= self.dr_low else (price - self.dr_low) / (self.dr_high - self.dr_low)

    def build(self, now: int, ltf: Rates, htf: Rates | None, d1: Rates | None, atr: float, ipda: tuple[int, ...], s: int, eq_tol_atr: float, point: float) -> None:
        self.levels = []
        self.merge_tol = max(atr * 0.05, point * 5)
        if d1 is not None and d1.n > 1:
            self.add(d1.h[1], 3, "PDH", d1.t[1], True)
            self.add(d1.l[1], 3, "PDL", d1.t[1], False)
            # Previous New York week, from the daily bars (MT5 W1[1]).
            wk = clk.ny_week_key(now) - 1
            idx = [i for i in range(1, d1.n) if clk.ny_week_key(d1.t[i] + d1.step - 1) == wk]
            if idx:
                self.add(max(d1.h[i] for i in idx), 3, "PWH", d1.t[idx[-1]], True)
                self.add(min(d1.l[i] for i in idx), 3, "PWL", d1.t[idx[-1]], False)
            for k, look in enumerate(ipda):
                n = min(look, d1.n - 1)
                if n < 2:
                    continue
                hi_i = max(range(1, n + 1), key=lambda i: d1.h[i])
                lo_i = min(range(1, n + 1), key=lambda i: d1.l[i])
                self.add(d1.h[hi_i], 3, "IPDA_HIGH", d1.t[hi_i], True)
                self.add(d1.l[lo_i], 3, "IPDA_LOW", d1.t[lo_i], False)
                if k == 0:
                    self.dr_low, self.dr_high = d1.l[lo_i], d1.h[hi_i]
        for start, end, name in ((-240, 0, "ASIA"), (120, 300, "LONDON"), (420, 720, "NYAM")):
            a, b = clk.ny_range_to_utc(now, start, end)
            if a >= now:
                continue
            rg = _range_in(ltf, a, b)
            if rg:
                self.add(rg[0], 2, f"{name}_HIGH", rg[2], True)
                self.add(rg[1], 2, f"{name}_LOW", rg[3], False)
        if htf is not None:
            added = 0
            i = s + 1
            while i < htf.n - s and added < 16:
                if is_swing_high(htf, i, s):
                    self.add(htf.h[i], 2, "HTF_SWING_HIGH", htf.t[i], True)
                    added += 1
                if is_swing_low(htf, i, s):
                    self.add(htf.l[i], 2, "HTF_SWING_LOW", htf.t[i], False)
                    added += 1
                i += 1
        sh: list[tuple[float, int]] = []
        sl: list[tuple[float, int]] = []
        for i in range(s + 1, min(ltf.n - s - 1, 240) + 1):
            if len(sh) >= 14 and len(sl) >= 14:
                break
            if len(sh) < 14 and is_swing_high(ltf, i, s):
                sh.append((ltf.h[i], ltf.t[i]))
            if len(sl) < 14 and is_swing_low(ltf, i, s):
                sl.append((ltf.l[i], ltf.t[i]))
        tol = eq_tol_atr * atr
        for pts, is_high in ((sh, True), (sl, False)):
            for a in range(len(pts)):
                eq = any(abs(pts[a][0] - pts[b][0]) <= tol for b in range(a + 1, len(pts)))
                side = "HIGH" if is_high else "LOW"
                self.add(pts[a][0], 2 if eq else 1, f"EQ_{side}" if eq else f"LTF_SWING_{side}", pts[a][1], is_high)

    def add_swings(self, r: Rates, s: int, max_each: int, prefix: str) -> None:
        nh = nl = 0
        for i in range(s + 1, min(r.n - s - 1, 300) + 1):
            if nh >= max_each and nl >= max_each:
                break
            if nh < max_each and is_swing_high(r, i, s):
                self.add(r.h[i], 1, f"{prefix}_SWING_HIGH", r.t[i], True)
                nh += 1
            if nl < max_each and is_swing_low(r, i, s):
                self.add(r.l[i], 1, f"{prefix}_SWING_LOW", r.t[i], False)
                nl += 1

    def find_sweeps(self, d: int, r: Rates, atr: float, lookback: int, min_pen_atr: float, confirm_bars: int, max_episode: int, not_older_than: int) -> list[Sweep]:
        """Confirmed liquidity sweeps. d=BUY looks under the lows (sell-side liquidity)."""
        out: list[Sweep] = []
        if atr <= 0 or r.n < 10:
            return out
        lb = min(lookback, r.n - 2)
        min_pen = min_pen_atr * atr
        want_high = d == SELL
        for lv in self.levels:
            if lv.is_high != want_high:
                continue
            level = lv.price
            v = -1
            for i in range(1, lb + 1):
                if r.t[i] <= lv.time:
                    break
                if (r.h[i] > level + min_pen) if want_high else (r.l[i] < level - min_pen):
                    v = i
                    break
            if v < 0:
                continue
            def beyond(i: int, lv: float = level) -> bool:
                return r.h[i] > lv if want_high else r.l[i] < lv

            e1 = v
            while e1 - 1 >= 1 and beyond(e1 - 1):
                e1 -= 1
            e2 = v
            while e2 + 1 <= lb and beyond(e2 + 1):
                e2 += 1
            episode = e2 - e1 + 1
            if episode > max_episode:
                continue  # a break, not a sweep
            def inside(i: int, lv: float = level) -> bool:
                return r.c[i] < lv if want_high else r.c[i] > lv

            confirm = e1 if inside(e1) else (e1 - 1 if e1 > 1 and inside(e1 - 1) else -1)
            if confirm < 0:
                continue
            ex_i, ex = e1, (r.h[e1] if want_high else r.l[e1])
            for i in range(e1, e2 + 1):
                if want_high and r.h[i] > ex:
                    ex, ex_i = r.h[i], i
                if not want_high and r.l[i] < ex:
                    ex, ex_i = r.l[i], i
            if ex_i - confirm > confirm_bars or r.t[ex_i] < not_older_than:
                continue
            out.append(Sweep(level, lv.rank, lv.type, lv.time, ex_i, ex, r.t[ex_i], e1, episode, abs(ex - level) / atr))
        out.sort(key=lambda x: (-x.rank, x.extreme_idx))
        return out[:8]

    def nearest_pool(self, d: int, entry: float, min_dist: float, max_dist: float, extras: list[float] = ()) -> tuple[float, str | None]:
        price, typ = 0.0, None
        want_high = d == BUY
        for lv in self.levels:
            if lv.is_high != want_high:
                continue
            dist = (lv.price - entry) if want_high else (entry - lv.price)
            if min_dist <= dist <= max_dist and (price == 0 or dist < abs(price - entry)):
                price, typ = lv.price, lv.type
        for x in extras:
            dist = (x - entry) if d == BUY else (entry - x)
            if min_dist <= dist <= max_dist and (price == 0 or dist < abs(price - entry)):
                price, typ = x, "SD_TARGET"
        return price, typ

    def has_equal_level_beyond(self, d: int, price: float, max_dist: float, exclude: float, tol: float) -> bool:
        for lv in self.levels:
            if lv.type != ("EQ_LOW" if d == BUY else "EQ_HIGH") or abs(lv.price - exclude) <= tol:
                continue
            dist = (price - lv.price) if d == BUY else (lv.price - price)
            if 0 < dist <= max_dist:
                return True
        return False


def sd_targets(d: int, origin: float, extreme: float) -> list[float]:
    """Standard deviations 2 / 2.5 / 4 of the manipulation leg, projected as targets."""
    rng = abs(origin - extreme)
    if rng <= 0:
        return []
    return [extreme + k * rng if d == BUY else extreme - k * rng for k in (2.0, 2.5, 4.0)]


# ======================================================================
# Reference levels (CReferenceLevels)
# ======================================================================
OPR = ((90, 120), (420, 450), (570, 600), (810, 840))  # 01:30, 07:00, 09:30, 13:30 NY


def _open_at_or_after(r: Rates | None, t: int, not_after: int) -> float:
    if r is None:
        return 0.0
    best, best_t = 0.0, 0
    for i in range(r.n):
        if t <= r.t[i] <= not_after and (best_t == 0 or r.t[i] < best_t):
            best, best_t = r.o[i], r.t[i]
    return best


def _close_before(r: Rates | None, t: int, not_before: int) -> float:
    if r is None:
        return 0.0
    best, best_t = 0.0, 0
    for i in range(1, r.n):  # index 0 is the placeholder
        if not_before <= r.t[i] < t and (best_t == 0 or r.t[i] > best_t):
            best, best_t = r.c[i], r.t[i]
    return best


class ReferenceLevels:
    def __init__(self) -> None:
        self.midnight_open = self.open_0730 = 0.0
        self.pd_high = self.pd_low = self.adr5 = self.day_high = self.day_low = 0.0
        self.ndog = self.nwog = (0.0, 0.0, 0)
        self.opr: list[tuple[float, float, int] | None] = [None] * 4
        self.tbr: tuple[float, float, int] | None = None

    def build(self, now: int, ltf: Rates, m1: Rates | None, htf: Rates | None, d1: Rates | None) -> None:
        day_start = clk.ny_minute_to_utc(now, 0)
        self.midnight_open = _open_at_or_after(ltf, day_start, day_start + 30 * MINUTE_MS)
        t0730 = clk.ny_minute_to_utc(now, 450)
        self.open_0730 = _open_at_or_after(ltf, t0730, t0730 + 30 * MINUTE_MS) if now >= t0730 else 0.0
        self.pd_high = self.pd_low = self.adr5 = 0.0
        if d1 is not None and d1.n > 1:
            self.pd_high, self.pd_low = d1.h[1], d1.l[1]
            rngs = [d1.h[i] - d1.l[i] for i in range(1, min(6, d1.n))]
            self.adr5 = sum(rngs) / len(rngs) if rngs else 0.0
        rg = _range_in(ltf, day_start, now + MINUTE_MS)
        self.day_high, self.day_low = (rg[0], rg[1]) if rg else (0.0, 0.0)
        self.ndog = self.nwog = (0.0, 0.0, 0)
        if htf is not None and htf.n > 30:
            c17 = clk.ny_minute_to_utc(now, 17 * 60, -1)
            o18 = clk.ny_minute_to_utc(now, 18 * 60, -1)
            c, o = _close_before(htf, c17, c17 - 4 * HOUR_MS), _open_at_or_after(htf, o18, o18 + 3 * HOUR_MS)
            if c > 0 and o > 0:
                self.ndog = (max(c, o), min(c, o), o18)
            back = (clk.ny_day_of_week(now) + 2) % 7 or 7
            fri17 = clk.ny_minute_to_utc(now, 17 * 60, -back)
            sun18 = clk.ny_minute_to_utc(now, 18 * 60, -back + 2)
            fc, so = _close_before(htf, fri17, fri17 - 4 * HOUR_MS), _open_at_or_after(htf, sun18, sun18 + 3 * HOUR_MS)
            if fc > 0 and so > 0:
                self.nwog = (max(fc, so), min(fc, so), sun18)
        for k, (a, b) in enumerate(OPR):
            s, e = clk.ny_range_to_utc(now, a, b)
            rg = _range_in(ltf, s, e) if now >= e else None
            self.opr[k] = (rg[0], rg[1], e) if rg else None
        self.tbr = None
        s, e = clk.ny_range_to_utc(now, 492, 552)
        if now >= e:
            rg = _range_in(m1, s, e) if (m1 is not None and m1.t[m1.n - 1] <= s) else None
            rg = rg or _range_in(ltf, s - 2 * MINUTE_MS, e)
            if rg:
                self.tbr = (rg[0], rg[1], e)

    def push_to(self, liq: LiquidityMap) -> None:
        for o in self.opr:
            if o:
                liq.add(o[0], 2, "OPR_HIGH", o[2], True)
                liq.add(o[1], 2, "OPR_LOW", o[2], False)
        if self.opr[2]:
            hi, lo, e = self.opr[2]
            for sd in (2.0, 2.5, 4.0, 6.0):
                liq.add(hi + sd * (hi - lo), 1, "SD_TARGET", e, True)
                liq.add(lo - sd * (hi - lo), 1, "SD_TARGET", e, False)
        if self.tbr:
            liq.add(self.tbr[0], 2, "TBR_HIGH", self.tbr[2], True)
            liq.add(self.tbr[1], 2, "TBR_LOW", self.tbr[2], False)
        for g, name in ((self.ndog, "NDOG"), (self.nwog, "NWOG")):
            if g[0] > 0:
                liq.add(g[0], 2, f"{name}_HIGH", g[2], True)
                liq.add(g[1], 2, f"{name}_LOW", g[2], False)

    def true_open(self, now: int) -> float:
        return self.open_0730 if clk.ny_minute_of_day(now) >= 450 and self.open_0730 > 0 else self.midnight_open

    def true_open_aligned(self, d: int, price: float, now: int) -> bool:
        to = self.true_open(now)
        return to > 0 and (price < to if d == BUY else price > to)

    def zone_hits(self, low: float, high: float, tol: float) -> str:
        lo, hi = low - tol, high + tol
        if self.pd_high > self.pd_low:
            for q in range(5):
                lvl = self.pd_low + (self.pd_high - self.pd_low) * q / 4
                if lo <= lvl <= hi:
                    return f"PD_Q{q * 25}"
        for k, o in enumerate(self.opr):
            if o:
                for v, tag in ((o[0], "H"), (o[1], "L"), ((o[0] + o[1]) / 2, "CE")):
                    if lo <= v <= hi:
                        return f"OPR{k}_{tag}"
        for g, name in ((self.ndog, "NDOG"), (self.nwog, "NWOG")):
            if g[0] > 0 and any(lo <= v <= hi for v in (g[0], g[1], (g[0] + g[1]) / 2)):
                return name
        return ""

    def adr_used_pct(self) -> float:
        if self.adr5 <= 0 or self.day_high <= self.day_low:
            return 0.0
        return 100.0 * (self.day_high - self.day_low) / self.adr5


# ======================================================================
# Setups
# ======================================================================
@dataclass
class SBParams:
    swing_strength: int = 2
    sweep_min_atr: float = 0.04
    sweep_confirm_bars: int = 3
    sweep_max_episode: int = 6
    sweep_lookback: int = 48
    pre_sweep_min: int = 45
    mss_max_bars: int = 15
    mss_min_range_atr: float = 0.3
    disp_body_atr: float = 0.8
    fvg_min_size_atr: float = 0.12
    entry_mode: int = 0  # 0 FVG edge, 1 FVG CE, 2 market on MSS
    require_discount: bool = True
    require_htf_align: bool = False
    use_ote_bonus: bool = True
    use_macro_bonus: bool = True
    min_score: int = 3
    sl_buffer_atr: float = 0.10
    tp_buffer_atr: float = 0.05
    fixed_rr_tp: bool = False
    min_rr: float = 2.0
    max_tp_dist_atr_d1: float = 1.5
    max_stop_atr: float = 6.0
    allow_fixed_rr_fallback: bool = True
    use_true_open_bonus: bool = True
    require_true_open: bool = False
    use_ref_level_bonus: bool = True
    ref_level_tol_atr: float = 0.15
    use_dow_score: bool = True
    use_bpr_bonus: bool = True
    use_sd_targets: bool = True
    eq_warn_atr: float = 1.5
    fvg_require_body: bool = False
    take_first_fvg: bool = True
    min_retrace: float = 0.35

    def relaxed(self) -> "SBParams":
        """The EA's second, relaxed pass (v6.20)."""
        return replace(self, require_htf_align=False, require_discount=False, require_true_open=False, fvg_require_body=False,
                       min_score=max(0, self.min_score - 3), min_rr=max(1.5, self.min_rr - 0.5), disp_body_atr=self.disp_body_atr * 0.6,
                       fvg_min_size_atr=self.fvg_min_size_atr * 0.6, sweep_min_atr=self.sweep_min_atr * 0.6, min_retrace=0.0)


@dataclass
class MBParams:
    swing_strength: int = 2
    lookback: int = 90
    swing_lookback: int = 75
    max_bars_to_confirm: int = 30
    sweep_min_atr: float = 0.05
    sweep_confirm_bars: int = 3
    sweep_max_episode: int = 8
    pre_macro_min: int = 25
    min_range_atr: float = 0.4
    disp_body_atr: float = 0.8
    fvg_min_size_atr: float = 0.15
    min_breaker_atr: float = 0.5
    entry_level: int = 0  # 0 breaker edge, 1 body, 2 CE
    require_unicorn: bool = False
    require_htf_align: bool = False
    require_true_open: bool = False
    min_score: int = 2
    sl_buffer_atr: float = 0.2
    generous_macro_mult: float = 1.5
    tp_buffer_atr: float = 0.05
    min_rr: float = 2.0
    max_tp_dist_atr_d1: float = 1.5
    max_stop_atr: float = 12.0
    allow_fixed_rr_fallback: bool = True
    use_sd_targets: bool = True
    use_ref_level_bonus: bool = True
    ref_level_tol_atr: float = 0.15
    use_dow_score: bool = True
    eq_warn_atr: float = 1.5
    fvg_require_body: bool = False
    allow_retested: bool = True

    def relaxed(self) -> "MBParams":
        return replace(self, require_htf_align=False, require_true_open=False, require_unicorn=False, fvg_require_body=False, allow_retested=True,
                       min_score=max(0, self.min_score - 2), min_rr=max(1.5, self.min_rr - 0.5), disp_body_atr=self.disp_body_atr * 0.6,
                       sweep_min_atr=self.sweep_min_atr * 0.6, min_range_atr=self.min_range_atr * 0.6)


@dataclass
class Setup:
    kind: str  # "SB" | "MB"
    dir: int
    entry: float
    sl: float
    tp: float
    rr: float
    score: int
    market_entry: bool
    invalid_level: float  # a close beyond it cancels a pending entry
    window: str
    window_start: int
    window_end: int
    id: str
    sweep: Sweep
    relaxed: bool = False
    unicorn: bool = False
    macro_id: int = 0
    tp_source: str = "RR"
    details: dict = field(default_factory=dict)

    @property
    def risk(self) -> float:
        return abs(self.entry - self.sl)

    def describe(self) -> str:
        what = "Silver Bullet" if self.kind == "SB" else f"Macro Breaker {self.macro_id:04d}"
        return (f"{what} {dir_str(self.dir)} score {self.score}{' (passe relâchée)' if self.relaxed else ''}{' UNICORN' if self.unicorn else ''}"
                f" : sweep {self.sweep.type} {self.sweep.level:.5g}, entrée {self.entry:.5g}, SL {self.sl:.5g}, TP {self.tp:.5g} (RR {self.rr:.1f}, cible {self.tp_source})")


@dataclass
class Market:
    """Everything a setup needs at the decision instant."""

    now: int
    ask: float
    bid: float
    min_stop: float
    liq: LiquidityMap
    ref: ReferenceLevels
    bias: int
    atr_d1: float


def _target(liq: LiquidityMap, d: int, entry: float, risk: float, min_rr: float, max_dist: float, buf: float, extras: list[float], nearest: bool, fallback: bool) -> tuple[float, str] | None:
    if nearest:
        price, typ = liq.nearest_pool(d, entry, min_rr * risk + buf, max_dist, extras)
        if price > 0:
            return (price - buf if d == BUY else price + buf), typ or "POOL"
        if not fallback:
            return None
    return (entry + min_rr * risk if d == BUY else entry - min_rr * risk), "RR"


def silver_bullet(ltf: Rates, mk: Market, window: str, ws: int, we: int, atr: float, p: SBParams, dirs: tuple[int, ...]) -> tuple[Setup | None, str]:
    """CSetupSilverBullet.Evaluate: sweep -> MSS with displacement -> FVG entry."""
    if atr <= 0 or ltf.n < 60:
        return None, "données insuffisantes"
    not_older = ws - p.pre_sweep_min * MINUTE_MS
    dow = clk.day_of_week_score(mk.now)
    best: Setup | None = None
    reasons = []
    for d in dirs:
        why = ""
        if p.require_htf_align and mk.bias not in (0, d):
            reasons.append(f"{dir_str(d)}: biais H1 opposé")
            continue
        sweeps = mk.liq.find_sweeps(d, ltf, atr, p.sweep_lookback, p.sweep_min_atr, p.sweep_confirm_bars, p.sweep_max_episode, not_older)
        if not sweeps:
            reasons.append(f"{dir_str(d)}: aucun sweep")
            continue
        for sw in sweeps:
            mss = find_mss(d, ltf, sw.extreme_idx, sw.extreme, p.mss_max_bars, p.mss_min_range_atr, p.disp_body_atr, atr, p.swing_strength)
            if mss is None:
                why = why or "pas de MSS avec displacement"
                continue
            fvgs = fvgs_in_leg(d, ltf, mss.bar_idx, sw.extreme_idx, p.fvg_min_size_atr * atr, p.fvg_require_body)
            if not fvgs:
                if why in ("", "pas de MSS avec displacement"):
                    why = "pas de FVG dans la jambe"
                continue
            order = list(reversed(fvgs)) if p.take_first_fvg else fvgs
            for f in order:
                s, w = _build_sb(d, ltf, sw, mss, f, atr, mk, window, ws, we, dow, p)
                if s is None:
                    why = w
                    continue
                if best is None or s.score > best.score or (s.score == best.score and s.rr > best.rr):
                    best = s
                if p.take_first_fvg:
                    break
        if why:
            reasons.append(f"{dir_str(d)}: {why}")
    return best, "; ".join(reasons)


def _build_sb(d: int, r: Rates, sw: Sweep, mss: MSS, f: FVG, atr: float, mk: Market, window: str, ws: int, we: int, dow: int, p: SBParams) -> tuple[Setup | None, str]:
    in_macro = clk.macro_at(mss.bar_time) is not None or clk.macro_at(mk.now) is not None
    leg_low, leg_high = (sw.extreme, mss.leg_extreme) if d == BUY else (mss.leg_extreme, sw.extreme)
    leg = leg_high - leg_low
    if leg <= 0:
        return None, "jambe nulle"
    price = f.ce if p.entry_mode == 1 else (f.top if d == BUY else f.bottom)
    market = False
    if p.entry_mode == 2:
        price, market = (mk.ask if d == BUY else mk.bid), True
    elif d == BUY and mk.ask <= f.top:
        if mk.ask < f.bottom:
            return None, "FVG traversé"
        price, market = mk.ask, True
    elif d == SELL and mk.bid >= f.bottom:
        if mk.bid > f.top:
            return None, "FVG traversé"
        price, market = mk.bid, True
    entry = price
    retrace = (leg_high - entry) / leg if d == BUY else (entry - leg_low) / leg
    if p.require_discount and retrace < p.min_retrace:
        return None, f"retracement {retrace:.2f} < {p.min_retrace:.2f}"
    ote_a = leg_high - 0.62 * leg if d == BUY else leg_low + 0.62 * leg
    ote_b = leg_high - 0.79 * leg if d == BUY else leg_low + 0.79 * leg
    in_ote = f.bottom <= max(ote_a, ote_b) and f.top >= min(ote_a, ote_b)
    to_aligned = mk.ref.true_open_aligned(d, entry, mk.now)
    if p.require_true_open and mk.ref.true_open(mk.now) > 0 and not to_aligned:
        return None, "entrée du mauvais côté du true open"
    ref_hit = mk.ref.zone_hits(f.bottom, f.top, p.ref_level_tol_atr * atr) if p.use_ref_level_bonus else ""
    bpr = p.use_bpr_bonus and has_opposing_overlap(d, r, f, 30, p.fvg_min_size_atr * atr)
    buffer = p.sl_buffer_atr * atr + (mk.ask - mk.bid)
    sl = sw.extreme - buffer if d == BUY else sw.extreme + buffer
    risk = abs(entry - sl)
    if risk < mk.min_stop:
        return None, "stop sous la distance minimale"
    if risk > p.max_stop_atr * atr:
        return None, f"stop trop large (> {p.max_stop_atr:.0f} ATR)"
    eq_warn = mk.liq.has_equal_level_beyond(d, sl, p.eq_warn_atr * atr, sw.level, 0.05 * atr)
    max_dist = p.max_tp_dist_atr_d1 * mk.atr_d1 if mk.atr_d1 > 0 else 50 * atr
    extras = sd_targets(d, mss.broken_level, sw.extreme) if p.use_sd_targets else []
    tgt = _target(mk.liq, d, entry, risk, p.min_rr, max_dist, p.tp_buffer_atr * atr, extras, not p.fixed_rr_tp, p.allow_fixed_rr_fallback)
    if tgt is None:
        return None, "aucun pool de liquidité opposé atteignable"
    tp, src = tgt
    rr = abs(tp - entry) / risk
    if rr < p.min_rr - 1e-6:
        return None, f"RR {rr:.2f} sous le minimum {p.min_rr:.2f}"
    disp = mss.disp_body / atr
    score = (2 if mk.bias == d else 0) + (2 if sw.rank >= 3 else 1 if sw.rank == 2 else 0) + (disp >= 1.5) + (not f.touched)
    score += (p.use_ote_bonus and in_ote) + (p.use_macro_bonus and in_macro) + (rr >= 3.0) + (p.use_true_open_bonus and to_aligned)
    score += bool(ref_hit) + bool(bpr) + (dow if p.use_dow_score else 0) - (2 if eq_warn else 0)
    if score < p.min_score:
        return None, f"score {score} < {p.min_score}"
    sid = f"SB_{ws}_{d}_{sw.extreme_time}"
    return Setup("SB", d, entry, sl, tp, rr, int(score), market, f.bottom if d == BUY else f.top, window, ws, we, sid, sw, tp_source=src,
                 details={"fvg": (f.bottom, f.top), "retrace": retrace, "ote": in_ote, "bpr": bpr, "ref": ref_hit, "disp_atr": disp, "eq_warning": eq_warn}), ""


def _breaker_candle(d: int, r: Rates, swing_idx: int) -> int:
    for i in range(swing_idx, max(1, swing_idx - 2) - 1, -1):
        if (d == BUY and r.c[i] < r.o[i]) or (d == SELL and r.c[i] > r.o[i]):
            return i
    return swing_idx


def macro_breaker(m1: Rates, mk: Market, macro: clk.Macro, ms: int, me: int, atr: float, atr_m5: float, p: MBParams, dirs: tuple[int, ...]) -> tuple[Setup | None, str]:
    """CSetupMacroBreaker.Evaluate: stop hunt -> breaker confirmed by a body close -> retest."""
    if atr <= 0 or m1.n < 60:
        return None, "données M1 insuffisantes"
    not_older = ms - (p.pre_macro_min + 10) * MINUTE_MS
    dow = clk.day_of_week_score(mk.now)
    best: Setup | None = None
    best_confirm = 0
    reasons = []
    for d in dirs:
        why = ""
        if p.require_htf_align and mk.bias not in (0, d):
            reasons.append(f"{dir_str(d)}: biais H1 opposé")
            continue
        sweeps = mk.liq.find_sweeps(d, m1, atr, p.lookback, p.sweep_min_atr, p.sweep_confirm_bars, p.sweep_max_episode, not_older)
        if not sweeps:
            reasons.append(f"{dir_str(d)}: aucun stop hunt")
            continue
        for sw in sweeps:
            s, w, confirm_t = _build_mb(d, m1, sw, atr, atr_m5, mk, macro, ms, me, dow, p)
            if s is None:
                why = w
                continue
            if best is None or confirm_t < best_confirm or (confirm_t == best_confirm and s.score > best.score):
                best, best_confirm = s, confirm_t
        if why:
            reasons.append(f"{dir_str(d)}: {why}")
    return best, "; ".join(reasons)


def _build_mb(d: int, r: Rates, sw: Sweep, atr: float, atr_m5: float, mk: Market, macro: clk.Macro, ms: int, me: int, dow: int, p: MBParams) -> tuple[Setup | None, str, int]:
    ex = sw.extreme_idx
    swing_idx = -1
    for i in range(ex + 1, min(r.n - p.swing_strength - 1, ex + p.swing_lookback) + 1):
        if sw.level_time > 0 and r.t[i] <= sw.level_time:
            break
        if d == BUY and is_swing_high(r, i, p.swing_strength) and r.h[i] >= sw.extreme + p.min_range_atr * atr:
            swing_idx = i
            break
        if d == SELL and is_swing_low(r, i, p.swing_strength) and r.l[i] <= sw.extreme - p.min_range_atr * atr:
            swing_idx = i
            break
    if swing_idx < 0:
        return None, "pas de swing opposé avant le stop hunt", 0
    bc = _breaker_candle(d, r, swing_idx)
    b_top, b_bot = r.h[bc], r.l[bc]
    body_top, body_bot = max(r.o[bc], r.c[bc]), min(r.o[bc], r.c[bc])
    swing_level = r.h[swing_idx] if d == BUY else r.l[swing_idx]
    confirm = -1
    body = 0.0
    leg_ext = -1.0 if d == BUY else float("inf")
    for j in range(ex - 1, max(1, ex - p.max_bars_to_confirm) - 1, -1):
        if (d == BUY and r.l[j] < sw.extreme) or (d == SELL and r.h[j] > sw.extreme):
            return None, "extrême du sweep violé avant confirmation", 0
        body = max(body, r.body(j))
        leg_ext = max(leg_ext, r.h[j]) if d == BUY else min(leg_ext, r.l[j])
        body_close = (r.c[j] > body_top and r.c[j] > r.o[j]) if d == BUY else (r.c[j] < body_bot and r.c[j] < r.o[j])
        new_ext = leg_ext > swing_level if d == BUY else leg_ext < swing_level
        if body_close and new_ext:
            confirm = j
            break
    if confirm < 0:
        return None, "pas de confirmation (corps au-delà du corps du swing)", 0
    if body < p.disp_body_atr * atr:
        return None, "displacement insuffisant", 0
    confirm_t = r.t[confirm]
    if confirm_t < ms - p.pre_macro_min * MINUTE_MS or confirm_t > me:
        return None, "confirmation hors macro", 0
    zone_top, zone_bot, unicorn = b_top, b_bot, False
    for f in fvgs_in_leg(d, r, confirm, ex, p.fvg_min_size_atr * atr, p.fvg_require_body):
        if f.bottom <= b_top and f.top >= b_bot:
            unicorn = True
            zone_top, zone_bot = min(b_top, f.top), max(b_bot, f.bottom)
            break
    if p.require_unicorn and not unicorn:
        return None, "pas de FVG dans le breaker (Unicorn requis)", 0
    edge = zone_top if d == BUY else zone_bot
    tested = False
    for j in range(confirm - 1, 0, -1):
        if (d == BUY and r.c[j] < zone_bot) or (d == SELL and r.c[j] > zone_top):
            return None, "breaker déjà violé", 0
        if (d == BUY and r.l[j] <= edge) or (d == SELL and r.h[j] >= edge):
            tested = True
    if tested and not p.allow_retested:
        return None, "breaker déjà retesté", 0
    if p.entry_level == 1:
        price = min(zone_top, body_top) if d == BUY else max(zone_bot, body_bot)
    elif p.entry_level == 2:
        price = (zone_top + zone_bot) / 2
    else:
        price = edge
    market = False
    if d == BUY and mk.ask <= price:
        if mk.ask < zone_bot:
            return None, "breaker traversé", 0
        price, market = mk.ask, True
    if d == SELL and mk.bid >= price:
        if mk.bid > zone_top:
            return None, "breaker traversé", 0
        price, market = mk.bid, True
    entry = price
    to_aligned = mk.ref.true_open_aligned(d, entry, mk.now)
    if p.require_true_open and mk.ref.true_open(mk.now) > 0 and not to_aligned:
        return None, "true open non aligné", 0
    ref_hit = mk.ref.zone_hits(zone_bot, zone_top, p.ref_level_tol_atr * atr_m5) if p.use_ref_level_bonus else ""
    mult = p.generous_macro_mult if macro.id == 920 else 1.0
    buffer = p.sl_buffer_atr * atr * mult + (mk.ask - mk.bid)
    sl_breaker = b_bot - buffer if d == BUY else b_top + buffer
    small = (b_top - b_bot) < p.min_breaker_atr * atr
    sl = (sw.extreme - buffer if d == BUY else sw.extreme + buffer) if small else sl_breaker
    sl = min(sl, sl_breaker) if d == BUY else max(sl, sl_breaker)
    risk = abs(entry - sl)
    if risk < mk.min_stop:
        return None, "stop sous la distance minimale", 0
    if risk > p.max_stop_atr * atr:
        return None, f"stop trop large (> {p.max_stop_atr:.0f} ATR M1)", 0
    eq_warn = mk.liq.has_equal_level_beyond(d, sl, p.eq_warn_atr * atr_m5, sw.level, 0.05 * atr_m5)
    max_dist = p.max_tp_dist_atr_d1 * mk.atr_d1 if mk.atr_d1 > 0 else 50 * atr_m5
    extras = sd_targets(d, swing_level, sw.extreme) if p.use_sd_targets else []
    tgt = _target(mk.liq, d, entry, risk, p.min_rr, max_dist, p.tp_buffer_atr * atr_m5, extras, True, p.allow_fixed_rr_fallback)
    if tgt is None:
        return None, "aucune cible atteignable", 0
    tp, src = tgt
    rr = abs(tp - entry) / risk
    if rr < p.min_rr - 1e-6:
        return None, f"RR {rr:.2f} sous le minimum {p.min_rr:.2f}", 0
    if (d == BUY and leg_ext >= tp) or (d == SELL and leg_ext <= tp):
        return None, "cible atteinte avant l'entrée", 0
    disp = body / atr
    score = macro.high_prob + (2 if sw.rank >= 3 else 1 if sw.rank == 2 else 0) + (2 if unicorn else 0) + (disp >= 1.5)
    score += (mk.bias == d) + to_aligned + bool(ref_hit) + (rr >= 3.0) + (dow if p.use_dow_score else 0) - (2 if eq_warn else 0)
    if score < p.min_score:
        return None, f"score {score} < {p.min_score}", 0
    sid = f"MB_{macro.id}_{ms}_{d}_{sw.extreme_time}"
    s = Setup("MB", d, entry, sl, tp, rr, int(score), market, zone_bot if d == BUY else zone_top, f"macro {macro.id:04d}", ms, me, sid, sw,
              unicorn=unicorn, macro_id=macro.id, tp_source=src,
              details={"breaker": (b_bot, b_top), "zone": (zone_bot, zone_top), "retested": tested, "ref": ref_hit, "disp_atr": disp, "eq_warning": eq_warn})
    return s, "", confirm_t

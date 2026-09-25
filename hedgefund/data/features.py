"""Feature library. Pure functions of a MarketView (point-in-time by construction).

Horizons are expressed in days and converted with ``bars_per_day`` so the same strategy
spec works on 1h or 4h bars.
"""

from __future__ import annotations

import math

from hedgefund.data.series import MarketView

FUNDING_PERIODS_PER_YEAR = 3 * 365  # 8-hourly funding (verify per venue/contract)


def perp_for(symbol: str) -> str:
    return symbol if symbol.endswith("-PERP") else f"{symbol}-PERP"


def annualized_vol(view: MarketView, symbol: str, days: float, bpd: int) -> float | None:
    stats = view.logret_stats(symbol, max(2, int(days * bpd)))
    if stats is None:
        return None
    return stats[1] * math.sqrt(365 * bpd)


def standard_features(view: MarketView, symbol: str, bpd: int) -> dict[str, float]:
    """Generic state features for one instrument. Missing inputs are simply omitted;
    consumers must treat absent keys as 'unknown', never as zero."""
    f: dict[str, float] = {}
    close = view.last_close(symbol)
    if close is None:
        return f
    f["close"] = close
    rv_short = annualized_vol(view, symbol, 6, bpd)
    rv_long = annualized_vol(view, symbol, 60, bpd)
    if rv_short is not None:
        f["rv_short"] = rv_short
    if rv_long is not None and rv_long > 0:
        f["rv_long"] = rv_long
        if rv_short is not None:
            f["rv_ratio"] = rv_short / rv_long
        daily_vol = rv_long / math.sqrt(365)
        f["daily_vol"] = daily_vol
        ret_1d = view.momentum(symbol, bpd)
        if ret_1d is not None:
            f["ret_1d"] = ret_1d
            f["ret_z_1d"] = ret_1d / daily_vol
        lr = view.last_logret(symbol)
        if lr is not None:
            f["bar_ret_z"] = lr / (rv_long / math.sqrt(365 * bpd))
    er = view.efficiency_ratio(symbol, 10 * bpd)
    if er is not None:
        f["er_10d"] = er
    for days in (20, 60, 120):
        m = view.momentum(symbol, days * bpd)
        if m is not None:
            f[f"mom_{days}d"] = m
    highs = view.highs(symbol, 6 * bpd)
    if highs:
        f["dd_6d"] = close / max(highs) - 1.0
    atr = view.atr_pct(symbol, 14 * bpd)
    if atr is not None:
        f["atr_pct"] = atr
    vol_1d = view.notional_volume(symbol, bpd)
    vol_30d = view.notional_volume(symbol, 30 * bpd)
    if vol_1d is not None and vol_30d:
        f["volume_ratio"] = vol_1d / (vol_30d / 30)
    last = view.last_bar(symbol)
    if last is not None:
        f["bar_notional_volume"] = last.volume * last.close
        f["range_pct"] = (last.high - last.low) / last.close
    perp = perp_for(symbol)
    funding = view.funding(perp, 9)  # 3 days of 8h prints
    if funding:
        f["funding_last_ann"] = funding[-1] * FUNDING_PERIODS_PER_YEAR
        f["funding_avg_3d_ann"] = sum(funding) / len(funding) * FUNDING_PERIODS_PER_YEAR
        f["funding_neg_streak"] = float(_neg_streak(funding))
    oi_now = view.open_interest_at(perp, view.t)
    oi_then = view.open_interest_at(perp, view.t - 86_400_000)
    if oi_now and oi_then:
        f["oi_chg_1d"] = oi_now / oi_then - 1.0
    return f


def _neg_streak(values: list[float]) -> int:
    n = 0
    for v in reversed(values):
        if v < 0:
            n += 1
        else:
            break
    return n


def stablecoin_growth(view: MarketView, days: int) -> float | None:
    now = view.macro_at("stablecoin_supply_usd", view.t)
    then = view.macro_at("stablecoin_supply_usd", view.t - days * 86_400_000)
    if not now or not then:
        return None
    return now / then - 1.0


def log_ratio_zscore(view: MarketView, num: str, den: str, n: int) -> tuple[float, float] | None:
    """z-score of ln(num/den) vs its trailing n-bar mean, and the ratio's efficiency ratio."""
    a, b = view.closes(num, n), view.closes(den, n)
    if len(a) < n or len(b) < n:
        return None
    r = [math.log(x / y) for x, y in zip(a, b)]
    mean = sum(r) / n
    var = sum((x - mean) ** 2 for x in r) / (n - 1)
    if var <= 0:
        return None
    path = sum(abs(r[i] - r[i - 1]) for i in range(1, n))
    er = abs(r[-1] - r[0]) / path if path > 0 else 0.0
    return (r[-1] - mean) / math.sqrt(var), er

"""Seeded synthetic market generator (regime-switching, with liquidation cascades and crises).

SYNTHETIC DATA PROVES PLUMBING, NOT EDGE. It exercises every code path (funding accrual,
cascades, crisis handling, partial fills) offline and deterministically. Any Sharpe ratio
computed on it says nothing about real markets; strategy promotion gates reject evidence
produced from synthetic data (see ``strategy.lifecycle``).
"""

from __future__ import annotations

import math
import random

from hedgefund.core.timeutil import DAY_MS, HOUR_MS, interval_ms
from hedgefund.core.types import Bar
from hedgefund.data.series import BarSeries, MarketData, Series

START_TS = 1_672_531_200_000  # 2023-01-01T00:00:00Z

REGIMES = {
    #            drift/yr  vol/yr  basis_mean  stable_growth/day  mean duration (days)
    "bull": (0.70, 0.45, 0.00045, 0.0015, 50),
    "bear": (-0.55, 0.60, -0.00015, -0.0005, 40),
    "range": (0.00, 0.35, 0.00010, 0.0003, 45),
    "high_vol": (0.00, 0.90, 0.00005, 0.0000, 15),
}
TRANSITIONS = {
    "bull": {"range": 0.5, "high_vol": 0.25, "bear": 0.25},
    "bear": {"range": 0.5, "high_vol": 0.3, "bull": 0.2},
    "range": {"bull": 0.4, "bear": 0.35, "high_vol": 0.25},
    "high_vol": {"range": 0.4, "bear": 0.3, "bull": 0.3},
}


def _pick(rng: random.Random, weights: dict[str, float]) -> str:
    x, acc = rng.random() * sum(weights.values()), 0.0
    for k, w in weights.items():
        acc += w
        if x <= acc:
            return k
    return next(iter(weights))


def generate_market_data(
    n_bars: int = 3000,
    interval: str = "4h",
    seed: int = 7,
    start_ts: int = START_TS,
    cascade_per_year: float = 10.0,
    crisis_per_year: float = 0.5,
) -> MarketData:
    rng = random.Random(seed)
    step = interval_ms(interval)
    bpy = 365 * DAY_MS / step
    ts = [start_ts + (i + 1) * step for i in range(n_bars)]

    regime = "range"
    regimes: list[str] = []
    btc_lr: list[float] = []
    eth_extra: list[float] = []
    shock_vol: list[float] = []  # volume multiplier from shocks
    oi_shock: list[float] = []
    basis_shock: list[float] = []
    pending: list[tuple[float, float, float, float]] = []  # (btc_lr, vol_mult, oi_lr, basis_add) queue
    ratio_x = 0.0

    for _ in range(n_bars):
        _, _, _, _, dur_days = REGIMES[regime]
        if rng.random() < 1.0 / (dur_days * DAY_MS / step):
            regime = _pick(rng, TRANSITIONS[regime])
        drift, vol, *_ = REGIMES[regime]

        if not pending:
            if rng.random() < crisis_per_year / bpy:
                # Crisis: ~-30% over ~3 days, vol explodes, basis/funding deeply negative.
                n = max(3, int(3 * DAY_MS / step))
                pending = [(math.log(0.70) / n, 4.0, math.log(0.6) / n, -0.004) for _ in range(n)]
                regime = "high_vol"
            elif rng.random() < cascade_per_year / bpy:
                # Liquidation cascade: sharp drop over 2 bars, OI flush, then partial rebound.
                drop = rng.uniform(0.06, 0.12)
                rebound = drop * rng.uniform(0.35, 0.65)
                k = rng.randint(6, 12)
                pending = [(math.log(1 - drop) / 2, 4.5, math.log(0.88) / 2, -0.0015)] * 2
                pending += [(math.log(1 + rebound) / k, 1.6, 0.0, -0.0004)] * k

        z = rng.gauss(0, 1) * (2.5 if rng.random() < 0.05 else 1.0)
        lr = (drift - 0.5 * vol * vol) / bpy + vol / math.sqrt(bpy) * z
        vm, oi_lr, b_add = 1.0, 0.0, 0.0
        if pending:
            p_lr, vm, oi_lr, b_add = pending.pop(0)
            lr = p_lr + 0.3 * vol / math.sqrt(bpy) * z
        btc_lr.append(lr)
        ratio_x += -ratio_x / 40.0 + 0.012 * rng.gauss(0, 1)  # OU on log(ETH/BTC), half-life ~28 bars
        eth_extra.append(ratio_x)
        regimes.append(regime)
        shock_vol.append(vm * (1 + 1.5 * abs(z) / 2.5))
        oi_shock.append(oi_lr)
        basis_shock.append(b_add)

    def bars_from(closes: list[float], base_volume: float, vol_scale: list[float]) -> list[Bar]:
        out, prev = [], closes[0]
        for i, c in enumerate(closes):
            o = prev
            wick = abs(rng.gauss(0, 1)) * 0.004
            h = max(o, c) * (1 + wick)
            l = min(o, c) * (1 - wick * rng.uniform(0.5, 1.5))
            v = base_volume * vol_scale[i] * math.exp(rng.gauss(0, 0.3))
            out.append(Bar(ts[i], o, h, l, c, v))
            prev = c
        return out

    btc, eth = [], []
    lp_btc, lp_eth0 = math.log(20_000.0), math.log(1_200.0)
    cum = 0.0
    for i in range(n_bars):
        cum += btc_lr[i]
        btc.append(math.exp(lp_btc + cum))
        eth.append(math.exp(lp_eth0 + 1.15 * cum + eth_extra[i] + rng.gauss(0, 0.002)))

    basis_btc, basis_eth = [], []
    b_btc = b_eth = 0.0001
    for i in range(n_bars):
        mean = REGIMES[regimes[i]][2]
        b_btc += 0.15 * (mean - b_btc) + rng.gauss(0, 0.00012) + basis_shock[i] * 0.5
        b_eth += 0.15 * (mean * 1.2 - b_eth) + rng.gauss(0, 0.00015) + basis_shock[i] * 0.6
        basis_btc.append(b_btc)
        basis_eth.append(b_eth)

    btc_perp = [p * (1 + b) for p, b in zip(btc, basis_btc)]
    eth_perp = [p * (1 + b) for p, b in zip(eth, basis_eth)]

    data = MarketData(
        interval_ms=step,
        bars={
            "BTCUSDT": BarSeries("BTCUSDT", bars_from(btc, 6_000.0 * step / (4 * HOUR_MS), shock_vol)),
            "ETHUSDT": BarSeries("ETHUSDT", bars_from(eth, 80_000.0 * step / (4 * HOUR_MS), shock_vol)),
            "BTCUSDT-PERP": BarSeries("BTCUSDT-PERP", bars_from(btc_perp, 15_000.0 * step / (4 * HOUR_MS), shock_vol)),
            "ETHUSDT-PERP": BarSeries("ETHUSDT-PERP", bars_from(eth_perp, 250_000.0 * step / (4 * HOUR_MS), shock_vol)),
        },
    )

    # 8-hourly funding prints on the 00/08/16 UTC grid, driven by basis (premium) + noise.
    for perp, basis, prices in (("BTCUSDT-PERP", basis_btc, btc_perp), ("ETHUSDT-PERP", basis_eth, eth_perp)):
        pairs = []
        for i, t in enumerate(ts):
            if t % (8 * HOUR_MS) == 0:
                rate = 0.0001 + 0.5 * (basis[i] - 0.0001) + rng.gauss(0, 0.00004)
                pairs.append((t, max(-0.003, min(0.003, rate))))
        data.funding[perp] = Series.from_pairs(pairs)
        # Open interest (quote notional): coin OI drifts with regime and flushes in shocks.
        coin_oi, oi_pairs = 1.0, []
        for i, t in enumerate(ts):
            drift = {"bull": 0.0008, "bear": -0.0004, "range": 0.0001, "high_vol": -0.0002}[regimes[i]]
            coin_oi *= math.exp(drift + oi_shock[i] + rng.gauss(0, 0.004))
            base = 5e9 if perp.startswith("BTC") else 3e9
            oi_pairs.append((t, base * coin_oi * prices[i] / prices[0]))
        data.open_interest[perp] = Series.from_pairs(oi_pairs)

    # Daily stablecoin supply (USD), regime-driven.
    supply, pairs = 1.4e11, []
    for i, t in enumerate(ts):
        if t % DAY_MS == 0:
            supply *= 1 + REGIMES[regimes[i]][3] + rng.gauss(0, 0.0004)
            pairs.append((t, supply))
    data.macro["stablecoin_supply_usd"] = Series.from_pairs(pairs)
    data.provenance = {
        k: {"source": "synthetic", "synthetic": True, "seed": seed, "generator": "hedgefund.data.synthetic"}
        for k in [*data.bars, "funding", "open_interest", "stablecoin_supply_usd"]
    }
    return data

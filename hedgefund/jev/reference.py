"""ReferenceJev: a transparent, deterministic, offline implementation of the Jev contract.

Roles: (1) default engine in backtests and offline paper trading, (2) fallback baseline,
(3) shadow comparator for the remote model. It maps features to calibrated-looking
probabilities with fixed logistic curves. Its calibration is measured like any other model
(Brier score per question) - it earns no trust by being simple.
"""

from __future__ import annotations

import math
from typing import Any

from hedgefund.core.types import Direction, Regime
from hedgefund.jev.engine import AnswerEngine
from hedgefund.jev.schema import JevSchema, JevState

NATURAL_REGIMES = {
    "directional": {Regime.TRENDING},
    "carry": {Regime.TRENDING, Regime.MEAN_REVERTING},
    "reversion": {Regime.MEAN_REVERTING, Regime.HIGH_VOL},
    "macro": {Regime.TRENDING, Regime.MEAN_REVERTING},
    "relative_value": {Regime.MEAN_REVERTING},
}


def _sig(x: float) -> float:
    if x >= 0:
        return 1.0 / (1.0 + math.exp(-x))
    e = math.exp(x)
    return e / (1.0 + e)


def _softmax(logits: dict[str, float]) -> dict[str, float]:
    m = max(logits.values())
    ex = {k: math.exp(v - m) for k, v in logits.items()}
    s = sum(ex.values())
    return {k: v / s for k, v in ex.items()}


def _level_dist(mean: float, labels: tuple[str, ...], spread: float = 0.55) -> dict[str, float]:
    mean = min(max(mean, 0.0), len(labels) - 1.0)
    w = [math.exp(-((i - mean) ** 2) / (2 * spread * spread)) for i in range(len(labels))]
    s = sum(w)
    return {lab: x / s for lab, x in zip(labels, w)}


def _clamp(x: float, lo: float, hi: float) -> float:
    return min(max(x, lo), hi)


class ReferenceJev(AnswerEngine):
    model_version = "reference-jev-1.0"

    # ---- regime ----
    @staticmethod
    def regime_probs(f: dict[str, float]) -> dict[str, float]:
        rv_ratio = f.get("rv_ratio")
        er = f.get("er_10d")
        if rv_ratio is None or er is None:
            return {r.value: 0.25 for r in Regime}  # unknown state -> low confidence
        dd = min(f.get("dd_6d", 0.0), f.get("ret_1d", 0.0))
        c = _sig(4.0 * (rv_ratio - 2.3)) * _sig(40.0 * (-dd - 0.12))
        hv = _sig(5.0 * (rv_ratio - 1.6)) * (1 - c)
        tr = _sig(14.0 * (er - 0.30)) * (1 - c) * (1 - hv / max(1 - c, 1e-9))
        mr = max(0.0, 1.0 - c - hv - tr)
        return {"trending": tr, "mean_reverting": mr, "high_vol": hv, "crisis": c}

    # ---- direction (profile-specific evidence for the candidate package direction) ----
    @staticmethod
    def direction_logits(profile: str, f: dict[str, float]) -> dict[str, float]:
        flat = 1.0
        if profile == "directional":
            dv = f.get("daily_vol")
            if not dv or "mom_20d" not in f or "mom_60d" not in f:
                return {"long": 0.0, "short": 0.0, "flat": flat}
            z20 = f["mom_20d"] / (dv * math.sqrt(20))
            z60 = f["mom_60d"] / (dv * math.sqrt(60))
            blend = 0.5 * z20 + 0.5 * z60
            return {"long": 2.5 * blend, "short": -2.5 * blend, "flat": flat}
        if profile == "carry":
            fa = f.get("funding_avg_3d_ann")
            if fa is None:
                return {"long": 0.0, "short": -8.0, "flat": flat}
            return {"long": 25.0 * (fa - 0.06) + flat, "short": -8.0, "flat": flat}
        if profile == "reversion":
            rz = f.get("ret_z_1d", 0.0)
            oi = f.get("oi_chg_1d", 0.0)
            fl = f.get("funding_last_ann", 0.11)
            s = 1.2 * (-rz - 2.0) + 12.0 * (-oi - 0.04) + 4.0 * (0.11 - fl)
            return {"long": s, "short": -4.0, "flat": 0.5}
        if profile == "macro":
            g = f.get("stable_growth_30d")
            sma = f.get("close_vs_sma200")
            if g is None or sma is None:
                return {"long": 0.0, "short": -8.0, "flat": flat}
            return {"long": 150.0 * (g - 0.004) + 8.0 * sma + flat, "short": -8.0, "flat": flat}
        if profile == "relative_value":
            z = f.get("ratio_z")
            rer = f.get("ratio_er", 0.5)
            if z is None:
                return {"long": 0.0, "short": 0.0, "flat": flat}
            trend_penalty = 6.0 * max(0.0, rer - 0.25)
            return {"long": 1.5 * (-z - 1.5) - trend_penalty, "short": 1.5 * (z - 1.5) - trend_penalty, "flat": 0.5}
        return {"long": 0.0, "short": 0.0, "flat": flat}

    @staticmethod
    def setup_strength(profile: str, f: dict[str, float]) -> float:
        """0 = no setup, ~1 = textbook setup, >1 = unusually strong."""
        if profile == "directional":
            dv = f.get("daily_vol") or 1.0
            return abs(0.5 * f.get("mom_20d", 0.0) / (dv * math.sqrt(20)) + 0.5 * f.get("mom_60d", 0.0) / (dv * math.sqrt(60))) / 1.2
        if profile == "carry":
            return max(0.0, f.get("funding_avg_3d_ann", 0.0)) / 0.15
        if profile == "reversion":
            return max(0.0, -f.get("ret_z_1d", 0.0)) / 3.0
        if profile == "macro":
            return max(0.0, f.get("stable_growth_30d", 0.0)) / 0.015 * (1.0 if f.get("close_vs_sma200", 0.0) > 0 else 0.3)
        if profile == "relative_value":
            return abs(f.get("ratio_z", 0.0)) / 2.5
        return 0.0

    def answers(self, state: JevState, schema: JevSchema) -> dict[str, dict[str, Any]]:
        f = state.features
        profile = state.profile

        regime_p = self.regime_probs(f)
        p_crisis, p_hv = regime_p["crisis"], regime_p["high_vol"]
        regime = max(regime_p, key=regime_p.get)
        fit = 1.0 if Regime(regime) in NATURAL_REGIMES.get(profile, set()) else 0.0

        dir_p = _softmax(self.direction_logits(profile, f))

        setup_mean = 3.0 * _clamp(self.setup_strength(profile, f), 0.0, 1.2) / 1.2 - (0.0 if fit else 0.8)
        setup_p = _level_dist(setup_mean, schema.question("setup_quality").levels)

        vr = f.get("volume_ratio")
        rp = f.get("range_pct", 0.02)
        liq_mean = 2.7 + 0.8 * _clamp(math.log(vr), -2.0, 0.0) if vr else 1.5
        liq_mean -= 30.0 * max(0.0, rp - 0.04) + 1.5 * p_crisis
        liq_p = _level_dist(liq_mean, schema.question("liquidity_quality").levels)

        bz = abs(f.get("bar_ret_z", 0.0))
        tox_mean = 0.3 + 0.6 * max(0.0, bz - 2.0) + (0.8 * max(0.0, math.log(vr) - 0.7) if vr else 0.5)
        tox_mean += 8.0 * max(0.0, abs(f.get("oi_chg_1d", 0.0)) - 0.06)
        tox_p = _level_dist(tox_mean, schema.question("toxic_flow").levels)

        exp_level = lambda p: sum(i * v for i, v in enumerate(p.values()))  # noqa: E731
        setup_e, liq_e, tox_e = exp_level(setup_p), exp_level(liq_p), exp_level(tox_p)
        edge = 50 + 14 * (setup_e - 1.5) + 6 * (liq_e - 1.5) - 9 * tox_e + (8 if fit else -12) - 40 * p_crisis
        edge_p = _level_dist(_clamp(edge, 0, 100) / 25.0, schema.question("expected_edge").levels, spread=0.7)

        p_tox_high = sum(v for i, v in enumerate(tox_p.values()) if i >= 2)
        p_flat_risk = p_crisis
        p_reduce = (1 - p_crisis) * max(p_hv, p_tox_high, sum(v for i, v in enumerate(liq_p.values()) if i <= 1))
        risk_p = {"safe": max(0.0, 1 - p_flat_risk - p_reduce), "reduce": p_reduce, "flat": p_flat_risk}

        cand = state.candidate_direction
        p_dir_ok = dir_p.get(cand.value, 0.0) if cand is not Direction.FLAT else 0.0
        p_trade = _sig(0.15 * (edge - 55)) * (1 - p_crisis) * (1 - p_tox_high) * min(1.0, p_dir_ok / 0.5)

        return {
            "regime": {"probabilities": regime_p},
            "direction": {"probabilities": dir_p},
            "setup_quality": {"probabilities": setup_p},
            "liquidity_quality": {"probabilities": liq_p},
            "toxic_flow": {"probabilities": tox_p},
            "expected_edge": {"probabilities": edge_p},
            "risk_state": {"probabilities": risk_p},
            "should_trade": {"p_yes": _clamp(p_trade, 0.0, 1.0)},
        }

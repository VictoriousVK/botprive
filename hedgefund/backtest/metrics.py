"""Performance statistics, including the probabilistic and deflated Sharpe ratios
(Bailey & Lopez de Prado) that guard against overfitting and multiple testing."""

from __future__ import annotations

import math
from statistics import NormalDist
from typing import Sequence

EULER_GAMMA = 0.5772156649015329
_N = NormalDist()


def simple_returns(values: Sequence[float]) -> list[float]:
    return [values[i] / values[i - 1] - 1.0 for i in range(1, len(values)) if values[i - 1] > 0]


def _moments(r: Sequence[float]) -> tuple[float, float, float, float]:
    n = len(r)
    mean = sum(r) / n
    var = sum((x - mean) ** 2 for x in r) / (n - 1) if n > 1 else 0.0
    sd = math.sqrt(var)
    if sd == 0:
        return mean, 0.0, 0.0, 3.0
    skew = sum(((x - mean) / sd) ** 3 for x in r) / n
    kurt = sum(((x - mean) / sd) ** 4 for x in r) / n
    return mean, sd, skew, kurt


def sharpe(r: Sequence[float], periods_per_year: float) -> float:
    if len(r) < 2:
        return 0.0
    mean, sd, _, _ = _moments(r)
    return mean / sd * math.sqrt(periods_per_year) if sd > 0 else 0.0


def sortino(r: Sequence[float], periods_per_year: float) -> float:
    if len(r) < 2:
        return 0.0
    mean = sum(r) / len(r)
    dd = math.sqrt(sum(min(x, 0.0) ** 2 for x in r) / len(r))
    return mean / dd * math.sqrt(periods_per_year) if dd > 0 else 0.0


def max_drawdown(values: Sequence[float]) -> float:
    peak, mdd = -math.inf, 0.0
    for v in values:
        peak = max(peak, v)
        if peak > 0:
            mdd = max(mdd, 1.0 - v / peak)
    return mdd


def cagr(values: Sequence[float], periods_per_year: float) -> float:
    if len(values) < 2 or values[0] <= 0 or values[-1] <= 0:
        return 0.0
    years = (len(values) - 1) / periods_per_year
    return (values[-1] / values[0]) ** (1 / years) - 1.0 if years > 0 else 0.0


def probabilistic_sharpe(r: Sequence[float], sr_benchmark: float = 0.0) -> float:
    """P(true per-period Sharpe > benchmark), accounting for sample length, skew and kurtosis."""
    n = len(r)
    if n < 3:
        return 0.0
    mean, sd, skew, kurt = _moments(r)
    if sd == 0:
        return 0.0
    sr = mean / sd
    denom = 1 - skew * sr + (kurt - 1) / 4 * sr * sr
    if denom <= 0:
        return 0.0
    return _N.cdf((sr - sr_benchmark) * math.sqrt(n - 1) / math.sqrt(denom))


def deflated_sharpe(r: Sequence[float], n_trials: int, sr_variance: float | None = None) -> float:
    """PSR against the expected maximum Sharpe of ``n_trials`` unskilled strategies.
    If the cross-trial variance of Sharpe estimates is unknown, the estimator variance is used."""
    n = len(r)
    if n < 3:
        return 0.0
    if n_trials <= 1:
        return probabilistic_sharpe(r, 0.0)
    mean, sd, skew, kurt = _moments(r)
    if sd == 0:
        return 0.0
    sr = mean / sd
    v = sr_variance if sr_variance is not None else max((1 - skew * sr + (kurt - 1) / 4 * sr * sr) / (n - 1), 1e-12)
    sr0 = math.sqrt(v) * ((1 - EULER_GAMMA) * _N.inv_cdf(1 - 1 / n_trials) + EULER_GAMMA * _N.inv_cdf(1 - 1 / (n_trials * math.e)))
    return probabilistic_sharpe(r, sr0)


def fold_returns(values: Sequence[float], folds: int) -> list[float]:
    if len(values) < folds * 2:
        return []
    size = len(values) // folds
    out = []
    for k in range(folds):
        a, b = values[k * size], values[min((k + 1) * size, len(values) - 1)]
        out.append(b / a - 1.0 if a > 0 else 0.0)
    return out


def summarize(values: Sequence[float], periods_per_year: float, n_trials: int = 1, folds: int = 4) -> dict[str, float]:
    r = simple_returns(values)
    fr = fold_returns(values, folds)
    return {
        "total_return": values[-1] / values[0] - 1.0 if len(values) > 1 else 0.0,
        "cagr": cagr(values, periods_per_year),
        "vol": (_moments(r)[1] * math.sqrt(periods_per_year)) if len(r) > 1 else 0.0,
        "sharpe": sharpe(r, periods_per_year),
        "sortino": sortino(r, periods_per_year),
        "max_drawdown": max_drawdown(values),
        "psr": probabilistic_sharpe(r),
        "dsr": deflated_sharpe(r, n_trials),
        "fold_returns": fr,
        "fold_positive_frac": sum(1 for x in fr if x > 0) / len(fr) if fr else 0.0,
    }

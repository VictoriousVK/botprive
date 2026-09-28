"""Stress tests and robustness checks, and conversion of results into lifecycle evidence."""

from __future__ import annotations

import math
from dataclasses import replace
from typing import Any

from hedgefund.backtest.engine import BacktestConfig, BacktestResult, run_backtest
from hedgefund.config import FundConfig
from hedgefund.core.types import Bar
from hedgefund.data.series import BarSeries, MarketData, Series
from hedgefund.strategy.spec import StrategySpec, with_params


def inject_crash(data: MarketData, at_frac: float = 0.6, drop: float = 0.30, bars: int = 3, oi_flush: float = 0.35) -> MarketData:
    """Copy of ``data`` with a correlated crash: every price falls ``drop`` over ``bars`` bars
    starting at ``at_frac`` of the sample and never recovers the gap; volume x4 during the
    crash, funding pinned negative, open interest flushed."""
    out = MarketData(data.interval_ms, {}, dict(data.funding), dict(data.open_interest), dict(data.macro), dict(data.provenance))
    for sym, s in data.bars.items():
        k = int(len(s) * at_frac)
        bars_out = []
        for i in range(len(s)):
            if i < k:
                fo = fc = 1.0
            else:
                step_i = min(i - k + 1, bars)
                fc = (1 - drop) ** (step_i / bars)
                fo = (1 - drop) ** (max(step_i - 1, 0) / bars) if i - k < bars else fc
            vol_mult = 4.0 if k <= i < k + bars else 1.0
            o, c = s.open[i] * fo, s.close[i] * fc
            h = max(s.high[i] * max(fo, fc), o, c)
            l = min(s.low[i] * min(fo, fc), o, c)
            bars_out.append(Bar(s.ts[i], o, h, l, c, s.volume[i] * vol_mult))
        out.bars[sym] = BarSeries(sym, bars_out)
        t_start, t_end = s.ts[k], s.ts[min(k + bars, len(s) - 1)]
        if sym in data.funding:
            f = data.funding[sym]
            out.funding[sym] = Series(f.ts, [(-0.002 if t_start <= t <= t_end + 86_400_000 else v) for t, v in zip(f.ts, f.values)])
        if sym in data.open_interest:
            oi = data.open_interest[sym]
            out.open_interest[sym] = Series(oi.ts, [v * ((1 - oi_flush) if t >= t_start else 1.0) for t, v in zip(oi.ts, oi.values)])
    return out


SCENARIOS: dict[str, dict[str, Any]] = {
    "base": {},
    "fees_2x": {"fee_mult": 2.0},
    "slippage_3x": {"slippage_mult": 3.0},
    "delay_2": {"delay_bars": 2},
    "crash_30pct": {"crash": True},
}


def run_scenarios(data: MarketData, specs: list[StrategySpec], config: FundConfig, bt: BacktestConfig | None = None) -> dict[str, BacktestResult]:
    bt = bt or BacktestConfig()
    out = {}
    for name, sc in SCENARIOS.items():
        d = inject_crash(data) if sc.get("crash") else data
        cfg = replace(bt, **{k: v for k, v in sc.items() if k != "crash"})
        out[name] = run_backtest(d, specs, config, cfg)
    return out


def param_perturbation(data: MarketData, spec: StrategySpec, config: FundConfig, pct: float = 0.2, bt: BacktestConfig | None = None) -> dict[str, float]:
    """One-at-a-time +/-pct changes to every numeric parameter. A robust strategy shows no
    cliff: the minimum Sharpe across perturbations stays near the base Sharpe."""
    out = {}
    for k, v in spec.params.items():
        for sgn in (-1, 1):
            nv = v * (1 + sgn * pct)
            if float(v).is_integer():
                nv = float(max(1, round(nv)))
            if nv == v:
                continue
            res = run_backtest(data, [with_params(spec, **{k: nv})], config, bt)
            out[f"{k}{'+' if sgn > 0 else '-'}{int(pct * 100)}%"] = res.metrics["sharpe"]
    return out


def evaluate_stress(results: dict[str, BacktestResult], max_drawdown_limit: float) -> tuple[bool, list[str]]:
    reasons = []
    for name, r in results.items():
        if r.metrics["max_drawdown"] > max_drawdown_limit:
            reasons.append(f"{name}: drawdown {r.metrics['max_drawdown']:.1%} > {max_drawdown_limit:.0%}")
        if name != "crash_30pct" and r.metrics["sharpe"] < 0:
            reasons.append(f"{name}: negative Sharpe {r.metrics['sharpe']:.2f}")
    return not reasons, reasons


def backtest_evidence(r: BacktestResult) -> dict[str, Any]:
    closes = sum(m.get("closing_fills") or 0 for m in r.strategy_metrics.values())
    return {
        "synthetic": r.synthetic,
        "backtest.trades": closes,
        "backtest.sharpe": round(r.metrics["sharpe"], 4),
        "backtest.psr": round(r.metrics["psr"], 4),
        "backtest.dsr": round(r.metrics["dsr"], 4),
        "backtest.max_drawdown": round(r.metrics["max_drawdown"], 4),
        "backtest.fold_positive_frac": r.metrics["fold_positive_frac"],
    }


def cost_and_stress_evidence(results: dict[str, BacktestResult], perturb: dict[str, float], max_drawdown_limit: float) -> dict[str, Any]:
    passed, reasons = evaluate_stress(results, max_drawdown_limit)
    return {
        "synthetic": any(r.synthetic for r in results.values()),
        "cost.sharpe_2x_fees": round(results["fees_2x"].metrics["sharpe"], 4),
        "cost.sharpe_3x_slippage": round(results["slippage_3x"].metrics["sharpe"], 4),
        "cost.sharpe_delay_2": round(results["delay_2"].metrics["sharpe"], 4),
        "stress.passed": passed,
        "stress.reasons": reasons,
        "stress.worst_drawdown": round(max(r.metrics["max_drawdown"] for r in results.values()), 4),
        "stress.param_sharpe_min": round(min(perturb.values()), 4) if perturb else math.nan,
    }

"""Records every Jev probability, resolves it against what actually happened, and scores
calibration per (model_version, strategy, question). Drift in these scores is a first-class
alert: a confidently wrong fast model is the most dangerous failure in the stack.

Outcome definitions (fixed in code so they cannot be tuned after the fact):
  should_trade  1 if the candidate package's forward return over the horizon, including
                funding and minus round-trip cost assumptions, is > 0.
  direction     1 if the package moved in the predicted direction (flat predictions skipped).
  regime        1 if the ex-post regime label of the forward window equals the prediction.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any

from hedgefund.calibration.metrics import score
from hedgefund.core.ledger import Kind
from hedgefund.core.types import Direction, Signal
from hedgefund.data.series import MarketData
from hedgefund.jev.schema import JevDecision


@dataclass(frozen=True)
class Prediction:
    decision_id: str
    strategy_id: str
    model_version: str
    question: str
    predicted: str
    prob: float
    ts: int
    horizon_bars: int
    legs: tuple[tuple[str, float], ...]
    direction_sign: int
    cost_bps: float


def package_forward_return(data: MarketData, legs: tuple[tuple[str, float], ...], sign: int, t0: int, t1: int) -> float | None:
    """Return per unit of package notional (the policy sizes legs as weight * notional)."""
    tot, unit = 0.0, 0.0
    for sym, w in legs:
        s = data.bars.get(sym)
        if s is None:
            return None
        i0, i1 = s.upto(t0), s.upto(t1)
        if i0 == 0 or i1 == 0 or s.ts[i1 - 1] < t1 - data.interval_ms:
            return None
        r = s.close[i1 - 1] / s.close[i0 - 1] - 1.0
        f = data.funding.get(sym)
        funding = sum(v for _, v in f.between(t0, t1)) if f else 0.0
        tot += sign * w * (r - funding)
        unit = max(unit, abs(w))
    return tot / unit if unit else None


def realized_regime(data: MarketData, symbol: str, t0: int, t1: int) -> str | None:
    s = data.bars.get(symbol)
    if s is None:
        return None
    i0, i1 = s.upto(t0), s.upto(t1)
    if i1 - i0 < 3 or i0 < 60:
        return None
    closes = s.close[i0 - 1 : i1]
    if min(closes) / closes[0] - 1 <= -0.15:
        return "crisis"
    fwd = s.logret_stats(i1, i1 - i0)
    trail = s.logret_stats(i0, min(i0 - 1, 360))
    if fwd and trail and trail[1] > 0 and fwd[1] / trail[1] >= 1.6:
        return "high_vol"
    path = sum(abs(closes[k] - closes[k - 1]) for k in range(1, len(closes)))
    er = abs(closes[-1] - closes[0]) / path if path > 0 else 0.0
    return "trending" if er >= 0.30 else "mean_reverting"


class CalibrationTracker:
    def __init__(self, ledger: Any):
        self.ledger = ledger
        self.pending: list[Prediction] = []
        self.resolved: list[tuple[Prediction, int]] = []

    def record(self, decision: JevDecision, signal: Signal, horizon_bars: int, cost_bps: float) -> None:
        legs = tuple((l.symbol, l.weight) for l in signal.legs)
        base = dict(decision_id=decision.decision_id, strategy_id=decision.strategy_id, model_version=decision.model_version, ts=decision.ts, horizon_bars=horizon_bars, legs=legs, cost_bps=cost_bps)
        preds = [Prediction(question="should_trade", predicted="yes", prob=decision.p_trade, direction_sign=signal.direction.sign, **base)]
        if decision.direction is not Direction.FLAT:
            preds.append(Prediction(question="direction", predicted=decision.direction.value, prob=decision.probabilities["direction"][decision.direction.value], direction_sign=decision.direction.sign, **base))
        preds.append(Prediction(question="regime", predicted=decision.regime.value, prob=decision.probabilities["regime"][decision.regime.value], direction_sign=0, **base))
        for p in preds:
            if signal.direction is Direction.FLAT and p.question == "should_trade":
                continue
            self.pending.append(p)
            self.ledger.append(Kind.CALIBRATION_PREDICTION, asdict(p), ts=p.ts, ref=p.decision_id)

    def resolve(self, data: MarketData, now_ts: int) -> int:
        still, n = [], 0
        for p in self.pending:
            t1 = p.ts + p.horizon_bars * data.interval_ms
            if t1 > now_ts:
                still.append(p)
                continue
            outcome = self._outcome(data, p, t1)
            if outcome is None:
                if now_ts - t1 > 10 * p.horizon_bars * data.interval_ms:
                    continue  # unresolvable (data gap): drop rather than guess
                still.append(p)
                continue
            self.resolved.append((p, outcome))
            self.ledger.append(Kind.CALIBRATION_OUTCOME, {"decision_id": p.decision_id, "question": p.question, "prob": p.prob, "outcome": outcome, "model_version": p.model_version, "strategy_id": p.strategy_id}, ts=now_ts, ref=p.decision_id)
            n += 1
        self.pending = still
        return n

    @staticmethod
    def _outcome(data: MarketData, p: Prediction, t1: int) -> int | None:
        if p.question == "regime":
            r = realized_regime(data, p.legs[0][0], p.ts, t1)
            return None if r is None else int(r == p.predicted)
        ret = package_forward_return(data, p.legs, p.direction_sign or 1, p.ts, t1)
        if ret is None:
            return None
        if p.question == "direction":
            return int(ret > 0)
        return int(ret - p.cost_bps / 1e4 > 0)

    def report(self, group_by: tuple[str, ...] = ("model_version", "question")) -> dict[str, dict]:
        groups: dict[str, tuple[list[float], list[int]]] = {}
        for p, o in self.resolved:
            key = "|".join(str(getattr(p, g)) for g in group_by)
            probs, outs = groups.setdefault(key, ([], []))
            probs.append(p.prob)
            outs.append(o)
        return {k: score(v[0], v[1]) for k, v in sorted(groups.items())}

    @staticmethod
    def from_ledger_outcomes(ledger: Any, since_ts: int | None = None) -> dict[str, dict]:
        groups: dict[str, tuple[list[float], list[int]]] = {}
        for e in ledger.query(kind=Kind.CALIBRATION_OUTCOME, since_ts=since_ts):
            key = f"{e.payload['model_version']}|{e.payload['strategy_id']}|{e.payload['question']}"
            probs, outs = groups.setdefault(key, ([], []))
            probs.append(float(e.payload["prob"]))
            outs.append(int(e.payload["outcome"]))
        return {k: score(v[0], v[1]) for k, v in sorted(groups.items())}

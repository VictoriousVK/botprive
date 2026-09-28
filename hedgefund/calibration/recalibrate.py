"""Controlled recalibration of Jev probabilities (the "learning" loop).

1. Resolved predictions are split in time: fit on the earlier part, evaluate on the later.
2. A Platt map p' = sigmoid(a * logit(p) + b) is fitted per (strategy, question), regularized
   toward the identity. A map is kept only if it improves holdout Brier with enough samples.
3. The accepted maps form a content-addressed CalibrationBundle; the wrapped engine reports
   model_version "<inner>+cal-<hash>" so every decision is traceable to the exact maps.
4. The bundle is replay-tested (full backtest) before it may be configured for paper/shadow;
   deployment follows the same stage discipline as strategies.
Deterministic policy thresholds are unchanged: recalibration changes what Jev's numbers
mean, never what the policy or risk engine allow.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any, Iterable

from hedgefund.calibration.metrics import brier
from hedgefund.calibration.tracker import Prediction
from hedgefund.core.ids import content_hash
from hedgefund.core.types import Direction, Regime
from hedgefund.jev.engine import JevEngine
from hedgefund.jev.schema import JevDecision, JevSchema, JevState

_EPS = 1e-6


def _logit(p: float) -> float:
    p = min(max(p, _EPS), 1 - _EPS)
    return math.log(p / (1 - p))


def _sig(z: float) -> float:
    return 1 / (1 + math.exp(-z)) if z >= 0 else math.exp(z) / (1 + math.exp(z))


@dataclass(frozen=True)
class PlattMap:
    a: float = 1.0
    b: float = 0.0

    def apply(self, p: float) -> float:
        return _sig(self.a * _logit(p) + self.b)


A_MIN, A_MAX, B_MAX = 0.05, 5.0, 5.0


def fit_platt(probs: list[float], outcomes: list[int], l2: float | None = None, iters: int = 60) -> PlattMap:
    """Damped Newton-Raphson logistic regression on logit(p), with an L2 pull toward the
    identity (a=1, b=0) that scales with sample size, and hard bounds on (a, b)."""
    a, b = 1.0, 0.0
    xs = [_logit(p) for p in probs]
    l2 = l2 if l2 is not None else max(1.0, 0.02 * len(xs))
    for _ in range(iters):
        g_a = l2 * (a - 1.0)
        g_b = l2 * b
        h_aa = h_bb = l2
        h_ab = 0.0
        for x, y in zip(xs, outcomes):
            q = _sig(a * x + b)
            w = q * (1 - q)
            g_a += (q - y) * x
            g_b += q - y
            h_aa += w * x * x
            h_ab += w * x
            h_bb += w
        det = h_aa * h_bb - h_ab * h_ab
        if abs(det) < 1e-12:
            break
        da = (h_bb * g_a - h_ab * g_b) / det
        db = (h_aa * g_b - h_ab * g_a) / det
        da, db = max(-0.5, min(0.5, da)), max(-0.5, min(0.5, db))
        a, b = a - da, b - db
        if abs(da) < 1e-9 and abs(db) < 1e-9:
            break
    return PlattMap(round(a, 6), round(max(-B_MAX, min(B_MAX, b)), 6))


@dataclass(frozen=True)
class CalibrationBundle:
    maps: dict[str, PlattMap]  # key: "strategy_id|question"
    base_model: str
    report: dict[str, dict]

    @property
    def version(self) -> str:
        return content_hash({k: [m.a, m.b] for k, m in sorted(self.maps.items())} | {"base": self.base_model})[:10]

    def save(self, directory: Path) -> Path:
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / f"calibration-{self.version}.json"
        path.write_text(json.dumps({"version": self.version, "base_model": self.base_model, "maps": {k: [m.a, m.b] for k, m in self.maps.items()}, "report": self.report}, indent=1, sort_keys=True))
        return path

    @classmethod
    def load(cls, path: Path) -> "CalibrationBundle":
        raw = json.loads(Path(path).read_text())
        b = cls({k: PlattMap(*v) for k, v in raw["maps"].items()}, raw["base_model"], raw.get("report", {}))
        if b.version != raw["version"]:
            raise ValueError(f"calibration bundle {path} failed its integrity check")
        return b


def propose_bundle(resolved: Iterable[tuple[Prediction, int]], base_model: str, train_frac: float = 0.7, min_train: int = 60, min_test: int = 30) -> CalibrationBundle:
    groups: dict[str, list[tuple[Prediction, int]]] = {}
    for p, o in resolved:
        if p.model_version == base_model:
            groups.setdefault(f"{p.strategy_id}|{p.question}", []).append((p, o))
    maps, report = {}, {}
    for key, rows in sorted(groups.items()):
        rows.sort(key=lambda r: r[0].ts)
        cut = int(len(rows) * train_frac)
        train, test = rows[:cut], rows[cut:]
        if len(train) < min_train or len(test) < min_test:
            report[key] = {"accepted": False, "why": f"insufficient data (train {len(train)}, test {len(test)})"}
            continue
        m = fit_platt([p.prob for p, _ in train], [o for _, o in train])
        if m.a < A_MIN:
            # Confidence is uninformative or inversely related to accuracy. Recalibrating would
            # hide (or invert) a broken model; that needs investigation, not a patch.
            report[key] = {"accepted": False, "a": m.a, "b": m.b, "why": "no positive skill: investigate the model/schema"}
            continue
        m = PlattMap(min(m.a, A_MAX), m.b)
        tp, to = [p.prob for p, _ in test], [o for _, o in test]
        before, after = brier(tp, to), brier([m.apply(x) for x in tp], to)
        ok = after is not None and before is not None and after < before - 0.002
        report[key] = {"accepted": ok, "a": m.a, "b": m.b, "holdout_brier_before": round(before, 4), "holdout_brier_after": round(after, 4), "n_train": len(train), "n_test": len(test)}
        if ok:
            maps[key] = m
    return CalibrationBundle(maps, base_model, report)


def _rescale(dist: dict[str, float], label: str, new_top: float) -> dict[str, float]:
    rest = 1.0 - dist[label]
    out = {k: (new_top if k == label else (v / rest * (1 - new_top) if rest > 0 else (1 - new_top) / (len(dist) - 1))) for k, v in dist.items()}
    return out


class RecalibratedJev:
    def __init__(self, inner: JevEngine, bundle: CalibrationBundle):
        if bundle.base_model != inner.model_version:
            raise ValueError(f"bundle fitted for {bundle.base_model}, engine is {inner.model_version}")
        self.inner, self.bundle = inner, bundle
        self.model_version = f"{inner.model_version}+cal-{bundle.version}"

    def decide(self, state: JevState, schema: JevSchema) -> JevDecision:
        d = self.inner.decide(state, schema)
        probs = {k: dict(v) for k, v in d.probabilities.items()}
        sid = d.strategy_id
        m = self.bundle.maps.get(f"{sid}|should_trade")
        p_trade = m.apply(d.p_trade) if m else d.p_trade
        probs["should_trade"] = {"yes": p_trade, "no": 1 - p_trade}
        for q in ("regime", "direction"):
            mq = self.bundle.maps.get(f"{sid}|{q}")
            if mq:
                top = max(probs[q], key=probs[q].get)
                probs[q] = _rescale(probs[q], top, mq.apply(probs[q][top]))
        regime = Regime(max(sorted(probs["regime"]), key=lambda k: probs["regime"][k]))
        direction = Direction(max(sorted(probs["direction"]), key=lambda k: probs["direction"][k]))
        conf = min(max(probs["regime"].values()), max(probs["direction"].values()), max(probs["risk_state"].values()), max(p_trade, 1 - p_trade))
        return replace(
            d,
            regime=regime,
            direction=direction,
            p_trade=round(p_trade, 6),
            should_trade=p_trade >= 0.5,
            confidence=round(conf, 6),
            probabilities=probs,
            model_version=self.model_version,
        )


def bundle_summary(bundle: CalibrationBundle) -> dict[str, Any]:
    return {"version": bundle.version, "base_model": bundle.base_model, "accepted": sorted(bundle.maps), "report": bundle.report}

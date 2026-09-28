"""Golden set of the ICT engine: annotations, synthetic cases and evaluation.

Two datasets:
  * ``golden-v1`` (and later versions): real charts annotated by Victor (and a second annotator
    on part of them), through the admin tool. This is the reference; the engine is measured
    against it, never the other way round.
  * ``synthetic-v1``: generated bars with FVGs and swings planted at known places. Labels come
    from the construction, not from the engine, so the check is not circular. It guards against
    regressions and tests the evaluation pipeline; it does not prove the engine matches Victor.

Matching rules (versioned with the definitions): an FVG matches if same kind, same middle bar
(±1 bar) and edges within ``tol_atr`` × ATR; a swing matches if same kind and same bar.
"""

from __future__ import annotations

import random
from typing import Any

from pydantic import BaseModel, Field

from hedgefund.saas.engines import ict as E
from hedgefund.strategy.library.ict_core import Rates

TOL_ATR = 0.10


class Bar(BaseModel):
    t: int  # open time, UTC ms
    o: float
    h: float
    low: float = Field(alias="l")
    c: float

    model_config = {"populate_by_name": True}


class Labels(BaseModel):
    fvg: list[dict[str, Any]] = []  # {"kind": "BISI"|"SIBI", "t": mid bar open time, "top": x, "bottom": y}
    swings: list[dict[str, Any]] = []  # {"kind": "high"|"low", "t": bar open time, "price": x}
    sweeps: list[dict[str, Any]] = []  # {"side": "BSL"|"SSL", "level": x, "t": bar open time}
    mss: list[dict[str, Any]] = []  # {"direction": "bullish"|"bearish", "t": bar open time}
    setup: dict[str, Any] | None = None  # {"model": …, "direction": …, "valid": bool}


class Annotation(BaseModel):
    dataset: str = Field(min_length=3, max_length=40, pattern=r"^[a-z0-9._-]+$")
    symbol: str = Field(min_length=2, max_length=20)
    timeframe: str = Field(pattern=r"^(M1|M5|M15|H1)$")
    as_of: int
    bars: list[list[float]] = Field(min_length=30, max_length=600)  # [t, o, h, l, c], oldest first
    labels: Labels
    annotator: str = Field(min_length=2, max_length=60)
    rationale: str = Field(default="", max_length=4000)
    split: str = Field(default="dev", pattern=r"^(dev|holdout)$")


def rates_from_bars(bars: list[list[float]], step_ms: int) -> Rates:
    """Oldest-first [t, o, h, l, c] → MQL5 series order with the index-0 placeholder."""
    rev = list(reversed(bars))
    last = rev[0][4]
    return Rates([int(rev[0][0]) + step_ms] + [int(b[0]) for b in rev], [last] + [b[1] for b in rev], [last] + [b[2] for b in rev],
                 [last] + [b[3] for b in rev], [last] + [b[4] for b in rev], step_ms)


STEP = {"M1": 60_000, "M5": 300_000, "M15": 900_000, "H1": 3_600_000}


def detect(bars: list[list[float]], tf: str) -> dict[str, Any]:
    r = rates_from_bars(bars, STEP[tf])
    atr = r.atr(1) or 1e-9
    return {
        "atr": atr,
        "fvg": [{"kind": g.kind, "t": g.created_utc, "top": g.top, "bottom": g.bottom} for g in E.fvgs(r, tf, atr, max_look=len(bars))],
        "swings": [{"kind": s.kind, "t": s.time_utc, "price": s.price} for s in E.swings(r, tf, max_each=10_000, max_look=len(bars))],
    }


def _match_fvg(a: dict[str, Any], b: dict[str, Any], step: int, tol: float) -> bool:
    return a["kind"] == b["kind"] and abs(int(a["t"]) - int(b["t"])) <= step and abs(a["top"] - b["top"]) <= tol and abs(a["bottom"] - b["bottom"]) <= tol


def _pr(labels: list[dict[str, Any]], found: list[dict[str, Any]], match) -> dict[str, Any]:
    used: set[int] = set()
    tp = 0
    missed = []
    for lab in labels:
        hit = next((i for i, f in enumerate(found) if i not in used and match(lab, f)), None)
        if hit is None:
            missed.append(lab)
        else:
            used.add(hit)
            tp += 1
    extra = [f for i, f in enumerate(found) if i not in used]
    return {"labels": len(labels), "found": len(found), "tp": tp, "precision": round(tp / len(found), 4) if found else None,
            "recall": round(tp / len(labels), 4) if labels else None, "missed": missed[:10], "extra": extra[:10]}


def evaluate_case(a: Annotation | dict[str, Any], tol_atr: float = TOL_ATR) -> dict[str, Any]:
    a = a if isinstance(a, Annotation) else Annotation.model_validate(a)
    det = detect(a.bars, a.timeframe)
    step = STEP[a.timeframe]
    tol = tol_atr * det["atr"]
    # The engine cannot confirm the last swing_strength bars: labels there are not counted.
    last_t = a.bars[-3][0] if len(a.bars) > 3 else a.bars[-1][0]
    sw_labels = [s for s in a.labels.swings if s["t"] < last_t and s["t"] > a.bars[2][0]]
    fvg_labels = [g for g in a.labels.fvg if a.bars[1][0] <= g["t"] <= a.bars[-2][0]]
    return {
        "fvg": _pr(fvg_labels, det["fvg"], lambda x, y: _match_fvg(x, y, step, tol)),
        "swings": _pr(sw_labels, [s for s in det["swings"] if s["t"] < last_t and s["t"] > a.bars[2][0]], lambda x, y: x["kind"] == y["kind"] and int(x["t"]) == int(y["t"])),
    }


def aggregate(results: list[dict[str, Any]]) -> dict[str, Any]:
    out = {}
    for key in ("fvg", "swings"):
        tp = sum(r[key]["tp"] for r in results)
        found = sum(r[key]["found"] for r in results)
        labels = sum(r[key]["labels"] for r in results)
        out[key] = {"cases": len(results), "labels": labels, "found": found, "tp": tp, "precision": round(tp / found, 4) if found else None, "recall": round(tp / labels, 4) if labels else None}
    return out


# ---------------------------------------------------------------- synthetic set
def synthetic_case(seed: int, n: int = 120, tf: str = "M5") -> dict[str, Any]:
    """A zigzag of overlapping bars (no FVG, swings exactly at the turning points) with two FVGs
    planted by strong three-candle moves. Labels come from the construction."""
    rng = random.Random(seed)
    step = STEP[tf]
    t0 = 1_790_000_000_000 - (1_790_000_000_000 % step)
    price = 2000.0 + rng.random() * 100
    bars: list[list[float]] = []
    labels: dict[str, list[dict[str, Any]]] = {"fvg": [], "swings": []}
    leg = rng.randint(6, 9)
    up = rng.random() < 0.5
    k = 0
    plant_at = sorted(rng.sample(range(20, n - 20), 2))
    while len(bars) < n:
        i = len(bars)
        if plant_at and i == plant_at[0] and k >= 2 and k <= leg - 4:
            plant_at.pop(0)
            gap = 1.5 + rng.random()
            d = 1 if up else -1
            prev = bars[-1]
            o = prev[4]
            c = o + d * (gap + 1.2)
            big = [t0 + i * step, o, max(o, c) + 0.05, min(o, c) - 0.05, c]
            bars.append(big)
            o2 = c
            c2 = o2 + d * 0.3
            nxt = [t0 + (i + 1) * step, o2, max(o2, c2) + 0.05, min(o2, c2) - 0.05, c2]
            bars.append(nxt)
            if d == 1:
                labels["fvg"].append({"kind": "BISI", "t": big[0], "top": nxt[3], "bottom": prev[2]})
            else:
                labels["fvg"].append({"kind": "SIBI", "t": big[0], "top": prev[3], "bottom": nxt[2]})
            price = c2
            k += 2
            continue
        d = 1 if up else -1
        o = price
        c = o + d * (0.15 + rng.random() * 0.1)
        # The first bar of a leg keeps a short wick toward the previous extreme, so the turning
        # point is a strict extreme (no equal highs/lows created by the construction itself).
        back = 0.1 if k == 0 and i > 0 else 0.3
        hi_w, lo_w = (0.3, back) if d == 1 else (back, 0.3)
        bars.append([t0 + i * step, o, max(o, c) + hi_w, min(o, c) - lo_w, c])
        price = c
        k += 1
        if k >= leg:
            last = bars[-1]
            labels["swings"].append({"kind": "high" if up else "low", "t": last[0], "price": last[2] if up else last[3]})
            up = not up
            k = 0
            leg = rng.randint(6, 9)
    return {"dataset": "synthetic-v1", "symbol": "SYNTH", "timeframe": tf, "as_of": bars[-1][0] + step, "bars": bars, "labels": labels,
            "annotator": "construction", "rationale": "FVG et swings plantés par construction", "split": "dev"}


def synthetic_set(n_cases: int = 40, seed: int = 1) -> list[dict[str, Any]]:
    return [synthetic_case(seed * 1000 + i) for i in range(n_cases)]

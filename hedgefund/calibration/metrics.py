"""Probability-forecast scoring."""

from __future__ import annotations

import math
from typing import Sequence


def brier(probs: Sequence[float], outcomes: Sequence[int]) -> float | None:
    if not probs:
        return None
    return sum((p - o) ** 2 for p, o in zip(probs, outcomes)) / len(probs)


def log_loss(probs: Sequence[float], outcomes: Sequence[int], eps: float = 1e-6) -> float | None:
    if not probs:
        return None
    tot = 0.0
    for p, o in zip(probs, outcomes):
        p = min(max(p, eps), 1 - eps)
        tot -= o * math.log(p) + (1 - o) * math.log(1 - p)
    return tot / len(probs)


def brier_skill_score(probs: Sequence[float], outcomes: Sequence[int]) -> float | None:
    """1 - Brier / Brier(climatology). > 0 means better than always predicting the base rate."""
    if not probs:
        return None
    base = sum(outcomes) / len(outcomes)
    ref = sum((base - o) ** 2 for o in outcomes) / len(outcomes)
    b = brier(probs, outcomes)
    if ref == 0 or b is None:
        return None
    return 1 - b / ref


def reliability(probs: Sequence[float], outcomes: Sequence[int], n_bins: int = 10) -> list[dict]:
    bins: list[list[tuple[float, int]]] = [[] for _ in range(n_bins)]
    for p, o in zip(probs, outcomes):
        bins[min(int(p * n_bins), n_bins - 1)].append((p, o))
    out = []
    for i, b in enumerate(bins):
        if b:
            out.append({
                "bin": f"{i / n_bins:.1f}-{(i + 1) / n_bins:.1f}",
                "n": len(b),
                "mean_prob": sum(p for p, _ in b) / len(b),
                "frequency": sum(o for _, o in b) / len(b),
            })
    return out


def ece(probs: Sequence[float], outcomes: Sequence[int], n_bins: int = 10) -> float | None:
    """Expected calibration error: weighted |mean prob - observed frequency| across bins."""
    if not probs:
        return None
    n = len(probs)
    return sum(r["n"] / n * abs(r["mean_prob"] - r["frequency"]) for r in reliability(probs, outcomes, n_bins))


def score(probs: Sequence[float], outcomes: Sequence[int]) -> dict:
    return {
        "n": len(probs),
        "base_rate": sum(outcomes) / len(outcomes) if outcomes else None,
        "mean_prob": sum(probs) / len(probs) if probs else None,
        "brier": brier(probs, outcomes),
        "brier_skill": brier_skill_score(probs, outcomes),
        "log_loss": log_loss(probs, outcomes),
        "ece": ece(probs, outcomes),
    }

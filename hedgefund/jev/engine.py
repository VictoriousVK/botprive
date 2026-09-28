"""Jev engine interface, latency budget enforcement and shadow comparison."""

from __future__ import annotations

import time
from typing import Any, Callable, Protocol

from hedgefund.core.ids import stable_id
from hedgefund.jev.schema import JevDecision, JevSchema, JevState, decision_from_answers


class JevUnavailable(RuntimeError):
    """Engine could not answer within budget. Callers must fail closed (no new risk)."""


class JevEngine(Protocol):
    model_version: str

    def decide(self, state: JevState, schema: JevSchema) -> JevDecision: ...


class AnswerEngine:
    """Base for engines that produce typed answers; shares validation via decision_from_answers."""

    model_version = "unknown"

    def answers(self, state: JevState, schema: JevSchema) -> dict[str, dict[str, Any]]:
        raise NotImplementedError

    def decide(self, state: JevState, schema: JevSchema) -> JevDecision:
        t0 = time.perf_counter()
        ans = self.answers(state, schema)
        latency = (time.perf_counter() - t0) * 1000
        did = stable_id("jev", state.strategy_id, state.package, state.ts, self.model_version, state.state_hash)
        return decision_from_answers(did, state, schema, ans, self.model_version, latency)


class BudgetedJev:
    """Enforces the latency budget: an answer that arrives late is treated as no answer."""

    def __init__(self, inner: JevEngine, timeout_ms: float):
        self.inner = inner
        self.timeout_ms = timeout_ms
        self.model_version = inner.model_version

    def decide(self, state: JevState, schema: JevSchema) -> JevDecision:
        d = self.inner.decide(state, schema)
        if d.latency_ms > self.timeout_ms:
            raise JevUnavailable(f"{self.model_version}: {d.latency_ms:.0f}ms > budget {self.timeout_ms:.0f}ms")
        return d


class ShadowJev:
    """Primary engine decides; shadow engine runs on the same state and the comparison is
    reported through ``on_shadow``. Shadow failures never affect the primary path."""

    def __init__(self, primary: JevEngine, shadow: JevEngine, on_shadow: Callable[[JevDecision, JevDecision | None, str | None], None]):
        self.primary, self.shadow, self.on_shadow = primary, shadow, on_shadow
        self.model_version = primary.model_version

    def decide(self, state: JevState, schema: JevSchema) -> JevDecision:
        d = self.primary.decide(state, schema)
        try:
            s = self.shadow.decide(state, schema)
            self.on_shadow(d, s, None)
        except Exception as e:  # noqa: BLE001 - shadow must never break the primary path
            self.on_shadow(d, None, f"{type(e).__name__}: {e}")
        return d

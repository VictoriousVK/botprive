"""Remote Jev adapter (TypeSafe Jev over HTTPS).

STATUS: WIRE FORMAT UNVERIFIED. At build time the official API reference
(https://docs.typesafe.ai/api) was not reachable from the build environment. What is known
from public descriptions: Jev takes a state plus typed questions of three kinds - Choice,
Score (ordered rubric of 2-10 levels) and Noul (a yes/no probability) - and returns typed
answers with calibrated confidence in roughly 70-500 ms.

Everything provider-specific is isolated in ``ProvisionalCodec``. Before enabling:
  1. Confirm endpoint, auth header, request and response field names against the official docs.
  2. Adjust ``ProvisionalCodec`` (or subclass it) and extend tests/test_jev_remote.py with a
     recorded real response.
  3. Set JEV_WIRE_FORMAT_VERIFIED=1. Without it the adapter refuses to start.
There is deliberately no default URL: JEV_API_URL must be set explicitly.
"""

from __future__ import annotations

import os
import time
from typing import Any

import requests

from hedgefund.core.ids import stable_id
from hedgefund.jev.engine import JevUnavailable
from hedgefund.jev.schema import JevDecision, JevSchema, JevSchemaError, JevState, decision_from_answers


class JevConfigError(RuntimeError):
    pass


class ProvisionalCodec:
    """Maps our typed questions to a request body and the provider response back to
    ``{key: {"probabilities": {...}} | {"p_yes": float}}``. Field names are provisional."""

    kind_names = {"choice": "choice", "score": "score", "binary": "noul"}

    def encode(self, state: JevState, schema: JevSchema, model: str) -> dict[str, Any]:
        questions = []
        for q in schema.questions:
            item: dict[str, Any] = {"id": q.key, "type": self.kind_names[q.kind], "instructions": q.prompt}
            if q.kind == "choice":
                item["options"] = list(q.options)
            elif q.kind == "score":
                item["levels"] = list(q.levels)
            questions.append(item)
        return {"model": model, "state": state.text(), "questions": questions}

    def decode(self, body: dict[str, Any], schema: JevSchema) -> dict[str, dict[str, Any]]:
        raw = body.get("answers")
        if not isinstance(raw, dict):
            raise JevSchemaError("response has no 'answers' object")
        out: dict[str, dict[str, Any]] = {}
        for q in schema.questions:
            a = raw.get(q.key)
            if not isinstance(a, dict):
                raise JevSchemaError(f"no answer for {q.key}")
            if q.kind == "binary":
                p = a.get("probability", a.get("value"))
                out[q.key] = {"p_yes": p}
            else:
                probs = a.get("probabilities")
                if not isinstance(probs, dict):
                    # Degrade to a point answer: all mass on the chosen value, scaled by confidence.
                    choice, conf = a.get("value"), a.get("confidence")
                    labels = q.options if q.kind == "choice" else q.levels
                    if choice not in labels or not isinstance(conf, (int, float)):
                        raise JevSchemaError(f"{q.key}: cannot interpret answer {a!r}")
                    rest = (1 - float(conf)) / max(1, len(labels) - 1)
                    probs = {l: (float(conf) if l == choice else rest) for l in labels}
                out[q.key] = {"probabilities": probs}
        return out


class RemoteJev:
    def __init__(
        self,
        api_url: str,
        api_key: str,
        model: str,
        timeout_ms: float = 250,
        codec: ProvisionalCodec | None = None,
        session: requests.Session | None = None,
        wire_format_verified: bool | None = None,
    ):
        verified = wire_format_verified if wire_format_verified is not None else os.environ.get("JEV_WIRE_FORMAT_VERIFIED") == "1"
        if not verified:
            raise JevConfigError(
                "RemoteJev wire format is unverified. Confirm the codec against the official Jev API docs, "
                "then set JEV_WIRE_FORMAT_VERIFIED=1. Until then use jev.engine: reference."
            )
        if not api_url or not api_key:
            raise JevConfigError("JEV_API_URL and JEV_API_KEY are required")
        self.api_url, self.api_key, self.model = api_url, api_key, model
        self.timeout_s = timeout_ms / 1000.0
        self.codec = codec or ProvisionalCodec()
        self.session = session or requests.Session()
        self.model_version = f"jev:{model}"

    @classmethod
    def from_env(cls, timeout_ms: float = 250) -> "RemoteJev":
        return cls(
            api_url=os.environ.get("JEV_API_URL", ""),
            api_key=os.environ.get("JEV_API_KEY", ""),
            model=os.environ.get("JEV_MODEL", "jev"),
            timeout_ms=timeout_ms,
        )

    def decide(self, state: JevState, schema: JevSchema) -> JevDecision:
        body = self.codec.encode(state, schema, self.model)
        t0 = time.perf_counter()
        try:
            r = self.session.post(
                self.api_url,
                json=body,
                headers={"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json"},
                timeout=self.timeout_s,
            )
        except requests.RequestException as e:
            raise JevUnavailable(f"transport: {e}") from e
        latency = (time.perf_counter() - t0) * 1000
        if r.status_code != 200:
            raise JevUnavailable(f"HTTP {r.status_code}: {r.text[:200]}")
        try:
            answers = self.codec.decode(r.json(), schema)
        except ValueError as e:
            raise JevSchemaError(f"undecodable response: {e}") from e
        did = stable_id("jev", state.strategy_id, state.package, state.ts, self.model_version, state.state_hash)
        return decision_from_answers(did, state, schema, answers, self.model_version, latency)

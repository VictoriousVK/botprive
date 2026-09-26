"""Model layer: registry of approved models, provider abstraction, tool loop, costs.

Business code only knows logical keys (``router``, ``coach``, ``analyste``…); the registry
(``config/models.yaml``) pins exact model IDs and prices (ADR-006). Claude is called through
the official SDK with structured outputs (``output_config.format``), a cached system prompt
and client tools; the answer is validated again with Pydantic.

Without an API key the layer is ``NullLLM``: agents then return their deterministic output
with a visible "narration indisponible" caveat, never an invented text.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Protocol, TypeVar

import yaml
from pydantic import BaseModel, ValidationError

from hedgefund.saas.harness import Budget, CircuitBreaker, HarnessError, current_tracer

M = TypeVar("M", bound=BaseModel)
CONFIG = Path(__file__).resolve().parents[2] / "config" / "models.yaml"
SUPPORTED_FORMATS = {"date-time", "time", "date", "duration", "email", "hostname", "uri", "ipv4", "ipv6", "uuid"}
DROP_KEYS = {"minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf", "minLength", "maxLength", "pattern", "minItems", "maxItems", "uniqueItems", "default", "title", "examples"}


class LLMError(HarnessError):
    pass


class LLMUnavailable(LLMError):
    pass


class LLMRefused(LLMError):
    pass


# ---------------------------------------------------------------- registry
class ModelSpec(BaseModel):
    key: str
    model: str
    max_tokens: int = 4000
    effort: str | None = None
    price_in: float  # $ per million input tokens
    price_out: float
    cache_read_multiplier: float = 0.1
    cache_write_multiplier: float = 1.25

    def cost(self, usage: dict[str, int]) -> float:
        base = self.price_in / 1e6
        return (
            usage.get("input_tokens", 0) * base
            + usage.get("cache_read_input_tokens", 0) * base * self.cache_read_multiplier
            + usage.get("cache_creation_input_tokens", 0) * base * self.cache_write_multiplier
            + usage.get("output_tokens", 0) * self.price_out / 1e6
        )


class ModelRegistry:
    def __init__(self, specs: dict[str, ModelSpec], batch_discount: float = 0.5):
        self.specs, self.batch_discount = specs, batch_discount

    @classmethod
    def load(cls, path: Path | None = None) -> "ModelRegistry":
        raw = yaml.safe_load((path or CONFIG).read_text(encoding="utf-8"))
        cache = raw.get("cache", {})
        specs = {}
        for key, body in raw["models"].items():
            specs[key] = ModelSpec(key=key, cache_read_multiplier=cache.get("read_multiplier", 0.1), cache_write_multiplier=cache.get("write_multiplier", 1.25), **body)
        return cls(specs, float(raw.get("batch_discount", 0.5)))

    def get(self, key: str) -> ModelSpec:
        if key not in self.specs:
            raise LLMError(f"modèle non enregistré : {key}")
        return self.specs[key]

    def ids(self) -> dict[str, str]:
        return {k: s.model for k, s in self.specs.items()}


# ---------------------------------------------------------------- schema
def strict_schema_dict(schema: dict[str, Any]) -> dict[str, Any]:
    """Pydantic JSON schema → the subset structured outputs accept: every object closed and
    fully required, unsupported constraints dropped (Pydantic re-checks them afterwards)."""

    def walk(node: Any) -> Any:
        if isinstance(node, list):
            return [walk(x) for x in node]
        if not isinstance(node, dict):
            return node
        out = {}
        for k, v in node.items():
            if k in DROP_KEYS:
                continue
            if k == "format" and v not in SUPPORTED_FORMATS:
                continue
            if k == "prefixItems":  # tuples: loosen to a plain array
                continue
            out[k] = walk(v)
        if "prefixItems" in node:
            types = [walk(x) for x in node["prefixItems"]]
            out["items"] = types[0] if all(t == types[0] for t in types) else {"anyOf": types}
            out["type"] = "array"
        if out.get("type") == "object" or "properties" in out:
            props = out.get("properties", {})
            out["type"] = "object"
            out["properties"] = props
            out["required"] = list(props.keys())
            out["additionalProperties"] = False
        return out

    return walk(schema)


def strict_schema(model: type[BaseModel]) -> dict[str, Any]:
    return strict_schema_dict(model.model_json_schema())


# ---------------------------------------------------------------- results
@dataclass
class LLMResult:
    data: BaseModel
    model: str
    usage: dict[str, int]
    cost_usd: float
    tool_calls: list[dict[str, Any]] = field(default_factory=list)


class LLM(Protocol):
    available: bool

    def run(self, spec: ModelSpec, system: str, user: str, output: type[M], budget: Budget, tools: list[dict[str, Any]] | None = None, execute_tool: Any = None, max_turns: int = 6) -> LLMResult: ...


def _usage(u: Any) -> dict[str, int]:
    return {k: int(getattr(u, k, 0) or 0) for k in ("input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")}


def _parse(output: type[M], text: str) -> M:
    try:
        return output.model_validate(json.loads(text))
    except (json.JSONDecodeError, ValidationError) as e:
        raise LLMError(f"réponse hors schéma : {str(e)[:300]}") from e


class NullLLM:
    """No provider configured: callers fall back to their deterministic output."""

    available = False

    def run(self, *a: Any, **k: Any) -> LLMResult:
        raise LLMUnavailable("aucun modèle configuré (ANTHROPIC_API_KEY absente)")


class AnthropicLLM:
    available = True

    def __init__(self, client: Any = None, breaker: CircuitBreaker | None = None):
        if client is None:
            import anthropic

            client = anthropic.Anthropic(max_retries=2, timeout=90.0)
        self.client = client
        self.breaker = breaker or CircuitBreaker("anthropic")

    def _create(self, spec: ModelSpec, system: str, messages: list[dict[str, Any]], output: type[BaseModel], tools: list[dict[str, Any]] | None) -> Any:
        cfg: dict[str, Any] = {"format": {"type": "json_schema", "schema": strict_schema(output)}}
        if spec.effort:
            cfg["effort"] = spec.effort
        kw: dict[str, Any] = {
            "model": spec.model,
            "max_tokens": spec.max_tokens,
            "system": [{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}],
            "messages": messages,
            "output_config": cfg,
        }
        if tools:
            kw["tools"] = tools
        return self.client.messages.create(**kw)

    def run(self, spec: ModelSpec, system: str, user: str, output: type[M], budget: Budget, tools: list[dict[str, Any]] | None = None, execute_tool: Any = None, max_turns: int = 6) -> LLMResult:
        tracer = current_tracer()
        messages: list[dict[str, Any]] = [{"role": "user", "content": user}]
        total: dict[str, int] = {}
        cost = 0.0
        calls: list[dict[str, Any]] = []
        repaired = False
        for _turn in range(max_turns):
            budget.before_llm()
            self.breaker.before()
            span = tracer.span(f"modèle {spec.key}", kind="llm", model=spec.model) if tracer else None
            attrs: dict[str, Any] = span.__enter__() if span else {}
            try:
                resp = self._create(spec, system, messages, output, tools)
                self.breaker.success()
            except Exception as e:
                self.breaker.failure()
                if span:
                    span.__exit__(type(e), e, None)
                raise LLMError(f"appel au modèle impossible : {str(e)[:200]}") from e
            u = _usage(resp.usage)
            c = spec.cost(u)
            budget.charge_llm(u["input_tokens"] + u["cache_read_input_tokens"] + u["cache_creation_input_tokens"], u["output_tokens"], c)
            for k, v in u.items():
                total[k] = total.get(k, 0) + v
            cost += c
            attrs.update(usage=u, cost_usd=round(c, 6), stop_reason=resp.stop_reason)
            if span:
                span.__exit__(None, None, None)
            if resp.stop_reason == "refusal":
                raise LLMRefused("le modèle a refusé de répondre")
            if resp.stop_reason == "max_tokens":
                raise LLMError("réponse tronquée (max_tokens)")
            if resp.stop_reason == "tool_use" and execute_tool is not None:
                messages.append({"role": "assistant", "content": resp.content})
                results = []
                for b in resp.content:
                    if getattr(b, "type", None) == "tool_use":
                        res = execute_tool(b.name, dict(b.input or {}))
                        calls.append({"name": b.name, "input": dict(b.input or {}), "ok": res.get("ok")})
                        results.append({"type": "tool_result", "tool_use_id": b.id, "content": json.dumps(res, ensure_ascii=False), "is_error": not res.get("ok", False)})
                messages.append({"role": "user", "content": results})
                continue
            text = "".join(b.text for b in resp.content if getattr(b, "type", None) == "text")
            try:
                data = _parse(output, text)
            except LLMError as e:
                if repaired:
                    raise
                repaired = True
                messages.append({"role": "assistant", "content": resp.content})
                messages.append({"role": "user", "content": f"Votre réponse ne respecte pas le schéma ({e}). Renvoyez uniquement un JSON valide."})
                continue
            return LLMResult(data, getattr(resp, "model", spec.model), total, cost, calls)
        raise LLMError(f"{max_turns} tours sans réponse finale")


# ---------------------------------------------------------------- test double
@dataclass
class _Block:
    type: str
    text: str = ""
    name: str = ""
    input: dict[str, Any] | None = None
    id: str = ""


@dataclass
class _Usage:
    input_tokens: int = 1200
    output_tokens: int = 300
    cache_read_input_tokens: int = 0
    cache_creation_input_tokens: int = 0


@dataclass
class _Resp:
    content: list[_Block]
    stop_reason: str
    usage: _Usage = field(default_factory=_Usage)
    model: str = "scripted"


class ScriptedClient:
    """Stands in for ``anthropic.Anthropic`` in tests: replays scripted turns and records the
    requests. A turn is a dict (final JSON), ``{"tool": name, "input": {…}}``, or
    ``{"refusal": True}``."""

    def __init__(self, turns: list[Any]):
        self.turns = list(turns)
        self.requests: list[dict[str, Any]] = []
        self.messages = self

    def create(self, **kw: Any) -> _Resp:
        self.requests.append(kw)
        if not self.turns:
            raise RuntimeError("script épuisé")
        t = self.turns.pop(0)
        if callable(t):
            t = t(kw)
        if isinstance(t, dict) and t.get("refusal"):
            return _Resp([], "refusal")
        if isinstance(t, dict) and "tool" in t:
            return _Resp([_Block("tool_use", name=t["tool"], input=t.get("input", {}), id=f"tu_{len(self.requests)}")], "tool_use")
        text = t if isinstance(t, str) else json.dumps(t)
        return _Resp([_Block("text", text=text)], "end_turn")


def make_llm() -> LLM:
    if os.environ.get("ANTHROPIC_API_KEY", "").strip() and os.environ.get("HF_LLM", "anthropic") != "off":
        try:
            return AnthropicLLM()
        except Exception:  # noqa: BLE001 - SDK missing: run without narration
            return NullLLM()
    return NullLLM()

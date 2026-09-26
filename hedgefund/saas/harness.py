"""The agent harness: everything that must not be left to a model.

Timeouts on external calls, retries only for read-only tools, idempotency keys for writes, a
circuit breaker per provider, per-run budgets (LLM calls, tokens, deadline), no-progress
detection, the version manifest attached to every trace, and spans stored with each run so the
member sees the agents work step by step.
"""

from __future__ import annotations

import concurrent.futures as cf
import contextvars
import hashlib
import json
import logging
import os
import subprocess
import threading
import time
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, TypeVar

from pydantic import BaseModel, ValidationError

from hedgefund.saas.db import Database, agent_runs, audit_records, new_id, now_ms, spans, version_manifests

log = logging.getLogger("hedgefund.saas")
T = TypeVar("T")
ROOT = Path(__file__).resolve().parents[2]
_POOL = cf.ThreadPoolExecutor(max_workers=16, thread_name_prefix="harness")


# ---------------------------------------------------------------- errors
class HarnessError(RuntimeError):
    pass


class BudgetExceeded(HarnessError):
    pass


class NoProgress(HarnessError):
    pass


class CircuitOpen(HarnessError):
    pass


class ToolFailed(HarnessError):
    pass


# ---------------------------------------------------------------- budget
@dataclass
class Budget:
    max_llm_calls: int = 3
    max_input_tokens: int = 30_000
    max_output_tokens: int = 4_000
    deadline_s: float = 60.0
    max_tool_calls: int = 8
    started: float = field(default_factory=time.monotonic)
    llm_calls: int = 0
    input_tokens: int = 0
    output_tokens: int = 0
    tool_calls: int = 0
    cost_usd: float = 0.0

    def remaining_s(self) -> float:
        return self.deadline_s - (time.monotonic() - self.started)

    def check(self) -> None:
        if self.remaining_s() <= 0:
            raise BudgetExceeded(f"délai dépassé ({self.deadline_s:.0f} s)")

    def before_llm(self) -> None:
        self.check()
        if self.llm_calls >= self.max_llm_calls:
            raise BudgetExceeded(f"{self.max_llm_calls} appels au modèle maximum")
        if self.input_tokens >= self.max_input_tokens or self.output_tokens >= self.max_output_tokens:
            raise BudgetExceeded("budget de tokens épuisé")

    def charge_llm(self, input_tokens: int, output_tokens: int, cost_usd: float) -> None:
        self.llm_calls += 1
        self.input_tokens += input_tokens
        self.output_tokens += output_tokens
        self.cost_usd += cost_usd

    def before_tool(self) -> None:
        self.check()
        if self.tool_calls >= self.max_tool_calls:
            raise BudgetExceeded(f"{self.max_tool_calls} appels d'outils maximum")
        self.tool_calls += 1

    def as_dict(self) -> dict[str, Any]:
        return {"llm_calls": self.llm_calls, "input_tokens": self.input_tokens, "output_tokens": self.output_tokens, "tool_calls": self.tool_calls, "cost_usd": round(self.cost_usd, 6)}


# ---------------------------------------------------------------- calls
def with_timeout(fn: Callable[[], T], timeout_s: float) -> T:
    fut = _POOL.submit(contextvars.copy_context().run, fn)
    try:
        return fut.result(timeout=timeout_s)
    except cf.TimeoutError as e:
        fut.cancel()
        raise ToolFailed(f"délai de {timeout_s:.0f} s dépassé") from e


def call(fn: Callable[[], T], *, read_only: bool, timeout_s: float = 10.0, retries: int = 2, backoff_s: float = 0.2, sleep: Callable[[float], None] = time.sleep) -> T:
    """Runs ``fn`` with a timeout. Only read-only calls are retried (exponential backoff): an
    action is never replayed behind the caller's back."""
    attempts = 1 + (retries if read_only else 0)
    last: Exception | None = None
    for i in range(attempts):
        try:
            return with_timeout(fn, timeout_s)
        except (ValidationError, ValueError, PermissionError):
            raise  # a bad input does not get better on retry
        except Exception as e:  # noqa: BLE001
            last = e
            if i + 1 < attempts:
                sleep(backoff_s * (2**i))
    raise ToolFailed(str(last)) from last


class CircuitBreaker:
    """Opens after ``threshold`` consecutive failures; lets one call through after ``cooldown_s``."""

    def __init__(self, name: str, threshold: int = 5, cooldown_s: float = 60.0, clock: Callable[[], float] = time.monotonic):
        self.name, self.threshold, self.cooldown_s, self.clock = name, threshold, cooldown_s, clock
        self.failures = 0
        self.opened_at: float | None = None
        self._lock = threading.Lock()

    def before(self) -> None:
        with self._lock:
            if self.opened_at is not None and self.clock() - self.opened_at < self.cooldown_s:
                raise CircuitOpen(f"{self.name} indisponible (disjoncteur ouvert)")

    def success(self) -> None:
        with self._lock:
            self.failures, self.opened_at = 0, None

    def failure(self) -> None:
        with self._lock:
            self.failures += 1
            if self.failures >= self.threshold:
                self.opened_at = self.clock()


class ProgressGuard:
    """Stops a loop that repeats the exact same tool call (same name, same arguments)."""

    def __init__(self, max_repeats: int = 1):
        self.seen: dict[str, int] = {}
        self.max_repeats = max_repeats

    @staticmethod
    def fingerprint(name: str, args: Any) -> str:
        return hashlib.sha256(f"{name}:{json.dumps(args, sort_keys=True, default=str)}".encode()).hexdigest()[:16]

    def check(self, name: str, args: Any) -> None:
        fp = self.fingerprint(name, args)
        n = self.seen.get(fp, 0)
        if n >= self.max_repeats:
            raise NoProgress(f"appel répété à l'identique : {name}")
        self.seen[fp] = n + 1


# ---------------------------------------------------------------- manifest
def _git_commit() -> str:
    env = os.environ.get("HF_GIT_COMMIT", "").strip()
    if env:
        return env[:40]
    try:
        out = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, timeout=3)
        return out.stdout.strip()[:40] or "unknown"
    except Exception:  # noqa: BLE001
        return "unknown"


class VersionManifest(BaseModel):
    model_ids: dict[str, str]
    prompt_sha: dict[str, str]
    tools_commit: str
    engines_commit: str
    config: dict[str, Any]
    fingerprint: str = ""

    def with_fingerprint(self) -> "VersionManifest":
        body = self.model_dump(exclude={"fingerprint"})
        fp = "v-" + hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()[:16]
        return self.model_copy(update={"fingerprint": fp})


def build_manifest(model_ids: dict[str, str], prompts: dict[str, str], config: dict[str, Any]) -> VersionManifest:
    commit = _git_commit()
    sha = {k: hashlib.sha256(v.encode()).hexdigest()[:16] for k, v in sorted(prompts.items())}
    return VersionManifest(model_ids=dict(sorted(model_ids.items())), prompt_sha=sha, tools_commit=commit, engines_commit=commit, config=config).with_fingerprint()


def store_manifest(db: Database, m: VersionManifest) -> None:
    from sqlalchemy import insert, select

    with db.system() as conn:
        if conn.execute(select(version_manifests.c.fingerprint).where(version_manifests.c.fingerprint == m.fingerprint)).first() is None:
            conn.execute(insert(version_manifests).values(fingerprint=m.fingerprint, body=m.model_dump(), created_at=now_ms()))


# ---------------------------------------------------------------- tracing
_current: contextvars.ContextVar["Tracer | None"] = contextvars.ContextVar("tracer", default=None)
_parent: contextvars.ContextVar[str | None] = contextvars.ContextVar("span_parent", default=None)


class Tracer:
    """Writes one span per node, model call, tool call and guardrail decision, under a trace
    id. The spans double as the step stream shown to the member. OpenTelemetry export is added
    by ``otel.py`` when the SDK and an endpoint are configured."""

    def __init__(self, db: Database, tenant_id: str, trace_id: str):
        self.db, self.tenant_id, self.trace_id = db, tenant_id, trace_id
        self.exporters: list[Callable[[dict[str, Any]], None]] = []

    @contextmanager
    def span(self, name: str, kind: str = "node", **attrs: Any) -> Iterator[dict[str, Any]]:
        sid = new_id("sp")
        rec = {"id": sid, "trace_id": self.trace_id, "parent_id": _parent.get(), "name": name[:80], "kind": kind, "status": "ok", "started_ms": now_ms(), "ended_ms": None, "attrs": dict(attrs)}
        tok_t, tok_p = _current.set(self), _parent.set(sid)
        self._write(rec, new=True)
        try:
            yield rec["attrs"]
        except Exception as e:
            rec["status"] = "error"
            rec["attrs"]["error"] = str(e)[:300]
            raise
        finally:
            _parent.reset(tok_p)
            _current.reset(tok_t)
            rec["ended_ms"] = now_ms()
            self._write(rec, new=False)

    def event(self, name: str, kind: str = "step", status: str = "ok", **attrs: Any) -> None:
        ts = now_ms()
        self._write({"id": new_id("sp"), "trace_id": self.trace_id, "parent_id": _parent.get(), "name": name[:80], "kind": kind, "status": status, "started_ms": ts, "ended_ms": ts, "attrs": attrs}, new=True)

    def _write(self, rec: dict[str, Any], new: bool) -> None:
        try:
            with self.db.tenant(self.tenant_id) as s:
                attrs = json.loads(json.dumps(rec["attrs"], default=str))
                if new:
                    s.insert(spans, {**rec, "attrs": attrs})
                else:
                    s.update(spans, {"id": rec["id"]}, {"status": rec["status"], "ended_ms": rec["ended_ms"], "attrs": attrs})
        except Exception as e:  # noqa: BLE001 - tracing never breaks a run
            log.warning("span not written: %s", e)
        if not new:
            for exp in self.exporters:
                try:
                    exp(rec)
                except Exception:  # noqa: BLE001
                    pass


def current_tracer() -> Tracer | None:
    return _current.get()


# ---------------------------------------------------------------- runs and audit
def start_run(db: Database, tenant_id: str, user_id: int | None, graph: str, payload: dict[str, Any], manifest: str, trace_id: str | None = None) -> str:
    tid = trace_id or new_id("tr")
    ts = now_ms()
    with db.tenant(tenant_id) as s:
        s.insert(agent_runs, {"id": tid, "user_id": user_id, "graph": graph, "status": "running", "input": payload, "manifest": manifest, "created_at": ts, "updated_at": ts})
    return tid


def finish_run(db: Database, tenant_id: str, trace_id: str, status: str, output: dict[str, Any] | None, budget: Budget | None = None, error: str | None = None) -> None:
    vals: dict[str, Any] = {"status": status, "output": json.loads(json.dumps(output, default=str)) if output is not None else None, "error": (error or None) and error[:2000], "updated_at": now_ms()}
    if budget is not None:
        vals.update(cost_usd=round(budget.cost_usd, 6), tokens_in=budget.input_tokens, tokens_out=budget.output_tokens, llm_calls=budget.llm_calls)
    with db.tenant(tenant_id) as s:
        s.update(agent_runs, {"id": trace_id}, vals)


def write_audit(db: Database, tenant_id: str, trace_id: str, body: dict[str, Any]) -> str:
    """Appends an audit record to the tenant's hash chain (same idea as the platform ledger)."""
    from sqlalchemy import desc

    body = json.loads(json.dumps(body, default=str))
    with db.tenant(tenant_id) as s:
        last = s.select(audit_records, order_by=desc(audit_records.c.seq), limit=1)
        seq = (last[0]["seq"] + 1) if last else 1
        prev = last[0]["hash"] if last else "0" * 64
        h = hashlib.sha256((prev + json.dumps(body, sort_keys=True)).encode()).hexdigest()
        existing = s.one(audit_records, {"trace_id": trace_id})
        if existing is not None:
            return existing["hash"]
        s.insert(audit_records, {"trace_id": trace_id, "seq": seq, "body": body, "prev_hash": prev, "hash": h, "created_at": now_ms()})
    return h


def verify_audit_chain(db: Database, tenant_id: str) -> tuple[bool, int]:
    from sqlalchemy import asc

    with db.tenant(tenant_id) as s:
        rows = s.select(audit_records, order_by=asc(audit_records.c.seq))
    prev = "0" * 64
    for i, r in enumerate(rows):
        h = hashlib.sha256((prev + json.dumps(r["body"], sort_keys=True)).encode()).hexdigest()
        if r["prev_hash"] != prev or r["hash"] != h:
            return False, i
        prev = h
    return True, len(rows)

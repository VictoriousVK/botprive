"""LangGraph plumbing shared by G1 to G4: checkpointer (PostgreSQL, SQLite or memory), a node
wrapper that traces every node as a span and enforces the run's budget, and run/resume helpers
that keep ``agent_runs`` in step with the graph (running → waiting on a human → done).

Graph states hold plain data only (dicts, strings, numbers), so a checkpoint can be resumed by
another process (the worker) after a restart.
"""

from __future__ import annotations

import logging
import sqlite3
import threading
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from hedgefund.saas.db import agent_runs, now_ms
from hedgefund.saas.harness import Budget, Tracer, finish_run, start_run

log = logging.getLogger("hedgefund.saas.graphs")


@dataclass
class RunContext:
    saas: Any
    tenant_id: str
    user_id: int
    trace_id: str
    budget: Budget
    tracer: Tracer
    entitlements: frozenset[str] = frozenset()
    plan: str = "gratuit"
    guardrails: list[dict[str, Any]] = field(default_factory=list)


_RUNS: dict[str, RunContext] = {}
_LOCK = threading.Lock()


def context(trace_id: str) -> RunContext:
    with _LOCK:
        ctx = _RUNS.get(trace_id)
    if ctx is None:
        raise RuntimeError(f"contexte d'exécution absent pour {trace_id}")
    return ctx


def node(name: str) -> Callable[[Callable[[Any, RunContext], dict[str, Any]]], Callable[[Any], dict[str, Any]]]:
    """Decorator: ``fn(state, ctx) -> update``; each call is a span, and the run's deadline is
    checked before the node starts."""

    def deco(fn: Callable[[Any, RunContext], dict[str, Any]]) -> Callable[[Any], dict[str, Any]]:
        def wrapped(state: Any) -> dict[str, Any]:
            ctx = context(state.trace_id)
            ctx.budget.check()
            with ctx.tracer.span(name, kind="node"):
                return fn(state, ctx) or {}

        wrapped.__name__ = f"node_{name}"
        return wrapped

    return deco


def make_checkpointer(saas: Any) -> Any:
    """PostgreSQL (production), SQLite next to the SaaS database, or memory (tests)."""
    db = saas.db
    if db.is_postgres:
        import psycopg
        from langgraph.checkpoint.postgres import PostgresSaver
        from psycopg.rows import dict_row

        url = db.engine.url.set(drivername="postgresql").render_as_string(hide_password=False)
        conn = psycopg.connect(url, autocommit=True, row_factory=dict_row)
        saver = PostgresSaver(conn)
        saver.setup()
        return saver
    path = db.engine.url.database
    if not path or path == ":memory:":
        from langgraph.checkpoint.memory import InMemorySaver

        return InMemorySaver()
    from langgraph.checkpoint.sqlite import SqliteSaver

    cp = Path(path).with_name("checkpoints.db")
    saver = SqliteSaver(sqlite3.connect(str(cp), check_same_thread=False))
    saver.setup()
    return saver


def _open(saas: Any, tenant_id: str, user_id: int, trace_id: str, budget: Budget, entitlements: frozenset[str], plan: str) -> RunContext:
    ctx = RunContext(saas, tenant_id, user_id, trace_id, budget, Tracer(saas.db, tenant_id, trace_id), entitlements, plan)
    with _LOCK:
        _RUNS[trace_id] = ctx
    return ctx


def _close(trace_id: str) -> None:
    with _LOCK:
        _RUNS.pop(trace_id, None)


def _status(result: dict[str, Any]) -> tuple[str, dict[str, Any] | None]:
    if result.get("__interrupt__"):
        intr = result["__interrupt__"][0]
        return "waiting", {"waiting_for": getattr(intr, "value", None), **{k: v for k, v in result.items() if k in ("output",)}}
    return "done", result.get("output")


def run_graph(saas: Any, graph: Any, graph_name: str, tenant_id: str, user_id: int, inputs: dict[str, Any], budget: Budget, trace_id: str | None = None,
              entitlements: frozenset[str] = frozenset(), plan: str = "gratuit") -> tuple[str, str, dict[str, Any] | None]:
    """Starts a run; returns (trace_id, status, output). A failing node marks the run failed
    and re-raises nothing: the member sees the error in the run."""
    tid = start_run(saas.db, tenant_id, user_id, graph_name, {k: v for k, v in inputs.items() if k != "trace_id"}, saas.manifest.fingerprint, trace_id)
    _open(saas, tenant_id, user_id, tid, budget, entitlements, plan)
    try:
        result = graph.invoke({**inputs, "trace_id": tid}, {"configurable": {"thread_id": tid}})
        status, output = _status(result)
        finish_run(saas.db, tenant_id, tid, status, output if status == "done" else {"waiting": True, **(output or {})}, budget)
        return tid, status, output
    except Exception as e:  # noqa: BLE001
        log.exception("run %s (%s) failed", tid, graph_name)
        finish_run(saas.db, tenant_id, tid, "failed", None, budget, error=f"{type(e).__name__}: {e}")
        return tid, "failed", None
    finally:
        _close(tid)


def resume_graph(saas: Any, graph: Any, tenant_id: str, user_id: int, trace_id: str, value: Any, budget: Budget | None = None, entitlements: frozenset[str] = frozenset(), plan: str = "gratuit") -> tuple[str, dict[str, Any] | None]:
    from langgraph.types import Command

    with saas.db.tenant(tenant_id) as s:
        run = s.one(agent_runs, {"id": trace_id})
        if run is None:
            raise LookupError("exécution introuvable")
        if run["status"] != "waiting":
            raise ValueError("cette exécution n'attend pas de décision")
        s.update(agent_runs, {"id": trace_id}, {"status": "running", "updated_at": now_ms()})
    budget = budget or Budget()
    _open(saas, tenant_id, user_id, trace_id, budget, entitlements, plan)
    try:
        result = graph.invoke(Command(resume=value), {"configurable": {"thread_id": trace_id}})
        status, output = _status(result)
        finish_run(saas.db, tenant_id, trace_id, status, output if status == "done" else {"waiting": True, **(output or {})})
        return status, output
    except Exception as e:  # noqa: BLE001
        log.exception("resume %s failed", trace_id)
        finish_run(saas.db, tenant_id, trace_id, "failed", None, error=f"{type(e).__name__}: {e}")
        return "failed", None
    finally:
        _close(trace_id)

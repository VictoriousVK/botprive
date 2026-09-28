"""Durable job queue in the SaaS database, and the worker that runs it.

Jobs live in the ``jobs`` table (PostgreSQL in production): they survive a restart, carry an
idempotency key (the same TradingView alert or n8n trigger is enqueued once), and are picked
with ``FOR UPDATE SKIP LOCKED`` so several worker processes can share the load. Priorities:
0 interactive, 1 scheduled, 2 batch. On a single machine the worker runs as threads inside the
web process; in Docker it is its own container (``python -m hedgefund.saas worker``).
"""

from __future__ import annotations

import logging
import os
import socket
import threading
import time
from collections.abc import Callable
from typing import Any

from sqlalchemy import and_, insert, or_, select, update

from hedgefund.saas.db import Database, jobs, new_id, now_ms

log = logging.getLogger("hedgefund.saas.jobs")
STALE_MS = 15 * 60 * 1000


class JobQueue:
    def __init__(self, db: Database):
        self.db = db
        self.wakeup = threading.Event()

    def enqueue(self, kind: str, payload: dict[str, Any], tenant_id: str | None = None, priority: int = 1, idem_key: str | None = None, run_after: int | None = None, max_attempts: int = 3) -> str:
        with self.db.system() as conn:
            if idem_key:
                row = conn.execute(select(jobs.c.id).where(jobs.c.idem_key == idem_key)).first()
                if row is not None:
                    return row.id
            jid = new_id("job")
            ts = now_ms()
            conn.execute(insert(jobs).values(id=jid, tenant_id=tenant_id, kind=kind, payload=payload, status="queued", priority=priority, idem_key=idem_key, attempts=0, max_attempts=max_attempts, run_after=run_after or ts, created_at=ts, updated_at=ts))
        self.wakeup.set()
        return jid

    def get(self, job_id: str) -> dict[str, Any] | None:
        with self.db.system() as conn:
            row = conn.execute(select(jobs).where(jobs.c.id == job_id)).first()
        return dict(row._mapping) if row else None

    def claim(self, worker: str, kinds: set[str] | None = None) -> dict[str, Any] | None:
        ts = now_ms()
        with self.db.system() as conn:
            conn.execute(update(jobs).where(and_(jobs.c.status == "running", jobs.c.locked_at < ts - STALE_MS)).values(status="queued", locked_by=None, updated_at=ts))
            q = select(jobs).where(and_(jobs.c.status == "queued", jobs.c.run_after <= ts))
            if kinds:
                q = q.where(jobs.c.kind.in_(sorted(kinds)))
            q = q.order_by(jobs.c.priority, jobs.c.run_after).limit(1)
            if self.db.is_postgres:
                q = q.with_for_update(skip_locked=True)
            row = conn.execute(q).first()
            if row is None:
                return None
            conn.execute(update(jobs).where(jobs.c.id == row.id).values(status="running", locked_by=worker, locked_at=ts, attempts=row.attempts + 1, updated_at=ts))
            job = dict(row._mapping)
            job["attempts"] += 1
            return job

    def complete(self, job_id: str, result: dict[str, Any] | None) -> None:
        with self.db.system() as conn:
            conn.execute(update(jobs).where(jobs.c.id == job_id).values(status="done", result=result, error=None, locked_by=None, updated_at=now_ms()))

    def fail(self, job: dict[str, Any], error: str, retry: bool = True) -> bool:
        """Returns True when the job will be retried, False when it is dead."""
        ts = now_ms()
        again = retry and job["attempts"] < job["max_attempts"]
        vals: dict[str, Any] = {"error": error[:2000], "locked_by": None, "updated_at": ts}
        if again:
            vals.update(status="queued", run_after=ts + 5000 * 2 ** (job["attempts"] - 1))
        else:
            vals.update(status="failed")
        with self.db.system() as conn:
            conn.execute(update(jobs).where(jobs.c.id == job["id"]).values(**vals))
        return again

    def counts(self) -> dict[str, int]:
        from sqlalchemy import func

        with self.db.system() as conn:
            return {r.status: r.n for r in conn.execute(select(jobs.c.status, func.count().label("n")).group_by(jobs.c.status))}

    def purge(self, older_than_ms: int) -> int:
        from sqlalchemy import delete

        with self.db.system() as conn:
            return conn.execute(delete(jobs).where(and_(or_(jobs.c.status == "done", jobs.c.status == "failed"), jobs.c.updated_at < older_than_ms))).rowcount


class PermanentError(RuntimeError):
    """A job error that retrying cannot fix (bad input, missing data)."""


class Worker:
    def __init__(self, queue: JobQueue, handlers: dict[str, Callable[[dict[str, Any]], dict[str, Any] | None]], name: str | None = None,
                 on_dead: Callable[[dict[str, Any], str], None] | None = None):
        self.queue, self.handlers, self.on_dead = queue, handlers, on_dead
        self.name = name or f"{socket.gethostname()}:{os.getpid()}"
        self.stop = threading.Event()
        self.threads: list[threading.Thread] = []

    def run_once(self) -> bool:
        job = self.queue.claim(self.name, set(self.handlers))
        if job is None:
            return False
        fn = self.handlers[job["kind"]]
        try:
            self.queue.complete(job["id"], fn(job) or {})
        except PermanentError as e:
            self._dead(job, str(e), self.queue.fail(job, str(e), retry=False))
        except Exception as e:  # noqa: BLE001
            log.exception("job %s (%s) failed", job["id"], job["kind"])
            self._dead(job, f"{type(e).__name__}: {e}", self.queue.fail(job, f"{type(e).__name__}: {e}"))
        return True

    def _dead(self, job: dict[str, Any], error: str, retried: bool) -> None:
        if retried or self.on_dead is None:
            return
        try:
            self.on_dead(job, error)
        except Exception:  # noqa: BLE001 - reporting a dead job never kills the worker
            log.exception("on_dead for job %s", job["id"])

    def drain(self, max_jobs: int = 100) -> int:
        n = 0
        while n < max_jobs and self.run_once():
            n += 1
        return n

    def loop(self, poll_s: float = 1.0) -> None:
        while not self.stop.is_set():
            try:
                busy = self.run_once()
            except Exception:  # noqa: BLE001 - database hiccup: wait and retry
                log.exception("worker loop")
                busy = False
            if not busy:
                self.queue.wakeup.wait(poll_s)
                self.queue.wakeup.clear()

    def start(self, threads: int = 2) -> None:
        for i in range(threads):
            t = threading.Thread(target=self.loop, name=f"saas-worker-{i}", daemon=True)
            t.start()
            self.threads.append(t)

    def shutdown(self, timeout: float = 5.0) -> None:
        self.stop.set()
        self.queue.wakeup.set()
        deadline = time.monotonic() + timeout
        for t in self.threads:
            t.join(max(0.0, deadline - time.monotonic()))

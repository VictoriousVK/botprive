"""Append-only, hash-chained audit ledger (SQLite).

Every decision, order, fill, risk event, stage transition, approval and research memo is
written here. Rows cannot be updated or deleted (enforced by triggers) and each row's hash
covers the previous row's hash, so tampering is detectable with ``verify_chain``.
"""

from __future__ import annotations

import dataclasses
import enum
import hashlib
import json
import sqlite3
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

GENESIS = "0" * 64


class Kind:
    CONFIG = "config"
    DATA_QUALITY = "data_quality"
    JEV_DECISION = "jev_decision"
    JEV_SHADOW = "jev_shadow"
    JEV_ERROR = "jev_error"
    POLICY = "policy"
    ESCALATION = "escalation"
    RISK_VERDICT = "risk_verdict"
    RISK_EVENT = "risk_event"
    KILL_SWITCH = "kill_switch"
    ORDER = "order"
    ORDER_UPDATE = "order_update"
    FILL = "fill"
    FUNDING = "funding"
    NAV = "nav"
    RECONCILIATION = "reconciliation"
    STAGE_TRANSITION = "stage_transition"
    APPROVAL = "approval"
    APPROVAL_REQUEST = "approval_request"
    RESEARCH_TASK = "research_task"
    RESEARCH_MEMO = "research_memo"
    RESEARCH_REVIEW = "research_review"
    CALIBRATION_PREDICTION = "calibration_prediction"
    CALIBRATION_OUTCOME = "calibration_outcome"
    ALERT = "alert"
    BACKTEST = "backtest"
    STRATEGY_HALT = "strategy_halt"
    HEARTBEAT = "heartbeat"


def _json_default(obj: Any) -> Any:
    if isinstance(obj, enum.Enum):
        return obj.value
    if dataclasses.is_dataclass(obj) and not isinstance(obj, type):
        return dataclasses.asdict(obj)
    if isinstance(obj, (set, frozenset, tuple)):
        return list(obj)
    if isinstance(obj, Path):
        return str(obj)
    raise TypeError(f"not JSON serializable: {type(obj).__name__}")


def to_json(payload: Any) -> str:
    return json.dumps(payload, sort_keys=True, default=_json_default, separators=(",", ":"))


@dataclass(frozen=True)
class LedgerEvent:
    seq: int
    ts: int
    kind: str
    ref: str | None
    payload: dict
    hash: str


class Ledger:
    def __init__(self, path: str | Path = ":memory:"):
        self.path = str(path)
        if self.path != ":memory:":
            Path(self.path).parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(self.path, check_same_thread=False, isolation_level=None)
        self._lock = threading.Lock()
        if self.path != ":memory:":
            self._conn.execute("PRAGMA journal_mode=WAL")
            self._conn.execute("PRAGMA synchronous=FULL")
        self._conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS events (
                seq INTEGER PRIMARY KEY AUTOINCREMENT,
                ts INTEGER NOT NULL,
                kind TEXT NOT NULL,
                ref TEXT,
                payload TEXT NOT NULL,
                prev_hash TEXT NOT NULL,
                hash TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_events_kind_ts ON events(kind, ts);
            CREATE INDEX IF NOT EXISTS idx_events_ref ON events(ref);
            CREATE TRIGGER IF NOT EXISTS events_no_update BEFORE UPDATE ON events
                BEGIN SELECT RAISE(ABORT, 'ledger is append-only'); END;
            CREATE TRIGGER IF NOT EXISTS events_no_delete BEFORE DELETE ON events
                BEGIN SELECT RAISE(ABORT, 'ledger is append-only'); END;
            """
        )
        row = self._conn.execute("SELECT hash FROM events ORDER BY seq DESC LIMIT 1").fetchone()
        self._last_hash = row[0] if row else GENESIS

    @staticmethod
    def _hash(prev: str, ts: int, kind: str, ref: str | None, body: str) -> str:
        return hashlib.sha256(f"{prev}|{ts}|{kind}|{ref or ''}|{body}".encode()).hexdigest()

    def append(self, kind: str, payload: Any, ts: int, ref: str | None = None) -> str:
        body = to_json(payload)
        with self._lock:
            h = self._hash(self._last_hash, ts, kind, ref, body)
            self._conn.execute(
                "INSERT INTO events (ts, kind, ref, payload, prev_hash, hash) VALUES (?, ?, ?, ?, ?, ?)",
                (ts, kind, ref, body, self._last_hash, h),
            )
            self._last_hash = h
        return h

    def query(
        self,
        kind: str | Iterable[str] | None = None,
        ref: str | None = None,
        since_ts: int | None = None,
        until_ts: int | None = None,
        limit: int | None = None,
        newest_first: bool = False,
    ) -> list[LedgerEvent]:
        sql = "SELECT seq, ts, kind, ref, payload, hash FROM events WHERE 1=1"
        args: list[Any] = []
        if kind is not None:
            kinds = [kind] if isinstance(kind, str) else list(kind)
            sql += f" AND kind IN ({','.join('?' * len(kinds))})"
            args.extend(kinds)
        if ref is not None:
            sql += " AND ref = ?"
            args.append(ref)
        if since_ts is not None:
            sql += " AND ts >= ?"
            args.append(since_ts)
        if until_ts is not None:
            sql += " AND ts <= ?"
            args.append(until_ts)
        sql += " ORDER BY seq DESC" if newest_first else " ORDER BY seq ASC"
        if limit is not None:
            sql += " LIMIT ?"
            args.append(int(limit))
        with self._lock:
            rows = self._conn.execute(sql, args).fetchall()
        return [LedgerEvent(r[0], r[1], r[2], r[3], json.loads(r[4]), r[5]) for r in rows]

    def count(self, kind: str | None = None) -> int:
        with self._lock:
            if kind is None:
                return self._conn.execute("SELECT COUNT(*) FROM events").fetchone()[0]
            return self._conn.execute("SELECT COUNT(*) FROM events WHERE kind = ?", (kind,)).fetchone()[0]

    def verify_chain(self) -> tuple[bool, int | None]:
        """Returns (ok, first_bad_seq)."""
        prev = GENESIS
        with self._lock:
            rows = self._conn.execute(
                "SELECT seq, ts, kind, ref, payload, prev_hash, hash FROM events ORDER BY seq ASC"
            ).fetchall()
        for seq, ts, kind, ref, body, prev_hash, h in rows:
            if prev_hash != prev or self._hash(prev, ts, kind, ref, body) != h:
                return False, seq
            prev = h
        return True, None

    def close(self) -> None:
        with self._lock:
            self._conn.close()


class NullLedger:
    """Drop-in ledger that stores nothing. For fast stress/perturbation runs only."""

    path = None

    def append(self, kind: str, payload: Any, ts: int, ref: str | None = None) -> str:
        return GENESIS

    def query(self, *args: Any, **kwargs: Any) -> list[LedgerEvent]:
        return []

    def count(self, kind: str | None = None) -> int:
        return 0

    def verify_chain(self) -> tuple[bool, int | None]:
        return True, None

    def close(self) -> None:
        pass

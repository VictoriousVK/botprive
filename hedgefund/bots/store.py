"""Mutable platform state (SQLite): bots, settings, users, sessions, login attempts.

The audit trail stays in the append-only ledger; this store only holds current state.
"""

from __future__ import annotations

import json
import sqlite3
import threading
from pathlib import Path
from typing import Any

SCHEMA = """
CREATE TABLE IF NOT EXISTS bots (id TEXT PRIMARY KEY, body TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    totp_secret TEXT,
    totp_enabled INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
    token_hash TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL,
    csrf TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    last_seen INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    ip TEXT,
    user_agent TEXT
);
CREATE TABLE IF NOT EXISTS login_attempts (key TEXT NOT NULL, ts INTEGER NOT NULL, ok INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS idx_attempts ON login_attempts(key, ts);
"""


class PlatformStore:
    def __init__(self, path: str | Path = ":memory:"):
        self.path = str(path)
        if self.path != ":memory:":
            Path(self.path).parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(self.path, check_same_thread=False, isolation_level=None)
        self._conn.row_factory = sqlite3.Row
        self._lock = threading.RLock()
        if self.path != ":memory:":
            self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.executescript(SCHEMA)

    def execute(self, sql: str, args: tuple = ()) -> list[sqlite3.Row]:
        with self._lock:
            return self._conn.execute(sql, args).fetchall()

    # ---- settings ----
    def get_setting(self, key: str, default: Any = None) -> Any:
        rows = self.execute("SELECT value FROM settings WHERE key = ?", (key,))
        return json.loads(rows[0]["value"]) if rows else default

    def set_setting(self, key: str, value: Any) -> None:
        self.execute("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", (key, json.dumps(value)))

    # ---- bots ----
    def list_bots(self) -> list[dict]:
        return [json.loads(r["body"]) for r in self.execute("SELECT body FROM bots ORDER BY id")]

    def get_bot(self, bot_id: str) -> dict | None:
        rows = self.execute("SELECT body FROM bots WHERE id = ?", (bot_id,))
        return json.loads(rows[0]["body"]) if rows else None

    def save_bot(self, bot: dict) -> None:
        self.execute("INSERT INTO bots (id, body) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET body = excluded.body", (bot["id"], json.dumps(bot)))

    def delete_bot(self, bot_id: str) -> None:
        self.execute("DELETE FROM bots WHERE id = ?", (bot_id,))

    def close(self) -> None:
        with self._lock:
            self._conn.close()

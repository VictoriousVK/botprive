"""Alerting: every alert goes to the ledger; high-severity alerts also go to an optional
Slack-compatible incoming webhook (JSON body {"text": ...}). Identical alerts are
de-duplicated for an hour so a stuck condition pages once, not every bar."""

from __future__ import annotations

import os
from typing import Any

import requests

from hedgefund.core.clock import Clock
from hedgefund.core.ledger import Kind
from hedgefund.core.timeutil import HOUR_MS, utc_iso


class AlertSink:
    def __init__(self, ledger: Any, clock: Clock, webhook_url: str | None = None, dedupe_ms: int = HOUR_MS):
        self.ledger = ledger
        self.clock = clock
        self.webhook_url = webhook_url
        self.dedupe_ms = dedupe_ms
        self._last: dict[str, int] = {}
        self.sent: list[dict] = []

    @classmethod
    def from_env(cls, ledger: Any, clock: Clock, env_var: str = "ALERT_WEBHOOK_URL") -> "AlertSink":
        return cls(ledger, clock, os.environ.get(env_var) or None)

    def alert(self, severity: str, message: str, **context: Any) -> bool:
        now = self.clock.now_ms()
        key = f"{severity}:{message}"
        if now - self._last.get(key, -10**15) < self.dedupe_ms:
            return False
        self._last[key] = now
        payload = {"severity": severity, "message": message, **context}
        self.ledger.append(Kind.ALERT, payload, ts=now)
        self.sent.append(payload)
        if self.webhook_url and severity in ("high", "critical"):
            try:
                requests.post(self.webhook_url, json={"text": f"[{severity.upper()}] {utc_iso(now)} {message}"}, timeout=5)
            except requests.RequestException:
                self.ledger.append(Kind.ALERT, {"severity": "low", "message": "alert webhook delivery failed"}, ts=now)
        return True

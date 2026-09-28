"""Latching kill switch.

Engaged automatically (max drawdown, reconciliation mismatch, NAV <= 0) or manually, either
through the CLI or by creating the flag file (``touch var/KILL_SWITCH``) - which works even
if every Python process is wedged. While engaged, only exposure-reducing orders pass risk,
and the runner flattens all books. Only a named human can reset it.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from hedgefund.core.clock import Clock
from hedgefund.core.ledger import Kind
from hedgefund.core.timeutil import utc_iso


class KillSwitch:
    def __init__(self, path: Path | None, ledger: Any, clock: Clock):
        self.path = Path(path) if path else None
        self.ledger = ledger
        self.clock = clock
        self._engaged = False
        self._reason = ""

    @property
    def engaged(self) -> bool:
        if self._engaged:
            return True
        if self.path is not None and self.path.exists():
            self._engaged = True
            try:
                self._reason = json.loads(self.path.read_text() or "{}").get("reason", "flag file present")
            except json.JSONDecodeError:
                self._reason = "flag file present"
            return True
        return False

    @property
    def reason(self) -> str:
        return self._reason if self.engaged else ""

    def engage(self, reason: str, source: str) -> None:
        if self._engaged:
            return
        self._engaged = True
        self._reason = reason
        ts = self.clock.now_ms()
        if self.path is not None:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.path.write_text(json.dumps({"reason": reason, "source": source, "at": utc_iso(ts)}))
        self.ledger.append(Kind.KILL_SWITCH, {"state": "engaged", "reason": reason, "source": source}, ts=ts)

    def reset(self, operator: str, reason: str) -> None:
        if not operator.strip() or not reason.strip():
            raise PermissionError("kill switch reset requires a named operator and a reason")
        ts = self.clock.now_ms()
        if self.path is not None and self.path.exists():
            self.path.unlink()
        self._engaged = False
        self._reason = ""
        self.ledger.append(Kind.APPROVAL, {"action": "kill_switch_reset", "operator": operator, "reason": reason}, ts=ts)
        self.ledger.append(Kind.KILL_SWITCH, {"state": "reset", "operator": operator, "reason": reason}, ts=ts)

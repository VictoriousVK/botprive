from __future__ import annotations

import hashlib
import json
import uuid
from typing import Any


def stable_id(*parts: Any, length: int = 24) -> str:
    """Deterministic id from parts. Used for decision ids and client order ids so that a
    retried or replayed step produces the same id (idempotency)."""
    raw = "|".join(str(p) for p in parts)
    return hashlib.sha256(raw.encode()).hexdigest()[:length]


def new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:16]}"


def content_hash(obj: Any) -> str:
    body = json.dumps(obj, sort_keys=True, default=str, separators=(",", ":"))
    return hashlib.sha256(body.encode()).hexdigest()[:16]

"""Wave Checkout API client (Wave Business, https://docs.wave.com/checkout).

Flow: create a checkout session (amount in XOF, https success/error URLs, our payment id as
``client_reference``), send the member to ``wave_launch_url``, then confirm the payment by reading
the session back from Wave. A payment is only ever credited from a session fetched from the
API with ``payment_status == "succeeded"`` and the expected amount, currency and reference:
neither the redirect back to the site nor the webhook body is trusted on its own.

Webhooks: Wave signs deliveries with a ``Wave-Signature: t=<timestamp>,v1=<hex>`` header, an
HMAC-SHA256 of the timestamp followed by the raw body, keyed with the webhook secret. Check the
exact scheme of your webhook in the Wave Business portal before going live; since the webhook
only triggers a re-read of the session from the API, a mistake here cannot credit a payment.
"""

from __future__ import annotations

import hashlib
import hmac
import time
from dataclasses import dataclass
from typing import Any

import requests

SIGNATURE_TOLERANCE_S = 300


class WaveError(RuntimeError):
    pass


@dataclass
class WaveClient:
    api_key: str
    base_url: str = "https://api.wave.com"
    timeout_s: float = 15.0
    session: Any = None  # requests.Session-like; injectable for tests

    def _http(self):
        return self.session or requests

    def _call(self, method: str, path: str, **kw: Any) -> dict[str, Any]:
        headers = {"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json", **kw.pop("headers", {})}
        try:
            r = self._http().request(method, f"{self.base_url}{path}", headers=headers, timeout=self.timeout_s, **kw)
        except requests.RequestException as e:
            raise WaveError(f"Wave injoignable : {e.__class__.__name__}") from e
        if r.status_code >= 400:
            try:
                detail = r.json().get("message") or r.json().get("code")
            except ValueError:
                detail = r.text[:200]
            raise WaveError(f"Wave a refusé la requête ({r.status_code}) : {detail}")
        return r.json() if r.content else {}

    def create_checkout(self, amount_xof: int, client_reference: str, success_url: str, error_url: str, idempotency_key: str) -> dict[str, Any]:
        body = {"amount": str(int(amount_xof)), "currency": "XOF", "client_reference": client_reference, "success_url": success_url, "error_url": error_url}
        return self._call("POST", "/v1/checkout/sessions", json=body, headers={"Idempotency-Key": idempotency_key})

    def get_checkout(self, session_id: str) -> dict[str, Any]:
        if not session_id or "/" in session_id or "?" in session_id:
            raise WaveError("identifiant de session Wave invalide")
        return self._call("GET", f"/v1/checkout/sessions/{session_id}")


def verify_signature(secret: str, header: str | None, raw_body: bytes, now: float | None = None) -> bool:
    """Checks a ``Wave-Signature: t=...,v1=...[,v1=...]`` header against the raw request body."""
    if not secret or not header:
        return False
    parts = [p.strip() for p in header.split(",")]
    ts = next((p[2:] for p in parts if p.startswith("t=")), "")
    sigs = [p[3:] for p in parts if p.startswith("v1=")]
    if not ts.isdigit() or not sigs:
        return False
    if abs((time.time() if now is None else now) - int(ts)) > SIGNATURE_TOLERANCE_S:
        return False
    expected = hmac.new(secret.encode(), ts.encode() + raw_body, hashlib.sha256).hexdigest()
    return any(hmac.compare_digest(expected, s) for s in sigs)


def sign(secret: str, raw_body: bytes, ts: int | None = None) -> str:
    """Builds a signature header the way Wave does (used by the tests)."""
    t = str(int(time.time() if ts is None else ts))
    return f"t={t},v1={hmac.new(secret.encode(), t.encode() + raw_body, hashlib.sha256).hexdigest()}"

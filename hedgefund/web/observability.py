"""Error and performance monitoring with Sentry (optional).

Nothing happens unless ``SENTRY_DSN`` is set and the ``sentry-sdk`` package is installed
(``pip install -e ".[monitoring]"``). Then every unhandled error of the platform (API, bots,
e-mails, Wave, IA coach) and every ``log.error``/``log.exception`` appears in the Sentry
dashboard, with the route, the stack trace and the release.

Privacy: no request body, cookie, CSRF token, password or Wave signature is ever sent. Only an
anonymous member id is attached to an error.

Environment variables:
  SENTRY_DSN                  server project DSN (Settings -> Projects -> Client Keys)
  SENTRY_BROWSER_DSN          optional, the site's (browser) project DSN; errors of the pages
                              members see. Can be the same DSN as the server.
  SENTRY_ENVIRONMENT          production (default) | staging | local
  SENTRY_TRACES_SAMPLE_RATE   share of requests timed for performance, 0 to 1 (default 0.1)
"""

from __future__ import annotations

import logging
import os
from typing import Any
from urllib.parse import urlsplit

from hedgefund import __version__

log = logging.getLogger("hedgefund.web")

SENSITIVE_HEADERS = {"cookie", "authorization", "x-csrf-token", "wave-signature", "x-api-key", "proxy-authorization"}
_enabled = False


def release() -> str:
    return os.environ.get("SENTRY_RELEASE", "").strip() or f"liberte-financiere@{__version__}"


def environment() -> str:
    return os.environ.get("SENTRY_ENVIRONMENT", "production").strip() or "production"


def scrub(event: dict[str, Any], _hint: Any = None) -> dict[str, Any]:
    """Removes secrets before an event leaves the server."""
    req = event.get("request")
    if isinstance(req, dict):
        req.pop("cookies", None)
        req.pop("data", None)
        headers = req.get("headers")
        if isinstance(headers, dict):
            for k in list(headers):
                if k.lower() in SENSITIVE_HEADERS:
                    headers[k] = "[filtré]"
        qs = req.get("query_string")
        if isinstance(qs, str) and "jeton=" in qs:  # e-mail links carry single-use tokens
            req["query_string"] = "[filtré]"
    user = event.get("user")
    if isinstance(user, dict):
        event["user"] = {"id": user["id"]} if "id" in user else {}
    return event


def init_sentry() -> bool:
    """Starts Sentry for this process. Returns True when it is running."""
    global _enabled
    dsn = os.environ.get("SENTRY_DSN", "").strip()
    if not dsn:
        return False
    try:
        import sentry_sdk
    except ImportError:
        log.warning("SENTRY_DSN est défini mais le paquet sentry-sdk n'est pas installé : pip install -e \".[monitoring]\"")
        return False
    try:
        rate = min(1.0, max(0.0, float(os.environ.get("SENTRY_TRACES_SAMPLE_RATE", "0.1"))))
    except ValueError:
        rate = 0.1
    sentry_sdk.init(
        dsn=dsn,
        environment=environment(),
        release=release(),
        traces_sample_rate=rate,
        send_default_pii=False,
        max_request_body_size="never",
        before_send=scrub,
        before_send_transaction=scrub,
    )
    _enabled = True
    log.info("Sentry actif (%s, %s)", environment(), release())
    return True


def set_member(member_id: int | None) -> None:
    """Attaches the anonymous member id to errors of the current request."""
    if not _enabled:
        return
    import sentry_sdk

    sentry_sdk.set_user({"id": str(member_id)} if member_id else None)


def browser_config() -> dict[str, str] | None:
    """What the site needs to report its own errors (a DSN is public by design)."""
    dsn = os.environ.get("SENTRY_BROWSER_DSN", "").strip()
    if not dsn.startswith("https://"):
        return None
    return {"dsn": dsn, "environment": environment(), "release": release()}


def sentry_browser_hosts() -> tuple[str, ...]:
    """Origin the pages may send error reports to (added to the CSP connect-src)."""
    cfg = browser_config()
    if cfg is None:
        return ()
    host = urlsplit(cfg["dsn"]).hostname
    return (f"https://{host}",) if host else ()

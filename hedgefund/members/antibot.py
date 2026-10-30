"""Sign-up protection against bots.

Layers, from cheapest to strongest (all on the server, a bot can't skip them by calling the
API directly):

1. Honeypot: a hidden ``website`` field. People never see it; form-filling bots fill it. The
   request is answered exactly like a real sign-up, but nothing is created.
2. Disposable e-mail domains are refused (yopmail, mailinator...), plus any domain listed in
   ``LF_BLOCKED_EMAIL_DOMAINS``.
3. Rate limit per IP (in ``Members.register``).
4. Cloudflare Turnstile (optional, free): set ``LF_TURNSTILE_SITE_KEY`` and
   ``LF_TURNSTILE_SECRET``. The sign-up form then shows the check and the server verifies it.
5. E-mail confirmation: an account can't sign in before its owner clicks the link we send.
"""

from __future__ import annotations

import logging

import requests

log = logging.getLogger("hedgefund.antibot")

TURNSTILE_VERIFY = "https://challenges.cloudflare.com/turnstile/v0/siteverify"
TURNSTILE_ORIGIN = "https://challenges.cloudflare.com"

# Most-used throwaway inbox services. Extend with LF_BLOCKED_EMAIL_DOMAINS (comma-separated).
DISPOSABLE_DOMAINS = frozenset(
    ["yopmail.com", "yopmail.fr", "yopmail.net", "cool.fr.nf", "jetable.fr.nf", "nospam.ze.tc", "nomail.xl.cx", "mega.zik.dj", "speed.1s.fr", "courriel.fr.nf", "moncourrier.fr.nf", "monemail.fr.nf", "monmail.fr.nf", "mailinator.com", "mailinator.net", "mailinator2.com", "guerrillamail.com", "guerrillamail.net", "guerrillamail.org", "guerrillamail.biz", "guerrillamailblock.com", "sharklasers.com", "grr.la", "spam4.me", "10minutemail.com", "10minutemail.net", "10minutemail.co.uk", "20minutemail.com", "temp-mail.org", "temp-mail.io", "tempmail.com", "tempmail.net", "tempmailo.com", "tempr.email", "tempail.com", "throwawaymail.com", "trashmail.com", "trashmail.de", "trashmail.net", "getnada.com", "nada.email", "dispostable.com", "maildrop.cc", "mailnesia.com", "mintemail.com", "mohmal.com", "fakeinbox.com", "fakemail.net", "emailondeck.com", "getairmail.com", "mailcatch.com", "spambox.us", "spamgourmet.com", "mytemp.email", "tmpmail.org", "tmpmail.net", "emailfake.com", "burnermail.io", "inboxkitten.com", "mail.tm", "mail.gw", "discard.email", "luxusmail.org", "minuteinbox.com", "moakt.com", "tempinbox.com", "mailpoof.com", "fexbox.org"]
)


def email_domain(email: str) -> str:
    return email.rpartition("@")[2].strip().lower()


def is_blocked_domain(email: str, extra: frozenset[str] = frozenset()) -> bool:
    d = email_domain(email)
    if not d:
        return True
    parts = d.split(".")
    # also matches sub-domains (x.yopmail.com)
    candidates = {".".join(parts[i:]) for i in range(len(parts) - 1)}
    return bool(candidates & (DISPOSABLE_DOMAINS | extra))


def verify_turnstile(secret: str, token: str | None, ip: str = "", session: requests.Session | None = None) -> bool:
    """True when Cloudflare confirms the check was passed by a person. Fails closed."""
    if not token or len(token) > 2048:
        return False
    try:
        r = (session or requests).post(TURNSTILE_VERIFY, data={"secret": secret, "response": token, **({"remoteip": ip} if ip else {})}, timeout=10)
        data = r.json()
    except (requests.RequestException, ValueError):
        log.exception("Turnstile injoignable")
        return False
    if not data.get("success"):
        log.info("Turnstile refusé : %s", data.get("error-codes"))
    return bool(data.get("success"))

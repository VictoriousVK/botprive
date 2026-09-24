"""Authentication primitives (standard library only).

* Passwords: scrypt (N=2^15, r=8, p=1), random 16-byte salt, constant-time comparison.
* Sessions: 256-bit random tokens; only their SHA-256 is stored, so a leaked database does not
  leak live sessions. Absolute and idle expiry.
* CSRF: per-session token, required in the X-CSRF-Token header on every state-changing call.
* TOTP (RFC 6238, SHA-1, 30 s, 6 digits, +/-1 step): compatible with Google Authenticator,
  Microsoft Authenticator, Aegis, 1Password...
* Brute force: failed logins are counted per username and per IP; 5 failures in 15 minutes
  lock that key for the rest of the window.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
import struct
import time
from dataclasses import dataclass
from typing import Any
from urllib.parse import quote

SCRYPT_N, SCRYPT_R, SCRYPT_P = 2**15, 8, 1
MIN_PASSWORD_LEN = 12
SESSION_HOURS = 12
IDLE_MINUTES = 120
MAX_FAILURES = 5
FAILURE_WINDOW_S = 15 * 60


# ---------------- passwords ----------------
def hash_password(password: str) -> str:
    if len(password) < MIN_PASSWORD_LEN:
        raise ValueError(f"le mot de passe doit contenir au moins {MIN_PASSWORD_LEN} caractères")
    salt = secrets.token_bytes(16)
    dk = hashlib.scrypt(password.encode(), salt=salt, n=SCRYPT_N, r=SCRYPT_R, p=SCRYPT_P, maxmem=2**26, dklen=32)
    return f"scrypt${SCRYPT_N}${SCRYPT_R}${SCRYPT_P}${base64.b64encode(salt).decode()}${base64.b64encode(dk).decode()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        algo, n, r, p, salt_b64, dk_b64 = stored.split("$")
        if algo != "scrypt":
            return False
        dk = hashlib.scrypt(password.encode(), salt=base64.b64decode(salt_b64), n=int(n), r=int(r), p=int(p), maxmem=2**26, dklen=32)
        return hmac.compare_digest(dk, base64.b64decode(dk_b64))
    except (ValueError, TypeError):
        return False


# Used to spend the same time on unknown usernames as on known ones (no user enumeration).
DUMMY_HASH = "scrypt$32768$8$1$AAAAAAAAAAAAAAAAAAAAAA==$" + base64.b64encode(b"\0" * 32).decode()


# ---------------- tokens ----------------
def new_token() -> str:
    return secrets.token_urlsafe(32)


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


# ---------------- TOTP ----------------
def new_totp_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode().rstrip("=")


def totp(secret: str, at: float | None = None, step: int = 30, digits: int = 6) -> str:
    key = base64.b32decode(secret + "=" * (-len(secret) % 8), casefold=True)
    counter = int((time.time() if at is None else at) // step)
    digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    off = digest[-1] & 0x0F
    code = (struct.unpack(">I", digest[off : off + 4])[0] & 0x7FFFFFFF) % 10**digits
    return f"{code:0{digits}d}"


def verify_totp(secret: str, code: str, at: float | None = None, window: int = 1) -> bool:
    code = (code or "").strip().replace(" ", "")
    if not code.isdigit() or len(code) != 6:
        return False
    now = time.time() if at is None else at
    return any(hmac.compare_digest(totp(secret, now + k * 30), code) for k in range(-window, window + 1))


def totp_uri(secret: str, username: str, issuer: str = "HedgeFund") -> str:
    return f"otpauth://totp/{quote(issuer)}:{quote(username)}?secret={secret}&issuer={quote(issuer)}&digits=6&period=30"


# ---------------- users / sessions ----------------
@dataclass
class Session:
    user_id: int
    username: str
    csrf: str
    totp_enabled: bool


class AuthService:
    def __init__(self, store: Any, session_hours: int = SESSION_HOURS, idle_minutes: int = IDLE_MINUTES):
        self.store = store
        self.session_s = session_hours * 3600
        self.idle_s = idle_minutes * 60

    # users
    def create_user(self, username: str, password: str) -> int:
        username = username.strip()
        if not (3 <= len(username) <= 40) or not username.replace("_", "").replace("-", "").replace(".", "").isalnum():
            raise ValueError("nom d'utilisateur : 3 à 40 caractères (lettres, chiffres, . _ -)")
        if self.store.execute("SELECT 1 FROM users WHERE username = ?", (username,)):
            raise ValueError("cet utilisateur existe déjà")
        self.store.execute("INSERT INTO users (username, password_hash, created_at) VALUES (?, ?, ?)", (username, hash_password(password), int(time.time())))
        return self.store.execute("SELECT id FROM users WHERE username = ?", (username,))[0]["id"]

    def user_count(self) -> int:
        return self.store.execute("SELECT COUNT(*) AS n FROM users")[0]["n"]

    def set_password(self, user_id: int, password: str) -> None:
        self.store.execute("UPDATE users SET password_hash = ? WHERE id = ?", (hash_password(password), user_id))
        self.store.execute("DELETE FROM sessions WHERE user_id = ?", (user_id,))

    def _user(self, user_id: int):
        rows = self.store.execute("SELECT * FROM users WHERE id = ?", (user_id,))
        return rows[0] if rows else None

    def check_password(self, user_id: int, password: str) -> bool:
        u = self._user(user_id)
        return bool(u) and verify_password(password, u["password_hash"])

    def check_second_factor(self, user_id: int, code: str | None) -> bool:
        u = self._user(user_id)
        if not u or not u["totp_enabled"]:
            return True
        return bool(code) and verify_totp(u["totp_secret"], code)

    # brute-force protection
    def _failures(self, key: str, now: int) -> int:
        return self.store.execute("SELECT COUNT(*) AS n FROM login_attempts WHERE key = ? AND ok = 0 AND ts > ?", (key, now - FAILURE_WINDOW_S))[0]["n"]

    def locked(self, username: str, ip: str, now: int | None = None) -> bool:
        now = int(now or time.time())
        return self._failures(f"u:{username}", now) >= MAX_FAILURES or self._failures(f"ip:{ip}", now) >= MAX_FAILURES * 4

    def _record(self, username: str, ip: str, ok: bool, now: int) -> None:
        for key in (f"u:{username}", f"ip:{ip}"):
            self.store.execute("INSERT INTO login_attempts (key, ts, ok) VALUES (?, ?, ?)", (key, now, int(ok)))
        self.store.execute("DELETE FROM login_attempts WHERE ts < ?", (now - 7 * 86_400,))

    def login(self, username: str, password: str, totp_code: str | None, ip: str, user_agent: str) -> tuple[str, Session] | None:
        """Returns (token, session) or None. Always does the same amount of hashing work."""
        now = int(time.time())
        rows = self.store.execute("SELECT * FROM users WHERE username = ?", (username.strip(),))
        u = rows[0] if rows else None
        ok = verify_password(password, u["password_hash"] if u else DUMMY_HASH) and u is not None
        if ok and u["totp_enabled"]:
            ok = bool(totp_code) and verify_totp(u["totp_secret"], totp_code or "")
        self._record(username.strip(), ip, ok, now)
        if not ok:
            return None
        token, csrf = new_token(), new_token()
        self.store.execute(
            "INSERT INTO sessions (token_hash, user_id, csrf, created_at, last_seen, expires_at, ip, user_agent) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (token_hash(token), u["id"], csrf, now, now, now + self.session_s, ip, user_agent[:200]),
        )
        return token, Session(u["id"], u["username"], csrf, bool(u["totp_enabled"]))

    def session(self, token: str | None) -> Session | None:
        if not token:
            return None
        now = int(time.time())
        th = token_hash(token)
        rows = self.store.execute(
            "SELECT s.*, u.username, u.totp_enabled FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?", (th,)
        )
        if not rows:
            return None
        r = rows[0]
        if r["expires_at"] < now or r["last_seen"] < now - self.idle_s:
            self.store.execute("DELETE FROM sessions WHERE token_hash = ?", (th,))
            return None
        self.store.execute("UPDATE sessions SET last_seen = ? WHERE token_hash = ?", (now, th))
        return Session(r["user_id"], r["username"], r["csrf"], bool(r["totp_enabled"]))

    def logout(self, token: str | None) -> None:
        if token:
            self.store.execute("DELETE FROM sessions WHERE token_hash = ?", (token_hash(token),))

    # TOTP enrolment
    def begin_totp(self, user_id: int) -> str:
        secret = new_totp_secret()
        self.store.execute("UPDATE users SET totp_secret = ?, totp_enabled = 0 WHERE id = ?", (secret, user_id))
        return secret

    def enable_totp(self, user_id: int, code: str) -> bool:
        u = self._user(user_id)
        if not u or not u["totp_secret"] or not verify_totp(u["totp_secret"], code):
            return False
        self.store.execute("UPDATE users SET totp_enabled = 1 WHERE id = ?", (user_id,))
        return True

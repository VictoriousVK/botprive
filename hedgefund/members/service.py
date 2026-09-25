"""Members, subscriptions and payments (Wave checkout, Wave manual transfer, grants)."""

from __future__ import annotations

import re
import secrets
import time
from typing import Any

from hedgefund.members.site import FREE_OFFER, MemberSettings, SiteConfig
from hedgefund.members.wave import WaveClient, WaveError
from hedgefund.web.security import AuthService, hash_password

TERMS_VERSION = "2026-10"
EMAIL_RE = re.compile(r"^[^@\s<>\"']{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,24}$")
PHONE_RE = re.compile(r"^\+?[0-9 ]{8,20}$")
TXN_RE = re.compile(r"^[A-Za-z0-9._-]{6,40}$")
PENDING = ("pending", "declared")

SCHEMA = """
CREATE TABLE IF NOT EXISTS members (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    phone TEXT,
    password_hash TEXT NOT NULL,
    totp_secret TEXT,
    totp_enabled INTEGER NOT NULL DEFAULT 0,
    offer TEXT NOT NULL DEFAULT 'decouverte',
    offer_expires_at INTEGER,
    status TEXT NOT NULL DEFAULT 'active',
    terms_version TEXT NOT NULL,
    created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS member_sessions (
    token_hash TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL,
    csrf TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    last_seen INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    ip TEXT,
    user_agent TEXT
);
CREATE TABLE IF NOT EXISTS payments (
    id TEXT PRIMARY KEY,
    member_id INTEGER NOT NULL,
    offer TEXT NOT NULL,
    months INTEGER NOT NULL,
    amount INTEGER NOT NULL,
    currency TEXT NOT NULL,
    method TEXT NOT NULL,
    status TEXT NOT NULL,
    provider_id TEXT,
    launch_url TEXT,
    transaction_ref TEXT,
    note TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    applied_at INTEGER
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_provider ON payments(provider_id) WHERE provider_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_txn ON payments(transaction_ref) WHERE transaction_ref IS NOT NULL AND status != 'rejected';
CREATE INDEX IF NOT EXISTS idx_payments_member ON payments(member_id, created_at);
CREATE TABLE IF NOT EXISTS leads (
    email TEXT NOT NULL,
    interest TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (email, interest)
);
"""

PAYMENT_STATUS = {
    "pending": "En attente de paiement",
    "declared": "Paiement déclaré, en cours de vérification",
    "succeeded": "Payé",
    "failed": "Échec du paiement",
    "expired": "Expiré",
    "rejected": "Refusé",
}
METHOD_LABEL = {"wave_checkout": "Wave", "wave_manual": "Wave (transfert)", "grant": "Attribué par l'équipe"}


class MemberError(ValueError):
    pass


def member_auth(store: Any, session_hours: int = 72) -> AuthService:
    return AuthService(store, session_hours=session_hours, idle_minutes=7 * 24 * 60, users="members", sessions="member_sessions", login_column="email", attempt_prefix="m:")


class Members:
    def __init__(self, store: Any, site: SiteConfig, settings: MemberSettings, wave: WaveClient | None = None, now=time.time):
        self.store, self.site, self.settings, self.now = store, site, settings, now
        store.executescript(SCHEMA)
        self.auth = member_auth(store)
        self.wave = wave or (WaveClient(settings.wave_api_key, settings.wave_api_base) if settings.wave_api_enabled else None)

    # ---------------- accounts ----------------
    def register(self, email: str, password: str, name: str, phone: str = "", ip: str = "") -> int:
        if not self.settings.registration_open:
            raise MemberError("les inscriptions sont fermées pour le moment")
        email = email.strip().lower()
        name = " ".join(name.split())
        phone = phone.strip()
        if not EMAIL_RE.match(email):
            raise MemberError("adresse e-mail invalide")
        if not 2 <= len(name) <= 80:
            raise MemberError("nom : 2 à 80 caractères")
        if phone and not PHONE_RE.match(phone):
            raise MemberError("numéro de téléphone invalide (chiffres, espaces et + uniquement)")
        now = int(self.now())
        key = f"reg:{ip}"
        recent = self.store.execute("SELECT COUNT(*) AS n FROM login_attempts WHERE key = ? AND ts > ?", (key, now - 3600))[0]["n"]
        if ip and recent >= 5:
            raise MemberError("trop d'inscriptions depuis cette connexion : réessayez dans une heure")
        pw = hash_password(password)  # raises ValueError if too short
        with self.store.atomic():
            if self.store.execute("SELECT 1 FROM members WHERE email = ?", (email,)):
                raise MemberError("un compte existe déjà avec cette adresse")
            self.store.execute(
                "INSERT INTO members (email, name, phone, password_hash, offer, terms_version, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (email, name, phone or None, pw, FREE_OFFER, TERMS_VERSION, now),
            )
            if ip:
                self.store.execute("INSERT INTO login_attempts (key, ts, ok) VALUES (?, ?, 1)", (key, now))
        return self.store.execute("SELECT id FROM members WHERE email = ?", (email,))[0]["id"]

    def get(self, member_id: int) -> dict[str, Any] | None:
        rows = self.store.execute("SELECT * FROM members WHERE id = ?", (member_id,))
        return dict(rows[0]) if rows else None

    def active_offer(self, m: dict[str, Any]) -> str:
        exp = m.get("offer_expires_at")
        if m["offer"] != FREE_OFFER and (exp is None or exp > self.now()) and m["offer"] in self.site.offers:
            return m["offer"]
        return FREE_OFFER

    def entitlements(self, m: dict[str, Any] | None) -> set[str]:
        if not m or m.get("status") != "active":
            return set()
        return set(self.site.offers[self.active_offer(m)].entitlements)

    def profile(self, m: dict[str, Any]) -> dict[str, Any]:
        offer = self.active_offer(m)
        return {
            "id": m["id"], "email": m["email"], "name": m["name"], "phone": m["phone"],
            "offer": offer, "offer_label": self.site.offers[offer].label,
            "offer_expires_at": m["offer_expires_at"] if offer != FREE_OFFER else None,
            "entitlements": sorted(self.entitlements(m)), "totp_enabled": bool(m["totp_enabled"]), "created_at": m["created_at"],
        }

    def add_lead(self, email: str, interest: str) -> None:
        email = email.strip().lower()
        if not EMAIL_RE.match(email):
            raise MemberError("adresse e-mail invalide")
        self.store.execute("INSERT OR IGNORE INTO leads (email, interest, created_at) VALUES (?, ?, ?)", (email, interest, int(self.now())))

    # ---------------- payments ----------------
    def _check_offer(self, offer: str, months: int) -> int:
        if offer not in self.site.offers or offer == FREE_OFFER:
            raise MemberError("offre inconnue")
        if months not in self.site.durations:
            raise MemberError("durée non proposée")
        return self.site.price(offer, months)

    def _new_payment(self, member_id: int, offer: str, months: int, method: str, status: str, note: str = "") -> dict[str, Any]:
        amount = self._check_offer(offer, months) if method != "grant" else 0
        now = int(self.now())
        pid = "pay_" + secrets.token_hex(8)
        self.store.execute(
            "INSERT INTO payments (id, member_id, offer, months, amount, currency, method, status, note, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 'XOF', ?, ?, ?, ?, ?)",
            (pid, member_id, offer, months, amount, method, status, note or None, now, now),
        )
        return self.payment(pid)

    def payment(self, payment_id: str) -> dict[str, Any] | None:
        rows = self.store.execute("SELECT * FROM payments WHERE id = ?", (payment_id,))
        return dict(rows[0]) if rows else None

    def public_payment(self, p: dict[str, Any]) -> dict[str, Any]:
        return {
            "id": p["id"], "offer": p["offer"], "offer_label": self.site.offers[p["offer"]].label if p["offer"] in self.site.offers else p["offer"],
            "months": p["months"], "amount": p["amount"], "currency": p["currency"], "method": p["method"], "method_label": METHOD_LABEL.get(p["method"], p["method"]),
            "status": p["status"], "status_label": PAYMENT_STATUS.get(p["status"], p["status"]), "transaction_ref": p["transaction_ref"],
            "launch_url": p["launch_url"] if p["status"] == "pending" else None, "created_at": p["created_at"], "applied_at": p["applied_at"],
        }

    def payments_of(self, member_id: int, limit: int = 50) -> list[dict[str, Any]]:
        return [self.public_payment(dict(r)) for r in self.store.execute("SELECT * FROM payments WHERE member_id = ? ORDER BY created_at DESC LIMIT ?", (member_id, limit))]

    def checkout(self, member_id: int, offer: str, months: int) -> dict[str, Any]:
        """Starts a payment: a Wave checkout session if the API is configured, else a manual transfer."""
        self._check_offer(offer, months)
        open_count = self.store.execute("SELECT COUNT(*) AS n FROM payments WHERE member_id = ? AND status IN ('pending', 'declared') AND created_at > ?", (member_id, int(self.now()) - 86_400))[0]["n"]
        if open_count >= 5:
            raise MemberError("trop de paiements en attente : terminez ou attendez la validation des précédents")
        if self.wave is None:
            wave = self.site.billing.get("wave", {}) or {}
            if not (wave.get("manual_number") or wave.get("manual_link")):
                raise MemberError("le paiement Wave n'est pas encore configuré : contactez l'équipe")
            p = self._new_payment(member_id, offer, months, "wave_manual", "pending")
            return {"payment": self.public_payment(p), "manual": {"number": wave.get("manual_number") or None, "link": wave.get("manual_link") or None, "amount": p["amount"], "reference": p["id"]}}
        p = self._new_payment(member_id, offer, months, "wave_checkout", "pending")
        back = f"{self.settings.public_url}/compte/?paiement={p['id']}"
        try:
            s = self.wave.create_checkout(p["amount"], p["id"], back + "&retour=ok", back + "&retour=erreur", idempotency_key=p["id"])
        except WaveError as e:
            self._set_status(p["id"], "failed", note=str(e)[:200])
            raise MemberError(str(e)) from e
        if not str(s.get("wave_launch_url", "")).startswith("https://") or not s.get("id"):
            self._set_status(p["id"], "failed", note="réponse Wave inattendue")
            raise MemberError("réponse inattendue de Wave : réessayez plus tard")
        self.store.execute("UPDATE payments SET provider_id = ?, launch_url = ?, updated_at = ? WHERE id = ?", (s["id"], s["wave_launch_url"], int(self.now()), p["id"]))
        return {"payment": self.public_payment(self.payment(p["id"])), "launch_url": s["wave_launch_url"]}

    def _set_status(self, payment_id: str, status: str, note: str | None = None, transaction_ref: str | None = None) -> None:
        self.store.execute(
            "UPDATE payments SET status = ?, note = COALESCE(?, note), transaction_ref = COALESCE(?, transaction_ref), updated_at = ? WHERE id = ? AND applied_at IS NULL",
            (status, note, transaction_ref, int(self.now()), payment_id),
        )

    def _apply(self, payment_id: str, transaction_ref: str | None = None, note: str | None = None) -> bool:
        """Credits a payment exactly once and extends the member's subscription."""
        with self.store.atomic():
            p = self.payment(payment_id)
            if p is None or p["applied_at"] is not None:
                return False
            m = self.get(p["member_id"])
            if m is None:
                return False
            now = int(self.now())
            days = p["months"] * self.site.month_days
            current = m["offer_expires_at"] or 0
            start = current if (m["offer"] == p["offer"] and current > now) else now
            self.store.execute("UPDATE members SET offer = ?, offer_expires_at = ? WHERE id = ?", (p["offer"], start + days * 86_400, m["id"]))
            self.store.execute(
                "UPDATE payments SET status = 'succeeded', applied_at = ?, updated_at = ?, transaction_ref = COALESCE(?, transaction_ref), note = COALESCE(?, note) WHERE id = ?",
                (now, now, transaction_ref, note, payment_id),
            )
        return True

    def refresh(self, payment_id: str) -> dict[str, Any] | None:
        """Re-reads a Wave checkout from the API and credits it when Wave says it is paid."""
        p = self.payment(payment_id)
        if p is None or p["method"] != "wave_checkout" or p["status"] != "pending" or not p["provider_id"] or self.wave is None:
            return p
        try:
            s = self.wave.get_checkout(p["provider_id"])
        except WaveError:
            return p
        ok = (
            s.get("id") == p["provider_id"]
            and s.get("client_reference") == p["id"]
            and str(s.get("currency")) == "XOF"
            and str(s.get("amount", "")).split(".")[0] == str(p["amount"])
        )
        if ok and s.get("payment_status") == "succeeded":
            self._apply(p["id"], transaction_ref=s.get("transaction_id"))
        elif s.get("checkout_status") == "expired" or s.get("payment_status") == "cancelled":
            self._set_status(p["id"], "expired" if s.get("checkout_status") == "expired" else "failed")
        elif not ok:
            self._set_status(p["id"], "failed", note="session Wave incohérente (montant, devise ou référence)")
        return self.payment(payment_id)

    def on_webhook(self, event: dict[str, Any]) -> str | None:
        """Handles a verified Wave webhook: finds our payment and re-reads it from the API."""
        data = event.get("data") or {}
        sid = data.get("id")
        if not isinstance(sid, str):
            return None
        rows = self.store.execute("SELECT id FROM payments WHERE provider_id = ?", (sid,))
        if not rows:
            return None
        self.refresh(rows[0]["id"])
        return rows[0]["id"]

    def declare(self, member_id: int, payment_id: str, transaction_ref: str) -> dict[str, Any]:
        """Manual Wave transfer: the member gives the transaction ID shown in their Wave app."""
        ref = transaction_ref.strip()
        if not TXN_RE.match(ref):
            raise MemberError("identifiant de transaction Wave invalide (6 à 40 lettres ou chiffres)")
        p = self.payment(payment_id)
        if p is None or p["member_id"] != member_id or p["method"] != "wave_manual":
            raise MemberError("paiement introuvable")
        if p["status"] not in ("pending", "declared"):
            raise MemberError("ce paiement est déjà traité")
        if self.store.execute("SELECT 1 FROM payments WHERE transaction_ref = ? AND id != ? AND status != 'rejected'", (ref, payment_id)):
            raise MemberError("cette transaction a déjà été déclarée")
        self._set_status(payment_id, "declared", transaction_ref=ref)
        return self.public_payment(self.payment(payment_id))

    # ---------------- administration ----------------
    def approve(self, payment_id: str, operator: str) -> bool:
        p = self.payment(payment_id)
        if p is None or p["method"] != "wave_manual" or p["status"] not in PENDING:
            raise MemberError("seul un transfert Wave en attente peut être validé")
        return self._apply(payment_id, note=f"validé par {operator}")

    def reject(self, payment_id: str, operator: str, reason: str) -> None:
        p = self.payment(payment_id)
        if p is None or p["status"] not in PENDING:
            raise MemberError("ce paiement n'est pas en attente")
        self._set_status(payment_id, "rejected", note=f"refusé par {operator} : {reason[:160]}")

    def grant(self, member_id: int, offer: str, months: int, operator: str, reason: str) -> dict[str, Any]:
        if offer not in self.site.offers or offer == FREE_OFFER or not 1 <= months <= 24:
            raise MemberError("offre ou durée invalide")
        if self.get(member_id) is None:
            raise MemberError("membre introuvable")
        p = self._new_payment(member_id, offer, months, "grant", "pending", note=f"attribué par {operator} : {reason[:160]}")
        self._apply(p["id"])
        return self.public_payment(self.payment(p["id"]))

    def set_status(self, member_id: int, status: str) -> None:
        if status not in ("active", "suspended"):
            raise MemberError("statut invalide")
        self.store.execute("UPDATE members SET status = ? WHERE id = ?", (status, member_id))
        if status == "suspended":
            self.store.execute("DELETE FROM member_sessions WHERE user_id = ?", (member_id,))

    def list_members(self, q: str = "", limit: int = 200) -> list[dict[str, Any]]:
        like = f"%{q.strip().lower()}%"
        rows = self.store.execute("SELECT * FROM members WHERE email LIKE ? OR lower(name) LIKE ? ORDER BY created_at DESC LIMIT ?", (like, like, limit))
        return [{**self.profile(dict(r)), "status": r["status"]} for r in rows]

    def list_payments(self, status: str = "", limit: int = 200) -> list[dict[str, Any]]:
        sql = "SELECT p.*, m.email, m.name FROM payments p JOIN members m ON m.id = p.member_id"
        args: tuple = ()
        if status:
            sql += " WHERE p.status = ?"
            args = (status,)
        rows = self.store.execute(sql + " ORDER BY p.created_at DESC LIMIT ?", (*args, limit))
        return [{**self.public_payment(dict(r)), "email": r["email"], "name": r["name"], "note": r["note"]} for r in rows]

    def list_leads(self, limit: int = 500) -> list[dict[str, Any]]:
        return [dict(r) for r in self.store.execute("SELECT * FROM leads ORDER BY created_at DESC LIMIT ?", (limit,))]

    def stats(self) -> dict[str, Any]:
        now = int(self.now())
        paying = self.store.execute("SELECT offer, COUNT(*) AS n FROM members WHERE offer != ? AND offer_expires_at > ? AND status = 'active' GROUP BY offer", (FREE_OFFER, now))
        revenue = self.store.execute("SELECT COALESCE(SUM(amount), 0) AS s FROM payments WHERE status = 'succeeded' AND applied_at > ?", (now - 30 * 86_400,))[0]["s"]
        return {
            "members": self.store.execute("SELECT COUNT(*) AS n FROM members")[0]["n"],
            "paying": {r["offer"]: r["n"] for r in paying},
            "to_review": self.store.execute("SELECT COUNT(*) AS n FROM payments WHERE status = 'declared'")[0]["n"],
            "revenue_30d_xof": revenue,
            "leads": self.store.execute("SELECT COUNT(*) AS n FROM leads")[0]["n"],
        }

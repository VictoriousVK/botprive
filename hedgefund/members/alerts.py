"""Team alerts when money arrives: a manual Wave transfer to check, or a Wave payment confirmed
by the API. Three channels, all optional, set in /admin/ → Réglages (or by environment):

* Telegram: the platform's bot writes to the operator's chat. Sending needs no domain name and
  no webhook; the admin finds the chat identifier with getUpdates after writing to the bot;
* e-mail, sent through an SMTP account (a Gmail address with an app password is enough);
* a Discord- or Slack-compatible webhook (the URL of a private channel of the team).

The message carries what the operator needs to find the transfer in the Wave app (name, offer,
amount, transaction ID) and nothing more: no member e-mail, no phone number. Credentials (bot
token, SMTP password, webhook URL) stay on the server and are never sent back to the page."""

from __future__ import annotations

import logging
import os
import re
import smtplib
import threading
from email.message import EmailMessage
from typing import Any, Callable

import requests

log = logging.getLogger(__name__)

KEY_WEBHOOK = "ops.alert_webhook_url"
KEY_TELEGRAM = "ops.alert_telegram_chat"
KEY_BOT = "ops.telegram_bot_token"
KEY_EMAIL = "ops.alert_email"
KEY_SMTP = "ops.smtp"  # {"host", "port", "user", "password"}
EMAIL_RE = re.compile(r"^[^@\s<>\"']{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,24}$")
TOKEN_RE = re.compile(r"^\d{5,15}:[A-Za-z0-9_-]{30,60}$")


def fcfa(amount: int | float | None) -> str:
    return f"{int(amount or 0):,}".replace(",", " ") + " FCFA"


def valid_webhook(url: str) -> bool:
    return url.startswith("https://") and len(url) <= 500 and " " not in url


def valid_chat(chat: str) -> bool:
    c = chat.strip()
    return (c.lstrip("-").isdigit() and 3 <= len(c) <= 20) or (c.startswith("@") and 5 <= len(c) <= 40)


def smtp_send(cfg: dict[str, Any], sender: str, to: str, subject: str, body: str) -> None:
    msg = EmailMessage()
    msg["From"], msg["To"], msg["Subject"] = sender, to, subject
    msg.set_content(body)
    port = int(cfg.get("port") or 587)
    if port == 465:
        with smtplib.SMTP_SSL(cfg["host"], port, timeout=15) as s:
            s.login(cfg["user"], cfg["password"])
            s.send_message(msg)
    else:
        with smtplib.SMTP(cfg["host"], port, timeout=15) as s:
            s.starttls()
            s.login(cfg["user"], cfg["password"])
            s.send_message(msg)


class OperatorAlerts:
    def __init__(self, store: Any, telegram_token: str | None = None, public_url: str = "", post: Callable[..., Any] = requests.post,
                 get: Callable[..., Any] = requests.get, mailer: Callable[..., None] = smtp_send, background: bool = True):
        self.store = store
        self._env_token = (telegram_token if telegram_token is not None else os.environ.get("HF_TELEGRAM_BOT_TOKEN", "")).strip()
        self.public_url = (public_url or os.environ.get("HF_PUBLIC_URL", "")).rstrip("/")
        self.post, self.get, self.mailer = post, get, mailer
        self.background = background

    # ---------------- settings ----------------
    def _setting(self, key: str) -> Any:
        return self.store.get_setting(key) if self.store is not None else None

    @property
    def telegram_token(self) -> str:
        return self._env_token or str(self._setting(KEY_BOT) or "").strip()

    @telegram_token.setter
    def telegram_token(self, value: str) -> None:  # tests and the environment
        self._env_token = value

    def webhook_url(self) -> str:
        return str(self._setting(KEY_WEBHOOK) or os.environ.get("ALERT_WEBHOOK_URL", "")).strip()

    def telegram_chat(self) -> str:
        return str(self._setting(KEY_TELEGRAM) or os.environ.get("LF_ALERT_TELEGRAM_CHAT", "")).strip()

    def email_to(self) -> str:
        return str(self._setting(KEY_EMAIL) or os.environ.get("LF_ALERT_EMAIL", "")).strip()

    def smtp(self) -> dict[str, Any] | None:
        env = {"host": os.environ.get("HF_SMTP_HOST", ""), "port": os.environ.get("HF_SMTP_PORT", "587"), "user": os.environ.get("HF_SMTP_USER", ""), "password": os.environ.get("HF_SMTP_PASSWORD", "")}
        cfg = env if env["host"] and env["user"] and env["password"] else (self._setting(KEY_SMTP) or None)
        return cfg if cfg and cfg.get("host") and cfg.get("user") and cfg.get("password") else None

    def public_settings(self) -> dict[str, Any]:
        """What the admin page shows. Credentials are reported as set or not, never returned."""
        smtp = self.smtp()
        return {
            "webhook_set": bool(self.webhook_url()), "webhook_from_env": bool(os.environ.get("ALERT_WEBHOOK_URL")) and not self._setting(KEY_WEBHOOK),
            "telegram_chat": self.telegram_chat(), "telegram_bot": bool(self.telegram_token), "telegram_bot_from_env": bool(self._env_token),
            "email_to": self.email_to(), "smtp_set": smtp is not None, "smtp_user": (smtp or {}).get("user", ""), "smtp_host": (smtp or {}).get("host", ""),
        }

    def save(self, webhook_url: str | None = None, telegram_chat: str | None = None, telegram_token: str | None = None, email_to: str | None = None,
             smtp_user: str | None = None, smtp_password: str | None = None, smtp_host: str | None = None) -> None:
        """``None`` keeps the current value, ``""`` clears it."""
        if webhook_url is not None:
            url = webhook_url.strip()
            if url and not valid_webhook(url):
                raise ValueError("adresse du webhook : elle doit commencer par https:// (Discord : Paramètres du salon → Intégrations → Webhooks)")
            self.store.set_setting(KEY_WEBHOOK, url)
        if telegram_token is not None:
            tok = telegram_token.strip()
            if tok and not TOKEN_RE.match(tok):
                raise ValueError("jeton du bot Telegram invalide : copiez-le tel que @BotFather l'affiche (123456789:AA…)")
            self.store.set_setting(KEY_BOT, tok)
        if telegram_chat is not None:
            chat = telegram_chat.strip()
            if chat and not valid_chat(chat):
                raise ValueError("identifiant Telegram : un nombre (ex. 123456789, ou -100… pour un groupe) ; utilisez « Trouver mon identifiant »")
            self.store.set_setting(KEY_TELEGRAM, chat)
        if email_to is not None:
            to = email_to.strip().lower()
            if to and not EMAIL_RE.match(to):
                raise ValueError("adresse e-mail de réception invalide")
            self.store.set_setting(KEY_EMAIL, to)
        if smtp_user is not None or smtp_password is not None or smtp_host is not None:
            cur = dict(self._setting(KEY_SMTP) or {})
            user = (smtp_user if smtp_user is not None else cur.get("user", "")).strip().lower()
            if user and not EMAIL_RE.match(user):
                raise ValueError("compte d'envoi : une adresse e-mail (ex. votre adresse Gmail)")
            host = (smtp_host if smtp_host is not None else cur.get("host", "")).strip() or ("smtp.gmail.com" if user.endswith("@gmail.com") else "")
            password = (smtp_password if smtp_password is not None else cur.get("password", "")).replace(" ", "").strip()
            if not user:
                self.store.set_setting(KEY_SMTP, {})
            else:
                if not host:
                    raise ValueError("serveur d'envoi (SMTP) manquant pour cette adresse")
                self.store.set_setting(KEY_SMTP, {"host": host, "port": 587, "user": user, "password": password})

    def find_chats(self) -> list[dict[str, Any]]:
        """Chats that recently wrote to the bot (Telegram getUpdates): no webhook, no domain needed."""
        if not self.telegram_token:
            raise ValueError("renseignez d'abord le jeton du bot (donné par @BotFather)")
        try:
            r = self.get(f"https://api.telegram.org/bot{self.telegram_token}/getUpdates", params={"limit": 50, "timeout": 0}, timeout=10)
        except requests.RequestException as e:
            raise ValueError(f"Telegram injoignable : {e}") from e
        if r.status_code == 409:
            raise ValueError("le bot a un webhook actif : envoyez-lui /id, il répond avec l'identifiant")
        if r.status_code == 401:
            raise ValueError("jeton du bot refusé par Telegram : vérifiez-le auprès de @BotFather")
        data = r.json() if r.status_code == 200 else {}
        seen: dict[str, dict[str, Any]] = {}
        for u in data.get("result", []) or []:
            msg = u.get("message") or u.get("channel_post") or u.get("my_chat_member") or {}
            chat = msg.get("chat") or {}
            if "id" in chat:
                name = chat.get("title") or " ".join(x for x in (chat.get("first_name"), chat.get("last_name")) if x) or chat.get("username") or ""
                seen[str(chat["id"])] = {"id": str(chat["id"]), "name": name, "type": chat.get("type", "")}
        return list(seen.values())

    # ---------------- sending ----------------
    def send(self, text: str, subject: str = "Alerte Liberté Financière") -> dict[str, bool | None]:
        """Sends now and reports each channel: True sent, False failed, None not configured."""
        out: dict[str, bool | None] = {"telegram": None, "email": None, "webhook": None}
        chat = self.telegram_chat()
        if chat and self.telegram_token:
            try:
                r = self.post(f"https://api.telegram.org/bot{self.telegram_token}/sendMessage", json={"chat_id": chat, "text": text[:4000], "disable_web_page_preview": True}, timeout=8)
                out["telegram"] = r.status_code == 200
            except requests.RequestException as e:
                log.warning("alert telegram: %s", e)
                out["telegram"] = False
        to, smtp = self.email_to(), self.smtp()
        if to and smtp:
            try:
                self.mailer(smtp, smtp["user"], to, subject, text)
                out["email"] = True
            except (OSError, smtplib.SMTPException) as e:
                log.warning("alert e-mail: %s", e)
                out["email"] = False
        url = self.webhook_url()
        if url:
            try:
                r = self.post(url, json={"content": text[:1900], "text": text[:1900]}, timeout=8)  # Discord reads "content", Slack "text"
                out["webhook"] = 200 <= r.status_code < 300
            except requests.RequestException as e:
                log.warning("alert webhook: %s", e)
                out["webhook"] = False
        return out

    def configured(self) -> bool:
        return bool((self.telegram_chat() and self.telegram_token) or (self.email_to() and self.smtp()) or self.webhook_url())

    def _dispatch(self, text: str, subject: str) -> None:
        if not self.configured():
            return
        if self.background:  # never make the member wait for Telegram, the mail server or Discord
            threading.Thread(target=self.send, args=(text, subject), name="operator-alert", daemon=True).start()
        else:
            self.send(text, subject)

    # ---------------- payment events ----------------
    def message(self, event: str, d: dict[str, Any]) -> tuple[str, str] | None:
        """(subject, text) for the team, or None when the team made the change itself."""
        duration = "à vie" if not d.get("months") else f"{d['months']} mois"
        what = f"{d['member_name']} · {d['offer_label']} ({duration}) · {fcfa(d['amount'])}"
        admin = f"{self.public_url}/admin/" if self.public_url else "/admin/ (sur le serveur)"
        if event == "payment_declared":
            return (f"Paiement Wave à valider : {d['offer_label']}, {fcfa(d['amount'])}",
                    f"Paiement Wave à valider\n{what}\nTransaction Wave : {d.get('transaction_ref') or '—'}\n"
                    f"Retrouvez ce transfert dans votre application Wave (même montant, même identifiant), puis validez-le : {admin} → Paiements.")
        if event == "payment_succeeded" and d.get("method") == "wave_checkout":
            return (f"Paiement Wave reçu : {d['offer_label']}, {fcfa(d['amount'])}", f"Paiement Wave reçu et confirmé par Wave\n{what}\nAccès activé automatiquement.")
        return None  # approvals and grants are made by the team itself; rejections too

    def on_payment(self, event: str, data: dict[str, Any]) -> None:
        m = self.message(event, data)
        if m:
            self._dispatch(m[1], m[0])

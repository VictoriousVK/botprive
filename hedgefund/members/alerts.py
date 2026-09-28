"""Team alerts when money arrives: a manual Wave transfer to check, or a Wave payment confirmed
by the API. Two channels, both optional and set in /admin/ → Réglages (or by environment):

* a Discord- or Slack-compatible webhook (the URL of a private channel of the team);
* a Telegram chat, reached through the platform's bot (HF_TELEGRAM_BOT_TOKEN).

The message carries what the operator needs to find the transfer in the Wave app (name, offer,
amount, transaction ID) and nothing more: no e-mail, no phone number."""

from __future__ import annotations

import logging
import os
import threading
from typing import Any, Callable

import requests

log = logging.getLogger(__name__)

KEY_WEBHOOK = "ops.alert_webhook_url"
KEY_TELEGRAM = "ops.alert_telegram_chat"


def fcfa(amount: int | float | None) -> str:
    return f"{int(amount or 0):,}".replace(",", " ") + " FCFA"


def valid_webhook(url: str) -> bool:
    return url.startswith("https://") and len(url) <= 500 and " " not in url


def valid_chat(chat: str) -> bool:
    c = chat.strip()
    return (c.lstrip("-").isdigit() and 3 <= len(c) <= 20) or (c.startswith("@") and 5 <= len(c) <= 40)


class OperatorAlerts:
    def __init__(self, store: Any, telegram_token: str | None = None, public_url: str = "", post: Callable[..., Any] = requests.post, background: bool = True):
        self.store = store
        self.telegram_token = (telegram_token if telegram_token is not None else os.environ.get("HF_TELEGRAM_BOT_TOKEN", "")).strip()
        self.public_url = (public_url or os.environ.get("HF_PUBLIC_URL", "")).rstrip("/")
        self.post = post
        self.background = background

    # ---------------- settings ----------------
    def webhook_url(self) -> str:
        return (self.store.get_setting(KEY_WEBHOOK) or os.environ.get("ALERT_WEBHOOK_URL", "")).strip()

    def telegram_chat(self) -> str:
        return (self.store.get_setting(KEY_TELEGRAM) or os.environ.get("LF_ALERT_TELEGRAM_CHAT", "")).strip()

    def public_settings(self) -> dict[str, Any]:
        """What the admin page shows: the webhook URL is a credential, so only whether it is set."""
        return {
            "webhook_set": bool(self.webhook_url()), "webhook_from_env": bool(os.environ.get("ALERT_WEBHOOK_URL")) and not self.store.get_setting(KEY_WEBHOOK),
            "telegram_chat": self.telegram_chat(), "telegram_bot": bool(self.telegram_token),
        }

    def save(self, webhook_url: str | None, telegram_chat: str | None) -> None:
        """``None`` keeps the current value, ``""`` clears it."""
        if webhook_url is not None:
            url = webhook_url.strip()
            if url and not valid_webhook(url):
                raise ValueError("adresse du webhook : elle doit commencer par https:// (Discord : Paramètres du salon → Intégrations → Webhooks)")
            self.store.set_setting(KEY_WEBHOOK, url)
        if telegram_chat is not None:
            chat = telegram_chat.strip()
            if chat and not valid_chat(chat):
                raise ValueError("identifiant Telegram : un nombre (ex. 123456789, ou -100… pour un groupe) ; envoyez /id au bot pour l'obtenir")
            self.store.set_setting(KEY_TELEGRAM, chat)

    # ---------------- sending ----------------
    def send(self, text: str) -> dict[str, bool | None]:
        """Sends now and reports each channel: True sent, False failed, None not configured."""
        out: dict[str, bool | None] = {"webhook": None, "telegram": None}
        url = self.webhook_url()
        if url:
            try:
                r = self.post(url, json={"content": text[:1900], "text": text[:1900]}, timeout=8)  # Discord reads "content", Slack "text"
                out["webhook"] = 200 <= r.status_code < 300
            except requests.RequestException as e:
                log.warning("alert webhook: %s", e)
                out["webhook"] = False
        chat = self.telegram_chat()
        if chat and self.telegram_token:
            try:
                r = self.post(f"https://api.telegram.org/bot{self.telegram_token}/sendMessage", json={"chat_id": chat, "text": text[:4000], "disable_web_page_preview": True}, timeout=8)
                out["telegram"] = r.status_code == 200
            except requests.RequestException as e:
                log.warning("alert telegram: %s", e)
                out["telegram"] = False
        return out

    def _dispatch(self, text: str) -> None:
        if not (self.webhook_url() or (self.telegram_chat() and self.telegram_token)):
            return
        if self.background:  # never make the member wait for Discord or Telegram
            threading.Thread(target=self.send, args=(text,), name="operator-alert", daemon=True).start()
        else:
            self.send(text)

    # ---------------- payment events ----------------
    def message(self, event: str, d: dict[str, Any]) -> str | None:
        duration = "à vie" if not d.get("months") else f"{d['months']} mois"
        what = f"{d['member_name']} · {d['offer_label']} ({duration}) · {fcfa(d['amount'])}"
        admin = f"{self.public_url}/admin/" if self.public_url else "/admin/"
        if event == "payment_declared":
            return (f"Paiement Wave à valider\n{what}\nTransaction Wave : {d.get('transaction_ref') or '—'}\n"
                    f"Retrouvez ce transfert dans votre application Wave (même montant, même identifiant), puis validez-le : {admin} → Paiements.")
        if event == "payment_succeeded" and d.get("method") == "wave_checkout":
            return f"Paiement Wave reçu et confirmé par Wave\n{what}\nAccès activé automatiquement."
        return None  # approvals and grants are made by the team itself; rejections too

    def on_payment(self, event: str, data: dict[str, Any]) -> None:
        text = self.message(event, data)
        if text:
            self._dispatch(text)

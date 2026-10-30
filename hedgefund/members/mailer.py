"""Outgoing e-mail (account confirmation, password reset).

Two senders:

* ``SmtpMailer``: any SMTP provider (Brevo, Resend, Mailjet, Gmail Workspace...). Configured
  with the ``LF_SMTP_*`` environment variables. Mails go out on a background thread, so a slow
  provider never slows down a sign-up.
* ``LogMailer``: no provider configured. Nothing is sent; the message (and its link) is written
  to the server log, and kept in ``outbox`` (used by the tests). Fine on a laptop, useless in
  production: the server prints a warning at start-up when it is in use.
"""

from __future__ import annotations

import html
import logging
import os
import smtplib
import ssl
import threading
from dataclasses import dataclass, field
from email.message import EmailMessage
from email.utils import formataddr, make_msgid, parseaddr

log = logging.getLogger("hedgefund.mail")


@dataclass
class Mail:
    to: str
    subject: str
    text: str
    html: str


class LogMailer:
    configured = False

    def __init__(self) -> None:
        self.outbox: list[Mail] = []

    def send(self, mail: Mail) -> None:
        self.outbox.append(mail)
        del self.outbox[:-50]
        log.warning("E-mail NON envoyé (aucun serveur SMTP configuré, voir LF_SMTP_HOST) - à %s : %s\n%s", mail.to, mail.subject, mail.text)


@dataclass
class SmtpMailer:
    host: str
    port: int = 587
    user: str = ""
    password: str = ""
    sender: str = ""
    security: str = "starttls"  # starttls | ssl | none
    timeout: float = 20.0
    background: bool = True
    configured: bool = field(default=True, init=False)

    def _message(self, mail: Mail) -> EmailMessage:
        msg = EmailMessage()
        msg["From"] = self.sender
        msg["To"] = mail.to
        msg["Subject"] = mail.subject
        domain = parseaddr(self.sender)[1].rpartition("@")[2] or None
        msg["Message-ID"] = make_msgid(domain=domain)
        msg.set_content(mail.text)
        msg.add_alternative(mail.html, subtype="html")
        return msg

    def _deliver(self, mail: Mail) -> None:
        try:
            ctx = ssl.create_default_context()
            if self.security == "ssl":
                smtp: smtplib.SMTP = smtplib.SMTP_SSL(self.host, self.port, timeout=self.timeout, context=ctx)
            else:
                smtp = smtplib.SMTP(self.host, self.port, timeout=self.timeout)
            with smtp:
                if self.security == "starttls":
                    smtp.starttls(context=ctx)
                if self.user:
                    smtp.login(self.user, self.password)
                smtp.send_message(self._message(mail))
            log.info("e-mail envoyé à %s : %s", mail.to, mail.subject)
        except Exception:
            log.exception("échec d'envoi de l'e-mail à %s (%s)", mail.to, mail.subject)

    def send(self, mail: Mail) -> None:
        if self.background:
            threading.Thread(target=self._deliver, args=(mail,), daemon=True, name="mailer").start()
        else:
            self._deliver(mail)


def mailer_from_env() -> SmtpMailer | LogMailer:
    host = os.environ.get("LF_SMTP_HOST", "").strip()
    if not host:
        return LogMailer()
    security = os.environ.get("LF_SMTP_SECURITY", "starttls").strip().lower()
    if security not in ("starttls", "ssl", "none"):
        security = "starttls"
    default_port = "465" if security == "ssl" else "587"
    return SmtpMailer(
        host=host,
        port=int(os.environ.get("LF_SMTP_PORT", default_port) or default_port),
        user=os.environ.get("LF_SMTP_USER", "").strip(),
        password=os.environ.get("LF_SMTP_PASSWORD", "").strip(),
        sender=os.environ.get("LF_MAIL_FROM", "").strip() or formataddr(("Liberté Financière", os.environ.get("LF_SMTP_USER", "").strip())),
        security=security,
    )


# ---------------- templates ----------------
def _layout(title: str, intro: str, button: str, link: str, outro: str) -> str:
    e = html.escape
    return f"""<!doctype html><html lang="fr"><body style="margin:0;background:#03050a;padding:32px 12px;font-family:Inter,Segoe UI,Roboto,Arial,sans-serif;color:#e9eef6">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center">
<table role="presentation" width="100%" style="max-width:520px;background:#0c1522;border:1px solid #172538;border-radius:16px" cellpadding="0" cellspacing="0">
<tr><td style="padding:32px 32px 8px"><div style="font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:#4fb0ff;font-weight:700">Liberté Financière</div>
<h1 style="margin:12px 0 0;font-size:22px;line-height:1.3;color:#ffffff">{e(title)}</h1></td></tr>
<tr><td style="padding:8px 32px 0;font-size:15px;line-height:1.6;color:#c4cedb">{e(intro)}</td></tr>
<tr><td style="padding:24px 32px"><a href="{e(link)}" style="display:inline-block;background:#2a8fea;color:#ffffff;text-decoration:none;font-weight:700;padding:12px 22px;border-radius:10px">{e(button)}</a></td></tr>
<tr><td style="padding:0 32px 28px;font-size:13px;line-height:1.6;color:#93a1b5">{e(outro)}<br><br>Si le bouton ne marche pas, copiez ce lien dans votre navigateur :<br><span style="color:#8fcbff;word-break:break-all">{e(link)}</span></td></tr>
</table></td></tr></table></body></html>"""


def verification_mail(to: str, name: str, link: str, hours: int) -> Mail:
    first = (name.split() or [""])[0]
    intro = f"Bonjour {first}, merci pour votre inscription. Confirmez votre adresse e-mail pour activer votre compte."
    outro = f"Ce lien est valable {hours} heures. Si vous n'avez pas créé de compte, ignorez cet e-mail : rien ne sera activé."
    text = f"{intro}\n\n{link}\n\n{outro}\n\nLiberté Financière"
    return Mail(to, "Confirmez votre adresse e-mail - Liberté Financière", text, _layout("Confirmez votre adresse e-mail", intro, "Confirmer mon adresse", link, outro))


def reset_mail(to: str, name: str, link: str, minutes: int) -> Mail:
    first = (name.split() or [""])[0]
    intro = f"Bonjour {first}, vous avez demandé à changer le mot de passe de votre compte."
    outro = f"Ce lien est valable {minutes} minutes et ne sert qu'une fois. Si vous n'avez rien demandé, ignorez cet e-mail : votre mot de passe reste inchangé."
    text = f"{intro}\n\n{link}\n\n{outro}\n\nLiberté Financière"
    return Mail(to, "Nouveau mot de passe - Liberté Financière", text, _layout("Choisissez un nouveau mot de passe", intro, "Changer mon mot de passe", link, outro))

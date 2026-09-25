"""Public site content (config/site.yaml) and server settings (environment variables)."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

from hedgefund.config import REPO_ROOT

# What a member can be given access to. Products grant a set of these; courses and features
# check them. Labels are shown to members.
ENTITLEMENTS = {
    "academy_free": "Cours gratuits",
    "academy_member": "Cours réservés aux membres",
    "community_private": "Communauté privée (Telegram et Discord)",
    "analyses": "Analyses Or et Nasdaq, commentaires quotidiens",
    "calendar": "Calendrier économique",
    "webinars": "Webinaires mensuels",
    "ea_one": "Accès à 1 EA",
    "ea_all": "Accès à tous les EA",
    "performance": "Dashboard de performance, journal et statistiques",
    "mt5_connect": "Connexion MT5",
    "coach_ia": "IA Trading Coach",
    "formation_ict": "Formation ICT Victorious Trader",
    "formation_ea": "Formation Développement EA MT5",
    "formation_quant": "Formation Quant et IA Trading",
    "elite_group": "Groupe privé Elite (lives, débriefs, questions-réponses)",
    "mentorat": "Mentorat individuel",
    "priority_support": "Support prioritaire",
    "early_access": "Accès anticipé aux nouveautés",
    "copy_demo": "Copytrading (démo)",
    "copy_live": "Copytrading réel (après ouverture)",
    "lab": "Laboratoire de backtest",
}
CATEGORIES = {
    "abonnement": "Abonnements mensuels",
    "formation": "Formations (paiement unique)",
    "mentorat": "Mentorat Victor Faye",
    "licence": "Licences EA",
}
PERIODS = ("month", "once")
PRODUCT_STATUSES = {"available": "Disponible", "soon": "Bientôt", "contact": "Sur candidature"}
FREE_OFFER = "gratuit"  # the account every member has, whatever they bought
ROBOT_STATUSES = {"beta": "Disponible en bêta", "available": "Disponible", "development": "En développement", "retired": "Retiré"}


class SiteConfigError(ValueError):
    pass


@dataclass(frozen=True)
class Product:
    key: str
    category: str
    label: str
    period: str  # "month" (paid per month) or "once" (one payment, lifetime access)
    status: str
    price_usd: float | None
    price_xof: int | None  # the amount charged through Wave
    price_range_usd: tuple[float, float] | None
    alt_price: str
    summary: str
    audience: tuple[str, ...]
    highlights: tuple[dict[str, Any], ...]
    entitlements: frozenset[str]
    featured: bool = False
    page: str = ""

    @property
    def purchasable(self) -> bool:
        return self.status == "available" and self.price_xof is not None and self.price_xof > 0

    def public(self) -> dict[str, Any]:
        return {
            "key": self.key, "category": self.category, "label": self.label, "period": self.period, "status": self.status,
            "status_label": PRODUCT_STATUSES[self.status], "price_usd": self.price_usd, "price_xof": self.price_xof,
            "price_range_usd": list(self.price_range_usd) if self.price_range_usd else None, "alt_price": self.alt_price,
            "summary": self.summary, "audience": list(self.audience), "highlights": list(self.highlights),
            "entitlements": sorted(self.entitlements), "featured": self.featured, "page": self.page, "purchasable": self.purchasable,
        }


@dataclass(frozen=True)
class SiteConfig:
    brand: dict[str, Any]
    founders: list[dict[str, Any]]
    free: dict[str, Any]
    products: dict[str, Product]
    billing: dict[str, Any]
    payment_methods: list[dict[str, Any]]
    contact: dict[str, str]
    robots: list[dict[str, Any]]
    academy: dict[str, Any]
    ticker: list[str]

    @property
    def durations(self) -> list[int]:
        return [int(m) for m in self.billing.get("durations", [1])]

    @property
    def month_days(self) -> int:
        return int(self.billing.get("month_days", 30))

    @property
    def free_entitlements(self) -> frozenset[str]:
        return frozenset(self.free.get("entitlements", []))

    def price(self, product: str, months: int) -> int:
        """Amount due in XOF: the monthly price x months (with any free months), or the one-time price."""
        p = self.products[product]
        if p.period == "once":
            return int(p.price_xof or 0)
        free = int(self.billing.get("free_months", {}).get(months, 0))
        return int(p.price_xof or 0) * max(1, months - free)

    def public(self) -> dict[str, Any]:
        wave = self.billing.get("wave", {}) or {}
        whatsapp = "".join(ch for ch in self.contact.get("whatsapp", "") if ch.isdigit())
        return {
            "brand": self.brand,
            "founders": self.founders,
            "free": {"label": self.free.get("label", "Compte gratuit"), "summary": self.free.get("summary", ""), "entitlements": sorted(self.free_entitlements)},
            "products": [p.public() for p in self.products.values()],
            "categories": CATEGORIES,
            "billing": {
                "currency": "XOF",
                "usd_xof": self.billing.get("usd_xof"),
                "durations": [{"months": m, "free_months": int(self.billing.get("free_months", {}).get(m, 0))} for m in self.durations],
                "wave_manual": bool(wave.get("manual_number") or wave.get("manual_link")),
            },
            "payment_methods": self.payment_methods,
            "contact": {"whatsapp": whatsapp, "whatsapp_display": self.contact.get("whatsapp", ""), "email": self.contact.get("email", "")},
            "academy": {"planned": self.academy.get("planned", [])},
            "entitlements": ENTITLEMENTS,
        }


def _xof(usd: float | None, raw: Any, rate: float, step: int) -> int | None:
    if raw is not None:
        return int(raw)
    if usd is None or not rate:
        return None
    return int(round(usd * rate / step) * step)


def _highlight(h: Any) -> dict[str, Any]:
    if isinstance(h, str):
        return {"text": h, "soon": False}
    return {"text": str(h.get("text", "")), "soon": bool(h.get("soon", False))}


def load_site(path: str | Path | None = None) -> SiteConfig:
    p = Path(path or os.environ.get("LF_SITE_CONFIG") or REPO_ROOT / "config" / "site.yaml")
    raw = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    billing = raw.get("billing") or {}
    rate = float(billing.get("usd_xof", 0) or 0)
    step = int(billing.get("round_xof", 1000) or 1)
    products: dict[str, Product] = {}
    for key, o in (raw.get("products") or {}).items():
        if key == FREE_OFFER:
            raise SiteConfigError(f"« {FREE_OFFER} » est réservé au compte gratuit")
        ents = frozenset(o.get("entitlements", []))
        unknown = ents - set(ENTITLEMENTS)
        if unknown:
            raise SiteConfigError(f"produit {key} : droits inconnus {sorted(unknown)}")
        cat, period, status = o.get("category"), o.get("period", "month"), o.get("status", "available")
        if cat not in CATEGORIES or period not in PERIODS or status not in PRODUCT_STATUSES:
            raise SiteConfigError(f"produit {key} : catégorie, période ou statut inconnu")
        usd = o.get("price_usd")
        rng = o.get("price_range_usd")
        xof = _xof(float(usd) if usd is not None else None, o.get("price_xof"), rate, step)
        if xof is not None and xof < 0:
            raise SiteConfigError(f"produit {key} : prix négatif")
        if status == "available" and not xof:
            raise SiteConfigError(f"produit {key} : un produit disponible doit avoir un prix fixe (price_usd ou price_xof)")
        products[key] = Product(
            key=key, category=cat, label=str(o.get("label", key)), period=period, status=status,
            price_usd=float(usd) if usd is not None else None, price_xof=xof,
            price_range_usd=(float(rng[0]), float(rng[1])) if rng else None, alt_price=str(o.get("alt_price", "")),
            summary=str(o.get("summary", "")), audience=tuple(o.get("audience", [])),
            highlights=tuple(_highlight(h) for h in o.get("highlights", [])), entitlements=ents,
            featured=bool(o.get("featured", False)), page=str(o.get("page", "")),
        )
    free = dict(raw.get("free") or {})
    if set(free.get("entitlements", [])) - set(ENTITLEMENTS):
        raise SiteConfigError("compte gratuit : droits inconnus")
    for m in billing.get("durations", [1]):
        if not 1 <= int(m) <= 24:
            raise SiteConfigError("billing.durations : entre 1 et 24 mois")
    robots = list(raw.get("robots") or [])
    for r in robots:
        if r.get("status") not in ROBOT_STATUSES:
            raise SiteConfigError(f"robot {r.get('key')} : statut inconnu {r.get('status')}")
        if r.get("access") and r["access"] not in ENTITLEMENTS:
            raise SiteConfigError(f"robot {r.get('key')} : droit inconnu {r['access']}")
    return SiteConfig(
        brand=dict(raw.get("brand") or {}),
        founders=list(raw.get("founders") or []),
        free=free,
        products=products,
        billing=billing,
        payment_methods=list(raw.get("payment_methods") or []),
        contact={k: str(v or "") for k, v in (raw.get("contact") or {}).items()},
        robots=robots,
        academy=dict(raw.get("academy") or {}),
        ticker=[str(s) for s in raw.get("ticker") or []],
    )


def _flag(name: str, default: str = "0") -> bool:
    return os.environ.get(name, default).strip().lower() in ("1", "true", "yes", "on")


@dataclass(frozen=True)
class MemberSettings:
    public_url: str = ""  # https://votredomaine.com, used for Wave redirects
    wave_api_key: str = ""
    wave_webhook_secret: str = ""
    wave_api_base: str = "https://api.wave.com"
    registration_open: bool = True
    copytrading: str = "demo"  # off | demo | live
    media_hosts: tuple[str, ...] = field(default_factory=tuple)
    telegram_url: str = ""  # private invite links: environment or admin settings, never the repository
    discord_url: str = ""

    @classmethod
    def from_env(cls) -> "MemberSettings":
        copy = os.environ.get("LF_COPYTRADING", "demo").strip().lower()
        if copy not in ("off", "demo", "live"):
            copy = "demo"
        if copy == "live" and not _flag("LF_COPYTRADING_LEGAL_OK"):
            copy = "demo"  # live copy needs the legal green light to be recorded explicitly
        return cls(
            public_url=os.environ.get("LF_PUBLIC_URL", "").strip().rstrip("/"),
            wave_api_key=os.environ.get("LF_WAVE_API_KEY", "").strip(),
            wave_webhook_secret=os.environ.get("LF_WAVE_WEBHOOK_SECRET", "").strip(),
            wave_api_base=os.environ.get("LF_WAVE_API_BASE", "https://api.wave.com").strip().rstrip("/"),
            registration_open=_flag("LF_REGISTRATION", "1"),
            copytrading=copy,
            media_hosts=tuple(h.strip().lower() for h in os.environ.get("LF_MEDIA_HOSTS", "").split(",") if h.strip()),
            telegram_url=os.environ.get("LF_TELEGRAM_URL", "").strip(),
            discord_url=os.environ.get("LF_DISCORD_URL", "").strip(),
        )

    @property
    def wave_api_enabled(self) -> bool:
        # Wave only redirects to https pages, and a webhook needs a public address.
        return bool(self.wave_api_key) and self.public_url.startswith("https://")

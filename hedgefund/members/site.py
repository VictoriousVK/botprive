"""Public site content (config/site.yaml) and server settings (environment variables)."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

from hedgefund.config import REPO_ROOT

ENTITLEMENTS = {
    "academy_free": "Cours gratuits",
    "academy_member": "Académie (membres)",
    "academy_advanced": "Modules avancés",
    "analyses": "Analyses de marché",
    "community_private": "Groupes privés",
    "robots": "Licence de robot",
    "robots_all": "Tous les robots",
    "early_access": "Accès anticipé",
    "copy_demo": "Copytrading (démo)",
    "copy_live": "Copytrading (réel, après ouverture)",
    "lab": "Laboratoire de backtest",
    "coaching": "Session mensuelle avec les cofondateurs",
}
FREE_OFFER = "decouverte"
ROBOT_STATUSES = {"beta": "Disponible en bêta", "available": "Disponible", "development": "En développement", "retired": "Retiré"}


class SiteConfigError(ValueError):
    pass


@dataclass(frozen=True)
class Offer:
    key: str
    label: str
    price_xof: int
    summary: str
    highlights: tuple[str, ...]
    entitlements: frozenset[str]
    featured: bool = False

    def public(self) -> dict[str, Any]:
        return {"key": self.key, "label": self.label, "price_xof": self.price_xof, "summary": self.summary, "highlights": list(self.highlights), "entitlements": sorted(self.entitlements), "featured": self.featured}


@dataclass(frozen=True)
class SiteConfig:
    brand: dict[str, Any]
    founders: list[dict[str, Any]]
    offers: dict[str, Offer]
    billing: dict[str, Any]
    robots: list[dict[str, Any]]
    academy: dict[str, Any]
    community: dict[str, str]
    ticker: list[str]

    @property
    def durations(self) -> list[int]:
        return [int(m) for m in self.billing.get("durations", [1])]

    def price(self, offer: str, months: int) -> int:
        """Amount due in XOF for `months` of `offer` (annual plans get free months)."""
        free = int(self.billing.get("free_months", {}).get(months, 0))
        return self.offers[offer].price_xof * max(1, months - free)

    @property
    def month_days(self) -> int:
        return int(self.billing.get("month_days", 30))

    def public(self) -> dict[str, Any]:
        wave = self.billing.get("wave", {}) or {}
        return {
            "brand": self.brand,
            "founders": self.founders,
            "offers": [o.public() for o in self.offers.values()],
            "billing": {
                "currency": self.billing.get("currency", "XOF"),
                "durations": [{"months": m, "free_months": int(self.billing.get("free_months", {}).get(m, 0))} for m in self.durations],
                "wave_manual": bool(wave.get("manual_number") or wave.get("manual_link")),
            },
            "academy": {"planned": self.academy.get("planned", [])},
            "community": {k: bool(v) for k, v in self.community.items()},
            "entitlements": ENTITLEMENTS,
        }


def load_site(path: str | Path | None = None) -> SiteConfig:
    p = Path(path or os.environ.get("LF_SITE_CONFIG") or REPO_ROOT / "config" / "site.yaml")
    raw = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    offers: dict[str, Offer] = {}
    for key, o in (raw.get("offers") or {}).items():
        ents = frozenset(o.get("entitlements", []))
        unknown = ents - set(ENTITLEMENTS)
        if unknown:
            raise SiteConfigError(f"offre {key} : droits inconnus {sorted(unknown)}")
        price = int(o.get("price_xof", 0))
        if price < 0:
            raise SiteConfigError(f"offre {key} : prix négatif")
        offers[key] = Offer(key, str(o.get("label", key)), price, str(o.get("summary", "")), tuple(o.get("highlights", [])), ents, bool(o.get("featured", False)))
    if FREE_OFFER not in offers or offers[FREE_OFFER].price_xof != 0:
        raise SiteConfigError(f"l'offre gratuite « {FREE_OFFER} » est obligatoire (prix 0)")
    billing = raw.get("billing") or {}
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
        offers=offers,
        billing=billing,
        robots=robots,
        academy=dict(raw.get("academy") or {}),
        community={k: str(v or "") for k, v in (raw.get("community") or {}).items()},
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
        )

    @property
    def wave_api_enabled(self) -> bool:
        # Wave only redirects to https pages, and a webhook needs a public address.
        return bool(self.wave_api_key) and self.public_url.startswith("https://")

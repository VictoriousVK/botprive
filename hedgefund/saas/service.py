"""The SaaS container: database, queue, worker, model layer, tools, prompts, manifest, market
data, access rights and quotas. Feature modules (journal, coach, analyst…) plug into it."""

from __future__ import annotations

import logging
import os
import threading
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

import yaml

from hedgefund.saas.db import Database, default_url, ensure_personal_tenant, usage
from hedgefund.saas.harness import VersionManifest, build_manifest, store_manifest
from hedgefund.saas.jobs import JobQueue, Worker
from hedgefund.saas.llm import LLM, ModelRegistry, make_llm
from hedgefund.saas.tools import ToolRegistry

log = logging.getLogger("hedgefund.saas")
ROOT = Path(__file__).resolve().parents[2]
PROMPTS = Path(__file__).parent / "prompts"
INTERVALS = {"M1": "1m", "M5": "5m", "M15": "15m", "H1": "1h", "H4": "4h", "D1": "1d"}


class AccessDenied(PermissionError):
    pass


class QuotaExceeded(PermissionError):
    pass


def month_key(ts_ms: int | None = None) -> str:
    return datetime.fromtimestamp((ts_ms or time.time() * 1000) / 1000, tz=timezone.utc).strftime("%Y-%m")


def load_saas_config(path: Path | None = None) -> dict[str, Any]:
    return yaml.safe_load((path or ROOT / "config" / "saas.yaml").read_text(encoding="utf-8"))


def load_prompts() -> dict[str, str]:
    return {p.stem: p.read_text(encoding="utf-8") for p in sorted(PROMPTS.glob("*.md"))}


@dataclass(frozen=True)
class Access:
    """Who is asking, in which tenant, with which rights. Built by the API from the session."""

    member_id: int
    tenant_id: str
    plan: str
    entitlements: frozenset[str]
    name: str = ""
    features: dict[str, str] = field(default_factory=dict)  # feature -> entitlement

    def can(self, feature: str) -> bool:
        need = self.features.get(feature)
        return need is None or need in self.entitlements

    def require(self, feature: str, label: str = "") -> None:
        if not self.can(feature):
            raise AccessDenied(f"« {label or feature} » n'est pas inclus dans votre offre")


class MarketData:
    """Bars and symbol specifications from the platform feed (the MT5 terminal of the server,
    or the simulation), with a short cache. Point-in-time: only bars closed at ``now``."""

    def __init__(self, feed: Any, clock: Callable[[], int] | None = None, ttl_s: float = 20.0):
        self.feed = feed
        self.clock = clock or (lambda: int(time.time() * 1000))
        self.ttl_s = ttl_s
        self._cache: dict[tuple, tuple[float, Any]] = {}
        self._lock = threading.Lock()

    @property
    def synthetic(self) -> bool:
        return bool(getattr(self.feed, "synthetic", False))

    @property
    def source(self) -> str:
        return getattr(self.feed, "name", "?")

    def now(self) -> int:
        return self.clock()

    def specs(self) -> dict[str, Any]:
        return self.feed.specs()

    def symbols(self) -> list[str]:
        return sorted(self.specs())

    def data(self, symbol: str, base: str, aux: dict[str, int], count: int, now: int | None = None):
        """MarketData for ``symbol`` on ``base`` with the other timeframes in ``aux`` (name ->
        bar count), all as of ``now``."""
        now = now or self.now()
        key = (symbol, base, tuple(sorted(aux.items())), count, now // 10_000)
        with self._lock:
            hit = self._cache.get(key)
            if hit and time.monotonic() - hit[0] < self.ttl_s:
                return hit[1]
        md = self.feed.market_data([symbol], INTERVALS.get(base, base), count, now)
        for tf, n in aux.items():
            md.aux[INTERVALS.get(tf, tf)] = self.feed.market_data([symbol], INTERVALS.get(tf, tf), n, now)
        with self._lock:
            if len(self._cache) > 256:
                self._cache.clear()
            self._cache[key] = (time.monotonic(), md)
        return md


@dataclass
class SaaSSettings:
    db_url: str = ""
    worker_threads: int = 2
    jobs_secret: str = ""  # n8n and other schedulers call /api/jobs/* with this secret
    public_url: str = ""
    telegram_bot_token: str = ""
    telegram_bot_name: str = ""

    @classmethod
    def from_env(cls, data_dir: str | Path | None = None, cfg: dict[str, Any] | None = None) -> "SaaSSettings":
        cfg = cfg or {}
        return cls(
            db_url=default_url(data_dir),
            worker_threads=int(os.environ.get("HF_SAAS_WORKERS", str(cfg.get("workers", {}).get("threads", 2)))),
            jobs_secret=os.environ.get("HF_JOBS_SECRET", "").strip(),
            public_url=os.environ.get("HF_PUBLIC_URL", "").strip().rstrip("/"),
            telegram_bot_token=os.environ.get("HF_TELEGRAM_BOT_TOKEN", "").strip(),
            telegram_bot_name=os.environ.get("HF_TELEGRAM_BOT_NAME", "").strip(),
        )


class SaaS:
    def __init__(self, db: Database, settings: SaaSSettings | None = None, llm: LLM | None = None, models: ModelRegistry | None = None,
                 market: MarketData | None = None, config: dict[str, Any] | None = None):
        self.db = db
        self.config = config or load_saas_config()
        self.settings = settings or SaaSSettings()
        self.llm = llm if llm is not None else make_llm()
        self.models = models or ModelRegistry.load()
        self.market = market
        self.queue = JobQueue(db)
        self.tools = ToolRegistry()
        self.handlers: dict[str, Callable[[dict[str, Any]], dict[str, Any] | None]] = {}
        self.prompts = load_prompts()
        self.features = {k: v["entitlement"] for k, v in self.config.get("features", {}).items()}
        self.modules: dict[str, Any] = {}
        self.worker: Worker | None = None
        self.manifest: VersionManifest = self._manifest()
        db.create_all()
        store_manifest(db, self.manifest)

    def _manifest(self) -> VersionManifest:
        return build_manifest(self.models.ids(), self.prompts, {"plans": self.config.get("plans", {}), "journal": self.config.get("journal", {}), "analysis": self.config.get("analysis", {})})

    def refresh_manifest(self) -> None:
        """Called after modules registered their prompts/config."""
        self.prompts = load_prompts()
        self.manifest = self._manifest()
        store_manifest(self.db, self.manifest)

    # ---- access ----
    def access(self, member: dict[str, Any], plan: str, entitlements: set[str] | frozenset[str]) -> Access:
        tid = ensure_personal_tenant(self.db, member["id"], member.get("name", ""))
        plan = plan if plan in self.config.get("plans", {}) else "gratuit"
        return Access(int(member["id"]), tid, plan, frozenset(entitlements), member.get("name", ""), self.features)

    def limits(self, plan: str) -> dict[str, int]:
        plans = self.config.get("plans", {})
        return dict(plans.get(plan) or plans.get("gratuit") or {})

    def usage_of(self, acc: Access, month: str | None = None) -> dict[str, dict[str, float]]:
        with self.db.tenant(acc.tenant_id) as s:
            rows = s.select(usage, {"month": month or month_key()})
        return {r["key"]: {"count": r["count"], "cost_usd": r["cost_usd"]} for r in rows}

    def consume(self, acc: Access, key: str, cost_usd: float = 0.0, n: int = 1) -> None:
        """Checks and counts one use of ``key`` against the member's monthly cap (0 = none left)."""
        cap = self.limits(acc.plan).get(key)
        month = month_key()
        with self.db.tenant(acc.tenant_id) as s:
            row = s.one(usage, {"month": month, "key": key})
            used = row["count"] if row else 0
            if cap is not None and used + n > cap:
                raise QuotaExceeded(f"plafond mensuel atteint pour « {key} » ({cap} par mois avec votre offre)")
            s.upsert(usage, {"month": month, "key": key}, {"count": used + n, "cost_usd": (row["cost_usd"] if row else 0.0) + cost_usd})

    def add_cost(self, acc_tenant: str, key: str, cost_usd: float) -> None:
        month = month_key()
        with self.db.tenant(acc_tenant) as s:
            row = s.one(usage, {"month": month, "key": key})
            s.upsert(usage, {"month": month, "key": key}, {"count": row["count"] if row else 0, "cost_usd": (row["cost_usd"] if row else 0.0) + cost_usd})

    # ---- worker ----
    def start(self, threads: int | None = None) -> None:
        n = self.settings.worker_threads if threads is None else threads
        if n > 0 and self.worker is None:
            self.worker = Worker(self.queue, self.handlers)
            self.worker.start(n)

    def shutdown(self) -> None:
        if self.worker is not None:
            self.worker.shutdown()
            self.worker = None


def build_saas(feed: Any = None, clock: Callable[[], int] | None = None, data_dir: str | Path | None = None, db_url: str | None = None, llm: LLM | None = None) -> SaaS:
    """Production wiring: database from HF_SAAS_DB (SQLite under the data dir by default)."""
    cfg = load_saas_config()
    settings = SaaSSettings.from_env(data_dir, cfg)
    if db_url:
        settings.db_url = db_url
    db = Database(settings.db_url)
    saas = SaaS(db, settings, llm=llm, market=MarketData(feed, clock) if feed is not None else None, config=cfg)
    from hedgefund.saas.modules import install_all

    install_all(saas)
    return saas

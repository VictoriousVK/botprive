"""SaaS database: SQLAlchemy Core tables, tenant scoping and PostgreSQL row-level security.

Two backends, same code:
  * PostgreSQL in production (``HF_SAAS_DB=postgresql+psycopg://…``). Every tenant table gets a
    row-level security policy (FORCE, so the table owner is subject to it too); each transaction
    sets ``app.tenant_id``, so a query that forgets its tenant filter still sees nothing else.
  * SQLite for a single machine (the Windows VPS) and for tests (``sqlite:///var/saas.db``).
    There is no RLS: isolation rests on ``Scoped``, which adds the tenant to every statement.

Every timestamp is UTC epoch milliseconds, like the rest of the platform.
"""

from __future__ import annotations

import os
import secrets
import threading
import time
from collections.abc import Iterator, Mapping
from contextlib import contextmanager
from pathlib import Path
from typing import Any

from sqlalchemy import (
    JSON,
    BigInteger,
    Boolean,
    Column,
    Float,
    Index,
    Integer,
    MetaData,
    String,
    Table,
    Text,
    UniqueConstraint,
    and_,
    create_engine,
    event,
    func,
    insert,
    select,
    text,
    update,
)
from sqlalchemy import delete as sa_delete
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.engine import Connection, Engine
from sqlalchemy.pool import StaticPool

metadata = MetaData()
Json = JSON().with_variant(JSONB(), "postgresql")
TENANT_TABLES: list[str] = []  # filled by _tenant_table(): the tables under row-level security


def now_ms() -> int:
    return int(time.time() * 1000)


def new_id(prefix: str) -> str:
    return f"{prefix}_{secrets.token_hex(8)}"


def _tenant_table(name: str, *cols: Any, tenant_pk: bool = False, **kw: Any) -> Table:
    """A table under tenant isolation; ``tenant_pk`` puts tenant_id in a composite primary key."""
    TENANT_TABLES.append(name)
    return Table(name, metadata, Column("tenant_id", String(40), nullable=False, index=True, primary_key=tenant_pk), *cols, **kw)


# ---------------------------------------------------------------- tenants and access
tenants = Table(
    "tenants", metadata,
    Column("id", String(40), primary_key=True),
    Column("kind", String(12), nullable=False),  # personal | team
    Column("name", String(120), nullable=False),
    Column("owner_member_id", Integer, nullable=False),
    Column("created_at", BigInteger, nullable=False),
)
tenant_members = Table(
    "tenant_members", metadata,
    Column("tenant_id", String(40), primary_key=True),
    Column("member_id", Integer, primary_key=True),
    Column("role", String(12), nullable=False),  # owner | member
    Column("created_at", BigInteger, nullable=False),
    Index("idx_tenant_members_member", "member_id"),
)
api_tokens = _tenant_table(
    "api_tokens",
    Column("id", String(40), primary_key=True),
    Column("user_id", Integer, nullable=False),
    Column("kind", String(16), nullable=False),  # ea_sync | tradingview | public_api
    Column("label", String(80), nullable=False),
    Column("token_hash", String(64), nullable=False, unique=True),
    Column("account_id", String(40)),
    Column("scopes", Json, nullable=False),
    Column("created_at", BigInteger, nullable=False),
    Column("last_used_at", BigInteger),
    Column("revoked_at", BigInteger),
)

# ---------------------------------------------------------------- journal
broker_accounts = _tenant_table(
    "broker_accounts",
    Column("id", String(40), primary_key=True),
    Column("user_id", Integer, nullable=False),
    Column("label", String(80), nullable=False),
    Column("broker", String(80), nullable=False, default=""),
    Column("server", String(120), nullable=False, default=""),
    Column("login", String(40), nullable=False, default=""),
    Column("kind", String(12), nullable=False, default="demo"),  # demo | real | prop
    Column("access_mode", String(12), nullable=False, default="csv"),  # csv | sync_ea | investor
    Column("secret_enc", Text),  # investor password, encrypted; never shown to a model
    Column("server_utc_offset_min", Integer),  # measured by the EA; None = rule below
    Column("server_winter_offset_h", Integer, nullable=False, default=2),
    Column("server_dst_rule", String(4), nullable=False, default="us"),  # us | eu | none
    Column("currency", String(8), nullable=False, default="USD"),
    Column("starting_balance", Float),
    Column("prop_profile", String(60)),
    Column("last_sync_at", BigInteger),
    Column("created_at", BigInteger, nullable=False),
    Column("archived", Boolean, nullable=False, default=False),
)
trades = _tenant_table(
    "trades",
    Column("id", String(40), primary_key=True),
    Column("user_id", Integer, nullable=False),
    Column("account_id", String(40), nullable=False),
    Column("position_id", String(40), nullable=False),
    Column("symbol_raw", String(40), nullable=False),
    Column("symbol", String(20), nullable=False),
    Column("side", String(5), nullable=False),  # long | short
    Column("volume", Float, nullable=False),
    Column("open_utc", BigInteger, nullable=False),
    Column("close_utc", BigInteger),
    Column("open_price", Float, nullable=False),
    Column("close_price", Float),
    Column("sl", Float),
    Column("tp", Float),
    Column("commission", Float, nullable=False, default=0.0),
    Column("swap", Float, nullable=False, default=0.0),
    Column("profit", Float, nullable=False, default=0.0),  # gross, account currency
    Column("net", Float, nullable=False, default=0.0),  # profit + commission + swap
    Column("risk_amount", Float),
    Column("r_multiple", Float),
    Column("r_source", String(8), nullable=False, default="none"),  # sl | plan | none
    Column("session", String(12)),
    Column("killzone", String(12)),
    Column("macro", String(20)),
    Column("weekday", Integer),
    Column("setup_model", String(30)),
    Column("plan_respected", Boolean),
    Column("magic", BigInteger),
    Column("comment", String(120)),
    Column("source", String(12), nullable=False),  # csv | mt5_report | sync_ea | investor | manual
    Column("import_job_id", String(40)),
    Column("enrichment_version", String(20)),
    Column("imported_at", BigInteger, nullable=False),
    UniqueConstraint("tenant_id", "account_id", "position_id", name="uq_trade_position"),
    Index("idx_trades_user_time", "tenant_id", "user_id", "open_utc"),
)
executions = _tenant_table(
    "executions",
    Column("id", String(40), primary_key=True),
    Column("account_id", String(40), nullable=False),
    Column("position_id", String(40), nullable=False),
    Column("deal_id", String(40), nullable=False),
    Column("time_utc", BigInteger, nullable=False),
    Column("entry", String(5), nullable=False),  # in | out | inout
    Column("side", String(5), nullable=False),
    Column("price", Float, nullable=False),
    Column("volume", Float, nullable=False),
    Column("profit", Float, nullable=False, default=0.0),
    Column("commission", Float, nullable=False, default=0.0),
    Column("swap", Float, nullable=False, default=0.0),
    Column("sl", Float),
    Column("tp", Float),
    UniqueConstraint("tenant_id", "account_id", "deal_id", name="uq_execution_deal"),
)
journal_entries = _tenant_table(
    "journal_entries",
    Column("trade_id", String(40), primary_key=True),
    Column("user_id", Integer, nullable=False),
    Column("setup_model", String(30)),
    Column("emotion_before", String(20)),  # declared by the trader, closed vocabulary
    Column("emotion_after", String(20)),
    Column("followed_plan", Boolean),
    Column("mistakes", Json, nullable=False),
    Column("notes", Text, nullable=False, default=""),
    Column("rating", Integer),
    Column("updated_at", BigInteger, nullable=False),
    Column("field_times", Json),  # per-field update times for offline sync (GMI Journal)
)
trading_plans = _tenant_table(
    "trading_plans",
    Column("user_id", Integer, primary_key=True),
    Column("body", Json, nullable=False),
    Column("updated_at", BigInteger, nullable=False),
    tenant_pk=True,
)
user_profiles = _tenant_table(
    "user_profiles",
    Column("user_id", Integer, primary_key=True),
    Column("body", Json, nullable=False),
    Column("updated_at", BigInteger, nullable=False),
    tenant_pk=True,
)
account_snapshots = _tenant_table(
    "account_snapshots",
    Column("id", String(40), primary_key=True),
    Column("account_id", String(40), nullable=False),
    Column("time_utc", BigInteger, nullable=False),
    Column("balance", Float, nullable=False),
    Column("equity", Float, nullable=False),
    Column("margin", Float),
    Column("source", String(12), nullable=False),
    Index("idx_snapshots_account_time", "tenant_id", "account_id", "time_utc"),
)
import_jobs = _tenant_table(
    "import_jobs",
    Column("id", String(40), primary_key=True),
    Column("user_id", Integer, nullable=False),
    Column("account_id", String(40), nullable=False),
    Column("source", String(12), nullable=False),
    Column("status", String(12), nullable=False),  # done | failed
    Column("stats", Json, nullable=False),
    Column("error", Text),
    Column("created_at", BigInteger, nullable=False),
)

# ---------------------------------------------------------------- memory and lessons
lessons = _tenant_table(
    "lessons",
    Column("id", String(40), primary_key=True),
    Column("user_id", Integer, nullable=False),
    Column("text", String(400), nullable=False),
    Column("behavior", String(30), nullable=False),
    Column("status", String(10), nullable=False),  # proposed | accepted | edited | rejected | retired
    Column("source_trace_ids", Json, nullable=False),
    Column("source_trade_ids", Json, nullable=False),
    Column("strength", Float, nullable=False, default=1.0),
    Column("created_at", BigInteger, nullable=False),
    Column("decided_at", BigInteger),
    Column("last_reinforced_at", BigInteger),
)
memories_episodic = _tenant_table(
    "memories_episodic",
    Column("id", String(40), primary_key=True),
    Column("user_id", Integer, nullable=False),
    Column("period", String(20), nullable=False),  # e.g. 2026-W40
    Column("summary", Text, nullable=False),
    Column("trajectory", Text, nullable=False),
    Column("what_worked", Text, nullable=False),
    Column("what_didnt_work", Text, nullable=False),
    Column("key_points", Json, nullable=False),
    Column("strength", Float, nullable=False, default=1.0),
    Column("created_at", BigInteger, nullable=False),
    UniqueConstraint("tenant_id", "user_id", "period", name="uq_episode_period"),
)

# ---------------------------------------------------------------- analyses, runs, audit
setup_analyses = _tenant_table(
    "setup_analyses",
    Column("id", String(40), primary_key=True),  # = trace_id
    Column("user_id", Integer, nullable=False),
    Column("symbol", String(20), nullable=False),
    Column("as_of", BigInteger, nullable=False),
    Column("source", String(12), nullable=False),  # user | tradingview
    Column("label", String(30), nullable=False),
    Column("body", Json, nullable=False),
    Column("decision", String(12)),  # approved | rejected | expired
    Column("decided_at", BigInteger),
    Column("expires_at", BigInteger),
    Column("created_at", BigInteger, nullable=False),
)
agent_runs = _tenant_table(
    "agent_runs",
    Column("id", String(40), primary_key=True),  # trace_id
    Column("user_id", Integer),
    Column("graph", String(20), nullable=False),
    Column("status", String(12), nullable=False),  # queued | running | waiting | done | failed
    Column("input", Json, nullable=False),
    Column("output", Json),
    Column("manifest", String(40)),
    Column("cost_usd", Float, nullable=False, default=0.0),
    Column("tokens_in", Integer, nullable=False, default=0),
    Column("tokens_out", Integer, nullable=False, default=0),
    Column("llm_calls", Integer, nullable=False, default=0),
    Column("error", Text),
    Column("created_at", BigInteger, nullable=False),
    Column("updated_at", BigInteger, nullable=False),
    Index("idx_runs_user_time", "tenant_id", "user_id", "created_at"),
)
spans = _tenant_table(
    "spans",
    Column("id", String(40), primary_key=True),
    Column("trace_id", String(40), nullable=False, index=True),
    Column("parent_id", String(40)),
    Column("name", String(80), nullable=False),
    Column("kind", String(12), nullable=False),  # node | llm | tool | guardrail | step
    Column("status", String(8), nullable=False),  # ok | error | skipped
    Column("started_ms", BigInteger, nullable=False),
    Column("ended_ms", BigInteger),
    Column("attrs", Json, nullable=False),
)
audit_records = _tenant_table(
    "audit_records",
    Column("trace_id", String(40), primary_key=True),
    Column("seq", Integer, nullable=False),
    Column("body", Json, nullable=False),
    Column("prev_hash", String(64), nullable=False),
    Column("hash", String(64), nullable=False),
    Column("created_at", BigInteger, nullable=False),
    UniqueConstraint("tenant_id", "seq", name="uq_audit_seq"),
)
usage = _tenant_table(
    "usage",
    Column("month", String(7), primary_key=True),  # 2026-10
    Column("key", String(30), primary_key=True),  # coach | analysis | mentor | backtest | ea_run
    Column("count", Integer, nullable=False, default=0),
    Column("cost_usd", Float, nullable=False, default=0.0),
    tenant_pk=True,
)
tv_hooks = _tenant_table(
    "tv_hooks",
    Column("id", String(40), primary_key=True),
    Column("user_id", Integer, nullable=False),
    Column("token_hash", String(64), nullable=False),
    Column("enabled", Boolean, nullable=False, default=True),
    Column("created_at", BigInteger, nullable=False),
)
tv_alerts_seen = _tenant_table(
    "tv_alerts_seen",
    Column("hook_id", String(40), primary_key=True),
    Column("alert_key", String(80), primary_key=True),
    Column("received_at", BigInteger, nullable=False),
    tenant_pk=True,
)
strategy_specs = _tenant_table(
    "strategy_specs",
    Column("id", String(40), primary_key=True),
    Column("user_id", Integer, nullable=False),
    Column("name", String(80), nullable=False),
    Column("version", Integer, nullable=False, default=1),
    Column("body", Json, nullable=False),
    Column("created_at", BigInteger, nullable=False),
)
lab_reports = _tenant_table(
    "lab_reports",
    Column("id", String(40), primary_key=True),
    Column("user_id", Integer, nullable=False),
    Column("kind", String(20), nullable=False),  # walk_forward | monte_carlo | look_ahead | demo_vs_real | ea_factory
    Column("title", String(160), nullable=False),
    Column("body", Json, nullable=False),
    Column("created_at", BigInteger, nullable=False),
)
notifications = _tenant_table(
    "notifications",
    Column("id", String(40), primary_key=True),
    Column("user_id", Integer, nullable=False),
    Column("kind", String(20), nullable=False),
    Column("title", String(160), nullable=False),
    Column("body", Text, nullable=False),
    Column("link", String(200)),
    Column("read_at", BigInteger),
    Column("created_at", BigInteger, nullable=False),
)
notify_channels = _tenant_table(
    "notify_channels",
    Column("user_id", Integer, primary_key=True),
    Column("kind", String(12), primary_key=True),  # telegram
    Column("address", String(80)),  # chat id, once linked
    Column("link_code", String(20)),
    Column("verified_at", BigInteger),
    Column("prefs", Json, nullable=False),
    tenant_pk=True,
)
ea_telemetry = _tenant_table(
    "ea_telemetry",
    Column("id", String(40), primary_key=True),
    Column("account_id", String(40), nullable=False),
    Column("ea", String(60), nullable=False),
    Column("magic", BigInteger),
    Column("time_utc", BigInteger, nullable=False),
    Column("status", String(12), nullable=False),  # running | stopped | error
    Column("spread_points", Float),
    Column("last_error", String(200)),
    Column("body", Json, nullable=False),
)

# ---------------------------------------------------------------- system tables (no tenant data)
jobs = Table(
    "jobs", metadata,
    Column("id", String(40), primary_key=True),
    Column("tenant_id", String(40)),
    Column("kind", String(30), nullable=False),
    Column("payload", Json, nullable=False),
    Column("status", String(10), nullable=False),  # queued | running | done | failed
    Column("priority", Integer, nullable=False, default=1),  # 0 interactive, 1 scheduled, 2 batch
    Column("idem_key", String(120), unique=True),
    Column("attempts", Integer, nullable=False, default=0),
    Column("max_attempts", Integer, nullable=False, default=3),
    Column("run_after", BigInteger, nullable=False),
    Column("locked_by", String(60)),
    Column("locked_at", BigInteger),
    Column("result", Json),
    Column("error", Text),
    Column("created_at", BigInteger, nullable=False),
    Column("updated_at", BigInteger, nullable=False),
    Index("idx_jobs_pick", "status", "priority", "run_after"),
)
version_manifests = Table(
    "version_manifests", metadata,
    Column("fingerprint", String(40), primary_key=True),
    Column("body", Json, nullable=False),
    Column("created_at", BigInteger, nullable=False),
)
knowledge_docs = Table(
    "knowledge_docs", metadata,
    Column("id", String(40), primary_key=True),
    Column("source", String(20), nullable=False),  # skill | course | faq | definition
    Column("title", String(200), nullable=False),
    Column("access", String(30), nullable=False),  # entitlement needed to read it
    Column("ref", String(200)),  # course slug / part id / skill path
    Column("version", String(40), nullable=False),
    Column("created_at", BigInteger, nullable=False),
)
knowledge_chunks = Table(
    "knowledge_chunks", metadata,
    Column("id", String(40), primary_key=True),
    Column("doc_id", String(40), nullable=False, index=True),
    Column("position", Integer, nullable=False),
    Column("text", Text, nullable=False),
    Column("timestamp_s", Integer),
    Column("tokens", Json, nullable=False),  # normalised terms for the lexical index
    Column("embedding", Json),  # optional vector (pgvector column added on PostgreSQL)
)
economic_events = Table(
    "economic_events", metadata,
    Column("id", String(40), primary_key=True),
    Column("time_utc", BigInteger, nullable=False, index=True),
    Column("currency", String(8), nullable=False),
    Column("title", String(200), nullable=False),
    Column("impact", String(8), nullable=False),  # high | medium | low
    Column("source", String(60), nullable=False),
    Column("as_of", BigInteger, nullable=False),
)
news_items = Table(
    "news_items", metadata,
    Column("id", String(40), primary_key=True),
    Column("time_utc", BigInteger, nullable=False, index=True),
    Column("publisher", String(80), nullable=False),
    Column("title", String(300), nullable=False),
    Column("url", String(500), nullable=False),
    Column("summary", Text, nullable=False, default=""),
    Column("symbols", Json, nullable=False),
    Column("hash", String(64), nullable=False, unique=True),
    Column("as_of", BigInteger, nullable=False),
)
briefings = Table(
    "briefings", metadata,
    Column("id", String(40), primary_key=True),
    Column("session", String(12), nullable=False),
    Column("as_of", BigInteger, nullable=False, index=True),
    Column("body", Json, nullable=False),
    Column("created_at", BigInteger, nullable=False),
)
ict_annotations = Table(
    "ict_annotations", metadata,
    Column("id", String(40), primary_key=True),
    Column("dataset", String(40), nullable=False),  # golden-v1, synthetic-v1…
    Column("symbol", String(20), nullable=False),
    Column("timeframe", String(4), nullable=False),
    Column("as_of", BigInteger, nullable=False),
    Column("bars", Json, nullable=False),  # the exact bars the annotator saw
    Column("labels", Json, nullable=False),  # {"fvg": […], "swings": […], "sweeps": […], "mss": […], "setup": …}
    Column("annotator", String(60), nullable=False),
    Column("rationale", Text, nullable=False, default=""),
    Column("split", String(10), nullable=False, default="dev"),  # dev | holdout
    Column("created_at", BigInteger, nullable=False),
)
eval_results = Table(
    "eval_results", metadata,
    Column("id", String(40), primary_key=True),
    Column("manifest", String(40), nullable=False),
    Column("suite", String(40), nullable=False),
    Column("body", Json, nullable=False),
    Column("passed", Boolean, nullable=False),
    Column("created_at", BigInteger, nullable=False),
)


# ---------------------------------------------------------------- database
class TenantError(PermissionError):
    pass


def default_url(data_dir: str | Path | None = None) -> str:
    url = os.environ.get("HF_SAAS_DB", "").strip()
    if url:
        return url
    base = Path(data_dir or os.environ.get("HF_DATA_DIR") or "var")
    base.mkdir(parents=True, exist_ok=True)
    return f"sqlite:///{(base / 'saas.db').as_posix()}"


class Database:
    def __init__(self, url: str = "sqlite://", echo: bool = False):
        self.url = url
        if url.startswith("sqlite"):
            memory = url in ("sqlite://", "sqlite:///:memory:")
            kw: dict[str, Any] = {"connect_args": {"check_same_thread": False}}
            if memory:
                kw["poolclass"] = StaticPool
            self.engine: Engine = create_engine(url, echo=echo, **kw)
            self._write_lock = threading.RLock()  # SQLite has one writer at a time

            @event.listens_for(self.engine, "connect")
            def _pragmas(dbapi_conn, _rec):  # noqa: ANN001
                cur = dbapi_conn.cursor()
                if not memory:
                    cur.execute("PRAGMA journal_mode=WAL")
                cur.execute("PRAGMA busy_timeout=5000")
                cur.execute("PRAGMA foreign_keys=ON")
                cur.close()
        else:
            self.engine = create_engine(url, echo=echo, pool_pre_ping=True, pool_size=10, max_overflow=10)
            self._write_lock = None

    @property
    def is_postgres(self) -> bool:
        return self.engine.dialect.name == "postgresql"

    # ---- schema ----
    def create_all(self) -> None:
        metadata.create_all(self.engine)
        if self.is_postgres:
            with self.engine.begin() as conn:
                for name in TENANT_TABLES:
                    conn.execute(text(f'ALTER TABLE "{name}" ENABLE ROW LEVEL SECURITY'))
                    conn.execute(text(f'ALTER TABLE "{name}" FORCE ROW LEVEL SECURITY'))
                    conn.execute(text(f'DROP POLICY IF EXISTS tenant_isolation ON "{name}"'))
                    cond = "tenant_id = current_setting('app.tenant_id', true) OR current_setting('app.role', true) = 'system'"
                    conn.execute(text(f'CREATE POLICY tenant_isolation ON "{name}" USING ({cond}) WITH CHECK ({cond})'))

    # ---- transactions ----
    @contextmanager
    def _begin(self) -> Iterator[Connection]:
        if self._write_lock is not None:
            with self._write_lock, self.engine.begin() as conn:
                yield conn
        else:
            with self.engine.begin() as conn:
                yield conn

    @contextmanager
    def tenant(self, tenant_id: str) -> Iterator["Scoped"]:
        """One transaction confined to ``tenant_id`` (in code, and by RLS on PostgreSQL)."""
        if not tenant_id or not isinstance(tenant_id, str):
            raise TenantError("tenant requis")
        with self._begin() as conn:
            if self.is_postgres:
                conn.execute(text("SELECT set_config('app.tenant_id', :t, true), set_config('app.role', 'tenant', true)"), {"t": tenant_id})
            yield Scoped(conn, tenant_id)

    @contextmanager
    def system(self) -> Iterator[Connection]:
        """Cross-tenant access for the platform itself (jobs, admin statistics, retention)."""
        with self._begin() as conn:
            if self.is_postgres:
                conn.execute(text("SELECT set_config('app.role', 'system', true)"))
            yield conn

    def dispose(self) -> None:
        self.engine.dispose()


class Scoped:
    """A connection bound to one tenant: every helper adds ``tenant_id`` itself."""

    def __init__(self, conn: Connection, tenant_id: str):
        self.conn, self.tenant_id = conn, tenant_id

    def _check(self, table: Table) -> None:
        if table.name not in TENANT_TABLES:
            raise TenantError(f"{table.name} n'est pas une table de tenant")

    def _where(self, table: Table, where: Mapping[str, Any] | None, *extra: Any):
        conds = [table.c.tenant_id == self.tenant_id]
        for k, v in (where or {}).items():
            conds.append(table.c[k].is_(None) if v is None else table.c[k] == v)
        conds.extend(extra)
        return and_(*conds)

    def insert(self, table: Table, values: Mapping[str, Any]) -> None:
        self._check(table)
        self.conn.execute(insert(table).values(**{**values, "tenant_id": self.tenant_id}))

    def insert_many(self, table: Table, rows: list[Mapping[str, Any]]) -> None:
        self._check(table)
        if rows:
            self.conn.execute(insert(table), [{**r, "tenant_id": self.tenant_id} for r in rows])

    def select(self, table: Table, where: Mapping[str, Any] | None = None, *extra: Any, order_by: Any = None, limit: int | None = None) -> list[dict[str, Any]]:
        self._check(table)
        q = select(table).where(self._where(table, where, *extra))
        if order_by is not None:
            q = q.order_by(*(order_by if isinstance(order_by, (list, tuple)) else [order_by]))
        if limit is not None:
            q = q.limit(limit)
        return [dict(r._mapping) for r in self.conn.execute(q)]

    def one(self, table: Table, where: Mapping[str, Any]) -> dict[str, Any] | None:
        rows = self.select(table, where, limit=1)
        return rows[0] if rows else None

    def count(self, table: Table, where: Mapping[str, Any] | None = None, *extra: Any) -> int:
        self._check(table)
        return int(self.conn.execute(select(func.count()).select_from(table).where(self._where(table, where, *extra))).scalar_one())

    def update(self, table: Table, where: Mapping[str, Any], values: Mapping[str, Any]) -> int:
        self._check(table)
        values = {k: v for k, v in values.items() if k != "tenant_id"}
        return self.conn.execute(update(table).where(self._where(table, where)).values(**values)).rowcount

    def delete(self, table: Table, where: Mapping[str, Any]) -> int:
        self._check(table)
        return self.conn.execute(sa_delete(table).where(self._where(table, where))).rowcount

    def upsert(self, table: Table, keys: Mapping[str, Any], values: Mapping[str, Any]) -> None:
        """Update the row identified by ``keys`` or insert it (portable, inside the transaction)."""
        if self.update(table, keys, values) == 0:
            self.insert(table, {**keys, **values})

    def execute(self, stmt: Any, params: Mapping[str, Any] | None = None):
        """Escape hatch for aggregate queries: the statement MUST filter on :tenant_id itself."""
        return self.conn.execute(stmt, {**(params or {}), "tenant_id": self.tenant_id})


def personal_tenant(member_id: int) -> str:
    return f"t_m{int(member_id)}"


def ensure_personal_tenant(db: Database, member_id: int, name: str) -> str:
    tid = personal_tenant(member_id)
    with db.system() as conn:
        if conn.execute(select(tenants.c.id).where(tenants.c.id == tid)).first() is None:
            ts = now_ms()
            conn.execute(insert(tenants).values(id=tid, kind="personal", name=name[:120] or tid, owner_member_id=int(member_id), created_at=ts))
            conn.execute(insert(tenant_members).values(tenant_id=tid, member_id=int(member_id), role="owner", created_at=ts))
    return tid


def tenants_of(db: Database, member_id: int) -> list[str]:
    with db.system() as conn:
        return [r.tenant_id for r in conn.execute(select(tenant_members.c.tenant_id).where(tenant_members.c.member_id == int(member_id)))]

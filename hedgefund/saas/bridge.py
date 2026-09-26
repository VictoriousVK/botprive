"""MT5 read-only bridge (fallback to the EA Journal Sync): logs in with the INVESTOR password,
reads the deal history and hands it to the journal. Runs on the Windows host that has the
MetaTrader5 package (``python -m hedgefund.saas bridge``).

The MetaTrader5 package drives one terminal logged into one account at a time, so accounts are
read one after the other. No function of this module can place, modify or close an order; a test
checks that no trading function is ever called.
"""

from __future__ import annotations

import logging
import time
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import and_, select

from hedgefund.saas import ingest as I
from hedgefund.saas.db import broker_accounts
from hedgefund.saas.vault import Vault

log = logging.getLogger("hedgefund.saas.bridge")
FORBIDDEN = ("order_send", "order_check", "Buy", "Sell", "position_close")


def _as_dict(obj: Any) -> dict[str, Any]:
    if isinstance(obj, dict):
        return obj
    if hasattr(obj, "_asdict"):
        return obj._asdict()
    return {k: getattr(obj, k) for k in dir(obj) if not k.startswith("_") and not callable(getattr(obj, k))}


class ReadOnlyMT5:
    """Wraps the MetaTrader5 module and exposes only reading functions."""

    ALLOWED = ("initialize", "shutdown", "login", "last_error", "account_info", "history_deals_get", "history_orders_get", "positions_get", "symbol_info_tick")

    def __init__(self, mt5: Any):
        self._mt5 = mt5

    def __getattr__(self, name: str) -> Any:
        if name not in self.ALLOWED:
            raise PermissionError(f"fonction MT5 interdite dans le pont en lecture seule : {name}")
        return getattr(self._mt5, name)


def read_account(mt5: Any, login: int, password: str, server: str, days: int = 90, terminal_path: str | None = None) -> dict[str, Any]:
    """One account: login, history, disconnect. Returns a SyncPayload-shaped dict."""
    m = ReadOnlyMT5(mt5)
    kw: dict[str, Any] = {"login": int(login), "password": password, "server": server, "timeout": 30_000}
    if terminal_path:
        kw["path"] = terminal_path
    if not m.initialize(**kw):
        raise ConnectionError(f"connexion MT5 impossible : {m.last_error()}")
    try:
        info = _as_dict(m.account_info())
        now = datetime.now(timezone.utc)
        deals = m.history_deals_get(now - timedelta(days=days), now + timedelta(days=1)) or ()
        orders = {int(_as_dict(o).get("ticket", 0)): _as_dict(o) for o in (m.history_orders_get(now - timedelta(days=days), now + timedelta(days=1)) or ())}
        rows = [_as_dict(d) for d in deals]
        meta = []
        for d in rows:
            if int(d.get("entry", -1)) == 0 and int(d.get("position_id", 0)):
                o = orders.get(int(d.get("order", 0)), {})
                meta.append({"position_id": int(d["position_id"]), "initial_sl": float(o.get("sl", 0) or 0), "initial_tp": float(o.get("tp", 0) or 0)})
        return {"account": info, "deals": rows, "positions": meta}
    finally:
        m.shutdown()


def run_once(saas: Any, mt5: Any, vault: Vault | None = None, plan_of: Any = None, sleep_s: float = 1.0) -> list[dict[str, Any]]:
    """Reads every account in investor mode, across tenants (system role), one at a time."""
    vault = vault or Vault()
    journal = saas.modules["journal"]
    with saas.db.system() as conn:
        accounts = [dict(r._mapping) for r in conn.execute(select(broker_accounts).where(and_(broker_accounts.c.access_mode == "investor", broker_accounts.c.archived.is_(False))))]
    report = []
    for a in accounts:
        try:
            if not a.get("secret_enc"):
                raise ValueError("mot de passe investisseur absent")
            data = read_account(mt5, int(a["login"]), vault.decrypt(a["secret_enc"]), a["server"])
            raws = I.trades_from_deals(data["deals"], {str(p["position_id"]): {"initial_sl": p["initial_sl"] or None, "tp": p["initial_tp"] or None} for p in data["positions"]})
            plan_key = plan_of(a["user_id"]) if plan_of else "gratuit"
            stats = journal.import_raw(a["tenant_id"], a["user_id"], plan_key, a["id"], raws, "investor")
            with saas.db.tenant(a["tenant_id"]) as s:
                s.update(broker_accounts, {"id": a["id"]}, {"last_sync_at": int(time.time() * 1000)})
            report.append({"account": a["id"], "ok": True, "inserted": stats["inserted"], "updated": stats["updated"]})
        except Exception as e:  # noqa: BLE001 - one account must not stop the others
            log.warning("bridge: account %s: %s", a["id"], e)
            report.append({"account": a["id"], "ok": False, "error": str(e)[:200]})
        time.sleep(sleep_s)
    return report

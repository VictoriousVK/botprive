"""Copytrading, demo phase: members follow a strategy and see what a proportional copy gives.

A *leader* is a strategy published by the team and linked to a bot of the console. Its record
is read from the platform's own ledger (the bot's P&L at every snapshot), never typed in by
hand, and is labelled with the mode it comes from (simulation, paper or MT5).

A *follow* copies the leader in proportion: follower P&L = leader P&L since the follow started
x (allocation / leader reference capital) x multiplier. The copy stops by itself when the
follower's drawdown reaches the limit they chose. This is a demonstration: no order is sent
for the member. Copying onto a member's own MT5 account is a regulated activity (asset
management / investment advice, AMF-UMOA in the WAEMU zone): it stays closed until a lawyer
has validated the offer and the member-side MT5 connector exists.
"""

from __future__ import annotations

import secrets
import time
from typing import Any

from hedgefund.core.ledger import Kind

SCHEMA = """
CREATE TABLE IF NOT EXISTS copy_leaders (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    trader TEXT NOT NULL,
    bio TEXT NOT NULL DEFAULT '',
    style TEXT NOT NULL DEFAULT '',
    bot_id TEXT,
    risk_level INTEGER NOT NULL DEFAULT 3,
    ref_capital REAL NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft',
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS copy_follows (
    id TEXT PRIMARY KEY,
    member_id INTEGER NOT NULL,
    leader_id TEXT NOT NULL,
    mode TEXT NOT NULL,
    allocation REAL NOT NULL,
    multiplier REAL NOT NULL,
    max_drawdown_pct REAL NOT NULL,
    status TEXT NOT NULL,
    stop_reason TEXT,
    start_ts INTEGER NOT NULL,
    start_pnl REAL NOT NULL,
    stop_ts INTEGER,
    accepted_risk_at INTEGER NOT NULL,
    created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_follows_member ON copy_follows(member_id, status);
"""

LEADER_STATUS = {"draft": "Brouillon", "open": "Ouvert à la copie", "paused": "Copie suspendue", "closed": "Fermé"}
MODE_LABEL = {"simulation": "Simulation (prix simulés)", "paper": "Papier (prix réels, ordres simulés)", "mt5": "Compte MT5"}
MIN_ALLOCATION, MAX_ALLOCATION = 100.0, 1_000_000.0


class CopyError(ValueError):
    pass


def _drawdown_stats(values: list[float]) -> tuple[float, float]:
    """(current drawdown, max drawdown) of an equity series, as fractions."""
    peak, mdd, dd = float("-inf"), 0.0, 0.0
    for v in values:
        peak = max(peak, v)
        dd = (peak - v) / peak if peak > 0 else 0.0
        mdd = max(mdd, dd)
    return dd, mdd


def _thin(points: list[tuple[int, float]], n: int) -> list[tuple[int, float]]:
    if len(points) <= n:
        return points
    step = len(points) / n
    return [points[int(i * step)] for i in range(n - 1)] + [points[-1]]


class Copytrading:
    CACHE_S = 15.0

    def __init__(self, store: Any, engine: Any, mode: str = "demo", now=time.time):
        self.store, self.engine, self.mode, self.now = store, engine, mode, now
        self._cache: dict[tuple[int, str], tuple[float, list[tuple[int, float]]]] = {}
        store.executescript(SCHEMA)

    @property
    def enabled(self) -> bool:
        return self.mode != "off"

    # ---------------- leader record, from the ledger ----------------
    def _pnl_series(self, bot_id: str | None, since_ms: int = 0) -> list[tuple[int, float]]:
        """The bot's cumulative P&L at every ledger snapshot (cached briefly: pages poll it)."""
        if not bot_id:
            return []
        key = (id(self.engine.ledger), bot_id)
        hit = self._cache.get(key)
        if hit is None or time.monotonic() - hit[0] > self.CACHE_S:
            series = [(e.ts, float(e.payload["books"][bot_id])) for e in self.engine.ledger.query(kind=Kind.NAV) if bot_id in (e.payload.get("books") or {})]
            hit = self._cache[key] = (time.monotonic(), series)
        return [p for p in hit[1] if p[0] >= since_ms]

    def _record(self, leader: dict[str, Any], points: int = 160) -> dict[str, Any]:
        series = self._pnl_series(leader["bot_id"])
        cap = leader["ref_capital"]
        snap_bot = next((b for b in self.engine.snapshot()["bots"] if b["id"] == leader["bot_id"]), None) if leader["bot_id"] else None
        base = {
            "source_mode": self.engine.mode, "source_label": MODE_LABEL.get(self.engine.mode, self.engine.mode), "synthetic": bool(self.engine.feed.synthetic),
            "closed_trades": snap_bot["closed_trades"] if snap_bot else 0, "win_rate": snap_bot["win_rate"] if snap_bot else None, "running": bool(snap_bot and snap_bot["running"]),
        }
        if len(series) < 2:
            return {**base, "since": series[0][0] if series else None, "return_pct": None, "max_drawdown_pct": None, "curve": []}
        first = series[0][1]
        equity = [cap + v - first for _, v in series]
        _, mdd = _drawdown_stats(equity)
        return {
            **base, "since": series[0][0], "return_pct": (equity[-1] - cap) / cap * 100, "max_drawdown_pct": mdd * 100,
            "curve": [{"t": t, "v": round((cap + v - first) / cap * 100 - 100, 3)} for t, v in _thin(series, points)],
        }

    def _leader_public(self, r: dict[str, Any], with_record: bool = True) -> dict[str, Any]:
        out = {k: r[k] for k in ("id", "name", "trader", "bio", "style", "risk_level", "ref_capital", "status")}
        out["status_label"] = LEADER_STATUS.get(r["status"], r["status"])
        out["followers"] = self.store.execute("SELECT COUNT(*) AS n FROM copy_follows WHERE leader_id = ? AND status = 'active'", (r["id"],))[0]["n"]
        if with_record:
            out["record"] = self._record(r)
        return out

    def leaders(self, include_drafts: bool = False) -> list[dict[str, Any]]:
        sql = "SELECT * FROM copy_leaders" + ("" if include_drafts else " WHERE status IN ('open', 'paused')") + " ORDER BY created_at"
        return [self._leader_public(dict(r)) | ({"bot_id": r["bot_id"]} if include_drafts else {}) for r in self.store.execute(sql)]

    def _leader(self, leader_id: str) -> dict[str, Any]:
        rows = self.store.execute("SELECT * FROM copy_leaders WHERE id = ?", (leader_id,))
        if not rows:
            raise CopyError("stratégie introuvable")
        return dict(rows[0])

    def save_leader(self, data: dict[str, Any], leader_id: str | None = None) -> dict[str, Any]:
        name = str(data.get("name", "")).strip()[:80]
        trader = str(data.get("trader", "")).strip()[:80]
        bot_id = str(data.get("bot_id") or "").strip() or None
        status = data.get("status", "draft")
        risk = int(data.get("risk_level", 3))
        cap = float(data.get("ref_capital", 0) or 0)
        if len(name) < 3 or len(trader) < 2:
            raise CopyError("nom de la stratégie et du trader requis")
        if status not in LEADER_STATUS or not 1 <= risk <= 5:
            raise CopyError("statut ou niveau de risque invalide (1 à 5)")
        if not 100 <= cap <= 1e9:
            raise CopyError("capital de référence invalide")
        if bot_id and self.engine.store.get_bot(bot_id) is None:
            raise CopyError("bot inconnu dans la console")
        if status == "open" and not bot_id:
            raise CopyError("reliez la stratégie à un bot de la console avant de l'ouvrir à la copie")
        now = int(self.now())
        vals = (name, trader, str(data.get("bio", "")).strip()[:1000], str(data.get("style", "")).strip()[:120], bot_id, risk, cap, status, now)
        if leader_id:
            self._leader(leader_id)
            self.store.execute("UPDATE copy_leaders SET name=?, trader=?, bio=?, style=?, bot_id=?, risk_level=?, ref_capital=?, status=?, updated_at=? WHERE id=?", (*vals, leader_id))
        else:
            leader_id = "ldr_" + secrets.token_hex(6)
            self.store.execute("INSERT INTO copy_leaders (name, trader, bio, style, bot_id, risk_level, ref_capital, status, updated_at, created_at, id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", (*vals, now, leader_id))
        if status == "closed":
            self._stop_all(leader_id, "stratégie fermée par l'équipe")
        return self._leader_public(self._leader(leader_id)) | {"bot_id": bot_id}

    def _stop_all(self, leader_id: str, reason: str) -> None:
        self.store.execute("UPDATE copy_follows SET status = 'stopped', stop_reason = ?, stop_ts = ? WHERE leader_id = ? AND status = 'active'", (reason, int(self.now() * 1000), leader_id))

    # ---------------- follows ----------------
    def follow(self, member_id: int, entitlements: set[str], leader_id: str, allocation: float, multiplier: float, max_drawdown_pct: float, mode: str = "demo") -> dict[str, Any]:
        if not self.enabled:
            raise CopyError("le copytrading n'est pas ouvert")
        if mode != "demo":
            raise CopyError("la copie sur compte réel ouvrira après validation juridique ; seule la démo est disponible")
        if "copy_demo" not in entitlements:
            raise CopyError("votre offre ne comprend pas le copytrading")
        leader = self._leader(leader_id)
        if leader["status"] != "open":
            raise CopyError("cette stratégie n'accepte pas de nouveaux copieurs")
        if not MIN_ALLOCATION <= allocation <= MAX_ALLOCATION:
            raise CopyError(f"capital alloué entre {MIN_ALLOCATION:.0f} et {MAX_ALLOCATION:.0f} USD")
        if not 0.1 <= multiplier <= 3.0:
            raise CopyError("multiplicateur de risque entre 0,1 et 3")
        if not 5 <= max_drawdown_pct <= 50:
            raise CopyError("perte maximale entre 5 % et 50 %")
        if self.store.execute("SELECT 1 FROM copy_follows WHERE member_id = ? AND leader_id = ? AND status = 'active'", (member_id, leader_id)):
            raise CopyError("vous copiez déjà cette stratégie")
        if self.store.execute("SELECT COUNT(*) AS n FROM copy_follows WHERE member_id = ? AND status = 'active'", (member_id,))[0]["n"] >= 5:
            raise CopyError("5 copies actives au maximum")
        series = self._pnl_series(leader["bot_id"])
        start_pnl = series[-1][1] if series else 0.0
        now = int(self.now())
        fid = "cpy_" + secrets.token_hex(6)
        self.store.execute(
            "INSERT INTO copy_follows (id, member_id, leader_id, mode, allocation, multiplier, max_drawdown_pct, status, start_ts, start_pnl, accepted_risk_at, created_at) VALUES (?, ?, ?, 'demo', ?, ?, ?, 'active', ?, ?, ?, ?)",
            (fid, member_id, leader_id, float(allocation), float(multiplier), float(max_drawdown_pct), series[-1][0] if series else now * 1000, start_pnl, now, now),
        )
        return self.follow_detail(member_id, fid)

    def stop(self, member_id: int, follow_id: str) -> dict[str, Any]:
        f = self._follow(member_id, follow_id)
        if f["status"] == "active":
            self.store.execute("UPDATE copy_follows SET status = 'stopped', stop_reason = 'arrêtée par le membre', stop_ts = ? WHERE id = ?", (int(self.now() * 1000), follow_id))
        return self.follow_detail(member_id, follow_id)

    def _follow(self, member_id: int, follow_id: str) -> dict[str, Any]:
        rows = self.store.execute("SELECT * FROM copy_follows WHERE id = ? AND member_id = ?", (follow_id, member_id))
        if not rows:
            raise CopyError("copie introuvable")
        return dict(rows[0])

    def follow_detail(self, member_id: int, follow_id: str, points: int = 160) -> dict[str, Any]:
        f = self._follow(member_id, follow_id)
        leader = self._leader(f["leader_id"])
        series = [p for p in self._pnl_series(leader["bot_id"], since_ms=f["start_ts"]) if f["stop_ts"] is None or p[0] <= f["stop_ts"]]
        scale = f["allocation"] / leader["ref_capital"] * f["multiplier"]
        curve: list[tuple[int, float]] = []
        peak = f["allocation"]
        stopped_at = None
        for t, v in series:
            eq = f["allocation"] + (v - f["start_pnl"]) * scale
            curve.append((t, eq))
            peak = max(peak, eq)
            if f["status"] == "active" and peak > 0 and (peak - eq) / peak * 100 >= f["max_drawdown_pct"]:
                stopped_at = t
                break
        if stopped_at is not None:
            self.store.execute("UPDATE copy_follows SET status = 'stopped', stop_reason = ?, stop_ts = ? WHERE id = ? AND status = 'active'", (f"perte maximale de {f['max_drawdown_pct']:.0f} % atteinte : copie arrêtée automatiquement", stopped_at, follow_id))
            f = self._follow(member_id, follow_id)
        equity = curve[-1][1] if curve else f["allocation"]
        dd, mdd = _drawdown_stats([f["allocation"]] + [v for _, v in curve])
        return {
            "id": f["id"], "leader": {"id": leader["id"], "name": leader["name"], "trader": leader["trader"]}, "mode": f["mode"],
            "allocation": f["allocation"], "multiplier": f["multiplier"], "max_drawdown_pct": f["max_drawdown_pct"],
            "status": f["status"], "stop_reason": f["stop_reason"], "start_ts": f["start_ts"], "stop_ts": f["stop_ts"],
            "equity": equity, "pnl": equity - f["allocation"], "return_pct": (equity / f["allocation"] - 1) * 100, "drawdown_pct": dd * 100, "max_drawdown_seen_pct": mdd * 100,
            "curve": [{"t": t, "v": round(v, 2)} for t, v in _thin(curve, points)], "source_label": MODE_LABEL.get(self.engine.mode, self.engine.mode), "synthetic": bool(self.engine.feed.synthetic),
        }

    def follows_of(self, member_id: int) -> list[dict[str, Any]]:
        ids = [r["id"] for r in self.store.execute("SELECT id FROM copy_follows WHERE member_id = ? ORDER BY created_at DESC LIMIT 20", (member_id,))]
        return [self.follow_detail(member_id, i, points=60) for i in ids]

"""ICT module: the deterministic analysis (member route and ``ict.analyze`` tool) and the
golden-set tooling for operators (snapshot, annotation, evaluation)."""

from __future__ import annotations

import threading
import time
from collections import deque
from typing import Any

from fastapi import Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import delete, insert, select

from hedgefund.saas import golden as G
from hedgefund.saas.api import ROUTERS, ApiContext, guard
from hedgefund.saas.db import ict_annotations, new_id, now_ms
from hedgefund.saas.engines import ict as E
from hedgefund.saas.ingest import normalize_symbol
from hedgefund.saas.service import INTERVALS, Access, SaaS
from hedgefund.saas.tools import Tool, ToolContext


class ICT:
    def __init__(self, saas: SaaS):
        self.saas = saas
        self._hits: dict[int, deque] = {}
        self._lock = threading.Lock()

    def symbols(self) -> list[str]:
        if self.saas.market is None:
            return []
        wanted = self.saas.config.get("analysis", {}).get("symbols", [])
        have = set(self.saas.market.symbols())
        return [s for s in wanted if s in have] or sorted(have)

    def resolve(self, symbol: str) -> str:
        have = set(self.saas.market.symbols()) if self.saas.market else set()
        if symbol in have:
            return symbol
        norm = normalize_symbol(symbol)
        if norm in have:
            return norm
        raise LookupError(f"symbole non disponible dans le flux de prix : {symbol}")

    def analyze(self, symbol: str, tf_entry: str = "M5", tf_htf: str = "H1", now: int | None = None) -> dict[str, Any]:
        if self.saas.market is None:
            raise LookupError("aucun flux de prix configuré")
        a = E.analyze(self.saas.market, self.resolve(symbol), tf_entry, tf_htf, now)
        return a.model_dump()

    def rate_ok(self, member_id: int, per_minute: int = 20) -> bool:
        now = time.monotonic()
        with self._lock:
            q = self._hits.setdefault(member_id, deque())
            while q and now - q[0] > 60:
                q.popleft()
            if len(q) >= per_minute:
                return False
            q.append(now)
            return True

    # ---- golden set ----
    def snapshot(self, symbol: str, tf: str, at: int | None = None, n: int = 120) -> dict[str, Any]:
        m = self.saas.market
        if m is None:
            raise LookupError("aucun flux de prix configuré")
        sym = self.resolve(symbol)
        at = at or m.now()
        md = m.feed.market_data([sym], INTERVALS[tf], n, at)
        view = md.view(at)
        ser, k = view.series(sym)
        step = md.interval_ms
        bars = [[ser.ts[i] - step, ser.open[i], ser.high[i], ser.low[i], ser.close[i]] for i in range(max(0, k - n), k)]
        return {"symbol": sym, "timeframe": tf, "as_of": at, "bars": bars, "synthetic": m.synthetic}

    def save(self, a: G.Annotation) -> str:
        aid = new_id("gold")
        with self.saas.db.system() as conn:
            conn.execute(insert(ict_annotations).values(id=aid, dataset=a.dataset, symbol=a.symbol, timeframe=a.timeframe, as_of=a.as_of, bars=a.bars,
                                                       labels=a.labels.model_dump(), annotator=a.annotator, rationale=a.rationale, split=a.split, created_at=now_ms()))
        return aid

    def list(self, dataset: str) -> list[dict[str, Any]]:
        with self.saas.db.system() as conn:
            rows = conn.execute(select(ict_annotations).where(ict_annotations.c.dataset == dataset).order_by(ict_annotations.c.created_at))
            return [dict(r._mapping) for r in rows]

    def delete(self, aid: str) -> None:
        with self.saas.db.system() as conn:
            if conn.execute(delete(ict_annotations).where(ict_annotations.c.id == aid)).rowcount == 0:
                raise LookupError("annotation introuvable")

    def evaluate(self, dataset: str, split: str = "dev") -> dict[str, Any]:
        if dataset == "synthetic-v1":
            cases = G.synthetic_set()
        else:
            cases = [r for r in self.list(dataset) if r["split"] == split]
        results = [G.evaluate_case({k: c[k] for k in ("dataset", "symbol", "timeframe", "as_of", "bars", "labels", "annotator", "rationale", "split")}) for c in cases]
        return {"dataset": dataset, "split": split, "definitions": E.VERSION, "summary": G.aggregate(results) if results else None, "cases": len(results)}


# ---------------------------------------------------------------- tool
class AnalyzeIn(BaseModel):
    symbol: str = Field(min_length=2, max_length=20)
    tf_entry: str = Field(default="M5", pattern=r"^(M1|M5|M15)$")
    tf_htf: str = Field(default="H1", pattern=r"^(H1|H4|D1)$")


def _analyze(ctx: ToolContext, p: AnalyzeIn) -> dict[str, Any]:
    a = ctx.services.modules["ict"].analyze(p.symbol, p.tf_entry, p.tf_htf)
    # Compact view for a model: the full object stays in the member's card.
    return {k: a[k] for k in ("symbol", "as_of", "price", "htf_bias", "premium_discount", "dealing_range", "time", "setups", "rejections", "caveats")} | {
        "open_fvgs": [g for g in a["fvgs"] if g["status"] != "mitigated"][-6:], "unswept_pools": [p for p in a["pools"] if not p["swept"]][:8], "structure": a["structure"][-6:]}


class SnapshotIn(BaseModel):
    symbol: str = Field(min_length=2, max_length=20)
    timeframe: str = Field(default="M5", pattern=r"^(M1|M5|M15|H1)$")
    at: int | None = None
    bars: int = Field(default=120, ge=40, le=600)


def mount(ctx: ApiContext) -> None:
    app, saas = ctx.app, ctx.saas
    ict: ICT = saas.modules["ict"]
    acc_dep = ctx.acc()

    @app.get("/api/app/symbols")
    def symbols(acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        m = saas.market
        return {"symbols": ict.symbols(), "source": m.source if m else None, "synthetic": m.synthetic if m else None}

    @app.get("/api/app/ict/{symbol}")
    def analyze(symbol: str, tf: str = "M5", htf: str = "H1", acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        guard(lambda: acc.require("analysis", "Analyse ICT"))
        if tf not in ("M1", "M5", "M15") or htf not in ("H1", "H4", "D1"):
            raise HTTPException(400, "unité de temps non prise en charge")
        if not ict.rate_ok(acc.member_id):
            raise HTTPException(429, "trop d'analyses : attendez une minute")
        return guard(lambda: ict.analyze(symbol[:20], tf, htf))

    @app.get("/api/app/bars/{symbol}")
    def bars(symbol: str, tf: str = "M5", n: int = 150, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        guard(lambda: acc.require("analysis", "Analyse ICT"))
        if tf not in ("M1", "M5", "M15", "H1"):
            raise HTTPException(400, "unité de temps non prise en charge")
        return guard(lambda: ict.snapshot(symbol[:20], tf, None, max(40, min(n, 400))))

    # ---- operators: golden set ----
    @app.post("/api/admin/golden/snapshot")
    def snapshot(body: SnapshotIn, s=Depends(ctx.operator)) -> dict:  # noqa: B008
        return guard(lambda: ict.snapshot(body.symbol, body.timeframe, body.at, body.bars))

    @app.post("/api/admin/golden")
    def save(body: G.Annotation, s=Depends(ctx.operator)) -> dict:  # noqa: B008
        return {"id": ict.save(body)}

    @app.get("/api/admin/golden")
    def list_(dataset: str = "golden-v1", s=Depends(ctx.operator)) -> list[dict]:  # noqa: B008
        return [{k: r[k] for k in ("id", "dataset", "symbol", "timeframe", "as_of", "annotator", "split", "created_at")} | {"labels": r["labels"]} for r in ict.list(dataset[:40])]

    @app.delete("/api/admin/golden/{aid}")
    def remove(aid: str, s=Depends(ctx.operator)) -> dict:  # noqa: B008
        guard(lambda: ict.delete(aid[:40]))
        return {"ok": True}

    @app.get("/api/admin/golden/eval")
    def evaluate(dataset: str = "golden-v1", split: str = "dev", s=Depends(ctx.operator)) -> dict:  # noqa: B008
        if split not in ("dev", "holdout"):
            raise HTTPException(400, "split : dev ou holdout")
        return ict.evaluate(dataset[:40], split)


def install(saas: SaaS) -> ICT:
    m = ICT(saas)
    saas.modules["ict"] = m
    saas.tools.register(Tool("ict.analyze", "Analyse ICT déterministe d'un symbole à l'instant présent (dernière bougie clôturée) : biais HTF, premium/discount, killzone et macro, FVG ouverts, liquidité non prise, structure, setups évalués par les règles et raisons de rejet.",
                             AnalyzeIn, _analyze, timeout_s=15.0))
    return m


ROUTERS.append(mount)

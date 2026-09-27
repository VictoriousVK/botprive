"""Setup analyst and graph G1: [ICT engine ‖ member's statistics ‖ briefing] → explanation →
deterministic risk gate → decision card → the member takes note (or rejects) → audit record.

No order is ever sent: the card is information and a proposal the member can act on in their
own platform. The analyst never sees the risk limits before writing (asymmetry); the gate then
applies them and logs any disagreement. If the gate cannot run, the card shows no proposal.
"""

from __future__ import annotations

import json
import operator
from typing import Annotated, Any, Optional

from fastapi import Depends
from pydantic import BaseModel, Field
from sqlalchemy import desc

from hedgefund.saas import guardrails as GR
from hedgefund.saas.api import ROUTERS, ApiContext, guard
from hedgefund.saas.db import agent_runs, briefings, new_id, now_ms, setup_analyses
from hedgefund.saas.graphs import RunContext, make_checkpointer, node, resume_graph, run_graph
from hedgefund.saas.harness import Budget, write_audit
from hedgefund.saas.llm import LLMError
from hedgefund.saas.schemas import AnalysteLLMOut, SetupRequest
from hedgefund.saas.service import Access, SaaS

MODEL_FR = {"SilverBullet": "Silver Bullet", "MacroBreaker": "Macro Breaker"}
PD_FR = {"premium": "premium", "discount": "discount", "equilibrium": "équilibre"}
BIAS_FR = {"bullish": "haussier", "bearish": "baissier", "neutral": "neutre"}


def _n(x: float | None, d: int = 2) -> str:
    if x is None:
        return "—"
    return f"{x:,.{d}f}".replace(",", " ").replace(".", ",")


def best_candidate(ict: dict[str, Any]) -> dict[str, Any] | None:
    cands = ict.get("setups") or []
    if not cands:
        return None
    return sorted(cands, key=lambda c: (c["relaxed"], -(c["rule_score"] - c["min_score"]), -c["rr"]))[0]


def label_for(ict: dict[str, Any] | None, cand: dict[str, Any] | None) -> str:
    if ict is None:
        return "INSUFFICIENT_EVIDENCE"
    if cand is None:
        return "NO_SETUP"
    price = ict["price"]
    if (cand["direction"] == "long" and price <= cand["invalidation"]) or (cand["direction"] == "short" and price >= cand["invalidation"]):
        return "INVALID"
    if cand["relaxed"]:
        return "PARTIAL"
    return "VALID_BY_RULES" if cand["rule_score"] >= cand["min_score"] else "PARTIAL"


def plan_alignment(ict: dict[str, Any], cand: dict[str, Any] | None, plan: dict[str, Any], stats: dict[str, Any]) -> list[str]:
    out = []
    sym = ict["symbol"]
    if plan.get("markets"):
        out.append(f"Marché {sym} {'dans' if sym in plan['markets'] else 'hors de'} votre plan")
    kz = ict["time"].get("killzone")
    if plan.get("killzones"):
        out.append(f"Killzone {kz or 'aucune'} : {'dans' if kz in plan['killzones'] else 'hors de'} votre plan")
    if cand:
        m = cand["model"]
        if plan.get("setups"):
            out.append(f"Modèle {MODEL_FR.get(m, m)} {'présent' if m in plan['setups'] else 'absent'} dans vos setups")
        if plan.get("min_rr"):
            ok = cand["rr"] >= float(plan["min_rr"]) - 1e-9
            out.append(f"RR {_n(cand['rr'])} {'≥' if ok else '<'} votre minimum {_n(float(plan['min_rr']), 1)}")
        s = stats.get(m) or {}
        if s.get("n"):
            out.append(f"Votre historique sur ce modèle : {s['n']} trades, espérance {_n(s.get('expectancy_r'))} R" + (" (échantillon faible)" if s.get("sample_warning") else ""))
        else:
            out.append("Aucun trade de ce modèle dans votre journal pour l'instant")
    return out


def rules_text(ict: dict[str, Any], cand: dict[str, Any] | None, label: str) -> str:
    t = ict["time"]
    ctx = f"Contexte : biais H1 {BIAS_FR[ict['htf_bias']]}, prix en zone {PD_FR[ict['premium_discount']]}"
    ctx += f", killzone {t['killzone']}" if t.get("killzone") else ", hors killzone"
    ctx += f", macro {t['macro_window']}" if t.get("macro_window") else ""
    if cand is None:
        why = "; ".join(ict.get("rejections") or []) or "aucun modèle d'entrée ne passe les règles"
        return f"Aucun setup valide selon les règles à cet instant ({why}). {ctx}."
    d = "d'achat" if cand["direction"] == "long" else "de vente"
    head = f"{MODEL_FR.get(cand['model'], cand['model'])} {d} évalué par les règles : score {cand['rule_score']} (minimum {cand['min_score']})"
    head += ", passe relâchée" if cand["relaxed"] else ""
    lv = f"Zone d'entrée {_n(cand['entry_zone'][0])} – {_n(cand['entry_zone'][1])}, entrée {_n(cand['entry'])}, invalidation {_n(cand['invalidation'])}, objectif {_n(cand['targets'][0])} (RR {_n(cand['rr'])})."
    ok = " ; ".join(cand["rules_passed"][:5])
    ko = " ; ".join(cand["rules_failed"][:4])
    txt = f"{head}. {lv} {ctx}. Règles validées : {ok}."
    if ko:
        txt += f" Règles non validées : {ko}."
    if label == "INVALID":
        txt += " Le prix a déjà dépassé l'invalidation : le setup n'est plus valable."
    return txt


def points_to_check(ict: dict[str, Any], cand: dict[str, Any] | None) -> list[str]:
    pts = ["La réaction du prix dans la zone d'entrée sur votre propre graphique (le moteur ne voit que les bougies clôturées)"]
    if cand:
        pts.append("Le spread et l'heure du serveur de votre broker (niveaux calculés sur le flux de la plateforme)")
    pts.append("Le calendrier économique : aucune annonce à fort impact pendant le trade")
    return pts


def confidence(cand: dict[str, Any] | None, stats: dict[str, Any]) -> int:
    """Heuristic until calibrated (docs/SAAS.md): the rule margin, not a win probability."""
    if cand is None:
        return 0
    c = 50 + 8 * (cand["rule_score"] - cand["min_score"])
    if cand["relaxed"]:
        c -= 15
    s = stats.get(cand["model"]) or {}
    if not s.get("n") or s.get("sample_warning"):
        c -= 10
    return int(max(5, min(85, c)))


def compact(ict: dict[str, Any]) -> dict[str, Any]:
    return {
        "symbol": ict["symbol"], "price": ict["price"], "htf_bias": ict["htf_bias"], "premium_discount": ict["premium_discount"], "dealing_range": ict["dealing_range"],
        "time": {k: ict["time"].get(k) for k in ("ny_time", "killzone", "macro_window", "silver_bullet_window", "midnight_open", "daily_open_18h", "amd_phase")},
        "unswept_pools": [{k: p[k] for k in ("side", "level", "source")} for p in ict["pools"] if not p["swept"]][:6],
        "open_fvgs": [{k: g[k] for k in ("kind", "top", "bottom", "status")} for g in ict["fvgs"] if g["status"] != "mitigated"][-5:],
        "structure": [{k: e[k] for k in ("kind", "direction", "level", "timeframe")} for e in ict["structure"]][-5:],
        "rejections": ict["rejections"], "caveats": ict["caveats"],
    }


# ---------------------------------------------------------------- graph G1
class G1State(BaseModel):
    trace_id: str
    request: dict[str, Any]
    ict: Optional[dict[str, Any]] = None
    stats: Optional[dict[str, Any]] = None
    briefing: Optional[dict[str, Any]] = None
    draft: Optional[dict[str, Any]] = None
    risk_gate: Optional[dict[str, Any]] = None
    card: Optional[dict[str, Any]] = None
    approval: Optional[dict[str, Any]] = None
    output: Optional[dict[str, Any]] = None
    errors: Annotated[list[str], operator.add] = []


def build_g1(saas: SaaS) -> Any:
    from langgraph.graph import END, START, StateGraph
    from langgraph.types import interrupt

    spec = saas.models.get("analyste")
    system = saas.prompts.get("analyste", "")
    expiry_min = int(saas.config.get("analysis", {}).get("approval_expiry_min", 120))

    @node("moteur ICT")
    def ict_node(state: G1State, ctx: RunContext) -> dict[str, Any]:
        r = state.request
        try:
            a = saas.modules["ict"].analyze(r["symbol"], r.get("tf_entry", "M5"), r.get("tf_htf", "H1"))
        except Exception as e:  # noqa: BLE001 - insufficient data, unknown symbol: the card says so
            return {"errors": [f"moteur ICT : {e}"]}
        ctx.tracer.event("setups évalués par les règles", setups=len(a["setups"]))
        return {"ict": a}

    @node("statistiques du membre")
    def quant_node(state: G1State, ctx: RunContext) -> dict[str, Any]:
        from hedgefund.saas.engines import perf

        journal = saas.modules["journal"]
        with saas.db.tenant(ctx.tenant_id) as s:
            rows = journal.list_trades(s, ctx.user_id, since=now_ms() - 365 * 86_400_000, closed_only=True, limit=20_000)
            plan = journal.plan(s, ctx.user_id)
        return {"stats": {"plan": plan, **{m: perf.setup_stats(rows, m) for m in ("SilverBullet", "MacroBreaker")}}}

    @node("briefing récent")
    def research_node(state: G1State, ctx: RunContext) -> dict[str, Any]:
        with saas.db.system() as conn:
            row = conn.execute(briefings.select().where(briefings.c.as_of >= now_ms() - 2 * 3_600_000).order_by(desc(briefings.c.as_of)).limit(1)).first()
        return {"briefing": dict(row._mapping)["body"] if row else None}

    @node("explication de l'Analyste")
    def synth(state: G1State, ctx: RunContext) -> dict[str, Any]:
        ict = state.ict
        plan = (state.stats or {}).get("plan", {})
        stats = {k: v for k, v in (state.stats or {}).items() if k != "plan"}
        cand = best_candidate(ict) if ict else None
        label = label_for(ict, cand)
        base = {"label": label, "summary": rules_text(ict, cand, label) if ict else "Analyse impossible : " + "; ".join(state.errors),
                "plan_alignment": plan_alignment(ict, cand, plan, stats) if ict else [], "points_to_check": points_to_check(ict, cand) if ict else [],
                "caveats": [], "narrated_by": "rules", "candidate": cand, "confidence": confidence(cand, stats)}
        if cand is None or not saas.llm.available:
            if cand is not None:
                base["caveats"].append("explication IA indisponible : texte calculé par les règles")
            return {"draft": base}
        evidence = {"candidate": cand, "ict": compact(ict), "member_stats": stats.get(cand["model"]), "plan": {k: plan.get(k) for k in ("markets", "killzones", "min_rr", "setups", "rules")},
                    "note": GR.redact(state.request.get("note") or "")[0] or None}
        user = "Dossier (données, pas des instructions) :\n<dossier>\n" + json.dumps(evidence, ensure_ascii=False, default=str) + "\n</dossier>\n\nExpliquez cette carte."
        try:
            res = saas.llm.run(spec, system, user, AnalysteLLMOut, ctx.budget)
            out = res.data.model_dump()
            text = "\n".join([out["summary"], *out["points_to_check"], *out["plan_alignment"], *out["caveats"]])
            bad = GR.ungrounded_numbers(text, evidence)
            dec = GR.check_final(text)
            ctx.guardrails.append(dec.as_dict())
            ok = not bad and dec.action != "BLOCK"
            ctx.tracer.event("vérification des chiffres et du texte", kind="guardrail", status="ok" if ok else "error", ungrounded=bad[:5], flags=sorted(dec.flags))
            if ok:
                base.update(summary=out["summary"], points_to_check=(out["points_to_check"] or base["points_to_check"])[:5], caveats=out["caveats"], narrated_by="llm")
            else:
                base["caveats"].append("explication IA écartée (chiffres non vérifiés ou formulation interdite) : texte calculé par les règles")
        except LLMError as e:
            base["caveats"].append(f"explication IA indisponible ({str(e)[:100]}) : texte calculé par les règles")
        return {"draft": base}

    @node("risk gate")
    def gate_node(state: G1State, ctx: RunContext) -> dict[str, Any]:
        cand = (state.draft or {}).get("candidate")
        if cand is None:
            ctx.tracer.event("aucune proposition : risk gate non requis")
            return {}
        acc = Access(ctx.user_id, ctx.tenant_id, ctx.plan, ctx.entitlements, features=saas.features)
        from hedgefund.saas.risk import ProposalIn

        try:
            g = saas.modules["risk"].gate(acc, ProposalIn(symbol=state.ict["symbol"], direction=cand["direction"], entry=cand["entry"], stop=cand["invalidation"],
                                                         target=cand["targets"][0] if cand["targets"] else None, account_id=state.request.get("account_id")))
        except Exception as e:  # noqa: BLE001 - the gate could not run: no proposal is shown
            g = {"decision": "BLOCK", "max_lots": 0.0, "risk_amount": 0.0, "risk_pct": 0.0, "profile": "—", "profile_verified": False, "rules_applied": [],
                 "violations": [f"risk gate indisponible : {e}"], "warnings": [], "disagreement_logged": False}
        g.pop("state", None)
        ctx.tracer.event(f"risk gate : {g['decision']}", kind="guardrail", status="ok" if g["decision"] != "BLOCK" else "error")
        return {"risk_gate": g}

    @node("carte de décision")
    def card_node(state: G1State, ctx: RunContext) -> dict[str, Any]:
        d = state.draft
        ict = state.ict
        g = state.risk_gate
        exp = now_ms() + expiry_min * 60_000 if d["candidate"] and g and g["decision"] != "BLOCK" else None
        caveats = list(d["caveats"]) + list((ict or {}).get("caveats", []))
        if state.briefing:
            caveats.append("briefing de pré-session disponible : " + str(state.briefing.get("label", ""))[:40])
        card = {
            "agent": "analyste", "agent_version": saas.manifest.fingerprint, "label": d["label"], "confidence": d["confidence"],
            "evidence": [{"source_id": "ict.analyze", "field": "rule_score", "value": d["candidate"]["rule_score"], "as_of": ict["as_of"]}] if d["candidate"] else [],
            "summary": d["summary"], "caveats": caveats, "insufficient_evidence": d["label"] == "INSUFFICIENT_EVIDENCE", "trace_id": state.trace_id,
            "narrated_by": d["narrated_by"], "symbol": (ict or {}).get("symbol", state.request["symbol"]), "as_of": (ict or {}).get("as_of", now_ms()),
            "candidate": d["candidate"], "ict": compact(ict) if ict else {}, "risk_gate": g, "stats": (state.stats or {}).get(d["candidate"]["model"]) if d["candidate"] else None,
            "plan_alignment": d["plan_alignment"], "points_to_check": d["points_to_check"], "expires_at": exp, "disclaimer": GR.DISCLAIMER,
            "last_line": f"VERDICT={d['label']};CONFIDENCE={d['confidence']};TRACE={state.trace_id}",
        }
        with saas.db.tenant(ctx.tenant_id) as s:
            s.insert(setup_analyses, {"id": state.trace_id, "user_id": ctx.user_id, "symbol": card["symbol"], "as_of": card["as_of"], "source": state.request.get("source", "user"),
                                      "label": d["label"], "body": json.loads(json.dumps(card, default=str)), "expires_at": exp, "created_at": now_ms()})
        return {"card": card, "output": card}

    @node("prise de connaissance")
    def approval_node(state: G1State, ctx: RunContext) -> dict[str, Any]:
        if state.card["expires_at"] is None:
            return {}
        decision = interrupt({"expires_at": state.card["expires_at"], "message": "Prenez connaissance de la carte : l'ajouter à votre plan du jour, ou la rejeter."})
        if now_ms() > state.card["expires_at"]:
            decision = {**(decision or {}), "decision": "expired"}
        return {"approval": decision}

    @node("audit")
    def audit_node(state: G1State, ctx: RunContext) -> dict[str, Any]:
        decision = (state.approval or {}).get("decision")
        with saas.db.tenant(ctx.tenant_id) as s:
            if decision:
                s.update(setup_analyses, {"id": state.trace_id}, {"decision": decision, "decided_at": now_ms()})
        write_audit(saas.db, ctx.tenant_id, state.trace_id, {
            "graph": "G1", "request": {k: v for k, v in state.request.items() if k != "note"}, "evidence": {"candidate": (state.draft or {}).get("candidate"), "as_of": (state.ict or {}).get("as_of")},
            "version": saas.manifest.fingerprint, "guardrail_decisions": ctx.guardrails, "risk_gate": state.risk_gate,
            "conclusion": {"label": state.card["label"], "narrated_by": state.card["narrated_by"]}, "autonomy_tier": "PROPOSE", "human_approval": state.approval,
        })
        return {"output": {**state.card, "decision": decision}}

    g = StateGraph(G1State)
    for name, fn in (("ict", ict_node), ("quant", quant_node), ("research", research_node), ("synth", synth), ("gate", gate_node), ("card", card_node),
                     ("approval", approval_node), ("audit", audit_node)):
        g.add_node(name, fn)
    for branch in ("ict", "quant", "research"):
        g.add_edge(START, branch)
    g.add_edge(["ict", "quant", "research"], "synth")
    g.add_edge("synth", "gate")
    g.add_edge("gate", "card")
    g.add_edge("card", "approval")
    g.add_edge("approval", "audit")
    g.add_edge("audit", END)
    return g.compile(checkpointer=make_checkpointer(saas))


# ---------------------------------------------------------------- service
class Analyste:
    def __init__(self, saas: SaaS):
        self.saas = saas
        self._graph = None

    @property
    def graph(self) -> Any:
        if self._graph is None:
            self._graph = build_g1(self.saas)
        return self._graph

    def start(self, acc: Access, req: SetupRequest, idem_key: str | None = None) -> dict[str, Any]:
        acc.require("analysis", "Analyste de setup")
        if req.note:
            d = GR.check_input(req.note, max_len=500)
            if d.action == "BLOCK":
                raise ValueError("; ".join(d.reasons))
        self.saas.modules["ict"].resolve(req.symbol)
        self.saas.consume(acc, "analysis")
        trace = new_id("tr")
        payload = {"tenant_id": acc.tenant_id, "user_id": acc.member_id, "request": req.model_dump(), "trace_id": trace, "plan": acc.plan, "entitlements": sorted(acc.entitlements)}
        self.saas.queue.enqueue("g1_analysis", payload, tenant_id=acc.tenant_id, priority=0, idem_key=idem_key or f"g1:{trace}")
        if self.saas.worker is None:
            self.saas.run_inline()
        return {"trace_id": trace}

    def run_job(self, job: dict[str, Any]) -> dict[str, Any]:
        p = job["payload"]
        budget = Budget(max_llm_calls=2, max_input_tokens=30_000, max_output_tokens=4_000, deadline_s=60)
        tid, status, _ = run_graph(self.saas, self.graph, "G1", p["tenant_id"], p["user_id"], {"request": p["request"]}, budget, trace_id=p["trace_id"],
                                   entitlements=frozenset(p.get("entitlements", [])), plan=p.get("plan", "gratuit"))
        self.saas.add_cost(p["tenant_id"], "analysis", budget.cost_usd)
        return {"trace_id": tid, "status": status}

    def list(self, acc: Access, limit: int = 30) -> list[dict[str, Any]]:
        with self.saas.db.tenant(acc.tenant_id) as s:
            rows = s.select(setup_analyses, {"user_id": acc.member_id}, order_by=desc(setup_analyses.c.created_at), limit=limit)
        return [{k: r[k] for k in ("id", "symbol", "as_of", "source", "label", "decision", "expires_at", "created_at")} | {"model": ((r["body"] or {}).get("candidate") or {}).get("model")} for r in rows]

    def get(self, acc: Access, trace_id: str) -> dict[str, Any]:
        with self.saas.db.tenant(acc.tenant_id) as s:
            run = s.one(agent_runs, {"id": trace_id, "user_id": acc.member_id, "graph": "G1"})
            row = s.one(setup_analyses, {"id": trace_id})
        if run is None:
            raise LookupError("analyse introuvable")
        return {"id": trace_id, "status": run["status"], "error": run["error"], "card": row["body"] if row else None, "decision": row["decision"] if row else None}

    def decide(self, acc: Access, trace_id: str, decision: str, comment: str = "") -> dict[str, Any]:
        if decision not in ("approved", "rejected"):
            raise ValueError("décision : approved ou rejected")
        self.get(acc, trace_id)
        status, _out = resume_graph(self.saas, self.graph, acc.tenant_id, acc.member_id, trace_id, {"decision": decision, "by": acc.member_id, "at": now_ms(), "comment": comment[:300]},
                                    entitlements=acc.entitlements, plan=acc.plan)
        return {**self.get(acc, trace_id), "run_status": status}


class DecisionIn(BaseModel):
    decision: str = Field(pattern=r"^(approved|rejected)$")
    comment: str = Field(default="", max_length=300)


def mount(ctx: ApiContext) -> None:
    app, saas = ctx.app, ctx.saas
    an: Analyste = saas.modules["analyste"]
    acc_dep = ctx.acc()

    @app.post("/api/app/analyses")
    def start(body: SetupRequest, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: an.start(acc, body.model_copy(update={"source": "user", "alert_id": None})))

    @app.get("/api/app/analyses")
    def list_(acc: Access = Depends(acc_dep)) -> list[dict]:  # noqa: B008
        return an.list(acc)

    @app.get("/api/app/analyses/{trace_id}")
    def get(trace_id: str, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: an.get(acc, trace_id[:40]))

    @app.post("/api/app/analyses/{trace_id}/decision")
    def decide(trace_id: str, body: DecisionIn, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: an.decide(acc, trace_id[:40], body.decision, body.comment))


def install(saas: SaaS) -> Analyste:
    a = Analyste(saas)
    saas.modules["analyste"] = a
    saas.handlers["g1_analysis"] = a.run_job
    return a


ROUTERS.append(mount)

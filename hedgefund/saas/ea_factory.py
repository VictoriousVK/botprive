"""EA factory, graph G2: validated spec → MQL5 code → deterministic review → compilation on the
Windows bridge → evaluator (at most six rounds, stops when the same errors come back) → model
card → a human approves the move to demo. The loop is anchored in what can be executed: the
compiler and the checklist judge the code, not a model.

The Strategy Tester backtest runs on the Windows bridge too; until one is configured, the card
says the EA is "compiled, not tested" — nothing here claims a performance.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Literal, Optional, Protocol

import requests
from fastapi import Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy import desc

from hedgefund.saas.api import ROUTERS, ApiContext, guard
from hedgefund.saas.db import agent_runs, lab_reports, new_id, now_ms, strategy_specs
from hedgefund.saas.graphs import RunContext, make_checkpointer, node, resume_graph, run_graph
from hedgefund.saas.harness import Budget, write_audit
from hedgefund.saas.service import Access, SaaS

MAX_ROUNDS = 6


# ---------------------------------------------------------------- spec and outputs
class StrategySpec(BaseModel):
    name: str = Field(min_length=3, max_length=60, pattern=r"^[A-Za-z0-9 _-]+$")
    symbols: list[str] = Field(min_length=1, max_length=3)
    timeframe: Literal["M1", "M5", "M15", "M30", "H1", "H4"] = "M5"
    direction: Literal["both", "long", "short"] = "both"
    entry_rules: list[str] = Field(min_length=1, max_length=12)
    exit_rules: list[str] = Field(min_length=1, max_length=8)
    risk_pct: float = Field(default=0.5, gt=0, le=2)
    stop_rule: str = Field(min_length=5, max_length=300)
    target_rule: str = Field(min_length=5, max_length=300)
    sessions: list[Literal["Asia", "London", "NY_AM", "NY_Lunch", "NY_PM"]] = Field(default_factory=list)
    max_spread_points: int = Field(default=40, ge=1, le=1000)
    max_trades_per_day: int = Field(default=2, ge=1, le=20)
    notes: str = Field(default="", max_length=2000)


class GenOut(BaseModel):
    code: str = Field(max_length=120_000)
    notes: str = Field(max_length=2000)
    assumptions: list[str] = Field(max_length=10)


# ---------------------------------------------------------------- deterministic review
CHECKS: list[tuple[str, str, Any]] = [
    ("magic", "Numéro magique en paramètre (770077 par défaut) et utilisé", lambda c: re.search(r"input\s+(long|ulong|int)\s+InpMagic\s*=\s*770077", c) and re.search(r"SetExpertMagicNumber|\.magic\s*=|InpMagic", c)),
    ("no_dll", "Aucune DLL ni appel réseau", lambda c: not re.search(r"#import|WebRequest|Socket(Create|Connect)|ShellExecute", c)),
    ("retcode", "Résultat de chaque ordre vérifié", lambda c: not re.search(r"OrderSend|\.Buy\(|\.Sell\(|PositionOpen", c) or re.search(r"ResultRetcode|retcode", c)),
    ("lots", "Lot normalisé (min, pas, max)", lambda c: all(k in c for k in ("SYMBOL_VOLUME_MIN", "SYMBOL_VOLUME_STEP", "SYMBOL_VOLUME_MAX"))),
    ("risk_sizing", "Taille calculée depuis le risque (valeur du tick)", lambda c: "SYMBOL_TRADE_TICK_VALUE" in c and "SYMBOL_TRADE_TICK_SIZE" in c),
    ("stops_level", "Distance minimale du stop respectée", lambda c: "SYMBOL_TRADE_STOPS_LEVEL" in c),
    ("no_martingale", "Ni martingale ni grille", lambda c: not re.search(r"(?i)martingale|grid|lots?\s*\*=\s*[2-9]|lot\s*=\s*lot\s*\*\s*2", c)),
    ("new_bar", "Décisions à la clôture d'une bougie", lambda c: re.search(r"iTime\s*\(|CopyRates|isNewBar|IsNewBar", c)),
    ("ny_time", "Heure de New York depuis TimeGMT", lambda c: "TimeGMT" in c),
    ("spread", "Filtre de spread", lambda c: "SYMBOL_SPREAD" in c),
    ("lifecycle", "OnInit valide les paramètres, OnDeinit présent", lambda c: "OnInit" in c and "OnDeinit" in c and "INIT_" in c),
]


def review(code: str) -> dict[str, Any]:
    results = [{"key": k, "label": label, "ok": bool(fn(code))} for k, label, fn in CHECKS]
    return {"passed": all(r["ok"] for r in results), "failed": [r["label"] for r in results if not r["ok"]], "checks": results}


# ---------------------------------------------------------------- compiler adapters
class Compiler(Protocol):
    available: bool

    def compile(self, name: str, code: str) -> dict[str, Any]: ...


class UnavailableCompiler:
    available = False

    def compile(self, name: str, code: str) -> dict[str, Any]:
        return {"ok": None, "errors": [], "warnings": [], "log": "compilateur indisponible : configurez le pont Windows (HF_MQL_COMPILER_URL)"}


class RemoteCompiler:
    """The Windows host runs ``python -m hedgefund.saas compile-server`` next to MetaTrader 5."""

    available = True

    def __init__(self, url: str, token: str):
        self.url, self.token = url.rstrip("/"), token

    def compile(self, name: str, code: str) -> dict[str, Any]:
        try:
            r = requests.post(f"{self.url}/compile", json={"name": name, "code": code}, headers={"Authorization": f"Bearer {self.token}"}, timeout=180)
            r.raise_for_status()
            return r.json()
        except requests.RequestException as e:
            return {"ok": None, "errors": [], "warnings": [], "log": f"pont de compilation injoignable : {e}"}


def parse_metaeditor_log(text: str) -> dict[str, Any]:
    errors = [line.strip() for line in text.splitlines() if re.search(r"\berror\b", line, re.I) and not re.search(r"\b0 errors?\b", line, re.I)]
    warnings = [line.strip() for line in text.splitlines() if re.search(r"\bwarning\b", line, re.I) and not re.search(r"\b0 warnings?\b", line, re.I)]
    m = re.search(r"(\d+)\s+errors?,\s*(\d+)\s+warnings?", text, re.I)
    ok = (int(m.group(1)) == 0) if m else not errors
    return {"ok": ok, "errors": errors[:30], "warnings": warnings[:30], "log": text[-4000:]}


def compile_local(metaeditor: str, experts_dir: str, name: str, code: str) -> dict[str, Any]:
    """On the Windows host: ``metaeditor64.exe /compile:"file.mq5" /log`` (MetaQuotes docs)."""
    safe = re.sub(r"[^A-Za-z0-9_-]", "_", name)[:60] or "ea"
    folder = Path(experts_dir) / "AlphaEdge"
    folder.mkdir(parents=True, exist_ok=True)
    src = folder / f"{safe}.mq5"
    src.write_text(code, encoding="utf-8")
    log = src.with_suffix(".log")
    subprocess.run([metaeditor, f"/compile:{src}", f"/log:{log}"], capture_output=True, timeout=170, check=False)
    text = log.read_text(encoding="utf-16", errors="replace") if log.exists() else ""
    return parse_metaeditor_log(text)


def make_compiler() -> Compiler:
    url, tok = os.environ.get("HF_MQL_COMPILER_URL", "").strip(), os.environ.get("HF_MQL_COMPILER_TOKEN", "").strip()
    return RemoteCompiler(url, tok) if url and tok else UnavailableCompiler()


def fingerprint(errors: list[str], failed: list[str]) -> str:
    norm = sorted(re.sub(r"\(\d+,\d+\)|\d+", "#", e) for e in errors) + sorted(failed)
    return hashlib.sha256(json.dumps(norm).encode()).hexdigest()[:16]


def model_card(spec: dict[str, Any], state: dict[str, Any]) -> str:
    rv = state.get("review") or {}
    cp = state.get("compile") or {}
    status = "compilé, non testé" if cp.get("ok") else "compilation non vérifiée" if cp.get("ok") is None else "ne compile pas"
    lines = [
        f"# Model card — EA {spec['name']}", "", f"Statut : **{status}**. Aucune performance n'est revendiquée : backtest, walk-forward et 3 mois de réel suivi restent à faire (skill backtest-protocol).", "",
        "## But et périmètre", f"Symboles : {', '.join(spec['symbols'])} ; unité de temps : {spec['timeframe']} ; sens : {spec['direction']} ; sessions : {', '.join(spec['sessions']) or 'toutes'}.", "",
        "## Règles (spécification validée par un humain)", *[f"- Entrée : {r}" for r in spec["entry_rules"]], *[f"- Sortie : {r}" for r in spec["exit_rules"]],
        f"- Stop : {spec['stop_rule']}", f"- Objectif : {spec['target_rule']}", f"- Risque : {spec['risk_pct']} % du solde par trade, {spec['max_trades_per_day']} trade(s) par jour au plus, spread maximal {spec['max_spread_points']} points.", "",
        "## Vérifications déterministes", *[f"- {'✔' if c['ok'] else '✘'} {c['label']}" for c in rv.get("checks", [])], "",
        "## Génération", f"Tours : {state.get('round', 0)} ; hypothèses d'interprétation : {'; '.join(state.get('assumptions') or []) or 'aucune'}.", "",
        "## Limites connues", "- Code généré par un modèle puis vérifié par règles et compilateur : une revue humaine reste nécessaire.",
        "- Les valeurs de tick et le spread dépendent du broker : tester chez le broker réel.", "- Interdit en prop firm si la firme refuse les EA de tiers : vérifier son règlement.",
    ]
    return "\n".join(lines)


# ---------------------------------------------------------------- graph G2
class G2State(BaseModel):
    trace_id: str
    spec_id: str
    spec: dict[str, Any]
    round: int = 0
    code: Optional[str] = None
    notes: Optional[str] = None
    assumptions: list[str] = []
    review: Optional[dict[str, Any]] = None
    compile: Optional[dict[str, Any]] = None
    feedback: Optional[str] = None
    fingerprints: list[str] = []
    verdict: Optional[str] = None
    approval: Optional[dict[str, Any]] = None
    output: Optional[dict[str, Any]] = None


def build_g2(saas: SaaS, factory: "EAFactory") -> Any:
    from langgraph.graph import END, START, StateGraph
    from langgraph.types import interrupt

    spec_model = saas.models.get("ea_factory")
    system = saas.prompts.get("ea_factory", "")

    @node("génération du code")
    def generate(state: G2State, ctx: RunContext) -> dict[str, Any]:
        user = "Spécification validée (données) :\n<spec>\n" + json.dumps(state.spec, ensure_ascii=False) + "\n</spec>"
        if state.code and state.feedback:
            user += "\n\nVersion précédente :\n<code>\n" + state.code[:60_000] + "\n</code>\n\nRetour de l'évaluateur :\n<retour>\n" + state.feedback + "\n</retour>"
        res = saas.llm.run(spec_model, system, user, GenOut, ctx.budget)
        return {"code": res.data.code, "notes": res.data.notes, "assumptions": res.data.assumptions, "round": state.round + 1}

    @node("revue déterministe")
    def check(state: G2State, ctx: RunContext) -> dict[str, Any]:
        return {"review": review(state.code or "")}

    @node("compilation")
    def compile_(state: G2State, ctx: RunContext) -> dict[str, Any]:
        if not state.review["passed"]:
            return {"compile": {"ok": False, "errors": [], "warnings": [], "log": "non compilé : revue en échec"}}
        return {"compile": factory.compiler.compile(state.spec["name"], state.code or "")}

    @node("évaluateur")
    def evaluate(state: G2State, ctx: RunContext) -> dict[str, Any]:
        errs = state.compile.get("errors") or []
        failed = state.review["failed"]
        if state.review["passed"] and state.compile.get("ok") is not False:
            return {"verdict": "READY_FOR_DEMO" if state.compile.get("ok") else "REVIEWED_NOT_COMPILED", "feedback": None}
        fp = fingerprint(errs, failed)
        if fp in state.fingerprints:
            return {"verdict": "NEEDS_WORK", "feedback": "non-progrès : mêmes erreurs deux fois", "fingerprints": [*state.fingerprints, fp]}
        if state.round >= MAX_ROUNDS:
            return {"verdict": "NEEDS_WORK", "feedback": f"{MAX_ROUNDS} tours atteints", "fingerprints": [*state.fingerprints, fp]}
        fb = "\n".join([*(f"Revue : {x}" for x in failed), *(f"Compilation : {e}" for e in errs[:20])])
        return {"verdict": None, "feedback": fb, "fingerprints": [*state.fingerprints, fp]}

    def after_eval(state: G2State) -> str:
        return "generate" if state.verdict is None else "card"

    @node("model card")
    def card(state: G2State, ctx: RunContext) -> dict[str, Any]:
        mc = model_card(state.spec, state.model_dump())
        out = {"verdict": state.verdict, "rounds": state.round, "review": state.review, "compile": {k: state.compile.get(k) for k in ("ok", "errors", "warnings")},
               "notes": state.notes, "assumptions": state.assumptions, "model_card": mc, "code": state.code, "spec_id": state.spec_id, "trace_id": state.trace_id}
        with saas.db.tenant(ctx.tenant_id) as s:
            s.insert(lab_reports, {"id": state.trace_id, "user_id": ctx.user_id, "kind": "ea_factory", "title": f"EA {state.spec['name']} — {state.verdict}", "body": out, "created_at": now_ms()})
        return {"output": out}

    @node("approbation pour la démo")
    def approve(state: G2State, ctx: RunContext) -> dict[str, Any]:
        if state.verdict != "READY_FOR_DEMO":
            return {}
        d = interrupt({"message": "Relisez le code et la model card, puis approuvez la mise en démo (compte démo uniquement)."})
        return {"approval": d}

    @node("audit")
    def audit(state: G2State, ctx: RunContext) -> dict[str, Any]:
        write_audit(saas.db, ctx.tenant_id, state.trace_id, {"graph": "G2", "request": {"spec_id": state.spec_id}, "evidence": {"review": state.review, "compile_ok": (state.compile or {}).get("ok")},
                                                             "version": saas.manifest.fingerprint, "guardrail_decisions": [], "risk_gate": None,
                                                             "conclusion": {"verdict": state.verdict, "rounds": state.round}, "autonomy_tier": "PROPOSE", "human_approval": state.approval})
        return {"output": {**(state.output or {}), "approval": state.approval}}

    g = StateGraph(G2State)
    for name, fn in (("generate", generate), ("check", check), ("compile", compile_), ("evaluate", evaluate), ("card", card), ("approve", approve), ("audit", audit)):
        g.add_node(name, fn)
    g.add_edge(START, "generate")
    g.add_edge("generate", "check")
    g.add_edge("check", "compile")
    g.add_edge("compile", "evaluate")
    g.add_conditional_edges("evaluate", after_eval, {"generate": "generate", "card": "card"})
    g.add_edge("card", "approve")
    g.add_edge("approve", "audit")
    g.add_edge("audit", END)
    return g.compile(checkpointer=make_checkpointer(saas))


class EAFactory:
    def __init__(self, saas: SaaS, compiler: Compiler | None = None):
        self.saas = saas
        self.compiler = compiler or make_compiler()
        self._graph = None

    @property
    def graph(self) -> Any:
        if self._graph is None:
            self._graph = build_g2(self.saas, self)
        return self._graph

    def save_spec(self, acc: Access, spec: StrategySpec) -> dict[str, Any]:
        acc.require("ea_factory", "Usine EA")
        with self.saas.db.tenant(acc.tenant_id) as s:
            prev = [r for r in s.select(strategy_specs, {"user_id": acc.member_id}) if r["name"] == spec.name]
            sid = new_id("spec")
            s.insert(strategy_specs, {"id": sid, "user_id": acc.member_id, "name": spec.name, "version": 1 + max((r["version"] for r in prev), default=0), "body": spec.model_dump(), "created_at": now_ms()})
            return s.one(strategy_specs, {"id": sid})

    def specs(self, acc: Access) -> list[dict[str, Any]]:
        with self.saas.db.tenant(acc.tenant_id) as s:
            return s.select(strategy_specs, {"user_id": acc.member_id}, order_by=desc(strategy_specs.c.created_at), limit=50)

    def start(self, acc: Access, spec_id: str) -> dict[str, Any]:
        acc.require("ea_factory", "Usine EA")
        if not self.saas.llm.available:
            raise ValueError("usine EA indisponible : aucun modèle configuré")
        with self.saas.db.tenant(acc.tenant_id) as s:
            spec = s.one(strategy_specs, {"id": spec_id, "user_id": acc.member_id})
        if spec is None:
            raise LookupError("spécification introuvable")
        self.saas.consume(acc, "ea_run")
        trace = new_id("tr")
        self.saas.queue.enqueue("g2_ea", {"tenant_id": acc.tenant_id, "user_id": acc.member_id, "spec_id": spec_id, "spec": spec["body"], "trace_id": trace, "plan": acc.plan,
                                          "entitlements": sorted(acc.entitlements)}, tenant_id=acc.tenant_id, priority=2, idem_key=f"g2:{trace}", max_attempts=1)
        if self.saas.worker is None:
            self.saas.run_inline()
        return {"trace_id": trace}

    def run_job(self, job: dict[str, Any]) -> dict[str, Any]:
        p = job["payload"]
        budget = Budget(max_llm_calls=MAX_ROUNDS, max_input_tokens=400_000, max_output_tokens=120_000, deadline_s=45 * 60, max_tool_calls=0)
        tid, status, _ = run_graph(self.saas, self.graph, "G2", p["tenant_id"], p["user_id"], {"spec_id": p["spec_id"], "spec": p["spec"]}, budget, trace_id=p["trace_id"],
                                   entitlements=frozenset(p.get("entitlements", [])), plan=p.get("plan", "gratuit"))
        self.saas.add_cost(p["tenant_id"], "ea_run", budget.cost_usd)
        return {"trace_id": tid, "status": status}

    def runs(self, acc: Access, limit: int = 20) -> list[dict[str, Any]]:
        with self.saas.db.tenant(acc.tenant_id) as s:
            rows = s.select(agent_runs, {"user_id": acc.member_id, "graph": "G2"}, order_by=desc(agent_runs.c.created_at), limit=limit)
        return [{"id": r["id"], "status": r["status"], "created_at": r["created_at"], "verdict": (r["output"] or {}).get("verdict"), "error": r["error"]} for r in rows]

    def get(self, acc: Access, trace_id: str) -> dict[str, Any]:
        with self.saas.db.tenant(acc.tenant_id) as s:
            run = s.one(agent_runs, {"id": trace_id, "user_id": acc.member_id, "graph": "G2"})
            rep = s.one(lab_reports, {"id": trace_id})
        if run is None:
            raise LookupError("exécution introuvable")
        report = {**rep["body"], "approval": (run["output"] or {}).get("approval")} if rep else None
        return {"id": trace_id, "status": run["status"], "error": run["error"], "report": report, "cost_usd": run["cost_usd"]}

    def approve(self, acc: Access, trace_id: str, decision: str) -> dict[str, Any]:
        self.get(acc, trace_id)
        resume_graph(self.saas, self.graph, acc.tenant_id, acc.member_id, trace_id, {"decision": decision, "by": acc.member_id, "at": now_ms()}, entitlements=acc.entitlements, plan=acc.plan)
        return self.get(acc, trace_id)


class StartIn(BaseModel):
    spec_id: str = Field(min_length=4, max_length=40)


class ApproveIn(BaseModel):
    decision: str = Field(pattern=r"^(approved|rejected)$")


class CompileIn(BaseModel):
    name: str = Field(min_length=1, max_length=60)
    code: str = Field(min_length=10, max_length=200_000)


def mount(ctx: ApiContext) -> None:
    app, saas = ctx.app, ctx.saas
    f: EAFactory = saas.modules["ea_factory"]
    acc_dep = ctx.acc()

    @app.post("/api/app/ea/specs")
    def save(body: StrategySpec, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: f.save_spec(acc, body))

    @app.get("/api/app/ea/specs")
    def specs(acc: Access = Depends(acc_dep)) -> list[dict]:  # noqa: B008
        return f.specs(acc)

    @app.post("/api/app/ea/runs")
    def start(body: StartIn, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: f.start(acc, body.spec_id))

    @app.get("/api/app/ea/runs")
    def runs(acc: Access = Depends(acc_dep)) -> list[dict]:  # noqa: B008
        return f.runs(acc)

    @app.get("/api/app/ea/runs/{trace_id}")
    def get(trace_id: str, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: f.get(acc, trace_id[:40]))

    @app.post("/api/app/ea/runs/{trace_id}/approve")
    def approve(trace_id: str, body: ApproveIn, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: f.approve(acc, trace_id[:40], body.decision))


def compile_server_app(metaeditor: str, experts_dir: str, token: str) -> Any:
    """The small HTTP service of the Windows host that compiles MQL5 (no trading function)."""
    import hmac

    from fastapi import FastAPI

    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

    @app.post("/compile")
    def compile_(body: CompileIn, request: Request) -> dict:
        got = request.headers.get("authorization", "")[7:]
        if not token or not hmac.compare_digest(got, token):
            raise HTTPException(401, "jeton invalide")
        with tempfile.TemporaryDirectory():
            return compile_local(metaeditor, experts_dir, body.name, body.code)

    return app


def install(saas: SaaS) -> EAFactory:
    f = EAFactory(saas)
    saas.modules["ea_factory"] = f
    saas.handlers["g2_ea"] = f.run_job
    return f


ROUTERS.append(mount)

"""Intent router: rules first (keywords, the button the member clicked), a small model only
when the rules cannot decide. It never answers; it picks one path and says why."""

from __future__ import annotations

import re
from typing import Any

from fastapi import Depends
from pydantic import BaseModel, Field

from hedgefund.saas import guardrails as GR
from hedgefund.saas.api import ROUTERS, ApiContext, guard
from hedgefund.saas.harness import Budget, Tracer, finish_run, start_run
from hedgefund.saas.llm import LLMError
from hedgefund.saas.schemas import RouteDecision, RouterLLMOut
from hedgefund.saas.service import Access, SaaS

TARGET = {
    "journal_review": "coach", "setup_analysis": "analyste", "learn": "mentor", "risk_check": "risk_service", "research": "research",
    "ea_factory": "ea_factory", "account_support": "support", "out_of_scope": "refuse", "advice_request": "refuse",
}
RULES: list[tuple[str, str]] = [
    ("ea_factory", r"\b(ea|expert advisor|mql5|mq5|robot|metaeditor|compil)"),
    ("risk_check", r"\b(taille de position|lot|lots|risque|drawdown|prop ?firm|ftmo|fundednext|perte journali|challenge)\b"),
    ("setup_analysis", r"\b(analy[sz]e|setup|fvg|sweep|mss|silver bullet|macro breaker|killzone|structure|liquidit)\w*.*\b(xau|gold|or|nas|nq|us30|us500|eurusd|gbpusd|ger40)\w*"),
    ("journal_review", r"\b(journal|mes trades|ma semaine|mes erreurs|revue|discipline|statisti|performance|revenge|overtrading|lecon|lecons)\b"),
    ("learn", r"\b(c'? ?est quoi|qu'? ?est[- ]ce|explique|definition|comprendre|apprendre|cours|module|formation|comment (fonctionne|marche)|what is)\b"),
    ("learn", r"\b(fvg|bisi|sibi|order block|breaker|bpr|ote|mss|choch|bos|killzone|silver bullet|macro|liquidite|premium|discount|ipda|amd|smt|cisd)\b"),
    ("research", r"\b(news|actualit|calendrier|nfp|cpi|fomc|annonce|macro(economi)?|dxy|taux)\b"),
    ("account_support", r"\b(paiement|wave|abonnement|facture|mot de passe|compte membre|acces|rembourse)\b"),
]
ADVICE_REPLY = (
    "Je ne peux pas vous dire quoi acheter ou vendre : ce serait un conseil en investissement personnalisé. "
    "Je peux en revanche analyser un setup selon les règles ICT, revoir votre journal ou vous expliquer un concept."
)


def by_rules(text: str) -> RouteDecision | None:
    n = GR._norm(text)
    if GR.check_input(text).flags & {"advice_request"}:
        return RouteDecision(intent="advice_request", target="refuse", reason="demande de conseil personnalisé", confidence=95)
    for intent, rx in RULES:
        if re.search(rx, n):
            return RouteDecision(intent=intent, target=TARGET[intent], reason=f"mots-clés : {intent}", confidence=80)
    return None


class RouteIn(BaseModel):
    message: str = Field(min_length=1, max_length=2000)


class Router:
    def __init__(self, saas: SaaS):
        self.saas = saas

    def route(self, acc: Access, text: str) -> dict[str, Any]:
        d = GR.check_input(text, max_len=2000)
        if d.action == "BLOCK":
            raise ValueError("; ".join(d.reasons))
        dec = by_rules(d.text or text)
        if dec is None and self.saas.llm.available:
            budget = Budget(max_llm_calls=1, max_input_tokens=3000, max_output_tokens=200, deadline_s=10)
            tid = start_run(self.saas.db, acc.tenant_id, acc.member_id, "router", {"chars": len(text)}, self.saas.manifest.fingerprint)
            try:
                with Tracer(self.saas.db, acc.tenant_id, tid).span("routeur", kind="node"):
                    res = self.saas.llm.run(self.saas.models.get("router"), self.saas.prompts.get("router", ""), "<message>\n" + (d.text or text) + "\n</message>", RouterLLMOut, budget)
                out: RouterLLMOut = res.data
                dec = RouteDecision(intent=out.intent, target=TARGET[out.intent], reason=out.reason[:200], confidence=max(0, min(100, out.confidence)), by="llm")
                finish_run(self.saas.db, acc.tenant_id, tid, "done", dec.model_dump(), budget)
            except LLMError as e:
                finish_run(self.saas.db, acc.tenant_id, tid, "failed", None, budget, error=str(e))
        if dec is None or dec.confidence < 60:
            dec = RouteDecision(intent="out_of_scope", target="refuse", reason="demande ambiguë : choisissez un service", confidence=0, by="menu")
            return {**dec.model_dump(), "menu": ["journal_review", "setup_analysis", "learn", "risk_check"], "flags": sorted(d.flags)}
        out = {**dec.model_dump(), "flags": sorted(d.flags)}
        if dec.intent == "advice_request":
            out["reply"] = ADVICE_REPLY + " " + GR.DISCLAIMER
        return out


def mount(ctx: ApiContext) -> None:
    app, saas = ctx.app, ctx.saas
    r: Router = saas.modules["router"]
    acc_dep = ctx.acc()

    @app.post("/api/app/ask")
    def ask(body: RouteIn, acc: Access = Depends(acc_dep)) -> dict:  # noqa: B008
        return guard(lambda: r.route(acc, body.message))


def install(saas: SaaS) -> Router:
    r = Router(saas)
    saas.modules["router"] = r
    return r


ROUTERS.append(mount)

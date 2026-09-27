"""P2: EA factory (graph G2 anchored in the checklist and the compiler), adversarial debate
(can only downgrade), read-only public API, MCP servers."""

import asyncio

from fastapi.testclient import TestClient

from hedgefund.saas import ea_factory as F
from hedgefund.saas.mcp_servers import build_server
from saas_helpers import grant, make_app, operator, register

GOOD = """
input long InpMagic = 770077;   // numéro magique
input double InpRiskPct = 0.5;
#include <Trade\\Trade.mqh>
CTrade trade;
int OnInit() { if(InpRiskPct <= 0) return(INIT_PARAMETERS_INCORRECT); trade.SetExpertMagicNumber(InpMagic); return(INIT_SUCCEEDED); }
void OnDeinit(const int reason) {}
datetime last = 0;
void OnTick() {
  if(iTime(_Symbol, PERIOD_M5, 0) == last) return; last = iTime(_Symbol, PERIOD_M5, 0);
  if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > 40) return;
  datetime gmt = TimeGMT();
  double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
  double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
  long lvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
  if(!trade.Buy(0.1, _Symbol, 0, 0, 0)) PrintFormat("erreur %d", trade.ResultRetcode());
}
"""
BAD = GOOD.replace("SYMBOL_VOLUME_STEP", "SYMBOL_POINT").replace("TimeGMT", "TimeCurrent")
SPEC = {"name": "SB Londres", "symbols": ["XAUUSD"], "timeframe": "M5", "entry_rules": ["sweep puis MSS dans la fenêtre 03:00-04:00 NY"], "exit_rules": ["objectif ou invalidation"],
        "stop_rule": "sous l'extrême du sweep", "target_rule": "liquidité opposée, RR 2 minimum", "sessions": ["London"]}


class FakeCompiler:
    available = True

    def __init__(self, ok=True):
        self.ok, self.calls = ok, 0

    def compile(self, name, code):
        self.calls += 1
        return {"ok": self.ok, "errors": [] if self.ok else ["SB.mq5(12,3) : error 256: undeclared identifier"], "warnings": [], "log": "0 errors, 0 warnings" if self.ok else "1 errors"}


def gen(code):
    return {"code": code, "notes": "version", "assumptions": ["fenêtre en heure de New York"]}


def _elite(tmp_path, turns):
    c, eng, saas, clock = make_app(tmp_path, turns=turns)
    h = register(c)
    op = TestClient(c.app)
    grant(op, operator(op), 1, "quant_elite")
    return c, h, saas


def test_review_and_metaeditor_log():
    assert F.review(GOOD)["passed"] is True
    r = F.review(BAD)
    assert not r["passed"] and "Lot normalisé (min, pas, max)" in r["failed"] and "Heure de New York depuis TimeGMT" in r["failed"]
    assert not F.review(GOOD + '\n#import "evil.dll"\n')["passed"]
    assert not F.review(GOOD + "\nlot *= 2; // martingale\n")["passed"]
    ok = F.parse_metaeditor_log("Result: 0 errors, 1 warnings")
    ko = F.parse_metaeditor_log("SB.mq5(12,3) : error 256: undeclared identifier 'x'\nResult: 1 errors, 0 warnings")
    assert ok["ok"] is True and ko["ok"] is False and ko["errors"]


def test_g2_loop_fixes_review_then_compiles_and_waits_for_approval(tmp_path):
    c, h, saas = _elite(tmp_path, [gen(BAD), gen(GOOD)])
    saas.modules["ea_factory"].compiler = FakeCompiler()
    spec = c.post("/api/app/ea/specs", json=SPEC, headers=h).json()
    assert spec["version"] == 1
    tid = c.post("/api/app/ea/runs", json={"spec_id": spec["id"]}, headers=h).json()["trace_id"]
    run = c.get(f"/api/app/ea/runs/{tid}").json()
    rep = run["report"]
    assert run["status"] == "waiting" and rep["verdict"] == "READY_FOR_DEMO" and rep["rounds"] == 2
    assert "compilé, non testé" in rep["model_card"] and "Aucune performance" in rep["model_card"]
    second = saas.llm.client.requests[1]["messages"][0]["content"]
    assert "Lot normalisé" in second and "<code>" in second  # the evaluator's feedback reached the generator
    assert [(r["id"], r["status"]) for r in c.get("/api/app/ea/runs").json()] == [(tid, "waiting")]
    steps = c.get(f"/api/app/runs/{tid}").json()["steps"]
    assert steps[-1]["name"] == "approbation pour la démo" and steps[-1]["status"] == "waiting"  # an interrupt is not an error
    done = c.post(f"/api/app/ea/runs/{tid}/approve", json={"decision": "approved"}, headers=h).json()
    assert done["status"] == "done" and done["report"]["approval"]["decision"] == "approved"
    assert c.get("/api/app/ea/runs").json()[0]["verdict"] == "READY_FOR_DEMO"


def test_g2_stops_on_no_progress(tmp_path):
    c, h, saas = _elite(tmp_path, [gen(BAD), gen(BAD), gen(BAD)])
    saas.modules["ea_factory"].compiler = FakeCompiler()
    spec = c.post("/api/app/ea/specs", json=SPEC, headers=h).json()
    tid = c.post("/api/app/ea/runs", json={"spec_id": spec["id"]}, headers=h).json()["trace_id"]
    rep = c.get(f"/api/app/ea/runs/{tid}").json()["report"]
    assert rep["verdict"] == "NEEDS_WORK" and rep["rounds"] == 2 and saas.modules["ea_factory"].compiler.calls == 0


def test_g2_access_and_model_required(tmp_path):
    c, eng, saas, clock = make_app(tmp_path)
    h = register(c)
    assert c.post("/api/app/ea/specs", json=SPEC, headers=h).status_code == 403
    op = TestClient(c.app)
    grant(op, operator(op), 1, "quant_elite")
    spec = c.post("/api/app/ea/specs", json=SPEC, headers=h).json()
    r = c.post("/api/app/ea/runs", json={"spec_id": spec["id"]}, headers=h)
    assert r.status_code == 400 and "aucun modèle" in r.json()["detail"]


NOW_SB = 1_791_900_000_000 - 7 * 3_600_000 + 15 * 60_000


def test_debate_can_only_downgrade(tmp_path):
    turns = [{"summary": "Setup selon les règles.", "plan_alignment": [], "points_to_check": [], "caveats": []},
             {"arguments": ["La liquidité a été prise avant l'entrée."]}, {"arguments": ["Le biais H1 n'est pas aligné."]},
             {"decision": "downgrade", "reasons": ["arguments contre sérieux"]}]
    c, eng, saas, clock = make_app(tmp_path, turns=turns, now=NOW_SB)
    h = register(c)
    op = TestClient(c.app)
    grant(op, operator(op), 1, "quant_elite")
    c.post("/api/app/accounts", json={"label": "Démo", "starting_balance": 10000}, headers=h)
    saas.config["analysis"]["debate"] = True
    tid = c.post("/api/app/analyses", json={"symbol": "XAUUSD"}, headers=h).json()["trace_id"]
    card = c.get(f"/api/app/analyses/{tid}").json()["card"]
    assert card["debate"]["decision"] == "downgrade" and card["label"] in ("PARTIAL",)
    assert "débat" in " ".join(card["caveats"]) and "même famille" in card["debate"]["caveat"]


def test_public_api_is_read_only_and_scoped(tmp_path):
    c, eng, saas, clock = make_app(tmp_path)
    h = register(c)
    assert c.post("/api/app/tokens/api", json={"label": "script"}, headers=h).status_code == 403
    op = TestClient(c.app)
    grant(op, operator(op), 1, "quant_elite")
    tok = c.post("/api/app/tokens/api", json={"label": "script", "scopes": ["read:stats"]}, headers=h).json()["token"]
    m = TestClient(c.app)
    assert m.get("/api/v1/stats", headers={"Authorization": f"Bearer {tok}"}).json()["kpis"]["n"] == 0
    assert m.get("/api/v1/trades", headers={"Authorization": f"Bearer {tok}"}).status_code == 401  # scope missing
    assert m.post("/api/v1/trades", headers={"Authorization": f"Bearer {tok}"}).status_code in (404, 405)
    assert m.get("/api/v1/stats").status_code == 401


def test_mcp_server_scopes_tenant_on_the_command_line(tmp_path):
    c, eng, saas, clock = make_app(tmp_path)
    register(c)
    server = build_server(saas, "journal", "t_m1", 1)
    names = [t.name for t in asyncio.run(server.list_tools())]
    assert "journal_query_trades" in names and not any(n.startswith("ict") for n in names)
    out = asyncio.run(server.call_tool("perf_kpis", {"args": {"days": 7}}))
    assert '"ok": true' in out.content[0].text

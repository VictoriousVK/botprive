"""The SaaS mounted in the platform: member access, plans, runs, operator overview."""

from fastapi.testclient import TestClient

from hedgefund.saas.harness import Tracer, finish_run, start_run
from saas_helpers import grant, make_app, operator, register


def test_member_sees_plan_limits_and_features(tmp_path):
    c, eng, saas, _ = make_app(tmp_path)
    assert c.get("/api/app/me").status_code == 401
    register(c)
    me = c.get("/api/app/me").json()
    assert me["plan"] == "gratuit" and me["limits"]["coach"] == 5 and me["ai"] is False
    assert me["market"] == {"source": "simulation", "synthetic": True}
    op = TestClient(c.app)
    grant(op, operator(op), 1, "pro_trader")
    me = c.get("/api/app/me").json()
    assert me["plan"] == "pro_trader" and me["features"]["lab"] is True and me["features"]["ea_factory"] is False


def test_runs_are_private_to_their_tenant(tmp_path):
    c, eng, saas, _ = make_app(tmp_path)
    register(c)
    tenant = c.get("/api/app/me").json()["tenant"]
    tid = start_run(saas.db, tenant, 1, "G3", {"x": 1}, saas.manifest.fingerprint)
    with Tracer(saas.db, tenant, tid).span("import"):
        pass
    finish_run(saas.db, tenant, tid, "done", {"ok": True})
    v = c.get(f"/api/app/runs/{tid}").json()
    assert v["status"] == "done" and [s["name"] for s in v["steps"]] == ["import"]
    body = c.get(f"/api/app/runs/{tid}/stream").text
    assert "event: step" in body and '"status": "done"' in body
    other = TestClient(c.app)
    register(other, "bob@example.com")
    assert other.get(f"/api/app/runs/{tid}").status_code == 404


def test_operator_overview(tmp_path):
    c, eng, saas, _ = make_app(tmp_path)
    assert c.get("/api/admin/saas/overview").status_code == 401
    oh = operator(c)
    ov = c.get("/api/admin/saas/overview", headers=oh).json()
    assert ov["database"] == "sqlite" and ov["manifest"]["fingerprint"].startswith("v-")

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


def test_a_queued_run_can_be_followed_before_a_worker_takes_it(tmp_path):
    c, eng, saas, _ = make_app(tmp_path)
    h = register(c)
    saas.worker = object()  # a background worker exists: nothing runs in the request
    tid = c.post("/api/app/coach/review", json={"days": 7}, headers=h).json()["trace_id"]
    assert c.get(f"/api/app/runs/{tid}").json()["status"] == "queued"
    assert c.get(f"/api/app/coach/reviews/{tid}").json() == {"id": tid, "status": "queued", "error": None, "verdict": None}
    saas.worker = None
    saas.run_inline()
    v = c.get(f"/api/app/runs/{tid}").json()
    assert v["status"] in ("waiting", "done") and v["steps"]
    assert len(c.get("/api/app/coach/reviews").json()) == 1  # the same run, not a second one


def test_a_dead_job_fails_its_run(tmp_path):
    from hedgefund.saas.harness import queue_run
    from hedgefund.saas.jobs import PermanentError

    c, eng, saas, _ = make_app(tmp_path)
    register(c)
    tenant = c.get("/api/app/me").json()["tenant"]

    def boom(job):
        raise PermanentError("données manquantes")

    saas.handlers["boom"] = boom
    queue_run(saas.db, tenant, 1, "G3", {}, saas.manifest.fingerprint, "tr_dead1")
    saas.queue.enqueue("boom", {"tenant_id": tenant, "trace_id": "tr_dead1"}, tenant_id=tenant)
    saas.run_inline()
    v = c.get("/api/app/runs/tr_dead1").json()
    assert v["status"] == "failed" and "données manquantes" in v["error"]


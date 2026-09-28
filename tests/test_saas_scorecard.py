"""The fast part of the scorecard must pass (the full one runs in CI: python -m hedgefund.saas eval)."""

from hedgefund.saas.evals import CATASTROPHIC, run_scorecard


def test_fast_scorecard_passes():
    rep = run_scorecard("fast")
    failed = [r for r in rep["rows"] if r["severity"] == CATASTROPHIC and not r["passed"]]
    assert rep["passed"] and not failed, rep["text"]

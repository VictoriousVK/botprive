"""Operator CLI:  python -m hedgefund <command>

  validate                         check config and every strategy spec
  org                              print departments and workflows
  backtest [--stress] [--perturb]  backtest specs (synthetic by default; --live-data for real)
  recalibrate                      fit + holdout-test + replay-test a Jev calibration bundle
  paper [--once | --replay N]      run the 24/7 loop (paper venue) or a synthetic replay
  status | health | report         operator views
  stages | promote | demote        strategy lifecycle
  approve                          decide an approval request from the research layer
  kill | reset-kill                kill switch
  calibration                      Jev calibration from resolved predictions
  research scan|memo|overnight     Opus 5.5 research (needs Anthropic credentials)
  verify-ledger                    check the audit ledger hash chain
"""

from __future__ import annotations

import argparse
import json
import signal
import sys
import threading
from pathlib import Path

from hedgefund.config import load_config
from hedgefund.core.clock import SimClock, SystemClock
from hedgefund.core.ledger import Kind, Ledger
from hedgefund.core.timeutil import DAY_MS, now_ms, utc_iso


def _cfg(args):
    return load_config(args.config)


def _specs(cfg, only: list[str] | None = None):
    from hedgefund.strategy.spec import load_specs

    specs = load_specs(cfg.strategy_dir)
    if only:
        missing = set(only) - {s.id for s in specs}
        if missing:
            sys.exit(f"unknown strategy ids: {sorted(missing)}")
        specs = [s for s in specs if s.id in only]
    return specs


def _data(args, cfg, specs):
    if getattr(args, "live_data", False):
        from hedgefund.data.sources import load_live_market_data

        symbols = sorted({s for spec in specs for s in spec.universe})
        return load_live_market_data(symbols, cfg.bar_interval, args.days)
    from hedgefund.data.synthetic import generate_market_data

    return generate_market_data(n_bars=args.bars, interval=cfg.bar_interval, seed=args.seed)


def _print_json(obj) -> None:
    print(json.dumps(obj, indent=2, sort_keys=True, default=str))


def cmd_validate(args) -> int:
    cfg = _cfg(args)
    bad = 0
    for spec in _specs(cfg):
        problems = spec.validate(set(cfg.instruments))
        print(f"{spec.id:28s} v{spec.version} stage={spec.stage.value:12s} {'OK' if not problems else problems}")
        bad += bool(problems)
    print(f"config {cfg.name!r} mode={cfg.mode.value} hash={cfg.source_hash} risk={cfg.risk}")
    return 1 if bad else 0


def cmd_org(args) -> int:
    from hedgefund.orchestration.departments import DEPARTMENTS
    from hedgefund.orchestration.workflows import WORKFLOWS

    for d in DEPARTMENTS:
        print(f"\n## {d.name}  [{d.layer}]\n  mandate: {d.mandate}\n  responsibilities: {'; '.join(d.responsibilities)}")
        print(f"  workflows: {', '.join(d.workflows)}\n  inputs: {'; '.join(d.inputs)}\n  outputs: {'; '.join(d.outputs)}\n  review: {d.review}")
    print("\n# Workflows")
    for w in WORKFLOWS:
        print(f"\n- {w.name} ({w.cadence}, {w.layer}, owner {w.owner})")
        for s in w.steps:
            print(f"    * {s}")
    return 0


def cmd_backtest(args) -> int:
    from hedgefund.backtest.engine import BacktestConfig, run_backtest
    from hedgefund.backtest.stress import backtest_evidence, cost_and_stress_evidence, param_perturbation, run_scenarios

    cfg = _cfg(args)
    specs = _specs(cfg, args.strategy)
    data = _data(args, cfg, specs)
    ledger = Ledger(cfg.ledger_path)
    trials = 1 + sum(1 for e in ledger.query(kind=Kind.BACKTEST) if set(e.payload.get("strategies", [])) == {s.id for s in specs})
    bt = BacktestConfig(seed=args.seed, n_trials=trials)
    res = run_backtest(data, specs, cfg, bt)
    label = "SYNTHETIC DATA - plumbing test, not evidence of edge" if data.synthetic else "real market data"
    print(f"\n=== Backtest ({label}); bars={len(res.equity)} trials counted for DSR={trials} ===")
    _print_json({k: v for k, v in res.metrics.items()})
    print("\nper strategy:")
    for sid, m in res.strategy_metrics.items():
        print(f"  {sid:28s} pnl {m['pnl']:>12,.0f}  sharpe {m['sharpe']:>6.2f}  maxDD {m['max_drawdown']:.2%}  fees {m['fees']:>9,.0f}  funding {m['funding_paid']:>9,.0f}  closes {m['closing_fills']}")
    print("\ntrades:", json.dumps(res.trades, default=str))
    print(f"decisions {res.decisions}, escalations {res.escalations}, risk events {res.risk_events}")
    print("\nJev calibration (resolved within the backtest):")
    for k, m in res.calibration.items():
        print(f"  {k:60s} n={m['n']:<5} brier={m['brier']:.3f} skill={m['brier_skill'] if m['brier_skill'] is None else round(m['brier_skill'], 3)}")
    evidence = backtest_evidence(res)
    if args.stress or args.perturb:
        scen = run_scenarios(data, specs, cfg, bt)
        print("\nstress scenarios:")
        for name, r in scen.items():
            print(f"  {name:14s} sharpe {r.metrics['sharpe']:>6.2f}  maxDD {r.metrics['max_drawdown']:.2%}  return {r.metrics['total_return']:+.2%}")
        perturb = {}
        if args.perturb and len(specs) == 1:
            perturb = param_perturbation(data, specs[0], cfg, bt=bt)
            print("\nparameter perturbation (+/-20%, Sharpe):", json.dumps(perturb))
        evidence |= cost_and_stress_evidence(scen, perturb, max_drawdown_limit=cfg.risk.max_drawdown_pct * 2)
    ledger.append(Kind.BACKTEST, {"strategies": [s.id for s in specs], "spec_hashes": {s.id: s.spec_hash for s in specs}, "synthetic": data.synthetic, "metrics": res.metrics, "evidence": evidence}, ts=now_ms())
    if args.evidence_out:
        Path(args.evidence_out).write_text(json.dumps(evidence, indent=2, default=str))
        print(f"\nevidence written to {args.evidence_out}")
    return 0


def cmd_recalibrate(args) -> int:
    from hedgefund.backtest.engine import BacktestConfig, run_backtest
    from hedgefund.calibration.recalibrate import RecalibratedJev, bundle_summary, propose_bundle
    from hedgefund.calibration.tracker import CalibrationTracker, Prediction
    from hedgefund.jev.reference import ReferenceJev

    cfg = _cfg(args)
    specs = _specs(cfg, args.strategy)
    data = _data(args, cfg, specs)
    base = ReferenceJev()
    # Collect resolved predictions from a full replay with the base engine.
    res_base = run_backtest(data, specs, cfg, BacktestConfig(record_ledger=True))
    tracker = CalibrationTracker(Ledger(":memory:"))
    resolved = {(e.payload["decision_id"], e.payload["question"]): e.payload["outcome"] for e in res_base.ledger.query(kind=Kind.CALIBRATION_OUTCOME)}
    for e in res_base.ledger.query(kind=Kind.CALIBRATION_PREDICTION):
        key = (e.payload["decision_id"], e.payload["question"])
        if key in resolved:
            p = {**e.payload, "legs": tuple(tuple(x) for x in e.payload["legs"])}
            tracker.resolved.append((Prediction(**p), resolved[key]))
    bundle = propose_bundle(tracker.resolved, base.model_version)
    _print_json(bundle_summary(bundle))
    if not bundle.maps:
        print("\nno map improved holdout Brier; nothing to deploy")
        return 0
    res_new = run_backtest(data, specs, cfg, BacktestConfig(), jev=RecalibratedJev(base, bundle))
    print(f"\nreplay: base sharpe {res_base.metrics['sharpe']:.2f} maxDD {res_base.metrics['max_drawdown']:.2%}  ->  recalibrated sharpe {res_new.metrics['sharpe']:.2f} maxDD {res_new.metrics['max_drawdown']:.2%}")
    path = bundle.save(cfg.var_dir / "calibration")
    improved = res_new.metrics["sharpe"] > res_base.metrics["sharpe"] and res_new.metrics["max_drawdown"] <= res_base.metrics["max_drawdown"] * 1.1
    rid = f"req_cal_{bundle.version}"
    desc = (
        f"enable calibration bundle {bundle.version}: replay sharpe {res_base.metrics['sharpe']:.2f} -> {res_new.metrics['sharpe']:.2f}, "
        f"maxDD {res_base.metrics['max_drawdown']:.2%} -> {res_new.metrics['max_drawdown']:.2%}; synthetic={data.synthetic}; "
        f"recommendation: {'approve for shadow' if improved and not data.synthetic else 'reject (replay did not improve or evidence is synthetic)'}"
    )
    Ledger(cfg.ledger_path).append(Kind.APPROVAL_REQUEST, {"request_id": rid, "status": "pending", "kind": "jev_schema_change", "target": str(path), "description": desc}, ts=now_ms(), ref=rid)
    print(f"bundle saved to {path} (NOT enabled). Approval request {rid}: {desc}")
    return 0


def cmd_paper(args) -> int:
    from hedgefund.ops.runner import FundRunner, LiveDataProvider, ReplayDataProvider

    cfg = _cfg(args)
    if args.replay:
        from hedgefund.data.synthetic import generate_market_data

        data = generate_market_data(n_bars=args.replay, interval=cfg.bar_interval, seed=args.seed)
        clock = SimClock(data.timeline()[0])
        ledger = Ledger(":memory:") if args.ephemeral else Ledger(cfg.ledger_path)
        runner = FundRunner(cfg, ReplayDataProvider(data), clock=clock, ledger=ledger, include_all_stages=True, persist_files=not args.ephemeral)
        print(f"synthetic replay over {args.replay} bars with ALL strategies (stage gates bypassed for the replay only)")
        for t in data.timeline():
            clock.set(t + 1_000)
            runner.run_once()
            runner.run_scheduled(clock.now_ms())
        from hedgefund.monitoring.report import daily_report

        st = runner.stack
        print(f"final NAV {st.portfolio.nav():,.2f}; kill switch {'ENGAGED: ' + st.kill_switch.reason if st.kill_switch.engaged else 'off'}\n")
        print(daily_report(runner.ledger, st.portfolio, {k: v.value for k, v in runner.stages.items()}, clock.now_ms(), synthetic=True))
        return 0
    specs = _specs(cfg)
    symbols = sorted({s for spec in specs for s in spec.universe})
    provider = LiveDataProvider(symbols, cfg.bar_interval, int(cfg.data.get("live_lookback_days", 220)))
    researcher = None
    if args.with_research:
        from hedgefund.research.opus import OpusResearcher

        researcher = OpusResearcher(model=cfg.research.get("model", "claude-opus-5-5"), effort=cfg.research.get("effort", "high"), max_tokens=int(cfg.research.get("max_tokens", 64000)))
    runner = FundRunner(cfg, provider, clock=SystemClock(), include_all_stages=args.all_stages, researcher=researcher)
    if args.once:
        _print_json(runner.run_once().__dict__)
        return 0
    stop = threading.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda *_: stop.set())
    print(f"running 24/7 in {cfg.mode.value} mode; Ctrl-C to stop. Heartbeat: {cfg.var_dir / 'heartbeat.json'}")
    runner.run_forever(stop)
    return 0


def cmd_status(args) -> int:
    from hedgefund.strategy.lifecycle import current_stage

    cfg = _cfg(args)
    ledger = Ledger(cfg.ledger_path)
    nav = ledger.query(kind=Kind.NAV, newest_first=True, limit=1)
    ks = cfg.kill_switch_path.exists()
    print(f"kill switch: {'ENGAGED ' + cfg.kill_switch_path.read_text() if ks else 'off'}")
    if nav:
        p = nav[0].payload
        print(f"last bar {utc_iso(p['bar_ts'])}  NAV {p['nav']:,.2f}  drawdown {p['drawdown']:.2%}")
        print("positions:", json.dumps(p["positions"]))
    else:
        print("no NAV snapshots yet (runner has not processed a bar)")
    for spec in _specs(cfg):
        print(f"  {spec.id:28s} {current_stage(spec, ledger).value}")
    decided = {e.payload.get("request_id") for e in ledger.query(kind=Kind.APPROVAL)}
    pending = [e.payload for e in ledger.query(kind=Kind.APPROVAL_REQUEST) if e.payload["request_id"] not in decided]
    print(f"pending approvals: {len(pending)}")
    for p in pending[:20]:
        print(f"  {p['request_id']}: {p.get('kind')} {p.get('target')} - {str(p.get('description'))[:120]}")
    hb = cfg.var_dir / "heartbeat.json"
    print("heartbeat:", hb.read_text() if hb.exists() else "none")
    return 0


def cmd_report(args) -> int:
    from hedgefund.monitoring.report import daily_report
    from hedgefund.ops.runner import replay_books
    from hedgefund.portfolio.book import Portfolio
    from hedgefund.strategy.lifecycle import current_stage

    cfg = _cfg(args)
    ledger = Ledger(cfg.ledger_path)
    pf = Portfolio(cfg.starting_nav, cfg.instruments)
    replay_books(ledger, pf)
    print(daily_report(ledger, pf, {s.id: current_stage(s, ledger).value for s in _specs(cfg)}, now_ms()))
    return 0


def cmd_stages(args) -> int:
    from hedgefund.strategy.lifecycle import GATES, current_stage

    cfg = _cfg(args)
    ledger = Ledger(cfg.ledger_path)
    for spec in _specs(cfg):
        cur = current_stage(spec, ledger)
        from hedgefund.strategy.spec import STAGE_ORDER

        nxt = STAGE_ORDER[cur.order + 1] if cur.order + 1 < len(STAGE_ORDER) - 1 else None
        print(f"{spec.id:28s} {cur.value:12s} next: {nxt.value if nxt else '-'}")
        if nxt and nxt in GATES:
            for c in GATES[nxt].checks:
                print(f"      needs {c.key} {c.op} {c.threshold if c.threshold is not None else ''} {c.why}")
            if GATES[nxt].real_data_required:
                print("      needs evidence from real market data (synthetic=false)")
            if GATES[nxt].requires_human:
                print("      needs a named human approval (--operator)")
    return 0


def cmd_promote(args, demote: bool = False) -> int:
    from hedgefund.strategy.lifecycle import Approval, transition
    from hedgefund.strategy.spec import Stage

    cfg = _cfg(args)
    ledger = Ledger(cfg.ledger_path)
    spec = _specs(cfg, [args.strategy])[0]
    evidence = json.loads(Path(args.evidence).read_text()) if getattr(args, "evidence", None) else {}
    approval = Approval(args.operator, args.reason, now_ms()) if getattr(args, "operator", None) else None
    res = transition(spec, Stage(args.to), evidence, ledger, now_ms(), approval=approval, reason=args.reason or "")
    print(f"{res.strategy_id}: {res.from_stage.value} -> {res.to_stage.value}: {'OK' if res.ok else 'REFUSED'}")
    for f in res.failures:
        print("  -", f)
    return 0 if res.ok else 1


def cmd_approve(args) -> int:
    cfg = _cfg(args)
    ledger = Ledger(cfg.ledger_path)
    if args.request_id == "risk_limits_change":
        payload = {"action": "risk_limits_change", "operator": args.operator, "reason": args.reason, "config_hash": cfg.source_hash, "risk_limits": vars(cfg.risk)}
    else:
        reqs = ledger.query(kind=Kind.APPROVAL_REQUEST, ref=args.request_id)
        if not reqs:
            sys.exit(f"no approval request {args.request_id}")
        payload = {"request_id": args.request_id, "decision": args.decision, "operator": args.operator, "reason": args.reason, "request": reqs[-1].payload}
    ledger.append(Kind.APPROVAL, payload, ts=now_ms(), ref=args.request_id)
    print("recorded:", json.dumps(payload, default=str)[:400])
    return 0


def cmd_kill(args) -> int:
    from hedgefund.risk.kill_switch import KillSwitch

    cfg = _cfg(args)
    ks = KillSwitch(cfg.kill_switch_path, Ledger(cfg.ledger_path), SystemClock())
    ks.engage(args.reason, f"cli:{args.operator or 'operator'}")
    print(f"kill switch ENGAGED ({cfg.kill_switch_path}); the runner will flatten all books on its next loop")
    return 0


def cmd_reset_kill(args) -> int:
    from hedgefund.risk.kill_switch import KillSwitch

    cfg = _cfg(args)
    ks = KillSwitch(cfg.kill_switch_path, Ledger(cfg.ledger_path), SystemClock())
    ks.reset(args.operator, args.reason)
    print("kill switch reset; restart the runner to resume trading")
    return 0


def cmd_calibration(args) -> int:
    from hedgefund.calibration.tracker import CalibrationTracker

    cfg = _cfg(args)
    rep = CalibrationTracker.from_ledger_outcomes(Ledger(cfg.ledger_path), since_ts=now_ms() - args.days * DAY_MS)
    _print_json(rep or {"note": "no resolved predictions yet"})
    return 0


def cmd_research(args) -> int:
    from hedgefund.research.opus import OpusResearcher
    from hedgefund.research.pipeline import market_evidence, record_result, spec_from_draft

    cfg = _cfg(args)
    ledger = Ledger(cfg.ledger_path)
    specs = _specs(cfg)
    args.live_data = not args.synthetic
    data = _data(args, cfg, specs)
    t = data.timeline()[-1]
    researcher = OpusResearcher(model=cfg.research.get("model", "claude-opus-5-5"), effort=cfg.research.get("effort", "high"), max_tokens=int(cfg.research.get("max_tokens", 64000)))
    evidence = market_evidence(data, t)
    if not data.synthetic:
        from hedgefund.data.sources import DataSourceError, HttpGetter, fetch_global_snapshot

        try:
            g = fetch_global_snapshot(HttpGetter())
            evidence += [
                {"metric": name, "value": g[key], "as_of": g["retrieved_at"], "source": g["source"]}
                for key, name in (("btc_dominance_pct", "BTC market-cap dominance %"), ("eth_dominance_pct", "ETH market-cap dominance %"), ("total_market_cap_usd", "total crypto market cap USD"))
                if g.get(key) is not None
            ]
        except (DataSourceError, KeyError) as e:
            print(f"note: global snapshot unavailable ({e}); continuing without it")
    if args.task == "scan":
        res = researcher.market_scan(evidence, utc_iso(t))
    elif args.task == "memo":
        if not args.topic:
            sys.exit("--topic is required for memo")
        res = researcher.write_memo(args.topic, evidence)
    else:
        from hedgefund.monitoring.report import daily_report
        from hedgefund.portfolio.book import Portfolio

        res = researcher.overnight_review(daily_report(ledger, Portfolio(cfg.starting_nav, cfg.instruments), {}, now_ms()), {})
    memo_id = record_result(ledger, res, now_ms())
    _print_json({"memo_id": memo_id, "usage": res.usage, "data": res.data})
    if args.task == "memo" and args.draft_strategy:
        draft = researcher.draft_strategy(res.data, sorted(cfg.instruments))
        spec, problems = spec_from_draft(draft.data, memo_id, set(cfg.instruments))
        record_result(ledger, draft, now_ms())
        print("strategy draft:", "valid (stage=hypothesis; needs code before the SIGNAL gate)" if spec else f"invalid: {problems}")
        if spec:
            import yaml

            from hedgefund.strategy.spec import spec_to_dict

            out = cfg.var_dir / "drafts" / f"{spec.id}.yaml"
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(yaml.safe_dump(spec_to_dict(spec), sort_keys=False))
            print(f"draft spec written to {out} (review, then move to config/strategies/)")
    return 0


def cmd_verify(args) -> int:
    cfg = _cfg(args)
    ok, bad = Ledger(cfg.ledger_path).verify_chain()
    print("ledger OK" if ok else f"LEDGER TAMPERED/CORRUPT at seq {bad}")
    return 0 if ok else 2


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="hedgefund", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default=None, help="path to fund.yaml (default: config/fund.yaml)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("validate")
    sub.add_parser("org")

    def data_opts(p):
        p.add_argument("--strategy", action="append", help="strategy id (repeatable); default all")
        p.add_argument("--bars", type=int, default=3000, help="synthetic bars")
        p.add_argument("--seed", type=int, default=7)
        p.add_argument("--live-data", action="store_true", help="fetch real data from public sources")
        p.add_argument("--days", type=int, default=730, help="history for --live-data")

    p = sub.add_parser("backtest")
    data_opts(p)
    p.add_argument("--stress", action="store_true")
    p.add_argument("--perturb", action="store_true", help="parameter perturbation (single strategy)")
    p.add_argument("--evidence-out", default=None)

    p = sub.add_parser("recalibrate")
    data_opts(p)

    p = sub.add_parser("paper")
    p.add_argument("--once", action="store_true")
    p.add_argument("--replay", type=int, default=0, help="synthetic replay over N bars (offline demo)")
    p.add_argument("--seed", type=int, default=7)
    p.add_argument("--ephemeral", action="store_true", help="replay into an in-memory ledger")
    p.add_argument("--all-stages", action="store_true", help="run strategies below paper_trade (paper venue only)")
    p.add_argument("--with-research", action="store_true", help="enable Opus overnight research")

    sub.add_parser("status")
    sub.add_parser("report")
    sub.add_parser("stages")
    sub.add_parser("verify-ledger")

    p = sub.add_parser("promote")
    p.add_argument("strategy")
    p.add_argument("--to", required=True)
    p.add_argument("--evidence", required=True, help="JSON evidence file (e.g. from backtest --evidence-out)")
    p.add_argument("--operator", default=None)
    p.add_argument("--reason", default="")

    p = sub.add_parser("demote")
    p.add_argument("strategy")
    p.add_argument("--to", choices=["paper_trade", "retired"], required=True)
    p.add_argument("--reason", required=True)

    p = sub.add_parser("approve")
    p.add_argument("request_id", help="approval request id, or 'risk_limits_change'")
    p.add_argument("--decision", choices=["approve", "reject"], default="approve")
    p.add_argument("--operator", required=True)
    p.add_argument("--reason", required=True)

    p = sub.add_parser("kill")
    p.add_argument("--reason", required=True)
    p.add_argument("--operator", default=None)

    p = sub.add_parser("reset-kill")
    p.add_argument("--operator", required=True)
    p.add_argument("--reason", required=True)

    p = sub.add_parser("calibration")
    p.add_argument("--days", type=int, default=30)

    p = sub.add_parser("research")
    p.add_argument("task", choices=["scan", "memo", "overnight"])
    p.add_argument("--topic", default=None)
    p.add_argument("--draft-strategy", action="store_true")
    p.add_argument("--synthetic", action="store_true", help="use synthetic evidence (offline)")
    p.add_argument("--bars", type=int, default=1500)
    p.add_argument("--seed", type=int, default=7)
    p.add_argument("--days", type=int, default=220)

    args = ap.parse_args(argv)
    if hasattr(signal, "SIGPIPE"):
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)  # quiet exit when piped into `head`
    handlers = {
        "validate": cmd_validate,
        "org": cmd_org,
        "backtest": cmd_backtest,
        "recalibrate": cmd_recalibrate,
        "paper": cmd_paper,
        "status": cmd_status,
        "report": cmd_report,
        "stages": cmd_stages,
        "promote": cmd_promote,
        "demote": lambda a: cmd_promote(a, demote=True),
        "approve": cmd_approve,
        "kill": cmd_kill,
        "reset-kill": cmd_reset_kill,
        "calibration": cmd_calibration,
        "research": cmd_research,
        "verify-ledger": cmd_verify,
    }
    return handlers[args.cmd](args)

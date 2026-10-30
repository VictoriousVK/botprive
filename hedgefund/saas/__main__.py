"""python -m hedgefund.saas <command>

  init-db                      create the tables (and the row-level security policies on PostgreSQL)
  worker [--threads N]         run the job worker (Docker: its own container)
  manifest                     print the version manifest (models, prompts, commit, config)
  verify-audit --tenant ID     check a tenant's audit hash chain
  eval [--suite NAME]          run the scorecard (exit code 1 on any catastrophic failure)
  mcp SERVER                   run an MCP server on stdio (journal, ict-engine, knowledge, market-data, backtest)
  purge-jobs --days N          delete finished jobs older than N days
  bridge [--every-min 15]      MT5 read-only bridge for accounts in investor mode (Windows host)
  compile-server --metaeditor PATH --experts DIR [--port 8765]
                               MQL5 compilation service for the EA factory (Windows host, token HF_MQL_COMPILER_TOKEN)

The database comes from HF_SAAS_DB (default: SQLite in the data directory).
"""

from __future__ import annotations

import argparse
import json
import logging
import signal
import sys
import time


def _saas(args):
    from hedgefund.saas.service import build_saas

    feed = None
    if getattr(args, "with_feed", False):
        from hedgefund.web.server import make_feed
        import os

        feed, _client = make_feed(os.environ.get("HF_FEED", "auto"))
    return build_saas(feed=feed, data_dir=args.data_dir)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="hedgefund.saas", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data-dir", default=None)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("init-db")
    p = sub.add_parser("worker")
    p.add_argument("--threads", type=int, default=2)
    sub.add_parser("manifest")
    p = sub.add_parser("verify-audit")
    p.add_argument("--tenant", required=True)
    p = sub.add_parser("eval")
    p.add_argument("--suite", default="all")
    p.add_argument("--json", action="store_true")
    p = sub.add_parser("mcp")
    p.add_argument("server")
    p.add_argument("--tenant", default="")
    p.add_argument("--user", type=int, default=0)
    p = sub.add_parser("bridge")
    p.add_argument("--every-min", type=int, default=15)
    p.add_argument("--once", action="store_true")
    p = sub.add_parser("compile-server")
    p.add_argument("--metaeditor", required=True)
    p.add_argument("--experts", required=True)
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=8765)
    p = sub.add_parser("purge-jobs")
    p.add_argument("--days", type=int, default=30)
    args = ap.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

    if args.cmd == "init-db":
        s = _saas(args)
        print(f"base prête ({'PostgreSQL + RLS' if s.db.is_postgres else 'SQLite'}), manifeste {s.manifest.fingerprint}")
        return 0
    if args.cmd == "manifest":
        print(json.dumps(_saas(args).manifest.model_dump(), indent=2, ensure_ascii=False))
        return 0
    if args.cmd == "verify-audit":
        from hedgefund.saas.harness import verify_audit_chain

        ok, n = verify_audit_chain(_saas(args).db, args.tenant)
        print(("chaîne intacte" if ok else "CHAÎNE ROMPUE à l'enregistrement") + f" ({n})")
        return 0 if ok else 1
    if args.cmd == "worker":
        args.with_feed = True
        s = _saas(args)
        s.start(max(1, args.threads))
        stop = {"flag": False}
        signal.signal(signal.SIGTERM, lambda *_: stop.update(flag=True))
        print(f"worker démarré ({args.threads} fils), manifeste {s.manifest.fingerprint}")
        try:
            while not stop["flag"]:
                time.sleep(1)
        except KeyboardInterrupt:
            pass
        s.shutdown()
        return 0
    if args.cmd == "bridge":
        import MetaTrader5 as mt5  # type: ignore[import-not-found]

        from hedgefund.saas.bridge import run_once

        s = _saas(args)
        while True:
            for line in run_once(s, mt5):
                print(line)
            if args.once:
                return 0
            time.sleep(max(5, args.every_min) * 60)
    if args.cmd == "compile-server":
        import os

        import uvicorn

        from hedgefund.saas.ea_factory import compile_server_app

        token = os.environ.get("HF_MQL_COMPILER_TOKEN", "").strip()
        if len(token) < 24:
            print("HF_MQL_COMPILER_TOKEN manquant ou trop court (24 caractères minimum)")
            return 1
        uvicorn.run(compile_server_app(args.metaeditor, args.experts, token), host=args.host, port=args.port, log_level="info", server_header=False)
        return 0
    if args.cmd == "purge-jobs":
        s = _saas(args)
        n = s.queue.purge(int(time.time() * 1000) - args.days * 86_400_000)
        print(f"{n} tâches supprimées")
        return 0
    if args.cmd == "eval":
        from hedgefund.saas.evals import run_scorecard

        report = run_scorecard(args.suite)
        print(json.dumps(report, indent=2, ensure_ascii=False) if args.json else report["text"])
        return 0 if report["passed"] else 1
    if args.cmd == "mcp":
        from hedgefund.saas.mcp_servers import serve

        return serve(_saas(args), args.server, args.tenant, args.user)
    return 2


if __name__ == "__main__":
    sys.exit(main())

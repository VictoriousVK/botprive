"""python -m hedgefund.web <command>

  create-user --username NAME     create a console login (password asked twice, >= 12 characters)
  reset-password --username NAME  set a new console password and revoke that user's sessions
  member-password --email EMAIL   set a new password for a site member and revoke their sessions
  serve [--host 127.0.0.1] [--port 8000]
"""

from __future__ import annotations

import argparse
import getpass
import os
import sys
from pathlib import Path


def _store(args):
    from hedgefund.bots.store import PlatformStore
    from hedgefund.config import load_config

    cfg = load_config(args.config)
    return PlatformStore(Path(args.data_dir or os.environ.get("HF_DATA_DIR") or cfg.var_dir) / "platform.db")


def _ask_password() -> str:
    p1 = getpass.getpass("Mot de passe (12 caractères minimum) : ")
    p2 = getpass.getpass("Confirmez : ")
    if p1 != p2:
        sys.exit("les mots de passe ne correspondent pas")
    return p1


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="hedgefund.web", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default=None)
    ap.add_argument("--data-dir", default=None)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("create-user", "reset-password"):
        p = sub.add_parser(name)
        p.add_argument("--username", required=True)
    p = sub.add_parser("member-password")
    p.add_argument("--email", required=True)
    p = sub.add_parser("serve")
    p.add_argument("--host", default=os.environ.get("HF_HOST", "127.0.0.1"))
    p.add_argument("--port", type=int, default=int(os.environ.get("HF_PORT", "8000")))
    args = ap.parse_args(argv)

    from hedgefund.web.security import AuthService

    if args.cmd == "create-user":
        auth = AuthService(_store(args))
        try:
            auth.create_user(args.username, _ask_password())
        except ValueError as e:
            sys.exit(str(e))
        print(f"utilisateur « {args.username} » créé")
        return 0
    if args.cmd == "reset-password":
        auth = AuthService(_store(args))
        rows = auth.store.execute("SELECT id FROM users WHERE username = ?", (args.username,))
        if not rows:
            sys.exit("utilisateur inconnu")
        try:
            auth.set_password(rows[0]["id"], _ask_password())
        except ValueError as e:
            sys.exit(str(e))
        print("mot de passe changé ; toutes les sessions de cet utilisateur sont fermées")
        return 0

    if args.cmd == "member-password":
        from hedgefund.members.service import SCHEMA, member_auth

        store = _store(args)
        store.executescript(SCHEMA)
        rows = store.execute("SELECT id FROM members WHERE email = ?", (args.email.strip().lower(),))
        if not rows:
            sys.exit("membre inconnu")
        try:
            member_auth(store).set_password(rows[0]["id"], _ask_password())
        except ValueError as e:
            sys.exit(str(e))
        print("mot de passe du membre changé ; ses sessions sont fermées")
        return 0

    import uvicorn

    from hedgefund.web.server import build_platform

    app, engine, auth = build_platform(args.config, args.data_dir)
    if auth.user_count() == 0:
        print("Aucun utilisateur : créez-en un d'abord avec  python -m hedgefund.web create-user --username VOTRE_NOM")
        return 1
    if args.host not in ("127.0.0.1", "localhost", "::1"):
        print(f"ATTENTION : écoute sur {args.host}. Exposez la plateforme uniquement derrière HTTPS (voir docs/PLATFORM.md).")
    print(f"Plateforme : http://{args.host}:{args.port}  (flux : {engine.feed.name}, mode : {engine.mode})")
    uvicorn.run(app, host=args.host, port=args.port, log_level="info", server_header=False, proxy_headers=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())

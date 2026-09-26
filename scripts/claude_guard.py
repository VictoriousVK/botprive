"""Claude Code PreToolUse hook (.claude/settings.json).

Blocks (exit code 2, message on stderr):
  * writing or editing an environment file (.env, .env.ps1…);
  * a `git commit` while a secret or a private invite link is staged (scripts/check_secrets.py).
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0
    tool = event.get("tool_name", "")
    args = event.get("tool_input", {}) or {}
    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        name = Path(str(args.get("file_path", ""))).name
        if name.startswith(".env"):
            print(f"écriture refusée : {name} contient des secrets locaux, modifiez-le vous-même", file=sys.stderr)
            return 2
    if tool == "Bash" and re.search(r"\bgit\b[^|;&]*\bcommit\b", str(args.get("command", ""))):
        res = subprocess.run([sys.executable, str(ROOT / "scripts" / "check_secrets.py"), "--staged"], cwd=ROOT, capture_output=True, text=True)
        if res.returncode != 0:
            print("commit refusé : " + res.stdout.strip(), file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

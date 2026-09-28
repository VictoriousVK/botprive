"""Blocks secrets and private invite links from entering the (public) repository.

Usage: python scripts/check_secrets.py [--staged]   (exit code 1 if something is found)
Run by CI, and by the Claude Code hook before every commit (.claude/settings.json).
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = [
    ("lien d'invitation Telegram privé", re.compile(r"t\.me/(\+|joinchat/)[A-Za-z0-9_-]{6,}")),
    ("lien d'invitation Discord", re.compile(r"discord(\.gg|app\.com/invite|\.com/invite)/[A-Za-z0-9-]{4,}")),
    ("clé API Anthropic", re.compile(r"sk-ant-[A-Za-z0-9_-]{20,}")),
    ("clé API Wave", re.compile(r"wave_[a-z]{2}_prod_[A-Za-z0-9_-]{16,}")),
    ("clé AWS", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("clé privée", re.compile(r"-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY-----")),
    ("jeton de bot Telegram", re.compile(r"\b\d{8,10}:AA[A-Za-z0-9_-]{30,}\b")),
    ("mot de passe en clair", re.compile(r"(?i)\b(password|passwd|mot_de_passe)\s*[:=]\s*['\"][^'\"\s]{8,}['\"]")),
]
SKIP_SUFFIX = {".png", ".jpg", ".jpeg", ".webp", ".ico", ".woff", ".woff2", ".zip", ".pdf", ".gif"}
ALLOW = {"scripts/check_secrets.py", "tests/test_saas_foundations.py"}


def files(staged: bool) -> list[str]:
    cmd = ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"] if staged else ["git", "ls-files"]
    out = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return [f for f in out.splitlines() if f and Path(f).suffix.lower() not in SKIP_SUFFIX and f not in ALLOW]


def scan(paths: list[str]) -> list[str]:
    hits = []
    for rel in paths:
        p = ROOT / rel
        if not p.is_file():
            continue
        try:
            text = p.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for label, rx in PATTERNS:
            for m in rx.finditer(text):
                if re.search(r"exemple|example|placeholder|xxxx", m.group(0), re.I):
                    continue  # obvious fakes used by tests and docs
                line = text.count("\n", 0, m.start()) + 1
                hits.append(f"{rel}:{line}: {label}")
    return hits


def main() -> int:
    hits = scan(files("--staged" in sys.argv))
    for h in hits:
        print(h)
    if hits:
        print(f"\n{len(hits)} élément(s) sensible(s) : retirez-les (le dépôt est public).")
        return 1
    print("aucun secret ni lien privé détecté")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""The secret scanner run by CI and by the commit hook: real-looking values are caught, the
placeholders that mask them (docs, tests, the Sentry SDK in the built site) are not."""

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("check_secrets", ROOT / "scripts" / "check_secrets.py")
cs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cs)


def test_a_plain_password_is_caught_but_not_a_masking_placeholder(tmp_path, monkeypatch):
    monkeypatch.setattr(cs, "ROOT", tmp_path)
    key = "pass" + "word"  # built at run time: this file must not trip the scanner itself
    (tmp_path / "real.js").write_text('const c = {' + key + ': "Tr0ub4dor-cheval"};\n')
    (tmp_path / "sdk.js").write_text('if(e.password){e.password="%filtered%"}\nx={password:"[Filtered]"}\n')
    (tmp_path / "doc.md").write_text('password = "motdepasse-exemple"\n')
    hits = cs.scan(["real.js", "sdk.js", "doc.md"])
    assert hits == ["real.js:1: mot de passe en clair"]

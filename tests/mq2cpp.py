#!/usr/bin/env python3
"""Convertit un fichier MQL5 (.mq5/.mqh) en C++ compilable avec tests/shim.

Ce n'est pas un compilateur MQL5 : il réécrit seulement les quelques
constructions propres à MQL5 (tableaux dynamiques, inputs, littéraux de
couleur, #property...) pour que g++ puisse vérifier la syntaxe, les types
et exécuter le moteur dans les tests.

Il effectue aussi des vérifications "lint" sur des règles MQL5 que g++
n'attraperait pas (références locales, structures passées par valeur,
initialiseurs de membres, 'this.').
"""
import re
import sys
from pathlib import Path

STRUCT_TYPES = set()


def lint(src: str, path: str) -> list:
    errors = []
    for m in re.finditer(r"^\s*struct\s+(\w+)", src, re.M):
        STRUCT_TYPES.add(m.group(1))
    for m in re.finditer(r"^\s*class\s+(\w+)", src, re.M):
        STRUCT_TYPES.add(m.group(1))
    STRUCT_TYPES.update({"MqlRates", "MqlTick", "MqlDateTime", "CTrade"})
    lines = src.split("\n")
    in_struct = False
    depth = 0
    for i, line in enumerate(lines, 1):
        code = re.sub(r'"(\\.|[^"\\])*"', '""', line).split("//")[0]
        # référence locale : "Type &x = ..." (interdit en MQL5)
        if re.match(r"^\s*(const\s+)?\w+\s*&\s*\w+\s*=", code):
            errors.append(f"{path}:{i}: référence locale interdite en MQL5: {line.strip()}")
        if re.search(r"\bthis\s*\.", code):
            errors.append(f"{path}:{i}: 'this.' interdit: {line.strip()}")
        if re.search(r"\b(auto|nullptr|static_cast|std::|long\s+long)\b", code):
            errors.append(f"{path}:{i}: construction C++ non MQL5: {line.strip()}")
        # structure passée par valeur dans une signature de fonction
        sig = re.match(r"^\s*[\w<>]+\s+(\w+)\s*\((.*)\)\s*(const)?\s*$", code)
        if sig and sig.group(1) not in ("if", "while", "for", "switch", "return"):
            for p in sig.group(2).split(","):
                p = p.strip()
                if not p:
                    continue
                toks = p.replace("const ", "").split()
                if toks and toks[0] in STRUCT_TYPES and "&" not in p and "*" not in p:
                    errors.append(f"{path}:{i}: objet passé par valeur (interdit en MQL5): {p}")
        # initialiseur de membre dans une struct/classe : "type nom = x;" au niveau membre
        if re.match(r"^\s*(struct|class)\s+\w+", code):
            in_struct = True
            depth = 0
        if in_struct:
            depth += code.count("{") - code.count("}")
            if depth == 1 and re.match(r"^\s*(int|double|bool|long|datetime|string|color|ulong|uint)\s+\w+\s*=", code):
                errors.append(f"{path}:{i}: initialiseur de membre interdit en MQL5: {line.strip()}")
            if depth <= 0 and "}" in code:
                in_struct = False
    return errors


TOKEN_RE = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'', re.S)


def join_literals(src: str) -> str:
    """MQL5 accepte "a"+"b" et "a"+(c?"x":"y") ; C++ non.
    Les littéraux reliés par + sont fusionnés, puis tout littéral voisin d'un + devient string("...")."""
    lits = [m for m in TOKEN_RE.finditer(src) if m.group(0).startswith('"')]
    groups = []
    for m in lits:
        if groups and re.fullmatch(r"\s*\+?\s*", src[groups[-1][-1].end():m.start()]):
            groups[-1].append(m)
        else:
            groups.append([m])
    out, last = [], 0
    for g in groups:
        start, end = g[0].start(), g[-1].end()
        text = '"' + "".join(m.group(0)[1:-1] for m in g) + '"'
        before = src[:start].rstrip()
        after = src[end:].lstrip()
        plus_before = before.endswith("+") and not before.endswith("++")
        plus_after = after.startswith("+") and not after.startswith("++") and not after.startswith("+=")
        if plus_before or plus_after:
            text = "string(" + text + ")"
        nl = "\n" * sum(src[g[i].end():g[i + 1].start()].count("\n") for i in range(len(g) - 1))
        out.append(src[last:start])
        out.append(text + nl)
        last = end
    out.append(src[last:])
    return "".join(out)


def mask_code(src: str) -> str:
    """Remplace commentaires, chaînes et caractères par des espaces (positions conservées)."""
    def blank(m):
        s = m.group(0)
        return re.sub(r"[^\n]", " ", s)
    return TOKEN_RE.sub(blank, src)


def add_prototypes(src: str) -> str:
    """MQL5 permet d'appeler une fonction globale définie plus bas ; C++ exige un prototype."""
    code = mask_code(src)
    lines = src.split("\n")
    clines = code.split("\n")
    depth = 0
    starts = []          # début de la construction de niveau 0 contenant chaque ligne
    cur = 0
    defs = []            # (nom, ligne de signature, texte de signature)
    for i, cl in enumerate(clines):
        s = cl.strip()
        if depth == 0 and s and not s.startswith("#") and not s.startswith("{"):
            cur = i
        starts.append(cur)
        if depth == 0:
            m = re.match(r"^([A-Za-z_][\w<>]*(?:\s*[&*])?(?:\s+[A-Za-z_][\w<>]*)*)\s+([A-Za-z_]\w*)\s*\(([^;{}]*)\)\s*(const)?\s*(\{.*)?$", cl)
            nxt = clines[i + 1].strip() if i + 1 < len(clines) else ""
            if m and m.group(2) not in ("if", "while", "for", "switch", "return") and (m.group(5) or nxt.startswith("{")):
                if not re.match(r"^\s*(class|struct|enum|return|else|new|delete)\b", cl):
                    defs.append((m.group(2), i, lines[i]))
        depth += cl.count("{") - cl.count("}")
    inserts = {}
    strip_defaults = set()
    for name, li, sig in defs:
        pat = re.compile(r"\b" + re.escape(name) + r"\s*\(")
        first = None
        for j in range(li):
            if pat.search(clines[j]):
                first = j
                break
        if first is None:
            continue
        proto = sig.split("{")[0].rstrip() + ";"
        inserts.setdefault(starts[first], []).append(proto)
        if "=" in sig.split("(", 1)[1]:
            strip_defaults.add(li)
    out = []
    for i, line in enumerate(lines):
        if i in inserts:
            out.extend(inserts[i])
        if i in strip_defaults:
            head, rest = line.split("(", 1)
            args, tail = rest.rsplit(")", 1)
            args = re.sub(r"\s*=\s*[^,]+", "", args)
            line = head + "(" + args + ")" + tail
        out.append(line)
    return "\n".join(out)


def convert(src: str, overrides: dict) -> str:
    if src.startswith("\ufeff"):
        src = src[1:]
    # membres pointeurs : en MQL5 on écrit p.Methode(), en C++ p->Methode()
    ptrs = set(re.findall(r"^\s*[A-Za-z_]\w*\s*\*\s*([A-Za-z_]\w*)\s*;", src, re.M))
    for name in ptrs:
        src = re.sub(r"\b" + re.escape(name) + r"\.(?=[A-Za-z_])", name + "->", src)
    src = join_literals(src)
    src = re.sub(r'^(\s*#define\s+\w+\s+)("(?:\\.|[^"\\])*")', r"\1string(\2)", src, flags=re.M)
    src = add_prototypes(src)
    out = []
    for line in src.split("\n"):
        m = re.match(r"^(\s*s?input\s+\w+\s+)(\w+)(\s*=\s*)([^;]+)(;.*)$", line)
        if m and m.group(2) in overrides:
            line = m.group(1) + m.group(2) + m.group(3) + overrides.pop(m.group(2)) + m.group(5)
        s = line.strip()
        if s.startswith("#property"):
            out.append("")
            continue
        if re.match(r"#include\s*<", s):
            out.append("")
            continue
        if re.match(r"^\s*input\s+group\b", line):
            out.append("")
            continue
        line = re.sub(r"^(\s*)(s?input)\s+", r"\1const ", line)
        line = re.sub(r"C'(\d+)\s*,\s*(\d+)\s*,\s*(\d+)'", r"MQL_RGB(\1,\2,\3)", line)
        # paramètres tableaux : Type &name[]
        line = re.sub(r"\b([A-Za-z_]\w*)\s*&\s*([A-Za-z_]\w*)\s*\[\s*\]", r"MqlArray<\1> &\2", line)
        # déclarations de tableaux dynamiques : Type name[]; ou Type a[],b[];
        line = re.sub(r"\b([A-Za-z_]\w*)(\s+)([A-Za-z_]\w*)\s*\[\s*\]\s*;", r"MqlArray<\1>\2\3;", line)
        mm = re.match(r"^(\s*)([A-Za-z_]\w*)(\s+)((?:[A-Za-z_]\w*\s*\[\s*\]\s*,\s*)+[A-Za-z_]\w*\s*\[\s*\]\s*);(.*)$", line)
        if mm and mm.group(2) not in ("return", "else"):
            names = [n.strip().split("[")[0].strip() for n in mm.group(4).split(",")]
            line = mm.group(1) + "MqlArray<" + mm.group(2) + ">" + mm.group(3) + ",".join(names) + ";" + mm.group(5)
        out.append(line)
    return "\n".join(out)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--set=")]
    overrides = dict(a[6:].split("=", 1) for a in sys.argv[1:] if a.startswith("--set="))
    if len(args) != 2:
        print("usage: mq2cpp.py input.mq5 output.cpp [--set=InpName=valeur ...]")
        return 2
    src_path, dst_path = args
    src = Path(src_path).read_text(encoding="utf-8-sig")
    errs = lint(src, src_path)
    Path(dst_path).write_text(convert(src, overrides), encoding="utf-8")
    if overrides:
        errs.append(f"paramètres inconnus: {', '.join(overrides)}")
    for e in errs:
        print(e)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())

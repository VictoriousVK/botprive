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
                if toks and toks[0] in STRUCT_TYPES and "&" not in p:
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


def convert(src: str, overrides: dict) -> str:
    if src.startswith("\ufeff"):
        src = src[1:]
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
        # déclarations de tableaux dynamiques : Type name[];
        line = re.sub(r"\b([A-Za-z_]\w*)(\s+)([A-Za-z_]\w*)\s*\[\s*\]\s*;", r"MqlArray<\1>\2\3;", line)
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

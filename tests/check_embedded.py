#!/usr/bin/env python3
"""Vérifie que les modules OPR intégrés à ICT_NAS_Institutional.mq5 sont identiques aux modules testés
de mql5/Experts/OPR_FVG (au renommage COprEngine -> CLondonOprEngine près)."""
import re
import sys
from pathlib import Path

ea = Path(sys.argv[1]).read_text(encoding="utf-8-sig")
opr = Path(sys.argv[2])
bad = 0
for name in ["OPR_Config", "OPR_Time", "OPR_Candles", "OPR_FVG", "OPR_Ranges", "OPR_Liquidity", "OPR_Journal", "OPR_Engine"]:
    a = ea.index(f"//=== début {name}.mqh ===\n") + len(f"//=== début {name}.mqh ===\n")
    b = ea.index(f"//=== fin {name}.mqh ===", a)
    ref = (opr / f"{name}.mqh").read_text(encoding="utf-8-sig")
    ref = re.sub(r'^#include\s+"OPR_\w+\.mqh"\s*\n', "", ref, flags=re.M)
    ref = re.sub(r"\bCOprEngine\b", "CLondonOprEngine", ref).rstrip() + "\n"
    if ea[a:b] != ref:
        print(f"module {name} : la copie intégrée diffère du module testé")
        bad += 1
print("modules OPR intégrés identiques aux modules testés" if bad == 0 else f"{bad} module(s) différent(s)")
sys.exit(1 if bad else 0)

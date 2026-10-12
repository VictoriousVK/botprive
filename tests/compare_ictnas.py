#!/usr/bin/env python3
"""Tableau « avant / après » d'ICT NAS à partir des lignes STATS écrites par ictnas_tests.cpp."""
import sys
from collections import defaultdict

runs = defaultdict(list)
order = []
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.startswith("STATS;"):
        continue
    f = line.rstrip("\n").split(";")
    label, ver, seed, days, fills, wins, losses, net, maxloss, sigs = f[1:11]
    models, decisions = {}, {}
    for kv in f[11:]:
        k, v = kv.rsplit("=", 1)
        (models if k.startswith("F:") else decisions)[k[2:]] = int(v)
    if label not in runs:
        order.append(label)
    runs[label].append(dict(ver=ver, seed=int(seed), days=int(days), fills=int(fills), wins=int(wins), losses=int(losses),
                            net=float(net), maxloss=float(maxloss), sigs=int(sigs), models=models, decisions=decisions))

print("| Configuration | trades exécutés / jour | dont London OPR PDF | dont SB Momentum | autres modèles | gagnants / perdants | perte max par trade |")
print("|---|---|---|---|---|---|---|")
for label in order:
    rs = runs[label]
    days = sum(r["days"] for r in rs)
    fills = sum(r["fills"] for r in rs)
    lo = sum(r["models"].get("LONDON_OPR_PDF", 0) for r in rs)
    sm = sum(r["models"].get("SB_MOMENTUM", 0) for r in rs)
    w = sum(r["wins"] for r in rs)
    l = sum(r["losses"] for r in rs)
    ml = max(r["maxloss"] for r in rs)
    print(f"| {label} | {fills / days:.2f} ({fills} sur {days} j) | {lo / days:.2f} | {sm / days:.2f} | {(fills - lo - sm) / days:.2f} "
          f"| {w} / {l} | {ml:.2f} % |")
print()
print("Principales décisions sur les signaux ICT complets (cumul des graines) :")
for label in order:
    agg = defaultdict(int)
    for r in runs[label]:
        for k, v in r["decisions"].items():
            agg[k] += v
    tot = sum(agg.values())
    top = sorted(agg.items(), key=lambda kv: -kv[1])[:6]
    print(f"  {label} ({tot} signaux) : " + " ; ".join(f"{k} {100.0 * v / tot:.0f} %" for k, v in top))

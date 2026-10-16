#!/usr/bin/env bash
# Convertit le code MQL5 en C++ (tests/mq2cpp.py), le compile avec g++ et exécute :
#   1. EA LRL Map : tests du moteur + EA complet simulé (4 variantes)
#   2. EA OPR + FVG : tests du moteur (10 tests obligatoires du cahier des charges)
#      + EA complet simulé tick par tick (5 variantes)
#   3. le comparatif « avant / après » sur les mêmes données synthétiques
#   4. EA ICT NAS Institutional : v2.30 (fusion avec le moteur OPR + FVG) testée de bout en bout
#      (6 variantes) et comparée à la v2.22 d'origine (tests/ref) sur les mêmes données
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
EA=../mql5/Experts/LRL_Map
CXX="g++ -std=c++17 -O2 -Wall -Wextra -Wno-unused-parameter -Wno-unused-variable -Werror -Ishim -Ibuild"

python3 mq2cpp.py "$EA/LRL_Engine.mqh" build/LRL_Engine.mqh
$CXX engine_tests.cpp -o build/engine_tests
./build/engine_tests

build_ea() {  # $1 = numéro de variante, puis surcharges --set=...
  local v=$1
  shift
  python3 mq2cpp.py "$EA/LRL_Map_EA.mq5" build/LRL_Map_EA.cpp "$@"
  $CXX -DVARIANT="$v" ea_sim_tests.cpp -o "build/ea_sim_$v"
}

echo
build_ea 0
./build/ea_sim_0
build_ea 1 --set=InpMaxPositions=100
./build/ea_sim_1
build_ea 2 --set=InpOrderMode=LRL_ORDER_MARKET --set=InpBreakEvenR=0.5 --set=InpDirection=LRL_DIR_SHORT \
  --set=InpMaxTradesDay=5 --set=InpExportCsv=true
./build/ea_sim_2
build_ea 3 --set=InpTheme=LRL_THEME_LIGHT --set=InpCorner=LRL_CORNER_TL
./build/ea_sim_3

# ---------------------------------------------------------------- EA OPR + FVG
OPR=../mql5/Experts/OPR_FVG
mkdir -p build/opr
for f in "$OPR"/*.mqh; do python3 mq2cpp.py "$f" "build/opr/$(basename "$f")"; done
OCXX="$CXX -Ibuild/opr"
$OCXX opr_engine_tests.cpp -o build/opr_engine_tests
echo
./build/opr_engine_tests

build_opr() {  # $1 = variante, puis surcharges --set=...
  local v=$1
  shift
  python3 mq2cpp.py "$OPR/OPR_FVG_EA.mq5" build/opr/OPR_FVG_EA.cpp "$@"
  $OCXX -DVARIANT="$v" opr_ea_tests.cpp -o "build/opr_ea_$v"
}
echo
build_opr 0
./build/opr_ea_0
build_opr 1 --set=InpServerTZ=OPR_SRV_GMT_US_DST
./build/opr_ea_1
build_opr 2 --set=InpServerTZ=OPR_SRV_GMT_US_DST --set=InpTradingEnabled=false
./build/opr_ea_2
build_opr 3 --set=InpServerTZ=OPR_SRV_GMT_US_DST --set=InpOpr2Trade=true
./build/opr_ea_3
build_opr 4 --set=InpServerTZ=OPR_SRV_GMT_US_DST --set=InpTheme=OPR_THEME_LIGHT --set=InpCorner=OPR_CORNER_TL
./build/opr_ea_4
echo
$CXX -Ibuild/opr compare_before_after.cpp -o build/compare_before_after
./build/compare_before_after

# ---------------------------------------------------------------- EA ICT NAS Institutional
ICT=../mql5/Experts/ICT_NAS_Institutional/ICT_NAS_Institutional.mq5
mkdir -p build/ict
ICXX="g++ -std=c++17 -O2 -Wall -Wextra -Wno-unused-parameter -Wno-unused-variable -Wno-misleading-indentation -Werror -Ishim -Ibuild/ict"
python3 check_embedded.py "$ICT" "$OPR"
build_ict() {  # $1 = source .mq5, $2 = binaire, $3 = version (222 / 230 / 240 / 250), $4 = variante, $5 = libellé, puis surcharges --set=...
  local src=$1 bin=$2 ver=$3 var=$4 label=$5
  shift 5
  python3 mq2cpp.py "$src" "build/ict/$bin.cpp" "$@"
  $ICXX -DICT_SRC="\"$bin.cpp\"" -DV230=$((ver >= 230 ? 1 : 0)) -DV240=$((ver >= 240 ? 1 : 0)) -DV250=$((ver >= 250 ? 1 : 0)) -DVARIANT="$var" -DLABEL="\"$label\"" \
    ictnas_tests.cpp -o "build/ict/$bin" -lsqlite3
}
run3() { for s in 71 72 73; do ./build/ict/$1 $s | tee -a $STATS | grep -v '^STATS'; done; }
STATS=build/ict/stats.txt
: > $STATS
echo
build_ict "$ICT" ict_def 250 0 "v2.50 (gagnants jusqu'à leur cible, DD testeur, apprentissage)"
run3 ict_def
build_ict "$ICT" ict_sig 250 1 "-" --set=InpTradingEnabled=false
./build/ict/ict_sig 71 | grep -v '^STATS'
build_ict "$ICT" ict_rst 250 2 "-" --set=InpFreshDBInTester=false
./build/ict/ict_rst 71 | grep -v '^STATS'
build_ict "$ICT" ict_leg 250 3 "v2.50 sans le modèle London PDF" --set=InpLondonMode=LONDON_LEGACY
run3 ict_leg
build_ict "$ICT" ict_bad 250 4 "-" --set=InpLOOpr2Trade=true
./build/ict/ict_bad 71 | grep -v '^STATS'
build_ict "$ICT" ict_vis 250 5 "-" --set=InpLondonManage=LM_ICTNAS
./build/ict/ict_vis 71 | grep -v '^STATS'
build_ict "$ICT" ict_open 250 7 "-"
./build/ict/ict_open 71 | grep -v '^STATS'
build_ict "$ICT" ict_nov6 250 9 "v2.50 sans les modèles v6.20" --set=InpV6EnableSB=false --set=InpV6EnableMB=false
run3 ict_nov6
build_ict "$ICT" ict_clamp 250 9 "option RiskGuard : SL ramené au plafond ATR" --set=InpSLCapMode=SLCAP_CLAMP
run3 ict_clamp
build_ict "$ICT" ict_small 250 6 "v2.50 petit compte (10 000, lot min 0,1)"
run3 ict_small
build_ict ref/ICT_NAS_Institutional_v230.mq5 ict_small230 230 6 "v2.30 petit compte (10 000, lot min 0,1)"
run3 ict_small230
build_ict "$ICT" ict_gate 250 9 "v2.50 + blocage par l'apprentissage (InpAdaptGate)" --set=InpAdaptGate=true
run3 ict_gate
build_ict "$ICT" ict_dd 250 9 "v2.50, DD total forcé à 1 % (le test continue)" --set=InpMaxTotalDDPct=1.0
run3 ict_dd
build_ict ref/ICT_NAS_Institutional_v240.mq5 ict_v240dd 240 9 "v2.40, DD total forcé à 1 % (arrêt définitif)" --set=InpMaxTotalDDPct=1.0
run3 ict_v240dd
build_ict ref/ICT_NAS_Institutional_v240.mq5 ict_v240 240 9 "v2.40"
run3 ict_v240
build_ict ref/ICT_NAS_Institutional_v230.mq5 ict_v230 230 9 "v2.30"
run3 ict_v230
build_ict ref/ICT_NAS_Institutional_v222.mq5 ict_v222 222 9 "v2.22 (origine)"
run3 ict_v222
echo
echo "Comparatif ICT NAS (données synthétiques, 3 graines x 60 jours) :"
python3 compare_ictnas.py $STATS | tee build/ict/comparatif.md
echo
echo "Tous les tests (LRL + OPR + ICT NAS) sont passés."

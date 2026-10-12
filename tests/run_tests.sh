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
build_ict() {  # $1 = source .mq5, $2 = binaire, $3 = 0/1 (v2.30), $4 = variante, $5 = libellé, puis surcharges --set=...
  local src=$1 bin=$2 v230=$3 var=$4 label=$5
  shift 5
  python3 mq2cpp.py "$src" "build/ict/$bin.cpp" "$@"
  $ICXX -DICT_SRC="\"$bin.cpp\"" -DV230="$v230" -DVARIANT="$var" -DLABEL="\"$label\"" ictnas_tests.cpp -o "build/ict/$bin" -lsqlite3
}
STATS=build/ict/stats.txt
: > $STATS
echo
build_ict "$ICT" ict_def 1 0 "v2.30 (nouvelle version)"
for s in 71 72 73; do ./build/ict/ict_def $s | tee -a $STATS | grep -v '^STATS'; done
build_ict "$ICT" ict_sig 1 1 "-" --set=InpTradingEnabled=false
./build/ict/ict_sig 71 | grep -v '^STATS'
build_ict "$ICT" ict_rst 1 2 "-" --set=InpFreshDBInTester=false
./build/ict/ict_rst 71 | grep -v '^STATS'
build_ict "$ICT" ict_leg 1 3 "v2.30 sans le modèle London PDF" --set=InpLondonMode=LONDON_LEGACY
for s in 71 72 73; do ./build/ict/ict_leg $s | tee -a $STATS | grep -v '^STATS'; done
build_ict "$ICT" ict_bad 1 4 "-" --set=InpLOOpr2Trade=true
./build/ict/ict_bad 71 | grep -v '^STATS'
build_ict "$ICT" ict_vis 1 5 "-" --set=InpLondonManage=LM_ICTNAS
./build/ict/ict_vis 71 | grep -v '^STATS'
build_ict "$ICT" ict_risk222 1 9 "v2.30 avec le risque de la v2.22" --set=InpRiskPct=3.0 --set=InpDailyLossPct=3.0 \
  --set=InpDailyTargetPct=9.0 --set=InpMaxConcurrent=1
for s in 71 72 73; do ./build/ict/ict_risk222 $s | tee -a $STATS | grep -v '^STATS'; done
build_ict "$ICT" ict_slcap 1 9 "option : SL max 4 ATR M5 (profil personnalisé)" --set=InpProfile=PROFILE_CUSTOM \
  --set=InpScoreMin=25 --set=InpMinFVGPts=3 --set=InpDispATRMult=1.2 --set=InpHuntMaxBars=45 --set=InpSLCapATR=4.0
for s in 71 72 73; do ./build/ict/ict_slcap $s | tee -a $STATS | grep -v '^STATS'; done
build_ict ref/ICT_NAS_Institutional_v222.mq5 ict_v222 0 9 "v2.22 (origine)"
for s in 71 72 73; do ./build/ict/ict_v222 $s | tee -a $STATS | grep -v '^STATS'; done
echo
echo "Comparatif ICT NAS (données synthétiques, 3 graines x 60 jours) :"
python3 compare_ictnas.py $STATS | tee build/ict/comparatif.md
echo
echo "Tous les tests (LRL + OPR + ICT NAS) sont passés."

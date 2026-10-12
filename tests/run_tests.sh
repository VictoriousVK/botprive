#!/usr/bin/env bash
# Convertit le code MQL5 en C++ (tests/mq2cpp.py), le compile avec g++ et exécute :
#   1. EA LRL Map : tests du moteur + EA complet simulé (4 variantes)
#   2. EA OPR + FVG : tests du moteur (10 tests obligatoires du cahier des charges)
#      + EA complet simulé tick par tick (5 variantes)
#   3. le comparatif « avant / après » sur les mêmes données synthétiques
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
echo
echo "Tous les tests (LRL + OPR) sont passés."

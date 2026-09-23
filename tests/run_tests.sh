#!/usr/bin/env bash
# Convertit le code MQL5 en C++ (tests/mq2cpp.py), le compile avec g++ et exécute :
#   1. les tests du moteur (scénarios + invariants sur données aléatoires)
#   2. l'EA complet sur un marché simulé tick par tick, en 4 variantes de paramètres
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
echo
echo "Tous les tests sont passés."

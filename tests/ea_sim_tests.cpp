// Test de bout en bout de l'EA complet (LRL_Map_EA.mq5 converti) sur un marché simulé
// tick par tick : warmup, ordres limites réels, SL/TP, fenêtre flat, dessin, tableau, CSV.
// Les trades réels sont comparés au modèle book du moteur.
#include "mql5_api.h"
bool g_shim_quiet = true;
Sim g_sim;
string _Symbol = "NQ";
double _Point = 0.01;
int _Digits = 2;
ENUM_TIMEFRAMES _Period = PERIOD_M1;

#include "LRL_Map_EA.cpp"
#include "synth.h"

#include <chrono>
#include <set>

#ifndef VARIANT
#define VARIANT 0
#endif
#define V_DEFAULT 0
#define V_MULTI 1
#define V_MISC 2
#define V_LIGHT 3

static int g_fail = 0, g_pass = 0;
#define CHECK(cond, msg)                                                   \
  do {                                                                     \
    if (cond) {                                                            \
      g_pass++;                                                            \
    } else {                                                               \
      g_fail++;                                                            \
      printf("  ECHEC %s:%d  %s   [%s]\n", __FILE__, __LINE__, msg, #cond); \
    }                                                                      \
  } while (0)

static datetime mkTime(int y, int mo, int d, int h, int mi) {
  MqlDateTime s;
  memset(&s, 0, sizeof(s));
  s.year = y; s.mon = mo; s.day = d; s.hour = h; s.min = mi;
  return StructToTime(s);
}

static long zoneOf(const std::string &cmt) {
  size_t p = cmt.rfind(' ');
  return p == std::string::npos ? 0 : atol(cmt.c_str() + p + 1);
}

int main() {
  const char *names[] = {"défaut (1 position max)", "positions multiples (comparaison exacte au book)",
                         "marché + BE + short seul + 5 trades/jour + CSV",
                         "thème clair, coin gauche, redémarrage de l'EA en cours de route"};
  printf("[test EA] variante : %s\n", names[VARIANT]);
  const int N = 140000;
  const int warm = 20000;
  auto bars = synth(N, 11 + VARIANT, mkTime(2025, 3, 3, 0, 0));
  g_sim.bars.clear();
  for (auto &b : bars) g_sim.bars.push_back({b.t, b.o, b.h, b.l, b.c});
  g_sim.visual = 1;
  g_sim.cur = warm;
  g_sim.setTick(bars[warm].t, bars[warm].o);

  auto t1 = std::chrono::steady_clock::now();
  int rc = OnInit();
  CHECK(rc == INIT_SUCCEEDED, "OnInit");
  CHECK(g_ea.m_ready, "warmup effectué dans OnInit");
  CHECK(g_ea.m_eng.m_bar == warm - 1, "warmup = toutes les bougies clôturées disponibles");
  datetime liveStart = bars[warm].t;

  // trades book de la période live (collectés aussi avant un redémarrage de l'EA)
  std::map<long, LRLTrade> book;
  auto collectBook = [&]() {
    for (int i = 0; i < ArraySize(g_ea.m_eng.m_closed); i++)
      if (g_ea.m_eng.m_closed[i].entryTime >= liveStart) book[g_ea.m_eng.m_closed[i].zoneId] = g_ea.m_eng.m_closed[i];
    for (int i = 0; i < ArraySize(g_ea.m_eng.m_open); i++)
      if (g_ea.m_eng.m_open[i].entryTime >= liveStart) book[g_ea.m_eng.m_open[i].zoneId] = g_ea.m_eng.m_open[i];
  };
  const int restartAt = (VARIANT == V_LIGHT) ? warm + 60000 + 37 : -1;

  int flatViolations = 0, windowViolations = 0, maxPos = 0, dirViolations = 0;
  std::map<long, int> perDay;
  size_t dealsSeen = 0;
  for (int i = warm; i < N; i++) {
    g_sim.cur = i;
    const Bar &b = bars[i];
    if (i == restartAt) {  // changement de paramètres : OnDeinit puis OnInit sur le même objet global
      collectBook();
      g_sim.setTick(b.t, b.o);
      OnDeinit(REASON_PARAMETERS);
      CHECK(OnInit() == INIT_SUCCEEDED && g_ea.m_ready, "redémarrage de l'EA");
    }
    double path[4] = {b.o, b.c >= b.o ? b.l : b.h, b.c >= b.o ? b.h : b.l, b.c};
    for (int k = 0; k < 4; k++) {
      g_sim.setTick(b.t + k * 15, path[k]);
      OnTick();
      int ny = g_ea.m_eng.NyMinute(g_sim.now);
      if (g_ea.m_eng.InFlatMin(ny) && (!g_sim.positions.empty() || !g_sim.orders.empty())) flatViolations++;
      maxPos = std::max(maxPos, (int)g_sim.positions.size());
    }
    if (i % 97 == 0) OnTimer();
    for (; dealsSeen < g_sim.deals.size(); dealsSeen++) {
      const SimDeal &d = g_sim.deals[dealsSeen];
      if (d.entry != DEAL_ENTRY_IN) continue;
      int ny = g_ea.m_eng.NyMinute(d.t);
      if (!g_ea.m_eng.InWindowMin(ny)) windowViolations++;
      if (VARIANT == V_MISC && d.type != 1) dirViolations++;
      perDay[(long)d.t / 86400]++;
    }
  }
  auto t2 = std::chrono::steady_clock::now();
  double ms = std::chrono::duration<double, std::milli>(t2 - t1).count();

  // ---------------------------------------------------------------- moteur identique à un moteur autonome
  CLRLEngine ref;
  ref.Init(g_ea.m_eng.cfg);
  for (int i = 0; i < N - 1; i++) ref.ProcessBar(bars[i].t, bars[i].o, bars[i].h, bars[i].l, bars[i].c);
  if (restartAt < 0) {
    CHECK(g_ea.m_eng.m_bar == ref.m_bar, "toutes les bougies clôturées traitées une seule fois");
    CHECK(g_ea.m_eng.m_stats.trades == ref.m_stats.trades && std::fabs(g_ea.m_eng.m_stats.netR - ref.m_stats.netR) < 1e-9,
          "statistiques identiques au moteur autonome");
  } else
    CHECK(g_ea.m_eng.LastBarTime() == bars[N - 2].t, "après redémarrage, traitement jusqu'à la dernière bougie clôturée");

  // ---------------------------------------------------------------- trades réels vs book
  collectBook();
  std::map<long, int> entriesPerZone;
  for (auto &d : g_sim.deals)
    if (d.entry == DEAL_ENTRY_IN) entriesPerZone[zoneOf(d.comment)]++;
  int dup = 0;
  for (auto &kv : entriesPerZone) dup += (kv.second > 1);
  CHECK(dup == 0, "jamais deux entrées réelles sur la même zone");

  struct Real { long zone; int type; double entry, exit, profit; datetime tin, tout; bool closed; int reason; double vol; double bal; };
  std::map<long, Real> real;
  double bal = 100000.0;
  for (auto &d : g_sim.deals) {
    long z = zoneOf(d.comment);
    if (d.entry == DEAL_ENTRY_IN) {
      Real r{z, d.type, d.price, 0, 0, d.t, 0, false, 0, d.vol, bal};
      real[z] = r;
    } else {
      auto it = real.find(z);
      if (it != real.end()) {
        it->second.exit = d.price;
        it->second.profit = d.profit;
        it->second.tout = d.t;
        it->second.closed = true;
        it->second.reason = d.reason;
      }
      bal += d.profit;
    }
  }
  int matched = 0, sameEntry = 0, sameOutcome = 0, comparable = 0, riskOk = 0, stopped = 0, beExits = 0;
  for (auto &kv : real) {
    auto it = book.find(kv.first);
    if (it == book.end()) continue;
    matched++;
    const LRLTrade &bt = it->second;
    double e = bt.dir < 0 ? std::ceil(bt.entry / 0.25 - 1e-9) * 0.25 : std::floor(bt.entry / 0.25 + 1e-9) * 0.25;
    if (std::fabs(kv.second.entry - e) < 1e-9 || (bt.dir < 0 ? kv.second.entry > e : kv.second.entry < e)) sameEntry++;
    if (kv.second.closed && !bt.open && bt.exitReason != LRL_EXIT_FLAT && kv.second.reason != 3) {
      comparable++;
      if ((kv.second.profit > 0) == (bt.r > 0)) sameOutcome++;
    }
    if (kv.second.closed && kv.second.reason == 2 && kv.second.profit >= 0.0) beExits++;
    if (kv.second.closed && kv.second.reason == 2 && VARIANT != V_MISC) {
      stopped++;
      double lossPct = -kv.second.profit / kv.second.bal * 100.0;
      // le volume est calculé sur le solde au placement de l'ordre limite : avec plusieurs positions
      // simultanées, le solde peut avoir changé avant l'exécution
      double maxPct = (VARIANT == V_MULTI) ? 0.56 : 0.5001;
      if (lossPct > 0.30 && lossPct <= maxPct) riskOk++;
      else if (getenv("DBG")) printf("    perte %.4f%% vol %.2f entrée %.2f sortie %.2f bal %.2f\n", lossPct, kv.second.vol, kv.second.entry, kv.second.exit, kv.second.bal);
    }
  }
  int bookN = (int)book.size(), realN = (int)real.size();
  printf("  %d bougies live en %.0f ms | book %d trades | réels %d (reliés au book %d, même entrée %d) | issue identique %d/%d | "
         "positions max %d | objets max %zu | erreurs ordres %d\n",
         N - warm, ms, bookN, realN, matched, sameEntry, sameOutcome, comparable, maxPos, g_sim.maxObjects, g_sim.orderErrors);

  CHECK(realN > 0, "des ordres réels sont exécutés");
  CHECK(matched == realN, "chaque trade réel correspond à un trade book (même zone)");
  CHECK(sameEntry == matched, "prix d'entrée réel = niveau book arrondi au tick (ou meilleur)");
  CHECK(g_sim.orderErrors == 0, "aucun ordre refusé");
  CHECK(flatViolations == 0, "rien d'ouvert pendant la fenêtre flat");
  CHECK(windowViolations == 0, "entrées uniquement dans la fenêtre");
  CHECK(g_sim.alerts == 0, "pas d'alertes popup dans le testeur");
  if (VARIANT != V_MISC)  // le break-even de la variante MISC change volontairement les issues
    CHECK(comparable == 0 || sameOutcome >= 0.9 * comparable, "issues réelles cohérentes avec le book (>= 90 %)");
  else
    CHECK(beExits > 0, "break-even déclenché (sorties au stop sans perte)");
  if (VARIANT != V_MISC) CHECK(stopped == 0 || riskOk == stopped, "perte au stop = 0.3 à 0.5 % du solde");
  if (VARIANT == V_DEFAULT || VARIANT == V_LIGHT) CHECK(maxPos <= 1, "au plus 1 position");
  if (VARIANT == V_MULTI) CHECK(realN >= 0.97 * bookN, "presque tous les trades book sont exécutés en réel");
  if (VARIANT == V_MISC) {
    CHECK(dirViolations == 0, "short uniquement");
    int maxDay = 0;
    for (auto &kv : perDay) maxDay = std::max(maxDay, kv.second);
    CHECK(maxDay <= 5, "5 trades par jour maximum");
  }
  CHECK(g_sim.maxObjects < 600, "nombre d'objets graphiques borné");
  bool hasTable = g_sim.objects.count("LRLM_TB_bg") > 0;
  CHECK(hasTable, "tableau affiché");
  bool hasLine = false;
  for (auto &kv : g_sim.objects)
    if (kv.first.rfind("LRLM_L", 0) == 0) hasLine = true;
  CHECK(hasLine, "lignes LRL dessinées");

  OnDeinit(REASON_REMOVE);
  CHECK(g_sim.objects.empty(), "objets supprimés au retrait de l'EA");
  CHECK(g_sim.orders.empty(), "ordres en attente supprimés au retrait de l'EA");
  if (VARIANT == V_MISC) {
    FILE *f = fopen("build/LRL_Map_NQ_M1.csv", "r");
    int lines = 0;
    char buf[512];
    while (f && fgets(buf, sizeof(buf), f)) lines++;
    if (f) fclose(f);
    CHECK(lines == g_ea.m_eng.ClosedTradeCount() + 1, "export CSV complet");
  }
  printf("  %d vérifications OK, %d échecs\n", g_pass, g_fail);
  return g_fail ? 1 : 0;
}

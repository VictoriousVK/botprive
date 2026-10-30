// Test de bout en bout de l'EA OPR_FVG_EA.mq5 (converti) sur un marché simulé tick par tick.
// Vérifie notamment les tests obligatoires 9 (backtest cohérent avec le journal des signaux)
// et 10 (aucun signal ni ordre dupliqué sur plusieurs ticks de la même bougie).
#include "mql5_api.h"
bool g_shim_quiet = true;
Sim g_sim;
string _Symbol = "NQ";
double _Point = 0.01;
int _Digits = 2;
ENUM_TIMEFRAMES _Period = PERIOD_M1;

#include "OPR_FVG_EA.cpp"
#include "synth.h"

#include <chrono>
#include <fstream>
#include <set>

#ifndef VARIANT
#define VARIANT 1
#endif
#define V_AUTO_TESTER 0   // fuseau serveur « auto » dans le testeur -> refus explicite
#define V_DEFAULT 1       // paramètres par défaut + fuseau serveur explicite
#define V_SIGNALS 2       // signaux seuls (aucun ordre)
#define V_BAD_SLOT 3      // OPR 2 tradé sans fenêtre -> refus explicite
#define V_RESTART 4       // redémarrage de l'EA en cours de route

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

static long mk(int y, int mo, int d, int h, int mi) {
  MqlDateTime s;
  memset(&s, 0, sizeof(s));
  s.year = y; s.mon = mo; s.day = d; s.hour = h; s.min = mi;
  return (long)StructToTime(s);
}

static long idOf(const std::string &cmt) {
  size_t p = cmt.rfind(' ');
  return p == std::string::npos ? 0 : atol(cmt.c_str() + p + 1);
}

struct JLine {
  std::string srv, st;
  int code, slot, dir, reason;
  long id;
  double p1, p2, p3, p4;
  std::string msg;
};

static std::vector<JLine> readJournal(const char *path) {
  std::vector<JLine> out;
  std::ifstream f(path);
  std::string line;
  bool header = true;
  while (std::getline(f, line)) {
    if (header) {
      header = false;
      continue;
    }
    std::vector<std::string> c;
    size_t a = 0;
    for (int k = 0; k < 11; k++) {
      size_t b = line.find(';', a);
      c.push_back(line.substr(a, b - a));
      a = b + 1;
    }
    c.push_back(line.substr(a));
    JLine j{c[0], c[1], atoi(c[2].c_str()), atoi(c[3].c_str()), atoi(c[4].c_str()), atoi(c[5].c_str()), atol(c[6].c_str()),
            atof(c[7].c_str()), atof(c[8].c_str()), atof(c[9].c_str()), atof(c[10].c_str()), c[11]};
    out.push_back(j);
  }
  return out;
}

int main() {
  const char *names[] = {"fuseau serveur auto dans le testeur", "paramètres par défaut (serveur GMT+2/+3 DST US)",
                         "signaux seuls", "OPR 2 tradé sans fenêtre", "redémarrage en cours de route"};
  printf("[test EA OPR] variante : %s\n", names[VARIANT]);
  remove("build/OPR_FVG_journal_NQ.csv");
  const int N = 130000;
  const int warm = 5000;
  auto bars = synth(N, 41 + VARIANT, (datetime)(mk(2025, 2, 2, 18, 0) + 7 * 3600));
  g_sim.bars.clear();
  for (auto &b : bars) g_sim.bars.push_back({b.t, b.o, b.h, b.l, b.c});
  g_sim.visual = 1;
  g_sim.cur = warm;
  g_sim.setTick(bars[warm].t, bars[warm].o);

  int rc = OnInit();
  if (VARIANT == V_AUTO_TESTER || VARIANT == V_BAD_SLOT) {
    CHECK(rc == INIT_PARAMETERS_INCORRECT, "paramètres refusés avec un message explicite");
    printf("  %d vérifications OK, %d échecs\n", g_pass, g_fail);
    return g_fail ? 1 : 0;
  }
  CHECK(rc == INIT_SUCCEEDED, "OnInit");
  CHECK(g_ea.m_ready, "historique rejoué");
  datetime liveStart = bars[warm].t;

  // trades book de la période live (collectés aussi avant un redémarrage : le moteur repart de zéro)
  std::set<long> bookFilled;
  auto collectBook = [&]() {
    for (int i = 0; i < ArraySize(g_ea.m_eng.m_closed); i++)
      if (g_ea.m_eng.m_closed[i].entrySrv >= liveStart) bookFilled.insert(g_ea.m_eng.m_closed[i].setupId);
    for (int i = 0; i < ArraySize(g_ea.m_eng.m_open); i++)
      if (g_ea.m_eng.m_open[i].entrySrv >= liveStart) bookFilled.insert(g_ea.m_eng.m_open[i].setupId);
  };
  auto t1 = std::chrono::steady_clock::now();
  int outsideWindow = 0, noStops = 0, maxPos = 0, authEvents = 0;
  std::map<long, int> authPerId;
  size_t dealsSeen = 0;
  const int restartAt = (VARIANT == V_RESTART) ? warm + 60000 + 523 : -1;
  for (int i = warm; i < N; i++) {
    g_sim.cur = i;
    const Bar &b = bars[i];
    if (i == restartAt) {
      collectBook();
      g_sim.setTick(b.t, b.o);
      OnDeinit(REASON_PARAMETERS);
      CHECK(OnInit() == INIT_SUCCEEDED && g_ea.m_ready, "redémarrage de l'EA");
    }
    double path[4] = {b.o, b.c >= b.o ? b.l : b.h, b.c >= b.o ? b.h : b.l, b.c};
    for (int k = 0; k < 4; k++) {
      g_sim.setTick(b.t + k * 15, path[k]);
      OnTick();
      maxPos = std::max(maxPos, (int)g_sim.positions.size());
      for (auto &p : g_sim.positions)
        if (p.sl <= 0 || p.tp <= 0) noStops++;
    }
    if (i % 97 == 0) OnTimer();
    for (; dealsSeen < g_sim.deals.size(); dealsSeen++) {
      const SimDeal &d = g_sim.deals[dealsSeen];
      if (d.entry != DEAL_ENTRY_IN) continue;
      int m = g_ea.m_eng.tm.MinuteOfDay(g_ea.m_eng.tm.StratTime(d.t));
      if (!(m >= 2 * 60 + 50 && m < 4 * 60 + 10)) outsideWindow++;
    }
  }
  auto t2 = std::chrono::steady_clock::now();
  double ms = std::chrono::duration<double, std::milli>(t2 - t1).count();
  collectBook();
  OnDeinit(REASON_REMOVE);

  // ------------------------------------------------------------------ journal CSV écrit par l'EA
  auto J = readJournal("build/OPR_FVG_journal_NQ.csv");
  std::map<long, JLine> auth;
  std::map<std::string, int> biasOfDay;  // date serveur -> sens
  int oprFinal = 0;
  for (auto &j : J) {
    if (j.code == J_ENTRY_AUTHORIZED) {
      auth[j.id] = j;
      authPerId[j.id]++;
      authEvents++;
    }
    if (j.code == J_OPR_FINAL && j.slot == 1) oprFinal++;
  }
  int dupAuth = 0;
  for (auto &kv : authPerId) dupAuth += (kv.second > 1);

  // ------------------------------------------------------------------ ordres et deals réels
  std::map<long, int> fillsPerId;
  int realIn = 0, notLogged = 0, levelsMismatch = 0, dirMismatch = 0, riskOk = 0, stopped = 0;
  double bal = 100000.0;
  std::map<long, double> balAt;
  for (auto &d : g_sim.deals) {
    long id = idOf(d.comment);
    if (d.entry == DEAL_ENTRY_IN) {
      realIn++;
      fillsPerId[id]++;
      balAt[id] = bal;
      auto it = auth.find(id);
      if (it == auth.end()) {
        notLogged++;
        continue;
      }
      int dir = d.type == 0 ? 1 : -1;
      if (dir != it->second.dir) dirMismatch++;
      // entrée réelle = niveau autorisé arrondi au tick (ou meilleur en cas d'entrée au marché)
      double e = dir < 0 ? std::ceil(it->second.p1 / 0.25 - 1e-9) * 0.25 : std::floor(it->second.p1 / 0.25 + 1e-9) * 0.25;
      if (!(std::fabs(d.price - e) < 1e-9 || (dir < 0 ? d.price > e : d.price < e))) levelsMismatch++;
    } else {
      bal += d.profit;
      if (d.reason == 2) {
        stopped++;
        double pct = -d.profit / balAt[id] * 100.0;
        if (pct > 0.25 && pct <= 0.5001) riskOk++;
      }
    }
  }
  int dupFill = 0, dupPlaced = 0;
  for (auto &kv : fillsPerId) dupFill += (kv.second > 1);
  for (auto &kv : g_sim.placed) dupPlaced += (kv.second > 1);

  // ------------------------------------------------------------------ book vs réel (période live)
  int both = 0;
  for (auto &kv : fillsPerId) both += bookFilled.count(kv.first);

  const OStats &s = g_ea.m_eng.stats;
  printf("  %d bougies live (%d ticks/bougie) en %.0f ms | %d jours | autorisations journalisées %d | ordres réels exécutés %d | "
         "book %d | communs %d | positions max %d | objets max %zu | erreurs ordres %d\n",
         N - warm, 4, ms, s.days, authEvents, realIn, (int)bookFilled.size(), both, maxPos, g_sim.maxObjects, g_sim.orderErrors);

  CHECK(oprFinal > 20, "journal CSV : un OPR finalisé par jour");
  CHECK(authEvents > 0, "des entrées sont autorisées");
  CHECK(dupAuth == 0, "test 10 : une seule autorisation par setup malgré 4 ticks par bougie");
  CHECK(g_sim.alerts == 0, "pas d'alertes popup dans le testeur");
  if (VARIANT == V_SIGNALS) {
    CHECK(g_sim.deals.empty() && g_sim.placed.empty(), "signaux seuls : aucun ordre envoyé");
  } else {
    CHECK(realIn > 0, "des ordres réels sont exécutés");
    CHECK(notLogged == 0, "test 9 : chaque exécution réelle correspond à une autorisation du journal");
    CHECK(dirMismatch == 0, "test 6 : sens réel = sens autorisé");
    CHECK(levelsMismatch == 0, "prix d'entrée réel = niveau du journal arrondi au tick (ou meilleur)");
    CHECK(dupFill == 0 && dupPlaced == 0, "test 10 : jamais deux ordres pour le même setup");
    CHECK(outsideWindow == 0, "entrées réelles uniquement dans la fenêtre 02:50-04:10 NY");
    CHECK(noStops == 0, "toutes les positions ont un stop et une cible");
    CHECK(maxPos <= 1, "1 position maximum");
    CHECK(g_sim.orderErrors == 0, "aucun ordre refusé par le serveur simulé");
    CHECK(stopped == 0 || riskOk == stopped, "perte au stop = 0,25 à 0,5 % du solde");
    CHECK(both >= 0.9 * realIn, "trades réels = trades du modèle book (>= 90 %)");
  }
  CHECK(g_sim.maxObjects < 800, "objets graphiques bornés");
  CHECK(g_sim.objects.empty(), "objets supprimés au retrait de l'EA");
  CHECK(g_sim.orders.empty(), "ordres en attente supprimés au retrait de l'EA");
  CHECK(GlobalVariableCheck("OPRFVG_26101201_NQ_0_H"), "OPR du jour sauvegardé (persistance)");
  printf("  %d vérifications OK, %d échecs\n", g_pass, g_fail);
  return g_fail ? 1 : 0;
}

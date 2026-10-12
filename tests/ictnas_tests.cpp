// Test de bout en bout d'ICT_NAS_Institutional (converti en C++) sur un marché simulé tick par tick.
//   -DICT_SRC="ICT_v230.cpp" -DV230=1 : nouvelle version (fusion avec le moteur OPR + FVG)
//   -DICT_SRC="ICT_v222.cpp" -DV230=0 : version d'origine (référence du comparatif avant / après)
// Chaque exécution écrit aussi une ligne « STATS;... » lue par compare_ictnas.py.
#include "mql5_api.h"
bool g_shim_quiet = true;
Sim g_sim;
string _Symbol = "NQ";
double _Point = 0.01;
int _Digits = 2;
ENUM_TIMEFRAMES _Period = PERIOD_M1;

#include ICT_SRC
#include "synth.h"

#include <chrono>
#include <fstream>
#include <set>

#ifndef VARIANT
#define VARIANT 0
#endif
#ifndef SEED
#define SEED 71
#endif
#ifndef LIVE_DAYS
#define LIVE_DAYS 60
#endif
#ifndef LABEL
#define LABEL "-"
#endif
#define V_DEFAULT 0   // paramètres par défaut
#define V_SIGNALS 1   // observation : aucun ordre
#define V_RESTART 2   // redémarrage de l'EA en cours de route
#define V_LEGACY 3    // London OPR v2.22 (moteur PDF en observation)
#define V_BADCFG 4    // OPR 2 tradé sans fenêtre -> refus explicite
#define V_VISUAL 5    // mode visuel (tracés, panneau), gestion ICT NAS des trades London, spread 1 tick
#define V_COMPARE 9   // comparatif seulement (pas de contrôle spécifique)

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

static const long kMagic = 26092801;
static long nyOf(datetime srv) { return (long)srv - 7 * 3600; }               // serveur = NY + 7 h (TZ_NY_PLUS_7)
static long tradingDay(datetime srv) { return (nyOf(srv) + 6 * 3600) / 86400; }  // le jour ICT commence à 18:00 NY
[[maybe_unused]] static int nyMinute(datetime srv) { return (int)(((nyOf(srv) % 86400) + 86400) % 86400 / 60); }
static std::string modelOf(const std::string &cmt) { return cmt.substr(0, cmt.find(' ')); }

struct JLine {
  int code, slot, dir, reason;
  long id;
  double p1, p2, p3;
};
[[maybe_unused]] static std::vector<JLine> readJournal(const char *path) {
  std::vector<JLine> out;
  std::ifstream f(path);
  std::string line;
  bool header = true;
  while (std::getline(f, line)) {
    if (header) { header = false; continue; }
    std::vector<std::string> c;
    size_t a = 0;
    for (int k = 0; k < 11; k++) {
      size_t b = line.find(';', a);
      if (b == std::string::npos) break;
      c.push_back(line.substr(a, b - a));
      a = b + 1;
    }
    if (c.size() < 10) continue;
    out.push_back({atoi(c[2].c_str()), atoi(c[3].c_str()), atoi(c[4].c_str()), atoi(c[5].c_str()), atol(c[6].c_str()),
                   atof(c[7].c_str()), atof(c[8].c_str()), atof(c[9].c_str())});
  }
  return out;
}

static std::map<std::string, int> sqlCount(const char *sql) {
  std::map<std::string, int> out;
  sqlite3 *db = nullptr;
  if (sqlite3_open_v2("build/common/ICTNAS/ict_nas.sqlite", &db, SQLITE_OPEN_READONLY, nullptr) != SQLITE_OK) return out;
  sqlite3_stmt *st = nullptr;
  if (sqlite3_prepare_v2(db, sql, -1, &st, nullptr) == SQLITE_OK) {
    while (sqlite3_step(st) == SQLITE_ROW) {
      const unsigned char *k = sqlite3_column_text(st, 0);
      out[k ? (const char *)k : "NULL"] = sqlite3_column_int(st, 1);
    }
    sqlite3_finalize(st);
  }
  sqlite3_close(db);
  return out;
}

int main(int argc, char **argv) {
  const int seed = argc > 1 ? atoi(argv[1]) : SEED;
  const char *names[] = {"défaut", "observation (aucun ordre)", "redémarrage en cours de route", "London v2.22 (moteur PDF en observation)",
                         "OPR 2 tradé sans fenêtre", "visuel + gestion ICT NAS du London + spread", "", "", "", "comparatif"};
  printf("[test ICT NAS %s] variante : %s (graine %d)\n", V230 ? "v2.30" : "v2.22", names[VARIANT], seed);
  const int histDays = 70;
  const int liveDays = (VARIANT == V_VISUAL) ? 12 : LIVE_DAYS;
  const int N = (histDays + liveDays) * 1440;
  const int warm = histDays * 1440;
  auto bars = synth(N, seed, (datetime)(mk(2025, 1, 5, 18, 0) + 7 * 3600));
  g_sim = Sim();
  for (auto &b : bars) g_sim.bars.push_back({b.t, b.o, b.h, b.l, b.c});
  g_sim.visual = (VARIANT == V_VISUAL) ? 1 : 0;
  g_sim.spread = (VARIANT == V_VISUAL) ? 0.25 : 0.0;
  g_sim.cur = warm;
  g_sim.setTick(bars[warm].t, bars[warm].o);
  // fichiers d'une exécution précédente (la variante « redémarrage » simule le live : l'EA ne les vide pas)
  remove("build/common/ICTNAS/ict_nas.sqlite");
  remove("build/common/ICTNAS/NQ_london_opr_journal.csv");
  remove("build/common/ICTNAS/NQ_signals.csv");
  remove("build/common/ICTNAS/NQ_day_context.csv");
  remove("build/common/ICTNAS/NQ_trades.csv");

  int rc = OnInit();
  if (VARIANT == V_BADCFG) {
    CHECK(rc == INIT_PARAMETERS_INCORRECT, "configuration refusée avec un message explicite");
    OnDeinit(REASON_INITFAILED);
    printf("  %d vérifications OK, %d échecs\n", g_pass, g_fail);
    return g_fail ? 1 : 0;
  }
  CHECK(rc == INIT_SUCCEEDED, "OnInit");
#if V230
  CHECK(g_loReady, "moteur London OPR : historique rejoué au démarrage");
  std::set<long> bookFilled;
  datetime liveStart = bars[warm].t;
  auto collectBook = [&]() {
    for (int i = 0; i < ArraySize(g_lo.m_closed); i++)
      if (g_lo.m_closed[i].entrySrv >= liveStart) bookFilled.insert(g_lo.m_closed[i].setupId);
    for (int i = 0; i < ArraySize(g_lo.m_open); i++)
      if (g_lo.m_open[i].entrySrv >= liveStart) bookFilled.insert(g_lo.m_open[i].setupId);
  };
#endif

  auto t1 = std::chrono::steady_clock::now();
  int maxPos = 0, bothDirs = 0, noStops = 0;
  const int restartAt = (VARIANT == V_RESTART) ? warm + 25 * 1440 + 177 : -1;
  for (int i = warm; i < N; i++) {
    g_sim.cur = i;
    const Bar &b = bars[i];
    if (i == restartAt) {
#if V230
      collectBook();
#endif
      g_sim.setTick(b.t, b.o);
      OnDeinit(REASON_PARAMETERS);
      CHECK(OnInit() == INIT_SUCCEEDED, "redémarrage de l'EA");
    }
    double path[4] = {b.o, b.c >= b.o ? b.l : b.h, b.c >= b.o ? b.h : b.l, b.c};
    for (int k = 0; k < 4; k++) {
      g_sim.setTick(b.t + k * 15, path[k]);
      OnTick();
      int n = 0, dirs = 0;
      for (auto &p : g_sim.positions) {
        if (p.magic != kMagic) continue;
        n++;
        dirs |= (p.type == 0 ? 1 : 2);
        if (p.sl <= 0 || p.tp <= 0) noStops++;
      }
      maxPos = std::max(maxPos, n);
      if (dirs == 3) bothDirs++;
    }
  }
  auto t2 = std::chrono::steady_clock::now();
  double ms = std::chrono::duration<double, std::milli>(t2 - t1).count();
#if V230
  collectBook();
#endif
  OnDeinit(REASON_REMOVE);

  // ------------------------------------------------------------------ deals réels
  struct PosInfo { std::string model, cmt; int dir; double entry, vol, bal, pnl; datetime t; bool sl; };
  std::map<ulong, PosInfo> pos;
  std::map<long, int> fillsPerDay;
  std::map<std::string, int> fillsByModel;
  double bal = 100000.0;
  int afterDailyStop = 0;
  std::map<long, double> dayStartBal, dayRealized;
  for (auto &d : g_sim.deals) {
    if (d.magic != kMagic) {
      bal += d.profit;
      continue;
    }
    long day = tradingDay(d.t);
    if (!dayStartBal.count(day)) dayStartBal[day] = bal;
    if (d.entry == DEAL_ENTRY_IN) {
      if (dayRealized[day] <= -0.02 * dayStartBal[day] - 1e-6) afterDailyStop++;
      pos[d.posId] = {modelOf(d.comment), d.comment, d.type == 0 ? 1 : -1, d.price, d.vol, bal, 0.0, d.t, false};
      fillsPerDay[day]++;
      fillsByModel[modelOf(d.comment)]++;
    } else {
      bal += d.profit;
      dayRealized[day] += d.profit;
      auto it = pos.find(d.posId);
      if (it != pos.end()) {
        it->second.pnl += d.profit;
        if (d.reason == 2) it->second.sl = true;
      }
    }
  }
  int fills = 0, maxPerDay = 0, wins = 0, losses = 0, riskBad = 0;
  double maxLossPct = 0.0;
  for (auto &kv : fillsPerDay) { fills += kv.second; maxPerDay = std::max(maxPerDay, kv.second); }
  for (auto &kv : pos) {
    const PosInfo &p = kv.second;
    if (p.pnl > 0) wins++; else if (p.pnl < 0) losses++;
    double lossPct = -p.pnl / p.bal * 100.0;
    maxLossPct = std::max(maxLossPct, lossPct);
  }
  int days = (int)liveDays;
  double netPct = (g_sim.balance - 100000.0) / 1000.0;

  // ------------------------------------------------------------------ base SQLite écrite par l'EA
  auto sigByModel = sqlCount("SELECT model, COUNT(*) FROM signals GROUP BY model");
  auto sigByDecision = sqlCount("SELECT decision || CASE WHEN reject_reason IS NULL THEN '' ELSE ' | ' || "
                                "CASE WHEN reject_reason LIKE 'RR %' THEN 'RR < min' WHEN reject_reason LIKE 'score %' THEN 'score < min' "
                                "WHEN reject_reason LIKE 'SL trop large%' THEN 'SL trop large' ELSE reject_reason END END, COUNT(*) "
                                "FROM signals GROUP BY 1 ORDER BY 2 DESC");
  auto takenByModel = sqlCount("SELECT model, COUNT(*) FROM signals WHERE decision='TAKEN' GROUP BY model");
  auto tradeRows = sqlCount("SELECT 'n', COUNT(*) FROM trades");
  int sigTotal = 0;
  for (auto &kv : sigByModel) sigTotal += kv.second;

  printf("  %d jours live (%d ticks) en %.0f ms | ordres exécutés %d (%.2f/jour, max %d/jour) | positions max %d | "
         "signaux enregistrés %d | lignes trades %d | erreurs ordres %d | erreurs SQL %d\n",
         days, (N - warm) * 4, ms, fills, (double)fills / days, maxPerDay, maxPos, sigTotal, tradeRows["n"], g_sim.orderErrors,
         g_sim.dbErrors);
  printf("  exécutés par modèle :");
  for (auto &kv : fillsByModel) printf(" %s=%d", kv.first.c_str(), kv.second);
  printf("\n  décisions des signaux :");
  int shown = 0;
  for (auto &kv : sigByDecision)
    if (shown++ < 12) printf("\n     %5d  %s", kv.second, kv.first.c_str());
  printf("\n");

  // ligne lue par compare_ictnas.py
  printf("STATS;%s;%s;%d;%d;%d;%d;%d;%.2f;%.3f;%d", LABEL, V230 ? "v2.30" : "v2.22", seed, days, fills, wins, losses, netPct,
         maxLossPct, sigTotal);
  for (auto &kv : fillsByModel) printf(";F:%s=%d", kv.first.c_str(), kv.second);
  for (auto &kv : sigByDecision) printf(";D:%s=%d", kv.first.c_str(), kv.second);
  printf("\n");

  // ------------------------------------------------------------------ contrôles communs
  CHECK(g_sim.dbErrors == 0, "toutes les requêtes SQL de l'EA sont valides");
  CHECK(sigTotal > 0, "des signaux sont enregistrés dans SQLite");
  CHECK(noStops == 0, "toutes les positions ont un stop et une cible");
  CHECK(bothDirs == 0, "jamais d'achat et de vente ouverts en même temps");
  if (VARIANT == V_SIGNALS) {
    CHECK(fills == 0 && g_sim.orders.empty(), "observation : aucun ordre de l'EA");
  }

#if V230
  // ------------------------------------------------------------------ contrôles v2.30
  auto J = readJournal("build/common/ICTNAS/NQ_london_opr_journal.csv");
  std::map<long, JLine> auth;
  std::map<long, int> authCount;
  int oprFinal = 0;
  for (auto &j : J) {
    if (j.code == J_ENTRY_AUTHORIZED) { auth[j.id] = j; authCount[j.id]++; }
    if (j.code == J_OPR_FINAL && j.slot == 1) oprFinal++;
  }
  int dupAuth = 0;
  for (auto &kv : authCount) dupAuth += kv.second > 1;
  int loFills = 0, loNotAuth = 0, loDir = 0, loLevel = 0, loOutside = 0, loBoth = 0, dupPlaced = 0;
  for (auto &kv : pos) {
    const PosInfo &p = kv.second;
    if (p.model != "LONDON_OPR_PDF") continue;
    loFills++;
    long id = atol(p.cmt.c_str() + p.cmt.find(" LP") + 3);
    auto it = auth.find(id);
    if (it == auth.end()) { loNotAuth++; continue; }
    if (it->second.dir != p.dir) loDir++;
    double e = p.dir < 0 ? std::ceil(it->second.p1 / 0.25 - 1e-9) * 0.25 : std::floor(it->second.p1 / 0.25 + 1e-9) * 0.25;
    double risk = std::fabs(it->second.p1 - it->second.p2);
    double deep = p.dir * (e - p.entry);  // > 0 : entrée au marché plus loin que le niveau
    if (deep > 0.25 * risk + 1e-9) loLevel++;
    int m = nyMinute(p.t);
    if (m < 2 * 60 + 50 || m >= 4 * 60 + 10) loOutside++;
    loBoth += bookFilled.count(id);
  }
  for (auto &kv : g_sim.placed)
    if (kv.first.rfind("LONDON_OPR_PDF", 0) == 0 && kv.second > 1) dupPlaced++;

  printf("  London OPR PDF : autorisations %d | exécutés réels %d | book %d | communs %d | rejetés hors fenêtre %d\n",
         (int)auth.size(), loFills, (int)bookFilled.size(), loBoth, loOutside);
  CHECK(oprFinal >= days / 2, "journal CSV : MOR finalisé chaque jour");
  CHECK(dupAuth == 0, "test 10 : une seule autorisation par setup malgré 4 ticks par bougie");
  CHECK(dupPlaced == 0, "test 10 : jamais deux ordres pour le même setup London (y compris après redémarrage)");
  CHECK(loNotAuth == 0, "test 9 : chaque exécution London correspond à une autorisation du journal");
  CHECK(loDir == 0, "test 6 : sens réel = sens autorisé");
  CHECK(loLevel == 0, "entrée réelle = niveau autorisé arrondi au tick (ou au plus 0,25 R plus loin)");
  CHECK(loOutside == 0, "entrées London uniquement dans la fenêtre 02:50-04:10 NY");
  if (VARIANT != V_COMPARE) {  // le comparatif peut utiliser d'autres réglages de risque
    CHECK(maxPos <= 2, "2 positions simultanées maximum");
    CHECK(maxPerDay <= 3, "3 trades exécutés maximum par jour de trading");
    CHECK(afterDailyStop == 0, "aucune entrée après le stop journalier (-2 %)");
    CHECK(maxLossPct <= 1.05, "perte maximale par trade <= 1 % du solde (+ arrondi)");
  }
  CHECK(GlobalVariableCheck("ICTNAS_26092801_NQ_LO0_H"), "MOR du jour sauvegardé (persistance)");
  if (VARIANT == V_DEFAULT || VARIANT == V_RESTART) {
    CHECK(loFills > 0, "le modèle London OPR PDF prend des trades");
    CHECK(loBoth >= 0.9 * loFills, "trades London réels = trades du modèle book (>= 90 %)");
    CHECK(takenByModel["LONDON_OPR_PDF"] > 0, "signaux London PDF enregistrés comme TAKEN");
  }
  if (VARIANT == V_LEGACY) {
    CHECK(sigByModel["LONDON_OPR_PDF"] == 0, "mode v2.22 : aucun signal London PDF");
    CHECK(auth.size() > 0, "mode v2.22 : le moteur PDF continue à journaliser");
  }
  if (VARIANT == V_VISUAL) {
    CHECK(g_sim.maxObjects > 0, "tracés et panneau créés en mode visuel");
    CHECK(g_sim.objects.empty(), "objets supprimés au retrait de l'EA");
  }
#endif
  printf("  %d vérifications OK, %d échecs\n", g_pass, g_fail);
  return g_fail ? 1 : 0;
}

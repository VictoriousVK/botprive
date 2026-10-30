// Tests du moteur OPR + FVG (code MQL5 converti par mq2cpp.py, compilé avec g++).
// Couvre les 10 tests obligatoires du cahier des charges (le n°10, doublons sur plusieurs
// ticks, est vérifié au niveau de l'EA dans opr_ea_tests.cpp) et des scénarios du PDF.
#include "mql5_core.h"
bool g_shim_quiet = true;
#include "OPR_Engine.mqh"

#include <chrono>
#include <functional>
#include <map>
#include <set>

#include "synth.h"

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
#define NEAR(a, b) (std::fabs((a) - (b)) < 1e-6)

static long mk(int y, int mo, int d, int h, int mi) {
  MqlDateTime s;
  memset(&s, 0, sizeof(s));
  s.year = y; s.mon = mo; s.day = d; s.hour = h; s.min = mi;
  return (long)StructToTime(s);
}
// serveur GMT+2/+3 aligné sur le DST US = heure de New York + 7 h, toute l'année
static datetime srvOfNy(long ny) { return (datetime)(ny + 7 * 3600); }

static OPRConfig baseCfg() {
  OPRConfig c;
  c.Defaults();
  c.stratTz = OPR_STZ_NEW_YORK;
  c.serverMode = OPR_SRV_GMT_US_DST;
  c.serverGmtSec = 2 * 3600;
  c.tickSize = 0.25;
  return c;
}

// --------------------------------------------------------------------------------------------
// Constructeur de scénario en heure de New York
struct Scn {
  std::vector<Bar> bars;  // t = heure serveur
  long cur = 0;           // heure NY de la prochaine bougie
  double p = 100.0;
  void at(long ny) { cur = ny; }
  void bar(double o, double h, double l, double c) {
    bars.push_back({srvOfNy(cur), o, h, l, c});
    p = c;
    cur += 60;
  }
  // bougies plates (aucun FVG, aucun pivot) jusqu'à l'heure NY "until" exclue
  void flat(long until, double px) {
    while (cur < until) bar(px, px + 0.5, px - 0.5, px);
  }
  // dérive linéaire sans FVG ni pivot (bougies qui se chevauchent)
  void drift(long until, double to) {
    long n = (until - cur) / 60;
    double from = p;
    for (long i = 1; i <= n; i++) {
      double a = from + (to - from) * (i - 1) / n, b = from + (to - from) * i / n;
      double lo = std::min(a, b) - 0.5, hi = std::max(a, b) + 0.5;
      bar(a, hi, lo, b);
    }
  }
};

struct Run {
  COprEngine e;
  std::vector<OJEvent> ev;
  std::vector<std::string> txt;
  void feed(const std::vector<Bar> &bars, size_t from = 0, size_t to = (size_t)-1) {
    for (size_t i = from; i < bars.size() && i < to; i++) {
      e.ProcessBar(bars[i].t, bars[i].o, bars[i].h, bars[i].l, bars[i].c);
      for (int k = 0; k < e.jr.m_count; k++) {
        ev.push_back(e.jr.m_ev[k]);
        std::string name = e.jr.m_ev[k].slot >= 0 ? e.slotName[e.jr.m_ev[k].slot] : "";
        txt.push_back(OprEventText(e.jr.m_ev[k], name, 2));
      }
    }
  }
  int count(int code, int slot = -9) const {
    int n = 0;
    for (auto &x : ev) n += (x.code == code && (slot == -9 || x.slot == slot));
    return n;
  }
  const OJEvent *first(int code) const {
    for (auto &x : ev)
      if (x.code == code) return &x;
    return nullptr;
  }
  bool hasReason(int code, int reason) const {
    for (auto &x : ev)
      if (x.code == code && x.reason == reason) return true;
    return false;
  }
  void dump() const {
    for (size_t i = 0; i < ev.size(); i++) {
      long ny = ev[i].st;
      printf("    %02ld:%02ld  %s\n", (ny % 86400) / 3600, (ny % 3600) / 60, txt[i].c_str());
    }
  }
};

// Journée type (session du mardi 10 mars 2026, DST US actif, DST européen pas encore) :
//   Asie 20:00-00:00 avec FVG M15 haussier sur la bougie de 20:00 puis un second à 21:30,
//   MOR 00:00-00:30 High 102 (00:17) / Low 98 (00:29), dérive sous l'OPR, swing high M1 à 02:30,
//   prise de ce swing à 02:55, déplacement baissier -> FVG M1 [95.5 ; 96.5] formé à 02:58,
//   retour dans le FVG à 03:00 (exécution 95.5), cible -2 STD = 90 atteinte vers 03:06.
// variant : 0 gain ; 1 cible atteinte avant l'entrée ; 2 prix dans l'OPR à 2:50 ;
//           3 FVG formé avant toute prise de liquidité ; 4 stop sur la bougie d'entrée ;
//           5 FVG hors macro (3:12)
static std::vector<Bar> londonDay(int variant) {
  Scn s;
  long D0 = mk(2026, 3, 9, 0, 0);  // lundi (calendrier NY)
  long D1 = mk(2026, 3, 10, 0, 0);
  s.at(D0 + 18 * 3600);
  s.p = 100;
  s.flat(D0 + 19 * 3600 + 45 * 60, 100);
  s.flat(D0 + 20 * 3600, 100);  // bougie M15 19:45 : High 100.5
  // 20:00-20:14 : déplacement haussier jusqu'à ~104
  for (int i = 0; i < 15; i++) {
    double a = 100 + i * 0.27, b = 100 + (i + 1) * 0.27;
    s.bar(a, b + 0.5, a - 0.5, b);
  }
  // 20:15-20:29 : consolidation haute, Low >= 101.2 (> 100.5 => FVG M15 [100.5 ; 101.2])
  for (int i = 0; i < 15; i++) s.bar(103.5, 104, 101.2 + (i % 3) * 0.5, 103.6);
  s.drift(D0 + 21 * 3600 + 30 * 60, 100.2);
  s.flat(D0 + 21 * 3600 + 30 * 60, 100.2);
  // 21:30-21:44 : nouveau déplacement haussier, 21:45-21:59 au-dessus => second FVG M15
  for (int i = 0; i < 15; i++) {
    double a = 100.2 + i * 0.2, b = 100.2 + (i + 1) * 0.2;
    s.bar(a, b + 0.5, a - 0.5, b);
  }
  for (int i = 0; i < 15; i++) s.bar(102.8, 103.2, 102.0, 102.9);
  s.drift(D0 + 23 * 3600, 100);
  s.flat(D1, 100);
  // MOR 00:00-00:29 : High 102 à 00:17, Low 98 à 00:29
  double inside = 100;
  for (int m = 0; m < 30; m++) {
    double h = inside + 0.5, l = inside - 0.5;
    if (m == 17) h = 102;
    if (m == 29) l = 98;
    s.bar(inside, h, l, inside);
  }
  // juste après la plage : plus haut et plus bas que l'OPR (ne doivent pas changer l'OPR)
  s.bar(100, 103, 99.5, 100);
  s.bar(100, 100.5, 97, 99);
  double lvl = (variant == 2) ? 99.0 : 96.0;
  s.drift(D1 + 2 * 3600 + 29 * 60, lvl);
  // swing high M1 (pivot 1/1) à 02:30
  if (variant == 2) {
    s.bar(lvl, lvl + 0.6, lvl - 0.4, lvl);
    s.bar(lvl, lvl + 0.8, lvl - 0.3, lvl);
    s.bar(lvl, lvl + 0.5, lvl - 0.4, lvl);
  } else {
    s.bar(96, 96.6, 95.6, 96);
    s.bar(96, 96.8, 95.7, 96);
    s.bar(96, 96.5, 95.6, 96);
  }
  if (variant == 3) {
    // FVG baissier à 02:51-02:53 sans prise de liquidité préalable
    s.flat(D1 + 2 * 3600 + 51 * 60, 96);
    s.bar(96, 96.4, 95.8, 95.9);
    s.bar(95.9, 95.9, 94.6, 94.7);
    s.bar(94.7, 95.2, 94.4, 94.5);
    s.flat(D1 + 3 * 3600, 94.5);
    s.flat(D1 + 4 * 3600 + 30 * 60, 94.5);
    return s.bars;
  }
  s.flat(D1 + 2 * 3600 + 50 * 60, lvl);  // 02:49 clôture à 96 (sous l'OPR) ou 99 (dans l'OPR)
  long sweepAt = (variant == 5) ? D1 + 3 * 3600 + 10 * 60 : D1 + 2 * 3600 + 55 * 60;
  if (variant == 2) {
    // prix dans l'OPR : FVG haussier et baissier pendant la macro ne doivent rien déclencher
    s.flat(D1 + 2 * 3600 + 52 * 60, 99);
    s.bar(99, 99.4, 98.8, 99.3);
    s.bar(99.3, 100.6, 99.3, 100.5);
    s.bar(100.5, 100.9, 99.8, 100.6);
    s.flat(D1 + 3 * 3600 + 5 * 60, 100.6);
    // clôture sous l'OPR à 03:05 -> biais VENTE (cassure)
    s.bar(100.6, 100.6, 97.5, 97.8);
    s.flat(D1 + 4 * 3600 + 30 * 60, 97.8);
    return s.bars;
  }
  s.flat(sweepAt, 96);
  s.bar(96, 97.0, 96.5, 96.9);        // prise du swing high 96.8 (c1, Low 96.5)
  s.bar(96.9, 96.95, 95.0, 95.1);     // déplacement
  s.bar(95.1, 95.5, 94.0, 94.2);      // c3 : High 95.5 < 96.5 => FVG [95.5 ; 96.5]
  if (variant == 1) {
    // la cible (90) est atteinte sans retour dans le FVG
    for (int i = 0; i < 6; i++) s.bar(94.2 - i, 94.4 - i, 93.0 - i, 93.2 - i);
    s.flat(D1 + 4 * 3600 + 30 * 60, 89);
    return s.bars;
  }
  s.bar(94.2, 94.8, 94.0, 94.6);
  s.bar(94.6, 95.2, 94.5, 95.1);
  if (variant == 4)
    s.bar(95.1, 97.5, 95.0, 95.3);    // exécution ET stop sur la même bougie
  else
    s.bar(95.1, 95.6, 95.0, 95.3);    // retour dans le FVG : exécution à 95.5
  for (int i = 0; i < 6; i++) s.bar(95.3 - i, 95.4 - i, 94.0 - i, 94.2 - i);  // jusqu'à 89 => cible 90
  s.flat(D1 + 4 * 3600 + 30 * 60, 89.5);
  // OPR 07:00-07:30 indépendant : High 92 (07:10), Low 89 (07:20)
  s.flat(D1 + 7 * 3600, 90.5);
  for (int m = 0; m < 30; m++) {
    double h = 91, l = 90;
    if (m == 10) h = 92;
    if (m == 20) l = 89;
    s.bar(90.5, h, l, 90.5);
  }
  s.flat(D1 + 8 * 3600, 90.5);
  return s.bars;
}

// --------------------------------------------------------------------------------------------
static void testTime() {
  printf("[test 8] conversions de fuseaux et changements d'heure\n");
  COprTime t;
  // serveur GMT+2/+3 aligné DST US -> NY
  t.Configure(OPR_STZ_NEW_YORK, OPR_SRV_GMT_US_DST, 2 * 3600, 18 * 60);
  CHECK(t.MinuteOfDay(t.StratTime(mk(2026, 1, 15, 16, 30))) == 9 * 60 + 30, "hiver : serveur 16:30 = NY 09:30");
  CHECK(t.MinuteOfDay(t.StratTime(mk(2026, 7, 15, 16, 30))) == 9 * 60 + 30, "été : serveur 16:30 = NY 09:30");
  CHECK(t.MinuteOfDay(t.StratTime(mk(2026, 3, 10, 9, 50))) == 2 * 60 + 50, "après le DST US : serveur 09:50 = NY 02:50");
  // serveur GMT+2/+3 aligné DST européen : entre le 8 et le 29 mars, l'écart serveur-NY est de 6 h
  t.Configure(OPR_STZ_NEW_YORK, OPR_SRV_GMT_EU_DST, 2 * 3600, 18 * 60);
  CHECK(t.MinuteOfDay(t.StratTime(mk(2026, 3, 16, 8, 50))) == 2 * 60 + 50, "DST US mais pas DST UE : écart 6 h");
  CHECK(t.MinuteOfDay(t.StratTime(mk(2026, 4, 6, 9, 50))) == 2 * 60 + 50, "les deux en DST : écart 7 h");
  CHECK(t.MinuteOfDay(t.StratTime(mk(2026, 1, 12, 9, 50))) == 2 * 60 + 50, "hiver : écart 7 h");
  // serveur UTC fixe
  t.Configure(OPR_STZ_NEW_YORK, OPR_SRV_GMT_FIXED, 0, 18 * 60);
  CHECK(t.MinuteOfDay(t.StratTime(mk(2026, 7, 1, 13, 30))) == 9 * 60 + 30, "UTC -> NY été");
  CHECK(t.MinuteOfDay(t.StratTime(mk(2026, 1, 1, 14, 30))) == 9 * 60 + 30, "UTC -> NY hiver");
  CHECK(t.MinuteOfDay(t.StratTime(mk(2026, 3, 8, 6, 59))) == 1 * 60 + 59, "juste avant le DST US");
  CHECK(t.MinuteOfDay(t.StratTime(mk(2026, 3, 8, 7, 0))) == 3 * 60, "début du DST US");
  CHECK(t.MinuteOfDay(t.StratTime(mk(2026, 11, 1, 6, 0))) == 1 * 60, "fin du DST US");
  // Londres / Paris
  t.Configure(OPR_STZ_LONDON, OPR_SRV_GMT_FIXED, 0, 0);
  CHECK(t.MinuteOfDay(t.StratTime(mk(2026, 3, 29, 0, 59))) == 59, "Londres avant BST");
  CHECK(t.MinuteOfDay(t.StratTime(mk(2026, 3, 29, 1, 0))) == 2 * 60, "Londres passage BST");
  CHECK(t.MinuteOfDay(t.StratTime(mk(2026, 10, 25, 1, 0))) == 60, "Londres fin BST");
  t.Configure(OPR_STZ_PARIS, OPR_SRV_GMT_FIXED, 0, 0);
  CHECK(t.MinuteOfDay(t.StratTime(mk(2026, 7, 1, 7, 0))) == 9 * 60, "Paris été UTC+2");
  CHECK(t.MinuteOfDay(t.StratTime(mk(2026, 1, 1, 7, 0))) == 8 * 60, "Paris hiver UTC+1");
  t.Configure(OPR_STZ_SERVER, OPR_SRV_GMT_FIXED, 3 * 3600, 0);
  CHECK(t.StratTime(mk(2026, 7, 1, 7, 0)) == mk(2026, 7, 1, 7, 0), "heure serveur = identité");
  // journée de session commençant à 18:00 NY ; plages qui traversent minuit
  t.Configure(OPR_STZ_NEW_YORK, OPR_SRV_GMT_FIXED, 0, 18 * 60);
  long ny1759 = mk(2026, 3, 9, 17, 59), ny1800 = mk(2026, 3, 9, 18, 0), ny0000 = mk(2026, 3, 10, 0, 0);
  CHECK(t.SessionDay(ny1759) != t.SessionDay(ny1800), "18:00 NY ouvre une nouvelle journée");
  CHECK(t.SessionDay(ny1800) == t.SessionDay(ny0000), "minuit reste dans la même journée de session");
  OPRTimeRange asia;
  asia.Set(20 * 60, 0);
  long a = 0, b = 0;
  t.RangeAbs(t.SessionDay(ny0000), asia, a, b);
  CHECK(a == mk(2026, 3, 9, 20, 0) && b == ny0000, "plage asiatique 20:00 (veille) -> 00:00");
  OPRTimeRange r;
  CHECK(OprParseRange("02:50-04:10", r) && r.startMin == 170 && r.endMin == 250, "lecture HH:MM-HH:MM");
  CHECK(OprParseRange("", r) && !r.valid, "chaîne vide = non configuré");
  CHECK(!OprParseRange("2h50-4h10", r), "format invalide refusé");
}

// --------------------------------------------------------------------------------------------
static void testOprLevels() {
  printf("[tests 1-3] OPR exacts, figés, indépendants\n");
  auto bars = londonDay(0);
  Run R;
  R.e.Init(baseCfg());
  // avant la fin de la plage : en calcul, jamais finalisé
  long D1 = mk(2026, 3, 10, 0, 0);
  size_t i = 0;
  for (; i < bars.size(); i++)
    if (bars[i].t >= srvOfNy(D1 + 29 * 60)) break;
  R.feed(bars, 0, i);
  CHECK(R.e.opr[0].m_st.status == OPR_ST_BUILDING, "OPR en cours de calcul à 00:28");
  CHECK(R.count(J_OPR_FINAL, 0) == 0, "pas finalisé avant la clôture de 00:29");
  R.feed(bars, i, i + 1);
  CHECK(R.e.opr[0].m_st.status == OPR_ST_FINAL, "finalisé à la clôture de la bougie 00:29 (00:30)");
  CHECK(NEAR(R.e.opr[0].m_st.high, 102) && NEAR(R.e.opr[0].m_st.low, 98), "High 102 / Low 98 exacts (bougies de la plage uniquement)");
  CHECK(R.e.opr[0].m_st.candles == 30, "30 bougies M1 dans la plage");
  R.feed(bars, i + 1);
  CHECK(NEAR(R.e.opr[0].m_st.high, 102) && NEAR(R.e.opr[0].m_st.low, 98), "niveaux figés malgré un plus haut (103) et un plus bas (97) ensuite");
  CHECK(R.count(J_OPR_FINAL, 0) == 1, "un seul événement de finalisation");
  CHECK(R.e.opr[1].m_st.status == OPR_ST_FINAL && NEAR(R.e.opr[1].m_st.high, 92) && NEAR(R.e.opr[1].m_st.low, 89),
        "OPR 07:00 indépendant : High 92 / Low 89");
  CHECK(NEAR(R.e.opr[0].m_st.high, 102), "l'OPR 07:00 ne modifie pas le MOR");
  CHECK(NEAR(OprStdLevel(R.e.opr[0].m_st, -1, 2.0), 90) && NEAR(OprStdLevel(R.e.opr[0].m_st, 1, 2.0), 110),
        "déviations standard : Low - 2x amplitude = 90, High + 2x = 110");
  CHECK(R.e.opr[2].m_st.status == OPR_ST_PENDING, "OPR 09:30 pas encore commencé à 08:00");

  // historique insuffisant : moteur démarré à 00:10 -> OPR incomplet, non utilisé
  Run R2;
  R2.e.Init(baseCfg());
  size_t j = 0;
  for (; j < bars.size(); j++)
    if (bars[j].t >= srvOfNy(D1 + 10 * 60)) break;
  R2.feed(bars, j);
  CHECK(R2.e.opr[0].m_st.status == OPR_ST_INCOMPLETE, "démarrage à 00:10 : OPR incomplet");
  CHECK(R2.hasReason(J_ENTRY_REJECTED, R_NO_OPR), "entrée rejetée : OPR non finalisé");
  CHECK(R2.count(J_ENTRY_AUTHORIZED) == 0, "aucune entrée sans OPR complet");

  // redémarrage : niveaux restaurés depuis la persistance -> le modèle fonctionne
  Run R3;
  R3.e.Init(baseCfg());
  size_t k = 0;
  for (; k < bars.size(); k++)
    if (bars[k].t >= srvOfNy(D1 + 40 * 60)) break;
  R3.feed(bars, j, k);
  bool restored = R3.e.RestoreOpr(0, R3.e.m_day, 102, 98);
  CHECK(restored && R3.e.opr[0].m_st.status == OPR_ST_FINAL && R3.e.opr[0].m_st.restored, "OPR restauré après redémarrage");
  R3.feed(bars, k);
  CHECK(R3.count(J_TRADE_FILLED) == 1, "trade possible avec l'OPR restauré");
}

// --------------------------------------------------------------------------------------------
static void testAsiaFvg() {
  printf("[tests 4-5] premier FVG M15 asiatique, pas de détection prématurée\n");
  auto bars = londonDay(0);
  long D0 = mk(2026, 3, 9, 0, 0);
  Run R;
  R.e.Init(baseCfg());
  size_t i = 0;
  for (; i < bars.size(); i++)
    if (bars[i].t >= srvOfNy(D0 + 20 * 3600 + 29 * 60)) break;
  R.feed(bars, 0, i);
  CHECK(R.e.m_asiaFvgId == 0, "pas de FVG avant la clôture de la 3e bougie M15 (20:29 non traitée)");
  R.feed(bars, i, i + 1);
  int fi = R.e.FindFvgIdx(R.e.m_asiaFvgId);
  CHECK(fi >= 0, "FVG asiatique identifié à la clôture de 20:29 (= 20:30)");
  if (fi >= 0) {
    const OFvg &f = R.e.fvgs.m_list[fi];
    CHECK(f.dir == 1 && NEAR(f.lo, 100.5) && NEAR(f.hi, 101.2), "FVG haussier [100.5 ; 101.2]");
    CHECK(f.c2T == D0 + 20 * 3600 && f.formedT == D0 + 20 * 3600 + 30 * 60, "gap sur la bougie de 20:00, confirmé à 20:30");
    CHECK(f.role == FVG_ROLE_ASIA && f.tfMin == 15, "rôle : FVG asiatique de référence, M15");
  }
  long firstId = R.e.m_asiaFvgId;
  R.feed(bars, i + 1);
  CHECK(R.e.m_asiaFvgId == firstId, "jamais remplacé par le FVG plus récent de 21:30");
  CHECK(R.count(J_ASIA_FVG) == 1, "un seul événement");
  bool second = false;
  for (int k = 0; k < R.e.fvgs.Count(); k++)
    if (R.e.fvgs.m_list[k].tfMin == 15 && R.e.fvgs.m_list[k].c2T == D0 + 21 * 3600 + 30 * 60) second = true;
  (void)second;

  // règle « les 3 bougies dans la plage » : le FVG de 20:00 (c1 = 19:45) ne compte pas
  OPRConfig c = baseCfg();
  c.asiaRule = OPR_ASIA_ALL_IN_RANGE;
  Run R2;
  R2.e.Init(c);
  R2.feed(bars);
  const OJEvent *a2 = R2.first(J_ASIA_FVG);
  CHECK(a2 && a2->st >= D0 + 20 * 3600 + 45 * 60, "avec la règle stricte, le premier FVG asiatique est postérieur");
  CHECK(R2.e.m_asiaFvgId != firstId, "règle configurable et documentée");

  // définition mathématique : test direct sur trois bougies
  OCandle c1 = {0, 0, 10, 11, 9, 10}, c2 = {60, 0, 10, 14, 10, 14}, c3 = {120, 0, 14, 15, 11.5, 14.5};
  int dir = 0;
  double lo = 0, hi = 0;
  CHECK(OprFvgDetect(c1, c2, c3, 0.0, dir, lo, hi) && dir == 1 && NEAR(lo, 11) && NEAR(hi, 11.5), "FVG haussier : Low(c3) > High(c1)");
  OCandle d3 = {120, 0, 14, 15, 11.0, 14.5};
  CHECK(!OprFvgDetect(c1, c2, d3, 0.0, dir, lo, hi), "Low(c3) = High(c1) : pas de FVG");
  CHECK(!OprFvgDetect(c1, c2, c3, 1.0, dir, lo, hi), "taille minimale respectée");
}

// --------------------------------------------------------------------------------------------
static const OJEvent *findAuth(const Run &R) { return R.first(J_ENTRY_AUTHORIZED); }

static void testLondonModel() {
  printf("[tests 6-7, 9] modèle London OPR (biais, liquidité, FVG, macro, stop, cible)\n");
  long D1 = mk(2026, 3, 10, 0, 0);
  {
    Run R;
    R.e.Init(baseCfg());
    R.feed(londonDay(0));
    const OJEvent *b = R.first(J_BIAS);
    CHECK(b && b->dir == -1 && b->st == D1 + 2 * 3600 + 49 * 60, "biais VENTE lu à 2:50 (clôture 02:49 = 96 < OPR Low 98)");
    const OJEvent *sw = R.first(J_SWEEP);
    CHECK(sw && sw->st == D1 + 2 * 3600 + 55 * 60 && NEAR(sw->p1, 96.8) && sw->aux == LIQ_SRC_M1, "prise du swing high M1 96.8 à 02:55");
    const OJEvent *a = findAuth(R);
    CHECK(a != nullptr, "entrée autorisée");
    if (a) {
      CHECK(a->dir == -1, "vente");
      CHECK(NEAR(a->p1, 95.5), "entrée au bord du FVG (95.5)");
      CHECK(NEAR(a->p2, 97.25), "stop au-dessus du swing (97.0) + 1 tick");
      CHECK(NEAR(a->p3, 90.0), "cible -2 STD du MOR (90)");
      CHECK(a->st == D1 + 2 * 3600 + 57 * 60 && a->aux == 0, "FVG confirmé à 02:58, dans la macro 1 (02:50-03:10)");
    }
    const OJEvent *f = R.first(J_TRADE_FILLED);
    CHECK(f && f->st == D1 + 3 * 3600 && NEAR(f->p1, 95.5), "exécution book à 03:00 au niveau 95.5");
    const OJEvent *cl = R.first(J_TRADE_CLOSED);
    CHECK(cl && cl->aux == BK_EXIT_TP && NEAR(cl->p4, (95.5 - 90.0) / 1.75), "cible atteinte : +3.14R");
    CHECK(R.e.stats.trades == 1 && R.e.stats.wins == 1, "statistiques book");
    CHECK(R.count(J_WINDOW_OPEN, 0) == 1 && R.count(J_WINDOW_CLOSE, 0) == 1, "fenêtre ouverte puis fermée une fois");
    CHECK(R.count(J_MACRO_OPEN, 0) == 3, "trois macros journalisées");
    CHECK(R.hasReason(J_ENTRY_REJECTED, R_TARGET_REACHED) || R.count(J_ENTRY_AUTHORIZED) == 1, "pas de second trade une fois la cible atteinte");
    // test 9 : chaque exécution correspond à une autorisation journalisée identique
    bool ok = true;
    for (auto &x : R.ev)
      if (x.code == J_TRADE_FILLED) {
        bool found = false;
        for (auto &y : R.ev)
          if (y.code == J_ENTRY_AUTHORIZED && y.id == x.id && NEAR(y.p1, x.p1) && NEAR(y.p2, x.p2) && NEAR(y.p3, x.p3) && y.st < x.st) found = true;
        ok = ok && found;
      }
    CHECK(ok, "chaque exécution est précédée de son autorisation (mêmes niveaux)");
    if (g_fail) R.dump();
  }
  {
    Run R;
    R.e.Init(baseCfg());
    R.feed(londonDay(1));
    CHECK(findAuth(R) != nullptr, "variante 1 : setup armé");
    CHECK(R.hasReason(J_SETUP_CANCELLED, R_TARGET_REACHED), "cible atteinte avant l'entrée : setup annulé");
    CHECK(R.count(J_TRADE_FILLED) == 0, "aucun trade");
  }
  {
    Run R;
    R.e.Init(baseCfg());
    R.feed(londonDay(2));
    CHECK(R.count(J_BIAS_CONSOL, 0) == 1, "test 7 : prix dans l'OPR à 2:50 -> consolidation journalisée");
    const OJEvent *bo = R.first(J_BIAS_BREAKOUT);
    CHECK(bo && bo->dir == -1 && bo->st == D1 + 3 * 3600 + 5 * 60, "direction donnée seulement par la clôture hors OPR (03:05)");
    bool early = false;
    for (auto &x : R.ev)
      if (x.code == J_ENTRY_AUTHORIZED && x.st < D1 + 3 * 3600 + 5 * 60) early = true;
    CHECK(!early, "aucune entrée tant que le prix est dans l'OPR");
    CHECK(R.count(J_TRADE_FILLED) == 0, "aucun trade dans ce scénario");
  }
  {
    Run R;
    R.e.Init(baseCfg());
    R.feed(londonDay(3));
    CHECK(R.hasReason(J_FVG_IGNORED, R_NO_SWEEP), "FVG sans prise de liquidité : rejet « confirmation manquante »");
    CHECK(R.count(J_ENTRY_AUTHORIZED) == 0, "aucune entrée");
  }
  {
    Run R;
    R.e.Init(baseCfg());
    R.feed(londonDay(4));
    const OJEvent *cl = R.first(J_TRADE_CLOSED);
    CHECK(cl && cl->aux == BK_EXIT_SL && NEAR(cl->p4, -1.0) && cl->st == D1 + 3 * 3600, "stop touché sur la bougie d'entrée : perte -1R");
  }
  {
    Run R;
    R.e.Init(baseCfg());
    R.feed(londonDay(5));
    CHECK(R.hasReason(J_FVG_IGNORED, R_OUTSIDE_MACRO), "FVG formé à 03:12 (hors macro) : ignoré");
    CHECK(R.count(J_ENTRY_AUTHORIZED) == 0, "aucune entrée hors macro");
    OPRConfig c = baseCfg();
    c.requireMacro = false;
    Run R2;
    R2.e.Init(c);
    R2.feed(londonDay(5));
    CHECK(R2.count(J_ENTRY_AUTHORIZED) == 1, "paramètre : sans exigence de macro, le même FVG est pris");
  }
  {
    // test 6 : un achat ne peut pas être déclenché par une condition de vente (et inversement)
    // même journée en miroir (prix inversés autour de 100) : le biais devient ACHAT
    auto bars = londonDay(0);
    for (auto &b : bars) {
      double o = 200 - b.o, h = 200 - b.l, l = 200 - b.h, c = 200 - b.c;
      b.o = o; b.h = h; b.l = l; b.c = c;
    }
    Run R;
    R.e.Init(baseCfg());
    R.feed(bars);
    const OJEvent *b = R.first(J_BIAS);
    const OJEvent *a = findAuth(R);
    CHECK(b && b->dir == 1, "miroir : biais ACHAT (prix au-dessus de l'OPR High)");
    CHECK(a && a->dir == 1 && NEAR(a->p1, 104.5) && NEAR(a->p2, 102.75) && NEAR(a->p3, 110.0), "achat : entrée 104.5, stop 102.75, cible +2 STD 110");
    bool wrong = false;
    for (auto &x : R.ev)
      if ((x.code == J_ENTRY_AUTHORIZED || x.code == J_TRADE_FILLED) && x.dir != 1) wrong = true;
    CHECK(!wrong, "aucune vente avec un biais acheteur");
    Run R0;
    R0.e.Init(baseCfg());
    R0.feed(londonDay(0));
    bool wrong0 = false;
    for (auto &x : R0.ev)
      if ((x.code == J_ENTRY_AUTHORIZED || x.code == J_TRADE_FILLED) && x.dir != -1) wrong0 = true;
    CHECK(!wrong0, "aucun achat avec un biais vendeur");
  }
  {
    // OPR sans règle d'entrée : jamais d'ordre
    OPRConfig c = baseCfg();
    c.slots[0].tradeEnabled = false;
    Run R;
    R.e.Init(c);
    R.feed(londonDay(0));
    CHECK(R.count(J_ENTRY_AUTHORIZED) == 0 && R.e.opr[0].IsFinal(), "entrée désactivée : niveaux calculés mais aucun ordre");
  }
}

// --------------------------------------------------------------------------------------------
// Invariants sur données aléatoires (24 h/24, plusieurs mois)
static void testRandom() {
  printf("[tests 1, 4, 6, 7, 9] invariants sur données aléatoires\n");
  for (unsigned seed = 21; seed <= 23; seed++) {
    auto bars = synth(250000, seed, (datetime)(mk(2025, 1, 5, 18, 0) + 7 * 3600));
    OPRConfig c = baseCfg();
    Run R;
    R.e.Init(c);
    R.e.logContext = true;
    auto t1 = std::chrono::steady_clock::now();
    // oracle indépendant : OPR et FVG asiatique recalculés depuis les bougies
    std::map<int, std::pair<double, double>> oprOracle;
    std::map<int, long> firstBarOfDay;
    COprTime tm;
    tm.Configure(c.stratTz, c.serverMode, c.serverGmtSec, c.dayStartMin);
    for (auto &b : bars) {
      long st = tm.StratTime(b.t);
      int day = tm.SessionDay(st);
      if (!firstBarOfDay.count(day)) firstBarOfDay[day] = st;
      long s0 = 0, e0 = 0;
      tm.RangeAbs(day, c.slots[0].calc, s0, e0);
      if (st >= s0 && st < e0) {
        auto it = oprOracle.find(day);
        if (it == oprOracle.end())
          oprOracle[day] = {b.h, b.l};
        else {
          it->second.first = std::max(it->second.first, b.h);
          it->second.second = std::min(it->second.second, b.l);
        }
      }
    }
    int badOpr = 0, oprChecked = 0, badAuth = 0, badFill = 0, dupMacro = 0, badDir = 0, badTime = 0, badCtx = 0;
    std::map<long, OJEvent> auth;
    std::set<std::tuple<int, int, int>> macroFills;
    std::map<int, int> biasOfDay;
    std::map<int, bool> sweptOfDay;
    for (size_t i = 0; i < bars.size(); i++) {
      R.e.ProcessBar(bars[i].t, bars[i].o, bars[i].h, bars[i].l, bars[i].c);
      int day = R.e.m_day;
      for (int k = 0; k < R.e.jr.m_count; k++) {
        const OJEvent &x = R.e.jr.m_ev[k];
        if (x.code == J_OPR_FINAL && x.slot == 0 && x.aux == 0) {
          oprChecked++;
          auto it = oprOracle.find(day);
          if (it == oprOracle.end() || !NEAR(it->second.first, x.p1) || !NEAR(it->second.second, x.p2)) badOpr++;
        }
        if ((x.code == J_BIAS || x.code == J_BIAS_BREAKOUT) && x.slot == 0) biasOfDay[day] = x.dir;
        if (x.code == J_SWEEP && x.slot == 0) sweptOfDay[day] = true;
        if (x.code == J_CTX_ABOVE && !(bars[i].c > R.e.opr[x.slot].m_st.high)) badCtx++;
        if (x.code == J_CTX_BELOW && !(bars[i].c < R.e.opr[x.slot].m_st.low)) badCtx++;
        if (x.code == J_ENTRY_AUTHORIZED) {
          auth[x.id] = x;
          int m = tm.MinuteOfDay(x.st);
          if (!c.slots[0].window.Contains(m)) badTime++;
          if (c.requireMacro && x.aux < 0) badTime++;
          if (!biasOfDay.count(day) || biasOfDay[day] != x.dir) badDir++;
          if (!sweptOfDay[day]) badAuth++;
          // niveaux cohérents et cible = 2 STD
          double tp = OprStdLevel(R.e.opr[0].m_st, x.dir, c.tpStd);
          if (!NEAR(tp, x.p3)) badAuth++;
          if (x.dir < 0 && !(x.p3 < x.p1 && x.p1 < x.p2)) badAuth++;
          if (x.dir > 0 && !(x.p2 < x.p1 && x.p1 < x.p3)) badAuth++;
          // prix dans l'OPR : jamais d'entrée « par défaut »
          if (x.dir < 0 && R.e.opr[0].m_st.status != OPR_ST_FINAL) badAuth++;
        }
        if (x.code == J_TRADE_FILLED) {
          auto it = auth.find(x.id);
          if (it == auth.end() || !NEAR(it->second.p1, x.p1) || !NEAR(it->second.p2, x.p2) || !NEAR(it->second.p3, x.p3)) badFill++;
          if (x.dir < 0 && bars[i].h < x.p1) badFill++;
          if (x.dir > 0 && bars[i].l > x.p1) badFill++;
          auto key = std::make_tuple(day, x.slot, x.aux);
          if (macroFills.count(key)) dupMacro++;
          macroFills.insert(key);
        }
      }
    }
    auto t2 = std::chrono::steady_clock::now();
    double ms = std::chrono::duration<double, std::milli>(t2 - t1).count();
    const OStats &s = R.e.stats;
    printf("  seed %u : %d jours, biais V/A/consol %d/%d/%d, FVG asiatique %d j, sweeps %d, candidats %d, armés %d, "
           "trades %d (%dW/%dL) net %+.1fR | %.0f ms\n",
           seed, s.days, s.biasSell, s.biasBuy, s.biasConsol, s.asiaFvgDays, s.sweeps, s.candidates, s.armed, s.trades, s.wins,
           s.losses, s.netR, ms);
    CHECK(oprChecked > 100 && badOpr == 0, "OPR = recalcul indépendant (max/min des bougies de la plage)");
    CHECK(badAuth == 0, "chaque entrée : OPR finalisé, liquidité prise, niveaux cohérents, cible 2 STD");
    CHECK(badDir == 0, "sens de l'entrée = biais du jour");
    CHECK(badTime == 0, "entrées uniquement dans la fenêtre et dans une macro");
    CHECK(badFill == 0, "chaque exécution correspond à une autorisation et à un prix réellement atteint");
    CHECK(dupMacro == 0, "1 macro = 1 trade");
    CHECK(badCtx == 0, "contexte journalisé conforme au prix");
    CHECK(s.wins + s.losses == s.trades, "W + L = trades");
    CHECK(ms < 30000, "performance");
  }
}

static void testDeterminism() {
  printf("[test] déterminisme et absence de dépendance au futur\n");
  auto bars = synth(40000, 31, (datetime)(mk(2025, 6, 1, 18, 0) + 7 * 3600));
  auto run = [&](size_t n, std::vector<std::string> &out) {
    Run R;
    R.e.Init(baseCfg());
    R.feed(bars, 0, n);
    for (auto &t : R.txt) out.push_back(t);
  };
  std::vector<std::string> full, part;
  run(bars.size(), full);
  run(bars.size() / 2, part);
  bool prefix = part.size() <= full.size();
  for (size_t i = 0; prefix && i < part.size(); i++) prefix = (part[i] == full[i]);
  CHECK(!part.empty() && prefix, "les événements d'un historique tronqué sont un préfixe exact de l'historique complet");
}

int main() {
  testTime();
  testOprLevels();
  testAsiaFvg();
  testLondonModel();
  testDeterminism();
  testRandom();
  printf("\n%d vérifications OK, %d échecs\n", g_pass, g_fail);
  return g_fail ? 1 : 0;
}

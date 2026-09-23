// Tests du moteur LRL Map (code MQL5 converti par mq2cpp.py et compilé avec g++).
#include "mql5_core.h"
bool g_shim_quiet = true;
#include "LRL_Engine.mqh"

#include <chrono>
#include <functional>
#include <map>
#include <random>

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

static datetime mkTime(int y, int mo, int d, int h, int mi) {
  MqlDateTime s;
  memset(&s, 0, sizeof(s));
  s.year = y; s.mon = mo; s.day = d; s.hour = h; s.min = mi;
  return StructToTime(s);
}

static LRLConfig scenarioCfg() {
  LRLConfig c;
  c.Defaults();
  c.baseSeconds = 60;
  c.htfMinutes[0] = 2; c.htfMinutes[1] = 0; c.htfMinutes[2] = 0;
  c.pivotLeft = 2; c.pivotRight = 2;
  c.maxSwings = 20; c.minTouches = 3; c.touchTolAtr = 0.2; c.minSpacing = 3;
  c.atrLen = 5; c.expireBars = 1000;
  c.minStop = 5.0; c.maxStopAtr = 0.0; c.rr = 1.0; c.lrlBeyondTarget = true;
  c.tradeOnlyInWindow = false; c.flatEnabled = false;
  c.tickSize = 0.25;
  c.tzMode = LRL_TZ_SERVER_NY; c.serverMinusNySec = 7 * 3600;
  return c;
}

// Phase LRL : 4 cycles de 10 bougies, swing lows exactement à 100 (bougies 5, 15, 25, 35),
// swing highs non alignés.
static std::vector<Bar> lrlPhase(datetime t0) {
  std::vector<Bar> v;
  double amp[4] = {2.0, 2.6, 3.8, 2.0};
  for (int cyc = 0; cyc < 4; cyc++)
    for (int j = 0; j < 10; j++) {
      double mid = 100.5 + std::abs(j - 5) * amp[cyc];
      Bar b;
      b.t = t0 + (cyc * 10 + j) * 60;
      b.l = mid - 0.5;
      b.h = mid + 0.5;
      b.o = mid - 0.2;
      b.c = mid + 0.2;
      v.push_back(b);
    }
  return v;
}

// Phase FVG : jambe haussière (FVG 2m [110, 115.5]), inversion, retest du CE, puis cible.
static std::vector<Bar> fvgPhase(datetime t0, int variant) {
  std::vector<std::vector<double>> ohlc = {
      // A
      {108, 109, 107.5, 108.8}, {108.8, 110, 108.5, 109.8},
      // B (déplacement)
      {109.8, 113, 109.7, 112.8}, {112.8, 116, 112.5, 115.8},
      // C -> FVG haussier [110, 115.5]
      {115.8, 118, 115.5, 117.5}, {117.5, 119, 116.8, 118.5},
      // D (extrême de jambe 121.5)
      {118.5, 121, 118, 120.5}, {120.5, 121.5, 115.9, 119.8},
      // E : clôture 2m sous 110 -> inversion
      {119.8, 120, 113, 113.5}, {113.5, 114, 109, 109.5},
      // F : retest du CE 112.75 sur la 2e bougie
      {109.5, 111, 108.5, 110.8}, {110.8, 113, 110.5, 112},
      // G : cible 103.75
      {112, 112.2, 106, 106.5}, {106.5, 107, 103.5, 104},
  };
  if (variant == 1)  // bougie qui touche stop ET cible -> perte
    ohlc[13] = {106.5, 122, 103, 110};
  if (variant == 2)  // la bougie d'entrée touche le stop -> perte sur la bougie d'entrée
    ohlc[11] = {110.8, 122, 110.5, 112};
  if (variant == 3) {  // clôture M1 sous le gap mais clôture 2m au-dessus -> pas d'inversion
    ohlc[8] = {119.8, 120, 108, 109};
    ohlc[9] = {109, 112, 108.8, 111};
  }
  std::vector<Bar> v;
  for (size_t i = 0; i < ohlc.size(); i++) {
    Bar b;
    b.t = t0 + (datetime)i * 60;
    b.o = ohlc[i][0]; b.h = ohlc[i][1]; b.l = ohlc[i][2]; b.c = ohlc[i][3];
    v.push_back(b);
  }
  return v;
}

struct Recorder {
  std::vector<LRLEvent> ev;
  void grab(CLRLEngine &e) {
    for (int i = 0; i < e.m_evCount; i++) ev.push_back(e.m_events[i]);
  }
  int count(int type) const {
    int n = 0;
    for (auto &x : ev) n += (x.type == type);
    return n;
  }
};

static void feed(CLRLEngine &e, const std::vector<Bar> &bars, Recorder &rec) {
  for (auto &b : bars) {
    e.ProcessBar(b.t, b.o, b.h, b.l, b.c);
    rec.grab(e);
  }
}

// ------------------------------------------------------------------
static void testNyTime() {
  printf("[test] heure de New York / DST\n");
  CLRLEngine e;
  LRLConfig c = scenarioCfg();
  c.tzMode = LRL_TZ_SERVER_GMT;
  c.serverGmtSec = 0;
  e.Init(c);
  CHECK(e.NyMinute(mkTime(2026, 7, 1, 13, 30)) == 9 * 60 + 30, "été: 13:30 UTC = 09:30 NY");
  CHECK(e.NyMinute(mkTime(2026, 1, 15, 14, 30)) == 9 * 60 + 30, "hiver: 14:30 UTC = 09:30 NY");
  // 2026 : DST du 8 mars 07:00 UTC au 1er novembre 06:00 UTC
  CHECK(e.NyMinute(mkTime(2026, 3, 8, 6, 59)) == 1 * 60 + 59, "juste avant DST");
  CHECK(e.NyMinute(mkTime(2026, 3, 8, 7, 0)) == 3 * 60, "début DST");
  CHECK(e.NyMinute(mkTime(2026, 11, 1, 5, 59)) == 1 * 60 + 59, "juste avant fin DST");
  CHECK(e.NyMinute(mkTime(2026, 11, 1, 6, 0)) == 1 * 60, "fin DST");
  // serveur GMT+2 fixe
  c.serverGmtSec = 2 * 3600;
  e.Init(c);
  CHECK(e.NyMinute(mkTime(2026, 7, 1, 15, 30)) == 9 * 60 + 30, "serveur GMT+2");
  // serveur = NY + 7h
  c.tzMode = LRL_TZ_SERVER_NY;
  c.serverMinusNySec = 7 * 3600;
  e.Init(c);
  CHECK(e.NyMinute(mkTime(2026, 7, 1, 16, 30)) == 9 * 60 + 30, "serveur NY+7");
  CHECK(e.NyMinute(mkTime(2026, 7, 1, 3, 0)) == 20 * 60, "NY+7 passage de minuit");
  // fenêtres
  c.winStartMin = 9 * 60 + 30; c.winEndMin = 10 * 60;
  c.flatEnabled = true; c.flatStartMin = 15 * 60 + 55; c.flatEndMin = 16 * 60;
  e.Init(c);
  CHECK(e.InWindowMin(9 * 60 + 30) && e.InWindowMin(9 * 60 + 59) && !e.InWindowMin(10 * 60), "fenêtre 09:30-10:00");
  CHECK(e.InFlatMin(15 * 60 + 55) && !e.InFlatMin(16 * 60) && !e.InFlatMin(15 * 60 + 54), "flat 15:55-16:00");
  c.winStartMin = 20 * 60; c.winEndMin = 2 * 60;
  e.Init(c);
  CHECK(e.InWindowMin(23 * 60) && e.InWindowMin(60) && !e.InWindowMin(3 * 60), "fenêtre à cheval sur minuit");
}

// ------------------------------------------------------------------
static void testHtfAggregation() {
  printf("[test] agrégation HTF depuis les bougies de base\n");
  CLRLEngine e;
  LRLConfig c = scenarioCfg();
  c.htfMinutes[0] = 5; c.htfMinutes[1] = 2; c.htfMinutes[2] = 7;  // 7 min ne divise pas 24h -> rejeté
  bool ok = e.Init(c);
  CHECK(ok, "init");
  CHECK(e.m_htfCount == 2, "HTF 7 min rejeté, 2 niveaux restants");
  CHECK(e.m_htf[0].minutes == 2 && e.m_htf[1].minutes == 5, "niveaux triés 2 puis 5");

  datetime t0 = mkTime(2026, 3, 2, 10, 1);  // commence au milieu d'une bougie 2m
  Recorder r;
  std::vector<Bar> bars;
  for (int i = 0; i < 12; i++) {
    Bar b;
    b.t = t0 + i * 60;
    b.o = 100 + i; b.h = 100.5 + i; b.l = 99.5 + i; b.c = 100.2 + i;
    bars.push_back(b);
  }
  feed(e, bars, r);  // 10:01 .. 10:12
  // 2m : première bougie partielle (10:00) ignorée ; closes à 10:03(10:02), 10:05(10:04) ... 10:11(10:10)
  CHECK(e.m_htf[0].count == 5, "5 bougies 2m clôturées");
  CHECK(e.m_htf[0].cT[0] == mkTime(2026, 3, 2, 10, 10), "dernière 2m = 10:10");
  CHECK(NEAR(e.m_htf[0].cH[0], 100.5 + 10) && NEAR(e.m_htf[0].cL[0], 99.5 + 9) && NEAR(e.m_htf[0].cO[0], 109) && NEAR(e.m_htf[0].cC[0], 110.2),
        "OHLC 2m correct");
  // 5m : bougie 10:05 clôturée sur la bougie 10:09
  CHECK(e.m_htf[1].count == 1 && e.m_htf[1].cT[0] == mkTime(2026, 3, 2, 10, 5), "une bougie 5m (10:05)");
  CHECK(NEAR(e.m_htf[1].cH[0], 100.5 + 8) && NEAR(e.m_htf[1].cL[0], 99.5 + 4), "OHLC 5m correct");

  // bougie manquante : 10:13 absente, 10:14 arrive -> la 2m 10:12 se clôture en retard
  Bar b;
  b.t = t0 + 13 * 60;  // 10:14
  b.o = b.h = b.l = b.c = 120;
  e.ProcessBar(b.t, b.o, b.h, b.l, b.c);
  CHECK(e.m_htf[0].count == 6 && e.m_htf[0].cT[0] == mkTime(2026, 3, 2, 10, 12), "clôture tardive de la 2m 10:12");
  CHECK(NEAR(e.m_htf[0].cC[0], 111.2), "clôture tardive : prix de la dernière bougie de la période");
}

// ------------------------------------------------------------------
static void testLrlAndTrade(int variant, const char *name, std::function<void(CLRLEngine &, Recorder &)> check,
                            std::function<void(LRLConfig &)> tweak = nullptr) {
  printf("[test] %s\n", name);
  CLRLEngine e;
  LRLConfig c = scenarioCfg();
  if (tweak) tweak(c);
  e.Init(c);
  Recorder r;
  datetime t0 = mkTime(2026, 3, 2, 14, 0);
  feed(e, lrlPhase(t0), r);
  feed(e, fvgPhase(t0 + 40 * 60, variant), r);
  check(e, r);
}

static void dumpEvents(const Recorder &r) {
  for (auto &x : r.ev)
    printf("    ev type=%d side=%d id=%ld tf=%d reason=%d n=%d t1=%s t2=%s p=%.2f %.2f %.2f %.2f %.2f\n", x.type, x.side, x.id,
           x.tfMin, x.reason, x.n, TimeToString(x.t1).c_str(), TimeToString(x.t2).c_str(), x.p1, x.p2, x.p3, x.p4, x.p5);
}

static const LRLEvent *findTrade(const Recorder &r, int type, double entry) {
  for (auto &x : r.ev)
    if (x.type == type && NEAR(x.p1, entry)) return &x;
  return nullptr;
}

static void testScenarios() {
  testLrlAndTrade(0, "LRL + iFVG 2m + retest CE -> gain 1R", [](CLRLEngine &e, Recorder &r) {
    CHECK(e.m_lrl[LRL_SIDE_LOW].active, "LRL basse active");
    CHECK(e.m_lrl[LRL_SIDE_LOW].touches == 4, "4 touches");
    CHECK(NEAR(e.m_lrl[LRL_SIDE_LOW].slope, 0.0) && NEAR(e.m_lrl[LRL_SIDE_LOW].PriceAt(e.m_bar), 100.0), "ligne plate à 100");
    CHECK(!e.m_lrl[LRL_SIDE_HIGH].active, "pas de LRL haute");
    CHECK(e.m_bias == -1, "biais short");
    CHECK(r.count(LRL_EV_LRL_NEW) >= 2, "LRL confirmée puis prolongée");
    const LRLEvent *op = findTrade(r, LRL_EV_TRADE_OPEN, 112.75);
    const LRLEvent *cl = findTrade(r, LRL_EV_TRADE_CLOSE, 112.75);
    CHECK(op != nullptr, "trade short ouvert au CE 112.75");
    if (op) {
      CHECK(op->side == -1, "direction short");
      CHECK(NEAR(op->p2, 121.75), "stop = extrême de jambe 121.5 + 1 tick");
      CHECK(NEAR(op->p3, 103.75), "cible 1R = 103.75");
      CHECK(op->t1 == mkTime(2026, 3, 2, 14, 51), "entrée sur la 2e bougie du retest (14:51)");
    }
    CHECK(cl != nullptr && cl->reason == LRL_EXIT_TARGET && NEAR(cl->p5, 1.0), "sortie à la cible, +1R");
    if (!op || !cl) dumpEvents(r);
  });

  testLrlAndTrade(1, "stop et cible sur la même bougie -> perte", [](CLRLEngine &e, Recorder &r) {
    const LRLEvent *cl = findTrade(r, LRL_EV_TRADE_CLOSE, 112.75);
    CHECK(cl != nullptr && cl->reason == LRL_EXIT_STOP && NEAR(cl->p5, -1.0), "règle conservatrice : perte");
  });

  testLrlAndTrade(2, "stop touché sur la bougie d'entrée -> perte", [](CLRLEngine &e, Recorder &r) {
    const LRLEvent *op = findTrade(r, LRL_EV_TRADE_OPEN, 112.75);
    const LRLEvent *cl = findTrade(r, LRL_EV_TRADE_CLOSE, 112.75);
    CHECK(op && cl && cl->t2 == op->t1 && cl->reason == LRL_EXIT_STOP, "perte sur la bougie d'entrée");
  });

  testLrlAndTrade(3, "inversion jugée sur la clôture HTF, pas sur une clôture M1", [](CLRLEngine &e, Recorder &r) {
    // la bougie M1 de 14:48 clôture sous 110 mais la 2m (14:48) clôture à 111 : pas d'inversion ;
    // la première clôture 2m sous 110 est celle de 14:52 (clôture 104, sur la bougie M1 de 14:53)
    datetime invAt = 0;
    for (auto &x : r.ev)
      if (x.type == LRL_EV_ZONE_INV && NEAR(x.p2, 110.0) && NEAR(x.p1, 115.5)) invAt = x.t2;
    CHECK(invAt == mkTime(2026, 3, 2, 14, 53), "inversion sur la clôture 2m de 14:52, pas avant");
    CHECK(findTrade(r, LRL_EV_TRADE_OPEN, 112.75) == nullptr, "aucun trade");
  });

  testLrlAndTrade(
      0, "filtre stop minimum (15 pts) -> setup ignoré et compté",
      [](CLRLEngine &e, Recorder &r) {
        CHECK(findTrade(r, LRL_EV_TRADE_OPEN, 112.75) == nullptr, "pas de trade");
        bool sk = false;
        for (auto &x : r.ev)
          if (x.type == LRL_EV_SETUP_SKIP && NEAR(x.p1, 112.75) && x.reason == LRL_BLOCK_MINSTOP) sk = true;
        CHECK(sk, "rejet min stop");
        CHECK(e.m_stats.skipMinStop >= 1, "compteur min stop");
      },
      [](LRLConfig &c) { c.minStop = 15.0; });

  testLrlAndTrade(
      0, "filtre LRL au-delà de la cible (2R -> cible 94.75 sous la LRL 100)",
      [](CLRLEngine &e, Recorder &r) {
        CHECK(findTrade(r, LRL_EV_TRADE_OPEN, 112.75) == nullptr, "pas de trade");
        bool sk = false;
        for (auto &x : r.ev)
          if (x.type == LRL_EV_SETUP_SKIP && NEAR(x.p1, 112.75) && x.reason == LRL_BLOCK_LRL) sk = true;
        CHECK(sk, "rejet LRL");
      },
      [](LRLConfig &c) { c.rr = 2.0; });

  testLrlAndTrade(
      0, "entrée au bord de la zone + stop au-delà de la zone",
      [](CLRLEngine &e, Recorder &r) {
        // bord = 110 ; retest dès F1 (haut 111) ; stop = 115.5 + 0.25 ; risque 5.75 ; cible 104.25
        const LRLEvent *op = findTrade(r, LRL_EV_TRADE_OPEN, 110.0);
        CHECK(op && NEAR(op->p2, 115.75) && NEAR(op->p3, 104.25), "niveaux bord/zone");
        CHECK(op && op->t1 == mkTime(2026, 3, 2, 14, 50), "retest sur F1");
        const LRLEvent *cl = findTrade(r, LRL_EV_TRADE_CLOSE, 110.0);
        CHECK(cl && cl->reason == LRL_EXIT_TARGET, "gain");
      },
      [](LRLConfig &c) {
        c.entryMode = LRL_ENTRY_EDGE;
        c.stopMode = LRL_STOP_ZONE;
      });

  testLrlAndTrade(
      0, "hors fenêtre avec 'trader seulement dans la fenêtre'",
      [](CLRLEngine &e, Recorder &r) {
        CHECK(findTrade(r, LRL_EV_TRADE_OPEN, 112.75) == nullptr, "pas de trade hors fenêtre");
        CHECK(e.m_stats.skipWindow >= 1, "compteur fenêtre");
      },
      [](LRLConfig &c) {
        c.tradeOnlyInWindow = true;
        c.winStartMin = 9 * 60 + 30;  // 14:51 serveur = 07:51 NY -> hors fenêtre
        c.winEndMin = 10 * 60;
      });

  testLrlAndTrade(
      0, "fenêtre désactivée : trade compté 'hors fenêtre'",
      [](CLRLEngine &e, Recorder &r) {
        const LRLEvent *op = findTrade(r, LRL_EV_TRADE_OPEN, 112.75);
        CHECK(op && op->n == 0, "trade marqué hors fenêtre");
        CHECK(e.m_stats.outTrades >= 1, "statistiques hors fenêtre");
      },
      [](LRLConfig &c) {
        c.tradeOnlyInWindow = false;
        c.winStartMin = 9 * 60 + 30;
        c.winEndMin = 10 * 60;
      });

}

// balayage : scénario dédié (cible sous 100)
static void testSweep() {
  printf("[test] balayage de la LRL et flat window\n");
  CLRLEngine e;
  LRLConfig c = scenarioCfg();
  c.flatEnabled = true;
  c.flatStartMin = 7 * 60 + 53;  // 14:53 serveur = 07:53 NY
  c.flatEndMin = 8 * 60;
  e.Init(c);
  Recorder r;
  datetime t0 = mkTime(2026, 3, 2, 14, 0);
  feed(e, lrlPhase(t0), r);
  auto f = fvgPhase(t0 + 40 * 60, 0);
  f.resize(12);  // jusqu'au retest (14:51)
  Bar b1 = {t0 + 52 * 60, 112, 112.5, 108, 108.5};  // 14:52 : ni stop ni cible
  Bar b2 = {t0 + 53 * 60, 108.5, 109, 99.0, 99.5};  // 14:53 : flat -> sortie à l'ouverture 108.5
  f.push_back(b1);
  f.push_back(b2);
  feed(e, f, r);
  const LRLEvent *cl = findTrade(r, LRL_EV_TRADE_CLOSE, 112.75);
  CHECK(cl && cl->reason == LRL_EXIT_FLAT, "sortie flat window");
  CHECK(cl && NEAR(cl->p4, 108.5) && NEAR(cl->p5, (112.75 - 108.5) / 9.0), "R fractionnaire à l'ouverture");
  CHECK(!e.m_lrl[LRL_SIDE_LOW].active, "LRL balayée par la mèche à 99");
  CHECK(e.m_bias == 0, "plus de biais");
}

// ------------------------------------------------------------------
static void testRandomInvariants() {
  printf("[test] invariants sur données aléatoires (3 x 300 000 bougies)\n");
  for (unsigned seed = 1; seed <= 3; seed++) {
    CLRLEngine e;
    LRLConfig c;
    c.Defaults();
    c.tickSize = 0.25;
    c.tradeOnlyInWindow = (seed != 2);
    e.Init(c);
    auto bars = synth(300000, seed, mkTime(2025, 1, 6, 0, 0));
    int opened = 0, closed = 0, bad = 0, badLrl = 0, badWatch = 0, badTime = 0;
    std::map<long, int> used;
    auto t1 = std::chrono::steady_clock::now();
    long watchedPrev = 0;
    LRLArmed armedPrev;
    armedPrev.Reset();
    for (size_t i = 0; i < bars.size(); i++) {
      const Bar &b = bars[i];
      e.ProcessBar(b.t, b.o, b.h, b.l, b.c);
      for (int k = 0; k < e.m_evCount; k++) {
        const LRLEvent &x = e.m_events[k];
        if (x.type == LRL_EV_TRADE_OPEN) {
          opened++;
          if (++used[x.id] > 1) bad++;  // une zone ne sert qu'une fois
          // le trade correspond au setup armé à la bougie précédente
          if (!(armedPrev.valid && armedPrev.zoneId == x.id && armedPrev.block == LRL_BLOCK_NONE)) bad++;
          // niveaux cohérents
          if (x.side < 0 && !(x.p2 > x.p1 && x.p3 < x.p1)) bad++;
          if (x.side > 0 && !(x.p2 < x.p1 && x.p3 > x.p1)) bad++;
          if (x.p4 < c.minStop - 1e-9) bad++;
          // LRL au-delà de la cible
          if (x.side < 0 && !(armedPrev.lrlPrice < x.p3)) badLrl++;
          if (x.side > 0 && !(armedPrev.lrlPrice > x.p3)) badLrl++;
          // le prix a bien atteint l'entrée sur cette bougie
          if (x.side < 0 && b.h < x.p1) badTime++;
          if (x.side > 0 && b.l > x.p1) badTime++;
          if (c.tradeOnlyInWindow && !e.InWindowMin(e.NyMinute(b.t))) badTime++;
        }
        if (x.type == LRL_EV_TRADE_CLOSE) {
          closed++;
          if (x.reason == LRL_EXIT_TARGET && !NEAR(x.p5, c.rr)) bad++;
          if (x.reason == LRL_EXIT_STOP && !NEAR(x.p5, -1.0)) bad++;
        }
      }
      // zone surveillée = plus haut TF parmi les iFVG vivants dans le sens du biais
      if (e.m_watchIdx >= 0) {
        int best = e.m_zones[e.m_watchIdx].tfMin;
        for (int z = 0; z < ArraySize(e.m_zones); z++)
          if (e.m_zones[z].inverted && !e.m_zones[z].dead && !e.m_zones[z].used && e.m_zones[z].dir == e.m_bias &&
              e.m_zones[z].tfMin > best)
            badWatch++;
        if (e.m_zones[e.m_watchIdx].dir != e.m_bias) badWatch++;
      }
      // LRL actives : jamais traversées depuis leur création
      for (int s = 0; s < 2; s++)
        if (e.m_lrl[s].active && e.m_lrl[s].createdBar < e.m_bar) {
          double lp = e.m_lrl[s].PriceAt(e.m_bar);
          if (s == LRL_SIDE_LOW && b.l < lp) badLrl++;
          if (s == LRL_SIDE_HIGH && b.h > lp) badLrl++;
        }
      armedPrev = e.m_armed;
      watchedPrev = e.m_watchId;
    }
    (void)watchedPrev;
    auto t2 = std::chrono::steady_clock::now();
    double ms = std::chrono::duration<double, std::milli>(t2 - t1).count();
    const LRLStats &s = e.m_stats;
    printf("  seed %u : %d trades (%dW/%dL) WR %.1f%% net %.2fR | in %d / out %d | skip minStop %d maxStop %d lrl %d window %d flat %d | armed %d | %.0f ms (%.2f us/bougie)\n",
           seed, s.trades, s.wins, s.losses, s.trades ? 100.0 * s.wins / s.trades : 0.0, s.netR, s.inTrades, s.outTrades,
           s.skipMinStop, s.skipMaxStop, s.skipLrl, s.skipWindow, s.skipFlat, s.armed, ms, 1000.0 * ms / bars.size());
    CHECK(opened > 0, "des trades sont produits");
    CHECK(closed + e.OpenTradeCount() == opened, "chaque trade ouvert est clos ou encore ouvert");
    CHECK(s.wins + s.losses == s.trades, "W + L = trades");
    CHECK(s.inTrades + s.outTrades == s.trades, "in + out = trades");
    CHECK(bad == 0, "cohérence des trades");
    CHECK(badLrl == 0, "LRL propre / au-delà de la cible");
    CHECK(badWatch == 0, "zone surveillée = plus haut timeframe");
    CHECK(badTime == 0, "entrée sur une bougie qui atteint le niveau, dans la fenêtre");
    if (c.tradeOnlyInWindow) CHECK(s.outTrades == 0, "aucun trade hors fenêtre quand le filtre est actif");
    CHECK(ms < 20000, "performance");
  }
}

// Déterminisme : deux passes identiques donnent exactement les mêmes événements.
static void testDeterminism() {
  printf("[test] déterminisme\n");
  auto bars = synth(60000, 7, mkTime(2025, 6, 2, 0, 0));
  auto run = [&](std::vector<std::string> &out) {
    CLRLEngine e;
    LRLConfig c;
    c.Defaults();
    c.tradeOnlyInWindow = false;
    e.Init(c);
    for (auto &b : bars) {
      e.ProcessBar(b.t, b.o, b.h, b.l, b.c);
      for (int k = 0; k < e.m_evCount; k++) {
        const LRLEvent &x = e.m_events[k];
        char buf[256];
        snprintf(buf, sizeof(buf), "%d %d %ld %ld %.4f %.4f %.4f", x.type, x.side, x.id, (long)x.t1, x.p1, x.p2, x.p3);
        out.push_back(buf);
      }
    }
  };
  std::vector<std::string> a, b;
  run(a);
  run(b);
  CHECK(a == b && !a.empty(), "mêmes événements");
}

int main() {
  testNyTime();
  testHtfAggregation();
  testScenarios();
  testSweep();
  testDeterminism();
  testRandomInvariants();
  printf("\n%d vérifications OK, %d échecs\n", g_pass, g_fail);
  return g_fail ? 1 : 0;
}

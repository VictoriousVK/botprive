// Backtest « avant / après » sur les MÊMES données synthétiques (modèle book de chaque moteur) :
//   avant = moteur LRL Map (première version de l'EA)
//   après = moteur OPR + FVG (modèle London OPR)
// Les données sont synthétiques (aucune donnée NQ réelle n'est accessible dans cet environnement) :
// ce comparatif mesure le comportement des règles, pas la rentabilité.
#include "mql5_core.h"
bool g_shim_quiet = true;
#include "LRL_Engine.mqh"
#include "OPR_Engine.mqh"
#include "synth.h"

#include <map>

static long mk(int y, int mo, int d, int h, int mi) {
  MqlDateTime s;
  memset(&s, 0, sizeof(s));
  s.year = y; s.mon = mo; s.day = d; s.hour = h; s.min = mi;
  return (long)StructToTime(s);
}

int main() {
  printf("Backtest avant / après (données synthétiques M1, serveur = NY + 7 h)\n");
  printf("%-6s | %-34s | %6s | %8s | %7s | %6s | %8s | %7s\n", "graine", "moteur", "jours", "trades", "/jour", "WR", "net R", "R moyen");
  for (unsigned seed = 61; seed <= 63; seed++) {
    auto bars = synth(260000, seed, (datetime)(mk(2025, 1, 5, 18, 0) + 7 * 3600));
    // --- avant : LRL Map, paramètres par défaut de l'EA
    CLRLEngine lrl;
    LRLConfig lc;
    lc.Defaults();
    lc.tickSize = 0.25;
    lc.tzMode = LRL_TZ_SERVER_NY;
    lc.serverMinusNySec = 7 * 3600;
    lrl.Init(lc);
    // --- après : OPR + FVG, paramètres par défaut de l'EA
    COprEngine opr;
    OPRConfig oc;
    oc.Defaults();
    oc.tickSize = 0.25;
    opr.Init(oc);
    std::map<int, int> lrlDays;
    for (auto &b : bars) {
      lrl.ProcessBar(b.t, b.o, b.h, b.l, b.c);
      opr.ProcessBar(b.t, b.o, b.h, b.l, b.c);
    }
    int days = opr.stats.days;
    const LRLStats &a = lrl.m_stats;
    const OStats &o = opr.stats;
    printf("%-6u | %-34s | %6d | %8d | %7.2f | %5.1f%% | %+8.1f | %+7.2f\n", seed, "avant : LRL Map (24 h, 3 HTF)", days, a.trades,
           (double)a.trades / days, a.trades ? 100.0 * a.wins / a.trades : 0.0, a.netR, a.trades ? a.netR / a.trades : 0.0);
    printf("%-6s | %-34s | %6d | %8d | %7.2f | %5.1f%% | %+8.1f | %+7.2f\n", "", "après : OPR + FVG (02:50-04:10 NY)", days, o.trades,
           (double)o.trades / days, o.trades ? 100.0 * o.wins / o.trades : 0.0, o.netR, o.trades ? o.netR / o.trades : 0.0);
    printf("%-6s |   après, entonnoir : biais %d (dont consolidation %d), prises de liquidité %d, FVG candidats %d, setups armés %d,\n"
           "       |   rejets : sans sweep %d, hors macro %d, macro déjà tradée %d, cible déjà atteinte %d, position ouverte %d\n",
           "", o.biasBuy + o.biasSell, o.biasConsol, o.sweeps, o.candidates, o.armed, o.rejected[R_NO_SWEEP], o.rejected[R_OUTSIDE_MACRO],
           o.rejected[R_MACRO_USED], o.rejected[R_TARGET_REACHED], o.rejected[R_IN_POSITION]);
  }
  printf("\nRappel : ces chiffres viennent d'une marche aléatoire avec phases de tendance. Ils ne disent RIEN de la\n"
         "rentabilité sur le NQ réel ; seul le testeur de stratégie MT5 sur l'historique du broker peut le mesurer.\n");
  return 0;
}

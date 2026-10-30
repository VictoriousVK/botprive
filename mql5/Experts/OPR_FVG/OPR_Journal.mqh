//+------------------------------------------------------------------+
//|                                                  OPR_Journal.mqh |
//|  Module 8 : journalisation et diagnostic.                        |
//|  Chaque décision du moteur est un événement codé, horodaté       |
//|  (heure stratégie + heure serveur), avec les prix concernés et,  |
//|  pour un rejet, sa raison. Le texte est produit ici pour que     |
//|  l'EA, les tests et le fichier CSV utilisent le même libellé.    |
//+------------------------------------------------------------------+
#ifndef OPR_JOURNAL_MQH
#define OPR_JOURNAL_MQH

#include "OPR_FVG.mqh"
#include "OPR_Liquidity.mqh"

//--- codes d'événements
#define J_OPR_BUILDING      1
#define J_OPR_FINAL         2
#define J_OPR_INCOMPLETE    3
#define J_OPR_NODATA        4
#define J_ASIA_FINAL        5
#define J_ASIA_FVG          6
#define J_ASIA_FVG_NONE     7
#define J_MIDNIGHT_FVG      8
#define J_CTX_ABOVE         9
#define J_CTX_BELOW         10
#define J_CTX_INSIDE        11
#define J_FVG_DETECTED      12
#define J_FVG_STATUS        13
#define J_WINDOW_OPEN       14
#define J_WINDOW_CLOSE      15
#define J_MACRO_OPEN        16
#define J_MACRO_CLOSE       17
#define J_OBS_OPEN          18
#define J_OBS_CLOSE         19
#define J_BIAS              20
#define J_BIAS_CONSOL       21
#define J_BIAS_BREAKOUT     22
#define J_SWEEP             23
#define J_FVG_CANDIDATE     24
#define J_FVG_IGNORED       25
#define J_ENTRY_REJECTED    26
#define J_ENTRY_AUTHORIZED  27
#define J_SETUP_CANCELLED   28
#define J_TRADE_FILLED      29
#define J_TRADE_CLOSED      30
#define J_DAY_START         31
#define J_SESSION_INFO      32

//--- raisons de rejet / d'annulation
#define R_NONE              0
#define R_NO_OPR            1   // OPR non finalisé / incomplet / sans données
#define R_TRADE_DISABLED    2   // pas de règle d'entrée configurée pour cet OPR
#define R_WRONG_DIR         3   // FVG dans le sens opposé au biais
#define R_OUTSIDE_MACRO     4
#define R_MACRO_USED        5   // 1 macro = 1 trade
#define R_IN_POSITION       6
#define R_TARGET_REACHED    7   // cible atteinte avant l'entrée
#define R_INVALID_LEVELS    8
#define R_MIN_STOP          9
#define R_MAX_STOP          10
#define R_DAY_LIMIT         11
#define R_FVG_INVALID       12
#define R_WINDOW_END        13
#define R_SL_BEFORE_ENTRY   14
#define R_NO_SWEEP          15  // FVG sans prise de liquidité préalable
#define R_AMBIGUOUS         16  // entrée et cible sur la même bougie (book conservateur)

struct OJEvent
  {
   int               code;
   int               slot;     // -1 : aucun
   int               dir;
   int               reason;
   int               aux;      // détail (statut FVG, source de liquidité, n° de macro...)
   long              id;
   long              st;       // heure stratégie
   datetime          srv;      // heure serveur de la bougie traitée
   double            p1;
   double            p2;
   double            p3;
   double            p4;
  };

string OprReasonText(const int r)
  {
   switch(r)
     {
      case R_NO_OPR:          return "OPR non finalisé (incomplet ou sans données)";
      case R_TRADE_DISABLED:  return "aucune règle d'entrée configurée pour cet OPR";
      case R_WRONG_DIR:       return "FVG dans le sens opposé au biais";
      case R_OUTSIDE_MACRO:   return "FVG formé hors d'une macro";
      case R_MACRO_USED:      return "macro déjà tradée (1 macro = 1 trade)";
      case R_IN_POSITION:     return "position déjà ouverte";
      case R_TARGET_REACHED:  return "cible atteinte avant l'entrée : pas de trade";
      case R_INVALID_LEVELS:  return "niveaux incohérents (entrée/stop/cible)";
      case R_MIN_STOP:        return "stop inférieur au minimum";
      case R_MAX_STOP:        return "stop supérieur au maximum";
      case R_DAY_LIMIT:       return "limite de trades journalière atteinte";
      case R_FVG_INVALID:     return "FVG d'entrée invalidé avant l'exécution";
      case R_WINDOW_END:      return "fin de la fenêtre de trading";
      case R_SL_BEFORE_ENTRY: return "niveau du stop dépassé avant l'entrée";
      case R_NO_SWEEP:        return "confirmation manquante : aucune prise de liquidité";
      case R_AMBIGUOUS:       return "entrée et cible touchées sur la même bougie (book conservateur)";
      default:                return "";
     }
  }

string OprDirText(const int dir) { return dir > 0 ? "ACHAT" : (dir < 0 ? "VENTE" : "-"); }
string OprFvgKind(const int dir) { return dir > 0 ? "haussier " : "baissier "; }

//+------------------------------------------------------------------+
//| Libellé complet d'un événement                                   |
//+------------------------------------------------------------------+
string OprEventText(const OJEvent &e, const string slotName, const int digits)
  {
   string px1 = DoubleToString(e.p1, digits);
   string px2 = DoubleToString(e.p2, digits);
   string px3 = DoubleToString(e.p3, digits);
   switch(e.code)
     {
      case J_DAY_START:        return "nouvelle journée de session";
      case J_OPR_BUILDING:     return slotName + " : OPR en cours de calcul";
      case J_OPR_FINAL:        return slotName + " : OPR finalisé, High " + px1 + " / Low " + px2;
      case J_OPR_INCOMPLETE:   return slotName + " : OPR incomplet (historique insuffisant), non utilisé";
      case J_OPR_NODATA:       return slotName + " : OPR sans données (aucune bougie dans la plage)";
      case J_ASIA_FINAL:       return "range asiatique finalisé, High " + px1 + " / Low " + px2;
      case J_ASIA_FVG:         return "premier FVG M15 asiatique identifié : " + OprFvgKind(e.dir) + px2 + " - " + px1;
      case J_ASIA_FVG_NONE:    return "aucun FVG M15 dans la plage asiatique";
      case J_MIDNIGHT_FVG:     return "FPFVG M1 de minuit identifié : " + OprFvgKind(e.dir) + px2 + " - " + px1;
      case J_CTX_ABOVE:        return slotName + " : prix au-dessus de l'OPR High (" + px1 + ")";
      case J_CTX_BELOW:        return slotName + " : prix sous l'OPR Low (" + px2 + ")";
      case J_CTX_INSIDE:       return slotName + " : prix à l'intérieur de l'OPR";
      case J_FVG_DETECTED:     return StringFormat("FVG M%d %s détecté : ", e.aux, e.dir > 0 ? "haussier" : "baissier") + px2 + " - " + px1;
      case J_FVG_STATUS:       return StringFormat("FVG M%d %s ", e.aux / 10, e.dir > 0 ? "haussier" : "baissier") + px2 + " - " + px1 +
                                         " : " + OprFvgStatusText(e.aux % 10);
      case J_WINDOW_OPEN:      return slotName + " : ouverture de la fenêtre de trading";
      case J_WINDOW_CLOSE:     return slotName + " : fermeture de la fenêtre de trading";
      case J_MACRO_OPEN:       return slotName + StringFormat(" : début de la macro n°%d", e.aux + 1);
      case J_MACRO_CLOSE:      return slotName + StringFormat(" : fin de la macro n°%d", e.aux + 1);
      case J_OBS_OPEN:         return "début de la fenêtre d'observation (information uniquement)";
      case J_OBS_CLOSE:        return "fin de la fenêtre d'observation";
      case J_BIAS:             return slotName + " : biais " + OprDirText(e.dir) + " (prix " + px1 + (e.dir > 0 ? " au-dessus de l'OPR High " + px2 : " sous l'OPR Low " + px3) + ")";
      case J_BIAS_CONSOL:      return slotName + " : prix dans l'OPR à l'ouverture de la fenêtre (consolidation), attente d'une clôture hors de l'OPR";
      case J_BIAS_BREAKOUT:    return slotName + " : clôture hors de l'OPR à " + px1 + ", biais " + OprDirText(e.dir);
      case J_SWEEP:            return slotName + " : liquidité prise (" + OprLiqSrcText(e.aux) + " " + px1 + ")";
      case J_FVG_CANDIDATE:    return slotName + " : FVG candidat " + OprDirText(e.dir) + " " + px2 + " - " + px1;
      case J_FVG_IGNORED:      return slotName + " : FVG ignoré, " + OprReasonText(e.reason);
      case J_ENTRY_REJECTED:   return slotName + " : entrée rejetée, " + OprReasonText(e.reason);
      case J_ENTRY_AUTHORIZED: return slotName + " : entrée autorisée " + OprDirText(e.dir) + ", toutes les conditions sont remplies : entrée " + px1 + " stop " + px2 + " cible " + px3;
      case J_SETUP_CANCELLED:  return slotName + " : setup annulé, " + OprReasonText(e.reason);
      case J_TRADE_FILLED:     return slotName + " : trade " + OprDirText(e.dir) + " exécuté (book) à " + px1;
      case J_TRADE_CLOSED:     return slotName + StringFormat(" : trade clôturé (book) %+.2fR", e.p4);
      case J_SESSION_INFO:
        {
         string what = (e.aux == 1) ? "ouverture" : "fermeture";
         return what + " de la session de Londres (information)";
        }
      default:                 return "";
     }
  }

class CJournal
  {
public:
   OJEvent           m_ev[];
   int               m_count;

                     CJournal() { m_count = 0; }

   void              Clear() { m_count = 0; }

   void              Add(const int code, const int slot, const int dir, const int reason, const int aux, const long id,
                         const long st, const datetime srv, const double p1, const double p2, const double p3, const double p4)
     {
      if(m_count >= ArraySize(m_ev))
         ArrayResize(m_ev, m_count + 32);
      m_ev[m_count].code   = code;
      m_ev[m_count].slot   = slot;
      m_ev[m_count].dir    = dir;
      m_ev[m_count].reason = reason;
      m_ev[m_count].aux    = aux;
      m_ev[m_count].id     = id;
      m_ev[m_count].st     = st;
      m_ev[m_count].srv    = srv;
      m_ev[m_count].p1     = p1;
      m_ev[m_count].p2     = p2;
      m_ev[m_count].p3     = p3;
      m_ev[m_count].p4     = p4;
      m_count++;
     }
  };

#endif // OPR_JOURNAL_MQH
//+------------------------------------------------------------------+

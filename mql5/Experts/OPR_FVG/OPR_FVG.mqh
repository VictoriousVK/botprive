//+------------------------------------------------------------------+
//|                                                      OPR_FVG.mqh |
//|  Module 3 : détection des FVG, indépendante et testable.         |
//|                                                                  |
//|  Définition (identique en historique et en temps réel), sur      |
//|  trois bougies CLÔTURÉES consécutives c1 (la plus ancienne),     |
//|  c2, c3 :                                                        |
//|    FVG haussier : Low(c3) > High(c1)  -> zone [High(c1), Low(c3)] |
//|    FVG baissier : High(c3) < Low(c1)  -> zone [High(c3), Low(c1)] |
//|  avec une taille minimale (en prix). Le FVG est confirmé à la    |
//|  clôture de c3, jamais avant.                                    |
//|                                                                  |
//|  Statuts (règles documentées, à valider) :                       |
//|    VALIDE     : formé, pas encore revisité ;                     |
//|    MITIGÉ     : une bougie du même timeframe est revenue dans la |
//|                 zone (mèche) ;                                   |
//|    INVALIDÉ   : une bougie du même timeframe a CLÔTURÉ au-delà   |
//|                 du bord opposé ;                                 |
//|    EXPIRÉ     : fin de la journée de session.                    |
//+------------------------------------------------------------------+
#ifndef OPR_FVG_MQH
#define OPR_FVG_MQH

#include "OPR_Candles.mqh"

#define FVG_VALID        0
#define FVG_MITIGATED    1
#define FVG_INVALIDATED  2
#define FVG_EXPIRED      3

#define FVG_ROLE_NONE     0
#define FVG_ROLE_ASIA     1   // premier FVG M15 de la plage asiatique (référence)
#define FVG_ROLE_MIDNIGHT 2   // FPFVG M1 après minuit (référence)
#define FVG_ROLE_ENTRY    3   // FVG utilisé comme zone d'entrée

#define OPR_MAX_FVG 3000

struct OFvg
  {
   long              id;
   int               dir;        // +1 haussier, -1 baissier
   int               tfMin;
   double            lo;
   double            hi;
   long              c1T;        // ouvertures (heure stratégie)
   long              c2T;
   long              c3T;
   long              formedT;    // clôture de c3 = confirmation
   datetime          c1Srv;
   datetime          formedSrv;
   int               status;
   long              statusT;
   int               role;
   int               slot;       // OPR associé (-1 : aucun)
   int               day;        // journée de session de formation
  };

//+------------------------------------------------------------------+
//| Détection pure sur trois bougies clôturées                       |
//+------------------------------------------------------------------+
bool OprFvgDetect(const OCandle &c1, const OCandle &c2, const OCandle &c3, const double minSize,
                  int &dir, double &lo, double &hi)
  {
   dir = 0;
   if(c3.l > c1.h && (c3.l - c1.h) >= minSize)
     {
      dir = 1;
      lo  = c1.h;
      hi  = c3.l;
      return true;
     }
   if(c3.h < c1.l && (c1.l - c3.h) >= minSize)
     {
      dir = -1;
      lo  = c3.h;
      hi  = c1.l;
      return true;
     }
   return false;
  }

string OprFvgStatusText(const int st)
  {
   switch(st)
     {
      case FVG_VALID:       return "valide";
      case FVG_MITIGATED:   return "mitigé";
      case FVG_INVALIDATED: return "invalidé";
      case FVG_EXPIRED:     return "expiré";
      default:              return "?";
     }
  }

//+------------------------------------------------------------------+
//| Registre des FVG de la journée                                   |
//+------------------------------------------------------------------+
class CFvgBook
  {
public:
   OFvg              m_list[];
   //--- changements de statut survenus lors du dernier OnCandle()
   int               m_chgIdx[];
   int               m_chgCount;

                     CFvgBook() { m_chgCount = 0; }

   void              Reset()
     {
      ArrayResize(m_list, 0, 256);
      ArrayResize(m_chgIdx, 0, 16);
      m_chgCount = 0;
     }

   int               Count() const { return ArraySize(m_list); }

   int               Find(const long id) const
     {
      for(int i = ArraySize(m_list) - 1; i >= 0; i--)
         if(m_list[i].id == id)
            return i;
      return -1;
     }

   //--- détecte un FVG sur les 3 dernières bougies clôturées de l'agrégateur ; renvoie l'index ou -1
   int               DetectOnClose(const CCandleAgg &agg, const double minSize, const int day)
     {
      OCandle c1, c2, c3;
      if(!agg.Get(2, c1) || !agg.Get(1, c2) || !agg.Get(0, c3))
         return -1;
      int dir = 0;
      double lo = 0.0, hi = 0.0;
      if(!OprFvgDetect(c1, c2, c3, minSize, dir, lo, hi))
         return -1;
      int n = ArraySize(m_list);
      if(n >= OPR_MAX_FVG)
        {
         //--- on retire le plus ancien FVG sans rôle
         int drop = -1;
         for(int i = 0; i < n; i++)
            if(m_list[i].role == FVG_ROLE_NONE)
              {
               drop = i;
               break;
              }
         if(drop < 0)
            return -1;
         for(int j = drop; j < n - 1; j++)
            m_list[j] = m_list[j + 1];
         n--;
        }
      ArrayResize(m_list, n + 1, 256);
      int tf = agg.PeriodMin();
      m_list[n].id        = (c3.t + agg.m_period) * 64 + tf * 2 + (dir > 0 ? 1 : 0);
      m_list[n].dir       = dir;
      m_list[n].tfMin     = tf;
      m_list[n].lo        = lo;
      m_list[n].hi        = hi;
      m_list[n].c1T       = c1.t;
      m_list[n].c2T       = c2.t;
      m_list[n].c3T       = c3.t;
      m_list[n].formedT   = c3.t + agg.m_period;
      m_list[n].c1Srv     = c1.srv;
      m_list[n].formedSrv = (datetime)((long)c3.srv + agg.m_period);
      m_list[n].status    = FVG_VALID;
      m_list[n].statusT   = m_list[n].formedT;
      m_list[n].role      = FVG_ROLE_NONE;
      m_list[n].slot      = -1;
      m_list[n].day       = day;
      return n;
     }

   //--- met à jour les statuts des FVG du timeframe avec une bougie clôturée de ce timeframe
   void              OnCandle(const int tfMin, const OCandle &cd, const long closeT)
     {
      m_chgCount = 0;
      int n = ArraySize(m_list);
      for(int i = 0; i < n; i++)
        {
         if(m_list[i].tfMin != tfMin || m_list[i].formedT > cd.t)
            continue;
         int st = m_list[i].status;
         if(st == FVG_INVALIDATED || st == FVG_EXPIRED)
            continue;
         int ns = st;
         if(m_list[i].dir > 0)
           {
            if(cd.c < m_list[i].lo)
               ns = FVG_INVALIDATED;
            else
               if(st == FVG_VALID && cd.l <= m_list[i].hi)
                  ns = FVG_MITIGATED;
           }
         else
           {
            if(cd.c > m_list[i].hi)
               ns = FVG_INVALIDATED;
            else
               if(st == FVG_VALID && cd.h >= m_list[i].lo)
                  ns = FVG_MITIGATED;
           }
         if(ns != st)
           {
            m_list[i].status  = ns;
            m_list[i].statusT = closeT;
            AddChange(i);
           }
        }
     }

   void              AddChange(const int idx)
     {
      if(m_chgCount >= ArraySize(m_chgIdx))
         ArrayResize(m_chgIdx, m_chgCount + 16);
      m_chgIdx[m_chgCount] = idx;
      m_chgCount++;
     }

   //--- fin de journée : tout ce qui est encore actif expire ; on ne garde que les FVG à rôle
   void              ExpireAll(const long t)
     {
      m_chgCount = 0;
      int n = ArraySize(m_list);
      int w = 0;
      for(int i = 0; i < n; i++)
        {
         if(m_list[i].status == FVG_VALID || m_list[i].status == FVG_MITIGATED)
           {
            m_list[i].status  = FVG_EXPIRED;
            m_list[i].statusT = t;
           }
         if(m_list[i].role == FVG_ROLE_NONE)
            continue;
         if(w != i)
            m_list[w] = m_list[i];
         w++;
        }
      ArrayResize(m_list, w, 256);
      //--- on ne garde que les références des 5 dernières journées
      while(ArraySize(m_list) > 40)
        {
         int m = ArraySize(m_list);
         for(int j = 0; j < m - 1; j++)
            m_list[j] = m_list[j + 1];
         ArrayResize(m_list, m - 1, 256);
        }
     }
  };

#endif // OPR_FVG_MQH
//+------------------------------------------------------------------+

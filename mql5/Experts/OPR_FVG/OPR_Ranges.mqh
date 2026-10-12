//+------------------------------------------------------------------+
//|                                                   OPR_Ranges.mqh |
//|  Module 2 : calcul des OPR (et de la plage asiatique).           |
//|                                                                  |
//|  Pour chaque plage [début, fin) d'une journée de session :       |
//|    - EN ATTENTE  avant le début ;                                |
//|    - EN CALCUL   pendant la plage (niveaux provisoires, jamais   |
//|                  utilisés par le modèle) ;                       |
//|    - FINALISÉ    à la clôture de la dernière bougie de la plage :|
//|                  High = max des High, Low = min des Low des      |
//|                  bougies dont l'ouverture est dans la plage.     |
//|                  Les niveaux ne changent PLUS jamais ;           |
//|    - INCOMPLET   si le moteur n'a pas observé la plage depuis    |
//|                  son début (historique insuffisant) ;            |
//|    - SANS DONNÉES si aucune bougie dans la plage.                |
//|  Chaque plage a son propre état : aucun mélange entre OPR.       |
//+------------------------------------------------------------------+
#ifndef OPR_RANGES_MQH
#define OPR_RANGES_MQH

#include "OPR_Time.mqh"

#define OPR_ST_NONE        0   // plage désactivée
#define OPR_ST_PENDING     1
#define OPR_ST_BUILDING    2
#define OPR_ST_FINAL       3
#define OPR_ST_INCOMPLETE  4
#define OPR_ST_NODATA      5

//--- événements renvoyés par Update()
#define OPR_RG_EV_NONE      0
#define OPR_RG_EV_BUILDING  1
#define OPR_RG_EV_FINAL     2

struct ORangeState
  {
   int               day;
   int               status;
   double            high;
   double            low;
   long              startT;     // heure stratégie
   long              endT;
   datetime          startSrv;   // heure serveur (approx. pour le dessin)
   datetime          endSrv;
   int               candles;
   long              highT;
   long              lowT;
   long              finalT;
   bool              fromStart;
   bool              restored;   // niveaux restaurés depuis la persistance
  };

string OprRangeStatusText(const int st)
  {
   switch(st)
     {
      case OPR_ST_NONE:       return "désactivé";
      case OPR_ST_PENDING:    return "en attente";
      case OPR_ST_BUILDING:   return "en calcul";
      case OPR_ST_FINAL:      return "finalisé";
      case OPR_ST_INCOMPLETE: return "incomplet";
      case OPR_ST_NODATA:     return "sans données";
      default:                return "?";
     }
  }

//--- niveau de déviation standard de la plage (Annexe 1 du PDF London OPR) :
//--- achat : High + k x amplitude ; vente : Low - k x amplitude
double OprStdLevel(const ORangeState &s, const int dir, const double k)
  {
   double r = s.high - s.low;
   if(dir > 0)
      return s.high + k * r;
   return s.low - k * r;
  }

class CRangeCalc
  {
public:
   OPRTimeRange      m_range;
   ORangeState       m_st;
   ORangeState       m_prev;      // journée précédente (pour l'affichage)

                     CRangeCalc() { m_range.Clear(); ResetState(m_st, 0); ResetState(m_prev, 0); }

   void              ResetState(ORangeState &s, const int day)
     {
      s.day       = day;
      s.status    = m_range.valid ? OPR_ST_PENDING : OPR_ST_NONE;
      s.high      = 0.0;
      s.low       = 0.0;
      s.startT    = 0;
      s.endT      = 0;
      s.startSrv  = 0;
      s.endSrv    = 0;
      s.candles   = 0;
      s.highT     = 0;
      s.lowT      = 0;
      s.finalT    = 0;
      s.fromStart = false;
      s.restored  = false;
     }

   void              Init(const OPRTimeRange &r)
     {
      m_range = r;
      ResetState(m_st, 0);
      ResetState(m_prev, 0);
     }

   bool              IsFinal() const { return m_st.status == OPR_ST_FINAL; }

   //--- nouvelle journée de session
   void              NewDay(const COprTime &tm, const int day, const long srvOffset)
     {
      if(m_st.day != 0)
         m_prev = m_st;
      ResetState(m_st, day);
      long s = 0, e = 0;
      if(tm.RangeAbs(day, m_range, s, e))
        {
         m_st.startT   = s;
         m_st.endT     = e;
         m_st.startSrv = (datetime)(s - srvOffset);
         m_st.endSrv   = (datetime)(e - srvOffset);
        }
     }

   //--- traite une bougie de base clôturée ; firstT = première bougie vue par le moteur
   int               Update(const long st, const double h, const double l, const int baseSec, const long firstT)
     {
      int ev = OPR_RG_EV_NONE;
      if(m_st.status == OPR_ST_NONE)
         return ev;
      //--- clôture tardive (dernière bougie de la plage manquante)
      if(m_st.status == OPR_ST_BUILDING && st >= m_st.endT)
        {
         Finalize(m_st.endT);
         return OPR_RG_EV_FINAL;
        }
      if(m_st.status == OPR_ST_PENDING && st >= m_st.endT)
        {
         m_st.status = OPR_ST_NODATA;
         m_st.finalT = m_st.endT;
         return OPR_RG_EV_FINAL;
        }
      if(st >= m_st.startT && st < m_st.endT && (m_st.status == OPR_ST_PENDING || m_st.status == OPR_ST_BUILDING))
        {
         if(m_st.status == OPR_ST_PENDING)
           {
            m_st.status    = OPR_ST_BUILDING;
            m_st.fromStart = (firstT <= m_st.startT);
            m_st.high      = h;
            m_st.low       = l;
            m_st.highT     = st;
            m_st.lowT      = st;
            ev = OPR_RG_EV_BUILDING;
           }
         else
           {
            if(h > m_st.high)
              {
               m_st.high  = h;
               m_st.highT = st;
              }
            if(l < m_st.low)
              {
               m_st.low  = l;
               m_st.lowT = st;
              }
           }
         m_st.candles++;
         if(st + baseSec >= m_st.endT)
           {
            Finalize(st + baseSec);
            ev = OPR_RG_EV_FINAL;
           }
        }
      return ev;
     }

   void              Finalize(const long t)
     {
      m_st.status = m_st.fromStart ? OPR_ST_FINAL : OPR_ST_INCOMPLETE;
      m_st.finalT = t;
     }

   //--- restauration depuis la persistance (même journée, plage déjà terminée)
   bool              Restore(const int day, const double high, const double low)
     {
      if(m_st.day != day || m_st.status == OPR_ST_FINAL || m_st.status == OPR_ST_BUILDING || m_st.status == OPR_ST_PENDING)
         return false;
      if(!(high >= low) || high <= 0.0)
         return false;
      m_st.high     = high;
      m_st.low      = low;
      m_st.status   = OPR_ST_FINAL;
      m_st.restored = true;
      return true;
     }
  };

#endif // OPR_RANGES_MQH
//+------------------------------------------------------------------+

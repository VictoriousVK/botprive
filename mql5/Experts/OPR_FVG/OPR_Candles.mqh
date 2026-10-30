//+------------------------------------------------------------------+
//|                                                  OPR_Candles.mqh |
//|  Bougies M1 / M5 / M15 reconstruites à partir des bougies M1     |
//|  clôturées, alignées sur l'heure de la stratégie.                |
//|  Une bougie n'existe pour le reste du moteur qu'une fois         |
//|  CLÔTURÉE : jamais de bougie en formation, jamais de futur.      |
//+------------------------------------------------------------------+
#ifndef OPR_CANDLES_MQH
#define OPR_CANDLES_MQH

#define OPR_CANDLE_RING 512

struct OCandle
  {
   long              t;      // ouverture, heure stratégie
   datetime          srv;    // ouverture, heure serveur
   double            o;
   double            h;
   double            l;
   double            c;
  };

class CCandleAgg
  {
public:
   int               m_period;     // secondes
   bool              m_hasCur;
   bool              m_started;
   long              m_curStart;
   datetime          m_curSrv;
   double            m_o;
   double            m_h;
   double            m_l;
   double            m_c;
   OCandle           m_ring[];
   int               m_head;
   int               m_count;
   OCandle           m_closed[2];  // bougies clôturées lors du dernier Add()
   int               m_nClosed;

                     CCandleAgg() { m_period = 60; m_head = 0; m_count = 0; m_nClosed = 0; m_hasCur = false; m_started = false; }

   void              Init(const int periodSec)
     {
      m_period  = periodSec;
      m_hasCur  = false;
      m_started = false;
      m_head    = 0;
      m_count   = 0;
      m_nClosed = 0;
      ArrayResize(m_ring, OPR_CANDLE_RING);
     }

   int               PeriodMin() const { return m_period / 60; }

   void              CloseCurrent()
     {
      OCandle cd;
      cd.t   = m_curStart;
      cd.srv = m_curSrv;
      cd.o   = m_o;
      cd.h   = m_h;
      cd.l   = m_l;
      cd.c   = m_c;
      m_ring[m_head] = cd;
      m_head = (m_head + 1) % OPR_CANDLE_RING;
      if(m_count < OPR_CANDLE_RING)
         m_count++;
      if(m_nClosed < 2)
        {
         m_closed[m_nClosed] = cd;
         m_nClosed++;
        }
      m_hasCur = false;
     }

   //--- ajoute une bougie de base clôturée (st = ouverture, heure stratégie)
   void              Add(const long st, const datetime srv, const double o, const double h, const double l,
                         const double c, const int baseSec)
     {
      m_nClosed = 0;
      long tt = st;
      long rem = tt % m_period;
      if(rem < 0)
         rem += m_period;
      long bucket = tt - rem;
      //--- clôture tardive si la dernière bougie de base de la période manquait
      if(m_hasCur && bucket != m_curStart)
         CloseCurrent();
      if(!m_hasCur)
        {
         //--- la toute première bougie doit être complète
         if(!m_started && tt != bucket)
            return;
         m_started  = true;
         m_hasCur   = true;
         m_curStart = bucket;
         m_curSrv   = (datetime)((long)srv - (tt - bucket));
         m_o = o;
         m_h = h;
         m_l = l;
         m_c = c;
        }
      else
        {
         if(h > m_h)
            m_h = h;
         if(l < m_l)
            m_l = l;
         m_c = c;
        }
      //--- clôture sur la bougie de base dont la clôture coïncide avec celle de la période
      if(tt + baseSec >= m_curStart + m_period)
         CloseCurrent();
     }

   //--- back = 0 : dernière bougie clôturée
   bool              Get(const int back, OCandle &out) const
     {
      if(back < 0 || back >= m_count)
         return false;
      int idx = (m_head - 1 - back + 2 * OPR_CANDLE_RING) % OPR_CANDLE_RING;
      out = m_ring[idx];
      return true;
     }

   int               Count() const { return m_count; }
  };

#endif // OPR_CANDLES_MQH
//+------------------------------------------------------------------+

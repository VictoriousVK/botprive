//+------------------------------------------------------------------+
//|                                                OPR_Liquidity.mqh |
//|  Pools de liquidité et prises de liquidité (sweeps).             |
//|                                                                  |
//|  PDF London OPR, étape 3 : « repérer les liquidités au-dessus et |
//|  en dessous du cours : hauts/bas équivalents, haut/bas de la     |
//|  session asiatique, hauts/bas simples, en priorité en M15 ».     |
//|  Étape 4 : « la Macro doit commencer par prendre une liquidité ».|
//|                                                                  |
//|  Formalisation (à valider) :                                     |
//|   - pool haut  = swing high confirmé (pivot gauche/droite) en M1 |
//|                  ou en M15, ou High de la plage asiatique ;      |
//|   - pool bas   = idem pour les lows ;                            |
//|   - prise      = une bougie M1 clôturée trade AU-DELÀ du niveau  |
//|                  (mèche) alors que le pool était confirmé avant  |
//|                  l'ouverture de cette bougie et pas encore pris. |
//+------------------------------------------------------------------+
#ifndef OPR_LIQUIDITY_MQH
#define OPR_LIQUIDITY_MQH

#include "OPR_Candles.mqh"

#define LIQ_SRC_M1    1
#define LIQ_SRC_M15   15
#define LIQ_SRC_ASIA  100

#define OPR_MAX_POOLS 1500

struct OPool
  {
   int               side;       // +1 = liquidité au-dessus (high), -1 = en dessous (low)
   int               src;
   double            level;
   long              formT;      // ouverture de la bougie du swing (heure stratégie)
   long              confirmT;   // disponible à partir de cette heure
   bool              swept;
   long              sweptT;
  };

string OprLiqSrcText(const int src)
  {
   if(src == LIQ_SRC_M1)
      return "swing M1";
   if(src == LIQ_SRC_M15)
      return "swing M15";
   if(src == LIQ_SRC_ASIA)
      return "range asiatique";
   return "?";
  }

class CLiquidity
  {
public:
   OPool             m_pools[];
   //--- prises survenues sur la dernière bougie traitée
   int               m_sweepIdx[];
   int               m_sweepCount;

                     CLiquidity() { m_sweepCount = 0; }

   void              Reset()
     {
      ArrayResize(m_pools, 0, 128);
      ArrayResize(m_sweepIdx, 0, 8);
      m_sweepCount = 0;
     }

   void              AddLevel(const int side, const int src, const double level, const long formT, const long confirmT)
     {
      int n = ArraySize(m_pools);
      if(n >= OPR_MAX_POOLS)
        {
         for(int i = 0; i < n - 1; i++)
            m_pools[i] = m_pools[i + 1];
         n--;
        }
      ArrayResize(m_pools, n + 1, 128);
      m_pools[n].side     = side;
      m_pools[n].src      = src;
      m_pools[n].level    = level;
      m_pools[n].formT    = formT;
      m_pools[n].confirmT = confirmT;
      m_pools[n].swept    = false;
      m_pools[n].sweptT   = 0;
     }

   //--- swings confirmés sur la dernière bougie clôturée de l'agrégateur (pivot L/R)
   void              OnCandle(const CCandleAgg &agg, const int pivot, const int src)
     {
      if(pivot < 1 || agg.Count() < 2 * pivot + 1)
         return;
      OCandle p;
      if(!agg.Get(pivot, p))
         return;
      bool isHigh = true;
      bool isLow  = true;
      for(int k = 1; k <= pivot; k++)
        {
         OCandle left, right;
         if(!agg.Get(pivot + k, left) || !agg.Get(pivot - k, right))
            return;
         if(!(p.h > left.h) || !(p.h >= right.h))
            isHigh = false;
         if(!(p.l < left.l) || !(p.l <= right.l))
            isLow = false;
        }
      OCandle last;
      if(!agg.Get(0, last))
         return;
      long confirmT = last.t + agg.m_period;
      if(isHigh)
         AddLevel(1, src, p.h, p.t, confirmT);
      if(isLow)
         AddLevel(-1, src, p.l, p.t, confirmT);
     }

   //--- prises de liquidité par une bougie de base clôturée
   void              OnBar(const long st, const double h, const double l)
     {
      m_sweepCount = 0;
      int n = ArraySize(m_pools);
      for(int i = 0; i < n; i++)
        {
         if(m_pools[i].swept || m_pools[i].confirmT > st)
            continue;
         bool taken = (m_pools[i].side > 0) ? (h > m_pools[i].level) : (l < m_pools[i].level);
         if(!taken)
            continue;
         m_pools[i].swept  = true;
         m_pools[i].sweptT = st;
         if(m_sweepCount >= ArraySize(m_sweepIdx))
            ArrayResize(m_sweepIdx, m_sweepCount + 8);
         m_sweepIdx[m_sweepCount] = i;
         m_sweepCount++;
        }
     }

   int               ActiveCount(const int side) const
     {
      int c = 0;
      for(int i = ArraySize(m_pools) - 1; i >= 0; i--)
         if(!m_pools[i].swept && m_pools[i].side == side)
            c++;
      return c;
     }
  };

#endif // OPR_LIQUIDITY_MQH
//+------------------------------------------------------------------+

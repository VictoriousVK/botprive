//+------------------------------------------------------------------+
//|                                                   LRL_Engine.mqh |
//|  Moteur "LRL Map" : Low Resistance Liquidity + iFVG du plus haut |
//|  timeframe, avec statistiques auto-mesurées (modèle "book").     |
//|                                                                  |
//|  Le moteur est purement causal : il reçoit les bougies de base   |
//|  clôturées une par une (ProcessBar) et ne regarde jamais le      |
//|  futur. Aucune fonction de trading ni de dessin ici : l'EA lit   |
//|  l'état public et la file d'événements après chaque bougie.      |
//+------------------------------------------------------------------+
#ifndef LRL_ENGINE_MQH
#define LRL_ENGINE_MQH

#define LRL_RING       16384      // historique de bougies conservé (puissance de 2)
#define LRL_RING_MASK  16383
#define LRL_MAX_HTF    3
#define LRL_SIDE_LOW   0          // ligne de swing lows (sous le prix) -> biais short
#define LRL_SIDE_HIGH  1          // ligne de swing highs (au-dessus)   -> biais long
#define LRL_MAX_CLOSED 50000      // trades clôturés gardés pour l'export CSV
#define LRL_MAX_LIVE_ZONES 240    // FVG non inversés vivants au maximum

//--- modes (les commentaires servent de libellés dans la fenêtre des paramètres)
enum ENUM_LRL_SWEEP
  {
   LRL_SWEEP_WICK  = 0,   // Mèche à travers la ligne
   LRL_SWEEP_CLOSE = 1    // Clôture à travers la ligne
  };

enum ENUM_LRL_INV
  {
   LRL_INV_CLOSE_GAP = 0, // Clôture HTF au-delà du gap
   LRL_INV_CLOSE_CE  = 1  // Clôture HTF au-delà du CE (agressif)
  };

enum ENUM_LRL_ENTRY
  {
   LRL_ENTRY_CE   = 0,    // CE (milieu de la zone)
   LRL_ENTRY_EDGE = 1     // Bord de la zone
  };

enum ENUM_LRL_STOP
  {
   LRL_STOP_LEG  = 0,     // Au-delà du swing de la jambe
   LRL_STOP_ZONE = 1      // Au-delà de la zone
  };

enum ENUM_LRL_TZ
  {
   LRL_TZ_AUTO          = 0, // Auto (live) / décalage NY fixe (testeur)
   LRL_TZ_SERVER_NY     = 1, // Serveur = NY + décalage fixe
   LRL_TZ_SERVER_GMT    = 2  // Serveur = GMT + décalage fixe (DST US calculé)
  };

//--- blocages / raisons de rejet d'un setup
#define LRL_BLOCK_NONE     0
#define LRL_BLOCK_INVALID  1
#define LRL_BLOCK_MINSTOP  2
#define LRL_BLOCK_MAXSTOP  3
#define LRL_BLOCK_LRL      4
#define LRL_SKIP_WINDOW    5
#define LRL_SKIP_FLAT      6

//--- événements
#define LRL_EV_LRL_NEW      1
#define LRL_EV_LRL_END      2
#define LRL_EV_ZONE_INV     3
#define LRL_EV_WATCH_START  4
#define LRL_EV_WATCH_END    5
#define LRL_EV_TRADE_OPEN   6
#define LRL_EV_TRADE_CLOSE  7
#define LRL_EV_SETUP_SKIP   8

//--- fins de ligne LRL
#define LRL_END_SWEEP     1
#define LRL_END_EXPIRE    2
#define LRL_END_REPLACED  3

//--- fins de surveillance d'une zone
#define LRL_WATCH_USED    1
#define LRL_WATCH_LOST    2

//--- sorties de trade
#define LRL_EXIT_TARGET   1
#define LRL_EXIT_STOP     2
#define LRL_EXIT_FLAT     3

//+------------------------------------------------------------------+
//| Configuration                                                    |
//+------------------------------------------------------------------+
struct LRLConfig
  {
   int               baseSeconds;
   int               htfMinutes[LRL_MAX_HTF];
   int               pivotLeft;
   int               pivotRight;
   int               maxSwings;
   int               minTouches;
   double            touchTolAtr;
   int               minSpacing;
   int               atrLen;
   int               sweepMode;
   int               expireBars;
   int               invMode;
   double            minGapTicks;
   int               maxZoneAge;
   int               entryMode;
   int               stopMode;
   double            stopBufferTicks;
   double            rr;
   double            minStop;
   double            maxStopAtr;
   bool              lrlBeyondTarget;
   bool              tradeOnlyInWindow;
   int               winStartMin;
   int               winEndMin;
   bool              flatEnabled;
   int               flatStartMin;
   int               flatEndMin;
   int               tzMode;            // LRL_TZ_SERVER_NY ou LRL_TZ_SERVER_GMT (AUTO résolu par l'EA)
   int               serverMinusNySec;
   int               serverGmtSec;
   double            tickSize;

   void              Defaults()
     {
      baseSeconds       = 60;
      htfMinutes[0]     = 2;
      htfMinutes[1]     = 3;
      htfMinutes[2]     = 5;
      pivotLeft         = 3;
      pivotRight        = 3;
      maxSwings         = 20;
      minTouches        = 3;
      touchTolAtr       = 0.15;
      minSpacing        = 5;
      atrLen            = 14;
      sweepMode         = LRL_SWEEP_WICK;
      expireBars        = 1500;
      invMode           = LRL_INV_CLOSE_GAP;
      minGapTicks       = 0.0;
      maxZoneAge        = 200;
      entryMode         = LRL_ENTRY_CE;
      stopMode          = LRL_STOP_LEG;
      stopBufferTicks   = 1.0;
      rr                = 1.0;
      minStop           = 15.0;
      maxStopAtr        = 0.0;
      lrlBeyondTarget   = true;
      tradeOnlyInWindow = true;
      winStartMin       = 0;
      winEndMin         = 16 * 60;
      flatEnabled       = true;
      flatStartMin      = 15 * 60 + 55;
      flatEndMin        = 16 * 60;
      tzMode            = LRL_TZ_SERVER_NY;
      serverMinusNySec  = 7 * 3600;
      serverGmtSec      = 0;
      tickSize          = 0.25;
     }
  };

//+------------------------------------------------------------------+
//| Structures d'état                                                |
//+------------------------------------------------------------------+
struct LRLSwing
  {
   int               bar;
   datetime          time;
   double            price;
  };

struct LRLLine
  {
   bool              active;
   int               side;
   long              id;
   int               anchorBar;
   double            anchorPrice;
   double            slope;          // prix par bougie de base
   int               pairA;          // bougies de la paire qui définit la pente
   int               pairB;
   int               firstBar;
   datetime          firstTime;
   int               lastTouchBar;
   datetime          lastTouchTime;
   int               touches;
   int               createdBar;
   datetime          createdTime;
   int               endBar;
   datetime          endTime;
   double            endPrice;
   int               endReason;

   void              Reset()
     {
      active = false; side = 0; id = 0; anchorBar = 0; anchorPrice = 0.0; slope = 0.0;
      pairA = -1; pairB = -1; firstBar = -1; firstTime = 0; lastTouchBar = -1; lastTouchTime = 0;
      touches = 0; createdBar = -1; createdTime = 0; endBar = -1; endTime = 0; endPrice = 0.0; endReason = 0;
     }
   double            PriceAt(const int bar) const { return anchorPrice + slope * (double)(bar - anchorBar); }
  };

struct LRLZone
  {
   long              id;
   int               level;          // index du niveau HTF (0..2)
   int               tfMin;          // minutes du niveau (sert au classement)
   int               dir;            // -1 = iFVG baissier (short), +1 = iFVG haussier (long)
   double            top;
   double            bottom;
   datetime          t0;             // ouverture de la bougie HTF du milieu
   int               createdBar;
   int               createdCandle;
   bool              inverted;
   int               invBar;
   datetime          invTime;
   int               invCandle;
   double            legExt;         // extrême de la jambe entre le gap et l'inversion
   bool              dead;
   bool              used;
  };

struct LRLHtf
  {
   bool              enabled;
   int               minutes;
   int               periodSec;
   bool              hasCur;
   long              curStart;
   double            o;
   double            h;
   double            l;
   double            c;
   double            cO[3];          // [0] = dernière bougie HTF clôturée
   double            cH[3];
   double            cL[3];
   double            cC[3];
   datetime          cT[3];
   int               nClosed;
   int               count;
  };

struct LRLArmed
  {
   bool              valid;
   long              zoneId;
   int               dir;
   int               tfMin;
   double            entry;
   double            stop;
   double            target;
   double            risk;
   double            lrlPrice;
   double            top;
   double            bottom;
   datetime          t0;
   datetime          invTime;
   int               block;

   void              Reset()
     {
      valid = false; zoneId = 0; dir = 0; tfMin = 0; entry = 0.0; stop = 0.0; target = 0.0; risk = 0.0;
      lrlPrice = 0.0; top = 0.0; bottom = 0.0; t0 = 0; invTime = 0; block = LRL_BLOCK_NONE;
     }
  };

struct LRLTrade
  {
   long              zoneId;
   int               dir;
   int               tfMin;
   double            entry;
   double            stop;
   double            target;
   double            risk;
   int               entryBar;
   datetime          entryTime;
   bool              inWindow;
   bool              open;
   int               exitBar;
   datetime          exitTime;
   double            exitPrice;
   int               exitReason;
   double            r;
  };

struct LRLStats
  {
   int               trades;
   int               wins;
   int               losses;
   double            netR;
   int               inTrades;
   int               inWins;
   double            inNetR;
   int               outTrades;
   int               outWins;
   double            outNetR;
   int               skipMinStop;
   int               skipMaxStop;
   int               skipLrl;
   int               skipWindow;
   int               skipFlat;
   int               skipInvalid;
   int               armed;

   void              Reset()
     {
      trades = 0; wins = 0; losses = 0; netR = 0.0;
      inTrades = 0; inWins = 0; inNetR = 0.0; outTrades = 0; outWins = 0; outNetR = 0.0;
      skipMinStop = 0; skipMaxStop = 0; skipLrl = 0; skipWindow = 0; skipFlat = 0; skipInvalid = 0; armed = 0;
     }
  };

struct LRLEvent
  {
   int               type;
   int               side;           // côté LRL ou direction du trade/zone
   long              id;
   int               tfMin;
   int               reason;
   int               n;
   datetime          t1;
   datetime          t2;
   double            p1;
   double            p2;
   double            p3;
   double            p4;
   double            p5;
  };

//+------------------------------------------------------------------+
//| Moteur                                                           |
//+------------------------------------------------------------------+
class CLRLEngine
  {
public:
   LRLConfig         cfg;

   //--- bougies de base (anneau)
   datetime          m_t[];
   double            m_o[];
   double            m_h[];
   double            m_l[];
   double            m_c[];
   int               m_bar;          // index absolu de la dernière bougie traitée (-1 = aucune)

   //--- ATR (RMA de Wilder, comme ta.atr)
   double            m_atr;
   double            m_atrSum;
   int               m_atrN;
   double            m_prevClose;

   //--- swings confirmés
   LRLSwing          m_swLo[];
   LRLSwing          m_swHi[];

   //--- LRL actives
   LRLLine           m_lrl[2];
   long              m_lineSeq;

   //--- timeframes supérieurs reconstruits
   LRLHtf            m_htf[LRL_MAX_HTF];
   int               m_htfCount;

   //--- FVG / iFVG
   LRLZone           m_zones[];

   //--- biais, zone surveillée, setup armé
   int               m_bias;
   int               m_watchIdx;
   long              m_watchId;
   LRLArmed          m_armed;

   //--- modèle book
   LRLTrade          m_open[];
   LRLTrade          m_closed[];
   LRLStats          m_stats;

   //--- événements de la dernière bougie traitée
   LRLEvent          m_events[];
   int               m_evCount;

   //--- cache DST US
   int               m_dstYear;
   long              m_dstStart;
   long              m_dstEnd;

                     CLRLEngine() { m_bar = -1; m_htfCount = 0; m_dstYear = 0; }

   //+---------------------------------------------------------------+
   bool              Init(const LRLConfig &c)
     {
      cfg = c;
      if(cfg.tickSize <= 0.0)
         cfg.tickSize = 0.00001;
      if(cfg.baseSeconds <= 0)
         cfg.baseSeconds = 60;
      if(cfg.pivotLeft < 1)
         cfg.pivotLeft = 1;
      if(cfg.pivotRight < 1)
         cfg.pivotRight = 1;
      if(cfg.maxSwings < 3)
         cfg.maxSwings = 3;
      if(cfg.minTouches < 2)
         cfg.minTouches = 2;
      if(cfg.minSpacing < 1)
         cfg.minSpacing = 1;
      if(cfg.atrLen < 1)
         cfg.atrLen = 1;
      if(cfg.expireBars < 1)
         cfg.expireBars = 1;
      if(cfg.rr <= 0.0)
         cfg.rr = 1.0;

      ArrayResize(m_t, LRL_RING);
      ArrayResize(m_o, LRL_RING);
      ArrayResize(m_h, LRL_RING);
      ArrayResize(m_l, LRL_RING);
      ArrayResize(m_c, LRL_RING);
      ArrayResize(m_swLo, 0);
      ArrayResize(m_swHi, 0);
      ArrayResize(m_zones, 0, 256);
      ArrayResize(m_open, 0, 16);
      ArrayResize(m_closed, 0, 1024);
      ArrayResize(m_events, 16);
      m_evCount   = 0;
      m_bar       = -1;
      m_atr       = 0.0;
      m_atrSum    = 0.0;
      m_atrN      = 0;
      m_prevClose = 0.0;
      m_lineSeq   = 0;
      m_bias      = 0;
      m_watchIdx  = -1;
      m_watchId   = 0;
      m_dstYear   = 0;
      m_lrl[0].Reset();
      m_lrl[1].Reset();
      m_armed.Reset();
      m_stats.Reset();

      //--- timeframes supérieurs : valides, uniques, triés du plus petit au plus grand
      int mins[LRL_MAX_HTF];
      int n = 0;
      for(int i = 0; i < LRL_MAX_HTF; i++)
        {
         int m = cfg.htfMinutes[i];
         if(m <= 0)
            continue;
         int ps = m * 60;
         if(ps <= cfg.baseSeconds || (ps % cfg.baseSeconds) != 0 || ps > 86400 || (86400 % ps) != 0)
           {
            PrintFormat("LRL Map: HTF %d min ignoré (doit être > et multiple de la base %d s, et diviser 24h)", m, cfg.baseSeconds);
            continue;
           }
         bool dup = false;
         for(int k = 0; k < n; k++)
            if(mins[k] == m)
               dup = true;
         if(dup)
           {
            PrintFormat("LRL Map: HTF %d min en double, ignoré", m);
            continue;
           }
         mins[n] = m;
         n++;
        }
      for(int a = 0; a < n - 1; a++)
         for(int b2 = a + 1; b2 < n; b2++)
            if(mins[b2] < mins[a])
              {
               int tmp = mins[a];
               mins[a] = mins[b2];
               mins[b2] = tmp;
              }
      m_htfCount = n;
      for(int li = 0; li < LRL_MAX_HTF; li++)
        {
         ZeroMemory(m_htf[li]);
         m_htf[li].enabled = (li < n);
         if(li < n)
           {
            m_htf[li].minutes   = mins[li];
            m_htf[li].periodSec = mins[li] * 60;
           }
        }
      return (n > 0);
     }

   //+---------------------------------------------------------------+
   //| Accès à l'anneau                                              |
   //+---------------------------------------------------------------+
   double            BarH(const int x) const { return m_h[x & LRL_RING_MASK]; }
   double            BarL(const int x) const { return m_l[x & LRL_RING_MASK]; }
   double            BarC(const int x) const { return m_c[x & LRL_RING_MASK]; }
   datetime          BarT(const int x) const { return m_t[x & LRL_RING_MASK]; }

   //+---------------------------------------------------------------+
   //| Heure de New York                                             |
   //+---------------------------------------------------------------+
   long              NthSundayUtc(const int year, const int mon, const int nth, const int hourUtc)
     {
      MqlDateTime s;
      ZeroMemory(s);
      s.year = year;
      s.mon  = mon;
      s.day  = 1;
      datetime first = StructToTime(s);
      MqlDateTime f;
      TimeToStruct(first, f);
      int firstSunday = 1 + (7 - f.day_of_week) % 7;
      int day = firstSunday + 7 * (nth - 1);
      return (long)first + (long)(day - 1) * 86400 + (long)hourUtc * 3600;
     }

   bool              IsUsDst(const long utc)
     {
      MqlDateTime s;
      TimeToStruct((datetime)utc, s);
      if(s.year != m_dstYear)
        {
         m_dstYear  = s.year;
         m_dstStart = NthSundayUtc(s.year, 3, 2, 7);   // 2e dimanche de mars, 02:00 EST
         m_dstEnd   = NthSundayUtc(s.year, 11, 1, 6);  // 1er dimanche de novembre, 02:00 EDT
        }
      return (utc >= m_dstStart && utc < m_dstEnd);
     }

   long              ServerToNy(const datetime t)
     {
      if(cfg.tzMode == LRL_TZ_SERVER_GMT)
        {
         long utc = (long)t - cfg.serverGmtSec;
         return utc - (IsUsDst(utc) ? 4 * 3600 : 5 * 3600);
        }
      return (long)t - cfg.serverMinusNySec;
     }

   int               NyMinute(const datetime t)
     {
      long ny  = ServerToNy(t);
      long sod = ny % 86400;
      if(sod < 0)
         sod += 86400;
      return (int)(sod / 60);
     }

   bool              InRange(const int m, const int s, const int e) const
     {
      if(s < e)
         return (m >= s && m < e);
      return (m >= s || m < e);
     }

   bool              InWindowMin(const int m) const
     {
      if(cfg.winStartMin == cfg.winEndMin)
         return true;
      return InRange(m, cfg.winStartMin, cfg.winEndMin);
     }

   bool              InFlatMin(const int m) const
     {
      if(!cfg.flatEnabled || cfg.flatStartMin == cfg.flatEndMin)
         return false;
      return InRange(m, cfg.flatStartMin, cfg.flatEndMin);
     }

   //+---------------------------------------------------------------+
   //| Événements                                                    |
   //+---------------------------------------------------------------+
   void              PushEvent(const LRLEvent &e)
     {
      if(m_evCount >= ArraySize(m_events))
         ArrayResize(m_events, m_evCount + 16);
      m_events[m_evCount] = e;
      m_evCount++;
     }

   //+---------------------------------------------------------------+
   //| Traitement d'une bougie de base clôturée                      |
   //+---------------------------------------------------------------+
   void              ProcessBar(const datetime t, const double o, const double h, const double l, const double c)
     {
      m_evCount = 0;
      CompactZones();

      m_bar++;
      int b = m_bar;
      int k = b & LRL_RING_MASK;
      m_t[k] = t;
      m_o[k] = o;
      m_h[k] = h;
      m_l[k] = l;
      m_c[k] = c;
      UpdateAtr(b, h, l, c);

      int  nyMin = NyMinute(t);
      bool flat  = InFlatMin(nyMin);
      bool inWin = InWindowMin(nyMin);

      //--- 1) trades book ouverts (bougies postérieures à l'entrée)
      ResolveBookTrades(b, t, o, h, l, flat);
      //--- 2) retests (état de fin de bougie précédente = ordre limite en attente)
      CheckRetests(b, t, h, l, flat, inWin);
      //--- 3) balayage des LRL actives
      CheckSweeps(b, t, h, l, c);
      //--- 4) timeframes supérieurs
      HtfLateCloses(b, t);
      UpdateLegExtremes(h, l);
      HtfAddBar(b, t, o, h, l, c);
      //--- 5) pivots -> swings -> ajustement des lignes
      DetectPivots(b);
      //--- 6) expiration des LRL
      CheckExpiry(b, t);
      //--- 7) biais, zone surveillée, setup armé pour la bougie suivante
      UpdateBias(b, c);
      SelectWatched(b, t);
      ComputeArmed(b);
     }

   //+---------------------------------------------------------------+
   void              UpdateAtr(const int b, const double h, const double l, const double c)
     {
      double tr = h - l;
      if(b > 0)
         tr = MathMax(h - l, MathMax(MathAbs(h - m_prevClose), MathAbs(l - m_prevClose)));
      m_prevClose = c;
      if(m_atrN < cfg.atrLen)
        {
         m_atrSum += tr;
         m_atrN++;
         m_atr = (m_atrN == cfg.atrLen) ? m_atrSum / cfg.atrLen : 0.0;
        }
      else
         m_atr = (m_atr * (cfg.atrLen - 1) + tr) / cfg.atrLen;
     }

   //+---------------------------------------------------------------+
   //| Modèle book : résolution conservatrice                        |
   //+---------------------------------------------------------------+
   void              ResolveBookTrades(const int b, const datetime t, const double o, const double h, const double l, const bool flat)
     {
      for(int i = ArraySize(m_open) - 1; i >= 0; i--)
        {
         if(m_open[i].entryBar >= b)
            continue;
         if(flat)
           {
            CloseTrade(i, b, t, o, LRL_EXIT_FLAT);
            continue;
           }
         if(m_open[i].dir < 0)
           {
            if(h >= m_open[i].stop)
               CloseTrade(i, b, t, m_open[i].stop, LRL_EXIT_STOP);
            else
               if(l <= m_open[i].target)
                  CloseTrade(i, b, t, m_open[i].target, LRL_EXIT_TARGET);
           }
         else
           {
            if(l <= m_open[i].stop)
               CloseTrade(i, b, t, m_open[i].stop, LRL_EXIT_STOP);
            else
               if(h >= m_open[i].target)
                  CloseTrade(i, b, t, m_open[i].target, LRL_EXIT_TARGET);
           }
        }
     }

   void              CloseTrade(const int idx, const int b, const datetime t, const double px, const int reason)
     {
      double r = 0.0;
      if(reason == LRL_EXIT_TARGET)
         r = cfg.rr;
      else
         if(reason == LRL_EXIT_STOP)
            r = -1.0;
         else
            if(m_open[idx].risk > 0.0)
               r = (m_open[idx].dir < 0 ? (m_open[idx].entry - px) : (px - m_open[idx].entry)) / m_open[idx].risk;

      m_open[idx].open       = false;
      m_open[idx].exitBar    = b;
      m_open[idx].exitTime   = t;
      m_open[idx].exitPrice  = px;
      m_open[idx].exitReason = reason;
      m_open[idx].r          = r;

      m_stats.trades++;
      if(r > 0.0)
         m_stats.wins++;
      else
         m_stats.losses++;
      m_stats.netR += r;
      if(m_open[idx].inWindow)
        {
         m_stats.inTrades++;
         if(r > 0.0)
            m_stats.inWins++;
         m_stats.inNetR += r;
        }
      else
        {
         m_stats.outTrades++;
         if(r > 0.0)
            m_stats.outWins++;
         m_stats.outNetR += r;
        }

      LRLEvent ev;
      ZeroMemory(ev);
      ev.type   = LRL_EV_TRADE_CLOSE;
      ev.side   = m_open[idx].dir;
      ev.id     = m_open[idx].zoneId;
      ev.tfMin  = m_open[idx].tfMin;
      ev.reason = reason;
      ev.t1     = m_open[idx].entryTime;
      ev.t2     = t;
      ev.p1     = m_open[idx].entry;
      ev.p2     = m_open[idx].stop;
      ev.p3     = m_open[idx].target;
      ev.p4     = px;
      ev.p5     = r;
      PushEvent(ev);

      int nc = ArraySize(m_closed);
      if(nc < LRL_MAX_CLOSED)
        {
         ArrayResize(m_closed, nc + 1, 1024);
         m_closed[nc] = m_open[idx];
        }
      int no = ArraySize(m_open);
      for(int j = idx; j < no - 1; j++)
         m_open[j] = m_open[j + 1];
      ArrayResize(m_open, no - 1, 16);
     }

   //+---------------------------------------------------------------+
   //| Retests                                                       |
   //+---------------------------------------------------------------+
   double            EntryPrice(const LRLZone &z) const
     {
      if(cfg.entryMode == LRL_ENTRY_EDGE)
         return (z.dir < 0) ? z.bottom : z.top;
      return 0.5 * (z.top + z.bottom);
     }

   void              CheckRetests(const int b, const datetime t, const double h, const double l, const bool flat, const bool inWin)
     {
      int n = ArraySize(m_zones);
      for(int i = 0; i < n; i++)
        {
         if(m_zones[i].dead || m_zones[i].used || !m_zones[i].inverted)
            continue;
         if(m_zones[i].invBar >= b)
            continue;
         double e = EntryPrice(m_zones[i]);
         bool touched = (m_zones[i].dir < 0) ? (h >= e) : (l <= e);
         if(!touched)
            continue;
         //--- premier retest : la zone est consommée, qu'elle soit tradée ou non
         m_zones[i].used = true;
         if(m_armed.valid && m_armed.zoneId == m_zones[i].id)
            TakeSetup(b, t, h, l, flat, inWin);
        }
     }

   void              TakeSetup(const int b, const datetime t, const double h, const double l, const bool flat, const bool inWin)
     {
      int reason = m_armed.block;
      if(flat)
         reason = LRL_SKIP_FLAT;
      else
         if(cfg.tradeOnlyInWindow && !inWin)
            reason = LRL_SKIP_WINDOW;

      if(reason != LRL_BLOCK_NONE)
        {
         if(reason == LRL_BLOCK_MINSTOP)
            m_stats.skipMinStop++;
         else
            if(reason == LRL_BLOCK_MAXSTOP)
               m_stats.skipMaxStop++;
            else
               if(reason == LRL_BLOCK_LRL)
                  m_stats.skipLrl++;
               else
                  if(reason == LRL_SKIP_WINDOW)
                     m_stats.skipWindow++;
                  else
                     if(reason == LRL_SKIP_FLAT)
                        m_stats.skipFlat++;
                     else
                        m_stats.skipInvalid++;
         LRLEvent sk;
         ZeroMemory(sk);
         sk.type   = LRL_EV_SETUP_SKIP;
         sk.side   = m_armed.dir;
         sk.id     = m_armed.zoneId;
         sk.tfMin  = m_armed.tfMin;
         sk.reason = reason;
         sk.t1     = t;
         sk.p1     = m_armed.entry;
         sk.p2     = m_armed.stop;
         sk.p3     = m_armed.target;
         sk.p4     = m_armed.risk;
         PushEvent(sk);
         return;
        }

      int n = ArraySize(m_open);
      ArrayResize(m_open, n + 1, 16);
      m_open[n].zoneId     = m_armed.zoneId;
      m_open[n].dir        = m_armed.dir;
      m_open[n].tfMin      = m_armed.tfMin;
      m_open[n].entry      = m_armed.entry;
      m_open[n].stop       = m_armed.stop;
      m_open[n].target     = m_armed.target;
      m_open[n].risk       = m_armed.risk;
      m_open[n].entryBar   = b;
      m_open[n].entryTime  = t;
      m_open[n].inWindow   = inWin;
      m_open[n].open       = true;
      m_open[n].exitBar    = -1;
      m_open[n].exitTime   = 0;
      m_open[n].exitPrice  = 0.0;
      m_open[n].exitReason = 0;
      m_open[n].r          = 0.0;

      LRLEvent ev;
      ZeroMemory(ev);
      ev.type  = LRL_EV_TRADE_OPEN;
      ev.side  = m_armed.dir;
      ev.id    = m_armed.zoneId;
      ev.tfMin = m_armed.tfMin;
      ev.n     = inWin ? 1 : 0;
      ev.t1    = t;
      ev.p1    = m_armed.entry;
      ev.p2    = m_armed.stop;
      ev.p3    = m_armed.target;
      ev.p4    = m_armed.risk;
      PushEvent(ev);

      //--- bougie d'entrée : seul le stop est vérifié
      if(m_armed.dir < 0 ? (h >= m_armed.stop) : (l <= m_armed.stop))
         CloseTrade(n, b, t, m_armed.stop, LRL_EXIT_STOP);
     }

   //+---------------------------------------------------------------+
   //| LRL : balayage / expiration / retrait                         |
   //+---------------------------------------------------------------+
   void              RetireLine(const int s, const int b, const datetime t, const int reason)
     {
      if(!m_lrl[s].active)
         return;
      m_lrl[s].active    = false;
      m_lrl[s].endBar    = b;
      m_lrl[s].endTime   = t;
      m_lrl[s].endPrice  = m_lrl[s].PriceAt(b);
      m_lrl[s].endReason = reason;

      LRLEvent ev;
      ZeroMemory(ev);
      ev.type   = LRL_EV_LRL_END;
      ev.side   = s;
      ev.id     = m_lrl[s].id;
      ev.reason = reason;
      ev.n      = m_lrl[s].touches;
      ev.t1     = m_lrl[s].firstTime;
      ev.p1     = m_lrl[s].PriceAt(m_lrl[s].firstBar);
      ev.t2     = t;
      ev.p2     = m_lrl[s].endPrice;
      PushEvent(ev);
     }

   void              CheckSweeps(const int b, const datetime t, const double h, const double l, const double c)
     {
      for(int s = 0; s < 2; s++)
        {
         if(!m_lrl[s].active || m_lrl[s].createdBar >= b)
            continue;
         double lp = m_lrl[s].PriceAt(b);
         bool swept = false;
         if(s == LRL_SIDE_LOW)
            swept = (cfg.sweepMode == LRL_SWEEP_CLOSE) ? (c < lp) : (l < lp);
         else
            swept = (cfg.sweepMode == LRL_SWEEP_CLOSE) ? (c > lp) : (h > lp);
         if(swept)
            RetireLine(s, b, t, LRL_END_SWEEP);
        }
     }

   void              CheckExpiry(const int b, const datetime t)
     {
      for(int s = 0; s < 2; s++)
         if(m_lrl[s].active && b - m_lrl[s].lastTouchBar > cfg.expireBars)
            RetireLine(s, b, t, LRL_END_EXPIRE);
     }

   //+---------------------------------------------------------------+
   //| Pivots confirmés                                              |
   //+---------------------------------------------------------------+
   void              DetectPivots(const int b)
     {
      int p = b - cfg.pivotRight;
      if(p - cfg.pivotLeft < 0)
         return;
      double hp = BarH(p);
      double lp = BarL(p);
      bool isHigh = true;
      bool isLow  = true;
      for(int k = 1; k <= cfg.pivotLeft; k++)
        {
         if(!(hp > BarH(p - k)))
            isHigh = false;
         if(!(lp < BarL(p - k)))
            isLow = false;
        }
      for(int k = 1; k <= cfg.pivotRight; k++)
        {
         if(!(hp >= BarH(p + k)))
            isHigh = false;
         if(!(lp <= BarL(p + k)))
            isLow = false;
        }
      if(isHigh)
        {
         AddSwing(LRL_SIDE_HIGH, p, BarT(p), hp);
         FitSide(LRL_SIDE_HIGH, b);
        }
      if(isLow)
        {
         AddSwing(LRL_SIDE_LOW, p, BarT(p), lp);
         FitSide(LRL_SIDE_LOW, b);
        }
     }

   void              AddSwing(const int side, const int bar, const datetime t, const double price)
     {
      if(side == LRL_SIDE_LOW)
        {
         int n = ArraySize(m_swLo);
         if(n >= cfg.maxSwings)
           {
            for(int i = 0; i < n - 1; i++)
               m_swLo[i] = m_swLo[i + 1];
            n--;
           }
         ArrayResize(m_swLo, n + 1, 32);
         m_swLo[n].bar   = bar;
         m_swLo[n].time  = t;
         m_swLo[n].price = price;
        }
      else
        {
         int n = ArraySize(m_swHi);
         if(n >= cfg.maxSwings)
           {
            for(int i = 0; i < n - 1; i++)
               m_swHi[i] = m_swHi[i + 1];
            n--;
           }
         ArrayResize(m_swHi, n + 1, 32);
         m_swHi[n].bar   = bar;
         m_swHi[n].time  = t;
         m_swHi[n].price = price;
        }
     }

   //+---------------------------------------------------------------+
   //| Ajustement LRL : toutes les paires de swings sont testées     |
   //+---------------------------------------------------------------+
   void              FitSide(const int side, const int b)
     {
      if(m_atr <= 0.0)
         return;
      int n = (side == LRL_SIDE_LOW) ? ArraySize(m_swLo) : ArraySize(m_swHi);
      if(n < cfg.minTouches)
         return;

      int      sb[];
      double   sp[];
      datetime st[];
      ArrayResize(sb, n);
      ArrayResize(sp, n);
      ArrayResize(st, n);
      for(int k = 0; k < n; k++)
        {
         if(side == LRL_SIDE_LOW)
           {
            sb[k] = m_swLo[k].bar;
            sp[k] = m_swLo[k].price;
            st[k] = m_swLo[k].time;
           }
         else
           {
            sb[k] = m_swHi[k].bar;
            sp[k] = m_swHi[k].price;
            st[k] = m_swHi[k].time;
           }
        }

      double tol    = cfg.touchTolAtr * m_atr;
      int    oldest = b - LRL_RING + 2;
      double cNow   = BarC(b);

      bool   found    = false;
      int    bTouches = 0;
      int    bFirst   = -1;
      int    bLast    = -1;
      int    bPairA   = -1;
      int    bPairB   = -1;
      int    bAnchorB = 0;
      double bAnchorP = 0.0;
      double bSlope   = 0.0;
      datetime bFirstT = 0;
      datetime bLastT  = 0;

      for(int i = 0; i < n - 1; i++)
        {
         if(sb[i] < oldest)
            continue;
         for(int j = i + 1; j < n; j++)
           {
            int bi = sb[i];
            int bj = sb[j];
            if(bj <= bi)
               continue;
            double slope = (sp[j] - sp[i]) / (double)(bj - bi);

            //--- touches (espacées) et cassure par un swing du côté opposé
            int    cnt     = 0;
            int    first   = -1;
            int    lastAcc = -1;
            int    firstK  = -1;
            int    lastK   = -1;
            bool   broken  = false;
            bool   offSet  = false;
            double off     = 0.0;
            for(int k = 0; k < n; k++)
              {
               if(sb[k] < oldest)
                  continue;
               double d = sp[k] - (sp[i] + slope * (double)(sb[k] - bi));
               if(MathAbs(d) <= tol)
                 {
                  if(first < 0 || sb[k] - lastAcc >= cfg.minSpacing)
                    {
                     cnt++;
                     lastAcc = sb[k];
                     lastK   = k;
                     if(first < 0)
                       {
                        first  = sb[k];
                        firstK = k;
                       }
                    }
                  if(!offSet || (side == LRL_SIDE_LOW ? (d < off) : (d > off)))
                    {
                     off    = d;
                     offSet = true;
                    }
                 }
               else
                  if(first >= 0 && ((side == LRL_SIDE_LOW && d < -tol) || (side == LRL_SIDE_HIGH && d > tol)))
                    {
                     broken = true;
                     break;
                    }
              }
            if(broken || cnt < cfg.minTouches)
               continue;
            if(b - lastAcc > cfg.expireBars)
               continue;
            //--- élagage : le candidat doit pouvoir battre le meilleur
            if(found)
              {
               if(cnt < bTouches)
                  continue;
               if(cnt == bTouches && lastAcc < bLast)
                  continue;
               if(cnt == bTouches && lastAcc == bLast && bj <= bPairB)
                  continue;
              }
            //--- propreté bougie par bougie depuis la première touche
            bool clean = true;
            for(int x = first; x <= b; x++)
              {
               double lpx = sp[i] + slope * (double)(x - bi);
               if(side == LRL_SIDE_LOW)
                 {
                  if(BarL(x) < lpx - tol)
                    {
                     clean = false;
                     break;
                    }
                 }
               else
                  if(BarH(x) > lpx + tol)
                    {
                     clean = false;
                     break;
                    }
              }
            if(!clean)
               continue;
            //--- ligne décalée sur la touche la plus extrême : le prix doit être du bon côté
            double anchorP = sp[i] + off;
            double lpNow   = anchorP + slope * (double)(b - bi);
            if(side == LRL_SIDE_LOW ? !(cNow > lpNow) : !(cNow < lpNow))
               continue;

            found    = true;
            bTouches = cnt;
            bFirst   = first;
            bLast    = lastAcc;
            bPairA   = bi;
            bPairB   = bj;
            bAnchorB = bi;
            bAnchorP = anchorP;
            bSlope   = slope;
            bFirstT  = st[firstK];
            bLastT   = st[lastK];
           }
        }
      if(!found)
         return;

      int s = side;
      bool extension = false;
      if(m_lrl[s].active)
        {
         double tolSame = cfg.tickSize * 0.5;
         bool same = (m_lrl[s].pairA == bPairA && m_lrl[s].pairB == bPairB && m_lrl[s].touches == bTouches &&
                      m_lrl[s].lastTouchBar == bLast && MathAbs(m_lrl[s].anchorPrice - bAnchorP) <= tolSame);
         if(same)
            return;
         bool better = (bTouches > m_lrl[s].touches) ||
                       (bTouches == m_lrl[s].touches && bLast > m_lrl[s].lastTouchBar);
         if(!better)
            return;
         extension = (m_lrl[s].firstBar == bFirst);
         RetireLine(s, b, BarT(b), LRL_END_REPLACED);
        }

      m_lrl[s].Reset();
      m_lineSeq++;
      m_lrl[s].active        = true;
      m_lrl[s].side          = s;
      m_lrl[s].id            = m_lineSeq;
      m_lrl[s].anchorBar     = bAnchorB;
      m_lrl[s].anchorPrice   = bAnchorP;
      m_lrl[s].slope         = bSlope;
      m_lrl[s].pairA         = bPairA;
      m_lrl[s].pairB         = bPairB;
      m_lrl[s].firstBar      = bFirst;
      m_lrl[s].firstTime     = bFirstT;
      m_lrl[s].lastTouchBar  = bLast;
      m_lrl[s].lastTouchTime = bLastT;
      m_lrl[s].touches       = bTouches;
      m_lrl[s].createdBar    = b;
      m_lrl[s].createdTime   = BarT(b);

      LRLEvent ev;
      ZeroMemory(ev);
      ev.type   = LRL_EV_LRL_NEW;
      ev.side   = s;
      ev.id     = m_lineSeq;
      ev.reason = extension ? 1 : 0;
      ev.n      = bTouches;
      ev.t1     = bFirstT;
      ev.p1     = m_lrl[s].PriceAt(bFirst);
      ev.t2     = BarT(b);
      ev.p2     = m_lrl[s].PriceAt(b);
      PushEvent(ev);
     }

   //+---------------------------------------------------------------+
   //| Timeframes supérieurs reconstruits depuis les bougies de base |
   //+---------------------------------------------------------------+
   long              BucketStart(const int li, const datetime t) const
     {
      long tt  = (long)t;
      long day = tt - (tt % 86400);
      long p   = (long)m_htf[li].periodSec;
      return day + ((tt - day) / p) * p;
     }

   void              HtfLateCloses(const int b, const datetime t)
     {
      //--- une bougie HTF dont la dernière bougie de base manque est clôturée
      //--- dès que la première bougie de la période suivante arrive
      for(int li = 0; li < m_htfCount; li++)
         if(m_htf[li].hasCur && BucketStart(li, t) != m_htf[li].curStart)
            CloseCandle(li, b, t);
     }

   void              HtfAddBar(const int b, const datetime t, const double o, const double h, const double l, const double c)
     {
      for(int li = 0; li < m_htfCount; li++)
        {
         long start = BucketStart(li, t);
         //--- la toute première bougie HTF doit être complète : on attend un début de période
         if(!m_htf[li].hasCur && m_htf[li].count == 0 && (long)t != start)
            continue;
         if(!m_htf[li].hasCur)
           {
            m_htf[li].hasCur   = true;
            m_htf[li].curStart = start;
            m_htf[li].o = o;
            m_htf[li].h = h;
            m_htf[li].l = l;
            m_htf[li].c = c;
           }
         else
           {
            if(h > m_htf[li].h)
               m_htf[li].h = h;
            if(l < m_htf[li].l)
               m_htf[li].l = l;
            m_htf[li].c = c;
           }
         //--- la bougie HTF se clôture sur la bougie de base dont la clôture = clôture HTF
         if((long)t + cfg.baseSeconds >= m_htf[li].curStart + m_htf[li].periodSec)
            CloseCandle(li, b, t);
        }
     }

   void              CloseCandle(const int li, const int b, const datetime t)
     {
      for(int k = 2; k > 0; k--)
        {
         m_htf[li].cO[k] = m_htf[li].cO[k - 1];
         m_htf[li].cH[k] = m_htf[li].cH[k - 1];
         m_htf[li].cL[k] = m_htf[li].cL[k - 1];
         m_htf[li].cC[k] = m_htf[li].cC[k - 1];
         m_htf[li].cT[k] = m_htf[li].cT[k - 1];
        }
      m_htf[li].cO[0] = m_htf[li].o;
      m_htf[li].cH[0] = m_htf[li].h;
      m_htf[li].cL[0] = m_htf[li].l;
      m_htf[li].cC[0] = m_htf[li].c;
      m_htf[li].cT[0] = (datetime)m_htf[li].curStart;
      if(m_htf[li].nClosed < 3)
         m_htf[li].nClosed++;
      m_htf[li].count++;
      m_htf[li].hasCur = false;
      OnHtfClose(li, b, t);
     }

   void              OnHtfClose(const int li, const int b, const datetime t)
     {
      double cl  = m_htf[li].cC[0];
      int    cnt = m_htf[li].count;
      int    n   = ArraySize(m_zones);
      //--- inversion / invalidation jugées sur la clôture de CE niveau
      for(int i = 0; i < n; i++)
        {
         if(m_zones[i].level != li || m_zones[i].dead || m_zones[i].used)
            continue;
         if(!m_zones[i].inverted)
           {
            if(cfg.maxZoneAge > 0 && cnt - m_zones[i].createdCandle > cfg.maxZoneAge)
              {
               m_zones[i].dead = true;
               continue;
              }
            double lvl = 0.0;
            if(cfg.invMode == LRL_INV_CLOSE_CE)
               lvl = 0.5 * (m_zones[i].top + m_zones[i].bottom);
            else
               lvl = (m_zones[i].dir < 0) ? m_zones[i].bottom : m_zones[i].top;
            bool inv = (m_zones[i].dir < 0) ? (cl < lvl) : (cl > lvl);
            if(inv)
              {
               m_zones[i].inverted  = true;
               m_zones[i].invBar    = b;
               m_zones[i].invTime   = t;
               m_zones[i].invCandle = cnt;
               LRLEvent ev;
               ZeroMemory(ev);
               ev.type  = LRL_EV_ZONE_INV;
               ev.side  = m_zones[i].dir;
               ev.id    = m_zones[i].id;
               ev.tfMin = m_zones[i].tfMin;
               ev.t1    = m_zones[i].t0;
               ev.t2    = t;
               ev.p1    = m_zones[i].top;
               ev.p2    = m_zones[i].bottom;
               ev.p3    = m_zones[i].legExt;
               PushEvent(ev);
              }
           }
         else
           {
            bool invalid = (m_zones[i].dir < 0) ? (cl > m_zones[i].top) : (cl < m_zones[i].bottom);
            if(invalid || (cfg.maxZoneAge > 0 && cnt - m_zones[i].invCandle > cfg.maxZoneAge))
               m_zones[i].dead = true;
           }
        }

      //--- nouveau FVG sur les 3 dernières bougies HTF clôturées
      if(m_htf[li].nClosed < 3)
         return;
      double minGap = MathMax(cfg.minGapTicks, 0.0) * cfg.tickSize;
      double h2 = m_htf[li].cH[2];
      double l2 = m_htf[li].cL[2];
      double h1 = m_htf[li].cH[1];
      double l1 = m_htf[li].cL[1];
      double h0 = m_htf[li].cH[0];
      double l0 = m_htf[li].cL[0];
      //--- FVG haussier : devient baissier (short) une fois inversé
      if(l0 > h2 && (l0 - h2) >= minGap)
         AddZone(li, -1, h2, l0, m_htf[li].cT[1], MathMax(h1, h0), b, cnt);
      //--- FVG baissier : devient haussier (long) une fois inversé
      if(h0 < l2 && (l2 - h0) >= minGap)
         AddZone(li, 1, h0, l2, m_htf[li].cT[1], MathMin(l1, l0), b, cnt);
     }

   void              AddZone(const int li, const int dir, const double bottom, const double top, const datetime t0,
                             const double legExt, const int b, const int candle)
     {
      int n = ArraySize(m_zones);
      ArrayResize(m_zones, n + 1, 256);
      m_zones[n].id            = (long)t0 * 16 + li * 2 + (dir > 0 ? 1 : 0);
      m_zones[n].level         = li;
      m_zones[n].tfMin         = m_htf[li].minutes;
      m_zones[n].dir           = dir;
      m_zones[n].top           = top;
      m_zones[n].bottom        = bottom;
      m_zones[n].t0            = t0;
      m_zones[n].createdBar    = b;
      m_zones[n].createdCandle = candle;
      m_zones[n].inverted      = false;
      m_zones[n].invBar        = -1;
      m_zones[n].invTime       = 0;
      m_zones[n].invCandle     = 0;
      m_zones[n].legExt        = legExt;
      m_zones[n].dead          = false;
      m_zones[n].used          = false;
     }

   void              UpdateLegExtremes(const double h, const double l)
     {
      int n = ArraySize(m_zones);
      for(int i = 0; i < n; i++)
        {
         if(m_zones[i].dead || m_zones[i].inverted)
            continue;
         if(m_zones[i].dir < 0)
           {
            if(h > m_zones[i].legExt)
               m_zones[i].legExt = h;
           }
         else
            if(l < m_zones[i].legExt)
               m_zones[i].legExt = l;
        }
     }

   void              CompactZones()
     {
      int n = ArraySize(m_zones);
      if(n == 0)
         return;
      //--- limite le nombre de FVG non inversés vivants (les plus anciens meurent)
      int live = 0;
      for(int i = 0; i < n; i++)
         if(!m_zones[i].dead && !m_zones[i].used && !m_zones[i].inverted)
            live++;
      for(int i = 0; i < n && live > LRL_MAX_LIVE_ZONES; i++)
         if(!m_zones[i].dead && !m_zones[i].used && !m_zones[i].inverted)
           {
            m_zones[i].dead = true;
            live--;
           }
      int w = 0;
      for(int i = 0; i < n; i++)
        {
         if(m_zones[i].dead || m_zones[i].used)
            continue;
         if(w != i)
            m_zones[w] = m_zones[i];
         w++;
        }
      if(w != n)
         ArrayResize(m_zones, w, 256);
      m_watchIdx = -1;
     }

   //+---------------------------------------------------------------+
   //| Biais, zone surveillée, setup armé                            |
   //+---------------------------------------------------------------+
   void              UpdateBias(const int b, const double c)
     {
      bool lo = m_lrl[LRL_SIDE_LOW].active;
      bool hi = m_lrl[LRL_SIDE_HIGH].active;
      int bias = 0;
      if(lo && !hi)
         bias = -1;
      else
         if(hi && !lo)
            bias = 1;
         else
            if(lo && hi)
              {
               if(m_lrl[LRL_SIDE_LOW].touches > m_lrl[LRL_SIDE_HIGH].touches)
                  bias = -1;
               else
                  if(m_lrl[LRL_SIDE_HIGH].touches > m_lrl[LRL_SIDE_LOW].touches)
                     bias = 1;
                  else
                    {
                     double dl = c - m_lrl[LRL_SIDE_LOW].PriceAt(b);
                     double dh = m_lrl[LRL_SIDE_HIGH].PriceAt(b) - c;
                     bias = (dl <= dh) ? -1 : 1;
                    }
              }
      m_bias = bias;
     }

   int               FindZone(const long id) const
     {
      int n = ArraySize(m_zones);
      for(int i = 0; i < n; i++)
         if(m_zones[i].id == id)
            return i;
      return -1;
     }

   void              SelectWatched(const int b, const datetime t)
     {
      int best = -1;
      if(m_bias != 0)
        {
         int n = ArraySize(m_zones);
         for(int i = 0; i < n; i++)
           {
            if(!m_zones[i].inverted || m_zones[i].dead || m_zones[i].used || m_zones[i].dir != m_bias)
               continue;
            if(best < 0 || m_zones[i].tfMin > m_zones[best].tfMin ||
               (m_zones[i].tfMin == m_zones[best].tfMin && m_zones[i].invBar > m_zones[best].invBar) ||
               (m_zones[i].tfMin == m_zones[best].tfMin && m_zones[i].invBar == m_zones[best].invBar && m_zones[i].id > m_zones[best].id))
               best = i;
           }
        }
      long newId = (best >= 0) ? m_zones[best].id : 0;
      if(newId != m_watchId)
        {
         if(m_watchId != 0)
           {
            int old = FindZone(m_watchId);
            LRLEvent ev;
            ZeroMemory(ev);
            ev.type   = LRL_EV_WATCH_END;
            ev.id     = m_watchId;
            ev.reason = (old >= 0 && m_zones[old].used) ? LRL_WATCH_USED : LRL_WATCH_LOST;
            if(old >= 0)
              {
               ev.side  = m_zones[old].dir;
               ev.tfMin = m_zones[old].tfMin;
               ev.p1    = m_zones[old].top;
               ev.p2    = m_zones[old].bottom;
               ev.t1    = m_zones[old].t0;
              }
            ev.t2 = t;
            PushEvent(ev);
           }
         if(newId != 0)
           {
            m_stats.armed++;
            LRLEvent ev2;
            ZeroMemory(ev2);
            ev2.type  = LRL_EV_WATCH_START;
            ev2.side  = m_zones[best].dir;
            ev2.id    = newId;
            ev2.tfMin = m_zones[best].tfMin;
            ev2.t1    = m_zones[best].t0;
            ev2.t2    = m_zones[best].invTime;
            ev2.p1    = m_zones[best].top;
            ev2.p2    = m_zones[best].bottom;
            ev2.p3    = EntryPrice(m_zones[best]);
            ev2.p4    = m_zones[best].legExt;
            PushEvent(ev2);
           }
        }
      m_watchIdx = best;
      m_watchId  = newId;
     }

   void              ComputeArmed(const int b)
     {
      m_armed.Reset();
      if(m_watchIdx < 0)
         return;
      int i = m_watchIdx;
      int dir = m_zones[i].dir;
      double e   = EntryPrice(m_zones[i]);
      double buf = cfg.stopBufferTicks * cfg.tickSize;
      double stop   = 0.0;
      double risk   = 0.0;
      double target = 0.0;
      if(dir < 0)
        {
         stop   = ((cfg.stopMode == LRL_STOP_LEG) ? m_zones[i].legExt : m_zones[i].top) + buf;
         risk   = stop - e;
         target = e - cfg.rr * risk;
        }
      else
        {
         stop   = ((cfg.stopMode == LRL_STOP_LEG) ? m_zones[i].legExt : m_zones[i].bottom) - buf;
         risk   = e - stop;
         target = e + cfg.rr * risk;
        }
      int side = (dir < 0) ? LRL_SIDE_LOW : LRL_SIDE_HIGH;
      double lp = m_lrl[side].active ? m_lrl[side].PriceAt(b + 1) : 0.0;

      int block = LRL_BLOCK_NONE;
      if(!(risk > 0.0))
         block = LRL_BLOCK_INVALID;
      else
         if(risk < cfg.minStop - 1e-9)
            block = LRL_BLOCK_MINSTOP;
         else
            if(cfg.maxStopAtr > 0.0 && risk > cfg.maxStopAtr * m_atr)
               block = LRL_BLOCK_MAXSTOP;
            else
               if(cfg.lrlBeyondTarget)
                 {
                  if(!m_lrl[side].active)
                     block = LRL_BLOCK_LRL;
                  else
                     if(dir < 0 ? !(lp < target) : !(lp > target))
                        block = LRL_BLOCK_LRL;
                 }

      m_armed.valid    = true;
      m_armed.zoneId   = m_zones[i].id;
      m_armed.dir      = dir;
      m_armed.tfMin    = m_zones[i].tfMin;
      m_armed.entry    = e;
      m_armed.stop     = stop;
      m_armed.target   = target;
      m_armed.risk     = risk;
      m_armed.lrlPrice = lp;
      m_armed.top      = m_zones[i].top;
      m_armed.bottom   = m_zones[i].bottom;
      m_armed.t0       = m_zones[i].t0;
      m_armed.invTime  = m_zones[i].invTime;
      m_armed.block    = block;
     }

   //+---------------------------------------------------------------+
   //| Accesseurs pour l'EA                                          |
   //+---------------------------------------------------------------+
   int               OpenTradeCount() const { return ArraySize(m_open); }
   int               ClosedTradeCount() const { return ArraySize(m_closed); }
   datetime          LastBarTime() const { return (m_bar >= 0) ? BarT(m_bar) : 0; }
   double            LinePriceNow(const int side) const { return m_lrl[side].active ? m_lrl[side].PriceAt(m_bar) : 0.0; }

   int               LiveInvertedZones(const int dir) const
     {
      int cnt = 0;
      int n = ArraySize(m_zones);
      for(int i = 0; i < n; i++)
         if(m_zones[i].inverted && !m_zones[i].dead && !m_zones[i].used && m_zones[i].dir == dir)
            cnt++;
      return cnt;
     }
  };

#endif // LRL_ENGINE_MQH
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                   OPR_Engine.mqh |
//|  Moteur de la stratégie OPR + FVG (modèle « London OPR »).       |
//|                                                                  |
//|  Reçoit les bougies M1 CLÔTURÉES une par une (ProcessBar) et     |
//|  orchestre les modules :                                         |
//|    1. horaires (OPR_Time)        5. contexte directionnel        |
//|    2. OPR (OPR_Ranges)           6. validation des entrées       |
//|    3. FVG (OPR_FVG)              7. modèle book (statistiques)   |
//|    4. FVG de référence (Asie M15, minuit M1)                     |
//|    + liquidité (OPR_Liquidity), journal (OPR_Journal).           |
//|                                                                  |
//|  Règles du modèle d'entrée (sources : PDF « London OPR Strategy »|
//|  et « Macro + breaker ») :                                       |
//|   a) biais lu à l'ouverture de la fenêtre (2:50 NY) : prix sous  |
//|      l'OPR Low -> vente, au-dessus de l'OPR High -> achat ; dans |
//|      l'OPR -> attente d'une clôture hors de l'OPR ;              |
//|   b) dans la fenêtre, une liquidité doit d'abord être prise      |
//|      (au-dessus pour une vente, en dessous pour un achat) ;      |
//|   c) puis un FVG dans le sens du biais (déplacement) formé dans  |
//|      une macro -> ordre limite au bord du FVG ;                  |
//|   d) stop au-delà du swing (extrême depuis la prise de           |
//|      liquidité) ; cible = déviation standard k de l'OPR ;        |
//|   e) 1 macro = 1 trade ; cible atteinte avant l'entrée -> pas de |
//|      trade ; fin de fenêtre -> ordre annulé.                     |
//|  Aucune décision ne s'appuie sur une bougie non clôturée.        |
//+------------------------------------------------------------------+
#ifndef OPR_ENGINE_MQH
#define OPR_ENGINE_MQH

#include "OPR_Config.mqh"
#include "OPR_Time.mqh"
#include "OPR_Candles.mqh"
#include "OPR_FVG.mqh"
#include "OPR_Ranges.mqh"
#include "OPR_Liquidity.mqh"
#include "OPR_Journal.mqh"

//--- contexte du prix par rapport à un OPR
#define CTX_NA      0
#define CTX_ABOVE   1
#define CTX_INSIDE  2
#define CTX_BELOW   3

//--- états du modèle d'entrée
#define SU_OFF        0   // pas de modèle pour cet OPR
#define SU_IDLE       1   // avant la fenêtre
#define SU_WAIT_BIAS  2   // prix dans l'OPR : attente d'une clôture hors de l'OPR
#define SU_WAIT_SWEEP 3   // attente d'une prise de liquidité
#define SU_WAIT_FVG   4   // attente du FVG d'entrée
#define SU_ARMED      5   // ordre limite en attente
#define SU_IN_TRADE   6
#define SU_DONE       7   // plus rien aujourd'hui

#define BK_EXIT_TP  1
#define BK_EXIT_SL  2

#define OPR_MAX_REASON 20

struct OSetup
  {
   int               day;
   int               state;
   int               dir;
   bool              consol;
   bool              biasDone;
   bool              windowOpen;
   bool              windowClosed;
   int               macroOpen;
   bool              macroUsed[OPR_MAX_MACROS];
   long              winS;
   long              winE;
   long              macroS[OPR_MAX_MACROS];
   long              macroE[OPR_MAX_MACROS];
   long              sweepT;
   double            sweepLevel;
   int               sweepSrc;
   double            extreme;
   long              setupId;
   long              fvgId;
   double            fvgLo;
   double            fvgHi;
   double            entry;
   double            sl;
   double            tp;
   double            risk;
   long              armedT;
   int               armedMacro;
   int               trades;
   double            winHigh;
   double            winLow;
   int               doneReason;
  };

struct OBookTrade
  {
   long              setupId;
   int               slot;
   int               dir;
   int               macro;
   double            entry;
   double            sl;
   double            tp;
   double            risk;
   long              entryT;
   datetime          entrySrv;
   bool              open;
   long              exitT;
   datetime          exitSrv;
   double            exitPx;
   int               exitReason;
   double            r;
  };

struct OStats
  {
   int               days;
   int               trades;
   int               wins;
   int               losses;
   double            netR;
   int               armed;
   int               sweeps;
   int               candidates;
   int               biasBuy;
   int               biasSell;
   int               biasConsol;
   int               asiaFvgDays;
   int               rejected[OPR_MAX_REASON];

   void              Reset()
     {
      days = 0; trades = 0; wins = 0; losses = 0; netR = 0.0; armed = 0; sweeps = 0; candidates = 0;
      biasBuy = 0; biasSell = 0; biasConsol = 0; asiaFvgDays = 0;
      for(int i = 0; i < OPR_MAX_REASON; i++)
         rejected[i] = 0;
     }
  };

class COprEngine
  {
public:
   OPRConfig         cfg;
   COprTime          tm;
   CJournal          jr;
   CCandleAgg        m_m1;
   CCandleAgg        m_m5;
   CCandleAgg        m_m15;
   CFvgBook          fvgs;
   CLiquidity        liq;
   CRangeCalc        opr[OPR_MAX_SLOTS];
   CRangeCalc        asia;
   OSetup            su[OPR_MAX_SLOTS];
   int               ctx[OPR_MAX_SLOTS];
   OBookTrade        m_open[];
   OBookTrade        m_closed[];
   OStats            stats;
   string            slotName[OPR_MAX_SLOTS];
   bool              logContext;
   bool              logAllFvg;

   int               m_day;
   long              m_firstT;
   long              m_lastT;
   datetime          m_lastSrv;
   long              m_srvOffset;   // heure stratégie - heure serveur
   double            m_prevClose;
   long              m_asiaFvgId;
   bool              m_asiaDone;
   long              m_midFvgId;
   bool              m_midDone;
   bool              m_inObs;
   bool              m_inLondon;
   int               m_tradesToday;
   int               m_newEntryFvg[];
   int               m_newEntryCount;
   int               m_bars;

                     COprEngine() { m_day = 0; m_firstT = 0; m_bars = 0; logContext = true; logAllFvg = false; }

   //+---------------------------------------------------------------+
   bool              Init(const OPRConfig &c)
     {
      cfg = c;
      if(cfg.tickSize <= 0.0)
         cfg.tickSize = 0.00001;
      tm.Configure(cfg.stratTz, cfg.serverMode, cfg.serverGmtSec, cfg.dayStartMin);
      m_m1.Init(60);
      m_m5.Init(300);
      m_m15.Init(900);
      fvgs.Reset();
      liq.Reset();
      for(int s = 0; s < OPR_MAX_SLOTS; s++)
        {
         opr[s].Init(cfg.slots[s].calc);
         ctx[s] = CTX_NA;
         ResetSetup(s, 0);
         if(StringLen(slotName[s]) == 0)
            slotName[s] = "OPR " + IntegerToString(s + 1);
        }
      asia.Init(cfg.asia);
      ArrayResize(m_open, 0, 8);
      ArrayResize(m_closed, 0, 256);
      ArrayResize(m_newEntryFvg, 0, 8);
      stats.Reset();
      jr.Clear();
      m_day = 0;
      m_firstT = 0;
      m_lastT = 0;
      m_lastSrv = 0;
      m_srvOffset = 0;
      m_prevClose = 0.0;
      m_asiaFvgId = 0;
      m_asiaDone = false;
      m_midFvgId = 0;
      m_midDone = false;
      m_inObs = false;
      m_inLondon = false;
      m_tradesToday = 0;
      m_newEntryCount = 0;
      m_bars = 0;
      return true;
     }

   void              ResetSetup(const int s, const int day)
     {
      su[s].day          = day;
      su[s].state        = cfg.slots[s].tradeEnabled ? SU_IDLE : SU_OFF;
      su[s].dir          = 0;
      su[s].consol       = false;
      su[s].biasDone     = false;
      su[s].windowOpen   = false;
      su[s].windowClosed = false;
      su[s].macroOpen    = -1;
      for(int i = 0; i < OPR_MAX_MACROS; i++)
        {
         su[s].macroUsed[i] = false;
         su[s].macroS[i]    = 0;
         su[s].macroE[i]    = 0;
        }
      su[s].winS       = 0;
      su[s].winE       = 0;
      su[s].sweepT     = 0;
      su[s].sweepLevel = 0.0;
      su[s].sweepSrc   = 0;
      su[s].extreme    = 0.0;
      su[s].setupId    = 0;
      su[s].fvgId      = 0;
      su[s].fvgLo      = 0.0;
      su[s].fvgHi      = 0.0;
      su[s].entry      = 0.0;
      su[s].sl         = 0.0;
      su[s].tp         = 0.0;
      su[s].risk       = 0.0;
      su[s].armedT     = 0;
      su[s].armedMacro = -1;
      su[s].trades     = 0;
      su[s].winHigh    = 0.0;
      su[s].winLow     = 0.0;
      su[s].doneReason = R_NONE;
      if(day != 0 && cfg.slots[s].tradeEnabled)
        {
         long a = 0, b = 0;
         if(tm.RangeAbs(day, cfg.slots[s].window, a, b))
           {
            su[s].winS = a;
            su[s].winE = b;
           }
         for(int i = 0; i < cfg.slots[s].macroCount && i < OPR_MAX_MACROS; i++)
            if(tm.RangeAbs(day, cfg.slots[s].macros[i], a, b))
              {
               su[s].macroS[i] = a;
               su[s].macroE[i] = b;
              }
        }
     }

   //--- raccourci de journalisation
   void              Log(const int code, const int slot, const int dir, const int reason, const int aux, const long id,
                         const double p1, const double p2, const double p3, const double p4)
     {
      jr.Add(code, slot, dir, reason, aux, id, m_lastT, m_lastSrv, p1, p2, p3, p4);
     }

   void              Reject(const int code, const int s, const int dir, const int reason, const long id)
     {
      if(reason >= 0 && reason < OPR_MAX_REASON)
         stats.rejected[reason]++;
      Log(code, s, dir, reason, 0, id, 0.0, 0.0, 0.0, 0.0);
     }

   //+---------------------------------------------------------------+
   //| Traitement d'une bougie M1 clôturée (srv = ouverture serveur) |
   //+---------------------------------------------------------------+
   void              ProcessBar(const datetime srv, const double o, const double h, const double l, const double c)
     {
      jr.Clear();
      long st = tm.StratTime(srv);
      m_lastT       = st;
      m_lastSrv     = srv;
      m_srvOffset   = st - (long)srv;
      if(m_firstT == 0)
         m_firstT = st;
      m_bars++;
      int day = tm.SessionDay(st);
      if(day != m_day)
         NewDay(day, st);

      //--- 1) modèle book : exécution / annulation / sortie avec cette bougie
      BookStep(st, srv, h, l);

      //--- 2) OPR et plage asiatique
      for(int s = 0; s < OPR_MAX_SLOTS; s++)
        {
         int ev = opr[s].Update(st, h, l, OPR_BASE_SEC, m_firstT);
         if(ev == OPR_RG_EV_BUILDING)
            Log(J_OPR_BUILDING, s, 0, R_NONE, 0, 0, 0.0, 0.0, 0.0, 0.0);
         else
            if(ev == OPR_RG_EV_FINAL)
              {
               int stt = opr[s].m_st.status;
               int code = (stt == OPR_ST_FINAL) ? J_OPR_FINAL : (stt == OPR_ST_INCOMPLETE ? J_OPR_INCOMPLETE : J_OPR_NODATA);
               Log(code, s, 0, R_NONE, 0, 0, opr[s].m_st.high, opr[s].m_st.low, 0.0, 0.0);
              }
        }
      int aev = asia.Update(st, h, l, OPR_BASE_SEC, m_firstT);
      if(aev == OPR_RG_EV_FINAL && asia.IsFinal())
        {
         Log(J_ASIA_FINAL, -1, 0, R_NONE, 0, 0, asia.m_st.high, asia.m_st.low, 0.0, 0.0);
         if(cfg.liqAsia)
           {
            liq.AddLevel(1, LIQ_SRC_ASIA, asia.m_st.high, asia.m_st.highT, asia.m_st.finalT);
            liq.AddLevel(-1, LIQ_SRC_ASIA, asia.m_st.low, asia.m_st.lowT, asia.m_st.finalT);
           }
        }

      //--- 3) bougies clôturées : statuts et détection des FVG, swings de liquidité
      m_newEntryCount = 0;
      m_m1.Add(st, srv, o, h, l, c, OPR_BASE_SEC);
      OnAggClosed(m_m1);
      if(cfg.entryTfMin == 5)
        {
         m_m5.Add(st, srv, o, h, l, c, OPR_BASE_SEC);
         OnAggClosed(m_m5);
        }
      m_m15.Add(st, srv, o, h, l, c, OPR_BASE_SEC);
      OnAggClosed(m_m15);

      //--- 4) prises de liquidité par cette bougie
      liq.OnBar(st, h, l);

      //--- 5) contexte directionnel par OPR finalisé
      UpdateContext(c);

      //--- 6) fenêtres d'information
      InfoWindows(st);

      //--- 7) modèle d'entrée
      for(int s = 0; s < OPR_MAX_SLOTS; s++)
         if(cfg.slots[s].tradeEnabled)
            SetupStep(s, st, o, h, l, c);

      m_prevClose = c;
     }

   //+---------------------------------------------------------------+
   void              NewDay(const int day, const long st)
     {
      //--- clôture propre de la journée précédente
      for(int s = 0; s < OPR_MAX_SLOTS; s++)
        {
         if(su[s].state == SU_ARMED)
           {
            Reject(J_SETUP_CANCELLED, s, su[s].dir, R_WINDOW_END, su[s].setupId);
            su[s].state = SU_DONE;
           }
        }
      m_day = day;
      stats.days++;
      Log(J_DAY_START, -1, 0, R_NONE, 0, day, 0.0, 0.0, 0.0, 0.0);
      fvgs.ExpireAll(st);
      liq.Reset();
      for(int s = 0; s < OPR_MAX_SLOTS; s++)
        {
         opr[s].NewDay(tm, day, m_srvOffset);
         ctx[s] = CTX_NA;
         ResetSetup(s, day);
        }
      asia.NewDay(tm, day, m_srvOffset);
      m_asiaFvgId   = 0;
      m_asiaDone    = !cfg.asia.valid;
      m_midFvgId    = 0;
      m_midDone     = !(cfg.slots[0].calc.valid && cfg.london.valid);
      m_tradesToday = 0;
     }

   //+---------------------------------------------------------------+
   //| Bougies clôturées d'un agrégateur                             |
   //+---------------------------------------------------------------+
   void              OnAggClosed(const CCandleAgg &agg)
     {
      int tf = agg.PeriodMin();
      for(int k = 0; k < agg.m_nClosed; k++)
        {
         OCandle cd;
         cd = agg.m_closed[k];
         long closeT = cd.t + agg.m_period;
         //--- statuts des FVG de ce timeframe
         fvgs.OnCandle(tf, cd, closeT);
         for(int j = 0; j < fvgs.m_chgCount; j++)
           {
            int idx = fvgs.m_chgIdx[j];
            if(fvgs.m_list[idx].role != FVG_ROLE_NONE)
               Log(J_FVG_STATUS, fvgs.m_list[idx].slot, fvgs.m_list[idx].dir, R_NONE, tf * 10 + fvgs.m_list[idx].status,
                   fvgs.m_list[idx].id, fvgs.m_list[idx].hi, fvgs.m_list[idx].lo, 0.0, 0.0);
           }
         //--- détection (seule la dernière bougie clôturée peut être c3)
         if(k == agg.m_nClosed - 1)
           {
            int fi = fvgs.DetectOnClose(agg, 0.0, m_day);
            if(fi >= 0)
               OnNewFvg(fi, tf);
           }
         //--- swings de liquidité
         if(k == agg.m_nClosed - 1)
           {
            if(tf == 1 && cfg.liqM1)
               liq.OnCandle(agg, cfg.liqPivotM1, LIQ_SRC_M1);
            if(tf == 15 && cfg.liqM15)
               liq.OnCandle(agg, cfg.liqPivotM15, LIQ_SRC_M15);
           }
         //--- fin de la recherche du FVG asiatique
         if(tf == 15 && !m_asiaDone && asia.m_st.endT > 0)
           {
            long lastC3 = (cfg.asiaRule == OPR_ASIA_C2_IN_RANGE) ? asia.m_st.endT : asia.m_st.endT - 900;
            if(cd.t >= lastC3)
              {
               m_asiaDone = true;
               if(m_asiaFvgId == 0)
                  Log(J_ASIA_FVG_NONE, -1, 0, R_NONE, 0, 0, 0.0, 0.0, 0.0, 0.0);
              }
           }
        }
     }

   void              OnNewFvg(const int fi, const int tf)
     {
      double size = fvgs.m_list[fi].hi - fvgs.m_list[fi].lo;
      //--- premier FVG M15 de la plage asiatique (référence, jamais remplacé)
      if(tf == 15 && !m_asiaDone && m_asiaFvgId == 0 && asia.m_st.endT > 0 &&
         size >= cfg.asiaMinGapTicks * cfg.tickSize - 1e-9)
        {
         long as = asia.m_st.startT;
         long ae = asia.m_st.endT;
         bool in = false;
         if(cfg.asiaRule == OPR_ASIA_C2_IN_RANGE)
            in = (fvgs.m_list[fi].c2T >= as && fvgs.m_list[fi].c2T < ae);
         else
            if(cfg.asiaRule == OPR_ASIA_ALL_IN_RANGE)
               in = (fvgs.m_list[fi].c1T >= as && fvgs.m_list[fi].formedT <= ae);
            else
               in = (fvgs.m_list[fi].c3T >= as && fvgs.m_list[fi].formedT <= ae);
         if(in)
           {
            fvgs.m_list[fi].role = FVG_ROLE_ASIA;
            m_asiaFvgId = fvgs.m_list[fi].id;
            m_asiaDone = true;
            stats.asiaFvgDays++;
            Log(J_ASIA_FVG, -1, fvgs.m_list[fi].dir, R_NONE, 15, m_asiaFvgId, fvgs.m_list[fi].hi, fvgs.m_list[fi].lo, 0.0, 0.0);
           }
        }
      //--- FPFVG M1 de minuit (référence)
      if(tf == 1 && !m_midDone && m_midFvgId == 0)
        {
         long mid = tm.SessionAbs(m_day, cfg.slots[0].calc.startMin);
         long lend = 0, lstart = 0;
         tm.RangeAbs(m_day, cfg.london, lstart, lend);
         if(fvgs.m_list[fi].c2T >= mid && fvgs.m_list[fi].c2T < lend &&
            size >= cfg.midnightMinGapTicks * cfg.tickSize - 1e-9)
           {
            fvgs.m_list[fi].role = FVG_ROLE_MIDNIGHT;
            m_midFvgId = fvgs.m_list[fi].id;
            m_midDone = true;
            Log(J_MIDNIGHT_FVG, -1, fvgs.m_list[fi].dir, R_NONE, 1, m_midFvgId, fvgs.m_list[fi].hi, fvgs.m_list[fi].lo, 0.0, 0.0);
           }
        }
      //--- FVG du timeframe d'entrée : candidats potentiels du modèle
      if(tf == cfg.entryTfMin)
        {
         if(m_newEntryCount >= ArraySize(m_newEntryFvg))
            ArrayResize(m_newEntryFvg, m_newEntryCount + 4);
         m_newEntryFvg[m_newEntryCount] = fi;
         m_newEntryCount++;
        }
      bool inWindow = false;
      for(int s = 0; s < OPR_MAX_SLOTS; s++)
         if(su[s].windowOpen && !su[s].windowClosed)
            inWindow = true;
      if(tf == 15 || logAllFvg || (tf == cfg.entryTfMin && inWindow))
         Log(J_FVG_DETECTED, -1, fvgs.m_list[fi].dir, R_NONE, tf, fvgs.m_list[fi].id, fvgs.m_list[fi].hi, fvgs.m_list[fi].lo, 0.0, 0.0);
     }

   //+---------------------------------------------------------------+
   //| Module 5 : contexte du prix par rapport à chaque OPR          |
   //+---------------------------------------------------------------+
   int               ContextOf(const int s, const double price) const
     {
      if(opr[s].m_st.status != OPR_ST_FINAL)
         return CTX_NA;
      if(price > opr[s].m_st.high)
         return CTX_ABOVE;
      if(price < opr[s].m_st.low)
         return CTX_BELOW;
      return CTX_INSIDE;
     }

   void              UpdateContext(const double c)
     {
      for(int s = 0; s < OPR_MAX_SLOTS; s++)
        {
         int nc = ContextOf(s, c);
         if(nc == ctx[s])
            continue;
         ctx[s] = nc;
         if(!logContext || nc == CTX_NA)
            continue;
         int code = (nc == CTX_ABOVE) ? J_CTX_ABOVE : (nc == CTX_BELOW ? J_CTX_BELOW : J_CTX_INSIDE);
         Log(code, s, 0, R_NONE, 0, 0, opr[s].m_st.high, opr[s].m_st.low, c, 0.0);
        }
     }

   void              InfoWindows(const long st)
     {
      int m = tm.MinuteOfDay(st);
      bool inObs = cfg.observe.Contains(m);
      if(inObs != m_inObs)
        {
         m_inObs = inObs;
         Log(inObs ? J_OBS_OPEN : J_OBS_CLOSE, -1, 0, R_NONE, 0, 0, 0.0, 0.0, 0.0, 0.0);
        }
      bool inLon = cfg.london.Contains(m);
      if(inLon != m_inLondon)
        {
         m_inLondon = inLon;
         Log(J_SESSION_INFO, -1, 0, R_NONE, inLon ? 1 : 0, 0, 0.0, 0.0, 0.0, 0.0);
        }
     }

   //+---------------------------------------------------------------+
   //| Module 6 : validation des conditions d'entrée                 |
   //+---------------------------------------------------------------+
   int               MacroAt(const int s, const long t) const
     {
      for(int i = 0; i < cfg.slots[s].macroCount && i < OPR_MAX_MACROS; i++)
         if(t >= su[s].macroS[i] && t < su[s].macroE[i])
            return i;
      return -1;
     }

   void              SetBias(const int s, const int dir, const double price, const bool breakout)
     {
      su[s].dir = dir;
      if(dir > 0)
         stats.biasBuy++;
      else
         stats.biasSell++;
      Log(breakout ? J_BIAS_BREAKOUT : J_BIAS, s, dir, R_NONE, 0, 0, price, opr[s].m_st.high, opr[s].m_st.low, 0.0);
     }

   void              SetupStep(const int s, const long st, const double o, const double h, const double l, const double c)
     {
      if(su[s].state == SU_OFF || su[s].winS == 0)
         return;
      //--- a) biais à l'ouverture de la fenêtre (prix à la clôture de la bougie qui se termine à l'ouverture)
      if(!su[s].biasDone && st + OPR_BASE_SEC >= su[s].winS && st < su[s].winE)
        {
         su[s].biasDone = true;
         double price = (st + OPR_BASE_SEC == su[s].winS) ? c : o;
         if(opr[s].m_st.status != OPR_ST_FINAL)
           {
            su[s].state = SU_DONE;
            su[s].doneReason = R_NO_OPR;
            Reject(J_ENTRY_REJECTED, s, 0, R_NO_OPR, 0);
           }
         else
            if(price > opr[s].m_st.high)
              {
               SetBias(s, 1, price, false);
               su[s].state = SU_WAIT_SWEEP;
              }
            else
               if(price < opr[s].m_st.low)
                 {
                  SetBias(s, -1, price, false);
                  su[s].state = SU_WAIT_SWEEP;
                 }
               else
                 {
                  su[s].consol = true;
                  su[s].state  = SU_WAIT_BIAS;
                  stats.biasConsol++;
                  Log(J_BIAS_CONSOL, s, 0, R_NONE, 0, 0, price, opr[s].m_st.high, opr[s].m_st.low, 0.0);
                 }
        }
      //--- ouverture de la fenêtre
      if(!su[s].windowOpen && st >= su[s].winS && st < su[s].winE)
        {
         su[s].windowOpen = true;
         su[s].winHigh = h;
         su[s].winLow  = l;
         Log(J_WINDOW_OPEN, s, 0, R_NONE, 0, 0, 0.0, 0.0, 0.0, 0.0);
        }
      if(!su[s].windowOpen || su[s].windowClosed)
         return;

      bool inWin = (st < su[s].winE);
      if(inWin)
        {
         if(h > su[s].winHigh)
            su[s].winHigh = h;
         if(l < su[s].winLow)
            su[s].winLow = l;
         //--- macros
         int mi = MacroAt(s, st);
         if(mi != su[s].macroOpen)
           {
            if(su[s].macroOpen >= 0)
               Log(J_MACRO_CLOSE, s, 0, R_NONE, su[s].macroOpen, 0, 0.0, 0.0, 0.0, 0.0);
            if(mi >= 0)
               Log(J_MACRO_OPEN, s, 0, R_NONE, mi, 0, 0.0, 0.0, 0.0, 0.0);
            su[s].macroOpen = mi;
           }
         StepState(s, st, h, l, c);
        }

      //--- fin de fenêtre (y compris clôture tardive si des bougies manquent)
      if(st + OPR_BASE_SEC >= su[s].winE)
        {
         if(su[s].macroOpen >= 0)
           {
            Log(J_MACRO_CLOSE, s, 0, R_NONE, su[s].macroOpen, 0, 0.0, 0.0, 0.0, 0.0);
            su[s].macroOpen = -1;
           }
         if(su[s].state == SU_ARMED && st + OPR_BASE_SEC >= su[s].winE + (long)cfg.graceMin * 60)
           {
            Reject(J_SETUP_CANCELLED, s, su[s].dir, R_WINDOW_END, su[s].setupId);
            su[s].state = SU_DONE;
           }
         if(su[s].state != SU_ARMED)
           {
            su[s].windowClosed = true;
            if(su[s].state != SU_IN_TRADE)
               su[s].state = SU_DONE;
            Log(J_WINDOW_CLOSE, s, 0, R_NONE, 0, 0, 0.0, 0.0, 0.0, 0.0);
           }
        }
     }

   void              StepState(const int s, const long st, const double h, const double l, const double c)
     {
      int dir = su[s].dir;
      //--- prix dans l'OPR : attente d'une clôture d'un côté ou de l'autre (aucune direction forcée)
      if(su[s].state == SU_WAIT_BIAS)
        {
         int nd = 0;
         if(c > opr[s].m_st.high)
            nd = 1;
         else
            if(c < opr[s].m_st.low)
               nd = -1;
         if(nd == 0)
            return;
         SetBias(s, nd, c, true);
         dir = nd;
         if(cfg.consolRequireSweep)
           {
            su[s].state = SU_WAIT_SWEEP;
            return;
           }
         //--- sans prise de liquidité exigée : le swing de référence part de la bougie de cassure
         su[s].sweepT   = st;
         su[s].sweepSrc = 0;
         su[s].extreme  = (dir < 0) ? h : l;
         su[s].state    = SU_WAIT_FVG;
        }

      //--- b) prise de liquidité du côté opposé au trade
      if(su[s].state == SU_WAIT_SWEEP)
        {
         int best = -1;
         for(int k = 0; k < liq.m_sweepCount; k++)
           {
            int pi = liq.m_sweepIdx[k];
            if(liq.m_pools[pi].side != -dir)
               continue;
            if(best < 0 || (dir < 0 ? liq.m_pools[pi].level > liq.m_pools[best].level : liq.m_pools[pi].level < liq.m_pools[best].level))
               best = pi;
           }
         if(best < 0)
           {
            //--- un FVG dans le sens du biais sans prise de liquidité préalable : confirmation manquante
            for(int k = 0; k < m_newEntryCount; k++)
              {
               int fi = m_newEntryFvg[k];
               if(fvgs.m_list[fi].dir == dir)
                  Reject(J_FVG_IGNORED, s, dir, R_NO_SWEEP, fvgs.m_list[fi].id);
              }
            return;
           }
         su[s].sweepT     = st;
         su[s].sweepLevel = liq.m_pools[best].level;
         su[s].sweepSrc   = liq.m_pools[best].src;
         su[s].extreme    = (dir < 0) ? h : l;
         su[s].state      = SU_WAIT_FVG;
         stats.sweeps++;
         Log(J_SWEEP, s, dir, R_NONE, su[s].sweepSrc, 0, su[s].sweepLevel, 0.0, 0.0, 0.0);
         return;   // le FVG doit commencer à partir de la bougie de prise de liquidité : il ne peut pas se clôturer sur celle-ci
        }

      //--- c) FVG d'entrée après la prise de liquidité
      if(su[s].state == SU_WAIT_FVG)
        {
         if(dir < 0 && h > su[s].extreme)
            su[s].extreme = h;
         if(dir > 0 && l < su[s].extreme)
            su[s].extreme = l;
         for(int k = 0; k < m_newEntryCount; k++)
           {
            int fi = m_newEntryFvg[k];
            if(fvgs.m_list[fi].dir != dir)
               continue;
            long period = (long)cfg.entryTfMin * 60;
            if(fvgs.m_list[fi].c1T + period <= su[s].sweepT)
               continue;
            if(fvgs.m_list[fi].hi - fvgs.m_list[fi].lo < cfg.minFvgTicks * cfg.tickSize - 1e-9)
               continue;
            stats.candidates++;
            Log(J_FVG_CANDIDATE, s, dir, R_NONE, cfg.entryTfMin, fvgs.m_list[fi].id, fvgs.m_list[fi].hi, fvgs.m_list[fi].lo, 0.0, 0.0);
            if(TryArm(s, fi, st))
               return;
            if(su[s].state != SU_WAIT_FVG)
               return;
           }
         return;
        }

      //--- setup armé : invalidation du FVG avant l'exécution
      if(su[s].state == SU_ARMED)
        {
         int fi = fvgs.Find(su[s].fvgId);
         if(fi >= 0 && fvgs.m_list[fi].status == FVG_INVALIDATED)
           {
            Reject(J_SETUP_CANCELLED, s, dir, R_FVG_INVALID, su[s].setupId);
            su[s].state = SU_WAIT_SWEEP;
           }
        }
     }

   //--- d) calcul et validation des niveaux ; arme le setup si tout est conforme
   bool              TryArm(const int s, const int fi, const long st)
     {
      int dir = su[s].dir;
      long fid = fvgs.m_list[fi].id;
      int mi = MacroAt(s, fvgs.m_list[fi].c3T);
      if(cfg.requireMacro && mi < 0)
        {
         Reject(J_FVG_IGNORED, s, dir, R_OUTSIDE_MACRO, fid);
         return false;
        }
      if(cfg.oneTradePerMacro && mi >= 0 && su[s].macroUsed[mi])
        {
         Reject(J_FVG_IGNORED, s, dir, R_MACRO_USED, fid);
         return false;
        }
      if(ArraySize(m_open) >= cfg.maxOpenTrades)
        {
         Reject(J_FVG_IGNORED, s, dir, R_IN_POSITION, fid);
         return false;
        }
      if(cfg.maxTradesDay > 0 && m_tradesToday >= cfg.maxTradesDay)
        {
         Reject(J_ENTRY_REJECTED, s, dir, R_DAY_LIMIT, fid);
         su[s].state = SU_DONE;
         return false;
        }
      double lo = fvgs.m_list[fi].lo;
      double hi = fvgs.m_list[fi].hi;
      double entry = (cfg.entryLevel == OPR_ENTRY_CE) ? 0.5 * (lo + hi) : (dir > 0 ? hi : lo);
      double buf = cfg.stopBufferTicks * cfg.tickSize;
      double sl = (dir > 0) ? su[s].extreme - buf : su[s].extreme + buf;
      double tp = OprStdLevel(opr[s].m_st, dir, cfg.tpStd);
      //--- e) cible déjà atteinte dans la fenêtre : pas de trade
      if((dir > 0 && su[s].winHigh >= tp) || (dir < 0 && su[s].winLow <= tp))
        {
         Reject(J_ENTRY_REJECTED, s, dir, R_TARGET_REACHED, fid);
         su[s].state = SU_DONE;
         su[s].doneReason = R_TARGET_REACHED;
         return false;
        }
      bool ok = (dir > 0) ? (sl < entry && entry < tp) : (tp < entry && entry < sl);
      if(!ok)
        {
         Reject(J_ENTRY_REJECTED, s, dir, R_INVALID_LEVELS, fid);
         return false;
        }
      double risk = MathAbs(entry - sl);
      if(cfg.minStop > 0.0 && risk < cfg.minStop - 1e-9)
        {
         Reject(J_ENTRY_REJECTED, s, dir, R_MIN_STOP, fid);
         return false;
        }
      if(cfg.maxStop > 0.0 && risk > cfg.maxStop + 1e-9)
        {
         Reject(J_ENTRY_REJECTED, s, dir, R_MAX_STOP, fid);
         return false;
        }
      fvgs.m_list[fi].role = FVG_ROLE_ENTRY;
      fvgs.m_list[fi].slot = s;
      su[s].setupId    = fid * 4 + s;
      su[s].fvgId      = fid;
      su[s].fvgLo      = lo;
      su[s].fvgHi      = hi;
      su[s].entry      = entry;
      su[s].sl         = sl;
      su[s].tp         = tp;
      su[s].risk       = risk;
      su[s].armedT     = st + OPR_BASE_SEC;
      su[s].armedMacro = mi;
      su[s].state      = SU_ARMED;
      stats.armed++;
      Log(J_ENTRY_AUTHORIZED, s, dir, R_NONE, mi, su[s].setupId, entry, sl, tp, risk);
      return true;
     }

   //+---------------------------------------------------------------+
   //| Module 7 : modèle book (entrée au niveau, résolution          |
   //| conservatrice : sur la bougie d'entrée seul le stop est       |
   //| vérifié ; stop et cible sur la même bougie = perte).          |
   //+---------------------------------------------------------------+
   void              BookStep(const long st, const datetime srv, const double h, const double l)
     {
      //--- sorties des trades ouverts (bougies postérieures à l'entrée)
      for(int i = ArraySize(m_open) - 1; i >= 0; i--)
        {
         if(m_open[i].entryT >= st)
            continue;
         int dir = m_open[i].dir;
         if(dir < 0 ? (h >= m_open[i].sl) : (l <= m_open[i].sl))
            CloseTrade(i, st, srv, m_open[i].sl, BK_EXIT_SL);
         else
            if(dir < 0 ? (l <= m_open[i].tp) : (h >= m_open[i].tp))
               CloseTrade(i, st, srv, m_open[i].tp, BK_EXIT_TP);
        }
      //--- ordres limites en attente
      for(int s = 0; s < OPR_MAX_SLOTS; s++)
        {
         if(su[s].state != SU_ARMED || su[s].armedT > st)
            continue;
         int dir = su[s].dir;
         bool hitEntry = (dir < 0) ? (h >= su[s].entry) : (l <= su[s].entry);
         bool hitTp    = (dir < 0) ? (l <= su[s].tp) : (h >= su[s].tp);
         if(hitEntry && hitTp)
           {
            Reject(J_SETUP_CANCELLED, s, dir, R_AMBIGUOUS, su[s].setupId);
            su[s].state = SU_DONE;
            continue;
           }
         if(hitTp)
           {
            Reject(J_SETUP_CANCELLED, s, dir, R_TARGET_REACHED, su[s].setupId);
            su[s].state = SU_DONE;
            continue;
           }
         if(!hitEntry)
            continue;
         int n = ArraySize(m_open);
         ArrayResize(m_open, n + 1, 8);
         m_open[n].setupId    = su[s].setupId;
         m_open[n].slot       = s;
         m_open[n].dir        = dir;
         m_open[n].macro      = su[s].armedMacro;
         m_open[n].entry      = su[s].entry;
         m_open[n].sl         = su[s].sl;
         m_open[n].tp         = su[s].tp;
         m_open[n].risk       = su[s].risk;
         m_open[n].entryT     = st;
         m_open[n].entrySrv   = srv;
         m_open[n].open       = true;
         m_open[n].exitT      = 0;
         m_open[n].exitSrv    = 0;
         m_open[n].exitPx     = 0.0;
         m_open[n].exitReason = 0;
         m_open[n].r          = 0.0;
         if(su[s].armedMacro >= 0)
            su[s].macroUsed[su[s].armedMacro] = true;
         su[s].trades++;
         m_tradesToday++;
         su[s].state = SU_IN_TRADE;
         Log(J_TRADE_FILLED, s, dir, R_NONE, su[s].armedMacro, su[s].setupId, su[s].entry, su[s].sl, su[s].tp, su[s].risk);
         //--- bougie d'entrée : seul le stop est vérifié
         if(dir < 0 ? (h >= su[s].sl) : (l <= su[s].sl))
            CloseTrade(n, st, srv, su[s].sl, BK_EXIT_SL);
        }
     }

   void              CloseTrade(const int i, const long st, const datetime srv, const double px, const int reason)
     {
      double r = (reason == BK_EXIT_TP) ? MathAbs(m_open[i].tp - m_open[i].entry) / m_open[i].risk : -1.0;
      m_open[i].open       = false;
      m_open[i].exitT      = st;
      m_open[i].exitSrv    = srv;
      m_open[i].exitPx     = px;
      m_open[i].exitReason = reason;
      m_open[i].r          = r;
      stats.trades++;
      if(r > 0.0)
         stats.wins++;
      else
         stats.losses++;
      stats.netR += r;
      int s = m_open[i].slot;
      Log(J_TRADE_CLOSED, s, m_open[i].dir, R_NONE, reason, m_open[i].setupId, px, m_open[i].entry, 0.0, r);
      if(s >= 0 && s < OPR_MAX_SLOTS && su[s].state == SU_IN_TRADE && su[s].setupId == m_open[i].setupId)
         su[s].state = (su[s].windowClosed || (su[s].winE > 0 && st >= su[s].winE)) ? SU_DONE : SU_WAIT_SWEEP;
      int nc = ArraySize(m_closed);
      if(nc < 20000)
        {
         ArrayResize(m_closed, nc + 1, 256);
         m_closed[nc] = m_open[i];
        }
      int no = ArraySize(m_open);
      for(int j = i; j < no - 1; j++)
         m_open[j] = m_open[j + 1];
      ArrayResize(m_open, no - 1, 8);
     }

   //+---------------------------------------------------------------+
   //| Accès pour l'EA                                               |
   //+---------------------------------------------------------------+
   int               FindFvgIdx(const long id) const { return (id == 0) ? -1 : fvgs.Find(id); }
   long              SrvOf(const long st) const { return st - m_srvOffset; }

   bool              RestoreOpr(const int s, const int day, const double high, const double low)
     {
      if(!opr[s].Restore(day, high, low))
         return false;
      Log(J_OPR_FINAL, s, 0, R_NONE, 1, 0, high, low, 0.0, 0.0);
      return true;
     }
  };

string OprSetupStateText(const int st)
  {
   switch(st)
     {
      case SU_OFF:        return "aucune règle d'entrée";
      case SU_IDLE:       return "attente de la fenêtre";
      case SU_WAIT_BIAS:  return "prix dans l'OPR : attente d'une clôture hors OPR";
      case SU_WAIT_SWEEP: return "attente d'une prise de liquidité";
      case SU_WAIT_FVG:   return "liquidité prise : attente du FVG";
      case SU_ARMED:      return "ordre limite armé";
      case SU_IN_TRADE:   return "en position";
      case SU_DONE:       return "terminé pour aujourd'hui";
      default:            return "?";
     }
  }

#endif // OPR_ENGINE_MQH
//+------------------------------------------------------------------+

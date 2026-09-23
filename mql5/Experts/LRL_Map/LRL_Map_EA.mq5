//+------------------------------------------------------------------+
//|                                                   LRL_Map_EA.mq5 |
//|  LRL Map : Low Resistance Liquidity + iFVG du plus haut          |
//|  timeframe, exécution automatique et statistiques auto-mesurées. |
//|                                                                  |
//|  Chaîne complète requise avant toute action :                    |
//|    LRL trouvée -> biais -> iFVG dans le sens de la LRL -> plus   |
//|    haut timeframe -> premier retest -> filtres -> trade.         |
//+------------------------------------------------------------------+
#property copyright   "LRL Map EA"
#property version     "1.00"
#property description "Low Resistance Liquidity + iFVG du plus haut timeframe (reconstruit depuis les bougies de base)."
#property description "Entrée au premier retest (CE ou bord), stop au-delà du swing de la jambe, cible en R."
#property description "Statistiques book (dans / hors fenêtre NY) affichées dans le tableau."

#include <Trade\Trade.mqh>
#include "LRL_Engine.mqh"

//--- énumérations propres à l'EA
enum ENUM_LRL_ORDER_MODE
  {
   LRL_ORDER_LIMIT  = 0,  // Ordre limite au niveau (recommandé)
   LRL_ORDER_MARKET = 1   // Ordre au marché quand le niveau est touché
  };

enum ENUM_LRL_LOT_MODE
  {
   LRL_LOT_RISK  = 0,     // % du solde risqué par trade
   LRL_LOT_FIXED = 1      // Lots fixes
  };

enum ENUM_LRL_DIRECTION
  {
   LRL_DIR_BOTH  = 0,     // Long et short
   LRL_DIR_LONG  = 1,     // Long uniquement
   LRL_DIR_SHORT = 2      // Short uniquement
  };

enum ENUM_LRL_THEME
  {
   LRL_THEME_DARK  = 0,   // Sombre
   LRL_THEME_LIGHT = 1    // Clair
  };

enum ENUM_LRL_CORNER
  {
   LRL_CORNER_TR = 0,     // Haut droite
   LRL_CORNER_TL = 1      // Haut gauche
  };

//+------------------------------------------------------------------+
//| Paramètres                                                       |
//+------------------------------------------------------------------+
input group "Bougies de base et timeframes supérieurs"
input ENUM_TIMEFRAMES     InpBaseTF          = PERIOD_M1;        // Timeframe de base (bougies d'exécution)
input int                 InpHTF1            = 2;                // HTF 1 en minutes (0 = désactivé)
input int                 InpHTF2            = 3;                // HTF 2 en minutes (0 = désactivé)
input int                 InpHTF3            = 5;                // HTF 3 en minutes (0 = désactivé)
input int                 InpWarmupBars      = 20000;            // Bougies d'historique rejouées au démarrage

input group "Swings"
input int                 InpPivotLeft       = 3;                // Pivot : bougies à gauche
input int                 InpPivotRight      = 3;                // Pivot : bougies à droite (délai de confirmation)
input int                 InpMaxSwings       = 20;               // Swings gardés par côté (N)

input group "LRL (Low Resistance Liquidity)"
input int                 InpMinTouches      = 3;                // Touches alignées minimum
input double              InpTouchTolATR     = 0.15;             // Tolérance de touche (x ATR)
input int                 InpMinSpacing      = 5;                // Espacement minimum entre touches (bougies)
input int                 InpAtrLen          = 14;               // Longueur ATR
input ENUM_LRL_SWEEP      InpSweepMode       = LRL_SWEEP_WICK;   // Ligne balayée par
input int                 InpExpireBars      = 1500;             // Expiration sans nouvelle touche (bougies)

input group "iFVG"
input ENUM_LRL_INV        InpInvMode         = LRL_INV_CLOSE_GAP; // Inversion
input double              InpMinGapTicks     = 0.0;              // Taille minimum du FVG (ticks)
input int                 InpMaxZoneAge      = 200;              // Âge maximum d'une zone (bougies HTF, 0 = illimité)

input group "Modèle de trade"
input ENUM_LRL_ENTRY      InpEntryMode       = LRL_ENTRY_CE;     // Entrée au retest
input ENUM_LRL_STOP       InpStopMode        = LRL_STOP_LEG;     // Placement du stop
input double              InpStopBufferTicks = 1.0;              // Marge du stop (ticks)
input double              InpRR              = 1.0;              // Cible (multiple de R)
input double              InpMinStop         = 15.0;             // Stop minimum (en unités de prix, ex. points NQ)
input double              InpMaxStopATR      = 0.0;              // Stop maximum (x ATR, 0 = désactivé)
input bool                InpLrlBeyondTarget = true;             // La LRL doit être au-delà de la cible

input group "Session New York"
input string              InpWinStart        = "00:00";          // Début de fenêtre (heure NY, HH:MM)
input string              InpWinEnd          = "16:00";          // Fin de fenêtre (heure NY, HH:MM)
input bool                InpTradeOnlyInWin  = true;             // Trader uniquement dans la fenêtre
input bool                InpFlatEnabled     = true;             // Tout clôturer dans la fenêtre flat
input string              InpFlatStart       = "15:55";          // Début flat (heure NY)
input string              InpFlatEnd         = "16:00";          // Fin flat (heure NY)
input ENUM_LRL_TZ         InpTzMode          = LRL_TZ_AUTO;      // Fuseau du serveur
input double              InpServerMinusNY   = 7.0;              // Serveur - NY en heures (mode NY fixe / testeur)
input double              InpServerGMT       = 2.0;              // Décalage GMT du serveur en heures (mode GMT)

input group "Exécution"
input bool                InpTradingEnabled  = true;             // Envoyer de vrais ordres
input ENUM_LRL_ORDER_MODE InpOrderMode       = LRL_ORDER_LIMIT;  // Type d'ordre
input ENUM_LRL_DIRECTION  InpDirection       = LRL_DIR_BOTH;     // Sens autorisés
input ENUM_LRL_LOT_MODE   InpLotMode         = LRL_LOT_RISK;     // Calcul du volume
input double              InpRiskPct         = 0.5;              // Risque par trade (% du solde)
input double              InpFixedLots       = 1.0;              // Lots fixes
input double              InpMaxLots         = 50.0;             // Lots maximum
input double              InpMaxChaseR       = 0.25;             // Entrée au marché tolérée au-delà du niveau (x R)
input double              InpMaxSpread       = 0.0;              // Spread maximum en prix (0 = désactivé)
input int                 InpMaxPositions    = 1;                // Positions simultanées maximum
input int                 InpMaxTradesDay    = 0;                // Trades par jour maximum (0 = illimité)
input double              InpMaxDailyLossPct = 0.0;              // Perte journalière maximum en % (0 = désactivé)
input double              InpBreakEvenR      = 0.0;              // Break-even à X R (0 = désactivé)
input double              InpBEOffsetTicks   = 1.0;              // Break-even : ticks au-delà de l'entrée
input long                InpMagic           = 26092201;         // Magic number
input string              InpComment         = "LRL";            // Commentaire des ordres
input int                 InpSlippagePoints  = 30;               // Slippage maximum (points)

input group "Affichage"
input bool                InpDraw            = true;             // Dessiner lignes, zones et trades
input bool                InpShowTable       = true;             // Afficher le tableau
input ENUM_LRL_THEME      InpTheme           = LRL_THEME_DARK;   // Thème du tableau
input ENUM_LRL_CORNER     InpCorner          = LRL_CORNER_TR;    // Position du tableau
input int                 InpFontSize        = 9;                // Taille de police du tableau
input int                 InpMaxObjects      = 40;               // Objets gardés par catégorie
input int                 InpLineWidth       = 2;                // Épaisseur des lignes LRL
input color               InpColLrlLow       = clrDeepSkyBlue;   // LRL sous le prix (cible des shorts)
input color               InpColLrlHigh      = clrOrange;        // LRL au-dessus (cible des longs)
input color               InpColSwept        = clrGray;          // LRL balayée / expirée
input color               InpColZoneBear     = clrCrimson;       // iFVG baissier surveillé
input color               InpColZoneBull     = clrLimeGreen;     // iFVG haussier surveillé
input color               InpColCE           = clrSilver;        // Ligne CE
input bool                InpFillBoxes       = true;             // Remplir les boîtes de trade
input color               InpColTP           = C'18,70,48';      // Boîte cible
input color               InpColSL           = C'82,24,30';      // Boîte stop
input color               InpColEntry        = clrWhite;         // Ligne d'entrée / textes

input group "Alertes (à la clôture de bougie)"
input bool                InpAlertPopup      = true;             // Popup
input bool                InpAlertPush       = false;            // Notification push
input bool                InpAlertSound      = false;            // Son
input bool                InpAlertLrl        = true;             // LRL confirmée
input bool                InpAlertArmed      = true;             // Setup armé (nouvelle zone surveillée)
input bool                InpAlertShort      = true;             // Entrée short
input bool                InpAlertLong       = true;             // Entrée long
input bool                InpAlertClosed     = true;             // Trade clôturé

input group "Divers"
input bool                InpExportCsv       = false;            // Exporter les trades book en CSV (MQL5\Files)
input bool                InpDebug           = false;            // Journal détaillé

#define LRL_TABLE_ROWS 20

//+------------------------------------------------------------------+
//| EA                                                               |
//+------------------------------------------------------------------+
class CLRLMapEA
  {
public:
   CLRLEngine        m_eng;
   CTrade            m_trade;
   ENUM_TIMEFRAMES   m_tf;
   int               m_tfSec;
   double            m_tick;
   int               m_volDigits;
   bool              m_ready;
   bool              m_live;
   bool              m_draw;
   bool              m_table;
   bool              m_isTester;
   datetime          m_lastBar;
   string            m_pfx;
   string            m_status;
   datetime          m_lastTable;

   //--- exécution
   ulong             m_pendTicket;
   long              m_pendZone;
   long              m_consumed[];
   long              m_failZone;
   int               m_failCount;
   int               m_dayTrades;
   double            m_dayPnL;

   //--- dessin
   string            m_lineName[2];
   string            m_zoneName;
   long              m_zoneId;
   double            m_zoneBottom;
   double            m_zoneCe;
   string            m_trName[];
   long              m_trZone[];
   double            m_trStop[];
   double            m_trTarget[];
   double            m_trEntry[];
   string            m_fifoL[];
   string            m_fifoZ[];
   string            m_fifoT[];

                     CLRLMapEA()
     {
      m_ready = false; m_live = false; m_draw = false; m_table = false; m_isTester = false;
      m_lastBar = 0; m_pendTicket = 0; m_pendZone = 0; m_failZone = 0; m_failCount = 0;
      m_dayTrades = 0; m_dayPnL = 0.0; m_zoneId = 0; m_zoneBottom = 0.0; m_zoneCe = 0.0;
      m_tfSec = 60; m_tick = 0.0; m_volDigits = 2; m_lastTable = 0;
     }

   //+---------------------------------------------------------------+
   //| Utilitaires                                                   |
   //+---------------------------------------------------------------+
   int               ParseHHMM(const string s)
     {
      string parts[];
      if(StringSplit(s, ':', parts) != 2)
         return -1;
      int h = (int)StringToInteger(parts[0]);
      int m = (int)StringToInteger(parts[1]);
      if(h < 0 || h > 24 || m < 0 || m > 59 || (h == 24 && m != 0))
         return -1;
      return (h * 60 + m) % 1440;
     }

   string            TfName(const ENUM_TIMEFRAMES tf)
     {
      switch(tf)
        {
         case PERIOD_M1:  return "M1";
         case PERIOD_M2:  return "M2";
         case PERIOD_M3:  return "M3";
         case PERIOD_M4:  return "M4";
         case PERIOD_M5:  return "M5";
         case PERIOD_M6:  return "M6";
         case PERIOD_M10: return "M10";
         case PERIOD_M12: return "M12";
         case PERIOD_M15: return "M15";
         case PERIOD_M20: return "M20";
         case PERIOD_M30: return "M30";
         case PERIOD_H1:  return "H1";
         default:         return IntegerToString(PeriodSeconds(tf) / 60) + "m";
        }
     }

   string            Px(const double p) { return DoubleToString(p, _Digits); }
   string            HHMM(const int m) { return StringFormat("%02d:%02d", m / 60, m % 60); }

   double            NormPrice(const double p) { return NormalizeDouble(MathRound(p / m_tick) * m_tick, _Digits); }
   double            NormUp(const double p)    { return NormalizeDouble(MathCeil(p / m_tick - 1e-9) * m_tick, _Digits); }
   double            NormDown(const double p)  { return NormalizeDouble(MathFloor(p / m_tick + 1e-9) * m_tick, _Digits); }

   string            BlockText(const int b)
     {
      switch(b)
        {
         case LRL_BLOCK_INVALID: return "stop invalide";
         case LRL_BLOCK_MINSTOP: return "stop < minimum";
         case LRL_BLOCK_MAXSTOP: return "stop > max ATR";
         case LRL_BLOCK_LRL:     return "LRL pas au-delà de la cible";
         case LRL_SKIP_WINDOW:   return "hors fenêtre";
         case LRL_SKIP_FLAT:     return "fenêtre flat";
         default:                return "";
        }
     }

   void              Log(const string msg)
     {
      m_status = msg;
      if(InpDebug || m_live)
         Print("LRL Map: ", msg);
     }

   void              Notify(const bool enabled, const string msg)
     {
      if(InpDebug)
         Print("LRL Map [", TimeToString(m_eng.LastBarTime(), TIME_DATE | TIME_MINUTES), "] ", msg);
      if(!enabled || !m_live || m_isTester)
         return;
      string full = "LRL Map " + _Symbol + " " + TfName(m_tf) + " : " + msg;
      if(InpAlertPopup)
         Alert(full);
      if(InpAlertPush)
         SendNotification(full);
      if(InpAlertSound)
         PlaySound("alert.wav");
     }

   //+---------------------------------------------------------------+
   //| Initialisation                                                |
   //+---------------------------------------------------------------+
   int               Init()
     {
      //--- MT5 ne réinitialise pas les globales lors d'un changement de symbole / timeframe
      m_ready      = false;
      m_live       = false;
      m_lastBar    = 0;
      m_pendTicket = 0;
      m_pendZone   = 0;
      m_failZone   = 0;
      m_failCount  = 0;
      m_dayTrades  = 0;
      m_dayPnL     = 0.0;
      m_zoneId     = 0;
      m_lastTable  = 0;
      m_isTester = (MQLInfoInteger(MQL_TESTER) != 0);
      bool visual = (MQLInfoInteger(MQL_VISUAL_MODE) != 0);
      bool optim  = (MQLInfoInteger(MQL_OPTIMIZATION) != 0);
      m_draw  = InpDraw && !optim && (!m_isTester || visual);
      m_table = InpShowTable && !optim && (!m_isTester || visual);
      m_pfx   = "LRLM_";

      m_tf    = (InpBaseTF == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpBaseTF;
      m_tfSec = PeriodSeconds(m_tf);
      if(m_tfSec <= 0 || m_tfSec > 3600)
        {
         Print("LRL Map: timeframe de base invalide (M1 à H1 attendu)");
         return INIT_PARAMETERS_INCORRECT;
        }

      m_tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(m_tick <= 0.0)
         m_tick = _Point;
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      m_volDigits = 0;
      double s = (step > 0.0) ? step : 0.01;
      while(s < 1.0 - 1e-9 && m_volDigits < 8)
        {
         s *= 10.0;
         m_volDigits++;
        }

      int ws = ParseHHMM(InpWinStart);
      int we = ParseHHMM(InpWinEnd);
      int fs = ParseHHMM(InpFlatStart);
      int fe = ParseHHMM(InpFlatEnd);
      if(ws < 0 || we < 0 || fs < 0 || fe < 0)
        {
         Print("LRL Map: heure invalide dans la fenêtre ou le flat (format HH:MM attendu)");
         return INIT_PARAMETERS_INCORRECT;
        }

      LRLConfig c;
      c.Defaults();
      c.baseSeconds       = m_tfSec;
      c.htfMinutes[0]     = InpHTF1;
      c.htfMinutes[1]     = InpHTF2;
      c.htfMinutes[2]     = InpHTF3;
      c.pivotLeft         = InpPivotLeft;
      c.pivotRight        = InpPivotRight;
      c.maxSwings         = InpMaxSwings;
      c.minTouches        = InpMinTouches;
      c.touchTolAtr       = InpTouchTolATR;
      c.minSpacing        = InpMinSpacing;
      c.atrLen            = InpAtrLen;
      c.sweepMode         = InpSweepMode;
      c.expireBars        = InpExpireBars;
      c.invMode           = InpInvMode;
      c.minGapTicks       = InpMinGapTicks;
      c.maxZoneAge        = InpMaxZoneAge;
      c.entryMode         = InpEntryMode;
      c.stopMode          = InpStopMode;
      c.stopBufferTicks   = InpStopBufferTicks;
      c.rr                = InpRR;
      c.minStop           = InpMinStop;
      c.maxStopAtr        = InpMaxStopATR;
      c.lrlBeyondTarget   = InpLrlBeyondTarget;
      c.tradeOnlyInWindow = InpTradeOnlyInWin;
      c.winStartMin       = ws;
      c.winEndMin         = we;
      c.flatEnabled       = InpFlatEnabled;
      c.flatStartMin      = fs;
      c.flatEndMin        = fe;
      c.tickSize          = m_tick;
      c.serverMinusNySec  = (int)MathRound(InpServerMinusNY * 3600.0);
      c.serverGmtSec      = (int)MathRound(InpServerGMT * 3600.0);
      c.tzMode            = (InpTzMode == LRL_TZ_SERVER_GMT) ? LRL_TZ_SERVER_GMT : LRL_TZ_SERVER_NY;

      if(InpTzMode == LRL_TZ_AUTO && !m_isTester)
        {
         long srv = (long)TimeTradeServer();
         long gmt = (long)TimeGMT();
         long off = (long)MathRound((double)(srv - gmt) / 1800.0) * 1800;
         long ny  = m_eng.IsUsDst(gmt) ? -4 * 3600 : -5 * 3600;
         c.serverMinusNySec = (int)(off - ny);
         PrintFormat("LRL Map: fuseau auto -> serveur GMT%+.1f, serveur - NY = %.1f h",
                     (double)off / 3600.0, (double)c.serverMinusNySec / 3600.0);
        }
      else
         if(InpTzMode == LRL_TZ_AUTO)
            PrintFormat("LRL Map: testeur -> serveur - NY fixé à %.1f h (paramètre)", InpServerMinusNY);

      if(!m_eng.Init(c))
        {
         Print("LRL Map: aucun timeframe supérieur valide. Les HTF doivent être > et multiples du timeframe de base.");
         return INIT_PARAMETERS_INCORRECT;
        }
      string htfs = "";
      for(int i = 0; i < m_eng.m_htfCount; i++)
         htfs += (i > 0 ? "/" : "") + IntegerToString(m_eng.m_htf[i].minutes);
      PrintFormat("LRL Map: base %s, HTF %s min, entrée %s, stop %s, cible %.2fR, stop min %.2f",
                  TfName(m_tf), htfs, InpEntryMode == LRL_ENTRY_CE ? "CE" : "bord",
                  InpStopMode == LRL_STOP_LEG ? "swing de jambe" : "zone", InpRR, InpMinStop);

      m_trade.SetExpertMagicNumber((ulong)InpMagic);
      m_trade.SetDeviationInPoints((ulong)MathMax(InpSlippagePoints, 0));
      m_trade.SetTypeFillingBySymbol(_Symbol);
      m_trade.SetAsyncMode(false);
      m_trade.LogLevel(InpDebug ? LOG_LEVEL_ALL : LOG_LEVEL_ERRORS);

      ArrayResize(m_consumed, 0);
      ArrayResize(m_trName, 0);
      ArrayResize(m_trZone, 0);
      ArrayResize(m_trStop, 0);
      ArrayResize(m_trTarget, 0);
      ArrayResize(m_trEntry, 0);
      ArrayResize(m_fifoL, 0);
      ArrayResize(m_fifoZ, 0);
      ArrayResize(m_fifoT, 0);
      m_lineName[0] = "";
      m_lineName[1] = "";
      m_zoneName = "";
      m_status = "initialisation";

      ObjectsDeleteAll(0, m_pfx);
      AdoptPending();
      if(!m_isTester || visual)
         EventSetTimer(1);
      Warmup();
      return INIT_SUCCEEDED;
     }

   void              Deinit(const int reason)
     {
      EventKillTimer();
      ExportCsv();
      if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE || reason == REASON_CLOSE ||
         reason == REASON_ACCOUNT || reason == REASON_INITFAILED)
         DeletePendings();
      ObjectsDeleteAll(0, m_pfx);
      ChartRedraw();
     }

   //+---------------------------------------------------------------+
   //| Historique : rejoue les dernières bougies clôturées           |
   //+---------------------------------------------------------------+
   bool              Warmup()
     {
      int avail = Bars(_Symbol, m_tf);
      if(avail < 100)
         return false;
      int want = MathMin(MathMax(InpWarmupBars, 100), avail - 1);
      MqlRates r[];
      int got = CopyRates(_Symbol, m_tf, 1, want, r);
      if(got < 100)
         return false;
      m_live = false;
      for(int i = 0; i < got; i++)
         FeedBar(r[i]);
      m_lastBar = r[got - 1].time;
      m_live  = true;
      m_ready = true;
      RefreshDaily();
      if(m_draw)
         ExtendActive();
      UpdateTable();
      LRLStats st;
      st = m_eng.m_stats;
      PrintFormat("LRL Map: %d bougies rejouées -> %d trades book (%dW/%dL), net %.2fR, %d ignorés (stop min)",
                  got, st.trades, st.wins, st.losses, st.netR, st.skipMinStop);
      m_status = "prêt";
      return true;
     }

   void              FeedBar(const MqlRates &r)
     {
      m_eng.ProcessBar(r.time, r.open, r.high, r.low, r.close);
      for(int i = 0; i < m_eng.m_evCount; i++)
         OnEngineEvent(m_eng.m_events[i]);
      if(m_live && m_draw)
         ExtendActive();
     }

   bool              ProcessNewBars()
     {
      datetime lastClosed = iTime(_Symbol, m_tf, 1);
      if(lastClosed == 0 || lastClosed <= m_lastBar)
         return false;
      int shift = iBarShift(_Symbol, m_tf, m_lastBar, true);
      int count = (shift > 1) ? shift - 1 : 1;
      if(shift < 0)
         count = 500;
      if(count > 5000)
         count = 5000;
      MqlRates r[];
      int got = CopyRates(_Symbol, m_tf, 1, count, r);
      if(got <= 0)
         return false;
      bool any = false;
      for(int i = 0; i < got; i++)
        {
         if(r[i].time <= m_lastBar)
            continue;
         FeedBar(r[i]);
         m_lastBar = r[i].time;
         any = true;
        }
      return any;
     }

   //+---------------------------------------------------------------+
   //| Tick / timer                                                  |
   //+---------------------------------------------------------------+
   void              Tick()
     {
      if(!m_ready && !Warmup())
         return;
      bool nb = ProcessNewBars();
      if(nb)
         RefreshDaily();
      Execute();
      if(nb)
        {
         UpdateTable();
         if(m_draw || m_table)
            ChartRedraw();
        }
     }

   void              Timer()
     {
      if(!m_ready)
        {
         Warmup();
         return;
        }
      if(m_table && TimeCurrent() != m_lastTable)
        {
         UpdateTable();
         ChartRedraw();
        }
     }

   //+---------------------------------------------------------------+
   //| Exécution réelle                                              |
   //+---------------------------------------------------------------+
   bool              IsOurs(const string sym, const long magic) { return (sym == _Symbol && magic == InpMagic); }

   int               CountPositions()
     {
      int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0)
            continue;
         if(IsOurs(PositionGetString(POSITION_SYMBOL), PositionGetInteger(POSITION_MAGIC)))
            n++;
        }
      return n;
     }

   int               CountPendings()
     {
      int n = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong tk = OrderGetTicket(i);
         if(tk == 0)
            continue;
         if(IsOurs(OrderGetString(ORDER_SYMBOL), OrderGetInteger(ORDER_MAGIC)))
            n++;
        }
      return n;
     }

   long              ZoneFromComment(const string cmt)
     {
      int pos = -1;
      int from = 0;
      while(true)
        {
         int f = StringFind(cmt, " ", from);
         if(f < 0)
            break;
         pos = f;
         from = f + 1;
        }
      if(pos < 0)
         return 0;
      return StringToInteger(StringSubstr(cmt, pos + 1));
     }

   bool              FindPending(ulong &ticket, long &zone)
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong tk = OrderGetTicket(i);
         if(tk == 0)
            continue;
         if(!IsOurs(OrderGetString(ORDER_SYMBOL), OrderGetInteger(ORDER_MAGIC)))
            continue;
         long ot = OrderGetInteger(ORDER_TYPE);
         if(ot != ORDER_TYPE_BUY_LIMIT && ot != ORDER_TYPE_SELL_LIMIT)
            continue;
         ticket = tk;
         zone   = ZoneFromComment(OrderGetString(ORDER_COMMENT));
         return true;
        }
      return false;
     }

   //--- après un redémarrage : reprend l'ordre en attente et marque comme consommées les zones
   //--- déjà tradées (position ouverte ou entrée récente), pour ne jamais doubler un trade
   void              AdoptPending()
     {
      ulong tk = 0;
      long zone = 0;
      if(FindPending(tk, zone))
        {
         m_pendTicket = tk;
         m_pendZone   = zone;
         PrintFormat("LRL Map: ordre en attente #%s repris (zone %s)", IntegerToString((long)tk), IntegerToString(zone));
        }
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong pt = PositionGetTicket(i);
         if(pt == 0)
            continue;
         if(IsOurs(PositionGetString(POSITION_SYMBOL), PositionGetInteger(POSITION_MAGIC)))
            Consume(ZoneFromComment(PositionGetString(POSITION_COMMENT)));
        }
      datetime now = TimeCurrent();
      if(HistorySelect(now - 3 * 86400, now + 60))
        {
         int n = HistoryDealsTotal();
         for(int i = 0; i < n; i++)
           {
            ulong d = HistoryDealGetTicket(i);
            if(d == 0)
               continue;
            if(!IsOurs(HistoryDealGetString(d, DEAL_SYMBOL), HistoryDealGetInteger(d, DEAL_MAGIC)))
               continue;
            if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
               Consume(ZoneFromComment(HistoryDealGetString(d, DEAL_COMMENT)));
           }
        }
     }

   void              DeletePendings()
     {
      m_pendTicket = 0;
      m_pendZone   = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong tk = OrderGetTicket(i);
         if(tk == 0)
            continue;
         if(!IsOurs(OrderGetString(ORDER_SYMBOL), OrderGetInteger(ORDER_MAGIC)))
            continue;
         if(!m_trade.OrderDelete(tk))
            Log("échec suppression ordre #" + IntegerToString((long)tk) + " : " + m_trade.ResultRetcodeDescription());
        }
     }

   void              CloseAllPositions()
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0)
            continue;
         if(!IsOurs(PositionGetString(POSITION_SYMBOL), PositionGetInteger(POSITION_MAGIC)))
            continue;
         if(m_trade.PositionClose(tk, (ulong)MathMax(InpSlippagePoints, 0)))
            Log("position #" + IntegerToString((long)tk) + " clôturée (fenêtre flat)");
         else
            Log("échec clôture #" + IntegerToString((long)tk) + " : " + m_trade.ResultRetcodeDescription());
        }
     }

   bool              IsConsumed(const long zid)
     {
      for(int i = ArraySize(m_consumed) - 1; i >= 0; i--)
         if(m_consumed[i] == zid)
            return true;
      return false;
     }

   void              Consume(const long zid)
     {
      if(zid == 0 || IsConsumed(zid))
         return;
      int n = ArraySize(m_consumed);
      if(n >= 256)
        {
         for(int i = 0; i < n - 1; i++)
            m_consumed[i] = m_consumed[i + 1];
         n--;
        }
      ArrayResize(m_consumed, n + 1);
      m_consumed[n] = zid;
     }

   void              RefreshDaily()
     {
      bool need = (InpMaxTradesDay > 0 || InpMaxDailyLossPct > 0.0 || m_table);
      if(!need || !m_live)
         return;
      datetime now = TimeCurrent();
      datetime day = (datetime)((long)now - ((long)now % 86400));
      m_dayTrades = 0;
      m_dayPnL    = 0.0;
      if(!HistorySelect(day, now + 60))
         return;
      int n = HistoryDealsTotal();
      for(int i = 0; i < n; i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0)
            continue;
         if(!IsOurs(HistoryDealGetString(d, DEAL_SYMBOL), HistoryDealGetInteger(d, DEAL_MAGIC)))
            continue;
         long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN)
            m_dayTrades++;
         m_dayPnL += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_COMMISSION);
        }
     }

   bool              DailyOk()
     {
      if(InpMaxTradesDay > 0 && m_dayTrades >= InpMaxTradesDay)
         return false;
      if(InpMaxDailyLossPct > 0.0 && m_dayPnL <= -InpMaxDailyLossPct / 100.0 * AccountInfoDouble(ACCOUNT_BALANCE))
         return false;
      return true;
     }

   double            ComputeLots(const int dir, const double entry, const double stop)
     {
      double lots = InpFixedLots;
      ENUM_ORDER_TYPE ot = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(InpLotMode == LRL_LOT_RISK)
        {
         double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPct / 100.0;
         double pl = 0.0;
         double lossPerLot = 0.0;
         if(OrderCalcProfit(ot, _Symbol, 1.0, entry, stop, pl) && pl < 0.0)
            lossPerLot = -pl;
         else
           {
            double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
            lossPerLot = MathAbs(entry - stop) / m_tick * tv;
           }
         if(lossPerLot <= 0.0)
            return 0.0;
         lots = riskMoney / lossPerLot;
        }
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      if(step <= 0.0)
         step = 0.01;
      lots = MathMin(lots, MathMin(vmax, InpMaxLots));
      //--- marge disponible
      double margin = 0.0;
      if(lots > 0.0 && OrderCalcMargin(ot, _Symbol, lots, entry, margin) && margin > 0.0)
        {
         double freeM = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.95;
         if(margin > freeM)
            lots = lots * freeM / margin;
        }
      lots = MathFloor(lots / step + 1e-9) * step;
      if(lots < vmin - 1e-12)
         return 0.0;
      return NormalizeDouble(lots, m_volDigits);
     }

   bool              SendLimit(const int dir, const double lots, const double price, const double sl, const double tp, const string cmt)
     {
      ENUM_ORDER_TYPE_TIME tt = ORDER_TIME_GTC;
      long em = SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE);
      if((em & SYMBOL_EXPIRATION_GTC) == 0)
         tt = ORDER_TIME_DAY;
      ENUM_ORDER_TYPE_FILLING fills[3];
      fills[0] = ORDER_FILLING_RETURN;
      fills[1] = ORDER_FILLING_IOC;
      fills[2] = ORDER_FILLING_FOK;
      bool ok = false;
      for(int attempt = 0; attempt < 4; attempt++)
        {
         if(attempt > 0)
            m_trade.SetTypeFilling(fills[attempt - 1]);
         if(dir < 0)
            ok = m_trade.SellLimit(lots, price, _Symbol, sl, tp, tt, 0, cmt);
         else
            ok = m_trade.BuyLimit(lots, price, _Symbol, sl, tp, tt, 0, cmt);
         if(ok || m_trade.ResultRetcode() != TRADE_RETCODE_INVALID_FILL)
            break;
        }
      m_trade.SetTypeFillingBySymbol(_Symbol);
      return ok;
     }

   void              ManageBreakEven(const MqlTick &tk)
     {
      if(InpBreakEvenR <= 0.0)
         return;
      double lvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      double off = InpBEOffsetTicks * m_tick;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(!IsOurs(PositionGetString(POSITION_SYMBOL), PositionGetInteger(POSITION_MAGIC)))
            continue;
         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl   = PositionGetDouble(POSITION_SL);
         double tp   = PositionGetDouble(POSITION_TP);
         if(sl <= 0.0)
            continue;
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
           {
            if(sl >= open)
               continue;
            if(tk.bid - open >= InpBreakEvenR * (open - sl))
              {
               double nsl = NormPrice(open + off);
               if(tk.bid - nsl > lvl && m_trade.PositionModify(ticket, nsl, tp))
                  Log("break-even long #" + IntegerToString((long)ticket));
              }
           }
         else
           {
            if(sl <= open)
               continue;
            if(open - tk.ask >= InpBreakEvenR * (sl - open))
              {
               double nsl = NormPrice(open - off);
               if(nsl - tk.ask > lvl && m_trade.PositionModify(ticket, nsl, tp))
                  Log("break-even short #" + IntegerToString((long)ticket));
              }
           }
        }
     }

   void              Execute()
     {
      if(!InpTradingEnabled || !m_live)
         return;
      if(!m_isTester && (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0 || MQLInfoInteger(MQL_TRADE_ALLOWED) == 0))
        {
         m_status = "AutoTrading désactivé";
         return;
        }
      MqlTick tk;
      if(!SymbolInfoTick(_Symbol, tk) || tk.bid <= 0.0 || tk.ask <= 0.0)
         return;
      datetime now = (tk.time > 0) ? tk.time : TimeCurrent();
      int nyMin = m_eng.NyMinute(now);

      //--- fenêtre flat : tout est clôturé
      if(m_eng.InFlatMin(nyMin))
        {
         if(CountPendings() > 0)
            DeletePendings();
         if(CountPositions() > 0)
            CloseAllPositions();
         return;
        }
      ManageBreakEven(tk);

      //--- l'ordre suivi a disparu : exécuté (ou annulé à la main) -> zone consommée
      if(m_pendTicket != 0 && !OrderSelect(m_pendTicket))
        {
         Consume(m_pendZone);
         Log("ordre limite #" + IntegerToString((long)m_pendTicket) + " exécuté ou retiré");
         m_pendTicket = 0;
         m_pendZone   = 0;
         RefreshDaily();
        }

      long zid = m_eng.m_armed.zoneId;
      int  dir = m_eng.m_armed.dir;
      bool want = m_eng.m_armed.valid && m_eng.m_armed.block == LRL_BLOCK_NONE && !IsConsumed(zid);
      if(want && ((InpDirection == LRL_DIR_LONG && dir < 0) || (InpDirection == LRL_DIR_SHORT && dir > 0)))
         want = false;
      if(want && InpTradeOnlyInWin && !m_eng.InWindowMin(nyMin))
         want = false;
      if(want && CountPositions() >= InpMaxPositions)
         want = false;
      if(want && !DailyOk())
         want = false;
      if(want && InpMaxSpread > 0.0 && (tk.ask - tk.bid) > InpMaxSpread)
         want = false;

      ulong pt = 0;
      long  pz = 0;
      bool hasPend = FindPending(pt, pz);
      if(!want)
        {
         if(hasPend)
            DeletePendings();
         return;
        }
      if(hasPend)
        {
         if(pz == zid)
           {
            m_pendTicket = pt;
            m_pendZone   = zid;
            return;
           }
         DeletePendings();
        }

      //--- arrondi au tick dans le sens qui garde le déclenchement identique au modèle book
      //--- (sur une grille de ticks : haut >= E  <=>  haut >= plafond(E), bas <= E  <=>  bas <= plancher(E))
      double entry  = (dir < 0) ? NormUp(m_eng.m_armed.entry)  : NormDown(m_eng.m_armed.entry);
      double stop   = (dir < 0) ? NormUp(m_eng.m_armed.stop)   : NormDown(m_eng.m_armed.stop);
      double target = (dir < 0) ? NormDown(m_eng.m_armed.target) : NormUp(m_eng.m_armed.target);
      double risk   = MathAbs(entry - stop);
      double lvl    = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      string cmt    = InpComment + " " + IntegerToString(zid);
      bool crossed  = (dir < 0) ? (tk.bid >= entry) : (tk.ask <= entry);

      //--- entrée au marché : mode marché au toucher, ou niveau déjà dépassé
      if(InpOrderMode == LRL_ORDER_MARKET || crossed)
        {
         if(!crossed)
            return;
         double px    = (dir < 0) ? tk.bid : tk.ask;
         double chase = (dir < 0) ? (px - entry) : (entry - px);
         bool pastStop = (dir < 0) ? (px >= stop - lvl) : (px <= stop + lvl);
         Consume(zid);
         if(chase > InpMaxChaseR * risk || pastStop)
           {
            Log("setup manqué : prix " + Px(px) + " trop loin de l'entrée " + Px(entry));
            return;
           }
         double lots = ComputeLots(dir, px, stop);
         if(lots <= 0.0)
           {
            Log("volume nul (risque trop faible ou marge insuffisante)");
            return;
           }
         bool ok = (dir < 0) ? m_trade.Sell(lots, _Symbol, 0.0, stop, target, cmt)
                   : m_trade.Buy(lots, _Symbol, 0.0, stop, target, cmt);
         if(ok)
            Log(StringFormat("%s marché %.2f lots @ %s SL %s TP %s", dir < 0 ? "SELL" : "BUY", lots, Px(px), Px(stop), Px(target)));
         else
            Log("échec ordre marché : " + m_trade.ResultRetcodeDescription());
         RefreshDaily();
         return;
        }

      //--- ordre limite au niveau
      if((dir < 0) ? (entry - tk.bid < lvl) : (tk.ask - entry < lvl))
         return;
      if((dir < 0) ? (stop - entry < lvl || entry - target < lvl) : (entry - stop < lvl || target - entry < lvl))
        {
         Consume(zid);
         Log("stops trop proches du prix d'entrée pour le broker");
         return;
        }
      double lots = ComputeLots(dir, entry, stop);
      if(lots <= 0.0)
        {
         Consume(zid);
         Log("volume nul (risque trop faible ou marge insuffisante)");
         return;
        }
      if(SendLimit(dir, lots, entry, stop, target, cmt))
        {
         m_pendTicket = m_trade.ResultOrder();
         m_pendZone   = zid;
         m_failCount  = 0;
         Log(StringFormat("%s LIMIT %.2f lots @ %s SL %s TP %s", dir < 0 ? "SELL" : "BUY", lots, Px(entry), Px(stop), Px(target)));
        }
      else
        {
         if(m_failZone != zid)
           {
            m_failZone  = zid;
            m_failCount = 0;
           }
         m_failCount++;
         Log("échec ordre limite (" + IntegerToString(m_failCount) + "/3) : " + m_trade.ResultRetcodeDescription());
         if(m_failCount >= 3)
            Consume(zid);
        }
     }

   //+---------------------------------------------------------------+
   //| Événements du moteur : alertes + dessin                       |
   //+---------------------------------------------------------------+
   void              OnEngineEvent(const LRLEvent &ev)
     {
      switch(ev.type)
        {
         case LRL_EV_LRL_NEW:
            DrawLineNew(ev);
            if(ev.reason == 0)
               Notify(InpAlertLrl, StringFormat("LRL confirmée %s, %d touches, %s",
                                                ev.side == LRL_SIDE_LOW ? "sous le prix (biais SHORT)" : "au-dessus du prix (biais LONG)",
                                                ev.n, Px(ev.p2)));
            break;
         case LRL_EV_LRL_END:
            DrawLineEnd(ev);
            break;
         case LRL_EV_WATCH_START:
            DrawZoneStart(ev);
            Notify(InpAlertArmed, StringFormat("setup armé : iFVG %dm %s %s - %s, entrée %s",
                                               ev.tfMin, ev.side < 0 ? "baissier" : "haussier", Px(ev.p2), Px(ev.p1), Px(ev.p3)));
            break;
         case LRL_EV_WATCH_END:
            DrawZoneEnd(ev);
            break;
         case LRL_EV_TRADE_OPEN:
            DrawTradeOpen(ev);
            Notify(ev.side < 0 ? InpAlertShort : InpAlertLong,
                   StringFormat("%s @ %s, stop %s, cible %s (iFVG %dm)", ev.side < 0 ? "SHORT" : "LONG",
                                Px(ev.p1), Px(ev.p2), Px(ev.p3), ev.tfMin));
            break;
         case LRL_EV_TRADE_CLOSE:
            DrawTradeClose(ev);
            Notify(InpAlertClosed, StringFormat("trade %s clôturé %+.2fR (%s)", ev.side < 0 ? "short" : "long", ev.p5,
                                                ev.reason == LRL_EXIT_TARGET ? "cible" : (ev.reason == LRL_EXIT_STOP ? "stop" : "flat")));
            break;
         case LRL_EV_SETUP_SKIP:
            if(InpDebug)
               Print("LRL Map: setup ignoré (", BlockText(ev.reason), ") entrée ", Px(ev.p1), " risque ", DoubleToString(ev.p4, 2));
            break;
         default:
            break;
        }
     }

   //+---------------------------------------------------------------+
   //| Dessin                                                        |
   //+---------------------------------------------------------------+
   void              FifoPush(string &arr[], const string prefix)
     {
      int n = ArraySize(arr);
      ArrayResize(arr, n + 1);
      arr[n] = prefix;
      n++;
      int maxN = MathMax(InpMaxObjects, 1);
      while(n > maxN)
        {
         ObjectsDeleteAll(0, arr[0]);
         for(int i = 0; i < n - 1; i++)
            arr[i] = arr[i + 1];
         n--;
         ArrayResize(arr, n);
        }
     }

   void              FifoRemove(string &arr[], const string prefix)
     {
      int n = ArraySize(arr);
      for(int i = 0; i < n; i++)
         if(arr[i] == prefix)
           {
            for(int j = i; j < n - 1; j++)
               arr[j] = arr[j + 1];
            ArrayResize(arr, n - 1);
            return;
           }
     }

   void              ObjCommon(const string name)
     {
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }

   void              MkTrend(const string name, const datetime t1, const double p1, const datetime t2, const double p2,
                             const color col, const int width, const ENUM_LINE_STYLE style, const string tip)
     {
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
      else
        {
         ObjectMove(0, name, 0, t1, p1);
         ObjectMove(0, name, 1, t2, p2);
        }
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
      ObjCommon(name);
     }

   void              MkRect(const string name, const datetime t1, const double p1, const datetime t2, const double p2,
                            const color col, const bool fill, const string tip)
     {
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_FILL, fill);
      ObjectSetInteger(0, name, OBJPROP_BACK, fill);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
      ObjCommon(name);
     }

   void              MkText(const string name, const datetime t, const double p, const string txt, const color col,
                            const ENUM_ANCHOR_POINT anchor)
     {
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
      ObjectSetString(0, name, OBJPROP_TEXT, txt);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      ObjCommon(name);
     }

   datetime          ExtTime() { return m_eng.LastBarTime() + m_tfSec; }

   void              DrawLineNew(const LRLEvent &ev)
     {
      if(!m_draw)
         return;
      string pfx  = m_pfx + "L" + IntegerToString(ev.id) + "_";
      color  col  = (ev.side == LRL_SIDE_LOW) ? InpColLrlLow : InpColLrlHigh;
      string tip  = StringFormat("LRL %s - %d touches", ev.side == LRL_SIDE_LOW ? "basse (cible short)" : "haute (cible long)", ev.n);
      MkTrend(pfx + "ln", ev.t1, ev.p1, ev.t2, ev.p2, col, InpLineWidth, STYLE_SOLID, tip);
      m_lineName[ev.side] = pfx + "ln";
      FifoPush(m_fifoL, pfx);
     }

   void              DrawLineEnd(const LRLEvent &ev)
     {
      if(!m_draw)
         return;
      string pfx = m_pfx + "L" + IntegerToString(ev.id) + "_";
      if(m_lineName[ev.side] == pfx + "ln")
         m_lineName[ev.side] = "";
      if(ev.reason == LRL_END_REPLACED)
        {
         ObjectsDeleteAll(0, pfx);
         FifoRemove(m_fifoL, pfx);
         return;
        }
      string name = pfx + "ln";
      ObjectMove(0, name, 1, ev.t2, ev.p2);
      ObjectSetInteger(0, name, OBJPROP_STYLE, ev.reason == LRL_END_SWEEP ? STYLE_DASH : STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_COLOR, InpColSwept);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, ev.reason == LRL_END_SWEEP ? "LRL balayée" : "LRL expirée");
     }

   void              DrawZoneStart(const LRLEvent &ev)
     {
      if(!m_draw)
         return;
      string pfx = m_pfx + "Z" + IntegerToString(ev.id) + "_";
      color  col = (ev.side < 0) ? InpColZoneBear : InpColZoneBull;
      double ce  = 0.5 * (ev.p1 + ev.p2);
      datetime te = ExtTime();
      string tip = StringFormat("iFVG %dm %s surveillé", ev.tfMin, ev.side < 0 ? "baissier" : "haussier");
      MkRect(pfx + "rc", ev.t1, ev.p1, te, ev.p2, col, false, tip);
      MkTrend(pfx + "ce", ev.t1, ce, te, ce, InpColCE, 1, STYLE_DOT, "CE");
      MkText(pfx + "tx", ev.t1, ev.side < 0 ? ev.p1 : ev.p2, StringFormat("iFVG %dm", ev.tfMin), col,
             ev.side < 0 ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
      m_zoneName   = pfx;
      m_zoneId     = ev.id;
      m_zoneBottom = ev.p2;
      m_zoneCe     = ce;
      FifoPush(m_fifoZ, pfx);
     }

   void              DrawZoneEnd(const LRLEvent &ev)
     {
      if(!m_draw)
         return;
      string pfx = m_pfx + "Z" + IntegerToString(ev.id) + "_";
      if(ObjectFind(0, pfx + "rc") >= 0)
        {
         ObjectMove(0, pfx + "rc", 1, ev.t2 + m_tfSec, ev.p2);
         ObjectMove(0, pfx + "ce", 1, ev.t2 + m_tfSec, 0.5 * (ev.p1 + ev.p2));
         if(ev.reason == LRL_WATCH_LOST)
            ObjectSetInteger(0, pfx + "rc", OBJPROP_STYLE, STYLE_DOT);
        }
      if(m_zoneId == ev.id)
        {
         m_zoneName = "";
         m_zoneId   = 0;
        }
     }

   void              DrawTradeOpen(const LRLEvent &ev)
     {
      if(!m_draw)
         return;
      string pfx = m_pfx + "T" + IntegerToString(ev.id) + "_";
      datetime te = ev.t1 + m_tfSec;
      MkRect(pfx + "tp", ev.t1, ev.p1, te, ev.p3, InpColTP, InpFillBoxes, "cible " + Px(ev.p3));
      MkRect(pfx + "sl", ev.t1, ev.p1, te, ev.p2, InpColSL, InpFillBoxes, "stop " + Px(ev.p2));
      MkTrend(pfx + "en", ev.t1, ev.p1, te, ev.p1, InpColEntry, 1, STYLE_SOLID, "entrée " + Px(ev.p1));
      MkText(pfx + "lb", ev.t1, ev.p2, StringFormat("%s %dm", ev.side < 0 ? "SHORT" : "LONG", ev.tfMin), InpColEntry,
             ev.side < 0 ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
      int n = ArraySize(m_trName);
      ArrayResize(m_trName, n + 1);
      ArrayResize(m_trZone, n + 1);
      ArrayResize(m_trStop, n + 1);
      ArrayResize(m_trTarget, n + 1);
      ArrayResize(m_trEntry, n + 1);
      m_trName[n]   = pfx;
      m_trZone[n]   = ev.id;
      m_trStop[n]   = ev.p2;
      m_trTarget[n] = ev.p3;
      m_trEntry[n]  = ev.p1;
      FifoPush(m_fifoT, pfx);
     }

   void              DrawTradeClose(const LRLEvent &ev)
     {
      if(!m_draw)
         return;
      string pfx = m_pfx + "T" + IntegerToString(ev.id) + "_";
      datetime te = ev.t2 + m_tfSec;
      if(ObjectFind(0, pfx + "tp") >= 0)
        {
         ObjectMove(0, pfx + "tp", 1, te, ev.p3);
         ObjectMove(0, pfx + "sl", 1, te, ev.p2);
         ObjectMove(0, pfx + "en", 1, te, ev.p1);
         MkText(pfx + "rs", te, ev.p4, StringFormat("%+.2fR", ev.p5), ev.p5 > 0.0 ? clrLimeGreen : clrTomato, ANCHOR_LEFT);
        }
      int n = ArraySize(m_trName);
      for(int i = 0; i < n; i++)
         if(m_trZone[i] == ev.id)
           {
            for(int j = i; j < n - 1; j++)
              {
               m_trName[j]   = m_trName[j + 1];
               m_trZone[j]   = m_trZone[j + 1];
               m_trStop[j]   = m_trStop[j + 1];
               m_trTarget[j] = m_trTarget[j + 1];
               m_trEntry[j]  = m_trEntry[j + 1];
              }
            ArrayResize(m_trName, n - 1);
            ArrayResize(m_trZone, n - 1);
            ArrayResize(m_trStop, n - 1);
            ArrayResize(m_trTarget, n - 1);
            ArrayResize(m_trEntry, n - 1);
            break;
           }
     }

   void              ExtendActive()
     {
      if(!m_draw)
         return;
      datetime te = ExtTime();
      int nb = m_eng.m_bar + 1;
      for(int s = 0; s < 2; s++)
         if(m_lineName[s] != "" && m_eng.m_lrl[s].active)
            ObjectMove(0, m_lineName[s], 1, te, m_eng.m_lrl[s].PriceAt(nb));
      if(m_zoneName != "")
        {
         ObjectMove(0, m_zoneName + "rc", 1, te, m_zoneBottom);
         ObjectMove(0, m_zoneName + "ce", 1, te, m_zoneCe);
        }
      for(int i = ArraySize(m_trName) - 1; i >= 0; i--)
        {
         ObjectMove(0, m_trName[i] + "tp", 1, te, m_trTarget[i]);
         ObjectMove(0, m_trName[i] + "sl", 1, te, m_trStop[i]);
         ObjectMove(0, m_trName[i] + "en", 1, te, m_trEntry[i]);
        }
     }

   //+---------------------------------------------------------------+
   //| Tableau                                                       |
   //+---------------------------------------------------------------+
   color             ThBg()      { return InpTheme == LRL_THEME_DARK ? C'18,20,26' : C'250,250,252'; }
   color             ThBorder()  { return InpTheme == LRL_THEME_DARK ? C'60,64,74' : C'200,200,210'; }
   color             ThText()    { return InpTheme == LRL_THEME_DARK ? C'205,210,220' : C'30,30,36'; }
   color             ThHead()    { return InpTheme == LRL_THEME_DARK ? C'255,196,72' : C'20,90,200'; }
   color             ThPos()     { return InpTheme == LRL_THEME_DARK ? C'80,200,120' : C'0,140,70'; }
   color             ThNeg()     { return InpTheme == LRL_THEME_DARK ? C'240,95,90' : C'200,40,40'; }
   color             ThMuted()   { return InpTheme == LRL_THEME_DARK ? C'140,145,158' : C'110,110,122'; }

   int               RowH() { return InpFontSize * 2 + 2; }
   int               TableW() { return InpFontSize * 40; }

   void              TableLabel(const string name, const int x, const int y, const ENUM_ANCHOR_POINT anchor)
     {
      ENUM_BASE_CORNER corner = (InpCorner == LRL_CORNER_TR) ? CORNER_RIGHT_UPPER : CORNER_LEFT_UPPER;
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
      ObjCommon(name);
     }

   void              TableRow(const int row, const string key, const string val, const color kc, const color vc)
     {
      int margin = 10;
      int pad    = 8;
      int w      = TableW();
      int y      = margin + pad / 2 + row * RowH();
      string kn  = m_pfx + "TB_k" + IntegerToString(row);
      string vn  = m_pfx + "TB_v" + IntegerToString(row);
      if(InpCorner == LRL_CORNER_TR)
        {
         TableLabel(kn, margin + w - pad, y, ANCHOR_LEFT_UPPER);
         TableLabel(vn, margin + pad, y, ANCHOR_RIGHT_UPPER);
        }
      else
        {
         TableLabel(kn, margin + pad, y, ANCHOR_LEFT_UPPER);
         TableLabel(vn, margin + w - pad, y, ANCHOR_RIGHT_UPPER);
        }
      ObjectSetString(0, kn, OBJPROP_TEXT, key);
      ObjectSetInteger(0, kn, OBJPROP_COLOR, kc);
      ObjectSetString(0, vn, OBJPROP_TEXT, (val == "") ? " " : val);
      ObjectSetInteger(0, vn, OBJPROP_COLOR, vc);
     }

   string            Pct(const int w, const int n) { return (n > 0) ? DoubleToString(100.0 * w / n, 1) + "%" : "-"; }
   string            Rs(const double r) { return StringFormat("%+.2fR", r); }

   void              UpdateTable()
     {
      if(!m_table)
         return;
      m_lastTable = TimeCurrent();
      int margin = 10;
      int w = TableW();
      string bg = m_pfx + "TB_bg";
      if(ObjectFind(0, bg) < 0)
         ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER, InpCorner == LRL_CORNER_TR ? CORNER_RIGHT_UPPER : CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, InpCorner == LRL_CORNER_TR ? margin + w : margin);
      ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, margin);
      ObjectSetInteger(0, bg, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, bg, OBJPROP_YSIZE, LRL_TABLE_ROWS * RowH() + 8);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, ThBg());
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_COLOR, ThBorder());
      ObjectSetInteger(0, bg, OBJPROP_ZORDER, 5);
      ObjCommon(bg);

      color tx = ThText();
      color hd = ThHead();
      color mu = ThMuted();
      color ps = ThPos();
      color ng = ThNeg();
      int r = 0;

      TableRow(r++, "LRL Map EA", _Symbol + "  " + TfName(m_tf), hd, hd);

      //--- état live
      for(int s = 0; s < 2; s++)
        {
         string key = (s == LRL_SIDE_LOW) ? "LRL basse (short)" : "LRL haute (long)";
         string val = "-";
         color  vc  = mu;
         if(m_eng.m_lrl[s].active)
           {
            val = Px(m_eng.LinePriceNow(s)) + "  " + IntegerToString(m_eng.m_lrl[s].touches) + " touches";
            vc  = (s == LRL_SIDE_LOW) ? InpColLrlLow : InpColLrlHigh;
           }
         TableRow(r++, key, val, tx, vc);
        }
      string bias = (m_eng.m_bias < 0) ? "SHORT" : (m_eng.m_bias > 0 ? "LONG" : "neutre");
      TableRow(r++, "Biais", bias, tx, m_eng.m_bias < 0 ? ng : (m_eng.m_bias > 0 ? ps : mu));

      string zone  = "-";
      string setup = (m_eng.m_bias == 0) ? "pas de LRL" : "attente d'un iFVG";
      color  sc    = mu;
      if(m_eng.m_armed.valid)
        {
         zone = StringFormat("%dm %s %s-%s", m_eng.m_armed.tfMin, m_eng.m_armed.dir < 0 ? "baissier" : "haussier",
                             Px(m_eng.m_armed.bottom), Px(m_eng.m_armed.top));
         if(m_eng.m_armed.block == LRL_BLOCK_NONE)
           {
            setup = "ARMÉ E " + Px(m_eng.m_armed.entry) + " S " + Px(m_eng.m_armed.stop) + " T " + Px(m_eng.m_armed.target);
            sc = hd;
           }
         else
           {
            setup = "bloqué : " + BlockText(m_eng.m_armed.block) + " (" + DoubleToString(m_eng.m_armed.risk, 2) + ")";
            sc = ng;
           }
        }
      TableRow(r++, "Zone surveillée", zone, tx, m_eng.m_armed.valid ? (m_eng.m_armed.dir < 0 ? InpColZoneBear : InpColZoneBull) : mu);
      TableRow(r++, "Setup", setup, tx, sc);

      datetime now = TimeCurrent();
      int nyMin = m_eng.NyMinute(now);
      string win = m_eng.InFlatMin(nyMin) ? "FLAT" : (m_eng.InWindowMin(nyMin) ? "DANS" : "HORS");
      TableRow(r++, "Fenêtre NY", win + "  " + HHMM(nyMin) + " NY", tx, win == "DANS" ? ps : (win == "FLAT" ? ng : mu));

      //--- statistiques book
      LRLStats st;
      st = m_eng.m_stats;
      TableRow(r++, "Statistiques (book)", "", hd, hd);
      TableRow(r++, "Trades", IntegerToString(st.trades) + "  (" + IntegerToString(st.wins) + "W / " + IntegerToString(st.losses) + "L)", tx, tx);
      TableRow(r++, "Win rate", Pct(st.wins, st.trades), tx, st.trades > 0 && 2 * st.wins >= st.trades ? ps : tx);
      TableRow(r++, "Net R / moyen", Rs(st.netR) + " / " + (st.trades > 0 ? Rs(st.netR / st.trades) : "-"), tx, st.netR >= 0.0 ? ps : ng);
      TableRow(r++, "Dans la fenêtre", IntegerToString(st.inTrades) + "  WR " + Pct(st.inWins, st.inTrades) + "  " + Rs(st.inNetR), tx, tx);
      TableRow(r++, "Hors fenêtre", IntegerToString(st.outTrades) + "  WR " + Pct(st.outWins, st.outTrades) + "  " + Rs(st.outNetR), tx, tx);
      TableRow(r++, "Ignorés stop min", IntegerToString(st.skipMinStop), tx, mu);
      TableRow(r++, "Autres rejets", "ATR " + IntegerToString(st.skipMaxStop) + "  LRL " + IntegerToString(st.skipLrl) +
               "  fen. " + IntegerToString(st.skipWindow) + "  flat " + IntegerToString(st.skipFlat), tx, mu);

      //--- compte
      TableRow(r++, "Compte", "", hd, hd);
      string exec = InpTradingEnabled ? ((InpOrderMode == LRL_ORDER_LIMIT ? "limite" : "marché") +
                                         (InpLotMode == LRL_LOT_RISK ? "  " + DoubleToString(InpRiskPct, 2) + "%" : "  " + DoubleToString(InpFixedLots, 2) + " lots"))
                                      : "désactivée (signaux seuls)";
      TableRow(r++, "Exécution", exec, tx, InpTradingEnabled ? ps : mu);
      TableRow(r++, "Positions / ordres", IntegerToString(CountPositions()) + " / " + IntegerToString(CountPendings()), tx, tx);
      TableRow(r++, "Aujourd'hui", IntegerToString(m_dayTrades) + " trades  " + DoubleToString(m_dayPnL, 2) + " " +
               AccountInfoString(ACCOUNT_CURRENCY), tx, m_dayPnL >= 0.0 ? ps : ng);
      TableRow(r++, "Statut", m_status, tx, mu);
     }

   //+---------------------------------------------------------------+
   //| Export CSV des trades book                                    |
   //+---------------------------------------------------------------+
   void              ExportCsv()
     {
      if(!InpExportCsv)
         return;
      string fn = "LRL_Map_" + _Symbol + "_" + TfName(m_tf) + ".csv";
      int h = FileOpen(fn, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(h == INVALID_HANDLE)
        {
         Print("LRL Map: impossible d'écrire ", fn);
         return;
        }
      FileWrite(h, "entry_time", "dir", "htf_min", "entry", "stop", "target", "risk", "exit_time", "exit_price", "exit_reason", "r", "in_window");
      int n = m_eng.ClosedTradeCount();
      for(int i = 0; i < n; i++)
        {
         string reason = (m_eng.m_closed[i].exitReason == LRL_EXIT_TARGET) ? "target" :
                         (m_eng.m_closed[i].exitReason == LRL_EXIT_STOP ? "stop" : "flat");
         FileWrite(h, TimeToString(m_eng.m_closed[i].entryTime, TIME_DATE | TIME_MINUTES),
                   m_eng.m_closed[i].dir < 0 ? "short" : "long",
                   m_eng.m_closed[i].tfMin,
                   Px(m_eng.m_closed[i].entry), Px(m_eng.m_closed[i].stop), Px(m_eng.m_closed[i].target),
                   DoubleToString(m_eng.m_closed[i].risk, _Digits),
                   TimeToString(m_eng.m_closed[i].exitTime, TIME_DATE | TIME_MINUTES),
                   Px(m_eng.m_closed[i].exitPrice), reason,
                   DoubleToString(m_eng.m_closed[i].r, 3),
                   m_eng.m_closed[i].inWindow ? 1 : 0);
        }
      FileClose(h);
      PrintFormat("LRL Map: %d trades book exportés dans %s", n, fn);
     }
  };

CLRLMapEA g_ea;

//+------------------------------------------------------------------+
int OnInit()
  {
   return g_ea.Init();
  }

void OnDeinit(const int reason)
  {
   g_ea.Deinit(reason);
  }

void OnTick()
  {
   g_ea.Tick();
  }

void OnTimer()
  {
   g_ea.Timer();
  }
//+------------------------------------------------------------------+

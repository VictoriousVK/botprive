//+------------------------------------------------------------------+
//|                                                  OPR_FVG_EA.mq5  |
//|  Stratégie ICT OPR + FVG (modèle « London OPR » de Mélanie)      |
//|                                                                  |
//|  Modules :                                                       |
//|   1. horaires / calendrier ......... OPR_Time.mqh                |
//|   2. calcul des OPR ................ OPR_Ranges.mqh              |
//|   3. détection des FVG ............. OPR_FVG.mqh                 |
//|   4. FVG de référence (Asie, minuit)  OPR_Engine.mqh             |
//|   5. contexte directionnel ......... OPR_Engine.mqh              |
//|   6. validation des entrées ........ OPR_Engine.mqh              |
//|   7. ordres et risque .............. ce fichier                  |
//|   8. journalisation / diagnostic ... OPR_Journal.mqh + ce fichier|
//|                                                                  |
//|  Toutes les plages horaires sont des paramètres de ce fichier    |
//|  (groupe « Plages horaires »), exprimées dans le fuseau de la    |
//|  stratégie.                                                      |
//+------------------------------------------------------------------+
#property copyright   "OPR FVG EA"
#property version     "1.00"
#property description "OPR (Midnight Opening Range et autres OPR), premier FVG M15 asiatique, FPFVG M1 de minuit."
#property description "Entrée : biais à l'ouverture de la fenêtre, prise de liquidité, FVG dans une macro, stop au-delà du swing, cible en déviations standard de l'OPR."
#property description "Chaque décision est expliquée dans le journal."

#include <Trade\Trade.mqh>
#include "OPR_Engine.mqh"

enum ENUM_OPR_LOT_MODE
  {
   OPR_LOT_RISK  = 0,      // % du solde risqué par trade
   OPR_LOT_FIXED = 1       // Lots fixes
  };

enum ENUM_OPR_THEME
  {
   OPR_THEME_DARK  = 0,    // Sombre
   OPR_THEME_LIGHT = 1     // Clair
  };

enum ENUM_OPR_CORNER
  {
   OPR_CORNER_TR = 0,      // Haut droite
   OPR_CORNER_TL = 1       // Haut gauche
  };

//+------------------------------------------------------------------+
//| Paramètres                                                       |
//+------------------------------------------------------------------+
input group "Fuseaux horaires"
input ENUM_OPR_STRAT_TZ  InpStratTZ      = OPR_STZ_NEW_YORK;    // Fuseau des horaires de la stratégie (PDF : heure de New York)
input ENUM_OPR_SERVER_TZ InpServerTZ     = OPR_SRV_AUTO;        // Fuseau du serveur du broker
input double             InpServerGMT    = 2.0;                 // Serveur : décalage GMT en hiver (heures)
input string             InpDayStart     = "18:00";             // Début de la journée de session (heure stratégie)

input group "Plages horaires (heure de la stratégie)"
input string             InpAsiaRange    = "20:00-00:00";       // Plage asiatique (premier FVG M15)
input string             InpLondonRange  = "00:00-06:00";       // Session de Londres (information + recherche du FPFVG de minuit)
input string             InpObsWindow    = "02:50-03:10";       // Fenêtre d'observation (information uniquement)
input string             InpOpr1Range    = "00:00-00:30";       // OPR 1 (Midnight Opening Range) : plage de calcul
input bool               InpOpr1Trade    = true;                // OPR 1 : modèle d'entrée actif (PDF London OPR)
input string             InpOpr1Window   = "02:50-04:10";       // OPR 1 : fenêtre de trading
input string             InpOpr1Macros   = "02:50-03:10,03:20-03:40,03:50-04:10"; // OPR 1 : macros
input string             InpOpr2Range    = "07:00-07:30";       // OPR 2 : plage de calcul ("" = désactivé)
input bool               InpOpr2Trade    = false;               // OPR 2 : modèle d'entrée (aucune règle documentée)
input string             InpOpr2Window   = "";                  // OPR 2 : fenêtre de trading
input string             InpOpr2Macros   = "";                  // OPR 2 : macros
input string             InpOpr3Range    = "09:30-10:00";       // OPR 3 : plage de calcul
input bool               InpOpr3Trade    = false;               // OPR 3 : modèle d'entrée (aucune règle documentée)
input string             InpOpr3Window   = "";                  // OPR 3 : fenêtre de trading
input string             InpOpr3Macros   = "";                  // OPR 3 : macros
input string             InpOpr4Range    = "13:30-14:00";       // OPR 4 : plage de calcul
input bool               InpOpr4Trade    = false;               // OPR 4 : modèle d'entrée (aucune règle documentée)
input string             InpOpr4Window   = "";                  // OPR 4 : fenêtre de trading
input string             InpOpr4Macros   = "";                  // OPR 4 : macros

input group "FVG"
input ENUM_OPR_ASIA_RULE   InpAsiaRule          = OPR_ASIA_C2_IN_RANGE; // FVG asiatique « présenté pendant la plage »
input double               InpAsiaMinGapTicks   = 1.0;          // FVG asiatique : taille minimale (ticks)
input double               InpMidnightMinGapTicks = 1.0;        // FPFVG M1 de minuit : taille minimale (ticks)
input ENUM_OPR_ENTRY_TF    InpEntryTF           = OPR_TF_M1;    // Timeframe du FVG d'entrée
input ENUM_OPR_ENTRY_LEVEL InpEntryLevel        = OPR_ENTRY_EDGE; // Niveau d'entrée dans le FVG
input double               InpMinFvgTicks       = 1.0;          // FVG d'entrée : taille minimale (ticks)

input group "Liquidité (à prendre avant l'entrée)"
input bool               InpLiqM1        = true;                // Swings M1 (hauts / bas simples)
input int                InpLiqPivotM1   = 1;                   // Swings M1 : bougies de chaque côté
input bool               InpLiqM15       = true;                // Swings M15
input int                InpLiqPivotM15  = 1;                   // Swings M15 : bougies de chaque côté
input bool               InpLiqAsia      = true;                // High / Low de la plage asiatique

input group "Modèle d'entrée"
input bool               InpRequireMacro      = true;           // Le FVG d'entrée doit se former dans une macro
input bool               InpOneTradePerMacro  = true;           // 1 macro = 1 trade
input bool               InpConsolRequireSweep = true;          // Prix dans l'OPR à l'ouverture : exiger aussi une prise de liquidité
input double             InpStopBufferTicks   = 1.0;            // Stop : ticks au-delà du swing
input double             InpTpStd             = 2.0;            // Cible : déviation standard de l'OPR (notes : 2 à 2,5)
input int                InpGraceMin          = 0;              // Ordre en attente conservé après la fenêtre (minutes)
input double             InpMinStop           = 0.0;            // Stop minimum en prix (0 = aucun)
input double             InpMaxStop           = 0.0;            // Stop maximum en prix (0 = aucun)
input int                InpMaxOpenTrades     = 1;              // Positions simultanées maximum
input int                InpMaxTradesDay      = 0;              // Trades par journée de session (0 = illimité)

input group "Exécution"
input bool               InpTradingEnabled = true;              // Envoyer de vrais ordres (sinon : signaux et journal seuls)
input ENUM_OPR_LOT_MODE  InpLotMode        = OPR_LOT_RISK;      // Calcul du volume
input double             InpRiskPct        = 0.5;               // Risque par trade (% du solde)
input double             InpFixedLots      = 1.0;               // Lots fixes
input double             InpMaxLots        = 50.0;              // Lots maximum
input double             InpMaxChaseR      = 0.25;              // Entrée au marché tolérée au-delà du niveau (x R)
input double             InpMaxSpread      = 0.0;               // Spread maximum en prix (0 = aucun)
input long               InpMagic          = 26101201;          // Magic number
input string             InpComment        = "OPR";             // Commentaire des ordres
input int                InpSlippagePoints = 30;                // Slippage maximum (points)

input group "Données, journal et persistance"
input int                InpWarmupDays     = 3;                 // Jours d'historique M1 rejoués au démarrage
input bool               InpJournalPrint   = true;              // Écrire chaque décision dans le journal Experts
input bool               InpJournalCsv     = true;              // Écrire le journal dans MQL5\Files (CSV)
input bool               InpLogContext     = true;              // Journaliser les changements de contexte (au-dessus / sous / dans l'OPR)
input bool               InpLogAllFvg      = false;             // Journaliser tous les FVG d'entrée (hors fenêtre aussi)
input bool               InpPersistOpr     = true;              // Sauvegarder les OPR finalisés (redémarrage de MT5)

input group "Affichage"
input bool               InpDraw           = true;              // Dessiner OPR, FVG, setups et trades
input bool               InpShowTable      = true;              // Afficher le tableau
input ENUM_OPR_THEME     InpTheme          = OPR_THEME_DARK;    // Thème du tableau
input ENUM_OPR_CORNER    InpCorner         = OPR_CORNER_TR;     // Position du tableau
input int                InpFontSize       = 9;                 // Taille de police du tableau
input int                InpDaysDrawn      = 5;                 // Journées conservées sur le graphique
input color              InpColOprHigh     = clrDodgerBlue;     // OPR High
input color              InpColOprLow      = clrOrangeRed;      // OPR Low
input color              InpColStd         = clrGoldenrod;      // Déviations standard
input color              InpColAsia        = clrSlateGray;      // Plage asiatique
input color              InpColAsiaFvg     = clrMediumPurple;   // Premier FVG M15 asiatique
input color              InpColMidFvg      = clrDeepSkyBlue;    // FPFVG M1 de minuit
input color              InpColEntryFvg    = clrGold;           // FVG d'entrée
input color              InpColTP          = C'18,70,48';       // Boîte cible
input color              InpColSL          = C'82,24,30';       // Boîte stop
input color              InpColText        = clrWhite;          // Textes

input group "Alertes (à la clôture de bougie)"
input bool               InpAlertPopup     = true;              // Popup
input bool               InpAlertPush      = false;             // Notification push
input bool               InpAlertSound     = false;             // Son
input bool               InpAlertOpr       = true;              // OPR finalisé
input bool               InpAlertBias      = true;              // Biais de la fenêtre
input bool               InpAlertSweep     = true;              // Liquidité prise
input bool               InpAlertEntry     = true;              // Entrée autorisée
input bool               InpAlertTrade     = true;              // Trade exécuté / clôturé (book)

#define OPR_TABLE_ROWS 21
#define OPR_LAST_MSGS  3

//+------------------------------------------------------------------+
//| EA                                                               |
//+------------------------------------------------------------------+
class COprEA
  {
public:
   COprEngine        m_eng;
   CTrade            m_trade;
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
   string            m_lastMsg[OPR_LAST_MSGS];
   int               m_journal;          // handle du CSV
   //--- exécution
   ulong             m_pendTicket[OPR_MAX_SLOTS];
   long              m_pendSetup[OPR_MAX_SLOTS];
   long              m_consumed[];
   long              m_failSetup;
   int               m_failCount;
   int               m_dayTrades;
   double            m_dayPnL;
   //--- dessin
   int               m_drawDays[];

                     COprEA()
     {
      m_ready = false; m_live = false; m_draw = false; m_table = false; m_isTester = false;
      m_lastBar = 0; m_journal = INVALID_HANDLE; m_failSetup = 0; m_failCount = 0; m_dayTrades = 0; m_dayPnL = 0.0;
      m_tick = 0.0; m_volDigits = 2;
     }

   //+---------------------------------------------------------------+
   //| Utilitaires                                                   |
   //+---------------------------------------------------------------+
   string            Px(const double p) { return DoubleToString(p, _Digits); }
   double            NormPrice(const double p) { return NormalizeDouble(MathRound(p / m_tick) * m_tick, _Digits); }
   double            NormUp(const double p)    { return NormalizeDouble(MathCeil(p / m_tick - 1e-9) * m_tick, _Digits); }
   double            NormDown(const double p)  { return NormalizeDouble(MathFloor(p / m_tick + 1e-9) * m_tick, _Digits); }
   string            StratClock(const long st) { return OprHHMM(m_eng.tm.MinuteOfDay(st)); }
   string            TzName()
     {
      switch(InpStratTZ)
        {
         case OPR_STZ_NEW_YORK: return "NY";
         case OPR_STZ_LONDON:   return "Londres";
         case OPR_STZ_PARIS:    return "Paris";
         case OPR_STZ_UTC:      return "UTC";
         default:               return "serveur";
        }
     }

   void              Status(const string msg)
     {
      m_status = msg;
      if(m_live)
         Print("OPR FVG: ", msg);
     }

   //+---------------------------------------------------------------+
   //| Construction et validation de la configuration                |
   //+---------------------------------------------------------------+
   bool              Fail(const string msg)
     {
      Print("OPR FVG - paramètre invalide : ", msg);
      return false;
     }

   bool              ParseSlot(OPRConfig &c, const int s, const string range, const bool trade, const string window, const string macros)
     {
      string name = "OPR " + IntegerToString(s + 1);
      OPRTimeRange r;
      if(!OprParseRange(range, r))
         return Fail(name + " : plage « " + range + " » (format HH:MM-HH:MM)");
      c.slots[s].calc = r;
      c.slots[s].tradeEnabled = false;
      m_eng.slotName[s] = r.valid ? name + " " + OprHHMM(r.startMin) : name;
      if(s == 0 && r.valid)
         m_eng.slotName[s] = "MOR " + OprHHMM(r.startMin);
      if(!trade)
         return true;
      if(!r.valid)
         return Fail(name + " : modèle d'entrée actif mais plage de calcul vide");
      OPRTimeRange w;
      if(!OprParseRange(window, w))
         return Fail(name + " : fenêtre « " + window + " »");
      if(!w.valid)
         return Fail(name + " : modèle d'entrée actif sans fenêtre de trading. Aucune règle n'est documentée pour cet OPR : "
                     "désactivez l'entrée ou renseignez la fenêtre et les macros.");
      if(!m_eng.tm.FitsInSession(r) || !m_eng.tm.FitsInSession(w))
         return Fail(name + " : plage ou fenêtre à cheval sur le début de la journée de session (" + InpDayStart + ")");
      int calcEnd = m_eng.tm.SessionMinute(r.startMin) + r.Length();
      if(m_eng.tm.SessionMinute(w.startMin) < calcEnd)
         return Fail(name + " : la fenêtre de trading commence avant la fin de l'OPR (le biais exige un OPR finalisé)");
      OPRTimeRange ms[];
      if(!OprParseRanges(macros, ms))
         return Fail(name + " : macros « " + macros + " »");
      int n = ArraySize(ms);
      if(n > OPR_MAX_MACROS)
         return Fail(name + StringFormat(" : %d macros maximum", OPR_MAX_MACROS));
      if(n == 0 && InpRequireMacro)
         return Fail(name + " : aucune macro alors que « macro exigée » est actif");
      for(int i = 0; i < n; i++)
        {
         int ws = m_eng.tm.SessionMinute(w.startMin);
         int ms0 = m_eng.tm.SessionMinute(ms[i].startMin);
         if(ms0 < ws || ms0 + ms[i].Length() > ws + w.Length())
            Print("OPR FVG - attention : ", name, " macro ", OprRangeText(ms[i]), " déborde de la fenêtre ", OprRangeText(w));
         c.slots[s].macros[i] = ms[i];
        }
      c.slots[s].macroCount = n;
      c.slots[s].window = w;
      c.slots[s].tradeEnabled = true;
      return true;
     }

   bool              BuildConfig(OPRConfig &c)
     {
      c.Defaults();
      c.stratTz = InpStratTZ;
      c.serverMode = InpServerTZ;
      c.serverGmtSec = (int)MathRound(InpServerGMT * 3600.0);
      int ds = OprParseHHMM(InpDayStart);
      if(ds < 0)
         return Fail("début de journée « " + InpDayStart + " »");
      c.dayStartMin = ds;

      if(InpServerTZ == OPR_SRV_AUTO)
        {
         if(m_isTester)
            return Fail("dans le testeur, le fuseau du serveur ne peut pas être mesuré : choisissez-le explicitement "
                        "(la plupart des brokers : « GMT+x en hiver, +1 h pendant le DST US » avec x = 2).");
         long srv = (long)TimeTradeServer();
         long gmt = (long)TimeGMT();
         long off = (long)MathRound((double)(srv - gmt) / 1800.0) * 1800;
         c.serverMode = OPR_SRV_GMT_FIXED;
         c.serverGmtSec = (int)off;
         PrintFormat("OPR FVG: fuseau du serveur mesuré : GMT%+.1f (constant pendant la session)", (double)off / 3600.0);
        }
      m_eng.tm.Configure(c.stratTz, c.serverMode, c.serverGmtSec, c.dayStartMin);

      if(!OprParseRange(InpAsiaRange, c.asia))
         return Fail("plage asiatique « " + InpAsiaRange + " »");
      if(!OprParseRange(InpLondonRange, c.london))
         return Fail("session de Londres « " + InpLondonRange + " »");
      if(!OprParseRange(InpObsWindow, c.observe))
         return Fail("fenêtre d'observation « " + InpObsWindow + " »");
      if(!m_eng.tm.FitsInSession(c.asia))
         return Fail("la plage asiatique doit tenir dans la journée de session (début " + InpDayStart + ")");

      if(!ParseSlot(c, 0, InpOpr1Range, InpOpr1Trade, InpOpr1Window, InpOpr1Macros))
         return false;
      if(!ParseSlot(c, 1, InpOpr2Range, InpOpr2Trade, InpOpr2Window, InpOpr2Macros))
         return false;
      if(!ParseSlot(c, 2, InpOpr3Range, InpOpr3Trade, InpOpr3Window, InpOpr3Macros))
         return false;
      if(!ParseSlot(c, 3, InpOpr4Range, InpOpr4Trade, InpOpr4Window, InpOpr4Macros))
         return false;

      c.asiaRule            = InpAsiaRule;
      c.asiaMinGapTicks     = MathMax(InpAsiaMinGapTicks, 0.0);
      c.midnightMinGapTicks = MathMax(InpMidnightMinGapTicks, 0.0);
      c.entryTfMin          = InpEntryTF;
      c.entryLevel          = InpEntryLevel;
      c.minFvgTicks         = MathMax(InpMinFvgTicks, 0.0);
      c.liqM1               = InpLiqM1;
      c.liqPivotM1          = MathMax(InpLiqPivotM1, 1);
      c.liqM15              = InpLiqM15;
      c.liqPivotM15         = MathMax(InpLiqPivotM15, 1);
      c.liqAsia             = InpLiqAsia;
      c.requireMacro        = InpRequireMacro;
      c.oneTradePerMacro    = InpOneTradePerMacro;
      c.consolRequireSweep  = InpConsolRequireSweep;
      c.stopBufferTicks     = MathMax(InpStopBufferTicks, 0.0);
      c.tpStd               = InpTpStd;
      c.graceMin            = MathMax(InpGraceMin, 0);
      c.minStop             = InpMinStop;
      c.maxStop             = InpMaxStop;
      c.maxOpenTrades       = InpMaxOpenTrades;
      c.maxTradesDay        = InpMaxTradesDay;
      c.tickSize            = m_tick;
      if(InpTpStd <= 0.0)
         return Fail("la cible doit être une déviation standard > 0");
      if(InpMaxOpenTrades < 1)
         return Fail("positions simultanées maximum >= 1");
      if(!InpLiqM1 && !InpLiqM15 && !InpLiqAsia)
         return Fail("aucune source de liquidité : le modèle ne pourrait jamais entrer");
      return true;
     }

   //+---------------------------------------------------------------+
   int               Init()
     {
      m_ready      = false;
      m_live       = false;
      m_lastBar    = 0;
      m_failSetup  = 0;
      m_failCount  = 0;
      m_dayTrades  = 0;
      m_dayPnL     = 0.0;
      m_status     = "initialisation";
      for(int i = 0; i < OPR_LAST_MSGS; i++)
         m_lastMsg[i] = "";
      for(int s = 0; s < OPR_MAX_SLOTS; s++)
        {
         m_pendTicket[s] = 0;
         m_pendSetup[s]  = 0;
        }
      ArrayResize(m_consumed, 0);
      ArrayResize(m_drawDays, 0);
      m_isTester = (MQLInfoInteger(MQL_TESTER) != 0);
      bool visual = (MQLInfoInteger(MQL_VISUAL_MODE) != 0);
      bool optim  = (MQLInfoInteger(MQL_OPTIMIZATION) != 0);
      m_draw  = InpDraw && !optim && (!m_isTester || visual);
      m_table = InpShowTable && !optim && (!m_isTester || visual);
      m_pfx   = "OPRM_";

      m_tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(m_tick <= 0.0)
         m_tick = _Point;
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      m_volDigits = 0;
      double sv = (step > 0.0) ? step : 0.01;
      while(sv < 1.0 - 1e-9 && m_volDigits < 8)
        {
         sv *= 10.0;
         m_volDigits++;
        }

      OPRConfig c;
      if(!BuildConfig(c))
         return INIT_PARAMETERS_INCORRECT;
      m_eng.logContext = InpLogContext;
      m_eng.logAllFvg  = InpLogAllFvg;
      m_eng.Init(c);
      LogConfig(c);

      m_trade.SetExpertMagicNumber((ulong)InpMagic);
      m_trade.SetDeviationInPoints((ulong)MathMax(InpSlippagePoints, 0));
      m_trade.SetTypeFillingBySymbol(_Symbol);
      m_trade.SetAsyncMode(false);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);

      ObjectsDeleteAll(0, m_pfx);
      OpenJournal();
      AdoptState();
      if(!m_isTester || visual)
         EventSetTimer(1);
      Warmup();
      return INIT_SUCCEEDED;
     }

   void              LogConfig(const OPRConfig &c)
     {
      PrintFormat("OPR FVG: fuseau stratégie %s, journée de session à partir de %s", TzName(), InpDayStart);
      for(int s = 0; s < OPR_MAX_SLOTS; s++)
        {
         if(!c.slots[s].calc.valid)
            continue;
         string m = "";
         for(int i = 0; i < c.slots[s].macroCount; i++)
            m += (i > 0 ? ", " : "") + OprRangeText(c.slots[s].macros[i]);
         if(c.slots[s].tradeEnabled)
            Print("OPR FVG: ", m_eng.slotName[s], " ", OprRangeText(c.slots[s].calc), " -> fenêtre ", OprRangeText(c.slots[s].window),
                  " macros ", m, StringFormat(" | FVG d'entrée M%d, cible %.2f STD", c.entryTfMin, c.tpStd));
         else
            Print("OPR FVG: ", m_eng.slotName[s], " ", OprRangeText(c.slots[s].calc), " -> niveaux et contexte seulement (entrée désactivée)");
        }
     }

   void              Deinit(const int reason)
     {
      EventKillTimer();
      if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE || reason == REASON_CLOSE ||
         reason == REASON_ACCOUNT || reason == REASON_INITFAILED)
         DeletePendings(-1);
      if(m_journal != INVALID_HANDLE)
        {
         FileClose(m_journal);
         m_journal = INVALID_HANDLE;
        }
      ObjectsDeleteAll(0, m_pfx);
      ChartRedraw();
     }

   //+---------------------------------------------------------------+
   //| Historique M1 et nouvelles bougies                            |
   //+---------------------------------------------------------------+
   bool              Warmup()
     {
      int avail = Bars(_Symbol, PERIOD_M1);
      if(avail < 200)
         return false;
      int want = MathMin(MathMax(InpWarmupDays, 1) * 1440 + 120, avail - 1);
      MqlRates r[];
      int got = CopyRates(_Symbol, PERIOD_M1, 1, want, r);
      if(got < 200)
         return false;
      m_live = false;
      for(int i = 0; i < got; i++)
         FeedBar(r[i]);
      m_lastBar = r[got - 1].time;
      RestoreOprLevels();
      m_live  = true;
      m_ready = true;
      RefreshDaily();
      UpdateTable();
      PrintFormat("OPR FVG: %d bougies M1 rejouées, journée de session en cours : %s", got, OprSetupStateText(m_eng.su[0].state));
      m_status = "prêt";
      return true;
     }

   void              FeedBar(const MqlRates &r)
     {
      m_eng.ProcessBar(r.time, r.open, r.high, r.low, r.close);
      for(int i = 0; i < m_eng.jr.m_count; i++)
         OnEngineEvent(m_eng.jr.m_ev[i]);
     }

   bool              ProcessNewBars()
     {
      datetime lastClosed = iTime(_Symbol, PERIOD_M1, 1);
      if(lastClosed == 0 || lastClosed <= m_lastBar)
         return false;
      int shift = iBarShift(_Symbol, PERIOD_M1, m_lastBar, true);
      int count = (shift > 1) ? shift - 1 : 1;
      if(shift < 0)
         count = 500;
      if(count > 5000)
         count = 5000;
      MqlRates r[];
      int got = CopyRates(_Symbol, PERIOD_M1, 1, count, r);
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
      if(m_table)
        {
         UpdateTable();
         ChartRedraw();
        }
     }

   //+---------------------------------------------------------------+
   //| Module 8 : journal (Experts + CSV), alertes                   |
   //+---------------------------------------------------------------+
   void              OpenJournal()
     {
      if(!InpJournalCsv)
         return;
      string fn = "OPR_FVG_journal_" + _Symbol + ".csv";
      m_journal = FileOpen(fn, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ, ';');
      if(m_journal == INVALID_HANDLE)
        {
         Print("OPR FVG: impossible d'ouvrir le journal ", fn);
         return;
        }
      FileSeek(m_journal, 0, SEEK_END);
      if(FileTell(m_journal) == 0)
         FileWrite(m_journal, "heure_serveur", "heure_strategie", "code", "opr", "sens", "raison", "id", "p1", "p2", "p3", "p4", "message");
     }

   void              OnEngineEvent(const OJEvent &e)
     {
      string name = (e.slot >= 0 && e.slot < OPR_MAX_SLOTS) ? m_eng.slotName[e.slot] : "";
      string txt = OprEventText(e, name, _Digits);
      //--- persistance des OPR finalisés
      if(e.code == J_OPR_FINAL && e.aux == 0 && InpPersistOpr && e.slot >= 0)
         SaveOpr(e.slot);
      Draw(e);
      if(!m_live)
         return;
      string stamp = "[" + StratClock(e.st) + " " + TzName() + "] ";
      if(InpJournalPrint)
         Print("OPR FVG ", stamp, txt);
      if(m_journal != INVALID_HANDLE)
        {
         FileWrite(m_journal, TimeToString(e.srv, TIME_DATE | TIME_MINUTES), StratClock(e.st), e.code, e.slot + 1, e.dir, e.reason,
                   IntegerToString(e.id), Px(e.p1), Px(e.p2), Px(e.p3), DoubleToString(e.p4, 2), txt);
         FileFlush(m_journal);
        }
      bool important = (e.code == J_OPR_FINAL || e.code == J_BIAS || e.code == J_BIAS_BREAKOUT || e.code == J_BIAS_CONSOL ||
                        e.code == J_SWEEP || e.code == J_ENTRY_AUTHORIZED || e.code == J_ENTRY_REJECTED || e.code == J_SETUP_CANCELLED ||
                        e.code == J_TRADE_FILLED || e.code == J_TRADE_CLOSED || e.code == J_ASIA_FVG);
      if(important)
        {
         for(int i = OPR_LAST_MSGS - 1; i > 0; i--)
            m_lastMsg[i] = m_lastMsg[i - 1];
         m_lastMsg[0] = StratClock(e.st) + " " + txt;
        }
      bool al = false;
      if(e.code == J_OPR_FINAL)
         al = InpAlertOpr;
      if(e.code == J_BIAS || e.code == J_BIAS_BREAKOUT || e.code == J_BIAS_CONSOL)
         al = InpAlertBias;
      if(e.code == J_SWEEP)
         al = InpAlertSweep;
      if(e.code == J_ENTRY_AUTHORIZED)
         al = InpAlertEntry;
      if(e.code == J_TRADE_FILLED || e.code == J_TRADE_CLOSED)
         al = InpAlertTrade;
      if(al && !m_isTester)
        {
         string full = "OPR FVG " + _Symbol + " " + stamp + txt;
         if(InpAlertPopup)
            Alert(full);
         if(InpAlertPush)
            SendNotification(full);
         if(InpAlertSound)
            PlaySound("alert.wav");
        }
     }

   //+---------------------------------------------------------------+
   //| Persistance des OPR (redémarrage de MT5)                      |
   //+---------------------------------------------------------------+
   string            GvName(const int s, const string what)
     {
      return "OPRFVG_" + IntegerToString(InpMagic) + "_" + _Symbol + "_" + IntegerToString(s) + "_" + what;
     }

   void              SaveOpr(const int s)
     {
      GlobalVariableSet(GvName(s, "D"), (double)m_eng.opr[s].m_st.day);
      GlobalVariableSet(GvName(s, "H"), m_eng.opr[s].m_st.high);
      GlobalVariableSet(GvName(s, "L"), m_eng.opr[s].m_st.low);
     }

   void              RestoreOprLevels()
     {
      if(!InpPersistOpr)
         return;
      for(int s = 0; s < OPR_MAX_SLOTS; s++)
        {
         if(!GlobalVariableCheck(GvName(s, "D")))
            continue;
         int day = (int)GlobalVariableGet(GvName(s, "D"));
         double h = GlobalVariableGet(GvName(s, "H"));
         double l = GlobalVariableGet(GvName(s, "L"));
         if(day != m_eng.m_day)
            continue;
         int st = m_eng.opr[s].m_st.status;
         if(st == OPR_ST_FINAL)
           {
            if(MathAbs(m_eng.opr[s].m_st.high - h) > m_tick * 0.5 || MathAbs(m_eng.opr[s].m_st.low - l) > m_tick * 0.5)
               Print("OPR FVG - attention : ", m_eng.slotName[s], " recalculé (", Px(m_eng.opr[s].m_st.high), "/", Px(m_eng.opr[s].m_st.low),
                     ") différent de la sauvegarde (", Px(h), "/", Px(l), ") : l'historique du broker a changé, le recalcul est conservé");
           }
         else
            if(m_eng.RestoreOpr(s, day, h, l))
              {
               Print("OPR FVG: ", m_eng.slotName[s], " restauré depuis la sauvegarde (historique insuffisant) : ", Px(h), " / ", Px(l));
               for(int i = 0; i < m_eng.jr.m_count; i++)
                  OnEngineEvent(m_eng.jr.m_ev[i]);
               m_eng.jr.Clear();
              }
        }
     }

   //+---------------------------------------------------------------+
   //| Module 7 : ordres et risque                                   |
   //+---------------------------------------------------------------+
   bool              IsOurs(const string sym, const long magic) { return (sym == _Symbol && magic == InpMagic); }

   long              IdFromComment(const string cmt)
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

   int               CountPositions()
     {
      int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk != 0 && IsOurs(PositionGetString(POSITION_SYMBOL), PositionGetInteger(POSITION_MAGIC)))
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
         if(tk != 0 && IsOurs(OrderGetString(ORDER_SYMBOL), OrderGetInteger(ORDER_MAGIC)))
            n++;
        }
      return n;
     }

   //--- ordre en attente d'un OPR (slot = id % 4)
   bool              FindPending(const int slot, ulong &ticket, long &setup)
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong tk = OrderGetTicket(i);
         if(tk == 0 || !IsOurs(OrderGetString(ORDER_SYMBOL), OrderGetInteger(ORDER_MAGIC)))
            continue;
         long id = IdFromComment(OrderGetString(ORDER_COMMENT));
         if(id <= 0 || (int)(id % 4) != slot)
            continue;
         ticket = tk;
         setup  = id;
         return true;
        }
      return false;
     }

   void              DeletePendings(const int slot)
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong tk = OrderGetTicket(i);
         if(tk == 0 || !IsOurs(OrderGetString(ORDER_SYMBOL), OrderGetInteger(ORDER_MAGIC)))
            continue;
         long id = IdFromComment(OrderGetString(ORDER_COMMENT));
         if(slot >= 0 && (id <= 0 || (int)(id % 4) != slot))
            continue;
         if(id > 0)
           {
            int s = (int)(id % 4);
            if(m_pendTicket[s] == tk)
              {
               m_pendTicket[s] = 0;
               m_pendSetup[s]  = 0;
              }
           }
         if(!m_trade.OrderDelete(tk))
            Status("échec suppression de l'ordre #" + IntegerToString((long)tk) + " : " + m_trade.ResultRetcodeDescription());
        }
     }

   bool              IsConsumed(const long id)
     {
      for(int i = ArraySize(m_consumed) - 1; i >= 0; i--)
         if(m_consumed[i] == id)
            return true;
      return false;
     }

   void              Consume(const long id)
     {
      if(id == 0 || IsConsumed(id))
         return;
      int n = ArraySize(m_consumed);
      if(n >= 256)
        {
         for(int i = 0; i < n - 1; i++)
            m_consumed[i] = m_consumed[i + 1];
         n--;
        }
      ArrayResize(m_consumed, n + 1);
      m_consumed[n] = id;
     }

   //--- après un redémarrage : reprise des ordres en attente, setups déjà exécutés marqués consommés
   void              AdoptState()
     {
      for(int s = 0; s < OPR_MAX_SLOTS; s++)
        {
         ulong tk = 0;
         long id = 0;
         if(FindPending(s, tk, id))
           {
            m_pendTicket[s] = tk;
            m_pendSetup[s]  = id;
           }
        }
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong pt = PositionGetTicket(i);
         if(pt != 0 && IsOurs(PositionGetString(POSITION_SYMBOL), PositionGetInteger(POSITION_MAGIC)))
            Consume(IdFromComment(PositionGetString(POSITION_COMMENT)));
        }
      datetime now = TimeCurrent();
      if(HistorySelect(now - 3 * 86400, now + 60))
        {
         int n = HistoryDealsTotal();
         for(int i = 0; i < n; i++)
           {
            ulong d = HistoryDealGetTicket(i);
            if(d == 0 || !IsOurs(HistoryDealGetString(d, DEAL_SYMBOL), HistoryDealGetInteger(d, DEAL_MAGIC)))
               continue;
            if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
               Consume(IdFromComment(HistoryDealGetString(d, DEAL_COMMENT)));
           }
        }
     }

   void              RefreshDaily()
     {
      if(!m_live)
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
         if(d == 0 || !IsOurs(HistoryDealGetString(d, DEAL_SYMBOL), HistoryDealGetInteger(d, DEAL_MAGIC)))
            continue;
         if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
            m_dayTrades++;
         m_dayPnL += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_COMMISSION);
        }
     }

   double            ComputeLots(const int dir, const double entry, const double stop)
     {
      double lots = InpFixedLots;
      ENUM_ORDER_TYPE ot = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(InpLotMode == OPR_LOT_RISK)
        {
         double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPct / 100.0;
         double pl = 0.0;
         double lossPerLot = 0.0;
         if(OrderCalcProfit(ot, _Symbol, 1.0, entry, stop, pl) && pl < 0.0)
            lossPerLot = -pl;
         else
            lossPerLot = MathAbs(entry - stop) / m_tick * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
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

   bool              DailyOk()
     {
      if(InpMaxTradesDay > 0 && m_dayTrades >= InpMaxTradesDay)
         return false;
      return true;
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
      double lvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

      for(int s = 0; s < OPR_MAX_SLOTS; s++)
        {
         //--- l'ordre suivi a disparu : exécuté (ou retiré à la main) -> setup consommé
         if(m_pendTicket[s] != 0 && !OrderSelect(m_pendTicket[s]))
           {
            Consume(m_pendSetup[s]);
            Status(m_eng.slotName[s] + " : ordre limite #" + IntegerToString((long)m_pendTicket[s]) + " exécuté ou retiré");
            m_pendTicket[s] = 0;
            m_pendSetup[s]  = 0;
            RefreshDaily();
           }

         bool armed = (m_eng.su[s].state == SU_ARMED);
         long id = m_eng.su[s].setupId;
         int dir = m_eng.su[s].dir;
         ulong pt = 0;
         long pid = 0;
         bool hasPend = FindPending(s, pt, pid);

         //--- règle du PDF Macro : « si ta cible est prise avant que le marché t'ait donné une entrée, pas de trade »
         if(armed && !IsConsumed(id))
           {
            bool tpHit = (dir < 0) ? (tk.bid <= m_eng.su[s].tp) : (tk.ask >= m_eng.su[s].tp);
            if(tpHit)
              {
               Consume(id);
               if(hasPend)
                  DeletePendings(s);
               Status(m_eng.slotName[s] + " : cible atteinte avant l'entrée, ordre annulé");
               continue;
              }
           }

         bool want = armed && !IsConsumed(id) && CountPositions() < InpMaxOpenTrades && DailyOk();
         if(want && InpMaxSpread > 0.0 && (tk.ask - tk.bid) > InpMaxSpread)
            want = false;
         if(!want)
           {
            if(hasPend)
               DeletePendings(s);
            continue;
           }
         if(hasPend)
           {
            if(pid == id)
              {
               m_pendTicket[s] = pt;
               m_pendSetup[s]  = id;
               continue;
              }
            DeletePendings(s);
           }

         //--- arrondi au tick dans le sens qui garde le déclenchement identique au modèle book
         double entry  = (dir < 0) ? NormUp(m_eng.su[s].entry) : NormDown(m_eng.su[s].entry);
         double stop   = (dir < 0) ? NormUp(m_eng.su[s].sl) : NormDown(m_eng.su[s].sl);
         double target = (dir < 0) ? NormDown(m_eng.su[s].tp) : NormUp(m_eng.su[s].tp);
         double risk   = MathAbs(entry - stop);
         string cmt    = InpComment + " " + IntegerToString(id);
         bool crossed  = (dir < 0) ? (tk.bid >= entry) : (tk.ask <= entry);
         if(crossed)
           {
            double px = (dir < 0) ? tk.bid : tk.ask;
            double chase = (dir < 0) ? (px - entry) : (entry - px);
            bool pastStop = (dir < 0) ? (px >= stop - lvl) : (px <= stop + lvl);
            Consume(id);
            if(chase > InpMaxChaseR * risk || pastStop)
              {
               Status(m_eng.slotName[s] + " : setup manqué, prix " + Px(px) + " trop loin de l'entrée " + Px(entry));
               continue;
              }
            double lotsM = ComputeLots(dir, px, stop);
            if(lotsM <= 0.0)
              {
               Status(m_eng.slotName[s] + " : volume nul (risque trop faible ou marge insuffisante)");
               continue;
              }
            bool okM = (dir < 0) ? m_trade.Sell(lotsM, _Symbol, 0.0, stop, target, cmt) : m_trade.Buy(lotsM, _Symbol, 0.0, stop, target, cmt);
            Status(m_eng.slotName[s] + (okM ? StringFormat(" : %s au marché %.2f lots @ %s SL %s TP %s", dir < 0 ? "SELL" : "BUY", lotsM, Px(px), Px(stop), Px(target))
                                      : " : échec de l'ordre au marché, " + m_trade.ResultRetcodeDescription()));
            RefreshDaily();
            continue;
           }
         if((dir < 0) ? (entry - tk.bid < lvl) : (tk.ask - entry < lvl))
            continue;
         if((dir < 0) ? (stop - entry < lvl || entry - target < lvl) : (entry - stop < lvl || target - entry < lvl))
           {
            Consume(id);
            Status(m_eng.slotName[s] + " : stops trop proches du prix d'entrée pour le broker");
            continue;
           }
         double lots = ComputeLots(dir, entry, stop);
         if(lots <= 0.0)
           {
            Consume(id);
            Status(m_eng.slotName[s] + " : volume nul (risque trop faible ou marge insuffisante)");
            continue;
           }
         if(SendLimit(dir, lots, entry, stop, target, cmt))
           {
            m_pendTicket[s] = m_trade.ResultOrder();
            m_pendSetup[s]  = id;
            m_failCount     = 0;
            Status(m_eng.slotName[s] + StringFormat(" : %s LIMIT %.2f lots @ %s SL %s TP %s", dir < 0 ? "SELL" : "BUY", lots, Px(entry), Px(stop), Px(target)));
           }
         else
           {
            if(m_failSetup != id)
              {
               m_failSetup = id;
               m_failCount = 0;
              }
            m_failCount++;
            Status(m_eng.slotName[s] + " : échec de l'ordre limite (" + IntegerToString(m_failCount) + "/3), " + m_trade.ResultRetcodeDescription());
            if(m_failCount >= 3)
               Consume(id);
           }
        }
     }

   //+---------------------------------------------------------------+
   //| Dessin                                                        |
   //+---------------------------------------------------------------+
   string            DayPfx(const int day) { return m_pfx + IntegerToString(day) + "_"; }

   void              TrackDay(const int day)
     {
      int n = ArraySize(m_drawDays);
      for(int i = 0; i < n; i++)
         if(m_drawDays[i] == day)
            return;
      ArrayResize(m_drawDays, n + 1);
      m_drawDays[n] = day;
      n++;
      int keep = MathMax(InpDaysDrawn, 1);
      while(n > keep)
        {
         ObjectsDeleteAll(0, DayPfx(m_drawDays[0]));
         for(int i = 0; i < n - 1; i++)
            m_drawDays[i] = m_drawDays[i + 1];
         n--;
         ArrayResize(m_drawDays, n);
        }
     }

   void              ObjCommon(const string name, const string tip)
     {
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
     }

   void              Seg(const string name, const datetime t1, const datetime t2, const double p, const color col, const int width,
                         const ENUM_LINE_STYLE style, const string tip)
     {
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_TREND, 0, t1, p, t2, p);
      else
        {
         ObjectMove(0, name, 0, t1, p);
         ObjectMove(0, name, 1, t2, p);
        }
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjCommon(name, tip);
     }

   void              Box(const string name, const datetime t1, const double p1, const datetime t2, const double p2, const color col,
                         const bool fill, const string tip)
     {
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      else
        {
         ObjectMove(0, name, 0, t1, p1);
         ObjectMove(0, name, 1, t2, p2);
        }
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_FILL, fill);
      ObjectSetInteger(0, name, OBJPROP_BACK, fill);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjCommon(name, tip);
     }

   void              Txt(const string name, const datetime t, const double p, const string txt, const color col, const ENUM_ANCHOR_POINT anchor)
     {
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
      ObjectSetString(0, name, OBJPROP_TEXT, txt);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      ObjCommon(name, txt);
     }

   datetime          Srv(const long st) { return (datetime)m_eng.SrvOf(st); }

   //--- fin de la journée de session = début de la suivante
   datetime          DayEndSrv() { return Srv(m_eng.tm.SessionAbs(m_eng.m_day + 1, m_eng.cfg.dayStartMin)); }

   void              Draw(const OJEvent &e)
     {
      if(!m_draw)
         return;
      int day = m_eng.m_day;
      TrackDay(day);
      string p = DayPfx(day);
      int s = e.slot;
      switch(e.code)
        {
         case J_OPR_FINAL:
           {
            if(s < 0)
               break;
            ORangeState r;
            r = m_eng.opr[s].m_st;
            datetime t1 = Srv(r.startT);
            datetime t2 = Srv(r.endT);
            datetime tEnd = (m_eng.su[s].winE > 0) ? Srv(m_eng.su[s].winE) : DayEndSrv();
            string nm = p + "O" + IntegerToString(s) + "_";
            Box(nm + "box", t1, r.high, t2, r.low, InpColAsia, false, m_eng.slotName[s]);
            Seg(nm + "hi", t2, tEnd, r.high, InpColOprHigh, 2, STYLE_SOLID, m_eng.slotName[s] + " High " + Px(r.high));
            Seg(nm + "lo", t2, tEnd, r.low, InpColOprLow, 2, STYLE_SOLID, m_eng.slotName[s] + " Low " + Px(r.low));
            Txt(nm + "tx", t1, r.high, m_eng.slotName[s], InpColText, ANCHOR_LEFT_LOWER);
            if(m_eng.cfg.slots[s].tradeEnabled && m_eng.su[s].winS > 0)
              {
               double ks[5];
               ks[0] = 1.0;
               ks[1] = 2.0;
               ks[2] = m_eng.cfg.tpStd;
               ks[3] = 3.0;
               ks[4] = 4.0;
               datetime ws = Srv(m_eng.su[s].winS);
               for(int i = 0; i < 5; i++)
                 {
                  double up = OprStdLevel(r, 1, ks[i]);
                  double dn = OprStdLevel(r, -1, ks[i]);
                  string kk = DoubleToString(ks[i], 1);
                  Seg(nm + "su" + IntegerToString(i), ws, tEnd, up, InpColStd, 1, STYLE_DOT, "+" + kk + " STD " + Px(up));
                  Seg(nm + "sd" + IntegerToString(i), ws, tEnd, dn, InpColStd, 1, STYLE_DOT, "-" + kk + " STD " + Px(dn));
                 }
              }
            break;
           }
         case J_ASIA_FINAL:
            Box(p + "asia", Srv(m_eng.asia.m_st.startT), m_eng.asia.m_st.high, Srv(m_eng.asia.m_st.endT), m_eng.asia.m_st.low, InpColAsia, false,
                "Plage asiatique");
            break;
         case J_ASIA_FVG:
         case J_MIDNIGHT_FVG:
           {
            int fi = m_eng.FindFvgIdx(e.id);
            if(fi < 0)
               break;
            color col = (e.code == J_ASIA_FVG) ? InpColAsiaFvg : InpColMidFvg;
            string lab = (e.code == J_ASIA_FVG) ? "FPFVG M15 Asie" : "FPFVG M1 minuit";
            Box(p + (e.code == J_ASIA_FVG ? "afvg" : "mfvg"), m_eng.fvgs.m_list[fi].c1Srv, e.p1, DayEndSrv(), e.p2, col, false, lab);
            break;
           }
         case J_SWEEP:
           {
            string nm = p + "sw" + IntegerToString(s) + "_" + IntegerToString((long)e.srv);
            if(ObjectFind(0, nm) < 0)
               ObjectCreate(0, nm, OBJ_ARROW, 0, e.srv, e.p1);
            ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, 251);
            ObjectSetInteger(0, nm, OBJPROP_COLOR, InpColText);
            ObjCommon(nm, "liquidité prise " + Px(e.p1));
            break;
           }
         case J_ENTRY_AUTHORIZED:
           {
            int fi = m_eng.FindFvgIdx(m_eng.su[s].fvgId);
            datetime t1 = (fi >= 0) ? m_eng.fvgs.m_list[fi].c1Srv : e.srv;
            datetime t2 = Srv(m_eng.su[s].winE);
            string nm = p + "E" + IntegerToString(e.id) + "_";
            Box(nm + "fvg", t1, m_eng.su[s].fvgHi, t2, m_eng.su[s].fvgLo, InpColEntryFvg, false, "FVG d'entrée");
            Seg(nm + "en", e.srv, t2, e.p1, InpColText, 1, STYLE_SOLID, "entrée " + Px(e.p1));
            Seg(nm + "sl", e.srv, t2, e.p2, InpColOprLow, 1, STYLE_DASH, "stop " + Px(e.p2));
            Seg(nm + "tp", e.srv, t2, e.p3, InpColOprHigh, 1, STYLE_DASH, "cible " + Px(e.p3));
            break;
           }
         case J_TRADE_FILLED:
           {
            string nm = p + "T" + IntegerToString(e.id) + "_";
            datetime t2 = (datetime)((long)e.srv + 60);
            Box(nm + "tp", e.srv, e.p1, t2, e.p3, InpColTP, true, "cible " + Px(e.p3));
            Box(nm + "sl", e.srv, e.p1, t2, e.p2, InpColSL, true, "stop " + Px(e.p2));
            Txt(nm + "lb", e.srv, e.p2, OprDirText(e.dir), InpColText, e.dir < 0 ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
            break;
           }
         case J_TRADE_CLOSED:
           {
            string nm = p + "T" + IntegerToString(e.id) + "_";
            datetime t2 = (datetime)((long)e.srv + 60);
            if(ObjectFind(0, nm + "tp") >= 0)
              {
               ObjectMove(0, nm + "tp", 1, t2, ObjectGetDouble(0, nm + "tp", OBJPROP_PRICE, 1));
               ObjectMove(0, nm + "sl", 1, t2, ObjectGetDouble(0, nm + "sl", OBJPROP_PRICE, 1));
              }
            Txt(nm + "rs", t2, e.p1, StringFormat("%+.2fR", e.p4), e.p4 > 0.0 ? clrLimeGreen : clrTomato, ANCHOR_LEFT);
            break;
           }
         default:
            break;
        }
     }

   //+---------------------------------------------------------------+
   //| Tableau                                                       |
   //+---------------------------------------------------------------+
   color             ThBg()    { return InpTheme == OPR_THEME_DARK ? C'18,20,26' : C'250,250,252'; }
   color             ThBorder(){ return InpTheme == OPR_THEME_DARK ? C'60,64,74' : C'200,200,210'; }
   color             ThText()  { return InpTheme == OPR_THEME_DARK ? C'205,210,220' : C'30,30,36'; }
   color             ThHead()  { return InpTheme == OPR_THEME_DARK ? C'255,196,72' : C'20,90,200'; }
   color             ThPos()   { return InpTheme == OPR_THEME_DARK ? C'80,200,120' : C'0,140,70'; }
   color             ThNeg()   { return InpTheme == OPR_THEME_DARK ? C'240,95,90' : C'200,40,40'; }
   color             ThMuted() { return InpTheme == OPR_THEME_DARK ? C'140,145,158' : C'110,110,122'; }
   int               RowH()    { return InpFontSize * 2 + 2; }
   int               TableW()  { return InpFontSize * 52; }

   void              TableLabel(const string name, const int x, const int y, const ENUM_ANCHOR_POINT anchor)
     {
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, InpCorner == OPR_CORNER_TR ? CORNER_RIGHT_UPPER : CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
      ObjCommon(name, "");
     }

   void              TableRow(const int row, const string key, const string val, const color kc, const color vc)
     {
      int margin = 10;
      int pad = 8;
      int w = TableW();
      int y = margin + pad / 2 + row * RowH();
      string kn = m_pfx + "TB_k" + IntegerToString(row);
      string vn = m_pfx + "TB_v" + IntegerToString(row);
      if(InpCorner == OPR_CORNER_TR)
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

   string            OprCell(const int s)
     {
      int st = m_eng.opr[s].m_st.status;
      if(st == OPR_ST_FINAL)
         return "H " + Px(m_eng.opr[s].m_st.high) + "  L " + Px(m_eng.opr[s].m_st.low) + (m_eng.opr[s].m_st.restored ? " (restauré)" : "");
      if(st == OPR_ST_BUILDING)
         return "en calcul  H " + Px(m_eng.opr[s].m_st.high) + "  L " + Px(m_eng.opr[s].m_st.low);
      return OprRangeStatusText(st);
     }

   string            FvgCell(const long id)
     {
      int fi = m_eng.FindFvgIdx(id);
      if(fi < 0)
         return "-";
      return OprFvgKind(m_eng.fvgs.m_list[fi].dir) + Px(m_eng.fvgs.m_list[fi].lo) + "-" + Px(m_eng.fvgs.m_list[fi].hi) + "  " +
             OprFvgStatusText(m_eng.fvgs.m_list[fi].status);
     }

   void              UpdateTable()
     {
      if(!m_table)
         return;
      int margin = 10;
      int w = TableW();
      string bg = m_pfx + "TB_bg";
      if(ObjectFind(0, bg) < 0)
         ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER, InpCorner == OPR_CORNER_TR ? CORNER_RIGHT_UPPER : CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, InpCorner == OPR_CORNER_TR ? margin + w : margin);
      ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, margin);
      ObjectSetInteger(0, bg, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, bg, OBJPROP_YSIZE, OPR_TABLE_ROWS * RowH() + 8);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, ThBg());
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_COLOR, ThBorder());
      ObjectSetInteger(0, bg, OBJPROP_ZORDER, 5);
      ObjCommon(bg, "");

      color tx = ThText();
      color hd = ThHead();
      color mu = ThMuted();
      color ps = ThPos();
      color ng = ThNeg();
      int r = 0;
      long nowSt = m_eng.tm.StratTime(TimeCurrent());
      TableRow(r++, "OPR + FVG EA", _Symbol + "  " + StratClock(nowSt) + " " + TzName(), hd, hd);
      for(int s = 0; s < OPR_MAX_SLOTS; s++)
        {
         if(m_eng.opr[s].m_st.status == OPR_ST_NONE)
            continue;
         int cx = m_eng.ctx[s];
         string cs = (cx == CTX_ABOVE) ? "  au-dessus" : (cx == CTX_BELOW ? "  dessous" : (cx == CTX_INSIDE ? "  dedans" : ""));
         TableRow(r++, m_eng.slotName[s], OprCell(s) + cs, tx, m_eng.opr[s].IsFinal() ? tx : mu);
        }
      string asiaTxt = m_eng.asia.IsFinal() ? "H " + Px(m_eng.asia.m_st.high) + "  L " + Px(m_eng.asia.m_st.low) : OprRangeStatusText(m_eng.asia.m_st.status);
      TableRow(r++, "Range asiatique", asiaTxt, tx, mu);
      TableRow(r++, "FPFVG M15 Asie", FvgCell(m_eng.m_asiaFvgId), tx, InpColAsiaFvg);
      TableRow(r++, "FPFVG M1 minuit", FvgCell(m_eng.m_midFvgId), tx, InpColMidFvg);
      if(m_eng.opr[0].IsFinal())
         TableRow(r++, StringFormat("STD %.1f", m_eng.cfg.tpStd), "achat " + Px(OprStdLevel(m_eng.opr[0].m_st, 1, m_eng.cfg.tpStd)) +
                  "  vente " + Px(OprStdLevel(m_eng.opr[0].m_st, -1, m_eng.cfg.tpStd)), tx, InpColStd);
      for(int s = 0; s < OPR_MAX_SLOTS; s++)
        {
         if(!m_eng.cfg.slots[s].tradeEnabled)
            continue;
         string b = (m_eng.su[s].dir > 0) ? "ACHAT" : (m_eng.su[s].dir < 0 ? "VENTE" : (m_eng.su[s].consol ? "consolidation" : "-"));
         TableRow(r++, "Biais " + OprRangeText(m_eng.cfg.slots[s].window), b, tx, m_eng.su[s].dir > 0 ? ps : (m_eng.su[s].dir < 0 ? ng : mu));
         string state = OprSetupStateText(m_eng.su[s].state);
         if(m_eng.su[s].state == SU_ARMED)
            state = "ARMÉ E " + Px(m_eng.su[s].entry) + " S " + Px(m_eng.su[s].sl) + " T " + Px(m_eng.su[s].tp);
         TableRow(r++, "Setup", state, tx, m_eng.su[s].state == SU_ARMED ? hd : tx);
         string mac = "";
         for(int i = 0; i < m_eng.cfg.slots[s].macroCount; i++)
            mac += (i > 0 ? " " : "") + OprHHMM(m_eng.cfg.slots[s].macros[i].startMin) + (m_eng.su[s].macroUsed[i] ? "*" : "");
         TableRow(r++, "Macros (* = tradée)", mac, tx, mu);
        }
      OStats st;
      st = m_eng.stats;
      TableRow(r++, "Statistiques (book)", "", hd, hd);
      TableRow(r++, "Trades", IntegerToString(st.trades) + "  (" + IntegerToString(st.wins) + "W / " + IntegerToString(st.losses) + "L)  " +
               StringFormat("%+.2fR", st.netR), tx, st.netR >= 0.0 ? ps : ng);
      TableRow(r++, "Setups armés / sweeps", IntegerToString(st.armed) + " / " + IntegerToString(st.sweeps), tx, mu);
      TableRow(r++, "Rejets", "sans sweep " + IntegerToString(st.rejected[R_NO_SWEEP]) + "  hors macro " + IntegerToString(st.rejected[R_OUTSIDE_MACRO]) +
               "  cible " + IntegerToString(st.rejected[R_TARGET_REACHED]), tx, mu);
      TableRow(r++, "Compte", IntegerToString(CountPositions()) + " pos. / " + IntegerToString(CountPendings()) + " ordres  " +
               DoubleToString(m_dayPnL, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY), tx, m_dayPnL >= 0.0 ? ps : ng);
      TableRow(r++, "Statut", m_status, tx, mu);
      for(int i = 0; i < OPR_LAST_MSGS && r < OPR_TABLE_ROWS; i++)
         TableRow(r++, i == 0 ? "Journal" : "", m_lastMsg[i], mu, mu);
      while(r < OPR_TABLE_ROWS)
         TableRow(r++, "", "", mu, mu);
     }
  };

COprEA g_ea;

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

//+------------------------------------------------------------------+
//|                                                   OPR_Config.mqh |
//|  Configuration centralisée de la stratégie OPR + FVG.            |
//|  Toutes les plages horaires sont exprimées dans le fuseau de la  |
//|  stratégie (New York par défaut, cf. PDF « London OPR Strategy » :|
//|  « entre 2:50 et 4:10 (heure de New York) »).                    |
//+------------------------------------------------------------------+
#ifndef OPR_CONFIG_MQH
#define OPR_CONFIG_MQH

#define OPR_MAX_SLOTS   4          // nombre d'OPR configurables
#define OPR_MAX_MACROS  6          // macros par fenêtre de trading
#define OPR_BASE_SEC    60         // bougies de base : M1

//--- fuseau des horaires de la stratégie
enum ENUM_OPR_STRAT_TZ
  {
   OPR_STZ_NEW_YORK = 0,   // New York (EST/EDT)
   OPR_STZ_LONDON   = 1,   // Londres (GMT/BST)
   OPR_STZ_PARIS    = 2,   // Paris (CET/CEST)
   OPR_STZ_UTC      = 3,   // UTC
   OPR_STZ_SERVER   = 4    // Heure du serveur MT5
  };

//--- fuseau du serveur du broker
enum ENUM_OPR_SERVER_TZ
  {
   OPR_SRV_AUTO       = 0, // Auto (mesuré en live ; à préciser dans le testeur)
   OPR_SRV_GMT_US_DST = 1, // GMT+x en hiver, +1 h pendant le DST US (ex. GMT+2/+3)
   OPR_SRV_GMT_EU_DST = 2, // GMT+x en hiver, +1 h pendant le DST européen
   OPR_SRV_GMT_FIXED  = 3  // GMT+x fixe toute l'année
  };

//--- niveau d'entrée dans le FVG
enum ENUM_OPR_ENTRY_LEVEL
  {
   OPR_ENTRY_EDGE = 0,     // Bord du FVG (« le prix revient dans le FVG »)
   OPR_ENTRY_CE   = 1      // CE (milieu du FVG)
  };

//--- règle « FVG présenté pendant la plage asiatique »
enum ENUM_OPR_ASIA_RULE
  {
   OPR_ASIA_C2_IN_RANGE  = 0, // Bougie du gap (2e) dans la plage
   OPR_ASIA_ALL_IN_RANGE = 1, // Les 3 bougies dans la plage
   OPR_ASIA_C3_IN_RANGE  = 2  // Bougie de confirmation (3e) clôturée dans la plage
  };

//--- timeframe du FVG d'entrée
enum ENUM_OPR_ENTRY_TF
  {
   OPR_TF_M1  = 1,         // M1
   OPR_TF_M5  = 5,         // M5
   OPR_TF_M15 = 15         // M15
  };

//+------------------------------------------------------------------+
//| Plage horaire [début, fin) en minutes du jour, peut traverser    |
//| minuit. valid = false : plage non configurée.                    |
//+------------------------------------------------------------------+
struct OPRTimeRange
  {
   bool              valid;
   int               startMin;
   int               endMin;

   void              Clear() { valid = false; startMin = 0; endMin = 0; }
   void              Set(const int s, const int e) { valid = (s != e); startMin = s; endMin = e; }
   int               Length() const { return valid ? (endMin - startMin + 1440) % 1440 : 0; }
   bool              Contains(const int m) const
     {
      if(!valid)
         return false;
      if(startMin < endMin)
         return (m >= startMin && m < endMin);
      return (m >= startMin || m < endMin);
     }
  };

//+------------------------------------------------------------------+
//| Un OPR : sa plage de calcul et, s'il est tradé, sa fenêtre de    |
//| trading et ses macros.                                           |
//+------------------------------------------------------------------+
struct OPRSlotCfg
  {
   OPRTimeRange      calc;          // plage de calcul High/Low (calc.valid = false : OPR désactivé)
   bool              tradeEnabled;  // modèle d'entrée actif pour cet OPR
   OPRTimeRange      window;        // fenêtre de trading (le biais est lu à son ouverture)
   int               macroCount;
   OPRTimeRange      macros[OPR_MAX_MACROS];

   void              Clear()
     {
      calc.Clear();
      tradeEnabled = false;
      window.Clear();
      macroCount = 0;
      for(int i = 0; i < OPR_MAX_MACROS; i++)
         macros[i].Clear();
     }
  };

//+------------------------------------------------------------------+
//| Configuration complète du moteur                                 |
//+------------------------------------------------------------------+
struct OPRConfig
  {
   //--- fuseaux
   int               stratTz;
   int               serverMode;
   int               serverGmtSec;      // décalage GMT du serveur (hiver) ou mesuré (auto)
   int               dayStartMin;       // début de la journée de session (heure stratégie)

   //--- plages
   OPRSlotCfg        slots[OPR_MAX_SLOTS];
   OPRTimeRange      asia;              // plage asiatique
   OPRTimeRange      london;            // session de Londres (information + recherche du FPFVG de minuit)
   OPRTimeRange      observe;           // fenêtre d'observation (information uniquement)

   //--- FVG de référence
   int               asiaRule;
   double            asiaMinGapTicks;
   double            midnightMinGapTicks;

   //--- FVG d'entrée
   int               entryTfMin;
   int               entryLevel;
   double            minFvgTicks;

   //--- liquidité
   bool              liqM1;
   int               liqPivotM1;
   bool              liqM15;
   int               liqPivotM15;
   bool              liqAsia;

   //--- modèle d'entrée
   bool              requireMacro;
   bool              oneTradePerMacro;
   bool              consolRequireSweep;
   double            stopBufferTicks;
   double            tpStd;
   int               graceMin;
   double            minStop;
   double            maxStop;
   int               maxOpenTrades;
   int               maxTradesDay;

   //--- symbole
   double            tickSize;

   void              Defaults()
     {
      stratTz      = OPR_STZ_NEW_YORK;
      serverMode   = OPR_SRV_GMT_US_DST;
      serverGmtSec = 2 * 3600;
      dayStartMin  = 18 * 60;

      for(int i = 0; i < OPR_MAX_SLOTS; i++)
         slots[i].Clear();
      //--- OPR principal de Londres (Midnight Opening Range) : 00:00-00:30, fenêtre 02:50-04:10
      slots[0].calc.Set(0, 30);
      slots[0].tradeEnabled = true;
      slots[0].window.Set(2 * 60 + 50, 4 * 60 + 10);
      slots[0].macroCount = 3;
      slots[0].macros[0].Set(2 * 60 + 50, 3 * 60 + 10);
      slots[0].macros[1].Set(3 * 60 + 20, 3 * 60 + 40);
      slots[0].macros[2].Set(3 * 60 + 50, 4 * 60 + 10);
      //--- autres OPR : niveaux calculés, aucune règle d'entrée documentée
      slots[1].calc.Set(7 * 60, 7 * 60 + 30);
      slots[2].calc.Set(9 * 60 + 30, 10 * 60);
      slots[3].calc.Set(13 * 60 + 30, 14 * 60);

      asia.Set(20 * 60, 0);
      london.Set(0, 6 * 60);
      observe.Set(2 * 60 + 50, 3 * 60 + 10);

      asiaRule            = OPR_ASIA_C2_IN_RANGE;
      asiaMinGapTicks     = 1.0;
      midnightMinGapTicks = 1.0;

      entryTfMin  = OPR_TF_M1;
      entryLevel  = OPR_ENTRY_EDGE;
      minFvgTicks = 1.0;

      liqM1       = true;
      liqPivotM1  = 1;
      liqM15      = true;
      liqPivotM15 = 1;
      liqAsia     = true;

      requireMacro       = true;
      oneTradePerMacro   = true;
      consolRequireSweep = true;
      stopBufferTicks    = 1.0;
      tpStd              = 2.0;
      graceMin           = 0;
      minStop            = 0.0;
      maxStop            = 0.0;
      maxOpenTrades      = 1;
      maxTradesDay       = 0;

      tickSize = 0.25;
     }
  };

#endif // OPR_CONFIG_MQH
//+------------------------------------------------------------------+

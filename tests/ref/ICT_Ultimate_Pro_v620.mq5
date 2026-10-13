//+------------------------------------------------------------------+
//|  ICT_Ultimate_Pro_AllInOne.mq5                                    |
//|  Version mono-fichier : a copier dans MQL5\Experts et compiler.   |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                              ICT_Ultimate_Pro.mq5 |
//|  v6.20 - Silver Bullet + Macro Breaker ICT, specialise or (XAUUSD)|
//|  Deux setups, un seul pipeline de decision :                      |
//|   - Silver Bullet (M5, fenetres 03-04 / 10-11 / 14-15 NY)         |
//|   - Macro Breaker (M1, macros ICT xx:20-xx:40 / xx:50-xx:10)      |
//|                                                                   |
//|  NOUVEAUTES v6.20 :                                               |
//|   1. CORRECTIF : les niveaux de reference (OPR, TBR, NDOG, NWOG,  |
//|      cibles SD) etaient enregistres avec time = maintenant, ce    |
//|      qui rendait leur sweep IMPOSSIBLE dans FindSweeps.           |
//|   2. Entree sur la 1ere FVG du displacement (Silver Bullet).      |
//|   3. Breaker deja touche : accepte tant qu'il n'est pas viole.    |
//|   4. Corps directionnel du FVG rendu optionnel.                   |
//|   5. Seuil de retracement parametrable (au lieu du mur a 50 %).   |
//|   6. Deuxieme passe "relachee" pour couvrir chaque fenetre/macro. |
//|   7. Plafond de spread auto-ajuste au nombre de decimales.        |
//|   8. Fenetre de formation du breaker elargie avant la macro.      |
//+------------------------------------------------------------------+
#property copyright   "ICT Ultimate Pro"
#property link        "https://www.mql5.com"
#property version     "6.20"
#property description "Silver Bullet (1ere FVG) + Macro Breaker ICT pour l'or : sweep -> MSS/breaker -> entree, risque defini en amont, apprentissage par buckets."

//--- Decommenter pour activer la protection par licence (necessite SecurityManager.mqh dans ce dossier)
//#define ICT_USE_LICENSE
#ifdef ICT_USE_LICENSE
   #include "SecurityManager.mqh"
#endif

#include <Trade\Trade.mqh>

//====================================================================
//  MODULE : ICTPro_Common.mqh
//====================================================================
#ifndef ICTPRO_COMMON_MQH
#define ICTPRO_COMMON_MQH

#define ICTPRO_VERSION    "6.20"
#define ICTPRO_FEATURES   20
#define ICTPRO_OBJ_PREFIX "ICTPro_"

//--- Direction d'un setup / d'un biais
enum ENUM_ICT_DIR
{
   DIR_NONE = 0,
   DIR_BUY  = 1,
   DIR_SELL = -1
};

//--- Type de setup
enum ENUM_SETUP_TYPE
{
   SETUP_SILVER_BULLET = 0,  // Silver Bullet (M5, fenetres 1h)
   SETUP_MACRO_BREAKER = 1   // Macro Breaker (M1, macros 20 min)
};

//--- Fenetres Silver Bullet (heure de New York)
enum ENUM_SB_WINDOW
{
   WIN_NONE   = 0,   // aucune
   WIN_LONDON = 1,   // 03:00-04:00 NY
   WIN_NY_AM  = 2,   // 10:00-11:00 NY
   WIN_NY_PM  = 3    // 14:00-15:00 NY
};

//--- Mode de definition du risque par trade (choisi par l'utilisateur)
enum ENUM_RISK_MODE
{
   RISK_PERCENT_EQUITY  = 0,  // % de l'equite
   RISK_PERCENT_BALANCE = 1,  // % de la balance
   RISK_FIXED_MONEY     = 2,  // montant fixe (devise du compte)
   RISK_FIXED_LOT       = 3   // lot fixe
};

//--- Mode d'entree Silver Bullet
enum ENUM_ENTRY_MODE
{
   ENTRY_FVG_TOP        = 0,  // ordre limite sur le bord du FVG
   ENTRY_FVG_CE         = 1,  // ordre limite sur le consequent encroachment (50 % du FVG)
   ENTRY_MARKET_ON_MSS  = 2,  // au marche des la confirmation MSS
   ENTRY_OB_AFTER_FVG   = 3   // attendre le rejet du FVG puis entrer sur l'order block forme
};

//--- Niveau d'entree Macro Breaker
enum ENUM_MB_ENTRY
{
   MB_ENTRY_BREAKER_EDGE = 0,  // bord du breaker (high pour un achat)
   MB_ENTRY_BREAKER_BODY = 1,  // corps du breaker
   MB_ENTRY_BREAKER_CE   = 2   // milieu du breaker
};

//--- Mode de cible
enum ENUM_TP_MODE
{
   TP_NEAREST_POOL = 0,  // pool de liquidite oppose le plus proche (RR min impose)
   TP_FIXED_RR     = 1   // RR fixe
};

//--- Mode d'apprentissage adaptatif
enum ENUM_ADAPT_MODE
{
   ADAPT_OFF            = 0,  // desactive
   ADAPT_SIZE           = 1,  // module la taille selon l'esperance du bucket
   ADAPT_SIZE_AND_GATE  = 2   // module la taille et bloque les buckets negatifs
};

//--- Types de niveaux de liquidite / reference
enum ENUM_LIQ_TYPE
{
   LIQ_PDH = 0, LIQ_PDL,
   LIQ_PWH,     LIQ_PWL,
   LIQ_ASIA_HIGH,   LIQ_ASIA_LOW,
   LIQ_LONDON_HIGH, LIQ_LONDON_LOW,
   LIQ_NYAM_HIGH,   LIQ_NYAM_LOW,
   LIQ_EQ_HIGH,     LIQ_EQ_LOW,
   LIQ_IPDA_HIGH,   LIQ_IPDA_LOW,
   LIQ_HTF_SWING_HIGH, LIQ_HTF_SWING_LOW,
   LIQ_LTF_SWING_HIGH, LIQ_LTF_SWING_LOW,
   LIQ_M1_SWING_HIGH,  LIQ_M1_SWING_LOW,
   LIQ_OPR_HIGH,   LIQ_OPR_LOW,
   LIQ_TBR_HIGH,   LIQ_TBR_LOW,
   LIQ_NDOG_HIGH,  LIQ_NDOG_LOW,
   LIQ_NWOG_HIGH,  LIQ_NWOG_LOW,
   LIQ_SD_TARGET
};

//--- Niveau de liquidite
struct SLiqLevel
{
   double        price;
   int           rank;     // 3 = PDH/PDL/PWH/PWL/IPDA, 2 = session/equal/HTF swing/OPR/NDOG, 1 = swing LTF / SD
   ENUM_LIQ_TYPE type;
   datetime      time;
   bool          isHigh;
};

//--- Sweep de liquidite detecte
struct SSweep
{
   bool          found;
   double        level;
   int           rank;
   ENUM_LIQ_TYPE type;
   datetime      levelTime;
   int           extremeIdx;        // index serie de l'extreme du sweep
   double        extreme;
   datetime      extremeTime;
   int           episodeNewestIdx;  // index de la derniere bougie sous/au-dessus du niveau
   int           episodeBars;
   double        penetrationATR;
};

//--- Market Structure Shift
struct SMSS
{
   bool     found;
   int      barIdx;
   datetime barTime;
   double   brokenLevel;
   double   dispBody;       // plus grand corps de la jambe
   double   legExtreme;     // extreme de la jambe apres le MSS
   int      legExtremeIdx;
};

//--- Fair Value Gap
struct SFVG
{
   bool     found;
   int      midIdx;
   datetime time;
   double   top;
   double   bottom;
   double   ce;
   double   size;
   bool     touched;
};

//--- Breaker block (Macro Breaker)
struct SBreaker
{
   bool     found;
   int      candleIdx;      // bougie qui a forme le swing (down-close pour un breaker haussier)
   datetime time;
   double   top;            // high de la bougie
   double   bottom;         // low de la bougie
   double   bodyTop;
   double   bodyBottom;
   double   swingLevel;     // extreme du swing casse (high pour haussier)
   int      confirmIdx;     // bougie dont le corps cloture au-dela du corps du breaker
   datetime confirmTime;
   double   dispBody;
   bool     unicorn;        // FVG a l'interieur du breaker
   double   zoneTop;        // zone d'entree retenue (breaker ou FVG dans le breaker)
   double   zoneBottom;
};

//--- Setup complet
struct SSetup
{
   bool            valid;
   ENUM_SETUP_TYPE setupType;
   ENUM_ICT_DIR    dir;
   ENUM_SB_WINDOW  window;
   datetime        windowStart;
   datetime        windowEnd;
   int             macroId;        // HHMM NY du debut de macro, 0 si aucune
   bool            macroHighProb;
   SSweep          sweep;
   SMSS            mss;
   SFVG            fvg;
   SBreaker        breaker;
   double          entry;
   double          sl;
   double          tp;
   double          rr;
   double          riskDist;
   double          legLow;
   double          legHigh;
   double          retracePct;     // retracement de la jambe au niveau de l'entree (0..1)
   double          pdPct;          // position dans le dealing range (0 = bas, 1 = haut)
   bool            inOTE;
   bool            inDiscount;
   bool            biasAligned;
   bool            inMacro;
   bool            fvgUntouched;
   bool            marketEntry;
   bool            needsOBConfirm; // ENTRY_OB_AFTER_FVG : armer, attendre le rejet du FVG
   bool            unicorn;
   bool            bpr;
   bool            refLevelHit;
   bool            trueOpenAligned;
   bool            eqWarning;
   bool            relaxed;        // v6.20 : setup issu de la 2e passe relachee
   int             dowScore;
   int             score;
   ENUM_ICT_DIR    bias;
   double          atr;
   double          atrD1;
   double          spreadPts;
   double          dispBodyATR;
   double          fvgSizeATR;
   double          trueOpen;
   int             tpSource;       // ENUM_LIQ_TYPE ou -1 pour RR fixe
   string          refLevelName;
   string          id;
   string          rejectReason;
};

//+------------------------------------------------------------------+
//| Utilitaires                                                      |
//+------------------------------------------------------------------+
string DirToStr(const ENUM_ICT_DIR d)
{
   if(d == DIR_BUY)  return "BUY";
   if(d == DIR_SELL) return "SELL";
   return "NONE";
}

string SetupTypeToStr(const ENUM_SETUP_TYPE t)
{
   return (t == SETUP_MACRO_BREAKER) ? "MB" : "SB";
}

string WindowToStr(const ENUM_SB_WINDOW w)
{
   switch(w)
   {
      case WIN_LONDON: return "LONDON";
      case WIN_NY_AM:  return "NY_AM";
      case WIN_NY_PM:  return "NY_PM";
      default:         return "NONE";
   }
}

string LiqTypeToStr(const int t)
{
   switch(t)
   {
      case LIQ_PDH: return "PDH";               case LIQ_PDL: return "PDL";
      case LIQ_PWH: return "PWH";               case LIQ_PWL: return "PWL";
      case LIQ_ASIA_HIGH: return "ASIA_H";      case LIQ_ASIA_LOW: return "ASIA_L";
      case LIQ_LONDON_HIGH: return "LONDON_H";  case LIQ_LONDON_LOW: return "LONDON_L";
      case LIQ_NYAM_HIGH: return "NYAM_H";      case LIQ_NYAM_LOW: return "NYAM_L";
      case LIQ_EQ_HIGH: return "EQH";           case LIQ_EQ_LOW: return "EQL";
      case LIQ_IPDA_HIGH: return "IPDA_H";      case LIQ_IPDA_LOW: return "IPDA_L";
      case LIQ_HTF_SWING_HIGH: return "HTF_SH"; case LIQ_HTF_SWING_LOW: return "HTF_SL";
      case LIQ_LTF_SWING_HIGH: return "LTF_SH"; case LIQ_LTF_SWING_LOW: return "LTF_SL";
      case LIQ_M1_SWING_HIGH: return "M1_SH";   case LIQ_M1_SWING_LOW: return "M1_SL";
      case LIQ_OPR_HIGH: return "OPR_H";        case LIQ_OPR_LOW: return "OPR_L";
      case LIQ_TBR_HIGH: return "TBR_H";        case LIQ_TBR_LOW: return "TBR_L";
      case LIQ_NDOG_HIGH: return "NDOG_H";      case LIQ_NDOG_LOW: return "NDOG_L";
      case LIQ_NWOG_HIGH: return "NWOG_H";      case LIQ_NWOG_LOW: return "NWOG_L";
      case LIQ_SD_TARGET: return "SD";
      case -1: return "FIXED_RR";
      default: return "UNKNOWN";
   }
}

double NormPrice(const string sym, const double p)
{
   int d = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   return NormalizeDouble(p, d);
}

bool IsTester()       { return (bool)MQLInfoInteger(MQL_TESTER); }
bool IsOptimization() { return (bool)MQLInfoInteger(MQL_OPTIMIZATION); }

double BodyOf(const MqlRates &r) { return MathAbs(r.close - r.open); }
double BodyTop(const MqlRates &r) { return MathMax(r.open, r.close); }
double BodyBottom(const MqlRates &r) { return MathMin(r.open, r.close); }

string TsToStr(const datetime t) { return TimeToString(t, TIME_DATE | TIME_MINUTES); }

//--- Nettoie une chaine pour le CSV
string CsvSafe(string s)
{
   StringReplace(s, ",", ";");
   StringReplace(s, "\"", "'");
   StringReplace(s, "\n", " ");
   StringReplace(s, "\r", " ");
   return s;
}

string D2(const double v, const int digits = 2) { return DoubleToString(v, digits); }

void ResetSetup(SSetup &s)
{
   s.valid = false;
   s.setupType = SETUP_SILVER_BULLET;
   s.dir = DIR_NONE;
   s.window = WIN_NONE;
   s.windowStart = 0;
   s.windowEnd = 0;
   s.macroId = 0;
   s.macroHighProb = false;
   ZeroMemory(s.sweep);
   ZeroMemory(s.mss);
   ZeroMemory(s.fvg);
   ZeroMemory(s.breaker);
   s.entry = 0; s.sl = 0; s.tp = 0; s.rr = 0; s.riskDist = 0;
   s.legLow = 0; s.legHigh = 0; s.retracePct = 0; s.pdPct = 0.5;
   s.inOTE = false; s.inDiscount = false; s.biasAligned = false;
   s.inMacro = false; s.fvgUntouched = false; s.marketEntry = false; s.needsOBConfirm = false;
   s.unicorn = false; s.bpr = false; s.refLevelHit = false; s.trueOpenAligned = false; s.eqWarning = false;
   s.relaxed = false;
   s.dowScore = 0;
   s.score = 0; s.bias = DIR_NONE; s.atr = 0; s.atrD1 = 0; s.spreadPts = 0;
   s.dispBodyATR = 0; s.fvgSizeATR = 0; s.trueOpen = 0; s.tpSource = -1;
   s.refLevelName = ""; s.id = ""; s.rejectReason = "";
}

//--- Vecteur de features (identique pour le journal et le modele ONNX)
void BuildFeatureVector(const SSetup &s, const int nyDayOfWeek, float &f[])
{
   ArrayResize(f, ICTPRO_FEATURES);
   f[0]  = (float)MathMin(s.score / 10.0, 1.0);
   f[1]  = (float)(s.sweep.rank / 3.0);
   f[2]  = (float)MathMin(s.dispBodyATR / 5.0, 1.0);
   f[3]  = (float)MathMin(s.fvgSizeATR / 3.0, 1.0);
   f[4]  = (float)MathMin(MathMax(s.retracePct, 0.0), 1.0);
   f[5]  = s.inOTE ? (float)1.0 : (float)0.0;
   f[6]  = (float)MathMin(s.rr / 5.0, 1.0);
   f[7]  = (float)(s.atr > 0 ? MathMin(s.spreadPts * _Point / s.atr, 1.0) : 0.0);
   f[8]  = (s.window == WIN_LONDON || (s.macroId >= 150 && s.macroId < 500)) ? (float)1.0 : (float)0.0;
   f[9]  = (s.window == WIN_NY_AM  || (s.macroId >= 800 && s.macroId < 1200)) ? (float)1.0 : (float)0.0;
   f[10] = (s.window == WIN_NY_PM  || (s.macroId >= 1200)) ? (float)1.0 : (float)0.0;
   f[11] = s.biasAligned ? (float)1.0 : (float)0.0;
   f[12] = s.inMacro ? (float)1.0 : (float)0.0;
   f[13] = s.fvgUntouched ? (float)1.0 : (float)0.0;
   f[14] = (float)(nyDayOfWeek / 5.0);
   f[15] = (float)(s.atrD1 > 0 ? MathMin(s.atr / s.atrD1, 1.0) : 0.0);
   f[16] = (s.setupType == SETUP_MACRO_BREAKER) ? (float)1.0 : (float)0.0;
   f[17] = s.unicorn ? (float)1.0 : (float)0.0;
   f[18] = s.bpr ? (float)1.0 : (float)0.0;
   f[19] = s.refLevelHit ? (float)1.0 : (float)0.0;
}

string FeatureHeaderCSV()
{
   string h = "f_score,f_sweep_rank,f_disp_atr,f_fvg_atr,f_retrace,f_in_ote,f_rr,f_spread_atr,";
   h += "f_win_london,f_win_nyam,f_win_nypm,f_bias_aligned,f_in_macro,f_fvg_untouched,f_dow,f_atr_ratio,";
   h += "f_setup_type,f_unicorn,f_bpr,f_ref_level";
   return h;
}

string FeatureCSV(const float &f[])
{
   string out = "";
   for(int i = 0; i < ArraySize(f); i++)
   {
      if(i > 0) out += ",";
      out += DoubleToString(f[i], 4);
   }
   return out;
}

#endif // ICTPRO_COMMON_MQH


//====================================================================
//  MODULE : ICTPro_SessionClock.mqh
//====================================================================
#ifndef ICTPRO_SESSIONCLOCK_MQH
#define ICTPRO_SESSIONCLOCK_MQH

#define ICTPRO_MAX_MACROS 32

class CSessionClock
{
private:
   int      m_offsetWinterHours;   // offset serveur vs UTC en hiver (ex: 2 pour EET)
   bool     m_followsEU;           // le serveur suit l'heure d'ete europeenne
   bool     m_forceManual;         // ignorer la mesure TimeGMT en live
   bool     m_useLondon;
   bool     m_useNYAM;
   bool     m_useNYPM;
   int      m_measuredOffsetSec;
   datetime m_lastMeasure;
   bool     m_tester;

   //--- table des macros (heure NY)
   int      m_mId[ICTPRO_MAX_MACROS];
   int      m_mStart[ICTPRO_MAX_MACROS];
   int      m_mEnd[ICTPRO_MAX_MACROS];
   bool     m_mHigh[ICTPRO_MAX_MACROS];
   bool     m_mEnabled[ICTPRO_MAX_MACROS];
   string   m_mName[ICTPRO_MAX_MACROS];
   int      m_mCount;

   void AddMacro(const int id, const int startMin, const int endMin, const bool highProb, const string name)
   {
      if(m_mCount >= ICTPRO_MAX_MACROS) return;
      m_mId[m_mCount] = id; m_mStart[m_mCount] = startMin; m_mEnd[m_mCount] = endMin;
      m_mHigh[m_mCount] = highProb; m_mEnabled[m_mCount] = false; m_mName[m_mCount] = name;
      m_mCount++;
   }
   void BuildMacroTable()
   {
      m_mCount = 0;
      //--- Londres
      AddMacro(150,  110, 130, false, "01:50 manipulation");
      AddMacro(250,  170, 190, false, "02:50 power hour / expansion");
      AddMacro(320,  200, 220, true,  "03:20 reversal / retracement");
      AddMacro(350,  230, 250, false, "03:50 continuation de 03:20");
      AddMacro(420,  260, 280, false, "04:20");
      //--- Early NY
      AddMacro(650,  410, 430, false, "06:50 early NY");
      AddMacro(750,  470, 490, false, "07:50 early NY");
      //--- NY
      AddMacro(820,  500, 520, true,  "08:20 manipulation / spooling (MSS)");
      AddMacro(850,  530, 550, false, "08:50 accumulation (low prob)");
      AddMacro(920,  560, 580, true,  "09:20 manipulation high prob");
      AddMacro(950,  590, 610, false, "09:50 continuation de 09:20");
      AddMacro(1020, 620, 640, true,  "10:20 reversal / retracement high prob");
      AddMacro(1050, 650, 670, false, "10:50 continuation de 10:20");
      AddMacro(1120, 680, 700, false, "11:20 changement de tendance");
      AddMacro(1150, 710, 730, false, "11:50 changement / continuation");
      AddMacro(1220, 740, 760, false, "12:20 volatilite");
      AddMacro(1250, 770, 790, false, "12:50 pre-lunch");
      AddMacro(1320, 800, 820, true,  "13:20 high prob + opening range PM");
      AddMacro(1350, 830, 850, false, "13:50");
      AddMacro(1420, 860, 880, false, "14:20 volatilite + livraison swing");
      AddMacro(1450, 890, 910, false, "14:50");
      AddMacro(1515, 915, 940, true,  "15:15 spooling high prob");
      AddMacro(1550, 950, 970, true,  "15:50 final hour high prob");
   }

   static int DaysInMonth(const int y, const int m)
   {
      switch(m)
      {
         case 2:  return (((y % 4 == 0) && (y % 100 != 0)) || (y % 400 == 0)) ? 29 : 28;
         case 4: case 6: case 9: case 11: return 30;
         default: return 31;
      }
   }
   static datetime MakeDate(const int y, const int m, const int d, const int h = 0, const int mi = 0)
   {
      MqlDateTime t;
      ZeroMemory(t);
      t.year = y; t.mon = m; t.day = d; t.hour = h; t.min = mi; t.sec = 0;
      return StructToTime(t);
   }
   static int DayOfWeek(const int y, const int m, const int d)
   {
      MqlDateTime t;
      TimeToStruct(MakeDate(y, m, d), t);
      return t.day_of_week;
   }
   static int NthSunday(const int y, const int m, const int n)
   {
      int dow1 = DayOfWeek(y, m, 1);
      int first = 1 + ((7 - dow1) % 7);
      return first + 7 * (n - 1);
   }
   static int LastSunday(const int y, const int m)
   {
      int dim = DaysInMonth(y, m);
      int dowL = DayOfWeek(y, m, dim);
      return dim - dowL;
   }
   static datetime DayStartOf(const datetime t)
   {
      long v = (long)t;
      return (datetime)(v - (v % 86400));
   }

public:
   CSessionClock()
   {
      m_offsetWinterHours = 2;
      m_followsEU = true;
      m_forceManual = false;
      m_useLondon = true; m_useNYAM = true; m_useNYPM = true;
      m_measuredOffsetSec = 0;
      m_lastMeasure = 0;
      m_tester = false;
      BuildMacroTable();
   }

   void Init(const int offsetWinterHours, const bool followsEU, const bool forceManual,
             const bool useLondon, const bool useNYAM, const bool useNYPM, const string enabledMacros)
   {
      m_offsetWinterHours = offsetWinterHours;
      m_followsEU = followsEU;
      m_forceManual = forceManual;
      m_useLondon = useLondon;
      m_useNYAM = useNYAM;
      m_useNYPM = useNYPM;
      m_tester = IsTester();
      m_lastMeasure = 0;
      SetEnabledMacros(enabledMacros);
   }

   //--- "0320,0350,1020" : liste des macros autorisees pour le Macro Breaker
   void SetEnabledMacros(const string list)
   {
      for(int i = 0; i < m_mCount; i++) m_mEnabled[i] = false;
      string parts[];
      int n = StringSplit(list, ',', parts);
      for(int k = 0; k < n; k++)
      {
         string p = parts[k];
         StringTrimLeft(p); StringTrimRight(p);
         StringReplace(p, ":", "");
         if(p == "") continue;
         int id = (int)StringToInteger(p);
         for(int i = 0; i < m_mCount; i++) if(m_mId[i] == id) m_mEnabled[i] = true;
      }
   }

   //--- Heure d'ete americaine : 2e dimanche de mars 07:00 UTC -> 1er dimanche de novembre 06:00 UTC
   static bool IsUSDST(const datetime utc)
   {
      MqlDateTime t;
      TimeToStruct(utc, t);
      datetime s = MakeDate(t.year, 3, NthSunday(t.year, 3, 2), 7, 0);
      datetime e = MakeDate(t.year, 11, NthSunday(t.year, 11, 1), 6, 0);
      return (utc >= s && utc < e);
   }

   //--- Heure d'ete europeenne : dernier dimanche de mars 01:00 UTC -> dernier dimanche d'octobre 01:00 UTC
   static bool IsEUDST(const datetime utc)
   {
      MqlDateTime t;
      TimeToStruct(utc, t);
      datetime s = MakeDate(t.year, 3, LastSunday(t.year, 3), 1, 0);
      datetime e = MakeDate(t.year, 10, LastSunday(t.year, 10), 1, 0);
      return (utc >= s && utc < e);
   }

   //--- Offset serveur -> UTC en secondes, pour un instant serveur donne
   int ServerOffsetSeconds(const datetime srv)
   {
      if(!m_tester && !m_forceManual)
      {
         if(m_lastMeasure == 0 || (long)srv - (long)m_lastMeasure > 3600)
         {
            datetime gmt = TimeGMT();
            datetime ts  = TimeTradeServer();
            if(gmt > 0 && ts > 0)
            {
               long diff = (long)ts - (long)gmt;
               m_measuredOffsetSec = (int)(MathRound(diff / 1800.0) * 1800);
               m_lastMeasure = srv;
            }
         }
         if(m_lastMeasure > 0)
            return m_measuredOffsetSec;
      }
      datetime approxUTC = (datetime)((long)srv - (long)m_offsetWinterHours * 3600);
      int off = m_offsetWinterHours * 3600;
      if(m_followsEU && IsEUDST(approxUTC))
         off += 3600;
      return off;
   }

   datetime ServerToUTC(const datetime srv)
   {
      return (datetime)((long)srv - ServerOffsetSeconds(srv));
   }
   datetime UTCToServer(const datetime utc)
   {
      datetime approxSrv = (datetime)((long)utc + (long)m_offsetWinterHours * 3600);
      return (datetime)((long)utc + ServerOffsetSeconds(approxSrv));
   }
   static datetime UTCToNY(const datetime utc)
   {
      int off = IsUSDST(utc) ? -4 : -5;
      return (datetime)((long)utc + (long)off * 3600);
   }
   static datetime NYToUTC(const datetime ny)
   {
      datetime guess = (datetime)((long)ny + 5 * 3600);
      if(IsUSDST(guess))
         return (datetime)((long)ny + 4 * 3600);
      return guess;
   }
   datetime ServerToNY(const datetime srv) { return UTCToNY(ServerToUTC(srv)); }
   datetime NYToServer(const datetime ny)  { return UTCToServer(NYToUTC(ny)); }

   int NYMinuteOfDay(const datetime srv)
   {
      MqlDateTime t;
      TimeToStruct(ServerToNY(srv), t);
      return t.hour * 60 + t.min;
   }
   int NYDayOfWeek(const datetime srv)
   {
      MqlDateTime t;
      TimeToStruct(ServerToNY(srv), t);
      return t.day_of_week;
   }
   long NYDayKey(const datetime srv)
   {
      MqlDateTime t;
      TimeToStruct(ServerToNY(srv), t);
      return (long)t.year * 10000 + (long)t.mon * 100 + (long)t.day;
   }
   long NYWeekKey(const datetime srv)
   {
      long days = (long)ServerToNY(srv) / 86400;
      return (days + 3) / 7;
   }
   datetime NYDayStartServer(const datetime srv)
   {
      return NYToServer(DayStartOf(ServerToNY(srv)));
   }
   datetime NYWeekStartServer(const datetime srv)
   {
      datetime ny = ServerToNY(srv);
      MqlDateTime t;
      TimeToStruct(ny, t);
      int back = (t.day_of_week + 6) % 7;
      datetime mondayNY = (datetime)((long)DayStartOf(ny) - (long)back * 86400);
      return NYToServer(mondayNY);
   }
   //--- Intervalle [start, end) en serveur pour une plage exprimee en minutes NY
   void NYRangeToServer(const datetime srv, const int startMin, const int endMin, datetime &startSrv, datetime &endSrv)
   {
      datetime dayStartNY = DayStartOf(ServerToNY(srv));
      startSrv = NYToServer((datetime)((long)dayStartNY + (long)startMin * 60));
      endSrv   = NYToServer((datetime)((long)dayStartNY + (long)endMin * 60));
   }
   //--- Instant serveur correspondant a une heure NY (minutes) d'un jour NY decale de dayOffset
   datetime NYMinuteToServer(const datetime srv, const int minuteOfDay, const int dayOffset = 0)
   {
      datetime dayStartNY = DayStartOf(ServerToNY(srv));
      return NYToServer((datetime)((long)dayStartNY + (long)dayOffset * 86400 + (long)minuteOfDay * 60));
   }
   string NYTimeStr(const datetime srv)
   {
      return TimeToString(ServerToNY(srv), TIME_DATE | TIME_MINUTES);
   }

   //--- Fenetre Silver Bullet active a l'instant srv (heure NY : 3-4, 10-11, 14-15)
   ENUM_SB_WINDOW WindowAt(const datetime srv, datetime &startSrv, datetime &endSrv)
   {
      int mod = NYMinuteOfDay(srv);
      ENUM_SB_WINDOW w = WIN_NONE;
      int s = 0, e = 0;
      if(m_useLondon && mod >= 180 && mod < 240) { w = WIN_LONDON; s = 180; e = 240; }
      else if(m_useNYAM && mod >= 600 && mod < 660) { w = WIN_NY_AM; s = 600; e = 660; }
      else if(m_useNYPM && mod >= 840 && mod < 900) { w = WIN_NY_PM; s = 840; e = 900; }
      if(w == WIN_NONE)
      {
         startSrv = 0; endSrv = 0;
         return WIN_NONE;
      }
      NYRangeToServer(srv, s, e, startSrv, endSrv);
      return w;
   }

   //--- Macro couvrant l'instant srv (toutes macros, activees ou non). Retourne l'index ou -1.
   int MacroIndexAt(const datetime srv)
   {
      int m = NYMinuteOfDay(srv);
      for(int i = 0; i < m_mCount; i++)
         if(m >= m_mStart[i] && m < m_mEnd[i]) return i;
      return -1;
   }
   //--- Derniere macro terminee depuis moins de graceMin minutes (index ou -1)
   int MacroIndexRecent(const datetime srv, const int graceMin)
   {
      int m = NYMinuteOfDay(srv);
      for(int i = 0; i < m_mCount; i++)
         if(m >= m_mEnd[i] && m < m_mEnd[i] + graceMin) return i;
      return -1;
   }
   bool   InMacro(const datetime srv) { return MacroIndexAt(srv) >= 0; }
   int    MacroId(const int idx)       { return (idx >= 0 && idx < m_mCount) ? m_mId[idx] : 0; }
   bool   MacroEnabled(const int idx)  { return (idx >= 0 && idx < m_mCount) ? m_mEnabled[idx] : false; }
   bool   MacroHighProb(const int idx) { return (idx >= 0 && idx < m_mCount) ? m_mHigh[idx] : false; }
   string MacroName(const int idx)     { return (idx >= 0 && idx < m_mCount) ? m_mName[idx] : "aucune"; }
   void   MacroRangeServer(const datetime srv, const int idx, datetime &startSrv, datetime &endSrv)
   {
      if(idx < 0 || idx >= m_mCount) { startSrv = 0; endSrv = 0; return; }
      NYRangeToServer(srv, m_mStart[idx], m_mEnd[idx], startSrv, endSrv);
   }
   int MacroCount() { return m_mCount; }

   //--- Profil hebdomadaire : lundi 0, mardi/mercredi/jeudi +1, vendredi -1, week-end -2
   int DayOfWeekScore(const datetime srv)
   {
      int d = NYDayOfWeek(srv);
      if(d == 2 || d == 3 || d == 4) return 1;
      if(d == 1) return 0;
      if(d == 5) return -1;
      return -2;
   }

   //--- Description pour le tableau de bord
   string Describe(const datetime srv)
   {
      int off = ServerOffsetSeconds(srv);
      int hours = off / 3600;
      int mins = (off % 3600) / 60;
      if(mins < 0) mins = -mins;
      string sign = (off >= 0) ? "+" : "-";
      if(hours < 0) hours = -hours;
      return StringFormat("NY %s | serveur UTC%s%d:%02d", NYTimeStr(srv), sign, hours, mins);
   }
};

#endif // ICTPRO_SESSIONCLOCK_MQH


//====================================================================
//  MODULE : ICTPro_NewsFilter.mqh
//====================================================================
#ifndef ICTPRO_NEWSFILTER_MQH
#define ICTPRO_NEWSFILTER_MQH

class CNewsFilter
{
private:
   datetime       m_times[];
   string         m_names[];
   int            m_count;
   bool           m_enabled;
   int            m_beforeSec;
   int            m_afterSec;
   string         m_currencies;
   bool           m_includeMedium;
   bool           m_useCalendar;
   string         m_csvFile;
   datetime       m_lastRefresh;
   bool           m_csvLoaded;
   CSessionClock *m_clock;

   void Clear()
   {
      ArrayResize(m_times, 0);
      ArrayResize(m_names, 0);
      m_count = 0;
   }
   void Add(const datetime tSrv, const string name)
   {
      for(int i = 0; i < m_count; i++)
         if(m_times[i] == tSrv && m_names[i] == name) return;
      ArrayResize(m_times, m_count + 1);
      ArrayResize(m_names, m_count + 1);
      m_times[m_count] = tSrv;
      m_names[m_count] = name;
      m_count++;
   }
   bool CurrencyWanted(const string cur)
   {
      if(m_currencies == "" || m_currencies == "*") return true;
      return (StringFind("," + m_currencies + ",", "," + cur + ",") >= 0);
   }

   //--- Fichier CSV : "yyyy.mm.dd hh:mi;CUR;HIGH|MEDIUM;Nom" avec heure en UTC
   void LoadCSV()
   {
      m_csvLoaded = true;
      if(m_csvFile == "") return;
      int h = FileOpen(m_csvFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
      if(h == INVALID_HANDLE)
         h = FileOpen(m_csvFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
      if(h == INVALID_HANDLE)
      {
         Print("[News] fichier introuvable : ", m_csvFile, " (aucun blackout en testeur)");
         return;
      }
      int loaded = 0;
      while(!FileIsEnding(h))
      {
         string line = FileReadString(h);
         StringTrimLeft(line);
         StringTrimRight(line);
         if(line == "" || StringGetCharacter(line, 0) == '#') continue;
         string parts[];
         int n = StringSplit(line, ';', parts);
         if(n < 3) continue;
         string impact = parts[2];
         StringToUpper(impact);
         if(impact != "HIGH" && !(m_includeMedium && impact == "MEDIUM")) continue;
         if(!CurrencyWanted(parts[1])) continue;
         datetime utc = StringToTime(parts[0]);
         if(utc <= 0) continue;
         string name = (n >= 4) ? parts[3] : "event";
         Add(m_clock.UTCToServer(utc), parts[1] + " " + name);
         loaded++;
      }
      FileClose(h);
      Print("[News] ", loaded, " evenements charges depuis ", m_csvFile);
   }

   //--- Calendrier MQL5 (live uniquement)
   void LoadCalendar(const datetime nowSrv)
   {
      string curs[];
      string list = (m_currencies == "" || m_currencies == "*") ? "USD" : m_currencies;
      int nc = StringSplit(list, ',', curs);
      datetime from = (datetime)((long)nowSrv - 2 * 86400);
      datetime to   = (datetime)((long)nowSrv + 4 * 86400);
      int total = 0;
      for(int c = 0; c < nc; c++)
      {
         MqlCalendarValue vals[];
         ResetLastError();
         int n = CalendarValueHistory(vals, from, to, NULL, curs[c]);
         if(n <= 0)
         {
            if(GetLastError() != 0)
               Print("[News] calendrier indisponible pour ", curs[c], " erreur ", GetLastError());
            continue;
         }
         for(int i = 0; i < n; i++)
         {
            MqlCalendarEvent ev;
            if(!CalendarEventById(vals[i].event_id, ev)) continue;
            if(ev.importance == CALENDAR_IMPORTANCE_HIGH ||
               (m_includeMedium && ev.importance == CALENDAR_IMPORTANCE_MODERATE))
            {
               Add(vals[i].time, curs[c] + " " + ev.name);
               total++;
            }
         }
      }
      Print("[News] calendrier : ", total, " evenements retenus");
   }

public:
   CNewsFilter()
   {
      m_count = 0; m_enabled = false; m_beforeSec = 900; m_afterSec = 900;
      m_currencies = "USD"; m_includeMedium = false; m_useCalendar = true;
      m_csvFile = ""; m_lastRefresh = 0; m_csvLoaded = false; m_clock = NULL;
   }

   void Init(const bool enabled, const int beforeMin, const int afterMin, const string currencies,
             const bool includeMedium, const bool useCalendar, const string csvFile, CSessionClock *clock)
   {
      m_enabled = enabled;
      m_beforeSec = beforeMin * 60;
      m_afterSec = afterMin * 60;
      m_currencies = currencies;
      StringToUpper(m_currencies);
      StringReplace(m_currencies, " ", "");
      m_includeMedium = includeMedium;
      m_useCalendar = useCalendar;
      m_csvFile = csvFile;
      m_clock = clock;
      m_lastRefresh = 0;
      m_csvLoaded = false;
      Clear();
   }

   void Refresh(const datetime nowSrv)
   {
      if(!m_enabled) return;
      bool tester = IsTester();
      if(tester || !m_useCalendar)
      {
         if(!m_csvLoaded) LoadCSV();
         return;
      }
      if(m_lastRefresh == 0 || (long)nowSrv - (long)m_lastRefresh > 3600)
      {
         Clear();
         LoadCalendar(nowSrv);
         if(m_count == 0 && !m_csvLoaded) LoadCSV();
         m_lastRefresh = nowSrv;
      }
   }

   bool IsBlackout(const datetime nowSrv, string &name)
   {
      name = "";
      if(!m_enabled) return false;
      for(int i = 0; i < m_count; i++)
      {
         long d = (long)m_times[i] - (long)nowSrv;   // >0 : evenement a venir
         if(d <= m_beforeSec && d >= -m_afterSec)
         {
            name = m_names[i];
            return true;
         }
      }
      return false;
   }

   //--- Prochain evenement (0 si aucun)
   datetime Next(const datetime nowSrv)
   {
      datetime best = 0;
      for(int i = 0; i < m_count; i++)
         if(m_times[i] >= nowSrv && (best == 0 || m_times[i] < best))
            best = m_times[i];
      return best;
   }

   int Count() { return m_count; }
};

#endif // ICTPRO_NEWSFILTER_MQH


//====================================================================
//  MODULE : ICTPro_MarketStructure.mqh
//====================================================================
#ifndef ICTPRO_MARKETSTRUCTURE_MQH
#define ICTPRO_MARKETSTRUCTURE_MQH

class CMarketStructure
{
public:
   //--- Swing high confirme a l'index i (necessite s bougies fermees de chaque cote)
   static bool IsSwingHigh(const MqlRates &r[], const int i, const int s, const int count)
   {
      if(i - s < 1 || i + s >= count) return false;
      for(int k = 1; k <= s; k++)
         if(r[i].high <= r[i - k].high || r[i].high < r[i + k].high) return false;
      return true;
   }
   static bool IsSwingLow(const MqlRates &r[], const int i, const int s, const int count)
   {
      if(i - s < 1 || i + s >= count) return false;
      for(int k = 1; k <= s; k++)
         if(r[i].low >= r[i - k].low || r[i].low > r[i + k].low) return false;
      return true;
   }

   //--- Biais par dernier Break Of Structure (iteration chronologique)
   static ENUM_ICT_DIR Bias(const MqlRates &r[], const int count, const int s,
                            double &lastSwingHigh, double &lastSwingLow)
   {
      ENUM_ICT_DIR bias = DIR_NONE;
      double curSH = 0, curSL = 0;
      lastSwingHigh = 0; lastSwingLow = 0;
      for(int k = count - s - 2; k >= 1; k--)
      {
         int i = k + s;   // le swing a l'index i devient connu a la bougie k
         if(IsSwingHigh(r, i, s, count)) { curSH = r[i].high; lastSwingHigh = curSH; }
         if(IsSwingLow(r, i, s, count))  { curSL = r[i].low;  lastSwingLow = curSL; }
         if(curSH > 0 && r[k].close > curSH) { bias = DIR_BUY;  curSH = 0; }
         if(curSL > 0 && r[k].close < curSL) { bias = DIR_SELL; curSL = 0; }
      }
      return bias;
   }

   //--- Dernier swing low confirme sous 'price' (pour trailing structurel)
   static double LastSwingLowBelow(const MqlRates &r[], const int count, const int s, const double price, const int maxLook)
   {
      int lim = MathMin(count - s - 1, maxLook);
      for(int i = s + 1; i <= lim; i++)
         if(IsSwingLow(r, i, s, count) && r[i].low < price) return r[i].low;
      return 0.0;
   }
   static double LastSwingHighAbove(const MqlRates &r[], const int count, const int s, const double price, const int maxLook)
   {
      int lim = MathMin(count - s - 1, maxLook);
      for(int i = s + 1; i <= lim; i++)
         if(IsSwingHigh(r, i, s, count) && r[i].high > price) return r[i].high;
      return 0.0;
   }

   //--- Market Structure Shift apres un sweep.
   //--- BUY : cloture au-dessus du dernier swing high precedant l'extreme du sweep.
   static bool FindMSS(const ENUM_ICT_DIR dir, const MqlRates &r[], const int count, const int extremeIdx,
                       const double extreme, const int maxBarsAfter, const double minRangeATR,
                       const double dispBodyATR, const double atr, const int s, SMSS &out)
   {
      ZeroMemory(out);
      if(extremeIdx < 2 || extremeIdx >= count - s - 1 || atr <= 0) return false;

      //--- niveau a casser : swing oppose le plus recent avant l'extreme, a distance minimale
      double level = 0;
      int lim = MathMin(count - s - 1, extremeIdx + 60);
      for(int i = extremeIdx + 1; i <= lim; i++)
      {
         if(dir == DIR_BUY && IsSwingHigh(r, i, s, count) && r[i].high >= extreme + minRangeATR * atr)
         { level = r[i].high; break; }
         if(dir == DIR_SELL && IsSwingLow(r, i, s, count) && r[i].low <= extreme - minRangeATR * atr)
         { level = r[i].low; break; }
      }
      if(level == 0)
      {
         //--- secours : extreme des 10 bougies precedant le sweep
         int to = MathMin(count - 1, extremeIdx + 10);
         for(int i = extremeIdx + 1; i <= to; i++)
         {
            if(dir == DIR_BUY)  level = (level == 0) ? r[i].high : MathMax(level, r[i].high);
            else                level = (level == 0) ? r[i].low  : MathMin(level, r[i].low);
         }
         if(level == 0) return false;
         if(dir == DIR_BUY  && level < extreme + minRangeATR * atr) return false;
         if(dir == DIR_SELL && level > extreme - minRangeATR * atr) return false;
      }

      //--- premiere cloture au-dela du niveau apres l'extreme
      int mssBar = -1;
      int stop = MathMax(1, extremeIdx - maxBarsAfter);
      for(int j = extremeIdx - 1; j >= stop; j--)
      {
         if(dir == DIR_BUY  && r[j].low  < extreme) return false;   // extreme du sweep viole
         if(dir == DIR_SELL && r[j].high > extreme) return false;
         if(dir == DIR_BUY  && r[j].close > level) { mssBar = j; break; }
         if(dir == DIR_SELL && r[j].close < level) { mssBar = j; break; }
      }
      if(mssBar < 0) return false;

      //--- displacement : plus grand corps de la jambe extreme -> MSS
      double body = 0;
      for(int j = mssBar; j <= extremeIdx - 1; j++)
         body = MathMax(body, BodyOf(r[j]));
      if(body < dispBodyATR * atr) return false;

      //--- extreme de la jambe depuis le MSS jusqu'a maintenant (bougie 0 incluse)
      double legExt = (dir == DIR_BUY) ? r[mssBar].high : r[mssBar].low;
      int legIdx = mssBar;
      for(int j = mssBar; j >= 0; j--)
      {
         if(dir == DIR_BUY  && r[j].high > legExt) { legExt = r[j].high; legIdx = j; }
         if(dir == DIR_SELL && r[j].low  < legExt) { legExt = r[j].low;  legIdx = j; }
      }

      out.found = true;
      out.barIdx = mssBar;
      out.barTime = r[mssBar].time;
      out.brokenLevel = level;
      out.dispBody = body;
      out.legExtreme = legExt;
      out.legExtremeIdx = legIdx;
      return true;
   }

   //--- Etat UT Bot (ligne de trailing ATR) sur la derniere bougie fermee.
   static ENUM_ICT_DIR UTBotState(const MqlRates &r[], const double &atr[], const int count, const double key)
   {
      if(count < 10) return DIR_NONE;
      double stop = 0;
      int start = MathMin(count - 2, 300);
      for(int i = start; i >= 1; i--)
      {
         double nLoss = key * atr[i];
         double c = r[i].close;
         double p = r[i + 1].close;
         double prev = stop;
         if(prev == 0) { stop = c - nLoss; continue; }
         if(c > prev && p > prev)       stop = MathMax(prev, c - nLoss);
         else if(c < prev && p < prev)  stop = MathMin(prev, c + nLoss);
         else if(c > prev)              stop = c - nLoss;
         else                           stop = c + nLoss;
      }
      if(stop == 0) return DIR_NONE;
      return (r[1].close > stop) ? DIR_BUY : DIR_SELL;
   }
};

#endif // ICTPRO_MARKETSTRUCTURE_MQH


//====================================================================
//  MODULE : ICTPro_FVG.mqh
//====================================================================
#ifndef ICTPRO_FVG_MQH
#define ICTPRO_FVG_MQH

class CFVG
{
public:
   //--- Tous les FVG dans la jambe [newestIdx .. oldestIdx] (indices serie).
   //--- Bougie du milieu m : plus vieille m+1, plus recente m-1.
   //--- BUY : low[m-1] > high[m+1] + minSize.
   //--- v6.20 : requireBody rend optionnel le corps directionnel de la bougie centrale.
   //--- Les FVG sont empiles par index croissant : out[n-1] est le PLUS ANCIEN de la
   //--- jambe, c'est-a-dire le PREMIER forme apres le sweep (1st FVG du displacement).
   static int FindInLeg(const ENUM_ICT_DIR dir, const MqlRates &r[], const int count,
                        const int newestIdx, const int oldestIdx, const double minSize, SFVG &out[],
                        const bool requireBody = true)
   {
      ArrayResize(out, 0);
      int from = MathMax(2, newestIdx - 1);
      int to   = MathMin(count - 2, oldestIdx - 1);
      for(int m = from; m <= to; m++)
      {
         SFVG f;
         ZeroMemory(f);
         if(dir == DIR_BUY)
         {
            double gap = r[m - 1].low - r[m + 1].high;
            if(gap < minSize) continue;
            if(requireBody && r[m].close <= r[m].open) continue;   // bougie centrale haussiere
            f.top = r[m - 1].low;
            f.bottom = r[m + 1].high;
         }
         else
         {
            double gap = r[m + 1].low - r[m - 1].high;
            if(gap < minSize) continue;
            if(requireBody && r[m].close >= r[m].open) continue;
            f.top = r[m + 1].low;
            f.bottom = r[m - 1].high;
         }
         f.found = true;
         f.midIdx = m;
         f.time = r[m].time;
         f.size = f.top - f.bottom;
         f.ce = (f.top + f.bottom) / 2.0;
         f.touched = false;
         CheckMitigation(dir, r, f);
         if(!f.found) continue;
         int n = ArraySize(out);
         ArrayResize(out, n + 1);
         out[n] = f;
      }
      return ArraySize(out);
   }

   //--- Balanced Price Range : un FVG oppose plus ancien recouvre le FVG courant
   static bool HasOpposingOverlap(const ENUM_ICT_DIR dir, const MqlRates &r[], const int count,
                                  const SFVG &f, const int lookbackBars, const double minSize)
   {
      int from = f.midIdx + 2;
      int to = MathMin(count - 2, f.midIdx + lookbackBars);
      for(int m = from; m <= to; m++)
      {
         double top, bottom;
         if(dir == DIR_BUY)
         {
            double gap = r[m + 1].low - r[m - 1].high;      // FVG baissier
            if(gap < minSize) continue;
            top = r[m + 1].low; bottom = r[m - 1].high;
         }
         else
         {
            double gap = r[m - 1].low - r[m + 1].high;      // FVG haussier
            if(gap < minSize) continue;
            top = r[m - 1].low; bottom = r[m + 1].high;
         }
         if(bottom <= f.top && top >= f.bottom) return true;
      }
      return false;
   }

   //--- Un FVG BUY est mitige si une bougie posterieure a traverse tout le gap (low < bottom).
   static void CheckMitigation(const ENUM_ICT_DIR dir, const MqlRates &r[], SFVG &f)
   {
      for(int k = f.midIdx - 2; k >= 0; k--)
      {
         if(dir == DIR_BUY)
         {
            if(r[k].low < f.bottom) { f.found = false; return; }
            if(r[k].low <= f.top)   f.touched = true;
         }
         else
         {
            if(r[k].high > f.top)    { f.found = false; return; }
            if(r[k].high >= f.bottom) f.touched = true;
         }
      }
   }
};

#endif // ICTPRO_FVG_MQH


//====================================================================
//  MODULE : ICTPro_LiquidityMap.mqh
//====================================================================
#ifndef ICTPRO_LIQUIDITYMAP_MQH
#define ICTPRO_LIQUIDITYMAP_MQH

class CLiquidityMap
{
private:
   SLiqLevel m_levels[];
   int       m_count;
   string    m_sym;
   double    m_drLow;
   double    m_drHigh;
   double    m_mergeTol;

public:
   //--- Ajoute un niveau (fusion si un niveau proche existe deja, le rang le plus eleve gagne)
   void AddLevel(const double price, const int rank, const ENUM_LIQ_TYPE type, const datetime time, const bool isHigh)
   {
      if(price <= 0) return;
      for(int i = 0; i < m_count; i++)
      {
         if(m_levels[i].isHigh == isHigh && MathAbs(m_levels[i].price - price) <= m_mergeTol)
         {
            if(rank > m_levels[i].rank)
            {
               m_levels[i].rank = rank;
               m_levels[i].type = type;
               m_levels[i].price = price;
               m_levels[i].time = time;
            }
            return;
         }
      }
      ArrayResize(m_levels, m_count + 1);
      m_levels[m_count].price = price;
      m_levels[m_count].rank = rank;
      m_levels[m_count].type = type;
      m_levels[m_count].time = time;
      m_levels[m_count].isHigh = isHigh;
      m_count++;
   }

private:
   //--- Extremes des bougies dont l'heure est dans [s, e)
   static bool RangeInTime(const MqlRates &r[], const int count, const datetime s, const datetime e,
                           double &hi, double &lo, datetime &hiT, datetime &loT)
   {
      hi = 0; lo = 0; hiT = 0; loT = 0;
      bool any = false;
      for(int i = 0; i < count; i++)
      {
         if(r[i].time < s || r[i].time >= e) continue;
         if(!any || r[i].high > hi) { hi = r[i].high; hiT = r[i].time; }
         if(!any || r[i].low < lo)  { lo = r[i].low;  loT = r[i].time; }
         any = true;
      }
      return any;
   }

   void AddSession(CSessionClock &clock, const MqlRates &ltf[], const int ltfCount, const datetime nowSrv,
                   const int startMin, const int endMin, const ENUM_LIQ_TYPE hiType, const ENUM_LIQ_TYPE loType)
   {
      datetime s, e;
      clock.NYRangeToServer(nowSrv, startMin, endMin, s, e);
      if(s >= nowSrv) return;               // session pas encore commencee
      double hi, lo; datetime hiT, loT;
      if(!RangeInTime(ltf, ltfCount, s, e, hi, lo, hiT, loT)) return;
      AddLevel(hi, 2, hiType, hiT, true);
      AddLevel(lo, 2, loType, loT, false);
   }

public:
   CLiquidityMap() { m_count = 0; m_sym = ""; m_drLow = 0; m_drHigh = 0; m_mergeTol = 0; }

   int Count() { return m_count; }
   void Get(const int i, SLiqLevel &lv) { lv = m_levels[i]; }
   double DealingRangeLow()  { return m_drLow; }
   double DealingRangeHigh() { return m_drHigh; }

   //--- Position dans le dealing range : 0 = bas, 0.5 = equilibre, 1 = haut
   double PremiumDiscountPct(const double price)
   {
      if(m_drHigh <= m_drLow) return 0.5;
      return (price - m_drLow) / (m_drHigh - m_drLow);
   }

   void Build(const string sym, CSessionClock &clock, const datetime nowSrv,
              const MqlRates &ltf[], const int ltfCount,
              const MqlRates &htf[], const int htfCount,
              const MqlRates &d1[], const int d1Count,
              const double atr, const int ipda1, const int ipda2, const int ipda3,
              const int swingStrength, const double eqTolATR)
   {
      m_sym = sym;
      m_count = 0;
      ArrayResize(m_levels, 0);
      m_mergeTol = MathMax(atr * 0.05, _Point * 5);

      //--- Jour et semaine precedents
      if(d1Count > 1)
      {
         AddLevel(d1[1].high, 3, LIQ_PDH, d1[1].time, true);
         AddLevel(d1[1].low,  3, LIQ_PDL, d1[1].time, false);
      }
      double pwh = iHigh(sym, PERIOD_W1, 1);
      double pwl = iLow(sym, PERIOD_W1, 1);
      datetime pwt = iTime(sym, PERIOD_W1, 1);
      if(pwh > 0 && pwl > 0)
      {
         AddLevel(pwh, 3, LIQ_PWH, pwt, true);
         AddLevel(pwl, 3, LIQ_PWL, pwt, false);
      }

      //--- IPDA : extremes sur 20/40/60 jours fermes. Dealing range = premier lookback.
      int look[3];
      look[0] = ipda1; look[1] = ipda2; look[2] = ipda3;
      for(int L = 0; L < 3; L++)
      {
         int n = MathMin(look[L], d1Count - 1);
         if(n < 2) continue;
         double hi = 0, lo = 0; datetime hiT = 0, loT = 0;
         for(int i = 1; i <= n; i++)
         {
            if(hi == 0 || d1[i].high > hi) { hi = d1[i].high; hiT = d1[i].time; }
            if(lo == 0 || d1[i].low  < lo) { lo = d1[i].low;  loT = d1[i].time; }
         }
         AddLevel(hi, 3, LIQ_IPDA_HIGH, hiT, true);
         AddLevel(lo, 3, LIQ_IPDA_LOW,  loT, false);
         if(L == 0) { m_drLow = lo; m_drHigh = hi; }
      }

      //--- Sessions du jour NY (minutes relatives a minuit NY ; negatif = veille)
      AddSession(clock, ltf, ltfCount, nowSrv, -240, 0,   LIQ_ASIA_HIGH,   LIQ_ASIA_LOW);    // Asie 20:00-00:00
      AddSession(clock, ltf, ltfCount, nowSrv, 120,  300, LIQ_LONDON_HIGH, LIQ_LONDON_LOW);  // Londres 02:00-05:00
      AddSession(clock, ltf, ltfCount, nowSrv, 420,  720, LIQ_NYAM_HIGH,   LIQ_NYAM_LOW);    // NY AM 07:00-12:00

      //--- Swings HTF (rang 2)
      int added = 0;
      for(int i = swingStrength + 1; i < htfCount - swingStrength && added < 16; i++)
      {
         if(CMarketStructure::IsSwingHigh(htf, i, swingStrength, htfCount)) { AddLevel(htf[i].high, 2, LIQ_HTF_SWING_HIGH, htf[i].time, true);  added++; }
         if(CMarketStructure::IsSwingLow(htf, i, swingStrength, htfCount))  { AddLevel(htf[i].low,  2, LIQ_HTF_SWING_LOW,  htf[i].time, false); added++; }
      }

      //--- Swings LTF (rang 1) et equal highs/lows (rang 2)
      double shP[]; datetime shT[]; double slP[]; datetime slT[];
      int nsh = 0, nsl = 0;
      int lim = MathMin(ltfCount - swingStrength - 1, 240);
      for(int i = swingStrength + 1; i <= lim && (nsh < 14 || nsl < 14); i++)
      {
         if(nsh < 14 && CMarketStructure::IsSwingHigh(ltf, i, swingStrength, ltfCount))
         {
            ArrayResize(shP, nsh + 1); ArrayResize(shT, nsh + 1);
            shP[nsh] = ltf[i].high; shT[nsh] = ltf[i].time; nsh++;
         }
         if(nsl < 14 && CMarketStructure::IsSwingLow(ltf, i, swingStrength, ltfCount))
         {
            ArrayResize(slP, nsl + 1); ArrayResize(slT, nsl + 1);
            slP[nsl] = ltf[i].low; slT[nsl] = ltf[i].time; nsl++;
         }
      }
      double eqTol = eqTolATR * atr;
      for(int a = 0; a < nsh; a++)
      {
         bool eq = false;
         for(int b = a + 1; b < nsh; b++)
            if(MathAbs(shP[a] - shP[b]) <= eqTol) { eq = true; break; }
         if(eq) AddLevel(shP[a], 2, LIQ_EQ_HIGH, shT[a], true);
         else   AddLevel(shP[a], 1, LIQ_LTF_SWING_HIGH, shT[a], true);
      }
      for(int a = 0; a < nsl; a++)
      {
         bool eq = false;
         for(int b = a + 1; b < nsl; b++)
            if(MathAbs(slP[a] - slP[b]) <= eqTol) { eq = true; break; }
         if(eq) AddLevel(slP[a], 2, LIQ_EQ_LOW, slT[a], false);
         else   AddLevel(slP[a], 1, LIQ_LTF_SWING_LOW, slT[a], false);
      }
   }

   //--- Sweeps confirmes. dir = DIR_BUY cherche les prises de liquidite sous les lows
   //--- (sell-side), dir = DIR_SELL au-dessus des highs (buy-side).
   int FindSweeps(const ENUM_ICT_DIR dir, const MqlRates &r[], const int count, const double atr,
                  const int lookback, const double minPenATR, const int confirmBars,
                  const int maxEpisodeBars, const datetime notOlderThan, SSweep &out[])
   {
      ArrayResize(out, 0);
      if(atr <= 0 || count < 10) return 0;
      int lb = MathMin(lookback, count - 2);
      double minPen = minPenATR * atr;
      bool wantHigh = (dir == DIR_SELL);

      for(int L = 0; L < m_count; L++)
      {
         if(m_levels[L].isHigh != wantHigh) continue;
         double level = m_levels[L].price;

         //--- bougie la plus recente ayant depasse le niveau de minPen
         int v = -1;
         for(int i = 1; i <= lb; i++)
         {
            if(r[i].time <= m_levels[L].time) break;            // le niveau n'existait pas encore
            bool beyond = wantHigh ? (r[i].high > level + minPen) : (r[i].low < level - minPen);
            if(beyond) { v = i; break; }
         }
         if(v < 0) continue;

         //--- bornes de l'episode (bougies contigues au-dela du niveau)
         int e1 = v;
         while(e1 - 1 >= 1)
         {
            bool b = wantHigh ? (r[e1 - 1].high > level) : (r[e1 - 1].low < level);
            if(!b) break;
            e1--;
         }
         int e2 = v;
         while(e2 + 1 <= lb)
         {
            bool b = wantHigh ? (r[e2 + 1].high > level) : (r[e2 + 1].low < level);
            if(!b) break;
            e2++;
         }
         int episodeBars = e2 - e1 + 1;
         if(episodeBars > maxEpisodeBars) continue;              // cassure, pas un sweep

         //--- confirmation : cloture de retour a l'interieur du niveau
         int confirmIdx = -1;
         bool closeInside = wantHigh ? (r[e1].close < level) : (r[e1].close > level);
         if(closeInside) confirmIdx = e1;
         else if(e1 > 1)
         {
            closeInside = wantHigh ? (r[e1 - 1].close < level) : (r[e1 - 1].close > level);
            if(closeInside) confirmIdx = e1 - 1;
         }
         if(confirmIdx < 0) continue;

         //--- extreme de l'episode
         int exIdx = e1;
         double ex = wantHigh ? r[e1].high : r[e1].low;
         for(int i = e1; i <= e2; i++)
         {
            if(wantHigh  && r[i].high > ex) { ex = r[i].high; exIdx = i; }
            if(!wantHigh && r[i].low  < ex) { ex = r[i].low;  exIdx = i; }
         }
         if(exIdx - confirmIdx > confirmBars) continue;           // retour trop lent
         if(r[exIdx].time < notOlderThan) continue;

         int n = ArraySize(out);
         ArrayResize(out, n + 1);
         out[n].found = true;
         out[n].level = level;
         out[n].rank = m_levels[L].rank;
         out[n].type = m_levels[L].type;
         out[n].levelTime = m_levels[L].time;
         out[n].extremeIdx = exIdx;
         out[n].extreme = ex;
         out[n].extremeTime = r[exIdx].time;
         out[n].episodeNewestIdx = e1;
         out[n].episodeBars = episodeBars;
         out[n].penetrationATR = MathAbs(ex - level) / atr;
      }

      //--- tri : rang decroissant puis plus recent d'abord
      int n = ArraySize(out);
      for(int a = 0; a < n - 1; a++)
         for(int b = a + 1; b < n; b++)
         {
            bool swap = (out[b].rank > out[a].rank) ||
                        (out[b].rank == out[a].rank && out[b].extremeIdx < out[a].extremeIdx);
            if(swap) { SSweep t = out[a]; out[a] = out[b]; out[b] = t; }
         }
      if(n > 8) { ArrayResize(out, 8); n = 8; }
      return n;
   }

   //--- Pool oppose le plus proche au-dela de minDist (et sous maxDist) depuis entry
   bool NearestPool(const ENUM_ICT_DIR dir, const double entry, const double minDist, const double maxDist,
                    double &price, int &type)
   {
      price = 0; type = -1;
      bool wantHigh = (dir == DIR_BUY);
      for(int i = 0; i < m_count; i++)
      {
         if(m_levels[i].isHigh != wantHigh) continue;
         double d = wantHigh ? (m_levels[i].price - entry) : (entry - m_levels[i].price);
         if(d < minDist || d > maxDist) continue;
         if(price == 0 || d < MathAbs(price - entry)) { price = m_levels[i].price; type = (int)m_levels[i].type; }
      }
      return (price > 0);
   }

   //--- Comme NearestPool, avec des niveaux supplementaires (deviations standard)
   bool NearestPoolWithExtras(const ENUM_ICT_DIR dir, const double entry, const double minDist, const double maxDist,
                              const double &extras[], double &price, int &type)
   {
      NearestPool(dir, entry, minDist, maxDist, price, type);
      for(int i = 0; i < ArraySize(extras); i++)
      {
         double d = (dir == DIR_BUY) ? (extras[i] - entry) : (entry - extras[i]);
         if(d < minDist || d > maxDist) continue;
         if(price == 0 || d < MathAbs(price - entry)) { price = extras[i]; type = (int)LIQ_SD_TARGET; }
      }
      return (price > 0);
   }

   //--- Equal highs/lows non balayes au-dela de 'price' dans le sens du stop
   bool HasEqualLevelBeyond(const ENUM_ICT_DIR dir, const double price, const double maxDist, const double excludeLevel, const double tol)
   {
      for(int i = 0; i < m_count; i++)
      {
         if(dir == DIR_BUY  && m_levels[i].type != LIQ_EQ_LOW)  continue;
         if(dir == DIR_SELL && m_levels[i].type != LIQ_EQ_HIGH) continue;
         if(MathAbs(m_levels[i].price - excludeLevel) <= tol) continue;
         double d = (dir == DIR_BUY) ? (price - m_levels[i].price) : (m_levels[i].price - price);
         if(d > 0 && d <= maxDist) return true;
      }
      return false;
   }

   //--- Ajoute les swings d'une serie (ex: M1) comme niveaux de rang 1
   void AddSwings(const MqlRates &r[], const int count, const int strength, const int maxEach,
                  const ENUM_LIQ_TYPE hiType, const ENUM_LIQ_TYPE loType)
   {
      int nh = 0, nl = 0;
      int lim = MathMin(count - strength - 1, 300);
      for(int i = strength + 1; i <= lim && (nh < maxEach || nl < maxEach); i++)
      {
         if(nh < maxEach && CMarketStructure::IsSwingHigh(r, i, strength, count)) { AddLevel(r[i].high, 1, hiType, r[i].time, true);  nh++; }
         if(nl < maxEach && CMarketStructure::IsSwingLow(r, i, strength, count))  { AddLevel(r[i].low,  1, loType, r[i].time, false); nl++; }
      }
   }

   string Summary()
   {
      int r3 = 0, r2 = 0, r1 = 0;
      for(int i = 0; i < m_count; i++)
      {
         if(m_levels[i].rank == 3) r3++;
         else if(m_levels[i].rank == 2) r2++;
         else r1++;
      }
      return StringFormat("niveaux %d (r3 %d, r2 %d, r1 %d) DR %.2f-%.2f", m_count, r3, r2, r1, m_drLow, m_drHigh);
   }
};

#endif // ICTPRO_LIQUIDITYMAP_MQH


//====================================================================
//  MODULE : ICTPro_Reference.mqh
//====================================================================
#ifndef ICTPRO_REFERENCE_MQH
#define ICTPRO_REFERENCE_MQH

#define ICTPRO_OPR_COUNT 4

class CReferenceLevels
{
private:
   CSessionClock *m_clock;
   double   m_midnightOpen;
   double   m_open0730;
   double   m_ndogHigh, m_ndogLow;
   double   m_nwogHigh, m_nwogLow;
   double   m_pdHigh, m_pdLow;
   double   m_oprHigh[ICTPRO_OPR_COUNT], m_oprLow[ICTPRO_OPR_COUNT];
   bool     m_oprValid[ICTPRO_OPR_COUNT];
   int      m_oprStart[ICTPRO_OPR_COUNT], m_oprEnd[ICTPRO_OPR_COUNT];
   double   m_tbrHigh, m_tbrLow;
   bool     m_tbrValid;
   double   m_adr5;
   double   m_dayHigh, m_dayLow;
   bool     m_useOPR, m_useTBR, m_useNDOG;
   //--- v6.20 : heures de formation reelles, indispensables pour que FindSweeps
   //--- accepte ces niveaux comme sources de sweep.
   datetime m_ndogTime, m_nwogTime;

   static bool RangeIn(const MqlRates &r[], const int count, const datetime s, const datetime e, double &hi, double &lo)
   {
      hi = 0; lo = 0; bool any = false;
      for(int i = 0; i < count; i++)
      {
         if(r[i].time < s || r[i].time >= e) continue;
         if(!any || r[i].high > hi) hi = r[i].high;
         if(!any || r[i].low < lo) lo = r[i].low;
         any = true;
      }
      return any;
   }
   static double OpenAtOrAfter(const MqlRates &r[], const int count, const datetime t, const datetime notAfter)
   {
      double best = 0; datetime bestT = 0;
      for(int i = 0; i < count; i++)
      {
         if(r[i].time < t || r[i].time > notAfter) continue;
         if(bestT == 0 || r[i].time < bestT) { bestT = r[i].time; best = r[i].open; }
      }
      return best;
   }
   static double CloseBefore(const MqlRates &r[], const int count, const datetime t, const datetime notBefore)
   {
      double best = 0; datetime bestT = 0;
      for(int i = 0; i < count; i++)
      {
         if(r[i].time >= t || r[i].time < notBefore) continue;
         if(bestT == 0 || r[i].time > bestT) { bestT = r[i].time; best = r[i].close; }
      }
      return best;
   }

public:
   CReferenceLevels()
   {
      m_clock = NULL; m_midnightOpen = 0; m_open0730 = 0; m_ndogHigh = 0; m_ndogLow = 0; m_nwogHigh = 0; m_nwogLow = 0;
      m_pdHigh = 0; m_pdLow = 0; m_tbrHigh = 0; m_tbrLow = 0; m_tbrValid = false; m_adr5 = 0; m_dayHigh = 0; m_dayLow = 0;
      m_useOPR = true; m_useTBR = true; m_useNDOG = true;
      m_ndogTime = 0; m_nwogTime = 0;
      m_oprStart[0] = 90;  m_oprEnd[0] = 120;   // 01:30-02:00 Londres
      m_oprStart[1] = 420; m_oprEnd[1] = 450;   // 07:00-07:30 pre-market
      m_oprStart[2] = 570; m_oprEnd[2] = 600;   // 09:30-10:00 AM
      m_oprStart[3] = 810; m_oprEnd[3] = 840;   // 13:30-14:00 PM
      for(int i = 0; i < ICTPRO_OPR_COUNT; i++) { m_oprHigh[i] = 0; m_oprLow[i] = 0; m_oprValid[i] = false; }
   }

   void Init(CSessionClock *clock, const bool useOPR, const bool useTBR, const bool useNDOG)
   {
      m_clock = clock; m_useOPR = useOPR; m_useTBR = useTBR; m_useNDOG = useNDOG;
   }

   void Build(const datetime nowSrv, const MqlRates &ltf[], const int ltfCount, const MqlRates &m1[], const int m1Count,
              const MqlRates &htf[], const int htfCount, const MqlRates &d1[], const int d1Count)
   {
      datetime dayStart = m_clock.NYDayStartServer(nowSrv);

      //--- true opens
      m_midnightOpen = OpenAtOrAfter(ltf, ltfCount, dayStart, (datetime)((long)dayStart + 1800));
      datetime t0730 = m_clock.NYMinuteToServer(nowSrv, 450);
      m_open0730 = (nowSrv >= t0730) ? OpenAtOrAfter(ltf, ltfCount, t0730, (datetime)((long)t0730 + 1800)) : 0;

      //--- range de la veille et ADR(5)
      m_pdHigh = 0; m_pdLow = 0; m_adr5 = 0;
      if(d1Count > 1) { m_pdHigh = d1[1].high; m_pdLow = d1[1].low; }
      int n = 0;
      for(int i = 1; i <= 5 && i < d1Count; i++) { m_adr5 += d1[i].high - d1[i].low; n++; }
      if(n > 0) m_adr5 /= n;

      //--- range du jour NY (depuis 00:00 NY)
      double hi, lo;
      if(RangeIn(ltf, ltfCount, dayStart, (datetime)((long)nowSrv + 60), hi, lo)) { m_dayHigh = hi; m_dayLow = lo; }
      else { m_dayHigh = 0; m_dayLow = 0; }

      //--- NDOG : close 16:59 NY de la veille -> open 18:00 NY de la veille (H1)
      m_ndogHigh = 0; m_ndogLow = 0; m_nwogHigh = 0; m_nwogLow = 0;
      m_ndogTime = 0; m_nwogTime = 0;
      if(m_useNDOG && htfCount > 30)
      {
         datetime close17 = m_clock.NYMinuteToServer(nowSrv, 17 * 60, -1);
         datetime open18  = m_clock.NYMinuteToServer(nowSrv, 18 * 60, -1);
         double c = CloseBefore(htf, htfCount, close17, (datetime)((long)close17 - 4 * 3600));
         double o = OpenAtOrAfter(htf, htfCount, open18, (datetime)((long)open18 + 3 * 3600));
         if(c > 0 && o > 0) { m_ndogHigh = MathMax(c, o); m_ndogLow = MathMin(c, o); m_ndogTime = open18; }
         //--- NWOG : dernier vendredi 16:59 -> dimanche 18:00
         int dow = m_clock.NYDayOfWeek(nowSrv);
         int backToFriday = (dow + 2) % 7;            // dimanche=0 -> 2, lundi -> 3, ... vendredi -> 0
         if(backToFriday == 0) backToFriday = 7;      // vendredi : semaine precedente
         datetime fri17 = m_clock.NYMinuteToServer(nowSrv, 17 * 60, -backToFriday);
         datetime sun18 = m_clock.NYMinuteToServer(nowSrv, 18 * 60, -backToFriday + 2);
         double fc = CloseBefore(htf, htfCount, fri17, (datetime)((long)fri17 - 4 * 3600));
         double so = OpenAtOrAfter(htf, htfCount, sun18, (datetime)((long)sun18 + 3 * 3600));
         if(fc > 0 && so > 0) { m_nwogHigh = MathMax(fc, so); m_nwogLow = MathMin(fc, so); m_nwogTime = sun18; }
      }

      //--- opening ranges (LTF M5)
      for(int i = 0; i < ICTPRO_OPR_COUNT; i++)
      {
         m_oprValid[i] = false;
         if(!m_useOPR) continue;
         datetime s, e;
         m_clock.NYRangeToServer(nowSrv, m_oprStart[i], m_oprEnd[i], s, e);
         if(nowSrv < e) continue;                     // range pas encore complet
         if(RangeIn(ltf, ltfCount, s, e, hi, lo)) { m_oprHigh[i] = hi; m_oprLow[i] = lo; m_oprValid[i] = true; }
      }

      //--- TBR 08:12-09:12 (M1 si disponible, sinon M5 approximatif)
      m_tbrValid = false;
      if(m_useTBR)
      {
         datetime s, e;
         m_clock.NYRangeToServer(nowSrv, 492, 552, s, e);
         if(nowSrv >= e)
         {
            if(m1Count > 0 && m1[m1Count - 1].time <= s && RangeIn(m1, m1Count, s, e, hi, lo)) { m_tbrHigh = hi; m_tbrLow = lo; m_tbrValid = true; }
            else if(RangeIn(ltf, ltfCount, (datetime)((long)s - 120), e, hi, lo)) { m_tbrHigh = hi; m_tbrLow = lo; m_tbrValid = true; }
         }
      }
   }

   //--- Pousse les niveaux de reference dans la carte de liquidite.
   //--- v6.20 : chaque niveau porte desormais SON heure de formation (fin de l'OPR,
   //--- fin du TBR, ouverture du gap) et non "maintenant". Sans cela, la condition
   //--- "if(r[i].time <= level.time) break" de FindSweeps rejetait tout de suite.
   void PushToMap(CLiquidityMap &map, const datetime nowSrv)
   {
      datetime s, e;
      for(int i = 0; i < ICTPRO_OPR_COUNT; i++)
      {
         if(!m_oprValid[i]) continue;
         m_clock.NYRangeToServer(nowSrv, m_oprStart[i], m_oprEnd[i], s, e);
         map.AddLevel(m_oprHigh[i], 2, LIQ_OPR_HIGH, e, true);
         map.AddLevel(m_oprLow[i],  2, LIQ_OPR_LOW,  e, false);
      }
      //--- deviations standard de l'opening range AM (2, 2.5, 4, 6) comme cibles
      if(m_oprValid[2])
      {
         m_clock.NYRangeToServer(nowSrv, m_oprStart[2], m_oprEnd[2], s, e);
         double rng = m_oprHigh[2] - m_oprLow[2];
         double sd[] = {2.0, 2.5, 4.0, 6.0};
         for(int k = 0; k < ArraySize(sd); k++)
         {
            map.AddLevel(m_oprHigh[2] + sd[k] * rng, 1, LIQ_SD_TARGET, e, true);
            map.AddLevel(m_oprLow[2]  - sd[k] * rng, 1, LIQ_SD_TARGET, e, false);
         }
      }
      if(m_tbrValid)
      {
         m_clock.NYRangeToServer(nowSrv, 492, 552, s, e);
         map.AddLevel(m_tbrHigh, 2, LIQ_TBR_HIGH, e, true);
         map.AddLevel(m_tbrLow,  2, LIQ_TBR_LOW,  e, false);
      }
      if(m_ndogHigh > 0)
      {
         map.AddLevel(m_ndogHigh, 2, LIQ_NDOG_HIGH, m_ndogTime, true);
         map.AddLevel(m_ndogLow,  2, LIQ_NDOG_LOW,  m_ndogTime, false);
      }
      if(m_nwogHigh > 0)
      {
         map.AddLevel(m_nwogHigh, 2, LIQ_NWOG_HIGH, m_nwogTime, true);
         map.AddLevel(m_nwogLow,  2, LIQ_NWOG_LOW,  m_nwogTime, false);
      }
   }

   //--- True open de reference a l'instant srv : 07:30 apres 07:30 NY, sinon minuit
   double TrueOpen(const datetime srv)
   {
      if(m_clock.NYMinuteOfDay(srv) >= 450 && m_open0730 > 0) return m_open0730;
      return m_midnightOpen;
   }
   double MidnightOpen() { return m_midnightOpen; }
   double Open0730() { return m_open0730; }

   //--- Achat sous le true open (discount du jour), vente au-dessus
   bool TrueOpenAligned(const ENUM_ICT_DIR dir, const double price, const datetime srv)
   {
      double to = TrueOpen(srv);
      if(to <= 0) return false;
      return (dir == DIR_BUY) ? (price < to) : (price > to);
   }

   //--- Une zone [low, high] touche-t-elle un niveau de reference ?
   bool ZoneHitsRefLevel(const double low, const double high, const double tol, string &name)
   {
      name = "";
      double lo = low - tol, hi = high + tol;
      if(m_pdHigh > m_pdLow)
      {
         double rng = m_pdHigh - m_pdLow;
         for(int q = 0; q <= 4; q++)
         {
            double lvl = m_pdLow + rng * q / 4.0;
            if(lvl >= lo && lvl <= hi) { name = StringFormat("PD_Q%d", q * 25); return true; }
         }
      }
      for(int i = 0; i < ICTPRO_OPR_COUNT; i++)
      {
         if(!m_oprValid[i]) continue;
         double ce = (m_oprHigh[i] + m_oprLow[i]) / 2.0;
         if(m_oprHigh[i] >= lo && m_oprHigh[i] <= hi) { name = StringFormat("OPR%d_H", i); return true; }
         if(m_oprLow[i]  >= lo && m_oprLow[i]  <= hi) { name = StringFormat("OPR%d_L", i); return true; }
         if(ce >= lo && ce <= hi) { name = StringFormat("OPR%d_CE", i); return true; }
      }
      if(m_ndogHigh > 0)
      {
         double ce = (m_ndogHigh + m_ndogLow) / 2.0;
         if((m_ndogHigh >= lo && m_ndogHigh <= hi) || (m_ndogLow >= lo && m_ndogLow <= hi) || (ce >= lo && ce <= hi)) { name = "NDOG"; return true; }
      }
      if(m_nwogHigh > 0)
      {
         double ce = (m_nwogHigh + m_nwogLow) / 2.0;
         if((m_nwogHigh >= lo && m_nwogHigh <= hi) || (m_nwogLow >= lo && m_nwogLow <= hi) || (ce >= lo && ce <= hi)) { name = "NWOG"; return true; }
      }
      return false;
   }

   //--- Part de l'ADR(5) deja parcourue aujourd'hui (en %)
   double ADRUsedPct()
   {
      if(m_adr5 <= 0 || m_dayHigh <= m_dayLow) return 0;
      return 100.0 * (m_dayHigh - m_dayLow) / m_adr5;
   }
   double ADR5() { return m_adr5; }

   string Summary()
   {
      string s = StringFormat("MO %s | 07:30 %s | ADR5 %s utilise %.0f%%", D2(m_midnightOpen, _Digits), D2(m_open0730, _Digits), D2(m_adr5, _Digits), ADRUsedPct());
      if(m_ndogHigh > 0) s += StringFormat(" | NDOG %s-%s", D2(m_ndogLow, _Digits), D2(m_ndogHigh, _Digits));
      for(int i = 0; i < ICTPRO_OPR_COUNT; i++) if(m_oprValid[i]) s += StringFormat(" | OPR%d %s-%s", i, D2(m_oprLow[i], _Digits), D2(m_oprHigh[i], _Digits));
      return s;
   }
};

#endif // ICTPRO_REFERENCE_MQH


//====================================================================
//  MODULE : ICTPro_SetupSilverBullet.mqh
//====================================================================
#ifndef ICTPRO_SETUPSILVERBULLET_MQH
#define ICTPRO_SETUPSILVERBULLET_MQH

struct SSetupParams
{
   int    swingStrength;
   double sweepMinATR;
   int    sweepConfirmBars;
   int    sweepMaxEpisodeBars;
   int    sweepLookbackBars;
   int    preSweepMinutes;
   int    mssMaxBars;
   double mssMinRangeATR;
   double dispBodyATR;
   double fvgMinSizeATR;
   ENUM_ENTRY_MODE entryMode;
   bool   requireDiscount;
   bool   requireHTFAlign;
   bool   useOTEBonus;
   bool   useMacroBonus;
   int    minScore;
   double slBufferATR;
   double tpBufferATR;
   ENUM_TP_MODE tpMode;
   double minRR;
   double maxTPDistATRD1;
   double maxStopATR;
   bool   allowFixedRRFallback;
   bool   utbotConfirm;
   double utbotKey;
   //--- tips ICT
   bool   useTrueOpenBonus;
   bool   requireTrueOpen;
   bool   useRefLevelBonus;
   double refLevelTolATR;
   bool   useDOWScore;
   bool   useBPRBonus;
   bool   useSDTargets;
   double eqWarnATR;
   //--- v6.20
   bool   fvgRequireBody;   // exiger un corps directionnel sur la bougie centrale du FVG
   bool   takeFirstFVG;     // prendre la 1ere FVG formee dans la jambe
   double minRetrace;       // retracement minimal de la jambe a l'entree
};

//--- Deviations standard de la jambe de manipulation projetees comme cibles
void BuildSDTargets(const ENUM_ICT_DIR dir, const double origin, const double extreme, double &levels[])
{
   double sd[] = {2.0, 2.5, 4.0};
   ArrayResize(levels, 0);
   double rng = MathAbs(origin - extreme);
   if(rng <= 0) return;
   ArrayResize(levels, ArraySize(sd));
   for(int i = 0; i < ArraySize(sd); i++)
      levels[i] = (dir == DIR_BUY) ? extreme + sd[i] * rng : extreme - sd[i] * rng;
}

class CSetupSilverBullet
{
private:
   SSetupParams      m_p;
   string            m_sym;
   CSessionClock    *m_clock;
   CLiquidityMap    *m_liq;
   CReferenceLevels *m_ref;

   bool BuildSetup(const ENUM_ICT_DIR dir, const MqlRates &r[], const int count, const SSweep &sw, const SMSS &mss,
                   const SFVG &fvg, const double atr, const double atrD1, const double ask, const double bid,
                   const double minStopDist, const datetime nowSrv, SSetup &s, string &why)
   {
      why = "";
      s.setupType = SETUP_SILVER_BULLET;
      s.dir = dir;
      s.sweep = sw;
      s.mss = mss;
      s.fvg = fvg;
      s.atr = atr;
      s.atrD1 = atrD1;
      s.spreadPts = (ask - bid) / _Point;
      s.dispBodyATR = mss.dispBody / atr;
      s.fvgSizeATR = fvg.size / atr;
      s.fvgUntouched = !fvg.touched;
      s.inMacro = m_clock.InMacro(mss.barTime) || m_clock.InMacro(nowSrv);

      //--- jambe : extreme du sweep -> extreme apres MSS
      if(dir == DIR_BUY) { s.legLow = sw.extreme; s.legHigh = mss.legExtreme; }
      else               { s.legHigh = sw.extreme; s.legLow = mss.legExtreme; }
      double legRange = s.legHigh - s.legLow;
      if(legRange <= 0) { why = "jambe nulle"; return false; }

      //--- prix d'entree
      double price = (m_p.entryMode == ENTRY_FVG_CE) ? fvg.ce : ((dir == DIR_BUY) ? fvg.top : fvg.bottom);
      s.marketEntry = false;
      s.needsOBConfirm = (m_p.entryMode == ENTRY_OB_AFTER_FVG);
      if(m_p.entryMode == ENTRY_MARKET_ON_MSS)
      {
         price = (dir == DIR_BUY) ? ask : bid;
         s.marketEntry = true;
      }
      else
      {
         if(dir == DIR_BUY && ask <= fvg.top)
         {
            if(ask < fvg.bottom) { why = "FVG traverse"; return false; }
            if(!s.needsOBConfirm) { price = ask; s.marketEntry = true; }
         }
         if(dir == DIR_SELL && bid >= fvg.bottom)
         {
            if(bid > fvg.top) { why = "FVG traverse"; return false; }
            if(!s.needsOBConfirm) { price = bid; s.marketEntry = true; }
         }
      }
      s.entry = NormPrice(m_sym, price);

      //--- retracement de la jambe, dealing range, OTE
      s.retracePct = (dir == DIR_BUY) ? (s.legHigh - s.entry) / legRange : (s.entry - s.legLow) / legRange;
      s.pdPct = m_liq.PremiumDiscountPct(s.entry);
      s.inDiscount = (s.retracePct >= 0.5);
      //--- v6.20 : seuil parametrable au lieu du mur a 50 %
      if(m_p.requireDiscount && s.retracePct < m_p.minRetrace)
      {
         why = StringFormat("retracement %.2f < %.2f", s.retracePct, m_p.minRetrace);
         return false;
      }
      double oteNear = (dir == DIR_BUY) ? s.legHigh - 0.62 * legRange : s.legLow + 0.62 * legRange;
      double oteFar  = (dir == DIR_BUY) ? s.legHigh - 0.79 * legRange : s.legLow + 0.79 * legRange;
      double oteLo = MathMin(oteNear, oteFar), oteHi = MathMax(oteNear, oteFar);
      s.inOTE = (fvg.bottom <= oteHi && fvg.top >= oteLo);

      //--- tips : true open, niveau de reference, BPR, equal highs/lows
      s.trueOpen = m_ref.TrueOpen(nowSrv);
      s.trueOpenAligned = m_ref.TrueOpenAligned(dir, s.entry, nowSrv);
      if(m_p.requireTrueOpen && s.trueOpen > 0 && !s.trueOpenAligned)
      {
         why = (dir == DIR_BUY) ? "entree au-dessus du true open" : "entree sous le true open";
         return false;
      }
      string refName = "";
      s.refLevelHit = m_p.useRefLevelBonus && m_ref.ZoneHitsRefLevel(fvg.bottom, fvg.top, m_p.refLevelTolATR * atr, refName);
      s.refLevelName = refName;
      s.bpr = m_p.useBPRBonus && CFVG::HasOpposingOverlap(dir, r, count, fvg, 30, m_p.fvgMinSizeATR * atr);

      //--- stop derriere l'extreme du sweep + buffer
      double buffer = m_p.slBufferATR * atr + (ask - bid);
      s.sl = NormPrice(m_sym, (dir == DIR_BUY) ? sw.extreme - buffer : sw.extreme + buffer);
      s.riskDist = MathAbs(s.entry - s.sl);
      if(s.riskDist < minStopDist) { why = "distance de stop sous le stops level"; return false; }
      if(s.riskDist > m_p.maxStopATR * atr) { why = StringFormat("stop trop large (> %.0f ATR)", m_p.maxStopATR); return false; }
      s.eqWarning = m_liq.HasEqualLevelBeyond(dir, s.sl, m_p.eqWarnATR * atr, sw.level, 0.05 * atr);

      //--- cible : pool le plus proche (+ deviations standard) avec RR minimum
      double minDist = m_p.minRR * s.riskDist;
      double maxDist = (atrD1 > 0) ? m_p.maxTPDistATRD1 * atrD1 : 50.0 * atr;
      double tpPrice = 0; int tpType = -1;
      double tpBuf = m_p.tpBufferATR * atr;
      if(m_p.tpMode == TP_NEAREST_POOL)
      {
         double sdLevels[];
         if(m_p.useSDTargets) BuildSDTargets(dir, mss.brokenLevel, sw.extreme, sdLevels);
         if(m_liq.NearestPoolWithExtras(dir, s.entry, minDist + tpBuf, maxDist, sdLevels, tpPrice, tpType))
            tpPrice = (dir == DIR_BUY) ? tpPrice - tpBuf : tpPrice + tpBuf;
         else if(m_p.allowFixedRRFallback)
         {
            tpPrice = (dir == DIR_BUY) ? s.entry + m_p.minRR * s.riskDist : s.entry - m_p.minRR * s.riskDist;
            tpType = -1;
         }
         else { why = "aucun pool de liquidite oppose atteignable"; return false; }
      }
      else
      {
         tpPrice = (dir == DIR_BUY) ? s.entry + m_p.minRR * s.riskDist : s.entry - m_p.minRR * s.riskDist;
         tpType = -1;
      }
      s.tp = NormPrice(m_sym, tpPrice);
      s.tpSource = tpType;
      s.rr = MathAbs(s.tp - s.entry) / s.riskDist;
      if(s.rr < m_p.minRR - 1e-6) { why = StringFormat("RR %.2f sous le minimum %.2f", s.rr, m_p.minRR); return false; }

      //--- score
      int score = 0;
      if(s.biasAligned) score += 2;
      if(sw.rank >= 3) score += 2; else if(sw.rank == 2) score += 1;
      if(s.dispBodyATR >= 1.5) score += 1;
      if(s.fvgUntouched) score += 1;
      if(m_p.useOTEBonus && s.inOTE) score += 1;
      if(m_p.useMacroBonus && s.inMacro) score += 1;
      if(s.rr >= 3.0) score += 1;
      if(m_p.useTrueOpenBonus && s.trueOpenAligned) score += 1;
      if(s.refLevelHit) score += 1;
      if(s.bpr) score += 1;
      if(m_p.useDOWScore) score += s.dowScore;
      if(s.eqWarning) score -= 2;
      s.score = score;
      if(score < m_p.minScore) { why = StringFormat("score %d < %d", score, m_p.minScore); return false; }

      s.id = StringFormat("SB_%s_%s_%s_%I64d", m_sym, TimeToString(s.windowStart, TIME_DATE | TIME_MINUTES), DirToStr(dir), (long)sw.extremeTime);
      StringReplace(s.id, " ", "T");
      StringReplace(s.id, ":", "");
      StringReplace(s.id, ".", "");
      s.valid = true;
      return true;
   }

public:
   CSetupSilverBullet() { m_sym = ""; m_clock = NULL; m_liq = NULL; m_ref = NULL; }

   void Init(const string sym, CSessionClock *clock, CLiquidityMap *liq, CReferenceLevels *ref, const SSetupParams &p)
   {
      m_sym = sym; m_clock = clock; m_liq = liq; m_ref = ref; m_p = p;
   }
   //--- v6.20 : permet la 2e passe relachee sans reconstruire l'objet
   void SetParams(const SSetupParams &p) { m_p = p; }

   //--- Evalue les deux directions. best.valid = true si un setup passe tous les filtres.
   bool Evaluate(const MqlRates &ltf[], const int ltfCount, const double &atrSeries[],
                 const ENUM_ICT_DIR bias, const ENUM_SB_WINDOW window, const datetime winStart, const datetime winEnd,
                 const datetime nowSrv, const double atr, const double atrD1, const double minStopDist,
                 SSetup &best, string &rejectSummary)
   {
      ResetSetup(best);
      rejectSummary = "";
      if(atr <= 0 || ltfCount < 60) { rejectSummary = "donnees insuffisantes"; return false; }

      double ask = SymbolInfoDouble(m_sym, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_sym, SYMBOL_BID);
      datetime notOlderThan = (datetime)((long)winStart - (long)m_p.preSweepMinutes * 60);
      int dow = m_clock.DayOfWeekScore(nowSrv);
      ENUM_ICT_DIR utState = m_p.utbotConfirm ? CMarketStructure::UTBotState(ltf, atrSeries, ltfCount, m_p.utbotKey) : DIR_NONE;

      ENUM_ICT_DIR dirs[2];
      dirs[0] = DIR_BUY; dirs[1] = DIR_SELL;
      for(int d = 0; d < 2; d++)
      {
         ENUM_ICT_DIR dir = dirs[d];
         string dirReason = "";
         if(m_p.requireHTFAlign && bias != DIR_NONE && bias != dir)
         {
            rejectSummary += DirToStr(dir) + ":biais HTF oppose; ";
            continue;
         }
         if(m_p.utbotConfirm && utState != DIR_NONE && utState != dir)
         {
            rejectSummary += DirToStr(dir) + ":UT Bot oppose; ";
            continue;
         }

         SSweep sweeps[];
         int ns = m_liq.FindSweeps(dir, ltf, ltfCount, atr, m_p.sweepLookbackBars, m_p.sweepMinATR,
                                   m_p.sweepConfirmBars, m_p.sweepMaxEpisodeBars, notOlderThan, sweeps);
         if(ns == 0) { rejectSummary += DirToStr(dir) + ":aucun sweep; "; continue; }

         for(int k = 0; k < ns; k++)
         {
            SMSS mss;
            if(!CMarketStructure::FindMSS(dir, ltf, ltfCount, sweeps[k].extremeIdx, sweeps[k].extreme, m_p.mssMaxBars,
                                          m_p.mssMinRangeATR, m_p.dispBodyATR, atr, m_p.swingStrength, mss))
            {
               if(dirReason == "") dirReason = "pas de MSS avec displacement";
               continue;
            }
            SFVG fvgs[];
            int nf = CFVG::FindInLeg(dir, ltf, ltfCount, mss.barIdx, sweeps[k].extremeIdx,
                                     m_p.fvgMinSizeATR * atr, fvgs, m_p.fvgRequireBody);
            if(nf == 0) { if(dirReason == "" || dirReason == "pas de MSS avec displacement") dirReason = "pas de FVG dans la jambe"; continue; }

            //--- v6.20 : FindInLeg empile par index croissant, donc fvgs[nf-1] est le
            //--- FVG le plus ancien de la jambe = 1ere FVG du displacement.
            bool picked = false;
            for(int q = 0; q < nf && !picked; q++)
            {
               int f = m_p.takeFirstFVG ? (nf - 1 - q) : q;
               SSetup s;
               ResetSetup(s);
               s.window = window; s.windowStart = winStart; s.windowEnd = winEnd;
               s.bias = bias; s.biasAligned = (bias == dir); s.dowScore = dow;
               string why;
               if(!BuildSetup(dir, ltf, ltfCount, sweeps[k], mss, fvgs[f], atr, atrD1, ask, bid, minStopDist, nowSrv, s, why))
               {
                  dirReason = why;
                  continue;
               }
               if(!best.valid || s.score > best.score || (s.score == best.score && s.rr > best.rr))
                  best = s;
               if(m_p.takeFirstFVG) picked = true;   // 1er FVG valide : on arrete pour ce sweep
            }
         }
         if(dirReason != "") rejectSummary += DirToStr(dir) + ":" + dirReason + "; ";
      }
      return best.valid;
   }
};

#endif // ICTPRO_SETUPSILVERBULLET_MQH


//====================================================================
//  MODULE : ICTPro_SetupMacroBreaker.mqh
//====================================================================
#ifndef ICTPRO_SETUPMACROBREAKER_MQH
#define ICTPRO_SETUPMACROBREAKER_MQH

struct SMBParams
{
   int    swingStrength;
   int    lookbackBars;
   int    swingLookback;
   int    maxBarsToConfirm;
   double sweepMinATR;
   int    sweepConfirmBars;
   int    sweepMaxEpisodeBars;
   int    preMacroMinutes;
   double minRangeATR;
   double dispBodyATR;
   double fvgMinSizeATR;
   double minBreakerATR;
   ENUM_MB_ENTRY entryLevel;
   bool   requireUnicorn;
   bool   requireHTFAlign;
   bool   requireTrueOpen;
   int    minScore;
   double slBufferATR;
   double generousMacroMult;
   double tpBufferATR;
   double minRR;
   double maxTPDistATRD1;
   double maxStopATR;
   bool   allowFixedRRFallback;
   bool   useSDTargets;
   bool   useRefLevelBonus;
   double refLevelTolATR;
   bool   useDOWScore;
   double eqWarnATR;
   //--- v6.20
   bool   fvgRequireBody;
   bool   allowRetested;    // accepter un breaker deja touche tant qu'il n'est pas viole
};

class CSetupMacroBreaker
{
private:
   SMBParams         m_p;
   string            m_sym;
   CSessionClock    *m_clock;
   CLiquidityMap    *m_liq;
   CReferenceLevels *m_ref;

   //--- Bougie breaker : down-close (achat) a partir du swing, sinon la bougie du swing
   int BreakerCandle(const ENUM_ICT_DIR dir, const MqlRates &r[], const int swingIdx)
   {
      for(int i = swingIdx; i >= MathMax(1, swingIdx - 2); i--)
      {
         if(dir == DIR_BUY  && r[i].close < r[i].open) return i;
         if(dir == DIR_SELL && r[i].close > r[i].open) return i;
      }
      return swingIdx;
   }

   bool BuildSetup(const ENUM_ICT_DIR dir, const MqlRates &r[], const int count, const SSweep &sw,
                   const double atr, const double atrM5, const double atrD1, const double ask, const double bid,
                   const double minStopDist, const datetime nowSrv, const datetime macroStart, const datetime macroEnd,
                   SSetup &s, string &why)
   {
      why = "";
      s.setupType = SETUP_MACRO_BREAKER;
      s.dir = dir;
      s.sweep = sw;
      s.atr = atr;
      s.atrD1 = atrD1;
      s.spreadPts = (ask - bid) / _Point;
      int ex = sw.extremeIdx;

      //--- swing oppose precedant le stop hunt (sequence L1 -> H1 -> stop hunt sous L1)
      int swingIdx = -1;
      int lim = MathMin(count - m_p.swingStrength - 1, ex + m_p.swingLookback);
      for(int i = ex + 1; i <= lim; i++)
      {
         if(sw.levelTime > 0 && r[i].time <= sw.levelTime) break;   // le swing doit etre posterieur au niveau balaye
         if(dir == DIR_BUY && CMarketStructure::IsSwingHigh(r, i, m_p.swingStrength, count) && r[i].high >= sw.extreme + m_p.minRangeATR * atr) { swingIdx = i; break; }
         if(dir == DIR_SELL && CMarketStructure::IsSwingLow(r, i, m_p.swingStrength, count) && r[i].low <= sw.extreme - m_p.minRangeATR * atr) { swingIdx = i; break; }
      }
      if(swingIdx < 0) { why = "pas de swing oppose avant le stop hunt"; return false; }

      SBreaker b;
      ZeroMemory(b);
      int bc = BreakerCandle(dir, r, swingIdx);
      b.candleIdx = bc;
      b.time = r[bc].time;
      b.top = r[bc].high; b.bottom = r[bc].low;
      b.bodyTop = BodyTop(r[bc]); b.bodyBottom = BodyBottom(r[bc]);
      b.swingLevel = (dir == DIR_BUY) ? r[swingIdx].high : r[swingIdx].low;

      //--- expansion + confirmation par le corps
      int confirmIdx = -1;
      double body = 0, legExt = (dir == DIR_BUY) ? -1 : DBL_MAX;
      int stop = MathMax(1, ex - m_p.maxBarsToConfirm);
      for(int j = ex - 1; j >= stop; j--)
      {
         if(dir == DIR_BUY  && r[j].low  < sw.extreme) { why = "extreme du sweep viole avant confirmation"; return false; }
         if(dir == DIR_SELL && r[j].high > sw.extreme) { why = "extreme du sweep viole avant confirmation"; return false; }
         body = MathMax(body, BodyOf(r[j]));
         if(dir == DIR_BUY)  legExt = MathMax(legExt, r[j].high);
         else                legExt = MathMin(legExt, r[j].low);
         bool bodyClose = (dir == DIR_BUY) ? (r[j].close > b.bodyTop && r[j].close > r[j].open)
                                           : (r[j].close < b.bodyBottom && r[j].close < r[j].open);
         bool newExtreme = (dir == DIR_BUY) ? (legExt > b.swingLevel) : (legExt < b.swingLevel);
         if(bodyClose && newExtreme) { confirmIdx = j; break; }
      }
      if(confirmIdx < 0) { why = "pas de confirmation (corps au-dela du corps du swing)"; return false; }
      if(body < m_p.dispBodyATR * atr) { why = "displacement insuffisant"; return false; }
      b.confirmIdx = confirmIdx;
      b.confirmTime = r[confirmIdx].time;
      b.dispBody = body;

      //--- le breaker doit se former dans la macro, ou jusqu'a preMacroMinutes avant
      //--- (cf. exemples : le breaker se forme souvent AVANT le debut de la macro,
      //---  c'est le retest/l'expansion qui se produit dans la macro)
      datetime earliest = (datetime)((long)macroStart - (long)m_p.preMacroMinutes * 60);
      if(b.confirmTime < earliest || b.confirmTime > macroEnd) { why = "confirmation hors macro"; return false; }

      //--- zone d'entree : breaker, ou FVG dans le breaker (Unicorn)
      b.zoneTop = b.top; b.zoneBottom = b.bottom;
      SFVG fvgs[];
      int nf = CFVG::FindInLeg(dir, r, count, confirmIdx, ex, m_p.fvgMinSizeATR * atr, fvgs, m_p.fvgRequireBody);
      for(int f = 0; f < nf; f++)
      {
         if(fvgs[f].bottom <= b.top && fvgs[f].top >= b.bottom)
         {
            b.unicorn = true;
            b.zoneTop = MathMin(b.top, fvgs[f].top);
            b.zoneBottom = MathMax(b.bottom, fvgs[f].bottom);
            s.fvg = fvgs[f];
            s.fvgSizeATR = fvgs[f].size / atr;
            s.fvgUntouched = !fvgs[f].touched;
            break;
         }
      }
      if(m_p.requireUnicorn && !b.unicorn) { why = "pas de FVG dans le breaker (Unicorn requis)"; return false; }
      s.breaker = b;
      s.unicorn = b.unicorn;
      s.dispBodyATR = body / atr;
      s.legLow = (dir == DIR_BUY) ? sw.extreme : legExt;
      s.legHigh = (dir == DIR_BUY) ? legExt : sw.extreme;

      //--- v6.20 : un breaker deja touche n'est plus rejete d'office. Seule une
      //--- cloture au-dela de la zone (violation) l'invalide.
      double zoneEdge = (dir == DIR_BUY) ? b.zoneTop : b.zoneBottom;
      bool alreadyTested = false;
      for(int j = confirmIdx - 1; j >= 1; j--)
      {
         bool touched = (dir == DIR_BUY) ? (r[j].low <= zoneEdge) : (r[j].high >= zoneEdge);
         bool violated = (dir == DIR_BUY) ? (r[j].close < b.zoneBottom) : (r[j].close > b.zoneTop);
         if(violated) { why = "breaker deja viole"; return false; }
         if(touched) alreadyTested = true;
      }
      if(alreadyTested && !m_p.allowRetested) { why = "breaker deja reteste"; return false; }

      //--- prix d'entree
      double price;
      if(m_p.entryLevel == MB_ENTRY_BREAKER_BODY)
         price = (dir == DIR_BUY) ? MathMin(b.zoneTop, b.bodyTop) : MathMax(b.zoneBottom, b.bodyBottom);
      else if(m_p.entryLevel == MB_ENTRY_BREAKER_CE)
         price = (b.zoneTop + b.zoneBottom) / 2.0;
      else
         price = zoneEdge;
      s.marketEntry = false;
      if(dir == DIR_BUY && ask <= price)
      {
         if(ask < b.zoneBottom) { why = "breaker traverse"; return false; }
         price = ask; s.marketEntry = true;
      }
      if(dir == DIR_SELL && bid >= price)
      {
         if(bid > b.zoneTop) { why = "breaker traverse"; return false; }
         price = bid; s.marketEntry = true;
      }
      s.entry = NormPrice(m_sym, price);
      double legRange = s.legHigh - s.legLow;
      s.retracePct = (legRange > 0) ? ((dir == DIR_BUY) ? (s.legHigh - s.entry) / legRange : (s.entry - s.legLow) / legRange) : 0;
      s.pdPct = m_liq.PremiumDiscountPct(s.entry);
      s.inDiscount = (s.retracePct >= 0.5);
      s.inMacro = true;

      //--- tips : true open, niveau de reference
      s.trueOpen = m_ref.TrueOpen(nowSrv);
      s.trueOpenAligned = m_ref.TrueOpenAligned(dir, s.entry, nowSrv);
      if(m_p.requireTrueOpen && s.trueOpen > 0 && !s.trueOpenAligned) { why = "true open non aligne"; return false; }
      string refName = "";
      s.refLevelHit = m_p.useRefLevelBonus && m_ref.ZoneHitsRefLevel(b.zoneBottom, b.zoneTop, m_p.refLevelTolATR * atrM5, refName);
      s.refLevelName = refName;

      //--- stop : sous le breaker, ou sous l'extreme du sweep si le breaker est petit
      double mult = (s.macroId == 920) ? m_p.generousMacroMult : 1.0;
      double buffer = m_p.slBufferATR * atr * mult + (ask - bid);
      double slBreaker = (dir == DIR_BUY) ? b.bottom - buffer : b.top + buffer;
      bool small = (b.top - b.bottom) < m_p.minBreakerATR * atr;
      double sl = small ? ((dir == DIR_BUY) ? sw.extreme - buffer : sw.extreme + buffer) : slBreaker;
      if(dir == DIR_BUY)  sl = MathMin(sl, slBreaker);
      else                sl = MathMax(sl, slBreaker);
      s.sl = NormPrice(m_sym, sl);
      s.riskDist = MathAbs(s.entry - s.sl);
      if(s.riskDist < minStopDist) { why = "distance de stop sous le stops level"; return false; }
      if(s.riskDist > m_p.maxStopATR * atr) { why = StringFormat("stop trop large (> %.0f ATR M1)", m_p.maxStopATR); return false; }
      s.eqWarning = m_liq.HasEqualLevelBeyond(dir, s.sl, m_p.eqWarnATR * atrM5, sw.level, 0.05 * atrM5);

      //--- cible : pool le plus proche (+ deviations standard de la jambe)
      double minDist = m_p.minRR * s.riskDist;
      double maxDist = (atrD1 > 0) ? m_p.maxTPDistATRD1 * atrD1 : 50.0 * atrM5;
      double tpPrice = 0; int tpType = -1;
      double tpBuf = m_p.tpBufferATR * atrM5;
      double sdLevels[];
      if(m_p.useSDTargets) BuildSDTargets(dir, b.swingLevel, sw.extreme, sdLevels);
      if(m_liq.NearestPoolWithExtras(dir, s.entry, minDist + tpBuf, maxDist, sdLevels, tpPrice, tpType))
         tpPrice = (dir == DIR_BUY) ? tpPrice - tpBuf : tpPrice + tpBuf;
      else if(m_p.allowFixedRRFallback)
      {
         tpPrice = (dir == DIR_BUY) ? s.entry + m_p.minRR * s.riskDist : s.entry - m_p.minRR * s.riskDist;
         tpType = -1;
      }
      else { why = "aucune cible atteignable (pas d'entree sans target)"; return false; }
      s.tp = NormPrice(m_sym, tpPrice);
      s.tpSource = tpType;
      s.rr = MathAbs(s.tp - s.entry) / s.riskDist;
      if(s.rr < m_p.minRR - 1e-6) { why = StringFormat("RR %.2f sous le minimum %.2f", s.rr, m_p.minRR); return false; }
      //--- cible deja prise avant l'entree = pas de trade
      bool tpTaken = (dir == DIR_BUY) ? (legExt >= s.tp) : (legExt <= s.tp);
      if(tpTaken) { why = "cible atteinte avant l'entree"; return false; }

      //--- score
      int score = 0;
      if(s.macroHighProb) score += 1;
      if(sw.rank >= 3) score += 2; else if(sw.rank == 2) score += 1;
      if(b.unicorn) score += 2;
      if(s.dispBodyATR >= 1.5) score += 1;
      if(s.biasAligned) score += 1;
      if(s.trueOpenAligned) score += 1;
      if(s.refLevelHit) score += 1;
      if(s.rr >= 3.0) score += 1;
      if(m_p.useDOWScore) score += s.dowScore;
      if(s.eqWarning) score -= 2;
      s.score = score;
      if(score < m_p.minScore) { why = StringFormat("score %d < %d", score, m_p.minScore); return false; }

      s.id = StringFormat("MB_%s_%d_%s_%s_%I64d", m_sym, s.macroId, TimeToString(macroStart, TIME_DATE), DirToStr(dir), (long)sw.extremeTime);
      StringReplace(s.id, " ", "T");
      StringReplace(s.id, ":", "");
      StringReplace(s.id, ".", "");
      s.valid = true;
      return true;
   }

public:
   CSetupMacroBreaker() { m_sym = ""; m_clock = NULL; m_liq = NULL; m_ref = NULL; }

   void Init(const string sym, CSessionClock *clock, CLiquidityMap *liq, CReferenceLevels *ref, const SMBParams &p)
   {
      m_sym = sym; m_clock = clock; m_liq = liq; m_ref = ref; m_p = p;
   }
   //--- v6.20
   void SetParams(const SMBParams &p) { m_p = p; }

   //--- Evalue les deux directions sur M1 pour la macro donnee.
   bool Evaluate(const MqlRates &m1[], const int m1Count, const ENUM_ICT_DIR bias,
                 const int macroId, const bool macroHighProb, const datetime macroStart, const datetime macroEnd,
                 const datetime nowSrv, const double atrM1, const double atrM5, const double atrD1, const double minStopDist,
                 SSetup &best, string &rejectSummary)
   {
      ResetSetup(best);
      rejectSummary = "";
      if(atrM1 <= 0 || m1Count < 60) { rejectSummary = "donnees M1 insuffisantes"; return false; }

      double ask = SymbolInfoDouble(m_sym, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_sym, SYMBOL_BID);
      datetime notOlderThan = (datetime)((long)macroStart - (long)(m_p.preMacroMinutes + 10) * 60);
      int dow = m_clock.DayOfWeekScore(nowSrv);
      datetime bestConfirm = 0;

      ENUM_ICT_DIR dirs[2];
      dirs[0] = DIR_BUY; dirs[1] = DIR_SELL;
      for(int d = 0; d < 2; d++)
      {
         ENUM_ICT_DIR dir = dirs[d];
         string dirReason = "";
         if(m_p.requireHTFAlign && bias != DIR_NONE && bias != dir)
         {
            rejectSummary += DirToStr(dir) + ":biais HTF oppose; ";
            continue;
         }
         SSweep sweeps[];
         int ns = m_liq.FindSweeps(dir, m1, m1Count, atrM1, m_p.lookbackBars, m_p.sweepMinATR,
                                   m_p.sweepConfirmBars, m_p.sweepMaxEpisodeBars, notOlderThan, sweeps);
         if(ns == 0) { rejectSummary += DirToStr(dir) + ":aucun stop hunt; "; continue; }

         for(int k = 0; k < ns; k++)
         {
            SSetup s;
            ResetSetup(s);
            s.macroId = macroId; s.macroHighProb = macroHighProb;
            s.windowStart = macroStart; s.windowEnd = macroEnd;
            s.bias = bias; s.biasAligned = (bias == dir); s.dowScore = dow;
            string why;
            if(!BuildSetup(dir, m1, m1Count, sweeps[k], atrM1, atrM5, atrD1, ask, bid, minStopDist, nowSrv, macroStart, macroEnd, s, why))
            {
               dirReason = why;
               continue;
            }
            //--- premier breaker forme d'abord, puis meilleur score
            bool better = !best.valid || (s.breaker.confirmTime < bestConfirm) ||
                          (s.breaker.confirmTime == bestConfirm && s.score > best.score);
            if(better) { best = s; bestConfirm = s.breaker.confirmTime; }
         }
         if(dirReason != "") rejectSummary += DirToStr(dir) + ":" + dirReason + "; ";
      }
      return best.valid;
   }
};

#endif // ICTPRO_SETUPMACROBREAKER_MQH


//====================================================================
//  MODULE : ICTPro_Executor.mqh
//====================================================================
#ifndef ICTPRO_EXECUTOR_MQH
#define ICTPRO_EXECUTOR_MQH

class CExecutor
{
private:
   CTrade  m_trade;
   string  m_sym;
   long    m_magic;
   int     m_digits;
   double  m_point;
   bool    m_expirySupported;
   string  m_lastError;

   double StopsLevel()  { return (double)SymbolInfoInteger(m_sym, SYMBOL_TRADE_STOPS_LEVEL) * m_point; }
   double FreezeLevel() { return (double)SymbolInfoInteger(m_sym, SYMBOL_TRADE_FREEZE_LEVEL) * m_point; }

   bool Ok(const uint rc)
   {
      return (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED || rc == TRADE_RETCODE_DONE_PARTIAL);
   }
   bool Retryable(const uint rc)
   {
      return (rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_CHANGED ||
              rc == TRADE_RETCODE_PRICE_OFF || rc == TRADE_RETCODE_CONNECTION ||
              rc == TRADE_RETCODE_TIMEOUT);
   }
   void Fail(const string what)
   {
      m_lastError = StringFormat("%s : retcode %d (%s)", what, m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
      Print("[Executor] ", m_lastError);
   }

public:
   CExecutor() { m_sym = ""; m_magic = 0; m_digits = 2; m_point = 0.01; m_expirySupported = false; m_lastError = ""; }

   void Init(const string sym, const long magic, const int slippagePoints)
   {
      m_sym = sym;
      m_magic = magic;
      m_digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      m_point = SymbolInfoDouble(sym, SYMBOL_POINT);
      m_trade.SetExpertMagicNumber((ulong)magic);
      m_trade.SetDeviationInPoints((ulong)slippagePoints);
      m_trade.SetTypeFillingBySymbol(sym);
      m_trade.SetMarginMode();
      m_trade.SetAsyncMode(false);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
      long expMode = SymbolInfoInteger(sym, SYMBOL_EXPIRATION_MODE);
      m_expirySupported = ((expMode & SYMBOL_EXPIRATION_SPECIFIED) != 0);
   }

   string LastError() { return m_lastError; }
   bool   ExpirySupported() { return m_expirySupported; }
   double Norm(const double p) { return NormalizeDouble(p, m_digits); }
   double MinStopDistance() { return MathMax(StopsLevel(), m_point); }

   //--- Verifie SL/TP par rapport au prix de reference (entry) et au stops level
   bool ValidateStops(const ENUM_ICT_DIR dir, const double entry, const double sl, const double tp, string &why)
   {
      double minD = StopsLevel();
      if(dir == DIR_BUY)
      {
         if(sl > 0 && (entry - sl) < minD) { why = "SL trop proche (stops level)"; return false; }
         if(tp > 0 && (tp - entry) < minD) { why = "TP trop proche (stops level)"; return false; }
         if(sl > 0 && sl >= entry) { why = "SL au-dessus de l'entree"; return false; }
         if(tp > 0 && tp <= entry) { why = "TP sous l'entree"; return false; }
      }
      else
      {
         if(sl > 0 && (sl - entry) < minD) { why = "SL trop proche (stops level)"; return false; }
         if(tp > 0 && (entry - tp) < minD) { why = "TP trop proche (stops level)"; return false; }
         if(sl > 0 && sl <= entry) { why = "SL sous l'entree"; return false; }
         if(tp > 0 && tp >= entry) { why = "TP au-dessus de l'entree"; return false; }
      }
      return true;
   }

   //--- Ordre limite. Bascule au marche si le prix limite est deja depasse et allowMarket.
   ulong PlaceLimit(const ENUM_ICT_DIR dir, const double lot, double price, double sl, double tp,
                    const datetime expiry, const string comment, const bool allowMarket, bool &wentMarket)
   {
      wentMarket = false;
      price = Norm(price); sl = Norm(sl); tp = Norm(tp);
      double ask = SymbolInfoDouble(m_sym, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_sym, SYMBOL_BID);
      double minD = StopsLevel();
      string why;
      if(!ValidateStops(dir, price, sl, tp, why)) { m_lastError = why; Print("[Executor] ", why); return 0; }

      bool limitOk = (dir == DIR_BUY) ? (price <= ask - minD) : (price >= bid + minD);
      if(!limitOk)
      {
         if(!allowMarket) { m_lastError = "prix limite deja depasse"; return 0; }
         wentMarket = true;
         return Market(dir, lot, sl, tp, comment);
      }

      ENUM_ORDER_TYPE_TIME tt = m_expirySupported && expiry > 0 ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;
      datetime exp = (tt == ORDER_TIME_SPECIFIED) ? expiry : 0;
      bool sent = (dir == DIR_BUY)
                  ? m_trade.BuyLimit(lot, price, m_sym, sl, tp, tt, exp, comment)
                  : m_trade.SellLimit(lot, price, m_sym, sl, tp, tt, exp, comment);
      if(!sent || !Ok(m_trade.ResultRetcode()))
      {
         Fail("ordre limite");
         return 0;
      }
      return m_trade.ResultOrder();
   }

   //--- Ordre au marche avec retry sur requote.
   ulong Market(const ENUM_ICT_DIR dir, const double lot, double sl, double tp, const string comment)
   {
      sl = Norm(sl); tp = Norm(tp);
      for(int attempt = 0; attempt < 3; attempt++)
      {
         double px = (dir == DIR_BUY) ? SymbolInfoDouble(m_sym, SYMBOL_ASK) : SymbolInfoDouble(m_sym, SYMBOL_BID);
         string why;
         if(!ValidateStops(dir, px, sl, tp, why)) { m_lastError = why; Print("[Executor] ", why); return 0; }
         bool sent = (dir == DIR_BUY)
                     ? m_trade.Buy(lot, m_sym, px, sl, tp, comment)
                     : m_trade.Sell(lot, m_sym, px, sl, tp, comment);
         uint rc = m_trade.ResultRetcode();
         if(sent && Ok(rc))
         {
            ulong deal = m_trade.ResultDeal();
            if(deal > 0 && HistoryDealSelect(deal))
               return (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
            return m_trade.ResultOrder();
         }
         if(!Retryable(rc)) { Fail("ordre marche"); return 0; }
         Sleep(250);
      }
      Fail("ordre marche (3 essais)");
      return 0;
   }

   //--- Modification SL/TP avec controle stops/freeze.
   bool ModifyPosition(const ulong ticket, double sl, double tp)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      sl = Norm(sl); tp = Norm(tp);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      if(MathAbs(curSL - sl) < m_point / 2 && MathAbs(curTP - tp) < m_point / 2) return true;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double bid = SymbolInfoDouble(m_sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_sym, SYMBOL_ASK);
      double minD = MathMax(StopsLevel(), FreezeLevel());
      if(type == POSITION_TYPE_BUY)
      {
         if(sl > 0 && sl > bid - minD) sl = Norm(bid - minD);
         if(tp > 0 && tp < ask + minD) return false;
      }
      else
      {
         if(sl > 0 && sl < ask + minD) sl = Norm(ask + minD);
         if(tp > 0 && tp > bid - minD) return false;
      }
      if(!m_trade.PositionModify(ticket, sl, tp) || !Ok(m_trade.ResultRetcode()))
      {
         Fail(StringFormat("modification #%I64u SL %s TP %s", ticket, DoubleToString(sl, m_digits), DoubleToString(tp, m_digits)));
         return false;
      }
      return true;
   }

   bool ClosePosition(const ulong ticket)
   {
      if(!m_trade.PositionClose(ticket) || !Ok(m_trade.ResultRetcode()))
      {
         Fail(StringFormat("cloture #%I64u", ticket));
         return false;
      }
      return true;
   }

   bool ClosePartial(const ulong ticket, const double volume)
   {
      if(!m_trade.PositionClosePartial(ticket, volume) || !Ok(m_trade.ResultRetcode()))
      {
         Fail(StringFormat("cloture partielle #%I64u vol %.2f", ticket, volume));
         return false;
      }
      return true;
   }

   bool DeleteOrder(const ulong ticket)
   {
      if(!OrderSelect(ticket)) return true;   // deja disparu
      if(!m_trade.OrderDelete(ticket) || !Ok(m_trade.ResultRetcode()))
      {
         Fail(StringFormat("suppression ordre #%I64u", ticket));
         return false;
      }
      return true;
   }

   //--- Ferme toutes les positions et supprime tous les ordres de cet EA sur ce symbole
   void CloseAll()
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic || PositionGetString(POSITION_SYMBOL) != m_sym) continue;
         ClosePosition(t);
      }
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong t = OrderGetTicket(i);
         if(t == 0) continue;
         if(OrderGetInteger(ORDER_MAGIC) != m_magic || OrderGetString(ORDER_SYMBOL) != m_sym) continue;
         DeleteOrder(t);
      }
   }

   //--- Normalisation de volume (arrondi vers le bas au pas)
   double NormalizeVolume(double lot)
   {
      double minL = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_MIN);
      double maxL = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_MAX);
      double step = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_STEP);
      if(step <= 0) step = 0.01;
      lot = MathFloor(lot / step + 1e-9) * step;
      lot = MathMax(0.0, MathMin(maxL, lot));
      if(lot < minL) return 0.0;
      int vd = (int)MathRound(-MathLog10(step));
      if(vd < 0) vd = 0;
      return NormalizeDouble(lot, vd);
   }
};

#endif // ICTPRO_EXECUTOR_MQH


//====================================================================
//  MODULE : ICTPro_RiskEngine.mqh
//====================================================================
#ifndef ICTPRO_RISKENGINE_MQH
#define ICTPRO_RISKENGINE_MQH

class CRiskEngine
{
private:
   string         m_sym;
   long           m_magic;
   CSessionClock *m_clock;
   CExecutor     *m_exec;
   string         m_gvPrefix;

   //--- parametres
   ENUM_RISK_MODE m_mode;
   double m_riskPct;
   double m_riskMoney;
   double m_fixedLot;
   double m_maxLotCap;
   double m_dailyLimitPct;
   double m_weeklyLimitPct;
   double m_maxOpenRiskPct;
   double m_ddHaltPct;
   int    m_maxConcurrent;
   int    m_maxConsecLosses;
   int    m_maxPerDay;
   int    m_maxPerWindow;
   double m_maxSpreadATR;
   int    m_maxSpreadPts;
   double m_minBalance;
   int    m_fridayLastHourNY;

   //--- etat
   long   m_dayKey;
   long   m_weekKey;
   double m_dayStartBalance;
   double m_weekStartBalance;
   double m_peakEquity;
   bool   m_halted;
   string m_haltReason;
   double m_closedToday;
   double m_closedWeek;
   int    m_tradesToday;
   int    m_consecLossesToday;
   datetime m_lastRefresh;

   double GV(const string name, const double def)
   {
      string k = m_gvPrefix + name;
      if(GlobalVariableCheck(k)) return GlobalVariableGet(k);
      return def;
   }
   void SetGV(const string name, const double v) { GlobalVariableSet(m_gvPrefix + name, v); }

   bool IsOurDeal(const ulong d)
   {
      return (HistoryDealGetInteger(d, DEAL_MAGIC) == m_magic && HistoryDealGetString(d, DEAL_SYMBOL) == m_sym);
   }

   //--- Recalcule P/L ferme du jour et de la semaine, trades du jour, pertes consecutives
   void ScanHistory(const datetime nowSrv)
   {
      datetime dayStart  = m_clock.NYDayStartServer(nowSrv);
      datetime weekStart = m_clock.NYWeekStartServer(nowSrv);
      m_closedToday = 0; m_closedWeek = 0; m_tradesToday = 0; m_consecLossesToday = 0;

      if(!HistorySelect(weekStart, (datetime)((long)nowSrv + 86400))) return;
      int total = HistoryDealsTotal();

      long   posIds[];  double posNet[];  datetime posLast[];  bool posToday[];
      int np = 0;
      for(int i = 0; i < total; i++)
      {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0 || !IsOurDeal(d)) continue;
         long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
         datetime t = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
         double pl = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_SWAP);
         if(entry == DEAL_ENTRY_IN && t >= dayStart) m_tradesToday++;
         m_closedWeek += pl;
         if(t >= dayStart) m_closedToday += pl;

         long pid = HistoryDealGetInteger(d, DEAL_POSITION_ID);
         int idx = -1;
         for(int k = 0; k < np; k++) if(posIds[k] == pid) { idx = k; break; }
         if(idx < 0)
         {
            ArrayResize(posIds, np + 1); ArrayResize(posNet, np + 1); ArrayResize(posLast, np + 1); ArrayResize(posToday, np + 1);
            posIds[np] = pid; posNet[np] = 0; posLast[np] = 0; posToday[np] = false;
            idx = np; np++;
         }
         posNet[idx] += pl;
         if(entry != DEAL_ENTRY_IN) { posLast[idx] = t; if(t >= dayStart) posToday[idx] = true; }
      }
      //--- positions encore ouvertes : exclues du decompte des pertes
      for(int k = 0; k < np; k++)
         if(posLast[k] == 0) posToday[k] = false;
      //--- tri par heure de derniere sortie, puis serie de pertes en remontant
      for(int a = 0; a < np - 1; a++)
         for(int b = a + 1; b < np; b++)
            if(posLast[b] > posLast[a])
            {
               long ti = posIds[a]; posIds[a] = posIds[b]; posIds[b] = ti;
               double tn = posNet[a]; posNet[a] = posNet[b]; posNet[b] = tn;
               datetime tl = posLast[a]; posLast[a] = posLast[b]; posLast[b] = tl;
               bool tt = posToday[a]; posToday[a] = posToday[b]; posToday[b] = tt;
            }
      for(int k = 0; k < np; k++)
      {
         if(!posToday[k]) break;
         if(posNet[k] < 0) m_consecLossesToday++;
         else break;
      }
   }

public:
   CRiskEngine()
   {
      m_sym = ""; m_magic = 0; m_clock = NULL; m_exec = NULL; m_gvPrefix = "";
      m_mode = RISK_PERCENT_EQUITY; m_riskPct = 0.5; m_riskMoney = 50; m_fixedLot = 0.01; m_maxLotCap = 5;
      m_dailyLimitPct = 2; m_weeklyLimitPct = 5; m_maxOpenRiskPct = 1.5; m_ddHaltPct = 10;
      m_maxConcurrent = 1; m_maxConsecLosses = 3; m_maxPerDay = 3; m_maxPerWindow = 1;
      m_maxSpreadATR = 0.15; m_maxSpreadPts = 60; m_minBalance = 100; m_fridayLastHourNY = 12;
      m_dayKey = 0; m_weekKey = 0; m_dayStartBalance = 0; m_weekStartBalance = 0; m_peakEquity = 0;
      m_halted = false; m_haltReason = ""; m_closedToday = 0; m_closedWeek = 0; m_tradesToday = 0;
      m_consecLossesToday = 0; m_lastRefresh = 0;
   }

   void Init(const string sym, const long magic, CSessionClock *clock, CExecutor *exec,
             const ENUM_RISK_MODE mode, const double riskPct, const double riskMoney, const double fixedLot, const double maxLotCap,
             const double dailyLimitPct, const double weeklyLimitPct, const double maxOpenRiskPct, const double ddHaltPct,
             const int maxConcurrent, const int maxConsecLosses, const int maxPerDay, const int maxPerWindow,
             const double maxSpreadATR, const int maxSpreadPts, const double minBalance, const int fridayLastHourNY)
   {
      m_sym = sym; m_magic = magic; m_clock = clock; m_exec = exec;
      m_gvPrefix = StringFormat("ICTPro_%s_%I64d_", sym, magic);
      m_mode = mode; m_riskPct = riskPct; m_riskMoney = riskMoney; m_fixedLot = fixedLot; m_maxLotCap = maxLotCap;
      m_dailyLimitPct = dailyLimitPct; m_weeklyLimitPct = weeklyLimitPct; m_maxOpenRiskPct = maxOpenRiskPct; m_ddHaltPct = ddHaltPct;
      m_maxConcurrent = maxConcurrent; m_maxConsecLosses = maxConsecLosses; m_maxPerDay = maxPerDay; m_maxPerWindow = maxPerWindow;
      m_maxSpreadATR = maxSpreadATR; m_maxSpreadPts = maxSpreadPts; m_minBalance = minBalance; m_fridayLastHourNY = fridayLastHourNY;
      m_peakEquity = GV("peak_equity", AccountInfoDouble(ACCOUNT_EQUITY));
      m_halted = false;
      m_lastRefresh = 0;
      Refresh(TimeCurrent(), true);
   }

   void Refresh(const datetime nowSrv, const bool force = false)
   {
      long dk = m_clock.NYDayKey(nowSrv);
      long wk = m_clock.NYWeekKey(nowSrv);
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

      if(!force && m_lastRefresh > 0 && (long)nowSrv - (long)m_lastRefresh < 5 && dk == m_dayKey) return;
      ScanHistory(nowSrv);

      if(dk != m_dayKey)
      {
         long savedKey = (long)GV("day_key", 0);
         if(savedKey == dk) m_dayStartBalance = GV("day_balance", balance - m_closedToday);
         else
         {
            m_dayStartBalance = balance - m_closedToday;
            SetGV("day_key", (double)dk);
            SetGV("day_balance", m_dayStartBalance);
         }
         m_dayKey = dk;
      }
      if(wk != m_weekKey)
      {
         long savedWk = (long)GV("week_key", 0);
         if(savedWk == wk) m_weekStartBalance = GV("week_balance", balance - m_closedWeek);
         else
         {
            m_weekStartBalance = balance - m_closedWeek;
            SetGV("week_key", (double)wk);
            SetGV("week_balance", m_weekStartBalance);
         }
         m_weekKey = wk;
      }
      if(equity > m_peakEquity) { m_peakEquity = equity; SetGV("peak_equity", m_peakEquity); }
      if(m_ddHaltPct > 0 && m_peakEquity > 0 && equity < m_peakEquity * (1.0 - m_ddHaltPct / 100.0) && !m_halted)
      {
         m_halted = true;
         m_haltReason = StringFormat("drawdown %.1f%% depuis le pic d'equite %.2f", 100.0 * (1.0 - equity / m_peakEquity), m_peakEquity);
         Print("[Risk] ARRET : ", m_haltReason);
      }
      m_lastRefresh = nowSrv;
   }

   void ResetHalt() { m_halted = false; m_haltReason = ""; m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY); SetGV("peak_equity", m_peakEquity); }
   bool Halted() { return m_halted; }

   double FloatingPL()
   {
      double pl = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic || PositionGetString(POSITION_SYMBOL) != m_sym) continue;
         pl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      }
      return pl;
   }
   double DailyPL()  { return m_closedToday + FloatingPL(); }
   double WeeklyPL() { return m_closedWeek + FloatingPL(); }
   double DailyLimitMoney()  { return m_dayStartBalance * m_dailyLimitPct / 100.0; }
   double WeeklyLimitMoney() { return m_weekStartBalance * m_weeklyLimitPct / 100.0; }
   int    TradesToday() { return m_tradesToday; }
   int    ConsecutiveLossesToday() { return m_consecLossesToday; }

   int OpenPositions()
   {
      int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) == m_magic && PositionGetString(POSITION_SYMBOL) == m_sym) n++;
      }
      return n;
   }
   int PendingOrders()
   {
      int n = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong t = OrderGetTicket(i);
         if(t == 0) continue;
         if(OrderGetInteger(ORDER_MAGIC) == m_magic && OrderGetString(ORDER_SYMBOL) == m_sym) n++;
      }
      return n;
   }
   ENUM_ICT_DIR OpenDirection()
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic || PositionGetString(POSITION_SYMBOL) != m_sym) continue;
         return (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? DIR_BUY : DIR_SELL;
      }
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong t = OrderGetTicket(i);
         if(t == 0) continue;
         if(OrderGetInteger(ORDER_MAGIC) != m_magic || OrderGetString(ORDER_SYMBOL) != m_sym) continue;
         long ot = OrderGetInteger(ORDER_TYPE);
         return (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP || ot == ORDER_TYPE_BUY) ? DIR_BUY : DIR_SELL;
      }
      return DIR_NONE;
   }

   //--- Entrees (deals IN) depuis winStart + ordres en attente
   int TradesInWindow(const datetime winStart)
   {
      int n = PendingOrders();
      if(!HistorySelect(winStart, (datetime)((long)TimeCurrent() + 86400))) return n;
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0 || !IsOurDeal(d)) continue;
         if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN &&
            (datetime)HistoryDealGetInteger(d, DEAL_TIME) >= winStart) n++;
      }
      return n;
   }

   //--- Risque monetaire encore ouvert (positions dont le SL est en perte)
   double OpenRiskMoney()
   {
      double risk = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic || PositionGetString(POSITION_SYMBOL) != m_sym) continue;
         double sl = PositionGetDouble(POSITION_SL);
         if(sl <= 0) { risk += AccountInfoDouble(ACCOUNT_EQUITY); continue; }   // pas de SL = risque total
         ENUM_ORDER_TYPE ot = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         double p = 0;
         if(OrderCalcProfit(ot, m_sym, PositionGetDouble(POSITION_VOLUME), PositionGetDouble(POSITION_PRICE_OPEN), sl, p) && p < 0)
            risk += -p;
      }
      return risk;
   }

   //--- Montant risque par trade selon le mode choisi par l'utilisateur
   double RiskMoneyPerTrade()
   {
      switch(m_mode)
      {
         case RISK_PERCENT_EQUITY:  return AccountInfoDouble(ACCOUNT_EQUITY)  * m_riskPct / 100.0;
         case RISK_PERCENT_BALANCE: return AccountInfoDouble(ACCOUNT_BALANCE) * m_riskPct / 100.0;
         case RISK_FIXED_MONEY:     return m_riskMoney;
         default:                   return 0.0;
      }
   }

   //--- Perte monetaire pour 1 lot entre entry et sl
   double LossPerLot(const ENUM_ICT_DIR dir, const double entry, const double sl)
   {
      double p = 0;
      ENUM_ORDER_TYPE ot = (dir == DIR_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(OrderCalcProfit(ot, m_sym, 1.0, entry, sl, p) && p != 0) return MathAbs(p);
      double tv = SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_VALUE);
      double ts = SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_SIZE);
      if(ts <= 0) return 0;
      return MathAbs(entry - sl) / ts * tv;
   }

   //--- Taille de position. factor = modulation adaptative (1.0 = neutre).
   double CalcLot(const ENUM_ICT_DIR dir, const double entry, const double sl, const double factor,
                  double &riskMoneyOut, string &reason)
   {
      reason = "";
      riskMoneyOut = 0;
      double lossPerLot = LossPerLot(dir, entry, sl);
      if(lossPerLot <= 0) { reason = "perte par lot non calculable"; return 0; }

      double lot = 0;
      if(m_mode == RISK_FIXED_LOT)
      {
         lot = m_fixedLot;
      }
      else
      {
         double riskMoney = RiskMoneyPerTrade() * factor;
         if(riskMoney <= 0) { reason = "risque monetaire nul"; return 0; }
         lot = riskMoney / lossPerLot;
         double minL = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_MIN);
         if(lot < minL)
         {
            if(minL * lossPerLot > riskMoney * 1.5) { reason = StringFormat("lot minimum %.2f = risque %.2f > 150%% du risque autorise %.2f", minL, minL * lossPerLot, riskMoney); return 0; }
            lot = minL;
         }
      }
      lot = MathMin(lot, m_maxLotCap);
      lot = m_exec.NormalizeVolume(lot);
      if(lot <= 0) { reason = "lot sous le minimum apres normalisation"; return 0; }

      //--- marge
      double margin = 0;
      ENUM_ORDER_TYPE ot = (dir == DIR_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(OrderCalcMargin(ot, m_sym, lot, entry, margin))
      {
         double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
         if(margin > free * 0.9)
         {
            double perLot = margin / lot;
            lot = m_exec.NormalizeVolume(free * 0.9 / perLot);
            if(lot <= 0) { reason = "marge insuffisante"; return 0; }
         }
      }
      riskMoneyOut = lot * lossPerLot;

      //--- risque ouvert cumule
      double maxOpen = AccountInfoDouble(ACCOUNT_EQUITY) * m_maxOpenRiskPct / 100.0;
      if(OpenRiskMoney() + riskMoneyOut > maxOpen)
      {
         reason = StringFormat("risque ouvert %.2f + %.2f > plafond %.2f", OpenRiskMoney(), riskMoneyOut, maxOpen);
         return 0;
      }
      return lot;
   }

   //--- Autorisation d'ouvrir un nouveau setup dans la fenetre courante
   bool CanOpen(const datetime nowSrv, const datetime winStart, const double atr, const ENUM_ICT_DIR dir, string &reason)
   {
      reason = "";
      if(m_halted) { reason = "EA arrete : " + m_haltReason; return false; }
      if(AccountInfoDouble(ACCOUNT_BALANCE) < m_minBalance) { reason = "balance sous le minimum"; return false; }
      if(DailyPL() <= -DailyLimitMoney() && m_dailyLimitPct > 0) { reason = StringFormat("perte journaliere %.2f >= limite %.2f", -DailyPL(), DailyLimitMoney()); return false; }
      if(WeeklyPL() <= -WeeklyLimitMoney() && m_weeklyLimitPct > 0) { reason = StringFormat("perte hebdo %.2f >= limite %.2f", -WeeklyPL(), WeeklyLimitMoney()); return false; }
      if(m_maxConsecLosses > 0 && m_consecLossesToday >= m_maxConsecLosses) { reason = StringFormat("%d pertes consecutives aujourd'hui", m_consecLossesToday); return false; }
      if(m_maxPerDay > 0 && m_tradesToday >= m_maxPerDay) { reason = "plafond de trades du jour atteint"; return false; }
      if(m_maxPerWindow > 0 && TradesInWindow(winStart) >= m_maxPerWindow) { reason = "plafond de trades de la fenetre atteint"; return false; }
      int open = OpenPositions() + PendingOrders();
      if(open >= m_maxConcurrent) { reason = "positions simultanees au plafond"; return false; }
      ENUM_ICT_DIR od = OpenDirection();
      if(od != DIR_NONE && od != dir) { reason = "position opposee deja ouverte"; return false; }
      int dow = m_clock.NYDayOfWeek(nowSrv);
      if(dow == 5 && m_fridayLastHourNY > 0 && m_clock.NYMinuteOfDay(nowSrv) >= m_fridayLastHourNY * 60) { reason = "vendredi apres l'heure limite"; return false; }
      double spread = SymbolInfoDouble(m_sym, SYMBOL_ASK) - SymbolInfoDouble(m_sym, SYMBOL_BID);
      double spreadPts = spread / _Point;
      if(m_maxSpreadPts > 0 && spreadPts > m_maxSpreadPts) { reason = StringFormat("spread %.0f pts > %d", spreadPts, m_maxSpreadPts); return false; }
      if(m_maxSpreadATR > 0 && atr > 0 && spread > m_maxSpreadATR * atr) { reason = StringFormat("spread %.2f > %.2f ATR", spread, m_maxSpreadATR); return false; }
      return true;
   }

   string Dashboard()
   {
      string mode;
      switch(m_mode)
      {
         case RISK_PERCENT_EQUITY:  mode = StringFormat("%.2f%% equite", m_riskPct); break;
         case RISK_PERCENT_BALANCE: mode = StringFormat("%.2f%% balance", m_riskPct); break;
         case RISK_FIXED_MONEY:     mode = StringFormat("%.2f fixe", m_riskMoney); break;
         default:                   mode = StringFormat("lot fixe %.2f", m_fixedLot);
      }
      string s = StringFormat("Risque/trade : %s (= %.2f %s)\n", mode, RiskMoneyPerTrade(), AccountInfoString(ACCOUNT_CURRENCY));
      s += StringFormat("Jour : P/L %.2f / limite -%.2f | trades %d/%d | pertes consec. %d/%d\n",
                        DailyPL(), DailyLimitMoney(), m_tradesToday, m_maxPerDay, m_consecLossesToday, m_maxConsecLosses);
      s += StringFormat("Semaine : P/L %.2f / limite -%.2f | risque ouvert %.2f | pic equite %.2f\n",
                        WeeklyPL(), WeeklyLimitMoney(), OpenRiskMoney(), m_peakEquity);
      if(m_halted) s += "ARRET : " + m_haltReason + "\n";
      return s;
   }
};

#endif // ICTPRO_RISKENGINE_MQH


//====================================================================
//  MODULE : ICTPro_Journal.mqh
//====================================================================
#ifndef ICTPRO_JOURNAL_MQH
#define ICTPRO_JOURNAL_MQH

class CJournal
{
private:
   bool   m_enabled;
   bool   m_logRejected;
   string m_folder;
   string m_sym;
   string m_lastRejectKey;
   int    m_flags;

   string MonthTag(const datetime t)
   {
      MqlDateTime d;
      TimeToStruct(t, d);
      return StringFormat("%04d%02d", d.year, d.mon);
   }

   int OpenAppend(const string name, const string header)
   {
      string path = m_folder + "\\" + name;
      bool existed = FileIsExist(path, FILE_COMMON);
      int h = FileOpen(path, m_flags);
      if(h == INVALID_HANDLE)
      {
         Print("[Journal] impossible d'ouvrir ", path, " erreur ", GetLastError());
         return INVALID_HANDLE;
      }
      FileSeek(h, 0, SEEK_END);
      if(!existed || FileTell(h) == 0)
         FileWriteString(h, header + "\r\n");
      return h;
   }

public:
   CJournal()
   {
      m_enabled = false; m_logRejected = true; m_folder = "ICTPro"; m_sym = ""; m_lastRejectKey = "";
      m_flags = FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE;
   }

   void Init(const bool enabled, const bool logRejected, const string folder, const string sym)
   {
      m_enabled = enabled;
      m_logRejected = logRejected;
      m_folder = (folder == "") ? "ICTPro" : folder;
      m_sym = sym;
      if(m_enabled) FolderCreate(m_folder, FILE_COMMON);
   }

   string SetupHeader()
   {
      string h = "ts_server,ts_ny,symbol,setup_id,setup_type,window,macro_id,direction,decision,reject_reason,score,htf_bias,bias_aligned,";
      h += "sweep_type,sweep_rank,sweep_level,sweep_extreme,sweep_pen_atr,mss_time,mss_level,disp_body_atr,";
      h += "fvg_top,fvg_bottom,fvg_ce,fvg_size_atr,fvg_untouched,breaker_top,breaker_bottom,unicorn,bpr,ref_level,true_open,true_open_aligned,dow_score,eq_warning,relaxed,";
      h += "leg_low,leg_high,retrace_pct,in_ote,pd_pct,in_discount,in_macro,";
      h += "entry,sl,tp,rr,risk_dist,tp_source,market_entry,atr_ltf,atr_d1,spread_pts,lot,risk_money,adapt_factor,model_prob,bucket,ticket,";
      h += FeatureHeaderCSV();
      return h;
   }

   void LogSetup(const SSetup &s, const string nyTime, const string decision, const string reason,
                 const double lot, const double riskMoney, const double adaptFactor, const double modelProb,
                 const string bucket, const ulong ticket, const float &features[])
   {
      if(!m_enabled) return;
      if(decision != "TAKEN")
      {
         if(!m_logRejected) return;
         string key = s.id + "|" + reason;
         if(key == m_lastRejectKey) return;
         m_lastRejectKey = key;
      }
      int h = OpenAppend(StringFormat("setups_%s_%s.csv", m_sym, MonthTag(TimeCurrent())), SetupHeader());
      if(h == INVALID_HANDLE) return;
      string line = StringFormat("%s,%s,%s,%s,%s,%s,%d,%s,%s,%s,%d,%s,%d,",
                                 TsToStr(TimeCurrent()), nyTime, m_sym, s.id, SetupTypeToStr(s.setupType), WindowToStr(s.window), s.macroId,
                                 DirToStr(s.dir), decision, CsvSafe(reason), s.score, DirToStr(s.bias), s.biasAligned ? 1 : 0);
      line += StringFormat("%s,%d,%s,%s,%.3f,%s,%s,%.3f,",
                           LiqTypeToStr((int)s.sweep.type), s.sweep.rank, D2(s.sweep.level, _Digits), D2(s.sweep.extreme, _Digits),
                           s.sweep.penetrationATR, TsToStr(s.mss.barTime), D2(s.mss.brokenLevel, _Digits), s.dispBodyATR);
      line += StringFormat("%s,%s,%s,%.3f,%d,%s,%s,%d,%d,%s,%s,%d,%d,%d,%d,",
                           D2(s.fvg.top, _Digits), D2(s.fvg.bottom, _Digits), D2(s.fvg.ce, _Digits), s.fvgSizeATR, s.fvgUntouched ? 1 : 0,
                           D2(s.breaker.zoneTop, _Digits), D2(s.breaker.zoneBottom, _Digits), s.unicorn ? 1 : 0, s.bpr ? 1 : 0,
                           CsvSafe(s.refLevelName), D2(s.trueOpen, _Digits), s.trueOpenAligned ? 1 : 0, s.dowScore, s.eqWarning ? 1 : 0,
                           s.relaxed ? 1 : 0);
      line += StringFormat("%s,%s,%.3f,%d,%.3f,%d,%d,",
                           D2(s.legLow, _Digits), D2(s.legHigh, _Digits), s.retracePct, s.inOTE ? 1 : 0, s.pdPct, s.inDiscount ? 1 : 0, s.inMacro ? 1 : 0);
      line += StringFormat("%s,%s,%s,%.2f,%s,%s,%d,%s,%s,%.0f,%.2f,%.2f,%.3f,%.3f,%s,%I64u,",
                           D2(s.entry, _Digits), D2(s.sl, _Digits), D2(s.tp, _Digits), s.rr, D2(s.riskDist, _Digits),
                           LiqTypeToStr(s.tpSource), s.marketEntry ? 1 : 0, D2(s.atr, _Digits), D2(s.atrD1, _Digits), s.spreadPts,
                           lot, riskMoney, adaptFactor, modelProb, bucket, ticket);
      line += FeatureCSV(features);
      FileWriteString(h, line + "\r\n");
      FileClose(h);
   }

   string ExitHeader()
   {
      string h = "ts_server,symbol,ticket,setup_id,window,direction,bucket,open_time,close_time,duration_min,entry,exit_price,";
      h += "exit_reason,risk_money,net_profit,r_realized,mfe_r,mae_r,planned_rr,score";
      return h;
   }

   void LogExit(const ulong ticket, const string setupId, const ENUM_SB_WINDOW window, const ENUM_ICT_DIR dir, const string bucket,
                const datetime openTime, const datetime closeTime, const double entry, const double exitPrice, const string reason,
                const double riskMoney, const double netProfit, const double rRealized, const double mfeR, const double maeR,
                const double plannedRR, const int score)
   {
      if(!m_enabled) return;
      int h = OpenAppend(StringFormat("exits_%s_%s.csv", m_sym, MonthTag(TimeCurrent())), ExitHeader());
      if(h == INVALID_HANDLE) return;
      double dur = ((long)closeTime - (long)openTime) / 60.0;
      string line = StringFormat("%s,%s,%I64u,%s,%s,%s,%s,%s,%s,%.1f,%s,%s,%s,%.2f,%.2f,%.3f,%.3f,%.3f,%.2f,%d",
                                 TsToStr(TimeCurrent()), m_sym, ticket, setupId, WindowToStr(window), DirToStr(dir), bucket,
                                 TsToStr(openTime), TsToStr(closeTime), dur, D2(entry, _Digits), D2(exitPrice, _Digits),
                                 CsvSafe(reason), riskMoney, netProfit, rRealized, mfeR, maeR, plannedRR, score);
      FileWriteString(h, line + "\r\n");
      FileClose(h);
   }

   void LogEvent(const string type, const string text)
   {
      if(!m_enabled) return;
      int h = OpenAppend(StringFormat("events_%s_%s.csv", m_sym, MonthTag(TimeCurrent())), "ts_server,symbol,type,text");
      if(h == INVALID_HANDLE) return;
      FileWriteString(h, StringFormat("%s,%s,%s,%s\r\n", TsToStr(TimeCurrent()), m_sym, type, CsvSafe(text)));
      FileClose(h);
   }
};

#endif // ICTPRO_JOURNAL_MQH


//====================================================================
//  MODULE : ICTPro_Adaptive.mqh
//====================================================================
#ifndef ICTPRO_ADAPTIVE_MQH
#define ICTPRO_ADAPTIVE_MQH

class CAdaptiveStats
{
private:
   string m_keys[];
   int    m_n[];
   double m_sumR[];
   double m_sumR2[];
   int    m_count;
   string m_file;
   ENUM_ADAPT_MODE m_mode;
   int    m_minSamples;
   double m_minFactor;
   double m_maxFactor;
   double m_priorWeight;
   double m_priorR;
   double m_gateZ;
   int    m_flags;

   int Find(const string key)
   {
      for(int i = 0; i < m_count; i++) if(m_keys[i] == key) return i;
      return -1;
   }
   int Ensure(const string key)
   {
      int i = Find(key);
      if(i >= 0) return i;
      ArrayResize(m_keys, m_count + 1); ArrayResize(m_n, m_count + 1);
      ArrayResize(m_sumR, m_count + 1); ArrayResize(m_sumR2, m_count + 1);
      m_keys[m_count] = key; m_n[m_count] = 0; m_sumR[m_count] = 0; m_sumR2[m_count] = 0;
      m_count++;
      return m_count - 1;
   }

public:
   CAdaptiveStats()
   {
      m_count = 0; m_file = "ICTPro\\adaptive_stats.csv"; m_mode = ADAPT_OFF; m_minSamples = 30;
      m_minFactor = 0.5; m_maxFactor = 1.25; m_priorWeight = 20; m_priorR = 0.0; m_gateZ = 1.0;
      m_flags = FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE;
   }

   void Init(const string file, const ENUM_ADAPT_MODE mode, const int minSamples, const double minFactor,
             const double maxFactor, const double priorWeight)
   {
      m_file = file; m_mode = mode; m_minSamples = MathMax(5, minSamples);
      m_minFactor = minFactor; m_maxFactor = maxFactor; m_priorWeight = MathMax(1.0, priorWeight);
      m_count = 0;
      ArrayResize(m_keys, 0); ArrayResize(m_n, 0); ArrayResize(m_sumR, 0); ArrayResize(m_sumR2, 0);
      if(m_mode != ADAPT_OFF && !IsOptimization()) Load();
   }

   static string ScoreBand(const int score)
   {
      if(score >= 7) return "S_HIGH";
      if(score >= 5) return "S_MID";
      return "S_LOW";
   }
   static string BucketKey(const ENUM_SETUP_TYPE t, const ENUM_SB_WINDOW w, const int macroId, const int score)
   {
      string ctx = (t == SETUP_MACRO_BREAKER) ? StringFormat("M%04d", macroId) : WindowToStr(w);
      return SetupTypeToStr(t) + "|" + ctx + "|" + ScoreBand(score);
   }

   void Load()
   {
      int h = FileOpen(m_file, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
      if(h == INVALID_HANDLE) return;
      while(!FileIsEnding(h))
      {
         string line = FileReadString(h);
         string p[];
         if(StringSplit(line, ',', p) < 4) continue;
         if(p[0] == "bucket") continue;
         int i = Ensure(p[0]);
         m_n[i] = (int)StringToInteger(p[1]);
         m_sumR[i] = StringToDouble(p[2]);
         m_sumR2[i] = StringToDouble(p[3]);
      }
      FileClose(h);
      Print("[Adaptive] ", m_count, " buckets charges depuis ", m_file);
   }

   void Save()
   {
      if(m_mode == ADAPT_OFF || IsOptimization()) return;
      int h = FileOpen(m_file, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
      if(h == INVALID_HANDLE) { Print("[Adaptive] sauvegarde impossible : ", GetLastError()); return; }
      FileWriteString(h, "bucket,n,sum_r,sum_r2\r\n");
      for(int i = 0; i < m_count; i++)
         FileWriteString(h, StringFormat("%s,%d,%.6f,%.6f\r\n", m_keys[i], m_n[i], m_sumR[i], m_sumR2[i]));
      FileClose(h);
   }

   void Update(const string key, const double r)
   {
      if(m_mode == ADAPT_OFF) return;
      int i = Ensure(key);
      m_n[i]++; m_sumR[i] += r; m_sumR2[i] += r * r;
      int a = Ensure("ALL");
      m_n[a]++; m_sumR[a] += r; m_sumR2[a] += r * r;
      Save();
   }

   double ShrunkExpectancy(const string key, int &n)
   {
      int i = Find(key);
      n = (i >= 0) ? m_n[i] : 0;
      double sum = (i >= 0) ? m_sumR[i] : 0;
      return (sum + m_priorWeight * m_priorR) / (n + m_priorWeight);
   }

   double SizeFactor(const string key, string &why)
   {
      why = "neutre";
      if(m_mode == ADAPT_OFF) return 1.0;
      int n;
      double e = ShrunkExpectancy(key, n);
      if(n < m_minSamples) { why = StringFormat("echantillon %d < %d", n, m_minSamples); return 1.0; }
      double f = 1.0 + 0.5 * e;
      f = MathMax(m_minFactor, MathMin(m_maxFactor, f));
      why = StringFormat("n=%d E[R]=%.2f", n, e);
      return f;
   }

   bool Blocked(const string key, string &why)
   {
      why = "";
      if(m_mode != ADAPT_SIZE_AND_GATE) return false;
      int i = Find(key);
      if(i < 0 || m_n[i] < m_minSamples) return false;
      double n = m_n[i];
      double mean = m_sumR[i] / n;
      double var = MathMax(0.0, m_sumR2[i] / n - mean * mean);
      double se = MathSqrt(var / n);
      if(mean + m_gateZ * se < 0)
      {
         why = StringFormat("bucket %s bloque : E[R]=%.2f +/- %.2f sur %d trades", key, mean, se, m_n[i]);
         return true;
      }
      return false;
   }

   string Summary()
   {
      if(m_mode == ADAPT_OFF) return "Apprentissage : desactive";
      int n; double e = ShrunkExpectancy("ALL", n);
      return StringFormat("Apprentissage : %d buckets, %d trades, E[R] global %.2f", m_count, n, e);
   }
};

//+------------------------------------------------------------------+
//| Filtre par modele ONNX entraine hors ligne                        |
//+------------------------------------------------------------------+
class CModelGate
{
private:
   long   m_handle;
   bool   m_enabled;
   double m_minProb;
   string m_file;

public:
   CModelGate() { m_handle = INVALID_HANDLE; m_enabled = false; m_minProb = 0.55; m_file = ""; }

   bool Init(const bool enabled, const string file, const double minProb)
   {
      m_enabled = false;
      m_minProb = minProb;
      m_file = file;
      if(!enabled || file == "") return false;
      ResetLastError();
      m_handle = OnnxCreate(file, ONNX_COMMON_FOLDER);
      if(m_handle == INVALID_HANDLE)
         m_handle = OnnxCreate(file, ONNX_DEFAULT);
      if(m_handle == INVALID_HANDLE)
      {
         Print("[Model] chargement impossible : ", file, " erreur ", GetLastError(), " (filtre desactive)");
         return false;
      }
      const ulong inShape[] = {1, ICTPRO_FEATURES};
      const ulong outShape[] = {1, 1};
      if(!OnnxSetInputShape(m_handle, 0, inShape) || !OnnxSetOutputShape(m_handle, 0, outShape))
      {
         Print("[Model] formes d'entree/sortie refusees, erreur ", GetLastError(), " (filtre desactive)");
         OnnxRelease(m_handle);
         m_handle = INVALID_HANDLE;
         return false;
      }
      m_enabled = true;
      Print("[Model] modele charge : ", file, " seuil ", minProb);
      return true;
   }

   void Release()
   {
      if(m_handle != INVALID_HANDLE) OnnxRelease(m_handle);
      m_handle = INVALID_HANDLE;
      m_enabled = false;
   }

   bool Enabled() { return m_enabled; }

   double Predict(const float &f[])
   {
      if(!m_enabled) return -1.0;
      matrixf X(1, ICTPRO_FEATURES);
      for(int i = 0; i < ICTPRO_FEATURES; i++) X[0][i] = f[i];
      matrixf Y(1, 1);
      if(!OnnxRun(m_handle, ONNX_DEFAULT, X, Y))
      {
         Print("[Model] OnnxRun a echoue, erreur ", GetLastError(), " (filtre desactive)");
         m_enabled = false;
         return -1.0;
      }
      return (double)Y[0][0];
   }

   bool Pass(const double prob) { return (!m_enabled || prob < 0 || prob >= m_minProb); }
};

#endif // ICTPRO_ADAPTIVE_MQH


//====================================================================
//  MODULE : ICTPro_PositionManager.mqh
//====================================================================
#ifndef ICTPRO_POSITIONMANAGER_MQH
#define ICTPRO_POSITIONMANAGER_MQH

enum ENUM_POS_STAGE { STAGE_OPEN = 0, STAGE_BE = 1, STAGE_PARTIAL = 2, STAGE_TRAILING = 3 };

struct STradeState
{
   ulong          ticket;        // ticket d'ordre (pending) ou de position
   long           posId;         // identifiant de position (0 tant que pending)
   bool           isPending;
   ENUM_ICT_DIR   dir;
   double         entry;
   double         sl0;
   double         tp;
   double         riskDist;
   double         riskMoney;
   double         initVolume;
   datetime       placedTime;
   datetime       openTime;
   datetime       expiry;
   datetime       windowEnd;
   double         invalidLevel;  // extreme du sweep : cloture au-dela = ordre annule
   int            stage;
   bool           beDone;
   bool           partialDone;
   double         mfeR;
   double         maeR;
   int            window;
   int            macroId;
   int            setupType;
   int            score;
   double         plannedRR;
   bool           finalized;
};

struct SPMParams
{
   double breakEvenAtR;
   int    beExtraPoints;
   double commissionPerLot;   // devise du compte, aller-retour, pour 1 lot
   bool   enablePartial;
   double partialAtR;
   double partialPercent;
   bool   enableTrailing;
   double trailingStartR;
   double trailingATRMult;
   bool   trailBySwing;
   int    trailMinStepPoints;
   int    timeStopMinutes;
   double timeStopMinR;
   int    swingStrength;
   int    maxHoldMinutes;
};

class CPositionManager
{
private:
   STradeState    m_st[];
   string         m_ids[];
   int            m_count;
   string         m_sym;
   long           m_magic;
   CExecutor     *m_exec;
   CJournal      *m_journal;
   CAdaptiveStats *m_stats;
   SPMParams      m_p;
   string         m_gvPrefix;
   datetime       m_lastBarTime;

   void SaveGV(const int i)
   {
      string k = m_gvPrefix + (string)m_st[i].ticket + "_";
      GlobalVariableSet(k + "sl0", m_st[i].sl0);
      GlobalVariableSet(k + "entry", m_st[i].entry);
      GlobalVariableSet(k + "risk", m_st[i].riskMoney);
      GlobalVariableSet(k + "wend", (double)(long)m_st[i].windowEnd);
      GlobalVariableSet(k + "inv", m_st[i].invalidLevel);
      GlobalVariableSet(k + "win", (double)m_st[i].window);
      GlobalVariableSet(k + "macro", (double)m_st[i].macroId);
      GlobalVariableSet(k + "stype", (double)m_st[i].setupType);
      GlobalVariableSet(k + "score", (double)m_st[i].score);
      GlobalVariableSet(k + "rr", m_st[i].plannedRR);
      GlobalVariableSet(k + "vol0", m_st[i].initVolume);
      GlobalVariableSet(k + "stage", (double)m_st[i].stage);
      GlobalVariableSet(k + "be", m_st[i].beDone ? 1.0 : 0.0);
      GlobalVariableSet(k + "part", m_st[i].partialDone ? 1.0 : 0.0);
      GlobalVariableSet(k + "mfe", m_st[i].mfeR);
      GlobalVariableSet(k + "mae", m_st[i].maeR);
   }
   void DeleteGV(const ulong ticket)
   {
      string k = m_gvPrefix + (string)ticket + "_";
      string names[] = {"sl0", "entry", "risk", "wend", "inv", "win", "macro", "stype", "score", "rr", "vol0", "stage", "be", "part", "mfe", "mae"};
      for(int i = 0; i < ArraySize(names); i++)
         if(GlobalVariableCheck(k + names[i])) GlobalVariableDel(k + names[i]);
   }
   double GV(const ulong ticket, const string name, const double def)
   {
      string k = m_gvPrefix + (string)ticket + "_" + name;
      return GlobalVariableCheck(k) ? GlobalVariableGet(k) : def;
   }

   int Find(const ulong ticket)
   {
      for(int i = 0; i < m_count; i++) if(m_st[i].ticket == ticket) return i;
      return -1;
   }
   int FindByPosId(const long posId)
   {
      for(int i = 0; i < m_count; i++) if(m_st[i].posId == posId && !m_st[i].isPending) return i;
      return -1;
   }
   void Remove(const int i)
   {
      DeleteGV(m_st[i].ticket);
      for(int k = i; k < m_count - 1; k++) { m_st[k] = m_st[k + 1]; m_ids[k] = m_ids[k + 1]; }
      m_count--;
      ArrayResize(m_st, m_count);
      ArrayResize(m_ids, m_count);
   }
   int Append(const STradeState &s, const string id)
   {
      ArrayResize(m_st, m_count + 1);
      ArrayResize(m_ids, m_count + 1);
      m_st[m_count] = s;
      m_ids[m_count] = id;
      m_count++;
      return m_count - 1;
   }

   //--- Offset de break-even : spread + commission convertie en prix + marge fixe
   double BEOffset(const double volume)
   {
      double spread = SymbolInfoDouble(m_sym, SYMBOL_ASK) - SymbolInfoDouble(m_sym, SYMBOL_BID);
      double tv = SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_VALUE);
      double ts = SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_SIZE);
      double commPrice = 0;
      if(tv > 0 && ts > 0 && m_p.commissionPerLot > 0)
         commPrice = m_p.commissionPerLot / (tv / ts);
      return spread + commPrice + m_p.beExtraPoints * _Point;
   }

   bool PositionNet(const long posId, double &net, datetime &closeTime, double &exitPrice, double &closedVolume)
   {
      net = 0; closeTime = 0; exitPrice = 0; closedVolume = 0;
      if(!HistorySelectByPosition(posId)) return false;
      int n = HistoryDealsTotal();
      double vwap = 0;
      for(int i = 0; i < n; i++)
      {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0) continue;
         net += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_SWAP);
         long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
         {
            double v = HistoryDealGetDouble(d, DEAL_VOLUME);
            vwap += HistoryDealGetDouble(d, DEAL_PRICE) * v;
            closedVolume += v;
            datetime t = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
            if(t > closeTime) closeTime = t;
         }
      }
      if(closedVolume > 0) exitPrice = vwap / closedVolume;
      return (n > 0);
   }

   string ExitReasonFromHistory(const long posId)
   {
      if(!HistorySelectByPosition(posId)) return "UNKNOWN";
      int n = HistoryDealsTotal();
      for(int i = n - 1; i >= 0; i--)
      {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0) continue;
         long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN) continue;
         long reason = HistoryDealGetInteger(d, DEAL_REASON);
         if(reason == DEAL_REASON_SL) return "SL";
         if(reason == DEAL_REASON_TP) return "TP";
         if(reason == DEAL_REASON_SO) return "STOP_OUT";
         if(reason == DEAL_REASON_EXPERT) return "EA";
         if(reason == DEAL_REASON_CLIENT || reason == DEAL_REASON_MOBILE || reason == DEAL_REASON_WEB) return "MANUAL";
         return "OTHER";
      }
      return "UNKNOWN";
   }

public:
   CPositionManager() { m_count = 0; m_sym = ""; m_magic = 0; m_exec = NULL; m_journal = NULL; m_stats = NULL; m_gvPrefix = ""; m_lastBarTime = 0; }

   void Init(const string sym, const long magic, CExecutor *exec, CJournal *journal, CAdaptiveStats *stats, const SPMParams &p)
   {
      m_sym = sym; m_magic = magic; m_exec = exec; m_journal = journal; m_stats = stats; m_p = p;
      m_gvPrefix = StringFormat("ICTPro_%s_%I64d_T", sym, magic);
      m_count = 0;
      ArrayResize(m_st, 0);
      ArrayResize(m_ids, 0);
      Rebuild();
   }

   int Count() { return m_count; }

   void Rebuild()
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic || PositionGetString(POSITION_SYMBOL) != m_sym) continue;
         STradeState s;
         ZeroMemory(s);
         s.ticket = t;
         s.posId = PositionGetInteger(POSITION_IDENTIFIER);
         s.isPending = false;
         s.dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? DIR_BUY : DIR_SELL;
         s.entry = PositionGetDouble(POSITION_PRICE_OPEN);
         s.tp = PositionGetDouble(POSITION_TP);
         s.openTime = (datetime)PositionGetInteger(POSITION_TIME);
         s.placedTime = s.openTime;
         double curSL = PositionGetDouble(POSITION_SL);
         s.sl0 = GV(t, "sl0", curSL);
         if(s.sl0 == 0) s.sl0 = curSL;
         s.riskDist = MathAbs(s.entry - s.sl0);
         s.riskMoney = GV(t, "risk", 0);
         s.initVolume = GV(t, "vol0", PositionGetDouble(POSITION_VOLUME));
         s.windowEnd = (datetime)(long)GV(t, "wend", 0);
         s.invalidLevel = GV(t, "inv", 0);
         s.window = (int)GV(t, "win", 0);
         s.macroId = (int)GV(t, "macro", 0);
         s.setupType = (int)GV(t, "stype", 0);
         s.score = (int)GV(t, "score", 0);
         s.plannedRR = GV(t, "rr", 0);
         s.stage = (int)GV(t, "stage", 0);
         s.beDone = GV(t, "be", 0) > 0.5;
         s.partialDone = GV(t, "part", 0) > 0.5;
         s.mfeR = GV(t, "mfe", 0);
         s.maeR = GV(t, "mae", 0);
         if(s.riskMoney <= 0 && s.riskDist > 0)
         {
            double p = 0;
            if(OrderCalcProfit(s.dir == DIR_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, m_sym, s.initVolume, s.entry, s.sl0, p))
               s.riskMoney = MathAbs(p);
         }
         if(!s.beDone && ((s.dir == DIR_BUY && curSL >= s.entry) || (s.dir == DIR_SELL && curSL > 0 && curSL <= s.entry))) s.beDone = true;
         if(!s.partialDone && PositionGetDouble(POSITION_VOLUME) < s.initVolume - 1e-8) s.partialDone = true;
         Append(s, "REBUILT_" + (string)t);
      }
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong t = OrderGetTicket(i);
         if(t == 0) continue;
         if(OrderGetInteger(ORDER_MAGIC) != m_magic || OrderGetString(ORDER_SYMBOL) != m_sym) continue;
         STradeState s;
         ZeroMemory(s);
         s.ticket = t;
         s.isPending = true;
         long ot = OrderGetInteger(ORDER_TYPE);
         s.dir = (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP) ? DIR_BUY : DIR_SELL;
         s.entry = OrderGetDouble(ORDER_PRICE_OPEN);
         s.sl0 = OrderGetDouble(ORDER_SL);
         s.tp = OrderGetDouble(ORDER_TP);
         s.riskDist = MathAbs(s.entry - s.sl0);
         s.placedTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
         s.expiry = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
         s.initVolume = OrderGetDouble(ORDER_VOLUME_INITIAL);
         s.riskMoney = GV(t, "risk", 0);
         s.windowEnd = (datetime)(long)GV(t, "wend", 0);
         s.invalidLevel = GV(t, "inv", 0);
         s.window = (int)GV(t, "win", 0);
         s.macroId = (int)GV(t, "macro", 0);
         s.setupType = (int)GV(t, "stype", 0);
         s.score = (int)GV(t, "score", 0);
         s.plannedRR = GV(t, "rr", 0);
         if(s.expiry == 0) s.expiry = (datetime)((long)s.windowEnd + 3600);
         Append(s, "REBUILT_" + (string)t);
      }
      if(m_count > 0) Print("[Positions] ", m_count, " etat(s) reconstruit(s)");
   }

   void Register(const ulong ticket, const bool isPending, const SSetup &s, const double lot, const double riskMoney, const datetime expiry)
   {
      STradeState st;
      ZeroMemory(st);
      st.ticket = ticket;
      st.posId = isPending ? 0 : (long)ticket;
      st.isPending = isPending;
      st.dir = s.dir;
      st.entry = s.entry;
      st.sl0 = s.sl;
      st.tp = s.tp;
      st.riskDist = s.riskDist;
      st.riskMoney = riskMoney;
      st.initVolume = lot;
      st.placedTime = TimeCurrent();
      st.openTime = isPending ? 0 : TimeCurrent();
      st.expiry = expiry;
      st.windowEnd = s.windowEnd;
      st.invalidLevel = s.sweep.extreme;
      st.window = (int)s.window;
      st.macroId = s.macroId;
      st.setupType = (int)s.setupType;
      st.score = s.score;
      st.plannedRR = s.rr;
      int i = Append(st, s.id);
      SaveGV(i);
   }

   void OnOrderFilled(const ulong orderTicket, const long posId, const double fillPrice, const datetime t)
   {
      int i = Find(orderTicket);
      if(i < 0 || !m_st[i].isPending) return;
      m_st[i].isPending = false;
      m_st[i].posId = posId;
      m_st[i].openTime = t;
      if(fillPrice > 0) { m_st[i].entry = fillPrice; m_st[i].riskDist = MathAbs(fillPrice - m_st[i].sl0); }
      for(int k = PositionsTotal() - 1; k >= 0; k--)
      {
         ulong pt = PositionGetTicket(k);
         if(pt != 0 && PositionGetInteger(POSITION_IDENTIFIER) == posId) { DeleteGV(m_st[i].ticket); m_st[i].ticket = pt; break; }
      }
      SaveGV(i);
      Print("[Positions] ordre ", orderTicket, " execute -> position ", m_st[i].ticket);
   }

   void OnPositionClosed(const long posId, const string reasonHint)
   {
      int i = FindByPosId(posId);
      if(i < 0) return;
      if(m_st[i].finalized) { Remove(i); return; }
      double net, exitPrice, closedVol; datetime closeT;
      PositionNet(posId, net, closeT, exitPrice, closedVol);
      double r = (m_st[i].riskMoney > 0) ? net / m_st[i].riskMoney : 0;
      string reason = (reasonHint != "") ? reasonHint : ExitReasonFromHistory(posId);
      string bucket = CAdaptiveStats::BucketKey((ENUM_SETUP_TYPE)m_st[i].setupType, (ENUM_SB_WINDOW)m_st[i].window, m_st[i].macroId, m_st[i].score);
      if(m_stats != NULL) m_stats.Update(bucket, r);
      if(m_journal != NULL)
         m_journal.LogExit(m_st[i].ticket, m_ids[i], (ENUM_SB_WINDOW)m_st[i].window, m_st[i].dir, bucket,
                           m_st[i].openTime, closeT, m_st[i].entry, exitPrice, reason, m_st[i].riskMoney, net, r,
                           m_st[i].mfeR, m_st[i].maeR, m_st[i].plannedRR, m_st[i].score);
      Print(StringFormat("[Positions] #%I64u ferme (%s) net %.2f = %.2fR  MFE %.2fR MAE %.2fR", m_st[i].ticket, reason, net, r, m_st[i].mfeR, m_st[i].maeR));
      m_st[i].finalized = true;
      Remove(i);
   }

   void OnOrderGone(const ulong orderTicket, const string reason)
   {
      int i = Find(orderTicket);
      if(i < 0 || !m_st[i].isPending) return;
      if(m_journal != NULL) m_journal.LogEvent("ORDER_" + reason, StringFormat("ordre %I64u setup %s", orderTicket, m_ids[i]));
      Remove(i);
   }

   //--- A appeler a chaque tick
   void OnTick(const MqlRates &ltf[], const int ltfCount, const double atr)
   {
      datetime now = TimeCurrent();
      double bid = SymbolInfoDouble(m_sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_sym, SYMBOL_ASK);
      bool newBar = (ltfCount > 1 && ltf[0].time != m_lastBarTime);
      if(newBar) m_lastBarTime = ltf[0].time;

      for(int i = m_count - 1; i >= 0; i--)
      {
         //--- ordres en attente
         if(m_st[i].isPending)
         {
            if(!OrderSelect(m_st[i].ticket))
            {
               if(HistoryOrderSelect(m_st[i].ticket))
               {
                  long state = HistoryOrderGetInteger(m_st[i].ticket, ORDER_STATE);
                  if(state == ORDER_STATE_FILLED)
                  {
                     long pid = HistoryOrderGetInteger(m_st[i].ticket, ORDER_POSITION_ID);
                     OnOrderFilled(m_st[i].ticket, pid, 0, now);
                     continue;
                  }
               }
               OnOrderGone(m_st[i].ticket, "GONE");
               continue;
            }
            if(m_st[i].expiry > 0 && now >= m_st[i].expiry)
            {
               if(m_exec.DeleteOrder(m_st[i].ticket)) OnOrderGone(m_st[i].ticket, "EXPIRED");
               continue;
            }
            //--- cible atteinte avant l'execution : pas de trade
            if(m_st[i].tp > 0)
            {
               bool tpHit = (m_st[i].dir == DIR_BUY) ? (bid >= m_st[i].tp) : (ask <= m_st[i].tp);
               if(tpHit && m_exec.DeleteOrder(m_st[i].ticket)) { OnOrderGone(m_st[i].ticket, "TARGET_BEFORE_FILL"); continue; }
            }
            if(newBar && m_st[i].invalidLevel > 0 && ltfCount > 1)
            {
               bool invalid = (m_st[i].dir == DIR_BUY) ? (ltf[1].close < m_st[i].invalidLevel) : (ltf[1].close > m_st[i].invalidLevel);
               if(invalid && m_exec.DeleteOrder(m_st[i].ticket)) { OnOrderGone(m_st[i].ticket, "INVALIDATED"); continue; }
            }
            continue;
         }

         //--- positions
         if(!PositionSelectByTicket(m_st[i].ticket))
         {
            OnPositionClosed(m_st[i].posId, "");
            continue;
         }
         double price = (m_st[i].dir == DIR_BUY) ? bid : ask;
         double curSL = PositionGetDouble(POSITION_SL);
         double curTP = PositionGetDouble(POSITION_TP);
         double vol = PositionGetDouble(POSITION_VOLUME);
         if(m_st[i].riskDist <= 0) continue;
         double r = (m_st[i].dir == DIR_BUY) ? (price - m_st[i].entry) / m_st[i].riskDist : (m_st[i].entry - price) / m_st[i].riskDist;
         bool changed = false;
         if(r > m_st[i].mfeR) { m_st[i].mfeR = r; changed = true; }
         if(r < m_st[i].maeR) { m_st[i].maeR = r; changed = true; }

         //--- 1. break-even
         if(!m_st[i].beDone && m_p.breakEvenAtR > 0 && r >= m_p.breakEvenAtR)
         {
            double off = BEOffset(vol);
            double be = (m_st[i].dir == DIR_BUY) ? m_st[i].entry + off : m_st[i].entry - off;
            bool slWorse = (m_st[i].dir == DIR_BUY) ? (curSL < be) : (curSL == 0 || curSL > be);
            if(slWorse)
            {
               if(m_exec.ModifyPosition(m_st[i].ticket, be, curTP))
               {
                  m_st[i].beDone = true; m_st[i].stage = STAGE_BE; changed = true;
                  Print(StringFormat("[Positions] #%I64u break-even a %s (%.2fR)", m_st[i].ticket, DoubleToString(be, _Digits), r));
               }
            }
            else { m_st[i].beDone = true; changed = true; }
         }

         //--- 2. cloture partielle unique
         if(m_p.enablePartial && !m_st[i].partialDone && r >= m_p.partialAtR)
         {
            double minL = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_MIN);
            double part = m_exec.NormalizeVolume(vol * m_p.partialPercent / 100.0);
            if(part > 0 && vol - part >= minL - 1e-9)
            {
               if(m_exec.ClosePartial(m_st[i].ticket, part))
               {
                  m_st[i].partialDone = true; m_st[i].stage = STAGE_PARTIAL; changed = true;
                  Print(StringFormat("[Positions] #%I64u partiel %.2f lot a %.2fR", m_st[i].ticket, part, r));
               }
            }
            else { m_st[i].partialDone = true; changed = true; }
         }

         //--- 3. trailing : ne recule jamais
         if(m_p.enableTrailing && r >= m_p.trailingStartR && atr > 0)
         {
            double cand = 0;
            if(m_st[i].dir == DIR_BUY)
            {
               cand = price - m_p.trailingATRMult * atr;
               if(m_p.trailBySwing)
               {
                  double sw = CMarketStructure::LastSwingLowBelow(ltf, ltfCount, m_p.swingStrength, price, 60);
                  if(sw > 0) cand = MathMax(cand, sw - m_p.beExtraPoints * _Point);
               }
               if(cand > curSL + m_p.trailMinStepPoints * _Point && cand > m_st[i].entry)
               {
                  if(m_exec.ModifyPosition(m_st[i].ticket, cand, curTP)) { m_st[i].stage = STAGE_TRAILING; changed = true; }
               }
            }
            else
            {
               cand = price + m_p.trailingATRMult * atr;
               if(m_p.trailBySwing)
               {
                  double sw = CMarketStructure::LastSwingHighAbove(ltf, ltfCount, m_p.swingStrength, price, 60);
                  if(sw > 0) cand = MathMin(cand, sw + m_p.beExtraPoints * _Point);
               }
               if((curSL == 0 || cand < curSL - m_p.trailMinStepPoints * _Point) && cand < m_st[i].entry)
               {
                  if(m_exec.ModifyPosition(m_st[i].ticket, cand, curTP)) { m_st[i].stage = STAGE_TRAILING; changed = true; }
               }
            }
         }

         //--- 4. time stop
         bool timeOut = false;
         if(m_p.timeStopMinutes > 0 && m_st[i].windowEnd > 0 &&
            now >= (datetime)((long)m_st[i].windowEnd + (long)m_p.timeStopMinutes * 60) && r < m_p.timeStopMinR)
            timeOut = true;
         if(m_p.maxHoldMinutes > 0 && m_st[i].openTime > 0 && (long)now - (long)m_st[i].openTime >= (long)m_p.maxHoldMinutes * 60)
            timeOut = true;
         if(timeOut)
         {
            if(m_exec.ClosePosition(m_st[i].ticket))
            {
               Print(StringFormat("[Positions] #%I64u time stop a %.2fR", m_st[i].ticket, r));
               OnPositionClosed(m_st[i].posId, "TIME_STOP");
               continue;
            }
         }
         if(changed) SaveGV(i);
      }
   }

   void FlattenAll(const string reason)
   {
      for(int i = m_count - 1; i >= 0; i--)
      {
         if(m_st[i].isPending)
         {
            if(m_exec.DeleteOrder(m_st[i].ticket)) OnOrderGone(m_st[i].ticket, reason);
         }
         else if(PositionSelectByTicket(m_st[i].ticket))
         {
            if(m_exec.ClosePosition(m_st[i].ticket)) OnPositionClosed(m_st[i].posId, reason);
         }
      }
   }

   string Dashboard()
   {
      if(m_count == 0) return "Positions : aucune\n";
      string s = "";
      for(int i = 0; i < m_count; i++)
      {
         if(m_st[i].isPending)
            s += StringFormat("Ordre #%I64u %s limite %s SL %s TP %s expire %s\n", m_st[i].ticket, DirToStr(m_st[i].dir),
                              DoubleToString(m_st[i].entry, _Digits), DoubleToString(m_st[i].sl0, _Digits), DoubleToString(m_st[i].tp, _Digits), TsToStr(m_st[i].expiry));
         else
            s += StringFormat("Position #%I64u %s entree %s  MFE %.2fR MAE %.2fR  BE:%s Partiel:%s Stage:%d\n", m_st[i].ticket, DirToStr(m_st[i].dir),
                              DoubleToString(m_st[i].entry, _Digits), m_st[i].mfeR, m_st[i].maeR, m_st[i].beDone ? "oui" : "non", m_st[i].partialDone ? "oui" : "non", m_st[i].stage);
      }
      return s;
   }
};

#endif // ICTPRO_POSITIONMANAGER_MQH


//====================================================================
//  PROGRAMME PRINCIPAL
//====================================================================

//+------------------------------------------------------------------+
//| Parametres                                                       |
//+------------------------------------------------------------------+
input group "=== STRATEGIES ==="
input bool InpEnableSilverBullet = true;   // Silver Bullet (M5)
input bool InpEnableMacroBreaker = true;   // Macro Breaker (M1)

input group "=== PRISE DE POSITION v6.20 ==="
input bool   InpSBTakeFirstFVG    = true;  // SB : entrer sur la 1ere FVG du displacement
input double InpSBMinRetrace      = 0.35;  // SB : retracement minimal de la jambe a l'entree
input bool   InpFVGRequireBody    = false; // Exiger un corps directionnel sur la bougie centrale du FVG
input bool   InpMBAllowRetested   = true;  // MB : accepter un breaker deja touche (non viole)
input int    InpSBRelaxAfterMin   = 30;    // SB : 2e passe relachee N min apres le debut de fenetre (0 = off)
input int    InpMBRelaxAfterMin   = 8;     // MB : 2e passe relachee N min apres le debut de macro (0 = off)

input group "=== RISQUE PAR TRADE (lot calcule sur le capital) ==="
input ENUM_RISK_MODE InpRiskMode          = RISK_PERCENT_EQUITY; // Mode de risque
input double         InpRiskPercent       = 0.75;   // Risque par trade en % (modes % equite / % balance)
input double         InpRiskFixedMoney    = 50.0;   // Risque par trade en devise du compte (mode montant fixe)
input double         InpFixedLot          = 0.01;   // Lot fixe (mode lot fixe - DECONSEILLE)
input double         InpMaxLotCap         = 20.0;   // Plafond absolu de lot

input group "=== PLAFONDS DE RISQUE (aucun minimum de trades) ==="
input double InpDailyLossLimitPct     = 3.0;   // Perte journaliere max en % (0 = off)
input double InpWeeklyLossLimitPct    = 6.0;   // Perte hebdomadaire max en % (0 = off)
input double InpMaxOpenRiskPct        = 2.5;   // Risque ouvert cumule max en % de l'equite
input double InpMaxDrawdownHaltPct    = 0.0;   // Arret complet si drawdown > % (0 = off ; 25 conseille en live)
input int    InpMaxConcurrentPositions = 2;    // Positions + ordres simultanes max
input int    InpMaxConsecutiveLosses  = 0;     // Pertes consecutives du jour avant pause (0 = off)
input int    InpMaxTradesPerDay       = 8;     // Trades max par jour NY (0 = off)
input int    InpMaxTradesPerWindow    = 1;     // Trades max par fenetre / macro (0 = off)
input double InpMaxSpreadATR          = 0.15;  // Spread max en fraction de l'ATR M5 (0 = off)
input int    InpMaxSpreadPoints       = 60;    // Spread max en points, base 2 decimales (auto-ajuste)
input double InpMinAccountBalance     = 100.0; // Balance minimale
input int    InpFridayLastEntryHourNY = 12;    // Vendredi : plus d'entree apres cette heure NY (0 = off)
input int    InpMaxADRUsedPct         = 0;     // NY : pas d'entree si le jour a deja fait ce % de l'ADR(5) (0 = off)
input int    InpFlattenAtNYMinute     = 0;     // Tout fermer a cette minute NY (ex: 720 = 12:00 ; 0 = off)

input group "=== SILVER BULLET (M5) ==="
input ENUM_TIMEFRAMES InpLTF            = PERIOD_M5;   // Timeframe d'entree
input ENUM_TIMEFRAMES InpHTF            = PERIOD_H1;   // Timeframe du biais
input int    InpSwingStrength           = 2;     // Force des swings fractals
input double InpSweepMinATR             = 0.04;  // Penetration minimale du sweep (ATR M5)
input int    InpSweepConfirmBars        = 3;     // Bougies max entre l'extreme et la cloture de retour
input int    InpSweepMaxEpisodeBars     = 6;     // Bougies max au-dela du niveau (sinon cassure)
input int    InpSweepLookbackBars       = 48;    // Bougies M5 de recherche du sweep
input int    InpPreSweepMinutes         = 45;    // Le sweep peut preceder la fenetre de N minutes
input int    InpMSSMaxBarsAfterSweep    = 15;    // Bougies max entre sweep et MSS
input double InpMSSMinRangeATR          = 0.3;   // Distance min entre extreme du sweep et niveau casse (ATR)
input double InpDisplacementBodyATR     = 0.8;   // Corps minimal de displacement (ATR M5)
input double InpFVGMinSizeATR           = 0.12;  // Taille minimale du FVG (ATR M5)
input double InpEqualHighsTolATR        = 0.10;  // Tolerance equal highs/lows (ATR M5)
input ENUM_ENTRY_MODE InpEntryMode      = ENTRY_FVG_TOP; // Mode d'entree
input int    InpOrderExpiryMinutes      = 45;    // Expiration de l'ordre limite apres la fin de fenetre
input bool   InpRequireDiscount         = true;  // Appliquer le seuil InpSBMinRetrace
input bool   InpRequireHTFAlignment     = false; // Exiger l'alignement avec le biais HTF
input bool   InpUseOTEBonus             = true;  // Bonus si le FVG recouvre l'OTE 62-79 %
input bool   InpUseMacroBonus           = true;  // Bonus si le MSS se forme dans une macro
input int    InpMinSetupScore           = 3;     // Score minimal Silver Bullet
input double InpSLBufferATR             = 0.10;  // Buffer du SL derriere l'extreme du sweep (ATR)
input double InpMaxStopATR              = 6.0;   // Distance de stop maximale (ATR M5)
input double InpTPBufferATR             = 0.05;  // TP place juste avant le pool (ATR)
input ENUM_TP_MODE InpTPMode            = TP_NEAREST_POOL; // Mode de cible
input double InpMinRR                   = 2.0;   // RR minimum planifie
input double InpMaxTPDistATRD1          = 1.5;   // Distance max du TP (ATR D1)
input bool   InpAllowFixedRRFallback    = true;  // Sans pool atteignable : TP a RR min
input int    InpIPDALookback1           = 20;    // IPDA lookback 1 (jours) = dealing range
input int    InpIPDALookback2           = 40;    // IPDA lookback 2 (jours)
input int    InpIPDALookback3           = 60;    // IPDA lookback 3 (jours)
input bool   InpUTBotConfirm            = false; // Confirmation UT Bot (ligne ATR)
input double InpUTBotKey                = 1.0;   // Sensibilite UT Bot

input group "=== MACRO BREAKER (M1, macros ICT) ==="
input ENUM_TIMEFRAMES InpMBTimeframe    = PERIOD_M1;   // Timeframe du breaker
input string InpMBMacros                = "0320,0350,0820,0920,0950,1020,1050,1120,1320,1420,1515,1550"; // Macros autorisees (HHMM NY)
input int    InpMBRetestGraceMinutes    = 25;    // Retest accepte jusqu'a N min apres la fin de macro
input int    InpMBOrderExpiryMinutes    = 35;    // Expiration de l'ordre apres la fin de macro
input int    InpMBSwingStrength         = 2;     // Force des swings M1
input int    InpMBLookbackBars          = 90;    // Bougies M1 de recherche du stop hunt
input int    InpMBSwingLookback         = 75;    // Bougies M1 de recherche du swing oppose
input int    InpMBMaxBarsToConfirm      = 30;    // Bougies max entre stop hunt et confirmation
input double InpMBSweepMinATR           = 0.05;  // Penetration minimale du stop hunt (ATR M1)
input int    InpMBPreMacroMinutes       = 25;    // Confirmation acceptee N min avant le debut de macro
input double InpMBMinRangeATR           = 0.4;   // Distance min extreme -> swing (ATR M1)
input double InpMBDisplacementBodyATR   = 0.8;   // Corps minimal de displacement (ATR M1)
input double InpMBFVGMinSizeATR         = 0.15;  // Taille minimale du FVG Unicorn (ATR M1)
input double InpMBMinBreakerATR         = 0.5;   // Breaker plus petit : SL derriere l'extreme du sweep
input ENUM_MB_ENTRY InpMBEntryLevel     = MB_ENTRY_BREAKER_EDGE; // Niveau d'entree dans le breaker
input bool   InpMBRequireUnicorn        = false; // Exiger un FVG dans le breaker
input bool   InpMBRequireHTFAlignment   = false; // Exiger l'alignement HTF
input int    InpMBMinScore              = 2;     // Score minimal Macro Breaker
input double InpMBSLBufferATR           = 0.2;   // Buffer du SL (ATR M1)
input double InpMBGenerousMacroMult     = 1.5;   // Multiplicateur du buffer pendant la macro 09:20
input double InpMBMaxStopATR            = 12.0;  // Distance de stop maximale (ATR M1)

input group "=== TIPS ICT (score et filtres) ==="
input bool   InpUseTrueOpenBonus        = true;  // Bonus : achat sous le true open, vente au-dessus
input bool   InpRequireTrueOpenAlignment = false; // ... en filtre dur
input bool   InpUseRefLevelBonus        = true;  // Bonus : FVG / breaker sur quadrant daily, OPR, NDOG/NWOG
input double InpRefLevelTolATR          = 0.15;  // Tolerance (ATR M5)
input bool   InpUseDayOfWeekScore       = true;  // Profil hebdo : mar/mer/jeu +1, ven -1
input bool   InpUseBPRBonus             = true;  // Bonus : Balanced Price Range
input bool   InpUseStdDevTargets        = true;  // Cibles : deviations standard 2 / 2.5 / 4
input double InpEqWarnATR               = 1.5;   // Equal highs/lows a moins de N ATR au-dela du stop : -2
input bool   InpUseOPRLevels            = true;  // Opening ranges 01:30, 07:00, 09:30, 13:30 NY
input bool   InpUseTBRLevels            = true;  // Time based range 08:12-09:12 NY
input bool   InpUseNDOGLevels           = true;  // NDOG / NWOG

input group "=== FENETRES (heure de New York, jamais serveur) ==="
input bool InpUseLondonSB          = true;  // Silver Bullet Londres 03:00-04:00 NY
input bool InpUseNYAMSB            = true;  // Silver Bullet NY AM 10:00-11:00 NY
input bool InpUseNYPMSB            = true;  // Silver Bullet NY PM 14:00-15:00 NY
input int  InpServerUTCOffsetWinter = 2;    // Offset serveur vs UTC en hiver (testeur / mode manuel)
input bool InpServerFollowsEUDST   = true;  // Le serveur suit l'heure d'ete europeenne
input bool InpForceManualOffset    = false; // Ignorer la mesure automatique en live

input group "=== GESTION DES POSITIONS (RR eleves) ==="
input double InpBreakEvenAtR      = 1.0;   // Break-even a partir de ce R (0 = off)
input int    InpBEExtraPoints     = 15;    // Marge du break-even en points
input double InpCommissionPerLot  = 0.0;   // Commission aller-retour par lot (devise du compte)
input bool   InpEnablePartial     = true;  // Cloture partielle unique
input double InpPartialAtR        = 2.0;   // ... a ce R
input double InpPartialPercent    = 40.0;  // ... pourcentage du volume
input bool   InpEnableTrailing    = true;  // Trailing stop
input double InpTrailingStartR    = 2.0;   // ... a partir de ce R
input double InpTrailingATRMult   = 2.5;   // ... distance en ATR M5
input bool   InpTrailBySwing      = true;  // ... ou sous le dernier swing M5 si plus proche
input int    InpTrailMinStepPoints = 20;   // Pas minimal de deplacement du SL (points)
input int    InpTimeStopMinutes   = 75;    // Time stop : minutes apres la fin de fenetre / macro (0 = off)
input double InpTimeStopMinR      = 0.3;   // ... si le trade n'a pas atteint ce R
input int    InpMaxHoldMinutes    = 0;     // Duree maximale d'une position (0 = off)

input group "=== NEWS ==="
input bool   InpUseNewsFilter        = true;   // Blackout autour des publications
input int    InpNewsBlackoutBeforeMin = 15;    // Minutes avant
input int    InpNewsBlackoutAfterMin  = 15;    // Minutes apres
input string InpNewsCurrencies       = "USD";  // Devises (separees par des virgules)
input bool   InpNewsIncludeMedium    = false;  // Inclure l'impact moyen
input bool   InpNewsUseCalendar      = true;   // Calendrier MQL5 en live
input string InpNewsCSVFile          = "ICTPro\\news_high_impact.csv"; // CSV (testeur) : "yyyy.mm.dd hh:mi;USD;HIGH;Nom" en UTC

input group "=== APPRENTISSAGE ==="
input ENUM_ADAPT_MODE InpAdaptMode   = ADAPT_SIZE; // Mode adaptatif
input int    InpAdaptMinSamples      = 25;     // Trades minimum par bucket avant modulation
input double InpAdaptMinFactor       = 0.5;    // Facteur de taille minimal
input double InpAdaptMaxFactor       = 1.25;   // Facteur de taille maximal
input double InpAdaptPriorWeight     = 20.0;   // Poids du prior (retrecissement)
input string InpAdaptStatsFile       = "";     // Fichier de stats (vide = ICTPro\adaptive_stats_<symbole>.csv)
input bool   InpUseONNXModel         = false;  // Filtre par modele ONNX entraine hors ligne
input string InpONNXModelFile        = "ICTPro\\silver_bullet_xauusd.onnx"; // Fichier ONNX (dossier commun)
input double InpONNXMinProb          = 0.55;   // Probabilite minimale

input group "=== JOURNAL ET AFFICHAGE ==="
input bool   InpLogToCSV      = true;      // Journal CSV (dossier commun\ICTPro)
input bool   InpLogRejected   = true;      // Journaliser les setups rejetes
input string InpJournalFolder = "ICTPro";  // Sous-dossier du journal
input bool   InpDrawOnChart   = true;      // Dessiner sweep, FVG, breaker, SL, TP
input bool   InpShowDashboard = true;      // Tableau de bord sur le graphique

input group "=== GENERAL ==="
input long   InpMagicNumber   = 202612;
input int    InpSlippagePoints = 30;
input string InpTradeComment  = "ICTPro";

#ifdef ICT_USE_LICENSE
input group "=== LICENCE ==="
input string License_Key = "";                    // Cle de licence
input bool   Enable_License_Protection = true;    // Activer la protection
CSecurityManager *g_security = NULL;
#endif

//+------------------------------------------------------------------+
//| Objets globaux                                                   |
//+------------------------------------------------------------------+
CSessionClock      g_clock;
CNewsFilter        g_news;
CLiquidityMap      g_liq;
CReferenceLevels   g_ref;
CSetupSilverBullet g_setupSB;
CSetupMacroBreaker g_setupMB;
CExecutor          g_exec;
CRiskEngine        g_risk;
CJournal           g_journal;
CAdaptiveStats     g_stats;
CModelGate         g_model;
CPositionManager   g_pm;

//--- v6.20 : jeux de parametres strict / relache pour la 2e passe
SSetupParams g_spStrict, g_spRelax;
SMBParams    g_mpStrict, g_mpRelax;

int       g_atrLTFHandle = INVALID_HANDLE;
int       g_atrM1Handle  = INVALID_HANDLE;
int       g_atrD1Handle  = INVALID_HANDLE;
MqlRates  g_ltf[];
MqlRates  g_m1[];
MqlRates  g_htf[];
MqlRates  g_d1[];
double    g_atrLTF[];
double    g_atrM1[];
double    g_atrD1[];
int       g_ltfCount = 0;
int       g_m1Count  = 0;
int       g_htfCount = 0;
int       g_d1Count  = 0;
int       g_maxSpreadPts = 0;
datetime  g_lastPipelineBar = 0;
datetime  g_lastDashboard = 0;
long      g_flattenDayKey = 0;
string    g_consumed[];
string    g_lastNoSetupKey = "";
string    g_lastBlockKey = "";
string    g_lastStatus = "";

//--- Setups Silver Bullet armes (ENTRY_OB_AFTER_FVG)
SSetup    g_armed[];
datetime  g_armedExpiry[];
int       g_armedCount = 0;

#define LTF_BARS 400
#define M1_BARS  420
#define HTF_BARS 400
#define D1_BARS  80

//+------------------------------------------------------------------+
//| Validation des parametres                                        |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
   bool ok = true;
   if(InpRiskMode != RISK_FIXED_LOT && InpRiskMode != RISK_FIXED_MONEY && (InpRiskPercent <= 0 || InpRiskPercent > 5))
   { Print("InpRiskPercent doit etre entre 0 et 5"); ok = false; }
   if(InpRiskMode == RISK_FIXED_MONEY && InpRiskFixedMoney <= 0) { Print("InpRiskFixedMoney doit etre > 0"); ok = false; }
   if(InpRiskMode == RISK_FIXED_LOT && InpFixedLot <= 0) { Print("InpFixedLot doit etre > 0"); ok = false; }
   if(InpRiskMode == RISK_FIXED_LOT) Print("ATTENTION : mode lot fixe actif, la taille ne suivra pas le capital.");
   if(InpMinRR < 1.0) { Print("InpMinRR doit etre >= 1"); ok = false; }
   if(PeriodSeconds(InpLTF) >= PeriodSeconds(InpHTF)) { Print("InpLTF doit etre inferieur a InpHTF"); ok = false; }
   if(PeriodSeconds(InpMBTimeframe) > PeriodSeconds(InpLTF)) { Print("InpMBTimeframe doit etre <= InpLTF"); ok = false; }
   if(InpSwingStrength < 1 || InpSwingStrength > 5) { Print("InpSwingStrength entre 1 et 5"); ok = false; }
   if(InpPartialPercent <= 0 || InpPartialPercent >= 100) { Print("InpPartialPercent entre 0 et 100 exclus"); ok = false; }
   if(InpMaxConcurrentPositions < 1) { Print("InpMaxConcurrentPositions >= 1"); ok = false; }
   if(InpSBMinRetrace < 0 || InpSBMinRetrace > 1) { Print("InpSBMinRetrace entre 0 et 1"); ok = false; }
   if(InpAdaptMinFactor <= 0 || InpAdaptMaxFactor < InpAdaptMinFactor) { Print("Facteurs adaptatifs incoherents"); ok = false; }
   if(!InpEnableSilverBullet && !InpEnableMacroBreaker) { Print("Aucune strategie activee"); ok = false; }
   if(InpEnableSilverBullet && !InpUseLondonSB && !InpUseNYAMSB && !InpUseNYPMSB) { Print("Aucune fenetre Silver Bullet activee"); ok = false; }
   string sym = _Symbol;
   StringToUpper(sym);
   if(StringFind(sym, "XAU") < 0 && StringFind(sym, "GOLD") < 0)
      Print("Attention : l'EA est calibre pour l'or, symbole courant ", _Symbol);
   return ok;
}

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!ValidateInputs()) return INIT_PARAMETERS_INCORRECT;

#ifdef ICT_USE_LICENSE
   if(Enable_License_Protection && !IsTester())
   {
      g_security = new CSecurityManager(License_Key);
      if(!g_security.ValidateLicense())
      {
         Alert("Licence invalide - compte ", AccountInfoInteger(ACCOUNT_LOGIN));
         Alert(g_security.GetLicenseInfo());
         return INIT_FAILED;
      }
      Print("Licence validee : ", g_security.GetLicenseInfo());
   }
#endif

   g_atrLTFHandle = iATR(_Symbol, InpLTF, 14);
   g_atrM1Handle  = iATR(_Symbol, InpMBTimeframe, 14);
   g_atrD1Handle  = iATR(_Symbol, PERIOD_D1, 14);
   if(g_atrLTFHandle == INVALID_HANDLE || g_atrM1Handle == INVALID_HANDLE || g_atrD1Handle == INVALID_HANDLE)
   {
      Print("Creation des handles ATR impossible");
      return INIT_FAILED;
   }
   ArraySetAsSeries(g_ltf, true);
   ArraySetAsSeries(g_m1, true);
   ArraySetAsSeries(g_htf, true);
   ArraySetAsSeries(g_d1, true);
   ArraySetAsSeries(g_atrLTF, true);
   ArraySetAsSeries(g_atrM1, true);
   ArraySetAsSeries(g_atrD1, true);

   g_clock.Init(InpServerUTCOffsetWinter, InpServerFollowsEUDST, InpForceManualOffset,
                InpUseLondonSB, InpUseNYAMSB, InpUseNYPMSB, InpMBMacros);
   g_news.Init(InpUseNewsFilter, InpNewsBlackoutBeforeMin, InpNewsBlackoutAfterMin, InpNewsCurrencies, InpNewsIncludeMedium,
               InpNewsUseCalendar, InpNewsCSVFile, GetPointer(g_clock));
   g_news.Refresh(TimeCurrent());
   g_exec.Init(_Symbol, InpMagicNumber, InpSlippagePoints);
   g_journal.Init(InpLogToCSV && !IsOptimization(), InpLogRejected, InpJournalFolder, _Symbol);
   g_ref.Init(GetPointer(g_clock), InpUseOPRLevels, InpUseTBRLevels, InpUseNDOGLevels);

   string statsFile = (InpAdaptStatsFile == "") ? "ICTPro\\adaptive_stats_" + _Symbol + ".csv" : InpAdaptStatsFile;
   g_stats.Init(statsFile, InpAdaptMode, InpAdaptMinSamples, InpAdaptMinFactor, InpAdaptMaxFactor, InpAdaptPriorWeight);
   g_model.Init(InpUseONNXModel, InpONNXModelFile, InpONNXMinProb);

   //--- v6.20 : le plafond de spread est exprime pour un symbole a 2 decimales.
   //--- Sur un XAUUSD a 3 decimales, 60 points = 0.06 $ et bloquerait tous les trades.
   g_maxSpreadPts = InpMaxSpreadPoints;
   if(g_maxSpreadPts > 0)
   {
      int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      if(dg > 2) g_maxSpreadPts = (int)(g_maxSpreadPts * MathPow(10, dg - 2));
      Print("Plafond de spread ajuste a ", g_maxSpreadPts, " points (digits=", dg,
            ", spread courant ", (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), ")");
   }

   g_risk.Init(_Symbol, InpMagicNumber, GetPointer(g_clock), GetPointer(g_exec),
               InpRiskMode, InpRiskPercent, InpRiskFixedMoney, InpFixedLot, InpMaxLotCap,
               InpDailyLossLimitPct, InpWeeklyLossLimitPct, InpMaxOpenRiskPct, InpMaxDrawdownHaltPct,
               InpMaxConcurrentPositions, InpMaxConsecutiveLosses, InpMaxTradesPerDay, InpMaxTradesPerWindow,
               InpMaxSpreadATR, g_maxSpreadPts, InpMinAccountBalance, InpFridayLastEntryHourNY);

   //--- parametres Silver Bullet
   SSetupParams sp;
   sp.swingStrength = InpSwingStrength;
   sp.sweepMinATR = InpSweepMinATR;
   sp.sweepConfirmBars = InpSweepConfirmBars;
   sp.sweepMaxEpisodeBars = InpSweepMaxEpisodeBars;
   sp.sweepLookbackBars = InpSweepLookbackBars;
   sp.preSweepMinutes = InpPreSweepMinutes;
   sp.mssMaxBars = InpMSSMaxBarsAfterSweep;
   sp.mssMinRangeATR = InpMSSMinRangeATR;
   sp.dispBodyATR = InpDisplacementBodyATR;
   sp.fvgMinSizeATR = InpFVGMinSizeATR;
   sp.entryMode = InpEntryMode;
   sp.requireDiscount = InpRequireDiscount;
   sp.requireHTFAlign = InpRequireHTFAlignment;
   sp.useOTEBonus = InpUseOTEBonus;
   sp.useMacroBonus = InpUseMacroBonus;
   sp.minScore = InpMinSetupScore;
   sp.slBufferATR = InpSLBufferATR;
   sp.tpBufferATR = InpTPBufferATR;
   sp.tpMode = InpTPMode;
   sp.minRR = InpMinRR;
   sp.maxTPDistATRD1 = InpMaxTPDistATRD1;
   sp.maxStopATR = InpMaxStopATR;
   sp.allowFixedRRFallback = InpAllowFixedRRFallback;
   sp.utbotConfirm = InpUTBotConfirm;
   sp.utbotKey = InpUTBotKey;
   sp.useTrueOpenBonus = InpUseTrueOpenBonus;
   sp.requireTrueOpen = InpRequireTrueOpenAlignment;
   sp.useRefLevelBonus = InpUseRefLevelBonus;
   sp.refLevelTolATR = InpRefLevelTolATR;
   sp.useDOWScore = InpUseDayOfWeekScore;
   sp.useBPRBonus = InpUseBPRBonus;
   sp.useSDTargets = InpUseStdDevTargets;
   sp.eqWarnATR = InpEqWarnATR;
   sp.fvgRequireBody = InpFVGRequireBody;
   sp.takeFirstFVG = InpSBTakeFirstFVG;
   sp.minRetrace = InpSBMinRetrace;

   g_spStrict = sp;
   g_spRelax  = sp;
   g_spRelax.requireHTFAlign = false;
   g_spRelax.requireDiscount = false;
   g_spRelax.requireTrueOpen = false;
   g_spRelax.fvgRequireBody  = false;
   g_spRelax.minScore        = (int)MathMax(0, InpMinSetupScore - 3);
   g_spRelax.minRR           = MathMax(1.5, InpMinRR - 0.5);
   g_spRelax.dispBodyATR     = InpDisplacementBodyATR * 0.6;
   g_spRelax.fvgMinSizeATR   = InpFVGMinSizeATR * 0.6;
   g_spRelax.sweepMinATR     = InpSweepMinATR * 0.6;
   g_spRelax.minRetrace      = 0.0;
   g_setupSB.Init(_Symbol, GetPointer(g_clock), GetPointer(g_liq), GetPointer(g_ref), g_spStrict);

   //--- parametres Macro Breaker
   SMBParams mp;
   mp.swingStrength = InpMBSwingStrength;
   mp.lookbackBars = InpMBLookbackBars;
   mp.swingLookback = InpMBSwingLookback;
   mp.maxBarsToConfirm = InpMBMaxBarsToConfirm;
   mp.sweepMinATR = InpMBSweepMinATR;
   mp.sweepConfirmBars = 3;
   mp.sweepMaxEpisodeBars = 8;
   mp.preMacroMinutes = InpMBPreMacroMinutes;
   mp.minRangeATR = InpMBMinRangeATR;
   mp.dispBodyATR = InpMBDisplacementBodyATR;
   mp.fvgMinSizeATR = InpMBFVGMinSizeATR;
   mp.minBreakerATR = InpMBMinBreakerATR;
   mp.entryLevel = InpMBEntryLevel;
   mp.requireUnicorn = InpMBRequireUnicorn;
   mp.requireHTFAlign = InpMBRequireHTFAlignment;
   mp.requireTrueOpen = InpRequireTrueOpenAlignment;
   mp.minScore = InpMBMinScore;
   mp.slBufferATR = InpMBSLBufferATR;
   mp.generousMacroMult = InpMBGenerousMacroMult;
   mp.tpBufferATR = InpTPBufferATR;
   mp.minRR = InpMinRR;
   mp.maxTPDistATRD1 = InpMaxTPDistATRD1;
   mp.maxStopATR = InpMBMaxStopATR;
   mp.allowFixedRRFallback = InpAllowFixedRRFallback;
   mp.useSDTargets = InpUseStdDevTargets;
   mp.useRefLevelBonus = InpUseRefLevelBonus;
   mp.refLevelTolATR = InpRefLevelTolATR;
   mp.useDOWScore = InpUseDayOfWeekScore;
   mp.eqWarnATR = InpEqWarnATR;
   mp.fvgRequireBody = InpFVGRequireBody;
   mp.allowRetested = InpMBAllowRetested;

   g_mpStrict = mp;
   g_mpRelax  = mp;
   g_mpRelax.requireHTFAlign = false;
   g_mpRelax.requireTrueOpen = false;
   g_mpRelax.requireUnicorn  = false;
   g_mpRelax.fvgRequireBody  = false;
   g_mpRelax.allowRetested   = true;
   g_mpRelax.minScore        = (int)MathMax(0, InpMBMinScore - 2);
   g_mpRelax.minRR           = MathMax(1.5, InpMinRR - 0.5);
   g_mpRelax.dispBodyATR     = InpMBDisplacementBodyATR * 0.6;
   g_mpRelax.sweepMinATR     = InpMBSweepMinATR * 0.6;
   g_mpRelax.minRangeATR     = InpMBMinRangeATR * 0.6;
   g_setupMB.Init(_Symbol, GetPointer(g_clock), GetPointer(g_liq), GetPointer(g_ref), g_mpStrict);

   SPMParams pm;
   pm.breakEvenAtR = InpBreakEvenAtR;
   pm.beExtraPoints = InpBEExtraPoints;
   pm.commissionPerLot = InpCommissionPerLot;
   pm.enablePartial = InpEnablePartial;
   pm.partialAtR = InpPartialAtR;
   pm.partialPercent = InpPartialPercent;
   pm.enableTrailing = InpEnableTrailing;
   pm.trailingStartR = InpTrailingStartR;
   pm.trailingATRMult = InpTrailingATRMult;
   pm.trailBySwing = InpTrailBySwing;
   pm.trailMinStepPoints = InpTrailMinStepPoints;
   pm.timeStopMinutes = InpTimeStopMinutes;
   pm.timeStopMinR = InpTimeStopMinR;
   pm.swingStrength = InpSwingStrength;
   pm.maxHoldMinutes = InpMaxHoldMinutes;
   g_pm.Init(_Symbol, InpMagicNumber, GetPointer(g_exec), GetPointer(g_journal), GetPointer(g_stats), pm);

   ArrayResize(g_consumed, 0);
   ArrayResize(g_armed, 0);
   ArrayResize(g_armedExpiry, 0);
   g_armedCount = 0;
   EventSetTimer(60);

   Print("ICT Ultimate Pro v", ICTPRO_VERSION, " initialise sur ", _Symbol, " | ", g_clock.Describe(TimeCurrent()));
   Print("Strategies : SB=", InpEnableSilverBullet ? "on" : "off", " MB=", InpEnableMacroBreaker ? "on" : "off",
         " | 1ere FVG : ", InpSBTakeFirstFVG ? "oui" : "non",
         " | breaker reteste accepte : ", InpMBAllowRetested ? "oui" : "non",
         " | macros MB : ", InpMBMacros);
   Print("2e passe relachee : SB apres ", InpSBRelaxAfterMin, " min, MB apres ", InpMBRelaxAfterMin, " min");
   Print("Risque par trade : ", DoubleToString(g_risk.RiskMoneyPerTrade(), 2), " ", AccountInfoString(ACCOUNT_CURRENCY),
         " | expiration d'ordres supportee : ", g_exec.ExpirySupported() ? "oui" : "non (geree par l'EA)");
   Print(g_stats.Summary());
   g_journal.LogEvent("INIT", StringFormat("v%s mode risque %d pct %.2f SB=%d MB=%d", ICTPRO_VERSION, (int)InpRiskMode, InpRiskPercent,
                      InpEnableSilverBullet ? 1 : 0, InpEnableMacroBreaker ? 1 : 0));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialisation                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   g_stats.Save();
   g_model.Release();
   if(g_atrLTFHandle != INVALID_HANDLE) IndicatorRelease(g_atrLTFHandle);
   if(g_atrM1Handle != INVALID_HANDLE) IndicatorRelease(g_atrM1Handle);
   if(g_atrD1Handle != INVALID_HANDLE) IndicatorRelease(g_atrD1Handle);
   ObjectsDeleteAll(0, ICTPRO_OBJ_PREFIX);
   Comment("");
#ifdef ICT_USE_LICENSE
   if(g_security != NULL) { delete g_security; g_security = NULL; }
#endif
}

//+------------------------------------------------------------------+
//| Chargement des donnees                                           |
//+------------------------------------------------------------------+
bool LoadFast()
{
   g_ltfCount = CopyRates(_Symbol, InpLTF, 0, LTF_BARS, g_ltf);
   if(g_ltfCount < 60) return false;
   int na = CopyBuffer(g_atrLTFHandle, 0, 0, LTF_BARS, g_atrLTF);
   if(na < 20 || g_atrLTF[1] <= 0) return false;
   if(na < g_ltfCount) g_ltfCount = na;
   return true;
}
bool LoadFull()
{
   g_htfCount = CopyRates(_Symbol, InpHTF, 0, HTF_BARS, g_htf);
   g_d1Count  = CopyRates(_Symbol, PERIOD_D1, 0, D1_BARS, g_d1);
   int nd = CopyBuffer(g_atrD1Handle, 0, 0, 3, g_atrD1);
   g_m1Count = CopyRates(_Symbol, InpMBTimeframe, 0, M1_BARS, g_m1);
   int nm = CopyBuffer(g_atrM1Handle, 0, 0, M1_BARS, g_atrM1);
   if(nm < g_m1Count) g_m1Count = nm;
   if(g_m1Count < 0) g_m1Count = 0;
   return (g_htfCount > 50 && g_d1Count > 5 && nd >= 2);
}

//+------------------------------------------------------------------+
//| Setups deja traites (evite de rejouer le meme sweep)             |
//+------------------------------------------------------------------+
bool IsConsumed(const string id)
{
   for(int i = 0; i < ArraySize(g_consumed); i++) if(g_consumed[i] == id) return true;
   return false;
}
void MarkConsumed(const string id)
{
   int n = ArraySize(g_consumed);
   if(n >= 60)
   {
      for(int i = 0; i < n - 1; i++) g_consumed[i] = g_consumed[i + 1];
      n--;
      ArrayResize(g_consumed, n);
   }
   ArrayResize(g_consumed, n + 1);
   g_consumed[n] = id;
}

//+------------------------------------------------------------------+
//| Dessin du setup                                                  |
//+------------------------------------------------------------------+
void DrawSetup(const SSetup &s)
{
   if(!InpDrawOnChart || IsOptimization()) return;
   string p = ICTPRO_OBJ_PREFIX + s.id + "_";
   datetime t0 = (s.setupType == SETUP_MACRO_BREAKER) ? s.breaker.time : s.fvg.time;
   datetime t1 = (datetime)((long)s.windowEnd + 3600);
   color c = (s.dir == DIR_BUY) ? clrMediumSeaGreen : clrIndianRed;
   if(s.setupType == SETUP_MACRO_BREAKER)
   {
      if(ObjectCreate(0, p + "BRK", OBJ_RECTANGLE, 0, s.breaker.time, s.breaker.top, t1, s.breaker.bottom))
      {
         ObjectSetInteger(0, p + "BRK", OBJPROP_COLOR, clrSlateBlue);
         ObjectSetInteger(0, p + "BRK", OBJPROP_FILL, false);
         ObjectSetInteger(0, p + "BRK", OBJPROP_BACK, true);
      }
   }
   if(s.fvg.found && ObjectCreate(0, p + "FVG", OBJ_RECTANGLE, 0, s.fvg.time, s.fvg.top, t1, s.fvg.bottom))
   {
      ObjectSetInteger(0, p + "FVG", OBJPROP_COLOR, c);
      ObjectSetInteger(0, p + "FVG", OBJPROP_FILL, true);
      ObjectSetInteger(0, p + "FVG", OBJPROP_BACK, true);
   }
   if(ObjectCreate(0, p + "SWEEP", OBJ_TREND, 0, s.sweep.extremeTime, s.sweep.level, t1, s.sweep.level))
   {
      ObjectSetInteger(0, p + "SWEEP", OBJPROP_COLOR, clrGoldenrod);
      ObjectSetInteger(0, p + "SWEEP", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetString(0, p + "SWEEP", OBJPROP_TEXT, "sweep " + LiqTypeToStr((int)s.sweep.type));
   }
   if(ObjectCreate(0, p + "SL", OBJ_TREND, 0, t0, s.sl, t1, s.sl))
      ObjectSetInteger(0, p + "SL", OBJPROP_COLOR, clrIndianRed);
   if(ObjectCreate(0, p + "TP", OBJ_TREND, 0, t0, s.tp, t1, s.tp))
      ObjectSetInteger(0, p + "TP", OBJPROP_COLOR, clrMediumSeaGreen);
   if(ObjectCreate(0, p + "ENTRY", OBJ_TREND, 0, t0, s.entry, t1, s.entry))
   {
      ObjectSetInteger(0, p + "ENTRY", OBJPROP_COLOR, clrDodgerBlue);
      ObjectSetString(0, p + "ENTRY", OBJPROP_TEXT, StringFormat("%s %s S%d RR %.1f%s", SetupTypeToStr(s.setupType), DirToStr(s.dir), s.score, s.rr, s.relaxed ? " RLX" : ""));
   }
}

//+------------------------------------------------------------------+
//| Tableau de bord                                                  |
//+------------------------------------------------------------------+
void UpdateDashboard(const bool force = false)
{
   if(!InpShowDashboard || IsOptimization()) return;
   datetime now = TimeCurrent();
   if(!force && (long)now - (long)g_lastDashboard < 2) return;
   g_lastDashboard = now;
   datetime ws, we;
   ENUM_SB_WINDOW w = g_clock.WindowAt(now, ws, we);
   int mi = g_clock.MacroIndexAt(now);
   string news;
   bool blackout = g_news.IsBlackout(now, news);
   string s = StringFormat("ICT Ultimate Pro v%s | %s | %s\n", ICTPRO_VERSION, _Symbol, g_clock.Describe(now));
   s += StringFormat("Fenetre SB : %s%s | macro : %s%s | news : %s\n", WindowToStr(w),
                     (w != WIN_NONE) ? StringFormat(" (fin %s)", TsToStr(we)) : "",
                     g_clock.MacroName(mi), (mi >= 0 && g_clock.MacroEnabled(mi)) ? " [MB actif]" : "",
                     blackout ? "BLACKOUT " + news : (g_news.Next(now) > 0 ? "prochaine " + TsToStr(g_news.Next(now)) : "aucune"));
   s += g_ref.Summary() + "\n";
   s += g_risk.Dashboard();
   s += g_pm.Dashboard();
   if(g_armedCount > 0) s += StringFormat("Setups armes (attente rejet FVG -> OB) : %d\n", g_armedCount);
   s += g_stats.Summary() + (g_model.Enabled() ? " | modele ONNX actif" : "") + "\n";
   s += "Statut : " + g_lastStatus + "\n";
   Comment(s);
}

//+------------------------------------------------------------------+
//| Portes communes puis execution d'un setup valide                 |
//+------------------------------------------------------------------+
bool ExecuteSetup(SSetup &best, const datetime now, const datetime countFrom, const double atr)
{
   float f[];
   BuildFeatureVector(best, g_clock.NYDayOfWeek(now), f);
   string bucket = CAdaptiveStats::BucketKey(best.setupType, best.window, best.macroId, best.score);
   string reason, why;

   if(!g_risk.CanOpen(now, countFrom, atr, best.dir, reason))
   {
      g_lastStatus = SetupTypeToStr(best.setupType) + " " + DirToStr(best.dir) + " S" + (string)best.score + " refuse : " + reason;
      g_journal.LogSetup(best, g_clock.NYTimeStr(now), "REJECTED_RISK", reason, 0, 0, 1.0, -1, bucket, 0, f);
      return false;
   }
   if(g_stats.Blocked(bucket, why))
   {
      g_lastStatus = why;
      g_journal.LogSetup(best, g_clock.NYTimeStr(now), "REJECTED_ADAPT", why, 0, 0, 1.0, -1, bucket, 0, f);
      MarkConsumed(best.id);
      return false;
   }
   double prob = g_model.Predict(f);
   if(!g_model.Pass(prob))
   {
      g_lastStatus = StringFormat("modele : p=%.2f < %.2f", prob, InpONNXMinProb);
      g_journal.LogSetup(best, g_clock.NYTimeStr(now), "REJECTED_MODEL", g_lastStatus, 0, 0, 1.0, prob, bucket, 0, f);
      MarkConsumed(best.id);
      return false;
   }
   double factor = g_stats.SizeFactor(bucket, why);

   double riskMoney;
   double lot = g_risk.CalcLot(best.dir, best.entry, best.sl, factor, riskMoney, reason);
   if(lot <= 0)
   {
      g_lastStatus = "taille refusee : " + reason;
      g_journal.LogSetup(best, g_clock.NYTimeStr(now), "REJECTED_SIZE", reason, 0, 0, factor, prob, bucket, 0, f);
      return false;
   }

   int expiryMin = (best.setupType == SETUP_MACRO_BREAKER) ? InpMBOrderExpiryMinutes : InpOrderExpiryMinutes;
   datetime expiry = (datetime)((long)best.windowEnd + (long)expiryMin * 60);
   string ctx = (best.setupType == SETUP_MACRO_BREAKER) ? StringFormat("M%04d", best.macroId) : WindowToStr(best.window);
   string comment = StringFormat("%s %s %s S%d", InpTradeComment, SetupTypeToStr(best.setupType), ctx, best.score);
   ulong ticket = 0;
   bool market = best.marketEntry;
   if(best.marketEntry)
      ticket = g_exec.Market(best.dir, lot, best.sl, best.tp, comment);
   else
      ticket = g_exec.PlaceLimit(best.dir, lot, best.entry, best.sl, best.tp, expiry, comment, true, market);
   if(ticket == 0)
   {
      g_lastStatus = "execution refusee : " + g_exec.LastError();
      g_journal.LogSetup(best, g_clock.NYTimeStr(now), "REJECTED_EXEC", g_exec.LastError(), lot, riskMoney, factor, prob, bucket, 0, f);
      return false;
   }
   g_pm.Register(ticket, !market, best, lot, riskMoney, expiry);
   MarkConsumed(best.id);
   g_journal.LogSetup(best, g_clock.NYTimeStr(now), "TAKEN", market ? "market" : "limit", lot, riskMoney, factor, prob, bucket, ticket, f);
   DrawSetup(best);
   g_risk.Refresh(now, true);
   g_lastStatus = StringFormat("%s %s %s S%d%s lot %.2f risque %.2f RR %.1f (%s) facteur %.2f", SetupTypeToStr(best.setupType),
                               market ? "MARCHE" : "LIMITE", DirToStr(best.dir), best.score, best.relaxed ? " RLX" : "", lot, riskMoney, best.rr,
                               LiqTypeToStr(best.tpSource), factor);
   Print("[Setup] ", g_lastStatus, " | sweep ", LiqTypeToStr((int)best.sweep.type), " @", DoubleToString(best.sweep.level, _Digits),
         (best.setupType == SETUP_MACRO_BREAKER ? " breaker " + DoubleToString(best.breaker.zoneBottom, _Digits) + "-" + DoubleToString(best.breaker.zoneTop, _Digits) + (best.unicorn ? " UNICORN" : "")
                                                : " FVG " + DoubleToString(best.fvg.bottom, _Digits) + "-" + DoubleToString(best.fvg.top, _Digits)),
         " entree ", DoubleToString(best.entry, _Digits), " SL ", DoubleToString(best.sl, _Digits), " TP ", DoubleToString(best.tp, _Digits));
   return true;
}

//+------------------------------------------------------------------+
//| Setups armes : attendre le rejet du FVG, puis entrer sur l'OB    |
//+------------------------------------------------------------------+
void ArmSetup(const SSetup &s, const datetime expiry)
{
   ArrayResize(g_armed, g_armedCount + 1);
   ArrayResize(g_armedExpiry, g_armedCount + 1);
   g_armed[g_armedCount] = s;
   g_armedExpiry[g_armedCount] = expiry;
   g_armedCount++;
   MarkConsumed(s.id);
   g_lastStatus = "setup arme " + s.id + " : attente rejet FVG puis OB";
   g_journal.LogEvent("ARMED", s.id);
}
void RemoveArmed(const int i)
{
   for(int k = i; k < g_armedCount - 1; k++) { g_armed[k] = g_armed[k + 1]; g_armedExpiry[k] = g_armedExpiry[k + 1]; }
   g_armedCount--;
   ArrayResize(g_armed, g_armedCount);
   ArrayResize(g_armedExpiry, g_armedCount);
}
void ProcessArmed(const datetime now, const double atr)
{
   for(int i = g_armedCount - 1; i >= 0; i--)
   {
      SSetup s = g_armed[i];
      if(now >= g_armedExpiry[i]) { g_journal.LogEvent("ARMED_EXPIRED", s.id); RemoveArmed(i); continue; }
      int touchIdx = -1, rejectIdx = -1;
      bool invalid = false, tpTaken = false;
      for(int k = g_ltfCount - 1; k >= 1; k--)
      {
         if(g_ltf[k].time <= s.mss.barTime) continue;
         if(s.dir == DIR_BUY)
         {
            if(g_ltf[k].close < s.fvg.bottom) { invalid = true; break; }
            if(g_ltf[k].high >= s.tp) { tpTaken = true; break; }
            if(touchIdx < 0 && g_ltf[k].low <= s.fvg.top) touchIdx = k;
            else if(touchIdx >= 0 && g_ltf[k].close > s.fvg.top && g_ltf[k].close > g_ltf[k].open) { rejectIdx = k; break; }
         }
         else
         {
            if(g_ltf[k].close > s.fvg.top) { invalid = true; break; }
            if(g_ltf[k].low <= s.tp) { tpTaken = true; break; }
            if(touchIdx < 0 && g_ltf[k].high >= s.fvg.bottom) touchIdx = k;
            else if(touchIdx >= 0 && g_ltf[k].close < s.fvg.bottom && g_ltf[k].close < g_ltf[k].open) { rejectIdx = k; break; }
         }
      }
      if(invalid) { g_journal.LogEvent("ARMED_INVALIDATED", s.id); RemoveArmed(i); continue; }
      if(tpTaken) { g_journal.LogEvent("ARMED_TARGET_TAKEN", s.id); RemoveArmed(i); continue; }
      if(rejectIdx < 0) continue;

      //--- order block : derniere bougie opposee entre le contact et le rejet
      int ob = touchIdx;
      for(int k = touchIdx; k > rejectIdx; k--)
      {
         if(s.dir == DIR_BUY  && g_ltf[k].close < g_ltf[k].open) ob = k;
         if(s.dir == DIR_SELL && g_ltf[k].close > g_ltf[k].open) ob = k;
      }
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double buffer = InpSLBufferATR * atr + (ask - bid);
      double entry = (s.dir == DIR_BUY) ? g_ltf[ob].high : g_ltf[ob].low;
      double sl = (s.dir == DIR_BUY) ? g_ltf[ob].low - buffer : g_ltf[ob].high + buffer;
      if(MathAbs(entry - sl) < 0.5 * atr)
         sl = (s.dir == DIR_BUY) ? s.sweep.extreme - buffer : s.sweep.extreme + buffer;
      s.marketEntry = false;
      if(s.dir == DIR_BUY && ask <= entry)  { entry = ask; s.marketEntry = true; }
      if(s.dir == DIR_SELL && bid >= entry) { entry = bid; s.marketEntry = true; }
      s.entry = NormPrice(_Symbol, entry);
      s.sl = NormPrice(_Symbol, sl);
      s.riskDist = MathAbs(s.entry - s.sl);
      if(s.riskDist < g_exec.MinStopDistance()) { g_journal.LogEvent("ARMED_STOP_TOO_TIGHT", s.id); RemoveArmed(i); continue; }
      s.rr = MathAbs(s.tp - s.entry) / s.riskDist;
      if(s.rr < InpMinRR) { g_journal.LogEvent("ARMED_RR_TOO_LOW", StringFormat("%s RR %.2f", s.id, s.rr)); RemoveArmed(i); continue; }
      s.needsOBConfirm = false;
      s.id += "_OB";
      datetime countFrom = s.windowStart;
      ExecuteSetup(s, now, countFrom, atr);
      RemoveArmed(i);
   }
}

//+------------------------------------------------------------------+
//| Pipeline de decision (une fois par nouvelle bougie M1)           |
//+------------------------------------------------------------------+
void RunPipeline()
{
   datetime now = TimeCurrent();
   g_risk.Refresh(now);

   //--- fermeture programmee (ex: midi NY)
   if(InpFlattenAtNYMinute > 0)
   {
      long dk = g_clock.NYDayKey(now);
      if(g_clock.NYMinuteOfDay(now) >= InpFlattenAtNYMinute && dk != g_flattenDayKey)
      {
         g_flattenDayKey = dk;
         if(g_pm.Count() > 0) { g_pm.FlattenAll("FLATTEN_NY_TIME"); g_lastStatus = "fermeture programmee"; }
         g_armedCount = 0; ArrayResize(g_armed, 0); ArrayResize(g_armedExpiry, 0);
      }
   }

   datetime ws = 0, we = 0;
   ENUM_SB_WINDOW window = InpEnableSilverBullet ? g_clock.WindowAt(now, ws, we) : WIN_NONE;
   int mi = -1;
   if(InpEnableMacroBreaker)
   {
      mi = g_clock.MacroIndexAt(now);
      if(mi < 0 || !g_clock.MacroEnabled(mi))
      {
         int rec = g_clock.MacroIndexRecent(now, InpMBRetestGraceMinutes);
         mi = (rec >= 0 && g_clock.MacroEnabled(rec)) ? rec : -1;
      }
   }
   bool armedPending = (g_armedCount > 0);
   if(window == WIN_NONE && mi < 0 && !armedPending)
   {
      g_lastStatus = "hors fenetre Silver Bullet et hors macro";
      g_lastNoSetupKey = "";
      return;
   }
   string newsName;
   if(g_news.IsBlackout(now, newsName))
   {
      g_lastStatus = "blackout news : " + newsName;
      string key = "NEWS|" + newsName;
      if(key != g_lastBlockKey) { g_journal.LogEvent("BLACKOUT", newsName); g_lastBlockKey = key; }
      return;
   }
   if(!LoadFull())
   {
      g_lastStatus = "donnees HTF/D1 insuffisantes";
      return;
   }

   double atr = g_atrLTF[1];
   double atrD1 = g_atrD1[1];
   double atrM1 = (g_m1Count > 20) ? g_atrM1[1] : 0;
   double sh, sl;
   ENUM_ICT_DIR bias = CMarketStructure::Bias(g_htf, g_htfCount, InpSwingStrength, sh, sl);
   g_liq.Build(_Symbol, g_clock, now, g_ltf, g_ltfCount, g_htf, g_htfCount, g_d1, g_d1Count, atr,
               InpIPDALookback1, InpIPDALookback2, InpIPDALookback3, InpSwingStrength, InpEqualHighsTolATR);
   g_ref.Build(now, g_ltf, g_ltfCount, g_m1, g_m1Count, g_htf, g_htfCount, g_d1, g_d1Count);
   g_ref.PushToMap(g_liq, now);
   if(g_m1Count > 60) g_liq.AddSwings(g_m1, g_m1Count, 3, 12, LIQ_M1_SWING_HIGH, LIQ_M1_SWING_LOW);

   //--- setups armes d'abord
   if(armedPending) ProcessArmed(now, atr);

   //--- filtre ADR
   if(InpMaxADRUsedPct > 0 && g_clock.NYMinuteOfDay(now) >= 420 && g_ref.ADRUsedPct() >= InpMaxADRUsedPct)
   {
      g_lastStatus = StringFormat("ADR deja utilise a %.0f%% : pas de nouvelle entree NY", g_ref.ADRUsedPct());
      return;
   }

   //--- candidats
   SSetup sb, mb;
   ResetSetup(sb); ResetSetup(mb);
   string rejSB = "", rejMB = "";
   bool haveSB = false, haveMB = false;

   //--- SILVER BULLET : passe stricte, puis passe relachee si rien n'est passe
   if(window != WIN_NONE)
   {
      haveSB = g_setupSB.Evaluate(g_ltf, g_ltfCount, g_atrLTF, bias, window, ws, we, now, atr, atrD1, g_exec.MinStopDistance(), sb, rejSB);
      if(!haveSB && InpSBRelaxAfterMin > 0 && now >= (datetime)((long)ws + (long)InpSBRelaxAfterMin * 60))
      {
         g_setupSB.SetParams(g_spRelax);
         haveSB = g_setupSB.Evaluate(g_ltf, g_ltfCount, g_atrLTF, bias, window, ws, we, now, atr, atrD1, g_exec.MinStopDistance(), sb, rejSB);
         g_setupSB.SetParams(g_spStrict);
         if(haveSB) { sb.relaxed = true; sb.id += "_RLX"; }
      }
   }

   //--- MACRO BREAKER : idem
   datetime ms = 0, me = 0;
   if(mi >= 0 && atrM1 > 0)
   {
      g_clock.MacroRangeServer(now, mi, ms, me);
      haveMB = g_setupMB.Evaluate(g_m1, g_m1Count, bias, g_clock.MacroId(mi), g_clock.MacroHighProb(mi), ms, me, now,
                                  atrM1, atr, atrD1, g_exec.MinStopDistance(), mb, rejMB);
      if(!haveMB && InpMBRelaxAfterMin > 0 && now >= (datetime)((long)ms + (long)InpMBRelaxAfterMin * 60))
      {
         g_setupMB.SetParams(g_mpRelax);
         haveMB = g_setupMB.Evaluate(g_m1, g_m1Count, bias, g_clock.MacroId(mi), g_clock.MacroHighProb(mi), ms, me, now,
                                     atrM1, atr, atrD1, g_exec.MinStopDistance(), mb, rejMB);
         g_setupMB.SetParams(g_mpStrict);
         if(haveMB) { mb.relaxed = true; mb.id += "_RLX"; }
      }
   }

   if(haveSB && IsConsumed(sb.id)) haveSB = false;
   if(haveMB && IsConsumed(mb.id)) haveMB = false;

   if(!haveSB && !haveMB)
   {
      string ctx = (window != WIN_NONE ? WindowToStr(window) : "") + (mi >= 0 ? " " + g_clock.MacroName(mi) : "");
      g_lastStatus = StringFormat("%s | biais %s | SB: %s | MB: %s", ctx, DirToStr(bias), rejSB == "" ? "-" : rejSB, rejMB == "" ? "-" : rejMB);
      string key = ctx + "|" + rejSB + "|" + rejMB;
      if(key != g_lastNoSetupKey && InpLogRejected)
      {
         g_journal.LogEvent("NO_SETUP", StringFormat("%s biais %s SB[%s] MB[%s]", ctx, DirToStr(bias), rejSB, rejMB));
         g_lastNoSetupKey = key;
      }
      return;
   }

   //--- arbitrage : setup strict prioritaire, puis meilleur score, puis MB Unicorn
   SSetup best;
   ResetSetup(best);
   if(haveSB && haveMB)
   {
      if(sb.relaxed != mb.relaxed)      best = sb.relaxed ? mb : sb;   // le non relache gagne
      else if(mb.score > sb.score)      best = mb;
      else if(mb.score == sb.score && mb.unicorn) best = mb;
      else                              best = sb;
   }
   else best = haveSB ? sb : mb;

   if(best.needsOBConfirm)
   {
      ArmSetup(best, (datetime)((long)best.windowEnd + (long)InpOrderExpiryMinutes * 60));
      return;
   }
   datetime countFrom = (best.setupType == SETUP_MACRO_BREAKER) ? ms : ws;
   ExecuteSetup(best, now, countFrom, atr);
}

//+------------------------------------------------------------------+
//| Tick                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!LoadFast()) return;

   //--- gestion des positions a chaque tick
   g_pm.OnTick(g_ltf, g_ltfCount, g_atrLTF[1]);

   //--- pipeline sur nouvelle bougie du timeframe le plus fin utilise
   datetime barTime = iTime(_Symbol, InpEnableMacroBreaker ? InpMBTimeframe : InpLTF, 0);
   if(barTime != g_lastPipelineBar)
   {
      g_lastPipelineBar = barTime;
      RunPipeline();
      UpdateDashboard(true);
   }
   else
      UpdateDashboard(false);
}

//+------------------------------------------------------------------+
//| Timer (1 min) : news, licence, rafraichissement du risque        |
//+------------------------------------------------------------------+
void OnTimer()
{
   g_news.Refresh(TimeCurrent());
   g_risk.Refresh(TimeCurrent(), true);
#ifdef ICT_USE_LICENSE
   static datetime lastCheck = 0;
   if(Enable_License_Protection && !IsTester() && g_security != NULL && (long)TimeCurrent() - (long)lastCheck > 3600)
   {
      lastCheck = TimeCurrent();
      if(!g_security.ValidateLicense())
      {
         Alert("Licence devenue invalide - arret du trading");
         g_exec.CloseAll();
         ExpertRemove();
      }
   }
#endif
}

//+------------------------------------------------------------------+
//| Transactions : synchronisation de l'etat                         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   long posId = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   datetime t = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   if(entry == DEAL_ENTRY_IN)
   {
      ulong order = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
      g_pm.OnOrderFilled(order, posId, HistoryDealGetDouble(trans.deal, DEAL_PRICE), t);
   }
   else
   {
      bool stillOpen = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong pt = PositionGetTicket(i);
         if(pt != 0 && PositionGetInteger(POSITION_IDENTIFIER) == posId) { stillOpen = true; break; }
      }
      if(!stillOpen) g_pm.OnPositionClosed(posId, "");
   }
   g_risk.Refresh(TimeCurrent(), true);
   UpdateDashboard(true);
}
//+-----------------------------------------------------------------

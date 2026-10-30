//+------------------------------------------------------------------+
//|                                       ICT_NAS_Institutional.mq5  |
//|                                                                  |
//|  EXPERT ADVISOR ICT COMPLET — NAS100 / US100                     |
//|                                                                  |
//|  Signal (ICT uniquement) :                                       |
//|    Liquidity Sweep -> MSS ou CISD -> Displacement -> FVG ->       |
//|    retour au CE -> Draw on Liquidity                             |
//|  Modèles : Shadow, Silver Bullet (03-04 / 10-11 / 14-15 + TGIF), |
//|    CRT (45 min + True Opens, OPR sweep/réintégration, macros     |
//|    08:30, 02:50, PM 14:50), Killzone, SB Momentum,               |
//|    London OPR (MOR, PDF), OPR 01:30 / 07:00 / 09:30 / 13:30,     |
//|    ERL->IRL                                                      |
//|  Contexte : heure NY (DST), MOR/OPR/STDV, carte de liquidité,    |
//|    NDOG/NWOG/RTH gap, Quarterly Theory, PD, SMT NQ/ES, FPFVG     |
//|  Décision : filtres -> RR -> score ICT -> ML ONNX -> risque      |
//|  Exécution : limite au CE, SL au-delà du sweep, TP1 50 % /       |
//|    TP2 25 % / TP3 25 %, BE+1, trailing structurel M1, flat       |
//|  Données : chaque setup (pris ou rejeté) + résultat simulé,      |
//|    chaque trade, contexte quotidien -> SQLite -> ict_quant       |
//|                                                                  |
//|  L'IA ne crée, ne modifie ni ne supprime jamais un signal ICT.   |
//|                                                                  |
//|  v2.21 :                                                         |
//|   - DOL des modèles "liquidité" = 1er pool intact à >= RR min    |
//|   - comparaisons RR / score tolérantes (virgule flottante)       |
//|   - SL toujours au-delà du sweep (alternative : bougie 1 du FVG) |
//|   - ordres : remplissage / expiration adaptés au broker          |
//|   - position au marché : délai de grâce avant abandon du suivi   |
//|                                                                  |
//|  v2.22 :                                                         |
//|   - contrôle d'autorisation de trading au démarrage (AutoTrading,|
//|     "Allow Algo Trading", compte, mode de trading du symbole)    |
//|   - ordre de test au démarrage dans le testeur (min lot)         |
//|   - lot réduit automatiquement si la marge libre est insuffisante|
//|   - DD total max : message explicite (0 = désactivé)             |
//|   - diagnostic écrit dans Common\Files\ICTNAS\diagnostic.txt     |
//|                                                                  |
//|  v2.30 : fusion avec le moteur « OPR + FVG » (cahier des charges |
//|  et PDF « London OPR Strategy » / « Macro + breaker »)           |
//|   - modèle LONDON_OPR_PDF fidèle au PDF : biais à 2:50 (clôture  |
//|     de la bougie 02:49), prise de liquidité dans la fenêtre,     |
//|     1er FVG M1 formé dans une macro après le sweep, entrée au    |
//|     bord du FVG, SL au-delà du swing, cible ±2 STD du MOR,       |
//|     1 macro = 1 trade, pas de trade si la cible est atteinte     |
//|     avant l'entrée, ordre annulé en fin de fenêtre               |
//|   - OPR figés à la clôture de leur plage et sauvegardés, 1er FVG |
//|     M15 asiatique et FPFVG M1 de minuit, journal CSV de chaque   |
//|     décision (Common\Files\ICTNAS)                               |
//|   - RR minimal par famille : ICT 2 (règle validée « RR min 2 »), |
//|     CRT 3 (inchangé), London PDF = cible du PDF ; le score ICT   |
//|     ne bloque pas le modèle PDF (il est enregistré)              |
//|   - trades max / jour : seuls les trades exécutés et les ordres  |
//|     en attente comptent (un ordre expiré ne consomme plus rien)  |
//|   - risque 1 % / trade, stop jour -2 %, objectif +3 % (règles    |
//|     validées de l'en-tête RiskManager), 2 positions simultanées  |
//|     maximum, toujours dans le même sens                          |
//|   - entrée au marché bornée (x R au-delà du niveau) et annulation|
//|     « cible atteinte avant l'entrée » contrôlée à chaque tick    |
//|                                                                  |
//|  v2.40 : union des EA ICT de l'auteur (ICT NAS, OPR + FVG,       |
//|  ICT Ultimate Pro v6.20, ICT_RiskGuard) - une seule chaîne de    |
//|  décision, de risque et de données                               |
//|   - modèles v6.20 : SB_V6 (Silver Bullet M5, 1er FVG de la jambe |
//|     après sweep confirmé + MSS) et MACRO_BREAKER (M1, macros ICT,|
//|     breaker confirmé par le corps, Unicorn), carte de liquidité  |
//|     et niveaux de référence v6.20, passe relâchée, arbitrage     |
//|     SB / MB, 1 trade par fenêtre / macro                         |
//|   - « un seul trade dans le testeur » : ordre de test désactivé  |
//|     par défaut, lot minimum accepté jusqu'à 1,5 x le risque      |
//|     (règle v6.20), trades du jour comptés depuis l'historique,   |
//|     exécution + clôture sur le même tick comptée et enregistrée, |
//|     prise de liquidité aussi détectée sur la bougie M1 clôturée  |
//|   - RiskGuard : risque ouvert cumulé max 3 %, lot max, délai     |
//|     entre deux ordres, spread max (ATR M5), SL au-delà du        |
//|     plafond ATR : rejet (ICT) ou ramené au plafond (RiskGuard)   |
//|   - diagnostic : entonnoir v6.20 et pistes quand l'EA ne trade   |
//|     pas (lot minimum, DD total, SL trop large)                   |
//|                                                                  |
//|  v2.50 : « pas vraiment rentable, fais qu'il prenne des trades » |
//|   - objectif journalier atteint : plus de nouvelle entrée, mais  |
//|     les positions ouvertes vont à leur SL / cible (DOL) au lieu  |
//|     d'être fermées (InpCloseOnDailyTarget) ; le stop journalier  |
//|     ferme toujours tout                                          |
//|   - testeur : DD total atteint = signalé (date, journal,         |
//|     diagnostic), le backtest continue (InpDDHaltInTester) ; en   |
//|     réel, arrêt définitif inchangé                               |
//|   - apprentissage de la v6.20 (règle ADAPT_SIZE_AND_GATE) par    |
//|     modèle x session, sur le résultat virtuel de chaque plan     |
//|     conforme (pris ou non) : signalé dans diagnostic.txt,        |
//|     bloqué seulement si InpAdaptGate = true                      |
//+------------------------------------------------------------------+
#property copyright "Victor — ICT NAS Institutional"
#property version   "2.50"
#property description "EA ICT complet NAS100 : modeles ICT, London OPR (PDF), Silver Bullet 1er FVG et Macro Breaker (v6.20), score, filtre ML ONNX, garde-fous RiskGuard, collecte de donnees."

#include <Trade\Trade.mqh>

//=== début Defines.mqh ===
//+------------------------------------------------------------------+
//|                                                     Defines.mqh  |
//|  ICT NAS Institutional — types et utilitaires communs            |
//|                                                                  |
//|  Convention : "points d'indice" = unités de prix (1.0 = 1 point  |
//|  NAS100). Ce n'est PAS le _Point MT5 (souvent 0.01 ou 0.1).      |
//+------------------------------------------------------------------+
#ifndef ICTNAS_DEFINES_MQH
#define ICTNAS_DEFINES_MQH

#define ICTNAS_PREFIX   "ICTNAS_"
#define ICTNAS_VERSION  "2.50"
#define SEC_MIN         60
#define SEC_HOUR        3600
#define SEC_DAY         86400

#define BIAS_BULL        1
#define BIAS_BEAR       -1
#define BIAS_NONE        0

//--- Fuseau horaire du serveur broker
enum ENUM_SERVER_TZ
  {
   TZ_NY_PLUS_7  = 0,   // Serveur = NY+7h (GMT+2/+3 suit le DST US) - standard
   TZ_FIXED_GMT  = 1,   // Serveur = GMT + offset fixe
   TZ_GMT_EU_DST = 2    // Serveur = GMT + offset hiver, +1h pendant le DST europeen
  };

//--- Tolérance des Equal Highs / Lows
enum ENUM_EQ_TOL_MODE
  {
   EQTOL_ATR_M15 = 0,   // Multiple de l'ATR(14) M15
   EQTOL_POINTS  = 1    // Points d'indice fixes
  };

//--- Fenêtres Silver Bullet
enum ENUM_SB_MODE
  {
   SB_THREE_WINDOWS = 0, // 03-04 / 10-11 / 14-15 NY
   SB_NY_AM_ONLY    = 1  // 10-11 NY uniquement
  };

//--- Profil d'entrée (seuils regroupés)
enum ENUM_ENTRY_PROFILE
  {
   PROFILE_STRICT     = 0,  // Strict : règles d'origine (score 60, RR 2, SL au sweep, pas de cible de secours)
   PROFILE_STANDARD   = 1,  // Standard : score 25, RR 2, SL borné ATR, cible de secours 3R, 50 % à 2R, momentum SB
   PROFILE_AGGRESSIVE = 2,  // Agressif : entrées au marché, score 0, RR 2, displacement non obligatoire
   PROFILE_CUSTOM     = 3   // Personnalisé : utilise les inputs du groupe "Profil personnalisé"
  };

//--- Biais hebdomadaire manuel
enum ENUM_WEEKLY_BIAS
  {
   WB_NONE =  0,   // Aucun
   WB_BULL =  1,   // Haussier
   WB_BEAR = -1    // Baissier
  };

//--- v2.30 : implémentation du modèle London OPR
enum ENUM_LONDON_MODE
  {
   LONDON_PDF    = 0,  // PDF London OPR (moteur OPR + FVG) - conseillé
   LONDON_LEGACY = 1,  // v2.22 : séquence ICT complète (sweep, MSS/CISD, displacement, FVG)
   LONDON_BOTH   = 2   // Les deux
  };

//--- v2.30 : gestion des trades du modèle London OPR (PDF)
enum ENUM_LONDON_MANAGE
  {
   LM_PDF    = 0,      // PDF : cible unique (±STD du MOR), ni BE ni partiel
   LM_ICTNAS = 1       // ICT NAS : BE à x R, 50 % au TP1, reste à la cible
  };

#define LO_MODEL "LONDON_OPR_PDF"   // nom du modèle London OPR du PDF (moteur OPR + FVG)

//--- v2.40 : SL au-delà du plafond ATR du profil
enum ENUM_SL_CAP_MODE
  {
   SLCAP_REJECT = 0,   // Rejet du setup (ICT : le SL reste au-delà du sweep)
   SLCAP_CLAMP  = 1    // SL ramené au plafond (RiskGuard)
  };

//--- Types de liquidité (le poids est défini dans LiquidityEngine)
enum ENUM_LIQ_TYPE
  {
   LIQ_ASIA = 0,      // Asia High / Low
   LIQ_PREV_DAY,      // PDH / PDL
   LIQ_LONDON,        // London High / Low
   LIQ_EQUAL,         // EQH / EQL
   LIQ_SWING_M15,     // Swing M15
   LIQ_PREV_WEEK,     // PWH / PWL
   LIQ_IPDA,          // IPDA 20/40/60 jours
   LIQ_RESET,         // Reset BSL / SSL (Shadow)
   LIQ_NY_AM,         // NY AM High / Low
   LIQ_LUNCH,         // Lunch High / Low
   LIQ_PREV_MONTH,    // PMH / PML
   LIQ_OPR            // High / Low des OPR (00:00, 09:30, 13:30) — modèle CRT
  };

//+------------------------------------------------------------------+
//| Fenêtre de prix (session, OPR, MOR...) + suivi après la fenêtre  |
//+------------------------------------------------------------------+
struct SRange
  {
   string            name;
   bool              valid;          // au moins une barre trouvée
   bool              complete;       // fenêtre terminée, niveaux figés
   datetime          startSrv;       // heure serveur
   datetime          endSrv;
   double            high;
   double            low;
   datetime          tHigh;
   datetime          tLow;
   //--- suivi après la fenêtre (extensions STDV, cassure, retour)
   double            postHigh;
   double            postLow;
   datetime          tUp2;           // 1re fois que +2 STDV est atteint
   datetime          tDn2;
   int               breakSide;      // +1 clôture M1 au-dessus, -1 en dessous, 0 aucune
   datetime          tBreak;
   bool              returnedInside; // clôture M1 revenue dans le range après la cassure
   datetime          tReturn;

   void              Reset(const string n)
     {
      name=n; valid=false; complete=false; startSrv=0; endSrv=0;
      high=0; low=0; tHigh=0; tLow=0; postHigh=0; postLow=0;
      tUp2=0; tDn2=0; breakSide=0; tBreak=0; returnedInside=false; tReturn=0;
     }
   double            Size(void)       { return(high-low); }
   double            Mid(void)        { return((high+low)/2.0); }
   double            Up(double k)     { return(high+k*(high-low)); }
   double            Dn(double k)     { return(low -k*(high-low)); }
   double            ExtUp(void)
     {
      double r=high-low;
      if(!complete || r<=0 || postHigh<=high) return(0.0);
      return((postHigh-high)/r);
     }
   double            ExtDn(void)
     {
      double r=high-low;
      if(!complete || r<=0 || postLow<=0 || postLow>=low) return(0.0);
      return((low-postLow)/r);
     }
  };

//+------------------------------------------------------------------+
//| Utilitaires                                                      |
//+------------------------------------------------------------------+
//--- "HH:MM" -> minutes depuis minuit (-1 si invalide)
int ParseHHMM(const string s)
  {
   string p[];
   if(StringSplit(s,':',p)!=2) return(-1);
   int h=(int)StringToInteger(p[0]);
   int m=(int)StringToInteger(p[1]);
   if(h<0 || h>23 || m<0 || m>59) return(-1);
   return(h*60+m);
  }

//--- "1,1.5,2" -> tableau de doubles > 0
int ParseLevels(const string s,double &out[])
  {
   string p[];
   int n=StringSplit(s,',',p);
   ArrayResize(out,0);
   for(int i=0;i<n;i++)
     {
      string t=p[i];
      StringTrimLeft(t);
      StringTrimRight(t);
      if(t=="") continue;
      double v=StringToDouble(t);
      if(v<=0) continue;
      int k=ArraySize(out);
      ArrayResize(out,k+1);
      out[k]=v;
     }
   return(ArraySize(out));
  }

//--- "a,b,c" -> tableau de chaînes nettoyées
int ParseList(const string s,string &out[])
  {
   string p[];
   int n=StringSplit(s,',',p);
   ArrayResize(out,n);
   for(int i=0;i<n;i++)
     {
      string t=p[i];
      StringTrimLeft(t);
      StringTrimRight(t);
      out[i]=t;
     }
   return(n);
  }

string PxStr(double p)
  {
   if(p==0.0) return("");
   return(DoubleToString(p,_Digits));
  }

//--- Plus haut / plus bas M1 entre deux heures serveur [from ; to[
bool M1Extremes(const string sym,datetime fromSrv,datetime toSrv,
                double &hi,double &lo,datetime &tHi,datetime &tLo)
  {
   if(toSrv<=fromSrv) return(false);
   MqlRates r[];
   int n=CopyRates(sym,PERIOD_M1,fromSrv,toSrv-1,r);
   if(n<=0) return(false);
   hi=r[0].high; lo=r[0].low; tHi=r[0].time; tLo=r[0].time;
   for(int i=1;i<n;i++)
     {
      if(r[i].high>hi) { hi=r[i].high; tHi=r[i].time; }
      if(r[i].low <lo) { lo=r[i].low;  tLo=r[i].time; }
     }
   return(true);
  }

//--- Première barre M1 dont l'ouverture est >= tSrv (dans une fenêtre de recherche)
bool FirstBarAtOrAfter(const string sym,datetime tSrv,int windowSec,MqlRates &out)
  {
   MqlRates r[];
   int n=CopyRates(sym,PERIOD_M1,tSrv,tSrv+windowSec,r);
   if(n<=0) return(false);
   out=r[0];
   return(true);
  }

//--- Dernière barre M1 dont l'ouverture est < tSrv (dans une fenêtre de recherche)
bool LastBarBefore(const string sym,datetime tSrv,int lookbackSec,MqlRates &out)
  {
   MqlRates r[];
   int n=CopyRates(sym,PERIOD_M1,tSrv-lookbackSec,tSrv-1,r);
   if(n<=0) return(false);
   out=r[n-1];
   return(true);
  }

//--- Première barre M1 (fermée) qui dépasse un niveau ; 0 si aucune
datetime FirstCross(const string sym,double level,bool above,datetime fromSrv,datetime toSrv)
  {
   if(toSrv<=fromSrv || level<=0) return(0);
   MqlRates r[];
   int n=CopyRates(sym,PERIOD_M1,fromSrv,toSrv,r);
   for(int i=0;i<n;i++)
     {
      if(above  && r[i].high>level) return(r[i].time);
      if(!above && r[i].low <level) return(r[i].time);
     }
   return(0);
  }

#endif
//+------------------------------------------------------------------+
//=== fin Defines.mqh ===
//=== début TimeManager.mqh ===
//+------------------------------------------------------------------+
//|                                                 TimeManager.mqh  |
//|  Conversion serveur <-> UTC <-> New York (DST US automatique),   |
//|  jour de trading ICT (démarre 18:00 NY), sessions, macros, SB.   |
//+------------------------------------------------------------------+
#ifndef ICTNAS_TIMEMANAGER_MQH
#define ICTNAS_TIMEMANAGER_MQH

class CTimeManager
  {
private:
   ENUM_SERVER_TZ    m_mode;
   int               m_gmtOff;      // heures (heure d'hiver pour le mode EU)

   static datetime   MakeDate(int y,int mo,int d)
     {
      MqlDateTime s;
      ZeroMemory(s);
      s.year=y; s.mon=mo; s.day=d;
      return(StructToTime(s));
     }
   static datetime   NthSunday(int y,int mo,int n)
     {
      datetime first=MakeDate(y,mo,1);
      MqlDateTime s;
      TimeToStruct(first,s);
      int add=(7-s.day_of_week)%7;
      return(first+(add+7*(n-1))*SEC_DAY);
     }
   static datetime   LastSunday(int y,int mo)
     {
      int ny=y,nm=mo+1;
      if(nm>12) { nm=1; ny++; }
      datetime last=MakeDate(ny,nm,1)-SEC_DAY;
      MqlDateTime s;
      TimeToStruct(last,s);
      return(last-s.day_of_week*SEC_DAY);
     }

public:
                     CTimeManager(void) : m_mode(TZ_NY_PLUS_7),m_gmtOff(2) {}
   void              Init(ENUM_SERVER_TZ mode,int gmtOff) { m_mode=mode; m_gmtOff=gmtOff; }

   //--- DST : US = 2e dimanche de mars 07:00 UTC -> 1er dimanche de novembre 06:00 UTC
   static bool       IsUS_DST(datetime utc)
     {
      MqlDateTime s;
      TimeToStruct(utc,s);
      datetime st=NthSunday(s.year,3,2)+7*SEC_HOUR;
      datetime en=NthSunday(s.year,11,1)+6*SEC_HOUR;
      return(utc>=st && utc<en);
     }
   //--- DST : UE = dernier dimanche de mars 01:00 UTC -> dernier dimanche d'octobre 01:00 UTC
   static bool       IsEU_DST(datetime utc)
     {
      MqlDateTime s;
      TimeToStruct(utc,s);
      datetime st=LastSunday(s.year,3)+SEC_HOUR;
      datetime en=LastSunday(s.year,10)+SEC_HOUR;
      return(utc>=st && utc<en);
     }
   static datetime   UTCToNY(datetime utc) { return(utc-(IsUS_DST(utc)?4:5)*SEC_HOUR); }
   static datetime   NYToUTC(datetime ny)  { return(ny+(IsUS_DST(ny+4*SEC_HOUR)?4:5)*SEC_HOUR); }

   datetime          ServerToUTC(datetime srv)
     {
      if(m_mode==TZ_NY_PLUS_7) return(NYToUTC(srv-7*SEC_HOUR));
      datetime u=srv-m_gmtOff*SEC_HOUR;
      if(m_mode==TZ_GMT_EU_DST && IsEU_DST(u-SEC_HOUR)) u-=SEC_HOUR;
      return(u);
     }
   datetime          UTCToServer(datetime utc)
     {
      if(m_mode==TZ_NY_PLUS_7) return(UTCToNY(utc)+7*SEC_HOUR);
      datetime s=utc+m_gmtOff*SEC_HOUR;
      if(m_mode==TZ_GMT_EU_DST && IsEU_DST(utc)) s+=SEC_HOUR;
      return(s);
     }
   datetime          ServerToNY(datetime srv)
     {
      if(m_mode==TZ_NY_PLUS_7) return(srv-7*SEC_HOUR);
      return(UTCToNY(ServerToUTC(srv)));
     }
   datetime          NYToServer(datetime ny)
     {
      if(m_mode==TZ_NY_PLUS_7) return(ny+7*SEC_HOUR);
      return(UTCToServer(NYToUTC(ny)));
     }
   datetime          NowNY(void) { return(ServerToNY(TimeCurrent())); }

   static string     OffStr(long sec)
     {
      double h=sec/3600.0;
      int dig=(MathAbs(h-MathRound(h))<0.01)?0:1;
      return((h>=0?"+":"")+DoubleToString(h,dig));
     }
   string            ModeName(void)
     {
      if(m_mode==TZ_NY_PLUS_7) return("NY+7");
      if(m_mode==TZ_FIXED_GMT) return("GMT"+OffStr(m_gmtOff*SEC_HOUR));
      return("GMT"+OffStr(m_gmtOff*SEC_HOUR)+" +DST UE");
     }
   //--- En live : compare l'offset réel du serveur à celui supposé
   string            CheckLiveOffset(bool &ok)
     {
      ok=true;
      if(MQLInfoInteger(MQL_TESTER))
         return("Testeur : fuseau serveur suppose ("+ModeName()+")");
      datetime srv=TimeTradeServer();
      long real=(long)(srv-TimeGMT());
      real=(long)MathRound(real/1800.0)*1800;
      long expct=(long)(srv-ServerToUTC(srv));
      if(real==expct) return("Fuseau serveur verifie : GMT"+OffStr(real)+" ("+ModeName()+")");
      ok=false;
      return("ATTENTION fuseau : reel GMT"+OffStr(real)+" / suppose GMT"+OffStr(expct)+" -> corriger InpServerTZ");
     }

   //--- Calendrier (sur des heures NY)
   static datetime   DayStart(datetime t)  { return((datetime)((long)t-((long)t%SEC_DAY))); }
   static int        MinuteOfDay(datetime t) { return((int)(((long)t%SEC_DAY)/60)); }
   static int        DayOfWeek(datetime t)
     {
      MqlDateTime s;
      TimeToStruct(t,s);
      return(s.day_of_week);
     }
   static int        Month(datetime t)
     {
      MqlDateTime s;
      TimeToStruct(t,s);
      return(s.mon);
     }
   //--- Minuit NY du jour de trading (le jour démarre à 18:00 NY la veille)
   static datetime   TradingDayAnchor(datetime ny)
     {
      datetime d=DayStart(ny);
      if(MinuteOfDay(ny)>=18*60) d+=SEC_DAY;
      int w=DayOfWeek(d);
      if(w==6) d+=2*SEC_DAY;
      else if(w==0) d+=SEC_DAY;
      return(d);
     }
   static datetime   PrevTradingDay(datetime anchor)
     {
      datetime d=anchor-SEC_DAY;
      while(DayOfWeek(d)==0 || DayOfWeek(d)==6) d-=SEC_DAY;
      return(d);
     }
   static bool       InWindow(datetime ny,int fromMin,int toMin)
     {
      int m=MinuteOfDay(ny);
      if(fromMin<=toMin) return(m>=fromMin && m<toMin);
      return(m>=fromMin || m<toMin);
     }
   //--- Macros ICT : xx:50-xx:10 et xx:20-xx:40
   static string     MacroLabel(datetime ny)
     {
      int mm=MinuteOfDay(ny)%60;
      if(mm>=50 || mm<10) return("xx:50-xx:10");
      if(mm>=20 && mm<40) return("xx:20-xx:40");
      return("");
     }
   static string     SessionLabel(datetime ny)
     {
      int m=MinuteOfDay(ny);
      if(m>=18*60)     return("Asie");
      if(m<2*60)       return("Pre-Londres");
      if(m<5*60)       return("Londres KZ");
      if(m<7*60)       return("London Lunch");
      if(m<10*60)      return("NY AM KZ");
      if(m<12*60)      return("NY AM");
      if(m<13*60+30)   return("NY Lunch");
      if(m<16*60)      return("NY PM");
      if(m<17*60)      return("Post-marche");
      return("Pause 17-18");
     }
   static string     SilverBulletLabel(datetime ny,ENUM_SB_MODE mode)
     {
      int m=MinuteOfDay(ny);
      if(m>=10*60 && m<11*60) return("SB NY AM 10-11");
      if(mode==SB_NY_AM_ONLY) return("");
      if(m>=3*60  && m<4*60)  return("SB Londres 03-04");
      if(m>=14*60 && m<15*60) return("SB NY PM 14-15");
      return("");
     }
  };

#endif
//+------------------------------------------------------------------+
//=== fin TimeManager.mqh ===
//=== début OPREngine.mqh ===
//+------------------------------------------------------------------+
//|                                                   OPREngine.mqh  |
//|  MOR (00:00-00:30), OPR 01:30 / 07:00 / 09:30 / 13:30,           |
//|  range Shadow / Reset (07:00 -> fin configurable), STDV,         |
//|  biais MOR à 02:50, cassure / retour, jour de tendance,         |
//|  statistiques Shadow (quelle liquidité prise en premier).        |
//|  Toutes les heures de fenêtre sont en New York.                  |
//+------------------------------------------------------------------+
#ifndef ICTNAS_OPRENGINE_MQH
#define ICTNAS_OPRENGINE_MQH

class COPREngine
  {
public:
   SRange            mor,opr0130,opr0700,opr0930,opr1330,shadow;
   int               morBias;         // BIAS_BULL / BIAS_BEAR / BIAS_NONE
   bool              morBiasSet;
   double            morBiasPrice;
   int               shadowFirstSide; // 1 = Reset BSL pris en 1er, -1 = SSL, 2 = même bougie
   datetime          shadowFirstTime;
   bool              shadowOppHit;
   datetime          shadowOppTime;
   //--- ouvertures clés du jour
   double            midnightOpen;    // 00:00 NY (True Day Open)
   double            open0830;        // 08:30 NY (news)
   double            open0930;        // ouverture RTH


private:
   string            m_sym;
   CTimeManager     *m_tm;
   double            m_lv[];
   double            m_key[];
   datetime          m_anchor;
   datetime          m_t0250Srv;
   datetime          m_dayEndSrv;
   int               m_shadowEndMin;

   void              SetWindow(SRange &r,const string name,int fromMin,int toMin)
     {
      r.Reset(name);
      r.startSrv=m_tm.NYToServer(m_anchor+fromMin*SEC_MIN);
      r.endSrv  =m_tm.NYToServer(m_anchor+toMin*SEC_MIN);
     }

   //--- Suivi d'une barre M1 clôturée après la fenêtre (idempotent)
   void              TrackBar(SRange &r,const MqlRates &b)
     {
      if(!r.complete || r.Size()<=0) return;
      if(b.time<r.endSrv || b.time>=m_dayEndSrv) return;
      if(b.high>r.postHigh) r.postHigh=b.high;
      if(b.low <r.postLow)  r.postLow=b.low;
      if(r.tUp2==0 && b.high>=r.Up(2.0)) r.tUp2=b.time;
      if(r.tDn2==0 && b.low <=r.Dn(2.0)) r.tDn2=b.time;
      if(r.breakSide==0)
        {
         if(b.close>r.high)     { r.breakSide= 1; r.tBreak=b.time; }
         else if(b.close<r.low) { r.breakSide=-1; r.tBreak=b.time; }
        }
      else if(!r.returnedInside && b.time>r.tBreak && b.close<=r.high && b.close>=r.low)
        {
         r.returnedInside=true;
         r.tReturn=b.time;
        }
     }

   //--- Shadow : quelle liquidité (Reset BSL / SSL) est prise en premier, puis l'opposée
   void              TrackShadow(const MqlRates &b)
     {
      if(!shadow.complete || b.time<shadow.endSrv || b.time>=m_dayEndSrv) return;
      bool upHit=(b.high>shadow.high);
      bool dnHit=(b.low <shadow.low);
      if(shadowFirstSide==0)
        {
         if(upHit && dnHit) { shadowFirstSide=2;  shadowFirstTime=b.time; } // même bougie M1 : ambigu
         else if(upHit)     { shadowFirstSide=1;  shadowFirstTime=b.time; }
         else if(dnHit)     { shadowFirstSide=-1; shadowFirstTime=b.time; }
         return;
        }
      if(!shadowOppHit && b.time>shadowFirstTime)
        {
         if(shadowFirstSide==1  && dnHit) { shadowOppHit=true; shadowOppTime=b.time; }
         if(shadowFirstSide==-1 && upHit) { shadowOppHit=true; shadowOppTime=b.time; }
        }
     }

   void              TrackAll(const MqlRates &b)
     {
      TrackBar(mor,b);
      TrackBar(opr0130,b);
      TrackBar(opr0700,b);
      TrackBar(opr0930,b);
      TrackBar(opr1330,b);
      TrackShadow(b);
     }

   //--- Met à jour un range ; à la clôture de la fenêtre, fige et rattrape les barres manquées
   void              UpdateRange(SRange &r,datetime now)
     {
      if(r.complete || now<r.startSrv) return;
      bool done=(now>=r.endSrv);
      datetime to=done ? r.endSrv : now+SEC_MIN;
      double hi,lo;
      datetime th,tl;
      if(!M1Extremes(m_sym,r.startSrv,to,hi,lo,th,tl)) return;
      r.valid=true;
      r.high=hi; r.low=lo; r.tHigh=th; r.tLow=tl;
      if(!done) return;
      r.complete=true;
      r.postHigh=hi;
      r.postLow=lo;
      //--- rattrapage (EA lancé en cours de journée)
      datetime cur=iTime(m_sym,PERIOD_M1,0);
      if(cur>r.endSrv)
        {
         MqlRates b[];
         int n=CopyRates(m_sym,PERIOD_M1,r.endSrv,cur-1,b);
         for(int i=0;i<n;i++) TrackAll(b[i]);
        }
     }

   double            OpenAtNY(int minuteOfDay)
     {
      MqlRates r;
      datetime t=m_tm.NYToServer(m_anchor+minuteOfDay*SEC_MIN);
      if(TimeCurrent()<t) return(0.0);
      if(FirstBarAtOrAfter(m_sym,t,10*SEC_MIN,r)) return(r.open);
      return(0.0);
     }

public:
   void              Init(const string sym,CTimeManager *tm,const string levels,const string keyLevels,int shadowEndMin)
     {
      m_sym=sym;
      m_tm=tm;
      ParseLevels(levels,m_lv);
      ParseLevels(keyLevels,m_key);
      m_shadowEndMin=(shadowEndMin>7*60)?shadowEndMin:9*60+30;
     }

   void              NewDay(datetime anchor)
     {
      m_anchor=anchor;
      SetWindow(mor,    "MOR",     0,       30);
      SetWindow(opr0130,"OPR 0130",90,      120);
      SetWindow(opr0700,"OPR 0700",7*60,    7*60+30);
      SetWindow(opr0930,"OPR 0930",9*60+30, 10*60);
      SetWindow(opr1330,"OPR 1330",13*60+30,14*60);
      SetWindow(shadow, "Shadow",  7*60,    m_shadowEndMin);
      m_t0250Srv =m_tm.NYToServer(anchor+2*SEC_HOUR+50*SEC_MIN);
      m_dayEndSrv=m_tm.NYToServer(anchor+17*SEC_HOUR);
      morBias=BIAS_NONE; morBiasSet=false; morBiasPrice=0;
      shadowFirstSide=0; shadowFirstTime=0; shadowOppHit=false; shadowOppTime=0;
      midnightOpen=0; open0830=0; open0930=0;
     }

   void              OnNewBar(datetime now)
     {
      UpdateRange(mor,now);
      UpdateRange(opr0130,now);
      UpdateRange(opr0700,now);
      UpdateRange(opr0930,now);
      UpdateRange(opr1330,now);
      UpdateRange(shadow,now);
      //--- dernière barre clôturée
      MqlRates b[];
      if(CopyRates(m_sym,PERIOD_M1,1,1,b)==1) TrackAll(b[0]);
      //--- biais MOR : prix de 02:50 comparé au range 00:00-00:30
      if(!morBiasSet && mor.complete && now>=m_t0250Srv)
        {
         MqlRates r;
         if(LastBarBefore(m_sym,m_t0250Srv,3*SEC_HOUR,r))
           {
            morBiasPrice=r.close;
            if(r.close>mor.high)     morBias=BIAS_BULL;
            else if(r.close<mor.low) morBias=BIAS_BEAR;
            else                     morBias=BIAS_NONE;
           }
         morBiasSet=true;
        }
      if(midnightOpen==0) midnightOpen=OpenAtNY(0);
      if(open0830==0)     open0830=OpenAtNY(8*60+30);
      if(open0930==0)     open0930=OpenAtNY(9*60+30);
     }

   //--- Jour de tendance (OPR 09:30) : cassure + 2 STDV atteints + aucun retour dans l'OPR
   bool              IsTrendDay(void)
     {
      if(!opr0930.complete || opr0930.breakSide==0 || opr0930.returnedInside) return(false);
      if(opr0930.breakSide>0) return(opr0930.tUp2>0);
      return(opr0930.tDn2>0);
     }

   int               LevelsCount(void)  { return(ArraySize(m_lv)); }
   double            Level(int i)       { return(m_lv[i]); }
   bool              IsKey(double k)
     {
      for(int i=0;i<ArraySize(m_key);i++)
         if(MathAbs(m_key[i]-k)<1e-9) return(true);
      return(false);
     }
   static string     BiasStr(int b) { return(b==BIAS_BULL?"BULL":(b==BIAS_BEAR?"BEAR":"NEUTRE")); }
  };

#endif
//+------------------------------------------------------------------+
//=== fin OPREngine.mqh ===
//=== début LiquidityEngine.mqh ===
//+------------------------------------------------------------------+
//|                                             LiquidityEngine.mqh  |
//|  Carte de liquidité : sessions (Asie, Londres, NY AM, Lunch),    |
//|  Reset BSL/SSL, PDH/PDL (3 derniers jours), PWH/PWL, PMH/PML,     |
//|  IPDA 20/40/60, swings M15, EQH/EQL. Suivi des sweeps.           |
//|  Poids (priorité validée) : HTF 8 > Asie 7 > PD 6 > Londres 5    |
//|  > EQ 4 > Swing M15 3.                                           |
//+------------------------------------------------------------------+
#ifndef ICTNAS_LIQUIDITYENGINE_MQH
#define ICTNAS_LIQUIDITYENGINE_MQH

struct SLiqLevel
  {
   int               id;
   string            name;
   int               type;       // ENUM_LIQ_TYPE
   bool              buySide;    // true = BSL (au-dessus), false = SSL (en dessous)
   double            price;
   datetime          tFormed;    // heure serveur
   bool              swept;
   datetime          tSwept;
   int               weight;
  };

class CLiquidityEngine
  {
public:
   SLiqLevel         lv[];
   SRange            asia,london,nyam,lunch,reset;
   double            pdh,pdl;          // jour précédent
   double            pwh,pwl;          // semaine précédente
   double            pmh,pml;          // mois précédent
   double            ipdaH[3],ipdaL[3];// 20 / 40 / 60 jours
   double            monthOpen;

   static int        Weight(int type)
     {
      switch(type)
        {
         case LIQ_PREV_WEEK:
         case LIQ_PREV_MONTH:
         case LIQ_IPDA:      return(8);
         case LIQ_ASIA:      return(7);
         case LIQ_PREV_DAY:  return(6);
         case LIQ_LONDON:
         case LIQ_NY_AM:
         case LIQ_RESET:
         case LIQ_OPR:       return(5);
         case LIQ_EQUAL:
         case LIQ_LUNCH:     return(4);
         case LIQ_SWING_M15: return(3);
        }
      return(1);
     }
   static string     TypeName(int type)
     {
      switch(type)
        {
         case LIQ_ASIA:       return("ASIA");
         case LIQ_PREV_DAY:   return("PREV_DAY");
         case LIQ_LONDON:     return("LONDON");
         case LIQ_EQUAL:      return("EQUAL");
         case LIQ_SWING_M15:  return("SWING_M15");
         case LIQ_PREV_WEEK:  return("PREV_WEEK");
         case LIQ_IPDA:       return("IPDA");
         case LIQ_RESET:      return("RESET");
         case LIQ_NY_AM:      return("NY_AM");
         case LIQ_LUNCH:      return("LUNCH");
         case LIQ_PREV_MONTH: return("PREV_MONTH");
         case LIQ_OPR:        return("OPR");
        }
      return("OTHER");
     }

private:
   string            m_sym;
   CTimeManager     *m_tm;
   datetime          m_anchor;
   datetime          m_dayStartSrv;
   datetime          m_dayEndSrv;
   int               m_strength;
   int               m_lookbackH;
   ENUM_EQ_TOL_MODE  m_eqMode;
   double            m_eqAtrMult;
   double            m_eqPts;
   int               m_atrH;
   int               m_nextId;
   int               m_resetEndMin;
   bool              m_addAsia,m_addLondon,m_addNYAM,m_addLunch,m_addReset;
   int               m_events[];      // index des niveaux pris depuis le dernier PopSweeps

   void              SetWindow(SRange &r,const string name,int fromMin,int toMin)
     {
      r.Reset(name);
      r.startSrv=m_tm.NYToServer(m_anchor+fromMin*SEC_MIN);
      r.endSrv  =m_tm.NYToServer(m_anchor+toMin*SEC_MIN);
     }

   double            Tick(void)
     {
      double t=SymbolInfoDouble(m_sym,SYMBOL_TRADE_TICK_SIZE);
      return(t>0?t:_Point);
     }

   int               FindNear(double price,bool buy)
     {
      double tol=Tick()*0.5;
      for(int i=0;i<ArraySize(lv);i++)
         if(lv[i].buySide==buy && MathAbs(lv[i].price-price)<=tol) return(i);
      return(-1);
     }

   //--- Ajoute un niveau ou fusionne avec un niveau existant au même prix (garde le plus lourd)
   int               AddOrMerge(const string name,int type,bool buy,double price,datetime tFormed,datetime checkFrom)
     {
      if(price<=0) return(-1);
      int w=Weight(type);
      int k=FindNear(price,buy);
      if(k>=0)
        {
         if(w>lv[k].weight) { lv[k].weight=w; lv[k].type=type; lv[k].name=name; }
         return(k);
        }
      int n=ArraySize(lv);
      ArrayResize(lv,n+1);
      lv[n].id=m_nextId++;
      lv[n].name=name;
      lv[n].type=type;
      lv[n].buySide=buy;
      lv[n].price=price;
      lv[n].tFormed=tFormed;
      lv[n].weight=w;
      lv[n].swept=false;
      lv[n].tSwept=0;
      //--- rattrapage : déjà pris depuis checkFrom ?
      datetime cur=iTime(m_sym,PERIOD_M1,0);
      if(checkFrom>0 && cur>checkFrom)
        {
         datetime t=FirstCross(m_sym,price,buy,checkFrom,cur-1);
         if(t>0) { lv[n].swept=true; lv[n].tSwept=t; }
        }
      return(n);
     }

   void              UpdateSession(SRange &r,const string nm,int type,bool &added,datetime now)
     {
      if(now<r.startSrv) return;
      if(!r.complete)
        {
         bool done=(now>=r.endSrv);
         datetime to=done ? r.endSrv : now+SEC_MIN;
         double hi,lo;
         datetime th,tl;
         if(M1Extremes(m_sym,r.startSrv,to,hi,lo,th,tl))
           {
            r.valid=true;
            r.high=hi; r.low=lo; r.tHigh=th; r.tLow=tl;
            if(done) r.complete=true;
           }
        }
      if(r.complete && !added)
        {
         AddOrMerge(nm+" H",type,true, r.high,r.tHigh,r.endSrv);
         AddOrMerge(nm+" L",type,false,r.low, r.tLow, r.endSrv);
         added=true;
        }
     }

   double            EqTolerance(void)
     {
      if(m_eqMode==EQTOL_POINTS) return(m_eqPts);
      double buf[];
      if(m_atrH!=INVALID_HANDLE && CopyBuffer(m_atrH,0,1,1,buf)==1 && buf[0]>0)
         return(buf[0]*m_eqAtrMult);
      return(m_eqPts);
     }

   void              TryAddSwing(bool buy,double price,datetime tBar,datetime after,datetime cur)
     {
      if(tBar<cur-m_lookbackH*SEC_HOUR) return;
      //--- déjà connu ?
      for(int i=0;i<ArraySize(lv);i++)
         if(lv[i].type==LIQ_SWING_M15 && lv[i].buySide==buy && lv[i].tFormed==tBar) return;
      //--- déjà pris avant d'être détecté : ce n'est plus un pool
      if(cur>after && FirstCross(m_sym,price,buy,after,cur-1)>0) return;
      //--- Equal Highs / Lows avec un swing intact existant
      double tol=EqTolerance();
      for(int i=0;i<ArraySize(lv);i++)
        {
         if(lv[i].swept || lv[i].buySide!=buy) continue;
         if(lv[i].type!=LIQ_SWING_M15 && lv[i].type!=LIQ_EQUAL) continue;
         if(MathAbs(lv[i].price-price)<=tol)
           {
            double eqPx=buy ? MathMax(lv[i].price,price) : MathMin(lv[i].price,price);
            AddOrMerge(buy?"EQH":"EQL",LIQ_EQUAL,buy,eqPx,lv[i].tFormed,after);
            break;
           }
        }
      AddOrMerge(buy?"SH M15":"SL M15",LIQ_SWING_M15,buy,price,tBar,after);
     }

   //--- Swings M15 entre deux décalages (shifts) de barres
   void              ScanSwings(int fromShift,int toShift)
     {
      int k=m_strength;
      if(fromShift<k+1) fromShift=k+1;
      if(toShift<fromShift) return;
      int need=toShift+k+1;
      MqlRates r[];
      ArraySetAsSeries(r,true);
      if(CopyRates(m_sym,PERIOD_M15,0,need,r)<need) return;
      datetime cur=iTime(m_sym,PERIOD_M1,0);
      int per=PeriodSeconds(PERIOD_M15);
      for(int i=toShift;i>=fromShift;i--)   // du plus ancien au plus récent
        {
         bool isH=true,isL=true;
         for(int j=1;j<=k;j++)
           {
            if(r[i-j].high>=r[i].high || r[i+j].high>=r[i].high) isH=false;
            if(r[i-j].low <=r[i].low  || r[i+j].low <=r[i].low)  isL=false;
           }
         datetime after=r[i].time+per;
         if(isH) TryAddSwing(true, r[i].high,r[i].time,after,cur);
         if(isL) TryAddSwing(false,r[i].low, r[i].time,after,cur);
        }
     }

public:
   void              Init(const string sym,CTimeManager *tm,int strength,int lookbackH,
                          ENUM_EQ_TOL_MODE eqMode,double eqAtrMult,double eqPts,int resetEndMin)
     {
      m_sym=sym;
      m_tm=tm;
      m_strength=MathMax(1,strength);
      m_lookbackH=MathMax(4,lookbackH);
      m_eqMode=eqMode;
      m_eqAtrMult=eqAtrMult;
      m_eqPts=eqPts;
      m_resetEndMin=(resetEndMin>7*60)?resetEndMin:9*60+30;
      m_atrH=iATR(sym,PERIOD_M15,14);
      m_nextId=0;
     }
   void              Deinit(void) { if(m_atrH!=INVALID_HANDLE) IndicatorRelease(m_atrH); }

   void              NewDay(datetime anchor)
     {
      m_anchor=anchor;
      m_dayStartSrv=m_tm.NYToServer(anchor-6*SEC_HOUR);
      m_dayEndSrv  =m_tm.NYToServer(anchor+17*SEC_HOUR);
      ArrayResize(lv,0);
      ArrayResize(m_events,0);
      m_addAsia=m_addLondon=m_addNYAM=m_addLunch=m_addReset=false;
      SetWindow(asia,  "Asie",   -6*60,   0);
      SetWindow(london,"Londres", 2*60,   5*60);
      SetWindow(nyam,  "NY AM",   9*60+30,12*60);
      SetWindow(lunch, "Lunch",  12*60,   13*60+30);
      SetWindow(reset, "Reset",   7*60,   m_resetEndMin);
      pdh=pdl=pwh=pwl=pmh=pml=0;
      monthOpen=iOpen(m_sym,PERIOD_MN1,0);
      //--- PDH/PDL des 3 derniers jours de trading (18:00 -> 17:00 NY), tracés H1 (astuce ICT)
      datetime d=anchor;
      int found=0;
      for(int tries=0;tries<8 && found<3;tries++)
        {
         d=CTimeManager::PrevTradingDay(d);
         MqlRates r[];
         datetime f=m_tm.NYToServer(d-6*SEC_HOUR),t=m_tm.NYToServer(d+17*SEC_HOUR);
         int n=CopyRates(m_sym,PERIOD_H1,f,t-1,r);
         if(n<=0) continue;
         double hi=r[0].high,lo=r[0].low;
         datetime th=r[0].time,tl=r[0].time;
         for(int i=1;i<n;i++)
           {
            if(r[i].high>hi) { hi=r[i].high; th=r[i].time; }
            if(r[i].low <lo) { lo=r[i].low;  tl=r[i].time; }
           }
         string tag=(found==0)?"PD":"PD-"+IntegerToString(found);
         if(found==0) { pdh=hi; pdl=lo; }
         //--- vérification de sweep depuis la fin du jour concerné
         AddOrMerge(tag+"H",LIQ_PREV_DAY,true, hi,th,t);
         AddOrMerge(tag+"L",LIQ_PREV_DAY,false,lo,tl,t);
         found++;
        }
      //--- Semaine / mois précédents (depuis le début de la période en cours)
      pwh=iHigh(m_sym,PERIOD_W1,1);  pwl=iLow(m_sym,PERIOD_W1,1);
      pmh=iHigh(m_sym,PERIOD_MN1,1); pml=iLow(m_sym,PERIOD_MN1,1);
      datetime w0=iTime(m_sym,PERIOD_W1,0),m0=iTime(m_sym,PERIOD_MN1,0);
      AddOrMerge("PWH",LIQ_PREV_WEEK, true, pwh,iTime(m_sym,PERIOD_W1,1), w0);
      AddOrMerge("PWL",LIQ_PREV_WEEK, false,pwl,iTime(m_sym,PERIOD_W1,1), w0);
      AddOrMerge("PMH",LIQ_PREV_MONTH,true, pmh,iTime(m_sym,PERIOD_MN1,1),m0);
      AddOrMerge("PML",LIQ_PREV_MONTH,false,pml,iTime(m_sym,PERIOD_MN1,1),m0);
      //--- IPDA 20 / 40 / 60 jours
      int per[3]={20,40,60};
      for(int i=0;i<3;i++)
        {
         ipdaH[i]=ipdaL[i]=0;
         int ih=iHighest(m_sym,PERIOD_D1,MODE_HIGH,per[i],1);
         int il=iLowest(m_sym,PERIOD_D1,MODE_LOW,per[i],1);
         if(ih<0 || il<0) continue;
         ipdaH[i]=iHigh(m_sym,PERIOD_D1,ih);
         ipdaL[i]=iLow(m_sym,PERIOD_D1,il);
         AddOrMerge("IPDA"+IntegerToString(per[i])+"H",LIQ_IPDA,true, ipdaH[i],iTime(m_sym,PERIOD_D1,ih),m_dayStartSrv);
         AddOrMerge("IPDA"+IntegerToString(per[i])+"L",LIQ_IPDA,false,ipdaL[i],iTime(m_sym,PERIOD_D1,il),m_dayStartSrv);
        }
      //--- swings M15 encore intacts sur la période de recherche
      int bars=m_lookbackH*4+m_strength+2;
      ScanSwings(m_strength+1,bars);
     }

   void              OnNewBar(datetime now)
     {
      UpdateSession(asia,  "Asie",   LIQ_ASIA,  m_addAsia,  now);
      UpdateSession(london,"Londres",LIQ_LONDON,m_addLondon,now);
      UpdateSession(nyam,  "NY AM",  LIQ_NY_AM, m_addNYAM,  now);
      UpdateSession(lunch, "Lunch",  LIQ_LUNCH, m_addLunch, now);
      UpdateSession(reset, "Reset",  LIQ_RESET, m_addReset, now);
     }

   //--- Niveau fourni par un autre module (ex. High / Low d'un OPR)
   int               AddExternal(const string name,int type,bool buy,double price,datetime tFormed,datetime checkFrom)
     { return(AddOrMerge(name,type,buy,price,tFormed,checkFrom)); }

   void              OnNewM15(void) { ScanSwings(m_strength+1,m_strength+1); }

   void              OnTick(double bid,datetime nowSrv)
     {
      for(int i=0;i<ArraySize(lv);i++)
        {
         if(lv[i].swept) continue;
         if(lv[i].buySide ? bid>lv[i].price : bid<lv[i].price)
           {
            lv[i].swept=true;
            lv[i].tSwept=nowSrv;
            int k=ArraySize(m_events);
            ArrayResize(m_events,k+1);
            m_events[k]=i;
           }
        }
     }

   //--- v2.40 : mèche de la bougie M1 clôturée au-delà d'un niveau intact = prise de liquidité.
   //--- En « Every tick » rien ne change ; en OHLC M1 / prix d'ouverture, aucune prise n'est manquée.
   void              OnClosedBar(void)
     {
      datetime t=iTime(m_sym,PERIOD_M1,1);
      double h=iHigh(m_sym,PERIOD_M1,1),l=iLow(m_sym,PERIOD_M1,1);
      if(t<=0 || h<=0 || l<=0) return;
      for(int i=0;i<ArraySize(lv);i++)
        {
         if(lv[i].swept || lv[i].tFormed>=t) continue;
         if(lv[i].buySide ? h>lv[i].price : l<lv[i].price)
           {
            lv[i].swept=true;
            lv[i].tSwept=t;
            int k=ArraySize(m_events);
            ArrayResize(m_events,k+1);
            m_events[k]=i;
           }
        }
     }

   //--- Niveaux pris en direct depuis le dernier appel (déclencheurs de setups)
   int               PopSweeps(int &out[])
     {
      int n=ArraySize(m_events);
      ArrayResize(out,n);
      for(int i=0;i<n;i++) out[i]=m_events[i];
      ArrayResize(m_events,0);
      return(n);
     }
   //--- Liquidité intacte la plus proche au-delà d'un prix (cible / DOL), poids minimal
   //--- buy=true : BSL au-dessus de px ; false : SSL en dessous. skip = nombre de niveaux à sauter.
   int               NextIntact(bool buy,double px,int minWeight,int skip=0)
     {
      int  used[];
      for(int pass=0;pass<=skip;pass++)
        {
         int best=-1;
         double bd=DBL_MAX;
         for(int i=0;i<ArraySize(lv);i++)
           {
            if(lv[i].swept || lv[i].buySide!=buy || lv[i].weight<minWeight) continue;
            bool isUsed=false;
            for(int u=0;u<ArraySize(used);u++) if(used[u]==i) isUsed=true;
            if(isUsed) continue;
            double d=buy ? lv[i].price-px : px-lv[i].price;
            if(d>0 && d<bd) { bd=d; best=i; }
           }
         if(best<0) return(-1);
         if(pass==skip) return(best);
         int k=ArraySize(used);
         ArrayResize(used,k+1);
         used[k]=best;
        }
      return(-1);
     }
   //--- Heure du sweep du premier niveau d'un type/côté donné (0 = pas pris ou absent)
   datetime          SweepTime(int type,bool buy)
     {
      for(int i=0;i<ArraySize(lv);i++)
         if(lv[i].type==type && lv[i].buySide==buy) return(lv[i].swept?lv[i].tSwept:0);
      return(0);
     }
   int               CountIntact(bool buy)
     {
      int c=0;
      for(int i=0;i<ArraySize(lv);i++) if(!lv[i].swept && lv[i].buySide==buy) c++;
      return(c);
     }
   //--- Niveau intact le plus proche du prix (index, -1 si aucun)
   int               NearestIntact(bool buy,double px)
     {
      int best=-1;
      double bd=DBL_MAX;
      for(int i=0;i<ArraySize(lv);i++)
        {
         if(lv[i].swept || lv[i].buySide!=buy) continue;
         double d=buy ? lv[i].price-px : px-lv[i].price;
         if(d>=0 && d<bd) { bd=d; best=i; }
        }
      return(best);
     }
   //--- Dernière liquidité prise (index, -1 si aucune aujourd'hui)
   int               LastSwept(void)
     {
      int best=-1;
      datetime bt=0;
      for(int i=0;i<ArraySize(lv);i++)
         if(lv[i].swept && lv[i].tSwept>=m_dayStartSrv && lv[i].tSwept>bt) { bt=lv[i].tSwept; best=i; }
      return(best);
     }
   //--- Zone de la plage du jour précédent : 0-25-50-75-100 %
   double            PDPercent(double px)
     {
      if(pdh<=pdl) return(-1);
      return((px-pdl)/(pdh-pdl)*100.0);
     }
  };

#endif
//+------------------------------------------------------------------+
//=== fin LiquidityEngine.mqh ===
//=== début GapEngine.mqh ===
//+------------------------------------------------------------------+
//|                                                   GapEngine.mqh  |
//|  NDOG (16:59 -> 18:00, 5 derniers jours), NWOG (vendredi ->      |
//|  dimanche, 5 dernières semaines), RTH Gap (clôture RTH veille -> |
//|  ouverture 09:30), CE, comblement, et "cluster" : le prix va là  |
//|  où il y a le plus de déséquilibres (NDOG/NWOG) à rééquilibrer.  |
//+------------------------------------------------------------------+
#ifndef ICTNAS_GAPENGINE_MQH
#define ICTNAS_GAPENGINE_MQH

struct SGap
  {
   bool              valid;
   bool              weekly;     // l'écart entre les deux barres dépasse 30 h (week-end)
   datetime          tClose;     // barre avant la pause (heure serveur)
   datetime          tOpen;      // première barre après la pause
   double            closePx;
   double            openPx;
   void              Clear(void) { valid=false; weekly=false; tClose=0; tOpen=0; closePx=0; openPx=0; }
   double            Hi(void)    { return(MathMax(closePx,openPx)); }
   double            Lo(void)    { return(MathMin(closePx,openPx)); }
   double            CE(void)    { return((closePx+openPx)/2.0); }
   double            Size(void)  { return(openPx-closePx); }
  };

class CGapEngine
  {
public:
   SGap              ndog[];     // [0] = le plus récent
   SGap              nwog[];
   SGap              rth;
   datetime          tRthCE;     // CE du RTH gap touchée
   datetime          tRthFill;   // RTH gap entièrement comblé
   double            weekOpen;   // ouverture de la semaine (dimanche 18:00)

private:
   string            m_sym;
   CTimeManager     *m_tm;
   int               m_keep;
   int               m_rthCloseMin;
   double            m_bigPts;
   datetime          m_anchor;
   datetime          m_rthOpenSrv;
   bool              m_rthDone;

   bool              FindGap(datetime afterNY,int searchSec,SGap &g)
     {
      g.Clear();
      MqlRates o,c;
      datetime t=m_tm.NYToServer(afterNY);
      if(!FirstBarAtOrAfter(m_sym,t,searchSec,o)) return(false);
      if(!LastBarBefore(m_sym,o.time,4*SEC_DAY,c)) return(false);
      g.valid=true;
      g.tOpen=o.time;  g.openPx=o.open;
      g.tClose=c.time; g.closePx=c.close;
      g.weekly=((o.time-c.time)>30*SEC_HOUR);
      return(true);
     }
   void              Push(SGap &arr[],SGap &g)
     {
      int n=ArraySize(arr);
      ArrayResize(arr,n+1);
      arr[n]=g;
     }
   void              TrackRth(const MqlRates &b)
     {
      if(!rth.valid || b.time<rth.tOpen) return;
      bool up=(rth.openPx>rth.closePx);
      if(tRthCE==0   && (up ? b.low<=rth.CE()     : b.high>=rth.CE()))     tRthCE=b.time;
      if(tRthFill==0 && (up ? b.low<=rth.closePx  : b.high>=rth.closePx))  tRthFill=b.time;
     }

public:
   void              Init(const string sym,CTimeManager *tm,int keep,int rthCloseMin,double bigPts)
     {
      m_sym=sym;
      m_tm=tm;
      m_keep=MathMax(1,keep);
      m_rthCloseMin=(rthCloseMin>0)?rthCloseMin:16*60+15;
      m_bigPts=bigPts;
     }

   void              NewDay(datetime anchor)
     {
      m_anchor=anchor;
      ArrayResize(ndog,0);
      ArrayResize(nwog,0);
      rth.Clear();
      tRthCE=0; tRthFill=0; m_rthDone=false;
      m_rthOpenSrv=m_tm.NYToServer(anchor+9*SEC_HOUR+30*SEC_MIN);
      //--- NDOG : première barre à partir de 17:00 NY la veille du jour de trading
      datetime a=anchor;
      for(int i=0;i<m_keep;i++)
        {
         SGap g;
         if(FindGap(a-7*SEC_HOUR,3*SEC_HOUR,g)) Push(ndog,g);
         a=CTimeManager::PrevTradingDay(a);
        }
      //--- NWOG : première barre à partir du vendredi 17:00 NY
      int dow=CTimeManager::DayOfWeek(anchor);
      datetime mon=anchor-(dow-1)*SEC_DAY;
      weekOpen=0;
      for(int w=0;w<m_keep;w++)
        {
         SGap g;
         datetime fri17=mon-7*w*SEC_DAY-3*SEC_DAY+17*SEC_HOUR;
         if(FindGap(fri17,3*SEC_DAY,g))
           {
            Push(nwog,g);
            if(w==0) weekOpen=g.openPx;
           }
        }
     }

   void              OnNewBar(datetime now)
     {
      if(!m_rthDone && now>=m_rthOpenSrv)
        {
         MqlRates c,o;
         datetime p=CTimeManager::PrevTradingDay(m_anchor);
         datetime closeSrv=m_tm.NYToServer(p+m_rthCloseMin*SEC_MIN);
         if(LastBarBefore(m_sym,closeSrv,30*SEC_MIN,c) && FirstBarAtOrAfter(m_sym,m_rthOpenSrv,10*SEC_MIN,o))
           {
            rth.valid=true;
            rth.tClose=c.time; rth.closePx=c.close;
            rth.tOpen=o.time;  rth.openPx=o.open;
            m_rthDone=true;
            //--- rattrapage
            datetime cur=iTime(m_sym,PERIOD_M1,0);
            if(cur>rth.tOpen)
              {
               MqlRates b[];
               int n=CopyRates(m_sym,PERIOD_M1,rth.tOpen,cur-1,b);
               for(int i=0;i<n;i++) TrackRth(b[i]);
              }
           }
         else if(now>=m_rthOpenSrv+15*SEC_MIN)
            m_rthDone=true;   // pas de données (jour férié US...)
        }
      MqlRates b[];
      if(CopyRates(m_sym,PERIOD_M1,1,1,b)==1) TrackRth(b[0]);
     }

   bool              RthIsBig(void) { return(rth.valid && MathAbs(rth.Size())>=m_bigPts); }

   //--- Cluster : nombre de CE NDOG/NWOG au-dessus / en dessous du prix
   void              Cluster(double px,int &above,int &below)
     {
      above=0; below=0;
      for(int i=0;i<ArraySize(ndog);i++)
        {
         if(!ndog[i].valid) continue;
         if(ndog[i].CE()>px) above++; else below++;
        }
      for(int i=0;i<ArraySize(nwog);i++)
        {
         if(!nwog[i].valid) continue;
         if(nwog[i].CE()>px) above++; else below++;
        }
     }
   //--- Biais "déséquilibres" : +1 si la majorité des gaps est au-dessus, -1 si en dessous
   int               ClusterBias(double px)
     {
      int a,b;
      Cluster(px,a,b);
      if(a>b) return(BIAS_BULL);
      if(b>a) return(BIAS_BEAR);
      return(BIAS_NONE);
     }
  };

#endif
//+------------------------------------------------------------------+
//=== fin GapEngine.mqh ===
//=== début QuarterlyEngine.mqh ===
//+------------------------------------------------------------------+
//|                                             QuarterlyEngine.mqh  |
//|  Quarterly Theory : jour de 24 h en 4 quarts de 6 h (AMDX),      |
//|  chaque quart en 4 cycles de 90 min, chaque cycle en 4 micro-    |
//|  quarts de 22,5 min. True Opens : jour 00:00, session (Q2 de la  |
//|  session : 19:30 / 01:30 / 07:30 / 13:30), cycle 90 min (+22:30),|
//|  semaine (lundi 18:00 = ouverture du mardi).                     |
//+------------------------------------------------------------------+
#ifndef ICTNAS_QUARTERLYENGINE_MQH
#define ICTNAS_QUARTERLYENGINE_MQH

class CQuarterlyEngine
  {
public:
   int               dayQ;        // 1 = Asie 18-00, 2 = Londres 00-06, 3 = NY AM 06-12, 4 = NY PM 12-18
   int               q90;         // 1..4 dans la session de 6 h
   int               q22;         // 1..4 dans le cycle de 90 min
   datetime          sessStartNY;
   datetime          cycStartNY;
   datetime          sessTO_NY;
   datetime          cycTO_NY;
   datetime          weekTO_NY;
   double            dayTO;       // 0 tant que l'heure n'est pas atteinte
   double            sessTO;
   double            cycTO;
   double            weekTO;

private:
   string            m_sym;
   CTimeManager     *m_tm;
   datetime          m_anchor;

   double            PriceAtNY(datetime ny)
     {
      datetime srv=m_tm.NYToServer(ny);
      if(srv>TimeCurrent()) return(0.0);
      MqlTick tk[];
      int n=CopyTicks(m_sym,tk,COPY_TICKS_INFO,(ulong)srv*1000,1);
      if(n>0 && tk[0].time<=srv+120 && tk[0].bid>0) return(tk[0].bid);
      MqlRates r;
      datetime barT=(datetime)((long)srv-((long)srv%60));
      if(FirstBarAtOrAfter(m_sym,barT,10*SEC_MIN,r)) return(r.open);
      return(0.0);
     }

public:
   void              Init(const string sym,CTimeManager *tm) { m_sym=sym; m_tm=tm; }

   void              NewDay(datetime anchor)
     {
      m_anchor=anchor;
      dayTO=0; sessTO=0; cycTO=0; weekTO=0;
      sessStartNY=0; cycStartNY=0;
      int dow=CTimeManager::DayOfWeek(anchor);
      datetime mon=anchor-(dow-1)*SEC_DAY;
      weekTO_NY=mon+18*SEC_HOUR;           // lundi 18:00 NY
     }

   //--- Appelé à chaque nouvelle barre M1
   void              Update(datetime nowNY)
     {
      int m=CTimeManager::MinuteOfDay(nowNY);
      datetime ds=CTimeManager::DayStart(nowNY);
      int sessStartMin;
      if(m>=18*60) { dayQ=1; sessStartMin=18*60; }
      else         { dayQ=m/360+2; if(dayQ>4) dayQ=4; sessStartMin=(dayQ-2)*360; }
      datetime ss=ds+sessStartMin*SEC_MIN;
      int secInSess=(int)(nowNY-ss);
      q90=MathMin(4,secInSess/5400+1);
      datetime cs=ss+(q90-1)*5400;
      int secInCyc=(int)(nowNY-cs);
      q22=MathMin(4,secInCyc/1350+1);
      if(ss!=sessStartNY) { sessStartNY=ss; sessTO_NY=ss+5400; sessTO=0; }
      if(cs!=cycStartNY)  { cycStartNY=cs;  cycTO_NY=cs+1350;  cycTO=0;  }
      if(dayTO==0  && nowNY>=m_anchor)   dayTO=PriceAtNY(m_anchor);
      if(sessTO==0 && nowNY>=sessTO_NY)  sessTO=PriceAtNY(sessTO_NY);
      if(cycTO==0  && nowNY>=cycTO_NY)   cycTO=PriceAtNY(cycTO_NY);
      if(weekTO==0 && nowNY>=weekTO_NY)  weekTO=PriceAtNY(weekTO_NY);
     }

   static string     AMDX(int q)
     {
      switch(q)
        {
         case 1: return("A");
         case 2: return("M");
         case 3: return("D");
         case 4: return("X");
        }
      return("?");
     }
   static string     DayQName(int q)
     {
      switch(q)
        {
         case 1: return("Asie");
         case 2: return("Londres");
         case 3: return("NY AM");
         case 4: return("NY PM");
        }
      return("?");
     }
   //--- Alignement ICT : acheter sous le True Open (discount), vendre au-dessus (premium)
   static int        Alignment(double px,double to)
     {
      if(to<=0) return(BIAS_NONE);
      if(px<to) return(BIAS_BULL);
      if(px>to) return(BIAS_BEAR);
      return(BIAS_NONE);
     }
  };

#endif
//+------------------------------------------------------------------+
//=== fin QuarterlyEngine.mqh ===
//=== début SMTCheck.mqh ===
//+------------------------------------------------------------------+
//|                                                    SMTCheck.mqh  |
//|  Vérifie la disponibilité des données ES / US500 pour la SMT.    |
//|  Phase 1 : contrôle seulement. La divergence arrive en Phase 2.  |
//|  Si aucune donnée : la SMT est désactivée automatiquement.       |
//+------------------------------------------------------------------+
#ifndef ICTNAS_SMTCHECK_MQH
#define ICTNAS_SMTCHECK_MQH

class CSMTCheck
  {
private:
   string            m_cands[];
   string            m_found;
   bool              m_avail;
   bool              m_enabled;
   int               m_tries;

   void              AddCand(const string s)
     {
      if(s=="") return;
      for(int i=0;i<ArraySize(m_cands);i++) if(m_cands[i]==s) return;
      int n=ArraySize(m_cands);
      ArrayResize(m_cands,n+1);
      m_cands[n]=s;
     }

public:
   void              Init(bool enabled,const string wanted)
     {
      m_enabled=enabled;
      m_avail=false;
      m_found="";
      m_tries=0;
      ArrayResize(m_cands,0);
      if(!enabled) return;
      if(wanted!="") { AddCand(wanted); return; }
      //--- suffixe du symbole du graphique (ex. ".cash", ".r", "m")
      string suffix="";
      int dot=StringFind(_Symbol,".");
      if(dot>0) suffix=StringSubstr(_Symbol,dot);
      string base[]={"US500","SPX500","US500Cash","USA500","SP500","SPX","ES","USSPX500"};
      for(int i=0;i<ArraySize(base);i++)
        {
         if(suffix!="") AddCand(base[i]+suffix);
         AddCand(base[i]);
        }
     }

   bool              Check(void)
     {
      if(!m_enabled || m_avail) return(m_avail);
      if(m_tries>=10) return(false);
      m_tries++;
      for(int i=0;i<ArraySize(m_cands);i++)
        {
         bool custom=false;
         if(!SymbolExist(m_cands[i],custom)) continue;
         if(!SymbolSelect(m_cands[i],true)) continue;
         if(Bars(m_cands[i],PERIOD_M1)>100)
           {
            m_found=m_cands[i];
            m_avail=true;
            return(true);
           }
        }
      return(false);
     }

   bool              Available(void) { return(m_enabled && m_avail); }
   string            FoundSymbol(void) { return(m_found); }

   //--- Divergence SMT au moment d'un sweep sur le NAS :
   //--- highSwept=true : le NAS a pris un plus haut (formé à tLevel) ; SMT si l'ES,
   //--- lui, n'a PAS dépassé son plus haut correspondant entre tLevel et tNow.
   //--- Renvoie -1 si la donnée ES manque (facteur inconnu), 0 = pas de SMT, 1 = SMT.
   int               Divergence(bool highSwept,datetime tLevel,datetime tNow)
     {
      if(!Available() || tLevel<=0 || tNow<=tLevel) return(-1);
      long age=(long)(tNow-tLevel);
      ENUM_TIMEFRAMES tf=(age<SEC_DAY)?PERIOD_M1:((age<5*SEC_DAY)?PERIOD_M15:PERIOD_H1);
      int ps=PeriodSeconds(tf);
      MqlRates ref[],aft[];
      int n1=CopyRates(m_found,tf,tLevel-3*ps,tLevel+3*ps,ref);
      int n2=CopyRates(m_found,tf,tLevel+4*ps,tNow,aft);
      if(n1<=0 || n2<=0) return(-1);
      if(highSwept)
        {
         double r=ref[0].high,a=aft[0].high;
         for(int i=1;i<n1;i++) r=MathMax(r,ref[i].high);
         for(int i=1;i<n2;i++) a=MathMax(a,aft[i].high);
         return(a<=r ? 1 : 0);
        }
      double r=ref[0].low,a=aft[0].low;
      for(int i=1;i<n1;i++) r=MathMin(r,ref[i].low);
      for(int i=1;i<n2;i++) a=MathMin(a,aft[i].low);
      return(a>=r ? 1 : 0);
     }
   string            Status(void)
     {
      if(!m_enabled) return("SMT desactivee (input)");
      if(m_avail)    return("SMT : donnees "+m_found+" OK");
      return("SMT : indisponible (aucun symbole ES/US500 avec historique) -> desactivee");
     }
  };

#endif
//+------------------------------------------------------------------+
//=== fin SMTCheck.mqh ===
//=== début RiskManager.mqh ===
//+------------------------------------------------------------------+
//|                                                 RiskManager.mqh  |
//|  Taille de lot au % de risque (OrderCalcProfit : valeur de tick  |
//|  et conversion de devise gérées par MT5), garde-fous journaliers |
//|  et prop firm. Règles validées : risque plafonné à 2 %, stop     |
//|  journalier -2 %, objectif +3 %, DD total 8 %, RR min 2.         |
//|  v2.30 : stop / objectif journalier à 0 = désactivé.             |
//|  v2.40 : lot minimum accepté si son risque <= tolérance x risque |
//|  voulu (v6.20 : 150 %, jamais au-delà du plafond dur), lot max.  |
//|  Le jour de risque démarre à 18:00 NY (= minuit Prague, FTMO).   |
//+------------------------------------------------------------------+
#ifndef ICTNAS_RISKMANAGER_MQH
#define ICTNAS_RISKMANAGER_MQH

#define RISK_HARD_CAP_PCT 3.0

class CRiskManager
  {
private:
   string            m_sym;
   double            m_riskPct;
   double            m_dailyLossPct;
   double            m_dailyTargetPct;
   double            m_maxTotalDDPct;
   double            m_minRR;
   double            m_initialBalance;
   double            m_dayStartBalance;
   bool              m_dayBlocked;
   bool              m_hardBlocked;
   string            m_reason;
   double            m_minLotTol;        // v2.40 : lot min accepté jusqu'à x fois le risque voulu (1 = refus strict)
   double            m_maxLots;          // v2.40 : lot maximum absolu (0 = aucun)
   string            m_lotNote;          // v2.40 : explication du dernier calcul (refus ou lot minimum)
   bool              m_ddReportOnly;     // v2.50 : testeur, DD total signalé sans arrêt définitif
   bool              m_ddReported;       // v2.50 : DD total déjà signalé
   datetime          m_ddHitTime;        // v2.50 : heure serveur du premier dépassement du DD total

   static int        VolDigits(double step)
     {
      int d=0;
      while(d<8 && MathAbs(step*MathPow(10,d)-MathRound(step*MathPow(10,d)))>1e-8) d++;
      return(d);
     }

public:
   void              Init(const string sym,double riskPct,double dailyLoss,double dailyTarget,
                          double maxTotalDD,double minRR,double initialBalance)
     {
      m_sym=sym;
      m_riskPct=MathMin(MathMax(riskPct,0.0),RISK_HARD_CAP_PCT);
      m_dailyLossPct=dailyLoss;
      m_dailyTargetPct=dailyTarget;
      m_maxTotalDDPct=maxTotalDD;
      m_minRR=minRR;
      m_initialBalance=(initialBalance>0)?initialBalance:AccountInfoDouble(ACCOUNT_BALANCE);
      m_dayStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
      m_dayBlocked=false;
      m_hardBlocked=false;
      m_reason="";
      m_minLotTol=1.0;
      m_maxLots=0;
      m_lotNote="";
      m_ddReportOnly=false;
      m_ddReported=false;
      m_ddHitTime=0;
     }
   //--- v2.50 : true = DD total signalé une fois, sans arrêt définitif (testeur uniquement)
   void              SetDDReportOnly(bool on) { m_ddReportOnly=on; }
   bool              DDReported(void)  { return(m_ddReported); }
   datetime          DDHitTime(void)   { return(m_ddHitTime); }
   void              SetLotLimits(double minLotTol,double maxLots) { m_minLotTol=MathMax(minLotTol,1.0); m_maxLots=MathMax(maxLots,0.0); }
   string            LotNote(void)   { return(m_lotNote); }
   double            RiskPct(void)   { return(m_riskPct); }
   double            MinRR(void)     { return(m_minRR); }

   void              NewDay(void)
     {
      m_dayStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
      m_dayBlocked=false;
      if(!m_hardBlocked) m_reason="";
     }

   double            DayPnLPct(void)
     {
      if(m_dayStartBalance<=0) return(0.0);
      return((AccountInfoDouble(ACCOUNT_EQUITY)-m_dayStartBalance)/m_dayStartBalance*100.0);
     }
   double            TotalDDPct(void)
     {
      if(m_initialBalance<=0) return(0.0);
      return((m_initialBalance-AccountInfoDouble(ACCOUNT_EQUITY))/m_initialBalance*100.0);
     }

   //--- À appeler régulièrement (nouvelle barre / tick)
   void              Update(void)
     {
      if(m_hardBlocked) return;
      if(m_maxTotalDDPct>0 && TotalDDPct()>=m_maxTotalDDPct && m_ddReportOnly)
        {
         //--- v2.50 : testeur, le DD total est signalé (date) mais le backtest continue
         if(!m_ddReported)
           {
            m_ddReported=true;
            m_ddHitTime=TimeCurrent();
            Print("!!! DD total ",DoubleToString(m_maxTotalDDPct,1),"% atteint le ",TimeToString(m_ddHitTime,TIME_DATE|TIME_MINUTES),
                  " : en reel, ARRET DEFINITIF. Testeur : le test continue (InpDDHaltInTester=false)");
           }
        }
      else if(m_maxTotalDDPct>0 && TotalDDPct()>=m_maxTotalDDPct)
        {
         //--- règle prop firm : DD total atteint = compte en échec -> plus aucun trade (0 = désactivé)
         m_hardBlocked=true;
         m_reason="DD total "+DoubleToString(m_maxTotalDDPct,1)+"% atteint : ARRET DEFINITIF (InpMaxTotalDDPct=0 pour desactiver)";
         Print("!!! ",m_reason);
         return;
        }
      if(m_dayBlocked) return;
      double d=DayPnLPct();
      if(m_dailyLossPct>0 && d<=-m_dailyLossPct)  { m_dayBlocked=true; m_reason="Stop journalier -"+DoubleToString(m_dailyLossPct,1)+"%"; }
      else if(m_dailyTargetPct>0 && d>=m_dailyTargetPct) { m_dayBlocked=true; m_reason="Objectif journalier +"+DoubleToString(m_dailyTargetPct,1)+"%"; }
     }
   bool              CanTrade(string &why)
     {
      why=m_reason;
      return(!m_dayBlocked && !m_hardBlocked);
     }

   //--- Lots pour risquer riskPct du solde entre entry et sl. 0 = trade impossible
   //--- (jamais d'arrondi vers le haut ; v2.40 : le lot minimum est accepté si son risque
   //--- reste <= m_minLotTol x le risque voulu et <= plafond dur, sinon refus expliqué)
   double            CalcLots(bool isBuy,double entry,double sl,double riskPct=-1)
     {
      if(riskPct<0) riskPct=m_riskPct;
      riskPct=MathMin(riskPct,RISK_HARD_CAP_PCT);
      m_lotNote="";
      if(entry<=0 || sl<=0 || entry==sl) return(0.0);
      double loss=0.0;
      ENUM_ORDER_TYPE t=isBuy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      if(!OrderCalcProfit(t,m_sym,1.0,entry,sl,loss)) return(0.0);
      loss=MathAbs(loss);
      if(loss<=0) return(0.0);
      double riskMoney=AccountInfoDouble(ACCOUNT_BALANCE)*riskPct/100.0;
      double step=SymbolInfoDouble(m_sym,SYMBOL_VOLUME_STEP);
      double vmin=SymbolInfoDouble(m_sym,SYMBOL_VOLUME_MIN);
      double vmax=SymbolInfoDouble(m_sym,SYMBOL_VOLUME_MAX);
      if(step<=0) step=0.01;
      double lots=MathFloor(riskMoney/loss/step+1e-9)*step;
      if(lots<vmin)
        {
         double bal=AccountInfoDouble(ACCOUNT_BALANCE);
         double minRisk=vmin*loss;
         double allowed=MathMin(riskMoney*m_minLotTol,bal*RISK_HARD_CAP_PCT/100.0);
         if(minRisk>allowed+1e-9)
           {
            m_lotNote="lot < lot minimum : "+DoubleToString(vmin,2)+" lot risque "+DoubleToString(minRisk,2)+" > "+
                      DoubleToString(allowed,2)+" autorises ("+DoubleToString(riskPct,2)+" % x "+DoubleToString(m_minLotTol,2)+")";
            return(0.0);
           }
         lots=vmin;
         m_lotNote="lot minimum "+DoubleToString(vmin,2)+" (risque "+DoubleToString((bal>0)?minRisk/bal*100.0:0,2)+" % du solde)";
        }
      if(lots>vmax) lots=vmax;
      if(m_maxLots>0 && lots>m_maxLots) lots=MathMax(vmin,MathFloor(m_maxLots/step+1e-9)*step);
      return(NormalizeDouble(lots,VolDigits(step)));
     }

   static double     RR(double entry,double sl,double tp)
     {
      double r=MathAbs(entry-sl);
      if(r<=0) return(0.0);
      return(MathAbs(tp-entry)/r);
     }
   //--- Spécifications du contrat (vérification broker, Q3)
   string            SpecString(void)
     {
      return("TickSize "+DoubleToString(SymbolInfoDouble(m_sym,SYMBOL_TRADE_TICK_SIZE),_Digits)+
             " | TickValue "+DoubleToString(SymbolInfoDouble(m_sym,SYMBOL_TRADE_TICK_VALUE),4)+
             " | Contrat "+DoubleToString(SymbolInfoDouble(m_sym,SYMBOL_TRADE_CONTRACT_SIZE),2)+
             " | Lot min/pas "+DoubleToString(SymbolInfoDouble(m_sym,SYMBOL_VOLUME_MIN),2)+"/"+
             DoubleToString(SymbolInfoDouble(m_sym,SYMBOL_VOLUME_STEP),2));
     }
  };

#endif
//+------------------------------------------------------------------+
//=== fin RiskManager.mqh ===
//=== début DataCollector.mqh ===
//+------------------------------------------------------------------+
//|                                               DataCollector.mqh  |
//|  Écrit les données dans SQLite (natif MT5, dossier Common\Files) |
//|  et, en option, dans un CSV miroir. Schéma : Database/schema.sql |
//|  Phase 1 : table day_context. Tables signals / trades prêtes.    |
//+------------------------------------------------------------------+
#ifndef ICTNAS_DATACOLLECTOR_MQH
#define ICTNAS_DATACOLLECTOR_MQH
//=== début Schema.mqh ===
//+------------------------------------------------------------------+
//|  Schema.mqh — GÉNÉRÉ AUTOMATIQUEMENT depuis Database/schema.sql   |
//|  Ne pas modifier à la main : python -m ict_quant.tools.gen_mql_schema
//+------------------------------------------------------------------+
#ifndef ICTNAS_SCHEMA_MQH
#define ICTNAS_SCHEMA_MQH

int ICTNAS_GetSchema(string &out[])
  {
   ArrayResize(out,7);
   out[0]="CREATE TABLE IF NOT EXISTS day_context ( "
        +"symbol            TEXT    NOT NULL, "
        +"trade_date        TEXT    NOT NULL, "
        +"dow               INTEGER, "
        +"month             INTEGER, "
        +"complete          INTEGER, "
        +"weekly_profile    TEXT, "
        +"day_open          REAL, day_high REAL, day_low REAL, day_close REAL, "
        +"asia_h REAL, asia_l REAL, asia_h_swept_ny TEXT, asia_l_swept_ny TEXT, "
        +"london_h REAL, london_l REAL, london_h_swept_ny TEXT, london_l_swept_ny TEXT, "
        +"nyam_h REAL, nyam_l REAL, "
        +"mor_h REAL, mor_l REAL, mor_bias_0250 INTEGER, "
        +"mor_ext_up REAL, mor_ext_dn REAL, mor_up2_ny TEXT, mor_dn2_ny TEXT, "
        +"opr0130_h REAL, opr0130_l REAL, opr0130_ext_up REAL, opr0130_ext_dn REAL, "
        +"opr0700_h REAL, opr0700_l REAL, opr0700_ext_up REAL, opr0700_ext_dn REAL, "
        +"opr0930_h REAL, opr0930_l REAL, opr0930_break INTEGER, opr0930_break_ny TEXT, "
        +"opr0930_returned INTEGER, opr0930_ext_up REAL, opr0930_ext_dn REAL, "
        +"opr0930_up2_ny TEXT, opr0930_dn2_ny TEXT, trend_day INTEGER, "
        +"opr1330_h REAL, opr1330_l REAL, opr1330_ext_up REAL, opr1330_ext_dn REAL, "
        +"shadow_h REAL, shadow_l REAL, shadow_first INTEGER, shadow_first_ny TEXT, "
        +"shadow_opp INTEGER, shadow_opp_ny TEXT, "
        +"pdh REAL, pdl REAL, pdh_swept_ny TEXT, pdl_swept_ny TEXT, "
        +"pwh REAL, pwl REAL, pmh REAL, pml REAL, "
        +"ipda20_h REAL, ipda20_l REAL, ipda40_h REAL, ipda40_l REAL, ipda60_h REAL, ipda60_l REAL, "
        +"midnight_open REAL, open_0830 REAL, open_0930 REAL, week_open REAL, month_open REAL, "
        +"ndog_size REAL, ndog_ce REAL, nwog_size REAL, nwog_ce REAL, "
        +"gaps_above_0930 INTEGER, gaps_below_0930 INTEGER, "
        +"rth_gap REAL, rth_big INTEGER, rth_ce_ny TEXT, rth_fill_ny TEXT, "
        +"ea_version        TEXT, "
        +"PRIMARY KEY (symbol, trade_date) "
        +") ";
   out[1]="CREATE TABLE IF NOT EXISTS signals ( "
        +"id                INTEGER PRIMARY KEY AUTOINCREMENT, "
        +"signal_uid        TEXT, "
        +"symbol            TEXT    NOT NULL, "
        +"signal_time_ny    TEXT    NOT NULL, "
        +"trade_date        TEXT    NOT NULL, "
        +"dow INTEGER, month INTEGER, hour_ny INTEGER, minute_ny INTEGER, "
        +"session TEXT, day_quarter INTEGER, q90 INTEGER, q22 INTEGER, "
        +"killzone TEXT, sb_window TEXT, macro TEXT, shadow_active INTEGER, "
        +"model             TEXT    NOT NULL, "
        +"direction         INTEGER NOT NULL, "
        +"swept_liq_type TEXT, swept_liq_weight INTEGER, swept_liq_price REAL, sweep_time_ny TEXT, "
        +"mss INTEGER, cisd INTEGER, displacement INTEGER, "
        +"disp_body_atr REAL, disp_candles INTEGER, disp_size_pts REAL, "
        +"atr_m1 REAL, atr_m5 REAL, atr_m15 REAL, "
        +"fvg_type TEXT, fvg_size_pts REAL, fvg_ce REAL, "
        +"unicorn INTEGER, breaker INTEGER, order_block INTEGER, mitigation_block INTEGER, bpr INTEGER, ifvg INTEGER, "
        +"entry REAL, sl REAL, tp1 REAL, tp2 REAL, tp3 REAL, "
        +"risk_pts REAL, dist_entry_ce REAL, dist_entry_invalidation REAL, planned_rr REAL, "
        +"premium_discount TEXT, pd_pct REAL, ote INTEGER, smt INTEGER, stdv_reached REAL, "
        +"weekly_profile TEXT, amdx TEXT, quarterly_align INTEGER, weekly_bias INTEGER, "
        +"gap_cluster_bias INTEGER, trend_day INTEGER, news_window INTEGER, "
        +"spread_pts REAL, day_range_so_far REAL, asia_range REAL, london_range REAL, ny_range REAL, "
        +"dist_daily_open REAL, dist_weekly_open REAL, dist_monthly_open REAL, dist_midnight_open REAL, "
        +"ict_score REAL, ml_prob REAL, ml_model_id TEXT, "
        +"decision TEXT, "
        +"reject_reason TEXT, "
        +"outcome TEXT, "
        +"simulated INTEGER, filled INTEGER, fill_time_ny TEXT, exit_time_ny TEXT, "
        +"r_multiple REAL, mfe_r REAL, mae_r REAL, minutes_in_trade INTEGER, "
        +"hit_tp1 INTEGER, hit_tp2 INTEGER, hit_tp3 INTEGER, "
        +"ea_version TEXT "
        +") ";
   out[2]="CREATE INDEX IF NOT EXISTS ix_signals_time  ON signals (symbol, signal_time_ny) ";
   out[3]="CREATE INDEX IF NOT EXISTS ix_signals_model ON signals (model) ";
   out[4]="CREATE INDEX IF NOT EXISTS ix_signals_uid   ON signals (signal_uid) ";
   out[5]="CREATE TABLE IF NOT EXISTS trades ( "
        +"id                INTEGER PRIMARY KEY AUTOINCREMENT, "
        +"signal_id         INTEGER REFERENCES signals(id), "
        +"signal_uid        TEXT, "
        +"model             TEXT, "
        +"symbol            TEXT    NOT NULL, "
        +"ticket            INTEGER, "
        +"open_time_ny TEXT, close_time_ny TEXT, "
        +"direction INTEGER, lots REAL, "
        +"entry REAL, exit_price REAL, sl REAL, "
        +"profit_money REAL, profit_pct REAL, profit_pts REAL, r_multiple REAL, "
        +"mfe_pts REAL, mae_pts REAL, minutes_in_trade INTEGER, "
        +"commission REAL, swap REAL, "
        +"outcome TEXT, "
        +"balance_before REAL "
        +") ";
   out[6]="CREATE INDEX IF NOT EXISTS ix_trades_signal ON trades (signal_id) ";
   return(7);
  }

#endif
//=== fin Schema.mqh ===

//--- Ligne à insérer : colonnes + valeurs SQL déjà formatées
class CSqlRow
  {
private:
   string            m_cols[];
   string            m_vals[];     // littéraux SQL
   string            m_raw[];      // valeurs brutes pour le CSV

   void              Push(const string c,const string sqlv,const string raw)
     {
      int n=ArraySize(m_cols);
      ArrayResize(m_cols,n+1);
      ArrayResize(m_vals,n+1);
      ArrayResize(m_raw,n+1);
      m_cols[n]=c; m_vals[n]=sqlv; m_raw[n]=raw;
     }
public:
   void              Clear(void) { ArrayResize(m_cols,0); ArrayResize(m_vals,0); ArrayResize(m_raw,0); }
   void              Text(const string c,const string v)
     {
      if(v=="") { Push(c,"NULL",""); return; }
      string e=v;
      StringReplace(e,"'","''");
      Push(c,"'"+e+"'",v);
     }
   void              Real(const string c,double v,int digits=5)
     {
      if(!MathIsValidNumber(v)) { Push(c,"NULL",""); return; }
      string s=DoubleToString(v,digits);
      Push(c,s,s);
     }
   //--- 0 -> NULL (niveau absent)
   void              Price(const string c,double v)
     {
      if(v==0.0) { Push(c,"NULL",""); return; }
      string s=DoubleToString(v,_Digits);
      Push(c,s,s);
     }
   void              Int(const string c,long v) { string s=IntegerToString(v); Push(c,s,s); }
   int               Count(void) { return(ArraySize(m_cols)); }
   string            InsertSql(const string table,bool replace)
     {
      string cols="",vals="";
      for(int i=0;i<ArraySize(m_cols);i++)
        {
         if(i>0) { cols+=","; vals+=","; }
         cols+=m_cols[i];
         vals+=m_vals[i];
        }
      return((replace?"INSERT OR REPLACE INTO ":"INSERT INTO ")+table+" ("+cols+") VALUES ("+vals+");");
     }
   string            CsvHeader(void)
     {
      string s="";
      for(int i=0;i<ArraySize(m_cols);i++) s+=(i>0?";":"")+m_cols[i];
      return(s);
     }
   string            CsvLine(void)
     {
      string s="";
      for(int i=0;i<ArraySize(m_raw);i++) s+=(i>0?";":"")+m_raw[i];
      return(s);
     }
  };

class CDataCollector
  {
private:
   int               m_db;
   string            m_dbFile;
   bool              m_csv;
   string            m_csvPrefix;
   string            m_lastError;

public:
                     CDataCollector(void) : m_db(INVALID_HANDLE),m_csv(false) {}

   //--- dbFile relatif au dossier Common\Files du terminal
   bool              Open(const string dbFile,bool csvMirror,const string csvPrefix,bool freshInTester)
     {
      m_dbFile=dbFile;
      m_csv=csvMirror;
      m_csvPrefix=csvPrefix;
      if(freshInTester && MQLInfoInteger(MQL_TESTER))
        {
         //--- chaque passe du testeur repart d'une base propre
         FileDelete(m_dbFile,FILE_COMMON);
         if(m_csv)
           {
            FileDelete(m_csvPrefix+"day_context.csv",FILE_COMMON);
            FileDelete(m_csvPrefix+"signals.csv",FILE_COMMON);
           }
        }
      int sep=StringFind(m_dbFile,"\\");
      if(sep>0) FolderCreate(StringSubstr(m_dbFile,0,sep),FILE_COMMON);
      m_db=DatabaseOpen(m_dbFile,DATABASE_OPEN_READWRITE|DATABASE_OPEN_CREATE|DATABASE_OPEN_COMMON);
      if(m_db==INVALID_HANDLE)
        {
         m_lastError="DatabaseOpen "+m_dbFile+" erreur "+IntegerToString(GetLastError());
         Print(m_lastError);
         return(false);
        }
      string st[];
      int n=ICTNAS_GetSchema(st);
      for(int i=0;i<n;i++)
        {
         if(!DatabaseExecute(m_db,st[i]))
           {
            m_lastError="Schema stmt "+IntegerToString(i)+" erreur "+IntegerToString(GetLastError());
            Print(m_lastError);
            return(false);
           }
        }
      return(true);
     }

   void              Close(void)
     {
      if(m_db!=INVALID_HANDLE) DatabaseClose(m_db);
      m_db=INVALID_HANDLE;
     }
   bool              IsOpen(void)    { return(m_db!=INVALID_HANDLE); }
   string            LastError(void) { return(m_lastError); }
   string            FilePath(void)
     {
      return(TerminalInfoString(TERMINAL_COMMONDATA_PATH)+"\\Files\\"+m_dbFile);
     }

   bool              Write(const string table,CSqlRow &row,bool replace)
     {
      bool ok=true;
      if(m_db!=INVALID_HANDLE)
        {
         if(!DatabaseExecute(m_db,row.InsertSql(table,replace)))
           {
            m_lastError=table+" insert erreur "+IntegerToString(GetLastError());
            Print(m_lastError);
            ok=false;
           }
        }
      if(m_csv) WriteCsv(m_csvPrefix+table+".csv",row);
      return(ok);
     }

   //--- Identifiant de la dernière ligne insérée (lier trades -> signals)
   long              LastInsertId(void)
     {
      if(m_db==INVALID_HANDLE) return(-1);
      int req=DatabasePrepare(m_db,"SELECT last_insert_rowid();");
      if(req==INVALID_HANDLE) return(-1);
      long id=-1;
      if(DatabaseRead(req)) DatabaseColumnLong(req,0,id);
      DatabaseFinalize(req);
      return(id);
     }

private:
   void              WriteCsv(const string file,CSqlRow &row)
     {
      int h=FileOpen(file,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ);
      if(h==INVALID_HANDLE) return;
      if(FileSize(h)==0) FileWriteString(h,row.CsvHeader()+"\r\n");
      FileSeek(h,0,SEEK_END);
      FileWriteString(h,row.CsvLine()+"\r\n");
      FileClose(h);
     }
  };

#endif
//+------------------------------------------------------------------+
//=== fin DataCollector.mqh ===
//=== début Drawer.mqh ===
//+------------------------------------------------------------------+
//|                                                      Drawer.mqh  |
//|  Tracés sur le graphique (mode debug) + panneau d'information.   |
//|  Désactivé automatiquement en backtest non visuel (vitesse).     |
//+------------------------------------------------------------------+
#ifndef ICTNAS_DRAWER_MQH
#define ICTNAS_DRAWER_MQH

class CDrawer
  {
private:
   bool              m_on;
   string            m_dayKey;
   string            m_keys[];
   int               m_keepDays;

   string            Name(const string id) { return(ICTNAS_PREFIX+m_dayKey+"_"+id); }
   void              Common(const string n,color c,bool back)
     {
      ObjectSetInteger(0,n,OBJPROP_COLOR,c);
      ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,n,OBJPROP_BACK,back);
     }

public:
   void              Init(bool on,int keepDays)
     {
      bool fastTester=(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE));
      m_on=on && !fastTester;
      m_keepDays=MathMax(1,keepDays);
      ArrayResize(m_keys,0);
     }
   bool              On(void) { return(m_on); }

   void              NewDay(datetime anchorNY)
     {
      m_dayKey=TimeToString(anchorNY,TIME_DATE);
      StringReplace(m_dayKey,".","");
      if(!m_on) return;
      int n=ArraySize(m_keys);
      ArrayResize(m_keys,n+1);
      m_keys[n]=m_dayKey;
      while(ArraySize(m_keys)>m_keepDays)
        {
         ObjectsDeleteAll(0,ICTNAS_PREFIX+m_keys[0]+"_");
         int k=ArraySize(m_keys);
         for(int i=0;i<k-1;i++) m_keys[i]=m_keys[i+1];
         ArrayResize(m_keys,k-1);
        }
     }

   void              Seg(const string id,datetime t1,datetime t2,double p,color c,
                         ENUM_LINE_STYLE st=STYLE_SOLID,int w=1,const string txt="",const string tip="")
     {
      if(!m_on || p<=0 || t2<=t1) return;
      string n=Name(id);
      if(ObjectFind(0,n)<0)
        {
         ObjectCreate(0,n,OBJ_TREND,0,t1,p,t2,p);
         ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false);
        }
      else
        {
         ObjectMove(0,n,0,t1,p);
         ObjectMove(0,n,1,t2,p);
        }
      Common(n,c,true);
      ObjectSetInteger(0,n,OBJPROP_STYLE,st);
      ObjectSetInteger(0,n,OBJPROP_WIDTH,w);
      ObjectSetString(0,n,OBJPROP_TOOLTIP,(tip!="")?tip:(txt!=""?txt:id)+" "+PxStr(p));
      if(txt!="") Text(id+"_t",t1,p,txt,c);
     }

   void              Box(const string id,datetime t1,datetime t2,double p1,double p2,color c,
                         bool fill,const string txt="")
     {
      if(!m_on || p1<=0 || p2<=0 || t2<=t1) return;
      string n=Name(id);
      if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_RECTANGLE,0,t1,p1,t2,p2);
      else
        {
         ObjectMove(0,n,0,t1,p1);
         ObjectMove(0,n,1,t2,p2);
        }
      Common(n,c,true);
      ObjectSetInteger(0,n,OBJPROP_FILL,fill);
      ObjectSetString(0,n,OBJPROP_TOOLTIP,txt);
      if(txt!="") Text(id+"_t",t1,MathMax(p1,p2),txt,c);
     }

   void              VLine(const string id,datetime t,color c,const string txt="")
     {
      if(!m_on || t<=0) return;
      string n=Name(id);
      if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_VLINE,0,t,0);
      else ObjectMove(0,n,0,t,0);
      Common(n,c,true);
      ObjectSetInteger(0,n,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetString(0,n,OBJPROP_TOOLTIP,txt);
     }

   void              Text(const string id,datetime t,double p,const string txt,color c,int size=7)
     {
      if(!m_on || p<=0) return;
      string n=Name(id);
      if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_TEXT,0,t,p);
      else ObjectMove(0,n,0,t,p);
      Common(n,c,false);
      ObjectSetString(0,n,OBJPROP_TEXT,txt);
      ObjectSetString(0,n,OBJPROP_FONT,"Arial");
      ObjectSetInteger(0,n,OBJPROP_FONTSIZE,size);
      ObjectSetInteger(0,n,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);
     }

   void              DeleteAll(void) { ObjectsDeleteAll(0,ICTNAS_PREFIX); }
  };

//+------------------------------------------------------------------+
//| Panneau texte (labels, police à chasse fixe)                     |
//+------------------------------------------------------------------+
class CPanel
  {
private:
   bool              m_on;
   int               m_lines;
   string            Name(int i) { return(ICTNAS_PREFIX+"PNL_"+IntegerToString(i)); }

public:
   void              Init(bool on)
     {
      bool fastTester=(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE));
      m_on=on && !fastTester;
      m_lines=0;
     }
   bool              On(void) { return(m_on); }

   //--- Les labels MT5 sont limités à 63 caractères : on coupe les lignes longues
   void              Show(string &src[])
     {
      if(!m_on) return;
      string lines[];
      for(int i=0;i<ArraySize(src);i++)
        {
         string s=src[i];
         bool first=true;
         do
           {
            int k=ArraySize(lines);
            ArrayResize(lines,k+1);
            int take=first?62:60;
            lines[k]=(first?"":"  ")+StringSubstr(s,0,take);
            s=(StringLen(s)>take)?StringSubstr(s,take):"";
            first=false;
           }
         while(s!="");
        }
      int n=ArraySize(lines);
      string bg=ICTNAS_PREFIX+"PNL_BG";
      if(ObjectFind(0,bg)<0)
        {
         ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
         ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,6);
         ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,18);
         ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,C'18,22,30');
         ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
         ObjectSetInteger(0,bg,OBJPROP_COLOR,C'60,70,90');
         ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);
        }
      ObjectSetInteger(0,bg,OBJPROP_XSIZE,430);
      ObjectSetInteger(0,bg,OBJPROP_YSIZE,n*14+10);
      for(int i=0;i<n;i++)
        {
         string nm=Name(i);
         if(ObjectFind(0,nm)<0)
           {
            ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
            ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_LEFT_UPPER);
            ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,12);
            ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,22+i*14);
            ObjectSetString(0,nm,OBJPROP_FONT,"Consolas");
            ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,8);
            ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
            ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
           }
         ObjectSetInteger(0,nm,OBJPROP_COLOR,(i==0)?clrGold:C'210,215,225');
         ObjectSetString(0,nm,OBJPROP_TEXT,lines[i]);
        }
      for(int i=n;i<m_lines;i++) ObjectDelete(0,Name(i));
      m_lines=n;
     }
  };

#endif
//+------------------------------------------------------------------+
//=== fin Drawer.mqh ===
//=== début Structure.mqh ===
//+------------------------------------------------------------------+
//|                                                   Structure.mqh  |
//|  Outils de structure ICT sur n'importe quelle unité de temps :   |
//|  ATR, bougies "miroir" (une seule logique pour long et short),   |
//|  FVG, swings, CISD. Les tableaux de barres sont chronologiques    |
//|  (index 0 = la plus ancienne).                                   |
//+------------------------------------------------------------------+
#ifndef ICTNAS_STRUCTURE_MQH
#define ICTNAS_STRUCTURE_MQH

//--- Zone FVG (prix réels, non miroir)
struct SFVG
  {
   bool              valid;
   int               dir;         // -1 baissier (vendeur), +1 haussier (acheteur)
   double            top;
   double            bottom;
   datetime          t1;          // bougie 1 du motif
   datetime          t3;          // bougie 3 du motif
   void              Clear(void)  { valid=false; dir=0; top=0; bottom=0; t1=0; t3=0; }
   double            CE(void)     { return((top+bottom)/2.0); }
   double            Size(void)   { return(top-bottom); }
  };

//--- ATR par unité de temps (handles partagés)
class CATRBank
  {
private:
   string            m_sym;
   int               m_h[5];
   ENUM_TIMEFRAMES   m_tf[5];
   int               Idx(ENUM_TIMEFRAMES tf)
     {
      for(int i=0;i<5;i++) if(m_tf[i]==tf) return(i);
      return(-1);
     }
public:
   void              Init(const string sym)
     {
      m_sym=sym;
      m_tf[0]=PERIOD_M1; m_tf[1]=PERIOD_M5; m_tf[2]=PERIOD_M15; m_tf[3]=PERIOD_H1; m_tf[4]=PERIOD_M3;
      for(int i=0;i<5;i++) m_h[i]=iATR(sym,m_tf[i],14);
     }
   void              Deinit(void) { for(int i=0;i<5;i++) if(m_h[i]!=INVALID_HANDLE) IndicatorRelease(m_h[i]); }
   //--- ATR de la dernière barre clôturée
   double            Get(ENUM_TIMEFRAMES tf)
     {
      int i=Idx(tf);
      if(i<0 || m_h[i]==INVALID_HANDLE) return(0.0);
      double b[];
      if(CopyBuffer(m_h[i],0,1,1,b)!=1) return(0.0);
      return(b[0]);
     }
  };

//--- Miroir : pour un LONG on inverse les prix ; toute la logique est écrite pour un SHORT
//--- (sweep d'un plus haut -> cassure vers le bas). dir=-1 : inchangé ; dir=+1 : miroir.
void MirrorRates(MqlRates &r[],int dir)
  {
   if(dir!=1) return;
   for(int i=0;i<ArraySize(r);i++)
     {
      double h=r[i].high,l=r[i].low;
      r[i].high=-l;
      r[i].low=-h;
      r[i].open=-r[i].open;
      r[i].close=-r[i].close;
     }
  }
double Unmirror(double p,int dir) { return(dir==1 ? -p : p); }

//--- Barres chronologiques entre deux heures (incluses) sur une UT
int GetBars(const string sym,ENUM_TIMEFRAMES tf,datetime from,datetime to,MqlRates &r[])
  {
   ArrayResize(r,0);
   if(to<from) return(0);
   int n=CopyRates(sym,tf,from,to,r);
   return(n<0?0:n);
  }

//--- Index de la barre à l'heure t (ou la dernière avant), -1 si absente
int IndexOfTime(MqlRates &r[],datetime t)
  {
   for(int i=ArraySize(r)-1;i>=0;i--) if(r[i].time<=t) return(i);
   return(-1);
  }

//--- Espace miroir (logique short) : FVG baissier = low[i-2] > high[i]
//--- Renvoie le FVG le plus récent entre les index [from ; to] (bougie 3), non comblé
//--- jusqu'à lastIdx (aucune barre après la bougie 3 n'a atteint le CE).
bool FindBearFVG(MqlRates &r[],int from,int to,int lastIdx,double minSize,
                 double &top,double &bottom,int &i1,int &i3)
  {
   for(int i=MathMin(to,ArraySize(r)-1);i>=MathMax(from,2);i--)
     {
      double t=r[i-2].low,b=r[i].high;
      if(t-b<minSize) continue;
      double ce=(t+b)/2.0;
      bool filled=false;
      for(int k=i+1;k<=lastIdx && k<ArraySize(r);k++)
         if(r[k].high>=ce) { filled=true; break; }
      if(filled) continue;
      top=t; bottom=b; i1=i-2; i3=i;
      return(true);
     }
   return(false);
  }

//--- Espace miroir : FVG haussier (pour détecter une IFVG cassée à la baisse)
bool FindBullFVGBrokenBy(MqlRates &r[],int from,int to,double closePx)
  {
   for(int i=MathMin(to,ArraySize(r)-1);i>=MathMax(from,2);i--)
     {
      double b=r[i-2].high,t=r[i].low;   // zone haussière [b ; t]
      if(t>b && closePx<b) return(true);
     }
   return(false);
  }

//--- Espace miroir : dernier plus bas fractal (1 bougie de chaque côté) strictement avant idx
int LastFractalLow(MqlRates &r[],int beforeIdx,int lookback)
  {
   int stop=MathMax(1,beforeIdx-lookback);
   for(int i=beforeIdx-1;i>=stop;i--)
     {
      if(i+1>=ArraySize(r)) continue;
      if(r[i].low<r[i-1].low && r[i].low<r[i+1].low) return(i);
     }
   return(-1);
  }

//--- Espace miroir : niveau CISD = ouverture de la première bougie de la série haussière
//--- qui a livré le prix jusqu'à l'extrême (idx). -1 si aucune série.
int CISDSeriesStart(MqlRates &r[],int extremeIdx)
  {
   int i=extremeIdx;
   if(i<0) return(-1);
   if(r[i].close<=r[i].open) i--;              // l'extrême peut être une mèche sur bougie baissière
   if(i<0 || r[i].close<=r[i].open) return(-1);
   while(i-1>=0 && r[i-1].close>r[i-1].open) i--;
   return(i);
  }

//--- Espace miroir : dernière bougie baissière avant la série haussière (OB haussier -> breaker)
int BullishOBBefore(MqlRates &r[],int seriesStart)
  {
   for(int i=seriesStart-1;i>=MathMax(0,seriesStart-5);i--)
      if(r[i].close<r[i].open) return(i);
   return(-1);
  }

#endif
//+------------------------------------------------------------------+
//=== fin Structure.mqh ===
//=== début SetupEngine.mqh ===
//+------------------------------------------------------------------+
//|                                                 SetupEngine.mqh  |
//|  Séquence ICT : Liquidity Sweep -> MSS ou CISD -> Displacement   |
//|  -> FVG -> (entrée au CE : gérée par le routeur de modèles).     |
//|                                                                  |
//|  Déclencheurs :                                                  |
//|   - un niveau de la carte de liquidité est pris (UT d'exécution) |
//|   - ERL H1 : une bougie H1 prend le plus haut/bas des N bougies  |
//|     précédentes puis clôture à l'intérieur -> MSS cherché en M5  |
//|  La logique est écrite une fois (cas SHORT) et appliquée au LONG |
//|  via des bougies "miroir".                                       |
//+------------------------------------------------------------------+
#ifndef ICTNAS_SETUPENGINE_MQH
#define ICTNAS_SETUPENGINE_MQH

#define LIQ_ERL_H1 100

//--- Candidat ICT complet (prix réels)
struct SSetup
  {
   bool              valid;
   int               dir;              // +1 long, -1 short
   ENUM_TIMEFRAMES   tf;
   bool              erl;              // déclenché par un sweep ERL H1
   bool              momentum;         // signal "Silver Bullet momentum" (logique de l'EA v6)
   string            liqName;
   int               liqType;
   int               liqWeight;
   double            liqPrice;
   datetime          tLevel;           // formation du niveau pris
   datetime          tSweep;
   double            extreme;          // extrême du sweep (invalidation)
   datetime          tExtreme;
   datetime          tTrigger;         // bougie de MSS / CISD
   bool              mss;
   bool              cisd;
   bool              displacement;
   double            dispBodyATR;
   int               dispCandles;
   double            dispSize;
   bool              ifvg;
   bool              breaker;
   bool              unicorn;
   bool              orderBlock;
   double            fvgTop;
   double            fvgBottom;
   datetime          fvgT1;
   double            fvgC1Ext;         // extrême de la bougie 1 du FVG côté SL (SL ICT alternatif)
   double            legEnd;           // extrême opposé de la jambe de displacement
   int               smt;              // -1 inconnu, 0 non, 1 oui
   double            CE(void) { return((fvgTop+fvgBottom)/2.0); }
  };

struct SHunt
  {
   bool              active;
   int               dir;
   ENUM_TIMEFRAMES   tf;
   bool              erl;
   string            liqName;
   int               liqType;
   int               liqWeight;
   double            liqPrice;
   datetime          tLevel;
   datetime          tSweep;
   int               maxBars;
  };

class CSetupEngine
  {
public:
   //--- diagnostic : où les séquences s'arrêtent (cumul depuis le lancement)
   int               nSweeps,nERL,nTimeout,nNoDisp,nNoFVG,nEmitted;

private:
   string            m_sym;
   CLiquidityEngine *m_liq;
   CSMTCheck        *m_smt;
   CATRBank         *m_atr;
   ENUM_TIMEFRAMES   m_execTF;
   double            m_minFVG;          // points d'indice
   double            m_dispMult;
   bool              m_needDisp;
   int               m_maxBars;
   int               m_erlLookback;
   bool              m_useERL;
   SHunt             m_h[];
   SSetup            m_out[];

   void              Emit(SSetup &s)
     {
      int n=ArraySize(m_out);
      ArrayResize(m_out,n+1);
      m_out[n]=s;
     }

   //--- Ajoute une chasse ; fusionne avec une chasse proche dans le même sens
   void              AddHunt(int dir,ENUM_TIMEFRAMES tf,bool erl,const string name,int type,int weight,
                             double price,datetime tLevel,datetime tSweep,int maxBars)
     {
      for(int i=0;i<ArraySize(m_h);i++)
        {
         if(!m_h[i].active || m_h[i].dir!=dir || m_h[i].tf!=tf || m_h[i].erl!=erl) continue;
         if(tSweep-m_h[i].tSweep<=15*SEC_MIN)
           {
            if(weight>m_h[i].liqWeight)
              {
               m_h[i].liqName=name; m_h[i].liqType=type; m_h[i].liqWeight=weight;
               m_h[i].liqPrice=price; m_h[i].tLevel=tLevel;
              }
            return;
           }
        }
      int k=-1;
      for(int i=0;i<ArraySize(m_h);i++) if(!m_h[i].active) { k=i; break; }
      if(k<0)
        {
         if(ArraySize(m_h)>=12) return;
         k=ArraySize(m_h);
         ArrayResize(m_h,k+1);
        }
      m_h[k].active=true; m_h[k].dir=dir; m_h[k].tf=tf; m_h[k].erl=erl;
      m_h[k].liqName=name; m_h[k].liqType=type; m_h[k].liqWeight=weight;
      m_h[k].liqPrice=price; m_h[k].tLevel=tLevel; m_h[k].tSweep=tSweep; m_h[k].maxBars=maxBars;
     }

   //--- Évalue une chasse sur les barres clôturées (sans état : tout est recalculé)
   void              Evaluate(SHunt &h)
     {
      int ps=PeriodSeconds(h.tf);
      datetime lastClosed=iTime(m_sym,h.tf,1);
      if(lastClosed<=0) return;
      MqlRates r[];
      int n=GetBars(m_sym,h.tf,h.tSweep-40*ps,lastClosed,r);
      if(n<5) return;
      int sw=IndexOfTime(r,h.tSweep);
      if(sw<0) return;
      if(n-1-sw>h.maxBars) { h.active=false; nTimeout++; return; }
      MirrorRates(r,h.dir==1?1:-1);
      //--- extrême (espace miroir : plus haut) depuis la bougie du sweep
      int ex=sw;
      for(int i=sw+1;i<n;i++) if(r[i].high>r[ex].high) ex=i;
      if(ex>=n-1) return;                                   // l'extrême est en cours de formation
      int swIdx=LastFractalLow(r,ex,30);
      int cs=CISDSeriesStart(r,ex);
      double mssLvl=(swIdx>=0)?r[swIdx].low:-DBL_MAX;
      double cisdLvl=(cs>=0)?r[cs].open:-DBL_MAX;
      int j=-1;
      for(int i=ex+1;i<n;i++)
         if((swIdx>=0 && r[i].close<mssLvl) || (cs>=0 && r[i].close<cisdLvl)) { j=i; break; }
      if(j<0) return;
      //--- displacement
      double atr=m_atr.Get(h.tf);
      double maxBody=0;
      for(int i=ex;i<=j;i++) maxBody=MathMax(maxBody,r[i].open-r[i].close);
      int dc=0;
      for(int i=j;i>ex && r[i].close<r[i].open;i--) dc++;
      bool disp=(atr>0 && maxBody>=m_dispMult*atr);
      if(m_needDisp && !disp)
        {
         if(n-1>j+3) { h.active=false; nNoDisp++; }         // cassure sans displacement : abandon
         return;
        }
      //--- FVG créé par le displacement (3 bougies max après la cassure)
      double top,bot;
      int i1,i3;
      int to=MathMin(j+3,n-1);
      if(!FindBearFVG(r,ex+1,to,n-1,m_minFVG,top,bot,i1,i3))
        {
         if(n-1>=j+3) { h.active=false; nNoFVG++; }
         return;
        }
      //--- candidat
      SSetup s;
      s.valid=true;
      s.dir=h.dir;
      s.tf=h.tf;
      s.erl=h.erl;
      s.momentum=false;
      s.liqName=h.liqName; s.liqType=h.liqType; s.liqWeight=h.liqWeight;
      s.liqPrice=h.liqPrice; s.tLevel=h.tLevel; s.tSweep=h.tSweep;
      s.extreme=Unmirror(r[ex].high,h.dir==1?1:-1);
      s.tExtreme=r[ex].time;
      s.tTrigger=r[j].time;
      s.mss=(swIdx>=0 && r[j].close<mssLvl);
      s.cisd=(cs>=0 && r[j].close<cisdLvl);
      s.displacement=disp;
      s.dispBodyATR=(atr>0)?maxBody/atr:0;
      s.dispCandles=dc;
      s.dispSize=r[ex].high-r[j].close;
      double a=Unmirror(top,h.dir==1?1:-1),b=Unmirror(bot,h.dir==1?1:-1);
      s.fvgTop=MathMax(a,b);
      s.fvgBottom=MathMin(a,b);
      s.fvgT1=r[i1].time;
      s.fvgC1Ext=Unmirror(r[i1].high,h.dir==1?1:-1);
      double leg=r[ex].low;
      for(int i=ex;i<n;i++) leg=MathMin(leg,r[i].low);
      s.legEnd=Unmirror(leg,h.dir==1?1:-1);
      s.ifvg=FindBullFVGBrokenBy(r,MathMax(2,ex-30),ex,r[j].close);
      s.orderBlock=(cs>=0);
      s.breaker=false; s.unicorn=false;
      if(cs>=0)
        {
         int ob=BullishOBBefore(r,cs);
         if(ob>=0 && r[j].close<r[ob].low)
           {
            s.breaker=true;
            double obTop=r[ob].high,obBot=r[ob].low;       // espace miroir
            s.unicorn=(obBot<=top && obTop>=bot);
           }
        }
      s.smt=m_smt.Divergence(h.dir==-1,h.tLevel,s.tTrigger);
      Emit(s);
      nEmitted++;
      h.active=false;
     }

public:
   void              Init(const string sym,CLiquidityEngine *liq,CSMTCheck *smt,CATRBank *atr,
                          ENUM_TIMEFRAMES execTF,double minFVG,double dispMult,bool needDisp,
                          int maxBars,bool useERL,int erlLookback)
     {
      m_sym=sym; m_liq=liq; m_smt=smt; m_atr=atr;
      m_execTF=execTF; m_minFVG=minFVG; m_dispMult=dispMult; m_needDisp=needDisp;
      m_maxBars=maxBars; m_useERL=useERL; m_erlLookback=MathMax(3,erlLookback);
      ArrayResize(m_h,0);
      ArrayResize(m_out,0);
      nSweeps=0; nERL=0; nTimeout=0; nNoDisp=0; nNoFVG=0; nEmitted=0;
     }

   void              NewDay(void) { ArrayResize(m_h,0); ArrayResize(m_out,0); }

   //--- Sweeps de la carte de liquidité -> nouvelles chasses (appelé à chaque tick)
   void              OnSweeps(void)
     {
      int ev[];
      int n=m_liq.PopSweeps(ev);
      for(int i=0;i<n;i++)
        {
         SLiqLevel l=m_liq.lv[ev[i]];
         nSweeps++;
         AddHunt(l.buySide?-1:1,m_execTF,false,l.name,l.type,l.weight,l.price,l.tFormed,l.tSwept,m_maxBars);
        }
     }

   //--- ERL H1 : bougie H1 qui prend l'extrême des N précédentes et clôture à l'intérieur
   void              OnNewH1(void)
     {
      if(!m_useERL) return;
      MqlRates r[];
      ArraySetAsSeries(r,true);
      int need=m_erlLookback+2;
      if(CopyRates(m_sym,PERIOD_H1,1,need,r)<need) return;
      double hi=r[1].high,lo=r[1].low;
      datetime th=r[1].time,tl=r[1].time;
      for(int i=2;i<need;i++)
        {
         if(r[i].high>hi) { hi=r[i].high; th=r[i].time; }
         if(r[i].low <lo) { lo=r[i].low;  tl=r[i].time; }
        }
      if(r[0].high>hi && r[0].close<hi) nERL++;
      if(r[0].low<lo && r[0].close>lo)  nERL++;
      if(r[0].high>hi && r[0].close<hi)
         AddHunt(-1,PERIOD_M5,true,"ERL H1 haut",LIQ_ERL_H1,6,hi,th,r[0].time,24);
      if(r[0].low<lo && r[0].close>lo)
         AddHunt(1,PERIOD_M5,true,"ERL H1 bas",LIQ_ERL_H1,6,lo,tl,r[0].time,24);
     }

   //--- À chaque nouvelle barre d'une UT : évaluation des chasses de cette UT
   void              OnNewBar(ENUM_TIMEFRAMES tf)
     {
      for(int i=0;i<ArraySize(m_h);i++)
         if(m_h[i].active && m_h[i].tf==tf) Evaluate(m_h[i]);
     }

   //--- Ajout d'un candidat construit ailleurs (modèle momentum)
   void              Inject(SSetup &s) { Emit(s); nEmitted++; }

   int               PopSetups(SSetup &out[])
     {
      int n=ArraySize(m_out);
      ArrayResize(out,n);
      for(int i=0;i<n;i++) out[i]=m_out[i];
      ArrayResize(m_out,0);
      return(n);
     }

   int               ActiveHunts(void)
     {
      int c=0;
      for(int i=0;i<ArraySize(m_h);i++) if(m_h[i].active) c++;
      return(c);
     }

   //--- IRL : FVG H1 non comblé le plus proche dans le sens du trade (cible ERL -> IRL)
   //--- dir=-1 (short) : FVG haussier sous le prix ; renvoie son bord le plus proche et son CE
   bool              FindIRL(int dir,double px,double &edge,double &ce)
     {
      MqlRates r[];
      int n=CopyRates(m_sym,PERIOD_H1,1,60,r);   // chronologique
      if(n<5) return(false);
      double best=DBL_MAX;
      bool found=false;
      for(int i=2;i<n;i++)
        {
         double zb,zt;
         if(dir==-1) { zb=r[i-2].high; zt=r[i].low;  if(zt<=zb) continue; }   // FVG haussier
         else        { zt=r[i-2].low;  zb=r[i].high; if(zt<=zb) continue; }   // FVG baissier
         bool filled=false;
         for(int k=i+1;k<n;k++)
           {
            if(dir==-1 && r[k].low<=zb)  { filled=true; break; }
            if(dir==1  && r[k].high>=zt) { filled=true; break; }
           }
         if(filled) continue;
         double e=(dir==-1)?zt:zb;
         double d=(dir==-1)?px-e:e-px;
         if(d>0 && d<best) { best=d; edge=e; ce=(zt+zb)/2.0; found=true; }
        }
      return(found);
     }
  };

#endif
//+------------------------------------------------------------------+
//=== fin SetupEngine.mqh ===
//=== début SignalLogger.mqh ===
//+------------------------------------------------------------------+
//|                                                SignalLogger.mqh  |
//|  Un enregistrement par setup ICT valide, PRIS OU REJETÉ.         |
//|  Chaque signal est suivi virtuellement (ordre limite au CE, SL,  |
//|  TP1 50 % / TP2 25 % / TP3 25 %, BE après TP1, sortie à l'heure  |
//|  de flat) : le résultat est connu même pour les setups non pris, |
//|  ce qui évite le biais de sélection dans l'apprentissage.        |
//|  Convention prudente : si SL et TP sont touchés dans la même     |
//|  bougie M1, le SL est compté en premier.                         |
//+------------------------------------------------------------------+
#ifndef ICTNAS_SIGNALLOGGER_MQH
#define ICTNAS_SIGNALLOGGER_MQH

struct SSignal
  {
   string            uid;
   string            model;
   int               dir;
   datetime          tSrv;            // heure serveur de la validation du setup
   datetime          tNY;
   //--- temps
   int               dow,month,hour,minute,dayQ,q90,q22,shadowActive;
   string            session,killzone,sbWindow,macro;
   //--- liquidité / structure
   string            liqType;
   int               liqWeight;
   double            liqPrice;
   datetime          tSweep;
   datetime          tSweepNY;
   int               mss,cisd,disp,dispCandles,unicorn,breaker,ob,ifvg;
   double            dispBodyATR,dispSize,atr1,atr5,atr15;
   string            fvgType;
   double            fvgSize,fvgCE,fvgTop,fvgBot;
   datetime          tFVG;
   //--- plan
   double            entry,sl,tp1,tp2,tp3,riskPts,planRR;
   double            w1,w2,w3;
   bool              market;          // entrée au marché (sinon ordre limite)
   double            beTrigger;       // prix qui déclenche le passage au break-even (1R)
   double            inval;           // règle des 50 % : clôture au-delà du CE = invalidation (0 = aucune)
   bool              beDone;
   //--- contexte
   string            pdLabel,weeklyProfile,amdx;
   double            pdPct,stdvReached;
   int               ote,smt,qAlign,weeklyBias,gapBias,trendDay,newsWin;
   double            spread,dayRange,asiaRange,londonRange,nyRange,dDaily,dWeekly,dMonthly,dMidnight;
   //--- décision
   double            score,mlProb;
   string            mlModel,decision,reason;
   bool              taken;
   //--- simulation
   datetime          expirySrv,flatSrv;
   bool              filled,done;
   datetime          tFill,tExit;
   double            rReal,remaining,curSL,mfe,mae,bePts;
   bool              tp1Hit,tp2Hit,tp3Hit;
   string            outcome;
   //--- v2.30
   double            cancelPx;        // cible atteinte avant l'entrée -> ordre annulé (0 = TP1)
   double            chaseR;          // entrée au marché tolérée au-delà du niveau (x R, 0 = règle v2.22)
   bool              fixedUid;        // identifiant déterministe (London OPR PDF : pas de doublon après redémarrage)
   long              extId;           // setup du moteur London OPR (0 = aucun)
   int               slot;            // OPR du moteur London (-1 = aucun)
   //--- v2.40
   string            extKey;          // fenêtre / macro v6.20 du signal ("" = aucune) : 1 trade par fenêtre
   //--- v2.50
   bool              adaptOk;         // plan conforme aux règles du modèle (filtres, RR, score, ML passés) : compte dans l'apprentissage
  };

//--- Répartition des sorties selon que les TP sont distincts ou non
void SetExitWeights(SSignal &s)
  {
   double tick=_Point;
   bool same12=MathAbs(s.tp1-s.tp2)<tick,same23=MathAbs(s.tp2-s.tp3)<tick;
   if(same12 && same23) { s.w1=1.0;  s.w2=0.0;  s.w3=0.0;  }
   else if(same23)      { s.w1=0.5;  s.w2=0.5;  s.w3=0.0;  }
   else if(same12)      { s.w1=0.75; s.w2=0.0;  s.w3=0.25; }
   else                 { s.w1=0.5;  s.w2=0.25; s.w3=0.25; }
  }

class CSignalLogger
  {
private:
   CDataCollector   *m_db;
   string            m_sym;
   SSignal           m_open[];        // signaux en cours de suivi virtuel
   int               m_written;
   //--- v2.50 : apprentissage par bucket « modèle|session » (règle de la v6.20), alimenté par le
   //---         résultat virtuel de CHAQUE setup exécuté virtuellement (pris ou rejeté)
   string            m_aKey[];
   int               m_aN[];
   double            m_aSum[];
   double            m_aSum2[];

   int               AdaptFind(const string k)
     {
      for(int i=0;i<ArraySize(m_aKey);i++) if(m_aKey[i]==k) return(i);
      return(-1);
     }
   void              AdaptAdd(SSignal &s)
     {
      if(!s.adaptOk || !s.filled || (s.outcome!="WIN" && s.outcome!="LOSS" && s.outcome!="BE")) return;
      string k=s.model+"|"+s.session;
      int i=AdaptFind(k);
      if(i<0)
        {
         i=ArraySize(m_aKey);
         ArrayResize(m_aKey,i+1); ArrayResize(m_aN,i+1); ArrayResize(m_aSum,i+1); ArrayResize(m_aSum2,i+1);
         m_aKey[i]=k; m_aN[i]=0; m_aSum[i]=0.0; m_aSum2[i]=0.0;
        }
      m_aN[i]++;
      m_aSum[i]+=s.rReal;
      m_aSum2[i]+=s.rReal*s.rReal;
     }

   static string     NYStr(datetime ny)
     {
      if(ny<=0) return("");
      string s=TimeToString(ny,TIME_DATE|TIME_MINUTES);
      StringReplace(s,".","-");
      return(s);
     }
   void              Close(SSignal &s,datetime t)
     {
      s.done=true;
      s.tExit=t;
      if(!s.filled) { s.outcome="NOFILL"; return; }
      if(s.rReal>0.05)       s.outcome="WIN";
      else if(s.rReal<-0.05) s.outcome="LOSS";
      else                   s.outcome="BE";
     }

   //--- Une bougie M1 clôturée
   void              Step(SSignal &s,const MqlRates &b)
     {
      if(s.done || b.time<s.tSrv) return;
      int d=s.dir;
      double fav=(d==1)?b.high:b.low;
      double adv=(d==1)?b.low:b.high;
      if(!s.filled)
        {
         if(b.time>=s.expirySrv) { Close(s,b.time); return; }
         if(d*(adv-s.entry)<=0)
           {
            s.filled=true;
            s.tFill=b.time;
            if(d*(adv-s.sl)<=0) { s.rReal=-1.0; s.remaining=0; s.mae=1.0; Close(s,b.time); }
            return;
           }
         double cx=(s.cancelPx>0)?s.cancelPx:s.tp1;
         if(d*(fav-cx)>=0) { Close(s,b.time); return; }      // cible atteinte sans retracement
         return;
        }
      double r=s.riskPts;
      if(r<=0) { Close(s,b.time); return; }
      s.mfe=MathMax(s.mfe,d*(fav-s.entry)/r);
      s.mae=MathMax(s.mae,-d*(adv-s.entry)/r);
      if(d*(adv-s.curSL)<=0)
        {
         s.rReal+=s.remaining*d*(s.curSL-s.entry)/r;
         s.remaining=0;
         Close(s,b.time);
         return;
        }
      //--- règle des 50 % du FVG : clôture au-delà du CE -> sortie
      if(s.inval>0 && d*(b.close-s.inval)<0)
        {
         s.rReal+=s.remaining*d*(b.close-s.entry)/r;
         s.remaining=0;
         Close(s,b.time);
         return;
        }
      //--- break-even à 1R
      if(!s.beDone && s.beTrigger>0 && d*(fav-s.beTrigger)>=0)
        {
         s.beDone=true;
         double be=s.entry+d*s.bePts;
         if(d*(be-s.curSL)>0) s.curSL=be;
        }
      if(!s.tp1Hit && d*(fav-s.tp1)>=0)
        {
         s.tp1Hit=true;
         s.rReal+=s.w1*d*(s.tp1-s.entry)/r;
         s.remaining-=s.w1;
         double be=s.entry+d*s.bePts;
         if(d*(be-s.curSL)>0) s.curSL=be;
        }
      if(s.w2>0 && !s.tp2Hit && d*(fav-s.tp2)>=0)
        {
         s.tp2Hit=true;
         s.rReal+=s.w2*d*(s.tp2-s.entry)/r;
         s.remaining-=s.w2;
        }
      if(s.w3>0 && !s.tp3Hit && d*(fav-s.tp3)>=0)
        {
         s.tp3Hit=true;
         s.rReal+=s.w3*d*(s.tp3-s.entry)/r;
         s.remaining-=s.w3;
        }
      if(s.remaining<=1e-9) { s.remaining=0; Close(s,b.time); return; }
      if(b.time>=s.flatSrv)
        {
         s.rReal+=s.remaining*d*(b.close-s.entry)/r;
         s.remaining=0;
         Close(s,b.time);
        }
     }

public:
   void              Init(CDataCollector *db,const string sym)
     {
      m_db=db; m_sym=sym; m_written=0; ArrayResize(m_open,0);
      ArrayResize(m_aKey,0); ArrayResize(m_aN,0); ArrayResize(m_aSum,0); ArrayResize(m_aSum2,0);
     }

   //--- v2.50 : règle ADAPT_SIZE_AND_GATE de la v6.20 : bucket bloqué si n >= minimum
   //---         et E[R] + 1 erreur standard < 0 (perte démontrée, pas un simple mauvais passage)
   bool              AdaptBucketBlocked(int i,int minSamples,double &mean,double &se)
     {
      mean=0; se=0;
      if(i<0 || i>=ArraySize(m_aKey) || m_aN[i]<MathMax(minSamples,5)) return(false);
      double n=(double)m_aN[i];
      mean=m_aSum[i]/n;
      double var=MathMax(0.0,m_aSum2[i]/n-mean*mean);
      se=MathSqrt(var/n);
      return(mean+se<0);
     }
   bool              AdaptBlocked(SSignal &s,int minSamples,string &why)
     {
      why="";
      double mean,se;
      int i=AdaptFind(s.model+"|"+s.session);
      if(!AdaptBucketBlocked(i,minSamples,mean,se)) return(false);
      why="adaptatif : "+m_aKey[i]+" E[R]="+DoubleToString(mean,2)+" +/- "+DoubleToString(se,2)+" sur "+IntegerToString(m_aN[i])+" setups";
      return(true);
     }
   //--- v2.50 : diagnostic, une ligne par bucket ayant assez de setups résolus ("" sinon)
   int               AdaptCount(void) { return(ArraySize(m_aKey)); }
   string            AdaptLine(int i,int minSamples)
     {
      if(i<0 || i>=ArraySize(m_aKey) || m_aN[i]<MathMax(minSamples,5)) return("");
      double mean,se;
      bool neg=AdaptBucketBlocked(i,minSamples,mean,se);
      string l=m_aKey[i]+" : n="+IntegerToString(m_aN[i])+" E[R]="+DoubleToString(mean,2)+" +/- "+DoubleToString(se,2);
      if(neg) l+=" -> ESPERANCE NEGATIVE DEMONTREE";
      return(l);
     }
   int               Written(void) { return(m_written); }
   int               Tracking(void) { return(ArraySize(m_open)); }

   void              Add(SSignal &s)
     {
      s.filled=false; s.done=false; s.tFill=0; s.tExit=0;
      s.rReal=0; s.remaining=1.0; s.curSL=s.sl; s.mfe=0; s.mae=0;
      s.tp1Hit=false; s.tp2Hit=false; s.tp3Hit=false; s.outcome=""; s.beDone=false;
      SetExitWeights(s);
      if(s.market) { s.filled=true; s.tFill=s.tSrv; }     // entrée au marché : remplie immédiatement
      int n=ArraySize(m_open);
      ArrayResize(m_open,n+1);
      m_open[n]=s;
     }

   //--- À chaque nouvelle barre M1 : avance les simulations, écrit les signaux terminés
   void              OnNewBar(void)
     {
      if(ArraySize(m_open)==0) return;
      MqlRates b[];
      if(CopyRates(m_sym,PERIOD_M1,1,1,b)!=1) return;
      for(int i=ArraySize(m_open)-1;i>=0;i--)
        {
         Step(m_open[i],b[0]);
         if(m_open[i].done)
           {
            AdaptAdd(m_open[i]);              // v2.50
            Write(m_open[i]);
            int n=ArraySize(m_open);
            for(int k=i;k<n-1;k++) m_open[k]=m_open[k+1];
            ArrayResize(m_open,n-1);
           }
        }
     }

   //--- Fin de programme : écrit les signaux encore ouverts (outcome OPEN)
   void              Flush(void)
     {
      for(int i=0;i<ArraySize(m_open);i++)
        {
         m_open[i].outcome="OPEN";
         Write(m_open[i]);
        }
      ArrayResize(m_open,0);
     }

   //--- v2.30 : signal annulé avant exécution (ex. setup London OPR abandonné par le moteur)
   void              CancelPending(const string uid,datetime t)
     {
      for(int i=0;i<ArraySize(m_open);i++)
         if(m_open[i].uid==uid && !m_open[i].filled && !m_open[i].done) Close(m_open[i],t);
     }

   //--- Signaux récents (pour les tracés / panneau)
   int               OpenCount(void) { return(ArraySize(m_open)); }
   bool              GetOpen(int i,SSignal &s)
     {
      if(i<0 || i>=ArraySize(m_open)) return(false);
      s=m_open[i];
      return(true);
     }

   void              Write(SSignal &s)
     {
      if(m_db==NULL || !m_db.IsOpen()) return;
      CSqlRow r;
      r.Text("signal_uid",s.uid);
      r.Text("symbol",m_sym);
      r.Text("signal_time_ny",NYStr(s.tNY));
      string d=TimeToString(s.tNY,TIME_DATE); StringReplace(d,".","-");
      r.Text("trade_date",d);
      r.Int("dow",s.dow); r.Int("month",s.month); r.Int("hour_ny",s.hour); r.Int("minute_ny",s.minute);
      r.Text("session",s.session); r.Int("day_quarter",s.dayQ); r.Int("q90",s.q90); r.Int("q22",s.q22);
      r.Text("killzone",s.killzone); r.Text("sb_window",s.sbWindow); r.Text("macro",s.macro);
      r.Int("shadow_active",s.shadowActive);
      r.Text("model",s.model); r.Int("direction",s.dir);
      r.Text("swept_liq_type",s.liqType); r.Int("swept_liq_weight",s.liqWeight);
      r.Price("swept_liq_price",s.liqPrice);
      r.Text("sweep_time_ny",NYStr(s.tSweepNY));
      r.Int("mss",s.mss); r.Int("cisd",s.cisd); r.Int("displacement",s.disp);
      r.Real("disp_body_atr",s.dispBodyATR,3); r.Int("disp_candles",s.dispCandles); r.Real("disp_size_pts",s.dispSize,2);
      r.Real("atr_m1",s.atr1,3); r.Real("atr_m5",s.atr5,3); r.Real("atr_m15",s.atr15,3);
      r.Text("fvg_type",s.fvgType); r.Real("fvg_size_pts",s.fvgSize,2); r.Price("fvg_ce",s.fvgCE);
      r.Int("unicorn",s.unicorn); r.Int("breaker",s.breaker); r.Int("order_block",s.ob);
      r.Text("mitigation_block",""); r.Text("bpr",""); r.Int("ifvg",s.ifvg);
      r.Price("entry",s.entry); r.Price("sl",s.sl); r.Price("tp1",s.tp1); r.Price("tp2",s.tp2); r.Price("tp3",s.tp3);
      r.Real("risk_pts",s.riskPts,2); r.Real("dist_entry_ce",0.0,2); r.Real("dist_entry_invalidation",s.riskPts,2);
      r.Real("planned_rr",s.planRR,3);
      r.Text("premium_discount",s.pdLabel);
      if(s.pdPct>=0) r.Real("pd_pct",s.pdPct,1); else r.Text("pd_pct","");
      r.Int("ote",s.ote);
      if(s.smt>=0) r.Int("smt",s.smt); else r.Text("smt","");
      r.Real("stdv_reached",s.stdvReached,3);
      r.Text("weekly_profile",s.weeklyProfile); r.Text("amdx",s.amdx);
      r.Int("quarterly_align",s.qAlign); r.Int("weekly_bias",s.weeklyBias); r.Int("gap_cluster_bias",s.gapBias);
      r.Int("trend_day",s.trendDay); r.Int("news_window",s.newsWin);
      r.Real("spread_pts",s.spread,2); r.Real("day_range_so_far",s.dayRange,2);
      r.Real("asia_range",s.asiaRange,2); r.Real("london_range",s.londonRange,2); r.Real("ny_range",s.nyRange,2);
      r.Real("dist_daily_open",s.dDaily,2); r.Real("dist_weekly_open",s.dWeekly,2);
      r.Real("dist_monthly_open",s.dMonthly,2); r.Real("dist_midnight_open",s.dMidnight,2);
      r.Real("ict_score",s.score,2);
      if(s.mlProb>=0) r.Real("ml_prob",s.mlProb,4); else r.Text("ml_prob","");
      r.Text("ml_model_id",s.mlModel);
      r.Text("decision",s.decision); r.Text("reject_reason",s.reason);
      r.Text("outcome",s.outcome);
      r.Int("simulated",s.taken?0:1);
      r.Int("filled",s.filled?1:0);
      r.Text("fill_time_ny",s.tFill>0?NYStr(s.tNY+(s.tFill-s.tSrv)):"");
      r.Text("exit_time_ny",s.tExit>0?NYStr(s.tNY+(s.tExit-s.tSrv)):"");
      if(s.filled && s.outcome!="OPEN")
        {
         r.Real("r_multiple",s.rReal,4); r.Real("mfe_r",s.mfe,3); r.Real("mae_r",s.mae,3);
         r.Int("minutes_in_trade",(long)((s.tExit-s.tFill)/60));
        }
      else
        {
         r.Text("r_multiple",""); r.Text("mfe_r",""); r.Text("mae_r",""); r.Text("minutes_in_trade","");
        }
      r.Int("hit_tp1",s.tp1Hit?1:0); r.Int("hit_tp2",s.tp2Hit?1:0); r.Int("hit_tp3",s.tp3Hit?1:0);
      r.Text("ea_version",ICTNAS_VERSION);
      if(m_db.Write("signals",r,false)) m_written++;
     }
  };

#endif
//+------------------------------------------------------------------+
//=== fin SignalLogger.mqh ===
//=== début Scoring.mqh ===
//+------------------------------------------------------------------+
//|                                                     Scoring.mqh  |
//|  Score de confluence ICT 0-100. Poids par défaut validés ;       |
//|  poids recalibrés chargés depuis ict_weights.json (généré par    |
//|  ict_quant) s'il existe — bornés, jamais négatifs.               |
//+------------------------------------------------------------------+
#ifndef ICTNAS_SCORING_MQH
#define ICTNAS_SCORING_MQH

#define ICT_FACTORS 8
enum ENUM_ICT_FACTOR
  {
   F_SWEEP_HTF=0, F_SMT, F_CISD, F_DISPLACEMENT, F_FVG_VALID, F_OTE, F_QUARTERLY, F_WEEKLY
  };

class CScorer
  {
private:
   double            m_w[ICT_FACTORS];
   double            m_def[ICT_FACTORS];
   string            m_src;

public:
   static string     Name(int i)
     {
      switch(i)
        {
         case F_SWEEP_HTF:    return("sweep_htf");
         case F_SMT:          return("smt");
         case F_CISD:         return("cisd");
         case F_DISPLACEMENT: return("displacement");
         case F_FVG_VALID:    return("fvg_valid");
         case F_OTE:          return("ote");
         case F_QUARTERLY:    return("quarterly_align");
         case F_WEEKLY:       return("weekly_bias");
        }
      return("");
     }

   void              Init(void)
     {
      m_def[F_SWEEP_HTF]=20; m_def[F_SMT]=15; m_def[F_CISD]=15; m_def[F_DISPLACEMENT]=15;
      m_def[F_FVG_VALID]=10; m_def[F_OTE]=10; m_def[F_QUARTERLY]=10; m_def[F_WEEKLY]=5;
      for(int i=0;i<ICT_FACTORS;i++) m_w[i]=m_def[i];
      m_src="defaut";
     }

   //--- Lecture de {"weights": {"sweep_htf": 21.05, ...}} (dossier Common\Files)
   bool              LoadJSON(const string file)
     {
      if(!FileIsExist(file,FILE_COMMON)) return(false);
      int h=FileOpen(file,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ);
      if(h==INVALID_HANDLE) return(false);
      string txt="";
      while(!FileIsEnding(h)) txt+=FileReadString(h);
      FileClose(h);
      int base=StringFind(txt,"\"weights\"");
      if(base<0) return(false);
      double w[ICT_FACTORS];
      double tot=0;
      for(int i=0;i<ICT_FACTORS;i++)
        {
         string key="\""+Name(i)+"\"";
         int p=StringFind(txt,key,base);
         if(p<0) return(false);
         int c=StringFind(txt,":",p);
         if(c<0) return(false);
         int e=c+1;
         while(e<StringLen(txt))
           {
            ushort ch=StringGetCharacter(txt,e);
            if(ch==',' || ch=='}') break;
            e++;
           }
         double v=StringToDouble(StringSubstr(txt,c+1,e-c-1));
         //--- garde-fou : 25 % à 200 % du poids ICT, jamais négatif
         v=MathMax(0.25*m_def[i],MathMin(2.0*m_def[i],v));
         w[i]=v;
         tot+=v;
        }
      if(tot<=0) return(false);
      for(int i=0;i<ICT_FACTORS;i++) m_w[i]=w[i]*100.0/tot;
      m_src=file;
      return(true);
     }

   double            Score(int &f[])
     {
      double s=0;
      for(int i=0;i<ICT_FACTORS && i<ArraySize(f);i++) if(f[i]==1) s+=m_w[i];
      return(MathMin(100.0,s));
     }
   double            Weight(int i) { return(m_w[i]); }
   string            Source(void)  { return(m_src); }
  };

#endif
//+------------------------------------------------------------------+
//=== fin Scoring.mqh ===
//=== début MLInference.mqh ===
//+------------------------------------------------------------------+
//|                                                 MLInference.mqh  |
//|  Filtre ML (ONNX natif MT5). Il ne voit que des setups ICT déjà  |
//|  validés et renvoie une probabilité de gain. Il ne crée, ne      |
//|  modifie et ne supprime jamais un signal.                        |
//|                                                                  |
//|  Fichiers (Common\Files\ICTNAS\model\), déployés par ict_quant : |
//|    classifier.onnx   feature_spec.txt   ea_model.cfg             |
//+------------------------------------------------------------------+
#ifndef ICTNAS_MLINFERENCE_MQH
#define ICTNAS_MLINFERENCE_MQH

enum ENUM_ML_MODE
  {
   ML_OFF     = 0,   // Désactivé
   ML_OBSERVE = 1,   // Observation : probabilité calculée et enregistrée, ne bloque rien
   ML_FILTER  = 2    // Filtre : rejette sous le seuil (seulement si le modèle est promu)
  };

class CMLInference
  {
private:
   long              m_h;
   bool              m_ok;
   string            m_cols[];
   double            m_thr;
   string            m_status;
   string            m_id;
   bool              m_promoted;
   string            m_msg;

   string            ReadAll(const string file)
     {
      string out="";
      int h=FileOpen(file,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ);
      if(h==INVALID_HANDLE) return("");
      while(!FileIsEnding(h)) out+=FileReadString(h)+"\n";
      FileClose(h);
      return(out);
     }
   string            CfgValue(const string cfg,const string key)
     {
      int p=StringFind(cfg,key+"=");
      if(p<0) return("");
      int s=p+StringLen(key)+1;
      int e=StringFind(cfg,"\n",s);
      string v=StringSubstr(cfg,s,(e<0)?-1:e-s);
      StringTrimLeft(v);
      StringTrimRight(v);
      return(v);
     }
   static float      NaNf(void) { return((float)MathSqrt(-1.0)); }

   //--- Valeur numérique d'une feature (mêmes noms que la base / Python)
   double            Num(SSignal &s,const string c)
     {
      if(c=="dow") return(s.dow);                 if(c=="month") return(s.month);
      if(c=="hour_ny") return(s.hour);            if(c=="minute_ny") return(s.minute);
      if(c=="day_quarter") return(s.dayQ);        if(c=="q90") return(s.q90);
      if(c=="q22") return(s.q22);                 if(c=="shadow_active") return(s.shadowActive);
      if(c=="direction") return(s.dir);           if(c=="swept_liq_weight") return(s.liqWeight);
      if(c=="mss") return(s.mss);                 if(c=="cisd") return(s.cisd);
      if(c=="displacement") return(s.disp);       if(c=="disp_body_atr") return(s.dispBodyATR);
      if(c=="disp_candles") return(s.dispCandles);if(c=="disp_size_pts") return(s.dispSize);
      if(c=="atr_m1") return(s.atr1);             if(c=="atr_m5") return(s.atr5);
      if(c=="atr_m15") return(s.atr15);           if(c=="fvg_size_pts") return(s.fvgSize);
      if(c=="unicorn") return(s.unicorn);         if(c=="breaker") return(s.breaker);
      if(c=="order_block") return(s.ob);          if(c=="ifvg") return(s.ifvg);
      if(c=="risk_pts") return(s.riskPts);        if(c=="dist_entry_ce") return(0.0);
      if(c=="dist_entry_invalidation") return(s.riskPts);
      if(c=="planned_rr") return(s.planRR);
      if(c=="pd_pct") return(s.pdPct>=0?s.pdPct:(double)NaNf());
      if(c=="ote") return(s.ote);
      if(c=="smt") return(s.smt>=0?s.smt:(double)NaNf());
      if(c=="stdv_reached") return(s.stdvReached);
      if(c=="quarterly_align") return(s.qAlign);  if(c=="weekly_bias") return(s.weeklyBias);
      if(c=="gap_cluster_bias") return(s.gapBias);if(c=="trend_day") return(s.trendDay);
      if(c=="news_window") return(s.newsWin);     if(c=="spread_pts") return(s.spread);
      if(c=="day_range_so_far") return(s.dayRange);
      if(c=="asia_range") return(s.asiaRange);    if(c=="london_range") return(s.londonRange);
      if(c=="ny_range") return(s.nyRange);        if(c=="dist_daily_open") return(s.dDaily);
      if(c=="dist_weekly_open") return(s.dWeekly);if(c=="dist_monthly_open") return(s.dMonthly);
      if(c=="dist_midnight_open") return(s.dMidnight);
      if(c=="ict_score") return(s.score);
      return((double)NaNf());
     }
   string            Cat(SSignal &s,const string c)
     {
      string v="";
      if(c=="session") v=s.session;               else if(c=="killzone") v=s.killzone;
      else if(c=="sb_window") v=s.sbWindow;       else if(c=="macro") v=s.macro;
      else if(c=="model") v=s.model;              else if(c=="swept_liq_type") v=s.liqType;
      else if(c=="fvg_type") v=s.fvgType;         else if(c=="premium_discount") v=s.pdLabel;
      else if(c=="weekly_profile") v=s.weeklyProfile; else if(c=="amdx") v=s.amdx;
      return(v=="" ? "__na__" : v);
     }
   bool              InVocab(const string cat,const string val)
     {
      string k=cat+"="+val;
      for(int i=0;i<ArraySize(m_cols);i++) if(m_cols[i]==k) return(true);
      return(false);
     }

public:
                     CMLInference(void) : m_h(INVALID_HANDLE),m_ok(false),m_thr(0.5),m_promoted(false) {}

   bool              Load(const string folder)
     {
      m_ok=false;
      string cfg=ReadAll(folder+"\\ea_model.cfg");
      string spec=ReadAll(folder+"\\feature_spec.txt");
      if(cfg=="" || spec=="") { m_msg="ML : aucun modele deploye ("+folder+")"; return(false); }
      m_id=CfgValue(cfg,"model_id");
      m_status=CfgValue(cfg,"status");
      m_promoted=(m_status=="FILTER");
      m_thr=StringToDouble(CfgValue(cfg,"prob_threshold"));
      if(CfgValue(cfg,"ea_compatible")=="0") { m_msg="ML : modele "+m_id+" non compatible EA (sortie ZipMap)"; return(false); }
      string lines[];
      int n=StringSplit(spec,'\n',lines);
      ArrayResize(m_cols,0);
      for(int i=0;i<n;i++)
        {
         string l=lines[i];
         StringTrimLeft(l);
         StringTrimRight(l);
         if(l=="") continue;
         int k=ArraySize(m_cols);
         ArrayResize(m_cols,k+1);
         m_cols[k]=l;
        }
      int nf=ArraySize(m_cols);
      m_h=OnnxCreate(folder+"\\classifier.onnx",ONNX_COMMON_FOLDER);
      if(m_h==INVALID_HANDLE) { m_msg="ML : OnnxCreate erreur "+IntegerToString(GetLastError()); return(false); }
      ulong inShape[]={1,(ulong)nf};
      ulong labShape[]={1};
      ulong prShape[]={1,2};
      if(!OnnxSetInputShape(m_h,0,inShape) || OnnxGetOutputCount(m_h)<2 ||
         !OnnxSetOutputShape(m_h,0,labShape) || !OnnxSetOutputShape(m_h,1,prShape))
        {
         m_msg="ML : formes ONNX incompatibles (erreur "+IntegerToString(GetLastError())+")";
         OnnxRelease(m_h);
         m_h=INVALID_HANDLE;
         return(false);
        }
      m_ok=true;
      m_msg="ML : "+m_id+" ("+m_status+", seuil "+DoubleToString(m_thr,2)+", "+IntegerToString(nf)+" features)";
      return(true);
     }

   void              Release(void) { if(m_h!=INVALID_HANDLE) OnnxRelease(m_h); m_h=INVALID_HANDLE; }
   bool              Ready(void)     { return(m_ok); }
   bool              Promoted(void)  { return(m_promoted); }
   double            Threshold(void) { return(m_thr); }
   string            ModelId(void)   { return(m_id); }
   string            Status(void)    { return(m_msg); }

   //--- Probabilité de gain ; -1 si indisponible
   double            Predict(SSignal &s,int &factors[])
     {
      if(!m_ok) return(-1.0);
      int nf=ArraySize(m_cols);
      matrixf x(1,nf);
      for(int i=0;i<nf;i++)
        {
         string c=m_cols[i];
         double v;
         if(StringFind(c,"f_")==0)
           {
            v=0;
            string fn=StringSubstr(c,2);
            for(int k=0;k<ICT_FACTORS;k++) if(CScorer::Name(k)==fn) v=factors[k];
           }
         else
           {
            int eq=StringFind(c,"=");
            if(eq>0)
              {
               string cat=StringSubstr(c,0,eq),val=StringSubstr(c,eq+1);
               string sv=Cat(s,cat);
               if(val=="__other__") v=InVocab(cat,sv)?0.0:1.0;
               else v=(sv==val)?1.0:0.0;
              }
            else v=Num(s,c);
           }
         x[0][i]=(float)v;
        }
      long lab[];
      ArrayResize(lab,1);
      matrixf pr(1,2);
      if(!OnnxRun(m_h,ONNX_NO_CONVERSION,x,lab,pr))
        {
         m_msg="ML : OnnxRun erreur "+IntegerToString(GetLastError())+" -> desactive";
         m_ok=false;
         return(-1.0);
        }
      return((double)pr[0][1]);
     }
  };

#endif
//+------------------------------------------------------------------+
//=== fin MLInference.mqh ===
//=== début NewsFilter.mqh ===
//+------------------------------------------------------------------+
//|                                                  NewsFilter.mqh  |
//|  News USD à fort impact : fenêtre [news - avant ; news + après]. |
//|  Live : calendrier économique MT5. Testeur : le calendrier n'est |
//|  pas disponible -> fichier Common\Files\ICTNAS\news_usd.csv      |
//|  (une ligne par news, heure NY : "YYYY-MM-DD HH:MM").            |
//+------------------------------------------------------------------+
#ifndef ICTNAS_NEWSFILTER_MQH
#define ICTNAS_NEWSFILTER_MQH

class CNewsFilter
  {
private:
   bool              m_on;
   int               m_before;
   int               m_after;
   CTimeManager     *m_tm;
   datetime          m_csv[];      // heures serveur
   datetime          m_cal[];      // cache calendrier (heures serveur)
   datetime          m_calFrom;
   datetime          m_calTo;
   string            m_status;

   void              LoadCSV(const string file)
     {
      ArrayResize(m_csv,0);
      if(!FileIsExist(file,FILE_COMMON)) return;
      int h=FileOpen(file,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ);
      if(h==INVALID_HANDLE) return;
      while(!FileIsEnding(h))
        {
         string l=FileReadString(h);
         StringTrimLeft(l);
         StringTrimRight(l);
         if(StringLen(l)<16) continue;
         string d=StringSubstr(l,0,16);
         StringReplace(d,"-",".");
         datetime ny=StringToTime(d);
         if(ny<=0) continue;
         int n=ArraySize(m_csv);
         ArrayResize(m_csv,n+1);
         m_csv[n]=m_tm.NYToServer(ny);
        }
      FileClose(h);
     }

   void              RefreshCalendar(datetime now)
     {
      if(now>=m_calFrom && now+SEC_DAY<=m_calTo) return;
      m_calFrom=now-SEC_HOUR;
      m_calTo=now+2*SEC_DAY;
      ArrayResize(m_cal,0);
      MqlCalendarValue v[];
      if(CalendarValueHistory(v,m_calFrom,m_calTo,"US")<=0) return;
      for(int i=0;i<ArraySize(v);i++)
        {
         MqlCalendarEvent e;
         if(!CalendarEventById(v[i].event_id,e)) continue;
         if(e.importance!=CALENDAR_IMPORTANCE_HIGH) continue;
         int n=ArraySize(m_cal);
         ArrayResize(m_cal,n+1);
         m_cal[n]=v[i].time;
        }
     }

public:
   void              Init(bool on,int beforeMin,int afterMin,CTimeManager *tm,const string csvFile)
     {
      m_on=on; m_before=beforeMin; m_after=afterMin; m_tm=tm;
      m_calFrom=0; m_calTo=0;
      if(!on) { m_status="Filtre news desactive"; return; }
      LoadCSV(csvFile);
      bool tester=(bool)MQLInfoInteger(MQL_TESTER);
      if(tester)
         m_status=(ArraySize(m_csv)>0)?"News : "+IntegerToString(ArraySize(m_csv))+" dates (CSV)":
                  "News : aucun CSV en testeur -> filtre inactif";
      else
         m_status="News : calendrier MT5 (USD, impact fort)";
     }
   string            Status(void) { return(m_status); }

   bool              InWindow(datetime nowSrv)
     {
      if(!m_on) return(false);
      for(int i=0;i<ArraySize(m_csv);i++)
         if(nowSrv>=m_csv[i]-m_before*SEC_MIN && nowSrv<=m_csv[i]+m_after*SEC_MIN) return(true);
      if(!MQLInfoInteger(MQL_TESTER))
        {
         RefreshCalendar(nowSrv);
         for(int i=0;i<ArraySize(m_cal);i++)
            if(nowSrv>=m_cal[i]-m_before*SEC_MIN && nowSrv<=m_cal[i]+m_after*SEC_MIN) return(true);
        }
      return(false);
     }
  };

#endif
//+------------------------------------------------------------------+
//=== fin NewsFilter.mqh ===
//=== début TradeManager.mqh ===
//+------------------------------------------------------------------+
//|                                                TradeManager.mqh  |
//|  Exécution et gestion :                                          |
//|   - ordre LIMITE au CE du FVG (pas d'entrée au marché, sauf si  |
//|     le prix est déjà dans la moitié "entrée" du FVG) ;          |
//|   - SL au-delà de l'extrême du sweep, TP dur = TP3 ;            |
//|   - partiels TP1 50 % / TP2 25 % / reste 25 %, SL au BE+1 pt    |
//|     après TP1, puis trailing structurel M1 (swing + buffer) ;   |
//|   - annulation de l'ordre à l'expiration ou si le prix atteint  |
//|     TP1 sans retracement ;                                       |
//|   - enregistrement de chaque trade clôturé (table trades).      |
//|  v2.21 : remplissage / expiration adaptés au broker, délai de    |
//|  grâce avant d'abandonner le suivi d'un ordre exécuté.           |
//|  v2.30 : trades exécutés du jour comptés à l'exécution, niveau   |
//|  d'annulation propre au signal, entrée au marché bornée,         |
//|  annulation par identifiant de signal, contrôle des doublons.    |
//+------------------------------------------------------------------+
#ifndef ICTNAS_TRADEMANAGER_MQH
#define ICTNAS_TRADEMANAGER_MQH

struct STradeCtx
  {
   bool              active;
   string            uid;
   string            model;
   int               dir;
   ulong             order;
   bool              filled;
   ulong             posTicket;
   double            entry,sl,tp1,tp2,tp3,riskPts,riskMoney,balBefore;
   double            w1,w2,w3,initVol;
   double            beTrigger,inval;
   double            cancelPx;          // v2.30 : prix qui annule l'ordre en attente (0 = TP1)
   string            key;               // v2.40 : fenêtre / macro v6.20 ("" = autre modèle)
   bool              tp1Done,tp2Done,beDone;
   datetime          lastBarChecked;
   datetime          tPlaced,tExpiry,tOpen;
   double            mfePts,maePts;
  };

class CTradeManager
  {
private:
   CTrade            m_trade;
   string            m_sym;
   long              m_magic;
   CDataCollector   *m_db;
   CTimeManager     *m_tm;
   STradeCtx         m_t[];
   double            m_bePts;
   bool              m_trail;
   double            m_trailBuf;
   string            m_last;
   int               m_filledToday;     // v2.30 : trades exécutés depuis le début du jour de trading
   datetime          m_dayStartSrv;     // v2.40 : début du jour de trading (18:00 NY la veille, heure serveur)
   datetime          m_v6Fills[];       // v2.40 : heures d'entrée des trades des modèles v6.20

   void              AddV6Fill(const STradeCtx &c)
     {
      if(c.key=="") return;
      int n=ArraySize(m_v6Fills);
      if(n>=100)
        {
         for(int i=0;i<n-1;i++) m_v6Fills[i]=m_v6Fills[i+1];
         n--;
        }
      ArrayResize(m_v6Fills,n+1);
      m_v6Fills[n]=(c.tOpen>0) ? c.tOpen : TimeCurrent();
     }

   //--- v2.40 : ordre exécuté PUIS clôturé avant le tick suivant (SL / TP sur la bougie d'entrée)
   bool              ClosedBeforeTick(STradeCtx &c)
     {
      if(!HistorySelectByPosition(c.order)) return(false);
      bool hasIn=false,hasOut=false;
      for(int k=0;k<HistoryDealsTotal();k++)
        {
         ulong d=HistoryDealGetTicket(k);
         long e=HistoryDealGetInteger(d,DEAL_ENTRY);
         if(e==DEAL_ENTRY_IN)
           {
            hasIn=true;
            c.tOpen=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
            c.entry=HistoryDealGetDouble(d,DEAL_PRICE);
           }
         if(e==DEAL_ENTRY_OUT || e==DEAL_ENTRY_OUT_BY) hasOut=true;
        }
      if(!hasIn || !hasOut) return(false);
      c.filled=true;
      return(true);
     }

   double            Tick(void)
     {
      double t=SymbolInfoDouble(m_sym,SYMBOL_TRADE_TICK_SIZE);
      return(t>0?t:_Point);
     }
   double            NP(double p) { double t=Tick(); return(NormalizeDouble(MathRound(p/t)*t,_Digits)); }
   double            NV(double v)
     {
      double st=SymbolInfoDouble(m_sym,SYMBOL_VOLUME_STEP);
      if(st<=0) st=0.01;
      return(NormalizeDouble(MathFloor(v/st+1e-9)*st,8));
     }
   double            VMin(void) { return(SymbolInfoDouble(m_sym,SYMBOL_VOLUME_MIN)); }

   //--- Type d'expiration accepté par le symbole (certains brokers refusent GTC)
   ENUM_ORDER_TYPE_TIME PendingTimeType(void)
     {
      int m=(int)SymbolInfoInteger(m_sym,SYMBOL_EXPIRATION_MODE);
      if((m&SYMBOL_EXPIRATION_GTC)!=0) return(ORDER_TIME_GTC);
      if((m&SYMBOL_EXPIRATION_SPECIFIED)!=0) return(ORDER_TIME_SPECIFIED);
      return(ORDER_TIME_DAY);
     }

   bool              FindPosition(ulong orderTicket,ulong &posTicket)
     {
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong t=PositionGetTicket(i);
         if(t==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_sym) continue;
         if((ulong)PositionGetInteger(POSITION_IDENTIFIER)==orderTicket) { posTicket=t; return(true); }
        }
      return(false);
     }

   //--- Dernier swing M1 (2 bougies de chaque côté) pour le trailing
   double            LastSwingM1(int dir)
     {
      MqlRates r[];
      ArraySetAsSeries(r,true);
      if(CopyRates(m_sym,PERIOD_M1,1,40,r)<40) return(0);
      for(int i=2;i<38;i++)
        {
         if(dir==1  && r[i].low <r[i-1].low  && r[i].low <r[i-2].low  && r[i].low <r[i+1].low  && r[i].low <r[i+2].low)  return(r[i].low);
         if(dir==-1 && r[i].high>r[i-1].high && r[i].high>r[i-2].high && r[i].high>r[i+1].high && r[i].high>r[i+2].high) return(r[i].high);
        }
      return(0);
     }

   void              Finalize(STradeCtx &c)
     {
      c.active=false;
      if(!HistorySelectByPosition(c.order)) return;
      double profit=0,comm=0,swap=0,exitPx=0,volOut=0,entryPx=c.entry;
      datetime tClose=0;
      for(int i=0;i<HistoryDealsTotal();i++)
        {
         ulong d=HistoryDealGetTicket(i);
         long entry=HistoryDealGetInteger(d,DEAL_ENTRY);
         double v=HistoryDealGetDouble(d,DEAL_VOLUME);
         comm+=HistoryDealGetDouble(d,DEAL_COMMISSION);
         swap+=HistoryDealGetDouble(d,DEAL_SWAP);
         profit+=HistoryDealGetDouble(d,DEAL_PROFIT);
         if(entry==DEAL_ENTRY_IN) entryPx=HistoryDealGetDouble(d,DEAL_PRICE);
         if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
           {
            exitPx+=HistoryDealGetDouble(d,DEAL_PRICE)*v;
            volOut+=v;
            tClose=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
           }
        }
      if(volOut>0) exitPx/=volOut;
      double net=profit+comm+swap;
      double r=(c.riskMoney>0)?net/c.riskMoney:0;
      if(m_db==NULL || !m_db.IsOpen()) return;
      CSqlRow row;
      row.Text("signal_uid",c.uid);
      row.Text("model",c.model);
      row.Text("symbol",m_sym);
      row.Int("ticket",(long)c.order);
      row.Text("open_time_ny",NYs(c.tOpen));
      row.Text("close_time_ny",NYs(tClose));
      row.Int("direction",c.dir);
      row.Real("lots",c.initVol,2);
      row.Price("entry",entryPx);
      row.Price("exit_price",exitPx);
      row.Price("sl",c.sl);
      row.Real("profit_money",net,2);
      row.Real("profit_pct",(c.balBefore>0)?net/c.balBefore*100.0:0,3);
      row.Real("profit_pts",c.dir*(exitPx-entryPx),2);
      row.Real("r_multiple",r,3);
      row.Real("mfe_pts",c.mfePts,2);
      row.Real("mae_pts",c.maePts,2);
      row.Int("minutes_in_trade",(tClose>c.tOpen)?(long)((tClose-c.tOpen)/60):0);
      row.Real("commission",comm,2);
      row.Real("swap",swap,2);
      row.Text("outcome",r>0.05?"WIN":(r<-0.05?"LOSS":"BE"));
      row.Real("balance_before",c.balBefore,2);
      m_db.Write("trades",row,false);
     }

   string            NYs(datetime srv)
     {
      if(srv<=0) return("");
      string s=TimeToString(m_tm.ServerToNY(srv),TIME_DATE|TIME_MINUTES);
      StringReplace(s,".","-");
      return(s);
     }

public:
   void              Init(const string sym,long magic,CDataCollector *db,CTimeManager *tm,
                          double bePts,bool trail,double trailBuf)
     {
      m_sym=sym; m_magic=magic; m_db=db; m_tm=tm;
      m_bePts=bePts; m_trail=trail; m_trailBuf=trailBuf;
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(20);
      m_trade.SetTypeFillingBySymbol(sym);
      ArrayResize(m_t,0);
      m_last="";
      m_filledToday=0;
      m_dayStartSrv=0;
      ArrayResize(m_v6Fills,0);
     }
   string            LastMessage(void) { return(m_last); }

   int               ActiveCount(void)
     {
      int c=0;
      for(int i=0;i<ArraySize(m_t);i++) if(m_t[i].active) c++;
      return(c);
     }
   int               ActiveDirection(void)
     {
      for(int i=0;i<ArraySize(m_t);i++) if(m_t[i].active) return(m_t[i].dir);
      return(0);
     }

   //--- v2.30 : compteurs du jour (trades exécutés, ordres en attente)
   void              NewDay(datetime dayStartSrv) { m_filledToday=0; m_dayStartSrv=dayStartSrv; }
   //--- v2.40 (RiskGuard) : entrées du jour lues dans l'historique (positions distinctes, magic de l'EA) ;
   //--- un redémarrage ou une exécution manquée par le suivi ne remet plus le compteur à zéro
   int               FilledToday(void)
     {
      int n=m_filledToday;
      if(m_dayStartSrv<=0 || !HistorySelect(m_dayStartSrv,TimeCurrent()+60)) return(n);
      long ids[];
      int h=0;
      for(int i=0;i<HistoryDealsTotal();i++)
        {
         ulong d=HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(d,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
         if(HistoryDealGetInteger(d,DEAL_MAGIC)!=m_magic || HistoryDealGetString(d,DEAL_SYMBOL)!=m_sym) continue;
         long pid=HistoryDealGetInteger(d,DEAL_POSITION_ID);
         bool seen=false;
         for(int j=0;j<h;j++) if(ids[j]==pid) { seen=true; break; }
         if(seen) continue;
         ArrayResize(ids,h+1);
         ids[h]=pid;
         h++;
        }
      return(h>n ? h : n);
     }
   //--- v2.40 (règle v6.20 « TradesInWindow ») : ordres v6.20 en attente + entrées v6.20 depuis le début
   //--- de la fenêtre / macro (un trade Macro Breaker compte aussi dans la fenêtre Silver Bullet qui le contient)
   int               V6CountSince(const datetime from)
     {
      int c=0;
      for(int i=0;i<ArraySize(m_t);i++) if(m_t[i].active && !m_t[i].filled && m_t[i].key!="") c++;
      for(int i=0;i<ArraySize(m_v6Fills);i++) if(m_v6Fills[i]>=from) c++;
      return(c);
     }
   //--- v2.40 (RiskGuard) : risque encore ouvert = positions dont le SL n'est pas au BE + ordres en attente
   double            OpenRiskMoney(void)
     {
      double risk=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong t=PositionGetTicket(i);
         if(t==0 || PositionGetString(POSITION_SYMBOL)!=m_sym || PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         double sl=PositionGetDouble(POSITION_SL),open=PositionGetDouble(POSITION_PRICE_OPEN),vol=PositionGetDouble(POSITION_VOLUME);
         bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
         if(sl<=0) { risk+=AccountInfoDouble(ACCOUNT_EQUITY); continue; }      // pas de SL = tout le compte
         if(buy ? sl>=open : sl<=open) continue;                               // SL au BE ou mieux : plus de risque
         double p=0;
         if(OrderCalcProfit(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,m_sym,vol,open,sl,p) && p<0) risk-=p;
        }
      for(int i=0;i<ArraySize(m_t);i++) if(m_t[i].active && !m_t[i].filled) risk+=m_t[i].riskMoney;
      return(risk);
     }
   int               PendingCount(void)
     {
      int c=0;
      for(int i=0;i<ArraySize(m_t);i++) if(m_t[i].active && !m_t[i].filled) c++;
      return(c);
     }

   //--- v2.30 : supprime l'ordre en attente d'un signal (false si absent ou déjà exécuté)
   bool              CancelUid(const string uid)
     {
      for(int i=0;i<ArraySize(m_t);i++)
        {
         if(!m_t[i].active || m_t[i].filled || m_t[i].uid!=uid) continue;
         if(OrderSelect(m_t[i].order)) m_trade.OrderDelete(m_t[i].order);
         m_t[i].active=false;
         return(true);
        }
      return(false);
     }

   //--- v2.30 : un ordre ou une position de ce signal existe déjà (ex. après un redémarrage)
   bool              ExistsOnServer(const string uid)
     {
      for(int i=0;i<ArraySize(m_t);i++) if(m_t[i].active && m_t[i].uid==uid) return(true);
      for(int i=OrdersTotal()-1;i>=0;i--)
        {
         ulong t=OrderGetTicket(i);
         if(t==0 || OrderGetString(ORDER_SYMBOL)!=m_sym || OrderGetInteger(ORDER_MAGIC)!=m_magic) continue;
         if(StringFind(OrderGetString(ORDER_COMMENT),uid)>=0) return(true);
        }
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong t=PositionGetTicket(i);
         if(t==0 || PositionGetString(POSITION_SYMBOL)!=m_sym || PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         if(StringFind(PositionGetString(POSITION_COMMENT),uid)>=0) return(true);
        }
      return(false);
     }

   //--- Place l'ordre du signal ; renvoie false (et err) si impossible
   bool              Place(SSignal &s,double lots,double riskMoney,string &err)
     {
      double ask=SymbolInfoDouble(m_sym,SYMBOL_ASK),bid=SymbolInfoDouble(m_sym,SYMBOL_BID);
      double stops=SymbolInfoInteger(m_sym,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
      double entry=NP(s.entry),sl=NP(s.sl),tp=NP(s.tp3);
      string cmt=s.model+" "+s.uid;
      if(StringLen(cmt)>31) cmt=StringSubstr(cmt,0,31);
      double pxNow=(s.dir==1)?ask:bid;
      if(s.inval>0 && s.dir*(pxNow-s.inval)<0) { err="FVG deja pris a plus de 50 %"; return(false); }
      //--- 0 = marché, 1 = limite au CE / bord du FVG
      int kind=-1;
      if(s.market) kind=0;
      else if(s.dir==1)
        {
         if(ask>entry+stops) kind=1;
         else if(ask>sl && ask<=s.fvgTop) kind=0;
        }
      else
        {
         if(bid<entry-stops) kind=1;
         else if(bid<sl && bid>=s.fvgBot) kind=0;
        }
      if(kind<0) { err="prix hors zone d'entree"; return(false); }
      //--- v2.30 : le prix a déjà traversé le niveau d'entrée : entrée au marché seulement s'il n'est pas allé trop loin
      if(kind==0 && !s.market && s.chaseR>0 && s.dir*(entry-pxNow)>s.chaseR*MathAbs(entry-sl))
        { err="setup manque : prix trop loin au-dela de l'entree"; return(false); }
      if(kind==0 && MathAbs(pxNow-sl)<=stops) { err="SL trop proche (stops level)"; return(false); }
      bool market=(kind==0);
      ENUM_ORDER_TYPE_TIME tt=PendingTimeType();
      datetime exp=0;
      if(tt==ORDER_TIME_SPECIFIED)
        {
         exp=s.expirySrv;
         if(exp<TimeCurrent()+120) exp=TimeCurrent()+120;
        }
      //--- nouvel essai avec un autre mode de remplissage si le broker refuse (retcode 10030)
      ENUM_ORDER_TYPE_FILLING fills[3]={ORDER_FILLING_RETURN,ORDER_FILLING_IOC,ORDER_FILLING_FOK};
      bool ok=false;
      uint rc=0;
      for(int a=0;a<4;a++)
        {
         if(a==0) m_trade.SetTypeFillingBySymbol(m_sym);
         else     m_trade.SetTypeFilling(fills[a-1]);
         if(market) ok=(s.dir==1)?m_trade.Buy(lots,m_sym,0,sl,tp,cmt):m_trade.Sell(lots,m_sym,0,sl,tp,cmt);
         else       ok=(s.dir==1)?m_trade.BuyLimit(lots,entry,m_sym,sl,tp,tt,exp,cmt)
                                 :m_trade.SellLimit(lots,entry,m_sym,sl,tp,tt,exp,cmt);
         rc=m_trade.ResultRetcode();
         if(rc!=TRADE_RETCODE_INVALID_FILL) break;
        }
      m_trade.SetTypeFillingBySymbol(m_sym);
      if(!ok || (rc!=TRADE_RETCODE_DONE && rc!=TRADE_RETCODE_PLACED && rc!=TRADE_RETCODE_DONE_PARTIAL))
        {
         err="ordre refuse ("+IntegerToString(rc)+" "+m_trade.ResultRetcodeDescription()+")";
         return(false);
        }
      int n=ArraySize(m_t);
      ArrayResize(m_t,n+1);
      m_t[n].active=true;
      m_t[n].uid=s.uid;
      m_t[n].model=s.model;
      m_t[n].dir=s.dir;
      m_t[n].order=m_trade.ResultOrder();
      m_t[n].filled=false;
      m_t[n].posTicket=0;
      m_t[n].entry=market?(s.dir==1?ask:bid):entry;
      m_t[n].sl=sl; m_t[n].tp1=NP(s.tp1); m_t[n].tp2=NP(s.tp2); m_t[n].tp3=tp;
      m_t[n].riskPts=MathAbs(m_t[n].entry-sl);
      m_t[n].riskMoney=riskMoney;
      m_t[n].balBefore=AccountInfoDouble(ACCOUNT_BALANCE);
      m_t[n].w1=s.w1; m_t[n].w2=s.w2; m_t[n].w3=s.w3;
      m_t[n].initVol=lots;
      m_t[n].tp1Done=false; m_t[n].tp2Done=false; m_t[n].beDone=false;
      m_t[n].beTrigger=s.beTrigger; m_t[n].inval=s.inval; m_t[n].lastBarChecked=0;
      m_t[n].cancelPx=(s.cancelPx>0)?NP(s.cancelPx):0;
      m_t[n].key=s.extKey;
      m_t[n].tPlaced=TimeCurrent();
      m_t[n].tExpiry=s.expirySrv;
      m_t[n].tOpen=0;
      m_t[n].mfePts=0; m_t[n].maePts=0;
      m_last=(market?"Marche ":"Limite ")+s.model+(s.dir==1?" BUY ":" SELL ")+DoubleToString(lots,2)+" @ "+PxStr(m_t[n].entry);
      return(true);
     }

   void              OnTick(void)
     {
      double bid=SymbolInfoDouble(m_sym,SYMBOL_BID),ask=SymbolInfoDouble(m_sym,SYMBOL_ASK);
      datetime now=TimeCurrent();
      for(int i=0;i<ArraySize(m_t);i++)
        {
         if(!m_t[i].active) continue;
         int d=m_t[i].dir;
         double px=(d==1)?bid:ask;
         //--- ordre en attente
         if(!m_t[i].filled)
           {
            ulong pt;
            if(FindPosition(m_t[i].order,pt))
              {
               m_t[i].filled=true;
               m_t[i].posTicket=pt;
               m_t[i].tOpen=(datetime)PositionGetInteger(POSITION_TIME);
               m_t[i].entry=PositionGetDouble(POSITION_PRICE_OPEN);
               m_filledToday++;
               AddV6Fill(m_t[i]);
               continue;
              }
            if(OrderSelect(m_t[i].order))
              {
               double cx=(m_t[i].cancelPx>0)?m_t[i].cancelPx:m_t[i].tp1;
               if(now>=m_t[i].tExpiry || d*(px-cx)>=0)
                 {
                  m_trade.OrderDelete(m_t[i].order);
                  m_t[i].active=false;
                 }
              }
            else if(ClosedBeforeTick(m_t[i]))
              {
               //--- v2.40 : exécuté et déjà clôturé (même tick) : compté dans le jour et enregistré dans « trades »
               m_filledToday++;
               AddV6Fill(m_t[i]);
               Finalize(m_t[i]);
              }
            else if(now-m_t[i].tPlaced>60)
               m_t[i].active=false;           // annulé / rejeté / expiré (délai de grâce : la position peut apparaître en retard)
            continue;
           }
         //--- position ouverte
         if(!PositionSelectByTicket(m_t[i].posTicket)) { Finalize(m_t[i]); continue; }
         double vol=PositionGetDouble(POSITION_VOLUME);
         double curSL=PositionGetDouble(POSITION_SL);
         double curTP=PositionGetDouble(POSITION_TP);
         m_t[i].mfePts=MathMax(m_t[i].mfePts,d*(px-m_t[i].entry));
         m_t[i].maePts=MathMax(m_t[i].maePts,-d*(px-m_t[i].entry));
         //--- règle des 50 % du FVG : clôture M1 au-delà du CE -> position fermée
         if(m_t[i].inval>0)
           {
            datetime b1=iTime(m_sym,PERIOD_M1,1);
            if(b1!=m_t[i].lastBarChecked && b1>=m_t[i].tOpen)
              {
               m_t[i].lastBarChecked=b1;
               double c1=iClose(m_sym,PERIOD_M1,1);
               if(d*(c1-m_t[i].inval)<0) { m_trade.PositionClose(m_t[i].posTicket); continue; }
              }
           }
         //--- break-even à 1R
         if(!m_t[i].beDone && m_t[i].beTrigger>0 && d*(px-m_t[i].beTrigger)>=0)
           {
            m_t[i].beDone=true;
            double be=NP(m_t[i].entry+d*m_bePts);
            if(d*(be-curSL)>0) m_trade.PositionModify(m_t[i].posTicket,be,curTP);
            continue;
           }
         if(!m_t[i].tp1Done && d*(px-m_t[i].tp1)>=0)
           {
            m_t[i].tp1Done=true;
            double cv=NV(m_t[i].initVol*m_t[i].w1);
            if(m_t[i].w1<1.0 && cv>=VMin() && vol-cv>=VMin()) m_trade.PositionClosePartial(m_t[i].posTicket,cv);
            else if(m_t[i].w1>=1.0) { m_trade.PositionClose(m_t[i].posTicket); continue; }
            double be=NP(m_t[i].entry+d*m_bePts);
            if(d*(be-curSL)>0) m_trade.PositionModify(m_t[i].posTicket,be,curTP);
            continue;
           }
         if(m_t[i].tp1Done && !m_t[i].tp2Done && m_t[i].w2>0 && d*(px-m_t[i].tp2)>=0)
           {
            m_t[i].tp2Done=true;
            if(m_t[i].w3<=0) { m_trade.PositionClose(m_t[i].posTicket); continue; }
            double cv=NV(m_t[i].initVol*m_t[i].w2);
            if(cv>=VMin() && vol-cv>=VMin()) m_trade.PositionClosePartial(m_t[i].posTicket,cv);
            continue;
           }
         //--- trailing structurel après TP1
         if(m_trail && m_t[i].tp1Done)
           {
            double sw=LastSwingM1(d);
            if(sw>0)
              {
               double nsl=NP(sw-d*m_trailBuf);
               double stops=SymbolInfoInteger(m_sym,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
               if(d*(nsl-curSL)>Tick() && d*(px-nsl)>stops)
                  m_trade.PositionModify(m_t[i].posTicket,nsl,curTP);
              }
           }
        }
      //--- purge des contextes inactifs
      int k=0;
      for(int i=0;i<ArraySize(m_t);i++) if(m_t[i].active) { if(k!=i) m_t[k]=m_t[i]; k++; }
      ArrayResize(m_t,k);
     }

   //--- v2.50 : supprime les ordres en attente, garde les positions (objectif journalier atteint)
   void              DeletePendingOrders(void)
     {
      for(int i=0;i<ArraySize(m_t);i++)
        {
         if(!m_t[i].active || m_t[i].filled) continue;
         if(OrderSelect(m_t[i].order) && m_trade.OrderDelete(m_t[i].order)) m_t[i].active=false;
        }
     }
   //--- Ferme tout (flat de fin de journée, limite journalière)
   void              CloseAll(void)
     {
      for(int i=0;i<ArraySize(m_t);i++)
        {
         if(!m_t[i].active) continue;
         if(!m_t[i].filled) { if(OrderSelect(m_t[i].order)) m_trade.OrderDelete(m_t[i].order); m_t[i].active=false; continue; }
         if(PositionSelectByTicket(m_t[i].posTicket)) m_trade.PositionClose(m_t[i].posTicket);
        }
     }
  };

#endif
//+------------------------------------------------------------------+
//=== fin TradeManager.mqh ===

//+------------------------------------------------------------------+
//| v2.30 : moteur London OPR (stratégie OPR + FVG, PDF de Mélanie). |
//| Modules repris tels quels de mql5/Experts/OPR_FVG (testés) ;     |
//| seule la classe COprEngine est renommée CLondonOprEngine.        |
//+------------------------------------------------------------------+
//=== début OPR_Config.mqh ===
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
//=== fin OPR_Config.mqh ===

//=== début OPR_Time.mqh ===
//+------------------------------------------------------------------+
//|                                                     OPR_Time.mqh |
//|  Module 1 : horaires et calendrier.                              |
//|  Conversion heure serveur -> UTC -> heure de la stratégie, avec  |
//|  les changements d'heure US et européens, et découpage en        |
//|  journées de session (les plages qui traversent minuit restent   |
//|  dans la même journée de session).                               |
//|                                                                  |
//|  Trois heures distinctes ne sont jamais mélangées :              |
//|    serveur (datetime MT5)  ->  UTC (long)  ->  stratégie (long). |
//+------------------------------------------------------------------+
#ifndef OPR_TIME_MQH
#define OPR_TIME_MQH

class COprTime
  {
public:
   int               m_stratTz;
   int               m_srvMode;
   int               m_srvGmtSec;
   int               m_dayStartMin;
   int               m_usYear;
   long              m_usStart;
   long              m_usEnd;
   int               m_euYear;
   long              m_euStart;
   long              m_euEnd;

                     COprTime() { m_usYear = 0; m_euYear = 0; m_stratTz = OPR_STZ_NEW_YORK; m_srvMode = OPR_SRV_GMT_FIXED; m_srvGmtSec = 0; m_dayStartMin = 18 * 60; }

   void              Configure(const int stratTz, const int srvMode, const int srvGmtSec, const int dayStartMin)
     {
      m_stratTz     = stratTz;
      m_srvMode     = srvMode;
      m_srvGmtSec   = srvGmtSec;
      m_dayStartMin = dayStartMin;
      m_usYear      = 0;
      m_euYear      = 0;
     }

   //+---------------------------------------------------------------+
   //| Règles de changement d'heure                                  |
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

   long              LastSundayUtc(const int year, const int mon, const int hourUtc)
     {
      //--- mars et octobre ont 31 jours
      MqlDateTime s;
      ZeroMemory(s);
      s.year = year;
      s.mon  = mon;
      s.day  = 31;
      datetime last = StructToTime(s);
      MqlDateTime f;
      TimeToStruct(last, f);
      return (long)last - (long)f.day_of_week * 86400 + (long)hourUtc * 3600;
     }

   //--- DST US : 2e dimanche de mars 07:00 UTC -> 1er dimanche de novembre 06:00 UTC
   bool              IsUsDst(const long utc)
     {
      MqlDateTime s;
      TimeToStruct((datetime)utc, s);
      if(s.year != m_usYear)
        {
         m_usYear  = s.year;
         m_usStart = NthSundayUtc(s.year, 3, 2, 7);
         m_usEnd   = NthSundayUtc(s.year, 11, 1, 6);
        }
      return (utc >= m_usStart && utc < m_usEnd);
     }

   //--- DST européen : dernier dimanche de mars 01:00 UTC -> dernier dimanche d'octobre 01:00 UTC
   bool              IsEuDst(const long utc)
     {
      MqlDateTime s;
      TimeToStruct((datetime)utc, s);
      if(s.year != m_euYear)
        {
         m_euYear  = s.year;
         m_euStart = LastSundayUtc(s.year, 3, 1);
         m_euEnd   = LastSundayUtc(s.year, 10, 1);
        }
      return (utc >= m_euStart && utc < m_euEnd);
     }

   //+---------------------------------------------------------------+
   //| Conversions                                                   |
   //+---------------------------------------------------------------+
   long              ServerToUtc(const datetime srv)
     {
      long guess = (long)srv - m_srvGmtSec;
      if(m_srvMode == OPR_SRV_GMT_US_DST)
         return IsUsDst(guess - 3600) ? guess - 3600 : guess;
      if(m_srvMode == OPR_SRV_GMT_EU_DST)
         return IsEuDst(guess - 3600) ? guess - 3600 : guess;
      return guess;
     }

   long              UtcToStrat(const long utc)
     {
      if(m_stratTz == OPR_STZ_NEW_YORK)
         return utc - 5 * 3600 + (IsUsDst(utc) ? 3600 : 0);
      if(m_stratTz == OPR_STZ_LONDON)
         return utc + (IsEuDst(utc) ? 3600 : 0);
      if(m_stratTz == OPR_STZ_PARIS)
         return utc + 3600 + (IsEuDst(utc) ? 3600 : 0);
      return utc;
     }

   long              StratTime(const datetime srv)
     {
      if(m_stratTz == OPR_STZ_SERVER)
         return (long)srv;
      return UtcToStrat(ServerToUtc(srv));
     }

   //--- minute du jour (0..1439) d'une heure stratégie
   int               MinuteOfDay(const long st) const
     {
      long sod = st % 86400;
      if(sod < 0)
         sod += 86400;
      return (int)(sod / 60);
     }

   //--- journée de session : commence à dayStartMin (ex. 18:00 la veille pour un début >= 12:00)
   int               SessionDay(const long st) const
     {
      long d = (st - (long)m_dayStartMin * 60);
      long day = (d >= 0) ? d / 86400 : (d - 86399) / 86400;
      return (int)(day + (m_dayStartMin >= 720 ? 1 : 0));
     }

   //--- heure stratégie absolue d'une minute du jour dans une journée de session
   long              SessionAbs(const int day, const int minute) const
     {
      long base = (long)day * 86400;
      if(m_dayStartMin >= 720 && minute >= m_dayStartMin)
         return base - 86400 + (long)minute * 60;
      if(m_dayStartMin < 720 && minute < m_dayStartMin)
         return base + 86400 + (long)minute * 60;
      return base + (long)minute * 60;
     }

   //--- bornes absolues [s, e) d'une plage dans une journée de session
   bool              RangeAbs(const int day, const OPRTimeRange &r, long &s, long &e) const
     {
      if(!r.valid)
         return false;
      s = SessionAbs(day, r.startMin);
      e = s + (long)r.Length() * 60;
      return true;
     }

   //--- position d'une minute dans la journée de session (0 = début de journée)
   int               SessionMinute(const int minute) const { return (minute - m_dayStartMin + 1440) % 1440; }

   //--- la plage tient-elle entièrement dans une journée de session ?
   bool              FitsInSession(const OPRTimeRange &r) const
     {
      if(!r.valid)
         return true;
      return (SessionMinute(r.startMin) + r.Length() <= 1440);
     }
  };

//+------------------------------------------------------------------+
//| Lecture "HH:MM" -> minutes (-1 si invalide)                      |
//+------------------------------------------------------------------+
int OprParseHHMM(const string txt)
  {
   string s = txt;
   StringTrimLeft(s);
   StringTrimRight(s);
   string parts[];
   if(StringSplit(s, ':', parts) != 2)
      return -1;
   if(StringLen(parts[0]) < 1 || StringLen(parts[1]) != 2)
      return -1;
   int h = (int)StringToInteger(parts[0]);
   int m = (int)StringToInteger(parts[1]);
   if(h < 0 || h > 24 || m < 0 || m > 59 || (h == 24 && m != 0))
      return -1;
   return (h * 60 + m) % 1440;
  }

//+------------------------------------------------------------------+
//| Lecture "HH:MM-HH:MM" ; chaîne vide = plage non configurée.      |
//| Retourne false si le texte est invalide.                         |
//+------------------------------------------------------------------+
bool OprParseRange(const string txt, OPRTimeRange &r)
  {
   r.Clear();
   string s = txt;
   StringTrimLeft(s);
   StringTrimRight(s);
   if(StringLen(s) == 0)
      return true;
   string parts[];
   if(StringSplit(s, '-', parts) != 2)
      return false;
   int a = OprParseHHMM(parts[0]);
   int b = OprParseHHMM(parts[1]);
   if(a < 0 || b < 0 || a == b)
      return false;
   r.Set(a, b);
   return true;
  }

//+------------------------------------------------------------------+
//| Lecture d'une liste "HH:MM-HH:MM,HH:MM-HH:MM"                    |
//+------------------------------------------------------------------+
bool OprParseRanges(const string txt, OPRTimeRange &out[])
  {
   ArrayResize(out, 0);
   string s = txt;
   StringTrimLeft(s);
   StringTrimRight(s);
   if(StringLen(s) == 0)
      return true;
   string parts[];
   int n = StringSplit(s, ',', parts);
   for(int i = 0; i < n; i++)
     {
      OPRTimeRange r;
      if(!OprParseRange(parts[i], r) || !r.valid)
         return false;
      ArrayResize(out, i + 1);
      out[i] = r;
     }
   return true;
  }

string OprHHMM(const int m) { return StringFormat("%02d:%02d", m / 60, m % 60); }
string OprRangeText(const OPRTimeRange &r) { return r.valid ? OprHHMM(r.startMin) + "-" + OprHHMM(r.endMin) : "-"; }

#endif // OPR_TIME_MQH
//+------------------------------------------------------------------+
//=== fin OPR_Time.mqh ===

//=== début OPR_Candles.mqh ===
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
//=== fin OPR_Candles.mqh ===

//=== début OPR_FVG.mqh ===
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
//=== fin OPR_FVG.mqh ===

//=== début OPR_Ranges.mqh ===
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
//=== fin OPR_Ranges.mqh ===

//=== début OPR_Liquidity.mqh ===
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
//=== fin OPR_Liquidity.mqh ===

//=== début OPR_Journal.mqh ===
//+------------------------------------------------------------------+
//|                                                  OPR_Journal.mqh |
//|  Module 8 : journalisation et diagnostic.                        |
//|  Chaque décision du moteur est un événement codé, horodaté       |
//|  (heure stratégie + heure serveur), avec les prix concernés et,  |
//|  pour un rejet, sa raison. Le texte est produit ici pour que     |
//|  l'EA, les tests et le fichier CSV utilisent le même libellé.    |
//+------------------------------------------------------------------+
#ifndef OPR_JOURNAL_MQH
#define OPR_JOURNAL_MQH

//--- codes d'événements
#define J_OPR_BUILDING      1
#define J_OPR_FINAL         2
#define J_OPR_INCOMPLETE    3
#define J_OPR_NODATA        4
#define J_ASIA_FINAL        5
#define J_ASIA_FVG          6
#define J_ASIA_FVG_NONE     7
#define J_MIDNIGHT_FVG      8
#define J_CTX_ABOVE         9
#define J_CTX_BELOW         10
#define J_CTX_INSIDE        11
#define J_FVG_DETECTED      12
#define J_FVG_STATUS        13
#define J_WINDOW_OPEN       14
#define J_WINDOW_CLOSE      15
#define J_MACRO_OPEN        16
#define J_MACRO_CLOSE       17
#define J_OBS_OPEN          18
#define J_OBS_CLOSE         19
#define J_BIAS              20
#define J_BIAS_CONSOL       21
#define J_BIAS_BREAKOUT     22
#define J_SWEEP             23
#define J_FVG_CANDIDATE     24
#define J_FVG_IGNORED       25
#define J_ENTRY_REJECTED    26
#define J_ENTRY_AUTHORIZED  27
#define J_SETUP_CANCELLED   28
#define J_TRADE_FILLED      29
#define J_TRADE_CLOSED      30
#define J_DAY_START         31
#define J_SESSION_INFO      32

//--- raisons de rejet / d'annulation
#define R_NONE              0
#define R_NO_OPR            1   // OPR non finalisé / incomplet / sans données
#define R_TRADE_DISABLED    2   // pas de règle d'entrée configurée pour cet OPR
#define R_WRONG_DIR         3   // FVG dans le sens opposé au biais
#define R_OUTSIDE_MACRO     4
#define R_MACRO_USED        5   // 1 macro = 1 trade
#define R_IN_POSITION       6
#define R_TARGET_REACHED    7   // cible atteinte avant l'entrée
#define R_INVALID_LEVELS    8
#define R_MIN_STOP          9
#define R_MAX_STOP          10
#define R_DAY_LIMIT         11
#define R_FVG_INVALID       12
#define R_WINDOW_END        13
#define R_SL_BEFORE_ENTRY   14
#define R_NO_SWEEP          15  // FVG sans prise de liquidité préalable
#define R_AMBIGUOUS         16  // entrée et cible sur la même bougie (book conservateur)

struct OJEvent
  {
   int               code;
   int               slot;     // -1 : aucun
   int               dir;
   int               reason;
   int               aux;      // détail (statut FVG, source de liquidité, n° de macro...)
   long              id;
   long              st;       // heure stratégie
   datetime          srv;      // heure serveur de la bougie traitée
   double            p1;
   double            p2;
   double            p3;
   double            p4;
  };

string OprReasonText(const int r)
  {
   switch(r)
     {
      case R_NO_OPR:          return "OPR non finalisé (incomplet ou sans données)";
      case R_TRADE_DISABLED:  return "aucune règle d'entrée configurée pour cet OPR";
      case R_WRONG_DIR:       return "FVG dans le sens opposé au biais";
      case R_OUTSIDE_MACRO:   return "FVG formé hors d'une macro";
      case R_MACRO_USED:      return "macro déjà tradée (1 macro = 1 trade)";
      case R_IN_POSITION:     return "position déjà ouverte";
      case R_TARGET_REACHED:  return "cible atteinte avant l'entrée : pas de trade";
      case R_INVALID_LEVELS:  return "niveaux incohérents (entrée/stop/cible)";
      case R_MIN_STOP:        return "stop inférieur au minimum";
      case R_MAX_STOP:        return "stop supérieur au maximum";
      case R_DAY_LIMIT:       return "limite de trades journalière atteinte";
      case R_FVG_INVALID:     return "FVG d'entrée invalidé avant l'exécution";
      case R_WINDOW_END:      return "fin de la fenêtre de trading";
      case R_SL_BEFORE_ENTRY: return "niveau du stop dépassé avant l'entrée";
      case R_NO_SWEEP:        return "confirmation manquante : aucune prise de liquidité";
      case R_AMBIGUOUS:       return "entrée et cible touchées sur la même bougie (book conservateur)";
      default:                return "";
     }
  }

string OprDirText(const int dir) { return dir > 0 ? "ACHAT" : (dir < 0 ? "VENTE" : "-"); }
string OprFvgKind(const int dir) { return dir > 0 ? "haussier " : "baissier "; }

//+------------------------------------------------------------------+
//| Libellé complet d'un événement                                   |
//+------------------------------------------------------------------+
string OprEventText(const OJEvent &e, const string slotName, const int digits)
  {
   string px1 = DoubleToString(e.p1, digits);
   string px2 = DoubleToString(e.p2, digits);
   string px3 = DoubleToString(e.p3, digits);
   switch(e.code)
     {
      case J_DAY_START:        return "nouvelle journée de session";
      case J_OPR_BUILDING:     return slotName + " : OPR en cours de calcul";
      case J_OPR_FINAL:        return slotName + " : OPR finalisé, High " + px1 + " / Low " + px2;
      case J_OPR_INCOMPLETE:   return slotName + " : OPR incomplet (historique insuffisant), non utilisé";
      case J_OPR_NODATA:       return slotName + " : OPR sans données (aucune bougie dans la plage)";
      case J_ASIA_FINAL:       return "range asiatique finalisé, High " + px1 + " / Low " + px2;
      case J_ASIA_FVG:         return "premier FVG M15 asiatique identifié : " + OprFvgKind(e.dir) + px2 + " - " + px1;
      case J_ASIA_FVG_NONE:    return "aucun FVG M15 dans la plage asiatique";
      case J_MIDNIGHT_FVG:     return "FPFVG M1 de minuit identifié : " + OprFvgKind(e.dir) + px2 + " - " + px1;
      case J_CTX_ABOVE:        return slotName + " : prix au-dessus de l'OPR High (" + px1 + ")";
      case J_CTX_BELOW:        return slotName + " : prix sous l'OPR Low (" + px2 + ")";
      case J_CTX_INSIDE:       return slotName + " : prix à l'intérieur de l'OPR";
      case J_FVG_DETECTED:     return StringFormat("FVG M%d %s détecté : ", e.aux, e.dir > 0 ? "haussier" : "baissier") + px2 + " - " + px1;
      case J_FVG_STATUS:       return StringFormat("FVG M%d %s ", e.aux / 10, e.dir > 0 ? "haussier" : "baissier") + px2 + " - " + px1 +
                                         " : " + OprFvgStatusText(e.aux % 10);
      case J_WINDOW_OPEN:      return slotName + " : ouverture de la fenêtre de trading";
      case J_WINDOW_CLOSE:     return slotName + " : fermeture de la fenêtre de trading";
      case J_MACRO_OPEN:       return slotName + StringFormat(" : début de la macro n°%d", e.aux + 1);
      case J_MACRO_CLOSE:      return slotName + StringFormat(" : fin de la macro n°%d", e.aux + 1);
      case J_OBS_OPEN:         return "début de la fenêtre d'observation (information uniquement)";
      case J_OBS_CLOSE:        return "fin de la fenêtre d'observation";
      case J_BIAS:             return slotName + " : biais " + OprDirText(e.dir) + " (prix " + px1 + (e.dir > 0 ? " au-dessus de l'OPR High " + px2 : " sous l'OPR Low " + px3) + ")";
      case J_BIAS_CONSOL:      return slotName + " : prix dans l'OPR à l'ouverture de la fenêtre (consolidation), attente d'une clôture hors de l'OPR";
      case J_BIAS_BREAKOUT:    return slotName + " : clôture hors de l'OPR à " + px1 + ", biais " + OprDirText(e.dir);
      case J_SWEEP:            return slotName + " : liquidité prise (" + OprLiqSrcText(e.aux) + " " + px1 + ")";
      case J_FVG_CANDIDATE:    return slotName + " : FVG candidat " + OprDirText(e.dir) + " " + px2 + " - " + px1;
      case J_FVG_IGNORED:      return slotName + " : FVG ignoré, " + OprReasonText(e.reason);
      case J_ENTRY_REJECTED:   return slotName + " : entrée rejetée, " + OprReasonText(e.reason);
      case J_ENTRY_AUTHORIZED: return slotName + " : entrée autorisée " + OprDirText(e.dir) + ", toutes les conditions sont remplies : entrée " + px1 + " stop " + px2 + " cible " + px3;
      case J_SETUP_CANCELLED:  return slotName + " : setup annulé, " + OprReasonText(e.reason);
      case J_TRADE_FILLED:     return slotName + " : trade " + OprDirText(e.dir) + " exécuté (book) à " + px1;
      case J_TRADE_CLOSED:     return slotName + StringFormat(" : trade clôturé (book) %+.2fR", e.p4);
      case J_SESSION_INFO:
        {
         string what = (e.aux == 1) ? "ouverture" : "fermeture";
         return what + " de la session de Londres (information)";
        }
      default:                 return "";
     }
  }

class CJournal
  {
public:
   OJEvent           m_ev[];
   int               m_count;

                     CJournal() { m_count = 0; }

   void              Clear() { m_count = 0; }

   void              Add(const int code, const int slot, const int dir, const int reason, const int aux, const long id,
                         const long st, const datetime srv, const double p1, const double p2, const double p3, const double p4)
     {
      if(m_count >= ArraySize(m_ev))
         ArrayResize(m_ev, m_count + 32);
      m_ev[m_count].code   = code;
      m_ev[m_count].slot   = slot;
      m_ev[m_count].dir    = dir;
      m_ev[m_count].reason = reason;
      m_ev[m_count].aux    = aux;
      m_ev[m_count].id     = id;
      m_ev[m_count].st     = st;
      m_ev[m_count].srv    = srv;
      m_ev[m_count].p1     = p1;
      m_ev[m_count].p2     = p2;
      m_ev[m_count].p3     = p3;
      m_ev[m_count].p4     = p4;
      m_count++;
     }
  };

#endif // OPR_JOURNAL_MQH
//+------------------------------------------------------------------+
//=== fin OPR_Journal.mqh ===

//=== début OPR_Engine.mqh ===
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

class CLondonOprEngine
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

                     CLondonOprEngine() { m_day = 0; m_firstT = 0; m_bars = 0; logContext = true; logAllFvg = false; }

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
//=== fin OPR_Engine.mqh ===

//+------------------------------------------------------------------+
//| v2.40 : modèles de « ICT Ultimate Pro v6.20 » (même auteur)      |
//|   - Silver Bullet (M5, fenêtres 03-04 / 10-11 / 14-15 NY) :      |
//|     sweep confirmé -> MSS + displacement -> 1er FVG de la jambe  |
//|   - Macro Breaker (M1, macros ICT xx:20-xx:40 / xx:50-xx:10) :   |
//|     stop hunt -> breaker confirmé par le corps -> entrée au bord |
//|     (Unicorn si FVG dans le breaker), cible avant entrée = rien  |
//| Modules repris de la v6.20 (détection uniquement), renommés avec |
//| le préfixe V6. Exécution, risque, filtres, ML et SQLite : chaîne |
//| de décision d'ICT NAS (voir V6Bridge).                           |
//+------------------------------------------------------------------+
//=== début V6_Common.mqh ===
#ifndef ICTV6_COMMON_MQH
#define ICTV6_COMMON_MQH


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

//--- Mode d'entree Silver Bullet
enum ENUM_ENTRY_MODE
{
   ENTRY_FVG_TOP        = 0,  // ordre limite sur le bord du FVG
   ENTRY_FVG_CE         = 1,  // ordre limite sur le consequent encroachment (50 % du FVG)
   ENTRY_MARKET_ON_MSS  = 2   // au marche des la confirmation MSS
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

//--- Types de niveaux de liquidite / reference
enum ENUM_V6_LIQ
{
   V6L_PDH = 0, V6L_PDL,
   V6L_PWH,     V6L_PWL,
   V6L_ASIA_HIGH,   V6L_ASIA_LOW,
   V6L_LONDON_HIGH, V6L_LONDON_LOW,
   V6L_NYAM_HIGH,   V6L_NYAM_LOW,
   V6L_EQ_HIGH,     V6L_EQ_LOW,
   V6L_IPDA_HIGH,   V6L_IPDA_LOW,
   V6L_HTF_SWING_HIGH, V6L_HTF_SWING_LOW,
   V6L_LTF_SWING_HIGH, V6L_LTF_SWING_LOW,
   V6L_M1_SWING_HIGH,  V6L_M1_SWING_LOW,
   V6L_OPR_HIGH,   V6L_OPR_LOW,
   V6L_TBR_HIGH,   V6L_TBR_LOW,
   V6L_NDOG_HIGH,  V6L_NDOG_LOW,
   V6L_NWOG_HIGH,  V6L_NWOG_LOW,
   V6L_SD_TARGET
};

//--- Niveau de liquidite
struct SV6Level
{
   double        price;
   int           rank;     // 3 = PDH/PDL/PWH/PWL/IPDA, 2 = session/equal/HTF swing/OPR/NDOG, 1 = swing LTF / SD
   ENUM_V6_LIQ type;
   datetime      time;
   bool          isHigh;
};

//--- Sweep de liquidite detecte
struct SV6Sweep
{
   bool          found;
   double        level;
   int           rank;
   ENUM_V6_LIQ type;
   datetime      levelTime;
   int           extremeIdx;        // index serie de l'extreme du sweep
   double        extreme;
   datetime      extremeTime;
   int           episodeNewestIdx;  // index de la derniere bougie sous/au-dessus du niveau
   int           episodeBars;
   double        penetrationATR;
};

//--- Market Structure Shift
struct SV6MSS
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
struct SV6FVG
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
struct SV6Breaker
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
struct SV6Setup
{
   bool            valid;
   ENUM_SETUP_TYPE setupType;
   ENUM_ICT_DIR    dir;
   ENUM_SB_WINDOW  window;
   datetime        windowStart;
   datetime        windowEnd;
   int             macroId;        // HHMM NY du debut de macro, 0 si aucune
   bool            macroHighProb;
   SV6Sweep          sweep;
   SV6MSS            mss;
   SV6FVG            fvg;
   SV6Breaker        breaker;
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
   int             tpSource;       // ENUM_V6_LIQ ou -1 pour RR fixe
   string          refLevelName;
   string          id;
   string          rejectReason;
};

//+------------------------------------------------------------------+
//| Utilitaires                                                      |
//+------------------------------------------------------------------+
string V6DirToStr(const ENUM_ICT_DIR d)
{
   if(d == DIR_BUY)  return "BUY";
   if(d == DIR_SELL) return "SELL";
   return "NONE";
}

string V6SetupTypeToStr(const ENUM_SETUP_TYPE t)
{
   return (t == SETUP_MACRO_BREAKER) ? "MB" : "SB";
}

string V6WindowToStr(const ENUM_SB_WINDOW w)
{
   switch(w)
   {
      case WIN_LONDON: return "LONDON";
      case WIN_NY_AM:  return "NY_AM";
      case WIN_NY_PM:  return "NY_PM";
      default:         return "NONE";
   }
}

string V6LiqTypeToStr(const int t)
{
   switch(t)
   {
      case V6L_PDH: return "PDH";               case V6L_PDL: return "PDL";
      case V6L_PWH: return "PWH";               case V6L_PWL: return "PWL";
      case V6L_ASIA_HIGH: return "ASIA_H";      case V6L_ASIA_LOW: return "ASIA_L";
      case V6L_LONDON_HIGH: return "LONDON_H";  case V6L_LONDON_LOW: return "LONDON_L";
      case V6L_NYAM_HIGH: return "NYAM_H";      case V6L_NYAM_LOW: return "NYAM_L";
      case V6L_EQ_HIGH: return "EQH";           case V6L_EQ_LOW: return "EQL";
      case V6L_IPDA_HIGH: return "IPDA_H";      case V6L_IPDA_LOW: return "IPDA_L";
      case V6L_HTF_SWING_HIGH: return "HTF_SH"; case V6L_HTF_SWING_LOW: return "HTF_SL";
      case V6L_LTF_SWING_HIGH: return "LTF_SH"; case V6L_LTF_SWING_LOW: return "LTF_SL";
      case V6L_M1_SWING_HIGH: return "M1_SH";   case V6L_M1_SWING_LOW: return "M1_SL";
      case V6L_OPR_HIGH: return "OPR_H";        case V6L_OPR_LOW: return "OPR_L";
      case V6L_TBR_HIGH: return "TBR_H";        case V6L_TBR_LOW: return "TBR_L";
      case V6L_NDOG_HIGH: return "NDOG_H";      case V6L_NDOG_LOW: return "NDOG_L";
      case V6L_NWOG_HIGH: return "NWOG_H";      case V6L_NWOG_LOW: return "NWOG_L";
      case V6L_SD_TARGET: return "SD";
      case -1: return "FIXED_RR";
      default: return "UNKNOWN";
   }
}

double V6NormPrice(const string sym, const double p)
{
   int d = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   return NormalizeDouble(p, d);
}


double V6BodyOf(const MqlRates &r) { return MathAbs(r.close - r.open); }
double V6BodyTop(const MqlRates &r) { return MathMax(r.open, r.close); }
double V6BodyBottom(const MqlRates &r) { return MathMin(r.open, r.close); }

string V6TsToStr(const datetime t) { return TimeToString(t, TIME_DATE | TIME_MINUTES); }

string V6D2(const double v, const int digits = 2) { return DoubleToString(v, digits); }

void V6ResetSetup(SV6Setup &s)
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

#endif // ICTV6_COMMON_MQH
//=== fin V6_Common.mqh ===

//=== début V6_SessionClock.mqh ===
#ifndef ICTV6_SESSIONCLOCK_MQH
#define ICTV6_SESSIONCLOCK_MQH

//+------------------------------------------------------------------+
//| CV6Clock : horloge des modèles v6.20 (fenêtres Silver Bullet,    |
//| table des macros ICT). Repris de CSessionClock (v6.20) ; les|
//| conversions serveur <-> New York passent par le CTimeManager     |
//| d'ICT NAS (un seul réglage de fuseau : InpServerTZ).             |
//+------------------------------------------------------------------+
#define ICTV6_MAX_MACROS 32

class CV6Clock
{
private:
   CTimeManager *m_tm;
   bool     m_useLondon;
   bool     m_useNYAM;
   bool     m_useNYPM;

   //--- table des macros (heure NY)
   int      m_mId[ICTV6_MAX_MACROS];
   int      m_mStart[ICTV6_MAX_MACROS];
   int      m_mEnd[ICTV6_MAX_MACROS];
   bool     m_mHigh[ICTV6_MAX_MACROS];
   bool     m_mEnabled[ICTV6_MAX_MACROS];
   string   m_mName[ICTV6_MAX_MACROS];
   int      m_mCount;

   void AddMacro(const int id, const int startMin, const int endMin, const bool highProb, const string name)
   {
      if(m_mCount >= ICTV6_MAX_MACROS) return;
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

   static datetime DayStartOf(const datetime t)
   {
      long v = (long)t;
      return (datetime)(v - (v % 86400));
   }

public:
   CV6Clock()
   {
      m_tm = NULL;
      m_useLondon = true; m_useNYAM = true; m_useNYPM = true;
      BuildMacroTable();
   }

   void Init(CTimeManager *tm, const bool useLondon, const bool useNYAM, const bool useNYPM, const string enabledMacros)
   {
      m_tm = tm;
      m_useLondon = useLondon;
      m_useNYAM = useNYAM;
      m_useNYPM = useNYPM;
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
   int EnabledCount()
   {
      int n = 0;
      for(int i = 0; i < m_mCount; i++) if(m_mEnabled[i]) n++;
      return n;
   }

   datetime ServerToNY(const datetime srv) { return m_tm.ServerToNY(srv); }
   datetime NYToServer(const datetime ny)  { return m_tm.NYToServer(ny); }

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
   datetime NYDayStartServer(const datetime srv)
   {
      return NYToServer(DayStartOf(ServerToNY(srv)));
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

   //--- Profil hebdomadaire : lundi 0, mardi/mercredi/jeudi +1, vendredi -1, week-end -2
   int DayOfWeekScore(const datetime srv)
   {
      int d = NYDayOfWeek(srv);
      if(d == 2 || d == 3 || d == 4) return 1;
      if(d == 1) return 0;
      if(d == 5) return -1;
      return -2;
   }
};

#endif // ICTV6_SESSIONCLOCK_MQH
//=== fin V6_SessionClock.mqh ===

//=== début V6_MarketStructure.mqh ===
#ifndef ICTV6_MARKETSTRUCTURE_MQH
#define ICTV6_MARKETSTRUCTURE_MQH

class CV6Structure
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
                       const double dispBodyATR, const double atr, const int s, SV6MSS &out)
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
         body = MathMax(body, V6BodyOf(r[j]));
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

#endif // ICTV6_MARKETSTRUCTURE_MQH
//=== fin V6_MarketStructure.mqh ===

//=== début V6_FVG.mqh ===
#ifndef ICTV6_FVG_MQH
#define ICTV6_FVG_MQH

class CV6FVGTools
{
public:
   //--- Tous les FVG dans la jambe [newestIdx .. oldestIdx] (indices serie).
   //--- Bougie du milieu m : plus vieille m+1, plus recente m-1.
   //--- BUY : low[m-1] > high[m+1] + minSize.
   //--- v6.20 : requireBody rend optionnel le corps directionnel de la bougie centrale.
   //--- Les FVG sont empiles par index croissant : out[n-1] est le PLUS ANCIEN de la
   //--- jambe, c'est-a-dire le PREMIER forme apres le sweep (1st FVG du displacement).
   static int FindInLeg(const ENUM_ICT_DIR dir, const MqlRates &r[], const int count,
                        const int newestIdx, const int oldestIdx, const double minSize, SV6FVG &out[],
                        const bool requireBody = true)
   {
      ArrayResize(out, 0);
      int from = MathMax(2, newestIdx - 1);
      int to   = MathMin(count - 2, oldestIdx - 1);
      for(int m = from; m <= to; m++)
      {
         SV6FVG f;
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
                                  const SV6FVG &f, const int lookbackBars, const double minSize)
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
   static void CheckMitigation(const ENUM_ICT_DIR dir, const MqlRates &r[], SV6FVG &f)
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

#endif // ICTV6_FVG_MQH
//=== fin V6_FVG.mqh ===

//=== début V6_LiquidityMap.mqh ===
#ifndef ICTV6_LIQUIDITYMAP_MQH
#define ICTV6_LIQUIDITYMAP_MQH

class CV6LiqMap
{
private:
   SV6Level m_levels[];
   int       m_count;
   string    m_sym;
   double    m_drLow;
   double    m_drHigh;
   double    m_mergeTol;

public:
   //--- Ajoute un niveau (fusion si un niveau proche existe deja, le rang le plus eleve gagne)
   void AddLevel(const double price, const int rank, const ENUM_V6_LIQ type, const datetime time, const bool isHigh)
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

   void AddSession(CV6Clock &clock, const MqlRates &ltf[], const int ltfCount, const datetime nowSrv,
                   const int startMin, const int endMin, const ENUM_V6_LIQ hiType, const ENUM_V6_LIQ loType)
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
   CV6LiqMap() { m_count = 0; m_sym = ""; m_drLow = 0; m_drHigh = 0; m_mergeTol = 0; }

   int Count() { return m_count; }
   void Get(const int i, SV6Level &lv) { lv = m_levels[i]; }
   double DealingRangeLow()  { return m_drLow; }
   double DealingRangeHigh() { return m_drHigh; }

   //--- Position dans le dealing range : 0 = bas, 0.5 = equilibre, 1 = haut
   double PremiumDiscountPct(const double price)
   {
      if(m_drHigh <= m_drLow) return 0.5;
      return (price - m_drLow) / (m_drHigh - m_drLow);
   }

   void Build(const string sym, CV6Clock &clock, const datetime nowSrv,
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
         AddLevel(d1[1].high, 3, V6L_PDH, d1[1].time, true);
         AddLevel(d1[1].low,  3, V6L_PDL, d1[1].time, false);
      }
      double pwh = iHigh(sym, PERIOD_W1, 1);
      double pwl = iLow(sym, PERIOD_W1, 1);
      datetime pwt = iTime(sym, PERIOD_W1, 1);
      if(pwh > 0 && pwl > 0)
      {
         AddLevel(pwh, 3, V6L_PWH, pwt, true);
         AddLevel(pwl, 3, V6L_PWL, pwt, false);
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
         AddLevel(hi, 3, V6L_IPDA_HIGH, hiT, true);
         AddLevel(lo, 3, V6L_IPDA_LOW,  loT, false);
         if(L == 0) { m_drLow = lo; m_drHigh = hi; }
      }

      //--- Sessions du jour NY (minutes relatives a minuit NY ; negatif = veille)
      AddSession(clock, ltf, ltfCount, nowSrv, -240, 0,   V6L_ASIA_HIGH,   V6L_ASIA_LOW);    // Asie 20:00-00:00
      AddSession(clock, ltf, ltfCount, nowSrv, 120,  300, V6L_LONDON_HIGH, V6L_LONDON_LOW);  // Londres 02:00-05:00
      AddSession(clock, ltf, ltfCount, nowSrv, 420,  720, V6L_NYAM_HIGH,   V6L_NYAM_LOW);    // NY AM 07:00-12:00

      //--- Swings HTF (rang 2)
      int added = 0;
      for(int i = swingStrength + 1; i < htfCount - swingStrength && added < 16; i++)
      {
         if(CV6Structure::IsSwingHigh(htf, i, swingStrength, htfCount)) { AddLevel(htf[i].high, 2, V6L_HTF_SWING_HIGH, htf[i].time, true);  added++; }
         if(CV6Structure::IsSwingLow(htf, i, swingStrength, htfCount))  { AddLevel(htf[i].low,  2, V6L_HTF_SWING_LOW,  htf[i].time, false); added++; }
      }

      //--- Swings LTF (rang 1) et equal highs/lows (rang 2)
      double shP[]; datetime shT[]; double slP[]; datetime slT[];
      int nsh = 0, nsl = 0;
      int lim = MathMin(ltfCount - swingStrength - 1, 240);
      for(int i = swingStrength + 1; i <= lim && (nsh < 14 || nsl < 14); i++)
      {
         if(nsh < 14 && CV6Structure::IsSwingHigh(ltf, i, swingStrength, ltfCount))
         {
            ArrayResize(shP, nsh + 1); ArrayResize(shT, nsh + 1);
            shP[nsh] = ltf[i].high; shT[nsh] = ltf[i].time; nsh++;
         }
         if(nsl < 14 && CV6Structure::IsSwingLow(ltf, i, swingStrength, ltfCount))
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
         if(eq) AddLevel(shP[a], 2, V6L_EQ_HIGH, shT[a], true);
         else   AddLevel(shP[a], 1, V6L_LTF_SWING_HIGH, shT[a], true);
      }
      for(int a = 0; a < nsl; a++)
      {
         bool eq = false;
         for(int b = a + 1; b < nsl; b++)
            if(MathAbs(slP[a] - slP[b]) <= eqTol) { eq = true; break; }
         if(eq) AddLevel(slP[a], 2, V6L_EQ_LOW, slT[a], false);
         else   AddLevel(slP[a], 1, V6L_LTF_SWING_LOW, slT[a], false);
      }
   }

   //--- Sweeps confirmes. dir = DIR_BUY cherche les prises de liquidite sous les lows
   //--- (sell-side), dir = DIR_SELL au-dessus des highs (buy-side).
   int FindSweeps(const ENUM_ICT_DIR dir, const MqlRates &r[], const int count, const double atr,
                  const int lookback, const double minPenATR, const int confirmBars,
                  const int maxEpisodeBars, const datetime notOlderThan, SV6Sweep &out[])
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
            if(swap) { SV6Sweep t = out[a]; out[a] = out[b]; out[b] = t; }
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
         if(price == 0 || d < MathAbs(price - entry)) { price = extras[i]; type = (int)V6L_SD_TARGET; }
      }
      return (price > 0);
   }

   //--- Equal highs/lows non balayes au-dela de 'price' dans le sens du stop
   bool HasEqualLevelBeyond(const ENUM_ICT_DIR dir, const double price, const double maxDist, const double excludeLevel, const double tol)
   {
      for(int i = 0; i < m_count; i++)
      {
         if(dir == DIR_BUY  && m_levels[i].type != V6L_EQ_LOW)  continue;
         if(dir == DIR_SELL && m_levels[i].type != V6L_EQ_HIGH) continue;
         if(MathAbs(m_levels[i].price - excludeLevel) <= tol) continue;
         double d = (dir == DIR_BUY) ? (price - m_levels[i].price) : (m_levels[i].price - price);
         if(d > 0 && d <= maxDist) return true;
      }
      return false;
   }

   //--- Ajoute les swings d'une serie (ex: M1) comme niveaux de rang 1
   void AddSwings(const MqlRates &r[], const int count, const int strength, const int maxEach,
                  const ENUM_V6_LIQ hiType, const ENUM_V6_LIQ loType)
   {
      int nh = 0, nl = 0;
      int lim = MathMin(count - strength - 1, 300);
      for(int i = strength + 1; i <= lim && (nh < maxEach || nl < maxEach); i++)
      {
         if(nh < maxEach && CV6Structure::IsSwingHigh(r, i, strength, count)) { AddLevel(r[i].high, 1, hiType, r[i].time, true);  nh++; }
         if(nl < maxEach && CV6Structure::IsSwingLow(r, i, strength, count))  { AddLevel(r[i].low,  1, loType, r[i].time, false); nl++; }
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

#endif // ICTV6_LIQUIDITYMAP_MQH
//=== fin V6_LiquidityMap.mqh ===

//=== début V6_Reference.mqh ===
#ifndef ICTV6_REFERENCE_MQH
#define ICTV6_REFERENCE_MQH

#define ICTV6_OPR_COUNT 4

class CV6RefLevels
{
private:
   CV6Clock *m_clock;
   double   m_midnightOpen;
   double   m_open0730;
   double   m_ndogHigh, m_ndogLow;
   double   m_nwogHigh, m_nwogLow;
   double   m_pdHigh, m_pdLow;
   double   m_oprHigh[ICTV6_OPR_COUNT], m_oprLow[ICTV6_OPR_COUNT];
   bool     m_oprValid[ICTV6_OPR_COUNT];
   int      m_oprStart[ICTV6_OPR_COUNT], m_oprEnd[ICTV6_OPR_COUNT];
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
   CV6RefLevels()
   {
      m_clock = NULL; m_midnightOpen = 0; m_open0730 = 0; m_ndogHigh = 0; m_ndogLow = 0; m_nwogHigh = 0; m_nwogLow = 0;
      m_pdHigh = 0; m_pdLow = 0; m_tbrHigh = 0; m_tbrLow = 0; m_tbrValid = false; m_adr5 = 0; m_dayHigh = 0; m_dayLow = 0;
      m_useOPR = true; m_useTBR = true; m_useNDOG = true;
      m_ndogTime = 0; m_nwogTime = 0;
      m_oprStart[0] = 90;  m_oprEnd[0] = 120;   // 01:30-02:00 Londres
      m_oprStart[1] = 420; m_oprEnd[1] = 450;   // 07:00-07:30 pre-market
      m_oprStart[2] = 570; m_oprEnd[2] = 600;   // 09:30-10:00 AM
      m_oprStart[3] = 810; m_oprEnd[3] = 840;   // 13:30-14:00 PM
      for(int i = 0; i < ICTV6_OPR_COUNT; i++) { m_oprHigh[i] = 0; m_oprLow[i] = 0; m_oprValid[i] = false; }
   }

   void Init(CV6Clock *clock, const bool useOPR, const bool useTBR, const bool useNDOG)
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
      for(int i = 0; i < ICTV6_OPR_COUNT; i++)
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
   void PushToMap(CV6LiqMap &map, const datetime nowSrv)
   {
      datetime s, e;
      for(int i = 0; i < ICTV6_OPR_COUNT; i++)
      {
         if(!m_oprValid[i]) continue;
         m_clock.NYRangeToServer(nowSrv, m_oprStart[i], m_oprEnd[i], s, e);
         map.AddLevel(m_oprHigh[i], 2, V6L_OPR_HIGH, e, true);
         map.AddLevel(m_oprLow[i],  2, V6L_OPR_LOW,  e, false);
      }
      //--- deviations standard de l'opening range AM (2, 2.5, 4, 6) comme cibles
      if(m_oprValid[2])
      {
         m_clock.NYRangeToServer(nowSrv, m_oprStart[2], m_oprEnd[2], s, e);
         double rng = m_oprHigh[2] - m_oprLow[2];
         double sd[] = {2.0, 2.5, 4.0, 6.0};
         for(int k = 0; k < ArraySize(sd); k++)
         {
            map.AddLevel(m_oprHigh[2] + sd[k] * rng, 1, V6L_SD_TARGET, e, true);
            map.AddLevel(m_oprLow[2]  - sd[k] * rng, 1, V6L_SD_TARGET, e, false);
         }
      }
      if(m_tbrValid)
      {
         m_clock.NYRangeToServer(nowSrv, 492, 552, s, e);
         map.AddLevel(m_tbrHigh, 2, V6L_TBR_HIGH, e, true);
         map.AddLevel(m_tbrLow,  2, V6L_TBR_LOW,  e, false);
      }
      if(m_ndogHigh > 0)
      {
         map.AddLevel(m_ndogHigh, 2, V6L_NDOG_HIGH, m_ndogTime, true);
         map.AddLevel(m_ndogLow,  2, V6L_NDOG_LOW,  m_ndogTime, false);
      }
      if(m_nwogHigh > 0)
      {
         map.AddLevel(m_nwogHigh, 2, V6L_NWOG_HIGH, m_nwogTime, true);
         map.AddLevel(m_nwogLow,  2, V6L_NWOG_LOW,  m_nwogTime, false);
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
      for(int i = 0; i < ICTV6_OPR_COUNT; i++)
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
      string s = StringFormat("MO %s | 07:30 %s | ADR5 %s utilise %.0f%%", V6D2(m_midnightOpen, _Digits), V6D2(m_open0730, _Digits), V6D2(m_adr5, _Digits), ADRUsedPct());
      if(m_ndogHigh > 0) s += StringFormat(" | NDOG %s-%s", V6D2(m_ndogLow, _Digits), V6D2(m_ndogHigh, _Digits));
      for(int i = 0; i < ICTV6_OPR_COUNT; i++) if(m_oprValid[i]) s += StringFormat(" | OPR%d %s-%s", i, V6D2(m_oprLow[i], _Digits), V6D2(m_oprHigh[i], _Digits));
      return s;
   }
};

#endif // ICTV6_REFERENCE_MQH
//=== fin V6_Reference.mqh ===

//=== début V6_SetupSilverBullet.mqh ===
#ifndef ICTV6_SETUPSILVERBULLET_MQH
#define ICTV6_SETUPSILVERBULLET_MQH

struct SV6SBParams
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
void V6BuildSDTargets(const ENUM_ICT_DIR dir, const double origin, const double extreme, double &levels[])
{
   double sd[] = {2.0, 2.5, 4.0};
   ArrayResize(levels, 0);
   double rng = MathAbs(origin - extreme);
   if(rng <= 0) return;
   ArrayResize(levels, ArraySize(sd));
   for(int i = 0; i < ArraySize(sd); i++)
      levels[i] = (dir == DIR_BUY) ? extreme + sd[i] * rng : extreme - sd[i] * rng;
}

class CV6SilverBullet
{
private:
   SV6SBParams      m_p;
   string            m_sym;
   CV6Clock    *m_clock;
   CV6LiqMap    *m_liq;
   CV6RefLevels *m_ref;

   bool BuildSetup(const ENUM_ICT_DIR dir, const MqlRates &r[], const int count, const SV6Sweep &sw, const SV6MSS &mss,
                   const SV6FVG &fvg, const double atr, const double atrD1, const double ask, const double bid,
                   const double minStopDist, const datetime nowSrv, SV6Setup &s, string &why)
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
      s.needsOBConfirm = false;   // ICT NAS : le mode « OB apres le FVG » n'est pas porte
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
      s.entry = V6NormPrice(m_sym, price);

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
      s.bpr = m_p.useBPRBonus && CV6FVGTools::HasOpposingOverlap(dir, r, count, fvg, 30, m_p.fvgMinSizeATR * atr);

      //--- stop derriere l'extreme du sweep + buffer
      double buffer = m_p.slBufferATR * atr + (ask - bid);
      s.sl = V6NormPrice(m_sym, (dir == DIR_BUY) ? sw.extreme - buffer : sw.extreme + buffer);
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
         if(m_p.useSDTargets) V6BuildSDTargets(dir, mss.brokenLevel, sw.extreme, sdLevels);
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
      s.tp = V6NormPrice(m_sym, tpPrice);
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

      s.id = StringFormat("SB_%s_%s_%s_%I64d", m_sym, TimeToString(s.windowStart, TIME_DATE | TIME_MINUTES), V6DirToStr(dir), (long)sw.extremeTime);
      StringReplace(s.id, " ", "T");
      StringReplace(s.id, ":", "");
      StringReplace(s.id, ".", "");
      s.valid = true;
      return true;
   }

public:
   CV6SilverBullet() { m_sym = ""; m_clock = NULL; m_liq = NULL; m_ref = NULL; }

   void Init(const string sym, CV6Clock *clock, CV6LiqMap *liq, CV6RefLevels *ref, const SV6SBParams &p)
   {
      m_sym = sym; m_clock = clock; m_liq = liq; m_ref = ref; m_p = p;
   }
   //--- v6.20 : permet la 2e passe relachee sans reconstruire l'objet
   void SetParams(const SV6SBParams &p) { m_p = p; }

   //--- Evalue les deux directions. best.valid = true si un setup passe tous les filtres.
   bool Evaluate(const MqlRates &ltf[], const int ltfCount, const double &atrSeries[],
                 const ENUM_ICT_DIR bias, const ENUM_SB_WINDOW window, const datetime winStart, const datetime winEnd,
                 const datetime nowSrv, const double atr, const double atrD1, const double minStopDist,
                 SV6Setup &best, string &rejectSummary)
   {
      V6ResetSetup(best);
      rejectSummary = "";
      if(atr <= 0 || ltfCount < 60) { rejectSummary = "donnees insuffisantes"; return false; }

      double ask = SymbolInfoDouble(m_sym, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_sym, SYMBOL_BID);
      datetime notOlderThan = (datetime)((long)winStart - (long)m_p.preSweepMinutes * 60);
      int dow = m_clock.DayOfWeekScore(nowSrv);
      ENUM_ICT_DIR utState = m_p.utbotConfirm ? CV6Structure::UTBotState(ltf, atrSeries, ltfCount, m_p.utbotKey) : DIR_NONE;

      ENUM_ICT_DIR dirs[2];
      dirs[0] = DIR_BUY; dirs[1] = DIR_SELL;
      for(int d = 0; d < 2; d++)
      {
         ENUM_ICT_DIR dir = dirs[d];
         string dirReason = "";
         if(m_p.requireHTFAlign && bias != DIR_NONE && bias != dir)
         {
            rejectSummary += V6DirToStr(dir) + ":biais HTF oppose; ";
            continue;
         }
         if(m_p.utbotConfirm && utState != DIR_NONE && utState != dir)
         {
            rejectSummary += V6DirToStr(dir) + ":UT Bot oppose; ";
            continue;
         }

         SV6Sweep sweeps[];
         int ns = m_liq.FindSweeps(dir, ltf, ltfCount, atr, m_p.sweepLookbackBars, m_p.sweepMinATR,
                                   m_p.sweepConfirmBars, m_p.sweepMaxEpisodeBars, notOlderThan, sweeps);
         if(ns == 0) { rejectSummary += V6DirToStr(dir) + ":aucun sweep; "; continue; }

         for(int k = 0; k < ns; k++)
         {
            SV6MSS mss;
            if(!CV6Structure::FindMSS(dir, ltf, ltfCount, sweeps[k].extremeIdx, sweeps[k].extreme, m_p.mssMaxBars,
                                          m_p.mssMinRangeATR, m_p.dispBodyATR, atr, m_p.swingStrength, mss))
            {
               if(dirReason == "") dirReason = "pas de MSS avec displacement";
               continue;
            }
            SV6FVG fvgs[];
            int nf = CV6FVGTools::FindInLeg(dir, ltf, ltfCount, mss.barIdx, sweeps[k].extremeIdx,
                                     m_p.fvgMinSizeATR * atr, fvgs, m_p.fvgRequireBody);
            if(nf == 0) { if(dirReason == "" || dirReason == "pas de MSS avec displacement") dirReason = "pas de FVG dans la jambe"; continue; }

            //--- v6.20 : FindInLeg empile par index croissant, donc fvgs[nf-1] est le
            //--- FVG le plus ancien de la jambe = 1ere FVG du displacement.
            bool picked = false;
            for(int q = 0; q < nf && !picked; q++)
            {
               int f = m_p.takeFirstFVG ? (nf - 1 - q) : q;
               SV6Setup s;
               V6ResetSetup(s);
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
         if(dirReason != "") rejectSummary += V6DirToStr(dir) + ":" + dirReason + "; ";
      }
      return best.valid;
   }
};

#endif // ICTV6_SETUPSILVERBULLET_MQH
//=== fin V6_SetupSilverBullet.mqh ===

//=== début V6_SetupMacroBreaker.mqh ===
#ifndef ICTV6_SETUPMACROBREAKER_MQH
#define ICTV6_SETUPMACROBREAKER_MQH

struct SV6MBParams
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

class CV6MacroBreaker
{
private:
   SV6MBParams         m_p;
   string            m_sym;
   CV6Clock    *m_clock;
   CV6LiqMap    *m_liq;
   CV6RefLevels *m_ref;

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

   bool BuildSetup(const ENUM_ICT_DIR dir, const MqlRates &r[], const int count, const SV6Sweep &sw,
                   const double atr, const double atrM5, const double atrD1, const double ask, const double bid,
                   const double minStopDist, const datetime nowSrv, const datetime macroStart, const datetime macroEnd,
                   SV6Setup &s, string &why)
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
         if(dir == DIR_BUY && CV6Structure::IsSwingHigh(r, i, m_p.swingStrength, count) && r[i].high >= sw.extreme + m_p.minRangeATR * atr) { swingIdx = i; break; }
         if(dir == DIR_SELL && CV6Structure::IsSwingLow(r, i, m_p.swingStrength, count) && r[i].low <= sw.extreme - m_p.minRangeATR * atr) { swingIdx = i; break; }
      }
      if(swingIdx < 0) { why = "pas de swing oppose avant le stop hunt"; return false; }

      SV6Breaker b;
      ZeroMemory(b);
      int bc = BreakerCandle(dir, r, swingIdx);
      b.candleIdx = bc;
      b.time = r[bc].time;
      b.top = r[bc].high; b.bottom = r[bc].low;
      b.bodyTop = V6BodyTop(r[bc]); b.bodyBottom = V6BodyBottom(r[bc]);
      b.swingLevel = (dir == DIR_BUY) ? r[swingIdx].high : r[swingIdx].low;

      //--- expansion + confirmation par le corps
      int confirmIdx = -1;
      double body = 0, legExt = (dir == DIR_BUY) ? -1 : DBL_MAX;
      int stop = MathMax(1, ex - m_p.maxBarsToConfirm);
      for(int j = ex - 1; j >= stop; j--)
      {
         if(dir == DIR_BUY  && r[j].low  < sw.extreme) { why = "extreme du sweep viole avant confirmation"; return false; }
         if(dir == DIR_SELL && r[j].high > sw.extreme) { why = "extreme du sweep viole avant confirmation"; return false; }
         body = MathMax(body, V6BodyOf(r[j]));
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
      SV6FVG fvgs[];
      int nf = CV6FVGTools::FindInLeg(dir, r, count, confirmIdx, ex, m_p.fvgMinSizeATR * atr, fvgs, m_p.fvgRequireBody);
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
      s.entry = V6NormPrice(m_sym, price);
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
      s.sl = V6NormPrice(m_sym, sl);
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
      if(m_p.useSDTargets) V6BuildSDTargets(dir, b.swingLevel, sw.extreme, sdLevels);
      if(m_liq.NearestPoolWithExtras(dir, s.entry, minDist + tpBuf, maxDist, sdLevels, tpPrice, tpType))
         tpPrice = (dir == DIR_BUY) ? tpPrice - tpBuf : tpPrice + tpBuf;
      else if(m_p.allowFixedRRFallback)
      {
         tpPrice = (dir == DIR_BUY) ? s.entry + m_p.minRR * s.riskDist : s.entry - m_p.minRR * s.riskDist;
         tpType = -1;
      }
      else { why = "aucune cible atteignable (pas d'entree sans target)"; return false; }
      s.tp = V6NormPrice(m_sym, tpPrice);
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

      s.id = StringFormat("MB_%s_%d_%s_%s_%I64d", m_sym, s.macroId, TimeToString(macroStart, TIME_DATE), V6DirToStr(dir), (long)sw.extremeTime);
      StringReplace(s.id, " ", "T");
      StringReplace(s.id, ":", "");
      StringReplace(s.id, ".", "");
      s.valid = true;
      return true;
   }

public:
   CV6MacroBreaker() { m_sym = ""; m_clock = NULL; m_liq = NULL; m_ref = NULL; }

   void Init(const string sym, CV6Clock *clock, CV6LiqMap *liq, CV6RefLevels *ref, const SV6MBParams &p)
   {
      m_sym = sym; m_clock = clock; m_liq = liq; m_ref = ref; m_p = p;
   }
   //--- v6.20
   void SetParams(const SV6MBParams &p) { m_p = p; }

   //--- Evalue les deux directions sur M1 pour la macro donnee.
   bool Evaluate(const MqlRates &m1[], const int m1Count, const ENUM_ICT_DIR bias,
                 const int macroId, const bool macroHighProb, const datetime macroStart, const datetime macroEnd,
                 const datetime nowSrv, const double atrM1, const double atrM5, const double atrD1, const double minStopDist,
                 SV6Setup &best, string &rejectSummary)
   {
      V6ResetSetup(best);
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
            rejectSummary += V6DirToStr(dir) + ":biais HTF oppose; ";
            continue;
         }
         SV6Sweep sweeps[];
         int ns = m_liq.FindSweeps(dir, m1, m1Count, atrM1, m_p.lookbackBars, m_p.sweepMinATR,
                                   m_p.sweepConfirmBars, m_p.sweepMaxEpisodeBars, notOlderThan, sweeps);
         if(ns == 0) { rejectSummary += V6DirToStr(dir) + ":aucun stop hunt; "; continue; }

         for(int k = 0; k < ns; k++)
         {
            SV6Setup s;
            V6ResetSetup(s);
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
         if(dirReason != "") rejectSummary += V6DirToStr(dir) + ":" + dirReason + "; ";
      }
      return best.valid;
   }
};

#endif // ICTV6_SETUPMACROBREAKER_MQH
//=== fin V6_SetupMacroBreaker.mqh ===

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Général ==="
input bool             InpTradingEnabled  = true;           // Autoriser l'envoi d'ordres (false = observation)
input ENUM_SERVER_TZ   InpServerTZ        = TZ_NY_PLUS_7;   // Fuseau du serveur broker
input int              InpServerGMTOff    = 2;              // Offset GMT serveur (modes GMT fixe / DST UE, heure d'hiver)
input long             InpMagic           = 26092801;       // Magic number

input group "=== Modèles ICT ==="
input bool             InpUseShadow       = true;           // Shadow Model (Reset BSL/SSL)
input bool             InpUseSB           = true;           // Silver Bullet
input ENUM_SB_MODE     InpSBMode          = SB_THREE_WINDOWS; // Fenêtres Silver Bullet
input bool             InpTGIF            = true;           // TGIF : vendredi 14-15, retracement du range hebdo
input double           InpTGIFRetrace     = 0.25;           // TGIF : part du range hebdo visée (0.20-0.30)
input int              InpSBMinLiqWeight  = 3;              // SB : poids minimal de la liquidité prise
input int              InpSBMinTargetWeight = 4;            // SB : poids minimal du pool de liquidité visé
input bool             InpUseLondonOPR    = true;           // London OPR (MOR, 02:50-04:10) : interrupteur général
input ENUM_LONDON_MODE InpLondonMode      = LONDON_PDF;     // London OPR : implémentation (PDF conseillé)
input bool             InpLondonNeedMacro = true;           // London OPR v2.22 : le sweep doit avoir lieu pendant une macro
input bool             InpUseOPR0130      = true;           // OPR 01:30-02:00 (fenêtre 02:00-05:00)
input bool             InpUseOPR0700      = true;           // OPR 07:00-07:30 (fenêtre 07:30-09:30)
input bool             InpUseOPR0930      = true;           // OPR 09:30-10:00 (fenêtre 10:00-12:00)
input bool             InpUseOPR1330      = true;           // OPR 13:30-14:00 (fenêtre 14:00-16:00)
input double           InpMomentumDispATR = 1.2;            // SB Momentum : displacement M5 >= x ATR (v6)
input bool             InpUseERL          = true;           // ERL -> IRL (sweep H1, MSS M5, cible FVG H1)
input int              InpERLLookback     = 10;             // ERL : bougies H1 de référence
input double           InpTargetSTDV      = 2.0;            // Cible des OPR / MOR (STDV)

input group "=== Profil d'entrée ==="
input ENUM_ENTRY_PROFILE InpProfile       = PROFILE_STANDARD; // Profil (Standard conseillé pour démarrer)
input bool             InpUseMomentum     = true;           // Modèle SB Momentum (logique de l'EA v6)
input bool             InpUseKillzoneModel= true;           // Modèle Killzone (tout setup ICT complet en killzone)

input group "=== Profil personnalisé (utilisé si Profil = Personnalisé) ==="
input double           InpScoreMin        = 60.0;           // Score ICT minimal (0-100)
input double           InpMinRR           = 2.0;            // RR minimal vers la cible, modèles ICT (v2.22 : 3)
input double           InpFallbackRR      = 3.0;            // Cible de secours sans DOL (R, 0 = rejet)
input double           InpMaxRR           = 5.0;            // Cible plafonnée à x R (0 = pas de plafond)
input double           InpSLFloorATR      = 0.8;            // SL minimum = x ATR M5 (0 = SL au sweep)
input double           InpSLCapATR        = 2.5;            // SL maximum = x ATR M5 (au-delà : SL bougie 1 du FVG, sinon rejet)
input double           InpTP1R            = 2.0;            // Allègement 50 % à x R (0 = non)
input bool             InpMarketEntry     = false;          // Entrée au marché au lieu de la limite au CE

input group "=== Modèles CRT_TRADE ==="
input bool             InpUseCRT45        = true;           // CRT : modèle 45 minutes (09:23-10:08)
input bool             InpCRTRequireTO    = true;           // CRT 45 min : au-dessus des True Opens -> ventes, en dessous -> achats
input bool             InpUseCRTOPR       = true;           // CRT : sweep au-delà de l'OPR puis retour dans le range
input bool             InpUseCRT0830      = true;           // CRT : macro 08:30 (breaker ou IFVG, trade la réaction à la news)
input bool             InpUseCRT0250      = true;           // CRT : macro 02:50-03:10 -> entrée jusqu'à 04:10
input bool             InpUseCRTPM        = true;           // CRT : macro PM d'impulsion 14:50-15:10
input bool             InpCRT50Rule       = true;           // CRT : entrée au bord du FVG, sortie si clôture au-delà du CE
input bool             InpBlockAccumMacro = true;           // Pas de nouvelle entrée pendant la macro 15:15-15:45
input double           InpCRTMinRR        = 3.0;            // CRT : RR minimal vers la DOL (gestion CRT : reste à la DOL >= 3R)

input group "=== London OPR PDF : modèle (moteur OPR + FVG) ==="
input ENUM_LONDON_MANAGE InpLondonManage  = LM_PDF;         // Gestion des trades (PDF : cible unique)
input double           InpLondonMinRR     = 0.0;            // RR minimal (0 = la cible du PDF est acceptée telle quelle)
input double           InpLOTpStd         = 2.0;            // Cible : déviation standard du MOR (notes : 2 à 2,5)
input bool             InpLORequireMacro  = true;           // Le FVG d'entrée doit se former dans une macro
input bool             InpLOOneTradePerMacro = true;        // 1 macro = 1 trade
input bool             InpLOConsolRequireSweep = true;      // Prix dans le MOR à 2:50 : exiger aussi une prise de liquidité
input double           InpLOStopBufferPts = 0.0;            // Stop : points au-delà du swing (0 = 1 tick)
input double           InpLOMinStopPts    = 0.0;            // Stop minimum en points (0 = aucun)
input double           InpLOMaxStopPts    = 0.0;            // Stop maximum en points (0 = aucun)
input double           InpLOMaxChaseR     = 0.25;           // Entrée au marché tolérée au-delà du niveau (x R)
input int              InpLOGraceMin      = 0;              // Ordre conservé après la fin de la fenêtre (minutes)
input ENUM_OPR_ENTRY_TF    InpLOEntryTF   = OPR_TF_M1;      // Timeframe du FVG d'entrée
input ENUM_OPR_ENTRY_LEVEL InpLOEntryLevel= OPR_ENTRY_EDGE; // Niveau d'entrée dans le FVG
input double           InpLOMinFvgPts     = 0.0;            // FVG d'entrée : taille minimale en points (0 = 1 tick)

input group "=== London OPR PDF : plages horaires (heure de New York) ==="
input string           InpLOAsiaRange     = "20:00-00:00";  // Plage asiatique (1er FVG M15 ; high / low = liquidité)
input string           InpLOLondonRange   = "00:00-06:00";  // Session de Londres (recherche du FPFVG M1 de minuit)
input string           InpLOObsWindow     = "02:50-03:10";  // Fenêtre d'observation (journal uniquement)
input string           InpLOOpr1Range     = "00:00-00:30";  // OPR 1 = MOR (Midnight Opening Range)
input bool             InpLOOpr1Trade     = true;           // OPR 1 : modèle d'entrée actif (PDF London OPR)
input string           InpLOOpr1Window    = "02:50-04:10";  // OPR 1 : fenêtre de trading
input string           InpLOOpr1Macros    = "02:50-03:10,03:20-03:40,03:50-04:10"; // OPR 1 : macros
input string           InpLOOpr2Range     = "07:00-07:30";  // OPR 2 : plage ("" = désactivé)
input bool             InpLOOpr2Trade     = false;          // OPR 2 : modèle d'entrée (aucune règle documentée)
input string           InpLOOpr2Window    = "";             // OPR 2 : fenêtre de trading
input string           InpLOOpr2Macros    = "";             // OPR 2 : macros
input string           InpLOOpr3Range     = "09:30-10:00";  // OPR 3 : plage
input bool             InpLOOpr3Trade     = false;          // OPR 3 : modèle d'entrée (aucune règle documentée)
input string           InpLOOpr3Window    = "";             // OPR 3 : fenêtre de trading
input string           InpLOOpr3Macros    = "";             // OPR 3 : macros
input string           InpLOOpr4Range     = "13:30-14:00";  // OPR 4 : plage
input bool             InpLOOpr4Trade     = false;          // OPR 4 : modèle d'entrée (aucune règle documentée)
input string           InpLOOpr4Window    = "";             // OPR 4 : fenêtre de trading
input string           InpLOOpr4Macros    = "";             // OPR 4 : macros

input group "=== London OPR PDF : FVG de référence et liquidité ==="
input ENUM_OPR_ASIA_RULE InpLOAsiaRule    = OPR_ASIA_C2_IN_RANGE; // FVG asiatique « présenté pendant la plage »
input double           InpLOAsiaMinGapPts = 0.0;            // FVG asiatique : taille minimale en points (0 = 1 tick)
input double           InpLOMidMinGapPts  = 0.0;            // FPFVG M1 de minuit : taille minimale en points (0 = 1 tick)
input bool             InpFPFVGFromEngine = true;           // FPFVG Asie / Midnight du moteur (false = calcul v2.22)
input bool             InpLOLiqM1         = true;           // Liquidité : swings M1 (hauts / bas simples)
input int              InpLOLiqPivotM1    = 1;              // Swings M1 : bougies de chaque côté
input bool             InpLOLiqM15        = true;           // Liquidité : swings M15
input int              InpLOLiqPivotM15   = 1;              // Swings M15 : bougies de chaque côté
input bool             InpLOLiqAsia       = true;           // Liquidité : high / low de la plage asiatique

input group "=== London OPR PDF : journal et persistance ==="
input int              InpLOWarmupDays    = 3;              // Jours d'historique M1 rejoués au démarrage
input bool             InpLOJournalCsv    = true;           // Journal CSV de chaque décision (Common\Files\ICTNAS)
input bool             InpLOJournalPrint  = true;           // Décisions importantes dans le journal Experts
input bool             InpLOPersist       = true;           // Sauvegarder les OPR finalisés (redémarrage de MT5)

input group "=== v6.20 : Silver Bullet 1er FVG et Macro Breaker (ICT Ultimate Pro) ==="
input bool             InpV6EnableSB      = true;           // Silver Bullet v6.20 (M5 : sweep confirmé -> MSS -> 1er FVG)
input bool             InpV6EnableMB      = true;           // Macro Breaker v6.20 (M1 : stop hunt -> breaker dans une macro)
input int              InpV6MaxTradesPerWindow = 1;         // Trades max par fenêtre SB / par macro (ordres + entrées, 0 = aucun plafond)
input bool             InpV6SBTakeFirstFVG= true;           // SB : entrer sur le 1er FVG du displacement
input double           InpV6SBMinRetrace  = 0.35;           // SB : retracement minimal de la jambe à l'entrée
input bool             InpV6FVGRequireBody= false;          // Exiger un corps directionnel sur la bougie centrale du FVG
input bool             InpV6MBAllowRetested = true;         // MB : accepter un breaker déjà touché (non violé)
input int              InpV6SBRelaxAfterMin = 30;           // SB : 2e passe relâchée N min après le début de fenêtre (0 = off)
input int              InpV6MBRelaxAfterMin = 8;            // MB : 2e passe relâchée N min après le début de macro (0 = off)
input bool             InpV6UseLondonSB   = true;           // Fenêtre Silver Bullet Londres 03:00-04:00 NY
input bool             InpV6UseNYAMSB     = true;           // Fenêtre Silver Bullet NY AM 10:00-11:00 NY
input bool             InpV6UseNYPMSB     = true;           // Fenêtre Silver Bullet NY PM 14:00-15:00 NY

input group "=== v6.20 : Silver Bullet (M5) ==="
input ENUM_TIMEFRAMES  InpV6LTF           = PERIOD_M5;      // Timeframe d'entrée
input ENUM_TIMEFRAMES  InpV6HTF           = PERIOD_H1;      // Timeframe du biais
input int              InpV6SwingStrength = 2;              // Force des swings fractals
input double           InpV6SweepMinATR   = 0.04;           // Pénétration minimale du sweep (ATR M5)
input int              InpV6SweepConfirmBars = 3;           // Bougies max entre l'extrême et la clôture de retour
input int              InpV6SweepMaxEpisodeBars = 6;        // Bougies max au-delà du niveau (sinon cassure)
input int              InpV6SweepLookbackBars = 48;         // Bougies M5 de recherche du sweep
input int              InpV6PreSweepMinutes = 45;           // Le sweep peut précéder la fenêtre de N minutes
input int              InpV6MSSMaxBars    = 15;             // Bougies max entre sweep et MSS
input double           InpV6MSSMinRangeATR= 0.3;            // Distance min entre l'extrême du sweep et le niveau cassé (ATR)
input double           InpV6DispBodyATR   = 0.8;            // Corps minimal de displacement (ATR M5)
input double           InpV6FVGMinSizeATR = 0.12;           // Taille minimale du FVG (ATR M5)
input double           InpV6EqualHighsTolATR = 0.10;        // Tolérance equal highs / lows (ATR M5)
input ENUM_ENTRY_MODE  InpV6EntryMode     = ENTRY_FVG_TOP;  // Mode d'entrée
input int              InpV6OrderExpiryMinutes = 45;        // Expiration de l'ordre limite après la fin de fenêtre
input bool             InpV6RequireDiscount = true;         // Appliquer le seuil de retracement
input bool             InpV6RequireHTFAlign = false;        // Exiger l'alignement avec le biais HTF
input bool             InpV6UseOTEBonus   = true;           // Bonus si le FVG recouvre l'OTE 62-79 %
input bool             InpV6UseMacroBonus = true;           // Bonus si le MSS se forme dans une macro
input int              InpV6MinSetupScore = 3;              // Score minimal Silver Bullet
input double           InpV6SLBufferATR   = 0.10;           // Buffer du SL derrière l'extrême du sweep (ATR)
input double           InpV6MaxStopATR    = 6.0;            // Distance de stop maximale (ATR M5)
input double           InpV6TPBufferATR   = 0.05;           // TP placé juste avant le pool (ATR)
input ENUM_TP_MODE     InpV6TPMode        = TP_NEAREST_POOL;// Mode de cible
input double           InpV6MinRR         = 2.0;            // RR minimum planifié (passe relâchée : max(1,5 ; RR - 0,5))
input double           InpV6MaxTPDistATRD1= 1.5;            // Distance max du TP (ATR D1)
input bool             InpV6AllowFixedRRFallback = true;    // Sans pool atteignable : TP au RR minimum
input int              InpV6IPDA1         = 20;             // IPDA lookback 1 (jours) = dealing range
input int              InpV6IPDA2         = 40;             // IPDA lookback 2 (jours)
input int              InpV6IPDA3         = 60;             // IPDA lookback 3 (jours)
input bool             InpV6UTBotConfirm  = false;          // Confirmation UT Bot (ligne ATR)
input double           InpV6UTBotKey      = 1.0;            // Sensibilité UT Bot

input group "=== v6.20 : Macro Breaker (M1, macros ICT) ==="
input ENUM_TIMEFRAMES  InpV6MBTimeframe   = PERIOD_M1;      // Timeframe du breaker
input string           InpV6MBMacros      = "0320,0350,0820,0920,0950,1020,1050,1120,1320,1420,1515,1550"; // Macros autorisées (HHMM NY)
input int              InpV6MBRetestGraceMinutes = 25;      // Retest accepté jusqu'à N min après la fin de macro
input int              InpV6MBOrderExpiryMinutes = 35;      // Expiration de l'ordre après la fin de macro
input int              InpV6MBSwingStrength = 2;            // Force des swings M1
input int              InpV6MBLookbackBars= 90;             // Bougies M1 de recherche du stop hunt
input int              InpV6MBSwingLookback = 75;           // Bougies M1 de recherche du swing opposé
input int              InpV6MBMaxBarsToConfirm = 30;        // Bougies max entre stop hunt et confirmation
input double           InpV6MBSweepMinATR = 0.05;           // Pénétration minimale du stop hunt (ATR M1)
input int              InpV6MBPreMacroMinutes = 25;         // Confirmation acceptée N min avant le début de macro
input double           InpV6MBMinRangeATR = 0.4;            // Distance min extrême -> swing (ATR M1)
input double           InpV6MBDispBodyATR = 0.8;            // Corps minimal de displacement (ATR M1)
input double           InpV6MBFVGMinSizeATR = 0.15;         // Taille minimale du FVG Unicorn (ATR M1)
input double           InpV6MBMinBreakerATR = 0.5;          // Breaker plus petit : SL derrière l'extrême du sweep
input ENUM_MB_ENTRY    InpV6MBEntryLevel  = MB_ENTRY_BREAKER_EDGE; // Niveau d'entrée dans le breaker
input bool             InpV6MBRequireUnicorn = false;       // Exiger un FVG dans le breaker (Unicorn)
input bool             InpV6MBRequireHTFAlign = false;      // Exiger l'alignement HTF
input int              InpV6MBMinScore    = 2;              // Score minimal Macro Breaker
input double           InpV6MBSLBufferATR = 0.2;            // Buffer du SL (ATR M1)
input double           InpV6MBGenerousMacroMult = 1.5;      // Multiplicateur du buffer pendant la macro 09:20
input double           InpV6MBMaxStopATR  = 12.0;           // Distance de stop maximale (ATR M1)

input group "=== v6.20 : tips ICT (score et cibles) ==="
input bool             InpV6UseTrueOpenBonus = true;        // Bonus : achat sous le true open, vente au-dessus
input bool             InpV6RequireTrueOpen = false;        // ... en filtre dur
input bool             InpV6UseRefLevelBonus = true;        // Bonus : FVG / breaker sur quadrant daily, OPR, NDOG / NWOG
input double           InpV6RefLevelTolATR = 0.15;          // Tolérance (ATR M5)
input bool             InpV6UseDOWScore   = true;           // Profil hebdo : mar / mer / jeu +1, ven -1
input bool             InpV6UseBPRBonus   = true;           // Bonus : Balanced Price Range
input bool             InpV6UseSDTargets  = true;           // Cibles : déviations standard 2 / 2,5 / 4
input double           InpV6EqWarnATR     = 1.5;            // Equal highs / lows à moins de N ATR au-delà du stop : -2
input bool             InpV6UseOPRLevels  = true;           // Opening ranges 01:30, 07:00, 09:30, 13:30 NY
input bool             InpV6UseTBRLevels  = true;           // Time based range 08:12-09:12 NY
input bool             InpV6UseNDOGLevels = true;           // NDOG / NWOG

input group "=== Séquence d'entrée ==="
input ENUM_TIMEFRAMES  InpExecTF          = PERIOD_M1;      // UT d'exécution (M1, M3 ou M5)
input double           InpMinFVGPts       = 5.0;            // [Personnalisé] Taille minimale du FVG (points d'indice)
input double           InpDispATRMult     = 1.5;            // [Personnalisé] Displacement : corps >= x ATR(14)
input bool             InpRequireDisp     = true;           // [Personnalisé] Displacement obligatoire
input int              InpHuntMaxBars     = 30;             // [Personnalisé] Barres max entre le sweep et le FVG
input double           InpSLBufferPts     = 4.0;            // Buffer du SL au-delà du sweep (points)
input int              InpPendingMaxMin   = 30;             // Durée de vie max de l'ordre limite (minutes)

input group "=== Filtres ==="
input bool             InpBlockLunch      = true;           // Pas d'entrée 05:00-07:00 et 12:00-13:30 NY
input bool             InpNewsFilter      = true;           // Filtre news USD fort impact
input int              InpNewsBeforeMin   = 10;             // News : minutes avant
input int              InpNewsAfterMin    = 20;             // News : minutes après
input string           InpNewsCSV         = "ICTNAS\\news_usd.csv"; // News en testeur (Common\Files, heure NY)
input bool             InpBlockTrendCounter = true;         // Jour de tendance : pas de trade contre la cassure de l'OPR 09:30
input bool             InpPDFilter        = false;          // Acheter seulement en discount / vendre en premium (PDH-PDL)
input ENUM_WEEKLY_BIAS InpWeeklyBias      = WB_NONE;        // Biais hebdo (manuel)
input bool             InpWeeklyBiasFilter= false;          // Bloquer les trades contre le biais hebdo
input string           InpFlatTime        = "15:50";        // Heure de flat (NY) : macro de settlement, tout est fermé
input int              InpMaxTradesDay    = 3;              // Trades exécutés max par jour (+ ordres en attente ; 0 = illimité)
input int              InpMaxConcurrent   = 2;              // Positions / ordres simultanés max (toujours dans le même sens)

input group "=== Score ICT ==="
input int              InpHTFWeightMin    = 6;              // "Sweep HTF" : poids de liquidité minimal
input string           InpWeightsFile     = "ICTNAS\\ict_weights.json"; // Poids recalibrés (optionnel)

input group "=== Machine Learning (filtre) ==="
input ENUM_ML_MODE     InpMLMode          = ML_OBSERVE;     // Mode ML
input string           InpMLFolder        = "ICTNAS\\model"; // Dossier du modèle (Common\Files)

input group "=== OPR / STDV (affichage et contexte) ==="
input string           InpSTDVLevels      = "1,1.5,2,2.5,3.5,5,6,6.5,10"; // Niveaux STDV
input string           InpSTDVKey         = "2,6,6.5";      // Niveaux STDV clés
input string           InpShadowEnd       = "09:30";        // Fin du range Shadow / Reset (début 07:00 NY)

input group "=== Liquidité ==="
input int              InpSwingStrength   = 2;              // Swings M15 : bougies de chaque côté
input int              InpSwingLookbackH  = 24;             // Swings M15 : ancienneté max (heures)
input ENUM_EQ_TOL_MODE InpEqTolMode       = EQTOL_ATR_M15;  // Tolérance EQH / EQL
input double           InpEqTolATR        = 0.10;           // Tolérance : multiple ATR(14) M15
input double           InpEqTolPts        = 3.0;            // Tolérance : points d'indice

input group "=== Gaps ==="
input int              InpGapsKeep        = 5;              // NDOG / NWOG conservés
input string           InpRTHClose        = "16:15";        // Clôture RTH de la veille (NY)
input double           InpRTHBigPts       = 80.0;           // RTH Gap "gros" à partir de (points)
input string           InpWeeklyProfile   = "Accumulation,Manipulation,Expansion,Distribution,Cloture"; // Profil Lun -> Ven

input group "=== SMT ==="
input bool             InpUseSMT          = true;           // SMT NQ / ES
input string           InpSMTSymbol       = "";             // Symbole ES / US500 (vide = détection auto)

input group "=== Risque ==="
input double           InpRiskPct         = 1.0;            // Risque par trade % (plafonné à 3 % ; v2.22 : 3 %)
input double           InpDailyLossPct    = 2.0;            // Stop journalier % (0 = désactivé ; 2 % = 2 pertes à 1 %)
input double           InpDailyTargetPct  = 3.0;            // Objectif journalier % (0 = désactivé)
input double           InpMaxTotalDDPct   = 8.0;            // DD total max % (prop firm) : arrêt définitif, 0 = désactivé
input bool             InpDDHaltInTester  = false;          // v2.50 : testeur : DD total = arrêt définitif (false = signalé avec sa date, le test continue)
input bool             InpCloseOnDailyLimit = true;         // Tout fermer quand une limite journalière est atteinte
input bool             InpCloseOnDailyTarget = false;       // v2.50 : objectif atteint -> fermer aussi les positions (false = plus d'entrée, positions jusqu'à leur SL / cible)
input double           InpInitialBalance  = 0;              // Solde de référence DD total (0 = solde au lancement)
input double           InpBEAtR           = 1.0;            // Break-even quand le prix atteint x R
input double           InpBEPts           = 1.0;            // Break-even : entrée + x points
input bool             InpTrailing        = false;          // Trailing structurel M1 après l'allègement
input double           InpTrailBufPts     = 2.0;            // Buffer du trailing (points)
input double           InpTestSLPts       = 20.0;           // Panneau : SL de test pour la taille de lot

input group "=== Garde-fous (RiskGuard / v6.20) ==="
input double           InpMinLotRiskTol   = 1.5;            // Lot minimum accepté si son risque <= x fois le risque voulu (v6.20 : 1,5 ; 1 = refus strict)
input double           InpMaxLots         = 0.0;            // Lot maximum absolu (0 = aucun ; RiskGuard : 1,00)
input double           InpMaxOpenRiskPct  = 3.0;            // Risque ouvert cumulé max % (positions hors BE + ordres en attente ; 0 = aucun)
input int              InpMinSecondsBetweenTrades = 0;      // Délai minimum entre deux ordres en secondes (0 = aucun ; RiskGuard : 900)
input double           InpMaxSpreadATR    = 0.0;            // Spread max en fraction de l'ATR M5 (0 = aucun ; v6.20 : 0,15)
input ENUM_SL_CAP_MODE InpSLCapMode       = SLCAP_REJECT;   // SL au-delà du plafond ATR du profil : rejet ou ramené au plafond

input group "=== v2.50 : apprentissage par modèle x session (règle v6.20) ==="
input bool             InpAdaptGate       = false;          // Bloquer un modèle x session à espérance négative démontrée (v6.20 : ADAPT_SIZE_AND_GATE ; false = signalé dans diagnostic.txt)
input int              InpAdaptMinSamples = 25;             // Setups résolus minimum avant de pouvoir bloquer (v6.20 : 25, min 5)

input group "=== Données ==="
input bool             InpCollect         = true;           // Enregistrer contexte, signaux et trades (SQLite)
input string           InpDBFile          = "ICTNAS\\ict_nas.sqlite"; // Base SQLite (Common\Files)
input bool             InpCSVMirror       = true;           // Copie CSV
input bool             InpFreshDBInTester = true;           // Testeur : base vide à chaque passe

input group "=== Diagnostic ==="
input bool             InpDebugLog        = false;          // Journal détaillé de chaque setup
input bool             InpDailyDiagnostic = true;           // Résumé de l'entonnoir chaque jour dans le journal
input bool             InpSelfTest        = false;          // Testeur : ordre de test (lot min) au démarrage (v2.40 : off, il apparaissait comme un trade du rapport)
input double           InpMaxMarginPct    = 80.0;           // Marge max utilisée par un trade (% de la marge libre)

input group "=== Affichage ==="
input bool             InpDraw            = true;           // Tracés (mode debug)
input bool             InpShowPanel       = true;           // Panneau d'information
input int              InpKeepDays        = 3;              // Jours conservés à l'écran
input bool             InpSTDV_MOR        = true;           // STDV du MOR
input bool             InpSTDV_0130       = false;          // STDV OPR 01:30
input bool             InpSTDV_0700       = false;          // STDV OPR 07:00
input bool             InpSTDV_0930       = true;           // STDV OPR 09:30
input bool             InpSTDV_1330       = false;          // STDV OPR 13:30
input bool             InpDrawSwings      = true;           // Swings M15 intacts
input color            InpClrMOR          = clrDodgerBlue;   // Couleur MOR
input color            InpClrOPR          = clrMediumPurple; // Couleur OPR
input color            InpClrSTDV         = C'90,90,120';    // Couleur STDV
input color            InpClrKeySTDV      = clrOrange;       // Couleur STDV clés
input color            InpClrBSL          = clrTomato;       // Couleur BSL
input color            InpClrSSL          = clrMediumSeaGreen; // Couleur SSL
input color            InpClrGap          = C'70,70,40';     // Couleur NDOG / NWOG
input color            InpClrSession      = C'40,48,64';     // Couleur sessions
input color            InpClrTO           = clrSilver;       // Couleur True Opens

//+------------------------------------------------------------------+
//| Globales                                                         |
//+------------------------------------------------------------------+
CTimeManager      g_tm;
COPREngine        g_opr;
CLiquidityEngine  g_liq;
CGapEngine        g_gap;
CQuarterlyEngine  g_q;
CSMTCheck         g_smt;
CRiskManager      g_risk;
CDataCollector    g_db;
CDrawer           g_draw;
CPanel            g_panel;
CATRBank          g_atr;
CSetupEngine      g_setup;
CSignalLogger     g_log;
CScorer           g_scorer;
CMLInference      g_ml;
CNewsFilter       g_news;
CTradeManager     g_tm_trades;
CLondonOprEngine  g_lo;             // v2.30 : moteur London OPR (PDF)

datetime          g_anchor=0;       // jour de trading en cours (minuit NY)
datetime          g_lastM1=0;
datetime          g_lastM15=0;
datetime          g_lastM5=0;
datetime          g_lastH1=0;
datetime          g_lastExec=0;
uint              g_lastPanelMs=0;
string            g_profile[];
string            g_tzMsg="";
bool              g_tzOk=true;
int               g_gapsAbove0930=-1,g_gapsBelow0930=-1;
int               g_tradesToday=0;  // ordres envoyés aujourd'hui (information ; la limite compte les exécutions)
datetime          g_lastOrderSrv=0; // v2.40 : heure du dernier ordre envoyé (délai minimum entre deux trades)
double            g_dayOpen=0;
bool              g_flatDone=false;
bool              g_limitClosed=false;
bool              g_targetKept=false;   // v2.50 : objectif journalier atteint, positions conservées (ordres en attente supprimés)
bool              g_oprLvl0000=false,g_oprLvl0930=false,g_oprLvl1330=false;
SFVG              g_fpAsia;
SFVG              g_fpMid;
string            g_recent[];       // dernières décisions (panneau)
int               g_setupsToday=0;
//--- paramètres effectifs (profil d'entrée)
double            g_pScoreMin,g_pMinRR,g_pFallbackRR,g_pMaxRR,g_pSLFloorATR,g_pSLCapATR,g_pTP1R;
double            g_pMinFVG,g_pDispMult;
int               g_pHuntBars;
bool              g_pRequireDisp,g_pMarket,g_pMomentum,g_pKillzone;
datetime          g_lastMomentum=0;
//--- diagnostic (cumul depuis le lancement)
int               g_nNoModel=0;
string            g_diagKey[];
int               g_diagCnt[];

//=== début ModelRouter.mqh ===
//+------------------------------------------------------------------+
//|                                                 ModelRouter.mqh  |
//|  Associe chaque candidat ICT (sweep -> MSS/CISD -> FVG) à un     |
//|  modèle, construit le plan (entrée CE, SL, TP1-3), calcule le    |
//|  contexte / les facteurs, puis applique la chaîne de décision :  |
//|  filtres -> RR -> score ICT -> ML -> risque -> conflit -> ordre. |
//|                                                                  |
//|  Priorité (validée) : Shadow > Silver Bullet > London OPR > OPR. |
//|  ERL/IRL : modèle séparé (sweep H1 -> MSS M5 -> cible FVG H1).   |
//|  v2.30 : RR minimal par famille (ICT / CRT / PDF), score ICT non |
//|  bloquant pour les modèles PDF, limite de trades sur exécutions. |
//|  v2.40 : modèles v6.20 (SB_V6, MACRO_BREAKER) : RR et score      |
//|  contrôlés par leur moteur ; risque ouvert, spread, délai.       |
//|                                                                  |
//|  Ce fichier utilise les objets globaux et les inputs de l'EA :   |
//|  il est inclus APRÈS leur déclaration.                           |
//+------------------------------------------------------------------+
#ifndef ICTNAS_MODELROUTER_MQH
#define ICTNAS_MODELROUTER_MQH

int ModelRank(const string m)
  {
   if(m=="SHADOW")        return(0);
   if(m=="CRT_45MIN")     return(1);
   if(m=="SILVER_BULLET") return(2);
   if(m=="SB_V6")         return(2);
   if(m=="CRT_0830")      return(3);
   if(m=="MACRO_BREAKER") return(3);
   if(m=="LONDON_OPR")    return(4);
   if(m==LO_MODEL)        return(4);
   if(m=="CRT_0250")      return(5);
   if(m=="CRT_OPR")       return(6);
   if(StringFind(m,"OPR_")==0) return(7);
   if(StringFind(m,"OPRPDF_")==0) return(7);
   if(m=="CRT_PM")        return(8);
   if(m=="KILLZONE")      return(9);
   if(m=="SB_MOMENTUM")   return(10);
   return(11);
  }
string ModelCode(const string m)
  {
   if(m=="SHADOW") return("SH");
   if(m=="SILVER_BULLET") return("SB");
   if(m=="SB_V6") return("S6");
   if(m=="MACRO_BREAKER") return("MB");
   if(m=="LONDON_OPR") return("LO");
   if(m==LO_MODEL) return("LP");
   if(StringFind(m,"OPRPDF_")==0) return("P"+StringSubstr(m,7));
   if(m=="ERL_IRL") return("EI");
   if(m=="KILLZONE") return("KZ");
   if(m=="SB_MOMENTUM") return("SM");
   if(m=="CRT_45MIN") return("C45");
   if(m=="CRT_0830") return("C08");
   if(m=="CRT_0250") return("C02");
   if(m=="CRT_OPR") return("COP");
   if(m=="CRT_PM") return("CPM");
   if(StringFind(m,"OPR_")==0) return("O"+StringSubstr(m,4));
   return("XX");
  }

bool InMin(int m,int a,int b) { return(m>=a && m<b); }

//--- +1 si le prix est au-dessus de l'OPR, -1 en dessous, 0 dedans / OPR incomplet
int OPRSide(SRange &r,double px)
  {
   if(!r.complete) return(0);
   if(px>r.high) return(1);
   if(px<r.low)  return(-1);
   return(0);
  }

//--- 2 STDV d'un range dans le sens du trade
double STDVTarget(SRange &r,int dir,double k)
  {
   if(!r.complete || r.Size()<=0) return(0);
   return(dir==1 ? r.Up(k) : r.Dn(k));
  }

#define RR_EPS 0.01                 // tolérance sur les comparaisons de RR (virgule flottante)
int g_liqTargetW=0;                 // >0 : la DOL est choisie dans la carte de liquidité (poids min)

//--- v2.30 : modèles issus du moteur OPR + FVG (PDF London OPR)
bool IsPdfModel(const string m) { return(m==LO_MODEL || StringFind(m,"OPRPDF_")==0); }
//--- v2.40 : modèles portés de la v6.20 (leur moteur applique son RR minimal et son score)
bool IsV6Model(const string m) { return(m=="SB_V6" || m=="MACRO_BREAKER"); }

//--- v2.30 : RR minimal par famille de modèles
//---   PDF : la cible est la déviation standard de l'OPR (InpLondonMinRR, 0 = acceptée telle quelle)
//---   CRT : gestion CRT, reste à la DOL >= 3R (InpCRTMinRR)
//---   autres modèles ICT : profil (règle validée « RR min 2 »)
double ModelMinRR(const string model)
  {
   if(IsPdfModel(model)) return(InpLondonMinRR);
   if(IsV6Model(model)) return(0);
   if(StringFind(model,"CRT_")==0) return(InpCRTMinRR);
   return(g_pMinRR);
  }

//--- v2.30 : le score ICT n'est pas une règle du PDF : il est calculé et enregistré, sans bloquer
bool ModelUsesScore(const string model) { return(!IsPdfModel(model) && !IsV6Model(model)); }

//--- DOL ICT : premier pool de liquidité intact (poids >= minW) situé à au moins g_pMinRR x R.
//--- Les pools plus proches sont des aimants sur le chemin, pas des obstacles. 0 = aucun.
double PickLiquidityDOL(int dir,double entry,double r,int minW)
  {
   if(r<=0) return(0);
   for(int skip=0;skip<10;skip++)
     {
      int k=g_liq.NextIntact(dir==1,entry,minW,skip);
      if(k<0) break;
      if(dir*(g_liq.lv[k].price-entry)>=(g_pMinRR-RR_EPS)*r) return(g_liq.lv[k].price);
     }
   return(0);
  }

//+------------------------------------------------------------------+
//| CRT_TRADE : cible = DOL opposé (PDH/PDL, CE des NDOG/NWOG, bord   |
//| opposé de l'OPR). On prend le plus proche situé à au moins        |
//| InpCRTMinRR x R ; à défaut le plus proche (le RR décide).         |
//+------------------------------------------------------------------+
double CRTTarget(int dir,double entry,double r,double extra)
  {
   double cands[];
   int n=0;
   double pd=(dir==1)?g_liq.pdh:g_liq.pdl;
   if(pd>0) { ArrayResize(cands,n+1); cands[n++]=pd; }
   for(int i=0;i<ArraySize(g_gap.ndog);i++) if(g_gap.ndog[i].valid) { ArrayResize(cands,n+1); cands[n++]=g_gap.ndog[i].CE(); }
   for(int i=0;i<ArraySize(g_gap.nwog);i++) if(g_gap.nwog[i].valid) { ArrayResize(cands,n+1); cands[n++]=g_gap.nwog[i].CE(); }
   if(extra>0) { ArrayResize(cands,n+1); cands[n++]=extra; }
   double bestFar=0,bestAny=0,dFar=DBL_MAX,dAny=DBL_MAX;
   for(int i=0;i<n;i++)
     {
      double d=dir*(cands[i]-entry);
      if(d<=0) continue;
      if(d<dAny) { dAny=d; bestAny=cands[i]; }
      if(r>0 && d>=(InpCRTMinRR-RR_EPS)*r && d<dFar) { dFar=d; bestFar=cands[i]; }
     }
   return(bestFar>0 ? bestFar : bestAny);
  }

//--- True Opens (Daily 00:00 et NY 07:30) : au-dessus des deux -> ventes, en dessous -> achats
int TrueOpenBias(double px)
  {
   double d=g_q.dayTO,n=g_q.sessTO;
   if(g_q.dayQ!=3 || d<=0 || n<=0) return(0);   // True Open NY défini pendant la session NY AM
   if(px>d && px>n) return(-1);
   if(px<d && px<n) return(1);
   return(0);
  }

//--- CRT OPR : sweep au-delà d'un OPR puis retour dans le range
bool CRTOPRReentry(SSetup &c,SRange &r,double px)
  {
   if(!r.complete || c.tExtreme<r.endSrv) return(false);
   bool inside=(px<=r.high && px>=r.low);
   if(c.dir==-1) return(c.extreme>r.high && inside);
   return(c.extreme<r.low && inside);
  }

double g_crtExtra=0;   // cible CRT supplémentaire (bord opposé de l'OPR)

//--- Choix du modèle + cible (DOL) + runner. Renvoie false si aucun modèle ne s'applique.
bool ChooseModel(SSetup &c,datetime nowNY,double px,string &model,double &dol,double &runner,datetime &expiryNY,SRange &refRange,bool &hasRef)
  {
   int m=CTimeManager::MinuteOfDay(nowNY);
   datetime day=g_anchor;
   dol=0; runner=0; hasRef=false; g_liqTargetW=0;
   //--- Momentum (logique Silver Bullet de l'EA v6) : cible = pool de liquidité le plus proche
   if(c.momentum)
     {
      model="SB_MOMENTUM";
      g_liqTargetW=4;
      int k=g_liq.NextIntact(c.dir==1,px,4);
      if(k>=0)
        {
         dol=g_liq.lv[k].price;
         int k2=g_liq.NextIntact(c.dir==1,px,4,1);
         if(k2>=0) runner=g_liq.lv[k2].price;
        }
      expiryNY=nowNY+15*SEC_MIN;
      return(true);
     }
   //--- ERL -> IRL
   if(c.erl)
     {
      if(!InpUseERL) return(false);
      if(!(InMin(m,120,300) || InMin(m,420,660) || InMin(m,810,900))) return(false);
      double edge,ce;
      if(!g_setup.FindIRL(c.dir,c.CE(),edge,ce)) { model="ERL_IRL"; expiryNY=nowNY+60*SEC_MIN; return(true); }
      model="ERL_IRL"; dol=edge; runner=ce; expiryNY=nowNY+60*SEC_MIN;
      return(true);
     }
   //--- 1. Shadow : la 1re Reset liquidity prise -> cible la Reset opposée.
   //---    Le sweep du setup doit être celui de la Reset (extrême au-delà du niveau,
   //---    pris au plus tôt au moment où la 1re Reset a été prise).
   int shEnd=ParseHHMM(InpShadowEnd);
   bool shSide=((c.dir==-1 && g_opr.shadowFirstSide==1 && c.extreme>g_opr.shadow.high) ||
                (c.dir==1  && g_opr.shadowFirstSide==-1 && c.extreme<g_opr.shadow.low));
   if(InpUseShadow && g_opr.shadow.complete && InMin(m,shEnd,11*60+30) && shSide &&
      c.tExtreme>=g_opr.shadowFirstTime-5*SEC_MIN)
     {
      model="SHADOW";
      dol=(c.dir==-1)?g_opr.shadow.low:g_opr.shadow.high;
      int k=g_liq.NextIntact(c.dir==1,dol,5);
      if(k>=0) runner=g_liq.lv[k].price;
      expiryNY=day+(11*60+30)*SEC_MIN;
      refRange=g_opr.shadow; hasRef=true;
      return(true);
     }
   g_crtExtra=0;
   //--- CRT A+B : modèle 45 minutes (09:23-10:08) + filtre des True Opens
   if(InpUseCRT45 && InMin(m,9*60+23,10*60+8) && (!InpCRTRequireTO || TrueOpenBias(px)==c.dir))
     {
      model="CRT_45MIN";
      expiryNY=day+(10*60+8)*SEC_MIN;
      if(g_opr.opr0930.complete) { refRange=g_opr.opr0930; hasRef=true; }
      return(true);
     }
   //--- 2. Silver Bullet (l'entrée doit se faire dans la fenêtre)
   string sb=CTimeManager::SilverBulletLabel(nowNY,InpSBMode);
   if(InpUseSB && sb!="" && c.liqWeight>=InpSBMinLiqWeight)
     {
      model="SILVER_BULLET";
      int h=m/60;
      expiryNY=day+(h+1)*SEC_HOUR;
      //--- TGIF : vendredi 14-15, retracement de 20-30 % du range hebdo
      if(InpTGIF && CTimeManager::DayOfWeek(day)==5 && h==14)
        {
         double wh=iHigh(_Symbol,PERIOD_W1,0),wl=iLow(_Symbol,PERIOD_W1,0),wo=iOpen(_Symbol,PERIOD_W1,0);
         double rg=wh-wl;
         if(rg>0 && ((c.dir==-1 && px>wo) || (c.dir==1 && px<wo)))
           {
            dol=(c.dir==-1)?wh-InpTGIFRetrace*rg:wl+InpTGIFRetrace*rg;
            model="SILVER_BULLET";
            return(true);
           }
        }
      g_liqTargetW=InpSBMinTargetWeight;
      int k=g_liq.NextIntact(c.dir==1,c.CE(),InpSBMinTargetWeight);
      if(k>=0)
        {
         dol=g_liq.lv[k].price;
         int k2=g_liq.NextIntact(c.dir==1,c.CE(),InpSBMinTargetWeight,1);
         if(k2>=0) runner=g_liq.lv[k2].price;
        }
      if(h==3) { refRange=g_opr.mor; hasRef=true; }
      else if(g_opr.opr0930.complete) { refRange=g_opr.opr0930; hasRef=true; }
      return(true);
     }
   //--- CRT D : macro de 08:30 (08:30-09:10), breaker ou IFVG exigé
   if(InpUseCRT0830 && InMin(m,8*60+30,9*60+10) && (c.breaker || c.ifvg))
     {
      model="CRT_0830";
      expiryNY=day+(9*60+10)*SEC_MIN;
      return(true);
     }
   //--- 3. London OPR (MOR) v2.22 : 02:50-04:10, biais de 02:50, sweep pendant une macro
   //---    v2.30 : le modèle du PDF (moteur OPR + FVG) le remplace par défaut (InpLondonMode)
   if(InpUseLondonOPR && InpLondonMode!=LONDON_PDF && InMin(m,170,250) && g_opr.morBiasSet && g_opr.morBias==c.dir)
     {
      bool macroOk=!InpLondonNeedMacro || (CTimeManager::MacroLabel(g_tm.ServerToNY(c.tSweep))!="");
      if(macroOk)
        {
         model="LONDON_OPR";
         dol=STDVTarget(g_opr.mor,c.dir,InpTargetSTDV);
         int k=g_liq.NextIntact(c.dir==1,dol>0?dol:c.CE(),6);
         if(k>=0) runner=g_liq.lv[k].price;
         expiryNY=day+(4*60+10)*SEC_MIN;
         refRange=g_opr.mor; hasRef=true;
         return(true);
        }
     }
   //--- CRT F : macro de 02:50-03:10 (sweep dans la macro), entrée jusqu'à 04:10
   if(InpUseCRT0250 && InMin(m,170,250))
     {
      int ms=CTimeManager::MinuteOfDay(g_tm.ServerToNY(c.tSweep));
      if(InMin(ms,170,190))
        {
         model="CRT_0250";
         expiryNY=day+(4*60+10)*SEC_MIN;
         refRange=g_opr.mor; hasRef=true;
         return(true);
        }
     }
   //--- CRT C : sweep au-delà d'un OPR (00:00, 09:30, 13:30) puis retour dans le range
   if(InpUseCRTOPR)
     {
      if(InMin(m,30,250) && CRTOPRReentry(c,g_opr.mor,px))
        { model="CRT_OPR"; g_crtExtra=(c.dir==1)?g_opr.mor.high:g_opr.mor.low; expiryNY=day+(4*60+10)*SEC_MIN; refRange=g_opr.mor; hasRef=true; return(true); }
      if(InMin(m,600,720) && CRTOPRReentry(c,g_opr.opr0930,px))
        { model="CRT_OPR"; g_crtExtra=(c.dir==1)?g_opr.opr0930.high:g_opr.opr0930.low; expiryNY=day+12*SEC_HOUR; refRange=g_opr.opr0930; hasRef=true; return(true); }
      if(InMin(m,840,950) && CRTOPRReentry(c,g_opr.opr1330,px))
        { model="CRT_OPR"; g_crtExtra=(c.dir==1)?g_opr.opr1330.high:g_opr.opr1330.low; expiryNY=day+(15*60+50)*SEC_MIN; refRange=g_opr.opr1330; hasRef=true; return(true); }
     }
   //--- 4. Les OPR : au-dessus du range -> achats, en dessous -> ventes, cible 2 STDV
   if(InpUseOPR0130 && InMin(m,120,300) && OPRSide(g_opr.opr0130,px)==c.dir)
     { model="OPR_0130"; dol=STDVTarget(g_opr.opr0130,c.dir,InpTargetSTDV); expiryNY=day+5*SEC_HOUR; refRange=g_opr.opr0130; hasRef=true; return(true); }
   if(InpUseOPR0700 && InMin(m,450,570) && OPRSide(g_opr.opr0700,px)==c.dir)
     { model="OPR_0700"; dol=STDVTarget(g_opr.opr0700,c.dir,InpTargetSTDV); expiryNY=day+(9*60+30)*SEC_MIN; refRange=g_opr.opr0700; hasRef=true; return(true); }
   if(InpUseOPR0930 && InMin(m,600,720) && OPRSide(g_opr.opr0930,px)==c.dir)
     { model="OPR_0930"; dol=STDVTarget(g_opr.opr0930,c.dir,InpTargetSTDV); expiryNY=day+12*SEC_HOUR; refRange=g_opr.opr0930; hasRef=true; return(true); }
   if(InpUseOPR1330 && InMin(m,840,960) && OPRSide(g_opr.opr1330,px)==c.dir)
     { model="OPR_1330"; dol=STDVTarget(g_opr.opr1330,c.dir,InpTargetSTDV); expiryNY=day+16*SEC_HOUR; refRange=g_opr.opr1330; hasRef=true; return(true); }
   //--- CRT E : macro PM d'impulsion 14:50-15:10
   if(InpUseCRTPM && InMin(m,14*60+50,15*60+10))
     {
      model="CRT_PM";
      expiryNY=day+(15*60+10)*SEC_MIN;
      return(true);
     }
   //--- 5. Killzone : tout setup ICT complet (sweep + MSS/CISD + FVG) dans une killzone,
   //---    cible = liquidité intacte la plus proche (poids >= 4)
   if(g_pKillzone && (InMin(m,120,300) || InMin(m,420,660) || InMin(m,810,960)))
     {
      model="KILLZONE";
      g_liqTargetW=4;
      int k=g_liq.NextIntact(c.dir==1,c.CE(),4);
      if(k>=0)
        {
         dol=g_liq.lv[k].price;
         int k2=g_liq.NextIntact(c.dir==1,c.CE(),4,1);
         if(k2>=0) runner=g_liq.lv[k2].price;
        }
      expiryNY=nowNY+30*SEC_MIN;
      return(true);
     }
   return(false);
  }

//--- FVG d'entrée qui chevauche un FPFVG (Asie M15 ou Midnight M1)
bool OverlapsFPFVG(double top,double bot)
  {
   if(g_fpAsia.valid && bot<=g_fpAsia.top && top>=g_fpAsia.bottom) return(true);
   if(g_fpMid.valid  && bot<=g_fpMid.top  && top>=g_fpMid.bottom)  return(true);
   return(false);
  }

//--- v2.30 : contexte temporel d'un signal (partagé par tous les modèles)
void FillTimeContext(SSignal &s,datetime nowNY)
  {
   int m=CTimeManager::MinuteOfDay(nowNY);
   MqlDateTime st;
   TimeToStruct(nowNY,st);
   s.dow=st.day_of_week; s.month=st.mon; s.hour=st.hour; s.minute=st.min;
   s.session=CTimeManager::SessionLabel(nowNY); s.killzone=s.session;
   s.sbWindow=CTimeManager::SilverBulletLabel(nowNY,InpSBMode);
   s.macro=CTimeManager::MacroLabel(nowNY);
   s.dayQ=g_q.dayQ; s.q90=g_q.q90; s.q22=g_q.q22;
   s.shadowActive=(g_opr.shadow.complete && InMin(m,ParseHHMM(InpShadowEnd),11*60+30))?1:0;
  }

//--- v2.30 : contexte de marché d'un signal (s.dir et s.entry doivent être renseignés)
void FillMarketContext(SSignal &s,datetime now,double bid,double ask)
  {
   s.pdPct=g_liq.PDPercent(s.entry);
   s.pdLabel=(s.pdPct<0)?"":(s.pdPct>=50?"PREMIUM":"DISCOUNT");
   s.weeklyProfile=ProfileOf(g_anchor);
   s.amdx=CQuarterlyEngine::AMDX(g_q.dayQ);
   double to=(g_q.sessTO>0)?g_q.sessTO:g_q.dayTO;
   s.qAlign=(to>0 && ((s.dir==-1 && s.entry>to) || (s.dir==1 && s.entry<to)))?1:0;
   s.weeklyBias=(int)InpWeeklyBias;
   s.gapBias=g_gap.ClusterBias(bid);
   s.trendDay=g_opr.IsTrendDay()?1:0;
   s.newsWin=g_news.InWindow(now)?1:0;
   s.spread=ask-bid;
   double hi,lo; datetime th,tl;
   s.dayRange=M1Extremes(_Symbol,g_tm.NYToServer(g_anchor-6*SEC_HOUR),now+60,hi,lo,th,tl)?hi-lo:0;
   s.asiaRange=g_liq.asia.valid?g_liq.asia.Size():0;
   s.londonRange=g_liq.london.valid?g_liq.london.Size():0;
   s.nyRange=g_liq.nyam.valid?g_liq.nyam.Size():0;
   s.dDaily=(g_dayOpen>0)?bid-g_dayOpen:0;
   s.dWeekly=(g_gap.weekOpen>0)?bid-g_gap.weekOpen:0;
   s.dMonthly=(g_liq.monthOpen>0)?bid-g_liq.monthOpen:0;
   s.dMidnight=(g_opr.midnightOpen>0)?bid-g_opr.midnightOpen:0;
  }

//--- Construit le signal complet à partir d'un candidat. false = aucun modèle.
bool BuildSignal(SSetup &c,SSignal &s)
  {
   datetime now=TimeCurrent();
   datetime nowNY=g_tm.ServerToNY(now);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID),ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double px=(c.dir==1)?ask:bid;
   string model;
   double dol,runner;
   datetime expNY;
   SRange ref;
   bool hasRef;
   ref.Reset("");
   if(!ChooseModel(c,nowNY,px,model,dol,runner,expNY,ref,hasRef)) return(false);
   MqlDateTime st;
   TimeToStruct(nowNY,st);
   s.model=model;
   s.dir=c.dir;
   s.tSrv=now;
   s.tNY=nowNY;
   s.uid=ModelCode(model)+"-"+StringFormat("%04d%02d%02d%02d%02d",st.year,st.mon,st.day,st.hour,st.min)+(c.dir==1?"L":"S");
   s.fixedUid=false; s.extId=0; s.slot=-1; s.cancelPx=0; s.chaseR=0; s.extKey=""; s.adaptOk=false;
   //--- temps
   FillTimeContext(s,nowNY);
   //--- liquidité / structure
   s.liqType=(c.liqType==LIQ_ERL_H1)?"ERL_H1":CLiquidityEngine::TypeName(c.liqType);
   s.liqWeight=c.liqWeight; s.liqPrice=c.liqPrice; s.tSweep=c.tSweep; s.tSweepNY=g_tm.ServerToNY(c.tSweep);
   s.mss=c.mss?1:0; s.cisd=c.cisd?1:0; s.disp=c.displacement?1:0;
   s.dispBodyATR=c.dispBodyATR; s.dispCandles=c.dispCandles; s.dispSize=c.dispSize;
   s.atr1=g_atr.Get(PERIOD_M1); s.atr5=g_atr.Get(PERIOD_M5); s.atr15=g_atr.Get(PERIOD_M15);
   s.ifvg=c.ifvg?1:0; s.breaker=c.breaker?1:0; s.unicorn=c.unicorn?1:0; s.ob=c.orderBlock?1:0;
   s.fvgTop=c.fvgTop; s.fvgBot=c.fvgBottom; s.fvgCE=c.CE(); s.fvgSize=c.fvgTop-c.fvgBottom; s.tFVG=c.fvgT1;
   s.fvgType=OverlapsFPFVG(c.fvgTop,c.fvgBottom)?"FPFVG":(c.ifvg?"IFVG":"CLASSIC");
   if(c.momentum) s.liqType="MOMENTUM";
   //--- plan : entrée au CE (limite) ou au marché ; SL au-delà de l'extrême du sweep
   bool crt=(StringFind(model,"CRT_")==0);
   s.market=(c.momentum || g_pMarket);
   //--- CRT : limite sur le bord proximal du FVG, invalidation si clôture au-delà du CE (règle des 50 %)
   if(s.market)   s.entry=px;
   else if(crt)   s.entry=(c.dir==1)?c.fvgTop:c.fvgBottom;
   else           s.entry=c.CE();
   s.inval=(crt && InpCRT50Rule)?c.CE():0;
   //--- SL ICT : TOUJOURS au-delà de l'extrême du sweep (+ buffer)
   string preReject="";
   s.sl=c.extreme-c.dir*InpSLBufferPts;
   double atr5=g_atr.Get(PERIOD_M5);
   if(atr5>0 && c.dir*(s.entry-s.sl)>0)
     {
      double dist=c.dir*(s.entry-s.sl);
      double lo=g_pSLFloorATR*atr5,hi=g_pSLCapATR*atr5;
      //--- plancher : jamais plus serré que x ATR M5 (on élargit, on ne rentre jamais dans le sweep)
      if(g_pSLFloorATR>0 && dist<lo) dist=lo;
      //--- plafond : sweep trop loin -> SL au-delà de la bougie 1 du FVG ; sinon setup rejeté
      if(g_pSLCapATR>0 && dist>hi)
        {
         double alt=(c.fvgC1Ext!=0)?c.fvgC1Ext-c.dir*InpSLBufferPts:0;
         double altDist=(alt!=0)?c.dir*(s.entry-alt):0;
         if(altDist>0 && altDist<=hi) dist=MathMax(altDist,(g_pSLFloorATR>0)?lo:0.0);
         else if(InpSLCapMode==SLCAP_CLAMP) dist=hi;                          // v2.40 (RiskGuard) : SL ramené au plafond
         else preReject="SL trop large ("+DoubleToString(dist,1)+" > "+DoubleToString(hi,1)+" pts)";
        }
      s.sl=s.entry-c.dir*dist;
     }
   if(c.dir*(s.entry-s.sl)<=0) return(false);            // entrée déjà au-delà du SL
   s.riskPts=MathAbs(s.entry-s.sl);
   double r=s.riskPts;
   if(crt) dol=CRTTarget(c.dir,s.entry,r,g_crtExtra);
   //--- modèles "liquidité" (SB, Killzone, Momentum) : DOL = 1er pool intact à >= RR min
   if(g_liqTargetW>0)
     {
      double d2=PickLiquidityDOL(c.dir,s.entry,r,g_liqTargetW);
      if(d2>0) dol=d2;
      else if(g_pFallbackRR>0) dol=0;                     // aucun pool assez loin -> cible de secours
     }
   //--- cible : DOL du modèle, plafonnée à g_pMaxRR ; sinon cible de secours à g_pFallbackRR
   if(dol>0 && c.dir*(dol-s.entry)>0 && g_pMaxRR>0 && MathAbs(dol-s.entry)>g_pMaxRR*r)
      dol=s.entry+c.dir*g_pMaxRR*r;
   if((dol<=0 || c.dir*(dol-s.entry)<=0) && g_pFallbackRR>0)
      dol=s.entry+c.dir*g_pFallbackRR*r;
   bool dolOk=(dol>0 && c.dir*(dol-s.entry)>0);
   s.tp2=dolOk?dol:0;
   s.tp1=s.tp2;
   s.tp3=s.tp2;
   //--- gestion CRT (tout l'EA) : BE à 1R, 50 % à 2R, le reste à la DOL (>= 3R)
   if(dolOk && g_pTP1R>0 && c.dir*(s.tp2-(s.entry+c.dir*g_pTP1R*r))>0) s.tp1=s.entry+c.dir*g_pTP1R*r;
   s.planRR=(dolOk && r>0)?MathAbs(s.tp2-s.entry)/r:0;
   s.bePts=InpBEPts;
   s.beTrigger=(InpBEAtR>0)?s.entry+c.dir*InpBEAtR*r:0;
   //--- contexte
   FillMarketContext(s,now,bid,ask);
   double legR=MathAbs(c.extreme-c.legEnd);
   double ret=(legR>0)?MathAbs(s.entry-c.legEnd)/legR:0;
   s.ote=(ret>=0.62 && ret<=0.79)?1:0;
   s.smt=c.smt;
   s.stdvReached=hasRef?((c.dir==-1)?ref.ExtUp():ref.ExtDn()):0;
   //--- expiration de l'ordre / flat
   datetime flatNY=g_anchor+ParseHHMM(InpFlatTime)*SEC_MIN;
   datetime expCap=nowNY+InpPendingMaxMin*SEC_MIN;
   if(expNY<=nowNY || expNY>expCap) expNY=expCap;
   if(expNY>flatNY) expNY=flatNY;
   s.expirySrv=g_tm.NYToServer(expNY);
   s.flatSrv=g_tm.NYToServer(flatNY);
   s.mlProb=-1; s.mlModel=""; s.score=0; s.taken=false;
   s.decision=(preReject!="")?"REJECTED_RISK":"";
   s.reason=preReject;
   return(true);
  }

void Factors(SSignal &s,int &f[])
  {
   ArrayResize(f,ICT_FACTORS);
   f[F_SWEEP_HTF]=(s.liqWeight>=InpHTFWeightMin)?1:0;
   f[F_SMT]=(s.smt==1)?1:0;
   f[F_CISD]=s.cisd;
   f[F_DISPLACEMENT]=s.disp;
   f[F_FVG_VALID]=(s.fvgSize>=g_pMinFVG)?1:0;
   f[F_OTE]=s.ote;
   f[F_QUARTERLY]=s.qAlign;
   f[F_WEEKLY]=(s.weeklyBias!=0 && s.weeklyBias==s.dir)?1:0;
  }

//--- Chaîne de décision. Renvoie la décision (et exécute si TAKEN).
void Decide(SSignal &s,bool conflictThisBar)
  {
   s.adaptOk=false;                                        // v2.50 : vrai seulement si le plan passe les règles du modèle
   datetime now=TimeCurrent();
   int m=CTimeManager::MinuteOfDay(s.tNY);
   int f[];
   Factors(s,f);
   s.score=g_scorer.Score(f);
   if(InpMLMode!=ML_OFF && g_ml.Ready())
     {
      s.mlProb=g_ml.Predict(s,f);
      s.mlModel=g_ml.ModelId();
     }
   if(s.decision!="") return;                              // rejeté dès la construction (SL trop large)
   //--- 1. filtres ICT
   string why="";
   if(now>=s.flatSrv) why="apres l'heure de flat";
   else if(InpBlockLunch && (InMin(m,5*60,7*60) || InMin(m,12*60,13*60+30))) why="lunch";
   else if(s.newsWin==1 && s.model!="CRT_0830") why="news";                 // CRT 08:30 : on trade la réaction
   else if(InpBlockAccumMacro && InMin(m,15*60+15,15*60+45)) why="macro d'accumulation 15:15-15:45";
   else if(InpBlockTrendCounter && s.trendDay==1 && g_opr.opr0930.breakSide==-s.dir) why="contre la tendance du jour";
   else if(InpPDFilter && ((s.dir==1 && s.pdLabel=="PREMIUM") || (s.dir==-1 && s.pdLabel=="DISCOUNT"))) why="premium/discount";
   else if(InpWeeklyBiasFilter && InpWeeklyBias!=WB_NONE && (int)InpWeeklyBias!=s.dir) why="contre le biais hebdo";
   if(why!="") { s.decision="REJECTED_FILTER"; s.reason=why; return; }
   //--- 2. cible / RR (v2.30 : RR minimal propre à la famille du modèle)
   double minRR=ModelMinRR(s.model);
   if(s.planRR<=0 || s.planRR<minRR-RR_EPS)
     {
      s.decision="REJECTED_RISK";
      s.reason=(s.planRR<=0)?"pas de cible (DOL)":"RR "+DoubleToString(s.planRR,2)+" < "+DoubleToString(minRR,1);
      return;
     }
   //--- 3. score ICT (v2.30 : informatif pour les modèles PDF)
   if(ModelUsesScore(s.model) && s.score<g_pScoreMin-1e-6) { s.decision="REJECTED_SCORE"; s.reason="score "+DoubleToString(s.score,0); return; }
   //--- 4. ML (filtre seulement si le modèle est promu ET le mode FILTRE choisi)
   if(InpMLMode==ML_FILTER && g_ml.Ready() && g_ml.Promoted() && s.mlProb>=0 && s.mlProb<g_ml.Threshold())
     { s.decision="REJECTED_ML"; s.reason="p="+DoubleToString(s.mlProb,2); return; }
   //--- 4 bis. v2.50 (apprentissage v6.20) : modèle x session dont l'espérance est négative
   //---        sur les setups déjà résolus (pris ou non : résultat virtuel du CSignalLogger)
   s.adaptOk=true;
   string aw;
   if(InpAdaptGate && g_log.AdaptBlocked(s,InpAdaptMinSamples,aw))
     { s.decision="REJECTED_FILTER"; s.reason=aw; return; }
   //--- 5. risque
   string rs;
   if(!g_risk.CanTrade(rs)) { s.decision="REJECTED_RISK"; s.reason=rs; return; }
   //--- v2.30 : seuls les trades exécutés et les ordres encore en attente comptent (un ordre expiré ne compte plus)
   if(InpMaxTradesDay>0 && g_tm_trades.FilledToday()+g_tm_trades.PendingCount()>=InpMaxTradesDay)
     { s.decision="REJECTED_RISK"; s.reason="max trades/jour"; return; }
   //--- 6. conflit : un seul biais à la fois, jamais buy + sell
   int ad=g_tm_trades.ActiveDirection();
   if(conflictThisBar || (ad!=0 && ad!=s.dir) || g_tm_trades.ActiveCount()>=InpMaxConcurrent)
     { s.decision="REJECTED_CONFLICT"; s.reason="position/ordre deja actif"; return; }
   //--- v2.40 (v6.20 / RiskGuard) : spread et délai minimum entre deux ordres
   double spr=SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double atrSpr=g_atr.Get(PERIOD_M5);
   if(InpMaxSpreadATR>0 && atrSpr>0 && spr>InpMaxSpreadATR*atrSpr)
     { s.decision="REJECTED_FILTER"; s.reason="spread "+DoubleToString(spr,2)+" > "+DoubleToString(InpMaxSpreadATR,2)+" ATR M5"; return; }
   if(InpMinSecondsBetweenTrades>0 && g_lastOrderSrv>0 && now-g_lastOrderSrv<InpMinSecondsBetweenTrades)
     { s.decision="REJECTED_RISK"; s.reason="delai minimum entre deux trades"; return; }
   if(!InpTradingEnabled) { s.decision="OBSERVED"; s.reason="trading desactive (input)"; return; }
   //--- 7. taille et exécution
   double lots=g_risk.CalcLots(s.dir==1,s.entry,s.sl);
   if(lots<=0)
     {
      s.decision="REJECTED_RISK";
      s.reason=(g_risk.LotNote()!="") ? g_risk.LotNote() : "lot < lot minimum (risque trop faible pour ce SL)";
      return;
     }
   if(g_risk.LotNote()!="") Print("Setup ",s.uid," : ",g_risk.LotNote());
   string mnote;
   lots=FitMargin(s.dir,lots,s.entry,mnote);
   if(mnote!="") Print("Setup ",s.uid," : ",mnote);
   if(lots<=0) { s.decision="REJECTED_RISK"; s.reason=mnote; return; }
   double loss=0;
   OrderCalcProfit(s.dir==1?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,lots,s.entry,s.sl,loss);
   //--- v2.40 (RiskGuard) : risque ouvert cumulé plafonné
   if(InpMaxOpenRiskPct>0)
     {
      double cap=AccountInfoDouble(ACCOUNT_EQUITY)*InpMaxOpenRiskPct/100.0;
      double openRisk=g_tm_trades.OpenRiskMoney();
      if(openRisk+MathAbs(loss)>cap+1e-6)
        {
         s.decision="REJECTED_RISK";
         s.reason="risque ouvert "+DoubleToString(openRisk,2)+" + "+DoubleToString(MathAbs(loss),2)+" > plafond "+DoubleToString(cap,2);
         return;
        }
     }
   SetExitWeights(s);
   string err;
   if(!g_tm_trades.Place(s,lots,MathAbs(loss),err)) { s.decision="REJECTED_RISK"; s.reason=err; return; }
   s.decision="TAKEN";
   s.taken=true;
   g_tradesToday++;
   g_lastOrderSrv=now;
  }

#endif
//+------------------------------------------------------------------+
//=== fin ModelRouter.mqh ===

//=== début LondonBridge.mqh ===
//+------------------------------------------------------------------+
//|                                                LondonBridge.mqh  |
//|  v2.30 : branche le moteur « OPR + FVG » (CLondonOprEngine) sur  |
//|  la chaîne de décision d'ICT NAS.                                |
//|                                                                  |
//|  - le moteur reçoit les bougies M1 CLÔTURÉES une par une ;       |
//|  - chaque « entrée autorisée » du moteur devient un signal       |
//|    LONDON_OPR_PDF (OPR 1) ou OPRPDF_hhmm (autres OPR, si une     |
//|    fenêtre est configurée) qui passe par Decide() : filtres,     |
//|    RR du modèle, ML, risque, conflit, puis ordre limite ;        |
//|  - chaque annulation du moteur (FVG invalidé, cible atteinte     |
//|    avant l'entrée, fin de fenêtre, trade book clôturé) supprime  |
//|    l'ordre en attente correspondant ;                            |
//|  - l'identifiant du signal (LP + id du setup) est déterministe : |
//|    après un redémarrage, un ordre déjà envoyé n'est pas doublé.  |
//|  Le moteur ne lit jamais une bougie en formation.                |
//+------------------------------------------------------------------+
#ifndef ICTNAS_LONDONBRIDGE_MQH
#define ICTNAS_LONDONBRIDGE_MQH

#define LO_LAST_MSGS 3

bool              g_loReady=false;     // historique rejoué
bool              g_loLive=false;      // false pendant le rattrapage : aucun ordre, aucun journal
datetime          g_loLastBar=0;       // dernière bougie M1 transmise au moteur (heure serveur)
double            g_loTick=0;
int               g_loJournal=INVALID_HANDLE;
long              g_loQueue[];         // setups autorisés à transformer en signaux
string            g_loLast[LO_LAST_MSGS];

string LoUid(const long setupId) { return("LP"+IntegerToString(setupId)); }

//--- nom du modèle : OPR 1 = London OPR du PDF ; autres OPR (si une fenêtre est configurée) : OPRPDF_hhmm
string LoModel(const int slot)
  {
   if(slot==0) return(LO_MODEL);
   string hm=OprHHMM(g_lo.cfg.slots[slot].calc.startMin);
   StringReplace(hm,":","");
   return("OPRPDF_"+hm);
  }

//--- arrondi au tick dans le sens qui garde le déclenchement identique au modèle book du moteur
double LoNormUp(const double p)   { return(NormalizeDouble(MathCeil(p/g_loTick-1e-9)*g_loTick,_Digits)); }
double LoNormDown(const double p) { return(NormalizeDouble(MathFloor(p/g_loTick+1e-9)*g_loTick,_Digits)); }

void LoAdd(string &a[],const string s) { int n=ArraySize(a); ArrayResize(a,n+1); a[n]=s; }

void LoResetState(void)
  {
   g_loReady=false;
   g_loLive=false;
   g_loLastBar=0;
   ArrayResize(g_loQueue,0);
   for(int i=0;i<LO_LAST_MSGS;i++) g_loLast[i]="";
  }

//+------------------------------------------------------------------+
//| Configuration du moteur (inputs du groupe London OPR PDF)        |
//+------------------------------------------------------------------+
bool LoFail(string &err,const string msg) { err=msg; return(false); }

bool LoParseSlot(OPRConfig &c,const int s,const string range,const bool trade,const string window,const string macros,string &err)
  {
   string name="OPR "+IntegerToString(s+1);
   OPRTimeRange r;
   if(!OprParseRange(range,r)) return(LoFail(err,name+" : plage '"+range+"' (format HH:MM-HH:MM)"));
   c.slots[s].calc=r;
   c.slots[s].tradeEnabled=false;
   g_lo.slotName[s]=r.valid ? name+" "+OprHHMM(r.startMin) : name;
   if(s==0 && r.valid) g_lo.slotName[s]="MOR "+OprHHMM(r.startMin);
   if(!trade) return(true);
   if(!r.valid) return(LoFail(err,name+" : modele d'entree actif mais plage de calcul vide"));
   OPRTimeRange w;
   if(!OprParseRange(window,w)) return(LoFail(err,name+" : fenetre '"+window+"'"));
   if(!w.valid)
      return(LoFail(err,name+" : modele d'entree actif sans fenetre de trading. Aucune regle n'est documentee pour cet OPR : "+
                    "desactivez l'entree ou renseignez la fenetre et les macros."));
   if(!g_lo.tm.FitsInSession(r) || !g_lo.tm.FitsInSession(w))
      return(LoFail(err,name+" : plage ou fenetre a cheval sur 18:00 NY (debut de la journee de trading)"));
   int calcEnd=g_lo.tm.SessionMinute(r.startMin)+r.Length();
   if(g_lo.tm.SessionMinute(w.startMin)<calcEnd)
      return(LoFail(err,name+" : la fenetre de trading commence avant la fin de l'OPR (le biais exige un OPR finalise)"));
   OPRTimeRange ms[];
   if(!OprParseRanges(macros,ms)) return(LoFail(err,name+" : macros '"+macros+"'"));
   int n=ArraySize(ms);
   if(n>OPR_MAX_MACROS) return(LoFail(err,name+StringFormat(" : %d macros maximum",OPR_MAX_MACROS)));
   if(n==0 && InpLORequireMacro) return(LoFail(err,name+" : aucune macro alors que 'macro exigee' est actif"));
   for(int i=0;i<n;i++)
     {
      int ws=g_lo.tm.SessionMinute(w.startMin);
      int m0=g_lo.tm.SessionMinute(ms[i].startMin);
      if(m0<ws || m0+ms[i].Length()>ws+w.Length())
         Print("London OPR - attention : ",name," macro ",OprRangeText(ms[i])," deborde de la fenetre ",OprRangeText(w));
      c.slots[s].macros[i]=ms[i];
     }
   c.slots[s].macroCount=n;
   c.slots[s].window=w;
   c.slots[s].tradeEnabled=true;
   return(true);
  }

double LoTicks(const double pts) { return((pts>0 && g_loTick>0) ? pts/g_loTick : 1.0); }

bool LoBuildConfig(OPRConfig &c,string &err)
  {
   c.Defaults();
   //--- fuseau : toutes les heures de la stratégie sont en New York ; le serveur suit InpServerTZ
   c.stratTz=OPR_STZ_NEW_YORK;
   if(InpServerTZ==TZ_NY_PLUS_7)       { c.serverMode=OPR_SRV_GMT_US_DST; c.serverGmtSec=2*3600; }
   else if(InpServerTZ==TZ_GMT_EU_DST) { c.serverMode=OPR_SRV_GMT_EU_DST; c.serverGmtSec=InpServerGMTOff*3600; }
   else                                { c.serverMode=OPR_SRV_GMT_FIXED;  c.serverGmtSec=InpServerGMTOff*3600; }
   c.dayStartMin=18*60;
   g_lo.tm.Configure(c.stratTz,c.serverMode,c.serverGmtSec,c.dayStartMin);

   if(!OprParseRange(InpLOAsiaRange,c.asia))     return(LoFail(err,"plage asiatique '"+InpLOAsiaRange+"'"));
   if(!OprParseRange(InpLOLondonRange,c.london)) return(LoFail(err,"session de Londres '"+InpLOLondonRange+"'"));
   if(!OprParseRange(InpLOObsWindow,c.observe))  return(LoFail(err,"fenetre d'observation '"+InpLOObsWindow+"'"));
   if(!g_lo.tm.FitsInSession(c.asia))            return(LoFail(err,"la plage asiatique doit tenir dans la journee de trading (debut 18:00 NY)"));

   if(!LoParseSlot(c,0,InpLOOpr1Range,InpLOOpr1Trade,InpLOOpr1Window,InpLOOpr1Macros,err)) return(false);
   if(!LoParseSlot(c,1,InpLOOpr2Range,InpLOOpr2Trade,InpLOOpr2Window,InpLOOpr2Macros,err)) return(false);
   if(!LoParseSlot(c,2,InpLOOpr3Range,InpLOOpr3Trade,InpLOOpr3Window,InpLOOpr3Macros,err)) return(false);
   if(!LoParseSlot(c,3,InpLOOpr4Range,InpLOOpr4Trade,InpLOOpr4Window,InpLOOpr4Macros,err)) return(false);

   c.asiaRule           =InpLOAsiaRule;
   c.asiaMinGapTicks    =LoTicks(InpLOAsiaMinGapPts);
   c.midnightMinGapTicks=LoTicks(InpLOMidMinGapPts);
   c.entryTfMin         =InpLOEntryTF;
   c.entryLevel         =InpLOEntryLevel;
   c.minFvgTicks        =LoTicks(InpLOMinFvgPts);
   c.liqM1              =InpLOLiqM1;
   c.liqPivotM1         =MathMax(InpLOLiqPivotM1,1);
   c.liqM15             =InpLOLiqM15;
   c.liqPivotM15        =MathMax(InpLOLiqPivotM15,1);
   c.liqAsia            =InpLOLiqAsia;
   c.requireMacro       =InpLORequireMacro;
   c.oneTradePerMacro   =InpLOOneTradePerMacro;
   c.consolRequireSweep =InpLOConsolRequireSweep;
   c.stopBufferTicks    =LoTicks(InpLOStopBufferPts);
   c.tpStd              =InpLOTpStd;
   c.graceMin           =MathMax(InpLOGraceMin,0);
   c.minStop            =InpLOMinStopPts;
   c.maxStop            =InpLOMaxStopPts;
   c.maxOpenTrades      =1;
   c.maxTradesDay       =0;
   c.tickSize           =g_loTick;
   if(InpLOTpStd<=0) return(LoFail(err,"la cible doit etre une deviation standard > 0"));
   if(!InpLOLiqM1 && !InpLOLiqM15 && !InpLOLiqAsia) return(LoFail(err,"aucune source de liquidite : le modele ne pourrait jamais entrer"));
   return(true);
  }

void LoLogConfig(void)
  {
   for(int s=0;s<OPR_MAX_SLOTS;s++)
     {
      if(!g_lo.cfg.slots[s].calc.valid) continue;
      string m="";
      for(int i=0;i<g_lo.cfg.slots[s].macroCount;i++) m+=(i>0?", ":"")+OprRangeText(g_lo.cfg.slots[s].macros[i]);
      if(g_lo.cfg.slots[s].tradeEnabled)
         Print("London OPR : ",g_lo.slotName[s]," ",OprRangeText(g_lo.cfg.slots[s].calc)," -> fenetre ",OprRangeText(g_lo.cfg.slots[s].window),
               " macros ",m,StringFormat(" | FVG d'entree M%d, cible %.2f STD | modele %s",g_lo.cfg.entryTfMin,g_lo.cfg.tpStd,LoModel(s)));
      else
         Print("London OPR : ",g_lo.slotName[s]," ",OprRangeText(g_lo.cfg.slots[s].calc)," -> niveaux et contexte seulement (entree desactivee)");
     }
   string mode=!InpUseLondonOPR ? "desactive (niveaux et journal seulement)" :
               (InpLondonMode==LONDON_PDF ? "PDF (moteur OPR + FVG)" : (InpLondonMode==LONDON_LEGACY ? "v2.22 (moteur en observation)" : "PDF + v2.22"));
   Print("London OPR : implementation ",mode," | gestion ",(InpLondonManage==LM_PDF?"PDF (cible unique)":"ICT NAS (BE + partiel)"),
         " | RR min ",DoubleToString(InpLondonMinRR,2));
  }

//+------------------------------------------------------------------+
//| Persistance des OPR finalisés (variables globales du terminal)   |
//+------------------------------------------------------------------+
string LoGvName(const int s,const string what)
  {
   return("ICTNAS_"+IntegerToString(InpMagic)+"_"+_Symbol+"_LO"+IntegerToString(s)+"_"+what);
  }

void LoSaveOpr(const int s)
  {
   GlobalVariableSet(LoGvName(s,"D"),(double)g_lo.opr[s].m_st.day);
   GlobalVariableSet(LoGvName(s,"H"),g_lo.opr[s].m_st.high);
   GlobalVariableSet(LoGvName(s,"L"),g_lo.opr[s].m_st.low);
  }

void LoRestoreLevels(void)
  {
   if(!InpLOPersist) return;
   for(int s=0;s<OPR_MAX_SLOTS;s++)
     {
      if(!GlobalVariableCheck(LoGvName(s,"D"))) continue;
      int day=(int)GlobalVariableGet(LoGvName(s,"D"));
      double h=GlobalVariableGet(LoGvName(s,"H"));
      double l=GlobalVariableGet(LoGvName(s,"L"));
      if(day!=g_lo.m_day) continue;
      if(g_lo.opr[s].m_st.status==OPR_ST_FINAL)
        {
         if(MathAbs(g_lo.opr[s].m_st.high-h)>g_loTick*0.5 || MathAbs(g_lo.opr[s].m_st.low-l)>g_loTick*0.5)
            Print("London OPR - attention : ",g_lo.slotName[s]," recalcule (",PxStr(g_lo.opr[s].m_st.high),"/",PxStr(g_lo.opr[s].m_st.low),
                  ") different de la sauvegarde (",PxStr(h),"/",PxStr(l),") : historique du broker modifie, le recalcul est conserve");
        }
      else if(g_lo.RestoreOpr(s,day,h,l))
        {
         Print("London OPR : ",g_lo.slotName[s]," restaure depuis la sauvegarde (historique insuffisant) : ",PxStr(h)," / ",PxStr(l));
         g_lo.jr.Clear();
        }
     }
  }

//+------------------------------------------------------------------+
//| Journal (CSV + Experts) et événements du moteur                  |
//+------------------------------------------------------------------+
void LoOpenJournal(void)
  {
   if(!InpLOJournalCsv) return;
   string fn="ICTNAS\\"+_Symbol+"_london_opr_journal.csv";
   FolderCreate("ICTNAS",FILE_COMMON);
   if(InpFreshDBInTester && MQLInfoInteger(MQL_TESTER)) FileDelete(fn,FILE_COMMON);
   g_loJournal=FileOpen(fn,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ|FILE_COMMON,';');
   if(g_loJournal==INVALID_HANDLE) { Print("London OPR : impossible d'ouvrir le journal ",fn); return; }
   FileSeek(g_loJournal,0,SEEK_END);
   if(FileTell(g_loJournal)==0)
      FileWrite(g_loJournal,"heure_serveur","heure_ny","code","opr","sens","raison","id","p1","p2","p3","p4","message");
  }

void LoCloseJournal(void)
  {
   if(g_loJournal!=INVALID_HANDLE) FileClose(g_loJournal);
   g_loJournal=INVALID_HANDLE;
  }

void LoQueue(const long id)
  {
   for(int i=0;i<ArraySize(g_loQueue);i++) if(g_loQueue[i]==id) return;
   int n=ArraySize(g_loQueue);
   ArrayResize(g_loQueue,n+1);
   g_loQueue[n]=id;
  }

//--- le moteur a abandonné le setup (ou son trade book est clôturé) : l'ordre en attente correspondant est supprimé
void LoCancelReal(const long id,const int reason)
  {
   string uid=LoUid(id);
   if(g_tm_trades.CancelUid(uid))
      Print("London OPR : ordre ",uid," supprime (",(reason>0?OprReasonText(reason):"trade book cloture"),")");
   g_log.CancelPending(uid,TimeCurrent());
  }

void LoOnEvent(const OJEvent &e)
  {
   if(e.code==J_OPR_FINAL && e.aux==0 && InpLOPersist && e.slot>=0) LoSaveOpr(e.slot);
   if(!g_loLive) return;
   if(e.code==J_ENTRY_AUTHORIZED) LoQueue(e.id);
   if(e.code==J_SETUP_CANCELLED)  LoCancelReal(e.id,e.reason);
   if(e.code==J_TRADE_CLOSED)     LoCancelReal(e.id,0);
   string name=(e.slot>=0 && e.slot<OPR_MAX_SLOTS) ? g_lo.slotName[e.slot] : "";
   string txt=OprEventText(e,name,_Digits);
   string clock=OprHHMM(g_lo.tm.MinuteOfDay(e.st));
   if(g_loJournal!=INVALID_HANDLE)
     {
      FileWrite(g_loJournal,TimeToString(e.srv,TIME_DATE|TIME_MINUTES),clock,e.code,e.slot+1,e.dir,e.reason,
                IntegerToString(e.id),PxStr(e.p1),PxStr(e.p2),PxStr(e.p3),DoubleToString(e.p4,2),txt);
      FileFlush(g_loJournal);
     }
   bool important=(e.code==J_OPR_FINAL || e.code==J_BIAS || e.code==J_BIAS_BREAKOUT || e.code==J_BIAS_CONSOL ||
                   e.code==J_SWEEP || e.code==J_ENTRY_AUTHORIZED || e.code==J_ENTRY_REJECTED || e.code==J_SETUP_CANCELLED ||
                   e.code==J_TRADE_FILLED || e.code==J_TRADE_CLOSED || e.code==J_ASIA_FVG);
   if(!important) return;
   for(int i=LO_LAST_MSGS-1;i>0;i--) g_loLast[i]=g_loLast[i-1];
   g_loLast[0]=clock+" "+txt;
   if(InpLOJournalPrint) Print("London OPR [",clock," NY] ",txt);
  }

void LoFeed(const MqlRates &r)
  {
   g_lo.ProcessBar(r.time,r.open,r.high,r.low,r.close);
   for(int i=0;i<g_lo.jr.m_count;i++) LoOnEvent(g_lo.jr.m_ev[i]);
  }

//+------------------------------------------------------------------+
//| FPFVG Asie / Midnight : références du moteur                     |
//+------------------------------------------------------------------+
void LoFvgToSFVG(const long id,SFVG &out)
  {
   out.Clear();
   int fi=g_lo.FindFvgIdx(id);
   if(fi<0) return;
   out.valid =true;
   out.dir   =g_lo.fvgs.m_list[fi].dir;
   out.top   =g_lo.fvgs.m_list[fi].hi;
   out.bottom=g_lo.fvgs.m_list[fi].lo;
   out.t1    =g_lo.fvgs.m_list[fi].c1Srv;
   out.t3    =(datetime)((long)g_lo.fvgs.m_list[fi].formedSrv-(long)g_lo.fvgs.m_list[fi].tfMin*60);
  }

void LoSyncFPFVG(void)
  {
   if(!InpFPFVGFromEngine) return;
   LoFvgToSFVG(g_lo.m_asiaFvgId,g_fpAsia);
   LoFvgToSFVG(g_lo.m_midFvgId,g_fpMid);
  }

//+------------------------------------------------------------------+
//| Historique et nouvelles bougies                                  |
//+------------------------------------------------------------------+
bool LoWarmup(void)
  {
   int avail=Bars(_Symbol,PERIOD_M1);
   if(avail<200) return(false);
   int want=MathMin(MathMax(InpLOWarmupDays,1)*1440+120,avail-1);
   MqlRates r[];
   int got=CopyRates(_Symbol,PERIOD_M1,1,want,r);
   if(got<200) return(false);
   g_loLive=false;
   for(int i=0;i<got;i++) LoFeed(r[i]);
   g_loLastBar=r[got-1].time;
   LoRestoreLevels();
   g_loLive=true;
   g_loReady=true;
   //--- setup armé pendant le rattrapage : traité comme une autorisation (l'uid empêche tout doublon)
   for(int s=0;s<OPR_MAX_SLOTS;s++)
      if(g_lo.su[s].state==SU_ARMED) LoQueue(g_lo.su[s].setupId);
   LoSyncFPFVG();
   PrintFormat("London OPR : %d bougies M1 rejouees, etat du jour : %s",got,OprSetupStateText(g_lo.su[0].state));
   return(true);
  }

void LoProcessNewBars(void)
  {
   if(!g_loReady && !LoWarmup()) return;
   datetime lastClosed=iTime(_Symbol,PERIOD_M1,1);
   if(lastClosed==0 || lastClosed<=g_loLastBar) return;
   int shift=iBarShift(_Symbol,PERIOD_M1,g_loLastBar,true);
   int count=(shift>1) ? shift-1 : 1;
   if(shift<0) count=500;
   if(count>5000) count=5000;
   MqlRates r[];
   int got=CopyRates(_Symbol,PERIOD_M1,1,count,r);
   for(int i=0;i<got;i++)
     {
      if(r[i].time<=g_loLastBar) continue;
      LoFeed(r[i]);
      g_loLastBar=r[i].time;
     }
   LoSyncFPFVG();
  }

//+------------------------------------------------------------------+
//| Setup armé du moteur -> signal ICT NAS                           |
//+------------------------------------------------------------------+
//--- extension STDV déjà atteinte par l'OPR de référence (contexte enregistré)
double LoStdvReached(const int slot,const int dir)
  {
   if(slot==0) return(dir==-1 ? g_opr.mor.ExtUp()     : g_opr.mor.ExtDn());
   if(slot==1) return(dir==-1 ? g_opr.opr0700.ExtUp() : g_opr.opr0700.ExtDn());
   if(slot==2) return(dir==-1 ? g_opr.opr0930.ExtUp() : g_opr.opr0930.ExtDn());
   return(dir==-1 ? g_opr.opr1330.ExtUp() : g_opr.opr1330.ExtDn());
  }

bool LoBuildSignal(const int slot,SSignal &s)
  {
   datetime now=TimeCurrent();
   datetime nowNY=g_tm.ServerToNY(now);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID),ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   int dir=g_lo.su[slot].dir;
   long id=g_lo.su[slot].setupId;
   if(dir==0 || id==0) return(false);
   s.model=LoModel(slot);
   s.dir=dir;
   s.tSrv=now;
   s.tNY=nowNY;
   s.uid=LoUid(id);
   s.fixedUid=true;
   s.extId=id;
   s.slot=slot;
   s.extKey="";
   s.adaptOk=false;
   FillTimeContext(s,nowNY);
   //--- liquidité prise (règle du PDF : « la macro doit commencer par prendre une liquidité »)
   int src=g_lo.su[slot].sweepSrc;
   s.liqType=(src==LIQ_SRC_ASIA) ? "ASIA" : (src==LIQ_SRC_M15 ? "SWING_M15" : (src==LIQ_SRC_M1 ? "SWING_M1" : "OPR_BREAKOUT"));
   s.liqWeight=(src==LIQ_SRC_ASIA) ? CLiquidityEngine::Weight(LIQ_ASIA) : (src==LIQ_SRC_M15 ? CLiquidityEngine::Weight(LIQ_SWING_M15) : (src==LIQ_SRC_M1 ? 2 : 0));
   s.liqPrice=g_lo.su[slot].sweepLevel;
   s.tSweep=(datetime)g_lo.SrvOf(g_lo.su[slot].sweepT);
   s.tSweepNY=g_tm.ServerToNY(s.tSweep);
   //--- structure : le PDF n'exige ni MSS/CISD ni displacement minimal
   s.mss=0; s.cisd=0; s.disp=0; s.dispBodyATR=0; s.dispCandles=0; s.dispSize=0;
   s.atr1=g_atr.Get(PERIOD_M1); s.atr5=g_atr.Get(PERIOD_M5); s.atr15=g_atr.Get(PERIOD_M15);
   s.ifvg=0; s.breaker=0; s.unicorn=0; s.ob=0;
   s.fvgTop=g_lo.su[slot].fvgHi;
   s.fvgBot=g_lo.su[slot].fvgLo;
   s.fvgCE=(s.fvgTop+s.fvgBot)/2.0;
   s.fvgSize=s.fvgTop-s.fvgBot;
   int fi=g_lo.FindFvgIdx(g_lo.su[slot].fvgId);
   s.tFVG=(fi>=0) ? g_lo.fvgs.m_list[fi].c1Srv : now;
   s.fvgType=OverlapsFPFVG(s.fvgTop,s.fvgBot) ? "FPFVG" : "CLASSIC";
   //--- plan du moteur : limite au bord du FVG, SL au-delà du swing, cible ±k STD de l'OPR
   s.market=false;
   s.entry=(dir<0) ? LoNormUp(g_lo.su[slot].entry) : LoNormDown(g_lo.su[slot].entry);
   s.sl   =(dir<0) ? LoNormUp(g_lo.su[slot].sl)    : LoNormDown(g_lo.su[slot].sl);
   double tp=(dir<0) ? LoNormDown(g_lo.su[slot].tp) : LoNormUp(g_lo.su[slot].tp);
   if(dir*(s.entry-s.sl)<=0 || dir*(tp-s.entry)<=0) return(false);
   s.inval=0;
   s.riskPts=MathAbs(s.entry-s.sl);
   double r=s.riskPts;
   s.tp1=tp; s.tp2=tp; s.tp3=tp;
   if(InpLondonManage==LM_ICTNAS && g_pTP1R>0 && dir*(tp-(s.entry+dir*g_pTP1R*r))>0) s.tp1=s.entry+dir*g_pTP1R*r;
   s.planRR=(r>0) ? MathAbs(tp-s.entry)/r : 0;
   s.bePts=InpBEPts;
   s.beTrigger=(InpLondonManage==LM_ICTNAS && InpBEAtR>0) ? s.entry+dir*InpBEAtR*r : 0;
   //--- PDF Macro : « si ta cible est prise avant que le marché t'ait donné une entrée, pas de trade »
   s.cancelPx=tp;
   s.chaseR=InpLOMaxChaseR;
   //--- contexte (mêmes colonnes que les autres modèles)
   FillMarketContext(s,now,bid,ask);
   s.ote=0;
   s.smt=-1;
   s.stdvReached=LoStdvReached(slot,dir);
   //--- expiration : fin de la fenêtre du moteur (+ grâce), jamais après le flat
   datetime flatSrv=g_tm.NYToServer(g_anchor+ParseHHMM(InpFlatTime)*SEC_MIN);
   datetime expSrv=(datetime)g_lo.SrvOf(g_lo.su[slot].winE+(long)g_lo.cfg.graceMin*60);
   s.expirySrv=(expSrv<flatSrv) ? expSrv : flatSrv;
   s.flatSrv=flatSrv;
   s.mlProb=-1; s.mlModel=""; s.score=0; s.taken=false;
   s.decision=""; s.reason="";
   return(true);
  }

//--- signaux London de la bougie (appelé par ProcessSetups) ; renvoie le nouveau nombre de signaux
int LoCollectSignals(SSignal &sigs[],int k)
  {
   int n=ArraySize(g_loQueue);
   for(int q=0;q<n;q++)
     {
      long id=g_loQueue[q];
      int s=(int)(id%4);
      if(s<0 || s>=OPR_MAX_SLOTS) continue;
      if(g_lo.su[s].state!=SU_ARMED || g_lo.su[s].setupId!=id) continue;    // déjà exécuté ou annulé par le moteur
      if(!InpUseLondonOPR || InpLondonMode==LONDON_LEGACY) continue;         // moteur en observation (niveaux, journal)
      string uid=LoUid(id);
      if(g_tm_trades.ExistsOnServer(uid)) continue;                           // déjà envoyé avant un redémarrage
      SSignal sg;
      if(!LoBuildSignal(s,sg)) continue;
      ArrayResize(sigs,k+1);
      sigs[k]=sg;
      k++;
     }
   ArrayResize(g_loQueue,0);
   return(k);
  }

//+------------------------------------------------------------------+
//| Panneau et diagnostic                                            |
//+------------------------------------------------------------------+
void LoPanelLines(string &L[])
  {
   string mode=!InpUseLondonOPR ? "OFF" : (InpLondonMode==LONDON_PDF ? "PDF" : (InpLondonMode==LONDON_LEGACY ? "v2.22" : "PDF+v2.22"));
   if(!g_loReady) { LoAdd(L,"London OPR "+mode+" : rattrapage de l'historique en attente"); return; }
   string lv=(g_lo.opr[0].m_st.status==OPR_ST_FINAL) ? PxStr(g_lo.opr[0].m_st.high)+"/"+PxStr(g_lo.opr[0].m_st.low)
                                                       : OprRangeStatusText(g_lo.opr[0].m_st.status);
   LoAdd(L,"London OPR "+mode+" | "+g_lo.slotName[0]+" "+lv+" | biais "+OprDirText(g_lo.su[0].dir)+
           " | book "+IntegerToString(g_lo.stats.trades)+" trades "+DoubleToString(g_lo.stats.netR,1)+"R");
   LoAdd(L,"  "+OprSetupStateText(g_lo.su[0].state));
   for(int i=0;i<LO_LAST_MSGS;i++) if(g_loLast[i]!="") LoAdd(L,"  "+g_loLast[i]);
  }

void LoDiagLines(string &a[])
  {
   ArrayResize(a,0);
   LoAdd(a,"6. London OPR PDF (moteur) : jours "+IntegerToString(g_lo.stats.days)+" | biais achat "+IntegerToString(g_lo.stats.biasBuy)+
           " / vente "+IntegerToString(g_lo.stats.biasSell)+" / consolidation "+IntegerToString(g_lo.stats.biasConsol));
   LoAdd(a,"   prises de liquidite "+IntegerToString(g_lo.stats.sweeps)+" | FVG candidats "+IntegerToString(g_lo.stats.candidates)+
           " | setups armes "+IntegerToString(g_lo.stats.armed)+" | trades book "+IntegerToString(g_lo.stats.trades)+
           " ("+DoubleToString(g_lo.stats.netR,1)+"R)");
   LoAdd(a,"   rejets : sans sweep "+IntegerToString(g_lo.stats.rejected[R_NO_SWEEP])+" | hors macro "+IntegerToString(g_lo.stats.rejected[R_OUTSIDE_MACRO])+
           " | macro deja tradee "+IntegerToString(g_lo.stats.rejected[R_MACRO_USED])+" | cible deja atteinte "+IntegerToString(g_lo.stats.rejected[R_TARGET_REACHED])+
           " | OPR non finalise "+IntegerToString(g_lo.stats.rejected[R_NO_OPR])+" | position book ouverte "+IntegerToString(g_lo.stats.rejected[R_IN_POSITION]));
  }

#endif
//+------------------------------------------------------------------+
//=== fin LondonBridge.mqh ===

//=== début V6Bridge.mqh ===
//+------------------------------------------------------------------+
//|                                                    V6Bridge.mqh  |
//|  v2.40 : branche les modèles de la v6.20 (SB_V6, MACRO_BREAKER)  |
//|  sur la chaîne de décision d'ICT NAS.                            |
//|  À chaque nouvelle bougie M1, dans une fenêtre Silver Bullet ou  |
//|  une macro autorisée : carte de liquidité v6.20, niveaux de      |
//|  référence, évaluation stricte puis relâchée (après N minutes),  |
//|  arbitrage de la v6.20 (strict > relâché > score > Unicorn), puis|
//|  un signal ICT NAS -> Decide() (filtres, ML, risque, conflit).   |
//|  Un setup n'est décidé qu'une fois ; une fenêtre / macro ne donne|
//|  qu'InpV6MaxTradesPerWindow trade(s) (« 1 macro = 1 trade »),    |
//|  compté comme la v6.20 : ordres v6.20 en attente + entrées v6.20 |
//|  depuis le début de la fenêtre / macro.                          |
//+------------------------------------------------------------------+
#ifndef ICTNAS_V6BRIDGE_MQH
#define ICTNAS_V6BRIDGE_MQH

#define V6_LTF_BARS 400
#define V6_M1_BARS  420
#define V6_HTF_BARS 400
#define V6_D1_BARS  80

CV6Clock          g_v6clock;
CV6LiqMap         g_v6liq;
CV6RefLevels      g_v6ref;
CV6SilverBullet   g_v6sb;
CV6MacroBreaker   g_v6mb;
SV6SBParams       g_v6spStrict,g_v6spRelax;
SV6MBParams       g_v6mpStrict,g_v6mpRelax;
int               g_v6hLTF=INVALID_HANDLE,g_v6hM1=INVALID_HANDLE,g_v6hD1=INVALID_HANDLE;
MqlRates          g_v6ltf[],g_v6m1[],g_v6htf[],g_v6d1[];
double            g_v6atrLTF[],g_v6atrM1[],g_v6atrD1[];
int               g_v6ltfN=0,g_v6m1N=0,g_v6htfN=0,g_v6d1N=0;
string            g_v6consumed[];
string            g_v6Status="";
//--- diagnostic (cumul depuis le lancement)
int               g_v6nSB=0,g_v6nMB=0,g_v6nRelax=0,g_v6nWinCap=0,g_v6nTaken=0;
string            g_v6rejKey[];
int               g_v6rejCnt[];

bool V6Enabled(void) { return(InpV6EnableSB || InpV6EnableMB); }

bool V6ValidateInputs(string &err)
  {
   err="";
   if(!V6Enabled()) return(true);
   if(PeriodSeconds(InpV6LTF)>=PeriodSeconds(InpV6HTF)) err="InpV6LTF doit etre inferieur a InpV6HTF";
   else if(PeriodSeconds(InpV6MBTimeframe)>PeriodSeconds(InpV6LTF)) err="InpV6MBTimeframe doit etre <= InpV6LTF";
   else if(InpV6SwingStrength<1 || InpV6SwingStrength>5) err="InpV6SwingStrength entre 1 et 5";
   else if(InpV6MinRR<1.0) err="InpV6MinRR doit etre >= 1";
   else if(InpV6SBMinRetrace<0 || InpV6SBMinRetrace>1) err="InpV6SBMinRetrace entre 0 et 1";
   else if(InpV6EnableSB && !InpV6UseLondonSB && !InpV6UseNYAMSB && !InpV6UseNYPMSB) err="aucune fenetre Silver Bullet v6 activee";
   return(err=="");
  }

void V6Init(void)
  {
   ArrayResize(g_v6consumed,0);
   ArrayResize(g_v6rejKey,0);
   ArrayResize(g_v6rejCnt,0);
   g_v6nSB=0; g_v6nMB=0; g_v6nRelax=0; g_v6nWinCap=0; g_v6nTaken=0;
   g_v6Status="";
   if(!V6Enabled()) return;
   g_v6hLTF=iATR(_Symbol,InpV6LTF,14);
   g_v6hM1=iATR(_Symbol,InpV6MBTimeframe,14);
   g_v6hD1=iATR(_Symbol,PERIOD_D1,14);
   ArraySetAsSeries(g_v6ltf,true);
   ArraySetAsSeries(g_v6m1,true);
   ArraySetAsSeries(g_v6htf,true);
   ArraySetAsSeries(g_v6d1,true);
   ArraySetAsSeries(g_v6atrLTF,true);
   ArraySetAsSeries(g_v6atrM1,true);
   ArraySetAsSeries(g_v6atrD1,true);
   g_v6clock.Init(GetPointer(g_tm),InpV6UseLondonSB,InpV6UseNYAMSB,InpV6UseNYPMSB,InpV6MBMacros);
   g_v6ref.Init(GetPointer(g_v6clock),InpV6UseOPRLevels,InpV6UseTBRLevels,InpV6UseNDOGLevels);

   //--- paramètres Silver Bullet (valeurs de la v6.20)
   SV6SBParams sp;
   sp.swingStrength=InpV6SwingStrength;
   sp.sweepMinATR=InpV6SweepMinATR;
   sp.sweepConfirmBars=InpV6SweepConfirmBars;
   sp.sweepMaxEpisodeBars=InpV6SweepMaxEpisodeBars;
   sp.sweepLookbackBars=InpV6SweepLookbackBars;
   sp.preSweepMinutes=InpV6PreSweepMinutes;
   sp.mssMaxBars=InpV6MSSMaxBars;
   sp.mssMinRangeATR=InpV6MSSMinRangeATR;
   sp.dispBodyATR=InpV6DispBodyATR;
   sp.fvgMinSizeATR=InpV6FVGMinSizeATR;
   sp.entryMode=InpV6EntryMode;
   sp.requireDiscount=InpV6RequireDiscount;
   sp.requireHTFAlign=InpV6RequireHTFAlign;
   sp.useOTEBonus=InpV6UseOTEBonus;
   sp.useMacroBonus=InpV6UseMacroBonus;
   sp.minScore=InpV6MinSetupScore;
   sp.slBufferATR=InpV6SLBufferATR;
   sp.tpBufferATR=InpV6TPBufferATR;
   sp.tpMode=InpV6TPMode;
   sp.minRR=InpV6MinRR;
   sp.maxTPDistATRD1=InpV6MaxTPDistATRD1;
   sp.maxStopATR=InpV6MaxStopATR;
   sp.allowFixedRRFallback=InpV6AllowFixedRRFallback;
   sp.utbotConfirm=InpV6UTBotConfirm;
   sp.utbotKey=InpV6UTBotKey;
   sp.useTrueOpenBonus=InpV6UseTrueOpenBonus;
   sp.requireTrueOpen=InpV6RequireTrueOpen;
   sp.useRefLevelBonus=InpV6UseRefLevelBonus;
   sp.refLevelTolATR=InpV6RefLevelTolATR;
   sp.useDOWScore=InpV6UseDOWScore;
   sp.useBPRBonus=InpV6UseBPRBonus;
   sp.useSDTargets=InpV6UseSDTargets;
   sp.eqWarnATR=InpV6EqWarnATR;
   sp.fvgRequireBody=InpV6FVGRequireBody;
   sp.takeFirstFVG=InpV6SBTakeFirstFVG;
   sp.minRetrace=InpV6SBMinRetrace;
   g_v6spStrict=sp;
   g_v6spRelax=sp;
   g_v6spRelax.requireHTFAlign=false;
   g_v6spRelax.requireDiscount=false;
   g_v6spRelax.requireTrueOpen=false;
   g_v6spRelax.fvgRequireBody=false;
   g_v6spRelax.minScore=(int)MathMax(0,InpV6MinSetupScore-3);
   g_v6spRelax.minRR=MathMax(1.5,InpV6MinRR-0.5);
   g_v6spRelax.dispBodyATR=InpV6DispBodyATR*0.6;
   g_v6spRelax.fvgMinSizeATR=InpV6FVGMinSizeATR*0.6;
   g_v6spRelax.sweepMinATR=InpV6SweepMinATR*0.6;
   g_v6spRelax.minRetrace=0.0;
   g_v6sb.Init(_Symbol,GetPointer(g_v6clock),GetPointer(g_v6liq),GetPointer(g_v6ref),g_v6spStrict);

   //--- paramètres Macro Breaker (valeurs de la v6.20)
   SV6MBParams mp;
   mp.swingStrength=InpV6MBSwingStrength;
   mp.lookbackBars=InpV6MBLookbackBars;
   mp.swingLookback=InpV6MBSwingLookback;
   mp.maxBarsToConfirm=InpV6MBMaxBarsToConfirm;
   mp.sweepMinATR=InpV6MBSweepMinATR;
   mp.sweepConfirmBars=3;
   mp.sweepMaxEpisodeBars=8;
   mp.preMacroMinutes=InpV6MBPreMacroMinutes;
   mp.minRangeATR=InpV6MBMinRangeATR;
   mp.dispBodyATR=InpV6MBDispBodyATR;
   mp.fvgMinSizeATR=InpV6MBFVGMinSizeATR;
   mp.minBreakerATR=InpV6MBMinBreakerATR;
   mp.entryLevel=InpV6MBEntryLevel;
   mp.requireUnicorn=InpV6MBRequireUnicorn;
   mp.requireHTFAlign=InpV6MBRequireHTFAlign;
   mp.requireTrueOpen=InpV6RequireTrueOpen;
   mp.minScore=InpV6MBMinScore;
   mp.slBufferATR=InpV6MBSLBufferATR;
   mp.generousMacroMult=InpV6MBGenerousMacroMult;
   mp.tpBufferATR=InpV6TPBufferATR;
   mp.minRR=InpV6MinRR;
   mp.maxTPDistATRD1=InpV6MaxTPDistATRD1;
   mp.maxStopATR=InpV6MBMaxStopATR;
   mp.allowFixedRRFallback=InpV6AllowFixedRRFallback;
   mp.useSDTargets=InpV6UseSDTargets;
   mp.useRefLevelBonus=InpV6UseRefLevelBonus;
   mp.refLevelTolATR=InpV6RefLevelTolATR;
   mp.useDOWScore=InpV6UseDOWScore;
   mp.eqWarnATR=InpV6EqWarnATR;
   mp.fvgRequireBody=InpV6FVGRequireBody;
   mp.allowRetested=InpV6MBAllowRetested;
   g_v6mpStrict=mp;
   g_v6mpRelax=mp;
   g_v6mpRelax.requireHTFAlign=false;
   g_v6mpRelax.requireTrueOpen=false;
   g_v6mpRelax.requireUnicorn=false;
   g_v6mpRelax.fvgRequireBody=false;
   g_v6mpRelax.allowRetested=true;
   g_v6mpRelax.minScore=(int)MathMax(0,InpV6MBMinScore-2);
   g_v6mpRelax.minRR=MathMax(1.5,InpV6MinRR-0.5);
   g_v6mpRelax.dispBodyATR=InpV6MBDispBodyATR*0.6;
   g_v6mpRelax.sweepMinATR=InpV6MBSweepMinATR*0.6;
   g_v6mpRelax.minRangeATR=InpV6MBMinRangeATR*0.6;
   g_v6mb.Init(_Symbol,GetPointer(g_v6clock),GetPointer(g_v6liq),GetPointer(g_v6ref),g_v6mpStrict);
   PrintFormat("Modeles v6.20 : Silver Bullet 1er FVG %s, Macro Breaker %s (%d macros) | passe relachee SB %d min, MB %d min | %d trade(s) par fenetre",
               InpV6EnableSB?"on":"off",InpV6EnableMB?"on":"off",g_v6clock.EnabledCount(),InpV6SBRelaxAfterMin,InpV6MBRelaxAfterMin,InpV6MaxTradesPerWindow);
  }

void V6Deinit(void)
  {
   if(g_v6hLTF!=INVALID_HANDLE) IndicatorRelease(g_v6hLTF);
   if(g_v6hM1!=INVALID_HANDLE)  IndicatorRelease(g_v6hM1);
   if(g_v6hD1!=INVALID_HANDLE)  IndicatorRelease(g_v6hD1);
   g_v6hLTF=INVALID_HANDLE; g_v6hM1=INVALID_HANDLE; g_v6hD1=INVALID_HANDLE;
  }

//--- séries de la v6.20 (LoadFast + LoadFull)
bool V6Load(void)
  {
   g_v6ltfN=CopyRates(_Symbol,InpV6LTF,0,V6_LTF_BARS,g_v6ltf);
   if(g_v6ltfN<60) return(false);
   int na=CopyBuffer(g_v6hLTF,0,0,V6_LTF_BARS,g_v6atrLTF);
   if(na<20 || g_v6atrLTF[1]<=0) return(false);
   if(na<g_v6ltfN) g_v6ltfN=na;
   g_v6htfN=CopyRates(_Symbol,InpV6HTF,0,V6_HTF_BARS,g_v6htf);
   g_v6d1N=CopyRates(_Symbol,PERIOD_D1,0,V6_D1_BARS,g_v6d1);
   int nd=CopyBuffer(g_v6hD1,0,0,3,g_v6atrD1);
   g_v6m1N=CopyRates(_Symbol,InpV6MBTimeframe,0,V6_M1_BARS,g_v6m1);
   int nm=CopyBuffer(g_v6hM1,0,0,V6_M1_BARS,g_v6atrM1);
   if(nm<g_v6m1N) g_v6m1N=nm;
   if(g_v6m1N<0) g_v6m1N=0;
   return(g_v6htfN>50 && g_v6d1N>5 && nd>=2);
  }

bool V6IsConsumed(const string id)
  {
   for(int i=0;i<ArraySize(g_v6consumed);i++) if(g_v6consumed[i]==id) return(true);
   return(false);
  }
void V6Consume(const string id)
  {
   int n=ArraySize(g_v6consumed);
   if(n>=200)
     {
      for(int i=0;i<n-1;i++) g_v6consumed[i]=g_v6consumed[i+1];
      n--;
     }
   ArrayResize(g_v6consumed,n+1);
   g_v6consumed[n]=id;
  }
//--- trades de la fenêtre / macro commencée à « from » (règle « TradesInWindow » de la v6.20)
int V6WindowCount(const datetime from) { return(g_tm_trades.V6CountSince(from)); }

//--- raison de rejet sans les valeurs numériques (« RR 1.52 sous le minimum 2.00 » -> « RR sous le minimum »)
string V6ReasonKey(const string why)
  {
   string k="";
   int n=StringLen(why);
   bool sp=false;
   for(int i=0;i<n;i++)
     {
      ushort c=StringGetCharacter(why,i);
      if((c>='0' && c<='9') || c=='.' || c=='%' || c=='(' || c==')' || c=='>' || c=='<' || c=='=')
        { sp=true; continue; }
      if(c==' ') { sp=true; continue; }
      if(sp && StringLen(k)>0) k+=" ";
      sp=false;
      k+=ShortToString(c);
     }
   return(k);
  }
void V6CountReject(const string prefix,const string why)
  {
   if(why=="") return;
   string key=prefix+V6ReasonKey(why);
   for(int i=0;i<ArraySize(g_v6rejKey);i++) if(g_v6rejKey[i]==key) { g_v6rejCnt[i]++; return; }
   int n=ArraySize(g_v6rejKey);
   if(n>=40) return;
   ArrayResize(g_v6rejKey,n+1);
   ArrayResize(g_v6rejCnt,n+1);
   g_v6rejKey[n]=key;
   g_v6rejCnt[n]=1;
  }

//--- filtres horaires d'ICT NAS appliqués AVANT l'évaluation (comme le blackout news de la v6.20) :
//--- un setup n'est pas consommé par un rejet purement horaire et reste prenable à la sortie du filtre
string V6TimeBlocked(const datetime now)
  {
   datetime nowNY=g_tm.ServerToNY(now);
   int m=CTimeManager::MinuteOfDay(nowNY);
   if(g_anchor>0 && now>=g_tm.NYToServer(g_anchor+ParseHHMM(InpFlatTime)*SEC_MIN)) return("apres l'heure de flat (ICT NAS)");
   if(InpBlockLunch && (InMin(m,5*60,7*60) || InMin(m,12*60,13*60+30))) return("lunch (ICT NAS)");
   if(InpBlockAccumMacro && InMin(m,15*60+15,15*60+45)) return("macro d'accumulation 15:15-15:45 (ICT NAS)");
   if(g_news.InWindow(now)) return("news (ICT NAS)");
   return("");
  }

string V6Model(const SV6Setup &b) { return(b.setupType==SETUP_MACRO_BREAKER ? "MACRO_BREAKER" : "SB_V6"); }

//--- identifiant court et déterministe (commentaire d'ordre <= 31 caractères, pas de doublon après redémarrage)
string V6Uid(const SV6Setup &b)
  {
   string head=(b.setupType==SETUP_MACRO_BREAKER) ? StringFormat("MB%04d",b.macroId) : "SB"+IntegerToString((int)b.window);
   return(head+IntegerToString((long)b.sweep.extremeTime%100000000)+(b.dir==DIR_BUY?"L":"S")+(b.relaxed?"R":""));
  }

//--- setup v6.20 -> signal ICT NAS (mêmes colonnes SQLite que les autres modèles)
bool V6ToSignal(const SV6Setup &b,const string winKey,SSignal &s)
  {
   datetime now=TimeCurrent();
   datetime nowNY=g_tm.ServerToNY(now);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID),ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   int dir=(b.dir==DIR_BUY) ? 1 : -1;
   bool mbk=(b.setupType==SETUP_MACRO_BREAKER);
   s.model=V6Model(b);
   s.dir=dir;
   s.tSrv=now;
   s.tNY=nowNY;
   s.uid=V6Uid(b);
   s.fixedUid=true;
   s.extId=0;
   s.slot=-1;
   s.extKey=winKey;
   s.adaptOk=false;
   FillTimeContext(s,nowNY);
   //--- liquidité prise
   s.liqType=V6LiqTypeToStr((int)b.sweep.type);
   s.liqWeight=(b.sweep.rank>=3) ? 8 : (b.sweep.rank==2 ? 5 : 3);
   s.liqPrice=b.sweep.level;
   s.tSweep=b.sweep.extremeTime;
   s.tSweepNY=g_tm.ServerToNY(s.tSweep);
   //--- structure
   s.mss=1; s.cisd=0; s.disp=1;
   s.dispBodyATR=b.dispBodyATR; s.dispCandles=0; s.dispSize=b.dispBodyATR*b.atr;
   s.atr1=g_atr.Get(PERIOD_M1); s.atr5=g_atr.Get(PERIOD_M5); s.atr15=g_atr.Get(PERIOD_M15);
   s.ifvg=0; s.breaker=mbk?1:0; s.unicorn=b.unicorn?1:0; s.ob=0;
   s.fvgTop=mbk ? b.breaker.zoneTop    : b.fvg.top;
   s.fvgBot=mbk ? b.breaker.zoneBottom : b.fvg.bottom;
   s.fvgCE=(s.fvgTop+s.fvgBot)/2.0;
   s.fvgSize=s.fvgTop-s.fvgBot;
   s.tFVG=mbk ? b.breaker.time : b.fvg.time;
   if(mbk) s.fvgType=b.unicorn ? "UNICORN" : "BREAKER";
   else    s.fvgType=OverlapsFPFVG(s.fvgTop,s.fvgBot) ? "FPFVG" : "CLASSIC";
   //--- plan du moteur v6.20 ; gestion ICT NAS (BE à x R, 50 % au TP1, reste à la cible)
   s.market=b.marketEntry;
   s.entry=b.entry;
   s.sl=b.sl;
   double tp=b.tp;
   if(dir*(s.entry-s.sl)<=0 || dir*(tp-s.entry)<=0) return(false);
   s.inval=0;
   s.riskPts=MathAbs(s.entry-s.sl);
   double r=s.riskPts;
   s.tp1=tp; s.tp2=tp; s.tp3=tp;
   if(g_pTP1R>0 && dir*(tp-(s.entry+dir*g_pTP1R*r))>0) s.tp1=s.entry+dir*g_pTP1R*r;
   s.planRR=b.rr;
   s.bePts=InpBEPts;
   s.beTrigger=(InpBEAtR>0) ? s.entry+dir*InpBEAtR*r : 0;
   s.cancelPx=tp;                       // cible prise avant l'exécution : pas de trade
   s.chaseR=0;
   FillMarketContext(s,now,bid,ask);
   s.ote=b.inOTE?1:0;
   s.smt=-1;
   s.stdvReached=0;
   //--- expiration de la v6.20 : fin de fenêtre / macro + N minutes, jamais après le flat
   int expMin=mbk ? InpV6MBOrderExpiryMinutes : InpV6OrderExpiryMinutes;
   datetime flatSrv=g_tm.NYToServer(g_anchor+ParseHHMM(InpFlatTime)*SEC_MIN);
   datetime expSrv=(datetime)((long)b.windowEnd+(long)expMin*60);
   s.expirySrv=(expSrv<flatSrv) ? expSrv : flatSrv;
   s.flatSrv=flatSrv;
   s.mlProb=-1; s.mlModel=""; s.score=0; s.taken=false;
   s.decision=""; s.reason="";
   return(true);
  }

//--- pipeline de la v6.20 sur la bougie : renvoie le nouveau nombre de signaux
int V6CollectSignals(SSignal &sigs[],int k)
  {
   if(!V6Enabled()) return(k);
   datetime now=TimeCurrent();
   datetime ws=0,we=0;
   ENUM_SB_WINDOW window=InpV6EnableSB ? g_v6clock.WindowAt(now,ws,we) : WIN_NONE;
   int mi=-1;
   if(InpV6EnableMB)
     {
      mi=g_v6clock.MacroIndexAt(now);
      if(mi<0 || !g_v6clock.MacroEnabled(mi))
        {
         int rec=g_v6clock.MacroIndexRecent(now,InpV6MBRetestGraceMinutes);
         mi=(rec>=0 && g_v6clock.MacroEnabled(rec)) ? rec : -1;
        }
     }
   if(window==WIN_NONE && mi<0) { g_v6Status="hors fenetre SB et hors macro"; return(k); }
   string blocked=V6TimeBlocked(now);
   if(blocked!="") { g_v6Status=blocked; return(k); }
   if(!V6Load()) { g_v6Status="donnees insuffisantes"; return(k); }

   double atr=g_v6atrLTF[1];
   double atrD1=g_v6atrD1[1];
   double atrM1=(g_v6m1N>20) ? g_v6atrM1[1] : 0;
   double minStop=MathMax((double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point,_Point);
   double sh,sl;
   ENUM_ICT_DIR bias=CV6Structure::Bias(g_v6htf,g_v6htfN,InpV6SwingStrength,sh,sl);
   g_v6liq.Build(_Symbol,g_v6clock,now,g_v6ltf,g_v6ltfN,g_v6htf,g_v6htfN,g_v6d1,g_v6d1N,atr,
                 InpV6IPDA1,InpV6IPDA2,InpV6IPDA3,InpV6SwingStrength,InpV6EqualHighsTolATR);
   g_v6ref.Build(now,g_v6ltf,g_v6ltfN,g_v6m1,g_v6m1N,g_v6htf,g_v6htfN,g_v6d1,g_v6d1N);
   g_v6ref.PushToMap(g_v6liq,now);
   if(g_v6m1N>60) g_v6liq.AddSwings(g_v6m1,g_v6m1N,3,12,V6L_M1_SWING_HIGH,V6L_M1_SWING_LOW);

   SV6Setup sb,mb;
   V6ResetSetup(sb);
   V6ResetSetup(mb);
   string rejSB="",rejMB="";
   bool haveSB=false,haveMB=false;
   //--- Silver Bullet : passe stricte, puis relâchée si rien n'est passé
   if(window!=WIN_NONE)
     {
      haveSB=g_v6sb.Evaluate(g_v6ltf,g_v6ltfN,g_v6atrLTF,bias,window,ws,we,now,atr,atrD1,minStop,sb,rejSB);
      if(!haveSB && InpV6SBRelaxAfterMin>0 && now>=(datetime)((long)ws+(long)InpV6SBRelaxAfterMin*60))
        {
         g_v6sb.SetParams(g_v6spRelax);
         haveSB=g_v6sb.Evaluate(g_v6ltf,g_v6ltfN,g_v6atrLTF,bias,window,ws,we,now,atr,atrD1,minStop,sb,rejSB);
         g_v6sb.SetParams(g_v6spStrict);
         if(haveSB) { sb.relaxed=true; sb.id+="_RLX"; }
        }
     }
   //--- Macro Breaker : idem
   datetime ms=0,me=0;
   if(mi>=0 && atrM1>0)
     {
      g_v6clock.MacroRangeServer(now,mi,ms,me);
      haveMB=g_v6mb.Evaluate(g_v6m1,g_v6m1N,bias,g_v6clock.MacroId(mi),g_v6clock.MacroHighProb(mi),ms,me,now,
                             atrM1,atr,atrD1,minStop,mb,rejMB);
      if(!haveMB && InpV6MBRelaxAfterMin>0 && now>=(datetime)((long)ms+(long)InpV6MBRelaxAfterMin*60))
        {
         g_v6mb.SetParams(g_v6mpRelax);
         haveMB=g_v6mb.Evaluate(g_v6m1,g_v6m1N,bias,g_v6clock.MacroId(mi),g_v6clock.MacroHighProb(mi),ms,me,now,
                                atrM1,atr,atrD1,minStop,mb,rejMB);
         g_v6mb.SetParams(g_v6mpStrict);
         if(haveMB) { mb.relaxed=true; mb.id+="_RLX"; }
        }
     }
   if(!haveSB) V6CountReject("SB : ",rejSB);
   if(!haveMB) V6CountReject("MB : ",rejMB);
   if(haveSB && V6IsConsumed(sb.id)) haveSB=false;
   if(haveMB && V6IsConsumed(mb.id)) haveMB=false;
   //--- une fenêtre / macro = InpV6MaxTradesPerWindow trade(s)
   string keySB="SB"+IntegerToString((long)ws);
   string keyMB="MB"+IntegerToString((long)ms);
   if(haveSB && InpV6MaxTradesPerWindow>0 && V6WindowCount(ws)>=InpV6MaxTradesPerWindow) { haveSB=false; g_v6nWinCap++; V6Consume(sb.id); rejSB="fenetre deja tradee"; }
   if(haveMB && InpV6MaxTradesPerWindow>0 && V6WindowCount(ms)>=InpV6MaxTradesPerWindow) { haveMB=false; g_v6nWinCap++; V6Consume(mb.id); rejMB="macro deja tradee"; }
   if(!haveSB && !haveMB)
     {
      g_v6Status=(window!=WIN_NONE?V6WindowToStr(window):"")+(mi>=0?" "+g_v6clock.MacroName(mi):"")+
                 " | SB: "+(rejSB==""?"-":rejSB)+" | MB: "+(rejMB==""?"-":rejMB);
      return(k);
     }
   //--- arbitrage de la v6.20 : setup strict prioritaire, puis meilleur score, puis MB Unicorn
   SV6Setup best;
   V6ResetSetup(best);
   if(haveSB && haveMB)
     {
      if(sb.relaxed!=mb.relaxed)                   best=sb.relaxed ? mb : sb;
      else if(mb.score>sb.score)                   best=mb;
      else if(mb.score==sb.score && mb.unicorn)    best=mb;
      else                                         best=sb;
     }
   else best=haveSB ? sb : mb;
   V6Consume(best.id);
   if(best.setupType==SETUP_MACRO_BREAKER) g_v6nMB++; else g_v6nSB++;
   if(best.relaxed) g_v6nRelax++;
   string uid=V6Uid(best);
   if(g_tm_trades.ExistsOnServer(uid)) return(k);                 // déjà envoyé avant un redémarrage
   SSignal sg;
   if(!V6ToSignal(best,(best.setupType==SETUP_MACRO_BREAKER) ? keyMB : keySB,sg)) return(k);
   g_v6Status=V6SetupTypeToStr(best.setupType)+" "+V6DirToStr(best.dir)+" S"+IntegerToString(best.score)+
              (best.relaxed?" RLX":"")+" RR "+DoubleToString(best.rr,1)+" sweep "+V6LiqTypeToStr((int)best.sweep.type);
   ArrayResize(sigs,k+1);
   sigs[k]=sg;
   return(k+1);
  }

//--- après la décision (diagnostic)
void V6AfterDecision(SSignal &s)
  {
   if(s.taken && StringLen(s.extKey)>0) g_v6nTaken++;
  }

//--- panneau et diagnostic
void V6PanelLines(string &L[])
  {
   if(!V6Enabled()) { LoAdd(L,"v6.20 SB / Macro Breaker : OFF"); return; }
   LoAdd(L,"v6.20 SB "+(InpV6EnableSB?"on":"off")+" / MB "+(InpV6EnableMB?"on":"off")+" | setups "+IntegerToString(g_v6nSB+g_v6nMB)+
           " | pris "+IntegerToString(g_v6nTaken));
   if(g_v6Status!="") LoAdd(L,"  "+StringSubstr(g_v6Status,0,110));
  }

void V6DiagLines(string &a[])
  {
   ArrayResize(a,0);
   if(!V6Enabled()) return;
   LoAdd(a,"7. Modeles v6.20 : setups Silver Bullet "+IntegerToString(g_v6nSB)+" | Macro Breaker "+IntegerToString(g_v6nMB)+
           " (dont passe relachee "+IntegerToString(g_v6nRelax)+") | ordres envoyes "+IntegerToString(g_v6nTaken)+
           " | ignores (fenetre / macro deja tradee) "+IntegerToString(g_v6nWinCap));
   //--- raisons les plus fréquentes (bougies M1 évaluées sans setup)
   int n=ArraySize(g_v6rejKey);
   int idx[];
   ArrayResize(idx,n);
   for(int i=0;i<n;i++) idx[i]=i;
   for(int i=1;i<n;i++)
     {
      int v=idx[i],j=i-1;
      while(j>=0 && g_v6rejCnt[idx[j]]<g_v6rejCnt[v]) { idx[j+1]=idx[j]; j--; }
      idx[j+1]=v;
     }
   for(int i=0;i<n && i<8;i++)
      LoAdd(a,"   "+g_v6rejKey[idx[i]]+" : "+IntegerToString(g_v6rejCnt[idx[i]])+" bougie(s)");
  }

#endif
//+------------------------------------------------------------------+
//=== fin V6Bridge.mqh ===



//+------------------------------------------------------------------+
//| Aides                                                            |
//+------------------------------------------------------------------+
//--- 'YYYY-MM-DD HH:MM' (format du schéma)
string NYStamp(datetime ny)
  {
   string s=TimeToString(ny,TIME_DATE|TIME_MINUTES);
   StringReplace(s,".","-");
   return(s);
  }
string NYHM(datetime srv)
  {
   if(srv<=0) return("");
   return(TimeToString(g_tm.ServerToNY(srv),TIME_MINUTES));
  }
string NYFull(datetime srv)
  {
   if(srv<=0) return("");
   return(NYStamp(g_tm.ServerToNY(srv)));
  }
string DateStr(datetime ny)
  {
   string s=TimeToString(ny,TIME_DATE);
   StringReplace(s,".","-");
   return(s);
  }
string DowFr(int d)
  {
   string n[]={"Dim","Lun","Mar","Mer","Jeu","Ven","Sam"};
   return(n[d%7]);
  }
string ProfileOf(datetime anchor)
  {
   int d=CTimeManager::DayOfWeek(anchor);
   if(d<1 || d>5 || ArraySize(g_profile)<d) return("");
   return(g_profile[d-1]);
  }
string Signed(double v,int dig=1) { return((v>=0?"+":"")+DoubleToString(v,dig)); }
string AboveBelow(double px,double ref) { if(ref<=0) return("n/d"); return(px>ref?"au-dessus":(px<ref?"en dessous":"=")); }

//+------------------------------------------------------------------+
//| Nouveau jour de trading                                          |
//+------------------------------------------------------------------+
void StartDay(datetime anchor)
  {
   g_anchor=anchor;
   g_opr.NewDay(anchor);
   g_liq.NewDay(anchor);
   g_gap.NewDay(anchor);
   g_q.NewDay(anchor);
   g_risk.NewDay();
   g_tm_trades.NewDay(g_tm.NYToServer(anchor-6*SEC_HOUR));
   g_draw.NewDay(anchor);
   g_smt.Check();
   g_setup.NewDay();
   g_scorer.LoadJSON(InpWeightsFile);                        // poids recalibrés éventuellement mis à jour
   if(InpMLMode!=ML_OFF) { g_ml.Release(); g_ml.Load(InpMLFolder); }
   g_gapsAbove0930=-1;
   g_gapsBelow0930=-1;
   g_tradesToday=0;
   g_setupsToday=0;
   g_dayOpen=0;
   g_flatDone=false;
   g_limitClosed=false;
   g_targetKept=false;
   g_oprLvl0000=false; g_oprLvl0930=false; g_oprLvl1330=false;
   g_fpAsia.Clear();
   g_fpMid.Clear();
   g_lastM1=0;     // force un traitement immédiat
   g_lastM15=0;
  }

//+------------------------------------------------------------------+
//| Enregistrement du contexte du jour écoulé                        |
//+------------------------------------------------------------------+
void LogDay(bool dayComplete)
  {
   if(!InpCollect || g_anchor==0) return;
   CSqlRow r;
   r.Text("symbol",_Symbol);
   r.Text("trade_date",DateStr(g_anchor));
   r.Int("dow",CTimeManager::DayOfWeek(g_anchor));
   r.Int("month",CTimeManager::Month(g_anchor));
   r.Int("complete",dayComplete?1:0);
   r.Text("weekly_profile",ProfileOf(g_anchor));
   //--- OHLC du jour ICT (18:00 -> 17:00)
   double hi=0,lo=0; datetime th,tl;
   datetime ds=g_tm.NYToServer(g_anchor-6*SEC_HOUR),de=g_tm.NYToServer(g_anchor+17*SEC_HOUR);
   MqlRates o,c;
   bool okO=FirstBarAtOrAfter(_Symbol,ds,3*SEC_HOUR,o);
   bool okC=LastBarBefore(_Symbol,de,6*SEC_HOUR,c);
   M1Extremes(_Symbol,ds,de,hi,lo,th,tl);
   r.Price("day_open",okO?o.open:0);
   r.Price("day_high",hi);
   r.Price("day_low",lo);
   r.Price("day_close",okC?c.close:0);
   //--- sessions
   r.Price("asia_h",g_liq.asia.high);   r.Price("asia_l",g_liq.asia.low);
   r.Text("asia_h_swept_ny",NYFull(g_liq.SweepTime(LIQ_ASIA,true)));
   r.Text("asia_l_swept_ny",NYFull(g_liq.SweepTime(LIQ_ASIA,false)));
   r.Price("london_h",g_liq.london.high); r.Price("london_l",g_liq.london.low);
   r.Text("london_h_swept_ny",NYFull(g_liq.SweepTime(LIQ_LONDON,true)));
   r.Text("london_l_swept_ny",NYFull(g_liq.SweepTime(LIQ_LONDON,false)));
   r.Price("nyam_h",g_liq.nyam.high);   r.Price("nyam_l",g_liq.nyam.low);
   //--- MOR / OPR
   r.Price("mor_h",g_opr.mor.high);     r.Price("mor_l",g_opr.mor.low);
   r.Int("mor_bias_0250",g_opr.morBias);
   r.Real("mor_ext_up",g_opr.mor.ExtUp(),3); r.Real("mor_ext_dn",g_opr.mor.ExtDn(),3);
   r.Text("mor_up2_ny",NYFull(g_opr.mor.tUp2)); r.Text("mor_dn2_ny",NYFull(g_opr.mor.tDn2));
   r.Price("opr0130_h",g_opr.opr0130.high); r.Price("opr0130_l",g_opr.opr0130.low);
   r.Real("opr0130_ext_up",g_opr.opr0130.ExtUp(),3); r.Real("opr0130_ext_dn",g_opr.opr0130.ExtDn(),3);
   r.Price("opr0700_h",g_opr.opr0700.high); r.Price("opr0700_l",g_opr.opr0700.low);
   r.Real("opr0700_ext_up",g_opr.opr0700.ExtUp(),3); r.Real("opr0700_ext_dn",g_opr.opr0700.ExtDn(),3);
   r.Price("opr0930_h",g_opr.opr0930.high); r.Price("opr0930_l",g_opr.opr0930.low);
   r.Int("opr0930_break",g_opr.opr0930.breakSide);
   r.Text("opr0930_break_ny",NYFull(g_opr.opr0930.tBreak));
   r.Int("opr0930_returned",g_opr.opr0930.returnedInside?1:0);
   r.Real("opr0930_ext_up",g_opr.opr0930.ExtUp(),3); r.Real("opr0930_ext_dn",g_opr.opr0930.ExtDn(),3);
   r.Text("opr0930_up2_ny",NYFull(g_opr.opr0930.tUp2)); r.Text("opr0930_dn2_ny",NYFull(g_opr.opr0930.tDn2));
   r.Int("trend_day",g_opr.IsTrendDay()?1:0);
   r.Price("opr1330_h",g_opr.opr1330.high); r.Price("opr1330_l",g_opr.opr1330.low);
   r.Real("opr1330_ext_up",g_opr.opr1330.ExtUp(),3); r.Real("opr1330_ext_dn",g_opr.opr1330.ExtDn(),3);
   //--- Shadow
   r.Price("shadow_h",g_opr.shadow.high); r.Price("shadow_l",g_opr.shadow.low);
   r.Int("shadow_first",g_opr.shadowFirstSide);
   r.Text("shadow_first_ny",NYFull(g_opr.shadowFirstTime));
   r.Int("shadow_opp",g_opr.shadowOppHit?1:0);
   r.Text("shadow_opp_ny",NYFull(g_opr.shadowOppTime));
   //--- HTF
   r.Price("pdh",g_liq.pdh); r.Price("pdl",g_liq.pdl);
   r.Text("pdh_swept_ny",NYFull(g_liq.SweepTime(LIQ_PREV_DAY,true)));
   r.Text("pdl_swept_ny",NYFull(g_liq.SweepTime(LIQ_PREV_DAY,false)));
   r.Price("pwh",g_liq.pwh); r.Price("pwl",g_liq.pwl);
   r.Price("pmh",g_liq.pmh); r.Price("pml",g_liq.pml);
   r.Price("ipda20_h",g_liq.ipdaH[0]); r.Price("ipda20_l",g_liq.ipdaL[0]);
   r.Price("ipda40_h",g_liq.ipdaH[1]); r.Price("ipda40_l",g_liq.ipdaL[1]);
   r.Price("ipda60_h",g_liq.ipdaH[2]); r.Price("ipda60_l",g_liq.ipdaL[2]);
   //--- ouvertures
   r.Price("midnight_open",g_opr.midnightOpen);
   r.Price("open_0830",g_opr.open0830);
   r.Price("open_0930",g_opr.open0930);
   r.Price("week_open",g_gap.weekOpen);
   r.Price("month_open",g_liq.monthOpen);
   //--- gaps
   bool hasN=(ArraySize(g_gap.ndog)>0 && g_gap.ndog[0].valid);
   bool hasW=(ArraySize(g_gap.nwog)>0 && g_gap.nwog[0].valid);
   if(hasN) { r.Real("ndog_size",g_gap.ndog[0].Size(),2); r.Price("ndog_ce",g_gap.ndog[0].CE()); }
   else     { r.Text("ndog_size",""); r.Text("ndog_ce",""); }
   if(hasW) { r.Real("nwog_size",g_gap.nwog[0].Size(),2); r.Price("nwog_ce",g_gap.nwog[0].CE()); }
   else     { r.Text("nwog_size",""); r.Text("nwog_ce",""); }
   if(g_gapsAbove0930>=0) { r.Int("gaps_above_0930",g_gapsAbove0930); r.Int("gaps_below_0930",g_gapsBelow0930); }
   else { r.Text("gaps_above_0930",""); r.Text("gaps_below_0930",""); }
   if(g_gap.rth.valid) { r.Real("rth_gap",g_gap.rth.Size(),2); r.Int("rth_big",g_gap.RthIsBig()?1:0); }
   else { r.Text("rth_gap",""); r.Text("rth_big",""); }
   r.Text("rth_ce_ny",NYFull(g_gap.tRthCE));
   r.Text("rth_fill_ny",NYFull(g_gap.tRthFill));
   r.Text("ea_version",ICTNAS_VERSION);
   g_db.Write("day_context",r,true);
  }

//+------------------------------------------------------------------+
//| Tracés                                                           |
//+------------------------------------------------------------------+
void DrawRange(SRange &r,const string id,color c,bool stdv,int stdvEndMinNY)
  {
   if(!r.valid) return;
   g_draw.Box(id,r.startSrv,r.endSrv,r.high,r.low,c,true,
              r.name+" "+PxStr(r.high)+" / "+PxStr(r.low)+(r.complete?"":" (en cours)"));
   if(!stdv || !r.complete || r.Size()<=0) return;
   datetime t2=g_tm.NYToServer(g_anchor+stdvEndMinNY*SEC_MIN);
   for(int i=0;i<g_opr.LevelsCount();i++)
     {
      double k=g_opr.Level(i);
      bool key=g_opr.IsKey(k);
      color cc=key?InpClrKeySTDV:InpClrSTDV;
      ENUM_LINE_STYLE st=key?STYLE_SOLID:STYLE_DOT;
      string ks=DoubleToString(k,(MathAbs(k-MathRound(k))<1e-9)?0:1);
      g_draw.Seg(id+"_u"+ks,r.endSrv,t2,r.Up(k),cc,st,key?2:1,key?r.name+" +"+ks:"",r.name+" +"+ks+" STDV");
      g_draw.Seg(id+"_d"+ks,r.endSrv,t2,r.Dn(k),cc,st,key?2:1,key?r.name+" -"+ks:"",r.name+" -"+ks+" STDV");
     }
  }

void DrawSession(SRange &r,const string id)
  {
   if(!r.valid) return;
   g_draw.Box(id,r.startSrv,r.endSrv,r.high,r.low,InpClrSession,false,r.name);
  }

void DrawAll(void)
  {
   if(!g_draw.On()) return;
   datetime dayStart=g_tm.NYToServer(g_anchor-6*SEC_HOUR);
   datetime dayEnd=g_tm.NYToServer(g_anchor+17*SEC_HOUR);
   //--- sessions
   DrawSession(g_liq.asia,"asia");
   DrawSession(g_liq.london,"lon");
   DrawSession(g_liq.nyam,"nyam");
   DrawSession(g_liq.lunch,"lunch");
   //--- MOR / OPR / Shadow
   DrawRange(g_opr.mor,    "mor", InpClrMOR,InpSTDV_MOR, 12*60);
   DrawRange(g_opr.opr0130,"o130",InpClrOPR,InpSTDV_0130,12*60);
   DrawRange(g_opr.opr0700,"o700",InpClrOPR,InpSTDV_0700,16*60);
   DrawRange(g_opr.opr0930,"o930",InpClrOPR,InpSTDV_0930,16*60);
   DrawRange(g_opr.opr1330,"o1330",InpClrOPR,InpSTDV_1330,16*60);
   if(g_opr.shadow.complete)
     {
      g_draw.Seg("rbsl",g_opr.shadow.endSrv,dayEnd,g_opr.shadow.high,InpClrBSL,STYLE_DASHDOT,1,"Reset BSL");
      g_draw.Seg("rssl",g_opr.shadow.endSrv,dayEnd,g_opr.shadow.low, InpClrSSL,STYLE_DASHDOT,1,"Reset SSL");
     }
   //--- liquidité
   for(int i=0;i<ArraySize(g_liq.lv);i++)
     {
      SLiqLevel l=g_liq.lv[i];
      if(l.type==LIQ_SWING_M15 && !InpDrawSwings) continue;
      datetime t1=(l.tFormed>dayStart)?l.tFormed:dayStart;
      datetime t2=l.swept?l.tSwept:dayEnd;
      if(t2<=t1) t2=t1+SEC_MIN;
      color c=l.buySide?InpClrBSL:InpClrSSL;
      string txt=l.name+(l.swept?" x "+NYHM(l.tSwept):"");
      g_draw.Seg("lq"+IntegerToString(l.id),t1,t2,l.price,c,l.swept?STYLE_DOT:STYLE_SOLID,
                 (l.weight>=7)?2:1,(l.type==LIQ_SWING_M15)?"":txt,
                 txt+" | poids "+IntegerToString(l.weight));
     }
   //--- quadrants du jour précédent
   if(g_liq.pdh>g_liq.pdl)
     {
      double q[5]={0,25,50,75,100};
      for(int i=1;i<4;i++)
        {
         double p=g_liq.pdl+(g_liq.pdh-g_liq.pdl)*q[i]/100.0;
         g_draw.Seg("pdq"+IntegerToString((int)q[i]),dayStart,dayEnd,p,clrDimGray,STYLE_DOT,1,
                    (i==2)?"PD 50% EQ":"PD "+IntegerToString((int)q[i])+"%");
        }
     }
   //--- gaps
   for(int i=0;i<ArraySize(g_gap.ndog);i++)
     {
      if(!g_gap.ndog[i].valid) continue;
      string id="ndog"+IntegerToString(i);
      if(i==0) g_draw.Box(id,g_gap.ndog[i].tOpen,dayEnd,g_gap.ndog[i].Hi(),g_gap.ndog[i].Lo(),InpClrGap,true,"NDOG");
      g_draw.Seg(id+"ce",(i==0)?g_gap.ndog[i].tOpen:dayStart,dayEnd,g_gap.ndog[i].CE(),clrKhaki,STYLE_DOT,1,
                 "NDOG"+IntegerToString(i+1)+" CE");
     }
   for(int i=0;i<ArraySize(g_gap.nwog);i++)
     {
      if(!g_gap.nwog[i].valid) continue;
      string id="nwog"+IntegerToString(i);
      datetime t1=(g_gap.nwog[i].tOpen>dayStart)?g_gap.nwog[i].tOpen:dayStart;
      if(i==0) g_draw.Box(id,t1,dayEnd,g_gap.nwog[i].Hi(),g_gap.nwog[i].Lo(),InpClrGap,true,"NWOG");
      g_draw.Seg(id+"ce",t1,dayEnd,g_gap.nwog[i].CE(),clrGoldenrod,STYLE_DASH,1,"NWOG"+IntegerToString(i+1)+" CE");
     }
   if(g_gap.rth.valid)
     {
      g_draw.Box("rth",g_gap.rth.tOpen,dayEnd,g_gap.rth.Hi(),g_gap.rth.Lo(),C'60,40,70',true,
                 "RTH gap "+Signed(g_gap.rth.Size()));
      g_draw.Seg("rthce",g_gap.rth.tOpen,dayEnd,g_gap.rth.CE(),clrPlum,STYLE_DOT,1,"RTH CE");
     }
   //--- True Opens
   if(g_q.dayTO>0)  g_draw.Seg("to_day",g_tm.NYToServer(g_anchor),dayEnd,g_q.dayTO,InpClrTO,STYLE_DASH,1,"Midnight Open");
   if(g_opr.open0830>0) g_draw.Seg("o0830",g_tm.NYToServer(g_anchor+8*SEC_HOUR+30*SEC_MIN),dayEnd,g_opr.open0830,InpClrTO,STYLE_DOT,1,"08:30 Open");
   if(g_q.weekTO>0) g_draw.Seg("to_wk",g_tm.NYToServer(g_q.weekTO_NY),dayEnd,g_q.weekTO,clrWhiteSmoke,STYLE_DASH,1,"True Week Open");
   if(g_q.sessTO>0) g_draw.Seg("to_s"+IntegerToString(g_q.dayQ),g_tm.NYToServer(g_q.sessTO_NY),
                               g_tm.NYToServer(g_q.sessStartNY+6*SEC_HOUR),g_q.sessTO,InpClrTO,STYLE_DOT,1,"TO session");
   if(g_q.cycTO>0)  g_draw.Seg("to_c"+TimeToString(g_q.cycStartNY,TIME_MINUTES),g_tm.NYToServer(g_q.cycTO_NY),
                               g_tm.NYToServer(g_q.cycStartNY+5400),g_q.cycTO,C'120,120,120',STYLE_DOT,1,"");
   //--- fenêtres Silver Bullet
   int sbH[3]={3,10,14};
   for(int i=0;i<3;i++)
     {
      if(InpSBMode==SB_NY_AM_ONLY && sbH[i]!=10) continue;
      g_draw.VLine("sb"+IntegerToString(sbH[i])+"a",g_tm.NYToServer(g_anchor+sbH[i]*SEC_HOUR),clrSlateGray,"Silver Bullet debut");
      g_draw.VLine("sb"+IntegerToString(sbH[i])+"b",g_tm.NYToServer(g_anchor+(sbH[i]+1)*SEC_HOUR),clrSlateGray,"Silver Bullet fin");
     }
   //--- FPFVG
   if(g_fpAsia.valid) g_draw.Box("fpa",g_fpAsia.t1,dayEnd,g_fpAsia.top,g_fpAsia.bottom,C'35,60,80',true,"FPFVG Asie");
   if(g_fpMid.valid)  g_draw.Box("fpm",g_fpMid.t1,dayEnd,g_fpMid.top,g_fpMid.bottom,C'60,45,80',true,"FPFVG Midnight");
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Panneau                                                          |
//+------------------------------------------------------------------+
string RangeLine(SRange &r)
  {
   if(!r.valid) return(r.name+" : en attente");
   string s=r.name+" "+PxStr(r.high)+"/"+PxStr(r.low)+" R="+DoubleToString(r.Size(),1);
   if(!r.complete) return(s+" (en cours)");
   return(s+" ext "+Signed(r.ExtUp(),2)+"/-"+DoubleToString(r.ExtDn(),2));
  }

void AddLine(string &a[],const string s) { int n=ArraySize(a); ArrayResize(a,n+1); a[n]=s; }

void UpdatePanel(datetime nowNY,double bid)
  {
   string L[];
   AddLine(L,"ICT NAS Institutional "+ICTNAS_VERSION+" - "+(InpTradingEnabled?"TRADING ACTIF":"OBSERVATION (aucun ordre)"));
   AddLine(L,"NY "+NYStamp(nowNY)+" "+DowFr(CTimeManager::DayOfWeek(g_anchor))+" | Profil: "+ProfileOf(g_anchor));
   AddLine(L,g_tzMsg);
   string macro=CTimeManager::MacroLabel(nowNY);
   string sb=CTimeManager::SilverBulletLabel(nowNY,InpSBMode);
   AddLine(L,"Session: "+CTimeManager::SessionLabel(nowNY)+" | Macro: "+(macro==""?"-":macro)+
             " | "+(sb==""?"SB: -":sb+" ACTIF"));
   AddLine(L,"Quarter jour: Q"+IntegerToString(g_q.dayQ)+" "+CQuarterlyEngine::DayQName(g_q.dayQ)+" ("+
             CQuarterlyEngine::AMDX(g_q.dayQ)+") | 90m: Q"+IntegerToString(g_q.q90)+" ("+CQuarterlyEngine::AMDX(g_q.q90)+
             ") | 22m: Q"+IntegerToString(g_q.q22));
   AddLine(L,"Midnight Open "+PxStr(g_q.dayTO)+" ("+AboveBelow(bid,g_q.dayTO)+") | TO sess "+PxStr(g_q.sessTO)+
             " ("+AboveBelow(bid,g_q.sessTO)+")");
   AddLine(L,"TO 90m "+TimeToString(g_q.cycTO_NY,TIME_MINUTES)+" "+PxStr(g_q.cycTO)+" | Week TO "+PxStr(g_q.weekTO)+
             " | 08:30 "+PxStr(g_opr.open0830));
   AddLine(L,RangeLine(g_opr.mor)+(g_opr.morBiasSet?" | 02:50 "+COPREngine::BiasStr(g_opr.morBias):""));
   AddLine(L,RangeLine(g_opr.opr0130));
   AddLine(L,RangeLine(g_opr.opr0700));
   string o930=RangeLine(g_opr.opr0930);
   if(g_opr.opr0930.breakSide!=0)
      o930+=" | cassure "+(g_opr.opr0930.breakSide>0?"haut ":"bas ")+NYHM(g_opr.opr0930.tBreak)+
            (g_opr.opr0930.returnedInside?" retour "+NYHM(g_opr.opr0930.tReturn):" sans retour")+
            (g_opr.IsTrendDay()?" => JOUR DE TENDANCE":"");
   AddLine(L,o930);
   AddLine(L,RangeLine(g_opr.opr1330));
   string sh=RangeLine(g_opr.shadow);
   if(g_opr.shadowFirstSide!=0)
      sh+=" | 1re: "+(g_opr.shadowFirstSide==1?"BSL":(g_opr.shadowFirstSide==-1?"SSL":"les deux"))+" "+
          NYHM(g_opr.shadowFirstTime)+" | opposee: "+(g_opr.shadowOppHit?NYHM(g_opr.shadowOppTime):"non");
   AddLine(L,sh);
   AddLine(L,"Asie "+PxStr(g_liq.asia.high)+"/"+PxStr(g_liq.asia.low)+" | Londres "+PxStr(g_liq.london.high)+"/"+PxStr(g_liq.london.low));
   double pd=g_liq.PDPercent(bid);
   AddLine(L,"PDH/PDL "+PxStr(g_liq.pdh)+"/"+PxStr(g_liq.pdl)+" | prix a "+(pd<0?"n/d":DoubleToString(pd,0)+"%")+
             (pd>=50?" PREMIUM":(pd>=0?" DISCOUNT":"")));
   AddLine(L,"PWH/PWL "+PxStr(g_liq.pwh)+"/"+PxStr(g_liq.pwl)+" | PMH/PML "+PxStr(g_liq.pmh)+"/"+PxStr(g_liq.pml));
   AddLine(L,"IPDA20 "+PxStr(g_liq.ipdaH[0])+"/"+PxStr(g_liq.ipdaL[0])+" | IPDA60 "+PxStr(g_liq.ipdaH[2])+"/"+PxStr(g_liq.ipdaL[2]));
   int ga,gb;
   g_gap.Cluster(bid,ga,gb);
   AddLine(L,"Gaps (NDOG+NWOG CE): "+IntegerToString(ga)+" au-dessus / "+IntegerToString(gb)+" en dessous -> draw "+
             (ga>gb?"HAUT":(gb>ga?"BAS":"neutre")));
   if(g_gap.rth.valid)
      AddLine(L,"RTH gap "+Signed(g_gap.rth.Size())+(g_gap.RthIsBig()?" (GROS)":"")+" CE "+PxStr(g_gap.rth.CE())+
                " touchee "+(g_gap.tRthCE>0?NYHM(g_gap.tRthCE):"non")+" | comble "+(g_gap.tRthFill>0?NYHM(g_gap.tRthFill):"non"));
   else AddLine(L,"RTH gap : en attente de 09:30");
   int nb=g_liq.NearestIntact(true,bid),ns=g_liq.NearestIntact(false,bid);
   AddLine(L,"Liquidite intacte: "+IntegerToString(g_liq.CountIntact(true))+" BSL / "+IntegerToString(g_liq.CountIntact(false))+" SSL");
   AddLine(L,"BSL proche: "+(nb>=0?g_liq.lv[nb].name+" "+PxStr(g_liq.lv[nb].price)+" (+"+DoubleToString(g_liq.lv[nb].price-bid,1)+")":"-")+
             " | SSL proche: "+(ns>=0?g_liq.lv[ns].name+" "+PxStr(g_liq.lv[ns].price)+" (-"+DoubleToString(bid-g_liq.lv[ns].price,1)+")":"-"));
   int ls=g_liq.LastSwept();
   AddLine(L,"Derniere liquidite prise: "+(ls>=0?g_liq.lv[ls].name+" a "+NYHM(g_liq.lv[ls].tSwept):"aucune aujourd'hui"));
   AddLine(L,g_smt.Status());
   double lots=g_risk.CalcLots(true,bid,bid-InpTestSLPts);
   string why;
   bool can=g_risk.CanTrade(why);
   AddLine(L,"Risque "+DoubleToString(g_risk.RiskPct(),2)+"% -> lot pour SL "+DoubleToString(InpTestSLPts,0)+" pts = "+
             (lots>0?DoubleToString(lots,2):"sous le lot min")+" | Jour "+Signed(g_risk.DayPnLPct(),2)+"%");
   AddLine(L,"Trading: "+(can?"autorise":"BLOQUE ("+why+")")+" | DB: "+(g_db.IsOpen()?"SQLite OK":"inactive"));
   AddLine(L,"Chasses actives: "+IntegerToString(g_setup.ActiveHunts())+" | Setups jour: "+IntegerToString(g_setupsToday)+
             " | Trades executes: "+IntegerToString(g_tm_trades.FilledToday())+"/"+IntegerToString(InpMaxTradesDay)+
             " | en attente: "+IntegerToString(g_tm_trades.PendingCount()));
   AddLine(L,"Signaux suivis: "+IntegerToString(g_log.Tracking())+" | enregistres: "+IntegerToString(g_log.Written())+
             " | Score min "+DoubleToString(g_pScoreMin,0)+" (poids "+g_scorer.Source()+")");
   AddLine(L,(InpMLMode==ML_OFF)?"ML : desactive":g_ml.Status()+(InpMLMode==ML_OBSERVE?" [observation]":" [filtre]"));
   AddLine(L,g_news.Status());
   if(g_fpAsia.valid) AddLine(L,"FPFVG Asie "+(g_fpAsia.dir==1?"haussier ":"baissier ")+PxStr(g_fpAsia.bottom)+"-"+PxStr(g_fpAsia.top));
   if(g_fpMid.valid)  AddLine(L,"FPFVG Midnight "+(g_fpMid.dir==1?"haussier ":"baissier ")+PxStr(g_fpMid.bottom)+"-"+PxStr(g_fpMid.top));
   LoPanelLines(L);
   V6PanelLines(L);
   for(int i=ArraySize(g_recent)-1;i>=0;i--) AddLine(L,"> "+g_recent[i]);
   if(g_tm_trades.LastMessage()!="") AddLine(L,"Dernier ordre: "+g_tm_trades.LastMessage());
   g_panel.Show(L);
  }

//+------------------------------------------------------------------+
//| FPFVG : Asie (M15, 1er FVG de la session 18:00-00:00) et         |
//| Midnight (M1, 1er FVG créé par un displacement après 00:00)      |
//+------------------------------------------------------------------+
bool FirstFVG(ENUM_TIMEFRAMES tf,datetime fromSrv,datetime toSrv,bool needDisp,SFVG &out)
  {
   MqlRates r[];
   int n=GetBars(_Symbol,tf,fromSrv,toSrv,r);
   double atr=g_atr.Get(tf);
   int ps=PeriodSeconds(tf);
   for(int i=2;i<n;i++)
     {
      if(r[i].time+ps>TimeCurrent()) break;                 // bougie 3 pas encore clôturée
      double body=MathAbs(r[i-1].close-r[i-1].open);
      if(needDisp && (atr<=0 || body<g_pDispMult*atr)) continue;
      if(r[i].low-r[i-2].high>=g_pMinFVG)
        {
         out.valid=true; out.dir=1; out.bottom=r[i-2].high; out.top=r[i].low; out.t1=r[i-2].time; out.t3=r[i].time;
         return(true);
        }
      if(r[i-2].low-r[i].high>=g_pMinFVG)
        {
         out.valid=true; out.dir=-1; out.top=r[i-2].low; out.bottom=r[i].high; out.t1=r[i-2].time; out.t3=r[i].time;
         return(true);
        }
     }
   return(false);
  }

void AddOPRLevels(SRange &r,const string tag,bool &done)
  {
   if(done || !r.complete) return;
   g_liq.AddExternal(tag+" H",LIQ_OPR,true, r.high,r.tHigh,r.endSrv);
   g_liq.AddExternal(tag+" L",LIQ_OPR,false,r.low, r.tLow, r.endSrv);
   done=true;
  }

void UpdateFPFVG(datetime nowSrv)
  {
   datetime mid=g_tm.NYToServer(g_anchor);
   if(!g_fpAsia.valid && nowSrv>=mid)
      FirstFVG(PERIOD_M15,g_tm.NYToServer(g_anchor-6*SEC_HOUR),mid-1,false,g_fpAsia);
   datetime t0250=g_tm.NYToServer(g_anchor+2*SEC_HOUR+50*SEC_MIN);
   if(!g_fpMid.valid && nowSrv>mid && nowSrv<t0250+SEC_HOUR)
      FirstFVG(PERIOD_M1,mid,nowSrv,true,g_fpMid);
  }

//+------------------------------------------------------------------+
//| Setups -> signaux -> décisions                                   |
//+------------------------------------------------------------------+
void PushRecent(const string s)
  {
   int n=ArraySize(g_recent);
   if(n>=5)
     {
      for(int i=0;i<n-1;i++) g_recent[i]=g_recent[i+1];
      g_recent[n-1]=s;
      return;
     }
   ArrayResize(g_recent,n+1);
   g_recent[n]=s;
  }

void DrawSignal(SSignal &s)
  {
   if(!g_draw.On()) return;
   color c=s.taken?(s.dir==1?clrLime:clrRed):clrGray;
   string id="sg"+s.uid;
   datetime t2=s.expirySrv+2*SEC_HOUR;
   g_draw.Box(id+"f",(s.tFVG>0)?s.tFVG:s.tSrv,s.expirySrv,s.fvgTop,s.fvgBot,s.taken?C'30,70,40':C'55,55,55',true,"");
   g_draw.Seg(id+"e",s.tSrv,t2,s.entry,c,STYLE_SOLID,s.taken?2:1,
              s.model+(s.dir==1?" L ":" S ")+DoubleToString(s.score,0)+" "+s.decision,s.reason);
   g_draw.Seg(id+"s",s.tSrv,t2,s.sl,clrRed,STYLE_DOT,1,"","SL "+PxStr(s.sl));
   if(s.tp1>0) g_draw.Seg(id+"t1",s.tSrv,t2,s.tp1,clrLime,STYLE_DOT,1,"","TP1 "+PxStr(s.tp1));
   if(s.tp2>0 && MathAbs(s.tp2-s.tp1)>_Point) g_draw.Seg(id+"t2",s.tSrv,t2,s.tp2,clrLime,STYLE_DOT,1,"","TP2 / DOL "+PxStr(s.tp2));
   if(s.tp3>0 && MathAbs(s.tp3-s.tp2)>_Point) g_draw.Seg(id+"t3",s.tSrv,t2,s.tp3,clrLime,STYLE_DOT,1,"","TP3 "+PxStr(s.tp3));
  }

//+------------------------------------------------------------------+
//| Profil d'entrée -> paramètres effectifs                          |
//| v2.30 : RR minimal 2 (règle validée « RR min 2 ») pour les       |
//| modèles ICT ; CRT : InpCRTMinRR ; London PDF : InpLondonMinRR.    |
//+------------------------------------------------------------------+
void ApplyProfile(void)
  {
   switch(InpProfile)
     {
      case PROFILE_STRICT:
         g_pScoreMin=60; g_pMinRR=2.0; g_pFallbackRR=0; g_pMaxRR=0; g_pSLFloorATR=0; g_pSLCapATR=0; g_pTP1R=2.0;
         g_pMinFVG=5; g_pDispMult=1.5; g_pHuntBars=30; g_pRequireDisp=true; g_pMarket=false;
         g_pMomentum=false; g_pKillzone=false;
         break;
      case PROFILE_STANDARD:
         g_pScoreMin=25; g_pMinRR=2.0; g_pFallbackRR=3.0; g_pMaxRR=5.0; g_pSLFloorATR=0.8; g_pSLCapATR=2.5; g_pTP1R=2.0;
         g_pMinFVG=3; g_pDispMult=1.2; g_pHuntBars=45; g_pRequireDisp=true; g_pMarket=false;
         g_pMomentum=InpUseMomentum; g_pKillzone=InpUseKillzoneModel;
         break;
      case PROFILE_AGGRESSIVE:
         g_pScoreMin=0; g_pMinRR=2.0; g_pFallbackRR=3.0; g_pMaxRR=4.0; g_pSLFloorATR=0.8; g_pSLCapATR=2.5; g_pTP1R=2.0;
         g_pMinFVG=2; g_pDispMult=1.0; g_pHuntBars=60; g_pRequireDisp=false; g_pMarket=true;
         g_pMomentum=InpUseMomentum; g_pKillzone=InpUseKillzoneModel;
         break;
      default:
         g_pScoreMin=InpScoreMin; g_pMinRR=InpMinRR; g_pFallbackRR=InpFallbackRR; g_pMaxRR=InpMaxRR;
         g_pSLFloorATR=InpSLFloorATR; g_pSLCapATR=InpSLCapATR; g_pTP1R=InpTP1R;
         g_pMinFVG=InpMinFVGPts; g_pDispMult=InpDispATRMult; g_pHuntBars=InpHuntMaxBars;
         g_pRequireDisp=InpRequireDisp; g_pMarket=InpMarketEntry;
         g_pMomentum=InpUseMomentum; g_pKillzone=InpUseKillzoneModel;
     }
   PrintFormat("Profil %s : score>=%.0f RR>=%.1f (CRT %.1f, London PDF %.1f) cible secours %.1fR SL %.1f-%.1f ATR M5 allegement 50%% a %.1fR FVG>=%.1f disp %.1f ATR %s | momentum %s | killzone %s",
               EnumToString(InpProfile),g_pScoreMin,g_pMinRR,InpCRTMinRR,InpLondonMinRR,g_pFallbackRR,g_pSLFloorATR,g_pSLCapATR,g_pTP1R,
               g_pMinFVG,g_pDispMult,g_pMarket?"MARCHE":"LIMITE CE",g_pMomentum?"on":"off",g_pKillzone?"on":"off");
  }

//+------------------------------------------------------------------+
//| SB Momentum (repris de l'EA v6) : sens = position vs PDH/PDL,     |
//| displacement M5 >= x ATR sur 5 bougies, retracement <= 61,8 %,   |
//| FVG M5 dans le même sens -> entrée au marché, en killzone NY.    |
//+------------------------------------------------------------------+
void ScanMomentum(void)
  {
   if(!g_pMomentum) return;
   datetime now=TimeCurrent();
   int m=CTimeManager::MinuteOfDay(g_tm.ServerToNY(now));
   if(!(InMin(m,120,300) || InMin(m,420,660) || InMin(m,810,960))) return;
   if(now-g_lastMomentum<15*SEC_MIN) return;
   double atr=g_atr.Get(PERIOD_M5);
   if(atr<=0 || g_liq.pdh<=0 || g_liq.pdl<=0) return;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   int dir;
   if(bid>g_liq.pdh) dir=1;
   else if(bid<g_liq.pdl) dir=-1;
   else dir=(bid>(g_liq.pdh+g_liq.pdl)/2.0)?1:-1;
   MqlRates r[];
   ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,PERIOD_M5,0,12,r)<12) return;
   double disp=(dir==1)?r[1].high-r[6].low:r[6].high-r[1].low;
   if(disp<InpMomentumDispATR*atr) return;
   double sh=r[1].high,sl=r[1].low;
   for(int i=1;i<=4;i++) { sh=MathMax(sh,r[i].high); sl=MathMin(sl,r[i].low); }
   double amp=sh-sl;
   if(amp<=0) return;
   double ret=(dir==1)?(sh-bid)/amp:(bid-sl)/amp;
   if(ret>0.618) return;
   double top=0,bot=0;
   datetime t1=0;
   bool found=false;
   for(int i=1;i<=6 && !found;i++)
     {
      if(dir==1 && r[i].low-r[i+2].high>=g_pMinFVG)  { top=r[i].low;   bot=r[i+2].high; t1=r[i+2].time; found=true; }
      if(dir==-1 && r[i+2].low-r[i].high>=g_pMinFVG) { top=r[i+2].low; bot=r[i].high;   t1=r[i+2].time; found=true; }
     }
   if(!found) return;
   SSetup c;
   c.valid=true; c.dir=dir; c.tf=PERIOD_M5; c.erl=false; c.momentum=true;
   c.liqName="MOMENTUM"; c.liqType=-1; c.liqWeight=0; c.liqPrice=0; c.tLevel=0; c.tSweep=now;
   c.extreme=(dir==1)?MathMin(bot,sl)-0.25*atr:MathMax(top,sh)+0.25*atr;
   c.tExtreme=r[1].time; c.tTrigger=r[1].time;
   c.mss=false; c.cisd=false; c.displacement=true;
   c.dispBodyATR=disp/atr; c.dispCandles=5; c.dispSize=disp;
   c.ifvg=false; c.breaker=false; c.unicorn=false; c.orderBlock=false;
   c.fvgTop=top; c.fvgBottom=bot; c.fvgT1=t1; c.fvgC1Ext=0;
   c.legEnd=(dir==1)?sh:sl;
   c.smt=-1;
   g_setup.Inject(c);
   g_lastMomentum=now;
  }

//+------------------------------------------------------------------+
//| v2.22 : l'EA a-t-il le droit de trader ? (cause n°1 de "aucune   |
//| entrée" en live : bouton Algo Trading / option de l'EA)          |
//+------------------------------------------------------------------+
string g_tradeReady="";
bool TradeReadiness(void)
  {
   string why="";
   if(!MQLInfoInteger(MQL_TESTER) && !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      why+="Bouton 'Algo Trading' desactive dans le terminal. ";
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      why+="Option 'Allow Algo Trading' decochee dans les proprietes de l'EA (onglet Commun). ";
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      why+="Trading interdit sur ce compte (mot de passe investisseur ?). ";
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      why+="Le broker interdit les EA sur ce compte. ";
   long tm=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
   if(tm==SYMBOL_TRADE_MODE_DISABLED)  why+="Trading desactive sur "+_Symbol+". ";
   if(tm==SYMBOL_TRADE_MODE_CLOSEONLY) why+="Symbole "+_Symbol+" en cloture seule. ";
   if(tm==SYMBOL_TRADE_MODE_LONGONLY)  why+="Symbole en achat seul. ";
   if(tm==SYMBOL_TRADE_MODE_SHORTONLY) why+="Symbole en vente seule. ";
   g_tradeReady=(why=="")?"Trading autorise":"BLOQUE : "+why;
   if(why!="") { Print("!!! ",g_tradeReady); if(!MQLInfoInteger(MQL_TESTER)) Alert("ICT NAS : ",g_tradeReady); }
   return(why=="");
  }

//--- Réduit le lot jusqu'à ce que la marge requise tienne dans x % de la marge libre
double FitMargin(int dir,double lots,double price,string &note)
  {
   note="";
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(step<=0) step=0.01;
   double freeM=AccountInfoDouble(ACCOUNT_MARGIN_FREE)*InpMaxMarginPct/100.0;
   ENUM_ORDER_TYPE t=(dir==1)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double m=0;
   if(!OrderCalcMargin(t,_Symbol,lots,price,m) || m<=freeM) return(lots);
   double m1=0;
   if(!OrderCalcMargin(t,_Symbol,1.0,price,m1) || m1<=0) return(lots);
   double fit=MathFloor(freeM/m1/step+1e-9)*step;
   if(fit<vmin) { note="marge insuffisante (lot min demande "+DoubleToString(vmin*m1,2)+", libre "+DoubleToString(freeM,2)+")"; return(0.0); }
   note="lot reduit "+DoubleToString(lots,2)+" -> "+DoubleToString(fit,2)+" (marge)";
   return(NormalizeDouble(fit,8));
  }

//--- Testeur : ordre de test au lot minimum pour vérifier toute la chaîne d'exécution
bool g_selfTestDone=false;
void SelfTest(void)
  {
   if(g_selfTestDone || !InpSelfTest || !MQLInfoInteger(MQL_TESTER)) return;
   g_selfTestDone=true;
   CTrade t;
   t.SetExpertMagicNumber(InpMagic+999);
   t.SetTypeFillingBySymbol(_Symbol);
   double v=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(!t.Buy(v,_Symbol,0,0,0,"ICTNAS self-test"))
     {
      Print("!!! ORDRE DE TEST REFUSE : ",t.ResultRetcode()," ",t.ResultRetcodeDescription(),
            " -> l'EA ne pourra pas trader tant que ce probleme n'est pas regle.");
      return;
     }
   ulong pos=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk>0 && PositionGetInteger(POSITION_MAGIC)==InpMagic+999) { pos=tk; break; }
     }
   if(pos>0) t.PositionClose(pos);
   Print("Ordre de test OK (",DoubleToString(v,2)," lot ouvert puis ferme) : la chaine d'execution fonctionne.");
  }

void DiagCount(const string key)
  {
   for(int i=0;i<ArraySize(g_diagKey);i++)
      if(g_diagKey[i]==key) { g_diagCnt[i]++; return; }
   int n=ArraySize(g_diagKey);
   ArrayResize(g_diagKey,n+1);
   ArrayResize(g_diagCnt,n+1);
   g_diagKey[n]=key;
   g_diagCnt[n]=1;
  }

//--- v2.40 : nombre de décisions dont la clé contient un texte
int DiagSum(const string part)
  {
   int n=0;
   for(int i=0;i<ArraySize(g_diagKey);i++) if(StringFind(g_diagKey[i],part)>=0) n+=g_diagCnt[i];
   return(n);
  }

//--- v2.40 : pistes quand l'EA trade peu (réponse à « il ne prend qu'un seul trade »)
void DiagHints(string &a[])
  {
   ArrayResize(a,0);
   int taken=DiagSum("TAKEN");
   LoAdd(a,"8. Ordres envoyes : "+IntegerToString(taken)+" | executes aujourd'hui : "+IntegerToString(g_tm_trades.FilledToday()));
   if(DiagSum("lot < lot minimum")>0)
      LoAdd(a,"   -> "+IntegerToString(DiagSum("lot < lot minimum"))+" setup(s) refuses : lot minimum trop risque pour ce capital / ce SL. "+
              "Augmenter le capital du testeur, InpRiskPct ou InpMinLotRiskTol.");
   if(DiagSum("DD total")>0 || StringFind(g_tradeReady,"DD total")>=0)
      LoAdd(a,"   -> DD total atteint : l'EA s'arrete DEFINITIVEMENT (regle prop firm). Backtest long : InpMaxTotalDDPct=0.");
   if(DiagSum("SL trop large")>0)
      LoAdd(a,"   -> "+IntegerToString(DiagSum("SL trop large"))+" setup(s) refuses : SL au-dela du plafond ATR. Option RiskGuard : InpSLCapMode=SL ramene au plafond.");
   if(DiagSum("max trades/jour")>0)
      LoAdd(a,"   -> "+IntegerToString(DiagSum("max trades/jour"))+" setup(s) apres la limite InpMaxTradesDay.");
   if(DiagSum("Stop journalier")>0 || DiagSum("Objectif journalier")>0)
      LoAdd(a,"   -> limites journalieres atteintes "+IntegerToString(DiagSum("Stop journalier")+DiagSum("Objectif journalier"))+" fois (InpDailyLossPct / InpDailyTargetPct).");
   if(g_risk.DDReported())
      LoAdd(a,"   -> DD total "+DoubleToString(InpMaxTotalDDPct,1)+" % atteint le "+TimeToString(g_risk.DDHitTime(),TIME_DATE|TIME_MINUTES)+
              " : en reel l'EA se serait arrete DEFINITIVEMENT a cette date. Testeur : le test a continue (InpDDHaltInTester=false).");
   //--- v2.50 : ce que l'EA a appris de TES données, modèle x session (règle v6.20), même avec InpAdaptGate=false
   string head="9. Modele x session (resultat virtuel des plans conformes ; regle v6.20 : n >= "+IntegerToString(MathMax(InpAdaptMinSamples,5))+
               " et E[R] + 1 erreur standard < 0)";
   if(!InpAdaptGate) head+=" - InpAdaptGate=false : signale, rien n'est bloque";
   LoAdd(a,head);
   for(int i=0;i<g_log.AdaptCount();i++)
     {
      string l=g_log.AdaptLine(i,InpAdaptMinSamples);
      if(l!="") LoAdd(a,"   "+l);
     }
   if(DiagSum("adaptatif")>0)
      LoAdd(a,"   -> "+IntegerToString(DiagSum("adaptatif"))+" setup(s) refuses par l'apprentissage (InpAdaptGate=true).");
   if(InpSelfTest && MQLInfoInteger(MQL_TESTER))
      LoAdd(a,"   -> InpSelfTest=true : le rapport du testeur contient aussi l'ordre de test (lot minimum, magic+999).");
  }

//--- Entonnoir complet : de la liquidité prise jusqu'à l'ordre
void PrintDiagnostic(const string title)
  {
   Print("===== DIAGNOSTIC ",title," =====");
   Print("1. Liquidites prises (declencheurs) : ",g_setup.nSweeps,"  | sweeps ERL H1 : ",g_setup.nERL);
   Print("2. Sequences abandonnees : pas de MSS/CISD a temps = ",g_setup.nTimeout,
         " | cassure sans displacement = ",g_setup.nNoDisp," | pas de FVG valide = ",g_setup.nNoFVG);
   Print("3. Setups ICT complets (sweep+MSS/CISD+displacement+FVG) : ",g_setup.nEmitted);
   Print("4. Setups hors fenetre / hors condition de modele (non enregistres) : ",g_nNoModel);
   Print("5. Decisions sur les setups valides :");
   for(int i=0;i<ArraySize(g_diagKey);i++) Print("     ",g_diagKey[i]," : ",g_diagCnt[i]);
   string lo[];
   LoDiagLines(lo);
   for(int i=0;i<ArraySize(lo);i++) Print(lo[i]);
   string v6[];
   V6DiagLines(v6);
   for(int i=0;i<ArraySize(v6);i++) Print(v6[i]);
   string hints[];
   DiagHints(hints);
   for(int i=0;i<ArraySize(hints);i++) Print(hints[i]);
   if(g_setup.nSweeps==0)
      Print("   -> Aucune liquidite prise : verifier le mode de ticks du testeur (utiliser 'Every tick based on real ticks') et l'historique.");
   else if(g_setup.nEmitted==0)
      Print("   -> Des sweeps mais aucun setup complet : essayer InpProfile=Agressif.");
   Print("   ",g_tradeReady);
   //--- v2.22 : copie dans Common\Files\ICTNAS\diagnostic.txt (facile à retrouver et à envoyer)
   FolderCreate("ICTNAS",FILE_COMMON);
   int h=FileOpen("ICTNAS\\diagnostic.txt",FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h!=INVALID_HANDLE)
     {
      FileWriteString(h,"DIAGNOSTIC "+title+" | "+_Symbol+" | v"+ICTNAS_VERSION+" | profil "+EnumToString(InpProfile)+"\r\n");
      FileWriteString(h,g_tradeReady+"\r\n");
      FileWriteString(h,"Liquidites prises : "+IntegerToString(g_setup.nSweeps)+" | ERL H1 : "+IntegerToString(g_setup.nERL)+"\r\n");
      FileWriteString(h,"Abandons : pas de MSS/CISD="+IntegerToString(g_setup.nTimeout)+" | sans displacement="+IntegerToString(g_setup.nNoDisp)+
                        " | sans FVG="+IntegerToString(g_setup.nNoFVG)+"\r\n");
      FileWriteString(h,"Setups complets : "+IntegerToString(g_setup.nEmitted)+" | hors modele : "+IntegerToString(g_nNoModel)+"\r\n");
      for(int i=0;i<ArraySize(g_diagKey);i++) FileWriteString(h,"  "+g_diagKey[i]+" : "+IntegerToString(g_diagCnt[i])+"\r\n");
      for(int i=0;i<ArraySize(lo);i++) FileWriteString(h,lo[i]+"\r\n");
      for(int i=0;i<ArraySize(v6);i++) FileWriteString(h,v6[i]+"\r\n");
      for(int i=0;i<ArraySize(hints);i++) FileWriteString(h,hints[i]+"\r\n");
      FileClose(h);
      Print("   Diagnostic ecrit dans : ",TerminalInfoString(TERMINAL_COMMONDATA_PATH),"\\Files\\ICTNAS\\diagnostic.txt");
     }
  }

void ProcessSetups(void)
  {
   SSetup c[];
   int n=g_setup.PopSetups(c);
   SSignal sigs[];
   int k=0;
   for(int i=0;i<n;i++)
     {
      SSignal s;
      if(!BuildSignal(c[i],s))
        {
         g_nNoModel++;
         if(InpDebugLog)
            Print("Setup sans modele : ",(c[i].dir==1?"LONG":"SHORT")," sweep ",c[i].liqName," a ",
                  TimeToString(g_tm.ServerToNY(c[i].tSweep),TIME_MINUTES)," NY, evalue a ",
                  TimeToString(g_tm.ServerToNY(TimeCurrent()),TIME_MINUTES)," NY (hors fenetre / condition de modele)");
         continue;
        }
      ArrayResize(sigs,k+1);
      sigs[k]=s;
      k++;
     }
   //--- v2.30 : setups autorisés par le moteur London OPR (PDF) sur cette bougie
   k=LoCollectSignals(sigs,k);
   //--- v2.40 : Silver Bullet 1er FVG / Macro Breaker de la v6.20 sur cette bougie
   k=V6CollectSignals(sigs,k);
   if(k==0) return;
   //--- tri par priorité de modèle (insertion)
   for(int i=1;i<k;i++)
     {
      SSignal t=sigs[i];
      int j=i-1;
      while(j>=0 && ModelRank(sigs[j].model)>ModelRank(t.model)) { sigs[j+1]=sigs[j]; j--; }
      sigs[j+1]=t;
     }
   bool takenThisBar=false;
   for(int i=0;i<k;i++)
     {
      g_setupsToday++;
      if(!sigs[i].fixedUid) sigs[i].uid+=IntegerToString(g_setupsToday);
      Decide(sigs[i],takenThisBar);
      V6AfterDecision(sigs[i]);
      string rk=sigs[i].decision;
      if(sigs[i].decision!="TAKEN" && sigs[i].reason!="")
        {
         string rr=sigs[i].reason;
         if(StringFind(rr,"RR ")==0) rr="RR < min";
         else if(StringFind(rr,"score ")==0) rr="score < min";
         else if(StringFind(rr,"p=")==0) rr="proba ML < seuil";
         else if(StringFind(rr,"SL trop large")==0) rr="SL trop large";
         else if(StringFind(rr,"ordre refuse")==0) rr="ordre refuse";
         else if(StringFind(rr,"marge insuffisante")==0) rr="marge insuffisante";
         else if(StringFind(rr,"lot < lot minimum")==0) rr="lot < lot minimum";
         else if(StringFind(rr,"DD total")==0) rr="DD total atteint";
         else if(StringFind(rr,"setup manque")==0) rr="setup manque (prix trop loin)";
         else if(StringFind(rr,"risque ouvert")==0) rr="risque ouvert cumule";
         else if(StringFind(rr,"spread ")==0) rr="spread";
         else if(StringFind(rr,"adaptatif")==0) rr="adaptatif (esperance negative)";
         rk+=" ("+rr+")";
        }
      DiagCount(rk);
      if(sigs[i].taken) takenThisBar=true;
      g_log.Add(sigs[i]);
      DrawSignal(sigs[i]);
      string line=TimeToString(sigs[i].tNY,TIME_MINUTES)+" "+sigs[i].model+(sigs[i].dir==1?" L":" S")+
                  " sc "+DoubleToString(sigs[i].score,0)+" RR "+DoubleToString(sigs[i].planRR,1)+
                  (sigs[i].mlProb>=0?" p "+DoubleToString(sigs[i].mlProb,2):"")+" -> "+sigs[i].decision;
      PushRecent(line+(sigs[i].reason!=""?" ("+sigs[i].reason+")":""));
      Print("Setup ",sigs[i].uid," ",line," ",sigs[i].reason);
      if(InpDebugLog)
         PrintFormat("   entree %s | SL %s | TP1 %s | DOL %s | risque %.1f pts | sweep %s (%s, poids %d)",
                     PxStr(sigs[i].entry),PxStr(sigs[i].sl),PxStr(sigs[i].tp1),PxStr(sigs[i].tp2),
                     sigs[i].riskPts,sigs[i].liqType,TimeToString(sigs[i].tSweepNY,TIME_MINUTES),sigs[i].liqWeight);
     }
  }

//--- Flat de fin de journée et limites journalières
void CheckDayGuards(datetime nowNY)
  {
   int m=CTimeManager::MinuteOfDay(nowNY);
   int flat=ParseHHMM(InpFlatTime);
   if(!g_flatDone && m>=flat && m<17*60)
     {
      g_tm_trades.CloseAll();
      g_flatDone=true;
     }
   string why;
   if(InpCloseOnDailyLimit && !g_limitClosed && !g_risk.CanTrade(why))
     {
      //--- v2.50 : objectif journalier atteint -> plus de nouvelle entrée (CanTrade), mais les positions
      //---         ouvertes gardent leur SL / cible (DOL). Le stop journalier reste surveillé ici.
      if(StringFind(why,"Objectif journalier")==0 && !InpCloseOnDailyTarget)
        {
         if(!g_targetKept)
           {
            g_targetKept=true;
            g_tm_trades.DeletePendingOrders();        // plus aucune nouvelle entrée, y compris par un ordre limite déjà posé
            Print("Objectif journalier atteint : ordres en attente supprimes, positions conservees jusqu'a leur SL / cible");
           }
         if(InpDailyLossPct>0 && g_risk.DayPnLPct()<=-InpDailyLossPct)
           {
            g_tm_trades.CloseAll();
            g_limitClosed=true;
            Print("Stop journalier -",DoubleToString(InpDailyLossPct,1),"% apres l'objectif -> positions fermees");
           }
         return;
        }
      g_tm_trades.CloseAll();
      g_limitClosed=true;
      Print("Limite atteinte : ",why," -> positions fermees, plus d'entree aujourd'hui");
     }
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- v2.30 : MT5 ne réinitialise pas les globales sur un changement de graphique / de paramètres
   g_anchor=0; g_lastM1=0; g_lastM15=0; g_lastM5=0; g_lastH1=0; g_lastExec=0;
   g_setupsToday=0; g_tradesToday=0; g_nNoModel=0; g_lastOrderSrv=0; g_selfTestDone=false;
   g_limitClosed=false; g_targetKept=false;                                  // v2.50
   ArrayResize(g_recent,0); ArrayResize(g_diagKey,0); ArrayResize(g_diagCnt,0);
   g_tm.Init(InpServerTZ,InpServerGMTOff);
   g_tzMsg=g_tm.CheckLiveOffset(g_tzOk);
   Print(g_tzMsg);
   if(!g_tzOk) Alert(g_tzMsg);

   int shadowEnd=ParseHHMM(InpShadowEnd);
   int rthClose=ParseHHMM(InpRTHClose);
   if(shadowEnd<0 || rthClose<0 || ParseHHMM(InpFlatTime)<0)
     {
      Print("Heure invalide (format HH:MM) : InpShadowEnd / InpRTHClose / InpFlatTime");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpExecTF!=PERIOD_M1 && InpExecTF!=PERIOD_M3 && InpExecTF!=PERIOD_M5)
     {
      Print("InpExecTF doit etre M1, M3 ou M5");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpRiskPct>RISK_HARD_CAP_PCT)
      Print("Risque demande ",InpRiskPct,"% > plafond ",RISK_HARD_CAP_PCT,"% : plafonne.");
   if(InpDailyLossPct>0 && InpDailyLossPct<InpRiskPct*1.999)
      Print("Attention : stop journalier ",InpDailyLossPct,"% < 2 x risque ",InpRiskPct,"% -> une seule perte arrete la journee.");

   //--- v2.30 : moteur London OPR (PDF) - configuration vérifiée avant tout le reste
   g_loTick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(g_loTick<=0) g_loTick=_Point;
   LoResetState();
   OPRConfig oc;
   string oerr="";
   if(!LoBuildConfig(oc,oerr))
     {
      Print("London OPR - parametre invalide : ",oerr);
      return(INIT_PARAMETERS_INCORRECT);
     }
   g_lo.logContext=true;
   g_lo.logAllFvg=false;
   g_lo.Init(oc);
   //--- v2.40 : modèles v6.20
   string v6err="";
   if(!V6ValidateInputs(v6err))
     {
      Print("Modeles v6.20 - parametre invalide : ",v6err);
      return(INIT_PARAMETERS_INCORRECT);
     }

   ParseList(InpWeeklyProfile,g_profile);
   g_atr.Init(_Symbol);
   g_opr.Init(_Symbol,GetPointer(g_tm),InpSTDVLevels,InpSTDVKey,shadowEnd);
   g_liq.Init(_Symbol,GetPointer(g_tm),InpSwingStrength,InpSwingLookbackH,InpEqTolMode,InpEqTolATR,InpEqTolPts,shadowEnd);
   g_gap.Init(_Symbol,GetPointer(g_tm),InpGapsKeep,rthClose,InpRTHBigPts);
   g_q.Init(_Symbol,GetPointer(g_tm));
   g_smt.Init(InpUseSMT,InpSMTSymbol);
   g_smt.Check();
   ApplyProfile();
   g_risk.Init(_Symbol,InpRiskPct,InpDailyLossPct,InpDailyTargetPct,InpMaxTotalDDPct,g_pMinRR,InpInitialBalance);
   g_risk.SetLotLimits(InpMinLotRiskTol,InpMaxLots);
   g_risk.SetDDReportOnly(MQLInfoInteger(MQL_TESTER)!=0 && !InpDDHaltInTester);   // v2.50
   g_draw.Init(InpDraw,InpKeepDays);
   g_panel.Init(InpShowPanel);
   g_setup.Init(_Symbol,GetPointer(g_liq),GetPointer(g_smt),GetPointer(g_atr),InpExecTF,g_pMinFVG,
                g_pDispMult,g_pRequireDisp,g_pHuntBars,InpUseERL,InpERLLookback);
   g_scorer.Init();
   if(g_scorer.LoadJSON(InpWeightsFile)) Print("Poids ICT recalibres charges : ",InpWeightsFile);
   if(InpMLMode!=ML_OFF) { g_ml.Load(InpMLFolder); Print(g_ml.Status()); }
   g_news.Init(InpNewsFilter,InpNewsBeforeMin,InpNewsAfterMin,GetPointer(g_tm),InpNewsCSV);
   Print(g_news.Status());

   if(InpCollect)
     {
      string csvPrefix="ICTNAS\\"+_Symbol+"_";
      if(g_db.Open(InpDBFile,InpCSVMirror,csvPrefix,InpFreshDBInTester))
         Print("DataCollector : ",g_db.FilePath());
      else
         Print("DataCollector desactive : ",g_db.LastError());
     }
   g_log.Init(GetPointer(g_db),_Symbol);
   g_tm_trades.Init(_Symbol,InpMagic,GetPointer(g_db),GetPointer(g_tm),InpBEPts,InpTrailing,InpTrailBufPts);
   V6Init();

   g_fpAsia.Clear();
   g_fpMid.Clear();
   //--- v2.30 : journal du moteur London OPR et rattrapage de l'historique M1
   LoCloseJournal();
   LoOpenJournal();
   LoLogConfig();
   LoWarmup();
   TradeReadiness();
   Print("ICT NAS Institutional ",ICTNAS_VERSION," | ",_Symbol," | ordres ",(InpTradingEnabled?"ACTIVES":"desactives (observation)")," | ",g_tradeReady);
   Print("Contrat : ",g_risk.SpecString());
   Print(g_smt.Status());
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   PrintDiagnostic("FINAL");
   g_log.Flush();
   if(g_anchor>0)
     {
      datetime nowNY=g_tm.ServerToNY(TimeCurrent());
      LogDay(nowNY>=g_anchor+17*SEC_HOUR);
     }
   g_db.Close();
   LoCloseJournal();
   V6Deinit();
   g_liq.Deinit();
   g_atr.Deinit();
   g_ml.Release();
   g_draw.DeleteAll();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime now=TimeCurrent();
   datetime nowNY=g_tm.ServerToNY(now);
   datetime anchor=CTimeManager::TradingDayAnchor(nowNY);
   if(anchor!=g_anchor)
     {
      if(g_anchor>0)
        {
         TradeReadiness();
         LogDay(true);
         if(InpDailyDiagnostic) PrintDiagnostic("cumul au "+DateStr(g_anchor));
        }
      StartDay(anchor);
     }

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(bid<=0) return;
   SelfTest();
   g_liq.OnTick(bid,now);
   g_setup.OnSweeps();
   g_tm_trades.OnTick();

   bool newBar=false;
   datetime m1=iTime(_Symbol,PERIOD_M1,0);
   if(m1!=g_lastM1 && m1>0)
     {
      g_lastM1=m1;
      newBar=true;
      //--- contexte
      g_opr.OnNewBar(now);
      g_liq.OnNewBar(now);
      g_liq.OnClosedBar();
      g_gap.OnNewBar(now);
      g_q.Update(nowNY);
      datetime m15=iTime(_Symbol,PERIOD_M15,0);
      if(m15!=g_lastM15 && m15>0)
        {
         if(g_lastM15>0) g_liq.OnNewM15();
         g_lastM15=m15;
        }
      if(g_dayOpen==0)
        {
         MqlRates o;
         if(FirstBarAtOrAfter(_Symbol,g_tm.NYToServer(g_anchor-6*SEC_HOUR),3*SEC_HOUR,o)) g_dayOpen=o.open;
        }
      //--- v2.30 : moteur London OPR (PDF) sur les bougies M1 clôturées ; FPFVG du moteur ou calcul v2.22
      LoProcessNewBars();
      if(!InpFPFVGFromEngine) UpdateFPFVG(now);
      //--- High / Low des OPR 00:00, 09:30 et 13:30 dans la carte de liquidité (modèle CRT OPR)
      AddOPRLevels(g_opr.mor,"OPR00",g_oprLvl0000);
      AddOPRLevels(g_opr.opr0930,"OPR0930",g_oprLvl0930);
      AddOPRLevels(g_opr.opr1330,"OPR1330",g_oprLvl1330);
      if(g_gapsAbove0930<0 && g_opr.open0930>0)
         g_gap.Cluster(g_opr.open0930,g_gapsAbove0930,g_gapsBelow0930);
      //--- setups
      g_setup.OnSweeps();
      datetime h1=iTime(_Symbol,PERIOD_H1,0);
      if(h1!=g_lastH1 && h1>0)
        {
         if(g_lastH1>0) g_setup.OnNewH1();
         g_lastH1=h1;
        }
      datetime m5=iTime(_Symbol,PERIOD_M5,0);
      if(m5!=g_lastM5 && m5>0)
        {
         g_lastM5=m5;
         g_setup.OnNewBar(PERIOD_M5);
         ScanMomentum();
        }
      if(InpExecTF!=PERIOD_M5)
        {
         datetime ex=iTime(_Symbol,InpExecTF,0);
         if(ex!=g_lastExec && ex>0)
           {
            g_lastExec=ex;
            g_setup.OnNewBar(InpExecTF);
           }
        }
      g_log.OnNewBar();
      ProcessSetups();
      g_risk.Update();
      CheckDayGuards(nowNY);
      DrawAll();
     }

   if(g_panel.On() && (newBar || GetTickCount()-g_lastPanelMs>500))
     {
      g_lastPanelMs=GetTickCount();
      UpdatePanel(nowNY,bid);
     }
  }
//+------------------------------------------------------------------+
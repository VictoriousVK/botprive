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
//|    London OPR (MOR), OPR 01:30 / 07:00 / 09:30 / 13:30, ERL->IRL |
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
//+------------------------------------------------------------------+
#property copyright "Victor — ICT NAS Institutional"
#property version   "2.21"
#property description "EA ICT complet NAS100 : modeles ICT, score, filtre ML ONNX, gestion des partiels, collecte de donnees."

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
#define ICTNAS_VERSION  "2.21"
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
   PROFILE_STANDARD   = 1,  // Standard : ICT + gestion v6 (SL borné ATR, cible de secours, TP1 à 1R, momentum SB)
   PROFILE_AGGRESSIVE = 2,  // Agressif : entrées au marché, RR 1, displacement non obligatoire
   PROFILE_CUSTOM     = 3   // Personnalisé : utilise les inputs du groupe "Profil personnalisé"
  };

//--- Biais hebdomadaire manuel
enum ENUM_WEEKLY_BIAS
  {
   WB_NONE =  0,   // Aucun
   WB_BULL =  1,   // Haussier
   WB_BEAR = -1    // Baissier
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
     }
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
      if(TotalDDPct()>=m_maxTotalDDPct)
        { m_hardBlocked=true; m_reason="DD total "+DoubleToString(m_maxTotalDDPct,1)+"% atteint"; return; }
      if(m_dayBlocked) return;
      double d=DayPnLPct();
      if(d<=-m_dailyLossPct)  { m_dayBlocked=true; m_reason="Stop journalier -"+DoubleToString(m_dailyLossPct,1)+"%"; }
      else if(d>=m_dailyTargetPct) { m_dayBlocked=true; m_reason="Objectif journalier +"+DoubleToString(m_dailyTargetPct,1)+"%"; }
     }
   bool              CanTrade(string &why)
     {
      why=m_reason;
      return(!m_dayBlocked && !m_hardBlocked);
     }

   //--- Lots pour risquer riskPct du solde entre entry et sl. 0 = trade impossible
   //--- (jamais d'arrondi vers le haut : si le lot min dépasse le risque, on refuse)
   double            CalcLots(bool isBuy,double entry,double sl,double riskPct=-1)
     {
      if(riskPct<0) riskPct=m_riskPct;
      riskPct=MathMin(riskPct,RISK_HARD_CAP_PCT);
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
      if(lots<vmin) return(0.0);
      if(lots>vmax) lots=vmax;
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
         if(d*(fav-s.tp1)>=0) { Close(s,b.time); return; }   // cible atteinte sans retracement
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
   void              Init(CDataCollector *db,const string sym) { m_db=db; m_sym=sym; m_written=0; ArrayResize(m_open,0); }
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
               continue;
              }
            if(OrderSelect(m_t[i].order))
              {
               if(now>=m_t[i].tExpiry || d*(px-m_t[i].tp1)>=0)
                 {
                  m_trade.OrderDelete(m_t[i].order);
                  m_t[i].active=false;
                 }
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
input bool             InpUseLondonOPR    = true;           // London OPR (MOR, 02:50-04:10)
input bool             InpLondonNeedMacro = true;           // London OPR : le sweep doit avoir lieu pendant une macro
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
input double           InpMinRR           = 3.0;            // RR minimal vers la cible
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
input int              InpMaxTradesDay    = 3;              // Trades max par jour
input int              InpMaxConcurrent   = 1;              // Positions / ordres simultanés max

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
input double           InpRiskPct         = 3.0;            // Risque par trade % (plafonné à 3 %)
input double           InpDailyLossPct    = 3.0;            // Stop journalier % (avec 3 %/trade : 1 perte = arrêt du jour)
input double           InpDailyTargetPct  = 9.0;            // Objectif journalier % (1 gain à 3R = 9 %)
input double           InpMaxTotalDDPct   = 8.0;            // DD total max % (prop firm)
input bool             InpCloseOnDailyLimit = true;         // Tout fermer quand une limite journalière est atteinte
input double           InpInitialBalance  = 0;              // Solde de référence DD total (0 = solde au lancement)
input double           InpBEAtR           = 1.0;            // Break-even quand le prix atteint x R
input double           InpBEPts           = 1.0;            // Break-even : entrée + x points
input bool             InpTrailing        = false;          // Trailing structurel M1 après l'allègement
input double           InpTrailBufPts     = 2.0;            // Buffer du trailing (points)
input double           InpTestSLPts       = 20.0;           // Panneau : SL de test pour la taille de lot

input group "=== Données ==="
input bool             InpCollect         = true;           // Enregistrer contexte, signaux et trades (SQLite)
input string           InpDBFile          = "ICTNAS\\ict_nas.sqlite"; // Base SQLite (Common\Files)
input bool             InpCSVMirror       = true;           // Copie CSV
input bool             InpFreshDBInTester = true;           // Testeur : base vide à chaque passe

input group "=== Diagnostic ==="
input bool             InpDebugLog        = false;          // Journal détaillé de chaque setup
input bool             InpDailyDiagnostic = true;           // Résumé de l'entonnoir chaque jour dans le journal

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
int               g_tradesToday=0;
double            g_dayOpen=0;
bool              g_flatDone=false;
bool              g_limitClosed=false;
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
   if(m=="CRT_0830")      return(3);
   if(m=="LONDON_OPR")    return(4);
   if(m=="CRT_0250")      return(5);
   if(m=="CRT_OPR")       return(6);
   if(StringFind(m,"OPR_")==0) return(7);
   if(m=="CRT_PM")        return(8);
   if(m=="KILLZONE")      return(9);
   if(m=="SB_MOMENTUM")   return(10);
   return(11);
  }
string ModelCode(const string m)
  {
   if(m=="SHADOW") return("SH");
   if(m=="SILVER_BULLET") return("SB");
   if(m=="LONDON_OPR") return("LO");
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
//| g_pMinRR x R ; à défaut le plus proche tout court (le RR décide). |
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
      if(r>0 && d>=(g_pMinRR-RR_EPS)*r && d<dFar) { dFar=d; bestFar=cands[i]; }
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
   //--- 3. London OPR (MOR) : 02:50-04:10, biais de 02:50, sweep pendant une macro
   if(InpUseLondonOPR && InMin(m,170,250) && g_opr.morBiasSet && g_opr.morBias==c.dir)
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
   int m=CTimeManager::MinuteOfDay(nowNY);
   MqlDateTime st;
   TimeToStruct(nowNY,st);
   s.model=model;
   s.dir=c.dir;
   s.tSrv=now;
   s.tNY=nowNY;
   s.uid=ModelCode(model)+"-"+StringFormat("%04d%02d%02d%02d%02d",st.year,st.mon,st.day,st.hour,st.min)+(c.dir==1?"L":"S");
   //--- temps
   s.dow=st.day_of_week; s.month=st.mon; s.hour=st.hour; s.minute=st.min;
   s.session=CTimeManager::SessionLabel(nowNY); s.killzone=s.session;
   s.sbWindow=CTimeManager::SilverBulletLabel(nowNY,InpSBMode);
   s.macro=CTimeManager::MacroLabel(nowNY);
   s.dayQ=g_q.dayQ; s.q90=g_q.q90; s.q22=g_q.q22;
   s.shadowActive=(g_opr.shadow.complete && InMin(m,ParseHHMM(InpShadowEnd),11*60+30))?1:0;
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
   s.pdPct=g_liq.PDPercent(s.entry);
   s.pdLabel=(s.pdPct<0)?"":(s.pdPct>=50?"PREMIUM":"DISCOUNT");
   double legR=MathAbs(c.extreme-c.legEnd);
   double ret=(legR>0)?MathAbs(s.entry-c.legEnd)/legR:0;
   s.ote=(ret>=0.62 && ret<=0.79)?1:0;
   s.smt=c.smt;
   s.stdvReached=hasRef?((c.dir==-1)?ref.ExtUp():ref.ExtDn()):0;
   s.weeklyProfile=ProfileOf(g_anchor);
   s.amdx=CQuarterlyEngine::AMDX(g_q.dayQ);
   double to=(g_q.sessTO>0)?g_q.sessTO:g_q.dayTO;
   s.qAlign=(to>0 && ((c.dir==-1 && s.entry>to) || (c.dir==1 && s.entry<to)))?1:0;
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
   //--- 2. cible / RR
   if(s.planRR<g_pMinRR-RR_EPS)
     {
      s.decision="REJECTED_RISK";
      s.reason=(s.planRR<=0)?"pas de cible (DOL)":"RR "+DoubleToString(s.planRR,2)+" < "+DoubleToString(g_pMinRR,1);
      return;
     }
   //--- 3. score ICT
   if(s.score<g_pScoreMin-1e-6) { s.decision="REJECTED_SCORE"; s.reason="score "+DoubleToString(s.score,0); return; }
   //--- 4. ML (filtre seulement si le modèle est promu ET le mode FILTRE choisi)
   if(InpMLMode==ML_FILTER && g_ml.Ready() && g_ml.Promoted() && s.mlProb>=0 && s.mlProb<g_ml.Threshold())
     { s.decision="REJECTED_ML"; s.reason="p="+DoubleToString(s.mlProb,2); return; }
   //--- 5. risque
   string rs;
   if(!g_risk.CanTrade(rs)) { s.decision="REJECTED_RISK"; s.reason=rs; return; }
   if(g_tradesToday>=InpMaxTradesDay) { s.decision="REJECTED_RISK"; s.reason="max trades/jour"; return; }
   //--- 6. conflit : un seul biais à la fois, jamais buy + sell
   int ad=g_tm_trades.ActiveDirection();
   if(conflictThisBar || (ad!=0 && ad!=s.dir) || g_tm_trades.ActiveCount()>=InpMaxConcurrent)
     { s.decision="REJECTED_CONFLICT"; s.reason="position/ordre deja actif"; return; }
   if(!InpTradingEnabled) { s.decision="OBSERVED"; s.reason="trading desactive (input)"; return; }
   //--- 7. taille et exécution
   double lots=g_risk.CalcLots(s.dir==1,s.entry,s.sl);
   if(lots<=0) { s.decision="REJECTED_RISK"; s.reason="lot < lot minimum"; return; }
   double loss=0;
   OrderCalcProfit(s.dir==1?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,lots,s.entry,s.sl,loss);
   SetExitWeights(s);
   string err;
   if(!g_tm_trades.Place(s,lots,MathAbs(loss),err)) { s.decision="REJECTED_RISK"; s.reason=err; return; }
   s.decision="TAKEN";
   s.taken=true;
   g_tradesToday++;
  }

#endif
//+------------------------------------------------------------------+
//=== fin ModelRouter.mqh ===

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
             " | Trades: "+IntegerToString(g_tradesToday)+"/"+IntegerToString(InpMaxTradesDay));
   AddLine(L,"Signaux suivis: "+IntegerToString(g_log.Tracking())+" | enregistres: "+IntegerToString(g_log.Written())+
             " | Score min "+DoubleToString(g_pScoreMin,0)+" (poids "+g_scorer.Source()+")");
   AddLine(L,(InpMLMode==ML_OFF)?"ML : desactive":g_ml.Status()+(InpMLMode==ML_OBSERVE?" [observation]":" [filtre]"));
   AddLine(L,g_news.Status());
   if(g_fpAsia.valid) AddLine(L,"FPFVG Asie "+(g_fpAsia.dir==1?"haussier ":"baissier ")+PxStr(g_fpAsia.bottom)+"-"+PxStr(g_fpAsia.top));
   if(g_fpMid.valid)  AddLine(L,"FPFVG Midnight "+(g_fpMid.dir==1?"haussier ":"baissier ")+PxStr(g_fpMid.bottom)+"-"+PxStr(g_fpMid.top));
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
//+------------------------------------------------------------------+
void ApplyProfile(void)
  {
   switch(InpProfile)
     {
      case PROFILE_STRICT:
         g_pScoreMin=60; g_pMinRR=3.0; g_pFallbackRR=0; g_pMaxRR=0; g_pSLFloorATR=0; g_pSLCapATR=0; g_pTP1R=2.0;
         g_pMinFVG=5; g_pDispMult=1.5; g_pHuntBars=30; g_pRequireDisp=true; g_pMarket=false;
         g_pMomentum=false; g_pKillzone=false;
         break;
      case PROFILE_STANDARD:
         g_pScoreMin=25; g_pMinRR=3.0; g_pFallbackRR=3.0; g_pMaxRR=5.0; g_pSLFloorATR=0.8; g_pSLCapATR=2.5; g_pTP1R=2.0;
         g_pMinFVG=3; g_pDispMult=1.2; g_pHuntBars=45; g_pRequireDisp=true; g_pMarket=false;
         g_pMomentum=InpUseMomentum; g_pKillzone=InpUseKillzoneModel;
         break;
      case PROFILE_AGGRESSIVE:
         g_pScoreMin=0; g_pMinRR=3.0; g_pFallbackRR=3.0; g_pMaxRR=4.0; g_pSLFloorATR=0.8; g_pSLCapATR=2.5; g_pTP1R=2.0;
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
   PrintFormat("Profil %s : score>=%.0f RR>=%.1f cible secours %.1fR SL %.1f-%.1f ATR M5 allegement 50%% a %.1fR FVG>=%.1f disp %.1f ATR %s | momentum %s | killzone %s",
               EnumToString(InpProfile),g_pScoreMin,g_pMinRR,g_pFallbackRR,g_pSLFloorATR,g_pSLCapATR,g_pTP1R,
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
   if(g_setup.nSweeps==0)
      Print("   -> Aucune liquidite prise : verifier le mode de ticks du testeur (utiliser 'Every tick based on real ticks') et l'historique.");
   else if(g_setup.nEmitted==0)
      Print("   -> Des sweeps mais aucun setup complet : essayer InpProfile=Agressif.");
  }

void ProcessSetups(void)
  {
   SSetup c[];
   int n=g_setup.PopSetups(c);
   if(n==0) return;
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
      sigs[i].uid+=IntegerToString(g_setupsToday);
      Decide(sigs[i],takenThisBar);
      string rk=sigs[i].decision;
      if(sigs[i].decision!="TAKEN" && sigs[i].reason!="")
        {
         string rr=sigs[i].reason;
         if(StringFind(rr,"RR ")==0) rr="RR < min";
         else if(StringFind(rr,"score ")==0) rr="score < min";
         else if(StringFind(rr,"p=")==0) rr="proba ML < seuil";
         else if(StringFind(rr,"SL trop large")==0) rr="SL trop large";
         else if(StringFind(rr,"ordre refuse")==0) rr="ordre refuse";
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

   g_fpAsia.Clear();
   g_fpMid.Clear();
   Print("ICT NAS Institutional ",ICTNAS_VERSION," | ",_Symbol," | ordres ",(InpTradingEnabled?"ACTIVES":"desactives (observation)"));
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
         LogDay(true);
         if(InpDailyDiagnostic) PrintDiagnostic("cumul au "+DateStr(g_anchor));
        }
      StartDay(anchor);
     }

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(bid<=0) return;
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
      UpdateFPFVG(now);
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

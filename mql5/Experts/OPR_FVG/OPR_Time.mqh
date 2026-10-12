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

#include "OPR_Config.mqh"

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

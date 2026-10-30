// Couche de compatibilité minimale MQL5 -> C++ (types, tableaux, maths, temps).
// Utilisée uniquement par les tests : le code de production reste du MQL5 pur.
#pragma once
#include <cfloat>
#include <climits>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <iostream>
#include <sstream>
#include <string>
#include <type_traits>
#include <vector>

typedef std::string string;
typedef long datetime;
typedef unsigned int color;
typedef unsigned long ulong;
typedef unsigned int uint;
typedef unsigned short ushort;
typedef unsigned char uchar;

#define MQL_RGB(r, g, b) ((color)((r) | ((g) << 8) | ((b) << 16)))

// --- tableaux dynamiques avec contrôle de bornes (équivalent "array out of range")
template <class T>
struct MqlArray {
  std::vector<T> v;
  bool series = false;
  T &at_(int i) {
    if (i < 0 || i >= (int)v.size()) {
      fprintf(stderr, "array out of range: index %d, size %d\n", i, (int)v.size());
      abort();
    }
    return series ? v[v.size() - 1 - i] : v[i];
  }
  T &operator[](int i) { return at_(i); }
  const T &operator[](int i) const { return const_cast<MqlArray *>(this)->at_(i); }
};
template <class T>
int ArraySize(const MqlArray<T> &a) { return (int)a.v.size(); }
template <class T, size_t N>
int ArraySize(const T (&)[N]) { return (int)N; }
template <class T>
int ArrayResize(MqlArray<T> &a, int n, int reserve = 0) {
  if (n < 0) return -1;
  if (reserve > 0) a.v.reserve(n + reserve);
  a.v.resize(n);
  return n;
}
template <class T>
void ArrayFree(MqlArray<T> &a) { a.v.clear(); }
template <class T>
bool ArraySetAsSeries(MqlArray<T> &a, bool f) { a.series = f; return true; }
template <class T>
void ZeroMemory(T &x) {
  static_assert(std::is_trivially_copyable<T>::value, "ZeroMemory sur type non trivial");
  memset((void *)&x, 0, sizeof(T));
}

// --- maths
template <class A, class B>
auto MathMax(A a, B b) -> decltype(a + b) { return a > b ? a : b; }
template <class A, class B>
auto MathMin(A a, B b) -> decltype(a + b) { return a < b ? a : b; }
inline double MathAbs(double x) { return std::fabs(x); }
inline double MathFloor(double x) { return std::floor(x); }
inline double MathCeil(double x) { return std::ceil(x); }
inline double MathRound(double x) { return std::round(x); }
inline double MathLog10(double x) { return std::log10(x); }
inline double MathPow(double a, double b) { return std::pow(a, b); }
inline double MathSqrt(double x) { return std::sqrt(x); }
inline double MathMod(double a, double b) { return std::fmod(a, b); }
inline bool MathIsValidNumber(double x) { return std::isfinite(x); }
inline double NormalizeDouble(double v, int d) {
  double p = std::pow(10.0, d);
  return std::round(v * p) / p;
}

// --- temps
struct MqlDateTime {
  int year, mon, day, hour, min, sec, day_of_week, day_of_year;
};
inline bool TimeToStruct(datetime t, MqlDateTime &s) {
  time_t tt = (time_t)t;
  struct tm g;
  gmtime_r(&tt, &g);
  s.year = g.tm_year + 1900;
  s.mon = g.tm_mon + 1;
  s.day = g.tm_mday;
  s.hour = g.tm_hour;
  s.min = g.tm_min;
  s.sec = g.tm_sec;
  s.day_of_week = g.tm_wday;
  s.day_of_year = g.tm_yday;
  return true;
}
inline datetime StructToTime(MqlDateTime &s) {
  struct tm g;
  memset(&g, 0, sizeof(g));
  g.tm_year = s.year - 1900;
  g.tm_mon = s.mon - 1;
  g.tm_mday = s.day;
  g.tm_hour = s.hour;
  g.tm_min = s.min;
  g.tm_sec = s.sec;
  return (datetime)timegm(&g);
}

// --- chaînes / affichage
inline const char *fmt_arg(const std::string &s) { return s.c_str(); }
template <class T>
T fmt_arg(T v) { return v; }

template <class... A>
string StringFormat(const string &f, A... a) {
  // MQL5 : %I64d / %I64u = entier 64 bits (long en C++ sous Linux)
  std::string g = f;
  for (size_t p; (p = g.find("%I64")) != std::string::npos;) g.replace(p, 4, "%l");
  char buf[4096];
  snprintf(buf, sizeof(buf), g.c_str(), fmt_arg(a)...);
  return string(buf);
}
extern bool g_shim_quiet;
template <class... A>
void PrintFormat(const string &f, A... a) {
  if (g_shim_quiet) return;
  std::cout << StringFormat(f, a...) << "\n";
}
inline void print_one(std::ostringstream &) {}
template <class T, class... R>
void print_one(std::ostringstream &o, const T &v, const R &...r) {
  o << v;
  print_one(o, r...);
}
template <class... A>
void Print(const A &...a) {
  if (g_shim_quiet) return;
  std::ostringstream o;
  print_one(o, a...);
  std::cout << o.str() << "\n";
}
inline string DoubleToString(double v, int d = 8) {
  char buf[64];
  snprintf(buf, sizeof(buf), "%.*f", d, v);
  return buf;
}
inline string IntegerToString(long v, int = 0, ushort = ' ') { return std::to_string(v); }
inline long StringToInteger(const string &s) { return atol(s.c_str()); }
inline double StringToDouble(const string &s) { return atof(s.c_str()); }
inline int StringLen(const string &s) { return (int)s.size(); }
inline string StringSubstr(const string &s, int start, int len = -1) {
  if (start < 0 || start >= (int)s.size()) return "";
  return len < 0 ? s.substr(start) : s.substr(start, len);
}
inline int StringFind(const string &s, const string &m, int start = 0) {
  size_t p = s.find(m, start);
  return p == std::string::npos ? -1 : (int)p;
}
inline int StringSplit(const string &s, ushort sep, MqlArray<string> &res) {
  res.v.clear();
  std::string cur;
  for (char ch : s) {
    if ((ushort)ch == sep) {
      res.v.push_back(cur);
      cur.clear();
    } else
      cur += ch;
  }
  res.v.push_back(cur);
  return (int)res.v.size();
}
inline bool StringTrimLeft(string &s) {
  size_t p = s.find_first_not_of(" \t");
  s = p == std::string::npos ? "" : s.substr(p);
  return true;
}
inline bool StringTrimRight(string &s) {
  size_t p = s.find_last_not_of(" \t");
  s = p == std::string::npos ? "" : s.substr(0, p + 1);
  return true;
}
// flags : 1 = date, 2 = heures:minutes, 4 = secondes (0 = date + heures:minutes, comme MT5)
inline string TimeToString(datetime t, int flags = 3) {
  MqlDateTime s;
  TimeToStruct(t, s);
  if (flags == 0) flags = 3;
  char buf[64];
  std::string out;
  if (flags & 1) {
    snprintf(buf, sizeof(buf), "%04d.%02d.%02d", s.year, s.mon, s.day);
    out = buf;
  }
  if (flags & 6) {
    if (!out.empty()) out += " ";
    if (flags & 4)
      snprintf(buf, sizeof(buf), "%02d:%02d:%02d", s.hour, s.min, s.sec);
    else
      snprintf(buf, sizeof(buf), "%02d:%02d", s.hour, s.min);
    out += buf;
  }
  return out;
}
// "YYYY.MM.DD [HH:MM[:SS]]"
inline datetime StringToTime(const string &str) {
  MqlDateTime s;
  memset(&s, 0, sizeof(s));
  int n = sscanf(str.c_str(), "%d.%d.%d %d:%d:%d", &s.year, &s.mon, &s.day, &s.hour, &s.min, &s.sec);
  if (n < 3) return 0;
  return StructToTime(s);
}
inline int StringReplace(string &s, const string &from, const string &to) {
  if (from.empty()) return 0;
  int n = 0;
  size_t p = 0;
  while ((p = s.find(from, p)) != std::string::npos) {
    s.replace(p, from.size(), to);
    p += to.size();
    n++;
  }
  return n;
}
inline ushort StringGetCharacter(const string &s, int pos) {
  return (pos >= 0 && pos < (int)s.size()) ? (ushort)(unsigned char)s[pos] : 0;
}
inline string ShortToString(ushort c) { return string(1, (char)c); }

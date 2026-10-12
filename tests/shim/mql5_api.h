// API MetaTrader 5 simulée pour les tests : marché tick par tick, ordres limites,
// positions avec SL/TP, historique des deals, objets graphiques et CTrade.
// Les signatures suivent la documentation MQL5 afin que g++ vérifie les appels de l'EA.
#pragma once
#include <algorithm>
#include <fstream>
#include <map>

#include "mql5_core.h"

#ifndef ULONG_MAX
#define ULONG_MAX 18446744073709551615UL
#endif

// ------------------------------------------------------------------ énumérations
enum ENUM_TIMEFRAMES {
  PERIOD_CURRENT = 0, PERIOD_M1 = 1, PERIOD_M2 = 2, PERIOD_M3 = 3, PERIOD_M4 = 4, PERIOD_M5 = 5, PERIOD_M6 = 6,
  PERIOD_M10 = 10, PERIOD_M12 = 12, PERIOD_M15 = 15, PERIOD_M20 = 20, PERIOD_M30 = 30, PERIOD_H1 = 16385,
  PERIOD_H4 = 16388, PERIOD_D1 = 16408
};
enum ENUM_ORDER_TYPE { ORDER_TYPE_BUY = 0, ORDER_TYPE_SELL = 1, ORDER_TYPE_BUY_LIMIT = 2, ORDER_TYPE_SELL_LIMIT = 3,
                       ORDER_TYPE_BUY_STOP = 4, ORDER_TYPE_SELL_STOP = 5 };
enum ENUM_ORDER_TYPE_TIME { ORDER_TIME_GTC = 0, ORDER_TIME_DAY = 1, ORDER_TIME_SPECIFIED = 2 };
enum ENUM_ORDER_TYPE_FILLING { ORDER_FILLING_FOK = 0, ORDER_FILLING_IOC = 1, ORDER_FILLING_RETURN = 2 };
enum ENUM_LINE_STYLE { STYLE_SOLID = 0, STYLE_DASH = 1, STYLE_DOT = 2, STYLE_DASHDOT = 3 };
enum ENUM_ANCHOR_POINT { ANCHOR_LEFT_UPPER = 0, ANCHOR_LEFT = 1, ANCHOR_LEFT_LOWER = 2, ANCHOR_LOWER = 3,
                         ANCHOR_RIGHT_LOWER = 4, ANCHOR_RIGHT = 5, ANCHOR_RIGHT_UPPER = 6, ANCHOR_UPPER = 7,
                         ANCHOR_CENTER = 8 };
enum ENUM_BASE_CORNER { CORNER_LEFT_UPPER = 0, CORNER_LEFT_LOWER = 1, CORNER_RIGHT_LOWER = 2, CORNER_RIGHT_UPPER = 3 };
enum ENUM_BORDER_TYPE { BORDER_FLAT = 0, BORDER_RAISED = 1, BORDER_SUNKEN = 2 };
enum ENUM_OBJECT { OBJ_VLINE = 0, OBJ_TREND = 2, OBJ_RECTANGLE = 16, OBJ_ARROW = 100, OBJ_TEXT = 101, OBJ_LABEL = 102,
                   OBJ_RECTANGLE_LABEL = 110 };
enum ENUM_OBJECT_PROPERTY_INTEGER {
  OBJPROP_COLOR, OBJPROP_STYLE, OBJPROP_WIDTH, OBJPROP_BACK, OBJPROP_ZORDER, OBJPROP_FILL, OBJPROP_HIDDEN,
  OBJPROP_SELECTED, OBJPROP_SELECTABLE, OBJPROP_RAY_LEFT, OBJPROP_RAY_RIGHT, OBJPROP_FONTSIZE, OBJPROP_ANCHOR,
  OBJPROP_XDISTANCE, OBJPROP_YDISTANCE, OBJPROP_XSIZE, OBJPROP_YSIZE, OBJPROP_BGCOLOR, OBJPROP_CORNER,
  OBJPROP_BORDER_TYPE, OBJPROP_ARROWCODE
};
enum ENUM_OBJECT_PROPERTY_DOUBLE { OBJPROP_PRICE };
enum ENUM_OBJECT_PROPERTY_STRING { OBJPROP_TEXT, OBJPROP_FONT, OBJPROP_TOOLTIP };
enum ENUM_LOG_LEVELS { LOG_LEVEL_NO = 0, LOG_LEVEL_ERRORS = 1, LOG_LEVEL_ALL = 2 };
enum ENUM_SYMBOL_INFO_DOUBLE { SYMBOL_BID, SYMBOL_ASK, SYMBOL_POINT, SYMBOL_TRADE_TICK_SIZE, SYMBOL_TRADE_TICK_VALUE,
                               SYMBOL_VOLUME_MIN, SYMBOL_VOLUME_MAX, SYMBOL_VOLUME_STEP };
enum ENUM_SYMBOL_INFO_INTEGER { SYMBOL_DIGITS, SYMBOL_TRADE_STOPS_LEVEL, SYMBOL_TRADE_FREEZE_LEVEL, SYMBOL_EXPIRATION_MODE,
                                SYMBOL_FILLING_MODE };
enum ENUM_ACCOUNT_INFO_DOUBLE { ACCOUNT_BALANCE, ACCOUNT_EQUITY, ACCOUNT_MARGIN_FREE };
enum ENUM_ACCOUNT_INFO_STRING { ACCOUNT_CURRENCY, ACCOUNT_NAME };
enum ENUM_MQL_INFO_INTEGER { MQL_TESTER, MQL_VISUAL_MODE, MQL_OPTIMIZATION, MQL_TRADE_ALLOWED };
enum ENUM_TERMINAL_INFO_INTEGER { TERMINAL_TRADE_ALLOWED, TERMINAL_CONNECTED };
enum ENUM_POSITION_PROPERTY_INTEGER { POSITION_MAGIC, POSITION_TYPE, POSITION_TIME };
enum ENUM_POSITION_PROPERTY_DOUBLE { POSITION_PRICE_OPEN, POSITION_SL, POSITION_TP, POSITION_VOLUME, POSITION_PROFIT };
enum ENUM_POSITION_PROPERTY_STRING { POSITION_SYMBOL, POSITION_COMMENT };
enum ENUM_POSITION_TYPE { POSITION_TYPE_BUY = 0, POSITION_TYPE_SELL = 1 };
enum ENUM_ORDER_PROPERTY_INTEGER { ORDER_MAGIC, ORDER_TYPE };
enum ENUM_ORDER_PROPERTY_DOUBLE { ORDER_PRICE_OPEN, ORDER_SL, ORDER_TP, ORDER_VOLUME_CURRENT };
enum ENUM_ORDER_PROPERTY_STRING { ORDER_SYMBOL, ORDER_COMMENT };
enum ENUM_DEAL_PROPERTY_INTEGER { DEAL_MAGIC, DEAL_ENTRY, DEAL_TYPE, DEAL_TIME };
enum ENUM_DEAL_PROPERTY_DOUBLE { DEAL_PROFIT, DEAL_SWAP, DEAL_COMMISSION, DEAL_PRICE, DEAL_VOLUME };
enum ENUM_DEAL_PROPERTY_STRING { DEAL_SYMBOL, DEAL_COMMENT };
enum ENUM_DEAL_ENTRY { DEAL_ENTRY_IN = 0, DEAL_ENTRY_OUT = 1, DEAL_ENTRY_INOUT = 2, DEAL_ENTRY_OUT_BY = 3 };

#define SYMBOL_EXPIRATION_GTC 1
#define SYMBOL_EXPIRATION_DAY 2
#define TRADE_RETCODE_DONE 10009
#define TRADE_RETCODE_PLACED 10008
#define TRADE_RETCODE_INVALID_PRICE 10015
#define TRADE_RETCODE_INVALID_STOPS 10016
#define TRADE_RETCODE_INVALID_VOLUME 10014
#define TRADE_RETCODE_INVALID_FILL 10030
#define INIT_SUCCEEDED 0
#define INIT_FAILED 1
#define INIT_PARAMETERS_INCORRECT 32767
#define REASON_PROGRAM 0
#define REASON_REMOVE 1
#define REASON_RECOMPILE 2
#define REASON_CHARTCHANGE 3
#define REASON_CHARTCLOSE 4
#define REASON_PARAMETERS 5
#define REASON_ACCOUNT 6
#define REASON_TEMPLATE 7
#define REASON_INITFAILED 8
#define REASON_CLOSE 9
#define FILE_READ 1
#define FILE_WRITE 2
#define FILE_CSV 8
#define FILE_ANSI 32
#define FILE_SHARE_READ 128
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#define INVALID_HANDLE (-1)
#define TIME_DATE 1
#define TIME_MINUTES 2
#define TIME_SECONDS 4

const color clrDeepSkyBlue = MQL_RGB(0, 191, 255);
const color clrOrange = MQL_RGB(255, 165, 0);
const color clrGray = MQL_RGB(128, 128, 128);
const color clrCrimson = MQL_RGB(220, 20, 60);
const color clrLimeGreen = MQL_RGB(50, 205, 50);
const color clrSilver = MQL_RGB(192, 192, 192);
const color clrWhite = MQL_RGB(255, 255, 255);
const color clrTomato = MQL_RGB(255, 99, 71);
const color clrRed = MQL_RGB(255, 0, 0);
const color clrDodgerBlue = MQL_RGB(30, 144, 255);
const color clrOrangeRed = MQL_RGB(255, 69, 0);
const color clrGoldenrod = MQL_RGB(218, 165, 32);
const color clrSlateGray = MQL_RGB(112, 128, 144);
const color clrMediumPurple = MQL_RGB(147, 112, 219);
const color clrGold = MQL_RGB(255, 215, 0);

struct MqlRates {
  datetime time;
  double open, high, low, close;
  long tick_volume;
  int spread;
  long real_volume;
};
struct MqlTick {
  datetime time;
  double bid, ask, last;
  ulong volume;
  long time_msc;
  uint flags;
  double volume_real;
};

// ------------------------------------------------------------------ simulateur
struct SimBar { datetime t; double o, h, l, c; };
struct SimOrder { ulong ticket; int type; double price, sl, tp, vol; long magic; std::string comment, symbol; };
struct SimPos { ulong ticket; int type; double open, sl, tp, vol; long magic; std::string comment, symbol; datetime t; };
struct SimDeal { ulong ticket; int entry; int type; double price, vol, profit; long magic; std::string symbol, comment; datetime t; int reason; };
struct SimObj { int type; std::vector<datetime> t; std::vector<double> p; std::map<int, long> iprops; std::map<int, std::string> sprops; };

struct Sim {
  std::vector<SimBar> bars;
  int cur = -1;  // bougie en formation
  double bid = 0, ask = 0, spread = 0;
  datetime now = 0;
  double tick = 0.25, point = 0.01, pointValue = 20.0;  // valeur monétaire d'1.0 de prix pour 1 lot
  double balance = 100000.0;
  double volMin = 0.01, volMax = 100.0, volStep = 0.01;
  long stopsLevel = 0;
  int visual = 1;
  std::vector<SimOrder> orders;
  std::vector<SimPos> positions;
  std::vector<SimDeal> deals;
  std::vector<SimDeal> histSel;
  std::map<std::string, SimObj> objects;
  size_t maxObjects = 0;
  ulong nextTicket = 1000;
  int selOrder = -1, selPos = -1;
  int alerts = 0, pushes = 0, orderErrors = 0;
  std::vector<std::string> log;
  std::map<std::string, int> placed;  // ordres envoyés par commentaire

  double profitOf(int posType, double open, double close, double vol) const {
    return (posType == 0 ? (close - open) : (open - close)) * vol * pointValue;
  }
  void closePos(size_t i, double px, int reason) {
    SimPos p = positions[i];
    double pr = profitOf(p.type, p.open, px, p.vol);
    balance += pr;
    deals.push_back({nextTicket++, DEAL_ENTRY_OUT, p.type == 0 ? 1 : 0, px, p.vol, pr, p.magic, p.symbol, p.comment, now, reason});
    positions.erase(positions.begin() + i);
  }
  void openPos(int type, double px, double sl, double tp, double vol, long magic, const std::string &cmt, const std::string &sym) {
    SimPos p{nextTicket++, type, px, sl, tp, vol, magic, cmt, sym, now};
    positions.push_back(p);
    deals.push_back({nextTicket++, DEAL_ENTRY_IN, type, px, vol, 0.0, magic, sym, cmt, now, 0});
  }
  // appelé à chaque tick AVANT OnTick (comme le testeur) : ordres en attente puis SL/TP
  void processFills() {
    for (size_t i = 0; i < orders.size();) {
      SimOrder &o = orders[i];
      bool fill = (o.type == ORDER_TYPE_SELL_LIMIT && bid >= o.price) || (o.type == ORDER_TYPE_BUY_LIMIT && ask <= o.price);
      if (fill) {
        SimOrder c = o;
        orders.erase(orders.begin() + i);
        openPos(c.type == ORDER_TYPE_BUY_LIMIT ? 0 : 1, c.price, c.sl, c.tp, c.vol, c.magic, c.comment, c.symbol);
      } else
        i++;
    }
    for (size_t i = 0; i < positions.size();) {
      SimPos &p = positions[i];
      if (p.type == 0) {
        if (p.sl > 0 && bid <= p.sl) { closePos(i, p.sl, 2); continue; }
        if (p.tp > 0 && bid >= p.tp) { closePos(i, p.tp, 1); continue; }
      } else {
        if (p.sl > 0 && ask >= p.sl) { closePos(i, p.sl, 2); continue; }
        if (p.tp > 0 && ask <= p.tp) { closePos(i, p.tp, 1); continue; }
      }
      i++;
    }
  }
  void setTick(datetime t, double price) {
    now = t;
    bid = price;
    ask = price + spread;
    processFills();
  }
};
extern Sim g_sim;

// ------------------------------------------------------------------ variables prédéfinies
extern string _Symbol;
extern double _Point;
extern int _Digits;
extern ENUM_TIMEFRAMES _Period;

// ------------------------------------------------------------------ infos
inline int PeriodSeconds(ENUM_TIMEFRAMES tf = PERIOD_CURRENT) {
  if (tf == PERIOD_CURRENT) tf = _Period;
  if (tf == PERIOD_H1) return 3600;
  if (tf == PERIOD_H4) return 4 * 3600;
  if (tf == PERIOD_D1) return 86400;
  return (int)tf * 60;
}
inline double SymbolInfoDouble(const string &, ENUM_SYMBOL_INFO_DOUBLE p) {
  switch (p) {
    case SYMBOL_BID: return g_sim.bid;
    case SYMBOL_ASK: return g_sim.ask;
    case SYMBOL_POINT: return g_sim.point;
    case SYMBOL_TRADE_TICK_SIZE: return g_sim.tick;
    case SYMBOL_TRADE_TICK_VALUE: return g_sim.tick * g_sim.pointValue;
    case SYMBOL_VOLUME_MIN: return g_sim.volMin;
    case SYMBOL_VOLUME_MAX: return g_sim.volMax;
    case SYMBOL_VOLUME_STEP: return g_sim.volStep;
  }
  return 0;
}
inline long SymbolInfoInteger(const string &, ENUM_SYMBOL_INFO_INTEGER p) {
  switch (p) {
    case SYMBOL_DIGITS: return _Digits;
    case SYMBOL_TRADE_STOPS_LEVEL: return g_sim.stopsLevel;
    case SYMBOL_TRADE_FREEZE_LEVEL: return 0;
    case SYMBOL_EXPIRATION_MODE: return SYMBOL_EXPIRATION_GTC | SYMBOL_EXPIRATION_DAY;
    case SYMBOL_FILLING_MODE: return 1;
  }
  return 0;
}
inline bool SymbolInfoTick(const string &, MqlTick &t) {
  memset(&t, 0, sizeof(t));
  t.time = g_sim.now;
  t.bid = g_sim.bid;
  t.ask = g_sim.ask;
  return true;
}
inline double AccountInfoDouble(ENUM_ACCOUNT_INFO_DOUBLE p) {
  if (p == ACCOUNT_MARGIN_FREE) return 1e9;
  return g_sim.balance;
}
inline string AccountInfoString(ENUM_ACCOUNT_INFO_STRING) { return "USD"; }
inline int MQLInfoInteger(ENUM_MQL_INFO_INTEGER p) {
  if (p == MQL_TESTER) return 1;
  if (p == MQL_VISUAL_MODE) return g_sim.visual;
  if (p == MQL_TRADE_ALLOWED) return 1;
  return 0;
}
inline int TerminalInfoInteger(ENUM_TERMINAL_INFO_INTEGER) { return 1; }
inline datetime TimeCurrent() { return g_sim.now; }
inline datetime TimeTradeServer() { return g_sim.now; }
inline datetime TimeGMT() { return g_sim.now - 3 * 3600; }

// ------------------------------------------------------------------ séries
inline int Bars(const string &, ENUM_TIMEFRAMES) { return g_sim.cur + 1; }
inline datetime iTime(const string &, ENUM_TIMEFRAMES, int shift) {
  int i = g_sim.cur - shift;
  return (i >= 0 && i < (int)g_sim.bars.size()) ? g_sim.bars[i].t : 0;
}
inline int iBarShift(const string &, ENUM_TIMEFRAMES, datetime t, bool exact = false) {
  auto &b = g_sim.bars;
  int lo = 0, hi = g_sim.cur;
  int found = -1;
  while (lo <= hi) {
    int mid = (lo + hi) / 2;
    if (b[mid].t <= t) { found = mid; lo = mid + 1; } else hi = mid - 1;
  }
  if (found < 0) return -1;
  if (exact && b[found].t != t) return -1;
  return g_sim.cur - found;
}
inline int CopyRates(const string &, ENUM_TIMEFRAMES, int start_pos, int count, MqlArray<MqlRates> &arr) {
  int last = g_sim.cur - start_pos;
  if (last < 0 || count <= 0) return -1;
  int first = std::max(0, last - count + 1);
  arr.v.clear();
  for (int i = first; i <= last; i++) {
    MqlRates r;
    memset(&r, 0, sizeof(r));
    r.time = g_sim.bars[i].t;
    r.open = g_sim.bars[i].o;
    r.high = g_sim.bars[i].h;
    r.low = g_sim.bars[i].l;
    r.close = g_sim.bars[i].c;
    arr.v.push_back(r);
  }
  return (int)arr.v.size();
}

// ------------------------------------------------------------------ événements / notifications
inline bool EventSetTimer(int) { return true; }
inline void EventKillTimer() {}
template <class... A>
void Alert(const A &...) { g_sim.alerts++; }
inline bool SendNotification(const string &) { g_sim.pushes++; return true; }
inline bool PlaySound(const string &) { return true; }

// ------------------------------------------------------------------ objets graphiques
inline void sim_track() { g_sim.maxObjects = std::max(g_sim.maxObjects, g_sim.objects.size()); }
inline bool ObjectCreate(long, const string &name, ENUM_OBJECT type, int, datetime t1, double p1) {
  if (g_sim.objects.count(name)) return false;
  SimObj o;
  o.type = type;
  o.t = {t1};
  o.p = {p1};
  g_sim.objects[name] = o;
  sim_track();
  return true;
}
inline bool ObjectCreate(long, const string &name, ENUM_OBJECT type, int, datetime t1, double p1, datetime t2, double p2) {
  if (g_sim.objects.count(name)) return false;
  SimObj o;
  o.type = type;
  o.t = {t1, t2};
  o.p = {p1, p2};
  g_sim.objects[name] = o;
  sim_track();
  return true;
}
inline int ObjectFind(long, const string &name) { return g_sim.objects.count(name) ? 0 : -1; }
inline bool ObjectDelete(long, const string &name) { return g_sim.objects.erase(name) > 0; }
inline int ObjectsDeleteAll(long, const string &prefix, int = -1, int = -1) {
  int n = 0;
  for (auto it = g_sim.objects.begin(); it != g_sim.objects.end();) {
    if (it->first.compare(0, prefix.size(), prefix) == 0) {
      it = g_sim.objects.erase(it);
      n++;
    } else
      ++it;
  }
  return n;
}
inline bool ObjectMove(long, const string &name, int idx, datetime t, double p) {
  auto it = g_sim.objects.find(name);
  if (it == g_sim.objects.end() || idx < 0 || idx >= (int)it->second.t.size()) return false;
  it->second.t[idx] = t;
  it->second.p[idx] = p;
  return true;
}
inline bool ObjectSetInteger(long, const string &name, ENUM_OBJECT_PROPERTY_INTEGER prop, long v) {
  auto it = g_sim.objects.find(name);
  if (it == g_sim.objects.end()) return false;
  it->second.iprops[prop] = v;
  return true;
}
inline bool ObjectSetString(long, const string &name, ENUM_OBJECT_PROPERTY_STRING prop, const string &v) {
  auto it = g_sim.objects.find(name);
  if (it == g_sim.objects.end()) return false;
  it->second.sprops[prop] = v;
  return true;
}
inline double ObjectGetDouble(long, const string &name, ENUM_OBJECT_PROPERTY_DOUBLE, int idx = 0) {
  auto it = g_sim.objects.find(name);
  if (it == g_sim.objects.end() || idx < 0 || idx >= (int)it->second.p.size()) return 0.0;
  return it->second.p[idx];
}
inline void ChartRedraw(long = 0) {}

// ------------------------------------------------------------------ variables globales du terminal
inline std::map<std::string, double> &sim_gv() {
  static std::map<std::string, double> g;
  return g;
}
inline datetime GlobalVariableSet(const string &name, double v) {
  sim_gv()[name] = v;
  return g_sim.now;
}
inline double GlobalVariableGet(const string &name) {
  auto it = sim_gv().find(name);
  return it == sim_gv().end() ? 0.0 : it->second;
}
inline bool GlobalVariableCheck(const string &name) { return sim_gv().count(name) > 0; }
inline bool GlobalVariableDel(const string &name) { return sim_gv().erase(name) > 0; }

// ------------------------------------------------------------------ ordres / positions / historique
inline int OrdersTotal() { return (int)g_sim.orders.size(); }
inline ulong OrderGetTicket(int i) {
  if (i < 0 || i >= (int)g_sim.orders.size()) { g_sim.selOrder = -1; return 0; }
  g_sim.selOrder = i;
  return g_sim.orders[i].ticket;
}
inline bool OrderSelect(ulong ticket) {
  for (size_t i = 0; i < g_sim.orders.size(); i++)
    if (g_sim.orders[i].ticket == ticket) { g_sim.selOrder = (int)i; return true; }
  g_sim.selOrder = -1;
  return false;
}
inline long OrderGetInteger(ENUM_ORDER_PROPERTY_INTEGER p) {
  if (g_sim.selOrder < 0) return 0;
  const SimOrder &o = g_sim.orders[g_sim.selOrder];
  return p == ORDER_MAGIC ? o.magic : o.type;
}
inline double OrderGetDouble(ENUM_ORDER_PROPERTY_DOUBLE p) {
  if (g_sim.selOrder < 0) return 0;
  const SimOrder &o = g_sim.orders[g_sim.selOrder];
  switch (p) {
    case ORDER_PRICE_OPEN: return o.price;
    case ORDER_SL: return o.sl;
    case ORDER_TP: return o.tp;
    case ORDER_VOLUME_CURRENT: return o.vol;
  }
  return 0;
}
inline string OrderGetString(ENUM_ORDER_PROPERTY_STRING p) {
  if (g_sim.selOrder < 0) return "";
  const SimOrder &o = g_sim.orders[g_sim.selOrder];
  return p == ORDER_SYMBOL ? o.symbol : o.comment;
}
inline int PositionsTotal() { return (int)g_sim.positions.size(); }
inline ulong PositionGetTicket(int i) {
  if (i < 0 || i >= (int)g_sim.positions.size()) { g_sim.selPos = -1; return 0; }
  g_sim.selPos = i;
  return g_sim.positions[i].ticket;
}
inline long PositionGetInteger(ENUM_POSITION_PROPERTY_INTEGER p) {
  if (g_sim.selPos < 0) return 0;
  const SimPos &o = g_sim.positions[g_sim.selPos];
  if (p == POSITION_MAGIC) return o.magic;
  if (p == POSITION_TYPE) return o.type;
  return o.t;
}
inline double PositionGetDouble(ENUM_POSITION_PROPERTY_DOUBLE p) {
  if (g_sim.selPos < 0) return 0;
  const SimPos &o = g_sim.positions[g_sim.selPos];
  switch (p) {
    case POSITION_PRICE_OPEN: return o.open;
    case POSITION_SL: return o.sl;
    case POSITION_TP: return o.tp;
    case POSITION_VOLUME: return o.vol;
    case POSITION_PROFIT: return g_sim.profitOf(o.type, o.open, o.type == 0 ? g_sim.bid : g_sim.ask, o.vol);
  }
  return 0;
}
inline string PositionGetString(ENUM_POSITION_PROPERTY_STRING p) {
  if (g_sim.selPos < 0) return "";
  const SimPos &o = g_sim.positions[g_sim.selPos];
  return p == POSITION_SYMBOL ? o.symbol : o.comment;
}
inline bool HistorySelect(datetime from, datetime to) {
  g_sim.histSel.clear();
  for (auto &d : g_sim.deals)
    if (d.t >= from && d.t <= to) g_sim.histSel.push_back(d);
  return true;
}
inline int HistoryDealsTotal() { return (int)g_sim.histSel.size(); }
inline ulong HistoryDealGetTicket(int i) {
  return (i >= 0 && i < (int)g_sim.histSel.size()) ? g_sim.histSel[i].ticket : 0;
}
inline const SimDeal *sim_deal(ulong t) {
  for (auto &d : g_sim.histSel)
    if (d.ticket == t) return &d;
  return nullptr;
}
inline long HistoryDealGetInteger(ulong t, ENUM_DEAL_PROPERTY_INTEGER p) {
  const SimDeal *d = sim_deal(t);
  if (!d) return 0;
  switch (p) {
    case DEAL_MAGIC: return d->magic;
    case DEAL_ENTRY: return d->entry;
    case DEAL_TYPE: return d->type;
    case DEAL_TIME: return d->t;
  }
  return 0;
}
inline double HistoryDealGetDouble(ulong t, ENUM_DEAL_PROPERTY_DOUBLE p) {
  const SimDeal *d = sim_deal(t);
  if (!d) return 0;
  switch (p) {
    case DEAL_PROFIT: return d->profit;
    case DEAL_PRICE: return d->price;
    case DEAL_VOLUME: return d->vol;
    default: return 0;
  }
}
inline string HistoryDealGetString(ulong t, ENUM_DEAL_PROPERTY_STRING p) {
  const SimDeal *d = sim_deal(t);
  if (!d) return "";
  return p == DEAL_SYMBOL ? d->symbol : d->comment;
}
inline bool OrderCalcProfit(ENUM_ORDER_TYPE action, const string &, double vol, double open, double close, double &profit) {
  profit = g_sim.profitOf(action == ORDER_TYPE_BUY ? 0 : 1, open, close, vol);
  return true;
}
inline bool OrderCalcMargin(ENUM_ORDER_TYPE, const string &, double vol, double, double &margin) {
  margin = vol * 1000.0;
  return true;
}

// ------------------------------------------------------------------ fichiers
inline std::map<int, std::ofstream *> &sim_files() {
  static std::map<int, std::ofstream *> f;
  return f;
}
inline std::map<int, char> &sim_delim() {
  static std::map<int, char> d;
  return d;
}
inline int FileOpen(const string &name, int flags, short delim = '\t', uint = 0) {
  static int next = 1;
  auto *o = new std::ofstream("build/" + name, (flags & FILE_READ) ? std::ios::app : std::ios::trunc);
  if (!o->is_open()) { delete o; return INVALID_HANDLE; }
  sim_files()[next] = o;
  sim_delim()[next] = (char)delim;
  return next++;
}
inline void sim_write(std::ostream &, char, bool) {}
template <class T, class... R>
void sim_write(std::ostream &o, char d, bool first, const T &v, const R &...r) {
  if (!first) o << d;
  o << v;
  sim_write(o, d, false, r...);
}
template <class... A>
uint FileWrite(int h, const A &...a) {
  auto it = sim_files().find(h);
  if (it == sim_files().end()) return 0;
  sim_write(*it->second, sim_delim()[h], true, a...);
  *it->second << "\n";
  return 1;
}
inline bool FileSeek(int h, long, int) { return sim_files().count(h) > 0; }
inline ulong FileTell(int h) {
  auto it = sim_files().find(h);
  if (it == sim_files().end()) return 0;
  return (ulong)it->second->tellp();
}
inline void FileFlush(int h) {
  auto it = sim_files().find(h);
  if (it != sim_files().end()) it->second->flush();
}
inline void FileClose(int h) {
  auto it = sim_files().find(h);
  if (it == sim_files().end()) return;
  it->second->close();
  delete it->second;
  sim_files().erase(it);
}

// ------------------------------------------------------------------ CTrade (sous-ensemble de Trade\Trade.mqh)
class CTrade {
 public:
  ulong m_magic = 0;
  uint m_ret = 0;
  ulong m_order = 0;
  ulong m_deal = 0;
  ENUM_ORDER_TYPE_FILLING m_fill = ORDER_FILLING_FOK;

  void SetExpertMagicNumber(const ulong magic) { m_magic = magic; }
  void SetDeviationInPoints(const ulong) {}
  bool SetTypeFillingBySymbol(const string &) { m_fill = ORDER_FILLING_IOC; return true; }
  void SetTypeFilling(const ENUM_ORDER_TYPE_FILLING f) { m_fill = f; }
  void SetAsyncMode(const bool) {}
  void LogLevel(const ENUM_LOG_LEVELS) {}
  uint ResultRetcode() const { return m_ret; }
  string ResultRetcodeDescription() const { return "retcode " + std::to_string(m_ret); }
  ulong ResultOrder() const { return m_order; }
  ulong ResultDeal() const { return m_deal; }

  bool fail(uint code) {
    m_ret = code;
    m_order = 0;
    g_sim.orderErrors++;
    return false;
  }
  bool checkVol(double v) {
    double k = v / g_sim.volStep;
    return v >= g_sim.volMin - 1e-12 && v <= g_sim.volMax + 1e-12 && std::fabs(k - std::round(k)) < 1e-6;
  }
  bool onGrid(double p) {
    double k = p / g_sim.tick;
    return std::fabs(k - std::round(k)) < 1e-6;
  }
  bool market(int type, double volume, double sl, double tp, const string &cmt) {
    g_sim.placed[cmt]++;
    if (!checkVol(volume)) return fail(TRADE_RETCODE_INVALID_VOLUME);
    double px = type == 0 ? g_sim.ask : g_sim.bid;
    if (type == 0 && ((sl > 0 && sl >= g_sim.bid) || (tp > 0 && tp <= g_sim.bid))) return fail(TRADE_RETCODE_INVALID_STOPS);
    if (type == 1 && ((sl > 0 && sl <= g_sim.ask) || (tp > 0 && tp >= g_sim.ask))) return fail(TRADE_RETCODE_INVALID_STOPS);
    if ((sl > 0 && !onGrid(sl)) || (tp > 0 && !onGrid(tp))) return fail(TRADE_RETCODE_INVALID_PRICE);
    g_sim.openPos(type, px, sl, tp, volume, (long)m_magic, cmt, _Symbol);
    m_ret = TRADE_RETCODE_DONE;
    m_deal = g_sim.nextTicket - 1;
    return true;
  }
  bool limit(int type, double volume, double price, double sl, double tp, const string &cmt) {
    g_sim.placed[cmt]++;
    if (!checkVol(volume)) return fail(TRADE_RETCODE_INVALID_VOLUME);
    if (!onGrid(price) || (sl > 0 && !onGrid(sl)) || (tp > 0 && !onGrid(tp))) return fail(TRADE_RETCODE_INVALID_PRICE);
    if (type == ORDER_TYPE_SELL_LIMIT) {
      if (price <= g_sim.bid) return fail(TRADE_RETCODE_INVALID_PRICE);
      if ((sl > 0 && sl <= price) || (tp > 0 && tp >= price)) return fail(TRADE_RETCODE_INVALID_STOPS);
    } else {
      if (price >= g_sim.ask) return fail(TRADE_RETCODE_INVALID_PRICE);
      if ((sl > 0 && sl >= price) || (tp > 0 && tp <= price)) return fail(TRADE_RETCODE_INVALID_STOPS);
    }
    SimOrder o{g_sim.nextTicket++, type, price, sl, tp, volume, (long)m_magic, cmt, _Symbol};
    g_sim.orders.push_back(o);
    m_ret = TRADE_RETCODE_DONE;
    m_order = o.ticket;
    return true;
  }
  bool Buy(const double volume, const string &symbol = "", double price = 0.0, const double sl = 0.0, const double tp = 0.0,
           const string &comment = "") {
    (void)symbol; (void)price;
    return market(0, volume, sl, tp, comment);
  }
  bool Sell(const double volume, const string &symbol = "", double price = 0.0, const double sl = 0.0, const double tp = 0.0,
            const string &comment = "") {
    (void)symbol; (void)price;
    return market(1, volume, sl, tp, comment);
  }
  bool BuyLimit(const double volume, const double price, const string &symbol = "", const double sl = 0.0, const double tp = 0.0,
                const ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC, const datetime expiration = 0, const string &comment = "") {
    (void)symbol; (void)type_time; (void)expiration;
    return limit(ORDER_TYPE_BUY_LIMIT, volume, price, sl, tp, comment);
  }
  bool SellLimit(const double volume, const double price, const string &symbol = "", const double sl = 0.0, const double tp = 0.0,
                 const ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC, const datetime expiration = 0, const string &comment = "") {
    (void)symbol; (void)type_time; (void)expiration;
    return limit(ORDER_TYPE_SELL_LIMIT, volume, price, sl, tp, comment);
  }
  bool OrderDelete(const ulong ticket) {
    for (size_t i = 0; i < g_sim.orders.size(); i++)
      if (g_sim.orders[i].ticket == ticket) {
        g_sim.orders.erase(g_sim.orders.begin() + i);
        m_ret = TRADE_RETCODE_DONE;
        return true;
      }
    return fail(10013);
  }
  bool PositionClose(const ulong ticket, const ulong deviation = ULONG_MAX) {
    (void)deviation;
    for (size_t i = 0; i < g_sim.positions.size(); i++)
      if (g_sim.positions[i].ticket == ticket) {
        double px = g_sim.positions[i].type == 0 ? g_sim.bid : g_sim.ask;
        g_sim.closePos(i, px, 3);
        m_ret = TRADE_RETCODE_DONE;
        return true;
      }
    return fail(10013);
  }
  bool PositionModify(const ulong ticket, const double sl, const double tp) {
    for (auto &p : g_sim.positions)
      if (p.ticket == ticket) {
        if (p.type == 0 && sl >= g_sim.bid) return fail(TRADE_RETCODE_INVALID_STOPS);
        if (p.type == 1 && sl <= g_sim.ask) return fail(TRADE_RETCODE_INVALID_STOPS);
        p.sl = sl;
        p.tp = tp;
        m_ret = TRADE_RETCODE_DONE;
        return true;
      }
    return fail(10013);
  }
};

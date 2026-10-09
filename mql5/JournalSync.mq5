//+------------------------------------------------------------------+
//| JournalSync.mq5 — Alpha Edge / Liberté Financière                  |
//| Envoie l'historique du compte (deals, solde, equity) au journal    |
//| du SaaS. LECTURE SEULE : cet EA n'ouvre, ne modifie et ne ferme     |
//| aucune position. Aucune DLL.                                       |
//|                                                                    |
//| Installation :                                                     |
//|  1. Outils > Options > Expert Advisors : cocher « Autoriser         |
//|     WebRequest pour les URL listées » et ajouter l'adresse du site  |
//|     (ex. https://votre-domaine.com).                               |
//|  2. Glisser l'EA sur n'importe quel graphique du compte à suivre.   |
//|  3. Coller l'URL et le jeton affichés dans l'espace membre.         |
//+------------------------------------------------------------------+
#property copyright "Liberté Financière"
#property version   "1.00"
#property description "Synchronise l'historique MT5 avec le journal Alpha Edge (lecture seule)."

input string InpUrl         = "https://votre-domaine.com/api/ingest/mt5"; // URL de synchronisation
input string InpToken       = "";                                        // Jeton personnel (espace membre)
input int    InpIntervalSec = 120;                                       // Intervalle entre deux envois (secondes, 60 minimum)
input int    InpDaysBack    = 90;                                        // Historique envoyé au premier lancement (jours)

string g_gv_name;
datetime g_last_ok = 0;

//+------------------------------------------------------------------+
string JsonEscape(const string s)
  {
   string out = "";
   int n = StringLen(s);
   for(int i = 0; i < n; i++)
     {
      ushort c = StringGetCharacter(s, i);
      if(c == '"')       out += "\\\"";
      else if(c == '\\') out += "\\\\";
      else if(c == '\n') out += "\\n";
      else if(c == '\r') out += "\\r";
      else if(c == '\t') out += " ";
      else if(c < 32)    out += " ";
      else               out += ShortToString(c);
     }
   return out;
  }

string Num(const double v) { return DoubleToString(v, 8); }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(StringLen(InpToken) < 10)
     {
      Print("JournalSync : collez le jeton personnel affiché dans l'espace membre.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(StringFind(InpUrl, "https://") != 0 && StringFind(InpUrl, "http://127.0.0.1") != 0 && StringFind(InpUrl, "http://localhost") != 0)
     {
      Print("JournalSync : l'URL doit commencer par https:// (ou http://127.0.0.1 en local).");
      return(INIT_PARAMETERS_INCORRECT);
     }
   g_gv_name = "JournalSync_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   if(GlobalVariableCheck(g_gv_name))
      g_last_ok = (datetime)GlobalVariableGet(g_gv_name);
   EventSetTimer((int)MathMax(60, InpIntervalSec));
   Sync();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason) { EventKillTimer(); }
void OnTimer()                  { Sync(); }
void OnTick()                   { }

//+------------------------------------------------------------------+
bool InList(const long &list[], const long v)
  {
   for(int i = 0; i < ArraySize(list); i++)
      if(list[i] == v) return(true);
   return(false);
  }

void Sync()
  {
   datetime now   = TimeCurrent();
   datetime from  = now - (datetime)(InpDaysBack * 86400);
   datetime since = (g_last_ok > 0) ? g_last_ok - 2 * 86400 : from;
   if(!HistorySelect(from, now + 86400))
     {
      Print("JournalSync : HistorySelect a échoué, erreur ", GetLastError());
      return;
     }
   int total = HistoryDealsTotal();

   // 1. Positions touchées depuis le dernier envoi réussi.
   long positions[];
   for(int i = 0; i < total; i++)
     {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      if((datetime)HistoryDealGetInteger(t, DEAL_TIME) < since) continue;
      long pid = HistoryDealGetInteger(t, DEAL_POSITION_ID);
      if(pid > 0 && !InList(positions, pid))
        {
         int k = ArraySize(positions);
         ArrayResize(positions, k + 1);
         positions[k] = pid;
        }
     }

   // 2. Tous les deals de ces positions (y compris les entrées plus anciennes).
   string deals = "";
   string meta  = "";
   int nd = 0;
   for(int i = 0; i < total && nd < 5000; i++)
     {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      long pid = HistoryDealGetInteger(t, DEAL_POSITION_ID);
      if(!InList(positions, pid)) continue;
      long type = HistoryDealGetInteger(t, DEAL_TYPE);
      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) continue;
      long entry = HistoryDealGetInteger(t, DEAL_ENTRY);
      if(nd > 0) deals += ",";
      deals += "{\"ticket\":" + IntegerToString((long)t)
             + ",\"order\":" + IntegerToString(HistoryDealGetInteger(t, DEAL_ORDER))
             + ",\"position_id\":" + IntegerToString(pid)
             + ",\"time\":" + IntegerToString(HistoryDealGetInteger(t, DEAL_TIME))
             + ",\"time_msc\":" + IntegerToString(HistoryDealGetInteger(t, DEAL_TIME_MSC))
             + ",\"type\":" + IntegerToString(type)
             + ",\"entry\":" + IntegerToString(entry)
             + ",\"symbol\":\"" + JsonEscape(HistoryDealGetString(t, DEAL_SYMBOL)) + "\""
             + ",\"volume\":" + Num(HistoryDealGetDouble(t, DEAL_VOLUME))
             + ",\"price\":" + Num(HistoryDealGetDouble(t, DEAL_PRICE))
             + ",\"commission\":" + Num(HistoryDealGetDouble(t, DEAL_COMMISSION))
             + ",\"swap\":" + Num(HistoryDealGetDouble(t, DEAL_SWAP))
             + ",\"profit\":" + Num(HistoryDealGetDouble(t, DEAL_PROFIT))
             + ",\"fee\":" + Num(HistoryDealGetDouble(t, DEAL_FEE))
             + ",\"magic\":" + IntegerToString(HistoryDealGetInteger(t, DEAL_MAGIC))
             + ",\"comment\":\"" + JsonEscape(HistoryDealGetString(t, DEAL_COMMENT)) + "\"}";
      nd++;
      if(entry == DEAL_ENTRY_IN)
        {
         // Stop et objectif initiaux : ceux de l'ordre d'entrée.
         ulong order = (ulong)HistoryDealGetInteger(t, DEAL_ORDER);
         double isl = HistoryOrderGetDouble(order, ORDER_SL);
         double itp = HistoryOrderGetDouble(order, ORDER_TP);
         double csl = 0, ctp = 0;
         if(PositionSelectByTicket((ulong)pid))
           {
            csl = PositionGetDouble(POSITION_SL);
            ctp = PositionGetDouble(POSITION_TP);
           }
         if(StringLen(meta) > 0) meta += ",";
         meta += "{\"position_id\":" + IntegerToString(pid) + ",\"initial_sl\":" + Num(isl) + ",\"initial_tp\":" + Num(itp)
               + ",\"sl\":" + Num(csl) + ",\"tp\":" + Num(ctp) + "}";
        }
     }

   // Décalage de l'heure du serveur par rapport à l'UTC, arrondi au quart d'heure.
   int offset_min = (int)MathRound((double)(TimeTradeServer() - TimeGMT()) / 900.0) * 15;
   string account = "{\"login\":" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
                  + ",\"server\":\"" + JsonEscape(AccountInfoString(ACCOUNT_SERVER)) + "\""
                  + ",\"company\":\"" + JsonEscape(AccountInfoString(ACCOUNT_COMPANY)) + "\""
                  + ",\"currency\":\"" + JsonEscape(AccountInfoString(ACCOUNT_CURRENCY)) + "\""
                  + ",\"balance\":" + Num(AccountInfoDouble(ACCOUNT_BALANCE))
                  + ",\"equity\":" + Num(AccountInfoDouble(ACCOUNT_EQUITY))
                  + ",\"margin\":" + Num(AccountInfoDouble(ACCOUNT_MARGIN))
                  + ",\"server_utc_offset_min\":" + IntegerToString(offset_min)
                  + ",\"trade_mode\":" + IntegerToString(AccountInfoInteger(ACCOUNT_TRADE_MODE)) + "}";
   string body = "{\"version\":\"1\",\"account\":" + account + ",\"deals\":[" + deals + "],\"positions\":[" + meta + "]}";

   char data[];
   char result[];
   string result_headers;
   int len = StringToCharArray(body, data, 0, WHOLE_ARRAY, CP_UTF8);
   if(len > 0) ArrayResize(data, len - 1); // sans le zéro final
   string headers = "Content-Type: application/json\r\nAuthorization: Bearer " + InpToken + "\r\n";
   ResetLastError();
   int code = WebRequest("POST", InpUrl, headers, 15000, data, result, result_headers);
   if(code == -1)
     {
      int err = GetLastError();
      if(err == 4014)
         Print("JournalSync : ajoutez l'URL dans Outils > Options > Expert Advisors > Autoriser WebRequest.");
      else
         Print("JournalSync : envoi impossible, erreur ", err);
      return;
     }
   if(code == 200)
     {
      g_last_ok = now;
      GlobalVariableSet(g_gv_name, (double)now);
      PrintFormat("JournalSync : %d deals envoyés.", nd);
     }
   else
      PrintFormat("JournalSync : le serveur a répondu %d : %s", code, CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8));
  }
//+------------------------------------------------------------------+

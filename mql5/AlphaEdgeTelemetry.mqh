//+------------------------------------------------------------------+
//| AlphaEdgeTelemetry.mqh — état d'un EA vers le SaaS (lecture seule)|
//| À inclure dans un EA : #include <AlphaEdgeTelemetry.mqh>           |
//| puis appeler AE_Telemetry(...) dans OnTimer (toutes les 5 min).   |
//| Utilise le même jeton et la même autorisation WebRequest que      |
//| JournalSync ; URL : https://votre-domaine.com/api/ingest/telemetry|
//+------------------------------------------------------------------+

string AE_Escape(const string s)
  {
   string out = s;
   StringReplace(out, "\\", "\\\\");
   StringReplace(out, "\"", "\\\"");
   StringReplace(out, "\n", " ");
   StringReplace(out, "\r", " ");
   return out;
  }

// status : "running", "stopped" ou "error"
bool AE_Telemetry(const string url, const string token, const string ea, const long magic, const string status, const string last_error = "")
  {
   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   string body = "{\"ea\":\"" + AE_Escape(ea) + "\",\"magic\":" + IntegerToString(magic) + ",\"status\":\"" + status + "\""
               + ",\"spread_points\":" + DoubleToString(spread, 1) + ",\"last_error\":\"" + AE_Escape(last_error) + "\""
               + ",\"extra\":{\"symbol\":\"" + AE_Escape(_Symbol) + "\",\"positions\":" + IntegerToString(PositionsTotal()) + "}}";
   char data[], result[];
   string result_headers;
   int len = StringToCharArray(body, data, 0, WHOLE_ARRAY, CP_UTF8);
   if(len > 0) ArrayResize(data, len - 1);
   string headers = "Content-Type: application/json\r\nAuthorization: Bearer " + token + "\r\n";
   int code = WebRequest("POST", url, headers, 10000, data, result, result_headers);
   return(code == 200);
  }

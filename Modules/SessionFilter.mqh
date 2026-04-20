//+------------------------------------------------------------------+
//|                                                 SessionFilter.mqh|
//|                          EA102 - XAUUSD Prop Firm EA             |
//|             Trading session filter (London / New York / etc.)    |
//+------------------------------------------------------------------+
#ifndef SESSIONFILTER_MQH
#define SESSIONFILTER_MQH
#include "Utilities.mqh"

//+------------------------------------------------------------------+
//| Session definition                                               |
//+------------------------------------------------------------------+
struct SessionDef
  {
   string name;
   int    startHour;   // UTC / server hour (24h)
   int    startMin;
   int    endHour;
   int    endMin;
   bool   enabled;
  };

//+------------------------------------------------------------------+
//| CSessionFilter class                                             |
//+------------------------------------------------------------------+
class CSessionFilter
  {
private:
   SessionDef   m_sessions[4];   // Up to 4 configurable sessions
   int          m_sessionCount;
   bool         m_closeTradesOutsideSession;
   string       m_symbol;
   int          m_magicNumber;
   bool         m_filterEnabled;

public:
   CSessionFilter() : m_sessionCount(0), m_filterEnabled(true), m_closeTradesOutsideSession(false) {}
   ~CSessionFilter() {}

   //--- Initialise sessions
   bool Init(const string symbol,
             int    magicNumber,
             bool   filterEnabled,
             bool   closeOutside,
             // London
             bool   useLondon,
             int    londonStart,   // hour
             int    londonEnd,     // hour
             // New York
             bool   useNewYork,
             int    nyStart,
             int    nyEnd,
             // Asian (optional)
             bool   useAsian,
             int    asianStart,
             int    asianEnd)
     {
      m_symbol                    = symbol;
      m_magicNumber               = magicNumber;
      m_filterEnabled             = filterEnabled;
      m_closeTradesOutsideSession = closeOutside;
      m_sessionCount              = 0;

      if(useLondon)
        {
         m_sessions[m_sessionCount].name      = "London";
         m_sessions[m_sessionCount].startHour = londonStart;
         m_sessions[m_sessionCount].startMin  = 0;
         m_sessions[m_sessionCount].endHour   = londonEnd;
         m_sessions[m_sessionCount].endMin    = 0;
         m_sessions[m_sessionCount].enabled   = true;
         m_sessionCount++;
        }

      if(useNewYork)
        {
         m_sessions[m_sessionCount].name      = "New York";
         m_sessions[m_sessionCount].startHour = nyStart;
         m_sessions[m_sessionCount].startMin  = 0;
         m_sessions[m_sessionCount].endHour   = nyEnd;
         m_sessions[m_sessionCount].endMin    = 0;
         m_sessions[m_sessionCount].enabled   = true;
         m_sessionCount++;
        }

      if(useAsian)
        {
         m_sessions[m_sessionCount].name      = "Asian";
         m_sessions[m_sessionCount].startHour = asianStart;
         m_sessions[m_sessionCount].startMin  = 0;
         m_sessions[m_sessionCount].endHour   = asianEnd;
         m_sessions[m_sessionCount].endMin    = 0;
         m_sessions[m_sessionCount].enabled   = true;
         m_sessionCount++;
        }

      if(!m_filterEnabled)
         LogInfo("SessionFilter", "Session filter DISABLED — trading all hours");
      else
         LogInfo("SessionFilter", StringFormat("Session filter ON | %d sessions", m_sessionCount));

      return true;
     }

   //--- Check if current server time is in any active session
   bool IsInSession() const
     {
      if(!m_filterEnabled) return true;
      if(m_sessionCount == 0) return true;   // No sessions configured = always allow

      MqlDateTime mdt;
      TimeToStruct(TimeCurrent(), mdt);
      int nowMinutes = mdt.hour * 60 + mdt.min;

      for(int i = 0; i < m_sessionCount; i++)
        {
         if(!m_sessions[i].enabled) continue;

         int startMin = m_sessions[i].startHour * 60 + m_sessions[i].startMin;
         int endMin   = m_sessions[i].endHour   * 60 + m_sessions[i].endMin;

         bool inSession = false;
         if(startMin < endMin)
           {
            // Normal range (e.g., 08:00–17:00)
            inSession = (nowMinutes >= startMin && nowMinutes < endMin);
           }
         else
           {
            // Overnight range (e.g., 22:00–06:00)
            inSession = (nowMinutes >= startMin || nowMinutes < endMin);
           }

         if(inSession) return true;
        }

      return false;
     }

   //--- Return the name of active session (or "None")
   string GetActiveSessionName() const
     {
      if(!m_filterEnabled) return "All";
      if(m_sessionCount == 0) return "All";

      MqlDateTime mdt;
      TimeToStruct(TimeCurrent(), mdt);
      int nowMinutes = mdt.hour * 60 + mdt.min;

      for(int i = 0; i < m_sessionCount; i++)
        {
         if(!m_sessions[i].enabled) continue;

         int startMin = m_sessions[i].startHour * 60 + m_sessions[i].startMin;
         int endMin   = m_sessions[i].endHour   * 60 + m_sessions[i].endMin;

         bool inSession = false;
         if(startMin < endMin)
            inSession = (nowMinutes >= startMin && nowMinutes < endMin);
         else
            inSession = (nowMinutes >= startMin || nowMinutes < endMin);

         if(inSession) return m_sessions[i].name;
        }

      return "None";
     }

   //--- If configured, close all positions outside session
   void CloseTradesOutsideSession()
     {
      if(!m_closeTradesOutsideSession) return;
      if(IsInSession()) return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;

         MqlTradeRequest req = {};
         MqlTradeResult  res = {};
         req.action    = TRADE_ACTION_DEAL;
         req.symbol    = m_symbol;
         req.position  = ticket;
         req.type      = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                         ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         req.volume    = PositionGetDouble(POSITION_VOLUME);
         req.price     = (req.type == ORDER_TYPE_BUY)
                         ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                         : SymbolInfoDouble(m_symbol, SYMBOL_BID);
         req.deviation = 50;
         req.type_filling = ORDER_FILLING_IOC;

         if(!OrderSend(req, res))
            LogError("SessionFilter", StringFormat(
               "Close outside session failed ticket=%llu err=%d", ticket, GetLastError()));
         else
            LogInfo("SessionFilter", StringFormat(
               "Closed outside session ticket=%llu", ticket));
        }
     }

   bool IsFilterEnabled() const { return m_filterEnabled; }
  };
//+------------------------------------------------------------------+
#endif // SESSIONFILTER_MQH

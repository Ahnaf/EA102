//+------------------------------------------------------------------+
//|                                                SessionFilter.mqh |
//|                        EA102 v2 - XAUUSD Prop Firm EA            |
//|                      Trading session window management           |
//+------------------------------------------------------------------+
#ifndef SESSIONFILTER_MQH
#define SESSIONFILTER_MQH

#include "Utilities.mqh"
#include <Trade\Trade.mqh>

struct SessionDef
  {
   bool   enabled;
   int    startHour;   // UTC
   int    endHour;     // UTC
   string name;
  };

//+------------------------------------------------------------------+
//| CSessionFilter — controls which hours EA may trade              |
//+------------------------------------------------------------------+
class CSessionFilter
  {
private:
   bool       m_filterEnabled;
   bool       m_closeOutside;
   string     m_symbol;
   int        m_magic;
   SessionDef m_sessions[3];   // London, NY, Asian
   CTrade     m_trade;

public:
   CSessionFilter() : m_filterEnabled(true), m_closeOutside(false) {}

   bool Init(const string symbol, int magic,
             bool filterEnabled, bool closeOutside,
             bool useLondon,  int londonStart,  int londonEnd,
             bool useNewYork, int nyStart,      int nyEnd,
             bool useAsian,   int asianStart,   int asianEnd)
     {
      m_symbol        = symbol;
      m_magic         = magic;
      m_filterEnabled = filterEnabled;
      m_closeOutside  = closeOutside;
      m_trade.SetExpertMagicNumber(magic);

      m_sessions[0].enabled   = useLondon;
      m_sessions[0].startHour = londonStart;
      m_sessions[0].endHour   = londonEnd;
      m_sessions[0].name      = "London";

      m_sessions[1].enabled   = useNewYork;
      m_sessions[1].startHour = nyStart;
      m_sessions[1].endHour   = nyEnd;
      m_sessions[1].name      = "New York";

      m_sessions[2].enabled   = useAsian;
      m_sessions[2].startHour = asianStart;
      m_sessions[2].endHour   = asianEnd;
      m_sessions[2].name      = "Asian";

      LogInfo("SessionFilter", StringFormat("Init | Filter=%s London=%s NY=%s Asian=%s",
              filterEnabled?"ON":"OFF",
              useLondon?"ON":"OFF", useNewYork?"ON":"OFF", useAsian?"ON":"OFF"));
      return true;
     }

   bool IsInSession() const
     {
      if(!m_filterEnabled) return true;
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int h = dt.hour;

      for(int i = 0; i < 3; i++)
        {
         if(!m_sessions[i].enabled) continue;
         int s = m_sessions[i].startHour;
         int e = m_sessions[i].endHour;
         if(s < e) { if(h >= s && h < e) return true; }
         else       { if(h >= s || h < e) return true; } // wraps midnight
        }
      return false;
     }

   string GetActiveSessionName() const
     {
      if(!m_filterEnabled) return "Any";
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int h = dt.hour;
      for(int i = 0; i < 3; i++)
        {
         if(!m_sessions[i].enabled) continue;
         int s = m_sessions[i].startHour;
         int e = m_sessions[i].endHour;
         bool inS = (s < e) ? (h >= s && h < e) : (h >= s || h < e);
         if(inS) return m_sessions[i].name;
        }
      return "None";
     }

   void CloseTradesOutsideSession()
     {
      if(!m_closeOutside || IsInSession()) return;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
         m_trade.PositionClose(ticket);
        }
     }
  };

#endif // SESSIONFILTER_MQH

//+------------------------------------------------------------------+
//|                                                   NewsFilter.mqh |
//|                          EA102 - XAUUSD Prop Firm EA             |
//|         High-impact news detection via manually entered events   |
//+------------------------------------------------------------------+
#ifndef NEWSFILTER_MQH
#define NEWSFILTER_MQH
#include "Utilities.mqh"

//+------------------------------------------------------------------+
//| A single news event entry                                        |
//+------------------------------------------------------------------+
struct NewsEvent
  {
   datetime eventTime;       // Exact server time of news release
   string   description;     // e.g. "US NFP", "FOMC"
   int      minsBefore;      // Block X mins before event
   int      minsAfter;       // Block X mins after event
   bool     active;
  };

//+------------------------------------------------------------------+
//| CNewsFilter class                                                |
//| NOTE: MT5 does not provide a built-in live economic calendar     |
//| API. This module supports two mechanisms:                        |
//|  1. Manual events — user enters times via input arrays           |
//|  2. Auto-block by weekday/time pattern (e.g. NFP Friday 12:30)  |
//+------------------------------------------------------------------+
class CNewsFilter
  {
private:
   NewsEvent   m_events[50];     // Up to 50 manual news events
   int         m_eventCount;

   bool        m_filterEnabled;
   int         m_defaultMinsBefore;
   int         m_defaultMinsAfter;

   // Auto-block: block all trades on NFP Fridays
   bool        m_autoBlockNFP;
   int         m_nfpHour;        // Server hour of NFP (usually 12 UTC)
   int         m_nfpWindowMins;  // +/- minutes around NFP time

   // Auto-block: FOMC (Wednesday/Thursday 18:00 UTC)
   bool        m_autoBlockFOMC;
   int         m_fomcHour;

public:
   CNewsFilter() : m_eventCount(0), m_filterEnabled(true) {}
   ~CNewsFilter() {}

   //--- Initialise filter
   bool Init(bool   filterEnabled,
             int    defaultMinsBefore,
             int    defaultMinsAfter,
             bool   autoBlockNFP,
             int    nfpHour,
             int    nfpWindowMins,
             bool   autoBlockFOMC,
             int    fomcHour)
     {
      m_filterEnabled      = filterEnabled;
      m_defaultMinsBefore  = defaultMinsBefore;
      m_defaultMinsAfter   = defaultMinsAfter;
      m_autoBlockNFP       = autoBlockNFP;
      m_nfpHour            = nfpHour;
      m_nfpWindowMins      = nfpWindowMins;
      m_autoBlockFOMC      = autoBlockFOMC;
      m_fomcHour           = fomcHour;
      m_eventCount         = 0;

      LogInfo("NewsFilter", StringFormat(
         "Init | Enabled=%s | DefaultWindow=[-%dm,+%dm] | AutoNFP=%s | AutoFOMC=%s",
         filterEnabled ? "YES" : "NO",
         defaultMinsBefore, defaultMinsAfter,
         autoBlockNFP ? "YES" : "NO",
         autoBlockFOMC ? "YES" : "NO"));
      return true;
     }

   //--- Add a manual news event (called from EA inputs processing)
   bool AddEvent(datetime eventTime, const string desc, int minsBefore = -1, int minsAfter = -1)
     {
      if(m_eventCount >= 50)
        {
         LogWarn("NewsFilter", "Max events (50) reached");
         return false;
        }
      if(eventTime == 0) return false;

      m_events[m_eventCount].eventTime   = eventTime;
      m_events[m_eventCount].description = desc;
      m_events[m_eventCount].minsBefore  = (minsBefore < 0) ? m_defaultMinsBefore : minsBefore;
      m_events[m_eventCount].minsAfter   = (minsAfter  < 0) ? m_defaultMinsAfter  : minsAfter;
      m_events[m_eventCount].active      = true;
      m_eventCount++;

      LogInfo("NewsFilter", StringFormat(
         "Event added: %s @ %s [-%dm, +%dm]",
         desc, TimeToString(eventTime, TIME_DATE | TIME_MINUTES),
         m_events[m_eventCount - 1].minsBefore,
         m_events[m_eventCount - 1].minsAfter));
      return true;
     }

   //--- Parse a datetime from string "YYYY.MM.DD HH:MM" and add event
   bool AddEventFromString(const string dtStr, const string desc,
                           int minsBefore = -1, int minsAfter = -1)
     {
      datetime t = StringToTime(dtStr);
      if(t == 0)
        {
         LogWarn("NewsFilter", "Invalid datetime string: " + dtStr);
         return false;
        }
      return AddEvent(t, desc, minsBefore, minsAfter);
     }

   //--- Is trading blocked right now?
   bool IsNewsBlocked() const
     {
      if(!m_filterEnabled) return false;

      datetime now = TimeCurrent();

      // 1. Check manual events
      for(int i = 0; i < m_eventCount; i++)
        {
         if(!m_events[i].active) continue;

         datetime blockStart = m_events[i].eventTime - m_events[i].minsBefore * 60;
         datetime blockEnd   = m_events[i].eventTime + m_events[i].minsAfter  * 60;

         if(now >= blockStart && now <= blockEnd)
           {
            LogDebug("NewsFilter", StringFormat(
               "Blocked by event: %s (window %s to %s)",
               m_events[i].description,
               TimeToString(blockStart, TIME_MINUTES),
               TimeToString(blockEnd,   TIME_MINUTES)));
            return true;
           }
        }

      // 2. Auto-block: NFP (first Friday of month, ~12:30 UTC)
      if(m_autoBlockNFP && IsNFPPeriod(now))
         return true;

      // 3. Auto-block: FOMC
      if(m_autoBlockFOMC && IsFOMCPeriod(now))
         return true;

      return false;
     }

   //--- Return reason string if blocked
   string GetBlockReason() const
     {
      if(!m_filterEnabled) return "NewsFilter OFF";

      datetime now = TimeCurrent();

      for(int i = 0; i < m_eventCount; i++)
        {
         if(!m_events[i].active) continue;
         datetime blockStart = m_events[i].eventTime - m_events[i].minsBefore * 60;
         datetime blockEnd   = m_events[i].eventTime + m_events[i].minsAfter  * 60;
         if(now >= blockStart && now <= blockEnd)
            return "NEWS: " + m_events[i].description;
        }

      if(m_autoBlockNFP && IsNFPPeriod(now))  return "AUTO-BLOCK: NFP";
      if(m_autoBlockFOMC && IsFOMCPeriod(now)) return "AUTO-BLOCK: FOMC";

      return "";
     }

   //--- Are we currently in alert window (within X mins of next news)?
   bool IsApproachingNews(int lookAheadMins = 5) const
     {
      if(!m_filterEnabled) return false;
      datetime now     = TimeCurrent();
      datetime horizon = now + lookAheadMins * 60;

      for(int i = 0; i < m_eventCount; i++)
        {
         if(!m_events[i].active) continue;
         datetime blockStart = m_events[i].eventTime - m_events[i].minsBefore * 60;
         if(blockStart > now && blockStart <= horizon)
            return true;
        }
      return false;
     }

private:
   //--- Check if current time is within NFP auto-block window
   //--- NFP = first Friday of month, typically 12:30 UTC
   bool IsNFPPeriod(datetime now) const
     {
      MqlDateTime mdt;
      TimeToStruct(now, mdt);

      // Must be a Friday
      if(mdt.day_of_week != 5) return false;

      // Must be in first 7 days of month
      if(mdt.day > 7) return false;

      // Must be within window of NFP hour
      int nowMin   = mdt.hour * 60 + mdt.min;
      int nfpMin   = m_nfpHour * 60 + 30;
      int winStart = nfpMin - m_nfpWindowMins;
      int winEnd   = nfpMin + m_nfpWindowMins;

      return (nowMin >= winStart && nowMin <= winEnd);
     }

   //--- FOMC: typically Wed/Thu at fomcHour UTC (e.g. 18:00)
   bool IsFOMCPeriod(datetime now) const
     {
      MqlDateTime mdt;
      TimeToStruct(now, mdt);

      // Wednesday = 3, Thursday = 4 in MQL5
      if(mdt.day_of_week != 3 && mdt.day_of_week != 4) return false;

      int nowHour = mdt.hour;
      // Block from fomcHour to fomcHour+2
      return (nowHour >= m_fomcHour && nowHour < m_fomcHour + 2);
     }
  };
//+------------------------------------------------------------------+
#endif // NEWSFILTER_MQH

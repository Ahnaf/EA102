//+------------------------------------------------------------------+
//|                                                  NewsFilter.mqh  |
//|                        EA102 v2 - XAUUSD Prop Firm EA            |
//|              High-impact news blocking (manual + auto NFP/FOMC) |
//+------------------------------------------------------------------+
#ifndef NEWSFILTER_MQH
#define NEWSFILTER_MQH

#include "Utilities.mqh"

#define MAX_NEWS_EVENTS 20

struct NewsEvent
  {
   datetime eventTime;
   int      minsBefore;
   int      minsAfter;
   string   description;
  };

//+------------------------------------------------------------------+
//| CNewsFilter                                                      |
//+------------------------------------------------------------------+
class CNewsFilter
  {
private:
   bool      m_filterEnabled;
   int       m_defaultMinsBefore;
   int       m_defaultMinsAfter;
   bool      m_autoBlockNFP;
   int       m_nfpHour;
   int       m_nfpWindowMins;
   bool      m_autoBlockFOMC;
   int       m_fomcHour;
   NewsEvent m_events[MAX_NEWS_EVENTS];
   int       m_eventCount;
   string    m_blockReason;

public:
   CNewsFilter() : m_filterEnabled(true), m_defaultMinsBefore(30),
                   m_defaultMinsAfter(15), m_autoBlockNFP(true),
                   m_nfpHour(12), m_nfpWindowMins(60),
                   m_autoBlockFOMC(true), m_fomcHour(18),
                   m_eventCount(0), m_blockReason("") {}

   bool Init(bool filterEnabled, int minsBefore, int minsAfter,
             bool autoNFP, int nfpHour, int nfpWindowMins,
             bool autoFOMC, int fomcHour)
     {
      m_filterEnabled     = filterEnabled;
      m_defaultMinsBefore = minsBefore;
      m_defaultMinsAfter  = minsAfter;
      m_autoBlockNFP      = autoNFP;
      m_nfpHour           = nfpHour;
      m_nfpWindowMins     = nfpWindowMins;
      m_autoBlockFOMC     = autoFOMC;
      m_fomcHour          = fomcHour;
      m_eventCount        = 0;
      LogInfo("NewsFilter", StringFormat("Init | Filter=%s NFP=%s FOMC=%s Before=%dm After=%dm",
              filterEnabled?"ON":"OFF", autoNFP?"ON":"OFF", autoFOMC?"ON":"OFF",
              minsBefore, minsAfter));
      return true;
     }

   bool AddEvent(datetime eventTime, const string desc, int minsBefore = -1, int minsAfter = -1)
     {
      if(m_eventCount >= MAX_NEWS_EVENTS) { LogWarn("NewsFilter", "Event list full"); return false; }
      m_events[m_eventCount].eventTime   = eventTime;
      m_events[m_eventCount].description = desc;
      m_events[m_eventCount].minsBefore  = (minsBefore < 0) ? m_defaultMinsBefore : minsBefore;
      m_events[m_eventCount].minsAfter   = (minsAfter  < 0) ? m_defaultMinsAfter  : minsAfter;
      m_eventCount++;
      LogInfo("NewsFilter", StringFormat("Added: %s @ %s", desc, TimeToString(eventTime)));
      return true;
     }

   bool AddEventFromString(const string dtStr, const string desc, int minsBefore = -1, int minsAfter = -1)
     {
      datetime t = StringToTime(dtStr);
      if(t <= 0) { LogWarn("NewsFilter", "Bad datetime: " + dtStr); return false; }
      return AddEvent(t, desc, minsBefore, minsAfter);
     }

   bool IsNewsBlocked()
     {
      if(!m_filterEnabled) return false;
      datetime now = TimeCurrent();
      m_blockReason = "";

      // Check manual events
      for(int i = 0; i < m_eventCount; i++)
        {
         datetime before = m_events[i].eventTime - m_events[i].minsBefore * 60;
         datetime after  = m_events[i].eventTime + m_events[i].minsAfter  * 60;
         if(now >= before && now <= after)
           {
            m_blockReason = m_events[i].description;
            return true;
           }
        }

      // Auto NFP: first Friday of every month at nfpHour UTC
      if(m_autoBlockNFP)
        {
         MqlDateTime dt;
         TimeToStruct(now, dt);
         if(dt.day_of_week == 5 && dt.day <= 7)  // First Friday
           {
            int nowMins  = dt.hour * 60 + dt.min;
            int nfpMins  = m_nfpHour * 60;
            if(nowMins >= nfpMins - m_nfpWindowMins && nowMins <= nfpMins + m_nfpWindowMins)
              {
               m_blockReason = "NFP";
               return true;
              }
           }
        }

      // Auto FOMC: Wednesday and Thursday around fomcHour
      if(m_autoBlockFOMC)
        {
         MqlDateTime dt;
         TimeToStruct(now, dt);
         if(dt.day_of_week == 3 || dt.day_of_week == 4)
           {
            int nowMins  = dt.hour * 60 + dt.min;
            int fomcMins = m_fomcHour * 60;
            if(nowMins >= fomcMins - 30 && nowMins <= fomcMins + 15)
              {
               m_blockReason = "FOMC";
               return true;
              }
           }
        }

      return false;
     }

   string GetBlockReason() const { return m_blockReason; }

   bool IsApproachingNews(int withinMins = 15) const
     {
      datetime now = TimeCurrent();
      for(int i = 0; i < m_eventCount; i++)
        {
         long diff = (long)m_events[i].eventTime - (long)now;
         if(diff >= 0 && diff <= withinMins * 60) return true;
        }
      return false;
     }
  };

#endif // NEWSFILTER_MQH

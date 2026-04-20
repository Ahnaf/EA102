//+------------------------------------------------------------------+
//|                                               PropProtection.mqh |
//|                        EA102 v2 - XAUUSD Prop Firm EA            |
//|              Prop firm drawdown protection & emergency controls  |
//+------------------------------------------------------------------+
#ifndef PROPPROTECTION_MQH
#define PROPPROTECTION_MQH

#include "Utilities.mqh"
#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| CPropProtection — enforces FTMO / FundedNext rules              |
//+------------------------------------------------------------------+
class CPropProtection
  {
private:
   string   m_symbol;
   int      m_magic;

   //--- Limits
   double   m_maxDDPct;          // Hard stop (e.g. 10%)
   double   m_dailyDDPct;        // Daily limit (e.g. 5%)
   bool     m_useProfitLock;
   double   m_profitLockPct;
   bool     m_useEmergencyClose;

   //--- State
   bool     m_maxDDBreached;
   bool     m_dailyDDBlocked;
   bool     m_profitLocked;

   //--- Tracking
   double   m_startBalance;      // Balance at EA init
   double   m_dayStartEquity;    // Equity at last day reset
   double   m_dayPL;             // Today's P/L
   datetime m_lastDayReset;

   CTrade   m_trade;

public:
   CPropProtection() : m_maxDDBreached(false), m_dailyDDBlocked(false),
                       m_profitLocked(false), m_startBalance(0),
                       m_dayStartEquity(0), m_dayPL(0), m_lastDayReset(0) {}

   bool Init(const string symbol, double maxDDPct, double dailyDDPct,
             bool useProfitLock, double profitLockPct,
             bool useEmergencyClose, int magic)
     {
      m_symbol           = symbol;
      m_maxDDPct         = maxDDPct;
      m_dailyDDPct       = dailyDDPct;
      m_useProfitLock    = useProfitLock;
      m_profitLockPct    = profitLockPct;
      m_useEmergencyClose = useEmergencyClose;
      m_magic            = magic;
      m_startBalance     = AccountInfoDouble(ACCOUNT_BALANCE);
      m_dayStartEquity   = AccountInfoDouble(ACCOUNT_EQUITY);
      m_lastDayReset     = GetDayStart();
      m_trade.SetExpertMagicNumber(magic);
      LogInfo("PropProtection", StringFormat("Init | MaxDD=%.1f%% DailyDD=%.1f%% StartBal=%.2f",
              maxDDPct, dailyDDPct, m_startBalance));
      return true;
     }

   //--- Call every tick
   void Update()
     {
      // Daily reset
      datetime today = GetDayStart();
      if(today != m_lastDayReset)
        {
         m_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         m_dailyDDBlocked = false;
         m_profitLocked   = false;
         m_lastDayReset   = today;
        }

      double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
      m_dayPL         = equity - m_dayStartEquity;

      // Max DD check (from start balance)
      double maxDDNow = (m_startBalance > 0) ? (m_startBalance - equity) / m_startBalance * 100.0 : 0;
      if(!m_maxDDBreached && maxDDNow >= m_maxDDPct)
        {
         m_maxDDBreached = true;
         LogError("PropProtection", StringFormat("MAX DD BREACHED! DD=%.2f%% >= %.1f%%", maxDDNow, m_maxDDPct));
         if(m_useEmergencyClose) EmergencyCloseAll("MAX DD");
        }

      // Daily DD check
      if(!m_dailyDDBlocked)
        {
         double dailyDDNow = (m_dayStartEquity > 0) ? (m_dayStartEquity - equity) / m_dayStartEquity * 100.0 : 0;
         if(dailyDDNow >= m_dailyDDPct)
           {
            m_dailyDDBlocked = true;
            LogWarn("PropProtection", StringFormat("DAILY DD BLOCKED! DD=%.2f%% >= %.1f%%", dailyDDNow, m_dailyDDPct));
            if(m_useEmergencyClose) EmergencyCloseAll("DAILY DD");
           }
        }

      // Profit lock
      if(m_useProfitLock && !m_profitLocked)
        {
         double dailyProfitPct = (m_dayStartEquity > 0) ? (equity - m_dayStartEquity) / m_dayStartEquity * 100.0 : 0;
         if(dailyProfitPct >= m_profitLockPct)
           {
            m_profitLocked = true;
            LogInfo("PropProtection", StringFormat("PROFIT LOCKED at %.2f%% daily gain", dailyProfitPct));
           }
        }
     }

   void EmergencyCloseAll(const string reason)
     {
      LogError("PropProtection", "EMERGENCY CLOSE ALL | Reason: " + reason);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
         m_trade.PositionClose(ticket);
        }
     }

   bool IsMaxDDBreached()    const { return m_maxDDBreached;  }
   bool IsDailyDDBlocked()   const { return m_dailyDDBlocked; }
   bool IsDailyProfitLocked() const { return m_profitLocked;   }
   bool IsTradingAllowed()   const { return !m_maxDDBreached && !m_dailyDDBlocked && !m_profitLocked; }

   double GetDailyDDPct() const
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      return (m_dayStartEquity > 0) ? (m_dayStartEquity - equity) / m_dayStartEquity * 100.0 : 0;
     }
   double GetMaxDDPct() const
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      return (m_startBalance > 0) ? (m_startBalance - equity) / m_startBalance * 100.0 : 0;
     }
   double GetDailyPL() const { return m_dayPL; }

   string GetStatusString() const
     {
      if(m_maxDDBreached)  return "MAX DD HIT";
      if(m_dailyDDBlocked) return "DAILY BLOCKED";
      if(m_profitLocked)   return "PROFIT LOCKED";
      return "OK";
     }
  };

#endif // PROPPROTECTION_MQH

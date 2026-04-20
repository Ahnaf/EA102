//+------------------------------------------------------------------+
//|                                                PropProtection.mqh|
//|                          EA102 - XAUUSD Prop Firm EA             |
//|            Prop Firm Compliance: DD limits, emergency close      |
//+------------------------------------------------------------------+
#ifndef PROPPROTECTION_MQH
#define PROPPROTECTION_MQH
#include "Utilities.mqh"

//+------------------------------------------------------------------+
//| Prop Protection State structure                                  |
//+------------------------------------------------------------------+
struct PropState
  {
   double   startingBalance;      // Balance at EA start (or day start)
   double   dailyStartBalance;    // Balance at start of trading day
   double   maxEquityHigh;        // Highest equity reached (for max DD calc)
   double   dailyRealizedPL;      // Realised P/L today (closed trades)
   double   dailyPeakEquity;      // Peak equity today (for daily DD calc)

   bool     maxDDBreached;        // True = hard stop, no more trades ever
   bool     dailyDDBlocked;       // True = blocked for rest of today
   bool     dailyProfitLocked;    // True = daily profit target hit, lock gains
   bool     emergencyClosed;      // True = emergency close was executed

   datetime lastDayChecked;       // Date of last daily reset
  };

//+------------------------------------------------------------------+
//| CPropProtection class                                            |
//+------------------------------------------------------------------+
class CPropProtection
  {
private:
   PropState   m_state;

   // Input parameters
   double      m_maxDDPercent;          // e.g. 10.0 = 10%
   double      m_dailyDDPercent;        // e.g. 5.0  = 5%
   double      m_dailyProfitLockPct;    // e.g. 3.0  = 3% optional lock
   bool        m_useDailyProfitLock;
   bool        m_useEmergencyClose;
   string      m_symbol;

   // Internal
   double      m_maxDDThreshold;        // Absolute equity floor for max DD
   double      m_accountStartBalance;   // Starting balance of the account

   //--- Build CTrade reference for emergency close
   int         m_magicNumber;

public:
   CPropProtection() {}
   ~CPropProtection() {}

   //--- Initialise with parameters
   bool Init(const string symbol,
             double maxDDPct,
             double dailyDDPct,
             bool   useProfitLock,
             double profitLockPct,
             bool   useEmergencyClose,
             int    magicNumber)
     {
      m_symbol              = symbol;
      m_maxDDPercent        = maxDDPct;
      m_dailyDDPercent      = dailyDDPct;
      m_useDailyProfitLock  = useProfitLock;
      m_dailyProfitLockPct  = profitLockPct;
      m_useEmergencyClose   = useEmergencyClose;
      m_magicNumber         = magicNumber;

      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      m_accountStartBalance         = bal;
      m_state.startingBalance       = bal;
      m_state.dailyStartBalance     = bal;
      m_state.maxEquityHigh         = AccountInfoDouble(ACCOUNT_EQUITY);
      m_state.dailyPeakEquity       = m_state.maxEquityHigh;
      m_state.dailyRealizedPL       = 0;
      m_state.maxDDBreached         = false;
      m_state.dailyDDBlocked        = false;
      m_state.dailyProfitLocked     = false;
      m_state.emergencyClosed       = false;
      m_state.lastDayChecked        = TimeCurrent();

      // Max DD threshold = starting balance * (1 - maxDDPct/100)
      m_maxDDThreshold = m_accountStartBalance * (1.0 - m_maxDDPercent / 100.0);

      LogInfo("PropProtection", StringFormat(
         "Initialised | StartBal=%.2f | MaxDD=%.1f%% | DailyDD=%.1f%%",
         bal, m_maxDDPercent, m_dailyDDPercent));
      return true;
     }

   //--- Call every tick / bar
   void Update()
     {
      DailyReset();
      CheckMaxDD();
      CheckDailyDD();
      if(m_useDailyProfitLock) CheckDailyProfitLock();
     }

   //--- Reset daily counters at new trading day
   void DailyReset()
     {
      datetime now = TimeCurrent();
      if(!SameDay(now, m_state.lastDayChecked))
        {
         m_state.dailyStartBalance   = AccountInfoDouble(ACCOUNT_BALANCE);
         m_state.dailyPeakEquity     = AccountInfoDouble(ACCOUNT_EQUITY);
         m_state.dailyRealizedPL     = 0;
         m_state.dailyDDBlocked      = false;   // Unblock at new day
         m_state.dailyProfitLocked   = false;
         m_state.lastDayChecked      = now;
         LogInfo("PropProtection", StringFormat(
            "New day reset | DayBal=%.2f", m_state.dailyStartBalance));
        }
     }

   //--- Check max drawdown against highest equity
   void CheckMaxDD()
     {
      if(m_state.maxDDBreached) return; // Already triggered

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);

      // Update peak equity
      if(equity > m_state.maxEquityHigh)
         m_state.maxEquityHigh = equity;

      // DD from absolute starting balance (FTMO style)
      double ddFromStart = (m_accountStartBalance - equity) / m_accountStartBalance * 100.0;

      if(ddFromStart >= m_maxDDPercent)
        {
         m_state.maxDDBreached = true;
         LogError("PropProtection", StringFormat(
            "MAX DRAWDOWN BREACHED! DD=%.2f%% | Equity=%.2f | Threshold=%.2f%%",
            ddFromStart, equity, m_maxDDPercent));

         if(m_useEmergencyClose)
            EmergencyCloseAll("MAX DD BREACHED");
        }
     }

   //--- Check daily drawdown
   void CheckDailyDD()
     {
      if(m_state.dailyDDBlocked) return;

      double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
      double dayStart  = m_state.dailyStartBalance;

      // Update today's peak equity
      if(equity > m_state.dailyPeakEquity)
         m_state.dailyPeakEquity = equity;

      // DD from today's start balance (strict prop firm rule)
      double dailyDD = (dayStart - equity) / dayStart * 100.0;

      if(dailyDD >= m_dailyDDPercent)
        {
         m_state.dailyDDBlocked = true;
         LogError("PropProtection", StringFormat(
            "DAILY DD BREACHED! DD=%.2f%% | Equity=%.2f | DayStart=%.2f",
            dailyDD, equity, dayStart));

         if(m_useEmergencyClose)
            EmergencyCloseAll("DAILY DD BREACHED");
        }
     }

   //--- Check daily profit lock
   void CheckDailyProfitLock()
     {
      if(m_state.dailyProfitLocked) return;

      double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      double dayStart = m_state.dailyStartBalance;
      double profitPct = (equity - dayStart) / dayStart * 100.0;

      if(profitPct >= m_dailyProfitLockPct)
        {
         m_state.dailyProfitLocked = true;
         LogInfo("PropProtection", StringFormat(
            "Daily profit lock triggered at +%.2f%%", profitPct));
        }
     }

   //--- Emergency close all positions for this magic number
   void EmergencyCloseAll(const string reason)
     {
      if(m_state.emergencyClosed) return;
      LogWarn("PropProtection", "EMERGENCY CLOSE ALL | Reason: " + reason);

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;

         MqlTradeRequest req  = {};
         MqlTradeResult  res  = {};
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
            LogError("PropProtection", StringFormat(
               "Close failed ticket=%llu err=%d", ticket, GetLastError()));
         else
            LogInfo("PropProtection", StringFormat(
               "Closed ticket=%llu", ticket));
        }

      m_state.emergencyClosed = true;
     }

   //--- State queries
   bool IsMaxDDBreached()     const { return m_state.maxDDBreached; }
   bool IsDailyDDBlocked()    const { return m_state.dailyDDBlocked; }
   bool IsDailyProfitLocked() const { return m_state.dailyProfitLocked; }
   bool IsEmergencyClosed()   const { return m_state.emergencyClosed; }

   bool IsTradingAllowed() const
     {
      return !m_state.maxDDBreached &&
             !m_state.dailyDDBlocked &&
             !m_state.dailyProfitLocked &&
             !m_state.emergencyClosed;
     }

   //--- Metrics for dashboard
   double GetDailyDDPct() const
     {
      double dayStart = m_state.dailyStartBalance;
      if(dayStart == 0) return 0;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      return (dayStart - equity) / dayStart * 100.0;
     }

   double GetMaxDDPct() const
     {
      if(m_accountStartBalance == 0) return 0;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      return (m_accountStartBalance - equity) / m_accountStartBalance * 100.0;
     }

   double GetDailyPL() const
     {
      return AccountInfoDouble(ACCOUNT_EQUITY) - m_state.dailyStartBalance;
     }

   double GetDailyPLPct() const
     {
      if(m_state.dailyStartBalance == 0) return 0;
      return GetDailyPL() / m_state.dailyStartBalance * 100.0;
     }

   string GetStatusString() const
     {
      if(m_state.maxDDBreached)   return "MAX DD HIT";
      if(m_state.emergencyClosed) return "EMERGENCY";
      if(m_state.dailyDDBlocked)  return "DAILY DD HIT";
      if(m_state.dailyProfitLocked) return "PROFIT LOCK";
      return "ACTIVE";
     }
  };
//+------------------------------------------------------------------+
#endif // PROPPROTECTION_MQH

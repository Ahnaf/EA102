//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|                          EA102 - XAUUSD Prop Firm EA             |
//|   Lot sizing, exposure control, frequency gate (condition X + F) |
//+------------------------------------------------------------------+
#pragma once
#include "Utilities.mqh"
#include "SignalEngine.mqh"

//+------------------------------------------------------------------+
//| CRiskManager class                                               |
//+------------------------------------------------------------------+
class CRiskManager
  {
private:
   string            m_symbol;
   int               m_magicNumber;

   // Risk parameters
   double            m_riskPctPerTrade;    // e.g. 1.0 = 1%
   double            m_maxRiskExposurePct; // Total open risk % allowed
   int               m_maxOpenTrades;
   double            m_maxSymbolRiskPct;   // Per-symbol exposure limit

   // Frequency control
   ENUM_TRADE_MODE   m_tradeMode;
   int               m_cooldownSecs;       // Cooldown after any trade (mode dependent)
   int               m_cooldownAfterLoss;  // Extra cooldown on losing trade
   int               m_maxTradesPerDay;
   int               m_maxTradesPerSession;

   // State
   datetime          m_lastTradeTime;
   datetime          m_lastLossTime;
   int               m_tradesToday;
   int               m_tradesThisSession;
   datetime          m_lastDayReset;
   datetime          m_lastSessionReset;

   // Hedge control
   bool              m_allowHedge;

public:
   CRiskManager() : m_lastTradeTime(0), m_lastLossTime(0),
                    m_tradesToday(0), m_tradesThisSession(0),
                    m_lastDayReset(0), m_lastSessionReset(0) {}
   ~CRiskManager() {}

   bool Init(const string    symbol,
             int             magicNumber,
             double          riskPct,
             double          maxExposurePct,
             int             maxOpenTrades,
             double          maxSymbolRiskPct,
             ENUM_TRADE_MODE tradeMode,
             bool            allowHedge,
             int             maxTradesPerDay,
             int             maxTradesPerSession)
     {
      m_symbol              = symbol;
      m_magicNumber         = magicNumber;
      m_riskPctPerTrade     = riskPct;
      m_maxRiskExposurePct  = maxExposurePct;
      m_maxOpenTrades       = maxOpenTrades;
      m_maxSymbolRiskPct    = maxSymbolRiskPct;
      m_tradeMode           = tradeMode;
      m_allowHedge          = allowHedge;
      m_maxTradesPerDay     = maxTradesPerDay;
      m_maxTradesPerSession = maxTradesPerSession;

      UpdateCooldownFromMode();

      LogInfo("RiskManager", StringFormat(
         "Init | Risk=%.1f%% | MaxExposure=%.1f%% | MaxTrades=%d | Mode=%s | AllowHedge=%s",
         riskPct, maxExposurePct, maxOpenTrades, EnumToString(tradeMode),
         allowHedge ? "YES" : "NO"));
      return true;
     }

   //--- Update cooldown settings based on trade mode
   void SetTradeMode(ENUM_TRADE_MODE mode)
     {
      m_tradeMode = mode;
      UpdateCooldownFromMode();
     }

   //--- Condition F: Frequency gate — can we place a new trade now?
   bool IsFrequencyGateOpen(string &reason)
     {
      DailyReset();
      SessionReset();

      datetime now = TimeCurrent();

      // 1. Daily trade count limit
      if(m_maxTradesPerDay > 0 && m_tradesToday >= m_maxTradesPerDay)
        {
         reason = StringFormat("Max trades/day reached (%d/%d)", m_tradesToday, m_maxTradesPerDay);
         return false;
        }

      // 2. Session trade count limit
      if(m_maxTradesPerSession > 0 && m_tradesThisSession >= m_maxTradesPerSession)
        {
         reason = StringFormat("Max trades/session reached (%d/%d)", m_tradesThisSession, m_maxTradesPerSession);
         return false;
        }

      // 3. General cooldown after last trade
      if(m_lastTradeTime > 0 && (now - m_lastTradeTime) < m_cooldownSecs)
        {
         reason = StringFormat("Cooldown active (%ds remaining)",
                               m_cooldownSecs - (int)(now - m_lastTradeTime));
         return false;
        }

      // 4. Extra cooldown after a loss
      if(m_lastLossTime > 0 && (now - m_lastLossTime) < m_cooldownAfterLoss)
        {
         reason = StringFormat("Loss cooldown active (%ds remaining)",
                               m_cooldownAfterLoss - (int)(now - m_lastLossTime));
         return false;
        }

      reason = "OK";
      return true;
     }

   //--- Condition X: Exposure gate — is opening a new trade safe?
   bool IsExposureAllowed(ENUM_SIGNAL_DIR newDir, double slDistance, string &reason)
     {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance <= 0)
        {
         reason = "Balance=0";
         return false;
        }

      // 1. Max open trades
      int openTrades = CountOpenTrades();
      if(openTrades >= m_maxOpenTrades)
        {
         reason = StringFormat("Max open trades (%d/%d)", openTrades, m_maxOpenTrades);
         return false;
        }

      // 2. Total open risk
      double totalRisk = CalculateTotalOpenRiskPct();
      if(totalRisk + m_riskPctPerTrade > m_maxRiskExposurePct)
        {
         reason = StringFormat("Total exposure too high (%.1f%% + %.1f%% > %.1f%%)",
                               totalRisk, m_riskPctPerTrade, m_maxRiskExposurePct);
         return false;
        }

      // 3. Hedge check
      if(!m_allowHedge)
        {
         bool hasBuy  = HasOpenTrade(POSITION_TYPE_BUY);
         bool hasSell = HasOpenTrade(POSITION_TYPE_SELL);
         if((newDir == SIGNAL_BUY && hasSell) || (newDir == SIGNAL_SELL && hasBuy))
           {
            reason = "Hedge not allowed";
            return false;
           }
        }

      reason = "OK";
      return true;
     }

   //--- Calculate risk-based lot size
   double CalculateLotSize(double entryPrice, double stopLossPrice)
     {
      double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmt  = balance * m_riskPctPerTrade / 100.0;
      double slDist   = MathAbs(entryPrice - stopLossPrice);

      if(slDist <= 0)
        {
         LogError("RiskManager", "SL distance=0, cannot calculate lot size");
         return SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
        }

      // pip value per lot
      double tickVal  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      double pvPerLot = (tickVal / tickSize) * slDist;

      if(pvPerLot <= 0)
        {
         LogError("RiskManager", "Pip value calc failed");
         return SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
        }

      double lots = riskAmt / pvPerLot;
      lots = NormalizeLots(m_symbol, lots);

      LogDebug("RiskManager", StringFormat(
         "LotCalc | Bal=%.2f Risk%%=%.2f RiskAmt=%.2f SLDist=%.5f PV/lot=%.4f Lots=%.2f",
         balance, m_riskPctPerTrade, riskAmt, slDist, pvPerLot, lots));

      return lots;
     }

   //--- Record trade opened
   void OnTradeOpened()
     {
      m_lastTradeTime = TimeCurrent();
      m_tradesToday++;
      m_tradesThisSession++;
      LogDebug("RiskManager", StringFormat(
         "Trade opened | Today=%d Session=%d", m_tradesToday, m_tradesThisSession));
     }

   //--- Record trade closed as loss
   void OnTradeLoss()
     {
      m_lastLossTime = TimeCurrent();
      LogDebug("RiskManager", "Loss cooldown started");
     }

   //--- Getters
   ENUM_TRADE_MODE GetTradeMode()       const { return m_tradeMode; }
   int             GetTradesPerDay()    const { return m_tradesToday; }
   int             GetOpenTradeCount()  const { return CountOpenTrades(); }
   double          GetTotalRiskPct()    const { return CalculateTotalOpenRiskPct(); }
   double          GetRiskPctPerTrade() const { return m_riskPctPerTrade; }

private:
   void UpdateCooldownFromMode()
     {
      switch(m_tradeMode)
        {
         case TRADE_MODE_SAFE:
            m_cooldownSecs     = 3600;  // 60 min
            m_cooldownAfterLoss = 7200; // 2 hours
            break;
         case TRADE_MODE_NORMAL:
            m_cooldownSecs     = 1800;  // 30 min
            m_cooldownAfterLoss = 3600; // 1 hour
            break;
         case TRADE_MODE_AGGRESSIVE:
            m_cooldownSecs     = 600;   // 10 min
            m_cooldownAfterLoss = 1800; // 30 min
            break;
        }
     }

   int CountOpenTrades() const
     {
      int count = 0;
      for(int i = 0; i < PositionsTotal(); i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;
         count++;
        }
      return count;
     }

   bool HasOpenTrade(ENUM_POSITION_TYPE type) const
     {
      for(int i = 0; i < PositionsTotal(); i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type) return true;
        }
      return false;
     }

   double CalculateTotalOpenRiskPct() const
     {
      double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance <= 0) return 0;

      double totalRisk = 0;
      for(int i = 0; i < PositionsTotal(); i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;

         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl        = PositionGetDouble(POSITION_SL);
         double lots      = PositionGetDouble(POSITION_VOLUME);
         ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         if(sl == 0) continue;

         double slDist = MathAbs(openPrice - sl);
         double tickVal  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
         double pvPerLot = (tickVal / tickSize) * slDist;

         totalRisk += pvPerLot * lots;
        }

      return totalRisk / balance * 100.0;
     }

   void DailyReset()
     {
      datetime now = TimeCurrent();
      if(!SameDay(now, m_lastDayReset))
        {
         m_tradesToday    = 0;
         m_lastDayReset   = now;
        }
     }

   void SessionReset()
     {
      // Reset session counter every 8 hours
      datetime now = TimeCurrent();
      if(m_lastSessionReset == 0 || (now - m_lastSessionReset) > 8 * 3600)
        {
         m_tradesThisSession = 0;
         m_lastSessionReset  = now;
        }
     }
  };
//+------------------------------------------------------------------+

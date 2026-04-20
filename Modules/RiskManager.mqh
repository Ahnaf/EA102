//+------------------------------------------------------------------+
//|                                                 RiskManager.mqh  |
//|                        EA102 v2 - XAUUSD Prop Firm EA            |
//|        Lot sizing, frequency gate, exposure control             |
//+------------------------------------------------------------------+
#ifndef RISKMANAGER_MQH
#define RISKMANAGER_MQH

#include "Utilities.mqh"

//+------------------------------------------------------------------+
//| CRiskManager                                                     |
//+------------------------------------------------------------------+
class CRiskManager
  {
private:
   string          m_symbol;
   int             m_magic;
   double          m_riskPct;
   double          m_maxExposurePct;
   int             m_maxOpenTrades;
   ENUM_TRADE_MODE m_tradeMode;
   bool            m_allowHedge;
   int             m_maxTradesPerDay;
   int             m_maxTradesPerSess;

   //--- Frequency tracking
   datetime m_lastTradeTime;
   datetime m_lastLossTime;
   int      m_tradesToday;
   int      m_tradesThisSess;
   datetime m_lastDayReset;
   datetime m_lastSessBarTime;

   //--- Per-mode cooldowns (seconds)
   int GetCooldownSecs()     const { return (m_tradeMode == TRADE_MODE_SAFE) ? 3600 : (m_tradeMode == TRADE_MODE_NORMAL) ? 1800 : 600; }
   int GetLossCooldownSecs() const { return (m_tradeMode == TRADE_MODE_SAFE) ? 7200 : (m_tradeMode == TRADE_MODE_NORMAL) ? 3600 : 1800; }

   //--- Count open EA positions
   int CountOpenPositions() const
     {
      int cnt = 0;
      for(int i = 0; i < PositionsTotal(); i++)
        {
         ulong t = PositionGetTicket(i);
         if(!PositionSelectByTicket(t)) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
         cnt++;
        }
      return cnt;
     }

public:
   CRiskManager() : m_lastTradeTime(0), m_lastLossTime(0),
                    m_tradesToday(0), m_tradesThisSess(0),
                    m_lastDayReset(0), m_lastSessBarTime(0) {}

   bool Init(const string symbol, int magic, double riskPct,
             double maxExposurePct, int maxOpenTrades, ENUM_TRADE_MODE tradeMode,
             bool allowHedge, int maxTradesPerDay, int maxTradesPerSess)
     {
      m_symbol          = symbol;
      m_magic           = magic;
      m_riskPct         = riskPct;
      m_maxExposurePct  = maxExposurePct;
      m_maxOpenTrades   = maxOpenTrades;
      m_tradeMode       = tradeMode;
      m_allowHedge      = allowHedge;
      m_maxTradesPerDay  = maxTradesPerDay;
      m_maxTradesPerSess = maxTradesPerSess;
      m_lastDayReset    = GetDayStart();
      LogInfo("RiskManager", StringFormat("Init | Risk=%.1f%% MaxExp=%.1f%% MaxOpen=%d Mode=%s",
              riskPct, maxExposurePct, maxOpenTrades, EnumToString(tradeMode)));
      return true;
     }

   void SetTradeMode(ENUM_TRADE_MODE mode) { m_tradeMode = mode; }

   //--- Daily reset of counters
   void UpdateDailyCounters()
     {
      datetime today = GetDayStart();
      if(today != m_lastDayReset)
        {
         m_tradesToday   = 0;
         m_tradesThisSess = 0;
         m_lastDayReset  = today;
        }
     }

   //+------------------------------------------------------------------+
   //| N (Frequency) gate — condition F                                |
   //+------------------------------------------------------------------+
   bool IsFrequencyGateOpen(string &reason) const
     {
      datetime now = TimeCurrent();

      // Global cooldown since last trade
      if(m_lastTradeTime > 0)
        {
         long elapsed = (long)now - (long)m_lastTradeTime;
         if(elapsed < GetCooldownSecs())
           {
            reason = StringFormat("Cooldown %ds remaining", GetCooldownSecs() - (int)elapsed);
            return false;
           }
        }

      // Loss cooldown
      if(m_lastLossTime > 0)
        {
         long elapsed = (long)now - (long)m_lastLossTime;
         if(elapsed < GetLossCooldownSecs())
           {
            reason = StringFormat("Loss-cooldown %ds remaining", GetLossCooldownSecs() - (int)elapsed);
            return false;
           }
        }

      // Daily limit
      if(m_maxTradesPerDay > 0 && m_tradesToday >= m_maxTradesPerDay)
        {
         reason = StringFormat("Daily limit %d reached", m_maxTradesPerDay);
         return false;
        }

      // Session limit
      if(m_maxTradesPerSess > 0 && m_tradesThisSess >= m_maxTradesPerSess)
        {
         reason = StringFormat("Session limit %d reached", m_maxTradesPerSess);
         return false;
        }

      reason = "";
      return true;
     }

   //+------------------------------------------------------------------+
   //| X (Exposure) gate — condition X                                 |
   //+------------------------------------------------------------------+
   bool IsExposureAllowed(ENUM_SIGNAL_DIR dir, double slDistancePrice, string &reason) const
     {
      // Max simultaneous open trades
      int open = CountOpenPositions();
      if(open >= m_maxOpenTrades)
        {
         reason = StringFormat("Max open trades %d reached", m_maxOpenTrades);
         return false;
        }

      // Hedge rule
      if(!m_allowHedge && open > 0)
        {
         for(int i = 0; i < PositionsTotal(); i++)
           {
            ulong t = PositionGetTicket(i);
            if(!PositionSelectByTicket(t)) continue;
            if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
            if((int)PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
            int posType = (int)PositionGetInteger(POSITION_TYPE);
            bool existingBuy  = (posType == POSITION_TYPE_BUY);
            bool existingSell = (posType == POSITION_TYPE_SELL);
            if((dir == SIGNAL_BUY  && existingSell) ||
               (dir == SIGNAL_SELL && existingBuy))
              {
               reason = "Hedge not allowed";
               return false;
              }
           }
        }

      // Total exposure check
      if(slDistancePrice > 0 && m_maxExposurePct > 0)
        {
         double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
         double newRisk   = balance * m_riskPct / 100.0;
         double currRisk  = 0;
         for(int i = 0; i < PositionsTotal(); i++)
           {
            ulong t = PositionGetTicket(i);
            if(!PositionSelectByTicket(t)) continue;
            if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
            if((int)PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
            double pnl = PositionGetDouble(POSITION_PROFIT);
            if(pnl < 0) currRisk += MathAbs(pnl);
           }
         double totalRisk    = currRisk + newRisk;
         double totalRiskPct = (balance > 0) ? totalRisk / balance * 100.0 : 0;
         if(totalRiskPct > m_maxExposurePct)
           {
            reason = StringFormat("Exposure %.1f%% > max %.1f%%", totalRiskPct, m_maxExposurePct);
            return false;
           }
        }

      reason = "";
      return true;
     }

   //+------------------------------------------------------------------+
   //| Lot sizing based on account risk and SL distance               |
   //+------------------------------------------------------------------+
   double CalculateLotSize(double entryPrice, double stopLoss) const
     {
      double slDist = MathAbs(entryPrice - stopLoss);
      if(slDist <= 0) return SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);

      double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskMoney  = balance * m_riskPct / 100.0;
      double tickVal    = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize   = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickVal <= 0 || tickSize <= 0) return SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);

      double valPerPoint = (tickVal / tickSize) * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double lossPerLot  = (slDist / SymbolInfoDouble(m_symbol, SYMBOL_POINT)) * valPerPoint;
      if(lossPerLot <= 0) return SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);

      double lots = riskMoney / lossPerLot;
      return NormalizeLots(m_symbol, lots);
     }

   //--- Called after a new trade is opened
   void OnTradeOpened()
     {
      m_lastTradeTime = TimeCurrent();
      m_tradesToday++;
      m_tradesThisSess++;
     }

   //--- Called when a trade closes in loss (from OnTradeTransaction)
   void OnTradeLoss()
     {
      m_lastLossTime = TimeCurrent();
      LogInfo("RiskManager", "Loss recorded — cooldown started");
     }

   //--- Getters
   ENUM_TRADE_MODE GetTradeMode()      const { return m_tradeMode;      }
   int             GetOpenTradeCount() const { return CountOpenPositions(); }
   int             GetTradesPerDay()   const { return m_tradesToday;     }
   int             GetTradesPerSess()  const { return m_tradesThisSess;  }
   double          GetRiskPct()        const { return m_riskPct;         }
  };

#endif // RISKMANAGER_MQH

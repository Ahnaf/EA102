//+------------------------------------------------------------------+
//|                                                 SignalEngine.mqh |
//|                          EA102 - XAUUSD Prop Firm EA             |
//|         HTF Trend Analysis: EMA, Market Structure, RSI           |
//+------------------------------------------------------------------+
#pragma once
#include "Utilities.mqh"
#include "MarketStructure.mqh"

//--- Trade frequency / confirmation mode
enum ENUM_TRADE_MODE
  {
   TRADE_MODE_SAFE       = 0,   // Strictest — requires full confluence
   TRADE_MODE_NORMAL     = 1,   // Balanced
   TRADE_MODE_AGGRESSIVE = 2,   // Relaxed — fewer confluences required
  };

//--- Signal direction
enum ENUM_SIGNAL_DIR
  {
   SIGNAL_NONE  = 0,
   SIGNAL_BUY   = 1,
   SIGNAL_SELL  = 2,
  };

//--- Full signal package returned to MainEA
struct SignalPackage
  {
   SIGNAL_DIR     direction;
   double         setupScore;   // 0.0 – 1.0 (confluence score)
   string         reason;
   double         suggestedSL;  // 0 = not set
   double         suggestedTP;  // 0 = not set
  };

//+------------------------------------------------------------------+
//| CSignalEngine class — evaluates conditions T + U                 |
//+------------------------------------------------------------------+
class CSignalEngine
  {
private:
   string              m_symbol;
   ENUM_TIMEFRAMES     m_htfTF;       // Higher timeframe for trend (e.g. H1/H4)
   ENUM_TIMEFRAMES     m_setupTF;     // Setup timeframe (e.g. M15)

   // EMA parameters
   int                 m_emaFastPeriod;
   int                 m_emaSlowPeriod;

   // RSI parameters
   int                 m_rsiPeriod;
   double              m_rsiBullMin;   // e.g. 50
   double              m_rsiBullMax;   // e.g. 70
   double              m_rsiBearMin;   // e.g. 30
   double              m_rsiBearMax;   // e.g. 50

   // Trade mode
   ENUM_TRADE_MODE     m_tradeMode;

   // Cached market structure object (set by owner)
   CMarketStructure   *m_htfStructure;
   CMarketStructure   *m_setupStructure;

   // State
   ENUM_SIGNAL_DIR     m_lastTrendDir;
   double              m_lastScore;

public:
   CSignalEngine() : m_lastTrendDir(SIGNAL_NONE), m_lastScore(0),
                     m_htfStructure(NULL), m_setupStructure(NULL) {}
   ~CSignalEngine() {}

   bool Init(const string       symbol,
             ENUM_TIMEFRAMES    htfTF,
             ENUM_TIMEFRAMES    setupTF,
             int                emaFast,
             int                emaSlow,
             int                rsiPeriod,
             double             rsiBullMin,
             double             rsiBullMax,
             double             rsiBearMin,
             double             rsiBearMax,
             ENUM_TRADE_MODE    tradeMode,
             CMarketStructure  *htfStructure,
             CMarketStructure  *setupStructure)
     {
      m_symbol         = symbol;
      m_htfTF          = htfTF;
      m_setupTF        = setupTF;
      m_emaFastPeriod  = emaFast;
      m_emaSlowPeriod  = emaSlow;
      m_rsiPeriod      = rsiPeriod;
      m_rsiBullMin     = rsiBullMin;
      m_rsiBullMax     = rsiBullMax;
      m_rsiBearMin     = rsiBearMin;
      m_rsiBearMax     = rsiBearMax;
      m_tradeMode      = tradeMode;
      m_htfStructure   = htfStructure;
      m_setupStructure = setupStructure;

      LogInfo("SignalEngine", StringFormat(
         "Init | HTF=%s Setup=%s EMA%d/%d RSI%d Mode=%s",
         EnumToString(htfTF), EnumToString(setupTF),
         emaFast, emaSlow, rsiPeriod, EnumToString(tradeMode)));
      return true;
     }

   //--- Evaluate full T + U conditions and return signal
   SignalPackage Evaluate()
     {
      SignalPackage pkg;
      pkg.direction   = SIGNAL_NONE;
      pkg.setupScore  = 0.0;
      pkg.reason      = "";
      pkg.suggestedSL = 0;
      pkg.suggestedTP = 0;

      // ===== T: Higher Timeframe Trend =====
      bool htfBull = false, htfBear = false;
      double trendScore = EvaluateHTFTrend(htfBull, htfBear);

      if(!htfBull && !htfBear)
        {
         pkg.reason = "No HTF trend";
         return pkg;
        }

      // ===== U: Setup on setup TF =====
      bool setupBull = false, setupBear = false;
      double setupScore = EvaluateSetup(setupBull, setupBear);

      // Apply trade mode minimum score
      double minScore = GetMinScore();

      if(htfBull && setupBull && setupScore >= minScore)
        {
         pkg.direction  = SIGNAL_BUY;
         pkg.setupScore = (trendScore + setupScore) / 2.0;
         pkg.reason     = StringFormat("HTF Bull + Setup Bull (score=%.2f)", pkg.setupScore);
        }
      else if(htfBear && setupBear && setupScore >= minScore)
        {
         pkg.direction  = SIGNAL_SELL;
         pkg.setupScore = (trendScore + setupScore) / 2.0;
         pkg.reason     = StringFormat("HTF Bear + Setup Bear (score=%.2f)", pkg.setupScore);
        }
      else
        {
         pkg.reason = StringFormat(
            "Trend/Setup mismatch or score too low (trend=%.2f setup=%.2f min=%.2f)",
            trendScore, setupScore, minScore);
        }

      m_lastTrendDir = pkg.direction;
      m_lastScore    = pkg.setupScore;

      if(pkg.direction != SIGNAL_NONE)
         LogDebug("SignalEngine", pkg.reason);

      return pkg;
     }

   //--- Trade mode setter (can be updated during runtime)
   void SetTradeMode(ENUM_TRADE_MODE mode)
     {
      m_tradeMode = mode;
      LogInfo("SignalEngine", StringFormat("TradeMode set to %s", EnumToString(mode)));
     }

   ENUM_SIGNAL_DIR GetLastTrendDir() const { return m_lastTrendDir; }
   double          GetLastScore()    const { return m_lastScore; }

private:
   //--- Evaluate HTF trend: EMAs + market structure + RSI
   //--- Returns score 0..1
   double EvaluateHTFTrend(bool &isBull, bool &isBear)
     {
      isBull = false;
      isBear = false;

      double emaFast = GetEMA(m_symbol, m_htfTF, m_emaFastPeriod, 1);
      double emaSlow = GetEMA(m_symbol, m_htfTF, m_emaSlowPeriod, 1);
      double rsi     = GetRSI(m_symbol, m_htfTF, m_rsiPeriod, 1);
      double close   = iClose(m_symbol, m_htfTF, 1);

      double score = 0.0;

      // EMA cross (weight 0.4)
      if(emaFast > emaSlow) score += 0.4;
      else if(emaFast < emaSlow) score -= 0.4;

      // Price vs EMA (weight 0.2)
      if(close > emaSlow) score += 0.2;
      else if(close < emaSlow) score -= 0.2;

      // RSI (weight 0.2)
      if(rsi > m_rsiBullMin && rsi < m_rsiBullMax) score += 0.2;
      else if(rsi < m_rsiBearMax && rsi > m_rsiBearMin) score -= 0.2;

      // Market structure (weight 0.2)
      if(m_htfStructure != NULL)
        {
         if(m_htfStructure->HasBullishSetup()) score += 0.2;
         else if(m_htfStructure->HasBearishSetup()) score -= 0.2;
        }

      double bullThreshold = GetBullThreshold();
      double bearThreshold = -GetBullThreshold();   // symmetric

      if(score >= bullThreshold)
        {
         isBull = true;
         return score;
        }
      if(score <= bearThreshold)
        {
         isBear = true;
         return MathAbs(score);
        }

      return 0.0;
     }

   //--- Evaluate M15 setup: BOS/CHOCH + OB/FVG
   double EvaluateSetup(bool &isBull, bool &isBear)
     {
      isBull = false;
      isBear = false;

      if(m_setupStructure == NULL) return 0.0;

      double score    = 0.0;
      double price    = iClose(m_symbol, m_setupTF, 1);

      ENUM_MS_SIGNAL sig = m_setupStructure->GetLastSignal();

      // BOS/CHOCH
      if(sig == MS_BOS_BULL || sig == MS_CHOCH_BULL || sig == MS_LIQ_SWEEP_L)
        {
         score += 0.4;
         isBull = true;
        }
      else if(sig == MS_BOS_BEAR || sig == MS_CHOCH_BEAR || sig == MS_LIQ_SWEEP_H)
        {
         score += 0.4;
         isBear = true;
        }

      // OB confluence
      if(isBull && m_setupStructure->IsPriceInBullishOB(price)) score += 0.3;
      if(isBear && m_setupStructure->IsPriceInBearishOB(price)) score += 0.3;

      // FVG confluence
      if(isBull && m_setupStructure->IsPriceInBullFVG(price)) score += 0.3;
      if(isBear && m_setupStructure->IsPriceInBearFVG(price)) score += 0.3;

      // Normalise
      score = MathMin(score, 1.0);

      return score;
     }

   //--- Minimum required setup score per trade mode
   double GetMinScore() const
     {
      switch(m_tradeMode)
        {
         case TRADE_MODE_SAFE:       return 0.75;
         case TRADE_MODE_NORMAL:     return 0.55;
         case TRADE_MODE_AGGRESSIVE: return 0.35;
        }
      return 0.55;
     }

   //--- Minimum trend score to confirm trend
   double GetBullThreshold() const
     {
      switch(m_tradeMode)
        {
         case TRADE_MODE_SAFE:       return 0.70;
         case TRADE_MODE_NORMAL:     return 0.50;
         case TRADE_MODE_AGGRESSIVE: return 0.30;
        }
      return 0.50;
     }
  };
//+------------------------------------------------------------------+

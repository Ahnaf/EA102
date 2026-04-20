//+------------------------------------------------------------------+
//|                                                SignalEngine.mqh  |
//|                        EA102 v2 - XAUUSD Prop Firm EA            |
//| DUAL ENGINE: Continuation + Reversal (independent score-based)  |
//+------------------------------------------------------------------+
#ifndef SIGNALENGINE_MQH
#define SIGNALENGINE_MQH

#include "Utilities.mqh"
#include "MarketStructure.mqh"

//--- Continuation signal result
struct ContinuationSignal
  {
   ENUM_SIGNAL_DIR direction;
   double          score;       // 0.0 – 1.0
   string          reason;
  };

//--- Reversal signal result
struct ReversalSignal
  {
   ENUM_SIGNAL_DIR direction;
   double          score;       // 0.0 – 1.0
   string          reason;
   bool            liqSweep;   // Triggered by liquidity sweep?
   bool            choch;      // Change of character confirmed?
  };

//+------------------------------------------------------------------+
//| CSignalEngine — dual engine                                     |
//+------------------------------------------------------------------+
class CSignalEngine
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_htfTF;       // H1 — trend reference
   ENUM_TIMEFRAMES   m_setupTF;     // M15 — setup reference
   int               m_emaFast;
   int               m_emaSlow;
   int               m_rsiPeriod;
   ENUM_TRADE_MODE   m_tradeMode;
   CMarketStructure *m_htfMS;
   CMarketStructure *m_setupMS;

   //--- Score weights (continuation)
   static const double W_HTF_EMA       = 0.20;
   static const double W_HTF_STRUC     = 0.20;
   static const double W_OB            = 0.25;
   static const double W_FVG           = 0.12;
   static const double W_RSI           = 0.12;
   static const double W_CANDLE        = 0.11;

   //--- Score weights (reversal)
   static const double WR_LIQSWEEP     = 0.30;
   static const double WR_CHOCH        = 0.25;
   static const double WR_CANDLE       = 0.20;
   static const double WR_RSI          = 0.15;
   static const double WR_ATR_EXP      = 0.10;

   //--- Internal: strong bullish/bearish candle check
   bool IsStrongBullCandle(ENUM_TIMEFRAMES tf, int shift = 1) const
     {
      double body  = CandleBody(m_symbol, tf, shift);
      double range = CandleRange(m_symbol, tf, shift);
      double atr   = GetATR(m_symbol, tf, 14, shift);
      if(atr <= 0 || range <= 0) return false;
      // Bull: bullish candle, body >= 40% ATR, body >= 60% of range
      return IsBullishCandle(m_symbol, tf, shift)
          && body >= 0.40 * atr
          && body >= 0.55 * range;
     }

   bool IsStrongBearCandle(ENUM_TIMEFRAMES tf, int shift = 1) const
     {
      double body  = CandleBody(m_symbol, tf, shift);
      double range = CandleRange(m_symbol, tf, shift);
      double atr   = GetATR(m_symbol, tf, 14, shift);
      if(atr <= 0 || range <= 0) return false;
      return IsBearishCandle(m_symbol, tf, shift)
          && body >= 0.40 * atr
          && body >= 0.55 * range;
     }

   //--- Wick rejection: hammer / shooting star
   bool IsBullishRejection(ENUM_TIMEFRAMES tf, int shift = 1) const
     {
      double body  = CandleBody(m_symbol, tf, shift);
      double lwic  = CandleLowerWick(m_symbol, tf, shift);
      double range = CandleRange(m_symbol, tf, shift);
      if(range <= 0) return false;
      // Lower wick >= 2× body and >= 60% of range → hammer / pin
      return (lwic >= 2.0 * body) && (lwic >= 0.55 * range);
     }

   bool IsBearishRejection(ENUM_TIMEFRAMES tf, int shift = 1) const
     {
      double body  = CandleBody(m_symbol, tf, shift);
      double uwic  = CandleUpperWick(m_symbol, tf, shift);
      double range = CandleRange(m_symbol, tf, shift);
      if(range <= 0) return false;
      return (uwic >= 2.0 * body) && (uwic >= 0.55 * range);
     }

   //--- ATR expansion: current ATR vs recent average
   bool IsATRExpansion(ENUM_TIMEFRAMES tf, double multiplier = 1.5) const
     {
      double atr1 = GetATR(m_symbol, tf, 14, 1);
      double atr6 = GetATR(m_symbol, tf, 14, 6);  // Average reference
      if(atr6 <= 0) return false;
      return atr1 >= multiplier * atr6;
     }

public:
   CSignalEngine() : m_htfMS(NULL), m_setupMS(NULL) {}

   bool Init(const string symbol,
             ENUM_TIMEFRAMES htfTF, ENUM_TIMEFRAMES setupTF,
             int emaFast, int emaSlow, int rsiPeriod,
             ENUM_TRADE_MODE tradeMode,
             CMarketStructure *htfMS, CMarketStructure *setupMS)
     {
      m_symbol    = symbol;
      m_htfTF     = htfTF;
      m_setupTF   = setupTF;
      m_emaFast   = emaFast;
      m_emaSlow   = emaSlow;
      m_rsiPeriod = rsiPeriod;
      m_tradeMode = tradeMode;
      m_htfMS     = htfMS;
      m_setupMS   = setupMS;
      LogInfo("SignalEngine", StringFormat("Init | HTF=%s Setup=%s EMA=%d/%d RSI=%d Mode=%s",
              EnumToString(htfTF), EnumToString(setupTF), emaFast, emaSlow, rsiPeriod,
              EnumToString(tradeMode)));
      return true;
     }

   void SetTradeMode(ENUM_TRADE_MODE mode) { m_tradeMode = mode; }

   //+------------------------------------------------------------------+
   //| ENGINE 1: Continuation (trend-following, score-based)           |
   //| Returns score for the given direction. Call for BUY and SELL,   |
   //| take the higher one (or the one matching HTF trend).            |
   //+------------------------------------------------------------------+
   ContinuationSignal GetContinuationSignal(ENUM_SIGNAL_DIR dir) const
     {
      ContinuationSignal sig;
      sig.direction = dir;
      sig.score     = 0;
      sig.reason    = "";

      if(dir == SIGNAL_NONE || m_htfMS == NULL || m_setupMS == NULL)
         return sig;

      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      string rstr  = "";
      double sc    = 0;

      //--- 1. HTF EMA alignment (W=0.20)
      double emaFast = GetEMA(m_symbol, m_htfTF, m_emaFast, 1);
      double emaSlow = GetEMA(m_symbol, m_htfTF, m_emaSlow, 1);
      if(dir == SIGNAL_BUY  && emaFast > emaSlow) { sc += W_HTF_EMA; rstr += "EMA↑ "; }
      if(dir == SIGNAL_SELL && emaFast < emaSlow) { sc += W_HTF_EMA; rstr += "EMA↓ "; }
      // Partial credit: price above/below slow EMA
      double ema50pct = W_HTF_EMA * 0.5;
      if(dir == SIGNAL_BUY  && price > emaSlow && emaFast <= emaSlow) { sc += ema50pct; rstr += "EMA½↑ "; }
      if(dir == SIGNAL_SELL && price < emaSlow && emaFast >= emaSlow) { sc += ema50pct; rstr += "EMA½↓ "; }

      //--- 2. HTF Structure BOS (W=0.20)
      if(dir == SIGNAL_BUY  && m_htfMS.HasBOSBull()) { sc += W_HTF_STRUC; rstr += "HTF-BOS↑ "; }
      if(dir == SIGNAL_SELL && m_htfMS.HasBOSBear()) { sc += W_HTF_STRUC; rstr += "HTF-BOS↓ "; }
      // Partial: bullish/bearish structure maintained
      if(dir == SIGNAL_BUY  && m_htfMS.HasBullishStructure() && !m_htfMS.HasBOSBull())  { sc += W_HTF_STRUC * 0.5; rstr += "HTFStrc↑ "; }
      if(dir == SIGNAL_SELL && m_htfMS.HasBearishStructure() && !m_htfMS.HasBOSBear())  { sc += W_HTF_STRUC * 0.5; rstr += "HTFStrc↓ "; }

      //--- 3. M15 Price in Order Block (W=0.25)
      if(dir == SIGNAL_BUY  && m_setupMS.IsPriceInBullishOB(price)) { sc += W_OB; rstr += "inBullOB "; }
      if(dir == SIGNAL_SELL && m_setupMS.IsPriceInBearishOB(price)) { sc += W_OB; rstr += "inBearOB "; }

      //--- 4. M15 Price in FVG (W=0.12)
      if(dir == SIGNAL_BUY  && m_setupMS.IsPriceInBullFVG(price)) { sc += W_FVG; rstr += "inFVG↑ "; }
      if(dir == SIGNAL_SELL && m_setupMS.IsPriceInBearFVG(price)) { sc += W_FVG; rstr += "inFVG↓ "; }

      //--- 5. RSI momentum (W=0.12)
      double rsi = GetRSI(m_symbol, m_htfTF, m_rsiPeriod, 1);
      if(dir == SIGNAL_BUY  && rsi > 50 && rsi < 70) { sc += W_RSI; rstr += "RSI↑ "; }
      if(dir == SIGNAL_SELL && rsi < 50 && rsi > 30) { sc += W_RSI; rstr += "RSI↓ "; }

      //--- 6. M15 Setup candle strength (W=0.11)
      if(dir == SIGNAL_BUY  && IsStrongBullCandle(m_setupTF, 1)) { sc += W_CANDLE; rstr += "SBull "; }
      if(dir == SIGNAL_SELL && IsStrongBearCandle(m_setupTF, 1)) { sc += W_CANDLE; rstr += "SBear "; }

      sig.score  = Clamp(sc, 0, 1.0);
      sig.reason = rstr;
      return sig;
     }

   //+------------------------------------------------------------------+
   //| ENGINE 2: Reversal (counter-trend, liquidity + exhaustion)      |
   //| Independently scores BOTH directions and returns the best one.  |
   //| Fires even when HTF trend shows old bias.                       |
   //+------------------------------------------------------------------+
   ReversalSignal GetReversalSignal() const
     {
      ReversalSignal sig;
      sig.direction = SIGNAL_NONE;
      sig.score     = 0;
      sig.reason    = "";
      sig.liqSweep  = false;
      sig.choch     = false;

      if(m_setupMS == NULL) return sig;

      double scBull = 0, scBear = 0;
      string rBull = "", rBear = "";
      bool   lsBull = false, lsBear = false;
      bool   chBull = false, chBear = false;

      //--- 1. Liquidity Sweep (W=0.30) — strongest reversal signal
      if(m_setupMS.IsLiquiditySweepBull()) { scBull += WR_LIQSWEEP; rBull += "LiqSwp↑ "; lsBull = true; }
      if(m_setupMS.IsLiquiditySweepBear()) { scBear += WR_LIQSWEEP; rBear += "LiqSwp↓ "; lsBear = true; }
      // Also check HTF liquidity sweeps
      if(m_htfMS != NULL)
        {
         if(m_htfMS.IsLiquiditySweepBull() && scBull < WR_LIQSWEEP) { scBull += WR_LIQSWEEP * 0.6; rBull += "HTFSwp↑ "; }
         if(m_htfMS.IsLiquiditySweepBear() && scBear < WR_LIQSWEEP) { scBear += WR_LIQSWEEP * 0.6; rBear += "HTFSwp↓ "; }
        }

      //--- 2. CHOCH — change of character (W=0.25)
      if(m_setupMS.HasCHOCHBull()) { scBull += WR_CHOCH; rBull += "CHOCH↑ "; chBull = true; }
      if(m_setupMS.HasCHOCHBear()) { scBear += WR_CHOCH; rBear += "CHOCH↓ "; chBear = true; }

      //--- 3. Candle: strong engulfing or wick rejection (W=0.20)
      // Check M15 and entry TF candles
      bool strongBull = IsStrongBullCandle(m_setupTF, 1) || IsBullishRejection(m_setupTF, 1)
                     || IsStrongBullCandle(m_setupTF, 2) || IsBullishRejection(m_setupTF, 2);
      bool strongBear = IsStrongBearCandle(m_setupTF, 1) || IsBearishRejection(m_setupTF, 1)
                     || IsStrongBearCandle(m_setupTF, 2) || IsBearishRejection(m_setupTF, 2);

      if(strongBull) { scBull += WR_CANDLE; rBull += "StrongCandle↑ "; }
      if(strongBear) { scBear += WR_CANDLE; rBear += "StrongCandle↓ "; }

      //--- 4. RSI extreme / momentum flip (W=0.15)
      double rsiSetup = GetRSI(m_symbol, m_setupTF, m_rsiPeriod, 1);
      double rsiPrev  = GetRSI(m_symbol, m_setupTF, m_rsiPeriod, 3);  // 3 bars ago

      // Bull reversal: was oversold, now recovering
      if(rsiSetup < 35 || (rsiPrev < 30 && rsiSetup > rsiPrev))
        { scBull += WR_RSI; rBull += "RSI-OS "; }
      // Bear reversal: was overbought, now falling
      if(rsiSetup > 65 || (rsiPrev > 70 && rsiSetup < rsiPrev))
        { scBear += WR_RSI; rBear += "RSI-OB "; }

      //--- 5. ATR expansion spike (W=0.10)
      if(IsATRExpansion(m_setupTF, 1.5))
        {
         // Direction of spike by the strongly expanding candle's bias
         if(IsBullishCandle(m_symbol, m_setupTF, 1)) { scBull += WR_ATR_EXP; rBull += "ATR-Exp↑ "; }
         else                                         { scBear += WR_ATR_EXP; rBear += "ATR-Exp↓ "; }
        }

      // Pick winning direction
      scBull = Clamp(scBull, 0, 1.0);
      scBear = Clamp(scBear, 0, 1.0);

      if(scBull >= scBear && scBull > 0)
        {
         sig.direction = SIGNAL_BUY;
         sig.score     = scBull;
         sig.reason    = rBull;
         sig.liqSweep  = lsBull;
         sig.choch     = chBull;
        }
      else if(scBear > scBull && scBear > 0)
        {
         sig.direction = SIGNAL_SELL;
         sig.score     = scBear;
         sig.reason    = rBear;
         sig.liqSweep  = lsBear;
         sig.choch     = chBear;
        }

      return sig;
     }

   //--- Expose last RSI for external use (e.g. ExitManager)
   double GetSetupRSI() const { return GetRSI(m_symbol, m_setupTF, m_rsiPeriod, 1); }
   double GetHTF_EMAFast() const { return GetEMA(m_symbol, m_htfTF, m_emaFast, 1); }
   double GetHTF_EMASlow() const { return GetEMA(m_symbol, m_htfTF, m_emaSlow, 1); }
  };

#endif // SIGNALENGINE_MQH

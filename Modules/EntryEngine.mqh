//+------------------------------------------------------------------+
//|                                                  EntryEngine.mqh |
//|                          EA102 - XAUUSD Prop Firm EA             |
//|        M5 Entry Confirmation: Candle + Momentum + Location       |
//+------------------------------------------------------------------+
#pragma once
#include "Utilities.mqh"
#include "SignalEngine.mqh"

//--- Entry confirmation result
struct EntryConfirmation
  {
   bool             confirmed;
   ENUM_SIGNAL_DIR  direction;
   double           entryPrice;
   double           stopLoss;
   double           takeProfit;
   string           reason;
  };

//+------------------------------------------------------------------+
//| CEntryEngine — validates M5 entry candles (condition E)         |
//+------------------------------------------------------------------+
class CEntryEngine
  {
private:
   string              m_symbol;
   ENUM_TIMEFRAMES     m_entryTF;       // M5
   ENUM_TIMEFRAMES     m_setupTF;       // M15

   // Parameters
   int                 m_rsiPeriod;
   double              m_rsiOverbought;
   double              m_rsiOversold;
   double              m_engulfMinRatio; // Body ratio for engulfing (e.g. 1.5)
   double              m_atrPeriod;
   double              m_minBodyAtrRatio;// Min body / ATR ratio for strong candle (e.g. 0.3)

   // SL/TP modes
   int                 m_slMode;        // 0=Structure, 1=ATR
   double              m_slAtrMul;      // ATR multiplier for SL
   int                 m_tpMode;        // 0=Fixed RR, 1=Liquidity, 2=Hybrid
   double              m_rrRatio;       // Default RR ratio (e.g. 2.0)

   // Swing references for structure-based SL
   double              m_swingHigh;
   double              m_swingLow;

public:
   CEntryEngine() {}
   ~CEntryEngine() {}

   bool Init(const string    symbol,
             ENUM_TIMEFRAMES entryTF,
             ENUM_TIMEFRAMES setupTF,
             int             rsiPeriod,
             double          rsiOverbought,
             double          rsiOversold,
             double          engulfMinRatio,
             int             atrPeriod,
             double          minBodyAtrRatio,
             int             slMode,
             double          slAtrMul,
             int             tpMode,
             double          rrRatio)
     {
      m_symbol          = symbol;
      m_entryTF         = entryTF;
      m_setupTF         = setupTF;
      m_rsiPeriod       = rsiPeriod;
      m_rsiOverbought   = rsiOverbought;
      m_rsiOversold     = rsiOversold;
      m_engulfMinRatio  = engulfMinRatio;
      m_atrPeriod       = atrPeriod;
      m_minBodyAtrRatio = minBodyAtrRatio;
      m_slMode          = slMode;
      m_slAtrMul        = slAtrMul;
      m_tpMode          = tpMode;
      m_rrRatio         = rrRatio;
      m_swingHigh       = 0;
      m_swingLow        = DBL_MAX;

      LogInfo("EntryEngine", StringFormat(
         "Init | %s %s | RSI%d | SLMode=%d | TPMode=%d RR=%.1f",
         symbol, EnumToString(entryTF), rsiPeriod, slMode, tpMode, rrRatio));
      return true;
     }

   //--- Update swing references
   void SetSwings(double swingHigh, double swingLow)
     {
      m_swingHigh = swingHigh;
      m_swingLow  = swingLow;
     }

   //--- Main entry check — call after signal is valid
   EntryConfirmation CheckEntry(ENUM_SIGNAL_DIR direction)
     {
      EntryConfirmation ec;
      ec.confirmed  = false;
      ec.direction  = SIGNAL_NONE;
      ec.entryPrice = 0;
      ec.stopLoss   = 0;
      ec.takeProfit = 0;
      ec.reason     = "";

      if(direction == SIGNAL_NONE) return ec;

      double atr = GetATR(m_symbol, m_entryTF, (int)m_atrPeriod, 1);
      if(atr == 0)
        {
         ec.reason = "ATR=0";
         return ec;
        }

      bool candleOK = false, momentumOK = false;
      string candleReason = "", momReason = "";

      if(direction == SIGNAL_BUY)
        {
         candleOK  = IsBullishEntryCandle(atr, candleReason);
         momentumOK = IsBullishMomentum(momReason);
        }
      else
        {
         candleOK  = IsBearishEntryCandle(atr, candleReason);
         momentumOK = IsBearishMomentum(momReason);
        }

      if(!candleOK)
        {
         ec.reason = "Candle: " + candleReason;
         return ec;
        }

      if(!momentumOK)
        {
         ec.reason = "Momentum: " + momReason;
         return ec;
        }

      // === Entry price (next bar open = market order) ===
      bool   isBuy    = (direction == SIGNAL_BUY);
      double entryPrice = isBuy
                          ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                          : SymbolInfoDouble(m_symbol, SYMBOL_BID);

      // === Stop Loss ===
      double sl = CalculateSL(direction, entryPrice, atr);
      if(sl == 0)
        {
         ec.reason = "SL calc failed";
         return ec;
        }

      // === Take Profit ===
      double tp = CalculateTP(direction, entryPrice, sl);

      // Sanity check: SL and TP on correct sides
      if(isBuy  && (sl >= entryPrice || (tp > 0 && tp <= entryPrice)))
        {
         ec.reason = "SL/TP sanity fail (BUY)";
         return ec;
        }
      if(!isBuy && (sl <= entryPrice || (tp > 0 && tp >= entryPrice)))
        {
         ec.reason = "SL/TP sanity fail (SELL)";
         return ec;
        }

      ec.confirmed  = true;
      ec.direction  = direction;
      ec.entryPrice = entryPrice;
      ec.stopLoss   = sl;
      ec.takeProfit = tp;
      ec.reason     = StringFormat("Candle OK + Momentum OK | Entry=%.5f SL=%.5f TP=%.5f",
                                    entryPrice, sl, tp);

      LogInfo("EntryEngine", ec.reason);
      return ec;
     }

private:
   //--- Bullish candle confirmation: engulfing or strong momentum candle
   bool IsBullishEntryCandle(double atr, string &reason)
     {
      double o1 = iOpen(m_symbol,  m_entryTF, 1);
      double c1 = iClose(m_symbol, m_entryTF, 1);
      double o2 = iOpen(m_symbol,  m_entryTF, 2);
      double c2 = iClose(m_symbol, m_entryTF, 2);
      double h1 = iHigh(m_symbol,  m_entryTF, 1);
      double l1 = iLow(m_symbol,   m_entryTF, 1);

      // Must be bullish
      if(c1 <= o1)
        {
         reason = "Bar[1] not bullish";
         return false;
        }

      double body1 = c1 - o1;
      double body2 = MathAbs(c2 - o2);

      // Option 1: Bullish engulfing — body1 engulfs body2
      bool isEngulfing = (o1 <= MathMin(o2, c2) && c1 >= MathMax(o2, c2));
      if(isEngulfing && body2 > 0 && body1 / body2 >= m_engulfMinRatio)
        {
         reason = "Bullish Engulfing";
         return true;
        }

      // Option 2: Strong single bar (body > minBodyAtrRatio * ATR)
      if(body1 >= m_minBodyAtrRatio * atr)
        {
         // Lower wick confirms buying pressure from lower area
         double lowerWick = o1 - l1;   // Bar body started above low
         if(lowerWick >= 0)
           {
            reason = StringFormat("Strong Bull Bar body=%.5f atr=%.5f", body1, atr);
            return true;
           }
        }

      reason = "No bullish candle pattern";
      return false;
     }

   //--- Bearish candle confirmation
   bool IsBearishEntryCandle(double atr, string &reason)
     {
      double o1 = iOpen(m_symbol,  m_entryTF, 1);
      double c1 = iClose(m_symbol, m_entryTF, 1);
      double o2 = iOpen(m_symbol,  m_entryTF, 2);
      double c2 = iClose(m_symbol, m_entryTF, 2);
      double h1 = iHigh(m_symbol,  m_entryTF, 1);

      if(c1 >= o1)
        {
         reason = "Bar[1] not bearish";
         return false;
        }

      double body1 = o1 - c1;
      double body2 = MathAbs(c2 - o2);

      bool isEngulfing = (o1 >= MathMax(o2, c2) && c1 <= MathMin(o2, c2));
      if(isEngulfing && body2 > 0 && body1 / body2 >= m_engulfMinRatio)
        {
         reason = "Bearish Engulfing";
         return true;
        }

      if(body1 >= m_minBodyAtrRatio * atr)
        {
         double upperWick = h1 - o1;
         if(upperWick >= 0)
           {
            reason = StringFormat("Strong Bear Bar body=%.5f atr=%.5f", body1, atr);
            return true;
           }
        }

      reason = "No bearish candle pattern";
      return false;
     }

   //--- RSI momentum aligned for buy
   bool IsBullishMomentum(string &reason)
     {
      double rsi = GetRSI(m_symbol, m_entryTF, m_rsiPeriod, 1);
      if(rsi >= 50.0 && rsi < m_rsiOverbought)
        {
         reason = StringFormat("RSI=%.1f (bullish zone)", rsi);
         return true;
        }
      // Also accept RSI bouncing from oversold
      double rsiPrev = GetRSI(m_symbol, m_entryTF, m_rsiPeriod, 2);
      if(rsiPrev < m_rsiOversold && rsi > rsiPrev)
        {
         reason = StringFormat("RSI bounce from oversold (%.1f→%.1f)", rsiPrev, rsi);
         return true;
        }
      reason = StringFormat("RSI=%.1f not bullish", rsi);
      return false;
     }

   //--- RSI momentum aligned for sell
   bool IsBearishMomentum(string &reason)
     {
      double rsi = GetRSI(m_symbol, m_entryTF, m_rsiPeriod, 1);
      if(rsi <= 50.0 && rsi > m_rsiOversold)
        {
         reason = StringFormat("RSI=%.1f (bearish zone)", rsi);
         return true;
        }
      double rsiPrev = GetRSI(m_symbol, m_entryTF, m_rsiPeriod, 2);
      if(rsiPrev > m_rsiOverbought && rsi < rsiPrev)
        {
         reason = StringFormat("RSI reject from overbought (%.1f→%.1f)", rsiPrev, rsi);
         return true;
        }
      reason = StringFormat("RSI=%.1f not bearish", rsi);
      return false;
     }

   //--- Calculate stop loss
   double CalculateSL(ENUM_SIGNAL_DIR dir, double entryPrice, double atr)
     {
      bool   isBuy  = (dir == SIGNAL_BUY);
      double sl     = 0;

      if(m_slMode == 0)
        {
         // Structure-based SL: below swing low (buy) or above swing high (sell)
         if(isBuy)
           {
            sl = (m_swingLow < DBL_MAX && m_swingLow > 0)
                 ? m_swingLow - atr * 0.3   // Small buffer below swing low
                 : entryPrice - atr * m_slAtrMul;
           }
         else
           {
            sl = (m_swingHigh > 0)
                 ? m_swingHigh + atr * 0.3
                 : entryPrice + atr * m_slAtrMul;
           }
        }
      else
        {
         // ATR-based SL
         sl = isBuy
              ? entryPrice - atr * m_slAtrMul
              : entryPrice + atr * m_slAtrMul;
        }

      // Ensure minimum distance from entry
      double minDist = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL)
                       * SymbolInfoDouble(m_symbol, SYMBOL_POINT);

      if(isBuy  && entryPrice - sl < minDist)
         sl = entryPrice - minDist;
      if(!isBuy && sl - entryPrice < minDist)
         sl = entryPrice + minDist;

      return NormalizeDouble(sl, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
     }

   //--- Calculate take profit
   double CalculateTP(ENUM_SIGNAL_DIR dir, double entryPrice, double sl)
     {
      bool   isBuy  = (dir == SIGNAL_BUY);
      double slDist = MathAbs(entryPrice - sl);
      double tp     = 0;

      if(m_tpMode == 0)
        {
         // Fixed RR
         tp = isBuy
              ? entryPrice + slDist * m_rrRatio
              : entryPrice - slDist * m_rrRatio;
        }
      else if(m_tpMode == 1)
        {
         // Liquidity target: use swing high for buys, swing low for sells
         if(isBuy && m_swingHigh > 0)
            tp = m_swingHigh;
         else if(!isBuy && m_swingLow < DBL_MAX)
            tp = m_swingLow;
         else
            tp = isBuy
                 ? entryPrice + slDist * m_rrRatio
                 : entryPrice - slDist * m_rrRatio;
        }
      else
        {
         // Hybrid: take the better of fixed RR and liquidity
         double fixedTP = isBuy
                          ? entryPrice + slDist * m_rrRatio
                          : entryPrice - slDist * m_rrRatio;
         double liqTP   = 0;
         if(isBuy && m_swingHigh > 0)  liqTP = m_swingHigh;
         if(!isBuy && m_swingLow < DBL_MAX) liqTP = m_swingLow;

         if(liqTP == 0)
            tp = fixedTP;
         else
            tp = isBuy ? MathMax(fixedTP, liqTP) : MathMin(fixedTP, liqTP);
        }

      return NormalizeDouble(tp, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
     }
  };
//+------------------------------------------------------------------+

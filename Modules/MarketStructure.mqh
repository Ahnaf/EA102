//+------------------------------------------------------------------+
//|                                               MarketStructure.mqh|
//|                          EA102 - XAUUSD Prop Firm EA             |
//|    BOS / CHOCH / Liquidity Sweep / Order Blocks / FVG Detection  |
//+------------------------------------------------------------------+
#pragma once
#include "Utilities.mqh"

//--- Structure type
enum ENUM_MS_SIGNAL
  {
   MS_NONE        = 0,
   MS_BOS_BULL    = 1,   // Bullish Break of Structure
   MS_BOS_BEAR    = 2,   // Bearish Break of Structure
   MS_CHOCH_BULL  = 3,   // Bullish Change of Character
   MS_CHOCH_BEAR  = 4,   // Bearish Change of Character
   MS_LIQ_SWEEP_H = 5,   // Liquidity Sweep of swing high
   MS_LIQ_SWEEP_L = 6,   // Liquidity Sweep of swing low
  };

//--- Order Block structure
struct OrderBlock
  {
   double   high;
   double   low;
   bool     isBullish;   // Bullish OB = bearish candle before bullish move
   datetime time;
   bool     active;
  };

//--- Fair Value Gap structure
struct FVG
  {
   double   upper;
   double   lower;
   bool     isBullish;
   datetime time;
   bool     active;
  };

//+------------------------------------------------------------------+
//| CMarketStructure class                                           |
//+------------------------------------------------------------------+
class CMarketStructure
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_lookback;       // Bars to look back for structure
   int               m_swingStrength;  // Min bars on each side for swing

   // Current structure state
   double            m_lastSwingHigh;
   double            m_lastSwingLow;
   double            m_prevSwingHigh;
   double            m_prevSwingLow;
   datetime          m_lastSwingHighTime;
   datetime          m_lastSwingLowTime;

   // Detected signals
   ENUM_MS_SIGNAL    m_lastSignal;
   datetime          m_lastSignalTime;

   // Order blocks (store up to 5)
   OrderBlock        m_orderBlocks[5];
   int               m_obCount;

   // FVGs (store up to 5)
   FVG               m_fvgs[5];
   int               m_fvgCount;

public:
   CMarketStructure() : m_lastSignal(MS_NONE), m_obCount(0), m_fvgCount(0) {}
   ~CMarketStructure() {}

   bool Init(const string symbol, ENUM_TIMEFRAMES tf, int lookback = 100, int swingStrength = 3)
     {
      m_symbol       = symbol;
      m_tf           = tf;
      m_lookback     = lookback;
      m_swingStrength = swingStrength;
      m_lastSwingHigh = 0;
      m_lastSwingLow  = DBL_MAX;
      m_prevSwingHigh = 0;
      m_prevSwingLow  = DBL_MAX;
      m_lastSignalTime= 0;

      LogInfo("MarketStructure", StringFormat(
         "Init | %s %s | Lookback=%d | SwingStr=%d",
         symbol, EnumToString(tf), lookback, swingStrength));
      return true;
     }

   //--- Master update — call once per bar
   void Update()
     {
      DetectSwings();
      DetectBOSandCHOCH();
      DetectLiquiditySweep();
      DetectOrderBlocks();
      DetectFVG();
     }

   //--- === SWING DETECTION ===
   void DetectSwings()
     {
      int bars = MathMin(m_lookback, iBars(m_symbol, m_tf) - m_swingStrength - 1);

      for(int i = m_swingStrength + 1; i < bars; i++)
        {
         // Check swing high: bar[i] is higher than m_swingStrength bars on each side
         double hi = iHigh(m_symbol, m_tf, i);
         bool   isSwingHigh = true;
         bool   isSwingLow  = true;

         for(int j = 1; j <= m_swingStrength; j++)
           {
            if(iHigh(m_symbol, m_tf, i - j) >= hi) { isSwingHigh = false; break; }
           }
         if(isSwingHigh)
           {
            for(int j = 1; j <= m_swingStrength; j++)
              {
               if(iHigh(m_symbol, m_tf, i + j) >= hi) { isSwingHigh = false; break; }
              }
           }

         double lo = iLow(m_symbol, m_tf, i);
         for(int j = 1; j <= m_swingStrength; j++)
           {
            if(iLow(m_symbol, m_tf, i - j) <= lo) { isSwingLow = false; break; }
           }
         if(isSwingLow)
           {
            for(int j = 1; j <= m_swingStrength; j++)
              {
               if(iLow(m_symbol, m_tf, i + j) <= lo) { isSwingLow = false; break; }
              }
           }

         if(isSwingHigh)
           {
            datetime t = iTime(m_symbol, m_tf, i);
            if(t != m_lastSwingHighTime)
              {
               m_prevSwingHigh     = m_lastSwingHigh;
               m_lastSwingHigh     = hi;
               m_lastSwingHighTime = t;
              }
           }

         if(isSwingLow)
           {
            datetime t = iTime(m_symbol, m_tf, i);
            if(t != m_lastSwingLowTime)
              {
               m_prevSwingLow     = m_lastSwingLow;
               m_lastSwingLow     = lo;
               m_lastSwingLowTime = t;
              }
           }
        }
     }

   //--- === BOS / CHOCH DETECTION ===
   void DetectBOSandCHOCH()
     {
      double closeNow  = iClose(m_symbol, m_tf, 1);
      datetime tNow    = iTime(m_symbol, m_tf, 1);

      if(tNow == m_lastSignalTime) return;

      // Bullish BOS: price closes above last swing high (continuation of uptrend)
      if(m_lastSwingHigh > 0 && closeNow > m_lastSwingHigh && m_prevSwingHigh > 0)
        {
         // If we were in a downtrend (LH), this is a CHOCH; otherwise BOS
         bool wasBearish = (m_lastSwingHigh < m_prevSwingHigh);
         m_lastSignal     = wasBearish ? MS_CHOCH_BULL : MS_BOS_BULL;
         m_lastSignalTime = tNow;
         LogDebug("MarketStructure", StringFormat(
            "%s detected | Price=%.5f | SwingHigh=%.5f",
            m_lastSignal == MS_CHOCH_BULL ? "CHOCH_BULL" : "BOS_BULL",
            closeNow, m_lastSwingHigh));
         return;
        }

      // Bearish BOS: price closes below last swing low (continuation of downtrend)
      if(m_lastSwingLow < DBL_MAX && closeNow < m_lastSwingLow && m_prevSwingLow < DBL_MAX)
        {
         bool wasBullish = (m_lastSwingLow > m_prevSwingLow);
         m_lastSignal     = wasBullish ? MS_CHOCH_BEAR : MS_BOS_BEAR;
         m_lastSignalTime = tNow;
         LogDebug("MarketStructure", StringFormat(
            "%s detected | Price=%.5f | SwingLow=%.5f",
            m_lastSignal == MS_CHOCH_BEAR ? "CHOCH_BEAR" : "BOS_BEAR",
            closeNow, m_lastSwingLow));
         return;
        }

      m_lastSignal = MS_NONE;
     }

   //--- === LIQUIDITY SWEEP DETECTION ===
   void DetectLiquiditySweep()
     {
      // A sweep: price wicks past a swing level but closes back inside
      double hi    = iHigh(m_symbol,  m_tf, 1);
      double lo    = iLow(m_symbol,   m_tf, 1);
      double close = iClose(m_symbol, m_tf, 1);

      // Sweep of swing high (hunt stops above, then close back below)
      if(m_lastSwingHigh > 0 && hi > m_lastSwingHigh && close < m_lastSwingHigh)
        {
         m_lastSignal     = MS_LIQ_SWEEP_H;
         m_lastSignalTime = iTime(m_symbol, m_tf, 1);
         LogDebug("MarketStructure", StringFormat(
            "LIQ_SWEEP_H | Hi=%.5f > SwingH=%.5f | Close=%.5f",
            hi, m_lastSwingHigh, close));
         return;
        }

      // Sweep of swing low
      if(m_lastSwingLow < DBL_MAX && lo < m_lastSwingLow && close > m_lastSwingLow)
        {
         m_lastSignal     = MS_LIQ_SWEEP_L;
         m_lastSignalTime = iTime(m_symbol, m_tf, 1);
         LogDebug("MarketStructure", StringFormat(
            "LIQ_SWEEP_L | Lo=%.5f < SwingL=%.5f | Close=%.5f",
            lo, m_lastSwingLow, close));
         return;
        }
     }

   //--- === ORDER BLOCK DETECTION ===
   //--- OB = last bearish candle before a bullish impulse (bullish OB)
   //---      last bullish candle before a bearish impulse (bearish OB)
   void DetectOrderBlocks()
     {
      if(m_obCount >= 5) return;

      // Look at bar[2]: if bar[1] is a strong impulse and bar[2] is opposite
      bool bar1Bull = IsBullishCandle(m_symbol, m_tf, 1);
      bool bar2Bull = IsBullishCandle(m_symbol, m_tf, 2);

      double bar1Body = MathAbs(iClose(m_symbol, m_tf, 1) - iOpen(m_symbol, m_tf, 1));
      double bar2Body = MathAbs(iClose(m_symbol, m_tf, 2) - iOpen(m_symbol, m_tf, 2));

      double atr = GetATR(m_symbol, m_tf, 14, 1);
      if(atr == 0) return;

      // Strong impulse = body > 0.5 * ATR
      bool bar1Strong = (bar1Body > atr * 0.5);

      if(bar1Strong && bar1Bull && !bar2Bull)
        {
         // Bearish bar[2] before bullish impulse = Bullish OB
         OrderBlock ob;
         ob.high      = iHigh(m_symbol, m_tf, 2);
         ob.low       = iLow(m_symbol, m_tf, 2);
         ob.isBullish = true;
         ob.time      = iTime(m_symbol, m_tf, 2);
         ob.active    = true;

         // Check not duplicate
         bool dup = false;
         for(int i = 0; i < m_obCount; i++)
            if(MathAbs(m_orderBlocks[i].high - ob.high) < SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 10)
              { dup = true; break; }

         if(!dup)
           {
            m_orderBlocks[m_obCount++] = ob;
            LogDebug("MarketStructure", StringFormat(
               "Bullish OB: %.5f-%.5f", ob.low, ob.high));
           }
        }

      if(bar1Strong && !bar1Bull && bar2Bull)
        {
         // Bullish bar[2] before bearish impulse = Bearish OB
         OrderBlock ob;
         ob.high      = iHigh(m_symbol, m_tf, 2);
         ob.low       = iLow(m_symbol, m_tf, 2);
         ob.isBullish = false;
         ob.time      = iTime(m_symbol, m_tf, 2);
         ob.active    = true;

         bool dup = false;
         for(int i = 0; i < m_obCount; i++)
            if(MathAbs(m_orderBlocks[i].high - ob.high) < SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 10)
              { dup = true; break; }

         if(!dup)
           {
            m_orderBlocks[m_obCount++] = ob;
            LogDebug("MarketStructure", StringFormat(
               "Bearish OB: %.5f-%.5f", ob.low, ob.high));
           }
        }
     }

   //--- === FVG DETECTION ===
   //--- FVG (3-candle pattern): gap between bar[3].high and bar[1].low (bull)
   //---                         gap between bar[3].low and bar[1].high (bear)
   void DetectFVG()
     {
      if(m_fvgCount >= 5) return;

      double hi1 = iHigh(m_symbol, m_tf, 1);
      double lo1 = iLow(m_symbol,  m_tf, 1);
      double hi3 = iHigh(m_symbol, m_tf, 3);
      double lo3 = iLow(m_symbol,  m_tf, 3);

      // Bullish FVG: lo of bar1 > hi of bar3
      if(lo1 > hi3)
        {
         FVG fvg;
         fvg.upper     = lo1;
         fvg.lower     = hi3;
         fvg.isBullish = true;
         fvg.time      = iTime(m_symbol, m_tf, 2);
         fvg.active    = true;

         bool dup = false;
         for(int i = 0; i < m_fvgCount; i++)
            if(MathAbs(m_fvgs[i].upper - fvg.upper) < SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 10)
              { dup = true; break; }

         if(!dup)
           {
            m_fvgs[m_fvgCount++] = fvg;
            LogDebug("MarketStructure", StringFormat(
               "Bullish FVG: %.5f-%.5f", fvg.lower, fvg.upper));
           }
        }

      // Bearish FVG: hi of bar1 < lo of bar3
      if(hi1 < lo3)
        {
         FVG fvg;
         fvg.upper     = lo3;
         fvg.lower     = hi1;
         fvg.isBullish = false;
         fvg.time      = iTime(m_symbol, m_tf, 2);
         fvg.active    = true;

         bool dup = false;
         for(int i = 0; i < m_fvgCount; i++)
            if(MathAbs(m_fvgs[i].upper - fvg.upper) < SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 10)
              { dup = true; break; }

         if(!dup)
           {
            m_fvgs[m_fvgCount++] = fvg;
            LogDebug("MarketStructure", StringFormat(
               "Bearish FVG: %.5f-%.5f", fvg.lower, fvg.upper));
           }
        }
     }

   //--- === PUBLIC QUERIES ===

   ENUM_MS_SIGNAL GetLastSignal()     const { return m_lastSignal; }
   datetime       GetLastSignalTime() const { return m_lastSignalTime; }
   double         GetLastSwingHigh()  const { return m_lastSwingHigh; }
   double         GetLastSwingLow()   const { return m_lastSwingLow; }

   //--- Is price inside any bullish OB?
   bool IsPriceInBullishOB(double price) const
     {
      for(int i = 0; i < m_obCount; i++)
         if(m_orderBlocks[i].active && m_orderBlocks[i].isBullish)
            if(price >= m_orderBlocks[i].low && price <= m_orderBlocks[i].high)
               return true;
      return false;
     }

   //--- Is price inside any bearish OB?
   bool IsPriceInBearishOB(double price) const
     {
      for(int i = 0; i < m_obCount; i++)
         if(m_orderBlocks[i].active && !m_orderBlocks[i].isBullish)
            if(price >= m_orderBlocks[i].low && price <= m_orderBlocks[i].high)
               return true;
      return false;
     }

   //--- Is price inside any bullish FVG?
   bool IsPriceInBullFVG(double price) const
     {
      for(int i = 0; i < m_fvgCount; i++)
         if(m_fvgs[i].active && m_fvgs[i].isBullish)
            if(price >= m_fvgs[i].lower && price <= m_fvgs[i].upper)
               return true;
      return false;
     }

   //--- Is price inside any bearish FVG?
   bool IsPriceInBearFVG(double price) const
     {
      for(int i = 0; i < m_fvgCount; i++)
         if(m_fvgs[i].active && !m_fvgs[i].isBullish)
            if(price >= m_fvgs[i].lower && price <= m_fvgs[i].upper)
               return true;
      return false;
     }

   //--- Is last signal bullish setup?
   bool HasBullishSetup() const
     {
      return (m_lastSignal == MS_BOS_BULL  ||
              m_lastSignal == MS_CHOCH_BULL ||
              m_lastSignal == MS_LIQ_SWEEP_L);
     }

   //--- Is last signal bearish setup?
   bool HasBearishSetup() const
     {
      return (m_lastSignal == MS_BOS_BEAR  ||
              m_lastSignal == MS_CHOCH_BEAR ||
              m_lastSignal == MS_LIQ_SWEEP_H);
     }

   //--- Invalidate old order blocks that have been fully retested / breached
   void PruneStaleOBs()
     {
      double askPrice = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bidPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      for(int i = 0; i < m_obCount; i++)
        {
         if(!m_orderBlocks[i].active) continue;

         // Bullish OB invalidated if price breaks below OB low
         if(m_orderBlocks[i].isBullish && bidPrice < m_orderBlocks[i].low)
            m_orderBlocks[i].active = false;

         // Bearish OB invalidated if price breaks above OB high
         if(!m_orderBlocks[i].isBullish && askPrice > m_orderBlocks[i].high)
            m_orderBlocks[i].active = false;
        }

      // Prune filled FVGs
      for(int i = 0; i < m_fvgCount; i++)
        {
         if(!m_fvgs[i].active) continue;

         // Bullish FVG filled when price retraces into it fully
         if(m_fvgs[i].isBullish && bidPrice < m_fvgs[i].lower)
            m_fvgs[i].active = false;

         if(!m_fvgs[i].isBullish && askPrice > m_fvgs[i].upper)
            m_fvgs[i].active = false;
        }
     }

   //--- Get nearest bullish OB zone (returns false if none)
   bool GetNearestBullishOB(double &outLow, double &outHigh) const
     {
      double price  = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double minDist = DBL_MAX;
      bool   found  = false;

      for(int i = 0; i < m_obCount; i++)
        {
         if(!m_orderBlocks[i].active || !m_orderBlocks[i].isBullish) continue;
         double mid  = (m_orderBlocks[i].high + m_orderBlocks[i].low) / 2.0;
         double dist = MathAbs(price - mid);
         if(dist < minDist)
           {
            minDist  = dist;
            outLow   = m_orderBlocks[i].low;
            outHigh  = m_orderBlocks[i].high;
            found    = true;
           }
        }
      return found;
     }

   //--- Get nearest bearish OB zone
   bool GetNearestBearishOB(double &outLow, double &outHigh) const
     {
      double price  = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double minDist = DBL_MAX;
      bool   found  = false;

      for(int i = 0; i < m_obCount; i++)
        {
         if(!m_orderBlocks[i].active || m_orderBlocks[i].isBullish) continue;
         double mid  = (m_orderBlocks[i].high + m_orderBlocks[i].low) / 2.0;
         double dist = MathAbs(price - mid);
         if(dist < minDist)
           {
            minDist  = dist;
            outLow   = m_orderBlocks[i].low;
            outHigh  = m_orderBlocks[i].high;
            found    = true;
           }
        }
      return found;
     }

   //--- String summary for dashboard
   string GetStructureSummary() const
     {
      string sig = "";
      switch(m_lastSignal)
        {
         case MS_BOS_BULL:    sig = "BOS↑";   break;
         case MS_BOS_BEAR:    sig = "BOS↓";   break;
         case MS_CHOCH_BULL:  sig = "CHOCH↑"; break;
         case MS_CHOCH_BEAR:  sig = "CHOCH↓"; break;
         case MS_LIQ_SWEEP_H: sig = "LiqSwp↑"; break;
         case MS_LIQ_SWEEP_L: sig = "LiqSwp↓"; break;
         default:             sig = "None";
        }
      return StringFormat("Sig=%s SH=%.2f SL=%.2f OBs=%d FVGs=%d",
         sig, m_lastSwingHigh, m_lastSwingLow, m_obCount, m_fvgCount);
     }
  };
//+------------------------------------------------------------------+

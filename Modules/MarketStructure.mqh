//+------------------------------------------------------------------+
//|                                             MarketStructure.mqh  |
//|                        EA102 v2 - XAUUSD Prop Firm EA            |
//| SMC Engine: BOS, CHOCH, Liquidity Sweep, Order Blocks, FVGs     |
//+------------------------------------------------------------------+
#ifndef MARKETSTRUCTURE_MQH
#define MARKETSTRUCTURE_MQH

#include "Utilities.mqh"

#define MAX_OBS  10
#define MAX_FVGS 10

//--- Order Block zone
struct OBZone
  {
   double   high;
   double   low;
   bool     bullish;     // bullish OB = support, bearish OB = resistance
   bool     active;
   datetime time;
  };

//--- Fair Value Gap zone (3-candle imbalance)
struct FVGZone
  {
   double   high;         // Top of gap
   double   low;          // Bottom of gap
   bool     bullish;      // Bullish FVG = price should retrace down to fill
   bool     active;
   datetime time;
  };

//+------------------------------------------------------------------+
//| CMarketStructure — per timeframe                                 |
//+------------------------------------------------------------------+
class CMarketStructure
  {
private:
   string           m_symbol;
   ENUM_TIMEFRAMES  m_tf;
   int              m_lookback;     // Bars to analyse
   int              m_swingStr;     // Bars each side for pivot

   //--- Swing tracking
   double   m_lastSwingHigh;
   double   m_lastSwingLow;
   double   m_prevSwingHigh;
   double   m_prevSwingLow;

   //--- Structure state
   bool     m_buStrucValid;    // Bullish structure (HH + HL)
   bool     m_beStrucValid;    // Bearish structure (LL + LH)
   bool     m_lastBOSBull;     // Last BOS was bullish?
   bool     m_lastBOSBear;
   bool     m_lastCHOCHBull;   // Change of character upward?
   bool     m_lastCHOCHBear;

   //--- Liquidity sweep flags (set on Update, valid for one bar)
   bool     m_liqSweepBull;    // Swept a low then reversed up
   bool     m_liqSweepBear;    // Swept a high then reversed down

   //--- Order Blocks
   OBZone   m_obs[MAX_OBS];
   int      m_obCount;

   //--- FVGs
   FVGZone  m_fvgs[MAX_FVGS];
   int      m_fvgCount;

   //--- Helpers
   bool IsSwingHigh(int idx) const
     {
      for(int k = 1; k <= m_swingStr; k++)
        {
         if(iHigh(m_symbol, m_tf, idx) <= iHigh(m_symbol, m_tf, idx + k)) return false;
         if(iHigh(m_symbol, m_tf, idx) <= iHigh(m_symbol, m_tf, idx - k)) return false;
        }
      return true;
     }

   bool IsSwingLow(int idx) const
     {
      for(int k = 1; k <= m_swingStr; k++)
        {
         if(iLow(m_symbol, m_tf, idx) >= iLow(m_symbol, m_tf, idx + k)) return false;
         if(iLow(m_symbol, m_tf, idx) >= iLow(m_symbol, m_tf, idx - k)) return false;
        }
      return true;
     }

   void AddOB(double high, double low, bool bullish)
     {
      if(m_obCount >= MAX_OBS)
        {
         // Shift array left (drop oldest)
         for(int i = 0; i < MAX_OBS - 1; i++) m_obs[i] = m_obs[i + 1];
         m_obCount = MAX_OBS - 1;
        }
      m_obs[m_obCount].high    = high;
      m_obs[m_obCount].low     = low;
      m_obs[m_obCount].bullish = bullish;
      m_obs[m_obCount].active  = true;
      m_obs[m_obCount].time    = iTime(m_symbol, m_tf, 0);
      m_obCount++;
     }

   void AddFVG(double high, double low, bool bullish)
     {
      if(m_fvgCount >= MAX_FVGS)
        {
         for(int i = 0; i < MAX_FVGS - 1; i++) m_fvgs[i] = m_fvgs[i + 1];
         m_fvgCount = MAX_FVGS - 1;
        }
      m_fvgs[m_fvgCount].high    = high;
      m_fvgs[m_fvgCount].low     = low;
      m_fvgs[m_fvgCount].bullish = bullish;
      m_fvgs[m_fvgCount].active  = true;
      m_fvgs[m_fvgCount].time    = iTime(m_symbol, m_tf, 0);
      m_fvgCount++;
     }

public:
   CMarketStructure() : m_lastSwingHigh(0), m_lastSwingLow(0),
                        m_prevSwingHigh(0), m_prevSwingLow(0),
                        m_buStrucValid(false), m_beStrucValid(false),
                        m_lastBOSBull(false), m_lastBOSBear(false),
                        m_lastCHOCHBull(false), m_lastCHOCHBear(false),
                        m_liqSweepBull(false), m_liqSweepBear(false),
                        m_obCount(0), m_fvgCount(0) {}

   bool Init(const string symbol, ENUM_TIMEFRAMES tf, int lookback, int swingStr)
     {
      m_symbol   = symbol;
      m_tf       = tf;
      m_lookback = lookback;
      m_swingStr = MathMax(1, swingStr);
      LogInfo("MarketStructure", StringFormat("Init | TF=%s Lookback=%d SwingStr=%d",
              EnumToString(tf), lookback, swingStr));
      Update();   // Initial scan
      return true;
     }

   //+------------------------------------------------------------------+
   //| Main update — call on each new bar                              |
   //+------------------------------------------------------------------+
   void Update()
     {
      // Reset per-bar flags
      m_lastBOSBull   = false;
      m_lastBOSBear   = false;
      m_lastCHOCHBull = false;
      m_lastCHOCHBear = false;
      m_liqSweepBull  = false;
      m_liqSweepBear  = false;

      // Collect swing highs and lows
      double swingHighs[]; double swingHighTimes[];
      double swingLows[];  double swingLowTimes[];
      int    shCount = 0,  slCount = 0;
      ArrayResize(swingHighs, m_lookback);
      ArrayResize(swingLows,  m_lookback);

      int end = m_lookback + m_swingStr;
      for(int i = m_swingStr; i <= end; i++)
        {
         if(IsSwingHigh(i))
           {
            if(shCount < m_lookback) { swingHighs[shCount] = iHigh(m_symbol, m_tf, i); shCount++; }
           }
         if(IsSwingLow(i))
           {
            if(slCount < m_lookback) { swingLows[slCount] = iLow(m_symbol, m_tf, i); slCount++; }
           }
        }

      // Update tracked swings (most recent first — index 0 = newest)
      if(shCount >= 2)
        {
         m_prevSwingHigh = (m_lastSwingHigh > 0) ? m_lastSwingHigh : swingHighs[1];
         m_lastSwingHigh = swingHighs[0];
        }
      else if(shCount == 1)
        {
         m_prevSwingHigh = m_lastSwingHigh;
         m_lastSwingHigh = swingHighs[0];
        }

      if(slCount >= 2)
        {
         m_prevSwingLow = (m_lastSwingLow > 0) ? m_lastSwingLow : swingLows[1];
         m_lastSwingLow = swingLows[0];
        }
      else if(slCount == 1)
        {
         m_prevSwingLow = m_lastSwingLow;
         m_lastSwingLow = swingLows[0];
        }

      double close0 = iClose(m_symbol, m_tf, 1);  // Last closed bar
      double high0  = iHigh (m_symbol, m_tf, 1);
      double low0   = iLow  (m_symbol, m_tf, 1);

      // BOS (Break of Structure) — continuation breaks
      if(m_prevSwingHigh > 0 && close0 > m_prevSwingHigh)
        {
         m_lastBOSBull  = true;
         m_buStrucValid = true;
         m_beStrucValid = false;
         // Mark the last bearish candle before breakout as Bearish OB (resistance-turned-support)
         for(int i = 2; i <= 6; i++)
           {
            if(iClose(m_symbol, m_tf, i) < iOpen(m_symbol, m_tf, i))
              {
               AddOB(iHigh(m_symbol, m_tf, i), iLow(m_symbol, m_tf, i), true);
               break;
              }
           }
        }

      if(m_prevSwingLow > 0 && close0 < m_prevSwingLow)
        {
         m_lastBOSBear  = true;
         m_beStrucValid = true;
         m_buStrucValid = false;
         // Mark last bullish candle before breakdown as Bullish OB (support-turned-resistance)
         for(int i = 2; i <= 6; i++)
           {
            if(iClose(m_symbol, m_tf, i) > iOpen(m_symbol, m_tf, i))
              {
               AddOB(iHigh(m_symbol, m_tf, i), iLow(m_symbol, m_tf, i), false);
               break;
              }
           }
        }

      // CHOCH — change of character (break AGAINST current trend)
      if(m_beStrucValid && m_prevSwingHigh > 0 && close0 > m_prevSwingHigh)
        {
         m_lastCHOCHBull = true;   // Was bearish, now breaks up
        }
      if(m_buStrucValid && m_prevSwingLow > 0 && close0 < m_prevSwingLow)
        {
         m_lastCHOCHBear = true;   // Was bullish, now breaks down
        }

      // --- LIQUIDITY SWEEP DETECTION ---
      // Bull sweep: bar swept below a recent swing low AND closed back above it → reversal up
      if(m_lastSwingLow > 0 && low0 < m_lastSwingLow && close0 > m_lastSwingLow)
        {
         // Additional quality filter: the sweep candle must be bullish (close > open)
         if(IsBullishCandle(m_symbol, m_tf, 1))
            m_liqSweepBull = true;
        }
      // Also check bar[2] swept and bar[1] confirmed reversal
      if(!m_liqSweepBull && m_lastSwingLow > 0)
        {
         double low2 = iLow(m_symbol, m_tf, 2);
         if(low2 < m_lastSwingLow && close0 > m_lastSwingLow && IsBullishCandle(m_symbol, m_tf, 1))
            m_liqSweepBull = true;
        }

      // Bear sweep: bar swept above a recent swing high AND closed back below it → reversal down
      if(m_lastSwingHigh > 0 && high0 > m_lastSwingHigh && close0 < m_lastSwingHigh)
        {
         if(IsBearishCandle(m_symbol, m_tf, 1))
            m_liqSweepBear = true;
        }
      if(!m_liqSweepBear && m_lastSwingHigh > 0)
        {
         double high2 = iHigh(m_symbol, m_tf, 2);
         if(high2 > m_lastSwingHigh && close0 < m_lastSwingHigh && IsBearishCandle(m_symbol, m_tf, 1))
            m_liqSweepBear = true;
        }

      // --- FVG DETECTION --- (3-candle imbalance pattern)
      // Bullish FVG: bar[3].high < bar[1].low  (gap between candle 3 and candle 1)
      if(iHigh(m_symbol, m_tf, 3) < iLow(m_symbol, m_tf, 1))
        AddFVG(iLow(m_symbol, m_tf, 1), iHigh(m_symbol, m_tf, 3), true);

      // Bearish FVG: bar[3].low > bar[1].high
      if(iLow(m_symbol, m_tf, 3) > iHigh(m_symbol, m_tf, 1))
        AddFVG(iHigh(m_symbol, m_tf, 1), iLow(m_symbol, m_tf, 3), false);
     }

   //--- Prune stale / breached OBs and filled FVGs
   void PruneStaleOBs()
     {
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      for(int i = 0; i < m_obCount; i++)
        {
         if(!m_obs[i].active) continue;
         // Bullish OB broken if price closes below its low
         if( m_obs[i].bullish && bid < m_obs[i].low)  m_obs[i].active = false;
         // Bearish OB broken if price closes above its high
         if(!m_obs[i].bullish && bid > m_obs[i].high) m_obs[i].active = false;
        }
      for(int i = 0; i < m_fvgCount; i++)
        {
         if(!m_fvgs[i].active) continue;
         // FVG considered filled when price moves through it
         if(m_fvgs[i].bullish  && bid < m_fvgs[i].low)  m_fvgs[i].active = false;
         if(!m_fvgs[i].bullish && bid > m_fvgs[i].high) m_fvgs[i].active = false;
        }
     }

   //+------------------------------------------------------------------+
   //| Query methods                                                    |
   //+------------------------------------------------------------------+
   bool HasBOSBull()   const { return m_lastBOSBull;   }
   bool HasBOSBear()   const { return m_lastBOSBear;   }
   bool HasCHOCHBull() const { return m_lastCHOCHBull; }
   bool HasCHOCHBear() const { return m_lastCHOCHBear; }
   bool HasBullishStructure() const { return m_buStrucValid; }
   bool HasBearishStructure() const { return m_beStrucValid; }

   bool IsLiquiditySweepBull() const { return m_liqSweepBull; }
   bool IsLiquiditySweepBear() const { return m_liqSweepBear; }

   double GetLastSwingHigh() const { return m_lastSwingHigh; }
   double GetLastSwingLow()  const { return m_lastSwingLow;  }
   double GetPrevSwingHigh() const { return m_prevSwingHigh; }
   double GetPrevSwingLow()  const { return m_prevSwingLow;  }

   bool IsPriceInBullishOB(double price) const
     {
      for(int i = 0; i < m_obCount; i++)
         if(m_obs[i].active && m_obs[i].bullish && price >= m_obs[i].low && price <= m_obs[i].high)
            return true;
      return false;
     }

   bool IsPriceInBearishOB(double price) const
     {
      for(int i = 0; i < m_obCount; i++)
         if(m_obs[i].active && !m_obs[i].bullish && price >= m_obs[i].low && price <= m_obs[i].high)
            return true;
      return false;
     }

   bool IsPriceInBullFVG(double price) const
     {
      for(int i = 0; i < m_fvgCount; i++)
         if(m_fvgs[i].active && m_fvgs[i].bullish && price >= m_fvgs[i].low && price <= m_fvgs[i].high)
            return true;
      return false;
     }

   bool IsPriceInBearFVG(double price) const
     {
      for(int i = 0; i < m_fvgCount; i++)
         if(m_fvgs[i].active && !m_fvgs[i].bullish && price >= m_fvgs[i].low && price <= m_fvgs[i].high)
            return true;
      return false;
     }

   //--- Nearest bullish OB top/bottom
   bool GetNearestBullishOB(double &outLow, double &outHigh) const
     {
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double bestDist = DBL_MAX;
      bool   found    = false;
      for(int i = 0; i < m_obCount; i++)
        {
         if(!m_obs[i].active || !m_obs[i].bullish) continue;
         double mid  = (m_obs[i].high + m_obs[i].low) * 0.5;
         double dist = MathAbs(bid - mid);
         if(dist < bestDist) { bestDist = dist; outLow = m_obs[i].low; outHigh = m_obs[i].high; found = true; }
        }
      return found;
     }

   bool GetNearestBearishOB(double &outLow, double &outHigh) const
     {
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double bestDist = DBL_MAX;
      bool   found    = false;
      for(int i = 0; i < m_obCount; i++)
        {
         if(!m_obs[i].active || m_obs[i].bullish) continue;
         double mid  = (m_obs[i].high + m_obs[i].low) * 0.5;
         double dist = MathAbs(bid - mid);
         if(dist < bestDist) { bestDist = dist; outLow = m_obs[i].low; outHigh = m_obs[i].high; found = true; }
        }
      return found;
     }
  };

#endif // MARKETSTRUCTURE_MQH

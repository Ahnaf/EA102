//+------------------------------------------------------------------+
//|                                                  EntryEngine.mqh |
//|                        EA102 v2 - XAUUSD Prop Firm EA            |
//| Staged entry: impulse detection + mode-based thresholds          |
//+------------------------------------------------------------------+
#ifndef ENTRYENGINE_MQH
#define ENTRYENGINE_MQH

#include "Utilities.mqh"
#include "TradeManager.mqh"  // EntryConfirmation struct

//+------------------------------------------------------------------+
//| CEntryEngine — confirms entry and calculates SL/TP              |
//+------------------------------------------------------------------+
class CEntryEngine
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_entryTF;    // M5
   ENUM_TIMEFRAMES m_setupTF;    // M15
   int             m_rsiPeriod;
   double          m_rsiOB;
   double          m_rsiOS;
   double          m_engulfRatio;
   int             m_atrPeriod;
   double          m_minBodyATR;
   int             m_slMode;        // 0=structure, 1=ATR
   double          m_slAtrMul;
   int             m_tpMode;        // 0=FixedRR, 1=Liquidity, 2=Hybrid
   double          m_rrRatio;

   //--- Swing references for structure-based SL (set from MarketStructure)
   double m_swingHigh;
   double m_swingLow;

   //--- Entry candle checks on entry TF
   bool IsBullishEngulf() const
     {
      double c1 = iClose(m_symbol, m_entryTF, 1), o1 = iOpen(m_symbol, m_entryTF, 1);
      double c2 = iClose(m_symbol, m_entryTF, 2), o2 = iOpen(m_symbol, m_entryTF, 2);
      if(c1 <= o1) return false;   // current not bullish
      if(c2 >= o2) return false;   // previous not bearish
      double body1 = c1 - o1, body2 = o2 - c2;
      return (body2 > 0) ? (body1 / body2 >= m_engulfRatio) : false;
     }

   bool IsBearishEngulf() const
     {
      double c1 = iClose(m_symbol, m_entryTF, 1), o1 = iOpen(m_symbol, m_entryTF, 1);
      double c2 = iClose(m_symbol, m_entryTF, 2), o2 = iOpen(m_symbol, m_entryTF, 2);
      if(c1 >= o1) return false;
      if(c2 <= o2) return false;
      double body1 = o1 - c1, body2 = c2 - o2;
      return (body2 > 0) ? (body1 / body2 >= m_engulfRatio) : false;
     }

   bool IsStrongBullBar() const
     {
      double body = CandleBody(m_symbol, m_entryTF, 1);
      double atr  = GetATR(m_symbol, m_entryTF, m_atrPeriod, 1);
      return IsBullishCandle(m_symbol, m_entryTF, 1) && body >= m_minBodyATR * atr;
     }

   bool IsStrongBearBar() const
     {
      double body = CandleBody(m_symbol, m_entryTF, 1);
      double atr  = GetATR(m_symbol, m_entryTF, m_atrPeriod, 1);
      return IsBearishCandle(m_symbol, m_entryTF, 1) && body >= m_minBodyATR * atr;
     }

   bool IsHammerBull() const
     {
      double lwic = CandleLowerWick(m_symbol, m_entryTF, 1);
      double body = CandleBody(m_symbol, m_entryTF, 1);
      double rng  = CandleRange(m_symbol, m_entryTF, 1);
      return rng > 0 && lwic >= 2.0 * body && lwic >= 0.5 * rng;
     }

   bool IsShootingStarBear() const
     {
      double uwic = CandleUpperWick(m_symbol, m_entryTF, 1);
      double body = CandleBody(m_symbol, m_entryTF, 1);
      double rng  = CandleRange(m_symbol, m_entryTF, 1);
      return rng > 0 && uwic >= 2.0 * body && uwic >= 0.5 * rng;
     }

   //--- SL calculation
   double CalculateSL(ENUM_SIGNAL_DIR dir, double entryPrice, double atr) const
     {
      double sl = 0;
      if(m_slMode == 0)  // Structure-based
        {
         double buffer = 0.2 * atr;
         if(dir == SIGNAL_BUY)
           {
            sl = (m_swingLow > 0) ? m_swingLow - buffer : entryPrice - m_slAtrMul * atr;
           }
         else
           {
            sl = (m_swingHigh > 0) ? m_swingHigh + buffer : entryPrice + m_slAtrMul * atr;
           }
        }
      else  // ATR-based
        {
         sl = (dir == SIGNAL_BUY) ? entryPrice - m_slAtrMul * atr
                                  : entryPrice + m_slAtrMul * atr;
        }
      return NormalizeDouble(sl, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
     }

   //--- TP calculation
   double CalculateTP(ENUM_SIGNAL_DIR dir, double entryPrice, double sl) const
     {
      double slDist = MathAbs(entryPrice - sl);
      double tp     = 0;

      if(m_tpMode == 0 || m_tpMode == 2)  // Fixed RR or Hybrid
        {
         tp = (dir == SIGNAL_BUY) ? entryPrice + slDist * m_rrRatio
                                  : entryPrice - slDist * m_rrRatio;
        }
      // Mode 1 (liquidity) and mode 2 (hybrid) — use nearest swing for TP if available
      if(m_tpMode >= 1 && m_swingHigh > 0 && m_swingLow > 0)
        {
         double liqTP = 0;
         if(dir == SIGNAL_BUY  && m_swingHigh > entryPrice) liqTP = m_swingHigh;
         if(dir == SIGNAL_SELL && m_swingLow  < entryPrice) liqTP = m_swingLow;
         if(liqTP > 0)
           {
            if(m_tpMode == 1) tp = liqTP;
            else              tp = (liqTP + tp) * 0.5;  // Hybrid: average
           }
        }
      return NormalizeDouble(tp, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
     }

public:
   CEntryEngine() : m_swingHigh(0), m_swingLow(0) {}

   bool Init(const string symbol, ENUM_TIMEFRAMES entryTF, ENUM_TIMEFRAMES setupTF,
             int rsiPeriod, double rsiOB, double rsiOS,
             double engulfRatio, int atrPeriod, double minBodyATR,
             int slMode, double slAtrMul, int tpMode, double rrRatio)
     {
      m_symbol      = symbol;
      m_entryTF     = entryTF;
      m_setupTF     = setupTF;
      m_rsiPeriod   = rsiPeriod;
      m_rsiOB       = rsiOB;
      m_rsiOS       = rsiOS;
      m_engulfRatio = engulfRatio;
      m_atrPeriod   = atrPeriod;
      m_minBodyATR  = minBodyATR;
      m_slMode      = slMode;
      m_slAtrMul    = slAtrMul;
      m_tpMode      = tpMode;
      m_rrRatio     = rrRatio;
      LogInfo("EntryEngine", StringFormat("Init | EntryTF=%s SetupTF=%s SLMode=%d TPMode=%d RR=%.1f",
              EnumToString(entryTF), EnumToString(setupTF), slMode, tpMode, rrRatio));
      return true;
     }

   //--- Update swing levels from MarketStructure (call before CheckEntry)
   void SetSwings(double swingHigh, double swingLow)
     {
      m_swingHigh = swingHigh;
      m_swingLow  = swingLow;
     }

   //+------------------------------------------------------------------+
   //| Core check — staged confirmation based on mode + signal type    |
   //+------------------------------------------------------------------+
   EntryConfirmation CheckEntry(ENUM_SIGNAL_DIR dir, ENUM_SIGNAL_TYPE sigType,
                                ENUM_TRADE_MODE mode, double signalScore) const
     {
      EntryConfirmation ec;
      ec.confirmed   = false;
      ec.direction   = dir;
      ec.signalType  = sigType;
      ec.score       = signalScore;
      ec.reason      = "";

      if(dir == SIGNAL_NONE) return ec;

      double atr        = GetATR(m_symbol, m_entryTF, m_atrPeriod, 1);
      if(atr <= 0) return ec;

      double ask        = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid        = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double entryPrice = (dir == SIGNAL_BUY) ? ask : bid;
      double rsi        = GetRSI(m_symbol, m_entryTF, m_rsiPeriod, 1);

      bool bullEngulf   = (dir == SIGNAL_BUY)  && IsBullishEngulf();
      bool bearEngulf   = (dir == SIGNAL_SELL) && IsBearishEngulf();
      bool bullStrong   = (dir == SIGNAL_BUY)  && IsStrongBullBar();
      bool bearStrong   = (dir == SIGNAL_SELL) && IsStrongBearBar();
      bool bullHammer   = (dir == SIGNAL_BUY)  && IsHammerBull();
      bool bearStar     = (dir == SIGNAL_SELL) && IsShootingStarBear();

      bool candleOK     = bullEngulf || bearEngulf || bullStrong || bearStrong || bullHammer || bearStar;
      bool rsiOK        = (dir == SIGNAL_BUY)  ? (rsi < m_rsiOB && rsi > 30)
                                                : (rsi > m_rsiOS && rsi < 70);

      // --- IMPULSE ENTRY: ATR expansion + breakout candle ---
      bool atrExpand = false;
      double atrPrev = GetATR(m_symbol, m_entryTF, m_atrPeriod, 5);
      if(atrPrev > 0) atrExpand = (atr >= 1.5 * atrPrev);
      bool impulse = atrExpand && candleOK;

      // Setup-TF candle to check momentum alignment
      bool setupCandleOK = (dir == SIGNAL_BUY)  ? IsBullishCandle(m_symbol, m_setupTF, 1)
                                                 : IsBearishCandle(m_symbol, m_setupTF, 1);

      bool confirmed = false;
      string reason  = "";

      // == SAFE mode: full confirmation (all 3: candle + RSI + setup TF aligned) ==
      if(mode == TRADE_MODE_SAFE)
        {
         confirmed = candleOK && rsiOK && setupCandleOK;
         if(!candleOK)      reason = "No entry candle";
         else if(!rsiOK)    reason = "RSI not aligned";
         else if(!setupCandleOK) reason = "Setup TF not aligned";
         else               reason = "SAFE confirmed";
        }

      // == NORMAL mode: candle + (RSI or setup TF) ==
      else if(mode == TRADE_MODE_NORMAL)
        {
         confirmed = candleOK && (rsiOK || setupCandleOK);
         if(!candleOK)        reason = "No entry candle";
         else if(!rsiOK && !setupCandleOK) reason = "RSI & setup TF both missing";
         else                 reason = "NORMAL confirmed";
        }

      // == AGGRESSIVE mode: candle alone, or impulse alone ==
      else  // TRADE_MODE_AGGRESSIVE
        {
         // Allow reversal entries even more readily if it came from reversal engine
         if(sigType == SIGNAL_TYPE_REVERSAL)
           confirmed = candleOK || impulse;
         else
           confirmed = candleOK;

         // Impulse entry: strong ATR spike + direction candle
         if(!confirmed && impulse)
           { confirmed = true; reason = "IMPULSE entry"; }

         if(!confirmed) reason = "No strong candle (AGGR)";
         else if(reason == "") reason = "AGGRESSIVE confirmed";
        }

      // --- Validate min SL distance against spread ---
      double sl  = CalculateSL(dir, entryPrice, atr);
      double slD = MathAbs(entryPrice - sl);
      double spread = (ask - bid);
      if(slD < spread * 2)
        {
         confirmed = false;
         reason    = "SL too tight vs spread";
        }

      if(!confirmed) { ec.reason = reason; return ec; }

      double tp = CalculateTP(dir, entryPrice, sl);

      ec.confirmed   = true;
      ec.direction   = dir;
      ec.entryPrice  = entryPrice;
      ec.stopLoss    = sl;
      ec.takeProfit  = tp;
      ec.reason      = reason;
      return ec;
     }

   //+------------------------------------------------------------------+
   //| Impulse-only check (for breakout detection in MainEA)           |
   //+------------------------------------------------------------------+
   bool IsImpulseEntry(ENUM_SIGNAL_DIR &outDir) const
     {
      double atr     = GetATR(m_symbol, m_entryTF, m_atrPeriod, 1);
      double atrPrev = GetATR(m_symbol, m_entryTF, m_atrPeriod, 5);
      if(atr <= 0 || atrPrev <= 0) return false;

      if(atr < 1.5 * atrPrev) return false;  // No ATR expansion

      // Direction by candle
      double body = CandleBody(m_symbol, m_entryTF, 1);
      if(body < 0.5 * atr) return false;  // Not strong enough

      outDir = IsBullishCandle(m_symbol, m_entryTF, 1) ? SIGNAL_BUY : SIGNAL_SELL;
      return true;
     }
  };

#endif // ENTRYENGINE_MQH

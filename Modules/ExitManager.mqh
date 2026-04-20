//+------------------------------------------------------------------+
//|                                                  ExitManager.mqh |
//|                        EA102 v2 - XAUUSD Prop Firm EA            |
//|              PROFIT PROTECTION ENGINE (per-trade R tracking)    |
//+------------------------------------------------------------------+
#ifndef EXITMANAGER_MQH
#define EXITMANAGER_MQH

#include "Utilities.mqh"
#include "TradeManager.mqh"
#include "SignalEngine.mqh"     // For ReversalSignal struct

#define MAX_TRADE_RECORDS 20

//--- Per-trade state tracked by ExitManager
struct TradeRecord
  {
   ulong            ticket;
   ENUM_SIGNAL_DIR  direction;
   ENUM_SIGNAL_TYPE signalType;
   double           entryPrice;
   double           originalSL;     // SL at trade open (1R distance reference)
   double           oneR;           // Distance in price = 1R (|entry - originalSL|)
   double           maxR;           // Peak R multiple reached
   double           currentR;       // Current R multiple
   bool             beApplied;      // Break-even SL applied?
   bool             partialDone;    // Partial close executed?
   bool             active;
  };

//+------------------------------------------------------------------+
//| CExitManager — Profit Protection Engine                         |
//+------------------------------------------------------------------+
class CExitManager
  {
private:
   CTradeManager   *m_trade;
   string           m_symbol;
   int              m_magic;

   //--- Break-even config
   bool    m_useBE;
   double  m_beTriggerR;      // R at which BE is applied (e.g. 0.8)
   double  m_beBufferPoints;  // Extra buffer above entry (points)

   //--- Partial close config
   bool    m_usePartial;
   double  m_partialTriggerR; // R trigger (e.g. 1.0)
   double  m_partialPct;      // % of position to close (e.g. 0.5 = 50%)

   //--- Giveback protection config
   bool    m_useGiveback;
   double  m_givebackR1;      // Lower threshold (e.g. 1.5)
   double  m_givebackDrop1;   // Drop from max to trigger (e.g. 0.5)
   double  m_givebackR2;      // Higher threshold (e.g. 2.0)
   double  m_givebackDrop2;   // Drop from max to trigger (e.g. 1.0)

   //--- Reversal exit config
   bool    m_useReversalExit;
   double  m_reversalExitScore; // Min reversal score to force close

   //--- ATR trailing stop config
   bool    m_useTrailing;
   int     m_trailAtrPeriod;
   double  m_trailAtrMul;
   ENUM_TIMEFRAMES m_trailTF;

   //--- Trade records
   TradeRecord m_records[MAX_TRADE_RECORDS];
   int         m_recordCount;

   //--- Find record for ticket (-1 if not found)
   int FindRecord(ulong ticket) const
     {
      for(int i = 0; i < m_recordCount; i++)
         if(m_records[i].active && m_records[i].ticket == ticket)
            return i;
      return -1;
     }

   //--- Calculate current R multiple for a position (by record index)
   double CalcCurrentR(int idx) const
     {
      if(m_records[idx].oneR <= 0) return 0;
      if(!PositionSelectByTicket(m_records[idx].ticket)) return 0;
      double price = PositionGetDouble(POSITION_PRICE_CURRENT);
      return (m_records[idx].direction == SIGNAL_BUY)
             ? (price - m_records[idx].entryPrice) / m_records[idx].oneR
             : (m_records[idx].entryPrice - price) / m_records[idx].oneR;
     }

   //--- Momentum fade: check if candle opposes position
   bool IsMomentumFade(int idx, ENUM_TIMEFRAMES tf) const
     {
      double atr  = GetATR(m_symbol, tf, m_trailAtrPeriod, 1);
      double body = CandleBody(m_symbol, tf, 1);
      if(body < 0.35 * atr) return false;
      if(m_records[idx].direction == SIGNAL_BUY  && IsBearishCandle(m_symbol, tf, 1)) return true;
      if(m_records[idx].direction == SIGNAL_SELL && IsBullishCandle(m_symbol, tf, 1)) return true;
      return false;
     }

public:
   CExitManager() : m_trade(NULL), m_recordCount(0) {}

   bool Init(CTradeManager *trade, const string symbol, int magic,
             bool useBE, double beTriggerR, double beBufferPoints,
             bool usePartial, double partialTriggerR, double partialPct,
             bool useGiveback,
             double givebackR1, double givebackDrop1,
             double givebackR2, double givebackDrop2,
             bool useReversalExit, double reversalExitScore,
             bool useTrailing, int trailAtrPeriod, double trailAtrMul,
             ENUM_TIMEFRAMES trailTF)
     {
      m_trade             = trade;
      m_symbol            = symbol;
      m_magic             = magic;
      m_useBE             = useBE;
      m_beTriggerR        = beTriggerR;
      m_beBufferPoints    = beBufferPoints;
      m_usePartial        = usePartial;
      m_partialTriggerR   = partialTriggerR;
      m_partialPct        = partialPct;
      m_useGiveback       = useGiveback;
      m_givebackR1        = givebackR1;
      m_givebackDrop1     = givebackDrop1;
      m_givebackR2        = givebackR2;
      m_givebackDrop2     = givebackDrop2;
      m_useReversalExit   = useReversalExit;
      m_reversalExitScore = reversalExitScore;
      m_useTrailing       = useTrailing;
      m_trailAtrPeriod    = trailAtrPeriod;
      m_trailAtrMul       = trailAtrMul;
      m_trailTF           = trailTF;
      m_recordCount       = 0;
      LogInfo("ExitManager", StringFormat("Init | BE=%.1fR Partial=%.1fR GivebackR1=%.1f/%.1f GivebackR2=%.1f/%.1f RevExit=%s",
              beTriggerR, partialTriggerR, givebackR1, givebackDrop1, givebackR2, givebackDrop2,
              useReversalExit ? "ON" : "OFF"));
      return true;
     }

   //--- Register a new trade (called by MainEA after OpenTrade)
   void RegisterTrade(ulong ticket, ENUM_SIGNAL_DIR dir, ENUM_SIGNAL_TYPE sigType,
                      double entryPrice, double originalSL)
     {
      // Clean stale records for this ticket (shouldn't happen, but safety)
      for(int i = 0; i < m_recordCount; i++)
         if(m_records[i].ticket == ticket) m_records[i].active = false;

      if(m_recordCount >= MAX_TRADE_RECORDS)
        {
         // Evict oldest inactive
         for(int i = 0; i < MAX_TRADE_RECORDS - 1; i++) m_records[i] = m_records[i + 1];
         m_recordCount = MAX_TRADE_RECORDS - 1;
        }

      double oneR = MathAbs(entryPrice - originalSL);
      TradeRecord r;
      r.ticket      = ticket;
      r.direction   = dir;
      r.signalType  = sigType;
      r.entryPrice  = entryPrice;
      r.originalSL  = originalSL;
      r.oneR        = oneR;
      r.maxR        = 0;
      r.currentR    = 0;
      r.beApplied   = false;
      r.partialDone = false;
      r.active      = true;
      m_records[m_recordCount++] = r;

      LogInfo("ExitManager", StringFormat("Registered ticket=%I64u dir=%s 1R=%.5f",
              ticket, SignalDirStr(dir), oneR));
     }

   //--- Remove closed positions from records
   void CleanupClosedPositions()
     {
      for(int i = 0; i < m_recordCount; i++)
        {
         if(!m_records[i].active) continue;
         if(!PositionSelectByTicket(m_records[i].ticket))
            m_records[i].active = false;  // Position no longer exists
        }
     }

   //+------------------------------------------------------------------+
   //| MAIN UPDATE — runs every tick (BEFORE new trade evaluation)     |
   //+------------------------------------------------------------------+
   void Update(ENUM_TIMEFRAMES entryTF, const ReversalSignal &revSig)
     {
      CleanupClosedPositions();

       for(int i = 0; i < m_recordCount; i++)
         {
          if(!m_records[i].active) continue;
          if(!PositionSelectByTicket(m_records[i].ticket)) continue;

          // Update R tracking
          m_records[i].currentR = CalcCurrentR(i);
          if(m_records[i].currentR > m_records[i].maxR) m_records[i].maxR = m_records[i].currentR;

          double curSL = PositionGetDouble(POSITION_SL);
          double curTP = PositionGetDouble(POSITION_TP);
          double lots  = PositionGetDouble(POSITION_VOLUME);

          //------------------------------------------------------------
          // EXIT PRIORITY 1: Reversal signal against this position
          //------------------------------------------------------------
          if(m_useReversalExit && revSig.score >= m_reversalExitScore)
            {
             bool revAgainst = (m_records[i].direction == SIGNAL_BUY  && revSig.direction == SIGNAL_SELL)
                            || (m_records[i].direction == SIGNAL_SELL && revSig.direction == SIGNAL_BUY);

             if(revAgainst && m_records[i].currentR > 0)
               {
                LogInfo("ExitManager", StringFormat("REVERSAL EXIT | ticket=%I64u R=%.2f RevScore=%.2f",
                        m_records[i].ticket, m_records[i].currentR, revSig.score));
                m_trade.ClosePosition(m_records[i].ticket);
                m_records[i].active = false;
                continue;
               }
             // Close in loss if reversal is very strong (liq sweep + CHOCH)
             if(revAgainst && revSig.liqSweep && revSig.choch && revSig.score >= 0.70)
               {
                LogInfo("ExitManager", StringFormat("STRONG REVERSAL EXIT (loss) | ticket=%I64u R=%.2f",
                        m_records[i].ticket, m_records[i].currentR));
                m_trade.ClosePosition(m_records[i].ticket);
                m_records[i].active = false;
                continue;
               }
            }

          //------------------------------------------------------------
          // EXIT PRIORITY 2: Strong giveback — maxR >= R2 and dropped by Drop2
          //------------------------------------------------------------
          if(m_useGiveback && m_records[i].maxR >= m_givebackR2
             && m_records[i].currentR < (m_records[i].maxR - m_givebackDrop2))
            {
             LogInfo("ExitManager", StringFormat("STRONG GIVEBACK | ticket=%I64u maxR=%.2f curR=%.2f",
                     m_records[i].ticket, m_records[i].maxR, m_records[i].currentR));
             m_trade.ClosePosition(m_records[i].ticket);
             m_records[i].active = false;
             continue;
            }

          //------------------------------------------------------------
          // EXIT PRIORITY 3: Moderate giveback — maxR >= R1 and dropped by Drop1
          //------------------------------------------------------------
          if(m_useGiveback && m_records[i].maxR >= m_givebackR1
             && m_records[i].currentR < (m_records[i].maxR - m_givebackDrop1))
            {
             LogInfo("ExitManager", StringFormat("GIVEBACK | ticket=%I64u maxR=%.2f curR=%.2f",
                     m_records[i].ticket, m_records[i].maxR, m_records[i].currentR));
             m_trade.ClosePosition(m_records[i].ticket);
             m_records[i].active = false;
             continue;
            }

          //------------------------------------------------------------
          // EXIT PRIORITY 4: Break-even
          //------------------------------------------------------------
          if(m_useBE && !m_records[i].beApplied && m_records[i].currentR >= m_beTriggerR)
            {
             double ptSize = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
             double beBuf  = m_beBufferPoints * ptSize;
             double beSL   = (m_records[i].direction == SIGNAL_BUY)
                              ? m_records[i].entryPrice + beBuf
                              : m_records[i].entryPrice - beBuf;
             beSL = NormalizeDouble(beSL, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));

             bool moveOK = (m_records[i].direction == SIGNAL_BUY)
                           ? (beSL > curSL)
                           : (beSL < curSL || curSL == 0);
             if(moveOK && m_trade.ModifyPosition(m_records[i].ticket, beSL, curTP))
               {
                m_records[i].beApplied = true;
                LogInfo("ExitManager", StringFormat("BE applied | ticket=%I64u SL=%.5f R=%.2f",
                        m_records[i].ticket, beSL, m_records[i].currentR));
               }
            }

          //------------------------------------------------------------
          // EXIT PRIORITY 5: Partial close
          //------------------------------------------------------------
          if(m_usePartial && !m_records[i].partialDone && m_records[i].currentR >= m_partialTriggerR)
            {
             double closeLots = NormalizeLots(m_symbol, lots * m_partialPct);
             if(m_trade.ClosePartial(m_records[i].ticket, closeLots))
               {
                m_records[i].partialDone = true;
                LogInfo("ExitManager", StringFormat("PARTIAL CLOSE | ticket=%I64u lots=%.2f R=%.2f",
                        m_records[i].ticket, closeLots, m_records[i].currentR));
               }
            }

          //------------------------------------------------------------
          // EXIT PRIORITY 6: Momentum fade (after partial)
          //------------------------------------------------------------
          if(m_records[i].partialDone && m_records[i].currentR > 0 && IsMomentumFade(i, entryTF))
            {
             if(m_records[i].currentR >= 1.0)
               {
                LogInfo("ExitManager", StringFormat("MOMENTUM FADE EXIT | ticket=%I64u R=%.2f",
                        m_records[i].ticket, m_records[i].currentR));
                m_trade.ClosePosition(m_records[i].ticket);
                m_records[i].active = false;
                continue;
               }
            }

          //------------------------------------------------------------
          // EXIT PRIORITY 7: ATR Trailing Stop (after BE applied)
          //------------------------------------------------------------
          if(m_useTrailing && m_records[i].beApplied)
            {
             double atr     = GetATR(m_symbol, m_trailTF, m_trailAtrPeriod, 1);
             double price   = PositionGetDouble(POSITION_PRICE_CURRENT);
             double trailSL = 0;

             if(m_records[i].direction == SIGNAL_BUY)
               {
                trailSL = NormalizeDouble(price - m_trailAtrMul * atr,
                                          (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
                if(trailSL > curSL && trailSL < price)
                   m_trade.ModifyPosition(m_records[i].ticket, trailSL, curTP);
               }
             else
               {
                trailSL = NormalizeDouble(price + m_trailAtrMul * atr,
                                          (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
                if((curSL == 0 || trailSL < curSL) && trailSL > price)
                   m_trade.ModifyPosition(m_records[i].ticket, trailSL, curTP);
               }
            }
         }
     }

   //--- Get current R for display purposes
   double GetCurrentR(ulong ticket) const
     {
      int idx = FindRecord(ticket);
      return (idx >= 0) ? m_records[idx].currentR : 0;
     }
   double GetMaxR(ulong ticket) const
     {
      int idx = FindRecord(ticket);
      return (idx >= 0) ? m_records[idx].maxR : 0;
     }
  };

#endif // EXITMANAGER_MQH

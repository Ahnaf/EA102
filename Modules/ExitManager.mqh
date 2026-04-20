//+------------------------------------------------------------------+
//|                                                   ExitManager.mqh|
//|                          EA102 - XAUUSD Prop Firm EA             |
//|   Break-even, Partial Close, ATR Trailing Stop, Exit Management  |
//+------------------------------------------------------------------+
#ifndef EXITMANAGER_MQH
#define EXITMANAGER_MQH
#include "Utilities.mqh"
#include "TradeManager.mqh"

//+------------------------------------------------------------------+
//| CExitManager class                                               |
//+------------------------------------------------------------------+
class CExitManager
  {
private:
   CTradeManager    *m_tradeMgr;
   string            m_symbol;
   int               m_magicNumber;

   // Break-even settings
   bool              m_useBE;
   double            m_beTriggerR;       // R multiple to trigger BE (e.g. 1.0)
   double            m_beBufferPoints;   // Extra buffer above entry for BE SL

   // Partial close settings
   bool              m_usePartialClose;
   double            m_partialCloseR;    // R multiple trigger for partial close
   double            m_partialClosePct;  // % of position to close (e.g. 50.0)

   // ATR trailing stop settings
   bool              m_useTrailing;
   int               m_trailingAtrPeriod;
   double            m_trailingAtrMul;   // e.g. 1.5 × ATR

   // Track which tickets already had BE / partial applied
   ulong             m_beApplied[100];
   int               m_beAppliedCount;
   ulong             m_partialApplied[100];
   int               m_partialAppliedCount;

public:
   CExitManager()
    : m_tradeMgr(NULL), m_beAppliedCount(0), m_partialAppliedCount(0) {}
   ~CExitManager() {}

   bool Init(CTradeManager *tradeMgr,
             const string   symbol,
             int            magicNumber,
             bool           useBE,
             double         beTriggerR,
             double         beBufferPoints,
             bool           usePartialClose,
             double         partialCloseR,
             double         partialClosePct,
             bool           useTrailing,
             int            trailingAtrPeriod,
             double         trailingAtrMul)
     {
      m_tradeMgr            = tradeMgr;
      m_symbol              = symbol;
      m_magicNumber         = magicNumber;
      m_useBE               = useBE;
      m_beTriggerR          = beTriggerR;
      m_beBufferPoints      = beBufferPoints;
      m_usePartialClose     = usePartialClose;
      m_partialCloseR       = partialCloseR;
      m_partialClosePct     = partialClosePct;
      m_useTrailing         = useTrailing;
      m_trailingAtrPeriod   = trailingAtrPeriod;
      m_trailingAtrMul      = trailingAtrMul;
      m_beAppliedCount      = 0;
      m_partialAppliedCount = 0;

      LogInfo("ExitManager", StringFormat(
         "Init | BE=%s(%.1fR+%.0fpts) | Partial=%s(%.1fR,%.0f%%) | Trail=%s(ATR%d×%.1f)",
         useBE ? "ON" : "OFF", beTriggerR, beBufferPoints,
         usePartialClose ? "ON" : "OFF", partialCloseR, partialClosePct,
         useTrailing ? "ON" : "OFF", trailingAtrPeriod, trailingAtrMul));
      return true;
     }

   //--- Master update — call once per tick / bar for all open positions
   void Update(ENUM_TIMEFRAMES entryTF)
     {
      if(m_tradeMgr == NULL) return;

      ulong tickets[];
      int count = m_tradeMgr->GetOpenTickets(tickets);

      for(int i = 0; i < count; i++)
        {
         ulong ticket = tickets[i];
         if(!PositionSelectByTicket(ticket)) continue;

         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double slPrice   = PositionGetDouble(POSITION_SL);
         double tpPrice   = PositionGetDouble(POSITION_TP);
         double lots      = PositionGetDouble(POSITION_VOLUME);
         ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         bool   isBuy     = (ptype == POSITION_TYPE_BUY);

         double currentPrice = isBuy
                               ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                               : SymbolInfoDouble(m_symbol, SYMBOL_ASK);

         double slDist = MathAbs(openPrice - slPrice);
         if(slDist <= 0) continue;

         double rMultiple = isBuy
                            ? (currentPrice - openPrice) / slDist
                            : (openPrice - currentPrice) / slDist;

         // 1. Break-even
         if(m_useBE && !WasBEApplied(ticket))
            TryApplyBE(ticket, isBuy, openPrice, slDist, rMultiple);

         // 2. Partial close
         if(m_usePartialClose && !WasPartialApplied(ticket))
            TryPartialClose(ticket, lots, rMultiple);

         // 3. Trailing stop
         if(m_useTrailing)
            TryTrailingStop(ticket, isBuy, currentPrice, slPrice, entryTF);
        }
     }

private:
   //--- Break-even: move SL to entry + buffer when R >= trigger
   void TryApplyBE(ulong ticket, bool isBuy, double openPrice,
                   double slDist, double rMultiple)
     {
      if(rMultiple < m_beTriggerR) return;

      double pt       = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double buffer   = m_beBufferPoints * pt;

      double newSL    = isBuy ? openPrice + buffer : openPrice - buffer;

      // Fetch current SL
      if(!PositionSelectByTicket(ticket)) return;
      double currentSL = PositionGetDouble(POSITION_SL);

      // Only move SL in favour of trade
      bool shouldMove = isBuy  ? (newSL > currentSL) : (newSL < currentSL);
      if(!shouldMove) return;

      if(m_tradeMgr->ModifyPosition(ticket, newSL))
        {
         MarkBEApplied(ticket);
         LogInfo("ExitManager", StringFormat(
            "BE applied ticket=%llu | R=%.2f | NewSL=%.5f", ticket, rMultiple, newSL));
        }
     }

   //--- Partial close: close m_partialClosePct at m_partialCloseR
   void TryPartialClose(ulong ticket, double lots, double rMultiple)
     {
      if(rMultiple < m_partialCloseR) return;

      double closeLots = NormalizeLots(m_symbol, lots * m_partialClosePct / 100.0);
      if(closeLots <= 0) return;

      if(m_tradeMgr->ClosePartial(ticket, closeLots))
        {
         MarkPartialApplied(ticket);
         LogInfo("ExitManager", StringFormat(
            "Partial close %.2f lots | ticket=%llu | R=%.2f", closeLots, ticket, rMultiple));
        }
     }

   //--- ATR trailing stop
   void TryTrailingStop(ulong ticket, bool isBuy, double currentPrice,
                        double currentSL, ENUM_TIMEFRAMES tf)
     {
      double atr     = GetATR(m_symbol, tf, m_trailingAtrPeriod, 1);
      if(atr <= 0) return;

      double trailDist = atr * m_trailingAtrMul;
      double newSL     = isBuy ? currentPrice - trailDist : currentPrice + trailDist;

      // Ensure we only tighten (never widen) the stop
      bool better = isBuy ? (newSL > currentSL) : (newSL < currentSL);
      if(!better) return;

      // Must maintain minimum stop distance
      int    stopsLevel = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double minDist    = stopsLevel * SymbolInfoDouble(m_symbol, SYMBOL_POINT);

      bool tooClose = isBuy  ? (currentPrice - newSL < minDist)
                              : (newSL - currentPrice < minDist);
      if(tooClose) return;

      newSL = NormalizeDouble(newSL, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
      m_tradeMgr->ModifyPosition(ticket, newSL);
     }

   //--- BE tracking helpers
   bool WasBEApplied(ulong ticket) const
     {
      for(int i = 0; i < m_beAppliedCount; i++)
         if(m_beApplied[i] == ticket) return true;
      return false;
     }

   void MarkBEApplied(ulong ticket)
     {
      if(m_beAppliedCount < 100)
         m_beApplied[m_beAppliedCount++] = ticket;
     }

   bool WasPartialApplied(ulong ticket) const
     {
      for(int i = 0; i < m_partialAppliedCount; i++)
         if(m_partialApplied[i] == ticket) return true;
      return false;
     }

   void MarkPartialApplied(ulong ticket)
     {
      if(m_partialAppliedCount < 100)
         m_partialApplied[m_partialAppliedCount++] = ticket;
     }
  };
//+------------------------------------------------------------------+
#endif // EXITMANAGER_MQH

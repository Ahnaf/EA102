//+------------------------------------------------------------------+
//|                                                 TradeManager.mqh |
//|                          EA102 - XAUUSD Prop Firm EA             |
//|              Trade Execution, Modification, and Tracking         |
//+------------------------------------------------------------------+
#ifndef TRADEMANAGER_MQH
#define TRADEMANAGER_MQH
#include "Utilities.mqh"
#include "EntryEngine.mqh"
#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| CTradeManager class                                              |
//+------------------------------------------------------------------+
class CTradeManager
  {
private:
   CTrade            m_trade;
   string            m_symbol;
   int               m_magicNumber;
   int               m_slippage;
   string            m_tradeComment;

public:
   CTradeManager() {}
   ~CTradeManager() {}

   bool Init(const string symbol, int magicNumber, int slippage, const string comment)
     {
      m_symbol       = symbol;
      m_magicNumber  = magicNumber;
      m_slippage     = slippage;
      m_tradeComment = comment;

      m_trade.SetExpertMagicNumber(magicNumber);
      m_trade.SetDeviationInPoints(slippage);
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      m_trade.SetAsyncMode(false);

      LogInfo("TradeManager", StringFormat(
         "Init | %s | Magic=%d | Slippage=%d", symbol, magicNumber, slippage));
      return true;
     }

   //--- Open a market order from EntryConfirmation
   bool OpenTrade(const EntryConfirmation &ec, double lots, ulong &outTicket)
     {
      outTicket = 0;

      if(!ec.confirmed)
        {
         LogWarn("TradeManager", "Entry not confirmed, skipping open");
         return false;
        }
      if(lots <= 0)
        {
         LogWarn("TradeManager", "Lot size=0, skipping");
         return false;
        }

      bool ok = false;

      if(ec.direction == SIGNAL_BUY)
        {
         ok = m_trade.Buy(lots, m_symbol, ec.entryPrice, ec.stopLoss, ec.takeProfit, m_tradeComment);
        }
      else if(ec.direction == SIGNAL_SELL)
        {
         ok = m_trade.Sell(lots, m_symbol, ec.entryPrice, ec.stopLoss, ec.takeProfit, m_tradeComment);
        }
      else
        {
         LogWarn("TradeManager", "Direction NONE — skipping trade");
         return false;
        }

      if(ok)
        {
         outTicket = m_trade.ResultOrder();
         LogInfo("TradeManager", StringFormat(
            "Opened | %s %.2f lots | Entry=%.5f SL=%.5f TP=%.5f | Ticket=%llu",
            (ec.direction == SIGNAL_BUY ? "BUY" : "SELL"),
            lots, ec.entryPrice, ec.stopLoss, ec.takeProfit, outTicket));
        }
      else
        {
         LogError("TradeManager", StringFormat(
            "Open FAILED | retcode=%d err=%s",
            m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
        }

      return ok;
     }

   //--- Modify SL / TP of an existing position
   bool ModifyPosition(ulong ticket, double newSL, double newTP = 0)
     {
      if(!PositionSelectByTicket(ticket))
        {
         LogWarn("TradeManager", StringFormat("ModifyPos: ticket %llu not found", ticket));
         return false;
        }

      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      // Use existing TP if not supplied
      if(newTP == 0) newTP = currentTP;

      // Only modify if values actually changed
      double pt = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(MathAbs(newSL - currentSL) < pt && MathAbs(newTP - currentTP) < pt)
         return true;

      bool ok = m_trade.PositionModify(ticket, newSL, newTP);
      if(ok)
        {
         LogDebug("TradeManager", StringFormat(
            "Modified ticket=%llu | SL=%.5f TP=%.5f", ticket, newSL, newTP));
        }
      else
        {
         LogError("TradeManager", StringFormat(
            "Modify FAILED ticket=%llu | retcode=%d", ticket, m_trade.ResultRetcode()));
        }
      return ok;
     }

   //--- Close a position fully
   bool ClosePosition(ulong ticket)
     {
      if(!PositionSelectByTicket(ticket))
        {
         LogWarn("TradeManager", StringFormat("ClosePos: ticket %llu not found", ticket));
         return false;
        }

      bool ok = m_trade.PositionClose(ticket, m_slippage);
      if(ok)
         LogInfo("TradeManager", StringFormat("Closed ticket=%llu", ticket));
      else
         LogError("TradeManager", StringFormat(
            "Close FAILED ticket=%llu retcode=%d", ticket, m_trade.ResultRetcode()));

      return ok;
     }

   //--- Close partial volume of a position
   bool ClosePartial(ulong ticket, double closeLots)
     {
      if(!PositionSelectByTicket(ticket))
        {
         LogWarn("TradeManager", StringFormat("ClosePartial: ticket %llu not found", ticket));
         return false;
        }

      double posVol   = PositionGetDouble(POSITION_VOLUME);
      double minLot   = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double lotStep  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

      // Clamp close volume to available, leaving at least minLot behind
      closeLots = MathMin(closeLots, posVol - minLot);
      closeLots = MathMax(closeLots, minLot);
      closeLots = NormalizeLots(m_symbol, closeLots);

      if(closeLots <= 0)
        {
         LogWarn("TradeManager", "ClosePartial: too small to close");
         return false;
        }

      ENUM_POSITION_TYPE ptype   = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      ENUM_ORDER_TYPE    ordType = (ptype == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      double             price   = (ordType == ORDER_TYPE_BUY)
                                   ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                                   : SymbolInfoDouble(m_symbol, SYMBOL_BID);

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action    = TRADE_ACTION_DEAL;
      req.symbol    = m_symbol;
      req.volume    = closeLots;
      req.type      = ordType;
      req.price     = price;
      req.deviation = m_slippage;
      req.position  = ticket;
      req.magic     = m_magicNumber;
      req.comment   = m_tradeComment + "_partial";
      req.type_filling = ORDER_FILLING_IOC;

      bool ok = OrderSend(req, res);
      if(ok && res.retcode <= TRADE_RETCODE_PLACED)
        {
         LogInfo("TradeManager", StringFormat(
            "Partial close %.2f lots | ticket=%llu", closeLots, ticket));
         return true;
        }
      else
        {
         LogError("TradeManager", StringFormat(
            "Partial close FAILED ticket=%llu retcode=%d", ticket, res.retcode));
         return false;
        }
     }

   //--- Close all positions for this EA
   void CloseAllPositions(const string reason)
     {
      LogWarn("TradeManager", "CloseAll: " + reason);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;
         ClosePosition(ticket);
        }
     }

   //--- Collect all open ticket numbers for this EA
   int GetOpenTickets(ulong &tickets[])
     {
      ArrayResize(tickets, 0);
      int count = 0;
      for(int i = 0; i < PositionsTotal(); i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;
         ArrayResize(tickets, count + 1);
         tickets[count++] = ticket;
        }
      return count;
     }

   string GetSymbol()      const { return m_symbol; }
   int    GetMagic()       const { return m_magicNumber; }
   CTrade *GetTrade()            { return &m_trade; }
  };
//+------------------------------------------------------------------+
#endif // TRADEMANAGER_MQH

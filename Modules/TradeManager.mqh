//+------------------------------------------------------------------+
//|                                                TradeManager.mqh  |
//|                        EA102 v2 - XAUUSD Prop Firm EA            |
//|              CTrade wrapper: open, close, modify, partial        |
//+------------------------------------------------------------------+
#ifndef TRADEMANAGER_MQH
#define TRADEMANAGER_MQH

#include "Utilities.mqh"
#include <Trade\Trade.mqh>

//--- Shared entry confirmation struct (used by EntryEngine + MainEA + TradeManager)
struct EntryConfirmation
  {
   bool            confirmed;
   ENUM_SIGNAL_DIR direction;
   ENUM_SIGNAL_TYPE signalType;
   double          entryPrice;
   double          stopLoss;
   double          takeProfit;
   double          score;
   string          reason;
  };

//+------------------------------------------------------------------+
//| CTradeManager                                                    |
//+------------------------------------------------------------------+
class CTradeManager
  {
private:
   string   m_symbol;
   int      m_magic;
   int      m_slippage;
   string   m_comment;
   CTrade   m_trade;

public:
   CTradeManager() {}

   bool Init(const string symbol, int magic, int slippage, const string comment)
     {
      m_symbol   = symbol;
      m_magic    = magic;
      m_slippage = slippage;
      m_comment  = comment;
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(slippage);
      LogInfo("TradeManager", StringFormat("Init | Symbol=%s Magic=%d Slip=%d", symbol, magic, slippage));
      return true;
     }

   //--- Open a market order from an EntryConfirmation
   bool OpenTrade(const EntryConfirmation &ec, double lots, ulong &ticket)
     {
      ticket = 0;
      if(!ec.confirmed || lots <= 0) return false;

      bool ok = false;
      string cmt = m_comment + StringFormat("|%.2f|%s", ec.score, SignalTypeStr(ec.signalType));

      if(ec.direction == SIGNAL_BUY)
         ok = m_trade.Buy(lots, m_symbol, 0, ec.stopLoss, ec.takeProfit, cmt);
      else
         ok = m_trade.Sell(lots, m_symbol, 0, ec.stopLoss, ec.takeProfit, cmt);

      if(ok)
        {
         ticket = m_trade.ResultOrder();
         LogInfo("TradeManager", StringFormat("OPEN %s | Lots=%.2f SL=%.5f TP=%.5f Ticket=%I64u",
                 SignalDirStr(ec.direction), lots, ec.stopLoss, ec.takeProfit, ticket));
        }
      else
        {
         LogError("TradeManager", StringFormat("Open failed | Ret=%d Err=%s",
                  m_trade.ResultRetcode(), m_trade.ResultComment()));
        }

      return ok;
     }

   //--- Modify SL / TP
   bool ModifyPosition(ulong ticket, double sl, double tp)
     {
      if(!PositionSelectByTicket(ticket)) return false;
      if((int)PositionGetInteger(POSITION_MAGIC) != m_magic) return false;
      bool ok = m_trade.PositionModify(ticket, sl, tp);
      if(!ok) LogWarn("TradeManager", StringFormat("Modify failed ticket=%I64u", ticket));
      return ok;
     }

   //--- Full close
   bool ClosePosition(ulong ticket)
     {
      if(!PositionSelectByTicket(ticket)) return false;
      if((int)PositionGetInteger(POSITION_MAGIC) != m_magic) return false;
      bool ok = m_trade.PositionClose(ticket);
      if(!ok) LogWarn("TradeManager", StringFormat("Close failed ticket=%I64u", ticket));
      return ok;
     }

   //--- Partial close (reduce volume)
   bool ClosePartial(ulong ticket, double lots)
     {
      if(!PositionSelectByTicket(ticket)) return false;
      if((int)PositionGetInteger(POSITION_MAGIC) != m_magic) return false;
      double curLots = PositionGetDouble(POSITION_VOLUME);
      double mn      = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      lots = NormalizeLots(m_symbol, MathMin(lots, curLots - mn));
      if(lots < mn) return false;
      bool ok = m_trade.PositionClosePartial(ticket, lots);
      if(!ok) LogWarn("TradeManager", StringFormat("PartialClose failed ticket=%I64u lots=%.2f", ticket, lots));
      return ok;
     }

   //--- Close all EA positions (emergency / session end)
   void CloseAllPositions(const string reason)
     {
      LogWarn("TradeManager", "Close ALL | " + reason);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(!PositionSelectByTicket(t)) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
         m_trade.PositionClose(t);
        }
     }

   //--- Get all open EA tickets
   int GetOpenTickets(ulong &tickets[]) const
     {
      ArrayResize(tickets, 0);
      int cnt = 0;
      for(int i = 0; i < PositionsTotal(); i++)
        {
         ulong t = PositionGetTicket(i);
         if(!PositionSelectByTicket(t)) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
         ArrayResize(tickets, cnt + 1);
         tickets[cnt++] = t;
        }
      return cnt;
     }
  };

#endif // TRADEMANAGER_MQH

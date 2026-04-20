//+------------------------------------------------------------------+
//|                                                    Utilities.mqh |
//|                          EA102 - XAUUSD Prop Firm EA             |
//|                        Shared Utility Functions & Helpers        |
//+------------------------------------------------------------------+
#pragma once

//--- Logging levels
enum ENUM_LOG_LEVEL
  {
   LOG_DEBUG   = 0,
   LOG_INFO    = 1,
   LOG_WARNING = 2,
   LOG_ERROR   = 3
  };

//--- Global log level (can be controlled via input)
ENUM_LOG_LEVEL g_LogLevel = LOG_INFO;

//+------------------------------------------------------------------+
//| Logging helper                                                   |
//+------------------------------------------------------------------+
void LogMessage(ENUM_LOG_LEVEL level, const string module, const string msg)
  {
   if(level < g_LogLevel)
      return;

   string prefix = "";
   switch(level)
     {
      case LOG_DEBUG:   prefix = "[DEBUG]  "; break;
      case LOG_INFO:    prefix = "[INFO ]  "; break;
      case LOG_WARNING: prefix = "[WARN ]  "; break;
      case LOG_ERROR:   prefix = "[ERROR]  "; break;
     }

   string fullMsg = prefix + "[" + module + "] " + msg;
   Print(fullMsg);
  }

//+------------------------------------------------------------------+
//| Shorthand log functions                                          |
//+------------------------------------------------------------------+
void LogDebug(const string module, const string msg)   { LogMessage(LOG_DEBUG,   module, msg); }
void LogInfo(const string module, const string msg)    { LogMessage(LOG_INFO,    module, msg); }
void LogWarn(const string module, const string msg)    { LogMessage(LOG_WARNING, module, msg); }
void LogError(const string module, const string msg)   { LogMessage(LOG_ERROR,   module, msg); }

//+------------------------------------------------------------------+
//| Format double to string with N decimal places                    |
//+------------------------------------------------------------------+
string DoubleToStr(double val, int digits = 2)
  {
   return DoubleToString(val, digits);
  }

//+------------------------------------------------------------------+
//| Get current server time as formatted string                      |
//+------------------------------------------------------------------+
string GetTimeString(datetime t = 0)
  {
   if(t == 0) t = TimeCurrent();
   return TimeToString(t, TIME_DATE | TIME_MINUTES);
  }

//+------------------------------------------------------------------+
//| Convert minutes to seconds                                       |
//+------------------------------------------------------------------+
int MinutesToSeconds(int minutes)
  {
   return minutes * 60;
  }

//+------------------------------------------------------------------+
//| Get start of current trading day (server time, 00:00)           |
//+------------------------------------------------------------------+
datetime GetDayStart()
  {
   MqlDateTime mdt;
   TimeToStruct(TimeCurrent(), mdt);
   mdt.hour = 0;
   mdt.min  = 0;
   mdt.sec  = 0;
   return StructToTime(mdt);
  }

//+------------------------------------------------------------------+
//| Check whether two datetimes fall on the same calendar day       |
//+------------------------------------------------------------------+
bool SameDay(datetime t1, datetime t2)
  {
   MqlDateTime d1, d2;
   TimeToStruct(t1, d1);
   TimeToStruct(t2, d2);
   return (d1.year == d2.year && d1.mon == d2.mon && d1.day == d2.day);
  }

//+------------------------------------------------------------------+
//| Clamp a double between min and max                               |
//+------------------------------------------------------------------+
double Clamp(double val, double minVal, double maxVal)
  {
   if(val < minVal) return minVal;
   if(val > maxVal) return maxVal;
   return val;
  }

//+------------------------------------------------------------------+
//| Normalise lots to broker specifications                          |
//+------------------------------------------------------------------+
double NormalizeLots(const string symbol, double lots)
  {
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = Clamp(lots, minLot, maxLot);
   return NormalizeDouble(lots, 2);
  }

//+------------------------------------------------------------------+
//| Points to price distance for symbol                              |
//+------------------------------------------------------------------+
double PointsToPrice(const string symbol, double points)
  {
   return points * SymbolInfoDouble(symbol, SYMBOL_POINT);
  }

//+------------------------------------------------------------------+
//| Price distance to points for symbol                              |
//+------------------------------------------------------------------+
double PriceToPoints(const string symbol, double priceDiff)
  {
   double pt = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(pt == 0) return 0;
   return priceDiff / pt;
  }

//+------------------------------------------------------------------+
//| ATR value helper — returns ATR[shift] on given TF               |
//+------------------------------------------------------------------+
double GetATR(const string symbol, ENUM_TIMEFRAMES tf, int period, int shift = 1)
  {
   int handle = iATR(symbol, tf, period);
   if(handle == INVALID_HANDLE)
     {
      LogError("Utilities", "Failed to create ATR handle");
      return 0;
     }

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) <= 0)
     {
      IndicatorRelease(handle);
      return 0;
     }

   double val = buf[0];
   IndicatorRelease(handle);
   return val;
  }

//+------------------------------------------------------------------+
//| Get candle body size in points                                   |
//+------------------------------------------------------------------+
double CandleBodyPoints(const string symbol, ENUM_TIMEFRAMES tf, int shift = 1)
  {
   double o = iOpen(symbol, tf, shift);
   double c = iClose(symbol, tf, shift);
   return MathAbs(PriceToPoints(symbol, MathAbs(c - o)));
  }

//+------------------------------------------------------------------+
//| Is candle bullish?                                               |
//+------------------------------------------------------------------+
bool IsBullishCandle(const string symbol, ENUM_TIMEFRAMES tf, int shift = 1)
  {
   return iClose(symbol, tf, shift) > iOpen(symbol, tf, shift);
  }

//+------------------------------------------------------------------+
//| Is candle bearish?                                               |
//+------------------------------------------------------------------+
bool IsBearishCandle(const string symbol, ENUM_TIMEFRAMES tf, int shift = 1)
  {
   return iClose(symbol, tf, shift) < iOpen(symbol, tf, shift);
  }

//+------------------------------------------------------------------+
//| Get RSI value                                                    |
//+------------------------------------------------------------------+
double GetRSI(const string symbol, ENUM_TIMEFRAMES tf, int period, int shift = 1)
  {
   int handle = iRSI(symbol, tf, period, PRICE_CLOSE);
   if(handle == INVALID_HANDLE) return 50.0;

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) <= 0)
     {
      IndicatorRelease(handle);
      return 50.0;
     }

   double val = buf[0];
   IndicatorRelease(handle);
   return val;
  }

//+------------------------------------------------------------------+
//| Get EMA value                                                    |
//+------------------------------------------------------------------+
double GetEMA(const string symbol, ENUM_TIMEFRAMES tf, int period, int shift = 1)
  {
   int handle = iMA(symbol, tf, period, 0, MODE_EMA, PRICE_CLOSE);
   if(handle == INVALID_HANDLE) return 0.0;

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) <= 0)
     {
      IndicatorRelease(handle);
      return 0.0;
     }

   double val = buf[0];
   IndicatorRelease(handle);
   return val;
  }

//+------------------------------------------------------------------+
//| Pip value for current symbol (USD account)                       |
//+------------------------------------------------------------------+
double GetPipValue(const string symbol)
  {
   double tickVal  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double point    = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(tickSize == 0) return 0;
   return tickVal * point / tickSize;
  }

//+------------------------------------------------------------------+
//| Return human-readable order type string                          |
//+------------------------------------------------------------------+
string OrderTypeStr(ENUM_ORDER_TYPE t)
  {
   switch(t)
     {
      case ORDER_TYPE_BUY:             return "BUY";
      case ORDER_TYPE_SELL:            return "SELL";
      case ORDER_TYPE_BUY_LIMIT:       return "BUY_LIMIT";
      case ORDER_TYPE_SELL_LIMIT:      return "SELL_LIMIT";
      case ORDER_TYPE_BUY_STOP:        return "BUY_STOP";
      case ORDER_TYPE_SELL_STOP:       return "SELL_STOP";
      default:                         return "UNKNOWN";
     }
  }
//+------------------------------------------------------------------+

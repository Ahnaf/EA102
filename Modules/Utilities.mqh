//+------------------------------------------------------------------+
//|                                                    Utilities.mqh |
//|                        EA102 v2 - XAUUSD Prop Firm EA            |
//|                            Shared Helpers & Enumerations         |
//+------------------------------------------------------------------+
#ifndef UTILITIES_MQH
#define UTILITIES_MQH

//--- Logging levels
enum ENUM_LOG_LEVEL
  {
   LOG_DEBUG   = 0,
   LOG_INFO    = 1,
   LOG_WARNING = 2,
   LOG_ERROR   = 3
  };

//--- Trade mode: controls entry aggressiveness and filter thresholds
enum ENUM_TRADE_MODE
  {
   TRADE_MODE_SAFE       = 0,   // Full confirmation required
   TRADE_MODE_NORMAL     = 1,   // Moderate confirmation
   TRADE_MODE_AGGRESSIVE = 2    // Early entry after first strong signal
  };

//--- Direction of trade signal
enum ENUM_SIGNAL_DIR
  {
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
  };

//--- Which engine generated the trade
enum ENUM_SIGNAL_TYPE
  {
   SIGNAL_TYPE_NONE         = 0,
   SIGNAL_TYPE_CONTINUATION = 1,   // Trend-following (EMA + BOS + OB/FVG)
   SIGNAL_TYPE_REVERSAL     = 2,   // Counter-trend  (liq sweep + CHOCH)
   SIGNAL_TYPE_IMPULSE      = 3    // Momentum spike breakout
  };

//--- Global log level (set from EA input)
ENUM_LOG_LEVEL g_LogLevel = LOG_INFO;

//+------------------------------------------------------------------+
//| Logging                                                          |
//+------------------------------------------------------------------+
void LogMessage(ENUM_LOG_LEVEL level, const string module, const string msg)
  {
   if(level < g_LogLevel) return;
   string pfx;
   switch(level)
     {
      case LOG_DEBUG:   pfx = "[DBG]  "; break;
      case LOG_INFO:    pfx = "[INFO] "; break;
      case LOG_WARNING: pfx = "[WARN] "; break;
      case LOG_ERROR:   pfx = "[ERR]  "; break;
      default:          pfx = "[LOG]  "; break;
     }
   Print(pfx + "[" + module + "] " + msg);
  }

void LogDebug(const string m, const string s) { LogMessage(LOG_DEBUG,   m, s); }
void LogInfo (const string m, const string s) { LogMessage(LOG_INFO,    m, s); }
void LogWarn (const string m, const string s) { LogMessage(LOG_WARNING, m, s); }
void LogError(const string m, const string s) { LogMessage(LOG_ERROR,   m, s); }

//+------------------------------------------------------------------+
//| Time helpers                                                     |
//+------------------------------------------------------------------+
datetime GetDayStart()
  {
   MqlDateTime d;
   TimeToStruct(TimeCurrent(), d);
   d.hour = 0; d.min = 0; d.sec = 0;
   return StructToTime(d);
  }

bool SameDay(datetime t1, datetime t2)
  {
   MqlDateTime d1, d2;
   TimeToStruct(t1, d1);
   TimeToStruct(t2, d2);
   return (d1.year == d2.year && d1.mon == d2.mon && d1.day == d2.day);
  }

string GetTimeString(datetime t = 0)
  {
   if(t == 0) t = TimeCurrent();
   return TimeToString(t, TIME_DATE | TIME_MINUTES);
  }

//+------------------------------------------------------------------+
//| Math / price helpers                                             |
//+------------------------------------------------------------------+
double Clamp(double val, double lo, double hi)
  {
   if(val < lo) return lo;
   if(val > hi) return hi;
   return val;
  }

double NormalizeLots(const string symbol, double lots)
  {
   double mn  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double mx  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double stp = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(stp <= 0) stp = 0.01;
   lots = MathFloor(lots / stp) * stp;
   return Clamp(lots, mn, mx);
  }

double PriceToPoints(const string symbol, double diff)
  {
   double pt = SymbolInfoDouble(symbol, SYMBOL_POINT);
   return (pt > 0) ? diff / pt : 0;
  }

double PointsToPrice(const string symbol, double pts)
  {
   return pts * SymbolInfoDouble(symbol, SYMBOL_POINT);
  }

//+------------------------------------------------------------------+
//| Indicator helpers — on-demand handles (released after use)      |
//+------------------------------------------------------------------+
double GetATR(const string symbol, ENUM_TIMEFRAMES tf, int period, int shift = 1)
  {
   int h = iATR(symbol, tf, period);
   if(h == INVALID_HANDLE) return 0;
   double buf[];
   ArraySetAsSeries(buf, true);
   double val = 0;
   if(CopyBuffer(h, 0, shift, 1, buf) > 0) val = buf[0];
   IndicatorRelease(h);
   return val;
  }

double GetEMA(const string symbol, ENUM_TIMEFRAMES tf, int period, int shift = 1)
  {
   int h = iMA(symbol, tf, period, 0, MODE_EMA, PRICE_CLOSE);
   if(h == INVALID_HANDLE) return 0;
   double buf[];
   ArraySetAsSeries(buf, true);
   double val = 0;
   if(CopyBuffer(h, 0, shift, 1, buf) > 0) val = buf[0];
   IndicatorRelease(h);
   return val;
  }

double GetRSI(const string symbol, ENUM_TIMEFRAMES tf, int period, int shift = 1)
  {
   int h = iRSI(symbol, tf, period, PRICE_CLOSE);
   if(h == INVALID_HANDLE) return 50;
   double buf[];
   ArraySetAsSeries(buf, true);
   double val = 50;
   if(CopyBuffer(h, 0, shift, 1, buf) > 0) val = buf[0];
   IndicatorRelease(h);
   return val;
  }

//+------------------------------------------------------------------+
//| Candle helpers                                                   |
//+------------------------------------------------------------------+
bool IsBullishCandle(const string symbol, ENUM_TIMEFRAMES tf, int shift = 1)
  {
   return iClose(symbol, tf, shift) > iOpen(symbol, tf, shift);
  }

bool IsBearishCandle(const string symbol, ENUM_TIMEFRAMES tf, int shift = 1)
  {
   return iClose(symbol, tf, shift) < iOpen(symbol, tf, shift);
  }

double CandleBody(const string symbol, ENUM_TIMEFRAMES tf, int shift = 1)
  {
   return MathAbs(iClose(symbol, tf, shift) - iOpen(symbol, tf, shift));
  }

double CandleRange(const string symbol, ENUM_TIMEFRAMES tf, int shift = 1)
  {
   return iHigh(symbol, tf, shift) - iLow(symbol, tf, shift);
  }

double CandleUpperWick(const string symbol, ENUM_TIMEFRAMES tf, int shift = 1)
  {
   return iHigh(symbol, tf, shift) - MathMax(iOpen(symbol, tf, shift), iClose(symbol, tf, shift));
  }

double CandleLowerWick(const string symbol, ENUM_TIMEFRAMES tf, int shift = 1)
  {
   return MathMin(iOpen(symbol, tf, shift), iClose(symbol, tf, shift)) - iLow(symbol, tf, shift);
  }

double GetPipValue(const string symbol)
  {
   double tv = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double pt = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(ts == 0) return 0;
   return tv * pt / ts;
  }

string SignalDirStr(ENUM_SIGNAL_DIR d)
  {
   if(d == SIGNAL_BUY)  return "BUY";
   if(d == SIGNAL_SELL) return "SELL";
   return "NONE";
  }

string SignalTypeStr(ENUM_SIGNAL_TYPE t)
  {
   switch(t)
     {
      case SIGNAL_TYPE_CONTINUATION: return "CONTINUATION";
      case SIGNAL_TYPE_REVERSAL:     return "REVERSAL";
      case SIGNAL_TYPE_IMPULSE:      return "IMPULSE";
      default:                       return "NONE";
     }
  }

#endif // UTILITIES_MQH

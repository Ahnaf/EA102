//+------------------------------------------------------------------+
//|                                                     MainEA.mq5   |
//|                          EA102 — XAUUSD Prop Firm Expert Advisor |
//|              Full Modular SMC / ICT Strategy with Prop Protection|
//|                                                                  |
//|  Decision Gate:                                                  |
//|    AllowTrade = R AND S AND N AND F AND T AND U AND E AND X      |
//|  R = Risk protection (DD checks)                                 |
//|  S = Session allowed                                             |
//|  N = News filter passed                                          |
//|  F = Frequency gate passed                                       |
//|  T = HTF trend valid                                             |
//|  U = Setup valid (BOS/CHOCH/OB/FVG)                             |
//|  E = Entry confirmation (candle + momentum)                      |
//|  X = Exposure allowed                                            |
//+------------------------------------------------------------------+
#property copyright "EA102 - XAUUSD Prop EA"
#property version   "1.00"
#property strict

//--- Module includes
#include "Modules/Utilities.mqh"
#include "Modules/PropProtection.mqh"
#include "Modules/SessionFilter.mqh"
#include "Modules/NewsFilter.mqh"
#include "Modules/MarketStructure.mqh"
#include "Modules/SignalEngine.mqh"
#include "Modules/EntryEngine.mqh"
#include "Modules/RiskManager.mqh"
#include "Modules/TradeManager.mqh"
#include "Modules/ExitManager.mqh"
#include "Modules/Dashboard.mqh"

//==================================================================//
//                       INPUT PARAMETERS                           //
//==================================================================//

//--- [ General ]
input group            "═══ General ═══"
input int              InpMagicNumber      = 102000;       // Magic number
input string           InpSymbol           = "XAUUSD";     // Symbol
input string           InpTradeComment     = "EA102";      // Trade comment
input int              InpSlippage         = 30;           // Slippage (points)
input ENUM_LOG_LEVEL   InpLogLevel         = LOG_INFO;     // Log level

//--- [ Prop Protection ]
input group            "═══ Prop Protection ═══"
input double           InpMaxDDPct         = 10.0;         // Max drawdown % (hard stop)
input double           InpDailyDDPct       = 5.0;          // Daily DD % limit
input bool             InpUseDailyProfitLock = false;      // Enable daily profit lock
input double           InpDailyProfitLockPct = 3.0;        // Daily profit lock % target
input bool             InpUseEmergencyClose  = true;       // Emergency close on breach

//--- [ Trade Mode ]
input group            "═══ Trade Mode ═══"
input ENUM_TRADE_MODE  InpTradeMode        = TRADE_MODE_NORMAL; // Trading mode

//--- [ Session Filter ]
input group            "═══ Session Filter ═══"
input bool             InpSessionFilterOn  = true;         // Enable session filter
input bool             InpCloseOutsideSession = false;     // Close trades outside session
input bool             InpUseLondon        = true;         // Enable London session
input int              InpLondonStart      = 7;            // London start hour (UTC)
input int              InpLondonEnd        = 16;           // London end hour (UTC)
input bool             InpUseNewYork       = true;         // Enable New York session
input int              InpNYStart          = 12;           // NY start hour (UTC)
input int              InpNYEnd            = 20;           // NY end hour (UTC)
input bool             InpUseAsian         = false;        // Enable Asian session
input int              InpAsianStart       = 0;            // Asian start hour (UTC)
input int              InpAsianEnd         = 6;            // Asian end hour (UTC)

//--- [ News Filter ]
input group            "═══ News Filter ═══"
input bool             InpNewsFilterOn     = true;         // Enable news filter
input int              InpNewsMinsB4       = 30;           // Minutes before news to block
input int              InpNewsMinsAfter    = 15;           // Minutes after news to unblock
input bool             InpAutoBlockNFP     = true;         // Auto-block NFP Fridays
input int              InpNFPHour          = 12;           // NFP hour (UTC, e.g. 12 = 12:30)
input int              InpNFPWindowMins    = 60;           // Window ±minutes around NFP
input bool             InpAutoBlockFOMC    = true;         // Auto-block FOMC
input int              InpFOMCHour         = 18;           // FOMC announcement hour (UTC)
// Manual news event 1 (leave blank to disable)
input string           InpNews1DateTime    = "";           // News event 1: "YYYY.MM.DD HH:MM"
input string           InpNews1Desc        = "Manual News 1"; // News event 1 description
// Manual news event 2
input string           InpNews2DateTime    = "";           // News event 2: "YYYY.MM.DD HH:MM"
input string           InpNews2Desc        = "Manual News 2"; // News event 2 description
// Manual news event 3
input string           InpNews3DateTime    = "";           // News event 3: "YYYY.MM.DD HH:MM"
input string           InpNews3Desc        = "Manual News 3"; // News event 3 description

//--- [ Risk Management ]
input group            "═══ Risk Management ═══"
input double           InpRiskPct          = 1.0;          // Risk per trade (%)
input double           InpMaxExposurePct   = 3.0;          // Max total open risk (%)
input int              InpMaxOpenTrades    = 2;            // Max open trades
input double           InpMaxSymbolRiskPct = 3.0;          // Max per-symbol risk (%)
input bool             InpAllowHedge       = false;        // Allow hedge trades
input int              InpMaxTradesPerDay  = 3;            // Max trades per day (0=unlimited)
input int              InpMaxTradesPerSess = 2;            // Max trades per session (0=unlimited)

//--- [ Stop Loss ]
input group            "═══ Stop Loss ═══"
input int              InpSLMode           = 0;            // SL mode: 0=Structure, 1=ATR
input double           InpSLAtrMul         = 1.5;          // ATR multiplier for SL

//--- [ Take Profit ]
input group            "═══ Take Profit ═══"
input int              InpTPMode           = 2;            // TP mode: 0=Fixed RR, 1=Liquidity, 2=Hybrid
input double           InpRRRatio          = 2.0;          // Risk:Reward ratio

//--- [ Break-even ]
input group            "═══ Break-even ═══"
input bool             InpUseBE            = true;         // Enable break-even
input double           InpBETriggerR       = 1.0;          // BE trigger (R multiple)
input double           InpBEBufferPoints   = 30;           // BE buffer above entry (points)

//--- [ Partial Close ]
input group            "═══ Partial Close ═══"
input bool             InpUsePartialClose  = true;         // Enable partial close
input double           InpPartialCloseR    = 1.2;          // Partial close trigger (R)
input double           InpPartialClosePct  = 50.0;         // Partial close % of position

//--- [ Trailing Stop ]
input group            "═══ Trailing Stop ═══"
input bool             InpUseTrailing      = true;         // Enable ATR trailing stop
input int              InpTrailingAtrPeriod = 14;          // ATR period for trailing
input double           InpTrailingAtrMul   = 2.0;          // ATR multiplier for trail

//--- [ Signal Engine — HTF Trend ]
input group            "═══ Signal Engine (HTF Trend) ═══"
input ENUM_TIMEFRAMES  InpHTFTimeframe     = PERIOD_H1;    // Higher timeframe for trend
input int              InpEMAFast          = 21;           // EMA fast period
input int              InpEMASlow          = 55;           // EMA slow period
input int              InpRSIPeriod        = 14;           // RSI period
input double           InpRSIBullMin       = 50.0;         // RSI bullish min
input double           InpRSIBullMax       = 70.0;         // RSI bullish max
input double           InpRSIBearMin       = 30.0;         // RSI bearish min
input double           InpRSIBearMax       = 50.0;         // RSI bearish max

//--- [ Market Structure ]
input group            "═══ Market Structure ═══"
input ENUM_TIMEFRAMES  InpSetupTimeframe   = PERIOD_M15;   // Setup timeframe
input int              InpHTFLookback      = 150;          // HTF structure lookback bars
input int              InpHTFSwingStr      = 3;            // HTF swing strength
input int              InpSetupLookback    = 100;          // Setup structure lookback bars
input int              InpSetupSwingStr    = 2;            // Setup swing strength

//--- [ Entry Engine ]
input group            "═══ Entry Engine (M5) ═══"
input ENUM_TIMEFRAMES  InpEntryTimeframe   = PERIOD_M5;    // Entry timeframe
input int              InpEntryRSIPeriod   = 14;           // Entry RSI period
input double           InpEntryRSIOB       = 70.0;         // Entry RSI overbought
input double           InpEntryRSIOS       = 30.0;         // Entry RSI oversold
input double           InpEngulfRatio      = 1.5;          // Min engulf body ratio
input int              InpATRPeriod        = 14;           // ATR period for entries
input double           InpMinBodyATR       = 0.3;          // Min body/ATR ratio for strong bar

//--- [ Dashboard ]
input group            "═══ Dashboard ═══"
input bool             InpShowDashboard    = true;         // Show on-chart dashboard

//==================================================================//
//                     MODULE INSTANCES                             //
//==================================================================//

CPropProtection   *g_prop     = NULL;
CSessionFilter    *g_session  = NULL;
CNewsFilter       *g_news     = NULL;
CMarketStructure  *g_htfMS    = NULL;
CMarketStructure  *g_setupMS  = NULL;
CSignalEngine     *g_signal   = NULL;
CEntryEngine      *g_entry    = NULL;
CRiskManager      *g_risk     = NULL;
CTradeManager     *g_trade    = NULL;
CExitManager      *g_exit     = NULL;
CDashboard        *g_dash     = NULL;

//--- Bar tracking
datetime g_lastBarTime   = 0;    // Last M5 bar open time processed
datetime g_lastHTFBar    = 0;    // Last HTF bar processed
datetime g_lastSetupBar  = 0;    // Last setup bar processed
datetime g_lastDashUpdate = 0;   // Last dashboard refresh
bool     g_initialised   = false;

//==================================================================//
//                           OnInit                                 //
//==================================================================//
int OnInit()
  {
   g_LogLevel = InpLogLevel;
   LogInfo("MainEA", "===== EA102 XAUUSD Prop Firm EA Starting =====");

   string sym = (StringLen(InpSymbol) > 0) ? InpSymbol : _Symbol;

   //--- Allocate modules
   g_prop    = new CPropProtection();
   g_session = new CSessionFilter();
   g_news    = new CNewsFilter();
   g_htfMS   = new CMarketStructure();
   g_setupMS = new CMarketStructure();
   g_signal  = new CSignalEngine();
   g_entry   = new CEntryEngine();
   g_risk    = new CRiskManager();
   g_trade   = new CTradeManager();
   g_exit    = new CExitManager();
   g_dash    = new CDashboard();

   if(!g_prop.Init(sym,
                   InpMaxDDPct, InpDailyDDPct,
                   InpUseDailyProfitLock, InpDailyProfitLockPct,
                   InpUseEmergencyClose, InpMagicNumber))
     { Alert("PropProtection init failed"); return INIT_FAILED; }

   if(!g_session.Init(sym, InpMagicNumber,
                      InpSessionFilterOn, InpCloseOutsideSession,
                      InpUseLondon, InpLondonStart, InpLondonEnd,
                      InpUseNewYork, InpNYStart, InpNYEnd,
                      InpUseAsian, InpAsianStart, InpAsianEnd))
     { Alert("SessionFilter init failed"); return INIT_FAILED; }

   if(!g_news.Init(InpNewsFilterOn,
                   InpNewsMinsB4, InpNewsMinsAfter,
                   InpAutoBlockNFP, InpNFPHour, InpNFPWindowMins,
                   InpAutoBlockFOMC, InpFOMCHour))
     { Alert("NewsFilter init failed"); return INIT_FAILED; }

   // Register manual news events
   if(StringLen(InpNews1DateTime) > 4)
      g_news.AddEventFromString(InpNews1DateTime, InpNews1Desc);
   if(StringLen(InpNews2DateTime) > 4)
      g_news.AddEventFromString(InpNews2DateTime, InpNews2Desc);
   if(StringLen(InpNews3DateTime) > 4)
      g_news.AddEventFromString(InpNews3DateTime, InpNews3Desc);

   if(!g_htfMS.Init(sym, InpHTFTimeframe, InpHTFLookback, InpHTFSwingStr))
     { Alert("HTF MarketStructure init failed"); return INIT_FAILED; }

   if(!g_setupMS.Init(sym, InpSetupTimeframe, InpSetupLookback, InpSetupSwingStr))
     { Alert("Setup MarketStructure init failed"); return INIT_FAILED; }

   if(!g_signal.Init(sym, InpHTFTimeframe, InpSetupTimeframe,
                     InpEMAFast, InpEMASlow, InpRSIPeriod,
                     InpRSIBullMin, InpRSIBullMax, InpRSIBearMin, InpRSIBearMax,
                     InpTradeMode, g_htfMS, g_setupMS))
     { Alert("SignalEngine init failed"); return INIT_FAILED; }

   if(!g_entry.Init(sym, InpEntryTimeframe, InpSetupTimeframe,
                    InpEntryRSIPeriod, InpEntryRSIOB, InpEntryRSIOS,
                    InpEngulfRatio, InpATRPeriod, InpMinBodyATR,
                    InpSLMode, InpSLAtrMul, InpTPMode, InpRRRatio))
     { Alert("EntryEngine init failed"); return INIT_FAILED; }

   if(!g_risk.Init(sym, InpMagicNumber,
                   InpRiskPct, InpMaxExposurePct, InpMaxOpenTrades,
                   InpMaxSymbolRiskPct, InpTradeMode,
                   InpAllowHedge, InpMaxTradesPerDay, InpMaxTradesPerSess))
     { Alert("RiskManager init failed"); return INIT_FAILED; }

   if(!g_trade.Init(sym, InpMagicNumber, InpSlippage, InpTradeComment))
     { Alert("TradeManager init failed"); return INIT_FAILED; }

   if(!g_exit.Init(g_trade, sym, InpMagicNumber,
                   InpUseBE, InpBETriggerR, InpBEBufferPoints,
                   InpUsePartialClose, InpPartialCloseR, InpPartialClosePct,
                   InpUseTrailing, InpTrailingAtrPeriod, InpTrailingAtrMul))
     { Alert("ExitManager init failed"); return INIT_FAILED; }

   if(InpShowDashboard)
     {
      if(!g_dash.Init(g_prop, g_session, g_news, g_risk))
        { Alert("Dashboard init failed"); return INIT_FAILED; }
     }

   g_initialised = true;
   LogInfo("MainEA", "All modules initialised successfully");
   LogInfo("MainEA", StringFormat("Mode=%-10s Magic=%-8d Symbol=%s",
           EnumToString(InpTradeMode), InpMagicNumber, sym));

   return INIT_SUCCEEDED;
  }

//==================================================================//
//                           OnDeinit                               //
//==================================================================//
void OnDeinit(const int reason)
  {
   LogInfo("MainEA", StringFormat("Deinitialising | Reason=%d", reason));

   if(g_dash    != NULL) { g_dash.Destroy();    delete g_dash;    g_dash    = NULL; }
   if(g_exit    != NULL) { delete g_exit;        g_exit    = NULL; }
   if(g_trade   != NULL) { delete g_trade;       g_trade   = NULL; }
   if(g_risk    != NULL) { delete g_risk;         g_risk    = NULL; }
   if(g_entry   != NULL) { delete g_entry;        g_entry   = NULL; }
   if(g_signal  != NULL) { delete g_signal;       g_signal  = NULL; }
   if(g_setupMS != NULL) { delete g_setupMS;      g_setupMS = NULL; }
   if(g_htfMS   != NULL) { delete g_htfMS;        g_htfMS   = NULL; }
   if(g_news    != NULL) { delete g_news;          g_news    = NULL; }
   if(g_session != NULL) { delete g_session;       g_session = NULL; }
   if(g_prop    != NULL) { delete g_prop;          g_prop    = NULL; }
  }

//==================================================================//
//                           OnTick                                 //
//==================================================================//
void OnTick()
  {
   if(!g_initialised) return;

   string sym = (StringLen(InpSymbol) > 0) ? InpSymbol : _Symbol;

   //-------------------------------------------------------------
   // PRIORITY 1: Prop protection update (runs every tick)
   //-------------------------------------------------------------
   g_prop.Update();

   // PRIORITY 1a: Max DD breached → hard stop, close everything
   if(g_prop.IsMaxDDBreached())
     {
      static bool maxDDAlerted = false;
      if(!maxDDAlerted)
        {
         LogError("MainEA", "MAX DD BREACHED — EA permanently disabled for this session!");
         g_trade.CloseAllPositions("MAX DD BREACH");
         maxDDAlerted = true;
        }
      UpdateDashboard("DISABLED", false);
      return;
     }

   //-------------------------------------------------------------
   // EXIT MANAGEMENT — runs every tick on all open positions
   //-------------------------------------------------------------
   g_exit.Update(InpEntryTimeframe);

   //-------------------------------------------------------------
   // PRIORITY 2: Daily DD blocked — no new trades today
   //-------------------------------------------------------------
   if(g_prop.IsDailyDDBlocked())
     {
      UpdateDashboard("DAILY DD BLOCKED", false);
      return;
     }

   //-------------------------------------------------------------
   // Daily profit lock — block new entries  
   //-------------------------------------------------------------
   if(g_prop.IsDailyProfitLocked())
     {
      UpdateDashboard("PROFIT LOCKED", false);
      return;
     }

   //-------------------------------------------------------------
   // Only analyse signals on new M5 bars (avoid duplicate signals)
   //-------------------------------------------------------------
   datetime currentBarTime = iTime(sym, InpEntryTimeframe, 0);
   bool isNewEntryBar  = (currentBarTime != g_lastBarTime);

   datetime currentHTFBar   = iTime(sym, InpHTFTimeframe,   0);
   bool isNewHTFBar    = (currentHTFBar != g_lastHTFBar);

   datetime currentSetupBar = iTime(sym, InpSetupTimeframe, 0);
   bool isNewSetupBar  = (currentSetupBar != g_lastSetupBar);

   // Update market structure on new bars
   if(isNewHTFBar)
     {
      g_htfMS.Update();
      g_htfMS.PruneStaleOBs();
      g_lastHTFBar = currentHTFBar;
     }

   if(isNewSetupBar)
     {
      g_setupMS.Update();
      g_setupMS.PruneStaleOBs();
      g_lastSetupBar = currentSetupBar;
     }

   //-------------------------------------------------------------
   // PRIORITY 3: Session filter
   //-------------------------------------------------------------
   g_session.CloseTradesOutsideSession();   // Handles close-outside if configured

   if(!g_session.IsInSession())
     {
      UpdateDashboard("OUT OF SESSION", false);
      return;
     }

   //-------------------------------------------------------------
   // PRIORITY 4: News filter
   //-------------------------------------------------------------
   if(g_news.IsNewsBlocked())
     {
      UpdateDashboard("NEWS BLOCKED: " + g_news.GetBlockReason(), false);
      return;
     }

   //-------------------------------------------------------------
   // Only evaluate new trade signals on new M5 bar
   //-------------------------------------------------------------
   if(!isNewEntryBar)
     {
      UpdateDashboard("ACTIVE", true);
      return;
     }
   g_lastBarTime = currentBarTime;

   //-------------------------------------------------------------
   // PRIORITY 5: Frequency gate (condition F)
   //-------------------------------------------------------------
   string freqReason = "";
   if(!g_risk.IsFrequencyGateOpen(freqReason))
     {
      LogDebug("MainEA", "Freq gate closed: " + freqReason);
      UpdateDashboard("COOLDOWN", true);
      return;
     }

   //-------------------------------------------------------------
   // PRIORITY 6: Signal engine (T + U)
   //-------------------------------------------------------------
   SignalPackage sig = g_signal.Evaluate();

   if(sig.direction == SIGNAL_NONE)
     {
      LogDebug("MainEA", "No signal: " + sig.reason);
      UpdateDashboard("ACTIVE", true);
      return;
     }

   //-------------------------------------------------------------
   // Update entry engine swings from setup structure
   //-------------------------------------------------------------
   g_entry.SetSwings(g_setupMS.GetLastSwingHigh(), g_setupMS.GetLastSwingLow());

   //-------------------------------------------------------------
   // PRIORITY 6b: Entry confirmation (condition E)
   //-------------------------------------------------------------
   EntryConfirmation ec = g_entry.CheckEntry(sig.direction);

   if(!ec.confirmed)
     {
      LogDebug("MainEA", "Entry not confirmed: " + ec.reason);
      UpdateDashboard("WAITING ENTRY", true);
      return;
     }

   //-------------------------------------------------------------
   // PRIORITY 7: Exposure gate (condition X)
   //-------------------------------------------------------------
   double slDist = MathAbs(ec.entryPrice - ec.stopLoss);
   string expReason = "";

   if(!g_risk.IsExposureAllowed(sig.direction, slDist, expReason))
     {
      LogDebug("MainEA", "Exposure blocked: " + expReason);
      UpdateDashboard("EXPOSURE LIMIT", false);
      return;
     }

   //-------------------------------------------------------------
   // ALL GATES PASSED — Calculate lot size and execute trade
   //-------------------------------------------------------------
   double lots = g_risk.CalculateLotSize(ec.entryPrice, ec.stopLoss);

   ulong ticket = 0;
   if(g_trade.OpenTrade(ec, lots, ticket))
     {
      g_risk.OnTradeOpened();
      LogInfo("MainEA", StringFormat(
         "NEW TRADE | %s %.2f @ %.5f | SL=%.5f TP=%.5f | Score=%.2f | %s",
         (sig.direction == SIGNAL_BUY ? "BUY" : "SELL"),
         lots, ec.entryPrice, ec.stopLoss, ec.takeProfit,
         sig.setupScore, sig.reason));
     }

   UpdateDashboard("ACTIVE", true);
  }

//==================================================================//
//                     Helper Functions                             //
//==================================================================//

//--- Refresh dashboard with current status
void UpdateDashboard(const string statusText, bool active)
  {
   if(!InpShowDashboard || g_dash == NULL) return;

   // Only refresh every second to avoid chart spam
   datetime now = TimeCurrent();
   if(now - g_lastDashUpdate < 1) return;
   g_lastDashUpdate = now;

   g_dash.SetStatus(active, statusText);
   g_dash.Update();
  }

//--- Called when a trade is closed (to detect loss for cooldown)
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
  {
   if(!g_initialised) return;

   // Detect position close of our magic number
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      if(trans.deal_type == DEAL_TYPE_BUY || trans.deal_type == DEAL_TYPE_SELL)
        {
         if((int)trans.position == 0) return;

         // Check deal profit to detect loss
         ulong dealTicket = trans.deal;
         if(HistoryDealSelect(dealTicket))
           {
            int dealMagic = (int)HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
            if(dealMagic != InpMagicNumber) return;

            double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            if(dealProfit < 0)
              {
               LogInfo("MainEA", StringFormat("Loss detected: $%.2f | Cooldown started", dealProfit));
               g_risk.OnTradeLoss();
              }
           }
        }
     }
  }
//+------------------------------------------------------------------+

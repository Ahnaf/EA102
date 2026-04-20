//+------------------------------------------------------------------+
//|                                                      MainEA.mq5  |
//|                        EA102 v2 - XAUUSD Prop Firm EA            |
//|     Three-Engine Architecture: Continuation + Reversal + Exit   |
//+------------------------------------------------------------------+
#property copyright "EA102 v2"
#property version   "2.00"
#property strict

//--- Module includes (dependency order)
#include "Modules/Utilities.mqh"
#include "Modules/PropProtection.mqh"
#include "Modules/SessionFilter.mqh"
#include "Modules/NewsFilter.mqh"
#include "Modules/MarketStructure.mqh"
#include "Modules/SignalEngine.mqh"
#include "Modules/TradeManager.mqh"
#include "Modules/EntryEngine.mqh"
#include "Modules/RiskManager.mqh"
#include "Modules/ExitManager.mqh"
#include "Modules/Dashboard.mqh"

//+------------------------------------------------------------------+
//|  ═══════════════  INPUT PARAMETERS  ═══════════════             |
//+------------------------------------------------------------------+

//--- Core
input string          InpSection1        = "── Core ──";
input int             InpMagicNumber     = 102002;
input string          InpEAComment       = "EA102v2";
input ENUM_TRADE_MODE InpTradeMode       = TRADE_MODE_NORMAL;  // SAFE / NORMAL / AGGRESSIVE
input int             InpSlippage        = 30;

//--- Timeframes
input string          InpSection2        = "── Timeframes ──";
input ENUM_TIMEFRAMES InpHTF_TF          = PERIOD_H1;    // Higher timeframe trend (EMAs, structure)
input ENUM_TIMEFRAMES InpSetupTF         = PERIOD_M15;   // Setup / OB / FVG timeframe
input ENUM_TIMEFRAMES InpEntryTF         = PERIOD_M5;    // Entry confirmation candle TF

//--- Prop Firm Protection (R = Risk gate)
input string          InpSection3        = "── Prop Protection ──";
input double          InpMaxDDPct        = 9.0;          // Hard max drawdown %
input double          InpDailyDDPct      = 4.5;          // Daily drawdown limit %
input bool            InpUseProfitLock   = true;
input double          InpProfitLockPct   = 4.0;          // Lock profit after this daily gain %
input bool            InpEmergencyClose  = true;

//--- Session (S gate)
input string          InpSection4        = "── Session Filter ──";
input bool            InpUseSession      = true;
input bool            InpSessionClose    = false;
input bool            InpUseLondon       = true;
input int             InpLondonStart     = 7;
input int             InpLondonEnd       = 15;
input bool            InpUseNewYork      = true;
input int             InpNYStart         = 13;
input int             InpNYEnd           = 20;
input bool            InpUseAsian        = false;
input int             InpAsianStart      = 0;
input int             InpAsianEnd        = 5;

//--- News (N gate)
input string          InpSection5        = "── News Filter ──";
input bool            InpUseNews         = true;
input int             InpNewsMinsBefore  = 30;
input int             InpNewsMinsAfter   = 20;
input bool            InpAutoNFP         = true;
input int             InpNFP_Hour        = 12;
input int             InpNFP_Window      = 60;
input bool            InpAutoFOMC        = true;
input int             InpFOMC_Hour       = 18;

//--- Signal Engines
input string          InpSection6        = "── Signal Engines ──";
input int             InpEMA_Fast        = 21;
input int             InpEMA_Slow        = 55;
input int             InpRSI_Period      = 14;
input double          InpRSI_OB          = 70.0;
input double          InpRSI_OS          = 30.0;
input int             InpMS_Lookback     = 40;           // Market structure lookback (bars)
input int             InpMS_SwingStr     = 3;            // Swing definition strength
// Score thresholds (auto-adjusted by mode, but can override)
input double          InpCont_ThreshSafe = 0.70;
input double          InpCont_ThreshNorm = 0.50;
input double          InpCont_ThreshAggr = 0.35;
input double          InpRev_ThreshSafe  = 0.75;
input double          InpRev_ThreshNorm  = 0.60;
input double          InpRev_ThreshAggr  = 0.45;

//--- Entry Engine
input string          InpSection7        = "── Entry Engine ──";
input double          InpEngulfRatio     = 1.2;          // Engulfing body ratio
input int             InpEntry_ATR_Per   = 14;
input double          InpMinBodyATR      = 0.30;         // Min body as ATR fraction
input int             InpSL_Mode         = 0;            // 0=Structure, 1=ATR
input double          InpSL_ATR_Mul      = 1.5;
input int             InpTP_Mode         = 0;            // 0=FixedRR, 1=Liquidity, 2=Hybrid
input double          InpRR_Ratio        = 2.0;

//--- Risk Manager (F + X gates)
input string          InpSection8        = "── Risk Manager ──";
input double          InpRiskPct         = 0.75;         // Risk per trade %
input double          InpMaxExposurePct  = 3.0;          // Total open risk %
input int             InpMaxOpenTrades   = 2;
input bool            InpAllowHedge      = false;
input int             InpMaxTradesDay    = 6;
input int             InpMaxTradesSess   = 3;

//--- Exit / Profit Protection Engine
input string          InpSection9        = "── Exit / Profit Protection ──";
input bool            InpUseBE           = true;
input double          InpBE_TriggerR     = 0.9;          // Apply BE when R >= this
input double          InpBE_BufferPts    = 20;           // Extra buffer (points) above entry
input bool            InpUsePartial      = true;
input double          InpPartial_R       = 1.0;          // Partial close trigger R
input double          InpPartial_Pct     = 0.50;         // Fraction to close (0.5 = 50%)
input bool            InpUseGiveback     = true;
input double          InpGiveR1          = 1.5;          // Give-back lower band
input double          InpGiveDrop1       = 0.6;          // Drop from maxR to trigger
input double          InpGiveR2          = 2.0;          // Give-back upper band
input double          InpGiveDrop2       = 0.9;          // Drop from maxR to trigger
input bool            InpRevExit         = true;
input double          InpRevExitScore    = 0.55;         // Min reversal score for reversal exit
input bool            InpUseTrail        = true;
input int             InpTrail_ATR_Per   = 14;
input double          InpTrail_ATR_Mul   = 1.8;

//--- Dashboard
input string          InpSection10       = "── Dashboard ──";
input bool            InpShowDashboard   = true;
input ENUM_LOG_LEVEL  InpLogLevel        = LOG_INFO;

//+------------------------------------------------------------------+
//|  Global module instances                                         |
//+------------------------------------------------------------------+
CPropProtection  g_prop;
CSessionFilter   g_session;
CNewsFilter      g_news;
CMarketStructure g_htfMS;
CMarketStructure g_setupMS;
CSignalEngine    g_signal;
CRiskManager     g_risk;
CTradeManager    g_trade;
CEntryEngine     g_entry;
CExitManager     g_exit;
CDashboard       g_dash;

//--- State
datetime g_lastHTFBar   = 0;
datetime g_lastSetupBar = 0;
datetime g_lastEntryBar = 0;

//--- Dashboard data
double g_contScoreBuy  = 0;
double g_contScoreSell = 0;
double g_revScore      = 0;
ENUM_SIGNAL_DIR  g_revDir       = SIGNAL_NONE;
ENUM_SIGNAL_TYPE g_lastSigType  = SIGNAL_TYPE_NONE;

//+------------------------------------------------------------------+
//| Threshold helper (returns threshold based on current mode)       |
//+------------------------------------------------------------------+
double GetContThreshold()
  {
   switch(InpTradeMode)
     {
      case TRADE_MODE_SAFE:       return InpCont_ThreshSafe;
      case TRADE_MODE_NORMAL:     return InpCont_ThreshNorm;
      case TRADE_MODE_AGGRESSIVE: return InpCont_ThreshAggr;
      default:                    return InpCont_ThreshNorm;
     }
  }
double GetRevThreshold()
  {
   switch(InpTradeMode)
     {
      case TRADE_MODE_SAFE:       return InpRev_ThreshSafe;
      case TRADE_MODE_NORMAL:     return InpRev_ThreshNorm;
      case TRADE_MODE_AGGRESSIVE: return InpRev_ThreshAggr;
      default:                    return InpRev_ThreshNorm;
     }
  }

//+------------------------------------------------------------------+
//| Get best open trade R for dashboard                              |
//+------------------------------------------------------------------+
void GetBestOpenR(double &maxR, double &curR)
  {
   maxR = 0; curR = 0;
   ulong tickets[];
   int cnt = g_trade.GetOpenTickets(tickets);
   double bestMax = -999;
   for(int i = 0; i < cnt; i++)
     {
      double m = g_exit.GetMaxR(tickets[i]);
      double c = g_exit.GetCurrentR(tickets[i]);
      if(m > bestMax) { bestMax = m; maxR = m; curR = c; }
     }
   if(bestMax < 0) { maxR = 0; curR = 0; }
  }

//+------------------------------------------------------------------+
//| Expert initialisation                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_LogLevel = InpLogLevel;
   LogInfo("MainEA", "═══ EA102 v2 STARTING ═══");

   string sym = _Symbol;
   int    mag = InpMagicNumber;

   //--- Prop Protection
   if(!g_prop.Init(sym, InpMaxDDPct, InpDailyDDPct,
                   InpUseProfitLock, InpProfitLockPct,
                   InpEmergencyClose, mag)) return INIT_FAILED;

   //--- Session Filter
   if(!g_session.Init(sym, mag, InpUseSession, InpSessionClose,
                      InpUseLondon, InpLondonStart, InpLondonEnd,
                      InpUseNewYork, InpNYStart, InpNYEnd,
                      InpUseAsian, InpAsianStart, InpAsianEnd)) return INIT_FAILED;

   //--- News Filter
   if(!g_news.Init(InpUseNews, InpNewsMinsBefore, InpNewsMinsAfter,
                   InpAutoNFP, InpNFP_Hour, InpNFP_Window,
                   InpAutoFOMC, InpFOMC_Hour)) return INIT_FAILED;

   //--- Market Structure (HTF + Setup TF)
   if(!g_htfMS.Init(sym, InpHTF_TF,   InpMS_Lookback, InpMS_SwingStr)) return INIT_FAILED;
   if(!g_setupMS.Init(sym, InpSetupTF, InpMS_Lookback, InpMS_SwingStr)) return INIT_FAILED;

   //--- Signal Engine (dual: Continuation + Reversal)
   if(!g_signal.Init(sym, InpHTF_TF, InpSetupTF,
                     InpEMA_Fast, InpEMA_Slow, InpRSI_Period,
                     InpTradeMode, &g_htfMS, &g_setupMS)) return INIT_FAILED;

   //--- Risk Manager
   if(!g_risk.Init(sym, mag, InpRiskPct, InpMaxExposurePct,
                   InpMaxOpenTrades, InpTradeMode,
                   InpAllowHedge, InpMaxTradesDay, InpMaxTradesSess)) return INIT_FAILED;

   //--- Trade Manager
   if(!g_trade.Init(sym, mag, InpSlippage, InpEAComment)) return INIT_FAILED;

   //--- Entry Engine
   if(!g_entry.Init(sym, InpEntryTF, InpSetupTF,
                    InpRSI_Period, InpRSI_OB, InpRSI_OS,
                    InpEngulfRatio, InpEntry_ATR_Per, InpMinBodyATR,
                    InpSL_Mode, InpSL_ATR_Mul, InpTP_Mode, InpRR_Ratio)) return INIT_FAILED;

   //--- Exit Manager (Profit Protection Engine)
   if(!g_exit.Init(&g_trade, sym, mag,
                   InpUseBE,   InpBE_TriggerR, InpBE_BufferPts,
                   InpUsePartial, InpPartial_R, InpPartial_Pct,
                   InpUseGiveback,
                   InpGiveR1, InpGiveDrop1,
                   InpGiveR2, InpGiveDrop2,
                   InpRevExit, InpRevExitScore,
                   InpUseTrail, InpTrail_ATR_Per, InpTrail_ATR_Mul,
                   InpSetupTF)) return INIT_FAILED;

   //--- Dashboard
   if(InpShowDashboard)
      g_dash.Init(&g_prop, &g_session, &g_news, &g_risk);

   LogInfo("MainEA", "══ Initialisation complete ══");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_dash.Destroy();
   LogInfo("MainEA", "Deinitialized | reason=" + IntegerToString(reason));
  }

//+------------------------------------------------------------------+
//| Main tick                                                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   //================================================================
   // STEP 0 — Reversal signal (computed EVERY tick for ExitManager)
   //================================================================
   ReversalSignal revSig = g_signal.GetReversalSignal();
   g_revScore = revSig.score;
   g_revDir   = revSig.direction;

   //================================================================
   // STEP 1 — PROFIT PROTECTION ENGINE (runs EVERY tick, BEFORE all)
   //================================================================
   g_exit.Update(InpEntryTF, revSig);

   //================================================================
   // STEP 2 — Prop Protection update (checks DD, triggers close)
   //================================================================
   g_prop.Update();

   if(g_prop.IsMaxDDBreached())
     {
      g_dash.SetStatus(false, "MAX DD HIT");
      if(InpShowDashboard)
        {
         double mr, cr; GetBestOpenR(mr, cr);
         g_dash.SetEngineScores(g_contScoreBuy, g_contScoreSell, g_revScore, g_revDir, g_lastSigType, mr, cr);
         g_dash.Update();
        }
      return;
     }

   if(g_prop.IsDailyDDBlocked())
     {
      g_dash.SetStatus(false, "DAILY BLOCKED");
      if(InpShowDashboard)
        {
         double mr, cr; GetBestOpenR(mr, cr);
         g_dash.SetEngineScores(g_contScoreBuy, g_contScoreSell, g_revScore, g_revDir, g_lastSigType, mr, cr);
         g_dash.Update();
        }
      return;
     }

   if(g_prop.IsDailyProfitLocked())
     {
      g_dash.SetStatus(false, "PROFIT LOCKED");
      if(InpShowDashboard)
        {
         double mr, cr; GetBestOpenR(mr, cr);
         g_dash.SetEngineScores(g_contScoreBuy, g_contScoreSell, g_revScore, g_revDir, g_lastSigType, mr, cr);
         g_dash.Update();
        }
      return;
     }

   g_dash.SetStatus(true, "ACTIVE");

   //================================================================
   // STEP 3 — Session gate (S)
   //================================================================
   if(!g_session.IsInSession()) { UpdateDash(); return; }
   g_session.CloseTradesOutsideSession();

   //================================================================
   // STEP 4 — News gate (N)
   //================================================================
   if(g_news.IsNewsBlocked()) { UpdateDash(); return; }

   //================================================================
   // STEP 5 — New-bar check on Entry TF (reduces noise)
   //================================================================
   datetime currentBar = iTime(_Symbol, InpEntryTF, 0);
   bool isNewEntryBar  = (currentBar != g_lastEntryBar);
   if(isNewEntryBar) g_lastEntryBar = currentBar;

   //--- Market structure: update on new bar of respective TF
   if(iTime(_Symbol, InpHTF_TF, 0) != g_lastHTFBar)
     {
      g_lastHTFBar = iTime(_Symbol, InpHTF_TF, 0);
      g_htfMS.Update();
      g_htfMS.PruneStaleOBs();
     }
   if(iTime(_Symbol, InpSetupTF, 0) != g_lastSetupBar)
     {
      g_lastSetupBar = iTime(_Symbol, InpSetupTF, 0);
      g_setupMS.Update();
      g_setupMS.PruneStaleOBs();
     }

   //--- Update dashboard on every tick (to show live R)
   {
      double mr, cr; GetBestOpenR(mr, cr);
      g_contScoreBuy  = g_signal.GetContinuationSignal(SIGNAL_BUY).score;
      g_contScoreSell = g_signal.GetContinuationSignal(SIGNAL_SELL).score;
      g_dash.SetEngineScores(g_contScoreBuy, g_contScoreSell, g_revScore, g_revDir, g_lastSigType, mr, cr);
      if(InpShowDashboard) g_dash.Update();
   }

   //--- Only evaluate new entries on new Entry-TF bars
   if(!isNewEntryBar) return;

   //================================================================
   // STEP 6 — Frequency gate (F)
   //================================================================
   g_risk.UpdateDailyCounters();
   string freqReason;
   if(!g_risk.IsFrequencyGateOpen(freqReason)) { LogDebug("MainEA", "FreqGate: " + freqReason); return; }

   //================================================================
   // STEP 7 — Get BOTH engine signals
   //================================================================
   ContinuationSignal contBuy  = g_signal.GetContinuationSignal(SIGNAL_BUY);
   ContinuationSignal contSell = g_signal.GetContinuationSignal(SIGNAL_SELL);
   g_contScoreBuy  = contBuy.score;
   g_contScoreSell = contSell.score;

   // Continuation: pick direction with higher score
   ContinuationSignal bestCont;
   if(contBuy.score >= contSell.score) bestCont = contBuy;
   else                                bestCont = contSell;

   // Reversal already computed above
   double contThresh = GetContThreshold();
   double revThresh  = GetRevThreshold();

   //================================================================
   // STEP 8 — Impulse entry check (AGGRESSIVE / NORMAL)
   //================================================================
   ENUM_SIGNAL_DIR impulseDir = SIGNAL_NONE;
   bool hasImpulse = (InpTradeMode >= TRADE_MODE_NORMAL) && g_entry.IsImpulseEntry(impulseDir);

   //================================================================
   // STEP 9 — Determine winning signal (OR logic — Reversal OR Cont.)
   //   Priority: Reversal (highest score, independent) > Continuation > Impulse
   //================================================================
   ENUM_SIGNAL_DIR  tradeDir   = SIGNAL_NONE;
   ENUM_SIGNAL_TYPE tradeType  = SIGNAL_TYPE_NONE;
   double           tradeSc    = 0;
   string           tradeRsn   = "";

   // Reversal engine wins if it meets threshold
   if(revSig.direction != SIGNAL_NONE && revSig.score >= revThresh)
     {
      tradeDir  = revSig.direction;
      tradeType = SIGNAL_TYPE_REVERSAL;
      tradeSc   = revSig.score;
      tradeRsn  = revSig.reason;
      LogInfo("MainEA", StringFormat("REVERSAL ENGINE | dir=%s score=%.0f%% | %s",
              SignalDirStr(tradeDir), tradeSc * 100, tradeRsn));
     }
   // Continuation engine (only if reversal not taken)
   else if(bestCont.direction != SIGNAL_NONE && bestCont.score >= contThresh)
     {
      tradeDir  = bestCont.direction;
      tradeType = SIGNAL_TYPE_CONTINUATION;
      tradeSc   = bestCont.score;
      tradeRsn  = bestCont.reason;
      LogInfo("MainEA", StringFormat("CONTINUATION ENGINE | dir=%s score=%.0f%% | %s",
              SignalDirStr(tradeDir), tradeSc * 100, tradeRsn));
     }
   // Impulse breakout (AGGRESSIVE/NORMAL only)
   else if(hasImpulse && InpTradeMode >= TRADE_MODE_NORMAL)
     {
      tradeDir  = impulseDir;
      tradeType = SIGNAL_TYPE_IMPULSE;
      tradeSc   = 0.50;
      tradeRsn  = "Impulse breakout";
      LogInfo("MainEA", StringFormat("IMPULSE ENGINE | dir=%s", SignalDirStr(impulseDir)));
     }

   if(tradeDir == SIGNAL_NONE) return;

   //================================================================
   // STEP 10 — Entry confirmation (staged mode-based)
   //================================================================
   g_entry.SetSwings(g_setupMS.GetLastSwingHigh(), g_setupMS.GetLastSwingLow());
   EntryConfirmation ec = g_entry.CheckEntry(tradeDir, tradeType, InpTradeMode, tradeSc);

   if(!ec.confirmed)
     {
      LogDebug("MainEA", "Entry not confirmed: " + ec.reason);
      return;
     }

   //================================================================
   // STEP 11 — Exposure gate (X)
   //================================================================
   string expReason;
   if(!g_risk.IsExposureAllowed(tradeDir, MathAbs(ec.entryPrice - ec.stopLoss), expReason))
     {
      LogDebug("MainEA", "ExposureGate: " + expReason);
      return;
     }

   //================================================================
   // STEP 12 — Calculate lot size and EXECUTE
   //================================================================
   double lots = g_risk.CalculateLotSize(ec.entryPrice, ec.stopLoss);
   if(lots <= 0)
     {
      LogWarn("MainEA", "Lot size = 0, skip");
      return;
     }

   ulong ticket = 0;
   if(g_trade.OpenTrade(ec, lots, ticket))
     {
      g_lastSigType = tradeType;
      g_exit.RegisterTrade(ticket, tradeDir, tradeType, ec.entryPrice, ec.stopLoss);
      g_risk.OnTradeOpened();
      LogInfo("MainEA", StringFormat("▶ TRADE OPENED | %s %.2f lots | SL=%.5f TP=%.5f | Score=%.0f%% | Type=%s",
              SignalDirStr(tradeDir), lots, ec.stopLoss, ec.takeProfit,
              tradeSc * 100, SignalTypeStr(tradeType)));
     }
  }

//+------------------------------------------------------------------+
//| Dashboard helper (called in early-return paths)                 |
//+------------------------------------------------------------------+
void UpdateDash()
  {
   if(!InpShowDashboard) return;
   double mr, cr; GetBestOpenR(mr, cr);
   g_dash.SetEngineScores(g_contScoreBuy, g_contScoreSell, g_revScore, g_revDir, g_lastSigType, mr, cr);
   g_dash.Update();
  }

//+------------------------------------------------------------------+
//| Trade transaction handler — detect loss for cooldown            |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   long   entry  = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);

   // Detect trade closure — if in loss, trigger loss cooldown
   if(entry == DEAL_ENTRY_OUT && profit < 0)
      g_risk.OnTradeLoss();
  }

//+------------------------------------------------------------------+
//| END OF MainEA.mq5                                               |
//+------------------------------------------------------------------+

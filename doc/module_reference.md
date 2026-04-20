# EA102 — Module Reference

Per-module class summary, key methods, and constructor inputs.

---

## Utilities.mqh

Global helpers — no class, standalone functions.

| Function | Signature | Description |
|---|---|---|
| `LogDebug/Info/Warn/Error` | `(module, msg)` | Levelled logging to Print() |
| `GetATR` | `(symbol, tf, period, shift)` | Returns ATR value |
| `GetEMA` | `(symbol, tf, period, shift)` | Returns EMA value |
| `GetRSI` | `(symbol, tf, period, shift)` | Returns RSI value |
| `NormalizeLots` | `(symbol, lots)` | Clamps/rounds to broker spec |
| `GetDayStart` | `()` | Returns 00:00 of current server day |
| `SameDay` | `(t1, t2)` | True if both datetimes on same calendar day |
| `CandleBodyPoints` | `(symbol, tf, shift)` | Body size in points |
| `IsBullishCandle` | `(symbol, tf, shift)` | Close > Open |

---

## PropProtection.mqh — `CPropProtection`

### Init Parameters
| Param | Type | Description |
|---|---|---|
| `symbol` | string | Trading symbol |
| `maxDDPct` | double | Max account DD % (hard stop, e.g. 10.0) |
| `dailyDDPct` | double | Daily DD % limit (e.g. 5.0) |
| `useProfitLock` | bool | Enable daily profit lock |
| `profitLockPct` | double | Target % to lock (e.g. 3.0) |
| `useEmergencyClose` | bool | Auto-close on breach |
| `magicNumber` | int | EA magic number |

### Key Methods
| Method | Returns | Description |
|---|---|---|
| `Update()` | void | Run daily reset + all checks each tick |
| `IsMaxDDBreached()` | bool | Hard stop triggered |
| `IsDailyDDBlocked()` | bool | Day blocked for new trades |
| `IsDailyProfitLocked()` | bool | Profit target hit, entries blocked |
| `IsTradingAllowed()` | bool | Combined gate — all clear |
| `EmergencyCloseAll(reason)` | void | Force close all EA positions |
| `GetDailyDDPct()` | double | Current daily DD % |
| `GetMaxDDPct()` | double | Current total DD % from start balance |
| `GetDailyPL()` | double | Today's P/L in account currency |
| `GetStatusString()` | string | Human-readable status |

---

## SessionFilter.mqh — `CSessionFilter`

### Init Parameters
| Param | Type | Description |
|---|---|---|
| `filterEnabled` | bool | Master on/off |
| `closeOutside` | bool | Auto-close positions outside session |
| `useLondon` | bool | Enable London window |
| `londonStart/End` | int | UTC hour (e.g. 7, 16) |
| `useNewYork` | bool | Enable NY window |
| `nyStart/End` | int | UTC hour (e.g. 12, 20) |
| `useAsian` | bool | Enable Asian window |
| `asianStart/End` | int | UTC hour (e.g. 0, 6) |

### Key Methods
| Method | Returns | Description |
|---|---|---|
| `IsInSession()` | bool | True if current time is within any enabled session |
| `GetActiveSessionName()` | string | "London" / "New York" / "Asian" / "None" |
| `CloseTradesOutsideSession()` | void | Closes EA positions if outside session (if enabled) |

---

## NewsFilter.mqh — `CNewsFilter`

### Init Parameters
| Param | Type | Description |
|---|---|---|
| `filterEnabled` | bool | Master on/off |
| `defaultMinsBefore` | int | Block window before event (e.g. 30) |
| `defaultMinsAfter` | int | Unblock window after event (e.g. 15) |
| `autoBlockNFP` | bool | Auto-detect first-Friday NFP |
| `nfpHour` | int | UTC hour of NFP (e.g. 12) |
| `nfpWindowMins` | int | ± minutes around NFP |
| `autoBlockFOMC` | bool | Auto-detect Wed/Thu FOMC |
| `fomcHour` | int | UTC hour of FOMC |

### Key Methods
| Method | Returns | Description |
|---|---|---|
| `AddEvent(time, desc, before, after)` | bool | Register a manual news event |
| `AddEventFromString(dtStr, desc, ...)` | bool | Parse "YYYY.MM.DD HH:MM" and register |
| `IsNewsBlocked()` | bool | True if any block window is active |
| `GetBlockReason()` | string | Which event is causing the block |
| `IsApproachingNews(mins)` | bool | News is within `mins` minutes |

---

## MarketStructure.mqh — `CMarketStructure`

### Init Parameters
| Param | Type | Description |
|---|---|---|
| `symbol` | string | Symbol |
| `tf` | ENUM_TIMEFRAMES | Timeframe to analyse |
| `lookback` | int | Bars to scan for swings (e.g. 100) |
| `swingStrength` | int | Bars each side for pivot (e.g. 3) |

### Key Methods
| Method | Returns | Description |
|---|---|---|
| `Update()` | void | Run all detection (call once per bar) |
| `PruneStaleOBs()` | void | Invalidate breached OBs / filled FVGs |
| `GetLastSignal()` | ENUM_MS_SIGNAL | Most recent BOS/CHOCH/sweep |
| `HasBullishSetup()` | bool | Signal is bullish-biased |
| `HasBearishSetup()` | bool | Signal is bearish-biased |
| `IsPriceInBullishOB(price)` | bool | Price inside a bullish Order Block |
| `IsPriceInBearishOB(price)` | bool | Price inside a bearish Order Block |
| `IsPriceInBullFVG(price)` | bool | Price inside bullish FVG |
| `IsPriceInBearFVG(price)` | bool | Price inside bearish FVG |
| `GetNearestBullishOB(low, high)` | bool | Nearest active bullish OB zone |
| `GetLastSwingHigh/Low()` | double | Most recently detected swing |

### Signal Enum
```
MS_NONE / MS_BOS_BULL / MS_BOS_BEAR / MS_CHOCH_BULL / MS_CHOCH_BEAR
MS_LIQ_SWEEP_H / MS_LIQ_SWEEP_L
```

---

## SignalEngine.mqh — `CSignalEngine`

### Init Parameters
| Param | Type | Description |
|---|---|---|
| `symbol` | string | Symbol |
| `htfTF` | ENUM_TIMEFRAMES | Higher timeframe (e.g. H1) |
| `setupTF` | ENUM_TIMEFRAMES | Setup timeframe (e.g. M15) |
| `emaFast/Slow` | int | EMA periods |
| `rsiPeriod` | int | RSI period |
| `rsiBullMin/Max` | double | RSI bullish zone |
| `rsiBearMin/Max` | double | RSI bearish zone |
| `tradeMode` | ENUM_TRADE_MODE | SAFE / NORMAL / AGGRESSIVE |
| `htfStructure` | CMarketStructure* | HTF structure instance |
| `setupStructure` | CMarketStructure* | Setup structure instance |

### Key Methods
| Method | Returns | Description |
|---|---|---|
| `Evaluate()` | SignalPackage | Full T+U evaluation |
| `SetTradeMode(mode)` | void | Change mode at runtime |

### SignalPackage struct
```cpp
SIGNAL_DIR   direction;   // SIGNAL_BUY / SIGNAL_SELL / SIGNAL_NONE
double       setupScore;  // 0.0–1.0 confluence score
string       reason;      // Human-readable explanation
```

---

## EntryEngine.mqh — `CEntryEngine`

### Init Parameters
| Param | Type | Description |
|---|---|---|
| `entryTF` | ENUM_TIMEFRAMES | Entry timeframe (M5) |
| `rsiPeriod` | int | RSI for momentum check |
| `rsiOverbought/Oversold` | double | RSI extremes |
| `engulfMinRatio` | double | Min body ratio for engulfing (e.g. 1.5) |
| `atrPeriod` | int | ATR period |
| `minBodyAtrRatio` | double | Min body/ATR for strong bar (e.g. 0.3) |
| `slMode` | int | 0=Structure, 1=ATR |
| `slAtrMul` | double | ATR multiplier for SL |
| `tpMode` | int | 0=Fixed RR, 1=Liquidity, 2=Hybrid |
| `rrRatio` | double | Risk:Reward ratio |

### Key Methods
| Method | Returns | Description |
|---|---|---|
| `SetSwings(high, low)` | void | Update swing reference for structure SL |
| `CheckEntry(direction)` | EntryConfirmation | Full E gate evaluation |

### EntryConfirmation struct
```cpp
bool             confirmed;
ENUM_SIGNAL_DIR  direction;
double           entryPrice;
double           stopLoss;
double           takeProfit;
string           reason;
```

---

## RiskManager.mqh — `CRiskManager`

### Init Parameters
| Param | Type | Description |
|---|---|---|
| `riskPct` | double | Risk per trade % (e.g. 1.0) |
| `maxExposurePct` | double | Max total open risk % |
| `maxOpenTrades` | int | Hard cap on concurrent positions |
| `tradeMode` | ENUM_TRADE_MODE | Sets cooldowns |
| `allowHedge` | bool | Allow opposing direction trades |
| `maxTradesPerDay` | int | Daily trade limit (0 = off) |
| `maxTradesPerSession` | int | Per-session limit (0 = off) |

### Key Methods
| Method | Returns | Description |
|---|---|---|
| `IsFrequencyGateOpen(reason)` | bool | Condition F check |
| `IsExposureAllowed(dir, slDist, reason)` | bool | Condition X check |
| `CalculateLotSize(entry, sl)` | double | Risk-based lot calculation |
| `OnTradeOpened()` | void | Record new trade (updates counters) |
| `OnTradeLoss()` | void | Start loss cooldown |
| `SetTradeMode(mode)` | void | Update mode + cooldowns |

---

## TradeManager.mqh — `CTradeManager`

### Key Methods
| Method | Returns | Description |
|---|---|---|
| `OpenTrade(ec, lots, ticket)` | bool | Market order from EntryConfirmation |
| `ModifyPosition(ticket, sl, tp)` | bool | Modify SL/TP |
| `ClosePosition(ticket)` | bool | Full close |
| `ClosePartial(ticket, lots)` | bool | Partial volume close |
| `CloseAllPositions(reason)` | void | Close all EA positions |
| `GetOpenTickets(tickets[])` | int | Array of active EA tickets |

---

## ExitManager.mqh — `CExitManager`

### Init Parameters
| Param | Type | Description |
|---|---|---|
| `useBE` | bool | Enable break-even |
| `beTriggerR` | double | R multiple to trigger BE (e.g. 1.0) |
| `beBufferPoints` | double | Extra points above entry for BE SL |
| `usePartialClose` | bool | Enable partial close |
| `partialCloseR` | double | R multiple trigger for partial |
| `partialClosePct` | double | % of position to close (e.g. 50.0) |
| `useTrailing` | bool | Enable ATR trailing stop |
| `trailingAtrPeriod` | int | ATR period for trail |
| `trailingAtrMul` | double | ATR multiplier for trail distance |

### Key Methods
| Method | Returns | Description |
|---|---|---|
| `Update(entryTF)` | void | Run BE / partial / trail for all open positions |

---

## Dashboard.mqh — `CDashboard`

### Init Parameters
| Param | Type | Description |
|---|---|---|
| `prop` | CPropProtection* | For DD metrics |
| `session` | CSessionFilter* | For session name |
| `news` | CNewsFilter* | For news status |
| `risk` | CRiskManager* | For trade counts |

### Key Methods
| Method | Returns | Description |
|---|---|---|
| `Update()` | void | Redraw all labels (call ≤ once/second) |
| `SetStatus(active, text)` | void | Update EA state display |
| `Destroy()` | void | Remove all chart objects (call in OnDeinit) |

---

## Trade Mode Cooldowns Reference

| Mode | Between-trade cooldown | After-loss cooldown | Min confluence score |
|---|---|---|---|
| SAFE | 3600s (60 min) | 7200s (2 hr) | 0.75 |
| NORMAL | 1800s (30 min) | 3600s (1 hr) | 0.55 |
| AGGRESSIVE | 600s (10 min) | 1800s (30 min) | 0.35 |

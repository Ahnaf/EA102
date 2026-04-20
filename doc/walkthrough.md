# EA102 — XAUUSD Prop Firm Expert Advisor
## Walkthrough & Deployment Guide

---

## File Structure

All files live in:
`…\MQL5\Experts\EA102\`

| File | Role | Size |
|---|---|---|
| `MainEA.mq5` | Master file — OnInit/OnTick/OnTradeTransaction | 23.9 KB |
| `Utilities.mqh` | Logging, math, ATR/EMA/RSI helpers | 9.7 KB |
| `PropProtection.mqh` | Daily DD, max DD, profit lock, emergency close | 10.0 KB |
| `SessionFilter.mqh` | London/NY/Asian session windows | 7.1 KB |
| `NewsFilter.mqh` | Manual events + auto NFP/FOMC blocks | 8.0 KB |
| `MarketStructure.mqh` | BOS/CHOCH/Liquidity sweep/OB/FVG | 17.3 KB |
| `SignalEngine.mqh` | HTF trend (EMA+RSI+structure) + setup scoring | 9.0 KB |
| `EntryEngine.mqh` | M5 candle confirmation + SL/TP calculation | 12.4 KB |
| `RiskManager.mqh` | Lot sizing, exposure gate, frequency gate | 11.1 KB |
| `TradeManager.mqh` | CTrade wrapper — open/modify/close/partial | 8.1 KB |
| `ExitManager.mqh` | Break-even, partial close, ATR trailing | 8.2 KB |
| `Dashboard.mqh` | On-chart info panel via ChartObjects | 7.9 KB |

---

## Decision Gate Architecture

```
AllowTrade = R AND S AND N AND F AND T AND U AND E AND X
```

Evaluated in **strict priority order** every M5 bar:

```
TICK arrives
  │
  ├─ R: PropProtection.Update()
  │    ├─ MaxDD breached? → HARD STOP (close all, disable forever)
  │    ├─ DailyDD breached? → block new trades for rest of day
  │    └─ ProfitLock reached? → block new entries
  │
  ├─ EXIT MANAGER runs every tick (BE / partial / trailing)
  │
  ├─ S: SessionFilter.IsInSession()? → skip if outside hours
  │
  ├─ N: NewsFilter.IsNewsBlocked()? → skip if news window
  │
  ├─ [New M5 bar check — skip signal if same bar]
  │
  ├─ F: RiskManager.IsFrequencyGateOpen()? → cooldown / daily limit
  │
  ├─ T+U: SignalEngine.Evaluate() → HTF trend + M15 setup score
  │
  ├─ E: EntryEngine.CheckEntry() → M5 candle + RSI momentum
  │
  ├─ X: RiskManager.IsExposureAllowed() → hedge/max risk check
  │
  └─ EXECUTE → CalculateLotSize → OpenTrade → OnTradeOpened
```

---

## How to Compile

1. Open **MetaEditor** (press F4 in MetaTrader 5, or launch from the Tools menu).
2. In the Navigator panel, locate:  
   `Experts → EA102 → MainEA.mq5`
3. Double-click `MainEA.mq5` to open it.
4. Press **F7** (or click the Compile button ▶).
5. Check the **Errors** tab at the bottom — it should show **0 errors, 0 warnings**.
6. The compiled `.ex5` file is automatically placed in the same folder.

> **IMPORTANT:** All `.mqh` files must remain in the **same directory** as `MainEA.mq5`.  
> Do not move them into subfolders — the `#include` directives use relative paths.

---

## How to Attach the EA

1. In MetaTrader 5, open a **XAUUSD M5** chart.
2. Open the **Navigator** panel (Ctrl+N).
3. Under **Expert Advisors → EA102**, drag `MainEA` onto the chart.
4. In the settings dialog, configure inputs (see below).
5. Enable **Allow Algo Trading** (the green robot button in the toolbar).
6. Confirm the EA appears in the chart's top-right corner with a green smiley face.

---

## Recommended Default Settings for XAUUSD

### General
| Parameter | Recommended |
|---|---|
| Magic Number | 102000 |
| Symbol | XAUUSD |
| Slippage | 30 points |
| Log Level | INFO |

### Prop Protection (FTMO / FundedNext)
| Parameter | Recommended |
|---|---|
| Max Drawdown % | 10.0 |
| Daily DD % | 5.0 |
| Emergency Close | ON |
| Daily Profit Lock | OFF (enable if challenge phase) |

### Risk
| Parameter | Recommended |
|---|---|
| Risk per trade % | 0.5–1.0% |
| Max total exposure % | 2.0–3.0% |
| Max open trades | 2 |
| Allow hedge | OFF |
| Max trades/day | 3 |

### Signal Timeframes
| Parameter | Recommended |
|---|---|
| HTF (Trend) | H1 |
| Setup | M15 |
| Entry | M5 |

### EMAs
| Parameter | Recommended |
|---|---|
| EMA Fast | 21 |
| EMA Slow | 55 |
| RSI Period | 14 |

### Stop Loss
| Parameter | Recommended |
|---|---|
| SL Mode | 0 (Structure-based) |
| ATR Multiplier (fallback) | 1.5 |

### Take Profit
| Parameter | Recommended |
|---|---|
| TP Mode | 2 (Hybrid) |
| RR Ratio | 2.0 |

### Break-even
| Parameter | Recommended |
|---|---|
| Enable BE | ON |
| BE Trigger | 1.0R |
| BE Buffer | 30 points |

### Partial Close
| Parameter | Recommended |
|---|---|
| Enable Partial | ON |
| Trigger at | 1.2R |
| Close % | 50% |

### Trailing Stop
| Parameter | Recommended |
|---|---|
| Enable Trailing | ON |
| ATR Period | 14 |
| ATR Multiplier | 2.0 |

### Sessions (UTC times — adjust for broker offset)
| Session | Start | End |
|---|---|---|
| London | 07:00 | 16:00 |
| New York | 12:00 | 20:00 |

### News Filter
| Parameter | Recommended |
|---|---|
| Filter ON | YES |
| Block before | 30 mins |
| Block after | 15 mins |
| Auto-block NFP | YES |
| Auto-block FOMC | YES |

---

## Trade Mode Summary

| Mode | Cooldown | Loss Cooldown | Min Score | Confirms required |
|---|---|---|---|---|
| SAFE | 60 min | 2 hours | 75% | All confluences |
| NORMAL | 30 min | 1 hour | 55% | Most confluences |
| AGGRESSIVE | 10 min | 30 min | 35% | Minimal |

> **TIP:** Start with **NORMAL** mode during the prop firm evaluation phase.  
> Switch to **SAFE** if approaching drawdown limits.

---

## Strategy Logic Summary

### T — HTF Trend (H1)
- EMA21 vs EMA55 cross (40% weight)
- Price vs EMA55 (20% weight)
- RSI 14 in bullish/bearish zone (20% weight)
- Market structure BOS/CHOCH (20% weight)

### U — M15 Setup
- BOS / CHOCH / Liquidity Sweep detection (+0.4)
- Price inside Order Block (+0.3)
- Price inside Fair Value Gap (+0.3)

### E — M5 Entry Confirmation
- Bullish/Bearish engulfing candle (body ratio ≥ 1.5)  
  OR Strong single bar (body ≥ 30% ATR)
- RSI aligned (≥50 for buy, ≤50 for sell)
- RSI bounce from oversold/overbought accepted

---

## Backtesting & Optimisation

All major parameters are inputs and compatible with the MT5 Strategy Tester optimizer.

**Recommended optimization sequence:**
1. Fix sessions, news filter, prop parameters
2. Optimize: `InpEMAFast`, `InpEMASlow` (ranges: 10–34, 30–89)
3. Optimize: `InpRSIPeriod`, `InpRSIBullMin/Max`
4. Optimize: `InpSLAtrMul`, `InpRRRatio`
5. Optimize: `InpBETriggerR`, `InpPartialCloseR`

Use **"Open prices only"** mode for speed when doing parameter sweeps;  
switch to **"Every tick"** for final validation.

> **WARNING:** Forward test for at least 30 trading days before live deployment.  
> Backtest results on XAUUSD are sensitive to tick data quality — use broker-provided tick data when available.

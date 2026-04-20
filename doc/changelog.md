# EA102 — Changelog

---

## v1.00 — 2026-04-21

### Initial Release

**Modules created:**
- `MainEA.mq5` — Master EA with full 8-gate decision system
- `Utilities.mqh` — Shared helpers, logging, ATR/EMA/RSI
- `PropProtection.mqh` — FTMO/FundedNext daily & max DD compliance
- `SessionFilter.mqh` — London / NY / Asian session windows
- `NewsFilter.mqh` — Manual events + auto NFP/FOMC blocks
- `MarketStructure.mqh` — BOS / CHOCH / Liquidity Sweep / OB / FVG
- `SignalEngine.mqh` — HTF trend scoring + M15 setup confluence
- `EntryEngine.mqh` — M5 candle confirmation + SL/TP calculation
- `RiskManager.mqh` — Lot sizing, frequency gate, exposure gate
- `TradeManager.mqh` — CTrade wrapper with partial close support
- `ExitManager.mqh` — Break-even, partial close, ATR trailing
- `Dashboard.mqh` — On-chart ChartObjects status panel

**Decision gate priority (strict):**
```
R(MaxDD/DailyDD) → S(Session) → N(News) → F(Frequency) →
T+U(Signal) → E(Entry) → X(Exposure) → EXECUTE
```

**Key features:**
- Risk-based lot sizing with full account balance awareness
- Three trade modes: SAFE / NORMAL / AGGRESSIVE
- Structure-based and ATR-based stop loss modes
- Fixed RR, liquidity target, and hybrid take profit modes
- OnTradeTransaction integration for loss cooldown tracking
- Full backtest optimisation support (all params are inputs)

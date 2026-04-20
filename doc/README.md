# EA102 — XAUUSD Prop Firm Expert Advisor
### Documentation Index

---

## Contents

| File | Description |
|---|---|
| [walkthrough.md](walkthrough.md) | Full deployment guide, settings reference, strategy logic, backtest tips |
| [module_reference.md](module_reference.md) | Per-module API reference: classes, methods, inputs |
| [changelog.md](changelog.md) | Version history and change log |

---

## Quick Start

```
1. Open MetaEditor → Experts/EA102/MainEA.mq5
2. Press F7 to compile (expect 0 errors)
3. Attach to XAUUSD M5 chart
4. Set Risk % = 1.0, Mode = NORMAL
5. Run on demo for 2 weeks minimum
```

---

## Project Structure

```
EA102/
├── MainEA.mq5              ← Entry point (compile this)
├── Utilities.mqh           ← Shared helpers & logging
├── PropProtection.mqh      ← Prop firm DD / profit limits
├── SessionFilter.mqh       ← London / NY / Asian sessions
├── NewsFilter.mqh          ← NFP / FOMC / manual news blocks
├── MarketStructure.mqh     ← BOS / CHOCH / OB / FVG
├── SignalEngine.mqh        ← HTF trend + M15 setup scoring
├── EntryEngine.mqh         ← M5 candle + momentum confirmation
├── RiskManager.mqh         ← Lot sizing + exposure + frequency
├── TradeManager.mqh        ← CTrade open/close/modify/partial
├── ExitManager.mqh         ← BE / partial close / trailing
├── Dashboard.mqh           ← On-chart info panel
└── doc/                    ← ← You are here
    ├── README.md
    ├── walkthrough.md
    ├── module_reference.md
    └── changelog.md
```

---

## Decision Gate (Priority Order)

```
R → S → N → F → T+U → E → X → EXECUTE
```

| Gate | Module | Condition |
|---|---|---|
| R | PropProtection | Max DD / Daily DD / Profit Lock |
| S | SessionFilter | London / NY / Asian windows |
| N | NewsFilter | NFP / FOMC / manual events |
| F | RiskManager | Cooldown / daily trade count |
| T | SignalEngine | HTF trend (EMA + RSI + structure) |
| U | SignalEngine + MarketStructure | M15 BOS/CHOCH + OB/FVG score |
| E | EntryEngine | M5 engulfing/strong-bar + RSI |
| X | RiskManager | Open risk % + hedge + max trades |

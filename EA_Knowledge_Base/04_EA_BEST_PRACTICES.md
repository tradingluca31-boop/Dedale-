# Meilleures Pratiques EA MQL5 - Guide Complet

## ARCHITECTURE EA PROFESSIONNELLE

### Structure de Fichiers Recommandee
```
EA_Project/
├── Include/
│   ├── TradeManager.mqh      // Gestion des ordres
│   ├── RiskManager.mqh       // Risk management
│   ├── SignalEngine.mqh      // Generation signaux
│   ├── PatternDetector.mqh   // Detection patterns
│   ├── PriceAction.mqh       // Analyse price action
│   └── Utils.mqh             // Fonctions utilitaires
├── Experts/
│   └── MyEA.mq5              // EA principal
├── Indicators/
│   └── CustomIndicator.mq5   // Indicateurs custom
└── Scripts/
    └── Backtester.mq5        // Scripts de test
```

### Template EA de Base
```cpp
//+------------------------------------------------------------------+
//|                                                      MyEA.mq5     |
//|                                            Professional Template  |
//+------------------------------------------------------------------+
#property copyright "Luca"
#property version   "1.00"
#property strict

//--- Includes
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>

//--- Input Parameters
input group "=== TRADING SETTINGS ==="
input double   RiskPercent     = 1.0;      // Risk per trade (%)
input double   RiskRewardRatio = 2.0;      // Risk/Reward Ratio
input int      MaxDailyTrades  = 3;        // Max trades per day
input int      MaxOpenTrades   = 1;        // Max concurrent trades

input group "=== STRATEGY SETTINGS ==="
input int      SignalPeriod    = 14;       // Signal period
input double   MinConfluence   = 5.0;      // Min confluence score

input group "=== TIME FILTER ==="
input bool     UseTimeFilter   = true;     // Use time filter
input int      StartHour       = 7;        // Start hour (GMT)
input int      EndHour         = 20;       // End hour (GMT)

input group "=== FTMO SETTINGS ==="
input double   MaxDailyDD      = 5.0;      // Max daily drawdown (%)
input double   MaxTotalDD      = 10.0;     // Max total drawdown (%)
input double   DailyTarget     = 1.0;      // Daily profit target (%)

//--- Global Objects
CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symbolInfo;

//--- Global Variables
double         startingBalance;
double         dailyStartBalance;
int            dailyTradesCount;
datetime       lastTradeDate;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit() {
    // Initialize symbol info
    if(!symbolInfo.Name(_Symbol)) {
        Print("Error initializing symbol info");
        return INIT_FAILED;
    }

    // Set trade parameters
    trade.SetExpertMagicNumber(123456);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    // Initialize tracking variables
    startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    dailyStartBalance = startingBalance;
    dailyTradesCount = 0;
    lastTradeDate = 0;

    Print("EA initialized successfully. Balance: ", startingBalance);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick() {
    // 1. Update daily tracking
    UpdateDailyTracking();

    // 2. Check FTMO rules
    if(!CheckFTMORules()) return;

    // 3. Check if new bar
    if(!IsNewBar()) return;

    // 4. Check time filter
    if(UseTimeFilter && !IsWithinTradingHours()) return;

    // 5. Check max trades
    if(dailyTradesCount >= MaxDailyTrades) return;
    if(CountOpenPositions() >= MaxOpenTrades) return;

    // 6. Generate signal
    int signal = GenerateSignal();

    // 7. Execute trade
    if(signal != 0) {
        ExecuteTrade(signal);
    }

    // 8. Manage open positions
    ManagePositions();
}
```

---

## RISK MANAGEMENT FTMO

### Calcul de Lot Size
```cpp
double CalculateLotSize(double stopLossPoints) {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * (RiskPercent / 100.0);

    // Get symbol info
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double pointValue = tickValue / tickSize * _Point;

    // Calculate lot size
    double lotSize = riskAmount / (stopLossPoints * pointValue);

    // Normalize lot size
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    lotSize = MathMax(minLot, lotSize);
    lotSize = MathMin(maxLot, lotSize);
    lotSize = NormalizeDouble(MathFloor(lotSize / lotStep) * lotStep, 2);

    return lotSize;
}
```

### Verification Regles FTMO
```cpp
bool CheckFTMORules() {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);

    // 1. Check Max Daily Drawdown (5%)
    double dailyLoss = dailyStartBalance - equity;
    double dailyDDPercent = (dailyLoss / dailyStartBalance) * 100;

    if(dailyDDPercent >= MaxDailyDD) {
        Print("FTMO ALERT: Daily DD limit reached: ", dailyDDPercent, "%");
        return false;
    }

    // 2. Check Max Total Drawdown (10%)
    double totalLoss = startingBalance - equity;
    double totalDDPercent = (totalLoss / startingBalance) * 100;

    if(totalDDPercent >= MaxTotalDD) {
        Print("FTMO ALERT: Total DD limit reached: ", totalDDPercent, "%");
        return false;
    }

    // 3. Check if daily target reached (optional - stop trading)
    double dailyProfit = equity - dailyStartBalance;
    double dailyProfitPercent = (dailyProfit / dailyStartBalance) * 100;

    if(dailyProfitPercent >= DailyTarget) {
        Print("Daily target reached: ", dailyProfitPercent, "%. Stopping for today.");
        return false;
    }

    return true;
}

void UpdateDailyTracking() {
    MqlDateTime currentTime;
    TimeToStruct(TimeCurrent(), currentTime);

    MqlDateTime lastTime;
    TimeToStruct(lastTradeDate, lastTime);

    // New day - reset counters
    if(currentTime.day != lastTime.day) {
        dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        dailyTradesCount = 0;
        lastTradeDate = TimeCurrent();
        Print("New day started. Daily balance reset to: ", dailyStartBalance);
    }
}
```

### Trailing Stop Intelligent
```cpp
void ManageTrailingStop(ulong ticket) {
    if(!PositionSelectByTicket(ticket)) return;

    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentSL = PositionGetDouble(POSITION_SL);
    double currentTP = PositionGetDouble(POSITION_TP);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

    double atr = iATR(_Symbol, PERIOD_CURRENT, 14);
    double currentPrice = (type == POSITION_TYPE_BUY) ?
                          SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                          SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    double risk = MathAbs(openPrice - currentSL);

    if(type == POSITION_TYPE_BUY) {
        // Move to break-even at 1R profit
        if(currentPrice >= openPrice + risk && currentSL < openPrice) {
            double newSL = openPrice + _Point * 10;  // Small buffer
            trade.PositionModify(ticket, newSL, currentTP);
            Print("Moved to break-even: ", newSL);
        }
        // Trail at 1.5 ATR after 2R
        else if(currentPrice >= openPrice + (risk * 2)) {
            double newSL = currentPrice - (atr * 1.5);
            if(newSL > currentSL) {
                trade.PositionModify(ticket, newSL, currentTP);
            }
        }
    }
    else {  // SELL
        if(currentPrice <= openPrice - risk && currentSL > openPrice) {
            double newSL = openPrice - _Point * 10;
            trade.PositionModify(ticket, newSL, currentTP);
        }
        else if(currentPrice <= openPrice - (risk * 2)) {
            double newSL = currentPrice + (atr * 1.5);
            if(newSL < currentSL) {
                trade.PositionModify(ticket, newSL, currentTP);
            }
        }
    }
}
```

---

## OPTIMISATIONS AVANCEES

### 1. Filtrage par Volatilite
```cpp
bool IsVolatilitySuitable() {
    double atr = iATR(_Symbol, PERIOD_CURRENT, 14);
    double atrPercent = (atr / iClose(_Symbol, PERIOD_CURRENT, 0)) * 100;

    // Gold typique: 0.5% - 2% ATR
    // Eviter faible volatilite (ranging) et extreme (news)
    return (atrPercent >= 0.3 && atrPercent <= 3.0);
}
```

### 2. Filtre de Tendance
```cpp
int GetTrendDirection() {
    double ema20 = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
    double ema50 = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
    double ema200 = iMA(_Symbol, PERIOD_CURRENT, 200, 0, MODE_EMA, PRICE_CLOSE);

    double close = iClose(_Symbol, PERIOD_CURRENT, 0);

    // Strong uptrend
    if(close > ema20 && ema20 > ema50 && ema50 > ema200) return 1;

    // Strong downtrend
    if(close < ema20 && ema20 < ema50 && ema50 < ema200) return -1;

    // No clear trend
    return 0;
}
```

### 3. Spread Filter
```cpp
bool IsSpreadAcceptable(double maxSpreadPoints = 50) {
    double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    return spread <= maxSpreadPoints;
}
```

### 4. New Bar Detection
```cpp
bool IsNewBar() {
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);

    if(currentBarTime != lastBarTime) {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}
```

---

## LOGGING ET DEBUGGING

### Systeme de Log
```cpp
enum LOG_LEVEL { LOG_DEBUG, LOG_INFO, LOG_WARNING, LOG_ERROR };

input LOG_LEVEL LogLevel = LOG_INFO;

void Log(LOG_LEVEL level, string message) {
    if(level < LogLevel) return;

    string prefix;
    switch(level) {
        case LOG_DEBUG:   prefix = "[DEBUG] "; break;
        case LOG_INFO:    prefix = "[INFO] "; break;
        case LOG_WARNING: prefix = "[WARN] "; break;
        case LOG_ERROR:   prefix = "[ERROR] "; break;
    }

    Print(prefix, message);

    // Optionnel: ecrire dans fichier
    if(level >= LOG_WARNING) {
        WriteToLogFile(prefix + message);
    }
}

void WriteToLogFile(string message) {
    int handle = FileOpen("EA_Log.txt", FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI);
    if(handle != INVALID_HANDLE) {
        FileSeek(handle, 0, SEEK_END);
        FileWriteString(handle, TimeToString(TimeCurrent()) + " " + message + "\n");
        FileClose(handle);
    }
}
```

### Trade Journal Automatique
```cpp
void LogTrade(ulong ticket, string action) {
    if(!PositionSelectByTicket(ticket)) return;

    string info = StringFormat(
        "%s | Ticket: %d | Symbol: %s | Type: %s | Lots: %.2f | Entry: %.5f | SL: %.5f | TP: %.5f",
        action,
        ticket,
        PositionGetString(POSITION_SYMBOL),
        PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL",
        PositionGetDouble(POSITION_VOLUME),
        PositionGetDouble(POSITION_PRICE_OPEN),
        PositionGetDouble(POSITION_SL),
        PositionGetDouble(POSITION_TP)
    );

    Log(LOG_INFO, info);
}
```

---

## CONSEILS CRITIQUES

### DO's
1. **Toujours utiliser un Magic Number unique** pour identifier les trades de l'EA
2. **Valider tous les inputs** au demarrage (OnInit)
3. **Gerer les erreurs** de toutes les operations de trading
4. **Utiliser des stops garantis** - jamais trader sans SL
5. **Tester extensivement** sur compte demo avant live
6. **Limiter le slippage** avec SetDeviationInPoints()
7. **Logger les decisions** pour analyse post-trade

### DON'Ts
1. **Ne jamais utiliser martingale ou grid sans limites**
2. **Ne pas over-optimiser** sur backtest (curve fitting)
3. **Ne pas ignorer le spread** - impact majeur sur GOLD
4. **Ne pas trader pendant les news majeures** sans protection
5. **Ne pas risquer plus de 1-2%** par trade (FTMO friendly)
6. **Ne pas modifier manuellement** les trades de l'EA en live
7. **Ne pas utiliser des timeframes trop bas** (< M5) sans raison

### FTMO Specific
1. Max daily loss: **4.5%** (safety buffer sous 5%)
2. Max total loss: **9%** (safety buffer sous 10%)
3. Profit target Phase 1: **10%** en 30 jours
4. Minimum trading days: **4 jours**
5. Pas de trading pendant weekends
6. Eviter overleveraging - garder margin libre > 80%

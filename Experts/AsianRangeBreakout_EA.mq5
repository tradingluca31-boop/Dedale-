//+------------------------------------------------------------------+
//|                                      AsianRangeBreakout_EA.mq5   |
//|                                                             Luca |
//|                                    Asian Range + Daily Trend EA  |
//+------------------------------------------------------------------+
#property copyright "Luca"
#property version   "1.00"
#property description "Trade le breakout du range Asiatique dans le sens de la tendance journaliere"
#property strict

//--- Includes
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

input group "=== SESSION SETTINGS ==="
input int      AsiaStartHour   = 0;       // Debut session Asie (GMT)
input int      AsiaEndHour     = 7;       // Fin session Asie / Debut Londres (GMT)
input int      TradeEndHour    = 18;      // Fin de trading (GMT)
input int      GMTOffset       = 0;       // Offset GMT du broker

input group "=== TREND FILTER ==="
input ENUM_TIMEFRAMES TrendTimeframe = PERIOD_D1;  // Timeframe pour tendance
input int      EMA_Fast        = 21;      // EMA rapide
input int      EMA_Slow        = 50;      // EMA lente
input int      EMA_Filter      = 200;     // EMA filtre tendance
input bool     UseStructure    = true;    // Utiliser structure HH/HL

input group "=== BREAKOUT SETTINGS ==="
input int      MinRangePips    = 150;     // Range minimum (pips) pour trader
input int      MaxRangePips    = 500;     // Range maximum (pips)
input int      BreakoutBuffer  = 20;      // Buffer au-dessus/dessous du range (pips)
input bool     WaitForClose    = true;    // Attendre cloture bougie pour confirmer

input group "=== RISK MANAGEMENT ==="
input double   RiskPercent     = 1.0;     // Risque par trade (%)
input double   RiskReward      = 2.0;     // Ratio Risk/Reward minimum
input bool     UsePartialTP    = true;    // Utiliser TP partiel
input double   PartialTPPercent= 50.0;    // % a fermer au TP1

input group "=== FTMO PROTECTION ==="
input double   MaxDailyLoss    = 4.5;     // Max perte journaliere (%)
input double   MaxTotalLoss    = 9.0;     // Max perte totale (%)
input int      MaxDailyTrades  = 2;       // Max trades par jour

input group "=== EA SETTINGS ==="
input ulong    MagicNumber     = 123456;  // Magic Number
input string   TradeComment    = "ARB";   // Commentaire trade

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symbolInfo;

// Session tracking
double         g_AsiaHigh = 0;
double         g_AsiaLow = DBL_MAX;
datetime       g_AsiaRangeDate = 0;
bool           g_RangeIdentified = false;
bool           g_TradedToday = false;

// Daily tracking
double         g_StartingBalance = 0;
double         g_DailyStartBalance = 0;
int            g_DailyTradesCount = 0;
datetime       g_LastTradeDate = 0;

// Trend
int            g_TrendDirection = 0;  // 1=bullish, -1=bearish, 0=neutral

// Indicator handles
int            h_EMA_Fast, h_EMA_Slow, h_EMA_Filter;
int            h_ATR;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit() {
    //--- Initialize symbol
    if(!symbolInfo.Name(_Symbol)) {
        Print("Erreur initialisation symbole");
        return INIT_FAILED;
    }

    //--- Setup trade
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(20);
    trade.SetTypeFilling(ORDER_FILLING_IOC);
    trade.SetAsyncMode(false);

    //--- Create indicator handles
    h_EMA_Fast = iMA(_Symbol, TrendTimeframe, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    h_EMA_Slow = iMA(_Symbol, TrendTimeframe, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
    h_EMA_Filter = iMA(_Symbol, TrendTimeframe, EMA_Filter, 0, MODE_EMA, PRICE_CLOSE);
    h_ATR = iATR(_Symbol, PERIOD_H1, 14);

    if(h_EMA_Fast == INVALID_HANDLE || h_EMA_Slow == INVALID_HANDLE ||
       h_EMA_Filter == INVALID_HANDLE || h_ATR == INVALID_HANDLE) {
        Print("Erreur creation indicateurs");
        return INIT_FAILED;
    }

    //--- Initialize balances
    g_StartingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    g_DailyStartBalance = g_StartingBalance;

    Print("=== Asian Range Breakout EA Initialized ===");
    Print("Symbol: ", _Symbol);
    Print("Trend TF: ", EnumToString(TrendTimeframe));
    Print("Risk: ", RiskPercent, "%");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    IndicatorRelease(h_EMA_Fast);
    IndicatorRelease(h_EMA_Slow);
    IndicatorRelease(h_EMA_Filter);
    IndicatorRelease(h_ATR);
    Print("EA Deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick() {
    //--- Update daily tracking
    UpdateDailyTracking();

    //--- Check FTMO rules
    if(!CheckFTMORules()) return;

    //--- Get current time
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int currentHour = (dt.hour + GMTOffset) % 24;

    //--- PHASE 1: During Asian Session - Build the range
    if(currentHour >= AsiaStartHour && currentHour < AsiaEndHour) {
        BuildAsianRange();
    }

    //--- PHASE 2: After Asian Session - Check for breakout
    if(currentHour >= AsiaEndHour && currentHour < TradeEndHour) {

        //--- Identify trend once per day
        if(!g_RangeIdentified && IsRangeValid()) {
            g_TrendDirection = GetDailyTrend();
            g_RangeIdentified = true;

            Print("=== Range Asie Identifie ===");
            Print("High: ", g_AsiaHigh, " | Low: ", g_AsiaLow);
            Print("Range: ", (g_AsiaHigh - g_AsiaLow) / _Point, " pips");
            Print("Tendance D1: ", g_TrendDirection == 1 ? "BULLISH" :
                                  g_TrendDirection == -1 ? "BEARISH" : "NEUTRAL");
        }

        //--- Check for breakout if not already traded
        if(g_RangeIdentified && !g_TradedToday && g_TrendDirection != 0) {
            CheckBreakout();
        }
    }

    //--- Manage open positions
    ManagePositions();

    //--- Reset at end of day
    if(currentHour >= TradeEndHour || currentHour < AsiaStartHour) {
        ResetDaily();
    }
}

//+------------------------------------------------------------------+
//| Build Asian Session Range                                         |
//+------------------------------------------------------------------+
void BuildAsianRange() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

    //--- New day - reset range
    if(today != g_AsiaRangeDate) {
        g_AsiaHigh = 0;
        g_AsiaLow = DBL_MAX;
        g_AsiaRangeDate = today;
        g_RangeIdentified = false;
        g_TradedToday = false;
    }

    //--- Update high/low
    double high = iHigh(_Symbol, PERIOD_M15, 0);
    double low = iLow(_Symbol, PERIOD_M15, 0);

    if(high > g_AsiaHigh) g_AsiaHigh = high;
    if(low < g_AsiaLow) g_AsiaLow = low;
}

//+------------------------------------------------------------------+
//| Validate Asian Range                                              |
//+------------------------------------------------------------------+
bool IsRangeValid() {
    if(g_AsiaHigh == 0 || g_AsiaLow == DBL_MAX) return false;

    double rangePips = (g_AsiaHigh - g_AsiaLow) / _Point;

    if(rangePips < MinRangePips) {
        Print("Range trop petit: ", rangePips, " pips (min: ", MinRangePips, ")");
        return false;
    }

    if(rangePips > MaxRangePips) {
        Print("Range trop grand: ", rangePips, " pips (max: ", MaxRangePips, ")");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Get Daily Trend Direction                                         |
//+------------------------------------------------------------------+
int GetDailyTrend() {
    double emaFast[], emaSlow[], emaFilter[];
    ArraySetAsSeries(emaFast, true);
    ArraySetAsSeries(emaSlow, true);
    ArraySetAsSeries(emaFilter, true);

    CopyBuffer(h_EMA_Fast, 0, 0, 3, emaFast);
    CopyBuffer(h_EMA_Slow, 0, 0, 3, emaSlow);
    CopyBuffer(h_EMA_Filter, 0, 0, 3, emaFilter);

    double close = iClose(_Symbol, TrendTimeframe, 1);

    //--- Method 1: EMA alignment
    bool emaBullish = (emaFast[0] > emaSlow[0]) && (emaSlow[0] > emaFilter[0]) && (close > emaFast[0]);
    bool emaBearish = (emaFast[0] < emaSlow[0]) && (emaSlow[0] < emaFilter[0]) && (close < emaFast[0]);

    //--- Method 2: Price structure (optional)
    int structureTrend = 0;
    if(UseStructure) {
        structureTrend = GetStructureTrend();
    }

    //--- Combine signals
    if(emaBullish && (!UseStructure || structureTrend >= 0)) return 1;   // BULLISH
    if(emaBearish && (!UseStructure || structureTrend <= 0)) return -1;  // BEARISH

    return 0;  // NEUTRAL - no trade
}

//+------------------------------------------------------------------+
//| Get Market Structure Trend                                        |
//+------------------------------------------------------------------+
int GetStructureTrend() {
    double highs[], lows[];
    int highCount = 0, lowCount = 0;
    double lastHH = 0, lastHL = 0, lastLH = 0, lastLL = 0;

    //--- Find last 4 swing points on H4
    for(int i = 5; i < 100 && (highCount < 2 || lowCount < 2); i++) {
        if(IsSwingHigh(i, PERIOD_H4)) {
            if(highCount == 0) lastHH = iHigh(_Symbol, PERIOD_H4, i);
            else lastLH = iHigh(_Symbol, PERIOD_H4, i);
            highCount++;
        }
        if(IsSwingLow(i, PERIOD_H4)) {
            if(lowCount == 0) lastHL = iLow(_Symbol, PERIOD_H4, i);
            else lastLL = iLow(_Symbol, PERIOD_H4, i);
            lowCount++;
        }
    }

    //--- Higher Highs & Higher Lows = Bullish
    if(lastHH > lastLH && lastHL > lastLL) return 1;

    //--- Lower Highs & Lower Lows = Bearish
    if(lastHH < lastLH && lastHL < lastLL) return -1;

    return 0;
}

//+------------------------------------------------------------------+
//| Check for Swing High                                              |
//+------------------------------------------------------------------+
bool IsSwingHigh(int shift, ENUM_TIMEFRAMES tf, int lookback = 3) {
    double high = iHigh(_Symbol, tf, shift);
    for(int i = 1; i <= lookback; i++) {
        if(iHigh(_Symbol, tf, shift - i) >= high) return false;
        if(iHigh(_Symbol, tf, shift + i) >= high) return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Check for Swing Low                                               |
//+------------------------------------------------------------------+
bool IsSwingLow(int shift, ENUM_TIMEFRAMES tf, int lookback = 3) {
    double low = iLow(_Symbol, tf, shift);
    for(int i = 1; i <= lookback; i++) {
        if(iLow(_Symbol, tf, shift - i) <= low) return false;
        if(iLow(_Symbol, tf, shift + i) <= low) return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Check for Breakout                                                |
//+------------------------------------------------------------------+
void CheckBreakout() {
    double bufferPoints = BreakoutBuffer * _Point;
    double breakoutHighLevel = g_AsiaHigh + bufferPoints;
    double breakoutLowLevel = g_AsiaLow - bufferPoints;

    double close = iClose(_Symbol, PERIOD_M15, 1);
    double open = iOpen(_Symbol, PERIOD_M15, 1);
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    //--- BULLISH BREAKOUT (only if trend is bullish)
    if(g_TrendDirection == 1) {
        bool breakoutConfirmed = WaitForClose ?
                                 (close > breakoutHighLevel && open < breakoutHighLevel) :
                                 (currentPrice > breakoutHighLevel);

        if(breakoutConfirmed) {
            Print(">>> BULLISH BREAKOUT DETECTED <<<");
            ExecuteBreakoutTrade(ORDER_TYPE_BUY);
        }
    }

    //--- BEARISH BREAKOUT (only if trend is bearish)
    if(g_TrendDirection == -1) {
        bool breakoutConfirmed = WaitForClose ?
                                 (close < breakoutLowLevel && open > breakoutLowLevel) :
                                 (currentPrice < breakoutLowLevel);

        if(breakoutConfirmed) {
            Print(">>> BEARISH BREAKOUT DETECTED <<<");
            ExecuteBreakoutTrade(ORDER_TYPE_SELL);
        }
    }
}

//+------------------------------------------------------------------+
//| Execute Breakout Trade                                            |
//+------------------------------------------------------------------+
void ExecuteBreakoutTrade(ENUM_ORDER_TYPE orderType) {
    //--- Check if already have position
    if(CountOpenPositions() > 0) {
        Print("Position deja ouverte - skip");
        return;
    }

    //--- Check daily trades limit
    if(g_DailyTradesCount >= MaxDailyTrades) {
        Print("Max trades journaliers atteint");
        return;
    }

    //--- Check spread
    double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
    double atr[];
    ArraySetAsSeries(atr, true);
    CopyBuffer(h_ATR, 0, 0, 1, atr);

    if(spread > atr[0] * 0.1) {  // Spread > 10% ATR
        Print("Spread trop eleve: ", spread / _Point, " pips");
        return;
    }

    //--- Calculate SL and TP
    double entryPrice, sl, tp;
    double rangeSize = g_AsiaHigh - g_AsiaLow;

    if(orderType == ORDER_TYPE_BUY) {
        entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        sl = g_AsiaLow - (BreakoutBuffer * _Point);  // SL sous le range
        tp = entryPrice + (rangeSize * RiskReward);   // TP = Range * R:R
    }
    else {
        entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        sl = g_AsiaHigh + (BreakoutBuffer * _Point);  // SL au-dessus du range
        tp = entryPrice - (rangeSize * RiskReward);
    }

    //--- Calculate lot size
    double slPoints = MathAbs(entryPrice - sl);
    double lotSize = CalculateLotSize(slPoints);

    if(lotSize == 0) {
        Print("Lot size calcule = 0");
        return;
    }

    //--- Execute trade
    string comment = StringFormat("%s_%s_%s", TradeComment,
                                  orderType == ORDER_TYPE_BUY ? "BUY" : "SELL",
                                  TimeToString(TimeCurrent(), TIME_DATE));

    bool success = false;
    if(orderType == ORDER_TYPE_BUY) {
        success = trade.Buy(lotSize, _Symbol, 0, sl, tp, comment);
    }
    else {
        success = trade.Sell(lotSize, _Symbol, 0, sl, tp, comment);
    }

    if(success) {
        g_TradedToday = true;
        g_DailyTradesCount++;

        Print("=== TRADE EXECUTED ===");
        Print("Type: ", orderType == ORDER_TYPE_BUY ? "BUY" : "SELL");
        Print("Entry: ", entryPrice);
        Print("SL: ", sl, " (", MathAbs(entryPrice - sl) / _Point, " pips)");
        Print("TP: ", tp, " (", MathAbs(tp - entryPrice) / _Point, " pips)");
        Print("Lots: ", lotSize);
        Print("Risk: ", RiskPercent, "%");
    }
    else {
        Print("Erreur execution: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Risk                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPoints) {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * (RiskPercent / 100.0);

    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double pointValue = tickValue / tickSize * _Point;

    double lotSize = riskAmount / (slPoints / _Point * pointValue);

    //--- Normalize
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    lotSize = MathMax(minLot, lotSize);
    lotSize = MathMin(maxLot, lotSize);
    lotSize = NormalizeDouble(MathFloor(lotSize / lotStep) * lotStep, 2);

    return lotSize;
}

//+------------------------------------------------------------------+
//| Manage Open Positions                                             |
//+------------------------------------------------------------------+
void ManagePositions() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!posInfo.SelectByIndex(i)) continue;
        if(posInfo.Magic() != MagicNumber) continue;
        if(posInfo.Symbol() != _Symbol) continue;

        //--- Partial Take Profit
        if(UsePartialTP) {
            ManagePartialTP(posInfo.Ticket());
        }

        //--- Move to Break Even after 1R
        MoveToBreakEven(posInfo.Ticket());
    }
}

//+------------------------------------------------------------------+
//| Manage Partial Take Profit                                        |
//+------------------------------------------------------------------+
void ManagePartialTP(ulong ticket) {
    if(!PositionSelectByTicket(ticket)) return;

    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double sl = PositionGetDouble(POSITION_SL);
    double tp = PositionGetDouble(POSITION_TP);
    double volume = PositionGetDouble(POSITION_VOLUME);

    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

    double risk = MathAbs(openPrice - sl);
    double profit = (type == POSITION_TYPE_BUY) ?
                    currentPrice - openPrice : openPrice - currentPrice;

    //--- Check if at 1R profit and volume allows partial close
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    if(profit >= risk && volume >= minLot * 2) {
        double closeVolume = NormalizeDouble(volume * (PartialTPPercent / 100.0), 2);
        closeVolume = MathMax(closeVolume, minLot);

        if(trade.PositionClosePartial(ticket, closeVolume)) {
            Print("Partial TP executed: ", closeVolume, " lots at 1R");
        }
    }
}

//+------------------------------------------------------------------+
//| Move Stop Loss to Break Even                                      |
//+------------------------------------------------------------------+
void MoveToBreakEven(ulong ticket) {
    if(!PositionSelectByTicket(ticket)) return;

    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double currentSL = PositionGetDouble(POSITION_SL);
    double tp = PositionGetDouble(POSITION_TP);

    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

    double risk = MathAbs(openPrice - currentSL);
    double profit = (type == POSITION_TYPE_BUY) ?
                    currentPrice - openPrice : openPrice - currentPrice;

    //--- Move to BE after 1R profit
    if(profit >= risk) {
        double newSL = openPrice + ((type == POSITION_TYPE_BUY) ? 10 * _Point : -10 * _Point);

        bool shouldMove = (type == POSITION_TYPE_BUY && newSL > currentSL) ||
                          (type == POSITION_TYPE_SELL && newSL < currentSL);

        if(shouldMove) {
            if(trade.PositionModify(ticket, newSL, tp)) {
                Print("Moved to Break Even: ", newSL);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Count Open Positions                                              |
//+------------------------------------------------------------------+
int CountOpenPositions() {
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!posInfo.SelectByIndex(i)) continue;
        if(posInfo.Magic() == MagicNumber && posInfo.Symbol() == _Symbol) {
            count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Update Daily Tracking                                             |
//+------------------------------------------------------------------+
void UpdateDailyTracking() {
    MqlDateTime currentTime, lastTime;
    TimeToStruct(TimeCurrent(), currentTime);
    TimeToStruct(g_LastTradeDate, lastTime);

    if(currentTime.day != lastTime.day) {
        g_DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        g_DailyTradesCount = 0;
        g_LastTradeDate = TimeCurrent();
        Print("New day - Daily balance reset: ", g_DailyStartBalance);
    }
}

//+------------------------------------------------------------------+
//| Check FTMO Rules                                                  |
//+------------------------------------------------------------------+
bool CheckFTMORules() {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);

    //--- Daily Drawdown Check
    double dailyLoss = g_DailyStartBalance - equity;
    double dailyDDPercent = (dailyLoss / g_DailyStartBalance) * 100;

    if(dailyDDPercent >= MaxDailyLoss) {
        Print("!!! FTMO DAILY DD LIMIT: ", dailyDDPercent, "% !!!");
        return false;
    }

    //--- Total Drawdown Check
    double totalLoss = g_StartingBalance - equity;
    double totalDDPercent = (totalLoss / g_StartingBalance) * 100;

    if(totalDDPercent >= MaxTotalLoss) {
        Print("!!! FTMO TOTAL DD LIMIT: ", totalDDPercent, "% !!!");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Reset Daily Variables                                             |
//+------------------------------------------------------------------+
void ResetDaily() {
    //--- Only reset once
    static datetime lastReset = 0;
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

    if(today != lastReset) {
        g_AsiaHigh = 0;
        g_AsiaLow = DBL_MAX;
        g_RangeIdentified = false;
        g_TradedToday = false;
        g_TrendDirection = 0;
        lastReset = today;
    }
}

//+------------------------------------------------------------------+

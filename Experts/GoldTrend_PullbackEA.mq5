//+------------------------------------------------------------------+
//|                                         GoldTrend_PullbackEA.mq5  |
//|                                                             Luca  |
//|        EA adapte pour GOLD en forte tendance (nouveaux highs)     |
//+------------------------------------------------------------------+
#property copyright "Luca"
#property version   "1.00"
#property description "Trade les micro-pullbacks dans une tendance forte"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "=== TREND DETECTION ==="
input ENUM_TIMEFRAMES TF_Trend     = PERIOD_H1;    // TF pour tendance
input ENUM_TIMEFRAMES TF_Entry     = PERIOD_M15;   // TF pour entry
input int      EMA_Fast            = 8;            // EMA rapide
input int      EMA_Slow            = 21;           // EMA lente
input int      EMA_Trend           = 50;           // EMA tendance

input group "=== PULLBACK SETTINGS ==="
input int      MinPullbackPips     = 30;           // Pullback minimum (pips)
input int      MaxPullbackPips     = 100;          // Pullback maximum (pips)
input double   FibOTE_Low          = 0.5;          // Fib OTE bas (50%)
input double   FibOTE_High         = 0.786;        // Fib OTE haut (78.6%)

input group "=== ENTRY CONFIRMATION ==="
input bool     WaitForBullishCandle = true;        // Attendre bougie haussiere
input bool     CheckEMABounce       = true;        // Verifier rebond sur EMA

input group "=== RISK MANAGEMENT ==="
input double   RiskPercent         = 1.0;          // Risque par trade (%)
input double   RiskReward          = 2.0;          // Risk/Reward minimum
input int      SL_BufferPips       = 15;           // Buffer SL (pips)
input int      MaxSL_Pips          = 80;           // SL maximum (pips)
input int      MinSL_Pips          = 30;           // SL minimum (pips)

input group "=== POSITION MANAGEMENT ==="
input bool     UsePartialTP        = true;         // TP partiel a 1R
input double   PartialPercent      = 50.0;         // % a fermer a 1R
input bool     MoveToBreakeven     = true;         // BE apres 1R

input group "=== FTMO ==="
input double   MaxDailyLoss        = 4.5;          // Max DD journalier (%)
input double   MaxTotalLoss        = 9.0;          // Max DD total (%)
input int      MaxDailyTrades      = 3;            // Max trades/jour

input group "=== EA SETTINGS ==="
input ulong    MagicNumber         = 789012;       // Magic Number
input string   Comment_Trade       = "GOLD_PB";    // Commentaire

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  posInfo;

// Indicators
int h_EMA_Fast, h_EMA_Slow, h_EMA_Trend;
int h_ATR;

// Tracking
double g_StartBalance, g_DailyBalance;
int    g_DailyTrades;
datetime g_LastTradeDay;

// Swing tracking
double g_LastSwingHigh, g_LastSwingLow;
datetime g_SwingHighTime, g_SwingLowTime;

// Pullback state
bool   g_InPullback;
double g_PullbackHigh;  // Le high avant le pullback
double g_PullbackLow;   // Le low du pullback actuel

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit() {
    // Trade setup
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(15);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    // Indicators on entry TF (M15)
    h_EMA_Fast = iMA(_Symbol, TF_Entry, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    h_EMA_Slow = iMA(_Symbol, TF_Entry, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
    h_EMA_Trend = iMA(_Symbol, TF_Entry, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
    h_ATR = iATR(_Symbol, TF_Entry, 14);

    if(h_EMA_Fast == INVALID_HANDLE || h_EMA_Slow == INVALID_HANDLE ||
       h_EMA_Trend == INVALID_HANDLE || h_ATR == INVALID_HANDLE) {
        Print("Erreur creation indicateurs");
        return INIT_FAILED;
    }

    // Initialize tracking
    g_StartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    g_DailyBalance = g_StartBalance;
    g_DailyTrades = 0;
    g_InPullback = false;

    Print("=== Gold Trend Pullback EA Started ===");
    Print("Looking for pullbacks in strong trend");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    IndicatorRelease(h_EMA_Fast);
    IndicatorRelease(h_EMA_Slow);
    IndicatorRelease(h_EMA_Trend);
    IndicatorRelease(h_ATR);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick() {
    // Daily reset
    CheckDailyReset();

    // FTMO check
    if(!CheckFTMO()) return;

    // Max trades check
    if(g_DailyTrades >= MaxDailyTrades) return;
    if(CountPositions() > 0) {
        ManageOpenPositions();
        return;
    }

    // Only on new bar (M15)
    if(!IsNewBar(TF_Entry)) return;

    // 1. Check if strong uptrend
    int trend = GetTrendDirection();

    if(trend == 1) {  // BULLISH
        // 2. Detect and trade pullbacks
        TradeBullishPullback();
    }
    else if(trend == -1) {  // BEARISH (rare pour GOLD actuellement)
        TradeBearishPullback();
    }
}

//+------------------------------------------------------------------+
//| GET TREND DIRECTION                                               |
//| Detecte tendance forte (EMA alignees + prix au-dessus)           |
//+------------------------------------------------------------------+
int GetTrendDirection() {
    double emaFast[], emaSlow[], emaTrend[];
    ArraySetAsSeries(emaFast, true);
    ArraySetAsSeries(emaSlow, true);
    ArraySetAsSeries(emaTrend, true);

    CopyBuffer(h_EMA_Fast, 0, 0, 3, emaFast);
    CopyBuffer(h_EMA_Slow, 0, 0, 3, emaSlow);
    CopyBuffer(h_EMA_Trend, 0, 0, 3, emaTrend);

    double close = iClose(_Symbol, TF_Entry, 1);

    // Strong BULLISH: EMA8 > EMA21 > EMA50 et prix > EMA8
    if(emaFast[1] > emaSlow[1] && emaSlow[1] > emaTrend[1] && close > emaFast[1]) {
        // Verifier que EMAs montent
        if(emaFast[1] > emaFast[2] && emaSlow[1] > emaSlow[2]) {
            return 1;
        }
    }

    // Strong BEARISH
    if(emaFast[1] < emaSlow[1] && emaSlow[1] < emaTrend[1] && close < emaFast[1]) {
        if(emaFast[1] < emaFast[2] && emaSlow[1] < emaSlow[2]) {
            return -1;
        }
    }

    return 0;
}

//+------------------------------------------------------------------+
//| TRADE BULLISH PULLBACK                                            |
//| Cherche un pullback dans une tendance haussiere                  |
//+------------------------------------------------------------------+
void TradeBullishPullback() {
    double emaFast[], emaSlow[];
    ArraySetAsSeries(emaFast, true);
    ArraySetAsSeries(emaSlow, true);
    CopyBuffer(h_EMA_Fast, 0, 0, 5, emaFast);
    CopyBuffer(h_EMA_Slow, 0, 0, 5, emaSlow);

    double close1 = iClose(_Symbol, TF_Entry, 1);
    double close2 = iClose(_Symbol, TF_Entry, 2);
    double low1 = iLow(_Symbol, TF_Entry, 1);
    double high1 = iHigh(_Symbol, TF_Entry, 1);

    // Trouver le dernier swing high recent (10-20 bougies)
    double recentHigh = FindRecentHigh(20);
    double recentLow = FindRecentLow(10);  // Low du pullback

    // Calculer la taille du pullback
    double pullbackSize = (recentHigh - recentLow) / _Point;

    // Verifier si pullback valide
    if(pullbackSize < MinPullbackPips || pullbackSize > MaxPullbackPips) {
        return;  // Pullback trop petit ou trop grand
    }

    // Calculer les niveaux Fibonacci
    double fibRange = recentHigh - recentLow;
    double fib50 = recentLow + (fibRange * 0.5);
    double fib618 = recentLow + (fibRange * 0.382);  // 61.8% depuis le bas
    double fib786 = recentLow + (fibRange * 0.214);  // 78.6% depuis le bas

    // Zone OTE = entre 50% et 78.6%
    double oteHigh = recentLow + (fibRange * (1 - FibOTE_Low));   // 50%
    double oteLow = recentLow + (fibRange * (1 - FibOTE_High));   // 78.6%

    // Verifier si prix dans zone OTE ou rebond sur EMA
    bool inOTE = (close1 >= oteLow && close1 <= oteHigh);
    bool nearEMA = (low1 <= emaSlow[1] * 1.002 && close1 > emaSlow[1]);  // Touche EMA21 et rebondit

    if(!inOTE && !nearEMA) {
        return;  // Pas dans une bonne zone
    }

    // Confirmation: bougie haussiere
    if(WaitForBullishCandle) {
        if(close1 <= iOpen(_Symbol, TF_Entry, 1)) {
            return;  // Pas une bougie haussiere
        }
        // Bonus: bougie avec meche basse (rejection)
        double body = MathAbs(close1 - iOpen(_Symbol, TF_Entry, 1));
        double lowerWick = MathMin(close1, iOpen(_Symbol, TF_Entry, 1)) - low1;
        if(lowerWick < body * 0.5) {
            // Pas assez de rejection, mais on peut quand meme entrer si autres criteres OK
        }
    }

    // === ENTRY ===
    Print("=== PULLBACK BUY SIGNAL ===");
    Print("Recent High: ", recentHigh, " | Recent Low: ", recentLow);
    Print("Pullback: ", pullbackSize, " pips");
    Print("In OTE: ", inOTE, " | Near EMA: ", nearEMA);

    ExecuteBuy(recentLow, recentHigh);
}

//+------------------------------------------------------------------+
//| TRADE BEARISH PULLBACK                                            |
//+------------------------------------------------------------------+
void TradeBearishPullback() {
    double emaFast[], emaSlow[];
    ArraySetAsSeries(emaFast, true);
    ArraySetAsSeries(emaSlow, true);
    CopyBuffer(h_EMA_Fast, 0, 0, 5, emaFast);
    CopyBuffer(h_EMA_Slow, 0, 0, 5, emaSlow);

    double close1 = iClose(_Symbol, TF_Entry, 1);
    double high1 = iHigh(_Symbol, TF_Entry, 1);

    double recentLow = FindRecentLow(20);
    double recentHigh = FindRecentHigh(10);

    double pullbackSize = (recentHigh - recentLow) / _Point;

    if(pullbackSize < MinPullbackPips || pullbackSize > MaxPullbackPips) {
        return;
    }

    double fibRange = recentHigh - recentLow;
    double oteHigh = recentHigh - (fibRange * (1 - FibOTE_High));
    double oteLow = recentHigh - (fibRange * (1 - FibOTE_Low));

    bool inOTE = (close1 >= oteLow && close1 <= oteHigh);
    bool nearEMA = (high1 >= emaSlow[1] * 0.998 && close1 < emaSlow[1]);

    if(!inOTE && !nearEMA) return;

    if(WaitForBullishCandle) {
        if(close1 >= iOpen(_Symbol, TF_Entry, 1)) return;
    }

    Print("=== PULLBACK SELL SIGNAL ===");
    ExecuteSell(recentHigh, recentLow);
}

//+------------------------------------------------------------------+
//| EXECUTE BUY                                                       |
//+------------------------------------------------------------------+
void ExecuteBuy(double swingLow, double swingHigh) {
    double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    // SL = sous le swing low du pullback + buffer
    double sl = swingLow - (SL_BufferPips * _Point);

    // Verifier SL pas trop large/serre
    double slPips = (entry - sl) / _Point;

    if(slPips > MaxSL_Pips) {
        sl = entry - (MaxSL_Pips * _Point);
        Print("SL ajuste au maximum: ", MaxSL_Pips, " pips");
    }
    if(slPips < MinSL_Pips) {
        sl = entry - (MinSL_Pips * _Point);
        Print("SL ajuste au minimum: ", MinSL_Pips, " pips");
    }

    // TP basé sur R:R
    double risk = entry - sl;
    double tp = entry + (risk * RiskReward);

    // Alternative: TP au dernier high + extension
    double tpAlt = swingHigh + (risk * 0.5);
    if(tpAlt > tp) tp = tpAlt;

    // Lot size
    double lots = CalculateLots(entry - sl);

    if(trade.Buy(lots, _Symbol, entry, sl, tp, Comment_Trade)) {
        g_DailyTrades++;
        Print("BUY executed: Entry=", entry, " SL=", sl, " TP=", tp, " Lots=", lots);
    }
}

//+------------------------------------------------------------------+
//| EXECUTE SELL                                                      |
//+------------------------------------------------------------------+
void ExecuteSell(double swingHigh, double swingLow) {
    double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    double sl = swingHigh + (SL_BufferPips * _Point);

    double slPips = (sl - entry) / _Point;
    if(slPips > MaxSL_Pips) sl = entry + (MaxSL_Pips * _Point);
    if(slPips < MinSL_Pips) sl = entry + (MinSL_Pips * _Point);

    double risk = sl - entry;
    double tp = entry - (risk * RiskReward);

    double lots = CalculateLots(sl - entry);

    if(trade.Sell(lots, _Symbol, entry, sl, tp, Comment_Trade)) {
        g_DailyTrades++;
        Print("SELL executed: Entry=", entry, " SL=", sl, " TP=", tp);
    }
}

//+------------------------------------------------------------------+
//| FIND RECENT HIGH (sur N bougies)                                  |
//+------------------------------------------------------------------+
double FindRecentHigh(int lookback) {
    double highest = 0;
    for(int i = 1; i <= lookback; i++) {
        double high = iHigh(_Symbol, TF_Entry, i);
        if(high > highest) highest = high;
    }
    return highest;
}

//+------------------------------------------------------------------+
//| FIND RECENT LOW (sur N bougies)                                   |
//+------------------------------------------------------------------+
double FindRecentLow(int lookback) {
    double lowest = DBL_MAX;
    for(int i = 1; i <= lookback; i++) {
        double low = iLow(_Symbol, TF_Entry, i);
        if(low < lowest) lowest = low;
    }
    return lowest;
}

//+------------------------------------------------------------------+
//| CALCULATE LOTS                                                    |
//+------------------------------------------------------------------+
double CalculateLots(double slDistance) {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * (RiskPercent / 100.0);

    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double pointValue = tickValue / tickSize * _Point;

    double lots = riskAmount / ((slDistance / _Point) * pointValue);

    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    lots = MathMax(minLot, lots);
    lots = MathMin(maxLot, lots);
    lots = NormalizeDouble(MathFloor(lots / lotStep) * lotStep, 2);

    return lots;
}

//+------------------------------------------------------------------+
//| MANAGE OPEN POSITIONS                                             |
//+------------------------------------------------------------------+
void ManageOpenPositions() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!posInfo.SelectByIndex(i)) continue;
        if(posInfo.Magic() != MagicNumber) continue;
        if(posInfo.Symbol() != _Symbol) continue;

        ulong ticket = posInfo.Ticket();

        if(UsePartialTP) ManagePartialTP(ticket);
        if(MoveToBreakeven) ManageBE(ticket);
    }
}

//+------------------------------------------------------------------+
//| PARTIAL TP                                                        |
//+------------------------------------------------------------------+
void ManagePartialTP(ulong ticket) {
    if(!PositionSelectByTicket(ticket)) return;

    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double sl = PositionGetDouble(POSITION_SL);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double volume = PositionGetDouble(POSITION_VOLUME);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

    double risk = MathAbs(openPrice - sl);
    double profit = (type == POSITION_TYPE_BUY) ? currentPrice - openPrice : openPrice - currentPrice;

    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    // A 1R, fermer partie
    if(profit >= risk && volume >= minLot * 2) {
        double closeVol = NormalizeDouble(volume * (PartialPercent / 100.0), 2);
        closeVol = MathMax(closeVol, minLot);

        if(trade.PositionClosePartial(ticket, closeVol)) {
            Print("Partial TP: ", closeVol, " lots closed at 1R");
        }
    }
}

//+------------------------------------------------------------------+
//| MOVE TO BREAKEVEN                                                 |
//+------------------------------------------------------------------+
void ManageBE(ulong ticket) {
    if(!PositionSelectByTicket(ticket)) return;

    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double sl = PositionGetDouble(POSITION_SL);
    double tp = PositionGetDouble(POSITION_TP);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

    double risk = MathAbs(openPrice - sl);
    double profit = (type == POSITION_TYPE_BUY) ? currentPrice - openPrice : openPrice - currentPrice;

    // A 1R, deplacer SL au BE
    if(profit >= risk) {
        double newSL = openPrice + ((type == POSITION_TYPE_BUY) ? 5 * _Point : -5 * _Point);

        bool shouldMove = (type == POSITION_TYPE_BUY && newSL > sl) ||
                          (type == POSITION_TYPE_SELL && newSL < sl);

        if(shouldMove) {
            if(trade.PositionModify(ticket, newSL, tp)) {
                Print("Moved to BE: ", newSL);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| COUNT POSITIONS                                                   |
//+------------------------------------------------------------------+
int CountPositions() {
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(posInfo.SelectByIndex(i) && posInfo.Magic() == MagicNumber && posInfo.Symbol() == _Symbol) {
            count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| CHECK DAILY RESET                                                 |
//+------------------------------------------------------------------+
void CheckDailyReset() {
    MqlDateTime now;
    TimeToStruct(TimeCurrent(), now);
    datetime today = StringToTime(StringFormat("%04d.%02d.%02d", now.year, now.mon, now.day));

    if(today != g_LastTradeDay) {
        g_DailyBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        g_DailyTrades = 0;
        g_LastTradeDay = today;
        Print("Daily reset - New balance: ", g_DailyBalance);
    }
}

//+------------------------------------------------------------------+
//| CHECK FTMO RULES                                                  |
//+------------------------------------------------------------------+
bool CheckFTMO() {
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);

    double dailyLoss = (g_DailyBalance - equity) / g_DailyBalance * 100;
    double totalLoss = (g_StartBalance - equity) / g_StartBalance * 100;

    if(dailyLoss >= MaxDailyLoss) {
        Print("FTMO Daily limit reached: ", dailyLoss, "%");
        return false;
    }
    if(totalLoss >= MaxTotalLoss) {
        Print("FTMO Total limit reached: ", totalLoss, "%");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| IS NEW BAR                                                        |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES tf) {
    static datetime lastBar = 0;
    datetime currentBar = iTime(_Symbol, tf, 0);

    if(currentBar != lastBar) {
        lastBar = currentBar;
        return true;
    }
    return false;
}
//+------------------------------------------------------------------+

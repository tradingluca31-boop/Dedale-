//+------------------------------------------------------------------+
//|                                                    Dedale_EA.mq5  |
//|                                                             Luca  |
//|                    DEDALE - Multi-Timeframe Trend Following       |
//+------------------------------------------------------------------+
#property copyright "Luca - DEDALE EA v1.0"
#property version   "1.00"
#property description "DEDALE - Navigate the Market Labyrinth"
#property description "H4: EMA20 Filter | H1: SMMA50 Filter | M15: OTE Sniper"
#property description "Entry only when 3 Timeframes are ALIGNED"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include "..\\Include\\PatternDetector.mqh"

//+------------------------------------------------------------------+
//|                           STRUCTURE MULTI-TF                      |
//|                                                                   |
//|   H4 (Tendance Globale)     ->  Direction principale              |
//|         |                       EMA 50/200, Structure HH/HL       |
//|         v                                                         |
//|   H1 (Validation)           ->  Confirme la tendance              |
//|         |                       EMA 21/50, meme direction         |
//|         v                                                         |
//|   M15 (Entry Sniper)        ->  Timing precis                     |
//|                                 Pullback OTE, rebond EMA          |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "=== TIMEFRAMES ==="
input ENUM_TIMEFRAMES TF_Major      = PERIOD_D1;   // D1 - Tendance MAJEURE (filtre direction)
input ENUM_TIMEFRAMES TF_Trend      = PERIOD_H4;   // H4 - Tendance globale
input ENUM_TIMEFRAMES TF_Validation = PERIOD_H1;   // H1 - Validation
input ENUM_TIMEFRAMES TF_Entry      = PERIOD_M15;  // M15 - Entry sniper

input group "=== D1 MAJOR TREND FILTER ==="
input int      D1_EMA_Fast          = 50;          // D1 EMA rapide
input int      D1_EMA_Slow          = 200;         // D1 EMA lente
input bool     OnlyTradeWithD1      = false;       // DESACTIVE: H4 est le filtre principal

input group "=== H4 TREND SETTINGS ==="
input int      H4_EMA_Fast          = 50;          // H4 EMA rapide (cross signal)
input int      H4_EMA_Slow          = 100;         // H4 EMA lente (cross signal)
input double   H4_EMA_MinDistance   = 0.15;        // Distance min EMA50/100 (% du prix)
input int      H4_CrossLookback     = 40;          // Lookback pour cross recent (barres H4)
input int      H4_EMA_Filter        = 55;          // H4 EMA 55 (FILTRE TENDANCE PRINCIPAL)
input bool     H4_UseStructure      = false;       // H4 Structure HH/HL (DESACTIVE - implicite dans EMA)

input group "=== H1 VALIDATION SETTINGS ==="
input int      H1_EMA_Fast          = 21;          // H1 EMA rapide
input int      H1_SMMA_Filter       = 50;          // H1 SMMA 50 (FILTRE PRINCIPAL)
input int      H1_ADX_Period        = 14;          // H1 ADX periode
input int      H1_ADX_Threshold     = 20;          // H1 ADX seuil tendance

input group "=== M15 ENTRY SETTINGS ==="
input int      M15_EMA              = 21;          // M15 EMA pour rebond
input int      M15_LookbackBars     = 20;          // M15 Lookback pour swings
input double   OTE_FibLow           = 0.382;       // OTE Fib bas (38.2% - capte les trends forts)
input double   OTE_FibHigh          = 0.786;       // OTE Fib haut (78.6%)
input bool     WaitBullishCandle    = true;        // Attendre bougie de confirmation

input group "=== ENTRY CONFIRMATION INDICATORS ==="
input int      RSI_Period           = 14;          // RSI Periode
input int      RSI_Oversold         = 45;          // RSI Survente (BUY si RSI < X)
input int      RSI_Overbought       = 55;          // RSI Surachat (SELL si RSI > X)
input int      Stoch_K              = 14;          // Stochastic %K
input int      Stoch_D              = 3;           // Stochastic %D
input int      Stoch_Slowing        = 3;           // Stochastic Slowing
input int      Stoch_Oversold       = 25;          // Stochastic Survente
input int      Stoch_Overbought     = 75;          // Stochastic Surachat
input bool     RequireRSI           = true;        // Exiger RSI en zone extreme
input bool     RequireStochCross    = false;       // Exiger croisement Stochastic (DESACTIVE)

input group "=== RISK MANAGEMENT ==="
input double   RiskPercent          = 1.0;         // Risque par trade (%)
input double   MinRiskReward        = 3.0;         // R:R minimum (3:1 pour FTMO)
input double   SL_ATR_Buffer        = 0.5;         // Buffer SL sous structure (x ATR)
input double   SL_ATR_Min           = 2.5;         // SL minimum (x ATR)
input double   SL_ATR_Max           = 2.5;         // SL maximum (x ATR)

input group "=== POSITION MANAGEMENT ==="
input bool     UseBreakEven         = true;        // Activer Break Even
input double   BE_TriggerR          = 1.5;         // BE se declenche a X R
input double   BE_LockR             = 0.5;         // BE verrouille X R de profit
input bool     UsePartialTP         = false;       // TP partiel (DESACTIVE - garder 100%)
input double   PartialTP_Percent    = 50.0;        // % a fermer au TP1
input bool     UseTrailingSL        = false;       // Trailing SL (DESACTIVE)
input double   TrailingATR_Mult     = 1.5;         // Trailing = ATR x mult

input group "=== FTMO PROTECTION ==="
input double   MaxDailyDD           = 100.0;       // Max DD journalier (%) - DESACTIVE
input double   MaxTotalDD           = 100.0;       // Max DD total (%) - DESACTIVE
input int      MaxDailyTrades       = 2;           // Max 2 trades/jour
input int      MaxOpenPositions     = 1;           // Max positions ouvertes

input group "=== TIME FILTER ==="
input bool     UseTimeFilter        = true;        // Utiliser filtre horaire
input int      TradeStartHour       = 7;           // Debut trading (GMT)
input int      TradeEndHour         = 20;          // Fin trading (GMT)
input bool     NoTradeFriday        = true;        // Pas de trade vendredi apres 16h

input group "=== SPREAD FILTER ==="
input bool     UseSpreadFilter      = true;        // Filtrer par spread
input int      MaxSpread            = 20;          // Spread max (points)

input group "=== PATTERN DETECTION ==="
input bool     UsePatternDetection  = true;        // Activer detection patterns H4/H1
input int      PatternLookback_H4   = 60;          // H4 lookback (barres)
input int      PatternLookback_H1   = 120;         // H1 lookback (barres)
input double   PatternTolerance     = 1.0;         // Tolerance niveaux (% - Gold=1.0)
input int      MinPatternScore      = 0;           // Score min (0=pas de filtre, 2=strict)
input bool     BlockOnReversal      = true;        // Bloquer si reversal contre tendance

input group "=== MOMENTUM CHECK ==="
input bool     UseMomentumCheck     = true;        // Activer momentum multi-bougie
input int      MomentumCandles      = 2;           // Nb bougies consecutives (2-3)

input group "=== EA SETTINGS ==="
input ulong    MagicNumber          = 202501;      // Magic Number
input string   TradeComment         = "DEDALE";    // Commentaire

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum TREND_STATE {
    TREND_STRONG_BULL = 2,
    TREND_BULL = 1,
    TREND_NEUTRAL = 0,
    TREND_BEAR = -1,
    TREND_STRONG_BEAR = -2
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  posInfo;

// Indicator handles - D1 (Major trend)
int h_D1_EMA_Fast, h_D1_EMA_Slow;

// Indicator handles - H4
int h_H4_EMA_Fast, h_H4_EMA_Slow, h_H4_EMA20;

// Indicator handles - H1
int h_H1_EMA_Fast, h_H1_SMMA50, h_H1_ADX;

// Indicator handles - M15
int h_M15_EMA, h_M15_ATR;

// Indicator handles - Entry Confirmation
int h_M15_RSI, h_M15_Stoch;

// D1 Trend direction
TREND_STATE g_D1_Trend;

// Pattern Detector
CPatternDetector g_PatternDetector;
int g_PatternScore;
bool g_ReversalWarning;

// Tracking
double g_StartBalance, g_DailyBalance;
int    g_DailyTrades;
datetime g_LastTradeDay;

// Current state
TREND_STATE g_H4_Trend;
TREND_STATE g_H1_Trend;
bool g_ValidSetup;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit() {
    //--- Trade setup
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(15);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    //--- D1 Indicators (Major Trend Filter)
    h_D1_EMA_Fast = iMA(_Symbol, TF_Major, D1_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    h_D1_EMA_Slow = iMA(_Symbol, TF_Major, D1_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);

    //--- H4 Indicators
    h_H4_EMA_Fast = iMA(_Symbol, TF_Trend, H4_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    h_H4_EMA_Slow = iMA(_Symbol, TF_Trend, H4_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
    h_H4_EMA20 = iMA(_Symbol, TF_Trend, H4_EMA_Filter, 0, MODE_EMA, PRICE_CLOSE);  // EMA 20 H4

    //--- H1 Indicators
    h_H1_EMA_Fast = iMA(_Symbol, TF_Validation, H1_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    h_H1_SMMA50 = iMA(_Symbol, TF_Validation, H1_SMMA_Filter, 0, MODE_SMMA, PRICE_CLOSE);  // SMMA 50 H1
    h_H1_ADX = iADX(_Symbol, TF_Validation, H1_ADX_Period);

    //--- M15 Indicators
    h_M15_EMA = iMA(_Symbol, TF_Entry, M15_EMA, 0, MODE_EMA, PRICE_CLOSE);
    h_M15_ATR = iATR(_Symbol, TF_Entry, 14);

    //--- Entry Confirmation Indicators
    h_M15_RSI = iRSI(_Symbol, TF_Entry, RSI_Period, PRICE_CLOSE);
    h_M15_Stoch = iStochastic(_Symbol, TF_Entry, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);

    //--- Validate handles
    if(h_H4_EMA_Fast == INVALID_HANDLE || h_H4_EMA_Slow == INVALID_HANDLE || h_H4_EMA20 == INVALID_HANDLE ||
       h_H1_EMA_Fast == INVALID_HANDLE || h_H1_SMMA50 == INVALID_HANDLE ||
       h_H1_ADX == INVALID_HANDLE || h_M15_EMA == INVALID_HANDLE || h_M15_ATR == INVALID_HANDLE ||
       h_M15_RSI == INVALID_HANDLE || h_M15_Stoch == INVALID_HANDLE) {
        Print("ERREUR: Creation indicateurs echouee");
        return INIT_FAILED;
    }

    //--- Initialize Pattern Detector
    if(UsePatternDetection) {
        if(!g_PatternDetector.Init(_Symbol, TF_Trend, TF_Validation, TF_Entry,
                                    PatternLookback_H4, PatternLookback_H1,
                                    PatternTolerance, MomentumCandles)) {
            Print("WARNING: Pattern detector init failed - continuing without patterns");
        }
    }
    g_PatternScore = 0;
    g_ReversalWarning = false;

    //--- Initialize tracking
    g_StartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    g_DailyBalance = g_StartBalance;
    g_DailyTrades = 0;

    Print("================================================");
    Print("=== DEDALE EA v1.0 - INITIALIZED ===");
    Print("Navigate the Market Labyrinth");
    Print("------------------------------------------------");
    Print("H4: EMA", H4_EMA_Filter, " Filter + EMA", H4_EMA_Fast, "/", H4_EMA_Slow);
    Print("H1: SMMA", H1_SMMA_Filter, " Filter + EMA", H1_EMA_Fast, " + ADX");
    Print("M15: OTE Entry (", OTE_FibLow*100, "%-", OTE_FibHigh*100, "%) + EMA", M15_EMA);
    Print("------------------------------------------------");
    Print(">>> 3 TIMEFRAMES MUST BE ALIGNED <<<");
    Print("Risk: ", RiskPercent, "% | Min R:R: ", MinRiskReward);
    Print("================================================");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    IndicatorRelease(h_D1_EMA_Fast);
    IndicatorRelease(h_D1_EMA_Slow);
    IndicatorRelease(h_H4_EMA_Fast);
    IndicatorRelease(h_H4_EMA_Slow);
    IndicatorRelease(h_H4_EMA20);
    IndicatorRelease(h_H1_EMA_Fast);
    IndicatorRelease(h_H1_SMMA50);
    IndicatorRelease(h_H1_ADX);
    IndicatorRelease(h_M15_EMA);
    IndicatorRelease(h_M15_ATR);
    IndicatorRelease(h_M15_RSI);
    IndicatorRelease(h_M15_Stoch);
    if(UsePatternDetection) g_PatternDetector.Deinit();
    Print("EA Deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick() {
    //--- Daily reset
    CheckDailyReset();

    //--- FTMO protection
    if(!CheckFTMO()) return;

    //--- Time filter
    if(UseTimeFilter && !IsGoodTradingTime()) return;

    //--- SPREAD FILTER - Pas de trade si spread trop haut
    if(UseSpreadFilter) {
        int currentSpread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
        if(currentSpread > MaxSpread) {
            return;  // Spread trop eleve
        }
    }

    //--- Manage open positions (BE sur chaque tick!)
    if(CountPositions() > 0) {
        ManagePositions();
    }

    //--- Max trades/positions
    if(g_DailyTrades >= MaxDailyTrades) return;
    if(CountPositions() >= MaxOpenPositions) return;

    //--- Only check on new M15 bar
    if(!IsNewBar(TF_Entry)) return;

    //=== MULTI-TIMEFRAME ANALYSIS ===

    //--- STEP 0: D1 Major Trend (Direction PRINCIPALE)
    g_D1_Trend = AnalyzeD1Trend();

    if(OnlyTradeWithD1 && g_D1_Trend == TREND_NEUTRAL) {
        return;  // Pas de tendance claire sur D1
    }

    //--- STEP 1: H4 Trend (Direction globale)
    g_H4_Trend = AnalyzeH4Trend();

    if(g_H4_Trend == TREND_NEUTRAL) {
        return;  // Pas de tendance claire sur H4
    }

    //--- FILTRE D1: H4 doit etre dans le meme sens que D1!
    if(OnlyTradeWithD1) {
        if((g_D1_Trend > 0 && g_H4_Trend < 0) || (g_D1_Trend < 0 && g_H4_Trend > 0)) {
            Print("[D1 FILTER] H4 contre D1 - SKIP");
            return;
        }
    }

    //--- STEP 2: H1 Validation
    g_H1_Trend = AnalyzeH1Validation();

    // H1 doit confirmer H4
    if((g_H4_Trend > 0 && g_H1_Trend <= 0) || (g_H4_Trend < 0 && g_H1_Trend >= 0)) {
        return;  // H1 ne confirme pas H4
    }

    //--- STEP 2.5: PATTERN DETECTION (H4 + H1) - Cache sur nouvelle barre H1
    g_PatternScore = 0;
    g_ReversalWarning = false;

    if(UsePatternDetection) {
        static datetime lastH1Bar = 0;
        static PatternScanResult cachedPatterns;

        datetime currentH1 = iTime(_Symbol, TF_Validation, 0);
        if(currentH1 != lastH1Bar) {
            int trendDir = (g_H4_Trend > 0) ? 1 : -1;
            cachedPatterns = g_PatternDetector.ScanPatterns(trendDir);
            lastH1Bar = currentH1;

            if(cachedPatterns.patternCount > 0) {
                Print("[PATTERN] ", cachedPatterns.patternCount, " patterns detectes | Score: ", cachedPatterns.totalScore);
                for(int i = 0; i < cachedPatterns.patternCount; i++) {
                    Print("  -> ", cachedPatterns.patterns[i].description, " (score: ", cachedPatterns.patterns[i].score, ")");
                }
            }
        }

        g_PatternScore = cachedPatterns.totalScore;

        // WARNING reversal contre tendance
        if(cachedPatterns.hasReversal && BlockOnReversal && cachedPatterns.totalScore < 0) {
            g_ReversalWarning = true;
            Print("[PATTERN] REVERSAL WARNING - Score negatif: ", cachedPatterns.totalScore);
        }
    }

    // Bloquer si reversal majeur detecte
    if(g_ReversalWarning) {
        Print("[PATTERN] TRADE BLOQUE - Reversal pattern contre tendance!");
        return;
    }

    // Verifier score minimum pattern
    if(UsePatternDetection && g_PatternScore < MinPatternScore) {
        return;  // Score pattern insuffisant
    }

    //--- STEP 3: M15 Entry Sniper (DANS LE SENS H4+H1)
    if(g_H4_Trend > 0 && g_H1_Trend > 0) {
        // H4/H1 bullish = BUY
        CheckBuyEntry();
    }
    else if(g_H4_Trend < 0 && g_H1_Trend < 0) {
        // H4/H1 bearish = SELL
        CheckSellEntry();
    }
}

//+------------------------------------------------------------------+
//| STEP 0: ANALYZE D1 MAJOR TREND                                    |
//| Tendance de fond - NE JAMAIS trader contre D1!                   |
//+------------------------------------------------------------------+
TREND_STATE AnalyzeD1Trend() {
    double emaFast[], emaSlow[];
    ArraySetAsSeries(emaFast, true);
    ArraySetAsSeries(emaSlow, true);

    CopyBuffer(h_D1_EMA_Fast, 0, 0, 3, emaFast);
    CopyBuffer(h_D1_EMA_Slow, 0, 0, 3, emaSlow);

    double close = iClose(_Symbol, TF_Major, 1);

    //=== D1 BULLISH: EMA50 > EMA200 ===
    if(emaFast[1] > emaSlow[1]) {
        // Tendance haussiere de fond
        bool strongBull = (close > emaFast[1]);  // Prix au-dessus EMA50
        Print("[D1] TREND: BULLISH | EMA50 > EMA200 | Prix: ", close);
        return strongBull ? TREND_STRONG_BULL : TREND_BULL;
    }

    //=== D1 BEARISH: EMA50 < EMA200 ===
    if(emaFast[1] < emaSlow[1]) {
        // Tendance baissiere de fond
        bool strongBear = (close < emaFast[1]);  // Prix en-dessous EMA50
        Print("[D1] TREND: BEARISH | EMA50 < EMA200 | Prix: ", close);
        return strongBear ? TREND_STRONG_BEAR : TREND_BEAR;
    }

    Print("[D1] TREND: NEUTRAL - EMA50 ≈ EMA200");
    return TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
//| STEP 1: ANALYZE H4 TREND                                          |
//| Direction globale du marche                                       |
//| FILTRE: Prix doit etre au-dessus/dessous EMA20 H4                |
//+------------------------------------------------------------------+
TREND_STATE AnalyzeH4Trend() {
    double ema50[], ema100[];
    ArraySetAsSeries(ema50, true);
    ArraySetAsSeries(ema100, true);
    CopyBuffer(h_H4_EMA_Fast, 0, 0, 3, ema50);
    CopyBuffer(h_H4_EMA_Slow, 0, 0, 3, ema100);

    double close = iClose(_Symbol, TF_Trend, 1);

    //=== ALIGNEMENT PUR: Prix > EMA50 > EMA100 (ou inverse) ===
    // Simplifie: plus de cross/distance/EMA55. Si l'ordre est bon = tendance confirmee.

    //=== BULLISH: Close > EMA50 > EMA100 ===
    if(close > ema50[1] && ema50[1] > ema100[1]) {
        Print("[H4] TREND: BULLISH | Close > EMA50 > EMA100 | Prix: ", close, " EMA50: ", NormalizeDouble(ema50[1], 2), " EMA100: ", NormalizeDouble(ema100[1], 2));
        return TREND_BULL;
    }

    //=== BEARISH: Close < EMA50 < EMA100 ===
    if(close < ema50[1] && ema50[1] < ema100[1]) {
        Print("[H4] TREND: BEARISH | Close < EMA50 < EMA100 | Prix: ", close, " EMA50: ", NormalizeDouble(ema50[1], 2), " EMA100: ", NormalizeDouble(ema100[1], 2));
        return TREND_BEAR;
    }

    Print("[H4] NEUTRAL - Alignement incomplet | Prix: ", close, " EMA50: ", NormalizeDouble(ema50[1], 2), " EMA100: ", NormalizeDouble(ema100[1], 2));
    return TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
//| STEP 2: ANALYZE H1 VALIDATION                                     |
//| Confirme la tendance H4                                           |
//| FILTRE: Prix doit etre au-dessus/dessous SMMA50 H1               |
//+------------------------------------------------------------------+
TREND_STATE AnalyzeH1Validation() {
    double smma50[];
    ArraySetAsSeries(smma50, true);
    CopyBuffer(h_H1_SMMA50, 0, 0, 3, smma50);

    double close = iClose(_Symbol, TF_Validation, 1);

    //=== FILTRE: Prix vs SMMA50 + direction SMMA ===
    // ADX SUPPRIME: il tue les pullbacks (ADX baisse pendant retracement)
    bool priceAboveSMMA = (close > smma50[1]);
    bool priceBelowSMMA = (close < smma50[1]);
    bool smmaRising = (smma50[1] > smma50[2]);
    bool smmaFalling = (smma50[1] < smma50[2]);

    //=== BULLISH: Prix > SMMA50 (pente ignoree - permet de capter les pullbacks) ===
    if(priceAboveSMMA) {
        Print("[H1] VALIDATION: BULLISH | Prix > SMMA50");
        return TREND_BULL;
    }

    //=== BEARISH: Prix < SMMA50 ===
    if(priceBelowSMMA) {
        Print("[H1] VALIDATION: BEARISH | Prix < SMMA50");
        return TREND_BEAR;
    }

    Print("[H1] VALIDATION: NEUTRAL - Prix: ", close, " | SMMA50: ", NormalizeDouble(smma50[1], 2));
    return TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
//| STEP 3A: CHECK BUY ENTRY ON M15                                   |
//| Entry sniper sur pullback                                         |
//+------------------------------------------------------------------+
void CheckBuyEntry() {
    double ema[];
    ArraySetAsSeries(ema, true);
    CopyBuffer(h_M15_EMA, 0, 0, 5, ema);

    //--- Prix et bougies
    double close1 = iClose(_Symbol, TF_Entry, 1);
    double open1 = iOpen(_Symbol, TF_Entry, 1);
    double low1 = iLow(_Symbol, TF_Entry, 1);
    double high1 = iHigh(_Symbol, TF_Entry, 1);

    //=== FILTRE M15: REBOND CONFIRME sur EMA21 ===
    // La bougie doit avoir TOUCHE l'EMA par le bas ET rebondi (cloture au-dessus)
    bool touchedEMA = (low1 <= ema[1] * 1.002);  // Low a touche ou traverse EMA
    bool rebounded = (close1 > ema[1]);           // Mais cloture AU-DESSUS
    bool isReboundCandle = touchedEMA && rebounded;

    // OU momentum fort: cloture actuelle > high de la bougie precedente
    double prevHigh = iHigh(_Symbol, TF_Entry, 2);
    bool hasMomentum = (close1 > prevHigh);

    if(!isReboundCandle && !hasMomentum) {
        Print("[M15] Skip BUY - Pas de rebond EMA ni momentum");
        return;
    }

    //--- Trouver swing high/low recent pour Fibonacci
    double swingHigh = FindSwingHigh(TF_Entry, M15_LookbackBars);
    double swingLow = FindSwingLow(TF_Entry, M15_LookbackBars);

    if(swingHigh == 0 || swingLow == 0 || swingHigh <= swingLow) {
        return;  // Pas de swings valides
    }

    //--- Calculer zone OTE
    double range = swingHigh - swingLow;
    double oteUpper = swingLow + range * (1 - OTE_FibLow);   // 50%
    double oteLower = swingLow + range * (1 - OTE_FibHigh);  // 78.6%

    //=== CHECK 1: Prix OBLIGATOIREMENT dans zone OTE (pullback reel) ===
    bool inOTE = (close1 >= oteLower && close1 <= oteUpper);

    if(!inOTE) {
        return;  // STRICT: Pas de trade hors OTE - on veut des pullbacks!
    }

    //--- Check 2: Pas trop pres du swing high (eviter achat au sommet)
    double distanceFromHigh = (swingHigh - close1) / range;
    bool notAtTop = (distanceFromHigh > 0.15);  // Au moins 15% sous le high

    if(!notAtTop) {
        Print("[M15] SKIP: Trop pres du swing high (", NormalizeDouble(distanceFromHigh * 100, 1), "%)");
        return;
    }

    //=== CHECK 3: Confirmation bougie OBLIGATOIRE ===
    bool isBullishCandle = (close1 > open1);  // Bougie verte

    // Pin bar avec meche basse (rejection du bas)
    double lowerWick = MathMin(open1, close1) - low1;
    double upperWick = high1 - MathMax(open1, close1);
    double body = MathAbs(close1 - open1);
    bool isPinBar = (lowerWick >= body * 1.5 && lowerWick > upperWick);

    // Engulfing bullish
    double prevClose = iClose(_Symbol, TF_Entry, 2);
    double prevOpen = iOpen(_Symbol, TF_Entry, 2);
    bool isEngulfing = (prevClose < prevOpen) && (close1 > prevOpen) && (open1 < prevClose);

    if(!isBullishCandle && !isPinBar && !isEngulfing) {
        Print("[M15] SKIP BUY: Pas de confirmation bougie (pas bullish/pinbar/engulfing)");
        return;
    }

    //=== CHECK 4: RSI - Zone de survente ou retournement ===
    if(RequireRSI) {
        double rsi[];
        ArraySetAsSeries(rsi, true);
        CopyBuffer(h_M15_RSI, 0, 0, 3, rsi);

        // RSI doit etre en zone de survente OU en train de remonter depuis survente
        bool rsiOversold = (rsi[1] < RSI_Oversold);
        bool rsiRising = (rsi[1] > rsi[2]);  // RSI monte
        bool rsiRecovering = (rsi[2] < RSI_Oversold && rsi[1] > rsi[2]);  // Etait survente, remonte

        if(!rsiOversold && !rsiRecovering) {
            Print("[M15] SKIP BUY: RSI pas en zone favorable (RSI=", NormalizeDouble(rsi[1], 1), ")");
            return;
        }
        Print("[M15] RSI OK: ", NormalizeDouble(rsi[1], 1), " | Oversold:", rsiOversold, " | Recovering:", rsiRecovering);
    }

    //=== CHECK 5: Stochastic - Croisement haussier en zone de survente ===
    if(RequireStochCross) {
        double stochK[], stochD[];
        ArraySetAsSeries(stochK, true);
        ArraySetAsSeries(stochD, true);
        CopyBuffer(h_M15_Stoch, 0, 0, 3, stochK);  // %K
        CopyBuffer(h_M15_Stoch, 1, 0, 3, stochD);  // %D

        // Stoch doit etre en zone de survente avec %K qui croise %D vers le haut
        bool stochOversold = (stochK[1] < Stoch_Oversold || stochD[1] < Stoch_Oversold);
        bool stochCrossUp = (stochK[2] < stochD[2] && stochK[1] > stochD[1]);  // Croisement haussier
        bool stochRising = (stochK[1] > stochK[2]);  // %K monte

        if(!stochOversold && !stochCrossUp) {
            Print("[M15] SKIP BUY: Stoch pas en zone favorable (K=", NormalizeDouble(stochK[1], 1), ")");
            return;
        }
        Print("[M15] Stoch OK: K=", NormalizeDouble(stochK[1], 1), " D=", NormalizeDouble(stochD[1], 1));
    }

    //=== ENTRY SIGNAL CONFIRMED ===
    Print("================================================");
    Print("[M15] >>> BUY SIGNAL CONFIRMED <<<");
    Print("OTE Zone: ", NormalizeDouble(oteLower, 2), " - ", NormalizeDouble(oteUpper, 2));
    Print("Swing High: ", swingHigh, " | Swing Low: ", swingLow);
    Print("Distance from High: ", NormalizeDouble(distanceFromHigh * 100, 1), "%");
    Print("================================================");

    ExecuteBuy(swingLow, swingHigh);
}

//+------------------------------------------------------------------+
//| STEP 3B: CHECK SELL ENTRY ON M15                                  |
//+------------------------------------------------------------------+
void CheckSellEntry() {
    double ema[];
    ArraySetAsSeries(ema, true);
    CopyBuffer(h_M15_EMA, 0, 0, 5, ema);

    double close1 = iClose(_Symbol, TF_Entry, 1);
    double open1 = iOpen(_Symbol, TF_Entry, 1);
    double high1 = iHigh(_Symbol, TF_Entry, 1);

    //=== FILTRE M15: REJECTION CONFIRMEE de EMA21 ===
    // La bougie doit avoir TOUCHE l'EMA par le haut ET ete rejetee (cloture en-dessous)
    bool touchedEMA = (high1 >= ema[1] * 0.998);  // High a touche ou traverse EMA
    bool rejected = (close1 < ema[1]);             // Mais cloture EN-DESSOUS
    bool isRejectionCandle = touchedEMA && rejected;

    // OU momentum fort: cloture actuelle < low de la bougie precedente
    double prevLow = iLow(_Symbol, TF_Entry, 2);
    bool hasMomentum = (close1 < prevLow);

    if(!isRejectionCandle && !hasMomentum) {
        Print("[M15] Skip SELL - Pas de rejection EMA ni momentum");
        return;
    }

    double swingHigh = FindSwingHigh(TF_Entry, M15_LookbackBars);
    double swingLow = FindSwingLow(TF_Entry, M15_LookbackBars);

    if(swingHigh == 0 || swingLow == 0 || swingHigh <= swingLow) return;

    double range = swingHigh - swingLow;
    double oteUpper = swingHigh - range * (1 - OTE_FibHigh);  // 78.6% depuis le haut
    double oteLower = swingHigh - range * (1 - OTE_FibLow);   // 50% depuis le haut

    //=== CHECK 1: Prix OBLIGATOIREMENT dans zone OTE (pullback reel) ===
    bool inOTE = (close1 >= oteLower && close1 <= oteUpper);

    if(!inOTE) {
        return;  // STRICT: Pas de trade hors OTE - on veut des pullbacks!
    }

    //--- Check 2: Pas trop pres du swing low (eviter vente au creux)
    double distanceFromLow = (close1 - swingLow) / range;
    bool notAtBottom = (distanceFromLow > 0.15);  // Au moins 15% au-dessus du low

    if(!notAtBottom) {
        Print("[M15] SKIP SELL: Trop pres du swing low (", NormalizeDouble(distanceFromLow * 100, 1), "%)");
        return;
    }

    //=== CHECK 3: Confirmation bougie OBLIGATOIRE ===
    bool isBearishCandle = (close1 < open1);  // Bougie rouge

    // Pin bar avec meche haute (rejection du haut)
    double upperWick = high1 - MathMax(open1, close1);
    double lowerWick = MathMin(open1, close1) - iLow(_Symbol, TF_Entry, 1);
    double body = MathAbs(close1 - open1);
    bool isPinBar = (upperWick >= body * 1.5 && upperWick > lowerWick);

    // Engulfing bearish
    double prevClose = iClose(_Symbol, TF_Entry, 2);
    double prevOpen = iOpen(_Symbol, TF_Entry, 2);
    bool isEngulfing = (prevClose > prevOpen) && (close1 < prevOpen) && (open1 > prevClose);

    if(!isBearishCandle && !isPinBar && !isEngulfing) {
        Print("[M15] SKIP SELL: Pas de confirmation bougie (pas bearish/pinbar/engulfing)");
        return;
    }

    //=== CHECK 4: RSI - Zone de surachat ou retournement ===
    if(RequireRSI) {
        double rsi[];
        ArraySetAsSeries(rsi, true);
        CopyBuffer(h_M15_RSI, 0, 0, 3, rsi);

        // RSI doit etre en zone de surachat OU en train de redescendre depuis surachat
        bool rsiOverbought = (rsi[1] > RSI_Overbought);
        bool rsiFalling = (rsi[1] < rsi[2]);  // RSI descend
        bool rsiReverting = (rsi[2] > RSI_Overbought && rsi[1] < rsi[2]);  // Etait surachat, descend

        if(!rsiOverbought && !rsiReverting) {
            Print("[M15] SKIP SELL: RSI pas en zone favorable (RSI=", NormalizeDouble(rsi[1], 1), ")");
            return;
        }
        Print("[M15] RSI OK: ", NormalizeDouble(rsi[1], 1), " | Overbought:", rsiOverbought, " | Reverting:", rsiReverting);
    }

    //=== CHECK 5: Stochastic - Croisement baissier en zone de surachat ===
    if(RequireStochCross) {
        double stochK[], stochD[];
        ArraySetAsSeries(stochK, true);
        ArraySetAsSeries(stochD, true);
        CopyBuffer(h_M15_Stoch, 0, 0, 3, stochK);  // %K
        CopyBuffer(h_M15_Stoch, 1, 0, 3, stochD);  // %D

        // Stoch doit etre en zone de surachat avec %K qui croise %D vers le bas
        bool stochOverbought = (stochK[1] > Stoch_Overbought || stochD[1] > Stoch_Overbought);
        bool stochCrossDown = (stochK[2] > stochD[2] && stochK[1] < stochD[1]);  // Croisement baissier
        bool stochFalling = (stochK[1] < stochK[2]);  // %K descend

        if(!stochOverbought && !stochCrossDown) {
            Print("[M15] SKIP SELL: Stoch pas en zone favorable (K=", NormalizeDouble(stochK[1], 1), ")");
            return;
        }
        Print("[M15] Stoch OK: K=", NormalizeDouble(stochK[1], 1), " D=", NormalizeDouble(stochD[1], 1));
    }

    Print("================================================");
    Print("[M15] >>> SELL SIGNAL CONFIRMED <<<");
    Print("================================================");

    ExecuteSell(swingHigh, swingLow);
}

//+------------------------------------------------------------------+
//| EXECUTE BUY TRADE                                                 |
//+------------------------------------------------------------------+
void ExecuteBuy(double swingLow, double swingHigh) {
    double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    //--- Calculer ATR (tout est base sur l'ATR)
    double atr[];
    ArraySetAsSeries(atr, true);
    CopyBuffer(h_M15_ATR, 0, 0, 1, atr);
    double atrValue = atr[0];

    if(atrValue == 0) { Print("ATR = 0, skip"); return; }

    //--- SL = Sous le swing low + buffer ATR
    double sl = swingLow - (atrValue * SL_ATR_Buffer);

    //--- Clamp SL entre min et max ATR
    double slDistance = entry - sl;
    double slMinDist = atrValue * SL_ATR_Min;
    double slMaxDist = atrValue * SL_ATR_Max;

    if(slDistance > slMaxDist) {
        sl = entry - slMaxDist;
        Print("SL clamp MAX: ", NormalizeDouble(SL_ATR_Max, 1), " ATR");
    }
    if(slDistance < slMinDist) {
        sl = entry - slMinDist;
        Print("SL clamp MIN: ", NormalizeDouble(SL_ATR_Min, 1), " ATR");
    }

    double slATRs = (entry - sl) / atrValue;
    Print("SL: ", NormalizeDouble(sl, 2), " (", NormalizeDouble(slATRs, 1), " ATR) | ATR=", NormalizeDouble(atrValue, 2));

    //--- TP avec R:R
    double risk = entry - sl;
    double tp = entry + (risk * MinRiskReward);

    //--- Verifier R:R
    double rr = (tp - entry) / (entry - sl);
    if(rr < MinRiskReward) {
        Print("R:R insuffisant: ", NormalizeDouble(rr, 2));
        return;
    }

    //--- Lot size
    double lots = CalculateLots(entry - sl);

    //--- Execute
    string comment = StringFormat("%s_BUY_RR%.1f", TradeComment, rr);

    if(trade.Buy(lots, _Symbol, entry, sl, tp, comment)) {
        g_DailyTrades++;

        Print("=== BUY EXECUTED ===");
        Print("Entry: ", entry);
        Print("SL: ", sl, " (", NormalizeDouble(slATRs, 1), " ATR)");
        Print("TP: ", tp, " (", NormalizeDouble((tp - entry) / atrValue, 1), " ATR)");
        Print("R:R: ", NormalizeDouble(rr, 2));
        Print("Lots: ", lots);
    }
    else {
        Print("BUY FAILED: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| EXECUTE SELL TRADE                                                |
//+------------------------------------------------------------------+
void ExecuteSell(double swingHigh, double swingLow) {
    double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    //--- Calculer ATR (tout est base sur l'ATR)
    double atr[];
    ArraySetAsSeries(atr, true);
    CopyBuffer(h_M15_ATR, 0, 0, 1, atr);
    double atrValue = atr[0];

    if(atrValue == 0) { Print("ATR = 0, skip"); return; }

    //--- SL = Au-dessus du swing high + buffer ATR
    double sl = swingHigh + (atrValue * SL_ATR_Buffer);

    //--- Clamp SL entre min et max ATR
    double slDistance = sl - entry;
    double slMinDist = atrValue * SL_ATR_Min;
    double slMaxDist = atrValue * SL_ATR_Max;

    if(slDistance > slMaxDist) sl = entry + slMaxDist;
    if(slDistance < slMinDist) sl = entry + slMinDist;

    double slATRs = (sl - entry) / atrValue;
    Print("SL: ", NormalizeDouble(sl, 2), " (", NormalizeDouble(slATRs, 1), " ATR) | ATR=", NormalizeDouble(atrValue, 2));

    double risk = sl - entry;
    double tp = entry - (risk * MinRiskReward);

    double rr = (entry - tp) / (sl - entry);
    if(rr < MinRiskReward) {
        Print("R:R insuffisant: ", NormalizeDouble(rr, 2));
        return;
    }

    double lots = CalculateLots(sl - entry);
    string comment = StringFormat("%s_SELL_RR%.1f", TradeComment, rr);

    if(trade.Sell(lots, _Symbol, entry, sl, tp, comment)) {
        g_DailyTrades++;
        Print("=== SELL EXECUTED ===");
        Print("Entry: ", entry, " | SL: ", sl, " | TP: ", tp, " | ATR: ", NormalizeDouble(atrValue, 2));
    }
}

//+------------------------------------------------------------------+
//| ANALYZE MARKET STRUCTURE                                          |
//| Returns: 1=HH/HL, -1=LH/LL, 0=neutral                            |
//+------------------------------------------------------------------+
int AnalyzeStructure(ENUM_TIMEFRAMES tf, int lookback) {
    double highs[2], lows[2];
    int hCount = 0, lCount = 0;

    for(int i = 5; i < lookback && (hCount < 2 || lCount < 2); i++) {
        // Swing High
        if(hCount < 2 && IsSwingPoint(tf, i, true)) {
            highs[hCount] = iHigh(_Symbol, tf, i);
            hCount++;
        }
        // Swing Low
        if(lCount < 2 && IsSwingPoint(tf, i, false)) {
            lows[lCount] = iLow(_Symbol, tf, i);
            lCount++;
        }
    }

    if(hCount < 2 || lCount < 2) return 0;

    // highs[0] = most recent
    bool higherHigh = (highs[0] > highs[1]);
    bool higherLow = (lows[0] > lows[1]);
    bool lowerHigh = (highs[0] < highs[1]);
    bool lowerLow = (lows[0] < lows[1]);

    if(higherHigh && higherLow) return 1;   // Bullish structure
    if(lowerHigh && lowerLow) return -1;    // Bearish structure

    return 0;
}

//+------------------------------------------------------------------+
//| IS SWING POINT                                                    |
//+------------------------------------------------------------------+
bool IsSwingPoint(ENUM_TIMEFRAMES tf, int shift, bool isHigh) {
    int lookback = 3;

    if(isHigh) {
        double high = iHigh(_Symbol, tf, shift);
        for(int i = 1; i <= lookback; i++) {
            if(iHigh(_Symbol, tf, shift - i) >= high) return false;
            if(iHigh(_Symbol, tf, shift + i) >= high) return false;
        }
        return true;
    }
    else {
        double low = iLow(_Symbol, tf, shift);
        for(int i = 1; i <= lookback; i++) {
            if(iLow(_Symbol, tf, shift - i) <= low) return false;
            if(iLow(_Symbol, tf, shift + i) <= low) return false;
        }
        return true;
    }
}

//+------------------------------------------------------------------+
//| FIND SWING HIGH                                                   |
//+------------------------------------------------------------------+
double FindSwingHigh(ENUM_TIMEFRAMES tf, int lookback) {
    for(int i = 3; i < lookback; i++) {
        if(IsSwingPoint(tf, i, true)) {
            return iHigh(_Symbol, tf, i);
        }
    }
    return 0;
}

//+------------------------------------------------------------------+
//| FIND SWING LOW                                                    |
//+------------------------------------------------------------------+
double FindSwingLow(ENUM_TIMEFRAMES tf, int lookback) {
    for(int i = 3; i < lookback; i++) {
        if(IsSwingPoint(tf, i, false)) {
            return iLow(_Symbol, tf, i);
        }
    }
    return 0;
}

//+------------------------------------------------------------------+
//| CALCULATE LOT SIZE                                                |
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
void ManagePositions() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!posInfo.SelectByIndex(i)) continue;
        if(posInfo.Magic() != MagicNumber) continue;
        if(posInfo.Symbol() != _Symbol) continue;

        ulong ticket = posInfo.Ticket();

        // Break Even a X R de profit
        if(UseBreakEven) ManageBreakEven(ticket);

        // Partial TP
        if(UsePartialTP) ManagePartialTP(ticket);
    }
}

//+------------------------------------------------------------------+
//| BREAK EVEN - Proteger le trade a X R de profit                    |
//+------------------------------------------------------------------+
void ManageBreakEven(ulong ticket) {
    if(!PositionSelectByTicket(ticket)) return;

    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double sl = PositionGetDouble(POSITION_SL);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

    double risk = MathAbs(openPrice - sl);
    if(risk == 0) return;

    double profit = (type == POSITION_TYPE_BUY) ? currentPrice - openPrice : openPrice - currentPrice;
    double profitR = profit / risk;  // Profit en multiples de R

    //--- Le trade a atteint le seuil de BE?
    if(profitR < BE_TriggerR) return;

    //--- Calculer le nouveau SL (verrouille BE_LockR de profit)
    double lockAmount = risk * BE_LockR;
    double newSL;

    if(type == POSITION_TYPE_BUY) {
        newSL = openPrice + lockAmount;
        // Ne deplacer que si c'est mieux que le SL actuel
        if(newSL <= sl) return;
    } else {
        newSL = openPrice - lockAmount;
        if(newSL >= sl) return;
    }

    //--- Deplacer le SL
    if(trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP))) {
        Print(">>> BREAK EVEN ACTIVE a ", NormalizeDouble(profitR, 1), "R | Nouveau SL: ", NormalizeDouble(newSL, 2),
              " | Profit verrouille: +", NormalizeDouble(BE_LockR, 1), "R");
    }
}

//+------------------------------------------------------------------+
//| PARTIAL TAKE PROFIT                                               |
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

    // A 1R profit, fermer partie
    if(profit >= risk && volume >= minLot * 2) {
        double closeVol = NormalizeDouble(volume * (PartialTP_Percent / 100.0), 2);
        closeVol = MathMax(closeVol, minLot);

        if(trade.PositionClosePartial(ticket, closeVol)) {
            Print(">>> PARTIAL TP: ", closeVol, " lots @ 1R");

            // Move to BE: verrouille BE_LockR x risque
            double lockAmount = risk * BE_LockR;
            double newSL = openPrice + ((type == POSITION_TYPE_BUY) ? lockAmount : -lockAmount);

            // S'assurer que le nouveau SL est mieux que l'ancien
            bool shouldMove = (type == POSITION_TYPE_BUY && newSL > sl) ||
                             (type == POSITION_TYPE_SELL && newSL < sl);

            if(shouldMove) {
                trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                Print(">>> PARTIAL TP + BE: SL -> ", newSL, " (lock ", BE_LockR, "R)");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| TRAILING STOP LOSS                                                |
//+------------------------------------------------------------------+
void ManageTrailingSL(ulong ticket) {
    if(!PositionSelectByTicket(ticket)) return;

    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double sl = PositionGetDouble(POSITION_SL);
    double tp = PositionGetDouble(POSITION_TP);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

    double atr[];
    ArraySetAsSeries(atr, true);
    CopyBuffer(h_M15_ATR, 0, 0, 1, atr);
    double trailDistance = atr[0] * TrailingATR_Mult;

    double risk = MathAbs(openPrice - sl);
    double profit = (type == POSITION_TYPE_BUY) ? currentPrice - openPrice : openPrice - currentPrice;

    // Trailer apres 1.5R
    if(profit >= risk * 1.5) {
        double newSL;

        if(type == POSITION_TYPE_BUY) {
            newSL = currentPrice - trailDistance;
            if(newSL > sl) {
                trade.PositionModify(ticket, newSL, tp);
                Print(">>> TRAILING SL: ", newSL);
            }
        }
        else {
            newSL = currentPrice + trailDistance;
            if(newSL < sl) {
                trade.PositionModify(ticket, newSL, tp);
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
        Print("=== DAILY RESET | Balance: ", g_DailyBalance, " ===");
    }
}

//+------------------------------------------------------------------+
//| CHECK FTMO RULES                                                  |
//+------------------------------------------------------------------+
bool CheckFTMO() {
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);

    double dailyLoss = (g_DailyBalance - equity) / g_DailyBalance * 100;
    double totalLoss = (g_StartBalance - equity) / g_StartBalance * 100;

    if(dailyLoss >= MaxDailyDD) {
        Print("!!! FTMO DAILY LIMIT: ", NormalizeDouble(dailyLoss, 2), "% !!!");
        return false;
    }
    if(totalLoss >= MaxTotalDD) {
        Print("!!! FTMO TOTAL LIMIT: ", NormalizeDouble(totalLoss, 2), "% !!!");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| IS GOOD TRADING TIME                                              |
//+------------------------------------------------------------------+
bool IsGoodTradingTime() {
    MqlDateTime dt;
    TimeToStruct(TimeGMT(), dt);

    // Friday restriction
    if(NoTradeFriday && dt.day_of_week == 5 && dt.hour >= 16) {
        return false;
    }

    // Hour filter
    if(dt.hour < TradeStartHour || dt.hour >= TradeEndHour) {
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

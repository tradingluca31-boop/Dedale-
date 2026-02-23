//+------------------------------------------------------------------+
//|                                                TrendFilters.mqh   |
//|                                                             Luca  |
//|                        Filtres de Tendance Optimises pour GOLD    |
//+------------------------------------------------------------------+
#property copyright "Luca"
#property strict

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum TREND_DIRECTION {
    TREND_BULLISH = 1,
    TREND_BEARISH = -1,
    TREND_NEUTRAL = 0
};

enum TREND_STRENGTH {
    STRENGTH_STRONG = 2,
    STRENGTH_MODERATE = 1,
    STRENGTH_WEAK = 0
};

//+------------------------------------------------------------------+
//| STRUCTURE RESULTAT                                                |
//+------------------------------------------------------------------+
struct TrendResult {
    TREND_DIRECTION direction;
    TREND_STRENGTH strength;
    int score;           // Score combine (-10 a +10)
    bool justChanged;    // Tendance vient de changer
    string description;
};

//+------------------------------------------------------------------+
//| CLASS: TrendFilters                                               |
//+------------------------------------------------------------------+
class CTrendFilters {
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_tfHigh;    // HTF pour direction principale
    ENUM_TIMEFRAMES m_tfMid;     // MTF pour confirmation
    ENUM_TIMEFRAMES m_tfLow;     // LTF pour timing

    // Indicator handles
    int h_EMA8, h_EMA21, h_EMA50, h_EMA200;
    int h_ATR;
    int h_ADX;
    int h_RSI;
    int h_Supertrend;

    // Previous state for change detection
    TREND_DIRECTION m_prevTrend;

public:
    CTrendFilters();
    ~CTrendFilters();

    bool Init(string symbol, ENUM_TIMEFRAMES tfHigh = PERIOD_H4,
              ENUM_TIMEFRAMES tfMid = PERIOD_H1, ENUM_TIMEFRAMES tfLow = PERIOD_M15);
    void Deinit();

    // Main function - returns combined trend analysis
    TrendResult GetTrend();

    // Individual filters
    TREND_DIRECTION Filter_EMA_Ribbon();
    TREND_DIRECTION Filter_Price_Action_Structure();
    TREND_DIRECTION Filter_Supertrend();
    TREND_DIRECTION Filter_ADX_DI();
    TREND_DIRECTION Filter_Multi_Timeframe();
    TREND_DIRECTION Filter_Momentum();

    // Utility
    bool IsTrendStrong();
    bool HasTrendChanged();
    double GetTrendScore();
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CTrendFilters::CTrendFilters() {
    m_prevTrend = TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CTrendFilters::~CTrendFilters() {
    Deinit();
}

//+------------------------------------------------------------------+
//| Initialize                                                        |
//+------------------------------------------------------------------+
bool CTrendFilters::Init(string symbol, ENUM_TIMEFRAMES tfHigh,
                         ENUM_TIMEFRAMES tfMid, ENUM_TIMEFRAMES tfLow) {
    m_symbol = symbol;
    m_tfHigh = tfHigh;
    m_tfMid = tfMid;
    m_tfLow = tfLow;

    // Create indicator handles on MTF (H1 for GOLD)
    h_EMA8 = iMA(m_symbol, m_tfMid, 8, 0, MODE_EMA, PRICE_CLOSE);
    h_EMA21 = iMA(m_symbol, m_tfMid, 21, 0, MODE_EMA, PRICE_CLOSE);
    h_EMA50 = iMA(m_symbol, m_tfMid, 50, 0, MODE_EMA, PRICE_CLOSE);
    h_EMA200 = iMA(m_symbol, m_tfMid, 200, 0, MODE_EMA, PRICE_CLOSE);
    h_ATR = iATR(m_symbol, m_tfMid, 14);
    h_ADX = iADX(m_symbol, m_tfMid, 14);
    h_RSI = iRSI(m_symbol, m_tfMid, 14, PRICE_CLOSE);

    if(h_EMA8 == INVALID_HANDLE || h_EMA21 == INVALID_HANDLE ||
       h_EMA50 == INVALID_HANDLE || h_EMA200 == INVALID_HANDLE ||
       h_ATR == INVALID_HANDLE || h_ADX == INVALID_HANDLE) {
        Print("Erreur creation indicateurs TrendFilters");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Deinitialize                                                      |
//+------------------------------------------------------------------+
void CTrendFilters::Deinit() {
    if(h_EMA8 != INVALID_HANDLE) IndicatorRelease(h_EMA8);
    if(h_EMA21 != INVALID_HANDLE) IndicatorRelease(h_EMA21);
    if(h_EMA50 != INVALID_HANDLE) IndicatorRelease(h_EMA50);
    if(h_EMA200 != INVALID_HANDLE) IndicatorRelease(h_EMA200);
    if(h_ATR != INVALID_HANDLE) IndicatorRelease(h_ATR);
    if(h_ADX != INVALID_HANDLE) IndicatorRelease(h_ADX);
    if(h_RSI != INVALID_HANDLE) IndicatorRelease(h_RSI);
}

//+------------------------------------------------------------------+
//| MAIN FUNCTION: Get Combined Trend                                 |
//+------------------------------------------------------------------+
TrendResult CTrendFilters::GetTrend() {
    TrendResult result;
    result.score = 0;
    result.description = "";

    //--- Filter 1: EMA Ribbon (Poids: 3)
    TREND_DIRECTION emaRibbon = Filter_EMA_Ribbon();
    result.score += (int)emaRibbon * 3;
    if(emaRibbon != TREND_NEUTRAL)
        result.description += "EMA" + (emaRibbon == TREND_BULLISH ? "+" : "-") + " ";

    //--- Filter 2: Price Action Structure (Poids: 3)
    TREND_DIRECTION structure = Filter_Price_Action_Structure();
    result.score += (int)structure * 3;
    if(structure != TREND_NEUTRAL)
        result.description += "PA" + (structure == TREND_BULLISH ? "+" : "-") + " ";

    //--- Filter 3: ADX + DI (Poids: 2)
    TREND_DIRECTION adx = Filter_ADX_DI();
    result.score += (int)adx * 2;
    if(adx != TREND_NEUTRAL)
        result.description += "ADX" + (adx == TREND_BULLISH ? "+" : "-") + " ";

    //--- Filter 4: Multi-Timeframe (Poids: 2)
    TREND_DIRECTION mtf = Filter_Multi_Timeframe();
    result.score += (int)mtf * 2;
    if(mtf != TREND_NEUTRAL)
        result.description += "MTF" + (mtf == TREND_BULLISH ? "+" : "-") + " ";

    //--- Determine final direction
    // Score range: -10 to +10
    if(result.score >= 4) {
        result.direction = TREND_BULLISH;
        result.strength = (result.score >= 7) ? STRENGTH_STRONG : STRENGTH_MODERATE;
    }
    else if(result.score <= -4) {
        result.direction = TREND_BEARISH;
        result.strength = (result.score <= -7) ? STRENGTH_STRONG : STRENGTH_MODERATE;
    }
    else {
        result.direction = TREND_NEUTRAL;
        result.strength = STRENGTH_WEAK;
    }

    //--- Check if trend just changed
    result.justChanged = (result.direction != m_prevTrend && m_prevTrend != TREND_NEUTRAL);
    m_prevTrend = result.direction;

    return result;
}

//+------------------------------------------------------------------+
//| FILTER 1: EMA RIBBON (Reactif + Fiable)                          |
//| Le meilleur filtre pour suivre la tendance de pres               |
//+------------------------------------------------------------------+
TREND_DIRECTION CTrendFilters::Filter_EMA_Ribbon() {
    double ema8[], ema21[], ema50[];
    ArraySetAsSeries(ema8, true);
    ArraySetAsSeries(ema21, true);
    ArraySetAsSeries(ema50, true);

    CopyBuffer(h_EMA8, 0, 0, 3, ema8);
    CopyBuffer(h_EMA21, 0, 0, 3, ema21);
    CopyBuffer(h_EMA50, 0, 0, 3, ema50);

    double close = iClose(m_symbol, m_tfMid, 1);

    //--- Bullish: Prix > EMA8 > EMA21 > EMA50 (ribbon ordonne)
    if(close > ema8[1] && ema8[1] > ema21[1] && ema21[1] > ema50[1]) {
        // Verification que les EMAs montent
        if(ema8[1] > ema8[2] && ema21[1] > ema21[2]) {
            return TREND_BULLISH;
        }
    }

    //--- Bearish: Prix < EMA8 < EMA21 < EMA50
    if(close < ema8[1] && ema8[1] < ema21[1] && ema21[1] < ema50[1]) {
        if(ema8[1] < ema8[2] && ema21[1] < ema21[2]) {
            return TREND_BEARISH;
        }
    }

    //--- Early Trend Change Detection (REACTIF)
    // Prix croise EMA8 avec momentum
    double prevClose = iClose(m_symbol, m_tfMid, 2);

    // Bullish cross: prix passe au-dessus EMA8 et EMA8 > EMA21
    if(prevClose < ema8[2] && close > ema8[1] && ema8[1] > ema21[1]) {
        return TREND_BULLISH;
    }

    // Bearish cross
    if(prevClose > ema8[2] && close < ema8[1] && ema8[1] < ema21[1]) {
        return TREND_BEARISH;
    }

    return TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
//| FILTER 2: PRICE ACTION STRUCTURE (HH/HL - LH/LL)                 |
//| Detecte les changements de structure du marche                   |
//+------------------------------------------------------------------+
TREND_DIRECTION CTrendFilters::Filter_Price_Action_Structure() {
    //--- Find last 4 swing points
    double swingHighs[2], swingLows[2];
    int highIdx = 0, lowIdx = 0;

    for(int i = 3; i < 100 && (highIdx < 2 || lowIdx < 2); i++) {
        // Swing High detection
        if(highIdx < 2) {
            double high = iHigh(m_symbol, m_tfMid, i);
            bool isSwingHigh = true;

            for(int j = 1; j <= 3; j++) {
                if(iHigh(m_symbol, m_tfMid, i-j) >= high ||
                   iHigh(m_symbol, m_tfMid, i+j) >= high) {
                    isSwingHigh = false;
                    break;
                }
            }

            if(isSwingHigh) {
                swingHighs[highIdx] = high;
                highIdx++;
            }
        }

        // Swing Low detection
        if(lowIdx < 2) {
            double low = iLow(m_symbol, m_tfMid, i);
            bool isSwingLow = true;

            for(int j = 1; j <= 3; j++) {
                if(iLow(m_symbol, m_tfMid, i-j) <= low ||
                   iLow(m_symbol, m_tfMid, i+j) <= low) {
                    isSwingLow = false;
                    break;
                }
            }

            if(isSwingLow) {
                swingLows[lowIdx] = low;
                lowIdx++;
            }
        }
    }

    if(highIdx < 2 || lowIdx < 2) return TREND_NEUTRAL;

    //--- Analyze structure
    // swingHighs[0] = most recent, swingHighs[1] = previous
    bool higherHigh = swingHighs[0] > swingHighs[1];
    bool higherLow = swingLows[0] > swingLows[1];
    bool lowerHigh = swingHighs[0] < swingHighs[1];
    bool lowerLow = swingLows[0] < swingLows[1];

    //--- Bullish structure: HH + HL
    if(higherHigh && higherLow) return TREND_BULLISH;

    //--- Bearish structure: LH + LL
    if(lowerHigh && lowerLow) return TREND_BEARISH;

    //--- BREAK OF STRUCTURE (Changement de tendance)
    double currentPrice = iClose(m_symbol, m_tfMid, 0);

    // BOS Bullish: Prix casse le dernier Lower High
    if(lowerHigh && lowerLow && currentPrice > swingHighs[0]) {
        return TREND_BULLISH;  // Changement detecte!
    }

    // BOS Bearish: Prix casse le dernier Higher Low
    if(higherHigh && higherLow && currentPrice < swingLows[0]) {
        return TREND_BEARISH;  // Changement detecte!
    }

    return TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
//| FILTER 3: ADX + DI (Force de la tendance)                        |
//+------------------------------------------------------------------+
TREND_DIRECTION CTrendFilters::Filter_ADX_DI() {
    double adx[], diPlus[], diMinus[];
    ArraySetAsSeries(adx, true);
    ArraySetAsSeries(diPlus, true);
    ArraySetAsSeries(diMinus, true);

    CopyBuffer(h_ADX, 0, 0, 3, adx);      // ADX main
    CopyBuffer(h_ADX, 1, 0, 3, diPlus);   // +DI
    CopyBuffer(h_ADX, 2, 0, 3, diMinus);  // -DI

    //--- ADX > 20 = tendance presente
    if(adx[1] < 20) return TREND_NEUTRAL;

    //--- DI+ > DI- = Bullish
    if(diPlus[1] > diMinus[1]) {
        // Confirmation: DI+ augmente ou ecart significatif
        if(diPlus[1] - diMinus[1] > 5 || diPlus[1] > diPlus[2]) {
            return TREND_BULLISH;
        }
    }

    //--- DI- > DI+ = Bearish
    if(diMinus[1] > diPlus[1]) {
        if(diMinus[1] - diPlus[1] > 5 || diMinus[1] > diMinus[2]) {
            return TREND_BEARISH;
        }
    }

    return TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
//| FILTER 4: MULTI-TIMEFRAME ALIGNMENT                              |
//+------------------------------------------------------------------+
TREND_DIRECTION CTrendFilters::Filter_Multi_Timeframe() {
    //--- Check trend on HTF (H4 or D1)
    double ema50_htf = iMA(m_symbol, m_tfHigh, 50, 0, MODE_EMA, PRICE_CLOSE);
    double close_htf = iClose(m_symbol, m_tfHigh, 1);

    //--- Check trend on MTF (H1)
    double ema50_mtf[];
    ArraySetAsSeries(ema50_mtf, true);
    CopyBuffer(h_EMA50, 0, 0, 2, ema50_mtf);
    double close_mtf = iClose(m_symbol, m_tfMid, 1);

    //--- Check trend on LTF (M15)
    double ema21_ltf = iMA(m_symbol, m_tfLow, 21, 0, MODE_EMA, PRICE_CLOSE);
    double close_ltf = iClose(m_symbol, m_tfLow, 1);

    int bullishCount = 0;
    int bearishCount = 0;

    // HTF
    if(close_htf > ema50_htf) bullishCount++;
    else bearishCount++;

    // MTF
    if(close_mtf > ema50_mtf[1]) bullishCount++;
    else bearishCount++;

    // LTF
    if(close_ltf > ema21_ltf) bullishCount++;
    else bearishCount++;

    //--- All 3 TF aligned
    if(bullishCount == 3) return TREND_BULLISH;
    if(bearishCount == 3) return TREND_BEARISH;

    //--- 2/3 aligned (less strong but valid)
    if(bullishCount >= 2) return TREND_BULLISH;
    if(bearishCount >= 2) return TREND_BEARISH;

    return TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
//| FILTER 5: MOMENTUM (RSI + Price Momentum)                        |
//+------------------------------------------------------------------+
TREND_DIRECTION CTrendFilters::Filter_Momentum() {
    double rsi[];
    ArraySetAsSeries(rsi, true);
    CopyBuffer(h_RSI, 0, 0, 5, rsi);

    //--- RSI trend
    bool rsiUptrend = rsi[1] > 50 && rsi[1] > rsi[3];
    bool rsiDowntrend = rsi[1] < 50 && rsi[1] < rsi[3];

    //--- Price momentum (ROC)
    double close1 = iClose(m_symbol, m_tfMid, 1);
    double close5 = iClose(m_symbol, m_tfMid, 5);
    double roc = ((close1 - close5) / close5) * 100;

    //--- Combined
    if(rsiUptrend && roc > 0.1) return TREND_BULLISH;
    if(rsiDowntrend && roc < -0.1) return TREND_BEARISH;

    return TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
//| Utility: Is Trend Strong?                                        |
//+------------------------------------------------------------------+
bool CTrendFilters::IsTrendStrong() {
    double adx[];
    ArraySetAsSeries(adx, true);
    CopyBuffer(h_ADX, 0, 0, 1, adx);
    return adx[0] > 25;
}

//+------------------------------------------------------------------+
//| Utility: Has Trend Changed?                                      |
//+------------------------------------------------------------------+
bool CTrendFilters::HasTrendChanged() {
    TrendResult current = GetTrend();
    return current.justChanged;
}
//+------------------------------------------------------------------+

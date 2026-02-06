//+------------------------------------------------------------------+
//|                                             PatternDetector.mqh  |
//|                                                             Luca |
//|  Detection de patterns chartistes sur H4/H1 pour GOLD (XAUUSD)  |
//|  Continuation, Consolidation, Reversal, Momentum                 |
//+------------------------------------------------------------------+
#property copyright "Luca - DEDALE EA"
#property strict

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum PATTERN_TYPE {
    PATTERN_NONE               = 0,
    // Continuation
    PATTERN_BULL_FLAG           = 1,
    PATTERN_BEAR_FLAG           = 2,
    PATTERN_ASCENDING_TRIANGLE  = 3,
    PATTERN_DESCENDING_TRIANGLE = 4,
    // Consolidation
    PATTERN_INSIDE_BAR          = 5,
    PATTERN_RANGE               = 6,
    // Reversal
    PATTERN_DOUBLE_BOTTOM       = 10,
    PATTERN_DOUBLE_TOP          = 11,
    PATTERN_INV_HEAD_SHOULDERS  = 12,
    PATTERN_HEAD_SHOULDERS      = 13,
    // Momentum
    PATTERN_MOMENTUM_BULL       = 20,
    PATTERN_MOMENTUM_BEAR       = 21
};

enum PATTERN_CATEGORY {
    CAT_NONE          = 0,
    CAT_CONTINUATION  = 1,
    CAT_CONSOLIDATION = 2,
    CAT_REVERSAL      = 3,
    CAT_MOMENTUM      = 4
};

//+------------------------------------------------------------------+
//| STRUCTURES                                                        |
//+------------------------------------------------------------------+
struct ExtSwingPoint {
    double   price;
    datetime time;
    int      barIndex;
    bool     isHigh;
};

struct PatternResult {
    PATTERN_TYPE      type;
    PATTERN_CATEGORY  category;
    int               score;
    double            keyLevel;
    double            targetPrice;
    string            description;
    bool              isActive;
    ENUM_TIMEFRAMES   detectedOn;
};

struct PatternScanResult {
    PatternResult  patterns[20];
    int            patternCount;
    int            totalScore;
    bool           hasContinuation;
    bool           hasReversal;
    bool           hasMomentum;
};

//+------------------------------------------------------------------+
//| CLASS CPatternDetector                                            |
//+------------------------------------------------------------------+
class CPatternDetector {
private:
    string           m_symbol;
    ENUM_TIMEFRAMES  m_tfH4;
    ENUM_TIMEFRAMES  m_tfH1;
    ENUM_TIMEFRAMES  m_tfM15;
    int              m_lookbackH4;
    int              m_lookbackH1;
    double           m_tolerance;
    int              m_momentumCandles;
    int              h_ATR_H4;
    int              h_ATR_H1;
    int              h_ATR_M15;

    //--- Swing point collection
    void CollectSwingPoints(ENUM_TIMEFRAMES tf, ExtSwingPoint &highs[], ExtSwingPoint &lows[],
                            int lookback, int swingStrength);
    bool IsSwingHigh(ENUM_TIMEFRAMES tf, int shift, int strength);
    bool IsSwingLow(ENUM_TIMEFRAMES tf, int shift, int strength);

    //--- Utilities
    bool   IsSameLevel(double price1, double price2, double tolerancePct);
    double GetATR(ENUM_TIMEFRAMES tf);

    //--- Pattern detectors
    bool DetectBullFlag(ENUM_TIMEFRAMES tf, int lookback, PatternResult &result);
    bool DetectBearFlag(ENUM_TIMEFRAMES tf, int lookback, PatternResult &result);
    bool DetectAscendingTriangle(ENUM_TIMEFRAMES tf, int lookback, PatternResult &result);
    bool DetectDescendingTriangle(ENUM_TIMEFRAMES tf, int lookback, PatternResult &result);
    bool DetectInsideBar(ENUM_TIMEFRAMES tf, PatternResult &result);
    bool DetectRange(ENUM_TIMEFRAMES tf, PatternResult &result);
    bool DetectDoubleBottom(ENUM_TIMEFRAMES tf, int lookback, PatternResult &result);
    bool DetectDoubleTop(ENUM_TIMEFRAMES tf, int lookback, PatternResult &result);
    bool DetectInvHeadShoulders(ENUM_TIMEFRAMES tf, int lookback, PatternResult &result);
    bool DetectHeadShoulders(ENUM_TIMEFRAMES tf, int lookback, PatternResult &result);
    bool DetectMomentumBull(ENUM_TIMEFRAMES tf, PatternResult &result);
    bool DetectMomentumBear(ENUM_TIMEFRAMES tf, PatternResult &result);

    //--- Helper to add pattern to result
    void AddPattern(PatternScanResult &scan, PatternResult &pat);

public:
    CPatternDetector();
    ~CPatternDetector();

    bool Init(string symbol, ENUM_TIMEFRAMES tfH4, ENUM_TIMEFRAMES tfH1,
              ENUM_TIMEFRAMES tfM15, int lookbackH4, int lookbackH1,
              double tolerance, int momentumCandles);
    void Deinit();

    PatternScanResult ScanPatterns(int trendDirection);
};

//+------------------------------------------------------------------+
//| Constructor / Destructor                                          |
//+------------------------------------------------------------------+
CPatternDetector::CPatternDetector() {
    h_ATR_H4 = INVALID_HANDLE;
    h_ATR_H1 = INVALID_HANDLE;
    h_ATR_M15 = INVALID_HANDLE;
}

CPatternDetector::~CPatternDetector() {
    Deinit();
}

//+------------------------------------------------------------------+
//| Init                                                              |
//+------------------------------------------------------------------+
bool CPatternDetector::Init(string symbol, ENUM_TIMEFRAMES tfH4, ENUM_TIMEFRAMES tfH1,
                            ENUM_TIMEFRAMES tfM15, int lookbackH4, int lookbackH1,
                            double tolerance, int momentumCandles) {
    m_symbol = symbol;
    m_tfH4 = tfH4;
    m_tfH1 = tfH1;
    m_tfM15 = tfM15;
    m_lookbackH4 = lookbackH4;
    m_lookbackH1 = lookbackH1;
    m_tolerance = tolerance;
    m_momentumCandles = momentumCandles;

    h_ATR_H4 = iATR(m_symbol, m_tfH4, 14);
    h_ATR_H1 = iATR(m_symbol, m_tfH1, 14);
    h_ATR_M15 = iATR(m_symbol, m_tfM15, 14);

    if(h_ATR_H4 == INVALID_HANDLE || h_ATR_H1 == INVALID_HANDLE || h_ATR_M15 == INVALID_HANDLE) {
        Print("[PatternDetector] ERREUR: ATR handles invalides");
        return false;
    }

    Print("[PatternDetector] Initialise | H4 lookback: ", lookbackH4, " | H1 lookback: ", lookbackH1,
          " | Tolerance: ", tolerance, "% | Momentum: ", momentumCandles, " bougies");
    return true;
}

//+------------------------------------------------------------------+
//| Deinit                                                            |
//+------------------------------------------------------------------+
void CPatternDetector::Deinit() {
    if(h_ATR_H4 != INVALID_HANDLE) IndicatorRelease(h_ATR_H4);
    if(h_ATR_H1 != INVALID_HANDLE) IndicatorRelease(h_ATR_H1);
    if(h_ATR_M15 != INVALID_HANDLE) IndicatorRelease(h_ATR_M15);
    h_ATR_H4 = INVALID_HANDLE;
    h_ATR_H1 = INVALID_HANDLE;
    h_ATR_M15 = INVALID_HANDLE;
}

//+------------------------------------------------------------------+
//| UTILITY: IsSameLevel                                              |
//+------------------------------------------------------------------+
bool CPatternDetector::IsSameLevel(double price1, double price2, double tolerancePct) {
    if(price1 == 0) return false;
    return MathAbs(price1 - price2) / price1 <= tolerancePct / 100.0;
}

//+------------------------------------------------------------------+
//| UTILITY: GetATR                                                   |
//+------------------------------------------------------------------+
double CPatternDetector::GetATR(ENUM_TIMEFRAMES tf) {
    int handle = INVALID_HANDLE;
    if(tf == m_tfH4) handle = h_ATR_H4;
    else if(tf == m_tfH1) handle = h_ATR_H1;
    else if(tf == m_tfM15) handle = h_ATR_M15;

    if(handle == INVALID_HANDLE) return 0;

    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(handle, 0, 0, 1, atr) <= 0) return 0;
    return atr[0];
}

//+------------------------------------------------------------------+
//| SWING POINT DETECTION                                             |
//+------------------------------------------------------------------+
bool CPatternDetector::IsSwingHigh(ENUM_TIMEFRAMES tf, int shift, int strength) {
    double high = iHigh(m_symbol, tf, shift);
    if(high == 0) return false;
    for(int i = 1; i <= strength; i++) {
        if(iHigh(m_symbol, tf, shift - i) >= high) return false;
        if(iHigh(m_symbol, tf, shift + i) >= high) return false;
    }
    return true;
}

bool CPatternDetector::IsSwingLow(ENUM_TIMEFRAMES tf, int shift, int strength) {
    double low = iLow(m_symbol, tf, shift);
    if(low == 0) return false;
    for(int i = 1; i <= strength; i++) {
        if(iLow(m_symbol, tf, shift - i) <= low) return false;
        if(iLow(m_symbol, tf, shift + i) <= low) return false;
    }
    return true;
}

void CPatternDetector::CollectSwingPoints(ENUM_TIMEFRAMES tf, ExtSwingPoint &highs[], ExtSwingPoint &lows[],
                                           int lookback, int swingStrength) {
    ArrayResize(highs, 0);
    ArrayResize(lows, 0);

    for(int i = swingStrength; i < lookback - swingStrength; i++) {
        if(IsSwingHigh(tf, i, swingStrength)) {
            int idx = ArraySize(highs);
            ArrayResize(highs, idx + 1);
            highs[idx].price = iHigh(m_symbol, tf, i);
            highs[idx].time = iTime(m_symbol, tf, i);
            highs[idx].barIndex = i;
            highs[idx].isHigh = true;
        }
        if(IsSwingLow(tf, i, swingStrength)) {
            int idx = ArraySize(lows);
            ArrayResize(lows, idx + 1);
            lows[idx].price = iLow(m_symbol, tf, i);
            lows[idx].time = iTime(m_symbol, tf, i);
            lows[idx].barIndex = i;
            lows[idx].isHigh = false;
        }
    }
}

//+------------------------------------------------------------------+
//| HELPER: Add pattern to scan result                                |
//+------------------------------------------------------------------+
void CPatternDetector::AddPattern(PatternScanResult &scan, PatternResult &pat) {
    if(scan.patternCount >= 20) return;
    scan.patterns[scan.patternCount] = pat;
    scan.patternCount++;
    scan.totalScore += pat.score;

    if(pat.category == CAT_CONTINUATION) scan.hasContinuation = true;
    if(pat.category == CAT_REVERSAL)     scan.hasReversal = true;
    if(pat.category == CAT_MOMENTUM)     scan.hasMomentum = true;
}

//+------------------------------------------------------------------+
//| ============= MOMENTUM PATTERNS ================================  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Momentum Bullish: 2-3 bougies vertes consecutives                 |
//+------------------------------------------------------------------+
bool CPatternDetector::DetectMomentumBull(ENUM_TIMEFRAMES tf, PatternResult &result) {
    int count = 0;
    bool bodiesGrowing = true;
    double prevBody = 0;

    for(int i = 1; i <= m_momentumCandles + 1 && i <= 4; i++) {
        double close_i = iClose(m_symbol, tf, i);
        double open_i = iOpen(m_symbol, tf, i);
        double high_i = iHigh(m_symbol, tf, i);

        if(close_i <= open_i) break;  // Pas bullish

        double body = close_i - open_i;
        double upperWick = high_i - close_i;

        // Meche haute < 50% du body (pas de rejection)
        if(upperWick > body * 0.5) break;

        // Each close > previous close
        if(i > 1) {
            double prevClose = iClose(m_symbol, tf, i - 1);
            if(close_i >= prevClose) break;  // Pas de progression (note: i=1 est plus recent)
        }

        if(prevBody > 0 && body < prevBody * 0.7) bodiesGrowing = false;
        prevBody = body;
        count++;
    }

    if(count < m_momentumCandles) return false;

    result.type = PATTERN_MOMENTUM_BULL;
    result.category = CAT_MOMENTUM;
    result.score = (count >= 3 && bodiesGrowing) ? 2 : 1;
    result.keyLevel = iClose(m_symbol, tf, 1);
    result.targetPrice = 0;
    result.description = StringFormat("Momentum Bull (%d bougies) sur %s",
                                       count, EnumToString(tf));
    result.isActive = true;
    result.detectedOn = tf;
    return true;
}

//+------------------------------------------------------------------+
//| Momentum Bearish: 2-3 bougies rouges consecutives                 |
//+------------------------------------------------------------------+
bool CPatternDetector::DetectMomentumBear(ENUM_TIMEFRAMES tf, PatternResult &result) {
    int count = 0;
    bool bodiesGrowing = true;
    double prevBody = 0;

    for(int i = 1; i <= m_momentumCandles + 1 && i <= 4; i++) {
        double close_i = iClose(m_symbol, tf, i);
        double open_i = iOpen(m_symbol, tf, i);
        double low_i = iLow(m_symbol, tf, i);

        if(close_i >= open_i) break;  // Pas bearish

        double body = open_i - close_i;
        double lowerWick = close_i - low_i;

        if(lowerWick > body * 0.5) break;

        if(i > 1) {
            double prevClose = iClose(m_symbol, tf, i - 1);
            if(close_i <= prevClose) break;
        }

        if(prevBody > 0 && body < prevBody * 0.7) bodiesGrowing = false;
        prevBody = body;
        count++;
    }

    if(count < m_momentumCandles) return false;

    result.type = PATTERN_MOMENTUM_BEAR;
    result.category = CAT_MOMENTUM;
    result.score = (count >= 3 && bodiesGrowing) ? 2 : 1;
    result.keyLevel = iClose(m_symbol, tf, 1);
    result.targetPrice = 0;
    result.description = StringFormat("Momentum Bear (%d bougies) sur %s",
                                       count, EnumToString(tf));
    result.isActive = true;
    result.detectedOn = tf;
    return true;
}

//+------------------------------------------------------------------+
//| ============= CONSOLIDATION PATTERNS ===========================  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Inside Bar: High < prev High ET Low > prev Low                    |
//+------------------------------------------------------------------+
bool CPatternDetector::DetectInsideBar(ENUM_TIMEFRAMES tf, PatternResult &result) {
    double high1 = iHigh(m_symbol, tf, 1);
    double low1 = iLow(m_symbol, tf, 1);
    double high2 = iHigh(m_symbol, tf, 2);
    double low2 = iLow(m_symbol, tf, 2);

    if(high1 >= high2 || low1 <= low2) return false;

    result.type = PATTERN_INSIDE_BAR;
    result.category = CAT_CONSOLIDATION;
    result.score = 1;
    result.keyLevel = (high2 + low2) / 2.0;
    result.targetPrice = 0;
    result.description = StringFormat("Inside Bar sur %s", EnumToString(tf));
    result.isActive = true;
    result.detectedOn = tf;
    return true;
}

//+------------------------------------------------------------------+
//| Range: Prix comprime dans < 1.5 ATR sur 10 barres                |
//+------------------------------------------------------------------+
bool CPatternDetector::DetectRange(ENUM_TIMEFRAMES tf, PatternResult &result) {
    double atr = GetATR(tf);
    if(atr == 0) return false;

    int rangeBars = 10;
    double highestHigh = 0;
    double lowestLow = 999999;

    for(int i = 1; i <= rangeBars; i++) {
        double h = iHigh(m_symbol, tf, i);
        double l = iLow(m_symbol, tf, i);
        if(h > highestHigh) highestHigh = h;
        if(l < lowestLow) lowestLow = l;
    }

    double totalRange = highestHigh - lowestLow;
    if(totalRange >= atr * 1.5) return false;  // Pas en range

    result.type = PATTERN_RANGE;
    result.category = CAT_CONSOLIDATION;
    result.score = 1;
    result.keyLevel = (highestHigh + lowestLow) / 2.0;
    result.targetPrice = 0;
    result.description = StringFormat("Range (%.1f%% ATR) sur %s",
                                       totalRange / atr * 100, EnumToString(tf));
    result.isActive = true;
    result.detectedOn = tf;
    return true;
}

//+------------------------------------------------------------------+
//| ============= CONTINUATION PATTERNS ============================  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Bull Flag: Pole impulsif haussier + consolidation baissiere       |
//+------------------------------------------------------------------+
bool CPatternDetector::DetectBullFlag(ENUM_TIMEFRAMES tf, int lookback, PatternResult &result) {
    double atr = GetATR(tf);
    if(atr == 0) return false;

    //--- Phase 1: Chercher le POLE (mouvement impulsif haussier)
    int poleStart = -1, poleEnd = -1;
    double poleHigh = 0, poleLow = 999999;

    for(int startBar = 5; startBar < lookback - 7; startBar++) {
        // Chercher une serie de 3-7 bougies avec mouvement > 1.5 ATR
        for(int len = 3; len <= 7 && (startBar + len) < lookback; len++) {
            double moveHigh = 0, moveLow = 999999;
            int bullCount = 0;

            for(int j = 0; j < len; j++) {
                int bar = startBar + j;
                double h = iHigh(m_symbol, tf, bar);
                double l = iLow(m_symbol, tf, bar);
                double c = iClose(m_symbol, tf, bar);
                double o = iOpen(m_symbol, tf, bar);
                if(h > moveHigh) moveHigh = h;
                if(l < moveLow) moveLow = l;
                if(c > o) bullCount++;
            }

            double move = moveHigh - moveLow;

            // Pole valide: mouvement > 1.5 ATR et >60% bougies bullish
            if(move >= atr * 1.5 && bullCount >= len * 0.6) {
                // Verifier que le mouvement est vers le HAUT
                double startPrice = iClose(m_symbol, tf, startBar + len - 1);
                double endPrice = iClose(m_symbol, tf, startBar);
                if(endPrice > startPrice) {
                    poleStart = startBar + len - 1;
                    poleEnd = startBar;
                    poleHigh = moveHigh;
                    poleLow = moveLow;
                    break;
                }
            }
        }
        if(poleStart >= 0) break;
    }

    if(poleStart < 0) return false;  // Pas de pole trouve

    //--- Phase 2: Chercher le FLAG (consolidation apres le pole)
    double poleHeight = poleHigh - poleLow;
    int flagStart = poleEnd;
    int flagEnd = 1;

    if(flagStart - flagEnd < 3) return false;  // Flag trop court

    // Verifier que le flag retrace 20-50% du pole
    double flagHigh = 0, flagLow = 999999;
    int bearCount = 0;
    int flagBars = flagStart - flagEnd;

    for(int i = flagEnd; i < flagStart; i++) {
        double h = iHigh(m_symbol, tf, i);
        double l = iLow(m_symbol, tf, i);
        double c = iClose(m_symbol, tf, i);
        double o = iOpen(m_symbol, tf, i);
        if(h > flagHigh) flagHigh = h;
        if(l < flagLow) flagLow = l;
        if(c < o) bearCount++;
    }

    double retracement = (poleHigh - flagLow) / poleHeight;
    if(retracement < 0.15 || retracement > 0.55) return false;  // Retracement pas dans range

    // Le flag doit etre calme (range < pole)
    double flagRange = flagHigh - flagLow;
    if(flagRange > poleHeight * 0.6) return false;

    //--- Pattern confirme
    double target = iClose(m_symbol, tf, 1) + poleHeight;

    result.type = PATTERN_BULL_FLAG;
    result.category = CAT_CONTINUATION;
    result.score = 3;
    result.keyLevel = flagHigh;
    result.targetPrice = target;
    result.description = StringFormat("Bull Flag (pole=%.0f pips, retrace=%.0f%%) sur %s",
                                       poleHeight / _Point, retracement * 100, EnumToString(tf));
    result.isActive = true;
    result.detectedOn = tf;
    return true;
}

//+------------------------------------------------------------------+
//| Bear Flag: Pole impulsif baissier + consolidation haussiere       |
//+------------------------------------------------------------------+
bool CPatternDetector::DetectBearFlag(ENUM_TIMEFRAMES tf, int lookback, PatternResult &result) {
    double atr = GetATR(tf);
    if(atr == 0) return false;

    int poleStart = -1, poleEnd = -1;
    double poleHigh = 0, poleLow = 999999;

    for(int startBar = 5; startBar < lookback - 7; startBar++) {
        for(int len = 3; len <= 7 && (startBar + len) < lookback; len++) {
            double moveHigh = 0, moveLow = 999999;
            int bearCount = 0;

            for(int j = 0; j < len; j++) {
                int bar = startBar + j;
                double h = iHigh(m_symbol, tf, bar);
                double l = iLow(m_symbol, tf, bar);
                double c = iClose(m_symbol, tf, bar);
                double o = iOpen(m_symbol, tf, bar);
                if(h > moveHigh) moveHigh = h;
                if(l < moveLow) moveLow = l;
                if(c < o) bearCount++;
            }

            double move = moveHigh - moveLow;

            if(move >= atr * 1.5 && bearCount >= len * 0.6) {
                double startPrice = iClose(m_symbol, tf, startBar + len - 1);
                double endPrice = iClose(m_symbol, tf, startBar);
                if(endPrice < startPrice) {
                    poleStart = startBar + len - 1;
                    poleEnd = startBar;
                    poleHigh = moveHigh;
                    poleLow = moveLow;
                    break;
                }
            }
        }
        if(poleStart >= 0) break;
    }

    if(poleStart < 0) return false;

    double poleHeight = poleHigh - poleLow;
    int flagStart = poleEnd;
    int flagEnd = 1;

    if(flagStart - flagEnd < 3) return false;

    double flagHigh = 0, flagLow = 999999;
    for(int i = flagEnd; i < flagStart; i++) {
        double h = iHigh(m_symbol, tf, i);
        double l = iLow(m_symbol, tf, i);
        if(h > flagHigh) flagHigh = h;
        if(l < flagLow) flagLow = l;
    }

    double retracement = (flagHigh - poleLow) / poleHeight;
    if(retracement < 0.15 || retracement > 0.55) return false;

    double flagRange = flagHigh - flagLow;
    if(flagRange > poleHeight * 0.6) return false;

    double target = iClose(m_symbol, tf, 1) - poleHeight;

    result.type = PATTERN_BEAR_FLAG;
    result.category = CAT_CONTINUATION;
    result.score = 3;
    result.keyLevel = flagLow;
    result.targetPrice = target;
    result.description = StringFormat("Bear Flag (pole=%.0f pips, retrace=%.0f%%) sur %s",
                                       poleHeight / _Point, retracement * 100, EnumToString(tf));
    result.isActive = true;
    result.detectedOn = tf;
    return true;
}

//+------------------------------------------------------------------+
//| Ascending Triangle: Resistance horizontale + Higher Lows          |
//+------------------------------------------------------------------+
bool CPatternDetector::DetectAscendingTriangle(ENUM_TIMEFRAMES tf, int lookback, PatternResult &result) {
    ExtSwingPoint highs[], lows[];
    CollectSwingPoints(tf, highs, lows, lookback, 3);

    if(ArraySize(highs) < 2 || ArraySize(lows) < 2) return false;

    //--- Verifier resistance horizontale (highs au meme niveau)
    int horizontalCount = 0;
    double resistanceLevel = highs[0].price;

    for(int i = 1; i < ArraySize(highs) && i < 5; i++) {
        if(IsSameLevel(highs[i].price, resistanceLevel, m_tolerance)) {
            horizontalCount++;
            resistanceLevel = (resistanceLevel + highs[i].price) / 2.0;  // Moyenne
        }
    }

    if(horizontalCount < 1) return false;  // Au moins 2 touches sur resistance

    //--- Verifier higher lows (lows croissants)
    int higherLowCount = 0;
    for(int i = 0; i < ArraySize(lows) - 1 && i < 4; i++) {
        if(lows[i].price > lows[i + 1].price) {  // Plus recent > plus ancien
            higherLowCount++;
        }
    }

    if(higherLowCount < 1) return false;  // Au moins 2 higher lows

    //--- Prix actuel doit etre pres de la resistance (pret a casser)
    double close = iClose(m_symbol, tf, 1);
    double distToResistance = (resistanceLevel - close) / resistanceLevel * 100;
    if(distToResistance > 2.0 || distToResistance < -0.5) return false;

    double height = resistanceLevel - lows[0].price;

    result.type = PATTERN_ASCENDING_TRIANGLE;
    result.category = CAT_CONTINUATION;
    result.score = 2;
    result.keyLevel = resistanceLevel;
    result.targetPrice = resistanceLevel + height;
    result.description = StringFormat("Ascending Triangle (resist=%.2f, %d touches) sur %s",
                                       resistanceLevel, horizontalCount + 1, EnumToString(tf));
    result.isActive = true;
    result.detectedOn = tf;
    return true;
}

//+------------------------------------------------------------------+
//| Descending Triangle: Support horizontal + Lower Highs             |
//+------------------------------------------------------------------+
bool CPatternDetector::DetectDescendingTriangle(ENUM_TIMEFRAMES tf, int lookback, PatternResult &result) {
    ExtSwingPoint highs[], lows[];
    CollectSwingPoints(tf, highs, lows, lookback, 3);

    if(ArraySize(highs) < 2 || ArraySize(lows) < 2) return false;

    //--- Verifier support horizontal
    int horizontalCount = 0;
    double supportLevel = lows[0].price;

    for(int i = 1; i < ArraySize(lows) && i < 5; i++) {
        if(IsSameLevel(lows[i].price, supportLevel, m_tolerance)) {
            horizontalCount++;
            supportLevel = (supportLevel + lows[i].price) / 2.0;
        }
    }

    if(horizontalCount < 1) return false;

    //--- Verifier lower highs
    int lowerHighCount = 0;
    for(int i = 0; i < ArraySize(highs) - 1 && i < 4; i++) {
        if(highs[i].price < highs[i + 1].price) {
            lowerHighCount++;
        }
    }

    if(lowerHighCount < 1) return false;

    //--- Prix pres du support
    double close = iClose(m_symbol, tf, 1);
    double distToSupport = (close - supportLevel) / supportLevel * 100;
    if(distToSupport > 2.0 || distToSupport < -0.5) return false;

    double height = highs[ArraySize(highs) - 1].price - supportLevel;

    result.type = PATTERN_DESCENDING_TRIANGLE;
    result.category = CAT_CONTINUATION;
    result.score = 2;
    result.keyLevel = supportLevel;
    result.targetPrice = supportLevel - height;
    result.description = StringFormat("Descending Triangle (support=%.2f, %d touches) sur %s",
                                       supportLevel, horizontalCount + 1, EnumToString(tf));
    result.isActive = true;
    result.detectedOn = tf;
    return true;
}

//+------------------------------------------------------------------+
//| ============= REVERSAL PATTERNS ================================  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Double Bottom: 2 lows au meme niveau + neckline                   |
//+------------------------------------------------------------------+
bool CPatternDetector::DetectDoubleBottom(ENUM_TIMEFRAMES tf, int lookback, PatternResult &result) {
    ExtSwingPoint highs[], lows[];
    CollectSwingPoints(tf, highs, lows, lookback, 3);

    if(ArraySize(lows) < 2 || ArraySize(highs) < 1) return false;

    //--- Chercher 2 lows au meme niveau
    for(int i = 0; i < ArraySize(lows) - 1 && i < 5; i++) {
        for(int j = i + 1; j < ArraySize(lows) && j < 6; j++) {
            // Distance minimum entre les 2 bottoms (au moins 8 barres)
            if(MathAbs(lows[i].barIndex - lows[j].barIndex) < 8) continue;

            if(!IsSameLevel(lows[i].price, lows[j].price, m_tolerance)) continue;

            //--- Trouver le neckline (plus haut point entre les 2 lows)
            double neckline = 0;
            int startBar = MathMin(lows[i].barIndex, lows[j].barIndex);
            int endBar = MathMax(lows[i].barIndex, lows[j].barIndex);

            for(int k = startBar; k <= endBar; k++) {
                double h = iHigh(m_symbol, tf, k);
                if(h > neckline) neckline = h;
            }

            if(neckline == 0) continue;

            //--- Le prix actuel doit etre au-dessus ou pres du neckline
            double close = iClose(m_symbol, tf, 1);
            double bottomLevel = (lows[i].price + lows[j].price) / 2.0;
            double height = neckline - bottomLevel;

            // Le 2eme bottom doit etre le plus recent (index plus petit)
            if(lows[i].barIndex > lows[j].barIndex) continue;

            // Prix pres du neckline ou au-dessus
            double distToNeck = (close - neckline) / neckline * 100;
            if(distToNeck < -2.0) continue;  // Trop loin sous le neckline

            result.type = PATTERN_DOUBLE_BOTTOM;
            result.category = CAT_REVERSAL;
            result.score = 3;
            result.keyLevel = neckline;
            result.targetPrice = neckline + height;
            result.description = StringFormat("Double Bottom (neck=%.2f, bottom=%.2f) sur %s",
                                               neckline, bottomLevel, EnumToString(tf));
            result.isActive = true;
            result.detectedOn = tf;
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Double Top: 2 highs au meme niveau + neckline                    |
//+------------------------------------------------------------------+
bool CPatternDetector::DetectDoubleTop(ENUM_TIMEFRAMES tf, int lookback, PatternResult &result) {
    ExtSwingPoint highs[], lows[];
    CollectSwingPoints(tf, highs, lows, lookback, 3);

    if(ArraySize(highs) < 2 || ArraySize(lows) < 1) return false;

    for(int i = 0; i < ArraySize(highs) - 1 && i < 5; i++) {
        for(int j = i + 1; j < ArraySize(highs) && j < 6; j++) {
            if(MathAbs(highs[i].barIndex - highs[j].barIndex) < 8) continue;

            if(!IsSameLevel(highs[i].price, highs[j].price, m_tolerance)) continue;

            //--- Neckline (plus bas point entre les 2 tops)
            double neckline = 999999;
            int startBar = MathMin(highs[i].barIndex, highs[j].barIndex);
            int endBar = MathMax(highs[i].barIndex, highs[j].barIndex);

            for(int k = startBar; k <= endBar; k++) {
                double l = iLow(m_symbol, tf, k);
                if(l < neckline) neckline = l;
            }

            if(neckline >= 999999) continue;

            double close = iClose(m_symbol, tf, 1);
            double topLevel = (highs[i].price + highs[j].price) / 2.0;
            double height = topLevel - neckline;

            if(highs[i].barIndex > highs[j].barIndex) continue;

            double distToNeck = (neckline - close) / neckline * 100;
            if(distToNeck < -2.0) continue;

            result.type = PATTERN_DOUBLE_TOP;
            result.category = CAT_REVERSAL;
            result.score = 3;
            result.keyLevel = neckline;
            result.targetPrice = neckline - height;
            result.description = StringFormat("Double Top (neck=%.2f, top=%.2f) sur %s",
                                               neckline, topLevel, EnumToString(tf));
            result.isActive = true;
            result.detectedOn = tf;
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Inverse Head & Shoulders: 3 lows, milieu = plus bas               |
//+------------------------------------------------------------------+
bool CPatternDetector::DetectInvHeadShoulders(ENUM_TIMEFRAMES tf, int lookback, PatternResult &result) {
    ExtSwingPoint highs[], lows[];
    CollectSwingPoints(tf, highs, lows, lookback, 3);

    if(ArraySize(lows) < 3 || ArraySize(highs) < 2) return false;

    //--- Chercher 3 lows: milieu (Head) est le plus bas
    for(int h_idx = 0; h_idx < ArraySize(lows) - 2 && h_idx < 4; h_idx++) {
        // Lows tries par barIndex croissant (recent en premier)
        // Right shoulder = lows[h_idx], Head = lows[h_idx+1], Left shoulder = lows[h_idx+2]
        ExtSwingPoint rightShoulder = lows[h_idx];
        ExtSwingPoint head = lows[h_idx + 1];
        ExtSwingPoint leftShoulder = lows[h_idx + 2];

        // Head doit etre le plus bas
        if(head.price >= rightShoulder.price || head.price >= leftShoulder.price) continue;

        // Shoulders au meme niveau (tolerance 2% pour Gold)
        if(!IsSameLevel(leftShoulder.price, rightShoulder.price, m_tolerance * 2)) continue;

        // Head doit etre significativement plus bas (au moins 0.3%)
        double shoulderAvg = (leftShoulder.price + rightShoulder.price) / 2.0;
        if((shoulderAvg - head.price) / shoulderAvg * 100 < 0.3) continue;

        // Espacement minimum entre les points
        if(MathAbs(head.barIndex - rightShoulder.barIndex) < 5) continue;
        if(MathAbs(head.barIndex - leftShoulder.barIndex) < 5) continue;

        //--- Calculer neckline (plus haut entre head et shoulders)
        double neckline = 0;
        int start = rightShoulder.barIndex;
        int end = leftShoulder.barIndex;
        for(int k = start; k <= end; k++) {
            double hi = iHigh(m_symbol, tf, k);
            if(hi > neckline) neckline = hi;
        }

        if(neckline == 0) continue;

        double close = iClose(m_symbol, tf, 1);
        double height = neckline - head.price;

        // Prix pres du neckline
        double distToNeck = (close - neckline) / neckline * 100;
        if(distToNeck < -3.0) continue;

        result.type = PATTERN_INV_HEAD_SHOULDERS;
        result.category = CAT_REVERSAL;
        result.score = 3;
        result.keyLevel = neckline;
        result.targetPrice = neckline + height;
        result.description = StringFormat("Inv H&S (neck=%.2f, head=%.2f) sur %s",
                                           neckline, head.price, EnumToString(tf));
        result.isActive = true;
        result.detectedOn = tf;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Head & Shoulders: 3 highs, milieu = plus haut                    |
//+------------------------------------------------------------------+
bool CPatternDetector::DetectHeadShoulders(ENUM_TIMEFRAMES tf, int lookback, PatternResult &result) {
    ExtSwingPoint highs[], lows[];
    CollectSwingPoints(tf, highs, lows, lookback, 3);

    if(ArraySize(highs) < 3 || ArraySize(lows) < 2) return false;

    for(int h_idx = 0; h_idx < ArraySize(highs) - 2 && h_idx < 4; h_idx++) {
        ExtSwingPoint rightShoulder = highs[h_idx];
        ExtSwingPoint head = highs[h_idx + 1];
        ExtSwingPoint leftShoulder = highs[h_idx + 2];

        // Head doit etre le plus haut
        if(head.price <= rightShoulder.price || head.price <= leftShoulder.price) continue;

        // Shoulders au meme niveau
        if(!IsSameLevel(leftShoulder.price, rightShoulder.price, m_tolerance * 2)) continue;

        // Head significativement plus haut
        double shoulderAvg = (leftShoulder.price + rightShoulder.price) / 2.0;
        if((head.price - shoulderAvg) / shoulderAvg * 100 < 0.3) continue;

        // Espacement minimum
        if(MathAbs(head.barIndex - rightShoulder.barIndex) < 5) continue;
        if(MathAbs(head.barIndex - leftShoulder.barIndex) < 5) continue;

        //--- Neckline (plus bas entre head et shoulders)
        double neckline = 999999;
        int start = rightShoulder.barIndex;
        int end = leftShoulder.barIndex;
        for(int k = start; k <= end; k++) {
            double lo = iLow(m_symbol, tf, k);
            if(lo < neckline) neckline = lo;
        }

        if(neckline >= 999999) continue;

        double close = iClose(m_symbol, tf, 1);
        double height = head.price - neckline;

        double distToNeck = (neckline - close) / neckline * 100;
        if(distToNeck < -3.0) continue;

        result.type = PATTERN_HEAD_SHOULDERS;
        result.category = CAT_REVERSAL;
        result.score = 3;
        result.keyLevel = neckline;
        result.targetPrice = neckline - height;
        result.description = StringFormat("H&S (neck=%.2f, head=%.2f) sur %s",
                                           neckline, head.price, EnumToString(tf));
        result.isActive = true;
        result.detectedOn = tf;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| ============= MAIN SCAN =======================================  |
//+------------------------------------------------------------------+
PatternScanResult CPatternDetector::ScanPatterns(int trendDirection) {
    PatternScanResult scan;
    scan.patternCount = 0;
    scan.totalScore = 0;
    scan.hasContinuation = false;
    scan.hasReversal = false;
    scan.hasMomentum = false;

    PatternResult pat;

    //=== MOMENTUM (H1 + M15) ===
    if(trendDirection > 0) {
        if(DetectMomentumBull(m_tfH1, pat))  AddPattern(scan, pat);
        if(DetectMomentumBull(m_tfM15, pat)) AddPattern(scan, pat);
    } else {
        if(DetectMomentumBear(m_tfH1, pat))  AddPattern(scan, pat);
        if(DetectMomentumBear(m_tfM15, pat)) AddPattern(scan, pat);
    }

    //=== CONSOLIDATION (H1) ===
    if(DetectInsideBar(m_tfH1, pat)) AddPattern(scan, pat);
    if(DetectRange(m_tfH1, pat))     AddPattern(scan, pat);

    //=== CONTINUATION (H4 + H1) ===
    if(trendDirection > 0) {
        if(DetectBullFlag(m_tfH4, m_lookbackH4, pat))            AddPattern(scan, pat);
        if(DetectBullFlag(m_tfH1, m_lookbackH1, pat))            AddPattern(scan, pat);
        if(DetectAscendingTriangle(m_tfH4, m_lookbackH4, pat))   AddPattern(scan, pat);
        if(DetectAscendingTriangle(m_tfH1, m_lookbackH1, pat))   AddPattern(scan, pat);
    } else {
        if(DetectBearFlag(m_tfH4, m_lookbackH4, pat))            AddPattern(scan, pat);
        if(DetectBearFlag(m_tfH1, m_lookbackH1, pat))            AddPattern(scan, pat);
        if(DetectDescendingTriangle(m_tfH4, m_lookbackH4, pat))  AddPattern(scan, pat);
        if(DetectDescendingTriangle(m_tfH1, m_lookbackH1, pat))  AddPattern(scan, pat);
    }

    //=== REVERSAL (H4 - WARNING si contre tendance) ===
    // Double Bottom = bullish reversal → BON si on achete, MAUVAIS si on vend
    if(DetectDoubleBottom(m_tfH4, m_lookbackH4, pat)) {
        if(trendDirection < 0) {
            pat.score = -2;  // CONTRE notre direction SELL
            pat.description += " [CONTRE TENDANCE!]";
        }
        AddPattern(scan, pat);
    }
    if(DetectDoubleTop(m_tfH4, m_lookbackH4, pat)) {
        if(trendDirection > 0) {
            pat.score = -2;  // CONTRE notre direction BUY
            pat.description += " [CONTRE TENDANCE!]";
        }
        AddPattern(scan, pat);
    }
    if(DetectInvHeadShoulders(m_tfH4, m_lookbackH4, pat)) {
        if(trendDirection < 0) {
            pat.score = -3;
            pat.description += " [CONTRE TENDANCE!]";
        }
        AddPattern(scan, pat);
    }
    if(DetectHeadShoulders(m_tfH4, m_lookbackH4, pat)) {
        if(trendDirection > 0) {
            pat.score = -3;
            pat.description += " [CONTRE TENDANCE!]";
        }
        AddPattern(scan, pat);
    }

    return scan;
}

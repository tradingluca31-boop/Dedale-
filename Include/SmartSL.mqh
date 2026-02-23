//+------------------------------------------------------------------+
//|                                                     SmartSL.mqh   |
//|                                                             Luca  |
//|                    Stop Loss Intelligent base sur Structure       |
//+------------------------------------------------------------------+
#property copyright "Luca"
#property strict

//+------------------------------------------------------------------+
//| STRUCTURE SWING POINT                                             |
//+------------------------------------------------------------------+
struct SwingLevel {
    double price;
    datetime time;
    int barIndex;
    int touches;      // Nombre de fois teste
    bool isValid;
};

//+------------------------------------------------------------------+
//| CLASS: SmartStopLoss                                              |
//+------------------------------------------------------------------+
class CSmartSL {
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_tf;
    int h_ATR;

    // Buffer de securite (en % de l'ATR)
    double m_bufferPercent;

public:
    CSmartSL();
    ~CSmartSL();

    bool Init(string symbol, ENUM_TIMEFRAMES tf = PERIOD_H1, double bufferPercent = 20.0);
    void Deinit();

    //--- METHODES DE CALCUL SL
    double GetStructureSL_Buy();      // SL sous le dernier swing low
    double GetStructureSL_Sell();     // SL au-dessus du dernier swing high

    double GetSL_BelowLastLow(int numberOfLows = 1);   // Sous le(s) dernier(s) creux
    double GetSL_AboveLastHigh(int numberOfHighs = 1); // Au-dessus du(des) dernier(s) sommet(s)

    //--- SWING DETECTION
    SwingLevel FindLastSwingLow(int lookback = 50);
    SwingLevel FindLastSwingHigh(int lookback = 50);
    SwingLevel FindStrongestSwingLow(int lookback = 100);  // Le plus teste
    SwingLevel FindStrongestSwingHigh(int lookback = 100);

    //--- VALIDATION
    bool IsSLTooWide(double entry, double sl, double maxRiskPips);
    bool IsSLTooTight(double entry, double sl, double minRiskPips);
    double AdjustSLIfNeeded(double entry, double sl, double minPips, double maxPips);

    //--- UTILITY
    double GetATR();
    double GetBuffer();
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CSmartSL::CSmartSL() {
    m_bufferPercent = 20.0;  // 20% de l'ATR par defaut
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CSmartSL::~CSmartSL() {
    Deinit();
}

//+------------------------------------------------------------------+
//| Initialize                                                        |
//+------------------------------------------------------------------+
bool CSmartSL::Init(string symbol, ENUM_TIMEFRAMES tf, double bufferPercent) {
    m_symbol = symbol;
    m_tf = tf;
    m_bufferPercent = bufferPercent;

    h_ATR = iATR(m_symbol, m_tf, 14);
    if(h_ATR == INVALID_HANDLE) {
        Print("Erreur creation ATR pour SmartSL");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Deinitialize                                                      |
//+------------------------------------------------------------------+
void CSmartSL::Deinit() {
    if(h_ATR != INVALID_HANDLE) IndicatorRelease(h_ATR);
}

//+------------------------------------------------------------------+
//| GET STRUCTURE SL FOR BUY                                          |
//| SL = Dernier Swing Low - Buffer                                   |
//+------------------------------------------------------------------+
double CSmartSL::GetStructureSL_Buy() {
    SwingLevel swingLow = FindLastSwingLow();

    if(!swingLow.isValid) {
        Print("Aucun swing low trouve - utilisation ATR");
        double close = iClose(m_symbol, m_tf, 0);
        return close - (GetATR() * 2);
    }

    // SL = Swing Low - Buffer
    double buffer = GetBuffer();
    double sl = swingLow.price - buffer;

    Print("Structure SL BUY: ", sl, " (Swing Low: ", swingLow.price, " - Buffer: ", buffer, ")");

    return sl;
}

//+------------------------------------------------------------------+
//| GET STRUCTURE SL FOR SELL                                         |
//| SL = Dernier Swing High + Buffer                                  |
//+------------------------------------------------------------------+
double CSmartSL::GetStructureSL_Sell() {
    SwingLevel swingHigh = FindLastSwingHigh();

    if(!swingHigh.isValid) {
        Print("Aucun swing high trouve - utilisation ATR");
        double close = iClose(m_symbol, m_tf, 0);
        return close + (GetATR() * 2);
    }

    // SL = Swing High + Buffer
    double buffer = GetBuffer();
    double sl = swingHigh.price + buffer;

    Print("Structure SL SELL: ", sl, " (Swing High: ", swingHigh.price, " + Buffer: ", buffer, ")");

    return sl;
}

//+------------------------------------------------------------------+
//| FIND LAST SWING LOW                                               |
//| Cherche le dernier creux significatif                            |
//+------------------------------------------------------------------+
SwingLevel CSmartSL::FindLastSwingLow(int lookback) {
    SwingLevel result;
    result.isValid = false;

    for(int i = 3; i < lookback; i++) {
        double low = iLow(m_symbol, m_tf, i);
        bool isSwingLow = true;

        // Verifier que c'est un vrai creux (3 bougies de chaque cote)
        for(int j = 1; j <= 3; j++) {
            if(iLow(m_symbol, m_tf, i - j) <= low ||
               iLow(m_symbol, m_tf, i + j) <= low) {
                isSwingLow = false;
                break;
            }
        }

        if(isSwingLow) {
            result.price = low;
            result.time = iTime(m_symbol, m_tf, i);
            result.barIndex = i;
            result.touches = CountTouches(low, true, lookback);
            result.isValid = true;

            Print("Swing Low trouve: ", low, " (Bar ", i, ", Touches: ", result.touches, ")");
            return result;
        }
    }

    return result;
}

//+------------------------------------------------------------------+
//| FIND LAST SWING HIGH                                              |
//+------------------------------------------------------------------+
SwingLevel CSmartSL::FindLastSwingHigh(int lookback) {
    SwingLevel result;
    result.isValid = false;

    for(int i = 3; i < lookback; i++) {
        double high = iHigh(m_symbol, m_tf, i);
        bool isSwingHigh = true;

        for(int j = 1; j <= 3; j++) {
            if(iHigh(m_symbol, m_tf, i - j) >= high ||
               iHigh(m_symbol, m_tf, i + j) >= high) {
                isSwingHigh = false;
                break;
            }
        }

        if(isSwingHigh) {
            result.price = high;
            result.time = iTime(m_symbol, m_tf, i);
            result.barIndex = i;
            result.touches = CountTouches(high, false, lookback);
            result.isValid = true;

            Print("Swing High trouve: ", high, " (Bar ", i, ", Touches: ", result.touches, ")");
            return result;
        }
    }

    return result;
}

//+------------------------------------------------------------------+
//| FIND STRONGEST SWING LOW                                          |
//| Trouve le creux le plus teste (plus fort = plus de touches)      |
//+------------------------------------------------------------------+
SwingLevel CSmartSL::FindStrongestSwingLow(int lookback) {
    SwingLevel strongest;
    strongest.isValid = false;
    strongest.touches = 0;

    SwingLevel swings[];
    int count = 0;

    // Collecter tous les swing lows
    for(int i = 3; i < lookback; i++) {
        double low = iLow(m_symbol, m_tf, i);
        bool isSwingLow = true;

        for(int j = 1; j <= 3; j++) {
            if(iLow(m_symbol, m_tf, i - j) <= low ||
               iLow(m_symbol, m_tf, i + j) <= low) {
                isSwingLow = false;
                break;
            }
        }

        if(isSwingLow) {
            ArrayResize(swings, count + 1);
            swings[count].price = low;
            swings[count].time = iTime(m_symbol, m_tf, i);
            swings[count].barIndex = i;
            swings[count].touches = CountTouches(low, true, lookback);
            swings[count].isValid = true;

            if(swings[count].touches > strongest.touches) {
                strongest = swings[count];
            }

            count++;
        }
    }

    return strongest;
}

//+------------------------------------------------------------------+
//| FIND STRONGEST SWING HIGH                                         |
//+------------------------------------------------------------------+
SwingLevel CSmartSL::FindStrongestSwingHigh(int lookback) {
    SwingLevel strongest;
    strongest.isValid = false;
    strongest.touches = 0;

    for(int i = 3; i < lookback; i++) {
        double high = iHigh(m_symbol, m_tf, i);
        bool isSwingHigh = true;

        for(int j = 1; j <= 3; j++) {
            if(iHigh(m_symbol, m_tf, i - j) >= high ||
               iHigh(m_symbol, m_tf, i + j) >= high) {
                isSwingHigh = false;
                break;
            }
        }

        if(isSwingHigh) {
            int touches = CountTouches(high, false, lookback);
            if(touches > strongest.touches) {
                strongest.price = high;
                strongest.time = iTime(m_symbol, m_tf, i);
                strongest.barIndex = i;
                strongest.touches = touches;
                strongest.isValid = true;
            }
        }
    }

    return strongest;
}

//+------------------------------------------------------------------+
//| COUNT TOUCHES                                                     |
//| Compte combien de fois un niveau a ete teste                     |
//+------------------------------------------------------------------+
int CountTouches(double level, bool isSupport, int lookback) {
    int touches = 0;
    double tolerance = GetATR() * 0.3;  // 30% ATR de tolerance

    for(int i = 0; i < lookback; i++) {
        if(isSupport) {
            double low = iLow(m_symbol, m_tf, i);
            if(MathAbs(low - level) <= tolerance) {
                touches++;
            }
        }
        else {
            double high = iHigh(m_symbol, m_tf, i);
            if(MathAbs(high - level) <= tolerance) {
                touches++;
            }
        }
    }

    return touches;
}

//+------------------------------------------------------------------+
//| GET SL BELOW LAST N LOWS                                          |
//| Pour un SL plus conservateur: sous les 2-3 derniers creux        |
//+------------------------------------------------------------------+
double CSmartSL::GetSL_BelowLastLow(int numberOfLows) {
    double lowestLow = DBL_MAX;
    int foundCount = 0;

    for(int i = 3; i < 100 && foundCount < numberOfLows; i++) {
        double low = iLow(m_symbol, m_tf, i);
        bool isSwingLow = true;

        for(int j = 1; j <= 3; j++) {
            if(iLow(m_symbol, m_tf, i - j) <= low ||
               iLow(m_symbol, m_tf, i + j) <= low) {
                isSwingLow = false;
                break;
            }
        }

        if(isSwingLow) {
            if(low < lowestLow) {
                lowestLow = low;
            }
            foundCount++;
        }
    }

    if(lowestLow == DBL_MAX) {
        return iClose(m_symbol, m_tf, 0) - (GetATR() * 2);
    }

    return lowestLow - GetBuffer();
}

//+------------------------------------------------------------------+
//| GET SL ABOVE LAST N HIGHS                                         |
//+------------------------------------------------------------------+
double CSmartSL::GetSL_AboveLastHigh(int numberOfHighs) {
    double highestHigh = 0;
    int foundCount = 0;

    for(int i = 3; i < 100 && foundCount < numberOfHighs; i++) {
        double high = iHigh(m_symbol, m_tf, i);
        bool isSwingHigh = true;

        for(int j = 1; j <= 3; j++) {
            if(iHigh(m_symbol, m_tf, i - j) >= high ||
               iHigh(m_symbol, m_tf, i + j) >= high) {
                isSwingHigh = false;
                break;
            }
        }

        if(isSwingHigh) {
            if(high > highestHigh) {
                highestHigh = high;
            }
            foundCount++;
        }
    }

    if(highestHigh == 0) {
        return iClose(m_symbol, m_tf, 0) + (GetATR() * 2);
    }

    return highestHigh + GetBuffer();
}

//+------------------------------------------------------------------+
//| VALIDATION: SL TROP LARGE?                                        |
//+------------------------------------------------------------------+
bool CSmartSL::IsSLTooWide(double entry, double sl, double maxRiskPips) {
    double riskPips = MathAbs(entry - sl) / _Point;
    return riskPips > maxRiskPips;
}

//+------------------------------------------------------------------+
//| VALIDATION: SL TROP SERRE?                                        |
//+------------------------------------------------------------------+
bool CSmartSL::IsSLTooTight(double entry, double sl, double minRiskPips) {
    double riskPips = MathAbs(entry - sl) / _Point;
    return riskPips < minRiskPips;
}

//+------------------------------------------------------------------+
//| ADJUST SL IF NEEDED                                               |
//| Ajuste le SL s'il est trop large ou trop serre                   |
//+------------------------------------------------------------------+
double CSmartSL::AdjustSLIfNeeded(double entry, double sl, double minPips, double maxPips) {
    double riskPips = MathAbs(entry - sl) / _Point;
    bool isBuy = (sl < entry);

    // Trop serre -> elargir au minimum
    if(riskPips < minPips) {
        Print("SL trop serre (", riskPips, " pips) -> Ajuste a ", minPips, " pips");
        if(isBuy) {
            return entry - (minPips * _Point);
        } else {
            return entry + (minPips * _Point);
        }
    }

    // Trop large -> reduire au maximum (MAIS garder la structure si possible)
    if(riskPips > maxPips) {
        Print("SL trop large (", riskPips, " pips) -> Ajuste a ", maxPips, " pips");
        Print("ATTENTION: SL ne protege plus la structure!");
        if(isBuy) {
            return entry - (maxPips * _Point);
        } else {
            return entry + (maxPips * _Point);
        }
    }

    return sl;  // Pas d'ajustement necessaire
}

//+------------------------------------------------------------------+
//| GET ATR                                                           |
//+------------------------------------------------------------------+
double CSmartSL::GetATR() {
    double atr[];
    ArraySetAsSeries(atr, true);
    CopyBuffer(h_ATR, 0, 0, 1, atr);
    return atr[0];
}

//+------------------------------------------------------------------+
//| GET BUFFER                                                        |
//| Buffer = pourcentage de l'ATR pour eviter les meches             |
//+------------------------------------------------------------------+
double CSmartSL::GetBuffer() {
    return GetATR() * (m_bufferPercent / 100.0);
}
//+------------------------------------------------------------------+

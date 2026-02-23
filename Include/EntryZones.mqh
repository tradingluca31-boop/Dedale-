//+------------------------------------------------------------------+
//|                                                  EntryZones.mqh   |
//|                                                             Luca  |
//|            Zones d'Entree Strategiques - Fibonacci, S/R, OTE      |
//+------------------------------------------------------------------+
#property copyright "Luca"
#property strict

//+------------------------------------------------------------------+
//| NIVEAUX FIBONACCI IMPORTANTS                                      |
//+------------------------------------------------------------------+
// Retracements classiques
#define FIB_236  0.236
#define FIB_382  0.382
#define FIB_500  0.500
#define FIB_618  0.618   // GOLDEN RATIO - Le plus important!
#define FIB_786  0.786

// OTE Zone (Optimal Trade Entry) - Concept ICT
#define OTE_LOW  0.62
#define OTE_HIGH 0.79

//+------------------------------------------------------------------+
//| STRUCTURES                                                        |
//+------------------------------------------------------------------+
struct FibLevel {
    double price;
    double ratio;
    string name;
    bool isOTE;
};

struct EntryZone {
    double upperBound;
    double lowerBound;
    double optimalEntry;   // Meilleur prix d'entree
    string zoneType;       // "FIB", "SR", "FVG", "OTE"
    int quality;           // Score 1-10
};

struct SwingPoint {
    double price;
    datetime time;
    int barIndex;
    bool isHigh;
};

//+------------------------------------------------------------------+
//| CLASS: EntryZones                                                 |
//+------------------------------------------------------------------+
class CEntryZones {
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_tf;

    // Swing points storage
    SwingPoint m_lastSwingHigh;
    SwingPoint m_lastSwingLow;

    // ATR for dynamic zones
    int h_ATR;

public:
    CEntryZones();
    ~CEntryZones();

    bool Init(string symbol, ENUM_TIMEFRAMES tf = PERIOD_H1);
    void Deinit();

    //--- FIBONACCI METHODS
    void CalculateFibLevels(FibLevel &levels[], bool isBullish);
    bool IsPriceInOTE(bool isBullish);
    bool IsPriceAtFibLevel(double targetFib, double tolerance = 0.01);
    double GetFibLevel(double ratio, bool isBullish);

    //--- SWING POINTS
    void UpdateSwingPoints(int lookback = 50);
    SwingPoint GetLastSwingHigh();
    SwingPoint GetLastSwingLow();

    //--- PREMIUM/DISCOUNT ZONES
    bool IsInDiscountZone(bool isBullish);  // Zone d'achat favorable
    bool IsInPremiumZone(bool isBullish);   // Zone de vente favorable

    //--- ENTRY VALIDATION
    bool IsOptimalBuyZone();
    bool IsOptimalSellZone();
    EntryZone GetBestEntryZone(bool isBullish);

    //--- FAIR VALUE GAP
    bool FindFVG(bool isBullish, double &upperBound, double &lowerBound);

    //--- SUPPORT/RESISTANCE
    bool IsNearSupport(double tolerance = 0.002);
    bool IsNearResistance(double tolerance = 0.002);
    double FindNearestSupport();
    double FindNearestResistance();

    //--- UTILITY
    double GetCurrentPrice();
    double GetATR();
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CEntryZones::CEntryZones() {
    m_lastSwingHigh.price = 0;
    m_lastSwingLow.price = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CEntryZones::~CEntryZones() {
    Deinit();
}

//+------------------------------------------------------------------+
//| Initialize                                                        |
//+------------------------------------------------------------------+
bool CEntryZones::Init(string symbol, ENUM_TIMEFRAMES tf) {
    m_symbol = symbol;
    m_tf = tf;

    h_ATR = iATR(m_symbol, m_tf, 14);
    if(h_ATR == INVALID_HANDLE) {
        Print("Erreur creation ATR");
        return false;
    }

    // Initialize swing points
    UpdateSwingPoints();

    return true;
}

//+------------------------------------------------------------------+
//| Deinitialize                                                      |
//+------------------------------------------------------------------+
void CEntryZones::Deinit() {
    if(h_ATR != INVALID_HANDLE) IndicatorRelease(h_ATR);
}

//+------------------------------------------------------------------+
//| UPDATE SWING POINTS                                               |
//| Trouve les derniers swing high/low pour calculer Fibonacci        |
//+------------------------------------------------------------------+
void CEntryZones::UpdateSwingPoints(int lookback) {
    bool foundHigh = false;
    bool foundLow = false;

    for(int i = 5; i < lookback && (!foundHigh || !foundLow); i++) {
        //--- Swing High
        if(!foundHigh) {
            double high = iHigh(m_symbol, m_tf, i);
            bool isSwingHigh = true;

            for(int j = 1; j <= 5; j++) {
                if(iHigh(m_symbol, m_tf, i-j) >= high ||
                   iHigh(m_symbol, m_tf, i+j) >= high) {
                    isSwingHigh = false;
                    break;
                }
            }

            if(isSwingHigh) {
                m_lastSwingHigh.price = high;
                m_lastSwingHigh.time = iTime(m_symbol, m_tf, i);
                m_lastSwingHigh.barIndex = i;
                m_lastSwingHigh.isHigh = true;
                foundHigh = true;
            }
        }

        //--- Swing Low
        if(!foundLow) {
            double low = iLow(m_symbol, m_tf, i);
            bool isSwingLow = true;

            for(int j = 1; j <= 5; j++) {
                if(iLow(m_symbol, m_tf, i-j) <= low ||
                   iLow(m_symbol, m_tf, i+j) <= low) {
                    isSwingLow = false;
                    break;
                }
            }

            if(isSwingLow) {
                m_lastSwingLow.price = low;
                m_lastSwingLow.time = iTime(m_symbol, m_tf, i);
                m_lastSwingLow.barIndex = i;
                m_lastSwingLow.isHigh = false;
                foundLow = true;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| GET FIBONACCI LEVEL                                               |
//| Calcule un niveau Fib specifique                                  |
//+------------------------------------------------------------------+
double CEntryZones::GetFibLevel(double ratio, bool isBullish) {
    UpdateSwingPoints();

    double high = m_lastSwingHigh.price;
    double low = m_lastSwingLow.price;
    double range = high - low;

    if(isBullish) {
        // Pour achat: retracement depuis le haut vers le bas
        // Fib 0.618 = Low + (Range * 0.382) car on mesure depuis le bas
        return low + (range * (1 - ratio));
    }
    else {
        // Pour vente: retracement depuis le bas vers le haut
        return high - (range * (1 - ratio));
    }
}

//+------------------------------------------------------------------+
//| CALCULATE ALL FIB LEVELS                                          |
//+------------------------------------------------------------------+
void CEntryZones::CalculateFibLevels(FibLevel &levels[], bool isBullish) {
    UpdateSwingPoints();

    ArrayResize(levels, 5);

    double ratios[] = {FIB_236, FIB_382, FIB_500, FIB_618, FIB_786};
    string names[] = {"23.6%", "38.2%", "50.0%", "61.8%", "78.6%"};

    for(int i = 0; i < 5; i++) {
        levels[i].ratio = ratios[i];
        levels[i].name = names[i];
        levels[i].price = GetFibLevel(ratios[i], isBullish);
        levels[i].isOTE = (ratios[i] >= OTE_LOW && ratios[i] <= OTE_HIGH);
    }
}

//+------------------------------------------------------------------+
//| IS PRICE IN OTE (Optimal Trade Entry) ZONE                        |
//| Zone entre 62% et 79% Fibonacci - MEILLEURE ZONE D'ENTREE        |
//+------------------------------------------------------------------+
bool CEntryZones::IsPriceInOTE(bool isBullish) {
    double currentPrice = GetCurrentPrice();

    double oteLow = GetFibLevel(OTE_HIGH, isBullish);   // 79%
    double oteHigh = GetFibLevel(OTE_LOW, isBullish);   // 62%

    // Ajuster selon direction
    if(isBullish) {
        // Pour achat: prix doit etre dans la zone basse (discount)
        return (currentPrice >= oteLow && currentPrice <= oteHigh);
    }
    else {
        // Pour vente: prix doit etre dans la zone haute (premium)
        return (currentPrice <= oteLow && currentPrice >= oteHigh);
    }
}

//+------------------------------------------------------------------+
//| IS PRICE AT SPECIFIC FIB LEVEL                                    |
//+------------------------------------------------------------------+
bool CEntryZones::IsPriceAtFibLevel(double targetFib, double tolerance) {
    double currentPrice = GetCurrentPrice();
    double fibPrice = GetFibLevel(targetFib, true);

    double diff = MathAbs(currentPrice - fibPrice) / fibPrice;
    return diff <= tolerance;
}

//+------------------------------------------------------------------+
//| IS IN DISCOUNT ZONE (Pour acheter)                                |
//| Prix en dessous de 50% du range = zone favorable pour achat       |
//+------------------------------------------------------------------+
bool CEntryZones::IsInDiscountZone(bool isBullish) {
    if(!isBullish) return false;

    UpdateSwingPoints();

    double currentPrice = GetCurrentPrice();
    double midPoint = (m_lastSwingHigh.price + m_lastSwingLow.price) / 2;

    // Discount = en dessous du milieu
    return currentPrice < midPoint;
}

//+------------------------------------------------------------------+
//| IS IN PREMIUM ZONE (Pour vendre)                                  |
//| Prix au dessus de 50% du range = zone favorable pour vente        |
//+------------------------------------------------------------------+
bool CEntryZones::IsInPremiumZone(bool isBullish) {
    if(isBullish) return false;

    UpdateSwingPoints();

    double currentPrice = GetCurrentPrice();
    double midPoint = (m_lastSwingHigh.price + m_lastSwingLow.price) / 2;

    // Premium = au dessus du milieu
    return currentPrice > midPoint;
}

//+------------------------------------------------------------------+
//| IS OPTIMAL BUY ZONE                                               |
//| Combine plusieurs criteres pour valider zone d'achat              |
//+------------------------------------------------------------------+
bool CEntryZones::IsOptimalBuyZone() {
    int score = 0;

    // 1. Dans la zone OTE (62-79%)
    if(IsPriceInOTE(true)) score += 3;

    // 2. Dans la zone Discount (sous 50%)
    if(IsInDiscountZone(true)) score += 2;

    // 3. Pres d'un niveau Fib important (61.8% ou 78.6%)
    if(IsPriceAtFibLevel(FIB_618, 0.005)) score += 2;
    if(IsPriceAtFibLevel(FIB_786, 0.005)) score += 2;

    // 4. Pres d'un support
    if(IsNearSupport()) score += 2;

    // 5. FVG bullish present
    double fvgUpper, fvgLower;
    if(FindFVG(true, fvgUpper, fvgLower)) {
        double price = GetCurrentPrice();
        if(price >= fvgLower && price <= fvgUpper) score += 2;
    }

    // Score minimum de 5 pour valider
    return score >= 5;
}

//+------------------------------------------------------------------+
//| IS OPTIMAL SELL ZONE                                              |
//+------------------------------------------------------------------+
bool CEntryZones::IsOptimalSellZone() {
    int score = 0;

    // 1. Dans la zone OTE
    if(IsPriceInOTE(false)) score += 3;

    // 2. Dans la zone Premium
    if(IsInPremiumZone(false)) score += 2;

    // 3. Pres d'un niveau Fib important
    if(IsPriceAtFibLevel(FIB_618, 0.005)) score += 2;
    if(IsPriceAtFibLevel(FIB_786, 0.005)) score += 2;

    // 4. Pres d'une resistance
    if(IsNearResistance()) score += 2;

    // 5. FVG bearish present
    double fvgUpper, fvgLower;
    if(FindFVG(false, fvgUpper, fvgLower)) {
        double price = GetCurrentPrice();
        if(price >= fvgLower && price <= fvgUpper) score += 2;
    }

    return score >= 5;
}

//+------------------------------------------------------------------+
//| GET BEST ENTRY ZONE                                               |
//| Retourne la meilleure zone d'entree avec prix optimal             |
//+------------------------------------------------------------------+
EntryZone CEntryZones::GetBestEntryZone(bool isBullish) {
    EntryZone zone;
    zone.quality = 0;

    UpdateSwingPoints();

    double atr = GetATR();

    if(isBullish) {
        // Zone OTE pour achat
        zone.upperBound = GetFibLevel(OTE_LOW, true);   // 62%
        zone.lowerBound = GetFibLevel(OTE_HIGH, true);  // 79%
        zone.optimalEntry = GetFibLevel(FIB_618, true); // 61.8% = meilleur
        zone.zoneType = "OTE_BUY";

        // Ajuster avec le support le plus proche si present
        double support = FindNearestSupport();
        if(support > 0 && support > zone.lowerBound && support < zone.upperBound) {
            zone.optimalEntry = support + (atr * 0.1);  // Legrement au-dessus
            zone.quality += 2;
        }
    }
    else {
        // Zone OTE pour vente
        zone.lowerBound = GetFibLevel(OTE_LOW, false);
        zone.upperBound = GetFibLevel(OTE_HIGH, false);
        zone.optimalEntry = GetFibLevel(FIB_618, false);
        zone.zoneType = "OTE_SELL";

        double resistance = FindNearestResistance();
        if(resistance > 0 && resistance > zone.lowerBound && resistance < zone.upperBound) {
            zone.optimalEntry = resistance - (atr * 0.1);
            zone.quality += 2;
        }
    }

    // Calculer qualite de la zone
    zone.quality += 5;  // Base score

    // Bonus si FVG confirme
    double fvgU, fvgL;
    if(FindFVG(isBullish, fvgU, fvgL)) zone.quality += 2;

    return zone;
}

//+------------------------------------------------------------------+
//| FIND FAIR VALUE GAP (FVG)                                         |
//| Desequilibre entre bougies = zone d'attraction du prix           |
//+------------------------------------------------------------------+
bool CEntryZones::FindFVG(bool isBullish, double &upperBound, double &lowerBound) {
    for(int i = 2; i < 50; i++) {
        double high1 = iHigh(m_symbol, m_tf, i + 1);
        double low1 = iLow(m_symbol, m_tf, i + 1);
        double high3 = iHigh(m_symbol, m_tf, i - 1);
        double low3 = iLow(m_symbol, m_tf, i - 1);

        if(isBullish) {
            // Bullish FVG: gap entre high de bougie 1 et low de bougie 3
            if(low3 > high1) {
                upperBound = low3;
                lowerBound = high1;

                // Verifier que le FVG n'est pas deja rempli
                double currentLow = iLow(m_symbol, m_tf, 0);
                if(currentLow > lowerBound) {
                    return true;  // FVG encore valide
                }
            }
        }
        else {
            // Bearish FVG: gap entre low de bougie 1 et high de bougie 3
            if(high3 < low1) {
                upperBound = low1;
                lowerBound = high3;

                double currentHigh = iHigh(m_symbol, m_tf, 0);
                if(currentHigh < upperBound) {
                    return true;
                }
            }
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| FIND NEAREST SUPPORT                                              |
//+------------------------------------------------------------------+
double CEntryZones::FindNearestSupport() {
    double currentPrice = GetCurrentPrice();
    double nearestSupport = 0;
    double minDistance = DBL_MAX;

    // Chercher les swing lows recents
    for(int i = 5; i < 100; i++) {
        double low = iLow(m_symbol, m_tf, i);
        bool isSwingLow = true;

        for(int j = 1; j <= 3; j++) {
            if(iLow(m_symbol, m_tf, i-j) <= low ||
               iLow(m_symbol, m_tf, i+j) <= low) {
                isSwingLow = false;
                break;
            }
        }

        if(isSwingLow && low < currentPrice) {
            double distance = currentPrice - low;
            if(distance < minDistance) {
                minDistance = distance;
                nearestSupport = low;
            }
        }
    }

    return nearestSupport;
}

//+------------------------------------------------------------------+
//| FIND NEAREST RESISTANCE                                           |
//+------------------------------------------------------------------+
double CEntryZones::FindNearestResistance() {
    double currentPrice = GetCurrentPrice();
    double nearestResistance = 0;
    double minDistance = DBL_MAX;

    for(int i = 5; i < 100; i++) {
        double high = iHigh(m_symbol, m_tf, i);
        bool isSwingHigh = true;

        for(int j = 1; j <= 3; j++) {
            if(iHigh(m_symbol, m_tf, i-j) >= high ||
               iHigh(m_symbol, m_tf, i+j) >= high) {
                isSwingHigh = false;
                break;
            }
        }

        if(isSwingHigh && high > currentPrice) {
            double distance = high - currentPrice;
            if(distance < minDistance) {
                minDistance = distance;
                nearestResistance = high;
            }
        }
    }

    return nearestResistance;
}

//+------------------------------------------------------------------+
//| IS NEAR SUPPORT                                                   |
//+------------------------------------------------------------------+
bool CEntryZones::IsNearSupport(double tolerance) {
    double support = FindNearestSupport();
    if(support == 0) return false;

    double currentPrice = GetCurrentPrice();
    double diff = MathAbs(currentPrice - support) / support;

    return diff <= tolerance;
}

//+------------------------------------------------------------------+
//| IS NEAR RESISTANCE                                                |
//+------------------------------------------------------------------+
bool CEntryZones::IsNearResistance(double tolerance) {
    double resistance = FindNearestResistance();
    if(resistance == 0) return false;

    double currentPrice = GetCurrentPrice();
    double diff = MathAbs(currentPrice - resistance) / resistance;

    return diff <= tolerance;
}

//+------------------------------------------------------------------+
//| GET CURRENT PRICE                                                 |
//+------------------------------------------------------------------+
double CEntryZones::GetCurrentPrice() {
    return iClose(m_symbol, m_tf, 0);
}

//+------------------------------------------------------------------+
//| GET ATR                                                           |
//+------------------------------------------------------------------+
double CEntryZones::GetATR() {
    double atr[];
    ArraySetAsSeries(atr, true);
    CopyBuffer(h_ATR, 0, 0, 1, atr);
    return atr[0];
}

//+------------------------------------------------------------------+
//| Getters for Swing Points                                          |
//+------------------------------------------------------------------+
SwingPoint CEntryZones::GetLastSwingHigh() {
    UpdateSwingPoints();
    return m_lastSwingHigh;
}

SwingPoint CEntryZones::GetLastSwingLow() {
    UpdateSwingPoints();
    return m_lastSwingLow;
}
//+------------------------------------------------------------------+

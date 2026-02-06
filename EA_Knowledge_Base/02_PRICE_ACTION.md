# Price Action - Techniques Professionnelles pour EA MQL5

## PRINCIPES FONDAMENTAUX

### 1. Structure de Marche (Market Structure)
```
TENDANCE HAUSSIERE:
- Higher Highs (HH) + Higher Lows (HL)
- Chaque sommet depasse le precedent
- Chaque creux reste au-dessus du precedent

TENDANCE BAISSIERE:
- Lower Highs (LH) + Lower Lows (LL)
- Chaque sommet reste sous le precedent
- Chaque creux descend plus bas

RANGE/CONSOLIDATION:
- Pas de HH/HL ou LH/LL clairs
- Prix oscille entre support et resistance
```

### 2. Break of Structure (BOS)
```cpp
// Detection du Break of Structure
enum MARKET_STRUCTURE { MS_BULLISH, MS_BEARISH, MS_RANGING };

MARKET_STRUCTURE DetectStructure(int lookback = 50) {
    double lastHigh = 0, prevHigh = 0;
    double lastLow = DBL_MAX, prevLow = DBL_MAX;

    // Trouver les 2 derniers swing highs/lows
    int highCount = 0, lowCount = 0;

    for(int i = 5; i < lookback && (highCount < 2 || lowCount < 2); i++) {
        if(IsSwingHigh(i, 5)) {
            if(highCount == 0) lastHigh = iHigh(_Symbol, PERIOD_CURRENT, i);
            else prevHigh = iHigh(_Symbol, PERIOD_CURRENT, i);
            highCount++;
        }
        if(IsSwingLow(i, 5)) {
            if(lowCount == 0) lastLow = iLow(_Symbol, PERIOD_CURRENT, i);
            else prevLow = iLow(_Symbol, PERIOD_CURRENT, i);
            lowCount++;
        }
    }

    if(lastHigh > prevHigh && lastLow > prevLow) return MS_BULLISH;
    if(lastHigh < prevHigh && lastLow < prevLow) return MS_BEARISH;
    return MS_RANGING;
}
```

---

## CANDLESTICK PATTERNS ESSENTIELS

### A. PATTERNS DE REVERSAL (Single Candle)

#### 1. HAMMER / HANGING MAN
```
Structure:
- Petit corps en haut
- Longue meche inferieure (2-3x le corps)
- Peu ou pas de meche superieure

Hammer (Bullish): Apres tendance baissiere
Hanging Man (Bearish): Apres tendance haussiere
```

```cpp
bool IsHammer(int shift) {
    double open = iOpen(_Symbol, PERIOD_CURRENT, shift);
    double close = iClose(_Symbol, PERIOD_CURRENT, shift);
    double high = iHigh(_Symbol, PERIOD_CURRENT, shift);
    double low = iLow(_Symbol, PERIOD_CURRENT, shift);

    double body = MathAbs(close - open);
    double upperWick = high - MathMax(open, close);
    double lowerWick = MathMin(open, close) - low;

    // Corps petit, longue meche inferieure
    return (lowerWick >= body * 2) && (upperWick <= body * 0.5);
}
```

#### 2. INVERTED HAMMER / SHOOTING STAR
```
Structure:
- Petit corps en bas
- Longue meche superieure (2-3x le corps)
- Peu ou pas de meche inferieure

Inverted Hammer (Bullish): Apres tendance baissiere
Shooting Star (Bearish): Apres tendance haussiere
```

#### 3. DOJI
```
Types:
- Standard Doji: open ≈ close
- Dragonfly Doji: longue meche inferieure (bullish)
- Gravestone Doji: longue meche superieure (bearish)
- Long-legged Doji: longues meches des deux cotes (indecision)
```

```cpp
bool IsDoji(int shift, double tolerance = 0.1) {
    double open = iOpen(_Symbol, PERIOD_CURRENT, shift);
    double close = iClose(_Symbol, PERIOD_CURRENT, shift);
    double high = iHigh(_Symbol, PERIOD_CURRENT, shift);
    double low = iLow(_Symbol, PERIOD_CURRENT, shift);

    double body = MathAbs(close - open);
    double range = high - low;

    return (body <= range * tolerance);  // Corps < 10% du range
}
```

### B. PATTERNS DE REVERSAL (Multi-Candle)

#### 4. ENGULFING PATTERN
```
Bullish Engulfing:
- 1ere bougie: baissiere
- 2eme bougie: haussiere, corps englobe completement le corps de la 1ere

Bearish Engulfing:
- 1ere bougie: haussiere
- 2eme bougie: baissiere, corps englobe completement
```

```cpp
bool IsBullishEngulfing(int shift) {
    // Bougie actuelle (shift) et precedente (shift+1)
    double open1 = iOpen(_Symbol, PERIOD_CURRENT, shift + 1);
    double close1 = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
    double open2 = iOpen(_Symbol, PERIOD_CURRENT, shift);
    double close2 = iClose(_Symbol, PERIOD_CURRENT, shift);

    // 1ere baissiere, 2eme haussiere
    bool firstBearish = close1 < open1;
    bool secondBullish = close2 > open2;

    // Engulfing: corps 2 englobe corps 1
    bool engulfs = (open2 <= close1) && (close2 >= open1);

    return firstBearish && secondBullish && engulfs;
}

bool IsBearishEngulfing(int shift) {
    double open1 = iOpen(_Symbol, PERIOD_CURRENT, shift + 1);
    double close1 = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
    double open2 = iOpen(_Symbol, PERIOD_CURRENT, shift);
    double close2 = iClose(_Symbol, PERIOD_CURRENT, shift);

    bool firstBullish = close1 > open1;
    bool secondBearish = close2 < open2;
    bool engulfs = (open2 >= close1) && (close2 <= open1);

    return firstBullish && secondBearish && engulfs;
}
```

#### 5. MORNING STAR / EVENING STAR
```
Morning Star (Bullish - 3 bougies):
1. Grande bougie baissiere
2. Petite bougie (doji ou spinning top) avec gap down
3. Grande bougie haussiere qui remonte dans le corps de la 1ere

Evening Star (Bearish - 3 bougies):
1. Grande bougie haussiere
2. Petite bougie avec gap up
3. Grande bougie baissiere
```

#### 6. THREE WHITE SOLDIERS / THREE BLACK CROWS
```
Three White Soldiers (Bullish):
- 3 bougies haussières consecutives
- Chaque cloture > cloture precedente
- Petites meches

Three Black Crows (Bearish):
- 3 bougies baissieres consecutives
- Chaque cloture < cloture precedente
```

### C. PATTERNS DE CONTINUATION

#### 7. INSIDE BAR
```
Structure:
- La bougie actuelle est completement contenue dans la bougie precedente
- High actuel < High precedent
- Low actuel > Low precedent

Usage:
- Breakout dans la direction de la tendance
- Entry au breakout du high (bullish) ou low (bearish) de la mother bar
```

```cpp
bool IsInsideBar(int shift) {
    double high1 = iHigh(_Symbol, PERIOD_CURRENT, shift + 1);  // Mother bar
    double low1 = iLow(_Symbol, PERIOD_CURRENT, shift + 1);
    double high2 = iHigh(_Symbol, PERIOD_CURRENT, shift);      // Inside bar
    double low2 = iLow(_Symbol, PERIOD_CURRENT, shift);

    return (high2 < high1) && (low2 > low1);
}
```

#### 8. PIN BAR (PINOCCHIO BAR)
```
Structure:
- Longue meche (nose) dans la direction opposee au trade
- Petit corps a l'extremite opposee
- Rejection claire d'un niveau

Bullish Pin Bar: Longue meche inferieure, corps en haut
Bearish Pin Bar: Longue meche superieure, corps en bas
```

```cpp
bool IsBullishPinBar(int shift, double ratio = 2.0) {
    double open = iOpen(_Symbol, PERIOD_CURRENT, shift);
    double close = iClose(_Symbol, PERIOD_CURRENT, shift);
    double high = iHigh(_Symbol, PERIOD_CURRENT, shift);
    double low = iLow(_Symbol, PERIOD_CURRENT, shift);

    double body = MathAbs(close - open);
    double lowerWick = MathMin(open, close) - low;
    double upperWick = high - MathMax(open, close);
    double totalRange = high - low;

    // Longue meche inferieure, petit corps en haut
    return (lowerWick >= body * ratio) &&
           (upperWick <= totalRange * 0.25) &&
           (body <= totalRange * 0.35);
}
```

---

## ZONES DE PRIX CRITIQUES

### 1. Support et Resistance
```cpp
// Structure pour stocker les niveaux S/R
struct PriceLevel {
    double price;
    int touches;
    datetime firstTouch;
    datetime lastTouch;
    bool isBroken;
};

// Identifier les niveaux de support/resistance
void FindSupportResistance(PriceLevel &levels[], int lookback = 200, double tolerance = 0.001) {
    double prices[];
    ArrayResize(prices, lookback);

    // Collecter tous les swing points
    for(int i = 5; i < lookback - 5; i++) {
        if(IsSwingHigh(i, 5)) {
            // Ajouter comme niveau potentiel
            AddOrUpdateLevel(levels, iHigh(_Symbol, PERIOD_CURRENT, i), tolerance);
        }
        if(IsSwingLow(i, 5)) {
            AddOrUpdateLevel(levels, iLow(_Symbol, PERIOD_CURRENT, i), tolerance);
        }
    }

    // Trier par nombre de touches (plus fort = plus de touches)
    SortLevelsByStrength(levels);
}
```

### 2. Supply and Demand Zones
```
DEMAND ZONE (Zone d'achat):
- Zone ou les acheteurs ont domine
- Prix a fortement rebondi depuis cette zone
- Base: derniere bougie avant mouvement impulsif haussier

SUPPLY ZONE (Zone de vente):
- Zone ou les vendeurs ont domine
- Prix a fortement chute depuis cette zone
- Base: derniere bougie avant mouvement impulsif baissier
```

```cpp
struct SupplyDemandZone {
    double upperBound;
    double lowerBound;
    datetime formation;
    bool isDemand;  // true = demand, false = supply
    bool isFresh;   // jamais retestee
};

SupplyDemandZone FindLastDemandZone(int lookback = 100) {
    SupplyDemandZone zone;

    for(int i = 10; i < lookback; i++) {
        // Chercher mouvement impulsif haussier
        double move = iClose(_Symbol, PERIOD_CURRENT, i-5) - iClose(_Symbol, PERIOD_CURRENT, i);
        double atr = iATR(_Symbol, PERIOD_CURRENT, 14);

        if(move > atr * 2) {  // Mouvement > 2 ATR
            // La zone est la derniere bougie avant le mouvement
            zone.upperBound = iHigh(_Symbol, PERIOD_CURRENT, i);
            zone.lowerBound = iLow(_Symbol, PERIOD_CURRENT, i);
            zone.formation = iTime(_Symbol, PERIOD_CURRENT, i);
            zone.isDemand = true;
            zone.isFresh = !HasPriceRetested(zone.lowerBound, zone.upperBound, i);
            return zone;
        }
    }

    return zone;
}
```

### 3. Fair Value Gaps (FVG) / Imbalances
```
FVG BULLISH:
- Gap entre le high de bougie 1 et le low de bougie 3
- La bougie 2 ne couvre pas ce gap
- Zone de desequilibre que le prix tend a combler

FVG BEARISH:
- Gap entre le low de bougie 1 et le high de bougie 3
```

```cpp
struct FairValueGap {
    double upperBound;
    double lowerBound;
    datetime formation;
    bool isBullish;
    bool isFilled;
};

bool FindBullishFVG(int shift, FairValueGap &fvg) {
    double high1 = iHigh(_Symbol, PERIOD_CURRENT, shift + 2);
    double low3 = iLow(_Symbol, PERIOD_CURRENT, shift);

    if(low3 > high1) {
        fvg.upperBound = low3;
        fvg.lowerBound = high1;
        fvg.formation = iTime(_Symbol, PERIOD_CURRENT, shift + 1);
        fvg.isBullish = true;
        fvg.isFilled = false;
        return true;
    }
    return false;
}
```

---

## CONFLUENCES ET CONFIRMATIONS

### Multi-Timeframe Analysis
```
Regle des 3 Timeframes:
1. HIGHER TF (ex: H4): Direction de la tendance principale
2. MIDDLE TF (ex: H1): Zone d'entree / Structure
3. LOWER TF (ex: M15): Trigger d'entree precis

Alignement = Higher Probability Trade
```

```cpp
MARKET_STRUCTURE GetHTFTrend() {
    return DetectStructure(PERIOD_H4, 50);
}

bool IsAlignedWithHTF(ENUM_ORDER_TYPE direction) {
    MARKET_STRUCTURE htfTrend = GetHTFTrend();

    if(direction == ORDER_TYPE_BUY && htfTrend == MS_BULLISH) return true;
    if(direction == ORDER_TYPE_SELL && htfTrend == MS_BEARISH) return true;

    return false;
}
```

### Score de Confluence
```cpp
int CalculateConfluenceScore(ENUM_ORDER_TYPE direction, int shift) {
    int score = 0;

    // +2: Alignement HTF
    if(IsAlignedWithHTF(direction)) score += 2;

    // +2: Pattern candlestick
    if(direction == ORDER_TYPE_BUY && IsBullishEngulfing(shift)) score += 2;
    if(direction == ORDER_TYPE_SELL && IsBearishEngulfing(shift)) score += 2;

    // +1: Niveau S/R
    if(IsNearSupportResistance(iClose(_Symbol, PERIOD_CURRENT, shift))) score += 1;

    // +1: FVG
    FairValueGap fvg;
    if(FindBullishFVG(shift, fvg) && direction == ORDER_TYPE_BUY) score += 1;

    // +1: Volume superieur a la moyenne
    if(iVolume(_Symbol, PERIOD_CURRENT, shift) > GetAverageVolume(20)) score += 1;

    return score;
}

// Trade si score >= 4
bool ShouldTrade(ENUM_ORDER_TYPE direction, int shift) {
    return CalculateConfluenceScore(direction, shift) >= 4;
}
```

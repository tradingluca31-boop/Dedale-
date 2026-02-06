# Chart Patterns - Base de Connaissances EA MQL5

## PATTERNS DE CONTINUATION

### 1. ASCENDING TRIANGLE (Bullish)
```
Structure:
- Resistance horizontale (ligne plate en haut)
- Support ascendant (higher lows)
- Volume decroissant pendant formation

Detection MQL5:
- Identifier 2+ touches sur resistance
- Identifier 3+ higher lows
- Breakout = cloture au-dessus resistance + volume

Entry: Breakout confirme au-dessus resistance
TP: Hauteur du triangle projetee depuis breakout
SL: Sous le dernier higher low
```

### 2. DESCENDING TRIANGLE (Bearish)
```
Structure:
- Support horizontal (ligne plate en bas)
- Resistance descendante (lower highs)
- Volume decroissant pendant formation

Detection MQL5:
- Identifier 2+ touches sur support
- Identifier 3+ lower highs
- Breakdown = cloture sous support + volume

Entry: Breakdown confirme sous support
TP: Hauteur du triangle projetee depuis breakdown
SL: Au-dessus du dernier lower high
```

### 3. BULLISH WEDGE (Continuation haussiere)
```
Structure:
- Deux lignes convergentes descendantes
- Dans une tendance haussiere
- Compression du prix

Detection MQL5:
- Pente negative des deux lignes
- Lower highs ET lower lows mais angle plus plat sur lows
- Volume decroissant

Entry: Breakout haussier de la ligne superieure
TP: Hauteur du wedge ou debut du wedge
SL: Sous la ligne inferieure du wedge
```

### 4. BEARISH WEDGE (Continuation baissiere)
```
Structure:
- Deux lignes convergentes ascendantes
- Dans une tendance baissiere
- Compression du prix

Entry: Breakdown sous la ligne inferieure
TP: Hauteur du wedge projetee
SL: Au-dessus de la ligne superieure
```

### 5. BULLISH FLAG
```
Structure:
- Mat (pole): mouvement impulsif fort haussier
- Drapeau: canal descendant de consolidation
- Ratio ideal: drapeau = 1/3 a 1/2 du mat

Detection MQL5:
- Detecter mouvement impulsif (>2 ATR en peu de bougies)
- Canal de consolidation avec lower highs/lower lows
- Volume faible pendant consolidation

Entry: Breakout au-dessus du canal
TP: Hauteur du mat projetee depuis breakout
SL: Sous le bas du drapeau
```

### 6. BEARISH FLAG
```
Structure:
- Mat (pole): mouvement impulsif fort baissier
- Drapeau: canal ascendant de consolidation

Entry: Breakdown sous le canal
TP: Hauteur du mat projetee
SL: Au-dessus du haut du drapeau
```

### 7. BULLISH SYMMETRICAL TRIANGLE
```
Structure:
- Lignes convergentes symetriques
- Lower highs ET higher lows
- Breakout dans direction de tendance precedente

Entry: Breakout haussier avec confirmation
TP: Hauteur du triangle
SL: Milieu ou bas du triangle
```

### 8. BEARISH SYMMETRICAL TRIANGLE
```
Structure:
- Meme que bullish mais breakout baissier
- Tendance precedente baissiere

Entry: Breakdown confirme
TP: Hauteur du triangle
SL: Milieu ou haut du triangle
```

---

## PATTERNS DE REVERSAL

### 9. DOUBLE BOTTOM (Bullish Reversal)
```
Structure:
- Deux creux au meme niveau (tolerance 1-3%)
- Neckline = resistance horizontale au sommet entre les deux creux
- Pattern en "W"

Detection MQL5:
- Identifier premier low
- Rebond vers neckline
- Retour vers premier low (+-3%)
- Volume plus faible sur 2eme bottom

Entry: Breakout au-dessus de la neckline
TP: Distance bottom-neckline projetee
SL: Sous le 2eme bottom
Risk/Reward: Minimum 1:2
```

### 10. DOUBLE TOP (Bearish Reversal)
```
Structure:
- Deux sommets au meme niveau
- Neckline = support horizontal
- Pattern en "M"

Entry: Breakdown sous la neckline
TP: Distance top-neckline projetee
SL: Au-dessus du 2eme top
```

### 11. TRIPLE BOTTOM (Bullish Reversal)
```
Structure:
- Trois creux au meme niveau
- Plus fiable que double bottom
- Confirmation = breakout neckline

Entry: Breakout neckline avec volume
TP: Distance bottom-neckline
SL: Sous le 3eme bottom
```

### 12. TRIPLE TOP (Bearish Reversal)
```
Structure:
- Trois sommets au meme niveau
- Forte resistance confirmee

Entry: Breakdown neckline
TP: Distance top-neckline
SL: Au-dessus du 3eme top
```

### 13. INVERTED HEAD & SHOULDERS (Bullish Reversal)
```
Structure:
- Left Shoulder: premier creux
- Head: creux plus profond (le plus bas)
- Right Shoulder: creux similaire au left shoulder
- Neckline: ligne reliant les sommets entre creux

Detection MQL5:
- Head doit etre le point le plus bas
- Shoulders approximativement au meme niveau
- Neckline peut etre inclinee

Entry: Breakout au-dessus de la neckline
TP: Distance head-neckline projetee depuis breakout
SL: Sous le right shoulder
Confirmation: Volume croissant sur breakout
```

### 14. HEAD & SHOULDERS (Bearish Reversal)
```
Structure:
- Left Shoulder: premier sommet
- Head: sommet le plus haut
- Right Shoulder: sommet similaire au left
- Neckline: ligne reliant les creux

Entry: Breakdown sous la neckline
TP: Distance head-neckline projetee
SL: Au-dessus du right shoulder
```

### 15. FALLING WEDGE (Bullish Reversal)
```
Structure:
- Deux lignes descendantes convergentes
- Apparait apres tendance baissiere
- Signale epuisement de la tendance

Detection MQL5:
- Both trendlines pointing down
- Lower highs AND lower lows
- Convergence des lignes

Entry: Breakout haussier
TP: Hauteur du wedge ou retracement 61.8%
SL: Sous le dernier low du wedge
```

### 16. RISING WEDGE (Bearish Reversal)
```
Structure:
- Deux lignes ascendantes convergentes
- Apparait apres tendance haussiere
- Signale epuisement

Entry: Breakdown baissier
TP: Hauteur du wedge
SL: Au-dessus du dernier high
```

---

## REGLES DE DETECTION MQL5

### Fonction de Detection des Pivots
```cpp
// Detecter Swing High
bool IsSwingHigh(int shift, int lookback = 5) {
    double high = iHigh(_Symbol, PERIOD_CURRENT, shift);
    for(int i = 1; i <= lookback; i++) {
        if(iHigh(_Symbol, PERIOD_CURRENT, shift - i) >= high) return false;
        if(iHigh(_Symbol, PERIOD_CURRENT, shift + i) >= high) return false;
    }
    return true;
}

// Detecter Swing Low
bool IsSwingLow(int shift, int lookback = 5) {
    double low = iLow(_Symbol, PERIOD_CURRENT, shift);
    for(int i = 1; i <= lookback; i++) {
        if(iLow(_Symbol, PERIOD_CURRENT, shift - i) <= low) return false;
        if(iLow(_Symbol, PERIOD_CURRENT, shift + i) <= low) return false;
    }
    return true;
}
```

### Tolerance et Confirmation
```cpp
// Tolerance pour double/triple patterns (en %)
#define PATTERN_TOLERANCE 0.03  // 3%

// Verification niveau similaire
bool IsSameLevel(double price1, double price2, double tolerance = PATTERN_TOLERANCE) {
    return MathAbs(price1 - price2) / price1 <= tolerance;
}

// Confirmation breakout
bool IsBreakoutConfirmed(double breakoutLevel, ENUM_ORDER_TYPE direction) {
    double close = iClose(_Symbol, PERIOD_CURRENT, 1);
    double atr = iATR(_Symbol, PERIOD_CURRENT, 14);

    if(direction == ORDER_TYPE_BUY) {
        return close > breakoutLevel + (atr * 0.1);  // 10% ATR au-dessus
    } else {
        return close < breakoutLevel - (atr * 0.1);
    }
}
```

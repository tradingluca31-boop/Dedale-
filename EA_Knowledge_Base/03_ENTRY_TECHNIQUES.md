# Techniques d'Entree en Position - EA MQL5

## TYPES D'ENTREES

### 1. BREAKOUT ENTRY
```
Principe: Entrer quand le prix casse un niveau cle

Avantages:
- Capture les mouvements forts
- Entry claire et objective

Inconvenients:
- Faux breakouts frequents
- SL souvent plus large

Confirmation:
- Volume superieur a la moyenne
- Cloture au-dela du niveau (pas juste meche)
- Retest optionnel du niveau casse
```

```cpp
struct BreakoutSignal {
    double breakoutLevel;
    ENUM_ORDER_TYPE direction;
    datetime breakoutTime;
    bool confirmed;
};

bool DetectBreakout(double level, ENUM_ORDER_TYPE direction, int lookback = 5) {
    double close = iClose(_Symbol, PERIOD_CURRENT, 1);
    double prevClose = iClose(_Symbol, PERIOD_CURRENT, 2);
    double atr = iATR(_Symbol, PERIOD_CURRENT, 14);

    if(direction == ORDER_TYPE_BUY) {
        // Prix etait sous le niveau, maintenant au-dessus
        bool wasBellow = true;
        for(int i = 2; i < lookback + 2; i++) {
            if(iClose(_Symbol, PERIOD_CURRENT, i) > level) {
                wasBellow = false;
                break;
            }
        }
        // Breakout confirme: cloture > niveau + filtre ATR
        return wasBellow && (close > level + atr * 0.1);
    }
    else {
        bool wasAbove = true;
        for(int i = 2; i < lookback + 2; i++) {
            if(iClose(_Symbol, PERIOD_CURRENT, i) < level) {
                wasAbove = false;
                break;
            }
        }
        return wasAbove && (close < level - atr * 0.1);
    }
}
```

### 2. PULLBACK/RETEST ENTRY
```
Principe: Attendre que le prix revienne tester un niveau apres breakout

Avantages:
- Meilleur Risk/Reward
- Confirmation du breakout
- SL plus serre

Inconvenients:
- Peut rater des trades si pas de pullback
- Requiert patience

Ideal pour:
- Swing trading
- Continuation de tendance
```

```cpp
enum RETEST_STATUS { NO_RETEST, RETEST_IN_PROGRESS, RETEST_COMPLETE };

RETEST_STATUS CheckRetest(double breakoutLevel, ENUM_ORDER_TYPE direction, int maxBars = 20) {
    bool breakoutHappened = false;
    bool retestHappened = false;

    for(int i = 1; i < maxBars; i++) {
        double close = iClose(_Symbol, PERIOD_CURRENT, i);
        double low = iLow(_Symbol, PERIOD_CURRENT, i);
        double high = iHigh(_Symbol, PERIOD_CURRENT, i);

        if(direction == ORDER_TYPE_BUY) {
            // Chercher breakout au-dessus
            if(close > breakoutLevel) breakoutHappened = true;

            // Apres breakout, chercher retest (prix touche le niveau par le haut)
            if(breakoutHappened && low <= breakoutLevel * 1.002) {  // 0.2% tolerance
                retestHappened = true;
            }

            // Retest complete: prix a touche et rebondi
            if(retestHappened && close > breakoutLevel) {
                return RETEST_COMPLETE;
            }
        }
        else {
            if(close < breakoutLevel) breakoutHappened = true;
            if(breakoutHappened && high >= breakoutLevel * 0.998) {
                retestHappened = true;
            }
            if(retestHappened && close < breakoutLevel) {
                return RETEST_COMPLETE;
            }
        }
    }

    if(retestHappened) return RETEST_IN_PROGRESS;
    return NO_RETEST;
}
```

### 3. REVERSAL ENTRY (Counter-Trend)
```
Principe: Entrer contre la tendance a des niveaux cles

TRES RISQUE - Requiert:
- Niveau S/R majeur (multiple touches)
- Pattern de reversal confirme
- Divergence RSI/MACD
- Volume anormal

SL: Toujours serre, au-dela du niveau
TP: Premier niveau S/R oppose
```

```cpp
bool IsReversalSetup(ENUM_ORDER_TYPE direction) {
    int score = 0;

    // 1. Niveau S/R fort
    if(IsAtStrongSRLevel()) score += 2;

    // 2. Pattern candlestick de reversal
    if(direction == ORDER_TYPE_BUY) {
        if(IsHammer(1) || IsBullishEngulfing(1) || IsMorningStar()) score += 2;
    } else {
        if(IsShootingStar(1) || IsBearishEngulfing(1) || IsEveningStar()) score += 2;
    }

    // 3. Divergence
    if(HasDivergence(direction)) score += 2;

    // 4. Volume spike
    if(iVolume(_Symbol, PERIOD_CURRENT, 1) > GetAverageVolume(20) * 1.5) score += 1;

    return score >= 5;  // Minimum 5/7 pour reversal
}
```

### 4. ZONE ENTRY (Supply/Demand)
```
Principe: Entrer quand le prix entre dans une zone de supply/demand

Etapes:
1. Identifier la zone (voir Price Action)
2. Attendre que le prix entre dans la zone
3. Chercher confirmation sur LTF
4. Entrer avec SL au-dela de la zone
```

```cpp
bool IsPriceInZone(SupplyDemandZone &zone) {
    double close = iClose(_Symbol, PERIOD_CURRENT, 0);
    return (close >= zone.lowerBound && close <= zone.upperBound);
}

bool GetZoneEntrySignal(SupplyDemandZone &zone, ENUM_ORDER_TYPE &direction) {
    if(!zone.isFresh) return false;  // Zone deja testee

    if(IsPriceInZone(zone)) {
        if(zone.isDemand) {
            // Chercher confirmation bullish sur LTF
            if(IsBullishEngulfing(1) || IsHammer(1)) {
                direction = ORDER_TYPE_BUY;
                return true;
            }
        } else {
            if(IsBearishEngulfing(1) || IsShootingStar(1)) {
                direction = ORDER_TYPE_SELL;
                return true;
            }
        }
    }
    return false;
}
```

---

## TECHNIQUES DE CONFIRMATION

### 1. CONFIRMATION PAR VOLUME
```cpp
bool IsVolumeConfirmed(int shift = 1, double multiplier = 1.2) {
    long currentVol = iVolume(_Symbol, PERIOD_CURRENT, shift);
    long avgVol = GetAverageVolume(20);

    return currentVol > avgVol * multiplier;
}

long GetAverageVolume(int period) {
    long sum = 0;
    for(int i = 1; i <= period; i++) {
        sum += iVolume(_Symbol, PERIOD_CURRENT, i);
    }
    return sum / period;
}
```

### 2. CONFIRMATION PAR MOMENTUM
```cpp
bool IsMomentumConfirmed(ENUM_ORDER_TYPE direction) {
    // RSI
    double rsi = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);

    // MACD
    double macdMain[], macdSignal[];
    ArraySetAsSeries(macdMain, true);
    ArraySetAsSeries(macdSignal, true);
    int macdHandle = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
    CopyBuffer(macdHandle, 0, 0, 3, macdMain);
    CopyBuffer(macdHandle, 1, 0, 3, macdSignal);

    if(direction == ORDER_TYPE_BUY) {
        return (rsi > 50 && rsi < 70) && (macdMain[0] > macdSignal[0]);
    } else {
        return (rsi < 50 && rsi > 30) && (macdMain[0] < macdSignal[0]);
    }
}
```

### 3. CONFIRMATION MULTI-TIMEFRAME
```cpp
bool IsHTFAligned(ENUM_ORDER_TYPE direction) {
    // Verifier tendance sur H4
    ENUM_TIMEFRAMES htf = PERIOD_H4;

    double ema50 = iMA(_Symbol, htf, 50, 0, MODE_EMA, PRICE_CLOSE);
    double ema200 = iMA(_Symbol, htf, 200, 0, MODE_EMA, PRICE_CLOSE);
    double close = iClose(_Symbol, htf, 0);

    if(direction == ORDER_TYPE_BUY) {
        return (close > ema50) && (ema50 > ema200);  // Tendance haussiere
    } else {
        return (close < ema50) && (ema50 < ema200);  // Tendance baissiere
    }
}
```

---

## TIMING D'ENTREE

### 1. SESSIONS DE TRADING (GOLD/FOREX)
```cpp
enum TRADING_SESSION { SESSION_ASIAN, SESSION_LONDON, SESSION_NEW_YORK, SESSION_OVERLAP };

TRADING_SESSION GetCurrentSession() {
    MqlDateTime dt;
    TimeToStruct(TimeGMT(), dt);
    int hour = dt.hour;

    if(hour >= 0 && hour < 7) return SESSION_ASIAN;       // 00:00 - 07:00 GMT
    if(hour >= 7 && hour < 13) return SESSION_LONDON;     // 07:00 - 13:00 GMT
    if(hour >= 13 && hour < 17) return SESSION_OVERLAP;   // 13:00 - 17:00 GMT (London + NY)
    if(hour >= 17 && hour < 22) return SESSION_NEW_YORK;  // 17:00 - 22:00 GMT

    return SESSION_ASIAN;
}

bool IsBestTimeToTrade() {
    TRADING_SESSION session = GetCurrentSession();
    // Meilleur: London et Overlap pour GOLD
    return (session == SESSION_LONDON || session == SESSION_OVERLAP);
}
```

### 2. EVITER LES NEWS
```cpp
// Structure pour stocker les news
struct NewsEvent {
    datetime time;
    string currency;
    int impact;  // 1=low, 2=medium, 3=high
};

bool IsNearHighImpactNews(int minutesBefore = 30, int minutesAfter = 15) {
    // Implementer avec calendrier economique
    // Ne pas trader 30min avant et 15min apres news high impact

    // Placeholder - a implementer avec API news
    return false;
}
```

---

## ENTRY TRIGGERS COMBINES

### Score d'Entree Final
```cpp
struct EntrySignal {
    ENUM_ORDER_TYPE direction;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    int score;
    string reason;
};

EntrySignal EvaluateEntry() {
    EntrySignal signal;
    signal.score = 0;
    signal.reason = "";

    // Determiner direction potentielle
    MARKET_STRUCTURE structure = DetectStructure();

    if(structure == MS_BULLISH) {
        signal.direction = ORDER_TYPE_BUY;

        // +2: Tendance HTF alignee
        if(IsHTFAligned(ORDER_TYPE_BUY)) {
            signal.score += 2;
            signal.reason += "HTF_ALIGNED|";
        }

        // +2: Pattern candlestick
        if(IsBullishEngulfing(1) || IsHammer(1) || IsBullishPinBar(1)) {
            signal.score += 2;
            signal.reason += "CANDLE_PATTERN|";
        }

        // +1: Volume
        if(IsVolumeConfirmed()) {
            signal.score += 1;
            signal.reason += "VOLUME|";
        }

        // +1: Momentum
        if(IsMomentumConfirmed(ORDER_TYPE_BUY)) {
            signal.score += 1;
            signal.reason += "MOMENTUM|";
        }

        // +1: Bonne session
        if(IsBestTimeToTrade()) {
            signal.score += 1;
            signal.reason += "SESSION|";
        }

        // +1: Niveau S/R
        if(IsNearSupport()) {
            signal.score += 1;
            signal.reason += "SUPPORT|";
        }
    }
    else if(structure == MS_BEARISH) {
        signal.direction = ORDER_TYPE_SELL;
        // Meme logique inverse...
    }

    return signal;
}

// Seuil minimum pour trader
#define MIN_ENTRY_SCORE 5

bool ShouldEnterTrade(EntrySignal &signal) {
    return signal.score >= MIN_ENTRY_SCORE && !IsNearHighImpactNews();
}
```

---

## PLACEMENT DU STOP LOSS

### 1. ATR-Based Stop Loss
```cpp
double CalculateATRStopLoss(ENUM_ORDER_TYPE direction, double multiplier = 1.5) {
    double atr = iATR(_Symbol, PERIOD_CURRENT, 14);
    double close = iClose(_Symbol, PERIOD_CURRENT, 0);

    if(direction == ORDER_TYPE_BUY) {
        return close - (atr * multiplier);
    } else {
        return close + (atr * multiplier);
    }
}
```

### 2. Structure-Based Stop Loss
```cpp
double CalculateStructureStopLoss(ENUM_ORDER_TYPE direction) {
    double buffer = iATR(_Symbol, PERIOD_CURRENT, 14) * 0.2;  // 20% ATR buffer

    if(direction == ORDER_TYPE_BUY) {
        // SL sous le dernier swing low
        double lastLow = FindLastSwingLow(20);
        return lastLow - buffer;
    } else {
        // SL au-dessus du dernier swing high
        double lastHigh = FindLastSwingHigh(20);
        return lastHigh + buffer;
    }
}
```

### 3. Zone-Based Stop Loss
```cpp
double CalculateZoneStopLoss(SupplyDemandZone &zone, ENUM_ORDER_TYPE direction) {
    double buffer = iATR(_Symbol, PERIOD_CURRENT, 14) * 0.3;

    if(direction == ORDER_TYPE_BUY && zone.isDemand) {
        return zone.lowerBound - buffer;  // Sous la zone de demand
    } else if(direction == ORDER_TYPE_SELL && !zone.isDemand) {
        return zone.upperBound + buffer;  // Au-dessus de la zone de supply
    }

    return 0;  // Invalid
}
```

---

## PLACEMENT DU TAKE PROFIT

### 1. Risk/Reward Ratio
```cpp
double CalculateRRTakeProfit(double entry, double stopLoss, double rrRatio = 2.0) {
    double risk = MathAbs(entry - stopLoss);
    double reward = risk * rrRatio;

    if(entry > stopLoss) {  // BUY
        return entry + reward;
    } else {  // SELL
        return entry - reward;
    }
}
```

### 2. Structure-Based Take Profit
```cpp
double CalculateStructureTakeProfit(ENUM_ORDER_TYPE direction) {
    if(direction == ORDER_TYPE_BUY) {
        // TP au prochain swing high / resistance
        return FindNextResistance();
    } else {
        // TP au prochain swing low / support
        return FindNextSupport();
    }
}
```

### 3. Partial Take Profit Strategy
```cpp
struct PartialTP {
    double level;
    double percentClose;
};

void SetPartialTPs(double entry, double stopLoss, PartialTP &tps[]) {
    double risk = MathAbs(entry - stopLoss);

    ArrayResize(tps, 3);

    // TP1: 1R - Fermer 50%
    tps[0].level = (entry > stopLoss) ? entry + risk : entry - risk;
    tps[0].percentClose = 50;

    // TP2: 2R - Fermer 30%
    tps[1].level = (entry > stopLoss) ? entry + risk * 2 : entry - risk * 2;
    tps[1].percentClose = 30;

    // TP3: 3R - Fermer 20% restant
    tps[2].level = (entry > stopLoss) ? entry + risk * 3 : entry - risk * 3;
    tps[2].percentClose = 20;
}
```

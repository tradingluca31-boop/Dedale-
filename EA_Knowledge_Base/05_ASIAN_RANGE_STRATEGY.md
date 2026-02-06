# Strategie Asian Range Breakout + Daily Trend

## CONCEPT DE LA STRATEGIE

```
TIMELINE JOURNALIERE:

00:00 GMT                07:00 GMT                    18:00 GMT
    |-------- ASIE --------|-------- LONDRES/NY --------|
    |   [BUILD RANGE]      |   [TRADE BREAKOUT]         |
    |   High/Low du range  |   Dans sens tendance D1    |
```

### Logique
1. **Session Asie (00:00-07:00 GMT)**: Le marche consolide, on identifie le HIGH et LOW
2. **Ouverture Londres**: Le volume arrive, le prix casse le range
3. **Filtre Tendance D1**: On trade UNIQUEMENT dans le sens de la tendance journaliere
4. **Entry**: Breakout confirme (cloture au-dela du range)
5. **SL**: De l'autre cote du range
6. **TP**: Taille du range x Risk/Reward ratio

---

## POURQUOI CA FONCTIONNE

### 1. Session Asie = Consolidation
- Moins de volume (marches EU/US fermes)
- Le prix forme un range naturel
- Ce range represente l'equilibre avant le mouvement

### 2. Londres = Breakout
- Afflux massif de volume (ouverture Europe)
- Les gros players entrent en position
- Le range est casse avec conviction

### 3. Filtre Tendance = Edge Statistique
- Trader AVEC la tendance augmente le winrate
- Evite les faux breakouts contre-tendance
- Meilleur Risk/Reward sur les trades gagnants

---

## SCHEMA DE LA STRATEGIE

```
                           TENDANCE D1 HAUSSIERE
                                    |
                                    v
Prix                            [FILTRE OK - BUY ONLY]
  ^
  |                                    ___________
  |                         TP ->    /
  |                                 /
  |     ASIA HIGH -------- + -----X  <- ENTRY (breakout)
  |                        |  R   |
  |         RANGE          |  A   |
  |         ASIA           |  N   |
  |                        |  G   |
  |     ASIA LOW  -------- + -----|
  |                               |
  |                        SL ->  X
  |
  +-------------------------------------------------> Temps
       00:00    07:00      BREAKOUT
        GMT      GMT
```

```
                           TENDANCE D1 BAISSIERE
                                    |
                                    v
Prix                            [FILTRE OK - SELL ONLY]
  ^
  |                        SL ->  X
  |                               |
  |     ASIA HIGH -------- + -----|
  |                        |  R   |
  |         RANGE          |  A   |
  |         ASIA           |  N   |
  |                        |  G   |
  |     ASIA LOW  -------- + -----X  <- ENTRY (breakout)
  |                                 \
  |                         TP ->    \___________
  |
  +-------------------------------------------------> Temps
```

---

## DETECTION DE LA TENDANCE D1

### Methode 1: Triple EMA
```cpp
// Tendance HAUSSIERE si:
EMA21 > EMA50 > EMA200
ET
Close > EMA21

// Tendance BAISSIERE si:
EMA21 < EMA50 < EMA200
ET
Close < EMA21
```

### Methode 2: Structure de Marche
```cpp
// HAUSSIERE: Higher Highs + Higher Lows
// BAISSIERE: Lower Highs + Lower Lows
```

### Combinaison (Recommandee)
- EMA alignees + Structure alignee = TRADE
- Divergence entre EMA et Structure = NO TRADE

---

## REGLES D'ENTRY

### Conditions pour BUY
1. Tendance D1 = HAUSSIERE
2. Range Asie valide (150-500 pips pour GOLD)
3. Prix cloture AU-DESSUS de Asia High + Buffer
4. Spread < 10% de l'ATR
5. Pas deja de position ouverte

### Conditions pour SELL
1. Tendance D1 = BAISSIERE
2. Range Asie valide
3. Prix cloture EN-DESSOUS de Asia Low - Buffer
4. Spread acceptable
5. Pas deja de position ouverte

### Pas de Trade si
- Tendance D1 = NEUTRE
- Range trop petit (< 150 pips) = pas de volatilite
- Range trop grand (> 500 pips) = deja eu mouvement
- Breakout contre la tendance

---

## GESTION DU TRADE

### Stop Loss
```
BUY:  SL = Asia Low - Buffer (20 pips)
SELL: SL = Asia High + Buffer (20 pips)
```

### Take Profit
```
TP = Entry + (Range Size x RiskReward)

Exemple:
- Range = 200 pips
- RiskReward = 2.0
- TP = Entry + 400 pips
```

### Partial Take Profit (Recommande)
```
A 1R de profit:
- Fermer 50% de la position
- Deplacer SL au Break Even

Laisser courir le reste jusqu'au TP final
```

---

## PARAMETRES OPTIMAUX GOLD

| Parametre | Valeur | Raison |
|-----------|--------|--------|
| Asia Start | 00:00 GMT | Debut session Asie |
| Asia End | 07:00 GMT | Ouverture Londres |
| Trade End | 18:00 GMT | Eviter session Asie suivante |
| Min Range | 150 pips | Filtrer les jours calmes |
| Max Range | 500 pips | Eviter les jours deja volatils |
| Buffer | 20 pips | Eviter faux breakouts |
| Risk | 1% | FTMO compliant |
| R:R | 2.0 | Minimum pour profitabilite |

---

## BACKTEST EXPECTATIONS

### Metriques Cibles
- **Winrate**: 45-55% (normal avec filtre tendance)
- **Profit Factor**: > 1.5
- **Trades/mois**: 8-15 (pas tous les jours)
- **Max DD**: < 10% (FTMO compliant)

### Jours Sans Trade
- Tendance D1 neutre
- Range Asie invalide
- Breakout contre tendance
- Weekend / Jours feries

---

## VARIATIONS DE LA STRATEGIE

### 1. Multi-Session
```cpp
// Ajouter NY Range pour 2eme opportunite
// 12:00-13:00 GMT = range pre-NY
// 13:00-17:00 GMT = trade breakout
```

### 2. Pullback Entry
```cpp
// Au lieu d'entrer sur breakout direct:
// 1. Attendre breakout
// 2. Attendre pullback vers le range
// 3. Entrer sur rejection du niveau
// Avantage: Meilleur prix, SL plus serre
```

### 3. Multiple Timeframe Confirmation
```cpp
// Tendance D1 pour direction
// H4 pour structure
// H1 pour timing entry
```

---

## CODE SNIPPET - DETECTION RANGE

```cpp
// Variables globales
double g_AsiaHigh = 0;
double g_AsiaLow = DBL_MAX;

void BuildAsianRange() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int hour = dt.hour;  // Ajuster pour GMT offset

    // Pendant session Asie
    if(hour >= 0 && hour < 7) {
        double high = iHigh(_Symbol, PERIOD_M15, 0);
        double low = iLow(_Symbol, PERIOD_M15, 0);

        if(high > g_AsiaHigh) g_AsiaHigh = high;
        if(low < g_AsiaLow) g_AsiaLow = low;
    }
}

bool IsBreakoutValid(int direction) {
    double close = iClose(_Symbol, PERIOD_M15, 1);
    double buffer = 20 * _Point;

    if(direction == 1) {  // Bullish
        return close > g_AsiaHigh + buffer;
    } else {  // Bearish
        return close < g_AsiaLow - buffer;
    }
}
```

---

## CHECKLIST QUOTIDIENNE

### Avant Ouverture Londres (06:45 GMT)
- [ ] Identifier High/Low session Asie
- [ ] Verifier tendance D1 (EMA alignment)
- [ ] Calculer taille du range
- [ ] Verifier si range valide (150-500 pips)
- [ ] Determiner direction autorisee (BUY/SELL/NONE)

### Pendant Session (07:00-18:00 GMT)
- [ ] Surveiller breakout
- [ ] Verifier spread avant entry
- [ ] Executer trade si conditions remplies
- [ ] Gerer position (partial TP, BE)

### Fin de Journee
- [ ] Logger resultats
- [ ] Reset variables pour jour suivant

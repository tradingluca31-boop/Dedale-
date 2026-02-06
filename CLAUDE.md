# CLAUDE.md - EA MQL5 Development Project

## Contexte Projet

**Proprietaire**: Luca
**Objectif Principal**: Developper des Expert Advisors (EA) en MQL5 pour MetaTrader 5
**Cible**: Passer le challenge FTMO avec des strategies automatisees
**Instrument Principal**: GOLD (XAUUSD)

---

## Base de Connaissances Integree

Claude a acces aux fichiers suivants dans `EA_Knowledge_Base/`:

| Fichier | Contenu |
|---------|---------|
| `01_CHART_PATTERNS.md` | 16 patterns chartistes (continuation + reversal) avec code MQL5 |
| `02_PRICE_ACTION.md` | Techniques price action, candlesticks, S/R, Supply/Demand, FVG |
| `03_ENTRY_TECHNIQUES.md` | Techniques d'entree, confirmations, timing, SL/TP |
| `04_EA_BEST_PRACTICES.md` | Architecture EA, risk management FTMO, optimisations |

**IMPORTANT**: Avant de coder un EA, consulte ces fichiers pour utiliser le code et les patterns documentes.

---

## Patterns Chartistes Maitrises

### Continuation (8 patterns)
1. **Ascending Triangle** - Bullish breakout
2. **Descending Triangle** - Bearish breakdown
3. **Bullish Wedge** - Continuation haussiere
4. **Bearish Wedge** - Continuation baissiere
5. **Bullish Flag** - Mat + drapeau descendant
6. **Bearish Flag** - Mat + drapeau ascendant
7. **Bullish Symmetrical Triangle** - Breakout direction tendance
8. **Bearish Symmetrical Triangle** - Breakdown direction tendance

### Reversal (8 patterns)
1. **Double Bottom** - W pattern, bullish
2. **Double Top** - M pattern, bearish
3. **Triple Bottom** - 3 creux, bullish
4. **Triple Top** - 3 sommets, bearish
5. **Inverted Head & Shoulders** - Bullish reversal majeur
6. **Head & Shoulders** - Bearish reversal majeur
7. **Falling Wedge** - Bullish reversal
8. **Rising Wedge** - Bearish reversal

---

## Regles FTMO Critiques

```
PHASE 1 (Challenge):
- Capital: Variable (10k, 25k, 50k, 100k, 200k)
- Profit Target: 10%
- Max Daily Loss: 5%
- Max Total Loss: 10%
- Duree: 30 jours
- Min Trading Days: 4

PHASE 2 (Verification):
- Profit Target: 5%
- Max Daily Loss: 5%
- Max Total Loss: 10%
- Duree: 60 jours
- Min Trading Days: 4

REGLES STRICTES:
- NO martingale
- NO grid trading risque
- NO hedging sur meme instrument
- Trading uniquement pendant heures marche
- Positions fermees avant weekend (recommande)
```

---

## Architecture EA Standard

```
MonEA/
├── Include/
│   ├── TradeManager.mqh     // Gestion ordres CTrade
│   ├── RiskManager.mqh      // Calcul lots, FTMO rules
│   ├── SignalEngine.mqh     // Generation signaux
│   └── PatternDetector.mqh  // Detection patterns
├── Experts/
│   └── MonEA.mq5            // EA principal
└── Scripts/
    └── Backtester.mq5       // Tests
```

---

## Parametres EA Recommandes

```cpp
// Risk Management
input double RiskPercent = 1.0;        // 1% max par trade
input double MaxDailyDD = 4.5;         // Buffer sous 5% FTMO
input double MaxTotalDD = 9.0;         // Buffer sous 10% FTMO
input int MaxDailyTrades = 3;          // Limiter overtrading
input int MaxOpenTrades = 1;           // 1 position a la fois

// Strategy
input double MinRiskReward = 2.0;      // Minimum R:R
input int MinConfluenceScore = 5;      // Score minimum pour trader

// Time Filter
input int StartHour = 7;               // London open (GMT)
input int EndHour = 20;                // Before Asia
```

---

## Checklist Avant Nouveau EA

- [ ] Definir la strategie (pattern-based, price action, indicator)
- [ ] Verifier conformite FTMO (pas de martingale, risk < 1%)
- [ ] Utiliser les fonctions de detection documentees
- [ ] Implementer risk management complet
- [ ] Ajouter logging pour debug
- [ ] Tester sur M1 data (tick) minimum 1 an
- [ ] Walk-forward optimization
- [ ] Demo trading minimum 1 semaine

---

## Types d'EA a Developper

### 1. Pattern Recognition EA
- Detecte les 16 patterns chartistes
- Entry sur breakout/breakdown confirme
- TP = projection du pattern

### 2. Price Action EA
- Candlestick patterns (engulfing, pin bar, etc.)
- Supply/Demand zones
- Fair Value Gaps (FVG)

### 3. Multi-Timeframe EA
- HTF pour direction (H4/D1)
- MTF pour structure (H1)
- LTF pour entry (M15/M5)

### 4. Hybrid RL + Pattern EA (Future)
- Reinforcement Learning pour timing
- Patterns pour filtrage
- Optimisation continue

---

## Sessions de Trading GOLD

| Session | Heures (GMT) | Caracteristiques |
|---------|--------------|------------------|
| **Asie** | 00:00 - 07:00 | Faible volatilite, range |
| **Londres** | 07:00 - 13:00 | Haute volatilite, trends |
| **Overlap** | 13:00 - 17:00 | MEILLEUR - Max volatilite |
| **New York** | 17:00 - 22:00 | Bonne volatilite |

**Recommandation**: Trader principalement Londres + Overlap (07:00-17:00 GMT)

---

## Memoire Projet

### Decisions Prises
- [x] Focus sur GOLD (XAUUSD) uniquement
- [x] Risk maximum 1% par trade
- [x] Minimum R:R de 2:1
- [x] Pas de trading le vendredi apres 18h GMT
- [x] Confluence score minimum 5/8 pour entry

### A Implementer
- [ ] EA Pattern Recognition (tous les 16 patterns)
- [ ] EA Price Action (S/D + FVG)
- [ ] EA Breakout Pullback
- [ ] Dashboard de monitoring

### Notes Importantes
- ATR typique GOLD: 200-400 points
- Spread moyen GOLD: 15-30 points
- Eviter NFP, FOMC, CPI (high impact news)

---

## Instructions pour Claude

### Lors du Developpement EA
1. **TOUJOURS** consulter `EA_Knowledge_Base/` pour le code existant
2. **UTILISER** les fonctions de detection documentees
3. **RESPECTER** les regles FTMO (max DD, risk %)
4. **INCLURE** logging et error handling
5. **TESTER** le code avec des exemples concrets

### Format du Code
```cpp
// Header standard
#property copyright "Luca"
#property version   "1.00"
#property strict

// Inclure Trade library
#include <Trade/Trade.mqh>

// Grouper les inputs
input group "=== RISK MANAGEMENT ==="
input group "=== STRATEGY ==="
input group "=== FILTERS ==="
```

### Validation Pre-Trade
```cpp
bool CanTrade() {
    return CheckFTMORules() &&      // DD limits
           IsWithinTradingHours() && // Time filter
           IsSpreadAcceptable() &&   // Spread < 50 pts
           IsVolatilitySuitable() && // ATR in range
           !IsNearNews() &&          // No high impact news
           CountOpenTrades() < Max;  // Position limit
}
```

---

## Historique des Modifications

| Date | Modification |
|------|--------------|
| 2026-01-22 | Creation initiale - 16 patterns, price action, entry techniques |

---

## Contact & Support

- **Projet**: EA FTMO CLAUDE CODE
- **Localisation**: `c:\Users\lbye3\OneDrive\Desktop\EA FTMO CLAUDE CODE\`
- **Knowledge Base**: `EA_Knowledge_Base/`

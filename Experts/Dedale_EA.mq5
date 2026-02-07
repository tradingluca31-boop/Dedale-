//+------------------------------------------------------------------+
//|                                                    Dedale_EA.mq5 |
//|                                                             Luca |
//|    DEDALE V16 - Market Structure + ZLEMA Confluence               |
//+------------------------------------------------------------------+
#property copyright "Luca - DEDALE EA v16"
#property version   "16.00"
#property description "H4 EMA50 Filter + H1 ADX + Confluence Score"
#property description "Signals: EMA50/200 Cross + BOS/CHOCH + ZLEMA"
#property description "Placer sur graphique H1"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "=== MONEY MANAGEMENT ==="
input double   InputRiskUSD         = 100.0;    // Risque fixe par trade ($)
input double   InputRiskReward      = 3.0;      // Ratio R:R (TP = SL x 3)
input int      InputMagicNumber     = 161616;   // ID Unique V16

input group "=== H4 TREND FILTER ==="
input int      InputH4EmaPeriod     = 50;       // EMA H4 (filtre directionnel)

input group "=== H1 ADX FILTER ==="
input int      InputH1AdxPeriod     = 14;       // ADX period H1
input int      InputH1AdxThreshold  = 20;       // ADX minimum H1

input group "=== SIGNAL 1: EMA CROSS H1 ==="
input int      InputH1EmaFast       = 50;       // EMA rapide H1
input int      InputH1EmaSlow       = 200;      // EMA lente H1
input int      InputCrossLookback   = 10;       // Lookback barres pour cross recent

input group "=== SIGNAL 2: BOS/CHOCH H1 ==="
input int      InputSwingStrength   = 3;        // Force swing (barres chaque cote)
input int      InputSwingLookback   = 50;       // Lookback pour swing points

input group "=== SIGNAL 3: ZLEMA H1 ==="
input int      InputZlemaPeriod     = 21;       // ZLEMA period
input double   InputZlemaSlopeMin   = 2.0;      // Pente min ZLEMA sur 3 barres ($)

input group "=== CONFLUENCE ==="
input int      InputMinScore        = 2;        // Score minimum pour trader (sur 3)

input group "=== ATR & SL/TP ==="
input int      InputAtrPeriod       = 14;       // ATR period H1
input double   InputAtrMultSL       = 2.0;      // Multiplicateur ATR pour SL

input group "=== FILTRES ==="
input int      InputStartHour       = 7;        // Session debut (7h London)
input int      InputEndHour         = 18;       // Session fin (18h)
input int      InputMaxDailyTrades  = 1;        // Max trades par jour
input int      InputMaxSpread       = 30;       // Spread max (points)
input int      InputMaxTradeHours   = 96;       // Duree max position (heures)

//+------------------------------------------------------------------+
//| STRUCTURES                                                        |
//+------------------------------------------------------------------+
struct SwingPoint
{
   double   price;
   int      barIndex;
};

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                                |
//+------------------------------------------------------------------+
CTrade         trade;

//--- Indicator handles
int            handleH4Ema;
int            handleH1EmaFast;
int            handleH1EmaSlow;
int            handleH1Adx;
int            handleH1Atr;

//--- ZLEMA state (3 dernières valeurs pour calcul de pente)
double         g_Zlema[3];           // [0]=actuel, [1]=prev, [2]=prev-prev
int            g_ZlemaCount;         // Nombre de valeurs calculees
bool           g_ZlemaInitialized;

//--- Swing point cache
SwingPoint     g_SwingHighs[];
SwingPoint     g_SwingLows[];
datetime       g_LastSwingScan;

//+------------------------------------------------------------------+
//| INITIALISATION                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   handleH4Ema     = iMA(_Symbol, PERIOD_H4, InputH4EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handleH1EmaFast = iMA(_Symbol, PERIOD_H1, InputH1EmaFast, 0, MODE_EMA, PRICE_CLOSE);
   handleH1EmaSlow = iMA(_Symbol, PERIOD_H1, InputH1EmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   handleH1Adx     = iADX(_Symbol, PERIOD_H1, InputH1AdxPeriod);
   handleH1Atr     = iATR(_Symbol, PERIOD_H1, InputAtrPeriod);

   if(handleH4Ema == INVALID_HANDLE || handleH1EmaFast == INVALID_HANDLE ||
      handleH1EmaSlow == INVALID_HANDLE || handleH1Adx == INVALID_HANDLE ||
      handleH1Atr == INVALID_HANDLE)
   {
      Print("ERREUR: Impossible de creer les indicateurs.");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(InputMagicNumber);
   trade.SetDeviationInPoints(15);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   //--- Init ZLEMA
   g_Zlema[0] = 0; g_Zlema[1] = 0; g_Zlema[2] = 0;
   g_ZlemaCount = 0;
   g_ZlemaInitialized = false;
   g_LastSwingScan = 0;

   Print(">> DEDALE V16 CONFLUENCE | Session ", InputStartHour, "h-", InputEndHour, "h",
         " | Filter: H4 EMA", InputH4EmaPeriod, " + H1 ADX>", InputH1AdxThreshold,
         " | Signals: EMA", InputH1EmaFast, "/", InputH1EmaSlow,
         " + BOS/CHOCH(sw", InputSwingStrength, ")",
         " + ZLEMA(", InputZlemaPeriod, ")",
         " | MinScore=", InputMinScore, "/3",
         " | SL=", InputAtrMultSL, "xATR | RR=1:", InputRiskReward,
         " | Risk=$", InputRiskUSD);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| DEINITIALISATION                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleH4Ema != INVALID_HANDLE)     IndicatorRelease(handleH4Ema);
   if(handleH1EmaFast != INVALID_HANDLE) IndicatorRelease(handleH1EmaFast);
   if(handleH1EmaSlow != INVALID_HANDLE) IndicatorRelease(handleH1EmaSlow);
   if(handleH1Adx != INVALID_HANDLE)     IndicatorRelease(handleH1Adx);
   if(handleH1Atr != INVALID_HANDLE)     IndicatorRelease(handleH1Atr);
}

//+------------------------------------------------------------------+
//| ONTICK                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   ManagePositions();
   EntryLogic();
}

//+------------------------------------------------------------------+
//| GESTION DES POSITIONS - Fermer si duree > max heures              |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InputMagicNumber) continue;

      ulong  ticket   = PositionGetInteger(POSITION_TICKET);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      double elapsed   = (double)(TimeCurrent() - openTime) / 3600.0;

      if(elapsed >= InputMaxTradeHours)
      {
         trade.PositionClose(ticket);
         Print(">>> FERME (TIMEOUT) | Ticket #", ticket,
               " | Duree=", NormalizeDouble(elapsed, 1), "h >= ", InputMaxTradeHours, "h max");
      }
   }
}

//+------------------------------------------------------------------+
//| LOGIQUE D'ENTREE                                                  |
//+------------------------------------------------------------------+
void EntryLogic()
{
   if(CountPositions() > 0) return;
   if(CountTodayTrades() >= InputMaxDailyTrades) return;

   //--- Filtre horaire
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.hour < InputStartHour || dt.hour >= InputEndHour) return;

   //--- Filtre spread
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InputMaxSpread) return;

   //--- Nouvelle bougie H1 seulement
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_H1, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;

   //=== FILTRE 1: H4 EMA50 (direction) ===
   double h4Ema[];
   ArraySetAsSeries(h4Ema, true);
   if(CopyBuffer(handleH4Ema, 0, 0, 2, h4Ema) < 2) return;

   double h1Close = iClose(_Symbol, PERIOD_H1, 1);

   int direction = 0;
   if(h1Close > h4Ema[1])      direction = +1;   // Bullish
   else if(h1Close < h4Ema[1]) direction = -1;   // Bearish
   else
   {
      Print(">>> NO TRADE | Prix = EMA50 H4 (neutre)");
      return;
   }

   //=== FILTRE 2: H1 ADX > 20 ===
   double adxBuf[];
   ArraySetAsSeries(adxBuf, true);
   if(CopyBuffer(handleH1Adx, 0, 0, 2, adxBuf) < 2) return;
   double adxVal = adxBuf[1];

   if(adxVal < InputH1AdxThreshold)
   {
      Print(">>> NO TRADE | ADX H1=", NormalizeDouble(adxVal, 1), " < ", InputH1AdxThreshold);
      return;
   }

   //=== FILTRES OK - CALCUL DES SIGNAUX ===
   int confluenceScore = 0;
   string signals = "";

   //--- Signal 1: EMA 50/200 Cross
   int crossSignal = CheckEmaCross();
   if(crossSignal == direction)
   {
      confluenceScore++;
      signals += "EMA_CROSS ";
   }

   //--- Signal 2: BOS/CHOCH
   int structureSignal = CheckMarketStructure();
   if(structureSignal == direction)
   {
      confluenceScore++;
      signals += "BOS/CHOCH ";
   }

   //--- Signal 3: ZLEMA
   int zlemaSignal = CheckZLEMA();
   if(zlemaSignal == direction)
   {
      confluenceScore++;
      signals += "ZLEMA ";
   }

   //=== CONFLUENCE CHECK ===
   Print(">>> CONFLUENCE | Score=", confluenceScore, "/3",
         " | Dir=", (direction > 0 ? "BULL" : "BEAR"),
         " | ADX=", NormalizeDouble(adxVal, 1),
         " | Signals: ", signals);

   if(confluenceScore < InputMinScore)
   {
      Print(">>> SKIP | Score ", confluenceScore, " < Min ", InputMinScore);
      return;
   }

   //--- Lire ATR H1
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(handleH1Atr, 0, 0, 2, atrBuf) < 2) return;
   double atrVal = atrBuf[1];
   if(atrVal <= 0) return;

   //--- Execute
   if(direction == +1)
      ExecuteTrade(ORDER_TYPE_BUY, atrVal, confluenceScore, signals);
   else
      ExecuteTrade(ORDER_TYPE_SELL, atrVal, confluenceScore, signals);
}

//+------------------------------------------------------------------+
//| SIGNAL 1: EMA 50/200 CROSS (lookback)                            |
//+------------------------------------------------------------------+
int CheckEmaCross()
{
   int barsNeeded = InputCrossLookback + 2;
   double emaFast[], emaSlow[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);

   if(CopyBuffer(handleH1EmaFast, 0, 0, barsNeeded, emaFast) < barsNeeded) return 0;
   if(CopyBuffer(handleH1EmaSlow, 0, 0, barsNeeded, emaSlow) < barsNeeded) return 0;

   for(int i = 1; i <= InputCrossLookback; i++)
   {
      //--- Cross UP: EMA50 passe au-dessus de EMA200
      if(emaFast[i + 1] <= emaSlow[i + 1] && emaFast[i] > emaSlow[i])
      {
         Print(">>> SIGNAL EMA_CROSS | Cross UP il y a ", i, " barres H1");
         return +1;
      }
      //--- Cross DOWN: EMA50 passe en-dessous de EMA200
      if(emaFast[i + 1] >= emaSlow[i + 1] && emaFast[i] < emaSlow[i])
      {
         Print(">>> SIGNAL EMA_CROSS | Cross DOWN il y a ", i, " barres H1");
         return -1;
      }
   }

   return 0;
}

//+------------------------------------------------------------------+
//| SWING POINTS DETECTION (cached per H1 bar)                       |
//+------------------------------------------------------------------+
void UpdateSwingPoints()
{
   datetime currentBar = iTime(_Symbol, PERIOD_H1, 0);
   if(currentBar == g_LastSwingScan) return;
   g_LastSwingScan = currentBar;

   ArrayResize(g_SwingHighs, 0);
   ArrayResize(g_SwingLows, 0);

   int maxBar = InputSwingLookback - InputSwingStrength;

   for(int i = InputSwingStrength; i <= maxBar; i++)
   {
      //--- Swing High
      double high = iHigh(_Symbol, PERIOD_H1, i);
      bool isSwingHigh = true;
      for(int j = 1; j <= InputSwingStrength; j++)
      {
         if(iHigh(_Symbol, PERIOD_H1, i - j) >= high || iHigh(_Symbol, PERIOD_H1, i + j) >= high)
         {
            isSwingHigh = false;
            break;
         }
      }
      if(isSwingHigh)
      {
         int sz = ArraySize(g_SwingHighs);
         ArrayResize(g_SwingHighs, sz + 1);
         g_SwingHighs[sz].price = high;
         g_SwingHighs[sz].barIndex = i;
      }

      //--- Swing Low
      double low = iLow(_Symbol, PERIOD_H1, i);
      bool isSwingLow = true;
      for(int j = 1; j <= InputSwingStrength; j++)
      {
         if(iLow(_Symbol, PERIOD_H1, i - j) <= low || iLow(_Symbol, PERIOD_H1, i + j) <= low)
         {
            isSwingLow = false;
            break;
         }
      }
      if(isSwingLow)
      {
         int sz = ArraySize(g_SwingLows);
         ArrayResize(g_SwingLows, sz + 1);
         g_SwingLows[sz].price = low;
         g_SwingLows[sz].barIndex = i;
      }
   }
}

//+------------------------------------------------------------------+
//| SIGNAL 2: BOS / CHOCH                                            |
//| BOS = continuation (break dans le sens de la structure)           |
//| CHOCH = reversal (break contre la structure)                      |
//+------------------------------------------------------------------+
int CheckMarketStructure()
{
   UpdateSwingPoints();

   if(ArraySize(g_SwingHighs) < 2 || ArraySize(g_SwingLows) < 2)
   {
      Print(">>> BOS/CHOCH | Pas assez de swing points (H=", ArraySize(g_SwingHighs),
            " L=", ArraySize(g_SwingLows), ")");
      return 0;
   }

   //--- Les swings sont tries du plus recent [0] au plus ancien
   double sh0 = g_SwingHighs[0].price;   // Dernier swing high
   double sh1 = g_SwingHighs[1].price;   // Avant-dernier swing high
   double sl0 = g_SwingLows[0].price;    // Dernier swing low
   double sl1 = g_SwingLows[1].price;    // Avant-dernier swing low

   bool higherHigh = (sh0 > sh1);
   bool higherLow  = (sl0 > sl1);
   bool lowerHigh  = (sh0 < sh1);
   bool lowerLow   = (sl0 < sl1);

   bool isUptrend   = (higherHigh && higherLow);
   bool isDowntrend = (lowerHigh && lowerLow);

   double currentPrice = iClose(_Symbol, PERIOD_H1, 1);

   //--- BOS BULLISH: Uptrend + prix casse dernier swing high
   if(isUptrend && currentPrice > sh0)
   {
      Print(">>> SIGNAL BOS BULLISH | Prix ", NormalizeDouble(currentPrice, 2),
            " > SwingHigh ", NormalizeDouble(sh0, 2), " (continuation)");
      return +1;
   }

   //--- BOS BEARISH: Downtrend + prix casse dernier swing low
   if(isDowntrend && currentPrice < sl0)
   {
      Print(">>> SIGNAL BOS BEARISH | Prix ", NormalizeDouble(currentPrice, 2),
            " < SwingLow ", NormalizeDouble(sl0, 2), " (continuation)");
      return -1;
   }

   //--- CHOCH BULLISH: Downtrend + prix casse dernier lower high
   if(isDowntrend && currentPrice > sh0)
   {
      Print(">>> SIGNAL CHOCH BULLISH | Prix ", NormalizeDouble(currentPrice, 2),
            " > LowerHigh ", NormalizeDouble(sh0, 2), " (reversal)");
      return +1;
   }

   //--- CHOCH BEARISH: Uptrend + prix casse dernier higher low
   if(isUptrend && currentPrice < sl0)
   {
      Print(">>> SIGNAL CHOCH BEARISH | Prix ", NormalizeDouble(currentPrice, 2),
            " < HigherLow ", NormalizeDouble(sl0, 2), " (reversal)");
      return -1;
   }

   //--- Pas de break
   string structure = isUptrend ? "UPTREND" : (isDowntrend ? "DOWNTREND" : "MIXED");
   Print(">>> BOS/CHOCH | Pas de break | Structure=", structure,
         " | Prix=", NormalizeDouble(currentPrice, 2),
         " | SH=", NormalizeDouble(sh0, 2), "/", NormalizeDouble(sh1, 2),
         " | SL=", NormalizeDouble(sl0, 2), "/", NormalizeDouble(sl1, 2));
   return 0;
}

//+------------------------------------------------------------------+
//| ZLEMA UPDATE (manual calculation)                                 |
//| ZLEMA = EMA( 2*Close - Close[lag], period )                      |
//| lag = (period - 1) / 2                                           |
//| Stocke 3 valeurs pour calcul de pente sur 3 barres               |
//+------------------------------------------------------------------+
void UpdateZLEMA()
{
   int lag = (InputZlemaPeriod - 1) / 2;
   double alpha = 2.0 / (InputZlemaPeriod + 1);

   if(!g_ZlemaInitialized)
   {
      //--- Seed avec SMA des valeurs ajustees
      double sum = 0;
      for(int i = 1; i <= InputZlemaPeriod; i++)
      {
         double c    = iClose(_Symbol, PERIOD_H1, i);
         double cLag = iClose(_Symbol, PERIOD_H1, i + lag);
         sum += (2.0 * c - cLag);
      }
      g_Zlema[0] = sum / InputZlemaPeriod;
      g_Zlema[1] = g_Zlema[0];
      g_Zlema[2] = g_Zlema[0];
      g_ZlemaCount = 1;
      g_ZlemaInitialized = true;
      Print(">>> ZLEMA initialise | Seed=", NormalizeDouble(g_Zlema[0], 2),
            " | Period=", InputZlemaPeriod, " | Lag=", lag,
            " | SlopeMin=$", InputZlemaSlopeMin);
      return;
   }

   //--- Shift: [2] = ancien [1], [1] = ancien [0]
   g_Zlema[2] = g_Zlema[1];
   g_Zlema[1] = g_Zlema[0];

   //--- Update normal
   double close0   = iClose(_Symbol, PERIOD_H1, 1);
   double closeLag = iClose(_Symbol, PERIOD_H1, 1 + lag);
   double adjustedClose = 2.0 * close0 - closeLag;

   g_Zlema[0] = alpha * adjustedClose + (1.0 - alpha) * g_Zlema[1];
   if(g_ZlemaCount < 3) g_ZlemaCount++;
}

//+------------------------------------------------------------------+
//| SIGNAL 3: ZLEMA direction + pente minimum + position prix        |
//| Pente = progression ZLEMA sur 3 barres (en $)                    |
//+------------------------------------------------------------------+
int CheckZLEMA()
{
   UpdateZLEMA();

   if(!g_ZlemaInitialized || g_ZlemaCount < 3) return 0;

   double currentPrice = iClose(_Symbol, PERIOD_H1, 1);

   //--- Pente sur 3 barres (en $)
   double slope = g_Zlema[0] - g_Zlema[2];
   double absSlope = MathAbs(slope);
   bool zlemaRising  = (slope > 0);
   bool zlemaFalling = (slope < 0);

   //--- Verifier pente minimum
   if(absSlope < InputZlemaSlopeMin)
   {
      Print(">>> ZLEMA FLAT | Pente=$", NormalizeDouble(slope, 2),
            " < $", InputZlemaSlopeMin, " min",
            " | ZLEMA=", NormalizeDouble(g_Zlema[0], 2),
            " | Prix=", NormalizeDouble(currentPrice, 2));
      return 0;
   }

   //--- Bullish: ZLEMA monte assez ET prix au-dessus
   if(zlemaRising && currentPrice > g_Zlema[0])
   {
      Print(">>> SIGNAL ZLEMA BULLISH | Pente=+$", NormalizeDouble(slope, 2),
            " | ZLEMA=", NormalizeDouble(g_Zlema[0], 2),
            " | Prix=", NormalizeDouble(currentPrice, 2));
      return +1;
   }

   //--- Bearish: ZLEMA descend assez ET prix en-dessous
   if(zlemaFalling && currentPrice < g_Zlema[0])
   {
      Print(">>> SIGNAL ZLEMA BEARISH | Pente=$", NormalizeDouble(slope, 2),
            " | ZLEMA=", NormalizeDouble(g_Zlema[0], 2),
            " | Prix=", NormalizeDouble(currentPrice, 2));
      return -1;
   }

   Print(">>> ZLEMA NEUTRAL | Pente=$", NormalizeDouble(slope, 2),
         " | ZLEMA=", NormalizeDouble(g_Zlema[0], 2),
         " | Prix=", NormalizeDouble(currentPrice, 2));
   return 0;
}

//+------------------------------------------------------------------+
//| EXECUTION DU TRADE                                                |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double atrValue, int score, string signals)
{
   double price, sl, tp;
   double slDistance = atrValue * InputAtrMultSL;
   double tpDistance = slDistance * InputRiskReward;

   if(type == ORDER_TYPE_BUY)
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl    = price - slDistance;
      tp    = price + tpDistance;
   }
   else
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl    = price + slDistance;
      tp    = price - tpDistance;
   }

   price = NormalizeDouble(price, _Digits);
   sl    = NormalizeDouble(sl, _Digits);
   tp    = NormalizeDouble(tp, _Digits);

   double lotSize = CalculateLotSizeFixedRisk(slDistance);

   bool result;
   if(type == ORDER_TYPE_BUY)
      result = trade.Buy(lotSize, _Symbol, price, sl, tp, "DEDALE V16 Buy");
   else
      result = trade.Sell(lotSize, _Symbol, price, sl, tp, "DEDALE V16 Sell");

   if(result)
      Print(">>> OUVERT | ", (type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
            " | Score ", score, "/3 | ", signals,
            " | Lot: ", lotSize,
            " | SL: ", NormalizeDouble(slDistance / _Point, 0), " pts (",
            InputAtrMultSL, "xATR)",
            " | TP: ", NormalizeDouble(tpDistance / _Point, 0), " pts (1:",
            InputRiskReward, ")",
            " | Risk: $", InputRiskUSD);
   else
      Print(">>> ERREUR: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| CALCUL DU LOT - Risque fixe en $                                  |
//+------------------------------------------------------------------+
double CalculateLotSizeFixedRisk(double slDistance)
{
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize == 0 || tickValue == 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double slTicks = slDistance / tickSize;
   double lot = InputRiskUSD / (slTicks * tickValue);

   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / lotStep) * lotStep;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;

   return lot;
}

//+------------------------------------------------------------------+
//| COMPTER LES POSITIONS OUVERTES                                    |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol)
         if(PositionGetInteger(POSITION_MAGIC) == InputMagicNumber)
            count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| COMPTER LES TRADES DU JOUR                                        |
//+------------------------------------------------------------------+
int CountTodayTrades()
{
   int count = 0;
   datetime startOfDay = iTime(_Symbol, PERIOD_D1, 0);
   HistorySelect(startOfDay, TimeCurrent());

   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InputMagicNumber)
      {
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
            count++;
      }
   }
   return count;
}
//+------------------------------------------------------------------+

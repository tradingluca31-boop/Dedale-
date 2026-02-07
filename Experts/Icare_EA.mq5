//+------------------------------------------------------------------+
//|                                                     Icare_EA.mq5 |
//|                                                             Luca |
//|    ICARE V1 - BOS Pullback ZLEMA (EURUSD M15)                    |
//+------------------------------------------------------------------+
#property copyright "Luca - ICARE EA v1"
#property version   "1.00"
#property description "H4 EMA200 Filter + H1 ADX + M15 BOS/Pullback/Impulse"
#property description "State Machine: BOS -> Pullback ZLEMA -> Impulse Candle"
#property description "Placer sur graphique M15 - EURUSD"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "=== MONEY MANAGEMENT ==="
input double   InputRiskPercent     = 1.0;      // Risque par trade (% du capital)
input double   InputRiskReward      = 3.0;      // Ratio R:R (TP = SL x 3)
input int      InputMagicNumber     = 222222;   // ID Unique Icare

input group "=== H4 TREND FILTER ==="
input int      InputH4EmaPeriod     = 200;      // EMA H4 (filtre directionnel)

input group "=== H1 ADX FILTER ==="
input int      InputH1AdxPeriod     = 14;       // ADX period H1
input int      InputH1AdxThreshold  = 25;       // ADX minimum H1

input group "=== M15 BOS ==="
input int      InputSwingStrength   = 5;        // Force swing M15 (barres chaque cote)
input int      InputSwingLookback   = 100;      // Lookback pour swing points
input int      InputBosExpiry       = 20;       // Barres max attente pullback apres BOS

input group "=== M15 ZLEMA ==="
input int      InputZlemaPeriod     = 21;       // ZLEMA period
input double   InputZlemaSlopeMin   = 30.0;     // Pente min ZLEMA sur 3 barres (points)
input int      InputPullbackExpiry  = 10;       // Barres max attente impulse apres pullback

input group "=== M15 IMPULSE CANDLE ==="
input int      InputMinBodyPts      = 30;       // Corps min bougie impulsion (points)

input group "=== ATR & SL/TP ==="
input int      InputAtrPeriod       = 14;       // ATR period M15
input double   InputAtrMultSL       = 1.5;      // Multiplicateur ATR pour SL

input group "=== BREAK-EVEN ==="
input double   InputBeTriggerR      = 1.5;      // Break-Even a 1.5R (0=desactive)
input int      InputBeBufferPts     = 20;       // Buffer BE (points = 2 pips)

input group "=== FILTRES ==="
input int      InputStartHour       = 8;        // Session debut (8h London)
input int      InputEndHour         = 17;       // Session fin (17h)
input int      InputMaxDailyTrades  = 1;        // Max trades par jour
input int      InputMaxSpread       = 15;       // Spread max (points = 1.5 pips)
input int      InputMaxTradeHours   = 96;       // Duree max position (heures)

//+------------------------------------------------------------------+
//| STRUCTURES & ENUMS                                                |
//+------------------------------------------------------------------+
struct SwingPoint
{
   double   price;
   int      barIndex;
};

enum TradeState
{
   STATE_IDLE,              // Attente BOS
   STATE_BOS_DETECTED,      // BOS trouve, attente pullback ZLEMA
   STATE_PULLBACK_DONE      // Pullback fait, attente impulse candle
};

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                                |
//+------------------------------------------------------------------+
CTrade         trade;

//--- Indicator handles
int            handleH4Ema;
int            handleH1Adx;
int            handleM15Atr;

//--- ZLEMA state (3 dernieres valeurs pour calcul de pente)
double         g_Zlema[3];           // [0]=actuel, [1]=prev, [2]=prev-prev
int            g_ZlemaCount;
bool           g_ZlemaInitialized;

//--- Swing point cache
SwingPoint     g_SwingHighs[];
SwingPoint     g_SwingLows[];
datetime       g_LastSwingScan;

//--- State machine
TradeState     g_State;
int            g_StateDirection;     // +1 (buy) ou -1 (sell)
int            g_StateBars;          // Barres ecoulees dans l'etat courant
double         g_BosLevel;           // Prix du BOS (pour logs)

//+------------------------------------------------------------------+
//| INITIALISATION                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   handleH4Ema  = iMA(_Symbol, PERIOD_H4, InputH4EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handleH1Adx  = iADX(_Symbol, PERIOD_H1, InputH1AdxPeriod);
   handleM15Atr = iATR(_Symbol, PERIOD_M15, InputAtrPeriod);

   if(handleH4Ema == INVALID_HANDLE || handleH1Adx == INVALID_HANDLE ||
      handleM15Atr == INVALID_HANDLE)
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

   //--- Init State Machine
   g_State = STATE_IDLE;
   g_StateDirection = 0;
   g_StateBars = 0;
   g_BosLevel = 0;

   Print(">> ICARE V1 | EURUSD M15 | Session ", InputStartHour, "h-", InputEndHour, "h",
         " | Filter: H4 EMA", InputH4EmaPeriod, " + H1 ADX>", InputH1AdxThreshold,
         " | BOS(sw", InputSwingStrength, ") -> ZLEMA(", InputZlemaPeriod, ") -> Impulse",
         " | SL=", InputAtrMultSL, "xATR | RR=1:", InputRiskReward,
         " | BE@", InputBeTriggerR, "R",
         " | Risk=", InputRiskPercent, "%");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| DEINITIALISATION                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleH4Ema != INVALID_HANDLE)  IndicatorRelease(handleH4Ema);
   if(handleH1Adx != INVALID_HANDLE)  IndicatorRelease(handleH1Adx);
   if(handleM15Atr != INVALID_HANDLE) IndicatorRelease(handleM15Atr);
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
//| GESTION DES POSITIONS - BE + Timeout                              |
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

      //--- Timeout
      if(elapsed >= InputMaxTradeHours)
      {
         trade.PositionClose(ticket);
         Print(">>> FERME (TIMEOUT) | Ticket #", ticket,
               " | Duree=", NormalizeDouble(elapsed, 1), "h >= ", InputMaxTradeHours, "h max");
         continue;
      }

      //--- Break-Even
      if(InputBeTriggerR > 0)
      {
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double tp        = PositionGetDouble(POSITION_TP);
         long   posType   = PositionGetInteger(POSITION_TYPE);

         double slDistance = MathAbs(openPrice - currentSL);
         double triggerDist = slDistance * InputBeTriggerR;
         double beLevel   = (posType == POSITION_TYPE_BUY)
                            ? openPrice + InputBeBufferPts * _Point
                            : openPrice - InputBeBufferPts * _Point;

         bool alreadyBE = (posType == POSITION_TYPE_BUY) ? (currentSL >= openPrice) : (currentSL <= openPrice);

         if(!alreadyBE && slDistance > 0)
         {
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

            bool triggered = false;
            if(posType == POSITION_TYPE_BUY && bid >= openPrice + triggerDist)
               triggered = true;
            if(posType == POSITION_TYPE_SELL && ask <= openPrice - triggerDist)
               triggered = true;

            if(triggered)
            {
               trade.PositionModify(ticket, beLevel, tp);
               Print(">>> BREAK-EVEN | Ticket #", ticket,
                     " | Entry=", NormalizeDouble(openPrice, _Digits),
                     " | NewSL=", NormalizeDouble(beLevel, _Digits),
                     " | Trigger=", InputBeTriggerR, "R");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| LOGIQUE D'ENTREE - State Machine                                  |
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

   //--- Nouvelle bougie M15 seulement
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_M15, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;

   //--- Incrementer compteur barres dans l'etat
   g_StateBars++;

   //--- Update ZLEMA a chaque barre M15
   UpdateZLEMA();

   //=== FILTRE 1: H4 EMA200 (direction) ===
   double h4Ema[];
   ArraySetAsSeries(h4Ema, true);
   if(CopyBuffer(handleH4Ema, 0, 0, 2, h4Ema) < 2) return;

   double m15Close = iClose(_Symbol, PERIOD_M15, 1);
   int direction = 0;
   if(m15Close > h4Ema[1])      direction = +1;
   else if(m15Close < h4Ema[1]) direction = -1;
   else return;

   //--- Si direction H4 change, reset state machine
   if(g_State != STATE_IDLE && direction != g_StateDirection)
   {
      Print(">>> STATE RESET | Direction H4 changee de ",
            (g_StateDirection > 0 ? "BULL" : "BEAR"), " a ",
            (direction > 0 ? "BULL" : "BEAR"));
      ResetState();
   }

   //=== FILTRE 2: H1 ADX > 25 ===
   double adxBuf[];
   ArraySetAsSeries(adxBuf, true);
   if(CopyBuffer(handleH1Adx, 0, 0, 2, adxBuf) < 2) return;
   double adxVal = adxBuf[1];

   if(adxVal < InputH1AdxThreshold)
   {
      Print(">>> NO TRADE | ADX H1=", NormalizeDouble(adxVal, 1), " < ", InputH1AdxThreshold);
      return;
   }

   //=== STATE MACHINE ===
   switch(g_State)
   {
      case STATE_IDLE:
         ProcessStateIdle(direction);
         break;

      case STATE_BOS_DETECTED:
         ProcessStateBos();
         break;

      case STATE_PULLBACK_DONE:
         ProcessStatePullback();
         break;
   }
}

//+------------------------------------------------------------------+
//| STATE IDLE - Cherche BOS M15                                      |
//+------------------------------------------------------------------+
void ProcessStateIdle(int direction)
{
   int bosSignal = CheckBOS();

   if(bosSignal == direction)
   {
      g_State = STATE_BOS_DETECTED;
      g_StateDirection = direction;
      g_StateBars = 0;
      Print(">>> ETAT -> BOS_DETECTED | Dir=", (direction > 0 ? "BUY" : "SELL"),
            " | BOS@", NormalizeDouble(g_BosLevel, _Digits));
   }
}

//+------------------------------------------------------------------+
//| STATE BOS_DETECTED - Attend pullback vers ZLEMA                   |
//+------------------------------------------------------------------+
void ProcessStateBos()
{
   //--- Expiry check
   if(g_StateBars > InputBosExpiry)
   {
      Print(">>> STATE EXPIRE | BOS expire apres ", g_StateBars, " barres > ", InputBosExpiry);
      ResetState();
      return;
   }

   if(!g_ZlemaInitialized || g_ZlemaCount < 3) return;

   double low1  = iLow(_Symbol, PERIOD_M15, 1);
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);

   bool pullback = false;

   //--- BUY: prix descend toucher ZLEMA (meche basse <= ZLEMA)
   if(g_StateDirection == +1 && low1 <= g_Zlema[0])
      pullback = true;

   //--- SELL: prix monte toucher ZLEMA (meche haute >= ZLEMA)
   if(g_StateDirection == -1 && high1 >= g_Zlema[0])
      pullback = true;

   if(pullback)
   {
      g_State = STATE_PULLBACK_DONE;
      g_StateBars = 0;
      Print(">>> ETAT -> PULLBACK_DONE | Dir=", (g_StateDirection > 0 ? "BUY" : "SELL"),
            " | ZLEMA=", NormalizeDouble(g_Zlema[0], _Digits),
            " | Low=", NormalizeDouble(low1, _Digits),
            " | High=", NormalizeDouble(high1, _Digits));
   }
}

//+------------------------------------------------------------------+
//| STATE PULLBACK_DONE - Attend bougie d'impulsion                   |
//+------------------------------------------------------------------+
void ProcessStatePullback()
{
   //--- Expiry check
   if(g_StateBars > InputPullbackExpiry)
   {
      Print(">>> STATE EXPIRE | Pullback expire apres ", g_StateBars, " barres > ", InputPullbackExpiry);
      ResetState();
      return;
   }

   if(!g_ZlemaInitialized || g_ZlemaCount < 3) return;

   double open1  = iOpen(_Symbol, PERIOD_M15, 1);
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double body   = MathAbs(close1 - open1) / _Point;

   //--- Pente ZLEMA (en points)
   double slope = (g_Zlema[0] - g_Zlema[2]) / _Point;

   bool impulse = false;

   //--- BUY: close > ZLEMA, corps > min, pente ZLEMA positive
   if(g_StateDirection == +1 &&
      close1 > g_Zlema[0] &&
      close1 > open1 &&
      body >= InputMinBodyPts &&
      slope >= InputZlemaSlopeMin)
   {
      impulse = true;
   }

   //--- SELL: close < ZLEMA, corps > min, pente ZLEMA negative
   if(g_StateDirection == -1 &&
      close1 < g_Zlema[0] &&
      close1 < open1 &&
      body >= InputMinBodyPts &&
      slope <= -InputZlemaSlopeMin)
   {
      impulse = true;
   }

   if(impulse)
   {
      Print(">>> IMPULSE CANDLE! | Dir=", (g_StateDirection > 0 ? "BUY" : "SELL"),
            " | Body=", NormalizeDouble(body, 0), " pts",
            " | Slope=", NormalizeDouble(slope, 1), " pts",
            " | Close=", NormalizeDouble(close1, _Digits),
            " | ZLEMA=", NormalizeDouble(g_Zlema[0], _Digits));

      //--- Lire ATR M15
      double atrBuf[];
      ArraySetAsSeries(atrBuf, true);
      if(CopyBuffer(handleM15Atr, 0, 0, 2, atrBuf) < 2) { ResetState(); return; }
      double atrVal = atrBuf[1];
      if(atrVal <= 0) { ResetState(); return; }

      if(g_StateDirection == +1)
         ExecuteTrade(ORDER_TYPE_BUY, atrVal);
      else
         ExecuteTrade(ORDER_TYPE_SELL, atrVal);

      ResetState();
   }
}

//+------------------------------------------------------------------+
//| RESET STATE MACHINE                                               |
//+------------------------------------------------------------------+
void ResetState()
{
   g_State = STATE_IDLE;
   g_StateDirection = 0;
   g_StateBars = 0;
   g_BosLevel = 0;
}

//+------------------------------------------------------------------+
//| BOS DETECTION - Break of Structure M15                            |
//+------------------------------------------------------------------+
int CheckBOS()
{
   UpdateSwingPoints();

   if(ArraySize(g_SwingHighs) < 1 || ArraySize(g_SwingLows) < 1)
   {
      Print(">>> BOS | Pas assez de swing points (H=", ArraySize(g_SwingHighs),
            " L=", ArraySize(g_SwingLows), ")");
      return 0;
   }

   double currentClose = iClose(_Symbol, PERIOD_M15, 1);
   double lastSwingHigh = g_SwingHighs[0].price;
   double lastSwingLow  = g_SwingLows[0].price;

   //--- BOS BULLISH: close casse le dernier swing high
   if(currentClose > lastSwingHigh)
   {
      g_BosLevel = lastSwingHigh;
      Print(">>> BOS BULLISH | Close ", NormalizeDouble(currentClose, _Digits),
            " > SwingHigh ", NormalizeDouble(lastSwingHigh, _Digits));
      return +1;
   }

   //--- BOS BEARISH: close casse le dernier swing low
   if(currentClose < lastSwingLow)
   {
      g_BosLevel = lastSwingLow;
      Print(">>> BOS BEARISH | Close ", NormalizeDouble(currentClose, _Digits),
            " < SwingLow ", NormalizeDouble(lastSwingLow, _Digits));
      return -1;
   }

   return 0;
}

//+------------------------------------------------------------------+
//| SWING POINTS DETECTION M15 (cached per M15 bar)                   |
//+------------------------------------------------------------------+
void UpdateSwingPoints()
{
   datetime currentBar = iTime(_Symbol, PERIOD_M15, 0);
   if(currentBar == g_LastSwingScan) return;
   g_LastSwingScan = currentBar;

   ArrayResize(g_SwingHighs, 0);
   ArrayResize(g_SwingLows, 0);

   int maxBar = InputSwingLookback - InputSwingStrength;

   for(int i = InputSwingStrength; i <= maxBar; i++)
   {
      //--- Swing High
      double high = iHigh(_Symbol, PERIOD_M15, i);
      bool isSwingHigh = true;
      for(int j = 1; j <= InputSwingStrength; j++)
      {
         if(iHigh(_Symbol, PERIOD_M15, i - j) >= high || iHigh(_Symbol, PERIOD_M15, i + j) >= high)
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
      double low = iLow(_Symbol, PERIOD_M15, i);
      bool isSwingLow = true;
      for(int j = 1; j <= InputSwingStrength; j++)
      {
         if(iLow(_Symbol, PERIOD_M15, i - j) <= low || iLow(_Symbol, PERIOD_M15, i + j) <= low)
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
//| ZLEMA UPDATE M15 (manual calculation)                             |
//| ZLEMA = EMA( 2*Close - Close[lag], period )                      |
//| lag = (period - 1) / 2                                           |
//+------------------------------------------------------------------+
void UpdateZLEMA()
{
   int lag = (InputZlemaPeriod - 1) / 2;
   double alpha = 2.0 / (InputZlemaPeriod + 1);

   if(!g_ZlemaInitialized)
   {
      double sum = 0;
      for(int i = 1; i <= InputZlemaPeriod; i++)
      {
         double c    = iClose(_Symbol, PERIOD_M15, i);
         double cLag = iClose(_Symbol, PERIOD_M15, i + lag);
         sum += (2.0 * c - cLag);
      }
      g_Zlema[0] = sum / InputZlemaPeriod;
      g_Zlema[1] = g_Zlema[0];
      g_Zlema[2] = g_Zlema[0];
      g_ZlemaCount = 1;
      g_ZlemaInitialized = true;
      Print(">>> ZLEMA initialise | Seed=", NormalizeDouble(g_Zlema[0], _Digits),
            " | Period=", InputZlemaPeriod, " | Lag=", lag,
            " | SlopeMin=", InputZlemaSlopeMin, " pts");
      return;
   }

   g_Zlema[2] = g_Zlema[1];
   g_Zlema[1] = g_Zlema[0];

   double close0   = iClose(_Symbol, PERIOD_M15, 1);
   double closeLag = iClose(_Symbol, PERIOD_M15, 1 + lag);
   double adjustedClose = 2.0 * close0 - closeLag;

   g_Zlema[0] = alpha * adjustedClose + (1.0 - alpha) * g_Zlema[1];
   if(g_ZlemaCount < 3) g_ZlemaCount++;
}

//+------------------------------------------------------------------+
//| EXECUTION DU TRADE                                                |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double atrValue)
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

   double lotSize = CalculateLotSize(slDistance);

   bool result;
   if(type == ORDER_TYPE_BUY)
      result = trade.Buy(lotSize, _Symbol, price, sl, tp, "ICARE V1 Buy");
   else
      result = trade.Sell(lotSize, _Symbol, price, sl, tp, "ICARE V1 Sell");

   if(result)
      Print(">>> OUVERT | ", (type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
            " | Lot: ", lotSize,
            " | SL: ", NormalizeDouble(slDistance / _Point, 0), " pts (",
            InputAtrMultSL, "xATR)",
            " | TP: ", NormalizeDouble(tpDistance / _Point, 0), " pts (1:",
            InputRiskReward, ")",
            " | Risk: ", InputRiskPercent, "% = $",
            NormalizeDouble(AccountInfoDouble(ACCOUNT_BALANCE) * InputRiskPercent / 100.0, 2));
   else
      Print(">>> ERREUR: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| CALCUL DU LOT - Risque en % du capital                            |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskUSD  = balance * InputRiskPercent / 100.0;

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize == 0 || tickValue == 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double slTicks = slDistance / tickSize;
   double lot = riskUSD / (slTicks * tickValue);

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

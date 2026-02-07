//+------------------------------------------------------------------+
//|                                                     Icare_EA.mq5 |
//|                                                             Luca |
//|    ICARE PRO V2 - Smart Money: BOS + FVG + Limit Order           |
//|    EURUSD M15 - Institutional Flow                                |
//+------------------------------------------------------------------+
#property copyright "Luca - ICARE PRO V2"
#property version   "2.00"
#property description "H4 EMA200 → M15 BOS → FVG → Limit Order at 50%"
#property description "Smart Money / Institutional Approach"
#property description "Placer sur graphique M15 - EURUSD"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "=== MONEY MANAGEMENT ==="
input double   InputRiskPercent     = 1.0;      // Risk % du capital par trade
input double   InputRiskReward      = 3.0;      // R:R (TP = SL x 3)
input int      InputMagicNumber     = 222222;   // Magic Number

input group "=== H4 TREND FILTER ==="
input int      InputH4EmaPeriod     = 200;      // EMA period H4 (direction)

input group "=== M15 BOS ==="
input int      InputSwingStrength   = 3;        // Swing strength (barres chaque cote)
input int      InputSwingLookback   = 50;       // Swing lookback (barres)
input int      InputBosMaxBars      = 20;       // Max barres pour trouver FVG apres BOS

input group "=== M15 FVG ==="
input int      InputFvgScanBars     = 10;       // FVG scan range (barres)
input int      InputMinFvgPts       = 10;       // Taille min FVG (points = 1 pip)
input int      InputPendingExpiry   = 10;       // Annuler limit order apres N barres

input group "=== STOP LOSS ==="
input int      InputSlBufferPts     = 20;       // Buffer SL au-dela du swing (pts = 2 pips)
input int      InputMinSLPts        = 50;       // SL minimum (pts = 5 pips)

input group "=== BREAK-EVEN ==="
input double   InputBeTriggerR      = 1.5;      // BE a 1.5R (0 = desactive)
input int      InputBeBufferPts     = 20;       // Buffer BE (pts = 2 pips)

input group "=== FILTRES ==="
input int      InputStartHour       = 9;        // Session debut (London)
input int      InputEndHour         = 17;       // Session fin
input int      InputMaxDailyTrades  = 1;        // Max trades par jour
input int      InputMaxSpread       = 12;       // Spread max (pts = 1.2 pips)
input int      InputMaxTradeHours   = 96;       // Duree max position (heures)

input group "=== NEWS FILTER ==="
input bool     InputNewsFilter      = true;     // Filtre news (live only, off en backtest)
input int      InputNewsMinutes     = 30;       // Buffer autour des news (minutes)

//+------------------------------------------------------------------+
//| STRUCTURES & ENUMS                                                |
//+------------------------------------------------------------------+
struct SwingPoint
{
   double   price;
   int      barIndex;
};

struct FVGZone
{
   double   top;         // borne haute du gap
   double   bottom;      // borne basse du gap
   double   entry;       // niveau 50% (prix du limit order)
   int      direction;   // +1 bullish, -1 bearish
};

enum TradeState
{
   STATE_IDLE,            // Attente BOS
   STATE_BOS_DETECTED,    // BOS trouve, scan FVG en cours
   STATE_ORDER_PLACED     // Limit order actif
};

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                                |
//+------------------------------------------------------------------+
CTrade         trade;
int            handleH4Ema;

//--- Swing point cache
SwingPoint     g_SwingHighs[];
SwingPoint     g_SwingLows[];
datetime       g_LastSwingScan;

//--- State machine
TradeState     g_State;
int            g_StateDirection;     // +1 buy, -1 sell
double         g_BosLevel;           // Prix du BOS
double         g_SwingSL;            // SL structurel (swing)
int            g_StateBars;          // Barres dans l'etat courant

//--- Pending order tracking
ulong          g_PendingTicket;      // Ticket du limit order
int            g_PendingBars;        // Barres depuis placement

//+------------------------------------------------------------------+
//| INITIALISATION                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   handleH4Ema = iMA(_Symbol, PERIOD_H4, InputH4EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(handleH4Ema == INVALID_HANDLE)
   {
      Print("ERREUR: Impossible de creer indicateur H4 EMA");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(InputMagicNumber);
   trade.SetDeviationInPoints(15);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   //--- Init state
   g_LastSwingScan = 0;
   ResetState();
   g_PendingTicket = 0;
   g_PendingBars = 0;

   //--- Detect existing pending order (EA restart recovery)
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderGetInteger(ORDER_MAGIC) == InputMagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol)
      {
         g_PendingTicket = ticket;
         g_State = STATE_ORDER_PLACED;
         Print(">>> RECOVERY | Pending order #", ticket, " detected");
         break;
      }
   }

   Print(">> ICARE PRO V2 | EURUSD M15 | Session ", InputStartHour, "h-", InputEndHour, "h",
         " | H4 EMA", InputH4EmaPeriod,
         " | BOS(sw", InputSwingStrength, ") -> FVG -> Limit@50%",
         " | SL=Structural(min", InputMinSLPts, "pts) | RR=1:", InputRiskReward,
         " | BE@", InputBeTriggerR, "R",
         " | Risk=", InputRiskPercent, "%",
         " | News=", (InputNewsFilter ? "ON" : "OFF"));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| DEINITIALISATION                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleH4Ema != INVALID_HANDLE) IndicatorRelease(handleH4Ema);

   //--- Cancel pending order on deinit
   if(g_PendingTicket > 0)
   {
      trade.OrderDelete(g_PendingTicket);
      Print(">>> DEINIT | Pending order #", g_PendingTicket, " cancelled");
   }
}

//+------------------------------------------------------------------+
//| ONTICK                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   ManagePositions();
   ManagePendingOrders();
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

      ulong    ticket   = PositionGetInteger(POSITION_TICKET);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      double   elapsed  = (double)(TimeCurrent() - openTime) / 3600.0;

      //--- Timeout
      if(elapsed >= InputMaxTradeHours)
      {
         trade.PositionClose(ticket);
         Print(">>> TIMEOUT | #", ticket, " | ", NormalizeDouble(elapsed, 1),
               "h >= ", InputMaxTradeHours, "h");
         continue;
      }

      //--- Break-Even
      if(InputBeTriggerR > 0)
      {
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double tp        = PositionGetDouble(POSITION_TP);
         long   posType   = PositionGetInteger(POSITION_TYPE);

         double slDistance  = MathAbs(openPrice - currentSL);
         double triggerDist = slDistance * InputBeTriggerR;
         double beLevel     = (posType == POSITION_TYPE_BUY)
                              ? openPrice + InputBeBufferPts * _Point
                              : openPrice - InputBeBufferPts * _Point;

         bool alreadyBE = (posType == POSITION_TYPE_BUY)
                          ? (currentSL >= openPrice)
                          : (currentSL <= openPrice);

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
               Print(">>> BREAK-EVEN | #", ticket,
                     " | Entry=", NormalizeDouble(openPrice, _Digits),
                     " | NewSL=", NormalizeDouble(beLevel, _Digits),
                     " | Trigger=", InputBeTriggerR, "R");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| GESTION DES ORDRES PENDING - Fill check + Expiry                  |
//+------------------------------------------------------------------+
void ManagePendingOrders()
{
   if(g_PendingTicket == 0) return;

   //--- Check if pending order still exists
   bool orderExists = false;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == g_PendingTicket)
      {
         orderExists = true;
         break;
      }
   }

   if(!orderExists)
   {
      //--- Order disappeared: filled or cancelled externally
      if(CountPositions() > 0)
         Print(">>> LIMIT FILLED | #", g_PendingTicket, " -> Position ouverte");
      else
         Print(">>> LIMIT CANCELLED | #", g_PendingTicket);

      g_PendingTicket = 0;
      g_PendingBars = 0;
      ResetState();
      return;
   }

   //--- Bar-based expiry check (new bar only)
   static datetime lastCheckBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_M15, 0);
   if(currentBar != lastCheckBar)
   {
      lastCheckBar = currentBar;
      g_PendingBars++;

      if(g_PendingBars >= InputPendingExpiry)
      {
         trade.OrderDelete(g_PendingTicket);
         Print(">>> PENDING EXPIRED | #", g_PendingTicket,
               " | ", g_PendingBars, " barres sans fill -> annule");
         g_PendingTicket = 0;
         g_PendingBars = 0;
         ResetState();
      }
   }
}

//+------------------------------------------------------------------+
//| LOGIQUE D'ENTREE - Filtres + State Machine                        |
//+------------------------------------------------------------------+
void EntryLogic()
{
   //--- Skip if position open or pending order active
   if(CountPositions() > 0) return;
   if(g_State == STATE_ORDER_PLACED) return;
   if(CountTodayTrades() >= InputMaxDailyTrades) return;

   //--- Time filter
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.hour < InputStartHour || dt.hour >= InputEndHour) return;

   //--- Spread filter
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InputMaxSpread) return;

   //--- New M15 bar only
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_M15, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;

   //--- Increment state bars
   if(g_State != STATE_IDLE) g_StateBars++;

   //--- News filter (live only, skip in tester)
   if(InputNewsFilter && !MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
   {
      if(IsNearNews())
      {
         Print(">>> NEWS FILTER | High impact news within ", InputNewsMinutes, " min");
         return;
      }
   }

   //=== H4 EMA200 Direction ===
   double h4Ema[];
   ArraySetAsSeries(h4Ema, true);
   if(CopyBuffer(handleH4Ema, 0, 0, 2, h4Ema) < 2) return;

   double m15Close = iClose(_Symbol, PERIOD_M15, 1);
   int direction = 0;
   if(m15Close > h4Ema[1])      direction = +1;
   else if(m15Close < h4Ema[1]) direction = -1;
   else return;

   //--- If H4 direction changed, reset state machine
   if(g_State != STATE_IDLE && direction != g_StateDirection)
   {
      Print(">>> RESET | H4 direction changed: ",
            (g_StateDirection > 0 ? "BULL" : "BEAR"), " -> ",
            (direction > 0 ? "BULL" : "BEAR"));
      ResetState();
   }

   //=== STATE MACHINE ===
   switch(g_State)
   {
      case STATE_IDLE:
         ProcessStateIdle(direction);
         break;

      case STATE_BOS_DETECTED:
         ProcessStateBosDetected();
         break;

      case STATE_ORDER_PLACED:
         // Managed by ManagePendingOrders()
         break;
   }
}

//+------------------------------------------------------------------+
//| STATE IDLE - Detect BOS on M15                                    |
//+------------------------------------------------------------------+
void ProcessStateIdle(int direction)
{
   UpdateSwingPoints();

   int bosSignal = CheckBOS(direction);
   if(bosSignal == 0) return;

   //--- BOS found!
   g_State = STATE_BOS_DETECTED;
   g_StateDirection = direction;
   g_StateBars = 0;

   //--- Save structural SL (swing opposite to BOS direction)
   if(direction == +1 && ArraySize(g_SwingLows) > 0)
      g_SwingSL = g_SwingLows[0].price - InputSlBufferPts * _Point;
   else if(direction == -1 && ArraySize(g_SwingHighs) > 0)
      g_SwingSL = g_SwingHighs[0].price + InputSlBufferPts * _Point;
   else
   {
      Print(">>> BOS SKIP | No swing point for structural SL");
      ResetState();
      return;
   }

   Print(">>> BOS DETECTED | Dir=", (direction > 0 ? "BUY" : "SELL"),
         " | BOS@", NormalizeDouble(g_BosLevel, _Digits),
         " | Structural SL@", NormalizeDouble(g_SwingSL, _Digits));

   //--- Immediately try to find FVG on same bar
   ProcessStateBosDetected();
}

//+------------------------------------------------------------------+
//| STATE BOS_DETECTED - Scan for FVG                                 |
//+------------------------------------------------------------------+
void ProcessStateBosDetected()
{
   //--- Expiry check
   if(g_StateBars > InputBosMaxBars)
   {
      Print(">>> BOS EXPIRED | No FVG found in ", g_StateBars,
            " barres > ", InputBosMaxBars);
      ResetState();
      return;
   }

   //--- Check if structural SL has been swept (invalidates setup)
   double lastLow  = iLow(_Symbol, PERIOD_M15, 1);
   double lastHigh = iHigh(_Symbol, PERIOD_M15, 1);
   if(g_StateDirection == +1 && lastLow < g_SwingSL)
   {
      Print(">>> SETUP INVALID | Price swept below structural SL");
      ResetState();
      return;
   }
   if(g_StateDirection == -1 && lastHigh > g_SwingSL)
   {
      Print(">>> SETUP INVALID | Price swept above structural SL");
      ResetState();
      return;
   }

   //--- Scan for FVG
   FVGZone fvg;
   if(DetectFVG(g_StateDirection, fvg))
      PlaceLimitOrder(fvg);
}

//+------------------------------------------------------------------+
//| CHECK BOS - Break of Structure M15                                |
//+------------------------------------------------------------------+
int CheckBOS(int targetDirection)
{
   if(ArraySize(g_SwingHighs) < 1 || ArraySize(g_SwingLows) < 1)
      return 0;

   double currentClose = iClose(_Symbol, PERIOD_M15, 1);

   //--- Bullish BOS: close casse dernier swing high
   if(targetDirection == +1)
   {
      double lastSwingHigh = g_SwingHighs[0].price;
      if(currentClose > lastSwingHigh)
      {
         g_BosLevel = lastSwingHigh;
         Print(">>> BOS BULLISH | Close ", NormalizeDouble(currentClose, _Digits),
               " > SwingHigh ", NormalizeDouble(lastSwingHigh, _Digits),
               " (bar ", g_SwingHighs[0].barIndex, ")");
         return +1;
      }
   }

   //--- Bearish BOS: close casse dernier swing low
   if(targetDirection == -1)
   {
      double lastSwingLow = g_SwingLows[0].price;
      if(currentClose < lastSwingLow)
      {
         g_BosLevel = lastSwingLow;
         Print(">>> BOS BEARISH | Close ", NormalizeDouble(currentClose, _Digits),
               " < SwingLow ", NormalizeDouble(lastSwingLow, _Digits),
               " (bar ", g_SwingLows[0].barIndex, ")");
         return -1;
      }
   }

   return 0;
}

//+------------------------------------------------------------------+
//| UPDATE SWING POINTS M15 (cached per bar)                          |
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
         if(iHigh(_Symbol, PERIOD_M15, i - j) >= high ||
            iHigh(_Symbol, PERIOD_M15, i + j) >= high)
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
         if(iLow(_Symbol, PERIOD_M15, i - j) <= low ||
            iLow(_Symbol, PERIOD_M15, i + j) <= low)
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
//| DETECT FVG - Fair Value Gap on M15                                |
//| Bullish FVG: Low[i] > High[i+2] (gap above)                      |
//| Bearish FVG: High[i] < Low[i+2] (gap below)                      |
//+------------------------------------------------------------------+
bool DetectFVG(int direction, FVGZone &fvg)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist  = stopsLevel * _Point;

   for(int i = 1; i <= InputFvgScanBars; i++)
   {
      double high_i  = iHigh(_Symbol, PERIOD_M15, i);
      double low_i   = iLow(_Symbol, PERIOD_M15, i);
      double high_i2 = iHigh(_Symbol, PERIOD_M15, i + 2);
      double low_i2  = iLow(_Symbol, PERIOD_M15, i + 2);

      if(direction == +1)
      {
         //--- Bullish FVG: Low[i] > High[i+2]
         if(low_i > high_i2)
         {
            double gapSize = (low_i - high_i2) / _Point;
            if(gapSize < InputMinFvgPts) continue;

            fvg.top       = low_i;
            fvg.bottom    = high_i2;
            fvg.entry     = NormalizeDouble((low_i + high_i2) / 2.0, _Digits);
            fvg.direction = +1;

            //--- Validate: entry must be below current ask (valid buy limit)
            if(fvg.entry >= ask - minDist) continue;

            //--- Validate: SL must be below entry
            if(g_SwingSL >= fvg.entry) continue;

            //--- Validate: minimum SL distance
            double slDist = (fvg.entry - g_SwingSL) / _Point;
            if(slDist < InputMinSLPts) continue;

            Print(">>> FVG BULLISH | Top=", NormalizeDouble(fvg.top, _Digits),
                  " | Bottom=", NormalizeDouble(fvg.bottom, _Digits),
                  " | Entry@50%=", NormalizeDouble(fvg.entry, _Digits),
                  " | Gap=", NormalizeDouble(gapSize, 0), " pts | Bar=", i);
            return true;
         }
      }
      else if(direction == -1)
      {
         //--- Bearish FVG: High[i] < Low[i+2]
         if(high_i < low_i2)
         {
            double gapSize = (low_i2 - high_i) / _Point;
            if(gapSize < InputMinFvgPts) continue;

            fvg.top       = low_i2;
            fvg.bottom    = high_i;
            fvg.entry     = NormalizeDouble((low_i2 + high_i) / 2.0, _Digits);
            fvg.direction = -1;

            //--- Validate: entry must be above current bid (valid sell limit)
            if(fvg.entry <= bid + minDist) continue;

            //--- Validate: SL must be above entry
            if(g_SwingSL <= fvg.entry) continue;

            //--- Validate: minimum SL distance
            double slDist = (g_SwingSL - fvg.entry) / _Point;
            if(slDist < InputMinSLPts) continue;

            Print(">>> FVG BEARISH | Top=", NormalizeDouble(fvg.top, _Digits),
                  " | Bottom=", NormalizeDouble(fvg.bottom, _Digits),
                  " | Entry@50%=", NormalizeDouble(fvg.entry, _Digits),
                  " | Gap=", NormalizeDouble(gapSize, 0), " pts | Bar=", i);
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| PLACE LIMIT ORDER at FVG 50%                                      |
//+------------------------------------------------------------------+
void PlaceLimitOrder(FVGZone &fvg)
{
   double entry = fvg.entry;
   double sl    = NormalizeDouble(g_SwingSL, _Digits);

   //--- Calculate distances
   double slDist = MathAbs(entry - sl);
   double tpDist = slDist * InputRiskReward;

   //--- Calculate TP
   double tp;
   if(fvg.direction == +1)
      tp = entry + tpDist;
   else
      tp = entry - tpDist;
   tp = NormalizeDouble(tp, _Digits);

   //--- Calculate lot size
   double lotSize = CalculateLotSize(slDist);

   //--- Place limit order
   bool result = false;
   if(fvg.direction == +1)
      result = trade.BuyLimit(lotSize, entry, _Symbol, sl, tp,
                              ORDER_TIME_GTC, 0, "ICARE PRO Buy");
   else
      result = trade.SellLimit(lotSize, entry, _Symbol, sl, tp,
                               ORDER_TIME_GTC, 0, "ICARE PRO Sell");

   if(result)
   {
      g_PendingTicket = trade.ResultOrder();
      g_PendingBars = 0;
      g_State = STATE_ORDER_PLACED;

      Print(">>> LIMIT ORDER | ", (fvg.direction > 0 ? "BUY_LIMIT" : "SELL_LIMIT"),
            " | #", g_PendingTicket,
            " | Entry=", NormalizeDouble(entry, _Digits),
            " | SL=", NormalizeDouble(sl, _Digits),
            " (", NormalizeDouble(slDist / _Point, 0), " pts structural)",
            " | TP=", NormalizeDouble(tp, _Digits),
            " (1:", InputRiskReward, ")",
            " | Lot=", lotSize,
            " | Risk=", InputRiskPercent, "% = $",
            NormalizeDouble(AccountInfoDouble(ACCOUNT_BALANCE) * InputRiskPercent / 100.0, 2));
   }
   else
   {
      Print(">>> ORDER ERROR: ", trade.ResultRetcodeDescription());
   }
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
//| NEWS FILTER - MQL5 Calendar (live only)                           |
//| Verifie si un evenement high-impact EUR ou USD est proche          |
//+------------------------------------------------------------------+
bool IsNearNews()
{
   //--- Skip in tester/optimizer
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
      return false;

   MqlCalendarValue values[];
   datetime from = TimeCurrent() - InputNewsMinutes * 60;
   datetime to   = TimeCurrent() + InputNewsMinutes * 60;

   //--- Check EUR events
   int totalEur = CalendarValueHistory(values, from, to, NULL, "EUR");
   if(totalEur > 0)
   {
      for(int i = 0; i < totalEur; i++)
      {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
         {
            if(event.importance == CALENDAR_IMPORTANCE_HIGH)
            {
               Print(">>> NEWS | EUR High Impact: ", event.name);
               return true;
            }
         }
      }
   }

   //--- Check USD events
   ArrayResize(values, 0);
   int totalUsd = CalendarValueHistory(values, from, to, NULL, "USD");
   if(totalUsd > 0)
   {
      for(int i = 0; i < totalUsd; i++)
      {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
         {
            if(event.importance == CALENDAR_IMPORTANCE_HIGH)
            {
               Print(">>> NEWS | USD High Impact: ", event.name);
               return true;
            }
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| RESET STATE MACHINE                                               |
//+------------------------------------------------------------------+
void ResetState()
{
   g_State = STATE_IDLE;
   g_StateDirection = 0;
   g_BosLevel = 0;
   g_SwingSL = 0;
   g_StateBars = 0;
}
//+------------------------------------------------------------------+

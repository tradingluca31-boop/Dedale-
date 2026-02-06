//+------------------------------------------------------------------+
//|                                                    Dedale_EA.mq5 |
//|                                                             Luca |
//|        DEDALE V12 - EMA Cross + RSI + ADX + Break-Even (M15)     |
//+------------------------------------------------------------------+
#property copyright "Luca - DEDALE EA v12"
#property version   "12.00"
#property description "EMA 13/50 Cross + RSI Momentum + ADX Trend Power"
#property description "SL = ATR x 1.5 | TP = SL x 3 | Break-Even a 1R"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "=== MONEY MANAGEMENT ==="
input double   InputRiskUSD         = 100.0;    // Risque fixe par trade ($)
input double   InputRewardRatio     = 3.0;      // Ratio R:R (TP = SL x 3)
input int      InputMagicNumber     = 111111;   // ID Unique

input group "=== STRATEGIE ==="
input int      InputEmaFast         = 13;       // EMA rapide (Fibonacci)
input int      InputEmaSlow         = 50;       // EMA lente (Institutionnel)
input int      InputRsiPeriod       = 14;       // RSI periode
input int      InputRsiLevel        = 50;       // RSI seuil momentum
input int      InputAtrPeriod       = 14;       // ATR periode
input double   InputAtrMultSL       = 1.5;      // Multiplicateur ATR pour SL
input int      InputAdxPeriod       = 14;       // ADX periode
input int      InputAdxThreshold    = 20;       // ADX seuil minimum (< 20 = range)

input group "=== BREAK-EVEN ==="
input bool     UseBreakEven         = true;     // Activer Break-Even
input double   BreakEvenTriggerRatio = 1.0;     // BE se declenche a X fois le SL (1.0 = 1R)
input int      BreakEvenBufferPts   = 10;       // Buffer BE (points, couvre commissions)

input group "=== FILTRES ==="
input int      InputStartHour       = 9;        // Heure debut trading
input int      InputEndHour         = 21;       // Heure fin trading
input int      InputMaxDailyTrades  = 1;        // Max trades par jour
input int      InputMaxSpread       = 30;       // Spread max (points)

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                                |
//+------------------------------------------------------------------+
CTrade         trade;
int            handleEmaFast;
int            handleEmaSlow;
int            handleRsi;
int            handleAtr;
int            handleAdx;

//+------------------------------------------------------------------+
//| INITIALISATION                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   handleEmaFast = iMA(_Symbol, _Period, InputEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   handleEmaSlow = iMA(_Symbol, _Period, InputEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   handleRsi     = iRSI(_Symbol, _Period, InputRsiPeriod, PRICE_CLOSE);
   handleAtr     = iATR(_Symbol, _Period, InputAtrPeriod);
   handleAdx     = iADX(_Symbol, _Period, InputAdxPeriod);

   if(handleEmaFast == INVALID_HANDLE || handleEmaSlow == INVALID_HANDLE ||
      handleRsi == INVALID_HANDLE || handleAtr == INVALID_HANDLE ||
      handleAdx == INVALID_HANDLE)
   {
      Print("ERREUR: Impossible de creer les indicateurs.");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(InputMagicNumber);
   trade.SetDeviationInPoints(15);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   Print(">> DEDALE V12 | EMA ", InputEmaFast, "/", InputEmaSlow,
         " + RSI", InputRsiPeriod, " + ADX>", InputAdxThreshold,
         " | SL=ATRx", InputAtrMultSL, " | TP=SLx", InputRewardRatio,
         " | Risk=$", InputRiskUSD, " | BE=", UseBreakEven);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| DEINITIALISATION                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleEmaFast != INVALID_HANDLE) IndicatorRelease(handleEmaFast);
   if(handleEmaSlow != INVALID_HANDLE) IndicatorRelease(handleEmaSlow);
   if(handleRsi != INVALID_HANDLE)     IndicatorRelease(handleRsi);
   if(handleAtr != INVALID_HANDLE)     IndicatorRelease(handleAtr);
   if(handleAdx != INVALID_HANDLE)     IndicatorRelease(handleAdx);
}

//+------------------------------------------------------------------+
//| ONTICK                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- GESTION DES POSITIONS OUVERTES (Break-Even) - a chaque tick
   ManagePositions();

   //--- LOGIQUE D'ENTREE - seulement si pas de position
   EntryLogic();
}

//+------------------------------------------------------------------+
//| GESTION DES POSITIONS (Break-Even)                                |
//+------------------------------------------------------------------+
void ManagePositions()
{
   if(!UseBreakEven) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PositionGetSymbol(i) == _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InputMagicNumber) continue;

      ulong  ticket    = PositionGetInteger(POSITION_TICKET);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      double current   = PositionGetDouble(POSITION_PRICE_CURRENT);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      //--- Calculer la distance SL initiale
      double slDistance = MathAbs(openPrice - sl);
      if(slDistance == 0) continue;

      //--- Distance de declenchement du BE
      double triggerDistance = slDistance * BreakEvenTriggerRatio;
      double buffer = BreakEvenBufferPts * _Point;

      if(type == POSITION_TYPE_BUY)
      {
         //--- Le prix a atteint +1R ?
         if(current >= openPrice + triggerDistance)
         {
            double newSL = openPrice + buffer;
            //--- Ne deplacer que si le nouveau SL est mieux que l'ancien
            if(newSL > sl)
            {
               trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), tp);
               Print(">>> BE ACTIVE [BUY] | SL deplace a ", NormalizeDouble(newSL, _Digits), " (+", BreakEvenBufferPts, " pts)");
            }
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         if(current <= openPrice - triggerDistance)
         {
            double newSL = openPrice - buffer;
            if(newSL < sl)
            {
               trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), tp);
               Print(">>> BE ACTIVE [SELL] | SL deplace a ", NormalizeDouble(newSL, _Digits), " (-", BreakEvenBufferPts, " pts)");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| LOGIQUE D'ENTREE                                                  |
//+------------------------------------------------------------------+
void EntryLogic()
{
   //--- Position deja ouverte ?
   if(CountPositions() > 0) return;

   //--- Deja trade aujourd'hui ?
   if(CountTodayTrades() >= InputMaxDailyTrades) return;

   //--- Filtre horaire
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.hour < InputStartHour || dt.hour >= InputEndHour) return;

   //--- Filtre spread
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InputMaxSpread) return;

   //--- Nouvelle bougie seulement
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, _Period, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;

   //--- Charger les indicateurs
   double emaFast[], emaSlow[], rsi[], atr[], adx[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(adx, true);

   if(CopyBuffer(handleEmaFast, 0, 0, 3, emaFast) < 3) return;
   if(CopyBuffer(handleEmaSlow, 0, 0, 3, emaSlow) < 3) return;
   if(CopyBuffer(handleRsi, 0, 0, 3, rsi) < 3) return;
   if(CopyBuffer(handleAtr, 0, 0, 3, atr) < 3) return;
   if(CopyBuffer(handleAdx, 0, 0, 3, adx) < 3) return;  // ADX main line (index 0)

   //--- Valeurs bougies cloturees
   bool crossUp   = (emaFast[2] <= emaSlow[2] && emaFast[1] > emaSlow[1]);
   bool crossDown = (emaFast[2] >= emaSlow[2] && emaFast[1] < emaSlow[1]);

   double rsiVal = rsi[1];
   double atrVal = atr[1];
   double adxVal = adx[1];

   if(atrVal <= 0) return;

   //--- FILTRE ADX : Marche en tendance ?
   if(adxVal < InputAdxThreshold)
   {
      if(crossUp || crossDown)
         Print(">>> SIGNAL IGNORE | ADX=", NormalizeDouble(adxVal, 1), " < ", InputAdxThreshold, " (marche en range)");
      return;
   }

   //--- SIGNAL ACHAT : EMA cross UP + RSI > 50 + ADX > 20
   if(crossUp && rsiVal > InputRsiLevel)
   {
      Print(">>> SIGNAL BUY | EMA", InputEmaFast, " cross UP EMA", InputEmaSlow,
            " | RSI=", NormalizeDouble(rsiVal, 1),
            " | ADX=", NormalizeDouble(adxVal, 1));
      ExecuteTrade(ORDER_TYPE_BUY, atrVal);
   }
   //--- SIGNAL VENTE : EMA cross DOWN + RSI < 50 + ADX > 20
   else if(crossDown && rsiVal < InputRsiLevel)
   {
      Print(">>> SIGNAL SELL | EMA", InputEmaFast, " cross DOWN EMA", InputEmaSlow,
            " | RSI=", NormalizeDouble(rsiVal, 1),
            " | ADX=", NormalizeDouble(adxVal, 1));
      ExecuteTrade(ORDER_TYPE_SELL, atrVal);
   }
}

//+------------------------------------------------------------------+
//| EXECUTION DU TRADE                                                |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double atrValue)
{
   double price, sl, tp;
   double slDistance = atrValue * InputAtrMultSL;

   if(type == ORDER_TYPE_BUY)
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl    = price - slDistance;
      tp    = price + (slDistance * InputRewardRatio);
   }
   else
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl    = price + slDistance;
      tp    = price - (slDistance * InputRewardRatio);
   }

   price = NormalizeDouble(price, _Digits);
   sl    = NormalizeDouble(sl, _Digits);
   tp    = NormalizeDouble(tp, _Digits);

   double lotSize = CalculateLotSizeFixedRisk(slDistance);

   bool result;
   if(type == ORDER_TYPE_BUY)
      result = trade.Buy(lotSize, _Symbol, price, sl, tp, "DEDALE Buy");
   else
      result = trade.Sell(lotSize, _Symbol, price, sl, tp, "DEDALE Sell");

   if(result)
      Print(">>> TRADE OUVERT | ", (type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
            " | Lot: ", lotSize,
            " | SL: ", NormalizeDouble(slDistance / _Point, 0), " pts",
            " | TP: ", NormalizeDouble(slDistance * InputRewardRatio / _Point, 0), " pts",
            " | Risque: $", InputRiskUSD);
   else
      Print(">>> ERREUR TRADE: ", trade.ResultRetcodeDescription());
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

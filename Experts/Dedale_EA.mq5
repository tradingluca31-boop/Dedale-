//+------------------------------------------------------------------+
//|                                                    Dedale_EA.mq5 |
//|                                                             Luca |
//|                  DEDALE V10 - Trend Breakout H1 (Donchian + EMA) |
//+------------------------------------------------------------------+
#property copyright "Luca - DEDALE EA v10"
#property version   "10.00"
#property description "DEDALE - Trend Breakout sur H1"
#property description "EMA200 filtre tendance | Donchian 24h breakout"
#property description "SL = ATR x 1.5 | TP = SL x 3 (R:R 1:3)"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "=== MONEY MANAGEMENT ==="
input double   InpRiskPercent    = 1.0;      // Risque par trade (% du capital)
input double   InpRewardRatio    = 3.0;      // Ratio Gain (3.0 = TP est 3x le SL)
input int      InpMagicNumber    = 888888;   // ID Unique de l'EA

input group "=== STRATEGIE ==="
input int      InpEmaPeriod      = 200;      // EMA tendance de fond
input int      InpDonchianPeriod = 24;       // Donchian breakout (24 bougies H1 = 24h)
input int      InpAtrPeriod      = 14;       // ATR volatilite
input double   InpAtrMultiplier  = 1.5;      // Multiplicateur ATR pour le SL

input group "=== FILTRES ==="
input int      InpStartHour      = 9;        // Heure debut trading (heure serveur)
input int      InpEndHour        = 20;       // Heure fin trading (heure serveur)
input int      InpMaxDailyTrades = 1;        // Max trades par jour
input int      InpMaxSpread      = 30;       // Spread max (points)

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                                |
//+------------------------------------------------------------------+
CTrade         trade;
int            handleEMA;
int            handleATR;
double         bufferEMA[];
double         bufferATR[];

//+------------------------------------------------------------------+
//| INITIALISATION                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   handleEMA = iMA(_Symbol, _Period, InpEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handleATR = iATR(_Symbol, _Period, InpAtrPeriod);

   if(handleEMA == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("ERREUR: Impossible de creer les indicateurs.");
      return(INIT_FAILED);
   }

   ArraySetAsSeries(bufferEMA, true);
   ArraySetAsSeries(bufferATR, true);

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(15);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   Print(">> DEDALE V10 initialise | EMA", InpEmaPeriod, " + Donchian", InpDonchianPeriod, " | RR 1:", InpRewardRatio);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| DEINITIALISATION                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleEMA != INVALID_HANDLE) IndicatorRelease(handleEMA);
   if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);
   Print(">> DEDALE V10 arrete.");
}

//+------------------------------------------------------------------+
//| ONTICK - Logique principale                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 1. Position deja ouverte ? On attend
   if(CountPositions() > 0) return;

   //--- 2. Deja trade aujourd'hui ?
   if(CountTodayTrades() >= InpMaxDailyTrades) return;

   //--- 3. Filtre horaire
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.hour < InpStartHour || dt.hour >= InpEndHour) return;

   //--- 4. Filtre spread
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread) return;

   //--- 5. Nouvelle bougie H1 seulement (eviter multi-entrees sur meme bougie)
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, _Period, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;

   //--- 6. Charger indicateurs
   if(CopyBuffer(handleEMA, 0, 0, 3, bufferEMA) < 3) return;
   if(CopyBuffer(handleATR, 0, 0, 3, bufferATR) < 3) return;

   double emaVal = bufferEMA[1];
   double atrVal = bufferATR[1];

   if(atrVal <= 0) return;

   //--- 7. Donchian Channel (plus haut/bas des N dernieres bougies cloturees)
   double highestHigh = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, InpDonchianPeriod, 1));
   double lowestLow   = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, InpDonchianPeriod, 1));

   double close1 = iClose(_Symbol, _Period, 1);

   //--- 8. SIGNAL ACHAT : Close > EMA200 + Close casse le Donchian High
   if(close1 > emaVal && close1 > highestHigh)
   {
      Print(">>> SIGNAL BUY | Close: ", close1, " > EMA200: ", NormalizeDouble(emaVal, 2), " | Breakout > ", NormalizeDouble(highestHigh, 2));
      ExecuteTrade(ORDER_TYPE_BUY, atrVal);
   }
   //--- 9. SIGNAL VENTE : Close < EMA200 + Close casse le Donchian Low
   else if(close1 < emaVal && close1 < lowestLow)
   {
      Print(">>> SIGNAL SELL | Close: ", close1, " < EMA200: ", NormalizeDouble(emaVal, 2), " | Breakout < ", NormalizeDouble(lowestLow, 2));
      ExecuteTrade(ORDER_TYPE_SELL, atrVal);
   }
}

//+------------------------------------------------------------------+
//| EXECUTION DU TRADE                                                |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double atr)
{
   double price, sl, tp;
   double slDistance = atr * InpAtrMultiplier;

   if(type == ORDER_TYPE_BUY)
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl    = price - slDistance;
      tp    = price + (slDistance * InpRewardRatio);
   }
   else
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl    = price + slDistance;
      tp    = price - (slDistance * InpRewardRatio);
   }

   price = NormalizeDouble(price, _Digits);
   sl    = NormalizeDouble(sl, _Digits);
   tp    = NormalizeDouble(tp, _Digits);

   double lotSize = CalculateLotSize(slDistance);

   bool result;
   if(type == ORDER_TYPE_BUY)
      result = trade.Buy(lotSize, _Symbol, price, sl, tp, "DEDALE Buy");
   else
      result = trade.Sell(lotSize, _Symbol, price, sl, tp, "DEDALE Sell");

   if(result)
      Print(">>> TRADE OUVERT | Lot: ", lotSize, " | SL: ", sl, " (", NormalizeDouble(slDistance/_Point, 0), " pts) | TP: ", tp, " | RR 1:", InpRewardRatio);
   else
      Print(">>> ERREUR TRADE: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| CALCUL DU LOT (risque exact en %)                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistancePrice)
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPercent / 100.0);

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize == 0 || tickValue == 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double slPoints = slDistancePrice / tickSize;
   double lot = riskMoney / (slPoints * tickValue);

   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / lotStep) * lotStep;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;

   return lot;
}

//+------------------------------------------------------------------+
//| COMPTER LES POSITIONS OUVERTES (magic number)                     |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol)
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| COMPTER LES TRADES DU JOUR (magic number)                         |
//+------------------------------------------------------------------+
int CountTodayTrades()
{
   int count = 0;
   datetime startOfDay = iTime(_Symbol, PERIOD_D1, 0);
   HistorySelect(startOfDay, TimeCurrent());

   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber)
      {
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
            count++;
      }
   }
   return count;
}
//+------------------------------------------------------------------+

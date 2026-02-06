//+------------------------------------------------------------------+
//|                                                    Dedale_EA.mq5 |
//|                                                             Luca |
//|              DEDALE V11 - EMA Cross + RSI Momentum (M15)         |
//+------------------------------------------------------------------+
#property copyright "Luca - DEDALE EA v11"
#property version   "11.00"
#property description "DEDALE - Day Trading de Tendance sur XAUUSD M15"
#property description "EMA 13/50 Cross + RSI Momentum Filter"
#property description "SL = ATR x 1.5 | TP = SL x 3 | Risque fixe en $"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "=== MONEY MANAGEMENT ==="
input double   InputRiskUSD      = 100.0;    // Risque fixe par trade ($)
input double   InputRewardRatio  = 3.0;      // Ratio R:R (3.0 = TP est 3x le SL)
input int      InputMagicNumber  = 111111;   // ID Unique de l'EA

input group "=== STRATEGIE ==="
input int      InputEmaFast      = 13;       // EMA rapide (Fibonacci)
input int      InputEmaSlow      = 50;       // EMA lente (Institutionnel)
input int      InputRsiPeriod    = 14;       // RSI periode
input int      InputRsiLevel     = 50;       // RSI seuil momentum
input int      InputAtrPeriod    = 14;       // ATR periode (volatilite)
input double   InputAtrMultSL    = 1.5;      // Multiplicateur ATR pour SL

input group "=== FILTRES ==="
input int      InputStartHour    = 9;        // Heure debut trading (serveur)
input int      InputEndHour      = 21;       // Heure fin trading (serveur)
input int      InputMaxDailyTrades = 1;      // Max trades par jour
input int      InputMaxSpread    = 30;       // Spread max (points)

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                                |
//+------------------------------------------------------------------+
CTrade         trade;
int            handleEmaFast;
int            handleEmaSlow;
int            handleRsi;
int            handleAtr;

//+------------------------------------------------------------------+
//| INITIALISATION                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicateurs
   handleEmaFast = iMA(_Symbol, _Period, InputEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   handleEmaSlow = iMA(_Symbol, _Period, InputEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   handleRsi     = iRSI(_Symbol, _Period, InputRsiPeriod, PRICE_CLOSE);
   handleAtr     = iATR(_Symbol, _Period, InputAtrPeriod);

   if(handleEmaFast == INVALID_HANDLE || handleEmaSlow == INVALID_HANDLE ||
      handleRsi == INVALID_HANDLE || handleAtr == INVALID_HANDLE)
   {
      Print("ERREUR: Impossible de creer les indicateurs.");
      return(INIT_FAILED);
   }

   //--- Config trade
   trade.SetExpertMagicNumber(InputMagicNumber);
   trade.SetDeviationInPoints(15);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   Print(">> DEDALE V11 | EMA ", InputEmaFast, "/", InputEmaSlow,
         " + RSI", InputRsiPeriod, " | SL=ATRx", InputAtrMultSL,
         " | TP=SLx", InputRewardRatio, " | Risk=$", InputRiskUSD);
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
}

//+------------------------------------------------------------------+
//| ONTICK - Logique principale                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 1. Position deja ouverte ?
   if(CountPositions() > 0) return;

   //--- 2. Deja trade aujourd'hui ?
   if(CountTodayTrades() >= InputMaxDailyTrades) return;

   //--- 3. Filtre horaire
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.hour < InputStartHour || dt.hour >= InputEndHour) return;

   //--- 4. Filtre spread
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InputMaxSpread) return;

   //--- 5. Nouvelle bougie seulement (eviter multi-entrees)
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, _Period, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;

   //--- 6. Charger les indicateurs (3 bougies pour detecter le cross)
   double emaFast[], emaSlow[], rsi[], atr[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(handleEmaFast, 0, 0, 3, emaFast) < 3) return;
   if(CopyBuffer(handleEmaSlow, 0, 0, 3, emaSlow) < 3) return;
   if(CopyBuffer(handleRsi, 0, 0, 3, rsi) < 3) return;
   if(CopyBuffer(handleAtr, 0, 0, 3, atr) < 3) return;

   //--- 7. Detection du croisement EMA (sur bougies cloturees: index 1 et 2)
   // Index 2 = avant-derniere bougie, Index 1 = derniere bougie cloturee
   bool crossUp   = (emaFast[2] <= emaSlow[2] && emaFast[1] > emaSlow[1]);
   bool crossDown = (emaFast[2] >= emaSlow[2] && emaFast[1] < emaSlow[1]);

   double rsiVal = rsi[1];
   double atrVal = atr[1];

   if(atrVal <= 0) return;

   //--- 8. SIGNAL ACHAT : EMA13 croise EMA50 a la hausse + RSI > 50
   if(crossUp && rsiVal > InputRsiLevel)
   {
      Print(">>> SIGNAL BUY | EMA", InputEmaFast, " cross UP EMA", InputEmaSlow,
            " | RSI=", NormalizeDouble(rsiVal, 1),
            " | ATR=", NormalizeDouble(atrVal, 2));
      ExecuteTrade(ORDER_TYPE_BUY, atrVal);
   }
   //--- 9. SIGNAL VENTE : EMA13 croise EMA50 a la baisse + RSI < 50
   else if(crossDown && rsiVal < InputRsiLevel)
   {
      Print(">>> SIGNAL SELL | EMA", InputEmaFast, " cross DOWN EMA", InputEmaSlow,
            " | RSI=", NormalizeDouble(rsiVal, 1),
            " | ATR=", NormalizeDouble(atrVal, 2));
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
//| CALCUL DU LOT - Risque fixe en $ (precis pour Gold)               |
//+------------------------------------------------------------------+
double CalculateLotSizeFixedRisk(double slDistance)
{
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize == 0 || tickValue == 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   // Nombre de ticks dans le SL
   double slTicks = slDistance / tickSize;

   // Lot = Risque$ / (Ticks SL * Valeur du tick par lot)
   double lot = InputRiskUSD / (slTicks * tickValue);

   // Arrondir au pas de lot
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / lotStep) * lotStep;

   // Bornes
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

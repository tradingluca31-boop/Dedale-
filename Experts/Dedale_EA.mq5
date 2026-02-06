//+------------------------------------------------------------------+
//|                                                    Dedale_EA.mq5 |
//|                                                             Luca |
//|          DEDALE V14 - Gold Sniper Recovery (Session US)          |
//+------------------------------------------------------------------+
#property copyright "Luca - DEDALE EA v14"
#property version   "14.00"
#property description "Sniper: Session US 13h-18h uniquement"
#property description "EMA13/50 Cross + Bougie Impulsion + ADX>25 + EMA200 H1"
#property description "Placer sur graphique M15"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "=== MONEY MANAGEMENT ==="
input double   InputRiskUSD         = 50.0;     // Risque fixe par trade ($) - reduit pour recovery
input double   InputRewardRatio     = 3.0;      // Ratio R:R (TP = SL x 3)
input int      InputMagicNumber     = 111111;   // ID Unique

input group "=== H1 TREND FILTER ==="
input int      InputH1EmaPeriod     = 200;      // EMA H1 (tendance majeure)

input group "=== M15 ENTRY SIGNAL ==="
input int      InputEmaFast         = 13;       // EMA rapide M15
input int      InputEmaSlow         = 50;       // EMA lente M15
input int      InputRsiPeriod       = 14;       // RSI M15
input int      InputRsiLevel        = 50;       // RSI seuil momentum
input int      InputAdxPeriod       = 14;       // ADX M15
input int      InputAdxThreshold    = 25;       // ADX minimum (25 = plus strict)
input int      InputAtrPeriod       = 14;       // ATR M15
input double   InputAtrMultSL       = 1.5;      // Multiplicateur ATR pour SL

input group "=== FILTRE BOUGIE IMPULSION ==="
input int      MinCandleSizePoints  = 100;      // Taille min du corps (points = 10 pips)

input group "=== BREAK-EVEN ==="
input bool     UseBreakEven         = true;     // Activer Break-Even
input double   BreakEvenTriggerRatio = 1.0;     // BE a 1R
input int      BreakEvenBufferPts   = 20;       // Buffer BE (20 points)

input group "=== FILTRES ==="
input int      InputStartHour       = 13;       // Session US debut (13h)
input int      InputEndHour         = 18;       // Session US fin (18h)
input int      InputMaxDailyTrades  = 1;        // Max 1 trade par jour
input int      InputMaxSpread       = 30;       // Spread max (points)

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                                |
//+------------------------------------------------------------------+
CTrade         trade;
int            handleH1Ema;
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
   handleH1Ema   = iMA(_Symbol, PERIOD_H1, InputH1EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handleEmaFast = iMA(_Symbol, PERIOD_M15, InputEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   handleEmaSlow = iMA(_Symbol, PERIOD_M15, InputEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   handleRsi     = iRSI(_Symbol, PERIOD_M15, InputRsiPeriod, PRICE_CLOSE);
   handleAtr     = iATR(_Symbol, PERIOD_M15, InputAtrPeriod);
   handleAdx     = iADX(_Symbol, PERIOD_M15, InputAdxPeriod);

   if(handleH1Ema == INVALID_HANDLE || handleEmaFast == INVALID_HANDLE ||
      handleEmaSlow == INVALID_HANDLE || handleRsi == INVALID_HANDLE ||
      handleAtr == INVALID_HANDLE || handleAdx == INVALID_HANDLE)
   {
      Print("ERREUR: Impossible de creer les indicateurs.");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(InputMagicNumber);
   trade.SetDeviationInPoints(15);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   Print(">> DEDALE V14 SNIPER | Session ", InputStartHour, "h-", InputEndHour, "h",
         " | H1: EMA", InputH1EmaPeriod,
         " | M15: EMA", InputEmaFast, "/", InputEmaSlow,
         " + ADX>", InputAdxThreshold,
         " + MinCandle=", MinCandleSizePoints, "pts",
         " | Risk=$", InputRiskUSD);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| DEINITIALISATION                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleH1Ema != INVALID_HANDLE)   IndicatorRelease(handleH1Ema);
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
   ManagePositions();
   EntryLogic();
}

//+------------------------------------------------------------------+
//| BREAK-EVEN                                                        |
//+------------------------------------------------------------------+
void ManagePositions()
{
   if(!UseBreakEven) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InputMagicNumber) continue;

      ulong  ticket    = PositionGetInteger(POSITION_TICKET);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      double current   = PositionGetDouble(POSITION_PRICE_CURRENT);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double slDistance = MathAbs(openPrice - sl);
      if(slDistance == 0) continue;

      double triggerDist = slDistance * BreakEvenTriggerRatio;
      double buffer = BreakEvenBufferPts * _Point;

      if(type == POSITION_TYPE_BUY && current >= openPrice + triggerDist)
      {
         double newSL = openPrice + buffer;
         if(newSL > sl)
         {
            trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), tp);
            Print(">>> BE [BUY] | SL -> ", NormalizeDouble(newSL, _Digits));
         }
      }
      else if(type == POSITION_TYPE_SELL && current <= openPrice - triggerDist)
      {
         double newSL = openPrice - buffer;
         if(newSL < sl)
         {
            trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), tp);
            Print(">>> BE [SELL] | SL -> ", NormalizeDouble(newSL, _Digits));
         }
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

   //--- Filtre horaire SESSION US (13h-18h)
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.hour < InputStartHour || dt.hour >= InputEndHour)
   {
      return;
   }

   //--- Filtre spread
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InputMaxSpread) return;

   //--- Nouvelle bougie M15 seulement
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_M15, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;

   //=== ETAPE 1: H1 TREND (EMA 200) ===
   double h1Ema[];
   ArraySetAsSeries(h1Ema, true);
   if(CopyBuffer(handleH1Ema, 0, 0, 2, h1Ema) < 2) return;

   double currentPrice = iClose(_Symbol, PERIOD_M15, 1);
   bool h1Bullish = (currentPrice > h1Ema[0]);
   bool h1Bearish = (currentPrice < h1Ema[0]);

   //=== ETAPE 2: M15 INDICATORS ===
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
   if(CopyBuffer(handleAdx, 0, 0, 3, adx) < 3) return;

   bool crossUp   = (emaFast[2] <= emaSlow[2] && emaFast[1] > emaSlow[1]);
   bool crossDown = (emaFast[2] >= emaSlow[2] && emaFast[1] < emaSlow[1]);

   double rsiVal = rsi[1];
   double atrVal = atr[1];
   double adxVal = adx[1];

   if(atrVal <= 0) return;

   //--- Pas de cross ? On sort
   if(!crossUp && !crossDown) return;

   //=== ETAPE 3: FILTRE ADX (puissance) ===
   if(adxVal < InputAdxThreshold)
   {
      Print(">>> IGNORE | ADX=", NormalizeDouble(adxVal, 1), " < ", InputAdxThreshold, " (range/pas de force)");
      return;
   }

   //=== ETAPE 4: FILTRE BOUGIE IMPULSION ===
   double open1  = iOpen(_Symbol, PERIOD_M15, 1);
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double candleBody = MathAbs(close1 - open1) / _Point;

   if(candleBody < MinCandleSizePoints)
   {
      Print(">>> IGNORE | Bougie trop petite: ", NormalizeDouble(candleBody, 0), " pts < ", MinCandleSizePoints, " pts");
      return;
   }

   //=== ETAPE 5: SIGNAUX ===

   //--- BUY : H1 bullish + Cross UP + RSI > 50 + ADX > 25 + Grosse bougie
   if(h1Bullish && crossUp && rsiVal > InputRsiLevel)
   {
      Print(">>> BUY SIGNAL | H1: Prix>EMA", InputH1EmaPeriod,
            " | Cross UP | RSI=", NormalizeDouble(rsiVal, 1),
            " | ADX=", NormalizeDouble(adxVal, 1),
            " | Bougie=", NormalizeDouble(candleBody, 0), "pts");
      ExecuteTrade(ORDER_TYPE_BUY, atrVal);
   }
   //--- SELL : H1 bearish + Cross DOWN + RSI < 50 + ADX > 25 + Grosse bougie
   else if(h1Bearish && crossDown && rsiVal < InputRsiLevel)
   {
      Print(">>> SELL SIGNAL | H1: Prix<EMA", InputH1EmaPeriod,
            " | Cross DOWN | RSI=", NormalizeDouble(rsiVal, 1),
            " | ADX=", NormalizeDouble(adxVal, 1),
            " | Bougie=", NormalizeDouble(candleBody, 0), "pts");
      ExecuteTrade(ORDER_TYPE_SELL, atrVal);
   }
   //--- Bloque par H1
   else if(crossUp && rsiVal > InputRsiLevel && !h1Bullish)
   {
      Print(">>> BUY BLOQUE | H1 bearish (Prix < EMA200 H1)");
   }
   else if(crossDown && rsiVal < InputRsiLevel && !h1Bearish)
   {
      Print(">>> SELL BLOQUE | H1 bullish (Prix > EMA200 H1)");
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
      Print(">>> OUVERT | ", (type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
            " | Lot: ", lotSize,
            " | SL: ", NormalizeDouble(slDistance / _Point, 0), " pts",
            " | TP: ", NormalizeDouble(slDistance * InputRewardRatio / _Point, 0), " pts",
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

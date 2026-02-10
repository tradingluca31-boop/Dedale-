//+------------------------------------------------------------------+
//|                                                     Icare_EA.mq5 |
//|                                                             Luca |
//|    ICARE V3 - Institutional MTF: Structure + POI + ChoCH + FVG   |
//|    EURUSD M15 - Smart Money Confluence                            |
//+------------------------------------------------------------------+
#property copyright "Luca - ICARE V3"
#property version   "3.00"
#property description "Trend Filter (EMA50 H4 / SMMA50 H1) + Confluence"
#property description "H4 Structure + POI + M15 ChoCH + FVG Limit Order"
#property description "Placer sur graphique M15 - EURUSD"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "=== MONEY MANAGEMENT ==="
input double   InputRiskPercent      = 1.0;      // Risk % du capital
input double   InputRiskReward       = 3.0;      // R:R (TP = SL x 3)
input int      InputMagicNumber      = 333333;   // Magic Number V3

input group "=== TREND FILTER (obligatoire) ==="
input int      InputTrendMode        = 0;        // 0=EMA50 H4, 1=SMMA50 H1
input int      InputH4EmaPeriod      = 50;       // EMA period H4 (mode 0)
input int      InputH1SmmaPeriod     = 50;       // SMMA period H1 (mode 1)

input group "=== CONFLUENCE H1: EMA CROSS ==="
input bool     InputH1CrossOn        = true;     // Activer signal H1 EMA Cross
input int      InputH1CrossFast      = 20;       // EMA rapide H1
input int      InputH1CrossSlow      = 50;       // EMA lente H1
input int      InputH1CrossLookback  = 10;       // Lookback cross (barres H1)

input group "=== CONFLUENCE H4: STRUCTURE ==="
input bool     InputH4BosOn          = true;     // Activer H4 BOS signal
input int      InputH4SwingStrength  = 3;        // Swing strength H4
input int      InputH4SwingLookback  = 50;       // Swing lookback H4

input group "=== CONFLUENCE: DISCOUNT/PREMIUM ==="
input bool     InputDiscountOn       = true;     // Activer zone Discount/Premium

input group "=== CONFLUENCE SCORE ==="
input int      InputMinConfluence    = 2;        // Score min (max 3 signaux)

input group "=== M15 SMART MONEY ENTRY ==="
input int      InputM15SwingStrength = 3;        // Swing strength M15
input int      InputM15SwingLookback = 30;       // Swing lookback M15
input int      InputPoiMaxBars       = 30;       // Max barres attente ChoCH
input int      InputFvgScanBars      = 10;       // FVG scan range
input int      InputMinFvgPts        = 10;       // FVG taille min (pts = 1 pip)
input int      InputFvgMaxBars       = 10;       // Max barres scan FVG apres ChoCH
input int      InputPendingExpiry    = 10;       // Annuler limit apres N barres

input group "=== LIQUIDITY (IDM) ==="
input bool     InputIdmFilter        = true;     // Activer filtre sweep liquidite
input int      InputIdmLookback      = 20;       // Lookback sweep (barres M15)

input group "=== STOP LOSS ==="
input int      InputSlBufferPts      = 20;       // Buffer SL (pts = 2 pips)
input int      InputMinSLPts         = 50;       // SL minimum (pts = 5 pips)
input int      InputAtrPeriod        = 14;       // ATR period H1
input double   InputAtrMultSL        = 1.5;      // Multiplicateur ATR pour SL (H1)

input group "=== BREAK-EVEN ==="
input double   InputBeTriggerR       = 1.5;      // BE a 1.5R (0 = off)
input int      InputBeBufferPts      = 20;       // Buffer BE (pts = 2 pips)

input group "=== FILTRES ==="
input int      InputStartHour        = 9;        // Session debut
input int      InputEndHour          = 17;       // Session fin
input int      InputMaxDailyTrades   = 1;        // Max trades/jour
input int      InputMaxSpread        = 12;       // Spread max (pts = 1.2 pips)
input int      InputMaxTradeHours    = 96;       // Duree max position (heures)

input group "=== NEWS FILTER ==="
input bool     InputNewsFilter       = true;     // News filter (live only)
input int      InputNewsMinutes      = 30;       // Buffer news (min)

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
   double   top;
   double   bottom;
   double   entry;       // 50% level
   int      direction;   // +1 bullish, -1 bearish
};

enum TradeState
{
   STATE_IDLE,             // Attente conditions
   STATE_AWAITING_CHOCH,   // Dans zone, attente ChoCH M15
   STATE_SCANNING_FVG,     // ChoCH fait, scan FVG
   STATE_ORDER_PLACED      // Limit order actif
};

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                                |
//+------------------------------------------------------------------+
CTrade         trade;

//--- Indicator handles
int            handleTrendFilter;    // EMA50 H4 ou SMMA50 H1
int            handleH1EmaFast;      // EMA20 H1 (cross)
int            handleH1EmaSlow;      // EMA50 H1 (cross)
int            handleH1Atr;          // ATR H1 (SL volatilite)

//--- H4 Structure
SwingPoint     g_H4SwingHighs[];
SwingPoint     g_H4SwingLows[];
datetime       g_H4LastSwingScan;
int            g_H4Trend;            // +1 bull, -1 bear, 0 undefined
double         g_H4RangeHigh;
double         g_H4RangeLow;
double         g_H4Equilibrium;

//--- H4 POI (Order Block)
double         g_PoiTop;
double         g_PoiBottom;
bool           g_PoiValid;

//--- M15 Swings
SwingPoint     g_M15SwingHighs[];
SwingPoint     g_M15SwingLows[];
datetime       g_M15LastSwingScan;

//--- State machine
TradeState     g_State;
int            g_StateDirection;
double         g_SwingSL;            // SL structurel M15
int            g_StateBars;

//--- Pending order
ulong          g_PendingTicket;
int            g_PendingBars;

//+------------------------------------------------------------------+
//| INITIALISATION                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Trend filter
   if(InputTrendMode == 0)
      handleTrendFilter = iMA(_Symbol, PERIOD_H4, InputH4EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   else
      handleTrendFilter = iMA(_Symbol, PERIOD_H1, InputH1SmmaPeriod, 0, MODE_SMMA, PRICE_CLOSE);

   if(handleTrendFilter == INVALID_HANDLE)
   {
      Print("ERREUR: Trend filter indicator");
      return(INIT_FAILED);
   }

   //--- H1 Cross indicators
   handleH1EmaFast = INVALID_HANDLE;
   handleH1EmaSlow = INVALID_HANDLE;
   if(InputH1CrossOn)
   {
      handleH1EmaFast = iMA(_Symbol, PERIOD_H1, InputH1CrossFast, 0, MODE_EMA, PRICE_CLOSE);
      handleH1EmaSlow = iMA(_Symbol, PERIOD_H1, InputH1CrossSlow, 0, MODE_EMA, PRICE_CLOSE);
      if(handleH1EmaFast == INVALID_HANDLE || handleH1EmaSlow == INVALID_HANDLE)
      {
         Print("ERREUR: H1 Cross indicators");
         return(INIT_FAILED);
      }
   }

   //--- ATR H1
   handleH1Atr = iATR(_Symbol, PERIOD_H1, InputAtrPeriod);
   if(handleH1Atr == INVALID_HANDLE)
   {
      Print("ERREUR: ATR H1 indicator");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(InputMagicNumber);
   trade.SetDeviationInPoints(15);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   //--- Init state
   g_H4LastSwingScan = 0;
   g_M15LastSwingScan = 0;
   g_H4Trend = 0;
   g_H4RangeHigh = 0;
   g_H4RangeLow = 0;
   g_H4Equilibrium = 0;
   g_PoiValid = false;
   ResetState();
   g_PendingTicket = 0;
   g_PendingBars = 0;

   //--- Recovery: detect existing pending order
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderGetInteger(ORDER_MAGIC) == InputMagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol)
      {
         g_PendingTicket = ticket;
         g_State = STATE_ORDER_PLACED;
         Print(">>> RECOVERY | Pending #", ticket);
         break;
      }
   }

   string trendDesc = (InputTrendMode == 0)
      ? "EMA" + IntegerToString(InputH4EmaPeriod) + " H4"
      : "SMMA" + IntegerToString(InputH1SmmaPeriod) + " H1";

   Print(">> ICARE V3 INSTITUTIONAL | EURUSD M15",
         " | Trend=", trendDesc,
         " | Cross=", (InputH1CrossOn ? "EMA" + IntegerToString(InputH1CrossFast) + "/" + IntegerToString(InputH1CrossSlow) + " H1" : "OFF"),
         " | H4BOS=", (InputH4BosOn ? "ON" : "OFF"),
         " | Discount=", (InputDiscountOn ? "ON" : "OFF"),
         " | MinConfl=", InputMinConfluence,
         " | IDM=", (InputIdmFilter ? "ON" : "OFF"),
         " | RR=1:", InputRiskReward,
         " | SL=MAX(Struct,", InputAtrMultSL, "xATR H1)",
         " | BE@", InputBeTriggerR, "R",
         " | Risk=", InputRiskPercent, "%");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| DEINITIALISATION                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleTrendFilter != INVALID_HANDLE) IndicatorRelease(handleTrendFilter);
   if(handleH1EmaFast != INVALID_HANDLE)   IndicatorRelease(handleH1EmaFast);
   if(handleH1EmaSlow != INVALID_HANDLE)   IndicatorRelease(handleH1EmaSlow);
   if(handleH1Atr != INVALID_HANDLE)       IndicatorRelease(handleH1Atr);

   if(g_PendingTicket > 0)
   {
      trade.OrderDelete(g_PendingTicket);
      Print(">>> DEINIT | Pending #", g_PendingTicket, " cancelled");
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
//| MANAGE POSITIONS - BE + Timeout                                   |
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

      if(elapsed >= InputMaxTradeHours)
      {
         trade.PositionClose(ticket);
         Print(">>> TIMEOUT | #", ticket, " | ", NormalizeDouble(elapsed, 1), "h");
         continue;
      }

      if(InputBeTriggerR > 0)
      {
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double tp        = PositionGetDouble(POSITION_TP);
         long   posType   = PositionGetInteger(POSITION_TYPE);
         double slDist    = MathAbs(openPrice - currentSL);
         double trigDist  = slDist * InputBeTriggerR;
         double beLevel   = (posType == POSITION_TYPE_BUY)
                            ? openPrice + InputBeBufferPts * _Point
                            : openPrice - InputBeBufferPts * _Point;
         bool alreadyBE   = (posType == POSITION_TYPE_BUY)
                            ? (currentSL >= openPrice) : (currentSL <= openPrice);

         if(!alreadyBE && slDist > 0)
         {
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            bool trig = false;
            if(posType == POSITION_TYPE_BUY && bid >= openPrice + trigDist) trig = true;
            if(posType == POSITION_TYPE_SELL && ask <= openPrice - trigDist) trig = true;
            if(trig)
            {
               trade.PositionModify(ticket, beLevel, tp);
               Print(">>> BE | #", ticket, " | NewSL=", NormalizeDouble(beLevel, _Digits));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| MANAGE PENDING ORDERS                                             |
//+------------------------------------------------------------------+
void ManagePendingOrders()
{
   if(g_PendingTicket == 0) return;

   bool orderExists = false;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == g_PendingTicket) { orderExists = true; break; }
   }

   if(!orderExists)
   {
      if(CountPositions() > 0)
         Print(">>> LIMIT FILLED | #", g_PendingTicket);
      else
         Print(">>> LIMIT CANCELLED | #", g_PendingTicket);
      g_PendingTicket = 0;
      g_PendingBars = 0;
      ResetState();
      return;
   }

   static datetime lastCheckBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_M15, 0);
   if(currentBar != lastCheckBar)
   {
      lastCheckBar = currentBar;
      g_PendingBars++;
      if(g_PendingBars >= InputPendingExpiry)
      {
         trade.OrderDelete(g_PendingTicket);
         Print(">>> PENDING EXPIRED | #", g_PendingTicket, " | ", g_PendingBars, " bars");
         g_PendingTicket = 0;
         g_PendingBars = 0;
         ResetState();
      }
   }
}

//+------------------------------------------------------------------+
//| ENTRY LOGIC - Filters + State Machine                             |
//+------------------------------------------------------------------+
void EntryLogic()
{
   if(CountPositions() > 0) return;
   if(g_State == STATE_ORDER_PLACED) return;
   if(CountTodayTrades() >= InputMaxDailyTrades) return;

   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.hour < InputStartHour || dt.hour >= InputEndHour) return;

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InputMaxSpread) return;

   //--- New M15 bar only
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_M15, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;

   if(g_State != STATE_IDLE) g_StateBars++;

   //--- News filter
   if(InputNewsFilter && !MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
   {
      if(IsNearNews()) return;
   }

   //--- Update H4 structure (on new H4 bar)
   UpdateH4Structure();

   //--- Update M15 swings
   UpdateSwingPoints(PERIOD_M15, InputM15SwingStrength, InputM15SwingLookback,
                     g_M15SwingHighs, g_M15SwingLows, g_M15LastSwingScan);

   //=== TREND FILTER (mandatory) ===
   int direction = GetTrendDirection();
   if(direction == 0) return;

   //--- Reset if direction changed
   if(g_State != STATE_IDLE && direction != g_StateDirection)
   {
      Print(">>> RESET | Trend direction changed");
      ResetState();
   }

   //=== STATE MACHINE ===
   switch(g_State)
   {
      case STATE_IDLE:
         ProcessStateIdle(direction);
         break;
      case STATE_AWAITING_CHOCH:
         ProcessStateAwaitingChoch();
         break;
      case STATE_SCANNING_FVG:
         ProcessStateScanningFvg();
         break;
      case STATE_ORDER_PLACED:
         break;
   }
}

//+------------------------------------------------------------------+
//| GET TREND DIRECTION from MA filter                                |
//+------------------------------------------------------------------+
int GetTrendDirection()
{
   double ma[];
   ArraySetAsSeries(ma, true);
   if(CopyBuffer(handleTrendFilter, 0, 0, 2, ma) < 2) return 0;

   double m15Close = iClose(_Symbol, PERIOD_M15, 1);
   if(m15Close > ma[1]) return +1;
   if(m15Close < ma[1]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| CALCULATE CONFLUENCE SCORE                                        |
//| 1. H1 EMA 20/50 Cross                                            |
//| 2. H4 BOS (structural trend)                                     |
//| 3. Premium/Discount zone                                          |
//+------------------------------------------------------------------+
int CalculateConfluence(int direction)
{
   int score = 0;

   //--- Signal 1: H1 EMA Cross
   if(InputH1CrossOn && CheckH1Cross(direction))
      score++;

   //--- Signal 2: H4 BOS
   if(InputH4BosOn && g_H4Trend == direction)
      score++;

   //--- Signal 3: Discount/Premium
   if(InputDiscountOn && g_H4Trend != 0)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(direction == +1 && bid < g_H4Equilibrium) score++;   // Discount
      if(direction == -1 && bid > g_H4Equilibrium) score++;   // Premium
   }

   return score;
}

//+------------------------------------------------------------------+
//| CHECK H1 EMA CROSS (recent cross in trade direction)              |
//+------------------------------------------------------------------+
bool CheckH1Cross(int direction)
{
   if(!InputH1CrossOn) return false;

   double fast[], slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   int need = InputH1CrossLookback + 2;
   if(CopyBuffer(handleH1EmaFast, 0, 0, need, fast) < need) return false;
   if(CopyBuffer(handleH1EmaSlow, 0, 0, need, slow) < need) return false;

   for(int i = 1; i <= InputH1CrossLookback; i++)
   {
      if(direction == +1 && fast[i] > slow[i] && fast[i+1] <= slow[i+1])
         return true;
      if(direction == -1 && fast[i] < slow[i] && fast[i+1] >= slow[i+1])
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| UPDATE H4 STRUCTURE - Swings, BOS, Trend, Range, POI              |
//+------------------------------------------------------------------+
void UpdateH4Structure()
{
   if(!InputH4BosOn) return;

   //--- Only update on new H4 bar
   static datetime lastH4Bar = 0;
   datetime currentH4Bar = iTime(_Symbol, PERIOD_H4, 0);
   if(currentH4Bar == lastH4Bar) return;
   lastH4Bar = currentH4Bar;

   UpdateSwingPoints(PERIOD_H4, InputH4SwingStrength, InputH4SwingLookback,
                     g_H4SwingHighs, g_H4SwingLows, g_H4LastSwingScan);

   if(ArraySize(g_H4SwingHighs) < 2 || ArraySize(g_H4SwingLows) < 2) return;

   double h4Close = iClose(_Symbol, PERIOD_H4, 1);

   //--- Bullish BOS on H4
   if(h4Close > g_H4SwingHighs[0].price && g_H4Trend != +1)
   {
      g_H4Trend = +1;
      g_H4RangeHigh = g_H4SwingHighs[0].price;

      //--- Find preceding swing low (older than the broken swing high)
      g_H4RangeLow = g_H4SwingLows[0].price;
      for(int i = 0; i < ArraySize(g_H4SwingLows); i++)
      {
         if(g_H4SwingLows[i].barIndex > g_H4SwingHighs[0].barIndex)
         {
            g_H4RangeLow = g_H4SwingLows[i].price;
            break;
         }
      }
      g_H4Equilibrium = (g_H4RangeHigh + g_H4RangeLow) / 2.0;
      FindH4POI(+1);

      Print(">>> H4 BOS BULLISH | Range [", NormalizeDouble(g_H4RangeLow, _Digits),
            " - ", NormalizeDouble(g_H4RangeHigh, _Digits),
            "] | EQ=", NormalizeDouble(g_H4Equilibrium, _Digits));
   }

   //--- Bearish BOS on H4
   if(h4Close < g_H4SwingLows[0].price && g_H4Trend != -1)
   {
      g_H4Trend = -1;
      g_H4RangeLow = g_H4SwingLows[0].price;

      g_H4RangeHigh = g_H4SwingHighs[0].price;
      for(int i = 0; i < ArraySize(g_H4SwingHighs); i++)
      {
         if(g_H4SwingHighs[i].barIndex > g_H4SwingLows[0].barIndex)
         {
            g_H4RangeHigh = g_H4SwingHighs[i].price;
            break;
         }
      }
      g_H4Equilibrium = (g_H4RangeHigh + g_H4RangeLow) / 2.0;
      FindH4POI(-1);

      Print(">>> H4 BOS BEARISH | Range [", NormalizeDouble(g_H4RangeLow, _Digits),
            " - ", NormalizeDouble(g_H4RangeHigh, _Digits),
            "] | EQ=", NormalizeDouble(g_H4Equilibrium, _Digits));
   }
}

//+------------------------------------------------------------------+
//| FIND H4 POI - Order Block at swing extreme                       |
//+------------------------------------------------------------------+
void FindH4POI(int direction)
{
   g_PoiValid = false;

   if(direction == +1)
   {
      //--- Bullish: OB at the H4 swing low (base of impulse)
      int swBar = -1;
      for(int i = 0; i < ArraySize(g_H4SwingLows); i++)
      {
         if(g_H4SwingLows[i].barIndex > g_H4SwingHighs[0].barIndex)
         {
            swBar = g_H4SwingLows[i].barIndex;
            break;
         }
      }
      if(swBar < 0) return;

      //--- OB = the last bearish candle before the impulse up
      int obBar = swBar;
      for(int i = swBar; i >= 1; i--)
      {
         if(iClose(_Symbol, PERIOD_H4, i) > iOpen(_Symbol, PERIOD_H4, i))
         {
            obBar = (i + 1 <= swBar) ? i + 1 : swBar;
            break;
         }
      }

      g_PoiTop    = iHigh(_Symbol, PERIOD_H4, obBar);
      g_PoiBottom = iLow(_Symbol, PERIOD_H4, obBar);

      if(g_PoiBottom > g_H4Equilibrium) return;

      g_PoiValid = true;
      Print(">>> H4 POI (OB) BULLISH | [", NormalizeDouble(g_PoiBottom, _Digits),
            " - ", NormalizeDouble(g_PoiTop, _Digits), "] bar=", obBar);
   }
   else
   {
      int swBar = -1;
      for(int i = 0; i < ArraySize(g_H4SwingHighs); i++)
      {
         if(g_H4SwingHighs[i].barIndex > g_H4SwingLows[0].barIndex)
         {
            swBar = g_H4SwingHighs[i].barIndex;
            break;
         }
      }
      if(swBar < 0) return;

      int obBar = swBar;
      for(int i = swBar; i >= 1; i--)
      {
         if(iClose(_Symbol, PERIOD_H4, i) < iOpen(_Symbol, PERIOD_H4, i))
         {
            obBar = (i + 1 <= swBar) ? i + 1 : swBar;
            break;
         }
      }

      g_PoiTop    = iHigh(_Symbol, PERIOD_H4, obBar);
      g_PoiBottom = iLow(_Symbol, PERIOD_H4, obBar);

      if(g_PoiTop < g_H4Equilibrium) return;

      g_PoiValid = true;
      Print(">>> H4 POI (OB) BEARISH | [", NormalizeDouble(g_PoiBottom, _Digits),
            " - ", NormalizeDouble(g_PoiTop, _Digits), "] bar=", obBar);
   }
}

//+------------------------------------------------------------------+
//| STATE IDLE - Check confluence + POI entry                         |
//+------------------------------------------------------------------+
void ProcessStateIdle(int direction)
{
   //--- Confluence check
   int score = CalculateConfluence(direction);
   if(score < InputMinConfluence)
      return;

   //--- If H4 POI active: check if price is in POI zone
   bool poiRequired = (InputH4BosOn && g_PoiValid);

   if(poiRequired)
   {
      double low1  = iLow(_Symbol, PERIOD_M15, 1);
      double high1 = iHigh(_Symbol, PERIOD_M15, 1);

      bool inPoi = false;
      if(direction == +1 && low1 <= g_PoiTop)   inPoi = true;
      if(direction == -1 && high1 >= g_PoiBottom) inPoi = true;

      if(!inPoi) return;

      Print(">>> PRICE IN POI | Dir=", (direction > 0 ? "BUY" : "SELL"),
            " | Confluence=", score, "/", InputMinConfluence,
            " | POI [", NormalizeDouble(g_PoiBottom, _Digits),
            " - ", NormalizeDouble(g_PoiTop, _Digits), "]");
   }
   else
   {
      Print(">>> CONFLUENCE MET | Dir=", (direction > 0 ? "BUY" : "SELL"),
            " | Score=", score, "/", InputMinConfluence, " | No POI required");
   }

   g_State = STATE_AWAITING_CHOCH;
   g_StateDirection = direction;
   g_StateBars = 0;
}

//+------------------------------------------------------------------+
//| STATE AWAITING CHOCH - Wait for M15 Change of Character           |
//+------------------------------------------------------------------+
void ProcessStateAwaitingChoch()
{
   //--- Expiry
   if(g_StateBars > InputPoiMaxBars)
   {
      Print(">>> CHOCH TIMEOUT | ", g_StateBars, " bars > ", InputPoiMaxBars);
      ResetState();
      return;
   }

   //--- POI invalidation (if applicable)
   if(InputH4BosOn && g_PoiValid)
   {
      double close1 = iClose(_Symbol, PERIOD_M15, 1);
      double poiHeight = g_PoiTop - g_PoiBottom;
      if(g_StateDirection == +1 && close1 < g_PoiBottom - poiHeight)
      {
         Print(">>> POI INVALIDATED | Price blew through OB zone");
         ResetState();
         return;
      }
      if(g_StateDirection == -1 && close1 > g_PoiTop + poiHeight)
      {
         Print(">>> POI INVALIDATED | Price blew through OB zone");
         ResetState();
         return;
      }
   }

   //--- Check ChoCH (M15 swing break in trade direction)
   if(!CheckChoCH()) return;

   //--- IDM filter (optional)
   if(InputIdmFilter && !CheckIDM())
   {
      Print(">>> IDM FAIL | No liquidity sweep detected");
      return;
   }

   //--- Save structural SL from M15 swing
   if(g_StateDirection == +1 && ArraySize(g_M15SwingLows) > 0)
      g_SwingSL = g_M15SwingLows[0].price - InputSlBufferPts * _Point;
   else if(g_StateDirection == -1 && ArraySize(g_M15SwingHighs) > 0)
      g_SwingSL = g_M15SwingHighs[0].price + InputSlBufferPts * _Point;
   else
   {
      Print(">>> NO SWING FOR SL");
      return;
   }

   Print(">>> CHOCH CONFIRMED | Dir=", (g_StateDirection > 0 ? "BUY" : "SELL"),
         " | SL@", NormalizeDouble(g_SwingSL, _Digits),
         (InputIdmFilter ? " | IDM OK" : ""));

   //--- Immediately scan for FVG
   FVGZone fvg;
   if(DetectM15FVG(g_StateDirection, fvg))
   {
      PlaceLimitOrder(fvg);
   }
   else
   {
      g_State = STATE_SCANNING_FVG;
      g_StateBars = 0;
      Print(">>> No FVG yet, scanning...");
   }
}

//+------------------------------------------------------------------+
//| STATE SCANNING FVG - Scan for FVG after ChoCH                    |
//+------------------------------------------------------------------+
void ProcessStateScanningFvg()
{
   if(g_StateBars > InputFvgMaxBars)
   {
      Print(">>> FVG SCAN TIMEOUT | ", g_StateBars, " bars");
      ResetState();
      return;
   }

   FVGZone fvg;
   if(DetectM15FVG(g_StateDirection, fvg))
      PlaceLimitOrder(fvg);
}

//+------------------------------------------------------------------+
//| CHECK CHOCH - Change of Character on M15                          |
//| Bullish: Close > last M15 swing high (mini-BOS up)                |
//| Bearish: Close < last M15 swing low (mini-BOS down)               |
//+------------------------------------------------------------------+
bool CheckChoCH()
{
   if(ArraySize(g_M15SwingHighs) < 1 || ArraySize(g_M15SwingLows) < 1)
      return false;

   double close1 = iClose(_Symbol, PERIOD_M15, 1);

   if(g_StateDirection == +1 && close1 > g_M15SwingHighs[0].price)
   {
      Print(">>> CHOCH BULLISH | Close ", NormalizeDouble(close1, _Digits),
            " > M15 SwH ", NormalizeDouble(g_M15SwingHighs[0].price, _Digits));
      return true;
   }
   if(g_StateDirection == -1 && close1 < g_M15SwingLows[0].price)
   {
      Print(">>> CHOCH BEARISH | Close ", NormalizeDouble(close1, _Digits),
            " < M15 SwL ", NormalizeDouble(g_M15SwingLows[0].price, _Digits));
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| CHECK IDM - Inducement / Liquidity Sweep                          |
//| Bullish: price swept below a M15 swing low before reversing       |
//| Bearish: price swept above a M15 swing high before reversing      |
//+------------------------------------------------------------------+
bool CheckIDM()
{
   if(!InputIdmFilter) return true;

   if(g_StateDirection == +1)
   {
      if(ArraySize(g_M15SwingLows) < 2) return false;
      double sweepLevel = g_M15SwingLows[1].price;
      for(int i = 1; i <= InputIdmLookback; i++)
      {
         if(iLow(_Symbol, PERIOD_M15, i) < sweepLevel)
            return true;
      }
   }
   else
   {
      if(ArraySize(g_M15SwingHighs) < 2) return false;
      double sweepLevel = g_M15SwingHighs[1].price;
      for(int i = 1; i <= InputIdmLookback; i++)
      {
         if(iHigh(_Symbol, PERIOD_M15, i) > sweepLevel)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| DETECT M15 FVG                                                    |
//+------------------------------------------------------------------+
bool DetectM15FVG(int direction, FVGZone &fvg)
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

      if(direction == +1 && low_i > high_i2)
      {
         double gap = (low_i - high_i2) / _Point;
         if(gap < InputMinFvgPts) continue;

         fvg.top    = low_i;
         fvg.bottom = high_i2;
         fvg.entry  = NormalizeDouble((low_i + high_i2) / 2.0, _Digits);
         fvg.direction = +1;

         if(fvg.entry >= ask - minDist) continue;
         if(g_SwingSL >= fvg.entry) continue;

         Print(">>> FVG BULL | [", NormalizeDouble(fvg.bottom, _Digits),
               "-", NormalizeDouble(fvg.top, _Digits),
               "] Entry@", NormalizeDouble(fvg.entry, _Digits),
               " | Gap=", NormalizeDouble(gap, 0), "pts");
         return true;
      }

      if(direction == -1 && high_i < low_i2)
      {
         double gap = (low_i2 - high_i) / _Point;
         if(gap < InputMinFvgPts) continue;

         fvg.top    = low_i2;
         fvg.bottom = high_i;
         fvg.entry  = NormalizeDouble((low_i2 + high_i) / 2.0, _Digits);
         fvg.direction = -1;

         if(fvg.entry <= bid + minDist) continue;
         if(g_SwingSL <= fvg.entry) continue;

         Print(">>> FVG BEAR | [", NormalizeDouble(fvg.bottom, _Digits),
               "-", NormalizeDouble(fvg.top, _Digits),
               "] Entry@", NormalizeDouble(fvg.entry, _Digits),
               " | Gap=", NormalizeDouble(gap, 0), "pts");
         return true;
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

   //--- SL = MAX(structural, ATR H1, minimum)
   double structDist = MathAbs(entry - g_SwingSL);

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   double atrDist = 0;
   if(CopyBuffer(handleH1Atr, 0, 0, 2, atrBuf) >= 2)
      atrDist = atrBuf[1] * InputAtrMultSL;

   double minDist = InputMinSLPts * _Point;
   double slDist  = MathMax(structDist, MathMax(atrDist, minDist));

   double sl;
   if(fvg.direction == +1)
      sl = entry - slDist;
   else
      sl = entry + slDist;
   sl = NormalizeDouble(sl, _Digits);

   double tpDist = slDist * InputRiskReward;
   double tp = (fvg.direction == +1) ? entry + tpDist : entry - tpDist;
   tp = NormalizeDouble(tp, _Digits);

   double lotSize = CalculateLotSize(slDist);

   bool result = false;
   if(fvg.direction == +1)
      result = trade.BuyLimit(lotSize, entry, _Symbol, sl, tp,
                              ORDER_TIME_GTC, 0, "ICARE V3 Buy");
   else
      result = trade.SellLimit(lotSize, entry, _Symbol, sl, tp,
                               ORDER_TIME_GTC, 0, "ICARE V3 Sell");

   if(result)
   {
      g_PendingTicket = trade.ResultOrder();
      g_PendingBars = 0;
      g_State = STATE_ORDER_PLACED;
      string slType = (slDist == atrDist) ? "ATR" : ((slDist == structDist) ? "STRUCT" : "MIN");
      Print(">>> LIMIT | ", (fvg.direction > 0 ? "BUY" : "SELL"),
            " #", g_PendingTicket,
            " | Entry=", NormalizeDouble(entry, _Digits),
            " | SL=", NormalizeDouble(sl, _Digits),
            " (", NormalizeDouble(slDist / _Point, 0), "pts ", slType, ")",
            " | TP=", NormalizeDouble(tp, _Digits),
            " (1:", InputRiskReward, ")",
            " | Lot=", lotSize);
   }
   else
      Print(">>> ORDER ERROR: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| UPDATE SWING POINTS - Generic (any TF)                            |
//+------------------------------------------------------------------+
void UpdateSwingPoints(ENUM_TIMEFRAMES tf, int strength, int lookback,
                       SwingPoint &highs[], SwingPoint &lows[], datetime &lastScan)
{
   datetime currentBar = iTime(_Symbol, tf, 0);
   if(currentBar == lastScan) return;
   lastScan = currentBar;

   ArrayResize(highs, 0);
   ArrayResize(lows, 0);
   int maxBar = lookback - strength;

   for(int i = strength; i <= maxBar; i++)
   {
      double high = iHigh(_Symbol, tf, i);
      bool isSwH = true;
      for(int j = 1; j <= strength; j++)
      {
         if(iHigh(_Symbol, tf, i-j) >= high || iHigh(_Symbol, tf, i+j) >= high)
         { isSwH = false; break; }
      }
      if(isSwH)
      {
         int sz = ArraySize(highs);
         ArrayResize(highs, sz + 1);
         highs[sz].price = high;
         highs[sz].barIndex = i;
      }

      double low = iLow(_Symbol, tf, i);
      bool isSwL = true;
      for(int j = 1; j <= strength; j++)
      {
         if(iLow(_Symbol, tf, i-j) <= low || iLow(_Symbol, tf, i+j) <= low)
         { isSwL = false; break; }
      }
      if(isSwL)
      {
         int sz = ArraySize(lows);
         ArrayResize(lows, sz + 1);
         lows[sz].price = low;
         lows[sz].barIndex = i;
      }
   }
}

//+------------------------------------------------------------------+
//| CALCULATE LOT SIZE - % of capital                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskUSD  = balance * InputRiskPercent / 100.0;
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize == 0 || tickVal == 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double lot = riskUSD / ((slDistance / tickSize) * tickVal);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / lotStep) * lotStep;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   return lot;
}

//+------------------------------------------------------------------+
//| COUNT POSITIONS                                                   |
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
//| COUNT TODAY TRADES                                                 |
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
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
            count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| NEWS FILTER - MQL5 Calendar (live only)                           |
//+------------------------------------------------------------------+
bool IsNearNews()
{
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
      return false;

   MqlCalendarValue values[];
   datetime from = TimeCurrent() - InputNewsMinutes * 60;
   datetime to   = TimeCurrent() + InputNewsMinutes * 60;

   int totalEur = CalendarValueHistory(values, from, to, NULL, "EUR");
   if(totalEur > 0)
   {
      for(int i = 0; i < totalEur; i++)
      {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
            if(event.importance == CALENDAR_IMPORTANCE_HIGH)
               return true;
      }
   }

   ArrayResize(values, 0);
   int totalUsd = CalendarValueHistory(values, from, to, NULL, "USD");
   if(totalUsd > 0)
   {
      for(int i = 0; i < totalUsd; i++)
      {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
            if(event.importance == CALENDAR_IMPORTANCE_HIGH)
               return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| RESET STATE                                                       |
//+------------------------------------------------------------------+
void ResetState()
{
   g_State = STATE_IDLE;
   g_StateDirection = 0;
   g_SwingSL = 0;
   g_StateBars = 0;
}
//+------------------------------------------------------------------+

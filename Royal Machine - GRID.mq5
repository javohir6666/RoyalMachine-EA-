//+------------------------------------------------------------------+
//|                                            Royal_Grid_Machine.mq5 |
//|                                      Copyright 2026, Gemini       |
//+------------------------------------------------------------------+
#property copyright "Javohir Abdullayev"
#property link      "https://pycoder.uz"
#property version   "3.1"

#include <Trade\Trade.mqh>

//--- TP Mode Options
enum ENUM_TP_MODE
  {
   MODE_PHYSICAL = 0,   // Physical TP (Points)
   MODE_VIRTUAL = 1     // Virtual Basket TP (Money)
  };

//--- Telegram Interval Options
enum ENUM_TELEGRAM_INTERVAL
  {
   INTERVAL_OFF = 0,     // Notifications OFF
   INTERVAL_1H = 3600,   // Every 1 Hour
   INTERVAL_2H = 7200,   // Every 2 Hours
   INTERVAL_4H = 14400,  // Every 4 Hours
   INTERVAL_8H = 28800,  // Every 8 Hours
   INTERVAL_12H = 43200, // Every 12 Hours
   INTERVAL_24H = 86400  // Every 24 Hours
  };

//--- Main Settings
input group                "--- Main Settings ---";
input double               InpMultiplikator = 1.0;       // Lot Multiplier (Martingale)
input bool                 InpConstantLot = true;        // Use Constant Lot (True) or Auto (False)
input double               InpConstantLotSize = 0.3;     // Constant Lot Size
input double               InpRiskPercent = 1000.0;      // Auto-Lot Risk Percentage
input double               InpStep = 70.0;               // Initial Step Distance (in Points)
input double               InpStepMultiplier = 1.3;      // Step Multiplier (Dynamic Grid)
input int                  InpMaxOrders = 50;            // Maximum Allowed Orders
input ulong                InpMagic = 777777;            // Expert Magic Number

//--- Strategy: Supertrend + Parabolic SAR
input group                "--- Strategy Settings ---";
input string               InpSTName = "Supertrend";     // Supertrend File Name
input int                  InpSTPeriod = 10;             // Supertrend Period
input double               InpSTMultiplier = 3.0;        // Supertrend Multiplier
input double               InpSarStep = 0.02;            // Parabolic SAR Step
input double               InpSarMax = 0.2;              // Parabolic SAR Maximum

//--- RSI & Reversal Settings (YANGI MANTIQ)
input group                "--- RSI & Reversal Filter ---";
input bool                 InpUseRsiLogic = true;        // [ON/OFF] Use RSI Filter & Reversal Catch
input int                  InpRsiPeriod = 14;            // RSI Period
input double               InpRsiOB = 70.0;              // Danger Zone: Overbought (No Buy > 70)
input double               InpRsiOS = 30.0;              // Danger Zone: Oversold (No Sell < 30)
input double               InpRsiRevSell = 60.0;         // SAR Reversal Sell Trigger (if RSI > 60)
input double               InpRsiRevBuy = 40.0;          // SAR Reversal Buy Trigger (if RSI < 40)

//--- Grid Protection (To'r Himoyasi)
input group                "--- Grid Protection ---";
input bool                 InpUseGridFreeze = true;      // [ON/OFF] Freeze Grid on Reverse Trend (Supertrend)
input bool                 InpUseAtrStep = true;         // [ON/OFF] ATR Dynamic Step
input int                  InpAtrPeriod = 14;            // ATR Period for Step
input double               InpAtrMultiplier = 1.5;       // ATR Step Multiplier

//--- Take Profit Settings
input group                "--- Take Profit Settings ---";
input ENUM_TP_MODE         InpTpMode = MODE_VIRTUAL;     // Take Profit Mode
input double               InpTakeProfitPoints = 300.0;  // Target TP (if Physical, in Points)
input double               InpTakeProfitMoney = 10.0;    // Target TP (if Virtual & No Trailing, in $)
input bool                 InpUseVirtualTrailing = true; // Use Virtual Trailing (Quvib borish)
input double               InpTrailingStartMoney = 10.0; // Trailing Start (in $)
input double               InpTrailingStepMoney = 2.0;   // Trailing Step/Dropback (in $)

//--- Time Settings
input group                "--- Time Settings ---";
input bool                 InpUseTimeFilter = true;      // Enable Trading Time Filter
input string               InpStartTime = "01:00";       // Trading Start Time (HH:MM)
input string               InpEndTime = "22:00";         // Trading End Time (HH:MM)

//--- Telegram Settings
input group                "--- Telegram Settings ---";
input string               InpTelegramBotToken = "7602310057:AAGWxHexO7QlZcApmHyZxuSaX_r-uJWWHb8"; 
input string               InpTelegramChatID = "-5112900905";     
input ENUM_TELEGRAM_INTERVAL InpTelegramInterval = INTERVAL_4H;    

//--- Design Settings
input group                "--- Design Settings ---";
input bool                 InpApplyTheme = true;         
input bool                 InpShowLogo = true;           

//--- Global o'zgaruvchilar
CTrade         trade;
datetime       last_bar_time;

// Indikator Handles
int            st_handle;
int            sar_handle;
int            rsi_handle;
int            atr_step_handle; 

datetime       last_telegram_time = 0; 
bool           global_freeze_state = false;
double         global_current_step = 0;
double         current_rsi_value = 50.0;
double         max_profit_buy = 0;
double         max_profit_sell = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   if(InpApplyTheme) ApplyChartTheme();
   
   st_handle = iCustom(_Symbol, PERIOD_CURRENT, InpSTName, InpSTPeriod, InpSTMultiplier);
   if(st_handle == INVALID_HANDLE) { Print("XATOLIK: Supertrend topilmadi!"); return(INIT_FAILED); }
     
   sar_handle = iSAR(_Symbol, PERIOD_CURRENT, InpSarStep, InpSarMax);
   if(sar_handle == INVALID_HANDLE) { Print("XATOLIK: Parabolic SAR topilmadi!"); return(INIT_FAILED); }

   if(InpUseRsiLogic)
     {
      rsi_handle = iRSI(_Symbol, PERIOD_CURRENT, InpRsiPeriod, PRICE_CLOSE);
      if(rsi_handle == INVALID_HANDLE) { Print("XATOLIK: RSI topilmadi!"); return(INIT_FAILED); }
     }

   if(InpUseAtrStep)
     {
      atr_step_handle = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);
      if(atr_step_handle == INVALID_HANDLE) { Print("XATOLIK: ATR topilmadi!"); return(INIT_FAILED); }
     }

   if(InpShowLogo) DrawDashboard();
   if(InpTelegramInterval != INTERVAL_OFF) last_telegram_time = TimeCurrent();
   
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   IndicatorRelease(st_handle);
   IndicatorRelease(sar_handle);
   if(InpUseRsiLogic) IndicatorRelease(rsi_handle);
   if(InpUseAtrStep) IndicatorRelease(atr_step_handle);
   ObjectsDeleteAll(0, "Dash_");
  }

//+------------------------------------------------------------------+
//| Telegram yuborish funksiyasi                                     |
//+------------------------------------------------------------------+
void SendTelegramMessage(string message)
  {
   if(InpTelegramBotToken == "" || InpTelegramBotToken == "YOUR_BOT_TOKEN" || InpTelegramChatID == "") return;
   string url = "https://api.telegram.org/bot" + InpTelegramBotToken + "/sendMessage";
   string post_data = "chat_id=" + InpTelegramChatID + "&text=" + message + "&parse_mode=HTML";
   char data[], res[]; string headers;
   StringToCharArray(post_data, data, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(data, ArraySize(data) - 1); 
   WebRequest("POST", url, "application/x-www-form-urlencoded", 5000, data, res, headers);
  }

void CheckAndSendTelegramReport()
  {
   if(InpTelegramInterval == INTERVAL_OFF) return;
   datetime current_time = TimeCurrent();
   if(current_time - last_telegram_time >= (int)InpTelegramInterval)
     {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      int total_pos = CountOpenPositions();
      
      datetime start_today = current_time - (current_time % 86400); 
      double profit_today = 0;
      if(HistorySelect(start_today, current_time))
         for(int i = 0; i < HistoryDealsTotal(); i++) profit_today += HistoryDealGetDouble(HistoryDealGetTicket(i), DEAL_PROFIT);
      
      string msg = "🤖 <b>ROYAL MACHINE REPORT</b>\n\n";
      msg += "💵 <b>Balance:</b> $" + DoubleToString(balance, 2) + "\n";
      msg += "📈 <b>Equity:</b> $" + DoubleToString(equity, 2) + "\n";
      msg += "🛡 <b>Free Margin:</b> $" + DoubleToString(free_margin, 2) + "\n";
      msg += "💰 <b>Daily Profit:</b> $" + DoubleToString(profit_today, 2) + "\n";
      msg += "📦 <b>Open Positions:</b> " + IntegerToString(total_pos) + "\n\n";
      msg += "⏱ <i>Server Time: " + TimeToString(current_time, TIME_DATE|TIME_MINUTES) + "</i>";
      SendTelegramMessage(msg);
      last_telegram_time = current_time;
     }
  }

bool IsTradingTime()
  {
   if(!InpUseTimeFilter) return true;
   datetime time_current = TimeCurrent();
   MqlDateTime tm; TimeToStruct(time_current, tm);
   int current_mins = tm.hour * 60 + tm.min;
   string start_arr[], end_arr[];
   StringSplit(InpStartTime, ':', start_arr); StringSplit(InpEndTime, ':', end_arr);
   if(ArraySize(start_arr) < 2 || ArraySize(end_arr) < 2) return true; 
   int start_mins = (int)StringToInteger(start_arr[0]) * 60 + (int)StringToInteger(start_arr[1]);
   int end_mins = (int)StringToInteger(end_arr[0]) * 60 + (int)StringToInteger(end_arr[1]);
   if (start_mins < end_mins) return (current_mins >= start_mins && current_mins < end_mins);
   else return (current_mins >= start_mins || current_mins < end_mins);
  }

//+------------------------------------------------------------------+
//| ASINXRON (TEZKOR) YOPISH FUNKSIYASI                              |
//+------------------------------------------------------------------+
void CloseAllByType(int type)
  {
   trade.SetAsyncMode(true); 
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetInteger(POSITION_TYPE) == type)
         trade.PositionClose(ticket);
     }
   trade.SetAsyncMode(false); 
  }

void CheckVirtualTP(int type)
  {
   double total_profit = 0; int pos_count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetInteger(POSITION_TYPE) == type)
        {
         total_profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
         pos_count++;
        }
     }
     
   if(pos_count == 0)
     {
      if(type == POSITION_TYPE_BUY) max_profit_buy = 0;
      if(type == POSITION_TYPE_SELL) max_profit_sell = 0;
      return;
     }

   if(InpUseVirtualTrailing)
     {
      double current_max = (type == POSITION_TYPE_BUY) ? max_profit_buy : max_profit_sell;
      if(total_profit > current_max)
        {
         current_max = total_profit;
         if(type == POSITION_TYPE_BUY) max_profit_buy = current_max;
         if(type == POSITION_TYPE_SELL) max_profit_sell = current_max;
        }

      if(current_max >= InpTrailingStartMoney && total_profit <= (current_max - InpTrailingStepMoney))
        {
         CloseAllByType(type);
         if(type == POSITION_TYPE_BUY) max_profit_buy = 0;
         if(type == POSITION_TYPE_SELL) max_profit_sell = 0;
        }
     }
   else
     {
      if(total_profit > 0 && total_profit >= InpTakeProfitMoney) CloseAllByType(type);
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // RSI ni Dashboard uchun jonli o'qish
   if(InpUseRsiLogic)
     {
      double rsi_live[];
      if(CopyBuffer(rsi_handle, 0, 0, 1, rsi_live) > 0) current_rsi_value = rsi_live[0];
     }

   if(InpShowLogo) UpdateDashboard();
   CheckAndSendTelegramReport();

   if(InpTpMode == MODE_VIRTUAL)
     {
      CheckVirtualTP(POSITION_TYPE_BUY);
      CheckVirtualTP(POSITION_TYPE_SELL);
     }

   // --- QAT'IY QOIDA: BARCHA SAVDOLAR FAQAT YANGI BARDA OCHILADI ---
   datetime current_bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool isNewBar = false;
   if(current_bar_time != last_bar_time) 
     { 
      isNewBar = true; 
      last_bar_time = current_bar_time; 
     }

   if(!isNewBar) return; 

   int total_positions = CountOpenPositions();

   // ---------------------------------------------------------
   // 1. BIRINCHI SAVDONI OCHISH (RSI + SAR + ST MANTIG'I)
   // ---------------------------------------------------------
   if(total_positions == 0)
     {
      global_freeze_state = false; 
      global_current_step = 0;
      if(InpUseTimeFilter && !IsTradingTime()) return; 

      double initial_lot = CalculateLot();
      double close_price = iClose(_Symbol, PERIOD_CURRENT, 1);

      double st_val[]; CopyBuffer(st_handle, 0, 1, 1, st_val);
      double sar_val[]; CopyBuffer(sar_handle, 0, 1, 1, sar_val);
      
      if(st_val[0] != 0 && st_val[0] != EMPTY_VALUE && sar_val[0] != 0)
        {
         double current_st = st_val[0];
         double current_sar = sar_val[0];
         
         bool st_buy = (close_price > current_st);
         bool st_sell = (close_price < current_st);
         bool sar_buy = (close_price > current_sar);
         bool sar_sell = (close_price < current_sar);

         bool buy_signal = false;
         bool sell_signal = false;

         if(InpUseRsiLogic)
           {
            // A) Normal Trend: Supertrend va SAR bir xil yo'nalishda + RSI xavf zonasida Emas
            if(st_buy && sar_buy && current_rsi_value < InpRsiOB) buy_signal = true;
            if(st_sell && sar_sell && current_rsi_value > InpRsiOS) sell_signal = true;

            // B) Reversal (Qaytishni ushlash): Supertrend kechiksa ham, SAR va RSI qaytishni tasdiqlasa
            // Agar narx baland bo'lsa (RSI > 60) va SAR "Sell" ga o'tsa -> Reversal Sell
            if(st_buy && sar_sell && current_rsi_value > InpRsiRevSell) sell_signal = true;
            // Agar narx tubda bo'lsa (RSI < 40) va SAR "Buy" ga o'tsa -> Reversal Buy
            if(st_sell && sar_buy && current_rsi_value < InpRsiRevBuy) buy_signal = true;
           }
         else
           {
            // Eski uslub: Faqat Supertrend va SAR mos kelsa
            if(st_buy && sar_buy) buy_signal = true;
            if(st_sell && sar_sell) sell_signal = true;
           }

         // Buyruqni bajarish
         if(buy_signal)
           {
            trade.Buy(initial_lot, _Symbol);
            if(InpTpMode == MODE_PHYSICAL) UpdateGridTP(POSITION_TYPE_BUY);
           }
         else if(sell_signal)
           {
            trade.Sell(initial_lot, _Symbol);
            if(InpTpMode == MODE_PHYSICAL) UpdateGridTP(POSITION_TYPE_SELL);
           }
        }
     }
   
   // ---------------------------------------------------------
   // 2. GRID / AVERAGING (Himoya tizimlari bilan)
   // ---------------------------------------------------------
   else if(total_positions > 0 && total_positions < InpMaxOrders)
     {
      int pos_type = GetGridDirection();
      double last_order_price = GetLastOrderPrice(pos_type);
      double current_price = (pos_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      // Grid Protection 1: Grid Freeze
      bool freeze_grid = false;
      if(InpUseGridFreeze)
        {
         double st_val[];
         if(CopyBuffer(st_handle, 0, 1, 1, st_val) > 0 && st_val[0] != 0 && st_val[0] != EMPTY_VALUE)
           {
            double close_price = iClose(_Symbol, PERIOD_CURRENT, 1);
            if(pos_type == POSITION_TYPE_BUY && close_price < st_val[0]) freeze_grid = true;
            if(pos_type == POSITION_TYPE_SELL && close_price > st_val[0]) freeze_grid = true;
           }
        }

      // Grid Protection 2: ATR Dynamic Step
      double base_step = InpStep;
      if(InpUseAtrStep)
        {
         double atr_val[];
         if(CopyBuffer(atr_step_handle, 0, 1, 1, atr_val) > 0)
           {
            base_step = (atr_val[0] * InpAtrMultiplier) / _Point;
           }
        }
        
      double current_dynamic_step = base_step * MathPow(InpStepMultiplier, total_positions - 1);
      
      global_freeze_state = freeze_grid;
      global_current_step = current_dynamic_step;

      bool conditionToOpen = false;
      if(!freeze_grid) 
        {
         if(pos_type == POSITION_TYPE_BUY && (last_order_price - current_price) >= current_dynamic_step * _Point) conditionToOpen = true;
         if(pos_type == POSITION_TYPE_SELL && (current_price - last_order_price) >= current_dynamic_step * _Point) conditionToOpen = true;
        }

      if(conditionToOpen)
        {
         double next_lot = GetLastOrderLot(pos_type) * InpMultiplikator;
         if(pos_type == POSITION_TYPE_BUY) trade.Buy(next_lot, _Symbol);
         else if(pos_type == POSITION_TYPE_SELL) trade.Sell(next_lot, _Symbol);
         
         if(InpTpMode == MODE_PHYSICAL) UpdateGridTP(pos_type);
        }
     }
  }

//+------------------------------------------------------------------+
//| Foydali funksiyalar                                              |
//+------------------------------------------------------------------+
int CountOpenPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic) count++;
   return count;
  }

int GetGridDirection()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return (int)PositionGetInteger(POSITION_TYPE);
   return -1;
  }

double GetLastOrderPrice(int type)
  {
   double last_price = 0; datetime last_time = 0;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetInteger(POSITION_TYPE) == type)
        {
         datetime pos_time = (datetime)PositionGetInteger(POSITION_TIME);
         if(pos_time > last_time) { last_time = pos_time; last_price = PositionGetDouble(POSITION_PRICE_OPEN); }
        }
     }
   return last_price;
  }

double GetLastOrderLot(int type)
  {
   double last_lot = InpConstantLotSize; datetime last_time = 0;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetInteger(POSITION_TYPE) == type)
        {
         datetime pos_time = (datetime)PositionGetInteger(POSITION_TIME);
         if(pos_time > last_time) { last_time = pos_time; last_lot = PositionGetDouble(POSITION_VOLUME); }
        }
     }
   return last_lot;
  }

double CalculateLot()
  {
   if(InpConstantLot) return InpConstantLotSize;
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double lot = NormalizeDouble((free_margin * InpRiskPercent / 100000.0), 2);
   if(lot < 0.01) lot = 0.01;
   return lot;
  }

void UpdateGridTP(int type)
  {
   double total_volume = 0; double total_value = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetInteger(POSITION_TYPE) == type)
        {
         double vol = PositionGetDouble(POSITION_VOLUME);
         double price = PositionGetDouble(POSITION_PRICE_OPEN);
         total_volume += vol; total_value += price * vol;
        }
     }
   if(total_volume > 0)
     {
      double avg_price = total_value / total_volume; 
      double new_tp = 0;
      if(type == POSITION_TYPE_BUY) new_tp = avg_price + (InpTakeProfitPoints * _Point);
      else if(type == POSITION_TYPE_SELL) new_tp = avg_price - (InpTakeProfitPoints * _Point);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetInteger(POSITION_TYPE) == type)
            trade.PositionModify(PositionGetTicket(i), 0, new_tp); 
     }
  }

//+------------------------------------------------------------------+
//| Tema va Dashboard                                                |
//+------------------------------------------------------------------+
void ApplyChartTheme()
  {
   ChartSetInteger(0, CHART_MODE, CHART_CANDLES); ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrBlack); ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrWhite);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, clrMediumSeaGreen); ChartSetInteger(0, CHART_COLOR_CHART_DOWN, clrCrimson);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrMediumSeaGreen); ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrCrimson);
   ChartSetInteger(0, CHART_COLOR_CHART_LINE, clrMediumSeaGreen); ChartSetInteger(0, CHART_COLOR_VOLUME, clrTeal);
   ChartSetInteger(0, CHART_COLOR_ASK, clrGray); ChartSetInteger(0, CHART_COLOR_BID, clrWhite);
  }

void DrawDashboard()
  {
   color bg_color = clrBlack; 
   ObjectCreate(0, "Dash_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "Dash_BG", OBJPROP_XDISTANCE, 20); ObjectSetInteger(0, "Dash_BG", OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, "Dash_BG", OBJPROP_XSIZE, 280); ObjectSetInteger(0, "Dash_BG", OBJPROP_YSIZE, 175); 
   ObjectSetInteger(0, "Dash_BG", OBJPROP_BGCOLOR, clrBlack); ObjectSetInteger(0, "Dash_BG", OBJPROP_BORDER_COLOR, clrDimGray);
   ObjectSetInteger(0, "Dash_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);

   CreateText("Dash_Title", "ROYAL GRID MACHINE", 30, 25, clrGold, 12, true);
   CreateText("Dash_Time", "Time Filter: OFF", 30, 45, clrWhite, 10);
   CreateText("Dash_Mode", "Strategy: ST + SAR + RSI Filter", 30, 65, clrMediumSeaGreen, 10);
   CreateText("Dash_RSI", "RSI Level: 50.0", 30, 85, clrMediumPurple, 10);
   CreateText("Dash_Today", "Profit Today: 0.00", 30, 105, clrLightSkyBlue, 11);
   CreateText("Dash_Step", "Next Step Dist: Waiting...", 30, 125, clrLightGray, 10); 
   CreateText("Dash_Balance", "BALANCE: 0.00", 30, 145, clrMediumSeaGreen, 14, true);
  }

void CreateText(string name, string text, int x, int y, color clr, int size, bool bold=false)
  {
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0); ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y); ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr); ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, "Trebuchet MS"); if(bold) ObjectSetString(0, name, OBJPROP_FONT, "Trebuchet MS Bold");
  }

void UpdateDashboard()
  {
   string time_text = "Time Filter: OFF"; color time_clr = clrGray;
   if(InpUseTimeFilter)
     {
      if(IsTradingTime()) { time_text = "Trading Active (" + InpStartTime + "-" + InpEndTime + ")"; time_clr = clrMediumSeaGreen; }
      else { time_text = "Trading Paused (" + InpStartTime + " kutilyapti)"; time_clr = clrOrange; }
     }
   ObjectSetString(0, "Dash_Time", OBJPROP_TEXT, time_text); ObjectSetInteger(0, "Dash_Time", OBJPROP_COLOR, time_clr);

   if(InpUseRsiLogic) ObjectSetString(0, "Dash_RSI", OBJPROP_TEXT, "RSI Level: " + DoubleToString(current_rsi_value, 1));
   else ObjectSetString(0, "Dash_RSI", OBJPROP_TEXT, "RSI Level: OFF");

   datetime end = TimeCurrent(); datetime start_today = end - (end % 86400); double profit_today = 0;
   if(HistorySelect(start_today, end))
      for(int i = 0; i < HistoryDealsTotal(); i++) profit_today += HistoryDealGetDouble(HistoryDealGetTicket(i), DEAL_PROFIT);
   ObjectSetString(0, "Dash_Today", OBJPROP_TEXT, "Profit Today: $" + DoubleToString(profit_today, 2));

   int total_pos = CountOpenPositions();
   if(total_pos > 0)
     {
      string freeze_txt = global_freeze_state ? " (FROZEN BY TREND)" : "";
      string step_type = InpUseAtrStep ? "ATR Step: " : "Static Step: ";
      ObjectSetString(0, "Dash_Step", OBJPROP_TEXT, step_type + DoubleToString(global_current_step, 1) + " pts" + freeze_txt);
      ObjectSetInteger(0, "Dash_Step", OBJPROP_COLOR, global_freeze_state ? clrOrange : clrLightGray);
     }
   else
     {
      ObjectSetString(0, "Dash_Step", OBJPROP_TEXT, "Next Step: Waiting for positions...");
      ObjectSetInteger(0, "Dash_Step", OBJPROP_COLOR, clrLightGray);
     }

   ObjectSetString(0, "Dash_Balance", OBJPROP_TEXT, "BALANCE: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
  }
//+------------------------------------------------------------------+
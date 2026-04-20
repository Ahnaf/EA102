//+------------------------------------------------------------------+
//|                                                   Dashboard.mqh  |
//|                          EA102 - XAUUSD Prop Firm EA             |
//|              On-chart information panel (ChartObjects)           |
//+------------------------------------------------------------------+
#ifndef DASHBOARD_MQH
#define DASHBOARD_MQH
#include "Utilities.mqh"
#include "PropProtection.mqh"
#include "SessionFilter.mqh"
#include "NewsFilter.mqh"
#include "RiskManager.mqh"

//+------------------------------------------------------------------+
//| CDashboard — draws a clean status panel using ChartObjects       |
//+------------------------------------------------------------------+
class CDashboard
  {
private:
   //--- Layout
   int      m_x;            // Left edge pixel
   int      m_y;            // Top edge pixel
   int      m_lineHeight;   // Pixels per line
   int      m_fontSize;
   color    m_bgColor;
   color    m_titleColor;
   color    m_textColor;
   color    m_goodColor;
   color    m_warnColor;
   color    m_badColor;
   string   m_fontName;
   string   m_prefix;       // Object name prefix to avoid collision

   long     m_chartId;

   // Module pointers
   CPropProtection *m_prop;
   CSessionFilter  *m_session;
   CNewsFilter     *m_news;
   CRiskManager    *m_risk;

   // EA state string
   string   m_eaStatus;
   bool     m_tradingActive;

public:
   CDashboard()
     : m_x(10), m_y(30), m_lineHeight(18), m_fontSize(9),
       m_bgColor(C'15,17,28'), m_titleColor(clrGold), m_textColor(clrSilver),
       m_goodColor(clrLimeGreen), m_warnColor(clrOrange), m_badColor(clrRed),
       m_fontName("Segoe UI"), m_prefix("EA102_DB_"),
       m_prop(NULL), m_session(NULL), m_news(NULL), m_risk(NULL),
       m_tradingActive(true), m_eaStatus("ACTIVE")
     { m_chartId = ChartID(); }

   ~CDashboard() { Destroy(); }

   bool Init(CPropProtection *prop, CSessionFilter *session,
             CNewsFilter *news, CRiskManager *risk)
     {
      m_prop    = prop;
      m_session = session;
      m_news    = news;
      m_risk    = risk;

      CreateBackground();
      LogInfo("Dashboard", "Initialised");
      return true;
     }

   //--- Set trading state for display
   void SetStatus(bool active, const string status)
     {
      m_tradingActive = active;
      m_eaStatus      = status;
     }

   //--- Refresh all labels — call every tick or every N seconds
   void Update()
     {
      double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
      double floatPL    = equity - balance;
      int    openTrades = (m_risk != NULL) ? m_risk->GetOpenTradeCount() : 0;

      double dailyDD    = (m_prop != NULL) ? m_prop->GetDailyDDPct()  : 0;
      double totalDD    = (m_prop != NULL) ? m_prop->GetMaxDDPct()    : 0;
      double dailyPL    = (m_prop != NULL) ? m_prop->GetDailyPL()     : 0;

      string sessionStr = (m_session != NULL) ? m_session->GetActiveSessionName() : "N/A";
      string newsStr    = (m_news    != NULL  && m_news->IsNewsBlocked()) ? "BLOCKED" : "Clear";
      string propStr    = (m_prop    != NULL) ? m_prop->GetStatusString() : "N/A";
      string modeStr    = (m_risk    != NULL) ? EnumToString(m_risk->GetTradeMode()) : "N/A";

      // Colour coding
      color propColor   = (m_tradingActive) ? m_goodColor : m_badColor;
      color newsColor   = (m_news != NULL && m_news->IsNewsBlocked()) ? m_warnColor : m_goodColor;
      color ddDayColor  = (dailyDD > 3.0) ? m_warnColor : (dailyDD > 4.5 ? m_badColor : m_goodColor);
      color ddTotColor  = (totalDD > 7.0) ? m_warnColor : (totalDD > 9.0 ? m_badColor : m_goodColor);
      color plColor     = (floatPL >= 0) ? m_goodColor : m_warnColor;
      color dplColor    = (dailyPL >= 0) ? m_goodColor : m_warnColor;

      int row = 0;
      SetLabel("Title",    "═══  EA102 · XAUUSD  ═══", m_titleColor, m_fontSize + 1, row++);
      SetLabel("Blank1",   "", m_textColor, m_fontSize, row++);
      SetLabel("Bal",      StringFormat("Balance   : $%.2f", balance),   m_textColor, m_fontSize, row++);
      SetLabel("Eq",       StringFormat("Equity    : $%.2f", equity),    m_textColor, m_fontSize, row++);
      SetLabel("FPL",      StringFormat("Float P/L : %+.2f", floatPL),  plColor,     m_fontSize, row++);
      SetLabel("DayPL",    StringFormat("Today P/L : %+.2f", dailyPL),  dplColor,    m_fontSize, row++);
      SetLabel("Blank2",   "", m_textColor, m_fontSize, row++);
      SetLabel("DailyDD",  StringFormat("Daily DD  : %.2f%%", dailyDD), ddDayColor,  m_fontSize, row++);
      SetLabel("TotalDD",  StringFormat("Total DD  : %.2f%%", totalDD), ddTotColor,  m_fontSize, row++);
      SetLabel("Blank3",   "", m_textColor, m_fontSize, row++);
      SetLabel("OTrades",  StringFormat("Open Trades: %d", openTrades), m_textColor, m_fontSize, row++);
      SetLabel("TodayTr",  StringFormat("Today Trades: %d", (m_risk != NULL) ? m_risk->GetTradesPerDay() : 0), m_textColor, m_fontSize, row++);
      SetLabel("Mode",     StringFormat("Mode       : %s", modeStr),    m_textColor, m_fontSize, row++);
      SetLabel("Blank4",   "", m_textColor, m_fontSize, row++);
      SetLabel("Session",  StringFormat("Session   : %s", sessionStr),  m_goodColor, m_fontSize, row++);
      SetLabel("News",     StringFormat("News      : %s", newsStr),     newsColor,   m_fontSize, row++);
      SetLabel("Prop",     StringFormat("Protection: %s", propStr),     propColor,   m_fontSize, row++);
      SetLabel("State",    StringFormat("TRADING   : %s", m_eaStatus),
               m_tradingActive ? m_goodColor : m_badColor, m_fontSize, row++);
      SetLabel("Blank5",   "", m_textColor, m_fontSize, row++);
      SetLabel("Time",     StringFormat("Server    : %s", GetTimeString()), m_textColor, m_fontSize - 1, row++);

      ChartRedraw(m_chartId);
     }

   //--- Remove all dashboard objects
   void Destroy()
     {
      ObjectsDeleteAll(m_chartId, m_prefix);
      ChartRedraw(m_chartId);
     }

private:
   void CreateBackground()
     {
      string nm = m_prefix + "BG";
      if(ObjectFind(m_chartId, nm) < 0)
         ObjectCreate(m_chartId, nm, OBJ_RECTANGLE_LABEL, 0, 0, 0);

      ObjectSetInteger(m_chartId, nm, OBJPROP_XDISTANCE,  m_x - 5);
      ObjectSetInteger(m_chartId, nm, OBJPROP_YDISTANCE,  m_y - 5);
      ObjectSetInteger(m_chartId, nm, OBJPROP_XSIZE,      220);
      ObjectSetInteger(m_chartId, nm, OBJPROP_YSIZE,      390);
      ObjectSetInteger(m_chartId, nm, OBJPROP_BGCOLOR,    m_bgColor);
      ObjectSetInteger(m_chartId, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(m_chartId, nm, OBJPROP_COLOR,      clrDimGray);
      ObjectSetInteger(m_chartId, nm, OBJPROP_BACK,       false);
      ObjectSetInteger(m_chartId, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chartId, nm, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
     }

   void SetLabel(const string id, const string text, color clr, int fontSize, int row)
     {
      string nm = m_prefix + id;

      if(ObjectFind(m_chartId, nm) < 0)
        {
         ObjectCreate(m_chartId, nm, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(m_chartId, nm, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chartId, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chartId, nm, OBJPROP_BACK,       false);
        }

      ObjectSetString(m_chartId,  nm, OBJPROP_TEXT,      text);
      ObjectSetString(m_chartId,  nm, OBJPROP_FONT,      m_fontName);
      ObjectSetInteger(m_chartId, nm, OBJPROP_FONTSIZE,  fontSize);
      ObjectSetInteger(m_chartId, nm, OBJPROP_COLOR,     clr);
      ObjectSetInteger(m_chartId, nm, OBJPROP_XDISTANCE, m_x);
      ObjectSetInteger(m_chartId, nm, OBJPROP_YDISTANCE, m_y + row * m_lineHeight);
     }
  };
//+------------------------------------------------------------------+
#endif // DASHBOARD_MQH

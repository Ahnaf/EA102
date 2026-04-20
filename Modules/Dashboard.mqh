//+------------------------------------------------------------------+
//|                                                   Dashboard.mqh  |
//|                        EA102 v2 - XAUUSD Prop Firm EA            |
//|       On-chart panel: dual engine scores, R tracking, status    |
//+------------------------------------------------------------------+
#ifndef DASHBOARD_MQH
#define DASHBOARD_MQH

#include "Utilities.mqh"
#include "PropProtection.mqh"
#include "SessionFilter.mqh"
#include "NewsFilter.mqh"
#include "RiskManager.mqh"

//+------------------------------------------------------------------+
//| CDashboard — ChartObjects status panel                          |
//+------------------------------------------------------------------+
class CDashboard
  {
private:
   int      m_x, m_y, m_lineH, m_fontSize;
   color    m_bgColor, m_titleColor, m_textColor;
   color    m_goodColor, m_warnColor, m_badColor, m_accentColor;
   string   m_fontName, m_prefix;
   long     m_chartId;

   CPropProtection *m_prop;
   CSessionFilter  *m_session;
   CNewsFilter     *m_news;
   CRiskManager    *m_risk;

   string   m_eaStatus;
   bool     m_active;

   //--- Live data (set each Update call)
   double   m_contScoreBuy;
   double   m_contScoreSell;
   double   m_revScore;
   ENUM_SIGNAL_DIR m_revDir;
   ENUM_SIGNAL_TYPE m_lastTradeType;
   double   m_lastContScore;
   double   m_lastRevScore;
   double   m_openTradeMaxR;
   double   m_openTradeCurR;

public:
   CDashboard()
      : m_x(10), m_y(30), m_lineH(18), m_fontSize(9),
        m_bgColor(C'12,14,22'), m_titleColor(clrGold), m_textColor(clrSilver),
        m_goodColor(clrLimeGreen), m_warnColor(clrOrange), m_badColor(clrRed),
        m_accentColor(clrCyan),
        m_fontName("Segoe UI"), m_prefix("EA102v2_"),
        m_prop(NULL), m_session(NULL), m_news(NULL), m_risk(NULL),
        m_active(true), m_eaStatus("ACTIVE"),
        m_contScoreBuy(0), m_contScoreSell(0), m_revScore(0),
        m_revDir(SIGNAL_NONE), m_lastTradeType(SIGNAL_TYPE_NONE),
        m_lastContScore(0), m_lastRevScore(0),
        m_openTradeMaxR(0), m_openTradeCurR(0)
     { m_chartId = ChartID(); }

   ~CDashboard() { Destroy(); }

   bool Init(CPropProtection *prop, CSessionFilter *session,
             CNewsFilter *news, CRiskManager *risk)
     {
      m_prop    = prop;
      m_session = session;
      m_news    = news;
      m_risk    = risk;
      CreateBG();
      return true;
     }

   void SetStatus(bool active, const string status) { m_active = active; m_eaStatus = status; }

   //--- Feed engine scores for display
   void SetEngineScores(double contBuy, double contSell, double revScore,
                        ENUM_SIGNAL_DIR revDir, ENUM_SIGNAL_TYPE lastType,
                        double openMaxR, double openCurR)
     {
      m_contScoreBuy  = contBuy;
      m_contScoreSell = contSell;
      m_revScore      = revScore;
      m_revDir        = revDir;
      m_lastTradeType = lastType;
      m_openTradeMaxR = openMaxR;
      m_openTradeCurR = openCurR;
     }

   void Update()
     {
      double bal      = AccountInfoDouble(ACCOUNT_BALANCE);
      double eq       = AccountInfoDouble(ACCOUNT_EQUITY);
      double floatPL  = eq - bal;
      double dailyDD  = (m_prop != NULL) ? m_prop.GetDailyDDPct() : 0;
      double maxDD    = (m_prop != NULL) ? m_prop.GetMaxDDPct()   : 0;
      double dailyPL  = (m_prop != NULL) ? m_prop.GetDailyPL()    : 0;
      int    nOpen    = (m_risk != NULL) ? m_risk.GetOpenTradeCount() : 0;
      int    nToday   = (m_risk != NULL) ? m_risk.GetTradesPerDay()   : 0;
      string sess     = (m_session != NULL) ? m_session.GetActiveSessionName() : "?";
      string newsStr  = (m_news != NULL && m_news.IsNewsBlocked()) ? "BLOCKED" : "Clear";
      string propStr  = (m_prop != NULL) ? m_prop.GetStatusString() : "?";
      string modeStr  = (m_risk != NULL) ? EnumToString(m_risk.GetTradeMode()) : "?";

      color propCol  = m_active ? m_goodColor : m_badColor;
      color newsCol  = (m_news != NULL && m_news.IsNewsBlocked()) ? m_warnColor : m_goodColor;
      color ddDCol   = (dailyDD > 3.5) ? m_badColor : (dailyDD > 2.0 ? m_warnColor : m_goodColor);
      color ddMCol   = (maxDD   > 7.0) ? m_badColor : (maxDD   > 4.0 ? m_warnColor : m_goodColor);
      color plCol    = (floatPL >= 0)  ? m_goodColor : m_warnColor;
      color dplCol   = (dailyPL >= 0)  ? m_goodColor : m_warnColor;

      // Engine score colours
      color csBuyCol  = (m_contScoreBuy  >= 0.65) ? m_goodColor : (m_contScoreBuy  >= 0.40 ? m_warnColor : m_textColor);
      color csSellCol = (m_contScoreSell >= 0.65) ? m_goodColor : (m_contScoreSell >= 0.40 ? m_warnColor : m_textColor);
      color revCol    = (m_revScore >= 0.60) ? m_goodColor : (m_revScore >= 0.40 ? m_warnColor : m_textColor);
      color rCol      = (m_openTradeCurR >= 1.0) ? m_goodColor : (m_openTradeCurR >= 0 ? m_warnColor : m_badColor);

      int r = 0;
      SetLbl("Title",  "═══  EA102 v2 · XAUUSD  ═══",   m_titleColor,  m_fontSize+1, r++);
      SetLbl("Blank0", "",                               m_textColor,   m_fontSize,   r++);

      // Account
      SetLbl("Bal",    StringFormat("Balance   : $%.2f",  bal),         m_textColor,  m_fontSize, r++);
      SetLbl("Eq",     StringFormat("Equity    : $%.2f",  eq),          m_textColor,  m_fontSize, r++);
      SetLbl("FPL",    StringFormat("Float P/L : %+.2f",  floatPL),     plCol,        m_fontSize, r++);
      SetLbl("DPL",    StringFormat("Today P/L : %+.2f",  dailyPL),     dplCol,       m_fontSize, r++);
      SetLbl("Blank1", "",                                               m_textColor,  m_fontSize, r++);

      // Drawdown
      SetLbl("DDd",    StringFormat("Daily DD  : %.2f%%", dailyDD),     ddDCol,       m_fontSize, r++);
      SetLbl("DDm",    StringFormat("Max DD    : %.2f%%", maxDD),       ddMCol,       m_fontSize, r++);
      SetLbl("Prof",   StringFormat("Prop      : %s",     propStr),     propCol,      m_fontSize, r++);
      SetLbl("Blank2", "",                                               m_textColor,  m_fontSize, r++);

      // Continuation Engine scores
      SetLbl("EngHd",  "── Continuation Engine ──",                     m_accentColor, m_fontSize, r++);
      SetLbl("CsBuy",  StringFormat("BUY  score : %.0f%%", m_contScoreBuy  * 100),  csBuyCol,  m_fontSize, r++);
      SetLbl("CsSel",  StringFormat("SELL score : %.0f%%", m_contScoreSell * 100),  csSellCol, m_fontSize, r++);
      SetLbl("Blank3", "",                                               m_textColor,  m_fontSize, r++);

      // Reversal Engine scores
      SetLbl("RevHd",  "── Reversal Engine ──",                         m_accentColor, m_fontSize, r++);
      string revDirStr = (m_revDir == SIGNAL_BUY) ? "BUY" : (m_revDir == SIGNAL_SELL) ? "SELL" : "---";
      SetLbl("RevSc",  StringFormat("Rev score  : %.0f%% %s", m_revScore * 100, revDirStr), revCol, m_fontSize, r++);
      SetLbl("Blank4", "",                                               m_textColor,  m_fontSize, r++);

      // R tracking
      SetLbl("RHd",    "── Open Trade R ──",                            m_accentColor, m_fontSize, r++);
      SetLbl("CurR",   StringFormat("Current R  : %.2f",  m_openTradeCurR), rCol,     m_fontSize, r++);
      SetLbl("MaxR",   StringFormat("Max R      : %.2f",  m_openTradeMaxR), m_goodColor, m_fontSize, r++);
      SetLbl("Blank5", "",                                               m_textColor,  m_fontSize, r++);

      // Context
      SetLbl("Sess",   StringFormat("Session   : %s",   sess),    m_goodColor,  m_fontSize, r++);
      SetLbl("News",   StringFormat("News      : %s",   newsStr), newsCol,      m_fontSize, r++);
      SetLbl("Mode",   StringFormat("Mode      : %s",   modeStr), m_textColor,  m_fontSize, r++);
      SetLbl("OTrd",   StringFormat("Open      : %d  Today: %d", nOpen, nToday), m_textColor, m_fontSize, r++);
      SetLbl("State",  StringFormat("Status    : %s",   m_eaStatus), m_active ? m_goodColor : m_badColor, m_fontSize, r++);
      SetLbl("Blank6", "",                                               m_textColor,  m_fontSize, r++);
      SetLbl("Time",   StringFormat("Server    : %s", GetTimeString()), m_textColor, m_fontSize-1, r++);

      // Resize BG to fit
      ObjectSetInteger(m_chartId, m_prefix + "BG", OBJPROP_YSIZE, r * m_lineH + 18);
      ChartRedraw(m_chartId);
     }

   void Destroy()
     {
      ObjectsDeleteAll(m_chartId, m_prefix);
      ChartRedraw(m_chartId);
     }

private:
   void CreateBG()
     {
      string nm = m_prefix + "BG";
      if(ObjectFind(m_chartId, nm) < 0)
         ObjectCreate(m_chartId, nm, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(m_chartId, nm, OBJPROP_XDISTANCE,  m_x - 6);
      ObjectSetInteger(m_chartId, nm, OBJPROP_YDISTANCE,  m_y - 6);
      ObjectSetInteger(m_chartId, nm, OBJPROP_XSIZE,      230);
      ObjectSetInteger(m_chartId, nm, OBJPROP_YSIZE,      540);
      ObjectSetInteger(m_chartId, nm, OBJPROP_BGCOLOR,    m_bgColor);
      ObjectSetInteger(m_chartId, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(m_chartId, nm, OBJPROP_COLOR,      clrDimGray);
      ObjectSetInteger(m_chartId, nm, OBJPROP_BACK,       false);
      ObjectSetInteger(m_chartId, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chartId, nm, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
     }

   void SetLbl(const string id, const string text, color clr, int fs, int row)
     {
      string nm = m_prefix + id;
      if(ObjectFind(m_chartId, nm) < 0)
        {
         ObjectCreate(m_chartId, nm, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(m_chartId, nm, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chartId, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chartId, nm, OBJPROP_BACK,       false);
        }
      ObjectSetString (m_chartId, nm, OBJPROP_TEXT,     text);
      ObjectSetString (m_chartId, nm, OBJPROP_FONT,     m_fontName);
      ObjectSetInteger(m_chartId, nm, OBJPROP_FONTSIZE, fs);
      ObjectSetInteger(m_chartId, nm, OBJPROP_COLOR,    clr);
      ObjectSetInteger(m_chartId, nm, OBJPROP_XDISTANCE, m_x);
      ObjectSetInteger(m_chartId, nm, OBJPROP_YDISTANCE, m_y + row * m_lineH);
     }
  };

#endif // DASHBOARD_MQH

// Trailing Stop on Profit EA
// Copyright 2023, Your Name
// https://www.yourwebsite.com

#property copyright "EarnForex & Wiseman-Timelord"
#property link      "https://github.com/wiseman-timelord/Trailing-Stop-on-Profit-WT"
#property link      "https://github.com/EarnForex/Trailing-Stop-on-Profit"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>

// Expert Advisor Settings
input group "Expert Advisor Settings"
input int    TrailingStop = 50;   // Trailing Stop, points
input int    Profit       = 100;  // Profit threshold
input int    MagicNumber  = 123456; // Magic Number

// Global variables
int          OrderOpRetry = 5;    // Retry attempts
bool         EnableTrailing = true; // Trailing stop enabled
CTrade       Trade;
CPositionInfo Position;
CSymbolInfo  Symbol;
CAccountInfo Account;

// Position info structure
struct PositionInfo
{
    ulong ticket;
    string symbol;
    ENUM_POSITION_TYPE type;
    double openPrice;
    double currentPrice;
    double stopLoss;
    double takeProfit;
    double profit;
    bool isTrailing;
};

// Initialization function
int OnInit()
{
    // Set magic number
    Trade.SetExpertMagicNumber(MagicNumber);
    
    // Set symbol name
    if(!Symbol.Name(_Symbol))
    {
        Print("Failed to set symbol");
        return INIT_FAILED;
    }
    
    // Refresh symbol rates
    if(!Symbol.RefreshRates())
    {
        Print("Failed to refresh rates");
        return INIT_FAILED;
    }
    
    // Check trailing stop
    long stopLevel = Symbol.StopsLevel();
    if(TrailingStop < stopLevel)
    {
        Print("TrailingStop too small. Minimum:", stopLevel);
        return INIT_PARAMETERS_INCORRECT;
    }
    
    return(INIT_SUCCEEDED);
}

// Tick function
void OnTick()
{
    if(EnableTrailing)
    {
        TrailingStop();
    }
    DisplayOverlay();
}

// Chart event function
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_KEYDOWN)
    {
        if(lparam == 27) // Escape key
        {
            if(MessageBox("Close the EA?", "Terminate?", MB_YESNO) == IDYES)
            {
                ExpertRemove();
            }
        }
    }
}

// Trailing Stop function
void TrailingStop()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!Position.SelectByIndex(i)) continue;
        
        // Check symbol and magic
        if(Position.Symbol() != Symbol.Name() || Position.Magic() != MagicNumber) continue;

        double currentPrice = (Position.PositionType() == POSITION_TYPE_BUY) ? Symbol.Bid() : Symbol.Ask();
        double openPrice = Position.PriceOpen();
        double stopLoss = Position.StopLoss();
        double takeProfit = Position.TakeProfit();
        
        // Calculate minimum profit
        double minProfit = Profit * Symbol.Point();
        
        // Check profit threshold
        if(MathAbs(currentPrice - openPrice) >= minProfit)
        {
            double newStopLoss = CalculateNewStopLoss(Position.PositionType(), currentPrice);
            
            // Modify if better
            if((Position.PositionType() == POSITION_TYPE_BUY && newStopLoss > stopLoss) ||
               (Position.PositionType() == POSITION_TYPE_SELL && (newStopLoss < stopLoss || stopLoss == 0)))
            {
                ModifyPosition(Position.Ticket(), newStopLoss, takeProfit);
            }
        }
    }
}

// Calculate new StopLoss
double CalculateNewStopLoss(ENUM_POSITION_TYPE posType, double currentPrice)
{
    double newSL = 0;
    double tsPoints = TrailingStop * Symbol.Point();
    
    if(posType == POSITION_TYPE_BUY)
    {
        newSL = NormalizeDouble(currentPrice - tsPoints, Symbol.Digits());
    }
    else if(posType == POSITION_TYPE_SELL)
    {
        newSL = NormalizeDouble(currentPrice + tsPoints, Symbol.Digits());
    }
    
    return newSL;
}

// Modify position
void ModifyPosition(ulong ticket, double newSL, double TP)
{
    for(int attempt = 0; attempt < OrderOpRetry; attempt++)
    {
        if(Trade.PositionModify(ticket, newSL, TP))
        {
            Print("Update success:", ticket, newSL);
            break;
        }
        else
        {
            Print("Update failed:", ticket, GetLastError());
            Sleep(1000); // Wait before retry
        }
    }
}

// Get open positions info
PositionInfo[] GetOpenPositionsInfo()
{
    PositionInfo[] positions;
    ArrayResize(positions, PositionsTotal());
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(!Position.SelectByIndex(i)) continue;
        
        positions[i].ticket = Position.Ticket();
        positions[i].symbol = Position.Symbol();
        positions[i].type = Position.PositionType();
        positions[i].openPrice = Position.PriceOpen();
        positions[i].currentPrice = (positions[i].type == POSITION_TYPE_BUY) ? Symbol.Bid() : Symbol.Ask();
        positions[i].stopLoss = Position.StopLoss();
        positions[i].takeProfit = Position.TakeProfit();
        positions[i].profit = Position.Profit();
        positions[i].isTrailing = (MathAbs(positions[i].currentPrice - positions[i].openPrice) >= Profit * Symbol.Point());
    }
    
    return positions;
}

// Display overlay
void DisplayOverlay()
{
    PositionInfo[] positions = GetOpenPositionsInfo();
    
    string displayText = "Trailing Stop on Profit EA\n";
    displayText += "Trailing: " + (EnableTrailing ? "Enabled" : "Disabled") + "\n";
    displayText += "Trailing Stop: " + IntegerToString(TrailingStop) + " points\n";
    displayText += "Profit Threshold: " + IntegerToString(Profit) + " points\n";
    displayText += "Account Balance: " + DoubleToString(Account.Balance(), 2) + " " + Account.Currency() + "\n\n";
    
    int positionsCount = ArraySize(positions);
    if(positionsCount > 0)
    {
        displayText += "Open Positions:\n";
        for(int i = 0; i < positionsCount; i++)
        {
            if(positions[i].symbol != Symbol.Name()) continue; // Current symbol only
            
            displayText += "Ticket: " + IntegerToString(positions[i].ticket) + "\n";
            displayText += "  Type: " + EnumToString(positions[i].type) + "\n";
            displayText += "  Open: " + DoubleToString(positions[i].openPrice, Symbol.Digits()) + "\n";
            displayText += "  Current: " + DoubleToString(positions[i].currentPrice, Symbol.Digits()) + "\n";
            displayText += "  SL: " + DoubleToString(positions[i].stopLoss, Symbol.Digits()) + "\n";
            displayText += "  TP: " + DoubleToString(positions[i].takeProfit, Symbol.Digits()) + "\n";
            displayText += "  Profit: " + DoubleToString(positions[i].profit, 2) + "\n";
            displayText += "  Trailing: " + (positions[i].isTrailing ? "Active" : "Inactive") + "\n\n";
        }
    }
    else
    {
        displayText += "No open positions\n";
    }
    
    Comment(displayText);
}
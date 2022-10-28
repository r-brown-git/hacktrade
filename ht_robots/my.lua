dofile(string.format("%s\\lua\\hacktrade-ffeast.lua", getWorkingFolder()))

require("utils2")		 -- вспомогательные функции

function Robot()

	ACC ="SPBFUT****"		-- торговый счет
	CLI = "158****"			-- код клиента
	FUT_CLASS = "SPBFUT"		-- класс FORTS
	FUT_TICKER = "SRZ2"		-- код бумаги фьючерса

	feed = MarketData{
        market = FUT_CLASS,
        ticker = FUT_TICKER,
    }
	
	order1 = SmartOrder{
        account = ACC,
        client = CLI,
        market = FUT_CLASS,
        ticker = FUT_TICKER,
    }
	
	local is_trading_time = isTradingTime()

	if is_trading_time and check() then
		message("session inactive, waiting for trading status")
	else
		message("active")
	end
 
	sleep(500)
end

function check()
	message("i'm working")
	return tonumber(getParamEx(FUT_CLASS, FUT_TICKER, "TRADINGSTATUS").param_value) ~= 1
end
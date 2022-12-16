dofile(string.format("%s\\lua\\hacktrade-ffeast.lua", getWorkingFolder()))

require("Black-Scholes") -- функции расчета теоретической цены и греков
require("utils2")		 -- вспомогательные функции

-- Дельта-хэджер по всем открытым позициям заданного тикера

function Robot()

	FIRMID = "SPBFUT58****" -- код фирмы
	ACC = "SPBFUT****"		-- торговый счет
	CLI = "158****"			-- код клиента
	FUT_CLASS = "SPBFUT"
	OPT_CLASS = "SPBOPT"
	FUT_TICKER = "SRZ2"
	
	MIN_DELTA = -1			-- если дельта позиции становится ниже MIN_DELTA, увеличить дельту до MIN_DELTA
	MAX_DELTA = 1			-- если дельта позиции становится выше MAX_DELTA, уменьшить дельту до MAX_DELTA
	SENSITIVITY_DELTA = 2	-- хеджировать только если отклонение дельты позиции превышает SENSITIVITY_DELTA
	
	feed = MarketData {
		market = FUT_CLASS,
		ticker = FUT_TICKER,
	}
	
	order = SmartOrder {
		market = FUT_CLASS,
		ticker = FUT_TICKER,
		account = ACC,
		client = CLI,
	}
	
	local last_update_day = 0
	local all_opt_list = {}
	local our_opt_list = {}
	local i
	local opt_ticker
	local dt
	local pos = {}
	local delta = 0
	local sum_delta
	local opt_strike
	local opt_month
	local opt_type
	local hedge_count
	local planned
	
	local function isReady()
		if isConnected() == 1 then
			if isTradingTime() then
				if tonumber(getParamEx(FUT_CLASS, FUT_TICKER, "TRADINGSTATUS").param_value) == 1 then
					return true
				end
			end
		end
		
		log:trace("waiting for a resuming trading")
		sleep(15000)
		return false
	end

	while true do
		
		if isReady() then
		
			dt = os.sysdate()
			
			if last_update_day == 0 or dt["day"] ~= last_update_day and dt["hour"] >= 19 then
				last_update_day = dt["day"]
				
				all_opt_list = string.split(getClassSecurities(OPT_CLASS), ',')
				log:trace("fetched " .. #all_opt_list .. " option codes")
				
				for i, opt_ticker in ipairs(all_opt_list) do
					if opt_ticker:sub(1, 2) == FUT_TICKER:sub(1, 2) then
						table.insert(our_opt_list, opt_ticker)
					end
				end
			end
			
			sum_delta = 0
			hedge_count = 0
			
			for i, opt_ticker in ipairs(our_opt_list) do
				pos = getFuturesHolding(FIRMID, ACC, opt_ticker, 0)
				if pos and pos.totalnet ~= 0 then

					opt_strike, opt_month = string.match(opt_ticker, '^%a%a([%d]+[.]?[%d]*)B(%a)%d%a?$')
					opt_type = isOptionCall(opt_month) and "Call" or "Put"
					
					tmpParam = {
						["optiontype"] = opt_type,                                                                  -- тип опциона
						["settleprice"] = feed.last,           														-- текущая цена фьючерса
						["strike"] = opt_strike,                       												-- страйк опциона
						["volatility"] = getParamEx(OPT_CLASS, opt_ticker, "volatility").param_value,     			-- волатильность опциона из QUIK
						["DAYS_TO_MAT_DATE"] = getParamEx(OPT_CLASS, opt_ticker, "DAYS_TO_MAT_DATE").param_value    -- число дней до экспирации опциона
					}
					
					delta = Greeks(tmpParam)["Delta"]

					sum_delta = sum_delta + pos.totalnet * delta
					
				end
			end
			
			pos = getFuturesHolding(FIRMID, ACC, FUT_TICKER, 0)
			if pos and pos.totalnet ~= 0 then
				sum_delta = sum_delta + pos.totalnet
			end
			
			if sum_delta < MIN_DELTA - SENSITIVITY_DELTA then
				hedge_count = round(MIN_DELTA - sum_delta, 0)
			elseif sum_delta > MAX_DELTA + SENSITIVITY_DELTA then
				hedge_count = -round(sum_delta - MAX_DELTA, 0)
			end
			
			log:trace(string.format("delta: %.4f; hedge_count: %d", sum_delta, hedge_count))
			
			if hedge_count ~= 0 then
				planned = order.position + hedge_count
				repeat
					order:update(formatPrice(feed.last), planned)
					Trade()
					sleep(500)
				until order.filled
			end
			
			sleep(15000)
		end
	end
end

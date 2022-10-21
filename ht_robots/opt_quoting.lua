dofile(string.format("%s\\lua\\hacktrade-ffeast.lua", getWorkingFolder()))

require("Black-Scholes") -- функции расчета теоретической цены и греков
require("utils2")		 -- вспомогательные функции

function Robot()

	ACC = "SPBFUT****"				-- торговый счет
	CLI = "158****"					-- код клиента
	FUT_CLASS = "SPBFUT"
	OPT_CLASS = "SPBOPT"
	FUT_TICKER = "SRZ2" 			-- FUT_TICKER = "SRZ2"
	OPT_TICKER = "SR11000BJ2B" 		-- OPT_TICKER = "SR11000BJ2B"
	
	ORDER1_SIZE = 3					-- число лотов на покупку
	ORDER2_SIZE = 1					-- число лотов на продажу
	ORDER1_MIN_PROFIT_VOLA = -6.00	-- минимальная скидка покупки по волатильности, чтобы не стоять в конце стакана, если есть конкуренты
	ORDER1_MAX_PROFIT_VOLA = -10.00	-- максимальная: если стакан пустой, котируем покупку по цене девешле на это значение волатильности
	ORDER2_MIN_PROFIT_VOLA = 6.00
	ORDER2_MAX_PROFIT_VOLA = 10.00
	SENSITIVITY = 3					-- люфт - разница между текущей ценой заявки и новой расчетной ценой в шагах цены. Если разница меньше, чем люфт, то имеющуюся заявку не меняем.
	
	SLEEP_WITH_ORDER = 5000	-- время ожидания исполнения выставленного ордера до пересчета теоретической цены (в миллисекундах)
	SLEEP_WO_ORDER = 100	-- время ожидания после снятия ордера (в миллисекундах)
	
	feed = MarketData {
		market = OPT_CLASS,
		ticker = OPT_TICKER,
	}
	
	-- ордер на покупку
	order1 = SmartOrder {
		market = OPT_CLASS,
		ticker = OPT_TICKER,
		account = ACC,
		client = CLI,
	}
	
	-- ордер на продажу
	order2 = SmartOrder {
		market = OPT_CLASS,
		ticker = OPT_TICKER,
		account = ACC,
		client = CLI,
	}
	
	local step = feed.SEC_PRICE_STEP
	local optiontype = getParamEx(OPT_CLASS, OPT_TICKER, "optiontype").param_image
	local strike = getParamEx(OPT_CLASS, OPT_TICKER, "strike").param_value+0
	local tmpParam = {}
	
	local theor_price_quik = 0
	local theor_price_min_profit1 = 0
	local theor_price_max_profit1 = 0
	local theor_price_min_profit2 = 0
	local theor_price_max_profit2 = 0
	local price1_prev = 0
	local price1 = 0
	local price2_prev = 0
	local price2 = 0
	local best_offer = 0
	local best_bid = 0
	
	local is_trading_time = true
	
	while true do
		
		while isConnected() ~= 1 or tonumber(getParamEx(FUT_CLASS, FUT_TICKER, "TRADINGSTATUS").param_value) ~= 1 do
			log:trace("not connected, waiting for connection")
			sleep(15000)
		end
		
		if is_trading_time and not isTradingTime() then
			log:trace("trading time ended, cancelling orders")
			is_trading_time = false
			order1:update(nil, order1.position)
			order2:update(nil, order2.position)
			Trade()
		end
			
		while not is_trading_time do
			if isTradingTime() then
				log:trace("trading time started, resuming orders")
				is_trading_time = true
			else
				log:trace("waiting for a resuming trading")
				sleep(15000)
			end
		end

		tmpParam = {
			["optiontype"] = optiontype,                                                                -- тип опциона
			["settleprice"] = getParamEx(FUT_CLASS, FUT_TICKER, "settleprice").param_value+0,           -- текущая цена фьючерса
			["strike"] = strike,                       													-- страйк опциона
			["volatility"] = feed.volatility,                                                         	-- волатильность опциона из QUIK
			["DAYS_TO_MAT_DATE"] = feed.DAYS_TO_MAT_DATE    											-- число дней до экспирации опциона
		}
		
		theor_price_quik = TheorPrice(tmpParam)
		
		tmpParam.volatility = feed.volatility + ORDER1_MIN_PROFIT_VOLA
		theor_price_min_profit1 = TheorPrice(tmpParam)

		tmpParam.volatility = feed.volatility + ORDER1_MAX_PROFIT_VOLA
		theor_price_max_profit1 = TheorPrice(tmpParam)

		tmpParam.volatility = feed.volatility + ORDER2_MIN_PROFIT_VOLA
		theor_price_min_profit2 = TheorPrice(tmpParam)
		
		tmpParam.volatility = feed.volatility + ORDER2_MAX_PROFIT_VOLA
		theor_price_max_profit2 = TheorPrice(tmpParam)

		if feed.bids[1] ~= nil then
			if feed.bids[1].price ~= tonumber(order1.price) then
				best_bid = feed.bids[1].price
			elseif (feed.bids[2] ~= nil) then
				best_bid = feed.bids[2].price
			end
		end
		
		if feed.offers[1] ~= nil then
			if feed.offers[1].price ~= tonumber(order2.price) then
				best_offer = feed.offers[1].price
			elseif (feed.offers[2] ~= nil) then
				best_offer = feed.offers[2].price
			end
		end

		price1 = theor_price_max_profit1
		if best_bid ~= 0 then
			if best_bid > price1 then
				if best_bid > theor_price_min_profit1 then
					price1 = theor_price_min_profit1
				else
					price1 = (best_bid + theor_price_min_profit1) / 2
				end
			end
		end

		price2 = theor_price_max_profit2
		if best_offer ~= 0 then
			if best_offer < price2 then
				if best_offer < theor_price_min_profit2 then
					price2 = theor_price_min_profit2
				else
					price2 = (best_offer + theor_price_min_profit2) / 2
				end
			end
		end

		if math.abs(price1 - price1_prev) < SENSITIVITY * step then
			price1 = price1_prev
		else
			price1_prev = price1
		end

		if math.abs(price2 - price2_prev) < SENSITIVITY * step then
			price2 = price2_prev
		else
			price2_prev = price2
		end

		-- защита от отрицательной или нулевой цены
		if price1 < step then
			price1 = step
		end
		if price2 < step then
			price2 = step
		end

		theor_price_quik = theor_price_quik - math.fmod(theor_price_quik, step)
		
		theor_price_max_profit1 = theor_price_max_profit1 - math.fmod(theor_price_max_profit1, step)
		theor_price_min_profit1 = theor_price_min_profit1 - math.fmod(theor_price_min_profit1, step)
		best_bid = best_bid - math.fmod(best_bid, step)
		price1 = price1 - math.fmod(price1, step)
		
		theor_price_max_profit2 = theor_price_max_profit2 - math.fmod(theor_price_max_profit2, step)
		theor_price_min_profit2 = theor_price_min_profit2 - math.fmod(theor_price_min_profit2, step)
		best_bid = best_bid - math.fmod(best_bid, step)
		price2 = price2 - math.fmod(price2, step)
		
		order1:update(formatPrice(price1), ORDER1_SIZE-order2.position)

		order2:update(formatPrice(price2), -(ORDER2_SIZE+order1.position))
		
		Trade()
		
		log:trace(
			"T ".. formatPrice(theor_price_quik) .. "; " .. 
			"buy " .. (order1.planned - order1.position) .. " {" .. formatPrice(theor_price_max_profit1).. "-" .. formatPrice(theor_price_min_profit1) .. "; " ..
			"bid " .. formatPrice(best_bid).. "; " .. 
			"price " .. formatPrice(price1).. "} " ..
			"sell " .. -(order2.planned - order2.position) .. " {" .. formatPrice(theor_price_max_profit2).. "-" .. formatPrice(theor_price_min_profit2) .. "; " ..
			"offer " .. formatPrice(best_offer).. "; " .. 
			"price " .. formatPrice(price2).. "}"
		);
		
		if 
			(order1.planned - order1.position == 0 or order1.order ~= nil and order1.order.price - price1 == 0) and 
			(order2.planned - order2.position == 0 or order2.order ~= nil and order2.order.price - price2 == 0)
		then
			sleep(SLEEP_WITH_ORDER)
		else
			sleep(SLEEP_WO_ORDER)
		end
	end
end

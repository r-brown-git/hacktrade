dofile("../hacktrade-ffeast.lua")

require("Black-Scholes") -- функции расчета теоретической цены и греков
require("utils2")		 -- вспомогательные функции

function Robot()

	ACC = "SPBFUT*****"
	CLI = "158****"
	FUT_CLASS = "SPBFUT"
	OPT_CLASS = "SPBOPT"
	FUT_TICKER = "SRZ2" 			-- FUT_TICKER = "SRZ2"
	OPT_TICKER = "SR10750BV2D" 		-- OPT_TICKER = "SR11000BJ2B"
	
	ORDER1_SIZE = 1					-- число лотов на покупку
	ORDER2_SIZE = 1					-- число лотов на продажу
	ORDER1_MIN_PROFIT_VOLA = -12.00	-- минимальная скидка покупки по волатильности, чтобы не стоять в конце стакана, если есть конкуренты
	ORDER1_MAX_PROFIT_VOLA = -18.00	-- максимальная: если стакан пустой, котируем покупку по цене девешле на это значение волатильности
	ORDER2_MIN_PROFIT_VOLA = 12.00
	ORDER2_MAX_PROFIT_VOLA = 18.00
	SENSITIVITY = 3					-- люфт - разница между текущей ценой заявки и новой расчетной ценой в шагах цены. Если разница меньше, чем люфт, то имеющуюся заявку не меняем.
	
	SLEEP_WITH_ORDER = 5000	-- время ожидания исполнения выставленного ордера до пересчета теоретической цены (в миллисекундах)
	SLEEP_WO_ORDER = 100	-- время ожидания после снятия ордера (в миллисекундах)
	
	feed = MarketData {
		market = OPT_CLASS,
		ticker = OPT_TICKER,
	}
	
	order1 = SmartOrder {
		market = OPT_CLASS,
		ticker = OPT_TICKER,
		account = ACC,
		client = CLI,
	}
	
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
	local order1_theor_price_min_profit = 0
	local order1_theor_price_max_profit = 0
	local order2_theor_price_min_profit = 0
	local order2_theor_price_max_profit = 0
	local order1_price_prev = 0
	local order1_price = 0
	local order2_price_prev = 0
	local order2_price = 0
	local best_offer = 0
	local best_bid = 0
	
	while true do
		
		while isConnected() ~= 1 or not isTradingTime() do
			sleep(15000)
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
		order1_theor_price_min_profit = TheorPrice(tmpParam)

		tmpParam.volatility = feed.volatility + ORDER1_MAX_PROFIT_VOLA
		order1_theor_price_max_profit = TheorPrice(tmpParam)

		tmpParam.volatility = feed.volatility + ORDER2_MIN_PROFIT_VOLA
		order2_theor_price_min_profit = TheorPrice(tmpParam)
		
		tmpParam.volatility = feed.volatility + ORDER2_MAX_PROFIT_VOLA
		order2_theor_price_max_profit = TheorPrice(tmpParam)

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

		order1_price = order1_theor_price_max_profit
		if best_bid ~= 0 then
			if best_bid > order1_price then
				if best_bid > order1_theor_price_min_profit then
					order1_price = order1_theor_price_min_profit
				else
					order1_price = (best_bid + order1_theor_price_min_profit) / 2
				end
			end
		end

		order2_price = order2_theor_price_max_profit
		if best_offer ~= 0 then
			if best_offer < order2_price then
				if best_offer < order2_theor_price_min_profit then
					order2_price = order2_theor_price_min_profit
				else
					order2_price = (best_offer + order2_theor_price_min_profit) / 2
				end
			end
		end

		if math.abs(order1_price - order1_price_prev) < SENSITIVITY * step then
			order1_price = order1_price_prev
		else
			order1_price_prev = order1_price
		end

		if math.abs(order2_price - order2_price_prev) < SENSITIVITY * step then
			order2_price = order2_price_prev
		else
			order2_price_prev = order2_price
		end

		-- защита от отрицательной или нулевой цены
		if order1_price < step then
			order1_price = step
		end
		if order2_price < step then
			order2_price = step
		end

		theor_price_quik = theor_price_quik - math.fmod(theor_price_quik, step)
		
		order1_theor_price_max_profit = order1_theor_price_max_profit - math.fmod(order1_theor_price_max_profit, step)
		order1_theor_price_min_profit = order1_theor_price_min_profit - math.fmod(order1_theor_price_min_profit, step)
		best_bid = best_bid - math.fmod(best_bid, step)
		order1_price = order1_price - math.fmod(order1_price, step)
		
		order2_theor_price_max_profit = order2_theor_price_max_profit - math.fmod(order2_theor_price_max_profit, step)
		order2_theor_price_min_profit = order2_theor_price_min_profit - math.fmod(order2_theor_price_min_profit, step)
		best_bid = best_bid - math.fmod(best_bid, step)
		order2_price = order2_price - math.fmod(order2_price, step)
		
		order1:update(formatPrice(order1_price), ORDER1_SIZE-order2.position)

		order2:update(formatPrice(order2_price), -(ORDER2_SIZE+order1.position))
		
		Trade()
		
		log:trace(
			"T ".. formatPrice(theor_price_quik) .. "; " .. 
			"buy " .. order1.planned .. " {" .. formatPrice(order1_theor_price_max_profit).. "-" .. formatPrice(order1_theor_price_min_profit) .. "; " ..
			"bid " .. formatPrice(best_bid).. "; " .. 
			"price " .. formatPrice(order1_price).. "} " ..
			"sell " .. -order2.planned .. " {" .. formatPrice(order2_theor_price_max_profit).. "-" .. formatPrice(order2_theor_price_min_profit) .. "; " ..
			"offer " .. formatPrice(best_offer).. "; " .. 
			"price " .. formatPrice(order2_price).. "}"
		);
		
		if order1.order ~= nil and order1.order.price == order1_price or order2.order ~= nil and order2.order.price == order2_price then
			sleep(SLEEP_WITH_ORDER)
		else
			sleep(SLEEP_WO_ORDER)
		end
	end
end

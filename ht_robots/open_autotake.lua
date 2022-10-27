dofile(string.format("%s\\lua\\hacktrade-ffeast.lua", getWorkingFolder()))

require("utils2")		 -- вспомогательные функции

-- Робот для набора позиции заданного объема лесенкой, где каждая следующая покупка(продажа) дешевле(дороже) предыдущей.
-- При исполнении заявки, выставляется противоположная, тейк-профит, чтобы сразу закрыть часть в плюс и продолжить набирать позицию
-- Удобно использовать для хеджирования купленных опционов

function Robot()

	ACC = "SPBFUT****"		-- торговый счет
	CLI = "158****"			-- код клиента
	FUT_CLASS = "SPBFUT"	-- класс FORTS
	FUT_TICKER = "SRZ2"		-- код бумаги фьючерса
	
	-- покупка
	ORDER1_MAX = 30				-- макс лотов может быть набрано в лонг
	ORDER1_PART = 1				-- лотов в одной заявке
	ORDER1_FROM_CENTER = -50	-- цена первой покупки при отклонении от цены старта на это значение
	ORDER1_STEP = -10			-- следующая покупка ниже предыдущей на это значение
	
	-- продажа
	ORDER2_MAX = -30			-- макс лотов может быть набрано в шорт
	ORDER2_PART = -1			-- лотов в одной заявке
	ORDER2_FROM_CENTER = 50		-- цена первой продажи при отклонении от цены старта на это значение
	ORDER2_STEP = 10			-- следующая продажа выше предыдущей на это значение
	
	SLEEP_WITH_ORDER = 5000	-- время ожидания исполнения выставленного ордера до пересчета теоретической цены (в миллисекундах)
	SLEEP_WO_ORDER = 100	-- время ожидания после снятия ордера (в миллисекундах)
	
	order1 = SmartOrder{
        account = ACC,
        client = CLI,
        market = FUT_CLASS,
        ticker = FUT_TICKER,
    }
	
	order2 = SmartOrder{
        account = ACC,
        client = CLI,
        market = FUT_CLASS,
        ticker = FUT_TICKER,
    }
	
	local center = getParamEx(FUT_CLASS, FUT_TICKER, "settleprice").param_value

	local sec_price_step = getParamEx(FUT_CLASS, FUT_TICKER, "SEC_PRICE_STEP").param_value
	
	local price1
	local planned1
	local price2
	local planned2
	
	local is_trading_time = true
	
	local function isReady()
		if isConnected() ~= 1 then
			log:trace("not connected, waiting for connection")
			sleep(15000)
			return false
		end
		
		if tonumber(getParamEx(FUT_CLASS, FUT_TICKER, "TRADINGSTATUS").param_value) ~= 1 then
			log:trace("session inactive, waiting for trading status")
			sleep(15000)
			return false
		end
		
		if is_trading_time then
			if isTradingTime() then
				return true
			else
				log:trace("trading time ending, cancelling orders")
				is_trading_time = false
				order1:update(nil, order1.position)
				order2:update(nil, order2.position)
				Trade()
				return false
			end
		else
			if isTradingTime() then
				log:trace("trading time started, resuming orders")
				is_trading_time = true
				return true
			else
				log:trace("waiting for a resuming trading")
				sleep(15000)
				return false
			end
		end
	end

	log:trace(string.format("center: %s; order1 {%s; %s; %s}; order2 {%s; %s; %s}", formatPrice(center), ORDER1_MAX, ORDER1_FROM_CENTER, ORDER1_STEP, ORDER2_MAX, ORDER2_FROM_CENTER, ORDER2_STEP))

    while true do
		
		if isReady() then

			if order1.position + order2.position < ORDER1_MAX then
				price1 = formatPrice(center + ORDER1_FROM_CENTER + (order1.position+order2.position)*ORDER1_STEP)
				planned1 = order1.position + ORDER1_PART
				order1:update(price1, planned1)
				log:trace(string.format("order1 pos: %s; planned: %s; price: %s", order1.position, planned1, price1))
			else
				log:trace(string.format("order1 max pos %s reached: %s ; %s", ORDER1_MAX, order1.position, order2.position))
			end
			
			if order1.position + order2.position > ORDER2_MAX then
				price2 = formatPrice(center + ORDER2_FROM_CENTER - (order2.position+order1.position)*ORDER2_STEP)
				planned2 = order2.position + ORDER2_PART
				order2:update(price2, planned2)
				log:trace(string.format("order2 pos: %s; planned: %s; price: %s", order2.position, planned2, price2))
			else
				log:trace(string.format("order2 max pos %s reached: %s ; %s", ORDER2_MAX, order1.position, order2.position))
			end
			
			
			Trade()
			
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

end

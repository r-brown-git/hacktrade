dofile(string.format("%s\\lua\\hacktrade-ffeast.lua", getWorkingFolder()))

require("utils2")		 -- вспомогательные функции

function Robot()

	ACC = "SPBFUT****"		-- торговый счет
	CLI = "158****"			-- код клиента
	FUT_CLASS = "SPBFUT"		-- класс FORTS
	FUT_TICKER = "SRZ2"		-- код бумаги фьючерса
	
	PRICE_INTERVAL = 15		-- покупка выше центра, продажа ниже центра
	PRICE_STEP = 10			-- между частями продаж/покупок
	ICEBERG_SIZE = 50
	ICEBERG_PART = 2
	
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
	
	log:trace("center "..formatPrice(center).."; interval "..formatPrice(PRICE_INTERVAL).."; step "..formatPrice(PRICE_STEP))
	
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
		
		if math.abs(order1.position + order2.position) < ICEBERG_SIZE then
			
			price1 = formatPrice(center + PRICE_INTERVAL + (-order1.position-order2.position+1) * ICEBERG_PART * PRICE_STEP)
			planned1 = order1.position - ICEBERG_PART
			order1:update(price1, planned1)
			log:trace("order1 pos: "..order1.position.."; planned: "..formatPrice(planned1).."; price: "..formatPrice(price1))

			price2 = formatPrice(center - PRICE_INTERVAL - (order2.position+order1.position+1) * ICEBERG_PART * PRICE_STEP)
			planned2 = order2.position + ICEBERG_PART
			order2:update(price2, planned2)
			log:trace("order2 pos: "..order2.position.."; planned: "..formatPrice(planned2).."; price: "..formatPrice(price2))
		else 
			log:trace("max position reached, order1: " ..order1.position .. "; order2: " .. order2.position)
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











dofile(getScriptPath().."\\hacktrade-ffeast.lua")

function Robot()

	local ACC ="SPBFUT*****"		-- торговый счет
	local CLI = "158****"			-- код клиента
	local FUT_CLASS = "SPBFUT"		-- класс FORTS
	local FUT_TICKER = "SRZ2"		-- код бумаги фьючерса
	
	local PRICE_INTERVAL = 35		-- покупка выше центра, продажа ниже центра
	local PRICE_STEP = 15			-- между частями продаж/покупок
	local ICEBERG_SIZE = 10
	local ICEBERG_PART = 1

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

    while true do
	
		while isConnected() ~= 1 or not IsTradingTime() do
			sleep(15000)
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
		
		if order1.order ~= nil and order2.order ~= nil and order1.order.price == price1 and order2.order.price == price2 then
			sleep (5000)
		else
			sleep (100)
		end
	end

end

function formatPrice(price)
    price = tostring(price)

    if string.match(price, "%.(0+)") then
        price = string.format("%.0f", price)
    end

    return price
end

function IsTradingTime()
	local dt = os.sysdate()
	local minutes_count = dt["hour"] * 60 + dt["min"]
	
	 -- < 09:05
	if minutes_count < 9*60 + 5 then
		return false
	end
	-- 14:00 - 14:05
	if minutes_count > 14*60 and minutes_count < 14*60 + 5 then
		return false
	end
	-- 18:45 - 19:05
	if minutes_count > 18*60 + 45 and minutes_count < 19*60 + 5 then
		return false
	end
	-- > 23:45
	if minutes_count > 23*60 + 45 then
		return false
	end
	
	return true
end












dofile(string.format("%s\\lua\\hacktrade-ffeast.lua", getWorkingFolder()))

require("utils2")		 -- вспомогательные функции

-- Робот выставляет одновременно заявки и на покупку, и на продажу айсбергами.
-- При исполнении одной из них размер айсберга противоположной заявки пополняется на исполненное кол-во лотов
-- Изменено: при продаже присоединяемся к лучшему офферу, а при покупке ко второму биду в стакане, чтоб избежать манипуляций

function Robot()

	ACC = "SPBFUT****"		-- торговый счет
	CLI = "158****"			-- код клиента
	FUT_CLASS = "SPBFUT"	-- класс FORTS
	FUT_TICKER = "VIX2"		-- код бумаги фьючерса
	
	-- покупка
	ORDER1_MAX = 2				-- макс лотов может быть набрано в лонг
	ORDER1_PART = 1				-- лотов в одной заявке
	
	-- продажа
	ORDER2_MAX = -2				-- макс лотов может быть набрано в шорт
	ORDER2_PART = -1			-- лотов в одной заявке
	
	SLEEP_WITH_ORDER = 5000	-- время ожидания исполнения выставленного ордера до пересчета теоретической цены (в миллисекундах)
	SLEEP_WO_ORDER = 100	-- время ожидания после снятия ордера (в миллисекундах)
	
	feed = MarketData{
        market = FUT_CLASS,
        ticker = FUT_TICKER,
    }
	
	-- ордер на покупку
	order1 = SmartOrder{
        account = ACC,
        client = CLI,
        market = FUT_CLASS,
        ticker = FUT_TICKER,
    }
	
	-- ордер на продажу
	order2 = SmartOrder{
        account = ACC,
        client = CLI,
        market = FUT_CLASS,
        ticker = FUT_TICKER,
    }
	
	local bid
	local offer
	local price1			-- цена ордера на покупку
	local price2			-- цена ордера на продажу
	
	local is_trading_time = isTradingTime()
	
	local function isReady()
		if isConnected() ~= 1 then
			log:trace("not connected, waiting for connection")
			sleep(15000)
			return false
		end
		
		if is_trading_time and tonumber(getParamEx(FUT_CLASS, FUT_TICKER, "TRADINGSTATUS").param_value) ~= 1 then
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

	log:trace(string.format("order1 max: %s by %s; order2 max: %s by %s", ORDER1_MAX, ORDER1_PART, ORDER2_MAX, ORDER1_PART))

    while true do
		
		if isReady() then

			-- если суммарно размер лонга не больше ORDER1_MAX
			if order1.position + order2.position < ORDER1_MAX then
				
				price1 = 0
				if feed.bids[2] ~= nil then
					-- если 2 бид является нашим ордером (совпадает цена и размер), то ищем следующий, 3-й бид
					if order1.order ~= nil and feed.bids[2].price == tonumber(order1.price) and feed.bids[2].quantity == order1.planned - order1.position then
						if feed.bids[3] ~= nil then
							-- присоедияемся к 3 биду, который станет 2-м после переноса нашего ордера
							price1 = formatPrice(feed.bids[3].price)
						end
					-- иначе, второй бид является чужим ордером, значит присоединяемся к нему	
					else
						price1 = formatPrice(feed.bids[3].price)
					end
				end
				
				if price1 ~= 0 then
					order1:update(price1, order1.position + ORDER1_PART)
					log:trace(string.format("order1 pos: %s; planned: %s; price: %s;", order1.position, order1.planned, price1))
				else
					-- недостаточно ликвидности, отменяем ордер
					order1:update(nil, order1.position)
					log:trace("no bids")
				end 
				
			else
				log:trace(string.format("order1 max pos %s reached: %s ; %s", ORDER1_MAX, order1.position, order2.position))
			end
			
			-- если суммарно размер шорта не больше ORDER2_MAX
			if order1.position + order2.position > ORDER2_MAX then
				
				price2 = 0
				if feed.offers[1] ~= nil then
					-- если первый оффер является нашим ордером (совпадает цена и размер), то ищем следующий, 2-й оффер
					if order2.order ~= nil and feed.offers[1].price == tonumber(order2.price) and feed.offers[1].quantity == order2.position - order2.planned then
						-- присоединяемся ко 2 офферу, который станет 1-м после переноса нашего ордера
						if feed.offers[2] ~= nil then
							price2 = formatPrice(feed.offers[2].price)
						end
					-- иначе, первый оффер является чужим ордером, присоединяемся к нему
					else
						price2 = formatPrice(feed.offers[1].price)
					end
				end

				if price2 ~= 0 then
					order2:update(price2, order2.position + ORDER2_PART)
					log:trace(string.format("order2 pos: %s; planned: %s; price: %s;", order2.position, order2.planned, price2))
				else
					-- недостаточно ликвидности, отменяем ордер
					order1:update(nil, order2.position)
					log:trace("no offers")
				end
				
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

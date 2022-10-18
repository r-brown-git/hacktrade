dofile("../hacktrade-ffeast.lua")

require("utils2")		 -- вспомогательные функции

function Robot()

	while true do
	
		while isConnected() ~= 1 or not isTradingTime() do 
			message("sleep")
			sleep(5000) 
		end
		
		message(formatPrice("33.00"))
		
		sleep(1000)
	end
  
end

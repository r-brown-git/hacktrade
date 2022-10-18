function formatPrice(price)
    price = tostring(price)

    if string.match(price, "%.(0+)") then
        price = string.format("%.0f", price)
    end

    return price
end

-- seclist_csv.lua, © smart-lab.ru/profile/XXM/
function string.split(str, sep)
	local fields = {}
	str:gsub(string.format("([^%s]+)", sep), function(f_c) fields[#fields + 1] = f_c end)
	return fields
end

function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

-- Возвращает истину, если буква месяца опциона до 'L' включительно
-- коды месяца колл: 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L' (ascii byte <= 76)
-- коды месяца пут: 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X' (ascii byte > 77)
-- string M - буква месяца
function isOptionCall(M)
	local byteCode = M:byte(1)
	return byteCode <= 76
end

function isTradingTime()
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
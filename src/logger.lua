local logger = {}

local PREFIX = '[QuickHand] '

-- Steamodded's loggers when it is installed, plain print otherwise. Resolved per call
-- because these globals do not exist yet while this module is being loaded.
local function send(sender, message)
	if sender then
		sender(PREFIX .. tostring(message), 'QuickHand')
	else
		print(PREFIX .. tostring(message))
	end
end


function logger.log_error(message)
	send(sendErrorMessage, message)
end

return logger

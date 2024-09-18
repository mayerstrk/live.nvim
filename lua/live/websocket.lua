---@class LiveWebSocket
local websocket = {}

---@type LiveLogger
local logger = require("live.logger")

---@param url string
---@return LiveWebSocket
function websocket.new(url)
	local self = setmetatable({}, { __index = websocket })
	self.url = url
	self.client = nil
	return self
end

---@return boolean success
---@return string? error
function websocket:connect()
	local success, curl = pcall(require, "plenary.curl")
	if not success then
		return false, "Failed to load plenary.curl: " .. tostring(curl)
	end

	local connect_success, result = pcall(function()
		self.client = curl.post(self.url, {
			stream = true,
			body = "",
			headers = {
				["Connection"] = "Upgrade",
				["Upgrade"] = "websocket",
				["Sec-WebSocket-Key"] = "dGhlIHNhbXBsZSBub25jZQ==",
			},
			on_body = function(body, _)
				logger.log("Received: " .. body, "INFO")
			end,
		})
	end)

	if connect_success then
		logger.log("WebSocket connected to " .. self.url, "INFO")
		return true
	else
		return false, "Failed to connect WebSocket: " .. tostring(result)
	end
end

---@param message string
---@return boolean success
---@return string? error
function websocket:send(message)
	if not self.client then
		return false, "WebSocket not connected"
	end

	local success, result = pcall(function()
		self.client.stream(message)
	end)

	if success then
		logger.log("Sent message over WebSocket", "INFO")
		return true
	else
		return false, "Failed to send message over WebSocket: " .. tostring(result)
	end
end

---@return boolean success
---@return string? error
function websocket:close()
	if self.client then
		local success, result = pcall(function()
			self.client.shutdown()
		end)

		if success then
			logger.log("WebSocket connection closed", "INFO")
			self.client = nil
			return true
		else
			return false, "Failed to close WebSocket connection: " .. tostring(result)
		end
	end
	return true -- Already closed
end

return websocket

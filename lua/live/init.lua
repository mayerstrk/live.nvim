---@class LiveOptions
---@field log_level? 'INFO'|'WARN'|'ERROR'

---@class Live
local M = {}

---@type LiveCore
local core = require("live.core")
---@type LiveLogger
local logger = require("live.logger")

---@param opts LiveOptions
---@return boolean success
---@return string? error
function M.setup(opts)
	opts = opts or {}
	local setup_success, setup_error = pcall(function()
		logger.setup(opts.log_level or "INFO")
		core.setup(opts)
	end)
	if setup_success then
		logger.log("live.nvim setup completed successfully", "INFO")
		return true
	else
		logger.log("Error during live.nvim setup: " .. tostring(setup_error), "ERROR")
		return false, setup_error
	end
end

---@param ws_url string
---@return boolean success
---@return string? error
function M.start(ws_url)
	if type(ws_url) ~= "string" or ws_url == "" then
		logger.log("Invalid WebSocket URL provided", "ERROR")
		return false, "Invalid WebSocket URL"
	end

	local start_success, start_error = pcall(core.start_live_updates, ws_url)
	if start_success then
		return true
	else
		logger.log("Error starting live updates: " .. tostring(start_error), "ERROR")
		return false, start_error
	end
end

---@return boolean success
---@return string? error
function M.stop()
	local stop_success, stop_error = pcall(core.stop_live_updates)
	if stop_success then
		return true
	else
		logger.log("Error stopping live updates: " .. tostring(stop_error), "ERROR")
		return false, stop_error
	end
end

return M

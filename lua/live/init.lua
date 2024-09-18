---@class LiveOptions
---@field log_level? 'INFO'|'WARN'|'ERROR'

---@class Live
local M = {}

---@type LiveCore
local core = require("live.core")
---@type LiveLogger
local logger = require("live.logger")
---@type LiveUtil
local util = require("live.util")

---@param opts LiveOptions
---@return boolean success
---@return string? error
function M.setup(opts)
	if not util.is_linux() then
		return false, "This plugin currently supports only Linux systems"
	end

	if not util.has_websocat() then
		return false, "websocat is not installed or not in PATH"
	end

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

	return core.start_live_updates(ws_url)
end

---@return boolean success
---@return string? error
function M.stop()
	return core.stop_live_updates()
end

return M

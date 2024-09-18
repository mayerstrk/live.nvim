---@class LiveLogger
local M = {}

---@type table<string, number>
local log_levels = { INFO = 0, WARN = 1, ERROR = 2 }
---@type 'INFO'|'WARN'|'ERROR'
local current_log_level = "INFO"

---@param log_level 'INFO'|'WARN'|'ERROR'
---@return boolean success
---@return string? error
function M.setup(log_level)
	if log_levels[log_level] then
		current_log_level = log_level
		return true
	else
		return false, "Invalid log level: " .. tostring(log_level) .. ". Using default: INFO"
	end
end

---@param message string
---@param level 'INFO'|'WARN'|'ERROR'
---@return boolean success
---@return string? error
function M.log(message, level)
	if type(message) ~= "string" then
		return false, "Invalid message type. Expected string, got " .. type(message)
	end

	if not log_levels[level] then
		return false, "Invalid log level: " .. tostring(level)
	end

	if log_levels[level] >= log_levels[current_log_level] then
		local success, result = pcall(vim.api.nvim_echo, { { "live.nvim: " .. message, level } }, true, {})
		if not success then
			return false, "Logging error: " .. tostring(result)
		end
	end
	return true
end

return M

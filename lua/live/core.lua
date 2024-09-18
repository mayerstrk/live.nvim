---@class LiveCore
local M = {}

---@type LiveLogger
local logger = require("live.logger")
---@type LiveWebSocket
local websocket = require("live.websocket")

---@type LiveWebSocket|nil
local ws_client = nil
---@type string|nil
local last_content = nil

---@param opts LiveOptions
function M.setup(opts)
	-- Any core setup logic can go here
end

---@param current_content string
---@return string|nil diff
---@return string|nil error
local function create_diff_update(current_content)
	if last_content == nil then
		last_content = current_content
		return current_content -- First update, send full content
	end

	local success, result = pcall(vim.diff, last_content, current_content, {
		result_type = "unified",
		algorithm = "myers",
		ctxlen = 3,
	})

	if success then
		last_content = current_content
		return result
	else
		return nil, "Failed to create diff: " .. tostring(result)
	end
end

---@return boolean success
---@return string? error
local function send_diff_update()
	if not ws_client then
		return false, "WebSocket client not initialized"
	end

	local success, result = pcall(function()
		local bufnr = vim.api.nvim_get_current_buf()
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		local content = table.concat(lines, "\n")

		local diff, diff_error = create_diff_update(content)
		if diff_error then
			error(diff_error)
		elseif diff then
			local send_success, send_error = ws_client:send(diff)
			if not send_success then
				error(send_error)
			end
		end
	end)

	if success then
		logger.log("Diff update sent successfully", "INFO")
		return true
	else
		return false, "Failed to send diff update: " .. tostring(result)
	end
end

---@param ws_url string
---@return boolean success
---@return string? error
function M.start_live_updates(ws_url)
	if ws_client then
		return false, "Live updates already running. Stop first before starting a new session."
	end

	local connect_success, connect_error = pcall(function()
		ws_client = websocket.new(ws_url)
		local success, error = ws_client:connect()
		if not success then
			error(error)
		end
	end)

	if not connect_success then
		return false, "Failed to establish WebSocket connection: " .. tostring(connect_error)
	end

	local augroup_success, augroup_error = pcall(vim.api.nvim_create_augroup, "LiveUpdates", { clear = true })
	if not augroup_success then
		return false, "Failed to create augroup: " .. tostring(augroup_error)
	end

	local autocmd_success, autocmd_error = pcall(vim.api.nvim_create_autocmd, { "TextChanged", "TextChangedI" }, {
		group = "LiveUpdates",
		buffer = vim.api.nvim_get_current_buf(),
		callback = send_diff_update,
	})
	if not autocmd_success then
		return false, "Failed to create TextChanged autocmd: " .. tostring(autocmd_error)
	end

	local bufunload_success, bufunload_error = pcall(vim.api.nvim_create_autocmd, "BufUnload", {
		group = "LiveUpdates",
		buffer = vim.api.nvim_get_current_buf(),
		callback = M.stop_live_updates,
	})
	if not bufunload_success then
		return false, "Failed to create BufUnload autocmd: " .. tostring(bufunload_error)
	end

	logger.log("Live updates started successfully", "INFO")
	return true
end

---@return boolean success
---@return string? error
function M.stop_live_updates()
	local all_operations_successful = true
	local error_messages = {}

	if ws_client then
		local close_success, close_error = ws_client:close()
		if not close_success then
			all_operations_successful = false
			table.insert(error_messages, "Failed to close WebSocket connection: " .. tostring(close_error))
		end
		ws_client = nil
	end

	local clear_success, clear_error = pcall(vim.api.nvim_clear_autocmds, { group = "LiveUpdates" })
	if not clear_success then
		all_operations_successful = false
		table.insert(error_messages, "Failed to clear autocmds: " .. tostring(clear_error))
	end

	last_content = nil

	if all_operations_successful then
		logger.log("Live updates stopped successfully", "INFO")
		return true
	else
		local error_message = table.concat(error_messages, "; ")
		logger.log("Live updates stopped with errors: " .. error_message, "ERROR")
		return false, error_message
	end
end

return M

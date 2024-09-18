local M = {}

local logger = require("live.logger")
local websocket = require("live.websocket")

local ws_client = nil
local last_content = nil

function M.setup(opts)
	-- Any core setup logic can go here
end

---@param current_content string
---@return string|nil
local function create_diff_update(current_content)
	if last_content == nil then
		last_content = current_content
		return current_content -- First update, send full content
	end

	local success, diff = pcall(vim.diff, last_content, current_content, {
		result_type = "unified",
		algorithm = "myers",
		ctxlen = 3,
	})

	if success then
		last_content = current_content
		return diff
	else
		logger.log("Failed to create diff: " .. tostring(diff), "ERROR")
		return nil
	end
end

local function send_diff_update()
	local bufnr = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")

	local diff = create_diff_update(content)
	if diff and ws_client then
		ws_client:send(diff)
		logger.log("Diff update sent", "INFO")
	end
end

function M.start_live_updates(ws_url)
	if ws_client then
		logger.log("Live updates already running. Stop first before starting a new session.", "WARN")
		return
	end

	ws_client = websocket.new(ws_url)
	ws_client:connect()

	local augroup = vim.api.nvim_create_augroup("LiveUpdates", { clear = true })

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = augroup,
		buffer = vim.api.nvim_get_current_buf(),
		callback = send_diff_update,
	})

	vim.api.nvim_create_autocmd("BufUnload", {
		group = augroup,
		buffer = vim.api.nvim_get_current_buf(),
		callback = M.stop_live_updates,
	})

	logger.log("Live updates started", "INFO")
end

function M.stop_live_updates()
	if ws_client then
		ws_client:close()
		ws_client = nil
	end

	vim.api.nvim_clear_autocmds({ group = "LiveUpdates" })
	last_content = nil

	logger.log("Live updates stopped", "INFO")
end

return M

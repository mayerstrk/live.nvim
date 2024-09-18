---@class LiveCore
local M = {}

---@type LiveLogger
local logger = require("live.logger")
---@type LiveUtil
local util = require("live.util")

---@type string|nil
local last_content = nil
---@type integer|nil
local active_buffer = nil
---@type number|nil
local websocat_job_id = nil
---@type number|nil
local debounce_timer = nil

---@param opts LiveOptions
function M.setup(opts)
	-- Any core setup logic can go here
end

---@return boolean success
---@return string? error
local function send_current_buffer()
	if not active_buffer or not websocat_job_id then
		return false, "Buffer not active or websocat not running"
	end

	local success, lines = pcall(vim.api.nvim_buf_get_lines, active_buffer, 0, -1, false)
	if not success then
		return false, "Failed to get buffer lines: " .. tostring(lines)
	end

	local content = table.concat(lines, "\n")

	local json_success, json_content = pcall(vim.fn.json_encode, {
		type = "full_content",
		content = content,
	})
	if not json_success then
		return false, "Failed to encode JSON: " .. tostring(json_content)
	end

	local send_success, send_error = pcall(vim.fn.chansend, websocat_job_id, json_content .. "\n")
	if not send_success then
		return false, "Failed to send buffer content: " .. tostring(send_error)
	end

	last_content = content
	return true
end

---@param current_content string
---@return table|nil diff
---@return string? error
local function create_diff_update(current_content)
	if last_content == nil then
		last_content = current_content
		return {
			type = "full_content",
			content = current_content,
		}
	end

	local diff_success, result = pcall(vim.diff, last_content, current_content, {
		result_type = "indices",
		algorithm = "myers",
		ctxlen = 3,
	})

	if not diff_success then
		return nil, "Failed to create diff: " .. tostring(result)
	end

	local diff_updates = {}
	for _, hunk in ipairs(result) do
		local split_success, lines = pcall(vim.split, current_content, "\n", { plain = true })
		if not split_success then
			return nil, "Failed to split content: " .. tostring(lines)
		end

		local slice_success, sliced_lines = pcall(function()
			return { unpack(lines, hunk[3], hunk[3] + hunk[4] - 1) }
		end)
		if not slice_success then
			return nil, "Failed to slice lines: " .. tostring(sliced_lines)
		end

		table.insert(diff_updates, {
			start_a = hunk[1],
			count_a = hunk[2],
			start_b = hunk[3],
			count_b = hunk[4],
			lines = sliced_lines,
		})
	end

	last_content = current_content
	return {
		type = "diff_update",
		diffs = diff_updates,
	}
end

---@return boolean success
---@return string? error
local function send_diff_update()
	if not active_buffer or not websocat_job_id then
		return false, "Buffer not active or websocat not running"
	end

	local get_lines_success, lines = pcall(vim.api.nvim_buf_get_lines, active_buffer, 0, -1, false)
	if not get_lines_success then
		return false, "Failed to get buffer lines: " .. tostring(lines)
	end

	local content = table.concat(lines, "\n")

	local diff_success, diff = pcall(create_diff_update, content)
	if not diff_success then
		return false, "Failed to create diff update: " .. tostring(diff)
	end

	if diff then
		local json_success, json_diff = pcall(vim.fn.json_encode, diff)
		if not json_success then
			return false, "Failed to encode JSON: " .. tostring(json_diff)
		end

		local send_success, send_error = pcall(vim.fn.chansend, websocat_job_id, json_diff .. "\n")
		if not send_success then
			return false, "Failed to send update: " .. tostring(send_error)
		end
	end

	return true
end

---@return boolean success
---@return string? error
local function debounced_send_diff_update()
	if debounce_timer then
		local stop_success, stop_error = pcall(vim.fn.timer_stop, debounce_timer)
		if not stop_success then
			logger.log("Failed to stop debounce timer: " .. tostring(stop_error), "ERROR")
		end
	end

	local timer_success, timer_error = pcall(vim.fn.timer_start, 2000, function()
		local success, error = send_diff_update()
		if not success then
			logger.log("Failed to send diff update: " .. error, "ERROR")
		end
		debounce_timer = nil
	end)

	if not timer_success then
		return false, "Failed to start debounce timer: " .. tostring(timer_error)
	end

	debounce_timer = timer_error -- In success case, timer_error is actually the timer id
	return true
end

---@param ws_url string
---@return boolean success
---@return string? error
local function start_websocat(ws_url)
	local job_start_success, job_id = pcall(vim.fn.jobstart, { "websocat", ws_url }, {
		on_stderr = function(_, data)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						logger.log("websocat error: " .. line, "ERROR")
					end
				end
			end
		end,
		on_exit = function(_, exit_code)
			logger.log("websocat exited with code: " .. exit_code, "INFO")
			M.stop_live_updates()
		end,
	})

	if not job_start_success then
		return false, "Failed to start websocat: " .. tostring(job_id)
	end

	if job_id <= 0 then
		return false, "Failed to start websocat: Invalid job ID"
	end

	websocat_job_id = job_id
	return true
end

---@return boolean success
---@return string? error
local function setup_autocmds()
	local augroup_success, augroup_error = util.create_augroup("LiveUpdates")
	if not augroup_success then
		return false, augroup_error
	end

	local text_changed_success, text_changed_error = util.create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = "LiveUpdates",
		buffer = active_buffer,
		callback = debounced_send_diff_update,
	})
	if not text_changed_success then
		return false, text_changed_error
	end

	local bufunload_success, bufunload_error = util.create_autocmd("BufUnload", {
		group = "LiveUpdates",
		buffer = active_buffer,
		callback = function()
			M.stop_live_updates()
		end,
	})
	if not bufunload_success then
		return false, bufunload_error
	end

	return true
end

---@param ws_url string
---@return boolean success
---@return string? error
function M.start_live_updates(ws_url)
	if not util.is_linux() then
		return false, "This plugin currently supports only Linux systems"
	end

	if not util.has_websocat() then
		return false, "websocat is not installed or not in PATH"
	end

	if websocat_job_id then
		return false, "Live updates already running. Stop first before starting a new session."
	end

	local websocat_success, websocat_error = start_websocat(ws_url)
	if not websocat_success then
		return false, websocat_error
	end

	local buffer_success, buffer_error = pcall(function()
		active_buffer = vim.api.nvim_get_current_buf()
	end)
	if not buffer_success then
		M.stop_live_updates()
		return false, "Failed to get current buffer: " .. tostring(buffer_error)
	end

	local send_buffer_success, send_buffer_error = send_current_buffer()
	if not send_buffer_success then
		M.stop_live_updates()
		return false, "Failed to send initial buffer content: " .. send_buffer_error
	end

	local autocmd_success, autocmd_error = setup_autocmds()
	if not autocmd_success then
		M.stop_live_updates()
		return false, autocmd_error
	end

	logger.log("Live updates started successfully", "INFO")
	return true
end

---@return boolean success
---@return string? error
function M.stop_live_updates()
	local all_operations_successful = true
	local error_messages = {}

	if websocat_job_id then
		local stop_success, stop_error = util.stop_job(websocat_job_id)
		if not stop_success then
			all_operations_successful = false
			table.insert(error_messages, stop_error)
		end
		websocat_job_id = nil
	end

	if debounce_timer then
		local timer_stop_success, timer_stop_error = pcall(vim.fn.timer_stop, debounce_timer)
		if not timer_stop_success then
			all_operations_successful = false
			table.insert(error_messages, "Failed to stop debounce timer: " .. tostring(timer_stop_error))
		end
		debounce_timer = nil
	end

	local clear_success, clear_error = util.clear_autocmds("LiveUpdates")
	if not clear_success then
		all_operations_successful = false
		table.insert(error_messages, clear_error)
	end

	last_content = nil
	active_buffer = nil

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

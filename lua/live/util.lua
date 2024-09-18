---@class LiveUtil
local M = {}

---@return boolean
function M.is_linux()
	return vim.fn.has("unix") == 1 and vim.fn.has("mac") == 0
end

---@return boolean
function M.has_websocat()
	return vim.fn.executable("websocat") == 1
end

---@param group_name string
---@return boolean success
---@return string? error
function M.create_augroup(group_name)
	local success, result = pcall(vim.api.nvim_create_augroup, group_name, { clear = true })
	if not success then
		return false, "Failed to create augroup: " .. tostring(result)
	end
	return true
end

---@param events string[]
---@param opts table
---@return boolean success
---@return string? error
function M.create_autocmd(events, opts)
	local success, result = pcall(vim.api.nvim_create_autocmd, events, opts)
	if not success then
		return false, "Failed to create autocmd: " .. tostring(result)
	end
	return true
end

---@param group string
---@return boolean success
---@return string? error
function M.clear_autocmds(group)
	local success, result = pcall(vim.api.nvim_clear_autocmds, { group = group })
	if not success then
		return false, "Failed to clear autocmds: " .. tostring(result)
	end
	return true
end

---@param job_id number
---@return boolean success
---@return string? error
function M.stop_job(job_id)
	local success, result = pcall(vim.fn.jobstop, job_id)
	if not success or result == 0 then
		return false, "Failed to stop job: " .. tostring(result)
	end
	return true
end

return M

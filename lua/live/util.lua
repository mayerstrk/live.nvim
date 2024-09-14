---@class LiveUtil
local M = {}

-- Constants
---@type number
M.DEBOUNCE_MS = 100
---@type string
M.LOCALHOST = "127.0.0.1"

---Determines if the current buffer is a Markdown file
---@return boolean
function M.is_markdown()
	return vim.bo.filetype == "markdown"
end

---Gets the appropriate WebSocket endpoint based on file type
---@return string
function M.get_endpoint()
	return M.is_markdown() and "/markdown" or "/code"
end

---Gets the current buffer content as a string
---@return string
function M.get_buffer_content()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	return table.concat(lines, "\n")
end

---Creates a diff between two content strings
---@param old_content string
---@param new_content string
---@return string|nil
function M.create_diff(old_content, new_content)
	if old_content ~= new_content then
		local ok, diff = pcall(vim.diff, old_content, new_content, {
			algorithm = "myers",
		})
		if ok then
			return diff
		else
			vim.schedule(function()
				vim.api.nvim_err_writeln("Failed to create diff: " .. tostring(diff))
			end)
			return nil
		end
	end
	return nil
end

return M

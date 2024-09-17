-- lua/live/util.lua
local M = {}
local uv = vim.loop

-- Operation: Logging
function M.log_info(msg)
	vim.notify("[Live.nvim] " .. msg, vim.log.levels.INFO)
end

function M.log_error(msg)
	vim.notify("[Live.nvim] " .. msg, vim.log.levels.ERROR)
end
-- End of operation: Logging

-- Operation: Get Available Port
function M.get_available_port()
	local server = uv.new_tcp()
	local ok, err = pcall(function()
		server:bind("127.0.0.1", 0)
	end)
	if not ok then
		M.log_error("Failed to bind TCP server: " .. err)
		return nil
	end

	local address = server:getsockname()
	server:close()
	if not address or not address.port then
		M.log_error("Failed to get socket name.")
		return nil
	end
	return address.port
end
-- End of operation: Get Available Port

-- Operation: Debounce
function M.debounce(func, timeout)
	local timer_id
	return function(...)
		local args = { ... }
		if timer_id then
			uv.timer_stop(timer_id)
		else
			timer_id = uv.new_timer()
		end
		uv.timer_start(timer_id, timeout, 0, function()
			uv.timer_stop(timer_id)
			uv.close(timer_id)
			timer_id = nil
			func(unpack(args))
		end)
	end
end
-- End of operation: Debounce

-- Operation: Compute Diff
function M.compute_diff(old_content, new_content)
	-- Implement the Myers diff algorithm or use an existing library
	-- For brevity, we'll just return the new content in this example
	return new_content
end
-- End of operation: Compute Diff

return M

local uv = vim.loop
local api = vim.api

local M = {}

function M.find_free_port()
	-- _______
	-- operation: Find free port
	-- _______

	local port
	local ok, err = pcall(function()
		local server = uv.new_tcp()
		local res, bind_err = server:bind("127.0.0.1", 0)
		if not res then
			error("Failed to bind TCP socket: " .. (bind_err or "unknown error"))
		end

		local name = server:getsockname()
		server:close()

		if name and name.port then
			port = name.port
		else
			error("Failed to get socket name.")
		end
	end)

	if not ok then
		M.notify_error("Error finding free port: " .. err)
		return nil
	end

	-- end of operation: Find free port
	-- _______

	return port
end

function M.get_server_script_path()
	-- _______
	-- operation: Get server script path
	-- _______

	local ok, script_path = pcall(function()
		local source = debug.getinfo(1, "S").source:sub(2)
		return vim.fn.fnamemodify(source, ":p:h:h") .. "/server/server.go"
	end)

	if not ok or not script_path then
		M.notify_error("Failed to get server script path.")
		return nil
	end

	-- end of operation: Get server script path
	-- _______

	return script_path
end

function M.notify_error(msg)
	-- _______
	-- operation: Notify error
	-- _______

	api.nvim_err_writeln("[live.nvim] ERROR: " .. msg)
	M.log("ERROR", msg)

	-- end of operation: Notify error
	-- _______
end

function M.notify_info(msg)
	-- _______
	-- operation: Notify info
	-- _______

	api.nvim_out_write("[live.nvim] INFO: " .. msg .. "\n")
	M.log("INFO", msg)

	-- end of operation: Notify info
	-- _______
end

function M.log(level, msg)
	-- _______
	-- operation: Log message
	-- _______

	local log_file = M.get_log_file()
	local ok, err = pcall(function()
		local f = io.open(log_file, "a")
		if f then
			f:write(string.format("[%s] %s - %s\n", level, os.date("%Y-%m-%d %H:%M:%S"), msg))
			f:close()
		else
			error("Failed to open log file: " .. log_file)
		end
	end)

	if not ok then
		api.nvim_err_writeln("[live.nvim] Logging error: " .. err)
	end

	-- end of operation: Log message
	-- _______
end

function M.get_log_file()
	-- _______
	-- operation: Get log file path
	-- _______

	local ok, log_file = pcall(function()
		return vim.fn.stdpath("cache") .. "/live.nvim.log"
	end)

	if not ok or not log_file then
		api.nvim_err_writeln("[live.nvim] ERROR: Failed to get log file path.")
		return "/tmp/live.nvim.log" -- Fallback to tmp
	end

	-- end of operation: Get log file path
	-- _______

	return log_file
end

return M

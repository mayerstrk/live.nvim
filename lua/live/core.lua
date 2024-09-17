local uv = vim.loop
local api = vim.api
local util = require("live.util")

local M = {}

M.server_process = nil
M.ws_process = nil
M.debounce_timer = nil
M.server_address = nil
M.endpoint = nil

function M.setup(opts)
	-- No setup necessary for now, placeholder for future updates
end

function M.start(args)
	-- _______
	-- operation: Start live synchronization
	-- _______

	local ok, err = pcall(function()
		local server_address, endpoint = M.parse_args(args)
		M.detect_filetype()

		if not server_address then
			server_address = M.start_server()
			if not server_address then
				error("Failed to start the Go server.")
			end
		end

		M.server_address = server_address
		M.endpoint = endpoint or M.endpoint

		M.sync_buffer()

		M.set_autocommands()

		util.notify_info("Live synchronization started.")
	end)

	if not ok then
		util.notify_error("Error starting live.nvim: " .. err)
	end

	-- end of operation: Start live synchronization
	-- _______
end

function M.stop()
	-- _______
	-- operation: Stop live synchronization
	-- _______

	local ok, err = pcall(function()
		M.stop_sync()
		M.stop_server()
		M.remove_autocommands()
		util.notify_info("Live synchronization stopped.")
	end)

	if not ok then
		util.notify_error("Error stopping live.nvim: " .. err)
	end

	-- end of operation: Stop live synchronization
	-- _______
end

function M.parse_args(args)
	-- _______
	-- operation: Parse command arguments
	-- _______

	if not args or args == "" then
		return nil, nil
	end
	local arg_list = vim.split(args, "%s+")
	return arg_list[1], arg_list[2]

	-- end of operation: Parse command arguments
	-- _______
end

function M.detect_filetype()
	-- _______
	-- operation: Detect filetype to set endpoint
	-- _______

	local ok, ft = pcall(function()
		return vim.bo.filetype
	end)

	if not ok then
		util.notify_error("Failed to detect filetype.")
		ft = "plain"
	end

	if ft == "markdown" then
		M.endpoint = "/markdown"
	else
		M.endpoint = "/code"
	end

	-- end of operation: Detect filetype to set endpoint
	-- _______
end

function M.start_server()
	-- _______
	-- operation: Start Go server
	-- _______

	local port = util.find_free_port()
	if not port then
		util.notify_error("No available ports found.")
		return nil
	end

	local server_script = util.get_server_script_path()
	if not server_script then
		util.notify_error("Server script path not found.")
		return nil
	end

	local cmd = { "go", "run", server_script, "--port", tostring(port) }

	local handle
	local ok, err = pcall(function()
		handle = uv.spawn(cmd[1], { args = { unpack(cmd, 2) } }, function(code, signal)
			if code ~= 0 then
				util.notify_error(string.format("Go server exited with code %d, signal %d", code, signal))
			end
		end)
	end)

	if not ok or not handle then
		util.notify_error("Failed to start Go server process: " .. (err or "unknown error"))
		return nil
	end

	M.server_process = handle
	util.notify_info("Go server started on port " .. port)

	-- end of operation: Start Go server
	-- _______

	return "127.0.0.1:" .. port
end

function M.stop_server()
	-- _______
	-- operation: Stop Go server
	-- _______

	if M.server_process then
		M.server_process:kill()
		M.server_process:close()
		M.server_process = nil
		util.notify_info("Go server stopped.")
	end

	-- end of operation: Stop Go server
	-- _______
end

function M.sync_buffer()
	-- _______
	-- operation: Sync buffer content
	-- _______

	local ok, err = pcall(function()
		local content = M.get_buffer_content()
		M.send_content(content)
	end)

	if not ok then
		util.notify_error("Failed to sync buffer: " .. err)
	end

	-- end of operation: Sync buffer content
	-- _______
end

function M.get_buffer_content()
	-- _______
	-- operation: Get buffer content
	-- _______

	local lines = api.nvim_buf_get_lines(0, 0, -1, false)
	return table.concat(lines, "\n")

	-- end of operation: Get buffer content
	-- _______
end

function M.on_text_change()
	-- _______
	-- operation: Handle text change event
	-- _______

	local ok, err = pcall(function()
		M.debounce_sync()
	end)

	if not ok then
		util.notify_error("Error in on_text_change: " .. err)
	end

	-- end of operation: Handle text change event
	-- _______
end

function M.debounce_sync()
	-- _______
	-- operation: Debounce buffer synchronization
	-- _______

	if M.debounce_timer then
		M.debounce_timer:stop()
		M.debounce_timer:close()
	end

	M.debounce_timer = uv.new_timer()
	M.debounce_timer:start(200, 0, function()
		vim.schedule(function()
			M.sync_buffer()
		end)
		M.debounce_timer:stop()
		M.debounce_timer:close()
		M.debounce_timer = nil
	end)

	-- end of operation: Debounce buffer synchronization
	-- _______
end

function M.send_content(content)
	-- _______
	-- operation: Send content via WebSocket
	-- _______

	if not M.server_address or not M.endpoint then
		util.notify_error("Server address or endpoint not set.")
		return
	end

	local cmd = {
		"websocat",
		"ws://" .. M.server_address .. M.endpoint,
	}

	local stdin = uv.new_pipe(false)
	local stdout = uv.new_pipe(false)
	local stderr = uv.new_pipe(false)

	local handle
	local ok, err = pcall(function()
		handle = uv.spawn(
			cmd[1],
			{ args = { unpack(cmd, 2) }, stdio = { stdin, stdout, stderr } },
			function(code, signal)
				if code ~= 0 then
					util.notify_error(string.format("WebSocket exited with code %d, signal %d", code, signal))
				end
				stdin:close()
				stdout:close()
				stderr:close()
				if M.ws_process then
					M.ws_process:close()
					M.ws_process = nil
				end
			end
		)
	end)

	if not ok or not handle then
		util.notify_error("Failed to start WebSocket process: " .. (err or "unknown error"))
		stdin:close()
		stdout:close()
		stderr:close()
		return
	end

	M.ws_process = handle

	stdin:write(content, function(err)
		if err then
			util.notify_error("Error writing to WebSocket stdin: " .. err)
		end
		stdin:shutdown(function(err)
			if err then
				util.notify_error("Error shutting down stdin: " .. err)
			end
			stdin:close()
		end)
	end)

	-- end of operation: Send content via WebSocket
	-- _______
end

function M.stop_sync()
	-- _______
	-- operation: Stop buffer synchronization
	-- _______

	if M.ws_process then
		M.ws_process:kill()
		M.ws_process:close()
		M.ws_process = nil
		util.notify_info("WebSocket process stopped.")
	end

	-- end of operation: Stop buffer synchronization
	-- _______
end

function M.set_autocommands()
	-- _______
	-- operation: Set autocommands
	-- _______

	api.nvim_exec(
		[[
    augroup LiveSync
      autocmd!
      autocmd TextChanged,TextChangedI <buffer> lua require'live.core'.on_text_change()
      autocmd BufUnload,BufWipeout <buffer> lua require'live.core'.stop()
    augroup END
  ]],
		false
	)

	-- end of operation: Set autocommands
	-- _______
end

function M.remove_autocommands()
	-- _______
	-- operation: Remove autocommands
	-- _______

	api.nvim_command("augroup LiveSync | autocmd! | augroup END")

	-- end of operation: Remove autocommands
	-- _______
end

return M

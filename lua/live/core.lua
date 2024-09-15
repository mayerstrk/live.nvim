---@class Live
local M = {}
local util = require("live.util")

-- State variables
---@type number|nil
local server_process = nil
---@type number|nil
local websocat_process = nil
---@type string
local last_content = ""
---@type number|nil
local update_timer = nil
---@type number|nil
local server_port = nil
---@type boolean
local is_running = false

---@param _ number
---@param exit_code number
local function on_server_exit(_, exit_code)
	vim.schedule(function()
		print("Server process exited with code: " .. exit_code)
		server_process = nil
		server_port = nil
	end)
end

---@param _ number
---@param data string[]
local function on_server_stdout(_, data)
	for _, line in ipairs(data) do
		local port = line:match("Server started on port (%d+)")
		if port then
			server_port = tonumber(port)
			if server_port then
				M.connect_to_server(util.LOCALHOST, server_port)
				M.open_browser(server_port)
				break
			else
				vim.schedule(function()
					vim.api.nvim_err_writeln("Failed to parse server port number")
				end)
			end
		end
	end
end

---Starts the built-in Go server
---@return nil
function M.start_builtin_server()
	if is_running then
		print("Server is already running")
		return
	end

	if server_process then
		vim.api.nvim_err_writeln("Server is already running")
		return
	end

	local plugin_root = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand("<sfile>:p")), ":h:h:h")
	local server_path = plugin_root .. "/server/cmd/live/main.go"

	server_process = vim.fn.jobstart({ "go", "run", server_path }, {
		on_exit = on_server_exit,
		on_stdout = on_server_stdout,
	})

	if server_process <= 0 then
		vim.api.nvim_err_writeln("Failed to start server process")
		return
	end

	is_running = true

	print("Started built-in server in whth pid: " .. server_process)
end

---Opens the default browser to view the synced content
---@param port number
---@return nil
function M.open_browser(port)
	local url = string.format("http://127.0.0.1:%d", port)
	local cmd

	if vim.fn.has("mac") == 1 then
		cmd = { "open", url }
	elseif vim.fn.has("unix") == 1 then
		cmd = { "xdg-open", url }
	elseif vim.fn.has("win32") == 1 then
		cmd = { "cmd", "/c", "start", url }
	else
		vim.api.nvim_err_writeln("Unsupported operating system")
		return
	end

	vim.fn.jobstart(cmd, {
		detach = true,
		on_exit = function(_, code)
			if code ~= 0 then
				vim.schedule(function()
					vim.api.nvim_err_writeln("Failed to open browser")
				end)
			end
		end,
	})
end

---@param _ number
local function on_websocket_exit(_)
	vim.schedule(function()
		print("WebSocket connection closed")
		websocat_process = nil
	end)
end

---Connects to a WebSocket server
---@param host string
---@param port number
---@return nil
function M.connect_to_server(host, port)
	if is_running then
		print("Already connected to a server")
		return
	end

	if websocat_process then
		vim.api.nvim_err_writeln("Already connected to a server")
		return
	end

	local endpoint = util.get_endpoint()
	local url = string.format("ws://%s:%d%s", host, port, endpoint)

	websocat_process = vim.fn.jobstart({ "websocat", url }, {
		on_exit = on_websocket_exit,
	})

	if websocat_process <= 0 then
		vim.api.nvim_err_writeln("Failed to establish WebSocket connection")
		return
	end

	last_content = util.get_buffer_content()
	is_running = true
	print("Connected to WebSocket server")
end

---Handles text change events
---@return nil
function M.on_text_change()
	if not is_running then
		print("on_text_change handler attempted to run when server is not running")
		return
	end
	if update_timer then
		vim.fn.timer_stop(update_timer)
	end
	update_timer = vim.fn.timer_start(util.DEBOUNCE_MS, function()
		local current_content = util.get_buffer_content()
		local diff = util.create_diff(last_content, current_content)

		if diff and websocat_process then
			local success, err = pcall(vim.api.nvim_chan_send, websocat_process, diff .. "\n")
			if not success then
				vim.schedule(function()
					vim.api.nvim_err_writeln("Failed to send update: " .. tostring(err))
				end)
			end
		end

		last_content = current_content
	end)
end

---Stops all processes and resets state
---@return nil
local function stop_all_processes()
	if update_timer then
		vim.fn.timer_stop(update_timer)
		update_timer = nil
	end
	print("Stopped debounce timer")

	if websocat_process then
		pcall(vim.fn.jobstop, websocat_process)
		websocat_process = nil
	end
	print("Stopped websocat process")

	if server_process then
		local server_stopped = pcall(vim.fn.jobstop, server_process)
		-- Ensure the Go server process is terminated
		vim.fn.system('pkill -f "go run .*live/main.go"')
		if server_stopped then
			print("Stopped server process with pid: " .. server_process)
			server_process = nil
			last_content = ""
			server_port = nil
		else
			print("Failed to stop server process with pid: " .. server_process)
		end
	end
end

---Handles buffer unload events
---@return nil
function M.on_buffer_unload()
	M.stop()
end

---Stops all processes (public API for LiveStop command)
---@return nil
function M.stop()
	if not is_running then
		print("Attempted to stop but no server is running")
		return
	end

	stop_all_processes()
end

---Function to be called when the plugin is disabled
---@return nil
function M.disable_plugin()
	stop_all_processes()
	print("Stopped live synchronization")
end

---Setup function to be called when the plugin is loaded
---@return nil
function M.setup() end

return M

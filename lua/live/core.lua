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

local function log(message)
	print("LiveNvim: " .. message)
end

local function error_log(message)
	vim.api.nvim_err_writeln("LiveNvim Error: " .. message)
end

---@param _ number
---@param exit_code number
local function on_server_exit(_, exit_code)
	vim.schedule(function()
		log("Server process exited with code: " .. exit_code)
		server_process = nil
		server_port = nil
		is_running = false
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
				log("Server started on port " .. server_port)
				local success, err = pcall(M.connect_to_server, util.LOCALHOST, server_port)
				if not success then
					error_log("Failed to connect to server: " .. tostring(err))
					return
				end
				success, err = pcall(M.open_browser, server_port)
				if not success then
					error_log("Failed to open browser: " .. tostring(err))
				end
				break
			else
				error_log("Failed to parse server port number")
			end
		end
	end
end

---Starts the built-in Go server
---@return nil
function M.start_builtin_server()
	if is_running then
		log("Server is already running")
		return
	end

	if server_process then
		error_log("Server process exists but is_running is false. This shouldn't happen.")
		return
	end

	local plugin_root = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand("<sfile>:p")), ":h:h:h")
	local server_dir = plugin_root .. "/server"
	local server_file = "cmd/live/main.go"

	if not vim.fn.isdirectory(server_dir) then
		error_log("Server directory not found at: " .. server_dir)
		return
	end

	log("Attempting to start server from directory: " .. server_dir)

	-- Change to the server directory
	local original_dir = vim.fn.getcwd()
	vim.fn.chdir(server_dir)

	-- Start the server process
	server_process = vim.fn.jobstart({ "go", "run", server_file }, {
		on_stdout = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					log("Server stdout: " .. line)
				end
			end
		end,
		on_stderr = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					error_log("Server stderr: " .. line)
				end
			end
		end,
		on_exit = function(_, exit_code)
			log("Server process exited with code: " .. exit_code)
			server_process = nil
			is_running = false
		end,
	})

	-- Change back to the original directory
	vim.fn.chdir(original_dir)

	if server_process <= 0 then
		error_log("Failed to start server process. Return code: " .. server_process)
		return
	end

	is_running = true
	log("Started built-in server with pid: " .. server_process)
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
		error_log("Unsupported operating system")
		return
	end

	local job_id = vim.fn.jobstart(cmd, {
		detach = true,
		on_exit = function(_, code)
			if code ~= 0 then
				error_log("Failed to open browser. Exit code: " .. code)
			end
		end,
	})

	if job_id <= 0 then
		error_log("Failed to start browser opening job")
	end
end

---@param _ number
local function on_websocket_exit(_)
	vim.schedule(function()
		log("WebSocket connection closed")
		websocat_process = nil
		is_running = false
	end)
end

---Connects to a WebSocket server
---@param host string
---@param port number
---@return nil
function M.connect_to_server(host, port)
	if is_running then
		log("Already connected to a server")
		return
	end

	if websocat_process then
		error_log("WebSocket process exists but is_running is false. This shouldn't happen.")
		return
	end

	local endpoint = util.get_endpoint()
	local url = string.format("ws://%s:%d%s", host, port, endpoint)

	websocat_process = vim.fn.jobstart({ "websocat", url }, {
		on_exit = on_websocket_exit,
	})

	if websocat_process <= 0 then
		error_log("Failed to establish WebSocket connection. Return code: " .. websocat_process)
		return
	end

	last_content = util.get_buffer_content()
	is_running = true
	log("Connected to WebSocket server")
end

---Handles text change events
---@return nil
function M.on_text_change()
	if not is_running then
		log("on_text_change handler attempted to run when server is not running")
		return
	end
	if update_timer then
		local stop_success, stop_err = pcall(vim.fn.timer_stop, update_timer)
		if not stop_success then
			error_log("Failed to stop existing update timer: " .. tostring(stop_err))
		end
	end
	update_timer = vim.fn.timer_start(util.DEBOUNCE_MS, function()
		local current_content = util.get_buffer_content()
		local diff = util.create_diff(last_content, current_content)

		if diff and websocat_process then
			local success, err = pcall(vim.api.nvim_chan_send, websocat_process, diff .. "\n")
			if not success then
				error_log("Failed to send update: " .. tostring(err))
			end
		elseif not websocat_process then
			error_log("WebSocket process not found when trying to send update")
		end

		last_content = current_content
	end)
	if not update_timer then
		error_log("Failed to start update timer")
	end
end

---Stops all processes and resets state
---@return nil
local function stop_all_processes()
	if update_timer then
		local stop_success, stop_err = pcall(vim.fn.timer_stop, update_timer)
		if stop_success then
			log("Stopped debounce timer")
		else
			error_log("Failed to stop debounce timer: " .. tostring(stop_err))
		end
		update_timer = nil
	end

	if websocat_process then
		local stop_success, stop_err = pcall(vim.fn.jobstop, websocat_process)
		if stop_success then
			log("Stopped websocat process")
		else
			error_log("Failed to stop websocat process: " .. tostring(stop_err))
		end
		websocat_process = nil
	end

	if server_process then
		local server_stopped, stop_err = pcall(vim.fn.jobstop, server_process)
		-- Ensure the Go server process is terminated
		local pkill_success, pkill_result = pcall(vim.fn.system, 'pkill -f "go run .*live/main.go"')
		if server_stopped then
			log("Stopped server process with pid: " .. server_process)
		else
			error_log("Failed to stop server process with pid: " .. server_process .. ". Error: " .. tostring(stop_err))
		end
		if pkill_success then
			log("Pkill result: " .. vim.trim(pkill_result))
		else
			error_log("Failed to run pkill command: " .. tostring(pkill_result))
		end
		server_process = nil
		last_content = ""
		server_port = nil
	end

	is_running = false
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
		log("Attempted to stop but no server is running")
		return
	end

	stop_all_processes()
	log("Stopped live synchronization")
end

---Function to be called when the plugin is disabled
---@return nil
function M.disable_plugin()
	stop_all_processes()
	log("Plugin disabled")
end

---Setup function to be called when the plugin is loaded
---@return nil
function M.setup()
	-- Any setup logic can be added here if needed in the future
end

return M

---@class Live
local M = {}
local util = require("live.util")

-- Assign vim.loop to a local variable
local uv = vim.loop

-- State variables
---@type userdata|nil
local server_handle = nil
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

local function check_server_running()
	local handle = io.popen("pgrep -f 'go run.*live/main.go'")
	if handle then
		local result = handle:read("*a")
		handle:close()

		local pids = {}
		for pid in result:gmatch("%d+") do
			table.insert(pids, tonumber(pid))
		end

		return pids
	end
	return {}
end

---Starts the built-in Go server
---@return nil
function M.start_builtin_server()
	local running_servers = check_server_running()
	if #running_servers > 0 then
		error_log("Server instances already running with PIDs: " .. table.concat(running_servers, ", "))
		error_log("Please stop these instances before starting a new one.")
		return
	end

	if is_running then
		log("Server is already running")
		return
	end

	if server_handle then
		error_log("Server handle exists but is_running is false. This shouldn't happen.")
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
	log("Current working directory before change: " .. vim.fn.getcwd())

	local original_dir = vim.fn.getcwd()
	vim.fn.chdir(server_dir)

	log("Current working directory after change: " .. vim.fn.getcwd())
	log("Running command: go run " .. server_file)

	---@type userdata
	local stdout = uv.new_pipe(false)
	---@type userdata
	local stderr = uv.new_pipe(false)

	---@type userdata|nil
	local handle = uv.spawn("go", {
		args = { "run", server_file },
		stdio = { nil, stdout, stderr },
		cwd = server_dir,
	}, function(code, signal)
		stdout:close()
		stderr:close()
		if handle then
			handle:close()
		end
		vim.schedule(function()
			log("Server process exited with code: " .. tostring(code) .. " and signal: " .. tostring(signal))
			server_handle = nil
			is_running = false
		end)
	end)

	if not handle then
		error_log("Failed to start server process")
		vim.fn.chdir(original_dir)
		return
	end

	server_handle = handle
	is_running = true

	local pid = handle:get_pid()
	log("Started built-in server with PID: " .. tostring(pid))

	uv.read_start(stdout, function(err, data)
		assert(not err, err)
		if data then
			vim.schedule(function()
				log("Server stdout: " .. data)
				local port = data:match("Server started on port (%d+)")
				if port then
					server_port = tonumber(port)
					if server_port then
						log("Server started on port " .. server_port)
						M.connect_to_server(util.LOCALHOST, server_port)
						M.open_browser(server_port)
					else
						error_log("Failed to parse server port number")
					end
				end
			end)
		end
	end)

	uv.read_start(stderr, function(err, data)
		assert(not err, err)
		if data then
			vim.schedule(function()
				error_log("Server stderr: " .. data)
			end)
		end
	end)

	vim.fn.chdir(original_dir)
	log("Current working directory after changing back: " .. vim.fn.getcwd())

	vim.defer_fn(function()
		if not is_running then
			error_log("Server stopped shortly after starting. Check server logs for errors.")
		end
	end, 1000)
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

	vim.fn.jobstart(cmd, {
		detach = true,
		on_exit = function(_, code)
			if code ~= 0 then
				vim.schedule(function()
					error_log("Failed to open browser")
				end)
			end
		end,
	})
end

---Connects to a WebSocket server
---@param host string
---@param port number
---@return nil
function M.connect_to_server(host, port)
	if websocat_process then
		error_log("Already connected to a server")
		return
	end

	local endpoint = util.get_endpoint()
	local url = string.format("ws://%s:%d%s", host, port, endpoint)

	websocat_process = vim.fn.jobstart({ "websocat", url }, {
		on_stdout = function(_, data)
			vim.schedule(function()
				for _, line in ipairs(data) do
					if line ~= "" then
						log("WebSocket received: " .. line)
					end
				end
			end)
		end,
		on_stderr = function(_, data)
			vim.schedule(function()
				for _, line in ipairs(data) do
					if line ~= "" then
						error_log("WebSocket error: " .. line)
					end
				end
			end)
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				log("WebSocket connection closed with code: " .. code)
				websocat_process = nil
			end)
		end,
	})

	if websocat_process <= 0 then
		error_log("Failed to establish WebSocket connection")
		return
	end

	last_content = util.get_buffer_content()
	log("Connected to WebSocket server")
end

---Handles text change events
---@return nil
function M.on_text_change()
	if not is_running then
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
				error_log("Failed to send update: " .. tostring(err))
			end
		end

		last_content = current_content
	end)
end

---Handles buffer unload events
---@return nil
function M.on_buffer_unload()
	M.stop()
end

---Stops all processes (public API for LiveStop command)
---@return nil
function M.stop()
	if server_handle then
		server_handle:kill("sigterm")
		log("Sent stop signal to server process")
	end

	if websocat_process then
		vim.fn.jobstop(websocat_process)
		log("Sent stop signal to WebSocket process")
	end

	if update_timer then
		vim.fn.timer_stop(update_timer)
		update_timer = nil
	end

	vim.defer_fn(function()
		local running_servers = check_server_running()
		if #running_servers > 0 then
			error_log("Some server instances are still running. Forcing shutdown...")
			for _, pid in ipairs(running_servers) do
				uv.kill(pid, "sigkill")
			end
		end
		is_running = false
		server_handle = nil
		websocat_process = nil
		log("Stopped live synchronization")
	end, 5000)
end

---Function to be called when the plugin is disabled
---@return nil
function M.disable_plugin()
	M.stop()
end

---Setup function to be called when the plugin is loaded
---@return nil
function M.setup()
	-- Any setup logic can be added here if needed in the future
end

---Checks for running server instances
---@return nil
function M.check_running_servers()
	local running_servers = check_server_running()
	if #running_servers > 0 then
		log("Server instances running with PIDs: " .. table.concat(running_servers, ", "))
	else
		log("No server instances are currently running.")
	end
end

return M

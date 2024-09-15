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

	-- Log current working directory before changing
	log("Current working directory before change: " .. vim.fn.getcwd())

	-- Change to the server directory
	local original_dir = vim.fn.getcwd()
	vim.fn.chdir(server_dir)

	-- Log current working directory after changing
	log("Current working directory after change: " .. vim.fn.getcwd())

	-- Log the exact command we're about to run
	log("Running command: go run " .. server_file)

	-- Start the server process
	server_process = vim.fn.jobstart({ "go", "run", server_file }, {
		on_stdout = function(_, data)
			vim.schedule(function()
				for _, line in ipairs(data) do
					if line ~= "" then
						log("Server stdout: " .. line)
						local port = line:match("Server started on port (%d+)")
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
					end
				end
			end)
		end,
		on_stderr = function(_, data)
			vim.schedule(function()
				for _, line in ipairs(data) do
					if line ~= "" then
						error_log("Server stderr: " .. line)
					end
				end
			end)
		end,
		on_exit = function(_, exit_code)
			vim.schedule(function()
				log("Server process exited with code: " .. exit_code)
				server_process = nil
				is_running = false
			end)
		end,
	})

	-- Log current working directory before changing back
	log("Current working directory before changing back: " .. vim.fn.getcwd())

	-- Change back to the original directory
	vim.fn.chdir(original_dir)

	-- Log current working directory after changing back
	log("Current working directory after changing back: " .. vim.fn.getcwd())

	if server_process <= 0 then
		error_log("Failed to start server process. Return code: " .. server_process)
		return
	end

	is_running = true
	log("Started built-in server with job id: " .. server_process)

	-- Set a timer to check if the server is still running after a short delay
	vim.defer_fn(function()
		if not is_running then
			error_log("Server stopped shortly after starting. Check server logs for errors.")
		end
	end, 1000) -- Check after 1 second
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
	if not is_running then
		log("Attempted to stop but no server is running")
		return
	end

	if server_process then
		vim.fn.jobstop(server_process)
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

	-- Set a timer to force kill if it doesn't stop gracefully
	vim.defer_fn(function()
		if is_running then
			error_log("Server didn't stop gracefully, forcing shutdown")
			vim.fn.system('pkill -f "go run.*live/main.go"')
			vim.fn.system('pkill -f "websocat"')
			is_running = false
			server_process = nil
			websocat_process = nil
		end
		log("Stopped live synchronization")
	end, 5000) -- Wait for 5 seconds before force killing
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

return M

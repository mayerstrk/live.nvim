-- core.lua
local M = {}
local uv = vim.loop
local log = require("live.util").log

local server_handle = nil
local websocat_handle = nil
local autocmd_id = nil
local buffer = nil

function M.start(opts)
	-- _______
	-- operation: LiveStart command execution

	-- Check if already running
	if server_handle or websocat_handle then
		log("Live.nvim is already running.")
		return
	end

	-- Start the Go server
	local server_port = M.start_server()
	if not server_port then
		log("Failed to start the Go server.")
		return
	end

	-- Start websocat
	local success = M.start_websocat(server_port)
	if not success then
		log("Failed to start websocat.")
		M.stop_server()
		return
	end

	-- Set up autocommand for buffer changes
	M.setup_autocmd()

	log("Live.nvim started successfully.")

	-- end of operation: LiveStart command execution
	-- _______
end

function M.stop()
	-- _______
	-- operation: LiveStop command execution

	M.stop_autocmd()
	M.stop_websocat()
	M.stop_server()
	log("Live.nvim stopped successfully.")

	-- end of operation: LiveStop command execution
	-- _______
end

function M.start_server()
	-- _______
	-- operation: Starting Go server

	local port = math.random(10000, 60000)
	local cmd = { "go", "run", "server.go", "--port", tostring(port) }
	local handle, pid = nil, nil

	local success, err = pcall(function()
		handle, pid = uv.spawn("go", {
			args = { "run", "server.go", "--port", tostring(port) },
			stdio = { nil, nil, nil },
		}, function(code, signal)
			if code ~= 0 then
				log("Go server exited with code " .. code)
			end
			handle:close()
		end)
	end)

	if not success then
		log("Error starting Go server: " .. tostring(err))
		return nil
	else
		log("Go server started on port " .. port)
		server_handle = handle
		return port
	end

	-- end of operation: Starting Go server
	-- _______
end

function M.stop_server()
	-- _______
	-- operation: Stopping Go server

	if server_handle then
		local success, err = pcall(function()
			server_handle:kill("sigterm")
			server_handle = nil
		end)
		if not success then
			log("Error stopping Go server: " .. tostring(err))
		else
			log("Go server stopped successfully.")
		end
	end

	-- end of operation: Stopping Go server
	-- _______
end

function M.start_websocat(port)
	-- _______
	-- operation: Starting websocat

	local cmd = { "websocat", "-t", "ws://localhost:" .. tostring(port) .. "/ws" }
	local handle, pid = nil, nil

	local success, err = pcall(function()
		handle, pid = uv.spawn("websocat", {
			args = { "-t", "ws://localhost:" .. tostring(port) .. "/ws" },
			stdio = { nil, nil, nil },
		}, function(code, signal)
			if code ~= 0 then
				log("websocat exited with code " .. code)
			end
			handle:close()
		end)
	end)

	if not success then
		log("Error starting websocat: " .. tostring(err))
		return false
	else
		log("websocat started successfully.")
		websocat_handle = handle
		return true
	end

	-- end of operation: Starting websocat
	-- _______
end

function M.stop_websocat()
	-- _______
	-- operation: Stopping websocat

	if websocat_handle then
		local success, err = pcall(function()
			websocat_handle:kill("sigterm")
			websocat_handle = nil
		end)
		if not success then
			log("Error stopping websocat: " .. tostring(err))
		else
			log("websocat stopped successfully.")
		end
	end

	-- end of operation: Stopping websocat
	-- _______
end

function M.setup_autocmd()
	-- _______
	-- operation: Setting up autocommand

	buffer = vim.api.nvim_get_current_buf()
	autocmd_id = vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = buffer,
		callback = function()
			M.on_text_changed()
		end,
	})
	log("Autocommand set up for buffer " .. buffer)

	-- end of operation: Setting up autocommand
	-- _______
end

function M.stop_autocmd()
	-- _______
	-- operation: Removing autocommand

	if autocmd_id then
		local success, err = pcall(function()
			vim.api.nvim_del_autocmd(autocmd_id)
			autocmd_id = nil
		end)
		if not success then
			log("Error removing autocommand: " .. tostring(err))
		else
			log("Autocommand removed successfully.")
		end
	end

	-- end of operation: Removing autocommand
	-- _______
end

function M.on_text_changed()
	-- _______
	-- operation: Handling text change

	local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
	local content = table.concat(lines, "\n")
	-- Send content to the server via websocat
	M.send_content(content)

	-- end of operation: Handling text change
	-- _______
end

function M.send_content(content)
	-- _______
	-- operation: Sending content via websocat

	local success, err = pcall(function()
		-- Assuming you have a way to write to websocat's stdin
		-- For the purpose of this example, we'll just log the content
		log("Sending content. Length: " .. #content)
		-- Implement actual sending logic here
	end)

	if not success then
		log("Error sending content: " .. tostring(err))
	else
		log("Content sent successfully.")
	end

	-- end of operation: Sending content via websocat
	-- _______
end

return M

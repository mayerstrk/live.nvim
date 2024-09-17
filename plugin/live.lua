-- live.lua
local M = {}
local server_process = nil
local websocket_process = nil
local log_file = vim.fn.stdpath("cache") .. "/live.nvim.log"

local function log(message)
	local file = io.open(log_file, "a")
	if file then
		file:write(message .. "\n")
		file:close()
	end
end

function M.start()
	-- Start the Go server
	local server_cmd = { "go", "run", "main.go" }
	local ok, server = pcall(vim.fn.jobstart, server_cmd, {
		on_stdout = function(_, data)
			if data then
				for _, line in ipairs(data) do
					log(line)
				end
			end
		end,
	})
	if not ok then
		log("Failed to start Go server")
		return
	else
		log("Go server started successfully")
		server_process = server
	end

	-- Start the WebSocket client (websocat)
	local websocket_cmd = { "websocat", "ws://localhost:PORT/ws" }
	local ok, websocket = pcall(vim.fn.jobstart, websocket_cmd, {
		on_stderr = function(_, data)
			if data then
				for _, line in ipairs(data) do
					log("WebSocket error: " .. line)
				end
			end
		end,
	})
	if not ok then
		log("Failed to start WebSocket client")
		M.stop()
		return
	else
		log("WebSocket client started successfully")
		websocket_process = websocket
	end

	-- Set up autocommand for buffer changes
	local ok, _ = pcall(vim.api.nvim_create_autocmd, { "TextChanged", "TextChangedI" }, {
		callback = function()
			local content = vim.api.nvim_get_current_buf()
			-- Send content to the WebSocket server
			vim.fn.chansend(websocket_process, content)
		end,
	})
	if not ok then
		log("Failed to set up autocommand")
		M.stop()
		return
	else
		log("Autocommand set up successfully")
	end
end

function M.stop()
	if websocket_process then
		vim.fn.jobstop(websocket_process)
		log("WebSocket client stopped")
		websocket_process = nil
	end
	if server_process then
		vim.fn.jobstop(server_process)
		log("Go server stopped")
		server_process = nil
	end
	-- Remove autocommands
	vim.api.nvim_del_autocmds({ group = "LiveNvimGroup" })
	log("Autocommands removed")
end

return M

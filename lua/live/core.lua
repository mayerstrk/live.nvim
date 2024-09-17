-- lua/live/core.lua
local M = {}
local util = require("live.util")
local Job = require("plenary.job")

local server_job = nil
local websocat_job = nil
local autocmds = {}
local port = nil

local project_root = util.get_project_root()
local server_go_path = project_root .. "server/server.go"

-- Operation: Setup
function M.setup(opts)
	M.config = opts or {}
end
-- End of operation: Setup

-- Operation: Start
function M.start(server_address, endpoint)
	if server_job or websocat_job then
		util.log_error("Live synchronization is already running.")
		return
	end

	local ok, err = pcall(function()
		if not server_address then
			-- Assign an available port
			port = util.get_available_port()
			if not port then
				error("Failed to obtain an available port.")
			end

			-- Start the Go server
			server_job = Job:new({
				command = "go",
				args = { "run", server_go_path, "--port", tostring(port) },
				on_stdout = function(_, data)
					util.log_info("Go server output: " .. data)
				end,
				on_stderr = function(_, data)
					util.log_error("Go server error: " .. data)
				end,
				on_exit = function(_, code)
					util.log_info("Go server has exited with code " .. code .. ".")
				end,
			})
			server_job:start()
			util.log_info("Go server started on port " .. port)

			server_address = "ws://localhost:" .. port
		end

		local filetype = vim.bo.filetype
		local endpoint_path = endpoint or (filetype == "markdown" and "/markdown" or "/code")
		local websocket_url = server_address .. endpoint_path
		util.log_info("WebSocket URL: " .. websocket_url)

		-- Start websocat
		websocat_job = Job:new({
			command = "websocat",
			args = { "-t", websocket_url },
			on_stdout = function(_, data)
				util.log_info("Websocat output: " .. data)
			end,
			on_stderr = function(_, data)
				util.log_error("Websocat error: " .. data)
			end,
			on_exit = function(_, code)
				util.log_info("Websocat has exited with code " .. code .. ".")
			end,
		})
		websocat_job:start()
		util.log_info("WebSocket client started.")

		-- Send initial buffer content
		local content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		websocat_job:send(content)
		util.log_info("Initial buffer content sent.")

		-- Set up autocommands for buffer changes
		local group = vim.api.nvim_create_augroup("LiveSync", { clear = true })
		table.insert(autocmds, group)

		vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
			group = group,
			buffer = 0,
			callback = util.debounce(function()
				local success, err = pcall(function()
					local new_content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
					local diff = util.compute_diff(content, new_content)
					websocat_job:send(diff)
					content = new_content
					util.log_info("Buffer diff sent.")
				end)
				if not success then
					util.log_error("Error sending diff: " .. err)
					M.stop()
				end
			end, 500),
		})

		-- Handle buffer close
		vim.api.nvim_create_autocmd("BufWipeout", {
			group = group,
			buffer = 0,
			callback = function()
				M.stop()
			end,
		})

		util.log_info("Live synchronization started.")
	end)

	if not ok then
		util.log_error("Failed to start live synchronization: " .. err)
		M.stop()
	end
end
-- End of operation: Start

-- Operation: Stop
function M.stop()
	local ok, err = pcall(function()
		-- Stop websocat
		if websocat_job then
			websocat_job:shutdown()
			websocat_job = nil
			util.log_info("WebSocket client stopped.")
		end

		-- Stop Go server
		if server_job then
			server_job:shutdown()
			server_job = nil
			util.log_info("Go server stopped.")
		end

		-- Remove autocommands
		for _, group in ipairs(autocmds) do
			vim.api.nvim_del_augroup_by_id(group)
		end
		autocmds = {}

		util.log_info("Live synchronization stopped.")
	end)

	if not ok then
		util.log_error("Failed to stop live synchronization: " .. err)
	end
end
-- End of operation: Stop

return M

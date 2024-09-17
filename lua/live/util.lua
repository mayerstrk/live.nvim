-- lua/live/util.lua
local M = {}
local uv = vim.loop
local lfs = require("lfs") -- LuaFileSystem library (you may need to install it)

-- Function to get the absolute path to the project root
function M.get_project_root()
	-- Get the current file's directory
	local current_file = debug.getinfo(1, "S").source:sub(2)
	local current_dir = current_file:match("(.*/)")

	-- Traverse up directories to find the project root
	local function is_project_root(dir)
		-- Logic to determine if this is the project root
		-- For example, check if a specific file exists, like .git or a specific marker file
		return lfs.attributes(dir .. ".git", "mode") == "directory" -- assuming .git exists in root
	end

	local dir = current_dir
	while dir ~= "/" do
		if is_project_root(dir) then
			return dir
		end
		-- Move up one directory level
		dir = dir:match("(.*/).*/")
	end

	error("Project root not found")
end

-- Get the project root and dynamically append /server/server.go

-- Operation: Logging
function M.log_info(msg)
	vim.schedule(function()
		vim.notify("[Live.nvim] " .. msg, vim.log.levels.INFO)
	end)
end

function M.log_error(msg)
	vim.schedule(function()
		vim.notify("[Live.nvim] " .. msg, vim.log.levels.ERROR)
	end)
end
-- End of operation: Logging

-- Operation: Get Available Port
function M.get_available_port()
	local server = uv.new_tcp()
	if not server then
		M.log_error("Failed to create TCP server.")
		return nil
	end

	local ok, err = pcall(function()
		server:bind("127.0.0.1", 0)
	end)
	if not ok then
		M.log_error("Failed to bind TCP server: " .. err)
		server:close()
		return nil
	end

	local address = server:getsockname()
	if not address then
		M.log_error("Failed to get socket name.")
		server:close()
		return nil
	end

	server:close()
	if not address.port then
		M.log_error("Address port is nil.")
		return nil
	end

	M.log_info("Available port obtained: " .. tostring(address.port))
	return address.port
end
-- End of operation: Get Available Port

-- Operation: Debounce
function M.debounce(func, timeout)
	local timer = nil
	return function(...)
		local args = { ... }
		if timer then
			timer:stop()
			timer:close()
		end
		timer = uv.new_timer()
		timer:start(timeout, 0, function()
			timer:stop()
			timer:close()
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

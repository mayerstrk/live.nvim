local has_nvim_05, _ = pcall(vim.api.nvim_get_commands, {})
if not has_nvim_05 then
	vim.api.nvim_err_writeln("live.nvim requires Neovim 0.5 or higher")
	return
end

---@type Live
local live = require("live.core")

-- Add a version number for easier management
local VERSION = "0.1.0"

-- Implement a setup function for user configuration
---@param opts table|nil
local function setup(opts)
	opts = opts or {}
	-- You can add user configuration handling here in the future
	live.setup()
end

-- LiveStart command
vim.api.nvim_create_user_command("LiveStart", function(opts)
	if #opts.fargs == 0 then
		live.start_builtin_server()
	elseif #opts.fargs == 2 then
		local host, port = opts.fargs[1], tonumber(opts.fargs[2])
		if not port then
			vim.api.nvim_err_writeln("Invalid port number")
			return
		end
		live.connect_to_server(host, port)
		live.open_browser(port)
	else
		vim.api.nvim_err_writeln("Usage: LiveStart [host port]")
	end
end, { nargs = "*" })

-- LiveStop command
vim.api.nvim_create_user_command("LiveStop", function()
	live.stop()
end, {})

-- LiveCheckServer command
vim.api.nvim_create_user_command("LiveCheckServer", function()
	live.check_running_servers()
end, {})

-- Auto-commands for text changes and buffer unload
vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
	pattern = "*",
	callback = live.on_text_change,
})

vim.api.nvim_create_autocmd("BufUnload", {
	pattern = "*",
	callback = live.on_buffer_unload,
})

-- Return the module with setup function
return {
	setup = setup,
	version = VERSION,
}

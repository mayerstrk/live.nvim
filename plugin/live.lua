-- plugin/live.lua
local live = require("live.core")

-- Operation: Compatibility Check
if vim.fn.has("nvim-0.5") == 0 then
	vim.api.nvim_err_writeln("live.nvim requires Neovim 0.5 or higher")
	return
end
-- End of operation: Compatibility Check

-- Operation: Command Definitions
vim.api.nvim_create_user_command("LiveStart", function(opts)
	local args = opts.fargs
	if #args == 0 then
		live.start()
	elseif #args == 2 then
		live.start(args[1], args[2])
	else
		vim.api.nvim_err_writeln("Usage: :LiveStart [server_address endpoint]")
	end
end, { nargs = "*" })

vim.api.nvim_create_user_command("LiveStop", function()
	live.stop()
end, {})
-- End of operation: Command Definitions

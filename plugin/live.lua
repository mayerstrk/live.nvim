if vim.fn.has("nvim-0.5") == 0 then
	vim.api.nvim_err_writeln("live.nvim requires Neovim 0.5 or higher")
	return
end

local core = require("live.core")

vim.api.nvim_create_user_command("LiveStart", function(opts)
	local ok, err = pcall(function()
		core.start(opts.args)
	end)
	if not ok then
		require("live.util").notify_error("Error executing LiveStart: " .. err)
	end
end, { nargs = "*" })

vim.api.nvim_create_user_command("LiveStop", function()
	local ok, err = pcall(function()
		core.stop()
	end)
	if not ok then
		require("live.util").notify_error("Error executing LiveStop: " .. err)
	end
end, {})

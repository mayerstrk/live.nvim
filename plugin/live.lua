if vim.g.loaded_live_nvim == 1 then
	return
end
vim.g.loaded_live_nvim = 1

local live = require("live")

vim.api.nvim_create_user_command("LiveStart", function(args)
	if #args.fargs ~= 1 then
		vim.api.nvim_err_writeln("Usage: LiveStart <websocket_url>")
		return
	end
	local success, error = live.start(args.fargs[1])
	if not success then
		vim.api.nvim_err_writeln("Failed to start live updates: " .. tostring(error))
	end
end, { nargs = 1 })

vim.api.nvim_create_user_command("LiveStop", function()
	local success, error = live.stop()
	if not success then
		vim.api.nvim_err_writeln("Failed to stop live updates: " .. tostring(error))
	end
end, {})

-- Optional: Set up with default options
local setup_success, setup_error = live.setup({})
if not setup_success then
	vim.api.nvim_err_writeln("Failed to set up live.nvim: " .. tostring(setup_error))
end

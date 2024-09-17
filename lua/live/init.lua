-- init.lua
local live = require("live.core")

-- Define user commands
vim.api.nvim_create_user_command("LiveStart", function(opts)
	live.start(opts)
end, {
	nargs = "*",
})

vim.api.nvim_create_user_command("LiveStop", function()
	live.stop()
end, {})

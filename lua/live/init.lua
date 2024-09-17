-- init.lua
local live = require("live")

vim.api.nvim_create_user_command("LiveStart", live.start, {})
vim.api.nvim_create_user_command("LiveStop", live.stop, {})

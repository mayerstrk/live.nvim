-- util.lua
local M = {}

function M.log(message)
	-- For simplicity, just print to the Neovim message area
	vim.api.nvim_echo({ { "[live.nvim] " .. message, "None" } }, true, {})
end

return M

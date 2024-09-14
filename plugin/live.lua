if vim.fn.has("nvim-0.5") == 0 then
	vim.api.nvim_err_writeln("live.nvim requires Neovim 0.5 or higher")
	return
end

-- Prevent loading the plugin multiple times
if vim.g.loaded_live_nvim == 1 then
	return
end
vim.g.loaded_live_nvim = 1

-- Load the plugin
require("live")

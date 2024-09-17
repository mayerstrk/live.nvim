-- test_get_port.lua
local uv = vim.loop

function get_available_port()
	local server = uv.new_tcp()
	if not server then
		print("Failed to create TCP server.")
		return nil
	end

	local ok, err = pcall(function()
		server:bind("127.0.0.1", 0)
	end)
	if not ok then
		print("Failed to bind TCP server: " .. err)
		server:close()
		return nil
	end

	local address = server:getsockname()
	if not address then
		print("Failed to get socket name.")
		server:close()
		return nil
	end

	server:close()
	if not address.port then
		print("Address port is nil.")
		return nil
	end

	print("Available port obtained: " .. tostring(address.port))
	return address.port
end

get_available_port()

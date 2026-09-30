-- The game runs Lua 5.1, which has limits that the Lua 5.4 used for these tests does not:
-- a function may use at most 60 variables from outside itself (upvalues) and at most 200
-- local variables. A file that breaks them fails to load in the game, and everything after it
-- in the load order is missing (this once took the council window down). This test lists every
-- function of every file in the .toc with luac and checks the numbers. It needs `luac` next to
-- the Lua that runs the tests; without it, it says so and skips.

return function(check, H)
	local interpreter = (arg and arg[-1]) or "lua"
	local dir = interpreter:match("^(.*)[/\\]")
	local luac = (dir and (dir .. "/luac") or "luac")
	local probe = io.open(luac .. ".exe", "rb") or io.open(luac, "rb")
	if not probe then
		print("(limits_test skipped: no luac next to " .. interpreter .. ")")
		return
	end
	probe:close()

	local MAX_UPVALUES, MAX_LOCALS = 60, 200
	local files = {}
	for line in io.lines("ArbiterLootCouncil.toc") do
		line = line:gsub("\r", "")
		if line:match("%.lua$") then files[#files + 1] = (line:gsub("\\", "/")) end
	end

	local worstUpvalues, worstFile = 0, nil
	for _, file in ipairs(files) do
		-- (cmd.exe wants backslashes in the name of the program)
		local program = package.config:sub(1, 1) == "\\" and luac:gsub("/", "\\") or luac
		-- (the whole command in one more pair of quotes: cmd.exe strips the outer ones)
		local pipe = io.popen('""' .. program .. '" -l -l -p "' .. file .. '" 2>&1"')
		local listing = pipe:read("a")
		pipe:close()
		local name
		local broken = {}
		for text in listing:gmatch("[^\r\n]+") do
			local header = text:match("^function (<[^>]*>)") or text:match("^main (<[^>]*>)")
			if header then
				name = header
			elseif name then
				local upvalues = tonumber(text:match("(%d+) upvalues"))
				local locals = tonumber(text:match("(%d+) locals"))
				if upvalues then
					if upvalues > worstUpvalues then worstUpvalues, worstFile = upvalues, name end
					if upvalues > MAX_UPVALUES then broken[#broken + 1] = name .. " uses " .. upvalues .. " upvalues" end
					if locals and locals > MAX_LOCALS then broken[#broken + 1] = name .. " has " .. locals .. " locals" end
					name = nil
				end
			end
		end
		check(file .. " stays within the limits of Lua 5.1" .. (#broken > 0 and (": " .. table.concat(broken, "; ")) or ""), #broken == 0)
	end
	check("the functions with the most outside variables are listed (" .. tostring(worstFile) .. ", " .. worstUpvalues .. ")", worstUpvalues > 0)
end

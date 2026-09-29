-- Offline test harness: stubs the WoW API so addon logic can run under plain Lua 5.1.
-- Usage (from the addon folder): lua Tests/run.lua

local H = {}

local chat = {}
H.chat = chat

function H.setup()
	-- WoW string/table aliases
	format, strlower, strmatch = string.format, string.lower, string.match
	tinsert, tremove = table.insert, table.remove
	wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

	DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) chat[#chat + 1] = msg end }
	SlashCmdList = {}
	Ambiguate = function(name) return (name:gsub("%-.*$", "")) end
	CreateFrame = function()
		return { SetScript = function() end, RegisterEvent = function() end, UnregisterAllEvents = function() end,
			Show = function() end, Hide = function() end }
	end
	GetAddOnMetadata = function() return "test" end
	geterrorhandler = function() return print end
	UnitName = function() return "Tester" end
	UnitClass = function() return "Rogue", "ROGUE" end
	UnitRace = function() return "Human", "Human" end
	time, date = os.time, os.date
	securecallfunction = function(f, ...) return f(...) end
	GetCurrentRegion =function() return 3 end
	GetLocale =function() return "enUS" end
	UnitFactionGroup =function() return "Alliance" end
	GetRealmName = function() return "Realm" end
	strsplit = function(d, s) local t = {} for p in (s .. d):gmatch("(.-)" .. d:gsub("%p", "%%%0")) do t[#t + 1] = p end return unpack(t) end
	strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
	ALC_DB = nil
end

local function load(path)
	local chunk = assert(loadfile(path))
	return chunk("ArbiterLootCouncil", {})
end

function H.loadAddon()
	for _, f in ipairs({
		"Libs/LibStub/LibStub.lua",
		"Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
		"Libs/AceAddon-3.0/AceAddon-3.0.lua",
		"Libs/AceEvent-3.0/AceEvent-3.0.lua",
		"Libs/AceDB-3.0/AceDB-3.0.lua",
		"Core/Core.lua",
		"Core/Locale.lua",
		"Core/Debug.lua",
		"Core/Settings.lua",
		"Core/Commands.lua",
	}) do load(f) end
end

function H.slash(input) SlashCmdList["ALC"](input) end

return H

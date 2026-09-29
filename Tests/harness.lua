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
	UnitName = function(unit) if unit == "player" then return "Tester", "Moo" end end
	-- The client has no global GetItemInfo; it lives in C_Item.
	GetItemInfo = nil
	C_Item = { GetItemInfo = function() end }
	UnitClass = function() return "Rogue", "ROGUE" end
	UnitRace = function() return "Human", "Human" end
	time, date = os.time, os.date
	H.clock = 1000
	GetTime = function() return H.clock end
	C_Timer = { After = function(_, fn) fn() end }
	H.inRaid, H.inGroup = false, false
	IsInRaid = function() return H.inRaid end
	IsInGroup = function(category) if category == 2 then return false end return H.inGroup or H.inRaid end
	GetNumGroupMembers = function() return 1 end
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

-- AceComm needs the real chat system; replace it with a recorder.
local function stubAceComm()
	local lib = LibStub:NewLibrary("AceComm-3.0", 1)
	H.sent = {}
	function lib:Embed(target)
		target.RegisterComm = function(_, prefix, method) H.registered = { prefix = prefix, method = method } end
		target.SendCommMessage = function(_, prefix, text, dist, to, prio)
			H.sent[#H.sent + 1] = { prefix = prefix, text = text, dist = dist, target = to, prio = prio }
		end
		return target
	end
end

function H.loadAddon()
	local function loadAll(files) for _, f in ipairs(files) do load(f) end end
	loadAll({
		"Libs/LibStub/LibStub.lua",
		"Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
		"Libs/AceAddon-3.0/AceAddon-3.0.lua",
		"Libs/AceEvent-3.0/AceEvent-3.0.lua",
		"Libs/AceSerializer-3.0/AceSerializer-3.0.lua",
		"Libs/AceDB-3.0/AceDB-3.0.lua",
	})
	stubAceComm()
	-- Addon files in the same order as the game loads them.
	local files = {}
	for line in io.lines("ArbiterLootCouncil.toc") do
		line = line:gsub("\r", "")
		if line:match("%.lua$") then files[#files + 1] = (line:gsub("\\", "/")) end
	end
	loadAll(files)
end

function H.slash(input) SlashCmdList["ALC"](input) end

return H

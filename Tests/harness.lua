-- Offline test harness: stubs the WoW API so addon logic can run under plain Lua 5.1.
-- Usage (from the addon folder): lua Tests/run.lua

local H = {}

local chat = {}
H.chat = chat

-- Mock UI frames. Any method (names start upper case) is accepted and does nothing;
-- the ones the tests look at keep their state. Frames remember `parent` and `scripts`.
local function newFrame(kind, parent)
	local f = { kind = kind, parent = parent, scripts = {}, shown = true, alpha = 1, w = 100, h = 20 }
	local methods = {
		SetScript = function(self, name, fn) self.scripts[name] = fn end,
		GetScript = function(self, name) return self.scripts[name] end,
		HookScript = function() end,
		Show = function(self) self.shown = true end,
		Hide = function(self) self.shown = false end,
		SetShown = function(self, shown) self.shown = shown and true or false end,
		IsShown = function(self) return self.shown end,
		IsVisible = function(self) return self.shown end,
		SetText = function(self, text) self.text = text end,
		GetText = function(self) return self.text end,
		SetAlpha = function(self, a) self.alpha = a end,
		GetAlpha = function(self) return self.alpha end,
		SetTexture = function(self, tex) self.texture = tex end,
		SetTextColor = function(self, r, g, b, a) self.textColor = { r, g, b, a } end,
		SetColorTexture = function(self, r, g, b, a) self.colorTexture = { r, g, b, a } end,
		SetSize = function(self, w, h) self.w, self.h = w, h end,
		SetWidth = function(self, w) self.w = w end,
		SetHeight = function(self, h) self.h = h end,
		GetWidth = function(self) return self.w end,
		GetHeight = function(self) return self.h end,
		GetStringWidth = function(self) return #(self.text or "") * 6 end,
		GetStringHeight = function() return 12 end,
		GetParent = function(self) return self.parent end,
		SetPoint = function(self, ...) self.point = { ... } end,
		GetPoint = function(self) return "CENTER", nil, "CENTER", 0, 0 end,
		IsMouseOver = function() return false end,
		CreateTexture = function(self) return newFrame("Texture", self) end,
		CreateFontString = function(self) return newFrame("FontString", self) end,
		SetMovable = function(self, v) self.movable = v end,
		StartMoving = function(self) self.moving = true end,
		StopMovingOrSizing = function(self) self.moving = false end,
	}
	return setmetatable(f, {
		__index = function(_, key)
			if methods[key] then return methods[key] end
			if type(key) == "string" and key:match("^%u") then return function() end end
		end,
	})
end

function H.setupFrames()
	CreateFrame = function(kind, _, parent) return newFrame(kind, parent) end
	UIParent = newFrame("Frame")
	STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
	GameTooltip = newFrame("GameTooltip")
	GameTooltip.SetHyperlink = function(self, link) self.hyperlink = link end
end

function H.setup()
	-- WoW string/table aliases
	format, strlower, strmatch = string.format, string.lower, string.match
	tinsert, tremove = table.insert, table.remove
	wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

	DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) chat[#chat + 1] = msg end }
	SlashCmdList = {}
	Ambiguate = function(name) return (name:gsub("%-.*$", "")) end
	H.setupFrames()
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

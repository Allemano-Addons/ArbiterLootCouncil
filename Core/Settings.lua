-- Settings: SavedVariables (ALC_DB via AceDB), defaults and typed accessors.
-- Other modules read/change settings only through these functions.

local ALC = ALC
local LibStub = LibStub

local strlower = string.lower
local tinsert, tremove = table.insert, table.remove

local Settings = {}
ALC.Settings = Settings

-- Item quality ids: 0 poor, 1 common, 2 uncommon, 3 rare, 4 epic, 5 legendary.
local QUALITY_MIN, QUALITY_MAX = 0, 5

local defaults = {
	profile = {
		council = {},         -- array of character names, set before raid
		qualityThreshold = 4, -- epic
		debug = false,
		autoOpenLootWindow = true,
		keepCouncilOpen = false, -- keep the voting window open after an award
		responses = nil,      -- the loot master's answer buttons (Responses); nil = the default five
		minimap = { hidden = false }, -- the launcher button; its position is saved once it has been moved
		windows = {},         -- window key -> { point, relPoint, x, y }
	},
	global = {
		awardLog = {},        -- append-only, written by Awards
		debugLog = {},        -- ring buffer, owned by Debug
		lootList = {          -- the loot master's item list, owned by LootDetection
			items = {}, seen = {}, seenCount = 0, nextId = 0, hidden = 0,
		},
		sessionStore = {},    -- the loot master's running session (Sessions) and candidates (Candidates)
		seqState = {},        -- sid -> last seq we stamped as loot master (Comm)
	},
}

local db

function Settings:Init()
	db = LibStub("AceDB-3.0"):New("ALC_DB", defaults, true)
	ALC.Events:Fire("ALC_SETTINGS_READY")
end

function Settings:GetDB()
	return db
end

local function changed(key)
	ALC.Events:Fire("ALC_SETTINGS_CHANGED", key)
end

-- Debug -----------------------------------------------------------------------
function Settings:IsDebug()
	return db ~= nil and db.profile.debug
end

function Settings:SetDebug(enabled)
	db.profile.debug = enabled and true or false
	changed("debug")
end

-- Loot window -----------------------------------------------------------------
function Settings:GetAutoOpenLootWindow()
	return db.profile.autoOpenLootWindow
end

function Settings:SetAutoOpenLootWindow(enabled)
	db.profile.autoOpenLootWindow = enabled and true or false
	changed("autoOpenLootWindow")
end

-- The saved loot list. LootDetection owns its contents; Settings only hands it over.
function Settings:GetLootStore()
	return db.global.lootList
end

-- The font of every window: a path, or nil for the game's own.
function Settings:GetFont()
	return db.profile.font
end

function Settings:SetFont(path)
	db.profile.font = (type(path) == "string" and path ~= "") and path or nil
	changed("font")
end

-- Whether the voting window stays open after an award.
-- The loot master's answer buttons: a list of { id, label, color }, or nil for the default
-- five. The caller (Responses) checks the list; these only keep it.
function Settings:GetResponseSet()
	local saved = db.profile.responses
	if not saved then return nil end
	local copy = {}
	for i, r in ipairs(saved) do copy[i] = { id = r.id, label = r.label, color = { r.color[1], r.color[2], r.color[3] } } end
	return copy
end

function Settings:SetResponseSet(set)
	db.profile.responses = set
	changed("responses")
end

function Settings:GetKeepCouncilOpen()
	return db.profile.keepCouncilOpen == true
end

function Settings:SetKeepCouncilOpen(enabled)
	db.profile.keepCouncilOpen = enabled and true or false
	changed("keepCouncilOpen")
end

-- Small per-window values, such as how many rows the loot window shows.
function Settings:GetWindowOption(key, name, default)
	local window = db.profile.windows[key]
	local value = window and window[name]
	if value == nil then return default end
	return value
end

function Settings:SetWindowOption(key, name, value)
	local window = db.profile.windows[key] or {}
	window[name] = value
	db.profile.windows[key] = window
end

-- Launcher button (the "minimap button") ----------------------------------------
-- Where the player dropped it on the screen, or nil while it is at its default place.
function Settings:GetButtonPosition()
	local position = db.profile.minimap.position
	if position and position.point then return position end
	return nil
end

function Settings:SetButtonPosition(point, relPoint, x, y)
	db.profile.minimap.position = { point = point, relPoint = relPoint, x = x, y = y }
end

function Settings:IsMinimapHidden()
	return db.profile.minimap.hidden == true
end

function Settings:SetMinimapHidden(hidden)
	db.profile.minimap.hidden = hidden and true or false
	changed("minimapHidden")
end

-- The append-only log of every award, kept for the history views (v0.4). Only Awards writes.
function Settings:GetAwardLog()
	return db.global.awardLog
end

-- Saved state that lets the loot master survive a /reload. Each module owns its keys:
-- Sessions writes `session` and `savedAt`, Candidates writes `candidates`.
function Settings:GetSessionStore()
	return db.global.sessionStore
end

-- Comm keeps the sequence numbers it stamped, so they keep rising after a reload.
function Settings:GetSeqStore()
	return db.global.seqState
end

-- The saved position of a window, or nil when it was never moved. (A window can have a
-- saved open/closed flag without a position.)
function Settings:GetWindowPosition(key)
	local window = db.profile.windows[key]
	if window and window.point then return window end
	return nil
end

function Settings:SetWindowPosition(key, point, relPoint, x, y)
	local window = db.profile.windows[key] or {}
	window.point, window.relPoint, window.x, window.y = point, relPoint, x, y
	db.profile.windows[key] = window
end

-- Whether a window was open when it was last shown or hidden by the player.
function Settings:GetWindowShown(key)
	local window = db.profile.windows[key]
	return window ~= nil and window.shown == true
end

function Settings:SetWindowShown(key, shown)
	local window = db.profile.windows[key] or {}
	window.shown = shown and true or false
	db.profile.windows[key] = window
end

-- Loot quality threshold ------------------------------------------------------
function Settings:GetQualityThreshold()
	return db.profile.qualityThreshold
end

function Settings:SetQualityThreshold(quality)
	if type(quality) ~= "number" or quality < QUALITY_MIN or quality > QUALITY_MAX then
		return false
	end
	db.profile.qualityThreshold = quality
	changed("qualityThreshold")
	return true
end

-- Council list ----------------------------------------------------------------
-- Returns a copy so callers cannot mutate saved state.
function Settings:GetCouncil()
	local copy = {}
	for i, name in ipairs(db.profile.council) do copy[i] = name end
	return copy
end

local function findCouncil(name)
	local lower = strlower(name)
	for i, existing in ipairs(db.profile.council) do
		if strlower(existing) == lower then return i end
	end
end

-- Character names are always "First Last": each word capitalized, the rest lower case.
local function properName(name)
	return (string.gsub(name, "(%S)(%S*)", function(first, rest) return string.upper(first) .. strlower(rest) end))
end

-- Returns true, or false and why: "invalid", "duplicate" or "full". The loot master takes
-- one place of its own in the session's council list, hence the limit.
function Settings:AddCouncilMember(name)
	name = ALC:NormalizeName(name)
	-- The name travels in SESSION_START, where the protocol rejects control characters and `|`.
	if not name or #name < 2 or #name > 48 or string.find(name, "[%c|]") then return false, "invalid" end
	name = properName(name)
	if findCouncil(name) then return false, "duplicate" end
	if #db.profile.council >= ALC.Constants.MAX_COUNCIL - 1 then return false, "full" end
	tinsert(db.profile.council, name)
	changed("council")
	return true
end

function Settings:RemoveCouncilMember(name)
	name = ALC:NormalizeName(name)
	local index = name and findCouncil(name)
	if not index then return false end
	tremove(db.profile.council, index)
	changed("council")
	return true
end

-- Settings: SavedVariables (ALC_DB via AceDB), defaults and typed accessors.
-- Other modules read/change settings only through these functions.

local ALC = ALC
local LibStub = LibStub

local strlower = string.lower
local tinsert, tremove = table.insert, table.remove

local Settings = {}
ALC.Settings = Settings

-- Item quality ids: 0 poor, 1 common, 2 uncommon, 3 rare, 4 epic, 5 legendary.
local QUALITY_MIN, QUALITY_MAX = 2, 4 -- only green, blue and purple drop as loot

local defaults = {
	profile = {
		council = {},         -- array of character names, set before raid
		qualityThreshold = 4, -- epic
		debug = false,
		autoOpenLootWindow = true,
		keepCouncilOpen = false, -- keep the voting window open after an award
		warnMissing = true,      -- say who has no answer from the addon when a session starts
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

-- Whether the loot master is told, when a session starts, which players did not reply to the version check.
function Settings:GetWarnMissing()
	return db.profile.warnMissing ~= false
end

function Settings:SetWarnMissing(enabled)
	db.profile.warnMissing = enabled and true or false
	changed("warnMissing")
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

-- The council and loot master of the last session this character took part in, so the Settings
-- window can show who is on the council also between sessions. { lm = "Name", council = { ... } }
function Settings:GetLastCouncil()
	return db.global.lastCouncil
end

function Settings:SetLastCouncil(lm, council)
	local names = {}
	for i, name in ipairs(council or {}) do names[i] = name end
	db.global.lastCouncil = { lm = lm, council = names }
end

-- The append-only log of every award, kept for the history views (v0.4). Only Awards writes.
function Settings:GetAwardLog()
	return db.global.awardLog
end

-- The last cleared award history, kept so a clear can be taken back: { time, entries }, or nil.
function Settings:GetAwardBackup()
	return db.global.awardLogBackup
end

function Settings:SetAwardBackup(backup)
	db.global.awardLogBackup = backup
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

-- Compact windows (Everyone): smaller rows and buttons in the loot, response and voting windows.
-- Before this setting existed the voting window had its own "compact" option; that is used
-- until the new setting is changed.
function Settings:GetCompact()
	local value = db.profile.compact
	if value == nil then
		local window = db.profile.windows.council
		return window ~= nil and window.compact == true
	end
	return value == true
end

function Settings:SetCompact(enabled)
	db.profile.compact = enabled and true or false
	changed("compact")
end

-- The size of every window as a share of normal (Everyone): 70, 80, 90 or 100 percent.
Settings.WINDOW_SCALES = { 0.7, 0.8, 0.9, 1 }

function Settings:GetWindowScale()
	local value = db.profile.windowScale
	for _, scale in ipairs(self.WINDOW_SCALES) do
		if value == scale then return scale end
	end
	return 1
end

function Settings:SetWindowScale(scale)
	for _, allowed in ipairs(self.WINDOW_SCALES) do
		if scale == allowed then
			db.profile.windowScale = scale
			changed("windowScale")
			return true
		end
	end
	return false
end

-- Announce awards in raid or party chat (loot master): on by default.
function Settings:GetAnnounceAwards()
	return db.profile.announceAwards ~= false
end

function Settings:SetAnnounceAwards(enabled)
	db.profile.announceAwards = enabled and true or false
	changed("announceAwards")
end

-- The disenchanter (loot master): who gets the items nobody wants. A full name, or nil.
function Settings:GetDisenchanter()
	return db.profile.disenchanter
end

-- Returns true, or false and why ("invalid").
function Settings:SetDisenchanter(name)
	if name == nil or name == "" then
		db.profile.disenchanter = nil
		changed("disenchanter")
		return true
	end
	name = ALC:NormalizeName(name)
	-- The name travels in AWARD, where the protocol rejects control characters and `|`.
	if not name or #name < 2 or #name > 48 or string.find(name, "[%c|]") then return false, "invalid" end
	db.profile.disenchanter = (string.gsub(name, "(%S)(%S*)", function(first, rest) return string.upper(first) .. strlower(rest) end))
	changed("disenchanter")
	return true
end

-- The guild bank (loot master): the character that keeps the items the guild stores. A full name, or nil.
function Settings:GetGuildBank()
	return db.profile.guildBank
end

-- Returns true, or false and why ("invalid").
function Settings:SetGuildBank(name)
	if name == nil or name == "" then
		db.profile.guildBank = nil
		changed("guildBank")
		return true
	end
	name = ALC:NormalizeName(name)
	-- The name travels in AWARD, where the protocol rejects control characters and `|`.
	if not name or #name < 2 or #name > 48 or string.find(name, "[%c|]") then return false, "invalid" end
	db.profile.guildBank = (string.gsub(name, "(%S)(%S*)", function(first, rest) return string.upper(first) .. strlower(rest) end))
	changed("guildBank")
	return true
end

-- The Roll column of the voting window (reads /roll from the chat): off by default.
function Settings:GetRollsEnabled()
	return db.profile.rollsEnabled == true
end

function Settings:SetRollsEnabled(enabled)
	db.profile.rollsEnabled = enabled and true or false
	changed("rolls")
end

-- Take the loot for yourself when you open a corpse as master looter, so it sits in your bags
-- before the session starts (loot master): on by default.
function Settings:GetAutoLoot()
	return db.profile.autoLoot ~= false
end

function Settings:SetAutoLoot(enabled)
	db.profile.autoLoot = enabled and true or false
	changed("autoLoot")
end

-- Ask "loot all?" before taking the loot for yourself: on by default.
function Settings:GetAutoLootConfirm()
	return db.profile.autoLootConfirm ~= false
end

function Settings:SetAutoLootConfirm(enabled)
	db.profile.autoLootConfirm = enabled and true or false
	changed("autoLootConfirm")
end

-- Put won items into the trade window by itself (loot master): on by default.
function Settings:GetAutoTrade()
	return db.profile.autoTrade ~= false
end

function Settings:SetAutoTrade(enabled)
	db.profile.autoTrade = enabled and true or false
	changed("autoTrade")
end

-- Answer timer (loot master): players may answer for this many seconds after a session
-- starts; then the response window closes. Off by default.
Settings.TIMER_PRESETS = { 30, 60, 90, 120, 180, 300 }

function Settings:GetTimerEnabled()
	return db.profile.timerEnabled == true
end

function Settings:SetTimerEnabled(enabled)
	db.profile.timerEnabled = enabled and true or false
	changed("timer")
end

function Settings:GetTimerSeconds()
	local value = db.profile.timerSeconds
	local C = ALC.Constants
	if type(value) ~= "number" or value < C.TIMER_MIN or value > C.TIMER_MAX then return 120 end
	return math.floor(value)
end

function Settings:SetTimerSeconds(value)
	local C = ALC.Constants
	if type(value) ~= "number" or value < C.TIMER_MIN or value > C.TIMER_MAX then return false end
	db.profile.timerSeconds = math.floor(value)
	changed("timer")
	return true
end

-- What a new session starts with: seconds, or nil when the timer is off.
function Settings:GetActiveTimer()
	return self:GetTimerEnabled() and self:GetTimerSeconds() or nil
end

-- Recent awards: how many days back the council sees what a player was awarded -----
local RECENT_DAYS = { [7] = true, [14] = true, [30] = true, [90] = true }

function Settings:GetRecentDays()
	local value = db.profile.recentDays
	return RECENT_DAYS[value] and value or 30
end

function Settings:SetRecentDays(value)
	if not RECENT_DAYS[value] then return false end
	db.profile.recentDays = value
	changed("recentDays")
	return true
end

-- The award log: after how many awards the loot master is reminded to export it (0 = never) -----
local LOG_REMINDER = { [0] = true, [500] = true, [1000] = true, [2000] = true }

function Settings:GetLogReminder()
	local value = db.profile.logReminder
	if value == nil then return 1000 end
	return LOG_REMINDER[value] and value or 1000
end

function Settings:SetLogReminder(value)
	if not LOG_REMINDER[value] then return false end
	db.profile.logReminder = value
	changed("logReminder")
	return true
end

-- Loot quality threshold ------------------------------------------------------
function Settings:GetQualityThreshold()
	local quality = db.profile.qualityThreshold
	if type(quality) ~= "number" then return 4 end
	return math.max(QUALITY_MIN, math.min(QUALITY_MAX, quality)) -- an older saved Poor, Common or Legendary
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

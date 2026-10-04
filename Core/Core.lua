-- Core: namespace, event bus, init, shared helpers.
-- Everything lives under the single global `ALC`.

local LibStub = LibStub
local CallbackHandler = LibStub("CallbackHandler-1.0")
local AceAddon = LibStub("AceAddon-3.0")

local strlower = string.lower
local strmatch = string.match
local format = string.format

local ALC = AceAddon:NewAddon("ALC", "AceEvent-3.0")
_G.ALC = ALC

ALC.PROTOCOL_VERSION = 2
ALC.PREFIX = "ALC"

do
	local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	ALC.version = getMeta and getMeta("ArbiterLootCouncil", "Version") or "?"
end

--------------------------------------------------------------------------------
-- Internal event bus: ALC.Events
-- Events are named ALC_<MODULE>_<EVENT>. Register with
--   ALC.Events.Register(owner, "ALC_X_Y", "Method" | function)
-- and fire with ALC.Events:Fire("ALC_X_Y", ...).
--------------------------------------------------------------------------------
do
	local bus = {}
	local registry = CallbackHandler:New(bus, "Register", "Unregister", "UnregisterAll")
	function bus:Fire(event, ...)
		registry:Fire(event, ...)
	end
	ALC.Events = bus
end

--------------------------------------------------------------------------------
-- The API for other addons (Arbiter Soft Reserve is the first)
-- ALC.API_VERSION goes up when something is added to what other addons may use; an addon asks for the
-- version it needs with ALC.HasAPI(n) and says so to the player when ALC is too old. An addon announces
-- itself with ALC.RegisterExtension(name, version), so ALC and the Versions window can tell what is installed.
-- Nothing here changes what ALC does by itself.
--------------------------------------------------------------------------------
ALC.API_VERSION = 5

-- API 5: an addon can add entries to the window menu of the minimap button (Soft Reserve: Results, Session, Import).
-- ALC.RegisterLauncherEntry({ id, label, icon, section, color, available, open }):
--   id        a short key                                  label    the text of the row
--   icon      the name of one of ALC's icons (Media/Icons, "summary", "note", ...)
--   section   the heading the entries of one addon are grouped under ("Soft Reserve")
--   color     6 hex digits: the colour of the heading and of the icons
--   available function() -> true, or false and why not (the row is greyed out and says why)
--   open      function(): what the row does
do
	local launcherEntries = {} -- in the order they were added

	-- Returns true, or false and why not. Registering the same id again replaces the entry.
	function ALC.RegisterLauncherEntry(def)
		if type(def) ~= "table" or type(def.id) ~= "string" or def.id == "" then return false, "The entry needs an id." end
		if type(def.label) ~= "string" or def.label == "" then return false, "The entry needs a label." end
		if type(def.open) ~= "function" then return false, "The entry needs an open function." end
		local entry = {
			id = def.id, label = def.label, icon = type(def.icon) == "string" and def.icon or "loot",
			section = type(def.section) == "string" and def.section or nil, color = type(def.color) == "string" and def.color or nil,
			available = type(def.available) == "function" and def.available or function() return true end, open = def.open,
		}
		for i, e in ipairs(launcherEntries) do
			if e.id == def.id then
				launcherEntries[i] = entry
				ALC.Events:Fire("ALC_LAUNCHER_CHANGED")
				return true
			end
		end
		launcherEntries[#launcherEntries + 1] = entry
		ALC.Events:Fire("ALC_LAUNCHER_CHANGED")
		return true
	end

	function ALC.UnregisterLauncherEntry(id)
		for i, e in ipairs(launcherEntries) do
			if e.id == id then
				table.remove(launcherEntries, i)
				ALC.Events:Fire("ALC_LAUNCHER_CHANGED")
				return
			end
		end
	end

	-- The entries other addons added, in the order they were added.
	function ALC.GetLauncherEntries()
		local list = {}
		for i, e in ipairs(launcherEntries) do list[i] = e end
		return list
	end
end

-- API 5: an addon can say what the "Results" button of the Loot Response window opens (Soft Reserve: its results of the
-- last sessions). ALC.RegisterResultsViewer(function) and ALC.OpenResults(); without one the button opens ALC's own Result
-- window, which shows the rolls of the session that is running.
do
	local resultsViewer
	function ALC.RegisterResultsViewer(fn)
		if type(fn) ~= "function" then return false end
		resultsViewer = fn
		return true
	end
	function ALC.UnregisterResultsViewer() resultsViewer = nil end
	function ALC.OpenResults()
		if resultsViewer and pcall(resultsViewer) then return true end
		if ALC.Results and ALC.Results:HasAny() then
			ALC.ResultWindow:Toggle()
			return true
		end
		ALC:Print(ALC.L["There is no result to show."])
		return false
	end
end

-- API 5: an addon can add a section to the Settings window (Soft Reserve: the options of soft reserve sessions).
-- ALC.RegisterSettingsSection({ id, name, color, rows }): the rows are drawn by ALC in its own style, under a heading in
-- the addon's colour, at the end of the tab each row names. A row:
--   { tab = "everyone" | "lm", type = "check",  label, tip, get = function() -> boolean, set = function(boolean) }
--   { tab, type = "choice", label, options = { { label, value }, ... }, get = function() -> value, set = function(value) }
--   { tab, type = "action", label, confirm = "text for a second click" (optional), onClick = function() }
-- Register before the Settings window is first opened (at login); the window builds its rows once.
do
	local settingsSections = {} -- in the order they were added
	local ROW_TYPES = { check = true, choice = true, action = true }

	local function checkRow(row)
		if type(row) ~= "table" or (row.tab ~= "everyone" and row.tab ~= "lm") then return false, "A row needs a tab (everyone or lm)." end
		if not ROW_TYPES[row.type] then return false, "A row is a check, a choice or an action." end
		if type(row.label) ~= "string" or row.label == "" then return false, "A row needs a label." end
		if row.type == "check" and (type(row.get) ~= "function" or type(row.set) ~= "function") then return false, "A check needs get and set." end
		if row.type == "action" and type(row.onClick) ~= "function" then return false, "An action needs onClick." end
		if row.type == "choice" then
			if type(row.get) ~= "function" or type(row.set) ~= "function" then return false, "A choice needs get and set." end
			if type(row.options) ~= "table" or #row.options < 2 or #row.options > 6 then return false, "A choice needs 2 to 6 options." end
			for _, option in ipairs(row.options) do
				if type(option) ~= "table" or type(option.label) ~= "string" or option.value == nil then return false, "An option needs a label and a value." end
			end
		end
		return true
	end

	-- Returns true, or false and why not. Registering the same id again replaces the section.
	function ALC.RegisterSettingsSection(def)
		if type(def) ~= "table" or type(def.id) ~= "string" or def.id == "" then return false, "The section needs an id." end
		if type(def.name) ~= "string" or def.name == "" then return false, "The section needs a name." end
		if type(def.rows) ~= "table" or #def.rows == 0 then return false, "The section needs rows." end
		for _, row in ipairs(def.rows) do
			local ok, why = checkRow(row)
			if not ok then return false, why end
		end
		local section = { id = def.id, name = def.name, color = type(def.color) == "string" and def.color or nil, rows = def.rows }
		for i, existing in ipairs(settingsSections) do
			if existing.id == def.id then
				settingsSections[i] = section
				return true
			end
		end
		settingsSections[#settingsSections + 1] = section
		return true
	end

	function ALC.UnregisterSettingsSection(id)
		for i, existing in ipairs(settingsSections) do
			if existing.id == id then table.remove(settingsSections, i) return end
		end
	end

	function ALC.GetSettingsSections()
		local list = {}
		for i, section in ipairs(settingsSections) do list[i] = section end
		return list
	end
end

-- API 5: an addon can add a way to start a session (Soft Reserve: "Start SR") next to the normal "Start" of the
-- Loot window. ALC.RegisterStartMode({ id, label, name, color, start }):
--   id     a short key ("SR")                           label  the word on the buttons ("SR": "Start SR")
--   name   the longer name ("Soft Reserve")             color  6 hex digits, the colour of its mark and accent
--   info   (optional) function(itemID) -> a short text or nil: what the addon knows about the item ("SR x3"). The Loot
--          window shows it on the item's line, in the mode's colour, and gives that mode's button an amber frame.
--   start  function(itemStrings) -> true, or false and a message; it starts the session itself
--          (Sessions:StartItems with the same mode, modeName and modeColor)
do
	local startModes = {} -- id -> mode

	-- Returns true, or false and why not. Registering the same id again replaces it.
	function ALC.RegisterStartMode(def)
		if type(def) ~= "table" or type(def.id) ~= "string" or def.id == "" then return false, "The start mode needs an id." end
		if type(def.label) ~= "string" or def.label == "" then return false, "The start mode needs a label." end
		if type(def.start) ~= "function" then return false, "The start mode needs a start function." end
		startModes[def.id] = {
			id = def.id, label = def.label, name = type(def.name) == "string" and def.name or def.label,
			color = type(def.color) == "string" and def.color or nil, start = def.start, info = type(def.info) == "function" and def.info or nil,
		}
		ALC.Events:Fire("ALC_START_MODES_CHANGED")
		return true
	end

	function ALC.UnregisterStartMode(id)
		if startModes[id] then
			startModes[id] = nil
			ALC.Events:Fire("ALC_START_MODES_CHANGED")
		end
	end

	function ALC.GetStartMode(id)
		return startModes[id]
	end

	-- The start modes added by other addons, sorted by label.
	function ALC.GetStartModes()
		local list = {}
		for _, m in pairs(startModes) do list[#list + 1] = m end
		table.sort(list, function(a, b) return a.label < b.label end)
		return list
	end
end

do
	local extensions = {} -- name -> { name, version }

	function ALC.HasAPI(minVersion)
		return type(minVersion) == "number" and ALC.API_VERSION >= minVersion
	end

	-- Returns true, or false and why not. Registering the same name again replaces the version.
	function ALC.RegisterExtension(name, version)
		if type(name) ~= "string" or name == "" then return false, "The extension needs a name." end
		if type(version) ~= "string" and type(version) ~= "number" then return false, "The extension needs a version." end
		extensions[name] = { name = name, version = tostring(version) }
		ALC.Events:Fire("ALC_API_EXTENSION_REGISTERED", name, tostring(version))
		return true
	end

	-- { name, version } of a registered extension, or nil.
	function ALC.GetExtension(name)
		local e = extensions[name]
		return e and { name = e.name, version = e.version } or nil
	end

	-- All registered extensions, sorted by name.
	function ALC.GetExtensions()
		local list = {}
		for _, e in pairs(extensions) do list[#list + 1] = { name = e.name, version = e.version } end
		table.sort(list, function(a, b) return a.name < b.name end)
		return list
	end
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- On WoW Forever every character is "First Last": UnitName returns the first name and
-- the SURNAME as two values, and first names are not unique. The full name is the key.
local function surnameSeparator()
	local consts = Constants and Constants.CharacterNameSeparatorConsts
	return consts and consts.CHARACTERNAME_SURNAME_SEPARATOR or " "
end

-- "First Last" of a unit, nil if the unit does not exist.
function ALC:UnitFullName(unit)
	local first, surname = UnitName(unit)
	if not first or first == "" then return nil end
	if type(surname) == "string" and surname ~= "" then
		return first .. surnameSeparator() .. surname
	end
	return first
end

function ALC:PlayerName()
	return self:UnitFullName("player")
end

-- Unit ids of everyone in the group, ourselves included ("player" alone when ungrouped).
function ALC:GroupUnits()
	local units = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
	else
		units[1] = "player"
		if IsInGroup() then
			for i = 1, 4 do units[#units + 1] = "party" .. i end
		end
	end
	return units
end

-- The group unit of a character name, nil when they are not in the group.
function ALC:FindUnitByName(name)
	for _, unit in ipairs(self:GroupUnits()) do
		local full = self:UnitFullName(unit)
		if full and self:SameName(full, name) then return unit end
	end
	return nil
end

-- Strips a "-Realm" suffix and returns the character name ("First Last").
-- Whether an answer id is one only the loot master can give: the disenchanter or the guild bank.
function ALC:IsSpecialResponse(id)
	return id == ALC.Constants.DISENCHANT_ID or id == ALC.Constants.BANK_ID
end

function ALC:NormalizeName(name)
	if type(name) ~= "string" or name == "" then return nil end
	return strmatch(name, "^([^-]+)")
end

-- Case-insensitive name comparison after normalization.
function ALC:SameName(a, b)
	a, b = self:NormalizeName(a), self:NormalizeName(b)
	return a ~= nil and b ~= nil and strlower(a) == strlower(b)
end

-- The guild rank of a unit, when it is in the same guild as we are: its name and number
-- (0 is the guild master). Nil otherwise, and when the game has no guild data for it.
function ALC:GetGuildRank(unit)
	if not unit or not GetGuildInfo then return nil end
	local guild, rank, index = GetGuildInfo(unit)
	local ownGuild = GetGuildInfo("player")
	if not guild or not ownGuild or guild ~= ownGuild then return nil end
	if type(rank) ~= "string" or rank == "" or #rank > 32 or rank:find("[%c|]") then return nil end
	if type(index) ~= "number" or index < 0 or index > 20 or index ~= math.floor(index) then return nil end
	return rank, index
end

-- GetItemInfo moved into C_Item on newer clients (the global is gone on WoW Forever).
function ALC:GetItemInfo(item)
	local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if not fn then return nil end
	return fn(item)
end

function ALC:GetItemInfoInstant(item)
	local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	if not fn then return nil end
	return fn(item)
end

-- Asks the client to load an item so GetItemInfo works shortly after.
function ALC:RequestItemData(itemID)
	local fn = C_Item and C_Item.RequestLoadItemDataByID
	if fn then fn(itemID) end
end

-- Accepts an item link, an itemString, or an item id. Returns itemString, itemID.
function ALC:ParseItem(input)
	local id
	if type(input) == "number" then
		id = input
	elseif type(input) == "string" then
		local itemString = strmatch(input, "item:%-?%d+[%d:%-]*")
		if itemString then
			itemString = string.gsub(itemString, ":+$", "")
			-- Keep it within the protocol limit, cut on a field boundary.
			while #itemString > 120 do itemString = strmatch(itemString, "^(.*):[^:]*$") or "item:0" end
			id = tonumber(strmatch(itemString, "^item:(%-?%d+)"))
			if id and id >= 1 then return itemString, id end
			return nil
		end
		id = tonumber(input)
	end
	if id and id >= 1 and id == math.floor(id) then return "item:" .. id, id end
	return nil
end

-- Every item in a piece of text: links, itemStrings or plain item ids.
-- Returns an array of { itemString, itemID, link } (link is kept for its colour code).
function ALC:ParseItems(text)
	local out = {}
	if type(text) ~= "string" then return out end
	local function add(token, link)
		local itemString, itemID = self:ParseItem(token)
		if itemString then out[#out + 1] = { itemString = itemString, itemID = itemID, link = link } end
	end
	for link in string.gmatch(text, "|c[^|]*|Hitem:[^|]*|h") do add(link, link) end
	if #out == 0 then
		for token in string.gmatch(text, "item:%-?%d+[%d:%-]*") do add(token) end
	end
	if #out == 0 then
		for token in string.gmatch(text, "%d+") do add(tonumber(token)) end
	end
	return out
end

function ALC:Print(msg, ...)
	if select("#", ...) > 0 then msg = format(msg, ...) end
	DEFAULT_CHAT_FRAME:AddMessage("|cffE6A93C[ALC]|r " .. tostring(msg))
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
function ALC:OnInitialize()
	self.Settings:Init()
	self.UI:Init()
	self.Comm:Init()
	self.Council:Init()
	self.Sessions:Init()
	self.LootDetection:Init()
	self.LootWindow:Init()
	self.Responses:Init()
	self.Candidates:Init()
	self.Results:Init()
	self.Voting:Init()
	self.Awards:Init()
	self.Profile:Init()
	self.Recent:Init()
	self.Context:Init()
	self.Trades:Init()
	self.ResponseWindow:Init()
	self.CouncilWindow:Init()
	self.ContextWindow:Init()
	self.HubLog:Init()
	self.AwardDialog:Init()
	self.VersionWindow:Init()
	self.ResultWindow:Init()
	self.SettingsWindow:Init()
	self.MinimapButton:Init()
	self.Debug:Log("Core", "Arbiter Loot Council %s loaded (protocol v%d)", self.version, self.PROTOCOL_VERSION)
end

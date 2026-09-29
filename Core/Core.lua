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
	self.Voting:Init()
	self.Awards:Init()
	self.Trades:Init()
	self.ResponseWindow:Init()
	self.CouncilWindow:Init()
	self.AwardDialog:Init()
	self.SettingsWindow:Init()
	self.MinimapButton:Init()
	self.Debug:Log("Core", "Arbiter Loot Council %s loaded (protocol v%d)", self.version, self.PROTOCOL_VERSION)
end

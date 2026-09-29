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

ALC.PROTOCOL_VERSION = 1
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

function ALC:Print(msg, ...)
	if select("#", ...) > 0 then msg = format(msg, ...) end
	DEFAULT_CHAT_FRAME:AddMessage("|cffE6A93C[ALC]|r " .. tostring(msg))
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
function ALC:OnInitialize()
	self.Settings:Init()
	self.Comm:Init()
	self.Council:Init()
	self.Sessions:Init()
	self.Debug:Log("Core", "Arbiter Loot Council %s loaded (protocol v%d)", self.version, self.PROTOCOL_VERSION)
end

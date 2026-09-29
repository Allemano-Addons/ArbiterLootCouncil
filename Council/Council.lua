-- Council: who the loot master is and who is on the council.
--
-- Loot master: the master looter when Master Loot is active, otherwise the group
-- leader. Outside a group you are your own loot master, which is what lets `/alc test`
-- run solo. During a session the council is the list the loot master sent in
-- SESSION_START; otherwise it is the list in our own settings.

local ALC = ALC
local LibStub = LibStub

local Debug = ALC.Debug

local Council = {}
ALC.Council = Council
LibStub("AceEvent-3.0"):Embed(Council)

local lastLootMaster = false -- false = not resolved yet (no event on the first resolve)

--------------------------------------------------------------------------------
-- Game API access. Replaceable in tests.
--------------------------------------------------------------------------------

-- Returns method, partyMaster, raidMaster like GetLootMethod().
function Council.GetLootMethodInfo()
	local fn = GetLootMethod or (C_PartyInfo and C_PartyInfo.GetLootMethod)
	if not fn then return nil end
	return fn()
end

function Council.GetLeaderName()
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local unit = "raid" .. i
			if UnitIsGroupLeader(unit) then return ALC:UnitFullName(unit) end
		end
		return nil
	end
	if UnitIsGroupLeader("player") then return ALC:PlayerName() end
	for i = 1, 4 do
		local unit = "party" .. i
		if UnitExists(unit) and UnitIsGroupLeader(unit) then return ALC:UnitFullName(unit) end
	end
end

local function isMasterLoot(method)
	if method == "master" then return true end
	local enum = Enum and Enum.LootMethod
	return type(method) == "number" and enum ~= nil and method == enum.Masterlooter
end

--------------------------------------------------------------------------------
-- Loot master
--------------------------------------------------------------------------------
function Council:GetLootMaster()
	if not IsInGroup() then
		return ALC:NormalizeName(ALC:PlayerName())
	end
	local method, partyMaster, raidMaster = self.GetLootMethodInfo()
	if isMasterLoot(method) then
		local unit
		if IsInRaid() and raidMaster and raidMaster > 0 then
			unit = "raid" .. raidMaster
		elseif partyMaster == 0 then
			unit = "player"
		elseif partyMaster and partyMaster > 0 then
			unit = "party" .. partyMaster
		end
		local name = unit and ALC:UnitFullName(unit)
		if name then return ALC:NormalizeName(name) end
		Debug:Warn("Council", "master looter unit %s not found, using the group leader", tostring(unit))
	end
	return ALC:NormalizeName(self.GetLeaderName())
end

function Council:IsLootMaster(name)
	local lootMaster = self:GetLootMaster()
	return lootMaster ~= nil and ALC:SameName(name, lootMaster)
end

function Council:AmLootMaster()
	return self:IsLootMaster(ALC:PlayerName())
end

-- Re-resolves the loot master and announces a change.
function Council:Refresh()
	local current = self:GetLootMaster()
	if lastLootMaster == false then
		lastLootMaster = current
		return
	end
	if (current == nil) ~= (lastLootMaster == nil) or (current and not ALC:SameName(current, lastLootMaster)) then
		local old = lastLootMaster
		lastLootMaster = current
		Debug:Log("Council", "loot master changed: %s -> %s", tostring(old), tostring(current))
		ALC.Events:Fire("ALC_COUNCIL_LM_CHANGED", current, old)
	end
end

--------------------------------------------------------------------------------
-- Council
--------------------------------------------------------------------------------

-- The council list in force: the active session's, else our own settings.
function Council:GetList()
	local sessions = ALC.Sessions
	local list = sessions and sessions:GetSessionCouncil()
	return list or ALC.Settings:GetCouncil()
end

function Council:IsCouncil(name)
	if not ALC:NormalizeName(name) then return false end
	for _, member in ipairs(self:GetList()) do
		if ALC:SameName(member, name) then return true end
	end
	return false
end

function Council:AmCouncil()
	return self:IsCouncil(ALC:PlayerName())
end

-- What the loot master sends in SESSION_START: itself first (it must see the votes),
-- then the configured council, without duplicates, capped at the protocol limit.
function Council:BuildSessionList(lootMaster)
	local max = ALC.Constants.MAX_COUNCIL
	local list = { lootMaster }
	for _, name in ipairs(ALC.Settings:GetCouncil()) do
		if #list >= max then
			Debug:Warn("Council", "council list truncated to %d names", max)
			break
		end
		local duplicate = false
		for _, existing in ipairs(list) do
			if ALC:SameName(existing, name) then duplicate = true break end
		end
		if not duplicate then list[#list + 1] = name end
	end
	return list
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------
function Council:Init()
	local refresh = function() Council:Refresh() end
	self:RegisterEvent("PLAYER_ENTERING_WORLD", refresh)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", refresh)
	self:RegisterEvent("PARTY_LOOT_METHOD_CHANGED", refresh)
	self:RegisterEvent("PARTY_LEADER_CHANGED", refresh)
end

-- /alc debug lm: what the game says about the loot method, and who we think leads.
ALC.Commands:RegisterDebug("lm", function()
	local method, partyMaster, raidMaster = Council.GetLootMethodInfo()
	ALC:Print("GetLootMethod: %s, party=%s, raid=%s", tostring(method), tostring(partyMaster), tostring(raidMaster))
	ALC:Print("in group=%s raid=%s, leader=%s", tostring(IsInGroup()), tostring(IsInRaid()), tostring(Council.GetLeaderName()))
	ALC:Print("loot master: %s (you: %s)", tostring(Council:GetLootMaster()), tostring(ALC:PlayerName()))
	ALC:Print("council: %s", table.concat(Council:GetList(), ", "))
end)

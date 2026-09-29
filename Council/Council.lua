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
	return nil
end

-- True when the game says we are the master looter.
function Council.IsPlayerMasterLooter()
	return IsMasterLooter ~= nil and IsMasterLooter() == true
end

-- The roster entry flagged as master looter: index, name (as GetRaidRosterInfo reports it).
function Council.FindRosterMasterLooter()
	if not GetRaidRosterInfo then return nil end
	for i = 1, GetNumGroupMembers() do
		local name, _, _, _, _, _, _, _, _, _, isMasterLooter = GetRaidRosterInfo(i)
		if isMasterLooter then return i, name end
	end
	return nil
end

-- Newer clients return the loot method as a number: 2 is master loot, 3 group loot.
local function isMasterLoot(method)
	if method == "master" or method == 2 then return true end
	local enum = Enum and Enum.LootMethod
	return type(method) == "number" and enum ~= nil and method == enum.Masterlooter
end

-- The party unit for a roster name. On Forever the roster reports the full
-- "First Last"; a bare first name is accepted as a fallback.
local function unitByRosterName(rosterName)
	if type(rosterName) ~= "string" then return nil end
	local units = { "player", "party1", "party2", "party3", "party4" }
	for _, unit in ipairs(units) do
		local full = ALC:UnitFullName(unit)
		if full and ALC:SameName(full, rosterName) then return unit end
	end
	for _, unit in ipairs(units) do
		if UnitName(unit) == rosterName then return unit end
	end
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
		local name = self:FindMasterLooter(partyMaster, raidMaster)
		if name then return name end
		Debug:Warn("Council", "master loot is active but the master looter was not found, using the group leader")
	end
	return ALC:NormalizeName(self.GetLeaderName())
end

-- Master looter's full name, tried in order: the game says it is us, the ids
-- from the loot method, the roster flag. Returns nil when none of them finds one.
function Council:FindMasterLooter(partyMaster, raidMaster)
	if self.IsPlayerMasterLooter() then
		return ALC:NormalizeName(ALC:PlayerName())
	end

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

	local index, rosterName = self.FindRosterMasterLooter()
	if index then
		unit = IsInRaid() and ("raid" .. index) or unitByRosterName(rosterName)
		name = unit and ALC:UnitFullName(unit)
		if name then return ALC:NormalizeName(name) end
	end
	return nil
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
	ALC:Print("loot method: %s (party=%s, raid=%s), master loot=%s", tostring(method), tostring(partyMaster),
		tostring(raidMaster), tostring(isMasterLoot(method)))
	ALC:Print("in group=%s raid=%s, leader=%s, IsMasterLooter()=%s", tostring(IsInGroup()), tostring(IsInRaid()),
		tostring((Council.GetLeaderName())), tostring(Council.IsPlayerMasterLooter()))
	local index, rosterName = Council.FindRosterMasterLooter()
	ALC:Print("roster master looter flag: index=%s name=%s", tostring(index), tostring(rosterName))
	ALC:Print("loot master: %s (you: %s)", tostring(Council:GetLootMaster()), tostring(ALC:PlayerName()))
	ALC:Print("council: %s", table.concat(Council:GetList(), ", "))
end)

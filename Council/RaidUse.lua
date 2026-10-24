-- RaidUse: whether the loot master uses Arbiter Loot Council in this raid.
--
-- A box asks "Use Arbiter Loot Council in this raid?" when master loot is set and you become the master looter, in a raid
-- or a party (again each time the master looter changes to you), and each time you enter a raid instance as the loot
-- master (the leader when master loot is off). No pauses ALC for you as loot master: nothing goes on the loot list, no auto loot,
-- no sessions. Raiders are not affected: they only answer sessions, and none start. The answer lasts until you leave
-- the group or are asked again, also over a /reload; /alc on and /alc off change it by hand.
--
-- Events:
--   ALC_RAID_USE_CHANGED (on)   the answer changed

local ALC = ALC
local L = ALC.L
local Debug = ALC.Debug
local strlower = string.lower

local RaidUse = {}
ALC.RaidUse = RaidUse
LibStub("AceEvent-3.0"):Embed(RaidUse)

local POPUP = "ALC_USE_IN_RAID"
local lastMasterLooter = false -- the master looter last seen; false = not looked yet (login), nil = no master loot
local inRaidInstance = false

-- The answers, per character (lower-case name): { on = boolean }. Kept in the saved variables so a /reload keeps them.
local function answers()
	local db = ALC.Settings:GetDB()
	db.global.raidUse = db.global.raidUse or {}
	return db.global.raidUse
end

local function myKey()
	local name = ALC:PlayerName()
	return name and strlower(name)
end

-- True unless the player answered No for this raid. Outside a raid, and before any answer, ALC works as always.
function RaidUse:IsActive()
	local key = myKey()
	local entry = key and answers()[key]
	return not (entry and entry.on == false)
end

function RaidUse:Set(on, quiet)
	local key = myKey()
	if not key then return end
	on = on and true or false
	answers()[key] = { on = on }
	if not quiet then
		ALC:Print(on and L["Arbiter Loot Council is on for this raid."]
			or L["Arbiter Loot Council is off for this raid: no loot list and no sessions for you as loot master. /alc on turns it on again."])
	end
	ALC.Events:Fire("ALC_RAID_USE_CHANGED", on)
end

-- Forgets the answer (the group is gone): the next raid starts with ALC on.
function RaidUse:Forget()
	local key = myKey()
	if key and answers()[key] ~= nil then
		answers()[key] = nil
		ALC.Events:Fire("ALC_RAID_USE_CHANGED", true)
	end
end

-- Shows the question. Returns true when it was shown (the setting is on and the game has the box).
function RaidUse:Ask()
	if not ALC.Settings:GetAskRaidUse() then return false end
	if not (StaticPopup_Show and StaticPopupDialogs) then return false end
	StaticPopupDialogs[POPUP] = StaticPopupDialogs[POPUP] or {
		text = L["Use Arbiter Loot Council in this raid?\n\nNo: ALC stays quiet for you as loot master: no loot list, no auto loot, no sessions. Raiders are not affected. /alc on turns it on again."],
		button1 = YES or "Yes",
		button2 = NO or "No",
		OnAccept = function() RaidUse:Set(true) end,
		-- Only the No button counts; the box closing for another reason leaves the answer as it was.
		OnCancel = function(_, _, reason) if reason == "clicked" then RaidUse:Set(false) end end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = false,
		preferredIndex = 3,
	}
	StaticPopup_Show(POPUP)
	ALC.Debug:Log("RaidUse", "asked whether to use ALC in this raid")
	return true
end

-- The master looter's name, or nil when master loot is off.
local function masterLooter()
	local method, partyMaster, raidMaster = ALC.Council.GetLootMethodInfo()
	if not ALC.Council.IsMasterLootMethod(method) then return nil end
	return ALC.Council:FindMasterLooter(partyMaster, raidMaster)
end

-- The loot method or the master looter changed: ask when it is now us, in a raid or a party (ALC works in both).
-- The first look after login or a /reload only remembers who it is. Every step is logged (/alc debug log).
function RaidUse:OnLootMethodChanged()
	if not IsInGroup() then
		lastMasterLooter = nil
		Debug:Log("RaidUse", "loot method changed outside a group: no question")
		return
	end
	local current = masterLooter()
	local was = lastMasterLooter
	lastMasterLooter = current
	if was == false then
		Debug:Log("RaidUse", "first look: master looter is %s", tostring(current))
	elseif not current then
		Debug:Log("RaidUse", "master loot is off: no question")
	elseif was and ALC:SameName(current, was) then
		Debug:Log("RaidUse", "master looter is still %s: no question", current)
	elseif not ALC:SameName(current, ALC:PlayerName()) then
		Debug:Log("RaidUse", "master looter is now %s, not you: no question", current)
	else
		Debug:Log("RaidUse", "you are the master looter now (was %s)", tostring(was))
		self:Ask()
	end
end

-- A new zone: ask when we have just entered a raid instance as the loot master. A /reload inside it does not ask.
function RaidUse:OnZone(isReload)
	local inInstance, kind = false, nil
	if IsInInstance then inInstance, kind = IsInInstance() end
	local now = inInstance and kind == "raid" or false
	local was = inRaidInstance
	inRaidInstance = now
	if isReload or not now or was then return end
	if not IsInGroup() then
		Debug:Log("RaidUse", "entered a raid instance alone: no question")
	elseif not ALC.Council:AmLootMaster() then
		Debug:Log("RaidUse", "entered a raid instance, the loot master is %s: no question", tostring(ALC.Council:GetLootMaster()))
	else
		Debug:Log("RaidUse", "entered a raid instance as the loot master")
		self:Ask()
	end
end

-- /alc debug raiduse: what RaidUse sees right now.
function RaidUse:Report()
	local method = ALC.Council.GetLootMethodInfo()
	ALC:Print("ALC in this raid: %s (ask: %s)", self:IsActive() and "on" or "off", tostring(ALC.Settings:GetAskRaidUse()))
	ALC:Print("group=%s raid=%s, loot method=%s, master loot=%s, master looter=%s", tostring(IsInGroup()), tostring(IsInRaid()),
		tostring(method), tostring(ALC.Council.IsMasterLootMethod(method)), tostring(masterLooter()))
	ALC:Print("loot master=%s (you: %s), last master looter seen=%s, in a raid instance=%s",
		tostring(ALC.Council:GetLootMaster()), tostring(ALC:PlayerName()), tostring(lastMasterLooter), tostring(inRaidInstance))
end

function RaidUse:Init()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, _, isReloadingUi)
		if lastMasterLooter == false then lastMasterLooter = IsInGroup() and masterLooter() or nil end
		RaidUse:OnZone(isReloadingUi)
	end)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() RaidUse:OnZone(false) end)
	self:RegisterEvent("PARTY_LOOT_METHOD_CHANGED", function() RaidUse:OnLootMethodChanged() end)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function()
		if not IsInGroup() then
			RaidUse:Forget()
			lastMasterLooter = nil
		end
	end)
end

ALC.Commands:RegisterDebug("raiduse", function() RaidUse:Report() end)
ALC.Commands:Register("on", function() RaidUse:Set(true) end, L["use ALC in this raid (after answering No)"])
ALC.Commands:Register("off", function() RaidUse:Set(false) end, L["do not use ALC in this raid: no loot list and no sessions for you as loot master"])

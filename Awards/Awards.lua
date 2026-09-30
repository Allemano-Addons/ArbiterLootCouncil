-- Awards: the loot master hands an item to a candidate.
--
-- Award(name) does, in this order:
--   1. finds out whether the item can be handed out now (loot window open, we are the
--      master looter and the winner is a loot candidate);
--   2. broadcasts AWARD for that item (the session ends for everybody when its last item is awarded);
--   3. gives the item with GiveMasterLoot, or marks it "Awaiting trade";
--   4. announces the winner in raid chat;
--   5. appends a line to the award log.
-- GiveMasterLoot cannot say whether it worked, so we wait for the loot slot to empty.
--
-- Events:
--   ALC_AWARDS_LOGGED (entry)     an award was written to the log (loot master only)
--   ALC_AWARDS_ANNOUNCED (text)   the winner was announced (or printed, when ungrouped)

local ALC = ALC
local LibStub = LibStub
local L = ALC.L

local Debug = ALC.Debug

local strlower, format = string.lower, string.format
local time = time

local Awards = {}
ALC.Awards = Awards
LibStub("AceEvent-3.0"):Embed(Awards)

local GIVE_TIMEOUT = 15   -- seconds to wait for the loot slot to empty
local MAX_CANDIDATE_INDEX = 40

local lootOpen = false
local pendingGive         -- { slot, sid, winner, itemString } while we wait for the slot to empty
local lastAnnouncement

function Awards:GetLastAnnouncement()
	return lastAnnouncement
end

-- The append-only log (do not change it).
function Awards:GetLog()
	return ALC.Settings:GetAwardLog()
end

--------------------------------------------------------------------------------
-- Handing the item over
--------------------------------------------------------------------------------
local function findLootSlot(itemID)
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotLink(slot)
		if link then
			local _, id = ALC:ParseItem(link)
			if id == itemID then return slot end
		end
	end
end

-- The master loot list may name people by first name only; a full name is preferred.
local function matches(candidateName, winner)
	if ALC:SameName(candidateName, winner) then return 2 end
	local first = strlower(winner):match("^(%S+)")
	if first and strlower(candidateName) == first then return 1 end
	return 0
end

-- The loot slot and candidate index that hand `itemID` to `winner`, or nil when the
-- item cannot be handed out right now.
function Awards:FindGiveTarget(itemID, winner)
	if not lootOpen or not ALC.Council.IsPlayerMasterLooter() then return nil end
	local slot = findLootSlot(itemID)
	if not slot then return nil end
	local bestIndex, bestScore = nil, 0
	for index = 1, MAX_CANDIDATE_INDEX do
		local name = GetMasterLootCandidate(slot, index)
		local score = name and matches(name, winner) or 0
		if score > bestScore then bestIndex, bestScore = index, score end
	end
	if bestIndex then return slot, bestIndex end
	return nil
end

-- True when Award would hand the item out at once (used by the confirmation dialog).
function Awards:CanGiveNow(winner, item)
	local target = ALC.Sessions:GetItem(item or 1)
	return target ~= nil and self:FindGiveTarget(target.itemID, winner) ~= nil
end

--------------------------------------------------------------------------------
-- Announcing and logging
--------------------------------------------------------------------------------
local function announce(target, entry)
	local link = select(2, ALC:GetItemInfo(target.itemString)) or ("[item:" .. target.itemID .. "]")
	local text = format("[ALC] %s -> %s (%s)", link, entry.name, ALC.Responses:GetLabel(entry.response))
	lastAnnouncement = text
	local channel = (IsInRaid() and "RAID") or (IsInGroup() and "PARTY") or nil
	if channel then
		SendChatMessage(text, channel)
	else
		ALC:Print(text)
	end
	ALC.Events:Fire("ALC_AWARDS_ANNOUNCED", text)
end

local function logAward(session, target, entry, votes)
	local log = ALC.Settings:GetAwardLog()
	local record = {
		itemID = target.itemID,
		itemString = target.itemString,
		winner = entry.name,
		class = entry.class,
		response = entry.response,
		responseLabel = ALC.Responses:GetLabel(entry.response),
		responseColor = (ALC.Responses:Get(entry.response) or {}).color,
		votes = votes,
		sid = session.sid,
		lm = session.lm,
		time = time(),
		zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or "",
	}
	log[#log + 1] = record
	ALC.Events:Fire("ALC_AWARDS_LOGGED", record)
end

--------------------------------------------------------------------------------
-- Award
--------------------------------------------------------------------------------

-- Awards an item of the running session (the first when none is named) to a candidate.
-- Returns true, or false and a message.
function Awards:Award(name, item)
	item = item or 1
	local session = ALC.Sessions:GetSession()
	if not session then return false, L["There is no active session."] end
	if not session.isLM or not ALC.Council:AmLootMaster() then
		return false, L["Only the loot master can award items."]
	end
	local target = session.items[item]
	if not target then return false, L["That item is not in the session."] end
	if target.winner then return false, L["That item has already been awarded."] end
	local entry = ALC.Candidates:Get(name, item)
	if not entry then return false, L["That player has not answered."] end
	if entry.response == "PASS" then return false, L["That player passed."] end

	local votes = ALC.Voting:GetVotes(entry.name, item)
	local slot, index = self:FindGiveTarget(target.itemID, entry.name)
	-- An item that is awarded to the loot master is already in the loot master's bags.
	if not slot and not ALC:SameName(entry.name, ALC:PlayerName()) then
		ALC.LootDetection:MarkAwaitingTrade(session.sid, item)
	end

	local sent = ALC.Comm:SendRaid("AWARD", session.sid,
		{ item = item, winner = entry.name, itemID = target.itemID, response = entry.response })
	if not sent then
		return false, L["Could not send the award. See /alc debug log."]
	end

	if slot then
		local ok, err = pcall(GiveMasterLoot, slot, index)
		if ok then
			pendingGive = { slot = slot, sid = session.sid, item = item, winner = entry.name, itemString = target.itemString }
			local waiting = pendingGive
			C_Timer.After(GIVE_TIMEOUT, function() Awards:OnGiveTimeout(waiting) end)
		else
			Debug:Error("Awards", "GiveMasterLoot failed: %s", tostring(err))
			ALC.LootDetection:MarkAwaitingTrade(session.sid, item)
			ALC:Print(L["Could not hand out the item. Trade it to %s."], entry.name)
		end
	end

	-- Log first: the announcement refreshes windows that read the log (the history).
	logAward(session, target, entry, votes)
	announce(target, entry)
	Debug:Log("Awards", "%s -> %s (%s, %d votes, %s)", target.itemString, entry.name, entry.response, votes,
		slot and "given" or "awaiting trade")
	return true
end

-- The loot slot emptied: the game handed the item over.
function Awards:OnLootSlotCleared(slot)
	if pendingGive and pendingGive.slot == slot then
		Debug:Log("Awards", "slot %d emptied: %s was handed out", slot, pendingGive.winner)
		pendingGive = nil
	end
end

-- Nothing happened in time (for instance the confirmation was declined).
function Awards:OnGiveTimeout(waiting)
	if pendingGive ~= waiting then return end
	pendingGive = nil
	ALC.LootDetection:MarkAwaitingTrade(waiting.sid, waiting.item)
	ALC:Print(L["%s was not handed out. Trade it to %s."], select(2, ALC:GetItemInfo(waiting.itemString)) or waiting.itemString, waiting.winner)
end

function Awards:Init()
	self:RegisterEvent("LOOT_OPENED", function() lootOpen = true end)
	self:RegisterEvent("LOOT_CLOSED", function() lootOpen = false end)
	self:RegisterEvent("LOOT_SLOT_CLEARED", function(_, slot) Awards:OnLootSlotCleared(slot) end)
end

-- Test hooks: the loot window state normally comes from the game's events.
function Awards:SetLootOpen(open) lootOpen = open and true or false end

ALC.Commands:Register("award", function(arg)
	-- /alc award <name> [item number]
	local name, number = string.match(arg or "", "^(.-)%s*(%d*)$")
	if not name or name == "" then
		ALC:Print(L["Usage: /alc award <name> [item number]"])
		return
	end
	local ok, message = Awards:Award(name, tonumber(number) or 1)
	if not ok then ALC:Print(message) end
end, L["award the item to a candidate, without asking (loot master)"])

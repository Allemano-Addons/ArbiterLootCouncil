-- Awards: the loot master hands an item to a candidate.
--
-- Award(name) does, in this order:
--   1. finds out whether the item can be handed out now (loot window open, we are the
--      master looter and the winner is a loot candidate);
--   2. broadcasts AWARD for that item (the session ends for everybody when its last item is awarded);
--   3. gives the item with GiveMasterLoot, or marks it "Awaiting trade";
--   4. announces the winner in raid chat (party chat in a party);
--   5. appends a line to the award log.
-- GiveMasterLoot cannot say whether it worked, so we wait for the loot slot to empty.
--
-- Events:
--   ALC_AWARDS_LOGGED (entry)     an award was written to the log (loot master only)
--   ALC_AWARDS_CLEARED (count)    the history was cleared (or restored, count 0)
--   ALC_AWARDS_REVOKED (entry)    an award was taken back (Undo award); the log line is marked `revoked`
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
	if channel and ALC.Settings:GetAnnounceAwards() then
		SendChatMessage(text, channel)
	elseif channel then
		ALC:Print(L["Not announced in chat: %s"], text) -- the loot master chose not to announce
	else
		ALC:Print(text)
	end
	ALC.Events:Fire("ALC_AWARDS_ANNOUNCED", text)
end

local function logAward(session, target, entry, votes, item)
	local log = ALC.Settings:GetAwardLog()
	local record = {
		item = item,
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

-- The entry for an award to the disenchanter (who need not have answered), or nil and a message.
local function disenchantEntry()
	local name = ALC.Settings:GetDisenchanter()
	if not name then return nil, L["No disenchanter is set. Set one in Settings, Loot master."] end
	local unit = ALC:FindUnitByName(name)
	if not unit and not ALC:SameName(name, ALC:PlayerName()) then
		return nil, format(L["%s is not in your group."], name)
	end
	local class = unit and select(2, UnitClass(unit)) or nil
	return { name = name, class = class or "PRIEST", response = ALC.Constants.DISENCHANT_ID }
end

-- The entry an award to the disenchanter would have, or nil and why not.
function Awards:GetDisenchantEntry()
	return disenchantEntry()
end

-- Whether the loot master can award to the disenchanter right now: true, or false and why.
function Awards:CanDisenchant()
	local entry, message = disenchantEntry()
	return entry ~= nil, message
end

-- Awards an item of the running session (the first when none is named) to a candidate, or,
-- with `disenchant`, to the disenchanter from the settings.
-- Returns true, or false and a message.
function Awards:Award(name, item, disenchant)
	item = item or 1
	local session = ALC.Sessions:GetSession()
	if not session then return false, L["There is no active session."] end
	if not session.isLM or not ALC.Council:AmLootMaster() then
		return false, L["Only the loot master can award items."]
	end
	local target = session.items[item]
	if not target then return false, L["That item is not in the session."] end
	if target.winner then return false, L["That item has already been awarded."] end
	if session.paused then return false, L["The session is paused. Resume it to award."] end
	local entry
	if disenchant then
		local message
		entry, message = disenchantEntry()
		if not entry then return false, message end
	else
		entry = ALC.Candidates:Get(name, item)
		if not entry then return false, L["That player has not answered."] end
		if entry.response == "PASS" then return false, L["That player passed."] end
	end

	local votes = disenchant and 0 or ALC.Voting:GetVotes(entry.name, item)
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
	logAward(session, target, entry, votes, item)
	announce(target, entry)
	Debug:Log("Awards", "%s -> %s (%s, %d votes, %s)", target.itemString, entry.name, entry.response, votes,
		slot and "given" or "awaiting trade")

	-- With auto trade on, the trade window opens with the winner right away (or the winner is
	-- asked by whisper to come when too far away).
	if not slot and not ALC:SameName(entry.name, ALC:PlayerName()) and ALC.Settings:GetAutoTrade() then
		local sid = session.sid
		C_Timer.After(0.5, function()
			for _, waiting in ipairs(ALC.Trades:GetPending()) do
				if waiting.sid == sid and waiting.item == item then
					local ok, message = ALC.Trades:StartTrade(waiting.id)
					if not ok and message then ALC:Print(message) end
					return
				end
			end
		end)
	end
	return true
end

--------------------------------------------------------------------------------
-- The history: dates, export, clear, restore
--------------------------------------------------------------------------------
local function csv(value)
	value = tostring(value == nil and "" or value)
	if value:find('[",\n]') then value = '"' .. value:gsub('"', '""') .. '"' end
	return value
end

-- The day an award was made, as "2026-09-30".
function Awards.DateKey(timestamp)
	return date("%Y-%m-%d", timestamp or 0)
end

-- The awards that count (not the revoked ones), oldest first. `dates` is a set of date
-- keys (true values); nil means every date.
function Awards:GetCountedLog(dates)
	local list = {}
	for _, r in ipairs(ALC.Settings:GetAwardLog()) do
		if not r.revoked and (not dates or dates[Awards.DateKey(r.time)]) then list[#list + 1] = r end
	end
	return list
end

-- The days that have awards, newest first: { { key = "2026-09-30", count = 12 }, ... }.
function Awards:GetDates()
	local byKey, list = {}, {}
	for _, r in ipairs(self:GetCountedLog()) do
		local key = Awards.DateKey(r.time)
		local day = byKey[key]
		if not day then
			day = { key = key, count = 0 }
			byKey[key] = day
			list[#list + 1] = day
		end
		day.count = day.count + 1
	end
	table.sort(list, function(a, b) return a.key > b.key end)
	return list
end

-- Awards as CSV text, one line per award, oldest first. `list` is a list of log entries
-- (default: the whole history). Returns the text and the number of awards.
function Awards:BuildExport(list)
	list = list or self:GetCountedLog()
	local sorted = {}
	for i, r in ipairs(list) do sorted[i] = r end
	table.sort(sorted, function(a, b) return (a.time or 0) < (b.time or 0) end)
	local lines = { "date,time,player,class,item,itemID,response,votes,zone,lootMaster" }
	for _, r in ipairs(sorted) do
		local name = select(1, ALC:GetItemInfo(r.itemString or r.itemID))
		lines[#lines + 1] = table.concat({
			csv(date("%Y-%m-%d", r.time or 0)), csv(date("%H:%M", r.time or 0)),
			csv(r.winner), csv(r.class), csv(name or ("item:" .. tostring(r.itemID))), csv(r.itemID),
			csv(r.responseLabel or r.response), csv(r.votes), csv(r.zone), csv(r.lm),
		}, ",")
	end
	return table.concat(lines, "\n"), #lines - 1
end

-- Removes awards from the history: those of the dates in the set, or all of them when
-- `dates` is nil. They are kept in a backup that grows with every clear until it is
-- restored or forgotten. Returns how many awards were cleared.
function Awards:ClearLog(dates)
	local log = ALC.Settings:GetAwardLog()
	local kept, cleared = {}, {}
	for _, r in ipairs(log) do
		if not dates or dates[Awards.DateKey(r.time)] then cleared[#cleared + 1] = r else kept[#kept + 1] = r end
	end
	if #cleared == 0 then return 0 end
	local backup = ALC.Settings:GetAwardBackup()
	local entries = backup and backup.entries or {}
	for _, r in ipairs(cleared) do entries[#entries + 1] = r end
	ALC.Settings:SetAwardBackup({ time = time(), entries = entries })
	for i = #log, 1, -1 do log[i] = nil end
	for i, r in ipairs(kept) do log[i] = r end
	Debug:Log("Awards", "history cleared: %d awards moved to the backup", #cleared)
	ALC.Events:Fire("ALC_AWARDS_CLEARED", #cleared)
	return #cleared
end

-- The backup of cleared awards: how many and when the last clear was, or nil.
function Awards:GetBackupInfo()
	local backup = ALC.Settings:GetAwardBackup()
	if not backup or not backup.entries or #backup.entries == 0 then return nil end
	return #backup.entries, backup.time
end

-- Puts the backed-up awards back among the present history. Returns how many.
function Awards:RestoreLog()
	local backup = ALC.Settings:GetAwardBackup()
	if not backup or not backup.entries or #backup.entries == 0 then return 0 end
	local log = ALC.Settings:GetAwardLog()
	local merged = {}
	for _, r in ipairs(backup.entries) do merged[#merged + 1] = r end
	for _, r in ipairs(log) do merged[#merged + 1] = r end
	table.sort(merged, function(a, b) return (a.time or 0) < (b.time or 0) end)
	for i = #log, 1, -1 do log[i] = nil end
	for i, r in ipairs(merged) do log[i] = r end
	local count = #backup.entries
	ALC.Settings:SetAwardBackup(nil)
	ALC.Events:Fire("ALC_AWARDS_CLEARED", 0)
	return count
end

-- Throws the backup away for good.
function Awards:ForgetBackup()
	local count = self:GetBackupInfo()
	ALC.Settings:SetAwardBackup(nil)
	return count or 0
end

-- Takes an award back (loot master): the item is open again for everybody, the log line is
-- marked as revoked and the trade queue loses the item. The item itself is NOT taken back
-- from the winner: if it was already handed out, the winner has to trade it back.
-- Returns true, the winner's name and whether the item was handed out; or false and a message.
function Awards:Revoke(item)
	item = item or 1
	local session = ALC.Sessions:GetSession()
	if not session then return false, L["There is no active session."] end
	if not session.isLM or not ALC.Council:AmLootMaster() then
		return false, L["Only the loot master can undo awards."]
	end
	local target = session.items[item]
	if not target then return false, L["That item is not in the session."] end
	if not target.winner then return false, L["That item has not been awarded."] end
	local winner = target.winner
	-- Was it handed out? Then it is not in the trade queue (it never was), else it waits there.
	local handedOut = true
	for _, entry in ipairs(ALC.Trades:GetPending()) do
		if entry.sid == session.sid and entry.item == item then handedOut = false end
	end
	local sent = ALC.Comm:SendRaid("AWARD_REVOKE", session.sid, { item = item, winner = winner, itemID = target.itemID })
	if not sent then return false, L["Could not undo the award. See /alc debug log."] end

	-- The newest log line of this award.
	local log = ALC.Settings:GetAwardLog()
	local record
	for i = #log, 1, -1 do
		local r = log[i]
		if not r.revoked and r.sid == session.sid and r.itemID == target.itemID and ALC:SameName(r.winner, winner) then
			record = r
			break
		end
	end
	if record then record.revoked, record.revokedAt = true, time() end
	pendingGive = nil

	local link = select(2, ALC:GetItemInfo(target.itemString)) or ("[item:" .. target.itemID .. "]")
	local text = format("[ALC] %s", format(L["Award of %s to %s undone."], link, winner))
	lastAnnouncement = text
	local channel = (IsInRaid() and "RAID") or (IsInGroup() and "PARTY") or nil
	if channel and ALC.Settings:GetAnnounceAwards() then
		SendChatMessage(text, channel)
	else
		ALC:Print(text)
	end
	ALC.Events:Fire("ALC_AWARDS_REVOKED", record or { winner = winner, itemID = target.itemID })
	ALC.Events:Fire("ALC_AWARDS_ANNOUNCED", text)
	Debug:Log("Awards", "award of %s to %s revoked (handed out: %s)", target.itemString, winner, tostring(handedOut))
	return true, winner, handedOut
end

-- Notes in the log that the winner now has the item (a trade went through, or the game handed it
-- over). Looks at the newest awards of that item to that player that were not delivered yet.
-- Returns the log record, or nil when there is none.
function Awards:MarkDelivered(itemID, winner)
	local log = ALC.Settings:GetAwardLog()
	for i = #log, math.max(1, #log - 200), -1 do
		local r = log[i]
		if not r.revoked and not r.deliveredAt and r.itemID == itemID and ALC:SameName(r.winner, winner) then
			r.deliveredAt = time()
			ALC.Events:Fire("ALC_AWARDS_DELIVERED", r)
			return r
		end
	end
end

-- The loot slot emptied: the game handed the item over.
function Awards:OnLootSlotCleared(slot)
	if pendingGive and pendingGive.slot == slot then
		Debug:Log("Awards", "slot %d emptied: %s was handed out", slot, pendingGive.winner)
		local _, itemID = ALC:ParseItem(pendingGive.itemString)
		if itemID then Awards:MarkDelivered(itemID, pendingGive.winner) end
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

-- Council members keep the history too: what the loot master announced is logged on their side,
-- and an undo marks the line as revoked. (The loot master logs in Awards:Award.)
local function onAwardReceived(_, item, winner)
	local session = ALC.Sessions:GetSession()
	if not session or not session.isCouncil or session.isLM then return end
	local sid = session.sid
	local target = session.items[item]
	if not target then return end
	local p = { item = item, winner = winner, itemID = target.itemID }
	local log = ALC.Settings:GetAwardLog()
	for i = #log, math.max(1, #log - 40), -1 do
		local r = log[i]
		if not r.revoked and r.sid == sid and r.item == p.item and ALC:SameName(r.winner, p.winner) then return end
	end
	local entry = ALC.Candidates:Get(p.winner, p.item)
	if not entry then
		local unit = ALC:FindUnitByName(p.winner)
		entry = { name = p.winner, class = (unit and select(2, UnitClass(unit))) or "PRIEST", response = ALC.Constants.DISENCHANT_ID }
	end
	local votes = ALC.Voting:GetVotes(p.winner, p.item)
	logAward(session, target, entry, votes, p.item)
end

local function onAwardRevokeReceived(_, item, winner)
	local session = ALC.Sessions:GetSession()
	if not session or not session.isCouncil or session.isLM then return end
	local sid, p = session.sid, { item = item, winner = winner }
	local log = ALC.Settings:GetAwardLog()
	for i = #log, 1, -1 do
		local r = log[i]
		if not r.revoked and r.sid == sid and r.item == p.item and ALC:SameName(r.winner, p.winner) then
			r.revoked, r.revokedAt = true, time()
			ALC.Events:Fire("ALC_AWARDS_REVOKED", r)
			return
		end
	end
end

function Awards:Init()
	ALC.Events.Register(self, "ALC_SESSION_ITEM_AWARDED", onAwardReceived)
	ALC.Events.Register(self, "ALC_SESSION_ITEM_REVOKED", onAwardRevokeReceived)
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

-- /alc de [set <name> | clear | award [item number]]
ALC.Commands:Register("de", function(arg)
	local sub, rest = string.match(arg or "", "^(%S*)%s*(.-)$")
	sub = string.lower(sub)
	local settings = ALC.Settings
	if sub == "set" then
		local ok = settings:SetDisenchanter(rest)
		ALC:Print(ok and (settings:GetDisenchanter() and format(L["Disenchanter: %s"], settings:GetDisenchanter()) or L["No disenchanter set."])
			or L["That is not a valid name."])
	elseif sub == "clear" then
		settings:SetDisenchanter(nil)
		ALC:Print(L["No disenchanter set."])
	elseif sub == "award" then
		local ok, message = Awards:Award(nil, tonumber(rest) or 1, true)
		if not ok then ALC:Print(message) end
	else
		local name = settings:GetDisenchanter()
		ALC:Print(name and format(L["Disenchanter: %s"], name) or L["No disenchanter set."])
		ALC:Print(L["Usage: /alc de [set <name> | clear | award [item number]]"])
	end
end, L["show or set the disenchanter, or give an item to them: /alc de award [item number]"])

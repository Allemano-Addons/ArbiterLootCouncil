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
--   ALC_AWARDS_BATCH_DONE (awarded, failed)   an AwardMany finished: how many went well, and the messages of the rest

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

-- The two places an item can go without anybody asking for it: to the disenchanter, or to the guild bank character.
-- "special" is true or "disenchant" for the disenchanter, "bank" for the guild bank.
local function specialKind(special)
	if special == "bank" then return "bank" end
	if special then return "disenchant" end
end
Awards.SpecialKind = specialKind

-- The entry for an award to the disenchanter or the guild bank (who need not have answered), or nil and a message.
local function specialEntry(kind)
	local name, response, missing
	if kind == "bank" then
		name, response = ALC.Settings:GetGuildBank(), ALC.Constants.BANK_ID
		missing = L["No guild bank is set. Set one in Settings, Loot."]
	else
		name, response = ALC.Settings:GetDisenchanter(), ALC.Constants.DISENCHANT_ID
		missing = L["No disenchanter is set. Set one in Settings, Loot master."]
	end
	if not name then return nil, missing end
	local unit = ALC:FindUnitByName(name)
	if not unit and not ALC:SameName(name, ALC:PlayerName()) then
		return nil, format(L["%s is not in your group."], name)
	end
	local class = unit and select(2, UnitClass(unit)) or nil
	return { name = name, class = class or "PRIEST", response = response }
end

local function disenchantEntry() return specialEntry("disenchant") end

-- The entry an award to the disenchanter would have, or nil and why not.
function Awards:GetDisenchantEntry()
	return disenchantEntry()
end

-- The same for the guild bank.
function Awards:GetBankEntry()
	return specialEntry("bank")
end

-- Whether the loot master can award to the disenchanter right now: true, or false and why.
function Awards:CanDisenchant()
	local entry, message = disenchantEntry()
	return entry ~= nil, message
end

-- Whether the loot master can award to the guild bank right now: true, or false and why.
function Awards:CanBank()
	local entry, message = specialEntry("bank")
	return entry ~= nil, message
end

-- Awards an item of the running session (the first when none is named) to a candidate, or, with `disenchant`,
-- to the disenchanter from the settings (true), or to the guild bank (the text "bank").
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
		entry, message = specialEntry(specialKind(disenchant))
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
	Awards:CheckLogLimit()
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
-- Award many (for an addon built on ALC: Soft Reserve hands out all its winners at once)
--------------------------------------------------------------------------------
local WAIT_STEP = 0.3 -- seconds between two awards of a batch, and between looks at the loot slot of the last one
local batch           -- { sid, queue, awarded, failed } while a batch runs

-- Checks a list of awards without doing anything: { { item = 2, name = "Veyra Moo" }, { item = 3, disenchant = true }, ... }.
-- Returns true, or false and a message. Nothing is awarded unless every entry can be.
function Awards:CheckMany(list)
	local session = ALC.Sessions:GetSession()
	if not session then return false, L["There is no active session."] end
	if not session.isLM or not ALC.Council:AmLootMaster() then return false, L["Only the loot master can award items."] end
	if session.paused then return false, L["The session is paused. Resume it to award."] end
	if type(list) ~= "table" or #list == 0 then return false, L["There is nothing to award."] end
	local seen = {}
	for _, entry in ipairs(list) do
		local item = entry.item
		local target = type(item) == "number" and session.items[item]
		if not target then return false, L["That item is not in the session."] end
		if target.winner then return false, L["That item has already been awarded."] end
		if seen[item] then return false, L["An item is in the list twice."] end
		seen[item] = true
		if entry.disenchant then
			local ok, message
			if specialKind(entry.disenchant) == "bank" then ok, message = Awards:CanBank() else ok, message = Awards:CanDisenchant() end
			if not ok then return false, message end
		else
			local candidate = ALC.Candidates:Get(entry.name, item)
			if not candidate then return false, format(L["%s has not answered."], tostring(entry.name)) end
			if candidate.response == "PASS" then return false, format(L["%s passed."], candidate.name) end
		end
	end
	return true
end

function Awards:IsBatchRunning() return batch ~= nil end

local function finishBatch()
	local done = batch
	batch = nil
	for _, message in ipairs(done.failed) do ALC:Print(message) end
	ALC.Events:Fire("ALC_AWARDS_BATCH_DONE", done.awarded, done.failed)
end

-- One award at a time: GiveMasterLoot is followed by a wait for the loot slot to empty, and only one such wait is
-- tracked, so the next award starts when the last item has been handed over (or the wait ran out).
local function batchStep()
	if not batch then return end
	local session = ALC.Sessions:GetSession()
	if not session or session.sid ~= batch.sid then
		batch.failed[#batch.failed + 1] = L["The session ended before everything was awarded."]
		finishBatch()
		return
	end
	if #batch.queue == 0 then
		finishBatch()
		return
	end
	if pendingGive then
		C_Timer.After(WAIT_STEP, batchStep)
		return
	end
	local entry = table.remove(batch.queue, 1)
	local ok, message = Awards:Award(entry.name, entry.item, entry.disenchant)
	if ok then
		batch.awarded = batch.awarded + 1
	else
		batch.failed[#batch.failed + 1] = message or L["An award failed."]
	end
	C_Timer.After(WAIT_STEP, batchStep)
end

-- Awards a list of items in one go (the same as Award for each, one after the other). Returns true and how many were
-- queued, or false and a message. ALC_AWARDS_BATCH_DONE (awarded, failed) fires when the last one is done.
function Awards:AwardMany(list)
	local ok, message = self:CheckMany(list)
	if not ok then return false, message end
	if batch then return false, L["A batch of awards is already running."] end
	local session = ALC.Sessions:GetSession()
	batch = { sid = session.sid, queue = {}, awarded = 0, failed = {} }
	for i, entry in ipairs(list) do
		batch.queue[i] = { item = entry.item, name = entry.name, disenchant = specialKind(entry.disenchant) == "bank" and "bank" or (entry.disenchant and true or false) }
	end
	batchStep()
	return true, #list
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

-- Keeps the newest `keep` awards and moves the older ones to the backup (a clear that can be taken back, see RestoreLog).
-- Returns how many were moved.
function Awards:TrimLog(keep)
	keep = tonumber(keep)
	if not keep or keep < 0 then return 0 end
	local log = ALC.Settings:GetAwardLog()
	local extra = #log - math.floor(keep)
	if extra <= 0 then return 0 end
	local backup = ALC.Settings:GetAwardBackup()
	local entries = backup and backup.entries or {}
	for i = 1, extra do entries[#entries + 1] = log[i] end
	ALC.Settings:SetAwardBackup({ time = time(), entries = entries })
	local kept = {}
	for i = extra + 1, #log do kept[#kept + 1] = log[i] end
	for i = #log, 1, -1 do log[i] = nil end
	for i, r in ipairs(kept) do log[i] = r end
	Debug:Log("Awards", "history trimmed: %d old awards moved to the backup, %d kept", extra, #kept)
	ALC.Events:Fire("ALC_AWARDS_CLEARED", extra)
	return extra
end

-- When the log has grown to the limit the loot master chose (Settings), says so once per session, so it can be exported
-- and trimmed before it gets long. Returns true when the reminder was shown.
local reminded = false
function Awards:CheckLogLimit()
	local limit = ALC.Settings:GetLogReminder()
	local count = #ALC.Settings:GetAwardLog()
	if limit == 0 or count < limit or reminded then return false end
	reminded = true
	ALC:Print(L["The award log has %d awards (you asked to be reminded at %d). Export it from Award history, then trim it: /alc log trim <how many to keep>. The older awards go to a backup that can be restored."], count, limit)
	return true
end
function Awards:ResetLogReminder() reminded = false end

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

--------------------------------------------------------------------------------
-- What happened to an item after it was awarded: returned, traded on, still to trade
--------------------------------------------------------------------------------
local PASS_WINDOW = 7 * 86400 -- the newest awards of the last week are the ones that are matched

-- Whether the item of this award still waits in the trade queue.
local function awaitingTrade(entry)
	if not (ALC.Trades and ALC.Trades.GetPending) then return false end
	for _, waiting in ipairs(ALC.Trades:GetPending()) do
		if waiting.itemID == entry.itemID and ALC:SameName(waiting.winner, entry.winner) then return true end
	end
	return false
end

-- What the history says about an award: "returned" (the winner gave it back), "traded" (the winner traded it on, entry.tradedTo
-- says to whom), "awaiting" (still to be traded to the winner), "delivered" or nil. And a short text for it.
function Awards.StatusOf(entry)
	if entry.revoked then return "revoked", L["Revoked"] end
	if entry.returnedAt then return "returned", L["Returned"] end
	if entry.tradedTo then return "traded", string.format(L["Traded to %s"], entry.tradedTo) end
	if not entry.deliveredAt and awaitingTrade(entry) then return "awaiting", L["Awaiting trade"] end
	if entry.deliveredAt then return "delivered", L["Delivered"] end
end

-- The newest award of the last week of this item to this player that has not been returned, traded on or taken back.
function Awards:FindOpenAward(winner, itemID)
	local log = ALC.Settings:GetAwardLog()
	local oldest = time() - PASS_WINDOW
	for i = #log, math.max(1, #log - 200), -1 do
		local r = log[i]
		if (r.time or 0) < oldest then break end
		if not r.revoked and not r.returnedAt and not r.tradedTo and r.itemID == itemID and ALC:SameName(r.winner, winner) then return r end
	end
end

-- Says in the chat where an item went after the award (the same way the awards are announced).
local function announceTransfer(itemID, from, to)
	local link = select(2, ALC:GetItemInfo(itemID)) or ("item:" .. itemID)
	local text = format("[ALC] %s", format(L["%s traded %s on to %s."], from, link, to))
	local channel = (IsInRaid and IsInRaid() and "RAID") or (IsInGroup and IsInGroup() and "PARTY") or nil
	if channel and SendChatMessage and ALC.Settings:GetAnnounceAwards() then
		SendChatMessage(text, channel)
	else
		ALC:Print(text)
	end
end

-- Tells the council that an award changed afterwards ("returned" or "traded"). The loot master only.
local function notifyCouncil(record, kind, to)
	local targets = ALC.Settings:GetCouncil()
	if #targets == 0 then return end
	ALC.Comm:SendCouncil(targets, "AWARD_NOTE", nil, { itemID = record.itemID, winner = record.winner, kind = kind, to = to, time = time() })
end

-- The loot master saw the winner give the item back: the award is marked returned and the council is told.
function Awards:NoteReturned(record)
	if not record then return end
	record.returnedAt = record.returnedAt or time()
	notifyCouncil(record, "returned")
	ALC.Events:Fire("ALC_AWARDS_UPDATED", record)
end

-- A winner says they traded the item on (or the loot master did it themselves): the award keeps its winner, and the
-- history says where the item went. Returns true when an award was found.
function Awards:NoteTradedOn(winner, itemID, to)
	if ALC:SameName(winner, to) then return false end
	local record = self:FindOpenAward(winner, itemID)
	if not record then return false end
	record.tradedTo, record.tradedAt = to, time()
	announceTransfer(itemID, winner, to)
	notifyCouncil(record, "traded", to)
	ALC.Events:Fire("ALC_AWARDS_UPDATED", record)
	return true
end

-- The loot master hears from a winner that the item was passed on.
local function onItemPassed(_, sender, _, p)
	if not ALC.Council:AmLootMaster() then return end
	if ALC.Council:IsLootMaster(p.to) then return end -- given back to the loot master: seen by the trade itself
	Awards:NoteTradedOn(sender, p.itemID, p.to)
end

-- A council member hears it from the loot master and marks its own copy of the log.
local function onAwardNote(_, _, _, p)
	local log = ALC.Settings:GetAwardLog()
	for i = #log, math.max(1, #log - 200), -1 do
		local r = log[i]
		if not r.revoked and not r.returnedAt and not r.tradedTo and r.itemID == p.itemID and ALC:SameName(r.winner, p.winner) then
			if p.kind == "returned" then r.returnedAt = p.time or time() else r.tradedTo, r.tradedAt = p.to, p.time or time() end
			ALC.Events:Fire("ALC_AWARDS_UPDATED", r)
			return
		end
	end
end

-- What this player won, so that a trade of such an item to somebody else can be told to the loot master.
local WINS_KEEP = 40
local function myWins()
	local g = ALC.Settings:GetDB().global
	g.myWins = g.myWins or {}
	return g.myWins
end

local function recordMyWin(_, item, winner)
	if not winner or not ALC:SameName(winner, ALC:PlayerName()) then return end
	local session = ALC.Sessions:GetSession()
	local target = session and session.items[item]
	if not target then return end
	local wins = myWins()
	wins[#wins + 1] = { itemID = target.itemID, time = time() }
	while #wins > WINS_KEEP do table.remove(wins, 1) end
end

-- Called when a trade of ours went through: an item we won that left to somebody who is not the loot master is told to the
-- loot master (or noted right away when we are the loot master).
function Awards:ReportPassedOn(itemID, partner)
	if not partner then return false end
	local wins = myWins()
	local oldest = time() - PASS_WINDOW
	for i = #wins, 1, -1 do
		local w = wins[i]
		if w.itemID == itemID and w.time >= oldest then
			table.remove(wins, i)
			if ALC.Council:AmLootMaster() then
				return self:NoteTradedOn(ALC:PlayerName(), itemID, partner)
			end
			local lm = ALC.Council:GetLootMaster()
			if not lm or ALC:SameName(lm, partner) then return false end -- given back to the loot master: no news
			return ALC.Comm:SendWhisper(lm, "ITEM_PASSED", nil, { itemID = itemID, to = partner }) and true or false
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- History sync: the loot master's awards to the council, so nobody has gaps
--------------------------------------------------------------------------------
local SYNC_REPLY_WAIT = 30 -- seconds: one reply per council member in this time
local lastSyncReply = {}

local function hexOf(color)
	if type(color) == "string" and string.match(color, "^%x%x%x%x%x%x$") then return color end
	if type(color) == "table" then
		return string.format("%02x%02x%02x", math.floor((color[1] or 0) * 255 + 0.5), math.floor((color[2] or 0) * 255 + 0.5), math.floor((color[3] or 0) * 255 + 0.5))
	end
end

-- The payload of LOG_SYNC: the newest awards of the last `days` days (at most MAX_SYNC_ENTRIES), newest first.
function Awards:BuildSync(days)
	local log = ALC.Settings:GetAwardLog()
	local oldest = time() - (days or 30) * 86400
	local list = {}
	for i = 1, #log do
		local r = log[i]
		if r.time and r.time >= oldest and r.winner and r.itemID and r.response then list[#list + 1] = r end
	end
	table.sort(list, function(a, b) return a.time > b.time end)
	local entries = {}
	for i = 1, math.min(#list, ALC.Constants.MAX_SYNC_ENTRIES) do
		local r = list[i]
		local zone = type(r.zone) == "string" and r.zone ~= "" and string.sub(r.zone, 1, ALC.Constants.MAX_HISTORY_ZONE) or nil
		entries[#entries + 1] = {
			itemID = r.itemID, winner = r.winner, class = r.class, response = r.response,
			label = string.sub(r.responseLabel ~= nil and r.responseLabel ~= "" and r.responseLabel or "?", 1, ALC.Constants.MAX_RESPONSE_LABEL),
			color = hexOf(r.responseColor), time = r.time, zone = zone, votes = math.min(99, math.max(0, r.votes or 0)),
			returnedAt = r.returnedAt, tradedTo = r.tradedTo, revoked = r.revoked and true or nil,
		}
	end
	return { entries = entries }
end

-- The loot master sends the history to council members (all reachable ones, or just `only`). Returns how many.
function Awards:PushLogToCouncil(only, days)
	if not ALC.Council:AmLootMaster() then return 0 end
	local payload = self:BuildSync(days or 90)
	local sent = 0
	local targets = only and { only } or ALC.Settings:GetCouncil()
	for _, name in ipairs(targets) do
		if not ALC:SameName(name, ALC:PlayerName()) and ALC.Comm:SendWhisper(name, "LOG_SYNC", nil, payload) then sent = sent + 1 end
	end
	return sent
end

local function onSyncRequest(_, sender, _, p)
	if not ALC.Council:AmLootMaster() then return end
	local now = GetTime()
	if lastSyncReply[sender] and now - lastSyncReply[sender] < SYNC_REPLY_WAIT then return end
	lastSyncReply[sender] = now
	ALC.Comm:SendWhisper(sender, "LOG_SYNC", nil, Awards:BuildSync(p.days))
end

-- A council member puts the loot master's awards into its own log: new ones are added, the ones it has already are only
-- updated (returned, traded on, taken back). The same award is the same winner and item within three minutes.
local SAME_AWARD_SECONDS = 180
function Awards:MergeLog(entries)
	local log = ALC.Settings:GetAwardLog()
	local added, updated = 0, 0
	local used = {}
	for _, e in ipairs(entries) do
		local match
		for i = #log, 1, -1 do
			local r = log[i]
			if not used[r] and r.itemID == e.itemID and r.time and math.abs(r.time - e.time) <= SAME_AWARD_SECONDS and ALC:SameName(r.winner, e.winner) then
				match = r
				break
			end
		end
		if match then
			used[match] = true
			local changed
			if e.returnedAt and not match.returnedAt then match.returnedAt, changed = e.returnedAt, true end
			if e.tradedTo and not match.tradedTo then match.tradedTo, changed = e.tradedTo, true end
			if e.revoked and not match.revoked then match.revoked, changed = true, true end
			if changed then updated = updated + 1 end
		else
			local color
			if e.color then
				color = { tonumber(string.sub(e.color, 1, 2), 16) / 255, tonumber(string.sub(e.color, 3, 4), 16) / 255, tonumber(string.sub(e.color, 5, 6), 16) / 255 }
			end
			local record = {
				item = 0, itemID = e.itemID, itemString = "item:" .. e.itemID, winner = e.winner, class = e.class or "WARRIOR",
				response = e.response, responseLabel = e.label, responseColor = color, votes = e.votes or 0, sid = "sync",
				time = e.time, zone = e.zone or "", returnedAt = e.returnedAt, tradedTo = e.tradedTo, revoked = e.revoked,
			}
			log[#log + 1] = record
			used[record] = true
			added = added + 1
		end
	end
	if added > 0 then
		table.sort(log, function(a, b) return (a.time or 0) < (b.time or 0) end)
	end
	if added > 0 or updated > 0 then ALC.Events:Fire("ALC_AWARDS_UPDATED") end
	return added, updated
end

local function onLogSync(_, _, _, p)
	local added, updated = Awards:MergeLog(p.entries)
	if added > 0 or updated > 0 then
		Debug:Log("Awards", "history from the loot master: %d new, %d updated", added, updated)
	end
end

-- A council member asks the loot master for the awards of the last days (when a session starts).
function Awards:RequestLogSync()
	if ALC.Council:AmLootMaster() or not ALC.Council:AmCouncil() then return false end
	local lm = ALC.Council:GetLootMaster()
	if not lm then return false end
	local days = math.max(30, ALC.Settings:GetRecentDays())
	return ALC.Comm:SendWhisper(lm, "LOG_SYNC_REQUEST", nil, { days = days }) and true or false
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
local function onAwardReceived(_, item, winner, response)
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
		entry = { name = p.winner, class = (unit and select(2, UnitClass(unit))) or "PRIEST",
			response = response == ALC.Constants.BANK_ID and ALC.Constants.BANK_ID or ALC.Constants.DISENCHANT_ID }
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
	-- Settings (Loot master): when to be reminded to export the log, and a way to trim it
	ALC.RegisterSettingsSection({
		id = "ALC-award-log", name = L["Award log"],
		rows = {
			{ tab = "lm", type = "choice", label = L["Remind me to export the award log at"],
				options = { { label = L["Never"], value = 0 }, { label = "500", value = 500 }, { label = "1000", value = 1000 }, { label = "2000", value = 2000 } },
				get = function() return ALC.Settings:GetLogReminder() end,
				set = function(value) ALC.Settings:SetLogReminder(value) Awards:ResetLogReminder() end },
			{ tab = "lm", type = "action", label = L["Keep the newest 500 awards"], confirm = L["Click again: older awards go to the backup"],
				onClick = function()
					ALC:Print(L["%d older awards moved to the backup (Award history can restore them)."], Awards:TrimLog(500))
				end },
		},
	})
	-- one handler per event and object: the two things done when an award arrives share it
	ALC.Events.Register(self, "ALC_SESSION_ITEM_AWARDED", function(event, item, winner, response)
		onAwardReceived(event, item, winner, response)
		recordMyWin(event, item, winner)
	end)
	ALC.Events.Register(self, "ALC_COMM_ITEM_PASSED", onItemPassed)
	ALC.Events.Register(self, "ALC_COMM_LOG_SYNC_REQUEST", onSyncRequest)
	ALC.Events.Register(self, "ALC_COMM_LOG_SYNC", onLogSync)
	-- a council member fills the gaps of its history from the loot master when a session starts
	ALC.Events.Register(self, "ALC_SESSION_STARTED", function(_, session, restored)
		if restored or not session or session.isLM then return end
		C_Timer.After(3, function() Awards:RequestLogSync() end)
	end)
	ALC.Events.Register(self, "ALC_COMM_AWARD_NOTE", onAwardNote)
	ALC.Events.Register(self, "ALC_SESSION_ITEM_REVOKED", onAwardRevokeReceived)
	self:RegisterEvent("LOOT_OPENED", function() lootOpen = true end)
	self:RegisterEvent("LOOT_CLOSED", function() lootOpen = false end)
	self:RegisterEvent("LOOT_SLOT_CLEARED", function(_, slot) Awards:OnLootSlotCleared(slot) end)
end

-- Test hooks: the loot window state normally comes from the game's events.
function Awards:SetLootOpen(open) lootOpen = open and true or false end

ALC.Commands:Register("log", function(arg)
	-- /alc log           how many awards the log holds
	-- /alc log trim [n]  keep the newest n (500 when not said), the rest goes to the backup
	local sub, rest = string.match(arg or "", "^(%S*)%s*(.-)$")
	sub = string.lower(sub)
	local count = #ALC.Settings:GetAwardLog()
	if sub == "trim" then
		local keep = tonumber(rest) or 500
		ALC:Print(L["%d older awards moved to the backup (Award history can restore them)."], Awards:TrimLog(keep))
	else
		local limit = ALC.Settings:GetLogReminder()
		ALC:Print(L["The award log holds %d awards. Reminder at: %s. /alc log trim <how many to keep> moves the older ones to a backup."], count, limit == 0 and L["never"] or tostring(limit))
	end
end, L["the award log (trim: keep the newest awards)"])

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

-- /alc bank [set <name> | clear | award [item number]]
ALC.Commands:Register("bank", function(arg)
	local sub, rest = string.match(arg or "", "^(%S*)%s*(.-)$")
	sub = string.lower(sub)
	local settings = ALC.Settings
	if sub == "set" then
		local ok = settings:SetGuildBank(rest)
		ALC:Print(ok and (settings:GetGuildBank() and format(L["Guild bank: %s"], settings:GetGuildBank()) or L["No guild bank set."])
			or L["That is not a valid name."])
	elseif sub == "clear" then
		settings:SetGuildBank(nil)
		ALC:Print(L["No guild bank set."])
	elseif sub == "award" then
		local ok, message = Awards:Award(nil, tonumber(rest) or 1, "bank")
		if not ok then ALC:Print(message) end
	else
		local name = settings:GetGuildBank()
		ALC:Print(name and format(L["Guild bank: %s"], name) or L["No guild bank set."])
		ALC:Print(L["Usage: /alc bank [set <name> | clear | award [item number]]"])
	end
end, L["show or set the guild bank character, or give an item to it: /alc bank award [item number]"])

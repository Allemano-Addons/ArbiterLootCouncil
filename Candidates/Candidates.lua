-- Candidates: who wants each item, and with what.
--
-- The loot master builds one list per item of the session from the RESPONSE messages it
-- receives and sends every change to the council (only) as CANDIDATE_UPDATE. Council
-- members keep the lists from those updates; everybody else has none. A player who
-- answered Pass is a candidate with the PASS response, so windows can count them.
-- Items are numbered as in the session (1 = the first); functions take the item number
-- as their last argument and mean item 1 when it is left out.
--
-- Events:
--   ALC_CANDIDATES_CHANGED ()   a list changed or all were cleared

local ALC = ALC
local L = ALC.L

local Debug = ALC.Debug

local strlower = string.lower

local Candidates = {}
ALC.Candidates = Candidates

local lists = {} -- item number -> array of { item, name, class, response, gear }

local function listOf(item)
	local list = lists[item]
	if not list then
		list = {}
		lists[item] = list
	end
	return list
end

local function copyGear(gear)
	local copy = {}
	for i, itemString in ipairs(gear or {}) do copy[i] = itemString end
	return copy
end

local function copyEntry(entry, item)
	return {
		item = item or entry.item, name = entry.name, class = entry.class, response = entry.response, gear = copyGear(entry.gear),
		note = entry.note, rank = entry.rank, rankIndex = entry.rankIndex,
	}
end

local function sameGear(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

local function findIndex(list, name)
	for i, entry in ipairs(list) do
		if ALC:SameName(entry.name, name) then return i end
	end
end

-- Every candidate of every item, item by item, as one flat array (for saving and snapshots).
local function flatten()
	local flat = {}
	local items = {}
	for item in pairs(lists) do items[#items + 1] = item end
	table.sort(items)
	for _, item in ipairs(items) do
		for _, entry in ipairs(lists[item]) do flat[#flat + 1] = copyEntry(entry, item) end
	end
	return flat
end

-- The loot master keeps the lists so they survive a /reload (see Sessions).
local function persist()
	local session = ALC.Sessions:GetSession()
	if session and session.isLM then
		ALC.Settings:GetSessionStore().candidates = flatten()
	end
end

local function changed()
	persist()
	ALC.Events:Fire("ALC_CANDIDATES_CHANGED")
end

-- Adds or replaces a candidate of an item. Returns true when something actually changed.
local function upsert(item, entry)
	local list = listOf(item)
	local index = findIndex(list, entry.name)
	if index then
		local old = list[index]
		if old.response == entry.response and old.class == entry.class and sameGear(old.gear, entry.gear)
			and old.note == entry.note and old.rank == entry.rank and old.rankIndex == entry.rankIndex then
			return false
		end
		list[index] = copyEntry(entry, item)
	else
		list[#list + 1] = copyEntry(entry, item)
	end
	changed()
	return true
end

local function clear()
	ALC.Settings:GetSessionStore().candidates = nil
	if next(lists) == nil then return end
	lists = {}
	changed()
end

-- Replaces everything with a flat array (a snapshot, or what the loot master saved).
local function load(flat)
	lists = {}
	for _, entry in ipairs(flat or {}) do
		-- Lists saved by version 0.1 have no item number: they are for the only item.
		local item = entry.item or 1
		local list = listOf(item)
		list[#list + 1] = copyEntry(entry, item)
	end
end

--------------------------------------------------------------------------------
-- Getters
--------------------------------------------------------------------------------
function Candidates:GetList(item)
	local copy = {}
	local item_ = item or 1
	for i, entry in ipairs(lists[item_] or {}) do copy[i] = copyEntry(entry, item_) end
	return copy
end

function Candidates:Get(name, item)
	item = item or 1
	local list = lists[item] or {}
	local index = findIndex(list, name)
	return index and copyEntry(list[index], item) or nil
end

-- How many answered an item, how many of those passed, and how many in the group are silent.
function Candidates:GetCounts(item)
	local list = lists[item or 1] or {}
	local passed = 0
	for _, entry in ipairs(list) do
		if entry.response == "PASS" then passed = passed + 1 end
	end
	local groupSize = #ALC.Comm.GetGroupNames()
	return {
		responded = #list,
		passed = passed,
		wanting = #list - passed,
		silent = math.max(0, groupSize - #list),
	}
end

-- How many items of the session this player answered (for a "3 of 8 answered" line).
function Candidates:CountAnsweredBy(name)
	local count = 0
	for _, list in pairs(lists) do
		if findIndex(list, name) then count = count + 1 end
	end
	return count
end

--------------------------------------------------------------------------------
-- Loot master: RESPONSE in, CANDIDATE_UPDATE out
--------------------------------------------------------------------------------
local function send(session, item, entry)
	ALC.Comm:SendCouncil(ALC.Council:GetReachableCouncil(), "CANDIDATE_UPDATE", session.sid, copyEntry(entry, item))
end

local function onResponse(_, sender, _, p)
	local session = ALC.Sessions:GetSession()
	if not session or not session.isLM then return end
	if not ALC.Sessions:IsItemOpen(p.item) then return end -- already awarded

	local unit = ALC:FindUnitByName(sender)
	local class = unit and select(2, UnitClass(unit))
	if not class then
		Debug:Warn("Candidates", "no class for %s, response ignored", sender)
		return
	end

	local rank, rankIndex = ALC:GetGuildRank(unit)
	local entry = { name = sender, class = class, response = p.response, gear = p.gear, note = p.note, rank = rank, rankIndex = rankIndex }
	if not upsert(p.item, entry) then return end -- nothing new: council already knows
	Debug:Log("Candidates", "item %d, %s: %s", p.item, sender, p.response)
	send(session, p.item, entry)
end

-- Loot master: changes a candidate's answer (right-click menu). The council gets the same
-- CANDIDATE_UPDATE as for an answer from the player. Returns true, or false and a message.
function Candidates:SetResponse(name, response, item)
	item = item or 1
	local session = ALC.Sessions:GetSession()
	if not session or not session.isLM then return false, L["Only the loot master can do that."] end
	local list = lists[item] or {}
	local index = findIndex(list, name)
	if not index then return false, L["That player is not a candidate."] end
	if not ALC.Sessions:HasResponse(response) then return false, L["That is not a valid answer."] end
	if not ALC.Sessions:IsItemOpen(item) then return false, L["That item has already been awarded."] end
	local entry = copyEntry(list[index], item)
	entry.response = response
	if not upsert(item, entry) then return true end
	Debug:Log("Candidates", "item %d, %s: %s (set by the loot master)", item, entry.name, response)
	send(session, item, entry)
	return true
end

--------------------------------------------------------------------------------
-- Council: CANDIDATE_UPDATE in
--------------------------------------------------------------------------------
local function onUpdate(_, _, _, p)
	local session = ALC.Sessions:GetSession()
	if not session or not session.isCouncil then return end
	upsert(p.item, p)
end

--------------------------------------------------------------------------------
-- Recovery
--------------------------------------------------------------------------------
local function onSnapshotBuild(_, payload, requester, isCouncil)
	if isCouncil then payload.candidates = flatten() end
	local mine = {}
	for item, list in pairs(lists) do
		local index = findIndex(list, requester)
		if index then mine[#mine + 1] = { item = item, response = list[index].response } end
	end
	table.sort(mine, function(a, b) return a.item < b.item end)
	if #mine > 0 then payload.yourResponses = mine end
end

local function onSnapshot(_, p, session)
	load(session.isCouncil and p.candidates or nil)
	changed()
end

function Candidates:Init()
	local register = ALC.Events.Register
	register(self, "ALC_COMM_RESPONSE", onResponse)
	register(self, "ALC_COMM_CANDIDATE_UPDATE", onUpdate)
	register(self, "ALC_SESSION_SNAPSHOT_BUILD", onSnapshotBuild)
	register(self, "ALC_SESSION_SNAPSHOT", onSnapshot)
	register(self, "ALC_SESSION_STARTED", function(_, session, restored)
		if not restored then
			clear()
		elseif session.isLM then
			-- Our own session came back after a reload: so do its lists.
			load(ALC.Settings:GetSessionStore().candidates)
			changed()
		end
	end)
	register(self, "ALC_SESSION_ENDED", clear)
end

-- Until the voting window exists: /alc candidates prints the list of item 1 (or of item n).
ALC.Commands:Register("candidates", function(arg)
	local session = ALC.Sessions:GetSession()
	if not session then
		ALC:Print(L["No active session."])
		return
	end
	if not session.isCouncil then
		ALC:Print(L["Only the council sees the candidates."])
		return
	end
	local item = tonumber(arg) or 1
	local entries = Candidates:GetList(item)
	if #entries == 0 then
		ALC:Print(L["No responses yet."])
	end
	for _, entry in ipairs(entries) do
		local gear = {}
		for _, itemString in ipairs(entry.gear) do
			gear[#gear + 1] = select(2, ALC:GetItemInfo(itemString)) or itemString
		end
		local className = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[entry.class]) or entry.class
		ALC:Print("%s (%s): %s%s", entry.name, className, ALC.Responses:GetLabel(entry.response),
			#gear > 0 and (" - " .. table.concat(gear, ", ")) or "")
	end
	local counts = Candidates:GetCounts(item)
	ALC:Print(L["%d responded (%d passed), %d not responded."], counts.responded, counts.passed, counts.silent)
end, L["list the candidates of an item (council): /alc candidates [item number]"])

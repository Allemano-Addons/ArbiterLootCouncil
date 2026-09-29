-- Candidates: who wants the item, and with what.
--
-- The loot master builds the list from the RESPONSE messages it receives and sends
-- every change to the council (only) as CANDIDATE_UPDATE. Council members keep the
-- list from those updates; everybody else has no list. A player who answered Pass is
-- a candidate with the PASS response, so windows can count them.
--
-- Events:
--   ALC_CANDIDATES_CHANGED ()   the list changed or was cleared

local ALC = ALC
local L = ALC.L

local Debug = ALC.Debug

local strlower = string.lower

local Candidates = {}
ALC.Candidates = Candidates

local list = {} -- array of { name, class, response, gear }

local function copyGear(gear)
	local copy = {}
	for i, itemString in ipairs(gear or {}) do copy[i] = itemString end
	return copy
end

local function copyEntry(entry)
	return { name = entry.name, class = entry.class, response = entry.response, gear = copyGear(entry.gear) }
end

local function sameGear(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

local function findIndex(name)
	for i, entry in ipairs(list) do
		if ALC:SameName(entry.name, name) then return i end
	end
end

-- The loot master keeps the list so it survives a /reload (see Sessions).
local function persist()
	local session = ALC.Sessions:GetSession()
	if session and session.isLM then
		local saved = {}
		for i, entry in ipairs(list) do saved[i] = copyEntry(entry) end
		ALC.Settings:GetSessionStore().candidates = saved
	end
end

local function changed()
	persist()
	ALC.Events:Fire("ALC_CANDIDATES_CHANGED")
end

-- Adds or replaces a candidate. Returns true when something actually changed.
local function upsert(entry)
	local index = findIndex(entry.name)
	if index then
		local old = list[index]
		if old.response == entry.response and old.class == entry.class and sameGear(old.gear, entry.gear) then
			return false
		end
		list[index] = copyEntry(entry)
	else
		list[#list + 1] = copyEntry(entry)
	end
	changed()
	return true
end

local function clear()
	ALC.Settings:GetSessionStore().candidates = nil
	if #list == 0 then return end
	for i = #list, 1, -1 do list[i] = nil end
	changed()
end

--------------------------------------------------------------------------------
-- Getters
--------------------------------------------------------------------------------
function Candidates:GetList()
	local copy = {}
	for i, entry in ipairs(list) do copy[i] = copyEntry(entry) end
	return copy
end

function Candidates:Get(name)
	local index = findIndex(name)
	return index and copyEntry(list[index]) or nil
end

-- How many answered, how many of those passed, and how many in the group are silent.
function Candidates:GetCounts()
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

--------------------------------------------------------------------------------
-- Loot master: RESPONSE in, CANDIDATE_UPDATE out
--------------------------------------------------------------------------------
local function isConnected(name)
	local unit = ALC:FindUnitByName(name)
	return unit ~= nil and UnitIsConnected(unit) ~= false
end

-- Council members who can receive an update: us, and the ones in the group and online.
local function recipients(session)
	local names = {}
	local me = ALC:PlayerName()
	for _, name in ipairs(session.council) do
		if ALC:SameName(name, me) or (ALC.Comm:IsGroupMember(name) and isConnected(name)) then
			names[#names + 1] = name
		end
	end
	return names
end

local function onResponse(_, sender, _, p)
	local session = ALC.Sessions:GetSession()
	if not session or not session.isLM then return end

	local unit = ALC:FindUnitByName(sender)
	local class = unit and select(2, UnitClass(unit))
	if not class then
		Debug:Warn("Candidates", "no class for %s, response ignored", sender)
		return
	end

	local entry = { name = sender, class = class, response = p.response, gear = p.gear }
	if not upsert(entry) then return end -- nothing new: council already knows
	Debug:Log("Candidates", "%s: %s", sender, p.response)
	ALC.Comm:SendCouncil(recipients(session), "CANDIDATE_UPDATE", session.sid, copyEntry(entry))
end

--------------------------------------------------------------------------------
-- Council: CANDIDATE_UPDATE in
--------------------------------------------------------------------------------
local function onUpdate(_, _, _, p)
	local session = ALC.Sessions:GetSession()
	if not session or not session.isCouncil then return end
	upsert(p)
end

--------------------------------------------------------------------------------
-- Recovery
--------------------------------------------------------------------------------
local function onSnapshotBuild(_, payload, requester, isCouncil)
	if isCouncil then payload.candidates = Candidates:GetList() end
	local mine = Candidates:Get(requester)
	if mine then payload.yourResponse = mine.response end
end

local function onSnapshot(_, p, session)
	for i = #list, 1, -1 do list[i] = nil end
	if session.isCouncil and p.candidates then
		for _, entry in ipairs(p.candidates) do list[#list + 1] = copyEntry(entry) end
	end
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
			-- Our own session came back after a reload: so does its list.
			for i = #list, 1, -1 do list[i] = nil end
			for _, entry in ipairs(ALC.Settings:GetSessionStore().candidates or {}) do
				list[#list + 1] = copyEntry(entry)
			end
			changed()
		end
	end)
	register(self, "ALC_SESSION_ENDED", clear)
end

-- Until the voting window exists: /alc candidates prints the list.
ALC.Commands:Register("candidates", function()
	local session = ALC.Sessions:GetSession()
	if not session then
		ALC:Print(L["No active session."])
		return
	end
	if not session.isCouncil then
		ALC:Print(L["Only the council sees the candidates."])
		return
	end
	local entries = Candidates:GetList()
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
	local counts = Candidates:GetCounts()
	ALC:Print(L["%d responded (%d passed), %d not responded."], counts.responded, counts.passed, counts.silent)
end, L["list the candidates (council)"])

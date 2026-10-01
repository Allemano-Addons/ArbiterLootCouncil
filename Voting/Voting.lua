-- Voting: council votes on the candidates. One vote per council member and item; it
-- can be moved to another candidate or taken back.
--
-- The loot master is the authority: it receives VOTE, keeps who voted for whom and
-- sends the new count of every affected candidate to the council as VOTE_UPDATE.
-- Council members show what the loot master last told them; they never count
-- other people's votes themselves. Votes go only to the council.
-- Items are numbered as in the session (1 = the first); functions take the item number
-- as their last argument and mean item 1 when it is left out.
--
-- Events:
--   ALC_VOTING_CHANGED ()   the counts or our own votes changed, or were cleared

local ALC = ALC
local L = ALC.L

local Debug = ALC.Debug

local strlower = string.lower

local Voting = {}
ALC.Voting = Voting

-- What everybody on the council sees: item -> lowercase candidate -> { name, voters = { ... } }.
local tally = {}
local myVotes = {} -- item -> the candidate we voted for

-- Loot master only: item -> lowercase voter -> { voter, candidate }.
local voterOf = {}

local function copyList(list)
	local copy = {}
	for i, v in ipairs(list) do copy[i] = v end
	return copy
end

local function isMe(name)
	return ALC:SameName(name, ALC:PlayerName())
end

local function changed()
	ALC.Events:Fire("ALC_VOTING_CHANGED")
end

local function tallyOf(item)
	local t = tally[item]
	if not t then
		t = {}
		tally[item] = t
	end
	return t
end

local function votersOfItem(item)
	local v = voterOf[item]
	if not v then
		v = {}
		voterOf[item] = v
	end
	return v
end

local function recomputeMine()
	myVotes = {}
	for item, byCandidate in pairs(tally) do
		for _, entry in pairs(byCandidate) do
			for _, voter in ipairs(entry.voters) do
				if isMe(voter) then myVotes[item] = entry.name end
			end
		end
	end
end

local function setTally(item, candidate, voters)
	local key = strlower(candidate)
	if #voters == 0 then
		if tally[item] then tally[item][key] = nil end
	else
		tallyOf(item)[key] = { name = candidate, voters = copyList(voters) }
	end
end

--------------------------------------------------------------------------------
-- Getters
--------------------------------------------------------------------------------

-- How many council members voted for a candidate of an item, and who (a copy).
function Voting:GetVotes(candidate, item)
	local byCandidate = tally[item or 1]
	local entry = candidate and byCandidate and byCandidate[strlower(candidate)]
	if not entry then return 0, {} end
	return #entry.voters, copyList(entry.voters)
end

function Voting:GetMyVote(item)
	return myVotes[item or 1]
end

--------------------------------------------------------------------------------
-- Council: cast a vote
--------------------------------------------------------------------------------

-- Shows our own vote at once, before the loot master's count arrives (that one replaces it).
local function applyLocal(item, candidate)
	local me = ALC:PlayerName()
	local function without(voters)
		local list = {}
		for _, v in ipairs(voters) do if not ALC:SameName(v, me) then list[#list + 1] = v end end
		return list
	end
	local old = myVotes[item]
	if old then
		local entry = tally[item] and tally[item][strlower(old)]
		setTally(item, old, entry and without(entry.voters) or {})
	end
	if candidate then
		local entry = tally[item] and tally[item][strlower(candidate)]
		local voters = entry and without(entry.voters) or {}
		voters[#voters + 1] = me
		table.sort(voters)
		setTally(item, candidate, voters)
	end
	recomputeMine()
	changed()
end

-- Votes for a candidate of an item; voting for the one you already chose takes the vote
-- back. Returns true, or false and a message.
function Voting:Cast(candidate, item)
	item = item or 1
	local session = ALC.Sessions:GetSession()
	if not session then return false, L["There is no active session."] end
	if not session.isCouncil then return false, L["Only the council can vote."] end
	if not ALC.Sessions:GetItem(item) then return false, L["That item is not in the session."] end
	if not ALC.Sessions:IsItemOpen(item) then return false, L["That item has already been awarded."] end
	if session.paused then return false, L["The session is paused."] end

	local payload = { item = item }
	local mine = myVotes[item]
	if candidate and not (mine and ALC:SameName(mine, candidate)) then
		local entry = ALC.Candidates:Get(candidate, item)
		if not entry then return false, L["That player has not answered."] end
		if entry.response == "PASS" then return false, L["That player passed."] end
		payload.candidate = entry.name
	end
	if not ALC.Comm:SendWhisper(session.lm, "VOTE", session.sid, payload) then
		return false, L["Could not send your vote. See /alc debug log."]
	end
	applyLocal(item, payload.candidate)
	return true
end

--------------------------------------------------------------------------------
-- Loot master: VOTE in, VOTE_UPDATE out
--------------------------------------------------------------------------------
local function votersFor(item, candidate)
	local voters = {}
	for _, vote in pairs(votersOfItem(item)) do
		if ALC:SameName(vote.candidate, candidate) then voters[#voters + 1] = vote.voter end
	end
	table.sort(voters)
	return voters
end

local function persist()
	local saved = {}
	for item, byVoter in pairs(voterOf) do
		for _, vote in pairs(byVoter) do
			saved[#saved + 1] = { item = item, voter = vote.voter, candidate = vote.candidate }
		end
	end
	table.sort(saved, function(a, b)
		if a.item ~= b.item then return a.item < b.item end
		return a.voter < b.voter
	end)
	ALC.Settings:GetSessionStore().votes = saved
end

local function broadcast(session, item, candidate)
	local voters = votersFor(item, candidate)
	ALC.Comm:SendCouncil(ALC.Council:GetReachableCouncil(), "VOTE_UPDATE", session.sid,
		{ item = item, candidate = candidate, votes = #voters, voters = voters })
end

local function onVote(_, sender, _, p)
	local session = ALC.Sessions:GetSession()
	if not session or not session.isLM then return end
	local item = p.item
	if session.paused then
		Debug:Log("Voting", "vote from %s ignored (the session is paused)", sender)
		return
	end
	if not ALC.Sessions:IsItemOpen(item) then
		Debug:Warn("Voting", "%s voted on item %d, which is not open", sender, item)
		return
	end

	local entry = p.candidate and ALC.Candidates:Get(p.candidate, item)
	if p.candidate and (not entry or entry.response == "PASS") then
		Debug:Warn("Voting", "%s voted for %s, who is not a candidate for item %d", sender, tostring(p.candidate), item)
		return
	end
	local newCandidate = entry and entry.name or nil
	local key = strlower(sender)
	local byVoter = votersOfItem(item)
	local old = byVoter[key] and byVoter[key].candidate or nil

	local same = (old == nil and newCandidate == nil) or (old ~= nil and newCandidate ~= nil and ALC:SameName(old, newCandidate))
	if same then return end

	byVoter[key] = newCandidate and { voter = sender, candidate = newCandidate } or nil
	persist()
	Debug:Log("Voting", "item %d, %s: %s -> %s", item, sender, tostring(old), tostring(newCandidate))
	if old then broadcast(session, item, old) end
	if newCandidate then broadcast(session, item, newCandidate) end
end

--------------------------------------------------------------------------------
-- Council: VOTE_UPDATE in
--------------------------------------------------------------------------------
-- Messages can overtake each other: a count older than one already shown is dropped.
local appliedSeq = {} -- sid|item|candidate -> seq of the count shown

local function onUpdate(_, _, sid, p, seq)
	local session = ALC.Sessions:GetSession()
	if not session or not session.isCouncil then return end
	local key = sid .. "|" .. p.item .. "|" .. strlower(p.candidate)
	if seq and appliedSeq[key] and seq < appliedSeq[key] then return end
	appliedSeq[key] = seq
	setTally(p.item, p.candidate, p.voters)
	recomputeMine()
	changed()
end

--------------------------------------------------------------------------------
-- Recovery
--------------------------------------------------------------------------------
local function clear()
	ALC.Settings:GetSessionStore().votes = nil
	if next(tally) == nil and next(voterOf) == nil and next(myVotes) == nil then return end
	tally, voterOf, myVotes = {}, {}, {}
	changed()
end

-- A snapshot for a council member: the votes as they stand, and their own votes.
local function onSnapshotBuild(_, payload, requester, isCouncil)
	if not isCouncil then return end
	-- From the loot master's own records, not from what it displays.
	local votes, mine = {}, {}
	local key = strlower(requester)
	for item, byVoter in pairs(voterOf) do
		local names = {}
		for _, vote in pairs(byVoter) do names[strlower(vote.candidate)] = vote.candidate end
		for _, candidate in pairs(names) do
			votes[#votes + 1] = { item = item, candidate = candidate, voters = votersFor(item, candidate) }
		end
		if byVoter[key] then mine[#mine + 1] = { item = item, candidate = byVoter[key].candidate } end
	end
	table.sort(votes, function(a, b)
		if a.item ~= b.item then return a.item < b.item end
		return a.candidate < b.candidate
	end)
	table.sort(mine, function(a, b) return a.item < b.item end)
	payload.votes = votes
	if #mine > 0 then payload.yourVotes = mine end
end

local function onSnapshot(_, p, session)
	tally, myVotes = {}, {}
	if session.isCouncil then
		for _, vote in ipairs(p.votes or {}) do setTally(vote.item, vote.candidate, vote.voters) end
		recomputeMine()
	end
	changed()
end

-- The loot master's own session came back after a reload: so do the votes.
local function onSessionStarted(_, session, restored)
	if not restored then
		clear()
		return
	end
	if not session.isLM then return end
	tally, voterOf, myVotes = {}, {}, {}
	for _, vote in ipairs(ALC.Settings:GetSessionStore().votes or {}) do
		local item = vote.item or 1 -- votes saved by version 0.1 have no item
		votersOfItem(item)[strlower(vote.voter)] = { voter = vote.voter, candidate = vote.candidate }
	end
	for item, byVoter in pairs(voterOf) do
		local candidates = {}
		for _, vote in pairs(byVoter) do candidates[strlower(vote.candidate)] = vote.candidate end
		for _, candidate in pairs(candidates) do setTally(item, candidate, votersFor(item, candidate)) end
	end
	recomputeMine()
	changed()
end

function Voting:Init()
	local register = ALC.Events.Register
	register(self, "ALC_COMM_VOTE", onVote)
	register(self, "ALC_COMM_VOTE_UPDATE", onUpdate)
	register(self, "ALC_SESSION_SNAPSHOT_BUILD", onSnapshotBuild)
	register(self, "ALC_SESSION_SNAPSHOT", onSnapshot)
	register(self, "ALC_SESSION_STARTED", onSessionStarted)
	register(self, "ALC_SESSION_ENDED", clear)
end

-- /alc vote opens the voting window; /alc vote <name> votes from the chat, on the item the window shows.
ALC.Commands:Register("vote", function(arg)
	if arg == "" then
		if ALC.CouncilWindow then ALC.CouncilWindow:Toggle() end
		return
	end
	local item = ALC.CouncilWindow and ALC.CouncilWindow:GetFocus() or 1
	local ok, message = Voting:Cast(arg, item)
	if not ok then ALC:Print(message) end
end, L["open the voting window, or vote for a player on the item shown: /alc vote <name>"])

-- Voting: council votes on the candidates. One vote per council member and item; it
-- can be moved to another candidate or taken back.
--
-- The loot master is the authority: it receives VOTE, keeps who voted for whom and
-- sends the new count of every affected candidate to the council as VOTE_UPDATE.
-- Council members show what the loot master last told them; they never count
-- other people's votes themselves. Votes go only to the council.
--
-- Events:
--   ALC_VOTING_CHANGED ()   the counts or our own vote changed, or were cleared

local ALC = ALC
local L = ALC.L

local Debug = ALC.Debug

local strlower = string.lower

local Voting = {}
ALC.Voting = Voting

-- What everybody on the council sees: lowercase candidate -> { name, voters = { ... } }.
local tally = {}
local myVote -- the candidate we voted for, nil if none

-- Loot master only: lowercase voter -> { voter, candidate }.
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

local function recomputeMine()
	myVote = nil
	for _, entry in pairs(tally) do
		for _, voter in ipairs(entry.voters) do
			if isMe(voter) then myVote = entry.name end
		end
	end
end

local function setTally(candidate, voters)
	local key = strlower(candidate)
	if #voters == 0 then
		tally[key] = nil
	else
		tally[key] = { name = candidate, voters = copyList(voters) }
	end
end

--------------------------------------------------------------------------------
-- Getters
--------------------------------------------------------------------------------

-- How many council members voted for a candidate, and who (a copy).
function Voting:GetVotes(candidate)
	local entry = candidate and tally[strlower(candidate)]
	if not entry then return 0, {} end
	return #entry.voters, copyList(entry.voters)
end

function Voting:GetMyVote()
	return myVote
end

--------------------------------------------------------------------------------
-- Council: cast a vote
--------------------------------------------------------------------------------

-- Votes for a candidate; voting for the one you already chose takes the vote back.
-- Returns true, or false and a message.
function Voting:Cast(candidate)
	local session = ALC.Sessions:GetSession()
	if not session then return false, L["There is no active session."] end
	if not session.isCouncil then return false, L["Only the council can vote."] end

	local payload = {}
	if candidate and not (myVote and ALC:SameName(myVote, candidate)) then
		local entry = ALC.Candidates:Get(candidate)
		if not entry then return false, L["That player has not answered."] end
		if entry.response == "PASS" then return false, L["That player passed."] end
		payload.candidate = entry.name
	end
	if not ALC.Comm:SendWhisper(session.lm, "VOTE", session.sid, payload) then
		return false, L["Could not send your vote. See /alc debug log."]
	end
	return true
end

--------------------------------------------------------------------------------
-- Loot master: VOTE in, VOTE_UPDATE out
--------------------------------------------------------------------------------
local function votersFor(candidate)
	local voters = {}
	for _, vote in pairs(voterOf) do
		if ALC:SameName(vote.candidate, candidate) then voters[#voters + 1] = vote.voter end
	end
	table.sort(voters)
	return voters
end

local function persist()
	local saved = {}
	for _, vote in pairs(voterOf) do saved[#saved + 1] = { voter = vote.voter, candidate = vote.candidate } end
	ALC.Settings:GetSessionStore().votes = saved
end

local function broadcast(session, candidate)
	local voters = votersFor(candidate)
	ALC.Comm:SendCouncil(ALC.Council:GetReachableCouncil(), "VOTE_UPDATE", session.sid,
		{ candidate = candidate, votes = #voters, voters = voters })
end

local function onVote(_, sender, _, p)
	local session = ALC.Sessions:GetSession()
	if not session or not session.isLM then return end

	local entry = p.candidate and ALC.Candidates:Get(p.candidate)
	if p.candidate and (not entry or entry.response == "PASS") then
		Debug:Warn("Voting", "%s voted for %s, who is not a candidate", sender, tostring(p.candidate))
		return
	end
	local newCandidate = entry and entry.name or nil
	local key = strlower(sender)
	local old = voterOf[key] and voterOf[key].candidate or nil

	local same = (old == nil and newCandidate == nil) or (old ~= nil and newCandidate ~= nil and ALC:SameName(old, newCandidate))
	if same then return end

	voterOf[key] = newCandidate and { voter = sender, candidate = newCandidate } or nil
	persist()
	Debug:Log("Voting", "%s: %s -> %s", sender, tostring(old), tostring(newCandidate))
	if old then broadcast(session, old) end
	if newCandidate then broadcast(session, newCandidate) end
end

--------------------------------------------------------------------------------
-- Council: VOTE_UPDATE in
--------------------------------------------------------------------------------
local function onUpdate(_, _, _, p)
	local session = ALC.Sessions:GetSession()
	if not session or not session.isCouncil then return end
	setTally(p.candidate, p.voters)
	recomputeMine()
	changed()
end

--------------------------------------------------------------------------------
-- Recovery
--------------------------------------------------------------------------------
local function clear()
	ALC.Settings:GetSessionStore().votes = nil
	if next(tally) == nil and next(voterOf) == nil and myVote == nil then return end
	tally, voterOf, myVote = {}, {}, nil
	changed()
end

-- A snapshot for a council member: the votes as they stand, and their own vote.
local function onSnapshotBuild(_, payload, requester, isCouncil)
	if not isCouncil then return end
	-- From the loot master's own records, not from what it displays.
	local names, votes = {}, {}
	for _, vote in pairs(voterOf) do names[strlower(vote.candidate)] = vote.candidate end
	for _, candidate in pairs(names) do
		votes[#votes + 1] = { candidate = candidate, voters = votersFor(candidate) }
	end
	table.sort(votes, function(a, b) return a.candidate < b.candidate end)
	payload.votes = votes
	local mine = voterOf[strlower(requester)]
	if mine then payload.yourVote = mine.candidate end
end

local function onSnapshot(_, p, session)
	tally, myVote = {}, nil
	if session.isCouncil then
		for _, vote in ipairs(p.votes or {}) do setTally(vote.candidate, vote.voters) end
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
	tally, voterOf, myVote = {}, {}, nil
	for _, vote in ipairs(ALC.Settings:GetSessionStore().votes or {}) do
		voterOf[strlower(vote.voter)] = { voter = vote.voter, candidate = vote.candidate }
	end
	local candidates = {}
	for _, vote in pairs(voterOf) do candidates[strlower(vote.candidate)] = vote.candidate end
	for _, candidate in pairs(candidates) do setTally(candidate, votersFor(candidate)) end
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

-- /alc vote opens the voting window; /alc vote <name> votes from the chat.
ALC.Commands:Register("vote", function(arg)
	if arg == "" then
		if ALC.CouncilWindow then ALC.CouncilWindow:Toggle() end
		return
	end
	local ok, message = Voting:Cast(arg)
	if not ok then ALC:Print(message) end
end, L["open the voting window, or vote for a player: /alc vote <name>"])

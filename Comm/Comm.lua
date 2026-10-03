-- Comm: envelope, serialization, send helpers and the receive/validation pipeline.
--
-- Every outgoing message is validated with the same rules as an incoming one and is
-- also delivered to ourselves through a local loopback (serialized, so it is an
-- independent copy). That keeps one code path for the loot master and for clients,
-- and lets `/alc test` run solo. The network echo of our own messages is dropped.
--
-- Accepted messages are published on the event bus as ALC_COMM_<TYPE> with
--   (sender, sid, payload, seq, distribution)
--
-- Other modules are consulted through getters:
--   ALC.Council:IsLootMaster(name), ALC.Council:IsCouncil(name)
--   ALC.Sessions:GetActiveSid()
-- Until those modules exist, LM/council-only messages are rejected.

local ALC = ALC
local LibStub = LibStub
local AceSerializer = LibStub("AceSerializer-3.0")
local Protocol = ALC.Protocol
local Debug = ALC.Debug

local type, pairs, ipairs = type, pairs, ipairs
local strlower, strmatch = string.lower, string.match
local floor = math.floor
local GetTime, time = GetTime, time

local Comm = {}
ALC.Comm = Comm
LibStub("AceComm-3.0"):Embed(Comm)
LibStub("AceEvent-3.0"):Embed(Comm)

local MAX_MESSAGE_LENGTH = 65536 -- a snapshot of a session with many items and candidates is large
local LOG_INTERVAL = 10     -- seconds between identical rejection log lines
local VERSION_WAIT = 3      -- seconds to wait for version replies

local GROUP_DISTRIBUTIONS = { RAID = true, PARTY = true, INSTANCE_CHAT = true }

--------------------------------------------------------------------------------
-- Small bounded map, so per-session bookkeeping cannot grow without limit.
--------------------------------------------------------------------------------
local function newMap(limit)
	local map = { data = {}, n = 0 }
	function map:get(key) return self.data[key] end
	function map:set(key, value)
		if self.data[key] == nil then
			if self.n >= limit then self.data, self.n = {}, 0 end
			self.n = self.n + 1
		end
		self.data[key] = value
	end
	return map
end

-- Messages from the loot master can overtake each other on the way (a broadcast and a whisper, or
-- two priorities), so a number is accepted once while it is within SEQ_WINDOW of the highest one seen.
local SEQ_WINDOW = 64
local lastSeq = newMap(8)      -- sid -> { high = highest accepted seq, seen = { [seq] = true } }
local nextSeq = newMap(8)      -- sid -> last seq we stamped when sending as loot master
local rejectLog = newMap(200)  -- "sender|reason" -> time last logged
local versionWarned = newMap(200)
local versions = {}            -- lowercase name -> { name, addon, proto, seen }

--------------------------------------------------------------------------------
-- Identity and group
--------------------------------------------------------------------------------
-- Resolved on every call: UnitName("player") is not reliable while addons load.
local function me()
	return ALC:NormalizeName(ALC:PlayerName())
end

local HOME = LE_PARTY_CATEGORY_HOME or 1
local INSTANCE = LE_PARTY_CATEGORY_INSTANCE or 2

function Comm:GetGroupChannel()
	if IsInGroup(INSTANCE) and not IsInGroup(HOME) then return "INSTANCE_CHAT" end
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
	return nil
end

-- Full names of everyone in the group, including ourselves. Replaceable in tests.
function Comm.GetGroupNames()
	local names, seen = {}, {}
	local function add(name)
		local key = name and strlower(name)
		if key and not seen[key] then
			seen[key] = true
			names[#names + 1] = name
		end
	end
	add(me())
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do add(ALC:UnitFullName("raid" .. i)) end -- includes ourselves: counted once
	elseif IsInGroup() then
		for i = 1, 4 do add(ALC:UnitFullName("party" .. i)) end
	end
	return names
end

local roster, rosterDirty = {}, true

local function rebuildRoster()
	roster = {}
	for _, name in ipairs(Comm.GetGroupNames()) do
		local normalized = ALC:NormalizeName(name)
		if normalized then roster[strlower(normalized)] = true end
	end
	rosterDirty = false
end

function Comm:IsGroupMember(name)
	name = ALC:NormalizeName(name)
	if not name then return false end
	if rosterDirty then rebuildRoster() end
	return roster[strlower(name)] == true or ALC:SameName(name, me())
end

function Comm:InvalidateRoster()
	rosterDirty = true
end

--------------------------------------------------------------------------------
-- Rejection logging (rate limited so a noisy sender cannot flood the log)
--------------------------------------------------------------------------------
local function reject(sender, t, reason)
	local key = (sender or "?") .. "|" .. reason
	local now = GetTime()
	local last = rejectLog:get(key)
	if last and now - last < LOG_INTERVAL then return end
	rejectLog:set(key, now)
	Debug:Warn("Comm", "rejected %s from %s: %s", t or "?", sender or "?", reason)
end

--------------------------------------------------------------------------------
-- Versions
--------------------------------------------------------------------------------
local function recordVersion(name, addon, proto)
	versions[strlower(name)] = { name = name, addon = addon, proto = proto, seen = time() }
	ALC.Events:Fire("ALC_VERSIONS_CHANGED")
end

function Comm:GetVersions()
	return versions
end

-- Compares two version texts such as "0.2.0-alpha2": the numbers first, then a release is
-- newer than a pre-release, and pre-releases are compared as text. Returns -1, 0 or 1.
function Comm.CompareVersions(a, b)
	local function parse(text)
		local numbers, tag = strmatch(tostring(text or ""), "^v?([%d%.]+)%-?(.*)$")
		local parts = {}
		for n in string.gmatch(numbers or "", "%d+") do parts[#parts + 1] = tonumber(n) end
		return parts, tag or ""
	end
	local pa, ta = parse(a)
	local pb, tb = parse(b)
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then return x < y and -1 or 1 end
	end
	if ta == tb then return 0 end
	if ta == "" then return 1 end  -- a release is newer than its pre-release
	if tb == "" then return -1 end
	return ta < tb and -1 or 1
end

-- The group as a list for the version window: { name, class, status, addon, proto }, problems
-- first. Status: "self", "ok", "older", "newer" (their version compared with ours),
-- "incompatible" (another protocol) or "none" (no reply: no addon, or one too old).
local STATUS_ORDER = { incompatible = 1, none = 2, older = 3, newer = 4, ok = 5, self = 6 }

function Comm:GetVersionRows()
	local rows, listed = {}, {}
	local me = ALC:NormalizeName(ALC:PlayerName())
	local function add(name)
		local normalized = ALC:NormalizeName(name)
		local key = normalized and strlower(normalized)
		if not key or listed[key] then return end
		listed[key] = true
		local unit = ALC:FindUnitByName(normalized)
		local row = { name = normalized, class = unit and select(2, UnitClass(unit)) or nil }
		local info = versions[key]
		if me and strlower(me) == key then
			row.status, row.addon, row.proto = "self", ALC.version, Protocol.VERSION
		elseif not info then
			row.status = "none"
		elseif not info.addon or info.proto ~= Protocol.VERSION then
			row.status, row.addon, row.proto = "incompatible", info.addon, info.proto
		else
			local cmp = Comm.CompareVersions(info.addon, ALC.version)
			row.status = cmp == 0 and "ok" or (cmp < 0 and "older" or "newer")
			row.addon, row.proto = info.addon, info.proto
		end
		rows[#rows + 1] = row
	end
	if me then add(me) end
	for _, name in ipairs(self.GetGroupNames()) do add(name) end
	table.sort(rows, function(a, b)
		local oa, ob = STATUS_ORDER[a.status], STATUS_ORDER[b.status]
		if oa ~= ob then return oa < ob end
		return a.name < b.name
	end)
	return rows
end

--------------------------------------------------------------------------------
-- Receive pipeline
--------------------------------------------------------------------------------
local function senderAllowed(spec, sender)
	local who = spec.allowed
	if who == "lm" then
		local council = ALC.Council
		if council and council:IsLootMaster(sender) then return true end
		return false, "sender is not the loot master"
	elseif who == "council" then
		local council = ALC.Council
		if council and council:IsCouncil(sender) then return true end
		return false, "sender is not on the council"
	end
	if Comm:IsGroupMember(sender) then return true end
	return false, "sender is not in the group"
end

local function channelMatches(spec, distribution)
	if spec.channel == "WHISPER" then return distribution == "WHISPER" end
	return GROUP_DISTRIBUTIONS[distribution] == true
end

local function validSid(sid)
	return type(sid) == "string" and sid ~= "" and #sid <= Protocol.MAX_SID_LENGTH
end

-- Runs the six validation steps on a decoded envelope. A message that fails any
-- step never touches state. Returns true when the message was accepted.
function Comm:Process(env, distribution, sender)
	sender = ALC:NormalizeName(sender)
	if not sender then
		reject(nil, nil, "no sender")
		return false
	end

	-- 1. envelope shape and protocol version
	if type(env) ~= "table" or type(env.v) ~= "number" or type(env.t) ~= "string" or type(env.p) ~= "table" then
		reject(sender, nil, "malformed envelope")
		return false
	end
	if env.v ~= Protocol.VERSION then
		if not versionWarned:get(sender) then
			versionWarned:set(sender, true)
			Debug:Warn("Comm", "%s uses incompatible protocol v%s (ours is v%d)", sender, tostring(env.v), Protocol.VERSION)
			-- Without this the two of you would just not see each other's sessions.
			if Comm:IsGroupMember(sender) then
				ALC:Print(ALC.L["%s has another version of the addon (protocol v%s, yours is v%d). Update it to play together."],
					sender, tostring(env.v), Protocol.VERSION)
			end
		end
		if env.v == floor(env.v) and env.v >= 0 and env.v <= 9999 then
			recordVersion(sender, nil, env.v)
		end
		return false
	end
	local t = env.t

	-- 2. known type
	local spec = Protocol.specs[t]
	if not spec then
		reject(sender, "?", "unknown message type")
		return false
	end

	-- 3. sender and channel
	if not channelMatches(spec, distribution) then
		reject(sender, t, "wrong channel " .. tostring(distribution))
		return false
	end
	local ok, reason = senderAllowed(spec, sender)
	if not ok then
		reject(sender, t, reason)
		return false
	end

	-- 4. session id
	local sid = env.sid
	if spec.sid == "none" then
		if sid ~= nil then
			reject(sender, t, "unexpected sid")
			return false
		end
	else
		if not validSid(sid) then
			reject(sender, t, "missing or invalid sid")
			return false
		end
		if spec.sid == "active" then
			local sessions = ALC.Sessions
			local active = sessions and sessions:GetActiveSid()
			if sid ~= active then
				reject(sender, t, "stale or unknown session")
				return false
			end
		end
	end

	-- 5. sequence number (loot master messages only)
	local seq = env.seq
	if spec.seq then
		if type(seq) ~= "number" or seq ~= floor(seq) or seq < 1 or seq > 2147483647 then
			reject(sender, t, "missing or invalid seq")
			return false
		end
		local window = lastSeq:get(sid)
		if window and (seq <= window.high - SEQ_WINDOW or window.seen[seq]) then
			reject(sender, t, "old seq")
			return false
		end
	end

	-- 6. payload
	ok, reason = spec.validate(env.p, sender)
	if not ok then
		reject(sender, t, "invalid payload: " .. tostring(reason))
		return false
	end

	-- The item a message is about has to be one of the active session's items.
	if spec.sid == "active" and env.p.item ~= nil then
		local sessions = ALC.Sessions
		if sessions and sessions.GetItemCount and env.p.item > sessions:GetItemCount() then
			reject(sender, t, "item out of range")
			return false
		end
	end

	-- Accepted
	if spec.seq then
		local window = lastSeq:get(sid)
		if not window then window = { high = 0, seen = {} } lastSeq:set(sid, window) end
		window.seen[seq] = true
		if seq > window.high then
			window.high = seq
			for old in pairs(window.seen) do
				if old <= seq - SEQ_WINDOW then window.seen[old] = nil end
			end
		end
	end
	Debug:Log("Comm", "recv %s from %s sid=%s seq=%s", t, sender, tostring(sid), tostring(seq))
	ALC.Events:Fire("ALC_COMM_" .. t, sender, sid, env.p, seq, distribution)
	return true
end

-- Decodes a raw message (network or loopback) and runs it through the pipeline.
function Comm:HandleMessage(message, distribution, sender)
	if type(message) ~= "string" or #message > MAX_MESSAGE_LENGTH then
		reject(ALC:NormalizeName(sender), nil, "message missing or too large")
		return false
	end
	local ok, env = AceSerializer:Deserialize(message)
	if not ok then
		reject(ALC:NormalizeName(sender), nil, "undecodable message")
		return false
	end
	return self:Process(env, distribution, sender)
end

-- AceComm callback. Our own broadcasts come back from the server; loopback already
-- delivered them, so the echo is dropped.
function Comm:OnCommReceived(_, message, distribution, sender)
	if ALC:SameName(sender, me()) then return end
	self:HandleMessage(message, distribution, sender)
end

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------
-- A queue with explicit head and tail. (Not `#queue`: once the first entries are cleared
-- the length is unreliable, and a message sent while we are handling another one would
-- land behind the read position and wait for the next drain.)
local loopbackQueue, loopbackHead, loopbackTail, loopbackScheduled = {}, 1, 0, false

local function drainLoopback()
	while loopbackHead <= loopbackTail do
		local entry = loopbackQueue[loopbackHead]
		loopbackQueue[loopbackHead] = nil
		loopbackHead = loopbackHead + 1
		-- One broken listener must not stop the loot master's own messages: report the
		-- error like any other and go on with the next message.
		local ok, err = pcall(Comm.HandleMessage, Comm, entry.message, entry.distribution, me())
		if not ok then
			Debug:Error("Comm", "error while handling a message: %s", tostring(err))
			geterrorhandler()(err)
		end
	end
	loopbackHead, loopbackTail, loopbackScheduled = 1, 0, false
end

local function enqueueLoopback(message, distribution)
	loopbackTail = loopbackTail + 1
	loopbackQueue[loopbackTail] = { message = message, distribution = distribution }
	if not loopbackScheduled then
		loopbackScheduled = true
		C_Timer.After(0, drainLoopback)
	end
end

-- Validates an outgoing message and builds its envelope, or returns nil and logs why.
local function prepare(t, sid, p, channel)
	local spec = Protocol.specs[t]
	if not spec then
		Debug:Error("Comm", "cannot send unknown type %s", tostring(t))
		return nil
	end
	if spec.channel ~= channel then
		Debug:Error("Comm", "%s must be sent on %s, not %s", t, spec.channel, channel)
		return nil
	end
	if type(p) ~= "table" then
		Debug:Error("Comm", "%s has no payload table", t)
		return nil
	end
	if (spec.sid == "none") ~= (sid == nil) or (sid ~= nil and not validSid(sid)) then
		Debug:Error("Comm", "%s sent with wrong sid %s", t, tostring(sid))
		return nil
	end
	local self_ = me()
	local ok, reason = senderAllowed(spec, self_)
	if not ok then
		Debug:Error("Comm", "not sending %s: %s", t, reason)
		return nil
	end
	ok, reason = spec.validate(p, self_)
	if not ok then
		Debug:Error("Comm", "not sending %s: invalid payload: %s", t, tostring(reason))
		return nil
	end
	local env = { v = Protocol.VERSION, t = t, sid = sid, p = p }
	if spec.seq then env.seq = (nextSeq:get(sid) or 0) + 1 end
	return env
end

-- Remembers the seq we stamped, also on disk: after a /reload the loot master must keep
-- counting up, or the other players would reject its messages as old.
local MAX_SAVED_SEQS = 8

local function persistSeq(sid, seq)
	local store = ALC.Settings:GetSeqStore()
	if store[sid] == nil then
		local count = 0
		for _ in pairs(store) do count = count + 1 end
		if count >= MAX_SAVED_SEQS then
			for key in pairs(store) do store[key] = nil end
		end
	end
	store[sid] = seq
end

local function commit(env)
	if env.seq then
		nextSeq:set(env.sid, env.seq)
		persistSeq(env.sid, env.seq)
	end
end

-- Small messages the players wait for (answers, votes, awards) go in the fast lane of the
-- throttle library, so they are not stuck behind the big ones (a session start, a snapshot).
local ALERT_TYPES = {
	RESPONSE = true, CANDIDATE_UPDATE = true, VOTE = true, VOTE_UPDATE = true,
	AWARD = true, AWARD_REVOKE = true, SESSION_PAUSE = true,
}
local function priorityOf(t) return ALERT_TYPES[t] and "ALERT" or "NORMAL" end

-- Broadcast to the group (RAID, or PARTY in a party). Always delivered locally too.
function Comm:SendRaid(t, sid, p)
	local env = prepare(t, sid, p, "GROUP")
	if not env then return false end
	commit(env)
	local message = AceSerializer:Serialize(env)
	local channel = self:GetGroupChannel()
	if channel then
		self:SendCommMessage(ALC.PREFIX, message, channel, nil, priorityOf(t))
	end
	enqueueLoopback(message, channel or "RAID")
	return true
end

local function deliverWhisper(comm, message, target, priority)
	if ALC:SameName(target, me()) then
		enqueueLoopback(message, "WHISPER")
	else
		comm:SendCommMessage(ALC.PREFIX, message, "WHISPER", ALC:NormalizeName(target), priority or "NORMAL")
	end
end

function Comm:SendWhisper(target, t, sid, p)
	if not ALC:NormalizeName(target) then
		Debug:Error("Comm", "%s has no valid target", tostring(t))
		return false
	end
	local env = prepare(t, sid, p, "WHISPER")
	if not env then return false end
	commit(env)
	deliverWhisper(self, AceSerializer:Serialize(env), target, priorityOf(t))
	return true
end

-- One whisper per target, all carrying the same seq. Used for council-only updates.
function Comm:SendCouncil(targets, t, sid, p)
	local env = prepare(t, sid, p, "WHISPER")
	if not env then return false end
	commit(env)
	local message = AceSerializer:Serialize(env)
	local sent = {}
	for _, target in ipairs(targets) do
		local name = ALC:NormalizeName(target)
		local key = name and strlower(name)
		if key and not sent[key] then
			sent[key] = true
			deliverWhisper(self, message, name, priorityOf(t))
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- Version discovery (`/alc debug versions`)
--------------------------------------------------------------------------------
-- Asks the group who has the addon. `silent` leaves the answer to a window (no chat list).
function Comm:RequestVersions(silent)
	if not self:SendRaid("VERSION_REQUEST", nil, {}) then return false end
	if not self:GetGroupChannel() and not silent then
		ALC:Print(ALC.L["Not in a group; only your own version will be shown."])
	end
	if not silent then
		C_Timer.After(VERSION_WAIT, function() Comm:PrintVersions() end)
	end
	return true
end

-- When a session starts: asks the group who has the addon and, a few seconds later, tells the loot master who did not
-- reply (they probably have no Arbiter Loot Council and cannot answer) or runs another protocol. Nothing when alone.
-- Returns true when the question was sent.
function Comm:CheckAddonCoverage()
	if not self:RequestVersions(true) then return false end
	C_Timer.After(VERSION_WAIT + 0.5, function()
		local missing = {}
		for _, row in ipairs(Comm:GetVersionRows()) do
			if row.status == "none" or row.status == "incompatible" then missing[#missing + 1] = row.name end
		end
		if #missing == 0 then
			ALC.Events:Fire("ALC_ADDON_COVERAGE", missing)
			return
		end
		local shown = {}
		for i = 1, math.min(#missing, 6) do shown[i] = missing[i] end
		local names = table.concat(shown, ", ") .. (#missing > 6 and string.format(ALC.L[" and %d more"], #missing - 6) or "")
		ALC:Print(ALC.L["%s did not reply to the version check. They may not have Arbiter Loot Council, so they cannot answer."], names)
		ALC.Events:Fire("ALC_ADDON_COVERAGE", missing)
	end)
	return true
end

-- How long replies are awaited after a request (for "waiting" in the version window).
Comm.VERSION_WAIT = VERSION_WAIT

ALC.Commands:RegisterDebug("versions", function() Comm:RequestVersions() end)

function Comm:PrintVersions()
	local L = ALC.L
	ALC:Print(L["ALC versions (protocol v%d):"], Protocol.VERSION)
	local listed = {}
	for _, name in ipairs(self.GetGroupNames()) do
		local normalized = ALC:NormalizeName(name)
		local key = normalized and strlower(normalized)
		if key and not listed[key] then
			listed[key] = true
			local info = versions[key]
			if info and info.addon then
				ALC:Print("  %s: %s (v%d)", normalized, info.addon, info.proto)
			elseif info then
				ALC:Print("  %s: " .. L["incompatible protocol v%d"], normalized, info.proto)
			else
				ALC:Print("  %s: " .. L["no reply"], normalized)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------
function Comm:Init()
	for sid, seq in pairs(ALC.Settings:GetSeqStore()) do nextSeq:set(sid, seq) end
	self:RegisterComm(ALC.PREFIX, "OnCommReceived")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "InvalidateRoster")

	ALC.Events.Register(self, "ALC_COMM_VERSION_REQUEST", function(_, sender)
		self:SendWhisper(sender, "VERSION", nil, { addon = ALC.version, proto = Protocol.VERSION })
	end)
	ALC.Events.Register(self, "ALC_COMM_VERSION", function(_, sender, _, p)
		recordVersion(sender, p.addon, p.proto)
	end)
	-- A session the loot master starts (not one brought back after a reload): who cannot answer?
	ALC.Events.Register(self, "ALC_SESSION_STARTED", function(_, session, restored)
		if session and session.isLM and not restored and ALC.Settings:GetWarnMissing() then self:CheckAddonCoverage() end
	end)
end

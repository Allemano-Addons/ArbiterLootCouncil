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
local strlower = string.lower
local floor = math.floor
local GetTime, time = GetTime, time

local Comm = {}
ALC.Comm = Comm
LibStub("AceComm-3.0"):Embed(Comm)
LibStub("AceEvent-3.0"):Embed(Comm)

local MAX_MESSAGE_LENGTH = 16384
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

local lastSeq = newMap(8)      -- sid -> last accepted seq from the loot master
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
	local names = { me() }
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local name = ALC:UnitFullName("raid" .. i)
			if name then names[#names + 1] = name end
		end
	elseif IsInGroup() then
		for i = 1, 4 do
			local name = ALC:UnitFullName("party" .. i)
			if name then names[#names + 1] = name end
		end
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
end

function Comm:GetVersions()
	return versions
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
		if seq <= (lastSeq:get(sid) or 0) then
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

	-- Accepted
	if spec.seq then lastSeq:set(sid, seq) end
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

-- Broadcast to the group (RAID, or PARTY in a party). Always delivered locally too.
function Comm:SendRaid(t, sid, p)
	local env = prepare(t, sid, p, "GROUP")
	if not env then return false end
	commit(env)
	local message = AceSerializer:Serialize(env)
	local channel = self:GetGroupChannel()
	if channel then
		self:SendCommMessage(ALC.PREFIX, message, channel, nil, "NORMAL")
	end
	enqueueLoopback(message, channel or "RAID")
	return true
end

local function deliverWhisper(comm, message, target)
	if ALC:SameName(target, me()) then
		enqueueLoopback(message, "WHISPER")
	else
		comm:SendCommMessage(ALC.PREFIX, message, "WHISPER", ALC:NormalizeName(target), "NORMAL")
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
	deliverWhisper(self, AceSerializer:Serialize(env), target)
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
			deliverWhisper(self, message, name)
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- Version discovery (`/alc debug versions`)
--------------------------------------------------------------------------------
function Comm:RequestVersions()
	if not self:SendRaid("VERSION_REQUEST", nil, {}) then return end
	if not self:GetGroupChannel() then
		ALC:Print(ALC.L["Not in a group; only your own version will be shown."])
	end
	C_Timer.After(VERSION_WAIT, function() Comm:PrintVersions() end)
end

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
end

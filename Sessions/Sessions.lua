-- Sessions: the session lifecycle. One active session at a time; it holds one or more items
-- (numbered 1..n), all open for answers at once. An item is done when it is awarded; the
-- session ends when its last item is awarded, or when the loot master cancels it.
--
-- The loot master starts and ends sessions by broadcasting; everyone, the loot master
-- included, creates and ends their local session from the broadcast it receives
-- (Comm loops our own messages back). Clients never invent session state.
--
-- Events:
--   ALC_SESSION_STARTED (session, restored)   a session began, or was restored from a snapshot
--   ALC_SESSION_ENDED   (sid, reason, session)
--   ALC_SESSION_ITEM_AWARDED (item, winner)   one item of the running session was awarded
--   ALC_SESSION_SNAPSHOT_BUILD (payload, requester, isCouncil)
--       loot master side: modules add their own fields to a STATE_SNAPSHOT payload
--   ALC_SESSION_SNAPSHOT (payload, session)
--       client side: a snapshot was applied; modules restore their state from it
--   ALC_SESSION_RESTORED (session)
--       loot master side: our own saved session came back after a reload. Fired after
--       ALC_SESSION_STARTED, so modules that restored their data on STARTED can be read.
--
-- The loot master saves the running session (Settings:GetSessionStore) so a /reload does
-- not lose it. Clients do not save; they ask the loot master for a snapshot.

local ALC = ALC
local LibStub = LibStub
local L = ALC.L

local Debug = ALC.Debug

local strmatch, strlower, format = string.match, string.lower, string.format
local GetTime, time = GetTime, time

local Sessions = {}
ALC.Sessions = Sessions
LibStub("AceEvent-3.0"):Embed(Sessions)

local SNAPSHOT_WAIT = 15      -- seconds a snapshot is accepted after asking for it
local SNAPSHOT_COOLDOWN = 2   -- seconds between snapshots to the same player
local RELOAD_SYNC_DELAY = 5   -- seconds after a reload before asking for state
local RESTORE_DELAY = 3       -- seconds after a reload before the loot master restores its session
local MAX_SAVED_AGE = 6 * 3600 -- a saved session older than this is dropped

local session               -- the active session, or nil
local starting = false      -- we sent SESSION_START and are waiting for our own copy
local counter = 0
local awaitingUntil = 0
local lastServed = {}       -- lowercase name -> time of the last snapshot we sent

local function me()
	return ALC:NormalizeName(ALC:PlayerName())
end

local function copyList(list)
	local copy = {}
	for i, v in ipairs(list) do copy[i] = v end
	return copy
end

-- The items of a session: { itemID, itemString [, winner] }. Only known fields are kept.
local function copyItems(items)
	local copy = {}
	for i, item in ipairs(items) do
		copy[i] = { itemID = item.itemID, itemString = item.itemString, winner = item.winner }
	end
	return copy
end

-- A session saved by version 0.1 had one item and no list.
local function itemsOf(p)
	if p.items then return p.items end
	if p.itemID and p.itemString then return { { itemID = p.itemID, itemString = p.itemString } } end
	return {}
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local function isMe(name)
	return ALC:SameName(name, ALC:PlayerName())
end

local function makeSession(sid, p, restored)
	local s = {
		sid = sid,
		items = copyItems(itemsOf(p)),
		responses = ALC.Responses.FromWire(p.responses),
		council = copyList(p.council),
		lm = ALC:NormalizeName(p.lm),
		startedAt = time(),
		restored = restored and true or false,
		isLM = isMe(p.lm),
		isCouncil = false,
	}
	for _, name in ipairs(s.council) do
		if isMe(name) then s.isCouncil = true break end
	end
	return s
end

local function endSession(reason)
	if not session then return end
	local ended = session
	session, starting, awaitingUntil = nil, false, 0
	ALC.Settings:GetSessionStore().session = nil
	Debug:Log("Sessions", "session %s ended: %s", ended.sid, tostring(reason))
	ALC.Events:Fire("ALC_SESSION_ENDED", ended.sid, reason, ended)
end

-- The loot master keeps the running session so it survives a /reload.
local function saveSession()
	if not session or not session.isLM then return end
	local store = ALC.Settings:GetSessionStore()
	store.session = {
		sid = session.sid,
		items = copyItems(session.items),
		responses = ALC.Responses.ToWire(session.responses),
		council = copyList(session.council),
		lm = session.lm,
	}
	store.savedAt = time()
end

local function beginSession(sid, p, restored)
	if session then endSession("superseded") end
	session, starting = makeSession(sid, p, restored), false
	saveSession()
	Debug:Log("Sessions", "session %s started for %d item(s) (lm %s, council %d, restored=%s)",
		sid, #session.items, session.lm, #session.council, tostring(session.restored))
	ALC.Events:Fire("ALC_SESSION_STARTED", session, session.restored)
end

--------------------------------------------------------------------------------
-- Getters
--------------------------------------------------------------------------------
function Sessions:IsActive() return session ~= nil end

function Sessions:GetActiveSid()
	return session and session.sid or nil
end

-- A copy: callers cannot change session state through it.
function Sessions:GetSession()
	if not session then return nil end
	local copy = {}
	for k, v in pairs(session) do copy[k] = v end
	copy.council = copyList(session.council)
	copy.items = copyItems(session.items)
	copy.responses = ALC.Responses.FromWire(ALC.Responses.ToWire(session.responses))
	return copy
end

-- The answer buttons of the running session (a copy), or nil without a session.
function Sessions:GetResponses()
	if not session then return nil end
	return ALC.Responses.FromWire(ALC.Responses.ToWire(session.responses))
end

-- Whether the id is one of the running session's answers.
function Sessions:HasResponse(id)
	if not session then return false end
	for _, r in ipairs(session.responses) do
		if r.id == id then return true end
	end
	return false
end

function Sessions:GetItemCount()
	return session and #session.items or 0
end

-- One item of the running session (a copy): { itemID, itemString, winner }.
function Sessions:GetItem(index)
	local item = session and session.items[index]
	if not item then return nil end
	return { itemID = item.itemID, itemString = item.itemString, winner = item.winner }
end

-- True while the item has not been awarded.
function Sessions:IsItemOpen(index)
	local item = session and session.items[index]
	return item ~= nil and item.winner == nil
end

-- The council of the active session (a copy), or nil without a session.
function Sessions:GetSessionCouncil()
	return session and copyList(session.council) or nil
end

--------------------------------------------------------------------------------
-- Loot master actions
--------------------------------------------------------------------------------

-- Starts a session for a list of items (links, itemStrings or item ids), in that order.
-- Returns true, sid or false, message.
function Sessions:StartItems(list)
	local name = me()
	if not name or not ALC.Council:IsLootMaster(name) then
		return false, L["You are not the loot master."]
	end
	if session or starting then
		return false, L["A session is already active. Cancel it first with /alc cancel."]
	end
	if type(list) ~= "table" or #list == 0 then
		return false, L["That is not a valid item."]
	end
	if #list > ALC.Constants.MAX_SESSION_ITEMS then
		return false, format(L["A session holds at most %d items."], ALC.Constants.MAX_SESSION_ITEMS)
	end
	local items = {}
	for i, item in ipairs(list) do
		local itemString, itemID = ALC:ParseItem(item)
		if not itemString then
			return false, L["That is not a valid item."]
		end
		items[i] = { itemID = itemID, itemString = itemString }
	end
	counter = counter + 1
	local sid = format("%s-%d-%d", string.sub(name, 1, 30), time(), counter)
	starting = true
	local ok = ALC.Comm:SendRaid("SESSION_START", sid, {
		items = items,
		responses = ALC.Responses.ToWire(ALC.Responses:GetConfiguredSet()),
		council = ALC.Council:BuildSessionList(name),
		lm = name,
	})
	if not ok then
		starting = false
		return false, L["Could not start the session. See /alc debug log."]
	end
	return true, sid
end

-- Starts a session for one item.
function Sessions:Start(item)
	return self:StartItems({ item })
end

function Sessions:Cancel(reason)
	if not session then
		return false, L["There is no active session."]
	end
	if not session.isLM or not ALC.Council:AmLootMaster() then
		return false, L["Only the loot master can cancel the session."]
	end
	if not ALC.Comm:SendRaid("SESSION_CANCEL", session.sid, { reason = reason or "cancelled" }) then
		return false, L["Could not cancel the session. See /alc debug log."]
	end
	return true
end

--------------------------------------------------------------------------------
-- Recovery: a client that reloaded asks the loot master for the current session.
--------------------------------------------------------------------------------
function Sessions:RequestState()
	if session or not IsInGroup() then return false end
	local lootMaster = ALC.Council:GetLootMaster()
	if not lootMaster or isMe(lootMaster) then return false end
	if not ALC.Comm:SendWhisper(lootMaster, "STATE_REQUEST", nil, {}) then return false end
	awaitingUntil = GetTime() + SNAPSHOT_WAIT
	Debug:Log("Sessions", "asked %s for the session state", lootMaster)
	return true
end

--------------------------------------------------------------------------------
-- Message handlers
--------------------------------------------------------------------------------
local function onSessionStart(_, _, sid, p)
	beginSession(sid, p, false)
end

local function onSessionCancel(_, _, _, p)
	endSession(p.reason)
end

-- One item was awarded. The session goes on until its last item is done.
local function onAward(_, _, sid, p)
	local item = session and session.sid == sid and session.items[p.item]
	if not item then return end
	if item.winner ~= nil or item.itemID ~= p.itemID then
		Debug:Warn("Sessions", "ignored an award for item %d that does not fit the session", p.item)
		return
	end
	item.winner = p.winner
	saveSession()
	Debug:Log("Sessions", "item %d awarded to %s", p.item, p.winner)
	ALC.Events:Fire("ALC_SESSION_ITEM_AWARDED", p.item, p.winner)
	for _, other in ipairs(session.items) do
		if other.winner == nil then return end
	end
	endSession("awarded")
end

local function onStateRequest(_, sender)
	if not session or not session.isLM then return end
	local key = strlower(sender)
	local now = GetTime()
	if lastServed[key] and now - lastServed[key] < SNAPSHOT_COOLDOWN then
		Debug:Log("Sessions", "state request from %s ignored (too soon)", sender)
		return
	end
	lastServed[key] = now
	local isCouncil = ALC.Council:IsCouncil(sender)
	local payload = {
		items = copyItems(session.items),
		responses = ALC.Responses.ToWire(session.responses),
		council = copyList(session.council),
		lm = session.lm,
	}
	ALC.Events:Fire("ALC_SESSION_SNAPSHOT_BUILD", payload, sender, isCouncil)
	ALC.Comm:SendWhisper(sender, "STATE_SNAPSHOT", session.sid, payload)
end

local function onStateSnapshot(_, _, sid, p)
	if GetTime() > awaitingUntil then
		Debug:Warn("Sessions", "ignored a state snapshot we did not ask for")
		return
	end
	awaitingUntil = 0
	if session and session.sid == sid then return end
	beginSession(sid, p, true)
	ALC.Events:Fire("ALC_SESSION_SNAPSHOT", p, session)
end

-- Loot master changes are not supported mid-session in v0.1: the old loot master's
-- messages would be rejected from now on, so the session ends locally.
local function onLootMasterChanged(_, newLootMaster)
	if session and not (newLootMaster and ALC:SameName(newLootMaster, session.lm)) then
		endSession("loot master changed")
	end
end

--------------------------------------------------------------------------------
-- Recovery: the loot master's own session after a /reload
--------------------------------------------------------------------------------

-- Brings back the saved session when we are still the loot master. Nothing is
-- broadcast: the other players never lost it. Returns true when it was restored.
function Sessions:RestoreSaved()
	if session then return false end
	local store = ALC.Settings:GetSessionStore()
	local saved = store.session
	if not saved then return false end
	if time() - (store.savedAt or 0) > MAX_SAVED_AGE then
		store.session, store.candidates = nil, nil
		Debug:Log("Sessions", "dropped a saved session that was too old")
		return false
	end
	local name = me()
	if not name or not ALC:SameName(saved.lm, name) or not ALC.Council:IsLootMaster(name) then
		Debug:Log("Sessions", "kept the saved session %s: we are not its loot master now", tostring(saved.sid))
		return false
	end
	beginSession(saved.sid, saved, true)
	ALC.Events:Fire("ALC_SESSION_RESTORED", session)
	return true
end

-- After a login or reload: the loot master gets its session back, everybody else asks
-- the loot master for a snapshot.
function Sessions:OnEnteringWorld(isInitialLogin, isReloadingUi)
	if not (isInitialLogin or isReloadingUi) then return end
	C_Timer.After(RESTORE_DELAY, function() Sessions:RestoreSaved() end)
	C_Timer.After(RELOAD_SYNC_DELAY, function() Sessions:RequestState() end)
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------
function Sessions:Init()
	local register = ALC.Events.Register
	register(self, "ALC_COMM_SESSION_START", onSessionStart)
	register(self, "ALC_COMM_SESSION_CANCEL", onSessionCancel)
	register(self, "ALC_COMM_AWARD", onAward)
	register(self, "ALC_COMM_STATE_REQUEST", onStateRequest)
	register(self, "ALC_COMM_STATE_SNAPSHOT", onStateSnapshot)
	register(self, "ALC_COUNCIL_LM_CHANGED", onLootMasterChanged)

	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
		Sessions:OnEnteringWorld(isInitialLogin, isReloadingUi)
	end)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------
local function say(ok, message)
	if not ok and message then ALC:Print(message) end
	return ok
end

ALC.Commands:Register("start", function(arg)
	if arg == "" then
		ALC:Print(L["Usage: /alc start [item link or item id]"])
		return
	end
	say(Sessions:Start(arg))
end, L["start a session for an item (loot master)"])

ALC.Commands:Register("cancel", function()
	say(Sessions:Cancel("cancelled"))
end, L["cancel the active session (loot master)"])

ALC.Commands:Register("sync", function()
	if session then
		ALC:Print(L["You already have the session."])
	elseif Sessions:RequestState() then
		ALC:Print(L["Asked the loot master for the session."])
	else
		ALC:Print(L["Nothing to ask for: you are not in a group with another loot master."])
	end
end, L["ask the loot master for the current session"])

ALC.Commands:Register("status", function()
	if not session then
		ALC:Print(L["No active session."])
		return
	end
	local first = session.items[1].itemString
	local link = select(2, ALC:GetItemInfo(first)) or first
	if #session.items > 1 then link = format(L["%s and %d more"], link, #session.items - 1) end
	ALC:Print(L["Session %s: %s, loot master %s, council of %d%s."], session.sid, link, session.lm,
		#session.council, session.isCouncil and (", " .. L["you are on the council"]) or "")
end, L["show the active session"])

-- Temporary chat feedback until the windows exist.
ALC.Events.Register(Sessions, "ALC_SESSION_STARTED", function(_, s, restored)
	local first = s.items[1].itemString
	local link = select(2, ALC:GetItemInfo(first)) or first
	if #s.items > 1 then link = format(L["%s and %d more"], link, #s.items - 1) end
	ALC:Print(restored and L["Session restored: %s (loot master %s)."] or L["Session started: %s (loot master %s)."], link, s.lm)
end)

ALC.Events.Register(Sessions, "ALC_SESSION_ENDED", function(_, _, reason)
	ALC:Print(L["Session ended: %s."], tostring(reason))
end)

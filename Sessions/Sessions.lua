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
--   ALC_SESSION_ITEM_REVOKED (item, winner)   the loot master took an award back: the item is open again
--   ALC_SESSION_TIMER_ENDED (session)   the answer timer ran out: players can no longer answer
--       (the session itself goes on: the council still votes and awards)
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
local UNDO_GRACE = 90         -- seconds a session with every item awarded stays, for Undo award
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

-- What another addon attached to an item (see Protocol): copied one level deep, lists included.
local function copyExtra(extra)
	if type(extra) ~= "table" then return nil end
	local copy = {}
	for key, value in pairs(extra) do
		copy[key] = type(value) == "table" and copyList(value) or value
	end
	return copy
end

-- The items of a session: { itemID, itemString [, winner] [, extra] }. Only known fields are kept.
local function copyItems(items)
	local copy = {}
	for i, item in ipairs(items) do
		copy[i] = { itemID = item.itemID, itemString = item.itemString, winner = item.winner, extra = copyExtra(item.extra) }
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
	-- The answer timer: a snapshot says what is left of it, a new session its whole length.
	local timer = p.timer
	local left = p.timerLeft or timer
	local paused = p.paused == true
	local timeUp = timer ~= nil and left <= 0
	local s = {
		timer = timer,
		-- Paused: the time left is kept and the timer starts again on Resume.
		endsAt = (timer and not paused) and (GetTime() + left) or nil,
		pausedLeft = (timer and paused and not timeUp) and left or nil,
		paused = paused,
		rolls = p.rolls == true, -- the council gets a random roll per candidate
		mode = p.mode,           -- what kind of session an addon built on ALC says it is (nil for a normal one)
		modeName = p.modeName,   -- its longer name and colour, for the window titles and marks
		modeColor = p.modeColor,
		timeUp = timeUp,
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
		timer = session.timer,
		paused = session.paused or nil,
		rolls = session.rolls or nil,
		mode = session.mode,
		modeName = session.modeName,
		modeColor = session.modeColor,
		pausedLeft = session.pausedLeft,
		endsAtEpoch = session.endsAt and (time() + math.ceil(session.endsAt - GetTime())) or nil,
		sid = session.sid,
		items = copyItems(session.items),
		responses = ALC.Responses.ToWire(session.responses),
		council = copyList(session.council),
		lm = session.lm,
	}
	store.savedAt = time()
end

local function allAwarded()
	if not session then return false end
	for _, item in ipairs(session.items) do
		if item.winner == nil then return false end
	end
	return true
end

-- The session with its last item awarded stays for a while, so a mistaken award can be
-- undone with everybody's answers and votes still there. Then it ends.
local function finishLater(sid)
	session.finishing = true
	-- A session of an addon built on ALC (Soft Reserve) is closed by the loot master and no countdown runs: the rolls and
	-- the results stay as long as they are needed, and an award can be undone until then.
	if session.mode then
		session.finishEndsAt = nil
		return
	end
	session.finishEndsAt = GetTime() + UNDO_GRACE
	C_Timer.After(UNDO_GRACE, function()
		if session and session.sid == sid and allAwarded() then endSession("awarded") end
	end)
end

local function timerEnded(sid)
	if not session or session.sid ~= sid then return end
	session.timeUp = true
	Debug:Log("Sessions", "session %s: the answer timer ran out", sid)
	ALC:Print(L["The time to answer is up."])
	ALC.Events:Fire("ALC_SESSION_TIMER_ENDED", session)
end

-- Starts the answer timer for the seconds that are left. An older timer that is still
-- waiting (before a pause, say) no longer counts.
local timerGeneration = 0
local function armTimer(sid, seconds)
	timerGeneration = timerGeneration + 1
	local mine = timerGeneration
	C_Timer.After(math.max(0, seconds), function()
		if mine == timerGeneration then timerEnded(sid) end
	end)
end

local function beginSession(sid, p, restored)
	if session then endSession("superseded") end
	session, starting = makeSession(sid, p, restored), false
	saveSession()
	Debug:Log("Sessions", "session %s started for %d item(s) (lm %s, council %d, restored=%s)",
		sid, #session.items, session.lm, #session.council, tostring(session.restored))
	ALC.Events:Fire("ALC_SESSION_STARTED", session, session.restored)
	if session and session.sid == sid and allAwarded() then finishLater(sid) end -- restored with nothing left open
	if session.endsAt and session.sid == sid then
		if session.timeUp then
			Sessions:FireTimeUp(sid)
		else
			armTimer(sid, session.endsAt - GetTime())
		end
	end
end

-- A session that starts with its time already up (a snapshot or a reload late in the timer).
function Sessions:FireTimeUp(sid)
	if session and session.sid == sid then
		ALC.Events:Fire("ALC_SESSION_TIMER_ENDED", session)
	end
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

-- Whether a session runs, and how many of its items are still open: { running, total, open }.
function Sessions:GetSummary()
	if not session then return { running = false, total = 0, open = 0 } end
	local open = 0
	for _, item in ipairs(session.items) do
		if item.winner == nil then open = open + 1 end
	end
	return { running = open > 0, total = #session.items, open = open }
end

-- Seconds left of the answer timer (0 when it ran out), or nil when the session has none.
function Sessions:GetTimeLeft()
	if not session or not session.timer then return nil end
	if session.timeUp then return 0 end
	if session.paused then return session.pausedLeft or 0 end
	return math.max(0, session.endsAt - GetTime())
end

-- True when the loot master gave this session random rolls (the Roll column of the council).
function Sessions:HasRolls()
	return session ~= nil and session.rolls == true
end

-- True while the loot master has paused the session: no new answers, votes or awards.
function Sessions:IsPaused()
	return session ~= nil and session.paused == true
end

-- Seconds until a session with every item awarded closes (Undo award is possible until then), or nil.
function Sessions:GetFinishLeft()
	if not session or not session.finishing or not session.finishEndsAt then return nil end
	return math.max(0, session.finishEndsAt - GetTime())
end

-- True while every item is awarded and the session only waits to be closed (by itself, or by the loot master).
function Sessions:IsFinishing()
	return session ~= nil and session.finishing == true
end

-- True once the answer timer has run out.
function Sessions:IsTimeUp()
	return session ~= nil and session.timeUp == true
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
-- `options` is for an addon that builds on ALC (Soft Reserve); a normal session passes none:
--   mode       a short text for the kind of session ("SR")
--   modeName   its longer name ("Soft Reserve") and modeColor (6 hex digits): the windows show them as title and mark colour
--   extra      { [item number] = { key = value, ... } } data that travels with the items (see Protocol)
--   responses  the answer buttons for this session, as a wire list { { id, label, color }, ... }, PASS last
--   rolls      true or false: whether ALC rolls for a candidate when they answer (default: the setting)
function Sessions:StartItems(list, options)
	local name = me()
	if not name or not ALC.Council:IsLootMaster(name) then
		return false, L["You are not the loot master."]
	end
	if (session and not session.finishing) or starting then
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
		if options and options.extra and options.extra[i] ~= nil then
			if type(options.extra[i]) ~= "table" then return false, format(L["The session options are not valid (%s)."], "extra") end
			items[i].extra = copyExtra(options.extra[i])
		end
	end
	local payload = {
		items = items,
		responses = (options and options.responses) or ALC.Responses.ToWire(ALC.Responses:GetConfiguredSet()),
		council = ALC.Council:BuildSessionList(name),
		lm = name,
		timer = ALC.Settings:GetActiveTimer(),
		rolls = ALC.Settings:GetRollsEnabled() or nil,
		mode = options and options.mode or nil,
		modeName = options and options.modeName or nil,
		modeColor = options and options.modeColor or nil,
	}
	if options and options.rolls ~= nil then payload.rolls = options.rolls == true or nil end
	-- What an addon passes is checked here the way every player will check it, so a mistake shows up now.
	if options then
		local valid, reason = ALC.Protocol.specs.SESSION_START.validate(payload, name)
		if not valid then
			Debug:Warn("Sessions", "the session was not started: %s", tostring(reason))
			return false, format(L["The session options are not valid (%s)."], tostring(reason))
		end
	end
	counter = counter + 1
	local sid = format("%s-%d-%d", string.sub(name, 1, 30), time(), counter)
	starting = true
	local ok = ALC.Comm:SendRaid("SESSION_START", sid, payload)
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

-- Pauses (true) or resumes (false) the session for everybody. Returns true, or false and a message.
function Sessions:SetPaused(paused)
	if not session then return false, L["There is no active session."] end
	if not session.isLM or not ALC.Council:AmLootMaster() then
		return false, L["Only the loot master can pause the session."]
	end
	if session.finishing then return false, L["Everything is awarded: there is nothing to pause."] end
	if (session.paused == true) == (paused == true) then
		return false, paused and L["The session is already paused."] or L["The session is not paused."]
	end
	if not ALC.Comm:SendRaid("SESSION_PAUSE", session.sid, { paused = paused and true or false }) then
		return false, L["Could not pause the session. See /alc debug log."]
	end
	return true
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
	ALC.Events:Fire("ALC_SESSION_ITEM_AWARDED", p.item, p.winner, p.response)
	if session and session.sid == sid and allAwarded() then finishLater(sid) end
end

-- The loot master paused or resumed the session (every client, the loot master included).
local function onSessionPause(_, _, sid, p)
	if not session or session.sid ~= sid or session.paused == p.paused then return end
	if p.paused then
		if session.endsAt and not session.timeUp then
			session.pausedLeft = math.max(0, session.endsAt - GetTime())
			session.endsAt = nil
		end
		timerGeneration = timerGeneration + 1 -- the running timer must not fire now
	elseif session.pausedLeft then
		session.endsAt = GetTime() + session.pausedLeft
		armTimer(sid, session.pausedLeft)
		session.pausedLeft = nil
	end
	session.paused = p.paused
	saveSession()
	Debug:Log("Sessions", "session %s %s", sid, p.paused and "paused" or "resumed")
	ALC:Print(p.paused and L["The loot master paused the session."] or L["The session goes on."])
	ALC.Events:Fire("ALC_SESSION_PAUSED", p.paused)
end

-- The loot master took an award back: the item is open again.
local function onAwardRevoke(_, _, sid, p)
	local item = session and session.sid == sid and session.items[p.item]
	if not item then return end
	if item.winner == nil or item.itemID ~= p.itemID or not ALC:SameName(item.winner, p.winner) then
		Debug:Warn("Sessions", "ignored a revoke for item %d that does not fit the session", p.item)
		return
	end
	item.winner = nil
	session.finishing, session.finishEndsAt = false, nil
	saveSession()
	Debug:Log("Sessions", "award of item %d to %s revoked", p.item, p.winner)
	ALC.Events:Fire("ALC_SESSION_ITEM_REVOKED", p.item, p.winner)
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
	if session.timer then
		payload.timer = session.timer
		if session.timeUp then
			payload.timerLeft = 0
		elseif session.paused then
			payload.timerLeft = math.ceil(session.pausedLeft or 0)
		else
			payload.timerLeft = math.max(0, math.ceil(session.endsAt - GetTime()))
		end
	end
	if session.paused then payload.paused = true end
	if session.rolls then payload.rolls = true end
	if session.mode then payload.mode = session.mode end
	if session.modeName then payload.modeName = session.modeName end
	if session.modeColor then payload.modeColor = session.modeColor end
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
	if saved.timer and saved.paused and saved.pausedLeft then
		saved.timerLeft = math.min(saved.timer, math.max(0, math.ceil(saved.pausedLeft)))
	elseif saved.timer and saved.endsAtEpoch then
		saved.timerLeft = math.min(saved.timer, math.max(0, saved.endsAtEpoch - time()))
	else
		saved.timer = nil
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
	register(self, "ALC_COMM_AWARD_REVOKE", onAwardRevoke)
	register(self, "ALC_COMM_SESSION_PAUSE", onSessionPause)
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

ALC.Commands:Register("pause", function()
	say(Sessions:SetPaused(not Sessions:IsPaused()))
end, L["pause or resume the session (loot master)"])

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

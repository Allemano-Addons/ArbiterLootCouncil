-- Responses: the answer buttons of a session, and your answers to its items.
--
-- The loot master chooses the buttons (Settings, "Responses"; five by default) and every
-- session carries them, so everybody sees the same. An answer is sent to the loot master
-- with the items you wear in the same slots, one answer per item. You can change an answer
-- until the item is awarded. The response with the id PASS always exists and is last.
-- Items are numbered as in the session (1 = the first); functions take the item number
-- as their last argument and mean item 1 when it is left out.
--
-- Events:
--   ALC_RESPONSES_CHANGED ()   one of your own answers changed

local ALC = ALC
local L = ALC.L

local Debug = ALC.Debug

local Responses = {}
ALC.Responses = Responses

-- Order matters: it is the order of the buttons. `color` tints chips and labels.
local DEFAULT = {
	{ id = "BIS", label = L["BiS"], color = { 0.30, 0.75, 0.40 } },
	{ id = "UPGRADE", label = L["Upgrade"], color = { 0.35, 0.60, 0.95 } },
	{ id = "MINOR", label = L["Minor"], color = { 0.62, 0.65, 0.72 } },
	{ id = "OFFSPEC", label = L["Offspec"], color = { 0.62, 0.65, 0.72 } },
	{ id = "PASS", label = L["Pass"], color = { 0.50, 0.52, 0.58 } },
}

-- The colours the settings window offers for a button.
Responses.PALETTE = {
	{ 0.30, 0.75, 0.40 }, { 0.35, 0.60, 0.95 }, { 0.62, 0.65, 0.72 }, { 0.50, 0.52, 0.58 },
	{ 0.90, 0.66, 0.24 }, { 0.85, 0.32, 0.30 }, { 0.65, 0.45, 0.90 }, { 0.25, 0.75, 0.80 },
}

local myResponses = {} -- item -> our response id
local myNotes = {}     -- item -> the note that goes with our answer to it

--------------------------------------------------------------------------------
-- Sets of buttons
--------------------------------------------------------------------------------
local function copySet(set)
	local copy = {}
	for i, r in ipairs(set) do copy[i] = { id = r.id, label = r.label, color = { r.color[1], r.color[2], r.color[3] } } end
	return copy
end

function Responses:GetDefaultSet()
	return copySet(DEFAULT)
end

-- A label as it may be used: no control characters or `|`, trimmed, at most 12 letters.
-- Returns nil for a label that is empty once cleaned.
function Responses.CleanLabel(text)
	text = string.gsub(text or "", "[%c|]", "")
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	text = string.sub(text, 1, ALC.Constants.MAX_RESPONSE_LABEL)
	return text ~= "" and text or nil
end

-- Whether a list of buttons can be used: 2 to 8 buttons with their own ids and labels,
-- PASS as the last one. Returns true, or false and a reason.
function Responses:ValidateSet(set)
	if type(set) ~= "table" or #set < 2 or #set > ALC.Constants.MAX_RESPONSES then return false, "wrong number of buttons" end
	local seen = {}
	for i, r in ipairs(set) do
		if type(r) ~= "table" or type(r.id) ~= "string" or not string.match(r.id, "^%u[%u%d]*$") or #r.id > 10 then return false, "bad id" end
		if seen[r.id] then return false, "duplicate id" end
		if r.id == ALC.Constants.DISENCHANT_ID then return false, "reserved id" end
		seen[r.id] = true
		if Responses.CleanLabel(r.label) ~= r.label then return false, "bad label" end
		local col = r.color
		if type(col) ~= "table" or type(col[1]) ~= "number" or type(col[2]) ~= "number" or type(col[3]) ~= "number" then return false, "bad colour" end
		if (r.id == "PASS") ~= (i == #set) then return false, "PASS must be the last button" end
	end
	return true
end

-- The buttons the loot master has chosen (a copy); the default five until it has chosen.
function Responses:GetConfiguredSet()
	local saved = ALC.Settings:GetResponseSet()
	if saved and self:ValidateSet(saved) then return saved end
	return self:GetDefaultSet()
end

-- Saves the loot master's buttons; nil goes back to the default five.
-- Returns true, or false and a reason.
function Responses:SetConfiguredSet(set)
	if set ~= nil then
		local ok, reason = self:ValidateSet(set)
		if not ok then return false, reason end
	end
	ALC.Settings:SetResponseSet(set and copySet(set) or nil)
	return true
end

-- The buttons of the running session, else the loot master's own.
function Responses:GetSet()
	local sessionSet = ALC.Sessions:GetResponses()
	if sessionSet then return sessionSet end
	return self:GetConfiguredSet()
end

-- The position of a response among the buttons (for sorting); unknown ones last.
function Responses:GetOrder(id)
	for i, r in ipairs(self:GetSet()) do
		if r.id == id then return i end
	end
	return 99
end

local function hex(v)
	return string.format("%02x", math.max(0, math.min(255, math.floor(v * 255 + 0.5))))
end

-- The wire form of a set: colours as "rrggbb".
function Responses.ToWire(set)
	local wire = {}
	for i, r in ipairs(set) do
		wire[i] = { id = r.id, label = r.label, color = hex(r.color[1]) .. hex(r.color[2]) .. hex(r.color[3]) }
	end
	return wire
end

-- Back to a set; nil (an old session without buttons) gives the default five.
function Responses.FromWire(wire)
	if not wire then return copySet(DEFAULT) end
	local set = {}
	for i, r in ipairs(wire) do
		local h = r.color
		set[i] = { id = r.id, label = r.label, color = {
			tonumber(string.sub(h, 1, 2), 16) / 255, tonumber(string.sub(h, 3, 4), 16) / 255, tonumber(string.sub(h, 5, 6), 16) / 255 } }
	end
	return set
end

-- A response by id: among the buttons of the session, else among the loot master's, else
-- among the default five (old awards keep their ids). Nil for an id nobody knows.
-- The award to the disenchanter: shown in the log and the chat like an answer.
local DISENCHANT = { id = "DISENCHANT", label = L["Disenchant"], color = { 0.65, 0.45, 0.90 } }

function Responses:Get(id)
	for _, r in ipairs(self:GetSet()) do
		if r.id == id then return r end
	end
	for _, r in ipairs(DEFAULT) do
		if r.id == id then return r end
	end
	if id == DISENCHANT.id then return DISENCHANT end
end

function Responses:GetLabel(id)
	local response = self:Get(id)
	return response and response.label or tostring(id)
end

function Responses:GetMyResponse(item)
	return myResponses[item or 1]
end

-- How many items of the session we have answered.
function Responses:CountMine()
	local count = 0
	for _ in pairs(myResponses) do count = count + 1 end
	return count
end

local function setMine(item, id)
	if myResponses[item] == id then return end
	myResponses[item] = id
	ALC.Events:Fire("ALC_RESPONSES_CHANGED")
end

local function clearMine()
	myNotes = {}
	if next(myResponses) == nil then return end
	myResponses = {}
	ALC.Events:Fire("ALC_RESPONSES_CHANGED")
end

-- A note as it may be sent: no control characters or `|`, trimmed, at most 100 letters.
function Responses.CleanNote(text)
	text = string.gsub(text or "", "[%c|]", "")
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	return string.sub(text, 1, ALC.Constants.MAX_NOTE_LENGTH)
end

-- Our note for an item ("" when there is none).
function Responses:GetNote(item)
	return myNotes[item or 1] or ""
end

-- Sets the note for an item, without sending anything: it goes with the next answer.
function Responses:SetDraftNote(item, text)
	local note = Responses.CleanNote(text)
	myNotes[item or 1] = note ~= "" and note or nil
end

-- Sends (or changes) our response to an item, with that item's note. Returns true, or
-- false and a message.
function Responses:Send(id, item)
	item = item or 1
	local session = ALC.Sessions:GetSession()
	if not session then return false, L["There is no active session."] end
	if not ALC.Sessions:HasResponse(id) then return false, L["Unknown response."] end
	local target = session.items[item]
	if not target then return false, L["That item is not in the session."] end
	if target.winner then return false, L["That item has already been awarded."] end
	if session.paused then return false, L["The session is paused."] end
	if session.timeUp then return false, L["The time to answer is up."] end
	local payload = { item = item, response = id, gear = ALC.Gear:GetEquipped(target.itemString) }
	payload.note = myNotes[item]
	local sent = ALC.Comm:SendWhisper(session.lm, "RESPONSE", session.sid, payload)
	if not sent then return false, L["Could not send your response. See /alc debug log."] end
	Debug:Log("Responses", "item %d: sent %s to %s", item, id, session.lm)
	setMine(item, id)
	return true
end

-- Changes the note of an item and, when we have already answered it and the note is new,
-- sends the answer again with it. Returns true when that was done.
function Responses:SetNote(item, text)
	item = item or 1
	local unchanged = Responses.CleanNote(text) == (myNotes[item] or "")
	self:SetDraftNote(item, text)
	local id = myResponses[item]
	if not id or unchanged then return false end
	return self:Send(id, item) == true
end

function Responses:Init()
	local register = ALC.Events.Register
	register(self, "ALC_SESSION_STARTED", function(_, _, restored)
		if not restored then clearMine() end
	end)
	register(self, "ALC_SESSION_ENDED", clearMine)
	-- After a reload the loot master tells us what we answered.
	register(self, "ALC_SESSION_SNAPSHOT", function(_, p)
		myResponses, myNotes = {}, {}
		for _, mine in ipairs(p.yourResponses or {}) do
			if ALC.Sessions:HasResponse(mine.response) then myResponses[mine.item] = mine.response end
		end
		ALC.Events:Fire("ALC_RESPONSES_CHANGED")
	end)
	-- The loot master got its own session back: our answers are in the restored lists.
	register(self, "ALC_SESSION_RESTORED", function(_, session)
		myResponses, myNotes = {}, {}
		for item = 1, #session.items do
			local mine = ALC.Candidates:Get(ALC:PlayerName(), item)
			if mine and ALC.Sessions:HasResponse(mine.response) then
				myResponses[item] = mine.response
				myNotes[item] = mine.note
			end
		end
		ALC.Events:Fire("ALC_RESPONSES_CHANGED")
	end)
end

-- /alc respond opens the window; /alc respond <answer> [item number] answers from the chat.
ALC.Commands:Register("respond", function(arg)
	local answer, number = string.match(string.upper(arg or ""), "^(%S*)%s*(%d*)$")
	if not answer or answer == "" then
		if ALC.ResponseWindow then ALC.ResponseWindow:Show() end
		return
	end
	local ok, message = Responses:Send(answer, tonumber(number) or 1)
	if not ok then ALC:Print(message) end
end, L["open the response window (or answer: /alc respond bis|upgrade|minor|offspec|pass [item number])"])

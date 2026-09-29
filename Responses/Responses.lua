-- Responses: your answers to the items of the running session.
--
-- The five fixed responses are sent to the loot master with the items you wear in
-- the same slots, one answer per item. You can change an answer until the item is awarded.
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
Responses.LIST = {
	{ id = "BIS", label = L["BiS"], color = { 0.30, 0.75, 0.40 } },
	{ id = "UPGRADE", label = L["Upgrade"], color = { 0.35, 0.60, 0.95 } },
	{ id = "MINOR", label = L["Minor"], color = { 0.62, 0.65, 0.72 } },
	{ id = "OFFSPEC", label = L["Offspec"], color = { 0.62, 0.65, 0.72 } },
	{ id = "PASS", label = L["Pass"], color = { 0.50, 0.52, 0.58 } },
}

local BY_ID = {}
for _, response in ipairs(Responses.LIST) do BY_ID[response.id] = response end

local myResponses = {} -- item -> our response id
local draftNote = ""   -- the note that goes with our next answers (and is sent again when it changes)

function Responses:Get(id)
	return BY_ID[id]
end

function Responses:GetLabel(id)
	return BY_ID[id] and BY_ID[id].label or tostring(id)
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
	draftNote = ""
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

function Responses:GetNote()
	return draftNote
end

-- Sets the note that goes with the next answers, without sending anything.
function Responses:SetDraftNote(text)
	draftNote = Responses.CleanNote(text)
end

-- Sends (or changes) our response to an item, with the current note. Returns true, or
-- false and a message.
function Responses:Send(id, item)
	item = item or 1
	if not BY_ID[id] then return false, L["Unknown response."] end
	local session = ALC.Sessions:GetSession()
	if not session then return false, L["There is no active session."] end
	local target = session.items[item]
	if not target then return false, L["That item is not in the session."] end
	if target.winner then return false, L["That item has already been awarded."] end
	local payload = { item = item, response = id, gear = ALC.Gear:GetEquipped(target.itemString) }
	if draftNote ~= "" then payload.note = draftNote end
	local sent = ALC.Comm:SendWhisper(session.lm, "RESPONSE", session.sid, payload)
	if not sent then return false, L["Could not send your response. See /alc debug log."] end
	Debug:Log("Responses", "item %d: sent %s to %s", item, id, session.lm)
	setMine(item, id)
	return true
end

-- Changes the note and sends it again with every answer we have given to an open item.
-- Returns how many answers were sent.
function Responses:SetNote(text)
	draftNote = Responses.CleanNote(text)
	local session = ALC.Sessions:GetSession()
	if not session then return 0 end
	local resent = 0
	for item, id in pairs(myResponses) do
		if session.items[item] and not session.items[item].winner and self:Send(id, item) then resent = resent + 1 end
	end
	return resent
end

function Responses:Init()
	local register = ALC.Events.Register
	register(self, "ALC_SESSION_STARTED", function(_, _, restored)
		if not restored then clearMine() end
	end)
	register(self, "ALC_SESSION_ENDED", clearMine)
	-- After a reload the loot master tells us what we answered.
	register(self, "ALC_SESSION_SNAPSHOT", function(_, p)
		myResponses = {}
		for _, mine in ipairs(p.yourResponses or {}) do
			if BY_ID[mine.response] then myResponses[mine.item] = mine.response end
		end
		ALC.Events:Fire("ALC_RESPONSES_CHANGED")
	end)
	-- The loot master got its own session back: our answers are in the restored lists.
	register(self, "ALC_SESSION_RESTORED", function(_, session)
		myResponses = {}
		for item = 1, #session.items do
			local mine = ALC.Candidates:Get(ALC:PlayerName(), item)
			if mine and BY_ID[mine.response] then myResponses[item] = mine.response end
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

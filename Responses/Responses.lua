-- Responses: your answer to the item in the running session.
--
-- The five fixed responses are sent to the loot master with the items you wear in
-- the same slots. You can change your answer for as long as the session runs.
--
-- Events:
--   ALC_RESPONSES_CHANGED ()   your own response for the session changed

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

local myResponse -- our response id for the running session, or nil

function Responses:Get(id)
	return BY_ID[id]
end

function Responses:GetLabel(id)
	return BY_ID[id] and BY_ID[id].label or tostring(id)
end

function Responses:GetMyResponse()
	return myResponse
end

local function setMine(id)
	if myResponse == id then return end
	myResponse = id
	ALC.Events:Fire("ALC_RESPONSES_CHANGED")
end

-- Sends (or changes) our response. Returns true, or false and a message.
function Responses:Send(id)
	if not BY_ID[id] then return false, L["Unknown response."] end
	local session = ALC.Sessions:GetSession()
	if not session then return false, L["There is no active session."] end
	local sent = ALC.Comm:SendWhisper(session.lm, "RESPONSE", session.sid, {
		response = id,
		gear = ALC.Gear:GetEquipped(session.itemString),
	})
	if not sent then return false, L["Could not send your response. See /alc debug log."] end
	Debug:Log("Responses", "sent %s to %s", id, session.lm)
	setMine(id)
	return true
end

function Responses:Init()
	local register = ALC.Events.Register
	register(self, "ALC_SESSION_STARTED", function(_, _, restored)
		if not restored then setMine(nil) end
	end)
	register(self, "ALC_SESSION_ENDED", function() setMine(nil) end)
	-- After a reload the loot master tells us what we answered.
	register(self, "ALC_SESSION_SNAPSHOT", function(_, p)
		setMine(BY_ID[p.yourResponse] and p.yourResponse or nil)
	end)
end

ALC.Commands:Register("respond", function(arg)
	arg = string.upper(arg or "")
	if arg == "" then
		if ALC.ResponseWindow then ALC.ResponseWindow:Show() end
		return
	end
	local ok, message = Responses:Send(arg)
	if not ok then ALC:Print(message) end
end, L["open the response window (or answer: /alc respond bis|upgrade|minor|offspec|pass)"])

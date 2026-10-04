-- HubLog: tells Allemano Hub (when it is installed) what the session is doing, so a bug report from the Hub says what
-- happened before the problem: a session started, an item awarded or taken back, the timer ran out. Text only, and
-- nothing is done when the Hub is not there. Never raises an error: a log line must not break a session.

local ALC = ALC

local HubLog = {}
ALC.HubLog = HubLog

local function say(text)
	local log = _G.AllemanoHubLog
	if type(log) == "function" then pcall(log, "ALC", text) end
end

-- The name of item number `index` of the running session, or "item <index>".
local function itemName(index)
	local session = ALC.Sessions and ALC.Sessions.GetSession and ALC.Sessions:GetSession()
	local target = session and session.items and session.items[index]
	local name = target and target.itemString and ALC:GetItemInfo(target.itemString)
	return name or ("item " .. tostring(index))
end

function HubLog:Init()
	local register = ALC.Events.Register
	register(self, "ALC_SESSION_STARTED", function(_, session, restored)
		if not session then return end
		local count = session.items and #session.items or 0
		say(("%s %s: %d item%s%s%s"):format(restored and "Session restored" or "Session started", tostring(session.sid or "?"),
			count, count == 1 and "" or "s", session.modeName and (", " .. session.modeName) or "",
			session.isLM and ", I am the loot master" or (session.isCouncil and ", I am on the council" or "")))
	end)
	register(self, "ALC_SESSION_ENDED", function(_, sid, reason)
		say(("Session %s ended (%s)"):format(tostring(sid or "?"), tostring(reason or "?")))
	end)
	register(self, "ALC_SESSION_ITEM_AWARDED", function(_, item, winner)
		say(("%s awarded to %s"):format(itemName(item), tostring(winner or "?")))
	end)
	register(self, "ALC_SESSION_ITEM_REVOKED", function(_, item, winner)
		say(("Award of %s to %s taken back"):format(itemName(item), tostring(winner or "?")))
	end)
	register(self, "ALC_SESSION_PAUSED", function(_, paused)
		say(paused and "Session paused" or "Session resumed")
	end)
	register(self, "ALC_SESSION_TIMER_ENDED", function() say("The answer timer ran out") end)
	register(self, "ALC_LOOT_ADDED", function(_, count) say(("%s item%s added to the loot list"):format(tostring(count or "?"), count == 1 and "" or "s")) end)
end

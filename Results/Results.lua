-- Results: the outcome of an item that was decided by rolls, shown to everybody. An addon built on ALC (Soft
-- Reserve) works out who wins and hands the rows to the loot master's ALC, which sends them to the whole group as
-- RESULT messages (one per item); every player's ALC keeps the latest rows and can show them in the Result window,
-- so everybody can see that the rolls were fair. ALC itself decides nothing here: it carries and shows the rows.
--
-- A row: { name, answer (a response id), roll (1-100), rerolls = { ... }, outcome = "won" | "tied" | "lost" | "passed",
-- via = "SR" | "MS" | "OS", reserved = true }. A result has a state: "resolved" (the loot master may still reroll) or
-- "accepted".
--
-- Events:
--   ALC_RESULTS_CHANGED (item)   a result arrived, or all were cleared (item nil)

local ALC = ALC
local L = ALC.L

local Debug = ALC.Debug

local Results = {}
ALC.Results = Results

local results = {} -- item number -> { state, rows }

local function copyRows(rows)
	local copy = {}
	for i, r in ipairs(rows) do
		local rerolls
		if r.rerolls then
			rerolls = {}
			for j, n in ipairs(r.rerolls) do rerolls[j] = n end
		end
		copy[i] = { name = r.name, answer = r.answer, roll = r.roll, rerolls = rerolls, outcome = r.outcome, via = r.via, reserved = r.reserved }
	end
	return copy
end

local function clear()
	if next(results) == nil then return end
	results = {}
	ALC.Events:Fire("ALC_RESULTS_CHANGED", nil)
end

-- Loot master: sends the rows of an item to the group. Returns true, or false and a message.
function Results:Publish(item, state, rows)
	local session = ALC.Sessions:GetSession()
	if not session then return false, L["There is no active session."] end
	if not session.isLM or not ALC.Council:AmLootMaster() then return false, L["Only the loot master can do that."] end
	if not session.items[item] then return false, L["That item is not in the session."] end
	if type(rows) ~= "table" then return false, L["The result has no rows."] end
	if not ALC.Comm:SendRaid("RESULT", session.sid, { item = item, state = state, rows = copyRows(rows) }) then
		return false, L["Could not send the result. See /alc debug log."]
	end
	return true
end

-- The rows of an item (a copy), the state, or nil when there is no result for the item.
function Results:Get(item)
	local r = results[item or 1]
	if not r then return nil end
	return copyRows(r.rows), r.state
end

-- The item numbers that have a result, in order.
function Results:GetItems()
	local list = {}
	for item in pairs(results) do list[#list + 1] = item end
	table.sort(list)
	return list
end

function Results:HasAny()
	return next(results) ~= nil
end

local function onResult(_, _, _, p)
	local session = ALC.Sessions:GetSession()
	if not session or not session.items[p.item] then
		Debug:Warn("Results", "ignored a result for item %d, which is not in the session", p.item)
		return
	end
	results[p.item] = { state = p.state, rows = copyRows(p.rows) }
	Debug:Log("Results", "item %d: %d rows (%s)", p.item, #p.rows, p.state)
	ALC.Events:Fire("ALC_RESULTS_CHANGED", p.item)
end

function Results:Init()
	local register = ALC.Events.Register
	register(self, "ALC_COMM_RESULT", onResult)
	register(self, "ALC_SESSION_STARTED", function(_, _, restored)
		if not restored then clear() end
	end)
	register(self, "ALC_SESSION_ENDED", function() clear() end)
end

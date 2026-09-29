-- Protocol: the message type table (see ROADMAP.md) and per-type payload validators.
-- Pure data and functions; no networking. Validators return `true` or `false, reason`.
--
-- Spec fields:
--   allowed  "group" (any group member) | "lm" (loot master) | "council"
--   channel  "GROUP" (RAID/PARTY broadcast) | "WHISPER"
--   sid      "none" (must be nil) | "new" (any string; the receiver decides) | "active" (must match the active session)
--   seq      true when the loot master stamps a sequence number on it
--   validate function(payload, sender) -> ok, reason

local ALC = ALC

local type, ipairs, pairs = type, ipairs, pairs
local strfind, strmatch, floor = string.find, string.match, math.floor
local SameName = function(a, b) return ALC:SameName(a, b) end

local C = ALC.Constants

local Protocol = {}
ALC.Protocol = Protocol

Protocol.VERSION = ALC.PROTOCOL_VERSION
Protocol.MAX_SID_LENGTH = 64

local RESPONSE_SET = {}
for _, id in ipairs(C.RESPONSE_IDS) do RESPONSE_SET[id] = true end

-- Overridable so tests can run without the game client.
function Protocol.itemExists(itemID)
	local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	if not info then return true end
	return info(itemID) ~= nil
end

--------------------------------------------------------------------------------
-- Field helpers
--------------------------------------------------------------------------------
local function isInt(v, min, max)
	return type(v) == "number" and v == floor(v) and v >= min and v <= max
end

-- Text that ends up in the UI: no control characters and no `|` escape sequences.
local function isText(v, minLen, maxLen)
	return type(v) == "string" and #v >= minLen and #v <= maxLen and not strfind(v, "[%c|]")
end

local function isName(v) return isText(v, 2, 48) end

local function isArray(t, maxN)
	if type(t) ~= "table" then return false end
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n == #t and n <= maxN
end

local function isItemString(s)
	return type(s) == "string" and #s <= 120 and strmatch(s, "^item:%-?%d+[%d:%-]*$") ~= nil
end

local function itemStringID(s)
	return tonumber(strmatch(s, "^item:(%-?%d+)"))
end

local function isResponse(v) return type(v) == "string" and RESPONSE_SET[v] == true end

local function fail(reason) return false, reason end

local function checkItem(p)
	if not isInt(p.itemID, 1, 9999999) then return fail("bad itemID") end
	if not Protocol.itemExists(p.itemID) then return fail("unknown itemID") end
	return true
end

-- Which item of the session a message is about (1 = the first).
local function checkItemIndex(p)
	if not isInt(p.item, 1, C.MAX_SESSION_ITEMS) then return fail("bad item index") end
	return true
end

-- The items of a session: { itemID, itemString [, winner] } each. `winner` is only set on
-- items that were already awarded (a snapshot for a player who joined late or reloaded).
local function checkItems(items)
	if not isArray(items, C.MAX_SESSION_ITEMS) or #items == 0 then return fail("bad items list") end
	for _, item in ipairs(items) do
		if type(item) ~= "table" then return fail("bad item") end
		local ok, reason = checkItem(item)
		if not ok then return fail(reason) end
		if not isItemString(item.itemString) or itemStringID(item.itemString) ~= item.itemID then
			return fail("itemString does not match itemID")
		end
		if item.winner ~= nil and not isName(item.winner) then return fail("bad winner") end
	end
	return true
end

local function checkGear(gear)
	if not isArray(gear, C.MAX_GEAR_ITEMS) then return fail("bad gear list") end
	for _, s in ipairs(gear) do
		if not isItemString(s) then return fail("bad gear itemString") end
	end
	return true
end

local function checkNameList(list, max, field)
	if not isArray(list, max) then return fail("bad " .. field) end
	for _, name in ipairs(list) do
		if not isName(name) then return fail("bad name in " .. field) end
	end
	return true
end

local function checkCandidate(c)
	if type(c) ~= "table" then return fail("bad candidate") end
	local ok, reason = checkItemIndex(c)
	if not ok then return fail(reason) end
	if not isName(c.name) then return fail("bad candidate name") end
	if not (type(c.class) == "string" and #c.class <= 16 and strmatch(c.class, "^%u+$")) then
		return fail("bad candidate class")
	end
	if not isResponse(c.response) then return fail("bad candidate response") end
	return checkGear(c.gear)
end

local function checkVoters(voters)
	return checkNameList(voters, C.MAX_COUNCIL, "voters")
end

--------------------------------------------------------------------------------
-- Message specs
--------------------------------------------------------------------------------
local specs = {}
Protocol.specs = specs

specs.SESSION_START = {
	allowed = "lm", channel = "GROUP", sid = "new", seq = true,
	validate = function(p, sender)
		local ok, reason = checkItems(p.items)
		if not ok then return fail(reason) end
		ok, reason = checkNameList(p.council, C.MAX_COUNCIL, "council")
		if not ok then return fail(reason) end
		if not isName(p.lm) or not SameName(p.lm, sender) then return fail("lm does not match sender") end
		return true
	end,
}

specs.SESSION_CANCEL = {
	allowed = "lm", channel = "GROUP", sid = "active", seq = true,
	validate = function(p)
		if not isText(p.reason, 1, 64) then return fail("bad reason") end
		return true
	end,
}

specs.RESPONSE = {
	allowed = "group", channel = "WHISPER", sid = "active", seq = false,
	validate = function(p)
		local ok, reason = checkItemIndex(p)
		if not ok then return fail(reason) end
		if not isResponse(p.response) then return fail("bad response") end
		return checkGear(p.gear)
	end,
}

specs.CANDIDATE_UPDATE = {
	allowed = "lm", channel = "WHISPER", sid = "active", seq = true,
	validate = checkCandidate,
}

specs.VOTE = {
	allowed = "council", channel = "WHISPER", sid = "active", seq = false,
	validate = function(p)
		local ok, reason = checkItemIndex(p)
		if not ok then return fail(reason) end
		if p.candidate ~= nil and not isName(p.candidate) then return fail("bad candidate") end
		return true
	end,
}

specs.VOTE_UPDATE = {
	allowed = "lm", channel = "WHISPER", sid = "active", seq = true,
	validate = function(p)
		local ok, reason = checkItemIndex(p)
		if not ok then return fail(reason) end
		if not isName(p.candidate) then return fail("bad candidate") end
		ok, reason = checkVoters(p.voters)
		if not ok then return fail(reason) end
		if not isInt(p.votes, 0, C.MAX_COUNCIL) or p.votes ~= #p.voters then
			return fail("votes does not match voters")
		end
		return true
	end,
}

specs.AWARD = {
	allowed = "lm", channel = "GROUP", sid = "active", seq = true,
	validate = function(p)
		local ok, reason = checkItemIndex(p)
		if not ok then return fail(reason) end
		ok, reason = checkItem(p)
		if not ok then return fail(reason) end
		if not isName(p.winner) then return fail("bad winner") end
		if not isResponse(p.response) then return fail("bad response") end
		return true
	end,
}

specs.STATE_REQUEST = {
	allowed = "group", channel = "WHISPER", sid = "none", seq = false,
	validate = function() return true end,
}

-- Raiders get item, council and lm; council members additionally get candidates and votes.
-- `yourResponse` / `yourVote` restore the receiver's own choices after a reload.
specs.STATE_SNAPSHOT = {
	allowed = "lm", channel = "WHISPER", sid = "new", seq = true,
	validate = function(p, sender)
		local ok, reason = specs.SESSION_START.validate(p, sender)
		if not ok then return fail(reason) end
		if p.candidates ~= nil then
			if not isArray(p.candidates, C.MAX_CANDIDATES * C.MAX_SESSION_ITEMS) then return fail("bad candidates") end
			for _, c in ipairs(p.candidates) do
				ok, reason = checkCandidate(c)
				if not ok then return fail(reason) end
			end
		end
		if p.votes ~= nil then
			if not isArray(p.votes, C.MAX_CANDIDATES * C.MAX_SESSION_ITEMS) then return fail("bad votes") end
			for _, v in ipairs(p.votes) do
				if type(v) ~= "table" then return fail("bad vote entry") end
				ok, reason = checkItemIndex(v)
				if not ok then return fail(reason) end
				if not isName(v.candidate) then return fail("bad vote entry") end
				ok, reason = checkVoters(v.voters)
				if not ok then return fail(reason) end
			end
		end
		-- What the receiver itself answered and voted, one entry per item.
		if p.yourResponses ~= nil then
			if not isArray(p.yourResponses, C.MAX_SESSION_ITEMS) then return fail("bad yourResponses") end
			for _, r in ipairs(p.yourResponses) do
				if type(r) ~= "table" or not checkItemIndex(r) or not isResponse(r.response) then return fail("bad yourResponses entry") end
			end
		end
		if p.yourVotes ~= nil then
			if not isArray(p.yourVotes, C.MAX_SESSION_ITEMS) then return fail("bad yourVotes") end
			for _, v in ipairs(p.yourVotes) do
				if type(v) ~= "table" or not checkItemIndex(v) or not isName(v.candidate) then return fail("bad yourVotes entry") end
			end
		end
		return true
	end,
}

-- Addon version discovery for `/alc debug versions`. Not part of a session.
specs.VERSION_REQUEST = {
	allowed = "group", channel = "GROUP", sid = "none", seq = false,
	validate = function() return true end,
}

specs.VERSION = {
	allowed = "group", channel = "WHISPER", sid = "none", seq = false,
	validate = function(p)
		if not isText(p.addon, 1, 24) then return fail("bad addon version") end
		if not isInt(p.proto, 0, 9999) then return fail("bad protocol version") end
		return true
	end,
}

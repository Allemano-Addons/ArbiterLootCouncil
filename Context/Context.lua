-- Context: what the council wants to know about a candidate besides what is on the row: what the player has been
-- awarded before, in which slot, when, and anything an addon built on ALC adds (Soft Reserve: did they reserve it).
-- Presentation is the ContextWindow's; this module works the facts out.
--
-- The award log is the loot master's, so the loot master reads the history from it. A council member asks the loot master
-- for one player's history (HISTORY_REQUEST) and gets it back (HISTORY, at most MAX_HISTORY_ENTRIES awards, newest
-- first, with the start of the raid night) and keeps it for the session. Nothing is sent about players nobody looked at.
--
-- Events:
--   ALC_CONTEXT_CHANGED ()   a player's history arrived (a council member's copy), or went stale

local ALC = ALC
local L = ALC.L

local Debug = ALC.Debug

local strlower = string.lower
local time = time

local Context = {}
ALC.Context = Context

local DAY = 86400
local NIGHT_GAP = 4 * 3600  -- awards less than this apart are one raid night ("Tonight")
local REQUEST_WAIT = 15     -- seconds before the same player's history is asked for again

local cache = {}            -- lowercase name -> { entries, total, nightStart, at } (a council member's copy)
local requested = {}        -- lowercase name -> when it was asked for

--------------------------------------------------------------------------------
-- Slots
--------------------------------------------------------------------------------
-- INVTYPE_* -> the slot group an item belongs to for "the same slot" (a weapon is a weapon whichever hand it goes in).
local SLOT_GROUP = {
	INVTYPE_HEAD = "head", INVTYPE_NECK = "neck", INVTYPE_SHOULDER = "shoulder",
	INVTYPE_CHEST = "chest", INVTYPE_ROBE = "chest", INVTYPE_WAIST = "waist", INVTYPE_LEGS = "legs",
	INVTYPE_FEET = "feet", INVTYPE_WRIST = "wrist", INVTYPE_HAND = "hands",
	INVTYPE_FINGER = "finger", INVTYPE_TRINKET = "trinket", INVTYPE_CLOAK = "back",
	INVTYPE_WEAPON = "weapon", INVTYPE_2HWEAPON = "weapon", INVTYPE_WEAPONMAINHAND = "weapon", INVTYPE_WEAPONOFFHAND = "weapon",
	INVTYPE_SHIELD = "offhand", INVTYPE_HOLDABLE = "offhand",
	INVTYPE_RANGED = "ranged", INVTYPE_RANGEDRIGHT = "ranged", INVTYPE_THROWN = "ranged", INVTYPE_RELIC = "ranged",
}

local SLOT_LABEL = {
	head = L["Head"], neck = L["Neck"], shoulder = L["Shoulders"], chest = L["Chest"], waist = L["Waist"], legs = L["Legs"],
	feet = L["Feet"], wrist = L["Wrists"], hands = L["Hands"], finger = L["Ring"], trinket = L["Trinket"], back = L["Back"],
	weapon = L["Weapon"], offhand = L["Off-hand"], ranged = L["Ranged"],
}

-- The slot group of an item (id, link or itemString): "weapon", "head" ... or nil when it is not worn (or not known yet).
function Context.SlotOf(item)
	local _, _, _, equipLoc = ALC:GetItemInfoInstant(item)
	return equipLoc and SLOT_GROUP[equipLoc] or nil
end

function Context.SlotLabel(slot)
	return slot and SLOT_LABEL[slot] or nil
end

--------------------------------------------------------------------------------
-- The award log: the loot master's view of one player
--------------------------------------------------------------------------------
-- The awards of a player, newest first. (The log is in the order things happened, but a restored backup or a changed clock
-- can break that, so the time decides.)
local function logEntries(name, limit)
	local list = {}
	local log = ALC.Awards and ALC.Awards:GetLog() or {}
	for i = 1, #log do
		local r = log[i]
		if r.winner and ALC:SameName(r.winner, name) and not r.revoked and not ALC:IsSpecialResponse(r.response) and r.time then
			list[#list + 1] = {
				itemID = r.itemID, itemString = r.itemString,
				label = r.responseLabel or (ALC.Responses and ALC.Responses:GetLabel(r.response)) or "",
				color = r.responseColor, time = r.time, zone = r.zone, index = i,
			}
		end
	end
	table.sort(list, function(a, b)
		if a.time ~= b.time then return a.time > b.time end
		return a.index > b.index
	end)
	while #list > limit do list[#list] = nil end
	return list
end

-- When the current raid night began: the first award of the run of awards (all players) that ends now, where a gap of
-- NIGHT_GAP between two awards starts a new night. nil when nothing was awarded in the last NIGHT_GAP.
function Context.NightStart(now)
	now = now or time()
	local log = ALC.Awards and ALC.Awards:GetLog() or {}
	local times = {}
	for i = 1, #log do
		local r = log[i]
		if r.time and not r.revoked and not ALC:IsSpecialResponse(r.response) then times[#times + 1] = r.time end
	end
	table.sort(times, function(a, b) return a > b end)
	local start, previous = nil, now
	for _, t in ipairs(times) do
		if previous - t > NIGHT_GAP then break end
		start, previous = t, t
	end
	return start
end

--------------------------------------------------------------------------------
-- The loot master answers a council member's request
--------------------------------------------------------------------------------
-- The payload of HISTORY for a player: their awards (newest first) and when the raid night began.
function Context:BuildHistory(name)
	local entries = logEntries(name, 1000)
	local total = #entries
	local kept = {}
	for i = 1, math.min(total, ALC.Constants.MAX_HISTORY_ENTRIES) do
		local e = entries[i]
		local zone = e.zone
		if type(zone) ~= "string" or zone == "" then zone = nil else zone = string.sub(zone, 1, ALC.Constants.MAX_HISTORY_ZONE) end
		local color = type(e.color) == "string" and string.match(e.color, "^%x%x%x%x%x%x$") and e.color or nil
		if not color and type(e.color) == "table" then
			color = string.format("%02x%02x%02x", math.floor((e.color[1] or 0) * 255 + 0.5), math.floor((e.color[2] or 0) * 255 + 0.5), math.floor((e.color[3] or 0) * 255 + 0.5))
		end
		kept[#kept + 1] = {
			itemID = e.itemID, label = string.sub(e.label ~= "" and e.label or "?", 1, ALC.Constants.MAX_RESPONSE_LABEL),
			color = color, time = e.time, zone = zone,
		}
	end
	return { name = name, entries = kept, total = total, nightStart = Context.NightStart() }
end

local function onHistoryRequest(_, sender, _, p)
	local session = ALC.Sessions:GetSession()
	if not session or not session.isLM then return end
	ALC.Comm:SendWhisper(sender, "HISTORY", session.sid, Context:BuildHistory(p.name))
end

--------------------------------------------------------------------------------
-- A council member keeps what arrives
--------------------------------------------------------------------------------
local function onHistory(_, _, _, p)
	cache[strlower(p.name)] = {
		entries = p.entries, total = p.total, nightStart = p.nightStart, at = time(),
	}
	ALC.Events:Fire("ALC_CONTEXT_CHANGED")
end

local function forget()
	cache, requested = {}, {}
	ALC.Events:Fire("ALC_CONTEXT_CHANGED")
end

-- Asks the loot master for a player's history (a council member; the loot master reads its own log). Returns true when the
-- question was sent, false when it was not needed, was sent a moment ago, or could not be.
function Context:Request(name)
	local session = ALC.Sessions:GetSession()
	if not session or session.isLM or not name then return false end
	local key = strlower(name)
	local now = GetTime()
	if requested[key] and now - requested[key] < REQUEST_WAIT then return false end
	requested[key] = now
	return ALC.Comm:SendWhisper(session.lm, "HISTORY_REQUEST", session.sid, { name = name }) and true or false
end

-- True while a council member waits for a player's history.
function Context:IsWaiting(name)
	local session = ALC.Sessions:GetSession()
	if not session or session.isLM or not name then return false end
	return cache[strlower(name)] == nil and requested[strlower(name)] ~= nil
end

--------------------------------------------------------------------------------
-- Providers: other addons add lines (Soft Reserve: "Reserved this item")
--------------------------------------------------------------------------------
local providers = {} -- in the order they were added

-- ALC.RegisterContextProvider({ id, title, color, lines = function(name, info) -> { { label, text, color }, ... } or nil })
function ALC.RegisterContextProvider(def)
	if type(def) ~= "table" or type(def.id) ~= "string" or def.id == "" then return false, "The provider needs an id." end
	if type(def.title) ~= "string" or def.title == "" then return false, "The provider needs a title." end
	if type(def.lines) ~= "function" then return false, "The provider needs a lines function." end
	local provider = { id = def.id, title = def.title, color = type(def.color) == "string" and def.color or nil, lines = def.lines }
	for i, existing in ipairs(providers) do
		if existing.id == def.id then
			providers[i] = provider
			return true
		end
	end
	providers[#providers + 1] = provider
	return true
end

function ALC.UnregisterContextProvider(id)
	for i, existing in ipairs(providers) do
		if existing.id == id then table.remove(providers, i) return end
	end
end

--------------------------------------------------------------------------------
-- What the window shows
--------------------------------------------------------------------------------
local function dateText(t)
	return date("%Y-%m-%d", t)
end

-- A when-tag for an award time: "tonight" (this raid night), "week" (within seven days) or "older".
local function whenTag(t, nightStart, now)
	if nightStart and t >= nightStart then return "tonight" end
	if now - t <= 7 * DAY then return "week" end
	return "older"
end

-- Everything about a candidate for the item of the session the council is looking at.
-- Returns a table (see below), or nil when the candidate is not in the session.
--   name, class, rank, response (id), label, color, waiting, roll, note, votes, voters,
--   item = { itemString, itemID, name, ilvl, slot, slotLabel }, gear = { { itemString, name, ilvl, quality } },
--   ilvlDelta (the item's level against the lowest level of what it would replace, or nil), emptySlot,
--   history = { { itemID, itemString, name, quality, label, color, time, zone, tag, sameSlot, sameItem } } newest first,
--   total (how many awards the player has in all), sameSlot (the entries of the same slot), sameItem (the entries of this item),
--   counts = { [7] = n, [14] = n, [30] = n }, lastAgo (days since the last award), complete (false while the history is on its way),
--   providers = { { id, title, color, lines } }
function Context:Build(name, itemIndex)
	local session = ALC.Sessions:GetSession()
	if not session or not name then return nil end
	itemIndex = itemIndex or 1
	local target = session.items[itemIndex]
	local entry = ALC.Candidates:Get(name, itemIndex)
	local info = { name = (entry and entry.name) or name, class = entry and entry.class, waiting = entry == nil }
	if entry then
		info.rank, info.rankIndex, info.roll, info.note, info.response = entry.rank, entry.rankIndex, entry.roll, entry.note, entry.response
		local response = ALC.Responses:Get(entry.response)
		info.label = response and response.label or entry.response
		info.color = response and response.color or nil
	end
	local count, voters = ALC.Voting:GetVotes(info.name, itemIndex)
	info.votes, info.voters = count or 0, voters or {}

	-- the item
	if target then
		local _, _, _, ilvl = ALC:GetItemInfo(target.itemString)
		local display = ALC.LootDetection:GetItemDisplay({ itemString = target.itemString, itemID = target.itemID })
		info.item = { itemString = target.itemString, itemID = target.itemID, name = display.name, quality = display.quality, ilvl = ilvl, slot = Context.SlotOf(target.itemString) }
		info.item.slotLabel = Context.SlotLabel(info.item.slot)
	end

	-- what the player has on in that slot, and how the item compares
	info.gear = {}
	local lowest
	for _, itemString in ipairs(entry and entry.gear or {}) do
		local _, gID = ALC:ParseItem(itemString)
		local gDisplay = gID and ALC.LootDetection:GetItemDisplay({ itemString = itemString, itemID = gID }) or {}
		local _, _, _, gIlvl = ALC:GetItemInfo(itemString)
		local gName, quality = gDisplay.name, gDisplay.quality
		info.gear[#info.gear + 1] = { itemString = itemString, name = gName, ilvl = gIlvl, quality = quality }
		if gIlvl and (not lowest or gIlvl < lowest) then lowest = gIlvl end
	end
	info.emptySlot = entry ~= nil and #info.gear == 0
	if info.item and info.item.ilvl and lowest then info.ilvlDelta = info.item.ilvl - lowest end

	-- the history
	local now = time()
	local raw, total, nightStart, complete
	if session.isLM then
		raw = logEntries(info.name, 200)
		total, nightStart, complete = #raw, Context.NightStart(now), true
	else
		local cached = cache[strlower(info.name)]
		if cached then
			raw, total, nightStart, complete = cached.entries, cached.total or #cached.entries, cached.nightStart, true
		else
			raw, total, nightStart, complete = {}, 0, nil, false
		end
	end
	info.history, info.sameSlot, info.sameItem = {}, {}, {}
	info.counts = { [7] = 0, [14] = 0, [30] = 0 }
	for _, r in ipairs(raw) do
		local slot = r.itemID and Context.SlotOf(r.itemID) or nil
		-- the name and quality; asks the game for an item it has not got (the window draws again when it arrives)
		local itemName, quality
		if r.itemID then
			local display = ALC.LootDetection:GetItemDisplay({ itemString = r.itemString or ("item:" .. r.itemID), itemID = r.itemID })
			itemName, quality = display.name, display.quality
		end
		local h = {
			itemID = r.itemID, itemString = r.itemString, name = itemName, quality = quality, slot = slot,
			label = r.label, color = r.color, time = r.time, zone = r.zone,
			tag = whenTag(r.time, nightStart, now),
			sameSlot = info.item and info.item.slot ~= nil and slot == info.item.slot or false,
			sameItem = info.item and r.itemID == info.item.itemID or false,
		}
		h.dateText = dateText(r.time)
		info.history[#info.history + 1] = h
		if h.sameSlot then info.sameSlot[#info.sameSlot + 1] = h end
		if h.sameItem then info.sameItem[#info.sameItem + 1] = h end
		for days in pairs(info.counts) do
			if now - r.time <= days * DAY then info.counts[days] = info.counts[days] + 1 end
		end
	end
	info.total, info.complete = total, complete
	info.lastAgo = info.history[1] and math.max(0, math.floor((now - info.history[1].time) / DAY)) or nil

	-- what addons built on ALC know
	info.providers = {}
	-- The session itself can say who reserved the item (Soft Reserve sends mark and markFor with every item, to everybody)
	local extra = target and target.extra
	if type(extra) == "table" and type(extra.mark) == "string" and type(extra.markFor) == "table" then
		local first = strlower(string.match(info.name, "^(%S+)") or info.name)
		local reserved = false
		for _, listed in ipairs(extra.markFor) do
			if ALC:SameName(listed, info.name) or (not string.find(listed, " ", 1, true) and strlower(listed) == first) then reserved = true break end
		end
		local brandColor = session.modeColor and string.match(session.modeColor, "^%x%x%x%x%x%x$") and session.modeColor or nil
		info.providers[#info.providers + 1] = {
			id = "mark", title = session.modeName or extra.mark, color = brandColor,
			lines = { {
				label = L["Reserved this item"],
				text = reserved and string.format(L["Yes (%s, one of %d)"], extra.mark, #extra.markFor) or string.format(L["No (%d reserved it)"], #extra.markFor),
				color = reserved and brandColor or nil,
			} },
		}
	end
	for _, provider in ipairs(providers) do
		local ok, lines = pcall(provider.lines, info.name, info)
		if ok and type(lines) == "table" and #lines > 0 then
			info.providers[#info.providers + 1] = { id = provider.id, title = provider.title, color = provider.color, lines = lines }
		end
	end
	return info
end

function Context:Init()
	local register = ALC.Events.Register
	register(self, "ALC_COMM_HISTORY_REQUEST", onHistoryRequest)
	register(self, "ALC_COMM_HISTORY", onHistory)
	register(self, "ALC_SESSION_STARTED", function(_, _, restored) if not restored then forget() end end)
	register(self, "ALC_SESSION_ENDED", forget)
	-- A new award changes everybody's history: ask again for what the window shows
	register(self, "ALC_COMM_AWARD", forget)
end

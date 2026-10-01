-- LootDetection: the loot master's list of items to hand out (the "loot window" data).
--
-- Items arrive from loot windows (only while grouped and loot master), from
-- `/alc add`, and from sessions started by hand. Each item has a status:
--   pending   waiting for a session
--   session   a session is running for it
--   awarded   handed out
--   trade     awarded but still to be traded (set by Awards)
-- The list is saved so it survives a /reload (see MAX_AGE).
--
-- Events:
--   ALC_LOOT_CHANGED ()          the list, a status or the item data changed
--   ALC_LOOT_ADDED   (count)     new items were added

local ALC = ALC
local LibStub = LibStub
local L = ALC.L

local Debug = ALC.Debug

local strmatch, strlower, format = string.match, string.lower, string.format
local time, GetTime = time, GetTime

local LootDetection = {}
ALC.LootDetection = LootDetection
LibStub("AceEvent-3.0"):Embed(LootDetection)

local STATUS = { PENDING = "pending", SESSION = "session", AWARDED = "awarded", TRADE = "trade" }
LootDetection.STATUS = STATUS

local MAX_AGE = 8 * 3600      -- a saved list older than this is dropped
local MAX_SEEN = 300          -- remembered loot slots, to ignore a re-opened corpse
local ENCOUNTER_MEMORY = 900  -- seconds an encounter name is used for loot

local store                   -- the saved table (Settings:GetLootStore)
local encounter               -- { name, at } of the last boss kill
local requested = {}          -- item ids we asked the client to load
local waitingForInfo = false
local refreshQueued = false

--------------------------------------------------------------------------------
-- Item helpers
--------------------------------------------------------------------------------
local COLOR_QUALITY = {
	["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3,
	["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6, ["00ccff"] = 7,
}

-- Quality from the colour code of an item link, nil when it has none.
function LootDetection.QualityFromLink(link)
	if type(link) ~= "string" then return nil end
	local q = strmatch(link, "|cnIQ(%d):")
	if q then return tonumber(q) end
	local hex = strmatch(link, "|c%x%x(%x%x%x%x%x%x)")
	return hex and COLOR_QUALITY[strlower(hex)] or nil
end

local function itemQuality(itemString, link)
	local quality = select(3, ALC:GetItemInfo(link or itemString))
	return quality or LootDetection.QualityFromLink(link)
end

local SLOT_NAMES = _G -- INVTYPE_* strings live in the global table

-- What the window shows for an item; asks the client for data it does not have yet.
function LootDetection:GetItemDisplay(entry)
	local name, link, quality, _, _, itemType, subType, _, equipLoc, icon = ALC:GetItemInfo(entry.itemString)
	local _, instantType, instantSub, instantEquip, instantIcon = ALC:GetItemInfoInstant(entry.itemString)
	equipLoc = equipLoc or instantEquip
	subType = subType or instantSub
	itemType = itemType or instantType

	if not name then
		waitingForInfo = true
		if not requested[entry.itemID] then
			requested[entry.itemID] = true
			ALC:RequestItemData(entry.itemID)
		end
	end
	if quality and not entry.quality then entry.quality = quality end

	local parts = {}
	-- Items that cannot be worn have an empty slot name; an empty string must not count.
	local slot = equipLoc and equipLoc ~= "" and SLOT_NAMES[equipLoc]
	if type(slot) ~= "string" or slot == "" then slot = nil end
	if slot then parts[#parts + 1] = slot end
	local kind = subType and subType ~= "" and subType or itemType
	if kind and kind ~= "Miscellaneous" and kind ~= slot then parts[#parts + 1] = kind end

	return {
		name = name,
		link = link,
		quality = entry.quality,
		icon = icon or instantIcon,
		subtitle = table.concat(parts, " \194\183 "), -- middle dot
	}
end

--------------------------------------------------------------------------------
-- List
--------------------------------------------------------------------------------
local function changed()
	ALC.Events:Fire("ALC_LOOT_CHANGED")
end

local function find(id)
	for _, entry in ipairs(store.items) do
		if entry.id == id then return entry end
	end
end

-- The entry of one item of a session (item 1 when none is named).
local function findBySid(sid, item)
	for _, entry in ipairs(store.items) do
		if entry.sid == sid and (entry.item or 1) == (item or 1) then return entry end
	end
end

local function copyEntry(entry)
	local copy = {}
	for k, v in pairs(entry) do copy[k] = v end
	return copy
end

function LootDetection:GetItems()
	local list = {}
	for i, entry in ipairs(store.items) do list[i] = copyEntry(entry) end
	return list
end

function LootDetection:GetEntry(id)
	local entry = find(id)
	return entry and copyEntry(entry) or nil
end

function LootDetection:GetHiddenCount() return store.hidden end
function LootDetection:GetBossName() return store.boss end

local function newEntry(itemString, itemID, quality, source)
	store.nextId = store.nextId + 1
	local entry = {
		id = store.nextId,
		itemString = itemString,
		itemID = itemID,
		quality = quality,
		source = source,
		status = STATUS.PENDING,
		addedAt = time(),
	}
	store.items[#store.items + 1] = entry
	store.savedAt = time()
	return entry
end

local function removeWhere(predicate)
	local kept, removed = {}, 0
	for _, entry in ipairs(store.items) do
		if predicate(entry) then removed = removed + 1 else kept[#kept + 1] = entry end
	end
	if removed > 0 then
		for i = #store.items, 1, -1 do store.items[i] = nil end
		for i, entry in ipairs(kept) do store.items[i] = entry end
		if #kept == 0 then store.hidden = 0 end
		changed()
	end
	return removed
end

-- Adds one or more items typed by hand (links, itemStrings or ids).
-- Returns the number added and a message when none could be read.
function LootDetection:AddFromText(text)
	local found = ALC:ParseItems(text)
	if #found == 0 then return 0, L["No item found. Use /alc add [item link] or an item id."] end
	for _, item in ipairs(found) do
		newEntry(item.itemString, item.itemID, itemQuality(item.itemString, item.link), "manual")
	end
	changed()
	ALC.Events:Fire("ALC_LOOT_ADDED", #found)
	return #found
end

function LootDetection:Remove(id)
	local entry = find(id)
	if not entry or entry.status == STATUS.SESSION then return false end
	return removeWhere(function(e) return e == entry end) > 0
end

function LootDetection:ClearFinished()
	return removeWhere(function(e) return e.status == STATUS.AWARDED end)
end

-- Removes everything except an item that is in a session.
function LootDetection:Clear()
	return removeWhere(function(e) return e.status ~= STATUS.SESSION end)
end

function LootDetection:SetStatus(id, status)
	local entry = find(id)
	if not entry then return false end
	entry.status = status
	changed()
	return true
end

--------------------------------------------------------------------------------
-- Starting a session from the list
--------------------------------------------------------------------------------
local function clearStarting()
	for _, entry in ipairs(store.items) do entry.starting = nil end
end

function LootDetection:StartSession(id)
	local entry = find(id)
	if not entry then return false, L["That item is no longer in the list."] end
	if entry.status ~= STATUS.PENDING then return false, L["That item is not waiting for a session."] end
	entry.starting = true
	local ok, result = ALC.Sessions:Start(entry.itemString)
	if not ok then
		entry.starting = nil
		return false, result
	end
	return true
end

-- The items that wait for a session, in list order.
function LootDetection:GetPending()
	local list = {}
	for _, entry in ipairs(store.items) do
		if entry.status == STATUS.PENDING then list[#list + 1] = copyEntry(entry) end
	end
	return list
end

-- Starts one session for every item that waits (at most as many as a session holds).
function LootDetection:StartAll()
	local max = ALC.Constants.MAX_SESSION_ITEMS
	local entries, strings = {}, {}
	for _, entry in ipairs(store.items) do
		if entry.status == STATUS.PENDING and #entries < max then
			entries[#entries + 1] = entry
			strings[#strings + 1] = entry.itemString
		end
	end
	if #entries == 0 then return false, L["No items are waiting for a session."] end
	for _, entry in ipairs(entries) do entry.starting = true end
	local ok, result = ALC.Sessions:StartItems(strings)
	if not ok then
		clearStarting()
		return false, result
	end
	return true, #entries
end

-- Ties the items of a running session to list entries. Item by item: the entry that was
-- being started (in order), else a waiting entry of the same kind, else a new entry (a
-- session started by /alc start or /alc test).
local function onSessionStarted(_, session)
	if not session.isLM then return end
	-- A session restored after a reload belongs to the entries that started it.
	local restoredAny = false
	for i = 1, #session.items do
		local restored = findBySid(session.sid, i)
		if restored then
			restored.starting = nil
			if not session.items[i].winner and restored.status ~= STATUS.AWARDED and restored.status ~= STATUS.TRADE then
				restored.status = STATUS.SESSION
			end
			restoredAny = true
		end
	end
	if restoredAny then
		changed()
		return
	end

	local starting = {}
	for _, entry in ipairs(store.items) do
		if entry.starting then starting[#starting + 1] = entry end
	end
	local used, created = {}, 0
	for i, item in ipairs(session.items) do
		local target = table.remove(starting, 1)
		if not target then
			for _, entry in ipairs(store.items) do
				if entry.status == STATUS.PENDING and entry.itemID == item.itemID and not used[entry] then target = entry break end
			end
		end
		if not target then
			target = newEntry(item.itemString, item.itemID, itemQuality(item.itemString), "session")
			created = created + 1
		end
		used[target] = true
		target.starting = nil
		target.status = STATUS.SESSION
		target.sid = session.sid
		target.item = i
	end
	clearStarting()
	changed()
	if created > 0 then ALC.Events:Fire("ALC_LOOT_ADDED", created) end
end

-- An awarded item is "awarded", or "trade" while it still has to be traded to the winner.
local function awardedStatus(entry)
	return entry.trade and STATUS.TRADE or STATUS.AWARDED
end

-- Items still in the session go back to waiting, unless they were all awarded.
local function onSessionEnded(_, sid, reason)
	local touched = false
	for _, entry in ipairs(store.items) do
		if entry.sid == sid then
			entry.starting = nil
			if entry.status == STATUS.SESSION then
				entry.status = (reason == "awarded") and awardedStatus(entry) or STATUS.PENDING
				if entry.status == STATUS.PENDING then entry.sid, entry.item = nil, nil end
			end
			touched = true
		end
	end
	if touched then changed() end
end

local function onAward(_, _, sid, p)
	local entry = findBySid(sid, p.item)
	if not entry then return end
	entry.winner = p.winner
	entry.awardedAt = time()
	entry.status = awardedStatus(entry)
	changed()
end

-- The award was taken back: the item is open in the session again and leaves the trade queue.
local function onAwardRevoke(_, _, sid, p)
	local entry = findBySid(sid, p.item)
	if not entry then return end
	entry.winner, entry.awardedAt, entry.trade = nil, nil, nil
	entry.status = STATUS.SESSION
	changed()
end

-- The item of this session has to be traded to the winner (Awards calls this when it
-- could not be handed out through the loot window). Works before or after the AWARD
-- message is handled.
function LootDetection:MarkAwaitingTrade(sid, item)
	local entry = findBySid(sid, item)
	if not entry then return false end
	entry.trade = true
	if entry.status == STATUS.AWARDED then entry.status = STATUS.TRADE end
	changed()
	return true
end

--------------------------------------------------------------------------------
-- Loot windows
--------------------------------------------------------------------------------
local function currentBossName()
	if encounter and GetTime() - encounter.at < ENCOUNTER_MEMORY then return encounter.name end
	if UnitExists("target") and UnitIsDead("target") then return UnitName("target") end
	return GetZoneText and GetZoneText() or nil
end

-- A boss kill names the loot that follows.
function LootDetection:OnEncounterEnd(name, success)
	if success == 1 and type(name) == "string" then encounter = { name = name, at = GetTime() } end
end

-- True when every item in the list has been handed out.
local function allFinished()
	if #store.items == 0 then return false end
	for _, entry in ipairs(store.items) do
		if entry.status ~= STATUS.AWARDED then return false end
	end
	return true
end

function LootDetection:OnLootOpened()
	if not IsInGroup() or not ALC.Council:AmLootMaster() then return end
	local threshold = ALC.Settings:GetQualityThreshold()
	local fresh, hidden = {}, 0
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotLink(slot) -- nil for money slots
		if link then
			local itemString, itemID = ALC:ParseItem(link)
			if itemString then
				local guid = GetLootSourceInfo and GetLootSourceInfo(slot)
				local key = format("%s:%d:%d", tostring(guid or "?"), slot, itemID)
				if not store.seen[key] then
					if store.seenCount >= MAX_SEEN then
						store.seen, store.seenCount = {}, 0
					end
					store.seen[key] = true
					store.seenCount = store.seenCount + 1
					local quality = itemQuality(itemString, link)
					if quality == nil or quality >= threshold then
						fresh[#fresh + 1] = { itemString = itemString, itemID = itemID, quality = quality }
					else
						hidden = hidden + 1
					end
				end
			end
		end
	end
	if #fresh == 0 and hidden == 0 then return end

	if #fresh > 0 and allFinished() then
		removeWhere(function() return true end)
	end
	store.hidden = store.hidden + hidden
	if #fresh > 0 then
		store.boss = currentBossName()
		for _, item in ipairs(fresh) do
			newEntry(item.itemString, item.itemID, item.quality, "loot")
		end
		Debug:Log("LootDetection", "%d item(s) added from %s, %d below the threshold", #fresh, tostring(store.boss), hidden)
		changed()
		ALC.Events:Fire("ALC_LOOT_ADDED", #fresh)
	else
		changed()
	end
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------
local function restore()
	store = ALC.Settings:GetLootStore()
	if store.savedAt and time() - store.savedAt > MAX_AGE then
		for i = #store.items, 1, -1 do store.items[i] = nil end
		store.seen, store.seenCount, store.hidden, store.boss = {}, 0, 0, nil
		return
	end
	-- Sessions do not survive a reload on the loot master's side.
	for _, entry in ipairs(store.items) do
		entry.starting = nil
		if entry.status == STATUS.SESSION then entry.status = STATUS.PENDING end
	end
end

function LootDetection:Init()
	restore()
	self:RegisterEvent("LOOT_OPENED", function() LootDetection:OnLootOpened() end)
	self:RegisterEvent("ENCOUNTER_END", function(_, _, name, _, _, success)
		LootDetection:OnEncounterEnd(name, success)
	end)
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
		if not waitingForInfo or refreshQueued then return end
		refreshQueued = true
		C_Timer.After(0.3, function()
			refreshQueued, waitingForInfo = false, false
			changed()
		end)
	end)

	local register = ALC.Events.Register
	register(self, "ALC_SESSION_STARTED", onSessionStarted)
	register(self, "ALC_SESSION_ENDED", onSessionEnded)
	register(self, "ALC_COMM_AWARD", onAward)
	register(self, "ALC_COMM_AWARD_REVOKE", onAwardRevoke)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------
ALC.Commands:Register("add", function(arg)
	if arg == "" then
		ALC:Print(L["Usage: /alc add [item link] (or an item id)"])
		return
	end
	local added, message = LootDetection:AddFromText(arg)
	if added == 0 then
		ALC:Print(message)
	else
		ALC:Print(L["Added %d item(s) to the loot list."], added)
	end
end, L["add items to the loot list by link or id"])

-- Trades: the items that were awarded but still have to be handed to their winner.
--
-- The queue is the loot list's items with the status "trade", oldest first. A trade you
-- make with the winner marks the item as delivered on its own: when the trade window is
-- accepted by both sides we note what we offer and to whom, and when the game says the
-- trade is complete the matching items in the queue are moved to "awarded". The Done button
-- does the same by hand.

local ALC = ALC
local LibStub = LibStub
local L = ALC.L

local Debug = ALC.Debug

local strlower = string.lower
local format = string.format

local Trades = {}
ALC.Trades = Trades
LibStub("AceEvent-3.0"):Embed(Trades)

local SNAPSHOT_KEEP = 3 -- seconds the note of an accepted trade is kept after the window closes
local TRADE_SLOTS = 6   -- items you can offer in a trade

local offered -- { partner, items = { itemID, ... }, counts = { [itemID] = in bags } } for the trade both sides accepted
local lastAsked = {} -- queue entry id -> when the winner was last asked by whisper to come

local function status() return ALC.LootDetection.STATUS end

--------------------------------------------------------------------------------
-- The queue
--------------------------------------------------------------------------------

-- The items waiting to be traded, oldest award first (copies).
function Trades:GetPending()
	local list = {}
	for _, entry in ipairs(ALC.LootDetection:GetItems()) do
		if entry.status == status().TRADE and entry.winner then list[#list + 1] = entry end
	end
	table.sort(list, function(a, b)
		if (a.awardedAt or 0) ~= (b.awardedAt or 0) then return (a.awardedAt or 0) < (b.awardedAt or 0) end
		return a.id < b.id
	end)
	return list
end

function Trades:GetPendingCount()
	return #self:GetPending()
end

-- Marks an item as delivered by hand. Returns true, or false when it is not in the queue.
function Trades:MarkDone(id)
	local entry = ALC.LootDetection:GetEntry(id)
	if not entry or entry.status ~= status().TRADE then return false end
	return ALC.LootDetection:SetStatus(id, status().AWARDED)
end

--------------------------------------------------------------------------------
-- Opening a trade with the winner
--------------------------------------------------------------------------------

-- Whispers the winner of a waiting item to come and trade (at most once every 30 seconds per item).
-- Returns true when the whisper was sent.
function Trades:AskToCome(entry)
	if not SendChatMessage then return false end
	local now = GetTime()
	if lastAsked[entry.id] and now - lastAsked[entry.id] < 30 then return false end
	local name = ALC:NormalizeName(entry.winner)
	if not name then return false end
	lastAsked[entry.id] = now
	local link = select(2, ALC:GetItemInfo(entry.itemString or entry.itemID)) or ("item " .. entry.itemID)
	SendChatMessage(format("[ALC] You won %s. Please come to me and open a trade.", link), "WHISPER", nil, name)
	return true
end

-- Opens the trade window with an item's winner when that is possible. Returns true, or
-- false and the reason.
function Trades:StartTrade(id)
	local entry = ALC.LootDetection:GetEntry(id)
	if not entry or entry.status ~= status().TRADE then
		return false, L["That item is not waiting to be traded."]
	end
	if ALC:SameName(entry.winner, ALC:PlayerName()) then
		return false, L["You are the winner yourself: the item is already yours."]
	end
	local unit = ALC:FindUnitByName(entry.winner)
	if not unit then
		return false, format(L["%s is not in your group."], entry.winner)
	end
	if UnitIsConnected and UnitIsConnected(unit) == false then
		return false, format(L["%s is offline."], entry.winner)
	end
	if CheckInteractDistance and not CheckInteractDistance(unit, 2) then
		local message = format(L["%s is too far away to trade with."], entry.winner)
		if Trades:AskToCome(entry) then message = message .. " " .. L["They were asked by whisper to come."] end
		return false, message
	end
	InitiateTrade(unit)
	return true
end

--------------------------------------------------------------------------------
-- Noticing a completed trade
--------------------------------------------------------------------------------
local function isOn(value)
	return value == 1 or value == true
end

-- How many of an item are in the bags (0 when the container API is missing).
local function bagCount(itemID)
	local get = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
	local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
	if not get or not numSlots then return 0 end
	local total = 0
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, (numSlots(bag) or 0) do
			local info, count, _, _, _, _, _, _, _, id = get(bag, slot)
			if type(info) == "table" then
				if info.itemID == itemID then total = total + (info.stackCount or 1) end
			elseif id == itemID then
				total = total + (count or 1)
			end
		end
	end
	return total
end

-- Both sides accepted: remember what we give and to whom.
function Trades:OnTradeAcceptUpdate(playerAccepted, targetAccepted)
	if not (isOn(playerAccepted) and isOn(targetAccepted)) then return end
	local items, counts = {}, {}
	for slot = 1, TRADE_SLOTS do
		local link = GetTradePlayerItemLink(slot)
		local _, itemID = ALC:ParseItem(link)
		if itemID then
			items[#items + 1] = itemID
			counts[itemID] = bagCount(itemID)
		end
	end
	offered = { partner = ALC:UnitFullName("NPC"), items = items, counts = counts }
end

-- The game says the trade went through: move the matching items out of the queue.
function Trades:OnTradeComplete()
	local snapshot = offered
	offered = nil
	if not snapshot or not snapshot.partner then return 0 end

	local delivered = 0
	local pending = self:GetPending()
	for _, itemID in ipairs(snapshot.items) do
		for index, entry in ipairs(pending) do
			if entry.itemID == itemID and ALC:SameName(entry.winner, snapshot.partner) then
				ALC.LootDetection:SetStatus(entry.id, status().AWARDED)
				table.remove(pending, index)
				delivered = delivered + 1
				break
			end
		end
	end
	if delivered > 0 then
		Debug:Log("Trades", "%d item(s) delivered to %s", delivered, snapshot.partner)
		ALC:Print(L["Trade complete: %d item(s) delivered to %s."], delivered, snapshot.partner)
	end
	return delivered
end

--------------------------------------------------------------------------------
-- Putting the won items into the trade window
--------------------------------------------------------------------------------
local PLACE_DELAY = 0.3 -- seconds after the window opens before the items are put in

-- What sits in a bag slot: itemID and whether it is locked. Handles both client shapes of the
-- container API (a table, or several return values).
local function slotInfo(bag, slot)
	local get = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
	if not get then return nil end
	local info, _, _, _, _, _, _, _, _, itemID = get(bag, slot)
	if type(info) == "table" then return info.itemID, info.isLocked end
	return itemID, nil
end

-- The first bag slot holding the item that we have not used yet, or nil.
local function findInBags(itemID, used)
	local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
	if not numSlots then return nil end
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, (numSlots(bag) or 0) do
			local id, locked = slotInfo(bag, slot)
			if id == itemID and not locked and not used[bag .. ":" .. slot] then return bag, slot end
		end
	end
end

-- Puts the won items of the trade partner into the open trade window: one per waiting
-- entry, up to the six slots. The player still has to press Accept. Returns how many went in.
function Trades:FillTrade()
	if not ALC.Settings:GetAutoTrade() then return 0 end
	local partner = ALC:UnitFullName("NPC")
	if not partner or (InCombatLockdown and InCombatLockdown()) then return 0 end
	if CursorHasItem and CursorHasItem() then return 0 end -- something is being carried: leave it

	local inWindow, nextSlot = {}, 1
	for slot = 1, TRADE_SLOTS do
		local _, itemID = ALC:ParseItem(GetTradePlayerItemLink and GetTradePlayerItemLink(slot))
		if itemID then
			inWindow[itemID] = (inWindow[itemID] or 0) + 1
			nextSlot = slot + 1
		end
	end

	local used, placed = {}, 0
	for _, entry in ipairs(self:GetPending()) do
		if ALC:SameName(entry.winner, partner) then
			local link = select(2, ALC:GetItemInfo(entry.itemString or entry.itemID)) or ("item:" .. entry.itemID)
			if (inWindow[entry.itemID] or 0) > 0 then
				inWindow[entry.itemID] = inWindow[entry.itemID] - 1 -- already in the window
			elseif nextSlot > TRADE_SLOTS then
				ALC:Print(L["The trade window is full: %s is still waiting."], link)
			else
				local bag, slot = findInBags(entry.itemID, used)
				if not bag then
					ALC:Print(L["%s is not in your bags: it cannot be added to the trade."], link)
				else
					used[bag .. ":" .. slot] = true
					local pickup = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
					local ok = pcall(function()
						pickup(bag, slot)
						ClickTradeButton(nextSlot)
					end)
					if ok and not (CursorHasItem and CursorHasItem()) then
						placed = placed + 1
						nextSlot = nextSlot + 1
						Debug:Log("Trades", "put item %d in trade slot %d for %s", entry.itemID, nextSlot - 1, partner)
					else
						if ClearCursor then ClearCursor() end
						ALC:Print(L["Could not put %s in the trade: add it yourself."], link)
					end
				end
			end
		end
	end
	if placed > 0 then
		ALC:Print(L["Added %d item(s) to the trade with %s. Check it and press Accept."], placed, partner)
	end
	return placed
end

-- The window closed: keep the note a moment, since the "complete" message may follow. When no
-- message came, the bags tell: if the offered items left them, the trade went through.
function Trades:OnTradeClosed()
	local snapshot = offered
	if not snapshot then return end
	C_Timer.After(1.5, function()
		if offered ~= snapshot then return end
		for itemID, before in pairs(snapshot.counts or {}) do
			if bagCount(itemID) < before then
				Debug:Log("Trades", "no completion message, but item %d left the bags: the trade went through", itemID)
				Trades:OnTradeComplete()
				return
			end
		end
	end)
	C_Timer.After(SNAPSHOT_KEEP, function()
		if offered == snapshot then offered = nil end
	end)
end

function Trades:Init()
	self:RegisterEvent("TRADE_ACCEPT_UPDATE", function(_, player, target) Trades:OnTradeAcceptUpdate(player, target) end)
	self:RegisterEvent("TRADE_SHOW", function()
		C_Timer.After(PLACE_DELAY, function() Trades:FillTrade() end)
	end)
	self:RegisterEvent("TRADE_CLOSED", function() Trades:OnTradeClosed() end)
	self:RegisterEvent("UI_INFO_MESSAGE", function(_, _, message)
		if message == (ERR_TRADE_COMPLETE or "Trade complete.") then Trades:OnTradeComplete() end
	end)
	self:RegisterEvent("CHAT_MSG_SYSTEM", function(_, message)
		if message == (ERR_TRADE_COMPLETE or "Trade complete.") then Trades:OnTradeComplete() end
	end)
end

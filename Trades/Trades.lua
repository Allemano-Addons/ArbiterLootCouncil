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

local offered -- { partner, items = { itemID, ... } } for the trade both sides accepted

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
		return false, format(L["%s is too far away to trade with."], entry.winner)
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

-- Both sides accepted: remember what we give and to whom.
function Trades:OnTradeAcceptUpdate(playerAccepted, targetAccepted)
	if not (isOn(playerAccepted) and isOn(targetAccepted)) then return end
	local items = {}
	for slot = 1, TRADE_SLOTS do
		local link = GetTradePlayerItemLink(slot)
		local _, itemID = ALC:ParseItem(link)
		if itemID then items[#items + 1] = itemID end
	end
	offered = { partner = ALC:UnitFullName("NPC"), items = items }
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

-- The window closed: keep the note a moment, since the "complete" message may follow.
function Trades:OnTradeClosed()
	local snapshot = offered
	if not snapshot then return end
	C_Timer.After(SNAPSHOT_KEEP, function()
		if offered == snapshot then offered = nil end
	end)
end

function Trades:Init()
	self:RegisterEvent("TRADE_ACCEPT_UPDATE", function(_, player, target) Trades:OnTradeAcceptUpdate(player, target) end)
	self:RegisterEvent("TRADE_CLOSED", function() Trades:OnTradeClosed() end)
	self:RegisterEvent("UI_INFO_MESSAGE", function(_, _, message)
		if message == (ERR_TRADE_COMPLETE or "Trade complete.") then Trades:OnTradeComplete() end
	end)
end

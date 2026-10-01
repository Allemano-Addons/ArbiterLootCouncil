-- Won items go into the trade window by themselves (Gargul style); the player presses Accept.


return function(check, H)
	local ME = "Tester Moo"
	local env = H.env

	local db = {
		[200] = { "Crown of Destruction", 4, "INVTYPE_HEAD" },
		[201] = { "Belt of Might", 4, "INVTYPE_WAIST" },
		[202] = { "Ring of Focus", 4, "INVTYPE_FINGER" },
	}
	local leader = ME
	local function items()
		local function idOf(item) return tonumber(item) or tonumber(tostring(item):match("item:(%d+)")) end
		C_Item.GetItemInfoInstant = function(item)
			local d = db[idOf(item)]
			if d then return idOf(item), "Armor", "Plate", d[3], 133101 end
		end
		C_Item.GetItemInfo = function(item)
			local id = idOf(item)
			local d = db[id]
			if d then return d[1], "|Hitem:" .. id .. "|h[" .. d[1] .. "]|h", d[2], 60, 0, "Armor", "Plate", 1, d[3], 133101 end
		end
		C_Item.RequestLoadItemDataByID = function() end
	end
	local function world(grouped)
		local units = {
			player = { "Tester", "Moo", "ROGUE" },
			party1 = { "Veyra", "Moo", "WARRIOR" },
			party2 = { "Kaelis", "Moo", "HUNTER" },
		}
		UnitName = function(unit) local u = units[unit]; if u then return u[1], u[2] end end
		UnitClass = function(unit) local u = units[unit]; if u then return u[3], u[3] end end
		items()
		H.inGroup = grouped and true or false
		ALC.Council.GetLootMethodInfo = function() return 3 end
		ALC.Council.GetLeaderName = function() return leader end
		ALC.Comm.GetGroupNames = function()
			local names = {}
			for _, unit in ipairs(ALC:GroupUnits()) do
				local name = ALC:UnitFullName(unit)
				if name then names[#names + 1] = name end
			end
			return names
		end
		ALC.Comm:InvalidateRoster()
		ALC.Council:Refresh()
	end

	H.reload("fresh")
	leader = ME
	world(true)
	local Trades, LD, Settings = ALC.Trades, ALC.LootDetection, ALC.Settings
	local store = Settings:GetLootStore()
	local function won(id, winner)
		LD:AddFromText(tostring(id))
		local e = store.items[#store.items]
		e.winner, e.status = winner, LD.STATUS.TRADE
		e.awardedAt = #store.items
		return e
	end
	local function unitFor(name)
		local first, last = name:match("^(%S+) (%S+)$")
		return { first, last, "WARRIOR" }
	end

	-- Fake bags: bag 0 holds item 200 in slot 2, and 201 in slot 3; bag 1 a second 200.
	local bags = { [0] = { [2] = 200, [3] = 201 }, [1] = { [1] = 200 } }
	local cursor, tradeSlots, cursorBlocked = nil, {}, false
	C_Container = {
		GetContainerNumSlots = function(bag) return bags[bag] and 4 or 0 end,
		GetContainerItemInfo = function(bag, slot)
			local id = bags[bag] and bags[bag][slot]
			return id and { itemID = id, isLocked = false } or nil
		end,
		PickupContainerItem = function(bag, slot)
			cursor = { bag = bag, slot = slot, id = bags[bag][slot] }
		end,
	}
	ClearCursor = function() cursor = nil end
	CursorHasItem = function() return cursor ~= nil end
	ClickTradeButton = function(slot)
		if cursor and not cursorBlocked then
			tradeSlots[slot] = cursor.id
			bags[cursor.bag][cursor.slot] = nil
			cursor = nil
		end
	end
	GetTradePlayerItemLink = function(slot)
		local id = tradeSlots[slot]
		return id and ("|Hitem:" .. id .. "|h[x]|h") or nil
	end
	InCombatLockdown = function() return false end
	local partner = "Veyra Moo"
	local realFull = ALC.UnitFullName
	ALC.UnitFullName = function(self, unit)
		if unit == "NPC" then return partner end
		return realFull(self, unit)
	end

	check("on by default", Settings:GetAutoTrade() == true)
	won(200, "Veyra Moo")
	won(201, "Veyra Moo")
	won(200, "Kaelis Moo")
	check("three waiting", Trades:GetPendingCount() == 3)

	check("the winner's two items go in", Trades:FillTrade() == 2 and tradeSlots[1] == 200 and tradeSlots[2] == 201 and tradeSlots[3] == nil)
	check("the other winner's item is left in the bag", bags[1][1] == 200)
	check("the queue is untouched until the trade completes", Trades:GetPendingCount() == 3)
	check("a second run adds nothing", Trades:FillTrade() == 0 and tradeSlots[3] == nil)

	-- The window opening triggers it
	tradeSlots, cursor = {}, nil
	bags = { [0] = { [2] = 200, [3] = 201 } }
	check("off: nothing happens", (function()
		Settings:SetAutoTrade(false)
		local n = Trades:FillTrade()
		Settings:SetAutoTrade(true)
		return n == 0 and next(tradeSlots) == nil
	end)())

	-- Another player: nothing of theirs is waiting
	partner = "Nobody Moo"
	check("a stranger gets nothing", Trades:FillTrade() == 0 and next(tradeSlots) == nil)
	partner = "Kaelis Moo"
	check("another winner gets their own item", Trades:FillTrade() == 1 and tradeSlots[1] == 200)
	partner = "Veyra Moo"
	check("the first winner's item 200 is gone from bags, so it is reported", (function()
		local chat = #H.chat
		local n = Trades:FillTrade()
		return n == 1 and tradeSlots[2] == 201 and H.chat[#H.chat]:find("Added 1", 1, true) ~= nil and #H.chat > chat
	end)())

	-- Missing item, blocked pickup, full window, carrying something
	tradeSlots, bags = {}, { [0] = {} }
	local chat = #H.chat
	check("an item not in the bags is reported", Trades:FillTrade() == 0 and #H.chat > chat)
	check("...and says which", (function()
		for i = chat + 1, #H.chat do if H.chat[i]:find("not in your bags", 1, true) then return true end end
	end)())
	bags = { [0] = { [2] = 200, [3] = 201 } }
	cursorBlocked = true
	chat = #H.chat
	check("a blocked trade button leaves the cursor empty and reports", Trades:FillTrade() == 0 and cursor == nil and #H.chat > chat)
	cursorBlocked = false
	cursor = { id = 999 }
	check("a carried item is left alone", Trades:FillTrade() == 0 and cursor.id == 999)
	cursor = nil
	for i = 1, 6 do tradeSlots[i] = 500 + i end
	chat = #H.chat
	check("a full window is reported", Trades:FillTrade() == 0 and #H.chat > chat)

	-- In combat
	tradeSlots = {}
	InCombatLockdown = function() return true end
	check("not in combat", Trades:FillTrade() == 0)
	InCombatLockdown = function() return false end

	-- Settings window has the option
	check("the settings window builds", pcall(function() ALC.SettingsWindow:Show() end))
end

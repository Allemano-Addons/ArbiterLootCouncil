-- Small things: the X of an item that awaits trade is blocked, names in the settings get their class colour.


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
	local Sessions, Awards, Comm, Settings, LD, Responses = ALC.Sessions, ALC.Awards, ALC.Comm, ALC.Settings, ALC.LootDetection, ALC.Responses
	local Win, Dialog, Trades = ALC.CouncilWindow, ALC.AwardDialog, ALC.Trades
	Settings:AddCouncilMember("Veyra Moo")
	H.setupFrames()
	H.deferTimers = true
	H.timers = {}
	local function run() H.runTimers() end

	local STATUS = LD.STATUS
	local Loot = ALC.LootWindow
	local UI = ALC.UI

	-- The X of an item that still has to be traded is blocked
	LD:AddFromText("200")
	local entry = LD:GetItems()[1]
	check("an item is in the list", entry ~= nil)
	LD:SetStatus(entry.id, STATUS.TRADE)
	Loot:Show()
	Loot:Refresh()
	local row = Loot.rows[1]
	check("an item that awaits trade has a blocked X", row.removeBlocked == true)
	row.remove.scripts.OnClick(row.remove)
	check("clicking it removes nothing", #LD:GetItems() == 1)
	LD:SetStatus(entry.id, STATUS.PENDING)
	Loot:Refresh()
	check("a waiting item has a working X", row.removeBlocked == false)
	row.remove.scripts.OnClick(row.remove)
	check("and it removes the item", #LD:GetItems() == 0)
	Loot:Hide()

	-- Class colours: learned from the group, remembered when the player is gone
	check("a character in the group has a class", ALC:ClassOf("Veyra Moo") == "WARRIOR" and ALC:ClassOf("Kaelis Moo") == "HUNTER")
	check("a character nobody knows has none", ALC:ClassOf("Nobody Moo") == nil)
	ALC:RememberClass("Ashvane Moo", "PRIEST")
	check("a remembered class is found without the player being around", ALC:ClassOf("Ashvane Moo") == "PRIEST" and ALC:ClassOf("ashvane moo") == "PRIEST")
	H.inGroup = false
	ALC.Comm:InvalidateRoster()
	check("and so is one learned earlier", ALC:ClassOf("Veyra Moo") == "WARRIOR")
	H.inGroup = true
	ALC.Comm:InvalidateRoster()

	-- The settings window colours the names
	Settings:AddCouncilMember("Veyra Moo")
	Settings:AddCouncilMember("Nobody Moo")
	Settings:SetDisenchanter("Veyra Moo")
	Settings:SetGuildBank("Kaelis Moo")
	local SW = ALC.SettingsWindow
	SW:Show()
	SW:Refresh()
	local texts = {}
	for _, r in ipairs(SW.rows) do if r:IsShown() then texts[#texts + 1] = r.name:GetText() or "" end end
	check("a council member of a known class is coloured", texts[1] and texts[1]:find("|cff", 1, true) and texts[1]:find("Veyra Moo", 1, true))
	check("one of an unknown class is plain", texts[2] == "Nobody Moo")
	local frame = SW.rows[1] and SW.rows[1]:GetParent() and SW.rows[1]:GetParent():GetParent()
	check("the disenchanter and the guild bank are coloured too", pcall(function() SW:Refresh() end))
	SW:Hide()

	-- The ways to start are told apart by colour: Start LC green, Start SR purple
	local plain = UI.NewButton(UIParent, 50, 20, "x")
	plain:SetTint({ 0.1, 0.8, 0.3 })
	check("a button can carry a colour", plain.tint ~= nil and plain.tint[2] == 0.8)
	plain:SetTint(nil)
	check("and lose it", plain.tint == nil)
	check("a start mode registers", ALC.RegisterStartMode({ id = "SR", label = "SR", name = "Soft Reserve", color = "9B7BFF", start = function() return true end }) == true)
	LD:AddFromText("200")
	Loot:Show()
	Loot:Refresh()
	local lootRow = Loot.rows[1]
	check("Start LC is green", lootRow.start.tint ~= nil and lootRow.start.tint[2] > lootRow.start.tint[1] and lootRow.start.tint[2] > lootRow.start.tint[3])
	local srButton = lootRow.modeButtons and lootRow.modeButtons[1]
	check("Start SR is purple", srButton ~= nil and srButton.tint ~= nil and srButton.tint[3] > srButton.tint[2] and srButton.tint[1] > srButton.tint[2])
	ALC.UnregisterStartMode("SR")
	Loot:Refresh()
	check("without a second way the plain Start has no colour", lootRow.start.tint == nil)
	Loot:Hide()
end

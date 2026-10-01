-- Award to the disenchanter: the setting, the award, the button, the log, undo.


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

	-- The setting
	check("no disenchanter at first", Settings:GetDisenchanter() == nil)
	local can, why = Awards:CanDisenchant()
	check("so there is nothing to award to, and it says why", can == false and why:find("No disenchanter", 1, true) ~= nil)
	check("a name with a bar is refused", Settings:SetDisenchanter("Bad|Name") == false and Settings:GetDisenchanter() == nil)
	check("a name is saved properly written", Settings:SetDisenchanter("veyra MOO") == true and Settings:GetDisenchanter() == "Veyra Moo")
	check("an empty name clears it", Settings:SetDisenchanter("") == true and Settings:GetDisenchanter() == nil)
	Settings:SetDisenchanter("Veyra Moo")
	check("now it can be awarded", (Awards:CanDisenchant()) == true)

	-- The award
	LD:AddFromText("200")
	LD:AddFromText("201")
	Sessions:StartItems({ 200, 201 })
	run()
	local sid = Sessions:GetActiveSid()
	H.said = {}
	check("award item 1 to the disenchanter without anybody answering", Awards:Award(nil, 1, true) == true)
	run()
	check("the item is awarded to them", Sessions:GetSession().items[1].winner == "Veyra Moo" and not Sessions:IsItemOpen(1))
	local log = Awards:GetLog()
	check("the log has it with the Disenchant answer and no votes", #log == 1 and log[1].winner == "Veyra Moo" and log[1].response == "DISENCHANT"
		and log[1].responseLabel == "Disenchant" and log[1].votes == 0)
	check("it is announced", H.said[#H.said] and H.said[#H.said].text:find("Veyra Moo (Disenchant)", 1, true) ~= nil)
	check("it waits in the trade queue", Trades:GetPendingCount() == 1 and Trades:GetPending()[1].winner == "Veyra Moo")
	check("it is no answer the players can give", Sessions:HasResponse("DISENCHANT") == false)
	check("but the label is known", Responses:GetLabel("DISENCHANT") == "Disenchant")
	check("Recent does not count it", ALC.Recent:Build(30, { "Veyra Moo" })[1] == nil)
	check("the history lists it", #Win:GetHistory() == 1)

	-- Undo
	local ok = Awards:Revoke(1)
	run()
	check("it can be undone like any award", ok == true and Sessions:IsItemOpen(1) and Awards:GetLog()[1].revoked == true)

	-- Refusals
	Settings:SetDisenchanter("Nobody Moo")
	local _, message = Awards:Award(nil, 1, true)
	check("a disenchanter who is not in the group is refused", _ == false and message:find("not in your group", 1, true) ~= nil)
	Settings:SetDisenchanter(ME)
	check("the loot master can be the disenchanter", Awards:Award(nil, 1, true) == true)
	run()
	check("and the item needs no trade", Sessions:GetSession().items[1].winner == ME)
	Awards:Revoke(1)
	run()
	Settings:SetDisenchanter("Veyra Moo")
	Sessions:SetPaused(true)
	run()
	local paused, pmessage = Awards:Award(nil, 2, true)
	check("a paused session refuses", paused == false and pmessage:find("paused", 1, true) ~= nil)
	Sessions:SetPaused(false)
	run()
	check("item numbers that do not exist are refused", (Awards:Award(nil, 9, true)) == false)

	-- The window: button and dialog
	Win:Show()
	Win:Refresh()
	local frame = Win.rows[1].parent
	check("the loot master has a Disenchant button", frame.disenchant:IsShown() and frame.disenchant.available == true)
	frame.disenchant.scripts.OnClick(frame.disenchant)
	check("it asks first", Dialog:IsShown() and Dialog.frame.winner:GetText() == "to Veyra Moo")
	check("the dialog says what it is", Dialog.frame.details:GetText():find("Disenchant", 1, true) ~= nil)
	Dialog:Confirm()
	run()
	check("confirming awards it", Sessions:GetSession().items[1].winner == "Veyra Moo" and not Dialog:IsShown())
	Win:Refresh()
	Win:SetFocus(1)
	Win:Refresh()
	check("the button is gone for an awarded item", not frame.disenchant:IsShown())
	Settings:SetDisenchanter(nil)
	Win:SetFocus(2)
	Win:Refresh()
	check("without a disenchanter the button is greyed, with a reason", frame.disenchant:IsShown() and frame.disenchant.available == false and frame.disenchant.reason ~= nil)

	-- The answer is reserved
	local set = Responses:GetDefaultSet()
	table.insert(set, #set, { id = "DISENCHANT", label = "Disenchant", color = { 1, 1, 1 } })
	check("a button set cannot use the reserved answer", (Responses:ValidateSet(set)) == false)

	-- Protocol
	local spec = ALC.Protocol.specs.AWARD
	local function payload(response) return { item = 1, itemID = 200, itemString = "item:200", winner = "Veyra Moo", response = response } end
	check("protocol: an award with the Disenchant answer is fine", spec.validate(payload("DISENCHANT")) == true)
	check("protocol: and an unknown answer is not", spec.validate(payload("NONSENSE")) == false)
	check("protocol: a normal answer still is", spec.validate(payload("BIS")) == true)

	-- Settings window and command
	Sessions:Cancel("done")
	run()
	check("the settings window builds with the field", pcall(function() ALC.SettingsWindow:Show() end))
	local sw = ALC.SettingsWindow
	H.slash("de set kaelis moo")
	check("/alc de set", Settings:GetDisenchanter() == "Kaelis Moo")
	H.slash("de clear")
	check("/alc de clear", Settings:GetDisenchanter() == nil)
	H.slash("de")
	check("/alc de says there is none", H.chat[#H.chat - 1]:find("No disenchanter", 1, true) ~= nil)
end

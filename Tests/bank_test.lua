-- Award to the guild bank: the setting, the award, the button, the log, undo, and that it is kept out of the history counts.


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
	check("no guild bank at first", Settings:GetGuildBank() == nil)
	local can, why = Awards:CanBank()
	check("so there is nothing to award to, and it says why", can == false and why:find("No guild bank", 1, true) ~= nil)
	check("a name with a bar is refused", Settings:SetGuildBank("Bad|Name") == false and Settings:GetGuildBank() == nil)
	check("a name is saved properly written", Settings:SetGuildBank("veyra MOO") == true and Settings:GetGuildBank() == "Veyra Moo")
	check("an empty name clears it", Settings:SetGuildBank("") == true and Settings:GetGuildBank() == nil)
	Settings:SetGuildBank("Veyra Moo")
	check("now it can be awarded", (Awards:CanBank()) == true)

	-- The award
	LD:AddFromText("200")
	LD:AddFromText("201")
	Sessions:StartItems({ 200, 201 })
	run()
	H.said = {}
	check("award item 1 to the guild bank without anybody answering", Awards:Award(nil, 1, "bank") == true)
	run()
	check("the item is awarded to them", Sessions:GetSession().items[1].winner == "Veyra Moo" and not Sessions:IsItemOpen(1))
	local log = Awards:GetLog()
	check("the log has it with the Guild bank answer and no votes", #log == 1 and log[1].winner == "Veyra Moo" and log[1].response == "BANK"
		and log[1].responseLabel == "Guild bank" and log[1].votes == 0)
	check("it is announced", H.said[#H.said] and H.said[#H.said].text:find("Veyra Moo (Guild bank)", 1, true) ~= nil)
	check("it waits in the trade queue", Trades:GetPendingCount() == 1 and Trades:GetPending()[1].winner == "Veyra Moo")
	check("it is no answer the players can give", Sessions:HasResponse("BANK") == false)
	check("but the label is known", Responses:GetLabel("BANK") == "Guild bank")
	check("Recent does not count it", ALC.Recent:Build(30, { "Veyra Moo" })[1] == nil)
	check("Context does not count it as loot the bank character has had", #ALC.Context:Build("Veyra Moo", 2).history == 0)
	check("the history lists it", #Win:GetHistory() == 1)
	check("ALC knows both are special answers", ALC:IsSpecialResponse("BANK") and ALC:IsSpecialResponse("DISENCHANT") and not ALC:IsSpecialResponse("BIS"))

	-- Undo
	local ok = Awards:Revoke(1)
	run()
	check("it can be undone like any award", ok == true and Sessions:IsItemOpen(1) and Awards:GetLog()[1].revoked == true)

	-- Refusals
	Settings:SetGuildBank("Nobody Moo")
	local refused, message = Awards:Award(nil, 1, "bank")
	check("a bank character who is not in the group is refused", refused == false and message:find("not in your group", 1, true) ~= nil)
	Settings:SetGuildBank("Veyra Moo")
	Settings:SetDisenchanter("Kaelis Moo")
	check("the disenchanter and the bank are told apart", Awards:Award(nil, 2, true) == true)
	run()
	check("the disenchanter got it, not the bank", Sessions:GetSession().items[2].winner == "Kaelis Moo" and Awards:GetLog()[2].response == "DISENCHANT")
	Awards:Revoke(2)
	run()
	Sessions:SetPaused(true)
	run()
	local paused, pmessage = Awards:Award(nil, 1, "bank")
	check("a paused session refuses", paused == false and pmessage:find("paused", 1, true) ~= nil)
	Sessions:SetPaused(false)
	run()

	-- Many at once: the bank can be in a batch
	check("a batch can name the bank", Awards:CheckMany({ { item = 1, disenchant = "bank" }, { item = 2, disenchant = true } }) == true)
	Settings:SetGuildBank(nil)
	local manyOk, manyWhy = Awards:CheckMany({ { item = 1, disenchant = "bank" } })
	check("and says when there is none", manyOk == false and manyWhy:find("No guild bank", 1, true) ~= nil)
	Settings:SetGuildBank("Veyra Moo")

	-- The window: button and dialog
	Win:Show()
	Win:SetFocus(1)
	Win:Refresh()
	local frame = Win.rows[1].parent
	check("the loot master has a Guild bank button when one is set", frame.bank:IsShown() and frame.bank.available == true)
	frame.bank.scripts.OnClick(frame.bank)
	check("it asks first", Dialog:IsShown() and Dialog.frame.winner:GetText() == "to Veyra Moo")
	check("the dialog says what it is", Dialog.frame.details:GetText():find("Guild bank", 1, true) ~= nil)
	Dialog:Confirm()
	run()
	check("confirming awards it to the bank", Sessions:GetSession().items[1].winner == "Veyra Moo" and not Dialog:IsShown() and Awards:GetLog()[#Awards:GetLog()].response == "BANK")
	Win:Refresh()
	Win:SetFocus(1)
	Win:Refresh()
	check("the button is gone for an awarded item", not frame.bank:IsShown())
	Win:SetFocus(2)
	Settings:SetGuildBank(nil)
	Win:Refresh()
	check("without a bank character there is no button", not frame.bank:IsShown())

	-- The answer is reserved
	local set = Responses:GetDefaultSet()
	table.insert(set, #set, { id = "BANK", label = "Bank", color = { 1, 1, 1 } })
	check("a button set cannot use the reserved answer", (Responses:ValidateSet(set)) == false)

	-- Protocol
	local spec = ALC.Protocol.specs.AWARD
	local function payload(response) return { item = 1, itemID = 200, itemString = "item:200", winner = "Veyra Moo", response = response } end
	check("protocol: an award with the Guild bank answer is fine", spec.validate(payload("BANK")) == true)
	check("protocol: and an unknown answer is not", spec.validate(payload("NONSENSE")) == false)

	-- Settings window, profile and command
	Sessions:Cancel("done")
	run()
	check("the settings window builds with the field", pcall(function() ALC.SettingsWindow:Show() end))
	H.slash("bank set kaelis moo")
	check("/alc bank set", Settings:GetGuildBank() == "Kaelis Moo")
	local profile = ALC.Profile:Parse(ALC.Profile:Export())
	check("the guild bank is in a shared profile", profile.values.guildBank == "Kaelis Moo")
	H.slash("bank clear")
	check("/alc bank clear", Settings:GetGuildBank() == nil)
	H.slash("bank")
	check("/alc bank says there is none", H.chat[#H.chat - 1]:find("No guild bank", 1, true) ~= nil)
end

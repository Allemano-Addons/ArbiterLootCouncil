-- Auto-pass: items the class can never use get a Pass, only when the setting is on, and the player can change it.


return function(check, H)
	local ME = "Tester Moo"
	local env = H.env

	local db = {
		[200] = { "Crown of Destruction", 4, "INVTYPE_HEAD", 4, 4 },      -- plate
		[201] = { "Belt of Might", 4, "INVTYPE_WAIST", 4, 2 },            -- leather
		[202] = { "Ring of Focus", 4, "INVTYPE_FINGER", 4, 0 },           -- a ring
		[203] = { "Greatblade", 4, "INVTYPE_2HWEAPON", 2, 8 },            -- two-handed sword
		[204] = { "Blood Shard", 1, "", 12, 0 },                          -- a quest item
	}
	local leader = ME
	local function items()
		local function idOf(item) return tonumber(item) or tonumber(tostring(item):match("item:(%d+)")) end
		C_Item.GetItemInfoInstant = function(item)
			local d = db[idOf(item)]
			if d then return idOf(item), "Armor", "Plate", d[3], 133101, d[4], d[5] end
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

	-- The rules, for the classes that matter
	local U = ALC.Usable
	local function cannot(id, class) return (U:CannotUse(id, class)) end
	check("a priest cannot use plate, a warrior and a paladin can", cannot(200, "PRIEST") and cannot(200, "ROGUE") and not cannot(200, "WARRIOR") and not cannot(200, "PALADIN"))
	check("leather is not for mages, priests and warlocks", cannot(201, "MAGE") and cannot(201, "PRIEST") and cannot(201, "WARLOCK") and not cannot(201, "ROGUE") and not cannot(201, "DRUID"))
	check("a ring is for everybody", not cannot(202, "PRIEST") and not cannot(202, "WARRIOR") and not cannot(202, "MAGE"))
	check("a two-handed sword is not for rogues, priests, mages, shamans, warlocks, druids", cannot(203, "ROGUE") and cannot(203, "PRIEST") and cannot(203, "MAGE") and cannot(203, "SHAMAN") and cannot(203, "WARLOCK") and cannot(203, "DRUID"))
	check("but it is for warriors, paladins and hunters", not cannot(203, "WARRIOR") and not cannot(203, "PALADIN") and not cannot(203, "HUNTER"))
	check("an item that is not gear is never passed", not cannot(204, "PRIEST"))
	check("a class that is not known is never passed", not cannot(200, "DEATHKNIGHT") and not cannot(200, nil))
	local _, why = U:CannotUse(200, "PRIEST")
	local _, why2 = U:CannotUse(203, "ROGUE")
	check("it says what the item is", why == "plate" and why2 == "2H swords")
	check("an item nobody knows is left alone", not cannot(999, "PRIEST"))

	-- The setting: off by default
	check("auto-pass is off by default", Settings:GetAutoPass() == false)

	-- A session with the setting off: nothing is passed
	LD:AddFromText("200")
	LD:AddFromText("201")
	LD:AddFromText("202")
	LD:AddFromText("203")
	Sessions:StartItems({ 200, 201, 202, 203 })
	run()
	run()
	check("with the setting off nothing is answered for the player", Responses:GetMyResponse(1) == nil and Responses:GetAutoPassed(1) == nil)
	Sessions:Cancel("again")
	run()

	-- With the setting on (the player is a rogue)
	Settings:SetAutoPass(true)
	check("the setting can be turned on", Settings:GetAutoPass() == true)
	LD:AddFromText("200")
	LD:AddFromText("201")
	LD:AddFromText("202")
	LD:AddFromText("203")
	Sessions:StartItems({ 200, 201, 202, 203 })
	run()
	run()
	check("plate is passed for a rogue", Responses:GetMyResponse(1) == "PASS" and Responses:GetAutoPassed(1) == "plate")
	check("leather and the ring are not", Responses:GetMyResponse(2) == nil and Responses:GetMyResponse(3) == nil)
	check("a two-handed sword is passed", Responses:GetMyResponse(4) == "PASS" and Responses:GetAutoPassed(4) == "2H swords")
	check("it was said in the chat", H.chat[#H.chat] ~= nil)
	local Resp = ALC.ResponseWindow
	Resp:Show()
	Resp:Refresh()
	local subs = {}
	for _, row in ipairs(Resp.rows) do if row:IsShown() and row.sub and row.sub.GetText then subs[#subs + 1] = row.sub:GetText() or "" end end
	check("the window marks the auto-passed items", table.concat(subs, "|"):find("Auto-passed: ", 1, true) ~= nil)
	check("answered rows have the bar on their left and the waiting ones do not", Resp.rows[1].answerBar:IsShown() and Resp.rows[4].answerBar:IsShown()
		and not Resp.rows[2].answerBar:IsShown() and not Resp.rows[3].answerBar:IsShown())

	-- The player can change it
	check("the player can still answer", Responses:Send("BIS", 1) == true)
	check("and then the mark is gone", Responses:GetMyResponse(1) == "BIS" and Responses:GetAutoPassed(1) == nil)
	Resp:Refresh()
	check("the row follows the new answer", Resp.rows[1].answerBar:IsShown())

	-- A new session starts clean
	Sessions:Cancel("again")
	run()
	check("a new session forgets the old marks", Responses:GetAutoPassed(4) == nil)

	-- The settings window has the option on the Everyone tab
	check("the settings window builds with it", pcall(function() ALC.SettingsWindow:Show() end))
	check("the option is a switch that follows the setting", ALC.SettingsWindow.groups.everyone ~= nil)
end

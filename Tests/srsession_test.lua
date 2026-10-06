-- A finished session of an addon (Soft Reserve) stays until the loot master closes it; an ordinary one closes by itself.


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

	Settings:SetDisenchanter("Veyra Moo")

	-- An ordinary loot council session closes by itself after the last award
	LD:AddFromText("200")
	Sessions:StartItems({ 200 })
	run()
	check("a session is running", Sessions:IsActive() and not Sessions:IsFinishing())
	check("awarding the last item starts the countdown", Awards:Award(nil, 1, true) == true)
	run()
	check("it is finishing, with a countdown", Sessions:IsFinishing() == true and Sessions:GetFinishLeft() ~= nil)
	run()
	check("and it closes by itself", not Sessions:IsActive())

	-- A Soft Reserve session does not
	LD:AddFromText("201")
	local ok, why = Sessions:StartItems({ 201 }, { mode = "SR", modeName = "Soft Reserve", modeColor = "9B7BFF" })
	check("a session of an addon starts: " .. tostring(why), ok == true)
	run()
	check("it is running and not finishing", Sessions:IsActive() and not Sessions:IsFinishing())
	check("awarding the last item", Awards:Award(nil, 1, true) == true)
	run()
	check("it is finishing, but with no countdown", Sessions:IsFinishing() == true and Sessions:GetFinishLeft() == nil)
	run()
	run()
	check("and it stays open until the loot master closes it", Sessions:IsActive() and Sessions:IsFinishing())
	check("an award can still be undone", Awards:Revoke(1) == true)
	run()
	check("which opens the item again and the session is not finishing", not Sessions:IsFinishing() and Sessions:IsItemOpen(1))
	check("the loot master closes it", Sessions:Cancel("closed") == true)
	run()
	check("and it is gone", not Sessions:IsActive())

	-- The Loot window says so
	check("the Loot window tells the loot master what to do", ALC.LootWindow ~= nil)
end

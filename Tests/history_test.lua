-- Clear done loot, export / clear / restore of the award history.


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
	local Awards, LD, Settings, Win, Loot = ALC.Awards, ALC.LootDetection, ALC.Settings, ALC.CouncilWindow, ALC.LootWindow
	local Dialogs = ALC.HistoryDialogs
	H.setupFrames()

	----------------------------------------------------------------------------
	-- Clear done (loot window)
	----------------------------------------------------------------------------
	local store = Settings:GetLootStore()
	for _, id in ipairs({ 200, 201, 202 }) do LD:AddFromText(tostring(id)) end
	store.items[1].status, store.items[1].winner = LD.STATUS.AWARDED, "Veyra Moo"
	store.items[2].status, store.items[2].winner = LD.STATUS.TRADE, "Veyra Moo"
	Loot:Show()
	local frame = Loot.rows[1].parent
	frame.clearDone.scripts.OnClick(frame.clearDone)
	check("only the awarded item is removed", #LD:GetItems() == 2 and LD:GetItems()[1].status == LD.STATUS.TRADE)
	check("the one waiting to trade stays", LD:GetItems()[1].itemID == 201)
	check("nothing left to clear: the button is unavailable", frame.clearDone.available == false)

	----------------------------------------------------------------------------
	-- The history
	----------------------------------------------------------------------------
	local log = Settings:GetAwardLog()
	local function add(time, winner, itemID, label, zone, revoked)
		log[#log + 1] = { itemID = itemID, itemString = "item:" .. itemID, winner = winner, class = "WARRIOR",
			response = "BIS", responseLabel = label, votes = 2, sid = "s", lm = ME, time = time, zone = zone, revoked = revoked }
	end
	add(1700000000, "Veyra Moo", 200, "BiS", "Karazhan")
	add(1700003600, "Kaelis Moo", 201, "Upgrade", 'Zul"Aman, the Hall')
	add(1700007200, "Veyra Moo", 202, "BiS", "Karazhan", true) -- taken back

	local text, count = Awards:BuildExport()
	local lines = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do if line ~= "" then lines[#lines + 1] = line end end
	check("the export has a header and one line per counted award", count == 2 and #lines == 3)
	check("the header names the columns", lines[1]:find("^date,time,player,class,item,itemID,response,votes,zone,lootMaster$") ~= nil)
	check("oldest first, with player and item", lines[2]:find("Veyra Moo", 1, true) ~= nil and lines[2]:find("Crown of Destruction", 1, true) ~= nil)
	check("commas and quotes in a field are escaped", lines[3]:find('"Zul""Aman, the Hall"', 1, true) ~= nil)
	check("a revoked award is not exported", text:find("Ring of Focus", 1, true) == nil)

	-- Win: history tab shows export and clear
	Win:ToggleHistory()
	check("the history tab lists the two awards", #Win:GetHistory() == 2)

	-- Clear asks first
	check("clearing asks", Dialogs:AskClear() == true and Dialogs:IsClearShown())
	check("nothing is cleared by asking", #log == 3)
	check("export first opens the export window", (function()
		Dialogs:ShowExport()
		return Dialogs:IsExportShown()
	end)())
	Dialogs:ConfirmClear()
	check("confirming empties the history", #Settings:GetAwardLog() == 0 and #Win:GetHistory() == 0)
	check("and closes the question", not Dialogs:IsClearShown())
	local n, when = Awards:GetBackupInfo()
	check("a backup of all three is kept", n == 3 and when ~= nil)
	check("Recent forgets them", ALC.Recent:Build(30, { "Kaelis Moo" })[1] == nil)
	check("clearing an empty history says so", Dialogs:AskClear() == false)

	-- A second clear does not destroy the backup when nothing was there
	check("clearing nothing keeps the backup", Awards:ClearLog() == 0 and Awards:GetBackupInfo() == 3)

	-- Restore
	add(1700010000, "Veyra Moo", 200, "BiS", "Karazhan") -- a new award after the clear
	local restored = Awards:RestoreLog()
	check("restore puts them back", restored == 3 and #Settings:GetAwardLog() == 4)
	check("in time order", (function()
		local l = Settings:GetAwardLog()
		for i = 2, #l do if l[i].time < l[i - 1].time then return false end end
		return true
	end)())
	check("the backup is used up", Awards:GetBackupInfo() == nil and Awards:RestoreLog() == 0)

	-- Commands
	H.slash("history export")
	check("/alc history export opens the export", Dialogs:IsExportShown())
	H.slash("history clear")
	check("/alc history clear asks", Dialogs:IsClearShown())
	Dialogs:ConfirmClear()
	check("after confirming the history is empty", #Settings:GetAwardLog() == 0)
	H.slash("history restore")
	check("/alc history restore brings it back", #Settings:GetAwardLog() == 4)
	H.slash("history")
	check("/alc history alone opens the history", Win:GetTab() == "history")

	----------------------------------------------------------------------------
	-- Clearing picked dates, and the backup that grows
	----------------------------------------------------------------------------
	Awards:ForgetBackup()
	local l = Settings:GetAwardLog()
	for i = #l, 1, -1 do l[i] = nil end
	local DAY = 86400
	local now = os.time()
	add(now - 3 * DAY, "Veyra Moo", 200, "BiS", "Karazhan")
	add(now - 3 * DAY + 60, "Kaelis Moo", 201, "Upgrade", "Karazhan")
	add(now - 2 * DAY, "Veyra Moo", 202, "BiS", "Gruul")
	add(now - 1 * DAY, "Kaelis Moo", 200, "BiS", "Magtheridon")
	local d3, d2, d1 = Awards.DateKey(now - 3 * DAY), Awards.DateKey(now - 2 * DAY), Awards.DateKey(now - 1 * DAY)
	local dates = Awards:GetDates()
	check("four awards on three days", #Settings:GetAwardLog() == 4 and #dates == 3 and dates[3].key == d3 and dates[3].count == 2)
	check("a scope lists only its awards", #Awards:GetCountedLog({ [d3] = true }) == 2 and #Awards:GetCountedLog() == 4)
	local scoped = Awards:BuildExport(Awards:GetCountedLog({ [d2] = true }))
	check("an export of one day has only that day", scoped:find("Gruul", 1, true) ~= nil and scoped:find("Karazhan", 1, true) == nil)

	Win:ShowHistory()
	Win:ToggleHistoryDate(d3)
	local asked = Dialogs:AskClear(Win:GetSelectedDates())
	check("clearing picked dates asks about them", asked and Dialogs:IsClearShown())
	Dialogs:ConfirmClear()
	check("only the picked day is cleared", #Settings:GetAwardLog() == 2 and #Awards:GetDates() == 2)
	check("the other days stay", Settings:GetAwardLog()[1].zone == "Gruul")
	check("the cleared ones are in the backup", Awards:GetBackupInfo() == 2)
	check("a date that was cleared is no longer picked", Win:GetSelectedDates() == nil and #Win:GetHistory() == 2)
	Win:ClearHistoryDates()
	Dialogs:AskClear({ [d2] = true })
	Dialogs:ConfirmClear()
	check("a second clear adds to the backup", Awards:GetBackupInfo() == 3 and #Settings:GetAwardLog() == 1)
	check("clearing a date with nothing on it does nothing", Dialogs:AskClear({ ["1999-01-01"] = true }) == false)
	check("restore gives everything back", Awards:RestoreLog() == 3 and #Settings:GetAwardLog() == 4)
	H.slash("history forget")
	Awards:ClearLog({ [d1] = true })
	H.slash("history forget")
	check("forget throws the backup away", Awards:GetBackupInfo() == nil and #Settings:GetAwardLog() == 3)
end

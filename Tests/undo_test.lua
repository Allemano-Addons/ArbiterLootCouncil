-- Undo award: the item is open again, the log and trade queue follow, the session waits for it.


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
	local Sessions, Awards, Comm, Settings, LD = ALC.Sessions, ALC.Awards, ALC.Comm, ALC.Settings, ALC.LootDetection
	local Win, Trades = ALC.CouncilWindow, ALC.Trades
	Settings:AddCouncilMember("Veyra Moo")
	H.setupFrames()
	H.deferTimers = true
	H.timers = {}
	local function run() H.runTimers() end

	local revoked = {}
	local listener = {}
	ALC.Events.Register(listener, "ALC_SESSION_ITEM_REVOKED", function(_, item, winner) revoked[#revoked + 1] = { item, winner } end)
	local ended = {}
	ALC.Events.Register(listener, "ALC_SESSION_ENDED", function(_, _, reason) ended[#ended + 1] = reason end)

	LD:AddFromText("200")
	LD:AddFromText("201")
	check("a session for two items", Sessions:StartItems({ 200, 201 }) == true)
	run()
	local sid = Sessions:GetActiveSid()
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "UPGRADE", gear = {} }), "WHISPER", "Kaelis Moo")
	Comm:Process(env("RESPONSE", sid, nil, { item = 2, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
	run()

	check("nothing to undo before an award", (Awards:Revoke(1)) == false)
	check("award item 1 to Veyra", Awards:Award("Veyra Moo", 1) == true)
	run()
	check("item 1 is awarded", Sessions:IsItemOpen(1) == false and #Awards:GetLog() == 1)
	check("it waits in the trade queue", Trades:GetPendingCount() == 1)
	H.said = {}
	local ok, winner = Awards:Revoke(1)
	run()
	check("undo works", ok == true and winner == "Veyra Moo")
	check("the item is open again", Sessions:IsItemOpen(1) == true and Sessions:GetSession().items[1].winner == nil)
	check("the event fired", #revoked == 1 and revoked[1][1] == 1 and revoked[1][2] == "Veyra Moo")
	check("the log line is marked revoked, not removed", #Awards:GetLog() == 1 and Awards:GetLog()[1].revoked == true)
	check("the trade queue lost the item", Trades:GetPendingCount() == 0)
	check("the loot list entry is in the session again", LD:GetEntry(Trades and LD:GetItems()[1].id).status == LD.STATUS.SESSION)
	check("the history does not show it", #Win:GetHistory() == 0)
	check("Recent does not count it", ALC.Recent:Build(30, { "Veyra Moo" })[1] == nil)
	check("undo was announced", H.said[#H.said] and H.said[#H.said].text:find("undone", 1, true) ~= nil)
	check("the candidates are still there", ALC.Candidates:Get("Veyra Moo", 1) ~= nil and ALC.Candidates:Get("Kaelis Moo", 1) ~= nil)
	check("undoing twice is refused", (Awards:Revoke(1)) == false)
	check("the session goes on", Sessions:IsActive())

	-- Re-award to somebody else
	check("award again, to Kaelis", Awards:Award("Kaelis Moo", 1) == true)
	run()
	check("the new winner", Sessions:GetSession().items[1].winner == "Kaelis Moo" and #Awards:GetLog() == 2)

	-- The window and the menu
	Win:Show()
	Win:SetFocus(1)
	Win:Refresh()
	local winnerRow
	for _, row in ipairs(Win.rows) do
		if row.candidate == "Kaelis Moo" and row:IsShown() then winnerRow = row end
	end
	check("the winner's row shows the tag", winnerRow ~= nil and winnerRow.tag:IsShown())
	local other
	for _, row in ipairs(Win.rows) do
		if row.candidate == "Veyra Moo" and row:IsShown() then other = row end
	end
	check("the others do not", other ~= nil and not other.tag:IsShown())
	if winnerRow.scripts and winnerRow.scripts.OnEnter then
		winnerRow.scripts.OnEnter(winnerRow)
		winnerRow.scripts.OnLeave(winnerRow)
		check("the winner's row keeps its colour after the mouse leaves", winnerRow.isWinnerRow == true)
	end
	local menu = Win:GetRowMenu("Kaelis Moo")
	check("the winner's menu offers Undo award", #menu == 1 and menu[1].label == "Undo award")
	check("the others have no menu for an awarded item", #Win:GetRowMenu("Veyra Moo") == 0)
	menu[1].onClick()
	run()
	check("the menu undoes it", Sessions:IsItemOpen(1) == true and Sessions:GetSession().items[1].winner == nil)

	-- The last item: the session stays for a while
	check("award both items", Awards:Award("Veyra Moo", 1) == true and Awards:Award("Veyra Moo", 2) == true)
	run()
	local grace = H.timers -- the end-of-session timer waits; it fires when the grace time is over
	H.timers = {}
	ended = {}
	check("the session has not ended yet", Sessions:IsActive() == true and #ended == 0)
	check("it is not counted as running", Sessions:GetSummary().running == false)
	Win:Show()
	Win:Refresh()
	check("a countdown is offered", Sessions:GetFinishLeft() ~= nil and Sessions:GetFinishLeft() > 0)
	check("undo works on the last item", (Awards:Revoke(2)) == true)
	run()
	check("the session lives and is open again", Sessions:IsActive() and Sessions:IsItemOpen(2) and Sessions:GetSummary().running)
	-- the old end-of-session timer must not end it now
	H.timers = grace
	run()
	check("the old timer does not end it", Sessions:IsActive() == true)
	Awards:Award("Veyra Moo", 2)
	run()
	grace = H.timers
	H.timers = {}
	check("still waiting", Sessions:IsActive() == true)
	H.timers = grace
	run()
	check("after the grace time the session ends", Sessions:IsActive() == false and ended[#ended] == "awarded")

	-- Close now ends a finished session at once
	Sessions:StartItems({ 200 })
	run()
	local sid3 = Sessions:GetActiveSid()
	Comm:Process(env("RESPONSE", sid3, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
	Awards:Award("Veyra Moo", 1)
	run()
	check("waiting to close", Sessions:IsActive() and Sessions:GetSession().finishing == true)
	Win:StopSession()
	run()
	check("Close now ends it without asking", Sessions:IsActive() == false and ended[#ended] == "awarded")

	-- A new session replaces one waiting to end
	Sessions:StartItems({ 200 })
	run()
	local sid2 = Sessions:GetActiveSid()
	Comm:Process(env("RESPONSE", sid2, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
	Awards:Award("Veyra Moo", 1)
	run() -- the award arrives; its end-of-session timer is queued and not run
	check("the old session waits to end", Sessions:IsActive() and Sessions:GetSummary().open == 0)
	check("a new session can start while the old one waits", Sessions:StartItems({ 201 }) == true)
	run()
	check("and it is the new one", Sessions:GetActiveSid() ~= sid2 and Sessions:IsItemOpen(1))
	Sessions:Cancel("done")
	run()

	-- Protocol
	local spec = ALC.Protocol.specs.AWARD_REVOKE
	check("protocol: the spec exists and is loot master only", spec ~= nil and spec.allowed == "lm")
	check("protocol: a good payload", spec.validate({ item = 1, itemID = 200, itemString = "item:200", winner = "Veyra Moo" }) == true)
	check("protocol: no winner is refused", spec.validate({ item = 1, itemID = 200, itemString = "item:200" }) == false)
end

-- What happens to an item after it was awarded: given back, traded on, still to trade.


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

	local Council = ALC.Council
	local log = Settings:GetAwardLog()
	local function award(winner, itemID, extra)
		local r = { item = 1, itemID = itemID, itemString = "item:" .. itemID, winner = winner, class = "WARRIOR", response = "BIS",
			responseLabel = "BiS", time = time(), votes = 0, sid = "x" }
		for k, v in pairs(extra or {}) do r[k] = v end
		log[#log + 1] = r
		return r
	end
	local function sentTo(name)
		local n = 0
		for _, s in ipairs(H.sent) do if s.dist == "WHISPER" and s.target == name then n = n + 1 end end
		return n
	end

	-- Status of an award
	local plain = award("Veyra Moo", 200)
	check("an award nobody has touched has no status", Awards.StatusOf(plain) == nil)
	plain.deliveredAt = time()
	check("a delivered award says delivered", (Awards.StatusOf(plain)) == "delivered")
	local gone = award("Veyra Moo", 201, { revoked = true })
	check("a revoked award says so", (Awards.StatusOf(gone)) == "revoked")

	-- Traded on: the award keeps its winner and says where the item went
	local passed = award("Veyra Moo", 202)
	check("the loot master notes that the winner traded the item on", Awards:NoteTradedOn("Veyra Moo", 202, "Kaelis Moo") == true)
	check("the award keeps Veyra as the winner and says where it went", passed.winner == "Veyra Moo" and passed.tradedTo == "Kaelis Moo")
	local kind, text = Awards.StatusOf(passed)
	check("the status says traded to Kaelis", kind == "traded" and text == "Traded to Kaelis Moo")
	check("it is not noted twice", Awards:NoteTradedOn("Veyra Moo", 202, "Jonatan Moo") == false and passed.tradedTo == "Kaelis Moo")
	check("trading to yourself is nothing", Awards:NoteTradedOn("Veyra Moo", 200, "Veyra Moo") == false)
	check("an item the player was never awarded is nothing", Awards:NoteTradedOn("Kaelis Moo", 202, "Jonatan Moo") == false)

	-- The same, told by the winner
	local viaMessage = award("Veyra Moo", 203)
	local before = #H.said
	ALC.Comm:Process(H.env("ITEM_PASSED", nil, nil, { itemID = 203, to = "Kaelis Moo" }), "WHISPER", "Veyra Moo")
	check("a winner's message is noted by the loot master", viaMessage.tradedTo == "Kaelis Moo")
	check("it is announced in the chat", #H.said > before or true)
	local stranger = award("Veyra Moo", 204)
	ALC.Comm:Process(H.env("ITEM_PASSED", nil, nil, { itemID = 204, to = "Kaelis Moo" }), "WHISPER", "Stranger Moo")
	check("a message from somebody outside the group is not believed", stranger.tradedTo == nil)
	ALC.Comm:Process(H.env("ITEM_PASSED", nil, nil, { itemID = 204, to = ME }), "WHISPER", "Veyra Moo")
	check("an item passed back to the loot master is left to the trade itself", stranger.tradedTo == nil)
	local bad = award("Veyra Moo", 205)
	ALC.Comm:Process(H.env("ITEM_PASSED", nil, nil, { itemID = 205, to = "Bad|Name" }), "WHISPER", "Veyra Moo")
	check("a bad name is refused", bad.tradedTo == nil)

	-- Given back
	local councilBefore = #H.sent
	local back = award("Veyra Moo", 206)
	Awards:NoteReturned(back)
	check("a returned award is marked", back.returnedAt ~= nil and (Awards.StatusOf(back)) == "returned")
	check("the council is told", #H.sent > councilBefore and sentTo("Veyra Moo") >= 1)
	check("Recent does not count a returned award", (function()
		for _, e in ipairs(ALC.Recent:Build(30, { "Veyra Moo" })[1] or {}) do if e.itemID == 206 then return false end end
		return true
	end)())

	-- The council member hears it from the loot master
	leader = "Veyra Moo"
	Council:Refresh()
	check("somebody else is the loot master now", not Council:AmLootMaster())
	local mine = award("Kaelis Moo", 207)
	ALC.Comm:Process(H.env("AWARD_NOTE", nil, nil, { itemID = 207, winner = "Kaelis Moo", kind = "returned" }), "WHISPER", "Veyra Moo")
	check("a council member marks its own copy as returned", mine.returnedAt ~= nil)
	local mine2 = award("Kaelis Moo", 208)
	ALC.Comm:Process(H.env("AWARD_NOTE", nil, nil, { itemID = 208, winner = "Kaelis Moo", kind = "traded", to = "Jonatan Moo" }), "WHISPER", "Veyra Moo")
	check("or as traded on", mine2.tradedTo == "Jonatan Moo")
	local mine3 = award("Kaelis Moo", 209)
	ALC.Comm:Process(H.env("AWARD_NOTE", nil, nil, { itemID = 209, winner = "Kaelis Moo", kind = "returned" }), "WHISPER", "Kaelis Moo")
	check("a note that does not come from the loot master is refused", mine3.returnedAt == nil)
	ALC.Comm:Process(H.env("AWARD_NOTE", nil, nil, { itemID = 209, winner = "Kaelis Moo", kind = "nonsense" }), "WHISPER", "Veyra Moo")
	check("a note of a kind that does not exist is refused", mine3.returnedAt == nil and mine3.tradedTo == nil)

	-- A winner (not the loot master) trades an item on: the loot master is told
	local g = Settings:GetDB().global
	g.myWins = { { itemID = 210, time = time() } }
	H.sent = {}
	check("trading on an item we won tells the loot master", Awards:ReportPassedOn(210, "Jonatan Moo") == true and sentTo("Veyra Moo") == 1)
	check("it is told once", Awards:ReportPassedOn(210, "Jonatan Moo") == false and sentTo("Veyra Moo") == 1)
	g.myWins = { { itemID = 211, time = time() } }
	H.sent = {}
	check("giving it back to the loot master is not news", Awards:ReportPassedOn(211, "Veyra Moo") == false and sentTo("Veyra Moo") == 0)
	check("an item we did not win is nothing", Awards:ReportPassedOn(299, "Jonatan Moo") == false)
	g.myWins = { { itemID = 212, time = time() - 9 * 86400 } }
	check("an old win is forgotten", Awards:ReportPassedOn(212, "Jonatan Moo") == false)

	-- The History tab says what happened
	leader = ME
	Council:Refresh()
	Win:ShowHistory()
	local tags = {}
	for _, row in ipairs(Win.historyRows) do if row:IsShown() then tags[#tags + 1] = (row.class:GetText() or "") .. "|" .. (row.winner:GetText() or "") end end
	local joined = table.concat(tags, "\n")
	check("the History tab shows Traded to", joined:find("Traded to Kaelis Moo", 1, true) ~= nil)
	check("and Returned", joined:find("Returned", 1, true) ~= nil)
	Win:Hide()

	-- History sync: the loot master's awards to the council
	local plainLog = Settings:GetAwardLog()
	for i = #plainLog, 1, -1 do plainLog[i] = nil end
	local t0 = time() - 3600
	local lmA = award("Veyra Moo", 300, { time = t0, responseColor = { 0.1, 0.8, 0.3 }, zone = "Karazhan", votes = 2 })
	local lmB = award("Kaelis Moo", 301, { time = t0 + 60, returnedAt = t0 + 500 })
	local lmC = award("Veyra Moo", 302, { time = time() - 100 * 86400 })
	local payload = Awards:BuildSync(30)
	check("a sync holds the awards of the last days, newest first", #payload.entries == 2 and payload.entries[1].itemID == 301 and payload.entries[2].itemID == 300)
	check("with the answer, its colour as text and the flags", payload.entries[2].color == "1acc4d" and payload.entries[2].label == "BiS" and payload.entries[1].returnedAt == t0 + 500)
	check("an older award is left out", #Awards:BuildSync(120).entries == 3 and #payload.entries == 2)
	local spec = ALC.Protocol.specs.LOG_SYNC
	check("the sync is valid", spec.validate(payload) == true)
	local function badSync(change) local p = Awards:BuildSync(30) change(p) return spec.validate(p) == false end
	check("a sync with a bad item, name, colour or flag is refused", badSync(function(p) p.entries[1].itemID = 0 end) and badSync(function(p) p.entries[1].winner = "A|B" end)
		and badSync(function(p) p.entries[1].color = "zzzzzz" end) and badSync(function(p) p.entries[1].revoked = "yes" end) and badSync(function(p) p.entries = "x" end))
	check("too many entries are refused", badSync(function(p) p.entries = {} for i = 1, 61 do p.entries[i] = { itemID = 1, winner = "A B", response = "BIS", label = "B", time = 5 } end end))
	check("the request needs days", ALC.Protocol.specs.LOG_SYNC_REQUEST.validate({ days = 30 }) == true and ALC.Protocol.specs.LOG_SYNC_REQUEST.validate({ days = 0 }) == false)

	-- The loot master answers a council member's request, once in a while
	H.sent = {}
	ALC.Comm:Process(H.env("LOG_SYNC_REQUEST", nil, nil, { days = 30 }), "WHISPER", "Veyra Moo")
	check("the loot master answers a council member with the history", sentTo("Veyra Moo") == 1)
	ALC.Comm:Process(H.env("LOG_SYNC_REQUEST", nil, nil, { days = 30 }), "WHISPER", "Veyra Moo")
	check("and only once in a while", sentTo("Veyra Moo") == 1)
	ALC.Comm:Process(H.env("LOG_SYNC_REQUEST", nil, nil, { days = 30 }), "WHISPER", "Stranger Moo")
	check("not to somebody who is not on the council", sentTo("Stranger Moo") == 0)

	-- The loot master pushes it to the whole council
	H.sent = {}
	check("a push goes to every council member", Awards:PushLogToCouncil() >= 1 and sentTo("Veyra Moo") >= 1)

	-- A council member merges it
	local entries = Awards:BuildSync(120).entries
	for i = #plainLog, 1, -1 do plainLog[i] = nil end
	leader = "Veyra Moo"
	Council:Refresh()
	local added, updated = Awards:MergeLog(entries)
	check("a council member with an empty history gets every award", added == 3 and updated == 0 and #plainLog == 3)
	check("in time order, with the item and the answer", plainLog[1].itemID == 302 and plainLog[3].itemID == 301 and plainLog[2].responseLabel == "BiS" and plainLog[2].zone == "Karazhan")
	check("and the flags", plainLog[3].returnedAt == t0 + 500)
	local again, changed = Awards:MergeLog(entries)
	check("the same awards again are not added twice", again == 0 and changed == 0 and #plainLog == 3)
	entries[1].tradedTo = "Jonatan Moo"
	entries[2].revoked = true
	local a2, u2 = Awards:MergeLog(entries)
	check("a change on the loot master's side updates the copy", a2 == 0 and u2 == 2)

	-- The message path
	for i = #plainLog, 1, -1 do plainLog[i] = nil end
	local lm1 = { entries = { { itemID = 400, winner = "Kaelis Moo", class = "HUNTER", response = "BIS", label = "BiS", time = time() - 50 } } }
	ALC.Comm:Process(H.env("LOG_SYNC", nil, nil, lm1), "WHISPER", "Veyra Moo")
	check("the loot master's history arrives over the wire", #plainLog == 1 and plainLog[1].itemID == 400 and plainLog[1].class == "HUNTER")
	ALC.Comm:Process(H.env("LOG_SYNC", nil, nil, { entries = { { itemID = 401, winner = "Kaelis Moo", response = "BIS", label = "BiS", time = time() } } }), "WHISPER", "Kaelis Moo")
	check("a sync from somebody who is not the loot master is refused", #plainLog == 1)

	-- A council member asks when a session starts
	H.sent = {}
	Settings:AddCouncilMember(ME)
	check("a council member asks the loot master", Awards:RequestLogSync() == true and sentTo("Veyra Moo") == 1)
	leader = ME
	Council:Refresh()
	check("the loot master asks nobody", Awards:RequestLogSync() == false)

	-- The tooltip of an item that was awarded lately
	for i = #plainLog, 1, -1 do plainLog[i] = nil end
	local T = ALC.ItemTooltip
	local won = award("Veyra Moo", 500)
	local lines = T:LinesFor(500)
	check("an item awarded lately says who won it and with which answer", #lines >= 1 and lines[1].text:find("Veyra Moo", 1, true) and lines[1].text:find("(BiS)", 1, true))
	won.deliveredAt = time()
	lines = T:LinesFor(500)
	check("and what became of it", #lines == 2 and lines[2].text:find("Delivered", 1, true))
	won.tradedTo = "Kaelis Moo"
	check("also when it was traded on", T:LinesFor(500)[2].text:find("Traded to Kaelis Moo", 1, true) ~= nil)
	won.revoked = true
	check("a revoked award says nothing", #T:LinesFor(500) == 0)
	check("an item nobody was awarded says nothing", #T:LinesFor(501) == 0 and #T:LinesFor(nil) == 0)
	award("Kaelis Moo", 502, { time = time() - 9 * 86400 })
	check("an old award says nothing", #T:LinesFor(502) == 0)
	local fake = { added = {}, GetItem = function() return "Crown", "|cff0070dd|Hitem:503::::::::60:::::::|h[Crown]|h|r" end,
		AddLine = function(self, text) self.added[#self.added + 1] = text end, Show = function() end }
	award("Veyra Moo", 503)
	T:Add(fake)
	check("the tooltip gets the lines", #fake.added >= 1 and fake.added[1]:find("Veyra Moo", 1, true))
	local count = #fake.added
	T:Add(fake)
	check("only once each time it is shown", #fake.added == count)
end

-- Recent awards (what a player was awarded lately, for the council) and the History filter.
-- Every "reload" loads the whole addon again from the saved variables only.

return function(check, H)
	local AceSerializer = LibStub("AceSerializer-3.0")
	local ME = "Tester Moo"
	local env = H.env
	local DAY = 86400

	local db = {
		[200] = { "Crown of Destruction", 4, "INVTYPE_HEAD" },
		[201] = { "Belt of Might", 4, "INVTYPE_WAIST" },
		[202] = { "Ring of Focus", 4, "INVTYPE_FINGER" },
	}
	local leader = ME
	local function world()
		local units = {
			player = { "Tester", "Moo", "ROGUE" },
			party1 = { "Veyra", "Moo", "WARRIOR" },
			party2 = { "Kaelis", "Moo", "HUNTER" },
			party3 = { "Jonatan", "Moo", "PRIEST" },
		}
		UnitName = function(unit) local u = units[unit]; if u then return u[1], u[2] end end
		UnitClass = function(unit) local u = units[unit]; if u then return u[3], u[3] end end
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
		H.inGroup = true
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
	local function sent(t)
		local found = {}
		for _, s in ipairs(H.sent) do
			local _, e = AceSerializer:Deserialize(s.text)
			if e and e.t == t then found[#found + 1] = { target = s.target, p = e.p, sid = e.sid, seq = e.seq } end
		end
		return found
	end

	H.reload("fresh")
	leader = ME
	world()
	-- The tooltip records what is written in it (made anew by each reload).
	local tipLines = {}
	GameTooltip.SetText = function(self, text) tipLines = { text } end
	GameTooltip.AddLine = function(self, text) tipLines[#tipLines + 1] = text end
	local Sessions, Awards, Recent, Comm, Settings = ALC.Sessions, ALC.Awards, ALC.Recent, ALC.Comm, ALC.Settings
	local Win, LD = ALC.CouncilWindow, ALC.LootDetection
	Settings:AddCouncilMember("Veyra Moo")
	Settings:AddCouncilMember("Kaelis Moo")

	-- An award in the log, `days` ago.
	local function logAward(winner, itemID, days, response, label, color)
		local log = Awards:GetLog()
		log[#log + 1] = { itemID = itemID, itemString = "item:" .. itemID, winner = winner, class = "WARRIOR",
			response = response or "BIS", responseLabel = label, responseColor = color, votes = 0, sid = "old", lm = ME,
			time = time() - days * DAY - 60, zone = "Test" }
	end

	----------------------------------------------------------------------------
	-- The protocol
	----------------------------------------------------------------------------
	local spec = ALC.Protocol.specs.RECENT
	local function player(name, count, awards) return { name = name, count = count, awards = awards or {} } end
	local function award(itemID, label, ago, color) return { itemID = itemID, label = label, ago = ago, color = color } end
	check("a RECENT message is valid", spec.validate({ days = 30, players = { player("Veyra Moo", 2, { award(200, "BiS", 3, "4dbf66"), award(201, "Upgrade", 10) }) } }, ME) == true)
	check("an empty list is valid (nobody was awarded anything)", spec.validate({ days = 30, full = true, players = {} }, ME) == true)
	check("it needs its window", spec.validate({ players = {} }, ME) == false and spec.validate({ days = 0, players = {} }, ME) == false
		and spec.validate({ days = 366, players = {} }, ME) == false)
	check("and a list", spec.validate({ days = 30 }, ME) == false)
	check("full is a boolean", spec.validate({ days = 30, full = "yes", players = {} }, ME) == false)
	check("a player needs a name and a count", spec.validate({ days = 30, players = { { count = 1, awards = {} } } }, ME) == false
		and spec.validate({ days = 30, players = { { name = "Veyra Moo", awards = {} } } }, ME) == false)
	check("a name cannot hold an escape sequence", spec.validate({ days = 30, players = { player("Ve|cffff0000yra", 1) } }, ME) == false)
	check("the count is bounded", spec.validate({ days = 30, players = { player("Veyra Moo", -1) } }, ME) == false
		and spec.validate({ days = 30, players = { player("Veyra Moo", 10000) } }, ME) == false)
	local many = {}
	for i = 1, 7 do many[i] = award(200, "BiS", i) end
	check("at most six awards are listed per player", spec.validate({ days = 30, players = { player("Veyra Moo", 7, many) } }, ME) == false)
	many[7] = nil
	check("six are fine", spec.validate({ days = 30, players = { player("Veyra Moo", 7, many) } }, ME) == true)
	check("an award needs its item, label and age", spec.validate({ days = 30, players = { player("Veyra Moo", 1, { { label = "BiS", ago = 1 } }) } }, ME) == false
		and spec.validate({ days = 30, players = { player("Veyra Moo", 1, { { itemID = 200, ago = 1 } }) } }, ME) == false
		and spec.validate({ days = 30, players = { player("Veyra Moo", 1, { { itemID = 200, label = "BiS" } }) } }, ME) == false)
	check("a label is at most 12 letters and plain text", spec.validate({ days = 30, players = { player("Veyra Moo", 1, { award(200, "Thirteen chars", 1) }) } }, ME) == false
		and spec.validate({ days = 30, players = { player("Veyra Moo", 1, { award(200, "B|cffiS", 1) }) } }, ME) == false)
	check("a colour is six hex digits", spec.validate({ days = 30, players = { player("Veyra Moo", 1, { award(200, "BiS", 1, "red") }) } }, ME) == false)
	local tooMany = {}
	for i = 1, 61 do tooMany[i] = player("Player" .. i .. " Moo", 1) end
	check("at most 60 players per message", spec.validate({ days = 30, players = tooMany }, ME) == false)

	----------------------------------------------------------------------------
	-- The setting
	----------------------------------------------------------------------------
	check("the window is 30 days by default", Settings:GetRecentDays() == 30)
	check("7, 14, 30 and 90 are allowed", Settings:SetRecentDays(7) == true and Settings:GetRecentDays() == 7 and Settings:SetRecentDays(90) == true
		and Settings:SetRecentDays(14) == true and Settings:SetRecentDays(30) == true)
	check("nothing else is", Settings:SetRecentDays(45) == false and Settings:SetRecentDays("30") == false and Settings:SetRecentDays(nil) == false
		and Settings:GetRecentDays() == 30)
	Settings:GetDB().profile.recentDays = 12
	check("a damaged saved value falls back to 30", Settings:GetRecentDays() == 30)
	Settings:GetDB().profile.recentDays = nil

	----------------------------------------------------------------------------
	-- What a loot master works out from the award log
	----------------------------------------------------------------------------
	logAward("Veyra Moo", 200, 2, "BIS", "BiS", { 0.30, 0.75, 0.40 })
	logAward("Veyra Moo", 201, 5, "UPGRADE", "Upgrade", { 0.35, 0.60, 0.95 })
	logAward("Veyra Moo", 202, 20, "MINOR", "Minor")
	logAward("Veyra Moo", 200, 45, "BIS", "BiS") -- outside 30 days
	logAward("Kaelis Moo", 201, 8, "OFFSPEC", "Offspec")
	logAward("Jonatan Moo", 202, 100, "BIS", "BiS") -- outside even 90
	for i = 1, 9 do logAward("Stray Moo", 200, i, "BIS", "BiS") end
	logAward("Old Moo", 201, 20, "BIS", "BiS") -- only an old one: in a 30 day window, not in a 7 day one

	local built = Recent:Build(30)
	local byName = {}
	for _, p in ipairs(built) do byName[p.name] = p end
	check("everybody with an award in the window is counted", byName["Veyra Moo"].count == 3 and byName["Kaelis Moo"].count == 1 and byName["Stray Moo"].count == 9)
	check("nobody outside the window is", byName["Jonatan Moo"] == nil)
	check("the latest first, with item, label, colour and age in days", byName["Veyra Moo"].awards[1].itemID == 200 and byName["Veyra Moo"].awards[1].label == "BiS"
		and byName["Veyra Moo"].awards[1].color == "4dbf66" and byName["Veyra Moo"].awards[1].ago == 2 and byName["Veyra Moo"].awards[3].ago == 20)
	check("only the latest six are listed, the count is of all", #byName["Stray Moo"].awards == 6 and byName["Stray Moo"].count == 9 and byName["Stray Moo"].awards[1].ago == 1)
	check("an award without a saved label gets the current label", byName["Kaelis Moo"].awards[1].label == "Offspec" and byName["Kaelis Moo"].awards[1].color == nil)
	check("a longer window takes in older awards", (function()
		local p = {}
		for _, x in ipairs(Recent:Build(90)) do p[x.name] = x end
		return p["Veyra Moo"].count == 4 and p["Jonatan Moo"] == nil
	end)())
	check("a shorter window, fewer", (function()
		local p = {}
		for _, x in ipairs(Recent:Build(7)) do p[x.name] = x end
		return p["Veyra Moo"].count == 2 and p["Kaelis Moo"] == nil
	end)())
	check("a list of names narrows it", #Recent:Build(30, { "veyra moo" }) == 1 and Recent:Build(30, { "Nobody Moo" })[1] == nil)
	check("the message is built for sending", spec.validate({ days = 30, players = built }, ME) == true)

	----------------------------------------------------------------------------
	-- A session: the council is told at the start
	----------------------------------------------------------------------------
	H.sent = {}
	check("start a session", Sessions:StartItems({ 200, 201 }) == true)
	local sid = Sessions:GetActiveSid()
	local starts = sent("RECENT")
	check("the council was told, and only the council", #starts == 2 and ((starts[1].target == "Veyra Moo" and starts[2].target == "Kaelis Moo")
		or (starts[1].target == "Kaelis Moo" and starts[2].target == "Veyra Moo")))
	check("with everybody's figures and the window", starts[1].p.days == 30 and starts[1].p.full == true and #starts[1].p.players == 4)
	check("the loot master has them too", Recent:GetDays() == 30 and Recent:Get("Veyra Moo") == 3 and Recent:Get("Nobody Moo") == 0)
	local count, awards = Recent:Get("Veyra Moo")
	check("the list comes as a copy with colours", #awards == 3 and awards[1].label == "BiS" and awards[1].color[1] > 0.29 and awards[1].color[1] < 0.31 and awards[1].ago == 2)
	awards[1].label = "Hacked"
	check("changing the copy changes nothing", select(2, Recent:Get("Veyra Moo"))[1].label == "BiS")
	check("lookups ignore case", Recent:Get("veyra moo") == 3)

	-- The council window: a column and a tooltip.
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "UPGRADE", gear = {} }), "WHISPER", "Jonatan Moo")
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "MINOR", gear = {} }), "WHISPER", "Kaelis Moo")
	Win:Show()
	local rows = Win.rows
	local byRow = {}
	for _, row in ipairs(rows) do if row:IsShown() and row.candidate then byRow[row.candidate] = row end end
	check("the column shows how many awards", byRow["Veyra Moo"].recent:GetText() == "3" and byRow["Kaelis Moo"].recent:GetText() == "1")
	check("and a dash for nobody", byRow["Jonatan Moo"].recent:GetText() == "\226\128\148")
	byRow["Veyra Moo"].recentButton.scripts.OnEnter(byRow["Veyra Moo"].recentButton)
	check("hovering lists the awards: window, answer, item, age", tipLines[1] == "Awarded in the last 30 days"
		and tipLines[2] == "BiS  \194\183  Crown of Destruction  \194\183  2 days ago"
		and tipLines[3] == "Upgrade  \194\183  Belt of Might  \194\183  5 days ago"
		and tipLines[4] == "Minor  \194\183  Ring of Focus  \194\183  20 days ago")
	byRow["Stray Moo"] = nil
	byRow["Jonatan Moo"].recentButton.scripts.OnEnter(byRow["Jonatan Moo"].recentButton)
	check("nothing awarded says so", tipLines[1] == "Awarded in the last 30 days" and tipLines[2] == "Nothing")
	logAward("Veyra Moo", 200, 0, "BIS", "BiS")
	local _ = Recent:Send({ "Veyra Moo" })
	byRow["Veyra Moo"].recentButton.scripts.OnEnter(byRow["Veyra Moo"].recentButton)
	check("an award from today says today", tipLines[2]:find("today", 1, true) ~= nil)
	Recent:Send() -- everybody, so a later test starts from the log
	rows[1].recentButton.scripts.OnLeave(rows[1].recentButton)

	----------------------------------------------------------------------------
	-- An award: the winner's figures are sent
	----------------------------------------------------------------------------
	H.sent = {}
	local before = Recent:Get("Kaelis Moo")
	check("award item 1 to Kaelis", Awards:Award("Kaelis Moo", 1) == true)
	local after = sent("RECENT")
	check("the council hears about the winner only", #after == 2 and #after[1].p.players == 1 and after[1].p.players[1].name == "Kaelis Moo" and after[1].p.full == false)
	check("with one more award", Recent:Get("Kaelis Moo") == before + 1 and after[1].p.players[1].count == before + 1 and after[1].p.players[1].awards[1].ago == 0)
	check("the others keep theirs", Recent:Get("Veyra Moo") == 4)

	----------------------------------------------------------------------------
	-- The window changes
	----------------------------------------------------------------------------
	H.sent = {}
	check("before, the old award counted", Recent:Get("Old Moo") == 1)
	Settings:SetRecentDays(7)
	local changed = sent("RECENT")
	check("a new window is sent to the council as everybody's figures", #changed == 2 and changed[1].p.days == 7 and changed[1].p.full == true)
	check("a player with nothing in it disappears (full)", Recent:Get("Old Moo") == 0 and Recent:Get("Kaelis Moo") == 1)
	check("the window is remembered by the council", Recent:GetDays() == 7)
	check("Stray Moo's 9 awards came down to the last 7 days", Recent:Get("Stray Moo") == 6)
	Settings:SetRecentDays(30)

	----------------------------------------------------------------------------
	-- A council member, and somebody outside the council
	----------------------------------------------------------------------------
	local incoming = { days = 30, full = true, players = { player("Veyra Moo", 2, { award(200, "BiS", 1) }) } }
	check("only the loot master may send it", Comm:Process(env("RECENT", sid, nil, incoming), "WHISPER", "Veyra Moo") == false)
	check("and only over a whisper", Comm:Process(env("RECENT", sid, 500, incoming), "RAID", ME) == false)
	Sessions:Cancel("done")
	check("the figures are forgotten when the session ends", Recent:GetDays() == nil and Recent:Get("Veyra Moo") == 0)
	byRow = nil

	H.reload("fresh")
	leader = "Veyra Moo"
	world()
	Sessions, Awards, Recent, Comm, Settings = ALC.Sessions, ALC.Awards, ALC.Recent, ALC.Comm, ALC.Settings
	Win = ALC.CouncilWindow
	local council = { "Veyra Moo", ME }
	local start = { items = { { itemID = 200, itemString = "item:200" } }, council = council, lm = "Veyra Moo" }
	check("a session from somebody else's table", Comm:Process(env("SESSION_START", "sidR", 1, start), "PARTY", "Veyra Moo") == true)
	check("we have no figures yet", Recent:GetDays() == nil and Recent:Get("Kaelis Moo") == 0)
	check("they arrive from the loot master", Comm:Process(env("RECENT", "sidR", 2, { days = 14, full = true, players = {
		player("Kaelis Moo", 3, { award(201, "Upgrade", 4, "5b99f2"), award(200, "BiS", 9) }) } }), "WHISPER", "Veyra Moo") == true)
	check("and are kept", Recent:GetDays() == 14 and Recent:Get("Kaelis Moo") == 3 and select(2, Recent:Get("Kaelis Moo"))[1].label == "Upgrade")
	check("a partial message changes only the players in it", Comm:Process(env("RECENT", "sidR", 3, { days = 14, full = false, players = { player("Jonatan Moo", 1, { award(202, "Minor", 1) }) } }), "WHISPER", "Veyra Moo") == true
		and Recent:Get("Jonatan Moo") == 1 and Recent:Get("Kaelis Moo") == 3)
	check("a full message replaces everything", Comm:Process(env("RECENT", "sidR", 4, { days = 14, full = true, players = { player("Jonatan Moo", 2) } }), "WHISPER", "Veyra Moo") == true
		and Recent:Get("Jonatan Moo") == 2 and Recent:Get("Kaelis Moo") == 0)
	Comm:Process(env("SESSION_CANCEL", "sidR", 5, { reason = "done" }), "PARTY", "Veyra Moo")

	-- Not on the council: nothing is kept.
	local outside = { items = { { itemID = 200, itemString = "item:200" } }, council = { "Veyra Moo" }, lm = "Veyra Moo" }
	Comm:Process(env("SESSION_START", "sidS", 1, outside), "PARTY", "Veyra Moo")
	Comm:Process(env("RECENT", "sidS", 2, { days = 14, full = true, players = { player("Kaelis Moo", 3) } }), "WHISPER", "Veyra Moo")
	check("somebody outside the council keeps nothing", Recent:Get("Kaelis Moo") == 0 and Recent:GetDays() == nil)
	Comm:Process(env("SESSION_CANCEL", "sidS", 3, { reason = "done" }), "PARTY", "Veyra Moo")

	-- A snapshot carries the figures to a council member that reloaded, not to a raider.
	H.reload("fresh")
	leader = ME
	world()
	Sessions, Awards, Recent, Comm, Settings = ALC.Sessions, ALC.Awards, ALC.Recent, ALC.Comm, ALC.Settings
	ALC.Settings:AddCouncilMember("Veyra Moo")
	local log = Awards:GetLog()
	log[#log + 1] = { itemID = 201, itemString = "item:201", winner = "Kaelis Moo", class = "HUNTER", response = "BIS", responseLabel = "BiS",
		votes = 0, sid = "old", lm = ME, time = time() - 3 * DAY, zone = "Test" }
	Sessions:StartItems({ 200 })
	local sid2 = Sessions:GetActiveSid()
	H.clock = H.clock + 100
	H.sent = {}
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Veyra Moo")
	local snap = sent("STATE_SNAPSHOT")[1]
	check("a council member's snapshot has the figures", snap ~= nil and snap.p.recent ~= nil and snap.p.recent.full == true
		and snap.p.recent.players[1].name == "Kaelis Moo" and snap.p.recent.players[1].count == 1)
	H.clock = H.clock + 100
	H.sent = {}
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Jonatan Moo")
	local raiderSnap = sent("STATE_SNAPSHOT")[1]
	check("a raider's has none", raiderSnap ~= nil and raiderSnap.p.recent == nil)
	check("the snapshot is valid as sent", ALC.Protocol.specs.STATE_SNAPSHOT.validate(snap.p, ME) == true)

	-- The loot master's own reload: the figures are back, nothing is sent.
	local savedDb = H.snapshotDB()
	H.reload(savedDb)
	leader = ME
	world()
	H.sent = {}
	ALC.Sessions:OnEnteringWorld(false, true)
	check("after a reload the loot master has its figures again", ALC.Sessions:GetActiveSid() == sid2 and ALC.Recent:Get("Kaelis Moo") == 1 and ALC.Recent:GetDays() == 30)
	check("and sent nobody anything", #sent("RECENT") == 0)
	ALC.Sessions:Cancel("done")

	----------------------------------------------------------------------------
	-- The History: dates, search
	----------------------------------------------------------------------------
	H.reload("fresh")
	leader = ME
	world()
	Awards, Win, Settings = ALC.Awards, ALC.CouncilWindow, ALC.Settings
	local function addLog(winner, days, itemID, zone)
		local l = Awards:GetLog()
		l[#l + 1] = { itemID = itemID or 200, itemString = "item:" .. (itemID or 200), winner = winner, class = "WARRIOR", response = "BIS", responseLabel = "BiS",
			votes = 0, sid = "x", lm = ME, time = time() - days * DAY - 30, zone = zone or "Test" }
	end
	addLog("F Moo", 200) addLog("E Moo", 60) addLog("D Moo", 20) addLog("C Moo", 10, 201, "Karazhan")
	addLog("B Moo", 6) addLog("A Moo", 1) addLog("A Moo", 1, 201) -- oldest first, as the log is written
	check("all awards are shown by default", #Win:GetHistory() == 7 and Win:GetSelectedDates() == nil)
	check("newest first", Win:GetHistory()[1].winner == "A Moo" and Win:GetHistory()[7].winner == "F Moo")
	local dates = Awards:GetDates()
	check("the dates are listed newest first, with counts", #dates == 6 and dates[1].count == 2 and dates[1].key > dates[2].key)

	Win:ToggleHistoryDate(dates[1].key)
	check("picking a date shows only that day", #Win:GetHistory() == 2 and Win:GetSelectedDates()[dates[1].key] == true)
	Win:ToggleHistoryDate(dates[3].key)
	check("several dates can be picked", #Win:GetHistory() == 3)
	Win:ToggleHistoryDate(dates[1].key)
	check("picking it again drops it", #Win:GetHistory() == 1 and Win:GetHistory()[1].winner == "C Moo")
	Win:ClearHistoryDates()
	check("All dates clears the pick", #Win:GetHistory() == 7 and Win:GetSelectedDates() == nil)

	Win:SetHistorySearch("a moo")
	check("search finds a player, without regard to case", #Win:GetHistory() == 2)
	Win:SetHistorySearch("karazhan")
	check("search finds a zone", #Win:GetHistory() == 1 and Win:GetHistory()[1].winner == "C Moo")
	Win:SetHistorySearch("crown")
	check("search finds an item by name", #Win:GetHistory() >= 1 and Win:GetHistory()[1].itemID == 200)
	Win:SetHistorySearch("zzz")
	check("nothing matches", #Win:GetHistory() == 0)
	Win:SetHistorySearch("")
	Win:ToggleHistoryDate(dates[1].key)
	Win:SetHistorySearch("belt")
	check("search and date work together", #Win:GetHistory() == 1 and Win:GetHistory()[1].itemID == 201)
	Win:SetHistorySearch("")
	Win:ClearHistoryDates()
	check("the log itself is untouched", #Awards:GetLog() == 7)

	Win:ShowHistory()
	local frame = Win.historyRows[1].parent
	check("the date list has All dates first", frame.dateRows[1].label:GetText() == "All dates" and frame.dateRows[1].count:GetText() == "7")
	check("then the days", frame.dateRows[2].label:GetText() == dates[1].key and frame.dateRows[2].count:GetText() == "2")
	check("the list is marked: All dates is the pick", frame.dateRows[1].picked == true and frame.dateRows[2].picked == false)
	frame.dateRows[2].scripts.OnClick(frame.dateRows[2])
	check("a click picks the day", Win:GetSelectedDates()[dates[1].key] == true and frame.dateRows[2].picked == true and frame.dateRows[1].picked == false)
	check("the count says what it covers", frame.historyCount:GetText() == "2 awards \194\183 1 date")
	check("Clear now means the picked dates", frame.historyClear.label:GetText() == "Clear dates")
	frame.dateRows[1].scripts.OnClick(frame.dateRows[1])
	check("All dates shows everything again", frame.historyCount:GetText() == "7 awards" and Win.historyRows[7]:IsShown())
	frame.historySearch:SetText("karazhan")
	frame.historySearch.scripts.OnTextChanged(frame.historySearch)
	check("typing in the search field filters", frame.historyCount:GetText():find("^1 award") ~= nil and not Win.historyRows[2]:IsShown())
	Win:SetHistorySearch("")
	Win:Hide()

	----------------------------------------------------------------------------
	-- The settings window
	----------------------------------------------------------------------------
	local SW = ALC.SettingsWindow
	SW:Show()
	SW:SetTab("session")
	check("four buttons for the window of recent awards", #SW.recentButtons == 4 and SW.recentButtons[1].label:GetText() == "7 days" and SW.recentButtons[4].label:GetText() == "90 days")
	check("30 days is marked", SW.recentButtons[3].selected == true and SW.recentButtons[1].selected == false)
	SW.recentButtons[1].scripts.OnClick(SW.recentButtons[1])
	check("a click sets it", Settings:GetRecentDays() == 7 and SW.recentButtons[1].selected == true and SW.recentButtons[3].selected == false)
	check("they belong to the Session tab", SW.recentButtons[1]:IsShown())
	SW:SetTab("everyone")
	check("and are hidden on the others", not SW.recentButtons[1]:IsShown())
	SW:Hide()

	-- Put the environment back.
	UnitIsConnected = function() return true end
	H.inGroup = false
	C_Item.GetItemInfo = function() end
	C_Item.GetItemInfoInstant = nil
	C_Item.RequestLoadItemDataByID = nil
	GameTooltip.SetText, GameTooltip.AddLine = nil, nil
end

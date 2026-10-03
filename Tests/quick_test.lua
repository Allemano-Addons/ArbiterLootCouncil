-- Announce on/off, compact windows, the "session running" signs and the test mode with made-up
-- players. Every "reload" loads the whole addon again from the saved variables only.

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
	local Sessions, Awards, Comm, Settings = ALC.Sessions, ALC.Awards, ALC.Comm, ALC.Settings
	local Win, Resp, Loot = ALC.CouncilWindow, ALC.ResponseWindow, ALC.LootWindow
	Settings:AddCouncilMember("Veyra Moo")
	local tipLines = {}
	GameTooltip.SetText = function(self, text) tipLines = { text } end
	GameTooltip.AddLine = function(self, text) tipLines[#tipLines + 1] = text end

	----------------------------------------------------------------------------
	-- Announce in raid chat, on or off
	----------------------------------------------------------------------------
	check("awards are announced by default", Settings:GetAnnounceAwards() == true)
	check("it can be switched off and on", (function()
		Settings:SetAnnounceAwards(false)
		local off = Settings:GetAnnounceAwards() == false
		Settings:SetAnnounceAwards(true)
		return off and Settings:GetAnnounceAwards() == true
	end)())

	check("start a session with two items", Sessions:StartItems({ 200, 201 }) == true)
	local sid = Sessions:GetActiveSid()
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
	Comm:Process(env("RESPONSE", sid, nil, { item = 2, response = "UPGRADE", gear = {} }), "WHISPER", "Veyra Moo")
	H.said = {}
	check("an award is said in party chat when announcing is on", Awards:Award("Veyra Moo", 1) == true and #H.said == 1 and H.said[1].text:find("Veyra Moo", 1, true) ~= nil)
	Settings:SetAnnounceAwards(false)
	local chatBefore = #H.chat
	local announced
	local listener = {}
	ALC.Events.Register(listener, "ALC_AWARDS_ANNOUNCED", function(_, text) announced = text end)
	check("with it off, nothing is said in the group", Awards:Award("Veyra Moo", 2) == true and #H.said == 1)
	check("but the loot master is told in their own chat", H.chat[#H.chat]:find("Not announced in chat", 1, true) ~= nil and #H.chat > chatBefore)
	check("the award is still logged and remembered", #Awards:GetLog() == 2 and Awards:GetLastAnnouncement():find("Belt of Might", 1, true) ~= nil and announced ~= nil)
	ALC.Events.UnregisterAll(listener)
	Loot:Show()
	local lootFrame = Loot.rows[1].parent
	Loot:Hide()
	check("the session is over", not Sessions:IsActive())

	----------------------------------------------------------------------------
	-- Session running: the signs on the minimap button and the menu
	----------------------------------------------------------------------------
	local Button, Launcher = ALC.MinimapButton, ALC.Launcher
	local button = Button.button
	check("no session: no dot, a plain frame", not button.dot:IsShown() and Button:IsRunning() == false)
	check("the summary says so", Sessions:GetSummary().running == false and Sessions:GetSummary().total == 0)
	check("start a session", Sessions:StartItems({ 200, 201, 202 }) == true)
	sid = Sessions:GetActiveSid()
	check("a session runs: the dot shows", button.dot:IsShown() and Button:IsRunning() == true)
	check("the summary counts the open items", Sessions:GetSummary().running == true and Sessions:GetSummary().total == 3 and Sessions:GetSummary().open == 3)
	button.scripts.OnEnter(button)
	check("the tooltip says it", tipLines[2] == "Session running: 3 of 3 items open")
	Launcher:Show(button)
	check("the menu says it too", Launcher.rows[1].parent.status:GetText() == "3 OF 3 OPEN")
	Launcher:Hide()
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
	Awards:Award("Veyra Moo", 1)
	button.scripts.OnEnter(button)
	check("an award changes the count", Sessions:GetSummary().open == 2 and tipLines[2] == "Session running: 2 of 3 items open" and button.dot:IsShown())
	Sessions:Cancel("done")
	check("the session ends: the dot goes", not button.dot:IsShown() and Button:IsRunning() == false)
	Launcher:Show(button)
	check("and the menu's line", Launcher.rows[1].parent.status:GetText() == "")
	Launcher:Hide()
	button.scripts.OnEnter(button)
	check("and the tooltip loses the line", tipLines[2] ~= nil and tipLines[2]:find("Session running", 1, true) == nil)
	button.scripts.OnLeave(button)

	-- After a reload of the loot master the sign is back.
	Sessions:StartItems({ 200, 201 })
	local saved = H.snapshotDB()
	H.reload(saved)
	leader = ME
	world(true)
	check("after a reload nothing runs yet", ALC.MinimapButton.button.dot:IsShown() == false)
	ALC.Sessions:OnEnteringWorld(false, true)
	check("the restored session shows the dot again", ALC.MinimapButton.button.dot:IsShown() == true)
	ALC.Sessions:Cancel("done")
	Sessions, Awards, Comm, Settings = ALC.Sessions, ALC.Awards, ALC.Comm, ALC.Settings
	Win, Resp, Loot = ALC.CouncilWindow, ALC.ResponseWindow, ALC.LootWindow

	----------------------------------------------------------------------------
	-- Compact windows
	----------------------------------------------------------------------------
	H.reload("fresh")
	leader = ME
	world(true)
	Sessions, Awards, Comm, Settings = ALC.Sessions, ALC.Awards, ALC.Comm, ALC.Settings
	Win, Resp, Loot = ALC.CouncilWindow, ALC.ResponseWindow, ALC.LootWindow
	Settings:AddCouncilMember("Veyra Moo")
	check("not compact by default", Settings:GetCompact() == false)
	Settings:GetDB().profile.windows.council = { compact = true }
	check("an old voting window choice counts until the new setting is used", Settings:GetCompact() == true)
	Settings:GetDB().profile.windows.council = nil
	check("the new setting wins over it", (function()
		Settings:GetDB().profile.windows.council = { compact = true }
		Settings:SetCompact(false)
		local v = Settings:GetCompact()
		Settings:GetDB().profile.windows.council = nil
		return v == false
	end)())

	Loot:Show()
	LootDetection = ALC.LootDetection
	LootDetection:AddFromText("200 201")
	local lootRows = Loot.rows
	check("tall loot rows by default", lootRows[1].h == 56 and lootRows[1].iconFrame.h == 40 and lootRows[1].start.h == 34)
	local lootHeight = lootFrame and lootFrame:GetHeight() or 0
	Settings:SetCompact(true)
	check("compact loot rows are lower", lootRows[1].h == 36 and lootRows[1].iconFrame.h == 28 and lootRows[1].start.h == 24)
	check("and the list is placed by the new height", lootRows[2].point[5] == -(40 + 30 + 1 * (36 + 4)))
	Settings:SetCompact(false)
	-- A Bind-on-Pickup item shows a countdown bar along its row.
	local realSlots, realScan = ALC.LootDetection.FindBagSlots, ALC.LootDetection.ScanBagItem
	ALC.LootDetection.FindBagSlots = function() return { { 0, 1 } } end
	ALC.LootDetection:ClearTradeCache()
	ALC.LootDetection.ScanBagItem = function() return { "Soulbound", "You may trade this item with players that were eligible to loot it for the next 3 hours 30 min." } end
	Loot:Refresh()
	check("a BoP item shows its countdown bar", lootRows[1].bar:IsShown() and lootRows[1].bar.fill.w ~= nil and lootRows[1].bar.fill.w > 300)
	ALC.LootDetection.FindBagSlots, ALC.LootDetection.ScanBagItem = realSlots, realScan
	ALC.LootDetection:ClearTradeCache()

	-- The windows make their rows as needed and fill the pool in the background (never one long script).
	check("the loot window's pool fills up", #lootRows == 24)

	-- The window size follows the setting, in every window.
	check("an unknown window size is refused", Settings:SetWindowScale(0.5) == false and Settings:GetWindowScale() == 1)
	check("a known one is accepted", Settings:SetWindowScale(0.8) == true and lootRows[1].parent:GetScale() == 0.8)
	Settings:SetWindowScale(1)
	check("and back to normal", lootRows[1].parent:GetScale() == 1)
	check("back to the old sizes", lootRows[1].h == 56 and lootRows[2].point[5] == -(40 + 30 + 1 * (56 + 8)))
	Settings:SetCompact(true)
	Loot:Hide()

	check("start a session", Sessions:StartItems({ 200, 201 }) == true)
	local sid2 = Sessions:GetActiveSid()
	check("the response window has compact rows", Resp:IsShown() and Resp.rows[1].h == 30 and Resp.rows[1].itemBox.h == 22 and Resp.rows[1].buttons[1].h == 20)
	check("and they sit closer", Resp.rows[2].point[5] == -(40 + 10 + 1 * (30 + 2)))
	local compactHeight = Resp.rows[1].parent:GetHeight()
	Settings:SetCompact(false)
	check("switching back gives the tall rows", Resp.rows[1].h == 46 and Resp.rows[1].itemBox.h == 34 and Resp.rows[1].buttons[1].h == 30)
	check("and a taller window", Resp.rows[1].parent:GetHeight() > compactHeight)
	Settings:SetCompact(true)

	Comm:Process(env("RESPONSE", sid2, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
	Win:Show()
	local crow
	for _, row in ipairs(Win.rows) do if row:IsShown() and row.candidate == "Veyra Moo" then crow = row end end
	check("the voting window's rows are compact too", crow.h == 32)
	check("and its pool fills up in the background", #ALC.CouncilWindow.rows == 30)
	local councilFrame = crow.parent
	check("its own checkbox follows the setting", councilFrame.compact.checked == true)
	councilFrame.compact.scripts.OnClick(councilFrame.compact)
	check("and changes the same setting", Settings:GetCompact() == false and crow.h == 56)
	Sessions:Cancel("done")
	Win:Hide()

	local SW = ALC.SettingsWindow
	SW:Show()
	SW:SetTab("everyone")
	local sframe = SW.rows[1].parent.parent
	check("Everyone has a checkbox for compact windows", sframe.compact ~= nil and sframe.compact:IsShown() and sframe.compact.checked == false)
	sframe.compact.scripts.OnClick(sframe.compact)
	check("it sets the setting", Settings:GetCompact() == true)
	SW:SetTab("lm")
	check("the loot master has one for announcing, on", sframe.announce:IsShown() and sframe.announce.checked == true and not sframe.compact:IsShown())
	sframe.announce.scripts.OnClick(sframe.announce)
	check("it switches announcing off", Settings:GetAnnounceAwards() == false)
	SW:Hide()
	Settings:SetCompact(false)
	Settings:SetAnnounceAwards(true)

	----------------------------------------------------------------------------
	-- Test mode with made-up players
	----------------------------------------------------------------------------
	H.reload("fresh")
	leader = ME
	world(false)
	Sessions, Awards, Comm, Settings = ALC.Sessions, ALC.Awards, ALC.Comm, ALC.Settings
	Win = ALC.CouncilWindow
	local TestMode, Candidates = ALC.TestMode, ALC.Candidates
	TestMode.GetBagItemLinks = function() return { "|Hitem:200|h[Crown]|h", "|Hitem:201|h[Belt]|h", "|Hitem:202|h[Ring]|h" } end

	local seed = 12345
	TestMode.random = function() -- a fixed sequence, so the test does the same every time
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end

	H.slash("test 2 20")
	check("a session with two items started", Sessions:IsActive() and Sessions:GetItemCount() == 2)
	local count1 = #Candidates:GetList(1)
	local count2 = #Candidates:GetList(2)
	check("twenty made-up players are in, most of them on each item", count1 >= 12 and count1 <= 20 and count2 >= 12 and count2 <= 20)
	check("a few stay silent on an item, as in a real raid", count1 + count2 < 40)
	local names, valid = {}, true
	for _, e in ipairs(Candidates:GetList(1)) do
		if names[e.name] then valid = false end
		names[e.name] = true
		if not e.name:find(" Testa$") or not e.class:find("^%u+$") or not Sessions:HasResponse(e.response) then valid = false end
	end
	check("each has their own name, a class and one of the buttons", valid)
	local someRank, someNote, someGear = false, false, false
	for item = 1, 2 do
		for _, e in ipairs(Candidates:GetList(item)) do
			if e.rank and e.rankIndex then someRank = true end
			if e.note then someNote = true end
			if #e.gear > 0 then someGear = true end
		end
	end
	check("with ranks, notes and gear to look at", someRank and someNote and someGear)
	check("the made-up players pass the protocol", (function()
		for _, e in ipairs(Candidates:GetList(1)) do
			local ok = ALC.Protocol.specs.CANDIDATE_UPDATE.validate(e, ME)
			if not ok then return false end
		end
		return true
	end)())
	Win:Show()
	check("the voting window lists them", #Win:GetVisible() >= 10 and Win.rows[1]:IsShown() and Win.rows[10]:IsShown())
	check("so the list needs a scrollbar at ten rows", Win.rows[1].parent.scroll:IsShown() == (#Win:GetVisible() > 10))
	local award = Win:GetVisible()[1].name
	check("one of them can be awarded", Awards:Award(award, 1) == true and not Sessions:IsItemOpen(1))
	Win:Hide()
	Sessions:Cancel("done")

	-- Fewer or more players, the limits.
	H.slash("test 1 3")
	check("three players", #Candidates:GetList(1) <= 3 and #Candidates:GetList(1) >= 1)
	Sessions:Cancel("done")
	H.slash("test 1 500")
	check("never more than the list of names (40)", #Candidates:GetList(1) <= 40)
	Sessions:Cancel("done")
	H.slash("test 1")
	check("without a number there are none", Sessions:IsActive() and #Candidates:GetList(1) == 0)
	Sessions:Cancel("done")
	H.slash("test")
	check("no arguments: one item, no players", Sessions:IsActive() and Sessions:GetItemCount() == 1 and #Candidates:GetList(1) == 0)
	Sessions:Cancel("done")

	-- Answers: the first buttons likeliest, Pass the least.
	local set = Sessions:StartItems({ 200 }) and Sessions:GetResponses()
	TestMode.random = function() return 0 end
	check("the first random value picks the first button", (function()
		TestMode:AddCandidates(1)
		return Candidates:GetList(1)[1] ~= nil and Candidates:GetList(1)[1].response == "BIS"
	end)())
	Sessions:Cancel("done")
	Sessions:StartItems({ 200 })
	TestMode.random = function() return 0.999 end
	check("and the last value picks Pass", (function()
		TestMode:AddCandidates(1)
		local first = Candidates:GetList(1)[1]
		return first == nil or first.response == "PASS" -- (0.999 is over 0.85: the player stays silent)
	end)())
	Sessions:Cancel("done")
	TestMode.random = math.random

	-- Only for the loot master, alone, on an open item, with a valid answer.
	Sessions:StartItems({ 200 })
	check("a player can be injected when alone", Candidates:Inject(1, { name = "Solo Testa", class = "MAGE", response = "BIS", gear = {} }) == true
		and Candidates:Get("Solo Testa", 1) ~= nil)
	check("not with an unknown answer", Candidates:Inject(1, { name = "Bad Testa", class = "MAGE", response = "NOPE", gear = {} }) == false)
	check("not for an item that does not exist", Candidates:Inject(5, { name = "Bad Testa", class = "MAGE", response = "BIS", gear = {} }) == false)
	check("not without a name or class", Candidates:Inject(1, { class = "MAGE", response = "BIS", gear = {} }) == false
		and Candidates:Inject(1, { name = "Bad Testa", response = "BIS", gear = {} }) == false)
	H.inGroup = true
	check("not in a group", Candidates:Inject(1, { name = "Group Testa", class = "MAGE", response = "BIS", gear = {} }) == false)
	check("and test mode does not start in a group either", (function()
		local ok = TestMode:Start(1, 5)
		return ok == false
	end)())
	H.inGroup = false
	Sessions:Cancel("done")
	check("nothing without a session", Candidates:Inject(1, { name = "Late Testa", class = "MAGE", response = "BIS", gear = {} }) == false and TestMode:AddCandidates(5) == 0)

	-- Put the environment back.
	H.inGroup = false
	C_Item.GetItemInfo = function() end
	C_Item.GetItemInfoInstant = nil
	C_Item.RequestLoadItemDataByID = nil
	GameTooltip.SetText, GameTooltip.AddLine = nil, nil
end

-- Awards, the confirmation dialog, the raid chat preview and the award log, on the real
-- modules. Runs before the Comm tests, which replace Council and Sessions with stand-ins.

return function(check, H)
	local Awards, Voting, Candidates, Sessions, Council, Comm = ALC.Awards, ALC.Voting, ALC.Candidates, ALC.Sessions, ALC.Council, ALC.Comm
	local LD, Win, Dialog, Loot = ALC.LootDetection, ALC.CouncilWindow, ALC.AwardDialog, ALC.LootWindow
	local STATUS = LD.STATUS
	local AceSerializer = LibStub("AceSerializer-3.0")
	local ME = "Tester Moo"

	local env = H.env

	-- Item data.
	local db = { [200] = { "Crown of Destruction", 4, "INVTYPE_HEAD" }, [300] = { "Small Paw", 1, "INVTYPE_NON_EQUIP_IGNORE" } }
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
	ALC.Gear.GetEquippedLink = function() return nil end

	-- A party we lead (group loot): the council is us, Veyra and Kaelis.
	local units = {
		player = { "Tester", "Moo", "ROGUE" },
		party1 = { "Veyra", "Moo", "WARRIOR" },
		party2 = { "Jonatan", "Moo", "PRIEST" },
		party3 = { "Kaelis", "Moo", "HUNTER" },
	}
	local realUnitName, realUnitClass = UnitName, UnitClass
	UnitName = function(unit) local u = units[unit]; if u then return u[1], u[2] end end
	UnitClass = function(unit) local u = units[unit]; if u then return u[3], u[3] end end
	UnitIsConnected = function() return true end
	H.inGroup = true
	local leader = ME
	Council.GetLootMethodInfo = function() return 3 end
	Council.GetLeaderName = function() return leader end
	Council.IsPlayerMasterLooter = function() return false end
	Comm.GetGroupNames = function()
		local names = {}
		for _, unit in ipairs(ALC:GroupUnits()) do
			local name = ALC:UnitFullName(unit)
			if name then names[#names + 1] = name end
		end
		return names
	end
	Comm:InvalidateRoster()
	Council:Refresh()
	ALC.Settings:GetDB().profile.council = {}
	ALC.Settings:AddCouncilMember("Veyra Moo")
	ALC.Settings:AddCouncilMember("Kaelis Moo")

	-- The loot window of the game and the master loot list.
	local lootSlots, candidatesBySlot, given = {}, {}, {}
	GetNumLootItems = function() return #lootSlots end
	GetLootSlotLink = function(slot) return lootSlots[slot] end
	GetMasterLootCandidate = function(slot, index) return candidatesBySlot[index] end
	local giveError
	GiveMasterLoot = function(slot, index)
		if giveError then error(giveError) end
		given[#given + 1] = { slot = slot, index = index }
	end
	local function openLootWindow(itemID, names)
		lootSlots = { "|Hitem:300|h[Small Paw]|h", "|Hitem:" .. itemID .. "|h[Item]|h" }
		candidatesBySlot = names
		Awards:SetLootOpen(true)
		Council.IsPlayerMasterLooter = function() return true end
	end
	local function closeLootWindow()
		lootSlots, candidatesBySlot = {}, {}
		Awards:SetLootOpen(false)
		Council.IsPlayerMasterLooter = function() return false end
	end

	local announced = {}
	local listener = {}
	ALC.Events.Register(listener, "ALC_AWARDS_ANNOUNCED", function(_, text) announced[#announced + 1] = text end)

	-- A session with three answers and two votes for Veyra.
	local function newSession()
		if Sessions:IsActive() then Sessions:Cancel("test reset") end
		LD:Clear()
		LD:AddFromText("200")
		LD:StartSession(LD:GetItems()[1].id)
		local sid = Sessions:GetActiveSid()
		Comm:Process(env("RESPONSE", sid, nil, { response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
		Comm:Process(env("RESPONSE", sid, nil, { response = "UPGRADE", gear = {} }), "WHISPER", "Jonatan Moo")
		Comm:Process(env("RESPONSE", sid, nil, { response = "PASS", gear = {} }), "WHISPER", "Kaelis Moo")
		Voting:Cast("Veyra Moo")
		Comm:Process(env("VOTE", sid, nil, { candidate = "Veyra Moo" }), "WHISPER", "Kaelis Moo")
		return sid
	end
	local function awardSent()
		for _, sent in ipairs(H.sent) do
			local _, e = AceSerializer:Deserialize(sent.text)
			if e and e.t == "AWARD" then return e, sent end
		end
	end
	local function reset()
		H.sent, H.said, announced, given, giveError = {}, {}, {}, {}, nil
	end
	local function logSize() return #Awards:GetLog() end

	----------------------------------------------------------------------------
	-- Refusals
	----------------------------------------------------------------------------
	reset()
	if Sessions:IsActive() then Sessions:Cancel("test reset") end
	local ok, message = Awards:Award("Veyra Moo")
	check("no award without a session", ok == false and message ~= nil)
	local sid = newSession()
	local logBefore = logSize()
	local okX, msgX = Awards:Award("Nobody Moo")
	check("no award to somebody who has not answered", okX == false and msgX ~= nil and Sessions:IsActive())
	local okP, msgP = Awards:Award("Kaelis Moo")
	check("no award to somebody who passed", okP == false and msgP ~= nil and Sessions:IsActive())
	check("a refused award logs and announces nothing", logSize() == logBefore and #H.said == 0)

	----------------------------------------------------------------------------
	-- Awarding when the item cannot be handed out: it is left to trade
	----------------------------------------------------------------------------
	reset()
	local entryId = LD:GetItems()[1].id
	check("the loot window is closed, so nothing to give now", Awards:CanGiveNow("Veyra Moo") == false)
	check("award to Veyra", Awards:Award("veyra moo") == true)
	local awardEnv, awardSend = awardSent()
	check("AWARD goes to the group", awardEnv ~= nil and awardSend.dist == "PARTY" and awardEnv.p.winner == "Veyra Moo" and awardEnv.p.response == "BIS" and awardEnv.p.itemID == 200)
	check("the session ended", not Sessions:IsActive())
	check("nothing was given through the loot window", #given == 0)
	check("the item is left to trade, with its winner", LD:GetEntry(entryId).status == STATUS.TRADE and LD:GetEntry(entryId).winner == "Veyra Moo")
	local expected = "[ALC] |Hitem:200|h[Crown of Destruction]|h -> Veyra Moo (BiS)"
	check("the winner is announced in party chat", #H.said == 1 and H.said[1].channel == "PARTY" and H.said[1].text == expected)
	check("the announcement is remembered and published", Awards:GetLastAnnouncement() == expected and announced[1] == expected)
	local log = Awards:GetLog()
	local line = log[#log]
	check("the award log has a line", logSize() == logBefore + 1 and line.winner == "Veyra Moo" and line.class == "WARRIOR"
		and line.response == "BIS" and line.itemID == 200 and line.sid == sid and line.lm == ME)
	check("with votes, item string, time and place", line.votes == 2 and line.itemString == "item:200" and type(line.time) == "number" and type(line.zone) == "string")
	check("candidates and votes are cleared", #Candidates:GetList() == 0 and Voting:GetVotes("Veyra Moo") == 0)

	-- Raid chat when in a raid, the chat window when alone.
	reset()
	sid = newSession()
	H.inRaid = true
	Awards:Award("Jonatan Moo")
	H.inRaid = false
	check("a raid gets it in raid chat", #H.said == 1 and H.said[1].channel == "RAID" and H.said[1].text:find("Jonatan Moo (Upgrade)", 1, true) ~= nil)

	reset()
	sid = newSession()
	H.inGroup = false
	local chat = #H.chat
	Awards:Award("Jonatan Moo")
	H.inGroup = true
	check("alone it is only printed", #H.said == 0 and #H.chat > chat and H.chat[#H.chat]:find("Jonatan Moo", 1, true) ~= nil)

	----------------------------------------------------------------------------
	-- Awarding through the loot window
	----------------------------------------------------------------------------
	reset()
	sid = newSession()
	openLootWindow(200, { "Tester Moo", "Jonatan Moo", "Veyra Moo" })
	check("the item can be given now", Awards:CanGiveNow("Veyra Moo") == true)
	H.deferTimers = true
	check("award to Veyra", Awards:Award("Veyra Moo") == true)
	check("the item was given to her slot and index", #given == 1 and given[1].slot == 2 and given[1].index == 3)
	local chatCount = #H.chat
	Awards:OnLootSlotCleared(2) -- the game empties the slot before the wait is over
	H.runTimers()               -- our own message comes back, the wait ends
	local awardedEntry
	for _, e in ipairs(LD:GetItems()) do if e.sid == sid then awardedEntry = e end end
	check("it counts as awarded, with its winner", awardedEntry ~= nil and awardedEntry.status == STATUS.AWARDED and awardedEntry.winner == "Veyra Moo")
	local function said(text, from)
		for i = (from or 0) + 1, #H.chat do
			if H.chat[i]:find(text, 1, true) then return true end
		end
		return false
	end
	check("once the slot empties nothing is said about a failed hand-over", not said("not handed out", chatCount))
	H.deferTimers = false

	-- The slot does not empty: the confirmation was declined.
	reset()
	sid = newSession()
	openLootWindow(200, { "Tester Moo", "Jonatan Moo", "Veyra Moo" })
	H.deferTimers = true
	Awards:Award("Veyra Moo")
	chatCount = #H.chat
	Awards:OnLootSlotCleared(5) -- some other slot: ours stays full
	H.runTimers()               -- our message comes back, then the wait runs out
	local entryNow
	for _, e in ipairs(LD:GetItems()) do if e.sid == sid then entryNow = e end end
	check("if the slot never empties it is left to trade", entryNow ~= nil and entryNow.status == STATUS.TRADE and entryNow.winner == "Veyra Moo")
	check("and the loot master is told to trade it", said("not handed out", chatCount) and said("Veyra Moo", chatCount))
	H.deferTimers = false

	-- Names in the master loot list.
	reset()
	sid = newSession()
	openLootWindow(200, { "Veyra", "Jonatan Moo", "Someone Else", "Veyra Moo" })
	Awards:Award("Veyra Moo")
	check("a full name is preferred over a first name", #given == 1 and given[1].index == 4)
	reset()
	sid = newSession()
	openLootWindow(200, { "Tester Moo", "Jonatan" })
	Awards:Award("Jonatan Moo")
	check("a first name alone still finds the player", #given == 1 and given[1].index == 2)
	reset()
	sid = newSession()
	openLootWindow(200, { "Tester Moo", "Jonatan Moo-SomeRealm" })
	Awards:Award("Jonatan Moo")
	check("a realm suffix is ignored", #given == 1 and given[1].index == 2)

	-- Cases where the item is not handed out.
	reset()
	sid = newSession()
	openLootWindow(200, { "Tester Moo", "Kaelis Moo" })
	Awards:Award("Jonatan Moo")
	check("a winner who is not a loot candidate: left to trade", #given == 0)
	reset()
	sid = newSession()
	openLootWindow(999, { "Tester Moo", "Jonatan Moo" })
	Awards:Award("Jonatan Moo")
	check("an item that is not in the loot window: left to trade", #given == 0)
	reset()
	sid = newSession()
	openLootWindow(200, { "Tester Moo", "Jonatan Moo" })
	Council.IsPlayerMasterLooter = function() return false end
	Awards:Award("Jonatan Moo")
	check("not the master looter: left to trade", #given == 0)
	closeLootWindow()
	reset()
	sid = newSession()
	openLootWindow(200, { "Tester Moo", "Jonatan Moo" })
	giveError = "no loot for you"
	local chat2 = #H.chat
	check("a failing GiveMasterLoot does not stop the award", Awards:Award("Jonatan Moo") == true and not Sessions:IsActive())
	local failedEntry
	for _, e in ipairs(LD:GetItems()) do if e.sid == sid then failedEntry = e end end
	check("it is left to trade and the loot master is told", failedEntry.status == STATUS.TRADE and #H.chat > chat2)
	closeLootWindow()

	----------------------------------------------------------------------------
	-- Only the loot master awards
	----------------------------------------------------------------------------
	reset()
	if Sessions:IsActive() then Sessions:Cancel("test reset") end
	units.party1 = { "Ashvane", "Moo", "MAGE" }
	units.party2 = { "Veyra", "Moo", "WARRIOR" }
	leader = "Ashvane Moo"
	Comm:InvalidateRoster()
	Council:Refresh()
	local council = { "Ashvane Moo", ME, "Veyra Moo" }
	Comm:Process(env("SESSION_START", "sidA", 1, { itemID = 200, itemString = "item:200", council = council, lm = "Ashvane Moo" }), "PARTY", "Ashvane Moo")
	Comm:Process(env("CANDIDATE_UPDATE", "sidA", 2, { name = "Veyra Moo", class = "WARRIOR", response = "BIS", gear = {} }), "WHISPER", "Ashvane Moo")
	local okNL, msgNL = Awards:Award("Veyra Moo")
	check("a council member who is not the loot master cannot award", okNL == false and msgNL ~= nil and Sessions:IsActive())
	Dialog:Ask("Veyra Moo")
	check("and gets no dialog", not Dialog:IsShown())
	check("the Award button is not offered", (function()
		for _, row in ipairs(Win.rows) do if row:IsShown() then return not row.award:IsShown() end end
		return false
	end)())
	Comm:Process(env("SESSION_CANCEL", "sidA", 3, { reason = "done" }), "PARTY", "Ashvane Moo")
	units.party1 = { "Veyra", "Moo", "WARRIOR" }
	units.party2 = { "Jonatan", "Moo", "PRIEST" }
	leader = ME
	Comm:InvalidateRoster()
	Council:Refresh()

	----------------------------------------------------------------------------
	-- The council window and the dialog
	----------------------------------------------------------------------------
	reset()
	sid = newSession()
	check("the voting window is open", Win:IsShown())
	local rowFor = {}
	for _, row in ipairs(Win.rows) do if row:IsShown() then rowFor[row.candidate] = row end end
	check("the loot master gets an Award button on every row", rowFor["Veyra Moo"].award:IsShown() and rowFor["Jonatan Moo"].award:IsShown())
	check("Award is amber, and Vote sits beside it", rowFor["Veyra Moo"].award.selected == true and rowFor["Veyra Moo"].vote:IsShown())

	local frame
	rowFor["Veyra Moo"].award.scripts.OnClick(rowFor["Veyra Moo"].award)
	frame = Dialog.frame
	check("Award asks first", Dialog:IsShown() and frame.item:GetText() == "Crown of Destruction" and frame.winner:GetText() == "to Veyra Moo")
	check("the dialog shows the answer and the votes", frame.details:GetText():find("BiS", 1, true) ~= nil and frame.details:GetText():find("2", 1, true) ~= nil)
	check("and says the item will be traded", frame.note:GetText():find("Awaiting trade", 1, true) ~= nil)
	frame.cancel.scripts.OnClick(frame.cancel)
	check("Cancel closes it and awards nothing", not Dialog:IsShown() and Sessions:IsActive() and #H.said == 0)

	openLootWindow(200, { "Tester Moo", "Veyra Moo" })
	rowFor["Veyra Moo"].award.scripts.OnClick(rowFor["Veyra Moo"].award)
	check("with the loot window open it says the item is handed out", frame.note:GetText():find("handed out", 1, true) ~= nil)
	frame.confirm.scripts.OnClick(frame.confirm)
	check("Confirm awards", not Dialog:IsShown() and not Sessions:IsActive() and #H.said == 1 and #given == 1)
	closeLootWindow()

	-- The dialog closes with the session.
	reset()
	sid = newSession()
	Dialog:Ask("Jonatan Moo")
	check("the dialog is open", Dialog:IsShown())
	Sessions:Cancel("changed my mind")
	check("and closes when the session ends", not Dialog:IsShown())

	----------------------------------------------------------------------------
	-- The raid chat preview in the loot window
	----------------------------------------------------------------------------
	reset()
	Loot:Show()
	local lootFrame = Loot.rows[1].parent
	local before = lootFrame:GetHeight()
	check("the preview shows the last announcement", lootFrame.chatBox:IsShown() and lootFrame.chatText:GetText() == Awards:GetLastAnnouncement())
	check("in the orange of raid chat", lootFrame.chatText.textColor[1] > 0.9 and lootFrame.chatText.textColor[3] < 0.5)
	sid = newSession()
	Awards:Award("Jonatan Moo")
	check("a new award updates it", lootFrame.chatText:GetText():find("Jonatan Moo", 1, true) ~= nil)
	check("the row shows the winner", (function()
		for _, e in ipairs(LD:GetItems()) do if e.sid == sid then return e.winner == "Jonatan Moo" end end
	end)())
	Loot:Hide()

	----------------------------------------------------------------------------
	-- The History tab
	----------------------------------------------------------------------------
	reset()
	Win:Hide()
	if Sessions:IsActive() then Sessions:Cancel("test reset") end
	Win:ShowHistory()
	local hframe = Win.rows[1].parent
	check("the history opens without a session", Win:IsShown() and Win:GetTab() == "history")
	check("the History tab is marked", Win.tabs.history.underline:IsShown() and not Win.tabs.council.underline:IsShown())
	check("the Council tab's widgets are hidden", not hframe.name:IsShown() and not Win.rows[1]:IsShown() and hframe.historyEmpty:IsShown() == false)
	local history, log = Win:GetHistory(), Awards:GetLog()
	check("the newest award comes first", #history == #log and history[1] == log[#log] and history[#history] == log[1])
	local top = Win.historyRows[1]
	check("a row tells what, to whom and with which answer", top.item.text:GetText() == "Crown of Destruction"
		and top.winner:GetText() == history[1].winner and top.chip.label:GetText() ~= nil and top.time:GetText() ~= nil)
	check("and the votes", top.votes:GetText() == (history[1].votes > 0 and tostring(history[1].votes) or "\226\128\148"))
	top.item.scripts.OnEnter(top.item)
	check("hovering the item shows its tooltip", GameTooltip.hyperlink == history[1].itemString)
	check("the footer counts the awards", hframe.historyCount:GetText() == (#history .. " awards"))
	H.slash("history")
	check("/alc history closes it when it is on that tab", not Win:IsShown())
	H.slash("history")
	check("and opens it again", Win:IsShown() and Win:GetTab() == "history")

	-- A long history scrolls.
	for i = 1, 14 do
		reset()
		newSession()
		Awards:Award(i % 2 == 1 and "Veyra Moo" or "Jonatan Moo")
	end
	history = Win:GetHistory()
	Win:ShowHistory() -- every session closed the window
	check("many awards", #history >= 15)
	check("twelve rows show at most, with a scrollbar", Win.historyRows[12]:IsShown() and hframe.historyScroll:IsShown())
	local firstWinner = Win.historyRows[1].winner:GetText()
	hframe.scripts.OnMouseWheel(hframe, -1)
	check("scrolling moves the list one award", Win.historyRows[1].winner:GetText() == history[2].winner and history[2].winner ~= firstWinner)
	for _ = 1, 30 do hframe.scripts.OnMouseWheel(hframe, -1) end
	check("scrolling stops at the oldest award", Win.historyRows[12].winner:GetText() == history[#history].winner)
	for _ = 1, 30 do hframe.scripts.OnMouseWheel(hframe, 1) end
	check("and at the newest", Win.historyRows[1].winner:GetText() == history[1].winner)
	local bar = hframe.historyScroll
	H.cursor = { 0, bar:GetTop() - bar:GetHeight() }
	bar.scripts.OnMouseDown(bar)
	bar.scripts.OnMouseUp(bar)
	check("the scrollbar jumps to the oldest awards", Win.historyRows[12].winner:GetText() == history[#history].winner)

	-- Switching tabs.
	Win:ShowHistory()
	Win.tabs.council.scripts.OnClick(Win.tabs.council)
	check("the Council tab without a session shows a hint", Win:GetTab() == "council" and hframe.idle:IsShown() and not hframe.name:IsShown() and not Win.rows[1]:IsShown())
	check("and the window is short", hframe:GetHeight() < 300)
	Win.tabs.history.scripts.OnClick(Win.tabs.history)
	check("the History tab brings the list back", Win:GetTab() == "history" and not hframe.idle:IsShown() and Win.historyRows[1]:IsShown())
	reset()
	newSession()
	check("a new session switches to the voting tab", Win:IsShown() and Win:GetTab() == "council" and hframe.name:IsShown() and not Win.historyRows[1]:IsShown())
	check("the tab buttons follow", Win.tabs.council.underline:IsShown() and not Win.tabs.history.underline:IsShown())

	-- After a session the window closes ...
	Awards:Award("Veyra Moo")
	check("by default an award closes the voting window", not Win:IsShown())
	-- ... unless the player keeps it open.
	ALC.Settings:SetKeepCouncilOpen(true)
	reset()
	newSession()
	check("with the option on the window opens as usual", Win:IsShown() and Win:GetTab() == "council")
	Awards:Award("Jonatan Moo")
	check("an award leaves it open, on the same tab", Win:IsShown() and Win:GetTab() == "council")
	Win:SetTab("history")
	check("and the new award is in the history", Win.historyRows[1].winner:GetText() == "Jonatan Moo")
	Win:SetTab("council")
	reset()
	newSession()
	Sessions:Cancel("changed my mind")
	check("a cancelled session leaves it open on the next items", Win:IsShown() and Win:GetTab() == "council" and Win.queueRows[1]:IsShown())
	ALC.Settings:SetKeepCouncilOpen(false)
	reset()
	newSession()
	Sessions:Cancel("again")
	check("switched off again, a session end closes it", not Win:IsShown())

	-- The loot master as winner: the item is already in the loot master's bags, so there is nothing to trade.
	reset()
	sid = newSession()
	ALC.Responses:Send("BIS")
	check("the loot master can award to itself", Awards:Award(ME) == true)
	local ownEntry
	for _, e in ipairs(LD:GetItems()) do if e.sid == sid then ownEntry = e end end
	check("and that is not left to trade", ownEntry ~= nil and ownEntry.status == STATUS.AWARDED and ownEntry.winner == ME)

	----------------------------------------------------------------------------
	-- Awarding many items in a row, from one window
	----------------------------------------------------------------------------
	ALC.Settings:SetKeepCouncilOpen(true)
	reset()
	if Sessions:IsActive() then Sessions:Cancel("test reset") end
	LD:Clear()
	Win:Hide()
	LD:AddFromText("200 200 200")
	local ids = {}
	for i, e in ipairs(LD:GetItems()) do ids[i] = e.id end
	local function answer(sessionId, name, response, gear)
		Comm:Process(env("RESPONSE", sessionId, nil, { response = response, gear = gear or {} }), "WHISPER", name)
	end

	LD:StartSession(ids[1])
	local firstSid = Sessions:GetActiveSid()
	answer(firstSid, "Veyra Moo", "BIS")
	answer(firstSid, "Jonatan Moo", "UPGRADE")
	check("the voting window opens with the first session", Win:IsShown() and Win:GetTab() == "council")
	Awards:Award("Veyra Moo")
	check("after the award the window is still there", Win:IsShown() and Win:GetTab() == "council")
	check("it offers the next two items", Win.queueRows[1]:IsShown() and Win.queueRows[2]:IsShown() and not Win.queueRows[3]:IsShown())
	check("the list replaces the hint", not hframe.idle:IsShown() and hframe.queueLabel:IsShown())
	check("a queue row names the item", Win.queueRows[1].name:GetText() == "Crown of Destruction")
	local nextStart = Win.queueRows[1].start
	nextStart.scripts.OnClick(nextStart)
	check("Start there starts the next session", Sessions:IsActive() and Sessions:GetActiveSid() ~= firstSid)
	check("in the same window, on the same tab", Win:IsShown() and Win:GetTab() == "council" and hframe.name:IsShown() and not Win.queueRows[1]:IsShown())
	answer(Sessions:GetActiveSid(), "Jonatan Moo", "UPGRADE")
	Awards:Award("Jonatan Moo")
	check("and again: the last item is offered", Win:IsShown() and Win.queueRows[1]:IsShown() and not Win.queueRows[2]:IsShown())
	Win.queueRows[1].start.scripts.OnClick(Win.queueRows[1].start)
	answer(Sessions:GetActiveSid(), "Veyra Moo", "MINOR")
	Awards:Award("Veyra Moo")
	check("with nothing left the hint returns", Win:IsShown() and hframe.idle:IsShown() and not Win.queueRows[1]:IsShown())
	check("three awards were made without the window ever closing", LD:GetItems()[3].status ~= LD.STATUS.PENDING)

	----------------------------------------------------------------------------
	-- The trade queue
	----------------------------------------------------------------------------
	local Trades = ALC.Trades
	local traded, inRange = {}, true
	InitiateTrade = function(unit) traded[#traded + 1] = unit end
	CheckInteractDistance = function() return inRange end
	local realConnected = UnitIsConnected

	local pending = Trades:GetPending()
	check("the three awards wait for a trade, oldest first", #pending == 3 and pending[1].winner == "Veyra Moo"
		and pending[2].winner == "Jonatan Moo" and pending[3].winner == "Veyra Moo" and pending[1].id < pending[3].id)
	check("the tab counts them in a badge", Win.tabs.trades.badge:IsShown() and Win.tabs.trades.badge.text:GetText() == "3")
	Win:SetTab("trades")
	local trows = Win.tradeRows
	check("the tab lists them", Win:GetTab() == "trades" and trows[3]:IsShown() and not trows[4]:IsShown() and trows[1].winner:GetText() == "Veyra Moo"
		and trows[1].item.text:GetText() == "Crown of Destruction" and trows[2].winner:GetText() == "Jonatan Moo")
	check("with how long ago", trows[1].when:GetText() == "just now")
	check("the tab is marked and the others are hidden", Win.tabs.trades.underline:IsShown() and not hframe.name:IsShown() and hframe.tradeCount:GetText() == "3 waiting")
	check("the Trade button is offered for players in the group", trows[1].trade.available == true and trows[2].trade.available == true)

	trows[1].trade.scripts.OnClick(trows[1].trade)
	check("Trade opens a trade with the winner", #traded == 1 and traded[1] == "party1")
	check("and leaves the item in the queue", Trades:GetPendingCount() == 3)
	inRange = false
	local chatBefore = #H.chat
	trows[1].trade.scripts.OnClick(trows[1].trade)
	check("out of range is explained, no trade is opened", #traded == 1 and H.chat[#H.chat]:find("too far", 1, true) ~= nil and #H.chat > chatBefore)
	inRange = true
	UnitIsConnected = function() return false end
	trows[1].trade.scripts.OnClick(trows[1].trade)
	check("offline is explained", #traded == 1 and H.chat[#H.chat]:find("offline", 1, true) ~= nil)
	UnitIsConnected = realConnected
	local savedParty1 = units.party1
	units.party1 = nil
	Win:Refresh()
	check("a winner who left the group cannot be traded with", trows[1].trade.available == false and trows[1].note:GetText():find("Not in the group", 1, true) ~= nil)
	local ok3, msg3 = Trades:StartTrade(pending[1].id)
	check("and says so", ok3 == false and msg3:find("not in your group", 1, true) ~= nil)
	units.party1 = savedParty1
	Win:Refresh()

	-- The loot master as winner has nothing to trade.
	local store = ALC.Settings:GetLootStore()
	LD:AddFromText("200")
	local self = store.items[#store.items]
	self.winner, self.status = ME, LD.STATUS.TRADE
	local ok4, msg4 = Trades:StartTrade(self.id)
	check("no trade with yourself", ok4 == false and msg4:find("yourself", 1, true) ~= nil)
	LD:Remove(self.id)
	check("an item that is not waiting cannot be traded", Trades:StartTrade(999999) == false and Trades:MarkDone(999999) == false)

	-- Done by hand.
	trows[1].done.scripts.OnClick(trows[1].done)
	check("Done takes the item out of the queue", Trades:GetPendingCount() == 2 and trows[3]:IsShown() == false)
	check("it counts as awarded", LD:GetEntry(pending[1].id).status == LD.STATUS.AWARDED and LD:GetEntry(pending[1].id).winner == "Veyra Moo")
	check("the badge follows", Win.tabs.trades.badge.text:GetText() == "2")
	check("Done twice does nothing", Trades:MarkDone(pending[1].id) == false)

	-- A trade that goes through delivers the item on its own.
	GetTradePlayerItemLink = function(slot) if slot == 1 then return "|Hitem:200|h[Crown]|h" end end
	units.NPC = { "Veyra", "Moo", "WARRIOR" }
	Trades:OnTradeAcceptUpdate(1, 0)
	check("a trade only we accepted is not counted", Trades:OnTradeComplete() == 0 and Trades:GetPendingCount() == 2)
	Trades:OnTradeAcceptUpdate(1, 1)
	local chatCount = #H.chat
	check("a completed trade delivers the item", Trades:OnTradeComplete() == 1 and Trades:GetPendingCount() == 1)
	check("to the right winner: Jonatan's item is still waiting", Trades:GetPending()[1].winner == "Jonatan Moo")
	check("and says so", H.chat[#H.chat]:find("delivered to Veyra Moo", 1, true) ~= nil and #H.chat > chatCount)
	check("the same trade cannot count twice", Trades:OnTradeComplete() == 0)

	units.NPC = { "Kaelis", "Moo", "HUNTER" }
	Trades:OnTradeAcceptUpdate(1, 1)
	check("an item given to somebody else's is not delivered", Trades:OnTradeComplete() == 0 and Trades:GetPendingCount() == 1)
	units.NPC = { "Jonatan", "Moo", "PRIEST" }
	GetTradePlayerItemLink = function(slot) if slot == 1 then return "|Hitem:999|h[Other]|h" end end
	Trades:OnTradeAcceptUpdate(true, true)
	check("another item to the winner is not delivered either", Trades:OnTradeComplete() == 0 and Trades:GetPendingCount() == 1)

	GetTradePlayerItemLink = function(slot) if slot == 1 then return "|Hitem:200|h[Crown]|h" end end
	H.deferTimers = true -- the game keeps the note a few seconds after the window closes
	Trades:OnTradeAcceptUpdate(true, true)
	Trades:OnTradeClosed()
	check("the note survives the window closing: the message may come after", Trades:OnTradeComplete() == 1 and Trades:GetPendingCount() == 0)
	H.runTimers()
	H.deferTimers = false
	check("the queue is empty", Win.tabs.trades.badge:IsShown() == false and hframe.tradeEmpty:IsShown() and hframe.tradeCount:GetText() == "0 waiting")

	LD:AddFromText("200")
	local late = LD:GetItems()[#LD:GetItems()]
	local lateEntry = store.items[#store.items]
	lateEntry.winner, lateEntry.status = "Jonatan Moo", LD.STATUS.TRADE
	H.deferTimers = true
	Trades:OnTradeAcceptUpdate(1, 1)
	Trades:OnTradeClosed()
	H.runTimers()
	check("an old note is dropped after a moment", Trades:OnTradeComplete() == 0 and Trades:GetPendingCount() == 1)
	H.deferTimers = false

	-- More items than fit: the list says how many are left.
	Win:SetTab("council")
	LD:Clear()
	LD:AddFromText("200 200 200 200 200 200 200 200")
	Win:Refresh()
	check("only six are offered, the rest are counted", Win.queueRows[6]:IsShown() and hframe.queueMore:IsShown() and hframe.queueMore:GetText():find("2 more", 1, true) ~= nil)
	LD:Clear()

	-- A session without a loot master's list: only a hint for a player who is not the loot master.
	Council.GetLeaderName = function() return "Ashvane Moo" end
	Council:Refresh()
	LD:AddFromText("200")
	Win:Refresh()
	check("a player who is not the loot master only gets the hint", hframe.idle:IsShown() and not Win.queueRows[1]:IsShown())
	Council.GetLeaderName = function() return ME end
	Council:Refresh()
	LD:Clear()

	----------------------------------------------------------------------------
	-- Compact rows and the grip
	----------------------------------------------------------------------------
	LD:AddFromText("200")
	LD:StartSession(LD:GetItems()[1].id)
	local sidC = Sessions:GetActiveSid()
	answer(sidC, "Veyra Moo", "BIS", { "item:151", "item:152" })
	answer(sidC, "Jonatan Moo", "UPGRADE")
	answer(sidC, "Kaelis Moo", "MINOR")
	ALC.Responses:Send("OFFSPEC")
	Win:Show()
	local tall = hframe:GetHeight()
	local crows = Win.rows
	check("rows are tall by default", crows[1].h == 56 and crows[1].class:IsShown() and hframe.compact.checked == false)
	hframe.compact.scripts.OnClick(hframe.compact)
	check("the compact option is remembered", ALC.Settings:GetWindowOption("council", "compact", false) == true)
	check("compact rows are lower, with the class left out", crows[1].h == 40 and not crows[1].class:IsShown() and hframe:GetHeight() < tall)
	check("only the first item of gear shows, the rest is counted", crows[1].gear[1]:IsShown() and not crows[1].gear[2]:IsShown() and crows[1].more:GetText() == "+1")
	check("a row with one item of gear counts nothing extra", crows[2].more:GetText() == "")
	check("the buttons are lower too", crows[1].vote.h == 26 and crows[1].award.h == 26)
	hframe.compact.scripts.OnClick(hframe.compact)
	check("switching back gives tall rows again", crows[1].h == 56 and crows[1].class:IsShown() and crows[1].more:GetText() == "" and hframe:GetHeight() == tall)

	check("the grip is offered on the voting tab", hframe.grip:IsShown())
	hframe.grip.scripts.OnMouseDown(hframe.grip)
	check("dragging anchors the window by its top edge", hframe.point[1] == "TOPLEFT" and hframe.point[3] == "BOTTOMLEFT")
	local fixed = 60 + 92 + 34 + 52 -- header, item, headings and footer
	H.cursor = { 0, hframe:GetTop() - fixed - 4 * 56 }
	hframe.grip.scripts.OnUpdate(hframe.grip)
	check("the mouse decides how many rows: four", ALC.Settings:GetWindowOption("council", "maxRows", 10) == 4)
	H.cursor = { 0, -9999 }
	hframe.grip.scripts.OnUpdate(hframe.grip)
	check("never more than 30", ALC.Settings:GetWindowOption("council", "maxRows", 10) == 30)
	H.cursor = { 0, 99999 }
	hframe.grip.scripts.OnUpdate(hframe.grip)
	check("never fewer than 3", ALC.Settings:GetWindowOption("council", "maxRows", 10) == 3)
	hframe.grip.scripts.OnMouseUp(hframe.grip)
	check("letting go stops it and saves the position", hframe.grip.scripts.OnUpdate == nil and ALC.Settings:GetWindowPosition("council").point == "TOPLEFT")
	hframe.grip.scripts.OnEnter(hframe.grip)
	hframe.grip.scripts.OnLeave(hframe.grip)
	ALC.Settings:SetWindowOption("council", "maxRows", 0) -- a damaged saved value
	Win:Refresh()
	check("a broken saved row count still shows three rows", crows[3]:IsShown() and not crows[4]:IsShown())
	ALC.Settings:SetWindowOption("council", "maxRows", 10)
	Win:SetTab("history")
	check("the grip only belongs to the voting tab", not hframe.grip:IsShown())
	Win:SetTab("council")
	Sessions:Cancel("done")

	----------------------------------------------------------------------------
	-- The tabs
	----------------------------------------------------------------------------
	local icons = ALC.UI.ICONS
	check("every tab has its icon", Win.tabs.council.icon.texture == icons .. "council" and Win.tabs.history.icon.texture == icons .. "history"
		and Win.tabs.trades.icon.texture == icons .. "trade" and Win.tabs.settings.icon.texture == icons .. "settings")
	check("the active tab is marked in amber", Win.tabs.council.underline:IsShown() and Win.tabs.council.label.textColor[1] == ALC.UI.color.gold[1]
		and Win.tabs.history.label.textColor[1] == ALC.UI.color.muted[1])
	Win.tabs.settings.scripts.OnClick(Win.tabs.settings)
	check("the Settings tab opens the settings window and does not change the tab", ALC.SettingsWindow:IsShown() and Win:GetTab() == "council")
	check("and is never marked", not Win.tabs.settings.underline:IsShown())
	ALC.SettingsWindow:Hide()

	-- Done with the window options: back to the defaults.
	LD:Clear()
	Win:Hide()
	ALC.Settings:SetKeepCouncilOpen(false)

	----------------------------------------------------------------------------
	-- /alc award
	----------------------------------------------------------------------------
	reset()
	sid = newSession()
	local before2 = logSize()
	H.slash("award veyra moo")
	check("/alc award awards without asking", not Sessions:IsActive() and logSize() == before2 + 1 and #H.said == 1)
	local chat3 = #H.chat
	H.slash("award")
	check("/alc award without a name prints usage", #H.chat == chat3 + 1)
	H.slash("award Nobody Moo")
	check("and refusals are printed", #H.chat == chat3 + 2)

	-- The log only grows.
	check("the log is append only", logSize() > 3 and Awards:GetLog()[1].winner ~= nil)

	-- Put the environment back for the following tests.
	ALC.Events.UnregisterAll(listener)
	UnitName, UnitClass = realUnitName, realUnitClass
	UnitIsConnected = function() return true end
	H.inGroup, H.inRaid = false, false
	C_Item.GetItemInfo = function() end
	C_Item.GetItemInfoInstant = nil
	C_Item.RequestLoadItemDataByID = nil
	Council.GetLeaderName = function() return nil end
	Council.IsPlayerMasterLooter = function() return false end
	Awards:SetLootOpen(false)
	Comm:InvalidateRoster()
	LD:Clear()
end

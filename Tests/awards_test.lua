-- Awards, the confirmation dialog, the raid chat preview and the award log, on the real
-- modules. Runs before the Comm tests, which replace Council and Sessions with stand-ins.

return function(check, H)
	local Awards, Voting, Candidates, Sessions, Council, Comm = ALC.Awards, ALC.Voting, ALC.Candidates, ALC.Sessions, ALC.Council, ALC.Comm
	local LD, Win, Dialog, Loot = ALC.LootDetection, ALC.CouncilWindow, ALC.AwardDialog, ALC.LootWindow
	local STATUS = LD.STATUS
	local AceSerializer = LibStub("AceSerializer-3.0")
	local ME = "Tester Moo"

	local function env(t, sid, seq, p) return { v = 1, t = t, sid = sid, seq = seq, p = p } end

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
	UnitIsConnected = nil
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

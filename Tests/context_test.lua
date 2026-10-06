-- The Context: what the council knows about a candidate (the loot master reads the award log, a council member asks for it).

return function(check, H)
	local ME = "Tester Moo"
	local env = H.env
	local DAY = 86400

	local db = {
		[200] = { "Crown of Destruction", 4, "INVTYPE_HEAD", 70 },
		[201] = { "Belt of Might", 4, "INVTYPE_WAIST", 70 },
		[202] = { "Ring of Focus", 4, "INVTYPE_FINGER", 70 },
		[210] = { "Plaguefang", 4, "INVTYPE_WEAPON", 76 },
		[211] = { "Twinblade of Echoes", 4, "INVTYPE_2HWEAPON", 63 },
		[212] = { "Shield of Dawn", 4, "INVTYPE_SHIELD", 66 },
	}
	local leader = ME
	local function idOf(item) return tonumber(item) or tonumber(tostring(item):match("item:(%d+)")) end
	local function world()
		local units = {
			player = { "Tester", "Moo", "ROGUE" },
			party1 = { "Veyra", "Moo", "WARRIOR" },
			party2 = { "Ashvane", "Moo", "PRIEST" },
		}
		C_Item.GetItemInfoInstant = function(item)
			local d = db[idOf(item)]
			if d then return idOf(item), "Armor", "Plate", d[3], 133101 end
		end
		C_Item.GetItemInfo = function(item)
			local id = idOf(item)
			local d = db[id]
			if d then return d[1], "|Hitem:" .. id .. "|h[" .. d[1] .. "]|h", d[2], d[4], 0, "Armor", "Plate", 1, d[3], 133101 end
		end
		C_Item.RequestLoadItemDataByID = function() end
		UnitName = function(unit) local u = units[unit]; if u then return u[1], u[2] end end
		UnitClass = function(unit) local u = units[unit]; if u then return u[3], u[3] end end
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

	----------------------------------------------------------------------------
	-- The loot master's own view
	----------------------------------------------------------------------------
	H.reload("fresh")
	leader = ME
	world()
	H.setupFrames()
	H.deferTimers = true
	H.timers = {}
	local Context, Sessions, Comm = ALC.Context, ALC.Sessions, ALC.Comm
	local function run() H.runTimers() end

	-- slots
	check("a weapon is a weapon in either hand and two-handed", Context.SlotOf(210) == "weapon" and Context.SlotOf(211) == "weapon")
	check("a shield is an off-hand, a ring a ring", Context.SlotOf(212) == "offhand" and Context.SlotOf(202) == "finger" and Context.SlotLabel("weapon") == "Weapon")
	check("an unknown item has no slot", Context.SlotOf(999) == nil and Context.SlotLabel(nil) == nil)

	-- the award log: Veyra's awards, and others that must not count
	local now = time()
	local log = ALC.Settings:GetAwardLog()
	local function award(winner, itemID, secondsAgo, extra)
		local r = { itemID = itemID, itemString = "item:" .. itemID, winner = winner, response = "BIS", responseLabel = "BiS", responseColor = { 0.3, 0.8, 0.3 },
			time = now - secondsAgo, zone = "Karazhan" }
		for k, v in pairs(extra or {}) do r[k] = v end
		log[#log + 1] = r
	end
	award("Veyra Moo", 211, 3 * DAY)                    -- a weapon, three days ago: this week
	award("Veyra Moo", 202, 10 * DAY, { zone = "Gruul's Lair" }) -- a ring, ten days ago
	award("Veyra Moo", 201, 3 * 3600)                   -- a belt, three hours ago ...
	award("Ashvane Moo", 200, 3.5 * 3600)               -- ... and somebody else's, which keeps the night going
	award("Veyra Moo", 200, 3600)                       -- a head, an hour ago: tonight
	award("Veyra Moo", 210, 2 * DAY, { response = "DISENCHANT" })           -- not an award to the player
	award("Veyra Moo", 212, 2 * DAY, { revoked = true })                    -- taken back
	award("Kaelis Moo", 210, 2 * DAY)                                       -- another player

	check("the raid night began three and a half hours ago (awards less than four hours apart)", Context.NightStart(now) == now - 3.5 * 3600)
	award("Ashvane Moo", 202, 20 * 3600)
	check("an award a day ago does not stretch it", Context.NightStart(now) == now - 3.5 * 3600)
	check("with nothing in the last four hours there is no night", Context.NightStart(now + 10 * 3600) == nil)

	-- a session on a weapon, and Veyra answers with a worse two-hander equipped
	Sessions:StartItems({ 210, 200 })
	run()
	local sid = Sessions:GetActiveSid()
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "BIS", gear = { "item:211" }, note = "my first one" }), "WHISPER", "Veyra Moo")
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Ashvane Moo")
	run()
	local info = Context:Build("Veyra Moo", 1)
	check("a candidate has a context", info ~= nil and info.name == "Veyra Moo" and info.class == "WARRIOR" and info.waiting == false)
	check("with the answer, its colour and the note", info.label == "BiS" and info.response == "BIS" and info.note == "my first one")
	check("and the item: its slot and level", info.item.itemID == 210 and info.item.slot == "weapon" and info.item.slotLabel == "Weapon" and info.item.ilvl == 76 and info.item.name == "Plaguefang")
	check("what is worn and how the item compares", #info.gear == 1 and info.gear[1].ilvl == 63 and info.ilvlDelta == 13 and info.emptySlot == false)
	check("somebody with nothing in the slot has an empty slot", Context:Build("Ashvane Moo", 1).emptySlot == true and Context:Build("Ashvane Moo", 1).ilvlDelta == nil)
	check("the history is newest first and only the player's own awards", #info.history == 4 and info.history[1].itemID == 200 and info.history[2].itemID == 201
		and info.history[3].itemID == 211 and info.history[4].itemID == 202)
	check("a disenchant, a revoked award and other players' awards are left out", info.total == 4)
	check("the same slot: Veyra has had a weapon before, and it says which", #info.sameSlot == 1 and info.sameSlot[1].itemID == 211 and info.sameSlot[1].sameSlot == true)
	check("tonight, this week and older are told apart", info.history[1].tag == "tonight" and info.history[2].tag == "tonight" and info.history[3].tag == "week" and info.history[4].tag == "older")
	check("each award knows its answer, its zone and its date", info.history[4].label == "BiS" and info.history[4].zone == "Gruul's Lair" and info.history[4].dateText:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil)
	check("how many awards in 7, 14 and 30 days, and since when", info.counts[7] == 3 and info.counts[14] == 4 and info.counts[30] == 4 and info.lastAgo == 0)
	check("the colour of an answer is kept as text", info.history[1].color == "4dcc4d" or info.history[1].color ~= nil)
	check("an item the player has not won has no same-item entry", #info.sameItem == 0)
	local second = Context:Build("Veyra Moo", 2) -- the head
	check("the same item shows when it is won again: the head is already hers", #second.sameItem == 1 and second.sameItem[1].itemID == 200 and second.sameItem[1].sameItem == true)
	check("and its slot is head", second.item.slot == "head" and #second.sameSlot == 1)
	check("a candidate who is not in the session has a waiting context", Context:Build("Kaelis Moo", 1).waiting == true and #Context:Build("Kaelis Moo", 1).history == 1)
	check("no session, no context", (function() return Context:Build("Veyra Moo", 9) ~= nil end)())

	-- Arbiter Context: a click on a row in the Council window opens the box beside it
	local Win, Ctx = ALC.CouncilWindow, ALC.ContextWindow
	Win:Show()
	local veyraRow
	for _, row in ipairs(Win.rows) do if row.candidate == "Veyra Moo" and row:IsShown() then veyraRow = row end end
	check("the Council window lists Veyra", veyraRow ~= nil)
	check("nothing is open until a row is clicked", Win:GetSelected() == nil and not Ctx:IsShown())
	veyraRow.scripts.OnClick(veyraRow, "RightButton")
	check("a right click opens the row's menu, not Arbiter Context", Win:GetSelected() == nil and not Ctx:IsShown())
	ALC.ContextMenu:Hide()
	veyraRow.scripts.OnClick(veyraRow, "LeftButton")
	check("a click picks the candidate and Arbiter Context opens", Win:GetSelected() == "Veyra Moo" and Ctx:IsShown())
	local box = Ctx:GetFrame()
	check("it names the player and the rank column", box.name:GetText() == "Veyra Moo" and box.answer:GetText() == "BiS")
	check("it shows the note in full and the item with its slot and level", box.note:GetText():find("my first one", 1, true) ~= nil
		and box.itemLine:GetText():find("Plaguefang", 1, true) ~= nil and box.itemLine:GetText():find("Weapon", 1, true) ~= nil and box.itemLine:GetText():find("ilvl 76", 1, true) ~= nil)
	check("and what is worn with the level difference", box.wearLine:GetText():find("Twinblade of Echoes", 1, true) ~= nil and box.wearLine:GetText():find("+13", 1, true) ~= nil)
	check("the same slot is told in the amber panel: a weapon before, with the date", box.slotPanel:IsShown() and box.slotText:GetText():find("Weapon", 1, true) ~= nil
		and box.slotText:GetText():find("Twinblade of Echoes", 1, true) ~= nil)
	check("the history rows are newest first with the tags", Ctx.histRows[1]:IsShown() and Ctx.histRows[1].name:GetText() == "Crown of Destruction" and Ctx.histRows[1].tag:GetText() == "TONIGHT"
		and Ctx.histRows[3].name:GetText() == "Twinblade of Echoes" and Ctx.histRows[3].badge:GetText() == "SAME SLOT" and Ctx.histRows[1].badge:GetText() == "")
	check("a summary says how many awards", box.histSummary:GetText():find("4 awards", 1, true) ~= nil)
	Win:SetFocus(2)
	check("another item of the session: the box follows (the head she has already won)", box.slotText:GetText():find("already won this item", 1, true) ~= nil and box.itemLine:GetText():find("Crown of Destruction", 1, true) ~= nil)
	Win:SetFocus(1)
	veyraRow.scripts.OnClick(veyraRow, "LeftButton")
	check("a second click on the same row lets go and closes the box", Win:GetSelected() == nil and not Ctx:IsShown())
	veyraRow.scripts.OnClick(veyraRow, "LeftButton")
	Win:Hide()
	check("closing the Council window closes Arbiter Context", not Ctx:IsShown())
	Win:Show()
	veyraRow.scripts.OnClick(veyraRow, "LeftButton")
	box.name:GetText()
	ALC.CouncilWindow:ClearSelected()
	check("the box's own close button lets go too", Win:GetSelected() == nil and not Ctx:IsShown())
	-- Arbiter Compare: Ctrl-click a second row
	local ashRow
	for _, row in ipairs(Win.rows) do if row.candidate == "Ashvane Moo" and row:IsShown() then ashRow = row end end
	local Cmp = ALC.CompareWindow
	check("Ashvane is listed too", ashRow ~= nil and Cmp ~= nil)
	if ashRow then
		local ctrl = true
		_G.IsControlKeyDown = function() return ctrl end
		ashRow.scripts.OnClick(ashRow, "LeftButton")
		check("Ctrl alone with nobody picked just picks", Win:GetSelected() == "Ashvane Moo" and Win:GetCompare() == nil and Ctx:IsShown() and not Cmp:IsShown())
		veyraRow.scripts.OnClick(veyraRow, "LeftButton")
		check("Ctrl-click on a second row opens the comparison instead of the box", Win:GetSelected() == "Ashvane Moo" and Win:GetCompare() == "Veyra Moo" and Cmp:IsShown() and not Ctx:IsShown())
		local cf = Cmp:GetFrame()
		check("the comparison names both players", cf.nameA:GetText() == "Ashvane Moo" and cf.nameB:GetText() == "Veyra Moo")
		local text = {}
		local function cellText(pool)
			local t = {}
			for _, line in ipairs(pool) do if line:IsShown() then t[#t + 1] = line.fs:GetText() or "" end end
			return table.concat(t, " / ")
		end
		local itemLines = 0
		for _, row in ipairs(cf.rows) do
			if row.label:IsShown() then text[#text + 1] = row.label:GetText() .. "=" .. cellText(row.a) .. "|" .. cellText(row.b) end
			for _, pool in ipairs({ row.a, row.b }) do for _, line in ipairs(pool) do if line:IsShown() and line.item then itemLines = itemLines + 1 end end end
		end
		local joined = table.concat(text, "\n")
		check("it has the answer, wearing, same-slot and last-7-days lines", joined:find("ANSWER", 1, true) and joined:find("WEARING", 1, true) and joined:find("SAME SLOT", 1, true) and joined:find("LAST 7 DAYS", 1, true))
		check("Veyra's earlier weapon shows on her side", joined:find("Twinblade of Echoes", 1, true) ~= nil)
		check("the items in the table have a tooltip", itemLines > 0)
		ashRow.scripts.OnClick(ashRow, "LeftButton")
		check("Ctrl-click on the first lets it go: the second stays alone", Win:GetSelected() == "Veyra Moo" and Win:GetCompare() == nil and Ctx:IsShown() and not Cmp:IsShown())
		ashRow.scripts.OnClick(ashRow, "LeftButton")
		check("Ctrl-click on another row brings the comparison back", Win:GetCompare() == "Ashvane Moo" and Cmp:IsShown())
		Win:ClearCompare()
		check("the comparison's x goes back to one candidate", Win:GetCompare() == nil and Ctx:IsShown() and not Cmp:IsShown())
		ctrl = false
		Win:ClearSelected()
		check("closing everything hides both", not Ctx:IsShown() and not Cmp:IsShown())
		_G.IsControlKeyDown = nil
	end
	-- a candidate who has not answered
	local waitingRow
	for _, row in ipairs(Win.rows) do if row.candidate == "Tester Moo" and row:IsShown() then waitingRow = row end end
	if waitingRow then
		waitingRow.scripts.OnClick(waitingRow, "LeftButton")
		check("a player who has not answered gets a box that says so", Ctx:IsShown() and box.answer:GetText() == "Has not answered yet")
		waitingRow.scripts.OnClick(waitingRow, "LeftButton")
	end
	Win:Hide()

	-- a session that says who reserved the item (Soft Reserve) shows it in the box
	Sessions:Cancel("again")
	run()
	Sessions:StartItems({ 210 }, { mode = "SR", modeName = "Soft Reserve", modeColor = "9B7BFF",
		extra = { [1] = { mark = "SR", markFor = { "Veyra", "Kaelis Moo" } } } })
	run()
	local sid2 = Sessions:GetActiveSid()
	Comm:Process(env("RESPONSE", sid2, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
	Comm:Process(env("RESPONSE", sid2, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Ashvane Moo")
	run()
	local reservedInfo = Context:Build("Veyra Moo", 1)
	check("a reserver is told so, by first name too, in the addon's name and colour", #reservedInfo.providers == 1 and reservedInfo.providers[1].title == "Soft Reserve"
		and reservedInfo.providers[1].color == "9B7BFF" and reservedInfo.providers[1].lines[1].text == "Yes (SR, one of 2)")
	local notReserved = Context:Build("Ashvane Moo", 1)
	check("and somebody who did not reserve it is told that too", notReserved.providers[1].lines[1].text == "No (2 reserved it)")
	Sessions:Cancel("done again")
	run()
	Sessions:StartItems({ 210, 200 })
	run()
	local sidAgain = Sessions:GetActiveSid()
	Comm:Process(env("RESPONSE", sidAgain, nil, { item = 1, response = "BIS", gear = { "item:211" }, note = "my first one" }), "WHISPER", "Veyra Moo")
	run()

	-- addons add lines
	check("a provider must have an id, a title and lines", ALC.RegisterContextProvider({ title = "X", lines = function() end }) == false
		and ALC.RegisterContextProvider({ id = "X", lines = function() end }) == false and ALC.RegisterContextProvider({ id = "X", title = "X" }) == false)
	check("a provider registers", ALC.RegisterContextProvider({ id = "SR", title = "Soft Reserve", color = "9B7BFF",
		lines = function(name) if name == "Veyra Moo" then return { { label = "Reserved", text = "Yes", color = "9B7BFF" } } end end }) == true)
	local withProvider = Context:Build("Veyra Moo", 1)
	check("its lines are in the context, for the player it knows", #withProvider.providers == 1 and withProvider.providers[1].title == "Soft Reserve" and withProvider.providers[1].lines[1].text == "Yes")
	check("and not for another player", #Context:Build("Ashvane Moo", 1).providers == 0)
	ALC.RegisterContextProvider({ id = "BAD", title = "Bad", lines = function() error("boom") end })
	check("a provider that fails does not break the context", pcall(function() return Context:Build("Veyra Moo", 1) end) and #Context:Build("Veyra Moo", 1).providers == 1)
	ALC.UnregisterContextProvider("BAD")
	ALC.UnregisterContextProvider("SR")
	check("a provider can be removed", #Context:Build("Veyra Moo", 1).providers == 0)

	-- the loot master answers a council member's question
	local payload = Context:BuildHistory("Veyra Moo")
	check("the answer holds the awards, newest first, and when the night began", payload.name == "Veyra Moo" and payload.total == 4 and #payload.entries == 4
		and payload.entries[1].itemID == 200 and payload.nightStart == now - 3.5 * 3600)
	check("the answer passes the protocol's check", ALC.Protocol.specs.HISTORY.validate(payload, ME) == true)
	for i = 1, 40 do award("Veyra Moo", 200, (20 + i) * DAY) end
	local big = Context:BuildHistory("Veyra Moo")
	check("a long history is cut at what one message holds, with the total told", #big.entries == ALC.Constants.MAX_HISTORY_ENTRIES and big.total == 44
		and ALC.Protocol.specs.HISTORY.validate(big, ME) == true)
	for i = #log, #log - 39, -1 do log[i] = nil end

	-- the protocol
	local spec = ALC.Protocol.specs
	check("a history question is for the loot master from the council", spec.HISTORY_REQUEST.allowed == "council" and spec.HISTORY.allowed == "lm")
	check("a question needs a good name", spec.HISTORY_REQUEST.validate({ name = "Veyra Moo" }) == true and spec.HISTORY_REQUEST.validate({ name = "A|cffff0000" }) == false and spec.HISTORY_REQUEST.validate({}) == false)
	local function badHistory(change)
		local p = Context:BuildHistory("Veyra Moo")
		change(p)
		return spec.HISTORY.validate(p, ME) == false
	end
	check("a bad answer is refused", badHistory(function(p) p.entries[1].itemID = 0 end) and badHistory(function(p) p.entries[1].label = nil end)
		and badHistory(function(p) p.entries[1].color = "red" end) and badHistory(function(p) p.total = -1 end) and badHistory(function(p) p.entries[1].time = "x" end)
		and badHistory(function(p) p.entries[1].zone = string.rep("z", 41) end))
	local tooMany = Context:BuildHistory("Veyra Moo")
	for i = 1, 31 do tooMany.entries[i] = { itemID = 200, label = "BiS", time = now } end
	check("too many entries are refused", spec.HISTORY.validate(tooMany, ME) == false)

	----------------------------------------------------------------------------
	-- The award log: a reminder at a limit, and trimming it
	----------------------------------------------------------------------------
	check("the reminder is at 1000 awards unless chosen otherwise", ALC.Settings:GetLogReminder() == 1000)
	check("only the offered limits are accepted", ALC.Settings:SetLogReminder(750) == false and ALC.Settings:SetLogReminder(500) == true and ALC.Settings:GetLogReminder() == 500)
	local lengths = #log
	check("below the limit nothing is said", ALC.Awards:CheckLogLimit() == false)
	for i = 1, 600 do award("Filler Moo", 200, (60 + i) * 3600) end
	local said = #H.chat
	check("at the limit the loot master is reminded, once", ALC.Awards:CheckLogLimit() == true and #H.chat == said + 1 and H.chat[#H.chat]:find("award log", 1, true) ~= nil and ALC.Awards:CheckLogLimit() == false)
	ALC.Awards:ResetLogReminder()
	ALC.Settings:SetLogReminder(0)
	check("never means never", ALC.Awards:CheckLogLimit() == false)
	ALC.Settings:SetLogReminder(1000)
	local before = #log
	check("a trim keeps the newest and moves the rest to the backup", ALC.Awards:TrimLog(500) == before - 500 and #log == 500 and select(1, ALC.Awards:GetBackupInfo()) == before - 500)
	check("what is left is the newest, in order", log[#log].winner == "Filler Moo" or log[#log].time >= log[1].time)
	check("trimming a short log does nothing, and a bad number is refused", ALC.Awards:TrimLog(500) == 0 and ALC.Awards:TrimLog("x") == 0 and ALC.Awards:TrimLog(-1) == 0)
	check("a trim can be taken back", ALC.Awards:RestoreLog() == before - 500 and #log == before)
	H.slash("log")
	check("/alc log says how many awards there are", H.chat[#H.chat]:find(tostring(before), 1, true) ~= nil)
	H.slash("log trim 100")
	check("/alc log trim keeps the number asked for", #log == 100)
	ALC.Awards:RestoreLog()
	local rows = {}
	for _, section in ipairs(ALC.GetSettingsSections()) do if section.id == "ALC-award-log" then rows = section.rows end end
	check("the Settings window offers the limit and a trim", #rows == 2 and rows[1].get() == 1000 and rows[2].confirm ~= nil)
	rows[1].set(2000)
	check("the choice is saved", ALC.Settings:GetLogReminder() == 2000)
	ALC.Settings:SetLogReminder(1000)
	-- clean up the filler so the council member part starts from the same log
	for i = #log, 1, -1 do if log[i].winner == "Filler Moo" then table.remove(log, i) end end

	----------------------------------------------------------------------------
	-- A council member
	----------------------------------------------------------------------------
	Sessions:Cancel("done")
	run()
	H.reload("fresh")
	leader = "Ashvane Moo"
	world()
	H.setupFrames()
	H.deferTimers = true
	H.timers = {}
	Context, Sessions, Comm = ALC.Context, ALC.Sessions, ALC.Comm
	Comm:Process(env("SESSION_START", "sidC", 1, {
		items = { { itemID = 210, itemString = "item:210:0" }, { itemID = 200, itemString = "item:200:0" } },
		council = { "Ashvane Moo", ME }, lm = "Ashvane Moo",
	}), "RAID", "Ashvane Moo")
	run()
	check("a council member is in the session", Sessions:GetActiveSid() == "sidC" and Sessions:GetSession().isLM == false and Sessions:GetSession().isCouncil == true)
	Comm:Process(env("CANDIDATE_UPDATE", "sidC", 2, { item = 1, name = "Veyra Moo", class = "WARRIOR", response = "BIS", gear = { "item:211" } }), "WHISPER", "Ashvane Moo")
	run()
	local noHistory = Context:Build("Veyra Moo", 1)
	check("before the history arrives the context says it is not complete, and shows the row's own facts", noHistory.complete == false and #noHistory.history == 0 and noHistory.label == "BiS" and noHistory.ilvlDelta == 13)
	H.sent = {}
	check("a council member asks the loot master", Context:Request("Veyra Moo") == true and #H.sent >= 1)
	check("and waits", Context:IsWaiting("Veyra Moo") == true)
	check("the same question is not asked again at once", Context:Request("Veyra Moo") == false)
	local asked = false
	for _, sent in ipairs(H.sent) do if sent.text and sent.text:find("HISTORY_REQUEST", 1, true) then asked = true end end
	check("it is a HISTORY_REQUEST to the loot master", asked)

	local changes = 0
	local listener = {}
	ALC.Events.Register(listener, "ALC_CONTEXT_CHANGED", function() changes = changes + 1 end)
	local answer = {
		name = "Veyra Moo", total = 5, nightStart = now - 2 * 3600,
		entries = {
			{ itemID = 200, label = "BiS", color = "4dcc4d", time = now - 3600, zone = "Karazhan" },
			{ itemID = 211, label = "Upgrade", color = "3fa0ff", time = now - 3 * DAY, zone = "Karazhan" },
		},
	}
	check("the loot master's answer is accepted from the loot master", Comm:Process(env("HISTORY", "sidC", 3, answer), "WHISPER", "Ashvane Moo") == true)
	check("and not from somebody else", Comm:Process(env("HISTORY", "sidC", 4, answer), "WHISPER", "Veyra Moo") == false)
	run()
	local full = Context:Build("Veyra Moo", 1)
	check("the history is there and complete, with the total", full.complete == true and #full.history == 2 and full.total == 5 and changes >= 1)
	check("tonight and the same slot work for a council member too", full.history[1].tag == "tonight" and full.history[2].tag == "week" and #full.sameSlot == 1 and full.sameSlot[1].itemID == 211)
	check("and the answers keep their colour", full.history[1].color == "4dcc4d" and full.history[2].label == "Upgrade")
	check("it is no longer waited for", Context:IsWaiting("Veyra Moo") == false)
	-- a new award makes it stale
	Comm:Process(env("AWARD", "sidC", 5, { item = 2, winner = "Veyra Moo", itemID = 200, response = "BIS" }), "RAID", "Ashvane Moo")
	run()
	check("a new award in the session makes the copies stale", Context:Build("Veyra Moo", 1).complete == false)
	check("a council member can ask again after that", (function() H.clock = (H.clock or 0) + 60 return true end)())
end

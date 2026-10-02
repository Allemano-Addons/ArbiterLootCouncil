-- Awards:AwardMany and the "Award all" question: a list of winners handed out in one go.

return function(check, H)
	local ME = "Tester Moo"
	local env = H.env
	local AceSerializer = LibStub("AceSerializer-3.0")

	local db = {
		[200] = { "Crown of Destruction", 4, "INVTYPE_HEAD" },
		[201] = { "Belt of Might", 4, "INVTYPE_WAIST" },
		[202] = { "Ring of Focus", 4, "INVTYPE_FINGER" },
	}
	local function idOf(item) return tonumber(item) or tonumber(tostring(item):match("item:(%d+)")) end
	local function items()
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

	H.reload("fresh")
	items()
	local units = {
		player = { "Tester", "Moo", "ROGUE" },
		party1 = { "Veyra", "Moo", "WARRIOR" },
		party2 = { "Jonatan", "Moo", "PRIEST" },
		party3 = { "Kaelis", "Moo", "HUNTER" },
	}
	UnitName = function(unit) local u = units[unit]; if u then return u[1], u[2] end end
	UnitClass = function(unit) local u = units[unit]; if u then return u[3], u[3] end end
	UnitIsConnected = function() return true end
	H.inGroup = true
	local Awards, Sessions, Council, Comm, Candidates = ALC.Awards, ALC.Sessions, ALC.Council, ALC.Comm, ALC.Candidates
	local Dialog = ALC.AwardDialog
	Council.GetLootMethodInfo = function() return 3 end
	Council.GetLeaderName = function() return ME end
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
	H.setupFrames()
	H.deferTimers = true
	H.timers = {}
	local function run() H.runTimers() end

	local batchDone = {}
	local listener = {}
	ALC.Events.Register(listener, "ALC_AWARDS_BATCH_DONE", function(_, awarded, failed) batchDone[#batchDone + 1] = { awarded = awarded, failed = failed } end)

	local function awardsSent()
		local list = {}
		for _, sent in ipairs(H.sent) do
			local _, e = AceSerializer:Deserialize(sent.text)
			if e and e.t == "AWARD" then list[#list + 1] = e.p end
		end
		return list
	end
	local function newSession()
		if Sessions:IsActive() then Sessions:Cancel("test reset") end
		run()
		Sessions:StartItems({ 200, 201, 202 })
		run()
		local sid = Sessions:GetActiveSid()
		Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
		Comm:Process(env("RESPONSE", sid, nil, { item = 2, response = "BIS", gear = {} }), "WHISPER", "Kaelis Moo")
		Comm:Process(env("RESPONSE", sid, nil, { item = 3, response = "UPGRADE", gear = {} }), "WHISPER", "Jonatan Moo")
		Comm:Process(env("RESPONSE", sid, nil, { item = 3, response = "PASS", gear = {} }), "WHISPER", "Veyra Moo")
		run()
		H.sent = {}
		return sid
	end

	----------------------------------------------------------------------------
	-- What is refused (and nothing happens)
	----------------------------------------------------------------------------
	check("no session, no batch", (Awards:AwardMany({ { item = 1, name = "Veyra Moo" } })) == false)
	local sid = newSession()
	local function refused(list) local ok, why = Awards:CheckMany(list) return ok == false and why ~= nil end
	check("an empty list is refused", refused({}) and refused(nil))
	check("an item that is not in the session is refused", refused({ { item = 9, name = "Veyra Moo" } }))
	check("a player who has not answered is refused", refused({ { item = 1, name = "Nobody Moo" } }))
	check("a player who passed is refused", refused({ { item = 3, name = "Veyra Moo" } }))
	check("the same item twice is refused", refused({ { item = 1, name = "Veyra Moo" }, { item = 1, name = "Veyra Moo" } }))
	check("the disenchanter must be set", refused({ { item = 1, disenchant = true } }))
	check("one bad entry stops the whole list", Awards:AwardMany({ { item = 1, name = "Veyra Moo" }, { item = 2, name = "Nobody Moo" } }) == false
		and Sessions:IsItemOpen(1) and Sessions:IsItemOpen(2) and #awardsSent() == 0 and not Awards:IsBatchRunning())

	-- not the loot master
	local realAm = Council.AmLootMaster
	Council.AmLootMaster = function() return false end
	check("only the loot master can award many", refused({ { item = 1, name = "Veyra Moo" } }))
	Council.AmLootMaster = realAm

	-- paused
	Sessions:SetPaused(true)
	run()
	check("a paused session cannot award", refused({ { item = 1, name = "Veyra Moo" } }))
	Sessions:SetPaused(false)
	run()

	----------------------------------------------------------------------------
	-- Awarding the list
	----------------------------------------------------------------------------
	local list = { { item = 1, name = "Veyra Moo" }, { item = 2, name = "Kaelis Moo" }, { item = 3, name = "Jonatan Moo" } }
	check("a good list passes the check", Awards:CheckMany(list) == true)
	local ok, count = Awards:AwardMany(list)
	run() run() run() run()
	check("the batch is accepted", ok == true and count == 3)
	local sent = awardsSent()
	check("an AWARD goes out for each item, in order", #sent == 3 and sent[1].item == 1 and sent[1].winner == "Veyra Moo" and sent[2].item == 2 and sent[3].winner == "Jonatan Moo")
	check("every item has its winner", not Sessions:IsItemOpen(1) and not Sessions:IsItemOpen(2) and not Sessions:IsItemOpen(3))
	check("the batch says it is done", #batchDone == 1 and batchDone[1].awarded == 3 and #batchDone[1].failed == 0 and not Awards:IsBatchRunning())
	local log = Awards:GetLog()
	check("each award is in the log", log[#log].winner == "Jonatan Moo" and log[#log - 1].winner == "Kaelis Moo" and log[#log - 2].winner == "Veyra Moo")

	-- a second batch cannot start while one runs
	sid = newSession()
	batchDone = {}
	check("a batch runs one award at a time", Awards:AwardMany({ { item = 1, name = "Veyra Moo" }, { item = 2, name = "Kaelis Moo" } }) == true)
	check("the first is awarded at once", #awardsSent() == 1 and Awards:IsBatchRunning())
	check("another batch is refused meanwhile", select(1, Awards:AwardMany({ { item = 3, name = "Jonatan Moo" } })) == false)
	run() run() run()
	check("and the rest follows", #awardsSent() == 2 and #batchDone == 1 and batchDone[1].awarded == 2)

	-- the session ends in the middle
	sid = newSession()
	batchDone = {}
	Awards:AwardMany({ { item = 1, name = "Veyra Moo" }, { item = 2, name = "Kaelis Moo" } })
	Sessions:Cancel("stop")
	run() run() run()
	check("a session that ends stops the batch", #batchDone == 1 and batchDone[1].awarded == 1 and #batchDone[1].failed == 1 and not Awards:IsBatchRunning())

	----------------------------------------------------------------------------
	-- Master loot: the next item waits until the last one has been handed over
	----------------------------------------------------------------------------
	local lootSlots, candidatesBySlot, given = {}, {}, {}
	GetNumLootItems = function() return #lootSlots end
	GetLootSlotLink = function(slot) return lootSlots[slot] end
	GetMasterLootCandidate = function(_, index) return candidatesBySlot[index] end
	GiveMasterLoot = function(slot, index) given[#given + 1] = { slot = slot, index = index } end
	lootSlots = { "|Hitem:200|h[Crown]|h", "|Hitem:201|h[Belt]|h" }
	candidatesBySlot = { "Veyra Moo", "Kaelis Moo", "Jonatan Moo" }
	Awards:SetLootOpen(true)
	Council.IsPlayerMasterLooter = function() return true end

	sid = newSession()
	batchDone = {}
	Awards:AwardMany({ { item = 1, name = "Veyra Moo" }, { item = 2, name = "Kaelis Moo" } })
	check("the first item is handed out", #given == 1 and given[1].slot == 1 and given[1].index == 1)
	local realTimeout = Awards.OnGiveTimeout
	Awards.OnGiveTimeout = function() end -- the give timeout must not fire in this part
	run()
	Awards.OnGiveTimeout = realTimeout
	check("the second waits for the first slot to empty", #given == 1 and Awards:IsBatchRunning())
	Awards:OnLootSlotCleared(1)
	run()
	check("then it follows", #given == 2 and given[2].slot == 2 and given[2].index == 2)
	Awards:OnLootSlotCleared(2)
	run() run()
	check("and the batch finishes", #batchDone == 1 and batchDone[1].awarded == 2)
	Council.IsPlayerMasterLooter = function() return false end
	Awards:SetLootOpen(false)

	----------------------------------------------------------------------------
	-- The question
	----------------------------------------------------------------------------
	sid = newSession()
	batchDone = {}
	local asked = { { item = 1, name = "Veyra Moo", note = "SR, roll 87" }, { item = 2, name = "Kaelis Moo" }, { item = 3, name = "Jonatan Moo" } }
	check("nothing is asked for a bad list", Dialog:AskMany({ { item = 1, name = "Nobody Moo" } }) == false and not Dialog:IsManyShown())
	check("a good list opens the question", Dialog:AskMany(asked) == true and Dialog:IsManyShown())
	local frame = Dialog.manyFrame
	check("it names the number of items", frame.title:GetText():find("3", 1, true) ~= nil)
	check("one row per item with the winner", frame.rows[1]:IsShown() and frame.rows[3]:IsShown() and not frame.rows[4]:IsShown()
		and frame.rows[1].winner:GetText() == "Veyra Moo" and frame.rows[1].item:GetText() == "Crown of Destruction")
	check("and the note", frame.rows[1].note:GetText() == "SR, roll 87")
	check("nothing is awarded before the confirmation", Sessions:IsItemOpen(1) and #awardsSent() == 0)
	Dialog:HideMany()
	check("Cancel awards nothing", not Dialog:IsManyShown() and Sessions:IsItemOpen(1))
	Dialog:AskMany(asked)
	frame.confirm.scripts.OnClick(frame.confirm)
	run() run() run() run()
	check("Award all hands everything out", not Dialog:IsManyShown() and #awardsSent() == 3 and #batchDone == 1 and batchDone[1].awarded == 3)

	-- the question goes away with the session
	sid = newSession()
	Dialog:AskMany({ { item = 1, name = "Veyra Moo" } })
	Sessions:Cancel("x")
	run() run()
	check("it closes when the session ends", not Dialog:IsManyShown())

	ALC.Events.UnregisterAll(listener)
end

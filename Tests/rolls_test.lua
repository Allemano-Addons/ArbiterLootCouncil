-- Random rolls: made by the loot master when a player answers, shown in the Roll column.


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
	local Sessions, Comm, Settings, Candidates, Win = ALC.Sessions, ALC.Comm, ALC.Settings, ALC.Candidates, ALC.CouncilWindow
	Settings:AddCouncilMember("Veyra Moo")
	H.setupFrames()
	H.deferTimers = true
	H.timers = {}
	local function run() H.runTimers() end

	local updates = {}
	local listener = {}
	ALC.Events.Register(listener, "ALC_COMM_CANDIDATE_UPDATE", function(_, _, _, p) updates[#updates + 1] = p end)

	check("rolls are off by default", Settings:GetRollsEnabled() == false)
	Sessions:StartItems({ 200 })
	run()
	local sid0 = Sessions:GetActiveSid()
	Comm:Process(env("RESPONSE", sid0, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
	run()
	check("with the setting off a session has no rolls and nobody gets one", Sessions:HasRolls() == false and Candidates:Get("Veyra Moo", 1).roll == nil)
	Win:Show()
	Win:Refresh()
	check("so the window has no Roll column", not Win.rows[1].parent.rollHeading:IsShown() and Win.rows[1].noteButton.w == 116)
	Sessions:Cancel("done")
	run()
	Settings:SetRollsEnabled(true)
	updates = {}
	Sessions:StartItems({ 200, 201 })
	run()
	local sid = Sessions:GetActiveSid()
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "UPGRADE", gear = {} }), "WHISPER", "Kaelis Moo")
	run()
	check("the session says it has rolls", Sessions:HasRolls() == true)
	local a, b = Candidates:Get("Veyra Moo", 1), Candidates:Get("Kaelis Moo", 1)
	check("every candidate gets a roll from 1 to 100", a.roll and b.roll and a.roll >= 1 and a.roll <= 100 and b.roll >= 1 and b.roll <= 100)
	check("and they differ", a.roll ~= b.roll)
	check("the council is sent the roll", #updates >= 2 and updates[1].roll == a.roll)

	-- A new answer keeps the roll
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "MINOR", gear = {} }), "WHISPER", "Veyra Moo")
	run()
	check("a changed answer keeps the roll", Candidates:Get("Veyra Moo", 1).response == "MINOR" and Candidates:Get("Veyra Moo", 1).roll == a.roll)
	Candidates:SetResponse("Kaelis Moo", "OFFSPEC", 1)
	run()
	check("so does a change by the loot master", Candidates:Get("Kaelis Moo", 1).roll == b.roll)

	-- Each item has its own
	Comm:Process(env("RESPONSE", sid, nil, { item = 2, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
	run()
	check("item 2 has a roll of its own", Candidates:Get("Veyra Moo", 2).roll ~= nil)

	-- No two the same
	local realRandom = math.random
	local values = { 5, 5, 5, 9 }
	math.random = function() return table.remove(values, 1) or 50 end
	Comm:Process(env("RESPONSE", sid, nil, { item = 2, response = "UPGRADE", gear = {} }), "WHISPER", "Kaelis Moo")
	run()
	math.random = realRandom
	local other = Candidates:Get("Veyra Moo", 2).roll
	check("a number already taken is not given again", Candidates:Get("Kaelis Moo", 2).roll ~= other)

	-- Recovery
	local built
	ALC.Events.Register(listener, "ALC_SESSION_SNAPSHOT_BUILD", function(_, payload) built = payload end)
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Veyra Moo")
	local withRoll = false
	for _, entry in ipairs(built and built.candidates or {}) do
		if entry.name == "Veyra Moo" and entry.item == 1 and entry.roll == a.roll then withRoll = true end
	end
	check("a snapshot carries the rolls", withRoll)
	local saved = H.snapshotDB()
	H.reload(saved)
	leader = ME
	world(true)
	H.setupFrames()
	ALC.Sessions:OnEnteringWorld(false, true)
	H.runTimers()
	check("the session still has rolls after a reload", ALC.Sessions:HasRolls() == true)
	check("the loot master's rolls survive a reload", ALC.Candidates:Get("Veyra Moo", 1) and ALC.Candidates:Get("Veyra Moo", 1).roll == a.roll)
	Sessions, Comm, Settings, Candidates, Win = ALC.Sessions, ALC.Comm, ALC.Settings, ALC.Candidates, ALC.CouncilWindow

	-- The window
	Win:Show()
	Win:Refresh()
	local frame = Win.rows[1].parent
	check("the heading is there and the note is narrower", frame.rollHeading:IsShown() and Win.rows[1].noteButton.w == 66)
	local byName = {}
	for _, row in ipairs(Win.rows) do if row:IsShown() and row.candidate then byName[row.candidate] = row end end
	check("the rows show the rolls", byName["Veyra Moo"].roll:GetText() == tostring(a.roll) and byName["Kaelis Moo"].roll:GetText() == tostring(b.roll))
	Win:SetSortMode("roll")
	local order = {}
	for _, entry in ipairs(Win:GetVisible()) do order[#order + 1] = entry.roll end
	check("by roll: highest first", #order == 2 and order[1] > order[2])
	Win:SetSortMode("rank")
	Win:CycleSortMode()
	check("the sort button can reach it", Win:GetSortMode() == "roll")
	local tip = {}
	GameTooltip.SetText = function(_, text) tip[1] = text end
	local rb = byName["Veyra Moo"].rollButton
	rb.scripts.OnEnter(rb)
	check("hover explains the roll", tip[1] == "Random roll")
	-- The next session without rolls: the column and the roll order are gone.
	ALC.Sessions:Cancel("done")
	H.runTimers()
	ALC.Settings:SetRollsEnabled(false)
	ALC.Sessions:StartItems({ 200 })
	H.runTimers()
	Win:Show()
	Win:Refresh()
	check("a session without rolls: no column, the wide note", not frame.rollHeading:IsShown() and Win.rows[1].noteButton.w == 116)
	Win:SetSortMode("roll")
	check("and no roll order", Win:GetSortMode() == "response")
	Win:SetSortMode("rank")
	Win:CycleSortMode()
	check("the sort button skips it", Win:GetSortMode() == "name")

	-- Protocol
	local spec = ALC.Protocol.specs.CANDIDATE_UPDATE
	local start = ALC.Protocol.specs.SESSION_START
	local base = { items = { { itemID = 200, itemString = "item:200" } }, council = { ME }, lm = ME }
	check("protocol: SESSION_START accepts a rolls flag", start.validate({ items = base.items, council = base.council, lm = ME, rolls = true }, ME) == true)
	check("protocol: and refuses a bad one", start.validate({ items = base.items, council = base.council, lm = ME, rolls = "yes" }, ME) == false)
	local function candidate(extra)
		local c = { item = 1, name = "Veyra Moo", class = "WARRIOR", response = "BIS", gear = {} }
		for k, v in pairs(extra) do c[k] = v end
		return c
	end
	check("protocol: a candidate without a roll is fine", spec.validate(candidate({})) == true)
	check("protocol: 1 and 100 are fine", spec.validate(candidate({ roll = 1 })) == true and spec.validate(candidate({ roll = 100 })) == true)
	check("protocol: 0, 101 and text are refused", spec.validate(candidate({ roll = 0 })) == false and spec.validate(candidate({ roll = 101 })) == false and spec.validate(candidate({ roll = "x" })) == false)
end

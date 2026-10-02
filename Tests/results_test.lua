-- Results: the outcome of items decided by rolls, sent to the group by the loot master (RESULT) and shown in the
-- Result window.

return function(check, H)
	local ME = "Tester Moo"
	local env = H.env

	local db = {
		[200] = { "Crown of Destruction", 4, "INVTYPE_HEAD" },
		[201] = { "Belt of Might", 4, "INVTYPE_WAIST" },
	}
	local leader = ME
	local units
	local function world()
		units = {
			player = { "Tester", "Moo", "ROGUE" },
			party1 = { "Veyra", "Moo", "WARRIOR" },
			party2 = { "Ashvane", "Moo", "PRIEST" },
		}
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

	local row = function(name, answer, roll, outcome, extra)
		local r = { name = name, answer = answer, roll = roll, outcome = outcome }
		for k, v in pairs(extra or {}) do r[k] = v end
		return r
	end

	----------------------------------------------------------------------------
	-- The message
	----------------------------------------------------------------------------
	H.reload("fresh")
	leader = ME
	world()
	local Sessions, Comm, Results, Win = ALC.Sessions, ALC.Comm, ALC.Results, ALC.ResultWindow
	H.setupFrames()
	H.deferTimers = true
	H.timers = {}
	local function run() H.runTimers() end

	----------------------------------------------------------------------------
	-- Publishing as the loot master
	----------------------------------------------------------------------------
	local good = { item = 1, state = "resolved", rows = { row("Veyra Moo", "PASS", nil, "passed"), row("Kaelis Moo", "BIS", 40, "won", { via = "SR", reserved = true, rerolls = { 12, 80 } }) } }
	check("nothing can be published without a session", (Results:Publish(1, "resolved", good.rows)) == false)
	check("and there is no result", Results:HasAny() == false and Results:Get(1) == nil and #Results:GetItems() == 0)

	local changes = {}
	local listener = {}
	ALC.Events.Register(listener, "ALC_RESULTS_CHANGED", function(_, item) changes[#changes + 1] = item or "cleared" end)

	Sessions:StartItems({ 200, 201 })
	run()
	local sid = Sessions:GetActiveSid()

	local spec = ALC.Protocol.specs.RESULT
	check("RESULT is a loot master message to the group", spec ~= nil and spec.allowed == "lm" and spec.channel == "GROUP" and spec.sid == "active" and spec.seq == true)
	check("a good result passes", spec.validate(good, ME) == true)
	local function bad(change) local p = { item = 1, state = "resolved", rows = { row("Veyra Moo", "BIS", 40, "won") } } change(p) return spec.validate(p, ME) == false end
	check("a bad item is refused", bad(function(p) p.item = 0 end) and bad(function(p) p.item = 99 end))
	check("a bad state is refused", bad(function(p) p.state = "done" end) and bad(function(p) p.state = nil end))
	check("rows must be a list", bad(function(p) p.rows = "x" end) and bad(function(p) p.rows = { a = 1 } end))
	check("too many rows are refused", bad(function(p) p.rows = {} for i = 1, 61 do p.rows[i] = row("Player" .. i, "BIS", 5, "lost") end end))
	check("a row needs a name", bad(function(p) p.rows[1].name = nil end) and bad(function(p) p.rows[1].name = "A|cffff0000" end))
	check("an answer that is not one of the buttons is refused", bad(function(p) p.rows[1].answer = "NOPE" end))
	check("a roll is 1 to 100", bad(function(p) p.rows[1].roll = 0 end) and bad(function(p) p.rows[1].roll = 101 end) and bad(function(p) p.rows[1].roll = 5.5 end))
	check("rerolls are a short list of rolls", bad(function(p) p.rows[1].rerolls = { 0 } end) and bad(function(p) p.rows[1].rerolls = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 } end) and bad(function(p) p.rows[1].rerolls = "x" end))
	check("the outcome is one of four", bad(function(p) p.rows[1].outcome = "champion" end) and bad(function(p) p.rows[1].outcome = nil end))
	check("via is SR, MS or OS", bad(function(p) p.rows[1].via = "XX" end))
	check("reserved is yes or no", bad(function(p) p.rows[1].reserved = "yes" end))
	check("a row that is not a table is refused", bad(function(p) p.rows[1] = "x" end))

	check("the loot master publishes a result", Results:Publish(1, "resolved", good.rows) == true)
	run()
	check("it arrives (we get our own message too)", Results:HasAny() and #changes == 1 and changes[1] == 1)
	local rows, state = Results:Get(1)
	check("the rows and the state are there", state == "resolved" and #rows == 2 and rows[2].name == "Kaelis Moo" and rows[2].roll == 40 and rows[2].via == "SR" and rows[2].reserved == true)
	check("with the rerolls", rows[2].rerolls[1] == 12 and rows[2].rerolls[2] == 80)
	rows[1].name = "Mutated"
	check("Get hands out a copy", Results:Get(1)[1].name == "Veyra Moo")
	check("an item without a result has none", Results:Get(2) == nil)

	Results:Publish(1, "accepted", good.rows)
	run()
	check("a new result replaces the old", select(2, Results:Get(1)) == "accepted" and #Results:GetItems() == 1)
	Results:Publish(2, "resolved", { row("Veyra Moo", "BIS", 7, "won", { via = "MS" }) })
	run()
	check("another item is kept next to it", #Results:GetItems() == 2 and Results:GetItems()[1] == 1 and Results:GetItems()[2] == 2)

	check("a bad result is not sent", (Results:Publish(1, "bogus", good.rows)) == false and (Results:Publish(1, "resolved", "x")) == false)
	check("rows from an item that is not in the session are refused", (Results:Publish(9, "resolved", good.rows)) == false)

	-- Other senders
	check("a result from someone else is refused", Comm:Process(env("RESULT", sid, 99, good), "RAID", "Veyra Moo") == false)
	check("and one for another session", Comm:Process(env("RESULT", "other-sid", 99, good), "RAID", ME) == false)

	----------------------------------------------------------------------------
	-- The window
	----------------------------------------------------------------------------
	H.slash("results")
	check("/alc results opens the window", Win:IsShown())
	check("it lists the items that have a result", Win.itemRows[1]:IsShown() and Win.itemRows[2]:IsShown() and not Win.itemRows[3]:IsShown())
	check("with the winner", Win.itemRows[2].status:GetText():find("Veyra Moo", 1, true) ~= nil)
	check("the rows of the first item", Win.rows[1]:IsShown() and Win.rows[2]:IsShown() and not Win.rows[3]:IsShown())
	check("a row shows name, answer and roll", Win.rows[2].name:GetText() == "Kaelis Moo" and Win.rows[2].roll:GetText() == "40 > 12, 80")
	check("the winner's outcome says how", Win.rows[2].result:GetText():find("Won", 1, true) and Win.rows[2].result:GetText():find("Soft reserve", 1, true))
	check("a reserver is tagged", Win.rows[2].tag:GetText() == "SR" and Win.rows[1].tag:GetText() == "")
	check("a pass has no roll", Win.rows[1].roll:GetText() == "\226\128\148" and Win.rows[1].result:GetText() == "Passed")
	Win.itemRows[2].scripts.OnClick(Win.itemRows[2])
	check("clicking another item shows its rows", Win.rows[1].name:GetText() == "Veyra Moo" and Win.rows[1].roll:GetText() == "7" and not Win.rows[2]:IsShown())
	Win:Hide()
	check("the window can be closed", not Win:IsShown())

	-- A new session clears the results
	Sessions:Cancel("done")
	run()
	check("the results go when the session ends", Results:HasAny() == false and changes[#changes] == "cleared")
	H.chat = H.chat or {}
	local before = #H.chat
	H.slash("results")
	check("and /alc results says there is none", #H.chat == before + 1 and not Win:IsShown())

	----------------------------------------------------------------------------
	-- As a player: the window opens by itself, once
	----------------------------------------------------------------------------
	H.reload("fresh")
	leader = "Ashvane Moo"
	world()
	H.setupFrames()
	H.deferTimers = true
	H.timers = {}
	Sessions, Comm, Results, Win = ALC.Sessions, ALC.Comm, ALC.Results, ALC.ResultWindow
	Comm:Process(env("SESSION_START", "sidP", 1, {
		items = { { itemID = 200, itemString = "item:200:0" }, { itemID = 201, itemString = "item:201:0" } },
		council = { "Ashvane Moo" }, lm = "Ashvane Moo",
	}), "RAID", "Ashvane Moo")
	run()
	check("a player is in the session", Sessions:GetActiveSid() == "sidP" and Sessions:GetSession().isLM == false)
	check("the window is closed", not Win:IsShown())
	local ok = Comm:Process(env("RESULT", "sidP", 2, good), "RAID", "Ashvane Moo")
	run()
	check("the loot master's result is accepted", ok == true and Results:HasAny())
	check("the window opens by itself", Win:IsShown())
	Win:Hide()
	Comm:Process(env("RESULT", "sidP", 3, { item = 1, state = "accepted", rows = good.rows }), "RAID", "Ashvane Moo")
	run()
	check("and does not open again for the same session", not Win:IsShown())
	check("the new rows are there when it is opened", select(2, Results:Get(1)) == "accepted")
	check("an older message is ignored", Comm:Process(env("RESULT", "sidP", 1, good), "RAID", "Ashvane Moo") == false)
	Win:Show()
	check("a player sees the rows", Win.rows[2]:IsShown() and Win.rows[2].name:GetText() == "Kaelis Moo")
	Win:Hide()

	----------------------------------------------------------------------------
	-- The tag in the response window: "SR" for the players an addon marks
	----------------------------------------------------------------------------
	Sessions:Cancel("x")
	Comm:Process(env("SESSION_CANCEL", "sidP", 4, { reason = "done" }), "RAID", "Ashvane Moo")
	run()
	local Resp = ALC.ResponseWindow
	Comm:Process(env("SESSION_START", "sidM", 5, {
		items = {
			{ itemID = 200, itemString = "item:200:0", extra = { mark = "SR", markFor = { "Tester" } } },
			{ itemID = 201, itemString = "item:201:0", extra = { mark = "SR", markFor = { "Veyra", "Tester Mu" } } },
			{ itemID = 200, itemString = "item:200:0", extra = { mark = "SR", markFor = { "Tester Moo" } } },
			{ itemID = 201, itemString = "item:201:0" },
		},
		council = { "Ashvane Moo" }, lm = "Ashvane Moo", mode = "SR",
	}), "RAID", "Ashvane Moo")
	run()
	Resp:Show()
	Resp:Refresh()
	local function text(i) return Resp.rows[i].name:GetText() end
	check("a first name in the list marks every character with it", text(1):find("SR", 1, true) ~= nil and text(1):find("Crown", 1, true) ~= nil)
	check("other people's names do not mark you, nor another surname", text(2):find("SR", 1, true) == nil)
	check("a full name marks you", text(3):find("SR", 1, true) ~= nil)
	check("an item with no data has no tag", text(4):find("SR", 1, true) == nil)
	Resp:Hide()
	Sessions:Cancel("x")
	ALC.Events.UnregisterAll(listener)
end

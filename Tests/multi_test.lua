-- Sessions with several items: protocol, answers, votes and awards per item, the item
-- strip, and recovery. Every "reload" here loads the whole addon again from the saved
-- variables only. Runs after the recovery tests.

return function(check, H)
	local AceSerializer = LibStub("AceSerializer-3.0")
	local ME = "Tester Moo"
	local env = H.env

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
		UnitIsConnected = function() return true end
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

	H.reload("fresh")
	leader = ME
	world()
	local Sessions, Candidates, Voting, Responses, Awards, Comm = ALC.Sessions, ALC.Candidates, ALC.Voting, ALC.Responses, ALC.Awards, ALC.Comm
	local Win, Resp, LD = ALC.CouncilWindow, ALC.ResponseWindow, ALC.LootDetection
	ALC.Settings:AddCouncilMember("Veyra Moo")
	ALC.Settings:AddCouncilMember("Kaelis Moo")

	local function raw(t, sid, seq, p) return { v = 2, t = t, sid = sid, seq = seq, p = p } end
	local function sent(t)
		local found = {}
		for _, s in ipairs(H.sent) do
			local _, e = AceSerializer:Deserialize(s.text)
			if e and e.t == t then found[#found + 1] = { target = s.target, p = e.p, sid = e.sid, seq = e.seq } end
		end
		return found
	end

	----------------------------------------------------------------------------
	-- The protocol
	----------------------------------------------------------------------------
	local startBase = function(items) return { items = items, council = { ME, "Veyra Moo" }, lm = ME } end
	local one = { itemID = 200, itemString = "item:200" }
	local spec = ALC.Protocol.specs.SESSION_START
	check("one item is a valid session", spec.validate(startBase({ one }), ME) == true)
	check("so are three", spec.validate(startBase({ one, { itemID = 201, itemString = "item:201" }, { itemID = 202, itemString = "item:202" } }), ME) == true)
	check("a session needs an item", spec.validate(startBase({}), ME) == false)
	check("no items list is refused", spec.validate({ council = { ME }, lm = ME }, ME) == false)
	local many = {}
	for i = 1, 31 do many[i] = one end
	check("31 items are too many", spec.validate(startBase(many), ME) == false)
	check("30 are the most", (function() many[31] = nil return spec.validate(startBase(many), ME) end)() == true)
	check("an item must match its itemString", spec.validate(startBase({ { itemID = 201, itemString = "item:200" } }), ME) == false)
	check("an item cannot be a number", spec.validate(startBase({ 200 }), ME) == false)
	check("the old single-item form is refused", spec.validate({ itemID = 200, itemString = "item:200", council = { ME }, lm = ME }, ME) == false)
	check("a winner must be a name", spec.validate(startBase({ { itemID = 200, itemString = "item:200", winner = 5 } }), ME) == false)

	-- (There is no session here, so the default five stand in for its answers.)
	local realKnown = ALC.Protocol.knownResponse
	ALC.Protocol.knownResponse = function(id) return id == "BIS" or id == "UPGRADE" or id == "MINOR" or id == "OFFSPEC" or id == "PASS" end
	local resp = ALC.Protocol.specs.RESPONSE
	check("an answer names its item", resp.validate({ item = 2, response = "BIS", gear = {} }) == true)
	check("an answer without an item is refused", resp.validate({ response = "BIS", gear = {} }) == false)
	check("item 0 is refused", resp.validate({ item = 0, response = "BIS", gear = {} }) == false)
	check("item 31 is refused", resp.validate({ item = 31, response = "BIS", gear = {} }) == false)
	check("item 1.5 is refused", resp.validate({ item = 1.5, response = "BIS", gear = {} }) == false)
	check("votes name their item", ALC.Protocol.specs.VOTE.validate({ item = 1, candidate = "Veyra Moo" }) == true
		and ALC.Protocol.specs.VOTE.validate({ candidate = "Veyra Moo" }) == false)
	check("awards name their item", ALC.Protocol.specs.AWARD.validate({ item = 1, winner = "Veyra Moo", itemID = 200, response = "BIS" }) == true
		and ALC.Protocol.specs.AWARD.validate({ winner = "Veyra Moo", itemID = 200, response = "BIS" }) == false)
	ALC.Protocol.knownResponse = realKnown

	----------------------------------------------------------------------------
	-- Starting a session with three items
	----------------------------------------------------------------------------
	local okNone, msgNone = Sessions:StartItems({})
	check("no items, no session", okNone == false and msgNone ~= nil and not Sessions:IsActive())
	local tooMany = {}
	for i = 1, 31 do tooMany[i] = 200 end
	local okMany, msgMany = Sessions:StartItems(tooMany)
	check("more than 30 items is refused with the limit named", okMany == false and msgMany:find("30", 1, true) ~= nil)
	local okBad, msgBad = Sessions:StartItems({ 200, "junk" })
	check("one bad item refuses the whole start", okBad == false and msgBad ~= nil and not Sessions:IsActive())

	H.sent = {}
	check("start a session with three items", Sessions:StartItems({ 200, 201, 202 }) == true and Sessions:IsActive())
	local sid = Sessions:GetActiveSid()
	local session = Sessions:GetSession()
	check("the session holds them in order", #session.items == 3 and session.items[1].itemID == 200 and session.items[2].itemID == 201 and session.items[3].itemID == 202)
	check("counted and read one by one", Sessions:GetItemCount() == 3 and Sessions:GetItem(2).itemID == 201 and Sessions:GetItem(4) == nil)
	check("all are open", Sessions:IsItemOpen(1) and Sessions:IsItemOpen(2) and Sessions:IsItemOpen(3) and not Sessions:IsItemOpen(4))
	local startMsg = sent("SESSION_START")[1]
	check("one SESSION_START carries all three", startMsg ~= nil and #startMsg.p.items == 3)
	local copy = Sessions:GetSession()
	copy.items[1].winner = "Hacker"
	check("the session cannot be changed through a copy", Sessions:GetItem(1).winner == nil)

	check("the loot list has three entries, all in the session", #LD:GetItems() == 3 and LD:GetItems()[1].status == LD.STATUS.SESSION
		and LD:GetItems()[2].item == 2 and LD:GetItems()[3].item == 3 and LD:GetItems()[3].sid == sid)

	-- The response window: a row per item.
	check("the response window shows a row per item", Resp:IsShown() and Resp.rows[1]:IsShown() and Resp.rows[3]:IsShown() and not Resp.rows[4]:IsShown())
	check("each row names its item", Resp.rows[2].name:GetText() == "Belt of Might" and Resp.rows[3].name:GetText() == "Ring of Focus")
	check("each row has the five answers", #Resp.rows[2].buttons == 5)
	check("nothing is answered yet", Responses:GetMyResponse(1) == nil and Responses:CountMine() == 0)
	check("the status counts the answers", Resp.rows[1].parent.status:GetText():find("Answered 0 of 3", 1, true) ~= nil)

	----------------------------------------------------------------------------
	-- Answers, per item
	----------------------------------------------------------------------------
	H.sent = {}
	check("answer the second item", Responses:Send("BIS", 2) == true)
	check("only that item is answered", Responses:GetMyResponse(2) == "BIS" and Responses:GetMyResponse(1) == nil and Responses:CountMine() == 1)
	check("we are a candidate for item 2 only", Candidates:Get(ME, 2).response == "BIS" and Candidates:Get(ME, 1) == nil and #Candidates:GetList(3) == 0)
	local update = sent("CANDIDATE_UPDATE")[1]
	check("the council update names the item", update ~= nil and update.p.item == 2 and update.p.name == ME)
	check("the button of that row is selected", Resp.rows[2].buttons[1].selected == true and Resp.rows[1].buttons[1].selected == false)
	check("the status follows", Resp.rows[1].parent.status:GetText():find("Answered 1 of 3", 1, true) ~= nil)
	Responses:Send("UPGRADE", 1)
	Responses:Send("MINOR", 3)
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "BIS", gear = { "item:151" } }), "WHISPER", "Veyra Moo")
	Comm:Process(env("RESPONSE", sid, nil, { item = 2, response = "UPGRADE", gear = {} }), "WHISPER", "Veyra Moo")
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "PASS", gear = {} }), "WHISPER", "Kaelis Moo")
	check("lists are kept per item", #Candidates:GetList(1) == 3 and #Candidates:GetList(2) == 2 and #Candidates:GetList(3) == 1)
	check("counts are per item", Candidates:GetCounts(1).passed == 1 and Candidates:GetCounts(1).wanting == 2 and Candidates:GetCounts(2).passed == 0)
	check("the same player answers each item on its own", Candidates:Get("Veyra Moo", 1).response == "BIS" and Candidates:Get("Veyra Moo", 2).response == "UPGRADE")
	check("a player who was not asked about item 3 is not on its list", Candidates:Get("Veyra Moo", 3) == nil)

	H.sent = {}
	check("an answer for an item that does not exist is refused", Comm:Process(env("RESPONSE", sid, nil, { item = 4, response = "BIS", gear = {} }), "WHISPER", "Jonatan Moo") == false)
	check("and nothing was added", #Candidates:GetList(1) == 3 and Candidates:Get("Jonatan Moo", 4) == nil)
	local okS, msgS = Responses:Send("BIS", 5)
	check("we cannot answer an item that is not there", okS == false and msgS ~= nil)

	-- Changing an answer changes only that item.
	Responses:Send("OFFSPEC", 2)
	check("a changed answer replaces the old one", Candidates:Get(ME, 2).response == "OFFSPEC" and Candidates:Get(ME, 1).response == "UPGRADE")

	----------------------------------------------------------------------------
	-- Votes, per item
	----------------------------------------------------------------------------
	H.sent = {}
	check("vote for Veyra on item 1", Voting:Cast("Veyra Moo", 1) == true)
	check("and for somebody else on item 2", Voting:Cast(ME, 2) == true)
	check("one vote each, on its own item", Voting:GetMyVote(1) == "Veyra Moo" and Voting:GetMyVote(2) == ME and Voting:GetMyVote(3) == nil)
	check("counts are per item", Voting:GetVotes("Veyra Moo", 1) == 1 and Voting:GetVotes("Veyra Moo", 2) == 0 and Voting:GetVotes(ME, 2) == 1 and Voting:GetVotes(ME, 1) == 0)
	local updates = sent("VOTE_UPDATE")
	local items = {}
	for _, u in ipairs(updates) do items[u.p.item] = true end
	check("the vote updates name their item", items[1] == true and items[2] == true and items[3] == nil)
	Comm:Process(env("VOTE", sid, nil, { item = 1, candidate = "Veyra Moo" }), "WHISPER", "Kaelis Moo")
	check("another council member votes on item 1", Voting:GetVotes("Veyra Moo", 1) == 2)
	Comm:Process(env("VOTE", sid, nil, { item = 3, candidate = ME }), "WHISPER", "Kaelis Moo")
	check("the same member votes on item 3 without touching item 1", Voting:GetVotes(ME, 3) == 1 and Voting:GetVotes("Veyra Moo", 1) == 2)
	Comm:Process(env("VOTE", sid, nil, { item = 3, candidate = "Veyra Moo" }), "WHISPER", "Kaelis Moo")
	check("a vote for a player who did not answer that item is ignored", Voting:GetVotes("Veyra Moo", 3) == 0 and Voting:GetVotes(ME, 3) == 1)
	Comm:Process(env("RESPONSE", sid, nil, { item = 3, response = "UPGRADE", gear = {} }), "WHISPER", "Jonatan Moo")
	Comm:Process(env("VOTE", sid, nil, { item = 3, candidate = "Jonatan Moo" }), "WHISPER", "Kaelis Moo")
	check("moving a vote on item 3 leaves item 1 alone", Voting:GetVotes(ME, 3) == 0 and Voting:GetVotes("Jonatan Moo", 3) == 1 and Voting:GetVotes("Veyra Moo", 1) == 2)
	Comm:Process(env("VOTE", sid, nil, { item = 3 }), "WHISPER", "Kaelis Moo")
	check("a vote is taken back on its own item", Voting:GetVotes("Jonatan Moo", 3) == 0 and Voting:GetVotes("Veyra Moo", 1) == 2)
	local okV, msgV = Voting:Cast("Kaelis Moo", 1)
	check("nobody votes for a player who passed that item", okV == false and msgV ~= nil)
	check("but that player is a fine choice on an item they did not pass", (function()
		Comm:Process(env("RESPONSE", sid, nil, { item = 2, response = "MINOR", gear = {} }), "WHISPER", "Kaelis Moo")
		return Voting:Cast("Kaelis Moo", 2) == true and Voting:GetVotes("Kaelis Moo", 2) == 1
	end)())
	local okX, msgX = Voting:Cast("Veyra Moo", 9)
	check("a vote on a missing item is refused", okX == false and msgX ~= nil)
	local stored = ALC.Settings:GetSessionStore().votes
	local storedItems = {}
	for _, v in ipairs(stored) do storedItems[v.item] = true end
	check("votes are saved with their item", storedItems[1] == true and storedItems[2] == true and storedItems[3] == nil)
	local savedCandidates = ALC.Settings:GetSessionStore().candidates
	check("candidates are saved with their item", #savedCandidates == 8 and savedCandidates[1].item == 1 and savedCandidates[#savedCandidates].item == 3)

	----------------------------------------------------------------------------
	-- The council window: the item strip
	----------------------------------------------------------------------------
	Win:Show()
	local strip = Win.strip
	check("three strip buttons for three items", strip[1]:IsShown() and strip[2]:IsShown() and strip[3]:IsShown() and not strip[4]:IsShown())
	check("the first item is shown", Win:GetFocus() == 1 and Win.rows[1].parent.name:GetText() == "Crown of Destruction")
	check("the counter names the item", Win.rows[1].parent.sub:GetText():find("Item 1 of 3", 1, true) ~= nil)
	check("the strip button marks the item shown", strip[1].selected:IsShown() and not strip[2].selected:IsShown())
	check("its badge counts those who want the item", strip[1].badge.text:GetText() == "2" and strip[2].badge.text:GetText() == "3")
	local names = {}
	for _, entry in ipairs(Win:GetVisible()) do names[#names + 1] = entry.name end
	check("the table lists item 1's candidates", table.concat(names, ",") == "Veyra Moo,Tester Moo")
	strip[2].scripts.OnClick(strip[2])
	check("a click on the strip switches item", Win:GetFocus() == 2 and Win.rows[1].parent.name:GetText() == "Belt of Might")
	names = {}
	for _, entry in ipairs(Win:GetVisible()) do names[#names + 1] = entry.name end
	check("and the table follows", table.concat(names, ",") == "Veyra Moo,Kaelis Moo,Tester Moo")
	check("votes shown are those of that item", Win.rows[2].candidate == "Kaelis Moo" and Win.rows[2].votes.text:GetText() == "1" and Win.rows[3].votes.text:GetText() ~= "1")
	check("the strip follows the switch", strip[2].selected:IsShown() and not strip[1].selected:IsShown())
	check("the vote button reflects the vote on this item", Win.rows[2].vote.label:GetText() == "Voted" and Win.rows[1].vote.label:GetText() == "Vote")
	check("a missing item cannot be chosen", Win:SetFocus(4) == false and Win:SetFocus(0) == false and Win:GetFocus() == 2)
	Win:SetFocus(1)

	-- The row menu works on the item shown.
	Win:SetFocus(2)
	local menu = Win:GetRowMenu("Kaelis Moo")
	check("the menu is about the item shown", menu[1].label == "Voted" and Win:GetRowMenu(ME)[1].label == "Vote")
	local before = Candidates:Get(ME, 1).response
	Win:GetRowMenu("Veyra Moo")
	for _, item in ipairs(Win:GetRowMenu("Veyra Moo")) do
		if item.label == "Minor" then item.onClick() end
	end
	check("Change response changes the item shown only", Candidates:Get("Veyra Moo", 2).response == "MINOR" and Candidates:Get("Veyra Moo", 1).response == "BIS")
	check("and the same for the loot master's own row on another item", Candidates:Get(ME, 1).response == before)
	Win:SetFocus(1)

	----------------------------------------------------------------------------
	-- Awards, item by item
	----------------------------------------------------------------------------
	local okNo, msgNo = Awards:Award("Jonatan Moo", 1)
	check("awarding somebody who did not answer that item is refused", okNo == false and msgNo ~= nil)
	local okBadItem, msgBadItem = Awards:Award("Veyra Moo", 7)
	check("awarding a missing item is refused", okBadItem == false and msgBadItem ~= nil)
	H.sent = {}
	check("award item 2 to Kaelis", Awards:Award("Kaelis Moo", 2) == true)
	local awardMsg = sent("AWARD")[1]
	check("the AWARD names item 2 and its itemID", awardMsg ~= nil and awardMsg.p.item == 2 and awardMsg.p.itemID == 201 and awardMsg.p.winner == "Kaelis Moo")
	check("the session goes on", Sessions:IsActive() and Sessions:GetActiveSid() == sid)
	check("item 2 is done, the others are open", not Sessions:IsItemOpen(2) and Sessions:IsItemOpen(1) and Sessions:IsItemOpen(3) and Sessions:GetItem(2).winner == "Kaelis Moo")
	local log = Awards:GetLog()
	check("the log has that item", log[#log].itemID == 201 and log[#log].winner == "Kaelis Moo" and log[#log].votes == 1)
	check("the announcement names that item", Awards:GetLastAnnouncement():find("Belt of Might", 1, true) ~= nil)
	check("the loot list entry of that item is awarded, the others still in the session", LD:GetItems()[2].status ~= LD.STATUS.SESSION and LD:GetItems()[1].status == LD.STATUS.SESSION
		and LD:GetItems()[3].status == LD.STATUS.SESSION)
	check("an awarded item cannot be awarded again", Awards:Award("Veyra Moo", 2) == false)
	local okR, msgR = Responses:Send("BIS", 2)
	check("nor answered", okR == false and msgR ~= nil)
	local okVt, msgVt = Voting:Cast("Veyra Moo", 2)
	check("nor voted on", okVt == false and msgVt ~= nil)
	local okSet = Candidates:SetResponse("Veyra Moo", "PASS", 2)
	check("nor changed", okSet == false)
	Comm:Process(env("RESPONSE", sid, nil, { item = 2, response = "BIS", gear = {} }), "WHISPER", "Jonatan Moo")
	check("a late answer for an awarded item is ignored", Candidates:Get("Jonatan Moo", 2) == nil)
	Comm:Process(env("VOTE", sid, nil, { item = 2, candidate = "Veyra Moo" }), "WHISPER", "Kaelis Moo")
	check("a late vote for an awarded item is ignored", Voting:GetVotes("Veyra Moo", 2) == 0)
	check("a second AWARD for item 2 is ignored", (function()
		Comm:SendRaid("AWARD", sid, { item = 2, winner = "Veyra Moo", itemID = 201, response = "BIS" })
		return Sessions:GetItem(2).winner == "Kaelis Moo"
	end)())
	check("an AWARD whose itemID does not fit is ignored", (function()
		Comm:SendRaid("AWARD", sid, { item = 3, winner = "Veyra Moo", itemID = 200, response = "BIS" })
		return Sessions:GetItem(3).winner == nil and Sessions:IsActive()
	end)())

	check("the strip marks the awarded item", strip[2].check:IsShown() and strip[2].winner == "Kaelis Moo" and not strip[1].check:IsShown())
	check("and its badge is gone", not strip[2].badge:IsShown())
	Win:SetFocus(2)
	check("an awarded item shows who won", Win.rows[1].parent.sub:GetText() :find("^Awarded to Kaelis Moo") ~= nil)
	check("and offers no vote or award", not Win.rows[1].vote:IsShown() and not Win.rows[1].award:IsShown())
	check("nor a menu", #Win:GetRowMenu("Veyra Moo") == 0)
	Win:SetFocus(1)
	check("the other items still do", Win.rows[1].vote:IsShown() and Win.rows[1].award:IsShown())

	-- Awarding the shown item moves the table on to the next open item.
	Win:SetFocus(1)
	Awards:Award("Veyra Moo", 1)
	check("after an award the table moves to the next open item", Win:GetFocus() == 3 and Win.rows[1].parent.name:GetText() == "Ring of Focus")
	check("the session is still running with one item open", Sessions:IsActive() and Sessions:IsItemOpen(3))
	check("the response window lists open items first, awarded ones after", Resp.rows[1].name:GetText() == "Ring of Focus" and Resp.rows[1].buttons[1]:IsShown()
		and Resp.rows[2].name:GetText() == "Crown of Destruction" and Resp.rows[3].name:GetText() == "Belt of Might")
	check("an awarded row shows the winner instead of the buttons", Resp.rows[2].result:IsShown() and Resp.rows[2].result:GetText() == "Awarded to Veyra Moo"
		and not Resp.rows[2].buttons[1]:IsShown() and Resp.rows[3].result:GetText() == "Awarded to Kaelis Moo")
	check("a click in a moved row answers that row's item", (function()
		Resp.rows[1].buttons[2].scripts.OnClick(Resp.rows[1].buttons[2])
		return Responses:GetMyResponse(3) == "UPGRADE"
	end)())

	-- Everybody passing: the item stays in the table's reach.
	Win:SetFocus(3)
	Candidates:SetResponse(ME, "PASS", 3)
	Candidates:SetResponse("Veyra Moo", "PASS", 3) -- not a candidate here: refused
	Comm:Process(env("RESPONSE", sid, nil, { item = 3, response = "PASS", gear = {} }), "WHISPER", "Jonatan Moo")
	check("nobody left who wants it", #Win:GetVisible() == 0 and Candidates:GetCounts(3).wanting == 0 and Candidates:GetCounts(3).passed == 2)
	check("the table says everybody passed, and how to see them", Win.rows[1].parent.empty:IsShown() and Win.rows[1].parent.empty:GetText():find("passed (2)", 1, true) ~= nil)
	check("the strip shows a grey zero for it", Win.strip[3].badge:IsShown() and Win.strip[3].badge.text:GetText() == "0")
	check("Show passed lists them", (function()
		Win.rows[1].parent.showPassed.scripts.OnClick(Win.rows[1].parent.showPassed)
		return Win:ShowsPassed() and #Win:GetVisible() == 2 and Win.rows[1]:IsShown() and Win.rows[2]:IsShown()
	end)())
	check("a passed player has no Vote or Award button", not Win.rows[1].vote:IsShown() and not Win.rows[1].award:IsShown())
	local passMenu = Win:GetRowMenu("Jonatan Moo")
	local passLabels = {}
	for _, item in ipairs(passMenu) do passLabels[#passLabels + 1] = item.label end
	check("the loot master can take a passed player back from the menu", table.concat(passLabels, "|") == "Change response|BiS|Upgrade|Minor|Offspec|Pass")
	for _, item in ipairs(passMenu) do
		if item.label == "Upgrade" then item.onClick() end
	end
	check("and then they are a candidate again", Candidates:Get("Jonatan Moo", 3).response == "UPGRADE" and Win.strip[3].badge.text:GetText() == "1")
	Win.rows[1].parent.showPassed.scripts.OnClick(Win.rows[1].parent.showPassed)
	check("Show passed switches off again", not Win:ShowsPassed())
	Candidates:SetResponse(ME, "MINOR", 3)

	-- A snapshot now: winners are in the item list.
	H.clock = H.clock + 100
	H.sent = {}
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Kaelis Moo")
	local snap = sent("STATE_SNAPSHOT")[1]
	check("a snapshot carries the items with their winners", snap ~= nil and #snap.p.items == 3 and snap.p.items[1].winner == "Veyra Moo"
		and snap.p.items[2].winner == "Kaelis Moo" and snap.p.items[3].winner == nil)
	local flatItems = {}
	for _, cnd in ipairs(snap.p.candidates or {}) do flatItems[cnd.item] = (flatItems[cnd.item] or 0) + 1 end
	check("a council member's snapshot has every item's candidates", flatItems[1] == 3 and flatItems[2] == 3 and flatItems[3] == 2)
	local yourVotes = {}
	for _, v in ipairs(snap.p.yourVotes or {}) do yourVotes[v.item] = v.candidate end
	check("and their own votes, item by item", yourVotes[1] == "Veyra Moo" and yourVotes[2] == nil and yourVotes[3] == nil)
	H.clock = H.clock + 100
	H.sent = {}
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Jonatan Moo")
	local raiderSnap = sent("STATE_SNAPSHOT")[1]
	check("a raider's snapshot has no candidates", raiderSnap ~= nil and raiderSnap.p.candidates == nil and raiderSnap.p.votes == nil)

	-- The last award ends the session.
	local ended
	local listener = {}
	ALC.Events.Register(listener, "ALC_SESSION_ENDED", function(_, endedSid, reason) ended = { sid = endedSid, reason = reason } end)
	Awards:Award(ME, 3)
	check("the last award ends the session as awarded", not Sessions:IsActive() and ended ~= nil and ended.reason == "awarded" and ended.sid == sid)
	check("all three entries are awarded", LD:GetItems()[1].status == LD.STATUS.AWARDED or LD:GetItems()[1].status == LD.STATUS.TRADE)
	check("nothing is left of the session", #Candidates:GetList(1) == 0 and Voting:GetMyVote(1) == nil and Responses:CountMine() == 0
		and ALC.Settings:GetSessionStore().session == nil and ALC.Settings:GetSessionStore().candidates == nil and ALC.Settings:GetSessionStore().votes == nil)
	check("the windows close", not Resp:IsShown() and not Win:IsShown())
	ALC.Events.UnregisterAll(listener)

	----------------------------------------------------------------------------
	-- Cancelling: unawarded items go back to waiting
	----------------------------------------------------------------------------
	LD:Clear()
	LD:AddFromText("200 201 202")
	check("three waiting items", #LD:GetPending() == 3)
	local okAll, count = LD:StartAll()
	check("Start all starts one session for them", okAll == true and count == 3 and Sessions:IsActive() and Sessions:GetItemCount() == 3)
	local sid2 = Sessions:GetActiveSid()
	local entries = LD:GetItems()
	check("each entry is tied to its item", entries[1].item == 1 and entries[2].item == 2 and entries[3].item == 3 and entries[1].sid == sid2)
	check("and shows in session", entries[1].status == LD.STATUS.SESSION and entries[3].status == LD.STATUS.SESSION)
	local okAgain, msgAgain = LD:StartAll()
	check("Start all while a session runs is refused", okAgain == false and msgAgain ~= nil)
	Responses:Send("BIS", 1)
	Comm:Process(env("RESPONSE", sid2, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
	Awards:Award("Veyra Moo", 1)
	check("one item awarded", not Sessions:IsItemOpen(1) and Sessions:IsActive())
	ALC.Settings:SetKeepCouncilOpen(true)
	Win:Show()
	Sessions:Cancel("stopped")
	check("the session is over", not Sessions:IsActive())
	check("a window kept open shows no item strip between sessions", Win:IsShown() and (function()
		for _, button in ipairs(Win.strip) do
			if button:IsShown() then return false end
		end
		return true
	end)())
	ALC.Settings:SetKeepCouncilOpen(false)
	Win:Hide()
	entries = LD:GetItems()
	check("the awarded item stays awarded", entries[1].status == LD.STATUS.AWARDED or entries[1].status == LD.STATUS.TRADE)
	check("the others wait for another session", entries[2].status == LD.STATUS.PENDING and entries[3].status == LD.STATUS.PENDING and entries[2].sid == nil)
	check("Start all takes just those two", (function()
		local ok, n = LD:StartAll()
		return ok == true and n == 2 and Sessions:GetItemCount() == 2 and Sessions:GetItem(1).itemID == 201
	end)())
	Sessions:Cancel("stopped")

	LD:Clear()
	local okEmpty, msgEmpty = LD:StartAll()
	check("nothing waiting, nothing started", okEmpty == false and msgEmpty ~= nil and not Sessions:IsActive())

	----------------------------------------------------------------------------
	-- A reload in the middle of a multi-item session
	----------------------------------------------------------------------------
	LD:AddFromText("200 201 202")
	LD:StartAll()
	local sid3 = Sessions:GetActiveSid()
	Responses:Send("UPGRADE", 1)
	Responses:Send("MINOR", 3)
	Comm:Process(env("RESPONSE", sid3, nil, { item = 2, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
	Comm:Process(env("RESPONSE", sid3, nil, { item = 3, response = "UPGRADE", gear = {} }), "WHISPER", "Veyra Moo")
	Voting:Cast("Veyra Moo", 3)
	Voting:Cast("Veyra Moo", 2)
	Awards:Award("Veyra Moo", 2)
	local saved = H.snapshotDB()
	check("the saved session has all items and the winner", (function()
		local s = saved.global.sessionStore.session
		return s and #s.items == 3 and s.items[2].winner == "Veyra Moo" and s.items[1].winner == nil
	end)())

	H.reload(saved)
	leader = ME
	world()
	Sessions, Candidates, Voting, Responses, Awards, Comm = ALC.Sessions, ALC.Candidates, ALC.Voting, ALC.Responses, ALC.Awards, ALC.Comm
	Win, Resp, LD = ALC.CouncilWindow, ALC.ResponseWindow, ALC.LootDetection
	check("nothing runs right after the reload", not Sessions:IsActive())
	Sessions:OnEnteringWorld(false, true)
	check("the session is back with its three items", Sessions:GetActiveSid() == sid3 and Sessions:GetItemCount() == 3)
	check("the winner of item 2 is remembered", Sessions:GetItem(2).winner == "Veyra Moo" and Sessions:IsItemOpen(1) and Sessions:IsItemOpen(3))
	check("candidates are back per item", Candidates:Get(ME, 1).response == "UPGRADE" and Candidates:Get("Veyra Moo", 3).response == "UPGRADE"
		and Candidates:Get(ME, 3).response == "MINOR" and Candidates:Get(ME, 2) == nil)
	check("votes are back per item", Voting:GetVotes("Veyra Moo", 3) == 1 and Voting:GetMyVote(3) == "Veyra Moo")
	check("our answers are back per item", Responses:GetMyResponse(1) == "UPGRADE" and Responses:GetMyResponse(3) == "MINOR" and Responses:GetMyResponse(2) == nil)
	local entries2 = LD:GetItems()
	check("the loot list entries are back on their items", entries2[1].status == LD.STATUS.SESSION and entries2[3].status == LD.STATUS.SESSION
		and entries2[2].status ~= LD.STATUS.SESSION and entries2[2].winner == "Veyra Moo")
	Sessions:Cancel("done")

	-- A player who reloads gets the items, winners and their own answers from the loot master.
	H.reload("fresh")
	leader = "Veyra Moo"
	world()
	Sessions, Candidates, Voting, Responses, Comm = ALC.Sessions, ALC.Candidates, ALC.Voting, ALC.Responses, ALC.Comm
	Win, Resp = ALC.CouncilWindow, ALC.ResponseWindow
	H.clock = H.clock + 100
	check("ask for the state", Sessions:RequestState() == true)
	local council = { "Veyra Moo", ME }
	local snapshot = {
		items = { { itemID = 200, itemString = "item:200" }, { itemID = 201, itemString = "item:201", winner = "Kaelis Moo" }, { itemID = 202, itemString = "item:202" } },
		council = council, lm = "Veyra Moo",
		candidates = {
			{ item = 1, name = "Kaelis Moo", class = "HUNTER", response = "BIS", gear = {} },
			{ item = 3, name = ME, class = "ROGUE", response = "MINOR", gear = {} },
		},
		votes = { { item = 3, candidate = ME, voters = { "Veyra Moo", ME } } },
		yourResponses = { { item = 1, response = "PASS" }, { item = 3, response = "MINOR" } },
		yourVotes = { { item = 3, candidate = ME } },
	}
	check("the snapshot is accepted", Comm:Process(env("STATE_SNAPSHOT", "sidR", 1, snapshot), "WHISPER", "Veyra Moo") == true)
	check("the session is back with its winners", Sessions:GetActiveSid() == "sidR" and Sessions:GetItem(2).winner == "Kaelis Moo" and Sessions:IsItemOpen(3))
	check("candidates and votes are back per item", Candidates:Get("Kaelis Moo", 1).response == "BIS" and Candidates:Get(ME, 3).response == "MINOR"
		and Voting:GetVotes(ME, 3) == 2 and Voting:GetMyVote(3) == ME and Voting:GetMyVote(1) == nil)
	check("our own answers are back per item", Responses:GetMyResponse(1) == "PASS" and Responses:GetMyResponse(3) == "MINOR" and Responses:GetMyResponse(2) == nil)
	check("the response window shows the awarded item as awarded", Resp:IsShown() == false or Resp.rows[2].result:GetText() == "Awarded to Kaelis Moo")
	local malformed = { items = snapshot.items, council = council, lm = "Veyra Moo", yourResponses = { { response = "PASS" } } }
	H.clock = H.clock + 100
	Sessions:RequestState()
	Comm:Process(env("SESSION_CANCEL", "sidR", 2, { reason = "done" }), "PARTY", "Veyra Moo")
	Sessions:RequestState()
	check("a snapshot whose answers do not name an item is refused", Comm:Process(env("STATE_SNAPSHOT", "sidS", 1, malformed), "WHISPER", "Veyra Moo") == false)

	----------------------------------------------------------------------------
	-- A session saved by version 0.1 (no item numbers) still comes back
	----------------------------------------------------------------------------
	H.reload("fresh")
	leader = ME
	world()
	ALC.Settings:AddCouncilMember("Veyra Moo")
	ALC.Sessions:Start(200)
	local legacySid = ALC.Sessions:GetActiveSid()
	ALC.Responses:Send("BIS")
	ALC.Comm:Process(env("RESPONSE", legacySid, nil, { item = 1, response = "UPGRADE", gear = {} }), "WHISPER", "Veyra Moo")
	ALC.Voting:Cast("Veyra Moo")
	local old = H.snapshotDB()
	local s = old.global.sessionStore
	s.session.itemID, s.session.itemString = s.session.items[1].itemID, s.session.items[1].itemString
	s.session.items = nil
	for _, entry in ipairs(s.candidates) do entry.item = nil end
	for _, vote in ipairs(s.votes) do vote.item = nil end
	H.reload(old)
	leader = ME
	world()
	ALC.Council:Refresh()
	local okLegacy = pcall(ALC.Sessions.OnEnteringWorld, ALC.Sessions, false, true)
	check("an old saved session restores without an error", okLegacy and ALC.Sessions:IsActive() and ALC.Sessions:GetItemCount() == 1)
	check("as a one-item session", ALC.Sessions:GetItem(1).itemID == 200 and ALC.Sessions:IsItemOpen(1))
	check("its candidates, votes and our answer land on item 1", #ALC.Candidates:GetList(1) == 2 and ALC.Voting:GetVotes("Veyra Moo", 1) == 1
		and ALC.Voting:GetMyVote(1) == "Veyra Moo" and ALC.Responses:GetMyResponse(1) == "BIS")
	ALC.Sessions:Cancel("done")

	-- Put the environment back.
	UnitIsConnected = function() return true end
	H.inGroup = false
	C_Item.GetItemInfo = function() end
	C_Item.GetItemInfoInstant = nil
	C_Item.RequestLoadItemDataByID = nil
end

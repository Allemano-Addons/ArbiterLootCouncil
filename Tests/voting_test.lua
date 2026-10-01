-- Voting and the council window, on the real modules.
-- Runs before the Comm tests, which replace Council and Sessions with stand-ins.

return function(check, H)
	local Voting, Candidates, Sessions, Council, Comm, Win = ALC.Voting, ALC.Candidates, ALC.Sessions, ALC.Council, ALC.Comm, ALC.CouncilWindow
	local AceSerializer = LibStub("AceSerializer-3.0")
	local ME = "Tester Moo"

	local env = H.env

	-- Item data.
	local db = {
		[200] = { "Crown of Destruction", 4, "INVTYPE_HEAD" },
		[151] = { "Old Helm", 3, "INVTYPE_HEAD" },
		[152] = { "Old Ring", 2, "INVTYPE_FINGER" },
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

	ALC.Gear.GetEquippedLink = function() return nil end -- we wear nothing in these tests

	-- A party: we lead it (group loot), the council is us, Veyra and Kaelis.
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
	Win:Hide()

	-- Regression: closing a window before it was ever moved saves only "closed", with no
	-- position. Reading that as a position crashed SetPoint(nil).
	ALC.Settings:GetDB().profile.windows.council = { shown = false }
	check("a window with only an open/closed flag has no saved position", ALC.Settings:GetWindowPosition("council") == nil)
	ALC.Settings:GetDB().profile.windows.loot = { shown = true }
	ALC.Settings:GetDB().profile.windows.response = { shown = true }
	check("the same holds for the other windows", ALC.Settings:GetWindowPosition("loot") == nil and ALC.Settings:GetWindowPosition("response") == nil)

	local changes = 0
	local listener = {}
	ALC.Events.Register(listener, "ALC_VOTING_CHANGED", function() changes = changes + 1 end)

	local function updates()
		local found = {}
		for _, sent in ipairs(H.sent) do
			local _, e = AceSerializer:Deserialize(sent.text)
			if e and e.t == "VOTE_UPDATE" then found[#found + 1] = { target = sent.target, p = e.p, seq = e.seq } end
		end
		return found
	end
	local function targetsOf(list)
		local t = {}
		for _, u in ipairs(list) do t[#t + 1] = u.target end
		table.sort(t)
		return table.concat(t, ",")
	end
	local function votersOf(name) local _, voters = Voting:GetVotes(name) return table.concat(voters, ",") end

	if Sessions:IsActive() then Sessions:Cancel("test reset") end

	----------------------------------------------------------------------------
	-- Before a session
	----------------------------------------------------------------------------
	local ok0, msg0 = Voting:Cast("Veyra Moo")
	check("no vote without a session", ok0 == false and msg0 ~= nil)
	check("no votes, no vote of ours", Voting:GetVotes("Veyra Moo") == 0 and Voting:GetMyVote() == nil)
	Win:Show()
	check("the voting window needs a session", not Win:IsShown())

	----------------------------------------------------------------------------
	-- As loot master: a session with answers
	----------------------------------------------------------------------------
	check("start a session", Sessions:Start(200) == true)
	local sid = Sessions:GetActiveSid()
	check("the voting window opens for the council", Win:IsShown())
	ALC.Responses:Send("UPGRADE") -- us
	Comm:Process(env("RESPONSE", sid, nil, { response = "BIS", gear = { "item:151" } }), "WHISPER", "Veyra Moo")
	Comm:Process(env("RESPONSE", sid, nil, { response = "MINOR", gear = { "item:151", "item:152" } }), "WHISPER", "Jonatan Moo")
	Comm:Process(env("RESPONSE", sid, nil, { response = "PASS", gear = {} }), "WHISPER", "Kaelis Moo")
	check("four answers in", #Candidates:GetList() == 4)

	local okX, msgX = Voting:Cast("Nobody Moo")
	check("cannot vote for someone who has not answered", okX == false and msgX ~= nil)
	local okP, msgP = Voting:Cast("Kaelis Moo")
	check("cannot vote for someone who passed", okP == false and msgP ~= nil)

	----------------------------------------------------------------------------
	-- Casting, moving and taking back a vote
	----------------------------------------------------------------------------
	H.sent = {}
	check("vote for Veyra", Voting:Cast("veyra moo") == true)
	check("one vote, ours", Voting:GetVotes("Veyra Moo") == 1 and votersOf("Veyra Moo") == ME)
	check("and it is our vote", Voting:GetMyVote() == "Veyra Moo")
	local sentUpdates = updates()
	check("only the council was told", targetsOf(sentUpdates) == "Kaelis Moo,Veyra Moo")
	check("the update carries the count and the voters", sentUpdates[1].p.candidate == "Veyra Moo" and sentUpdates[1].p.votes == 1 and sentUpdates[1].p.voters[1] == ME)
	check("voters changed event", changes > 0)

	H.sent = {}
	check("voting for the same player takes the vote back", Voting:Cast("Veyra Moo") == true)
	check("no votes left, no vote of ours", Voting:GetVotes("Veyra Moo") == 0 and Voting:GetMyVote() == nil)
	local backUpdate = updates()
	check("the council hears that Veyra has none", #backUpdate == 2 and backUpdate[1].p.votes == 0 and #backUpdate[1].p.voters == 0)

	Voting:Cast("Veyra Moo")
	H.sent = {}
	Voting:Cast("Jonatan Moo")
	check("the vote moved", Voting:GetVotes("Veyra Moo") == 0 and Voting:GetVotes("Jonatan Moo") == 1 and Voting:GetMyVote() == "Jonatan Moo")
	local moved = updates()
	local candidates = {}
	for _, u in ipairs(moved) do candidates[u.p.candidate] = (candidates[u.p.candidate] or 0) + 1 end
	check("both candidates' counts were sent", candidates["Veyra Moo"] == 2 and candidates["Jonatan Moo"] == 2)

	-- Other council members.
	H.sent = {}
	check("Veyra votes for Jonatan", Comm:Process(env("VOTE", sid, nil, { candidate = "Jonatan Moo" }), "WHISPER", "Veyra Moo") == true)
	check("two votes, listed by name", Voting:GetVotes("Jonatan Moo") == 2 and votersOf("Jonatan Moo") == "Tester Moo,Veyra Moo")
	H.sent = {}
	Comm:Process(env("VOTE", sid, nil, { candidate = "Jonatan Moo" }), "WHISPER", "Veyra Moo")
	check("a repeated vote changes nothing and tells nobody", #updates() == 0 and Voting:GetVotes("Jonatan Moo") == 2)
	check("a non-council member cannot vote", Comm:Process(env("VOTE", sid, nil, { candidate = "Veyra Moo" }), "WHISPER", "Jonatan Moo") == false
		and Voting:GetVotes("Veyra Moo") == 0)
	Comm:Process(env("VOTE", sid, nil, { candidate = "Kaelis Moo" }), "WHISPER", "Veyra Moo")
	check("a vote for a player who passed is ignored", Voting:GetVotes("Kaelis Moo") == 0 and Voting:GetVotes("Jonatan Moo") == 2)
	Comm:Process(env("VOTE", sid, nil, { candidate = "Nobody Moo" }), "WHISPER", "Veyra Moo")
	check("a vote for a stranger is ignored", Voting:GetVotes("Nobody Moo") == 0 and Voting:GetVotes("Jonatan Moo") == 2)
	Comm:Process(env("VOTE", sid, nil, {}), "WHISPER", "Veyra Moo")
	check("a vote can be withdrawn", Voting:GetVotes("Jonatan Moo") == 1 and votersOf("Jonatan Moo") == ME)
	Comm:Process(env("VOTE", sid, nil, {}), "WHISPER", "Kaelis Moo")
	check("withdrawing without a vote changes nothing", Voting:GetVotes("Jonatan Moo") == 1)

	-- The votes are saved for a reload.
	local store = ALC.Settings:GetSessionStore()
	check("the votes are saved", store.votes ~= nil and #store.votes == 1 and store.votes[1].voter == ME and store.votes[1].candidate == "Jonatan Moo")

	----------------------------------------------------------------------------
	-- Snapshots
	----------------------------------------------------------------------------
	Comm:Process(env("VOTE", sid, nil, { candidate = "Veyra Moo" }), "WHISPER", "Veyra Moo")
	H.clock = H.clock + 100
	H.sent = {}
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Veyra Moo")
	local _, councilSnap = AceSerializer:Deserialize(H.sent[1].text)
	local votesByName = {}
	for _, vote in ipairs(councilSnap.p.votes or {}) do votesByName[vote.candidate] = #vote.voters end
	check("a council member gets the votes and their own vote", votesByName["Jonatan Moo"] == 1 and votesByName["Veyra Moo"] == 1 and councilSnap.p.yourVotes[1].candidate == "Veyra Moo" and councilSnap.p.yourVotes[1].item == 1)
	H.sent = {}
	H.clock = H.clock + 100
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Jonatan Moo")
	local _, raiderSnap = AceSerializer:Deserialize(H.sent[1].text)
	check("a raider gets no votes", raiderSnap.p.votes == nil and raiderSnap.p.yourVotes == nil)

	----------------------------------------------------------------------------
	-- The council window
	----------------------------------------------------------------------------
	local rows = Win.rows
	Win:Hide()
	Win:Show()
	local frame = rows[1].parent
	check("the window is open, with a pool of rows to scroll through", Win:IsShown() and #rows == 30)
	check("a short list needs no scrollbar", not frame.scroll:IsShown())
	local visible = Win:GetVisible()
	check("those who passed are not listed", #visible == 3)
	check("ordered by answer: BiS, Upgrade, Minor", visible[1].name == "Veyra Moo" and visible[2].name == ME and visible[3].name == "Jonatan Moo")
	check("one row per candidate", rows[3]:IsShown() and not rows[4]:IsShown())
	check("name, class and answer", rows[1].name:GetText() == "Veyra Moo" and rows[1].class:GetText() == "WARRIOR" and rows[1].chip.label:GetText() == "BiS")
	check("the class colours the name", rows[1].name.textColor[1] == 0.78)
	check("current gear is listed with its quality colour", rows[1].gear[1].text:GetText() == "Old Helm" and rows[1].gear[1].text.textColor[3] < 0.9)
	check("two items of gear give two lines", rows[3].gear[1].text:GetText() == "Old Helm" and rows[3].gear[2].text:GetText() == "Old Ring" and rows[3].gear[2]:IsShown())
	check("nothing equipped is said so", rows[2].gear[1].text:GetText() == "Nothing equipped" and not rows[2].gear[2]:IsShown())
	check("vote counts", rows[1].votes.text:GetText() == "1" and rows[3].votes.text:GetText() == "1")
	rows[1].gear[1].scripts.OnEnter(rows[1].gear[1])
	check("hovering the gear shows its tooltip", GameTooltip.hyperlink == "item:151")
	rows[3].votes.scripts.OnEnter(rows[3].votes)
	rows[3].votes.scripts.OnLeave(rows[3].votes)
	check("progress and footer", frame.progress:GetText() == "4/4 responded" and frame.tally:GetText():find("1 passed", 1, true) ~= nil)
	check("the loot master is named", frame.lootMaster:GetText():find(ME, 1, true) ~= nil)
	check("the item is shown", frame.name:GetText() == "Crown of Destruction")

	-- The buttons: start from no vote of ours.
	Comm:Process(env("VOTE", sid, nil, {}), "WHISPER", "Veyra Moo")
	if Voting:GetMyVote() then Voting:Cast(Voting:GetMyVote()) end
	check("we have no vote now", Voting:GetMyVote() == nil)
	local target
	for _, row in ipairs(rows) do if row:IsShown() and row.candidate == "Veyra Moo" then target = row end end
	check("the Vote button says Vote", target.vote.label:GetText() == "Vote" and target.vote.selected == false)
	target.vote.scripts.OnClick(target.vote)
	check("clicking Vote votes", Voting:GetMyVote() == "Veyra Moo" and target.vote.label:GetText() == "Voted" and target.vote.selected == true)
	check("and the count follows", target.votes.text:GetText() == "1")
	target.vote.scripts.OnClick(target.vote)
	check("clicking Voted takes the vote back", Voting:GetMyVote() == nil and target.vote.label:GetText() == "Vote")

	-- Sorting: by response (the default), by votes, by name.
	local function order()
		local names = {}
		for _, entry in ipairs(Win:GetVisible()) do names[#names + 1] = entry.name end
		return table.concat(names, ",")
	end
	check("the default order is by response", Win:GetSortMode() == "response" and order() == "Veyra Moo,Tester Moo,Jonatan Moo")
	check("the sort button names the order", frame.sort.label:GetText() == "Sort: By response")
	Voting:Cast("Jonatan Moo")
	check("by response still puts BiS above a vote leader", order() == "Veyra Moo,Tester Moo,Jonatan Moo")
	Win:SetSortMode("votes")
	check("by votes, the player with most votes is on top", order() == "Jonatan Moo,Veyra Moo,Tester Moo")
	check("the sort button follows", frame.sort.label:GetText() == "Sort: By votes")
	check("rows follow the order", rows[1].candidate == "Jonatan Moo")
	Win:SetSortMode("name")
	check("by name", order() == "Jonatan Moo,Tester Moo,Veyra Moo")
	Win:SetSortMode("nonsense")
	check("an unknown order is ignored", Win:GetSortMode() == "name")
	frame.sort.scripts.OnClick(frame.sort)
	check("the button steps to the next order", Win:GetSortMode() == "response")
	frame.sort.scripts.OnClick(frame.sort)
	check("and on", Win:GetSortMode() == "votes")
	check("the order is saved", ALC.Settings:GetWindowOption("council", "sort") == "votes")
	ALC.Settings:GetDB().profile.windows.council.sort = "garbage"
	check("a damaged saved order falls back to response", Win:GetSortMode() == "response")
	Voting:Cast("Jonatan Moo")
	check("the vote is taken back", Voting:GetMyVote() == nil)

	-- The right-click menu: the loot master can vote, award, change the answer and remove.
	local function labels(items)
		local t = {}
		for _, item in ipairs(items) do t[#t + 1] = item.label end
		return table.concat(t, "|")
	end
	local menuItems = Win:GetRowMenu("Veyra Moo")
	check("the loot master's menu", labels(menuItems) == "Vote|Award|Change response|BiS|Upgrade|Minor|Offspec|Pass|Remove from consideration")
	local byLabel = {}
	for _, item in ipairs(menuItems) do byLabel[item.label] = item end
	check("the current answer cannot be picked again", byLabel["BiS"].enabled == false and byLabel["Upgrade"].enabled == true)
	check("Change response is a caption", byLabel["Change response"].header == true)
	check("no menu for a stranger", #Win:GetRowMenu("Nobody Moo") == 0)

	local Menu = ALC.ContextMenu
	local rowOfVeyra
	for _, row in ipairs(rows) do if row:IsShown() and row.candidate == "Veyra Moo" then rowOfVeyra = row end end
	rowOfVeyra.scripts.OnClick(rowOfVeyra, "LeftButton")
	check("a left click on a row opens no menu", not Menu:IsShown())
	rowOfVeyra.scripts.OnClick(rowOfVeyra, "RightButton")
	check("a right click on a row opens the menu", Menu:IsShown())
	check("with the player's name as caption and one line per entry", Menu.rows[1].label:GetText() == "VEYRA MOO"
		and Menu.rows[2].label:GetText() == "Vote" and Menu.rows[10].label:GetText() == "Remove from consideration"
		and (Menu.rows[11] == nil or not Menu.rows[11]:IsShown()))
	H.sent = {}
	Menu.rows[6].scripts.OnClick(Menu.rows[6]) -- caption, Vote, Award, caption, BiS, Upgrade
	check("choosing an answer closes the menu", not Menu:IsShown())
	check("the answer was changed", Candidates:Get("Veyra Moo").response == "UPGRADE")
	local changedUpdates = {}
	for _, sent in ipairs(H.sent) do
		local _, e = AceSerializer:Deserialize(sent.text)
		if e and e.t == "CANDIDATE_UPDATE" then changedUpdates[#changedUpdates + 1] = { target = sent.target, p = e.p } end
	end
	check("only the council heard of it", #changedUpdates == 2 and changedUpdates[1].p.name == "Veyra Moo" and changedUpdates[1].p.response == "UPGRADE")
	Win:OpenRowMenu("Veyra Moo")
	Menu.rows[6].scripts.OnClick(Menu.rows[6]) -- Upgrade is the current answer now: disabled
	check("a disabled entry does nothing", Menu:IsShown() and Candidates:Get("Veyra Moo").response == "UPGRADE")
	Menu:Hide()
	check("the loot master can change it back", Candidates:SetResponse("Veyra Moo", "BIS") == true and Candidates:Get("Veyra Moo").response == "BIS")
	local okBad, msgBad = Candidates:SetResponse("Veyra Moo", "MAYBE")
	check("an unknown answer is refused", okBad == false and msgBad ~= nil and Candidates:Get("Veyra Moo").response == "BIS")
	local okNone, msgNone = Candidates:SetResponse("Nobody Moo", "BIS")
	check("a stranger cannot be given an answer", okNone == false and msgNone ~= nil)
	H.sent = {}
	check("same answer again changes nothing and tells nobody", Candidates:SetResponse("Veyra Moo", "BIS") == true and #H.sent == 0)

	-- Removing a player from the running: they no longer show, and can be put back.
	Win:OpenRowMenu("Jonatan Moo")
	check("Remove from consideration is the last entry", Menu.rows[10].label:GetText() == "Remove from consideration")
	Menu.rows[10].scripts.OnClick(Menu.rows[10])
	check("the removed player is gone from the table", order() == "Veyra Moo,Tester Moo")
	Candidates:SetResponse("Jonatan Moo", "MINOR")
	check("and can be put back", order() == "Veyra Moo,Tester Moo,Jonatan Moo")

	-- Stopping the session: the loot master asks twice.
	check("the loot master sees Stop session", frame.stop:IsShown() and frame.stop.label:GetText() == "Stop session")
	H.deferTimers = true
	frame.stop.scripts.OnClick(frame.stop)
	check("the first click asks and stops nothing", Sessions:IsActive() and frame.stop.label:GetText() == "Sure?")
	H.runTimers()
	H.deferTimers = false
	check("it goes back after a while", Sessions:IsActive() and frame.stop.label:GetText() == "Stop session")
	H.deferTimers = true
	frame.stop.scripts.OnClick(frame.stop)
	frame.stop.scripts.OnClick(frame.stop)
	H.deferTimers = false
	H.runTimers()
	check("the second click stops the session", not Sessions:IsActive())
	check("and the window closes", not Win:IsShown())
	check("the button is reset for the next session", frame.stop.label:GetText() == "Stop session")
	check("start a new session for the rest", Sessions:Start(200) == true)
	sid = Sessions:GetActiveSid()
	ALC.Responses:Send("UPGRADE")
	Win:Show()

	-- Closing and the end of the session.
	frame.header.scripts.OnDragStop(frame.header)
	check("the position is saved", ALC.Settings:GetWindowPosition("council") ~= nil)
	Win:Hide()
	check("a closed window is remembered", ALC.Settings:GetWindowShown("council") == false)
	Win:Show()
	check("the window can be opened again", Win:IsShown() and ALC.Settings:GetWindowShown("council") == true)

	Sessions:Cancel("done")
	check("the window closes with the session", not Win:IsShown())
	check("votes are cleared", Voting:GetVotes("Jonatan Moo") == 0 and Voting:GetMyVote() == nil and ALC.Settings:GetSessionStore().votes == nil)

	----------------------------------------------------------------------------
	-- As a council member under somebody else
	----------------------------------------------------------------------------
	H.sent = {}
	units.party1 = { "Ashvane", "Moo", "MAGE" }
	units.party2 = { "Veyra", "Moo", "WARRIOR" }
	leader = "Ashvane Moo"
	Comm:InvalidateRoster()
	Council:Refresh()

	local council = { "Ashvane Moo", ME, "Veyra Moo" }
	Comm:Process(env("SESSION_START", "sidV", 1, { itemID = 200, itemString = "item:200", council = council, lm = "Ashvane Moo" }), "PARTY", "Ashvane Moo")
	check("the session started here, and the voting window opened", Sessions:GetActiveSid() == "sidV" and Win:IsShown())
	local names = { "Veyra Moo", "Kaelis Moo", "Jonatan Moo" }
	for i, name in ipairs(names) do
		Comm:Process(env("CANDIDATE_UPDATE", "sidV", 1 + i, { name = name, class = "WARRIOR", response = "UPGRADE", gear = {} }), "WHISPER", "Ashvane Moo")
	end

	local seq = 10
	check("a vote count from the loot master shows", Comm:Process(env("VOTE_UPDATE", "sidV", seq, { candidate = "Veyra Moo", votes = 2, voters = { "Ashvane Moo", "Kaelis Moo" } }), "WHISPER", "Ashvane Moo") == true
		and Voting:GetVotes("Veyra Moo") == 2 and Voting:GetMyVote() == nil)
	seq = seq + 1
	Comm:Process(env("VOTE_UPDATE", "sidV", seq, { candidate = "Jonatan Moo", votes = 1, voters = { ME } }), "WHISPER", "Ashvane Moo")
	check("our own vote is recognised from the loot master's list", Voting:GetMyVote() == "Jonatan Moo")
	seq = seq + 1
	Comm:Process(env("VOTE_UPDATE", "sidV", seq, { candidate = "Jonatan Moo", votes = 0, voters = {} }), "WHISPER", "Ashvane Moo")
	check("a count of zero removes the entry", Voting:GetVotes("Jonatan Moo") == 0 and Voting:GetMyVote() == nil)
	check("only the loot master sends counts", Comm:Process(env("VOTE_UPDATE", "sidV", seq + 1, { candidate = "Veyra Moo", votes = 0, voters = {} }), "WHISPER", "Veyra Moo") == false
		and Voting:GetVotes("Veyra Moo") == 2)

	H.sent = {}
	check("cast a vote", Voting:Cast("Kaelis Moo") == true)
	local _, castEnv = AceSerializer:Deserialize(H.sent[1].text)
	check("it goes to the loot master", H.sent[1].target == "Ashvane Moo" and castEnv.t == "VOTE" and castEnv.p.candidate == "Kaelis Moo")
	check("a vote goes in the fast lane", H.sent[1].prio == "ALERT")
	check("our own vote shows at once", Voting:GetVotes("Kaelis Moo") == 1 and Voting:GetMyVote() == "Kaelis Moo")
	check("a vote for another player moves it", Voting:Cast("Veyra Moo") == true and Voting:GetVotes("Kaelis Moo") == 0 and Voting:GetMyVote() == "Veyra Moo")
	check("the same player again takes it back", Voting:Cast("Veyra Moo") == true and Voting:GetMyVote() == nil)

	-- The window sorts by votes within an answer.
	check("more votes come first", Win:GetVisible()[1].name == "Veyra Moo")

	-- A council member who is not the loot master can only vote from the menu, and cannot stop.
	check("a council member's menu has only Vote", labels(Win:GetRowMenu("Veyra Moo")) == "Vote")
	check("and no Stop session button", not frame.stop:IsShown())
	local okSet, msgSet = Candidates:SetResponse("Veyra Moo", "BIS")
	check("only the loot master changes an answer", okSet == false and msgSet ~= nil and Candidates:Get("Veyra Moo").response == "UPGRADE")

	-- The history on a council member's side: what the loot master awards is logged here too, and an undo marks it.
	local log = ALC.Settings:GetAwardLog()
	local logBefore = #log
	H.deferTimers = true -- the session would otherwise finish at once, as the last item is awarded
	check("an award from the loot master is logged on the council side",
		Comm:Process(env("AWARD", "sidV", 30, { item = 1, winner = "Veyra Moo", itemID = 200, response = "UPGRADE" }), "PARTY", "Ashvane Moo") == true
		and #log == logBefore + 1 and log[#log].winner == "Veyra Moo" and log[#log].itemID == 200 and log[#log].sid == "sidV" and log[#log].votes == 2)
	Comm:Process(env("AWARD_REVOKE", "sidV", 31, { item = 1, winner = "Veyra Moo", itemID = 200 }), "PARTY", "Ashvane Moo")
	check("an undo marks the line as revoked", log[#log].revoked == true)
	H.runTimers()
	H.deferTimers = false
	table.remove(log) -- leave the log as the next tests expect it

	Comm:Process(env("SESSION_CANCEL", "sidV", 20, { reason = "done" }), "PARTY", "Ashvane Moo")

	-- Not on the council.
	H.sent = {}
	Comm:Process(env("SESSION_START", "sidW", 1, { itemID = 200, itemString = "item:200", council = { "Ashvane Moo", "Veyra Moo" }, lm = "Ashvane Moo" }), "PARTY", "Ashvane Moo")
	check("outside the council the window does not open", not Win:IsShown())
	local okNC, msgNC = Voting:Cast("Veyra Moo")
	check("and voting is refused", okNC == false and msgNC ~= nil and #H.sent == 0)
	Win:Show()
	check("and the window refuses to open", not Win:IsShown())
	Win:ShowHistory()
	Win:SetTab("council")
	check("the history is open to anybody, the voting tab is not", Win:IsShown() and Win:GetTab() == "history")
	Win:Hide()
	Comm:Process(env("VOTE_UPDATE", "sidW", 2, { candidate = "Veyra Moo", votes = 1, voters = { "Ashvane Moo" } }), "WHISPER", "Ashvane Moo")
	check("counts sent to a non-council member are ignored", Voting:GetVotes("Veyra Moo") == 0)
	Comm:Process(env("SESSION_CANCEL", "sidW", 3, { reason = "done" }), "PARTY", "Ashvane Moo")

	-- After a reload the snapshot restores the counts and our vote.
	H.clock = H.clock + 100
	Sessions:RequestState()
	local snap = { itemID = 200, itemString = "item:200", council = council, lm = "Ashvane Moo",
		candidates = { { name = "Veyra Moo", class = "WARRIOR", response = "BIS", gear = {} } },
		votes = { { candidate = "Veyra Moo", voters = { "Ashvane Moo", ME } } }, yourVote = "Veyra Moo" }
	Comm:Process(env("STATE_SNAPSHOT", "sidS", 1, snap), "WHISPER", "Ashvane Moo")
	check("the counts and our vote are restored", Voting:GetVotes("Veyra Moo") == 2 and Voting:GetMyVote() == "Veyra Moo")
	Comm:Process(env("SESSION_CANCEL", "sidS", 2, { reason = "done" }), "PARTY", "Ashvane Moo")

	-- A long list scrolls.
	H.sent = {}
	Comm:Process(env("SESSION_START", "sidL", 1, { itemID = 200, itemString = "item:200", council = council, lm = "Ashvane Moo" }), "PARTY", "Ashvane Moo")
	for i = 1, 12 do
		local name = string.format("Player%02d Moo", i)
		Comm:Process(env("CANDIDATE_UPDATE", "sidL", 1 + i, { name = name, class = "MAGE", response = "UPGRADE", gear = {} }), "WHISPER", "Ashvane Moo")
	end
	check("ten rows show at most", rows[10]:IsShown() and #Win:GetVisible() == 12)
	check("a long list has a scrollbar", frame.scroll:IsShown() == true)
	local scrollBar = frame.scroll
	H.cursor = { 0, scrollBar:GetTop() - scrollBar:GetHeight() }
	scrollBar.scripts.OnMouseDown(scrollBar)
	scrollBar.scripts.OnMouseUp(scrollBar)
	check("the scrollbar jumps to the end", rows[10].candidate == Win:GetVisible()[12].name)
	H.cursor = { 0, scrollBar:GetTop() + 50 }
	scrollBar.scripts.OnMouseDown(scrollBar)
	scrollBar.scripts.OnMouseUp(scrollBar)
	check("and back to the top", rows[1].candidate == Win:GetVisible()[1].name)
	local firstName = rows[1].candidate
	frame.scripts.OnMouseWheel(frame, -1)
	check("scrolling moves the list", rows[1].candidate ~= firstName and rows[1].candidate == Win:GetVisible()[2].name)
	for _ = 1, 10 do frame.scripts.OnMouseWheel(frame, -1) end
	check("scrolling stops at the end", rows[10].candidate == Win:GetVisible()[12].name)
	Comm:Process(env("SESSION_CANCEL", "sidL", 20, { reason = "done" }), "PARTY", "Ashvane Moo")

	-- Put the environment back for the following tests.
	ALC.Events.UnregisterAll(listener)
	UnitName, UnitClass = realUnitName, realUnitClass
	UnitIsConnected = function() return true end
	H.inGroup = false
	C_Item.GetItemInfo = function() end
	C_Item.GetItemInfoInstant = nil
	C_Item.RequestLoadItemDataByID = nil
	Council.GetLeaderName = function() return nil end
	Comm:InvalidateRoster()
	ALC.LootDetection:Clear()
end

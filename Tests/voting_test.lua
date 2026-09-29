-- Voting and the council window, on the real modules.
-- Runs before the Comm tests, which replace Council and Sessions with stand-ins.

return function(check, H)
	local Voting, Candidates, Sessions, Council, Comm, Win = ALC.Voting, ALC.Candidates, ALC.Sessions, ALC.Council, ALC.Comm, ALC.CouncilWindow
	local AceSerializer = LibStub("AceSerializer-3.0")
	local ME = "Tester Moo"

	local function env(t, sid, seq, p) return { v = 1, t = t, sid = sid, seq = seq, p = p } end

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
	check("a council member gets the votes and their own vote", votesByName["Jonatan Moo"] == 1 and votesByName["Veyra Moo"] == 1 and councilSnap.p.yourVote == "Veyra Moo")
	H.sent = {}
	H.clock = H.clock + 100
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Jonatan Moo")
	local _, raiderSnap = AceSerializer:Deserialize(H.sent[1].text)
	check("a raider gets no votes", raiderSnap.p.votes == nil and raiderSnap.p.yourVote == nil)

	----------------------------------------------------------------------------
	-- The council window
	----------------------------------------------------------------------------
	local rows = Win.rows
	Win:Hide()
	Win:Show()
	local frame = rows[1].parent
	check("the window is open", Win:IsShown() and #rows == 10)
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
	check("and we do not count it ourselves", Voting:GetVotes("Kaelis Moo") == 0 and Voting:GetMyVote() == nil)

	-- The window sorts by votes within an answer.
	check("more votes come first", Win:GetVisible()[1].name == "Veyra Moo")

	Comm:Process(env("SESSION_CANCEL", "sidV", 20, { reason = "done" }), "PARTY", "Ashvane Moo")

	-- Not on the council.
	H.sent = {}
	Comm:Process(env("SESSION_START", "sidW", 1, { itemID = 200, itemString = "item:200", council = { "Ashvane Moo", "Veyra Moo" }, lm = "Ashvane Moo" }), "PARTY", "Ashvane Moo")
	check("outside the council the window does not open", not Win:IsShown())
	local okNC, msgNC = Voting:Cast("Veyra Moo")
	check("and voting is refused", okNC == false and msgNC ~= nil and #H.sent == 0)
	Win:Show()
	check("and the window refuses to open", not Win:IsShown())
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
	local firstName = rows[1].candidate
	frame.scripts.OnMouseWheel(frame, -1)
	check("scrolling moves the list", rows[1].candidate ~= firstName and rows[1].candidate == Win:GetVisible()[2].name)
	for _ = 1, 10 do frame.scripts.OnMouseWheel(frame, -1) end
	check("scrolling stops at the end", rows[10].candidate == Win:GetVisible()[12].name)
	Comm:Process(env("SESSION_CANCEL", "sidL", 20, { reason = "done" }), "PARTY", "Ashvane Moo")

	-- Put the environment back for the following tests.
	ALC.Events.UnregisterAll(listener)
	UnitName, UnitClass = realUnitName, realUnitClass
	UnitIsConnected = nil
	H.inGroup = false
	C_Item.GetItemInfo = function() end
	C_Item.GetItemInfoInstant = nil
	C_Item.RequestLoadItemDataByID = nil
	Council.GetLeaderName = function() return nil end
	Comm:InvalidateRoster()
	ALC.LootDetection:Clear()
end

-- Council, Sessions and test mode, on the real modules (Comm loops our messages back).
-- Runs before the Comm tests, which replace Council and Sessions with stand-ins.

return function(check, H)
	local Council, Sessions, Comm = ALC.Council, ALC.Sessions, ALC.Comm
	local AceSerializer = LibStub("AceSerializer-3.0")

	local ME = "Tester Moo"
	local started, ended, builds, applied = {}, {}, {}, {}
	local listener = {}
	ALC.Events.Register(listener, "ALC_SESSION_STARTED", function(_, s, restored) started[#started + 1] = { s = s, restored = restored } end)
	ALC.Events.Register(listener, "ALC_SESSION_ENDED", function(_, sid, reason) ended[#ended + 1] = { sid = sid, reason = reason } end)
	ALC.Events.Register(listener, "ALC_SESSION_SNAPSHOT_BUILD", function(_, payload, requester, isCouncil)
		builds[#builds + 1] = requester
		if isCouncil then payload.candidates = {} end -- what the Candidates module will do
	end)
	ALC.Events.Register(listener, "ALC_SESSION_SNAPSHOT", function(_, p) applied[#applied + 1] = p end)

	local function env(t, sid, seq, p) return { v = 1, t = t, sid = sid, seq = seq, p = p } end

	-- A fake group: who is in it, who leads, and the loot method.
	local units = {}
	local realUnitName, realIsInGroup = UnitName, IsInGroup
	local group = { method = "group", partyMaster = nil, raidMaster = nil, leader = nil }
	local function setGroup(members, leader, method, partyMaster)
		units = {}
		for i, full in ipairs(members) do
			local first, last = full:match("^(%S+) (%S+)$")
			units["party" .. i] = { first, last }
		end
		H.inGroup = #members > 0
		group.leader, group.method, group.partyMaster = leader, method or "group", partyMaster
		Comm.GetGroupNames = function()
			local names = { ME }
			for _, m in ipairs(members) do names[#names + 1] = m end
			return names
		end
		Comm:InvalidateRoster()
	end
	UnitName = function(unit)
		if unit == "player" then return "Tester", "Moo" end
		local u = units[unit]
		if u then return u[1], u[2] end
	end
	Council.GetLootMethodInfo = function() return group.method, group.partyMaster, group.raidMaster end
	Council.GetLeaderName = function() return group.leader end

	local function reset()
		if Sessions:IsActive() then Sessions:Cancel("test reset") end
		started, ended, builds, applied = {}, {}, {}, {}
		H.sent = {}
	end

	----------------------------------------------------------------------------
	-- Council: loot master
	----------------------------------------------------------------------------
	setGroup({}, nil)
	check("solo: you are your own loot master", Council:GetLootMaster() == ME and Council:AmLootMaster())
	check("solo: others are not", Council:IsLootMaster("Veyra Moo") == false)

	setGroup({ "Ashvane Moo", "Veyra Moo" }, "Ashvane Moo", "group")
	check("group loot: the leader is the loot master", Council:GetLootMaster() == "Ashvane Moo")
	check("IsLootMaster ignores case and realm", Council:IsLootMaster("ashvane moo-Realm"))
	check("you are not the loot master then", Council:AmLootMaster() == false)

	setGroup({ "Ashvane Moo", "Veyra Moo" }, "Ashvane Moo", "master", 2)
	check("master loot: the master looter, not the leader", Council:GetLootMaster() == "Veyra Moo")
	setGroup({ "Ashvane Moo" }, "Ashvane Moo", "master", 0)
	check("master loot: partyMaster 0 is you", Council:AmLootMaster())
	setGroup({ "Ashvane Moo" }, "Ashvane Moo", "master", 4)
	check("master looter not found: falls back to the leader", Council:GetLootMaster() == "Ashvane Moo")

	-- The newer client returns the loot method as a number: 2 = master, 3 = group.
	local realMethodInfo = Council.GetLootMethodInfo
	Council.GetLootMethodInfo = function() return 3 end
	setGroup({ "Ashvane Moo" }, "Ashvane Moo", "group")
	check("numeric group loot: the leader", Council:GetLootMaster() == "Ashvane Moo")
	Council.GetLootMethodInfo = function() return 2 end
	Council.IsPlayerMasterLooter = function() return true end
	check("numeric master loot and the game says it is you", Council:GetLootMaster() == ME)
	Council.IsPlayerMasterLooter = function() return false end
	Council.FindRosterMasterLooter = function() return 2, "Veyra" end
	setGroup({ "Ashvane Moo", "Veyra Moo" }, "Ashvane Moo", "group")
	check("master looter found through the roster flag in a party", Council:GetLootMaster() == "Veyra Moo")
	H.inRaid = true
	units = { raid2 = { "Jonatan", "Moo" } }
	Council.FindRosterMasterLooter = function() return 2, "Jonatan" end
	check("master looter found through the roster flag in a raid", Council:GetLootMaster() == "Jonatan Moo")
	H.inRaid = false
	Council.FindRosterMasterLooter = function() return nil end
	Council.GetLootMethodInfo = realMethodInfo

	-- A leader function that returns no value at all must not break the diagnostics.
	setGroup({}, nil)
	local realLeader = Council.GetLeaderName
	Council.GetLeaderName = function() end
	H.slash("debug lm")
	check("debug lm survives a missing leader", true)
	Council.GetLeaderName = realLeader
	Council.GetLeaderName = function() return group.leader end

	-- Loot master change is announced (not on the first resolve).
	local changes = {}
	ALC.Events.Register(listener, "ALC_COUNCIL_LM_CHANGED", function(_, new, old) changes[#changes + 1] = { new, old } end)
	setGroup({ "Ashvane Moo", "Veyra Moo" }, "Ashvane Moo", "group")
	Council:Refresh()
	setGroup({ "Ashvane Moo", "Veyra Moo" }, "Veyra Moo", "group")
	Council:Refresh()
	check("loot master change fires an event", #changes >= 1 and changes[#changes][1] == "Veyra Moo" and changes[#changes][2] == "Ashvane Moo")
	Council:Refresh()
	local n = #changes
	Council:Refresh()
	check("no event when nothing changed", #changes == n)

	----------------------------------------------------------------------------
	-- Council list
	----------------------------------------------------------------------------
	ALC.Settings:GetDB().profile.council = {}
	ALC.Settings:AddCouncilMember("Veyra Moo")
	ALC.Settings:AddCouncilMember("tester moo")
	check("IsCouncil reads settings without a session", Council:IsCouncil("veyra moo") and not Council:IsCouncil("Jonatan Moo"))
	local list = Council:BuildSessionList(ME)
	check("session list: loot master first, no duplicates", list[1] == ME and #list == 2 and list[2] == "Veyra Moo")

	----------------------------------------------------------------------------
	-- Starting and cancelling as loot master (solo)
	----------------------------------------------------------------------------
	setGroup({}, nil)
	reset()
	local ok, msg = Sessions:Start("garbage")
	check("invalid item refused", ok == false and msg ~= nil and not Sessions:IsActive())
	ok = Sessions:Start(19019)
	check("start by item id", ok == true and Sessions:IsActive())
	local s = Sessions:GetSession()
	check("session state", s.itemID == 19019 and s.itemString == "item:19019" and s.lm == ME and s.isLM and s.isCouncil and not s.restored)
	check("council in the session", #s.council == 2 and s.council[1] == ME and s.council[2] == "Veyra Moo")
	check("started event fired once", #started == 1 and started[1].s.sid == s.sid and started[1].restored == false)
	check("GetActiveSid", Sessions:GetActiveSid() == s.sid)
	check("IsCouncil now follows the session list", Council:IsCouncil("Veyra Moo") and Council:IsCouncil(ME))

	s.council[1] = "Mutated"
	check("GetSession returns a copy", Sessions:GetSession().council[1] == ME)

	local ok2, msg2 = Sessions:Start(19019)
	check("second start refused while active", ok2 == false and msg2 ~= nil and #started == 1)

	local firstSid = s.sid
	check("cancel", Sessions:Cancel("changed my mind") == true and not Sessions:IsActive())
	check("ended event carries the reason", #ended == 1 and ended[1].sid == firstSid and ended[1].reason == "changed my mind")
	check("cancel without a session refused", Sessions:Cancel() == false)

	-- Two sessions in a row: nothing from the first leaks into the second.
	check("start again", Sessions:Start("|cffa335ee|Hitem:19019::::::::80::::::::|h[Thunderfury]|h|r") == true)
	local second = Sessions:GetSession()
	check("item link parsed to an itemString", second.itemString == "item:19019::::::::80" and second.itemID == 19019)
	check("new session id", second.sid ~= firstSid)
	local before = #started
	check("stale message for the old session is rejected",
		Comm:Process(env("RESPONSE", firstSid, nil, { response = "BIS", gear = {} }), "WHISPER", ME) == false)
	check("old session id does not resurrect anything", Sessions:GetActiveSid() == second.sid and #started == before)
	Sessions:Cancel("done")

	-- An AWARD ends the session.
	Sessions:Start(19019)
	check("AWARD from the loot master accepted", Comm:SendRaid("AWARD", Sessions:GetActiveSid(), { winner = "Veyra Moo", itemID = 19019, response = "BIS" }) == true)
	check("the session ended on AWARD", not Sessions:IsActive() and ended[#ended].reason == "awarded")

	----------------------------------------------------------------------------
	-- Not the loot master
	----------------------------------------------------------------------------
	reset()
	setGroup({ "Ashvane Moo", "Veyra Moo" }, "Ashvane Moo", "master", 1)
	Council:Refresh() -- in the game the roster and loot method events do this
	local okNo, msgNo = Sessions:Start(19019)
	check("only the loot master can start", okNo == false and msgNo ~= nil and not Sessions:IsActive())
	check("nothing was sent", #H.sent == 0)

	-- Client side: the loot master's SESSION_START creates the session.
	local council = { "Ashvane Moo", "Veyra Moo", ME }
	local startPayload = { itemID = 19019, itemString = "item:19019:0", council = council, lm = "Ashvane Moo" }
	check("SESSION_START from the loot master starts a session",
		Comm:Process(env("SESSION_START", "sidA", 1, startPayload), "PARTY", "Ashvane Moo") == true and Sessions:GetActiveSid() == "sidA")
	local cs = Sessions:GetSession()
	check("client session: not loot master, on the council", cs.isLM == false and cs.isCouncil == true and cs.lm == "Ashvane Moo")
	check("client cannot cancel", select(1, Sessions:Cancel()) == false)
	check("session council is used for IsCouncil", Council:IsCouncil("Ashvane Moo") and not Council:IsCouncil("Jonatan Moo"))

	-- Only the loot master serves snapshots; a client must never hand out council data.
	H.sent = {}
	H.clock = H.clock + 100
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Veyra Moo")
	check("a client with a session does not answer state requests", #H.sent == 0)

	-- A new SESSION_START from the loot master supersedes the old session.
	check("a newer session supersedes",
		Comm:Process(env("SESSION_START", "sidB", 1, startPayload), "PARTY", "Ashvane Moo") == true
		and Sessions:GetActiveSid() == "sidB" and ended[#ended].reason == "superseded")

	check("SESSION_CANCEL ends it", Comm:Process(env("SESSION_CANCEL", "sidB", 2, { reason = "loot master cancelled" }), "PARTY", "Ashvane Moo") == true
		and not Sessions:IsActive() and ended[#ended].reason == "loot master cancelled")

	-- Loot master change ends the session locally.
	Comm:Process(env("SESSION_START", "sidC", 1, startPayload), "PARTY", "Ashvane Moo")
	check("session active before the change", Sessions:GetActiveSid() == "sidC")
	setGroup({ "Ashvane Moo", "Veyra Moo" }, "Ashvane Moo", "master", 2)
	Council:Refresh()
	check("loot master change ends the session", not Sessions:IsActive() and ended[#ended].reason == "loot master changed")

	----------------------------------------------------------------------------
	-- Recovery: a client asks the loot master for a snapshot
	----------------------------------------------------------------------------
	reset()
	setGroup({ "Ashvane Moo", "Veyra Moo" }, "Ashvane Moo", "master", 1)
	H.clock = H.clock + 100
	local snapPayload = { itemID = 19019, itemString = "item:19019:0", council = council, lm = "Ashvane Moo", yourResponse = "PASS" }
	check("unrequested snapshot is ignored",
		Comm:Process(env("STATE_SNAPSHOT", "sidS0", 1, snapPayload), "WHISPER", "Ashvane Moo") == true and not Sessions:IsActive())
	H.sent = {}
	check("request state", Sessions:RequestState() == true)
	local _, req = AceSerializer:Deserialize(H.sent[1].text)
	check("STATE_REQUEST whispered to the loot master without a sid",
		#H.sent == 1 and H.sent[1].dist == "WHISPER" and H.sent[1].target == "Ashvane Moo" and req.t == "STATE_REQUEST" and req.sid == nil)
	check("requested snapshot restores the session",
		Comm:Process(env("STATE_SNAPSHOT", "sidS1", 5, snapPayload), "WHISPER", "Ashvane Moo") == true and Sessions:GetActiveSid() == "sidS1")
	check("restored flag and events", Sessions:GetSession().restored == true and started[#started].restored == true and #applied == 1 and applied[1].yourResponse == "PASS")
	check("no second request while a session is active", Sessions:RequestState() == false)
	Comm:Process(env("SESSION_CANCEL", "sidS1", 6, { reason = "done" }), "PARTY", "Ashvane Moo")
	check("cancel after restore works (seq continues)", not Sessions:IsActive())

	check("a snapshot is accepted only once per request",
		(function()
			Comm:Process(env("STATE_SNAPSHOT", "sidS2", 7, snapPayload), "WHISPER", "Ashvane Moo")
			return not Sessions:IsActive()
		end)())

	check("nothing to request when you are the loot master", (function()
		setGroup({ "Veyra Moo" }, ME, "master", 0)
		return Sessions:RequestState() == false
	end)())

	----------------------------------------------------------------------------
	-- Recovery: the loot master answers a request
	----------------------------------------------------------------------------
	reset()
	setGroup({ "Veyra Moo", "Jonatan Moo" }, ME, "master", 0)
	Sessions:Start(19019)
	local sid = Sessions:GetActiveSid()
	H.sent = {}
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Veyra Moo")
	check("the loot master answers with a snapshot", #H.sent == 1 and H.sent[1].target == "Veyra Moo")
	local _, snap = AceSerializer:Deserialize(H.sent[1].text)
	check("snapshot envelope", snap.t == "STATE_SNAPSHOT" and snap.sid == sid and snap.seq ~= nil)
	check("snapshot carries the session", snap.p.itemID == 19019 and snap.p.lm == ME and #snap.p.council == 2)
	check("council member gets the council-only fields", snap.p.candidates ~= nil and builds[#builds] == "Veyra Moo")

	H.sent = {}
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Jonatan Moo")
	local _, raiderSnap = AceSerializer:Deserialize(H.sent[1].text)
	check("a raider gets no council-only fields", raiderSnap.p.candidates == nil)

	H.sent = {}
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Jonatan Moo")
	check("repeated requests are throttled", #H.sent == 0)
	H.clock = H.clock + 10
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Jonatan Moo")
	check("answered again after the cooldown", #H.sent == 1)

	H.sent = {}
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Stranger Moo")
	check("a stranger gets nothing", #H.sent == 0)
	Sessions:Cancel("done")
	H.sent = {}
	H.clock = H.clock + 10
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Veyra Moo")
	check("no snapshot without a session", #H.sent == 0)

	----------------------------------------------------------------------------
	-- Test mode
	----------------------------------------------------------------------------
	reset()
	setGroup({}, nil)
	local realGetItemInfo = C_Item.GetItemInfo
	local qualities = { ["item:100"] = 1, ["item:200"] = 4, ["item:300"] = 3 }
	C_Item.GetItemInfo = function(link) local q = qualities[link:match("(item:%d+)")]; return "Name", link, q end
	ALC.TestMode.GetBagItemLinks = function() return { "|Hitem:100|h[a]|h", "|Hitem:200|h[b]|h", "|Hitem:300|h[c]|h" } end
	check("test mode picks the best item", ALC.TestMode:PickItem():find("item:200", 1, true) ~= nil)
	local okT = ALC.TestMode:Start()
	check("test mode starts a session", okT == true and Sessions:IsActive() and Sessions:GetSession().itemID == 200)
	Sessions:Cancel("done")

	ALC.TestMode.GetBagItemLinks = function() return {} end
	local okE, msgE = ALC.TestMode:Start()
	check("empty bags: nothing to test with", okE == false and msgE ~= nil and not Sessions:IsActive())

	setGroup({ "Veyra Moo" }, ME, "group")
	ALC.TestMode.GetBagItemLinks = function() return { "|Hitem:200|h[b]|h" } end
	local okG = ALC.TestMode:Start()
	check("test mode refuses inside a group", okG == false and not Sessions:IsActive())

	-- Slash commands.
	setGroup({}, nil)
	H.slash("start 19019")
	check("/alc start", Sessions:IsActive())
	local chat = #H.chat
	H.slash("status")
	check("/alc status prints", #H.chat == chat + 1)
	H.slash("cancel")
	check("/alc cancel", not Sessions:IsActive())
	H.slash("test")
	C_Item.GetItemInfo = realGetItemInfo
	ALC.TestMode.GetBagItemLinks = function() return {} end
	H.slash("cancel")
	H.slash("debug lm")
	H.slash("debug help")

	-- Put the environment back for the following tests.
	UnitName, IsInGroup = realUnitName, realIsInGroup
	H.inGroup = false
	setGroup({}, nil)
	Sessions:Cancel("cleanup")
end

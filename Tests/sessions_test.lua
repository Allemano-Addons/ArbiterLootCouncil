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

	local env = H.env

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

	-- The roster reports "First Last" (as seen on Forever): matched against the party.
	setGroup({ "Ashvane Moo", "Veyra Moo" }, "Ashvane Moo", "group")
	Council.GetLootMethodInfo = function() return 2 end
	Council.FindRosterMasterLooter = function() return 3, "Veyra Moo" end
	check("roster name with a surname finds the party unit", Council:GetLootMaster() == "Veyra Moo")
	Council.FindRosterMasterLooter = function() return nil end
	Council.GetLootMethodInfo = realMethodInfo

	-- Council names are stored as "First Last".
	ALC.Settings:GetDB().profile.council = {}
	check("lower case name is stored capitalized", ALC.Settings:AddCouncilMember("allemano moo") == true and ALC.Settings:GetCouncil()[1] == "Allemano Moo")
	check("the same name in another case is a duplicate", ALC.Settings:AddCouncilMember("ALLEMANO MOO") == false)
	check("removal ignores case", ALC.Settings:RemoveCouncilMember("allemano moo") == true and #ALC.Settings:GetCouncil() == 0)

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
	check("session state", #s.items == 1 and s.items[1].itemID == 19019 and s.items[1].itemString == "item:19019" and s.lm == ME and s.isLM and s.isCouncil and not s.restored)
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
	check("item link parsed to an itemString", second.items[1].itemString == "item:19019::::::::80" and second.items[1].itemID == 19019)
	check("new session id", second.sid ~= firstSid)
	local before = #started
	check("stale message for the old session is rejected",
		Comm:Process(env("RESPONSE", firstSid, nil, { response = "BIS", gear = {} }), "WHISPER", ME) == false)
	check("old session id does not resurrect anything", Sessions:GetActiveSid() == second.sid and #started == before)
	Sessions:Cancel("done")

	-- An AWARD ends the session.
	Sessions:Start(19019)
	check("AWARD from the loot master accepted", Comm:SendRaid("AWARD", Sessions:GetActiveSid(), { item = 1, winner = "Veyra Moo", itemID = 19019, response = "BIS" }) == true)
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
	check("restored flag and events", Sessions:GetSession().restored == true and started[#started].restored == true and #applied == 1 and applied[1].yourResponses[1].response == "PASS")
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
	check("snapshot carries the session", snap.p.items[1].itemID == 19019 and snap.p.lm == ME and #snap.p.council == 2)
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
	check("test mode starts a session", okT == true and Sessions:IsActive() and Sessions:GetSession().items[1].itemID == 200)
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

	----------------------------------------------------------------------------
	-- Options for an addon that builds on ALC (Soft Reserve): a mode and data per item
	----------------------------------------------------------------------------
	setGroup({ "Veyra Moo", "Jonatan Moo" }, ME, "master", 0)
	reset()
	check("a normal session has no mode and no extra", Sessions:Start(19019) == true and Sessions:GetSession().mode == nil and Sessions:GetSession().items[1].extra == nil)
	Sessions:Cancel("plain")

	local srResponses = {
		{ id = "MS", label = "MS", color = "4caf50" },
		{ id = "OS", label = "OS", color = "ffb300" },
		{ id = "PASS", label = "Pass", color = "888888" },
	}
	local okSR, sidSR = Sessions:StartItems({ 19019, 200 }, {
		mode = "SR", modeName = "Soft Reserve", modeColor = "9B7BFF",
		responses = srResponses,
		rolls = false,
		extra = { [1] = { sr = { "Veyra Moo", "Kaelis Moo" }, note = "tier token", reserved = true, copies = 2 } },
	})
	check("a session starts with options", okSR == true and Sessions:IsActive())
	local sr = Sessions:GetSession()
	check("the mode is kept", sr.mode == "SR")
	check("and its name and colour", sr.modeName == "Soft Reserve" and sr.modeColor == "9B7BFF")
	local brandName, brandColor = ALC.UI.SessionBrand(sr)
	check("the windows can read the brand", brandName == "Soft Reserve" and math.abs(brandColor[1] - 0x9B / 255) < 0.001)
	check("a normal session has no brand", ALC.UI.SessionBrand({ mode = "SR" }) == nil and ALC.UI.SessionBrand(nil) == nil)
	local logo = ALC.UI.NewLogo(CreateFrame("Frame"), 22)
	check("a logo has a hidden second texture for the accent part", logo.accent ~= nil and not logo.accent:IsShown())
	ALC.UI.ApplyBrand(logo, sr)
	check("a branded session tints only that part (the mark itself stays white)", logo.accent:IsShown())
	ALC.UI.ApplyBrand(logo, { mode = "SR" })
	check("a normal session hides it again", not logo.accent:IsShown())
	check("the data travels with the item", sr.items[1].extra.sr[2] == "Kaelis Moo" and sr.items[1].extra.note == "tier token"
		and sr.items[1].extra.reserved == true and sr.items[1].extra.copies == 2)
	check("an item without data has none", sr.items[2].extra == nil)
	check("the answer buttons are the ones given", #sr.responses == 3 and sr.responses[1].id == "MS" and sr.responses[3].id == "PASS")
	check("rolls can be turned off for the session", sr.rolls == false)
	sr.items[1].extra.sr[1] = "Mutated"
	check("GetSession hands out a copy of the data", Sessions:GetSession().items[1].extra.sr[1] == "Veyra Moo")

	-- the snapshot brings mode and data to a player who reloads
	H.sent = {}
	H.clock = H.clock + 100
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Veyra Moo")
	local _, srSnap = AceSerializer:Deserialize(H.sent[1].text)
	check("the snapshot carries the mode", srSnap.p.mode == "SR" and srSnap.p.modeName == "Soft Reserve" and srSnap.p.modeColor == "9B7BFF")
	check("and the data of the items", srSnap.p.items[1].extra.sr[1] == "Veyra Moo" and srSnap.p.items[2].extra == nil)

	-- the loot master's own saved session keeps them over a /reload
	local saved = ALC.Settings:GetSessionStore().session
	check("the saved session keeps the mode and the data", saved and saved.mode == "SR" and saved.modeName == "Soft Reserve" and saved.modeColor == "9B7BFF" and saved.items[1].extra.copies == 2)
	Sessions:Cancel("sr done")
	check("a bad colour is refused before anything is sent", (Sessions:StartItems({ 19019 }, { mode = "SR", modeName = "Soft Reserve", modeColor = "purple" })) == false and not Sessions:IsActive())
	check("so is a name with strange characters", (Sessions:StartItems({ 19019 }, { mode = "SR", modeName = "Soft|cffff0000 Reserve", modeColor = "9B7BFF" })) == false)

	-- a player's client builds the same session from the loot master's message
	reset()
	setGroup({ "Ashvane Moo", "Veyra Moo" }, "Ashvane Moo", "master", 1)
	Council:Refresh()
	local startSR = {
		items = { { itemID = 19019, itemString = "item:19019:0", extra = { sr = { ME }, reserved = true } }, { itemID = 200, itemString = "item:200:0" } },
		council = { "Ashvane Moo", "Veyra Moo" }, lm = "Ashvane Moo", mode = "SR", responses = srResponses,
	}
	check("a player accepts a session with a mode and data",
		Comm:Process(env("SESSION_START", "sidSR", 1, startSR), "PARTY", "Ashvane Moo") == true and Sessions:GetActiveSid() == "sidSR")
	local cl = Sessions:GetSession()
	check("and sees them", cl.mode == "SR" and cl.items[1].extra.sr[1] == ME and cl.items[1].extra.reserved == true)
	Sessions:Cancel("x")
	Comm:Process(env("SESSION_CANCEL", "sidSR", 2, { reason = "done" }), "PARTY", "Ashvane Moo")
	reset()

	-- What is refused: the loot master's own check and every player's check are the same one
	setGroup({}, nil)
	H.sent = {}
	local function refused(options) local ok, why = Sessions:StartItems({ 19019 }, options) return ok == false and why ~= nil and not Sessions:IsActive() end
	check("a mode with a pipe is refused", refused({ mode = "S|R" }))
	check("a mode that is too long is refused", refused({ mode = string.rep("A", 17) }))
	check("data that is not a table is refused", refused({ extra = { [1] = "text" } }))
	check("too many keys are refused", refused({ extra = { [1] = { a = 1, b = 1, c = 1, d = 1, e = 1, f = 1, g = 1, h = 1, i = 1 } } }))
	check("a key with strange characters is refused", refused({ extra = { [1] = { ["a b"] = 1 } } }))
	check("a text with an escape code is refused", refused({ extra = { [1] = { note = "|cffff0000red|r" } } }))
	check("a nested table is refused", refused({ extra = { [1] = { sr = { { "deep" } } } } }))
	check("a function is refused", refused({ extra = { [1] = { x = print } } }))
	check("too long a list is refused", (function()
		local names = {}
		for i = 1, 41 do names[i] = "Player" .. i end
		return refused({ extra = { [1] = { sr = names } } })
	end)())
	check("answers without PASS last are refused", refused({ responses = { { id = "PASS", label = "Pass", color = "888888" }, { id = "MS", label = "MS", color = "4caf50" } } }))
	check("nothing was sent for any of them", #H.sent == 0)

	-- A normal session is unchanged by all this
	check("a normal session still starts", Sessions:Start(19019) == true)
	Sessions:Cancel("end")

	-- Put the environment back for the following tests.
	ALC.Events.UnregisterAll(listener)
	UnitName, IsInGroup = realUnitName, realIsInGroup
	H.inGroup = false
	setGroup({}, nil)
	Sessions:Cancel("cleanup")
end

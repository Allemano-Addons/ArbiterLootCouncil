-- Comm and Protocol tests. Runs after the core tests, on the same loaded addon.

return function(check, H)
	local Comm, Protocol = ALC.Comm, ALC.Protocol
	local AceSerializer = LibStub("AceSerializer-3.0")

	-- Stand-ins for the Council and Sessions modules (built in later steps).
	local lmName, activeSid = "Ashvane", "sid1"
	local council = { ashvane = true, veyra = true, ["allemano moo"] = true }
	ALC.Council = {
		IsLootMaster = function(_, name) return ALC:SameName(name, lmName) end,
		IsCouncil = function(_, name) return council[string.lower(ALC:NormalizeName(name) or "")] == true end,
	}
	ALC.Sessions = { GetActiveSid = function() return activeSid end }

	local group = { "Tester Moo", "Ashvane", "Veyra", "Jonatan", "Allemano Moo" }
	Comm.GetGroupNames = function() return group end
	Comm:InvalidateRoster()

	-- Count accepted messages per type.
	local accepted, last = {}, {}
	for t in pairs(Protocol.specs) do
		ALC.Events.Register({}, "ALC_COMM_" .. t, function(_, sender, sid, p, seq, dist)
			accepted[t] = (accepted[t] or 0) + 1
			last[t] = { sender = sender, sid = sid, p = p, seq = seq, dist = dist }
		end)
	end
	local function total() local n = 0 for _, c in pairs(accepted) do n = n + c end return n end

	local function env(t, sid, seq, p) return { v = 1, t = t, sid = sid, seq = seq, p = p } end
	local function start()
		return { itemID = 19019, itemString = "item:19019:0:0:0:0:0:0:0", council = { "Ashvane", "Veyra" }, lm = "Ashvane" }
	end
	local function candidate()
		return { name = "Jonatan", class = "WARRIOR", response = "UPGRADE", gear = { "item:12345:0:0:0" } }
	end
	local function warnCount(pattern)
		local n = 0
		for _, e in ipairs(ALC.Debug:GetLines()) do
			if e.lvl == "warn" and e.msg:find(pattern, 1, true) then n = n + 1 end
		end
		return n
	end

	-- Every case below must be rejected: no event, and no state change.
	local function rejects(label, e, dist, sender)
		local before = total()
		local ok = Comm:Process(e, dist, sender)
		check("rejects: " .. label, ok == false and total() == before)
	end

	----------------------------------------------------------------------------
	-- Step 1-2: envelope and type
	----------------------------------------------------------------------------
	rejects("non-table envelope", "junk", "RAID", "Ashvane")
	rejects("missing payload", { v = 1, t = "SESSION_START", sid = "s", seq = 1 }, "RAID", "Ashvane")
	rejects("wrong protocol version", { v = 2, t = "SESSION_START", sid = "s", seq = 1, p = start() }, "RAID", "Ashvane")
	rejects("wrong protocol version again", { v = 2, t = "SESSION_START", sid = "s", seq = 2, p = start() }, "RAID", "Ashvane")
	check("incompatible version logged once per sender", warnCount("incompatible protocol v2") == 1)
	check("incompatible version recorded", Comm:GetVersions()["ashvane"].proto == 2)
	rejects("unknown type", env("HACK", nil, nil, {}), "RAID", "Ashvane")
	rejects("no sender", env("VERSION_REQUEST", nil, nil, {}), "RAID", nil)

	----------------------------------------------------------------------------
	-- Step 3: sender and channel
	----------------------------------------------------------------------------
	rejects("SESSION_START from a non-LM", env("SESSION_START", "sid1", 1, start()), "RAID", "Veyra")
	rejects("SESSION_START from outside the group", env("SESSION_START", "sid1", 1, start()), "RAID", "Stranger")
	rejects("SESSION_START over whisper", env("SESSION_START", "sid1", 1, start()), "WHISPER", "Ashvane")
	rejects("RESPONSE over raid channel", env("RESPONSE", "sid1", nil, { response = "BIS", gear = {} }), "RAID", "Jonatan")
	rejects("RESPONSE from a non-member", env("RESPONSE", "sid1", nil, { response = "BIS", gear = {} }), "WHISPER", "Stranger")
	rejects("VOTE from a non-council member", env("VOTE", "sid1", nil, { candidate = "Jonatan" }), "WHISPER", "Jonatan")

	----------------------------------------------------------------------------
	-- Step 4: session id
	----------------------------------------------------------------------------
	rejects("RESPONSE with wrong sid", env("RESPONSE", "other", nil, { response = "BIS", gear = {} }), "WHISPER", "Jonatan")
	rejects("RESPONSE without sid", env("RESPONSE", nil, nil, { response = "BIS", gear = {} }), "WHISPER", "Jonatan")
	rejects("STATE_REQUEST with a sid", env("STATE_REQUEST", "sid1", nil, {}), "WHISPER", "Jonatan")
	rejects("SESSION_START without sid", env("SESSION_START", nil, 1, start()), "RAID", "Ashvane")
	rejects("sid too long", env("SESSION_START", string.rep("x", 65), 1, start()), "RAID", "Ashvane")

	----------------------------------------------------------------------------
	-- Accepting valid messages (and sequence handling, step 5)
	----------------------------------------------------------------------------
	check("valid SESSION_START accepted", Comm:Process(env("SESSION_START", "sid1", 1, start()), "RAID", "Ashvane") == true)
	check("event carries sender, sid, seq", last.SESSION_START.sender == "Ashvane" and last.SESSION_START.sid == "sid1" and last.SESSION_START.seq == 1)
	rejects("replayed seq", env("SESSION_START", "sid1", 1, start()), "RAID", "Ashvane")
	rejects("missing seq", env("AWARD", "sid1", nil, { winner = "Jonatan", itemID = 19019, response = "BIS" }), "RAID", "Ashvane")
	rejects("fractional seq", env("AWARD", "sid1", 1.5, { winner = "Jonatan", itemID = 19019, response = "BIS" }), "RAID", "Ashvane")
	check("accepted with realm suffix and higher seq",
		Comm:Process(env("SESSION_CANCEL", "sid1", 3, { reason = "test" }), "PARTY", "Ashvane-SomeRealm") == true)
	rejects("older seq after newer", env("AWARD", "sid1", 2, { winner = "Jonatan", itemID = 19019, response = "BIS" }), "RAID", "Ashvane")
	check("RESPONSE from a raider accepted",
		Comm:Process(env("RESPONSE", "sid1", nil, { response = "BIS", gear = { "item:12345:0:0:0" } }), "WHISPER", "Jonatan") == true)
	check("VOTE from council accepted",
		Comm:Process(env("VOTE", "sid1", nil, { candidate = "Jonatan" }), "WHISPER", "Veyra") == true)
	check("VOTE removal (no candidate) accepted",
		Comm:Process(env("VOTE", "sid1", nil, {}), "WHISPER", "Veyra") == true)
	check("STATE_REQUEST accepted", Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Jonatan") == true)
	check("name with a space and realm suffix is a council member",
		Comm:Process(env("VOTE", "sid1", nil, { candidate = "Jonatan" }), "WHISPER", "Allemano Moo-Realm") == true)

	----------------------------------------------------------------------------
	-- Step 6: payloads. High seq so only the payload can be the reason.
	----------------------------------------------------------------------------
	local bad = {
		{ "SESSION_START itemString/itemID mismatch", "SESSION_START", "sidX", function(p) p.itemString = "item:1:0" end, "RAID", "Ashvane" },
		{ "SESSION_START lm is not the sender", "SESSION_START", "sidX", function(p) p.lm = "Veyra" end, "RAID", "Ashvane" },
		{ "SESSION_START council too big", "SESSION_START", "sidX", function(p) p.council = {} for i = 1, 41 do p.council[i] = "Name" .. i end end, "RAID", "Ashvane" },
		{ "SESSION_START itemString injection", "SESSION_START", "sidX", function(p) p.itemString = "item:19019|cffff0000" end, "RAID", "Ashvane" },
		{ "SESSION_START negative itemID", "SESSION_START", "sidX", function(p) p.itemID = -5 end, "RAID", "Ashvane" },
		{ "SESSION_START council name with |", "SESSION_START", "sidX", function(p) p.council = { "Bad|cffff0000Name" } end, "RAID", "Ashvane" },
	}
	for _, c in ipairs(bad) do
		local p = start()
		c[4](p)
		rejects(c[1], env(c[2], c[3], 100, p), c[5], c[6])
	end
	rejects("RESPONSE with unknown response id", env("RESPONSE", "sid1", nil, { response = "MAINSPEC", gear = {} }), "WHISPER", "Jonatan")
	rejects("RESPONSE without gear list", env("RESPONSE", "sid1", nil, { response = "BIS" }), "WHISPER", "Jonatan")
	rejects("RESPONSE with too much gear", env("RESPONSE", "sid1", nil, { response = "BIS", gear = { "item:1", "item:2", "item:3", "item:4", "item:5" } }), "WHISPER", "Jonatan")
	rejects("RESPONSE with a gear link instead of itemString", env("RESPONSE", "sid1", nil, { response = "BIS", gear = { "|cffa335ee|Hitem:19019|h[X]|h|r" } }), "WHISPER", "Jonatan")
	rejects("VOTE with a non-string candidate", env("VOTE", "sid1", nil, { candidate = 42 }), "WHISPER", "Veyra")
	rejects("VOTE_UPDATE votes do not match voters", env("VOTE_UPDATE", "sid1", 100, { candidate = "Jonatan", votes = 3, voters = { "Veyra" } }), "WHISPER", "Ashvane")
	rejects("CANDIDATE_UPDATE lowercase class", env("CANDIDATE_UPDATE", "sid1", 100, { name = "Jonatan", class = "warrior", response = "BIS", gear = {} }), "WHISPER", "Ashvane")
	rejects("CANDIDATE_UPDATE with array holes", env("CANDIDATE_UPDATE", "sid1", 100, { name = "Jonatan", class = "WARRIOR", response = "BIS", gear = { [2] = "item:1" } }), "WHISPER", "Ashvane")
	rejects("AWARD without winner", env("AWARD", "sid1", 100, { itemID = 19019, response = "BIS" }), "RAID", "Ashvane")
	rejects("SESSION_CANCEL with empty reason", env("SESSION_CANCEL", "sid1", 100, { reason = "" }), "RAID", "Ashvane")
	rejects("VERSION with bad proto", env("VERSION", nil, nil, { addon = "0.1.0", proto = "x" }), "WHISPER", "Jonatan")

	Protocol.itemExists = function(id) return id ~= 99999 end
	rejects("AWARD for an unknown item", env("AWARD", "sid1", 100, { winner = "Jonatan", itemID = 99999, response = "BIS" }), "RAID", "Ashvane")
	Protocol.itemExists = function() return true end

	-- A rejected message must not consume its seq.
	check("valid message with the seq a bad one tried is still accepted",
		Comm:Process(env("CANDIDATE_UPDATE", "sid1", 100, candidate()), "WHISPER", "Ashvane") == true)

	-- STATE_SNAPSHOT: council view and raider view.
	local snapshot = start()
	snapshot.candidates = { candidate() }
	snapshot.votes = { { candidate = "Jonatan", voters = { "Veyra" } } }
	snapshot.yourVote = "Jonatan"
	check("council snapshot accepted", Comm:Process(env("STATE_SNAPSHOT", "sid1", 101, snapshot), "WHISPER", "Ashvane") == true)
	check("raider snapshot accepted", Comm:Process(env("STATE_SNAPSHOT", "sid1", 102, (function() local p = start() p.yourResponse = "PASS" return p end)()), "WHISPER", "Ashvane") == true)
	local badSnap = start()
	badSnap.candidates = { { name = "Jonatan", class = "WARRIOR", response = "NOPE", gear = {} } }
	rejects("snapshot with a bad candidate", env("STATE_SNAPSHOT", "sid1", 103, badSnap), "WHISPER", "Ashvane")

	----------------------------------------------------------------------------
	-- Decoding
	----------------------------------------------------------------------------
	local before = total()
	check("garbage rejected", Comm:HandleMessage("garbage", "WHISPER", "Veyra") == false)
	check("oversized rejected", Comm:HandleMessage(string.rep("x", 20000), "WHISPER", "Veyra") == false)
	check("non-string rejected", Comm:HandleMessage(nil, "WHISPER", "Veyra") == false)
	check("decode failures change nothing", total() == before)
	check("roundtrip through the serializer",
		Comm:HandleMessage(AceSerializer:Serialize(env("VOTE", "sid1", nil, { candidate = "Jonatan" })), "WHISPER", "Veyra") == true)

	----------------------------------------------------------------------------
	-- Sending
	----------------------------------------------------------------------------
	H.sent = {}
	local sent = H.sent
	activeSid = "sid1"

	-- As a non-LM, LM-only messages are refused locally.
	lmName = "Ashvane"
	before = total()
	check("non-LM cannot send SESSION_CANCEL", Comm:SendRaid("SESSION_CANCEL", "sid1", { reason = "x" }) == false)
	check("nothing sent or delivered", #H.sent == 0 and total() == before)
	check("wrong channel refused", Comm:SendWhisper("Veyra", "AWARD", "sid1", { winner = "Jonatan", itemID = 19019, response = "BIS" }) == false)
	check("invalid payload refused", Comm:SendWhisper("Veyra", "VOTE", "sid1", { candidate = 42 }) == false)
	check("missing target refused", Comm:SendWhisper("", "STATE_REQUEST", nil, {}) == false)

	-- As LM.
	lmName = "Tester Moo"
	activeSid = "sidLM"
	local mine = start()
	mine.lm = "Tester Moo"
	H.inRaid = true
	check("LM sends SESSION_START", Comm:SendRaid("SESSION_START", "sidLM", mine) == true)
	check("sent on the raid channel", #H.sent == 1 and H.sent[1].dist == "RAID" and H.sent[1].prefix == "ALC")
	check("loopback delivered it to ourselves", last.SESSION_START.sid == "sidLM" and last.SESSION_START.sender == "Tester Moo" and last.SESSION_START.seq == 1)
	check("loopback is an independent copy", last.SESSION_START.p ~= mine)
	check("LM sends AWARD with the next seq", Comm:SendRaid("AWARD", "sidLM", { winner = "Jonatan", itemID = 19019, response = "BIS" }) == true)
	check("seq increments per session", last.AWARD.seq == 2)
	local okDecode, decoded = AceSerializer:Deserialize(H.sent[2].text)
	check("wire message is a valid envelope", okDecode and decoded.v == 1 and decoded.t == "AWARD" and decoded.seq == 2 and decoded.sid == "sidLM")

	-- Solo: no network traffic, still delivered locally.
	H.inRaid = false
	local netBefore = #H.sent
	check("solo broadcast works", Comm:SendRaid("SESSION_CANCEL", "sidLM", { reason = "solo" }) == true)
	check("solo broadcast stays local", #H.sent == netBefore and last.SESSION_CANCEL.p.reason == "solo")

	-- Whispers.
	H.sent = {}
	check("whisper to another player", Comm:SendWhisper("Veyra", "CANDIDATE_UPDATE", "sidLM", candidate()) == true)
	check("sent as WHISPER to the target", #H.sent == 1 and H.sent[1].dist == "WHISPER" and H.sent[1].target == "Veyra")
	H.sent = {}
	local acceptedBefore = accepted.CANDIDATE_UPDATE
	check("whisper to ourselves", Comm:SendWhisper("Tester Moo", "CANDIDATE_UPDATE", "sidLM", candidate()) == true)
	check("self whisper is loopback only", #H.sent == 0 and accepted.CANDIDATE_UPDATE == acceptedBefore + 1)

	-- Council fan-out: one seq for everyone, duplicates removed, self by loopback.
	H.sent = {}
	acceptedBefore = accepted.VOTE_UPDATE or 0
	check("council fan-out", Comm:SendCouncil({ "Veyra", "veyra", "Tester Moo", "Allemano Moo" }, "VOTE_UPDATE", "sidLM",
		{ candidate = "Jonatan", votes = 1, voters = { "Veyra" } }) == true)
	check("one whisper per distinct remote target", #H.sent == 2 and H.sent[1].target == "Veyra" and H.sent[2].target == "Allemano Moo")
	check("self got it by loopback", accepted.VOTE_UPDATE == acceptedBefore + 1)
	local _, e1 = AceSerializer:Deserialize(H.sent[1].text)
	local _, e2 = AceSerializer:Deserialize(H.sent[2].text)
	check("same seq for every recipient", e1.seq == e2.seq and e1.seq == last.VOTE_UPDATE.seq)

	-- Own network echo is dropped.
	before = total()
	Comm:OnCommReceived("ALC", AceSerializer:Serialize(env("VERSION_REQUEST", nil, nil, {})), "RAID", "Tester Moo")
	check("network echo of our own message ignored", total() == before)

	----------------------------------------------------------------------------
	-- Versions
	----------------------------------------------------------------------------
	H.sent = {}
	Comm:OnCommReceived("ALC", AceSerializer:Serialize(env("VERSION_REQUEST", nil, nil, {})), "RAID", "Jonatan")
	check("version request answered by whisper", #H.sent == 1 and H.sent[1].dist == "WHISPER" and H.sent[1].target == "Jonatan")
	local _, reply = AceSerializer:Deserialize(H.sent[1].text)
	check("reply carries our versions", reply.t == "VERSION" and reply.p.addon == ALC.version and reply.p.proto == 1)
	Comm:OnCommReceived("ALC", AceSerializer:Serialize(env("VERSION", nil, nil, { addon = "0.1.0", proto = 1 })), "WHISPER", "Veyra")
	check("version reply recorded", Comm:GetVersions()["veyra"].addon == "0.1.0")

	local chatBefore = #H.chat
	Comm:RequestVersions()
	check("version report printed", #H.chat > chatBefore)

	----------------------------------------------------------------------------
	-- Rejection log is rate limited
	----------------------------------------------------------------------------
	local rejectedLines = function() return warnCount("rejected VOTE from Jonatan: sender is not on the council") end
	H.clock = H.clock + 60 -- the same rejection was already logged earlier in this run
	local n0 = rejectedLines()
	for _ = 1, 20 do Comm:Process(env("VOTE", "sidLM", nil, { candidate = "X1" }), "WHISPER", "Jonatan") end
	check("repeated rejection logged once", rejectedLines() - n0 == 1)
	H.clock = H.clock + 60
	Comm:Process(env("VOTE", "sidLM", nil, { candidate = "X1" }), "WHISPER", "Jonatan")
	check("logged again after the interval", rejectedLines() - n0 == 2)
end

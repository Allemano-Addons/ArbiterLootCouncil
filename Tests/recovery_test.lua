-- The loot master survives a /reload: session, candidates, loot list and message
-- numbering come back. Every "reload" here loads the whole addon again from the saved
-- variables only, so nothing can leak through memory. Runs last.

return function(check, H)
	local AceSerializer = LibStub("AceSerializer-3.0")
	local ME = "Tester Moo"

	local function env(t, sid, seq, p) return { v = 1, t = t, sid = sid, seq = seq, p = p } end

	-- The world after each reload: the fake party, item data and who leads.
	local leader = ME
	local function world()
		local units = {
			player = { "Tester", "Moo", "ROGUE" },
			party1 = { "Veyra", "Moo", "WARRIOR" },
			party2 = { "Ashvane", "Moo", "MAGE" },
		}
		UnitName = function(unit) local u = units[unit]; if u then return u[1], u[2] end end
		UnitClass = function(unit) local u = units[unit]; if u then return u[3], u[3] end end
		UnitIsConnected = function() return true end
		C_Item.GetItemInfoInstant = function(item)
			local id = tonumber(item) or tonumber(tostring(item):match("item:(%d+)"))
			if id == 200 then return id, "Armor", "Leather", "INVTYPE_HEAD", 133101 end
		end
		H.inGroup = true
		ALC.Council.GetLootMethodInfo = function() return 3 end
		ALC.Council.GetLeaderName = function() return leader end
		ALC.Council:Refresh()
	end

	----------------------------------------------------------------------------
	-- Before the reload: a session with answers
	----------------------------------------------------------------------------
	H.reload("fresh")

	-- A window whose build fails half way must not stay half built: the next try starts over.
	local realCreateFrame, created = CreateFrame, 0
	CreateFrame = function(...)
		created = created + 1
		if created == 3 then error("build broke") end
		return realCreateFrame(...)
	end
	local built = pcall(ALC.LootWindow.Show, ALC.LootWindow)
	CreateFrame = realCreateFrame
	check("a failing build raises its error", built == false)
	check("and leaves no window open", not ALC.LootWindow:IsShown())
	ALC.LootWindow:Show()
	check("the next try builds the whole window", ALC.LootWindow:IsShown() and #ALC.LootWindow.rows == 8)
	ALC.LootWindow:Hide()

	leader = ME
	world()
	local LD, Sessions, Candidates, Responses, Comm = ALC.LootDetection, ALC.Sessions, ALC.Candidates, ALC.Responses, ALC.Comm
	ALC.Settings:AddCouncilMember("Veyra Moo")

	-- Two of the same item: the session must come back on the row that started it.
	LD:AddFromText("200 200")
	local firstId, entryId = LD:GetItems()[1].id, LD:GetItems()[2].id
	check("start a session from the second row", LD:StartSession(entryId) == true and Sessions:IsActive())
	local sid = Sessions:GetActiveSid()
	Responses:Send("UPGRADE")
	Comm:Process(env("RESPONSE", sid, nil, { response = "BIS", gear = { "item:151" } }), "WHISPER", "Veyra Moo")
	check("two candidates before the reload", #Candidates:GetList() == 2)
	local seqBefore = ALC.Settings:GetSeqStore()[sid]
	check("the sequence numbers are saved as they are used", seqBefore ~= nil and seqBefore >= 2)
	local store = ALC.Settings:GetSessionStore()
	check("the session and the candidates are saved", store.session ~= nil and store.session.sid == sid and #store.candidates == 2)
	local before = H.snapshotDB()
	check("the response window is open before the reload", ALC.ResponseWindow:IsShown())
	ALC.ResponseWindow:Hide() -- the player closes it
	local beforeClosed = H.snapshotDB()

	----------------------------------------------------------------------------
	-- The reload
	----------------------------------------------------------------------------
	H.reload(before)
	world()
	LD, Sessions, Candidates, Responses, Comm = ALC.LootDetection, ALC.Sessions, ALC.Candidates, ALC.Responses, ALC.Comm
	check("nothing is running right after the reload", not Sessions:IsActive() and #Candidates:GetList() == 0)
	check("the loot list is back, but not as a session", LD:GetEntry(entryId).status == LD.STATUS.PENDING)

	Sessions:OnEnteringWorld(false, false)
	check("a zone change restores nothing", not Sessions:IsActive())
	Sessions:OnEnteringWorld(false, true)
	check("the session is restored for the loot master", Sessions:GetActiveSid() == sid)
	local restored = Sessions:GetSession()
	check("it knows it is the loot master and on the council", restored.isLM and restored.isCouncil and restored.restored)
	check("the item and council are the same", restored.itemID == 200 and #restored.council == 2)
	check("the candidates are back", #Candidates:GetList() == 2 and Candidates:Get("Veyra Moo").response == "BIS"
		and Candidates:Get(ME).response == "UPGRADE")
	check("our own answer is back", Responses:GetMyResponse() == "UPGRADE")
	check("the loot list entry is in session again", LD:GetEntry(entryId).status == LD.STATUS.SESSION and LD:GetEntry(entryId).sid == sid)
	check("and the other row with the same item is still waiting", LD:GetEntry(firstId).status == LD.STATUS.PENDING and LD:GetEntry(firstId).sid == nil)
	check("nothing was broadcast to bring it back", #H.sent == 0)
	check("the response window is open again: it was open before the reload", ALC.ResponseWindow:IsShown())

	-- Messages keep their numbering, so the others still accept them.
	H.sent = {}
	Responses:Send("MINOR")
	local update
	for _, sent in ipairs(H.sent) do
		local _, decoded = AceSerializer:Deserialize(sent.text)
		if decoded.t == "CANDIDATE_UPDATE" then update = decoded end
	end
	check("the loot master's next message continues the numbering", update ~= nil and update.seq == seqBefore + 1 and update.sid == sid)

	-- The session works as before.
	check("the loot master can award it", Comm:SendRaid("AWARD", sid, { winner = "Veyra Moo", itemID = 200, response = "BIS" }) == true)
	check("which ends it and clears what was saved", not Sessions:IsActive()
		and ALC.Settings:GetSessionStore().session == nil and ALC.Settings:GetSessionStore().candidates == nil)
	check("and the entry is awarded", LD:GetEntry(entryId).status == LD.STATUS.AWARDED and LD:GetEntry(entryId).winner == "Veyra Moo")

	-- A window the player had closed stays closed, as long as the answer is in.
	H.reload(beforeClosed)
	leader = ME
	world()
	ALC.Sessions:OnEnteringWorld(false, true)
	check("the session is restored", ALC.Sessions:IsActive() and ALC.Candidates:Get(ME).response == "UPGRADE")
	check("a response window the player had closed stays closed", not ALC.ResponseWindow:IsShown())

	-- ... but an unanswered session always asks.
	local unanswered = H.snapshotDB()
	unanswered.global.sessionStore.candidates = {}
	H.reload(unanswered)
	leader = ME
	world()
	ALC.Sessions:OnEnteringWorld(false, true)
	check("without an answer the window opens even if it had been closed", ALC.ResponseWindow:IsShown())

	----------------------------------------------------------------------------
	-- Cases where the session must not come back
	----------------------------------------------------------------------------
	-- Somebody else leads now.
	H.reload(before)
	leader = "Ashvane Moo"
	world()
	ALC.Sessions:OnEnteringWorld(false, true)
	check("not restored when somebody else is the loot master", not ALC.Sessions:IsActive())
	check("it is kept in case we lead again", ALC.Settings:GetSessionStore().session ~= nil)

	-- Too old.
	H.reload(before)
	leader = ME
	world()
	ALC.Settings:GetSessionStore().savedAt = os.time() - 7 * 3600
	ALC.Sessions:OnEnteringWorld(false, true)
	check("an old session is not restored", not ALC.Sessions:IsActive())
	check("and is dropped", ALC.Settings:GetSessionStore().session == nil and ALC.Settings:GetSessionStore().candidates == nil)

	-- Ended before the reload.
	H.reload(before)
	leader = ME
	world()
	ALC.Sessions:OnEnteringWorld(false, true)
	ALC.Sessions:Cancel("done")
	local afterCancel = H.snapshotDB()
	H.reload(afterCancel)
	world()
	ALC.Sessions:OnEnteringWorld(false, true)
	check("a session that ended is not restored", not ALC.Sessions:IsActive())

	-- Players who are not the loot master save nothing.
	H.reload("fresh")
	leader = "Ashvane Moo"
	world()
	local Comm2 = ALC.Comm
	local council = { "Ashvane Moo", ME }
	Comm2:Process(env("SESSION_START", "sidX", 1, { itemID = 200, itemString = "item:200", council = council, lm = "Ashvane Moo" }), "PARTY", "Ashvane Moo")
	check("a client has the session", ALC.Sessions:GetActiveSid() == "sidX")
	check("but saves none of it", ALC.Settings:GetSessionStore().session == nil and ALC.Settings:GetSessionStore().candidates == nil)
	H.reload()
	world()
	ALC.Sessions:OnEnteringWorld(false, true)
	check("so after a reload it asks the loot master instead", not ALC.Sessions:IsActive() and #H.sent >= 1)
	local _, request = AceSerializer:Deserialize(H.sent[#H.sent].text)
	check("with a STATE_REQUEST", request.t == "STATE_REQUEST" and H.sent[#H.sent].target == "Ashvane Moo")

	-- The saved numbering is bounded.
	local seqStore = ALC.Settings:GetSeqStore()
	for i = 1, 12 do
		for k in pairs(seqStore) do seqStore[k] = nil end
		seqStore["old" .. i] = i
	end
	check("the seq store stays small", (function() local n = 0 for _ in pairs(seqStore) do n = n + 1 end return n <= 8 end)())
end

-- Gear, Responses, Candidates and the response window, on the real modules.
-- Runs before the Comm tests, which replace Council and Sessions with stand-ins.

return function(check, H)
	local Gear, Responses, Candidates = ALC.Gear, ALC.Responses, ALC.Candidates
	local Sessions, Council, Comm, Win = ALC.Sessions, ALC.Council, ALC.Comm, ALC.ResponseWindow
	local AceSerializer = LibStub("AceSerializer-3.0")
	local ME = "Tester Moo"

	local env = H.env

	----------------------------------------------------------------------------
	-- Fake item data
	----------------------------------------------------------------------------
	local db = {
		[200] = { "Crown of Destruction", "INVTYPE_HEAD" },
		[100] = { "Band of Accuria", "INVTYPE_FINGER" },
		[19019] = { "Thunderfury", "INVTYPE_WEAPON" },
		[400] = { "Greatsword", "INVTYPE_2HWEAPON" },
		[500] = { "Bulwark", "INVTYPE_SHIELD" },
		[600] = { "Trinket", "INVTYPE_TRINKET" },
		[700] = { "Offhand Orb", "INVTYPE_HOLDABLE" },
		[800] = { "Main Hand Dagger", "INVTYPE_WEAPONMAINHAND" },
		[900] = { "Wand", "INVTYPE_RANGEDRIGHT" },
		[300] = { "Small Furry Paw", "INVTYPE_NON_EQUIP_IGNORE" },
	}
	local function idOf(item) return tonumber(item) or tonumber(tostring(item):match("item:(%d+)")) end
	C_Item.GetItemInfoInstant = function(item)
		local d = db[idOf(item)]
		if d then return idOf(item), "Armor", "Plate", d[2], 133101 end
	end
	C_Item.GetItemInfo = function(item)
		local id = idOf(item)
		local d = db[id]
		if d then return d[1], "|Hitem:" .. id .. "|h[" .. d[1] .. "]|h", 4, 60, 0, "Armor", "Plate", 1, d[2], 133101 end
	end
	C_Item.RequestLoadItemDataByID = function() end

	----------------------------------------------------------------------------
	-- Gear
	----------------------------------------------------------------------------
	local worn = {}
	Gear.GetEquippedLink = function(slot) return worn[slot] end
	local function slotsOf(id) return table.concat(Gear:GetSlots(id), ",") end

	check("head has one slot", slotsOf(200) == "1")
	check("rings compete for two slots", slotsOf(100) == "11,12")
	check("trinkets compete for two slots", slotsOf(600) == "13,14")
	check("a one-hander fits either hand", slotsOf(19019) == "16,17")
	check("a two-hander is compared with both hands", slotsOf(400) == "16,17")
	check("main hand only", slotsOf(800) == "16")
	check("shield and held-in-off-hand go in the off hand", slotsOf(500) == "17" and slotsOf(700) == "17")
	check("ranged slot", slotsOf(900) == "18")
	check("items that are not worn have no slots", slotsOf(300) == "" and slotsOf(999) == "")
	local copy = Gear:GetSlots(100)
	copy[1] = 99
	check("GetSlots returns a copy", slotsOf(100) == "11,12")

	check("nothing worn: an empty list", #Gear:GetEquipped(100) == 0)
	worn[11] = "|cnIQ4:|Hitem:111::::::::60:::::::|h[Ring A]|h|r"
	local one = Gear:GetEquipped(100)
	check("one ring worn", #one == 1 and one[1] == "item:111::::::::60")
	worn[12] = "|cnIQ4:|Hitem:112::::::::60:::::::|h[Ring B]|h|r"
	local two = Gear:GetEquipped(100)
	check("both rings, in slot order", #two == 2 and two[1] == "item:111::::::::60" and two[2] == "item:112::::::::60")
	worn[16] = "|Hitem:113|h[Sword]|h"
	check("only the slots the item competes for", #Gear:GetEquipped(200) == 0 and #Gear:GetEquipped(800) == 1)
	check("a two-hander lists both hands when both are worn", (function()
		worn[17] = "|Hitem:114|h[Shield]|h"
		return #Gear:GetEquipped(400) == 2
	end)())
	check("unknown items list nothing", #Gear:GetEquipped(999) == 0)
	worn = {}

	----------------------------------------------------------------------------
	-- A party: we lead it (group loot, so we are the loot master)
	----------------------------------------------------------------------------
	local units = {
		player = { "Tester", "Moo", "ROGUE" },
		party1 = { "Veyra", "Moo", "WARRIOR" },
		party2 = { "Jonatan", "Moo", "PRIEST" },
		party3 = { "Kaelis", "Moo", "HUNTER" },
	}
	local offline = {}
	local realUnitName, realUnitClass = UnitName, UnitClass
	UnitName = function(unit) local u = units[unit]; if u then return u[1], u[2] end end
	UnitClass = function(unit) local u = units[unit]; if u then return u[3], u[3] end end
	UnitIsConnected = function(unit) return not offline[unit] end
	H.inGroup = true
	local leader = ME
	Council.GetLootMethodInfo = function() return 3 end
	Council.GetLeaderName = function() return leader end
	Comm.GetGroupNames = nil -- back to the real one, which reads the units above
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

	check("GroupUnits lists the party", table.concat(ALC:GroupUnits(), ",") == "player,party1,party2,party3,party4")
	check("FindUnitByName", ALC:FindUnitByName("veyra moo-Realm") == "party1" and ALC:FindUnitByName("Nobody Moo") == nil)

	local candidateEvents = 0
	local responseEvents = 0
	local listener = {}
	ALC.Events.Register(listener, "ALC_CANDIDATES_CHANGED", function() candidateEvents = candidateEvents + 1 end)
	ALC.Events.Register(listener, "ALC_RESPONSES_CHANGED", function() responseEvents = responseEvents + 1 end)

	local function whispersTo()
		local targets = {}
		for _, sent in ipairs(H.sent) do
			local _, e = AceSerializer:Deserialize(sent.text)
			if e and e.t == "CANDIDATE_UPDATE" then targets[#targets + 1] = sent.target end
		end
		table.sort(targets)
		return table.concat(targets, ",")
	end

	local function endSession()
		if Sessions:IsActive() then Sessions:Cancel("test reset") end
		H.sent = {}
	end
	endSession()

	----------------------------------------------------------------------------
	-- No session
	----------------------------------------------------------------------------
	local okNo, msgNo = Responses:Send("BIS")
	check("no response without a session", okNo == false and msgNo ~= nil)
	check("an unknown response is refused", Responses:Send("MAINSPEC") == false)
	check("labels", Responses:GetLabel("BIS") == "BiS" and Responses:GetLabel("PASS") == "Pass")

	----------------------------------------------------------------------------
	-- As loot master
	----------------------------------------------------------------------------
	worn[1] = "|Hitem:150::::::::60:::::::|h[Old Helm]|h"
	check("start a session", Sessions:Start(200) == true and Sessions:IsActive())
	check("the response window opens for a new session", Win:IsShown())
	check("no response yet", Responses:GetMyResponse() == nil)
	check("there are five buttons", #Win.rows[1].buttons == 5)
	H.sent = {}

	check("send a response", Responses:Send("UPGRADE") == true)
	check("our response is remembered", Responses:GetMyResponse() == "UPGRADE" and responseEvents > 0)
	local list = Candidates:GetList()
	check("we are a candidate, with class and gear", #list == 1 and list[1].name == ME and list[1].class == "ROGUE"
		and list[1].response == "UPGRADE" and list[1].gear[1] == "item:150::::::::60")
	check("the council was told, and only the council", whispersTo() == "Kaelis Moo,Veyra Moo")
	local _, update = AceSerializer:Deserialize(H.sent[1].text)
	check("the update carries the candidate", update.t == "CANDIDATE_UPDATE" and update.p.name == ME and update.p.response == "UPGRADE" and update.sid == Sessions:GetActiveSid())

	H.sent = {}
	Responses:Send("UPGRADE")
	check("the same answer again tells nobody", whispersTo() == "")
	local before = candidateEvents
	Responses:Send("BIS")
	check("changing the answer updates the list and the council", Candidates:Get(ME).response == "BIS" and whispersTo() == "Kaelis Moo,Veyra Moo" and candidateEvents > before)
	check("still one candidate", #Candidates:GetList() == 1)

	-- Answers from other players.
	H.sent = {}
	check("a raider's RESPONSE is accepted", Comm:Process(env("RESPONSE", Sessions:GetActiveSid(), nil, { response = "UPGRADE", gear = { "item:151" } }), "WHISPER", "Veyra Moo") == true)
	check("and becomes a candidate with their class", Candidates:Get("Veyra Moo").class == "WARRIOR" and Candidates:Get("veyra moo").gear[1] == "item:151")
	check("the council hears about it", whispersTo() == "Kaelis Moo,Veyra Moo")

	local n = #Candidates:GetList()
	check("a stranger's RESPONSE is rejected", Comm:Process(env("RESPONSE", Sessions:GetActiveSid(), nil, { response = "BIS", gear = {} }), "WHISPER", "Stranger Moo") == false and #Candidates:GetList() == n)

	-- Someone Comm accepts but we cannot find a class for.
	local names = Comm.GetGroupNames
	Comm.GetGroupNames = function() local t = names(); t[#t + 1] = "Ghost Moo"; return t end
	Comm:InvalidateRoster()
	check("a response we cannot classify is ignored", Comm:Process(env("RESPONSE", Sessions:GetActiveSid(), nil, { response = "BIS", gear = {} }), "WHISPER", "Ghost Moo") == true
		and Candidates:Get("Ghost Moo") == nil)
	Comm.GetGroupNames = names
	Comm:InvalidateRoster()

	-- Council members who are offline are not whispered.
	offline.party1 = true
	H.sent = {}
	Comm:Process(env("RESPONSE", Sessions:GetActiveSid(), nil, { response = "MINOR", gear = {} }), "WHISPER", "Jonatan Moo")
	check("offline council members are skipped", whispersTo() == "Kaelis Moo")
	offline.party1 = nil

	Comm:Process(env("RESPONSE", Sessions:GetActiveSid(), nil, { response = "PASS", gear = {} }), "WHISPER", "Jonatan Moo")
	check("a pass is a candidate too", Candidates:Get("Jonatan Moo").response == "PASS")
	local counts = Candidates:GetCounts()
	check("counts: responded, passed, silent", counts.responded == 3 and counts.passed == 1 and counts.wanting == 2 and counts.silent == 1)
	-- The loot master can set a roll later (Soft Reserve rolls when it resolves, not when a player answers).
	check("no roll was made: rolls are off in this session", Candidates:Get("Jonatan Moo").roll == nil)
	H.sent = {}
	local before2 = candidateEvents
	check("the loot master sets a roll", Candidates:SetRoll("Jonatan Moo", 77) == true and Candidates:Get("Jonatan Moo").roll == 77)
	check("the council was told, only the council", whispersTo() == "Kaelis Moo,Veyra Moo" and candidateEvents > before2)
	local _, rolled = AceSerializer:Deserialize(H.sent[1].text)
	check("the update carries the roll", rolled.t == "CANDIDATE_UPDATE" and rolled.p.name == "Jonatan Moo" and rolled.p.roll == 77)
	H.sent = {}
	check("the same roll again tells nobody", Candidates:SetRoll("Jonatan Moo", 77) == true and whispersTo() == "")
	check("a roll can be changed", Candidates:SetRoll("jonatan moo", 5) == true and Candidates:Get("Jonatan Moo").roll == 5)
	check("a roll outside 1 to 100 is refused", Candidates:SetRoll("Jonatan Moo", 0) == false and Candidates:SetRoll("Jonatan Moo", 101) == false and Candidates:Get("Jonatan Moo").roll == 5)
	check("a fraction or text is refused", Candidates:SetRoll("Jonatan Moo", 5.5) == false and Candidates:SetRoll("Jonatan Moo", "9") == false)
	check("someone who did not answer has no roll to set", Candidates:SetRoll("Nobody Moo", 50) == false)
	check("an item that is not in the session is refused", Candidates:SetRoll("Jonatan Moo", 50, 4) == false)

	-- Snapshots for players who reload.
	H.clock = H.clock + 100
	H.sent = {}
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Veyra Moo")
	local _, councilSnap = AceSerializer:Deserialize(H.sent[1].text)
	check("a council member gets the candidates", councilSnap.p.candidates ~= nil and #councilSnap.p.candidates == 3)
	check("and their own response", councilSnap.p.yourResponses[1].response == "UPGRADE" and councilSnap.p.yourResponses[1].item == 1)
	H.sent = {}
	H.clock = H.clock + 100
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Jonatan Moo")
	local _, raiderSnap = AceSerializer:Deserialize(H.sent[1].text)
	check("a raider gets no candidates but their own response", raiderSnap.p.candidates == nil and raiderSnap.p.yourResponses[1].response == "PASS")
	H.sent = {}
	H.clock = H.clock + 100
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Kaelis Moo")
	local _, silentSnap = AceSerializer:Deserialize(H.sent[1].text)
	check("someone who has not answered gets no response", silentSnap.p.yourResponse == nil and silentSnap.p.candidates ~= nil)

	-- Slash commands.
	local chat = #H.chat
	H.slash("candidates")
	check("/alc candidates prints the list", #H.chat > chat + 2)
	H.slash("respond minor")
	check("/alc respond answers", Responses:GetMyResponse() == "MINOR")
	Win:Hide()
	H.slash("respond")
	check("/alc respond opens the window", Win:IsShown())

	-- The window.
	local buttons = Win.rows[1].buttons
	check("the selected button is highlighted", buttons[3].selected == true and buttons[1].selected == false)
	buttons[1].scripts.OnClick(buttons[1])
	check("clicking a button answers", Responses:GetMyResponse() == "BIS" and buttons[1].selected == true and buttons[3].selected == false)
	local status = Win.rows[1].parent.status:GetText()
	check("the status shows the answer", status:find("BiS", 1, true) ~= nil)
	local realSend = Comm.SendWhisper
	Comm.SendWhisper = function() return false end
	buttons[2].scripts.OnClick(buttons[2])
	check("a failed send is reported, not remembered", Responses:GetMyResponse() == "BIS" and Win.rows[1].parent.status:GetText():find("Could not", 1, true) ~= nil)
	Comm.SendWhisper = realSend
	local frame = Win.rows[1].parent
	check("the window shows the item", Win.rows[1].name:GetText() == "Crown of Destruction" and Win.rows[1].icon.texture == 133101)
	check("and the loot master", frame.lm:GetText():find(ME, 1, true) ~= nil)
	frame.header.scripts.OnDragStop(frame.header)
	check("the window position is saved", ALC.Settings:GetWindowPosition("response") ~= nil)

	-- The end of the session clears everything.
	Sessions:Cancel("done")
	check("the session ended", not Sessions:IsActive())
	check("the response window closed", not Win:IsShown())
	check("the candidates are cleared", #Candidates:GetList() == 0)
	check("our response is cleared", Responses:GetMyResponse() == nil)
	local chat2 = #H.chat
	H.slash("respond")
	check("nothing to answer without a session", not Win:IsShown() and #H.chat == chat2 + 1)

	----------------------------------------------------------------------------
	-- As a council member, with somebody else as loot master
	----------------------------------------------------------------------------
	H.sent = {}
	units.party1 = { "Ashvane", "Moo", "MAGE" }
	units.party2 = { "Veyra", "Moo", "WARRIOR" }
	leader = "Ashvane Moo"
	Comm:InvalidateRoster()
	Council:Refresh()

	local council = { "Ashvane Moo", ME, "Veyra Moo" }
	local start = { itemID = 200, itemString = "item:200", council = council, lm = "Ashvane Moo" }
	Comm:Process(env("SESSION_START", "sidC", 1, start), "PARTY", "Ashvane Moo")
	check("a session from the loot master starts here", Sessions:GetActiveSid() == "sidC" and Win:IsShown())
	check("the window offers the answers", Sessions:GetSession().isCouncil and not Sessions:GetSession().isLM)

	local update1 = { name = "Veyra Moo", class = "WARRIOR", response = "BIS", gear = { "item:151" } }
	check("candidate updates from the loot master arrive", Comm:Process(env("CANDIDATE_UPDATE", "sidC", 2, update1), "WHISPER", "Ashvane Moo") == true
		and #Candidates:GetList() == 1 and Candidates:Get("Veyra Moo").response == "BIS")
	Comm:Process(env("CANDIDATE_UPDATE", "sidC", 3, { name = "Veyra Moo", class = "WARRIOR", response = "UPGRADE", gear = {} }), "WHISPER", "Ashvane Moo")
	check("an update replaces the entry", #Candidates:GetList() == 1 and Candidates:Get("Veyra Moo").response == "UPGRADE")
	check("only the loot master can send updates", Comm:Process(env("CANDIDATE_UPDATE", "sidC", 4, update1), "WHISPER", "Veyra Moo") == false)

	-- A RESPONSE whispered to somebody who is not the loot master must not build a list.
	local listBefore = #Candidates:GetList()
	check("comm lets the group member's response through", Comm:Process(env("RESPONSE", "sidC", nil, { response = "BIS", gear = {} }), "WHISPER", "Kaelis Moo") == true)
	check("but a non-loot-master ignores it", #Candidates:GetList() == listBefore and Candidates:Get("Kaelis Moo") == nil)

	H.sent = {}
	Responses:Send("OFFSPEC")
	local _, sentResponse = AceSerializer:Deserialize(H.sent[1].text)
	check("our response goes to the loot master", H.sent[1].target == "Ashvane Moo" and sentResponse.t == "RESPONSE" and sentResponse.p.response == "OFFSPEC")
	check("a non-loot-master does not build the list itself", #Candidates:GetList() == 1)

	Comm:Process(env("SESSION_CANCEL", "sidC", 5, { reason = "done" }), "PARTY", "Ashvane Moo")
	check("the list is cleared when the session ends", #Candidates:GetList() == 0)

	-- Not on the council: updates are ignored, the list stays empty.
	local startB = { itemID = 200, itemString = "item:200", council = { "Ashvane Moo", "Veyra Moo" }, lm = "Ashvane Moo" }
	Comm:Process(env("SESSION_START", "sidD", 1, startB), "PARTY", "Ashvane Moo")
	Comm:Process(env("CANDIDATE_UPDATE", "sidD", 2, update1), "WHISPER", "Ashvane Moo")
	check("outside the council there is no list", #Candidates:GetList() == 0)
	local chat3 = #H.chat
	H.slash("candidates")
	check("/alc candidates says the list is for the council", #H.chat == chat3 + 1 and H.chat[#H.chat]:find("council", 1, true) ~= nil)
	Comm:Process(env("SESSION_CANCEL", "sidD", 3, { reason = "done" }), "PARTY", "Ashvane Moo")

	-- After a reload: the snapshot restores the candidates and our answer.
	Win:Hide()
	H.clock = H.clock + 100
	check("ask for the state", Sessions:RequestState() == true)
	local snap = { itemID = 200, itemString = "item:200", council = council, lm = "Ashvane Moo",
		candidates = { update1, { name = "Jonatan Moo", class = "PRIEST", response = "PASS", gear = {} } }, yourResponse = "MINOR" }
	Comm:Process(env("STATE_SNAPSHOT", "sidE", 1, snap), "WHISPER", "Ashvane Moo")
	check("the session is restored", Sessions:GetActiveSid() == "sidE" and Sessions:GetSession().restored == true)
	check("the candidates are restored", #Candidates:GetList() == 2 and Candidates:Get("Jonatan Moo").response == "PASS")
	check("our answer is restored", Responses:GetMyResponse() == "MINOR")
	check("the window stays closed when there is nothing left to answer", not Win:IsShown())
	Comm:Process(env("SESSION_CANCEL", "sidE", 2, { reason = "done" }), "PARTY", "Ashvane Moo")

	-- ... and when we had not answered, the window comes back.
	H.clock = H.clock + 100
	Sessions:RequestState()
	local snap2 = { itemID = 200, itemString = "item:200", council = council, lm = "Ashvane Moo", candidates = {} }
	Comm:Process(env("STATE_SNAPSHOT", "sidF", 1, snap2), "WHISPER", "Ashvane Moo")
	check("an unanswered session reopens the window", Win:IsShown() and Responses:GetMyResponse() == nil)
	Comm:Process(env("SESSION_CANCEL", "sidF", 2, { reason = "done" }), "PARTY", "Ashvane Moo")

	-- Put the environment back for the following tests.
	UnitName, UnitClass = realUnitName, realUnitClass
	UnitIsConnected = function() return true end
	H.inGroup = false
	C_Item.GetItemInfo = function() end
	C_Item.GetItemInfoInstant = nil
	C_Item.RequestLoadItemDataByID = nil
	leader = ME
	Council.GetLeaderName = function() return nil end
	Comm:InvalidateRoster()
	ALC.LootDetection:Clear()
end

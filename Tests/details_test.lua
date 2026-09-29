-- Notes, guild ranks and custom response buttons. Every "reload" loads the whole addon
-- again from the saved variables only. Runs after the multi-item tests.

return function(check, H)
	local AceSerializer = LibStub("AceSerializer-3.0")
	local ME = "Tester Moo"
	local env = H.env

	local db = {
		[200] = { "Crown of Destruction", 4, "INVTYPE_HEAD" },
		[201] = { "Belt of Might", 4, "INVTYPE_WAIST" },
	}
	local guilds = { player = { "Slaughter", "Officer", 1 }, party1 = { "Slaughter", "Raider", 4 }, party2 = { "Other Guild", "Boss", 0 } }
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
		GetGuildInfo = function(unit) local g = guilds[unit]; if g then return g[1], g[2], g[3] end end
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
	local function sent(t)
		local found = {}
		for _, s in ipairs(H.sent) do
			local _, e = AceSerializer:Deserialize(s.text)
			if e and e.t == t then found[#found + 1] = { target = s.target, p = e.p, sid = e.sid } end
		end
		return found
	end

	H.reload("fresh")
	leader = ME
	world()
	local Sessions, Candidates, Responses, Comm = ALC.Sessions, ALC.Candidates, ALC.Responses, ALC.Comm
	local Win, Resp = ALC.CouncilWindow, ALC.ResponseWindow
	ALC.Settings:AddCouncilMember("Veyra Moo")

	----------------------------------------------------------------------------
	-- Notes and ranks in the protocol
	----------------------------------------------------------------------------
	local realKnown = ALC.Protocol.knownResponse
	ALC.Protocol.knownResponse = function(id) return id == "BIS" or id == "UPGRADE" or id == "MINOR" or id == "OFFSPEC" or id == "PASS" end
	local resp = ALC.Protocol.specs.RESPONSE
	check("an answer may carry a note", resp.validate({ item = 1, response = "BIS", gear = {}, note = "Main spec, for progress" }) == true)
	check("a note is optional", resp.validate({ item = 1, response = "BIS", gear = {} }) == true)
	check("an empty note is refused", resp.validate({ item = 1, response = "BIS", gear = {}, note = "" }) == false)
	check("a note cannot hold an escape sequence", resp.validate({ item = 1, response = "BIS", gear = {}, note = "|cffff0000red" }) == false)
	check("a note cannot hold a control character", resp.validate({ item = 1, response = "BIS", gear = {}, note = "a\nb" }) == false)
	check("100 letters is the longest note", resp.validate({ item = 1, response = "BIS", gear = {}, note = string.rep("x", 100) }) == true
		and resp.validate({ item = 1, response = "BIS", gear = {}, note = string.rep("x", 101) }) == false)
	check("a note must be text", resp.validate({ item = 1, response = "BIS", gear = {}, note = 5 }) == false)

	local cand = ALC.Protocol.specs.CANDIDATE_UPDATE
	local base = function() return { item = 1, name = "Veyra Moo", class = "WARRIOR", response = "BIS", gear = {} } end
	local c1 = base() c1.note, c1.rank, c1.rankIndex = "hello", "Raider", 4
	check("a candidate may carry a note and a rank", cand.validate(c1, ME) == true)
	local c2 = base() c2.rank = "Raider"
	check("a rank needs its number", cand.validate(c2, ME) == false)
	local c3 = base() c3.rank, c3.rankIndex = "Raider", 21
	check("rank numbers go up to 20", cand.validate(c3, ME) == false)
	local c4 = base() c4.rank, c4.rankIndex = "Ra|cffff0000ider", 3
	check("a rank name cannot hold an escape sequence", cand.validate(c4, ME) == false)
	local c5 = base() c5.rank, c5.rankIndex = "Raider", -1
	check("rank numbers are not negative", cand.validate(c5, ME) == false)
	local c6 = base() c6.note = "|Hitem:1|h[x]|h"
	check("a candidate's note cannot hold a link", cand.validate(c6, ME) == false)
	ALC.Protocol.knownResponse = realKnown

	----------------------------------------------------------------------------
	-- Guild ranks
	----------------------------------------------------------------------------
	local rank, index = ALC:GetGuildRank("party1")
	check("a guild mate has a rank", rank == "Raider" and index == 4)
	check("the loot master's own rank is found", ALC:GetGuildRank("player") == "Officer")
	check("a player of another guild has none", ALC:GetGuildRank("party2") == nil)
	check("an unknown unit has none", ALC:GetGuildRank("party3") == nil and ALC:GetGuildRank(nil) == nil)
	guilds.party1[2] = "Bad|cffff0000Rank"
	check("a rank name with an escape sequence is dropped", ALC:GetGuildRank("party1") == nil)
	guilds.party1[2] = "Raider"
	guilds.party1[3] = 99
	check("a rank number out of range is dropped", ALC:GetGuildRank("party1") == nil)
	guilds.party1[3] = 4

	----------------------------------------------------------------------------
	-- A session with notes and ranks
	----------------------------------------------------------------------------
	check("start a session with two items", Sessions:StartItems({ 200, 201 }) == true)
	local sid = Sessions:GetActiveSid()
	check("the notes start empty", Responses:GetNote(1) == "" and Responses:GetNote(2) == "")
	check("every row of the response window has its own note field", Resp.rows[1].note ~= nil and Resp.rows[2].note ~= nil
		and Resp.rows[1].note:GetText() == "" and Resp.rows[1].note ~= Resp.rows[2].note)
	check("it sits to the right of the last button", Resp.rows[1].note:IsShown() and Resp.rows[1].note.point[3] == "LEFT" and Resp.rows[1].note.point[4] > 230)

	H.sent = {}
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "BIS", gear = {}, note = "Need it for the raid" }), "WHISPER", "Veyra Moo")
	local entry = Candidates:Get("Veyra Moo", 1)
	check("the loot master keeps the note", entry.note == "Need it for the raid")
	check("and looks up the guild rank", entry.rank == "Raider" and entry.rankIndex == 4)
	local update = sent("CANDIDATE_UPDATE")[1]
	check("the council update carries both", update ~= nil and update.p.note == "Need it for the raid" and update.p.rank == "Raider" and update.p.rankIndex == 4)
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "UPGRADE", gear = {} }), "WHISPER", "Kaelis Moo")
	check("a player of another guild has a note-less, rank-less entry", Candidates:Get("Kaelis Moo", 1).rank == nil and Candidates:Get("Kaelis Moo", 1).note == nil)
	H.sent = {}
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "BIS", gear = {}, note = "Need it for the raid" }), "WHISPER", "Veyra Moo")
	check("the same answer again tells nobody", #sent("CANDIDATE_UPDATE") == 0)
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "BIS", gear = {}, note = "Changed my mind" }), "WHISPER", "Veyra Moo")
	check("a changed note is passed on", #sent("CANDIDATE_UPDATE") == 1 and Candidates:Get("Veyra Moo", 1).note == "Changed my mind")
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
	check("an answer without a note removes it", Candidates:Get("Veyra Moo", 1).note == nil)
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "BIS", gear = {}, note = "Need it for the raid" }), "WHISPER", "Veyra Moo")

	-- Our own answers carry the note.
	check("cleaning a note", Responses.CleanNote("  a|cff b\n c  ") == "acff b c" and Responses.CleanNote(string.rep("y", 200)) == string.rep("y", 100) and Responses.CleanNote(nil) == "")
	-- (In the game, clicking a button takes the focus from a field, which saves what is in it.)
	Resp.rows[1].note:SetText("  Note one  ")
	Resp.rows[1].note.scripts.OnEditFocusLost(Resp.rows[1].note)
	Resp.rows[2].note:SetText("Note two")
	Resp.rows[2].note.scripts.OnEditFocusLost(Resp.rows[2].note)
	check("what was written stays in its own field", Responses:GetNote(1) == "Note one" and Responses:GetNote(2) == "Note two")
	H.sent = {}
	Resp.rows[2].buttons[2].scripts.OnClick(Resp.rows[2].buttons[2]) -- Upgrade on the second item
	check("what is written on a row goes with the answer to that item", Responses:GetNote(2) == "Note two" and Candidates:Get(ME, 2).note == "Note two")
	check("the other item has nothing yet", Candidates:Get(ME, 1) == nil)
	Resp.rows[1].buttons[3].scripts.OnClick(Resp.rows[1].buttons[3]) -- Minor on the first
	check("each item carries its own note", Candidates:Get(ME, 1).note == "Note one" and Candidates:Get(ME, 2).note == "Note two" and Candidates:Get(ME, 1).rank == "Officer")
	check("and the notes are kept per item", Responses:GetNote(1) == "Note one" and Responses:GetNote(2) == "Note two")
	H.sent = {}
	Resp.rows[1].note:SetText("Note one, changed")
	Resp.rows[1].note.scripts.OnEnterPressed(Resp.rows[1].note)
	check("Enter sends a changed note with the answer already given, for that item only", Candidates:Get(ME, 1).note == "Note one, changed"
		and Candidates:Get(ME, 2).note == "Note two")
	Resp.rows[2].note:SetText("")
	Resp.rows[2].note.scripts.OnEnterPressed(Resp.rows[2].note)
	check("an emptied note is taken away", Candidates:Get(ME, 2).note == nil and Responses:GetNote(2) == "")
	Resp.rows[2].note:SetText("typed, then clicked")
	Resp.rows[2].buttons[1].scripts.OnClick(Resp.rows[2].buttons[1])
	check("a note that is still in the field goes with the click", Candidates:Get(ME, 2).note == "typed, then clicked" and Candidates:Get(ME, 2).response == "BIS")
	check("SetNote says whether an answer was sent", Responses:SetNote(1, "again") == true and (function()
		return Responses:SetNote(1, "x") == true
	end)())
	Responses:SetNote(2, "Note two")
	check("a note written before answering waits for the answer", (function()
		local session = Sessions:GetSession()
		return #session.items == 2 and Responses:SetDraftNote(1, "draft") == nil and Responses:GetNote(1) == "draft"
	end)())
	Responses:SetNote(1, "Note one, changed")
	Resp.rows[1].note:SetText("written but not sent")
	Resp.rows[1].note.scripts.OnEditFocusLost(Resp.rows[1].note)
	check("leaving the field keeps what was written for the next answer", Responses:GetNote(1) == "written but not sent" and Candidates:Get(ME, 1).note == "Note one, changed")
	Responses:SetNote(1, "Note one, changed")

	-- The council window shows them.
	Win:Show()
	local rows = Win.rows
	local byName = {}
	for _, row in ipairs(rows) do if row:IsShown() and row.candidate then byName[row.candidate] = row end end
	check("the rank is in the row", byName["Veyra Moo"].rank:GetText() == "Raider")
	check("a player without rank has an empty cell", byName["Kaelis Moo"].rank:GetText() == "")
	check("the note is in the row", byName["Veyra Moo"].note:GetText() == "Need it for the raid" and byName["Kaelis Moo"].note:GetText() == "")
	byName["Veyra Moo"].noteButton.scripts.OnEnter(byName["Veyra Moo"].noteButton)
	check("hovering the note shows all of it", GameTooltip.text == "Note")
	byName["Veyra Moo"].noteButton.scripts.OnLeave(byName["Veyra Moo"].noteButton)

	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Jonatan Moo")
	local function order()
		local names = {}
		for _, e in ipairs(Win:GetVisible()) do names[#names + 1] = e.name end
		return table.concat(names, ",")
	end
	Win:SetSortMode("rank")
	check("by rank, the highest rank first, players without one last", order() == "Tester Moo,Veyra Moo,Jonatan Moo,Kaelis Moo")
	check("the sort button says so", Win.rows[1].parent.sort.label:GetText() == "Sort: By rank")
	Win:SetSortMode("response")

	-- Snapshots carry them.
	H.clock = H.clock + 100
	H.sent = {}
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Veyra Moo")
	local snap = sent("STATE_SNAPSHOT")[1]
	local got
	for _, cnd in ipairs(snap.p.candidates) do if cnd.name == "Veyra Moo" and cnd.item == 1 then got = cnd end end
	check("a snapshot has notes and ranks", got ~= nil and got.note == "Need it for the raid" and got.rank == "Raider" and got.rankIndex == 4)

	Sessions:Cancel("done")
	check("the notes are forgotten with the session", Responses:GetNote(1) == "" and Responses:GetNote(2) == "")

	----------------------------------------------------------------------------
	-- Custom answer buttons: the protocol
	----------------------------------------------------------------------------
	local start = ALC.Protocol.specs.SESSION_START
	local function startWith(responses)
		return { items = { { itemID = 200, itemString = "item:200" } }, council = { ME }, lm = ME, responses = responses }
	end
	local function set(...)
		local list = {}
		for i, id in ipairs({ ... }) do list[i] = { id = id, label = id:sub(1, 1) .. id:sub(2):lower(), color = "4dbf66" } end
		return list
	end
	check("a session may bring its own buttons", start.validate(startWith(set("MAIN", "SIDE", "PASS")), ME) == true)
	check("the buttons are optional", start.validate(startWith(nil), ME) == true)
	check("two buttons are the fewest", start.validate(startWith(set("PASS")), ME) == false and start.validate(startWith(set("MAIN", "PASS")), ME) == true)
	check("eight are the most", start.validate(startWith(set("A", "B", "C", "D", "E", "F", "G", "PASS")), ME) == true
		and start.validate(startWith(set("A", "B", "C", "D", "E", "F", "G", "H", "PASS")), ME) == false)
	check("PASS has to be there and last", start.validate(startWith(set("MAIN", "SIDE")), ME) == false
		and start.validate(startWith(set("PASS", "MAIN")), ME) == false)
	check("ids cannot repeat", start.validate(startWith(set("MAIN", "MAIN", "PASS")), ME) == false)
	check("ids are capital letters and digits", start.validate(startWith(set("main", "PASS")), ME) == false
		and start.validate(startWith(set("MA IN", "PASS")), ME) == false and start.validate(startWith(set("1MAIN", "PASS")), ME) == false
		and start.validate(startWith(set("X1", "PASS")), ME) == true)
	check("ids are at most 10 long", start.validate(startWith(set("ABCDEFGHIJK", "PASS")), ME) == false)
	local bad = set("MAIN", "PASS")
	bad[1].label = "Thirteen chars"
	check("labels are at most 12 letters", start.validate(startWith(bad), ME) == false)
	bad[1].label = "A|cffff0000B"
	check("a label cannot hold an escape sequence", start.validate(startWith(bad), ME) == false)
	bad[1].label = ""
	check("a label cannot be empty", start.validate(startWith(bad), ME) == false)
	bad[1].label, bad[1].color = "Main", "zzzzzz"
	check("a colour is six hex digits", start.validate(startWith(bad), ME) == false)
	bad[1].color = "4dbf6"
	check("five is not enough", start.validate(startWith(bad), ME) == false)
	check("the list must be a list", start.validate(startWith("MAIN"), ME) == false and start.validate(startWith({ "MAIN", "PASS" }), ME) == false)

	local snapshotSpec = ALC.Protocol.specs.STATE_SNAPSHOT
	local snap = startWith(set("MAIN", "SIDE", "PASS"))
	snap.candidates = { { item = 1, name = "Veyra Moo", class = "WARRIOR", response = "MAIN", gear = {} } }
	snap.yourResponses = { { item = 1, response = "SIDE" } }
	check("a snapshot's answers are checked against its own buttons", snapshotSpec.validate(snap, ME) == true)
	snap.candidates[1].response = "BIS"
	check("an answer that is not one of them is refused", snapshotSpec.validate(snap, ME) == false)
	snap.candidates[1].response = "MAIN"
	snap.yourResponses[1].response = "BIS"
	check("also our own", snapshotSpec.validate(snap, ME) == false)
	local oldSnap = startWith(nil)
	oldSnap.candidates = { { item = 1, name = "Veyra Moo", class = "WARRIOR", response = "BIS", gear = {} } }
	check("without buttons the default five apply", snapshotSpec.validate(oldSnap, ME) == true)

	----------------------------------------------------------------------------
	-- Custom answer buttons: the loot master's set
	----------------------------------------------------------------------------
	check("the default set is the five", #Responses:GetConfiguredSet() == 5 and Responses:GetConfiguredSet()[1].id == "BIS" and Responses:GetConfiguredSet()[5].id == "PASS")
	check("a copy of it can be changed without harm", (function()
		local copy = Responses:GetDefaultSet()
		copy[1].label = "Hacked"
		copy[1].color[1] = 0
		return Responses:GetDefaultSet()[1].label == "BiS" and Responses:GetDefaultSet()[1].color[1] == 0.30
	end)())
	check("cleaning a label", Responses.CleanLabel("  Main|cff spec  ") == "Maincff spec" and Responses.CleanLabel("   ") == nil
		and Responses.CleanLabel("A very long label indeed") == "A very long " and Responses.CleanLabel(nil) == nil)
	local wire = Responses.ToWire(Responses:GetDefaultSet())
	check("the wire form has hex colours", wire[1].color == "4dbf66" and wire[5].id == "PASS" and #wire == 5)
	local back = Responses.FromWire(wire)
	check("and comes back the same, within a rounding", #back == 5 and back[1].id == "BIS" and math.abs(back[1].color[1] - 0.30) < 0.005 and math.abs(back[2].color[3] - 0.95) < 0.005)
	check("no wire form means the default five", #Responses.FromWire(nil) == 5)

	local mine = {
		{ id = "MAIN", label = "Main spec", color = { 0.30, 0.75, 0.40 } },
		{ id = "SIDE", label = "Side grade", color = { 0.35, 0.60, 0.95 } },
		{ id = "PASS", label = "No thanks", color = { 0.50, 0.52, 0.58 } },
	}
	check("a valid set is saved", Responses:SetConfiguredSet(mine) == true and #Responses:GetConfiguredSet() == 3 and Responses:GetConfiguredSet()[1].label == "Main spec")
	local okBadSet, whyBad = Responses:SetConfiguredSet({ { id = "MAIN", label = "Main", color = { 1, 1, 1 } } })
	check("an invalid set is refused and changes nothing", okBadSet == false and whyBad ~= nil and #Responses:GetConfiguredSet() == 3)
	check("PASS must be last", Responses:SetConfiguredSet({ mine[3], mine[1] }) == false)
	check("labels are checked", Responses:SetConfiguredSet({ { id = "MAIN", label = "", color = { 1, 1, 1 } }, mine[3] }) == false)
	check("colours are checked", Responses:SetConfiguredSet({ { id = "MAIN", label = "Main", color = { 1, 1 } }, mine[3] }) == false)
	check("the saved copy is separate from the one given", (function()
		mine[1].label = "Changed after"
		return Responses:GetConfiguredSet()[1].label == "Main spec"
	end)())
	mine[1].label = "Main spec"
	check("nil goes back to the default", Responses:SetConfiguredSet(nil) == true and #Responses:GetConfiguredSet() == 5)
	Responses:SetConfiguredSet(mine)

	----------------------------------------------------------------------------
	-- The settings window: the Buttons tab
	----------------------------------------------------------------------------
	local SW = ALC.SettingsWindow
	SW:Show()
	SW:SetTab("responses")
	local frame = SW.responseRows[1].parent
	local rows = SW.responseRows
	check("the tab lists the three buttons", rows[1]:IsShown() and rows[3]:IsShown() and not rows[4]:IsShown() and rows[1].edit:GetText() == "Main spec" and rows[3].edit:GetText() == "No thanks")
	check("the count is shown", frame.responseCount:GetText() == "3/8")
	check("PASS cannot be removed", not rows[3].remove:IsShown() and rows[1].remove:IsShown())
	check("the arrows do not move things past PASS", rows[2].down.available == false and rows[1].up.available == false and rows[1].down.available == true)
	check("the other tabs' settings are hidden", not frame.minimap:IsShown() and not frame.input:IsShown())
	rows[1].edit:SetText("  Primary  ")
	rows[1].edit.scripts.OnEnterPressed(rows[1].edit)
	check("Enter saves a new label", Responses:GetConfiguredSet()[1].label == "Primary" and rows[1].edit:GetText() == "Primary")
	rows[2].edit:SetText("Alt|cffff0000!")
	rows[2].edit.scripts.OnEnterPressed(rows[2].edit)
	check("a label is cleaned and cut to 12 letters", Responses:GetConfiguredSet()[2].label == "Altcffff0000")
	rows[2].edit:SetText("   ")
	rows[2].edit.scripts.OnEnterPressed(rows[2].edit)
	check("an empty label goes back", Responses:GetConfiguredSet()[2].label == "Altcffff0000" and rows[2].edit:GetText() == "Altcffff0000")
	rows[2].edit:SetText("Side grade")
	rows[2].edit.scripts.OnEnterPressed(rows[2].edit)
	local colorBefore = Responses:GetConfiguredSet()[1].color[1] .. "," .. Responses:GetConfiguredSet()[1].color[2]
	rows[1].color.scripts.OnClick(rows[1].color)
	check("a click on the colour steps through the palette", Responses:GetConfiguredSet()[1].color[1] .. "," .. Responses:GetConfiguredSet()[1].color[2] ~= colorBefore
		and Responses:GetConfiguredSet()[1].color[1] == 0.35)
	check("the swatch follows", rows[1].color.swatch.colorTexture[1] == 0.35)
	rows[1].down.scripts.OnClick(rows[1].down)
	check("a button moves down", Responses:GetConfiguredSet()[1].id == "SIDE" and Responses:GetConfiguredSet()[2].id == "MAIN" and rows[1].edit:GetText() == "Side grade")
	rows[2].down.scripts.OnClick(rows[2].down)
	check("but not below PASS", Responses:GetConfiguredSet()[3].id == "PASS" and Responses:GetConfiguredSet()[2].id == "MAIN")
	rows[2].up.scripts.OnClick(rows[2].up)
	check("and back up", Responses:GetConfiguredSet()[1].id == "MAIN")
	frame.addResponse.scripts.OnClick(frame.addResponse)
	check("Add button puts a new one before PASS", #Responses:GetConfiguredSet() == 4 and Responses:GetConfiguredSet()[3].id == "X1" and Responses:GetConfiguredSet()[4].id == "PASS"
		and Responses:GetConfiguredSet()[3].label == "New button" and rows[4]:IsShown())
	frame.addResponse.scripts.OnClick(frame.addResponse)
	check("a second new one gets its own id", Responses:GetConfiguredSet()[4].id == "X2" and #Responses:GetConfiguredSet() == 5)
	rows[3].remove.scripts.OnClick(rows[3].remove)
	rows[3].remove.scripts.OnClick(rows[3].remove)
	check("removing works", #Responses:GetConfiguredSet() == 3 and Responses:GetConfiguredSet()[3].id == "PASS")
	rows[2].remove.scripts.OnClick(rows[2].remove)
	check("the last button besides PASS stays", #Responses:GetConfiguredSet() == 2 and rows[1].remove:IsShown())
	rows[1].remove.scripts.OnClick(rows[1].remove)
	check("and cannot be removed", #Responses:GetConfiguredSet() == 2 and frame.responseFeedback:GetText():find("at least one button", 1, true) ~= nil)
	for _ = 1, 7 do frame.addResponse.scripts.OnClick(frame.addResponse) end
	check("eight buttons at most", #Responses:GetConfiguredSet() == 8 and frame.responseCount:GetText() == "8/8")
	frame.addResponse.scripts.OnClick(frame.addResponse)
	check("a ninth is refused with a reason", #Responses:GetConfiguredSet() == 8 and frame.responseFeedback:GetText():find("At most 8", 1, true) ~= nil)
	frame.resetResponses.scripts.OnClick(frame.resetResponses)
	check("Back to the default gives the five again", #Responses:GetConfiguredSet() == 5 and Responses:GetConfiguredSet()[1].id == "BIS" and rows[5]:IsShown() and not rows[6]:IsShown())
	SW:Hide()
	Responses:SetConfiguredSet(mine)

	----------------------------------------------------------------------------
	-- A session with custom buttons
	----------------------------------------------------------------------------
	H.sent = {}
	check("start a session with the custom buttons", Sessions:StartItems({ 200 }) == true)
	sid = Sessions:GetActiveSid()
	check("the session start carries them", #sent("SESSION_START")[1].p.responses == 3 and sent("SESSION_START")[1].p.responses[1].id == "MAIN")
	check("the session has them", #Sessions:GetResponses() == 3 and Sessions:HasResponse("MAIN") and Sessions:HasResponse("PASS") and not Sessions:HasResponse("BIS"))
	check("a copy of them cannot change the session", (function()
		Sessions:GetResponses()[1].label = "Hacked"
		Sessions:GetSession().responses[1].id = "HACKED"
		return Sessions:GetResponses()[1].label == "Main spec" and Sessions:HasResponse("MAIN")
	end)())
	check("changing the loot master's set does not change the running session", (function()
		Responses:SetConfiguredSet(Responses:GetDefaultSet())
		local same = #Sessions:GetResponses() == 3
		Responses:SetConfiguredSet(mine)
		return same
	end)())

	local rr = Resp.rows[1]
	check("the response window has three buttons, named and coloured as set", rr.buttons[1]:IsShown() and rr.buttons[3]:IsShown() and not rr.buttons[4]:IsShown() and not rr.buttons[5]:IsShown()
		and rr.buttons[1].label:GetText() == "Main spec" and rr.buttons[2].label:GetText() == "Side grade" and rr.buttons[3].label:GetText() == "No thanks"
		and rr.buttons[1].responseId == "MAIN" and rr.buttons[3].responseId == "PASS" and math.abs(rr.buttons[2].label.textColor[3] - 0.95) < 0.01)
	check("its buttons are as wide as the longest label needs", rr.buttons[1].w >= 60 and rr.buttons[1].w == rr.buttons[3].w)
	rr.buttons[1].scripts.OnClick(rr.buttons[1])
	check("a click answers with that button", Responses:GetMyResponse(1) == "MAIN" and Candidates:Get(ME, 1).response == "MAIN" and rr.buttons[1].selected == true)
	check("the status names the answer as labelled", rr.parent.status:GetText():find("Main spec", 1, true) ~= nil)
	local okOld, msgOld = Responses:Send("BIS", 1)
	check("an answer that is not a button is refused", okOld == false and msgOld == "Unknown response." and Responses:GetMyResponse(1) == "MAIN")
	check("the loot master refuses one from somebody else", Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo") == false
		and Candidates:Get("Veyra Moo", 1) == nil)
	check("and accepts a real one", Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "SIDE", gear = {}, note = "custom" }), "WHISPER", "Veyra Moo") == true
		and Candidates:Get("Veyra Moo", 1).response == "SIDE")
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "PASS", gear = {} }), "WHISPER", "Kaelis Moo")
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "MAIN", gear = {} }), "WHISPER", "Jonatan Moo")

	Win:Show()
	local names = {}
	for _, e in ipairs(Win:GetVisible()) do names[#names + 1] = e.name end
	check("the table follows the order of the buttons", table.concat(names, ",") == "Jonatan Moo,Tester Moo,Veyra Moo")
	local chip
	for _, row in ipairs(Win.rows) do if row:IsShown() and row.candidate == "Veyra Moo" then chip = row.chip end end
	check("the chips show the custom label and colour", chip.label:GetText() == "Side grade" and math.abs(chip.label.textColor[3] - 0.95) < 0.01)
	local labels = {}
	for _, item in ipairs(Win:GetRowMenu("Veyra Moo")) do labels[#labels + 1] = item.label end
	check("Change response lists the custom buttons", table.concat(labels, "|") == "Vote|Award|Change response|Main spec|Side grade|No thanks|Remove from consideration")
	check("Set response refuses an answer that is not a button", Candidates:SetResponse("Veyra Moo", "BIS", 1) == false and Candidates:SetResponse("Veyra Moo", "MAIN", 1) == true)
	check("and Remove from consideration still means PASS", Candidates:SetResponse("Veyra Moo", "PASS", 1) == true and Candidates:Get("Veyra Moo", 1).response == "PASS")
	Candidates:SetResponse("Veyra Moo", "SIDE", 1)

	-- A snapshot carries the buttons.
	H.clock = H.clock + 100
	H.sent = {}
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Veyra Moo")
	local snapMsg = sent("STATE_SNAPSHOT")[1]
	check("a snapshot has the session's buttons", snapMsg ~= nil and #snapMsg.p.responses == 3 and snapMsg.p.responses[2].label == "Side grade")

	-- The award keeps the label.
	H.sent = {}
	check("award the item", ALC.Awards:Award("Veyra Moo", 1) == true)
	check("the announcement uses the label", ALC.Awards:GetLastAnnouncement():find("Side grade", 1, true) ~= nil)
	local log = ALC.Awards:GetLog()
	check("the log keeps the answer's label and colour", log[#log].response == "SIDE" and log[#log].responseLabel == "Side grade" and math.abs(log[#log].responseColor[3] - 0.95) < 0.01)
	Responses:SetConfiguredSet(nil)
	Win:ShowHistory()
	local historyRow = Win.historyRows[1]
	check("the history still shows it after the buttons were changed", historyRow.chip.label:GetText() == "Side grade" and math.abs(historyRow.chip.label.textColor[3] - 0.95) < 0.01)
	Win:Hide()
	check("the loot master's own buttons are the default again, the ended session's are gone", not Sessions:IsActive() and #Responses:GetSet() == 5)
	Responses:SetConfiguredSet(mine)

	-- A restored session keeps its buttons.
	check("start another session", Sessions:StartItems({ 200 }) == true)
	local sid4 = Sessions:GetActiveSid()
	Responses:SetConfiguredSet(nil) -- the loot master changes the buttons meanwhile
	local savedDb = H.snapshotDB()
	H.reload(savedDb)
	leader = ME
	world()
	ALC.Council:Refresh()
	ALC.Sessions:OnEnteringWorld(false, true)
	check("after a reload the session has the buttons it started with", ALC.Sessions:GetActiveSid() == sid4 and #ALC.Sessions:GetResponses() == 3
		and ALC.Sessions:HasResponse("MAIN") and not ALC.Sessions:HasResponse("BIS"))
	ALC.Sessions:Cancel("done")

	-- Somebody else's session: the client gets the buttons in SESSION_START.
	leader = "Veyra Moo"
	world()
	ALC.Council:Refresh()
	local startMsg2 = { items = { { itemID = 200, itemString = "item:200" } }, council = { "Veyra Moo", ME }, lm = "Veyra Moo",
		responses = { { id = "GO", label = "Go for it", color = "ff8800" }, { id = "PASS", label = "Pass", color = "808080" } } }
	check("the session is accepted", ALC.Comm:Process(env("SESSION_START", "sidZ", 1, startMsg2), "PARTY", "Veyra Moo") == true)
	local rz = ALC.ResponseWindow.rows[1]
	check("our response window shows the loot master's buttons", ALC.ResponseWindow:IsShown() and rz.buttons[1].label:GetText() == "Go for it" and rz.buttons[2].label:GetText() == "Pass"
		and not rz.buttons[3]:IsShown() and rz.buttons[1].label.textColor[1] == 1)
	H.sent = {}
	rz.buttons[1].scripts.OnClick(rz.buttons[1])
	local ours = sent("RESPONSE")[1]
	check("our answer uses its id", ours ~= nil and ours.p.response == "GO" and ours.target == "Veyra Moo")
	check("a window that sizes itself to the buttons is not narrower than before", ALC.ResponseWindow.rows[1].parent.w >= 600)
	ALC.Comm:Process(env("SESSION_CANCEL", "sidZ", 2, { reason = "done" }), "PARTY", "Veyra Moo")

	-- Put the environment back.
	UnitIsConnected = nil
	GetGuildInfo = nil
	H.inGroup = false
	C_Item.GetItemInfo = function() end
	C_Item.GetItemInfoInstant = nil
	C_Item.RequestLoadItemDataByID = nil
end

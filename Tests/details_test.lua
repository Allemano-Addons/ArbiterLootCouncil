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
	check("the note starts empty", Responses:GetNote() == "")
	check("the response window has a note field", Resp.rows[1].parent.note ~= nil and Resp.rows[1].parent.note:GetText() == "")

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
	Resp.rows[1].parent.note:SetText("  My alt is a healer  ")
	H.sent = {}
	Resp.rows[2].buttons[2].scripts.OnClick(Resp.rows[2].buttons[2]) -- Upgrade on the second item
	check("what is written goes with the answer", Responses:GetNote() == "My alt is a healer" and Candidates:Get(ME, 2).note == "My alt is a healer")
	check("only for the item answered", Candidates:Get(ME, 1) == nil)
	Responses:Send("MINOR", 1)
	check("and with the next answer too", Candidates:Get(ME, 1).note == "My alt is a healer" and Candidates:Get(ME, 1).rank == "Officer")
	H.sent = {}
	local resent = Responses:SetNote("Changed for real")
	check("Enter sends the note again with every answer given", resent == 2 and Candidates:Get(ME, 1).note == "Changed for real" and Candidates:Get(ME, 2).note == "Changed for real")
	Resp.rows[1].parent.note:SetText("From the field")
	Resp.rows[1].parent.note.scripts.OnEnterPressed(Resp.rows[1].parent.note)
	check("the field does the same on Enter", Responses:GetNote() == "From the field" and Candidates:Get(ME, 2).note == "From the field")

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
	check("the note is forgotten with the session", Responses:GetNote() == "")

	-- Put the environment back.
	UnitIsConnected = nil
	GetGuildInfo = nil
	H.inGroup = false
	C_Item.GetItemInfo = function() end
	C_Item.GetItemInfoInstant = nil
	C_Item.RequestLoadItemDataByID = nil
end

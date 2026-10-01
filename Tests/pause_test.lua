-- Pause / Resume: no new answers, votes or awards while paused; the answer timer stops.


return function(check, H)
	local ME = "Tester Moo"
	local env = H.env

	local db = {
		[200] = { "Crown of Destruction", 4, "INVTYPE_HEAD" },
		[201] = { "Belt of Might", 4, "INVTYPE_WAIST" },
		[202] = { "Ring of Focus", 4, "INVTYPE_FINGER" },
	}
	local leader = ME
	local function items()
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
	end
	local function world(grouped)
		local units = {
			player = { "Tester", "Moo", "ROGUE" },
			party1 = { "Veyra", "Moo", "WARRIOR" },
			party2 = { "Kaelis", "Moo", "HUNTER" },
		}
		UnitName = function(unit) local u = units[unit]; if u then return u[1], u[2] end end
		UnitClass = function(unit) local u = units[unit]; if u then return u[3], u[3] end end
		items()
		H.inGroup = grouped and true or false
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
	world(true)
	local Sessions, Awards, Comm, Settings = ALC.Sessions, ALC.Awards, ALC.Comm, ALC.Settings
	local Win, Resp, Responses, Candidates, Voting = ALC.CouncilWindow, ALC.ResponseWindow, ALC.Responses, ALC.Candidates, ALC.Voting
	Settings:AddCouncilMember("Veyra Moo")
	H.setupFrames()
	H.deferTimers = true
	H.timers = {}
	local function run() H.runTimers() end

	local paused = {}
	local listener = {}
	ALC.Events.Register(listener, "ALC_SESSION_PAUSED", function(_, flag) paused[#paused + 1] = flag end)

	check("nothing to pause without a session", (Sessions:SetPaused(true)) == false)
	Sessions:StartItems({ 200, 201 })
	run()
	local sid = Sessions:GetActiveSid()
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
	run()
	check("not paused at the start", Sessions:IsPaused() == false)
	check("resuming a session that is not paused is refused", (Sessions:SetPaused(false)) == false)

	local ok = Sessions:SetPaused(true)
	run()
	check("the loot master pauses", ok == true and Sessions:IsPaused() == true and #paused == 1 and paused[1] == true)
	check("pausing twice is refused", (Sessions:SetPaused(true)) == false)
	check("the session copy says so", Sessions:GetSession().paused == true)

	-- What is blocked
	local sent, message = Responses:Send("BIS", 2)
	check("answering is refused", sent == false and message == "The session is paused.")
	Comm:Process(env("RESPONSE", sid, nil, { item = 2, response = "UPGRADE", gear = {} }), "WHISPER", "Kaelis Moo")
	check("an answer that arrives anyway is ignored", Candidates:Get("Kaelis Moo", 2) == nil)
	local voted, vmessage = Voting:Cast("Veyra Moo", 1)
	check("voting is refused", voted == false and vmessage == "The session is paused.")
	Comm:Process(env("VOTE", sid, nil, { item = 1, candidate = "Veyra Moo" }), "WHISPER", "Veyra Moo")
	check("a vote that arrives anyway is ignored", Voting:GetVotes("Veyra Moo", 1) == 0)
	local awarded, amessage = Awards:Award("Veyra Moo", 1)
	check("awarding is refused", awarded == false and amessage:find("paused", 1, true) ~= nil)
	check("the item is still open", Sessions:IsItemOpen(1))

	-- The windows
	Win:Show()
	Win:Refresh()
	local frame = Win.rows[1].parent
	check("the council window shows Resume and the tag", frame.pause.label:GetText() == "Resume" and frame.pausedTag:IsShown())
	check("no vote or award buttons on a row", Win.rows[1].award:IsShown() == false and Win.rows[1].vote:IsShown() == false)
	local menu = Win:GetRowMenu("Veyra Moo")
	local labels = {}
	for _, item in ipairs(menu) do labels[#labels + 1] = item.label end
	local text = table.concat(labels, "|")
	check("the menu has no Vote or Award while paused", text:find("Vote", 1, true) == nil and text:find("Award", 1, true) == nil)
	check("but the loot master can still change an answer", text:find("Change response", 1, true) ~= nil)
	Resp:Show()
	check("the response window says why", Resp:IsShown())

	-- Resume
	check("the Resume button resumes", (function()
		frame.pause.scripts.OnClick(frame.pause)
		run()
		return Sessions:IsPaused() == false and #paused == 2 and paused[2] == false
	end)())
	Win:Refresh()
	check("the button says Pause again, the tag is gone", frame.pause.label:GetText() == "Pause" and not frame.pausedTag:IsShown())
	check("answering works again", Responses:Send("BIS", 2) == true)
	run()
	check("voting works again", Voting:Cast("Veyra Moo", 1) == true)
	check("awarding works again", Awards:Award("Veyra Moo", 1) == true)
	run()

	-- The answer timer stops while paused
	Sessions:Cancel("done")
	run()
	H.timers = {}
	Settings:SetTimerEnabled(true)
	Settings:SetTimerSeconds(120)
	H.clock = 9000
	Sessions:StartItems({ 200 })
	run()
	local sid2 = Sessions:GetActiveSid()
	local running = H.timers
	H.timers = {}
	check("the timer runs: 120 s", math.floor(Sessions:GetTimeLeft() + 0.5) == 120)
	H.clock = 9030
	Sessions:SetPaused(true)
	run()
	check("paused after 30 s: 90 s left", math.floor(Sessions:GetTimeLeft() + 0.5) == 90)
	H.clock = 9500
	check("time passes, the timer does not", math.floor(Sessions:GetTimeLeft() + 0.5) == 90)
	H.timers = running
	run() -- the old timer wakes up
	check("the old timer does not end it", Sessions:IsTimeUp() == false and Sessions:IsActive())
	local built
	ALC.Events.Register(listener, "ALC_SESSION_SNAPSHOT_BUILD", function(_, payload) built = payload end)
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Veyra Moo")
	check("a snapshot carries the pause and the time left", built ~= nil and built.paused == true and built.timerLeft == 90)

	-- A reload while paused
	local saved = H.snapshotDB()
	check("the loot master saves the pause", saved.global.sessionStore.session.paused == true and saved.global.sessionStore.session.pausedLeft == 90)
	H.reload(saved)
	leader = ME
	world(true)
	H.setupFrames()
	H.deferTimers = true
	H.timers = {}
	H.clock = 9600
	ALC.Sessions:OnEnteringWorld(false, true)
	run()
	check("after a reload it is still paused with the time kept", ALC.Sessions:IsPaused() and math.floor(ALC.Sessions:GetTimeLeft() + 0.5) == 90)
	H.timers = {}
	ALC.Sessions:SetPaused(false)
	run()
	check("resumed: the time runs from 90 s", ALC.Sessions:IsPaused() == false and math.floor(ALC.Sessions:GetTimeLeft() + 0.5) == 90)
	local after = H.timers
	H.timers = {}
	H.clock = 9700
	for _, fn in ipairs(after) do fn() end
	check("and it ends when it runs out", ALC.Sessions:IsTimeUp() == true)
	ALC.Sessions:Cancel("done")
	run()

	-- The command, a finished session, protocol
	ALC.Settings:SetTimerEnabled(false)
	ALC.Sessions:StartItems({ 200 })
	run()
	H.slash("pause")
	run()
	check("/alc pause pauses", ALC.Sessions:IsPaused() == true)
	H.slash("pause")
	run()
	check("and again resumes", ALC.Sessions:IsPaused() == false)
	local sid3 = ALC.Sessions:GetActiveSid()
	ALC.Comm:Process(env("RESPONSE", sid3, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
	run()
	ALC.Awards:Award("Veyra Moo", 1)
	run()
	check("a session with everything awarded cannot be paused", (ALC.Sessions:SetPaused(true)) == false)

	local spec = ALC.Protocol.specs.SESSION_PAUSE
	check("protocol: loot master only", spec ~= nil and spec.allowed == "lm")
	check("protocol: true and false are fine", spec.validate({ paused = true }) == true and spec.validate({ paused = false }) == true)
	check("protocol: anything else is refused", spec.validate({ paused = "yes" }) == false and spec.validate({}) == false)
	local start = ALC.Protocol.specs.SESSION_START
	check("protocol: SESSION_START accepts a paused flag", start.validate({ items = { { itemID = 200, itemString = "item:200" } }, council = { ME }, lm = ME, paused = true }, ME) == true)
	check("protocol: and refuses a bad one", start.validate({ items = { { itemID = 200, itemString = "item:200" } }, council = { ME }, lm = ME, paused = 1 }, ME) == false)
end

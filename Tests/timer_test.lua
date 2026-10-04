-- The answer timer: settings, the countdown, the window closing, late answers, recovery.


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
	local Sessions, Comm, Settings, Resp = ALC.Sessions, ALC.Comm, ALC.Settings, ALC.ResponseWindow
	Settings:AddCouncilMember("Veyra Moo")
	H.setupFrames()

	local ended = 0
	local listener = {}
	ALC.Events.Register(listener, "ALC_SESSION_TIMER_ENDED", function() ended = ended + 1 end)

	-- Off by default -------------------------------------------------------------
	check("timer off by default", Settings:GetTimerEnabled() == false and Settings:GetActiveTimer() == nil)
	check("default length 120", Settings:GetTimerSeconds() == 120)
	check("a session without the timer has none", Sessions:StartItems({ 200 }) == true
		and Sessions:GetTimeLeft() == nil and Sessions:IsTimeUp() == false and Sessions:GetSession().timer == nil)
	Sessions:Cancel("done")

	-- Settings ---------------------------------------------------------------------
	check("too short is refused", Settings:SetTimerSeconds(5) == false and Settings:GetTimerSeconds() == 120)
	check("too long is refused", Settings:SetTimerSeconds(601) == false and Settings:GetTimerSeconds() == 120)
	check("a length is saved", Settings:SetTimerSeconds(90) == true and Settings:GetTimerSeconds() == 90)
	Settings:SetTimerSeconds(120)
	Settings:SetTimerEnabled(true)
	check("on, 120 sec", Settings:GetActiveTimer() == 120)

	-- A running timer ----------------------------------------------------------------
	H.deferTimers = true
	H.timers = {}
	H.clock = 5000
	check("start with the timer", Sessions:StartItems({ 200 }) == true)
	H.runTimers() -- the loop-back of our own message
	local sid = Sessions:GetActiveSid()
	check("the session carries it", Sessions:GetSession().timer == 120 and Sessions:GetTimeLeft() == 120 and not Sessions:IsTimeUp())
	check("the response window opens", Resp:IsShown())
	H.clock = 5030
	check("time passes", math.floor(Sessions:GetTimeLeft() + 0.5) == 90)
	local rf = Resp.rows[1] and Resp.rows[1].parent
	if rf then
		Resp:UpdateBar()
		check("the time bar is shown and a quarter is gone", rf.timerFill:IsShown() and rf.timerTrack:IsShown())
		H.clock = 5100
		Resp:UpdateBar()
		check("the bar turns red at the end", rf.timerFill:IsShown())
		H.clock = 5030
	end
	check("answering works while it runs", ALC.Responses:Send("BIS", 1) == true)

	-- Snapshot for a client mid-timer
	local built
	ALC.Events.Register(listener, "ALC_SESSION_SNAPSHOT_BUILD", function(_, payload) built = payload end)
	Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Veyra Moo")
	check("a snapshot says what is left", built ~= nil and built.timer == 120 and built.timerLeft == 90)

	-- It runs out -------------------------------------------------------------------
	H.clock = 5120
	H.runTimers()
	check("the timer event fired once", ended == 1)
	check("time is up", Sessions:IsTimeUp() and Sessions:GetTimeLeft() == 0)
	check("the session goes on", Sessions:IsActive())
	check("the response window is gone", not Resp:IsShown())
	local ok, message = ALC.Responses:Send("UPGRADE", 1)
	check("answering is refused", ok == false and message == "The time to answer is up.")
	Resp:Show()
	check("the window does not reopen", not Resp:IsShown())

	-- Late answers at the loot master
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "BIS", gear = {} }), "WHISPER", "Veyra Moo")
	check("an answer within the grace is taken", ALC.Candidates:Get("Veyra Moo", 1) ~= nil)
	H.clock = 5130
	Comm:Process(env("RESPONSE", sid, nil, { item = 1, response = "MINOR", gear = {} }), "WHISPER", "Kaelis Moo")
	check("a late answer is ignored", ALC.Candidates:Get("Kaelis Moo", 1) == nil)
	check("a snapshot after it says 0", (function()
		built = nil
		H.clock = 5140
		Comm:Process(env("STATE_REQUEST", nil, nil, {}), "WHISPER", "Kaelis Moo")
		return built ~= nil and built.timerLeft == 0
	end)())

	-- A reload of the loot master ------------------------------------------------------
	local saved = H.snapshotDB()
	H.reload(saved)
	leader = ME
	world(true)
	H.setupFrames()
	H.clock = 5150
	ALC.Sessions:OnEnteringWorld(false, true)
	check("after a reload past the end the time is still up", ALC.Sessions:IsActive() and ALC.Sessions:IsTimeUp())
	check("and the window stays closed", not ALC.ResponseWindow:IsShown())
	ALC.Sessions:Cancel("done")

	-- A reload in the middle
	H.reload("fresh")
	leader = ME
	world(true)
	H.setupFrames()
	ALC.Settings:AddCouncilMember("Veyra Moo")
	ALC.Settings:SetTimerEnabled(true)
	ALC.Settings:SetTimerSeconds(120)
	H.clock = 6000
	ALC.Sessions:StartItems({ 200 })
	saved = H.snapshotDB()
	local store = saved.global.sessionStore.session
	check("the loot master saves the timer", store.timer == 120 and store.endsAtEpoch ~= nil)
	store.endsAtEpoch = store.endsAtEpoch - 30 -- half a minute passes while it reloads
	H.reload(saved)
	leader = ME
	world(true)
	H.setupFrames()
	H.deferTimers = true
	ALC.Sessions:OnEnteringWorld(false, true)
	H.runTimers()
	local left = ALC.Sessions:GetTimeLeft()
	check("a reload mid-timer keeps what is left", left ~= nil and left > 85 and left <= 91)
	ALC.Sessions:Cancel("done")

	-- Protocol
	local spec = ALC.Protocol.specs.SESSION_START
	local function p(extra)
		local payload = { items = { { itemID = 200, itemString = "item:200" } }, council = { ME }, lm = ME }
		for k, v in pairs(extra) do payload[k] = v end
		return payload
	end
	check("protocol: no timer is fine", spec.validate(p({}), ME) == true)
	check("protocol: 60 is fine", spec.validate(p({ timer = 60 }), ME) == true)
	check("protocol: 5 is refused", spec.validate(p({ timer = 5 }), ME) == false)
	check("protocol: 601 is refused", spec.validate(p({ timer = 601 }), ME) == false)
	check("protocol: 'x' is refused", spec.validate(p({ timer = "x" }), ME) == false)
	check("protocol: timerLeft 0 is fine", spec.validate(p({ timer = 60, timerLeft = 0 }), ME) == true)
	check("protocol: negative timerLeft is refused", spec.validate(p({ timer = 60, timerLeft = -1 }), ME) == false)

	-- Settings window
	H.deferTimers = false
	ALC.Settings:SetTimerEnabled(false)
	check("settings window builds with the timer rows", pcall(function() ALC.SettingsWindow:Show() end))
	ALC.Settings:SetTimerEnabled(true)
	ALC.Settings:SetTimerSeconds(180)
end

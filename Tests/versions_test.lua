-- The version check: comparing versions, the group list, the window.


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
	local Comm, Win = ALC.Comm, ALC.VersionWindow
	H.setupFrames()
	ALC.version = "0.2.0-alpha2"

	-- Comparing versions
	local cmp = Comm.CompareVersions
	check("the same version", cmp("0.2.0-alpha2", "0.2.0-alpha2") == 0)
	check("a higher number is newer", cmp("0.2.1", "0.2.0") == 1 and cmp("0.1.9", "0.2.0") == -1 and cmp("1.0.0", "0.9.9") == 1)
	check("10 is higher than 9", cmp("0.10.0", "0.9.0") == 1)
	check("a release is newer than its pre-release", cmp("0.2.0", "0.2.0-alpha2") == 1 and cmp("0.2.0-alpha2", "0.2.0") == -1)
	check("pre-releases compare by name", cmp("0.2.0-alpha2", "0.2.0-alpha1") == 1 and cmp("0.2.0-beta1", "0.2.0-alpha9") == 1)
	check("a missing number counts as 0", cmp("0.2", "0.2.0") == 0)
	check("a leading v is fine", cmp("v0.3.0", "0.2.0") == 1)
	check("junk does not crash", cmp(nil, "0.2.0") == -1 and cmp("x", "y") == 0)

	-- The group before anybody has answered
	local rows = Comm:GetVersionRows()
	check("the group is listed: you and two more", #rows == 3)
	check("you are marked with your own version", (function()
		for _, r in ipairs(rows) do
			if r.name == ME then return r.status == "self" and r.addon == "0.2.0-alpha2" and r.proto == 2 end
		end
	end)())
	check("the others have not replied", (function()
		for _, r in ipairs(rows) do
			if r.name == "Veyra Moo" then return r.status == "none" and r.addon == nil end
		end
	end)())

	-- Replies
	Comm:Process(env("VERSION", nil, nil, { addon = "0.2.0-alpha2", proto = 2 }), "WHISPER", "Veyra Moo")
	Comm:Process(env("VERSION", nil, nil, { addon = "0.1.0", proto = 2 }), "WHISPER", "Kaelis Moo")
	rows = Comm:GetVersionRows()
	local by = {}
	for _, r in ipairs(rows) do by[r.name] = r end
	check("the same version is up to date", by["Veyra Moo"].status == "ok")
	check("a lower version is older", by["Kaelis Moo"].status == "older" and by["Kaelis Moo"].addon == "0.1.0")
	Comm:Process(env("VERSION", nil, nil, { addon = "0.3.0", proto = 2 }), "WHISPER", "Kaelis Moo")
	check("a higher one is newer", (function()
		for _, r in ipairs(Comm:GetVersionRows()) do if r.name == "Kaelis Moo" then return r.status == "newer" end end
	end)())
	Comm:GetVersions()["kaelis moo"] = { name = "Kaelis Moo", addon = nil, proto = 1, seen = 0 }
	rows = Comm:GetVersionRows()
	check("another protocol is incompatible, and sorts first", rows[1].name == "Kaelis Moo" and rows[1].status == "incompatible" and rows[1].proto == 1)
	check("then those who did not reply, up to date last", rows[#rows].status == "self")
	Comm:GetVersions()["kaelis moo"] = { name = "Kaelis Moo", addon = "0.2.0-alpha2", proto = 2, seen = 0 }
	Comm:GetVersions()["veyra moo"] = nil
	rows = Comm:GetVersionRows()
	check("no reply sorts before up to date", rows[1].name == "Veyra Moo" and rows[1].status == "none" and rows[2].status == "ok")

	-- The window
	local events = 0
	local listener = {}
	ALC.Events.Register(listener, "ALC_VERSIONS_CHANGED", function() events = events + 1 end)
	H.deferTimers = true
	H.timers = {}
	H.sent = {}
	Win:Show()
	check("the window opens", Win:IsShown())
	local frame = Win.rows[1].parent
	check("it shows the rows with names and statuses", Win.rows[1]:IsShown() and Win.rows[1].name:GetText() == "Veyra Moo" and Win.rows[1].status:GetText() == "Waiting...")
	check("the summary counts the addon", frame.summary:GetText():find("^2 of 3 have the addon") ~= nil)
	check("your own version is stated", frame.mine:GetText() == "Your version: 0.2.0-alpha2 (protocol v2)")
	check("it says it is asking", frame.note:GetText() == "Asking the group...")
	H.clock = H.clock + 10
	H.runTimers()
	check("after the wait: no reply, and the summary says so", Win.rows[1].status:GetText() == "No reply: no addon?" and frame.summary:GetText():find("1 no reply", 1, true) ~= nil)
	Comm:Process(env("VERSION", nil, nil, { addon = "0.2.0-alpha2", proto = 2 }), "WHISPER", "Veyra Moo")
	check("a late reply updates the window by itself", events >= 1 and frame.summary:GetText():find("^3 of 3 have the addon") ~= nil)
	check("and the row says up to date", (function()
		for _, row in ipairs(Win.rows) do
			if row:IsShown() and row.name:GetText() == "Veyra Moo" then return row.status:GetText() == "Up to date" end
		end
	end)())
	frame.refresh.scripts.OnClick(frame.refresh)
	check("Ask again waits for replies again", frame.note:GetText() == "Asking the group...")
	Win:Hide()
	check("the window closes", not Win:IsShown())

	-- A session starts: who did not reply?
	H.inGroup = true
	Comm.GetGroupNames = function()
		local names = {}
		for _, unit in ipairs(ALC:GroupUnits()) do
			local name = ALC:UnitFullName(unit)
			if name then names[#names + 1] = name end
		end
		return names
	end
	Comm:InvalidateRoster()
	local known = Comm:GetVersions()
	known["veyra moo"], known["kaelis moo"] = nil, nil
	H.runTimers() -- what is held back from before (a lost timer would leave the message queue stuck)
	H.deferTimers = true
	H.timers = {}
	H.sent = {}
	local said = #H.chat
	check("the check asks the group", Comm:CheckAddonCoverage() == true and #H.sent >= 1)
	Comm:Process(env("VERSION", nil, nil, { addon = "0.2.0-alpha2", proto = 2 }), "WHISPER", "Veyra Moo")
	H.clock = H.clock + 10
	H.runTimers()
	check("and tells who did not reply", #H.chat > said and H.chat[#H.chat]:find("Kaelis Moo", 1, true) ~= nil and H.chat[#H.chat]:find("Veyra", 1, true) == nil)
	Comm:Process(env("VERSION", nil, nil, { addon = "0.2.0-alpha2", proto = 2 }), "WHISPER", "Kaelis Moo")
	said = #H.chat
	Comm:CheckAddonCoverage()
	H.clock = H.clock + 10
	H.runTimers()
	check("when everybody replied nothing is said", #H.chat == said)
	-- starting a session does it
	known["kaelis moo"] = nil
	H.sent = {}
	said = #H.chat
	ALC.Sessions:StartItems({ 200 })
	H.clock = H.clock + 10
	H.runTimers() -- the session starts when its own message comes back
	H.clock = H.clock + 10
	H.runTimers() -- and the version check it asks for runs out
	local warned = false
	for i = said + 1, #H.chat do if H.chat[i]:find("did not reply", 1, true) and H.chat[i]:find("Kaelis Moo", 1, true) then warned = true end end
	check("a session the loot master starts asks and warns", warned)
	ALC.Sessions:Cancel("test")
	H.runTimers()
	ALC.Settings:SetWarnMissing(false)
	known["kaelis moo"] = nil
	H.sent = {}
	said = #H.chat
	ALC.Sessions:StartItems({ 200 })
	H.clock = H.clock + 10
	H.runTimers()
	local asked = false
	for _, sent in ipairs(H.sent) do if sent.text and sent.text:find("VERSION_REQUEST", 1, true) then asked = true end end
	local warnedOff = false
	for i = said + 1, #H.chat do if H.chat[i]:find("did not reply", 1, true) then warnedOff = true end end
	check("with the warning turned off nothing is asked or said", not warnedOff and not asked)
	ALC.Sessions:Cancel("test")
	H.runTimers()
	ALC.Settings:SetWarnMissing(true)
	check("the setting is on by default and remembered", ALC.Settings:GetWarnMissing() == true)
	H.deferTimers = false

	-- Out of a group
	H.inGroup = false
	Comm.GetGroupNames = function() return {} end
	Comm:InvalidateRoster()
	Win:Show()
	check("alone: you are the only row and it says so", Win.rows[1]:IsShown() and not Win.rows[2]:IsShown() and frame.summary:GetText() == "You are not in a group.")
	Win:Hide()

	-- The launcher and the command
	local Launcher = ALC.Launcher
	Launcher:Show()
	local entry
	for _, row in ipairs(Launcher.rows) do if row.entry.label == "Versions" then entry = row end end
	check("the launcher has a Versions entry", entry ~= nil and entry.enabled == true)
	entry.scripts.OnClick(entry)
	check("it opens the window", Win:IsShown() and not Launcher:IsShown())
	H.slash("versions")
	check("/alc versions closes it again", not Win:IsShown())
	H.slash("versions")
	check("and opens it", Win:IsShown())
	Win:Hide()
end

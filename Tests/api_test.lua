-- The API for other addons: the version and the list of extensions. Nothing else in ALC depends on it.

return function(check)
	check("the API has a version", type(ALC.API_VERSION) == "number" and ALC.API_VERSION >= 1)
	check("HasAPI says yes to the version we have", ALC.HasAPI(ALC.API_VERSION) and ALC.HasAPI(1))
	check("and no to a later one", not ALC.HasAPI(ALC.API_VERSION + 1))
	check("and no to something that is not a number", not ALC.HasAPI("1") and not ALC.HasAPI(nil))

	check("no extension is there to begin with", #ALC.GetExtensions() == 0 and ALC.GetExtension("ASR") == nil)

	local fired = {}
	local owner = {}
	ALC.Events.Register(owner, "ALC_API_EXTENSION_REGISTERED", function(_, name, version) fired[#fired + 1] = name .. " " .. version end)

	check("an extension can register", ALC.RegisterExtension("ASR", "0.1.0") == true)
	check("and is found with its version", ALC.GetExtension("ASR").version == "0.1.0")
	check("the event says so", fired[1] == "ASR 0.1.0")
	check("a number is a fine version", ALC.RegisterExtension("Other", 2) == true and ALC.GetExtension("Other").version == "2")
	check("the list is sorted by name", ALC.GetExtensions()[1].name == "ASR" and ALC.GetExtensions()[2].name == "Other")
	ALC.RegisterExtension("ASR", "0.2.0")
	check("registering again replaces the version", ALC.GetExtension("ASR").version == "0.2.0" and #ALC.GetExtensions() == 2)

	local copy = ALC.GetExtension("ASR")
	copy.version = "hacked"
	check("what comes back is a copy", ALC.GetExtension("ASR").version == "0.2.0")

	local ok, reason = ALC.RegisterExtension("", "1")
	check("a name is needed", ok == false and reason ~= nil)
	check("a version is needed", ALC.RegisterExtension("X", nil) == false and ALC.GetExtension("X") == nil)
	check("a table is not a name", ALC.RegisterExtension({}, "1") == false)

	-- API 5: ways to start a session
	check("the API is at least 5", ALC.HasAPI(5))
	check("no start mode to begin with", #ALC.GetStartModes() == 0 and ALC.GetStartMode("SR") == nil)
	check("a start mode needs an id, a label and a start function",
		ALC.RegisterStartMode({ label = "SR", start = function() end }) == false
		and ALC.RegisterStartMode({ id = "SR", start = function() end }) == false
		and ALC.RegisterStartMode({ id = "SR", label = "SR" }) == false
		and ALC.RegisterStartMode("SR") == false and #ALC.GetStartModes() == 0)
	local changed = 0
	ALC.Events.Register(owner, "ALC_START_MODES_CHANGED", function() changed = changed + 1 end)
	check("a start mode registers", ALC.RegisterStartMode({ id = "SR", label = "SR", name = "Soft Reserve", color = "9B7BFF", start = function() return true end }) == true)
	check("and is listed and announced", #ALC.GetStartModes() == 1 and ALC.GetStartMode("SR").name == "Soft Reserve" and changed == 1)
	ALC.RegisterStartMode({ id = "XX", label = "XX", start = function() end })
	check("the name falls back to the label", ALC.GetStartMode("XX").name == "XX")
	ALC.UnregisterStartMode("XX")

	-- API 5: entries in the window menu
	check("no launcher entry to begin with", #ALC.GetLauncherEntries() == 0)
	check("a launcher entry needs an id, a label and an open function",
		ALC.RegisterLauncherEntry({ label = "R", open = function() end }) == false
		and ALC.RegisterLauncherEntry({ id = "r", open = function() end }) == false
		and ALC.RegisterLauncherEntry({ id = "r", label = "R" }) == false and #ALC.GetLauncherEntries() == 0)
	local menuChanged = 0
	ALC.Events.Register(owner, "ALC_LAUNCHER_CHANGED", function() menuChanged = menuChanged + 1 end)
	local opened = 0
	check("an entry registers", ALC.RegisterLauncherEntry({ id = "asr-results", label = "Results", icon = "summary", section = "Soft Reserve", color = "9B7BFF",
		open = function() opened = opened + 1 end }) == true)
	check("and is listed, available by default", #ALC.GetLauncherEntries() == 1 and ALC.GetLauncherEntries()[1].available() == true and menuChanged == 1)
	check("the same id again replaces it", ALC.RegisterLauncherEntry({ id = "asr-results", label = "Results 2", open = function() end }) == true
		and #ALC.GetLauncherEntries() == 1 and ALC.GetLauncherEntries()[1].label == "Results 2")
	ALC.RegisterLauncherEntry({ id = "asr-results", label = "Results", icon = "summary", section = "Soft Reserve", color = "9B7BFF",
		available = function() return false, "Needs a session." end, open = function() opened = opened + 1 end })
	ALC.RegisterLauncherEntry({ id = "asr-import", label = "Import", icon = "note", section = "Soft Reserve", color = "9B7BFF", open = function() opened = opened + 1 end })
	local Launcher = ALC.Launcher
	Launcher:Show(nil)
	local headings, entryRows = 0, 0
	for _, row in ipairs(Launcher.rows) do
		if row.heading == "Soft Reserve" then headings = headings + 1 end
		if row.entry and row.entry.id == "asr-results" then entryRows = entryRows + 1 end
	end
	check("the menu has a heading for the addon and a row for each entry", headings == 1 and entryRows == 1 and #Launcher.entries + 3 <= #Launcher.rows)
	local resultsRow
	for _, row in ipairs(Launcher.rows) do if row.entry and row.entry.id == "asr-results" then resultsRow = row end end
	check("an entry that is not available is greyed out with its reason", resultsRow.enabled == false and resultsRow.reason == "Needs a session.")
	local importRow
	for _, row in ipairs(Launcher.rows) do if row.entry and row.entry.id == "asr-import" then importRow = row end end
	check("an available one is clickable", importRow.enabled == true)
	importRow.scripts.OnClick(importRow)
	check("and does what it says", opened == 1 and not Launcher:IsShown())
	Launcher:Show(nil)
	resultsRow.scripts.OnClick(resultsRow)
	check("a greyed-out one does nothing", opened == 1)
	Launcher:Hide()
	ALC.UnregisterLauncherEntry("asr-results")
	ALC.UnregisterLauncherEntry("asr-import")
	Launcher:Show(nil)
	local stillThere = false
	for _, row in ipairs(Launcher.rows) do if row.entry and row.entry.id and row.entry.id:find("asr", 1, true) then stillThere = true end end
	check("removed entries leave the menu", #ALC.GetLauncherEntries() == 0 and not stillThere)
	Launcher:Hide()
	ALC.UnregisterStartMode("SR")
	check("a start mode can be removed", #ALC.GetStartModes() == 0 and changed == 4)

	ALC.Events.UnregisterAll(owner)
end

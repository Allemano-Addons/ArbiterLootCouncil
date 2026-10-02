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

	ALC.Events.UnregisterAll(owner)
end

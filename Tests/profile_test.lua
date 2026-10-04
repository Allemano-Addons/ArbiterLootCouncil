-- Profile: the loot master's settings as a text to share, read back, checked, previewed, applied and undone.

return function(check, H)
	H.reload("fresh")
	local S, P = ALC.Settings, ALC.Profile

	-- A set of settings to share
	S:AddCouncilMember("Veyra Moo")
	S:AddCouncilMember("Kaelis Moo")
	S:SetQualityThreshold(3)
	S:SetAutoTrade(false)
	S:SetRollsEnabled(true)
	S:SetDisenchanter("Ashvane Moo")
	S:SetRecentDays(14)
	S:SetTimerEnabled(true)
	S:SetTimerSeconds(60)
	S:SetLogReminder(500)
	local mine = {
		{ id = "BIS", label = "Best", color = { 0.1, 0.8, 0.3 } },
		{ id = "MS", label = "Main", color = { 0.9, 0.6, 0.1 } },
		{ id = "PASS", label = "Pass", color = { 0.5, 0.5, 0.5 } },
	}
	check("the answer buttons can be set", ALC.Responses:SetConfiguredSet(mine) == true)

	local text = P:Export()
	check("the text starts with the profile mark and a check number", text:match("^ALCP1:%x%x%x%x:[%w%-_]+$") ~= nil)
	local profile, why = P:Parse(text)
	check("it reads back", profile ~= nil and why == nil)
	check("with the council, threshold, timer and buttons", #profile.values.council == 2 and profile.values.qualityThreshold == 3
		and profile.values.timerSeconds == 60 and profile.values.responses and #profile.values.responses == 3)
	check("and it says nothing would change on the same settings", #P:Changes(profile) == 0)

	-- Another loot master has other settings
	S:RemoveCouncilMember("Veyra Moo")
	S:AddCouncilMember("Somebody Else")
	S:SetQualityThreshold(4)
	S:SetAutoTrade(true)
	S:SetDisenchanter(nil)
	S:SetTimerSeconds(120)
	ALC.Responses:SetConfiguredSet(nil)
	local before = P:Snapshot()

	local changes = P:Changes(profile)
	local byKey = {}
	for _, ch in ipairs(changes) do byKey[ch.key] = ch end
	check("the changes list what differs", byKey.council and byKey.qualityThreshold and byKey.autoTrade and byKey.disenchanter and byKey.timerSeconds and byKey.responses)
	check("and not what is the same", byKey.rollsEnabled == nil and byKey.recentDays == nil)
	check("a change has a label and a before and after", byKey.qualityThreshold.from ~= byKey.qualityThreshold.to and byKey.autoTrade.label == "Auto trade")
	check("the council change counts the new and the removed", byKey.council.to:find("2 names", 1, true) and byKey.council.to:find("1 new", 1, true) and byKey.council.to:find("1 removed", 1, true))
	check("nothing was changed by looking", S:GetQualityThreshold() == 4 and S:GetAutoTrade() == true)

	-- Apply
	local count = P:Apply(profile)
	check("applying changes the settings", count == #changes and S:GetQualityThreshold() == 3 and S:GetAutoTrade() == false and S:GetDisenchanter() == "Ashvane Moo"
		and S:GetTimerSeconds() == 60 and #S:GetCouncil() == 2 and S:GetCouncil()[1] == "Veyra Moo")
	check("the buttons came along", #ALC.Responses:GetConfiguredSet() == 3 and ALC.Responses:GetConfiguredSet()[1].label == "Best")
	check("there is something to undo", P:UndoTime() ~= nil)

	-- Undo
	local undone = P:Undo()
	check("undo puts the old settings back", undone == count and S:GetQualityThreshold() == 4 and S:GetAutoTrade() == true and S:GetDisenchanter() == nil
		and S:GetTimerSeconds() == 120 and #S:GetCouncil() == 2 and S:GetCouncil()[1] == "Kaelis Moo" and S:GetCouncil()[2] == "Somebody Else")
	check("the buttons are back to the default", #ALC.Responses:GetConfiguredSet() == 5)
	local again, reason = P:Undo()
	check("a second undo has nothing to do", again == nil and reason ~= nil and P:UndoTime() == nil)
	check("all of it is as before", select(1, (function() local now = P:Snapshot() for k, v in pairs(before) do
		if type(v) ~= "table" and now[k] ~= v then return false end end return true end)()))

	-- Text that is damaged
	local function refused(t) local p, r = P:Parse(t) return p == nil and type(r) == "string" end
	check("an empty text is not a profile", refused("") and refused("   \n  "))
	check("another text is not a profile", refused("hello") and refused("ALCP1:zzzz:abc"))
	check("a cut text is refused", refused(text:sub(1, #text - 5)))
	local flipped = text:sub(1, #text - 3) .. (text:sub(#text - 2, #text - 2) == "A" and "B" or "A") .. text:sub(#text - 1)
	check("a changed text is refused", refused(flipped))
	check("line breaks and spaces from a chat are fine", P:Parse(text:sub(1, 30) .. "\n  " .. text:sub(31, 80) .. " \n" .. text:sub(81)) ~= nil)
	check("a huge text is refused", refused(string.rep("A", 20000)))

	-- Text that comes from somebody who means harm: everything is checked
	local evil = P.Pack({ v = 1, data = {
		council = { "|cffff0000Red Name", "Good Name", "Good Name", string.rep("x", 80), 5, "A", "Line\nBreak" },
		qualityThreshold = 9, autoTrade = "yes", timerSeconds = 5, recentDays = 31, logReminder = 3, disenchanter = "|Hbad|h",
		responses = { { id = "bis", label = "x", color = { 2, 0, 0 } }, { id = "PASS", label = "Pass", color = { 1, 1, 1 } } },
		unknownSetting = "ignored",
	} })
	local hostile = P:Parse(evil)
	check("a hostile text still reads", hostile ~= nil)
	local v = hostile.values
	check("names with control characters and bars are dropped, the rest kept once", #v.council == 1 and v.council[1] == "Good Name")
	check("values out of range are dropped", v.qualityThreshold == nil and v.autoTrade == nil and v.timerSeconds == nil and v.recentDays == nil and v.logReminder == nil)
	check("a bad disenchanter name is dropped", v.disenchanter == nil)
	check("bad buttons are dropped", v.responses == nil)
	check("unknown settings are ignored", v.unknownSetting == nil)
	check("a profile of a newer format is refused", refused(P.Pack({ v = 2, data = {} })))
	check("a text that is not a profile table is refused", refused(P.Pack({ hello = 1 })))

	-- Settings of other addons come along when they have an id
	local state = { on = false, mode = "off" }
	ALC.RegisterSettingsSection({ id = "TEST", name = "Test addon", rows = {
		{ tab = "lm", id = "flag", type = "check", label = "A flag", get = function() return state.on end, set = function(x) state.on = x end },
		{ tab = "lm", id = "mode", type = "choice", label = "A mode", options = { { label = "Off", value = "off" }, { label = "All", value = "all" } },
			get = function() return state.mode end, set = function(x) state.mode = x end },
		{ tab = "lm", type = "check", label = "No id", get = function() return true end, set = function() end },
		{ tab = "everyone", id = "personal", type = "check", label = "Personal", get = function() return true end, set = function() end },
	} })
	state.on, state.mode = true, "all"
	local withExt = P:Export()
	state.on, state.mode = false, "off"
	local ext = P:Parse(withExt)
	check("a row with an id on the loot master tab is in the profile", ext.values["x:TEST:flag"] == true and ext.values["x:TEST:mode"] == "all")
	check("a row without an id or on another tab is not", ext.values["x:TEST:personal"] == nil and next({}) == nil)
	P:Apply(ext)
	check("it is applied to the addon", state.on == true and state.mode == "all")
	local badExt = P:Parse(P.Pack({ v = 1, data = { ["x:TEST:mode"] = "nonsense", ["x:TEST:flag"] = "x" } }))
	check("a value the addon does not offer is dropped", badExt.values["x:TEST:mode"] == nil and badExt.values["x:TEST:flag"] == nil)
	ALC.UnregisterSettingsSection("TEST")

	-- The window
	local Win = ALC.ProfileWindow
	Win:ShowExport()
	local f = Win:GetFrame()
	check("the export window shows the text", Win:IsShown() and f.block.edit:GetText():match("^ALCP1:") ~= nil and not f.apply:IsShown())
	Win:ShowImport()
	check("the import window starts empty with Apply off", Win:IsShown() and f.apply:IsShown() and f.apply.available == false)
	f.block.edit:SetText("not a profile")
	f.block.edit.scripts.OnTextChanged(f.block.edit, true)
	check("a wrong text is told so", f.status:GetText() ~= "" and f.apply.available == false)
	S:SetQualityThreshold(4)
	f.block.edit:SetText(text)
	f.block.edit.scripts.OnTextChanged(f.block.edit, true)
	check("a right text shows the changes and turns Apply on", f.apply.available == true and f.changes:GetText():find("Loot quality threshold", 1, true) ~= nil)
	Win:Apply()
	check("Apply imports it and closes the window", S:GetQualityThreshold() == 3 and not Win:IsShown())
	P:Undo()
end

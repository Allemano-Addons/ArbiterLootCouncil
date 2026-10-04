-- Sections that other addons add to the Settings window (ALC.RegisterSettingsSection). A fresh reload: the window builds
-- its rows once, so the section has to be there before it is first opened.

return function(check, H)
	H.reload("fresh")
	local Win = ALC.SettingsWindow
	local base = #ALC.GetSettingsSections() -- ALC's own section (the award log) is there from the start

	-- What is refused
	local function refused(def) local ok, why = ALC.RegisterSettingsSection(def) return ok == false and why ~= nil end
	local function row(extra)
		local r = { tab = "everyone", type = "check", label = "Show it", get = function() return true end, set = function() end }
		for k, v in pairs(extra or {}) do r[k] = v end
		return r
	end
	check("a section needs an id, a name and rows", refused({ name = "X", rows = { row() } }) and refused({ id = "X", rows = { row() } })
		and refused({ id = "X", name = "X" }) and refused({ id = "X", name = "X", rows = {} }) and refused("X"))
	check("a row needs a tab, a known type and a label", refused({ id = "X", name = "X", rows = { row({ tab = "council" }) } })
		and refused({ id = "X", name = "X", rows = { row({ type = "slider" }) } }) and refused({ id = "X", name = "X", rows = { row({ label = "" }) } }))
	check("a check needs get and set", refused({ id = "X", name = "X", rows = { row({ get = false }) } }) and refused({ id = "X", name = "X", rows = { row({ set = false }) } }))
	check("a choice needs two to six options with a label and a value",
		refused({ id = "X", name = "X", rows = { row({ type = "choice", options = { { label = "a", value = 1 } } }) } })
		and refused({ id = "X", name = "X", rows = { row({ type = "choice", options = { { label = "a", value = 1 }, { label = "b" } } }) } }))
	check("an action needs onClick", refused({ id = "X", name = "X", rows = { row({ type = "action", onClick = false }) } }))
	check("nothing refused was kept", #ALC.GetSettingsSections() == base)

	-- A section with all three kinds of row, on both tabs
	local state = { tooltip = true, keep = 15, announce = "off", cleared = 0, disenchant = false }
	local registered = ALC.RegisterSettingsSection({
		id = "ASR", name = "Soft Reserve", color = "9B7BFF",
		rows = {
			{ tab = "everyone", type = "check", label = "Show who reserved it", tip = "Tooltips",
				get = function() return state.tooltip end, set = function(on) state.tooltip = on end },
			{ tab = "everyone", type = "choice", label = "Results kept",
				options = { { label = "5", value = 5 }, { label = "10", value = 10 }, { label = "15", value = 15 } },
				get = function() return state.keep end, set = function(value) state.keep = value end },
			{ tab = "everyone", type = "action", label = "Clear saved results", confirm = "Click again to clear",
				onClick = function() state.cleared = state.cleared + 1 end },
			{ tab = "lm", type = "check", label = "Hand it to the disenchanter",
				get = function() return state.disenchant end, set = function(on) state.disenchant = on end },
			{ tab = "lm", type = "choice", label = "Announce", options = { { label = "Off", value = "off" }, { label = "Winners", value = "winners" } },
				get = function() return state.announce end, set = function(value) state.announce = value end },
		},
	})
	check("a good section is accepted and listed", registered == true and #ALC.GetSettingsSections() == base + 1 and ALC.GetSettingsSections()[base + 1].name == "Soft Reserve")
	check("the same id again replaces it", ALC.RegisterSettingsSection({ id = "ASR", name = "Soft Reserve", color = "9B7BFF", rows = ALC.GetSettingsSections()[base + 1].rows }) == true
		and #ALC.GetSettingsSections() == base + 1)

	-- The window draws them
	H.setupFrames()
	local okShow = pcall(function() Win:Show() end)
	check("the Settings window builds with the section", okShow and Win:IsShown() and #Win.extRefresh == 5) -- the four of this section and the award log's choice
	local function find(group, text)
		for _, widget in ipairs(Win.groups[group]) do
			if widget.label and widget.label.GetText and widget.label:GetText() == text then return widget end
		end
	end
	local tooltipBox = find("everyone", "Show who reserved it")
	local keep10 = find("everyone", "10")
	local clearButton = find("everyone", "Clear saved results")
	local deBox = find("session", "Hand it to the disenchanter")
	local winners = find("session", "Winners")
	check("the rows are there on the tabs they named", tooltipBox and keep10 and clearButton and deBox and winners)
	check("a check shows what the addon says", tooltipBox.checked == true and deBox.checked == false)
	check("a choice marks the current value", find("everyone", "15").selected == true and keep10.selected == false and find("session", "Off").selected == true)

	-- Using them
	tooltipBox.scripts.OnClick(tooltipBox)
	check("clicking a check tells the addon", state.tooltip == false)
	keep10.scripts.OnClick(keep10)
	check("clicking a choice sets the value and moves the mark", state.keep == 10 and keep10.selected == true and find("everyone", "15").selected == false)
	winners.scripts.OnClick(winners)
	check("a choice on the loot master tab works too", state.announce == "winners" and winners.selected == true and find("session", "Off").selected == false)
	H.deferTimers = true -- the "click again" waits four seconds before it gives up
	H.timers = {}
	clearButton.scripts.OnClick(clearButton)
	check("an action with a confirmation asks first", state.cleared == 0 and clearButton.label:GetText() == "Click again to clear")
	clearButton.scripts.OnClick(clearButton)
	check("and does it on the second click", state.cleared == 1 and clearButton.label:GetText() == "Clear saved results")
	clearButton.scripts.OnClick(clearButton)
	H.runTimers()
	H.deferTimers = false
	check("an unanswered question goes away by itself", clearButton.label:GetText() == "Clear saved results" and state.cleared == 1)

	-- The tabs show only their own rows
	Win:SetTab("everyone")
	check("the everyone tab shows its rows and not the loot master's", tooltipBox:IsShown() and not deBox:IsShown())
	Win:SetTab("session")
	check("the loot master tab shows its rows and not the other's", deBox:IsShown() and not tooltipBox:IsShown())

	-- A row that fails does not break the window
	ALC.RegisterSettingsSection({ id = "BAD", name = "Bad", rows = { row({ label = "Broken", get = function() error("boom") end }) } })
	check("a get that fails leaves the window working", pcall(function() Win:Refresh() end))
	ALC.UnregisterSettingsSection("BAD")
	ALC.UnregisterSettingsSection("ASR")
	check("a section can be removed", #ALC.GetSettingsSections() == base)
	Win:Hide()
end

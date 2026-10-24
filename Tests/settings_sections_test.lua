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
	local tooltipBox = find("module:ASR", "Show who reserved it")
	local keep10 = find("module:ASR", "10")
	local clearButton = find("module:ASR", "Clear saved results")
	local deBox = find("module:ASR", "Hand it to the disenchanter")
	local winners = find("module:ASR", "Winners")
	check("the rows are all on the module's own page", tooltipBox and keep10 and clearButton and deBox and winners)
	local modulePage, entry, awardLog, profile
	for _, page in ipairs(Win.PAGES) do
		if page.key == "module:ASR" then modulePage = page end
	end
	for _, button in ipairs(Win.tabButtons) do
		if button.tab == "module:ASR" then entry = button end
	end
	check("the module has a page in the sidebar, under Modules, before Tools",
		modulePage and modulePage.group == "modules" and entry and entry.label:GetText() == "Soft Reserve"
		and Win.PAGES[#Win.PAGES].key == "tools")
	for _, widget in ipairs(Win.groups.session) do
		if widget.label and widget.label.GetText and widget.label:GetText() == "Never" then awardLog = widget end
	end
	for _, widget in ipairs(Win.groups.tools) do
		if widget.label and widget.label.GetText and widget.label:GetText() == "Copy my settings" then profile = widget end
	end
	check("ALC's own sections are on the pages they name: the award log on Session, Share settings on Tools", awardLog and profile)
	check("a check shows what the addon says", tooltipBox.checked == true and deBox.checked == false)
	check("a choice marks the current value", find("module:ASR", "15").selected == true and keep10.selected == false and find("module:ASR", "Off").selected == true)

	-- Using them
	tooltipBox.scripts.OnClick(tooltipBox)
	check("clicking a check tells the addon", state.tooltip == false)
	keep10.scripts.OnClick(keep10)
	check("clicking a choice sets the value and moves the mark", state.keep == 10 and keep10.selected == true and find("module:ASR", "15").selected == false)
	winners.scripts.OnClick(winners)
	check("a choice on the loot master tab works too", state.announce == "winners" and winners.selected == true and find("module:ASR", "Off").selected == false)
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

	-- A page shows only its own rows
	Win:SetTab("module:ASR")
	check("the module page shows the rows for everybody and for the loot master", tooltipBox:IsShown() and deBox:IsShown())
	Win:SetTab("general")
	check("another page hides them", not deBox:IsShown() and not tooltipBox:IsShown())

	-- A row that fails does not break the window
	ALC.RegisterSettingsSection({ id = "BAD", name = "Bad", rows = { row({ label = "Broken", get = function() error("boom") end }) } })
	check("a get that fails leaves the window working", pcall(function() Win:Refresh() end))
	ALC.UnregisterSettingsSection("BAD")
	ALC.UnregisterSettingsSection("ASR")
	check("a section can be removed", #ALC.GetSettingsSections() == base)
	Win:Hide()
end

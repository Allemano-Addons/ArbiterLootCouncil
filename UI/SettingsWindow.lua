-- SettingsWindow: the council list, loot options, the minimap button and debugging in
-- one place. Presentation only: every change goes through Settings, which tells the
-- rest of the addon.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local strupper, strtrim = string.upper, function(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
local min, max = math.min, math.max

local WIDTH, PAD = 480, 22
local HEADER_H = 40
local LIST_ROWS, LIST_ROW_H = 3, 26 -- the council list shows three names; the mouse wheel scrolls the rest

local SettingsWindow = {}
ALC.SettingsWindow = SettingsWindow
LibStub("AceEvent-3.0"):Embed(SettingsWindow)
SettingsWindow.rows = {}
local function qualityName(quality)
	return _G["ITEM_QUALITY" .. quality .. "_DESC"] or tostring(quality)
end

-- The list of qualities for the loot threshold drop-down.
function SettingsWindow:OpenQualityMenu()
	local current = ALC.Settings:GetQualityThreshold()
	local items = {}
	for quality = 2, 4 do
		items[#items + 1] = {
			label = qualityName(quality) .. (quality == current and "  \226\128\162" or ""),
			color = UI.QualityColor(quality),
			onClick = function() ALC.Settings:SetQualityThreshold(quality) end,
		}
	end
	ALC.ContextMenu:Open(items, L["Loot quality threshold"])
end

local frame, offset = nil, 0
local feedback -- the last message about the council list, shown under the input
local activeTab -- "everyone", "council" or "lm"; nil until the window is first opened
local c = UI.color

-- Settings are grouped by who they matter for.
SettingsWindow.TABS = {
	{ key = "everyone", label = L["Everyone"], note = L["How the addon looks on your own screen. Nobody else is affected."] },
	{ key = "council", label = L["Council"], note = L["For council members: how the voting window behaves for you."] },
	{ key = "lm", label = L["Loot"], note = L["Only used when you are the loot master: the council list, what happens to the loot, the disenchanter."] },
	{ key = "session", label = L["Session"], note = L["Only used when you are the loot master: how a session runs. A session that is running keeps its settings."] },
	{ key = "responses", label = L["Buttons"], note = L["Only used when you are the loot master: the answer buttons every player gets. A session that is running keeps the ones it started with."] },
}

-- The role the player has right now: "lm", "council" or "everyone" (a plain raider).
local function currentRole()
	if ALC.Council:AmLootMaster() then return "lm" end
	if ALC.Council:AmCouncil() then return "council" end
	return "everyone"
end

local ROLE_TEXT = {
	lm = L["You are the loot master"],
	council = L["You are on the council"],
	everyone = L["You are a raider"],
}

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------
local REASONS = {
	invalid = L["That is not a valid player name."],
	duplicate = L["That player is already on the council."],
	full = L["The council is full."],
}

local function setFeedback(text)
	feedback = text
	SettingsWindow:Refresh()
end

local function addName(text)
	text = strtrim(text or "")
	if text == "" then
		setFeedback(L["Type a player name first."])
		return
	end
	local ok, reason = ALC.Settings:AddCouncilMember(text)
	if ok then
		frame.input:SetText("")
		frame.input.placeholder:Show()
		setFeedback(nil)
	else
		setFeedback(REASONS[reason] or REASONS.invalid)
	end
end

-- The disenchanter: the name typed, the target, or nothing (clears it).
local deFeedback
local function setDisenchanter(text)
	text = strtrim(text or "")
	local ok = ALC.Settings:SetDisenchanter(text)
	deFeedback = (not ok) and L["That is not a valid name."] or nil
	if ok and frame and frame.deInput then
		frame.deInput:SetText("")
		frame.deInput.placeholder:Show()
	end
	SettingsWindow:Refresh()
end

local function setDisenchanterTarget()
	if not UnitIsPlayer("target") then
		deFeedback = L["Target a player first."]
		SettingsWindow:Refresh()
		return
	end
	setDisenchanter(ALC:UnitFullName("target") or "")
end

-- The guild bank character: the name typed, the target, or nothing (clears it).
local bankFeedback
local function setGuildBank(text)
	text = strtrim(text or "")
	local ok = ALC.Settings:SetGuildBank(text)
	bankFeedback = (not ok) and L["That is not a valid name."] or nil
	if ok and frame and frame.bankInput then
		frame.bankInput:SetText("")
		frame.bankInput.placeholder:Show()
	end
	SettingsWindow:Refresh()
end

local function setGuildBankTarget()
	if not UnitIsPlayer("target") then
		bankFeedback = L["Target a player first."]
		SettingsWindow:Refresh()
		return
	end
	setGuildBank(ALC:UnitFullName("target") or "")
end

local function addTarget()
	if not UnitIsPlayer("target") then
		setFeedback(L["Target a player first."])
		return
	end
	local name = ALC:UnitFullName("target")
	local ok, reason = ALC.Settings:AddCouncilMember(name or "")
	setFeedback(not ok and (REASONS[reason] or REASONS.invalid) or nil)
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------
local function savePosition()
	local point, _, relPoint, x, y = frame:GetPoint()
	ALC.Settings:SetWindowPosition("settings", point, relPoint, x, y)
end

local function restorePosition()
	frame:ClearAllPoints()
	local pos = ALC.Settings:GetWindowPosition("settings")
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
	end
end

local function build()
	frame = CreateFrame("Frame", nil, UIParent)
	UI.RegisterScaled(frame)
	frame:SetSize(WIDTH, 700)
	frame:SetFrameStrata("HIGH")
	frame:SetFrameLevel(80)   -- each window has its own band of levels, so windows never mix
	frame:SetToplevel(true) -- and the one you click comes to the front
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	frame:Hide()

	local bg = UI.NewFill(frame, 10)
	UI.SetTextureColor(bg, c.bg)
	UI.AddBorder(frame, c.border, 1, 10)

	-- Header, also the drag handle.
	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	header:SetHeight(HEADER_H)
	frame.header = header
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() frame:StartMoving() end)
	header:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		savePosition()
	end)

	frame.logo = UI.NewLogo(header, 22)
	frame.logo:SetPoint("LEFT", header, "LEFT", PAD, 0)
	local title = UI.NewText(header, 15, c.text)
	title:SetPoint("LEFT", frame.logo, "RIGHT", 10, 0)
	title:SetText(strupper(L["Settings"]))

	local close = CreateFrame("Button", nil, header)
	close:SetSize(30, 30)
	close:SetPoint("RIGHT", header, "RIGHT", -12, 0)
	close.text = UI.NewText(close, 30, c.muted, "CENTER")
	close.text:SetPoint("CENTER", 0, 0)
	close.text:SetText("\195\151")
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(c.text[1], c.text[2], c.text[3], 1) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1) end)
	close:SetScript("OnClick", function() SettingsWindow:Hide() end)

	-- Every setting belongs to one of three tabs, by who it matters for: everybody in the raid,
	-- the council members, or the loot master. `into` puts a widget in its tab's group.
	local groups = { everyone = {}, council = {}, lm = {}, session = {}, responses = {} }
	SettingsWindow.groups = groups
	local function into(key, widget)
		local group = groups[key]
		group[#group + 1] = widget
		return widget
	end
	local heights = {}

	local function divider(y, key)
		local line = frame:CreateTexture(nil, "BORDER")
		line:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -y)
		line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -y)
		line:SetHeight(1)
		UI.SetTextureColor(line, c.border)
		if key then into(key, line) end
		return line
	end
	local function section(key, y, text)
		local fs = UI.NewText(frame, 11, c.muted)
		fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
		fs:SetText(strupper(text))
		return into(key, fs)
	end
	local function paragraph(key, y, text, color)
		local fs = UI.NewText(frame, 11, color or c.muted)
		fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
		fs:SetWidth(WIDTH - 2 * PAD)
		fs:SetWordWrap(true)
		fs:SetText(text)
		return into(key, fs)
	end
	divider(HEADER_H)

	-- Who is looking: the role the player has right now.
	frame.role = UI.NewText(header, 12, c.muted, "RIGHT")
	frame.role:SetPoint("RIGHT", close, "LEFT", -12, 0)

	-- The three tabs.
	local tabY = HEADER_H + 14
	local gap = 8
	local tabWidth = math.floor((WIDTH - 2 * PAD - (#SettingsWindow.TABS - 1) * gap) / #SettingsWindow.TABS)
	SettingsWindow.tabButtons = {}
	for i, tab in ipairs(SettingsWindow.TABS) do
		local button = UI.NewButton(frame, tabWidth, 26, tab.label, function() SettingsWindow:SetTab(tab.key) end)
		button:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (i - 1) * (tabWidth + gap), -tabY)
		button.tab = tab.key
		SettingsWindow.tabButtons[i] = button
	end
	frame.tabNote = UI.NewText(frame, 11, c.muted)
	frame.tabNote:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(tabY + 34))
	frame.tabNote:SetWidth(WIDTH - 2 * PAD)
	frame.tabNote:SetWordWrap(true)
	local contentY = tabY + 34 + 30
	divider(contentY)
	contentY = contentY + 18

	-- Sections that other addons add (ALC.RegisterSettingsSection): a heading in the addon's colour, then its rows for
	-- this tab, drawn in the window's own style. Returns the y below them.
	local extRefresh = {}
	SettingsWindow.extRefresh = extRefresh
	local function extensionRows(tabKey, at, groupKey)
		local key = groupKey or tabKey
		for _, section in ipairs(ALC.GetSettingsSections()) do
			local rows = {}
			for _, row in ipairs(section.rows) do
				if row.tab == tabKey then rows[#rows + 1] = row end
			end
			if #rows > 0 then
				local heading = into(key, UI.NewText(frame, 11, UI.HexColor(section.color) or c.muted))
				heading:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -at)
				heading:SetText(strupper(section.name))
				at = at + 22
				for _, row in ipairs(rows) do
					if row.type == "check" then
						local box = into(key, UI.NewCheckbox(frame, row.label, function(checked)
							pcall(row.set, checked)
						end, row.tip))
						box:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -at)
						extRefresh[#extRefresh + 1] = function()
							local ok, value = pcall(row.get)
							box:SetChecked(ok and value and true or false)
						end
						at = at + 29
					elseif row.type == "choice" then
						local label = into(key, UI.NewText(frame, 12, c.text))
						label:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -at)
						label:SetText(row.label)
						at = at + 22
						local n = #row.options
						local width = math.floor((WIDTH - 2 * PAD - (n - 1) * 6) / n)
						local buttons = {}
						for i, option in ipairs(row.options) do
							buttons[i] = into(key, UI.NewButton(frame, width, 30, option.label, function()
								pcall(row.set, option.value)
								SettingsWindow:Refresh()
							end))
							buttons[i]:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (i - 1) * (width + 6), -at)
						end
						extRefresh[#extRefresh + 1] = function()
							local ok, value = pcall(row.get)
							for i, option in ipairs(row.options) do buttons[i]:SetSelected(ok and value == option.value) end
						end
						at = at + 40
					else -- an action; with `confirm` the first click asks and the second one does it
						local armed
						local button = into(key, UI.NewButton(frame, 240, 30, row.label, function(self)
							if row.confirm and not armed then
								armed = true
								self:SetLabel(row.confirm)
								C_Timer.After(4, function()
									armed = nil
									self:SetLabel(row.label)
								end)
								return
							end
							armed = nil
							self:SetLabel(row.label)
							pcall(row.onClick)
							SettingsWindow:Refresh()
						end))
						button:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -at)
						at = at + 38
					end
				end
				at = at + 8
			end
		end
		return at
	end

	-- Loot master: the council list ---------------------------------------------
	local y = contentY
	section("lm", y, L["Council"])
	frame.count = into("lm", UI.NewText(frame, 11, c.muted, "RIGHT"))
	frame.count:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y)
	y = y + 20

	paragraph("lm", y, L["Set before the raid. The loot master is always on the council. Changes apply to the next session."])
	y = y + 34

	frame.input = into("lm", UI.NewEditBox(frame, 240, 30, L["Player name (First Last)"], addName))
	frame.input:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	frame.add = into("lm", UI.NewButton(frame, 70, 30, L["Add"], function() addName(frame.input:GetText()) end))
	frame.add:SetPoint("LEFT", frame.input, "RIGHT", 8, 0)
	frame.addTarget = into("lm", UI.NewButton(frame, 110, 30, L["Add target"], addTarget))
	frame.addTarget:SetPoint("LEFT", frame.add, "RIGHT", 8, 0)
	y = y + 38

	frame.feedback = into("lm", UI.NewText(frame, 11, c.danger))
	frame.feedback:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 20

	frame.listBox = into("lm", CreateFrame("Frame", nil, frame))
	frame.listBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	frame.listBox:SetSize(WIDTH - 2 * PAD, LIST_ROWS * LIST_ROW_H + 4)
	frame.listBox.bg = UI.NewFill(frame.listBox, 8)
	UI.SetTextureColor(frame.listBox.bg, c.panel)
	UI.AddBorder(frame.listBox, c.border, 1, 8)

	frame.empty = UI.NewText(frame.listBox, 12, c.muted, "CENTER")
	frame.empty:SetPoint("CENTER", frame.listBox, "CENTER", 0, 0)
	frame.empty:SetText(L["No council members yet."])

	for i = 1, LIST_ROWS do
		local row = CreateFrame("Frame", nil, frame.listBox)
		row:SetHeight(LIST_ROW_H)
		row:SetPoint("TOPLEFT", frame.listBox, "TOPLEFT", 2, -2 - (i - 1) * LIST_ROW_H)
		row:SetPoint("TOPRIGHT", frame.listBox, "TOPRIGHT", -2, -2 - (i - 1) * LIST_ROW_H)
		row.name = UI.NewText(row, 13, c.text)
		row.name:SetPoint("LEFT", row, "LEFT", 12, 0)
		row.remove = CreateFrame("Button", nil, row)
		row.remove:SetSize(24, 24)
		row.remove:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		row.remove.text = UI.NewText(row.remove, 18, c.muted, "CENTER")
		row.remove.text:SetPoint("CENTER", 0, 1)
		row.remove.text:SetText("\195\151")
		row.remove:SetScript("OnEnter", function(self) self.text:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1) end)
		row.remove:SetScript("OnLeave", function(self) self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1) end)
		row.remove:SetScript("OnClick", function()
			if row.member then
				ALC.Settings:RemoveCouncilMember(row.member)
			end
		end)
		SettingsWindow.rows[i] = row
	end
	y = y + LIST_ROWS * LIST_ROW_H + 4 + 16

	-- Loot master: loot -----------------------------------------------------------
	divider(y, "lm")
	y = y + 16
	section("lm", y, L["Loot"])
	y = y + 22
	local thresholdLabel = into("lm", UI.NewText(frame, 12, c.text))
	thresholdLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	thresholdLabel:SetText(L["Loot quality threshold"])
	y = y + 22

	-- A drop-down: the button shows the threshold, a click opens the list of qualities.
	frame.qualityButton = into("lm", UI.NewButton(frame, WIDTH - 2 * PAD, 30, "", function()
		SettingsWindow:OpenQualityMenu()
	end))
	frame.qualityButton:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 42

	frame.autoOpen = into("lm", UI.NewCheckbox(frame, L["Open the loot window when items arrive"], function(checked)
		ALC.Settings:SetAutoOpenLootWindow(checked)
	end))
	frame.autoOpen:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 29

	frame.announce = into("lm", UI.NewCheckbox(frame, L["Announce awards"], function(checked)
		ALC.Settings:SetAnnounceAwards(checked)
	end, L["Say who got which item in raid chat (party chat in a party), and when a trade went through."]))
	frame.announce:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 29

	frame.autoLoot = into("lm", UI.NewCheckbox(frame, L["Auto loot"], function(checked)
		ALC.Settings:SetAutoLoot(checked)
	end, L["When you open a corpse as master looter, the items over the threshold are given to you, so you can award them later without assigning each one."]))
	frame.autoLoot:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 29

	frame.autoLootConfirm = into("lm", UI.NewCheckbox(frame, L["Ask first (\"Loot all?\")"], function(checked)
		ALC.Settings:SetAutoLootConfirm(checked)
	end, L["Show a question before the loot is taken for you."]))
	frame.autoLootConfirm:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 24, -y)
	y = y + 29

	frame.autoTrade = into("lm", UI.NewCheckbox(frame, L["Auto trade"], function(checked)
		ALC.Settings:SetAutoTrade(checked)
	end, L["When you award an item, the trade window opens with the winner and the item is put in it. A winner who is far away is asked by whisper to come."]))
	frame.autoTrade:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 38

	-- The disenchanter: gets the items nobody wants (the Disenchant button of the voting window).
	local deLabel = into("lm", UI.NewText(frame, 12, c.text))
	deLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	deLabel:SetText(L["Disenchanter: gets the items nobody wants"])
	y = y + 22
	frame.deInput = into("lm", UI.NewEditBox(frame, 200, 30, L["Player name (First Last)"], setDisenchanter))
	frame.deInput:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	frame.deSet = into("lm", UI.NewButton(frame, 60, 30, L["Set"], function() setDisenchanter(frame.deInput:GetText()) end))
	frame.deSet:SetPoint("LEFT", frame.deInput, "RIGHT", 8, 0)
	frame.deTarget = into("lm", UI.NewButton(frame, 100, 30, L["Use target"], setDisenchanterTarget))
	frame.deTarget:SetPoint("LEFT", frame.deSet, "RIGHT", 8, 0)
	frame.deClear = into("lm", UI.NewButton(frame, 60, 30, L["Clear"], function() setDisenchanter("") end))
	frame.deClear:SetPoint("LEFT", frame.deTarget, "RIGHT", 8, 0)
	y = y + 36
	frame.deCurrent = into("lm", UI.NewText(frame, 12, c.muted))
	frame.deCurrent:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 28

	-- The guild bank: a character that keeps the items the guild stores (the Guild bank button of the voting window).
	local bankLabel = into("lm", UI.NewText(frame, 12, c.text))
	bankLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	bankLabel:SetText(L["Guild bank: gets the items the guild keeps"])
	y = y + 22
	frame.bankInput = into("lm", UI.NewEditBox(frame, 200, 30, L["Player name (First Last)"], setGuildBank))
	frame.bankInput:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	frame.bankSet = into("lm", UI.NewButton(frame, 60, 30, L["Set"], function() setGuildBank(frame.bankInput:GetText()) end))
	frame.bankSet:SetPoint("LEFT", frame.bankInput, "RIGHT", 8, 0)
	frame.bankTarget = into("lm", UI.NewButton(frame, 100, 30, L["Use target"], setGuildBankTarget))
	frame.bankTarget:SetPoint("LEFT", frame.bankSet, "RIGHT", 8, 0)
	frame.bankClear = into("lm", UI.NewButton(frame, 60, 30, L["Clear"], function() setGuildBank("") end))
	frame.bankClear:SetPoint("LEFT", frame.bankTarget, "RIGHT", 8, 0)
	y = y + 36
	frame.bankCurrent = into("lm", UI.NewText(frame, 12, c.muted))
	frame.bankCurrent:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 28

	heights.lm = y + 40

	-- Session: how a session runs -------------------------------------------------
	y = contentY
	section("session", y, L["Session"])
	y = y + 24
	-- A random roll per candidate and item, for the council to choose by when it cannot decide.
	frame.rolls = into("session", UI.NewCheckbox(frame, L["Random rolls for the council"], function(checked)
		ALC.Settings:SetRollsEnabled(checked)
	end))
	frame.rolls:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 34

	-- A warning when a session starts about players who did not reply to the version check (no addon)
	frame.warnMissing = into("session", UI.NewCheckbox(frame, L["Warn about players without the addon"], function(checked)
		ALC.Settings:SetWarnMissing(checked)
	end, L["When a session starts, the chat says which players did not reply to the version check: they probably have no Arbiter Loot Council and cannot answer."]))
	frame.warnMissing:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 29

	-- How far back the council sees what a player was awarded (the Recent column).
	local recentLabel = into("session", UI.NewText(frame, 12, c.text))
	recentLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	recentLabel:SetText(L["Recent awards: the council sees the last"])
	y = y + 22
	SettingsWindow.recentButtons = {}
	local recentWidth = math.floor((WIDTH - 2 * PAD - 3 * 6) / 4)
	for i, recentDays in ipairs({ 7, 14, 30, 90 }) do
		local button = into("session", UI.NewButton(frame, recentWidth, 30, string.format(L["%d days"], recentDays), function()
			ALC.Settings:SetRecentDays(recentDays)
		end))
		button:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (i - 1) * (recentWidth + 6), -y)
		button.days = recentDays
		SettingsWindow.recentButtons[i] = button
	end
	y = y + 42

	-- The answer timer: when it runs out the response window closes for the players.
	frame.timerCheck = into("session", UI.NewCheckbox(frame, "", function(checked)
		ALC.Settings:SetTimerEnabled(checked)
	end))
	frame.timerCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 30
	SettingsWindow.timerButtons = {}
	local presets = ALC.Settings.TIMER_PRESETS
	local timerWidth = math.floor((WIDTH - 2 * PAD - (#presets - 1) * 6) / #presets)
	for i, seconds in ipairs(presets) do
		local button = into("session", UI.NewButton(frame, timerWidth, 30, string.format(L["%d sec"], seconds), function()
			ALC.Settings:SetTimerSeconds(seconds)
		end))
		button:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (i - 1) * (timerWidth + 6), -y)
		button.seconds = seconds
		SettingsWindow.timerButtons[i] = button
	end
	y = y + 38
	paragraph("session", y, L["When the time is up the response window closes for everybody. The council can still vote and award."])
	y = y + 40
	y = extensionRows("lm", y, "session")
	heights.session = y + 40

	-- Council ---------------------------------------------------------------------
	y = contentY
	section("council", y, L["Voting window"])
	y = y + 24
	frame.keepOpen = into("council", UI.NewCheckbox(frame, L["Keep the voting window open after an award"], function(checked)
		ALC.Settings:SetKeepCouncilOpen(checked)
	end))
	frame.keepOpen:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 29
	y = y + 8
	frame.councilHint = paragraph("council", y, L["Sorting, compact rows and the number of rows are set in the voting window itself. Right-click a player there for more."])
	y = y + 50

	-- Who is on the council: the loot master decides, everybody on it can read the list here.
	section("council", y, L["Who is on the council"])
	y = y + 24
	frame.councilNames = paragraph("council", y, "", c.text)
	frame.councilNames:SetHeight(96)
	frame.councilNames:SetJustifyV("TOP")
	y = y + 104
	heights.council = y + 40

	-- Everyone --------------------------------------------------------------------
	y = contentY
	section("everyone", y, L["Interface"])
	y = y + 22
	frame.minimap = into("everyone", UI.NewCheckbox(frame, L["Show the minimap button"], function(checked)
		ALC.Settings:SetMinimapHidden(not checked)
	end))
	frame.minimap:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 29

	frame.compact = into("everyone", UI.NewCheckbox(frame, L["Compact windows (smaller rows and buttons)"], function(checked)
		ALC.Settings:SetCompact(checked)
	end))
	frame.compact:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 29

	-- Pass by itself on items the class can never use (plate for a priest). Personal, off by default.
	frame.autoPass = into("everyone", UI.NewCheckbox(frame, L["Pass automatically on items I can never use"], function(checked)
		ALC.Settings:SetAutoPass(checked)
	end, L["When a session starts, items your class can never wear or wield (plate for a priest, leather for a warlock, a two-handed sword for a rogue) get a Pass for you. You can still change the answer. Rings, necklaces, trinkets and cloaks are for everybody and are never passed."]))
	frame.autoPass:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 38

	-- How big the windows are: smaller windows take less of the screen.
	local sizeLabel = into("everyone", UI.NewText(frame, 12, c.text))
	sizeLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	sizeLabel:SetText(L["Window size"])
	y = y + 22
	SettingsWindow.scaleButtons = {}
	local scaleWidth = math.floor((WIDTH - 2 * PAD - 3 * 6) / 4)
	for i, scale in ipairs(ALC.Settings.WINDOW_SCALES) do
		local button = into("everyone", UI.NewButton(frame, scaleWidth, 30, string.format("%d%%", scale * 100), function()
			ALC.Settings:SetWindowScale(scale)
		end))
		button:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (i - 1) * (scaleWidth + 6), -y)
		button.scale = scale
		SettingsWindow.scaleButtons[i] = button
	end
	y = y + 46

	-- The font of every window; opens a list where each font is shown as itself.
	local fontLabel = into("everyone", UI.NewText(frame, 12, c.text))
	fontLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	fontLabel:SetText(L["Font"])
	y = y + 20
	frame.fontButton = into("everyone", UI.NewButton(frame, WIDTH - 2 * PAD, 30, "", function() SettingsWindow:ToggleFontMenu() end))
	frame.fontButton:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 46

	-- Debug -----------------------------------------------------------------------
	divider(y, "everyone")
	y = y + 16
	section("everyone", y, L["Debug"])
	y = y + 22
	frame.debug = into("everyone", UI.NewCheckbox(frame, L["Print debug messages in chat"], function(checked)
		ALC.Settings:SetDebug(checked)
	end))
	frame.debug:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 34
	frame.showLog = into("everyone", UI.NewButton(frame, 120, 30, L["Show log"], function() ALC.Debug:Dump(30) end))
	frame.showLog:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	frame.clearLog = into("everyone", UI.NewButton(frame, 120, 30, L["Clear log"], function()
		ALC.Debug:Clear()
		ALC:Print(L["Debug log cleared."])
	end))
	frame.clearLog:SetPoint("LEFT", frame.showLog, "RIGHT", 8, 0)
	y = y + 46
	y = extensionRows("everyone", y)
	heights.everyone = y + 40
	SettingsWindow.heights = heights

	-- Buttons: the answers of the loot master's sessions ----------------------------
	y = contentY
	section("responses", y, L["Answer buttons"])
	frame.responseCount = into("responses", UI.NewText(frame, 11, c.muted, "RIGHT"))
	frame.responseCount:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y)
	y = y + 24
	SettingsWindow.responseRows = {}
	local RESPONSE_ROW_H = 36
	for i = 1, ALC.Constants.MAX_RESPONSES do
		local row = into("responses", CreateFrame("Frame", nil, frame))
		row:SetSize(WIDTH - 2 * PAD, RESPONSE_ROW_H - 4)
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(y + (i - 1) * RESPONSE_ROW_H))
		row.index = i
		row.up = UI.NewButton(row, 24, 30, "^", function() SettingsWindow:MoveResponse(i, -1) end)
		row.up:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.down = UI.NewButton(row, 24, 30, "v", function() SettingsWindow:MoveResponse(i, 1) end)
		row.down:SetPoint("LEFT", row.up, "RIGHT", 2, 0)
		row.edit = UI.NewEditBox(row, 210, 30, L["Label"], function() SettingsWindow:CommitResponseLabel(i) end)
		row.edit:SetMaxLetters(ALC.Constants.MAX_RESPONSE_LABEL)
		row.edit:SetPoint("LEFT", row.down, "RIGHT", 8, 0)
		row.edit:HookScript("OnEditFocusLost", function() SettingsWindow:CommitResponseLabel(i) end)
		row.color = UI.NewButton(row, 34, 30, "", function() SettingsWindow:CycleResponseColor(i) end)
		row.color:SetPoint("LEFT", row.edit, "RIGHT", 8, 0)
		row.color.swatch = row.color:CreateTexture(nil, "OVERLAY")
		row.color.swatch:SetPoint("TOPLEFT", 7, -7)
		row.color.swatch:SetPoint("BOTTOMRIGHT", -7, 7)
		row.remove = CreateFrame("Button", nil, row)
		row.remove:SetSize(24, 24)
		row.remove:SetPoint("LEFT", row.color, "RIGHT", 8, 0)
		row.remove.text = UI.NewText(row.remove, 18, c.muted, "CENTER")
		row.remove.text:SetPoint("CENTER", 0, 1)
		row.remove.text:SetText("\195\151")
		row.remove:SetScript("OnEnter", function(self) self.text:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1) end)
		row.remove:SetScript("OnLeave", function(self) self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1) end)
		row.remove:SetScript("OnClick", function() SettingsWindow:RemoveResponse(i) end)
		SettingsWindow.responseRows[i] = row
	end
	y = y + ALC.Constants.MAX_RESPONSES * RESPONSE_ROW_H + 4
	frame.addResponse = into("responses", UI.NewButton(frame, 130, 30, L["Add button"], function() SettingsWindow:AddResponse() end))
	frame.addResponse:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	frame.resetResponses = into("responses", UI.NewButton(frame, 160, 30, L["Back to the default five"], function() SettingsWindow:ResetResponses() end))
	frame.resetResponses:SetPoint("LEFT", frame.addResponse, "RIGHT", 8, 0)
	y = y + 40
	frame.responseFeedback = into("responses", UI.NewText(frame, 11, c.danger))
	frame.responseFeedback:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 24
	heights.responses = y + 40

	frame.version = UI.NewText(frame, 11, c.muted)
	frame.version:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 16)
	frame.version:SetText(string.format("Arbiter Loot Council %s \194\183 Allemano Addons", ALC.version or "?"))
	frame:SetHeight(heights.everyone)

	frame:SetScript("OnMouseWheel", function(_, delta)
		if activeTab ~= "lm" then return end -- only the council list scrolls
		local count = #ALC.Settings:GetCouncil()
		offset = max(0, min(offset - delta, max(0, count - LIST_ROWS)))
		SettingsWindow:Refresh()
	end)
	frame:SetScript("OnShow", function() SettingsWindow:Refresh() end)

	restorePosition()
end

--------------------------------------------------------------------------------
-- The font list
--------------------------------------------------------------------------------
local FONT_ROWS, FONT_ROW_H = 8, 30
local fontMenu, fontCatcher
local fontChoices, fontOffset = {}, 0

local function refreshFontMenu()
	if not fontMenu or not fontMenu:IsShown() then return end
	fontOffset = max(0, min(fontOffset, max(0, #fontChoices - FONT_ROWS)))
	local current = ALC.Settings:GetFont()
	for i, row in ipairs(fontMenu.rows) do
		local choice = fontChoices[fontOffset + i]
		if choice then
			row.choice = choice
			-- Each font is shown as itself; a font the game cannot load falls back to the default.
			-- The font must be set before the text: a text without a font is an error.
			local ok = row.name:SetFont(choice.path or STANDARD_TEXT_FONT, 13, "")
			if ok == false then row.name:SetFont(STANDARD_TEXT_FONT, 13, "") end
			row.name:SetText(choice.name)
			local selected = (choice.path == nil and current == nil)
				or (choice.path ~= nil and current ~= nil and string.lower(choice.path) == string.lower(current))
			row.selected = selected
			UI.SetTextureColor(row.bg, selected and c.goldTint or c.panel, selected and 1 or 0)
			local color = selected and c.gold or c.text
			row.name:SetTextColor(color[1], color[2], color[3], 1)
			row:Show()
		else
			row.choice = nil
			row:Hide()
		end
	end
	fontMenu.scroll:Update(#fontChoices, FONT_ROWS, fontOffset)
end

local function buildFontMenu()
	fontCatcher = CreateFrame("Frame", nil, UIParent)
	fontCatcher:SetAllPoints(UIParent)
	fontCatcher:SetFrameStrata("DIALOG")
	fontCatcher:EnableMouse(true)
	fontCatcher:SetScript("OnMouseDown", function() SettingsWindow:HideFontMenu() end)
	fontCatcher:Hide()

	fontMenu = CreateFrame("Frame", nil, UIParent)
	fontMenu:SetFrameStrata("FULLSCREEN_DIALOG")
	fontMenu:SetClampedToScreen(true)
	fontMenu:EnableMouseWheel(true)
	fontMenu:SetSize(WIDTH - 2 * PAD, FONT_ROWS * FONT_ROW_H + 12)
	fontMenu:Hide()
	local bg = UI.NewFill(fontMenu, 8)
	UI.SetTextureColor(bg, c.bg)
	UI.AddBorder(fontMenu, c.border, 1, 8)

	fontMenu.rows = {}
	for i = 1, FONT_ROWS do
		local row = CreateFrame("Button", nil, fontMenu)
		row:SetHeight(FONT_ROW_H)
		row:SetPoint("TOPLEFT", fontMenu, "TOPLEFT", 6, -6 - (i - 1) * FONT_ROW_H)
		row:SetPoint("TOPRIGHT", fontMenu, "TOPRIGHT", -16, -6 - (i - 1) * FONT_ROW_H)
		row.bg = UI.NewFill(row, 6)
		UI.SetTextureColor(row.bg, c.panel, 0)
		-- Not made with UI.NewText: the font of a row is its own, whatever the setting is.
		row.name = row:CreateFontString(nil, "OVERLAY")
		row.name:SetFont(STANDARD_TEXT_FONT, 13, "") -- every text needs a font before it gets its text
		row.name:SetPoint("LEFT", row, "LEFT", 12, 0)
		row.name:SetJustifyH("LEFT")
		row:SetScript("OnEnter", function(self) UI.SetTextureColor(self.bg, c.panelHover, 1) end)
		row:SetScript("OnLeave", function(self)
			UI.SetTextureColor(self.bg, self.selected and c.goldTint or c.panel, self.selected and 1 or 0)
		end)
		row:SetScript("OnClick", function(self)
			if not self.choice then return end
			ALC.Settings:SetFont(self.choice.path)
			SettingsWindow:HideFontMenu()
		end)
		fontMenu.rows[i] = row
	end
	fontMenu.scroll = UI.NewScrollBar(fontMenu, function(newOffset)
		fontOffset = newOffset
		refreshFontMenu()
	end)
	fontMenu.scroll:SetPoint("TOPRIGHT", fontMenu, "TOPRIGHT", -5, -6)
	fontMenu.scroll:SetHeight(FONT_ROWS * FONT_ROW_H)
	fontMenu.scroll:Hide()
	fontMenu:SetScript("OnMouseWheel", function(_, delta)
		fontOffset = max(0, min(fontOffset - delta, max(0, #fontChoices - FONT_ROWS)))
		refreshFontMenu()
	end)
end

function SettingsWindow:ShowFontMenu()
	if not frame then return end
	if not fontMenu then buildFontMenu() end
	fontChoices = UI.GetFontChoices()
	fontOffset = 0
	fontMenu:ClearAllPoints()
	fontMenu:SetPoint("TOPLEFT", frame.fontButton, "BOTTOMLEFT", 0, -4)
	fontCatcher:Show()
	fontMenu:Show()
	refreshFontMenu()
end

function SettingsWindow:HideFontMenu()
	if fontMenu then fontMenu:Hide() end
	if fontCatcher then fontCatcher:Hide() end
end

function SettingsWindow:ToggleFontMenu()
	if fontMenu and fontMenu:IsShown() then self:HideFontMenu() else self:ShowFontMenu() end
end

SettingsWindow.fontMenu = function() return fontMenu end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- The answer buttons (tab "Buttons")
--------------------------------------------------------------------------------
local responseFeedback

local function setResponseFeedback(text)
	responseFeedback = text
	if frame and frame.responseFeedback then frame.responseFeedback:SetText(text or "") end
end

-- Saves an edited copy of the loot master's buttons; on refusal the reason is shown.
local function saveResponses(set)
	local ok, reason = ALC.Responses:SetConfiguredSet(set)
	if not ok then setResponseFeedback(reason) return false end
	setResponseFeedback(nil)
	return true
end

function SettingsWindow:CommitResponseLabel(index)
	local row = self.responseRows and self.responseRows[index]
	local set = ALC.Responses:GetConfiguredSet()
	if not row or not set[index] then return end
	local label = ALC.Responses.CleanLabel(row.edit:GetText())
	if label and label ~= set[index].label then
		set[index].label = label
		saveResponses(set)
	end
	row.edit:SetText(set[index].label) -- an empty label goes back to what it was
end

function SettingsWindow:CycleResponseColor(index)
	local set = ALC.Responses:GetConfiguredSet()
	if not set[index] then return end
	local palette = ALC.Responses.PALETTE
	local current = 0
	for i, color in ipairs(palette) do
		if math.abs(color[1] - set[index].color[1]) < 0.01 and math.abs(color[2] - set[index].color[2]) < 0.01
			and math.abs(color[3] - set[index].color[3]) < 0.01 then current = i end
	end
	local nextColor = palette[current % #palette + 1]
	set[index].color = { nextColor[1], nextColor[2], nextColor[3] }
	saveResponses(set)
end

-- Moves a button up or down among the others; PASS stays last.
function SettingsWindow:MoveResponse(index, step)
	local set = ALC.Responses:GetConfiguredSet()
	local target = index + step
	if not set[index] or not set[target] or set[index].id == "PASS" or set[target].id == "PASS" then return end
	set[index], set[target] = set[target], set[index]
	saveResponses(set)
end

function SettingsWindow:RemoveResponse(index)
	local set = ALC.Responses:GetConfiguredSet()
	if not set[index] or set[index].id == "PASS" then return end
	if #set <= 2 then
		setResponseFeedback(L["There must be at least one button besides Pass."])
		return
	end
	table.remove(set, index)
	saveResponses(set)
end

function SettingsWindow:AddResponse()
	local set = ALC.Responses:GetConfiguredSet()
	if #set >= ALC.Constants.MAX_RESPONSES then
		setResponseFeedback(string.format(L["At most %d buttons."], ALC.Constants.MAX_RESPONSES))
		return
	end
	local used = {}
	for _, r in ipairs(set) do used[r.id] = true end
	local n = 1
	while used["X" .. n] do n = n + 1 end
	local color = ALC.Responses.PALETTE[(#set - 1) % #ALC.Responses.PALETTE + 1]
	table.insert(set, #set, { id = "X" .. n, label = L["New button"], color = { color[1], color[2], color[3] } })
	saveResponses(set)
end

function SettingsWindow:ResetResponses()
	saveResponses(nil)
end

-- Shows the settings of one tab and hides the others.
function SettingsWindow:SetTab(key)
	if not self.groups or not self.groups[key] then return end
	local switched = activeTab ~= key
	activeTab = key
	for tabKey, widgets in pairs(self.groups) do
		for _, widget in ipairs(widgets) do widget:SetShown(tabKey == key) end
	end
	local buttons = ALC.Responses:GetConfiguredSet()
	for i, row in ipairs(self.responseRows) do
		if i > #buttons then row:Hide() end -- no such button
	end
	for _, button in ipairs(self.tabButtons) do
		button:SetSelected(button.tab == key)
	end
	for _, tab in ipairs(self.TABS) do
		if tab.key == key then frame.tabNote:SetText(tab.note) end
	end
	frame:SetHeight(self.heights[key])
	if switched then self:HideFontMenu() end
end

function SettingsWindow:GetTab()
	return activeTab
end

function SettingsWindow:Refresh()
	if not frame or not frame:IsShown() then return end
	local settings = ALC.Settings

	frame.role:SetText(ROLE_TEXT[currentRole()])
	if not activeTab then activeTab = currentRole() end
	self:SetTab(activeTab)

	local council = settings:GetCouncil()
	local count = #council
	offset = max(0, min(offset, max(0, count - LIST_ROWS)))
	for i = 1, LIST_ROWS do
		local row = self.rows[i]
		local name = council[offset + i]
		row.member = name
		if name then
			row.name:SetText(name)
			row:Show()
		else
			row:Hide()
		end
	end
	frame.empty:SetShown(count == 0)
	frame.count:SetText(string.format("%d/%d", count, ALC.Constants.MAX_COUNCIL - 1))
	frame.feedback:SetText(feedback or "")

	-- The council of the running session, else the one of the last session.
	local session = ALC.Sessions:GetSession()
	local lm, names
	if session then
		lm, names = session.lm, session.council
	else
		local last = settings:GetLastCouncil()
		lm, names = last and last.lm, last and last.council
	end
	if names and #names > 0 then
		frame.councilNames:SetText(format(L["Loot master: %s"], lm or "?") .. "\n" .. table.concat(names, ", ")
			.. (session and "" or ("\n\n" .. L["From the last session. The loot master sends the council again when a session starts."])))
	else
		frame.councilNames:SetText(L["No session yet. The loot master chooses the council and sends it to everybody when a session starts."])
	end

	local threshold = settings:GetQualityThreshold()
	frame.qualityButton:SetLabel(qualityName(threshold))
	local qc = UI.QualityColor(threshold)
	frame.qualityButton.label:SetTextColor(qc[1], qc[2], qc[3], 1)
	local buttons = ALC.Responses:GetConfiguredSet()
	frame.responseCount:SetText(string.format("%d/%d", #buttons, ALC.Constants.MAX_RESPONSES))
	for i, row in ipairs(self.responseRows) do
		local r = buttons[i]
		if r then
			row.edit:SetText(r.label)
			local isPass = r.id == "PASS"
			row.color.swatch:SetColorTexture(r.color[1], r.color[2], r.color[3], 1)
			row.remove:SetShown(not isPass)
			row.up:SetAvailable(i > 1 and buttons[i - 1].id ~= "PASS" and not isPass)
			row.down:SetAvailable(not isPass and buttons[i + 1] ~= nil and buttons[i + 1].id ~= "PASS")
			row:SetShown(activeTab == "responses")
		else
			row:Hide()
		end
	end
	frame.responseFeedback:SetText(responseFeedback or "")
	frame.autoOpen:SetChecked(settings:GetAutoOpenLootWindow())
	frame.announce:SetChecked(settings:GetAnnounceAwards())
	frame.autoLoot:SetChecked(settings:GetAutoLoot())
	frame.autoLootConfirm:SetChecked(settings:GetAutoLootConfirm())
	frame.autoTrade:SetChecked(settings:GetAutoTrade())
	frame.timerCheck:SetChecked(settings:GetTimerEnabled())
	frame.timerCheck.label:SetText(settings:GetTimerEnabled()
		and string.format(L["Answer timer: On, %d sec"], settings:GetTimerSeconds()) or L["Answer timer: Off"])
	for _, button in ipairs(self.timerButtons) do button:SetSelected(button.seconds == settings:GetTimerSeconds()) end
	frame.compact:SetChecked(settings:GetCompact())
	frame.autoPass:SetChecked(settings:GetAutoPass())
	for _, button in ipairs(self.recentButtons) do button:SetSelected(button.days == settings:GetRecentDays()) end
	for _, button in ipairs(self.scaleButtons) do button:SetSelected(button.scale == settings:GetWindowScale()) end
	frame.minimap:SetChecked(not settings:IsMinimapHidden())
	frame.keepOpen:SetChecked(settings:GetKeepCouncilOpen())
	frame.rolls:SetChecked(settings:GetRollsEnabled())
	frame.warnMissing:SetChecked(settings:GetWarnMissing())
	local disenchanter = settings:GetDisenchanter()
	if deFeedback then
		frame.deCurrent:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1)
		frame.deCurrent:SetText(deFeedback)
	else
		frame.deCurrent:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
		frame.deCurrent:SetText(disenchanter and (L["Disenchanter"] .. ": " .. disenchanter) or L["No disenchanter set."])
	end
	frame.deClear:SetAvailable(disenchanter ~= nil)
	local bank = settings:GetGuildBank()
	if bankFeedback then
		frame.bankCurrent:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1)
		frame.bankCurrent:SetText(bankFeedback)
	else
		frame.bankCurrent:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
		frame.bankCurrent:SetText(bank and (L["Guild bank"] .. ": " .. bank) or L["No guild bank set."])
	end
	frame.bankClear:SetAvailable(bank ~= nil)
	frame.debug:SetChecked(settings:IsDebug())
	for _, refreshRow in ipairs(self.extRefresh or {}) do refreshRow() end
	frame.fontButton:SetLabel(UI.FontName(settings:GetFont()))
	refreshFontMenu()
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------
-- Whether the window is open is remembered across a /reload.
function SettingsWindow:Show()
	if not frame then
		-- A build that fails half way must not leave a broken frame behind.
		local ok, err = pcall(build)
		if not ok then
			frame = nil
			error(err, 0)
		end
	end
	frame:Show()
	ALC.Settings:SetWindowShown("settings", true)
	self:Refresh()
end

function SettingsWindow:Hide()
	self:HideFontMenu()
	if frame then frame:Hide() end
	ALC.Settings:SetWindowShown("settings", false)
end

function SettingsWindow:Toggle()
	if frame and frame:IsShown() then self:Hide() else self:Show() end
end

function SettingsWindow:IsShown()
	return frame ~= nil and frame:IsShown()
end

function SettingsWindow:OnEnteringWorld(isInitialLogin, isReloadingUi)
	if not (isInitialLogin or isReloadingUi) then return end
	if ALC.Settings:GetWindowShown("settings") then self:Show() end
end

function SettingsWindow:Init()
	ALC.Events.Register(self, "ALC_SETTINGS_CHANGED", function(_, key)
		if key == "windowScale" then UI.ApplyScales() end
		SettingsWindow:Refresh()
	end)
	ALC.Events.Register(self, "ALC_SESSION_STARTED", function(_, session)
		if session and session.council then ALC.Settings:SetLastCouncil(session.lm, session.council) end
		SettingsWindow:Refresh()
	end)
	ALC.Events.Register(self, "ALC_SESSION_ENDED", function() SettingsWindow:Refresh() end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
		SettingsWindow:OnEnteringWorld(isInitialLogin, isReloadingUi)
	end)
end

ALC.Commands:Register("settings", function() SettingsWindow:Toggle() end, L["open the settings window"])

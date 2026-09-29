-- SettingsWindow: the council list, loot options, the minimap button and debugging in
-- one place. Presentation only: every change goes through Settings, which tells the
-- rest of the addon.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local strupper, strtrim = string.upper, function(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
local min, max = math.min, math.max

local WIDTH, PAD = 480, 22
local HEADER_H = 52
local LIST_ROWS, LIST_ROW_H = 6, 28

local SettingsWindow = {}
ALC.SettingsWindow = SettingsWindow
LibStub("AceEvent-3.0"):Embed(SettingsWindow)
SettingsWindow.rows = {}
SettingsWindow.qualityButtons = {}

local frame, offset = nil, 0
local feedback -- the last message about the council list, shown under the input
local c = UI.color

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

	frame.logo = UI.NewLogo(header, 28)
	frame.logo:SetPoint("LEFT", header, "LEFT", PAD, 0)
	local title = UI.NewText(header, 15, c.text)
	title:SetPoint("LEFT", frame.logo, "RIGHT", 10, 0)
	title:SetText(strupper(L["Settings"]))

	local close = CreateFrame("Button", nil, header)
	close:SetSize(28, 28)
	close:SetPoint("RIGHT", header, "RIGHT", -12, 0)
	close.text = UI.NewText(close, 22, c.muted, "CENTER")
	close.text:SetPoint("CENTER", 0, 0)
	close.text:SetText("\195\151")
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(c.text[1], c.text[2], c.text[3], 1) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1) end)
	close:SetScript("OnClick", function() SettingsWindow:Hide() end)

	local function divider(y)
		local line = frame:CreateTexture(nil, "BORDER")
		line:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -y)
		line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -y)
		line:SetHeight(1)
		UI.SetTextureColor(line, c.border)
	end
	local function section(y, text)
		local fs = UI.NewText(frame, 11, c.muted)
		fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
		fs:SetText(strupper(text))
		return fs
	end
	divider(HEADER_H)

	-- Council ---------------------------------------------------------------
	local y = HEADER_H + 18
	section(y, L["Council"])
	frame.count = UI.NewText(frame, 11, c.muted, "RIGHT")
	frame.count:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y)
	y = y + 20

	local note = UI.NewText(frame, 11, c.muted)
	note:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	note:SetWidth(WIDTH - 2 * PAD)
	note:SetWordWrap(true)
	note:SetText(L["Set before the raid. The loot master is always on the council. Changes apply to the next session."])
	y = y + 34

	frame.input = UI.NewEditBox(frame, 240, 30, L["Player name (First Last)"], addName)
	frame.input:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	frame.add = UI.NewButton(frame, 70, 30, L["Add"], function() addName(frame.input:GetText()) end)
	frame.add:SetPoint("LEFT", frame.input, "RIGHT", 8, 0)
	frame.addTarget = UI.NewButton(frame, 110, 30, L["Add target"], addTarget)
	frame.addTarget:SetPoint("LEFT", frame.add, "RIGHT", 8, 0)
	y = y + 38

	frame.feedback = UI.NewText(frame, 11, c.danger)
	frame.feedback:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 20

	frame.listBox = CreateFrame("Frame", nil, frame)
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

	-- Loot ------------------------------------------------------------------
	divider(y)
	y = y + 16
	section(y, L["Loot"])
	y = y + 22
	local thresholdLabel = UI.NewText(frame, 12, c.text)
	thresholdLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	thresholdLabel:SetText(L["Loot quality threshold"])
	y = y + 22

	local gap = 6
	local width = math.floor((WIDTH - 2 * PAD - 5 * gap) / 6)
	for quality = 0, 5 do
		local label = _G["ITEM_QUALITY" .. quality .. "_DESC"] or tostring(quality)
		local button = UI.NewButton(frame, width, 30, label, function()
			ALC.Settings:SetQualityThreshold(quality)
		end)
		button:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + quality * (width + gap), -y)
		local qc = UI.QualityColor(quality)
		button.label:SetTextColor(qc[1], qc[2], qc[3], 1)
		button.quality = quality
		SettingsWindow.qualityButtons[quality + 1] = button
	end
	y = y + 42

	frame.autoOpen = UI.NewCheckbox(frame, L["Open the loot window when items arrive"], function(checked)
		ALC.Settings:SetAutoOpenLootWindow(checked)
	end)
	frame.autoOpen:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 38

	-- Interface -------------------------------------------------------------
	divider(y)
	y = y + 16
	section(y, L["Interface"])
	y = y + 22
	frame.minimap = UI.NewCheckbox(frame, L["Show the minimap button"], function(checked)
		ALC.Settings:SetMinimapHidden(not checked)
	end)
	frame.minimap:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 30
	frame.keepOpen = UI.NewCheckbox(frame, L["Keep the voting window open after an award"], function(checked)
		ALC.Settings:SetKeepCouncilOpen(checked)
	end)
	frame.keepOpen:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 34

	-- The font of every window; opens a list where each font is shown as itself.
	local fontLabel = UI.NewText(frame, 12, c.text)
	fontLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	fontLabel:SetText(L["Font"])
	y = y + 20
	frame.fontButton = UI.NewButton(frame, WIDTH - 2 * PAD, 30, "", function() SettingsWindow:ToggleFontMenu() end)
	frame.fontButton:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 46

	-- Debug -----------------------------------------------------------------
	divider(y)
	y = y + 16
	section(y, L["Debug"])
	y = y + 22
	frame.debug = UI.NewCheckbox(frame, L["Print debug messages in chat"], function(checked)
		ALC.Settings:SetDebug(checked)
	end)
	frame.debug:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 34
	frame.showLog = UI.NewButton(frame, 120, 30, L["Show log"], function() ALC.Debug:Dump(30) end)
	frame.showLog:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	frame.clearLog = UI.NewButton(frame, 120, 30, L["Clear log"], function()
		ALC.Debug:Clear()
		ALC:Print(L["Debug log cleared."])
	end)
	frame.clearLog:SetPoint("LEFT", frame.showLog, "RIGHT", 8, 0)
	y = y + 46

	frame.version = UI.NewText(frame, 11, c.muted)
	frame.version:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 16)
	frame.version:SetText(string.format("Arbiter Loot Council %s \194\183 Allemano Addons", ALC.version or "?"))
	frame:SetHeight(y + 40)

	frame:SetScript("OnMouseWheel", function(_, delta)
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
function SettingsWindow:Refresh()
	if not frame or not frame:IsShown() then return end
	local settings = ALC.Settings

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

	local threshold = settings:GetQualityThreshold()
	for _, button in ipairs(self.qualityButtons) do
		button:SetSelected(button.quality == threshold)
	end
	frame.autoOpen:SetChecked(settings:GetAutoOpenLootWindow())
	frame.minimap:SetChecked(not settings:IsMinimapHidden())
	frame.keepOpen:SetChecked(settings:GetKeepCouncilOpen())
	frame.debug:SetChecked(settings:IsDebug())
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
	ALC.Events.Register(self, "ALC_SETTINGS_CHANGED", function() SettingsWindow:Refresh() end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
		SettingsWindow:OnEnteringWorld(isInitialLogin, isReloadingUi)
	end)
end

ALC.Commands:Register("settings", function() SettingsWindow:Toggle() end, L["open the settings window"])

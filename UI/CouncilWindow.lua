-- CouncilWindow: the council's window, with tabs.
--   Council      who wants the item, with what, and the votes; award from here
--   History      the awards in the award log, newest first
--   Trade Queue  awarded items that still have to be handed to their winner
--   Settings     (opens the settings window)
-- Presentation only: data comes from Candidates, Voting, Sessions, Awards and Trades;
-- votes go through Voting and awards through the AwardDialog.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local strupper = string.upper
local min, max = math.min, math.max

local WIDTH, PAD = 1010, 20
local HEADER_H, ITEM_H, TABLE_HEAD_H, FOOTER_H = 60, 64, 34, 52
local ROW_H, COMPACT_ROW_H = 56, 32
local POOL, DEFAULT_ROWS, MIN_ROWS = 30, 10, 3
local INITIAL_ROWS = 6 -- candidate rows made when the window is built
local ICON = 40
local BUTTON_W = 92
local NAME_X, RANK_X, RESPONSE_X, GEAR_X, RECENT_X, NOTE_X, VOTES_X = 16, 172, 268, 376, 536, 590, 712
local GEAR_W, RECENT_W, NOTE_W, RANK_W = 150, 44, 116, 90
-- The optional Roll column (Settings, Council) sits before the note, which gets narrower.
local ROLL_X, ROLL_W, NOTE_NARROW_X, NOTE_NARROW_W = 588, 44, 640, 66
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- The History tab: one row per award in the award log, newest first.
local HISTORY_ROW_H, HISTORY_ROWS = 48, 12 -- the row height is 30 in compact mode (layoutHistoryRow)
local historyLayout -- whether the History rows are laid out compact now
local TIME_X, HITEM_X, WINNER_X, HRESPONSE_X, HVOTES_X = 12, 112, 392, 560, 672
local HITEM_W = 270
-- The date list to the left of the History table: "All dates" and one row per day.
local DATE_W, DATE_ROW_H, DATE_ROWS = 190, 28, 12
local HOFF = DATE_W + 10 -- the table starts right of the list

-- The Trade Queue tab: one row per item still to be traded.
local TRADE_ROW_H, TRADE_ROWS = 52, 10
local TITEM_X, TWINNER_X, TWHEN_X = 16, 430, 700
local TITEM_W = 390

-- The list of next items shown on the Council tab between two sessions (loot master).
local QUEUE_ROW_H, QUEUE_ROWS = 46, 6

local CouncilWindow = {}
ALC.CouncilWindow = CouncilWindow
CouncilWindow.rows = {}         -- the candidate rows of the Council tab
CouncilWindow.historyRows = {}  -- the award rows of the History tab
CouncilWindow.tradeRows = {}    -- the rows of the Trade Queue tab
CouncilWindow.queueRows = {}    -- the next items, between sessions
CouncilWindow.tabs = {}

local frame
local offset, historyOffset, tradeOffset = 0, 0, 0
local historyDates, historySearch, dateOffset = {}, "", 0 -- History: the dates picked (a set), the search text, the date list's scroll
local activeTab = "council"     -- "council", "history" or "trades"
local layoutCompact             -- how the candidate rows are laid out now
local focus = 1                -- the item of the session the Council tab shows
local stopArmed = false         -- "Stop session" was clicked once and waits for a second click
local disarmStop                -- resets the Stop session button (defined below)
local councilStatic, historyStatic, tradeStatic, queueStatic = {}, {}, {}, {} -- widgets of one tab only
local c = UI.color

local function setShown(widgets, shown)
	for _, widget in ipairs(widgets) do widget:SetShown(shown) end
end

--------------------------------------------------------------------------------
-- Settings of this window
--------------------------------------------------------------------------------

-- How many candidate rows the window shows at most; the grip changes it.
local function maxRows()
	local rows = ALC.Settings:GetWindowOption("council", "maxRows", DEFAULT_ROWS)
	return max(MIN_ROWS, min(POOL, rows))
end

-- The same setting as the other windows' compact mode (Settings, Everyone).
local function isCompact()
	return ALC.Settings:GetCompact()
end

local function rowHeight()
	return isCompact() and COMPACT_ROW_H or ROW_H
end

--------------------------------------------------------------------------------
-- Building blocks
--------------------------------------------------------------------------------
local function showItemTooltip(owner, itemString)
	if not itemString then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(itemString)
	GameTooltip:Show()
end

-- A small response chip: the answer's name on a tinted rounded background.
local function newChip(parent, width, height, fontSize)
	local chip = CreateFrame("Frame", nil, parent)
	chip:SetSize(width, height)
	chip.bg = UI.NewFill(chip, 6)
	chip.label = UI.NewText(chip, fontSize, c.text, "CENTER")
	chip.label:SetPoint("CENTER", 0, 0)
	return chip
end

-- Places the parts of a candidate row, tall or compact.
local function layoutRow(row, index, compact)
	local height = compact and COMPACT_ROW_H or ROW_H
	row:SetHeight(height)
	local top = -(HEADER_H + ITEM_H + TABLE_HEAD_H + (index - 1) * height)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, top)
	row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, top)

	row.name:ClearAllPoints()
	if compact then
		row.name:SetPoint("LEFT", row, "LEFT", NAME_X, 0)
	else
		row.name:SetPoint("TOPLEFT", row, "TOPLEFT", NAME_X, -10)
	end
	row.class:SetShown(not compact)

	row.chip:SetSize(96, compact and 20 or 26)

	for i, button in ipairs(row.gear) do
		button:ClearAllPoints()
		if compact then
			button:SetSize(GEAR_W - 30, 20)
			button:SetPoint("LEFT", row, "LEFT", GEAR_X, 0)
			button.text:SetWidth(GEAR_W - 30)
		else
			button:SetSize(GEAR_W, 22)
			button:SetPoint("TOPLEFT", row, "TOPLEFT", GEAR_X, -6 - (i - 1) * 22)
			button.text:SetWidth(GEAR_W)
		end
	end
	row.more:ClearAllPoints()
	row.more:SetPoint("LEFT", row, "LEFT", GEAR_X + GEAR_W - 28, 0)

	local buttonHeight = compact and 22 or 34
	row.vote:SetSize(BUTTON_W, buttonHeight)
	row.award:SetSize(BUTTON_W, buttonHeight)
	row.compact = compact
end

local function newRow(index)
	local row = CreateFrame("Button", nil, frame)

	row.bg = UI.NewFill(row, 8)
	UI.SetTextureColor(row.bg, c.bg, 0)
	row.line = row:CreateTexture(nil, "BORDER")
	row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 0)
	row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 0)
	row.line:SetHeight(1)
	UI.SetTextureColor(row.line, c.border, 0.6)

	row.name = UI.NewText(row, 15, c.text)
	row.name:SetWidth(RANK_X - NAME_X - 8)
	row.class = UI.NewText(row, 11, c.muted)
	row.class:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)

	-- The player's guild rank, and the note they wrote (the full note shows on hover).
	row.rank = UI.NewText(row, 12, c.text)
	row.rank:SetPoint("LEFT", row, "LEFT", RANK_X, 0)
	row.rank:SetWidth(RANK_W)
	-- How many items the player was awarded lately; the list of them on hover (council only).
	row.recentButton = CreateFrame("Button", nil, row)
	row.recentButton:SetSize(RECENT_W, 30)
	row.recentButton:SetPoint("LEFT", row, "LEFT", RECENT_X, 0)
	row.recent = UI.NewText(row.recentButton, 13, c.muted, "CENTER")
	row.recent:SetPoint("CENTER", 0, 0)
	row.recent:SetWidth(RECENT_W)
	row.recentButton:SetScript("OnEnter", function(self)
		if not self.player then return end
		CouncilWindow:ShowRecentTooltip(self, self.player)
	end)
	row.recentButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- The random roll the player made (when the Roll column is on); hover for the range.
	row.rollButton = CreateFrame("Button", nil, row)
	row.rollButton:SetSize(ROLL_W, 30)
	row.rollButton:SetPoint("LEFT", row, "LEFT", ROLL_X, 0)
	row.roll = UI.NewText(row.rollButton, 13, c.muted, "CENTER")
	row.roll:SetPoint("CENTER", 0, 0)
	row.roll:SetWidth(ROLL_W)
	row.rollButton:SetScript("OnEnter", function(self)
		if not self.value then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["Random roll"])
		GameTooltip:AddLine(L["Made by the addon when the player answered: 1 to 100, every player a different number. It is only there to choose by when the council cannot."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	row.rollButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.rollButton:Hide()

	row.noteButton = CreateFrame("Button", nil, row)
	row.noteButton:SetSize(NOTE_W, 30)
	row.noteButton:SetPoint("LEFT", row, "LEFT", NOTE_X, 0)
	row.note = UI.NewText(row.noteButton, 12, c.muted)
	row.note:SetPoint("LEFT", row.noteButton, "LEFT", 0, 0)
	row.note:SetWidth(NOTE_W)
	row.noteButton:SetScript("OnEnter", function(self)
		if not self.fullNote or self.fullNote == "" then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["Note"])
		GameTooltip:AddLine(self.fullNote, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	row.noteButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	row.tag = UI.NewText(row, 12, c.gold, "RIGHT") -- "Awarded" on the winner's row
	row.tag:SetPoint("RIGHT", row, "RIGHT", -16, 0)
	row.tag:SetText(strupper(L["Awarded"]))
	row.tag:Hide()

	row.chip = newChip(row, 96, 26, 13)
	row.chip:SetPoint("LEFT", row, "LEFT", RESPONSE_X, 0)

	row.gear = {}
	for i = 1, 2 do
		local button = CreateFrame("Button", nil, row)
		button.text = UI.NewText(button, 12, c.text)
		button.text:SetPoint("LEFT", button, "LEFT", 0, 0)
		button:SetScript("OnEnter", function(self) showItemTooltip(self, self.itemString) end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row.gear[i] = button
	end
	row.more = UI.NewText(row, 11, c.muted, "RIGHT") -- "+1": more gear than the compact row shows
	row.more:SetWidth(28)

	row.votes = CreateFrame("Button", nil, row)
	row.votes:SetSize(60, 32)
	row.votes:SetPoint("LEFT", row, "LEFT", VOTES_X, 0)
	row.votes.text = UI.NewText(row.votes, 16, c.text, "CENTER")
	row.votes.text:SetPoint("CENTER", 0, 0)
	row.votes:SetScript("OnEnter", function(self)
		if not self.voters or #self.voters == 0 then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["Voted for by"])
		for _, name in ipairs(self.voters) do GameTooltip:AddLine(name, 1, 1, 1) end
		GameTooltip:Show()
	end)
	row.votes:SetScript("OnLeave", function() GameTooltip:Hide() end)

	row.vote = UI.NewButton(row, BUTTON_W, 34, L["Vote"], function()
		local ok, message = ALC.Voting:Cast(row.candidate, focus)
		if not ok and message then ALC:Print(message) end
	end)
	row.vote:SetPoint("RIGHT", row, "RIGHT", -12, 0)

	-- Only the loot master hands the item out; the amber frame marks the final step.
	row.award = UI.NewButton(row, BUTTON_W, 34, L["Award"], function()
		ALC.AwardDialog:Ask(row.candidate, focus)
	end)
	row.award:SetPoint("RIGHT", row, "RIGHT", -12, 0)
	row.award:SetSelected(true)
	row.award.label:SetTextColor(c.gold[1], c.gold[2], c.gold[3], 1)
	row.award:Hide()

	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", function(self, button)
		if button == "RightButton" and self.candidate then CouncilWindow:OpenRowMenu(self.candidate) end
	end)
	-- Hover lights the row; leaving returns it to its resting colour (gold for the winner).
	row:SetScript("OnEnter", function(self)
		if self.isWinnerRow then
			UI.SetTextureColor(self.bg, c.gold, 0.22)
		else
			UI.SetTextureColor(self.bg, c.panelHover, 0.5)
		end
	end)
	row:SetScript("OnLeave", function(self)
		if self.isWinnerRow then
			UI.SetTextureColor(self.bg, c.gold, 0.14)
		else
			UI.SetTextureColor(self.bg, c.bg, 0)
		end
	end)
	layoutRow(row, index, false)
	return row
end

-- Lays a History row out: two lines per cell, or one tight line in compact mode.
local function layoutHistoryRow(row, index, compact)
	local height = compact and 30 or 48
	row:SetHeight(height)
	row:ClearAllPoints()
	local top = -(HEADER_H + TABLE_HEAD_H + (index - 1) * height)
	row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + HOFF, top)
	row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, top)
	row.time:ClearAllPoints()
	row.winner:ClearAllPoints()
	if compact then
		row.time:SetPoint("LEFT", row, "LEFT", TIME_X, 0)
		row.winner:SetPoint("LEFT", row, "LEFT", WINNER_X, 0)
	else
		row.time:SetPoint("TOPLEFT", row, "TOPLEFT", TIME_X, -9)
		row.winner:SetPoint("TOPLEFT", row, "TOPLEFT", WINNER_X, -9)
	end
	row.zone:SetShown(not compact)
	row.class:SetShown(not compact)
	row.item:SetSize(HITEM_W, compact and 24 or 36)
	row.item.iconBorder:SetSize(compact and 22 or 30, compact and 22 or 30)
	row.chip:SetHeight(compact and 20 or 24)
end

-- Makes the candidate rows up to `count` (never more than the pool).
function CouncilWindow.EnsureRows(count)
	for i = #CouncilWindow.rows + 1, min(POOL, count) do
		local row = newRow(i)
		layoutRow(row, i, layoutCompact == true)
		row:Hide() -- a row shows itself when it has a candidate to show
		CouncilWindow.rows[i] = row
	end
end

-- A row of the History tab: when, what, to whom, with which answer, and the votes.
local function newHistoryRow(index)
	local row = CreateFrame("Frame", nil, frame)
	row:SetHeight(HISTORY_ROW_H)
	local top = -(HEADER_H + TABLE_HEAD_H + (index - 1) * HISTORY_ROW_H)
	row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + HOFF, top)
	row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, top)

	row.line = row:CreateTexture(nil, "BORDER")
	row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 0)
	row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 0)
	row.line:SetHeight(1)
	UI.SetTextureColor(row.line, c.border, 0.6)

	row.time = UI.NewText(row, 12, c.text)
	row.time:SetPoint("TOPLEFT", row, "TOPLEFT", TIME_X, -9)
	row.zone = UI.NewText(row, 10, c.muted)
	row.zone:SetPoint("TOPLEFT", row.time, "BOTTOMLEFT", 0, -3)
	row.zone:SetWidth(HITEM_X - TIME_X - 10)

	row.item = CreateFrame("Button", nil, row)
	row.item:SetSize(HITEM_W, 36)
	row.item:SetPoint("LEFT", row, "LEFT", HITEM_X, 0)
	row.item.iconBorder = CreateFrame("Frame", nil, row.item)
	row.item.iconBorder:SetSize(30, 30)
	row.item.iconBorder:SetPoint("LEFT", row.item, "LEFT", 0, 0)
	row.item.icon = row.item.iconBorder:CreateTexture(nil, "ARTWORK")
	row.item.icon:SetPoint("TOPLEFT", 1, -1)
	row.item.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	row.item.border = UI.AddBorder(row.item.iconBorder, c.border, 1, 6, "OVERLAY")
	row.item.text = UI.NewText(row.item, 13, c.text)
	row.item.text:SetPoint("LEFT", row.item.iconBorder, "RIGHT", 10, 0)
	row.item.text:SetWidth(HITEM_W - 44)
	row.item:SetScript("OnEnter", function(self) showItemTooltip(self, self.itemString) end)
	row.item:SetScript("OnLeave", function() GameTooltip:Hide() end)

	row.winner = UI.NewText(row, 14, c.text)
	row.winner:SetPoint("TOPLEFT", row, "TOPLEFT", WINNER_X, -9)
	row.winner:SetWidth(HRESPONSE_X - WINNER_X - 10)
	row.class = UI.NewText(row, 11, c.muted)
	row.class:SetPoint("TOPLEFT", row.winner, "BOTTOMLEFT", 0, -3)

	row.chip = newChip(row, 90, 24, 12)
	row.chip:SetPoint("LEFT", row, "LEFT", HRESPONSE_X, 0)

	row.votes = UI.NewText(row, 15, c.text, "CENTER")
	row.votes:SetPoint("LEFT", row, "LEFT", HVOTES_X - 8, 0)
	row.votes:SetWidth(48)
	layoutHistoryRow(row, index, false)
	return row
end

-- A row of the Trade Queue tab: the item, its winner, how long ago, and the buttons.
local function newTradeRow(index)
	local row = CreateFrame("Frame", nil, frame)
	row:SetHeight(TRADE_ROW_H)
	local top = -(HEADER_H + TABLE_HEAD_H + (index - 1) * TRADE_ROW_H)
	row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, top)
	row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, top)

	row.line = row:CreateTexture(nil, "BORDER")
	row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 0)
	row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 0)
	row.line:SetHeight(1)
	UI.SetTextureColor(row.line, c.border, 0.6)

	row.item = CreateFrame("Button", nil, row)
	row.item:SetSize(TITEM_W, 38)
	row.item:SetPoint("LEFT", row, "LEFT", TITEM_X, 0)
	row.item.iconBorder = CreateFrame("Frame", nil, row.item)
	row.item.iconBorder:SetSize(32, 32)
	row.item.iconBorder:SetPoint("LEFT", row.item, "LEFT", 0, 0)
	row.item.icon = row.item.iconBorder:CreateTexture(nil, "ARTWORK")
	row.item.icon:SetPoint("TOPLEFT", 1, -1)
	row.item.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	row.item.border = UI.AddBorder(row.item.iconBorder, c.border, 1, 6, "OVERLAY")
	row.item.text = UI.NewText(row.item, 14, c.text)
	row.item.text:SetPoint("LEFT", row.item.iconBorder, "RIGHT", 10, 0)
	row.item.text:SetWidth(TITEM_W - 46)
	row.item:SetScript("OnEnter", function(self) showItemTooltip(self, self.itemString) end)
	row.item:SetScript("OnLeave", function() GameTooltip:Hide() end)

	row.winner = UI.NewText(row, 14, c.text)
	row.winner:SetPoint("TOPLEFT", row, "TOPLEFT", TWINNER_X, -9)
	row.winner:SetWidth(TWHEN_X - TWINNER_X - 10)
	row.note = UI.NewText(row, 11, c.muted)
	row.note:SetPoint("TOPLEFT", row.winner, "BOTTOMLEFT", 0, -3)

	row.when = UI.NewText(row, 12, c.muted)
	row.when:SetPoint("LEFT", row, "LEFT", TWHEN_X, 0)
	row.when:SetWidth(110)

	row.done = UI.NewButton(row, 74, 30, L["Done"], function() ALC.Trades:MarkDone(row.entryId) end)
	row.done:SetPoint("RIGHT", row, "RIGHT", -10, 0)
	row.trade = UI.NewButton(row, 74, 30, L["Trade"], function()
		local ok, message = ALC.Trades:StartTrade(row.entryId)
		if not ok and message then ALC:Print(message) end
	end)
	row.trade:SetPoint("RIGHT", row.done, "LEFT", -8, 0)
	row.trade:SetSelected(true)
	row.trade.label:SetTextColor(c.gold[1], c.gold[2], c.gold[3], 1)
	return row
end

-- A row of the "next items" list, shown between two sessions to the loot master.
local function newQueueRow(index)
	local row = CreateFrame("Frame", nil, frame)
	row:SetHeight(QUEUE_ROW_H - 6)
	local top = -(HEADER_H + 54 + (index - 1) * QUEUE_ROW_H)
	row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, top)
	row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, top)
	row.bg = UI.NewFill(row, 8)
	UI.SetTextureColor(row.bg, c.panel)
	row.border = UI.AddBorder(row, c.border, 1, 8)

	row.iconBorder = CreateFrame("Frame", nil, row)
	row.iconBorder:SetSize(30, 30)
	row.iconBorder:SetPoint("LEFT", row, "LEFT", 10, 0)
	row.icon = row.iconBorder:CreateTexture(nil, "ARTWORK")
	row.icon:SetPoint("TOPLEFT", 1, -1)
	row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	row.iconRing = UI.AddBorder(row.iconBorder, c.border, 1, 6, "OVERLAY")
	row.name = UI.NewText(row, 14, c.text)
	row.name:SetPoint("LEFT", row.iconBorder, "RIGHT", 12, 0)
	row.name:SetWidth(WIDTH - 2 * PAD - 190)
	row.start = UI.NewButton(row, 90, 30, L["Start"], function()
		local ok, message = ALC.LootDetection:StartSession(row.entryId)
		if not ok and message then ALC:Print(message) end
	end)
	row.start:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	return row
end

local function savePosition()
	local point, _, relPoint, x, y = frame:GetPoint()
	ALC.Settings:SetWindowPosition("council", point, relPoint, x, y)
end

local function restorePosition()
	frame:ClearAllPoints()
	local pos = ALC.Settings:GetWindowPosition("council")
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 360, -20)
	end
end

--------------------------------------------------------------------------------
-- Building the window
--------------------------------------------------------------------------------
local TABS = {
	{ key = "council", icon = "council", label = L["Council"] },
	{ key = "history", icon = "history", label = L["History"] },
	{ key = "trades", icon = "trade", label = L["Trade Queue"], badge = true },
	{ key = "settings", icon = "settings", label = L["Settings"], action = function() ALC.SettingsWindow:Toggle() end },
}

local function buildTabs(header)
	local x = 296
	for _, tab in ipairs(TABS) do
		local button = CreateFrame("Button", nil, header)
		button.tab = tab.key
		button.action = tab.action

		button.icon = button:CreateTexture(nil, "ARTWORK")
		button.icon:SetSize(16, 16)
		button.icon:SetPoint("LEFT", button, "LEFT", 4, 1)
		button.icon:SetTexture(UI.ICONS .. tab.icon)
		button.label = UI.NewText(button, 13, c.muted)
		button.label:SetPoint("LEFT", button.icon, "RIGHT", 8, 0)
		button.label:SetText(tab.label)

		local width = 4 + 16 + 8 + button.label:GetStringWidth() + 14
		if tab.badge then
			-- A count of how many are waiting, in a small amber chip.
			button.badge = CreateFrame("Frame", nil, button)
			button.badge:SetSize(20, 16)
			button.badge:SetPoint("LEFT", button.label, "RIGHT", 6, 0)
			button.badge.bg = UI.NewFill(button.badge, 4)
			UI.SetTextureColor(button.badge.bg, c.gold)
			button.badge.text = UI.NewText(button.badge, 10, c.bg, "CENTER")
			button.badge.text:SetPoint("CENTER", 0, 0)
			button.badge:Hide()
			width = width + 26
		end
		button:SetSize(width, HEADER_H)
		button:SetPoint("LEFT", header, "LEFT", x, 0)
		x = x + width + 10

		button.underline = button:CreateTexture(nil, "OVERLAY")
		button.underline:SetHeight(2)
		button.underline:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
		button.underline:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
		UI.SetTextureColor(button.underline, c.gold)
		button.underline:Hide()

		button:SetScript("OnClick", function(self)
			if self.action then self.action() else CouncilWindow:SetTab(self.tab) end
		end)
		button:SetScript("OnEnter", function(self)
			if activeTab ~= self.tab then
				self.label:SetTextColor(c.text[1], c.text[2], c.text[3], 1)
				self.icon:SetVertexColor(c.text[1], c.text[2], c.text[3], 1)
			end
		end)
		button:SetScript("OnLeave", function() CouncilWindow:Refresh() end)
		CouncilWindow.tabs[tab.key] = button
	end
end

-- The grip in the bottom right corner (Council tab): drag it to show more or fewer rows.
local STRIP_BUTTON, STRIP_GAP, STRIP_COLUMN = 44, 6, 8

-- The item strip is part of the window but hangs outside its left edge.
local function buildStrip()
	CouncilWindow.strip = {}
	-- A small panel of its own, attached to the window's left edge.
	frame.stripPanel = CreateFrame("Frame", nil, frame)
	frame.stripPanel:SetPoint("TOPRIGHT", frame, "TOPLEFT", -4, 0)
	frame.stripPanel:SetSize(STRIP_BUTTON + 2 * STRIP_GAP, STRIP_BUTTON + 2 * STRIP_GAP)
	frame.stripPanel.bg = UI.NewFill(frame.stripPanel, 10)
	UI.SetTextureColor(frame.stripPanel.bg, c.bg)
	UI.AddBorder(frame.stripPanel, c.border, 1, 10)
	frame.stripPanel:Hide()
	for i = 1, ALC.Constants.MAX_SESSION_ITEMS do
		local button = CreateFrame("Button", nil, frame.stripPanel)
		button:SetSize(STRIP_BUTTON, STRIP_BUTTON) -- placed by updateStrip
		button.selected = button:CreateTexture(nil, "BACKGROUND")
		button.selected:SetPoint("TOPLEFT", -3, 3)
		button.selected:SetPoint("BOTTOMRIGHT", 3, -3)
		UI.SetTextureColor(button.selected, c.goldTint)
		button.icon = button:CreateTexture(nil, "ARTWORK")
		button.icon:SetPoint("TOPLEFT", 2, -2)
		button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
		button.ring = UI.AddBorder(button, c.border, 2, 8, "OVERLAY")
		-- A small gold mark on an awarded item.
		button.check = button:CreateTexture(nil, "OVERLAY")
		button.check:SetSize(10, 10)
		button.check:SetPoint("TOPRIGHT", button, "TOPRIGHT", -3, -3)
		UI.SetTextureColor(button.check, c.gold)
		button.badge = CreateFrame("Frame", nil, button)
		button.badge:SetSize(18, 16)
		button.badge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 3, -3)
		button.badge.bg = UI.NewFill(button.badge, 4)
		UI.SetTextureColor(button.badge.bg, c.gold)
		button.badge.text = UI.NewText(button.badge, 10, c.bg, "CENTER")
		button.badge.text:SetPoint("CENTER", 0, 0)
		button:SetScript("OnClick", function(self) if self.item then CouncilWindow:SetFocus(self.item) end end)
		button:SetScript("OnEnter", function(self)
			if not self.itemString then return end
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetHyperlink(self.itemString)
			if self.winner then GameTooltip:AddLine(string.format(L["Awarded to %s"], self.winner), c.gold[1], c.gold[2], c.gold[3]) end
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
		button:Hide()
		CouncilWindow.strip[i] = button
	end
end

local function buildGrip()
	frame.grip = CreateFrame("Button", nil, frame)
	frame.grip:SetSize(14, 14)
	frame.grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
	frame.grip.dots = {}
	for _, spot in ipairs({ { 2, 2 }, { 7, 2 }, { 12, 2 }, { 2, 7 }, { 7, 7 }, { 2, 12 } }) do
		local dot = frame.grip:CreateTexture(nil, "OVERLAY")
		dot:SetSize(2, 2)
		dot:SetPoint("BOTTOMRIGHT", frame.grip, "BOTTOMRIGHT", -(spot[1] - 2), spot[2] - 2)
		UI.SetTextureColor(dot, c.muted, 0.7)
		frame.grip.dots[#frame.grip.dots + 1] = dot
	end
	frame.grip:SetScript("OnEnter", function(self)
		for _, dot in ipairs(self.dots) do UI.SetTextureColor(dot, c.gold, 1) end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(L["Drag to change how many candidates are shown"])
		GameTooltip:Show()
	end)
	frame.grip:SetScript("OnLeave", function(self)
		for _, dot in ipairs(self.dots) do UI.SetTextureColor(dot, c.muted, 0.7) end
		GameTooltip:Hide()
	end)
	frame.grip:SetScript("OnMouseDown", function()
		GameTooltip:Hide()
		CouncilWindow:StartResize()
	end)
	frame.grip:SetScript("OnMouseUp", function() CouncilWindow:StopResize() end)
	frame.grip:Hide()
end

-- The column headings of the Council tab. (Apart from build(): a function may use at most 60
-- outside variables in the game's Lua, and build() is near the limit.)
local function councilHeadings(heading)
	return {
		heading(L["Player"], NAME_X),
		heading(L["Rank"], RANK_X),
		heading(L["Response"], RESPONSE_X),
		heading(L["Current gear"], GEAR_X),
		heading(L["Recent"], RECENT_X, "CENTER", RECENT_W),
		heading(L["Note"], NOTE_X),
		heading(L["Votes"], VOTES_X, "CENTER", 60),
		heading(L["Roll"], ROLL_X, "CENTER", ROLL_W),
	}
end

-- The left side of the History tab: a search field and the list of dates. A click on a date
-- picks it (several can be picked); "All dates" clears the pick. Returns the widgets.
local function buildDatePanel()
	local widgets = {}
	local function add(widget) widgets[#widgets + 1] = widget return widget end

	frame.historySearch = add(UI.NewEditBox(frame, DATE_W, 26, L["Search item or player"], function() end))
	frame.historySearch:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER_H + 4))
	frame.historySearch:HookScript("OnTextChanged", function(self)
		CouncilWindow:SetHistorySearch(self:GetText())
	end)

	local top = HEADER_H + TABLE_HEAD_H + 10
	frame.dateRows = {}
	for i = 1, DATE_ROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetSize(DATE_W - 12, DATE_ROW_H - 2)
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(top + (i - 1) * DATE_ROW_H))
		row:RegisterForClicks("LeftButtonUp")
		row.bg = UI.NewFill(row, 6)
		UI.SetTextureColor(row.bg, c.gold, 0)
		row.label = UI.NewText(row, 13, c.text)
		row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
		row.count = UI.NewText(row, 12, c.muted, "RIGHT")
		row.count:SetPoint("RIGHT", row, "RIGHT", -8, 0)
		row:SetScript("OnClick", function(self)
			if self.key then CouncilWindow:ToggleHistoryDate(self.key) else CouncilWindow:ClearHistoryDates() end
		end)
		row:SetScript("OnEnter", function(self)
			if not self.picked then UI.SetTextureColor(self.bg, c.panelHover, 0.5) end
		end)
		row:SetScript("OnLeave", function(self)
			if not self.picked then UI.SetTextureColor(self.bg, c.gold, 0) end
		end)
		frame.dateRows[i] = add(row)
	end
	frame.dateScroll = add(UI.NewScrollBar(frame, function(newOffset)
		dateOffset = newOffset
		CouncilWindow:Refresh()
	end))
	frame.dateScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + DATE_W - 8, -top)
	frame.dateScroll:SetHeight(DATE_ROWS * DATE_ROW_H - 2)
	frame.dateScroll:Hide()
	return widgets
end

local function build()
	frame = CreateFrame("Frame", nil, UIParent)
	UI.RegisterScaled(frame)
	frame:SetSize(WIDTH, 400)
	frame:SetFrameStrata("HIGH")
	frame:SetFrameLevel(60)
	frame:SetToplevel(true)
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

	frame.logo = UI.NewLogo(header, 30)
	frame.logo:SetPoint("LEFT", header, "LEFT", PAD, 0)
	local title = UI.NewText(header, 15, c.text)
	title:SetPoint("TOPLEFT", frame.logo, "TOPRIGHT", 12, -1)
	title:SetText(strupper(L["Arbiter Loot Council"]))
	local subtitle = UI.NewText(header, 10, c.muted)
	subtitle:SetPoint("BOTTOMLEFT", frame.logo, "BOTTOMRIGHT", 12, 1)
	subtitle:SetText(strupper(L["Allemano Addons"]))

	local close = CreateFrame("Button", nil, header)
	close:SetSize(28, 28)
	close:SetPoint("RIGHT", header, "RIGHT", -14, 0)
	close.text = UI.NewText(close, 22, c.muted, "CENTER")
	close.text:SetPoint("CENTER", 0, 0)
	close.text:SetText("\195\151")
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(c.text[1], c.text[2], c.text[3], 1) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1) end)
	close:SetScript("OnClick", function() CouncilWindow:Hide() end)

	buildTabs(header)

	local function divider(y)
		local line = frame:CreateTexture(nil, "BORDER")
		line:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, y)
		line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, y)
		line:SetHeight(1)
		UI.SetTextureColor(line, c.border)
		return line
	end
	divider(-HEADER_H)

	local function heading(text, x, justify, width, y)
		local fs = UI.NewText(frame, 11, c.muted, justify)
		fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + x, -(y or (HEADER_H + ITEM_H + 12)))
		if width then fs:SetWidth(width) end
		fs:SetText(strupper(text))
		return fs
	end
	local function footerLine()
		local line = frame:CreateTexture(nil, "BORDER")
		line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, FOOTER_H)
		line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, FOOTER_H)
		line:SetHeight(1)
		UI.SetTextureColor(line, c.border)
		return line
	end
	local function centred(y, text)
		local fs = UI.NewText(frame, 13, c.muted, "CENTER")
		fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
		fs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y)
		fs:SetText(text)
		return fs
	end

	-- Council tab ------------------------------------------------------------
	local itemBox = CreateFrame("Frame", nil, frame)
	itemBox:SetSize(ICON, ICON)
	itemBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER_H + 12))
	itemBox:EnableMouse(true)
	frame.icon = itemBox:CreateTexture(nil, "ARTWORK")
	frame.icon:SetPoint("TOPLEFT", 2, -2)
	frame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	frame.iconBorder = UI.AddBorder(itemBox, c.border, 2, 8, "OVERLAY")
	itemBox:SetScript("OnEnter", function(self)
		local target = ALC.Sessions:GetItem(focus)
		if target then showItemTooltip(self, target.itemString) end
	end)
	itemBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

	frame.name = UI.NewText(frame, 17, c.text)
	frame.name:SetPoint("TOPLEFT", itemBox, "TOPRIGHT", 12, 0)
	frame.name:SetWidth(340)
	frame.sub = UI.NewText(frame, 12, c.muted)
	frame.sub:SetPoint("BOTTOMLEFT", itemBox, "BOTTOMRIGHT", 12, 0)
	frame.sub:SetWidth(340)

	frame.progress = UI.NewText(frame, 13, c.muted, "RIGHT")
	frame.progress:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(HEADER_H + 38))
	frame.barBg = frame:CreateTexture(nil, "ARTWORK")
	frame.barBg:SetSize(220, 6)
	frame.barBg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(HEADER_H + 55))
	UI.SetTextureColor(frame.barBg, c.panelHover)
	frame.barFill = frame:CreateTexture(nil, "OVERLAY")
	frame.barFill:SetHeight(6)
	frame.barFill:SetPoint("TOPLEFT", frame.barBg, "TOPLEFT", 0, 0)
	UI.SetTextureColor(frame.barFill, c.gold)

	local itemDivider = divider(-(HEADER_H + ITEM_H))
	local headings = councilHeadings(heading)
	frame.noteHeading, frame.rollHeading = headings[6], headings[8]
	local tableDivider = divider(-(HEADER_H + ITEM_H + TABLE_HEAD_H))
	frame.empty = centred(HEADER_H + ITEM_H + TABLE_HEAD_H + 26, L["Waiting for responses..."])
	frame.footerLine = footerLine()
	frame.lootMaster = UI.NewText(frame, 13, c.muted)
	frame.lootMaster:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 18)
	frame.tally = UI.NewText(frame, 13, c.muted, "RIGHT")
	frame.tally:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 12, 18)

	-- The compact toggle: fewer pixels per candidate when there are many.
	frame.compact = UI.NewCheckbox(frame, L["Compact rows"], function(checked)
		ALC.Settings:SetCompact(checked) -- refreshes this window through the settings event
	end)
	frame.compact:SetSize(150, 24)
	frame.compact:SetPoint("BOTTOM", frame, "BOTTOM", 60, 16)

	-- Players who passed are hidden unless asked for: nothing to vote on, but they can be
	-- taken back by the loot master (right-click).
	frame.showPassed = UI.NewCheckbox(frame, L["Show passed"], function(checked)
		ALC.Settings:SetWindowOption("council", "showPassed", checked)
		offset = 0
		CouncilWindow:Refresh()
	end)
	frame.showPassed:SetSize(130, 24)
	frame.showPassed:SetPoint("RIGHT", frame.compact, "LEFT", -6, 0)

	-- Sorting: one button that steps through the orders.
	frame.sort = UI.NewButton(frame, 150, 24, "", function() CouncilWindow:CycleSortMode() end)
	frame.sort:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(PAD + 12), -(HEADER_H + ITEM_H + 5))

	-- Stopping the session (loot master). The first click asks, the second stops.
	frame.stop = UI.NewButton(frame, 112, 24, L["Stop session"], function() CouncilWindow:StopSession() end)
	frame.stop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(HEADER_H + 8))
	-- Pause / Resume (loot master): no new answers, votes or awards while paused.
	frame.pause = UI.NewButton(frame, 84, 24, L["Pause"], function()
		local ok, message = ALC.Sessions:SetPaused(not ALC.Sessions:IsPaused())
		if not ok and message then ALC:Print(message) end
	end)
	frame.pause:SetPoint("RIGHT", frame.stop, "LEFT", -6, 0)
	-- Disenchant (loot master): gives the item shown to the disenchanter of the settings.
	frame.disenchant = UI.NewButton(frame, 104, 24, L["Disenchant"], function()
		ALC.AwardDialog:AskDisenchant(focus)
	end)
	frame.disenchant:SetPoint("RIGHT", frame.pause, "LEFT", -6, 0)
	frame.disenchant.label:SetTextColor(0.65, 0.45, 0.90, 1)
	frame.disenchant:HookScript("OnEnter", function(self)
		if not self.reason then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(self.reason)
		GameTooltip:Show()
	end)
	frame.disenchant:HookScript("OnLeave", function() GameTooltip:Hide() end)
	frame.pausedTag = UI.NewText(frame, 13, c.danger, "RIGHT")
	frame.pausedTag:SetPoint("RIGHT", frame.disenchant, "LEFT", -12, 0)
	frame.pausedTag:SetText(strupper(L["Paused"]))

	councilStatic = { itemBox, frame.name, frame.sub, frame.progress, frame.barBg, frame.barFill, itemDivider, tableDivider,
		headings[1], headings[2], headings[3], headings[4], headings[5], headings[6], headings[7], headings[8], frame.empty, frame.footerLine, frame.lootMaster,
		frame.tally, frame.compact, frame.showPassed, frame.sort, frame.stop, frame.pause, frame.pausedTag, frame.disenchant }

	-- Shown instead of the Council tab while no session runs.
	frame.idle = centred(HEADER_H + 46, L["No running session. Start one from the loot window."])
	frame.idle:Hide()
	frame.queueLabel = UI.NewText(frame, 11, c.muted)
	frame.queueLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER_H + 26))
	frame.queueLabel:SetText(strupper(L["Next in the loot list"]))
	-- Start every waiting item in one session.
	frame.startAll = UI.NewButton(frame, 130, 26, L["Start all"], function()
		local ok, message = ALC.LootDetection:StartAll()
		if not ok and message then ALC:Print(message) end
	end)
	frame.startAll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(HEADER_H + 18))
	frame.startAll:Hide()
	frame.queueMore = UI.NewText(frame, 12, c.muted)
	frame.queueMore:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER_H + 54 + QUEUE_ROWS * QUEUE_ROW_H))
	queueStatic = { frame.queueLabel, frame.queueMore }
	for i = 1, QUEUE_ROWS do
		CouncilWindow.queueRows[i] = newQueueRow(i)
		CouncilWindow.queueRows[i]:Hide()
	end
	setShown(queueStatic, false)

	-- The rows are made as they are needed, and the rest of the pool a few at a time, so opening
	-- the window never runs one long script (the game stops those: "script ran too long").
	CouncilWindow.EnsureRows(INITIAL_ROWS)
	local function fillPool()
		if #CouncilWindow.rows >= POOL then return end
		CouncilWindow.EnsureRows(#CouncilWindow.rows + 4)
		C_Timer.After(0, fillPool)
	end
	C_Timer.After(0, fillPool)
	frame.scroll = UI.NewScrollBar(frame, function(newOffset)
		offset = newOffset
		CouncilWindow:Refresh()
	end)
	frame.scroll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -(HEADER_H + ITEM_H + TABLE_HEAD_H))
	frame.scroll:SetHeight(DEFAULT_ROWS * ROW_H)
	frame.scroll:Hide()

	-- History tab ------------------------------------------------------------
	local historyHeadings = {
		heading(L["Time"], TIME_X + HOFF, nil, nil, HEADER_H + 12),
		heading(L["Item"], HITEM_X + HOFF, nil, nil, HEADER_H + 12),
		heading(L["Winner"], WINNER_X + HOFF, nil, nil, HEADER_H + 12),
		heading(L["Response"], HRESPONSE_X + HOFF, nil, nil, HEADER_H + 12),
		heading(L["Votes"], HVOTES_X - 8 + HOFF, "CENTER", 48, HEADER_H + 12),
	}
	local historyDivider = divider(-(HEADER_H + TABLE_HEAD_H))
	frame.historyEmpty = centred(HEADER_H + TABLE_HEAD_H + 30, L["No awards recorded on this character yet."])
	frame.historyFooterLine = footerLine()
	frame.historyCount = UI.NewText(frame, 13, c.muted)
	frame.historyCount:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 18)
	-- The history is the council's: players outside it never open this window.
	frame.historyNote = UI.NewText(frame, 12, c.muted)
	frame.historyNote:SetPoint("LEFT", frame.historyCount, "RIGHT", 14, 0)
	frame.historyNote:SetText(L["Only the council sees the history"])
	-- Export the shown awards as text, or clear the picked dates (with a chance to export first).
	frame.historyClear = UI.NewButton(frame, 90, 26, L["Clear"], function()
		ALC.HistoryDialogs:AskClear(CouncilWindow:GetSelectedDates())
	end)
	frame.historyClear:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 14, 13)
	frame.historyClear.label:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1)
	frame.historyExport = UI.NewButton(frame, 90, 26, L["Export"], function()
		ALC.HistoryDialogs:ShowExport(CouncilWindow:GetHistory())
	end)
	frame.historyExport:SetPoint("RIGHT", frame.historyClear, "LEFT", -6, 0)
	historyStatic = { historyHeadings[1], historyHeadings[2], historyHeadings[3], historyHeadings[4], historyHeadings[5],
		historyDivider, frame.historyEmpty, frame.historyFooterLine, frame.historyCount, frame.historyNote, frame.historyExport, frame.historyClear }
	for _, widget in ipairs(buildDatePanel()) do historyStatic[#historyStatic + 1] = widget end
	for i = 1, HISTORY_ROWS do
		CouncilWindow.historyRows[i] = newHistoryRow(i)
	end
	frame.historyScroll = UI.NewScrollBar(frame, function(newOffset)
		historyOffset = newOffset
		CouncilWindow:Refresh()
	end)
	frame.historyScroll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -(HEADER_H + TABLE_HEAD_H))
	frame.historyScroll:SetHeight(HISTORY_ROWS * HISTORY_ROW_H)
	frame.historyScroll:Hide()

	-- Trade Queue tab --------------------------------------------------------
	local tradeHeadings = {
		heading(L["Item"], TITEM_X, nil, nil, HEADER_H + 12),
		heading(L["Winner"], TWINNER_X, nil, nil, HEADER_H + 12),
		heading(L["Awarded"], TWHEN_X, nil, nil, HEADER_H + 12),
	}
	local tradeDivider = divider(-(HEADER_H + TABLE_HEAD_H))
	frame.tradeEmpty = centred(HEADER_H + TABLE_HEAD_H + 30, L["Everything that was awarded has been handed out."])
	frame.tradeFooterLine = footerLine()
	frame.tradeCount = UI.NewText(frame, 13, c.muted)
	frame.tradeCount:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 18)
	tradeStatic = { tradeHeadings[1], tradeHeadings[2], tradeHeadings[3], tradeDivider, frame.tradeEmpty,
		frame.tradeFooterLine, frame.tradeCount }
	for i = 1, TRADE_ROWS do
		CouncilWindow.tradeRows[i] = newTradeRow(i)
	end
	frame.tradeScroll = UI.NewScrollBar(frame, function(newOffset)
		tradeOffset = newOffset
		CouncilWindow:Refresh()
	end)
	frame.tradeScroll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -(HEADER_H + TABLE_HEAD_H))
	frame.tradeScroll:SetHeight(TRADE_ROWS * TRADE_ROW_H)
	frame.tradeScroll:Hide()

	buildGrip()
	buildStrip()

	frame:SetScript("OnMouseWheel", function(_, delta)
		if activeTab == "history" then
			historyOffset = max(0, min(historyOffset - delta, max(0, #CouncilWindow:GetHistory() - HISTORY_ROWS)))
		elseif activeTab == "trades" then
			tradeOffset = max(0, min(tradeOffset - delta, max(0, ALC.Trades:GetPendingCount() - TRADE_ROWS)))
		else
			offset = max(0, min(offset - delta, max(0, #CouncilWindow:GetVisible() - maxRows())))
		end
		CouncilWindow:Refresh()
	end)
	frame:SetScript("OnShow", function() CouncilWindow:Refresh() end)
	-- While a finished session waits to close, the countdown in the header ticks.
	local sinceTick = 0
	frame:SetScript("OnUpdate", function(_, elapsed)
		sinceTick = sinceTick + elapsed
		if sinceTick < 1 then return end
		sinceTick = 0
		if ALC.Sessions:GetFinishLeft() then CouncilWindow:Refresh() end
	end)

	restorePosition()
end

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------
-- The place of an answer among the session's buttons; the order of the table follows it.
local function orderOf(id) return ALC.Responses:GetOrder(id) end

-- How the table is sorted. Every mode ends in the name, so the order is always the same.
CouncilWindow.SORT_MODES = {
	{ key = "response", label = L["By response"] },
	{ key = "votes", label = L["By votes"] },
	{ key = "rank", label = L["By rank"] },
	{ key = "roll", label = L["By roll"] },
	{ key = "name", label = L["By name"] },
}

local COMPARE = {
	response = function(a, b)
		local oa, ob = orderOf(a.response), orderOf(b.response)
		if oa ~= ob then return oa < ob end
		if a.votes ~= b.votes then return a.votes > b.votes end
		return a.name < b.name
	end,
	votes = function(a, b)
		if a.votes ~= b.votes then return a.votes > b.votes end
		local oa, ob = orderOf(a.response), orderOf(b.response)
		if oa ~= ob then return oa < ob end
		return a.name < b.name
	end,
	-- Highest guild rank first (rank 0 is the guild master); players without a rank last.
	rank = function(a, b)
		local ra, rb = a.rankIndex or 99, b.rankIndex or 99
		if ra ~= rb then return ra < rb end
		local oa, ob = orderOf(a.response), orderOf(b.response)
		if oa ~= ob then return oa < ob end
		if a.votes ~= b.votes then return a.votes > b.votes end
		return a.name < b.name
	end,
	-- Highest roll first; an entry without one (from an older version) last.
	roll = function(a, b)
		local ra, rb = a.roll or -1, b.roll or -1
		if ra ~= rb then return ra > rb end
		local oa, ob = orderOf(a.response), orderOf(b.response)
		if oa ~= ob then return oa < ob end
		return a.name < b.name
	end,
	name = function(a, b) return a.name < b.name end,
}

function CouncilWindow:GetSortMode()
	local mode = ALC.Settings:GetWindowOption("council", "sort", "response")
	if mode == "roll" and not ALC.Sessions:HasRolls() then return "response" end -- no roll column: no roll order
	return COMPARE[mode] and mode or "response"
end

function CouncilWindow:SetSortMode(mode)
	if not COMPARE[mode] then return end
	ALC.Settings:SetWindowOption("council", "sort", mode)
	offset = 0
	self:Refresh()
end

-- The next mode in the list, for the button that steps through them.
function CouncilWindow:CycleSortMode()
	local current = self:GetSortMode()
	for i, mode in ipairs(self.SORT_MODES) do
		if mode.key == current then
			local nextMode = self.SORT_MODES[i % #self.SORT_MODES + 1]
			if nextMode.key == "roll" and not ALC.Sessions:HasRolls() then
				nextMode = self.SORT_MODES[(i + 1) % #self.SORT_MODES + 1]
			end
			self:SetSortMode(nextMode.key)
			return
		end
	end
end

function CouncilWindow:ShowsPassed()
	return ALC.Settings:GetWindowOption("council", "showPassed", false) == true
end

-- The candidates the table lists, in the chosen order; those who passed only when asked for.
function CouncilWindow:GetVisible()
	local list = {}
	local showPassed = self:ShowsPassed()
	for _, entry in ipairs(ALC.Candidates:GetList(focus)) do
		if entry.response ~= "PASS" or showPassed then
			entry.votes = ALC.Voting:GetVotes(entry.name, focus)
			list[#list + 1] = entry
		end
	end
	table.sort(list, COMPARE[self:GetSortMode()])
	-- Those who have not answered yet come last, so the council sees who is missing.
	if ALC.Sessions:IsItemOpen(focus) then
		for _, silent in ipairs(ALC.Candidates:GetSilent(focus)) do
			silent.response, silent.gear, silent.votes, silent.waiting = "WAITING", {}, 0, true
			list[#list + 1] = silent
		end
	end
	return list
end

-- The awards in the log, newest first (a new list; the entries are shared).
-- How long ago an award was, in words: "today", "yesterday", "5 days ago".
local function daysAgo(days)
	if days <= 0 then return L["today"] end
	if days == 1 then return L["yesterday"] end
	return string.format(L["%d days ago"], days)
end

-- What a player was awarded lately: the count in the column, the latest on hover.
function CouncilWindow:ShowRecentTooltip(owner, name)
	local count, awards = ALC.Recent:Get(name)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(string.format(L["Awarded in the last %d days"], ALC.Recent:GetDays() or ALC.Settings:GetRecentDays()))
	if count == 0 then
		GameTooltip:AddLine(L["Nothing"], c.muted[1], c.muted[2], c.muted[3])
	end
	for _, award in ipairs(awards) do
		local display = ALC.LootDetection:GetItemDisplay({ itemID = award.itemID, itemString = "item:" .. award.itemID })
		local color = award.color or c.muted
		GameTooltip:AddLine(string.format("%s  \194\183  %s  \194\183  %s", award.label, display.name or ("item " .. award.itemID), daysAgo(award.ago)),
			color[1], color[2], color[3])
	end
	if count > #awards then
		GameTooltip:AddLine(string.format(L["+ %d more"], count - #awards), c.muted[1], c.muted[2], c.muted[3])
	end
	GameTooltip:Show()
end

-- The History tab shows the awards of the picked dates (all dates when none is picked)
-- that match the search text.
function CouncilWindow:GetSelectedDates()
	if next(historyDates) == nil then return nil end
	local copy = {}
	for key in pairs(historyDates) do copy[key] = true end
	return copy
end

function CouncilWindow:ToggleHistoryDate(key)
	historyDates[key] = (not historyDates[key]) or nil
	historyOffset = 0
	self:Refresh()
end

function CouncilWindow:ClearHistoryDates()
	historyDates = {}
	historyOffset = 0
	self:Refresh()
end

function CouncilWindow:GetHistorySearch()
	return historySearch
end

function CouncilWindow:SetHistorySearch(text)
	text = string.lower(text or "")
	if text == historySearch then return end
	historySearch = text
	historyOffset = 0
	self:Refresh()
end

local function matchesSearch(entry, query)
	local itemName = ALC:GetItemInfo(entry.itemString or entry.itemID)
	local haystack = string.lower(table.concat({
		entry.winner or "", entry.class or "", entry.responseLabel or "", entry.zone or "", itemName or "",
	}, "\n"))
	return string.find(haystack, query, 1, true) ~= nil
end

function CouncilWindow:GetHistory()
	local log = ALC.Awards:GetLog()
	local picked = next(historyDates) ~= nil and historyDates or nil
	local query = historySearch ~= "" and historySearch or nil
	local list = {}
	for i = #log, 1, -1 do
		local entry = log[i]
		if not entry.revoked and (not picked or picked[ALC.Awards.DateKey(entry.time)]) and (not query or matchesSearch(entry, query)) then
			list[#list + 1] = entry
		end
	end
	return list
end

-- Fills the date list: "All dates", then the days with awards, newest first.
local function renderDates(self)
	local dates = ALC.Awards:GetDates()
	local total, awards = #dates + 1, 0
	local present = {}
	for _, day in ipairs(dates) do
		awards = awards + day.count
		present[day.key] = true
	end
	for key in pairs(historyDates) do
		if not present[key] then historyDates[key] = nil end -- a date that was cleared
	end
	dateOffset = max(0, min(dateOffset, max(0, total - DATE_ROWS)))
	local none = next(historyDates) == nil
	for i = 1, DATE_ROWS do
		local row = frame.dateRows[i]
		local index = dateOffset + i
		local day = index > 1 and dates[index - 1] or nil
		if index == 1 then
			row.key, row.picked = nil, none
			row.label:SetText(L["All dates"])
			row.count:SetText(tostring(awards))
			row:Show()
		elseif day then
			row.key, row.picked = day.key, historyDates[day.key] == true
			row.label:SetText(day.key)
			row.count:SetText(tostring(day.count))
			row:Show()
		else
			row.key, row.picked = nil, false
			row:Hide()
		end
		if row:IsShown() then
			UI.SetTextureColor(row.bg, c.gold, row.picked and 0.28 or 0)
			local tone = row.picked and c.gold or c.text
			row.label:SetTextColor(tone[1], tone[2], tone[3], 1)
		end
	end
	frame.dateScroll:Update(total, DATE_ROWS, dateOffset)
end

local function localizedClass(class)
	return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class or ""
end

--------------------------------------------------------------------------------
-- Rendering: the Council tab
--------------------------------------------------------------------------------
local function renderRow(row, entry, myVote, topVotes, isLM, compact, open, isWinner)
	row.candidate = entry.name
	-- The player who got the item stays in the list, marked.
	row.isWinnerRow = isWinner == true
	UI.SetTextureColor(row.bg, isWinner and c.gold or c.bg, isWinner and 0.14 or 0)
	row.tag:SetShown(isWinner == true)
	local classColor = UI.ClassColor(entry.class)
	row.name:SetTextColor(classColor[1], classColor[2], classColor[3], 1)
	if entry.waiting then row.name:SetTextColor(classColor[1], classColor[2], classColor[3], 0.55) end
	row.name:SetText(entry.name)
	row.class:SetText(localizedClass(entry.class))
	row.rank:SetText(entry.rank or "")
	row.note:SetText(entry.note or "")
	row.noteButton.fullNote = entry.note
	row.rollButton.value = entry.roll
	if entry.roll then
		row.roll:SetText(tostring(entry.roll))
		row.roll:SetTextColor(c.text[1], c.text[2], c.text[3], 1)
	else
		row.roll:SetText("\226\128\148")
		row.roll:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
	end
	local recentCount = ALC.Recent:Get(entry.name)
	row.recentButton.player = entry.name
	row.recent:SetText(recentCount > 0 and tostring(recentCount) or "\226\128\148") -- em dash
	if recentCount > 0 then
		row.recent:SetTextColor(c.text[1], c.text[2], c.text[3], 1)
	else
		row.recent:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
	end

	local response = not entry.waiting and ALC.Responses:Get(entry.response) or nil
	local rc = response and response.color or c.muted
	UI.SetTextureColor(row.chip.bg, rc, entry.waiting and 0.1 or 0.22)
	row.chip.label:SetTextColor(rc[1], rc[2], rc[3], 1)
	row.chip.label:SetText(entry.waiting and L["Waiting"] or (response and response.label or entry.response))

	for i, button in ipairs(row.gear) do
		local itemString = entry.gear[i]
		button.itemString = itemString
		if itemString and not (compact and i > 1) then
			local _, itemID = ALC:ParseItem(itemString)
			local display = ALC.LootDetection:GetItemDisplay({ itemString = itemString, itemID = itemID })
			local qc = UI.QualityColor(display.quality)
			button.text:SetTextColor(qc[1], qc[2], qc[3], 1)
			button.text:SetText(display.name or L["Loading..."])
			button:Show()
		else
			button:Hide()
		end
	end
	if #entry.gear == 0 and not entry.waiting then
		row.gear[1].text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
		row.gear[1].text:SetText(L["Nothing equipped"])
		row.gear[1]:Show()
	end
	local extra = compact and (#entry.gear - 1) or 0
	row.more:SetText(extra > 0 and ("+" .. extra) or "")

	local count, voters = ALC.Voting:GetVotes(entry.name, focus)
	row.votes.voters = voters
	if count == 0 then
		row.votes.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
		row.votes.text:SetText("\226\128\148") -- em dash
	else
		local top = count == topVotes
		row.votes.text:SetTextColor(top and c.gold[1] or c.text[1], top and c.gold[2] or c.text[2], top and c.gold[3] or c.text[3], 1)
		row.votes.text:SetText(tostring(count))
	end

	local mine = myVote ~= nil and ALC:SameName(myVote, entry.name)
	row.vote:SetLabel(mine and L["Voted"] or L["Vote"])
	row.vote:SetSelected(mine)

	-- The loot master also gets Award; Vote then moves left to make room. Nothing to do
	-- for an item that was awarded.
	row.vote:ClearAllPoints()
	if isLM then
		row.vote:SetPoint("RIGHT", row.award, "LEFT", -8, 0)
		row.award:SetShown(open and entry.response ~= "PASS" and not entry.waiting)
	else
		row.vote:SetPoint("RIGHT", row, "RIGHT", -12, 0)
		row.award:Hide()
	end
	row.vote:SetShown(open and entry.response ~= "PASS" and not entry.waiting) -- nothing to vote on for a player who passed or has not answered
	row:Show()
end

local function hideCouncilRows(self)
	for _, row in ipairs(self.rows) do row:Hide() end
	for _, button in ipairs(self.strip) do button:Hide() end
	frame.stripPanel:Hide()
	frame.scroll:Hide()
	frame.grip:Hide()
end

local function hideHistory(self)
	setShown(historyStatic, false)
	for _, row in ipairs(self.historyRows) do row:Hide() end
	frame.historyScroll:Hide()
end

local function hideTrades(self)
	setShown(tradeStatic, false)
	for _, row in ipairs(self.tradeRows) do row:Hide() end
	frame.tradeScroll:Hide()
end

local function hideQueue(self)
	setShown(queueStatic, false)
	if frame.startAll then frame.startAll:Hide() end
	for _, row in ipairs(self.queueRows) do row:Hide() end
end

-- The strip of items at the left edge of the window: one button per item of the session,
-- shown when there is more than one. A click chooses the item the table is about.
local function updateStrip(self, session)
	local count = #session.items
	-- The strip hangs outside the window: keep it on the screen too.
	local columns = count > 1 and math.ceil(count / STRIP_COLUMN) or 0
	local rows = count > 1 and math.ceil(count / math.max(columns, 1)) or 0
	local panelWidth = columns * (STRIP_BUTTON + STRIP_GAP) + STRIP_GAP
	frame.stripPanel:SetShown(count > 1)
	frame.stripPanel:SetSize(panelWidth, rows * (STRIP_BUTTON + STRIP_GAP) + STRIP_GAP)
	frame:SetClampRectInsets(count > 1 and (panelWidth + 4) or 0, 0, 0, 0)
	columns = max(columns, 1)
	for i, button in ipairs(self.strip) do
		local item = session.items[i]
		if item and count > 1 then
			local display = ALC.LootDetection:GetItemDisplay({ itemString = item.itemString, itemID = item.itemID })
			button.item = i
			button.itemString = item.itemString
			button.winner = item.winner
			button.icon:SetTexture(display.icon or UNKNOWN_ICON)
			button.icon:SetDesaturated(item.winner ~= nil)
			button.icon:SetVertexColor(1, 1, 1, item.winner and 0.55 or 1)
			local qc = UI.QualityColor(display.quality)
			button.ring:SetColor(i == focus and c.gold or c.border)
			button.check:SetShown(item.winner ~= nil)
			-- Open items: how many want it (grey zero when everybody who answered passed).
			local counts = ALC.Candidates:GetCounts(i)
			button.badge.text:SetText(tostring(counts.wanting))
			button.badge.bg:SetColor(counts.wanting > 0 and c.gold or c.muted)
			button.badge:SetShown(item.winner == nil and counts.responded > 0)
			-- Items read left to right, row by row; the first column is next to the window.
			local column, row = (i - 1) % columns, math.floor((i - 1) / columns)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", frame.stripPanel, "TOPLEFT",
				STRIP_GAP + column * (STRIP_BUTTON + STRIP_GAP), -(STRIP_GAP + row * (STRIP_BUTTON + STRIP_GAP)))
			button.selected:SetShown(i == focus)
			button:Show()
		else
			button.item = nil
			button:Hide()
		end
	end
end

-- The Roll column: shown when it is on in Settings, then the note is narrower.
local function applyRollColumn(self)
	local on = ALC.Sessions:HasRolls()
	local noteX, noteW = on and NOTE_NARROW_X or NOTE_X, on and NOTE_NARROW_W or NOTE_W
	for _, row in ipairs(self.rows) do
		row.noteButton:ClearAllPoints()
		row.noteButton:SetPoint("LEFT", row, "LEFT", noteX, 0)
		row.noteButton:SetSize(noteW, 30)
		row.note:SetWidth(noteW)
		row.rollButton:SetShown(on)
	end
	frame.noteHeading:ClearAllPoints()
	frame.noteHeading:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + noteX, -(HEADER_H + ITEM_H + 12))
	frame.rollHeading:SetShown(on)
end

local function renderCouncil(self, session)
	setShown(councilStatic, true)
	frame.idle:Hide()
	hideQueue(self)
	applyRollColumn(self)

	local compact = isCompact()
	if layoutCompact ~= compact then
		for index, row in ipairs(self.rows) do layoutRow(row, index, compact) end
		layoutCompact = compact
	end
	local rowH = compact and COMPACT_ROW_H or ROW_H
	local rowsAllowed = maxRows()

	if focus > #session.items then focus = #session.items end
	local target = session.items[focus]
	local display = ALC.LootDetection:GetItemDisplay({ itemString = target.itemString, itemID = target.itemID })
	frame.icon:SetTexture(display.icon or UNKNOWN_ICON)
	local qc = UI.QualityColor(display.quality)
	frame.iconBorder:SetColor(qc)
	frame.name:SetTextColor(qc[1], qc[2], qc[3], 1)
	frame.name:SetText(display.name or L["Loading..."])
	local sub = display.subtitle
	if #session.items > 1 then
		sub = string.format(L["Item %d of %d"], focus, #session.items) .. (sub ~= "" and (" \194\183 " .. sub) or "")
	end
	if target.winner then
		sub = string.format(L["Awarded to %s"], target.winner)
		if session.isLM then sub = sub .. " \194\183 " .. L["right-click the winner to undo"] end
	end
	frame.sub:SetText(sub)
	frame.sub:SetTextColor(target.winner and c.gold[1] or c.muted[1], target.winner and c.gold[2] or c.muted[2], target.winner and c.gold[3] or c.muted[3], 1)
	updateStrip(self, session)

	local counts = ALC.Candidates:GetCounts(focus)
	local total = counts.responded + counts.silent
	frame.progress:SetText(string.format("%d/%d %s", counts.responded, total, L["responded"]))
	local finishLeft = ALC.Sessions:GetFinishLeft()
	if finishLeft then
		finishLeft = math.ceil(finishLeft)
		frame.progress:SetText(string.format(L["All awarded \194\183 closing in %d:%02d"], math.floor(finishLeft / 60), finishLeft % 60))
	end
	frame.barFill:SetWidth(max(1, 220 * (total > 0 and counts.responded / total or 0)))
	frame.compact:SetChecked(compact)
	for _, mode in ipairs(self.SORT_MODES) do
		if mode.key == self:GetSortMode() then frame.sort:SetLabel(L["Sort"] .. ": " .. mode.label) end
	end
	frame.stop:SetShown(session.isLM == true)
	frame.pause:SetShown(session.isLM == true and not session.finishing)
	frame.pause:SetLabel(session.paused and L["Resume"] or L["Pause"])
	frame.pausedTag:SetShown(session.paused == true)
	local canDisenchant, deReason = ALC.Awards:CanDisenchant()
	frame.disenchant:SetShown(session.isLM == true and target.winner == nil and not session.finishing)
	frame.disenchant:SetAvailable(canDisenchant and not session.paused)
	frame.disenchant.reason = (not canDisenchant) and deReason or nil
	if canDisenchant and not session.paused then frame.disenchant.label:SetTextColor(0.65, 0.45, 0.90, 1) end
	if session.finishing then
		frame.stop:SetLabel(L["Close now"])
	elseif not stopArmed then
		frame.stop:SetLabel(L["Stop session"])
	end
	if not session.isLM then disarmStop() end

	local list = self:GetVisible()
	local count = #list
	offset = max(0, min(offset, max(0, count - rowsAllowed)))
	local topVotes = 0
	for _, entry in ipairs(list) do
		if entry.votes > topVotes then topVotes = entry.votes end
	end

	local myVote = ALC.Voting:GetMyVote(focus)
	local shown = min(count - offset, rowsAllowed)
	CouncilWindow.EnsureRows(shown)
	for i = 1, #self.rows do
		local row = self.rows[i]
		local entry = list[offset + i]
		if entry and i <= shown then
			renderRow(row, entry, myVote, topVotes, session.isLM, compact, target.winner == nil and not session.paused,
				target.winner ~= nil and ALC:SameName(target.winner, entry.name))
		else
			row.candidate = nil
			row:Hide()
		end
	end
	frame.empty:SetShown(count == 0)
	frame.showPassed:SetChecked(self:ShowsPassed())
	if count == 0 then
		local passed = counts.passed
		frame.empty:SetText(passed > 0 and string.format(L["Everybody who answered passed (%d). Tick Show passed to see them."], passed)
			or L["Waiting for responses..."])
	end
	frame.scroll:SetHeight(max(shown, 1) * rowH)
	frame.scroll:Update(count, rowsAllowed, offset)
	frame.grip:Show()

	frame.lootMaster:SetText(L["Loot master"] .. ": " .. session.lm)
	frame.tally:SetText(string.format("%d %s \194\183 %d %s", counts.passed, L["passed"], counts.silent, L["not responded"]))

	frame:SetHeight(HEADER_H + ITEM_H + TABLE_HEAD_H + max(shown, 2) * rowH + FOOTER_H)
end

-- The next pending items of the loot list.
local function pendingItems()
	local list = {}
	for _, entry in ipairs(ALC.LootDetection:GetItems()) do
		if entry.status == ALC.LootDetection.STATUS.PENDING then list[#list + 1] = entry end
	end
	return list
end

-- The Council tab without a session. The loot master sees the next items of the loot list
-- with a Start button, so the next session is one click away and no window changes;
-- everybody else sees a hint.
local function renderIdle(self)
	setShown(councilStatic, false)
	hideCouncilRows(self)

	local isLM = ALC.Council:AmLootMaster()
	local pending = isLM and pendingItems() or {}
	if #pending == 0 then
		hideQueue(self)
		frame.idle:Show()
		frame:SetHeight(HEADER_H + 130)
		return
	end

	frame.idle:Hide()
	frame.queueLabel:Show()
	frame.startAll:SetShown(#pending > 1)
	frame.startAll:SetLabel(string.format("%s (%d)", L["Start all"], min(#pending, ALC.Constants.MAX_SESSION_ITEMS)))
	local shown = min(#pending, QUEUE_ROWS)
	for i = 1, QUEUE_ROWS do
		local row = self.queueRows[i]
		local entry = pending[i]
		if entry and i <= shown then
			local display = ALC.LootDetection:GetItemDisplay(entry)
			row.entryId = entry.id
			row.icon:SetTexture(display.icon or UNKNOWN_ICON)
			local qc = UI.QualityColor(display.quality)
			row.iconRing:SetColor(qc)
			row.name:SetTextColor(qc[1], qc[2], qc[3], 1)
			row.name:SetText(display.name or L["Loading..."])
			row.start:SetAvailable(isLM)
			row:Show()
		else
			row.entryId = nil
			row:Hide()
		end
	end
	local more = #pending - shown
	frame.queueMore:SetText(more > 0 and string.format(L["+ %d more in the loot list"], more) or "")
	frame.queueMore:SetShown(more > 0)
	frame:SetHeight(HEADER_H + 54 + shown * QUEUE_ROW_H + (more > 0 and 30 or 12) + 20)
end

--------------------------------------------------------------------------------
-- Rendering: the History tab
--------------------------------------------------------------------------------
local function renderHistoryRow(row, entry)
	row.time:SetText(date("%d %b %H:%M", entry.time or 0))
	row.zone:SetText(entry.zone or "")

	local display = ALC.LootDetection:GetItemDisplay({ itemString = entry.itemString, itemID = entry.itemID })
	row.item.itemString = entry.itemString
	row.item.icon:SetTexture(display.icon or UNKNOWN_ICON)
	local qc = UI.QualityColor(display.quality)
	row.item.border:SetColor(qc)
	row.item.text:SetTextColor(qc[1], qc[2], qc[3], 1)
	row.item.text:SetText(display.name or L["Loading..."])

	local cc = UI.ClassColor(entry.class)
	row.winner:SetTextColor(cc[1], cc[2], cc[3], 1)
	row.winner:SetText(entry.winner)
	row.class:SetText(localizedClass(entry.class))

	-- The award log keeps the label and colour the answer had at the time.
	local response = ALC.Responses:Get(entry.response)
	local rc = entry.responseColor or (response and response.color) or c.muted
	UI.SetTextureColor(row.chip.bg, rc, 0.22)
	row.chip.label:SetTextColor(rc[1], rc[2], rc[3], 1)
	row.chip.label:SetText(entry.responseLabel or (response and response.label) or tostring(entry.response))

	local votes = entry.votes or 0
	row.votes:SetTextColor(votes > 0 and c.text[1] or c.muted[1], votes > 0 and c.text[2] or c.muted[2], votes > 0 and c.text[3] or c.muted[3], 1)
	row.votes:SetText(votes > 0 and tostring(votes) or "\226\128\148")
	row:Show()
end

local function renderHistory(self)
	setShown(councilStatic, false)
	hideQueue(self)
	frame.idle:Hide()
	hideCouncilRows(self)
	hideTrades(self)
	setShown(historyStatic, true)

	local compact = isCompact()
	if historyLayout ~= compact then
		for index, historyRow in ipairs(self.historyRows) do layoutHistoryRow(historyRow, index, compact) end
		HISTORY_ROW_H = compact and 30 or 48
		frame.historyScroll:SetHeight(HISTORY_ROWS * HISTORY_ROW_H)
		historyLayout = compact
	end

	local list = self:GetHistory()
	local count = #list
	historyOffset = max(0, min(historyOffset, max(0, count - HISTORY_ROWS)))
	local shown = min(count - historyOffset, HISTORY_ROWS)
	for i = 1, HISTORY_ROWS do
		local row = self.historyRows[i]
		local entry = list[historyOffset + i]
		if entry and i <= shown then renderHistoryRow(row, entry) else row:Hide() end
	end
	frame.historyEmpty:SetShown(count == 0)
	local backupCount = ALC.Awards:GetBackupInfo()
	frame.historyEmpty:SetText(backupCount
		and string.format(L["No awards in the history. A backup of %d awards can be restored with /alc history restore."], backupCount)
		or ((#ALC.Settings:GetAwardLog() > 0) and L["No awards match."] or L["No awards recorded on this character yet."]))
	frame.historyClear:SetAvailable(#ALC.Settings:GetAwardLog() > 0)
	frame.historyExport:SetAvailable(count > 0)
	local picked = 0
	for _ in pairs(historyDates) do picked = picked + 1 end
	local summary = string.format("%d %s", count, count == 1 and L["award"] or L["awards"])
	if picked > 0 then summary = summary .. string.format(" \194\183 %d %s", picked, picked == 1 and L["date"] or L["dates"]) end
	if historySearch ~= "" then summary = summary .. string.format(" \194\183 \"%s\"", historySearch) end
	frame.historyCount:SetText(summary)
	frame.historyClear.label:SetText(picked > 0 and L["Clear dates"] or L["Clear"])
	renderDates(self)
	frame.historyScroll:Update(count, HISTORY_ROWS, historyOffset)
	frame:SetHeight(HEADER_H + TABLE_HEAD_H + max(shown, 8) * HISTORY_ROW_H + FOOTER_H)
end

--------------------------------------------------------------------------------
-- Rendering: the Trade Queue tab
--------------------------------------------------------------------------------

-- "just now", "5 min ago", "2 h ago".
local function timeAgo(since)
	if not since then return "" end
	local seconds = max(0, time() - since)
	if seconds < 60 then return L["just now"] end
	if seconds < 3600 then return string.format(L["%d min ago"], math.floor(seconds / 60)) end
	return string.format(L["%d h ago"], math.floor(seconds / 3600))
end

local function renderTradeRow(row, entry)
	row.entryId = entry.id
	local display = ALC.LootDetection:GetItemDisplay(entry)
	row.item.itemString = entry.itemString
	row.item.icon:SetTexture(display.icon or UNKNOWN_ICON)
	local qc = UI.QualityColor(display.quality)
	row.item.border:SetColor(qc)
	row.item.text:SetTextColor(qc[1], qc[2], qc[3], 1)
	row.item.text:SetText(display.name or L["Loading..."])

	-- The winner, in class colour when they are in the group.
	local unit = ALC:FindUnitByName(entry.winner)
	local class = unit and select(2, UnitClass(unit))
	local cc = class and UI.ClassColor(class) or c.text
	row.winner:SetTextColor(cc[1], cc[2], cc[3], 1)
	row.winner:SetText(entry.winner)
	local note = unit and "" or L["Not in the group right now"]
	local left = ALC.LootDetection:GetTradeTimeLeft(entry)
	if left then
		note = (note ~= "" and (note .. " \194\183 ") or "") .. format(L["BoP %s"], ALC.LootWindow.FormatTradeTime(left))
	end
	row.note:SetText(note)
	row.when:SetText(timeAgo(entry.awardedAt))
	row.trade:SetAvailable(unit ~= nil and not ALC:SameName(entry.winner, ALC:PlayerName()))
	row:Show()
end

local function renderTrades(self)
	setShown(councilStatic, false)
	hideQueue(self)
	frame.idle:Hide()
	hideCouncilRows(self)
	hideHistory(self)
	setShown(tradeStatic, true)

	local list = ALC.Trades:GetPending()
	local count = #list
	tradeOffset = max(0, min(tradeOffset, max(0, count - TRADE_ROWS)))
	local shown = min(count - tradeOffset, TRADE_ROWS)
	for i = 1, TRADE_ROWS do
		local row = self.tradeRows[i]
		local entry = list[tradeOffset + i]
		if entry and i <= shown then renderTradeRow(row, entry) else row.entryId = nil; row:Hide() end
	end
	-- Only the loot master has the items, so only the loot master has a queue.
	local isLM = ALC.Council:AmLootMaster()
	frame.tradeEmpty:SetText(isLM and L["Everything that was awarded has been handed out."]
		or L["The trade queue is only for the loot master, who has the items and hands them out."])
	frame.tradeEmpty:SetShown(count == 0)
	frame.tradeCount:SetText(isLM and string.format("%d %s", count, L["waiting"]) or L["Loot master only"])
	frame.tradeScroll:Update(count, TRADE_ROWS, tradeOffset)
	frame:SetHeight(HEADER_H + TABLE_HEAD_H + max(shown, 3) * TRADE_ROW_H + FOOTER_H)
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------
local function updateTabs(self)
	for key, button in pairs(self.tabs) do
		local active = key == activeTab
		button.underline:SetShown(active)
		local color = active and c.gold or c.muted
		button.label:SetTextColor(color[1], color[2], color[3], 1)
		button.icon:SetVertexColor(color[1], color[2], color[3], 1)
		if button.badge then
			local waiting = ALC.Trades:GetPendingCount()
			button.badge:SetShown(waiting > 0)
			button.badge.text:SetText(tostring(waiting))
		end
	end
end

function CouncilWindow:Refresh()
	if not frame or not frame:IsShown() then return end
	updateTabs(self)

	if activeTab == "history" then
		renderHistory(self)
	elseif activeTab == "trades" then
		renderTrades(self)
	else
		hideHistory(self)
		hideTrades(self)
		local session = ALC.Sessions:GetSession()
		if session then renderCouncil(self, session) else renderIdle(self) end
	end
end

--------------------------------------------------------------------------------
-- Resizing with the grip: the top edge stays put, the window grows downwards and the
-- number of candidate rows follows the mouse.
--------------------------------------------------------------------------------
local function resizeStep()
	local _, cursorY = GetCursorPosition()
	cursorY = cursorY / frame:GetEffectiveScale()
	local body = (frame:GetTop() - cursorY) - (HEADER_H + ITEM_H + TABLE_HEAD_H + FOOTER_H)
	local rows = max(MIN_ROWS, min(POOL, math.floor(body / rowHeight() + 0.5)))
	if rows ~= maxRows() then
		ALC.Settings:SetWindowOption("council", "maxRows", rows)
		CouncilWindow:Refresh()
	end
end

function CouncilWindow:StartResize()
	if not frame then return end
	local left, top = frame:GetLeft(), frame:GetTop()
	if left and top then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	end
	frame.grip:SetScript("OnUpdate", resizeStep)
end

function CouncilWindow:StopResize()
	if not frame then return end
	frame.grip:SetScript("OnUpdate", nil)
	savePosition()
end

--------------------------------------------------------------------------------
-- Stop session and the right-click menu
--------------------------------------------------------------------------------
function disarmStop()
	stopArmed = false
	if frame and frame.stop then frame.stop:SetLabel(L["Stop session"]) end
end

-- The first click asks "Sure?", the second stops the session; after 4 s it goes back.
function CouncilWindow:StopSession()
	local session = ALC.Sessions:GetSession()
	if not session or not session.isLM then return end
	if session.finishing then -- everything is awarded: close at once, no question
		disarmStop()
		local ok, message = ALC.Sessions:Cancel("awarded")
		if not ok and message then ALC:Print(message) end
		return
	end
	if not stopArmed then
		stopArmed = true
		frame.stop:SetLabel(L["Sure?"])
		C_Timer.After(4, function()
			if stopArmed then disarmStop() end
		end)
		return
	end
	disarmStop()
	local ok, message = ALC.Sessions:Cancel()
	if not ok and message then ALC:Print(message) end
end

-- What the right-click menu of a candidate offers. The council can vote; the loot master
-- can also award, change the answer and take the player out of the running.
function CouncilWindow:GetRowMenu(name)
	local session = ALC.Sessions:GetSession()
	local candidate = ALC.Candidates:Get(name, focus)
	if not session or not session.isCouncil or not candidate then return {} end
	if not ALC.Sessions:IsItemOpen(focus) then
		-- Awarded: the loot master can take the award back from the winner's row.
		local awarded = session.items[focus] and session.items[focus].winner
		if not (session.isLM and awarded and ALC:SameName(awarded, candidate.name)) then return {} end
		return { {
			label = L["Undo award"], color = c.danger,
			onClick = function()
				local ok, winner, handedOut = ALC.Awards:Revoke(focus)
				if not ok then
					if winner then ALC:Print(winner) end
				elseif handedOut and not ALC:SameName(winner, ALC:PlayerName()) then
					ALC:Print(L["%s may already have the item: ask them to trade it back."], winner)
				end
			end,
		} }
	end

	local items = {}
	local function changeResponse()
		items[#items + 1] = { label = L["Change response"], header = true }
		for _, response in ipairs(ALC.Responses:GetSet()) do
			items[#items + 1] = {
				label = response.label, color = response.color,
				enabled = response.id ~= candidate.response,
				onClick = function()
					local ok, message = ALC.Candidates:SetResponse(candidate.name, response.id, focus)
					if not ok and message then ALC:Print(message) end
				end,
			}
		end
	end
	-- Somebody who passed can only be taken back by the loot master.
	if candidate.response == "PASS" then
		if session.isLM then changeResponse() end
		return items
	end
	local myVote = ALC.Voting:GetMyVote(focus)
	local mine = myVote ~= nil and ALC:SameName(myVote, candidate.name)
	-- Paused: no voting or awarding; the loot master can still change answers.
	if not session.paused then
		items[#items + 1] = {
			label = mine and L["Voted"] or L["Vote"],
			onClick = function()
				local ok, message = ALC.Voting:Cast(candidate.name, focus)
				if not ok and message then ALC:Print(message) end
			end,
		}
	end
	if not session.isLM then return items end

	if not session.paused then
		items[#items + 1] = {
			label = L["Award"], color = c.gold,
			onClick = function() ALC.AwardDialog:Ask(candidate.name, focus) end,
		}
	end
	changeResponse()
	items[#items + 1] = {
		label = L["Remove from consideration"],
		onClick = function()
			local ok, message = ALC.Candidates:SetResponse(candidate.name, "PASS", focus)
			if not ok and message then ALC:Print(message) end
		end,
	}
	return items
end

function CouncilWindow:OpenRowMenu(name)
	local items = self:GetRowMenu(name)
	if #items > 0 then ALC.ContextMenu:Open(items, name) end
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------
local function ensureBuilt()
	if frame then return end
	-- A build that fails half way must not leave a broken frame behind.
	local ok, err = pcall(build)
	if not ok then
		frame = nil
		error(err, 0)
	end
end

function CouncilWindow:GetTab()
	return activeTab
end

-- The item of the session the Council tab shows (1 = the first).
function CouncilWindow:GetFocus()
	return focus
end

function CouncilWindow:SetFocus(item)
	local count = ALC.Sessions:GetItemCount()
	if count == 0 or not item or item < 1 or item > count then return false end
	focus = item
	offset = 0
	ALC.ContextMenu:Hide()
	self:Refresh()
	return true
end

-- Switches tab. The Council tab is for the council; History and Trade Queue are for anybody.
function CouncilWindow:SetTab(tab)
	if tab ~= "council" and tab ~= "history" and tab ~= "trades" then return end
	if tab == "council" then
		local session = ALC.Sessions:GetSession()
		if session and not session.isCouncil then
			ALC:Print(L["Only the council can open the voting window."])
			return
		end
	end
	activeTab = tab
	self:Refresh()
end

local function open(self, tab)
	ensureBuilt()
	activeTab = tab
	frame:Show()
	ALC.Settings:SetWindowShown("council", true)
	self:Refresh()
end

-- Only the council opens the voting tab, during a session. Whether the window is open is
-- remembered across a /reload.
function CouncilWindow:Show()
	local session = ALC.Sessions:GetSession()
	if not session then
		ALC:Print(L["There is no active session."])
		return
	end
	if not session.isCouncil then
		ALC:Print(L["Only the council can open the voting window."])
		return
	end
	open(self, "council")
end

function CouncilWindow:ShowHistory() open(self, "history") end
function CouncilWindow:ShowTrades() open(self, "trades") end

function CouncilWindow:Hide()
	if frame then frame:Hide() end
	ALC.Settings:SetWindowShown("council", false)
end

function CouncilWindow:IsShown()
	return frame ~= nil and frame:IsShown()
end

function CouncilWindow:Toggle()
	if self:IsShown() then self:Hide() else self:Show() end
end

function CouncilWindow:ToggleHistory()
	if self:IsShown() and activeTab == "history" then self:Hide() else self:ShowHistory() end
end

function CouncilWindow:ToggleTrades()
	if self:IsShown() and activeTab == "trades" then self:Hide() else self:ShowTrades() end
end

-- After a reload the session is back: reopen the window if it was open.
local function reopen()
	local session = ALC.Sessions:GetSession()
	if session and session.isCouncil and ALC.Settings:GetWindowShown("council") then
		CouncilWindow:Show()
	end
end

function CouncilWindow:Init()
	local register = ALC.Events.Register
	local refresh = function() CouncilWindow:Refresh() end
	if C_Timer and C_Timer.NewTicker then
		C_Timer.NewTicker(30, function() if activeTab == "trades" then CouncilWindow:Refresh() end end)
	end
	register(self, "ALC_CANDIDATES_CHANGED", refresh)
	register(self, "ALC_VOTING_CHANGED", refresh)
	register(self, "ALC_LOOT_CHANGED", refresh)
	register(self, "ALC_AWARDS_ANNOUNCED", refresh)
	register(self, "ALC_RECENT_CHANGED", refresh)
	register(self, "ALC_SETTINGS_CHANGED", function(_, key)
		if key == "compact" then CouncilWindow:Refresh() end
	end)
	register(self, "ALC_SESSION_STARTED", function(_, session, restored)
		focus = 1
		-- A session an addon built on ALC runs with its own window (Soft Reserve has no voting): the council window
		-- stays closed then, and can still be opened from the menu.
		if not restored and session.isCouncil and not session.mode then CouncilWindow:Show() end
	end)
	-- An awarded item is done: the table moves on to the next item that is still open.
	register(self, "ALC_SESSION_ITEM_AWARDED", function(_, item)
		if item == focus then
			local count = ALC.Sessions:GetItemCount()
			for step = 1, count - 1 do
				local candidate = (focus - 1 + step) % count + 1
				if ALC.Sessions:IsItemOpen(candidate) then
					focus = candidate
					offset = 0
					break
				end
			end
		end
		CouncilWindow:Refresh()
	end)
	-- An award was taken back: the table returns to that item.
	register(self, "ALC_SESSION_ITEM_REVOKED", function(_, item)
		focus = item
		offset = 0
		CouncilWindow:Refresh()
	end)
	register(self, "ALC_AWARDS_REVOKED", refresh)
	register(self, "ALC_SESSION_PAUSED", refresh)
	register(self, "ALC_AWARDS_CLEARED", refresh)
	register(self, "ALC_SESSION_SNAPSHOT", reopen)
	register(self, "ALC_SESSION_RESTORED", reopen)
	-- After a session the window closes, unless the player keeps it open. Then it stays on
	-- the tab it was on: between sessions the Council tab offers the next item of the loot
	-- list, so awarding many items in a row never leaves the window.
	register(self, "ALC_SESSION_ENDED", function()
		disarmStop()
		focus = 1
		if ALC.Settings:GetKeepCouncilOpen() and CouncilWindow:IsShown() then
			CouncilWindow:Refresh()
		else
			CouncilWindow:Hide()
		end
	end)
end

ALC.Commands:Register("trades", function() CouncilWindow:ToggleTrades() end, L["open the trade queue"])

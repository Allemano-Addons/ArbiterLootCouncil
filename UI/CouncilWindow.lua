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

local WIDTH, PAD = 840, 20
local HEADER_H, ITEM_H, TABLE_HEAD_H, FOOTER_H = 60, 92, 34, 52
local ROW_H, COMPACT_ROW_H = 56, 40
local POOL, DEFAULT_ROWS, MIN_ROWS = 30, 10, 3
local ICON = 52
local BUTTON_W = 92
local NAME_X, RESPONSE_X, GEAR_X, VOTES_X = 16, 200, 308, 512
local GEAR_W = 196
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- The History tab: one row per award in the award log, newest first.
local HISTORY_ROW_H, HISTORY_ROWS = 48, 12
local TIME_X, HITEM_X, WINNER_X, HRESPONSE_X, HVOTES_X = 16, 150, 470, 656, 756
local HITEM_W = 300

-- The Trade Queue tab: one row per item still to be traded.
local TRADE_ROW_H, TRADE_ROWS = 52, 10
local TITEM_X, TWINNER_X, TWHEN_X = 16, 370, 590
local TITEM_W = 330

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
local activeTab = "council"     -- "council", "history" or "trades"
local layoutCompact             -- how the candidate rows are laid out now
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

local function isCompact()
	return ALC.Settings:GetWindowOption("council", "compact", false) == true
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

	row.chip:SetSize(96, compact and 22 or 26)

	for i, button in ipairs(row.gear) do
		button:ClearAllPoints()
		if compact then
			button:SetSize(GEAR_W - 30, 22)
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

	local buttonHeight = compact and 26 or 34
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
	row.name:SetWidth(RESPONSE_X - NAME_X - 8)
	row.class = UI.NewText(row, 11, c.muted)
	row.class:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)

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
		local ok, message = ALC.Voting:Cast(row.candidate)
		if not ok and message then ALC:Print(message) end
	end)
	row.vote:SetPoint("RIGHT", row, "RIGHT", -12, 0)

	-- Only the loot master hands the item out; the amber frame marks the final step.
	row.award = UI.NewButton(row, BUTTON_W, 34, L["Award"], function()
		ALC.AwardDialog:Ask(row.candidate)
	end)
	row.award:SetPoint("RIGHT", row, "RIGHT", -12, 0)
	row.award:SetSelected(true)
	row.award.label:SetTextColor(c.gold[1], c.gold[2], c.gold[3], 1)
	row.award:Hide()

	row:SetScript("OnEnter", function(self) UI.SetTextureColor(self.bg, c.panelHover, 0.5) end)
	row:SetScript("OnLeave", function(self) UI.SetTextureColor(self.bg, c.bg, 0) end)
	layoutRow(row, index, false)
	return row
end

-- A row of the History tab: when, what, to whom, with which answer, and the votes.
local function newHistoryRow(index)
	local row = CreateFrame("Frame", nil, frame)
	row:SetHeight(HISTORY_ROW_H)
	local top = -(HEADER_H + TABLE_HEAD_H + (index - 1) * HISTORY_ROW_H)
	row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, top)
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

local function build()
	frame = CreateFrame("Frame", nil, UIParent)
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
	itemBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER_H + 20))
	itemBox:EnableMouse(true)
	frame.icon = itemBox:CreateTexture(nil, "ARTWORK")
	frame.icon:SetPoint("TOPLEFT", 2, -2)
	frame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	frame.iconBorder = UI.AddBorder(itemBox, c.border, 2, 8, "OVERLAY")
	itemBox:SetScript("OnEnter", function(self)
		local session = ALC.Sessions:GetSession()
		if session then showItemTooltip(self, session.itemString) end
	end)
	itemBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

	frame.name = UI.NewText(frame, 20, c.text)
	frame.name:SetPoint("TOPLEFT", itemBox, "TOPRIGHT", 16, -2)
	frame.name:SetWidth(430)
	frame.sub = UI.NewText(frame, 12, c.muted)
	frame.sub:SetPoint("BOTTOMLEFT", itemBox, "BOTTOMRIGHT", 16, 2)
	frame.sub:SetWidth(430)

	frame.progress = UI.NewText(frame, 13, c.muted, "RIGHT")
	frame.progress:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(HEADER_H + 24))
	frame.barBg = frame:CreateTexture(nil, "ARTWORK")
	frame.barBg:SetSize(220, 6)
	frame.barBg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(HEADER_H + 50))
	UI.SetTextureColor(frame.barBg, c.panelHover)
	frame.barFill = frame:CreateTexture(nil, "OVERLAY")
	frame.barFill:SetHeight(6)
	frame.barFill:SetPoint("TOPLEFT", frame.barBg, "TOPLEFT", 0, 0)
	UI.SetTextureColor(frame.barFill, c.gold)

	local itemDivider = divider(-(HEADER_H + ITEM_H))
	local headings = {
		heading(L["Player"], NAME_X),
		heading(L["Response"], RESPONSE_X),
		heading(L["Current gear"], GEAR_X),
		heading(L["Votes"], VOTES_X, "CENTER", 60),
	}
	local tableDivider = divider(-(HEADER_H + ITEM_H + TABLE_HEAD_H))
	frame.empty = centred(HEADER_H + ITEM_H + TABLE_HEAD_H + 26, L["Waiting for responses..."])
	frame.footerLine = footerLine()
	frame.lootMaster = UI.NewText(frame, 13, c.muted)
	frame.lootMaster:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 18)
	frame.tally = UI.NewText(frame, 13, c.muted, "RIGHT")
	frame.tally:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 12, 18)

	-- The compact toggle: fewer pixels per candidate when there are many.
	frame.compact = UI.NewCheckbox(frame, L["Compact rows"], function(checked)
		ALC.Settings:SetWindowOption("council", "compact", checked)
		CouncilWindow:Refresh()
	end)
	frame.compact:SetSize(150, 24)
	frame.compact:SetPoint("BOTTOM", frame, "BOTTOM", 0, 16)

	councilStatic = { itemBox, frame.name, frame.sub, frame.progress, frame.barBg, frame.barFill, itemDivider, tableDivider,
		headings[1], headings[2], headings[3], headings[4], frame.empty, frame.footerLine, frame.lootMaster,
		frame.tally, frame.compact }

	-- Shown instead of the Council tab while no session runs.
	frame.idle = centred(HEADER_H + 46, L["No running session. Start one from the loot window."])
	frame.idle:Hide()
	frame.queueLabel = UI.NewText(frame, 11, c.muted)
	frame.queueLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER_H + 26))
	frame.queueLabel:SetText(strupper(L["Next in the loot list"]))
	frame.queueMore = UI.NewText(frame, 12, c.muted)
	frame.queueMore:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER_H + 54 + QUEUE_ROWS * QUEUE_ROW_H))
	queueStatic = { frame.queueLabel, frame.queueMore }
	for i = 1, QUEUE_ROWS do
		CouncilWindow.queueRows[i] = newQueueRow(i)
		CouncilWindow.queueRows[i]:Hide()
	end
	setShown(queueStatic, false)

	for i = 1, POOL do
		CouncilWindow.rows[i] = newRow(i)
	end
	frame.scroll = UI.NewScrollBar(frame, function(newOffset)
		offset = newOffset
		CouncilWindow:Refresh()
	end)
	frame.scroll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -(HEADER_H + ITEM_H + TABLE_HEAD_H))
	frame.scroll:SetHeight(DEFAULT_ROWS * ROW_H)
	frame.scroll:Hide()

	-- History tab ------------------------------------------------------------
	local historyHeadings = {
		heading(L["Time"], TIME_X, nil, nil, HEADER_H + 12),
		heading(L["Item"], HITEM_X, nil, nil, HEADER_H + 12),
		heading(L["Winner"], WINNER_X, nil, nil, HEADER_H + 12),
		heading(L["Response"], HRESPONSE_X, nil, nil, HEADER_H + 12),
		heading(L["Votes"], HVOTES_X - 8, "CENTER", 48, HEADER_H + 12),
	}
	local historyDivider = divider(-(HEADER_H + TABLE_HEAD_H))
	frame.historyEmpty = centred(HEADER_H + TABLE_HEAD_H + 30, L["No awards recorded on this character yet."])
	frame.historyFooterLine = footerLine()
	frame.historyCount = UI.NewText(frame, 13, c.muted)
	frame.historyCount:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 18)
	historyStatic = { historyHeadings[1], historyHeadings[2], historyHeadings[3], historyHeadings[4], historyHeadings[5],
		historyDivider, frame.historyEmpty, frame.historyFooterLine, frame.historyCount }
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

	restorePosition()
end

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------
local ORDER = {}
for i, response in ipairs(ALC.Responses.LIST) do ORDER[response.id] = i end

-- The candidates the table lists (not the ones who passed): answer first, then votes,
-- then name.
function CouncilWindow:GetVisible()
	local list = {}
	for _, entry in ipairs(ALC.Candidates:GetList()) do
		if entry.response ~= "PASS" then
			entry.votes = ALC.Voting:GetVotes(entry.name)
			list[#list + 1] = entry
		end
	end
	table.sort(list, function(a, b)
		if ORDER[a.response] ~= ORDER[b.response] then return ORDER[a.response] < ORDER[b.response] end
		if a.votes ~= b.votes then return a.votes > b.votes end
		return a.name < b.name
	end)
	return list
end

-- The awards in the log, newest first (a new list; the entries are shared).
function CouncilWindow:GetHistory()
	local log = ALC.Awards:GetLog()
	local list = {}
	for i = #log, 1, -1 do list[#list + 1] = log[i] end
	return list
end

local function localizedClass(class)
	return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class or ""
end

--------------------------------------------------------------------------------
-- Rendering: the Council tab
--------------------------------------------------------------------------------
local function renderRow(row, entry, myVote, topVotes, isLM, compact)
	row.candidate = entry.name
	local classColor = UI.ClassColor(entry.class)
	row.name:SetTextColor(classColor[1], classColor[2], classColor[3], 1)
	row.name:SetText(entry.name)
	row.class:SetText(localizedClass(entry.class))

	local response = ALC.Responses:Get(entry.response)
	local rc = response and response.color or c.muted
	UI.SetTextureColor(row.chip.bg, rc, 0.22)
	row.chip.label:SetTextColor(rc[1], rc[2], rc[3], 1)
	row.chip.label:SetText(response and response.label or entry.response)

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
	if #entry.gear == 0 then
		row.gear[1].text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
		row.gear[1].text:SetText(L["Nothing equipped"])
		row.gear[1]:Show()
	end
	local extra = compact and (#entry.gear - 1) or 0
	row.more:SetText(extra > 0 and ("+" .. extra) or "")

	local count, voters = ALC.Voting:GetVotes(entry.name)
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

	-- The loot master also gets Award; Vote then moves left to make room.
	row.vote:ClearAllPoints()
	if isLM then
		row.vote:SetPoint("RIGHT", row.award, "LEFT", -8, 0)
		row.award:Show()
	else
		row.vote:SetPoint("RIGHT", row, "RIGHT", -12, 0)
		row.award:Hide()
	end
	row:Show()
end

local function hideCouncilRows(self)
	for _, row in ipairs(self.rows) do row:Hide() end
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
	for _, row in ipairs(self.queueRows) do row:Hide() end
end

local function renderCouncil(self, session)
	setShown(councilStatic, true)
	frame.idle:Hide()
	hideQueue(self)

	local compact = isCompact()
	if layoutCompact ~= compact then
		for index, row in ipairs(self.rows) do layoutRow(row, index, compact) end
		layoutCompact = compact
	end
	local rowH = compact and COMPACT_ROW_H or ROW_H
	local rowsAllowed = maxRows()

	local display = ALC.LootDetection:GetItemDisplay({ itemString = session.itemString, itemID = session.itemID })
	frame.icon:SetTexture(display.icon or UNKNOWN_ICON)
	local qc = UI.QualityColor(display.quality)
	frame.iconBorder:SetColor(qc)
	frame.name:SetTextColor(qc[1], qc[2], qc[3], 1)
	frame.name:SetText(display.name or L["Loading..."])
	frame.sub:SetText(display.subtitle)

	local counts = ALC.Candidates:GetCounts()
	local total = counts.responded + counts.silent
	frame.progress:SetText(string.format("%d/%d %s", counts.responded, total, L["responded"]))
	frame.barFill:SetWidth(max(1, 220 * (total > 0 and counts.responded / total or 0)))
	frame.compact:SetChecked(compact)

	local list = self:GetVisible()
	local count = #list
	offset = max(0, min(offset, max(0, count - rowsAllowed)))
	local topVotes = 0
	for _, entry in ipairs(list) do
		if entry.votes > topVotes then topVotes = entry.votes end
	end

	local myVote = ALC.Voting:GetMyVote()
	local shown = min(count - offset, rowsAllowed)
	for i = 1, POOL do
		local row = self.rows[i]
		local entry = list[offset + i]
		if entry and i <= shown then
			renderRow(row, entry, myVote, topVotes, session.isLM, compact)
		else
			row.candidate = nil
			row:Hide()
		end
	end
	frame.empty:SetShown(count == 0)
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
	row.time:SetText(date("%d %b  %H:%M", entry.time or 0))
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

	local response = ALC.Responses:Get(entry.response)
	local rc = response and response.color or c.muted
	UI.SetTextureColor(row.chip.bg, rc, 0.22)
	row.chip.label:SetTextColor(rc[1], rc[2], rc[3], 1)
	row.chip.label:SetText(response and response.label or tostring(entry.response))

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
	frame.historyCount:SetText(string.format("%d %s", count, count == 1 and L["award"] or L["awards"]))
	frame.historyScroll:Update(count, HISTORY_ROWS, historyOffset)
	frame:SetHeight(HEADER_H + TABLE_HEAD_H + max(shown, 3) * HISTORY_ROW_H + FOOTER_H)
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
	row.note:SetText(unit and "" or L["Not in the group right now"])
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
	frame.tradeEmpty:SetShown(count == 0)
	frame.tradeCount:SetText(string.format("%d %s", count, L["waiting"]))
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
	register(self, "ALC_CANDIDATES_CHANGED", refresh)
	register(self, "ALC_VOTING_CHANGED", refresh)
	register(self, "ALC_LOOT_CHANGED", refresh)
	register(self, "ALC_AWARDS_ANNOUNCED", refresh)
	register(self, "ALC_SESSION_STARTED", function(_, session, restored)
		if not restored and session.isCouncil then CouncilWindow:Show() end
	end)
	register(self, "ALC_SESSION_SNAPSHOT", reopen)
	register(self, "ALC_SESSION_RESTORED", reopen)
	-- After a session the window closes, unless the player keeps it open. Then it stays on
	-- the tab it was on: between sessions the Council tab offers the next item of the loot
	-- list, so awarding many items in a row never leaves the window.
	register(self, "ALC_SESSION_ENDED", function()
		if ALC.Settings:GetKeepCouncilOpen() and CouncilWindow:IsShown() then
			CouncilWindow:Refresh()
		else
			CouncilWindow:Hide()
		end
	end)
end

ALC.Commands:Register("history", function() CouncilWindow:ToggleHistory() end, L["open the award history"])
ALC.Commands:Register("trades", function() CouncilWindow:ToggleTrades() end, L["open the trade queue"])

-- CouncilWindow: the voting window. Who wants the item, with what, and how many council
-- members have voted for them. Only the council gets it. Presentation only: data comes
-- from Candidates, Voting and Sessions, and votes go through Voting.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local strupper = string.upper
local min, max = math.min, math.max

local WIDTH, PAD = 840, 20
local HEADER_H, ITEM_H, TABLE_HEAD_H, FOOTER_H = 60, 92, 34, 52
local ROW_H, MAX_ROWS = 56, 10
local ICON = 52
local BUTTON_W = 92
local NAME_X, RESPONSE_X, GEAR_X, VOTES_X = 16, 200, 308, 512
local GEAR_W = 196
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- The History tab: one row per award in the award log, newest first.
local HISTORY_ROW_H, HISTORY_ROWS = 48, 12
local TIME_X, HITEM_X, WINNER_X, HRESPONSE_X, HVOTES_X = 16, 150, 470, 656, 756
local HITEM_W = 300

local CouncilWindow = {}
ALC.CouncilWindow = CouncilWindow
CouncilWindow.rows = {}         -- the candidate rows of the Council tab
CouncilWindow.historyRows = {}  -- the award rows of the History tab
CouncilWindow.tabs = {}

local frame, offset, historyOffset = nil, 0, 0
local activeTab = "council"     -- "council" or "history"
local councilStatic, historyStatic = {}, {} -- widgets that belong to one tab only
local c = UI.color

local function setShown(widgets, shown)
	for _, widget in ipairs(widgets) do widget:SetShown(shown) end
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------
local function showItemTooltip(owner, itemString)
	if not itemString then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(itemString)
	GameTooltip:Show()
end

local function newRow(index)
	local row = CreateFrame("Button", nil, frame)
	row:SetHeight(ROW_H)
	local top = -(HEADER_H + ITEM_H + TABLE_HEAD_H + (index - 1) * ROW_H)
	row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, top)
	row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, top)

	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	UI.SetTextureColor(row.bg, c.bg, 0)
	row.line = row:CreateTexture(nil, "BORDER")
	row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
	row.line:SetHeight(1)
	UI.SetTextureColor(row.line, c.border, 0.6)

	row.name = UI.NewText(row, 15, c.text)
	row.name:SetPoint("TOPLEFT", row, "TOPLEFT", NAME_X, -10)
	row.name:SetWidth(RESPONSE_X - NAME_X - 8)
	row.class = UI.NewText(row, 11, c.muted)
	row.class:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)

	row.chip = CreateFrame("Frame", nil, row)
	row.chip:SetSize(96, 26)
	row.chip:SetPoint("LEFT", row, "LEFT", RESPONSE_X, 0)
	row.chip.bg = row.chip:CreateTexture(nil, "BACKGROUND")
	row.chip.bg:SetAllPoints()
	row.chip.label = UI.NewText(row.chip, 13, c.text, "CENTER")
	row.chip.label:SetPoint("CENTER", 0, 0)

	row.gear = {}
	for i = 1, 2 do
		local button = CreateFrame("Button", nil, row)
		button:SetSize(GEAR_W, 22)
		button:SetPoint("TOPLEFT", row, "TOPLEFT", GEAR_X, -6 - (i - 1) * 22)
		button.text = UI.NewText(button, 12, c.text)
		button.text:SetPoint("LEFT", button, "LEFT", 0, 0)
		button.text:SetWidth(GEAR_W)
		button:SetScript("OnEnter", function(self) showItemTooltip(self, self.itemString) end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row.gear[i] = button
	end

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
	row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
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
	row.item.border = UI.AddBorder(row.item.iconBorder, c.border, 1)
	row.item.icon = row.item.iconBorder:CreateTexture(nil, "ARTWORK")
	row.item.icon:SetPoint("TOPLEFT", 1, -1)
	row.item.icon:SetPoint("BOTTOMRIGHT", -1, 1)
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

	row.chip = CreateFrame("Frame", nil, row)
	row.chip:SetSize(90, 24)
	row.chip:SetPoint("LEFT", row, "LEFT", HRESPONSE_X, 0)
	row.chip.bg = row.chip:CreateTexture(nil, "BACKGROUND")
	row.chip.bg:SetAllPoints()
	row.chip.label = UI.NewText(row.chip, 12, c.text, "CENTER")
	row.chip.label:SetPoint("CENTER", 0, 0)

	row.votes = UI.NewText(row, 15, c.text, "CENTER")
	row.votes:SetPoint("LEFT", row, "LEFT", HVOTES_X - 8, 0)
	row.votes:SetWidth(48)
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

local function build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(WIDTH, 400)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	frame:Hide()

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	UI.SetTextureColor(bg, c.bg)
	UI.AddBorder(frame, c.border)

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

	-- Tabs, after the title: the active one has an amber line under it.
	for i, tab in ipairs({ { "council", L["Council"] }, { "history", L["History"] } }) do
		local button = CreateFrame("Button", nil, header)
		button:SetSize(100, HEADER_H)
		button:SetPoint("LEFT", header, "LEFT", 320 + (i - 1) * 104, 0)
		button.label = UI.NewText(button, 14, c.muted, "CENTER")
		button.label:SetPoint("CENTER", 0, 1)
		button.label:SetText(tab[2])
		button.underline = button:CreateTexture(nil, "OVERLAY")
		button.underline:SetHeight(2)
		button.underline:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 8, 0)
		button.underline:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -8, 0)
		UI.SetTextureColor(button.underline, c.gold)
		button.underline:Hide()
		button.tab = tab[1]
		button:SetScript("OnClick", function(self) CouncilWindow:SetTab(self.tab) end)
		button:SetScript("OnEnter", function(self)
			if activeTab ~= self.tab then self.label:SetTextColor(c.text[1], c.text[2], c.text[3], 1) end
		end)
		button:SetScript("OnLeave", function() CouncilWindow:Refresh() end)
		CouncilWindow.tabs[tab[1]] = button
	end

	local function divider(y)
		local line = frame:CreateTexture(nil, "BORDER")
		line:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, y)
		line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, y)
		line:SetHeight(1)
		UI.SetTextureColor(line, c.border)
		return line
	end
	divider(-HEADER_H)

	-- The item.
	local itemBox = CreateFrame("Frame", nil, frame)
	itemBox:SetSize(ICON, ICON)
	itemBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER_H + 20))
	itemBox:EnableMouse(true)
	frame.iconBorder = UI.AddBorder(itemBox, c.border, 2)
	frame.icon = itemBox:CreateTexture(nil, "ARTWORK")
	frame.icon:SetPoint("TOPLEFT", 2, -2)
	frame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
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

	-- Progress: how many in the group have answered.
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

	-- Column headings.
	local itemDivider = divider(-(HEADER_H + ITEM_H))
	local function heading(text, x, justify, width, y)
		local fs = UI.NewText(frame, 11, c.muted, justify)
		fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + x, -(y or (HEADER_H + ITEM_H + 12)))
		if width then fs:SetWidth(width) end
		fs:SetText(strupper(text))
		return fs
	end
	local headings = {
		heading(L["Player"], NAME_X),
		heading(L["Response"], RESPONSE_X),
		heading(L["Current gear"], GEAR_X),
		heading(L["Votes"], VOTES_X, "CENTER", 60),
	}
	local tableDivider = divider(-(HEADER_H + ITEM_H + TABLE_HEAD_H))
	councilStatic = { itemBox, frame.name, frame.sub, frame.progress, frame.barBg, frame.barFill,
		itemDivider, tableDivider, headings[1], headings[2], headings[3], headings[4] }

	frame.empty = UI.NewText(frame, 13, c.muted, "CENTER")
	frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER_H + ITEM_H + TABLE_HEAD_H + 26))
	frame.empty:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(HEADER_H + ITEM_H + TABLE_HEAD_H + 26))
	frame.empty:SetText(L["Waiting for responses..."])

	-- Footer.
	frame.footerLine = frame:CreateTexture(nil, "BORDER")
	frame.footerLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, FOOTER_H)
	frame.footerLine:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, FOOTER_H)
	frame.footerLine:SetHeight(1)
	UI.SetTextureColor(frame.footerLine, c.border)
	frame.lootMaster = UI.NewText(frame, 13, c.muted)
	frame.lootMaster:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 18)
	frame.tally = UI.NewText(frame, 13, c.muted, "RIGHT")
	frame.tally:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 18)
	councilStatic[#councilStatic + 1] = frame.empty
	councilStatic[#councilStatic + 1] = frame.footerLine
	councilStatic[#councilStatic + 1] = frame.lootMaster
	councilStatic[#councilStatic + 1] = frame.tally

	-- Shown instead of the Council tab while no session is running.
	frame.idle = UI.NewText(frame, 13, c.muted, "CENTER")
	frame.idle:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER_H + 46))
	frame.idle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(HEADER_H + 46))
	frame.idle:SetText(L["No running session. Start one from the loot window."])
	frame.idle:Hide()

	for i = 1, MAX_ROWS do
		CouncilWindow.rows[i] = newRow(i)
	end
	frame.scroll = UI.NewScrollBar(frame, function(newOffset)
		offset = newOffset
		CouncilWindow:Refresh()
	end)
	frame.scroll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -(HEADER_H + ITEM_H + TABLE_HEAD_H))
	frame.scroll:SetHeight(MAX_ROWS * ROW_H)
	frame.scroll:Hide()

	-- The History tab.
	local historyHeadings = {
		heading(L["Time"], TIME_X, nil, nil, HEADER_H + 12),
		heading(L["Item"], HITEM_X, nil, nil, HEADER_H + 12),
		heading(L["Winner"], WINNER_X, nil, nil, HEADER_H + 12),
		heading(L["Response"], HRESPONSE_X, nil, nil, HEADER_H + 12),
		heading(L["Votes"], HVOTES_X - 8, "CENTER", 48, HEADER_H + 12),
	}
	local historyDivider = divider(-(HEADER_H + TABLE_HEAD_H))
	frame.historyEmpty = UI.NewText(frame, 13, c.muted, "CENTER")
	frame.historyEmpty:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER_H + TABLE_HEAD_H + 30))
	frame.historyEmpty:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(HEADER_H + TABLE_HEAD_H + 30))
	frame.historyEmpty:SetText(L["No awards recorded on this character yet."])
	frame.historyFooterLine = frame:CreateTexture(nil, "BORDER")
	frame.historyFooterLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, FOOTER_H)
	frame.historyFooterLine:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, FOOTER_H)
	frame.historyFooterLine:SetHeight(1)
	UI.SetTextureColor(frame.historyFooterLine, c.border)
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

	frame:SetScript("OnMouseWheel", function(_, delta)
		if activeTab == "history" then
			historyOffset = max(0, min(historyOffset - delta, max(0, #CouncilWindow:GetHistory() - HISTORY_ROWS)))
		else
			offset = max(0, min(offset - delta, max(0, #CouncilWindow:GetVisible() - MAX_ROWS)))
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

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------
local function renderRow(row, entry, myVote, topVotes, isLM)
	row.candidate = entry.name
	local classColor = UI.ClassColor(entry.class)
	row.name:SetTextColor(classColor[1], classColor[2], classColor[3], 1)
	row.name:SetText(entry.name)
	row.class:SetText((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[entry.class]) or entry.class)

	local response = ALC.Responses:Get(entry.response)
	local rc = response and response.color or c.muted
	UI.SetTextureColor(row.chip.bg, rc, 0.22)
	row.chip.label:SetTextColor(rc[1], rc[2], rc[3], 1)
	row.chip.label:SetText(response and response.label or entry.response)

	for i, button in ipairs(row.gear) do
		local itemString = entry.gear[i]
		button.itemString = itemString
		if itemString then
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

local function renderCouncil(self, session)
	setShown(councilStatic, true)
	frame.idle:Hide()

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

	local list = self:GetVisible()
	local count = #list
	offset = max(0, min(offset, max(0, count - MAX_ROWS)))
	local topVotes = 0
	for _, entry in ipairs(list) do
		if entry.votes > topVotes then topVotes = entry.votes end
	end

	local myVote = ALC.Voting:GetMyVote()
	local shown = min(count - offset, MAX_ROWS)
	for i = 1, MAX_ROWS do
		local row = self.rows[i]
		local entry = list[offset + i]
		if entry and i <= shown then
			renderRow(row, entry, myVote, topVotes, session.isLM)
		else
			row.candidate = nil
			row:Hide()
		end
	end
	frame.empty:SetShown(count == 0)
	frame.scroll:Update(count, MAX_ROWS, offset)

	frame.lootMaster:SetText(L["Loot master"] .. ": " .. session.lm)
	frame.tally:SetText(string.format("%d %s \194\183 %d %s", counts.passed, L["passed"], counts.silent, L["not responded"]))

	local rows = max(shown, 2)
	frame:SetHeight(HEADER_H + ITEM_H + TABLE_HEAD_H + rows * ROW_H + FOOTER_H)
end

-- The Council tab without a session: only a hint (the window can stay open after an award).
local function renderIdle(self)
	setShown(councilStatic, false)
	for _, row in ipairs(self.rows) do row:Hide() end
	frame.scroll:Hide()
	frame.idle:Show()
	frame:SetHeight(HEADER_H + 130)
end

local function hideHistory(self)
	setShown(historyStatic, false)
	for _, row in ipairs(self.historyRows) do row:Hide() end
	frame.historyScroll:Hide()
end

-- The awards in the log, newest first (a copy of the list, the entries are shared).
function CouncilWindow:GetHistory()
	local log = ALC.Awards:GetLog()
	local list = {}
	for i = #log, 1, -1 do list[#list + 1] = log[i] end
	return list
end

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
	row.class:SetText((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[entry.class]) or entry.class or "")

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
	frame.idle:Hide()
	frame.scroll:Hide()
	for _, row in ipairs(self.rows) do row:Hide() end
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

function CouncilWindow:Refresh()
	if not frame or not frame:IsShown() then return end

	for tab, button in pairs(self.tabs) do
		local active = tab == activeTab
		button.underline:SetShown(active)
		local color = active and c.text or c.muted
		button.label:SetTextColor(color[1], color[2], color[3], 1)
	end

	if activeTab == "history" then
		renderHistory(self)
		return
	end
	hideHistory(self)
	local session = ALC.Sessions:GetSession()
	if not session then
		renderIdle(self)
		return
	end
	renderCouncil(self, session)
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

-- Switches tab. The Council tab is for the council; the History tab is for anybody.
function CouncilWindow:SetTab(tab)
	if tab ~= "council" and tab ~= "history" then return end
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
	ensureBuilt()
	activeTab = "council"
	frame:Show()
	ALC.Settings:SetWindowShown("council", true)
	self:Refresh()
end

-- The History tab needs no session.
function CouncilWindow:ShowHistory()
	ensureBuilt()
	activeTab = "history"
	frame:Show()
	ALC.Settings:SetWindowShown("council", true)
	self:Refresh()
end

function CouncilWindow:Hide()
	if frame then frame:Hide() end
	ALC.Settings:SetWindowShown("council", false)
end

function CouncilWindow:Toggle()
	if frame and frame:IsShown() then self:Hide() else self:Show() end
end

function CouncilWindow:ToggleHistory()
	if frame and frame:IsShown() and activeTab == "history" then self:Hide() else self:ShowHistory() end
end

function CouncilWindow:IsShown()
	return frame ~= nil and frame:IsShown()
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
	register(self, "ALC_SESSION_STARTED", function(_, session, restored)
		if not restored and session.isCouncil then CouncilWindow:Show() end
	end)
	register(self, "ALC_SESSION_SNAPSHOT", reopen)
	register(self, "ALC_SESSION_RESTORED", reopen)
	register(self, "ALC_AWARDS_ANNOUNCED", refresh)
	-- After a session the window closes, unless the player wants to keep it: then it stays
	-- and, after an award, shows the history with the new award at the top.
	register(self, "ALC_SESSION_ENDED", function(_, _, reason)
		if ALC.Settings:GetKeepCouncilOpen() and CouncilWindow:IsShown() then
			if reason == "awarded" then
				historyOffset = 0
				CouncilWindow:SetTab("history")
			else
				CouncilWindow:Refresh()
			end
		else
			CouncilWindow:Hide()
		end
	end)
end

ALC.Commands:Register("history", function() CouncilWindow:ToggleHistory() end, L["open the award history"])

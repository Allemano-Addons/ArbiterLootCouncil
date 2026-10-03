-- ResultWindow: the outcome of the items that were decided by rolls (see Results), for everybody. The items on
-- the left, every player's answer, roll and outcome for the selected item on the right. Read only: it shows what
-- the loot master's addon sent, so the ones who did not get an item can see that the rolls were fair.
-- Opens by itself for the players when the first result of a session arrives; /alc results opens it by hand.
-- Presentation only: the data is ALC.Results.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local strupper = string.upper
local min, max = math.min, math.max

local WIDTH, HEIGHT, PAD = 780, 560, 16
local HEADER_H, FOOTER_H = 52, 56
local ITEM_H, ITEM_GAP, ITEM_ROWS, LIST_W = 52, 4, 8, 250
local ROW_H, ROWS = 26, 15
local COL = { name = 12, answer = 190, roll = 250, result = 360 }

local ResultWindow = {}
ALC.ResultWindow = ResultWindow
ResultWindow.itemRows, ResultWindow.rows = {}, {}

local frame
local selected = nil          -- item number shown on the right
local itemOffset, rowOffset = 0, 0
local c = UI.color

local GREEN = { 0.30, 0.75, 0.40, 1 }

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------
local function savePosition()
	local point, _, relPoint, x, y = frame:GetPoint()
	ALC.Settings:SetWindowPosition("results", point, relPoint, x, y)
end

local function restorePosition()
	frame:ClearAllPoints()
	local pos = ALC.Settings:GetWindowPosition("results")
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
end

local function newItemRow(parent, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ITEM_H)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * (ITEM_H + ITEM_GAP))
	row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -(index - 1) * (ITEM_H + ITEM_GAP))
	row:RegisterForClicks("LeftButtonUp")
	row.bg = UI.NewFill(row, 6)
	row.border = UI.AddBorder(row, c.border, 1, 6)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(34, 34)
	row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
	row.name = UI.NewText(row, 13, c.text)
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
	row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.status = UI.NewText(row, 11, c.muted)
	row.status:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1)
	row.status:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row:SetScript("OnClick", function(self)
		selected = self.item
		rowOffset = 0
		ResultWindow:Refresh()
	end)
	row:SetScript("OnEnter", function(self)
		if self.item ~= selected then
			UI.SetTextureColor(self.bg, c.panelHover)
			self.border:SetColor(c.gold)
		end
	end)
	row:SetScript("OnLeave", function(self) self:Paint() end)
	function row:Paint()
		if self.item == selected then
			UI.SetTextureColor(self.bg, c.goldTint)
			self.border:SetColor(c.gold)
		else
			UI.SetTextureColor(self.bg, c.panel)
			self.border:SetColor(c.border)
		end
	end
	return row
end

local function newPlayerRow(parent, index)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * ROW_H)
	row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -(index - 1) * ROW_H)
	row.line = row:CreateTexture(nil, "BORDER")
	row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 0)
	row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 0)
	row.line:SetHeight(1)
	UI.SetTextureColor(row.line, c.border, 0.5)
	row.tag = UI.NewText(row, 10, c.gold)
	row.tag:SetPoint("LEFT", row, "LEFT", COL.name, 0)
	row.name = UI.NewText(row, 13, c.text)
	row.name:SetPoint("LEFT", row, "LEFT", COL.name + 24, 0)
	row.name:SetWidth(COL.answer - COL.name - 30)
	row.answer = UI.NewText(row, 12, c.muted)
	row.answer:SetPoint("LEFT", row, "LEFT", COL.answer, 0)
	row.roll = UI.NewText(row, 13, c.text)
	row.roll:SetPoint("LEFT", row, "LEFT", COL.roll, 0)
	row.result = UI.NewText(row, 13, c.muted)
	row.result:SetPoint("LEFT", row, "LEFT", COL.result, 0)
	return row
end

local function build()
	frame = CreateFrame("Frame", nil, UIParent)
	UI.RegisterScaled(frame)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("HIGH")
	frame:SetFrameLevel(50)
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	frame:Hide()

	local bg = UI.NewFill(frame, 10)
	UI.SetTextureColor(bg, c.bg)
	UI.AddBorder(frame, c.border, 1, 10)

	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	header:SetHeight(HEADER_H)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() frame:StartMoving() end)
	header:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		savePosition()
	end)
	local logo = UI.NewLogo(header, 28)
	logo:SetPoint("LEFT", header, "LEFT", PAD, 0)
	local title = UI.NewText(header, 15, c.text)
	title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
	title:SetText(strupper(L["Results"]))
	frame.state = UI.NewText(header, 12, c.gold, "RIGHT")

	local close = CreateFrame("Button", nil, header)
	close:SetSize(28, 28)
	close:SetPoint("RIGHT", header, "RIGHT", -12, 0)
	close.text = UI.NewText(close, 22, c.muted, "CENTER")
	close.text:SetPoint("CENTER", 0, 0)
	close.text:SetText("\195\151")
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(c.text[1], c.text[2], c.text[3], 1) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1) end)
	close:SetScript("OnClick", function() ResultWindow:Hide() end)
	frame.state:SetPoint("RIGHT", close, "LEFT", -14, 0)

	local divider = frame:CreateTexture(nil, "BORDER")
	divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -HEADER_H)
	divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -HEADER_H)
	divider:SetHeight(1)
	UI.SetTextureColor(divider, c.border)

	-- the items that have a result
	local top = HEADER_H + 16
	frame.list = CreateFrame("Frame", nil, frame)
	frame.list:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -top)
	frame.list:SetSize(LIST_W, ITEM_ROWS * (ITEM_H + ITEM_GAP))
	for i = 1, ITEM_ROWS do ResultWindow.itemRows[i] = newItemRow(frame.list, i) end
	frame.itemScroll = UI.NewScrollBar(frame.list, function(newOffset)
		itemOffset = newOffset
		ResultWindow:Refresh()
	end)
	frame.itemScroll:SetPoint("TOPRIGHT", frame.list, "TOPRIGHT", 0, 0)
	frame.itemScroll:SetPoint("BOTTOMRIGHT", frame.list, "BOTTOMRIGHT", 0, 0)

	-- the rows of the selected item
	frame.right = CreateFrame("Frame", nil, frame)
	frame.right:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + LIST_W + 20, -top)
	frame.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, FOOTER_H + 8)
	frame.itemName = UI.NewText(frame.right, 16, c.text)
	frame.itemName:SetPoint("TOPLEFT", frame.right, "TOPLEFT", 0, 0)
	frame.itemName:SetPoint("RIGHT", frame.right, "RIGHT", 0, 0)
	frame.itemSub = UI.NewText(frame.right, 12, c.muted)
	frame.itemSub:SetPoint("TOPLEFT", frame.right, "TOPLEFT", 0, -24)
	frame.itemSub:SetPoint("RIGHT", frame.right, "RIGHT", 0, 0)
	local function heading(text, x)
		local fs = UI.NewText(frame.right, 11, c.muted)
		fs:SetPoint("TOPLEFT", frame.right, "TOPLEFT", x, -52)
		fs:SetText(strupper(text))
	end
	heading(L["Player"], COL.name)
	heading(L["Answer"], COL.answer)
	heading(L["Roll"], COL.roll)
	heading(L["Result"], COL.result)
	frame.rowsFrame = CreateFrame("Frame", nil, frame.right)
	frame.rowsFrame:SetPoint("TOPLEFT", frame.right, "TOPLEFT", 0, -72)
	frame.rowsFrame:SetPoint("RIGHT", frame.right, "RIGHT", 0, 0)
	frame.rowsFrame:SetHeight(ROWS * ROW_H)
	for i = 1, ROWS do ResultWindow.rows[i] = newPlayerRow(frame.rowsFrame, i) end
	frame.rowScroll = UI.NewScrollBar(frame.rowsFrame, function(newOffset)
		rowOffset = newOffset
		ResultWindow:Refresh()
	end)
	frame.rowScroll:SetPoint("TOPRIGHT", frame.rowsFrame, "TOPRIGHT", 0, 0)
	frame.rowScroll:SetPoint("BOTTOMRIGHT", frame.rowsFrame, "BOTTOMRIGHT", 0, 0)

	frame.empty = UI.NewText(frame, 13, c.muted, "CENTER")
	frame.empty:SetPoint("CENTER", frame, "CENTER", 0, 0)
	frame.empty:SetText(L["No result yet."])

	local footer = frame:CreateTexture(nil, "BORDER")
	footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, FOOTER_H)
	footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, FOOTER_H)
	footer:SetHeight(1)
	UI.SetTextureColor(footer, c.border)
	local note = UI.NewText(frame, 11, c.muted)
	note:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 22)
	note:SetPoint("RIGHT", frame, "RIGHT", -PAD - 110, 0)
	note:SetText(L["The rolls are made by the loot master's addon and shown to everybody here."])
	local closeButton = UI.NewButton(frame, 90, 30, L["Close"], function() ResultWindow:Hide() end)
	closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 13)

	frame:SetScript("OnMouseWheel", function(_, delta)
		rowOffset = rowOffset - delta * 3
		ResultWindow:Refresh()
	end)
	frame:SetScript("OnShow", function() ResultWindow:Refresh() end)
	restorePosition()
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------
local ANSWER = { PASS = true }

local function answerLabel(id)
	for _, r in ipairs(ALC.Sessions:GetResponses() or {}) do
		if r.id == id then return r.label end
	end
	return ANSWER[id] and L["Pass"] or id
end

local function rollText(row)
	if not row.roll then return "\226\128\148" end
	local text = tostring(row.roll)
	if row.rerolls and #row.rerolls > 0 then
		local more = {}
		for _, n in ipairs(row.rerolls) do more[#more + 1] = tostring(n) end
		text = text .. " > " .. table.concat(more, ", ")
	end
	return text
end

local VIA = { SR = L["Soft reserve"], MS = L["Main spec"], OS = L["Off spec"] }

local function outcomeText(row)
	if row.silent then return L["Did not answer"] end
	if row.outcome == "won" then return L["Won"] .. (row.via and (" (" .. (VIA[row.via] or row.via) .. ")") or "") end
	if row.outcome == "tied" then return L["Tied"] end
	if row.outcome == "passed" then return L["Passed"] end
	return row.roll and L["Lost"] or ""
end

local function winnersOf(rows)
	local names = {}
	for _, r in ipairs(rows) do
		if r.outcome == "won" then names[#names + 1] = r.name end
	end
	return names
end

local function renderItemRow(row, item)
	row.item = item
	local session = ALC.Sessions:GetSession()
	local entry = session and session.items[item]
	local display = entry and ALC.LootDetection:GetItemDisplay({ itemString = entry.itemString, itemID = entry.itemID }) or {}
	row.icon:SetTexture(display.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	local qc = UI.QualityColor(display.quality)
	row.name:SetTextColor(qc[1], qc[2], qc[3], 1)
	row.name:SetText(display.name or L["Loading..."])
	local rows = ALC.Results:Get(item) or {}
	local winners = winnersOf(rows)
	local tied = false
	for _, r in ipairs(rows) do if r.outcome == "tied" then tied = true end end
	local tone = tied and c.gold or c.muted
	row.status:SetTextColor(tone[1], tone[2], tone[3], 1)
	row.status:SetText(tied and L["Tie: the loot master rerolls"] or (#winners > 0 and (L["Winner"] .. ": " .. table.concat(winners, ", ")) or L["Nobody"]))
	row:Paint()
	row:Show()
end

local function renderPlayerRow(row, info)
	row.tag:SetText(info.reserved and "SR" or "")
	local unit = ALC:FindUnitByName(info.name)
	local class = unit and select(2, UnitClass(unit))
	local nc = class and UI.ClassColor(class) or c.text
	row.name:SetTextColor(nc[1], nc[2], nc[3], 1)
	row.name:SetText(info.name)
	row.answer:SetText(info.silent and "-" or answerLabel(info.answer))
	row.roll:SetText(rollText(info))
	local rc = c.muted
	if info.outcome == "won" then rc = GREEN elseif info.outcome == "tied" then rc = c.gold elseif info.silent then rc = c.danger end
	row.result:SetTextColor(rc[1], rc[2], rc[3], 1)
	row.result:SetText(outcomeText(info))
	row:Show()
end

function ResultWindow:Refresh()
	if not frame or not frame:IsShown() then return end
	local items = ALC.Results:GetItems()
	local has = #items > 0
	frame.empty:SetShown(not has)
	frame.list:SetShown(has)
	frame.right:SetShown(has)
	if not has then
		frame.state:SetText("")
		return
	end
	-- keep the selection when it still has a result, else the first item
	local found = false
	for _, item in ipairs(items) do if item == selected then found = true end end
	if not found then selected = items[1] end

	itemOffset = max(0, min(itemOffset, max(0, #items - ITEM_ROWS)))
	for i = 1, ITEM_ROWS do
		local item = items[itemOffset + i]
		if item then renderItemRow(self.itemRows[i], item) else self.itemRows[i]:Hide() end
	end
	frame.itemScroll:Update(#items, ITEM_ROWS, itemOffset)

	local rows, state = ALC.Results:Get(selected)
	rows = rows or {}
	local session = ALC.Sessions:GetSession()
	local entry = session and session.items[selected]
	local display = entry and ALC.LootDetection:GetItemDisplay({ itemString = entry.itemString, itemID = entry.itemID }) or {}
	frame.itemName:SetText(display.name or L["Loading..."])
	local qc = UI.QualityColor(display.quality)
	frame.itemName:SetTextColor(qc[1], qc[2], qc[3], 1)
	frame.itemSub:SetText(string.format(L["%d players"], #rows))
	frame.state:SetText(state == "accepted" and strupper(L["Accepted"]) or strupper(L["Resolved"]))

	rowOffset = max(0, min(rowOffset, max(0, #rows - ROWS)))
	for i = 1, ROWS do
		local info = rows[rowOffset + i]
		if info then renderPlayerRow(self.rows[i], info) else self.rows[i]:Hide() end
	end
	frame.rowScroll:Update(#rows, ROWS, rowOffset)
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------
function ResultWindow:Show()
	if not frame then
		-- A build that fails half way must not leave a broken frame behind.
		local ok, err = pcall(build)
		if not ok then
			frame = nil
			error(err, 0)
		end
	end
	itemOffset, rowOffset = 0, 0
	frame:Show()
	self:Refresh()
end

function ResultWindow:Hide()
	if frame then frame:Hide() end
end

function ResultWindow:Toggle()
	if self:IsShown() then self:Hide() else self:Show() end
end

function ResultWindow:IsShown()
	return frame ~= nil and frame:IsShown()
end

function ResultWindow:Init()
	local register = ALC.Events.Register
	-- The first result of a session opens the window for the players (the loot master has its own tools).
	register(self, "ALC_RESULTS_CHANGED", function(_, item)
		local session = ALC.Sessions:GetSession()
		if item and session and not session.isLM and not ResultWindow:IsShown() and not ResultWindow.openedFor then
			ResultWindow.openedFor = session.sid
			ResultWindow:Show()
		end
		ResultWindow:Refresh()
	end)
	register(self, "ALC_SESSION_ENDED", function()
		ResultWindow.openedFor = nil
	end)
	register(self, "ALC_LOOT_CHANGED", function() ResultWindow:Refresh() end)
end

ALC.Commands:Register("results", function()
	if ALC.Results:HasAny() then
		ResultWindow:Toggle()
	else
		ALC:Print(L["There is no result to show."])
	end
end, L["show the results of the items decided by rolls"])

-- ResponseWindow: the window every player gets when a session starts: one row per item
-- with five buttons. Presentation only; answers go through Responses.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local strupper = string.upper
local min, max = math.min, math.max

local WIDTH, PAD = 600, 16
local HEADER_H, FOOTER_H = 52, 92
local ROW_H, ROW_GAP = 46, 4
local ICON = 34
local BUTTON_W, BUTTON_H, GAP = 58, 30, 4
local NAME_W = 170
local POOL, MAX_VISIBLE = ALC.Constants.MAX_SESSION_ITEMS, 10
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local ResponseWindow = {}
ALC.ResponseWindow = ResponseWindow
ResponseWindow.rows = {}

local frame
local offset = 0
local c = UI.color
local feedback -- an error from the last click, shown until the next refresh with a response

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------
local function savePosition()
	local point, _, relPoint, x, y = frame:GetPoint()
	ALC.Settings:SetWindowPosition("response", point, relPoint, x, y)
end

local function restorePosition()
	frame:ClearAllPoints()
	local pos = ALC.Settings:GetWindowPosition("response")
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", -170, 100)
	end
end

-- One item: its icon and name, and the five answer buttons (or who won it).
local function newRow(index)
	local row = CreateFrame("Frame", nil, frame)
	row:SetHeight(ROW_H)
	local top = -(HEADER_H + 10 + (index - 1) * (ROW_H + ROW_GAP))
	row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, top)
	row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - 14, top)
	row.bg = UI.NewFill(row, 8)
	UI.SetTextureColor(row.bg, c.panel)
	row.border = UI.AddBorder(row, c.border, 1, 8)

	row.itemBox = CreateFrame("Button", nil, row)
	row.itemBox:SetSize(ICON, ICON)
	row.itemBox:SetPoint("LEFT", row, "LEFT", 8, 0)
	row.icon = row.itemBox:CreateTexture(nil, "ARTWORK")
	row.icon:SetPoint("TOPLEFT", 2, -2)
	row.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	row.iconBorder = UI.AddBorder(row.itemBox, c.border, 2, 8, "OVERLAY")
	row.itemBox:SetScript("OnEnter", function(self)
		if not row.itemString then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(row.itemString)
		GameTooltip:Show()
	end)
	row.itemBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

	row.name = UI.NewText(row, 12, c.text)
	row.name:SetPoint("TOPLEFT", row.itemBox, "TOPRIGHT", 8, 0)
	row.name:SetWidth(NAME_W)
	row.sub = UI.NewText(row, 10, c.muted)
	row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
	row.sub:SetWidth(NAME_W)

	local left = 8 + ICON + 8 + NAME_W + 8
	row.buttons = {}
	for i, response in ipairs(ALC.Responses.LIST) do
		local button = UI.NewButton(row, BUTTON_W, BUTTON_H, response.label, function()
			ALC.Responses:SetDraftNote(frame.note:GetText()) -- what is written goes with the answer
			local ok, message = ALC.Responses:Send(response.id, row.item)
			feedback = not ok and message or nil
			ResponseWindow:Refresh()
		end)
		button:SetPoint("LEFT", row, "LEFT", left + (i - 1) * (BUTTON_W + GAP), 0)
		button.label:SetTextColor(response.color[1], response.color[2], response.color[3], 1)
		button.responseId = response.id
		row.buttons[i] = button
	end

	-- Instead of the buttons once the item is awarded.
	row.result = UI.NewText(row, 13, c.gold, "RIGHT")
	row.result:SetPoint("RIGHT", row, "RIGHT", -14, 0)
	row.result:SetWidth(5 * (BUTTON_W + GAP) - GAP)
	row.result:Hide()
	return row
end

local function build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(WIDTH, 270)
	frame:SetFrameStrata("HIGH")
	frame:SetFrameLevel(40)
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
	frame.header = header
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() frame:StartMoving() end)
	header:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		savePosition()
	end)

	local logo = UI.NewLogo(header, 28)
	logo:SetPoint("LEFT", header, "LEFT", PAD, 0)
	frame.logo = logo
	local title = UI.NewText(header, 15, c.text)
	title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
	title:SetText(strupper(L["Loot response"]))
	frame.lm = UI.NewText(header, 12, c.muted, "RIGHT")

	local close = CreateFrame("Button", nil, header)
	close:SetSize(28, 28)
	close:SetPoint("RIGHT", header, "RIGHT", -12, 0)
	close.text = UI.NewText(close, 22, c.muted, "CENTER")
	close.text:SetPoint("CENTER", 0, 0)
	close.text:SetText("\195\151")
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(c.text[1], c.text[2], c.text[3], 1) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1) end)
	close:SetScript("OnClick", function() ResponseWindow:Hide() end)
	frame.lm:SetPoint("RIGHT", close, "LEFT", -10, 0)

	local divider = frame:CreateTexture(nil, "BORDER")
	divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -HEADER_H)
	divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -HEADER_H)
	divider:SetHeight(1)
	UI.SetTextureColor(divider, c.border)

	for i = 1, POOL do
		ResponseWindow.rows[i] = newRow(i)
	end
	frame.scroll = UI.NewScrollBar(frame, function(newOffset)
		offset = newOffset
		ResponseWindow:Refresh()
	end)
	frame.scroll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -(HEADER_H + 10))
	frame.scroll:SetHeight(ROW_H)
	frame.scroll:Hide()

	frame.footerLine = frame:CreateTexture(nil, "BORDER")
	frame.footerLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, FOOTER_H)
	frame.footerLine:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, FOOTER_H)
	frame.footerLine:SetHeight(1)
	UI.SetTextureColor(frame.footerLine, c.border)

	-- A note for the council, sent with every answer (Enter sends it again with the ones already given).
	frame.note = UI.NewEditBox(frame, WIDTH - 2 * PAD, 28, L["Note for the council (optional). Press Enter to send it with your answers."], function(text)
		local resent = ALC.Responses:SetNote(text)
		feedback = nil
		if resent > 0 then ALC:Print(L["Note sent with %d answer(s)."], resent) end
		ResponseWindow:Refresh()
	end)
	frame.note:SetMaxLetters(ALC.Constants.MAX_NOTE_LENGTH)
	frame.note:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 52)
	frame.note:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 52)

	frame.status = UI.NewText(frame, 12, c.muted)
	frame.status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 14)
	frame.status:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
	frame.status:SetWordWrap(true) -- the longer messages take two lines
	frame.status:SetJustifyV("BOTTOM")

	frame:SetScript("OnMouseWheel", function(_, delta)
		local count = ALC.Sessions:GetItemCount()
		offset = max(0, min(offset - delta, max(0, count - MAX_VISIBLE)))
		ResponseWindow:Refresh()
	end)
	frame:SetScript("OnShow", function() ResponseWindow:Refresh() end)
	restorePosition()
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------
local function renderRow(row, index, item)
	row.item = index
	row.itemString = item.itemString
	local display = ALC.LootDetection:GetItemDisplay({ itemString = item.itemString, itemID = item.itemID })
	row.icon:SetTexture(display.icon or UNKNOWN_ICON)
	local qc = UI.QualityColor(display.quality)
	row.iconBorder:SetColor(qc)
	row.name:SetTextColor(qc[1], qc[2], qc[3], 1)
	row.name:SetText(display.name or L["Loading..."])
	row.sub:SetText(display.subtitle)

	local mine = ALC.Responses:GetMyResponse(index)
	local awarded = item.winner ~= nil
	for _, button in ipairs(row.buttons) do
		button:SetShown(not awarded)
		button:SetSelected(button.responseId == mine)
	end
	row.result:SetShown(awarded)
	if awarded then
		row.result:SetText(string.format(L["Awarded to %s"], item.winner))
		UI.SetTextureColor(row.bg, c.panel, 0.5)
	else
		UI.SetTextureColor(row.bg, c.panel)
	end
	row:Show()
end

function ResponseWindow:Refresh()
	if not frame or not frame:IsShown() then return end
	local session = ALC.Sessions:GetSession()
	if not session then
		self:Hide()
		return
	end

	local count = #session.items
	local visible = min(count, MAX_VISIBLE)
	offset = max(0, min(offset, max(0, count - visible)))
	-- Items that still wait for an answer first, the awarded ones after them.
	local order = {}
	for index, item in ipairs(session.items) do
		if not item.winner then order[#order + 1] = index end
	end
	for index, item in ipairs(session.items) do
		if item.winner then order[#order + 1] = index end
	end
	for i = 1, POOL do
		local index = order[offset + i]
		if index and i <= visible then renderRow(self.rows[i], index, session.items[index]) else self.rows[i]:Hide() end
	end
	frame.scroll:SetHeight(visible * (ROW_H + ROW_GAP) - ROW_GAP)
	frame.scroll:Update(count, visible, offset)
	frame.lm:SetText(L["Loot master"] .. ": " .. session.lm)
	frame:SetHeight(HEADER_H + 10 + visible * (ROW_H + ROW_GAP) - ROW_GAP + 14 + FOOTER_H)

	local open = 0
	for _, item in ipairs(session.items) do
		if not item.winner then open = open + 1 end
	end
	local answered = ALC.Responses:CountMine()
	if feedback then
		frame.status:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1)
		frame.status:SetText(feedback)
	elseif count == 1 and answered == 1 then
		frame.status:SetTextColor(c.gold[1], c.gold[2], c.gold[3], 1)
		frame.status:SetText(L["Your response: %s. You can change it until the session ends."]:format(ALC.Responses:GetLabel(ALC.Responses:GetMyResponse(1))))
	elseif count == 1 then
		frame.status:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
		frame.status:SetText(L["Pick one. The council sees it right away."])
	else
		local color = (answered >= count or open == 0) and c.gold or c.muted
		frame.status:SetTextColor(color[1], color[2], color[3], 1)
		frame.status:SetText(string.format(L["Answered %d of %d items. You can change an answer until its item is awarded."], answered, count))
	end
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------
-- Whether the window is open is remembered, so it is as you left it after a /reload.
function ResponseWindow:Show()
	if not ALC.Sessions:IsActive() then
		ALC:Print(L["There is no active session."])
		return
	end
	if not frame then
		-- A build that fails half way must not leave a broken frame behind.
		local ok, err = pcall(build)
		if not ok then
			frame = nil
			error(err, 0)
		end
	end
	feedback = nil
	offset = 0
	frame:Show()
	ALC.Settings:SetWindowShown("response", true)
	self:Refresh()
end

function ResponseWindow:Hide()
	if frame then frame:Hide() end
	ALC.Settings:SetWindowShown("response", false)
end

-- After a reload the session is back: the window returns if it was open, and also if
-- there is still something to answer.
local function reopen(answered)
	if ALC.Settings:GetWindowShown("response") or not answered then
		ResponseWindow:Show()
	else
		ResponseWindow:Refresh()
	end
end

function ResponseWindow:IsShown()
	return frame ~= nil and frame:IsShown()
end

function ResponseWindow:Init()
	local register = ALC.Events.Register
	local refresh = function() ResponseWindow:Refresh() end
	register(self, "ALC_RESPONSES_CHANGED", refresh)
	register(self, "ALC_LOOT_CHANGED", refresh)
	register(self, "ALC_SESSION_ITEM_AWARDED", refresh)
	register(self, "ALC_SESSION_STARTED", function(_, _, restored)
		if not restored then ResponseWindow:Show() end
		if frame then frame.note:SetText("") end -- a new session, a new note
	end)
	register(self, "ALC_SESSION_SNAPSHOT", function(_, p)
		reopen(p.yourResponses ~= nil)
	end)
	-- The loot master's own session came back; our answers are in the restored lists.
	register(self, "ALC_SESSION_RESTORED", function(_, session)
		-- Read from the candidates: the order in which modules hear of the event is not fixed.
		local answered = false
		for item = 1, #session.items do
			if ALC.Candidates:Get(ALC:PlayerName(), item) then answered = true end
		end
		reopen(answered)
	end)
	register(self, "ALC_SESSION_ENDED", function() ResponseWindow:Hide() end)
end

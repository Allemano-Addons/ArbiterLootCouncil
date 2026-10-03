-- ResponseWindow: the window every player gets when a session starts: one row per item
-- with five buttons. Presentation only; answers go through Responses.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local strupper = string.upper
local min, max = math.min, math.max

local WIDTH, PAD = 600, 16
local HEADER_H, FOOTER_H = 40, 52
local NOTE_W = 150 -- the note field at the right end of a row
local ROW_H, ROW_GAP = 46, 4
local ICON = 34
local BUTTON_W, BUTTON_H, GAP = 58, 30, 4
local NAME_W = 170
local POOL, MAX_VISIBLE = ALC.Constants.MAX_SESSION_ITEMS, 10
local INITIAL_ROWS = 6 -- rows made when the window is built
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

local buttonWidth = BUTTON_W -- the width of every answer button of this session
local currentSet = {}     -- the answers the buttons stand for
local setKey = ""

-- The buttons of a row follow the session's answers: as many as it has, as wide as its
-- longest label needs.
local function ensureButtons(row, count)
	while #row.buttons < count do
		local button
		button = UI.NewButton(row, BUTTON_W, BUTTON_H, "", function()
			ALC.Responses:SetDraftNote(button.row.item, button.row.note:GetText()) -- what is written goes with the answer
			local ok, message = ALC.Responses:Send(button.responseId, row.item)
			feedback = not ok and message or nil
			ResponseWindow:Refresh()
		end)
		button.row = row
		row.buttons[#row.buttons + 1] = button
	end
end

local function applySet(set)
	local key = ""
	for _, r in ipairs(set) do key = key .. r.id .. ":" .. r.label .. ":" .. r.color[1] .. ":" .. r.color[2] .. ":" .. r.color[3] .. ";" end
	if key == setKey then return end
	setKey, currentSet = key, set
	local count = #set
	local first = ResponseWindow.rows[1]
	ensureButtons(first, count)
	local widest = 0
	for i, r in ipairs(set) do
		first.buttons[i]:SetLabel(r.label)
		widest = math.max(widest, first.buttons[i].label:GetStringWidth())
	end
	buttonWidth = math.max(BUTTON_W, math.floor(widest + 22))
	local left = 8 + ICON + 8 + NAME_W + 8
	for _, row in ipairs(ResponseWindow.rows) do
		ensureButtons(row, count)
		for i, button in ipairs(row.buttons) do
			local r = set[i]
			if r then
				button:SetSize(buttonWidth, BUTTON_H)
				button:ClearAllPoints()
				button:SetPoint("LEFT", row, "LEFT", left + (i - 1) * (buttonWidth + GAP), 0)
				button:SetLabel(r.label)
				button.label:SetTextColor(r.color[1], r.color[2], r.color[3], 1)
				button.responseId = r.id
			else
				button.responseId = nil
			end
		end
		row.result:SetWidth(count * (buttonWidth + GAP) - GAP + NOTE_W + 8)
		row.note:ClearAllPoints()
		row.note:SetPoint("LEFT", row, "LEFT", left + count * (buttonWidth + GAP) + 4, 0)
	end
	frame:SetWidth(math.max(WIDTH, left + count * (buttonWidth + GAP) + NOTE_W + 4 + 12 + 2 * PAD + 14))
end

-- Compact mode (Settings, Everyone): lower rows, smaller icons and buttons.
local layoutCompact

-- Sizes and places one row for the density that is current.
local function layoutRowDensity(row, index)
	row:SetHeight(ROW_H)
	local top = -(HEADER_H + 10 + (index - 1) * (ROW_H + ROW_GAP))
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, top)
	row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - 14, top)
	row.itemBox:SetSize(ICON, ICON)
	row.name:SetWidth(NAME_W)
	row.sub:SetWidth(NAME_W)
	row.note:SetSize(NOTE_W, BUTTON_H)
end

local function applyDensity()
	local compact = ALC.Settings:GetCompact()
	if layoutCompact == compact then return end
	layoutCompact = compact
	if compact then
		ROW_H, ROW_GAP, ICON, BUTTON_H, NAME_W = 30, 2, 22, 20, 150
	else
		ROW_H, ROW_GAP, ICON, BUTTON_H, NAME_W = 46, 4, 34, 30, 170
	end
	for index, row in ipairs(ResponseWindow.rows) do layoutRowDensity(row, index) end
	setKey = "" -- the buttons are laid out again with the new sizes
end

-- One item: its icon and name, and the answer buttons (or who won it).
local newRow

-- Makes the rows up to `count` (never more than the pool), in the density that is current.
function ResponseWindow.EnsureRows(count)
	for i = #ResponseWindow.rows + 1, math.min(POOL, count) do
		local row = newRow(i)
		layoutRowDensity(row, i)
		row:Hide() -- a row shows itself when it has an item to show
		ResponseWindow.rows[i] = row
		setKey = "" -- the buttons are laid out again for the new row
	end
end

function newRow(index)
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

	row.buttons = {} -- made as the session needs them (see applySet)

	-- A note for the council about this item, sent with the answer. Enter sends it again
	-- with an answer that was already given.
	row.note = UI.NewEditBox(row, NOTE_W, BUTTON_H, L["Note"], function(text)
		local resent = ALC.Responses:SetNote(row.item, text)
		feedback = nil
		if resent then ALC:Print(L["Note sent."]) end
		ResponseWindow:Refresh()
	end)
	row.note:SetMaxLetters(ALC.Constants.MAX_NOTE_LENGTH)
	row.note:SetSize(NOTE_W, BUTTON_H)
	-- Leaving the field sends the note too, so it can be written after the answer was clicked.
	row.note:HookScript("OnEditFocusLost", function(self)
		if ALC.Responses:SetNote(row.item, self:GetText()) then ResponseWindow:Refresh() end
	end)

	-- Instead of the buttons once the item is awarded.
	row.result = UI.NewText(row, 13, c.gold, "RIGHT")
	row.result:SetPoint("RIGHT", row, "RIGHT", -14, 0)
	row.result:SetWidth(5 * (BUTTON_W + GAP) - GAP)
	row.result:Hide()
	return row
end

local function build()
	frame = CreateFrame("Frame", nil, UIParent)
	UI.RegisterScaled(frame)
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

	local logo = UI.NewLogo(header, 22)
	logo:SetPoint("LEFT", header, "LEFT", PAD, 0)
	frame.logo = logo
	local title = UI.NewText(header, 15, c.text)
	title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
	title:SetText(strupper(L["Loot response"]))
	frame.title = title
	frame.lm = UI.NewText(header, 12, c.muted, "RIGHT")
	frame.timer = UI.NewText(header, 13, c.gold, "RIGHT") -- the answer timer, when the session has one

	local close = CreateFrame("Button", nil, header)
	close:SetSize(24, 24)
	close:SetPoint("RIGHT", header, "RIGHT", -12, 0)
	close.text = UI.NewText(close, 22, c.muted, "CENTER")
	close.text:SetPoint("CENTER", 0, 0)
	close.text:SetText("\195\151")
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(c.text[1], c.text[2], c.text[3], 1) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1) end)
	close:SetScript("OnClick", function() ResponseWindow:Hide() end)
	frame.lm:SetPoint("RIGHT", close, "LEFT", -10, 0)
	frame.timer:SetPoint("RIGHT", frame.lm, "LEFT", -16, 0)

	local divider = frame:CreateTexture(nil, "BORDER")
	divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -HEADER_H)
	divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -HEADER_H)
	divider:SetHeight(1)
	UI.SetTextureColor(divider, c.border)

	-- Rows are made as they are needed and the rest of the pool a few at a time (see CouncilWindow).
	ResponseWindow.EnsureRows(INITIAL_ROWS)
	local function fillPool()
		if #ResponseWindow.rows >= POOL then return end
		ResponseWindow.EnsureRows(#ResponseWindow.rows + 4)
		C_Timer.After(0, fillPool)
	end
	C_Timer.After(0, fillPool)
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

	-- The results of the rolls (and, with Soft Reserve, of the earlier sessions): a click away for every player
	frame.resultsButton = UI.NewButton(frame, 80, 26, L["Results"], function() ALC.OpenResults() end)
	frame.resultsButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 12)

	frame.status = UI.NewText(frame, 12, c.muted)
	frame.status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 14)
	frame.status:SetPoint("RIGHT", frame.resultsButton, "LEFT", -10, 0)
	frame.status:SetWordWrap(true) -- the longer messages take two lines
	frame.status:SetJustifyV("BOTTOM")

	frame:SetScript("OnMouseWheel", function(_, delta)
		local count = ALC.Sessions:GetItemCount()
		offset = max(0, min(offset - delta, max(0, count - MAX_VISIBLE)))
		ResponseWindow:Refresh()
	end)
	frame:SetScript("OnShow", function() ResponseWindow:Refresh() end)
	local sinceTick = 0
	frame:SetScript("OnUpdate", function(_, elapsed)
		sinceTick = sinceTick + elapsed
		if sinceTick < 0.25 then return end
		sinceTick = 0
		ResponseWindow:UpdateTimer()
	end)
	restorePosition()
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------
-- A tag in front of the item's name for the players an addon built on ALC marks (Soft Reserve: "SR" for those who
-- reserved the item). The addon sends `extra.mark` (the text) and `extra.markFor` (names). A name without a
-- surname in the list matches every character with that first name.
local function markFor(item)
	local extra = item.extra
	if type(extra) ~= "table" or type(extra.mark) ~= "string" or type(extra.markFor) ~= "table" then return nil end
	local me = ALC:PlayerName()
	if not me then return nil end
	local first = string.lower(string.match(me, "^(%S+)") or me)
	for _, name in ipairs(extra.markFor) do
		if ALC:SameName(name, me) or (not string.find(name, " ", 1, true) and string.lower(name) == first) then
			return string.sub(extra.mark, 1, 6)
		end
	end
	return nil
end

-- After the loot master's addon has rolled (Soft Reserve), what the player rolled and who leads, from the results every
-- player gets. Returns the text and its colour, or nil when there is no result for the item.
local VIA_TEXT = { SR = L["Soft reserve"], MS = L["Main spec"], OS = L["Off spec"] }
local function myRoll(index)
	if not (ALC.Results and ALC.Results.Get) then return nil end
	local rows = ALC.Results:Get(index)
	if not rows or #rows == 0 then return nil end
	local me = ALC:PlayerName()
	local mine, leader
	for _, r in ipairs(rows) do
		if me and ALC:SameName(r.name, me) then mine = r end
		if not leader and r.outcome == "won" then leader = r end
	end
	local function shown(r)
		if r.rerolls and #r.rerolls > 0 then return r.rerolls[#r.rerolls] end
		return r.roll
	end
	if not mine then return L["You did not answer: no roll."], c.muted end
	if mine.silent then return L["You reserved it but did not answer: no roll."], c.danger end
	if mine.outcome == "passed" then return L["You passed."], c.muted end
	if mine.outcome == "won" then
		return string.format(L["You won! Your roll: %s (%s)"], tostring(shown(mine) or "-"), VIA_TEXT[mine.via] or L["Won"]), { 0.30, 0.75, 0.40 }
	end
	if mine.outcome == "tied" then return string.format(L["Your roll: %s. A tie: the loot master rerolls."], tostring(shown(mine) or "-")), c.gold end
	local text = string.format(L["Your roll: %s."], tostring(shown(mine) or "-"))
	if leader then text = text .. " " .. string.format(L["%s won with %s."], leader.name, tostring(shown(leader) or "-")) end
	return text, c.muted
end

local function renderRow(row, index, item)
	row.item = index
	row.itemString = item.itemString
	local display = ALC.LootDetection:GetItemDisplay({ itemString = item.itemString, itemID = item.itemID })
	row.icon:SetTexture(display.icon or UNKNOWN_ICON)
	local qc = UI.QualityColor(display.quality)
	row.iconBorder:SetColor(qc)
	row.name:SetTextColor(qc[1], qc[2], qc[3], 1)
	local mark = markFor(item)
	row.name:SetText((mark and ("|cffE6A93C" .. mark .. "|r  ") or "") .. (display.name or L["Loading..."]))
	row.sub:SetText(display.subtitle)

	local mine = ALC.Responses:GetMyResponse(index)
	local awarded = item.winner ~= nil
	-- Rolled but not awarded yet: the answers are closed, so the buttons give way to what the player rolled
	local rollText, rollColor
	if not awarded then rollText, rollColor = myRoll(index) end
	for i, button in ipairs(row.buttons) do
		button:SetShown(not awarded and not rollText and currentSet[i] ~= nil)
		button:SetSelected(button.responseId ~= nil and button.responseId == mine)
	end
	row.note:SetShown(not awarded and not rollText)
	if not row.note:HasFocus() then row.note:SetText(ALC.Responses:GetNote(index)) end -- not while it is being written
	row.result:SetShown(awarded or rollText ~= nil)
	if awarded then
		row.result:SetTextColor(c.gold[1], c.gold[2], c.gold[3], 1)
		row.result:SetText(string.format(L["Awarded to %s"], item.winner))
		UI.SetTextureColor(row.bg, c.panel, 0.5)
	elseif rollText then
		row.result:SetTextColor(rollColor[1], rollColor[2], rollColor[3], 1)
		row.result:SetText(rollText)
		UI.SetTextureColor(row.bg, c.panel)
	else
		UI.SetTextureColor(row.bg, c.panel)
	end
	row:Show()
end

-- The countdown in the header: "Time left 1:23", red for the last 15 seconds.
function ResponseWindow:UpdateTimer()
	if not frame then return end
	local left = ALC.Sessions:GetTimeLeft()
	if not left then
		frame.timer:SetText("")
		return
	end
	if ALC.Sessions:IsPaused() then
		frame.timer:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1)
		frame.timer:SetText(string.format(L["Paused \194\183 %d:%02d left"], math.floor(math.ceil(left) / 60), math.ceil(left) % 60))
		return
	end
	left = math.ceil(left)
	local color = left <= 15 and c.danger or c.gold
	frame.timer:SetTextColor(color[1], color[2], color[3], 1)
	frame.timer:SetText(string.format(L["Time left %d:%02d"], math.floor(left / 60), left % 60))
end

function ResponseWindow:Refresh()
	if not frame or not frame:IsShown() then return end
	local session = ALC.Sessions:GetSession()
	if not session then
		self:Hide()
		return
	end

	applyDensity()
	-- A session started by an addon built on ALC (Soft Reserve) shows that addon's name and colour.
	local brandName = UI.SessionBrand(session)
	UI.ApplyBrand(frame.logo, session)
	frame.title:SetText(strupper(brandName and (brandName .. " " .. L["response"]) or L["Loot response"]))
	applySet(session.responses)
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
	ResponseWindow.EnsureRows(visible)
	for i = 1, #self.rows do
		local index = order[offset + i]
		if index and i <= visible then renderRow(self.rows[i], index, session.items[index]) else self.rows[i]:Hide() end
	end
	frame.scroll:SetHeight(visible * (ROW_H + ROW_GAP) - ROW_GAP)
	frame.scroll:Update(count, visible, offset)
	frame.lm:SetText(L["Loot master"] .. ": " .. session.lm)
	self:UpdateTimer()
	frame:SetHeight(HEADER_H + 10 + visible * (ROW_H + ROW_GAP) - ROW_GAP + 14 + FOOTER_H)

	local open = 0
	for _, item in ipairs(session.items) do
		if not item.winner then open = open + 1 end
	end
	local answered = ALC.Responses:CountMine()
	if feedback then
		frame.status:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1)
		frame.status:SetText(feedback)
	elseif ALC.Sessions:IsPaused() then
		frame.status:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1)
		frame.status:SetText(L["The loot master has paused the session. You can answer when it goes on."])
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
	if ALC.Sessions:IsTimeUp() then
		ALC:Print(L["The time to answer is up."])
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
	if ALC.Sessions:IsTimeUp() then
		ResponseWindow:Hide()
	elseif ALC.Settings:GetWindowShown("response") or not answered then
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
	register(self, "ALC_SESSION_PAUSED", refresh)
	register(self, "ALC_RESULTS_CHANGED", function() ResponseWindow:Refresh() end)
	register(self, "ALC_SETTINGS_CHANGED", function(_, key)
		if key == "compact" then ResponseWindow:Refresh() end
	end)
	register(self, "ALC_SESSION_STARTED", function(_, _, restored)
		if not restored then ResponseWindow:Show() end
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
	-- The answer timer ran out: the window goes away for everybody.
	register(self, "ALC_SESSION_TIMER_ENDED", function() ResponseWindow:Hide() end)
end

-- LootWindow: the loot master's list of items (see LootDetection) with a Start button
-- per item and Cancel for the running session. Presentation only: it reads
-- LootDetection and Sessions and calls their functions.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local strupper = string.upper
local min, max = math.min, math.max

local BASE_WIDTH, PAD = 400, 16
local WIDTH = BASE_WIDTH -- wider while an addon built on ALC has added a way to start a session (Start SR)
local MODE_EXTRA = 90 -- the width one more way to start needs
local HEADER_H, LABEL_H, FOOTER_H = 40, 30, 70
local ROW_H, ROW_GAP = 56, 8
local POOL, DEFAULT_ROWS, MIN_ROWS = 24, 8, 3 -- rows built, rows shown by default, fewest rows
local RETURNED_H = 34 -- the bar that offers an item a winner traded back
local INITIAL_ROWS = 6 -- rows made when the window is built
local ICON = 40
local REMOVE_SIZE = 28
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local LootWindow = {}
ALC.LootWindow = LootWindow
LibStub("AceEvent-3.0"):Embed(LootWindow)
LootWindow.rows = {}

local frame, offset = nil, 0
local c = UI.color

-- How many rows the window shows at most; the player changes it with the grip.
local function maxRows()
	local rows = ALC.Settings:GetWindowOption("loot", "maxRows", DEFAULT_ROWS)
	return max(MIN_ROWS, min(POOL, rows))
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------
local function rowTop(index)
	return -(HEADER_H + LABEL_H + (index - 1) * (ROW_H + ROW_GAP))
end

local function showTooltip(row)
	local entry = row.entry
	if not entry then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(entry.itemString)
	GameTooltip:Show()
end

local function newRow(index)
	local row = CreateFrame("Button", nil, frame)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, rowTop(index))
	row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, rowTop(index))

	row.bg = UI.NewFill(row, 8)
	row.border = UI.AddBorder(row, c.border, 1, 8)

	local iconFrame = CreateFrame("Frame", nil, row)
	row.iconFrame = iconFrame
	iconFrame:SetSize(ICON, ICON)
	iconFrame:SetPoint("LEFT", row, "LEFT", 12, 0)
	row.iconBorder = UI.AddBorder(iconFrame, c.border, 2, 6, "OVERLAY")
	row.icon = iconFrame:CreateTexture(nil, "ARTWORK")
	row.icon:SetPoint("TOPLEFT", 2, -2)
	row.icon:SetPoint("BOTTOMRIGHT", -2, 2)

	row.status = UI.NewText(row, 13, c.muted, "RIGHT")
	row.status:SetPoint("RIGHT", row, "RIGHT", -16, 0)

	-- Right to left: the remove button, then Start (or the status text).
	row.remove = CreateFrame("Button", nil, row)
	row.remove:SetSize(REMOVE_SIZE, REMOVE_SIZE)
	row.remove:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.remove.bg = UI.NewFill(row.remove, 6)
	UI.SetTextureColor(row.remove.bg, c.panelHover)
	row.remove.bg:Hide()
	row.remove.text = UI.NewText(row.remove, 20, c.muted, "CENTER")
	row.remove.text:SetPoint("CENTER", 0, 1)
	row.remove.text:SetText("\195\151") -- multiplication sign
	row.remove:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if row.removeBlocked then
			-- an item that is still to be traded stays in the list until it has been handed over
			GameTooltip:SetText(L["Still to be traded"])
			GameTooltip:AddLine(L["It leaves the list by itself when it has been handed over."], c.muted[1], c.muted[2], c.muted[3], true)
		else
			self.bg:Show()
			self.text:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1)
			GameTooltip:SetText(L["Remove from the list"])
		end
		GameTooltip:Show()
	end)
	row.remove:SetScript("OnLeave", function(self)
		self.bg:Hide()
		self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
		GameTooltip:Hide()
	end)
	row.remove:SetScript("OnClick", function()
		if row.removeBlocked then return end
		GameTooltip:Hide()
		ALC.LootDetection:Remove(row.entryId)
	end)

	row.start = UI.NewButton(row, 76, 34, L["Start"], function()
		local ok, message = ALC.LootDetection:StartSession(row.entryId)
		if not ok and message then ALC:Print(message) end
	end)
	row.start:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)

	row.name = UI.NewText(row, 14, c.text)
	row.name:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 12, -2)
	row.name:SetPoint("RIGHT", row, "RIGHT", -(REMOVE_SIZE + 8 + 76 + 6 + 10), 0)

	-- The countdown of a Bind-on-Pickup trade window: a thin bar along the bottom edge of the row.
	row.bar = CreateFrame("Frame", nil, row)
	row.bar:SetHeight(2)
	row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 1)
	row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 1)
	row.bar.fill = row.bar:CreateTexture(nil, "ARTWORK")
	row.bar.fill:SetPoint("LEFT", row.bar, "LEFT", 0, 0)
	row.bar.fill:SetHeight(2)
	row.bar:Hide()

	row.sub = UI.NewText(row, 11, c.muted)
	row.sub:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMRIGHT", 12, 2)
	row.sub:SetPoint("RIGHT", row, "RIGHT", -(REMOVE_SIZE + 8 + 76 + 6 + 10), 0)

	row:SetScript("OnEnter", function(self) showTooltip(self) end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

-- Compact mode (Settings, Everyone): lower rows and smaller icons.
local layoutCompact

-- Makes the rows up to `count` (never more than the pool), in the density that is current.
function LootWindow.EnsureRows(count)
	for i = #LootWindow.rows + 1, min(POOL, count) do
		local row = newRow(i)
		row.iconFrame:SetSize(ICON, ICON)
		row.start:SetSize(layoutCompact and 64 or 76, layoutCompact and 24 or 34)
		row:Hide() -- a row shows itself when it has an item to show
		LootWindow.rows[i] = row
	end
end

local function applyDensity()
	local compact = ALC.Settings:GetCompact()
	if layoutCompact == compact then return end
	layoutCompact = compact
	if compact then
		ROW_H, ROW_GAP, ICON = 36, 4, 28
	else
		ROW_H, ROW_GAP, ICON = 56, 8, 40
	end
	for index, row in ipairs(LootWindow.rows) do
		row:SetHeight(ROW_H)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, rowTop(index))
		row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, rowTop(index))
		row.iconFrame:SetSize(ICON, ICON)
		row.start:SetSize(compact and 64 or 76, compact and 24 or 34)
	end
end

local function savePosition()
	local point, _, relPoint, x, y = frame:GetPoint()
	ALC.Settings:SetWindowPosition("loot", point, relPoint, x, y)
end

local function restorePosition()
	frame:ClearAllPoints()
	local pos = ALC.Settings:GetWindowPosition("loot")
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", -580, 100)
	end
end

local function build()
	frame = CreateFrame("Frame", nil, UIParent)
	UI.RegisterScaled(frame)
	frame:SetSize(WIDTH, 300)
	frame:SetFrameStrata("HIGH")
	frame:SetFrameLevel(20)
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

	local logo = UI.NewLogo(header, 22)
	logo:SetPoint("LEFT", header, "LEFT", PAD, 0)
	frame.logo = logo

	frame.title = UI.NewText(header, 15, c.text)
	frame.title:SetPoint("LEFT", logo, "RIGHT", 10, 0)

	local close = CreateFrame("Button", nil, header)
	close:SetSize(30, 30)
	close:SetPoint("RIGHT", header, "RIGHT", -12, 0)
	close.text = UI.NewText(close, 30, c.muted, "CENTER")
	close.text:SetPoint("CENTER", 0, 0)
	close.text:SetText("\195\151")
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(c.text[1], c.text[2], c.text[3], 1) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1) end)
	close:SetScript("OnClick", function() LootWindow:Hide() end)

	local divider = frame:CreateTexture(nil, "BORDER")
	divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -HEADER_H)
	divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -HEADER_H)
	divider:SetHeight(1)
	UI.SetTextureColor(divider, c.border)

	frame.label = UI.NewText(frame, 11, c.muted)
	frame.label:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER_H + 12))
	-- How many items the list holds, on the same line as the quality filter.
	frame.count = UI.NewText(frame, 11, c.text, "RIGHT")
	frame.count:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(HEADER_H + 12))

	frame.empty = UI.NewText(frame, 12, c.muted, "CENTER")
	frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER_H + LABEL_H + 14))
	frame.empty:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(HEADER_H + LABEL_H + 14))
	frame.empty:SetWordWrap(true)
	frame.empty:SetText(L["No items yet. Loot a boss as loot master, or add one with /alc add [item]."])

	-- Footer.
	frame.footerDivider = frame:CreateTexture(nil, "BORDER")
	frame.footerDivider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, FOOTER_H)
	frame.footerDivider:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, FOOTER_H)
	frame.footerDivider:SetHeight(1)
	UI.SetTextureColor(frame.footerDivider, c.border)

	frame.hint = UI.NewText(frame, 13, c.muted)
	frame.hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 22)

	frame.cancel = UI.NewButton(frame, 120, 30, L["Cancel session"], function()
		local ok, message = ALC.Sessions:Cancel("cancelled")
		if not ok and message then ALC:Print(message) end
	end)
	frame.startAll = UI.NewButton(frame, 100, 30, L["Start all"], function()
		local ok, message = ALC.LootDetection:StartAll()
		if not ok and message then ALC:Print(message) end
	end)
	frame.startAll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 17)
	frame.startAll:SetSelected(true)
	frame.startAll.label:SetTextColor(c.gold[1], c.gold[2], c.gold[3], 1)
	frame.cancel:SetPoint("RIGHT", frame.startAll, "LEFT", -8, 0)
	-- Takes the finished (awarded) items off the list; items still to trade stay.
	frame.clearDone = UI.NewButton(frame, 92, 30, L["Clear done"], function()
		ALC:Print(L["Removed %d finished item(s)."], ALC.LootDetection:ClearFinished())
	end)
	frame.clearDone:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 17)
	frame.hint:ClearAllPoints()
	frame.hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 54)

	-- A winner traded an item back: one bar above the buttons asks whether to put it in the list again.
	local bar = CreateFrame("Frame", nil, frame)
	bar:SetHeight(RETURNED_H)
	bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, FOOTER_H + 6)
	bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, FOOTER_H + 6)
	bar.bg = UI.NewFill(bar, 6)
	UI.SetTextureColor(bar.bg, c.goldTint)
	bar.border = UI.AddBorder(bar, c.gold, 1, 6)
	bar.dismiss = CreateFrame("Button", nil, bar)
	bar.dismiss:SetSize(24, 24)
	bar.dismiss:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
	bar.dismiss.text = UI.NewText(bar.dismiss, 18, c.muted, "CENTER")
	bar.dismiss.text:SetPoint("CENTER", 0, 1)
	bar.dismiss.text:SetText("\195\151")
	bar.dismiss:SetScript("OnEnter", function(self) self.text:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1) end)
	bar.dismiss:SetScript("OnLeave", function(self) self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1) end)
	bar.dismiss:SetScript("OnClick", function()
		if bar.offerId then ALC.LootDetection:DismissReturned(bar.offerId) end
	end)
	bar.add = UI.NewButton(bar, 64, 24, L["Add"], function()
		if bar.offerId then ALC.LootDetection:AcceptReturned(bar.offerId) end
	end)
	bar.add:SetPoint("RIGHT", bar.dismiss, "LEFT", -6, 0)
	bar.text = UI.NewText(bar, 12, c.text)
	bar.text:SetPoint("LEFT", bar, "LEFT", 10, 0)
	bar.text:SetPoint("RIGHT", bar.add, "LEFT", -8, 0)
	bar.text:SetWordWrap(false)
	bar:Hide()
	frame.returnedBar = bar

	-- Rows are made as they are needed and the rest of the pool a few at a time (see CouncilWindow).
	LootWindow.EnsureRows(INITIAL_ROWS)
	local function fillPool()
		if #LootWindow.rows >= POOL then return end
		LootWindow.EnsureRows(#LootWindow.rows + 4)
		C_Timer.After(0, fillPool)
	end
	C_Timer.After(0, fillPool)

	-- The scrollbar sits in the right margin, beside the rows.
	frame.scroll = UI.NewScrollBar(frame, function(newOffset)
		offset = newOffset
		LootWindow:Refresh()
	end)
	frame.scroll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -(HEADER_H + LABEL_H))
	frame.scroll:SetHeight(DEFAULT_ROWS * (ROW_H + ROW_GAP) - ROW_GAP)
	frame.scroll:Hide()

	-- The grip in the bottom right corner: drag it to show more or fewer rows.
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
		GameTooltip:SetText(L["Drag to change how many items are shown"])
		GameTooltip:Show()
	end)
	frame.grip:SetScript("OnLeave", function(self)
		for _, dot in ipairs(self.dots) do UI.SetTextureColor(dot, c.muted, 0.7) end
		GameTooltip:Hide()
	end)
	frame.grip:SetScript("OnMouseDown", function(self)
		GameTooltip:Hide()
		LootWindow:StartResize()
	end)
	frame.grip:SetScript("OnMouseUp", function() LootWindow:StopResize() end)

	frame:SetScript("OnMouseWheel", function(_, delta)
		local count = #ALC.LootDetection:GetItems()
		offset = max(0, min(offset - delta, max(0, count - maxRows())))
		LootWindow:Refresh()
	end)
	frame:SetScript("OnShow", function() LootWindow:Refresh() end)

	restorePosition()
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------
-- The status text sits at the right edge, or beside the remove button when it is shown.
local function anchorStatus(row, besideRemove)
	row.status:ClearAllPoints()
	if besideRemove then
		row.status:SetPoint("RIGHT", row.remove, "LEFT", -12, 0)
	else
		row.status:SetPoint("RIGHT", row, "RIGHT", -16, 0)
	end
end

-- "1h 42m", "42m" or "<1m"; orange when under half an hour, red under ten minutes.
function LootWindow.FormatTradeTime(seconds)
	if seconds <= 0 then return "|cffff5a5a" .. L["expired"] .. "|r" end
	local text
	if seconds >= 3600 then
		text = format("%dh %dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
	elseif seconds >= 60 then
		text = format("%dm", math.floor(seconds / 60))
	else
		text = "<1m"
	end
	local color = seconds < 600 and "ff5a5a" or seconds < 1800 and "e8a33d" or "9aa0a8"
	return "|cff" .. color .. text .. "|r"
end

-- The buttons of a row, right to left: remove, "Start" (the normal Loot Council session), then one per way an
-- addon built on ALC added (see ALC.RegisterStartMode). The name and the line under it keep clear of them.
-- The colours that tell the ways to start apart: Loot Council green (the colour of ALC), the other ways take their addon's
-- colour (Soft Reserve purple).
local function lcColor() return UI.HexColor("45C97E") or c.gold end
local function modeColor(mode) return (mode and mode.color and UI.HexColor(mode.color)) or UI.HexColor("9B7BFF") or c.gold end

local function layoutRowButtons(row, modes)
	local w, h = layoutCompact and 64 or 76, layoutCompact and 24 or 34
	row.start:SetSize(w, h)
	row.start:SetLabel(#modes > 0 and L["Start LC"] or L["Start"])
	row.start:SetTint(#modes > 0 and lcColor() or nil)
	row.modeButtons = row.modeButtons or {}
	local previous = row.start
	for i, mode in ipairs(modes) do
		local button = row.modeButtons[i]
		if not button then
			button = UI.NewButton(row, w, h, "", function(self)
				local ok, message = ALC.LootDetection:StartSession(row.entryId, self.modeId)
				if not ok and message then ALC:Print(message) end
			end)
			row.modeButtons[i] = button
		end
		button.modeId = mode.id
		button:SetSize(w, h)
		button:SetLabel(L["Start"] .. " " .. mode.label)
		button:SetTint(modeColor(mode))
		button:ClearAllPoints()
		button:SetPoint("RIGHT", previous, "LEFT", -6, 0)
		previous = button
	end
	for i = #modes + 1, #row.modeButtons do row.modeButtons[i]:Hide() end
	local reserved = REMOVE_SIZE + 8 + (#modes + 1) * (w + 6) + 10
	row.name:SetPoint("RIGHT", row, "RIGHT", -reserved, 0)
	row.sub:SetPoint("RIGHT", row, "RIGHT", -reserved, 0)
end

-- The winner's name in their class colour, when we know the class (they are in the group, or answered the item).
local function winnerText(entry)
	local name = entry.winner
	local unit = ALC:FindUnitByName(name)
	local class = unit and select(2, UnitClass(unit))
	if not class and entry.item and ALC.Candidates and ALC.Candidates.Get then
		local candidate = ALC.Candidates:Get(name, entry.item)
		class = candidate and candidate.class
	end
	if not class then return name end
	local color = UI.ClassColor(class)
	return string.format("|cff%02x%02x%02x%s|r", math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5), math.floor(color[3] * 255 + 0.5), name)
end

local function renderRow(row, entry, sessionActive, isLM, modes, brand)
	local LootDetection = ALC.LootDetection
	local status = LootDetection.STATUS
	local display = LootDetection:GetItemDisplay(entry)

	row.entry, row.entryId = entry, entry.id
	layoutRowButtons(row, modes)
	row.icon:SetTexture(display.icon or UNKNOWN_ICON)
	local qc = UI.QualityColor(display.quality)
	row.iconBorder:SetColor(qc)
	row.name:SetTextColor(qc[1], qc[2], qc[3], 1)
	row.name:SetText(display.name or L["Loading..."])

	local subtitle = display.subtitle
	-- What an addon built on ALC knows about the item ("SR x3"), and that mode's start button marked
	local flagged = {}
	if entry.status == status.PENDING then
		for i, mode in ipairs(modes) do
			local ok, text = false, nil
			if mode.info then ok, text = pcall(mode.info, entry.itemID) end
			if ok and text then
				flagged[i] = true
				local hex = mode.color and mode.color:match("^%x%x%x%x%x%x$")
				subtitle = (subtitle ~= "" and (subtitle .. " \194\183 ") or "") .. (hex and ("|cff" .. hex .. text .. "|r") or text)
			end
		end
	end
	if (entry.status == status.AWARDED or entry.status == status.TRADE) and entry.winner then
		subtitle = (subtitle ~= "" and (subtitle .. " \194\183 ") or "") .. winnerText(entry)
	end
	local left = LootDetection:GetTradeTimeLeft(entry)
	if left then
		subtitle = (subtitle ~= "" and (subtitle .. " \194\183 ") or "") .. format(L["BoP %s"], LootWindow.FormatTradeTime(left))
		local share = math.min(1, left / LootDetection.BOP_TRADE_SECONDS)
		local width = max(1, math.floor((WIDTH - 2 * PAD - 12) * share))
		row.bar.fill:SetWidth(width)
		local tone = left < 600 and { 1, 0.35, 0.35 } or left < 1800 and { 0.91, 0.64, 0.24 } or { 0.55, 0.58, 0.62 }
		row.bar.fill:SetColorTexture(tone[1], tone[2], tone[3], 0.9)
		row.bar:Show()
	else
		row.bar:Hide()
	end
	row.sub:SetText(subtitle)

	local inSession = entry.status == status.SESSION
	-- The accent of a row in a session is the colour of the addon that started it (Soft Reserve: purple).
	local accent = (inSession and brand) or c.gold
	if inSession then
		if brand then UI.SetTextureColor(row.bg, brand, 0.14) else UI.SetTextureColor(row.bg, c.goldTint) end
		row.border:SetColor(accent)
	else
		UI.SetTextureColor(row.bg, c.panel)
		row.border:SetColor(c.border)
	end

	row.start:Hide()
	for _, button in ipairs(row.modeButtons or {}) do button:Hide() end
	row.status:Hide()
	row.remove:Hide()
	row.removeBlocked = entry.status == status.TRADE
	row.remove.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], row.removeBlocked and 0.35 or 1)
	if entry.status == status.PENDING then
		row.start:Show()
		row.start:SetAvailable(isLM and not sessionActive)
		for i = 1, #modes do
			row.modeButtons[i]:Show()
			row.modeButtons[i]:SetAvailable(isLM and not sessionActive)
			row.modeButtons[i]:SetSelected(flagged[i] == true) -- the way to start that fits what the addon knows
		end
		row.remove:Show()
	elseif inSession then
		anchorStatus(row, false)
		row.status:SetTextColor(accent[1], accent[2], accent[3], 1)
		row.status:SetText(L["In session"])
		row.status:Show()
	elseif entry.status == status.TRADE then
		anchorStatus(row, true)
		row.status:SetTextColor(c.gold[1], c.gold[2], c.gold[3], 0.8)
		row.status:SetText(L["Awaiting trade"])
		row.status:Show()
		row.remove:Show()
	else
		anchorStatus(row, true)
		row.status:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
		row.status:SetText(L["Awarded"])
		row.status:Show()
		row.remove:Show()
	end
	row:Show()
end

function LootWindow:Refresh()
	if not frame or not frame:IsShown() then return end
	applyDensity()
	local LootDetection = ALC.LootDetection
	local items = LootDetection:GetItems()
	local count = #items
	local rowsAllowed = maxRows()
	offset = max(0, min(offset, max(0, count - rowsAllowed)))

	frame.title:SetText(L["LOOT"])

	local qualityName = _G["ITEM_QUALITY" .. ALC.Settings:GetQualityThreshold() .. "_DESC"] or L["Selected quality"]
	local label = strupper(qualityName) .. " " .. strupper(L["and above"])
	local hidden = LootDetection:GetHiddenCount()
	if hidden > 0 then label = label .. " \194\183 " .. hidden .. " " .. strupper(L["hidden"]) end
	frame.label:SetText(label)
	frame.count:SetText(string.format("%d %s", count, count == 1 and L["item"] or L["items"]))

	local session = ALC.Sessions:GetSession()
	local sessionActive = session ~= nil
	local isLM = ALC.Council:AmLootMaster()
	local modes = ALC.GetStartModes()
	local _, brand = UI.SessionBrand(session)

	-- More ways to start a session need more room: wider window, one more button per mode in the footer.
	WIDTH = BASE_WIDTH + MODE_EXTRA * min(#modes, 2)
	frame:SetWidth(WIDTH)

	local shown = min(count - offset, rowsAllowed)
	LootWindow.EnsureRows(shown)
	for i = 1, #self.rows do
		local row = self.rows[i]
		local entry = items[offset + i]
		if entry and i <= shown then renderRow(row, entry, sessionActive, isLM, modes, brand) else row.entry, row.entryId = nil, nil; row:Hide() end
	end

	frame.empty:SetShown(count == 0)
	frame.hint:SetText(sessionActive and (session.finishing and (session.mode and L["All awarded. Close the session when you are done."] or L["All awarded. The session closes by itself."]) or L["In session"]) or "")
	local finished = 0
	for _, entry in ipairs(items) do
		if entry.status == LootDetection.STATUS.AWARDED then finished = finished + 1 end
	end
	frame.clearDone:SetLabel(finished > 0 and string.format("%s (%d)", L["Clear done"], finished) or L["Clear done"])
	frame.clearDone:SetAvailable(finished > 0)
	frame.cancel:SetAvailable(sessionActive and session.isLM)
	local waiting = #LootDetection:GetPending()
	local allLabel = #modes > 0 and L["Start all LC"] or L["Start all"]
	frame.startAll:SetLabel(waiting > 1 and string.format("%s (%d)", allLabel, waiting) or allLabel)
	frame.startAll:SetAvailable(isLM and not sessionActive and waiting > 1)
	-- With one way to start it keeps its amber frame; with two, neither is picked for you.
	frame.startAll:SetSelected(#modes == 0)
	frame.startAll:SetTint(#modes > 0 and lcColor() or nil)
	-- One "Start all" for each way an addon built on ALC added (left of the normal one, the nearest to the corner first).
	frame.modeAll = frame.modeAll or {}
	local anchor = nil
	for i = 1, min(#modes, 2) do
		local mode = modes[i]
		local button = frame.modeAll[i]
		if not button then
			button = UI.NewButton(frame, 104, 30, "", function(clicked)
				local ok, message = ALC.LootDetection:StartAll(clicked.modeId)
				if not ok and message then ALC:Print(message) end
			end)
			frame.modeAll[i] = button
		end
		button.modeId = mode.id
		local label = L["Start all"] .. " " .. mode.label
		button:SetLabel(waiting > 1 and string.format("%s (%d)", label, waiting) or label)
		button:SetTint(modeColor(mode))
		button:SetAvailable(isLM and not sessionActive and waiting > 1)
		button:ClearAllPoints()
		button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - (i - 1) * 112, 17)
		button:Show()
		anchor = button
	end
	for i = min(#modes, 2) + 1, #frame.modeAll do frame.modeAll[i]:Hide() end
	frame.startAll:ClearAllPoints()
	if anchor then
		-- The row of buttons: the "Start all" of each mode, then the normal one, then Cancel.
		frame.startAll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - min(#modes, 2) * 112, 17)
		frame.startAll:SetSize(112, 30)
	else
		frame.startAll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 17)
		frame.startAll:SetSize(100, 30)
	end

	-- An item a winner traded back, waiting for the loot master's answer.
	local offers = LootDetection:GetReturned()
	local offer = offers[1]
	local bar = frame.returnedBar
	if offer and isLM then
		local display = LootDetection:GetItemDisplay({ itemString = offer.itemString, itemID = offer.itemID })
		bar.offerId = offer.id
		bar.text:SetText(winnerText({ winner = offer.from }) .. " " .. L["gave back"] .. " " .. (display.name or "?")
			.. (#offers > 1 and (" (+" .. (#offers - 1) .. ")") or ""))
		bar:Show()
	else
		bar.offerId = nil
		bar:Hide()
	end
	local extra = (offer and isLM) and (RETURNED_H + 8) or 0

	local body = max(shown, 1) * (ROW_H + ROW_GAP) - ROW_GAP
	if count == 0 then body = 64 end

	-- The scrollbar follows the rows and shows itself only when the list is longer.
	frame.scroll:SetHeight(max(shown, 1) * (ROW_H + ROW_GAP) - ROW_GAP)
	frame.scroll:Update(count, rowsAllowed, offset)

	frame:SetHeight(HEADER_H + LABEL_H + body + 14 + FOOTER_H + extra)
end

--------------------------------------------------------------------------------
-- Resizing with the grip: the top edge stays put, the window grows downwards, and the
-- number of rows follows the mouse.
--------------------------------------------------------------------------------
local function resizeStep()
	local _, cursorY = GetCursorPosition()
	cursorY = cursorY / frame:GetEffectiveScale()
	local body = (frame:GetTop() - cursorY) - (HEADER_H + LABEL_H + 14 + FOOTER_H)
	local rows = max(MIN_ROWS, min(POOL, math.floor(body / (ROW_H + ROW_GAP) + 0.5)))
	if rows ~= maxRows() then
		ALC.Settings:SetWindowOption("loot", "maxRows", rows)
		LootWindow:Refresh()
	end
end

function LootWindow:StartResize()
	if not frame then return end
	local left, top = frame:GetLeft(), frame:GetTop()
	if left and top then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	end
	frame.grip:SetScript("OnUpdate", resizeStep)
end

function LootWindow:StopResize()
	if not frame then return end
	frame.grip:SetScript("OnUpdate", nil)
	savePosition()
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------
-- Whether the window is open is remembered, so it comes back after a /reload.
function LootWindow:Show()
	if not frame then
		-- A build that fails half way must not leave a broken frame behind.
		local ok, err = pcall(build)
		if not ok then
			frame = nil
			error(err, 0)
		end
	end
	frame:Show()
	ALC.Settings:SetWindowShown("loot", true)
	self:Refresh()
end

function LootWindow:Hide()
	if frame then frame:Hide() end
	ALC.Settings:SetWindowShown("loot", false)
end

-- After a reload or login: reopen the window if it was open and there are items to show.
function LootWindow:OnEnteringWorld(isInitialLogin, isReloadingUi)
	if not (isInitialLogin or isReloadingUi) then return end
	if ALC.Settings:GetWindowShown("loot") and #ALC.LootDetection:GetItems() > 0 then
		self:Show()
	end
end

function LootWindow:Toggle()
	if frame and frame:IsShown() then self:Hide() else self:Show() end
end

function LootWindow:IsShown()
	return frame ~= nil and frame:IsShown()
end

function LootWindow:Init()
	local register = ALC.Events.Register
	local refresh = function() LootWindow:Refresh() end
	register(self, "ALC_LOOT_CHANGED", refresh)
	register(self, "ALC_LOOT_RETURNED", function()
		if ALC.Settings:GetAutoOpenLootWindow() then LootWindow:Show() end
		LootWindow:Refresh()
	end)
	register(self, "ALC_SESSION_STARTED", refresh)
	register(self, "ALC_SESSION_ENDED", refresh)
	register(self, "ALC_COUNCIL_LM_CHANGED", refresh)
	register(self, "ALC_AWARDS_ANNOUNCED", refresh)
	register(self, "ALC_SETTINGS_CHANGED", function(_, key)
		if key == "compact" or key == "announceAwards" then LootWindow:Refresh() end
	end)
	register(self, "ALC_LOOT_ADDED", function()
		if ALC.Settings:GetAutoOpenLootWindow() then LootWindow:Show() end
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
		LootWindow:OnEnteringWorld(isInitialLogin, isReloadingUi)
	end)
	-- The trade timers count down while the window is open.
	if C_Timer and C_Timer.NewTicker then
		C_Timer.NewTicker(30, function() if frame and frame:IsShown() then LootWindow:Refresh() end end)
	end
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------
ALC.Commands:Register("loot", function(arg)
	local sub, rest = string.match(arg, "^(%S*)%s*(.-)$")
	sub = string.lower(sub)
	if sub == "" then
		LootWindow:Toggle()
	elseif sub == "auto" then
		local settings = ALC.Settings
		rest = string.lower(rest)
		if rest == "on" or rest == "off" then settings:SetAutoOpenLootWindow(rest == "on") end
		ALC:Print(settings:GetAutoOpenLootWindow() and L["The loot window opens by itself when items arrive."] or L["The loot window stays closed until you open it."])
	elseif sub == "clear" then
		ALC:Print(L["Removed %d finished item(s)."], ALC.LootDetection:ClearFinished())
	elseif sub == "reset" then
		ALC:Print(L["Removed %d item(s)."], ALC.LootDetection:Clear())
	else
		ALC:Print(L["Usage: /alc loot [auto on|off | clear | reset]"])
	end
end, L["open the loot window (auto on|off, clear, reset)"])

-- ContextWindow: "Arbiter Context", the box that opens to the right of the Council window when the council clicks a
-- candidate. It shows what is on the row, in full (rank, answer, roll, votes, the note), how the item compares with what
-- the player wears, whether the player has already had loot in the same slot (or this very item), the loot history with
-- "tonight", "this week" and older told apart, and anything an addon built on ALC adds (Soft Reserve: reserved or not).
-- Presentation only: the facts come from ALC.Context.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local strupper = string.upper
local min, max, floor = math.min, math.max, math.floor

local WIDTH, PAD, HEADER_H = 380, 16, 40
local HIST_POOL, HIST_H = 24, 40  -- history rows made, and the height of one
local HIST_SHOWN = 7              -- history rows shown at most (the rest scrolls)
local PROVIDER_LINES = 8          -- lines of providers shown at most
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local c = UI.color

local ContextWindow = {}
ALC.ContextWindow = ContextWindow
ContextWindow.histRows = {}

local frame
local histOffset = 0
local shownName, shownItem

local DAY = 86400

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------
local function hex(color)
	return string.format("%02x%02x%02x", floor((color[1] or 1) * 255 + 0.5), floor((color[2] or 1) * 255 + 0.5), floor((color[3] or 1) * 255 + 0.5))
end

local function colored(text, color)
	if not color then return text end
	local h = type(color) == "string" and color or hex(color)
	return "|cff" .. h .. text .. "|r"
end

-- The colour of a response as a table, from the hex text the history keeps or a table.
local function colorOf(value)
	if type(value) == "table" then return value end
	return UI.HexColor(value)
end

-- "tonight", "3 days ago" or the date.
local function whenText(h)
	if h.tag == "tonight" then return L["tonight"] end
	local days = max(0, floor((time() - h.time) / DAY))
	if h.tag == "week" then return days <= 1 and (days == 0 and L["today"] or L["yesterday"]) or string.format(L["%d days ago"], days) end
	return h.dateText or ""
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------
local function newHistoryRow()
	local row = CreateFrame("Frame", nil, frame)
	row:SetHeight(HIST_H - 4)
	row.bg = UI.NewFill(row, 6)
	UI.SetTextureColor(row.bg, c.panel)
	row.border = UI.AddBorder(row, c.border, 1, 6)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(24, 24)
	row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
	row.name = UI.NewText(row, 13, c.text)
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
	row.name:SetWidth(WIDTH - 2 * PAD - 160)
	row.sub = UI.NewText(row, 11, c.muted)
	row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -1)
	row.sub:SetWidth(WIDTH - 2 * PAD - 100)
	row.tag = UI.NewText(row, 11, c.muted, "RIGHT")
	row.tag:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -6)
	row.badge = UI.NewText(row, 10, c.gold, "RIGHT")
	row.badge:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 6)
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		if GameTooltip and self.itemString then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetHyperlink(self.itemString)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	row:Hide()
	return row
end

local function build()
	frame = CreateFrame("Frame", nil, UIParent)
	UI.RegisterScaled(frame)
	frame:SetSize(WIDTH, 400)
	frame:SetFrameStrata("HIGH")
	frame:SetFrameLevel(61)
	frame:SetClampedToScreen(true)
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
	local logo = UI.NewLogo(header, 22)
	logo:SetPoint("LEFT", header, "LEFT", PAD, 0)
	local title = UI.NewText(header, 14, c.text)
	title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
	title:SetText(strupper(L["Arbiter Context"]))
	local close = CreateFrame("Button", nil, header)
	close:SetSize(30, 30)
	close:SetPoint("RIGHT", header, "RIGHT", -12, 0)
	close.text = UI.NewText(close, 30, c.muted, "CENTER")
	close.text:SetPoint("CENTER", 0, 0)
	close.text:SetText("\195\151")
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(c.text[1], c.text[2], c.text[3], 1) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1) end)
	close:SetScript("OnClick", function() ALC.CouncilWindow:ClearSelected() end)
	local line = frame:CreateTexture(nil, "BORDER")
	line:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -HEADER_H)
	line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -HEADER_H)
	line:SetHeight(1)
	UI.SetTextureColor(line, c.border)

	local function text(size, color, justify, wrap)
		local fs = UI.NewText(frame, size, color or c.text, justify)
		if wrap then
			fs:SetWidth(WIDTH - 2 * PAD)
			fs:SetWordWrap(true)
			fs:SetJustifyV("TOP")
		end
		return fs
	end
	-- who
	frame.name = text(16)
	frame.rank = text(12, c.muted, "RIGHT")
	frame.answer = text(13)
	frame.meta = text(12, c.muted)
	frame.voters = text(11, c.muted, nil, true)
	frame.note = text(12, c.text, nil, true)
	-- the item
	frame.itemTitle = text(11, c.muted)
	frame.itemTitle:SetText(strupper(L["This item"]))
	frame.itemLine = text(13)
	frame.wearLine = text(12, c.muted, nil, true)
	-- the same slot
	frame.slotPanel = CreateFrame("Frame", nil, frame)
	frame.slotPanel.bg = UI.NewFill(frame.slotPanel, 8)
	frame.slotPanel.border = UI.AddBorder(frame.slotPanel, c.border, 1, 8)
	frame.slotText = UI.NewText(frame.slotPanel, 12, c.text)
	frame.slotText:SetPoint("TOPLEFT", frame.slotPanel, "TOPLEFT", 10, -8)
	frame.slotText:SetWidth(WIDTH - 2 * PAD - 20)
	frame.slotText:SetWordWrap(true)
	frame.slotText:SetJustifyV("TOP")
	frame.slotPanel:Hide()
	-- what addons add
	frame.providerLines = {}
	for i = 1, PROVIDER_LINES do
		local fs = text(12, c.text, nil, true)
		fs:Hide()
		frame.providerLines[i] = fs
	end
	-- the history
	frame.histTitle = text(11, c.muted)
	frame.histTitle:SetText(strupper(L["Loot history"]))
	frame.histSummary = text(12, c.muted, nil, true)
	frame.histEmpty = text(12, c.muted, nil, true)
	frame.hint = text(11, c.muted)
	frame.hint:SetText(L["Ctrl-click another row to compare."])
	for i = 1, HIST_POOL do ContextWindow.histRows[i] = newHistoryRow() end
	frame.scroll = UI.NewScrollBar(frame, function(newOffset)
		histOffset = newOffset
		ContextWindow:Sync()
	end)
	frame.scroll:Hide()
	frame:SetScript("OnMouseWheel", function(_, delta)
		histOffset = max(0, histOffset - delta)
		ContextWindow:Sync()
	end)
end

--------------------------------------------------------------------------------
-- Placing and drawing
--------------------------------------------------------------------------------
local function place(widget, y, x, anchor)
	widget:ClearAllPoints()
	widget:SetPoint(anchor or "TOPLEFT", frame, anchor or "TOPLEFT", x or PAD, -y)
end

local function heightOf(fs, fallback)
	local h = fs.GetStringHeight and fs:GetStringHeight()
	if not h or h <= 0 then return fallback end
	return h
end

-- Sits right of the Council window, or left of it when the screen is too narrow.
local function position()
	local council = ALC.CouncilWindow:GetFrame()
	if not council then return end
	frame:ClearAllPoints()
	local right = council:GetRight()
	local scale = council:GetEffectiveScale() / UIParent:GetEffectiveScale()
	if right and UIParent:GetWidth() and right * scale + WIDTH + 12 > UIParent:GetWidth() then
		frame:SetPoint("TOPRIGHT", council, "TOPLEFT", -90, 0) -- left of the item strip that hangs outside the window
	else
		frame:SetPoint("TOPLEFT", council, "TOPRIGHT", 8, 0)
	end
end

local function render(info)
	local y = HEADER_H + 14
	local classColor = UI.ClassColor(info.class)
	frame.name:SetTextColor(classColor[1], classColor[2], classColor[3], 1)
	frame.name:SetText(info.name)
	place(frame.name, y)
	frame.rank:SetText(info.rank or "")
	place(frame.rank, y + 3, -PAD, "TOPRIGHT")
	y = y + 26

	-- the answer, the roll and the votes
	if info.waiting then
		frame.answer:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
		frame.answer:SetText(L["Has not answered yet"])
	else
		local color = colorOf(info.color) or c.text
		frame.answer:SetTextColor(color[1], color[2], color[3], 1)
		frame.answer:SetText(info.label or "")
	end
	place(frame.answer, y)
	local meta = {}
	if info.roll then meta[#meta + 1] = string.format(L["Roll %d"], info.roll) end
	if (info.votes or 0) > 0 then meta[#meta + 1] = string.format(L["%d votes"], info.votes) end
	frame.meta:SetText(table.concat(meta, "   "))
	frame.meta:ClearAllPoints()
	frame.meta:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y)
	y = y + 20
	if info.voters and #info.voters > 0 then
		frame.voters:SetText(L["Voted for by"] .. ": " .. table.concat(info.voters, ", "))
		place(frame.voters, y)
		y = y + heightOf(frame.voters, 14) + 6
	else
		frame.voters:SetText("")
	end
	if info.note and info.note ~= "" then
		frame.note:SetText("\"" .. info.note .. "\"")
		place(frame.note, y)
		y = y + heightOf(frame.note, 16) + 8
	else
		frame.note:SetText("")
	end
	y = y + 6

	-- the item and what is worn
	place(frame.itemTitle, y)
	y = y + 18
	if info.item then
		local qc = info.item.quality and UI.QualityColor(info.item.quality)
		local parts = { colored(info.item.name or L["Loading..."], qc) }
		if info.item.slotLabel then parts[#parts + 1] = info.item.slotLabel end
		if info.item.ilvl then parts[#parts + 1] = string.format(L["ilvl %d"], info.item.ilvl) end
		frame.itemLine:SetText(table.concat(parts, "  \194\183  "))
	else
		frame.itemLine:SetText("")
	end
	place(frame.itemLine, y)
	y = y + 20
	local wear
	if info.waiting then
		wear = L["No answer yet, so nothing is known about what is worn."]
	elseif info.emptySlot then
		wear = colored(L["Nothing equipped in that slot"], { 0.30, 0.75, 0.40 })
	else
		local worn = {}
		for _, g in ipairs(info.gear) do
			local qc = g.quality and UI.QualityColor(g.quality)
			worn[#worn + 1] = colored(g.name or L["Loading..."], qc) .. (g.ilvl and (" (" .. g.ilvl .. ")") or "")
		end
		wear = L["Wearing"] .. ": " .. table.concat(worn, ", ")
		if info.ilvlDelta then
			local d = info.ilvlDelta
			local tone = d > 0 and { 0.30, 0.75, 0.40 } or (d < 0 and c.danger or c.muted)
			wear = wear .. "   " .. colored(d == 0 and L["same item level"] or ((d > 0 and "+" or "") .. d .. " " .. L["item level"]), tone)
		end
	end
	frame.wearLine:SetText(wear)
	place(frame.wearLine, y)
	y = y + heightOf(frame.wearLine, 16) + 10

	-- the same slot, or the very same item: the thing the council most wants to see
	local panel = frame.slotPanel
	local lines
	local tone
	if #info.sameItem > 0 then
		lines, tone = {}, c.danger
		lines[1] = colored(L["Has already won this item"], c.danger)
		for i = 1, min(2, #info.sameItem) do
			local h = info.sameItem[i]
			lines[#lines + 1] = string.format("%s  \194\183  %s", whenText(h), colored(h.label, colorOf(h.color)))
		end
	elseif #info.sameSlot > 0 then
		lines, tone = {}, c.gold
		lines[1] = colored(string.format(L["Has already received a %s"], info.item and info.item.slotLabel or L["piece in this slot"]), c.gold)
		for i = 1, min(3, #info.sameSlot) do
			local h = info.sameSlot[i]
			local qc = h.quality and UI.QualityColor(h.quality)
			lines[#lines + 1] = string.format("%s  \194\183  %s  \194\183  %s", colored(h.name or L["Loading..."], qc), colored(h.label, colorOf(h.color)), whenText(h))
		end
		if #info.sameSlot > 3 then lines[#lines + 1] = string.format(L["... and %d more"], #info.sameSlot - 3) end
	elseif info.complete and info.item and info.item.slot then
		lines, tone = { colored(string.format(L["No loot in the %s slot yet"], info.item.slotLabel or ""), { 0.30, 0.75, 0.40 }) }, { 0.30, 0.75, 0.40 }
	end
	if lines then
		frame.slotText:SetText(table.concat(lines, "\n"))
		panel:ClearAllPoints()
		panel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
		local h = heightOf(frame.slotText, 16 * #lines) + 16
		panel:SetSize(WIDTH - 2 * PAD, h)
		UI.SetTextureColor(panel.bg, tone, 0.12)
		panel.border:SetColor(tone)
		panel:Show()
		y = y + h + 10
	else
		panel:Hide()
	end

	-- what addons built on ALC know
	local used = 0
	for _, provider in ipairs(info.providers or {}) do
		if used < PROVIDER_LINES then
			used = used + 1
			local fs = frame.providerLines[used]
			fs:SetText(colored(strupper(provider.title), provider.color))
			place(fs, y)
			fs:Show()
			y = y + 18
		end
		for _, line in ipairs(provider.lines) do
			if used < PROVIDER_LINES then
				used = used + 1
				local fs = frame.providerLines[used]
				fs:SetText(colored((line.label or "") .. (line.label and ": " or ""), c.muted) .. colored(line.text or "", line.color))
				place(fs, y)
				fs:Show()
				y = y + heightOf(fs, 16) + 2
			end
		end
		y = y + 6
	end
	for i = used + 1, PROVIDER_LINES do frame.providerLines[i]:Hide() end

	-- the history
	place(frame.histTitle, y)
	y = y + 18
	local summary
	if not info.complete then
		summary = L["Asking the loot master ..."]
	elseif #info.history == 0 then
		summary = L["No loot recorded for this player yet."]
	else
		summary = string.format(L["%d awards"], info.total)
		summary = summary .. string.format(L["  \194\183  7 days: %d  \194\183  14 days: %d  \194\183  30 days: %d"], info.counts[7], info.counts[14], info.counts[30])
		if info.total > #info.history then summary = summary .. "  \194\183  " .. string.format(L["the latest %d are listed"], #info.history) end
	end
	frame.histSummary:SetText(summary)
	place(frame.histSummary, y)
	y = y + heightOf(frame.histSummary, 16) + 8
	frame.histEmpty:SetText("")

	local shown = min(#info.history, HIST_SHOWN)
	histOffset = max(0, min(histOffset, max(0, #info.history - shown)))
	for i, row in ipairs(ContextWindow.histRows) do
		local h = info.history[i + histOffset]
		if h and i <= shown then
			local display = ALC.LootDetection:GetItemDisplay({ itemString = h.itemString or ("item:" .. h.itemID), itemID = h.itemID })
			row.itemString = h.itemString or ("item:" .. h.itemID)
			row.icon:SetTexture(display.icon or UNKNOWN_ICON)
			local qc = UI.QualityColor(display.quality)
			row.name:SetTextColor(qc[1], qc[2], qc[3], 1)
			row.name:SetText(display.name or L["Loading..."])
			local sub = colored(h.label or "", colorOf(h.color))
			if h.zone and h.zone ~= "" then sub = sub .. "  \194\183  " .. h.zone end
			row.sub:SetText(sub)
			local tag = whenText(h)
			if h.tag == "tonight" then
				row.tag:SetTextColor(0.30, 0.75, 0.40, 1)
			elseif h.tag == "week" then
				row.tag:SetTextColor(c.text[1], c.text[2], c.text[3], 1)
			else
				row.tag:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
			end
			row.tag:SetText(h.tag == "tonight" and strupper(tag) or tag)
			if h.sameItem then
				row.badge:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1)
				row.badge:SetText(strupper(L["same item"]))
			elseif h.sameSlot then
				row.badge:SetTextColor(c.gold[1], c.gold[2], c.gold[3], 1)
				row.badge:SetText(strupper(L["same slot"]))
			else
				row.badge:SetText("")
			end
			if h.sameSlot or h.sameItem then
				row.border:SetColor(h.sameItem and c.danger or c.gold)
			else
				row.border:SetColor(c.border)
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(y + (i - 1) * HIST_H))
			row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - (#info.history > shown and 12 or 0), -(y + (i - 1) * HIST_H))
			row:Show()
		else
			row:Hide()
		end
	end
	local listHeight = shown * HIST_H
	frame.scroll:ClearAllPoints()
	frame.scroll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -y)
	frame.scroll:SetHeight(max(1, listHeight - 4))
	frame.scroll:Update(#info.history, max(1, shown), histOffset)
	y = y + listHeight + 10
	place(frame.hint, y)
	y = y + 26
	frame:SetHeight(y)
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------
-- Called after the Council window drew itself, and when something about the player arrives: shows the box for the
-- candidate the council picked (or hides it).
function ContextWindow:Sync()
	local council = ALC.CouncilWindow
	local name = council:GetSelected()
	local compare = ALC.CompareWindow
	if name == nil then
		if frame then frame:Hide() end
		if compare then compare:Hide() end
		shownName = nil
		return
	end
	local session = ALC.Sessions:GetSession()
	local visible = council:IsShown() and council:GetTab() == "council" and session ~= nil and session.isCouncil
	if not visible then
		if frame then frame:Hide() end
		if compare then compare:Hide() end
		shownName = nil
		return
	end
	local item = council:GetFocus()
	-- A second candidate (Ctrl-click): the comparison takes the place of this box
	local other = council:GetCompare()
	if other and compare then
		local a, b = ALC.Context:Build(name, item), ALC.Context:Build(other, item)
		if a and b then
			if not a.complete then ALC.Context:Request(a.name) end
			if not b.complete then ALC.Context:Request(b.name) end
			if frame then frame:Hide() end
			shownName, shownItem = nil, item
			compare:Show(a, b)
			return
		end
	end
	if compare then compare:Hide() end
	if not frame then build() end
	if name ~= shownName or item ~= shownItem then histOffset = 0 end
	shownName, shownItem = name, item
	position()
	local info = ALC.Context:Build(name, item)
	if not info then
		frame:Hide()
		return
	end
	if not info.complete then ALC.Context:Request(info.name) end
	render(info)
	frame:Show()
end

function ContextWindow:IsShown()
	return frame ~= nil and frame:IsShown()
end

function ContextWindow:GetFrame()
	return frame
end

function ContextWindow:Init()
	local register = ALC.Events.Register
	register(self, "ALC_CONTEXT_CHANGED", function() ContextWindow:Sync() end)
	register(self, "ALC_SESSION_ENDED", function() ContextWindow:Sync() end)
end

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

local CouncilWindow = {}
ALC.CouncilWindow = CouncilWindow
CouncilWindow.rows = {}

local frame, offset = nil, 0
local c = UI.color

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
	divider(-(HEADER_H + ITEM_H))
	local function heading(text, x, justify, width)
		local fs = UI.NewText(frame, 11, c.muted, justify)
		fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + x, -(HEADER_H + ITEM_H + 12))
		if width then fs:SetWidth(width) end
		fs:SetText(strupper(text))
		return fs
	end
	heading(L["Player"], NAME_X)
	heading(L["Response"], RESPONSE_X)
	heading(L["Current gear"], GEAR_X)
	heading(L["Votes"], VOTES_X, "CENTER", 60)
	divider(-(HEADER_H + ITEM_H + TABLE_HEAD_H))

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

	for i = 1, MAX_ROWS do
		CouncilWindow.rows[i] = newRow(i)
	end

	frame:SetScript("OnMouseWheel", function(_, delta)
		local count = #CouncilWindow:GetVisible()
		offset = max(0, min(offset - delta, max(0, count - MAX_ROWS)))
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

function CouncilWindow:Refresh()
	if not frame or not frame:IsShown() then return end
	local session = ALC.Sessions:GetSession()
	if not session then
		self:Hide()
		return
	end

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

	frame.lootMaster:SetText(L["Loot master"] .. ": " .. session.lm)
	frame.tally:SetText(string.format("%d %s \194\183 %d %s", counts.passed, L["passed"], counts.silent, L["not responded"]))

	local rows = max(shown, 2)
	frame:SetHeight(HEADER_H + ITEM_H + TABLE_HEAD_H + rows * ROW_H + FOOTER_H)
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------
-- Only the council opens it. Whether it is open is remembered across a /reload.
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
	if not frame then
		-- A build that fails half way must not leave a broken frame behind.
		local ok, err = pcall(build)
		if not ok then
			frame = nil
			error(err, 0)
		end
	end
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
	register(self, "ALC_SESSION_ENDED", function() CouncilWindow:Hide() end)
end

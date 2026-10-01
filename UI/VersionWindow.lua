-- VersionWindow: who in the group has the addon, and which version. A small window opened
-- from the launcher or with /alc versions; it asks the group when it opens and fills in as
-- the answers arrive. Presentation only: the data is Comm:GetVersionRows().

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local strupper = string.upper
local min, max = math.min, math.max

local WIDTH, PAD = 460, 16
local HEADER_H, SUB_H, HEAD_H, FOOTER_H = 52, 48, 28, 54
local ROW_H, ROWS = 30, 12
local NAME_X, VERSION_X, STATUS_X = 12, 200, 310

local VersionWindow = {}
ALC.VersionWindow = VersionWindow
VersionWindow.rows = {}

local frame
local offset = 0
local waitingUntil = 0 -- replies are still awaited until then
local c = UI.color

local GREEN = { 0.30, 0.75, 0.40, 1 }

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------
local function savePosition()
	local point, _, relPoint, x, y = frame:GetPoint()
	ALC.Settings:SetWindowPosition("versions", point, relPoint, x, y)
end

local function restorePosition()
	frame:ClearAllPoints()
	local pos = ALC.Settings:GetWindowPosition("versions")
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	end
end

local function newRow(index)
	local row = CreateFrame("Frame", nil, frame)
	row:SetHeight(ROW_H)
	local top = -(HEADER_H + SUB_H + HEAD_H + (index - 1) * ROW_H)
	row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, top)
	row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - 10, top)
	row.line = row:CreateTexture(nil, "BORDER")
	row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 0)
	row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 0)
	row.line:SetHeight(1)
	UI.SetTextureColor(row.line, c.border, 0.5)
	row.name = UI.NewText(row, 13, c.text)
	row.name:SetPoint("LEFT", row, "LEFT", NAME_X, 0)
	row.name:SetWidth(VERSION_X - NAME_X - 8)
	row.version = UI.NewText(row, 13, c.text)
	row.version:SetPoint("LEFT", row, "LEFT", VERSION_X, 0)
	row.version:SetWidth(STATUS_X - VERSION_X - 8)
	row.status = UI.NewText(row, 12, c.muted)
	row.status:SetPoint("LEFT", row, "LEFT", STATUS_X, 0)
	row.status:SetWidth(WIDTH - 2 * PAD - STATUS_X - 14)
	return row
end

local function build()
	frame = CreateFrame("Frame", nil, UIParent)
	UI.RegisterScaled(frame)
	frame:SetSize(WIDTH, 300)
	frame:SetFrameStrata("HIGH")
	frame:SetFrameLevel(30)
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
	frame.header = header

	local logo = UI.NewLogo(header, 28)
	logo:SetPoint("LEFT", header, "LEFT", PAD, 0)
	local title = UI.NewText(header, 15, c.text)
	title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
	title:SetText(strupper(L["Versions"]))

	local close = CreateFrame("Button", nil, header)
	close:SetSize(28, 28)
	close:SetPoint("RIGHT", header, "RIGHT", -12, 0)
	close.text = UI.NewText(close, 22, c.muted, "CENTER")
	close.text:SetPoint("CENTER", 0, 0)
	close.text:SetText("\195\151")
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(c.text[1], c.text[2], c.text[3], 1) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1) end)
	close:SetScript("OnClick", function() VersionWindow:Hide() end)

	local divider = frame:CreateTexture(nil, "BORDER")
	divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -HEADER_H)
	divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -HEADER_H)
	divider:SetHeight(1)
	UI.SetTextureColor(divider, c.border)

	-- What we run ourselves, and the summary of the group.
	frame.mine = UI.NewText(frame, 12, c.muted)
	frame.mine:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER_H + 10))
	frame.summary = UI.NewText(frame, 13, c.text)
	frame.summary:SetPoint("TOPLEFT", frame.mine, "BOTTOMLEFT", 0, -6)

	local function heading(text, x)
		local fs = UI.NewText(frame, 11, c.muted)
		fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + x, -(HEADER_H + SUB_H + 6))
		fs:SetText(strupper(text))
	end
	heading(L["Player"], NAME_X)
	heading(L["Version"], VERSION_X)
	heading(L["Status"], STATUS_X)

	for i = 1, ROWS do VersionWindow.rows[i] = newRow(i) end
	frame.scroll = UI.NewScrollBar(frame, function(newOffset)
		offset = newOffset
		VersionWindow:Refresh()
	end)
	frame.scroll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -(HEADER_H + SUB_H + HEAD_H))
	frame.scroll:SetHeight(ROWS * ROW_H)
	frame.scroll:Hide()

	frame.footerLine = frame:CreateTexture(nil, "BORDER")
	frame.footerLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, FOOTER_H)
	frame.footerLine:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, FOOTER_H)
	frame.footerLine:SetHeight(1)
	UI.SetTextureColor(frame.footerLine, c.border)
	frame.note = UI.NewText(frame, 11, c.muted)
	frame.note:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 20)
	frame.refresh = UI.NewButton(frame, 110, 30, L["Ask again"], function() VersionWindow:Ask() end)
	frame.refresh:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 12)

	frame:SetScript("OnMouseWheel", function(_, delta)
		local total = #ALC.Comm:GetVersionRows()
		offset = max(0, min(offset - delta, max(0, total - ROWS)))
		VersionWindow:Refresh()
	end)
	frame:SetScript("OnShow", function() VersionWindow:Refresh() end)
	restorePosition()
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------
local STATUS_TEXT = {
	self = { text = L["You"], color = c.muted },
	ok = { text = L["Up to date"], color = GREEN },
	older = { text = L["Older: needs an update"], color = c.gold },
	newer = { text = L["Newer than yours"], color = c.gold },
	incompatible = { text = L["Incompatible protocol"], color = c.danger },
	none = { text = L["No reply: no addon?"], color = c.muted },
}

local function renderRow(row, info, waiting)
	local cc = info.class and UI.ClassColor(info.class) or c.text
	row.name:SetTextColor(cc[1], cc[2], cc[3], 1)
	row.name:SetText(info.name)
	row.version:SetText(info.addon and (info.addon .. (info.proto and string.format(" (v%d)", info.proto) or "")) or "\226\128\148")
	local state = STATUS_TEXT[info.status]
	local text, color = state.text, state.color
	if info.status == "none" and waiting then text, color = L["Waiting..."], c.muted end
	if info.status == "incompatible" and info.proto then text = string.format(L["Incompatible protocol (v%d)"], info.proto) end
	row.status:SetTextColor(color[1], color[2], color[3], 1)
	row.status:SetText(text)
	row:Show()
end

function VersionWindow:Refresh()
	if not frame or not frame:IsShown() then return end
	local list = ALC.Comm:GetVersionRows()
	local waiting = GetTime() < waitingUntil
	local total = #list
	local shown = min(total, ROWS)
	offset = max(0, min(offset, max(0, total - ROWS)))
	for i = 1, ROWS do
		local info = list[offset + i]
		if info and i <= shown then renderRow(self.rows[i], info, waiting) else self.rows[i]:Hide() end
	end
	frame.scroll:SetHeight(max(shown, 1) * ROW_H)
	frame.scroll:Update(total, ROWS, offset)

	local counts = { ok = 0, older = 0, newer = 0, incompatible = 0, none = 0 }
	for _, info in ipairs(list) do
		if counts[info.status] then counts[info.status] = counts[info.status] + 1 end
	end
	local withAddon = total - counts.none - counts.incompatible
	frame.mine:SetText(string.format(L["Your version: %s (protocol v%d)"], ALC.version, ALC.PROTOCOL_VERSION))
	if total <= 1 then
		frame.summary:SetText(L["You are not in a group."])
		frame.summary:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
	else
		local problems = counts.older + counts.incompatible + counts.none
		frame.summary:SetText(string.format(L["%d of %d have the addon"], withAddon, total)
			.. (counts.older > 0 and (" \194\183 " .. string.format(L["%d older"], counts.older)) or "")
			.. (counts.incompatible > 0 and (" \194\183 " .. string.format(L["%d incompatible"], counts.incompatible)) or "")
			.. (counts.none > 0 and not waiting and (" \194\183 " .. string.format(L["%d no reply"], counts.none)) or ""))
		local tone = (problems == 0 or waiting) and c.text or c.gold
		frame.summary:SetTextColor(tone[1], tone[2], tone[3], 1)
	end
	frame.note:SetText(waiting and L["Asking the group..."] or L["Anyone without a reply has no addon, or one too old to answer."])
	frame:SetHeight(HEADER_H + SUB_H + HEAD_H + max(shown, 3) * ROW_H + FOOTER_H)
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------
-- Asks the group again; the answers fill the list as they come.
function VersionWindow:Ask()
	ALC.Comm:RequestVersions(true)
	waitingUntil = GetTime() + ALC.Comm.VERSION_WAIT
	self:Refresh()
	-- When the time is up "Waiting..." turns into "No reply".
	C_Timer.After(ALC.Comm.VERSION_WAIT + 0.2, function() VersionWindow:Refresh() end)
end

function VersionWindow:Show()
	if not frame then
		-- A build that fails half way must not leave a broken frame behind.
		local ok, err = pcall(build)
		if not ok then
			frame = nil
			error(err, 0)
		end
	end
	offset = 0
	frame:Show()
	self:Ask()
end

function VersionWindow:Hide()
	if frame then frame:Hide() end
end

function VersionWindow:Toggle()
	if self:IsShown() then self:Hide() else self:Show() end
end

function VersionWindow:IsShown()
	return frame ~= nil and frame:IsShown()
end

function VersionWindow:Init()
	ALC.Events.Register(self, "ALC_VERSIONS_CHANGED", function() VersionWindow:Refresh() end)
	ALC.Events.Register(self, "ALC_SETTINGS_CHANGED", function(_, key)
		if key == "font" then VersionWindow:Refresh() end
	end)
end

ALC.Commands:Register("versions", function() VersionWindow:Toggle() end, L["show who in the group has the addon, and which version"])

-- ContextMenu: a small right-click menu that opens at the mouse.
-- Items are { label, onClick, enabled, reason, header, color }. A header is a caption, not
-- a choice. A disabled item is greyed out and says why in a tooltip. Presentation only.

local ALC = ALC
local UI = ALC.UI

local strupper = string.upper

local WIDTH, PAD = 220, 6
local ROW_H, HEADER_H = 26, 22

local ContextMenu = {}
ALC.ContextMenu = ContextMenu
ContextMenu.rows = {}

local menu, catcher
local c = UI.color

local function newRow(index)
	local row = CreateFrame("Button", nil, menu)
	row:RegisterForClicks("LeftButtonUp")
	row.bg = UI.NewFill(row, 6)
	UI.SetTextureColor(row.bg, c.panelHover, 0)
	row.label = UI.NewText(row, 13, c.text)
	row.label:SetPoint("LEFT", row, "LEFT", 10, 0)
	row.label:SetPoint("RIGHT", row, "RIGHT", -10, 0)
	row:SetScript("OnEnter", function(self)
		if self.header then return end
		UI.SetTextureColor(self.bg, c.panelHover, 0.7)
		if self.reason then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.reason)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		UI.SetTextureColor(self.bg, c.panelHover, 0)
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self)
		if self.header or not self.enabled then return end
		local onClick = self.onClick
		ContextMenu:Hide()
		if onClick then onClick() end
	end)
	ContextMenu.rows[index] = row
	return row
end

local function build()
	catcher = CreateFrame("Frame", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("DIALOG")
	catcher:SetFrameLevel(90)
	catcher:EnableMouse(true)
	catcher:SetScript("OnMouseDown", function() ContextMenu:Hide() end)
	catcher:Hide()

	menu = CreateFrame("Frame", nil, UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetClampedToScreen(true)
	menu:SetWidth(WIDTH)
	menu:Hide()
	local bg = UI.NewFill(menu, 8)
	UI.SetTextureColor(bg, c.bg)
	UI.AddBorder(menu, c.border, 1, 8)
end

-- Opens the menu at the mouse. `title` is an optional caption above the items.
function ContextMenu:Open(items, title)
	if not menu then build() end
	local list = {}
	if title then list[1] = { label = title, header = true } end
	for _, item in ipairs(items) do list[#list + 1] = item end
	if #list == 0 then return end

	local y = PAD
	for i, item in ipairs(list) do
		local row = self.rows[i] or newRow(i)
		local height = item.header and HEADER_H or ROW_H
		row:SetHeight(height)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD, -y)
		row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -PAD, -y)
		y = y + height

		row.header = item.header and true or false
		row.onClick = item.onClick
		row.enabled = item.enabled ~= false
		row.reason = (not row.enabled) and item.reason or nil
		if row.header then
			row.label:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
			row.label:SetText(strupper(item.label))
		else
			local color = item.color or c.text
			local alpha = row.enabled and 1 or 0.45
			row.label:SetTextColor(color[1], color[2], color[3], alpha)
			row.label:SetText(item.label)
		end
		UI.SetTextureColor(row.bg, c.panelHover, 0)
		row:Show()
	end
	for i = #list + 1, #self.rows do self.rows[i]:Hide() end
	menu:SetHeight(y + PAD)

	local x, cursorY = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, cursorY / scale)
	catcher:Show()
	menu:Show()
end

function ContextMenu:Hide()
	if menu then menu:Hide() end
	if catcher then catcher:Hide() end
end

function ContextMenu:IsShown()
	return menu ~= nil and menu:IsShown()
end

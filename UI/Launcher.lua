-- Launcher: the small menu that opens the addon's windows. Entries that do not apply
-- right now are greyed out and say why. Presentation only.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local strupper = string.upper

local WIDTH, PAD = 240, 8
local ROW_H, ICON = 34, 18

local Launcher = {}
ALC.Launcher = Launcher
Launcher.rows = {}

local menu, catcher
local c = UI.color

-- One entry per window. `available` returns true, or false and the reason it is not.
local function session() return ALC.Sessions:GetSession() end

Launcher.entries = {
	{
		icon = "loot", label = L["Loot window"],
		available = function() return true end,
		open = function() ALC.LootWindow:Toggle() end,
	},
	{
		icon = "council", label = L["Voting window"],
		available = function()
			local s = session()
			if not s then return false, L["Needs a running session."] end
			if not s.isCouncil then return false, L["Only the council votes."] end
			return true
		end,
		open = function() ALC.CouncilWindow:Toggle() end,
	},
	{
		icon = "vote", label = L["Response window"],
		available = function()
			if not session() then return false, L["Needs a running session."] end
			return true
		end,
		open = function() ALC.ResponseWindow:Show() end,
	},
	{
		icon = "history", label = L["Award history"],
		available = function() return true end,
		open = function() ALC.CouncilWindow:ToggleHistory() end,
	},
	{
		icon = "settings", label = L["Settings"],
		available = function() return true end,
		open = function() ALC.SettingsWindow:Toggle() end,
	},
}

local function build()
	catcher = CreateFrame("Frame", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("DIALOG")
	catcher:EnableMouse(true)
	catcher:SetScript("OnMouseDown", function() Launcher:Hide() end)
	catcher:Hide()

	menu = CreateFrame("Frame", nil, UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetClampedToScreen(true)
	menu:SetSize(WIDTH, PAD * 2 + #Launcher.entries * ROW_H + 30)
	menu:Hide()

	local bg = menu:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	UI.SetTextureColor(bg, c.bg)
	UI.AddBorder(menu, c.border)

	local title = UI.NewText(menu, 11, c.muted)
	title:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD + 8, -PAD - 6)
	title:SetText(strupper(L["Arbiter Loot Council"]))

	for i, entry in ipairs(Launcher.entries) do
		local row = CreateFrame("Button", nil, menu)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD, -(PAD + 26 + (i - 1) * ROW_H))
		row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -PAD, -(PAD + 26 + (i - 1) * ROW_H))
		row:RegisterForClicks("LeftButtonUp")
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		UI.SetTextureColor(row.bg, c.panelHover, 0)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(ICON, ICON)
		row.icon:SetPoint("LEFT", row, "LEFT", 10, 0)
		row.icon:SetTexture(UI.ICONS .. entry.icon)
		row.label = UI.NewText(row, 13, c.text)
		row.label:SetPoint("LEFT", row.icon, "RIGHT", 12, 0)
		row.label:SetText(entry.label)
		row.entry = entry

		row:SetScript("OnEnter", function(self)
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
			if not self.enabled then return end
			Launcher:Hide()
			self.entry.open()
		end)
		Launcher.rows[i] = row
	end
end

-- Greys out the entries that do not apply right now.
local function refresh()
	for _, row in ipairs(Launcher.rows) do
		local ok, reason = row.entry.available()
		row.enabled = ok and true or false
		row.reason = not ok and reason or nil
		if ok then
			row.icon:SetVertexColor(c.gold[1], c.gold[2], c.gold[3], 1)
			row.label:SetTextColor(c.text[1], c.text[2], c.text[3], 1)
		else
			row.icon:SetVertexColor(c.muted[1], c.muted[2], c.muted[3], 0.6)
			row.label:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 0.7)
		end
	end
end

-- Opens the menu next to `anchor` (the minimap button), or wherever it is when none is given.
function Launcher:Show(anchor)
	if not menu then build() end
	refresh()
	menu:ClearAllPoints()
	if anchor then
		-- Open away from the screen edge the button is near, so the menu always fits.
		local x, y = anchor:GetCenter()
		local left = x ~= nil and x < UIParent:GetWidth() / 2
		local below = y ~= nil and y >= UIParent:GetHeight() / 2
		local side = left and "LEFT" or "RIGHT"
		if below then
			menu:SetPoint("TOP" .. side, anchor, "BOTTOM" .. side, 0, -6)
		else
			menu:SetPoint("BOTTOM" .. side, anchor, "TOP" .. side, 0, 6)
		end
	else
		menu:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
	catcher:Show()
	menu:Show()
end

function Launcher:Hide()
	if menu then menu:Hide() end
	if catcher then catcher:Hide() end
end

function Launcher:IsShown()
	return menu ~= nil and menu:IsShown()
end

function Launcher:Toggle(anchor)
	if self:IsShown() then self:Hide() else self:Show(anchor) end
end

ALC.Commands:Register("menu", function() Launcher:Toggle() end, L["open the window menu"])

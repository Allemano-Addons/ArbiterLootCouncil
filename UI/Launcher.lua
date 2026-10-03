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
		icon = "trade", label = L["Trade queue"],
		available = function() return true end,
		open = function() ALC.CouncilWindow:ToggleTrades() end,
	},
	{
		icon = "addon_check", label = L["Versions"],
		available = function() return true end,
		open = function() ALC.VersionWindow:Toggle() end,
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
	menu.catcher = catcher

	local bg = UI.NewFill(menu, 10)
	UI.SetTextureColor(bg, c.bg)
	UI.AddBorder(menu, c.border, 1, 10)

	local title = UI.NewText(menu, 11, UI.HexColor("45C97E") or c.muted) -- ALC's green, like Soft Reserve's heading is purple
	title:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD + 8, -PAD - 6)
	title:SetText(strupper(L["Arbiter"])) -- the family: Loot Council and the addons built on it
	-- "Session 2/5" in amber while a session is running (filled in by refresh).
	menu.status = UI.NewText(menu, 11, c.gold, "RIGHT")
	menu.status:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -PAD - 8, -PAD - 6)

end

-- A row of the menu: an entry (icon and label) or a heading (the name of the addon an entry belongs to).
local function newRow(i)
	local row = CreateFrame("Button", nil, menu)
	row:RegisterForClicks("LeftButtonUp")
	row.bg = UI.NewFill(row, 6)
	UI.SetTextureColor(row.bg, c.panelHover, 0)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("LEFT", row, "LEFT", 10, 0)
	row.label = UI.NewText(row, 13, c.text)
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 12, 0)
	row:SetScript("OnEnter", function(self)
		if not self.entry then return end
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
		if not self.entry or not self.enabled then return end
		Launcher:Hide()
		self.entry.open()
	end)
	Launcher.rows[i] = row
	return row
end

local HEADING_H = 28

-- The rows of the menu: ALC's own entries, then the entries other addons added, under a heading for each addon.
local function items()
	local list = {}
	for _, entry in ipairs(Launcher.entries) do list[#list + 1] = { entry = entry } end
	local seen = {}
	for _, entry in ipairs(ALC.GetLauncherEntries()) do
		local section = entry.section or ""
		if not seen[section] then
			seen[section] = true
			if section ~= "" then list[#list + 1] = { heading = section, color = UI.HexColor(entry.color) } end
			for _, other in ipairs(ALC.GetLauncherEntries()) do
				if (other.section or "") == section then list[#list + 1] = { entry = other } end
			end
		end
	end
	return list
end

-- Makes a row for every item and the menu as tall as they need.
local function layout()
	local list = items()
	local y = PAD + 26
	for i, item in ipairs(list) do
		local row = Launcher.rows[i] or newRow(i)
		local height = item.heading and HEADING_H or ROW_H
		row:SetHeight(height)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD, -y)
		row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -PAD, -y)
		y = y + height
		row.entry = item.entry
		row.heading = item.heading
		if item.heading then
			row.icon:Hide()
			row.label:ClearAllPoints()
			row.label:SetPoint("LEFT", row, "LEFT", 10, -4)
			local tone = item.color or c.muted
			row.label:SetTextColor(tone[1], tone[2], tone[3], 1)
			row.label:SetText(strupper(item.heading))
			row.enabled, row.reason = false, nil
		else
			row.icon:Show()
			row.icon:SetTexture(UI.ICONS .. item.entry.icon)
			row.label:ClearAllPoints()
			row.label:SetPoint("LEFT", row.icon, "RIGHT", 12, 0)
			row.label:SetText(item.entry.label)
			row.tint = UI.HexColor(item.entry.color)
		end
		row:Show()
	end
	for i = #list + 1, #Launcher.rows do
		Launcher.rows[i].entry, Launcher.rows[i].heading = nil, nil
		Launcher.rows[i]:Hide()
	end
	menu:SetHeight(y + PAD + 4)
end

-- Greys out the entries that do not apply right now.
local function refresh()
	local summary = ALC.Sessions:GetSummary()
	menu.status:SetText(summary.running and strupper(string.format(L["%d of %d open"], summary.open, summary.total)) or "")
	for _, row in ipairs(Launcher.rows) do
		-- (a heading, or a row nobody uses, has no entry and nothing to grey out)
		if row.entry then
			local ok, reason = row.entry.available()
			row.enabled = ok and true or false
			row.reason = not ok and reason or nil
			if ok then
				local tint = row.tint or c.gold
				row.icon:SetVertexColor(tint[1], tint[2], tint[3], 1)
				row.label:SetTextColor(c.text[1], c.text[2], c.text[3], 1)
			else
				row.icon:SetVertexColor(c.muted[1], c.muted[2], c.muted[3], 0.6)
				row.label:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 0.7)
			end
		end
	end
end

-- Opens the menu next to `anchor` (the minimap button), or wherever it is when none is given.
function Launcher:Show(anchor)
	if not menu then build() end
	layout()
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

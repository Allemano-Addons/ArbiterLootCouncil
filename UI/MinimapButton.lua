-- MinimapButton: the square launcher button, styled like the other minimap buttons. Left
-- click opens the window menu, right click opens Settings. Drag it anywhere on the screen
-- with the left mouse button; it stays where you drop it. It can be hidden in Settings
-- or with /alc minimap.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local SIZE = 34
local c = UI.color

local MinimapButton = {}
ALC.MinimapButton = MinimapButton

local button

-- Where the button sits until the player moves it: just left of the minimap.
local function placeDefault()
	button:ClearAllPoints()
	if Minimap then
		button:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -8, 0)
	else
		button:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -40)
	end
end

local function place()
	local position = ALC.Settings:GetButtonPosition()
	if position then
		button:ClearAllPoints()
		button:SetPoint(position.point, UIParent, position.relPoint, position.x, position.y)
	else
		placeDefault()
	end
end

local function showTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText(L["Arbiter Loot Council"])
	GameTooltip:AddLine(L["Left-click: open the window menu"], 0.86, 0.87, 0.90)
	GameTooltip:AddLine(L["Right-click: settings"], 0.86, 0.87, 0.90)
	GameTooltip:AddLine(L["Drag: move this button"], 0.55, 0.58, 0.64)
	GameTooltip:Show()
end

local function build()
	button = CreateFrame("Button", nil, UIParent)
	button:SetSize(SIZE, SIZE)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:SetClampedToScreen(true)
	button:SetMovable(true)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")

	-- A dark square with a thin frame, like the other minimap buttons.
	button.bg = UI.NewFill(button, 8)
	UI.SetTextureColor(button.bg, c.bg)
	button.border = UI.AddBorder(button, c.border, 1, 8)

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", 5, -5)
	button.icon:SetPoint("BOTTOMRIGHT", -5, 5)
	button.icon:SetTexture(UI.LOGO)

	button:SetScript("OnClick", function(self, mouseButton)
		GameTooltip:Hide()
		if mouseButton == "RightButton" then
			ALC.Launcher:Hide()
			ALC.SettingsWindow:Toggle()
		else
			ALC.Launcher:Toggle(self)
		end
	end)
	button:SetScript("OnEnter", function(self)
		self.border:SetColor(c.gold)
		showTooltip(self)
	end)
	button:SetScript("OnLeave", function(self)
		self.border:SetColor(c.border)
		GameTooltip:Hide()
	end)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:StartMoving()
	end)
	button:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ALC.Settings:SetButtonPosition(point, relPoint, x, y)
	end)
	MinimapButton.button = button
end

-- Places the button and shows or hides it according to the setting.
function MinimapButton:Refresh()
	if not button then return end
	place()
	if ALC.Settings:IsMinimapHidden() then button:Hide() else button:Show() end
end

function MinimapButton:Init()
	build()
	self:Refresh()
	ALC.Events.Register(self, "ALC_SETTINGS_CHANGED", function(_, key)
		if key == "minimapHidden" then MinimapButton:Refresh() end
	end)
end

ALC.Commands:Register("minimap", function()
	local hidden = not ALC.Settings:IsMinimapHidden()
	ALC.Settings:SetMinimapHidden(hidden)
	ALC:Print(hidden and L["The minimap button is hidden."] or L["The minimap button is shown."])
end, L["show or hide the minimap button"])

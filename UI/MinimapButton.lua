-- MinimapButton: the square launcher button, styled like the other minimap buttons. Left
-- click opens the window menu, right click opens Settings. Drag it anywhere on the screen
-- with the left mouse button; it stays where you drop it. It can be hidden in Settings
-- or with /alc minimap.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local SIZE = 30
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
	local summary = ALC.Sessions:GetSummary()
	if summary.running then
		GameTooltip:AddLine(string.format(L["Session running: %d of %d items open"], summary.open, summary.total), c.gold[1], c.gold[2], c.gold[3])
	end
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

	-- A small amber dot in the corner while a session is running, so it is not forgotten
	-- when the windows are closed.
	button.dot = CreateFrame("Frame", nil, button)
	button.dot:SetSize(10, 10)
	button.dot:SetPoint("TOPRIGHT", button, "TOPRIGHT", 3, 3)
	button.dot:SetFrameLevel(button:GetFrameLevel() + 3)
	button.dot.fill = UI.NewFill(button.dot, 4)
	UI.SetTextureColor(button.dot.fill, c.gold)
	button.dot:Hide()

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", 2, -2)
	button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	button.icon:SetTexture(UI.MEDIA .. "wow\\mark")

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
		self.border:SetColor(MinimapButton:IsRunning() and c.gold or c.border)
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

function MinimapButton:IsRunning()
	return ALC.Sessions:GetSummary().running
end

-- Places the button and shows or hides it according to the setting; the dot and the amber
-- frame show that a session is running.
function MinimapButton:Refresh()
	if not button then return end
	place()
	local running = self:IsRunning()
	button.dot:SetShown(running)
	button.border:SetColor(running and c.gold or c.border)
	if ALC.Settings:IsMinimapHidden() then button:Hide() else button:Show() end
end

function MinimapButton:Init()
	build()
	self:Refresh()
	ALC.Events.Register(self, "ALC_SETTINGS_CHANGED", function(_, key)
		if key == "minimapHidden" then MinimapButton:Refresh() end
	end)
	local refresh = function() MinimapButton:Refresh() end
	for _, event in ipairs({ "ALC_SESSION_STARTED", "ALC_SESSION_ENDED", "ALC_SESSION_SNAPSHOT", "ALC_SESSION_RESTORED" }) do
		ALC.Events.Register(self, event, refresh)
	end
end

ALC.Commands:Register("minimap", function()
	local hidden = not ALC.Settings:IsMinimapHidden()
	ALC.Settings:SetMinimapHidden(hidden)
	ALC:Print(hidden and L["The minimap button is hidden."] or L["The minimap button is shown."])
end, L["show or hide the minimap button"])

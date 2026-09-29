-- MinimapButton: the round button on the minimap. Left click opens the window menu,
-- right click opens Settings, dragging moves it around the minimap. It can be hidden
-- in Settings or with /alc minimap.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local cos, sin, rad, deg = math.cos, math.sin, math.rad, math.deg
local min, max = math.min, math.max
-- Lua 5.1 (the game) has math.atan2; later versions fold it into math.atan.
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local SIZE = 32
local EDGE = 5 -- how far the button sits outside the minimap edge

local MinimapButton = {}
ALC.MinimapButton = MinimapButton

local button

-- Where a button at `angle` (degrees, 0 = right, 90 = up) sits relative to the minimap
-- centre. Square minimaps (some UI addons) get the button on their edge.
function MinimapButton.OffsetFor(angle, halfWidth, halfHeight, square)
	local w, h = halfWidth + EDGE, halfHeight + EDGE
	local x, y = cos(rad(angle)) * w, sin(rad(angle)) * h
	if square then
		x = max(-w, min(x * 1.4142, w))
		y = max(-h, min(y * 1.4142, h))
	end
	return x, y
end

local function isSquare()
	return GetMinimapShape ~= nil and GetMinimapShape() == "SQUARE"
end

local function place()
	local x, y = MinimapButton.OffsetFor(ALC.Settings:GetMinimapAngle(), Minimap:GetWidth() / 2, Minimap:GetHeight() / 2, isSquare())
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- While dragging, the button follows the mouse around the minimap centre.
local function followCursor()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	ALC.Settings:SetMinimapAngle(deg(atan2(cy / scale - my, cx / scale - mx)))
	place()
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
	button = CreateFrame("Button", nil, Minimap)
	button:SetSize(SIZE, SIZE)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture(UI.MEDIA .. "Logo\\alc_minimap", "ADD")

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexture(UI.MEDIA .. "Logo\\alc_minimap")

	button:SetScript("OnClick", function(self, mouseButton)
		GameTooltip:Hide()
		if mouseButton == "RightButton" then
			ALC.Launcher:Hide()
			ALC.SettingsWindow:Toggle()
		else
			ALC.Launcher:Toggle(self)
		end
	end)
	button:SetScript("OnEnter", showTooltip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", followCursor) -- only while dragging
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	MinimapButton.button = button
end

-- Shows or hides the button according to the setting.
function MinimapButton:Refresh()
	if not button then return end
	place()
	if ALC.Settings:IsMinimapHidden() then button:Hide() else button:Show() end
end

function MinimapButton:Init()
	if not Minimap then return end
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

-- UI widgets: the shared look (dark panels, amber accent) and the small building blocks
-- the windows are made of. No addon logic in here.

local ALC = ALC

local UI = {}
ALC.UI = UI

UI.color = {
	bg = { 0.055, 0.063, 0.078, 0.98 },
	panel = { 0.086, 0.098, 0.122, 1 },
	panelHover = { 0.11, 0.125, 0.155, 1 },
	border = { 0.165, 0.184, 0.22, 1 },
	text = { 0.86, 0.87, 0.90, 1 },
	muted = { 0.55, 0.58, 0.64, 1 },
	gold = { 0.90, 0.66, 0.24, 1 },
	goldTint = { 0.20, 0.15, 0.07, 1 },
	danger = { 0.85, 0.32, 0.30, 1 },
}

-- Textures shipped with the addon (Media/). Paths take no file extension.
UI.MEDIA = "Interface\\AddOns\\ArbiterLootCouncil\\Media\\"
UI.LOGO = UI.MEDIA .. "Logo\\alc_mark_64"
UI.ICONS = UI.MEDIA .. "Icons\\" -- + name, white on transparent: tint with SetVertexColor

-- The ALC mark as a square texture of `size` pixels.
function UI.NewLogo(parent, size)
	local logo = parent:CreateTexture(nil, "ARTWORK")
	logo:SetSize(size, size)
	logo:SetTexture(UI.LOGO)
	return logo
end

-- Item quality colours, indexed by quality id (0 poor ... 7 heirloom).
UI.qualityColor = {
	[0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
	[4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 },
}

function UI.QualityColor(quality)
	return UI.qualityColor[quality] or UI.color.muted
end

-- Class colours by class token, used when the game's RAID_CLASS_COLORS is not there.
local CLASS_FALLBACK = {
	WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 },
	ROGUE = { 1, 0.96, 0.41 }, PRIEST = { 1, 1, 1 }, DEATHKNIGHT = { 0.77, 0.12, 0.23 },
	SHAMAN = { 0, 0.44, 0.87 }, MAGE = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 },
	MONK = { 0, 1, 0.6 }, DRUID = { 1, 0.49, 0.04 },
}

function UI.ClassColor(class)
	local game = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if game then return { game.r, game.g, game.b } end
	return CLASS_FALLBACK[class] or UI.color.text
end

local function unpackColor(c, alpha)
	return c[1], c[2], c[3], alpha or c[4] or 1
end

function UI.SetTextureColor(texture, c, alpha)
	texture:SetColorTexture(unpackColor(c, alpha))
end

-- A 1px (or `size`) border made of four textures. Returns an object with :SetColor(c).
function UI.AddBorder(frame, c, size)
	size = size or 1
	local edges = {}
	local function edge(p1, p2, w, h)
		local t = frame:CreateTexture(nil, "BORDER")
		t:SetPoint(p1, frame, p1, 0, 0)
		t:SetPoint(p2, frame, p2, 0, 0)
		if w then t:SetWidth(w) end
		if h then t:SetHeight(h) end
		edges[#edges + 1] = t
	end
	edge("TOPLEFT", "TOPRIGHT", nil, size)
	edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, size)
	edge("TOPLEFT", "BOTTOMLEFT", size, nil)
	edge("TOPRIGHT", "BOTTOMRIGHT", size, nil)
	local border = {}
	function border:SetColor(color, alpha)
		for _, t in ipairs(edges) do t:SetColorTexture(unpackColor(color, alpha)) end
	end
	border:SetColor(c)
	return border
end

function UI.NewText(parent, size, color, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(STANDARD_TEXT_FONT, size, "")
	fs:SetTextColor(unpackColor(color or UI.color.text))
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

-- A flat button. `button:SetAvailable(false)` greys it out and stops clicks.
function UI.NewButton(parent, width, height, label, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, height)
	button:RegisterForClicks("LeftButtonUp")

	button.bg = button:CreateTexture(nil, "BACKGROUND")
	button.bg:SetAllPoints()
	UI.SetTextureColor(button.bg, UI.color.panel)
	button.border = UI.AddBorder(button, UI.color.border)

	button.label = UI.NewText(button, 13, UI.color.text, "CENTER")
	button.label:SetPoint("CENTER", 0, 0)
	button.label:SetText(label)

	button.available = true
	button.selected = false

	-- The resting look: selected buttons keep the amber frame.
	local function restingLook(self)
		if self.selected then
			UI.SetTextureColor(self.bg, UI.color.goldTint)
			self.border:SetColor(UI.color.gold)
		else
			UI.SetTextureColor(self.bg, UI.color.panel)
			self.border:SetColor(UI.color.border)
		end
	end

	button:SetScript("OnEnter", function(self)
		if self.available then
			UI.SetTextureColor(self.bg, UI.color.panelHover)
			self.border:SetColor(UI.color.gold)
		end
	end)
	button:SetScript("OnLeave", restingLook)
	button:SetScript("OnClick", function(self)
		if self.available and onClick then onClick(self) end
	end)

	function button:SetSelected(selected)
		self.selected = selected and true or false
		restingLook(self)
	end

	function button:SetAvailable(available)
		self.available = available and true or false
		local c = self.available and UI.color.text or UI.color.muted
		self.label:SetTextColor(unpackColor(c, self.available and 1 or 0.6))
	end
	function button:SetLabel(text) self.label:SetText(text) end

	return button
end

-- A thin scrollbar for lists made of a fixed set of rows. The caller anchors it, gives it
-- a height, and calls bar:Update(total, visible, offset) after every change of the list.
-- Dragging the thumb, or clicking the track, calls onScroll(newOffset); the caller
-- changes its offset and updates the bar again. The bar hides itself when everything fits.
function UI.NewScrollBar(parent, onScroll)
	local bar = CreateFrame("Button", nil, parent)
	bar:SetWidth(6)
	bar:EnableMouse(true)
	bar:RegisterForClicks("LeftButtonUp")

	bar.track = bar:CreateTexture(nil, "BACKGROUND")
	bar.track:SetAllPoints()
	UI.SetTextureColor(bar.track, UI.color.panelHover, 0.7)
	bar.thumb = bar:CreateTexture(nil, "ARTWORK")
	UI.SetTextureColor(bar.thumb, UI.color.muted, 0.8)

	bar.total, bar.visible, bar.offset, bar.thumbHeight = 0, 0, 0, 0

	function bar:Update(total, visible, offset)
		self.total, self.visible, self.offset = total, visible, offset
		if total <= visible or visible <= 0 then
			self:Hide()
			return
		end
		self:Show()
		local height = self:GetHeight()
		self.thumbHeight = math.max(20, height * visible / total)
		local travel = height - self.thumbHeight
		local position = travel * offset / (total - visible)
		self.thumb:ClearAllPoints()
		self.thumb:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -position)
		self.thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -position)
		self.thumb:SetHeight(self.thumbHeight)
	end

	-- The thumb is centred on the mouse while the button is down.
	local function follow(self)
		local _, cursorY = GetCursorPosition()
		cursorY = cursorY / self:GetEffectiveScale()
		local travel = self:GetHeight() - self.thumbHeight
		if travel <= 0 then return end
		local ratio = ((self:GetTop() - cursorY) - self.thumbHeight / 2) / travel
		ratio = math.max(0, math.min(1, ratio))
		local newOffset = math.floor(ratio * (self.total - self.visible) + 0.5)
		if newOffset ~= self.offset and onScroll then onScroll(newOffset) end
	end
	bar:SetScript("OnMouseDown", function(self)
		follow(self)
		self:SetScript("OnUpdate", follow)
	end)
	bar:SetScript("OnMouseUp", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	bar.Follow = follow

	return bar
end

-- A checkbox with a label. `onToggle(checked)` runs when the player clicks it;
-- `checkbox:SetChecked(bool)` only changes how it looks.
function UI.NewCheckbox(parent, label, onToggle)
	local box = CreateFrame("Button", nil, parent)
	box:SetSize(320, 24)
	box:RegisterForClicks("LeftButtonUp")

	box.square = CreateFrame("Frame", nil, box)
	box.square:SetSize(18, 18)
	box.square:SetPoint("LEFT", box, "LEFT", 0, 0)
	box.square.bg = box.square:CreateTexture(nil, "BACKGROUND")
	box.square.bg:SetAllPoints()
	UI.SetTextureColor(box.square.bg, UI.color.panel)
	box.square.border = UI.AddBorder(box.square, UI.color.border)
	box.mark = box.square:CreateTexture(nil, "ARTWORK")
	box.mark:SetPoint("TOPLEFT", 4, -4)
	box.mark:SetPoint("BOTTOMRIGHT", -4, 4)
	UI.SetTextureColor(box.mark, UI.color.gold)
	box.mark:Hide()

	box.label = UI.NewText(box, 13, UI.color.text)
	box.label:SetPoint("LEFT", box.square, "RIGHT", 10, 0)
	box.label:SetText(label)

	box.checked = false
	box:SetScript("OnEnter", function(self) self.square.border:SetColor(UI.color.gold) end)
	box:SetScript("OnLeave", function(self) self.square.border:SetColor(UI.color.border) end)
	box:SetScript("OnClick", function(self)
		local checked = not self.checked
		self:SetChecked(checked)
		if onToggle then onToggle(checked) end
	end)

	function box:SetChecked(checked)
		self.checked = checked and true or false
		self.mark:SetShown(self.checked)
	end
	function box:IsChecked() return self.checked end

	return box
end

-- A one-line text field. `onEnter(text)` runs when the player presses Enter.
function UI.NewEditBox(parent, width, height, placeholder, onEnter)
	local edit = CreateFrame("EditBox", nil, parent)
	edit:SetSize(width, height)
	edit:SetFont(STANDARD_TEXT_FONT, 13, "")
	edit:SetTextColor(unpackColor(UI.color.text))
	edit:SetTextInsets(10, 10, 0, 0)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(48)

	edit.bg = edit:CreateTexture(nil, "BACKGROUND")
	edit.bg:SetAllPoints()
	UI.SetTextureColor(edit.bg, UI.color.panel)
	edit.border = UI.AddBorder(edit, UI.color.border)

	edit.placeholder = UI.NewText(edit, 13, UI.color.muted)
	edit.placeholder:SetPoint("LEFT", edit, "LEFT", 10, 0)
	edit.placeholder:SetText(placeholder or "")

	edit:SetScript("OnEditFocusGained", function(self) self.border:SetColor(UI.color.gold) end)
	edit:SetScript("OnEditFocusLost", function(self) self.border:SetColor(UI.color.border) end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	edit:SetScript("OnTextChanged", function(self)
		self.placeholder:SetShown((self:GetText() or "") == "")
	end)
	edit:SetScript("OnEnterPressed", function(self)
		local text = self:GetText() or ""
		self:ClearFocus()
		if onEnter then onEnter(text) end
	end)
	return edit
end

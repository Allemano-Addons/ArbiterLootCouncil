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

UI.LOGO_WHITE = UI.MEDIA .. "Logo\\alc_mark_white_64" -- the same mark in white, for a colour of an addon built on ALC
UI.LOGO_ACCENT = UI.MEDIA .. "Logo\\alc_mark_accent_64" -- only the lower (accent) part of the mark, in white: tint it

-- The colour of "9B7BFF" as { r, g, b }, or nil when it is not six hex digits.
function UI.HexColor(hex)
	if type(hex) ~= "string" or not string.match(hex, "^%x%x%x%x%x%x$") then return nil end
	return {
		tonumber(string.sub(hex, 1, 2), 16) / 255,
		tonumber(string.sub(hex, 3, 4), 16) / 255,
		tonumber(string.sub(hex, 5, 6), 16) / 255,
	}
end

-- What an addon built on ALC called its session (Soft Reserve): its name and colour, or nil for a normal
-- session (or one that did not send them).
function UI.SessionBrand(session)
	if not session or not session.modeName then return nil end
	local color = UI.HexColor(session.modeColor)
	if not color then return nil end
	return session.modeName, color
end

-- Puts the mark of the session's addon on a logo texture: ALC's own mark for a normal session, and for an addon built
-- on ALC the same mark with the green lower part in that addon's colour (the upper part stays white). The coloured
-- part is a second texture, over the all-white mark (see Tools/make_accent.lua).
function UI.ApplyBrand(logo, session)
	local _, color = UI.SessionBrand(session)
	if color then
		logo:SetTexture(UI.LOGO_WHITE)
		logo:SetVertexColor(1, 1, 1, 1)
		if logo.accent then
			logo.accent:SetVertexColor(color[1], color[2], color[3], 1)
			logo.accent:Show()
		end
	else
		logo:SetTexture(UI.LOGO)
		logo:SetVertexColor(1, 1, 1, 1)
		if logo.accent then logo.accent:Hide() end
	end
end

-- The ALC mark as a square texture of `size` pixels.
function UI.NewLogo(parent, size)
	local logo = parent:CreateTexture(nil, "ARTWORK")
	logo:SetSize(size, size)
	logo:SetTexture(UI.LOGO)
	-- the part that another addon's colour replaces (see ApplyBrand); hidden for ALC's own mark
	logo.accent = parent:CreateTexture(nil, "OVERLAY")
	logo.accent:SetAllPoints(logo)
	logo.accent:SetTexture(UI.LOGO_ACCENT)
	logo.accent:Hide()
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

--------------------------------------------------------------------------------
-- Rounded shapes. The game has no rounded rectangles, so the windows are drawn from
-- small white shape textures (Media/Shapes, made by Tools/make_shapes.lua). A shape is cut
-- into nine pieces: four corners that keep their size, four edges and a centre that
-- stretch. Colour is applied as a vertex colour.
--------------------------------------------------------------------------------
UI.SHAPES = UI.MEDIA .. "Shapes\\"
local SHAPE_SIZE = 32
local RADII = { 4, 6, 8, 10 } -- the radii there are textures for

local function nearestRadius(radius)
	local best = RADII[1]
	for _, r in ipairs(RADII) do
		if math.abs(r - radius) < math.abs(best - radius) then best = r end
	end
	return best
end

-- Lays the pieces of one shape texture around `frame`. Returns the list of textures.
local function slice(frame, texturePath, corner, layer, withCentre)
	local pieces = {}
	local lo = corner / SHAPE_SIZE
	local hi = 1 - lo
	local c = corner
	local function piece(u1, u2, v1, v2, anchors, width, height)
		local t = frame:CreateTexture(nil, layer)
		t:SetTexture(texturePath)
		t:SetTexCoord(u1, u2, v1, v2)
		for _, a in ipairs(anchors) do t:SetPoint(a[1], frame, a[2], a[3], a[4]) end
		if width then t:SetWidth(width) end
		if height then t:SetHeight(height) end
		pieces[#pieces + 1] = t
	end
	piece(0, lo, 0, lo, { { "TOPLEFT", "TOPLEFT", 0, 0 } }, c, c)
	piece(hi, 1, 0, lo, { { "TOPRIGHT", "TOPRIGHT", 0, 0 } }, c, c)
	piece(0, lo, hi, 1, { { "BOTTOMLEFT", "BOTTOMLEFT", 0, 0 } }, c, c)
	piece(hi, 1, hi, 1, { { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 } }, c, c)
	piece(lo, hi, 0, lo, { { "TOPLEFT", "TOPLEFT", c, 0 }, { "TOPRIGHT", "TOPRIGHT", -c, 0 } }, nil, c)
	piece(lo, hi, hi, 1, { { "BOTTOMLEFT", "BOTTOMLEFT", c, 0 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", -c, 0 } }, nil, c)
	piece(0, lo, lo, hi, { { "TOPLEFT", "TOPLEFT", 0, -c }, { "BOTTOMLEFT", "BOTTOMLEFT", 0, c } }, c, nil)
	piece(hi, 1, lo, hi, { { "TOPRIGHT", "TOPRIGHT", 0, -c }, { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, c } }, c, nil)
	if withCentre then
		piece(lo, hi, lo, hi, { { "TOPLEFT", "TOPLEFT", c, -c }, { "BOTTOMRIGHT", "BOTTOMRIGHT", -c, c } })
	end
	return pieces
end

-- What NewFill and AddBorder return: colour and visibility for all the pieces at once.
local function shapeObject(pieces)
	local shape = { pieces = pieces }
	function shape:SetColorTexture(r, g, b, a)
		for _, t in ipairs(self.pieces) do t:SetVertexColor(r, g, b, a) end
	end
	function shape:SetColor(color, alpha)
		self:SetColorTexture(unpackColor(color, alpha))
	end
	function shape:SetShown(shown)
		for _, t in ipairs(self.pieces) do t:SetShown(shown) end
	end
	function shape:Show() self:SetShown(true) end
	function shape:Hide() self:SetShown(false) end
	return shape
end

-- A rounded background filling `frame`. Colour it with UI.SetTextureColor(fill, colour).
function UI.NewFill(frame, radius)
	radius = nearestRadius(radius or 6)
	return shapeObject(slice(frame, UI.SHAPES .. "fill_r" .. radius, radius + 2, "BACKGROUND", true))
end

-- A rounded border round `frame`: `thickness` 1 or 2 px. `layer` is BORDER (behind the
-- frame's contents); an icon's frame uses OVERLAY, so the ring also rounds the icon's corners.
function UI.AddBorder(frame, c, thickness, radius, layer)
	thickness = thickness == 2 and 2 or 1
	radius = nearestRadius(radius or 6)
	local border = shapeObject(slice(frame, UI.SHAPES .. "ring_r" .. radius .. "_t" .. thickness, radius + 2, layer or "BORDER", false))
	border:SetColor(c)
	return border
end

--------------------------------------------------------------------------------
-- Text and fonts
--------------------------------------------------------------------------------
local texts = {} -- every text made by NewText or NewEditBox, so a change of font reaches all

function UI.GetFont()
	return UI.fontPath or STANDARD_TEXT_FONT
end

local function applyFont(fs, size)
	local ok = fs:SetFont(UI.GetFont(), size, "")
	if ok == false then fs:SetFont(STANDARD_TEXT_FONT, size, "") end -- a font the game cannot load
end

-- Uses another font everywhere (nil goes back to the game's own). Returns the path in use.
function UI.SetFont(path)
	if type(path) ~= "string" or path == "" then path = nil end
	UI.fontPath = path
	for _, entry in ipairs(texts) do applyFont(entry.fs, entry.size) end
	return UI.GetFont()
end

-- The fonts to choose from: the game's own, and every font LibSharedMedia knows when some
-- addon has loaded it. Each is { name, path }; the first has no path (the game default).
local BUILTIN_FONTS = {
	{ "Friz Quadrata", "Fonts\\FRIZQT__.TTF" },
	{ "Arial Narrow", "Fonts\\ARIALN.TTF" },
	{ "Skurri", "Fonts\\skurri.ttf" },
	{ "Morpheus", "Fonts\\MORPHEUS.ttf" },
}

function UI.GetFontChoices()
	local list = { { name = ALC.L["Game default"] } }
	local seen = {}
	local function add(name, path)
		local key = string.lower(path)
		if seen[key] then return end
		seen[key] = true
		list[#list + 1] = { name = name, path = path }
	end
	for _, font in ipairs(BUILTIN_FONTS) do add(font[1], font[2]) end

	local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
	if lsm then
		local names = {}
		local hash = lsm:HashTable("font")
		for name in pairs(hash) do names[#names + 1] = name end
		table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
		for _, name in ipairs(names) do add(name, hash[name]) end
	end
	return list
end

-- The name to show for a font path.
function UI.FontName(path)
	if not path then return ALC.L["Game default"] end
	for _, font in ipairs(UI.GetFontChoices()) do
		if font.path and string.lower(font.path) == string.lower(path) then return font.name end
	end
	return (string.match(path, "([^\\/]+)$")) or path
end

-- Applies the saved font, and follows changes of the setting.
function UI.Init()
	UI.SetFont(ALC.Settings:GetFont())
	ALC.Events.Register(UI, "ALC_SETTINGS_CHANGED", function(_, key)
		if key == "font" then UI.SetFont(ALC.Settings:GetFont()) end
	end)
end

function UI.NewText(parent, size, color, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	applyFont(fs, size)
	texts[#texts + 1] = { fs = fs, size = size }
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

	button.bg = UI.NewFill(button, 6)
	UI.SetTextureColor(button.bg, UI.color.panel)
	button.border = UI.AddBorder(button, UI.color.border, 1, 6)

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
-- Windows that follow the "Window size" setting (Settings, Everyone).
local scaledFrames = {}

function UI.RegisterScaled(frame)
	scaledFrames[#scaledFrames + 1] = frame
	frame:SetScale(ALC.Settings:GetWindowScale())
end

function UI.ApplyScales()
	local scale = ALC.Settings:GetWindowScale()
	for _, frame in ipairs(scaledFrames) do frame:SetScale(scale) end
end

-- `tooltip` (optional) is a longer explanation shown when the pointer is over the switch.
function UI.NewCheckbox(parent, label, onToggle, tooltip)
	local box = CreateFrame("Button", nil, parent)
	box:SetSize(320, 26)
	box:RegisterForClicks("LeftButtonUp")

	-- A switch: a pill that is amber when on, with a round knob that slides to the right.
	box.square = CreateFrame("Frame", nil, box)
	box.square:SetSize(44, 24)
	box.square:SetPoint("LEFT", box, "LEFT", 0, 0)
	box.square.bg = UI.NewFill(box.square, 10)
	UI.SetTextureColor(box.square.bg, UI.color.border)
	box.square.border = UI.AddBorder(box.square, UI.color.border, 1, 10)
	box.knob = CreateFrame("Frame", nil, box.square)
	box.knob:SetSize(18, 18)
	box.knob:SetFrameLevel(box.square:GetFrameLevel() + 2)
	box.knob.bg = UI.NewFill(box.knob, 8)
	UI.SetTextureColor(box.knob.bg, UI.color.muted)

	box.label = UI.NewText(box, 13, UI.color.text)
	box.label:SetPoint("LEFT", box.square, "RIGHT", 12, 0)
	box.label:SetText(label)

	box.checked = false
	box:SetScript("OnEnter", function(self)
		self.square.border:SetColor(UI.color.gold)
		if tooltip and GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(label)
			GameTooltip:AddLine(tooltip, UI.color.muted[1], UI.color.muted[2], UI.color.muted[3], true)
			GameTooltip:Show()
		end
	end)
	box:SetScript("OnLeave", function(self)
		self.square.border:SetColor(UI.color.border)
		if tooltip and GameTooltip then GameTooltip:Hide() end
	end)
	box:SetScript("OnClick", function(self)
		local checked = not self.checked
		self:SetChecked(checked)
		if onToggle then onToggle(checked) end
	end)

	function box:SetChecked(checked)
		self.checked = checked and true or false
		self.knob:ClearAllPoints()
		if self.checked then
			self.knob:SetPoint("RIGHT", self.square, "RIGHT", -3, 0)
			UI.SetTextureColor(self.square.bg, UI.color.gold)
			UI.SetTextureColor(self.knob.bg, UI.color.text)
		else
			self.knob:SetPoint("LEFT", self.square, "LEFT", 3, 0)
			UI.SetTextureColor(self.square.bg, UI.color.border)
			UI.SetTextureColor(self.knob.bg, UI.color.muted)
		end
	end
	function box:IsChecked() return self.checked end

	box:SetChecked(false)
	return box
end

-- A read-only block of text in a scrolling box, for text the player copies (Ctrl+C): the text
-- is selected when the box is clicked. Returns the scroll frame; `block.edit` is the EditBox.
function UI.NewTextBlock(parent, width, height)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	scroll:SetSize(width, height)
	scroll.bg = UI.NewFill(scroll, 6)
	UI.SetTextureColor(scroll.bg, UI.color.panel)
	scroll.border = UI.AddBorder(scroll, UI.color.border, 1, 6)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = math.max(0, (self.edit:GetHeight() or 0) - self:GetHeight())
		local target = math.max(0, math.min(maxScroll, (self:GetVerticalScroll() or 0) - delta * 40))
		self:SetVerticalScroll(target)
	end)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(0)
	edit:SetWidth(width - 20)
	applyFont(edit, 12)
	texts[#texts + 1] = { fs = edit, size = 12 }
	edit:SetTextColor(unpackColor(UI.color.text))
	edit:SetTextInsets(8, 8, 6, 6)
	scroll:SetScrollChild(edit)
	scroll.edit = edit
	-- Read only: what is typed is undone. Clicking selects everything, ready for Ctrl+C.
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and scroll.fixed and self:GetText() ~= scroll.fixed then self:SetText(scroll.fixed) end
	end)
	edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	function scroll:SetContent(text)
		self.fixed = text
		self.edit:SetText(text)
		self:SetVerticalScroll(0)
	end
	return scroll
end

-- A one-line text field. `onEnter(text)` runs when the player presses Enter.
function UI.NewEditBox(parent, width, height, placeholder, onEnter)
	local edit = CreateFrame("EditBox", nil, parent)
	edit:SetSize(width, height)
	applyFont(edit, 13)
	texts[#texts + 1] = { fs = edit, size = 13 }
	edit:SetTextColor(unpackColor(UI.color.text))
	edit:SetTextInsets(10, 10, 0, 0)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(48)

	edit.bg = UI.NewFill(edit, 6)
	UI.SetTextureColor(edit.bg, UI.color.panel)
	edit.border = UI.AddBorder(edit, UI.color.border, 1, 6)

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

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

-- Item quality colours, indexed by quality id (0 poor ... 7 heirloom).
UI.qualityColor = {
	[0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
	[4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 },
}

function UI.QualityColor(quality)
	return UI.qualityColor[quality] or UI.color.muted
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

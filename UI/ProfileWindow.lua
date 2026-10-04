-- ProfileWindow: the window for sharing the loot master's settings. "Copy my settings" shows the text to copy;
-- "Import settings" takes a pasted text, shows what it would change, and applies it only when the player says so.
-- Presentation only: the work is done by ALC.Profile.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local strupper = string.upper

local ProfileWindow = {}
ALC.ProfileWindow = ProfileWindow

local c = UI.color
local WIDTH, PAD = 560, 20
local SHOWN_CHANGES = 12 -- lines of changes shown at most
local frame
local pending -- the parsed profile waiting for Apply

local function build()
	local f = CreateFrame("Frame", nil, UIParent)
	UI.RegisterScaled(f)
	f:SetSize(WIDTH, 420)
	f:SetFrameStrata("DIALOG")
	f:SetFrameLevel(60)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	f:Hide()

	local bg = UI.NewFill(f, 10)
	UI.SetTextureColor(bg, c.bg)
	UI.AddBorder(f, c.border, 1, 10)

	f.logo = UI.NewLogo(f, 26)
	f.logo:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
	f.title = UI.NewText(f, 14, c.text)
	f.title:SetPoint("LEFT", f.logo, "RIGHT", 10, 0)

	local close = CreateFrame("Button", nil, f)
	close:SetSize(30, 30)
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -12)
	close.text = UI.NewText(close, 30, c.muted, "CENTER")
	close.text:SetPoint("CENTER", 0, 0)
	close.text:SetText("\195\151")
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(c.text[1], c.text[2], c.text[3], 1) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1) end)
	close:SetScript("OnClick", function() f:Hide() end)

	f.hint = UI.NewText(f, 12, c.muted)
	f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(PAD + 40))
	f.hint:SetWidth(WIDTH - 2 * PAD)
	f.hint:SetWordWrap(true)
	f.hint:SetJustifyV("TOP")

	f.block = UI.NewTextBlock(f, WIDTH - 2 * PAD, 96)
	f.block:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(PAD + 116))

	f.status = UI.NewText(f, 12, c.muted)
	f.status:SetPoint("TOPLEFT", f.block, "BOTTOMLEFT", 0, -12)
	f.status:SetWidth(WIDTH - 2 * PAD)
	f.status:SetWordWrap(true)
	f.status:SetJustifyV("TOP")

	f.changes = UI.NewText(f, 12, c.text)
	f.changes:SetPoint("TOPLEFT", f.status, "BOTTOMLEFT", 0, -8)
	f.changes:SetWidth(WIDTH - 2 * PAD)
	f.changes:SetWordWrap(true)
	f.changes:SetJustifyV("TOP")

	f.apply = UI.NewButton(f, 130, 34, L["Apply"], function() ProfileWindow:Apply() end)
	f.apply:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
	f.apply:SetSelected(true)
	f.close = UI.NewButton(f, 110, 34, L["Close"], function() f:Hide() end)
	f.close:SetPoint("RIGHT", f.apply, "LEFT", -8, 0)

	-- A pasted text is read as it arrives
	f.block.edit:SetScript("OnTextChanged", function(self)
		if f.mode == "import" then ProfileWindow:Read(self:GetText()) end
	end)
	return f
end

local function ensure()
	if not frame then frame = build() end
	return frame
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
function ProfileWindow:ShowExport()
	local f = ensure()
	f.mode = "export"
	pending = nil
	f.title:SetText(strupper(L["Share my settings"]))
	f.hint:SetText(L["Click in the box, press Ctrl+A then Ctrl+C, and send the text to the other loot master (Discord, a whisper). They paste it under Settings > Session > Import settings. It has the council, the threshold, the answer buttons, the timer and the other loot master settings, not your windows or your font."])
	f.block.fixed = nil
	f.block:SetContent(ALC.Profile:Export())
	f.status:SetText("")
	f.changes:SetText("")
	f.apply:Hide()
	f:SetHeight(340)
	f:Show()
	f.block.edit:SetFocus()
	f.block.edit:HighlightText()
end

--------------------------------------------------------------------------------
-- Import
--------------------------------------------------------------------------------
function ProfileWindow:ShowImport()
	local f = ensure()
	f.mode = "import"
	pending = nil
	f.title:SetText(strupper(L["Import settings"]))
	f.hint:SetText(L["Paste the text from the other loot master here (Ctrl+V). You will see what it would change before anything is changed, and Undo puts your old settings back."])
	f.block.fixed = nil -- the box is for typing and pasting here
	f.block.edit:SetText("")
	f.status:SetText("")
	f.changes:SetText("")
	f.apply:Show()
	f.apply:SetAvailable(false)
	f:SetHeight(450)
	f:Show()
	f.block.edit:SetFocus()
end

-- Reads what was pasted and shows what it would change.
function ProfileWindow:Read(text)
	local f = frame
	pending = nil
	f.apply:SetAvailable(false)
	if not text or text:match("^%s*$") then
		f.status:SetText("")
		f.changes:SetText("")
		return
	end
	local profile, why = ALC.Profile:Parse(text)
	if not profile then
		f.status:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1)
		f.status:SetText(why)
		f.changes:SetText("")
		return
	end
	local changes = ALC.Profile:Changes(profile)
	local from = profile.by and string.format(L["From %s"], profile.by) or L["From someone"]
	if profile.ver then from = from .. " (" .. profile.ver .. ")" end
	if #changes == 0 then
		f.status:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
		f.status:SetText(from .. ". " .. L["Nothing would change: you already have these settings."])
		f.changes:SetText("")
		return
	end
	f.status:SetTextColor(c.text[1], c.text[2], c.text[3], 1)
	f.status:SetText(from .. ". " .. string.format(L["%d settings would change:"], #changes))
	local lines = {}
	for i = 1, math.min(#changes, SHOWN_CHANGES) do
		local ch = changes[i]
		lines[#lines + 1] = string.format("|cff%s%s|r  %s  |cff%s>|r  %s", "8a929c", ch.label, ch.from, "e6a93c", ch.to)
	end
	if #changes > SHOWN_CHANGES then lines[#lines + 1] = string.format(L["... and %d more"], #changes - SHOWN_CHANGES) end
	f.changes:SetText(table.concat(lines, "\n"))
	pending = profile
	f.apply:SetAvailable(true)
end

function ProfileWindow:Apply()
	if not pending then return end
	local count = ALC.Profile:Apply(pending)
	pending = nil
	ALC:Print(L["%d settings imported. Undo: Settings > Session > Undo the last import (or /alc profile undo)."], count)
	if frame then frame:Hide() end
end

function ProfileWindow:IsShown() return frame ~= nil and frame:IsShown() end
function ProfileWindow:GetFrame() return frame end

-- ResponseWindow: the window every player gets when a session starts: the item and
-- five buttons. Presentation only; answers go through Responses.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local strupper = string.upper

local WIDTH, PAD = 400, 16
local HEADER_H = 52
local ICON = 52
local BUTTON_H, GAP = 44, 6
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local ResponseWindow = {}
ALC.ResponseWindow = ResponseWindow
ResponseWindow.buttons = {}

local frame
local c = UI.color
local feedback -- an error from the last click, shown until the next refresh with a response

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------
local function savePosition()
	local point, _, relPoint, x, y = frame:GetPoint()
	ALC.Settings:SetWindowPosition("response", point, relPoint, x, y)
end

local function restorePosition()
	frame:ClearAllPoints()
	local pos = ALC.Settings:GetWindowPosition("response")
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	end
end

local function build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(WIDTH, 270)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:Hide()

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	UI.SetTextureColor(bg, c.bg)
	UI.AddBorder(frame, c.border)

	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	header:SetHeight(HEADER_H)
	frame.header = header
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() frame:StartMoving() end)
	header:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		savePosition()
	end)

	local logo = UI.NewLogo(header, 28)
	logo:SetPoint("LEFT", header, "LEFT", PAD, 0)
	frame.logo = logo
	local title = UI.NewText(header, 15, c.text)
	title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
	title:SetText(strupper(L["Loot response"]))

	local close = CreateFrame("Button", nil, header)
	close:SetSize(28, 28)
	close:SetPoint("RIGHT", header, "RIGHT", -12, 0)
	close.text = UI.NewText(close, 22, c.muted, "CENTER")
	close.text:SetPoint("CENTER", 0, 0)
	close.text:SetText("\195\151")
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(c.text[1], c.text[2], c.text[3], 1) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1) end)
	close:SetScript("OnClick", function() ResponseWindow:Hide() end)

	local divider = frame:CreateTexture(nil, "BORDER")
	divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -HEADER_H)
	divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -HEADER_H)
	divider:SetHeight(1)
	UI.SetTextureColor(divider, c.border)

	-- The item.
	local itemBox = CreateFrame("Frame", nil, frame)
	itemBox:SetSize(ICON, ICON)
	itemBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER_H + 18))
	itemBox:EnableMouse(true)
	frame.iconBorder = UI.AddBorder(itemBox, c.border, 2)
	frame.icon = itemBox:CreateTexture(nil, "ARTWORK")
	frame.icon:SetPoint("TOPLEFT", 2, -2)
	frame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	itemBox:SetScript("OnEnter", function(self)
		local session = ALC.Sessions:GetSession()
		if not session then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(session.itemString)
		GameTooltip:Show()
	end)
	itemBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

	frame.name = UI.NewText(frame, 16, c.text)
	frame.name:SetPoint("TOPLEFT", itemBox, "TOPRIGHT", 14, -4)
	frame.name:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
	frame.sub = UI.NewText(frame, 11, c.muted)
	frame.sub:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -5)
	frame.sub:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
	frame.lm = UI.NewText(frame, 11, c.muted)
	frame.lm:SetPoint("BOTTOMLEFT", itemBox, "BOTTOMRIGHT", 14, 2)
	frame.lm:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)

	-- The five answers.
	local prompt = UI.NewText(frame, 11, c.muted)
	prompt:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER_H + 18 + ICON + 20))
	prompt:SetText(strupper(L["Choose your response"]))

	local list = ALC.Responses.LIST
	local width = math.floor((WIDTH - 2 * PAD - (#list - 1) * GAP) / #list)
	for i, response in ipairs(list) do
		local button = UI.NewButton(frame, width, BUTTON_H, response.label, function()
			local ok, message = ALC.Responses:Send(response.id)
			feedback = not ok and message or nil
			ResponseWindow:Refresh()
		end)
		button:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (i - 1) * (width + GAP), -(HEADER_H + 18 + ICON + 40))
		button.label:SetTextColor(response.color[1], response.color[2], response.color[3], 1)
		button.responseId = response.id
		ResponseWindow.buttons[i] = button
	end

	frame.status = UI.NewText(frame, 12, c.muted)
	frame.status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 16)
	frame.status:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
	frame.status:SetWordWrap(true) -- the longer messages take two lines
	frame.status:SetJustifyV("BOTTOM")

	frame:SetScript("OnShow", function() ResponseWindow:Refresh() end)
	restorePosition()
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------
function ResponseWindow:Refresh()
	if not frame or not frame:IsShown() then return end
	local session = ALC.Sessions:GetSession()
	if not session then
		self:Hide()
		return
	end

	local display = ALC.LootDetection:GetItemDisplay({ itemString = session.itemString, itemID = session.itemID })
	frame.icon:SetTexture(display.icon or UNKNOWN_ICON)
	local qc = UI.QualityColor(display.quality)
	frame.iconBorder:SetColor(qc)
	frame.name:SetTextColor(qc[1], qc[2], qc[3], 1)
	frame.name:SetText(display.name or L["Loading..."])
	frame.sub:SetText(display.subtitle)
	frame.lm:SetText(L["Loot master"] .. ": " .. session.lm)

	local mine = ALC.Responses:GetMyResponse()
	for _, button in ipairs(self.buttons) do
		button:SetSelected(button.responseId == mine)
	end

	if feedback then
		frame.status:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1)
		frame.status:SetText(feedback)
	elseif mine then
		frame.status:SetTextColor(c.gold[1], c.gold[2], c.gold[3], 1)
		frame.status:SetText(L["Your response: %s. You can change it until the session ends."]:format(ALC.Responses:GetLabel(mine)))
	else
		frame.status:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
		frame.status:SetText(L["Pick one. The council sees it right away."])
	end
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------
-- Whether the window is open is remembered, so it is as you left it after a /reload.
function ResponseWindow:Show()
	if not ALC.Sessions:IsActive() then
		ALC:Print(L["There is no active session."])
		return
	end
	if not frame then build() end
	feedback = nil
	frame:Show()
	ALC.Settings:SetWindowShown("response", true)
	self:Refresh()
end

function ResponseWindow:Hide()
	if frame then frame:Hide() end
	ALC.Settings:SetWindowShown("response", false)
end

-- After a reload the session is back: the window returns if it was open, and also if
-- there is still something to answer.
local function reopen(answered)
	if ALC.Settings:GetWindowShown("response") or not answered then
		ResponseWindow:Show()
	else
		ResponseWindow:Refresh()
	end
end

function ResponseWindow:IsShown()
	return frame ~= nil and frame:IsShown()
end

function ResponseWindow:Init()
	local register = ALC.Events.Register
	local refresh = function() ResponseWindow:Refresh() end
	register(self, "ALC_RESPONSES_CHANGED", refresh)
	register(self, "ALC_LOOT_CHANGED", refresh)
	register(self, "ALC_SESSION_STARTED", function(_, _, restored)
		if not restored then ResponseWindow:Show() end
	end)
	register(self, "ALC_SESSION_SNAPSHOT", function(_, p)
		reopen(p.yourResponse ~= nil)
	end)
	-- The loot master's own session came back; our answer is in the restored list.
	register(self, "ALC_SESSION_RESTORED", function()
		reopen(ALC.Candidates:Get(ALC:PlayerName()) ~= nil)
	end)
	register(self, "ALC_SESSION_ENDED", function() ResponseWindow:Hide() end)
end

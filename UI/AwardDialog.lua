-- AwardDialog: "Award X to Y?" before the loot master hands an item out. Presentation
-- only: the award itself is Awards:Award.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local strupper = string.upper

local WIDTH, HEIGHT, PAD = 440, 236, 20
local ICON = 44
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local AwardDialog = {}
ALC.AwardDialog = AwardDialog

local frame
local c = UI.color

local function build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	frame:Hide()

	local bg = UI.NewFill(frame, 10)
	UI.SetTextureColor(bg, c.bg)
	UI.AddBorder(frame, c.gold, 1, 10)

	frame.logo = UI.NewLogo(frame, 26)
	frame.logo:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
	local title = UI.NewText(frame, 14, c.text)
	title:SetPoint("LEFT", frame.logo, "RIGHT", 10, 0)
	title:SetText(strupper(L["Award item"]))

	local itemBox = CreateFrame("Frame", nil, frame)
	itemBox:SetSize(ICON, ICON)
	itemBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(PAD + 46))
	frame.iconBorder = UI.AddBorder(itemBox, c.border, 2, 8, "OVERLAY")
	frame.icon = itemBox:CreateTexture(nil, "ARTWORK")
	frame.icon:SetPoint("TOPLEFT", 2, -2)
	frame.icon:SetPoint("BOTTOMRIGHT", -2, 2)

	frame.item = UI.NewText(frame, 16, c.text)
	frame.item:SetPoint("TOPLEFT", itemBox, "TOPRIGHT", 14, -2)
	frame.item:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
	frame.winner = UI.NewText(frame, 14, c.text)
	frame.winner:SetPoint("BOTTOMLEFT", itemBox, "BOTTOMRIGHT", 14, 2)
	frame.winner:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)

	frame.details = UI.NewText(frame, 12, c.muted)
	frame.details:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(PAD + 46 + ICON + 14))
	frame.details:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
	frame.note = UI.NewText(frame, 12, c.gold)
	frame.note:SetPoint("TOPLEFT", frame.details, "BOTTOMLEFT", 0, -8)
	frame.note:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
	frame.note:SetWordWrap(true)
	frame.note:SetJustifyV("TOP")

	frame.confirm = UI.NewButton(frame, 130, 38, L["Award"], function() AwardDialog:Confirm() end)
	frame.confirm:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
	frame.confirm:SetSelected(true)
	frame.confirm.label:SetTextColor(c.gold[1], c.gold[2], c.gold[3], 1)
	frame.cancel = UI.NewButton(frame, 110, 38, L["Cancel"], function() AwardDialog:Hide() end)
	frame.cancel:SetPoint("RIGHT", frame.confirm, "LEFT", -10, 0)
	AwardDialog.frame = frame
end

-- Asks whether to award an item of the running session (the first when none is named)
-- to a candidate.
function AwardDialog:Ask(name, item)
	item = item or 1
	local session = ALC.Sessions:GetSession()
	if not session then
		ALC:Print(L["There is no active session."])
		return
	end
	if not session.isLM then
		ALC:Print(L["Only the loot master can award items."])
		return
	end
	local target = ALC.Sessions:GetItem(item)
	if not target then
		ALC:Print(L["That item is not in the session."])
		return
	end
	if target.winner then
		ALC:Print(L["That item has already been awarded."])
		return
	end
	local entry = ALC.Candidates:Get(name, item)
	if not entry then
		ALC:Print(L["That player has not answered."])
		return
	end

	if not frame then build() end
	self.candidate = entry.name
	self.item = item

	local display = ALC.LootDetection:GetItemDisplay({ itemString = target.itemString, itemID = target.itemID })
	frame.icon:SetTexture(display.icon or UNKNOWN_ICON)
	local qc = UI.QualityColor(display.quality)
	frame.iconBorder:SetColor(qc)
	frame.item:SetTextColor(qc[1], qc[2], qc[3], 1)
	frame.item:SetText(display.name or L["Loading..."])

	local cc = UI.ClassColor(entry.class)
	frame.winner:SetTextColor(cc[1], cc[2], cc[3], 1)
	frame.winner:SetText(L["to"] .. " " .. entry.name)

	local votes = ALC.Voting:GetVotes(entry.name, item)
	frame.details:SetText(string.format("%s: %s  \194\183  %s: %d", L["Response"], ALC.Responses:GetLabel(entry.response), L["Votes"], votes))
	frame.note:SetText(ALC.Awards:CanGiveNow(entry.name, item)
		and L["The item is handed out from the open loot window."]
		or L["The loot window is not open for this item: it will be marked Awaiting trade and you trade it yourself."])
	frame:Show()
end

function AwardDialog:Confirm()
	local name, item = self.candidate, self.item
	self:Hide()
	if not name then return end
	local ok, message = ALC.Awards:Award(name, item)
	if not ok and message then ALC:Print(message) end
end

function AwardDialog:Hide()
	if frame then frame:Hide() end
	self.candidate, self.item = nil, nil
end

function AwardDialog:IsShown()
	return frame ~= nil and frame:IsShown()
end

function AwardDialog:Init()
	-- The question makes no sense once the session is over, or the item is awarded.
	ALC.Events.Register(self, "ALC_SESSION_ENDED", function() AwardDialog:Hide() end)
	ALC.Events.Register(self, "ALC_SESSION_ITEM_AWARDED", function(_, item)
		if AwardDialog.item == item then AwardDialog:Hide() end
	end)
end

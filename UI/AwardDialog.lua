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
	UI.RegisterScaled(frame)
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
-- `disenchant` is true for the disenchanter, or the text "bank" for the guild bank.
function AwardDialog:Ask(name, item, disenchant)
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
	local entry
	if disenchant then
		local message
		if ALC.Awards.SpecialKind(disenchant) == "bank" then
			entry, message = ALC.Awards:GetBankEntry()
		else
			entry, message = ALC.Awards:GetDisenchantEntry()
		end
		if not entry then
			ALC:Print(message)
			return
		end
	else
		entry = ALC.Candidates:Get(name, item)
		if not entry then
			ALC:Print(L["That player has not answered."])
			return
		end
	end

	if not frame then build() end
	self.candidate = entry.name
	self.item = item
	self.disenchant = disenchant and (ALC.Awards.SpecialKind(disenchant) == "bank" and "bank" or true) or false

	local display = ALC.LootDetection:GetItemDisplay({ itemString = target.itemString, itemID = target.itemID })
	frame.icon:SetTexture(display.icon or UNKNOWN_ICON)
	local qc = UI.QualityColor(display.quality)
	frame.iconBorder:SetColor(qc)
	frame.item:SetTextColor(qc[1], qc[2], qc[3], 1)
	frame.item:SetText(display.name or L["Loading..."])

	local cc = UI.ClassColor(entry.class)
	frame.winner:SetTextColor(cc[1], cc[2], cc[3], 1)
	frame.winner:SetText(L["to"] .. " " .. entry.name)

	if disenchant then
		frame.details:SetText(ALC.Awards.SpecialKind(disenchant) == "bank" and L["Guild bank: the item goes to the guild bank character."]
			or L["Disenchant: the item goes to the disenchanter."])
	else
		local votes = ALC.Voting:GetVotes(entry.name, item)
		frame.details:SetText(string.format("%s: %s  \194\183  %s: %d", L["Response"], ALC.Responses:GetLabel(entry.response), L["Votes"], votes))
	end
	frame.note:SetText(ALC.Awards:CanGiveNow(entry.name, item)
		and L["The item is handed out from the open loot window."]
		or L["The loot window is not open for this item: it will be marked Awaiting trade and you trade it yourself."])
	frame:Show()
end

--------------------------------------------------------------------------------
-- Award many: one question for a whole list
--------------------------------------------------------------------------------
local MANY_WIDTH, MANY_ROW, MANY_MAX = 520, 28, 12
local manyFrame
local manyList

local function buildMany()
	manyFrame = CreateFrame("Frame", nil, UIParent)
	UI.RegisterScaled(manyFrame)
	manyFrame:SetWidth(MANY_WIDTH)
	manyFrame:SetFrameStrata("DIALOG")
	manyFrame:SetClampedToScreen(true)
	manyFrame:EnableMouse(true)
	manyFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	manyFrame:Hide()
	local bg = UI.NewFill(manyFrame, 10)
	UI.SetTextureColor(bg, c.bg)
	UI.AddBorder(manyFrame, c.gold, 1, 10)

	manyFrame.logo = UI.NewLogo(manyFrame, 26)
	manyFrame.logo:SetPoint("TOPLEFT", manyFrame, "TOPLEFT", PAD, -PAD)
	manyFrame.title = UI.NewText(manyFrame, 14, c.text)
	manyFrame.title:SetPoint("LEFT", manyFrame.logo, "RIGHT", 10, 0)

	manyFrame.rows = {}
	for i = 1, MANY_MAX do
		local row = CreateFrame("Frame", nil, manyFrame)
		row:SetHeight(MANY_ROW)
		row:SetPoint("TOPLEFT", manyFrame, "TOPLEFT", PAD, -(PAD + 44 + (i - 1) * MANY_ROW))
		row:SetPoint("TOPRIGHT", manyFrame, "TOPRIGHT", -PAD, -(PAD + 44 + (i - 1) * MANY_ROW))
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(22, 22)
		row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.item = UI.NewText(row, 13, c.text)
		row.item:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
		row.item:SetWidth(210)
		row.winner = UI.NewText(row, 13, c.text)
		row.winner:SetPoint("LEFT", row, "LEFT", 250, 0)
		row.winner:SetWidth(110)
		row.note = UI.NewText(row, 11, c.muted)
		row.note:SetPoint("LEFT", row, "LEFT", 366, 0)
		row.note:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		manyFrame.rows[i] = row
	end
	manyFrame.more = UI.NewText(manyFrame, 12, c.muted)
	manyFrame.note = UI.NewText(manyFrame, 12, c.gold)
	manyFrame.note:SetWordWrap(true)
	manyFrame.note:SetJustifyV("TOP")

	manyFrame.confirm = UI.NewButton(manyFrame, 150, 38, "", function() AwardDialog:ConfirmMany() end)
	manyFrame.confirm:SetPoint("BOTTOMRIGHT", manyFrame, "BOTTOMRIGHT", -PAD, PAD)
	manyFrame.confirm:SetSelected(true)
	manyFrame.confirm.label:SetTextColor(c.gold[1], c.gold[2], c.gold[3], 1)
	manyFrame.cancel = UI.NewButton(manyFrame, 110, 38, L["Cancel"], function() AwardDialog:HideMany() end)
	manyFrame.cancel:SetPoint("RIGHT", manyFrame.confirm, "LEFT", -10, 0)
	AwardDialog.manyFrame = manyFrame
end

-- Asks whether to award a list of items at once: { { item = 2, name = "Veyra Moo", note = "SR, roll 87" },
-- { item = 3, disenchant = true } ... }. Nothing is awarded until the loot master confirms. Returns true, or false
-- and a message (also printed).
function AwardDialog:AskMany(list)
	local ok, message = ALC.Awards:CheckMany(list)
	if not ok then
		ALC:Print(message)
		return false, message
	end
	if not manyFrame then buildMany() end
	manyList = {}
	for i, entry in ipairs(list) do
		manyList[i] = { item = entry.item, name = entry.name, note = entry.note,
			disenchant = ALC.Awards.SpecialKind(entry.disenchant) == "bank" and "bank" or (entry.disenchant and true or false) }
	end
	local session = ALC.Sessions:GetSession()
	manyFrame.title:SetText(strupper(string.format(L["Award %d items"], #manyList)))
	for i, row in ipairs(manyFrame.rows) do
		local entry = manyList[i]
		if entry then
			local target = session.items[entry.item]
			local display = ALC.LootDetection:GetItemDisplay({ itemString = target.itemString, itemID = target.itemID })
			row.icon:SetTexture(display.icon or UNKNOWN_ICON)
			local qc = UI.QualityColor(display.quality)
			row.item:SetTextColor(qc[1], qc[2], qc[3], 1)
			row.item:SetText(display.name or L["Loading..."])
			if entry.disenchant then
				row.winner:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
				row.winner:SetText(ALC.Awards.SpecialKind(entry.disenchant) == "bank" and L["Guild bank"] or L["Disenchant"])
			else
				local candidate = ALC.Candidates:Get(entry.name, entry.item)
				local cc = UI.ClassColor(candidate.class)
				row.winner:SetTextColor(cc[1], cc[2], cc[3], 1)
				row.winner:SetText(candidate.name)
			end
			row.note:SetText(type(entry.note) == "string" and entry.note or "")
			row:Show()
		else
			row:Hide()
		end
	end
	local shown = math.min(#manyList, MANY_MAX)
	local y = PAD + 44 + shown * MANY_ROW + 8
	manyFrame.more:ClearAllPoints()
	manyFrame.more:SetPoint("TOPLEFT", manyFrame, "TOPLEFT", PAD, -y)
	manyFrame.more:SetText(#manyList > MANY_MAX and string.format(L["... and %d more"], #manyList - MANY_MAX) or "")
	if #manyList > MANY_MAX then y = y + 18 end
	manyFrame.note:ClearAllPoints()
	manyFrame.note:SetPoint("TOPLEFT", manyFrame, "TOPLEFT", PAD, -y)
	manyFrame.note:SetPoint("RIGHT", manyFrame, "RIGHT", -PAD, 0)
	manyFrame.note:SetText(L["Items are handed out from the open loot window when it is open; the others are marked Awaiting trade."])
	manyFrame.confirm:SetLabel(string.format(L["Award all (%d)"], #manyList))
	manyFrame:SetHeight(y + 34 + 38 + PAD)
	manyFrame:Show()
	return true
end

function AwardDialog:ConfirmMany()
	local list = manyList
	self:HideMany()
	if not list then return end
	local ok, message = ALC.Awards:AwardMany(list)
	if not ok and message then ALC:Print(message) end
end

function AwardDialog:HideMany()
	if manyFrame then manyFrame:Hide() end
	manyList = nil
end

function AwardDialog:IsManyShown()
	return manyFrame ~= nil and manyFrame:IsShown()
end

function AwardDialog:Confirm()
	local name, item, disenchant = self.candidate, self.item, self.disenchant
	self:Hide()
	if not name then return end
	local ok, message = ALC.Awards:Award(name, item, disenchant)
	if not ok and message then ALC:Print(message) end
end

function AwardDialog:Hide()
	if frame then frame:Hide() end
	self.candidate, self.item, self.disenchant = nil, nil, nil
end

-- Asks whether to give an item of the running session to the disenchanter.
function AwardDialog:AskDisenchant(item)
	self:Ask(nil, item, true)
end

-- The same for the guild bank character.
function AwardDialog:AskBank(item)
	self:Ask(nil, item, "bank")
end

function AwardDialog:IsShown()
	return frame ~= nil and frame:IsShown()
end

function AwardDialog:Init()
	-- The question makes no sense once the session is over, or the item is awarded.
	ALC.Events.Register(self, "ALC_SESSION_ENDED", function() AwardDialog:Hide() AwardDialog:HideMany() end)
	ALC.Events.Register(self, "ALC_SESSION_ITEM_AWARDED", function(_, item)
		if AwardDialog.item == item then AwardDialog:Hide() end
	end)
end

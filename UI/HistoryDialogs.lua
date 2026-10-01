-- HistoryDialogs: the export window (the history as text to copy) and the "clear the
-- history?" question. Presentation only: the work is done by Awards.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local strupper = string.upper

local HistoryDialogs = {}
ALC.HistoryDialogs = HistoryDialogs

local c = UI.color
local PAD = 20
local exportFrame, clearFrame

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
local function buildExport()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(640, 440)
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
	local title = UI.NewText(f, 14, c.text)
	title:SetPoint("LEFT", f.logo, "RIGHT", 10, 0)
	title:SetText(strupper(L["Export history"]))

	f.hint = UI.NewText(f, 12, c.muted)
	f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(PAD + 40))
	f.hint:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
	f.hint:SetWordWrap(true)
	f.hint:SetText(L["Click in the box, press Ctrl+A then Ctrl+C, and paste it into a file or a spreadsheet (CSV)."])

	f.block = UI.NewTextBlock(f, 640 - 2 * PAD, 440 - 2 * PAD - 40 - 40 - 54)
	f.block:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(PAD + 40 + 36))

	f.close = UI.NewButton(f, 110, 34, L["Close"], function() f:Hide() end)
	f.close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
	f.count = UI.NewText(f, 12, c.muted)
	f.count:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD + 10)
	return f
end

-- Shows awards as text (a list of log entries; nil = the whole history). Returns how many.
function HistoryDialogs:ShowExport(list)
	if not exportFrame then exportFrame = buildExport() end
	local text, count = ALC.Awards:BuildExport(list)
	exportFrame.block:SetContent(text)
	exportFrame.count:SetText(string.format("%d %s", count, count == 1 and L["award"] or L["awards"]))
	exportFrame:Show()
	exportFrame.block.edit:SetFocus()
	return count
end

--------------------------------------------------------------------------------
-- Clear
--------------------------------------------------------------------------------
local function buildClear()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(480, 230)
	f:SetFrameStrata("DIALOG")
	f:SetFrameLevel(50)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	f:Hide()

	local bg = UI.NewFill(f, 10)
	UI.SetTextureColor(bg, c.bg)
	UI.AddBorder(f, c.danger, 1, 10)

	f.logo = UI.NewLogo(f, 26)
	f.logo:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
	local title = UI.NewText(f, 14, c.text)
	title:SetPoint("LEFT", f.logo, "RIGHT", 10, 0)
	title:SetText(strupper(L["Clear the history"]))

	f.text = UI.NewText(f, 13, c.text)
	f.text:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(PAD + 44))
	f.text:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
	f.text:SetWordWrap(true)
	f.text:SetJustifyV("TOP")
	f.note = UI.NewText(f, 12, c.muted)
	f.note:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -10)
	f.note:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
	f.note:SetWordWrap(true)
	f.note:SetJustifyV("TOP")

	f.export = UI.NewButton(f, 130, 36, L["Export first"], function()
		HistoryDialogs:ShowExport(ALC.Awards:GetCountedLog(HistoryDialogs.scope))
	end)
	f.export:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
	f.confirm = UI.NewButton(f, 130, 36, L["Clear history"], function() HistoryDialogs:ConfirmClear() end)
	f.confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
	f.confirm.label:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1)
	f.cancel = UI.NewButton(f, 100, 36, L["Cancel"], function() f:Hide() end)
	f.cancel:SetPoint("RIGHT", f.confirm, "LEFT", -10, 0)
	return f
end

-- Asks whether to clear awards from the history, with the chance to export them first.
-- `dates` is a set of date keys; nil means the whole history.
function HistoryDialogs:AskClear(dates)
	local count = #ALC.Awards:GetCountedLog(dates)
	if count == 0 then
		ALC:Print(L["There is nothing to clear."])
		return false
	end
	if not clearFrame then clearFrame = buildClear() end
	self.scope = dates
	if dates then
		local days = 0
		for _ in pairs(dates) do days = days + 1 end
		clearFrame.text:SetText(string.format(L["Clear the %d awards of the %d picked date(s) from the history? They also stop counting in the Recent awards column."], count, days))
	else
		clearFrame.text:SetText(string.format(L["Clear all %d awards from the history? They also stop counting in the Recent awards column."], count))
	end
	clearFrame.note:SetText(L["What is cleared is saved as a backup first: /alc history restore brings it back (/alc history forget throws the backup away). Export it if you want to keep it for good."])
	clearFrame:Show()
	return true
end

function HistoryDialogs:ConfirmClear()
	if clearFrame then clearFrame:Hide() end
	local count = ALC.Awards:ClearLog(self.scope)
	self.scope = nil
	ALC:Print(L["History cleared: %d awards. Bring them back with /alc history restore."], count)
end

function HistoryDialogs:IsClearShown() return clearFrame ~= nil and clearFrame:IsShown() end
function HistoryDialogs:IsExportShown() return exportFrame ~= nil and exportFrame:IsShown() end

-- /alc history [export | clear | restore]
ALC.Commands:Register("history", function(arg)
	local sub = string.lower(arg or "")
	if sub == "export" then
		HistoryDialogs:ShowExport()
	elseif sub == "clear" then
		HistoryDialogs:AskClear()
	elseif sub == "forget" then
		local count = ALC.Awards:ForgetBackup()
		ALC:Print(count > 0 and L["The backup of %d awards was thrown away."] or L["There is no backup."], count)
	elseif sub == "restore" then
		local count = ALC.Awards:RestoreLog()
		if count > 0 then
			ALC:Print(L["Restored %d awards to the history."], count)
		else
			ALC:Print(L["There is no backup to restore."])
		end
	else
		ALC.CouncilWindow:ToggleHistory()
	end
end, L["open the award history (/alc history export | clear | restore | forget)"])

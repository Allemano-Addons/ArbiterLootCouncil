-- CompareWindow: "Arbiter Compare", two candidates side by side. Ctrl-click a second row in the Council window and it
-- takes the place of Arbiter Context: one column per player, one line per fact (answer, roll, votes, what is worn,
-- the same slot, how much loot lately, what addons add). Where one side clearly has the better number it is green.
-- Presentation only: the facts come from ALC.Context, the same as in Arbiter Context.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local strupper = string.upper
local min, max, floor = math.min, math.max, math.floor

local LABEL_W, COL_W, PAD, HEADER_H = 96, 218, 16, 40
local WIDTH = PAD * 2 + LABEL_W + COL_W * 2 + 10
local ROW_POOL = 20
local GREEN = { 0.30, 0.75, 0.40 }
local c = UI.color

local CompareWindow = {}
ALC.CompareWindow = CompareWindow

local frame

local function hex(color)
	return string.format("%02x%02x%02x", floor((color[1] or 1) * 255 + 0.5), floor((color[2] or 1) * 255 + 0.5), floor((color[3] or 1) * 255 + 0.5))
end

local function colored(text, color)
	if not color then return text end
	local h = type(color) == "string" and color or hex(color)
	return "|cff" .. h .. text .. "|r"
end

local function colorOf(value)
	if type(value) == "table" then return value end
	return UI.HexColor(value)
end

local function ago(h)
	local days = max(0, floor((time() - h.time) / 86400))
	if h.tag == "tonight" then return L["tonight"] end
	if days == 0 then return L["today"] end
	if days == 1 then return L["yesterday"] end
	return string.format(L["%d days ago"], days)
end

--------------------------------------------------------------------------------
-- The lines of the table
--------------------------------------------------------------------------------
local function worn(info)
	if info.waiting then return L["No answer yet"] end
	if info.emptySlot then return colored(L["Nothing equipped in that slot"], GREEN) end
	local parts = {}
	for _, g in ipairs(info.gear) do
		local qc = g.quality and UI.QualityColor(g.quality)
		parts[#parts + 1] = colored(g.name or L["Loading..."], qc) .. (g.ilvl and (" (" .. g.ilvl .. ")") or "")
	end
	return table.concat(parts, "\n")
end

local function upgrade(info)
	local d = info.ilvlDelta
	if info.waiting then return "-" end
	if info.emptySlot then return colored(L["Empty slot"], GREEN) end
	if d == nil then return "-" end
	if d == 0 then return L["same item level"] end
	return colored((d > 0 and "+" or "") .. d .. " " .. L["item level"], d > 0 and GREEN or c.danger)
end

local function sameSlot(info)
	if #info.sameItem > 0 then
		return colored(L["Has already won this item"], c.danger) .. "\n" .. ago(info.sameItem[1])
	elseif #info.sameSlot > 0 then
		local h = info.sameSlot[1]
		local qc = h.quality and UI.QualityColor(h.quality)
		local more = #info.sameSlot > 1 and ("\n" .. string.format(L["... and %d more"], #info.sameSlot - 1)) or ""
		return colored(string.format(L["%d in this slot"], #info.sameSlot), c.gold) .. "\n" .. colored(h.name or L["Loading..."], qc) .. " " .. ago(h) .. more
	elseif info.complete and info.item and info.item.slot then
		return colored(L["No loot in this slot yet"], GREEN)
	end
	return "-"
end

local function tonight(info)
	local n = 0
	for _, h in ipairs(info.history) do if h.tag == "tonight" then n = n + 1 end end
	return n
end

local function recent(info)
	if not info.complete then return L["Asking the loot master ..."] end
	if #info.history == 0 then return L["Nothing yet"] end
	local lines = {}
	for i = 1, min(4, #info.history) do
		local h = info.history[i]
		local qc = h.quality and UI.QualityColor(h.quality)
		lines[#lines + 1] = colored(h.name or L["Loading..."], qc) .. "\n   " .. colored(h.label or "", colorOf(h.color)) .. " \194\183 " .. ago(h)
	end
	return table.concat(lines, "\n")
end

-- Which side has the higher number (nil when equal or unknown).
local function higher(a, b)
	if a == nil or b == nil or a == b then return nil end
	return a > b and "a" or "b"
end

local function number(n, side, best)
	if n == nil then return "-" end
	return best == side and colored(tostring(n), GREEN) or tostring(n)
end

local function buildRows(a, b)
	local rows = {}
	local function add(label, ta, tb) rows[#rows + 1] = { label = label, a = ta, b = tb } end

	local function answer(info)
		if info.waiting then return colored(L["Has not answered yet"], c.muted) end
		return colored(info.label or "", colorOf(info.color) or c.text)
	end
	add(L["Answer"], answer(a), answer(b))
	local rollBest = higher(a.roll, b.roll)
	add(L["Roll"], number(a.roll, "a", rollBest), number(b.roll, "b", rollBest))
	local voteBest = higher(a.votes or 0, b.votes or 0)
	add(L["Votes"], number(a.votes or 0, "a", voteBest), number(b.votes or 0, "b", voteBest))
	if (a.note and a.note ~= "") or (b.note and b.note ~= "") then
		add(L["Note"], a.note and a.note ~= "" and ("\"" .. a.note .. "\"") or "-", b.note and b.note ~= "" and ("\"" .. b.note .. "\"") or "-")
	end
	add(L["Wearing"], worn(a), worn(b))
	add(L["Upgrade"], upgrade(a), upgrade(b))
	add(L["Same slot"], sameSlot(a), sameSlot(b))
	add(L["Tonight"], tostring(tonight(a)), tostring(tonight(b)))
	add(L["Last 7 days"], tostring(a.counts[7]), tostring(b.counts[7]))
	add(L["Last 30 days"], tostring(a.counts[30]), tostring(b.counts[30]))
	add(L["All awards"], tostring(a.total), tostring(b.total))

	-- what addons built on ALC add: lines with the same provider and label sit on one row
	local order, byKey = {}, {}
	local function collect(info, side)
		for _, provider in ipairs(info.providers or {}) do
			for _, line in ipairs(provider.lines) do
				local key = (provider.id or provider.title) .. "|" .. (line.label or "")
				if not byKey[key] then
					byKey[key] = { label = line.label or provider.title }
					order[#order + 1] = key
				end
				byKey[key][side] = colored(line.text or "", line.color)
			end
		end
	end
	collect(a, "a")
	collect(b, "b")
	for _, key in ipairs(order) do
		local r = byKey[key]
		add(r.label, r.a or "-", r.b or "-")
	end

	add(L["Latest loot"], recent(a), recent(b))
	return rows
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------
local function newRow()
	local row = {}
	row.sep = frame:CreateTexture(nil, "BORDER")
	row.sep:SetHeight(1)
	UI.SetTextureColor(row.sep, c.border, 0.6)
	row.label = UI.NewText(frame, 11, c.muted)
	row.label:SetWidth(LABEL_W - 6)
	row.a = UI.NewText(frame, 12, c.text)
	row.b = UI.NewText(frame, 12, c.text)
	for _, fs in ipairs({ row.a, row.b }) do
		fs:SetWidth(COL_W - 12)
		fs:SetWordWrap(true)
		fs:SetJustifyV("TOP")
	end
	return row
end

local function build()
	frame = CreateFrame("Frame", nil, UIParent)
	UI.RegisterScaled(frame)
	frame:SetSize(WIDTH, 400)
	frame:SetFrameStrata("HIGH")
	frame:SetFrameLevel(61)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:Hide()

	local bg = UI.NewFill(frame, 10)
	UI.SetTextureColor(bg, c.bg)
	UI.AddBorder(frame, c.border, 1, 10)

	local logo = UI.NewLogo(frame, 22)
	logo:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -9)
	local title = UI.NewText(frame, 14, c.text)
	title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
	title:SetText(strupper(L["Arbiter Compare"]))
	local close = CreateFrame("Button", nil, frame)
	close:SetSize(30, 30)
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -5)
	close.text = UI.NewText(close, 30, c.muted, "CENTER")
	close.text:SetPoint("CENTER", 0, 0)
	close.text:SetText("\195\151")
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(c.text[1], c.text[2], c.text[3], 1) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1) end)
	close:SetScript("OnClick", function() ALC.CouncilWindow:ClearCompare() end) -- back to the single candidate
	local line = frame:CreateTexture(nil, "BORDER")
	line:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -HEADER_H)
	line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -HEADER_H)
	line:SetHeight(1)
	UI.SetTextureColor(line, c.border)

	frame.nameA = UI.NewText(frame, 16)
	frame.nameB = UI.NewText(frame, 16)
	frame.rankA = UI.NewText(frame, 12, c.muted)
	frame.rankB = UI.NewText(frame, 12, c.muted)
	frame.hint = UI.NewText(frame, 11, c.muted)
	frame.hint:SetText(L["Ctrl-click a row to swap or remove a candidate. x goes back to one."])
	frame.rows = {}
	for i = 1, ROW_POOL do frame.rows[i] = newRow() end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------
local function heightOf(fs, fallback)
	local h = fs.GetStringHeight and fs:GetStringHeight()
	if not h or h <= 0 then return fallback end
	return h
end

local function position()
	local council = ALC.CouncilWindow:GetFrame()
	if not council then return end
	frame:ClearAllPoints()
	local right = council:GetRight()
	local scale = council:GetEffectiveScale() / UIParent:GetEffectiveScale()
	if right and UIParent:GetWidth() and right * scale + WIDTH + 12 > UIParent:GetWidth() then
		frame:SetPoint("TOPRIGHT", council, "TOPLEFT", -90, 0)
	else
		frame:SetPoint("TOPLEFT", council, "TOPRIGHT", 8, 0)
	end
end

local function render(a, b)
	local xA = PAD + LABEL_W
	local xB = xA + COL_W
	local y = HEADER_H + 12
	for _, side in ipairs({ { a, frame.nameA, frame.rankA, xA }, { b, frame.nameB, frame.rankB, xB } }) do
		local info, name, rank, x = side[1], side[2], side[3], side[4]
		local cc = UI.ClassColor(info.class)
		name:SetTextColor(cc[1], cc[2], cc[3], 1)
		name:SetText(info.name)
		name:SetWidth(COL_W - 12)
		name:ClearAllPoints()
		name:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
		rank:SetText(info.rank or "")
		rank:ClearAllPoints()
		rank:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -(y + 21))
	end
	y = y + 44

	local rows = buildRows(a, b)
	for i, row in ipairs(frame.rows) do
		local r = rows[i]
		if r then
			row.label:SetText(strupper(r.label))
			row.a:SetText(r.a)
			row.b:SetText(r.b)
			row.sep:ClearAllPoints()
			row.sep:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
			row.sep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y)
			row.sep:Show()
			local top = y + 8
			row.label:ClearAllPoints()
			row.label:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -top)
			row.a:ClearAllPoints()
			row.a:SetPoint("TOPLEFT", frame, "TOPLEFT", xA, -top)
			row.b:ClearAllPoints()
			row.b:SetPoint("TOPLEFT", frame, "TOPLEFT", xB, -top)
			row.label:Show()
			row.a:Show()
			row.b:Show()
			y = top + max(heightOf(row.a, 16), heightOf(row.b, 16), 16) + 8
		else
			row.sep:Hide()
			row.label:Hide()
			row.a:Hide()
			row.b:Hide()
		end
	end
	frame.hint:ClearAllPoints()
	frame.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(y + 4))
	frame:SetHeight(y + 28)
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------
-- Draws the comparison of two Context:Build results and shows the box.
function CompareWindow:Show(a, b)
	if not frame then build() end
	position()
	render(a, b)
	frame:Show()
end

function CompareWindow:Hide()
	if frame then frame:Hide() end
end

function CompareWindow:IsShown()
	return frame ~= nil and frame:IsShown()
end

function CompareWindow:GetFrame()
	return frame
end

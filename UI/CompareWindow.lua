-- CompareWindow: "Arbiter Compare", two candidates side by side. Ctrl-click a second row in the Council window and it
-- takes the place of Arbiter Context: one column per player, one line per fact (answer, roll, votes, what is worn,
-- the same slot, how much loot lately, what addons add). Where one side clearly has the better number it is green.
-- An item in a line (what is worn, the loot history) shows its tooltip when the mouse is over it.
-- Presentation only: the facts come from ALC.Context, the same as in Arbiter Context.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local strupper = string.upper
local min, max, floor = math.min, math.max, math.floor

local LABEL_W, COL_W, PAD, HEADER_H = 96, 218, 16, 40
local WIDTH = PAD * 2 + LABEL_W + COL_W * 2 + 10
local ROW_POOL = 20
local LINE_GAP = 2
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

-- A cell is a list of lines: { text = "...", item = "item:123" or nil }. An item line shows its tooltip.
local function one(text) return { { text = text } } end

local function itemOf(h)
	if h.itemString then return h.itemString end
	if h.itemID then return "item:" .. h.itemID end
end

--------------------------------------------------------------------------------
-- The cells of the table
--------------------------------------------------------------------------------
local function worn(info)
	if info.waiting then return one(L["No answer yet"]) end
	if info.emptySlot then return one(colored(L["Nothing equipped in that slot"], GREEN)) end
	local lines = {}
	for _, g in ipairs(info.gear) do
		local qc = g.quality and UI.QualityColor(g.quality)
		lines[#lines + 1] = { text = colored(g.name or L["Loading..."], qc) .. (g.ilvl and (" (" .. g.ilvl .. ")") or ""), item = g.itemString }
	end
	return lines
end

local function upgrade(info)
	local d = info.ilvlDelta
	if info.waiting then return one("-") end
	if info.emptySlot then return one(colored(L["Empty slot"], GREEN)) end
	if d == nil then return one("-") end
	if d == 0 then return one(L["same item level"]) end
	return one(colored((d > 0 and "+" or "") .. d .. " " .. L["item level"], d > 0 and GREEN or c.danger))
end

local function sameSlot(info)
	if #info.sameItem > 0 then
		local h = info.sameItem[1]
		return { { text = colored(L["Has already won this item"], c.danger) .. "\n" .. ago(h), item = itemOf(h) } }
	elseif #info.sameSlot > 0 then
		local h = info.sameSlot[1]
		local qc = h.quality and UI.QualityColor(h.quality)
		local lines = {
			{ text = colored(string.format(L["%d in this slot"], #info.sameSlot), c.gold) },
			{ text = colored(h.name or L["Loading..."], qc) .. " " .. ago(h), item = itemOf(h) },
		}
		if #info.sameSlot > 1 then lines[#lines + 1] = { text = string.format(L["... and %d more"], #info.sameSlot - 1) } end
		return lines
	elseif info.complete and info.item and info.item.slot then
		return one(colored(L["No loot in this slot yet"], GREEN))
	end
	return one("-")
end

local function tonight(info)
	local n = 0
	for _, h in ipairs(info.history) do if h.tag == "tonight" then n = n + 1 end end
	return n
end

local function recent(info)
	if not info.complete then return one(L["Asking the loot master ..."]) end
	if #info.history == 0 then return one(L["Nothing yet"]) end
	local lines = {}
	for i = 1, min(4, #info.history) do
		local h = info.history[i]
		local qc = h.quality and UI.QualityColor(h.quality)
		lines[#lines + 1] = {
			text = colored(h.name or L["Loading..."], qc) .. "\n   " .. colored(h.label or "", colorOf(h.color)) .. " \194\183 " .. ago(h),
			item = itemOf(h),
		}
	end
	return lines
end

-- Which side has the higher number (nil when equal or unknown).
local function higher(a, b)
	if a == nil or b == nil or a == b then return nil end
	return a > b and "a" or "b"
end

local function number(n, side, best)
	if n == nil then return one("-") end
	return one(best == side and colored(tostring(n), GREEN) or tostring(n))
end

local function buildRows(a, b)
	local rows = {}
	local function add(label, ca, cb) rows[#rows + 1] = { label = label, a = ca, b = cb } end

	local function answer(info)
		if info.waiting then return one(colored(L["Has not answered yet"], c.muted)) end
		return one(colored(info.label or "", colorOf(info.color) or c.text))
	end
	add(L["Answer"], answer(a), answer(b))
	local rollBest = higher(a.roll, b.roll)
	add(L["Roll"], number(a.roll, "a", rollBest), number(b.roll, "b", rollBest))
	local voteBest = higher(a.votes or 0, b.votes or 0)
	add(L["Votes"], number(a.votes or 0, "a", voteBest), number(b.votes or 0, "b", voteBest))
	if (a.note and a.note ~= "") or (b.note and b.note ~= "") then
		add(L["Note"], one(a.note and a.note ~= "" and ("\"" .. a.note .. "\"") or "-"), one(b.note and b.note ~= "" and ("\"" .. b.note .. "\"") or "-"))
	end
	add(L["Wearing"], worn(a), worn(b))
	add(L["Upgrade"], upgrade(a), upgrade(b))
	add(L["Same slot"], sameSlot(a), sameSlot(b))
	add(L["Tonight"], one(tostring(tonight(a))), one(tostring(tonight(b))))
	add(L["Last 7 days"], one(tostring(a.counts[7])), one(tostring(b.counts[7])))
	add(L["Last 30 days"], one(tostring(a.counts[30])), one(tostring(b.counts[30])))
	add(L["All awards"], one(tostring(a.total)), one(tostring(b.total)))

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
				byKey[key][side] = one(colored(line.text or "", line.color))
			end
		end
	end
	collect(a, "a")
	collect(b, "b")
	for _, key in ipairs(order) do
		local r = byKey[key]
		add(r.label, r.a or one("-"), r.b or one("-"))
	end

	add(L["Latest loot"], recent(a), recent(b))
	return rows
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------
-- One line of a cell: a button so that an item can show its tooltip.
local function newLine()
	local line = CreateFrame("Button", nil, frame)
	line.fs = UI.NewText(line, 12, c.text)
	line.fs:SetPoint("TOPLEFT", line, "TOPLEFT", 0, 0)
	line.fs:SetWidth(COL_W - 12)
	line.fs:SetWordWrap(true)
	line.fs:SetJustifyV("TOP")
	line:SetScript("OnEnter", function(self)
		if self.item and GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(self.item)
			GameTooltip:Show()
		end
	end)
	line:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	line:Hide()
	return line
end

local function newRow()
	local row = {}
	row.sep = frame:CreateTexture(nil, "BORDER")
	row.sep:SetHeight(1)
	UI.SetTextureColor(row.sep, c.border, 0.6)
	row.label = UI.NewText(frame, 11, c.muted)
	row.label:SetWidth(LABEL_W - 6)
	row.a, row.b = {}, {} -- the lines made so far for each column (more are made as a cell needs them)
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

-- Puts the lines of one cell at x and top, below each other. Returns the height used.
local function layoutCell(pool, cell, x, top)
	local y = 0
	for i, data in ipairs(cell) do
		local line = pool[i]
		if not line then
			line = newLine()
			pool[i] = line
		end
		line.item = data.item
		line.fs:SetText(data.text)
		local h = heightOf(line.fs, 16)
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -(top + y))
		line:SetSize(COL_W - 12, h)
		line:Show()
		y = y + h + LINE_GAP
	end
	for i = #cell + 1, #pool do pool[i]:Hide() end
	return max(0, y - LINE_GAP)
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
			row.sep:ClearAllPoints()
			row.sep:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
			row.sep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y)
			row.sep:Show()
			local top = y + 8
			row.label:ClearAllPoints()
			row.label:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -top)
			row.label:Show()
			local hA = layoutCell(row.a, r.a, xA, top)
			local hB = layoutCell(row.b, r.b, xB, top)
			y = top + max(hA, hB, 16) + 8
		else
			row.sep:Hide()
			row.label:Hide()
			layoutCell(row.a, {}, 0, 0)
			layoutCell(row.b, {}, 0, 0)
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

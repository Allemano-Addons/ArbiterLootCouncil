-- SettingsWindow: the council list, loot options, the minimap button and debugging in
-- one place. Presentation only: every change goes through Settings, which tells the
-- rest of the addon.

local ALC = ALC
local UI = ALC.UI
local L = ALC.L

local strupper, strtrim = string.upper, function(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
local min, max = math.min, math.max

-- The window is a sidebar with the tabs on the left and the settings of the chosen tab on the right.
-- WIDTH is the width of the right-hand part, where every setting is laid out.
local WIDTH, PAD = 480, 22
local SIDEBAR_W = 176
local HEADER_H = 84          -- the page header on the right: the tab's name and what it is for
local NAV_H, NAV_GAP = 34, 4
local MAX_H, PAGE_STEP = 640, 40 -- a page taller than the window allows scrolls, 40 px per notch of the wheel

local LIST_ROWS, LIST_ROW_H = 3, 26 -- the council list shows three names; the mouse wheel scrolls the rest

local SettingsWindow = {}
ALC.SettingsWindow = SettingsWindow
LibStub("AceEvent-3.0"):Embed(SettingsWindow)
SettingsWindow.rows = {}
local function qualityName(quality)
	return _G["ITEM_QUALITY" .. quality .. "_DESC"] or tostring(quality)
end

-- The list of qualities for the loot threshold drop-down.
function SettingsWindow:OpenQualityMenu()
	local current = ALC.Settings:GetQualityThreshold()
	local items = {}
	for quality = 2, 4 do
		items[#items + 1] = {
			label = qualityName(quality) .. (quality == current and "  \226\128\162" or ""),
			color = UI.QualityColor(quality),
			onClick = function() ALC.Settings:SetQualityThreshold(quality) end,
		}
	end
	ALC.ContextMenu:Open(items, L["Loot quality threshold"])
end

local frame, offset = nil, 0
local feedback -- the last message about the council list, shown under the input
local activeTab -- the key of the page that is shown; nil until the window is first opened
local sidebarMinH = 400 -- the window is never lower than its sidebar; set when the sidebar is built
local pageOffset = 0    -- how far the page is scrolled, in pixels

-- The tallest the window may be: MAX_H, or less on a small screen (the window follows the Window size setting).
local function maxHeight()
	local screen = UIParent and UIParent.GetHeight and UIParent:GetHeight()
	if type(screen) ~= "number" or screen <= 0 then return MAX_H end
	return min(MAX_H, screen * 0.9 / ((frame and frame:GetScale()) or 1))
end
local c = UI.color

-- The pages, by what you want to set (not by who you are). `group` puts a heading over the page in the sidebar:
-- "lm" for the pages only the loot master uses. Every addon built on ALC that adds settings gets a page of its own
-- under "Modules", added when the window is built.
SettingsWindow.BASE_PAGES = {
	{ key = "general", label = L["General"], note = L["How ALC behaves for you. Nobody else is affected."] },
	{ key = "appearance", label = L["Appearance"], note = L["How the windows look on your own screen."] },
	{ key = "lootmaster", label = L["Master Loot"], group = "lm", note = L["Used when you are the loot master: what happens to the loot, and who gets the items nobody wants."] },
	{ key = "council", label = L["Council"], group = "lm", note = L["Who votes, and what the council sees. Your list is used when you are the loot master."] },
	{ key = "responses", label = L["Responses"], group = "lm", note = L["Used when you are the loot master: the answers every player gets, and how long they have. A running session keeps the ones it started with."] },
	{ key = "session", label = L["Session"], group = "lm", note = L["Used when you are the loot master: how a session runs, and the award log."] },
	{ key = "tools", label = L["Tools"], group = "tools", note = L["Share your settings with another loot master, and find out what went wrong."] },
}
SettingsWindow.PAGES = SettingsWindow.BASE_PAGES
SettingsWindow.TABS = SettingsWindow.PAGES -- the old name

-- The base pages, then a page per module (a settings section that names no page of its own), then Tools last.
local function collectPages()
	local pages, tools = {}, nil
	for _, page in ipairs(SettingsWindow.BASE_PAGES) do
		if page.key == "tools" then tools = page else pages[#pages + 1] = page end
	end
	for _, sec in ipairs(ALC.GetSettingsSections()) do
		if not sec.page then
			pages[#pages + 1] = { key = "module:" .. sec.id, label = sec.name, group = "modules", color = sec.color, section = sec,
				note = string.format(L["Settings that %s adds to ALC."], sec.name) }
		end
	end
	pages[#pages + 1] = tools
	SettingsWindow.PAGES = pages
	SettingsWindow.TABS = pages
	return pages
end

-- The role the player has right now: "lm", "council" or "everyone" (a plain raider).
local function currentRole()
	if ALC.Council:AmLootMaster() then return "lm" end
	if ALC.Council:AmCouncil() then return "council" end
	return "everyone"
end

-- The page the window first opens on: the one that matters most for the role.
local FIRST_PAGE = { lm = "lootmaster", council = "council", everyone = "general" }

local ROLE_TEXT = {
	lm = L["You are the loot master"],
	council = L["You are on the council"],
	everyone = L["You are a raider"],
}

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------
local REASONS = {
	invalid = L["That is not a valid player name."],
	duplicate = L["That player is already on the council."],
	full = L["The council is full."],
}

local function setFeedback(text)
	feedback = text
	SettingsWindow:Refresh()
end

local function addName(text)
	text = strtrim(text or "")
	if text == "" then
		setFeedback(L["Type a player name first."])
		return
	end
	local ok, reason = ALC.Settings:AddCouncilMember(text)
	if ok then
		frame.input:SetText("")
		frame.input.placeholder:Show()
		setFeedback(nil)
	else
		setFeedback(REASONS[reason] or REASONS.invalid)
	end
end

-- A name in its class colour (white when the class is not known).
local function coloured(name)
	local class = name and ALC:ClassOf(name)
	if not class then return name end
	local cc = UI.ClassColor(class)
	return string.format("|cff%02x%02x%02x%s|r", math.floor(cc[1] * 255 + 0.5), math.floor(cc[2] * 255 + 0.5), math.floor(cc[3] * 255 + 0.5), name)
end

local function learnTarget()
	if UnitIsPlayer("target") then ALC:RememberClass(ALC:UnitFullName("target"), select(2, UnitClass("target"))) end
end

-- The disenchanter: the name typed, the target, or nothing (clears it).
local deFeedback
local function setDisenchanter(text)
	text = strtrim(text or "")
	local ok = ALC.Settings:SetDisenchanter(text)
	deFeedback = (not ok) and L["That is not a valid name."] or nil
	if ok and frame and frame.deInput then
		frame.deInput:SetText("")
		frame.deInput.placeholder:Show()
	end
	SettingsWindow:Refresh()
end

local function setDisenchanterTarget()
	if not UnitIsPlayer("target") then
		deFeedback = L["Target a player first."]
		SettingsWindow:Refresh()
		return
	end
	learnTarget()
	setDisenchanter(ALC:UnitFullName("target") or "")
end

-- The guild bank character: the name typed, the target, or nothing (clears it).
local bankFeedback
local function setGuildBank(text)
	text = strtrim(text or "")
	local ok = ALC.Settings:SetGuildBank(text)
	bankFeedback = (not ok) and L["That is not a valid name."] or nil
	if ok and frame and frame.bankInput then
		frame.bankInput:SetText("")
		frame.bankInput.placeholder:Show()
	end
	SettingsWindow:Refresh()
end

local function setGuildBankTarget()
	if not UnitIsPlayer("target") then
		bankFeedback = L["Target a player first."]
		SettingsWindow:Refresh()
		return
	end
	learnTarget()
	setGuildBank(ALC:UnitFullName("target") or "")
end

local function addTarget()
	if not UnitIsPlayer("target") then
		setFeedback(L["Target a player first."])
		return
	end
	learnTarget()
	local name = ALC:UnitFullName("target")
	local ok, reason = ALC.Settings:AddCouncilMember(name or "")
	setFeedback(not ok and (REASONS[reason] or REASONS.invalid) or nil)
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------
local function savePosition()
	local point, _, relPoint, x, y = frame:GetPoint()
	ALC.Settings:SetWindowPosition("settings", point, relPoint, x, y)
end

local function restorePosition()
	frame:ClearAllPoints()
	local pos = ALC.Settings:GetWindowPosition("settings")
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
	end
end

local function build()
	frame = CreateFrame("Frame", nil, UIParent)
	SettingsWindow.frame = frame -- for the tests and for addons built on ALC
	UI.RegisterScaled(frame)
	frame:SetSize(SIDEBAR_W + WIDTH, 700)
	frame:SetFrameStrata("HIGH")
	frame:SetFrameLevel(80)   -- each window has its own band of levels, so windows never mix
	frame:SetToplevel(true) -- and the one you click comes to the front
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	frame:Hide()

	local bg = UI.NewFill(frame, 10)
	UI.SetTextureColor(bg, c.bg)
	UI.AddBorder(frame, c.border, 1, 10)

	local function draggable(f)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", function() frame:StartMoving() end)
		f:SetScript("OnDragStop", function()
			frame:StopMovingOrSizing()
			savePosition()
		end)
	end

	-- Sidebar: the addon's name, who you are, the tabs, and the version at the bottom. Also a drag handle.
	local sidebar = CreateFrame("Frame", nil, frame)
	sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	sidebar:SetWidth(SIDEBAR_W)
	draggable(sidebar)
	frame.sidebar = sidebar
	local sideLine = sidebar:CreateTexture(nil, "BORDER")
	sideLine:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, -1)
	sideLine:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 1)
	sideLine:SetWidth(1)
	UI.SetTextureColor(sideLine, c.border)

	frame.logo = UI.NewLogo(sidebar, 26)
	frame.logo:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 18, -22)
	local name = UI.NewText(sidebar, 18, c.text)
	name:SetPoint("LEFT", frame.logo, "RIGHT", 10, 0)
	name:SetText("ALC")
	local subtitle = UI.NewText(sidebar, 11, c.muted)
	subtitle:SetPoint("TOPLEFT", frame.logo, "BOTTOMLEFT", 0, -10)
	subtitle:SetText(L["Settings"])
	-- Who is looking: the role the player has right now.
	frame.role = UI.NewText(sidebar, 11, c.gold)
	frame.role:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -4)
	frame.role:SetWidth(SIDEBAR_W - 36)
	frame.role:SetWordWrap(true)

	-- The pages, one under the other, under a heading where a group starts (Loot master, Modules; Tools stands
	-- apart). The chosen page has a panel and an amber bar on its left edge; a module's name is in its colour.
	SettingsWindow.tabButtons = {}
	local GROUP_HEADING = { lm = L["Loot master"], modules = L["Modules"] }
	local navY, lastGroup = 112, nil
	for i, tab in ipairs(collectPages()) do
		if tab.group ~= lastGroup then
			navY = navY + 10
			if GROUP_HEADING[tab.group] then
				local heading = UI.NewText(sidebar, 10, c.muted)
				heading:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 24, -navY)
				heading:SetText(strupper(GROUP_HEADING[tab.group]))
				navY = navY + 20
			end
			lastGroup = tab.group
		end
		local item = CreateFrame("Button", nil, sidebar)
		item:SetSize(SIDEBAR_W - 16, NAV_H)
		item:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 8, -navY)
		navY = navY + NAV_H + NAV_GAP
		item.color = tab.color and UI.HexColor(tab.color)
		item.bg = UI.NewFill(item, 6)
		item.bar = item:CreateTexture(nil, "ARTWORK")
		item.bar:SetPoint("TOPLEFT", item, "TOPLEFT", 0, -7)
		item.bar:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0, 7)
		item.bar:SetWidth(3)
		UI.SetTextureColor(item.bar, c.gold)
		item.label = UI.NewText(item, 13, c.muted)
		item.label:SetPoint("LEFT", item, "LEFT", 16, 0)
		item.label:SetText(tab.label)
		item.tab = tab.key
		function item:SetSelected(on)
			self.selected = on
			self.bar:SetShown(on)
			self.bg:SetShown(on or self.hover)
			UI.SetTextureColor(self.bg, on and c.panel or c.panelHover)
			local tc = self.color or (on and c.text) or c.muted
			self.label:SetTextColor(tc[1], tc[2], tc[3], (self.color and not on) and 0.75 or 1)
		end
		item:SetScript("OnEnter", function(self) self.hover = true; self:SetSelected(self.selected) end)
		item:SetScript("OnLeave", function(self) self.hover = false; self:SetSelected(self.selected) end)
		item:SetScript("OnClick", function() SettingsWindow:SetTab(tab.key) end)
		item:SetSelected(false)
		SettingsWindow.tabButtons[i] = item
	end
	sidebarMinH = navY + 70 -- room for the version lines at the bottom

	frame.version = UI.NewText(sidebar, 11, c.muted)
	frame.version:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 18, 18)
	frame.version:SetWidth(SIDEBAR_W - 36)
	frame.version:SetWordWrap(true)
	frame.version:SetText(string.format("%s\n%s", ALC.version or "?", L["/alc for commands"]))

	-- The right-hand part: every setting is laid out in here, as if it were the whole window.
	local body = CreateFrame("Frame", nil, frame)
	body:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDEBAR_W, 0)
	body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	frame.body = body

	-- Page header: the name of the tab and what it is for. Also a drag handle.
	local header = CreateFrame("Frame", nil, body)
	header:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
	header:SetHeight(HEADER_H)
	frame.header = header
	draggable(header)

	frame.pageTitle = UI.NewText(header, 20, c.text)
	frame.pageTitle:SetPoint("TOPLEFT", header, "TOPLEFT", PAD, -22)
	frame.tabNote = UI.NewText(header, 11, c.muted)
	frame.tabNote:SetPoint("TOPLEFT", frame.pageTitle, "BOTTOMLEFT", 0, -8)
	frame.tabNote:SetWidth(WIDTH - 2 * PAD - 30)
	frame.tabNote:SetWordWrap(true)

	local close = CreateFrame("Button", nil, header)
	close:SetSize(30, 30)
	close:SetPoint("TOPRIGHT", header, "TOPRIGHT", -12, -10)
	close.text = UI.NewText(close, 30, c.muted, "CENTER")
	close.text:SetPoint("CENTER", 0, 0)
	close.text:SetText("\195\151")
	close:SetScript("OnEnter", function(self) self.text:SetTextColor(c.text[1], c.text[2], c.text[3], 1) end)
	close:SetScript("OnLeave", function(self) self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1) end)
	close:SetScript("OnClick", function() SettingsWindow:Hide() end)

	-- Every setting belongs to one page (SettingsWindow.PAGES, plus a page per module). `into` puts a widget in its
	-- page's group, so SetTab can show one page and hide the rest.
	local groups = {}
	for _, page in ipairs(SettingsWindow.PAGES) do groups[page.key] = {} end
	SettingsWindow.groups = groups
	local function into(key, widget)
		local group = groups[key]
		group[#group + 1] = widget
		return widget
	end
	local heights = {}

	local function divider(y, key)
		local line = body:CreateTexture(nil, "BORDER")
		line:SetPoint("TOPLEFT", body, "TOPLEFT", 1, -y)
		line:SetPoint("TOPRIGHT", body, "TOPRIGHT", -1, -y)
		line:SetHeight(1)
		UI.SetTextureColor(line, c.border)
		if key then into(key, line) end
		return line
	end
	-- A heading over a group of settings, in the accent colour (or a module's own). Returns the y below it.
	local function section(key, y, text, color)
		local fs = UI.NewText(body, 11, color or c.accent)
		fs:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -y)
		fs:SetText(strupper(text))
		into(key, fs)
		return y + 22
	end
	divider(HEADER_H)

	-- Under the page header the settings scroll: from here on `body` is the scroll child, the page itself, and
	-- every y is measured from its top. The mouse wheel and the bar on the right move it when it is taller than
	-- the window can be (MAX_H).
	local scroll = CreateFrame("ScrollFrame", nil, frame.body)
	scroll:SetPoint("TOPLEFT", frame.body, "TOPLEFT", 0, -(HEADER_H + 1))
	scroll:SetPoint("BOTTOMRIGHT", frame.body, "BOTTOMRIGHT", 0, 1)
	frame.scroll = scroll
	body = CreateFrame("Frame", nil, scroll)
	body:SetSize(WIDTH, 100)
	scroll:SetScrollChild(body)
	frame.page = body
	frame.pageBar = UI.NewScrollBar(frame.body, function(newOffset) SettingsWindow:ScrollPage(newOffset) end)
	frame.pageBar:SetPoint("TOPRIGHT", frame.body, "TOPRIGHT", -7, -(HEADER_H + 8))
	frame.pageBar:SetPoint("BOTTOMRIGHT", frame.body, "BOTTOMRIGHT", -7, 8)
	frame.pageBar:Hide()
	local contentY = 20

	-- One setting is one card: a title and a short description on the left, the control on the right (`rightW`
	-- keeps the text clear of it), or controls under the text (`below`: their height). Returns the card and the y
	-- of the next card.
	local CARD_W, CARD_PAD, CARD_GAP = WIDTH - 2 * PAD, 14, 8
	local function lines(text, width) -- about how many lines an 11 px text wraps to
		return max(1, math.ceil(#text * 4.8 / width))
	end
	local function card(key, y, title, desc, rightW, below)
		local f = into(key, CreateFrame("Frame", nil, body))
		f:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -y)
		f.bg = UI.NewFill(f, 6)
		UI.SetTextureColor(f.bg, c.panel)
		UI.AddBorder(f, c.border, 1, 6)
		f.title = UI.NewText(f, 13, c.text)
		f.title:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_PAD, -12)
		f.title:SetText(title)
		local textH = 15
		if desc and desc ~= "" then
			local width = CARD_W - 2 * CARD_PAD - (rightW and rightW + 16 or 0)
			f.desc = UI.NewText(f, 11, c.muted)
			f.desc:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
			f.desc:SetWidth(width)
			f.desc:SetWordWrap(true)
			f.desc:SetText(desc)
			-- The real height of the wrapped text when the game can tell (it can once the font is set), else a guess.
			local measured = f.desc:GetStringHeight()
			local descH = (type(measured) == "number" and measured > 0 and measured < 120) and math.ceil(measured) or 14 * lines(desc, width)
			textH = textH + 4 + descH
		end
		f.headH = 12 + textH + 12
		local h = f.headH + (below and below + 12 or 0)
		f:SetSize(CARD_W, h)
		return f, y + h + CARD_GAP
	end
	-- A control on the right of a card, in the middle of its title and description.
	local function right(key, f, control)
		control:SetPoint("RIGHT", f, "TOPRIGHT", -CARD_PAD, -f.headH / 2)
		return into(key, control)
	end
	-- Controls under the text of a card: `x` from its left edge, `dy` down from the text.
	local function under(key, f, control, x, dy)
		control:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_PAD + (x or 0), -(f.headH + (dy or 0)))
		return into(key, control)
	end
	-- A switch on its own card. Returns the switch and the y of the next card.
	local function switch(key, y, title, desc, onToggle)
		local f
		f, y = card(key, y, title, desc, 44)
		local box = UI.NewCheckbox(f, title, onToggle)
		box:SetSize(44, 26)
		box.label:Hide() -- the card's title shows it; the label keeps the same text, hidden
		box.card = f
		right(key, f, box)
		return box, y
	end
	-- A row of buttons under the text of a card, one per choice. Returns the buttons.
	local function choices(key, f, options, onPick)
		local n = #options
		local width = math.floor((CARD_W - 2 * CARD_PAD - (n - 1) * 6) / n)
		local buttons = {}
		for i, option in ipairs(options) do
			buttons[i] = under(key, f, UI.NewButton(f, width, 28, option.label, function() onPick(option.value) end), (i - 1) * (width + 6))
			buttons[i].value = option.value
		end
		return buttons
	end

	-- Rows from ALC.RegisterSettingsSection, drawn as cards like ALC's own. Returns the y of the next card.
	local extRefresh = {}
	SettingsWindow.extRefresh = extRefresh
	local function extensionRow(key, row, y)
		if row.type == "check" then
			local box
			box, y = switch(key, y, row.label, row.tip, function(checked) pcall(row.set, checked) end)
			extRefresh[#extRefresh + 1] = function()
				local ok, value = pcall(row.get)
				box:SetChecked(ok and value and true or false)
			end
			return y
		elseif row.type == "choice" then
			local f
			f, y = card(key, y, row.label, row.tip, nil, 28)
			local buttons = choices(key, f, row.options, function(value)
				pcall(row.set, value)
				SettingsWindow:Refresh()
			end)
			extRefresh[#extRefresh + 1] = function()
				local ok, value = pcall(row.get)
				for _, button in ipairs(buttons) do button:SetSelected(ok and value == button.value) end
			end
			return y
		end
		return y -- actions are drawn by extensionRows, side by side in one card
	end
	-- An action button; with `confirm` the first click asks and the second one does it.
	local function actionButton(key, f, row, width)
		local armed
		return into(key, UI.NewButton(f, width, 28, row.label, function(self)
			if row.confirm and not armed then
				armed = true
				self:SetLabel(row.confirm)
				C_Timer.After(4, function()
					armed = nil
					self:SetLabel(row.label)
				end)
				return
			end
			armed = nil
			self:SetLabel(row.label)
			pcall(row.onClick)
			SettingsWindow:Refresh()
		end))
	end
	-- Rows of a section: checks and choices one card each; actions that follow each other share one card, titled
	-- `title`, with their buttons in a row (the button says what it does, so it needs no title of its own).
	local function extensionRows(key, rows, y, title)
		local i = 1
		while i <= #rows do
			local row = rows[i]
			if row.type == "action" then
				local actions = {}
				while rows[i] and rows[i].type == "action" do
					actions[#actions + 1] = rows[i]
					i = i + 1
				end
				local f
				f, y = card(key, y, title, nil, nil, 28)
				local n = #actions
				local width = math.floor((CARD_W - 2 * CARD_PAD - (n - 1) * 6) / n)
				for k, action in ipairs(actions) do
					local button = actionButton(key, f, action, width)
					button:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_PAD + (k - 1) * (width + 6), -f.headH)
				end
			else
				y = extensionRow(key, row, y)
				i = i + 1
			end
		end
		return y
	end
	-- ALC's own sections that name a page (Share settings on Tools, the award log on Session): a heading, then every row.
	local function pageSections(key, y)
		for _, sec in ipairs(ALC.GetSettingsSections()) do
			if sec.page == key then
				y = section(key, y, sec.name, UI.HexColor(sec.color))
				y = extensionRows(key, sec.rows, y, sec.name) + 10
			end
		end
		return y
	end

	-- A name box with Set, Use target and Clear, and a line under it saying who it is now (disenchanter, guild bank).
	local function nameCard(key, y, title, desc, onSet, onTarget, fields)
		local f
		f, y = card(key, y, title, desc, nil, 30 + 8 + 14)
		local input = under(key, f, UI.NewEditBox(f, 170, 30, L["Player name (First Last)"], onSet))
		local set = into(key, UI.NewButton(f, 56, 30, L["Set"], function() onSet(input:GetText()) end))
		set:SetPoint("LEFT", input, "RIGHT", 8, 0)
		local target = into(key, UI.NewButton(f, 96, 30, L["Use target"], onTarget))
		target:SetPoint("LEFT", set, "RIGHT", 8, 0)
		local clear = into(key, UI.NewButton(f, 56, 30, L["Clear"], function() onSet("") end))
		clear:SetPoint("LEFT", target, "RIGHT", 8, 0)
		local current = under(key, f, UI.NewText(f, 12, c.muted), 0, 38)
		frame[fields .. "Input"], frame[fields .. "Set"], frame[fields .. "Target"] = input, set, target
		frame[fields .. "Clear"], frame[fields .. "Current"] = clear, current
		return y
	end

	-- General: how ALC behaves for you ---------------------------------------------
	local y = section("general", contentY, L["You"])
	frame.autoPass, y = switch("general", y, L["Pass automatically on items I can never use"],
		L["Items your class can never wear or wield (plate for a priest) get a Pass for you, and you can still change it. Rings, necklaces, trinkets and cloaks are never passed."],
		function(checked) ALC.Settings:SetAutoPass(checked) end)
	frame.minimap, y = switch("general", y, L["Show the minimap button"], L["Opens the window menu. The launcher works without it."],
		function(checked) ALC.Settings:SetMinimapHidden(not checked) end)
	heights.general = y + 32

	-- Appearance: how the windows look on your screen ------------------------------
	y = section("appearance", contentY, L["Windows"])
	frame.compact, y = switch("appearance", y, L["Compact windows"], L["Smaller rows and buttons in the loot, answer and voting windows."],
		function(checked) ALC.Settings:SetCompact(checked) end)
	local sizeCard
	sizeCard, y = card("appearance", y, L["Window size"], L["Every ALC window, on your screen only."], nil, 28)
	local scaleOptions = {}
	for i, scale in ipairs(ALC.Settings.WINDOW_SCALES) do scaleOptions[i] = { label = string.format("%d%%", scale * 100), value = scale } end
	SettingsWindow.scaleButtons = choices("appearance", sizeCard, scaleOptions, function(scale) ALC.Settings:SetWindowScale(scale) end)
	for _, button in ipairs(SettingsWindow.scaleButtons) do button.scale = button.value end
	local fontCard
	fontCard, y = card("appearance", y, L["Font"], L["The letters of every ALC window. Each font in the list is shown as itself."], 180)
	frame.fontButton = right("appearance", fontCard, UI.NewButton(fontCard, 180, 28, "", function() SettingsWindow:ToggleFontMenu() end))
	heights.appearance = y + 32

	-- Master Loot: what happens to the loot ----------------------------------------
	y = section("lootmaster", contentY, L["Auto loot"])
	frame.autoLoot, y = switch("lootmaster", y, L["Auto loot"],
		L["When you open a corpse as master looter, the items over the threshold are given to you, to award later."],
		function(checked) ALC.Settings:SetAutoLoot(checked) end)
	frame.autoLootConfirm, y = switch("lootmaster", y, L["Ask first (\"Loot all?\")"], L["A question before the loot is taken for you."],
		function(checked) ALC.Settings:SetAutoLootConfirm(checked) end)
	local qualityCard
	qualityCard, y = card("lootmaster", y, L["Loot quality threshold"], L["Items of this quality and better go on the loot list."], 160)
	-- A drop-down: the button shows the threshold, a click opens the list of qualities.
	frame.qualityButton = right("lootmaster", qualityCard, UI.NewButton(qualityCard, 160, 28, "", function()
		SettingsWindow:OpenQualityMenu()
	end))

	y = section("lootmaster", y + 10, L["Loot list"])
	frame.autoOpen, y = switch("lootmaster", y, L["Open the loot window when items arrive"],
		L["Off: the items are still listed quietly. Open the list with /alc loot."],
		function(checked) ALC.Settings:SetAutoOpenLootWindow(checked) end)

	y = section("lootmaster", y + 10, L["After the award"])
	frame.autoTrade, y = switch("lootmaster", y, L["Auto trade"],
		L["The trade window opens with the winner and the item is put in. A winner far away gets a whisper to come."],
		function(checked) ALC.Settings:SetAutoTrade(checked) end)
	frame.announce, y = switch("lootmaster", y, L["Announce awards"],
		L["Say who got which item in raid chat (party chat in a party), and when a trade went through."],
		function(checked) ALC.Settings:SetAnnounceAwards(checked) end)

	y = section("lootmaster", y + 10, L["Recipients"])
	y = nameCard("lootmaster", y, L["Disenchanter"], L["Gets the items nobody wants (the Disenchant button of the voting window)."],
		setDisenchanter, setDisenchanterTarget, "de")
	y = nameCard("lootmaster", y, L["Guild bank"], L["Gets the items the guild keeps (the Guild bank button of the voting window)."],
		setGuildBank, setGuildBankTarget, "bank")
	heights.lootmaster = y + 32

	-- Council: who votes, and what the council sees -------------------------------
	y = section("council", contentY, L["Your council"])
	local listH = LIST_ROWS * LIST_ROW_H + 4
	local councilCard
	councilCard, y = card("council", y, L["Council members"],
		L["Set before the raid. The loot master is always on the council. Changes apply to the next session."], 50, 30 + 6 + 14 + 6 + listH)
	frame.count = right("council", councilCard, UI.NewText(councilCard, 11, c.muted, "RIGHT"))
	frame.input = under("council", councilCard, UI.NewEditBox(councilCard, 214, 30, L["Player name (First Last)"], addName))
	frame.add = into("council", UI.NewButton(councilCard, 70, 30, L["Add"], function() addName(frame.input:GetText()) end))
	frame.add:SetPoint("LEFT", frame.input, "RIGHT", 8, 0)
	frame.addTarget = into("council", UI.NewButton(councilCard, 100, 30, L["Add target"], addTarget))
	frame.addTarget:SetPoint("LEFT", frame.add, "RIGHT", 8, 0)
	frame.feedback = under("council", councilCard, UI.NewText(councilCard, 11, c.danger), 0, 36)

	frame.listBox = under("council", councilCard, CreateFrame("Frame", nil, councilCard), 0, 56)
	frame.listBox:SetSize(CARD_W - 2 * CARD_PAD, listH)
	frame.listBox.bg = UI.NewFill(frame.listBox, 6)
	UI.SetTextureColor(frame.listBox.bg, c.bg)
	UI.AddBorder(frame.listBox, c.border, 1, 6)

	frame.empty = UI.NewText(frame.listBox, 12, c.muted, "CENTER")
	frame.empty:SetPoint("CENTER", frame.listBox, "CENTER", 0, 0)
	frame.empty:SetText(L["No council members yet."])

	for i = 1, LIST_ROWS do
		local row = CreateFrame("Frame", nil, frame.listBox)
		row:SetHeight(LIST_ROW_H)
		row:SetPoint("TOPLEFT", frame.listBox, "TOPLEFT", 2, -2 - (i - 1) * LIST_ROW_H)
		row:SetPoint("TOPRIGHT", frame.listBox, "TOPRIGHT", -2, -2 - (i - 1) * LIST_ROW_H)
		row.name = UI.NewText(row, 13, c.text)
		row.name:SetPoint("LEFT", row, "LEFT", 12, 0)
		row.remove = CreateFrame("Button", nil, row)
		row.remove:SetSize(24, 24)
		row.remove:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		row.remove.text = UI.NewText(row.remove, 18, c.muted, "CENTER")
		row.remove.text:SetPoint("CENTER", 0, 1)
		row.remove.text:SetText("\195\151")
		row.remove:SetScript("OnEnter", function(self) self.text:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1) end)
		row.remove:SetScript("OnLeave", function(self) self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1) end)
		row.remove:SetScript("OnClick", function()
			if row.member then
				ALC.Settings:RemoveCouncilMember(row.member)
			end
		end)
		SettingsWindow.rows[i] = row
	end

	-- The council of this raid: the list the loot master sent, which every council member can read.
	local raidCard
	raidCard, y = card("council", y, L["This raid's council"], L["The list the loot master sent with the last session."], nil, 56)
	frame.councilNames = under("council", raidCard, UI.NewText(raidCard, 12, c.text))
	frame.councilNames:SetWidth(CARD_W - 2 * CARD_PAD)
	frame.councilNames:SetHeight(56)
	frame.councilNames:SetWordWrap(true)
	frame.councilNames:SetJustifyV("TOP")

	y = section("council", y + 10, L["Voting window"])
	frame.keepOpen, y = switch("council", y, L["Keep the voting window open after an award"],
		L["Sorting, compact rows and the number of rows are set in the voting window itself. Right-click a player there for more."],
		function(checked) ALC.Settings:SetKeepCouncilOpen(checked) end)
	frame.councilHint = frame.keepOpen.card.desc

	y = section("council", y + 10, L["What the council sees"])
	-- A random roll per candidate and item, for the council to choose by when it cannot decide.
	frame.rolls, y = switch("council", y, L["Random rolls for the council"],
		L["A roll for every answer, shown as its own column, for when the council cannot decide."],
		function(checked) ALC.Settings:SetRollsEnabled(checked) end)
	-- How far back the council sees what a player was awarded (the Recent column).
	local recentCard
	recentCard, y = card("council", y, L["Recent awards"], L["How far back the council sees what each player has won."], nil, 28)
	local recentOptions = {}
	for i, recentDays in ipairs({ 7, 14, 30, 90 }) do recentOptions[i] = { label = string.format(L["%d days"], recentDays), value = recentDays } end
	SettingsWindow.recentButtons = choices("council", recentCard, recentOptions, function(days) ALC.Settings:SetRecentDays(days) end)
	for _, button in ipairs(SettingsWindow.recentButtons) do button.days = button.value end
	heights.council = y + 32

	-- Responses: the answers every player gets, and how long they have --------------
	y = section("responses", contentY, L["Answer buttons"])
	local RESPONSE_ROW_H = 36
	local buttonsCard
	buttonsCard, y = card("responses", y, L["Answer buttons"], L["2 to 8 answers with your own names and colours. Pass is always last."], 50,
		ALC.Constants.MAX_RESPONSES * RESPONSE_ROW_H + 30 + 6 + 14)
	frame.responseCount = right("responses", buttonsCard, UI.NewText(buttonsCard, 11, c.muted, "RIGHT"))
	SettingsWindow.responseRows = {}
	for i = 1, ALC.Constants.MAX_RESPONSES do
		local row = under("responses", buttonsCard, CreateFrame("Frame", nil, buttonsCard), 0, (i - 1) * RESPONSE_ROW_H)
		row:SetSize(CARD_W - 2 * CARD_PAD, RESPONSE_ROW_H - 4)
		row.index = i
		row.up = UI.NewButton(row, 24, 30, "^", function() SettingsWindow:MoveResponse(i, -1) end)
		row.up:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.down = UI.NewButton(row, 24, 30, "v", function() SettingsWindow:MoveResponse(i, 1) end)
		row.down:SetPoint("LEFT", row.up, "RIGHT", 2, 0)
		row.edit = UI.NewEditBox(row, 210, 30, L["Label"], function() SettingsWindow:CommitResponseLabel(i) end)
		row.edit:SetMaxLetters(ALC.Constants.MAX_RESPONSE_LABEL)
		row.edit:SetPoint("LEFT", row.down, "RIGHT", 8, 0)
		row.edit:HookScript("OnEditFocusLost", function() SettingsWindow:CommitResponseLabel(i) end)
		row.color = UI.NewButton(row, 34, 30, "", function() SettingsWindow:CycleResponseColor(i) end)
		row.color:SetPoint("LEFT", row.edit, "RIGHT", 8, 0)
		row.color.swatch = row.color:CreateTexture(nil, "OVERLAY")
		row.color.swatch:SetPoint("TOPLEFT", 7, -7)
		row.color.swatch:SetPoint("BOTTOMRIGHT", -7, 7)
		row.remove = CreateFrame("Button", nil, row)
		row.remove:SetSize(24, 24)
		row.remove:SetPoint("LEFT", row.color, "RIGHT", 8, 0)
		row.remove.text = UI.NewText(row.remove, 18, c.muted, "CENTER")
		row.remove.text:SetPoint("CENTER", 0, 1)
		row.remove.text:SetText("\195\151")
		row.remove:SetScript("OnEnter", function(self) self.text:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1) end)
		row.remove:SetScript("OnLeave", function(self) self.text:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1) end)
		row.remove:SetScript("OnClick", function() SettingsWindow:RemoveResponse(i) end)
		SettingsWindow.responseRows[i] = row
	end
	local listEnd = ALC.Constants.MAX_RESPONSES * RESPONSE_ROW_H
	frame.addResponse = under("responses", buttonsCard, UI.NewButton(buttonsCard, 130, 30, L["Add button"], function() SettingsWindow:AddResponse() end), 0, listEnd)
	frame.resetResponses = into("responses", UI.NewButton(buttonsCard, 160, 30, L["Back to the default five"], function() SettingsWindow:ResetResponses() end))
	frame.resetResponses:SetPoint("LEFT", frame.addResponse, "RIGHT", 8, 0)
	frame.responseFeedback = under("responses", buttonsCard, UI.NewText(buttonsCard, 11, c.danger), 0, listEnd + 36)

	-- The answer timer: when it runs out the response window closes for the players.
	y = section("responses", y + 10, L["Answer timer"])
	local timerCard
	timerCard, y = card("responses", y, L["Answer timer"],
		L["When the time is up the response window closes for everybody. The council can still vote and award."], 44, 28)
	frame.timerCheck = right("responses", timerCard, UI.NewCheckbox(timerCard, "", function(checked) ALC.Settings:SetTimerEnabled(checked) end))
	frame.timerCheck:SetSize(44, 26)
	frame.timerCheck.label:Hide() -- Refresh still writes "On, 60 sec" to it, for the tests and the tooltip-less card
	local timerOptions = {}
	for i, seconds in ipairs(ALC.Settings.TIMER_PRESETS) do timerOptions[i] = { label = string.format(L["%d sec"], seconds), value = seconds } end
	SettingsWindow.timerButtons = choices("responses", timerCard, timerOptions, function(seconds) ALC.Settings:SetTimerSeconds(seconds) end)
	for _, button in ipairs(SettingsWindow.timerButtons) do button.seconds = button.value end
	heights.responses = y + 32

	-- Session: how a session runs, and the award log ------------------------------
	y = section("session", contentY, L["Session"])
	-- A warning when a session starts about players who did not reply to the version check (no addon)
	frame.warnMissing, y = switch("session", y, L["Warn about players without the addon"],
		L["When a session starts, the chat says which players did not reply to the version check: they probably cannot answer."],
		function(checked) ALC.Settings:SetWarnMissing(checked) end)
	y = pageSections("session", y + 10)
	heights.session = y + 22

	-- Tools: share your settings, and find out what went wrong ----------------------
	y = pageSections("tools", contentY)
	y = section("tools", y, L["Troubleshooting"])
	frame.debug, y = switch("tools", y, L["Print debug messages in chat"], L["What ALC does, as it happens. Mostly for bug reports."],
		function(checked) ALC.Settings:SetDebug(checked) end)
	local logCard
	logCard, y = card("tools", y, L["Debug log"], L["The last 30 lines in chat, or empty the log."], 248)
	frame.clearLog = right("tools", logCard, UI.NewButton(logCard, 120, 28, L["Clear log"], function()
		ALC.Debug:Clear()
		ALC:Print(L["Debug log cleared."])
	end))
	frame.showLog = into("tools", UI.NewButton(logCard, 120, 28, L["Show log"], function() ALC.Debug:Dump(30) end))
	frame.showLog:SetPoint("RIGHT", frame.clearLog, "LEFT", -8, 0)
	local versionCard
	versionCard, y = card("tools", y, L["Who has the addon"], L["Every player in the group and the version of ALC they have."], 120)
	frame.versions = right("tools", versionCard, UI.NewButton(versionCard, 120, 28, L["Show"], function()
		if ALC.VersionWindow then ALC.VersionWindow:Toggle() end
	end))
	heights.tools = y + 32

	-- Modules: a page per addon built on ALC (Soft Reserve), with the rows it added. The rows for everybody come
	-- first, then the ones only used by the loot master under a heading of their own, both in the module's colour.
	for _, page in ipairs(SettingsWindow.PAGES) do
		if page.section then
			local key = page.key
			local color = UI.HexColor(page.section.color)
			y = contentY
			for _, tab in ipairs({ "everyone", "lm" }) do
				local rows = {}
				for _, row in ipairs(page.section.rows) do
					if row.tab == tab then rows[#rows + 1] = row end
				end
				if #rows > 0 then
					y = section(key, y, tab == "lm" and L["When you are the loot master"] or L["For you"], color)
					y = extensionRows(key, rows, y, page.section.name)
					y = y + 10
				end
			end
			heights[key] = y + 22
		end
	end

	SettingsWindow.heights = heights
	frame:SetHeight(max(HEADER_H + heights.general, sidebarMinH))

	-- The wheel scrolls the page; over the council list it scrolls the list.
	frame:SetScript("OnMouseWheel", function(_, delta)
		SettingsWindow:ScrollPage((pageOffset or 0) - delta * PAGE_STEP)
	end)
	frame.listBox:EnableMouseWheel(true)
	frame.listBox:SetScript("OnMouseWheel", function(_, delta)
		local count = #ALC.Settings:GetCouncil()
		offset = max(0, min(offset - delta, max(0, count - LIST_ROWS)))
		SettingsWindow:Refresh()
	end)
	frame:SetScript("OnShow", function() SettingsWindow:Refresh() end)

	restorePosition()
end

--------------------------------------------------------------------------------
-- The font list
--------------------------------------------------------------------------------
local FONT_ROWS, FONT_ROW_H = 8, 30
local fontMenu, fontCatcher
local fontChoices, fontOffset = {}, 0

local function refreshFontMenu()
	if not fontMenu or not fontMenu:IsShown() then return end
	fontOffset = max(0, min(fontOffset, max(0, #fontChoices - FONT_ROWS)))
	local current = ALC.Settings:GetFont()
	for i, row in ipairs(fontMenu.rows) do
		local choice = fontChoices[fontOffset + i]
		if choice then
			row.choice = choice
			-- Each font is shown as itself; a font the game cannot load falls back to the default.
			-- The font must be set before the text: a text without a font is an error.
			local ok = row.name:SetFont(choice.path or STANDARD_TEXT_FONT, 13, "")
			if ok == false then row.name:SetFont(STANDARD_TEXT_FONT, 13, "") end
			row.name:SetText(choice.name)
			local selected = (choice.path == nil and current == nil)
				or (choice.path ~= nil and current ~= nil and string.lower(choice.path) == string.lower(current))
			row.selected = selected
			UI.SetTextureColor(row.bg, selected and c.goldTint or c.panel, selected and 1 or 0)
			local color = selected and c.gold or c.text
			row.name:SetTextColor(color[1], color[2], color[3], 1)
			row:Show()
		else
			row.choice = nil
			row:Hide()
		end
	end
	fontMenu.scroll:Update(#fontChoices, FONT_ROWS, fontOffset)
end

local function buildFontMenu()
	fontCatcher = CreateFrame("Frame", nil, UIParent)
	fontCatcher:SetAllPoints(UIParent)
	fontCatcher:SetFrameStrata("DIALOG")
	fontCatcher:EnableMouse(true)
	fontCatcher:SetScript("OnMouseDown", function() SettingsWindow:HideFontMenu() end)
	fontCatcher:Hide()

	fontMenu = CreateFrame("Frame", nil, UIParent)
	fontMenu:SetFrameStrata("FULLSCREEN_DIALOG")
	fontMenu:SetClampedToScreen(true)
	fontMenu:EnableMouseWheel(true)
	fontMenu:SetSize(WIDTH - 2 * PAD, FONT_ROWS * FONT_ROW_H + 12)
	fontMenu:Hide()
	local bg = UI.NewFill(fontMenu, 8)
	UI.SetTextureColor(bg, c.bg)
	UI.AddBorder(fontMenu, c.border, 1, 8)

	fontMenu.rows = {}
	for i = 1, FONT_ROWS do
		local row = CreateFrame("Button", nil, fontMenu)
		row:SetHeight(FONT_ROW_H)
		row:SetPoint("TOPLEFT", fontMenu, "TOPLEFT", 6, -6 - (i - 1) * FONT_ROW_H)
		row:SetPoint("TOPRIGHT", fontMenu, "TOPRIGHT", -16, -6 - (i - 1) * FONT_ROW_H)
		row.bg = UI.NewFill(row, 6)
		UI.SetTextureColor(row.bg, c.panel, 0)
		-- Not made with UI.NewText: the font of a row is its own, whatever the setting is.
		row.name = row:CreateFontString(nil, "OVERLAY")
		row.name:SetFont(STANDARD_TEXT_FONT, 13, "") -- every text needs a font before it gets its text
		row.name:SetPoint("LEFT", row, "LEFT", 12, 0)
		row.name:SetJustifyH("LEFT")
		row:SetScript("OnEnter", function(self) UI.SetTextureColor(self.bg, c.panelHover, 1) end)
		row:SetScript("OnLeave", function(self)
			UI.SetTextureColor(self.bg, self.selected and c.goldTint or c.panel, self.selected and 1 or 0)
		end)
		row:SetScript("OnClick", function(self)
			if not self.choice then return end
			ALC.Settings:SetFont(self.choice.path)
			SettingsWindow:HideFontMenu()
		end)
		fontMenu.rows[i] = row
	end
	fontMenu.scroll = UI.NewScrollBar(fontMenu, function(newOffset)
		fontOffset = newOffset
		refreshFontMenu()
	end)
	fontMenu.scroll:SetPoint("TOPRIGHT", fontMenu, "TOPRIGHT", -5, -6)
	fontMenu.scroll:SetHeight(FONT_ROWS * FONT_ROW_H)
	fontMenu.scroll:Hide()
	fontMenu:SetScript("OnMouseWheel", function(_, delta)
		fontOffset = max(0, min(fontOffset - delta, max(0, #fontChoices - FONT_ROWS)))
		refreshFontMenu()
	end)
end

function SettingsWindow:ShowFontMenu()
	if not frame then return end
	if not fontMenu then buildFontMenu() end
	fontChoices = UI.GetFontChoices()
	fontOffset = 0
	fontMenu:ClearAllPoints()
	fontMenu:SetPoint("TOPRIGHT", frame.fontButton, "BOTTOMRIGHT", 0, -4) -- the button sits on the right of its card
	fontCatcher:Show()
	fontMenu:Show()
	refreshFontMenu()
end

function SettingsWindow:HideFontMenu()
	if fontMenu then fontMenu:Hide() end
	if fontCatcher then fontCatcher:Hide() end
end

function SettingsWindow:ToggleFontMenu()
	if fontMenu and fontMenu:IsShown() then self:HideFontMenu() else self:ShowFontMenu() end
end

SettingsWindow.fontMenu = function() return fontMenu end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- The answer buttons (tab "Buttons")
--------------------------------------------------------------------------------
local responseFeedback

local function setResponseFeedback(text)
	responseFeedback = text
	if frame and frame.responseFeedback then frame.responseFeedback:SetText(text or "") end
end

-- Saves an edited copy of the loot master's buttons; on refusal the reason is shown.
local function saveResponses(set)
	local ok, reason = ALC.Responses:SetConfiguredSet(set)
	if not ok then setResponseFeedback(reason) return false end
	setResponseFeedback(nil)
	return true
end

function SettingsWindow:CommitResponseLabel(index)
	local row = self.responseRows and self.responseRows[index]
	local set = ALC.Responses:GetConfiguredSet()
	if not row or not set[index] then return end
	local label = ALC.Responses.CleanLabel(row.edit:GetText())
	if label and label ~= set[index].label then
		set[index].label = label
		saveResponses(set)
	end
	row.edit:SetText(set[index].label) -- an empty label goes back to what it was
end

function SettingsWindow:CycleResponseColor(index)
	local set = ALC.Responses:GetConfiguredSet()
	if not set[index] then return end
	local palette = ALC.Responses.PALETTE
	local current = 0
	for i, color in ipairs(palette) do
		if math.abs(color[1] - set[index].color[1]) < 0.01 and math.abs(color[2] - set[index].color[2]) < 0.01
			and math.abs(color[3] - set[index].color[3]) < 0.01 then current = i end
	end
	local nextColor = palette[current % #palette + 1]
	set[index].color = { nextColor[1], nextColor[2], nextColor[3] }
	saveResponses(set)
end

-- Moves a button up or down among the others; PASS stays last.
function SettingsWindow:MoveResponse(index, step)
	local set = ALC.Responses:GetConfiguredSet()
	local target = index + step
	if not set[index] or not set[target] or set[index].id == "PASS" or set[target].id == "PASS" then return end
	set[index], set[target] = set[target], set[index]
	saveResponses(set)
end

function SettingsWindow:RemoveResponse(index)
	local set = ALC.Responses:GetConfiguredSet()
	if not set[index] or set[index].id == "PASS" then return end
	if #set <= 2 then
		setResponseFeedback(L["There must be at least one button besides Pass."])
		return
	end
	table.remove(set, index)
	saveResponses(set)
end

function SettingsWindow:AddResponse()
	local set = ALC.Responses:GetConfiguredSet()
	if #set >= ALC.Constants.MAX_RESPONSES then
		setResponseFeedback(string.format(L["At most %d buttons."], ALC.Constants.MAX_RESPONSES))
		return
	end
	local used = {}
	for _, r in ipairs(set) do used[r.id] = true end
	local n = 1
	while used["X" .. n] do n = n + 1 end
	local color = ALC.Responses.PALETTE[(#set - 1) % #ALC.Responses.PALETTE + 1]
	table.insert(set, #set, { id = "X" .. n, label = L["New button"], color = { color[1], color[2], color[3] } })
	saveResponses(set)
end

function SettingsWindow:ResetResponses()
	saveResponses(nil)
end

-- Shows the settings of one tab and hides the others.
function SettingsWindow:SetTab(key)
	if not self.groups or not self.groups[key] then return end
	local switched = activeTab ~= key
	activeTab = key
	for tabKey, widgets in pairs(self.groups) do
		for _, widget in ipairs(widgets) do widget:SetShown(tabKey == key) end
	end
	local buttons = ALC.Responses:GetConfiguredSet()
	for i, row in ipairs(self.responseRows) do
		if i > #buttons then row:Hide() end -- no such button
	end
	for _, button in ipairs(self.tabButtons) do
		button:SetSelected(button.tab == key)
	end
	for _, tab in ipairs(self.TABS) do
		if tab.key == key then
			frame.pageTitle:SetText(tab.title or tab.label)
			frame.tabNote:SetText(tab.note)
		end
	end
	-- As tall as the page needs, between the sidebar's height and MAX_H; a taller page scrolls.
	local pageH = self.heights[key]
	frame.page:SetHeight(pageH)
	frame:SetHeight(min(max(HEADER_H + pageH, sidebarMinH), maxHeight()))
	if switched then
		self:HideFontMenu()
		self:ScrollPage(0)
	else
		self:ScrollPage(pageOffset or 0)
	end
end

-- Scrolls the page to `to` pixels from its top (kept inside the page) and moves the bar.
function SettingsWindow:ScrollPage(to)
	if not frame then return end
	local visible = frame:GetHeight() - HEADER_H - 2
	local total = self.heights and self.heights[activeTab] or visible
	pageOffset = max(0, min(to or 0, max(0, total - visible)))
	frame.scroll:SetVerticalScroll(pageOffset)
	frame.pageBar:Update(total, visible, pageOffset)
end

function SettingsWindow:GetTab()
	return activeTab
end

function SettingsWindow:Refresh()
	if not frame or not frame:IsShown() then return end
	local settings = ALC.Settings

	frame.role:SetText(ROLE_TEXT[currentRole()])
	if not activeTab then activeTab = FIRST_PAGE[currentRole()] end
	self:SetTab(activeTab)

	local council = settings:GetCouncil()
	local count = #council
	offset = max(0, min(offset, max(0, count - LIST_ROWS)))
	for i = 1, LIST_ROWS do
		local row = self.rows[i]
		local name = council[offset + i]
		row.member = name
		if name then
			row.name:SetText(coloured(name))
			row:Show()
		else
			row:Hide()
		end
	end
	frame.empty:SetShown(count == 0)
	frame.count:SetText(string.format("%d/%d", count, ALC.Constants.MAX_COUNCIL - 1))
	frame.feedback:SetText(feedback or "")

	-- The council of the running session, else the one of the last session.
	local session = ALC.Sessions:GetSession()
	local lm, names
	if session then
		lm, names = session.lm, session.council
	else
		local last = settings:GetLastCouncil()
		lm, names = last and last.lm, last and last.council
	end
	if names and #names > 0 then
		frame.councilNames:SetText(format(L["Loot master: %s"], lm or "?") .. "\n" .. table.concat(names, ", ")
			.. (session and "" or ("\n\n" .. L["From the last session. The loot master sends the council again when a session starts."])))
	else
		frame.councilNames:SetText(L["No session yet. The loot master chooses the council and sends it to everybody when a session starts."])
	end

	local threshold = settings:GetQualityThreshold()
	frame.qualityButton:SetLabel(qualityName(threshold))
	local qc = UI.QualityColor(threshold)
	frame.qualityButton.label:SetTextColor(qc[1], qc[2], qc[3], 1)
	local buttons = ALC.Responses:GetConfiguredSet()
	frame.responseCount:SetText(string.format("%d/%d", #buttons, ALC.Constants.MAX_RESPONSES))
	for i, row in ipairs(self.responseRows) do
		local r = buttons[i]
		if r then
			row.edit:SetText(r.label)
			local isPass = r.id == "PASS"
			row.color.swatch:SetColorTexture(r.color[1], r.color[2], r.color[3], 1)
			row.remove:SetShown(not isPass)
			row.up:SetAvailable(i > 1 and buttons[i - 1].id ~= "PASS" and not isPass)
			row.down:SetAvailable(not isPass and buttons[i + 1] ~= nil and buttons[i + 1].id ~= "PASS")
			row:SetShown(activeTab == "responses")
		else
			row:Hide()
		end
	end
	frame.responseFeedback:SetText(responseFeedback or "")
	frame.autoOpen:SetChecked(settings:GetAutoOpenLootWindow())
	frame.announce:SetChecked(settings:GetAnnounceAwards())
	frame.autoLoot:SetChecked(settings:GetAutoLoot())
	frame.autoLootConfirm:SetChecked(settings:GetAutoLootConfirm())
	frame.autoTrade:SetChecked(settings:GetAutoTrade())
	frame.timerCheck:SetChecked(settings:GetTimerEnabled())
	frame.timerCheck.label:SetText(settings:GetTimerEnabled()
		and string.format(L["Answer timer: On, %d sec"], settings:GetTimerSeconds()) or L["Answer timer: Off"])
	for _, button in ipairs(self.timerButtons) do button:SetSelected(button.seconds == settings:GetTimerSeconds()) end
	frame.compact:SetChecked(settings:GetCompact())
	frame.autoPass:SetChecked(settings:GetAutoPass())
	for _, button in ipairs(self.recentButtons) do button:SetSelected(button.days == settings:GetRecentDays()) end
	for _, button in ipairs(self.scaleButtons) do button:SetSelected(button.scale == settings:GetWindowScale()) end
	frame.minimap:SetChecked(not settings:IsMinimapHidden())
	frame.keepOpen:SetChecked(settings:GetKeepCouncilOpen())
	frame.rolls:SetChecked(settings:GetRollsEnabled())
	frame.warnMissing:SetChecked(settings:GetWarnMissing())
	local disenchanter = settings:GetDisenchanter()
	if deFeedback then
		frame.deCurrent:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1)
		frame.deCurrent:SetText(deFeedback)
	else
		frame.deCurrent:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
		frame.deCurrent:SetText(disenchanter and (L["Disenchanter"] .. ": " .. coloured(disenchanter)) or L["No disenchanter set."])
	end
	frame.deClear:SetAvailable(disenchanter ~= nil)
	local bank = settings:GetGuildBank()
	if bankFeedback then
		frame.bankCurrent:SetTextColor(c.danger[1], c.danger[2], c.danger[3], 1)
		frame.bankCurrent:SetText(bankFeedback)
	else
		frame.bankCurrent:SetTextColor(c.muted[1], c.muted[2], c.muted[3], 1)
		frame.bankCurrent:SetText(bank and (L["Guild bank"] .. ": " .. coloured(bank)) or L["No guild bank set."])
	end
	frame.bankClear:SetAvailable(bank ~= nil)
	frame.debug:SetChecked(settings:IsDebug())
	for _, refreshRow in ipairs(self.extRefresh or {}) do refreshRow() end
	frame.fontButton:SetLabel(UI.FontName(settings:GetFont()))
	refreshFontMenu()
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------
-- Whether the window is open is remembered across a /reload.
function SettingsWindow:Show()
	if not frame then
		-- A build that fails half way must not leave a broken frame behind.
		local ok, err = pcall(build)
		if not ok then
			frame = nil
			error(err, 0)
		end
	end
	frame:Show()
	ALC.Settings:SetWindowShown("settings", true)
	self:Refresh()
end

function SettingsWindow:Hide()
	self:HideFontMenu()
	if frame then frame:Hide() end
	ALC.Settings:SetWindowShown("settings", false)
end

function SettingsWindow:Toggle()
	if frame and frame:IsShown() then self:Hide() else self:Show() end
end

function SettingsWindow:IsShown()
	return frame ~= nil and frame:IsShown()
end

function SettingsWindow:OnEnteringWorld(isInitialLogin, isReloadingUi)
	if not (isInitialLogin or isReloadingUi) then return end
	if ALC.Settings:GetWindowShown("settings") then self:Show() end
end

function SettingsWindow:Init()
	ALC.Events.Register(self, "ALC_SETTINGS_CHANGED", function(_, key)
		if key == "windowScale" then UI.ApplyScales() end
		SettingsWindow:Refresh()
	end)
	ALC.Events.Register(self, "ALC_SESSION_STARTED", function(_, session)
		if session and session.council then ALC.Settings:SetLastCouncil(session.lm, session.council) end
		SettingsWindow:Refresh()
	end)
	ALC.Events.Register(self, "ALC_SESSION_ENDED", function() SettingsWindow:Refresh() end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
		SettingsWindow:OnEnteringWorld(isInitialLogin, isReloadingUi)
	end)
end

ALC.Commands:Register("settings", function() SettingsWindow:Toggle() end, L["open the settings window"])

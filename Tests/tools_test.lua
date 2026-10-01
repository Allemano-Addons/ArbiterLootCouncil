-- The settings window, the window menu and the minimap button, on the real modules.
-- A fresh reload, so these start from an empty session and empty saved variables.
-- Runs last.

return function(check, H)
	H.reload("fresh")
	local ME = "Tester Moo"

	local Settings, Win, Launcher, Button = ALC.Settings, ALC.SettingsWindow, ALC.Launcher, ALC.MinimapButton
	local frame

	local env = H.env
	local function hasText(list, text)
		for _, line in ipairs(list) do
			if line:find(text, 1, true) then return true end
		end
		return false
	end

	----------------------------------------------------------------------------
	-- Settings: the rules behind the window
	----------------------------------------------------------------------------
	local ok, why = Settings:AddCouncilMember("Bad|cffff0000Name")
	check("a name with an escape sequence is refused", ok == false and why == "invalid")
	ok, why = Settings:AddCouncilMember("x")
	check("a one-letter name is refused", ok == false and why == "invalid")
	ok, why = Settings:AddCouncilMember(string.rep("a", 49))
	check("a name that is too long is refused", ok == false and why == "invalid")
	check("a good name is accepted", Settings:AddCouncilMember("veyra moo") == true)
	ok, why = Settings:AddCouncilMember("VEYRA MOO")
	check("a duplicate says so", ok == false and why == "duplicate")
	for i = 1, 38 do Settings:AddCouncilMember("Player" .. string.char(64 + (i % 26) + 1) .. string.rep("a", i)) end
	check("the council holds 39 names", #Settings:GetCouncil() == 39)
	ok, why = Settings:AddCouncilMember("One Toomany")
	check("the 40th is refused, the loot master needs a place", ok == false and why == "full")
	for _, name in ipairs(Settings:GetCouncil()) do
		if name ~= "Veyra Moo" then Settings:RemoveCouncilMember(name) end
	end
	check("back to one name", #Settings:GetCouncil() == 1)

	check("the button starts shown, at its default place", Settings:IsMinimapHidden() == false and Settings:GetButtonPosition() == nil)
	Settings:SetButtonPosition("TOPLEFT", "TOPLEFT", 120, -80)
	local saved = Settings:GetButtonPosition()
	check("a dropped position is kept", saved.point == "TOPLEFT" and saved.relPoint == "TOPLEFT" and saved.x == 120 and saved.y == -80)
	Settings:GetDB().profile.minimap.position = { x = 5 }
	check("a position without an anchor point counts as none", Settings:GetButtonPosition() == nil)
	Settings:GetDB().profile.minimap.position = nil

	----------------------------------------------------------------------------
	-- The settings window
	----------------------------------------------------------------------------
	-- The first opening picks the tab by role: here, a plain raider.
	local realAmLootMaster, realAmCouncil = ALC.Council.AmLootMaster, ALC.Council.AmCouncil
	ALC.Council.AmLootMaster = function() return false end
	ALC.Council.AmCouncil = function() return false end
	Win:Show()
	frame = Win.rows[1].parent.parent
	check("the window opens", Win:IsShown() and #Win.rows == 6)
	check("the council list shows the member", Win.rows[1].name:GetText() == "Veyra Moo" and Win.rows[1]:IsShown() and not Win.rows[2]:IsShown())
	check("the count is shown", frame.count:GetText() == "1/39")
	check("the empty hint is hidden", frame.empty:IsShown() == false)
	check("the mark is in the header", frame.logo.texture == ALC.UI.LOGO)

	-- Settings are grouped by who they matter for: everyone, the council, the loot master.
	local function shown(widget) return widget:IsShown() end
	check("a plain raider starts on the Everyone tab", Win:GetTab() == "everyone" and frame.role:GetText() == "You are a raider")
	check("Everyone has the look and debug settings", shown(frame.minimap) and shown(frame.fontButton) and shown(frame.debug))
	check("and none of the council's or the loot master's", not shown(frame.keepOpen) and not shown(frame.input) and not shown(frame.autoOpen)
		and not shown(frame.listBox) and not shown(frame.qualityButton))
	check("the tab says who it is for", frame.tabNote:GetText():find("Nobody else is affected", 1, true) ~= nil)
	local tabButtons = Win.tabButtons
	check("four tabs, the current one selected", #tabButtons == 4 and tabButtons[1].selected == true and tabButtons[2].selected == false)
	tabButtons[2].scripts.OnClick(tabButtons[2])
	check("the Council tab has the voting window setting", Win:GetTab() == "council" and shown(frame.keepOpen) and not shown(frame.minimap) and not shown(frame.input))
	tabButtons[3].scripts.OnClick(tabButtons[3])
	check("the Loot master tab has the council list and the loot settings", Win:GetTab() == "lm" and shown(frame.input) and shown(frame.listBox)
		and shown(frame.autoOpen) and shown(frame.qualityButton) and not shown(frame.keepOpen) and not shown(frame.minimap))
	check("each tab is its own height", Win.heights.lm ~= Win.heights.council and frame:GetHeight() == Win.heights.lm)
	Win:SetTab("nonsense")
	check("an unknown tab is ignored", Win:GetTab() == "lm")
	ALC.Council.AmCouncil = function() return true end
	Win:Refresh()
	check("a council member is told so", frame.role:GetText() == "You are on the council" and Win:GetTab() == "lm")
	ALC.Council.AmLootMaster = function() return true end
	Win:Refresh()
	check("the loot master is told so", frame.role:GetText() == "You are the loot master")
	ALC.Council.AmLootMaster, ALC.Council.AmCouncil = realAmLootMaster, realAmCouncil
	Win:Refresh()
	tabButtons[1].scripts.OnClick(tabButtons[1])
	check("back on the Everyone tab", Win:GetTab() == "everyone" and shown(frame.minimap) and not shown(frame.input))
	tabButtons[3].scripts.OnClick(tabButtons[3]) -- the tests below work on the council list

	-- Adding.
	frame.input:SetText("kaelis moo")
	frame.input.scripts.OnEnterPressed(frame.input)
	check("Enter in the box adds the player", Settings:GetCouncil()[2] == "Kaelis Moo" and Win.rows[2].name:GetText() == "Kaelis Moo")
	check("the box is emptied", frame.input:GetText() == "")
	frame.input:SetText("jonatan moo")
	frame.add.scripts.OnClick(frame.add)
	check("the Add button adds too", Settings:GetCouncil()[3] == "Jonatan Moo")
	frame.input:SetText("veyra moo")
	frame.add.scripts.OnClick(frame.add)
	check("a duplicate is explained", frame.feedback:GetText():find("already", 1, true) ~= nil and #Settings:GetCouncil() == 3)
	frame.input:SetText("   ")
	frame.add.scripts.OnClick(frame.add)
	check("an empty name is explained", frame.feedback:GetText():find("Type", 1, true) ~= nil)
	frame.input:SetText("Bad|Name")
	frame.add.scripts.OnClick(frame.add)
	check("an invalid name is explained", frame.feedback:GetText():find("valid", 1, true) ~= nil and #Settings:GetCouncil() == 3)
	frame.input:SetText("ashvane moo")
	frame.add.scripts.OnClick(frame.add)
	check("a good name clears the message", frame.feedback:GetText() == "")

	-- Add target.
	UnitIsPlayer = function() return false end
	frame.addTarget.scripts.OnClick(frame.addTarget)
	check("a target that is not a player is refused", frame.feedback:GetText():find("Target a player", 1, true) ~= nil)
	UnitIsPlayer = function() return true end
	local realUnitName = UnitName
	UnitName = function(unit) if unit == "target" then return "Lyra", "Moo" end return realUnitName(unit) end
	frame.addTarget.scripts.OnClick(frame.addTarget)
	check("a player target is added, with the full name", Settings:GetCouncil()[5] == "Lyra Moo")
	frame.addTarget.scripts.OnClick(frame.addTarget)
	check("the same target twice is explained", frame.feedback:GetText():find("already", 1, true) ~= nil)
	UnitName = realUnitName

	-- Removing and scrolling.
	check("five members now", #Settings:GetCouncil() == 5 and frame.count:GetText() == "5/39")
	Win.rows[1].remove.scripts.OnClick(Win.rows[1].remove)
	check("the x removes a member", #Settings:GetCouncil() == 4 and Win.rows[1].name:GetText() == "Kaelis Moo")
	for i = 1, 8 do Settings:AddCouncilMember("Extra" .. string.rep("z", i) .. " Moo") end
	check("a long list shows six rows", Win.rows[6]:IsShown() and #Settings:GetCouncil() == 12)
	local first = Win.rows[1].name:GetText()
	frame.scripts.OnMouseWheel(frame, -1)
	check("scrolling moves the list", Win.rows[1].name:GetText() ~= first)
	for _ = 1, 20 do frame.scripts.OnMouseWheel(frame, -1) end
	check("scrolling stops at the end", Win.rows[6].name:GetText() == Settings:GetCouncil()[12])
	for _ = 1, 20 do frame.scripts.OnMouseWheel(frame, 1) end
	check("and at the top", Win.rows[1].name:GetText() == first)

	-- The council list changes from outside (a slash command): the window follows.
	H.slash("council add Outside Moo")
	check("the window follows changes made elsewhere", frame.count:GetText() == "13/39")
	H.slash("council remove Outside Moo")

	-- Loot options.
	_G.ITEM_QUALITY0_DESC, _G.ITEM_QUALITY1_DESC, _G.ITEM_QUALITY2_DESC, _G.ITEM_QUALITY3_DESC, _G.ITEM_QUALITY4_DESC, _G.ITEM_QUALITY5_DESC = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary"
	Win:Refresh()
	check("the threshold starts at epic", Settings:GetQualityThreshold() == 4 and frame.qualityButton.label:GetText() == "Epic")
	frame.qualityButton.scripts.OnClick(frame.qualityButton)
	local menuRows = ALC.ContextMenu.rows
	check("the drop-down lists the three qualities under a caption", ALC.ContextMenu:IsShown() and menuRows[1].header == true and menuRows[2].label:GetText() == "Uncommon"
		and menuRows[4].label:GetText():find("Epic", 1, true) ~= nil)
	check("the current one is marked", menuRows[4].label:GetText() ~= "Epic")
	menuRows[3].scripts.OnClick(menuRows[3])
	check("a choice sets the threshold and closes the list", Settings:GetQualityThreshold() == 3 and frame.qualityButton.label:GetText() == "Rare" and not ALC.ContextMenu:IsShown())
	H.slash("quality uncommon")
	check("the window follows /alc quality", frame.qualityButton.label:GetText() == "Uncommon")
	Settings:SetQualityThreshold(4)

	check("auto open starts on", frame.autoOpen:IsChecked() == true)
	frame.autoOpen.scripts.OnClick(frame.autoOpen)
	check("its checkbox switches it off", Settings:GetAutoOpenLootWindow() == false and frame.autoOpen:IsChecked() == false)
	frame.autoOpen.scripts.OnClick(frame.autoOpen)
	check("and on again", Settings:GetAutoOpenLootWindow() == true)

	-- Debug.
	check("debug starts off", frame.debug:IsChecked() == false)
	frame.debug.scripts.OnClick(frame.debug)
	check("its checkbox switches it on", Settings:IsDebug() == true)
	H.slash("debug off")
	check("the window follows /alc debug", frame.debug:IsChecked() == false)
	local chat = #H.chat
	frame.showLog.scripts.OnClick(frame.showLog)
	check("Show log prints the log", #H.chat > chat)
	ALC.Debug:Log("Test", "something")
	frame.clearLog.scripts.OnClick(frame.clearLog)
	check("Clear log empties it", #ALC.Debug:GetLines() == 0)

	-- Keeping the voting window open after an award.
	check("closing the voting window after an award is the default", frame.keepOpen:IsChecked() == false and Settings:GetKeepCouncilOpen() == false)
	frame.keepOpen.scripts.OnClick(frame.keepOpen)
	check("its checkbox keeps the window open", Settings:GetKeepCouncilOpen() == true and frame.keepOpen:IsChecked() == true)
	Settings:SetKeepCouncilOpen(false)
	check("the window follows a change from elsewhere", frame.keepOpen:IsChecked() == false)

	-- Fonts: the list, and how a change reaches every text.
	local UI = ALC.UI
	local choices = UI.GetFontChoices()
	check("the list starts with the game's own font", choices[1].path == nil and choices[1].name == "Game default")
	check("then four fonts of the game", #choices == 5 and choices[2].name == "Friz Quadrata" and choices[3].path == "Fonts\\ARIALN.TTF")
	check("a font name is found from its path", UI.FontName(nil) == "Game default" and UI.FontName("fonts\\arialn.ttf") == "Arial Narrow"
		and UI.FontName("Interface\\AddOns\\Some\\thing.ttf") == "thing.ttf")

	local lsm = LibStub:NewLibrary("LibSharedMedia-3.0", 1)
	function lsm:HashTable()
		return {
			Zeta = "Interface\\AddOns\\X\\z.ttf", Alpha = "Interface\\AddOns\\X\\a.ttf", Beta = "Interface\\AddOns\\X\\b.ttf",
			Gamma = "Interface\\AddOns\\X\\g.ttf", Delta = "Interface\\AddOns\\X\\d.ttf", Epsilon = "Interface\\AddOns\\X\\e.ttf",
			Copy = "FONTS\\frizqt__.ttf", -- the same file as a built-in one
		}
	end
	choices = UI.GetFontChoices()
	check("fonts from LibSharedMedia are added, sorted by name", #choices == 11 and choices[6].name == "Alpha" and choices[11].name == "Zeta")
	check("a file that is already in the list is not added twice", (function()
		for _, choice in ipairs(choices) do if choice.name == "Copy" then return false end end
		return true
	end)())

	local sample = UI.NewText(UIParent, 12)
	check("a text starts in the game's font", sample.font[1] == STANDARD_TEXT_FONT)
	UI.SetFont("Fonts\\ARIALN.TTF")
	check("a change of font reaches texts that already exist", sample.font[1] == "Fonts\\ARIALN.TTF" and sample.font[2] == 12)
	check("and texts made afterwards", UI.NewText(UIParent, 14).font[1] == "Fonts\\ARIALN.TTF")
	UI.SetFont("Fonts\\BAD.ttf")
	check("a font the game cannot load falls back to the default", sample.font[1] == STANDARD_TEXT_FONT)
	UI.SetFont(nil)
	check("nil goes back to the game's own font", sample.font[1] == STANDARD_TEXT_FONT and UI.GetFont() == STANDARD_TEXT_FONT)

	Settings:SetFont("Fonts\\ARIALN.TTF")
	check("the setting changes the font everywhere", UI.GetFont() == "Fonts\\ARIALN.TTF" and sample.font[1] == "Fonts\\ARIALN.TTF")
	Settings:SetFont("")
	check("an empty setting means the game's font", Settings:GetFont() == nil and sample.font[1] == STANDARD_TEXT_FONT)

	-- The font list in the settings window.
	check("the button names the font in use", frame.fontButton.label:GetText() == "Game default")
	frame.fontButton.scripts.OnClick(frame.fontButton)
	local menu = Win.fontMenu()
	check("the button opens a list", menu ~= nil and menu:IsShown())
	check("with eight rows and a scrollbar for the rest", menu.rows[8]:IsShown() and menu.scroll:IsShown())
	check("each font is listed by name", menu.rows[1].name:GetText() == "Game default" and menu.rows[2].name:GetText() == "Friz Quadrata")
	check("and shown as itself", menu.rows[3].name.font[1] == "Fonts\\ARIALN.TTF" and menu.rows[1].name.font[1] == STANDARD_TEXT_FONT)
	check("the one in use is marked", menu.rows[1].selected == true and menu.rows[3].selected == false)
	menu.rows[3].scripts.OnClick(menu.rows[3])
	check("choosing a font sets it and closes the list", Settings:GetFont() == "Fonts\\ARIALN.TTF" and not menu:IsShown() and UI.GetFont() == "Fonts\\ARIALN.TTF")
	check("the button follows", frame.fontButton.label:GetText() == "Arial Narrow")
	frame.fontButton.scripts.OnClick(frame.fontButton)
	check("reopened, the chosen font is marked", menu.rows[3].selected == true and menu.rows[1].selected == false)
	menu.scripts.OnMouseWheel(menu, -1)
	check("the list scrolls", menu.rows[1].name:GetText() == "Friz Quadrata")
	for _ = 1, 10 do menu.scripts.OnMouseWheel(menu, -1) end
	check("to the end", menu.rows[8].name:GetText() == "Zeta")
	local bar = menu.scroll
	H.cursor = { 0, bar:GetTop() + 50 }
	bar.scripts.OnMouseDown(bar)
	bar.scripts.OnMouseUp(bar)
	check("the scrollbar goes back to the top", menu.rows[1].name:GetText() == "Game default")
	menu.rows[1].scripts.OnClick(menu.rows[1])
	check("the first entry gives the game's font back", Settings:GetFont() == nil and UI.GetFont() == STANDARD_TEXT_FONT)
	frame.fontButton.scripts.OnClick(frame.fontButton)
	Win:Hide()
	check("closing the settings closes the list", not menu:IsShown())
	Win:Show()
	LibStub.libs["LibSharedMedia-3.0"], LibStub.minors["LibSharedMedia-3.0"] = nil, nil

	-- Position and being open across a reload.
	frame.header.scripts.OnDragStop(frame.header)

	check("the position is saved", Settings:GetWindowPosition("settings") ~= nil)
	Win:Hide()
	check("closing is remembered", Settings:GetWindowShown("settings") == false)
	H.slash("settings")
	check("/alc settings opens it", Win:IsShown())
	Win:OnEnteringWorld(false, false)
	frame:Hide()
	Win:OnEnteringWorld(false, false)
	check("a zone change does not reopen it", not Win:IsShown())
	Win:OnEnteringWorld(false, true)
	check("a reload reopens it when it was open", Win:IsShown())
	H.slash("settings")
	check("/alc settings closes it", not Win:IsShown())

	----------------------------------------------------------------------------
	-- The window menu
	----------------------------------------------------------------------------
	local button = Button.button
	check("the minimap button exists and is shown", button ~= nil and button:IsShown())
	Launcher:Show()
	local rows = Launcher.rows
	check("the menu has seven entries", #rows == 7 and Launcher:IsShown())
	check("loot, history, trade queue and settings are always available", rows[1].enabled and rows[4].enabled and rows[5].enabled and rows[6].enabled and rows[7].enabled)
	check("voting and response need a session", not rows[2].enabled and not rows[3].enabled)
	check("and say why", rows[2].reason ~= nil and rows[3].reason ~= nil)
	rows[2].scripts.OnEnter(rows[2])
	check("the reason is a tooltip", GameTooltip.text == rows[2].reason)
	rows[2].scripts.OnClick(rows[2])
	check("a greyed entry does nothing", Launcher:IsShown() and not ALC.CouncilWindow:IsShown())
	check("the icons come from the media folder", rows[1].icon.texture == ALC.UI.ICONS .. "loot" and rows[4].icon.texture == ALC.UI.ICONS .. "history" and rows[5].icon.texture == ALC.UI.ICONS .. "trade" and rows[6].icon.texture == ALC.UI.ICONS .. "addon_check" and rows[7].icon.texture == ALC.UI.ICONS .. "settings")

	rows[1].scripts.OnClick(rows[1])
	check("the loot entry opens the loot window and closes the menu", ALC.LootWindow:IsShown() and not Launcher:IsShown())
	ALC.LootWindow:Hide()
	Launcher:Show()
	rows[7].scripts.OnClick(rows[7])
	check("the settings entry opens settings", Win:IsShown() and not Launcher:IsShown())
	Win:Hide()

	Launcher:Show()
	rows[4].scripts.OnClick(rows[4])
	local council = ALC.CouncilWindow
	check("the history entry opens the history, even without a session", council:IsShown() and council:GetTab() == "history" and not Launcher:IsShown())
	local historyFrame = council.historyRows[1].parent
	check("which is empty on a fresh install", historyFrame.historyEmpty:IsShown() and historyFrame.historyCount:GetText() == "0 awards")
	Launcher:Show()
	rows[4].scripts.OnClick(rows[4])
	check("choosing it again closes it", not council:IsShown())
	Launcher:Show()
	rows[5].scripts.OnClick(rows[5])
	check("the trade queue entry opens the trade queue", council:IsShown() and council:GetTab() == "trades" and not Launcher:IsShown())
	check("which is empty on a fresh install", historyFrame.tradeEmpty:IsShown() and historyFrame.tradeCount:GetText() == "0 waiting")
	Launcher:Show()
	rows[5].scripts.OnClick(rows[5])
	check("and choosing it again closes it", not council:IsShown())

	Launcher:Toggle()
	check("Toggle opens the menu", Launcher:IsShown())
	Launcher:Toggle()
	check("and closes it", not Launcher:IsShown())
	H.slash("menu")
	check("/alc menu opens it", Launcher:IsShown())
	Launcher:Hide()

	-- With a session the windows become available.
	UnitName = function(unit) if unit == "player" then return "Tester", "Moo" end end
	UnitClass = function() return "Rogue", "ROGUE" end
	Settings:GetDB().profile.council = {}
	C_Item.GetItemInfoInstant = function(item)
		local id = tonumber(item) or tonumber(tostring(item):match("item:(%d+)"))
		if id == 200 then return id, "Armor", "Plate", "INVTYPE_HEAD", 133101 end
	end
	check("start a session", ALC.Sessions:Start(200) == true)
	Launcher:Show()
	check("now every entry is available", rows[1].enabled and rows[2].enabled and rows[3].enabled and rows[4].enabled and rows[5].enabled and rows[6].enabled)
	check("and none is explained", rows[2].reason == nil and rows[3].reason == nil)
	Launcher:Hide()
	ALC.Sessions:Cancel("done")

	----------------------------------------------------------------------------
	-- The minimap button
	----------------------------------------------------------------------------
	check("it is a free button, not a child of the minimap", button.parent == UIParent)
	check("a small square, like the other minimap buttons", button.w == 30 and button.h == 30 and button.bg ~= nil and button.border ~= nil)
	check("with the ALC mark in it", button.icon.texture == ALC.UI.MEDIA .. "wow\\mark")
	check("it can be dragged with the left button and stays on screen", button.movable == true)
	check("until moved it sits just left of the minimap",
		button.point[1] == "TOPRIGHT" and button.point[2] == Minimap and button.point[3] == "TOPLEFT")

	-- Dragging: it moves with the mouse and stays where it is dropped.
	button.scripts.OnDragStart(button)
	check("dragging starts the move", button.moving == true)
	button:ClearAllPoints()
	button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 300, 200) -- where the player let go
	button.scripts.OnDragStop(button)
	check("letting go stops the move", button.moving == false)
	saved = Settings:GetButtonPosition()
	check("and the drop place is saved", saved ~= nil and saved.point == "BOTTOMLEFT" and saved.relPoint == "BOTTOMLEFT" and saved.x == 300 and saved.y == 200)
	Button:Refresh()
	check("it is placed there again", button.point[1] == "BOTTOMLEFT" and button.point[2] == UIParent and button.point[4] == 300 and button.point[5] == 200)

	-- The menu opens away from the screen edge the button is near.
	UIParent:SetSize(1920, 1080)
	button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 50, -50)
	button.centerY, button.centerX = 1000, 60 -- near the top left
	Launcher:Show(button)
	local menuFrame = Launcher.rows[1].parent
	check("near the top left the menu opens down and to the right", menuFrame.point[1] == "TOPLEFT" and menuFrame.point[3] == "BOTTOMLEFT")
	Launcher:Hide()
	button.centerY, button.centerX = 100, 1800 -- near the bottom right
	Launcher:Show(button)
	check("near the bottom right it opens up and to the left", menuFrame.point[1] == "BOTTOMRIGHT" and menuFrame.point[3] == "TOPRIGHT")
	Launcher:Hide()
	button.centerY, button.centerX = nil, nil
	UIParent:SetSize(100, 20)

	-- Clicking.
	button.scripts.OnClick(button, "LeftButton")
	check("left click opens the window menu", Launcher:IsShown())
	button.scripts.OnClick(button, "LeftButton")
	check("left click again closes it", not Launcher:IsShown())
	button.scripts.OnClick(button, "RightButton")
	check("right click opens settings", Win:IsShown() and not Launcher:IsShown())
	button.scripts.OnClick(button, "RightButton")
	check("right click again closes settings", not Win:IsShown())
	Launcher:Show()
	button.scripts.OnClick(button, "RightButton")
	check("right click with the menu open closes the menu", not Launcher:IsShown() and Win:IsShown())
	Win:Hide()

	button.scripts.OnEnter(button)
	check("hovering shows what the clicks do", GameTooltip.text == "Arbiter Loot Council")
	button.scripts.OnLeave(button)

	-- Showing and hiding.
	H.slash("minimap")
	check("/alc minimap hides the button", button:IsShown() == false and Settings:IsMinimapHidden() == true)
	H.slash("minimap")
	check("and shows it again", button:IsShown() == true and Settings:IsMinimapHidden() == false)
	Win:Show()
	frame = Win.rows[1].parent.parent
	frame.minimap.scripts.OnClick(frame.minimap)
	check("the checkbox in settings hides it", button:IsShown() == false and frame.minimap:IsChecked() == false)
	H.slash("minimap")
	check("the checkbox follows /alc minimap", frame.minimap:IsChecked() == true and button:IsShown() == true)
	Win:Hide()

	-- The position is remembered across a reload.
	Settings:SetButtonPosition("CENTER", "CENTER", -40, 75)
	H.reload()
	local reloaded = ALC.MinimapButton.button
	check("the drop place survives a reload", ALC.Settings:GetButtonPosition().x == -40)
	check("and the button is placed there", reloaded ~= nil and reloaded.point[1] == "CENTER" and reloaded.point[2] == UIParent
		and reloaded.point[4] == -40 and reloaded.point[5] == 75)
	ALC.Settings:SetMinimapHidden(true)
	H.reload()
	check("a hidden button stays hidden after a reload", ALC.MinimapButton.button:IsShown() == false)

	-- The chosen font is used again after a reload.
	ALC.Settings:SetFont("Fonts\\ARIALN.TTF")
	H.reload()
	check("the font survives a reload", ALC.UI.GetFont() == "Fonts\\ARIALN.TTF" and ALC.UI.NewText(UIParent, 12).font[1] == "Fonts\\ARIALN.TTF")
end

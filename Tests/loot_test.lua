-- LootDetection (the item list) and the loot window, on the real modules.
-- Runs before the Comm tests, which replace Council and Sessions with stand-ins.

return function(check, H)
	local LD, Win = ALC.LootDetection, ALC.LootWindow
	local Sessions, Council, Comm = ALC.Sessions, ALC.Council, ALC.Comm
	local STATUS = LD.STATUS
	local ME = "Tester Moo"

	----------------------------------------------------------------------------
	-- Fake item data and loot window
	----------------------------------------------------------------------------
	local db = {
		[19019] = { "Thunderfury, Blessed Blade of the Windseeker", 5, "Weapon", "One-Handed Swords", "INVTYPE_WEAPON", 135349 },
		[200] = { "Crown of Destruction", 4, "Armor", "Mail", "INVTYPE_HEAD", 133101 },
		[100] = { "Band of Accuria", 3, "Armor", "Miscellaneous", "INVTYPE_FINGER", 133345 },
		[300] = { "Small Furry Paw", 1, "Quest", "Quest", "INVTYPE_NON_EQUIP_IGNORE", 133648 },
	}
	INVTYPE_NON_EQUIP_IGNORE = "" -- the client gives items that cannot be worn an empty slot name
	INVTYPE_WEAPON, INVTYPE_HEAD, INVTYPE_FINGER = "One-Hand", "Head", "Finger"
	local requested = {}
	local function idOf(item) return tonumber(item) or tonumber(tostring(item):match("item:(%d+)")) end
	C_Item.GetItemInfo = function(item)
		local id = idOf(item)
		local d = id and db[id]
		if d then return d[1], "|Hitem:" .. id .. "|h[" .. d[1] .. "]|h", d[2], 60, 0, d[3], d[4], 1, d[5], d[6] end
	end
	C_Item.GetItemInfoInstant = function(item)
		local id = idOf(item)
		local d = id and db[id]
		if d then return id, d[3], d[4], d[5], d[6] end
	end
	C_Item.RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end

	local slots = {}
	GetNumLootItems = function() return #slots end
	LootSlotHasItem = function(i) return slots[i] ~= nil and slots[i].link ~= nil end
	GetLootSlotLink = function(i) return slots[i].link end
	GetLootSourceInfo = function(i) return slots[i].guid, 1 end
	GetZoneText = function() return "Molten Core" end
	UnitExists = function() return false end
	UnitIsDead = function() return false end

	local function link(id, quality) return "|cnIQ" .. quality .. ":|Hitem:" .. id .. "::::::::60:::::::|h[Item " .. id .. "]|h|r" end
	local function corpse(guid, ...)
		slots = {}
		for _, id in ipairs({ ... }) do slots[#slots + 1] = { link = link(id, db[id][2]), guid = guid } end
	end

	-- We are the loot master of a party with group loot (the leader is the loot master).
	H.inGroup = true
	local leader = ME
	Council.GetLootMethodInfo = function() return 3 end
	Council.GetLeaderName = function() return leader end
	Comm.GetGroupNames = function() return { ME } end
	Comm:InvalidateRoster()

	ALC.Settings:SetQualityThreshold(4) -- an earlier test left it at legendary
	local added, changes = {}, 0
	local listener = {}
	ALC.Events.Register(listener, "ALC_LOOT_ADDED", function(_, count) added[#added + 1] = count end)
	ALC.Events.Register(listener, "ALC_LOOT_CHANGED", function() changes = changes + 1 end)

	local function reset()
		if Sessions:IsActive() then Sessions:Cancel("test reset") end
		LD:Clear()
		local store = ALC.Settings:GetLootStore()
		store.seen, store.seenCount, store.hidden, store.boss = {}, 0, 0, nil
		added, changes = {}, 0
		H.sent = {}
	end
	reset()

	----------------------------------------------------------------------------
	-- Parsing
	----------------------------------------------------------------------------
	local parsed = ALC:ParseItems(link(19019, 5) .. " and " .. link(200, 4))
	check("two links parsed", #parsed == 2 and parsed[1].itemID == 19019 and parsed[2].itemID == 200)
	check("the link is kept for its colour", parsed[1].link:find("IQ5", 1, true) ~= nil)
	check("item strings parsed", ALC:ParseItems("item:200:0:0")[1].itemID == 200)
	local ids = ALC:ParseItems("19019 200")
	check("plain ids parsed", #ids == 2 and ids[2].itemString == "item:200")
	check("garbage parses to nothing", #ALC:ParseItems("hello world") == 0 and #ALC:ParseItems(nil) == 0)
	check("quality read from a new style link", LD.QualityFromLink(link(1, 4)) == 4)
	check("quality read from a colour code", LD.QualityFromLink("|cffa335ee|Hitem:1|h[x]|h|r") == 4)
	check("no quality without a colour", LD.QualityFromLink("item:1") == nil)

	----------------------------------------------------------------------------
	-- Loot windows
	----------------------------------------------------------------------------
	H.inGroup = false
	corpse("Creature-A", 19019, 100, 200)
	LD:OnLootOpened()
	check("loot outside a group is ignored", #LD:GetItems() == 0)

	H.inGroup = true
	leader = "Ashvane Moo"
	LD:OnLootOpened()
	check("loot when you are not the loot master is ignored", #LD:GetItems() == 0)

	leader = ME
	LD:OnEncounterEnd("Ragnaros", 1)
	LD:OnLootOpened()
	local items = LD:GetItems()
	check("items at or above the threshold are listed", #items == 2 and items[1].itemID == 19019 and items[2].itemID == 200)
	check("lower items are only counted", LD:GetHiddenCount() == 1)
	check("boss named from the encounter", LD:GetBossName() == "Ragnaros")
	check("entries start pending", items[1].status == STATUS.PENDING and items[1].source == "loot")
	check("quality read from the link", items[1].quality == 5 and items[2].quality == 4)
	check("ADDED fired with the count", added[#added] == 2)

	local countBefore = #LD:GetItems()
	LD:OnLootOpened()
	check("re-opening the same corpse adds nothing", #LD:GetItems() == countBefore and LD:GetHiddenCount() == 1)

	-- The threshold decides what is listed.
	ALC.Settings:SetQualityThreshold(3)
	corpse("Creature-B", 100)
	LD:OnLootOpened()
	check("a lower threshold lists rare items", #LD:GetItems() == 3)
	ALC.Settings:SetQualityThreshold(4)

	-- Without an encounter the zone names the loot.
	reset()
	LD:OnEncounterEnd("Wipe", 0)
	H.clock = H.clock + 5000
	corpse("Creature-C", 200)
	LD:OnLootOpened()
	check("boss falls back to the zone", LD:GetBossName() == "Molten Core")

	-- A secret boss name (target or encounter) is never kept: the zone names the loot instead.
	local SECRET = {}
	local realSecret, realExists, realDead, realName = issecretvalue, UnitExists, UnitIsDead, UnitName
	issecretvalue = function(v) return v == SECRET end
	UnitExists = function() return true end
	UnitIsDead = function() return true end
	UnitName = function(unit) if unit == "target" then return SECRET end return realName(unit) end
	reset()
	H.clock = H.clock + 5000
	corpse("Creature-D", 200)
	LD:OnLootOpened()
	check("a secret target name is not used as the boss", LD:GetBossName() == "Molten Core")
	LD:OnEncounterEnd(SECRET, 1)
	reset()
	corpse("Creature-E", 200)
	LD:OnLootOpened()
	check("a secret encounter name is not used as the boss", LD:GetBossName() == "Molten Core")
	issecretvalue, UnitExists, UnitIsDead, UnitName = realSecret, realExists, realDead, realName

	-- A looted Bind-on-Pickup item can be traded for two hours: the loot window counts it down.
	local realInfo = C_Item.GetItemInfo
	local bind = 1
	C_Item.GetItemInfo = function() return "Crown", "|Hitem:200|h[Crown]|h", 4, 60, 0, "Armor", "Plate", 1, "INVTYPE_HEAD", 133101, 0, 4, 1, bind end
	local bopEntry = LD:GetItems()[1]
	bopEntry.addedAt = time() - 600
	local left = LD:GetTradeTimeLeft(bopEntry)
	check("a looted BoP item has about 1h 50m left", left ~= nil and left > 6500 and left <= 6600)
	bopEntry.addedAt = time() - 8000
	check("an expired window counts down to zero", LD:GetTradeTimeLeft(bopEntry) == 0)
	bind = 2
	check("other items get no timer", LD:GetTradeTimeLeft(bopEntry) == nil)
	bind = 1
	bopEntry.source = "manual"
	check("items added by hand get one too, counted from when they were added", LD:GetTradeTimeLeft(bopEntry) ~= nil)
	bopEntry.source = "loot"
	local fmt = ALC.LootWindow.FormatTradeTime
	check("the time reads as hours and minutes", fmt(6100):find("1h 41m", 1, true) ~= nil and fmt(1500):find("25m", 1, true) ~= nil and fmt(30):find("<1m", 1, true) ~= nil)
	check("expired is said so", fmt(0):find("expired", 1, true) ~= nil)
	C_Item.GetItemInfo = realInfo

	-- The game's own loot threshold follows ALC's when the group leader changes it.
	local gameSet, gameNow = nil, 2
	local realLeader = UnitIsGroupLeader
	UnitIsGroupLeader = function() return true end
	SetLootThreshold = function(q) gameSet = q end
	GetLootThreshold = function() return gameNow end
	ALC.Settings:SetQualityThreshold(3)
	check("the game's threshold is set to the new one", gameSet == 3)
	gameNow, gameSet = 4, nil
	ALC.Settings:SetQualityThreshold(4)
	check("and left alone when it already matches", gameSet == nil)
	UnitIsGroupLeader = function() return false end
	gameNow = 2
	ALC.Settings:SetQualityThreshold(3)
	check("only the group leader can change it", gameSet == nil)
	ALC.Settings:SetQualityThreshold(4)
	UnitIsGroupLeader, SetLootThreshold, GetLootThreshold = realLeader, nil, nil

	----------------------------------------------------------------------------
	-- Adding by hand
	----------------------------------------------------------------------------
	reset()
	local n, msg = LD:AddFromText("nonsense")
	check("nothing to add is reported", n == 0 and msg ~= nil and #LD:GetItems() == 0)
	n = LD:AddFromText(link(19019, 5) .. link(200, 4))
	check("two links added", n == 2 and #LD:GetItems() == 2 and added[#added] == 2)
	check("manual source", LD:GetItems()[1].source == "manual")
	H.slash("add 100")
	check("/alc add with an id", #LD:GetItems() == 3 and LD:GetItems()[3].itemID == 100)
	local chat = #H.chat
	H.slash("add")
	H.slash("add nonsense")
	check("/alc add prints usage and errors", #H.chat == chat + 2)

	----------------------------------------------------------------------------
	-- Item display
	----------------------------------------------------------------------------
	local d = LD:GetItemDisplay(LD:GetItems()[2])
	check("display: name, icon and quality", d.name == "Crown of Destruction" and d.icon == 133101 and d.quality == 4)
	check("display: slot and armor type", d.subtitle == "Head \194\183 Mail")
	check("display: weapon", LD:GetItemDisplay(LD:GetItems()[1]).subtitle == "One-Hand \194\183 One-Handed Swords")
	check("display: miscellaneous is left out", LD:GetItemDisplay(LD:GetItems()[3]).subtitle == "Finger")
	check("display: an item that cannot be worn has no leading separator",
		LD:GetItemDisplay({ itemString = "item:300", itemID = 300 }).subtitle == "Quest")
	LD:AddFromText("555")
	local unknown = LD:GetItemDisplay(LD:GetItems()[4])
	check("display: unknown item is requested from the client", unknown.name == nil and requested[#requested] == 555)
	LD:GetItemDisplay(LD:GetItems()[4])
	local requestsSoFar = #requested
	LD:GetItemDisplay(LD:GetItems()[4])
	check("an item is only requested once", #requested == requestsSoFar)

	----------------------------------------------------------------------------
	-- Sessions from the list
	----------------------------------------------------------------------------
	reset()
	LD:AddFromText(link(19019, 5) .. link(200, 4))
	local first, second = LD:GetItems()[1], LD:GetItems()[2]
	local ok = LD:StartSession(first.id)
	check("start a session from the list", ok == true and Sessions:IsActive() and Sessions:GetSession().items[1].itemID == 19019)
	check("the entry is in session", LD:GetEntry(first.id).status == STATUS.SESSION and LD:GetEntry(first.id).sid == Sessions:GetActiveSid())
	local okSecond, messageSecond = LD:StartSession(second.id)
	check("one item at a time", okSecond == false and messageSecond ~= nil and LD:GetEntry(second.id).status == STATUS.PENDING)
	check("removing an item in session is refused", LD:Remove(first.id) == false)

	Sessions:Cancel("changed my mind")
	check("cancelling puts the item back", LD:GetEntry(first.id).status == STATUS.PENDING)

	LD:StartSession(first.id)
	check("award ends it as awarded", Comm:SendRaid("AWARD", Sessions:GetActiveSid(), { item = 1, winner = "Veyra Moo", itemID = 19019, response = "BIS" }) == true)
	local awarded = LD:GetEntry(first.id)
	check("awarded with the winner", awarded.status == STATUS.AWARDED and awarded.winner == "Veyra Moo")
	check("the other item is still waiting", LD:GetEntry(second.id).status == STATUS.PENDING)

	-- A session started by hand shows up in the list.
	reset()
	H.slash("start 19019")
	local manual = LD:GetItems()
	check("/alc start creates an entry in session", #manual == 1 and manual[1].status == STATUS.SESSION and manual[1].source == "session")
	check("and announces it as added", added[#added] == 1)
	Sessions:Cancel("x")

	-- A waiting item of the same kind is used instead of a new entry.
	reset()
	LD:AddFromText("19019")
	H.slash("start 19019")
	check("an existing entry is reused", #LD:GetItems() == 1 and LD:GetItems()[1].status == STATUS.SESSION)
	Sessions:Cancel("x")

	----------------------------------------------------------------------------
	-- Cleaning up
	----------------------------------------------------------------------------
	reset()
	LD:AddFromText("19019 200 100")
	local list = LD:GetItems()
	LD:SetStatus(list[1].id, STATUS.AWARDED)
	LD:SetStatus(list[2].id, STATUS.TRADE)
	check("ClearFinished removes only awarded items", LD:ClearFinished() == 1 and #LD:GetItems() == 2)
	check("a pending item can be removed", LD:Remove(LD:GetItems()[2].id) == true and #LD:GetItems() == 1)
	check("Clear removes what is left", LD:Clear() == 1 and #LD:GetItems() == 0)

	-- New loot replaces a list where everything is handed out.
	reset()
	corpse("Creature-D", 19019)
	LD:OnLootOpened()
	LD:SetStatus(LD:GetItems()[1].id, STATUS.AWARDED)
	corpse("Creature-E", 200)
	LD:OnLootOpened()
	check("a finished list is replaced by new loot", #LD:GetItems() == 1 and LD:GetItems()[1].itemID == 200)
	corpse("Creature-F", 19019)
	LD:OnLootOpened()
	check("an unfinished list keeps its items", #LD:GetItems() == 2)

	----------------------------------------------------------------------------
	-- Saved list
	----------------------------------------------------------------------------
	reset()
	LD:AddFromText("19019 200")
	local store = ALC.Settings:GetLootStore()
	store.items[1].status = STATUS.SESSION
	store.items[1].starting = true
	LD:Init()
	check("a session does not survive a reload", LD:GetItems()[1].status == STATUS.PENDING and LD:GetItems()[1].starting == nil)
	check("the list survives a reload", #LD:GetItems() == 2)
	store.savedAt = store.savedAt - 9 * 3600
	LD:Init()
	check("an old list is dropped", #LD:GetItems() == 0)

	----------------------------------------------------------------------------
	-- The window
	----------------------------------------------------------------------------
	reset()
	local rows = Win.rows
	Win:Hide()
	check("the window can be hidden", not Win:IsShown())
	Win:Show()
	check("the window is shown, with a pool of rows to scroll through", Win:IsShown() and #rows == 24)
	check("empty list: no rows", not rows[1]:IsShown() and rows[1].entry == nil)
	local frame = rows[1].parent
	check("empty list: the hint is shown", frame.empty:IsShown() == true)

	Win:Hide()
	ALC.Settings:SetAutoOpenLootWindow(true)
	LD:AddFromText(link(19019, 5) .. link(200, 4) .. link(100, 3))
	check("new items open the window by themselves", Win:IsShown())
	check("one row per item", rows[1]:IsShown() and rows[3]:IsShown() and not rows[4]:IsShown())
	check("row shows the item", rows[2].name:GetText() == "Crown of Destruction" and rows[2].sub:GetText() == "Head \194\183 Mail")
	check("quality colours the name", rows[2].name.textColor[1] == 0.64 and rows[2].name.textColor[3] == 0.93)
	check("icon set", rows[1].icon.texture == 135349)
	check("pending row has a Start button", rows[1].start:IsShown() and rows[1].start.available == true and not rows[1].status:IsShown())
	check("cancel is not available without a session", frame.cancel.available == false)
	check("title without a boss", frame.title:GetText() == "LOOT")
	check("filter label", frame.label:GetText():find("AND ABOVE", 1, true) ~= nil)
	check("the list counts its items", frame.count:GetText() == "3 items")
	local tall = frame:GetHeight()

	Win:Hide()
	ALC.Settings:SetAutoOpenLootWindow(false)
	LD:AddFromText("19019")
	check("auto open can be switched off", not Win:IsShown())
	H.slash("loot")
	check("/alc loot opens the window", Win:IsShown())
	check("a taller list gives a taller window", frame:GetHeight() > tall)
	H.slash("loot")
	check("/alc loot closes it again", not Win:IsShown())
	H.slash("loot auto on")
	check("/alc loot auto on", ALC.Settings:GetAutoOpenLootWindow() == true)
	Win:Show()

	-- Clicking Start.
	rows[1].start.scripts.OnClick(rows[1].start)
	check("Start starts a session for that row", Sessions:IsActive() and Sessions:GetSession().items[1].itemID == 19019)
	check("the row shows In session", not rows[1].start:IsShown() and rows[1].status:GetText() == "In session" and rows[1].border ~= nil)
	check("the other rows cannot start", rows[2].start:IsShown() and rows[2].start.available == false)
	check("cancel is available for the loot master", frame.cancel.available == true and frame.hint:GetText() == "In session")
	local sessionFrames = rows[2].start
	sessionFrames.scripts.OnClick(sessionFrames)
	check("a disabled Start does nothing", LD:GetEntry(rows[2].entryId).status == STATUS.PENDING)

	frame.cancel.scripts.OnClick(frame.cancel)
	check("Cancel ends the session", not Sessions:IsActive())
	check("the row is back to pending", rows[1].start:IsShown() and rows[1].start.available == true)
	check("hint is back", frame.hint:GetText() == "")

	Comm:SendRaid("AWARD", (function() rows[1].start.scripts.OnClick(rows[1].start) return Sessions:GetActiveSid() end)(),
		{ item = 1, winner = "Veyra Moo", itemID = 19019, response = "BIS" })
	check("an awarded row shows Awarded and the winner", rows[1].status:GetText() == "Awarded" and rows[1].sub:GetText():find("Veyra Moo", 1, true) ~= nil)

	check("the remove button is big enough to hit", rows[2].remove:GetWidth() >= 24 and rows[2].remove:GetHeight() >= 24)
	-- Removing and hover.
	local removed = rows[2].entryId
	rows[2].remove.scripts.OnClick(rows[2].remove)
	check("the x button removes the item", LD:GetEntry(removed) == nil)
	rows[1].scripts.OnEnter(rows[1])
	check("hovering shows the item tooltip", GameTooltip.hyperlink == rows[1].entry.itemString)

	-- Scrolling a long list.
	reset()
	local many = {}
	for i = 1, 11 do many[i] = "19019" end
	LD:AddFromText(table.concat(many, " "))
	check("only eight rows are shown", rows[8]:IsShown() and #LD:GetItems() == 11)
	local firstId = rows[1].entryId
	frame.scripts.OnMouseWheel(frame, -1)
	check("scrolling moves the list", rows[1].entryId ~= firstId and rows[1].entryId == LD:GetItems()[2].id)
	for _ = 1, 10 do frame.scripts.OnMouseWheel(frame, -1) end
	check("scrolling stops at the end", rows[8].entryId == LD:GetItems()[11].id)
	for _ = 1, 10 do frame.scripts.OnMouseWheel(frame, 1) end
	check("and at the top", rows[1].entryId == LD:GetItems()[1].id)

	-- The scrollbar.
	local bar = frame.scroll
	check("a long list has a scrollbar", bar:IsShown() and bar.thumbHeight < bar:GetHeight() and bar.thumbHeight >= 20)
	check("the thumb starts at the top", bar.thumb.point[5] == 0 or bar.thumb.point[5] == -0)
	frame.scripts.OnMouseWheel(frame, -1)
	check("scrolling moves the thumb down", bar.thumb.point[5] < 0)
	frame.scripts.OnMouseWheel(frame, 1)
	H.cursor = { 0, bar:GetTop() - bar:GetHeight() } -- the mouse at the bottom of the track
	bar.scripts.OnMouseDown(bar)
	check("clicking the bottom of the track scrolls to the end", rows[8].entryId == LD:GetItems()[11].id)
	check("and following the mouse goes on while the button is down", bar.scripts.OnUpdate ~= nil)
	H.cursor = { 0, bar:GetTop() + 100 } -- above the track
	bar.scripts.OnUpdate(bar)
	check("dragging above the track goes back to the top", rows[1].entryId == LD:GetItems()[1].id)
	bar.scripts.OnMouseUp(bar)
	check("letting go stops following", bar.scripts.OnUpdate == nil)

	-- The grip: drag it to show more or fewer rows.
	local settings = ALC.Settings
	check("eight rows by default", settings:GetWindowOption("loot", "maxRows", 8) == 8)
	frame.grip.scripts.OnMouseDown(frame.grip)
	check("dragging anchors the window by its top edge", frame.point[1] == "TOPLEFT" and frame.point[3] == "BOTTOMLEFT" and frame.point[5] == 800)
	local topOfRows = 52 + 34 + 14 + 64 -- header, label, gap and footer
	H.cursor = { 0, 800 - topOfRows - 5 * 64 }
	frame.grip.scripts.OnUpdate(frame.grip)
	check("the mouse decides how many rows: five", settings:GetWindowOption("loot", "maxRows", 8) == 5 and rows[5]:IsShown() and not rows[6]:IsShown())
	check("the scrollbar follows", bar:IsShown() and bar:GetHeight() == 5 * 64 - 8)
	H.cursor = { 0, -5000 }
	frame.grip.scripts.OnUpdate(frame.grip)
	check("never more rows than the window is built with", settings:GetWindowOption("loot", "maxRows", 8) == 24 and rows[11]:IsShown() and not bar:IsShown())
	H.cursor = { 0, 5000 }
	frame.grip.scripts.OnUpdate(frame.grip)
	check("never fewer than three", settings:GetWindowOption("loot", "maxRows", 8) == 3 and rows[3]:IsShown() and not rows[4]:IsShown())
	frame.grip.scripts.OnMouseUp(frame.grip)
	check("letting go stops it and saves the position", frame.grip.scripts.OnUpdate == nil and settings:GetWindowPosition("loot").point == "TOPLEFT")
	frame.grip.scripts.OnEnter(frame.grip)
	frame.grip.scripts.OnLeave(frame.grip)
	settings:SetWindowOption("loot", "maxRows", 0) -- a damaged saved value
	Win:Refresh()
	check("a broken saved row count still shows at least three rows", rows[3]:IsShown() and not rows[4]:IsShown())
	settings:SetWindowOption("loot", "maxRows", 500)
	Win:Refresh()
	check("and never more than the window is built with", rows[24] ~= nil and #Win.rows == 24)
	settings:SetWindowOption("loot", "maxRows", 8)
	Win:Refresh()
	check("back to eight rows", rows[8]:IsShown() and not rows[9]:IsShown())
	check("the chosen rows are kept with the position", settings:GetWindowOption("loot", "maxRows", 8) == 8 and settings:GetWindowPosition("loot") ~= nil)

	-- Reloading: an open window comes back, a closed one stays closed.
	Win:Show()
	frame:Hide() -- what a reload does to the frame; the saved flag stays
	Win:OnEnteringWorld(false, true)
	check("a window that was open comes back after a reload", Win:IsShown())
	Win:Hide() -- the player closes it
	Win:OnEnteringWorld(false, true)
	check("a window the player closed stays closed", not Win:IsShown())
	Win:Show()
	frame:Hide()
	Win:OnEnteringWorld(false, false)
	check("a zone change does not reopen it", not Win:IsShown())
	Win:OnEnteringWorld(true, false)
	check("logging in reopens it", Win:IsShown())
	frame:Hide()
	LD:Clear()
	Win:OnEnteringWorld(false, true)
	check("nothing to show: it stays closed", not Win:IsShown())
	local settings = ALC.Settings
	settings:SetWindowPosition("probe", "TOP", "TOP", 1, 2)
	settings:SetWindowShown("probe", true)
	check("shown flag keeps the position", settings:GetWindowPosition("probe").x == 1 and settings:GetWindowShown("probe") == true)
	settings:SetWindowPosition("probe", "TOP", "TOP", 3, 4)
	check("moving keeps the shown flag", settings:GetWindowPosition("probe").x == 3 and settings:GetWindowShown("probe") == true)
	check("an unknown window is not shown", settings:GetWindowShown("nothing") == false)

	-- Moving the window is remembered.
	frame.header.scripts.OnDragStart(frame.header)
	check("dragging the header moves the window", frame.moving == true)
	frame.header.scripts.OnDragStop(frame.header)
	local pos = ALC.Settings:GetWindowPosition("loot")
	check("the position is saved when the window stops moving", frame.moving == false and pos ~= nil and pos.point == frame.point[1])

	-- Leave things as the next tests expect.
	ALC.Events.UnregisterAll(listener)
	Win:Hide()
	reset()
	H.inGroup = false
	C_Item.GetItemInfo = function() end
	C_Item.GetItemInfoInstant = nil
	C_Item.RequestLoadItemDataByID = nil
end

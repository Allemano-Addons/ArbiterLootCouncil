-- RaidUse: the question "Use Arbiter Loot Council in this raid?" to the loot master, and what No does.

return function(check, H)
	H.reload("fresh")
	local RU, Council, Sessions, LD = ALC.RaidUse, ALC.Council, ALC.Sessions, ALC.LootDetection

	local shown = {}
	StaticPopupDialogs = {}
	StaticPopup_Show = function(name) shown[#shown + 1] = name end
	local zone = { false, nil }
	IsInInstance = function() return zone[1], zone[2] end
	local method, masterLooter, leader = 3, nil, "Tester Moo"
	Council.GetLootMethodInfo = function() return method end
	Council.FindMasterLooter = function() return masterLooter end
	Council.GetLeaderName = function() return leader end
	H.inRaid = true

	check("ALC is on before any answer", RU:IsActive())

	-- The master looter
	RU:OnLootMethodChanged()
	check("the first look (login) asks nothing", #shown == 0)
	method, masterLooter = "master", "Tester Moo"
	RU:OnLootMethodChanged()
	check("becoming the master looter asks", #shown == 1 and shown[1] == "ALC_USE_IN_RAID")
	RU:OnLootMethodChanged()
	check("the same master looter again asks nothing more", #shown == 1)

	local dialog = StaticPopupDialogs.ALC_USE_IN_RAID
	dialog.OnCancel(nil, nil, "clicked")
	check("No turns ALC off for us", not RU:IsActive())
	local ok, why = Sessions:StartItems({})
	check("no session can start", ok == false and why:find("off for this raid", 1, true) ~= nil)
	local read = false
	GetNumLootItems = function() read = true return 0 end
	LD:OnLootOpened()
	check("a corpse is not read for the loot list", read == false)
	dialog.OnCancel(nil, nil, "timeout")
	check("the box closing for another reason changes nothing", not RU:IsActive())

	masterLooter = "Ashvane Moo"
	RU:OnLootMethodChanged()
	check("someone else becoming master looter asks us nothing", #shown == 1)
	masterLooter = "Tester Moo"
	RU:OnLootMethodChanged()
	check("becoming master looter again asks again", #shown == 2)
	dialog.OnAccept()
	check("Yes turns it on", RU:IsActive())
	LD:OnLootOpened()
	check("and corpses are read again", read == true)

	-- Entering a raid instance
	zone = { true, "raid" }
	RU:OnZone(false)
	check("entering a raid instance as the loot master asks", #shown == 3)
	RU:OnZone(false)
	check("a new area inside it asks nothing more", #shown == 3)
	zone = { false, nil }
	RU:OnZone(false)
	zone = { true, "raid" }
	RU:OnZone(true)
	check("a /reload inside does not ask", #shown == 3)
	zone = { false, nil }
	RU:OnZone(false)
	zone = { true, "party" }
	RU:OnZone(false)
	check("a dungeon asks nothing", #shown == 3)
	zone = { false, nil }
	RU:OnZone(false)
	method, masterLooter, leader = 3, nil, "Ashvane Moo"
	zone = { true, "raid" }
	RU:OnZone(false)
	check("not the loot master: no question", #shown == 3)
	leader = "Tester Moo"
	zone = { false, nil }
	RU:OnZone(false)
	zone = { true, "raid" }
	RU:OnZone(false)
	check("the raid leader is the loot master without master loot, and is asked", #shown == 4)

	-- The setting
	ALC.Settings:SetAskRaidUse(false)
	zone = { false, nil }
	RU:OnZone(false)
	zone = { true, "raid" }
	RU:OnZone(false)
	check("with the setting off nothing is asked and ALC is on", #shown == 4 and RU:IsActive())
	ALC.Settings:SetAskRaidUse(true)

	-- By hand, over a /reload, and after the group
	H.slash("off")
	check("/alc off", not RU:IsActive())
	H.slash("on")
	check("/alc on", RU:IsActive())
	H.slash("off")
	H.reload()
	check("the answer is kept over a /reload", not ALC.RaidUse:IsActive())
	ALC.RaidUse:Forget()
	check("leaving the group forgets it", ALC.RaidUse:IsActive())

	StaticPopupDialogs, StaticPopup_Show, IsInInstance, GetNumLootItems = nil, nil, nil, nil
	H.inRaid, H.inGroup = false, false
	H.reload("fresh")
end

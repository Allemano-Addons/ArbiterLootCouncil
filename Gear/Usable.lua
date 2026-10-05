-- Usable: whether a class can EVER use an item, for the "pass automatically on items I can never use" setting.
-- Only what a class can never wear or wield: plate for a priest, leather for a warlock, a two-handed sword for a rogue.
-- Rings, necklaces, trinkets and cloaks are for everybody and are never passed. An item whose type is not known here is
-- left alone (the answer stays with the player), and so is a class that is not in the table. Level is not considered: a
-- warrior who cannot wear plate yet will, so plate is not passed for a warrior.

local ALC = ALC
local L = ALC.L

local Usable = {}
ALC.Usable = Usable

-- Armor (item class 4): the types that are not for everybody, and who can wear each. Cloth, rings, necks, trinkets and
-- cloaks are for all, so they are not in the table.
local ARMOR_NAME = {
	[2] = L["leather"], [3] = L["mail"], [4] = L["plate"], [6] = L["shields"],
	[7] = L["librams"], [8] = L["idols"], [9] = L["totems"],
}
local function set(...) local t = {} for _, v in ipairs({ ... }) do t[v] = true end return t end
local ARMOR_FOR = {
	[2] = set("DRUID", "ROGUE", "HUNTER", "SHAMAN", "WARRIOR", "PALADIN"),
	[3] = set("HUNTER", "SHAMAN", "WARRIOR", "PALADIN"),
	[4] = set("WARRIOR", "PALADIN"),
	[6] = set("WARRIOR", "PALADIN", "SHAMAN"),
	[7] = set("PALADIN"),
	[8] = set("DRUID"),
	[9] = set("SHAMAN"),
}

-- Weapons (item class 2): the kinds there are, by item subclass, and what each class can use. Where the game's versions
-- differ the wider list is used, so that nothing is passed that somebody could use.
local WEAPON_NAME = {
	-- short, because they are shown on a row ("Auto-passed: 2H swords")
	[0] = L["1H axes"], [1] = L["2H axes"], [2] = L["bows"], [3] = L["guns"],
	[4] = L["1H maces"], [5] = L["2H maces"], [6] = L["polearms"], [7] = L["1H swords"],
	[8] = L["2H swords"], [10] = L["staves"], [13] = L["fist weapons"], [15] = L["daggers"],
	[16] = L["thrown"], [18] = L["crossbows"], [19] = L["wands"],
}
local WEAPONS_FOR = {
	WARRIOR = set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18),
	PALADIN = set(0, 1, 4, 5, 6, 7, 8),
	HUNTER = set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18),
	ROGUE = set(0, 2, 3, 4, 7, 13, 15, 16, 18),
	PRIEST = set(4, 10, 15, 19),
	SHAMAN = set(0, 1, 4, 5, 10, 13, 15),
	MAGE = set(7, 10, 15, 19),
	WARLOCK = set(7, 10, 15, 19),
	DRUID = set(4, 5, 6, 10, 13, 15),
}
local ARMOR_CLASSES = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true }

local CLASS_ARMOR, CLASS_WEAPON = 4, 2

-- Returns true and a short word for what it is ("plate", "two-handed swords") when `classFile` can never use the item,
-- else false. `item` is an item link, string or id.
function Usable:CannotUse(item, classFile)
	if not item or not classFile or not ARMOR_CLASSES[classFile] then return false end
	local _, _, _, _, _, classID, subClassID = ALC:GetItemInfoInstant(item)
	if classID == CLASS_ARMOR then
		local who = ARMOR_FOR[subClassID]
		if who and not who[classFile] then return true, ARMOR_NAME[subClassID] end
	elseif classID == CLASS_WEAPON then
		local name = WEAPON_NAME[subClassID]
		if name and not WEAPONS_FOR[classFile][subClassID] then return true, name end
	end
	return false
end

-- The same for the player's own class.
function Usable:PlayerCannotUse(item)
	local _, classFile = UnitClass("player")
	return self:CannotUse(item, classFile)
end

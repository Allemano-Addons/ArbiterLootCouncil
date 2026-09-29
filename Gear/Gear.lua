-- Gear: which of your equipped items an item would replace, so council can compare.
-- The list is sent with your response (inspecting other players is unreliable).

local ALC = ALC

local Gear = {}
ALC.Gear = Gear

-- Inventory slot ids.
local HEAD, NECK, SHOULDER, CHEST, WAIST, LEGS, FEET, WRIST, HANDS = 1, 2, 3, 5, 6, 7, 8, 9, 10
local FINGER1, FINGER2, TRINKET1, TRINKET2, BACK = 11, 12, 13, 14, 15
local MAINHAND, OFFHAND, RANGED = 16, 17, 18

-- INVTYPE_* -> the slots an item of that type competes for.
-- One-hand weapons fit either hand, and a two-hander is compared with both hands
-- (Titan's Grip, or a one-hander plus an off-hand).
local SLOTS = {
	INVTYPE_HEAD = { HEAD },
	INVTYPE_NECK = { NECK },
	INVTYPE_SHOULDER = { SHOULDER },
	INVTYPE_CHEST = { CHEST },
	INVTYPE_ROBE = { CHEST },
	INVTYPE_WAIST = { WAIST },
	INVTYPE_LEGS = { LEGS },
	INVTYPE_FEET = { FEET },
	INVTYPE_WRIST = { WRIST },
	INVTYPE_HAND = { HANDS },
	INVTYPE_FINGER = { FINGER1, FINGER2 },
	INVTYPE_TRINKET = { TRINKET1, TRINKET2 },
	INVTYPE_CLOAK = { BACK },
	INVTYPE_WEAPON = { MAINHAND, OFFHAND },
	INVTYPE_2HWEAPON = { MAINHAND, OFFHAND },
	INVTYPE_WEAPONMAINHAND = { MAINHAND },
	INVTYPE_WEAPONOFFHAND = { OFFHAND },
	INVTYPE_SHIELD = { OFFHAND },
	INVTYPE_HOLDABLE = { OFFHAND },
	INVTYPE_RANGED = { RANGED },
	INVTYPE_RANGEDRIGHT = { RANGED },
	INVTYPE_THROWN = { RANGED },
	INVTYPE_RELIC = { RANGED },
}

-- Replaceable in tests.
function Gear.GetEquippedLink(slot)
	return GetInventoryItemLink("player", slot)
end

-- The slots an item competes for (a copy), or an empty list for items that are not worn.
function Gear:GetSlots(item)
	local _, _, _, equipLoc = ALC:GetItemInfoInstant(item)
	local slots = equipLoc and SLOTS[equipLoc]
	local copy = {}
	if slots then
		for i, slot in ipairs(slots) do copy[i] = slot end
	end
	return copy
end

-- itemStrings of what you wear in those slots, empty slots skipped.
function Gear:GetEquipped(item)
	local equipped = {}
	for _, slot in ipairs(self:GetSlots(item)) do
		local link = self.GetEquippedLink(slot)
		local itemString = link and ALC:ParseItem(link)
		if itemString then equipped[#equipped + 1] = itemString end
	end
	return equipped
end

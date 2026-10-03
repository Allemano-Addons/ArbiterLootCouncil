std = "lua51"
max_line_length = false
exclude_files = { "Libs/", "Tests/" } -- the tests replace the game API on purpose
ignore = { "212/self", "212/_.*", "211", "311", "411", "421", "431" } -- style warnings: unused locals, shadowing

globals = { "ALC", "ALC_DB", "SLASH_ALC1", "SlashCmdList", "StaticPopupDialogs" }

read_globals = {
	"LibStub", "C_AddOns", "GetAddOnMetadata", "Ambiguate", "DEFAULT_CHAT_FRAME",
	"GetTime", "issecretvalue", "IsInRaid", "IsInGroup", "GetNumGroupMembers", "UnitName", "C_Timer", "C_Item", "GetItemInfoInstant",
	"date", "time", "format", "strlower", "strmatch", "tinsert", "tremove", "wipe",
}

-- Game API used by the addon (the list grows with the code; a typo in a name shows up as a new warning).
for _, name in ipairs({
	"BIND_TRADE_TIME_REMAINING", "C_Container", "C_PartyInfo", "CheckInteractDistance", "ClearCursor", "ClickTradeButton", "Constants", "CreateFrame", "CursorHasItem", "ERR_TRADE_COMPLETE", "Enum", "GameTooltip", "GetContainerItemInfo", "GetContainerItemLink", "GetContainerNumSlots", "GetCursorPosition", "GetGuildInfo", "GetInventoryItemLink", "GetItemInfo", "GetLootMethod", "GetLootSlotLink", "GetLootSourceInfo", "GetLootThreshold", "GetMasterLootCandidate", "GetNumLootItems", "GetRaidRosterInfo", "GetRealZoneText", "GetTradePlayerItemLink", "GetTradeTargetItemLink", "GetZoneText", "GiveMasterLoot", "ITEM_SOULBOUND", "InCombatLockdown", "InitiateTrade", "IsMasterLooter", "LE_PARTY_CATEGORY_HOME", "LE_PARTY_CATEGORY_INSTANCE", "LOCALIZED_CLASS_NAMES_MALE", "Minimap", "NO", "NUM_BAG_SLOTS", "PickupContainerItem", "RAID_CLASS_COLORS", "STANDARD_TEXT_FONT", "SendChatMessage", "SetLootThreshold", "SplitContainerItem", "StaticPopup_Hide", "StaticPopup_Show", "TradeFrameRecipientNameText", "UIParent", "UnitClass", "UnitExists", "UnitIsConnected", "UnitIsDead", "UnitIsGroupLeader", "UnitIsPlayer", "YES", "geterrorhandler",
}) do read_globals[#read_globals + 1] = name end

std = "lua51"
max_line_length = false
exclude_files = { "Libs/" }
ignore = { "212/self", "212/_.*" }

globals = { "ALC", "ALC_DB", "SLASH_ALC1", "SlashCmdList" }

read_globals = {
	"LibStub", "C_AddOns", "GetAddOnMetadata", "Ambiguate", "DEFAULT_CHAT_FRAME",
	"date", "time", "format", "strlower", "strmatch", "tinsert", "tremove", "wipe",
}

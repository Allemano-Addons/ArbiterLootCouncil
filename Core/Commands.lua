-- Commands: /alc dispatcher. Modules register their own subcommands via
-- ALC.Commands:Register(name, handler, help).

local ALC = ALC
local L = ALC.L

local strlower = string.lower
local strmatch = string.match
local tinsert, sort = table.insert, table.sort

local Commands = {}
ALC.Commands = Commands

local handlers = {}
local helpText = {}

function Commands:Register(name, handler, help)
	handlers[strlower(name)] = handler
	helpText[strlower(name)] = help
end

local function printHelp()
	ALC:Print(L["Commands:"])
	local names = {}
	for name in pairs(helpText) do tinsert(names, name) end
	sort(names)
	for _, name in ipairs(names) do
		ALC:Print("  /alc %s - %s", name, helpText[name])
	end
end

SLASH_ALC1 = "/alc"
SlashCmdList["ALC"] = function(input)
	local cmd, rest = strmatch(input or "", "^%s*(%S*)%s*(.-)%s*$")
	cmd = strlower(cmd or "")
	if cmd == "" or cmd == "help" then
		printHelp()
		return
	end
	local handler = handlers[cmd]
	if not handler then
		ALC:Print(L["Unknown command '%s'. Type /alc help."], cmd)
		return
	end
	handler(rest)
end

--------------------------------------------------------------------------------
-- Built-in commands
--------------------------------------------------------------------------------

Commands:Register("debug", function(arg)
	arg = strlower(arg)
	local settings = ALC.Settings
	if arg == "" then
		settings:SetDebug(not settings:IsDebug())
	elseif arg == "on" then
		settings:SetDebug(true)
	elseif arg == "off" then
		settings:SetDebug(false)
	elseif arg == "log" then
		ALC.Debug:Dump(30)
		return
	elseif arg == "clear" then
		ALC.Debug:Clear()
		ALC:Print(L["Debug log cleared."])
		return
	else
		ALC:Print(L["Usage: /alc debug [on|off|log|clear]"])
		return
	end
	ALC:Print(settings:IsDebug() and L["Debug output on."] or L["Debug output off."])
end, L["toggle debug output (on|off|log|clear)"])

Commands:Register("council", function(arg)
	local settings = ALC.Settings
	local action, name = strmatch(arg, "^(%S*)%s*(.-)$")
	action = strlower(action)
	if action == "add" and name ~= "" then
		ALC:Print(settings:AddCouncilMember(name) and L["Added %s to the council."] or L["%s is invalid or already on the council."], name)
	elseif action == "remove" and name ~= "" then
		ALC:Print(settings:RemoveCouncilMember(name) and L["Removed %s from the council."] or L["%s is not on the council."], name)
	elseif action == "" or action == "list" then
		local list = settings:GetCouncil()
		if #list == 0 then
			ALC:Print(L["The council is empty. Use /alc council add <name>."])
		else
			ALC:Print(L["Council (%d): %s"], #list, table.concat(list, ", "))
		end
	else
		ALC:Print(L["Usage: /alc council [list|add <name>|remove <name>]"])
	end
end, L["show or edit the council list"])

local QUALITY_NAMES = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 }

Commands:Register("quality", function(arg)
	local settings = ALC.Settings
	if arg ~= "" then
		local quality = QUALITY_NAMES[strlower(arg)] or tonumber(arg)
		if not settings:SetQualityThreshold(quality) then
			ALC:Print(L["Usage: /alc quality [poor|common|uncommon|rare|epic|legendary]"])
			return
		end
	end
	ALC:Print(L["Loot quality threshold: %d"], settings:GetQualityThreshold())
end, L["show or set the loot quality threshold"])

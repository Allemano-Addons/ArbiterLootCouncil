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

-- Modules add diagnostics under /alc debug <name> via Commands:RegisterDebug.
local debugHandlers = {}

function Commands:RegisterDebug(name, handler)
	debugHandlers[strlower(name)] = handler
end

local function debugUsage()
	local names = { "on", "off", "log", "clear" }
	local extra = {}
	for name in pairs(debugHandlers) do tinsert(extra, name) end
	sort(extra)
	for _, name in ipairs(extra) do tinsert(names, name) end
	return table.concat(names, "|")
end

Commands:Register("debug", function(arg)
	local sub, rest = strmatch(arg, "^(%S*)%s*(.-)$")
	sub = strlower(sub)
	local settings = ALC.Settings
	if sub == "" then
		settings:SetDebug(not settings:IsDebug())
	elseif sub == "on" then
		settings:SetDebug(true)
	elseif sub == "off" then
		settings:SetDebug(false)
	elseif sub == "log" then
		ALC.Debug:Dump(30)
		return
	elseif sub == "clear" then
		ALC.Debug:Clear()
		ALC:Print(L["Debug log cleared."])
		return
	elseif debugHandlers[sub] then
		debugHandlers[sub](rest)
		return
	else
		ALC:Print(L["Usage: /alc debug [%s]"], debugUsage())
		return
	end
	ALC:Print(settings:IsDebug() and L["Debug output on."] or L["Debug output off."])
end, L["toggle debug output, diagnostics (/alc debug help)"])

Commands:RegisterDebug("help", function()
	ALC:Print(L["Usage: /alc debug [%s]"], debugUsage())
end)

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

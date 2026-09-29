-- Debug: leveled logging into a ring buffer that persists in ALC_DB.global.debugLog.
-- Entries logged before the DB exists are held in memory and flushed on ALC_SETTINGS_READY.

local ALC = ALC

local format = string.format
local pcall = pcall
local select = select
local tostring = tostring
local time = time
local tinsert, tremove = table.insert, table.remove

local MAX_LINES = 500
local LEVELS = { info = 1, warn = 2, error = 3 }
local LEVEL_COLOR = { info = "ffB0B0B0", warn = "ffE6A93C", error = "ffFF5555" }

local Debug = {}
ALC.Debug = Debug

local pending = {}
local log -- ALC_DB.global.debugLog once the DB is ready

local function push(entry)
	local target = log or pending
	tinsert(target, entry)
	while #target > MAX_LINES do
		tremove(target, 1)
	end
end

local function write(level, module, msg, ...)
	if select("#", ...) > 0 then
		local ok, formatted = pcall(format, msg, ...)
		msg = ok and formatted or (tostring(msg) .. " [format error]")
	end
	msg = tostring(msg)
	push({ t = time(), lvl = level, mod = module, msg = msg })
	if level == "error" or (ALC.Settings.IsDebug and ALC.Settings:IsDebug()) then
		ALC:Print("|c%s%s|r %s: %s", LEVEL_COLOR[level], level, module, msg)
	end
end

function Debug:Log(module, msg, ...) write("info", module, msg, ...) end
function Debug:Warn(module, msg, ...) write("warn", module, msg, ...) end
function Debug:Error(module, msg, ...) write("error", module, msg, ...) end

-- Read-only view of the current buffer (oldest first).
function Debug:GetLines()
	return log or pending
end

function Debug:Clear()
	local target = log or pending
	for i = #target, 1, -1 do target[i] = nil end
end

function Debug:Dump(count)
	local lines = self:GetLines()
	local from = math.max(1, #lines - (count or 20) + 1)
	for i = from, #lines do
		local e = lines[i]
		ALC:Print("%s |c%s%s|r %s: %s", date("%H:%M:%S", e.t), LEVEL_COLOR[e.lvl] or LEVEL_COLOR.info, e.lvl, e.mod, e.msg)
	end
	if #lines == 0 then ALC:Print(ALC.L["Debug log is empty."]) end
end

ALC.Events.Register(Debug, "ALC_SETTINGS_READY", function()
	log = ALC.Settings:GetDB().global.debugLog
	for i = 1, #pending do
		tinsert(log, pending[i])
		pending[i] = nil
	end
	while #log > MAX_LINES do tremove(log, 1) end
end)

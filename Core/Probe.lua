-- Probe: answers one question before a whisper fallback is built: can the addon READ a whisper that comes in, and can
-- it SEND one, in the places a raid happens? On WoW Forever the text of chat messages can be a "secret" string in a fight
-- or an instance (it can be shown but not read), which would make a fallback where raiders whisper their answers to the
-- loot master useless exactly where it is needed.
--
--   /alc probe                what has been seen, and how to use it
--   /alc probe whisper on|off listen to incoming whispers and note, for each, whether the text and the name could be read
--   /alc probe reply <name>   send one whisper and note whether the game let it through
--   /alc probe clear          forget what was noted
--
-- It keeps only facts about each message (readable or not, how long, where the player was), never the text.

local ALC = ALC
local LibStub = LibStub
local L = ALC.L

local Probe = {}
ALC.Probe = Probe
LibStub("AceEvent-3.0"):Embed(Probe)

local KEEP = 60
local listening = false

local function store()
	local g = ALC.Settings:GetDB().global
	g.probe = g.probe or { log = {}, listen = false }
	return g.probe
end

local function readable(value)
	if type(value) ~= "string" then return false end
	if issecretvalue and issecretvalue(value) then return false end
	return true
end

-- Where the player is right now, as the facts that matter.
local function place()
	local inInstance, kind = IsInInstance()
	local group = (IsInRaid and IsInRaid()) and "raid" or ((IsInGroup and IsInGroup()) and "party" or "alone")
	local combat = (UnitAffectingCombat and UnitAffectingCombat("player")) or (InCombatLockdown and InCombatLockdown()) or false
	return { instance = inInstance and tostring(kind or "yes") or "no", group = group, combat = combat and true or false }
end

local function add(entry)
	local log = store().log
	entry.t = time()
	log[#log + 1] = entry
	while #log > KEEP do table.remove(log, 1) end
	local where = string.format("instance=%s group=%s combat=%s", entry.instance, entry.group, entry.combat and "yes" or "no")
	if entry.kind == "whisper" then
		ALC.Debug:Log("Probe", "whisper: text %s, name %s, %d letters (%s)", entry.textReadable and "READABLE" or "SECRET",
			entry.senderReadable and "readable" or "secret", entry.length or 0, where)
	else
		ALC.Debug:Log("Probe", "reply to %s: %s (%s)", tostring(entry.target), entry.ok and "SENT" or ("REFUSED: " .. tostring(entry.error)), where)
	end
	return entry
end

-- A whisper came in (the game's CHAT_MSG_WHISPER, or the Battle.net one). Only facts are kept.
function Probe:OnWhisper(event, text, sender)
	if not listening then return end
	local entry = place()
	entry.kind = "whisper"
	entry.event = event
	entry.textReadable = readable(text)
	entry.senderReadable = readable(sender)
	if entry.textReadable then
		entry.length = #text
		entry.hasLink = string.find(text, "|Hitem:", 1, true) ~= nil
	end
	local added = add(entry)
	ALC:Print(L["Probe: a whisper came in, the text is %s (%s)."], entry.textReadable and L["readable"] or L["SECRET"],
		string.format("%s, %s, %s", added.instance, added.group, added.combat and L["in combat"] or L["not in combat"]))
end

-- Sends one whisper and notes whether the game let it through.
function Probe:SendReply(name)
	local entry = place()
	entry.kind = "reply"
	entry.target = name
	local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	local ok, err = pcall(fn, "ALC probe: this is a test whisper, no need to answer.", "WHISPER", nil, name)
	entry.ok = ok
	entry.error = (not ok) and tostring(err) or nil
	return add(entry)
end

function Probe:IsListening() return listening end

function Probe:SetListening(on)
	listening = on and true or false
	store().listen = listening
end

function Probe:GetLog() return store().log end

function Probe:Clear() store().log = {} end

-- A summary: how many whispers were readable, in which places.
function Probe:Summary()
	local counts = {}
	for _, e in ipairs(store().log) do
		if e.kind == "whisper" then
			local key = string.format("%s/%s/%s", e.instance, e.group, e.combat and "combat" or "calm")
			counts[key] = counts[key] or { readable = 0, secret = 0 }
			counts[key][e.textReadable and "readable" or "secret"] = counts[key][e.textReadable and "readable" or "secret"] + 1
		end
	end
	local lines = {}
	for key, c in pairs(counts) do lines[#lines + 1] = string.format("%s: %d readable, %d secret", key, c.readable, c.secret) end
	table.sort(lines)
	return lines
end

function Probe:Init()
	listening = store().listen == true
	self:RegisterEvent("CHAT_MSG_WHISPER", function(event, text, sender) Probe:OnWhisper(event, text, sender) end)
	self:RegisterEvent("CHAT_MSG_BN_WHISPER", function(event, text, sender) Probe:OnWhisper(event, text, sender) end)
end

ALC.Commands:Register("probe", function(arg)
	local sub, rest = string.match(arg or "", "^(%S*)%s*(.-)$")
	sub = string.lower(sub)
	if sub == "whisper" then
		local on = string.lower(rest) ~= "off"
		Probe:SetListening(on)
		ALC:Print(on and L["Probe: listening to whispers. Ask somebody to whisper you in the places that matter (a raid, a dungeon, in a fight). /alc probe shows what was seen."]
			or L["Probe: not listening."])
	elseif sub == "reply" then
		if rest == "" then ALC:Print(L["Usage: /alc probe reply <name>"]) return end
		local entry = Probe:SendReply(rest)
		ALC:Print(entry.ok and L["Probe: a whisper was sent to %s."] or L["Probe: the game refused the whisper to %s."], rest)
	elseif sub == "clear" then
		Probe:Clear()
		ALC:Print(L["Probe: what was seen is cleared."])
	else
		ALC:Print(L["Probe: can the addon read a whisper, and send one, where a raid happens? /alc probe whisper on (then get whispered), /alc probe reply <name>, /alc probe clear."])
		local lines = Probe:Summary()
		if #lines == 0 then ALC:Print(L["Nothing seen yet."]) end
		for _, line in ipairs(lines) do ALC:Print("  " .. line) end
		local log = Probe:GetLog()
		local replies = 0
		for _, e in ipairs(log) do
			if e.kind == "reply" then
				replies = replies + 1
				ALC:Print("  reply: %s (instance=%s, group=%s, %s)", e.ok and "sent" or ("refused: " .. tostring(e.error)), e.instance, e.group, e.combat and "in combat" or "calm")
			end
		end
		ALC:Print(L["Listening: %s."], Probe:IsListening() and L["yes"] or L["no"])
	end
end, L["find out if a whisper fallback can work: can whispers be read and sent in a raid"])

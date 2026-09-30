-- Recent: what each player has been awarded lately, for the council's eyes.
--
-- The loot master keeps the award log, so the loot master works out, for every player who has
-- been awarded something in the last N days (Settings, 30 by default), how many items it was
-- and the latest few (item, the answer they gave, how many days ago). It sends that to the
-- council only, as RECENT: when a session starts, when an item is awarded and when the
-- window is changed. The council window shows the count in a column and the list on hover.
-- Nobody else sees any of it.
--
-- Events:
--   ALC_RECENT_CHANGED ()   the council's copy of the figures changed

local ALC = ALC
local L = ALC.L

local Debug = ALC.Debug

local strlower, format = string.lower, string.format
local time = time

local Recent = {}
ALC.Recent = Recent

local MAX_ENTRIES = 6    -- how many awards are listed per player (the count is of all of them)
local MAX_PLAYERS = 60   -- how many players one message holds
local DAY = 86400

local data = {}          -- lowercase name -> { name, count, awards = { { itemID, label, color, ago } } }
local days = nil         -- the window the figures are for

--------------------------------------------------------------------------------
-- Getters (council)
--------------------------------------------------------------------------------

-- The window the figures are for, in days, or nil before any arrived.
function Recent:GetDays()
	return days
end

-- How many awards a player got in the window, and the latest of them (a copy):
-- { itemID, label, color = { r, g, b }, ago (days) }.
function Recent:Get(name)
	local entry = name and data[strlower(name)]
	if not entry then return 0, {} end
	local copy = {}
	for i, a in ipairs(entry.awards) do
		copy[i] = { itemID = a.itemID, label = a.label, color = a.color and { a.color[1], a.color[2], a.color[3] } or nil, ago = a.ago }
	end
	return entry.count, copy
end

--------------------------------------------------------------------------------
-- Loot master: work it out from the award log
--------------------------------------------------------------------------------
local function hexOf(color)
	if type(color) ~= "table" then return nil end
	local function h(v) return format("%02x", math.max(0, math.min(255, math.floor((tonumber(v) or 0) * 255 + 0.5)))) end
	return h(color[1]) .. h(color[2]) .. h(color[3])
end

-- The figures for the players in `names` (a list of full names), or for everybody in the
-- log when it is nil. Returns the players list in the wire form, newest winners first.
function Recent:Build(windowDays, names)
	local wanted
	if names then
		wanted = {}
		for _, name in ipairs(names) do wanted[strlower(name)] = true end
	end
	local now = time()
	local cutoff = now - windowDays * DAY
	local byName, order = {}, {}
	local log = ALC.Awards:GetLog()
	-- Newest first (the log is in the order things happened, but do not rely on it).
	local recent = {}
	for i, entry in ipairs(log) do
		if entry.time and entry.time >= cutoff and entry.winner and (not wanted or wanted[strlower(entry.winner)]) then
			recent[#recent + 1] = { entry = entry, index = i }
		end
	end
	table.sort(recent, function(a, b)
		if a.entry.time ~= b.entry.time then return a.entry.time > b.entry.time end
		return a.index > b.index
	end)
	for _, item in ipairs(recent) do
		local entry = item.entry
		do
			local key = strlower(entry.winner)
			local player = byName[key]
			if not player then
				player = { name = entry.winner, count = 0, awards = {} }
				byName[key] = player
				order[#order + 1] = player
			end
			player.count = player.count + 1
			if #player.awards < MAX_ENTRIES then
				player.awards[#player.awards + 1] = {
					itemID = entry.itemID,
					label = entry.responseLabel or ALC.Responses:GetLabel(entry.response),
					color = hexOf(entry.responseColor),
					ago = math.max(0, math.floor((now - entry.time) / DAY)),
				}
			end
		end
	end
	while #order > MAX_PLAYERS do order[#order] = nil end
	return order
end

-- Sends the figures for `names` (nil = everybody in the log) to the council.
function Recent:Send(names)
	local session = ALC.Sessions:GetSession()
	if not session or not session.isLM then return false end
	local windowDays = ALC.Settings:GetRecentDays()
	local players = self:Build(windowDays, names)
	return ALC.Comm:SendCouncil(ALC.Council:GetReachableCouncil(), "RECENT", session.sid,
		{ days = windowDays, full = names == nil, players = players })
end

--------------------------------------------------------------------------------
-- Council: RECENT in
--------------------------------------------------------------------------------
local function colorOf(hex)
	if type(hex) ~= "string" then return nil end
	return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
end

-- Takes in a list of players from a message (they replace what was known about them).
local function apply(p)
	days = p.days
	if p.full then data = {} end -- everybody's figures came: anybody missing has none
	for _, player in ipairs(p.players or {}) do
		local awards = {}
		for i, a in ipairs(player.awards or {}) do
			awards[i] = { itemID = a.itemID, label = a.label, color = colorOf(a.color), ago = a.ago }
		end
		data[strlower(player.name)] = { name = player.name, count = player.count, awards = awards }
	end
	ALC.Events:Fire("ALC_RECENT_CHANGED")
end

local function onRecent(_, _, _, p)
	local session = ALC.Sessions:GetSession()
	if not session or not session.isCouncil then return end
	apply(p)
end

local function reset()
	if next(data) == nil and days == nil then return end
	data, days = {}, nil
	ALC.Events:Fire("ALC_RECENT_CHANGED")
end

--------------------------------------------------------------------------------
-- Recovery
--------------------------------------------------------------------------------
local function onSnapshotBuild(_, payload, _, isCouncil)
	if not isCouncil then return end
	local windowDays = ALC.Settings:GetRecentDays()
	payload.recent = { days = windowDays, full = true, players = Recent:Build(windowDays) }
end

local function onSnapshot(_, p, session)
	data, days = {}, nil
	if session.isCouncil and p.recent then apply(p.recent) else ALC.Events:Fire("ALC_RECENT_CHANGED") end
end

function Recent:Init()
	local register = ALC.Events.Register
	register(self, "ALC_COMM_RECENT", onRecent)
	register(self, "ALC_SESSION_SNAPSHOT_BUILD", onSnapshotBuild)
	register(self, "ALC_SESSION_SNAPSHOT", onSnapshot)
	register(self, "ALC_SESSION_STARTED", function(_, session, restored)
		if not restored then reset() end
		if session.isLM then
			if restored then
				-- Back after a reload: the council has its figures, only ours are gone.
				local windowDays = ALC.Settings:GetRecentDays()
				apply({ days = windowDays, full = true, players = Recent:Build(windowDays) })
			else
				Recent:Send()
			end
		end
	end)
	register(self, "ALC_SESSION_ENDED", reset)
	-- An award was just logged: the winner's figures changed.
	register(self, "ALC_AWARDS_LOGGED", function(_, entry)
		if entry and entry.winner then Recent:Send({ entry.winner }) end
	end)
	-- The window was changed in Settings: everybody's figures change.
	register(self, "ALC_SETTINGS_CHANGED", function(_, key)
		if key == "recentDays" then Recent:Send() end
	end)
end

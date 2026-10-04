-- Profile: the loot master's settings as a line of text to share, and the other way round. When another player takes
-- over as loot master for a week they can paste the line and have the same council, threshold, answer buttons, timer
-- and so on. What is personal (window positions, font, size, the minimap button, debug, the logs) is not in it.
--
-- The text is "ALCP1:<check>:<base64>", the settings as an AceSerializer table. Whatever is pasted is treated as
-- untrusted: every value is checked against what the setting accepts, anything unknown is dropped, and nothing is
-- applied before the player has seen what would change. The values from before an import are kept once, for Undo.

local ALC = ALC
local LibStub = LibStub
local L = ALC.L

local floor = math.floor
local strlower = string.lower

local Profile = {}
ALC.Profile = Profile

local PREFIX = "ALCP1"
local FORMAT = 1
local MAX_TEXT = 14000

--------------------------------------------------------------------------------
-- The text: base64 (URL safe, no padding) and a check number to catch a text that was cut or changed
--------------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local B64_INDEX = {}
for i = 1, #B64 do B64_INDEX[string.sub(B64, i, i)] = i - 1 end

local function encode(s)
	local out = {}
	for i = 1, #s, 3 do
		local a, b, c = string.byte(s, i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1, c2, c3, c4 = floor(n / 262144) % 64, floor(n / 4096) % 64, floor(n / 64) % 64, n % 64
		out[#out + 1] = string.sub(B64, c1 + 1, c1 + 1) .. string.sub(B64, c2 + 1, c2 + 1)
			.. (b and string.sub(B64, c3 + 1, c3 + 1) or "") .. (c and string.sub(B64, c4 + 1, c4 + 1) or "")
	end
	return table.concat(out)
end

local function decode(s)
	local out = {}
	for i = 1, #s, 4 do
		local chunk = string.sub(s, i, i + 3)
		local n, count = 0, 0
		for j = 1, #chunk do
			local v = B64_INDEX[string.sub(chunk, j, j)]
			if not v then return nil end
			n = n * 64 + v
			count = count + 1
		end
		if count == 1 then return nil end
		for _ = count + 1, 4 do n = n * 64 end
		local bytes = { floor(n / 65536) % 256, floor(n / 256) % 256, n % 256 }
		for j = 1, count - 1 do out[#out + 1] = string.char(bytes[j]) end
	end
	return table.concat(out)
end

local function check(payload)
	local h = 0
	for i = 1, #payload do h = (h * 31 + string.byte(payload, i)) % 65521 end
	return string.format("%04x", h)
end

--------------------------------------------------------------------------------
-- The settings that are in a profile. Each: key, label, get(), clean(value) -> a usable value or nil, set(value),
-- text(value, current) -> how it is shown in the list of changes.
--------------------------------------------------------------------------------
local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	if #a ~= #b then return false end
	for k, v in pairs(a) do if not same(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

local function yesNo(v) return v and L["On"] or L["Off"] end

local function boolField(key, label, getter, setter)
	return {
		key = key, label = label,
		get = function() return ALC.Settings[getter](ALC.Settings) and true or false end,
		clean = function(v) if type(v) == "boolean" then return v end end,
		set = function(v) ALC.Settings[setter](ALC.Settings, v) end,
		text = yesNo,
	}
end

local function properName(name)
	return (string.gsub(name, "(%S)(%S*)", function(first, rest) return string.upper(first) .. strlower(rest) end))
end

-- A character name as the council list and the disenchanter accept it, or nil.
local function cleanName(name)
	if type(name) ~= "string" then return nil end
	name = ALC:NormalizeName(name)
	if not name or #name < 2 or #name > 48 or string.find(name, "[%c|]") then return nil end
	return properName(name)
end

local function qualityName(q) return _G["ITEM_QUALITY" .. tostring(q) .. "_DESC"] or tostring(q) end

local FIELDS = {
	{
		key = "council", label = L["Council"],
		get = function() return ALC.Settings:GetCouncil() end,
		clean = function(v)
			if type(v) ~= "table" then return nil end
			local out, seen = {}, {}
			for i = 1, #v do
				local name = cleanName(v[i])
				if name and not seen[strlower(name)] and #out < ALC.Constants.MAX_COUNCIL - 1 then
					seen[strlower(name)] = true
					out[#out + 1] = name
				end
			end
			return out
		end,
		set = function(list)
			for _, name in ipairs(ALC.Settings:GetCouncil()) do ALC.Settings:RemoveCouncilMember(name) end
			for _, name in ipairs(list) do ALC.Settings:AddCouncilMember(name) end
		end,
		text = function(list, current)
			local have = {}
			for _, name in ipairs(current or {}) do have[strlower(name)] = true end
			local added = 0
			for _, name in ipairs(list) do if not have[strlower(name)] then added = added + 1 end end
			local want = {}
			for _, name in ipairs(list) do want[strlower(name)] = true end
			local removed = 0
			for _, name in ipairs(current or {}) do if not want[strlower(name)] then removed = removed + 1 end end
			return string.format(L["%d names (%d new, %d removed)"], #list, added, removed)
		end,
	},
	{
		key = "qualityThreshold", label = L["Loot quality threshold"],
		get = function() return ALC.Settings:GetQualityThreshold() end,
		clean = function(v) if type(v) == "number" and v >= 2 and v <= 4 and v == floor(v) then return v end end,
		set = function(v) ALC.Settings:SetQualityThreshold(v) end,
		text = qualityName,
	},
	boolField("autoOpenLootWindow", L["Open the loot window when items arrive"], "GetAutoOpenLootWindow", "SetAutoOpenLootWindow"),
	boolField("announceAwards", L["Announce awards"], "GetAnnounceAwards", "SetAnnounceAwards"),
	boolField("autoLoot", L["Auto loot"], "GetAutoLoot", "SetAutoLoot"),
	boolField("autoLootConfirm", L["Ask first (\"Loot all?\")"], "GetAutoLootConfirm", "SetAutoLootConfirm"),
	boolField("autoTrade", L["Auto trade"], "GetAutoTrade", "SetAutoTrade"),
	{
		key = "disenchanter", label = L["Disenchanter"],
		get = function() return ALC.Settings:GetDisenchanter() or false end,
		clean = function(v)
			if v == false then return false end
			return cleanName(v)
		end,
		set = function(v) ALC.Settings:SetDisenchanter(v or nil) end,
		text = function(v) return v or L["None"] end,
	},
	{
		key = "guildBank", label = L["Guild bank"],
		get = function() return ALC.Settings:GetGuildBank() or false end,
		clean = function(v)
			if v == false then return false end
			return cleanName(v)
		end,
		set = function(v) ALC.Settings:SetGuildBank(v or nil) end,
		text = function(v) return v or L["None"] end,
	},
	boolField("rollsEnabled", L["Random rolls for the council"], "GetRollsEnabled", "SetRollsEnabled"),
	boolField("warnMissing", L["Warn about players without the addon"], "GetWarnMissing", "SetWarnMissing"),
	{
		key = "recentDays", label = L["Recent awards: the council sees the last"],
		get = function() return ALC.Settings:GetRecentDays() end,
		clean = function(v) if v == 7 or v == 14 or v == 30 or v == 90 then return v end end,
		set = function(v) ALC.Settings:SetRecentDays(v) end,
		text = function(v) return string.format(L["%d days"], v) end,
	},
	boolField("timerEnabled", L["Answer timer"], "GetTimerEnabled", "SetTimerEnabled"),
	{
		key = "timerSeconds", label = L["Answer timer: seconds"],
		get = function() return ALC.Settings:GetTimerSeconds() end,
		clean = function(v)
			local C = ALC.Constants
			if type(v) == "number" and v >= C.TIMER_MIN and v <= C.TIMER_MAX then return floor(v) end
		end,
		set = function(v) ALC.Settings:SetTimerSeconds(v) end,
		text = function(v) return string.format(L["%d sec"], v) end,
	},
	{
		key = "logReminder", label = L["Remind me to export the award log at"],
		get = function() return ALC.Settings:GetLogReminder() end,
		clean = function(v) if v == 0 or v == 500 or v == 1000 or v == 2000 then return v end end,
		set = function(v) ALC.Settings:SetLogReminder(v) end,
		text = function(v) return v == 0 and L["Never"] or tostring(v) end,
	},
	{
		key = "responses", label = L["Answer buttons"],
		get = function()
			local set = ALC.Responses:GetConfiguredSet()
			local out = {}
			for i, r in ipairs(set) do out[i] = { id = r.id, label = r.label, color = { r.color[1], r.color[2], r.color[3] } } end
			return out
		end,
		clean = function(v)
			if type(v) ~= "table" then return nil end
			local out = {}
			for i = 1, #v do
				local r = v[i]
				if type(r) ~= "table" or type(r.color) ~= "table" then return nil end
				local color = {}
				for k = 1, 3 do
					local x = r.color[k]
					if type(x) ~= "number" or x ~= x then return nil end
					color[k] = math.max(0, math.min(1, x))
				end
				out[i] = { id = r.id, label = ALC.Responses.CleanLabel(r.label), color = color }
			end
			if ALC.Responses:ValidateSet(out) then return out end
		end,
		set = function(v) ALC.Responses:SetConfiguredSet(v) end,
		text = function(set)
			local names = {}
			for i, r in ipairs(set) do names[i] = r.label end
			return table.concat(names, ", ")
		end,
	},
}

-- The loot master settings of other addons (Soft Reserve): rows with an `id` on the loot master tab.
local function extensionFields()
	local list = {}
	for _, section in ipairs(ALC.GetSettingsSections()) do
		for _, row in ipairs(section.rows) do
			if row.tab == "lm" and type(row.id) == "string" and (row.type == "check" or row.type == "choice") then
				local field = {
					key = "x:" .. section.id .. ":" .. row.id, label = section.name .. ": " .. row.label, row = row,
					get = function()
						local ok, value = pcall(row.get)
						if not ok then return nil end
						return value
					end,
					set = function(v) pcall(row.set, v) end,
				}
				if row.type == "check" then
					field.clean = function(v) if type(v) == "boolean" then return v end end
					field.get = function()
						local ok, value = pcall(row.get)
						return ok and value and true or false
					end
					field.text = yesNo
				else
					local labels = {}
					for _, option in ipairs(row.options) do labels[option.value] = option.label end
					field.clean = function(v) if labels[v] ~= nil then return v end end
					field.text = function(v) return tostring(labels[v] or v) end
				end
				list[#list + 1] = field
			end
		end
	end
	return list
end

local function allFields()
	local list = {}
	for _, f in ipairs(FIELDS) do list[#list + 1] = f end
	for _, f in ipairs(extensionFields()) do list[#list + 1] = f end
	return list
end

--------------------------------------------------------------------------------
-- Export and import
--------------------------------------------------------------------------------
-- The settings now, as a table { key = value }.
function Profile:Snapshot()
	local data = {}
	for _, field in ipairs(allFields()) do
		local value = field.get()
		if value ~= nil then data[field.key] = value end
	end
	return data
end

-- A table as the text to share.
function Profile.Pack(tbl)
	local payload = encode(LibStub("AceSerializer-3.0"):Serialize(tbl))
	return string.format("%s:%s:%s", PREFIX, check(payload), payload)
end

-- The text to share.
function Profile:Export()
	return Profile.Pack({ v = FORMAT, ver = ALC.version, by = ALC:PlayerName(), t = time(), data = self:Snapshot() })
end

-- Reads a pasted text. Returns { values = { key = clean value }, by, ver, t }, or nil and a reason.
function Profile:Parse(text)
	if type(text) ~= "string" then return nil, L["Nothing to read."] end
	text = string.gsub(text, "%s", "")
	if text == "" then return nil, L["Paste the text here."] end
	if #text > MAX_TEXT then return nil, L["That text is too long to be a profile."] end
	local prefix, sum, payload = string.match(text, "^(%w+):(%x+):([%w%-_]+)$")
	if prefix ~= PREFIX then return nil, L["That does not look like an Arbiter Loot Council profile."] end
	if check(payload) ~= sum then return nil, L["The text is damaged (cut off or changed). Copy it again."] end
	local raw = decode(payload)
	if not raw then return nil, L["The text is damaged (cut off or changed). Copy it again."] end
	local ok, tbl = LibStub("AceSerializer-3.0"):Deserialize(raw)
	if not ok or type(tbl) ~= "table" or tbl.v ~= FORMAT or type(tbl.data) ~= "table" then
		return nil, L["That profile was made by a version this one cannot read."]
	end
	local values = {}
	for _, field in ipairs(allFields()) do
		local given = tbl.data[field.key]
		if given ~= nil then
			local value = field.clean(given)
			if value ~= nil then values[field.key] = value end
		end
	end
	return {
		values = values,
		by = type(tbl.by) == "string" and (string.sub((string.gsub(tbl.by, "[%c|]", "")), 1, 48)) or nil,
		ver = type(tbl.ver) == "string" and (string.sub((string.gsub(tbl.ver, "[%c|]", "")), 1, 24)) or nil,
		t = type(tbl.t) == "number" and tbl.t or nil,
	}
end

-- What the profile would change: a list of { key, label, from, to } in the order of the settings window.
function Profile:Changes(profile)
	local changes = {}
	for _, field in ipairs(allFields()) do
		local want = profile.values[field.key]
		if want ~= nil then
			local now = field.get()
			if not same(now, want) then
				changes[#changes + 1] = {
					key = field.key, label = field.label,
					from = field.text(now, now), to = field.text(want, now),
				}
			end
		end
	end
	return changes
end

local function store()
	return ALC.Settings:GetDB().global
end

-- Applies the profile. The settings from before are kept for Undo. Returns how many settings changed.
function Profile:Apply(profile)
	local before = self:Snapshot()
	local count = 0
	for _, field in ipairs(allFields()) do
		local want = profile.values[field.key]
		if want ~= nil and not same(field.get(), want) then
			field.set(want)
			count = count + 1
		end
	end
	if count > 0 then store().profileUndo = { t = time(), data = before } end
	ALC.Events:Fire("ALC_PROFILE_APPLIED", count)
	return count
end

-- When the last import was made (a time), or nil when there is nothing to undo.
function Profile:UndoTime()
	local undo = store().profileUndo
	return undo and undo.t or nil
end

-- Puts the settings from before the last import back. Returns how many settings changed, or nil and a reason.
function Profile:Undo()
	local undo = store().profileUndo
	if type(undo) ~= "table" or type(undo.data) ~= "table" then return nil, L["There is no import to undo."] end
	local values = {}
	for _, field in ipairs(allFields()) do
		local value = field.clean(undo.data[field.key])
		if value ~= nil then values[field.key] = value end
	end
	local count = 0
	for _, field in ipairs(allFields()) do
		local want = values[field.key]
		if want ~= nil and not same(field.get(), want) then
			field.set(want)
			count = count + 1
		end
	end
	store().profileUndo = nil
	ALC.Events:Fire("ALC_PROFILE_APPLIED", count)
	return count
end

--------------------------------------------------------------------------------
-- Settings window and commands
--------------------------------------------------------------------------------
function Profile:Init()
	ALC.RegisterSettingsSection({
		id = "ALC-profile", name = L["Share settings"],
		rows = {
			{ tab = "lm", type = "action", label = L["Copy my settings"], onClick = function() ALC.ProfileWindow:ShowExport() end },
			{ tab = "lm", type = "action", label = L["Import settings"], onClick = function() ALC.ProfileWindow:ShowImport() end },
			{ tab = "lm", type = "action", label = L["Undo the last import"], confirm = L["Click again to put the old settings back"],
				onClick = function()
					local count, why = Profile:Undo()
					ALC:Print(count and L["%d settings put back."] or why, count)
				end },
		},
	})
end

ALC.Commands:Register("profile", function(arg)
	local sub = string.lower(string.match(arg or "", "^(%S*)") or "")
	if sub == "import" then
		ALC.ProfileWindow:ShowImport()
	elseif sub == "undo" then
		local count, why = Profile:Undo()
		ALC:Print(count and L["%d settings put back."] or why, count)
	else
		ALC.ProfileWindow:ShowExport()
	end
end, L["share your loot master settings (import: paste someone else's, undo: put back)"])

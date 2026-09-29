-- All user-facing strings go through ALC.L so localization can be added in v0.9.
-- A missing key falls back to the key itself (the English text).

local ALC = ALC

ALC.L = setmetatable({}, {
	__index = function(_, key) return key end,
})

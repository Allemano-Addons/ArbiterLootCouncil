-- Constants shared between modules (protocol validation, responses, limits).

local ALC = ALC

ALC.Constants = {
	-- Fixed response ids in v0.1, in display order. Labels live in the Responses module.
	RESPONSE_IDS = { "BIS", "UPGRADE", "MINOR", "OFFSPEC", "PASS" },

	MAX_COUNCIL = 40,
	MAX_CANDIDATES = 60,
	MAX_GEAR_ITEMS = 4,
	MAX_SESSION_ITEMS = 30,
}

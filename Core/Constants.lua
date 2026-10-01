-- Constants shared between modules (protocol validation, responses, limits).

local ALC = ALC

ALC.Constants = {
	-- Fixed response ids in v0.1, in display order. Labels live in the Responses module.
	RESPONSE_IDS = { "BIS", "UPGRADE", "MINOR", "OFFSPEC", "PASS" },

	-- The answer an item gets when it is awarded to the disenchanter. It is not a button
	-- players can press: only the loot master gives it, so it is not among the session's answers.
	DISENCHANT_ID = "DISENCHANT",

	MAX_COUNCIL = 40,
	MAX_CANDIDATES = 60,
	MAX_GEAR_ITEMS = 4,
	MAX_SESSION_ITEMS = 30,
	MAX_RECENT_PLAYERS = 60,
	MAX_RECENT_AWARDS = 6,
	MAX_NOTE_LENGTH = 100,
	TIMER_MIN = 10,  -- seconds: the answer timer of a session
	TIMER_MAX = 600,
	MAX_RESPONSES = 8,
	MAX_RESPONSE_LABEL = 12,
}

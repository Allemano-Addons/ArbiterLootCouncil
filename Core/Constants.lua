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
	MAX_HISTORY_ENTRIES = 30, -- the awards of one player a council member gets (see Context)
	MAX_HISTORY_ZONE = 40,
	MAX_NOTE_LENGTH = 100,
	TIMER_MIN = 10,  -- seconds: the answer timer of a session
	TIMER_MAX = 600,
	MAX_RESPONSES = 8,
	MAX_RESPONSE_LABEL = 12,

	-- What another addon (Arbiter Soft Reserve) may attach to a session: a `mode` text, and per item an `extra`
	-- table. ALC does not look at the content; it only keeps it small and plain.
	MAX_MODE_LENGTH = 16,
	MAX_MODE_NAME = 24, -- the longer name of a mode ("Soft Reserve"), shown in the window titles
	MAX_EXTRA_KEYS = 8,
	MAX_EXTRA_TEXT = 64,
	MAX_EXTRA_LIST = 40,

	-- The result of an item decided by rolls (see Results): rows per item, rerolls per row.
	MAX_RESULT_ROWS = 60,
	MAX_REROLLS = 10,
}

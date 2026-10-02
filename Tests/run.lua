package.path = "./Tests/?.lua;" .. package.path
local H = require("harness")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1 else failed = failed + 1 print("FAIL: " .. name) end
end

H.setup()
H.loadAddon()

-- Debug entries logged before init are buffered, then flushed into the DB.
ALC.Debug:Log("Test", "early %d", 1)
ALC:OnInitialize()
local log = ALC_DB and ALC.Settings:GetDB().global.debugLog
check("db created", log ~= nil)
check("early entry flushed", log[1] and log[1].msg == "early 1")
check("init logged", log[#log].msg:find("loaded", 1, true) ~= nil)

-- Ring buffer caps at 500.
for i = 1, 600 do ALC.Debug:Log("Test", "line %d", i) end
check("ring buffer capped", #log == 500)
check("oldest dropped", log[#log].msg == "line 600" and log[1].msg == "line 101")

-- Debug toggle prints only when enabled; errors always print.
local before = #H.chat
ALC.Debug:Log("Test", "quiet")
check("info silent when debug off", #H.chat == before)
ALC.Debug:Error("Test", "boom")
check("error always printed", #H.chat == before + 1)
H.slash("debug on")
check("debug on", ALC.Settings:IsDebug() == true)
before = #H.chat
ALC.Debug:Log("Test", "loud")
check("info printed when debug on", #H.chat == before + 1)
H.slash("debug off")
check("debug off", ALC.Settings:IsDebug() == false)

-- Names on Forever are "First Last": UnitName returns the surname as its second value.
check("player full name has the surname", ALC:PlayerName() == "Tester Moo")
check("missing unit has no name", ALC:UnitFullName("raid7") == nil)
check("realm suffix stripped, surname kept", ALC:NormalizeName("Allemano Moo-ClassicBetaPvP2") == "Allemano Moo")
check("same first name, different surname are different players", ALC:SameName("Allemano Moo", "Allemano Mu") == false)
check("names compare case-insensitively", ALC:SameName("allemano moo", "Allemano Moo-Realm") == true)
check("empty name rejected", ALC:NormalizeName("") == nil and ALC:NormalizeName(nil) == nil)

-- Council list: normalization, dedupe (case-insensitive), removal.
check("add member", ALC.Settings:AddCouncilMember("Ashvane-Realm") == true)
check("duplicate rejected", ALC.Settings:AddCouncilMember("ashvane") == false)
check("second member", ALC.Settings:AddCouncilMember("Veyra") == true)
local council = ALC.Settings:GetCouncil()
check("stored without realm", council[1] == "Ashvane" and #council == 2)
council[1] = "Mutated"
check("GetCouncil returns a copy", ALC.Settings:GetCouncil()[1] == "Ashvane")
check("remove member", ALC.Settings:RemoveCouncilMember("ASHVANE") == true)
check("remove missing", ALC.Settings:RemoveCouncilMember("Nobody") == false)
check("invalid name rejected", ALC.Settings:AddCouncilMember("") == false)

-- Quality threshold validation.
check("default epic", ALC.Settings:GetQualityThreshold() == 4)
check("set rare", ALC.Settings:SetQualityThreshold(3) == true)
check("reject 9", ALC.Settings:SetQualityThreshold(9) == false)
check("reject string", ALC.Settings:SetQualityThreshold("epic") == false)
check("unchanged after reject", ALC.Settings:GetQualityThreshold() == 3)

-- Events fire on settings changes.
local fired
ALC.Events.Register({}, "ALC_SETTINGS_CHANGED", function(_, key) fired = key end)
ALC.Settings:SetQualityThreshold(4)
check("settings event fired", fired == "qualityThreshold")

-- Slash dispatcher.
before = #H.chat
H.slash("bogus")
check("unknown command reported", #H.chat == before + 1)
H.slash("quality uncommon")
check("quality by name", ALC.Settings:GetQualityThreshold() == 2)
H.slash("quality legendary")
check("legendary is not offered", ALC.Settings:GetQualityThreshold() == 2)
H.slash("council add Kaelis")
check("council via slash", ALC.Settings:GetCouncil()[2] == "Kaelis" or ALC.Settings:GetCouncil()[1] == "Kaelis")

dofile("Tests/sessions_test.lua")(check, H)
dofile("Tests/loot_test.lua")(check, H)
dofile("Tests/responses_test.lua")(check, H)
dofile("Tests/voting_test.lua")(check, H)
dofile("Tests/awards_test.lua")(check, H)
dofile("Tests/media_test.lua")(check, H)
dofile("Tests/comm_test.lua")(check, H)
dofile("Tests/recovery_test.lua")(check, H)
dofile("Tests/multi_test.lua")(check, H)
dofile("Tests/details_test.lua")(check, H)
dofile("Tests/recent_test.lua")(check, H)
dofile("Tests/quick_test.lua")(check, H)
dofile("Tests/timer_test.lua")(check, H)
dofile("Tests/trade_test.lua")(check, H)
dofile("Tests/undo_test.lua")(check, H)
dofile("Tests/history_test.lua")(check, H)
dofile("Tests/pause_test.lua")(check, H)
dofile("Tests/rolls_test.lua")(check, H)
dofile("Tests/versions_test.lua")(check, H)
dofile("Tests/disenchant_test.lua")(check, H)
dofile("Tests/limits_test.lua")(check, H)
dofile("Tests/tools_test.lua")(check, H)
dofile("Tests/api_test.lua")(check, H)
dofile("Tests/results_test.lua")(check, H)
dofile("Tests/awardmany_test.lua")(check, H)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)

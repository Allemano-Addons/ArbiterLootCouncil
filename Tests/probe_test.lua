-- Probe: notes whether whispers can be read and sent, keeping facts and never the text.

return function(check, H)
	H.reload("fresh")
	local P = ALC.Probe
	check("the probe exists and is not listening at first", P ~= nil and P:IsListening() == false)

	-- Not listening: nothing is noted
	P:OnWhisper("CHAT_MSG_WHISPER", "hello", "Veyra-Realm")
	check("a whisper is ignored when not listening", #P:GetLog() == 0)

	H.slash("probe whisper on")
	check("/alc probe whisper on starts listening", P:IsListening() == true)

	-- A readable whisper in a raid, calm
	IsInInstance = function() return true, "raid" end
	IsInRaid = function() return true end
	IsInGroup = function() return true end
	UnitAffectingCombat = function() return false end
	P:OnWhisper("CHAT_MSG_WHISPER", "1 bis, 2 os", "Veyra-Realm")
	local e = P:GetLog()[1]
	check("a readable whisper is noted with where it came", e and e.kind == "whisper" and e.textReadable == true and e.senderReadable == true and e.length == 11
		and e.instance == "raid" and e.group == "raid" and e.combat == false)
	check("the text itself is not kept", e.text == nil and e.m == nil)

	-- A whisper with an item link
	P:OnWhisper("CHAT_MSG_WHISPER", "|cff0070dd|Hitem:200::::::::::|h[Crown]|h|r bis", "Veyra-Realm")
	check("a link in the text is noted", P:GetLog()[2].hasLink == true)

	-- A secret whisper in a fight
	local secret = {}
	issecretvalue = function(v) return v == secret end
	UnitAffectingCombat = function() return true end
	P:OnWhisper("CHAT_MSG_WHISPER", secret, "Veyra-Realm")
	local s = P:GetLog()[3]
	check("a secret text is noted as secret, with no length", s.textReadable == false and s.length == nil and s.combat == true)
	P:OnWhisper("CHAT_MSG_WHISPER", "ok", secret)
	check("a secret name is noted too", P:GetLog()[4].textReadable == true and P:GetLog()[4].senderReadable == false)

	-- The summary
	local lines = P:Summary()
	local joined = table.concat(lines, "\n")
	check("the summary counts readable and secret per place", joined:find("raid/raid/calm: 2 readable, 0 secret", 1, true) and joined:find("raid/raid/combat: 1 readable, 1 secret", 1, true))

	-- Replies
	local sent = {}
	SendChatMessage = function(text, kind, _, target) sent[#sent + 1] = { text, kind, target } end
	C_ChatInfo = nil
	local r = P:SendReply("Veyra")
	check("a reply is sent as a whisper and noted as sent", r.ok == true and sent[1][2] == "WHISPER" and sent[1][3] == "Veyra" and P:GetLog()[5].ok == true)
	SendChatMessage = function() error("not allowed here") end
	local refused = P:SendReply("Veyra")
	check("a refused reply is noted with the reason", refused.ok == false and refused.error:find("not allowed", 1, true) ~= nil)

	-- The command and the log
	H.chat = H.chat or {}
	local before = #H.chat
	H.slash("probe")
	check("/alc probe prints a summary", #H.chat > before)
	H.slash("probe clear")
	check("clear forgets what was noted", #P:GetLog() == 0)
	H.slash("probe whisper off")
	check("off stops listening", P:IsListening() == false)
	for _ = 1, 70 do P:SetListening(true) P:OnWhisper("CHAT_MSG_WHISPER", "x", "A") end
	check("the log keeps the last 60", #P:GetLog() == 60)
	P:Clear()
	P:SetListening(false)
	issecretvalue = nil
	IsInInstance, IsInRaid, IsInGroup, UnitAffectingCombat = nil, nil, nil, nil
end

-- HubLog: what the session does is told to Allemano Hub's activity log, when the Hub is installed.

return function(check, H)
	H.reload("fresh")
	local lines = {}
	_G.AllemanoHubLog = function(source, text) lines[#lines + 1] = source .. ": " .. text end

	ALC.Events:Fire("ALC_SESSION_PAUSED", true)
	ALC.Events:Fire("ALC_SESSION_PAUSED", false)
	check("a pause and a resume are told to the Hub", lines[1] == "ALC: Session paused" and lines[2] == "ALC: Session resumed")
	ALC.Events:Fire("ALC_SESSION_ENDED", "s1", "finished", { sid = "s1" })
	check("the end of a session is told, with the reason", lines[#lines] == "ALC: Session s1 ended (finished)")

	-- a Hub that raises an error must not break the session
	_G.AllemanoHubLog = function() error("boom") end
	check("an error in the Hub is swallowed", pcall(function() ALC.Events:Fire("ALC_SESSION_PAUSED", true) end))

	-- and without the Hub nothing happens
	_G.AllemanoHubLog = nil
	check("without the Hub nothing happens", pcall(function() ALC.Events:Fire("ALC_SESSION_PAUSED", true) end))
end

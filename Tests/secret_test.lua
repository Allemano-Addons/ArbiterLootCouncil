-- Secret strings: a name the game hides (the trade partner in an instance) must not raise an error, only count as
-- "no usable name".

return function(check, H)
	H.reload("fresh")
	local secret = {}
	local realUnitName, realSecret = UnitName, issecretvalue
	-- a real secret value raises an error when it is compared or joined: the fake one does too
	local guard = setmetatable({}, { __eq = function() error("attempt to compare a secret string value") end,
		__concat = function() error("attempt to perform string conversion on a secret string value") end })
	secret = guard
	issecretvalue = function(v) return v == nil and false or rawequal(v, secret) end

	UnitName = function(unit)
		if unit == "NPC" then return secret, "Moo" end
		if unit == "target" then return "Veyra", secret end
		return "Tester", "Moo"
	end
	check("a trade partner with a secret first name has no usable name", ALC:UnitFullName("NPC") == nil)
	check("nor has one with a secret surname", ALC:UnitFullName("target") == nil)
	check("a normal unit is still fine", ALC:UnitFullName("player") == "Tester Moo")
	check("a secret text is not a name", ALC:NormalizeName(secret) == nil)
	check("a normal name still normalizes", ALC:NormalizeName("Veyra-Realm") == "Veyra")
	check("a name that is not a text is nothing", ALC:NormalizeName(nil) == nil and ALC:NormalizeName(5) == nil)

	-- The trade window opens with such a partner: no error
	local ok, err = pcall(function() ALC.Trades:OnTradeShow() end)
	check("the trade window opening with a secret partner raises no error: " .. tostring(err), ok)
	local ok2 = pcall(function() return ALC.Trades:FillTrade() end)
	check("filling the trade with a secret partner raises no error", ok2)

	UnitName, issecretvalue = realUnitName, realSecret
end

-- Every texture the addon points at must exist in the addon folder, and the windows
-- must use the ALC mark. A wrong path shows as a green square in the game.

return function(check)
	local UI = ALC.UI
	local PREFIX = "Interface\\AddOns\\ArbiterLootCouncil\\"

	-- "Interface\AddOns\ArbiterLootCouncil\Media\Logo\alc_mark_64" -> "Media/Logo/alc_mark_64.tga"
	local function fileOf(path)
		if path:sub(1, #PREFIX) ~= PREFIX then return nil end
		return (path:sub(#PREFIX + 1):gsub("\\", "/")) .. ".tga"
	end
	local function exists(file)
		local handle = file and io.open(file, "rb")
		if handle then handle:close() return true end
		return false
	end

	check("the media path is inside the addon", fileOf(UI.LOGO) == "Media/Logo/alc_mark_64.tga")
	check("the logo file exists", exists(fileOf(UI.LOGO)))

	local icons = { "council", "history", "summary", "trade", "settings", "vote", "award", "loot", "blind_vote",
		"quorum", "note", "disenchant", "revote", "bank", "addon_check", "warning" }
	local missing = {}
	for _, name in ipairs(icons) do
		if not exists(fileOf(UI.ICONS .. name)) then missing[#missing + 1] = name end
	end
	check("every icon file exists" .. (#missing > 0 and (" (missing: " .. table.concat(missing, ", ") .. ")") or ""), #missing == 0)

	-- The addon list icon in the .toc.
	local toc = io.open("ArbiterLootCouncil.toc", "rb"):read("*a")
	local iconPath = toc:match("## IconTexture:%s*([^\r\n]+)")
	check("the .toc has an icon", iconPath ~= nil)
	check("and its file exists", iconPath ~= nil and exists(fileOf(iconPath)))

	-- The windows use it.
	ALC.Settings:GetDB() -- settings are up
	ALC.LootWindow:Show()
	check("the loot window shows the mark", ALC.LootWindow.rows[1].parent.logo.texture == UI.LOGO)
	ALC.LootWindow:Hide()
	local frameLogo = UI.NewLogo(UIParent, 28)
	check("NewLogo sets the texture and size", frameLogo.texture == UI.LOGO and frameLogo.w == 28 and frameLogo.h == 28)
end

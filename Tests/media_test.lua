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

	-- The rounded shapes: a texture for every radius, cut into pieces.
	local shapeMissing = {}
	for _, radius in ipairs({ 4, 6, 8, 10 }) do
		local files = { "fill_r" .. radius, "ring_r" .. radius .. "_t1", "ring_r" .. radius .. "_t2" }
		for _, name in ipairs(files) do
			if not exists(fileOf(UI.SHAPES .. name)) then shapeMissing[#shapeMissing + 1] = name end
		end
	end
	check("every rounded shape texture exists" .. (#shapeMissing > 0 and (" (missing: " .. table.concat(shapeMissing, ", ") .. ")") or ""), #shapeMissing == 0)

	local holder = CreateFrame("Frame", nil, UIParent)
	local fill = UI.NewFill(holder, 8)
	check("a fill is nine pieces of the right shape", #fill.pieces == 9 and fill.pieces[1].texture == UI.SHAPES .. "fill_r8")
	check("with the corners at their own size", fill.pieces[1].w == 10 and fill.pieces[1].h == 10)
	check("a radius between two shapes takes the nearest", UI.NewFill(holder, 7).pieces[1].texture == UI.SHAPES .. "fill_r6"
		and UI.NewFill(holder, 100).pieces[1].texture == UI.SHAPES .. "fill_r10" and UI.NewFill(holder, 1).pieces[1].texture == UI.SHAPES .. "fill_r4")
	fill:SetColorTexture(0.1, 0.2, 0.3, 0.4)
	check("colour reaches every piece", fill.pieces[1].vertexColor[3] == 0.3 and fill.pieces[9].vertexColor[4] == 0.4)
	UI.SetTextureColor(fill, { 1, 0.5, 0.25 }, 0.5)
	check("UI.SetTextureColor works on a fill", fill.pieces[5].vertexColor[2] == 0.5 and fill.pieces[5].vertexColor[4] == 0.5)
	fill:Hide()
	check("a fill hides as a whole", fill.pieces[1].shown == false and fill.pieces[9].shown == false)
	fill:Show()
	check("and shows again", fill.pieces[1].shown == true)

	local ring = UI.AddBorder(holder, UI.color.gold, 2, 10)
	check("a border is eight pieces, no centre", #ring.pieces == 8 and ring.pieces[1].texture == UI.SHAPES .. "ring_r10_t2")
	check("a border starts in its colour", ring.pieces[1].vertexColor[1] == UI.color.gold[1])
	ring:SetColor(UI.color.border)
	check("and changes colour", ring.pieces[8].vertexColor[1] == UI.color.border[1])
	check("thickness is 1 or 2", UI.AddBorder(holder, UI.color.gold, 3, 6).pieces[1].texture == UI.SHAPES .. "ring_r6_t1")

	-- Each window has its own band of frame levels, so windows never mix when they overlap.
	local loot, response, council = ALC.LootWindow.rows[1].parent, ALC.ResponseWindow.buttons[1].parent, ALC.CouncilWindow.rows[1].parent
	check("windows sit in separate level bands", loot.level == 20 and response.level == 40 and council.level == 60)
	check("and the clicked one comes to the front", loot.toplevel and response.toplevel and council.toplevel)

	-- The windows use it.
	ALC.Settings:GetDB() -- settings are up
	ALC.LootWindow:Show()
	check("the loot window shows the mark", ALC.LootWindow.rows[1].parent.logo.texture == UI.LOGO)
	ALC.LootWindow:Hide()
	local frameLogo = UI.NewLogo(UIParent, 28)
	check("NewLogo sets the texture and size", frameLogo.texture == UI.LOGO and frameLogo.w == 28 and frameLogo.h == 28)
end

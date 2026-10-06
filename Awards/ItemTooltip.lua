-- ItemTooltip: the tooltip of an item that was awarded lately says who won it and what became of it ("Awarded to Veyra Moo
-- (BiS)", "Awaiting trade"). On every item tooltip in the game (bags, chat links, the loot window, the trade queue), so the
-- loot master sees at a glance which item in the bags is for whom. Only awards of the last week, nothing for other items.

local ALC = ALC
local L = ALC.L

local ItemTooltip = {}
ALC.ItemTooltip = ItemTooltip

local WINDOW = 7 * 86400
local MAX_SHOWN = 2

local STATUS_COLOR = {
	awaiting = { 0.90, 0.66, 0.24 }, delivered = { 0.30, 0.75, 0.40 }, returned = { 0.90, 0.66, 0.24 },
	traded = { 0.54, 0.71, 0.97 }, revoked = { 0.60, 0.60, 0.60 },
}

-- The lines for an item: { { text, r, g, b }, ... }, empty when it was not awarded in the last week.
function ItemTooltip:LinesFor(itemID)
	local lines = {}
	if not itemID or not ALC.Settings or not ALC.Settings:GetDB() then return lines end
	local log = ALC.Settings:GetAwardLog()
	local oldest = time() - WINDOW
	local shown = 0
	for i = #log, math.max(1, #log - 300), -1 do
		local r = log[i]
		if (r.time or 0) < oldest then break end
		if r.itemID == itemID and not r.revoked and shown < MAX_SHOWN then
			shown = shown + 1
			local cc = ALC.UI and ALC.UI.ClassColor(r.class) or { 1, 1, 1 }
			local label = r.responseLabel or (ALC.Responses and ALC.Responses:GetLabel(r.response)) or ""
			lines[#lines + 1] = {
				text = string.format("ALC: %s |cff%02x%02x%02x%s|r%s", L["awarded to"], math.floor(cc[1] * 255 + 0.5), math.floor(cc[2] * 255 + 0.5),
					math.floor(cc[3] * 255 + 0.5), r.winner, label ~= "" and (" (" .. label .. ")") or ""),
				r = 0.80, g = 0.82, b = 0.85,
			}
			local kind, text = ALC.Awards.StatusOf(r)
			if kind and kind ~= "revoked" then
				local color = STATUS_COLOR[kind] or { 0.8, 0.8, 0.8 }
				lines[#lines + 1] = { text = "      " .. text, r = color[1], g = color[2], b = color[3] }
			end
		end
	end
	return lines
end

-- Adds the lines to a tooltip that shows an item (once per time it is shown).
function ItemTooltip:Add(tooltip)
	if not tooltip or not tooltip.GetItem then return end
	local _, link = tooltip:GetItem()
	if not link or tooltip.alcItemShown == link then return end
	local _, itemID = ALC:ParseItem(link)
	local lines = self:LinesFor(itemID)
	if #lines == 0 then return end
	tooltip.alcItemShown = link
	for _, line in ipairs(lines) do tooltip:AddLine(line.text, line.r, line.g, line.b) end
	if tooltip.Show then tooltip:Show() end
end

local hooked = {}
local function hook(tooltip)
	if not tooltip or hooked[tooltip] or not tooltip.HookScript then return end
	hooked[tooltip] = true
	pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(self) ItemTooltip:Add(self) end)
	pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", function(self) self.alcItemShown = nil end)
end

function ItemTooltip:Init()
	-- The newer tooltip API calls us after an item is put in a tooltip; the older one has a script for it.
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
		pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tooltip) ItemTooltip:Add(tooltip) end)
	end
	hook(GameTooltip)
	hook(ItemRefTooltip)
	hook(ShoppingTooltip1)
end

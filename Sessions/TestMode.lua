-- Test mode: `/alc test` starts a real session, locally, for an item from your bags,
-- so the whole flow can be exercised without a raid. It only runs outside a group,
-- where you are your own loot master.

local ALC = ALC
local L = ALC.L

local NUM_BAG_SLOTS = NUM_BAG_SLOTS or 4

local TestMode = {}
ALC.TestMode = TestMode

-- Replaceable in tests.
function TestMode.GetBagItemLinks()
	local container = C_Container
	local numSlots = (container and container.GetContainerNumSlots) or GetContainerNumSlots
	local getLink = (container and container.GetContainerItemLink) or GetContainerItemLink
	local links = {}
	if not numSlots or not getLink then return links end
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, numSlots(bag) or 0 do
			local link = getLink(bag, slot)
			if link then links[#links + 1] = link end
		end
	end
	return links
end

-- The best item in the bags: highest quality first, bag order breaks ties.
function TestMode:PickItem()
	local best, bestQuality
	for _, link in ipairs(self.GetBagItemLinks()) do
		local quality = select(3, ALC:GetItemInfo(link)) or -1
		if not best or quality > bestQuality then best, bestQuality = link, quality end
	end
	return best
end

-- The best `count` items in the bags, best first (a stack of the same item counts once).
function TestMode:PickItems(count)
	local picked, seen = {}, {}
	for _, link in ipairs(self.GetBagItemLinks()) do
		local itemString = ALC:ParseItem(link)
		if itemString and not seen[itemString] then
			seen[itemString] = true
			picked[#picked + 1] = { link = link, quality = select(3, ALC:GetItemInfo(link)) or -1, order = #picked }
		end
	end
	table.sort(picked, function(a, b)
		if a.quality ~= b.quality then return a.quality > b.quality end
		return a.order < b.order
	end)
	local links = {}
	for i = 1, math.min(count, #picked) do links[i] = picked[i].link end
	return links
end

function TestMode:Start(count)
	if IsInGroup() then
		return false, L["Test mode only runs outside a group."]
	end
	local links = self:PickItems(math.max(1, count or 1))
	if #links == 0 then
		return false, L["You have no items in your bags to test with."]
	end
	return ALC.Sessions:StartItems(links)
end

ALC.Commands:Register("test", function(arg)
	local ok, message = TestMode:Start(tonumber(arg))
	if not ok then ALC:Print(message) end
end, L["start a solo test session with items from your bags: /alc test [number of items]"])

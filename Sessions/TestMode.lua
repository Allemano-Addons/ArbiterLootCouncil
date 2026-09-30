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

--------------------------------------------------------------------------------
-- Made-up players, to see the windows with a full raid
--------------------------------------------------------------------------------
TestMode.random = math.random -- replaceable in tests

local FIRST_NAMES = { "Alyssa", "Bjorn", "Cedric", "Dagny", "Elric", "Freya", "Gunnar", "Helga", "Ivar", "Jorun",
	"Kael", "Liv", "Magnus", "Nora", "Olaf", "Petra", "Quill", "Ragna", "Sven", "Tyra",
	"Ulf", "Vera", "Wolf", "Xena", "Yngve", "Zara", "Arvid", "Britt", "Calle", "Disa",
	"Erik", "Frida", "Gisle", "Hedda", "Isak", "Jonna", "Knut", "Lena", "Mats", "Nils" }
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local RANKS = { { "Guild Master", 0 }, { "Officer", 1 }, { "Raider", 4 }, { "Raider", 4 }, { "Raider", 4 }, { "Trial", 6 } }
local NOTES = { "Main spec", "Alt", "4 piece", "Need it for progress", "Second piece", "Off piece", "WTH" }
local MAX_TEST_CANDIDATES = #FIRST_NAMES

-- Picks an answer for a made-up player: the first answers are the likeliest, PASS the least.
local function pickResponse(set)
	local total, weights = 0, {}
	for i, r in ipairs(set) do
		weights[i] = (r.id == "PASS") and 1.5 or (i <= 2 and 3 or 2)
		total = total + weights[i]
	end
	local roll = TestMode.random() * total
	for i, r in ipairs(set) do
		roll = roll - weights[i]
		if roll <= 0 then return r.id end
	end
	return set[#set].id
end

local function pick(list)
	return list[math.min(#list, math.floor(TestMode.random() * #list) + 1)]
end

-- Gives the running session `count` made-up players, who answer most of its items.
function TestMode:AddCandidates(count)
	local session = ALC.Sessions:GetSession()
	if not session or not session.isLM then return 0 end
	local set = session.responses
	local added = 0
	for index = 1, math.min(count, MAX_TEST_CANDIDATES, ALC.Constants.MAX_CANDIDATES) do
		local name = FIRST_NAMES[index] .. " Testa"
		local class = pick(CLASSES)
		local rank = pick(RANKS)
		for item, target in ipairs(session.items) do
			if not target.winner and TestMode.random() < 0.85 then -- some stay silent
				local gear = {}
				if TestMode.random() < 0.6 then gear[1] = session.items[(item % #session.items) + 1].itemString end
				local entry = { name = name, class = class, response = pickResponse(set), gear = gear,
					rank = rank[1], rankIndex = rank[2] }
				if TestMode.random() < 0.25 then entry.note = pick(NOTES) end
				if ALC.Candidates:Inject(item, entry) then added = added + 1 end
			end
		end
	end
	return added
end

local pendingCandidates = 0

function TestMode:Start(count, candidates)
	if IsInGroup() then
		return false, L["Test mode only runs outside a group."]
	end
	local links = self:PickItems(math.max(1, count or 1))
	if #links == 0 then
		return false, L["You have no items in your bags to test with."]
	end
	-- Set before the start: the session may come into being at once (and in the game a moment later).
	pendingCandidates = math.max(0, math.min(candidates or 0, MAX_TEST_CANDIDATES))
	local ok, result = ALC.Sessions:StartItems(links)
	if not ok then pendingCandidates = 0 end
	return ok, result
end

-- The session comes into being a moment after it is started; the players join then.
ALC.Events.Register(TestMode, "ALC_SESSION_STARTED", function(_, session)
	if pendingCandidates > 0 and session.isLM then
		local count = pendingCandidates
		pendingCandidates = 0
		TestMode:AddCandidates(count)
	end
end)

ALC.Commands:Register("test", function(arg)
	local items, candidates = string.match(arg or "", "^(%d*)%s*(%d*)$")
	local ok, message = TestMode:Start(tonumber(items), tonumber(candidates))
	if not ok then ALC:Print(message) end
end, L["start a solo test session with items from your bags and made-up players: /alc test [items] [players]"])

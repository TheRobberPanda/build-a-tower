--!strict
-- Weekly featured tower. Likes are counted per UTC week in an OrderedDataStore;
-- the featured tower for week W is the most liked tower of week W-1. When a week
-- ends, exactly one server settles it (claimed via UpdateAsync) and gives the top
-- 3 racers on that week's featured tower a badge and Bricks.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Retry = require(script.Parent.Parent.Lib.Retry)
local ProgressionService = require(script.Parent.ProgressionService)
local SocialService = require(script.Parent.SocialService)
local TowerService = require(script.Parent.TowerService)

local FeaturedService = {}

local WEEK = 7 * 86400
local retry: Retry.Options = {
	attempts = Config.DS_ATTEMPTS,
	baseDelay = Config.DS_BASE_DELAY,
	maxDelay = Config.DS_MAX_DELAY,
	wait = task.wait,
}
local cache: { [number]: { at: number, keys: { string } } } = {}

local function week(): number
	return os.time() // WEEK
end

local function store(w: number): OrderedDataStore
	return DataStoreService:GetOrderedDataStore(Config.FEATURED_PREFIX .. w)
end

-- Most liked tower owners of week w, best first (cached 5 minutes).
local function topOf(w: number, count: number): { string }
	local c = cache[w]
	if c and os.clock() - c.at < 300 then
		return c.keys
	end
	local keys = {}
	local ok, pages = Retry.call(retry, function()
		return store(w):GetSortedAsync(false, count)
	end)
	if ok and pages then
		for _, item in pages:GetCurrentPage() do
			table.insert(keys, tostring(item.key))
		end
	end
	cache[w] = { at = os.clock(), keys = keys }
	return keys
end

-- The featured tower owner for week w (top of the previous week), or nil.
function FeaturedService.featuredOwner(w: number?): number?
	local keys = topOf((w or week()) - 1, 1)
	return if keys[1] then tonumber(keys[1]) else nil
end

local function settle(w: number)
	local claimed = false
	Retry.call(retry, function()
		return DataStoreService:GetDataStore(Config.FEATURED_SETTLE_STORE)
			:UpdateAsync(tostring(w), function(old: any)
				if old then
					claimed = false
					return nil
				end
				claimed = true
				return true
			end)
	end)
	if not claimed then
		return
	end
	local owner = FeaturedService.featuredOwner(w)
	local tower = owner and TowerService.getPublished(owner)
	if not owner or not tower then
		return
	end
	for place, e in TowerService.published():topTimes(owner, tower.hash, 3) or {} do
		local racer = tonumber(e.key)
		if racer then
			ProgressionService.prize(racer, "FeaturedPodium", Config.FEATURED_PODIUM_BRICKS)
			SocialService.notify(
				racer,
				string.format(
					"You placed #%d on featured tower %s! +%d Coins",
					place,
					tower.name,
					Config.FEATURED_PODIUM_BRICKS
				)
			)
		end
	end
end

function FeaturedService.init()
	TowerService.Liked:Connect(function(ownerId: number, likes: number)
		local w = week()
		Retry.call(retry, function()
			return store(w):IncrementAsync(tostring(ownerId), likes)
		end)
	end)
	TowerService.setFeaturedSource(function(): { string }
		local keys = {}
		local featured = FeaturedService.featuredOwner()
		if featured then
			table.insert(keys, tostring(featured))
		end
		for _, key in topOf(week(), 25) do -- trending this week
			if key ~= keys[1] then
				table.insert(keys, key)
			end
		end
		return keys
	end)
	task.spawn(function()
		while true do
			settle(week() - 1)
			task.wait(3600)
		end
	end)
end

return FeaturedService

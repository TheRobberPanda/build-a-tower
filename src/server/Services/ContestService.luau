--!strict
-- Seasonal build contests (schedule in Config.CONTESTS). During the entry window
-- builders enter their published tower; during voting each player has
-- Config.CONTEST_VOTES votes (not on their own tower, one per tower). After the
-- contest one server settles it once and prizes the top 3.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Events = require(ReplicatedStorage.Shared.Events)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local Retry = require(script.Parent.Parent.Lib.Retry)
local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)
local SocialService = require(script.Parent.SocialService)
local TowerService = require(script.Parent.TowerService)

local ContestService = {}

local retry: Retry.Options = {
	attempts = Config.DS_ATTEMPTS,
	baseDelay = Config.DS_BASE_DELAY,
	maxDelay = Config.DS_MAX_DELAY,
	wait = task.wait,
}
local limiter = RateLimiter.new(5, 1)
local cache: { [string]: { at: number, keys: { string } } } = {}

local function store(id: string): OrderedDataStore
	return DataStoreService:GetOrderedDataStore(Config.CONTEST_STORE_PREFIX .. id)
end

local function entries(id: string, count: number): { string }
	local c = cache[id]
	if c and os.clock() - c.at < 30 then
		return c.keys
	end
	local keys = {}
	local ok, pages = Retry.call(retry, function()
		return store(id):GetSortedAsync(false, count)
	end)
	if ok and pages then
		for _, item in pages:GetCurrentPage() do
			table.insert(keys, tostring(item.key))
		end
	end
	cache[id] = { at = os.clock(), keys = keys }
	return keys
end

local function votesUsed(player: Player, id: string): { number }
	local data = DataService.get(player)
	if not data then
		return {}
	end
	local used = data.contestVotes[id]
	if not used then
		used = {}
		data.contestVotes[id] = used
	end
	return used
end

local function onInfo(player: Player): { [string]: any }?
	local contest, phase = Events.contest(os.time())
	if not contest or not phase then
		return nil
	end
	return {
		id = contest.id,
		theme = contest.theme,
		phase = phase,
		endsIn = (if phase == "entries" then contest.votingFrom else contest.ends) - os.time(),
		votesLeft = Config.CONTEST_VOTES - #votesUsed(player, contest.id),
		entered = table.find(entries(contest.id, 100), tostring(player.UserId)) ~= nil,
	}
end

local function onEnter(player: Player): (boolean, string?)
	local contest, phase = Events.contest(os.time())
	if not limiter:allow(player) or not contest or phase ~= "entries" then
		return false, "Entries are closed"
	end
	if not TowerService.getPublished(player.UserId) then
		return false, "Publish a tower first"
	end
	local ok = Retry.call(retry, function()
		return store(contest.id):UpdateAsync(tostring(player.UserId), function(old: any)
			return if type(old) == "number" then nil else 0 -- keep votes if already entered
		end)
	end)
	cache[contest.id] = nil
	return ok, if ok then nil else "Try again"
end

local function onVote(player: Player, ownerId: any): (boolean, string?)
	local contest, phase = Events.contest(os.time())
	if not limiter:allow(player) or not contest or phase ~= "voting" then
		return false, "Voting is closed"
	end
	if type(ownerId) ~= "number" or ownerId == player.UserId then
		return false, "Can't vote for that"
	end
	if not table.find(entries(contest.id, 100), tostring(ownerId)) then
		return false, "Not entered"
	end
	local used = votesUsed(player, contest.id)
	if #used >= Config.CONTEST_VOTES or table.find(used, ownerId) then
		return false, "No votes left for that"
	end
	table.insert(used, ownerId)
	local ok = Retry.call(retry, function()
		return store(contest.id):IncrementAsync(tostring(ownerId), 1)
	end)
	if not ok then
		table.remove(used, #used)
		return false, "Try again"
	end
	return true, nil
end

local function settle()
	local now = os.time()
	for _, contest in Config.CONTESTS do
		if now < contest.ends then
			continue
		end
		local claimed = false
		Retry.call(retry, function()
			return DataStoreService:GetDataStore(Config.FEATURED_SETTLE_STORE)
				:UpdateAsync("contest_" .. contest.id, function(old: any)
					if old then
						claimed = false
						return nil
					end
					claimed = true
					return true
				end)
		end)
		if claimed then
			for place, key in entries(contest.id, 3) do
				local ownerId = tonumber(key)
				if ownerId then
					ProgressionService.prize(ownerId, "ContestWinner", Config.CONTEST_PRIZE_BRICKS)
					SocialService.notify(
						ownerId,
						string.format(
							"Your tower placed #%d in the %s contest! +%d Bricks",
							place,
							contest.theme,
							Config.CONTEST_PRIZE_BRICKS
						)
					)
				end
			end
		end
	end
end

function ContestService.init()
	TowerService.setContestSource(function(): { string }
		local contest = Events.contest(os.time())
		return if contest then entries(contest.id, 50) else {}
	end)
	Remotes.func("ContestInfo").OnServerInvoke = onInfo
	Remotes.func("EnterContest").OnServerInvoke = onEnter
	Remotes.func("VoteContest").OnServerInvoke = onVote
	Players.PlayerRemoving:Connect(function(player)
		limiter:forget(player)
	end)
	task.spawn(function()
		while true do
			settle()
			task.wait(3600)
		end
	end)
end

return ContestService

--!strict
-- Per-tower play stats for discovery: starts, finishes, likes, difficulty and
-- the Popular / Hardest ranked lists. Counts are batched in memory and flushed
-- periodically so a busy server costs a few writes a minute, not one per run.
--
-- stats   (DataStore)        key = ownerId -> { hash, starts, finishes, likes, best?, bestBy? }
--                            Counters reset when the tower version (hash) changes.
-- popular (OrderedDataStore) key = ownerId -> likes * 5 + finishes
-- hardest (OrderedDataStore) key = ownerId -> difficulty score (0 = not enough data)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Retry = require(script.Parent.Retry)

export type Stats = {
	hash: string,
	starts: number,
	finishes: number,
	likes: number,
	best: number?, -- record ms
	bestBy: number?, -- record holder userId
}

export type Deps = {
	stats: any,
	popular: any,
	hardest: any,
	wait: (number) -> (),
	budgetReady: (() -> boolean)?,
	log: ((string) -> ())?,
}

type Pending =
	{ hash: string, starts: number, finishes: number, likes: number, best: number?, bestBy: number? }

local TowerStats = {}
TowerStats.__index = TowerStats

export type TowerStats = typeof(setmetatable(
	{} :: { _deps: Deps, _retry: Retry.Options, _pending: { [number]: Pending } },
	TowerStats
))

function TowerStats.new(deps: Deps): TowerStats
	return setmetatable({
		_deps = deps,
		_retry = {
			attempts = Config.DS_ATTEMPTS,
			baseDelay = Config.DS_BASE_DELAY,
			maxDelay = Config.DS_MAX_DELAY,
			wait = deps.wait,
			budgetReady = deps.budgetReady,
			log = deps.log,
		},
		_pending = {},
	}, TowerStats)
end

-- Difficulty label from completion rate. "New" until enough attempts.
function TowerStats.difficulty(starts: number, finishes: number): string
	if starts < Config.DIFFICULTY_MIN_STARTS then
		return "New"
	end
	local rate = finishes / starts
	if rate >= 0.6 then
		return "Easy"
	elseif rate >= 0.3 then
		return "Medium"
	elseif rate >= 0.1 then
		return "Hard"
	end
	return "Insane"
end

-- Integer for the Hardest list: higher = harder, 0 = not ranked yet.
function TowerStats.hardScore(starts: number, finishes: number): number
	if starts < Config.DIFFICULTY_MIN_STARTS then
		return 0
	end
	return math.floor((1 - finishes / starts) * 1000) + 1
end

function TowerStats.popularScore(s: Stats): number
	return s.likes * 5 + s.finishes
end

local function pendingFor(self: TowerStats, ownerId: number, hash: string): Pending
	local p = self._pending[ownerId]
	if not p or p.hash ~= hash then
		p = { hash = hash, starts = 0, finishes = 0, likes = 0 }
		self._pending[ownerId] = p
	end
	return p
end

function TowerStats.addStart(self: TowerStats, ownerId: number, hash: string)
	local p = pendingFor(self, ownerId, hash)
	p.starts += 1
end

function TowerStats.addFinish(self: TowerStats, ownerId: number, hash: string, racerId: number, ms: number)
	local p = pendingFor(self, ownerId, hash)
	p.finishes += 1
	if not p.best or ms < p.best then
		p.best = ms
		p.bestBy = racerId
	end
end

-- Caller dedupes likes per player (PlayerData.liked).
function TowerStats.addLike(self: TowerStats, ownerId: number, hash: string)
	local p = pendingFor(self, ownerId, hash)
	p.likes += 1
end

local function clean(raw: any, hash: string): Stats
	if type(raw) == "table" and raw.hash == hash then
		local function n(v: any): number
			return if type(v) == "number" and v == v and v >= 0 then math.floor(v) else 0
		end
		return {
			hash = hash,
			starts = n(raw.starts),
			finishes = n(raw.finishes),
			likes = n(raw.likes),
			best = if type(raw.best) == "number" then raw.best else nil,
			bestBy = if type(raw.bestBy) == "number" then raw.bestBy else nil,
		}
	end
	return { hash = hash, starts = 0, finishes = 0, likes = 0 }
end

-- Writes all pending counters. Failed towers stay pending for the next flush.
function TowerStats.flush(self: TowerStats)
	local deps = self._deps
	local batch = self._pending
	self._pending = {}
	for ownerId, p in batch do
		local key = tostring(ownerId)
		local result: Stats? = nil
		local ok = Retry.call(self._retry, function()
			return deps.stats:UpdateAsync(key, function(old: any)
				local s = clean(old, p.hash)
				s.starts += p.starts
				s.finishes += p.finishes
				s.likes += p.likes
				if p.best and (not s.best or p.best < s.best) then
					s.best = p.best
					s.bestBy = p.bestBy
				end
				result = s
				return s
			end)
		end)
		local s = result
		if not ok or not s then
			-- Merge back so nothing is lost (newer pending for the same hash adds up).
			local cur = self._pending[ownerId]
			if not cur or cur.hash == p.hash then
				local merged = cur or { hash = p.hash, starts = 0, finishes = 0, likes = 0 }
				merged.starts += p.starts
				merged.finishes += p.finishes
				merged.likes += p.likes
				if p.best and (not merged.best or p.best < merged.best) then
					merged.best = p.best
					merged.bestBy = p.bestBy
				end
				self._pending[ownerId] = merged
			end
			continue
		end
		Retry.call(self._retry, function()
			return deps.popular:SetAsync(key, TowerStats.popularScore(s))
		end)
		Retry.call(self._retry, function()
			return deps.hardest:SetAsync(key, TowerStats.hardScore(s.starts, s.finishes))
		end)
	end
end

-- Stats for the current tower version (zeros if none yet or version changed).
function TowerStats.get(self: TowerStats, ownerId: number, hash: string): Stats
	local deps = self._deps
	local ok, raw = Retry.call(self._retry, function()
		return deps.stats:GetAsync(tostring(ownerId))
	end)
	return clean(if ok then raw else nil, hash)
end

local function page(self: TowerStats, store: any, count: number): { { key: string, value: number } }?
	local ok, pages = Retry.call(self._retry, function()
		return store:GetSortedAsync(false, math.clamp(count, 1, 100), 1)
	end)
	if not ok then
		return nil
	end
	local out = {}
	for _, item in pages:GetCurrentPage() do
		table.insert(out, { key = tostring(item.key), value = item.value })
	end
	return out
end

function TowerStats.popularPage(self: TowerStats, count: number)
	return page(self, self._deps.popular, count)
end

function TowerStats.hardestPage(self: TowerStats, count: number)
	return page(self, self._deps.hardest, count)
end

-- Drops a tower from the ranked lists (hidden after reports).
function TowerStats.unlist(self: TowerStats, ownerId: number)
	local deps = self._deps
	for _, store in { deps.popular, deps.hardest } do
		Retry.call(self._retry, function()
			return store:RemoveAsync(tostring(ownerId))
		end)
	end
end

return TowerStats

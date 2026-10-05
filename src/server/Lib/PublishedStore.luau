--!strict
-- Published towers, the browse list and per-tower leaderboards.
-- Stores are injected (fakes in tests, DataStoreService in game).
--
-- published  (DataStore)        key = ownerId -> PublishedTower
-- browse     (OrderedDataStore) key = ownerId -> publishedAt (newest first)
-- leaderboard(OrderedDataStore) one per (owner, tower hash), key = racerId -> best ms (ascending)
-- reports    (DataStore)        key = ownerId -> { hash, by = {reporterIds} } for the current version

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local TowerCodec = require(ReplicatedStorage.Shared.TowerCodec)
local Types = require(ReplicatedStorage.Shared.Types)
local Retry = require(script.Parent.Retry)

type Tower = Types.Tower
type PublishedTower = Types.PublishedTower

export type Entry = { key: string, value: number }

export type Deps = {
	published: any, -- GetAsync/UpdateAsync
	browse: any, -- OrderedDataStore
	leaderboard: (name: string) -> any, -- returns an OrderedDataStore
	reports: any, -- DataStore
	now: () -> number,
	wait: (number) -> (),
	budgetReady: (() -> boolean)?,
	log: ((string) -> ())?,
}

local PublishedStore = {}
PublishedStore.__index = PublishedStore

export type PublishedStore =
	typeof(setmetatable({} :: { _deps: Deps, _retry: Retry.Options }, PublishedStore))

function PublishedStore.new(deps: Deps): PublishedStore
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
	}, PublishedStore)
end

function PublishedStore.leaderboardName(ownerId: number, hash: string): string
	-- OrderedDataStore names max 50 chars; the hash prefix is enough to separate versions
	return Config.LEADERBOARD_PREFIX .. tostring(ownerId) .. "_" .. string.sub(hash, 1, 16)
end

-- Caller must already have checked verifiedHash == hash(tower).
function PublishedStore.publish(
	self: PublishedStore,
	ownerId: number,
	name: string,
	tower: Tower
): (boolean, string?)
	local ok, err = TowerCodec.validate(tower)
	if not ok then
		return false, err
	end
	local record: PublishedTower = {
		v = Config.SCHEMA_VERSION,
		owner = ownerId,
		name = name,
		hash = TowerCodec.hash(tower),
		pieces = tower.pieces,
		publishedAt = self._deps.now(),
	}
	local deps = self._deps
	local key = tostring(ownerId)
	if self:isHidden(ownerId, record.hash) then
		return false, "hidden after reports"
	end
	-- Tower first, then the browse entry, so the list never points at a missing tower.
	local wrote = Retry.call(self._retry, function()
		return deps.published:UpdateAsync(key, function()
			return record
		end)
	end)
	if not wrote then
		return false, "datastore"
	end
	local listed = Retry.call(self._retry, function()
		return deps.browse:SetAsync(key, math.floor(record.publishedAt))
	end)
	if not listed then
		return false, "browse"
	end
	return true, record.hash
end

-- True if this exact tower version collected enough reports to be hidden.
function PublishedStore.isHidden(self: PublishedStore, ownerId: number, hash: string): boolean
	local deps = self._deps
	local ok, raw = Retry.call(self._retry, function()
		return deps.reports:GetAsync(tostring(ownerId))
	end)
	return ok
		and type(raw) == "table"
		and raw.hash == hash
		and type(raw.by) == "table"
		and #raw.by >= Config.REPORTS_TO_HIDE
end

-- One report per reporter per tower version. Owners can't report themselves.
-- Returns true when this report hid the tower from the browse list.
function PublishedStore.report(
	self: PublishedStore,
	ownerId: number,
	hash: string,
	reporterId: number
): boolean
	if reporterId == ownerId then
		return false
	end
	local deps = self._deps
	local hide = false
	local ok = Retry.call(self._retry, function()
		return deps.reports:UpdateAsync(tostring(ownerId), function(old: any)
			hide = false
			local rec = if type(old) == "table"
					and old.hash == hash
					and type(old.by) == "table"
				then old
				else { hash = hash, by = {} }
			if table.find(rec.by, reporterId) or #rec.by >= Config.REPORTS_TO_HIDE then
				return nil
			end
			table.insert(rec.by, reporterId)
			hide = #rec.by >= Config.REPORTS_TO_HIDE
			return rec
		end)
	end)
	if ok and hide then
		Retry.call(self._retry, function()
			return deps.browse:RemoveAsync(tostring(ownerId))
		end)
	end
	return ok and hide
end

-- Loads and re-validates a published tower (data from the store is untrusted too).
function PublishedStore.get(self: PublishedStore, ownerId: number): PublishedTower?
	local deps = self._deps
	local ok, raw = Retry.call(self._retry, function()
		return deps.published:GetAsync(tostring(ownerId))
	end)
	if not ok or type(raw) ~= "table" then
		return nil
	end
	local tower, dropped = TowerCodec.sanitize(raw)
	if not tower or dropped > 0 or type(raw.name) ~= "string" then
		return nil
	end
	return {
		v = tower.v,
		owner = ownerId,
		name = string.sub(raw.name, 1, Config.TOWER_NAME_MAX),
		hash = TowerCodec.hash(tower),
		pieces = tower.pieces,
		publishedAt = if type(raw.publishedAt) == "number" then raw.publishedAt else 0,
	}
end

local function readPage(self: PublishedStore, store: any, ascending: boolean, count: number): { Entry }?
	local ok, pages = Retry.call(self._retry, function()
		return store:GetSortedAsync(ascending, math.clamp(count, 1, 100))
	end)
	if not ok then
		return nil
	end
	local out: { Entry } = {}
	for _, item in pages:GetCurrentPage() do
		table.insert(out, { key = tostring(item.key), value = item.value })
	end
	return out
end

-- Newest published towers first.
function PublishedStore.browsePage(self: PublishedStore, count: number): { Entry }?
	return readPage(self, self._deps.browse, false, count)
end

function PublishedStore.topTimes(
	self: PublishedStore,
	ownerId: number,
	hash: string,
	count: number
): { Entry }?
	return readPage(self, self._deps.leaderboard(PublishedStore.leaderboardName(ownerId, hash)), true, count)
end

-- Records ms only if it beats the racer's stored best. Returns (improved, previous best ms?).
function PublishedStore.submitTime(
	self: PublishedStore,
	ownerId: number,
	hash: string,
	racerId: number,
	ms: number
): (boolean, number?)
	if ms % 1 ~= 0 or ms < Config.MIN_RUN_MS or ms > Config.MAX_RUN_MS then
		return false
	end
	local store = self._deps.leaderboard(PublishedStore.leaderboardName(ownerId, hash))
	local improved = false
	local previous: number? = nil
	local ok = Retry.call(self._retry, function()
		return store:UpdateAsync(tostring(racerId), function(old: any)
			previous = if type(old) == "number" then old else nil
			if type(old) == "number" and old <= ms then
				improved = false
				return nil
			end
			improved = true
			return ms
		end)
	end)
	return ok and improved, previous
end

return PublishedStore

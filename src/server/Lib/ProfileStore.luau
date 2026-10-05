--!strict
-- Session-locked player records on top of any object with UpdateAsync(key, transform).
-- The store, clock and wait are injected so tests can use a fake DataStore.
--
-- Record: { v = schema, lock = {j = jobId, t = time}?, data = PlayerData, quarantine = any? }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local TowerCodec = require(ReplicatedStorage.Shared.TowerCodec)
local Types = require(ReplicatedStorage.Shared.Types)
local Retry = require(script.Parent.Retry)
local SessionLock = require(script.Parent.SessionLock)

type PlayerData = Types.PlayerData

export type UpdateStore = {
	UpdateAsync: (self: any, key: string, transform: (any, any) -> any) -> any,
}

export type Deps = {
	store: UpdateStore,
	jobId: string,
	now: () -> number,
	wait: (number) -> (),
	budgetReady: (() -> boolean)?,
	log: ((string) -> ())?,
}

export type LoadError = "datastore" | "locked" | "newer"

local ProfileStore = {}
ProfileStore.__index = ProfileStore

export type ProfileStore = typeof(setmetatable(
	{} :: {
		_deps: Deps,
		_retry: Retry.Options,
		_busy: { [string]: boolean },
	},
	ProfileStore
))

function ProfileStore.new(deps: Deps): ProfileStore
	local self = setmetatable({
		_deps = deps,
		_retry = {
			attempts = Config.DS_ATTEMPTS,
			baseDelay = Config.DS_BASE_DELAY,
			maxDelay = Config.DS_MAX_DELAY,
			wait = deps.wait,
			budgetReady = deps.budgetReady,
			log = deps.log,
		},
		_busy = {},
	}, ProfileStore)
	return self
end

function ProfileStore.keyFor(userId: number): string
	return "u_" .. tostring(userId)
end

function ProfileStore.defaultData(): PlayerData
	return {
		tower = TowerCodec.empty(),
		towerName = "My Tower",
		liked = {},
		likedOrder = {},
		secretsFound = 0,
		xp = 0,
		bricks = 0,
		material = Cosmetics.DEFAULT,
		unlocked = {},
		activeSlot = 1,
		slots = {},
	}
end

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value :: any do
		out[deepCopy(k)] = deepCopy(v)
	end
	return out :: any
end

-- Turns whatever is stored into clean PlayerData. Returns nil if any part was
-- written by a newer schema (we must not load or overwrite that).
local function sanitizeData(raw: any): (PlayerData?, boolean)
	local data = ProfileStore.defaultData()
	if type(raw) ~= "table" then
		return data, false
	end
	local tower, dropped = TowerCodec.sanitize(raw.tower)
	if not tower then
		return nil, false
	end
	data.tower = tower
	if type(raw.towerName) == "string" and #raw.towerName <= Config.TOWER_NAME_MAX then
		data.towerName = raw.towerName
	end
	-- Verification only survives if it still matches the (possibly sanitised) tower.
	local hash = TowerCodec.hash(tower)
	if raw.verifiedHash == hash then
		data.verifiedHash = hash
	end
	if type(raw.publishedHash) == "string" then
		data.publishedHash = raw.publishedHash
	end
	if
		type(raw.secretsFound) == "number"
		and raw.secretsFound == raw.secretsFound
		and raw.secretsFound >= 0
	then
		data.secretsFound = math.floor(math.min(raw.secretsFound, 1e9))
	end
	if
		type(raw.activeSlot) == "number"
		and raw.activeSlot % 1 == 0
		and raw.activeSlot >= 1
		and raw.activeSlot <= Config.TOWER_SLOTS
	then
		data.activeSlot = raw.activeSlot
	end
	if type(raw.slots) == "table" then
		for i = 1, Config.TOWER_SLOTS do
			local key = tostring(i)
			local slot = raw.slots[key]
			if i ~= data.activeSlot and type(slot) == "table" then
				local slotTower, slotDropped = TowerCodec.sanitize(slot.tower)
				if not slotTower then
					return nil, false -- newer schema in a slot: refuse, like the main tower
				end
				local slotHash = TowerCodec.hash(slotTower)
				data.slots[key] = {
					tower = slotTower,
					name = if type(slot.name) == "string" and #slot.name <= Config.TOWER_NAME_MAX
						then slot.name
						else "Tower " .. key,
					verifiedHash = if slot.verifiedHash == slotHash then slotHash else nil,
				}
				dropped += slotDropped
			end
		end
	end
	if type(raw.material) == "string" and Cosmetics.byKey[raw.material] then
		data.material = raw.material
	end
	if type(raw.unlocked) == "table" then
		for key, v in raw.unlocked do
			if v == true and type(key) == "string" and Cosmetics.byKey[key] then
				data.unlocked[key] = true
			end
		end
	end
	for _, field in { "xp", "bricks" } do
		local v = raw[field]
		if type(v) == "number" and v == v and v >= 0 then
			(data :: any)[field] = math.floor(math.min(v, 1e12))
		end
	end
	if type(raw.likedOrder) == "table" and type(raw.liked) == "table" then
		for _, key in raw.likedOrder do
			local likedHash = raw.liked[key]
			if type(key) == "string" and type(likedHash) == "string" and not data.liked[key] then
				data.liked[key] = likedHash
				table.insert(data.likedOrder, key)
			end
		end
		while #data.likedOrder > Config.LIKED_MAX do
			data.liked[table.remove(data.likedOrder, 1) :: string] = nil
		end
	end
	return data, dropped > 0
end

function ProfileStore._withKey<T...>(self: ProfileStore, key: string, fn: () -> T...): T...
	while self._busy[key] do
		self._deps.wait(0.1)
	end
	self._busy[key] = true
	local result = table.pack(pcall(fn))
	self._busy[key] = nil
	if not result[1] then
		error(result[2], 0)
	end
	return table.unpack(result, 2, result.n)
end

-- Acquires the session lock and returns the player's data.
function ProfileStore.load(self: ProfileStore, userId: number): (PlayerData?, LoadError?)
	local key = ProfileStore.keyFor(userId)
	local deps = self._deps
	return self:_withKey(key, function(): (PlayerData?, LoadError?)
		for _ = 1, Config.LOAD_LOCK_RETRIES do
			local outcome: string = "datastore"
			local loaded: PlayerData? = nil
			local ok = Retry.call(self._retry, function()
				return deps.store:UpdateAsync(key, function(record: any)
					outcome = "datastore"
					if record ~= nil and type(record) ~= "table" then
						record = nil -- unreadable garbage; treat as new
					end
					record = record or { v = Config.SCHEMA_VERSION }
					if type(record.v) == "number" and record.v > Config.SCHEMA_VERSION then
						outcome = "newer"
						return nil
					end
					if
						not SessionLock.canAcquire(
							record.lock,
							deps.jobId,
							deps.now(),
							Config.LOCK_STALE_SECONDS
						)
					then
						outcome = "locked"
						return nil
					end
					local data, hadBadPieces = sanitizeData(record.data)
					if not data then
						outcome = "newer"
						return nil
					end
					if hadBadPieces and record.quarantine == nil then
						-- keep the original so nothing is lost for good
						record.quarantine = deepCopy(record.data)
					end
					record.v = Config.SCHEMA_VERSION
					record.data = data
					record.lock = { j = deps.jobId, t = deps.now() }
					outcome = "ok"
					loaded = deepCopy(data)
					return record
				end)
			end)
			if not ok then
				return nil, "datastore"
			end
			if outcome == "ok" then
				return loaded, nil
			elseif outcome == "newer" then
				return nil, "newer"
			elseif outcome == "locked" then
				deps.wait(Config.LOAD_LOCK_WAIT)
			else
				return nil, "datastore"
			end
		end
		return nil, "locked"
	end)
end

-- Writes data if this server still owns the lock. `release` drops the lock.
-- Returns false if the write failed or the lock was lost (caller must stop saving).
function ProfileStore.save(
	self: ProfileStore,
	userId: number,
	data: PlayerData,
	release: boolean
): (boolean, string?)
	local key = ProfileStore.keyFor(userId)
	local deps = self._deps
	local snapshot = deepCopy(data)
	return self:_withKey(key, function(): (boolean, string?)
		local outcome = "datastore"
		local ok = Retry.call(self._retry, function()
			return deps.store:UpdateAsync(key, function(record: any)
				if type(record) ~= "table" or not SessionLock.owns(record.lock, deps.jobId) then
					outcome = "lost"
					return nil
				end
				record.data = snapshot
				record.lock = if release then nil else { j = deps.jobId, t = deps.now() }
				outcome = "ok"
				return record
			end)
		end)
		if not ok then
			return false, "datastore"
		end
		if outcome ~= "ok" then
			return false, outcome
		end
		return true, nil
	end)
end

return ProfileStore

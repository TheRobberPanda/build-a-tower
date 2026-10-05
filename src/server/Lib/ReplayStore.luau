--!strict
-- Saved runs for ghosts and the replay viewer. One record per racer per tower
-- version, overwritten only by a faster run (caller checks "improved").
-- key = "<ownerId>_<hash16>_<racerId>" -> { v = 1, ms, path (PathCodec), splits = {ms...} }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PathCodec = require(ReplicatedStorage.Shared.PathCodec)
local Retry = require(script.Parent.Retry)

export type Replay = { ms: number, path: string, splits: { number } }

export type Deps = {
	store: any,
	wait: (number) -> (),
	budgetReady: (() -> boolean)?,
	log: ((string) -> ())?,
}

local ReplayStore = {}
ReplayStore.__index = ReplayStore

export type ReplayStore = typeof(setmetatable({} :: { _deps: Deps, _retry: Retry.Options }, ReplayStore))

function ReplayStore.new(deps: Deps): ReplayStore
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
	}, ReplayStore)
end

function ReplayStore.key(ownerId: number, hash: string, racerId: number): string
	return string.format("%d_%s_%d", ownerId, string.sub(hash, 1, 16), racerId)
end

-- Keeps the faster of the stored and the new run.
function ReplayStore.save(
	self: ReplayStore,
	ownerId: number,
	hash: string,
	racerId: number,
	ms: number,
	path: string,
	splits: { number }
): boolean
	local deps = self._deps
	local ok = Retry.call(self._retry, function()
		return deps.store:UpdateAsync(ReplayStore.key(ownerId, hash, racerId), function(old: any)
			if type(old) == "table" and type(old.ms) == "number" and old.ms <= ms then
				return nil
			end
			return { v = 1, ms = ms, path = path, splits = splits }
		end)
	end)
	return ok
end

-- Validated replay or nil.
function ReplayStore.get(self: ReplayStore, ownerId: number, hash: string, racerId: number): Replay?
	local deps = self._deps
	local ok, raw = Retry.call(self._retry, function()
		return deps.store:GetAsync(ReplayStore.key(ownerId, hash, racerId))
	end)
	if not ok or type(raw) ~= "table" or type(raw.ms) ~= "number" or type(raw.path) ~= "string" then
		return nil
	end
	if not PathCodec.decode(raw.path, Config.PATH_MAX_SAMPLES * 2) then
		return nil
	end
	local splits = {}
	if type(raw.splits) == "table" then
		for _, v in raw.splits do
			if type(v) == "number" and #splits < 64 then
				table.insert(splits, v)
			end
		end
	end
	return { ms = raw.ms, path = raw.path, splits = splits }
end

return ReplayStore

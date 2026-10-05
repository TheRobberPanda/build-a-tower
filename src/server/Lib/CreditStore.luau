--!strict
-- Rewards owed to builders, credited even while they are offline and claimed
-- into their profile on join. Bricks are capped per UTC day per builder so a
-- swarm of alt accounts can't farm currency.
-- key = ownerId -> { xp, bricks (unclaimed), day, bricksToday }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Retry = require(script.Parent.Retry)

export type Deps = {
	store: any,
	now: () -> number,
	wait: (number) -> (),
	budgetReady: (() -> boolean)?,
	log: ((string) -> ())?,
}

local CreditStore = {}
CreditStore.__index = CreditStore

export type CreditStore = typeof(setmetatable({} :: { _deps: Deps, _retry: Retry.Options }, CreditStore))

function CreditStore.new(deps: Deps): CreditStore
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
	}, CreditStore)
end

local function num(v: any): number
	return if type(v) == "number" and v == v and v >= 0 then math.floor(math.min(v, 1e12)) else 0
end

-- Adds rewards for a builder. Returns false if the write failed (caller may retry).
function CreditStore.add(self: CreditStore, ownerId: number, xp: number, bricks: number): boolean
	local day = self._deps.now() // 86400
	local ok = Retry.call(self._retry, function()
		return self._deps.store:UpdateAsync(tostring(ownerId), function(old: any)
			local rec = if type(old) == "table" then old else {}
			local today = if rec.day == day then num(rec.bricksToday) else 0
			local granted = math.clamp(bricks, 0, math.max(Config.BRICKS_DAILY_CAP - today, 0))
			return {
				xp = num(rec.xp) + math.max(xp, 0),
				bricks = num(rec.bricks) + granted,
				day = day,
				bricksToday = today + granted,
			}
		end)
	end)
	return ok
end

-- Takes everything owed (zeroing it). Returns xp, bricks; 0, 0 on failure.
function CreditStore.claim(self: CreditStore, ownerId: number): (number, number)
	local xp, bricks = 0, 0
	local ok = Retry.call(self._retry, function()
		return self._deps.store:UpdateAsync(tostring(ownerId), function(old: any)
			if type(old) ~= "table" then
				xp, bricks = 0, 0
				return nil
			end
			xp, bricks = num(old.xp), num(old.bricks)
			if xp == 0 and bricks == 0 then
				return nil
			end
			return { xp = 0, bricks = 0, day = old.day, bricksToday = num(old.bricksToday) }
		end)
	end)
	if not ok then
		return 0, 0
	end
	return xp, bricks
end

return CreditStore

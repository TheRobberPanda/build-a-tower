--!strict
-- Token bucket per key (usually a Player). `now` is injected for tests.

export type RateLimiter = {
	allow: (self: RateLimiter, key: any) -> boolean,
	forget: (self: RateLimiter, key: any) -> (),
}

local RateLimiter = {}

function RateLimiter.new(capacity: number, refillPerSecond: number, now: (() -> number)?): RateLimiter
	local clock = now or os.clock
	local buckets: { [any]: { tokens: number, at: number } } = {}

	local self = {}
	function self.allow(_, key: any): boolean
		local t = clock()
		local b = buckets[key]
		if not b then
			b = { tokens = capacity, at = t }
			buckets[key] = b
		end
		b.tokens = math.min(capacity, b.tokens + (t - b.at) * refillPerSecond)
		b.at = t
		if b.tokens >= 1 then
			b.tokens -= 1
			return true
		end
		return false
	end
	function self.forget(_, key: any)
		buckets[key] = nil
	end
	return (self :: any) :: RateLimiter
end

return RateLimiter

--!strict
-- Retries a yielding call with exponential backoff. `wait` and `budget` are injected
-- so the logic can be tested without DataStoreService.

export type Options = {
	attempts: number,
	baseDelay: number,
	maxDelay: number,
	wait: (number) -> (),
	-- Optional: returns true when a request may be sent now; waited on before each try.
	budgetReady: (() -> boolean)?,
	log: ((string) -> ())?,
}

local Retry = {}

function Retry.delayFor(attempt: number, opts: Options): number
	return math.min(opts.baseDelay * 2 ^ (attempt - 1), opts.maxDelay)
end

function Retry.call<T...>(opts: Options, fn: () -> T...): (boolean, ...any)
	local lastErr: any = nil
	for attempt = 1, opts.attempts do
		if opts.budgetReady then
			local waited = 0
			while not opts.budgetReady() and waited < 30 do
				opts.wait(1)
				waited += 1
			end
		end
		local result = table.pack(pcall(fn))
		if result[1] then
			return table.unpack(result, 1, result.n)
		end
		lastErr = result[2]
		if opts.log then
			opts.log(string.format("attempt %d/%d failed: %s", attempt, opts.attempts, tostring(lastErr)))
		end
		if attempt < opts.attempts then
			opts.wait(Retry.delayFor(attempt, opts))
		end
	end
	return false, lastErr
end

return Retry

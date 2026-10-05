--!strict
-- Session-lock rules for a player record, applied inside UpdateAsync transforms.

export type Lock = { j: string, t: number }

local SessionLock = {}

-- True if `jobId` may take (or already holds) the lock at time `now`.
function SessionLock.canAcquire(lock: Lock?, jobId: string, now: number, staleAfter: number): boolean
	if lock == nil or type(lock) ~= "table" then
		return true
	end
	if lock.j == jobId then
		return true
	end
	return type(lock.t) ~= "number" or now - lock.t > staleAfter
end

-- True only if this server still owns the lock; saves must not write otherwise.
function SessionLock.owns(lock: Lock?, jobId: string): boolean
	return lock ~= nil and type(lock) == "table" and lock.j == jobId
end

return SessionLock

--!strict
-- Pure movement plausibility check between two server samples. Judges only
-- physics (speed, rise, jumps in position), never which route was taken.
-- Registered jump pads and teleporters widen the limits so secrets stay legal.

export type Allowance = {
	launchSpeed: number, -- extra upward speed granted by a jump pad
	launchUntil: number,
	teleportTo: Vector3?,
	teleportUntil: number,
}

export type Limits = {
	walkSpeed: number,
	maxRiseSpeed: number,
	speedFactor: number,
	speedSlack: number,
	teleportRadius: number,
}

local MovementCheck = {}

function MovementCheck.newAllowance(): Allowance
	return { launchSpeed = 0, launchUntil = 0, teleportUntil = 0 }
end

-- Returns nil if the move is plausible, otherwise a short reason.
-- May consume a pending teleport allowance.
function MovementCheck.check(
	prev: Vector3,
	cur: Vector3,
	dt: number,
	now: number,
	allow: Allowance,
	limits: Limits
): string?
	if dt <= 0 then
		return nil
	end
	local target = allow.teleportTo
	if target and now <= allow.teleportUntil and (cur - target).Magnitude <= limits.teleportRadius then
		allow.teleportTo = nil
		return nil
	end

	local delta = cur - prev
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude / dt
	local launching = now <= allow.launchUntil
	local maxHorizontal = limits.walkSpeed * limits.speedFactor + limits.speedSlack
	if launching then
		maxHorizontal += 20 -- pads add some air control drift
	end
	if horizontal > maxHorizontal then
		return string.format("speed %.0f > %.0f", horizontal, maxHorizontal)
	end

	local maxRise = limits.maxRiseSpeed + (if launching then allow.launchSpeed else 0)
	local rise = delta.Y / dt
	if rise > maxRise then
		return string.format("rise %.0f > %.0f", rise, maxRise)
	end
	return nil
end

export type Hover = { since: number? }

-- Flags staying airborne without falling (fly/hover exploits). `airborne` is the
-- humanoid's FloorMaterial == Air; `dy` the vertical move since the last sample.
-- A real jump stops rising within ~0.5 s; jump pads get their launch window.
function MovementCheck.hover(
	state: Hover,
	airborne: boolean,
	dy: number,
	now: number,
	launching: boolean,
	maxSeconds: number
): string?
	if not airborne or launching or dy < -0.5 then
		state.since = nil
		return nil
	end
	local since = state.since
	if not since then
		state.since = now
		return nil
	end
	if now - since > maxSeconds then
		state.since = now -- one flag per window
		return string.format("airborne without falling %.1fs", now - since)
	end
	return nil
end

return MovementCheck

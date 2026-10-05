--!strict
-- Client-side view state shared by controllers. Mirrors server data; never authoritative.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

export type Mode = "build" | "run"

local changed = Instance.new("BindableEvent")

local State = {
	mode = "build" :: Mode,
	selected = 1, -- piece type id
	rotation = 0,
	deleting = false,
	tower = nil :: Types.Tower?,
	verified = false,
	runOwner = 0,
	runName = "",
	runStartedAt = 0,
	Changed = changed.Event,
}

-- Apply a partial update and notify listeners.
function State.set(patch: { [string]: any })
	for k, v in patch do
		(State :: any)[k] = v
	end
	changed:Fire()
end

return State

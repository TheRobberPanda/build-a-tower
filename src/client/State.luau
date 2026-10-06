--!strict
-- Client-side view state shared by controllers. Mirrors server data; never authoritative.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PieceDefs = require(ReplicatedStorage.Shared.PieceDefs)
local Types = require(ReplicatedStorage.Shared.Types)

export type Mode = "build" | "run"

local changed = Instance.new("BindableEvent")

local State = {
	mode = "build" :: Mode,
	selected = 1, -- piece type id
	rotation = 0,
	props = {} :: { [string]: number }, -- chosen setting per prop key (power, ch)
	deleting = false,
	fill = false, -- touch: two taps fill the box between them (desktop: drag)
	tower = nil :: Types.Tower?,
	verified = false,
	runOwner = 0,
	runName = "",
	runStartedAt = 0,
	-- progression (from the server's Progress event)
	level = 1,
	xp = 0,
	bricks = 0,
	budget = 150,
	levelXp = 0,
	nextXp = 100,
	material = "plastic",
	unlocked = {} :: { [string]: boolean },
	activeSlot = 1,
	slots = 3,
	trail = nil :: string?,
	run = nil :: string?, -- running animation key
	theme = "grass",
	lobbyMode = "lobby", -- "lobby" | "queue" (play rounds) | "free" (free build on your island)
	inRound = false,
	roundPhase = "waiting", -- taking part in the current round (RoundController)
	buildOwner = 0, -- userId whose plot you are building on; 0 = your own
	plotSize = 16, -- home island cells per side (grows with expansions)
	hotbarTab = "blocks", -- "blocks" | "decor"
	hotbarKeys = {} :: { number }, -- piece id per number key, in visible hotbar order
	Changed = changed.Event,
}

-- The setting key and range of a piece type (JumpPad power, Teleporter channel), if any.
function State.settingOf(typeId: number): (string?, { number }?)
	local def = PieceDefs.byId[typeId]
	if def then
		for k, range in def.props do
			return k, range
		end
	end
	return nil, nil
end

-- Unlocked by level, or (asset decorations) owned. The server checks again.
function State.canUse(typeId: number): boolean
	local def = PieceDefs.byId[typeId]
	if not def then
		return false
	end
	if def.asset then
		return State.unlocked["decor_" .. typeId] == true
	end
	return State.level >= (def.level or 1)
end

-- Props to send for the selected piece.
function State.selectedProps(): { [string]: number }?
	local k, range = State.settingOf(State.selected)
	if not k or not range then
		return nil
	end
	return { [k] = State.props[k] or range[1] }
end

-- Apply a partial update and notify listeners.
function State.set(patch: { [string]: any })
	for k, v in patch do
		(State :: any)[k] = v
	end
	changed:Fire()
end

return State

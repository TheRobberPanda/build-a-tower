--!strict
-- Piece types. `t` ids are persisted: never renumber or reuse an id.
-- size is in grid cells {x, y, z} before rotation. props lists the integer
-- properties a piece may carry and their inclusive ranges.

local Types = require(script.Parent.Types)

type PieceDef = Types.PieceDef

local list: { PieceDef } = {
	{ id = 1, name = "Block", hint = "Solid block", size = { 1, 1, 1 }, props = {} },
	{ id = 2, name = "Platform", hint = "Wide platform to land on", size = { 2, 1, 2 }, props = {} },
	{ id = 3, name = "Ramp", hint = "Walk up it; R rotates", size = { 1, 1, 2 }, props = {} },
	{
		id = 4,
		name = "JumpPad",
		hint = "Launches you up. Power 1-3",
		size = { 1, 1, 1 },
		props = { power = { 1, 3 } },
	},
	{
		id = 5,
		name = "Teleporter",
		hint = "Links to the next teleporter of the same colour",
		size = { 1, 1, 1 },
		props = { ch = { 1, 4 } },
	},
	{
		id = 6,
		name = "FakeWall",
		hint = "Looks solid, but you can walk through it",
		size = { 1, 2, 1 },
		props = {},
	},
	{ id = 7, name = "InvisiblePlatform", hint = "Solid but invisible", size = { 1, 1, 1 }, props = {} },
	{
		id = 8,
		name = "Finish",
		hint = "The goal. One per tower",
		size = { 1, 1, 1 },
		props = {},
		maxCount = 1,
	},
	-- M2 secret pieces
	{ id = 9, name = "Crumble", hint = "Falls shortly after you land on it", size = { 2, 1, 2 }, props = {} }, -- falls shortly after you land
	{ id = 10, name = "Conveyor", hint = "Carries you the way it faces", size = { 2, 1, 2 }, props = {} }, -- carries you toward its rotation
	{
		id = 11,
		name = "OneWay",
		hint = "A wall you can only pass from behind",
		size = { 1, 2, 1 },
		props = {},
	}, -- pass through from the front only
	{
		id = 12,
		name = "Button",
		hint = "Opens doors of the same colour for 6 s",
		size = { 1, 1, 1 },
		props = { ch = { 1, 4 } },
	}, -- opens doors on its channel
	{
		id = 13,
		name = "Door",
		hint = "Opened by a button of the same colour",
		size = { 1, 2, 1 },
		props = { ch = { 1, 4 } },
	},
	-- M3
	{
		id = 14,
		name = "Checkpoint",
		hint = "Respawn point and split time",
		size = { 1, 1, 1 },
		props = {},
		maxCount = 16,
	}, -- respawn point + split time
	-- M4 decorations (no collision, outside the budget)
	{ id = 15, name = "Plant", hint = "Decoration, free", size = { 1, 1, 1 }, props = {}, decor = true },
	{
		id = 16,
		name = "Lamp",
		hint = "Decoration with light, free",
		size = { 1, 2, 1 },
		props = {},
		decor = true,
	},
	{
		id = 17,
		name = "Flag",
		hint = "Decoration, free",
		size = { 1, 2, 1 },
		props = { ch = { 1, 4 } },
		decor = true,
	}, -- ch = colour
	-- M7 limited-time (window in Config.EVENT_PIECES)
	{
		id = 18,
		name = "Pumpkin",
		hint = "Halloween decoration, free",
		size = { 1, 1, 1 },
		props = {},
		decor = true,
	},
}

local byId: { [number]: PieceDef } = {}
for _, def in list do
	table.freeze(def.size)
	table.freeze(def.props)
	byId[def.id] = table.freeze(def)
end

return table.freeze({
	list = table.freeze(list),
	byId = table.freeze(byId),
	FINISH_ID = 8,
})

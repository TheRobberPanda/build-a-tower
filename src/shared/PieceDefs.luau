--!strict
-- Piece types. `t` ids are persisted: never renumber or reuse an id.
-- size is in grid cells {x, y, z} before rotation. props lists the integer
-- properties a piece may carry and their inclusive ranges.

local Types = require(script.Parent.Types)

type PieceDef = Types.PieceDef

local list: { PieceDef } = {
	{ id = 1, name = "Block", size = { 1, 1, 1 }, props = {} },
	{ id = 2, name = "Platform", size = { 2, 1, 2 }, props = {} },
	{ id = 3, name = "Ramp", size = { 1, 1, 2 }, props = {} },
	{ id = 4, name = "JumpPad", size = { 1, 1, 1 }, props = { power = { 1, 3 } } },
	{ id = 5, name = "Teleporter", size = { 1, 1, 1 }, props = { ch = { 1, 4 } } },
	{ id = 6, name = "FakeWall", size = { 1, 2, 1 }, props = {} },
	{ id = 7, name = "InvisiblePlatform", size = { 1, 1, 1 }, props = {} },
	{ id = 8, name = "Finish", size = { 1, 1, 1 }, props = {}, maxCount = 1 },
	-- M2 secret pieces
	{ id = 9, name = "Crumble", size = { 2, 1, 2 }, props = {} }, -- falls shortly after you land
	{ id = 10, name = "Conveyor", size = { 2, 1, 2 }, props = {} }, -- carries you toward its rotation
	{ id = 11, name = "OneWay", size = { 1, 2, 1 }, props = {} }, -- pass through from the front only
	{ id = 12, name = "Button", size = { 1, 1, 1 }, props = { ch = { 1, 4 } } }, -- opens doors on its channel
	{ id = 13, name = "Door", size = { 1, 2, 1 }, props = { ch = { 1, 4 } } },
	-- M3
	{ id = 14, name = "Checkpoint", size = { 1, 1, 1 }, props = {}, maxCount = 16 }, -- respawn point + split time
	-- M4 decorations (no collision, outside the budget)
	{ id = 15, name = "Plant", size = { 1, 1, 1 }, props = {}, decor = true },
	{ id = 16, name = "Lamp", size = { 1, 2, 1 }, props = {}, decor = true },
	{ id = 17, name = "Flag", size = { 1, 2, 1 }, props = { ch = { 1, 4 } }, decor = true }, -- ch = colour
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

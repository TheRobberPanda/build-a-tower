--!strict
-- The 8 V1 piece types. `t` ids are persisted: never renumber or reuse an id.
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

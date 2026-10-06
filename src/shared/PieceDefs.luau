--!strict
-- Piece types. `t` ids are persisted: never renumber or reuse an id.
-- size is in grid cells {x, y, z} before rotation. props lists the integer
-- properties a piece may carry and their inclusive ranges.

local Types = require(script.Parent.Types)

type PieceDef = Types.PieceDef

local list: { PieceDef } = {
	{ id = 1, name = "Block", hint = "Solid block", size = { 1, 1, 1 }, props = {} },
	{ id = 2, name = "Platform", hint = "Wide platform to land on", size = { 2, 1, 2 }, props = {} },
	{ id = 3, name = "Ramp", hint = "Steep ramp, 2 wide, 2 high; R rotates", size = { 2, 2, 2 }, props = {} },
	{
		id = 4,
		level = 2,
		name = "JumpPad",
		hint = "Launches you up. Power 1-3",
		size = { 1, 1, 1 },
		props = { power = { 1, 3 } },
	},
	{
		id = 5,
		level = 3,
		name = "Teleporter",
		hint = "Links to the next teleporter of the same colour",
		size = { 1, 1, 1 },
		props = { ch = { 1, 4 } },
	},
	{
		id = 6,
		level = 4,
		name = "FakeWall",
		hint = "Looks solid, but you can walk through it",
		size = { 2, 2, 1 },
		props = {},
	},
	{
		id = 7,
		level = 5,
		name = "InvisiblePlatform",
		hint = "Solid but invisible",
		size = { 1, 1, 1 },
		props = {},
	},
	{
		id = 8,
		name = "Finish",
		hint = "The goal. One per tower",
		size = { 1, 1, 1 },
		props = {},
		maxCount = 1,
	},
	-- M2 secret pieces
	{
		id = 9,
		level = 2,
		name = "Crumble",
		hint = "Falls shortly after you land on it",
		size = { 2, 1, 2 },
		props = {},
	}, -- falls shortly after you land
	{
		id = 10,
		level = 2,
		name = "Conveyor",
		hint = "Carries you the way it faces",
		size = { 2, 1, 2 },
		props = {},
	}, -- carries you toward its rotation
	{
		id = 11,
		level = 6,
		name = "OneWay",
		hint = "A wall you can only pass from behind",
		size = { 2, 2, 1 },
		props = {},
	}, -- pass through from the front only
	{
		id = 12,
		level = 4,
		name = "Button",
		hint = "Opens doors of the same colour for 6 s",
		size = { 1, 1, 1 },
		props = { ch = { 1, 4 } },
	}, -- opens doors on its channel
	{
		id = 13,
		level = 4,
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
		level = 2,
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
	-- Premades (several parts; rotation turns them like a ramp)
	{ id = 19, name = "Stairs", hint = "Walkable stairs, 2 high", size = { 1, 2, 2 }, props = {} },
	{ id = 20, name = "Beam", hint = "Long plank walkway", size = { 1, 1, 4 }, props = {} },
	{
		id = 21,
		level = 2,
		name = "LongRamp",
		hint = "Long sloped plank, 2 high",
		size = { 1, 2, 4 },
		props = {},
	},
	-- Big pieces: one click covers a lot (still one piece of budget)
	{ id = 22, name = "BigFloor", hint = "3x3 floor, builds fast", size = { 3, 1, 3 }, props = {} },
	{ id = 23, name = "Wall", hint = "Wall 2 wide, 2 high; R rotates", size = { 2, 2, 1 }, props = {} },
	-- Day/night (DayNightService toggles them)
	{
		id = 24,
		level = 6,
		name = "SunBlock",
		hint = "Solid by day, a ghost at night",
		size = { 1, 1, 1 },
		props = {},
	},
	{
		id = 25,
		level = 6,
		name = "MoonBlock",
		hint = "Solid at night, a ghost by day",
		size = { 1, 1, 1 },
		props = {},
	},
	-- Traps: touching one knocks you out (back to your last checkpoint)
	{
		id = 26,
		level = 3,
		name = "Spikes",
		hint = "Trap: touch it and you're out",
		size = { 1, 1, 1 },
		props = {},
	},
	{
		id = 27,
		level = 5,
		name = "Lava",
		hint = "Trap floor: don't step on it",
		size = { 2, 1, 2 },
		props = {},
	},
}

-- Store decorations (ReplicatedStorage.DecorAssets, Creator Store models; see
-- CREDITS.md): bought with Coins or won, no collision, outside the budget.
-- { id, model, label, size, price }
local STORE: { { any } } = {
	{ 30, "OakTree", "Oak Tree", { 2, 4, 2 }, 60 },
	{ 31, "RoundTree", "Round Tree", { 2, 4, 2 }, 60 },
	{ 32, "PineTree", "Pine Tree", { 2, 5, 2 }, 80 },
	{ 33, "PalmTree", "Palm Tree", { 2, 4, 2 }, 100 },
	{ 34, "BlossomTree", "Blossom Tree", { 2, 3, 2 }, 120 },
	{ 35, "DeadTree", "Dead Tree", { 2, 4, 2 }, 60 },
	{ 36, "BigBush", "Big Bush", { 1, 1, 1 }, 25 },
	{ 37, "SmallBush", "Small Bush", { 1, 1, 1 }, 20 },
	{ 38, "Flower", "Flower", { 1, 1, 1 }, 15 },
	{ 39, "Sunflower", "Sunflower", { 1, 2, 1 }, 30 },
	{ 40, "Mushrooms", "Mushrooms", { 1, 1, 1 }, 25 },
	{ 41, "BigMushroom", "Big Mushroom", { 1, 1, 1 }, 40 },
	{ 42, "Boulder", "Boulder", { 1, 1, 1 }, 30 },
	{ 43, "RockPile", "Rock Pile", { 2, 1, 1 }, 40 },
	{ 44, "Pebbles", "Pebbles", { 1, 1, 1 }, 15 },
	{ 45, "Cactus", "Cactus", { 1, 2, 1 }, 40 },
	{ 46, "Log", "Log", { 2, 1, 1 }, 30 },
	{ 47, "Stump", "Stump", { 1, 1, 1 }, 20 },
	{ 48, "HayBales", "Hay Bales", { 2, 1, 2 }, 60 },
	{ 49, "Bench", "Bench", { 2, 1, 1 }, 50 },
	{ 50, "PicnicTable", "Picnic Table", { 2, 1, 2 }, 80 },
	{ 51, "Crate", "Crate", { 1, 1, 1 }, 20 },
	{ 52, "CrateStack", "Crate Stack", { 1, 1, 1 }, 50 },
	{ 53, "Barrel", "Barrel", { 1, 1, 1 }, 30 },
	{ 54, "Campfire", "Campfire", { 1, 1, 1 }, 80 },
	{ 55, "Tent", "Tent", { 2, 2, 2 }, 120 },
	{ 56, "Fountain", "Fountain", { 2, 2, 2 }, 200 },
	{ 57, "Signpost", "Signpost", { 1, 1, 1 }, 25 },
	{ 58, "Well", "Well", { 1, 1, 1 }, 100 },
	{ 59, "StreetLantern", "Street Lantern", { 1, 3, 1 }, 70 },
	{ 60, "Mailbox", "Mailbox", { 1, 1, 1 }, 40 },
	{ 61, "Windmill", "Windmill", { 2, 6, 2 }, 300 },
	{ 62, "TreasureChest", "Treasure Chest", { 1, 1, 1 }, 150 },
	{ 63, "Crystal", "Crystal", { 1, 1, 1 }, 90 },
	{ 64, "CandyCane", "Candy Cane", { 1, 2, 1 }, 60 },
	{ 65, "Donut", "Donut", { 1, 1, 1 }, 50 },
	{ 66, "Asteroid", "Space Rock", { 1, 1, 1 }, 70 },
	{ 67, "Pumpkins", "Pumpkins", { 1, 1, 1 }, 40 },
}
for _, e in STORE do
	table.insert(list, {
		id = e[1],
		name = e[2],
		hint = e[3],
		size = e[4],
		props = {},
		decor = true,
		asset = e[2],
		price = e[5],
	})
end

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
	STORE_FIRST = 30, -- store decorations are ids 30.. (rewards pick from them)
})

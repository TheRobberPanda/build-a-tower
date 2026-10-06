--!strict
-- Cosmetic catalogs: tower materials, run trails and VIP plot themes. Never part
-- of the tower hash. Keys are persisted: never rename or reuse.
-- Materials apply to structural pieces; fake walls and one-way walls follow so
-- they still blend in.

export type MaterialDef = {
	key: string,
	name: string,
	material: Enum.Material,
	level: number,
	bricks: number,
	pass: string?, -- game pass required instead of level/Bricks
}
export type TrailDef = { key: string, name: string, colors: { Color3 }, bricks: number }
export type ThemeDef = { key: string, name: string, color: Color3, material: Enum.Material }
export type RunDef = { key: string, name: string, anim: string, bricks: number }

local materials: { MaterialDef } = {
	{ key = "plastic", name = "Plastic", material = Enum.Material.SmoothPlastic, level = 1, bricks = 0 },
	{ key = "wood", name = "Wood", material = Enum.Material.WoodPlanks, level = 3, bricks = 0 },
	{ key = "brick", name = "Brick", material = Enum.Material.Brick, level = 5, bricks = 0 },
	{ key = "marble", name = "Marble", material = Enum.Material.Marble, level = 1, bricks = 300 },
	{ key = "ice", name = "Ice", material = Enum.Material.Ice, level = 1, bricks = 600 },
	{
		key = "metal",
		name = "Diamond Plate",
		material = Enum.Material.DiamondPlate,
		level = 8,
		bricks = 1000,
	},
	{
		key = "glass",
		name = "Glass",
		material = Enum.Material.Glass,
		level = 1,
		bricks = 0,
		pass = "BuilderPass",
	},
	{
		key = "foil",
		name = "Foil",
		material = Enum.Material.Foil,
		level = 1,
		bricks = 0,
		pass = "BuilderPass",
	},
}

-- Run trails. Keys share the unlocked map with materials, so they are prefixed.
local trails: { TrailDef } = {
	{
		key = "trail_spark",
		name = "Spark",
		colors = { Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 120, 40) },
		bricks = 200,
	},
	{
		key = "trail_frost",
		name = "Frost",
		colors = { Color3.fromRGB(180, 240, 255), Color3.fromRGB(80, 160, 255) },
		bricks = 400,
	},
	{
		key = "trail_rainbow",
		name = "Rainbow",
		colors = {
			Color3.fromRGB(255, 80, 80),
			Color3.fromRGB(255, 220, 80),
			Color3.fromRGB(80, 220, 120),
			Color3.fromRGB(80, 160, 255),
			Color3.fromRGB(200, 100, 255),
		},
		bricks = 1200,
	},
}

-- Running animations (Roblox's own animation packs, free to use in any game).
-- Keys share the unlocked map too, so they are prefixed.
local runs: { RunDef } = {
	{ key = "run_toy", name = "Toy", anim = "rbxassetid://782842708", bricks = 150 },
	{ key = "run_cartoony", name = "Cartoony", anim = "rbxassetid://742638842", bricks = 200 },
	{ key = "run_zombie", name = "Zombie", anim = "rbxassetid://616163682", bricks = 250 },
	{ key = "run_robot", name = "Robot", anim = "rbxassetid://616091570", bricks = 300 },
	{ key = "run_stylish", name = "Stylish", anim = "rbxassetid://616140816", bricks = 400 },
	{ key = "run_superhero", name = "Superhero", anim = "rbxassetid://616117076", bricks = 500 },
	{ key = "run_ninja", name = "Ninja", anim = "rbxassetid://656118852", bricks = 600 },
	{ key = "run_levitation", name = "Levitation", anim = "rbxassetid://616010382", bricks = 800 },
	{ key = "run_werewolf", name = "Werewolf", anim = "rbxassetid://1083216690", bricks = 1000 },
}

-- VIP island themes: the whole island's ground, colours and scenery change
-- (PlotBuilder THEMES). color/material are for the shop swatch.
local themes: { ThemeDef } = {
	{
		key = "grass", -- persisted key; shown as Skylands
		name = "Skylands",
		color = Color3.fromRGB(96, 196, 80), -- matches the island grass (PlotBuilder)
		material = Enum.Material.SmoothPlastic,
	},
	{
		key = "lava",
		name = "Lava",
		color = Color3.fromRGB(200, 70, 30),
		material = Enum.Material.CrackedLava,
	},
	{ key = "space", name = "Space", color = Color3.fromRGB(30, 30, 60), material = Enum.Material.Glass },
	{
		key = "candy",
		name = "Candy",
		color = Color3.fromRGB(255, 170, 210),
		material = Enum.Material.SmoothPlastic,
	},
}

local function index<T>(list: { T }): { [string]: T }
	local out = {}
	for _, def in list do
		out[(def :: any).key] = table.freeze(def)
	end
	return table.freeze(out)
end

-- Pieces that take the tower material.
local STRUCTURAL = table.freeze({
	Block = true,
	Platform = true,
	BigFloor = true,
	Wall = true,
	Ramp = true,
	FakeWall = true,
	OneWay = true,
})

return table.freeze({
	materials = table.freeze(materials),
	byKey = index(materials),
	DEFAULT = "plastic",
	trails = table.freeze(trails),
	trailByKey = index(trails),
	runs = table.freeze(runs),
	runByKey = index(runs),
	DEFAULT_RUN = "run_default", -- equip key for the avatar's own run
	themes = table.freeze(themes),
	themeByKey = index(themes),
	DEFAULT_THEME = "grass",
	structural = STRUCTURAL,
})

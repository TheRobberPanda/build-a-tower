--!strict
-- Tower materials. Cosmetic only (never part of the tower hash). Applied to the
-- structural pieces; fake walls and one-way walls follow so they still blend in.
-- Keys are persisted: never rename or reuse.

export type MaterialDef =
	{ key: string, name: string, material: Enum.Material, level: number, bricks: number }

local list: { MaterialDef } = {
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
}

local byKey: { [string]: MaterialDef } = {}
for _, def in list do
	byKey[def.key] = table.freeze(def)
end

-- Pieces that take the tower material.
local STRUCTURAL = table.freeze({
	Block = true,
	Platform = true,
	Ramp = true,
	FakeWall = true,
	OneWay = true,
})

return table.freeze({
	materials = table.freeze(list),
	byKey = table.freeze(byKey),
	DEFAULT = "plastic",
	structural = STRUCTURAL,
})

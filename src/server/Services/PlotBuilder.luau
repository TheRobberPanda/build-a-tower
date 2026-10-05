--!strict
-- Builds the static scenery of a plot: a floating grass island with a rocky
-- underside, the fixed tower core in the middle (Config.CORE), the spawn apron
-- and a few trees and rocks around the edge. Nothing here is part of a tower.

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local PlotBuilder = {}

local BAND_COLORS = {
	Color3.fromRGB(40, 120, 255),
	Color3.fromRGB(255, 140, 30),
	Color3.fromRGB(255, 205, 40),
	Color3.fromRGB(60, 200, 90),
	Color3.fromRGB(235, 60, 75),
	Color3.fromRGB(150, 80, 240),
}

local GRID_TEXTURE = "rbxassetid://139861751774533" -- assets/ui/grid_cell.png

local G = Config.GRID_STUDS
local GRASS = Color3.fromRGB(110, 178, 78)
local ROCK = Color3.fromRGB(110, 104, 98)
local STONE_DARK = Color3.fromRGB(112, 108, 104)

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function decoPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local p = part(parent, name, size, cf, color, material)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function tree(parent: Instance, at: Vector3, scale: number)
	local trunkH = 7 * scale
	part(
		parent,
		"Trunk",
		Vector3.new(1.6, trunkH, 1.6) * Vector3.new(scale, 1, scale),
		CFrame.new(at + Vector3.new(0, trunkH / 2, 0)),
		Color3.fromRGB(110, 78, 52),
		Enum.Material.Wood
	)
	for i, off in { Vector3.new(0, 0, 0), Vector3.new(1.6, -1, 0.8), Vector3.new(-1.4, -0.8, -1) } do
		local leaves = decoPart(
			parent,
			"Leaves",
			Vector3.one * (6 - i) * scale,
			CFrame.new(at + Vector3.new(0, trunkH + 1, 0) + off * scale),
			Color3.fromRGB(70, 150 + i * 12, 70),
			Enum.Material.Grass
		)
		leaves.Shape = Enum.PartType.Ball
	end
end

local function noQuery(folder: Instance)
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false -- building raycasts only see the grid and the core
		end
	end
end

local function rock(parent: Instance, at: Vector3, size: number)
	local r = decoPart(
		parent,
		"Rock",
		Vector3.new(size, size * 0.7, size * 0.9),
		CFrame.new(at) * CFrame.Angles(0, math.random() * 6.28, math.rad(10)),
		STONE_DARK,
		Enum.Material.Slate
	)
	r.CanCollide = true
	r.CanQuery = false
end

-- The fixed core: a sandstone tower. Its outer shape is exactly the core
-- footprint (corner pillars and trim bands reach the edge, the walls are
-- recessed), so pieces built against it never overlap decoration.
local function core(model: Model, origin: Vector3)
	local c = Config.CORE
	local w = (c.x1 - c.x0) * G
	local d = (c.z1 - c.z0) * G
	local h = c.height * G
	local cx, cz = (c.x0 + c.x1) / 2 * G, (c.z0 + c.z1) / 2 * G
	local folder = Instance.new("Folder")
	folder.Name = "Core"
	local inset = 0.5
	local wall = Color3.fromRGB(70, 78, 96) -- dark panels
	local trim = Color3.fromRGB(196, 200, 210) -- steel
	local body = part(
		folder,
		"CoreBody",
		Vector3.new(w - inset * 2, h - 0.6, d - inset * 2),
		CFrame.new(origin + Vector3.new(cx, (h - 0.6) / 2, cz)),
		wall,
		Enum.Material.SmoothPlastic
	)
	body:SetAttribute("Core", true)
	-- Corner pillars, full height, flush with the footprint (solid, so raycasts
	-- and building treat the core as its full 2x2 size).
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(
				folder,
				"CorePillar",
				Vector3.new(1.4, h - 0.6, 1.4),
				CFrame.new(
					origin + Vector3.new(cx + sx * (w / 2 - 0.7), (h - 0.6) / 2, cz + sz * (d / 2 - 0.7))
				),
				trim,
				Enum.Material.Metal
			)
		end
	end
	-- Trim bands every 4 cells fill the recess to the edge.
	for y = 0, c.height, 4 do
		local bandY = math.clamp(y * G, 0.5, h - 1.2)
		part(
			folder,
			"CoreBand",
			Vector3.new(w - 0.16, 1, d - 0.16), -- a hair inside the pillars: no shared faces
			CFrame.new(origin + Vector3.new(cx, bandY, cz)),
			BAND_COLORS[(y // 4) % #BAND_COLORS + 1], -- same colour bands as the pieces
			Enum.Material.SmoothPlastic
		)
	end
	-- Dark window slits set into the recessed walls, two per side every other band.
	for y = 2, c.height - 2, 8 do
		for _, side in { -1, 1 } do
			decoPart(
				folder,
				"Window",
				Vector3.new(1.4, 3.2, 0.2),
				CFrame.new(origin + Vector3.new(cx, y * G, cz + side * (d / 2 - inset + 0.05))),
				Color3.fromRGB(46, 38, 34),
				Enum.Material.SmoothPlastic
			)
			decoPart(
				folder,
				"Window",
				Vector3.new(0.2, 3.2, 1.4),
				CFrame.new(origin + Vector3.new(cx + side * (w / 2 - inset + 0.05), y * G, cz)),
				Color3.fromRGB(46, 38, 34),
				Enum.Material.SmoothPlastic
			)
		end
	end
	-- Coloured roof cap (inside the footprint, top flush with the roof).
	part(
		folder,
		"CoreRoof",
		Vector3.new(w, 0.6, d),
		CFrame.new(origin + Vector3.new(cx, h - 0.3, cz)),
		Color3.fromRGB(255, 205, 40),
		Enum.Material.Neon
	)
	folder.Parent = model
end

-- The buildable base (exactly the grid, named "Base") and the spawn apron.
function PlotBuilder.base(model: Model, origin: Vector3, apronDepth: number)
	local g = G
	local APRON_DEPTH = apronDepth
	-- Base covers exactly the buildable grid; the apron in front is where runs start.
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Anchored = true
	base.Size = Vector3.new(Config.PLOT_CELLS_X * g, 1, Config.PLOT_CELLS_Z * g)
	base.Position = origin + Vector3.new(Config.PLOT_CELLS_X * g / 2, -0.5, Config.PLOT_CELLS_Z * g / 2)
	base.Color = Color3.fromRGB(110, 178, 78)
	base.Material = Enum.Material.Grass
	base.TopSurface = Enum.SurfaceType.Smooth
	local grid = Instance.new("Texture")
	grid.Texture = GRID_TEXTURE
	grid.Face = Enum.NormalId.Top
	grid.StudsPerTileU = g
	grid.StudsPerTileV = g
	grid.Transparency = 0.55
	grid.Parent = base
	base.Parent = model
	local apron = Instance.new("Part")
	apron.Name = "Apron"
	apron.Anchored = true
	apron.Size = Vector3.new(Config.PLOT_CELLS_X * g, 1, APRON_DEPTH)
	apron.Position = origin + Vector3.new(Config.PLOT_CELLS_X * g / 2, -0.5, -APRON_DEPTH / 2)
	apron.Color = Color3.fromRGB(196, 176, 140)
	apron.Material = Enum.Material.Cobblestone
	apron.TopSurface = Enum.SurfaceType.Smooth
	apron.Parent = model
end

-- Builds island, core and scenery into `model`. The buildable base (named
-- "Base") stays exactly the grid size so building/raycasts are unchanged.
function PlotBuilder.build(model: Model, origin: Vector3, apronDepth: number)
	local sizeX, sizeZ = Config.PLOT_CELLS_X * G, Config.PLOT_CELLS_Z * G
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"

	-- Island: grass strips around (not under) the base and apron, so no faces
	-- overlap and nothing z-fights; layered rock cliffs below.
	local RIM = 12
	local front = -apronDepth - RIM
	local back = sizeZ + RIM
	local function strip(name: string, x0: number, x1: number, z0: number, z1: number)
		local p = part(
			scenery,
			name,
			Vector3.new(x1 - x0, 1, z1 - z0),
			CFrame.new(origin + Vector3.new((x0 + x1) / 2, -0.5, (z0 + z1) / 2)),
			GRASS,
			Enum.Material.Grass
		)
		p.CanQuery = false
	end
	strip("RimLeft", -RIM, 0, front, back)
	strip("RimRight", sizeX, sizeX + RIM, front, back)
	strip("RimFront", 0, sizeX, front, -apronDepth)
	strip("RimBack", 0, sizeX, sizeZ, back)
	local islandX, islandZ = sizeX + RIM * 2, back - front
	local islandCenter = origin + Vector3.new(sizeX / 2, 0, (front + back) / 2)
	local top = -1.05
	for i, depth in { 6, 10, 16, 22 } do
		local shrink = (i - 1) * 10
		decoPart(
			scenery,
			"Cliff",
			Vector3.new(islandX - shrink, depth, islandZ - shrink),
			CFrame.new(islandCenter + Vector3.new(0, top - depth / 2, 0)),
			ROCK:Lerp(Color3.new(0, 0, 0), (i - 1) * 0.12),
			if i == 1 then Enum.Material.Ground else Enum.Material.Rock
		)
		top -= depth
	end

	-- Trees and rocks on the rim, outside the buildable grid.
	local rng = Random.new(model.Name:len() * 7919)
	for _ = 1, 7 do
		local side = rng:NextInteger(1, 3)
		local at = if side == 1
			then Vector3.new(rng:NextNumber(-8, -3), 0, rng:NextNumber(0, sizeZ))
			elseif side == 2 then Vector3.new(sizeX + rng:NextNumber(3, 8), 0, rng:NextNumber(0, sizeZ))
			else Vector3.new(rng:NextNumber(0, sizeX), 0, sizeZ + rng:NextNumber(3, 8))
		tree(scenery, origin + at, rng:NextNumber(0.8, 1.3))
	end
	for _ = 1, 6 do
		local at = Vector3.new(rng:NextNumber(-10, sizeX + 10), 0.5, sizeZ + rng:NextNumber(2, 10))
		rock(scenery, origin + at, rng:NextNumber(1.5, 3.5))
	end
	noQuery(scenery)
	scenery.Parent = model
	core(model, origin)
end

-- Shared world bits, once per server: ocean far below and soft clouds.
function PlotBuilder.buildWorld()
	local terrain = workspace.Terrain
	terrain:FillBlock(CFrame.new(800, -70, 0), Vector3.new(4000, 20, 2000), Enum.Material.Water)
	terrain.WaterColor = Color3.fromRGB(40, 120, 170)
	terrain.WaterWaveSize = 0.15
	terrain.WaterTransparency = 0.4
	if not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.55
		clouds.Density = 0.6
		clouds.Parent = terrain
	end
end

return PlotBuilder

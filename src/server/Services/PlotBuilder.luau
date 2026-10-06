--!strict
-- Builds the static scenery of a plot: a floating grass island with a rocky
-- underside, the fixed tower core in the middle (Config.CORE), the spawn apron
-- and a few trees and rocks around the edge. Nothing here is part of a tower.

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local PlotBuilder = {}

local GRID_TEXTURE = "rbxassetid://139861751774533" -- assets/ui/grid_cell.png

local G = Config.GRID_STUDS
local GRASS = Color3.fromRGB(96, 196, 80)
local ROCK = Color3.fromRGB(165, 128, 96)
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

-- A copy of a Creator Store model from ServerStorage.SceneryAssets, scaled and
-- set on the ground at `at`. Returns nil when the asset isn't there.
local function prop(parent: Instance, name: string, at: Vector3, scale: number, rng: Random): Model?
	local assets = game:GetService("ServerStorage"):FindFirstChild("SceneryAssets")
	local template = assets and assets:FindFirstChild(name)
	if not template or not template:IsA("Model") then
		return nil
	end
	local m = template:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy() -- never run scripts from free models
		end
	end
	m:ScaleTo(m:GetScale() * scale)
	m:PivotTo(CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	local cf, size = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() + (at - Vector3.new(cf.X, cf.Y - size.Y / 2, cf.Z)))
	m.Parent = parent
	return m
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

-- The fixed tower frame: four steel corner pillars and a blue floor every
-- level (Config.CORE / TowerCodec.inCore). Pillars sit 0.1 studs inside the
-- footprint so no face is shared with the floors or neighbouring pieces.
local function core(model: Model, origin: Vector3)
	local c = Config.CORE
	local h = c.height * G
	local folder = Instance.new("Folder")
	folder.Name = "Core"
	local steel = Color3.fromRGB(168, 170, 176) -- light concrete grey, like the thumbnail
	local floorColor = Color3.fromRGB(40, 120, 255)
	local trimColor = Color3.fromRGB(255, 205, 40)
	for _, x in { c.x0, c.x1 - 1 } do
		for _, z in { c.z0, c.z1 - 1 } do
			local p = part(
				folder,
				"CorePillar",
				Vector3.new(G - 0.4, h - 0.02, G - 0.4), -- just inside the cell it reserves
				CFrame.new(origin + Vector3.new((x + 0.5) * G, h / 2 - 0.01, (z + 0.5) * G)),
				steel,
				Enum.Material.SmoothPlastic
			)
			p:SetAttribute("Core", true)
		end
	end
	local w, d = (c.x1 - c.x0) * G, (c.z1 - c.z0) * G
	local cx, cz = (c.x0 + c.x1) / 2 * G, (c.z0 + c.z1) / 2 * G
	for k = 1, c.levels do
		local top = k * c.level * G
		local floor = part(
			folder,
			"CoreFloor",
			Vector3.new(w, 1.4, d),
			CFrame.new(origin + Vector3.new(cx, top - 0.7, cz)),
			floorColor,
			Enum.Material.SmoothPlastic
		)
		floor:SetAttribute("Core", true)
		-- Yellow trim around the floor edge (decor, just inside the footprint).
		for _, e in
			{
				{ Vector3.new(w - 0.4, 0.6, 0.6), Vector3.new(0, 0, d / 2 - 0.5) },
				{ Vector3.new(w - 0.4, 0.6, 0.6), Vector3.new(0, 0, -d / 2 + 0.5) },
				{ Vector3.new(0.6, 0.6, d - 0.4), Vector3.new(w / 2 - 0.5, 0, 0) },
				{ Vector3.new(0.6, 0.6, d - 0.4), Vector3.new(-w / 2 + 0.5, 0, 0) },
			}
		do
			decoPart(
				folder,
				"CoreTrim",
				e[1],
				CFrame.new(origin + Vector3.new(cx, top - 1.7, cz) + e[2]),
				trimColor,
				Enum.Material.SmoothPlastic
			)
		end
	end
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
	base.Color = GRASS
	base.Material = Enum.Material.SmoothPlastic
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
			Enum.Material.SmoothPlastic
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
			Enum.Material.SmoothPlastic
		)
		top -= depth
	end

	-- Trees, bushes and rocks on the rim, outside the buildable grid. Uses the free
	-- Creator Store models in ServerStorage.SceneryAssets (see CREDITS.md) and
	-- falls back to simple part-built ones when they are missing.
	local rng = Random.new(model.Name:len() * 7919)
	local function rimSpot(margin: number): Vector3
		local side = rng:NextInteger(1, 4)
		return if side == 1
			then Vector3.new(
				rng:NextNumber(-RIM + margin, -margin),
				0,
				rng:NextNumber(front + margin, back - margin)
			)
			elseif side == 2 then Vector3.new(
				sizeX + rng:NextNumber(margin, RIM - margin),
				0,
				rng:NextNumber(front + margin, back - margin)
			)
			elseif side == 3 then Vector3.new(
				rng:NextNumber(0, sizeX),
				0,
				sizeZ + rng:NextNumber(margin, RIM - margin)
			)
			else Vector3.new(rng:NextNumber(0, sizeX), 0, front + rng:NextNumber(margin, RIM - margin))
	end
	local placed = 0
	for _, spec in
		{
			{ names = { "Tree1", "Tree2" }, count = 8, scale = { 0.45, 0.7 }, margin = 4 },
			{ names = { "Bush1", "Bush2" }, count = 10, scale = { 0.6, 0.9 }, margin = 2 },
			{ names = { "Rock1", "Rock2" }, count = 6, scale = { 0.25, 0.5 }, margin = 2 },
		}
	do
		for _ = 1, spec.count do
			local name = spec.names[rng:NextInteger(1, #spec.names)]
			if
				prop(
					scenery,
					name,
					origin + rimSpot(spec.margin),
					rng:NextNumber(spec.scale[1], spec.scale[2]),
					rng
				)
			then
				placed += 1
			end
		end
	end
	if placed == 0 then
		for _ = 1, 7 do
			tree(scenery, origin + rimSpot(3), rng:NextNumber(0.8, 1.3))
		end
		for _ = 1, 6 do
			rock(scenery, origin + rimSpot(2) + Vector3.new(0, 0.5, 0), rng:NextNumber(1.5, 3.5))
		end
	end
	-- Flower patches (Flower1 from SceneryAssets), petals tinted per patch.
	local petals = {
		Color3.fromRGB(255, 90, 120),
		Color3.fromRGB(255, 210, 60),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(170, 110, 255),
	}
	for _ = 1, 14 do
		local c = origin + rimSpot(2)
		local color = petals[rng:NextInteger(1, #petals)]
		for _ = 1, rng:NextInteger(2, 4) do
			local at = c + Vector3.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5))
			local flower = prop(scenery, "Flower1", at, rng:NextNumber(0.35, 0.5), rng)
			if flower then
				for _, d in flower:GetDescendants() do
					if d:IsA("BasePart") then
						d.CanCollide = false
						if d.Name:find("Mesh35") then
							d.Color = color
						end
					end
				end
			end
		end
	end
	-- Start gate at the front of the apron: two posts and a banner.
	local gateZ = -apronDepth + 1
	for _, x in { 2, sizeX - 2 } do
		part(
			scenery,
			"GatePost",
			Vector3.new(2, 14, 2),
			CFrame.new(origin + Vector3.new(x, 7, gateZ)),
			Color3.fromRGB(255, 140, 30),
			Enum.Material.SmoothPlastic
		)
		local cap = decoPart(
			scenery,
			"GateCap",
			Vector3.new(2.6, 1, 2.6),
			CFrame.new(origin + Vector3.new(x, 14.5, gateZ)),
			Color3.fromRGB(255, 205, 40),
			Enum.Material.Neon
		)
		cap.CastShadow = false
	end
	local banner = decoPart(
		scenery,
		"GateBanner",
		Vector3.new(sizeX - 2, 3.4, 0.6),
		CFrame.new(origin + Vector3.new(sizeX / 2, 13, gateZ)),
		Color3.fromRGB(40, 120, 255),
		Enum.Material.SmoothPlastic
	)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.PixelsPerStud = 20
		gui.LightInfluence = 0
		gui.Parent = banner
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.FredokaOne
		text.TextScaled = true
		text.Text = "BUILD A TOWER"
		text.TextColor3 = Color3.new(1, 1, 1)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(20, 50, 130)
		stroke.Parent = text
		text.Parent = gui
	end
	noQuery(scenery)
	scenery.Parent = model
	core(model, origin)
end

-- Bright cartoon daylight like the store thumbnail: deep blue sky, crisp sun,
-- saturated colours. Lives in code so every server (and the preview) matches.
function PlotBuilder.lighting()
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 14.5
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(120, 130, 150)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 165, 190)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.ExposureCompensation = 0.1
	local function get<T>(class: string): T
		local found = Lighting:FindFirstChildOfClass(class :: any)
		if not found then
			found = Instance.new(class :: any)
			found.Parent = Lighting
		end
		return found :: any
	end
	local atmosphere = get("Atmosphere") :: Atmosphere
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(175, 215, 255)
	atmosphere.Decay = Color3.fromRGB(70, 140, 230)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 0.6
	local cc = get("ColorCorrectionEffect") :: ColorCorrectionEffect
	cc.Saturation = 0.22
	cc.Contrast = 0.08
	cc.Brightness = 0.02
	cc.TintColor = Color3.fromRGB(255, 252, 245)
	local bloom = get("BloomEffect") :: BloomEffect
	bloom.Intensity = 0.6
	bloom.Size = 30
	bloom.Threshold = 1.6
	local rays = get("SunRaysEffect") :: SunRaysEffect
	rays.Intensity = 0.05
	rays.Spread = 0.6
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		dof.Enabled = false -- keeps the far islands crisp, like the thumbnail
	end
end

-- Scenery props for the world, with no collision or shadows.
local function skyProp(parent: Instance, name: string, at: Vector3, scale: number, rng: Random): Model?
	local m = prop(parent, name, at, scale, rng)
	if m then
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CastShadow = false
			end
		end
	end
	return m
end

-- Shared world bits, once per server: ocean, hills on the horizon, floating
-- islands and puffy clouds all around the plot row (plots run along +X).
function PlotBuilder.buildWorld()
	PlotBuilder.lighting()
	local terrain = workspace.Terrain
	terrain:FillBlock(CFrame.new(800, -70, 0), Vector3.new(4000, 20, 2000), Enum.Material.Water)
	terrain.WaterColor = Color3.fromRGB(25, 95, 175)
	terrain.WaterWaveSize = 0.15
	terrain.WaterTransparency = 0.15
	terrain.WaterReflectance = 0.6
	if not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.45
		clouds.Density = 0.5
		clouds.Color = Color3.fromRGB(255, 255, 255)
		clouds.Parent = terrain
	end
	if workspace:FindFirstChild("World") then
		return
	end
	local world = Instance.new("Folder")
	world.Name = "World"
	local rng = Random.new(20261006)
	local X0, X1 = -500, 2100 -- plot row spans about x 0..1600
	-- Grassy mesas on the far horizon (Hill1, about 43 studs wide), half sunk in the sea.
	for _, side in { -1, 1 } do
		local x = X0 - 400
		while x < X1 + 400 do
			local scale = rng:NextNumber(5, 11)
			local sink = 22 * scale * rng:NextNumber(0.4, 0.6)
			skyProp(world, "Hill1", Vector3.new(x, -60 - sink, side * rng:NextNumber(1300, 1500)), scale, rng)
			x += 43 * scale * rng:NextNumber(0.6, 0.9)
		end
	end
	-- Floating islands (Island1, about 29 studs wide) with a tree or two on top.
	for _ = 1, 26 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local at =
			Vector3.new(rng:NextNumber(X0, X1), rng:NextNumber(-60, 130), side * rng:NextNumber(260, 700))
		local scale = rng:NextNumber(1, 2.4)
		local island = skyProp(world, "Island1", at, scale, rng)
		if island then
			local cf, size = island:GetBoundingBox()
			local top = cf.Position + Vector3.new(0, size.Y / 2, 0)
			for _ = 1, rng:NextInteger(1, 2) do
				local a = rng:NextNumber(0, math.pi * 2)
				local d = rng:NextNumber(0, size.X * 0.25)
				local treeName = if rng:NextInteger(1, 2) == 1 then "Tree1" else "Tree2"
				skyProp(
					world,
					treeName,
					top + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d),
					scale * 0.6,
					rng
				)
			end
		end
	end
	-- Low-poly clouds (Cloud1): some low beside the plots, most high around the towers.
	for _ = 1, 60 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		skyProp(
			world,
			"Cloud1",
			Vector3.new(rng:NextNumber(X0, X1), rng:NextNumber(40, 320), side * rng:NextNumber(170, 800)),
			rng:NextNumber(1.5, 4),
			rng
		)
	end
	world.Parent = workspace
end

return PlotBuilder

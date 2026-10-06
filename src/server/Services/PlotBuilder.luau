--!strict
-- Builds the static scenery of a plot: a floating island (Creator Store mesh),
-- the fixed tower core in the middle (Config.CORE), the spawn apron
-- and props around the edge. Nothing here is part of a tower.

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local PlotBuilder = {}

-- Plots float this high above the ocean (sea level is about y -60), up in the clouds.
PlotBuilder.ALTITUDE = 300

local GRID_TEXTURE = "rbxassetid://139861751774533" -- assets/ui/grid_cell.png

local G = Config.GRID_STUDS
local GRASS = Color3.fromRGB(128, 196, 84) -- matches the Island2 mesh grass

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

-- The fixed tower frame: four corner pillars and a floor every level
-- (Config.CORE / TowerCodec.inCore). Every part stays inside the cells the core
-- reserves, so no face is shared with player pieces. Only the pillar shafts and
-- floor slabs collide; the rest is trim.
local function core(model: Model, origin: Vector3)
	local c = Config.CORE
	local h = c.height * G
	local lv = c.level * G
	local folder = Instance.new("Folder")
	folder.Name = "Core"
	local concrete = Color3.fromRGB(196, 198, 204)
	local band = Color3.fromRGB(120, 124, 134)
	local floorColor = Color3.fromRGB(40, 120, 255)
	local beamColor = Color3.fromRGB(24, 70, 170)
	local trimColor = Color3.fromRGB(255, 205, 40)
	local cx, cz = (c.x0 + c.x1) / 2 * G, (c.z0 + c.z1) / 2 * G
	for _, x in { c.x0, c.x1 - 1 } do
		for _, z in { c.z0, c.z1 - 1 } do
			local at = origin + Vector3.new((x + 0.5) * G, 0, (z + 0.5) * G)
			local p = part(
				folder,
				"CorePillar",
				Vector3.new(G - 0.8, h - 0.02, G - 0.8),
				CFrame.new(at + Vector3.new(0, h / 2 - 0.01, 0)),
				concrete,
				Enum.Material.Concrete
			)
			p:SetAttribute("Core", true)
			-- Corner ribs running up the shaft.
			for _, s in
				{ Vector3.new(1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(-1, 0, -1) }
			do
				decoPart(
					folder,
					"CoreRib",
					Vector3.new(0.6, h - 0.2, 0.6),
					CFrame.new(at + Vector3.new(0, h / 2, 0) + s * (G / 2 - 0.55)),
					band,
					Enum.Material.Metal
				)
			end
			for k = 0, c.levels - 1 do
				local y = k * lv
				-- Plinth at the foot of each level.
				decoPart(
					folder,
					"CorePlinth",
					Vector3.new(G - 0.2, 1, G - 0.2),
					CFrame.new(at + Vector3.new(0, y + 0.5, 0)),
					band,
					Enum.Material.Concrete
				)
				-- Level number facing outwards on both open sides.
				for _, face in
					{
						if x == c.x0 then Enum.NormalId.Left else Enum.NormalId.Right,
						if z == c.z0 then Enum.NormalId.Front else Enum.NormalId.Back,
					}
				do
					local gui = Instance.new("SurfaceGui")
					gui.Face = face
					gui.PixelsPerStud = 20
					gui.LightInfluence = 0.3
					gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
					local label = Instance.new("TextLabel")
					label.AnchorPoint = Vector2.new(0.5, 0)
					label.Position = UDim2.fromScale(0.5, 1 - (y + lv * 0.75) / h)
					label.Size = UDim2.fromScale(0.95, 4.5 / h)
					label.BackgroundTransparency = 1
					label.Font = Enum.Font.FredokaOne
					label.TextScaled = true
					label.Text = tostring(k + 1)
					label.TextColor3 = Color3.new(1, 1, 1)
					local stroke = Instance.new("UIStroke")
					stroke.Thickness = 4
					stroke.Color = floorColor
					stroke.Parent = label
					label.Parent = gui
					gui.Parent = p
				end
			end
			decoPart(
				folder,
				"CoreCap",
				Vector3.new(G - 0.2, 0.8, G - 0.2),
				CFrame.new(at + Vector3.new(0, h - 0.4, 0)),
				trimColor,
				Enum.Material.SmoothPlastic
			)
		end
	end
	local w, d = (c.x1 - c.x0) * G, (c.z1 - c.z0) * G
	for k = 1, c.levels do
		local top = k * lv
		local floor = part(
			folder,
			"CoreFloor",
			Vector3.new(w - 0.1, 1.4, d - 0.1),
			CFrame.new(origin + Vector3.new(cx, top - 0.7, cz)),
			floorColor,
			Enum.Material.SmoothPlastic
		)
		floor:SetAttribute("Core", true)
		local grid = Instance.new("Texture")
		grid.Texture = GRID_TEXTURE
		grid.Face = Enum.NormalId.Top
		grid.StudsPerTileU = G
		grid.StudsPerTileV = G
		grid.Transparency = 0.7
		grid.Parent = floor
		-- Steel beams under the slab and hazard trim round its edge.
		for i = 1, c.x1 - c.x0 - 1 do
			decoPart(
				folder,
				"CoreBeam",
				Vector3.new(0.8, 1, d - 2.2),
				CFrame.new(origin + Vector3.new(c.x0 * G + i * G, top - 1.9, cz)),
				beamColor,
				Enum.Material.Metal
			)
		end
		for _, e in
			{
				{ Vector3.new(w - 2 * G + 0.8, 1.1, 0.6), Vector3.new(0, 0, d / 2 - 0.5) },
				{ Vector3.new(w - 2 * G + 0.8, 1.1, 0.6), Vector3.new(0, 0, -d / 2 + 0.5) },
				{ Vector3.new(0.6, 1.1, d - 2 * G + 0.8), Vector3.new(w / 2 - 0.5, 0, 0) },
				{ Vector3.new(0.6, 1.1, d - 2 * G + 0.8), Vector3.new(-w / 2 + 0.5, 0, 0) },
			}
		do
			decoPart(
				folder,
				"CoreTrim",
				e[1],
				CFrame.new(origin + Vector3.new(cx, top - 1.9, cz) + e[2]),
				trimColor,
				Enum.Material.DiamondPlate
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
-- All scenery is Creator Store models from ServerStorage.SceneryAssets
-- (see CREDITS.md); missing ones are simply skipped.
function PlotBuilder.build(model: Model, origin: Vector3, apronDepth: number)
	local sizeX, sizeZ = Config.PLOT_CELLS_X * G, Config.PLOT_CELLS_Z * G
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	local rng = Random.new(model.Name:len() * 7919)

	local RIM = 12
	local front = -apronDepth - RIM
	local back = sizeZ + RIM
	local islandX = sizeX + RIM * 2

	-- Island2 is one big grass-and-cliff mesh with a raised plateau in its +Z
	-- half. Stretched so its top covers the plot and rim and the plateau ends up
	-- as a hill behind it. Its top isn't flat, so it is lowered until no point of
	-- the rim is above the grid, and every prop is dropped onto the surface. The
	-- template is set to PreciseConvexDecomposition in Studio so players walk on it.
	local meshSize = Vector3.new(islandX * 1.8, 130, 300)
	local meshCenterZ = front + meshSize.Z * 0.35
	local meshCenterX = sizeX / 2 - 18 -- covers the notch in the mesh's front-left corner
	local hillAt = origin + Vector3.new(meshCenterX, 0, meshCenterZ + meshSize.Z * 0.25)
	local assets = game:GetService("ServerStorage"):FindFirstChild("SceneryAssets")
	local template = assets and assets:FindFirstChild("Island2")
	local surfaceAt: (number, number) -> number? = function(_x, _z)
		return nil
	end
	-- `at` dropped onto the island if the ground within `r` studs is level
	-- enough to stand a prop on (nothing hangs over an edge or a slope).
	local function spot(at: Vector3, r: number): Vector3?
		local x, z = at.X - origin.X, at.Z - origin.Z
		local y = surfaceAt(x, z)
		if not y then
			return nil
		end
		for _, o in { Vector2.new(r, 0), Vector2.new(-r, 0), Vector2.new(0, r), Vector2.new(0, -r) } do
			local oy = surfaceAt(x + o.X, z + o.Y)
			if not oy or math.abs(oy - y) > 1 then
				return nil
			end
		end
		return Vector3.new(at.X, y, at.Z)
	end
	local ground: (Vector3) -> Vector3 = function(at)
		return at
	end
	local islandModel: Model? = nil
	if template and template:IsA("Model") then
		local m = template:Clone()
		m.Name = "Island"
		local from, size = m:GetBoundingBox()
		local k = meshSize / size
		local to = CFrame.new(origin + Vector3.new(meshCenterX, -meshSize.Y * 0.245, meshCenterZ))
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				local rel = from:ToObjectSpace(d.CFrame)
				d.Size *= k
				d.CFrame = to * CFrame.new(rel.Position * k) * rel.Rotation
				d.Anchored = true
				d.CanTouch = false
				d.CanQuery = true
			end
		end
		m.Parent = workspace -- briefly, so it can be raycast
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { m }
		local function surface(x: number, z: number): number?
			local hit = workspace:Raycast(origin + Vector3.new(x, 200, z), Vector3.new(0, -400, 0), params)
			return hit and hit.Position.Y
		end
		local top = -math.huge
		for x = 0, sizeX, 4 do
			for z = -apronDepth, sizeZ, 4 do
				top = math.max(top, surface(x, z) or -math.huge)
			end
		end
		if top > -math.huge then
			m:PivotTo(m:GetPivot() - Vector3.new(0, top - origin.Y + 0.2, 0))
		end
		surfaceAt = surface
		ground = function(at: Vector3): Vector3
			local y = surface(at.X - origin.X, at.Z - origin.Z)
			return if y then Vector3.new(at.X, y, at.Z) else at
		end
		islandModel = m
	end

	-- Fence round the rim, open at the front of the apron.
	local function fenceLine(a: Vector3, b: Vector3)
		local len = (b - a).Magnitude
		local n = math.max(1, math.round(len / 11.5))
		for i = 0, n - 1 do
			local at = ground(origin + a:Lerp(b, (i + 0.5) / n))
			-- Skip segments that would sit on the hill.
			local f = if at.Y < origin.Y + 0.5 then prop(scenery, "Fence1", at, len / n / 11.5, rng) else nil
			if f then
				f:PivotTo(
					CFrame.lookAt(f:GetPivot().Position, f:GetPivot().Position + (b - a))
						* CFrame.Angles(0, math.pi / 2, 0)
				)
			end
		end
	end
	local e = RIM - 1.5
	fenceLine(Vector3.new(-e, 0, front + 1.5), Vector3.new(-e, 0, back - 1.5))
	fenceLine(Vector3.new(sizeX + e, 0, front + 1.5), Vector3.new(sizeX + e, 0, back - 1.5))
	fenceLine(Vector3.new(-e, 0, back - 1.5), Vector3.new(sizeX + e, 0, back - 1.5))

	-- Lamps at the start line and the plot corners.
	for _, at in
		{
			Vector3.new(-2, 0, -apronDepth),
			Vector3.new(sizeX + 2, 0, -apronDepth),
			Vector3.new(-2, 0, sizeZ + 2),
			Vector3.new(sizeX + 2, 0, sizeZ + 2),
			Vector3.new(-2, 0, sizeZ / 2),
			Vector3.new(sizeX + 2, 0, sizeZ / 2),
		}
	do
		prop(scenery, "Lamp1", ground(origin + at), 1, rng)
	end

	-- A prop on level ground near `at`, or nothing.
	local function place(name: string, at: Vector3, scale: number): Model?
		local p = spot(at, if name:find("Tree") then 5 else 1.5)
		return if p then prop(scenery, name, p, scale, rng) else nil
	end

	-- Trees, bushes, rocks, mushrooms and grass on the rim (outside the grid).
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
	for _, spec in
		{
			{ names = { "Tree1", "Tree2" }, count = 6, scale = { 0.45, 0.7 }, margin = 4 },
			{ names = { "Bush1", "Bush2" }, count = 12, scale = { 0.6, 0.9 }, margin = 2 },
			{ names = { "Rock1", "Rock2" }, count = 8, scale = { 0.25, 0.5 }, margin = 2 },
			{ names = { "Mushroom1" }, count = 8, scale = { 0.3, 0.5 }, margin = 2 },
			{ names = { "Grass1" }, count = 60, scale = { 0.8, 1.4 }, margin = 1 },
		}
	do
		for _ = 1, spec.count do
			place(
				spec.names[rng:NextInteger(1, #spec.names)],
				origin + rimSpot(spec.margin),
				rng:NextNumber(spec.scale[1], spec.scale[2])
			)
		end
	end
	-- Meadow outside the fence: random spots on the island top (not the cliffs
	-- or the hill) get trees, bushes, rocks, mushrooms, flowers and grass.
	local outer = {
		{ names = { "Tree1", "Tree2" }, count = 14, scale = { 0.6, 1 } },
		{ names = { "Bush1", "Bush2" }, count = 20, scale = { 0.6, 1 } },
		{ names = { "Rock1", "Rock2" }, count = 10, scale = { 0.3, 0.7 } },
		{ names = { "Mushroom1" }, count = 10, scale = { 0.3, 0.6 } },
		{ names = { "Flower1" }, count = 40, scale = { 0.35, 0.5 } },
		{ names = { "Grass1" }, count = 120, scale = { 0.8, 1.4 } },
	}
	local halfX = meshSize.X / 2
	for _, spec in outer do
		local placed, tries = 0, 0
		while placed < spec.count and tries < spec.count * 10 do
			tries += 1
			local x = rng:NextNumber(meshCenterX - halfX, meshCenterX + halfX)
			local z = rng:NextNumber(meshCenterZ - meshSize.Z / 2, hillAt.Z - origin.Z - 30)
			local inside = x > -RIM - 2 and x < sizeX + RIM + 2 and z > front - 2 and z < back + 2
			local y = if inside then nil else surfaceAt(x, z)
			if
				y
				and y > origin.Y - 6
				and y < origin.Y + 1
				and place(
					spec.names[rng:NextInteger(1, #spec.names)],
					origin + Vector3.new(x, 0, z),
					rng:NextNumber(spec.scale[1], spec.scale[2])
				)
			then
				placed += 1
			end
		end
	end
	-- A little wood on the hill behind the plot.
	for _ = 1, 9 do
		local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, 40)
		local name = if rng:NextInteger(1, 2) == 1 then "Tree1" else "Tree2"
		place(
			name,
			hillAt + Vector3.new(math.cos(a) * r * 1.4, 0, math.sin(a) * r * 0.6),
			rng:NextNumber(0.6, 1)
		)
	end
	-- Flower patches (Flower1), petals tinted per patch.
	local petals = {
		Color3.fromRGB(255, 90, 120),
		Color3.fromRGB(255, 210, 60),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(170, 110, 255),
	}
	for _ = 1, 16 do
		local c = origin + rimSpot(2)
		local color = petals[rng:NextInteger(1, #petals)]
		for _ = 1, rng:NextInteger(2, 4) do
			local at = c + Vector3.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5))
			local flower = place("Flower1", at, rng:NextNumber(0.35, 0.5))
			if flower then
				for _, d in flower:GetDescendants() do
					if d:IsA("BasePart") and d.Name:find("Mesh35") then
						d.Color = color
					end
				end
			end
		end
	end
	-- Props are walk-through except tree trunks, rocks and fences.
	for _, m in scenery:GetChildren() do
		if
			m:IsA("Model")
			and not (
				m.Name:find("Tree")
				or m.Name:find("Rock")
				or m.Name:find("Fence")
				or m.Name:find("Lamp")
			)
		then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					d.CanCollide = false
				end
			end
		end
	end
	if islandModel then
		islandModel.Parent = scenery
	end
	noQuery(scenery)
	scenery.Parent = model
	core(model, origin)
end

-- Bright cartoon daylight like the store thumbnail: deep blue sky, crisp sun,
-- saturated colours. Lives in code so every server (and the preview) matches.
function PlotBuilder.lighting()
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 16.3
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
	rays.Intensity = 0.12
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
	local ALT = PlotBuilder.ALTITUDE
	local X0, X1 = -500, 2100 -- plot row spans about x 0..1600
	local mid = Vector3.new((X0 + X1) / 2, 0, 0)
	local terrain = workspace.Terrain
	-- ponytail: one big water slab; split into chunks if FillBlock stalls startup
	terrain:FillBlock(CFrame.new(mid.X, -64, 0), Vector3.new(7000, 8, 7000), Enum.Material.Water)
	terrain.WaterColor = Color3.fromRGB(20, 110, 190)
	terrain.WaterWaveSize = 0.3
	terrain.WaterWaveSpeed = 8
	terrain.WaterTransparency = 0.2
	terrain.WaterReflectance = 0.8
	if not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.5
		clouds.Density = 0.6
		clouds.Color = Color3.fromRGB(255, 255, 255)
		clouds.Parent = terrain
	end
	if workspace:FindFirstChild("World") then
		return
	end
	local world = Instance.new("Folder")
	world.Name = "World"
	local rng = Random.new(20261006)
	local function around(r0: number, r1: number): Vector3
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(r0, r1)
		return mid + Vector3.new(math.cos(a) * r * 1.4, 0, math.sin(a) * r) -- stretched along the plot row
	end
	-- Mountains rising out of the ocean all around (Hill1, about 43 studs wide).
	for _ = 1, 40 do
		local scale = rng:NextNumber(5, 10)
		skyProp(world, "Hill1", around(1600, 2600) - Vector3.new(0, 64 + 22 * scale * 0.3, 0), scale, rng)
	end
	-- Rocky islets in the sea far below.
	for _ = 1, 25 do
		skyProp(world, "Rock2", around(500, 1500) - Vector3.new(0, 66, 0), rng:NextNumber(1, 3), rng)
	end
	-- Floating islands (Island1, about 29 studs wide) at plot height, with trees.
	for _ = 1, 34 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local at = Vector3.new(
			rng:NextNumber(X0, X1),
			ALT + rng:NextNumber(-140, 160),
			side * rng:NextNumber(260, 900)
		)
		local scale = rng:NextNumber(1.2, 3.5)
		local island = skyProp(world, "Island1", at, scale, rng)
		if island then
			local cf, size = island:GetBoundingBox()
			-- Trees dropped onto the island's top with a raycast (it isn't flat).
			island.Parent = workspace
			local parts = {}
			for _, d in island:GetDescendants() do
				if d:IsA("BasePart") then
					d.CanQuery = true
					table.insert(parts, d)
				end
			end
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { island }
			for _ = 1, rng:NextInteger(1, 3) do
				local a = rng:NextNumber(0, math.pi * 2)
				local d = rng:NextNumber(0, size.X * 0.15)
				local from = cf.Position + Vector3.new(math.cos(a) * d, size.Y, math.sin(a) * d)
				local hit = workspace:Raycast(from, Vector3.new(0, -size.Y * 2, 0), params)
				if hit and hit.Normal.Y > 0.8 then
					local treeName = if rng:NextInteger(1, 2) == 1 then "Tree1" else "Tree2"
					skyProp(world, treeName, hit.Position, scale * 0.6, rng)
				end
			end
			for _, d in parts do
				d.CanQuery = false
			end
			island.Parent = world
		end
	end
	-- A sea of clouds (Cloud1) below the plots, and scattered ones above.
	for _ = 1, 140 do
		local at =
			Vector3.new(rng:NextNumber(X0, X1), ALT - rng:NextNumber(90, 160), rng:NextNumber(-900, 900))
		skyProp(world, "Cloud1", at, rng:NextNumber(3, 7), rng)
	end
	for _ = 1, 45 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local at = Vector3.new(
			rng:NextNumber(X0, X1),
			ALT + rng:NextNumber(20, 300),
			side * rng:NextNumber(170, 800)
		)
		skyProp(world, "Cloud1", at, rng:NextNumber(1.5, 4), rng)
	end
	world.Parent = workspace
end

return PlotBuilder

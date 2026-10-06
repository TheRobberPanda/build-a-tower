--!strict
-- Looks for placed pieces. Gameplay shape/collision stays on the main part
-- (PlotService); this only recolours it and adds decoration children that never
-- collide, touch or block raycasts.

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local PieceVisuals = {}

local G = Config.GRID_STUDS

-- Chunky cartoon looks matching the hotbar icon sheet (assets/ui/piece_icons.png).
local STONE = Color3.fromRGB(150, 156, 168)
local BRICK = Color3.fromRGB(138, 144, 156) -- walls, fake walls and one-way walls must match
local BLUE = Color3.fromRGB(60, 140, 235)
local WOOD = Color3.fromRGB(176, 110, 62)
local DARK = Color3.new(0, 0, 0)

local function deco(
	parent: BasePart,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = "Deco"
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function sparkles(part: BasePart, color: Color3, rate: number)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(2, 4)
	e.SpreadAngle = Vector2.new(25, 25)
	e.Rate = rate
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = part
end

local function pole(part: BasePart, flagColor: Color3, scale: number?)
	local k = scale or 1
	local top = part.CFrame * CFrame.new(-part.Size.X / 2 + 0.4, part.Size.Y / 2, -part.Size.Z / 2 + 0.4)
	deco(
		part,
		Vector3.new(0.3 * k, 5 * k, 0.3 * k),
		top * CFrame.new(0, 2.5 * k, 0),
		Color3.fromRGB(230, 230, 235),
		Enum.Material.Metal
	)
	deco(
		part,
		Vector3.new(0.1, 1.6 * k, 2.4 * k),
		top * CFrame.new(0, 4.1 * k, 1.25 * k),
		flagColor,
		Enum.Material.Fabric
	)
end

-- AI-painted face textures matching the icon sheet (assets/textures/*.png). The
-- painted rim gives each face its cartoon outline; the factory's inset keeps gaps.
local TEX = {
	stone = "rbxassetid://119484405922970",
	brick = "rbxassetid://115361175478336",
	wood = "rbxassetid://112942160962510",
	platform = "rbxassetid://77281096911289",
	tiles = "rbxassetid://104813448091682",
	crumble = "rbxassetid://125530033648969",
	sun = "rbxassetid://92738377327937",
	moon = "rbxassetid://126322619810953",
	orangewood = "rbxassetid://116469885897832",
}
PieceVisuals.TEX = TEX

-- One stretched decal per face; long thin faces (slab and wall sides) get the
-- image tiled in squares instead, so it isn't squashed. They fade with the piece.
local function skin(part: BasePart, image: string, faces: { Enum.NormalId }?, stretch: boolean?)
	local s = part.Size
	for _, face in faces or Enum.NormalId:GetEnumItems() :: { Enum.NormalId } do
		local u, v = s.X, s.Z
		if face == Enum.NormalId.Front or face == Enum.NormalId.Back then
			v = s.Y
		elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then
			u, v = s.Z, s.Y
		end
		local short = math.min(u, v)
		local d: Decal
		if not stretch and short < math.max(u, v) * 0.7 then
			local t = Instance.new("Texture")
			t.StudsPerTileU = short
			t.StudsPerTileV = short
			d = t
		else
			d = Instance.new("Decal")
		end
		d.Name = "Skin"
		d.Texture = image
		d.Face = face
		d.Parent = part
	end
	part:GetPropertyChangedSignal("Transparency"):Connect(function()
		for _, c in part:GetChildren() do
			if c:IsA("Decal") and c.Name == "Skin" then
				c.Transparency = part.Transparency
			end
		end
	end)
end
PieceVisuals.skin = skin

local WEDGE =
	{ Enum.NormalId.Top, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Bottom }
PieceVisuals.WEDGE = WEDGE

-- Breaks a part into unanchored chunks that tumble away and vanish (crumble
-- platforms, collapsing towers). The caller hides or removes the part itself.
function PieceVisuals.shatter(part: BasePart)
	local s = part.Size
	local n = Vector3.new(
		math.clamp(math.round(s.X / 2), 1, 4),
		math.clamp(math.round(s.Y / 2), 1, 4),
		math.clamp(math.round(s.Z / 2), 1, 4)
	)
	local cell = s / n
	for ix = 1, n.X do
		for iy = 1, n.Y do
			for iz = 1, n.Z do
				local c = Instance.new("Part")
				c.Name = "Chunk"
				c.Size = cell * (0.75 + math.random() * 0.2)
				c.CFrame = part.CFrame
					* CFrame.new((Vector3.new(ix, iy, iz) - Vector3.one * 0.5) * cell - s / 2)
				c.Color = part.Color
				c.Material = part.Material
				c.CanCollide = false
				c.CanQuery = false
				c.CanTouch = false
				c.CastShadow = false
				c.AssemblyLinearVelocity =
					Vector3.new(math.random(-8, 8), math.random(0, 10), math.random(-8, 8))
				c.AssemblyAngularVelocity =
					Vector3.new(math.random(-6, 6), math.random(-6, 6), math.random(-6, 6))
				c.Parent = workspace
				game:GetService("Debris"):AddItem(c, 2.5)
			end
		end
	end
end

-- Shakes a part (and its decoration) sideways for `seconds`, harder toward the
-- end: the warning before a crumble or collapse. Restores the original spot.
function PieceVisuals.tremble(part: BasePart, seconds: number)
	if part:GetAttribute("Trembling") then
		return
	end
	part:SetAttribute("Trembling", true)
	local parts: { BasePart } = { part }
	for _, d in part:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local base: { CFrame } = {}
	for i, p in parts do
		base[i] = p.CFrame
	end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < seconds and part.Parent do
			local k = 0.1 + 0.25 * (os.clock() - t0) / seconds
			local off = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * k
			for i, p in parts do
				p.CFrame = base[i] + off
			end
			task.wait(0.05)
		end
		for i, p in parts do
			p.CFrame = base[i]
		end
		part:SetAttribute("Trembling", nil)
	end)
end

-- Bits falling off the bottom, like the crumble icon's debris.
local function debris(part: BasePart)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(Color3.fromRGB(150, 110, 60))
	e.Size = NumberSequence.new(0.25)
	e.Lifetime = NumberRange.new(1, 1.5)
	e.Speed = NumberRange.new(0.5, 1)
	e.Acceleration = Vector3.new(0, -20, 0)
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Rate = 1.5
	e.Parent = part
end

-- A flat arrowhead (two bars) lying in `cf`'s XZ plane, pointing toward -Z.
local function chevron(part: BasePart, cf: CFrame, color: Color3, scale: number)
	for _, side in { -1, 1 } do
		deco(
			part,
			Vector3.new(0.4, 0.15, 1.6) * Vector3.new(scale, 1, scale),
			cf * CFrame.new(side * 0.55 * scale, 0, 0.55 * scale) * CFrame.Angles(0, side * math.rad(45), 0),
			color,
			Enum.Material.Neon
		)
	end
end

local function disc(
	part: BasePart,
	diameter: number,
	height: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = deco(
		part,
		Vector3.new(height, diameter, diameter),
		cf * CFrame.Angles(0, 0, math.pi / 2),
		color,
		material
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- name = piece type name; r = rotation; channelColor for linked pieces.
function PieceVisuals.decorate(part: BasePart, name: string, _y: number, r: number, channelColor: Color3?)
	local top = part.CFrame * CFrame.new(0, part.Size.Y / 2, 0)
	if name == "Block" then
		part.Color = STONE
		skin(part, TEX.stone)
	elseif name == "Wall" or name == "FakeWall" or name == "OneWay" then
		part.Color = BRICK
		skin(part, TEX.brick)
		if name == "OneWay" then
			-- Cyan arrow on both faces, pointing the way you may pass.
			for _, side in { -1, 1 } do
				local face = part.CFrame
					* CFrame.Angles(0, r * math.pi / 2, 0)
					* CFrame.new(0, 0, side * (math.min(part.Size.X, part.Size.Z) / 2 + 0.05))
					* CFrame.Angles(math.pi / 2, 0, 0)
				chevron(part, face, Color3.fromRGB(60, 230, 255), 1.3)
				deco(
					part,
					Vector3.new(0.6, 0.15, 2),
					face * CFrame.new(0, 0, 0.9),
					Color3.fromRGB(60, 230, 255),
					Enum.Material.Neon
				)
			end
		end
	elseif name == "Platform" then
		part.Color = BLUE
		skin(part, TEX.platform)
	elseif name == "BigFloor" then
		part.Color = Color3.fromRGB(120, 190, 240)
		skin(part, TEX.tiles)
	elseif name == "Ramp" then
		part.Color = WOOD
		skin(part, TEX.wood, WEDGE)
	elseif name == "Crumble" then
		part.Color = Color3.fromRGB(205, 165, 105)
		skin(part, TEX.crumble)
		debris(part)
	elseif name == "JumpPad" then
		-- Silver rim, orange cushion, cream arrow pointing up the pad (like the icon).
		part.Color = Color3.fromRGB(190, 195, 205)
		part.Material = Enum.Material.Metal
		local plate = part.CFrame * CFrame.new(0, part.Size.Y / 2 + 0.15, 0)
		local cushion = Color3.fromRGB(255, 140, 20)
		local w = part.Size.X - 1.4
		deco(part, Vector3.new(w, 0.5, w), plate, cushion)
		-- Rounded edges and corners: cylinders along each side, balls in the corners.
		for _, side in { -1, 1 } do
			for _, turn in { 0, math.pi / 2 } do
				local edge = deco(
					part,
					Vector3.new(w, 0.6, 0.6),
					plate * CFrame.Angles(0, turn, 0) * CFrame.new(0, 0, side * w / 2),
					cushion
				)
				edge.Shape = Enum.PartType.Cylinder
				local ball = deco(
					part,
					Vector3.one * 0.6,
					plate * CFrame.Angles(0, turn, 0) * CFrame.new(side * w / 2, 0, side * w / 2),
					cushion
				)
				ball.Shape = Enum.PartType.Ball
			end
		end
		local arrow = Color3.fromRGB(255, 240, 200)
		local up = plate * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, math.pi, 0)
		chevron(part, up * CFrame.new(0, 0, -0.6), arrow, 1.3)
		deco(part, Vector3.new(0.7, 0.15, 2.2), up * CFrame.new(0, 0, 0.8), arrow, Enum.Material.Neon)
		sparkles(part, Color3.fromRGB(255, 200, 90), 3)
	elseif name == "Teleporter" then
		-- Purple pad with a glowing swirl disc and a faint light column.
		local color = channelColor or Color3.fromRGB(170, 85, 255)
		part.Color = color:Lerp(DARK, 0.5)
		part.Material = Enum.Material.SmoothPlastic
		part.Size = Vector3.new(part.Size.X, 0.6, part.Size.Z)
		part.CFrame -= Vector3.new(0, (G - 0.6) / 2, 0)
		local pad = part.CFrame * CFrame.new(0, 0.35, 0)
		-- Gradient rings (dark rim -> white core) with three spiral arms on top, like the icon.
		for i = 0, 3 do
			disc(
				part,
				(G - 0.8) * (1 - i * 0.22),
				0.1 + i * 0.03,
				pad,
				color:Lerp(Color3.new(1, 1, 1), i * 0.22),
				Enum.Material.SmoothPlastic -- flat rings so the neon arms read as a swirl
			)
		end
		local white = color:Lerp(Color3.new(1, 1, 1), 0.7)
		for arm = 0, 2 do
			for k = 1, 6 do
				local a = arm * math.pi * 2 / 3 + k * 0.45
				local rad = 0.25 + k * 0.28
				deco(
					part,
					Vector3.new(0.18, 0.08, 0.7),
					pad * CFrame.new(math.cos(a) * rad, 0.24, math.sin(a) * rad) * CFrame.Angles(0, -a, 0),
					white:Lerp(color, k / 6),
					Enum.Material.Neon
				)
			end
		end
		deco(
			part,
			Vector3.new(G - 0.2, 0.3, G - 0.2),
			part.CFrame * CFrame.new(0, 0.2, 0),
			color:Lerp(DARK, 0.3)
		)
		sparkles(part, color, 8)
	elseif name == "Finish" then
		-- Just a big green flag on a wooden pole, like the icon (the box stays as the hitbox).
		part.Transparency = 1
		local base = part.CFrame * CFrame.new(0, -part.Size.Y / 2, 0)
		local h = G * 2.2
		deco(
			part,
			Vector3.new(0.6, h, 0.6),
			base * CFrame.new(0, h / 2, 0),
			Color3.fromRGB(200, 170, 120),
			Enum.Material.Wood
		)
		local green = Color3.fromRGB(60, 200, 70)
		deco(
			part,
			Vector3.new(G * 0.6, G * 0.8, 0.15),
			base * CFrame.new(G * 0.32, h - G * 0.45, 0) * CFrame.Angles(0, 0.2, 0),
			green,
			Enum.Material.Fabric
		)
		deco(
			part,
			Vector3.new(G * 0.65, G * 0.7, 0.15),
			base * CFrame.new(G * 0.9, h - G * 0.5, -0.25) * CFrame.Angles(0, -0.25, 0.08),
			green:Lerp(DARK, 0.15),
			Enum.Material.Fabric
		)
		local knob = deco(
			part,
			Vector3.one * 0.9,
			base * CFrame.new(0, h + 0.3, 0),
			Color3.fromRGB(255, 205, 60),
			Enum.Material.Metal
		)
		knob.Shape = Enum.PartType.Ball
		disc(
			part,
			2.2,
			0.5,
			base * CFrame.new(0, 0.25, 0),
			Color3.fromRGB(120, 120, 130),
			Enum.Material.Slate
		)
		sparkles(part, Color3.fromRGB(120, 255, 160), 8)
	elseif name == "Checkpoint" then
		part.Material = Enum.Material.Glass
		part.Color = Color3.fromRGB(90, 200, 205)
		pole(part, Color3.fromRGB(80, 190, 200))
		sparkles(part, Color3.fromRGB(120, 255, 255), 3)
	elseif name == "Conveyor" then
		-- Dark belt, yellow side rails, glowing chevrons pointing the way it carries you.
		local alongX = r % 2 == 1
		for _, side in { -1, 1 } do
			local offset = if alongX
				then CFrame.new(0, part.Size.Y / 2 + 0.3, side * (part.Size.Z / 2 - 0.2))
				else CFrame.new(side * (part.Size.X / 2 - 0.2), part.Size.Y / 2 + 0.3, 0)
			local size = if alongX
				then Vector3.new(part.Size.X, 0.7, 0.6)
				else Vector3.new(0.6, 0.7, part.Size.Z)
			deco(part, size, part.CFrame * offset, Color3.fromRGB(255, 200, 40), Enum.Material.Metal)
		end
		-- Round rollers at both ends, under the belt.
		local along = part.CFrame * CFrame.Angles(0, r * math.pi / 2, 0)
		local len = if alongX then part.Size.X else part.Size.Z
		local wide = if alongX then part.Size.Z else part.Size.X
		for _, e in { -1, 1 } do
			local roller = deco(
				part,
				Vector3.new(wide - 0.3, part.Size.Y + 0.1, part.Size.Y + 0.1),
				along * CFrame.new(0, 0, e * (len / 2 - 0.1)),
				Color3.fromRGB(40, 40, 48),
				Enum.Material.Metal
			)
			roller.Shape = Enum.PartType.Cylinder
		end
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Color3.fromRGB(35, 35, 42)
		local facing = CFrame.new(top.Position + Vector3.new(0, 0.12, 0))
			* CFrame.Angles(0, r * math.pi / 2, 0)
		for _, z in { -2.2, 0, 2.2 } do
			chevron(part, facing * CFrame.new(0, 0, z), Color3.fromRGB(255, 200, 40), 1.4)
		end
	elseif name == "Button" then
		local base = part.CFrame * CFrame.new(0, -part.Size.Y / 2 + 0.15, 0)
		disc(part, part.Size.X + 1.2, 0.3, base, Color3.fromRGB(140, 145, 155), Enum.Material.Metal)
		disc(part, part.Size.X + 0.2, part.Size.Y, part.CFrame, part.Color, Enum.Material.Neon)
		part.Transparency = 1 -- the round cap shows instead of the square hitbox
	elseif name == "Door" then
		-- Wooden door in a frame of its channel colour (the frame stays when it opens).
		local color = channelColor or part.Color
		part.Color = WOOD
		part.Size = Vector3.new(part.Size.X, part.Size.Y, 1.2) -- thin like the icon; still blocks the cell
		skin(part, TEX.wood, nil, true)
		local s = part.Size
		for _, z in { -1, 1 } do
			local knob = deco(
				part,
				Vector3.new(0.5, 0.5, 0.5),
				part.CFrame * CFrame.new(s.X / 2 - 0.9, -0.4, z * (s.Z / 2 + 0.2)),
				Color3.fromRGB(240, 200, 80),
				Enum.Material.Metal
			)
			knob.Shape = Enum.PartType.Ball
		end
		for _, side in { -1, 1 } do
			deco(
				part,
				Vector3.new(0.8, s.Y + 0.5, s.Z + 0.8),
				part.CFrame * CFrame.new(side * (s.X / 2 - 0.3), 0.25, 0),
				color
			)
		end
		deco(part, Vector3.new(s.X + 0.2, 0.8, s.Z + 1), part.CFrame * CFrame.new(0, s.Y / 2 + 0.1, 0), color)
	elseif name == "Plant" then
		-- Leafy bush: a cluster of balls on a dark soil square.
		part.Color = Color3.fromRGB(70, 150, 55)
		part.Size = Vector3.one * G * 0.7
		part.CFrame -= Vector3.new(0, G * 0.1, 0)
		deco(
			part,
			Vector3.new(G - 0.4, 0.4, G - 0.4),
			part.CFrame * CFrame.new(0, -G * 0.4 + 0.2, 0),
			Color3.fromRGB(60, 110, 45)
		)
		for i = 0, 4 do
			local a = i * math.pi * 2 / 5
			local ball = deco(
				part,
				Vector3.one * G * (0.42 + i % 2 * 0.08),
				part.CFrame
					* CFrame.new(math.cos(a) * G * 0.27, -G * 0.08 + i % 2 * 0.3, math.sin(a) * G * 0.27),
				Color3.fromRGB(55 + i * 8, 130 + i * 10, 45),
				Enum.Material.Grass
			)
			ball.Shape = Enum.PartType.Ball
		end
	elseif name == "Lamp" then
		-- Grey post with a glowing lantern on top.
		part.Color = Color3.fromRGB(70, 75, 85)
		part.Material = Enum.Material.Metal
		part.Size = Vector3.new(0.5, part.Size.Y - 1.6, 0.5)
		part.CFrame -= Vector3.new(0, 0.8, 0)
		local foot = part.CFrame * CFrame.new(0, -part.Size.Y / 2 + 0.2, 0)
		disc(part, 1.8, 0.4, foot, Color3.fromRGB(70, 75, 85), Enum.Material.Metal)
		local head = part.CFrame * CFrame.new(0, part.Size.Y / 2 + 0.8, 0)
		deco(part, Vector3.new(1.4, 1.6, 1.4), head, Color3.fromRGB(255, 200, 110), Enum.Material.Neon)
		deco(
			part,
			Vector3.new(1.1, 0.3, 1.1),
			head * CFrame.new(0, -0.95, 0),
			Color3.fromRGB(70, 75, 85),
			Enum.Material.Metal
		)
		sparkles(part, Color3.fromRGB(255, 210, 120), 2)
		deco(
			part,
			Vector3.new(1.8, 0.3, 1.8),
			head * CFrame.new(0, 0.95, 0),
			Color3.fromRGB(70, 75, 85),
			Enum.Material.Metal
		)
	elseif name == "Flag" then
		-- White pole down the cloth's edge to the ground.
		local h = part.Size.Y * 2
		deco(
			part,
			Vector3.new(0.3, h, 0.3),
			part.CFrame * CFrame.new(-part.Size.X / 2 - 0.15, part.Size.Y / 2 - h / 2, 0),
			Color3.fromRGB(235, 235, 240),
			Enum.Material.Metal
		)
	elseif name == "Pumpkin" then
		deco(
			part,
			Vector3.new(0.4, 0.8, 0.4),
			part.CFrame * CFrame.new(0, part.Size.Y / 2 + 0.2, 0),
			Color3.fromRGB(110, 75, 35)
		)
		local glow = Color3.fromRGB(255, 220, 90)
		local face = part.CFrame * CFrame.new(0, 0, -part.Size.Z / 2 + 0.25)
		for _, side in { -1, 1 } do
			deco(
				part,
				Vector3.new(0.8, 0.8, 0.6),
				face * CFrame.new(side * 0.9, 0.6, 0) * CFrame.Angles(0, 0, math.rad(45)),
				glow,
				Enum.Material.Neon
			)
		end
		deco(part, Vector3.new(2.2, 0.5, 0.6), face * CFrame.new(0, -0.8, 0), glow, Enum.Material.Neon)
	elseif name == "SunBlock" or name == "MoonBlock" then
		local sun = name == "SunBlock"
		part.Color = if sun then Color3.fromRGB(255, 195, 40) else Color3.fromRGB(50, 80, 200)
		skin(part, if sun then TEX.sun else TEX.moon)
		sparkles(part, if sun then Color3.fromRGB(255, 230, 120) else Color3.fromRGB(255, 240, 180), 2)
	end
end

return PieceVisuals

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

-- Four glowing strips around the top edge of a pad.
local function frame(part: BasePart, color: Color3)
	local top = part.CFrame * CFrame.new(0, part.Size.Y / 2 + 0.05, 0)
	local sx, sz = part.Size.X, part.Size.Z
	for _, e in
		{
			{ Vector3.new(sx, 0.2, 0.5), CFrame.new(0, 0, sz / 2 - 0.25) },
			{ Vector3.new(sx, 0.2, 0.5), CFrame.new(0, 0, -sz / 2 + 0.25) },
			{ Vector3.new(0.5, 0.2, sz - 1), CFrame.new(sx / 2 - 0.25, 0, 0) },
			{ Vector3.new(0.5, 0.2, sz - 1), CFrame.new(-sx / 2 + 0.25, 0, 0) },
		}
	do
		deco(part, e[1], top * e[2], color, Enum.Material.Neon)
	end
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

-- Darker strips on all 12 edges: the bevel and outline of the icon art. They fade
-- with the piece (crumble, day/night ghosts).
-- ponytail: 12 extra parts per bevelled piece; swap to a bevelled MeshPart if part count hurts.
local function bevel(part: BasePart)
	local s = part.Size
	local t = 0.5
	local color = part.Color:Lerp(DARK, 0.45)
	for axis = 1, 3 do
		for _, a in { -1, 1 } do
			for _, b in { -1, 1 } do
				local size, offset
				if axis == 1 then
					size = Vector3.new(s.X + 0.06, t, t)
					offset = Vector3.new(0, a * (s.Y - t) / 2 + a * 0.03, b * (s.Z - t) / 2 + b * 0.03)
				elseif axis == 2 then
					size = Vector3.new(t, s.Y + 0.06, t)
					offset = Vector3.new(a * (s.X - t) / 2 + a * 0.03, 0, b * (s.Z - t) / 2 + b * 0.03)
				else
					size = Vector3.new(t, t, s.Z + 0.06)
					offset = Vector3.new(a * (s.X - t) / 2 + a * 0.03, b * (s.Y - t) / 2 + b * 0.03, 0)
				end
				local strip = deco(part, size, part.CFrame * CFrame.new(offset), color)
				strip.Name = "Bevel"
			end
		end
	end
	part:GetPropertyChangedSignal("Transparency"):Connect(function()
		for _, c in part:GetChildren() do
			if c.Name == "Bevel" and c:IsA("BasePart") then
				c.Transparency = part.Transparency
			end
		end
	end)
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
		part.Material = Enum.Material.Slate
		bevel(part)
	elseif name == "Wall" or name == "FakeWall" or name == "OneWay" then
		part.Color = BRICK
		part.Material = Enum.Material.Brick -- the tower material cosmetic may override it
		bevel(part)
	elseif name == "Platform" then
		part.Color = BLUE
		bevel(part)
	elseif name == "BigFloor" then
		part.Color = Color3.fromRGB(120, 190, 240)
		bevel(part)
		-- 3x3 tile grooves on top
		local line = part.Color:Lerp(DARK, 0.3)
		for _, k in { -1, 1 } do
			deco(part, Vector3.new(0.2, 0.06, part.Size.Z), top * CFrame.new(k * part.Size.X / 6, 0, 0), line)
			deco(part, Vector3.new(part.Size.X, 0.06, 0.2), top * CFrame.new(0, 0, k * part.Size.Z / 6), line)
		end
	elseif name == "Ramp" then
		part.Color = WOOD
		part.Material = Enum.Material.WoodPlanks
	elseif name == "Crumble" then
		part.Color = Color3.fromRGB(205, 165, 105)
		part.Material = Enum.Material.Sandstone
		bevel(part)
		local crack = Color3.fromRGB(110, 80, 45)
		deco(part, Vector3.new(0.18, 0.06, part.Size.Z * 0.8), top * CFrame.Angles(0, 0.3, 0), crack)
		deco(part, Vector3.new(part.Size.X * 0.7, 0.06, 0.18), top * CFrame.Angles(0, -0.2, 0), crack)
	elseif name == "JumpPad" then
		-- Grey base, glowing orange top plate with an arrow.
		part.Color = Color3.fromRGB(110, 115, 128)
		part.Material = Enum.Material.Metal
		local plate = part.CFrame * CFrame.new(0, part.Size.Y / 2 + 0.1, 0)
		deco(part, Vector3.new(part.Size.X - 0.5, 0.2, part.Size.Z - 0.5), plate, Color3.fromRGB(235, 95, 0))
		local arrow = Color3.fromRGB(255, 240, 200)
		chevron(part, plate * CFrame.new(0, 0.1, -0.9), arrow, 1.2)
		deco(part, Vector3.new(0.6, 0.15, 2.4), plate * CFrame.new(0, 0.1, 0.6), arrow, Enum.Material.Neon)
		sparkles(part, Color3.fromRGB(255, 200, 90), 3)
	elseif name == "Teleporter" then
		-- Purple pad with a glowing swirl disc and a faint light column.
		local color = channelColor or Color3.fromRGB(170, 85, 255)
		part.Color = color:Lerp(DARK, 0.5)
		part.Material = Enum.Material.SmoothPlastic
		part.Size = Vector3.new(part.Size.X, 0.6, part.Size.Z)
		part.CFrame -= Vector3.new(0, (G - 0.6) / 2, 0)
		local pad = part.CFrame * CFrame.new(0, 0.35, 0)
		disc(part, G - 0.8, 0.12, pad, color, Enum.Material.Neon)
		disc(part, G - 2, 0.14, pad, color:Lerp(Color3.new(1, 1, 1), 0.5), Enum.Material.Neon)
		disc(part, G - 3, 0.16, pad, color, Enum.Material.Neon)
		disc(part, G - 1, G - 0.6, pad * CFrame.new(0, (G - 0.6) / 2, 0), color, Enum.Material.Neon).Transparency =
			0.85
		sparkles(part, color, 8)
	elseif name == "Finish" then
		-- Glowing green pad, light beam and a big green flag.
		part.Color = Color3.fromRGB(40, 60, 50)
		part.Material = Enum.Material.SmoothPlastic
		frame(part, Color3.fromRGB(60, 255, 120))
		local beam = deco(
			part,
			Vector3.new(part.Size.X - 1, 18, part.Size.Z - 1),
			part.CFrame * CFrame.new(0, part.Size.Y / 2 + 9, 0),
			Color3.fromRGB(90, 255, 140),
			Enum.Material.Neon
		)
		beam.Transparency = 0.82
		pole(part, Color3.fromRGB(60, 200, 80), 1.8)
		sparkles(part, Color3.fromRGB(120, 255, 160), 8)
	elseif name == "Checkpoint" then
		pole(part, Color3.fromRGB(0, 210, 220))
	elseif name == "Conveyor" then
		-- Dark belt, yellow side rails, glowing chevrons pointing the way it carries you.
		local alongX = r % 2 == 1
		for _, side in { -1, 1 } do
			local offset = if alongX
				then CFrame.new(0, part.Size.Y / 2 + 0.3, side * (part.Size.Z / 2 - 0.2))
				else CFrame.new(side * (part.Size.X / 2 - 0.2), part.Size.Y / 2 + 0.3, 0)
			local size = if alongX
				then Vector3.new(part.Size.X, 0.6, 0.4)
				else Vector3.new(0.4, 0.6, part.Size.Z)
			deco(part, size, part.CFrame * offset, Color3.fromRGB(255, 200, 40), Enum.Material.Metal)
		end
		local facing = CFrame.new(top.Position + Vector3.new(0, 0.05, 0))
			* CFrame.Angles(0, r * math.pi / 2, 0)
		for _, z in { -2.2, 0, 2.2 } do
			chevron(part, facing * CFrame.new(0, 0, z), Color3.fromRGB(255, 200, 40), 1)
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
		local s = part.Size
		for _, side in { -1, 1 } do
			deco(
				part,
				Vector3.new(0.5, s.Y + 0.2, s.Z + 0.3),
				part.CFrame * CFrame.new(side * (s.X / 2 + 0.1), 0.1, 0),
				color
			)
		end
		deco(
			part,
			Vector3.new(s.X + 0.7, 0.5, s.Z + 0.3),
			part.CFrame * CFrame.new(0, s.Y / 2 + 0.2, 0),
			color
		)
	elseif name == "Plant" then
		deco(
			part,
			Vector3.new(G - 0.4, 0.4, G - 0.4),
			part.CFrame * CFrame.new(0, -G / 2 + 0.2, 0),
			Color3.fromRGB(80, 140, 60)
		)
	elseif name == "Lamp" then
		-- Grey post with a glowing lantern on top.
		part.Color = Color3.fromRGB(120, 125, 135)
		part.Material = Enum.Material.Metal
		local head = part.CFrame * CFrame.new(0, part.Size.Y / 2 - 0.9, 0)
		deco(part, Vector3.new(1.4, 1.4, 1.4), head, Color3.fromRGB(255, 200, 110), Enum.Material.Neon)
		deco(
			part,
			Vector3.new(1.8, 0.3, 1.8),
			head * CFrame.new(0, 0.85, 0),
			Color3.fromRGB(90, 95, 105),
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
		bevel(part)
		-- A sun (disc) or crescent (disc with a block-coloured bite) on each side face.
		local symbol = if sun then Color3.fromRGB(255, 240, 150) else Color3.fromRGB(255, 225, 130)
		for i = 0, 3 do
			local face = part.CFrame
				* CFrame.Angles(0, i * math.pi / 2, 0)
				* CFrame.new(0, 0, -part.Size.Z / 2 - 0.04)
			disc(part, 2.4, 0.06, face * CFrame.Angles(math.pi / 2, 0, 0), symbol, Enum.Material.Neon).Name =
				"Bevel"
			if not sun then
				local bite = face * CFrame.new(0.7, 0.4, -0.03) * CFrame.Angles(math.pi / 2, 0, 0)
				disc(part, 2.1, 0.06, bite, part.Color).Name = "Bevel"
			end
		end
	end
end

return PieceVisuals

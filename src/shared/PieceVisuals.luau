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

-- One stretched decal per face; they fade with the piece (crumble, day/night ghosts).
local function skin(part: BasePart, image: string, faces: { Enum.NormalId }?)
	for _, face in faces or Enum.NormalId:GetEnumItems() :: { Enum.NormalId } do
		local d = Instance.new("Decal")
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

local FLAT = { Enum.NormalId.Top, Enum.NormalId.Bottom }

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
					* CFrame.new(0, 0, side * (part.Size.Z / 2 + 0.05))
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
		skin(part, TEX.platform, FLAT)
	elseif name == "BigFloor" then
		part.Color = Color3.fromRGB(120, 190, 240)
		skin(part, TEX.tiles, FLAT)
	elseif name == "Ramp" then
		part.Color = WOOD
		skin(part, TEX.wood, { Enum.NormalId.Top, Enum.NormalId.Back })
	elseif name == "Crumble" then
		part.Color = Color3.fromRGB(205, 165, 105)
		skin(part, TEX.crumble, FLAT)
		debris(part)
	elseif name == "JumpPad" then
		-- Grey base, glowing orange top plate with an arrow.
		part.Color = Color3.fromRGB(110, 115, 128)
		part.Material = Enum.Material.Metal
		local plate = part.CFrame * CFrame.new(0, part.Size.Y / 2 + 0.1, 0)
		deco(part, Vector3.new(part.Size.X - 0.5, 0.2, part.Size.Z - 0.5), plate, Color3.fromRGB(235, 95, 0))
		local arrow = Color3.fromRGB(255, 210, 120)
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
		deco(
			part,
			Vector3.new(G * 1.2, G * 0.8, 0.15),
			base * CFrame.new(G * 0.62, h - G * 0.45, 0),
			Color3.fromRGB(60, 200, 70),
			Enum.Material.Fabric
		)
		sparkles(part, Color3.fromRGB(120, 255, 160), 8)
	elseif name == "Checkpoint" then
		pole(part, Color3.fromRGB(0, 210, 220))
		sparkles(part, Color3.fromRGB(120, 255, 255), 3)
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
		sparkles(part, Color3.fromRGB(255, 210, 120), 2)
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
		skin(part, if sun then TEX.sun else TEX.moon)
		sparkles(part, if sun then Color3.fromRGB(255, 230, 120) else Color3.fromRGB(255, 240, 180), 2)
	end
end

return PieceVisuals

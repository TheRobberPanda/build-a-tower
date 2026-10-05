--!strict
-- Looks for placed pieces. Gameplay shape/collision stays on the main part
-- (PlotService); this only recolours it and adds decoration children that never
-- collide, touch or block raycasts.

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local PieceVisuals = {}

local G = Config.GRID_STUDS
local TILE = "rbxassetid://139861751774533" -- assets/ui/grid_cell.png (white cell outline)

-- Structural colour shifts with height so a tower reads as a colourful climb.
-- Fake walls and one-way walls use the same colour as blocks at that height.
local BANDS = {
	Color3.fromRGB(40, 120, 255), -- blue
	Color3.fromRGB(255, 140, 30), -- orange
	Color3.fromRGB(255, 205, 40), -- yellow
	Color3.fromRGB(60, 200, 90), -- green
	Color3.fromRGB(235, 60, 75), -- red
	Color3.fromRGB(150, 80, 240), -- purple
}
PieceVisuals.BANDS = BANDS

function PieceVisuals.heightColor(y: number): Color3
	-- Vivid colour bands, a new colour every 4 rows (matches the core's rings).
	return BANDS[(y // 4) % #BANDS + 1]
end

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

-- White cell outlines on every face: the blocky "obby" look.
local function tiles(part: BasePart, transparency: number)
	for _, face in Enum.NormalId:GetEnumItems() do
		local t = Instance.new("Texture")
		t.Texture = TILE
		t.Face = face
		t.StudsPerTileU = G
		t.StudsPerTileV = G
		t.Transparency = transparency
		t.Color3 = Color3.fromRGB(30, 30, 40) -- dark cell edges
		t.Parent = part
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

local function pole(part: BasePart, flagColor: Color3)
	local top = part.CFrame * CFrame.new(-part.Size.X / 2 + 0.4, part.Size.Y / 2, -part.Size.Z / 2 + 0.4)
	deco(
		part,
		Vector3.new(0.3, 5, 0.3),
		top * CFrame.new(0, 2.5, 0),
		Color3.fromRGB(230, 230, 235),
		Enum.Material.Metal
	)
	deco(part, Vector3.new(0.1, 1.6, 2.4), top * CFrame.new(0, 4.1, 1.25), flagColor, Enum.Material.Fabric)
end

local function ring(part: BasePart, color: Color3, height: number)
	local d = math.min(part.Size.X, part.Size.Z) * 0.85
	deco(
		part,
		Vector3.new(0.3, d, d),
		part.CFrame * CFrame.new(0, part.Size.Y / 2 + height, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		Enum.Material.Neon
	).Shape =
		Enum.PartType.Cylinder
end

-- name = piece type name; y/r = grid row and rotation; channelColor for linked pieces.
function PieceVisuals.decorate(part: BasePart, name: string, y: number, r: number, channelColor: Color3?)
	if name == "Block" or name == "FakeWall" or name == "OneWay" then
		part.Color = PieceVisuals.heightColor(y)
		tiles(part, 0.35)
	elseif name == "Platform" then
		part.Color = PieceVisuals.heightColor(y):Lerp(Color3.new(1, 1, 1), 0.25)
		tiles(part, 0.45)
	elseif name == "Ramp" then
		part.Color = PieceVisuals.heightColor(y):Lerp(Color3.fromRGB(255, 200, 120), 0.35)
	elseif name == "Crumble" then
		part.Color = Color3.fromRGB(176, 138, 96)
		tiles(part, 0.6)
	elseif name == "JumpPad" then
		part.Color = Color3.fromRGB(60, 60, 70)
		part.Material = Enum.Material.SmoothPlastic
		ring(part, Color3.fromRGB(255, 190, 40), 0.05)
		sparkles(part, Color3.fromRGB(255, 210, 80), 4)
	elseif name == "Teleporter" then
		local color = channelColor or Color3.fromRGB(170, 85, 255)
		part.Color = Color3.fromRGB(40, 40, 55)
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = 0
		ring(part, color, 0.05)
		ring(part, color, 2).Transparency = 0.5
		sparkles(part, color, 10)
	elseif name == "Finish" then
		part.Color = Color3.fromRGB(0, 200, 90)
		pole(part, Color3.fromRGB(255, 255, 255))
		sparkles(part, Color3.fromRGB(120, 255, 160), 8)
	elseif name == "Checkpoint" then
		pole(part, Color3.fromRGB(0, 210, 220))
	elseif name == "Conveyor" then
		-- Side rails along the belt direction (rotation 0/2 runs along Z, 1/3 along X).
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
	elseif name == "Button" then
		local base = part.CFrame * CFrame.new(0, -part.Size.Y / 2 - 0.1, 0)
		deco(
			part,
			Vector3.new(part.Size.X + 1, 0.3, part.Size.Z + 1),
			base,
			Color3.fromRGB(90, 90, 100),
			Enum.Material.Metal
		)
	elseif name == "Door" then
		tiles(part, 0.7)
	end
end

return PieceVisuals

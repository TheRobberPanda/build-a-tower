--!strict
-- Looks for placed pieces. Gameplay shape/collision stays on the main part
-- (PlotService); this only recolours it and adds decoration children that never
-- collide, touch or block raycasts.

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local PieceVisuals = {}

local G = Config.GRID_STUDS

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

-- name = piece type name; y/r = grid row and rotation; channelColor for linked pieces.
function PieceVisuals.decorate(part: BasePart, name: string, y: number, r: number, channelColor: Color3?)
	if name == "Block" or name == "FakeWall" or name == "OneWay" then
		part.Color = PieceVisuals.heightColor(y)
	elseif name == "Platform" then
		part.Color = PieceVisuals.heightColor(y):Lerp(Color3.new(1, 1, 1), 0.25)
	elseif name == "Ramp" then
		part.Color = PieceVisuals.heightColor(y):Lerp(Color3.fromRGB(255, 200, 120), 0.35)
	elseif name == "Crumble" then
		part.Color = Color3.fromRGB(176, 138, 96)
	elseif name == "JumpPad" then
		-- Dark square pad with a glowing yellow frame (like the reference art).
		part.Color = Color3.fromRGB(70, 74, 86)
		part.Material = Enum.Material.SmoothPlastic
		frame(part, Color3.fromRGB(255, 200, 40))
		sparkles(part, Color3.fromRGB(255, 220, 90), 3)
	elseif name == "Teleporter" then
		-- A glowing archway: two posts, a lintel and a translucent portal pane.
		local color = channelColor or Color3.fromRGB(170, 85, 255)
		part.Color = Color3.fromRGB(60, 50, 80)
		part.Material = Enum.Material.SmoothPlastic
		part.Size = Vector3.new(part.Size.X, 0.6, part.Size.Z)
		part.CFrame -= Vector3.new(0, (G - 0.6) / 2, 0)
		local base = part.CFrame
		local h = G - 0.6
		for _, side in { -1, 1 } do
			deco(
				part,
				Vector3.new(0.6, h, 0.6),
				base * CFrame.new(side * (G / 2 - 0.5), 0.3 + h / 2, 0),
				color:Lerp(Color3.new(1, 1, 1), 0.2)
			)
		end
		deco(
			part,
			Vector3.new(G - 0.4, 0.6, 0.6),
			base * CFrame.new(0, 0.3 + h - 0.3, 0),
			color:Lerp(Color3.new(1, 1, 1), 0.2)
		)
		local pane = deco(
			part,
			Vector3.new(G - 1.6, h - 0.6, 0.2),
			base * CFrame.new(0, 0.3 + (h - 0.6) / 2, 0),
			color,
			Enum.Material.Neon
		)
		pane.Transparency = 0.35
		sparkles(part, color, 8)
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
	end
end

return PieceVisuals

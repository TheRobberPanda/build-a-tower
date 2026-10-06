--!strict
-- Builds the part for one tower piece: gameplay shape, collision, attributes and
-- tags, then the looks from PieceVisuals. No service state, so Edit-mode previews
-- (tools/preview_plot.luau) use exactly what the game uses.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PieceDefs = require(ReplicatedStorage.Shared.PieceDefs)
local TowerCodec = require(ReplicatedStorage.Shared.TowerCodec)
local Types = require(ReplicatedStorage.Shared.Types)
local PieceVisuals = require(script.Parent.PieceVisuals)

type Piece = Types.Piece

local PieceFactory = {}

local function child(root: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = root.CFrame * offset
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = root
	return p
end

local ORANGE = Color3.fromRGB(255, 140, 30)
local BLUE = Color3.fromRGB(40, 120, 255)
local YELLOW = Color3.fromRGB(255, 205, 40)

-- Premade pieces, built in the root's local space (length along local Z, rising toward +Z).
local COMPOUND: { [string]: (BasePart) -> () } = {
	Stairs = function(root)
		local size = root.Size
		local steps = 8
		local run, rise = size.Z / steps, size.Y / steps
		for i = 1, steps do
			local h = rise * i
			child(
				root,
				"Stairs",
				Vector3.new(size.X, h, run),
				CFrame.new(0, -size.Y / 2 + h / 2, -size.Z / 2 + run * (i - 0.5)),
				if i % 2 == 0 then ORANGE else ORANGE:Lerp(YELLOW, 0.3)
			)
		end
	end,
	Beam = function(root)
		local size = root.Size
		child(root, "Beam", Vector3.new(size.X, 1.2, size.Z), CFrame.new(0, size.Y / 2 - 0.6, 0), BLUE)
		child(
			root,
			"BeamTrim",
			Vector3.new(size.X - 0.6, 0.4, size.Z - 0.6),
			CFrame.new(0, size.Y / 2 - 1.4, 0),
			YELLOW
		)
	end,
	LongRamp = function(root)
		local size = root.Size
		local length = math.sqrt(size.Z ^ 2 + (size.Y - 1) ^ 2)
		local angle = math.atan2(size.Y - 1, size.Z)
		child(root, "LongRamp", Vector3.new(size.X, 1, length), CFrame.Angles(-angle, 0, 0), ORANGE) -- rises toward +Z
	end,
}

local INSET = {
	Block = true,
	Platform = true,
	BigFloor = true,
	Wall = true,
	FakeWall = true,
	OneWay = true,
	Crumble = true,
	Door = true,
}

local COLORS: { [string]: Color3 } = {
	Block = Color3.fromRGB(163, 162, 165),
	Platform = Color3.fromRGB(110, 153, 202),
	Ramp = Color3.fromRGB(196, 140, 98),
	JumpPad = Color3.fromRGB(255, 176, 0),
	Teleporter = Color3.fromRGB(170, 85, 255),
	FakeWall = Color3.fromRGB(163, 162, 165), -- looks like a Block on purpose
	InvisiblePlatform = Color3.fromRGB(255, 255, 255),
	Finish = Color3.fromRGB(0, 200, 90),
	Crumble = Color3.fromRGB(181, 140, 90),
	Conveyor = Color3.fromRGB(60, 60, 70),
	OneWay = Color3.fromRGB(163, 162, 165), -- looks like a wall
	Button = Color3.fromRGB(230, 60, 60),
	Door = Color3.fromRGB(150, 100, 60),
	Checkpoint = Color3.fromRGB(0, 190, 200),
	Plant = Color3.fromRGB(70, 160, 70),
	Lamp = Color3.fromRGB(255, 220, 140),
	Flag = Color3.fromRGB(230, 60, 60),
	Pumpkin = Color3.fromRGB(255, 130, 20),
	Stairs = Color3.fromRGB(255, 140, 30),
	Beam = Color3.fromRGB(40, 120, 255),
	BigFloor = Color3.fromRGB(110, 153, 202),
	Wall = Color3.fromRGB(163, 162, 165),
	LongRamp = Color3.fromRGB(255, 140, 30),
}

local TELEPORTER_COLORS: { Color3 } = {
	Color3.fromRGB(170, 85, 255),
	Color3.fromRGB(0, 170, 255),
	Color3.fromRGB(255, 85, 170),
	Color3.fromRGB(255, 255, 85),
}

function PieceFactory.make(piece: Piece, origin: Vector3): BasePart
	local def = PieceDefs.byId[piece.t]
	local sx, sy, sz = TowerCodec.extent(piece)
	local g = Config.GRID_STUDS
	local part: BasePart = if def.name == "Ramp" then Instance.new("WedgePart") else Instance.new("Part")
	-- Ramps and premades are sized before rotation and turned with the CFrame.
	local turned = def.name == "Ramp" or COMPOUND[def.name] ~= nil
	part.Size = if turned
		then Vector3.new(def.size[1], def.size[2], def.size[3]) * g
		else Vector3.new(sx, sy, sz) * g
	local center = origin + Vector3.new(piece.x + sx / 2, piece.y + sy / 2, piece.z + sz / 2) * g
	part.CFrame = CFrame.new(center) * CFrame.Angles(0, if turned then piece.r * math.pi / 2 else 0, 0)
	part.Anchored = true
	part.Color = COLORS[def.name]
	part.Name = def.name
	part.TopSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("PieceType", piece.t)
	if piece.p then
		for k, v in piece.p do
			part:SetAttribute(k, v)
		end
	end
	if def.name == "FakeWall" then
		part.CanCollide = false
	elseif def.name == "InvisiblePlatform" then
		part.Transparency = 1
	elseif def.name == "JumpPad" or def.name == "Finish" or def.name == "Teleporter" then
		part.Material = Enum.Material.Neon
	end
	if def.name == "Teleporter" then
		local ch = piece.p and piece.p.ch or 1
		part.Color = TELEPORTER_COLORS[ch] or part.Color -- linked pairs share a colour
	elseif def.name == "JumpPad" then
		local power = piece.p and piece.p.power or 1
		part.Size = Vector3.new(part.Size.X, part.Size.Y * (0.25 + 0.15 * power), part.Size.Z) -- taller = stronger
		part.Position -= Vector3.new(0, (Config.GRID_STUDS - part.Size.Y) / 2, 0)
	end
	if def.name == "Crumble" then
		part.Material = Enum.Material.Slate
	elseif def.name == "Conveyor" then
		part.Material = Enum.Material.DiamondPlate
		-- Anchored parts with velocity carry whatever stands on them. Direction follows rotation.
		local dir = CFrame.Angles(0, piece.r * math.pi / 2, 0).LookVector
		part.AssemblyLinearVelocity = dir * Config.CONVEYOR_SPEED
		part:SetAttribute("Dir", dir)
	elseif def.name == "OneWay" then
		part:SetAttribute("Dir", CFrame.Angles(0, piece.r * math.pi / 2, 0).LookVector) -- direction you may pass
	elseif def.name == "Button" then
		part.Size = Vector3.new(part.Size.X * 0.6, part.Size.Y * 0.3, part.Size.Z * 0.6)
		part.Position -= Vector3.new(0, (Config.GRID_STUDS - part.Size.Y) / 2, 0)
		part.Material = Enum.Material.Neon
	elseif def.name == "Door" then
		part.Material = Enum.Material.WoodPlanks
	elseif def.decor then
		part.CanCollide = false
		part.CanTouch = false
		part.CastShadow = false
		if def.name == "Plant" then
			part.Shape = Enum.PartType.Ball
			part.Material = Enum.Material.Grass
		elseif def.name == "Lamp" then
			part.Size = Vector3.new(part.Size.X * 0.3, part.Size.Y, part.Size.Z * 0.3)
			part.Material = Enum.Material.Neon
			local light = Instance.new("PointLight")
			light.Range = 14
			light.Brightness = 1.5
			light.Color = part.Color
			light.Parent = part
		elseif def.name == "Pumpkin" then
			part.Shape = Enum.PartType.Ball
			part.Material = Enum.Material.SmoothPlastic
			local glow = Instance.new("PointLight")
			glow.Range = 8
			glow.Color = Color3.fromRGB(255, 160, 60)
			glow.Parent = part
		elseif def.name == "Flag" then
			part.Size = Vector3.new(part.Size.X * 0.9, part.Size.Y * 0.5, 0.3)
			part.Position += Vector3.new(0, Config.GRID_STUDS / 2, 0)
			part.Material = Enum.Material.Fabric
			local ch = piece.p and piece.p.ch or 1
			part.Color = TELEPORTER_COLORS[ch] or part.Color
		end
	elseif def.name == "Checkpoint" then
		part.Size = Vector3.new(part.Size.X, part.Size.Y * 0.25, part.Size.Z)
		part.Position -= Vector3.new(0, (Config.GRID_STUDS - part.Size.Y) / 2, 0)
		part.Material = Enum.Material.Neon
	end
	if def.name == "Button" or def.name == "Door" then
		local ch = piece.p and piece.p.ch or 1
		part.Color = TELEPORTER_COLORS[ch] or part.Color -- button and its doors share a colour
	end
	local build = COMPOUND[def.name]
	if build then
		-- The root is an invisible box; solid, visible children do the work.
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		build(part)
	end
	-- Small gaps between neighbouring blocks outline them (a 0.12 stud inset per side).
	if INSET[def.name] then
		part.Size -= Vector3.new(0.24, 0.24, 0.24)
	end
	local ch = piece.p and piece.p.ch
	PieceVisuals.decorate(part, def.name, piece.y, piece.r, if ch then TELEPORTER_COLORS[ch] else nil)
	if
		def.name == "JumpPad"
		or def.name == "Teleporter"
		or def.name == "FakeWall"
		or def.name == "InvisiblePlatform"
		or def.name == "Crumble"
		or def.name == "Conveyor"
		or def.name == "OneWay"
		or def.name == "Button"
	then
		CollectionService:AddTag(part, def.name) -- MechanicsService / client controller pick these up
	end
	return part
end

PieceFactory.CHANNEL_COLORS = TELEPORTER_COLORS

return PieceFactory

--!strict
-- One plot per player. Renders a tower's pieces as parts on the plot.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PieceDefs = require(ReplicatedStorage.Shared.PieceDefs)
local TowerCodec = require(ReplicatedStorage.Shared.TowerCodec)
local Types = require(ReplicatedStorage.Shared.Types)

type Piece = Types.Piece

local PlotService = {}

local PLOT_SPACING = 200
local APRON_DEPTH = 16
local GRID_TEXTURE = "rbxassetid://139861751774533" -- assets/ui/grid_cell.png
local plotsFolder = Instance.new("Folder")
plotsFolder.Name = "Plots"

type Plot = { slot: number, origin: Vector3, model: Model }
local plots: { [Player]: Plot } = {}

local function freeSlot(): number
	local used: { [number]: boolean } = {}
	for _, plot in plots do
		used[plot.slot] = true
	end
	local slot = 0
	while used[slot] do
		slot += 1
	end
	return slot
end

local COLORS: { [string]: Color3 } = {
	Block = Color3.fromRGB(163, 162, 165),
	Platform = Color3.fromRGB(110, 153, 202),
	Ramp = Color3.fromRGB(196, 140, 98),
	JumpPad = Color3.fromRGB(255, 176, 0),
	Teleporter = Color3.fromRGB(170, 85, 255),
	FakeWall = Color3.fromRGB(163, 162, 165), -- looks like a Block on purpose
	InvisiblePlatform = Color3.fromRGB(255, 255, 255),
	Finish = Color3.fromRGB(0, 200, 90),
}

local TELEPORTER_COLORS: { Color3 } = {
	Color3.fromRGB(170, 85, 255),
	Color3.fromRGB(0, 170, 255),
	Color3.fromRGB(255, 85, 170),
	Color3.fromRGB(255, 255, 85),
}

local function makePart(piece: Piece, origin: Vector3): BasePart
	local def = PieceDefs.byId[piece.t]
	local sx, sy, sz = TowerCodec.extent(piece)
	local g = Config.GRID_STUDS
	local part: BasePart = if def.name == "Ramp" then Instance.new("WedgePart") else Instance.new("Part")
	-- WedgePart size is defined before rotation, so use the unrotated def size
	part.Size = if def.name == "Ramp"
		then Vector3.new(def.size[1], def.size[2], def.size[3]) * g
		else Vector3.new(sx, sy, sz) * g
	local center = origin + Vector3.new(piece.x + sx / 2, piece.y + sy / 2, piece.z + sz / 2) * g
	part.CFrame = CFrame.new(center)
		* CFrame.Angles(0, if def.name == "Ramp" then piece.r * math.pi / 2 else 0, 0)
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
	if def.name == "JumpPad" or def.name == "Teleporter" then
		CollectionService:AddTag(part, def.name) -- MechanicsService / client controller pick these up
	end
	return part
end

function PlotService.get(player: Player): Plot?
	return plots[player]
end

function PlotService.spawnCFrame(player: Player): CFrame?
	local plot = plots[player]
	if not plot then
		return nil
	end
	local g = Config.GRID_STUDS
	-- On the apron, facing the tower
	local pos = plot.origin + Vector3.new(Config.PLOT_CELLS_X * g / 2, 3, -APRON_DEPTH / 2)
	return CFrame.lookAt(pos, pos + Vector3.zAxis)
end

-- Clears the plot and builds `pieces` on it.
function PlotService.render(player: Player, pieces: { Piece })
	local plot = plots[player]
	if not plot then
		return
	end
	local container = plot.model:FindFirstChild("Pieces")
	if container then
		container:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Pieces"
	for _, piece in pieces do
		makePart(piece, plot.origin).Parent = folder
	end
	folder.Parent = plot.model
end

local function onPlayerAdded(player: Player)
	local slot = freeSlot()
	local g = Config.GRID_STUDS
	local origin = Vector3.new(slot * PLOT_SPACING, 0, 0)
	local model = Instance.new("Model")
	model.Name = "Plot_" .. player.UserId
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("Origin", origin) -- clients convert world <-> grid with this
	-- Base covers exactly the buildable grid; the apron in front is where runs start.
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Anchored = true
	base.Size = Vector3.new(Config.PLOT_CELLS_X * g, 1, Config.PLOT_CELLS_Z * g)
	base.Position = origin + Vector3.new(Config.PLOT_CELLS_X * g / 2, -0.5, Config.PLOT_CELLS_Z * g / 2)
	base.Color = Color3.fromRGB(80, 140, 90)
	base.Material = Enum.Material.SmoothPlastic
	base.TopSurface = Enum.SurfaceType.Smooth
	local grid = Instance.new("Texture")
	grid.Texture = GRID_TEXTURE
	grid.Face = Enum.NormalId.Top
	grid.StudsPerTileU = g
	grid.StudsPerTileV = g
	grid.Parent = base
	base.Parent = model
	local apron = Instance.new("Part")
	apron.Name = "Apron"
	apron.Anchored = true
	apron.Size = Vector3.new(Config.PLOT_CELLS_X * g, 1, APRON_DEPTH)
	apron.Position = origin + Vector3.new(Config.PLOT_CELLS_X * g / 2, -0.5, -APRON_DEPTH / 2)
	apron.Color = Color3.fromRGB(90, 95, 110)
	apron.Material = Enum.Material.SmoothPlastic
	apron.TopSurface = Enum.SurfaceType.Smooth
	apron.Parent = model
	model.Parent = plotsFolder
	plots[player] = { slot = slot, origin = origin, model = model }

	-- Everyone spawns at their own plot.
	local function onCharacter(character: Model)
		task.defer(function()
			local cf = PlotService.spawnCFrame(player)
			if cf and character.Parent then
				character:PivotTo(cf)
			end
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	local plot = plots[player]
	if plot then
		plot.model:Destroy()
		plots[player] = nil
	end
end

function PlotService.init()
	plotsFolder.Parent = workspace
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		onPlayerAdded(p)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return PlotService

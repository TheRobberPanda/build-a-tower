--!strict
-- One plot per player. Renders a tower's pieces as parts on the plot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local PieceFactory = require(game:GetService("ReplicatedStorage").Shared.PieceFactory)
local PlotBuilder = require(script.Parent.PlotBuilder)
local Types = require(ReplicatedStorage.Shared.Types)

type Piece = Types.Piece

local PlotService = {}

local PLOT_SPACING = 200
local APRON_DEPTH = 16
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

-- During a run, respawn here instead of the plot spawn (nil = plot spawn).
local respawnAt: { [Player]: CFrame } = {}
function PlotService.setRespawn(player: Player, cf: CFrame?)
	respawnAt[player] = cf
end

-- VIP plot theme: recolours the plot base.
function PlotService.setTheme(player: Player, color: Color3, material: Enum.Material)
	local plot = plots[player]
	local base = plot and plot.model:FindFirstChild("Base")
	if base and base:IsA("BasePart") then
		base.Color = color
		base.Material = material
	end
end

function PlotService.respawnFor(player: Player): CFrame?
	return respawnAt[player]
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

local function pieceKey(piece: Piece): string
	local key = string.format("%d,%d,%d,%d,%d", piece.t, piece.x, piece.y, piece.z, piece.r)
	if piece.p then
		local names = {}
		for k in piece.p do
			table.insert(names, k)
		end
		table.sort(names)
		for _, k in names do
			key ..= string.format(",%s=%d", k, piece.p[k])
		end
	end
	return key
end

-- Makes the plot show exactly `pieces`. Only changed parts are destroyed or
-- created, so an edit replicates one part instead of the whole tower.
function PlotService.render(player: Player, pieces: { Piece }, mat: string?)
	local plot = plots[player]
	if not plot then
		return
	end
	local folder = plot.model:FindFirstChild("Pieces")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Pieces"
		folder.Parent = plot.model
	end
	assert(folder, "Pieces folder")
	local wanted: { [string]: Piece } = {}
	for _, piece in pieces do
		wanted[pieceKey(piece)] = piece
	end
	for _, part in folder:GetChildren() do
		local key = part:GetAttribute("Key")
		if type(key) == "string" and wanted[key] then
			wanted[key] = nil -- already there
		else
			part:Destroy()
		end
	end
	for key, piece in wanted do
		local part = PieceFactory.make(piece, plot.origin)
		part:SetAttribute("Key", key)
		part.Parent = folder
	end
	-- Tower material on structural pieces (cosmetic, so applied in place).
	local def = Cosmetics.byKey[mat or Cosmetics.DEFAULT] or Cosmetics.byKey[Cosmetics.DEFAULT]
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") and Cosmetics.structural[part.Name] then
			part.Material = def.material
		end
	end
end

local function onPlayerAdded(player: Player)
	local slot = freeSlot()
	local origin = Vector3.new(slot * PLOT_SPACING, 0, 0)
	local model = Instance.new("Model")
	model.Name = "Plot_" .. player.UserId
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("Origin", origin) -- clients convert world <-> grid with this
	PlotBuilder.base(model, origin, APRON_DEPTH)
	PlotBuilder.build(model, origin, APRON_DEPTH)
	model.Parent = plotsFolder
	plots[player] = { slot = slot, origin = origin, model = model }

	-- Everyone spawns at their own plot (or their run checkpoint).
	local function onCharacter(character: Model)
		task.defer(function()
			local cf = respawnAt[player] or PlotService.spawnCFrame(player)
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
	respawnAt[player] = nil
	local plot = plots[player]
	if plot then
		plot.model:Destroy()
		plots[player] = nil
	end
end

function PlotService.init()
	local preview = workspace:FindFirstChild("EditorPreview") -- tools/editor_island.luau
	if preview then
		preview:Destroy()
	end
	PlotBuilder.buildWorld()
	plotsFolder.Parent = workspace
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		onPlayerAdded(p)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return PlotService

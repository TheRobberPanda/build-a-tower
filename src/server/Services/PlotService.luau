--!strict
-- One plot per player. Renders a tower's pieces as parts on the plot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local PieceFactory = require(game:GetService("ReplicatedStorage").Shared.PieceFactory)
local PieceVisuals = require(ReplicatedStorage.Shared.PieceVisuals)
local AntiCheat = require(script.Parent.AntiCheat)
local PlotBuilder = require(script.Parent.PlotBuilder)
local TowerCodec = require(ReplicatedStorage.Shared.TowerCodec)
local Types = require(ReplicatedStorage.Shared.Types)

type Piece = Types.Piece

local PlotService = {}

local APRON_DEPTH = 16
-- Islands sit in a ring round the lobby, far apart (glide between them): six
-- per ring, a wider ring past that.
local RING_RADIUS = 700
local plotsFolder = Instance.new("Folder")
plotsFolder.Name = "Plots"

-- size = buildable cells in X and Z, theme = Cosmetics theme key, core = the
-- round tower frame is standing (only while a round tower is shown).
type Plot = { slot: number, origin: Vector3, model: Model, size: number, theme: string, core: boolean }
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

-- During a run, respawn here instead of the home spawn (nil = home spawn).
local respawnAt: { [Player]: CFrame } = {}
function PlotService.setRespawn(player: Player, cf: CFrame?)
	respawnAt[player] = cf
end

-- Home = where you (re)spawn outside runs: your own island.
function PlotService.homeCFrame(player: Player): CFrame?
	return PlotService.spawnCFrame(player) or PlotBuilder.lobbySpawn()
end

-- Back home now (round over, chose free build...), or to the lobby island.
function PlotService.sendHome(player: Player, lobby: boolean?)
	local cf = if lobby then PlotBuilder.lobbySpawn() else PlotService.homeCFrame(player)
	local character = player.Character
	if cf and character then
		AntiCheat.expectTeleport(player, cf.Position)
		character:PivotTo(cf)
	end
end

-- Rebuilds the island scenery (theme or size changed). Pieces are kept.
local function rebuild(plot: Plot)
	for _, name in { "Base", "Apron", "Scenery", "Core" } do
		local old = plot.model:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	PlotBuilder.base(plot.model, plot.origin, APRON_DEPTH, plot.size, plot.theme)
	PlotBuilder.build(plot.model, plot.origin, APRON_DEPTH, plot.size, plot.theme)
	if plot.core then
		PlotBuilder.core(plot.model, plot.origin)
	end
	plot.model:SetAttribute("Size", plot.size)
end

-- Plot theme (whole island) and size (expansions). No-op when nothing changed.
function PlotService.configure(player: Player, theme: string, size: number)
	local plot = plots[player]
	if plot and (plot.theme ~= theme or plot.size ~= size) then
		plot.theme = theme
		plot.size = size
		rebuild(plot)
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
	local pos = plot.origin + Vector3.new(plot.size * g / 2, 3, -APRON_DEPTH / 2)
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

-- The course trophy: a store decoration floating over the Finish of the tower
-- being run (nil removes it). Finishing the course gives it (RunTimerService).
function PlotService.setTrophy(player: Player, typeId: number?)
	local plot = plots[player]
	if not plot then
		return
	end
	local old = plot.model:FindFirstChild("Trophy")
	if old then
		old:Destroy()
	end
	local pieces = plot.model:FindFirstChild("Pieces")
	local finish = pieces and pieces:FindFirstChild("Finish")
	if not typeId or not finish or not finish:IsA("BasePart") then
		return
	end
	-- Floats over the flag (Finish keys are "t,x,y,z,r").
	local key = finish:GetAttribute("Key")
	local x, y, z = string.match(if type(key) == "string" then key else "", "^%d+,(%d+),(%d+),(%d+)")
	if not x then
		return
	end
	local part = PieceFactory.make({
		t = typeId,
		x = tonumber(x) :: number,
		y = (tonumber(y) :: number) + 3,
		z = tonumber(z) :: number,
		r = 0,
	}, plot.origin)
	part.Name = "Trophy"
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 220, 120)
	glow.Range = 16
	glow.Parent = part
	part.Parent = plot.model
end

-- Coins at plot-relative spots (the builder's climb in a round race); touching
-- one calls onCollect once. An empty list clears them.
function PlotService.dropCoins(player: Player, spots: { Vector3 }, onCollect: (Player) -> ())
	local plot = plots[player]
	if not plot then
		return
	end
	local old = plot.model:FindFirstChild("Coins")
	if old then
		old:Destroy()
	end
	if #spots == 0 then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Coins"
	for _, at in spots do
		local coin = Instance.new("Part")
		coin.Name = "PathCoin"
		coin.Shape = Enum.PartType.Cylinder
		coin.Size = Vector3.new(0.4, 2.6, 2.6)
		coin.CFrame = CFrame.new(plot.origin + at) -- the disc stands on its edge (cylinder axis = X)
		coin.Color = Color3.fromRGB(255, 200, 40)
		coin.Material = Enum.Material.Neon
		coin.Anchored = true
		coin.CanCollide = false
		coin.CanQuery = false
		game:GetService("CollectionService"):AddTag(coin, "PathCoin") -- clients spin it
		coin.Touched:Connect(function(hit)
			local character = player.Character
			if coin.Parent and character and hit:IsDescendantOf(character) then
				coin:Destroy()
				onCollect(player)
			end
		end)
		coin.Parent = folder
	end
	folder.Parent = plot.model
end

-- Breaks these pieces' parts into falling chunks (call before render removes them).
function PlotService.shatter(player: Player, pieces: { Piece })
	local folder = plots[player] and plots[player].model:FindFirstChild("Pieces")
	if not folder then
		return
	end
	local keys: { [string]: boolean } = {}
	for _, piece in pieces do
		keys[pieceKey(piece)] = true
	end
	for _, part in folder:GetChildren() do
		local key = part:GetAttribute("Key")
		if part:IsA("BasePart") and type(key) == "string" and keys[key] then
			PieceVisuals.shatter(part)
		end
	end
end

-- Makes the plot show exactly `pieces` (with the round frame if `core`). Only
-- changed parts are destroyed or created, so an edit replicates one part.
function PlotService.render(player: Player, pieces: { Piece }, mat: string?, core: boolean?)
	local plot = plots[player]
	if not plot then
		return
	end
	if plot.core ~= (core == true) then
		plot.core = core == true
		local old = plot.model:FindFirstChild("Core")
		if old then
			old:Destroy()
		end
		if plot.core then
			PlotBuilder.core(plot.model, plot.origin)
		end
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
			-- The default keeps each piece's own (icon) material.
			local base = part:GetAttribute("BaseMat")
			part.Material = if def.key == Cosmetics.DEFAULT and type(base) == "string"
				then (Enum.Material :: any)[base]
				else def.material
			-- Painted textures only with the default material, so a bought one shows.
			for _, c in part:GetDescendants() do
				if c:IsA("Decal") and c.Name == "Skin" then
					c.Transparency = if def.key == Cosmetics.DEFAULT then part.Transparency else 1
				end
			end
		end
	end
	-- Weakly supported pieces glow: yellow two hops out from support, red from four or floating.
	local byKey: { [string]: Instance } = {}
	for _, part in folder:GetChildren() do
		local key = part:GetAttribute("Key")
		if type(key) == "string" then
			byKey[key] = part
		end
	end
	local support = TowerCodec.support(pieces, plot.core)
	for i, piece in pieces do
		local part = byKey[pieceKey(piece)]
		if not part or not part:IsA("BasePart") then
			continue
		end
		local old = part:FindFirstChild("WeakGlow")
		if old then
			old:Destroy()
		end
		local d = support[i]
		if d >= 2 then
			local k = math.clamp((d - 2) / 2, 0, 1)
			local glow = Instance.new("Part")
			glow.Name = "WeakGlow"
			glow.Anchored = true
			glow.CanCollide = false
			glow.CanTouch = false
			glow.CanQuery = false
			glow.CastShadow = false
			glow.Material = Enum.Material.ForceField
			glow.Color = Color3.fromRGB(255, 220, 70):Lerp(Color3.fromRGB(255, 60, 50), k)
			glow.Size = part.Size + Vector3.one * 0.3
			glow.CFrame = part.CFrame
			glow.Parent = part
			if d >= Config.COLLAPSE_HOPS then
				PieceVisuals.tremble(part, Config.COLLAPSE_DELAY) -- TowerService drops it then
			end
		end
	end
end

local function originFor(slot: number): Vector3
	local ring = slot // 6
	local a = (slot % 6 + ring * 0.5) / 6 * math.pi * 2
	local r = RING_RADIUS + ring * 500
	local half = Config.PLOT_CELLS_MAX * Config.GRID_STUDS / 2
	local at = PlotBuilder.LOBBY + Vector3.new(math.cos(a) * r - half, 0, math.sin(a) * r - half)
	return Vector3.new(math.round(at.X), at.Y, math.round(at.Z))
end

local function onPlayerAdded(player: Player)
	local slot = freeSlot()
	local origin = originFor(slot)
	local model = Instance.new("Model")
	model.Name = "Plot_" .. player.UserId
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("Origin", origin) -- clients convert world <-> grid with this
	local plot: Plot = {
		slot = slot,
		origin = origin,
		model = model,
		size = Config.PLOT_CELLS_X,
		theme = Cosmetics.DEFAULT_THEME,
		core = false,
	}
	rebuild(plot)
	model.Parent = plotsFolder
	plots[player] = plot

	-- Spawn at home (lobby or island), or the run checkpoint.
	local function onCharacter(character: Model)
		task.defer(function()
			local cf = respawnAt[player] or PlotService.homeCFrame(player)
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
	PlotBuilder.lobby()
	plotsFolder.Parent = workspace
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		onPlayerAdded(p)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Fell off an island (or slipped under one): straight back to the checkpoint
	-- or home instead of a long fall to the sea. Plots and the lobby sit at
	-- ALTITUDE; island tops dip a few studs below it, so 25 is out of reach in
	-- a run. Outside runs you may glide far below the islands first.
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
					continue
				end
				local pos = root.Position
				local plot = plots[player]
				local underGrid = plot ~= nil
					and pos.Y < plot.origin.Y - 4
					and pos.X > plot.origin.X
					and pos.X < plot.origin.X + plot.size * Config.GRID_STUDS
					and pos.Z > plot.origin.Z
					and pos.Z < plot.origin.Z + plot.size * Config.GRID_STUDS
				local drop = if respawnAt[player] then 25 else 180
				if pos.Y < PlotBuilder.ALTITUDE - drop or underGrid then
					local cf = respawnAt[player] or PlotService.homeCFrame(player)
					if cf then
						AntiCheat.expectTeleport(player, cf.Position)
						root.AssemblyLinearVelocity = Vector3.zero
						character:PivotTo(cf)
					end
				end
			end
		end
	end)
end

return PlotService

--!strict
-- Turns pointer/touch input into place/remove intents. Shows a ghost of the
-- selected piece. The server re-validates everything.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local PieceFactory = require(ReplicatedStorage.Shared.PieceFactory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TowerCodec = require(ReplicatedStorage.Shared.TowerCodec)
local State = require(script.Parent.Parent.State)

local BuildController = {}

local player = Players.LocalPlayer
local G = Config.GRID_STUDS

local ghost: Part
local outline: SelectionBox
local countTag: BillboardGui
local FILL_MAX = 64 -- matches the server's PlaceArea cap
-- Fill mode (button or G): the first click/tap sets a corner, the second fills
-- the box between them (with Delete on: deletes everything in it).
type Corner = { cell: Vector3 }
local corner: Corner? = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

-- cell = the empty cell a click would build in; removeCell = the piece cell hit.
type Target = { cell: Vector3, removeCell: Vector3?, valid: boolean }

local function myPlot(): Model?
	local plots = workspace:FindFirstChild("Plots")
	local owner = if State.buildOwner ~= 0 then State.buildOwner else player.UserId
	local plot = plots and plots:FindFirstChild("Plot_" .. owner)
	return if plot and plot:IsA("Model") then plot else nil
end

local function toCell(origin: Vector3, worldPos: Vector3): Vector3
	local p = (worldPos - origin) / G
	return Vector3.new(math.floor(p.X), math.floor(p.Y), math.floor(p.Z))
end

local function selectedPiece(cell: Vector3): TowerCodec.Piece
	return {
		t = State.selected,
		x = cell.X,
		y = cell.Y,
		z = cell.Z,
		r = State.rotation,
		p = State.selectedProps(),
	}
end

-- Same rules as the server (TowerService.rulesFor); the server still decides.
local function rules(): TowerCodec.Rules
	if State.inRound then
		return { core = true, size = Config.PLOT_CELLS_X }
	end
	return { size = State.plotSize }
end

-- Occupied cells of the tower being edited, rebuilt when it changes.
local placeState = TowerCodec.newPlaceState()
local function refreshPlaceState()
	placeState = TowerCodec.newPlaceState()
	for _, piece in if State.tower then State.tower.pieces else {} do
		TowerCodec.add(placeState, piece)
	end
end

local function canPlace(piece: TowerCodec.Piece): boolean
	local clean = TowerCodec.validatePiece(piece, rules())
	if not clean or not State.canUse(clean.t) then
		return false
	end
	return (TowerCodec.canAdd(placeState, clean))
end

-- The main axis of a surface normal, with its sign (a ramp slope counts as up).
local function axisOf(n: Vector3): Vector3
	local ax, ay, az = math.abs(n.X), math.abs(n.Y), math.abs(n.Z)
	if ay >= ax and ay >= az then
		return Vector3.new(0, math.sign(n.Y), 0)
	elseif ax >= az then
		return Vector3.new(math.sign(n.X), 0, 0)
	end
	return Vector3.new(0, 0, math.sign(n.Z))
end

-- Raycasts onto the plot being edited. `viewport` = coordinates include the top-bar
-- inset (GetMouseLocation); otherwise they are GUI coordinates (input.Position, taps).
local function targetAt(screenPos: Vector2, viewport: boolean): Target?
	local plot = myPlot()
	local camera = workspace.CurrentCamera
	if not plot or not camera then
		return nil
	end
	local origin = plot:GetAttribute("Origin")
	if typeof(origin) ~= "Vector3" then
		return nil
	end
	rayParams.FilterDescendantsInstances = { plot }
	local ray = if viewport
		then camera:ViewportPointToRay(screenPos.X, screenPos.Y)
		else camera:ScreenPointToRay(screenPos.X, screenPos.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 600, rayParams)
	if not hit or hit.Instance.Name == "Apron" then
		return nil
	end
	local pieces = plot:FindFirstChild("Pieces")
	local cell: Vector3
	local removeCell: Vector3? = nil
	local axis = axisOf(hit.Normal)
	if pieces and hit.Instance:IsDescendantOf(pieces) then
		-- Step inwards to the piece's cell, then one whole cell out of the face hit.
		-- (Stepping out from the hit point landed back inside thin pieces like
		-- jump pads and buttons, so nothing could go on top of them.)
		removeCell = toCell(origin, hit.Position - hit.Normal * 0.05)
		cell = (removeCell :: Vector3) + axis
	else
		cell = toCell(origin, hit.Position + hit.Normal * (G / 2))
	end
	-- Pieces grow towards +x/+y/+z from their cell, so on a -x/-y/-z face a wide
	-- piece starts further out instead of reaching back into what was hit.
	local sx, sy, sz = TowerCodec.extent(selectedPiece(cell))
	cell -= Vector3.new(
		if axis.X < 0 then sx - 1 else 0,
		if axis.Y < 0 then sy - 1 else 0,
		if axis.Z < 0 then sz - 1 else 0
	)
	return { cell = cell, removeCell = removeCell, valid = canPlace(selectedPiece(cell)) }
end

-- Snaps a box to whole pieces and the fill cap. Returns start, end (both piece
-- origins) and the piece count.
local function fillBox(a: Vector3, b: Vector3): (Vector3, Vector3, number)
	local sx, sy, sz = TowerCodec.extent(selectedPiece(a))
	local ext = { sx, sy, sz }
	local from = { a.X, a.Y, a.Z }
	local to = { b.X, b.Y, b.Z }
	local counts = {}
	for i = 1, 3 do
		counts[i] = math.floor(math.abs(to[i] - from[i]) / ext[i]) + 1
	end
	while counts[1] * counts[2] * counts[3] > FILL_MAX do
		local big = 1
		for i = 2, 3 do
			if counts[i] > counts[big] then
				big = i
			end
		end
		counts[big] -= 1
	end
	local out = {}
	for i = 1, 3 do
		local dir = if to[i] >= from[i] then 1 else -1
		out[i] = from[i] + dir * (counts[i] - 1) * ext[i]
	end
	return a, Vector3.new(out[1], out[2], out[3]), counts[1] * counts[2] * counts[3]
end

-- See-through copy of the real piece where a single click would place it.
local preview: BasePart? = nil
local previewKey = ""

local function setPreview(piece: TowerCodec.Piece?, origin: Vector3?)
	local key = if piece then game:GetService("HttpService"):JSONEncode(piece) else ""
	if key == previewKey then
		return
	end
	previewKey = key
	if preview then
		preview:Destroy()
		preview = nil
	end
	if not piece or not origin then
		return
	end
	local root = PieceFactory.make(piece, origin)
	local all = root:GetDescendants()
	table.insert(all, root)
	for _, d in all do
		for _, tag in CollectionService:GetTags(d) do
			CollectionService:RemoveTag(d, tag) -- no jump pad / one-way behaviour on a ghost
		end
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Transparency = math.max(d.Transparency, 0.45)
		elseif d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = math.max(d.Transparency, 0.45)
		elseif d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	root.Parent = workspace
	preview = root
end

local function showGhost(cf: CFrame, size: Vector3, color: Color3, count: number)
	ghost.CFrame = cf
	ghost.Size = size
	ghost.Color = color
	outline.Color3 = color
	outline.SurfaceColor3 = color
	local label = countTag:FindFirstChildOfClass("TextLabel")
	if label then
		label.Text = "x" .. count
	end
	countTag.Enabled = count > 1
	ghost.Parent = workspace
end

local RED = Color3.fromRGB(235, 70, 80)

local function updateGhost(target: Target?)
	local plot = myPlot()
	if State.mode ~= "build" or not target or not plot or State.deleting then
		setPreview(nil)
	end
	if State.mode ~= "build" or not target or not plot then
		ghost.Parent = nil
		return
	end
	local origin = plot:GetAttribute("Origin") :: Vector3
	if State.deleting then
		local c = target.removeCell
		if not c then
			ghost.Parent = nil
			return
		end
		local a = if corner then corner.cell else c
		local lo, hi = a:Min(c), a:Max(c) + Vector3.one
		local n = (hi - lo)
		showGhost(
			CFrame.new(origin + (lo + hi) / 2 * G),
			n * G + Vector3.one * 0.2,
			RED,
			if corner then n.X * n.Y * n.Z else 1
		)
		return
	end
	local a = if corner then corner.cell else target.cell
	local first, last, count = fillBox(a, target.cell)
	local sx, sy, sz = TowerCodec.extent(selectedPiece(first))
	local lo = first:Min(last)
	local hi = last:Max(first) + Vector3.new(sx, sy, sz)
	local valid = count > 1 or target.valid
	setPreview(if valid and count == 1 then selectedPiece(first) else nil, origin)
	ghost.Transparency = if preview then 1 else 0.6 -- the outline stays around the real shape
	showGhost(
		CFrame.new(origin + (lo + hi) / 2 * G),
		(hi - lo) * G,
		if valid then Color3.fromRGB(80, 200, 255) else RED,
		count
	)
end

-- One click or tap on the plot.
local function act(target: Target?)
	if State.mode ~= "build" or not target then
		return
	end
	local cell = if State.deleting then target.removeCell else target.cell
	if not cell then
		return
	end
	if State.fill then
		local c = corner
		if not c then
			corner = { cell = cell }
			return
		end
		corner = nil
		if State.deleting then
			Remotes.event("RemoveArea"):FireServer(c.cell.X, c.cell.Y, c.cell.Z, cell.X, cell.Y, cell.Z)
			return
		end
		local first, last, count = fillBox(c.cell, cell)
		if count > 1 then
			Remotes.event("PlaceArea"):FireServer(
				State.selected,
				first.X,
				first.Y,
				first.Z,
				last.X,
				last.Y,
				last.Z,
				State.rotation,
				State.selectedProps()
			)
			return
		end
	end
	if State.deleting then
		Remotes.event("RemovePiece"):FireServer(cell.X, cell.Y, cell.Z)
	elseif target.valid then
		Remotes.event("PlacePiece")
			:FireServer(State.selected, cell.X, cell.Y, cell.Z, State.rotation, State.selectedProps())
	end
end

-- Number keys pick the Nth visible hotbar slot (UIController fills State.hotbarKeys).
local KEY_TO_SLOT: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.Zero] = 10,
}

-- Steps the selected piece's setting (jump pad power, teleporter channel).
function BuildController.cycleSetting()
	local k, range = State.settingOf(State.selected)
	if not k or not range then
		return
	end
	local cur = State.props[k] or range[1]
	local props = table.clone(State.props)
	props[k] = if cur >= range[2] then range[1] else cur + 1
	State.set({ props = props })
end

function BuildController.init()
	ghost = Instance.new("Part")
	ghost.Name = "BuildGhost"
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.CanTouch = false
	ghost.Transparency = 0.6
	ghost.Material = Enum.Material.ForceField
	outline = Instance.new("SelectionBox")
	outline.Adornee = ghost
	outline.LineThickness = 0.12
	outline.SurfaceTransparency = 0.85
	outline.Parent = ghost
	countTag = Instance.new("BillboardGui")
	countTag.Size = UDim2.fromOffset(70, 34)
	countTag.AlwaysOnTop = true
	countTag.Adornee = ghost
	countTag.Parent = ghost
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Parent = countTag
end

function BuildController.start()
	State.Changed:Connect(function()
		if not State.fill then
			corner = nil
		end
	end)
	Remotes.event("TowerChanged").OnClientEvent:Connect(function()
		task.defer(refreshPlaceState) -- after UIController stored the new tower
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- One click = one action (holding no longer paints: it deleted the piece
			-- behind the one just removed).
			act(targetAt(UserInputService:GetMouseLocation(), true))
		elseif input.UserInputType == Enum.UserInputType.Keyboard and State.mode == "build" then
			local n = KEY_TO_SLOT[input.KeyCode]
			local piece = n and State.hotbarKeys[n]
			if piece and State.canUse(piece) then
				State.set({ selected = piece, deleting = false })
			elseif input.KeyCode == Enum.KeyCode.R then
				State.set({ rotation = (State.rotation + 1) % 4 })
			elseif input.KeyCode == Enum.KeyCode.Z then
				Remotes.event("Undo"):FireServer()
			elseif input.KeyCode == Enum.KeyCode.F then
				BuildController.cycleSetting()
			elseif input.KeyCode == Enum.KeyCode.X then
				State.set({ deleting = not State.deleting })
			elseif input.KeyCode == Enum.KeyCode.G then
				State.set({ fill = not State.fill })
			elseif input.KeyCode == Enum.KeyCode.Escape then
				corner = nil
			end
		end
	end)

	-- Touch: a tap (not a drag/camera swipe) places or deletes.
	UserInputService.TouchTap:Connect(function(positions, processed)
		if not processed and positions[1] then
			local target = targetAt(Vector2.new(positions[1].X, positions[1].Y), false)
			act(target)
			updateGhost(target)
		end
	end)

	-- Desktop hover preview (the ghost follows the mouse, no smoothing lag).
	RunService.RenderStepped:Connect(function()
		if UserInputService.MouseEnabled and State.mode == "build" then
			updateGhost(targetAt(UserInputService:GetMouseLocation(), true))
		elseif State.mode ~= "build" then
			ghost.Parent = nil
			corner = nil
			setPreview(nil)
		end
	end)
end

return BuildController

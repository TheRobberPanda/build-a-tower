--!strict
-- Turns pointer/touch input into place/remove intents. Shows a ghost of the
-- selected piece. The server re-validates everything.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local PieceDefs = require(ReplicatedStorage.Shared.PieceDefs)
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
local ghostTarget: CFrame? = nil -- the ghost glides here (visual only)
local FILL_MAX = 64 -- matches the server's PlaceArea cap
-- Drag state: press on a face, drag across the plane of that face, release to
-- fill the rectangle (ground = floor, wall face = wall). A plain click = one piece.
type Drag = { cell: Vector3, normal: Vector3, ended: Vector3, at: Vector3, n: Vector3 }
local drag: Drag? = nil
local tapStart: Drag? = nil -- touch Fill mode: first tap sets the corner
local painting = false
local lastPainted: Vector3? = nil
local lastPaintAt = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

type Target =
	{ cell: Vector3, removeCell: Vector3?, valid: boolean, normal: Vector3, at: Vector3, n: Vector3 }

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

-- Raycasts onto the player's own plot. `viewport` = coordinates include the top-bar
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
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
	if not hit or hit.Instance.Name == "Apron" then
		return nil
	end
	-- Nudge along the normal: outwards = the empty cell to build in, inwards = the piece hit.
	local cell = toCell(origin, hit.Position + hit.Normal * (G / 2))
	local removeCell = if hit.Instance.Name ~= "Base"
		then toCell(origin, hit.Position - hit.Normal * (G / 2))
		else nil
	local valid = TowerCodec.validatePiece(selectedPiece(cell)) ~= nil
	local n = hit.Normal
	local axis = if math.abs(n.Y) >= math.abs(n.X) and math.abs(n.Y) >= math.abs(n.Z)
		then Vector3.yAxis
		elseif math.abs(n.X) >= math.abs(n.Z) then Vector3.xAxis
		else Vector3.zAxis
	return { cell = cell, removeCell = removeCell, valid = valid, normal = axis, at = hit.Position, n = n }
end

-- The cell under the pointer on the plane the drag started on.
local function cellOnPlane(screenPos: Vector2, viewport: boolean, d: Drag): Vector3
	local plot = myPlot()
	local camera = workspace.CurrentCamera
	local origin = plot and plot:GetAttribute("Origin")
	if not camera or typeof(origin) ~= "Vector3" then
		return d.cell
	end
	local ray = if viewport
		then camera:ViewportPointToRay(screenPos.X, screenPos.Y)
		else camera:ScreenPointToRay(screenPos.X, screenPos.Y)
	-- Intersect the clicked face itself (not the cell centre half a cell above it:
	-- at shallow camera angles that plane lands cells away and a click became a fill).
	local denom = ray.Direction:Dot(d.n)
	if math.abs(denom) < 1e-3 then
		return d.cell
	end
	local t = (d.at - ray.Origin):Dot(d.n) / denom
	if t < 0 or t > 800 then
		return d.cell
	end
	local c = toCell(origin, ray.Origin + ray.Direction * t + d.n * (G / 2))
	local keep = d.cell * d.normal -- stay on the starting layer/wall
	return c * (Vector3.one - d.normal) + keep
end

-- Snaps a drag box to whole pieces and the fill cap. Returns start, end
-- (both piece origins) and the piece count.
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
		elseif d:IsA("Decal") then
			d.Transparency = 0.45
		elseif d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		end
	end
	root.Parent = workspace
	preview = root
end

local function showGhost(cf: CFrame, size: Vector3, color: Color3, count: number)
	if ghost.Parent == nil or not ghostTarget then
		ghost.CFrame = cf -- appear in place, then glide
	end
	ghostTarget = cf
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

local function updateGhost(target: Target?)
	local plot = myPlot()
	if State.mode ~= "build" or not target or not plot or State.deleting then
		setPreview(nil)
	end
	if State.mode ~= "build" or not target or not plot then
		ghost.Parent = nil
		ghostTarget = nil
		return
	end
	local origin = plot:GetAttribute("Origin") :: Vector3
	if State.deleting then
		if not target.removeCell then
			ghost.Parent = nil
			return
		end
		local pos = origin + (target.removeCell + Vector3.one * 0.5) * G
		showGhost(CFrame.new(pos), Vector3.one * (G + 0.2), Color3.fromRGB(235, 70, 80), 1)
		return
	end
	local a = target.cell
	local b = target.cell
	local d = drag or tapStart
	if d then
		a, b = d.cell, d.ended
	end
	local first, last, count = fillBox(a, b)
	local sx, sy, sz = TowerCodec.extent(selectedPiece(first))
	local ext = Vector3.new(sx, sy, sz)
	local lo = first:Min(last)
	local hi = last:Max(first) + ext
	local valid = TowerCodec.validatePiece(selectedPiece(first)) ~= nil
	setPreview(if valid and count == 1 then selectedPiece(first) else nil, origin)
	ghost.Transparency = if preview then 1 else 0.6 -- the outline stays around the real shape
	showGhost(
		CFrame.new(origin + (lo + hi) / 2 * G),
		(hi - lo) * G,
		if valid then Color3.fromRGB(80, 200, 255) else Color3.fromRGB(235, 70, 80),
		count
	)
end

local function act(target: Target?)
	if State.mode ~= "build" then
		return
	end
	if not target then
		return
	end
	if State.deleting then
		local c = target.removeCell
		if c then
			Remotes.event("RemovePiece"):FireServer(c.X, c.Y, c.Z)
		end
	elseif target.valid then
		local c = target.cell
		Remotes.event("PlacePiece")
			:FireServer(State.selected, c.X, c.Y, c.Z, State.rotation, State.selectedProps())
	end
end

local function fill(a: Vector3, b: Vector3)
	if State.mode ~= "build" or State.deleting then
		return
	end
	local first, last, count = fillBox(a, b)
	if count <= 1 then
		Remotes.event("PlacePiece")
			:FireServer(State.selected, first.X, first.Y, first.Z, State.rotation, State.selectedProps())
	else
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
	end
end

local KEY_TO_PIECE: { [Enum.KeyCode]: number } = {
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
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local target = targetAt(Vector2.new(input.Position.X, input.Position.Y), false)
			if State.deleting then
				act(target)
				painting = true
				lastPainted = target and target.removeCell
			elseif target and target.valid and State.mode == "build" then
				drag = {
					cell = target.cell,
					normal = target.normal,
					ended = target.cell,
					at = target.at,
					n = target.n,
				}
			end
		elseif input.UserInputType == Enum.UserInputType.Keyboard and State.mode == "build" then
			local piece = KEY_TO_PIECE[input.KeyCode]
			if piece and PieceDefs.byId[piece] then
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
			end
		end
	end)

	-- Touch: a tap (not a drag/camera swipe) places or deletes.
	UserInputService.TouchTap:Connect(function(positions, processed)
		if not processed and positions[1] then
			local pos = Vector2.new(positions[1].X, positions[1].Y)
			local target = targetAt(pos, false)
			if State.fill and not State.deleting and State.mode == "build" then
				-- Fill mode: first tap = one corner, second tap = the other corner.
				if tapStart then
					local d = tapStart
					d.ended = cellOnPlane(pos, false, d)
					tapStart = nil
					fill(d.cell, d.ended)
				elseif target and target.valid then
					tapStart = {
						cell = target.cell,
						normal = target.normal,
						ended = target.cell,
						at = target.at,
						n = target.n,
					}
				end
				updateGhost(target)
				return
			end
			updateGhost(target)
			act(target)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			painting = false
			lastPainted = nil
			local d = drag
			drag = nil
			if d then
				fill(d.cell, d.ended)
			end
		end
	end)
	State.Changed:Connect(function()
		if not State.fill then
			tapStart = nil
		end
	end)

	-- Desktop hover preview; holding the mouse button paints along the drag.
	RunService.RenderStepped:Connect(function()
		if UserInputService.MouseEnabled and State.mode == "build" then
			local mouse = UserInputService:GetMouseLocation()
			local target = targetAt(mouse, true)
			local d = drag
			if d then
				d.ended = cellOnPlane(mouse, true, d)
			end
			updateGhost(
				if d then { cell = d.cell, valid = true, normal = d.normal, at = d.at, n = d.n } else target
			)
			if painting and target then
				local cell = if State.deleting then target.removeCell else target.cell
				if cell and cell ~= lastPainted and os.clock() - lastPaintAt > 0.08 then
					lastPainted = cell
					lastPaintAt = os.clock()
					act(target)
				end
			end
		elseif State.mode ~= "build" then
			ghost.Parent = nil
			drag = nil
			setPreview(nil)
		end
		local goal = ghostTarget
		if goal and ghost.Parent then
			ghost.CFrame = ghost.CFrame:Lerp(goal, 0.45)
		end
	end)
end

return BuildController

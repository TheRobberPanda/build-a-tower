--!strict
-- Turns pointer/touch input into place/remove intents. Shows a ghost of the
-- selected piece. The server re-validates everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local PieceDefs = require(ReplicatedStorage.Shared.PieceDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TowerCodec = require(ReplicatedStorage.Shared.TowerCodec)
local State = require(script.Parent.Parent.State)

local BuildController = {}

local player = Players.LocalPlayer
local G = Config.GRID_STUDS

local ghost: Part
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

type Target = { cell: Vector3, removeCell: Vector3?, valid: boolean }

local function myPlot(): Model?
	local plots = workspace:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot_" .. player.UserId)
	return if plot and plot:IsA("Model") then plot else nil
end

local function toCell(origin: Vector3, worldPos: Vector3): Vector3
	local p = (worldPos - origin) / G
	return Vector3.new(math.floor(p.X), math.floor(p.Y), math.floor(p.Z))
end

local function selectedPiece(cell: Vector3): TowerCodec.Piece
	return { t = State.selected, x = cell.X, y = cell.Y, z = cell.Z, r = State.rotation }
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
	if not hit then
		return nil
	end
	-- Nudge along the normal: outwards = the empty cell to build in, inwards = the piece hit.
	local cell = toCell(origin, hit.Position + hit.Normal * (G / 2))
	local removeCell = if hit.Instance.Name ~= "Base"
		then toCell(origin, hit.Position - hit.Normal * (G / 2))
		else nil
	local valid = TowerCodec.validatePiece(selectedPiece(cell)) ~= nil
	return { cell = cell, removeCell = removeCell, valid = valid }
end

local function updateGhost(target: Target?)
	local plot = myPlot()
	if State.mode ~= "build" or not target or not plot then
		ghost.Parent = nil
		return
	end
	local origin = plot:GetAttribute("Origin") :: Vector3
	if State.deleting then
		if not target.removeCell then
			ghost.Parent = nil
			return
		end
		ghost.Size = Vector3.one * (G + 0.2)
		ghost.Position = origin + (target.removeCell + Vector3.one * 0.5) * G
		ghost.Color = Color3.fromRGB(235, 70, 80)
	else
		local piece = selectedPiece(target.cell)
		local sx, sy, sz = TowerCodec.extent(piece)
		ghost.Size = Vector3.new(sx, sy, sz) * G
		ghost.Position = origin + (target.cell + Vector3.new(sx, sy, sz) / 2) * G
		ghost.Color = if target.valid then Color3.fromRGB(80, 200, 255) else Color3.fromRGB(235, 70, 80)
	end
	ghost.Parent = workspace
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
		Remotes.event("PlacePiece"):FireServer(State.selected, c.X, c.Y, c.Z, State.rotation)
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
}

function BuildController.init()
	ghost = Instance.new("Part")
	ghost.Name = "BuildGhost"
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.CanTouch = false
	ghost.Transparency = 0.6
	ghost.Material = Enum.Material.ForceField
end

function BuildController.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			act(targetAt(Vector2.new(input.Position.X, input.Position.Y), false))
		elseif input.UserInputType == Enum.UserInputType.Keyboard and State.mode == "build" then
			local piece = KEY_TO_PIECE[input.KeyCode]
			if piece and PieceDefs.byId[piece] then
				State.set({ selected = piece, deleting = false })
			elseif input.KeyCode == Enum.KeyCode.R then
				State.set({ rotation = (State.rotation + 1) % 4 })
			elseif input.KeyCode == Enum.KeyCode.X then
				State.set({ deleting = not State.deleting })
			end
		end
	end)

	-- Touch: a tap (not a drag/camera swipe) places or deletes.
	UserInputService.TouchTap:Connect(function(positions, processed)
		if not processed and positions[1] then
			local target = targetAt(Vector2.new(positions[1].X, positions[1].Y), false)
			updateGhost(target)
			act(target)
		end
	end)

	-- Desktop hover preview.
	RunService.RenderStepped:Connect(function()
		if UserInputService.MouseEnabled and State.mode == "build" then
			updateGhost(targetAt(UserInputService:GetMouseLocation(), true))
		elseif State.mode ~= "build" then
			ghost.Parent = nil
		end
	end)
end

return BuildController

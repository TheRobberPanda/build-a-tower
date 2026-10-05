--!strict
-- Optional build camera: orbits the plot you are building on so your character
-- doesn't block the view (mainly for phones). Drag to rotate, scroll / pinch to
-- zoom; the target height follows the tower. Turns off when a run starts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local State = require(script.Parent.Parent.State)

local CameraController = {}

local player = Players.LocalPlayer
local G = Config.GRID_STUDS

local active = false
local yaw = math.rad(200)
local pitch = math.rad(35)
local distance = 90
local dragging = false
local lastPos: Vector2? = nil
local pinchStart: number? = nil
local pinchDistance = distance

local changed = Instance.new("BindableEvent")
CameraController.Changed = changed.Event -- (active)

local function plot(): Model?
	local plots = workspace:FindFirstChild("Plots")
	local owner = if State.buildOwner ~= 0 then State.buildOwner else player.UserId
	local p = plots and plots:FindFirstChild("Plot_" .. owner)
	return if p and p:IsA("Model") then p else nil
end

local function towerTop(): number
	local top = 0
	for _, piece in if State.tower then State.tower.pieces else {} do
		top = math.max(top, piece.y + 1)
	end
	return top * G
end

function CameraController.isActive(): boolean
	return active
end

function CameraController.set(on: boolean)
	if on == active then
		return
	end
	active = on
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if on then
		camera.CameraType = Enum.CameraType.Scriptable
	else
		camera.CameraType = Enum.CameraType.Custom
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	changed:Fire(active)
end

function CameraController.toggle()
	CameraController.set(not active)
end

function CameraController.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not active or processed then
			return
		end
		-- Right mouse or a touch starts a rotate drag (a short tap still places).
		if
			input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			lastPos = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
			lastPos = nil
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if not active then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			distance = math.clamp(distance - input.Position.Z * 8, 30, 220)
		elseif
			dragging
			and lastPos
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			local delta = pos - lastPos
			lastPos = pos
			yaw -= delta.X * 0.008
			pitch = math.clamp(pitch + delta.Y * 0.006, math.rad(10), math.rad(80))
		end
	end)
	UserInputService.TouchPinch:Connect(function(_positions, scale, _velocity, inputState, processed)
		if not active or processed then
			return
		end
		if inputState == Enum.UserInputState.Begin then
			pinchStart = scale
			pinchDistance = distance
		elseif pinchStart then
			distance = math.clamp(pinchDistance / math.max(scale, 0.1), 30, 220)
		end
	end)

	-- A run or another mode needs the normal camera.
	State.Changed:Connect(function()
		if active and State.mode ~= "build" then
			CameraController.set(false)
		end
	end)

	RunService:BindToRenderStep("BuildCamera", Enum.RenderPriority.Camera.Value + 1, function()
		local camera = workspace.CurrentCamera
		local p = plot()
		if not active or not camera or not p then
			return
		end
		local origin = p:GetAttribute("Origin")
		if typeof(origin) ~= "Vector3" then
			return
		end
		local target = origin
			+ Vector3.new(
				Config.PLOT_CELLS_X * G / 2,
				math.min(towerTop() * 0.6, 200),
				Config.PLOT_CELLS_Z * G / 2
			)
		local offset = CFrame.Angles(0, yaw, 0) * CFrame.Angles(-pitch, 0, 0) * Vector3.new(0, 0, distance)
		camera.CFrame = CFrame.lookAt(target + offset, target)
	end)
end

return CameraController

--!strict
-- How the local character moves and feels in first person: sprint (Shift, L3 or
-- the touch button) with a FOV kick, head bob and wind streaks; visible arms that
-- follow the camera and pump while running; wall running (run along a wall
-- while airborne, jump to kick off); pushing other players (E or the touch button).
-- The server only checks pushes; movement physics is the client's anyway.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local CameraController = require(script.Parent.CameraController)

local MovementController = {}

local player = Players.LocalPlayer
local WALK = 16
local FOV, FOV_SPRINT = 70, 84
local WALLRUN_SPEED = 28
local WALLRUN_SECONDS = 1.0
local WALL_REACH = 3.2

local sprinting = false
local bobTime = 0
local fov = FOV
local wind: ParticleEmitter? = nil
local cursorFree = false -- Left Alt held: free the mouse in first person (menus)
local punchAt = 0 -- when the arms last shoved forward
local crosshair: Frame

type Wallrun = { normal: Vector3, along: Vector3, started: number, side: number }
local wallrun: Wallrun? = nil
local lastWall: Vector3? = nil -- can't wall run the same wall twice in a row
local roll = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function parts(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and humanoid and root and root:IsA("BasePart") and humanoid.Health > 0 then
		return character, humanoid, root
	end
	return nil, nil, nil
end

local function firstPerson(): boolean
	local camera = workspace.CurrentCamera
	local head = player.Character and player.Character:FindFirstChild("Head")
	return not CameraController.isActive()
		and camera ~= nil
		and head ~= nil
		and head:IsA("BasePart")
		and (camera.CFrame.Position - head.Position).Magnitude < 2
end

---------------------------------------------------------------- sprint

local function setSprint(on: boolean)
	sprinting = on
	local _, humanoid = parts()
	if humanoid then
		humanoid.WalkSpeed = if on then Config.SPRINT_SPEED else WALK
	end
end

local function onSprint(_name: string, state: Enum.UserInputState, input: InputObject)
	if input.UserInputType == Enum.UserInputType.Touch then
		if state == Enum.UserInputState.Begin then
			setSprint(not sprinting) -- the touch button toggles
		end
	else
		setSprint(state == Enum.UserInputState.Begin)
	end
	return Enum.ContextActionResult.Pass
end

---------------------------------------------------------------- push

local lastPush = 0
local function onPush(_name: string, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin and os.clock() - lastPush > 1 then
		lastPush = os.clock()
		Remotes.event("Push"):FireServer()
		punchAt = os.clock()
	end
	return Enum.ContextActionResult.Pass
end

---------------------------------------------------------------- wall running

-- A wall beside the character (left or right), facing it.
local function wallBeside(root: BasePart): (Vector3?, number)
	rayParams.FilterDescendantsInstances = { player.Character :: Model }
	for _, side in { -1, 1 } do
		local hit = workspace:Raycast(root.Position, root.CFrame.RightVector * side * WALL_REACH, rayParams)
		if hit and math.abs(hit.Normal.Y) < 0.3 and hit.Instance.CanCollide then
			return hit.Normal, side
		end
	end
	return nil, 0
end

local function stepWallrun(humanoid: Humanoid, root: BasePart)
	local run = wallrun
	local airborne = humanoid.FloorMaterial == Enum.Material.Air
	if run then
		local normal = wallBeside(root)
		local t = os.clock() - run.started
		if not airborne or not normal or t > WALLRUN_SECONDS or humanoid.MoveDirection.Magnitude < 0.3 then
			wallrun = nil
			return
		end
		-- Glide along the wall, sinking a little faster as it goes (AntiCheat
		-- only flags airtime that doesn't fall).
		root.AssemblyLinearVelocity = run.along * WALLRUN_SPEED
			+ Vector3.new(0, -2 - 10 * t / WALLRUN_SECONDS, 0)
			- run.normal * 2
		return
	end
	if not airborne or humanoid.MoveDirection.Magnitude < 0.5 or root.AssemblyLinearVelocity.Y > 20 then
		return
	end
	local normal, side = wallBeside(root)
	if not normal or (lastWall and normal:Dot(lastWall) > 0.95) then
		return
	end
	local along = humanoid.MoveDirection - normal * humanoid.MoveDirection:Dot(normal)
	if along.Magnitude < 0.4 then
		return -- running into the wall, not along it
	end
	wallrun = { normal = normal, along = along.Unit, started = os.clock(), side = side }
	lastWall = normal
end

---------------------------------------------------------------- arms

-- R15 shoulders, rest pose, so the arms can be raised into view.
type Arm = { motor: Motor6D, rest: CFrame, side: number }
local arms: { Arm } = {}

local function grabArms(character: Model)
	table.clear(arms)
	for _, info in { { "RightUpperArm", "RightShoulder", 1 }, { "LeftUpperArm", "LeftShoulder", -1 } } do
		local upper = character:WaitForChild(info[1], 5)
		local motor = upper and upper:FindFirstChild(info[2])
		if motor and motor:IsA("Motor6D") then
			table.insert(arms, { motor = motor, rest = motor.C0, side = info[3] :: number })
		end
	end
end

local function showArms(character: Model, humanoid: Humanoid, on: boolean)
	for _, d in character:GetChildren() do
		if d:IsA("BasePart") and (d.Name:find("Arm") or d.Name:find("Hand")) then
			d.LocalTransparencyModifier = if on then 0 else d.LocalTransparencyModifier
		end
	end
	local camera = workspace.CurrentCamera
	local pitch = if camera then math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1)) else 0
	local speed = if sprinting then 14 else 9
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local punch = math.max(0, 1 - (os.clock() - punchAt) / 0.25)
	for _, arm in arms do
		if on then
			-- Arms forward following the view, pumping while running.
			local swing = if moving
				then math.sin(bobTime * speed + (arm.side > 0 and 0 or math.pi)) * 0.35
				else 0
			arm.motor.C0 = arm.rest
				* CFrame.new(0, 0, -punch * 1.2)
				* CFrame.Angles(math.rad(80) + pitch + swing, 0, arm.side * math.rad(-12))
		else
			arm.motor.C0 = arm.rest
		end
	end
end
---------------------------------------------------------------- effects

local function makeWind(root: BasePart)
	local a = Instance.new("Attachment")
	a.Position = Vector3.new(0, 1.5, -3)
	a.Parent = root
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.new(1, 1, 1))
	e.LightEmission = 0.6
	e.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new(0.12)
	e.Lifetime = NumberRange.new(0.25, 0.4)
	e.Speed = NumberRange.new(40, 55)
	e.SpreadAngle = Vector2.new(35, 35)
	e.EmissionDirection = Enum.NormalId.Back
	e.Rate = 0
	e.Parent = a
	wind = e
end

local function freeCursorWanted(): boolean
	if cursorFree then
		return true
	end
	for _, gui in CollectionService:GetTagged("FreeCursor") do
		if gui:IsA("GuiObject") and gui.Visible then
			local screen = gui:FindFirstAncestorOfClass("ScreenGui")
			if screen and screen.Enabled then
				return true
			end
		end
	end
	return false
end

function MovementController.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Crosshair"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1
	crosshair = Instance.new("Frame")
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.Size = UDim2.fromOffset(6, 6)
	crosshair.BackgroundColor3 = Color3.new(1, 1, 1)
	crosshair.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = crosshair
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Parent = crosshair
	crosshair.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
end

function MovementController.start()
	ContextActionService:BindAction("Sprint", onSprint, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("Sprint", "Run")
	ContextActionService:SetPosition("Sprint", UDim2.new(1, -170, 1, -70))
	ContextActionService:BindAction("Push", onPush, true, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("Push", "Push")
	ContextActionService:SetPosition("Push", UDim2.new(1, -230, 1, -130))

	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftAlt then
			cursorFree = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftAlt then
			cursorFree = false
		end
	end)

	-- Kick off the wall: jump away from it and up.
	UserInputService.JumpRequest:Connect(function()
		local run = wallrun
		local _, _, root = parts()
		if run and root then
			wallrun = nil
			root.AssemblyLinearVelocity = run.normal * 34 + run.along * 18 + Vector3.new(0, 52, 0)
		end
	end)

	Remotes.event("Pushed").OnClientEvent:Connect(function(dir: any)
		local _, humanoid, root = parts()
		if typeof(dir) == "Vector3" and humanoid and root then
			local flat = Vector3.new(dir.X, 0, dir.Z)
			if flat.Magnitude > 0 then
				humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
				root.AssemblyLinearVelocity = flat.Unit * 55 + Vector3.new(0, 28, 0)
				Sounds.play("JumpPad")
			end
		end
	end)

	local function onCharacter(character: Model)
		wallrun = nil
		lastWall = nil
		setSprint(sprinting)
		task.spawn(grabArms, character)
		local root = character:WaitForChild("HumanoidRootPart", 5)
		if root and root:IsA("BasePart") then
			makeWind(root)
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	RunService.Heartbeat:Connect(function()
		local _, humanoid, root = parts()
		if not humanoid or not root then
			wallrun = nil
			return
		end
		if humanoid.FloorMaterial ~= Enum.Material.Air then
			lastWall = nil
		end
		stepWallrun(humanoid, root)
	end)

	-- After the camera scripts: FOV kick, head bob, wall-run tilt, arms, cursor.
	RunService:BindToRenderStep("Movement", Enum.RenderPriority.Camera.Value + 2, function(dt)
		local camera = workspace.CurrentCamera
		local character, humanoid, root = parts()
		if not camera or not character or not humanoid or not root then
			return
		end
		local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
		local running = sprinting and speed > 18
		bobTime += dt * (if humanoid.FloorMaterial ~= Enum.Material.Air then speed / 16 else 0)
		fov += ((if running or wallrun then FOV_SPRINT else FOV) - fov) * math.min(dt * 8, 1)
		local fp = firstPerson()
		if fp then
			camera.FieldOfView = fov
			local bob = if humanoid.FloorMaterial ~= Enum.Material.Air and speed > 2
				then CFrame.new(math.sin(bobTime * 5) * 0.06, math.abs(math.sin(bobTime * 5)) * 0.12, 0)
				else CFrame.identity
			local run = wallrun
			roll += ((if run then -run.side * math.rad(9) else 0) - roll) * math.min(dt * 10, 1)
			camera.CFrame = camera.CFrame * bob * CFrame.Angles(0, 0, roll)
		elseif not CameraController.isActive() then
			camera.FieldOfView = FOV
		end
		if wind then
			wind.Rate = if running or wallrun then 60 else 0
		end
		showArms(character, humanoid, fp)
		local free = fp and freeCursorWanted()
		if free then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end
		crosshair.Visible = fp and not free and UserInputService.MouseEnabled
	end)
end

return MovementController

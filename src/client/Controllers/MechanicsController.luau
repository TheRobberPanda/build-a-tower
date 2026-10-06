--!strict
-- Client side of jump pads: launch the local character immediately on touch.
-- The server registers the same speed as an AntiCheat allowance.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Sounds = require(ReplicatedStorage.Shared.Sounds)

local MechanicsController = {}

local player = Players.LocalPlayer
local lastLaunch = 0

local function onJumpPad(part: BasePart)
	part.Touched:Connect(function(hit)
		local character = player.Character
		if not character or not hit:IsDescendantOf(character) or os.clock() - lastLaunch < 0.4 then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return
		end
		lastLaunch = os.clock()
		local power = part:GetAttribute("power")
		local speed = Config.JUMP_PAD_SPEED[if type(power) == "number" then power else 1]
			or Config.JUMP_PAD_SPEED[1]
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, speed, v.Z)
		Sounds.play("JumpPad")
	end)
end

-- One-way walls: you may pass along Dir only. Character physics runs on the
-- client, so a local CanCollide change is all it takes.
local oneWays: { [BasePart]: boolean } = {}

local function updateOneWays()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	for part in oneWays do
		if not part.Parent then
			oneWays[part] = nil
			continue
		end
		local dir = part:GetAttribute("Dir")
		if typeof(dir) == "Vector3" then
			-- Passable from behind (entry side) and while inside; solid once you are
			-- fully on the exit side, so nobody can come back the other way.
			local along = (root.Position - part.Position):Dot(dir)
			part.CanCollide = along > Config.GRID_STUDS / 2
		end
	end
end

-- Secret pieces get their icon's particles, but only for the builder (others must find them).
local SECRET_FX: { [string]: Color3 } = {
	FakeWall = Color3.fromRGB(190, 110, 255), -- purple wisps
	InvisiblePlatform = Color3.fromRGB(210, 240, 255), -- frosty sparkles
}

local function onSecret(inst: Instance, color: Color3)
	local plot = inst:FindFirstAncestorOfClass("Model")
	if not inst:IsA("BasePart") or not plot or plot:GetAttribute("OwnerId") ~= player.UserId then
		return
	end
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Transparency = NumberSequence.new(0.3, 1)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(1, 1.6)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(30, 30)
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = 4
	e.Parent = inst
	-- A glowing outline so the builder always knows which piece is the secret.
	local box = Instance.new("SelectionBox")
	box.Adornee = inst
	box.Color3 = color
	box.LineThickness = 0.08
	box.SurfaceTransparency = 0.85
	box.SurfaceColor3 = color
	box.Parent = inst
	if inst.Name == "FakeWall" then
		inst.LocalTransparencyModifier = 0.45 -- see-through for the builder only
		for _, c in inst:GetChildren() do
			if c:IsA("Decal") then
				c.LocalTransparencyModifier = 0.45
			end
		end
	end
end

-- Stacked pieces with outline gaps read as ladder rungs to Roblox's auto-climb,
-- letting players scale any wall. Towers have stairs and ramps; no climbing.
local function noClimb(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	end
end

-- Cables from each button to the doors it opens (same channel, same tower).
local rewirePending: { [Instance]: boolean } = {}
local function rewire(folder: Instance)
	rewirePending[folder] = nil
	for _, c in folder:GetDescendants() do
		if c.Name == "Cable" then
			c:Destroy()
		end
	end
	for _, button in folder:GetChildren() do
		if not (button:IsA("BasePart") and button.Name == "Button") then
			continue
		end
		for _, door in folder:GetChildren() do
			if
				door:IsA("BasePart")
				and door.Name == "Door"
				and door:GetAttribute("ch") == button:GetAttribute("ch")
			then
				local a0 = Instance.new("Attachment")
				a0.Name = "Cable"
				a0.Parent = button
				local a1 = Instance.new("Attachment")
				a1.Name = "Cable"
				a1.Position = Vector3.new(0, -door.Size.Y / 2 + 0.3, 0)
				a1.Parent = door
				local beam = Instance.new("Beam")
				beam.Name = "Cable"
				beam.Attachment0 = a0
				beam.Attachment1 = a1
				beam.Color = ColorSequence.new(button.Color)
				beam.LightEmission = 0.6
				beam.Width0 = 0.25
				beam.Width1 = 0.25
				beam.FaceCamera = true
				beam.Parent = button
			end
		end
	end
end
local function wireLater(inst: Instance)
	local folder = inst.Parent
	if folder and not rewirePending[folder] then
		rewirePending[folder] = true
		task.delay(0.2, rewire, folder) -- a tower arrives part by part; wire once
	end
end

function MechanicsController.start()
	for _, tag in { "Button", "Door" } do
		CollectionService:GetInstanceAddedSignal(tag):Connect(wireLater)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(wireLater)
		for _, inst in CollectionService:GetTagged(tag) do
			wireLater(inst)
		end
	end
	player.CharacterAdded:Connect(noClimb)
	if player.Character then
		task.spawn(noClimb, player.Character)
	end
	for tag, color in SECRET_FX do
		for _, inst in CollectionService:GetTagged(tag) do
			onSecret(inst, color)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			onSecret(inst, color)
		end)
	end
	local function addOneWay(inst: Instance)
		if inst:IsA("BasePart") then
			oneWays[inst] = true
		end
	end
	for _, inst in CollectionService:GetTagged("OneWay") do
		addOneWay(inst)
	end
	CollectionService:GetInstanceAddedSignal("OneWay"):Connect(addOneWay)

	-- Conveyors: an anchored part's velocity doesn't replicate, and characters
	-- are simulated on the client, so set it here from the server's Dir attribute.
	local function addConveyor(inst: Instance)
		local dir = inst:GetAttribute("Dir")
		if inst:IsA("BasePart") and typeof(dir) == "Vector3" then
			inst.AssemblyLinearVelocity = dir * Config.CONVEYOR_SPEED
		end
	end
	for _, inst in CollectionService:GetTagged("Conveyor") do
		addConveyor(inst)
	end
	CollectionService:GetInstanceAddedSignal("Conveyor"):Connect(addConveyor)
	game:GetService("RunService").Heartbeat:Connect(updateOneWays)

	for _, part in CollectionService:GetTagged("JumpPad") do
		if part:IsA("BasePart") then
			onJumpPad(part)
		end
	end
	CollectionService:GetInstanceAddedSignal("JumpPad"):Connect(function(inst)
		if inst:IsA("BasePart") then
			onJumpPad(inst)
		end
	end)
end

return MechanicsController

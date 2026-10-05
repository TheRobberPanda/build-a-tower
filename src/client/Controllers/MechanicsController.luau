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

function MechanicsController.start()
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

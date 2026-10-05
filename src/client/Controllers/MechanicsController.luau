--!strict
-- Client side of jump pads: launch the local character immediately on touch.
-- The server registers the same speed as an AntiCheat allowance.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

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
	end)
end

function MechanicsController.start()
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

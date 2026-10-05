--!strict
-- Server side of secret mechanics. Jump pads: the client applies the launch for
-- responsiveness; the server just registers the matching AntiCheat allowance.
-- Teleporters: fully server-driven, linking to the next teleporter on the same channel.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local AntiCheat = require(script.Parent.AntiCheat)

local MechanicsService = {}

local lastTeleport: { [Player]: number } = {}

local function playerFromHit(hit: BasePart): Player?
	local model = hit:FindFirstAncestorOfClass("Model")
	return if model then Players:GetPlayerFromCharacter(model) else nil
end

local function onJumpPad(part: BasePart)
	part.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		if player then
			local power = part:GetAttribute("power")
			local speed = Config.JUMP_PAD_SPEED[if type(power) == "number" then power else 1]
				or Config.JUMP_PAD_SPEED[1]
			AntiCheat.expectLaunch(player, speed)
		end
	end)
end

-- Teleporters on the same channel within the same tower, in a stable order.
local function channelPeers(part: BasePart): { BasePart }
	local peers: { BasePart } = {}
	local folder = part.Parent
	if not folder then
		return peers
	end
	for _, other in folder:GetChildren() do
		if
			other:IsA("BasePart")
			and CollectionService:HasTag(other, "Teleporter")
			and other:GetAttribute("ch") == part:GetAttribute("ch")
		then
			table.insert(peers, other)
		end
	end
	table.sort(peers, function(a, b)
		local pa, pb = a.Position, b.Position
		if pa.Y ~= pb.Y then
			return pa.Y < pb.Y
		end
		if pa.X ~= pb.X then
			return pa.X < pb.X
		end
		return pa.Z < pb.Z
	end)
	return peers
end

local function onTeleporter(part: BasePart)
	part.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		local character = player and player.Character
		if not player or not character then
			return
		end
		local now = os.clock()
		if now - (lastTeleport[player] or 0) < Config.TELEPORT_COOLDOWN then
			return
		end
		local peers = channelPeers(part)
		local index = table.find(peers, part)
		if not index or #peers < 2 then
			return
		end
		local dest = peers[index % #peers + 1]
		lastTeleport[player] = now
		local target = dest.Position + Vector3.new(0, dest.Size.Y / 2 + 3, 0)
		AntiCheat.expectTeleport(player, target)
		character:PivotTo(CFrame.new(target))
	end)
end

function MechanicsService.init()
	CollectionService:GetInstanceAddedSignal("JumpPad"):Connect(function(inst)
		if inst:IsA("BasePart") then
			onJumpPad(inst)
		end
	end)
	CollectionService:GetInstanceAddedSignal("Teleporter"):Connect(function(inst)
		if inst:IsA("BasePart") then
			onTeleporter(inst)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastTeleport[player] = nil
	end)
end

return MechanicsService

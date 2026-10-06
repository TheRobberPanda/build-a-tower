--!strict
-- Server side of secret mechanics. Jump pads: the client applies the launch for
-- responsiveness; the server just registers the matching AntiCheat allowance.
-- Teleporters: fully server-driven, linking to the next teleporter on the same channel.
-- Crumble platforms and button-opened doors are server-driven too: every racer
-- climbs their own copy of a tower on their own plot, so changing a part only
-- affects that racer.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local PieceVisuals = require(ReplicatedStorage.Shared.PieceVisuals)
local AntiCheat = require(script.Parent.AntiCheat)

local MechanicsService = {}

-- (player, kind) whenever someone uses a secret: FakeWall, InvisiblePlatform,
-- Teleporter, JumpPad, Button. RunTimerService records these during runs.
local secretUsed = Instance.new("BindableEvent")
MechanicsService.SecretUsed = secretUsed.Event

local function used(player: Player, kind: string)
	secretUsed:Fire(player, kind)
end

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
			used(player, "JumpPad")
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
		Sounds.play("Teleport", dest)
		used(player, "Teleporter")
	end)
end

-- Walking through a fake wall or standing on an invisible platform.
local function onPassive(kind: string): (BasePart) -> ()
	return function(part: BasePart)
		part.Touched:Connect(function(hit)
			local player = playerFromHit(hit)
			if player then
				used(player, kind)
			end
		end)
	end
end

local function onCrumble(part: BasePart)
	local busy = false
	part.Touched:Connect(function(hit)
		if busy or not playerFromHit(hit) then
			return
		end
		busy = true
		PieceVisuals.tremble(part, Config.CRUMBLE_DELAY)
		task.delay(Config.CRUMBLE_DELAY, function()
			if not part.Parent then
				return
			end
			PieceVisuals.shatter(part)
			part.Transparency = 1
			part.CanCollide = false
			Sounds.play("Crumble", part)
			task.delay(Config.CRUMBLE_RESPAWN, function()
				if part.Parent then
					part.Transparency = 0
					part.CanCollide = true
				end
				busy = false
			end)
		end)
	end)
end

local openUntil: { [Instance]: number } = {} -- door folder+channel key -> time

local function setDoors(folder: Instance, ch: any, open: boolean)
	for _, other in folder:GetChildren() do
		if other:IsA("BasePart") and other.Name == "Door" and other:GetAttribute("ch") == ch then
			other.CanCollide = not open
			other.Transparency = if open then 0.75 else 0
		end
	end
end

-- The round cap (decoration) sinks while the button holds its doors open.
local function pressCap(part: BasePart, down: boolean)
	for _, c in part:GetChildren() do
		if c:IsA("BasePart") and c.Material == Enum.Material.Neon then
			c.CFrame += Vector3.new(0, if down then -0.25 else 0.25, 0)
		end
	end
end

local function onButton(part: BasePart)
	part.Touched:Connect(function(hit)
		local folder = part.Parent
		if not folder or not playerFromHit(hit) then
			return
		end
		used(playerFromHit(hit) :: Player, "Button")
		local ch = part:GetAttribute("ch")
		local untilTime = os.clock() + Config.DOOR_OPEN_SECONDS
		if not openUntil[part] then
			Sounds.play("Door", part) -- only when the doors actually open
			pressCap(part, true)
		end
		openUntil[part] = untilTime
		setDoors(folder, ch, true)
		task.delay(Config.DOOR_OPEN_SECONDS, function()
			if openUntil[part] == untilTime then
				openUntil[part] = nil
				if part.Parent then
					setDoors(folder, ch, false)
					pressCap(part, false)
				end
			end
		end)
	end)
	part.Destroying:Connect(function()
		openUntil[part] = nil
	end)
end

-- Traps knock you out: the run respawns you at your last checkpoint.
local function onTrap(part: BasePart)
	part.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		local humanoid = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
			Sounds.play("Fail", part)
		end
	end)
end

-- Shoves the nearest player in front of you (not during runs: those are timed
-- and AntiCheat-checked, and racers can't reach each other anyway).
local lastPush: { [Player]: number } = {}
local function onPush(player: Player)
	local now = os.clock()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if
		not root
		or not root:IsA("BasePart")
		or now - (lastPush[player] or 0) < 0.9
		or AntiCheat.isWatched(player)
	then
		return
	end
	lastPush[player] = now
	local best: Player? = nil
	local bestDist = 8
	for _, other in Players:GetPlayers() do
		local r = other ~= player and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if r and r:IsA("BasePart") and not AntiCheat.isWatched(other) then
			local offset = r.Position - root.Position
			local d = offset.Magnitude
			if d < bestDist and d > 0 and offset.Unit:Dot(root.CFrame.LookVector) > 0.3 then
				best, bestDist = other, d
			end
		end
	end
	local target = best
	if target then
		Remotes.event("Pushed"):FireClient(target, root.CFrame.LookVector)
	end
end

function MechanicsService.init()
	Remotes.event("Push").OnServerEvent:Connect(onPush)
	Players.RespawnTime = 1.5 -- traps and falls are part of play; get back quickly
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
	local handlers: { [string]: (BasePart) -> () } = {
		Crumble = onCrumble,
		Button = onButton,
		Spikes = onTrap,
		Lava = onTrap,
		FakeWall = onPassive("FakeWall"),
		InvisiblePlatform = onPassive("InvisiblePlatform"),
	}
	for tag, handler in handlers do
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			if inst:IsA("BasePart") then
				handler(inst)
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastTeleport[player] = nil
		lastPush[player] = nil
	end)
end

return MechanicsService

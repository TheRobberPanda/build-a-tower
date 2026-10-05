--!strict
-- Samples character positions during runs and flags implausible movement.
-- Never checks the route. Jump pads/teleporters register allowances first.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MovementCheck = require(script.Parent.Parent.Lib.MovementCheck)

local AntiCheat = {}

type Watch = {
	allow: MovementCheck.Allowance,
	last: Vector3?,
	lastAt: number,
	flags: number,
	onFail: (reason: string) -> (),
}

local watched: { [Player]: Watch } = {}
local allowances: { [Player]: MovementCheck.Allowance } = {}

local function allowanceFor(player: Player): MovementCheck.Allowance
	local a = allowances[player]
	if not a then
		a = MovementCheck.newAllowance()
		allowances[player] = a
	end
	return a
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- A jump pad launched this player: allow extra rise for a short window.
function AntiCheat.expectLaunch(player: Player, speed: number)
	local a = allowanceFor(player)
	a.launchSpeed = math.max(speed, if os.clock() <= a.launchUntil then a.launchSpeed else 0)
	a.launchUntil = os.clock() + 2.5
end

-- The server is about to move this player to `position`.
function AntiCheat.expectTeleport(player: Player, position: Vector3)
	local a = allowanceFor(player)
	a.teleportTo = position
	a.teleportUntil = os.clock() + 2
	local w = watched[player]
	if w then
		w.last = nil -- restart sampling from the destination
	end
end

-- Start checking. `onFail` is called once when flags reach the limit.
function AntiCheat.watch(player: Player, onFail: (string) -> ())
	watched[player] = { allow = allowanceFor(player), lastAt = os.clock(), flags = 0, onFail = onFail }
end

function AntiCheat.unwatch(player: Player)
	watched[player] = nil
end

function AntiCheat.init()
	Players.PlayerRemoving:Connect(function(player)
		watched[player] = nil
		allowances[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.AC_SAMPLE_SECONDS)
			local now = os.clock()
			for player, w in watched do
				local root = rootOf(player)
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if not root or not humanoid then
					continue
				end
				local pos = root.Position
				local last = w.last
				if last then
					local reason = MovementCheck.check(last, pos, now - w.lastAt, now, w.allow, {
						walkSpeed = humanoid.WalkSpeed,
						maxRiseSpeed = Config.AC_MAX_RISE_SPEED,
						speedFactor = Config.AC_SPEED_FACTOR,
						speedSlack = Config.AC_SPEED_SLACK,
						teleportRadius = Config.AC_TELEPORT_RADIUS,
					})
					if reason then
						w.flags += 1
						warn(string.format("[AntiCheat] %s flagged (%d): %s", player.Name, w.flags, reason))
						if w.flags >= Config.AC_FLAGS_TO_FAIL then
							watched[player] = nil
							task.spawn(w.onFail, reason)
							continue
						end
					end
				end
				w.last = pos
				w.lastAt = now
			end
		end
	end)
end

return AntiCheat

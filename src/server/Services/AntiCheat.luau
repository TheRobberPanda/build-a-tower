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
	cleanSince: number,
	hover: MovementCheck.Hover,
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
	watched[player] = {
		allow = allowanceFor(player),
		lastAt = os.clock(),
		flags = 0,
		cleanSince = os.clock(),
		hover = {},
		onFail = onFail,
	}
end

function AntiCheat.isWatched(player: Player): boolean
	return watched[player] ~= nil
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
				if not root or not humanoid or humanoid.Health <= 0 then
					w.last = nil -- dead bodies ragdoll; resume from the respawn
					continue
				end
				local pos = root.Position
				local last = w.last
				if last then
					local reason = MovementCheck.check(last, pos, now - w.lastAt, now, w.allow, {
						-- Sprint is client-side and conveyors push on top of it.
						walkSpeed = math.max(humanoid.WalkSpeed, Config.SPRINT_SPEED),
						maxRiseSpeed = Config.AC_MAX_RISE_SPEED,
						speedFactor = Config.AC_SPEED_FACTOR,
						speedSlack = Config.AC_SPEED_SLACK + Config.CONVEYOR_SPEED,
						teleportRadius = Config.AC_TELEPORT_RADIUS,
					}) or MovementCheck.hover(
						w.hover,
						humanoid.FloorMaterial == Enum.Material.Air,
						pos.Y - last.Y,
						now,
						now <= w.allow.launchUntil,
						Config.AC_HOVER_SECONDS
					)
					if reason then
						w.flags += 1
						w.cleanSince = now
						warn(string.format("[AntiCheat] %s flagged (%d): %s", player.Name, w.flags, reason))
						if w.flags >= Config.AC_FLAGS_TO_FAIL then
							watched[player] = nil
							task.spawn(w.onFail, reason)
							continue
						end
					elseif w.flags > 0 and now - w.cleanSince >= Config.AC_FLAG_DECAY_SECONDS then
						w.flags -= 1
						w.cleanSince = now
					end
				end
				w.last = pos
				w.lastAt = now
			end
		end
	end)
end

return AntiCheat

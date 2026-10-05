--!strict
-- Server-timed runs. A run on your own tower is a verification run: finishing it
-- marks that exact tower hash as verified (required to publish). A run on someone
-- else's published tower submits a time to that tower's leaderboard.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PieceDefs = require(ReplicatedStorage.Shared.PieceDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TowerCodec = require(ReplicatedStorage.Shared.TowerCodec)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local AntiCheat = require(script.Parent.AntiCheat)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local TowerService = require(script.Parent.TowerService)

local RunTimerService = {}

type Run = { ownerId: number, hash: string, startedAt: number, conn: RBXScriptConnection? }
local runs: { [Player]: Run } = {}
local startLimiter = RateLimiter.new(2, 1 / 3)

local function restoreOwnTower(player: Player)
	local data = DataService.get(player)
	if data then
		PlotService.render(player, data.tower.pieces)
	end
end

local function endRun(player: Player)
	local run = runs[player]
	if run and run.conn then
		run.conn:Disconnect()
	end
	runs[player] = nil
	AntiCheat.unwatch(player)
	TowerService.setEditLocked(player, false)
end

local function finish(player: Player, run: Run)
	local ms = math.floor((os.clock() - run.startedAt) * 1000)
	endRun(player)
	if ms < Config.MIN_RUN_MS or ms > Config.MAX_RUN_MS then
		Remotes.event("RunResult"):FireClient(player, false, ms, false)
		return
	end
	if run.ownerId == player.UserId then
		local data = DataService.get(player)
		-- Only verify if the tower is still exactly the one that was climbed.
		if data and TowerCodec.hash(data.tower) == run.hash then
			data.verifiedHash = run.hash
		end
		Remotes.event("RunResult"):FireClient(player, true, ms, false)
		Remotes.event("TowerChanged")
			:FireClient(player, data and data.tower, data and data.verifiedHash ~= nil)
	else
		local improved = TowerService.published():submitTime(run.ownerId, run.hash, player.UserId, ms)
		Remotes.event("RunResult"):FireClient(player, true, ms, improved)
		restoreOwnTower(player)
	end
end

local function onStartRun(player: Player, ownerId: any)
	if not startLimiter:allow(player) then
		return
	end
	if
		type(ownerId) ~= "number"
		or ownerId ~= ownerId
		or ownerId % 1 ~= 0
		or ownerId < 1
		or ownerId > 2 ^ 53
	then
		return
	end
	local character = player.Character
	local plot = PlotService.get(player)
	if not character or not plot then
		return
	end
	if runs[player] then
		endRun(player)
		restoreOwnTower(player)
	end

	local hash: string
	local towerName: string
	if ownerId == player.UserId then
		local data = DataService.get(player)
		if not data then
			return
		end
		local valid, err = TowerCodec.validate(data.tower)
		if not valid then
			local msg = if err == "no finish" then "Place a Finish piece first" else "Tower is not valid"
			Remotes.event("RunResult"):FireClient(player, false, 0, false, msg)
			return
		end
		hash = TowerCodec.hash(data.tower)
		towerName = data.towerName
		PlotService.render(player, data.tower.pieces)
	else
		local tower = TowerService.getPublished(ownerId)
		if not tower then
			return
		end
		hash = tower.hash
		towerName = tower.name
		PlotService.render(player, tower.pieces)
	end

	local run: Run = { ownerId = ownerId, hash = hash, startedAt = os.clock() }
	runs[player] = run
	TowerService.setEditLocked(player, true)

	local pieces = plot.model:FindFirstChild("Pieces")
	for _, part in if pieces then pieces:GetChildren() else {} do
		if part:IsA("BasePart") and part:GetAttribute("PieceType") == PieceDefs.FINISH_ID then
			run.conn = part.Touched:Connect(function(hit)
				if runs[player] == run and hit:IsDescendantOf(character) then
					finish(player, run)
				end
			end)
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Once(function()
			if runs[player] == run then
				endRun(player)
				restoreOwnTower(player)
				Remotes.event("RunResult"):FireClient(player, false, 0, false, "You died, run over")
			end
		end)
	end

	local spawn = PlotService.spawnCFrame(player)
	if spawn then
		AntiCheat.expectTeleport(player, spawn.Position)
		character:PivotTo(spawn)
	end
	AntiCheat.watch(player, function(reason)
		if runs[player] == run then
			endRun(player)
			restoreOwnTower(player)
			Remotes.event("RunResult"):FireClient(player, false, 0, false, "Run invalid: " .. reason)
		end
	end)
	run.startedAt = os.clock() -- start after the teleport
	Remotes.event("RunStarted"):FireClient(player, ownerId, towerName)
end

local function onStopRun(player: Player)
	if runs[player] and startLimiter:allow(player) then
		endRun(player)
		restoreOwnTower(player)
		Remotes.event("RunResult"):FireClient(player, false, 0, false)
	end
end

function RunTimerService.isRunning(player: Player): boolean
	return runs[player] ~= nil
end

function RunTimerService.init()
	Remotes.event("StartRun").OnServerEvent:Connect(onStartRun)
	Remotes.event("StopRun").OnServerEvent:Connect(onStopRun)
	Players.PlayerRemoving:Connect(function(player)
		endRun(player)
		startLimiter:forget(player)
	end)
end

return RunTimerService

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
local Analytics = require(script.Parent.Analytics)
local AntiCheat = require(script.Parent.AntiCheat)
local Badges = require(script.Parent.Badges)
local MechanicsService = require(script.Parent.MechanicsService)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local TowerService = require(script.Parent.TowerService)

local RunTimerService = {}

type Run = {
	ownerId: number,
	hash: string,
	startedAt: number,
	conn: RBXScriptConnection?,
	used: { [string]: boolean }, -- secret kinds used this run
}
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
			Analytics.step(player, "Verified")
		end
		Remotes.event("RunResult"):FireClient(player, true, ms, false)
		Remotes.event("TowerChanged")
			:FireClient(player, data and data.tower, data and data.verifiedHash ~= nil)
	else
		Analytics.event(player, "RaceFinished", ms / 1000)
		local usedList: { string } = {}
		for kind in run.used do
			table.insert(usedList, kind)
			local badge = Config.SECRET_BADGES[kind]
			if badge then
				Badges.award(player, badge)
			end
		end
		Badges.award(player, "FirstRace")
		local data = DataService.get(player)
		if data then
			data.secretsFound += #usedList
			if data.secretsFound >= Config.SECRET_HUNTER_COUNT then
				Badges.award(player, "SecretHunter")
			end
		end
		-- Compare against stats before this finish is counted.
		local before = TowerService.stats(run.ownerId, run.hash)
		if not before.best or ms < before.best then
			Badges.award(player, "RecordHolder")
		end
		TowerService.recordFinish(player, run.ownerId, run.hash, ms, usedList)
		local improved, previous = TowerService.published()
			:submitTime(run.ownerId, run.hash, player.UserId, ms)
		local canLike = not TowerService.hasLiked(player, run.ownerId, run.hash)
		-- How the racer compares: average time and how often each secret is found.
		local foundPct: { [string]: number } = {}
		for kind, n in before.found do
			foundPct[kind] = math.floor(n / math.max(before.finishes, 1) * 100 + 0.5)
		end
		local info = {
			average = if before.finishes > 0 then math.floor(before.sumMs / before.finishes) else nil,
			used = usedList,
			foundPct = foundPct,
			finishes = before.finishes,
		}
		Remotes.event("RunResult"):FireClient(player, true, ms, improved, nil, previous, canLike, info)
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

	local run: Run = { ownerId = ownerId, hash = hash, startedAt = os.clock(), used = {} }
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
	if ownerId == player.UserId then
		Analytics.step(player, "StartedTestRun")
	else
		Analytics.event(player, "RaceStarted")
		TowerService.recordStart(ownerId, hash)
	end
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
	MechanicsService.SecretUsed:Connect(function(player: Player, kind: string)
		local run = runs[player]
		if run then
			run.used[kind] = true
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		endRun(player)
		startLimiter:forget(player)
	end)
end

return RunTimerService

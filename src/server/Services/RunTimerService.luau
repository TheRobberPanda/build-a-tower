--!strict
-- Server-timed runs. A run on your own tower is a verification run: finishing it
-- marks that exact tower hash as verified (required to publish). A run on someone
-- else's published tower submits a time to that tower's leaderboard.
-- Runs record the racer's path (for ghosts and replays) and split times at
-- checkpoints; dying after a checkpoint respawns there with the timer running.
-- Watching a replay renders the tower on your plot without a run.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(ReplicatedStorage.Shared.Config)
local PathCodec = require(ReplicatedStorage.Shared.PathCodec)
local PieceDefs = require(ReplicatedStorage.Shared.PieceDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TowerCodec = require(ReplicatedStorage.Shared.TowerCodec)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local ReplayStore = require(script.Parent.Parent.Lib.ReplayStore)
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
	conns: { RBXScriptConnection },
	used: { [string]: boolean }, -- secret kinds used this run
	path: { Vector3 }, -- plot-relative samples
	splits: { number }, -- ms at each new checkpoint
	reached: { [BasePart]: boolean },
}

local runs: { [Player]: Run } = {}
local watching: { [Player]: boolean } = {}
local startLimiter = RateLimiter.new(2, 1 / 3)
local replayLimiter = RateLimiter.new(6, 1 / 5)
local replays: ReplayStore.ReplayStore

local function isId(n: any): boolean
	return type(n) == "number" and n == n and n % 1 == 0 and n >= 0 and n <= 2 ^ 53
end

local function restoreOwnTower(player: Player)
	local data = DataService.get(player)
	if data then
		PlotService.render(player, data.tower.pieces, data.material)
	end
end

local function endRun(player: Player)
	local run = runs[player]
	if run then
		for _, conn in run.conns do
			conn:Disconnect()
		end
	end
	runs[player] = nil
	PlotService.setRespawn(player, nil)
	AntiCheat.unwatch(player)
	TowerService.setEditLocked(player, watching[player] == true)
end

local function saveReplay(player: Player, run: Run, ms: number)
	local path = PathCodec.encode(run.path)
	task.spawn(function()
		replays:save(run.ownerId, run.hash, player.UserId, ms, path, run.splits)
	end)
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
			saveReplay(player, run, ms) -- the builder's run, watchable once published
		end
		Remotes.event("RunResult"):FireClient(player, true, ms, false)
		Remotes.event("TowerChanged")
			:FireClient(player, data and data.tower, data and data.verifiedHash ~= nil)
		return
	end

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
	local improved, previous = TowerService.published():submitTime(run.ownerId, run.hash, player.UserId, ms)
	if improved then
		saveReplay(player, run, ms)
	end
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
		splits = run.splits,
	}
	Remotes.event("RunResult"):FireClient(player, true, ms, improved, nil, previous, canLike, info)
	restoreOwnTower(player)
end

local function fail(player: Player, run: Run, message: string?)
	if runs[player] == run then
		endRun(player)
		restoreOwnTower(player)
		Remotes.event("RunResult"):FireClient(player, false, 0, false, message)
	end
end

-- Died: back to the last checkpoint if there is one, otherwise the run is over.
local function hookCharacter(player: Player, run: Run, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	table.insert(
		run.conns,
		humanoid.Died:Once(function()
			if runs[player] ~= run then
				return
			end
			if next(run.reached) == nil then
				fail(player, run, "You died, run over")
			end
			-- Otherwise PlotService respawns the character at the checkpoint.
		end)
	)
end

local function onCharacterAdded(player: Player, character: Model)
	local run = runs[player]
	if not run then
		return
	end
	hookCharacter(player, run, character)
	local cf = PlotService.respawnFor(player)
	if cf then
		AntiCheat.expectTeleport(player, cf.Position)
	end
end

local function hookPieces(player: Player, run: Run, pieces: Instance)
	for _, part in pieces:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		local t = part:GetAttribute("PieceType")
		local def = if type(t) == "number" then PieceDefs.byId[t] else nil
		if t == PieceDefs.FINISH_ID then
			table.insert(
				run.conns,
				part.Touched:Connect(function(hit)
					local character = player.Character
					if runs[player] == run and character and hit:IsDescendantOf(character) then
						finish(player, run)
					end
				end)
			)
		elseif def and def.name == "Checkpoint" then
			table.insert(
				run.conns,
				part.Touched:Connect(function(hit)
					local character = player.Character
					if runs[player] ~= run or not character or not hit:IsDescendantOf(character) then
						return
					end
					PlotService.setRespawn(player, part.CFrame + Vector3.new(0, 4, 0))
					if not run.reached[part] then
						run.reached[part] = true
						local ms = math.floor((os.clock() - run.startedAt) * 1000)
						table.insert(run.splits, ms)
						Remotes.event("Split"):FireClient(player, #run.splits, ms)
					end
				end)
			)
		end
	end
end

local function stopWatching(player: Player)
	if watching[player] then
		watching[player] = nil
		TowerService.setEditLocked(player, runs[player] ~= nil)
		if not runs[player] then
			restoreOwnTower(player)
		end
	end
end

local function onStartRun(player: Player, ownerId: any)
	if not startLimiter:allow(player) or not isId(ownerId) or ownerId < 1 then
		return
	end
	local character = player.Character
	local plot = PlotService.get(player)
	if not character or not plot then
		return
	end
	stopWatching(player)
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
		PlotService.render(player, data.tower.pieces, data.material)
	else
		local tower = TowerService.getPublished(ownerId)
		if not tower then
			return
		end
		hash = tower.hash
		towerName = tower.name
		PlotService.render(player, tower.pieces, tower.mat)
	end

	local run: Run = {
		ownerId = ownerId,
		hash = hash,
		startedAt = os.clock(),
		conns = {},
		used = {},
		path = {},
		splits = {},
		reached = {},
	}
	runs[player] = run
	TowerService.setEditLocked(player, true)

	local pieces = plot.model:FindFirstChild("Pieces")
	if pieces then
		hookPieces(player, run, pieces)
	end
	hookCharacter(player, run, character)

	local spawn = PlotService.spawnCFrame(player)
	if spawn then
		AntiCheat.expectTeleport(player, spawn.Position)
		character:PivotTo(spawn)
	end
	AntiCheat.watch(player, function(reason)
		fail(player, run, "Run invalid: " .. reason)
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

-- racerId 0 = the tower's record holder. Returns { racer, ms, path, splits } or nil.
local function findReplay(ownerId: number, racerId: number): { [string]: any }?
	local tower = TowerService.getPublished(ownerId)
	if not tower then
		return nil
	end
	local racer = racerId
	if racer == 0 then
		local top = TowerService.published():topTimes(ownerId, tower.hash, 1)
		local first = top and top[1]
		racer = if first then tonumber(first.key) or 0 else 0
		if racer == 0 then
			return nil
		end
	end
	local replay = replays:get(ownerId, tower.hash, racer)
	if not replay then
		return nil
	end
	return { racer = racer, ms = replay.ms, path = replay.path, splits = replay.splits }
end

local function onGetReplay(player: Player, ownerId: any, racerId: any): { [string]: any }?
	if not replayLimiter:allow(player) or not isId(ownerId) or not isId(racerId) then
		return nil
	end
	return findReplay(ownerId, racerId)
end

-- Renders the tower on your plot and returns the replay; the client plays it back.
local function onWatchReplay(player: Player, ownerId: any, racerId: any): { [string]: any }?
	if not replayLimiter:allow(player) or not isId(ownerId) or not isId(racerId) or runs[player] then
		return nil
	end
	local replay = findReplay(ownerId, racerId)
	local tower = replay and TowerService.getPublished(ownerId)
	if not replay or not tower then
		return nil
	end
	watching[player] = true
	TowerService.setEditLocked(player, true)
	PlotService.render(player, tower.pieces, tower.mat)
	return replay
end

function RunTimerService.isRunning(player: Player): boolean
	return runs[player] ~= nil
end

function RunTimerService.init()
	replays = ReplayStore.new({
		store = DataStoreService:GetDataStore(Config.REPLAYS_STORE),
		wait = task.wait,
		log = function(msg)
			warn("[Replays] " .. msg)
		end,
	})
	Remotes.event("StartRun").OnServerEvent:Connect(onStartRun)
	Remotes.event("StopRun").OnServerEvent:Connect(onStopRun)
	Remotes.event("StopWatch").OnServerEvent:Connect(stopWatching)
	Remotes.func("GetReplay").OnServerInvoke = onGetReplay
	Remotes.func("WatchReplay").OnServerInvoke = onWatchReplay
	MechanicsService.SecretUsed:Connect(function(player: Player, kind: string)
		local run = runs[player]
		if run then
			run.used[kind] = true
		end
	end)
	local function added(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end
	Players.PlayerAdded:Connect(added)
	for _, p in Players:GetPlayers() do
		added(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		endRun(player)
		watching[player] = nil
		startLimiter:forget(player)
		replayLimiter:forget(player)
	end)

	-- Path recording for every active run.
	task.spawn(function()
		while true do
			task.wait(Config.PATH_SAMPLE_SECONDS)
			for player, run in runs do
				local plot = PlotService.get(player)
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if plot and root and root:IsA("BasePart") and #run.path < Config.PATH_MAX_SAMPLES then
					table.insert(run.path, root.Position - plot.origin)
				end
			end
		end
	end)
end

return RunTimerService

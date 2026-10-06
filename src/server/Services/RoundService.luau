--!strict
-- Round mode: one round at a time per server (servers hold up to 6 players).
-- Waiting -> Intermission -> Build (shared clock: build, then climb your own
-- tower) -> for each valid tower: Race (everyone else, first to the top wins,
-- builder wins if nobody does) then Vote (replay of the builder's verify climb,
-- 1-5 stars, donations) -> Results (coins, good towers get published).
-- Players who join mid-round build freely on their own plot until the next one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TowerCodec = require(ReplicatedStorage.Shared.TowerCodec)
local Types = require(ReplicatedStorage.Shared.Types)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local DataService = require(script.Parent.DataService)
local LiveRaceService = require(script.Parent.LiveRaceService)
local PlotService = require(script.Parent.PlotService)
local ProgressionService = require(script.Parent.ProgressionService)
local RunTimerService = require(script.Parent.RunTimerService)
local SocialService = require(script.Parent.SocialService)
local TowerService = require(script.Parent.TowerService)

local RoundService = {}

type Entry = {
	player: Player,
	name: string,
	coins: number,
	wins: number,
	valid: boolean,
	tower: Types.PublishedTower?,
	replay: { path: string, splits: { number }, ms: number }?,
	stars: { [Player]: number },
	donated: { [Player]: boolean },
}

local phase = "waiting"
local entries: { Entry } = {}
local entryOf: { [Player]: Entry } = {}
local state: { [string]: any } = { phase = "waiting" }
local roundTowers: { [number]: Types.PublishedTower } = {}
local shown: Entry? = nil -- tower being raced or voted on
local raceWinner: Player? = nil
local limiter = RateLimiter.new(4, 1)
local sitOut: { [Player]: boolean } = {}

local function seconds(s: number): number
	if RunService:IsStudio() and ServerStorage:GetAttribute("RoundFast") == true then
		return math.max(3, s / 10)
	end
	return s
end

local function broadcast(newPhase: string, duration: number, extra: { [string]: any }?)
	phase = newPhase
	state = extra or {}
	state.phase = newPhase
	state.endsAt = workspace:GetServerTimeNow() + duration
	state.players = #entries
	local members = {}
	for _, e in entries do
		table.insert(members, e.player.UserId)
	end
	state.members = members
	Remotes.event("Round"):FireAllClients(state)
	if RunService:IsStudio() and ServerStorage:GetAttribute("RunQA") ~= nil then
		print(string.format("[Round] %s members=%d builder=%s", newPhase, #members, tostring(state.builder)))
	end
end

local function present(e: Entry): boolean
	return e.player.Parent == Players and entryOf[e.player] == e
end

local function anyPresent(): boolean
	for _, e in entries do
		if present(e) then
			return true
		end
	end
	return false
end

local function give(e: Entry, coins: number)
	e.coins += coins
	local data = DataService.get(e.player)
	if data and coins > 0 then
		data.bricks += coins
		data.xp += coins
		ProgressionService.refresh(e.player)
	end
end

-- Waits until the clock runs out, everyone left, or stop() says so.
local function waitPhase(duration: number, stop: (() -> boolean)?)
	local ends = os.clock() + duration
	while os.clock() < ends and anyPresent() and not (stop and stop()) do
		task.wait(0.25)
	end
end

local function loadedPlayers(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if DataService.get(p) and p.Character and not sitOut[p] then
			table.insert(list, p)
		end
	end
	return list
end

local function startBuild(): boolean
	table.clear(entries)
	table.clear(entryOf)
	for _, p in loadedPlayers() do
		RunTimerService.stop(p, "A round is starting")
		if TowerService.enterRound(p) then
			local e: Entry = {
				player = p,
				name = p.DisplayName,
				coins = 0,
				wins = 0,
				valid = false,
				stars = {},
				donated = {},
			}
			table.insert(entries, e)
			entryOf[p] = e
			local spawn = PlotService.spawnCFrame(p)
			local character = p.Character
			if spawn and character then
				character:PivotTo(spawn)
			end
		end
	end
	return #entries > 0
end

local function endBuild()
	for _, e in entries do
		if not present(e) then
			continue
		end
		local p = e.player
		RunTimerService.stop(p, "Time's up")
		TowerService.setEditLocked(p, true)
		local data = DataService.get(p)
		local replay = RunTimerService.verifyReplay(p)
		if data and data.verifiedHash and data.verifiedHash == TowerCodec.hash(data.tower) and replay then
			e.valid = true
			e.replay = replay
			local tower: Types.PublishedTower = {
				v = data.tower.v,
				owner = p.UserId,
				name = e.name .. "'s tower",
				hash = data.verifiedHash,
				pieces = data.tower.pieces,
				publishedAt = 0,
				mat = data.material,
				builderMs = data.verifiedMs,
			}
			e.tower = tower
			roundTowers[p.UserId] = tower
			give(e, Config.COINS_VALID)
		end
	end
end

local function race(e: Entry, index: number, count: number): Entry?
	local tower = e.tower :: Types.PublishedTower
	local racers = {}
	for _, other in entries do
		if other ~= e and present(other) then
			table.insert(racers, other.player)
		end
	end
	if #racers == 0 then
		return nil -- alone: nobody to race
	end
	shown = e
	raceWinner = nil
	broadcast("race", seconds(Config.RACE_SECONDS), {
		builder = e.player.UserId,
		builderName = e.name,
		index = index,
		count = count,
	})
	LiveRaceService.startRound(tower.owner, tower.name, racers, { e.player })
	waitPhase(seconds(Config.RACE_SECONDS), function()
		return raceWinner ~= nil
	end)
	for _, p in racers do
		RunTimerService.stop(
			p,
			if raceWinner then raceWinner.DisplayName .. " reached the top first" else "Time's up"
		)
	end
	local winner = raceWinner and entryOf[raceWinner]
	if winner then
		winner.wins += 1
		give(winner, Config.COINS_RACE_WIN)
	else
		e.wins += 1
		give(e, Config.COINS_BUILDER_WIN)
	end
	return winner
end

local function vote(e: Entry, winner: Entry?)
	local tower = e.tower :: Types.PublishedTower
	shown = e
	broadcast("vote", seconds(Config.VOTE_SECONDS), {
		builder = e.player.UserId,
		builderName = e.name,
		winnerName = winner and winner.name,
	})
	for _, other in entries do
		if present(other) then
			PlotService.render(other.player, tower.pieces, tower.mat)
			Remotes.event("RoundReplay"):FireClient(other.player, e.replay)
		end
	end
	waitPhase(seconds(Config.VOTE_SECONDS))
	local total, n = 0, 0
	for voter, stars in e.stars do
		total += stars
		n += 1
		if stars >= 4 and voter.Parent then
			TowerService.addLike(tower.owner, tower.hash)
		end
	end
	if n > 0 and present(e) then
		give(e, total * Config.COINS_PER_STAR)
	end
	shown = nil
end

local function finishRound()
	local results = {}
	for _, e in entries do
		local n, total = 0, 0
		for _, s in e.stars do
			n += 1
			total += s
		end
		local avg = if n > 0 then total / n else nil
		table.insert(results, { name = e.name, coins = e.coins, valid = e.valid, stars = avg, wins = e.wins })
		if not present(e) then
			continue
		end
		local roundTower = TowerService.leaveRound(e.player)
		TowerService.setEditLocked(e.player, false)
		-- Back to the spawn so nobody ends up inside their restored tower.
		local spawn = PlotService.spawnCFrame(e.player)
		local character = e.player.Character
		if spawn and character then
			character:PivotTo(spawn)
		end
		-- Good towers are saved: valid, and rated 3+ stars (or nobody was there to rate).
		local tower = e.tower
		local qa = RunService:IsStudio() and ServerStorage:GetAttribute("RunQA") ~= nil
		if tower and roundTower and not qa and (avg == nil or avg >= 3) then
			task.spawn(TowerService.publishRound, e.player, roundTower, tower.name, tower.builderMs)
		end
	end
	table.sort(results, function(a, b)
		return a.coins > b.coins
	end)
	Remotes.event("RoundResults"):FireAllClients(results)
	table.clear(roundTowers)
	table.clear(entryOf)
	table.clear(entries)
end

local function loop()
	while true do
		local ready = loadedPlayers()
		if #ready < Config.ROUND_MIN_PLAYERS then
			if phase ~= "waiting" then
				broadcast("waiting", 0)
			end
			task.wait(1)
			continue
		end
		broadcast("intermission", seconds(Config.ROUND_WAIT_SECONDS))
		task.wait(seconds(Config.ROUND_WAIT_SECONDS))
		if not startBuild() then
			continue
		end
		-- QA harness needs a longer build phase than RoundFast gives.
		local qaBuild = RunService:IsStudio() and ServerStorage:GetAttribute("QABuildSeconds")
		local build = if type(qaBuild) == "number" then qaBuild else seconds(Config.BUILD_SECONDS)
		broadcast("build", build)
		waitPhase(build)
		endBuild()
		local valid = {}
		for _, e in entries do
			if e.valid and present(e) then
				table.insert(valid, e)
			end
		end
		for i, e in valid do
			if not present(e) then
				continue
			end
			local winner = race(e, i, #valid)
			if #loadedPlayers() > 1 and present(e) then
				vote(e, winner)
			end
		end
		finishRound()
		broadcast("results", seconds(Config.RESULTS_SECONDS))
		task.wait(seconds(Config.RESULTS_SECONDS))
	end
end

local function onVote(player: Player, stars: any)
	local e = shown
	if
		phase ~= "vote"
		or not e
		or e.player == player
		or not present(e)
		or not entryOf[player]
		or not limiter:allow(player)
		or type(stars) ~= "number"
		or stars % 1 ~= 0
		or stars < 1
		or stars > 5
	then
		return
	end
	e.stars[player] = stars
end

local function onDonate(player: Player, amount: any)
	local e = shown
	if
		phase ~= "vote"
		or not e
		or e.player == player
		or e.donated[player]
		or not limiter:allow(player)
		or not table.find(Config.DONATE_AMOUNTS, amount)
		or not present(e)
	then
		return
	end
	if ProgressionService.spend(player, amount) then
		e.donated[player] = true
		give(e, amount)
	end
end

function RoundService.inRound(player: Player): boolean
	return entryOf[player] ~= nil
end

function RoundService.init()
	RunTimerService.setRoundSource(function(ownerId: number)
		return roundTowers[ownerId]
	end)
	-- In a round you may only start your own verification run, and only while building.
	RunTimerService.setStartFilter(function(player: Player, ownerId: number): boolean
		if not entryOf[player] then
			return roundTowers[ownerId] == nil
		end
		return phase == "build" and ownerId == player.UserId
	end)
	SocialService.setRunCheck(function(player: Player): boolean
		return RunTimerService.isRunning(player) or entryOf[player] ~= nil
	end)
	RunTimerService.Ended:Connect(function(player: Player, ownerId: number, finished: boolean)
		local e = shown
		if finished and phase == "race" and e and e.player.UserId == ownerId and not raceWinner then
			raceWinner = player
		end
	end)
	Remotes.event("RoundVote").OnServerEvent:Connect(onVote)
	Remotes.event("RoundDonate").OnServerEvent:Connect(onDonate)
	-- Sitting out takes effect from the next round (the current one keeps you).
	Remotes.event("RoundSitOut").OnServerEvent:Connect(function(player: Player, on: any)
		if type(on) == "boolean" and limiter:allow(player) then
			sitOut[player] = if on then true else nil
		end
	end)
	DataService.Loaded:Connect(function(player: Player)
		Remotes.event("Round"):FireClient(player, state)
	end)
	Players.PlayerRemoving:Connect(function(player)
		entryOf[player] = nil
		sitOut[player] = nil
		limiter:forget(player)
	end)
	task.spawn(loop)
end

return RoundService

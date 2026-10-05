--!strict
-- Live races: a host opens a lobby for a published tower, others in the server
-- join within Config.LIVE_RACE_LOBBY_SECONDS, then everyone starts together.
-- Each racer climbs their own copy on their own plot (so nobody can block
-- anyone); racers see each other as live ghosts and get standings as they finish.
-- Times still go to the tower's normal leaderboard through RunTimerService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local RunTimerService = require(script.Parent.RunTimerService)
local TowerService = require(script.Parent.TowerService)

local LiveRaceService = {}

type Race = {
	id: number,
	host: Player,
	ownerId: number,
	towerName: string,
	members: { Player },
	state: "lobby" | "running",
	startsAt: number,
	results: { { player: Player, ms: number? } }, -- in finishing order; ms nil = did not finish
}

local races: { [number]: Race } = {}
local raceOf: { [Player]: Race } = {}
local nextId = 0
local limiter = RateLimiter.new(3, 1 / 2)

local function isId(n: any): boolean
	return type(n) == "number" and n == n and n % 1 == 0 and n >= 1 and n <= 2 ^ 53
end

local function lobbyInfo(race: Race): { [string]: any }
	return {
		id = race.id,
		host = race.host.DisplayName,
		tower = race.towerName,
		count = #race.members,
		seconds = math.max(0, math.ceil(race.startsAt - os.clock())),
	}
end

local function broadcastLobby(race: Race)
	Remotes.event("LiveRaceLobby"):FireAllClients(lobbyInfo(race))
end

local function standings(race: Race): { { [string]: any } }
	local out = {}
	for i, r in race.results do
		table.insert(out, { place = i, name = r.player.DisplayName, ms = r.ms })
	end
	return out
end

local function closeRace(race: Race)
	races[race.id] = nil
	for _, p in race.members do
		if raceOf[p] == race then
			raceOf[p] = nil
		end
	end
	Remotes.event("LiveRaceLobby"):FireAllClients({ id = race.id, closed = true })
end

local function removeMember(race: Race, player: Player)
	local i = table.find(race.members, player)
	if i then
		table.remove(race.members, i)
	end
	raceOf[player] = nil
	if race.state == "lobby" then
		if #race.members == 0 then
			closeRace(race)
		else
			broadcastLobby(race)
		end
	end
end

local function hasResult(race: Race, player: Player): boolean
	for _, r in race.results do
		if r.player == player then
			return true
		end
	end
	return false
end

local function checkDone(race: Race)
	for _, p in race.members do
		if not hasResult(race, p) then
			return
		end
	end
	for _, p in race.members do
		Remotes.event("LiveRaceStandings"):FireClient(p, standings(race), true)
	end
	closeRace(race)
end

local function startRace(race: Race)
	if races[race.id] ~= race or race.state ~= "lobby" then
		return
	end
	race.state = "running"
	Remotes.event("LiveRaceLobby"):FireAllClients({ id = race.id, closed = true })
	local started = {}
	for _, p in race.members do
		if RunTimerService.startRun(p, race.ownerId) then
			table.insert(started, p)
		else
			raceOf[p] = nil
		end
	end
	race.members = started
	if #started == 0 then
		closeRace(race)
		return
	end
	for _, p in started do
		Remotes.event("LiveRaceStarted"):FireClient(p, race.id)
	end
	-- Hard stop so a stalled racer can't keep the race open forever.
	task.delay(Config.MAX_RUN_MS / 1000, function()
		if races[race.id] == race then
			for _, p in race.members do
				if not hasResult(race, p) then
					table.insert(race.results, { player = p })
				end
			end
			checkDone(race)
		end
	end)
end

local function onHost(player: Player, ownerId: any): boolean
	-- Owners race their own tower as a verification run, so they can't host or join it.
	if
		not limiter:allow(player)
		or not isId(ownerId)
		or ownerId == player.UserId
		or raceOf[player]
		or RunTimerService.isRunning(player)
	then
		return false
	end
	local tower = TowerService.getPublished(ownerId)
	if not tower then
		return false
	end
	nextId += 1
	local race: Race = {
		id = nextId,
		host = player,
		ownerId = ownerId,
		towerName = tower.name,
		members = { player },
		state = "lobby",
		startsAt = os.clock() + Config.LIVE_RACE_LOBBY_SECONDS,
		results = {},
	}
	races[race.id] = race
	raceOf[player] = race
	broadcastLobby(race)
	task.delay(Config.LIVE_RACE_LOBBY_SECONDS, startRace, race)
	return true
end

local function onJoin(player: Player, raceId: any): boolean
	local race = if type(raceId) == "number" then races[raceId] else nil
	if
		not limiter:allow(player)
		or not race
		or race.state ~= "lobby"
		or race.ownerId == player.UserId
		or raceOf[player]
		or #race.members >= Config.LIVE_RACE_MAX
		or RunTimerService.isRunning(player)
	then
		return false
	end
	table.insert(race.members, player)
	raceOf[player] = race
	broadcastLobby(race)
	return true
end

local function onLeave(player: Player)
	local race = raceOf[player]
	if race and race.state == "lobby" then
		removeMember(race, player)
	end
end

function LiveRaceService.init()
	RunTimerService.setLockCheck(function(player: Player): boolean
		return raceOf[player] ~= nil
	end)
	RunTimerService.Ended:Connect(function(player: Player, _ownerId: number, finished: boolean, ms: number)
		local race = raceOf[player]
		if not race or race.state ~= "running" or hasResult(race, player) then
			return
		end
		table.insert(race.results, { player = player, ms = if finished then ms else nil })
		-- Finishers first, in order; non-finishers after them.
		table.sort(race.results, function(a, b)
			if a.ms and b.ms then
				return a.ms < b.ms
			end
			return a.ms ~= nil and b.ms == nil
		end)
		raceOf[player] = nil
		for _, p in race.members do
			Remotes.event("LiveRaceStandings"):FireClient(p, standings(race), false)
		end
		checkDone(race)
	end)
	Remotes.func("HostLiveRace").OnServerInvoke = onHost
	Remotes.func("JoinLiveRace").OnServerInvoke = onJoin
	Remotes.event("LeaveLiveRace").OnServerEvent:Connect(onLeave)
	Players.PlayerRemoving:Connect(function(player)
		local race = raceOf[player]
		if race then
			if race.state == "lobby" then
				removeMember(race, player)
			else
				raceOf[player] = nil
				if not hasResult(race, player) then
					table.insert(race.results, { player = player })
				end
				checkDone(race)
			end
		end
		limiter:forget(player)
	end)

	-- Live positions: every racer gets the others' plot-relative positions.
	task.spawn(function()
		while true do
			task.wait(0.2)
			for _, race in races do
				if race.state ~= "running" then
					continue
				end
				local positions = {}
				for _, p in race.members do
					local pos = RunTimerService.lastPosition(p)
					if pos then
						table.insert(positions, { id = p.UserId, name = p.DisplayName, pos = pos })
					end
				end
				for _, p in race.members do
					if RunTimerService.isRunning(p) then
						Remotes.event("LiveRacePositions"):FireClient(p, positions)
					end
				end
			end
		end
	end)
end

return LiveRaceService

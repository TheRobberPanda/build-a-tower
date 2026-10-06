--!strict
-- Remote names. The server creates them (Remotes.setup); clients call Remotes.get.
-- Every server handler must validate types/ranges and rate-limit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

Remotes.Events = table.freeze({
	"PlacePiece", -- (typeId, x, y, z, r, props?)
	"PlaceArea", -- (typeId, x0, y0, z0, x1, y1, z1, r, props?) fill a box, max 64 pieces
	"RemovePiece", -- (x, y, z)
	"Undo", -- () revert the last place/remove
	"StartRun", -- (ownerId) ownerId == own id means a verification run
	"TowerChanged", -- server -> client (tower, verified)
	"StopRun", -- () leave the current run
	"RunStarted", -- server -> client (ownerId, towerName)
	"RunResult", -- server -> client (ok, ms, improved, message?, previousBestMs?, canLike?, info?)
	"Split", -- server -> client (checkpointIndex, ms)
	"StopWatch", -- () stop watching a replay
	"Progress", -- server -> client { xp, bricks, level, budget, levelXp, nextXp, material, unlocked }
	"Inbox", -- server -> client { { t, text } }
	"BuildInvite", -- server -> client (fromUserId, fromName)
	"BuildTarget", -- server -> client (ownerId; 0 = your own plot)
	"LiveRaceLobby", -- server -> all { id, host, tower, count, seconds } or { id, closed = true }
	"LiveRaceStarted", -- server -> client (raceId)
	"LiveRacePositions", -- server -> client { { id, name, pos (plot-relative) } }
	"LiveRaceStandings", -- server -> client ({ { place, name, ms? } }, final)
	"LeaveLiveRace", -- () leave a lobby
	"Passes", -- server -> client { [passName]: owned }
	"TutorialDone", -- () the first-time tutorial was closed
	"Round", -- server -> all { phase, endsAt (server time), players, builder?, builderName?, tower?, index?, count?, message? }
	"RoundReplay", -- server -> client { path, splits, ms } the builder's verify climb
	"RoundResults", -- server -> all { { name, coins, valid, stars?, wins } }
	"RoundVote", -- (stars 1-5) for the tower being shown
	"RoundDonate", -- (amount from Config.DONATE_AMOUNTS) to the tower's builder
})

Remotes.Functions = table.freeze({
	"Publish", -- (name) -> (ok, err)
	"Browse", -- (tab: "featured"|"contest"|"new"|"popular"|"hard"|"friends", query?) -> cards
	"Leaderboard", -- (ownerId, monthly?) -> (list, summary)
	"ReportTower", -- (ownerId) -> ok
	"LikeTower", -- (ownerId) -> ok; only after finishing that version
	"GetReplay", -- (ownerId, racerId; 0 = record) -> { racer, ms, path, splits }?
	"WatchReplay", -- (ownerId, racerId) -> replay?; renders the tower on your plot
	"SetMaterial", -- (key) -> (ok, err)
	"BuyMaterial", -- (key) -> (ok, err); spends Bricks
	"SwitchSlot", -- (index) -> ok
	"VisitPlot", -- (userId) -> ok
	"InviteBuilder", -- (userId) -> ok
	"JoinBuild", -- (ownerId; 0 = back to own plot) -> ok
	"HostLiveRace", -- (ownerId) -> ok
	"JoinLiveRace", -- (raceId) -> ok
	"BuyTrail", -- (key) -> (ok, err); buys with Bricks if needed and equips
	"EquipTrail", -- (key or "") -> ok
	"SetTheme", -- (key) -> ok; VIP only
	"ContestInfo", -- () -> { id, theme, phase, endsIn, votesLeft, entered }?
	"EnterContest", -- () -> (ok, err)
	"VoteContest", -- (ownerId) -> (ok, err)
})

function Remotes.setup(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in Remotes.Events do
		local r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	for _, name in Remotes.Functions do
		local r = Instance.new("RemoteFunction")
		r.Name = name
		r.Parent = folder
	end
	folder.Parent = ReplicatedStorage
	return folder
end

function Remotes.event(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name) :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name) :: RemoteFunction
end

return Remotes

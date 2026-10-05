--!strict
-- Remote names. The server creates them (Remotes.setup); clients call Remotes.get.
-- Every server handler must validate types/ranges and rate-limit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

Remotes.Events = table.freeze({
	"PlacePiece", -- (typeId, x, y, z, r, props?)
	"RemovePiece", -- (x, y, z)
	"StartRun", -- (ownerId) ownerId == own id means a verification run
	"TowerChanged", -- server -> client (tower, verified)
	"StopRun", -- () leave the current run
	"RunStarted", -- server -> client (ownerId, towerName)
	"RunResult", -- server -> client (ok, ms, improved, message?, previousBestMs?, canLike?, info?)
	"Split", -- server -> client (checkpointIndex, ms)
	"StopWatch", -- () stop watching a replay
	"Progress", -- server -> client { xp, bricks, level, budget, levelXp, nextXp, material, unlocked }
})

Remotes.Functions = table.freeze({
	"Publish", -- (name) -> (ok, err)
	"Browse", -- (tab: "new"|"popular"|"hard"|"friends", query?) -> cards
	"Leaderboard", -- (ownerId) -> list
	"ReportTower", -- (ownerId) -> ok
	"LikeTower", -- (ownerId) -> ok; only after finishing that version
	"GetReplay", -- (ownerId, racerId; 0 = record) -> { racer, ms, path, splits }?
	"WatchReplay", -- (ownerId, racerId) -> replay?; renders the tower on your plot
	"SetMaterial", -- (key) -> (ok, err)
	"BuyMaterial", -- (key) -> (ok, err); spends Bricks
	"SwitchSlot", -- (index) -> ok
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

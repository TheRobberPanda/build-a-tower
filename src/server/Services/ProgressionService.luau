--!strict
-- Builder XP, levels and Bricks. Rewards are credited to builders (online or not)
-- through CreditStore when TowerStats flushes, and claimed into the profile on
-- join and every few minutes while online.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local CreditStore = require(script.Parent.Parent.Lib.CreditStore)
local Badges = require(script.Parent.Badges)
local DataService = require(script.Parent.DataService)

type PlayerData = Types.PlayerData

local ProgressionService = {}

local changed = Instance.new("BindableEvent")
ProgressionService.Changed = changed.Event -- (player, data) after xp/bricks change

local credits: CreditStore.CreditStore
local hasPass: (Player) -> boolean = function(_player: Player)
	return false
end

-- MonetizationService registers the Builder Pass check (it requires us).
function ProgressionService.setPassCheck(fn: (Player) -> boolean)
	hasPass = fn
end

function ProgressionService.hasBuilderPass(player: Player): boolean
	return hasPass(player)
end

local function push(player: Player, data: PlayerData)
	local level = Progression.level(data.xp)
	Remotes.event("Progress"):FireClient(player, {
		xp = data.xp,
		bricks = data.bricks,
		level = level,
		budget = Progression.budget(level, hasPass(player)),
		slots = Progression.slots(hasPass(player)),
		trail = data.trail,
		run = data.run,
		theme = data.theme,
		levelXp = Progression.xpFor(level),
		nextXp = Progression.xpFor(level + 1),
		material = data.material,
		unlocked = data.unlocked,
		activeSlot = data.activeSlot,
		tutorialDone = data.tutorialDone,
		plotSize = data.plotSize,
	})
	changed:Fire(player, data)
end

local function claim(player: Player)
	local xp, bricks, badges = credits:claim(player.UserId)
	for _, badge in badges do
		Badges.award(player, badge)
	end
	local data = DataService.get(player)
	if not data or (xp == 0 and bricks == 0) then
		-- Rewards claimed for a player whose profile vanished are lost; that only
		-- happens when they left mid-claim, and the amounts are small.
		return
	end
	data.xp += xp
	data.bricks += bricks
	push(player, data)
end

-- Called after a stats flush: reward the builder for new finishes and likes.
function ProgressionService.credit(ownerId: number, finishes: number, likes: number)
	if finishes <= 0 and likes <= 0 then
		return
	end
	local xp = finishes * Config.XP_PER_FINISH + likes * Config.XP_PER_LIKE
	local bricks = finishes * Config.BRICKS_PER_FINISH + likes * Config.BRICKS_PER_LIKE
	if not credits:add(ownerId, xp, bricks) then
		warn(string.format("[Progression] could not credit %d", ownerId))
	end
end

-- Week-end prizes (featured tower podium), delivered on next claim.
function ProgressionService.prize(userId: number, badge: string, bricks: number)
	if not credits:addPrize(userId, badge, bricks) then
		warn(string.format("[Progression] could not queue prize for %d", userId))
	end
end

function ProgressionService.level(data: PlayerData): number
	return Progression.level(data.xp)
end

-- Takes Bricks if the player has enough.
function ProgressionService.spend(player: Player, amount: number): boolean
	local data = DataService.get(player)
	if not data or amount < 0 or data.bricks < amount then
		return false
	end
	data.bricks -= amount
	push(player, data)
	return true
end

function ProgressionService.refresh(player: Player)
	local data = DataService.get(player)
	if data then
		push(player, data)
	end
end

function ProgressionService.init()
	credits = CreditStore.new({
		store = DataStoreService:GetDataStore(Config.CREDITS_STORE),
		now = os.time,
		wait = task.wait,
		log = function(msg)
			warn("[Credits] " .. msg)
		end,
	})
	Remotes.event("TutorialDone").OnServerEvent:Connect(function(player: Player)
		local data = DataService.get(player)
		if data then
			data.tutorialDone = true
		end
	end)
	DataService.Loaded:Connect(function(player: Player, data: PlayerData)
		push(player, data)
		task.spawn(claim, player)
	end)
	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE_SECONDS)
			for _, player in Players:GetPlayers() do
				if DataService.get(player) then
					task.spawn(claim, player)
				end
			end
		end
	end)
end

return ProgressionService

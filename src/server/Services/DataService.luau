--!strict
-- Loads/saves player data with session locking, autosave, PlayerRemoving and BindToClose.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local ProfileStore = require(script.Parent.Parent.Lib.ProfileStore)

type PlayerData = Types.PlayerData

local DataService = {}

local profiles: { [Player]: PlayerData } = {}
local noSave: { [Player]: boolean } = {} -- Studio fallback or lost lock: never write
local loadedEvent = Instance.new("BindableEvent")
DataService.Loaded = loadedEvent.Event -- (player, data)

local store: ProfileStore.ProfileStore

local function budgetReady(): boolean
	return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) > 0
end

local function log(msg: string)
	warn("[DataService] " .. msg)
end

function DataService.get(player: Player): PlayerData?
	return profiles[player]
end

local function write(player: Player, data: PlayerData, final: boolean)
	local ok, err = store:save(player.UserId, data, final)
	if not ok then
		log(string.format("save failed for %d: %s", player.UserId, tostring(err)))
		if err == "lost" and not final and profiles[player] then
			noSave[player] = true -- another server owns the record now
			player:Kick("Your data is open in another server. Please rejoin.")
		end
	end
end

-- Immediate save (purchases). True only if the record was written.
function DataService.saveNow(player: Player): boolean
	local data = profiles[player]
	if not data or noSave[player] then
		return false
	end
	local ok = store:save(player.UserId, data, false)
	return ok == true
end

local function autosave(player: Player)
	local data = profiles[player]
	if data and not noSave[player] then
		write(player, data, false)
	end
end

-- Final save + lock release. Removes the profile first so it only runs once
-- (PlayerRemoving and BindToClose can both fire for the same player).
local function release(player: Player)
	local data = profiles[player]
	local skip = noSave[player]
	profiles[player] = nil
	noSave[player] = nil
	if data and not skip then
		write(player, data, true)
	end
end

-- Final save + lock release for everyone, now (shutdown paths that skip
-- BindToClose, e.g. the Studio QA harness ending a test).
function DataService.releaseAll()
	for player in profiles do
		release(player)
	end
end

local function onPlayerAdded(player: Player)
	local data, err = store:load(player.UserId)
	if not data then
		if RunService:IsStudio() and err == "datastore" then
			log("DataStores unavailable in Studio; using unsaved data (enable API access to test saving)")
			data = ProfileStore.defaultData()
			noSave[player] = true
		else
			player:Kick("Could not load your data (" .. tostring(err) .. "). Please rejoin.")
			return
		end
	end
	if player.Parent ~= Players then
		-- left while loading: release the lock we just took
		profiles[player] = data
		release(player)
		return
	end
	profiles[player] = data
	loadedEvent:Fire(player, data)
end

function DataService.init()
	store = ProfileStore.new({
		store = DataStoreService:GetDataStore(Config.PLAYER_STORE),
		-- fixed Studio id: a stopped playtest never releases its lock, so the next one must own it
		jobId = if game.JobId ~= "" then game.JobId else "studio",
		now = os.time,
		wait = task.wait,
		budgetReady = budgetReady,
		log = log,
	})

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(release)

	-- Staggered autosave: each player saves at their own offset within the interval.
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(1)
			tick += 1
			for player in profiles do
				if (player.UserId + tick) % Config.AUTOSAVE_SECONDS == 0 then
					task.spawn(autosave, player)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				release(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + (if RunService:IsStudio() then 5 else 25)
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService

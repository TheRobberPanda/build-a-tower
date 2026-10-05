--!strict
-- Building, publishing, browse list and leaderboards. All remote input is untrusted.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TowerCodec = require(ReplicatedStorage.Shared.TowerCodec)
local Types = require(ReplicatedStorage.Shared.Types)
local PublishedStore = require(script.Parent.Parent.Lib.PublishedStore)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

type PlayerData = Types.PlayerData
type PublishedTower = Types.PublishedTower

local TowerService = {}

local states: { [Player]: TowerCodec.PlaceState } = {}
local editLocked: { [Player]: boolean } = {} -- set by RunTimerService during runs
local published: PublishedStore.PublishedStore

local editLimiter = RateLimiter.new(20, 10)
local publishLimiter = RateLimiter.new(1, 1 / 10)
local queryLimiter = RateLimiter.new(5, 1)

local CACHE_SECONDS = 30
local towerCache: { [number]: { at: number, tower: PublishedTower? } } = {}
local browseCache: { at: number, list: { any } }? = nil

local function isInt(n: any, lo: number, hi: number): boolean
	return type(n) == "number" and n == n and n % 1 == 0 and n >= lo and n <= hi
end

local function pushTower(player: Player, data: PlayerData)
	PlotService.render(player, data.tower.pieces)
	Remotes.event("TowerChanged"):FireClient(player, data.tower, data.verifiedHash ~= nil)
end

function TowerService.setEditLocked(player: Player, locked: boolean)
	editLocked[player] = if locked then true else nil
end

function TowerService.published(): PublishedStore.PublishedStore
	return published
end

-- Cached read of a published tower (shared by browse, leaderboard and races).
function TowerService.getPublished(ownerId: number): PublishedTower?
	local c = towerCache[ownerId]
	if c and os.clock() - c.at < CACHE_SECONDS then
		return c.tower
	end
	local tower = published:get(ownerId)
	towerCache[ownerId] = { at = os.clock(), tower = tower }
	return tower
end

local function editable(player: Player): PlayerData?
	if editLocked[player] or not editLimiter:allow(player) then
		return nil
	end
	return DataService.get(player)
end

local function onPlace(player: Player, t: any, x: any, y: any, z: any, r: any, p: any)
	local data = editable(player)
	local state = states[player]
	if not data or not state then
		return
	end
	if
		not (
			isInt(t, 1, 255)
			and isInt(x, 0, 255)
			and isInt(y, 0, 255)
			and isInt(z, 0, 255)
			and isInt(r, 0, 3)
		)
	then
		return
	end
	if p ~= nil and type(p) ~= "table" then
		return
	end
	local piece = TowerCodec.validatePiece({ t = t, x = x, y = y, z = z, r = r, p = p })
	if not piece or not TowerCodec.canAdd(state, piece) then
		return
	end
	TowerCodec.add(state, piece)
	table.insert(data.tower.pieces, piece)
	data.verifiedHash = nil -- any edit resets verification
	pushTower(player, data)
	Analytics.step(player, "PlacedPiece")
end

local function onRemove(player: Player, x: any, y: any, z: any)
	local data = editable(player)
	local state = states[player]
	if not data or not state then
		return
	end
	if not (isInt(x, 0, 255) and isInt(y, 0, 255) and isInt(z, 0, 255)) then
		return
	end
	for i, piece in data.tower.pieces do
		local sx, sy, sz = TowerCodec.extent(piece)
		if
			x >= piece.x
			and x < piece.x + sx
			and y >= piece.y
			and y < piece.y + sy
			and z >= piece.z
			and z < piece.z + sz
		then
			TowerCodec.remove(state, piece)
			table.remove(data.tower.pieces, i)
			data.verifiedHash = nil
			pushTower(player, data)
			return
		end
	end
end

local function onPublish(player: Player, name: any): (boolean, string?)
	if not publishLimiter:allow(player) then
		return false, "slow down"
	end
	local data = DataService.get(player)
	if not data or editLocked[player] then
		return false, "not ready"
	end
	if type(name) ~= "string" or #name < 1 or #name > Config.TOWER_NAME_MAX or not utf8.len(name) then
		return false, "bad name"
	end
	local hash = TowerCodec.hash(data.tower)
	if data.verifiedHash ~= hash then
		return false, "climb your tower first"
	end
	local okFilter, filtered = pcall(function()
		return TextService:FilterStringAsync(name, player.UserId):GetNonChatStringForBroadcastAsync()
	end)
	if not okFilter then
		return false, "filter unavailable"
	end
	local ok, result = published:publish(player.UserId, filtered, data.tower)
	if not ok then
		return false, result
	end
	data.towerName = filtered
	data.publishedHash = hash
	towerCache[player.UserId] = nil
	browseCache = nil
	Analytics.step(player, "Published")
	return true, nil
end

local function onBrowse(player: Player): { any }
	if not queryLimiter:allow(player) then
		return {}
	end
	if browseCache and os.clock() - browseCache.at < CACHE_SECONDS then
		return browseCache.list
	end
	local page = published:browsePage(25) or {}
	local list = {}
	for _, entry in page do
		local ownerId = tonumber(entry.key)
		local tower = ownerId and TowerService.getPublished(ownerId)
		if tower then
			table.insert(list, { owner = tower.owner, name = tower.name, pieces = #tower.pieces })
		end
	end
	browseCache = { at = os.clock(), list = list }
	return list
end

local function onLeaderboard(player: Player, ownerId: any): { any }
	if not queryLimiter:allow(player) or not isInt(ownerId, 1, 2 ^ 53) then
		return {}
	end
	local tower = TowerService.getPublished(ownerId)
	if not tower then
		return {}
	end
	local out = {}
	for _, e in published:topTimes(ownerId, tower.hash, 10) or {} do
		table.insert(out, { userId = tonumber(e.key), ms = e.value })
	end
	return out
end

function TowerService.init()
	published = PublishedStore.new({
		published = DataStoreService:GetDataStore(Config.PUBLISHED_STORE),
		browse = DataStoreService:GetOrderedDataStore(Config.BROWSE_STORE),
		leaderboard = function(name: string)
			return DataStoreService:GetOrderedDataStore(name)
		end,
		now = os.time,
		wait = task.wait,
		log = function(msg)
			warn("[TowerService] " .. msg)
		end,
	})

	DataService.Loaded:Connect(function(player: Player, data: PlayerData)
		states[player] = TowerCodec.buildState(data.tower)
		pushTower(player, data)
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		editLocked[player] = nil
		editLimiter:forget(player)
		publishLimiter:forget(player)
		queryLimiter:forget(player)
	end)

	Remotes.event("PlacePiece").OnServerEvent:Connect(onPlace)
	Remotes.event("RemovePiece").OnServerEvent:Connect(onRemove)
	Remotes.func("Publish").OnServerInvoke = onPublish
	Remotes.func("Browse").OnServerInvoke = onBrowse
	Remotes.func("Leaderboard").OnServerInvoke = onLeaderboard
end

return TowerService

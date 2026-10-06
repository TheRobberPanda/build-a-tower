--!strict
-- Building, publishing, browse list and leaderboards. All remote input is untrusted.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Events = require(ReplicatedStorage.Shared.Events)
local PieceDefs = require(ReplicatedStorage.Shared.PieceDefs)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TowerCodec = require(ReplicatedStorage.Shared.TowerCodec)
local Types = require(ReplicatedStorage.Shared.Types)
local PublishedStore = require(script.Parent.Parent.Lib.PublishedStore)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local TowerStats = require(script.Parent.Parent.Lib.TowerStats)
local Analytics = require(script.Parent.Analytics)
local Badges = require(script.Parent.Badges)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local ProgressionService = require(script.Parent.ProgressionService)
local PlotService = require(script.Parent.PlotService)

type PlayerData = Types.PlayerData
type PublishedTower = Types.PublishedTower

local TowerService = {}

local budgetFor: (Player, PlayerData) -> number

local states: { [Player]: TowerCodec.PlaceState } = {}
-- Undo history per tower owner: most recent last.
type Action = { kind: "place" | "remove" | "fill", piece: Types.Piece, pieces: { Types.Piece }? }
local history: { [Player]: { Action } } = {}
local HISTORY_MAX = 30

local function remember(owner: Player, kind: "place" | "remove", piece: Types.Piece)
	local list = history[owner] or {}
	history[owner] = list
	table.insert(list, { kind = kind, piece = piece })
	if #list > HISTORY_MAX then
		table.remove(list, 1)
	end
end
local editLocked: { [Player]: boolean } = {} -- set by RunTimerService during runs
local published: PublishedStore.PublishedStore

local editLimiter = RateLimiter.new(20, 10)
local publishLimiter = RateLimiter.new(1, 1 / 10)
local queryLimiter = RateLimiter.new(5, 1)
local reportLimiter = RateLimiter.new(3, 1 / 60)

local CACHE_SECONDS = 30
local towerCache: { [number]: { at: number, tower: PublishedTower? } } = {}
local browseCache: { [string]: { at: number, list: { any } } } = {}
local hidden: { [number]: boolean } = {} -- hidden after reports, this server
local finished: { [Player]: { [number]: string } } = {} -- ownerId -> hash finished this session
local stats: TowerStats.TowerStats

local function isInt(n: any, lo: number, hi: number): boolean
	return type(n) == "number" and n == n and n % 1 == 0 and n >= lo and n <= hi
end

local buildersOf: (Player) -> { Player }

local function pushTower(player: Player, data: PlayerData)
	PlotService.render(player, data.tower.pieces, data.material)
	for _, builder in buildersOf(player) do
		Remotes.event("TowerChanged"):FireClient(builder, data.tower, data.verifiedHash ~= nil)
	end
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

-- Co-building: a helper's edits go to the owner's tower (the owner keeps
-- publish rights; runs and publishing always use your own tower).
local buildTarget: { [Player]: Player } = {}

-- The tower this player is editing right now: (owner, owner's data), or nil.
local function editable(player: Player): (Player?, PlayerData?)
	local owner = buildTarget[player] or player
	if owner.Parent == nil or editLocked[owner] or editLocked[player] or not editLimiter:allow(player) then
		return nil, nil
	end
	return owner, DataService.get(owner)
end

-- Everyone currently building on owner's plot (owner first).
function buildersOf(owner: Player): { Player }
	local list = { owner }
	for helper, target in buildTarget do
		if target == owner then
			table.insert(list, helper)
		end
	end
	return list
end

function TowerService.setBuildTarget(player: Player, owner: Player?)
	buildTarget[player] = if owner and owner ~= player then owner else nil
	Remotes.event("BuildTarget")
		:FireClient(player, if buildTarget[player] then (owner :: Player).UserId else 0)
	local data = DataService.get(owner or player)
	if data then
		Remotes.event("TowerChanged"):FireClient(player, data.tower, data.verifiedHash ~= nil)
	end
end

function TowerService.buildTargetOf(player: Player): Player?
	return buildTarget[player]
end

-- True if the piece's cells overlap any character (you can't build inside a player).
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
local function hitsCharacter(owner: Player, piece: Types.Piece): boolean
	local plot = PlotService.get(owner)
	if not plot then
		return false
	end
	local chars = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(chars, p.Character)
		end
	end
	overlap.FilterDescendantsInstances = chars
	local sx, sy, sz = TowerCodec.extent(piece)
	local g = Config.GRID_STUDS
	local center = plot.origin + Vector3.new(piece.x + sx / 2, piece.y + sy / 2, piece.z + sz / 2) * g
	return #workspace:GetPartBoundsInBox(
		CFrame.new(center),
		Vector3.new(sx, sy, sz) * g - Vector3.one * 0.2,
		overlap
	) > 0
end

local function onPlace(player: Player, t: any, x: any, y: any, z: any, r: any, p: any)
	local owner, data = editable(player)
	local state = owner and states[owner]
	if not owner or not data or not state then
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
	if
		not piece
		or not Events.pieceAvailable(piece.t, os.time())
		or not TowerCodec.canAdd(state, piece)
		or hitsCharacter(owner, piece)
	then
		return
	end
	TowerCodec.add(state, piece)
	table.insert(data.tower.pieces, piece)
	data.verifiedHash = nil -- any edit resets verification
	remember(owner, "place", piece)
	pushTower(owner, data)
	Analytics.step(player, "PlacedPiece")
end

-- Fills the box between two cells with the selected piece (stepping by its
-- size) in one intent, so floors and walls don't need a click per block.
local FILL_MAX = 64
local function onPlaceArea(
	player: Player,
	t: any,
	x0: any,
	y0: any,
	z0: any,
	x1: any,
	y1: any,
	z1: any,
	r: any,
	p: any
)
	local owner, data = editable(player)
	local state = owner and states[owner]
	if not owner or not data or not state then
		return
	end
	for _, n in { x0, y0, z0, x1, y1, z1 } do
		if not isInt(n, 0, 255) then
			return
		end
	end
	if not isInt(t, 1, 255) or not isInt(r, 0, 3) or (p ~= nil and type(p) ~= "table") then
		return
	end
	local probe = TowerCodec.validatePiece({ t = t, x = x0, y = y0, z = z0, r = r, p = p })
	if not probe or not Events.pieceAvailable(probe.t, os.time()) then
		return
	end
	local sx, sy, sz = TowerCodec.extent(probe)
	local function steps(a: number, b: number, s: number): { number }
		local out = {}
		local dir = if b >= a then 1 else -1
		for v = a, b, dir * s do
			table.insert(out, v)
		end
		return out
	end
	local xs, ys, zs = steps(x0, x1, sx), steps(y0, y1, sy), steps(z0, z1, sz)
	if #xs * #ys * #zs > FILL_MAX then
		return
	end
	local added = {}
	for _, y in ys do
		for _, x in xs do
			for _, z in zs do
				local piece = TowerCodec.validatePiece({ t = t, x = x, y = y, z = z, r = r, p = p })
				if piece and TowerCodec.canAdd(state, piece) and not hitsCharacter(owner, piece) then
					TowerCodec.add(state, piece)
					table.insert(data.tower.pieces, piece)
					table.insert(added, piece)
				end
			end
		end
	end
	if #added == 0 then
		return
	end
	data.verifiedHash = nil
	local list = history[owner] or {}
	history[owner] = list
	table.insert(list, { kind = "fill", piece = added[1], pieces = added })
	if #list > HISTORY_MAX then
		table.remove(list, 1)
	end
	pushTower(owner, data)
	Analytics.step(player, "PlacedPiece")
end

local function onRemove(player: Player, x: any, y: any, z: any)
	local owner, data = editable(player)
	local state = owner and states[owner]
	if not owner or not data or not state then
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
			remember(owner, "remove", piece)
			pushTower(owner, data)
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
	local ok, result = published:publish(player.UserId, filtered, data.tower, data.material, data.verifiedMs)
	if not ok then
		return false, result
	end
	data.towerName = filtered
	data.publishedHash = hash
	towerCache[player.UserId] = nil
	table.clear(browseCache)
	Analytics.step(player, "Published")
	Badges.award(player, "FirstPublish")
	return true, nil
end

-- Level budget, plus the Builder Pass bonus.
budgetFor = function(player: Player, data: PlayerData): number
	return Progression.budget(
		ProgressionService.level(data),
		MonetizationService.hasPass(player, "BuilderPass")
	)
end

local TABS =
	table.freeze({ new = true, popular = true, hard = true, friends = true, featured = true, contest = true })

-- (ownerId, likes) after likes are flushed; FeaturedService counts them per week.
local liked = Instance.new("BindableEvent")
TowerService.Liked = liked.Event

local featuredSource: () -> { string } = function()
	return {}
end
function TowerService.setFeaturedSource(fn: () -> { string })
	featuredSource = fn
end

local contestSource: () -> { string } = function()
	return {}
end
function TowerService.setContestSource(fn: () -> { string })
	contestSource = fn
end

local function towerHeight(tower: PublishedTower): number
	local top = 0
	for _, piece in tower.pieces do
		local _, sy = TowerCodec.extent(piece)
		top = math.max(top, piece.y + sy)
	end
	return top
end

local SECRET_PIECES: { [string]: boolean } = {
	FakeWall = true,
	InvisiblePlatform = true,
	Teleporter = true,
	OneWay = true,
	Button = true,
}

-- Number of secret pieces (shown as "N secrets hidden", never where).
local function secretCount(tower: PublishedTower): number
	local n = 0
	for _, piece in tower.pieces do
		local def = PieceDefs.byId[piece.t]
		if def and SECRET_PIECES[def.name] then
			n += 1
		end
	end
	return n
end

-- Card data shown in browse lists.
local function card(tower: PublishedTower): { [string]: any }
	local st = stats:get(tower.owner, tower.hash)
	return {
		owner = tower.owner,
		name = tower.name,
		pieces = #tower.pieces,
		height = towerHeight(tower),
		secrets = secretCount(tower),
		builderMs = tower.builderMs,
		difficulty = TowerStats.difficulty(st.starts, st.finishes),
		likes = st.likes,
		finishes = st.finishes,
		best = st.best,
		bestBy = st.bestBy,
	}
end

local function cardsFor(keys: { string }, limit: number): { any }
	local list = {}
	for _, key in keys do
		local ownerId = tonumber(key)
		local tower = ownerId and TowerService.getPublished(ownerId)
		if tower and not hidden[tower.owner] then
			table.insert(list, card(tower))
			if #list >= limit then
				break
			end
		end
	end
	return list
end

local function keysOf(page: { { key: string, value: number } }?): { string }
	local keys = {}
	for _, entry in page or {} do
		table.insert(keys, entry.key)
	end
	return keys
end

local function friendKeys(player: Player): { string }
	local friends: { [number]: boolean } = {}
	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(player.UserId)
	end)
	if ok and pages then
		for _ = 1, 3 do -- up to ~150 friends
			for _, f in pages:GetCurrentPage() do
				friends[f.Id] = true
			end
			if pages.IsFinished or not pcall(function()
				pages:AdvanceToNextPageAsync()
			end) then
				break
			end
		end
	end
	local keys = {}
	for _, key in keysOf(published:browsePage(100)) do
		if friends[tonumber(key) or 0] then
			table.insert(keys, key)
		end
	end
	return keys
end

-- tab: "new" | "popular" | "hard" | "friends". query: optional builder name to search.
local function onBrowse(player: Player, tab: any, query: any): { any }
	if not queryLimiter:allow(player) then
		return {}
	end
	if type(query) == "string" and #query >= 3 and #query <= 20 and query:match("^[%w_]+$") then
		local ok, userId = pcall(function()
			return Players:GetUserIdFromNameAsync(query)
		end)
		return if ok and type(userId) == "number" then cardsFor({ tostring(userId) }, 1) else {}
	end
	local name = if type(tab) == "string" and TABS[tab] then tab else "new"
	if name == "friends" then
		return cardsFor(friendKeys(player), 25) -- per player, not cached
	end
	local cached = browseCache[name]
	if cached and os.clock() - cached.at < CACHE_SECONDS then
		return cached.list
	end
	local keys = if name == "featured"
		then featuredSource()
		elseif name == "contest" then contestSource()
		elseif name == "popular" then keysOf(stats:popularPage(25))
		elseif name == "hard" then keysOf(stats:hardestPage(25))
		else keysOf(published:browsePage(25))
	local list = cardsFor(keys, 25)
	browseCache[name] = { at = os.clock(), list = list }
	return list
end

-- One like per player per tower version, only after finishing that version.
local function onLike(player: Player, ownerId: any): boolean
	if not isInt(ownerId, 1, 2 ^ 53) or ownerId == player.UserId or not queryLimiter:allow(player) then
		return false
	end
	local data = DataService.get(player)
	local tower = TowerService.getPublished(ownerId)
	local done = finished[player]
	if not data or not tower or not done or done[ownerId] ~= tower.hash then
		return false
	end
	local key = tostring(ownerId)
	if data.liked[key] == tower.hash then
		return false
	end
	if not data.liked[key] then
		table.insert(data.likedOrder, key)
		if #data.likedOrder > Config.LIKED_MAX then
			data.liked[table.remove(data.likedOrder, 1) :: string] = nil
		end
	end
	data.liked[key] = tower.hash
	stats:addLike(ownerId, tower.hash)
	return true
end

-- Called by RunTimerService.
function TowerService.recordStart(ownerId: number, hash: string)
	stats:addStart(ownerId, hash)
end

function TowerService.recordFinish(
	player: Player,
	ownerId: number,
	hash: string,
	ms: number,
	used: { string }
)
	stats:addFinish(ownerId, hash, player.UserId, ms, used)
	local done = finished[player]
	if done then
		done[ownerId] = hash
	end
end

function TowerService.stats(ownerId: number, hash: string): TowerStats.Stats
	return stats:get(ownerId, hash)
end

function TowerService.hasLiked(player: Player, ownerId: number, hash: string): boolean
	local data = DataService.get(player)
	return data ~= nil and data.liked[tostring(ownerId)] == hash
end

-- monthly = true for this month's season board instead of all-time.
local function onLeaderboard(player: Player, ownerId: any, monthly: any): ({ any }, { [string]: any }?)
	if not queryLimiter:allow(player) or not isInt(ownerId, 1, 2 ^ 53) then
		return {}
	end
	local tower = TowerService.getPublished(ownerId)
	if not tower then
		return {}
	end
	local out = {}
	local season = if monthly == true then Events.season(os.time()) else nil
	for _, e in published:topTimes(ownerId, tower.hash, 10, season) or {} do
		table.insert(out, { userId = tonumber(e.key), ms = e.value })
	end
	local st = stats:get(ownerId, tower.hash)
	local summary: { [string]: any } = {
		difficulty = TowerStats.difficulty(st.starts, st.finishes),
		starts = st.starts,
		finishes = st.finishes,
		average = TowerStats.averageMs(st),
	}
	if ownerId == player.UserId then
		-- Only the builder learns which of their secrets racers find.
		local found = {}
		for kind, n in st.found do
			found[kind] = math.floor(n / math.max(st.finishes, 1) * 100 + 0.5)
		end
		summary.found = found
	end
	return out, summary
end

-- Switch to another tower slot. The current tower is kept as it is (including
-- its verification) and the target slot becomes the editable tower.
local function onSwitchSlot(player: Player, index: any): boolean
	-- Only your own towers: no slot switching while helping someone else build.
	local owner, data = editable(player)
	if owner ~= player then
		return false
	end
	local slots = Progression.slots(MonetizationService.hasPass(player, "BuilderPass"))
	if not data or not isInt(index, 1, slots) or index == data.activeSlot then
		return false
	end
	data.slots[tostring(data.activeSlot)] = {
		tower = data.tower,
		name = data.towerName,
		verifiedHash = data.verifiedHash,
		verifiedMs = data.verifiedMs,
	}
	local key = tostring(index)
	local target = data.slots[key]
	data.slots[key] = nil
	data.activeSlot = index
	data.tower = if target then target.tower else TowerCodec.empty()
	data.towerName = if target then target.name else "Tower " .. key
	data.verifiedHash = if target then target.verifiedHash else nil
	data.verifiedMs = if target then target.verifiedMs else nil
	states[player] = TowerCodec.buildState(data.tower, budgetFor(player, data))
	history[player] = nil -- undo history belongs to the previous slot
	pushTower(player, data)
	ProgressionService.refresh(player)
	return true
end

-- Reverts the last place/remove on the tower you are editing.
local function onUndo(player: Player)
	local owner, data = editable(player)
	local state = owner and states[owner]
	local list = owner and history[owner]
	if not owner or not data or not state or not list or #list == 0 then
		return
	end
	local action = table.remove(list) :: Action
	if action.kind == "fill" then
		for _, piece in action.pieces or {} do
			local i = table.find(data.tower.pieces, piece)
			if i then
				TowerCodec.remove(state, piece)
				table.remove(data.tower.pieces, i)
			end
		end
	elseif action.kind == "place" then
		local i = table.find(data.tower.pieces, action.piece)
		if i then
			TowerCodec.remove(state, action.piece)
			table.remove(data.tower.pieces, i)
		end
	elseif TowerCodec.canAdd(state, action.piece) then
		TowerCodec.add(state, action.piece)
		table.insert(data.tower.pieces, action.piece)
	end
	data.verifiedHash = nil
	pushTower(owner, data)
end

local function canUseMaterial(player: Player, data: PlayerData, key: string): boolean
	local def = Cosmetics.byKey[key]
	if not def then
		return false
	end
	if def.pass then
		return MonetizationService.hasPass(player, def.pass)
	end
	if def.bricks > 0 then
		return data.unlocked[key] == true
	end
	return ProgressionService.level(data) >= def.level
end

-- Equip a material you have unlocked. Cosmetic: does not clear verification.
local function onSetMaterial(player: Player, key: any): (boolean, string?)
	local data = DataService.get(player)
	if not data or type(key) ~= "string" or not queryLimiter:allow(player) then
		return false, "bad request"
	end
	if not canUseMaterial(player, data, key) then
		return false, "locked"
	end
	data.material = key
	if not editLocked[player] then
		PlotService.render(player, data.tower.pieces, data.material)
	end
	return true, nil
end

-- Buy a Bricks material (level requirement still applies).
local function onBuyMaterial(player: Player, key: any): (boolean, string?)
	local data = DataService.get(player)
	local def = if type(key) == "string" then Cosmetics.byKey[key] else nil
	if not data or not def or def.bricks <= 0 or not queryLimiter:allow(player) then
		return false, "bad request"
	end
	if data.unlocked[def.key] then
		return true, nil
	end
	if ProgressionService.level(data) < def.level then
		return false, "level " .. def.level
	end
	if not ProgressionService.spend(player, def.bricks) then
		return false, "not enough Bricks"
	end
	data.unlocked[def.key] = true
	return onSetMaterial(player, def.key)
end

local function onReport(player: Player, ownerId: any): boolean
	if not isInt(ownerId, 1, 2 ^ 53) or ownerId == player.UserId or not reportLimiter:allow(player) then
		return false
	end
	local tower = TowerService.getPublished(ownerId)
	if not tower then
		return false
	end
	if published:report(ownerId, tower.hash, player.UserId) then
		warn(string.format("[TowerService] tower %d (%s) hidden after reports", ownerId, tower.hash))
		hidden[ownerId] = true
		stats:unlist(ownerId)
		table.clear(browseCache)
	end
	return true
end

function TowerService.init()
	published = PublishedStore.new({
		published = DataStoreService:GetDataStore(Config.PUBLISHED_STORE),
		browse = DataStoreService:GetOrderedDataStore(Config.BROWSE_STORE),
		reports = DataStoreService:GetDataStore(Config.REPORTS_STORE),
		leaderboard = function(name: string)
			return DataStoreService:GetOrderedDataStore(name)
		end,
		now = os.time,
		wait = task.wait,
		log = function(msg)
			warn("[TowerService] " .. msg)
		end,
	})

	stats = TowerStats.new({
		stats = DataStoreService:GetDataStore(Config.STATS_STORE),
		popular = DataStoreService:GetOrderedDataStore(Config.POPULAR_STORE),
		hardest = DataStoreService:GetOrderedDataStore(Config.HARDEST_STORE),
		wait = task.wait,
		log = function(msg)
			warn("[TowerStats] " .. msg)
		end,
		onFlushed = function(ownerId: number, finishes: number, likes: number)
			ProgressionService.credit(ownerId, finishes, likes)
			if likes > 0 then
				liked:Fire(ownerId, likes)
			end
		end,
	})
	-- Level-ups raise the piece budget immediately.
	ProgressionService.Changed:Connect(function(player: Player, data: PlayerData)
		local state = states[player]
		if state then
			state.budget = budgetFor(player, data)
		end
	end)
	MonetizationService.Changed:Connect(ProgressionService.refresh)
	task.spawn(function()
		while true do
			task.wait(Config.STATS_FLUSH_SECONDS)
			stats:flush()
		end
	end)
	game:BindToClose(function()
		stats:flush()
	end)

	DataService.Loaded:Connect(function(player: Player, data: PlayerData)
		finished[player] = {}
		states[player] = TowerCodec.buildState(data.tower, budgetFor(player, data))
		pushTower(player, data)
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		history[player] = nil
		finished[player] = nil
		buildTarget[player] = nil
		for helper, owner in buildTarget do
			if owner == player then
				TowerService.setBuildTarget(helper, nil) -- owner left: helpers go back to their own tower
			end
		end
		editLocked[player] = nil
		editLimiter:forget(player)
		publishLimiter:forget(player)
		queryLimiter:forget(player)
		reportLimiter:forget(player)
	end)

	Remotes.event("PlacePiece").OnServerEvent:Connect(onPlace)
	Remotes.event("PlaceArea").OnServerEvent:Connect(onPlaceArea)
	Remotes.event("RemovePiece").OnServerEvent:Connect(onRemove)
	Remotes.event("Undo").OnServerEvent:Connect(onUndo)
	Remotes.func("Publish").OnServerInvoke = onPublish
	Remotes.func("Browse").OnServerInvoke = onBrowse
	Remotes.func("Leaderboard").OnServerInvoke = onLeaderboard
	Remotes.func("ReportTower").OnServerInvoke = onReport
	Remotes.func("LikeTower").OnServerInvoke = onLike
	Remotes.func("SetMaterial").OnServerInvoke = onSetMaterial
	Remotes.func("SwitchSlot").OnServerInvoke = onSwitchSlot
	Remotes.func("BuyMaterial").OnServerInvoke = onBuyMaterial
end

return TowerService

--!strict
-- Social features: inbox notifications, visiting plots and co-building invites.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local InboxStore = require(script.Parent.Parent.Lib.InboxStore)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local TowerService = require(script.Parent.TowerService)

local SocialService = {}

local inbox: InboxStore.InboxStore
local limiter = RateLimiter.new(5, 1)
local invites: { [Player]: { [Player]: boolean } } = {} -- invitee -> owners who invited them
local isRunning: (Player) -> boolean = function(_player: Player)
	return false
end

-- RunTimerService registers itself here (it requires us, not the other way round).
function SocialService.setRunCheck(fn: (Player) -> boolean)
	isRunning = fn
end

-- Queues a notification; delivered now if the player is online, else on next join.
function SocialService.notify(userId: number, text: string)
	local online = Players:GetPlayerByUserId(userId)
	if online then
		Remotes.event("Inbox"):FireClient(online, { { t = os.time(), text = text } })
		return
	end
	task.spawn(function()
		inbox:push(userId, text)
	end)
end

local function playerById(id: any): Player?
	if type(id) ~= "number" or id ~= id or id % 1 ~= 0 then
		return nil
	end
	return Players:GetPlayerByUserId(id)
end

-- Teleport to another player's plot apron (outside runs only).
local function onVisit(player: Player, userId: any): boolean
	local target = playerById(userId)
	local character = player.Character
	if not limiter:allow(player) or not target or not character or isRunning(player) then
		return false
	end
	local cf = PlotService.spawnCFrame(target)
	if not cf then
		return false
	end
	character:PivotTo(cf * CFrame.new(math.random(-6, 6), 0, 0))
	return true
end

local function onInvite(player: Player, userId: any): boolean
	local target = playerById(userId)
	if not limiter:allow(player) or not target or target == player then
		return false
	end
	local list = invites[target] or {}
	invites[target] = list
	list[player] = true
	Remotes.event("BuildInvite"):FireClient(target, player.UserId, player.DisplayName)
	return true
end

-- Accept an invite: you now build on the inviter's plot. ownerId 0 = go back to your own.
local function onJoinBuild(player: Player, ownerId: any): boolean
	if not limiter:allow(player) or isRunning(player) then
		return false
	end
	if ownerId == 0 then
		TowerService.setBuildTarget(player, nil)
		return true
	end
	local owner = playerById(ownerId)
	local list = invites[player]
	if not owner or not list or not list[owner] then
		return false
	end
	list[owner] = nil
	TowerService.setBuildTarget(player, owner)
	local character = player.Character
	local cf = PlotService.spawnCFrame(owner)
	if character and cf then
		character:PivotTo(cf)
	end
	return true
end

function SocialService.init()
	inbox = InboxStore.new({
		store = DataStoreService:GetDataStore(Config.INBOX_STORE),
		now = os.time,
		wait = task.wait,
		log = function(msg)
			warn("[Inbox] " .. msg)
		end,
	})
	DataService.Loaded:Connect(function(player: Player)
		task.spawn(function()
			local messages = inbox:take(player.UserId)
			if #messages > 0 then
				Remotes.event("Inbox"):FireClient(player, messages)
			end
		end)
	end)
	Remotes.func("VisitPlot").OnServerInvoke = onVisit
	Remotes.func("InviteBuilder").OnServerInvoke = onInvite
	Remotes.func("JoinBuild").OnServerInvoke = onJoinBuild
	Players.PlayerRemoving:Connect(function(player)
		invites[player] = nil
		for _, list in invites do
			list[player] = nil
		end
		limiter:forget(player)
	end)
end

return SocialService

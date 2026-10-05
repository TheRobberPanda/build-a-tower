--!strict
-- Awards Roblox badges. Ids live in Config.BADGES; 0 = not created yet (skipped),
-- so the game runs before the badges exist on the Creator Dashboard.

local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Badges = {}

local awarded: { [Player]: { [string]: boolean } } = {}

function Badges.award(player: Player, name: string)
	local id = (Config.BADGES :: any)[name]
	if type(id) ~= "number" or id == 0 then
		return
	end
	local seen = awarded[player]
	if not seen then
		seen = {}
		awarded[player] = seen
	end
	if seen[name] then
		return
	end
	seen[name] = true
	task.spawn(function()
		local ok, has = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, id)
		if ok and not has then
			pcall(BadgeService.AwardBadge, BadgeService, player.UserId, id)
		end
	end)
end

function Badges.init()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		awarded[player] = nil
	end)
end

return Badges

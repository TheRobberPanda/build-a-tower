--!strict
-- Server entry point: create remotes, then init services in dependency order.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage.Shared.Remotes).setup()

local Services = script.Parent.Services
for _, name in
	{
		"Analytics",
		"Badges",
		"PlotService",
		"DataService",
		"ProgressionService",
		"MonetizationService",
		"TowerService",
		"SocialService",
		"AntiCheat",
		"MechanicsService",
		"RunTimerService",
		"LiveRaceService",
		"RoundService",
		"FeaturedService",
		"ContestService",
		"DayNightService",
	}
do
	(require(Services:FindFirstChild(name) :: ModuleScript) :: any).init()
end

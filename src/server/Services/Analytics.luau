--!strict
-- Launch analytics. Onboarding funnel: join -> place -> test run -> verified -> published.
-- Roblox counts each step once per player, so logging it again is harmless.
-- Never let analytics break gameplay: every call is pcall'd.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

local Analytics = {}

local STEPS = table.freeze({
	Joined = 1,
	PlacedPiece = 2,
	StartedTestRun = 3,
	Verified = 4,
	Published = 5,
})
export type Step = "Joined" | "PlacedPiece" | "StartedTestRun" | "Verified" | "Published"

local reached: { [Player]: { [string]: boolean } } = {}

function Analytics.step(player: Player, step: Step)
	local seen = reached[player]
	if not seen or seen[step] then
		return
	end
	seen[step] = true
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, STEPS[step], step)
	end)
end

-- Custom events, e.g. RaceStarted / RaceFinished.
function Analytics.event(player: Player, name: string, value: number?)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1)
	end)
end

function Analytics.init()
	local function added(player: Player)
		reached[player] = {}
		Analytics.step(player, "Joined")
	end
	Players.PlayerAdded:Connect(added)
	for _, p in Players:GetPlayers() do
		added(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		reached[player] = nil
	end)
end

return Analytics

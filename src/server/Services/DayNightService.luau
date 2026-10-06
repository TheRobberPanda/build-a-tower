--!strict
-- Day/night cycle. The server drives Lighting.ClockTime (it replicates) and
-- flips the tagged pieces when day turns to night: SunBlocks are solid by day,
-- MoonBlocks at night, Lamps light up and invisible platforms shimmer at night.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local DayNightService = {}

function DayNightService.isDay(clock: number): boolean
	return clock >= 6 and clock < 18
end

local function apply(inst: Instance, day: boolean)
	if inst:IsA("BasePart") and inst.Name == "InvisiblePlatform" then
		inst.Transparency = if day then 1 else 0.85 -- a faint shimmer at night is the only hint
		inst.Material = Enum.Material.Neon
	elseif inst:IsA("BasePart") and inst.Name ~= "Lamp" then
		local solid = (inst.Name == "SunBlock") == day
		inst.CanCollide = solid
		inst.Transparency = if solid then 0 else 0.8
	else
		local light = inst:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = not day
		end
	end
end

function DayNightService.init()
	local day = DayNightService.isDay(Lighting.ClockTime)
	for _, tag in { "SunBlock", "MoonBlock", "Lamp", "InvisiblePlatform" } do
		for _, inst in CollectionService:GetTagged(tag) do
			apply(inst, day)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			apply(inst, day)
		end)
	end
	RunService.Heartbeat:Connect(function(dt)
		Lighting.ClockTime = (Lighting.ClockTime + dt * 24 / Config.DAY_SECONDS) % 24
		local now = DayNightService.isDay(Lighting.ClockTime)
		if now ~= day then
			day = now
			for _, tag in { "SunBlock", "MoonBlock", "Lamp", "InvisiblePlatform" } do
				for _, inst in CollectionService:GetTagged(tag) do
					apply(inst, day)
				end
			end
		end
	end)
end

return DayNightService

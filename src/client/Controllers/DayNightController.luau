--!strict
-- Day/night clock, left side under the Shop and Camera buttons: a dial whose hand follows Lighting.ClockTime (the
-- server drives it), a sun or moon in the middle, and which blocks are solid now
-- plus the time until they swap. Pulses when day turns to night and back.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)

local DayNightController = {}

local DAY = Color3.fromRGB(255, 200, 60)
local NIGHT = Color3.fromRGB(110, 130, 255)

local dial: Frame
local hand: Frame
local icon: TextLabel
local title: TextLabel
local detail: TextLabel
local scale: UIScale

local function isDay(t: number): boolean
	return t >= 6 and t < 18
end

function DayNightController.init()
	local gui = Kit.new("ScreenGui", {
		Name = "DayNightUI",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local panel = Kit.panel({
		Name = "Clock",
		Position = UDim2.fromScale(0.015, 0.375),
		Size = UDim2.fromScale(0.2, 0.09),
		Parent = gui,
	})
	Kit.new("UIAspectRatioConstraint", { AspectRatio = 3.4, Parent = panel })
	Kit.new("UISizeConstraint", { MinSize = Vector2.new(150, 44), Parent = panel })
	scale = Kit.new("UIScale", { Parent = panel })
	-- Dial: a round face with 12 ticks, the hand turns once per day.
	dial = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.03, 0.5),
		Size = UDim2.fromScale(0.85, 0.85),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = DAY,
		Parent = panel,
	}, { Kit.corner(0.5), Kit.stroke(2) })
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + math.sin(a) * 0.4, 0.5 - math.cos(a) * 0.4),
			Size = UDim2.fromScale(0.06, 0.06),
			BackgroundColor3 = Theme.Panel,
			Parent = dial,
		}, { Kit.corner(0.5) })
	end
	-- The hand: a bar from the centre; the frame turns around the dial's centre.
	local pivot = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = dial,
	})
	hand = pivot
	Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.08, 0.38),
		BackgroundColor3 = Theme.Panel,
		Parent = pivot,
	}, { Kit.corner(0.5) })
	icon = Kit.label("☀", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		ZIndex = 2,
		Parent = dial,
	})
	title = Kit.label("Day", {
		Position = UDim2.fromScale(0.3, 0.08),
		Size = UDim2.fromScale(0.67, 0.46),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	detail = Kit.label("", {
		Position = UDim2.fromScale(0.3, 0.54),
		Size = UDim2.fromScale(0.67, 0.36),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.BodyFont,
		TextColor3 = Theme.TextDim,
		Parent = panel,
	})
end

function DayNightController.start()
	local wasDay: boolean? = nil
	RunService.RenderStepped:Connect(function()
		local t = Lighting.ClockTime
		local day = isDay(t)
		hand.Rotation = t / 24 * 360
		-- Game seconds until the swap: a full day is Config.DAY_SECONDS.
		local hoursLeft = if day then 18 - t elseif t >= 18 then 30 - t else 6 - t
		local left = math.ceil(hoursLeft / 24 * Config.DAY_SECONDS)
		detail.Text = string.format("%s in %d:%02d", if day then "Night" else "Day", left // 60, left % 60)
		if day ~= wasDay then
			title.Text = if day then "Day: Sun blocks solid" else "Night: Moon blocks solid"
			title.TextColor3 = if day then DAY else NIGHT
			icon.Text = if day then "☀" else "☾"
			TweenService:Create(dial, Theme.FAST, { BackgroundColor3 = if day then DAY else NIGHT }):Play()
			if wasDay ~= nil then
				scale.Scale = 1.25
				TweenService:Create(scale, Theme.BOUNCY, { Scale = 1 }):Play()
			end
			wasDay = day
		end
	end)
end

return DayNightController

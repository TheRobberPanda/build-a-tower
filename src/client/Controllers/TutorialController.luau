--!strict
-- First-time "how to play" cards, shown once per account (the server remembers).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)

local TutorialController = {}

local player = Players.LocalPlayer

local PAGES = {
	{ "Build", "Pick a piece from the bar at the bottom and tap the grid to place it. Build upwards!" },
	{
		"Hide secrets",
		"Fake walls, invisible platforms, teleporters and hidden doors. Anyone who finds a secret may use it.",
	},
	{
		"Prove it",
		"Add a Finish on top and press Test Run. Climb your own tower to unlock Menu → Publish.",
	},
	{ "Race", "Menu → Browse to race other towers, beat the record ghost, or press Live to race friends." },
}

local panel: Frame
local title: TextLabel
local body: TextLabel
local nextButton: TextButton
local page = 1
local shown = false

local function render()
	title.Text = string.format("%s  (%d/%d)", PAGES[page][1], page, #PAGES)
	body.Text = PAGES[page][2]
	nextButton.Text = if page == #PAGES then "Let's go!" else "Next"
end

local function close()
	panel.Visible = false
	Remotes.event("TutorialDone"):FireServer()
end

function TutorialController.init()
	local gui = Kit.new("ScreenGui", {
		Name = "TutorialUI",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 10,
		Parent = player:WaitForChild("PlayerGui"),
	})
	panel = Kit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.45, 0.4),
		Visible = false,
		Parent = gui,
	})
	Kit.new(
		"UISizeConstraint",
		{ MinSize = Vector2.new(280, 180), MaxSize = Vector2.new(520, 320), Parent = panel }
	)
	title = Kit.label(
		"",
		{ Position = UDim2.fromScale(0.05, 0.05), Size = UDim2.fromScale(0.9, 0.2), Parent = panel }
	)
	body = Kit.label("", {
		Position = UDim2.fromScale(0.07, 0.3),
		Size = UDim2.fromScale(0.86, 0.38),
		TextWrapped = true,
		Font = Theme.BodyFont,
		Parent = panel,
	})
	Kit.button("Skip", Theme.PanelLight, close, {
		Position = UDim2.fromScale(0.05, 0.74),
		Size = UDim2.fromScale(0.3, 0.2),
		Parent = panel,
	})
	nextButton = Kit.button("Next", Theme.Success, function()
		if page >= #PAGES then
			close()
		else
			page += 1
			render()
		end
	end, { Position = UDim2.fromScale(0.5, 0.74), Size = UDim2.fromScale(0.45, 0.2), Parent = panel })
end

function TutorialController.start()
	Remotes.event("Progress").OnClientEvent:Connect(function(p)
		if not shown and type(p) == "table" and p.tutorialDone == false then
			shown = true
			page = 1
			render()
			panel.Visible = true
		end
	end)
end

return TutorialController

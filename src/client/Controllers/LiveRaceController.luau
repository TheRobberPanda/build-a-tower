--!strict
-- Live race UI: lobby banner (join / leave), opponents as coloured ghosts on your
-- plot during the race, and live standings.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GhostController = require(script.Parent.GhostController)
local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)

local LiveRaceController = {}

local player = Players.LocalPlayer
local COLORS = {
	Color3.fromRGB(255, 120, 120),
	Color3.fromRGB(255, 200, 90),
	Color3.fromRGB(150, 255, 140),
	Color3.fromRGB(200, 140, 255),
	Color3.fromRGB(255, 150, 220),
	Color3.fromRGB(140, 220, 255),
	Color3.fromRGB(255, 255, 160),
}

local gui: ScreenGui
local banner: Frame
local bannerText: TextLabel
local joinButton: TextButton
local standingsPanel: Frame
local standingsText: TextLabel

local lobbyId = 0 -- lobby shown in the banner
local joinedId = 0 -- lobby we joined
local lobbyEndsAt = 0
local lobbyLabel = ""

type Opponent = { model: Model, from: Vector3, to: Vector3, at: number }
local opponents: { [number]: Opponent } = {}
local colorIndex = 0

local function plotOrigin(): Vector3?
	local plots = workspace:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot_" .. player.UserId)
	local origin = plot and plot:GetAttribute("Origin")
	return if typeof(origin) == "Vector3" then origin else nil
end

local function clearOpponents()
	for _, o in opponents do
		o.model:Destroy()
	end
	table.clear(opponents)
end

local function renderBanner()
	if lobbyId == 0 then
		banner.Visible = false
		return
	end
	banner.Visible = true
	local seconds = math.max(0, math.ceil(lobbyEndsAt - os.clock()))
	bannerText.Text = string.format("%s  ·  starts in %ds", lobbyLabel, seconds)
	joinButton.Text = if joinedId == lobbyId then "Leave" else "Join"
	joinButton.BackgroundColor3 = if joinedId == lobbyId then Theme.Danger else Theme.Success
end

-- Called from a browse card.
function LiveRaceController.host(ownerId: number)
	task.spawn(function()
		local ok, hosted = pcall(function()
			return Remotes.func("HostLiveRace"):InvokeServer(ownerId)
		end)
		if ok and hosted then
			joinedId = -1 -- set properly when the lobby broadcast arrives
		end
	end)
end

function LiveRaceController.init()
	gui = Kit.new("ScreenGui", {
		Name = "LiveRaceUI",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 4,
		Parent = player:WaitForChild("PlayerGui"),
	})
	banner = Kit.panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.8), -- above the hotbar, clear of the run timer
		Size = UDim2.fromScale(0.5, 0.07),
		Visible = false,
		Parent = gui,
	})
	bannerText = Kit.label("", {
		Position = UDim2.fromScale(0.03, 0.1),
		Size = UDim2.fromScale(0.72, 0.8),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.BodyFont,
		Parent = banner,
	})
	joinButton = Kit.button("Join", Theme.Success, function()
		if joinedId == lobbyId then
			joinedId = 0
			Remotes.event("LeaveLiveRace"):FireServer()
			renderBanner()
			return
		end
		local id = lobbyId
		task.spawn(function()
			local ok, joined = pcall(function()
				return Remotes.func("JoinLiveRace"):InvokeServer(id)
			end)
			if ok and joined then
				joinedId = id
				renderBanner()
			end
		end)
	end, { Position = UDim2.fromScale(0.77, 0.12), Size = UDim2.fromScale(0.21, 0.76), Parent = banner })

	standingsPanel = Kit.panel({
		Position = UDim2.fromScale(0.015, 0.24),
		Size = UDim2.fromScale(0.18, 0.3),
		Visible = false,
		Parent = gui,
	})
	standingsText = Kit.label("", {
		Position = UDim2.fromScale(0.06, 0.04),
		Size = UDim2.fromScale(0.88, 0.92),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextScaled = false,
		TextSize = 16,
		TextWrapped = true,
		Font = Theme.BodyFont,
		Parent = standingsPanel,
	})
end

function LiveRaceController.start()
	Remotes.event("LiveRaceLobby").OnClientEvent:Connect(function(info)
		if type(info) ~= "table" or type(info.id) ~= "number" then
			return
		end
		if info.closed then
			if lobbyId == info.id then
				lobbyId = 0
			end
			if joinedId == info.id then
				joinedId = 0
			end
		else
			lobbyId = info.id
			lobbyEndsAt = os.clock() + (tonumber(info.seconds) or 0)
			lobbyLabel = string.format(
				"%s is racing %s (%d in)",
				tostring(info.host),
				tostring(info.tower),
				tonumber(info.count) or 1
			)
			if joinedId == -1 then
				joinedId = info.id -- we hosted it
			end
		end
		renderBanner()
	end)

	Remotes.event("LiveRaceStarted").OnClientEvent:Connect(function()
		clearOpponents()
		colorIndex = 0
		standingsText.Text = "Racing..."
		standingsPanel.Visible = true
	end)

	Remotes.event("LiveRacePositions").OnClientEvent:Connect(function(list)
		local origin = plotOrigin()
		if type(list) ~= "table" or not origin then
			return
		end
		local seen: { [number]: boolean } = {}
		for _, entry in list do
			if type(entry) ~= "table" or type(entry.id) ~= "number" or typeof(entry.pos) ~= "Vector3" then
				continue
			end
			if entry.id == player.UserId then
				continue
			end
			seen[entry.id] = true
			local world = origin + entry.pos
			local o = opponents[entry.id]
			if not o then
				colorIndex = colorIndex % #COLORS + 1
				local model = GhostController.newGhost(COLORS[colorIndex])
				model.Name = "Racer_" .. tostring(entry.name)
				model.Parent = workspace
				o = { model = model, from = world, to = world, at = os.clock() }
				opponents[entry.id] = o
			end
			o.from = o.model:GetPivot().Position
			o.to = world
			o.at = os.clock()
		end
		for id, o in opponents do
			if not seen[id] then
				o.model:Destroy()
				opponents[id] = nil
			end
		end
	end)

	Remotes.event("LiveRaceStandings").OnClientEvent:Connect(function(list, final)
		if type(list) ~= "table" then
			return
		end
		local lines = { if final then "Final standings" else "Standings" }
		for _, s in list do
			if type(s) == "table" then
				table.insert(
					lines,
					string.format(
						"%d. %s  %s",
						tonumber(s.place) or 0,
						tostring(s.name),
						if type(s.ms) == "number" then Format.ms(s.ms) else "DNF"
					)
				)
			end
		end
		standingsText.Text = table.concat(lines, "\n")
		standingsPanel.Visible = true
		if final then
			clearOpponents()
			task.delay(10, function()
				standingsPanel.Visible = false
			end)
		end
	end)

	-- Smooth opponents between 0.2 s updates; keep the banner countdown ticking.
	RunService.RenderStepped:Connect(function()
		for _, o in opponents do
			local alpha = math.clamp((os.clock() - o.at) / 0.2, 0, 1)
			o.model:PivotTo(CFrame.new(o.from:Lerp(o.to, alpha)))
		end
		if lobbyId ~= 0 then
			renderBanner()
		end
	end)
end

return LiveRaceController

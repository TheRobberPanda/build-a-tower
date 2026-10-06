--!strict
-- Round HUD: phase + clock at the top, a big banner on phase changes, the
-- 1-5 star vote with donate buttons, and the results board.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local State = require(script.Parent.Parent.State)
local GhostController = require(script.Parent.GhostController)
local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)

local RoundController = {}

local player = Players.LocalPlayer

local gui: ScreenGui
local clock: TextLabel
local timerPanel: Frame
local timerTitle: TextLabel
local timerText: TextLabel
local timerFill: Frame
local stepsPanel: Frame
local explained = 0 -- build phases the explainer was shown this session
local banner: TextLabel
local votePanel: Frame
local voteTitle: TextLabel
local starButtons: { TextButton } = {}
local donateButtons: { TextButton } = {}
local resultsPanel: Frame
local lobbyPanel: Frame
local queuePanel: Frame
local resultsText: TextLabel
local state: { [string]: any } = { phase = "waiting" }

local TITLES = {
	waiting = "Waiting for players",
	intermission = "Next round in",
	build = "BUILD + CLIMB your tower",
	race = "RACE",
	vote = "Rate this tower",
	results = "Results",
}

local function flash(text: string, color: Color3?)
	banner.Text = text
	banner.TextColor3 = color or Theme.Text
	Kit.show(banner, true)
	local current = text
	task.delay(3, function()
		if banner.Text == current then
			banner.Visible = false
		end
	end)
end

local function updateClock()
	local phase = state.phase
	local title = TITLES[phase] or ""
	if phase == "race" and state.builderName then
		title = string.format("RACE %d/%d: %s's tower", state.index or 1, state.count or 1, state.builderName)
		if state.builder == player.UserId then
			title = "Your tower is being raced"
		end
	end
	local left = math.max(0, math.ceil((state.endsAt or 0) - workspace:GetServerTimeNow()))
	if not State.inRound and (phase == "build" or phase == "race" or phase == "vote") then
		title = if State.lobbyMode == "queue"
			then "Round in progress, you're in the next one"
			else "Round in progress"
	end
	if phase == "waiting" then
		clock.Text = title
	else
		clock.Text = string.format("%s  %d:%02d", title, left // 60, left % 60)
	end
	clock.TextColor3 = if phase ~= "waiting" and left <= 10 then Theme.Danger else Theme.Text
	-- Members building get the big timer instead of the one-line clock.
	local building = phase == "build" and State.inRound
	timerPanel.Visible = building
	clock.Visible = not building
	if building then
		local total = math.max((state.endsAt or 0) - (state.startedAt or 0), 1)
		local frac = math.clamp(((state.endsAt or 0) - workspace:GetServerTimeNow()) / total, 0, 1)
		timerText.Text = string.format("%d:%02d", left // 60, left % 60)
		timerFill.Size = UDim2.fromScale(frac, 1)
		local urgent = left <= 30
		timerFill.BackgroundColor3 = if urgent
			then Theme.Danger
			elseif frac < 0.5 then Theme.Primary
			else Theme.Success
		timerText.TextColor3 = if urgent then Theme.Danger else Theme.Text
		timerTitle.Text = if State.verified
			then "Climbed! Your tower is in the race"
			else "Build up to the flag, then CLIMB it"
	end
end

-- 1-2-3 of a round, shown at the start of your first build phases.
local function showSteps()
	Kit.show(stepsPanel, true)
	task.delay(14, function()
		stepsPanel.Visible = false
	end)
end

local function buildTimer()
	timerPanel = Kit.panel({
		Name = "BuildTimer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.01),
		Size = UDim2.fromScale(0.34, 0.1),
		Visible = false,
		Parent = gui,
	})
	Kit.new("UIAspectRatioConstraint", { AspectRatio = 5, Parent = timerPanel })
	timerTitle = Kit.label("", {
		Position = UDim2.fromScale(0.03, 0.06),
		Size = UDim2.fromScale(0.64, 0.42),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.BodyFont,
		Parent = timerPanel,
	})
	timerText = Kit.label("5:00", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.97, 0.02),
		Size = UDim2.fromScale(0.3, 0.55),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = timerPanel,
	})
	local bar = Kit.new("Frame", {
		Position = UDim2.fromScale(0.03, 0.62),
		Size = UDim2.fromScale(0.94, 0.26),
		BackgroundColor3 = Theme.PanelLight,
		Parent = timerPanel,
	}, { Kit.corner(0.5) })
	timerFill = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Success,
		Parent = bar,
	}, { Kit.corner(0.5) })

	stepsPanel = Kit.panel({
		FreeCursor = true,
		Name = "HowToPlay",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.55),
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	Kit.new("UIAspectRatioConstraint", { AspectRatio = 2.1, Parent = stepsPanel })
	Kit.label("How a round works", {
		Position = UDim2.fromScale(0.03, 0.03),
		Size = UDim2.fromScale(0.7, 0.11),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 21,
		Parent = stepsPanel,
	})
	local steps = {
		{
			"rbxassetid://132798033157454",
			string.format("1. Build up to the flag (%d:00)", Config.BUILD_SECONDS // 60),
		},
		{ "rbxassetid://92390672268585", "2. Climb your own tower before time runs out" },
		{ "rbxassetid://110557618052012", "3. Race the other towers. First to the top wins!" },
	}
	for i, step in steps do
		local x = 0.03 + (i - 1) * 0.32
		Kit.new("ImageLabel", {
			Position = UDim2.fromScale(x, 0.17),
			Size = UDim2.fromScale(0.3, 0.6),
			Image = step[1],
			ScaleType = Enum.ScaleType.Crop,
			BackgroundTransparency = 1,
			ZIndex = 21,
			Parent = stepsPanel,
		}, { Kit.corner(0.06) })
		Kit.label(step[2], {
			Position = UDim2.fromScale(x, 0.79),
			Size = UDim2.fromScale(0.3, 0.17),
			Font = Theme.BodyFont,
			TextWrapped = true,
			ZIndex = 21,
			Parent = stepsPanel,
		})
	end
	Kit.button("Got it", Theme.Success, function()
		stepsPanel.Visible = false
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.97, 0.03),
		Size = UDim2.fromScale(0.18, 0.11),
		ZIndex = 21,
		Parent = stepsPanel,
	})
end

local function setStars(n: number)
	for i, b in starButtons do
		b.TextColor3 = if i <= n then Theme.Primary else Theme.TextDim
	end
end

local function onRound(s: any)
	if type(s) ~= "table" then
		return
	end
	local old = state.phase
	state = s
	local members = if type(s.members) == "table" then s.members else {}
	local inRound = table.find(members, player.UserId) ~= nil
	if inRound ~= State.inRound or s.phase ~= State.roundPhase then
		State.set({ inRound = inRound, roundPhase = s.phase })
	end
	votePanel.Visible = false
	Sounds.music(
		if not inRound
			then "Ambient"
			elseif s.phase == "build" then "BuildMusic"
			elseif s.phase == "race" then "RaceMusic"
			else "Ambient"
	)
	if s.phase ~= old then
		if s.phase == "build" then
			resultsPanel.Visible = false
			flash("Build a tower, then CLIMB it before time runs out!", Theme.Primary)
			Sounds.play("RoundStart")
			if inRound and explained < 2 then
				explained += 1
				showSteps()
			end
		elseif s.phase == "race" then
			flash(
				if s.builder == player.UserId then "Watch them try your tower!" else "First to the top wins!",
				Theme.Accent
			)
		elseif s.phase == "intermission" then
			flash("Round starting soon", Theme.TextDim)
		end
	end
	if s.phase == "vote" then
		local mine = s.builder == player.UserId
		voteTitle.Text = if mine
			then "Your climb is replayed for everyone"
			else string.format(
				"%s's tower%s",
				tostring(s.builderName),
				if s.winnerName then "  (won by " .. tostring(s.winnerName) .. ")" else "  (nobody made it!)"
			)
		setStars(0)
		for _, b in starButtons do
			b.Visible = not mine
		end
		for _, b in donateButtons do
			b.Visible = not mine
			Kit.setEnabled(b, true, Theme.Success)
		end
		Kit.show(votePanel, true)
	end
	updateClock()
end

local function onResults(list: any)
	if type(list) ~= "table" then
		return
	end
	local lines = {}
	for i, r in list do
		if type(r) ~= "table" then
			continue
		end
		table.insert(
			lines,
			string.format(
				"%d. %s  +%d coins  %s%s",
				i,
				tostring(r.name),
				tonumber(r.coins) or 0,
				if r.valid then "" else "(no valid tower) ",
				if type(r.stars) == "number" then string.format("%.1f stars", r.stars) else ""
			)
		)
	end
	resultsText.Text = table.concat(lines, "\n")
	Kit.show(resultsPanel, true)
	Sounds.play("Victory")
	Sounds.play("Cheer")
	task.delay(Config.RESULTS_SECONDS, function()
		resultsPanel.Visible = false
	end)
end

-- Lobby choices (also on the two pads in the lobby).
local function renderLobby()
	local mode = State.lobbyMode
	lobbyPanel.Visible = mode == "lobby" and not State.inRound and State.mode == "build"
	queuePanel.Visible = mode == "queue" and not State.inRound
end

local function buildLobby()
	lobbyPanel = Kit.panel({
		FreeCursor = true,
		Name = "Lobby",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.95),
		Size = UDim2.fromScale(0.5, 0.22),
		Visible = false,
		Parent = gui,
	})
	Kit.new("UIAspectRatioConstraint", { AspectRatio = 3.4, Parent = lobbyPanel })
	Kit.label("Welcome! What do you want to do?", {
		Size = UDim2.fromScale(0.92, 0.26),
		Position = UDim2.fromScale(0.04, 0.06),
		Parent = lobbyPanel,
	})
	Kit.button("Play rounds", Theme.Success, function()
		Remotes.event("SetMode"):FireServer("queue")
	end, {
		Position = UDim2.fromScale(0.04, 0.4),
		Size = UDim2.fromScale(0.44, 0.5),
		Parent = lobbyPanel,
	})
	Kit.button("Free build", Theme.Primary, function()
		Remotes.event("SetMode"):FireServer("free")
	end, {
		Position = UDim2.fromScale(0.52, 0.4),
		Size = UDim2.fromScale(0.44, 0.5),
		Parent = lobbyPanel,
	})
	queuePanel = Kit.panel({
		FreeCursor = true,
		Name = "Queue",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.95),
		Size = UDim2.fromScale(0.4, 0.12),
		Visible = false,
		Parent = gui,
	})
	Kit.new("UIAspectRatioConstraint", { AspectRatio = 5, Parent = queuePanel })
	Kit.label("You're in the queue for the next round", {
		Size = UDim2.fromScale(0.6, 0.6),
		Position = UDim2.fromScale(0.04, 0.2),
		Font = Theme.BodyFont,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = queuePanel,
	})
	Kit.button("Leave", Theme.Danger, function()
		Remotes.event("SetMode"):FireServer("lobby")
	end, {
		Position = UDim2.fromScale(0.7, 0.15),
		Size = UDim2.fromScale(0.26, 0.7),
		Parent = queuePanel,
	})
end

function RoundController.init()
	gui = Kit.new("ScreenGui", {
		Name = "RoundUI",
		ResetOnSpawn = false,
		DisplayOrder = 10, -- above the build UI and run result dialog
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Parent = player:WaitForChild("PlayerGui"),
	})
	clock = Kit.label("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.01),
		Size = UDim2.fromScale(0.5, 0.055),
		Parent = gui,
	})
	banner = Kit.label("", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.17),
		Size = UDim2.fromScale(0.8, 0.08),
		Visible = false,
		Parent = gui,
	})

	votePanel = Kit.panel({
		FreeCursor = true,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.97),
		Size = UDim2.fromScale(0.5, 0.2),
		Visible = false,
		Parent = gui,
	})
	Kit.new("UIAspectRatioConstraint", { AspectRatio = 3.2, Parent = votePanel })
	voteTitle = Kit.label(
		"",
		{ Size = UDim2.fromScale(0.94, 0.28), Position = UDim2.fromScale(0.03, 0.04), Parent = votePanel }
	)
	for i = 1, 5 do
		local b = Kit.button("★", Theme.PanelLight, function()
			setStars(i)
			Remotes.event("RoundVote"):FireServer(i)
		end, {
			Position = UDim2.fromScale(0.04 + (i - 1) * 0.12, 0.38),
			Size = UDim2.fromScale(0.11, 0.5),
			TextColor3 = Theme.TextDim,
			Parent = votePanel,
		})
		starButtons[i] = b
	end
	for i, amount in Config.DONATE_AMOUNTS do
		local b: TextButton
		b = Kit.button("Give " .. amount, Theme.Success, function()
			Remotes.event("RoundDonate"):FireServer(amount)
			for _, other in donateButtons do
				Kit.setEnabled(other, false, Theme.Success)
			end
		end, {
			Position = UDim2.fromScale(0.66 + (i - 1) * 0.165, 0.38),
			Size = UDim2.fromScale(0.15, 0.5),
			Parent = votePanel,
		})
		donateButtons[i] = b
	end

	resultsPanel = Kit.panel({
		FreeCursor = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		Visible = false,
		Parent = gui,
	})
	Kit.new("UIAspectRatioConstraint", { AspectRatio = 2, Parent = resultsPanel })
	Kit.label("Round results", {
		Size = UDim2.fromScale(1, 0.15),
		Position = UDim2.fromScale(0, 0.03),
		TextColor3 = Theme.Primary,
		Parent = resultsPanel,
	})
	buildLobby()
	buildTimer()
	resultsText = Kit.label("", {
		Size = UDim2.fromScale(0.9, 0.75),
		Position = UDim2.fromScale(0.05, 0.2),
		Font = Theme.BodyFont,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = resultsPanel,
	})
end

function RoundController.start()
	Remotes.event("Mode").OnClientEvent:Connect(function(mode)
		if mode == "lobby" or mode == "queue" or mode == "free" then
			State.set({ lobbyMode = mode })
		end
	end)
	State.Changed:Connect(renderLobby)
	Remotes.event("Round").OnClientEvent:Connect(onRound)
	Remotes.event("RoundResults").OnClientEvent:Connect(onResults)
	Remotes.event("RoundReplay").OnClientEvent:Connect(function(replay)
		if type(replay) == "table" then
			GhostController.playReplay(replay)
		end
	end)
	while true do
		updateClock()
		task.wait(0.25)
	end
end

return RoundController

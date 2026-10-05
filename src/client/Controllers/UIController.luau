--!strict
-- All V1 screens: build hotbar + tools, run HUD, publish dialog, browse list,
-- leaderboard and results. Renders State and sends intents; computes nothing that matters.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PieceDefs = require(ReplicatedStorage.Shared.PieceDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local State = require(script.Parent.Parent.State)
local BuildController = require(script.Parent.BuildController)

local UIController = {}

local player = Players.LocalPlayer

-- Same colours as the parts on the plot so slots read at a glance.
local PIECE_COLORS: { [string]: Color3 } = {
	Block = Color3.fromRGB(163, 162, 165),
	Platform = Color3.fromRGB(110, 153, 202),
	Ramp = Color3.fromRGB(196, 140, 98),
	JumpPad = Color3.fromRGB(255, 176, 0),
	Teleporter = Color3.fromRGB(170, 85, 255),
	FakeWall = Color3.fromRGB(120, 120, 128),
	InvisiblePlatform = Color3.fromRGB(220, 240, 255),
	Finish = Color3.fromRGB(0, 200, 90),
}
local SHORT_NAMES: { [string]: string } = {
	InvisiblePlatform = "Invisible",
	FakeWall = "Fake Wall",
	JumpPad = "Jump Pad",
	Teleporter = "Teleport",
}

local gui: ScreenGui
local buildLayer: Frame
local runLayer: Frame
local slots: { [number]: Frame } = {}
local budgetLabel: TextLabel
local verifiedLabel: TextLabel
local deleteButton: TextButton
local settingButton: TextButton
local publishButton: TextButton
local testButton: TextButton
local timerLabel: TextLabel
local runNameLabel: TextLabel
local modals: { [string]: Frame } = {}
local openModalName: string? = nil

local nameCache: { [number]: string } = {}
local function userName(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and type(name) == "string" then name else ("User " .. userId)
	nameCache[userId] = result
	return result
end

local function openModal(name: string?)
	for key, frame in modals do
		if key ~= name and frame.Visible then
			Kit.show(frame, false)
		end
	end
	openModalName = name
	if name then
		Kit.show(modals[name], true)
	end
end

-- Centered dialog with a title and a close button. Content goes in the returned body.
local function makeModal(name: string, title: string, sizeY: number): Frame
	local panel = Kit.panel({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, sizeY),
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	Kit.new(
		"UISizeConstraint",
		{ MinSize = Vector2.new(300, 0), MaxSize = Vector2.new(560, math.huge), Parent = panel }
	)
	Kit.label(title, {
		Name = "Title",
		Size = UDim2.fromScale(0.75, 0.13),
		Position = UDim2.fromScale(0.04, 0.03),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	Kit.button("X", Theme.Danger, function()
		openModal(nil)
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.97, 0.03),
		Size = UDim2.fromScale(0.13, 0.13),
		Parent = panel,
	}).SizeConstraint =
		Enum.SizeConstraint.RelativeYY
	local body = Kit.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.04, 0.19),
		Size = UDim2.fromScale(0.92, 0.77),
		Parent = panel,
	})
	modals[name] = panel
	return body
end

local function listFrame(parent: Instance): ScrollingFrame
	local scroll: ScrollingFrame = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		BorderSizePixel = 0,
		Parent = parent,
	})
	Kit.new(
		"UIListLayout",
		{ Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll }
	)
	return scroll
end

local function clearList(scroll: ScrollingFrame)
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- A fixed-height row (in pixels, so text stays readable inside a scrolling list).
local function row(scroll: ScrollingFrame, order: number): Frame
	return Kit.new("Frame", {
		BackgroundColor3 = Theme.PanelLight,
		Size = UDim2.new(1, -8, 0, 52),
		LayoutOrder = order,
		Parent = scroll,
	}, { Kit.corner(0.2) })
end

---------------------------------------------------------------- build layer

local function buildHotbar()
	local bar = Kit.new("Frame", {
		Name = "Hotbar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.985),
		Size = UDim2.fromScale(0.5, 0.11),
		Parent = buildLayer,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0.01, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = bar,
	})
	for _, def in PieceDefs.list do
		local slot: TextButton = Kit.new("TextButton", {
			Name = def.name,
			LayoutOrder = def.id,
			Size = UDim2.fromScale(0.115, 1),
			BackgroundColor3 = Theme.Panel,
			AutoButtonColor = true,
			Text = "",
			Parent = bar,
		}, {
			Kit.aspect(1),
			Kit.corner(0.18),
			Kit.new("UIStroke", { Name = "Select", Thickness = 3, Color = Theme.Stroke }),
		})
		local tileProps: { [string]: any } = {
			Name = "Tile",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.04),
			Size = UDim2.fromScale(0.66, 0.66),
			Parent = slot,
		}
		if Theme.PieceIconSheet ~= "" then
			local cell = Theme.PieceIconCell
			local i = def.id - 1
			tileProps.BackgroundTransparency = 1
			tileProps.Image = Theme.PieceIconSheet
			tileProps.ImageRectSize = Vector2.new(cell, cell)
			tileProps.ImageRectOffset = Vector2.new((i % 4) * cell, (i // 4) * cell)
			Kit.new("ImageLabel", tileProps)
		else
			tileProps.BackgroundColor3 = PIECE_COLORS[def.name]
			tileProps.Size = UDim2.fromScale(0.55, 0.55)
			tileProps.Position = UDim2.fromScale(0.5, 0.1)
			Kit.new("Frame", tileProps, { Kit.corner(0.15), Kit.stroke(1.5) })
		end
		Kit.label(SHORT_NAMES[def.name] or def.name, {
			Size = UDim2.fromScale(0.94, 0.26),
			Position = UDim2.fromScale(0.03, 0.7),
			Font = Theme.BodyFont,
			Parent = slot,
		})
		Kit.label(tostring(def.id), {
			Size = UDim2.fromScale(0.25, 0.25),
			Position = UDim2.fromScale(0.04, 0.03),
			TextColor3 = Theme.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = slot,
		})
		slot.Activated:Connect(function()
			Kit.pop(slot)
			State.set({ selected = def.id, deleting = false })
		end)
		slots[def.id] = slot
	end

	budgetLabel = Kit.label("Pieces 0/" .. Config.PIECE_BUDGET, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.86),
		Size = UDim2.fromScale(0.3, 0.04),
		Parent = buildLayer,
	})
end

local function buildTools()
	-- Right edge, above the mobile jump button.
	local column = Kit.new("Frame", {
		Name = "Tools",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.985, 0.4),
		Size = UDim2.fromScale(0.14, 0.5),
		Parent = buildLayer,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(170, math.huge), Parent = column })
	Kit.new("UIListLayout", {
		Padding = UDim.new(0.025, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = column,
	})
	local function tool(order: number, text: string, color: Color3, fn: () -> ()): TextButton
		return Kit.button(text, color, fn, {
			LayoutOrder = order,
			Size = UDim2.fromScale(1, 0.145),
			Parent = column,
		})
	end
	tool(1, "Rotate", Theme.Accent, function()
		State.set({ rotation = (State.rotation + 1) % 4 })
	end)
	settingButton = tool(2, "", Theme.Accent, BuildController.cycleSetting)
	deleteButton = tool(3, "Delete", Theme.PanelLight, function()
		State.set({ deleting = not State.deleting })
	end)
	testButton = tool(4, "Test Run", Theme.Success, function()
		Remotes.event("StartRun"):FireServer(player.UserId)
	end)
	publishButton = tool(5, "Publish", Theme.Primary, function()
		openModal("Publish")
	end)
	tool(6, "Browse", Theme.Accent, function()
		UIController.openBrowse()
	end)

	verifiedLabel = Kit.label("", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.985, 0.08),
		Size = UDim2.fromScale(0.25, 0.04),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Theme.BodyFont,
		Parent = buildLayer,
	})
end

---------------------------------------------------------------- run layer

local function buildRunHud()
	-- Top centre only: bottom corners stay clear for thumbstick and jump.
	local top = Kit.panel({
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.02),
		Size = UDim2.fromScale(0.26, 0.12),
		Parent = runLayer,
	})
	Kit.new("UISizeConstraint", { MinSize = Vector2.new(170, 0), Parent = top })
	runNameLabel = Kit.label("", {
		Position = UDim2.fromScale(0.05, 0.05),
		Size = UDim2.fromScale(0.9, 0.3),
		TextColor3 = Theme.TextDim,
		Font = Theme.BodyFont,
		Parent = top,
	})
	timerLabel = Kit.label("0:00.000", {
		Position = UDim2.fromScale(0.05, 0.35),
		Size = UDim2.fromScale(0.9, 0.6),
		Parent = top,
	})
	Kit.button("Quit", Theme.Danger, function()
		Remotes.event("StopRun"):FireServer()
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.985, 0.02),
		Size = UDim2.fromScale(0.1, 0.07),
		Parent = runLayer,
	})
	-- Back to the start with a fresh timer, same tower.
	Kit.button("Restart", Theme.Accent, function()
		Remotes.event("StartRun"):FireServer(State.runOwner)
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.985, 0.1),
		Size = UDim2.fromScale(0.1, 0.07),
		Parent = runLayer,
	})
end

---------------------------------------------------------------- modals

local publishStatus: TextLabel
local publishBox: TextBox
local publishConfirm: TextButton

local function buildPublish()
	local body = makeModal("Publish", "Publish tower", 0.5)
	publishBox = Kit.new("TextBox", {
		Size = UDim2.fromScale(1, 0.25),
		BackgroundColor3 = Theme.PanelLight,
		Font = Theme.BodyFont,
		PlaceholderText = "Tower name",
		Text = "",
		TextColor3 = Theme.Text,
		TextScaled = true,
		ClearTextOnFocus = false,
		Parent = body,
	}, { Kit.corner(0.2), Kit.textSize(28), Kit.padding(0.12) })
	publishStatus = Kit.label("", {
		Position = UDim2.fromScale(0, 0.32),
		Size = UDim2.fromScale(1, 0.2),
		Font = Theme.BodyFont,
		TextColor3 = Theme.TextDim,
		Parent = body,
	})
	local busy = false
	publishConfirm = Kit.button("Publish", Theme.Primary, function()
		if busy then
			return
		end
		local name = string.sub(publishBox.Text, 1, Config.TOWER_NAME_MAX)
		if #name == 0 then
			publishStatus.Text = "Give your tower a name"
			return
		end
		busy = true
		publishStatus.Text = "Publishing..."
		local ok, success, err = pcall(function()
			return Remotes.func("Publish"):InvokeServer(name)
		end)
		busy = false
		if ok and success then
			publishStatus.Text = "Published! Others can race it now."
		else
			publishStatus.Text = "Failed: " .. tostring(if ok then err else "network")
		end
	end, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.5, 0.28),
		Parent = body,
	})
end

local browseList: ScrollingFrame
local leaderboardList: ScrollingFrame
local leaderboardTitle: TextLabel

local function buildBrowse()
	browseList = listFrame(makeModal("Browse", "Towers", 0.75))
end

local function buildLeaderboard()
	local body = makeModal("Leaderboard", "Best times", 0.75)
	leaderboardTitle = Kit.label("", {
		Size = UDim2.fromScale(1, 0.1),
		Font = Theme.BodyFont,
		TextColor3 = Theme.TextDim,
		Parent = body,
	})
	local holder = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0.12),
		Size = UDim2.fromScale(1, 0.88),
		Parent = body,
	})
	leaderboardList = listFrame(holder)
end

local resultTime: TextLabel
local resultNote: TextLabel
local resultTimesButton: TextButton

local function buildResults()
	local body = makeModal("Results", "Finished!", 0.5)
	resultTime = Kit.label("", { Size = UDim2.fromScale(1, 0.35), Parent = body })
	resultNote = Kit.label("", {
		Position = UDim2.fromScale(0, 0.38),
		Size = UDim2.fromScale(1, 0.2),
		Font = Theme.BodyFont,
		TextColor3 = Theme.TextDim,
		Parent = body,
	})
	resultTimesButton = Kit.button("Times", Theme.Accent, function()
		UIController.openLeaderboard(State.runOwner)
	end, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0.05, 1),
		Size = UDim2.fromScale(0.42, 0.28),
		Parent = body,
	})
	Kit.button("OK", Theme.Success, function()
		openModal(nil)
	end, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(0.95, 1),
		Size = UDim2.fromScale(0.42, 0.28),
		Parent = body,
	})
end

---------------------------------------------------------------- data-driven screens

function UIController.openBrowse()
	openModal("Browse")
	clearList(browseList)
	Kit.label("Loading...", { Size = UDim2.new(1, 0, 0, 40), Font = Theme.BodyFont, Parent = browseList })
	task.spawn(function()
		local ok, list = pcall(function()
			return Remotes.func("Browse"):InvokeServer()
		end)
		clearList(browseList)
		if not ok or type(list) ~= "table" or #list == 0 then
			Kit.label(if ok then "No towers published yet" else "Could not load", {
				Size = UDim2.new(1, 0, 0, 40),
				Font = Theme.BodyFont,
				Parent = browseList,
			})
			return
		end
		for i, entry in list do
			local r = row(browseList, i)
			Kit.label(tostring(entry.name), {
				Position = UDim2.fromScale(0.03, 0.05),
				Size = UDim2.fromScale(0.5, 0.55),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = r,
			})
			local by = Kit.label(string.format("%d pieces", tonumber(entry.pieces) or 0), {
				Position = UDim2.fromScale(0.03, 0.6),
				Size = UDim2.fromScale(0.5, 0.35),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.TextDim,
				Font = Theme.BodyFont,
				Parent = r,
			})
			local owner = tonumber(entry.owner) or 0
			task.spawn(function()
				by.Text = string.format("by %s · %d pieces", userName(owner), tonumber(entry.pieces) or 0)
			end)
			Kit.button("Times", Theme.Accent, function()
				UIController.openLeaderboard(owner)
			end, {
				Position = UDim2.fromScale(0.56, 0.12),
				Size = UDim2.fromScale(0.2, 0.76),
				Parent = r,
			})
			Kit.button("Race", Theme.Success, function()
				openModal(nil)
				Remotes.event("StartRun"):FireServer(owner)
			end, {
				Position = UDim2.fromScale(0.78, 0.12),
				Size = UDim2.fromScale(0.2, 0.76),
				Parent = r,
			})
		end
	end)
end

function UIController.openLeaderboard(ownerId: number)
	openModal("Leaderboard")
	clearList(leaderboardList)
	leaderboardTitle.Text = "Loading..."
	task.spawn(function()
		local ok, list = pcall(function()
			return Remotes.func("Leaderboard"):InvokeServer(ownerId)
		end)
		leaderboardTitle.Text = userName(ownerId) .. "'s tower"
		if not ok or type(list) ~= "table" or #list == 0 then
			Kit.label("No times yet. Be the first!", {
				Size = UDim2.new(1, 0, 0, 40),
				Font = Theme.BodyFont,
				Parent = leaderboardList,
			})
			return
		end
		for i, entry in list do
			local r = row(leaderboardList, i)
			local mine = entry.userId == player.UserId
			if mine then
				r.BackgroundColor3 = Theme.Primary
			end
			Kit.label("#" .. i, {
				Position = UDim2.fromScale(0.03, 0.15),
				Size = UDim2.fromScale(0.12, 0.7),
				Parent = r,
			})
			local nameLabel = Kit.label("...", {
				Position = UDim2.fromScale(0.17, 0.15),
				Size = UDim2.fromScale(0.5, 0.7),
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Theme.BodyFont,
				Parent = r,
			})
			Kit.label(Kit.formatMs(tonumber(entry.ms) or 0), {
				Position = UDim2.fromScale(0.68, 0.15),
				Size = UDim2.fromScale(0.29, 0.7),
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = r,
			})
			task.spawn(function()
				nameLabel.Text = userName(tonumber(entry.userId) or 0)
			end)
		end
	end)
end

local function setResultTitle(text: string)
	local title = modals.Results:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = text
	end
end

local function showResult(ok: boolean, ms: number, improved: boolean, message: string?)
	if not ok then
		if message then -- invalid run; a plain quit shows nothing
			setResultTitle("Not this time")
			resultTime.Text = "No time"
			resultNote.Text = message
			resultTimesButton.Visible = false
			openModal("Results")
		end
		return
	end
	local own = State.runOwner == player.UserId
	setResultTitle("Finished!")
	resultTime.Text = Kit.formatMs(ms)
	resultNote.Text = if own
		then "Tower verified! You can publish it now."
		elseif improved then "New personal best!"
		else "Not your best this time."
	resultTimesButton.Visible = not own
	openModal("Results")
end

---------------------------------------------------------------- state rendering

local function render()
	local isBuild = State.mode == "build"
	buildLayer.Visible = isBuild
	runLayer.Visible = not isBuild

	for id, slot in slots do
		local stroke = slot:FindFirstChild("Select") :: UIStroke
		local active = id == State.selected and not State.deleting
		stroke.Color = if active then Theme.Primary else Theme.Stroke
		stroke.Thickness = if active then 4 else 3
	end
	local count = if State.tower then #State.tower.pieces else 0
	budgetLabel.Text = string.format("Pieces %d/%d", count, Config.PIECE_BUDGET)
	budgetLabel.TextColor3 = if count >= Config.PIECE_BUDGET then Theme.Danger else Theme.Text

	local settingKey, settingRange = State.settingOf(State.selected)
	settingButton.Visible = settingKey ~= nil and not State.deleting
	if settingKey and settingRange then
		local value = State.props[settingKey] or settingRange[1]
		settingButton.Text = string.format("%s %d", if settingKey == "ch" then "Channel" else "Power", value)
	end
	deleteButton.BackgroundColor3 = if State.deleting then Theme.Danger else Theme.PanelLight
	Kit.setEnabled(publishButton, State.verified, Theme.Primary)
	Kit.setEnabled(publishConfirm, State.verified, Theme.Primary)
	-- A teleporter alone on its channel goes nowhere; tell the builder.
	local perChannel: { [number]: number } = {}
	for _, piece in if State.tower then State.tower.pieces else {} do
		if PieceDefs.byId[piece.t] and PieceDefs.byId[piece.t].name == "Teleporter" then
			local ch = piece.p and piece.p.ch or 1
			perChannel[ch] = (perChannel[ch] or 0) + 1
		end
	end
	local lonely: number? = nil
	for ch, n in perChannel do
		if n == 1 and (lonely == nil or ch < lonely) then
			lonely = ch
		end
	end
	if lonely then
		verifiedLabel.Text = string.format("Teleporter channel %d needs a partner", lonely)
		verifiedLabel.TextColor3 = Theme.Danger
	else
		verifiedLabel.Text = if State.verified
			then "Verified: ready to publish"
			else "Climb your tower to verify it"
		verifiedLabel.TextColor3 = if State.verified then Theme.Success else Theme.TextDim
	end
	testButton.Visible = isBuild
	runNameLabel.Text = State.runName
end

function UIController.init()
	gui = Kit.new("ScreenGui", {
		Name = "TowerUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	buildLayer = Kit.new(
		"Frame",
		{ Name = "Build", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui }
	)
	runLayer = Kit.new("Frame", {
		Name = "Run",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = gui,
	})
	buildHotbar()
	buildTools()
	buildRunHud()
	buildPublish()
	buildBrowse()
	buildLeaderboard()
	buildResults()
	gui.Parent = player:WaitForChild("PlayerGui")
	render()
end

function UIController.start()
	State.Changed:Connect(render)

	Remotes.event("TowerChanged").OnClientEvent:Connect(function(tower, verified)
		State.set({ tower = tower, verified = verified == true })
	end)
	Remotes.event("RunStarted").OnClientEvent:Connect(function(ownerId, name)
		if openModalName then
			openModal(nil)
		end
		State.set({ mode = "run", runOwner = ownerId, runName = tostring(name), runStartedAt = os.clock() })
	end)
	Remotes.event("RunResult").OnClientEvent:Connect(function(ok, ms, improved, message)
		State.set({ mode = "build" })
		showResult(
			ok == true,
			tonumber(ms) or 0,
			improved == true,
			if type(message) == "string" then message else nil
		)
	end)

	-- Display-only timer; the real time is measured on the server.
	RunService.Heartbeat:Connect(function()
		if State.mode == "run" then
			timerLabel.Text = Kit.formatMs(math.floor((os.clock() - State.runStartedAt) * 1000))
		end
	end)
end

return UIController

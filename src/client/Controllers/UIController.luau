--!strict
-- All V1 screens: build hotbar + tools, run HUD, publish dialog, browse list,
-- leaderboard and results. Renders State and sends intents; computes nothing that matters.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PieceDefs = require(ReplicatedStorage.Shared.PieceDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local State = require(script.Parent.Parent.State)
local BuildController = require(script.Parent.BuildController)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Events = require(ReplicatedStorage.Shared.Events)
local GhostController = require(script.Parent.GhostController)
local SocialController = require(script.Parent.SocialController)
local LiveRaceController = require(script.Parent.LiveRaceController)
local ShopController = require(script.Parent.ShopController)

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
	Crumble = Color3.fromRGB(181, 140, 90),
	Conveyor = Color3.fromRGB(60, 60, 70),
	OneWay = Color3.fromRGB(140, 200, 255),
	Button = Color3.fromRGB(230, 60, 60),
	Door = Color3.fromRGB(150, 100, 60),
	Checkpoint = Color3.fromRGB(0, 190, 200),
	Plant = Color3.fromRGB(70, 160, 70),
	Lamp = Color3.fromRGB(255, 220, 140),
	Flag = Color3.fromRGB(230, 60, 60),
	Pumpkin = Color3.fromRGB(255, 130, 20),
}
local SHORT_NAMES: { [string]: string } = {
	InvisiblePlatform = "Invisible",
	FakeWall = "Fake Wall",
	JumpPad = "Jump Pad",
	Teleporter = "Teleport",
	OneWay = "One Way",
}

local SECRET_NAMES: { [string]: string } = {
	FakeWall = "a fake wall",
	InvisiblePlatform = "an invisible platform",
	Teleporter = "a teleporter",
	JumpPad = "a jump pad",
	Button = "a hidden door",
}

local gui: ScreenGui
local buildLayer: Frame
local runLayer: Frame
local slots: { [number]: Frame } = {}
local budgetLabel: TextLabel
local pieceHint: TextLabel
local levelLabel: TextLabel
local bricksLabel: TextLabel
local xpFill: Frame
local verifiedLabel: TextLabel
local hintLabel: TextLabel
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
	-- Square tiles sized by the bar height (touch friendly); scrolls sideways
	-- when there are more pieces than fit.
	local bar = Kit.new("ScrollingFrame", {
		Name = "Hotbar",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.985),
		Size = UDim2.fromScale(0.8, 0.12),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 4,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Parent = buildLayer,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = bar,
	})
	for _, def in PieceDefs.list do
		local slot: TextButton = Kit.new("TextButton", {
			Name = def.name,
			LayoutOrder = def.id,
			Size = UDim2.fromOffset(60, 60), -- resized to the bar height below
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
		if Theme.PieceIconSheet ~= "" and def.id <= Theme.PieceIconCount then
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
		slot.Visible = Events.pieceAvailable(def.id, os.time()) -- limited-time pieces
	end
	local function sizeTiles()
		local h = math.max(math.floor(bar.AbsoluteSize.Y * 0.9), 44)
		for _, slot in slots do
			slot.Size = UDim2.fromOffset(h, h)
		end
	end
	bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(sizeTiles)
	sizeTiles()

	budgetLabel = Kit.label("Pieces 0/" .. State.budget, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.86),
		Size = UDim2.fromScale(0.3, 0.04),
		Parent = buildLayer,
	})
	pieceHint = Kit.label("", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.815),
		Size = UDim2.fromScale(0.4, 0.035),
		TextColor3 = Theme.TextDim,
		Font = Theme.BodyFont,
		Parent = buildLayer,
	})
	-- First-time guidance, top centre; hidden once the tower has a Finish.
	hintLabel = Kit.label("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.02),
		Size = UDim2.fromScale(0.5, 0.045),
		Font = Theme.BodyFont,
		Parent = buildLayer,
	})
end

-- Level, XP bar and Bricks, left side below the Roblox top bar.
local function buildProfileBadge()
	local panel = Kit.panel({
		Name = "Profile",
		Position = UDim2.fromScale(0.015, 0.12),
		Size = UDim2.fromScale(0.16, 0.1),
		Parent = gui,
	})
	Kit.new(
		"UISizeConstraint",
		{ MinSize = Vector2.new(130, 50), MaxSize = Vector2.new(220, 90), Parent = panel }
	)
	levelLabel = Kit.label("Lv 1", {
		Position = UDim2.fromScale(0.06, 0.05),
		Size = UDim2.fromScale(0.4, 0.45),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	bricksLabel = Kit.label("0 Bricks", {
		Position = UDim2.fromScale(0.45, 0.08),
		Size = UDim2.fromScale(0.5, 0.38),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Primary,
		Font = Theme.BodyFont,
		Parent = panel,
	})
	local bar = Kit.new("Frame", {
		Position = UDim2.fromScale(0.06, 0.62),
		Size = UDim2.fromScale(0.88, 0.22),
		BackgroundColor3 = Theme.PanelLight,
		Parent = panel,
	}, { Kit.corner(0.5) })
	xpFill = Kit.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Success,
		Parent = bar,
	}, { Kit.corner(0.5) })
	-- Just under the level badge.
	Kit.button("Shop", Theme.Primary, ShopController.toggle, {
		Position = UDim2.fromScale(0.015, 0.235),
		Size = UDim2.fromScale(0.09, 0.055),
		Parent = gui,
	})
end

---------------------------------------------------------------- tower menu (slots + materials)

local slotButtons: { TextButton } = {}
local materialList: ScrollingFrame
local towerMenuStatus: TextLabel

local function renderTowerMenu()
	for i, button in slotButtons do
		button.BackgroundColor3 = if i == State.activeSlot then Theme.Primary else Theme.PanelLight
		button.Visible = i <= State.slots
	end
	if not materialList then
		return
	end
	clearList(materialList)
	for i, def in Cosmetics.materials do
		local r = row(materialList, i)
		Kit.label(def.name, {
			Position = UDim2.fromScale(0.04, 0.15),
			Size = UDim2.fromScale(0.5, 0.7),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = r,
		})
		local owned = if def.bricks > 0 then State.unlocked[def.key] == true else State.level >= def.level
		local text, color, action
		if State.material == def.key then
			text, color = "Equipped", Theme.Success
		elseif owned then
			text, color, action = "Use", Theme.Accent, "SetMaterial"
		elseif State.level < def.level then
			text, color = "Lv " .. def.level, Theme.PanelLight
		else
			text, color, action = def.bricks .. " Bricks", Theme.Primary, "BuyMaterial"
		end
		local button = Kit.button(text, color, function()
			if not action then
				return
			end
			task.spawn(function()
				local ok, success, err = pcall(function()
					return Remotes.func(action):InvokeServer(def.key)
				end)
				if ok and success then
					State.set({ material = def.key })
					towerMenuStatus.Text = def.name .. " equipped"
				else
					towerMenuStatus.Text = if ok and type(err) == "string"
						then err
						else "Could not change material"
				end
				renderTowerMenu()
			end)
		end, { Position = UDim2.fromScale(0.6, 0.12), Size = UDim2.fromScale(0.37, 0.76), Parent = r })
		Kit.setEnabled(button, action ~= nil or State.material == def.key, color)
	end
end

local function buildTowerMenu()
	local body = makeModal("TowerMenu", "My towers", 0.75)
	local slotsRow =
		Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0.12), Parent = body })
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0.02, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = slotsRow,
	})
	for i = 1, Config.MAX_TOWER_SLOTS do
		slotButtons[i] = Kit.button(tostring(i), Theme.PanelLight, function()
			task.spawn(function()
				local ok, switched = pcall(function()
					return Remotes.func("SwitchSlot"):InvokeServer(i)
				end)
				towerMenuStatus.Text = if ok and switched then "Switched to tower " .. i else ""
			end)
		end, { LayoutOrder = i, Size = UDim2.fromScale(0.18, 1), Parent = slotsRow })
	end
	towerMenuStatus = Kit.label("", {
		Position = UDim2.fromScale(0, 0.13),
		Size = UDim2.fromScale(1, 0.07),
		Font = Theme.BodyFont,
		TextColor3 = Theme.TextDim,
		Parent = body,
	})
	Kit.label("Material", {
		Position = UDim2.fromScale(0, 0.21),
		Size = UDim2.fromScale(1, 0.07),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = body,
	})
	local holder = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0.3),
		Size = UDim2.fromScale(1, 0.7),
		Parent = body,
	})
	materialList = listFrame(holder)
end

local function buildTools()
	-- Right edge, above the mobile jump button. Only the building actions live
	-- here; everything else is behind Menu so buttons stay touch-sized.
	local column = Kit.new("Frame", {
		Name = "Tools",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.985, 0.42),
		Size = UDim2.fromScale(0.14, 0.56),
		Parent = buildLayer,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(170, math.huge), Parent = column })
	Kit.new("UIListLayout", {
		Padding = UDim.new(0.025, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = column,
	})
	local function tool(
		parent: Instance,
		order: number,
		text: string,
		color: Color3,
		fn: () -> ()
	): TextButton
		return Kit.button(text, color, fn, {
			LayoutOrder = order,
			Size = UDim2.fromScale(1, 0.15),
			Parent = parent,
		})
	end
	tool(column, 1, "Rotate", Theme.Accent, function()
		State.set({ rotation = (State.rotation + 1) % 4 })
	end)
	settingButton = tool(column, 2, "", Theme.Accent, BuildController.cycleSetting)
	deleteButton = tool(column, 3, "Delete", Theme.PanelLight, function()
		State.set({ deleting = not State.deleting })
	end)
	tool(column, 4, "Undo", Theme.PanelLight, function()
		Remotes.event("Undo"):FireServer()
	end)
	testButton = tool(column, 5, "Test Run", Theme.Success, function()
		Remotes.event("StartRun"):FireServer(player.UserId)
	end)

	-- Menu: a second column to the left of the tools.
	local menu = Kit.new("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.83, 0.42),
		Size = UDim2.fromScale(0.14, 0.56),
		Visible = false,
		Parent = buildLayer,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(170, math.huge), Parent = menu })
	Kit.new("UIListLayout", {
		Padding = UDim.new(0.025, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = menu,
	})
	local function menuItem(order: number, text: string, color: Color3, fn: () -> ()): TextButton
		return tool(menu, order, text, color, function()
			menu.Visible = false
			fn()
		end)
	end
	tool(column, 6, "Menu", Theme.PanelLight, function()
		menu.Visible = not menu.Visible
	end)
	publishButton = menuItem(1, "Publish", Theme.Primary, function()
		openModal("Publish")
	end)
	menuItem(2, "Browse", Theme.Accent, function()
		UIController.openBrowse()
	end)
	menuItem(3, "My Towers", Theme.PanelLight, function()
		openModal("TowerMenu")
		renderTowerMenu()
	end)
	menuItem(4, "Players", Theme.PanelLight, function()
		SocialController.openPlayers()
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

local browseTab = "featured"
local browseTabButtons: { [string]: TextButton } = {}
local browseSearch: TextBox

local BROWSE_TABS = {
	{ "featured", "Featured" },
	{ "contest", "Contest" },
	{ "new", "New" },
	{ "popular", "Popular" },
	{ "hard", "Hardest" },
	{ "friends", "Friends" },
}
local contestInfo: { [string]: any }? = nil

local function buildBrowse()
	local body = makeModal("Browse", "Towers", 0.8)
	local tabs =
		Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0.1), Parent = body })
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0.01, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabs,
	})
	for i, t in BROWSE_TABS do
		browseTabButtons[t[1]] = Kit.button(t[2], Theme.PanelLight, function()
			browseTab = t[1]
			UIController.openBrowse()
		end, { LayoutOrder = i, Size = UDim2.fromScale(0.158, 1), Parent = tabs })
	end
	browseTabButtons.contest.Visible = false -- shown while a contest runs
	browseSearch = Kit.new("TextBox", {
		Position = UDim2.fromScale(0, 0.12),
		Size = UDim2.fromScale(1, 0.08),
		BackgroundColor3 = Theme.PanelLight,
		Font = Theme.BodyFont,
		PlaceholderText = "Search builder name",
		Text = "",
		TextColor3 = Theme.Text,
		TextScaled = true,
		ClearTextOnFocus = false,
		Parent = body,
	}, { Kit.corner(0.2) })
	browseSearch.FocusLost:Connect(function(enter)
		if enter then
			UIController.openBrowse(browseSearch.Text)
		end
	end)
	local holder = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0.22),
		Size = UDim2.fromScale(1, 0.78),
		Parent = body,
	})
	browseList = listFrame(holder)
end

local reportButton: TextButton
local monthlyButton: TextButton
local leaderboardOwner = 0
local leaderboardMonthly = false

local function buildLeaderboard()
	local body = makeModal("Leaderboard", "Best times", 0.75)
	leaderboardTitle = Kit.label("", {
		Position = UDim2.fromScale(0.23, 0), -- between the season toggle and Report
		Size = UDim2.fromScale(0.54, 0.1),
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
	monthlyButton = Kit.button("All time", Theme.Accent, function()
		leaderboardMonthly = not leaderboardMonthly
		UIController.openLeaderboard(leaderboardOwner)
	end, {
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(0.22, 0.1),
		Parent = body,
	})
	reportButton = Kit.button("Report", Theme.Danger, function()
		local ownerId = leaderboardOwner
		reportButton.Visible = false
		task.spawn(function()
			pcall(function()
				Remotes.func("ReportTower"):InvokeServer(ownerId)
			end)
		end)
		leaderboardTitle.Text = "Thanks, reported"
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.22, 0.1),
		Parent = body,
	})
end

local resultTime: TextLabel
local resultNote: TextLabel
local resultTimesButton: TextButton
local resultLikeButton: TextButton
local resultHint: TextLabel

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
	resultHint = Kit.label("", {
		Position = UDim2.fromScale(0, 0.58),
		Size = UDim2.fromScale(1, 0.12),
		Font = Theme.BodyFont,
		TextColor3 = Theme.Primary,
		Parent = body,
	})
	resultTimesButton = Kit.button("Times", Theme.Accent, function()
		UIController.openLeaderboard(State.runOwner)
	end, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0.05, 1),
		Size = UDim2.fromScale(0.3, 0.28),
		Parent = body,
	})
	resultLikeButton = Kit.button("Like", Theme.Primary, function()
		local ownerId = State.runOwner
		resultLikeButton.Visible = false
		task.spawn(function()
			pcall(function()
				Remotes.func("LikeTower"):InvokeServer(ownerId)
			end)
		end)
	end, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.26, 0.28),
		Parent = body,
	})
	Kit.button("OK", Theme.Success, function()
		openModal(nil)
	end, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(0.95, 1),
		Size = UDim2.fromScale(0.3, 0.28),
		Parent = body,
	})
end

---------------------------------------------------------------- data-driven screens

local DIFFICULTY_COLORS: { [string]: Color3 } = {
	New = Color3.fromRGB(160, 160, 170),
	Easy = Color3.fromRGB(80, 200, 120),
	Medium = Color3.fromRGB(240, 200, 60),
	Hard = Color3.fromRGB(240, 120, 50),
	Insane = Color3.fromRGB(220, 60, 90),
}

-- query: builder name to search instead of the current tab.
-- First row of the Contest tab: theme, phase and what you can do now.
local function contestHeader(info: { [string]: any })
	local r = row(browseList, 0)
	r.Size = UDim2.new(1, -8, 0, 64)
	local days = math.max(0, math.floor((tonumber(info.endsIn) or 0) / 86400))
	local voting = info.phase == "voting"
	Kit.label(string.format('Contest: "%s"', tostring(info.theme)), {
		Position = UDim2.fromScale(0.03, 0.05),
		Size = UDim2.fromScale(0.62, 0.45),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = r,
	})
	Kit.label(
		if voting
			then string.format("Voting · %d votes left · %d days", tonumber(info.votesLeft) or 0, days)
			else string.format("Entries open · %d days left", days),
		{
			Position = UDim2.fromScale(0.03, 0.55),
			Size = UDim2.fromScale(0.62, 0.38),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.TextDim,
			Font = Theme.BodyFont,
			Parent = r,
		}
	)
	if not voting then
		local entered = info.entered == true
		local button = Kit.button(if entered then "Entered" else "Enter my tower", Theme.Primary, function()
			task.spawn(function()
				local ok, success, err = pcall(function()
					return Remotes.func("EnterContest"):InvokeServer()
				end)
				SocialController.toast(
					if ok and success then "Your tower is entered!" else tostring(err or "Could not enter")
				)
				UIController.openBrowse()
			end)
		end, { Position = UDim2.fromScale(0.67, 0.18), Size = UDim2.fromScale(0.31, 0.64), Parent = r })
		Kit.setEnabled(button, not entered, Theme.Primary)
	end
end

function UIController.openBrowse(query: string?)
	openModal("Browse")
	for key, button in browseTabButtons do
		button.BackgroundColor3 = if key == browseTab and not query then Theme.Primary else Theme.PanelLight
	end
	clearList(browseList)
	Kit.label("Loading...", { Size = UDim2.new(1, 0, 0, 40), Font = Theme.BodyFont, Parent = browseList })
	task.spawn(function()
		local okInfo, contest = pcall(function()
			return Remotes.func("ContestInfo"):InvokeServer()
		end)
		contestInfo = if okInfo and type(contest) == "table" then contest else nil
		browseTabButtons.contest.Visible = contestInfo ~= nil
		local ok, list = pcall(function()
			return Remotes.func("Browse")
				:InvokeServer(browseTab, if query and query ~= "" then query else nil)
		end)
		clearList(browseList)
		if browseTab == "contest" and not query and contestInfo then
			contestHeader(contestInfo)
		end
		if not ok or type(list) ~= "table" or #list == 0 then
			local empty = if not ok
				then "Could not load"
				elseif query then "No tower by that builder"
				elseif browseTab == "friends" then "No friends' towers yet"
				elseif browseTab == "contest" then "No entries yet"
				elseif browseTab == "featured" then "No featured tower yet. Like towers to pick next week's!"
				else "No towers here yet. Be the first!"
			Kit.label(empty, { Size = UDim2.new(1, 0, 0, 40), Font = Theme.BodyFont, Parent = browseList })
			return
		end
		for i, entry in list do
			local r = row(browseList, i)
			r.Size = UDim2.new(1, -8, 0, 64)
			local difficulty = tostring(entry.difficulty or "New")
			Kit.label(tostring(entry.name), {
				Position = UDim2.fromScale(0.03, 0.04),
				Size = UDim2.fromScale(0.5, 0.42),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = r,
			})
			Kit.label(difficulty, {
				Position = UDim2.fromScale(0.03, 0.48),
				Size = UDim2.fromScale(0.13, 0.24),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = DIFFICULTY_COLORS[difficulty] or Theme.TextDim,
				Font = Theme.BodyFont,
				Parent = r,
			})
			local info = Kit.label("", {
				Position = UDim2.fromScale(0.17, 0.48),
				Size = UDim2.fromScale(0.37, 0.24),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.TextDim,
				Font = Theme.BodyFont,
				Parent = r,
			})
			local record = Kit.label("", {
				Position = UDim2.fromScale(0.03, 0.74),
				Size = UDim2.fromScale(0.51, 0.22),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.TextDim,
				Font = Theme.BodyFont,
				Parent = r,
			})
			local owner = tonumber(entry.owner) or 0
			local secrets = tonumber(entry.secrets) or 0
			local stats = string.format(
				"%d high · %d likes%s",
				tonumber(entry.height) or 0,
				tonumber(entry.likes) or 0,
				if secrets > 0 then string.format(" · %d secrets hidden", secrets) else ""
			)
			info.Text = stats
			task.spawn(function()
				info.Text = string.format("by %s · %s", userName(owner), stats)
				local best, bestBy = tonumber(entry.best), tonumber(entry.bestBy)
				local builderMs = tonumber(entry.builderMs)
				record.Text = (
					if best and bestBy
						then string.format("Record %s by %s", Kit.formatMs(best), userName(bestBy))
						else "No record yet"
				) .. (if builderMs then " · Builder " .. Kit.formatMs(builderMs) else "")
			end)
			Kit.button("Times", Theme.Accent, function()
				UIController.openLeaderboard(owner)
			end, {
				Position = UDim2.fromScale(0.55, 0.14),
				Size = UDim2.fromScale(0.14, 0.72),
				Parent = r,
			})
			Kit.button("Race", Theme.Success, function()
				openModal(nil)
				Remotes.event("StartRun"):FireServer(owner)
			end, {
				Position = UDim2.fromScale(0.70, 0.14),
				Size = UDim2.fromScale(0.14, 0.72),
				Parent = r,
			})
			local voting = browseTab == "contest" and contestInfo and contestInfo.phase == "voting"
			if voting and owner ~= player.UserId then
				Kit.button("Vote", Theme.Primary, function()
					task.spawn(function()
						local ok2, success, err = pcall(function()
							return Remotes.func("VoteContest"):InvokeServer(owner)
						end)
						SocialController.toast(
							if ok2 and success then "Vote counted!" else tostring(err or "Could not vote")
						)
					end)
				end, {
					Position = UDim2.fromScale(0.85, 0.14),
					Size = UDim2.fromScale(0.13, 0.72),
					Parent = r,
				})
			elseif owner ~= player.UserId then
				-- Host a live race (not on your own tower).
				Kit.button("Live", Theme.Primary, function()
					openModal(nil)
					LiveRaceController.host(owner)
				end, {
					Position = UDim2.fromScale(0.85, 0.14),
					Size = UDim2.fromScale(0.13, 0.72),
					Parent = r,
				})
			end
		end
	end)
end

function UIController.openLeaderboard(ownerId: number)
	openModal("Leaderboard")
	clearList(leaderboardList)
	leaderboardOwner = ownerId
	reportButton.Visible = ownerId ~= player.UserId
	monthlyButton.Text = if leaderboardMonthly then "This month" else "All time"
	leaderboardTitle.Text = "Loading..."
	task.spawn(function()
		local ok, list, summary = pcall(function()
			return Remotes.func("Leaderboard"):InvokeServer(ownerId, leaderboardMonthly)
		end)
		local title = userName(ownerId) .. "'s tower"
		if ok and type(summary) == "table" then
			title ..= string.format(
				" · %s · %d finishes",
				tostring(summary.difficulty),
				tonumber(summary.finishes) or 0
			)
			if tonumber(summary.average) then
				title ..= " · avg " .. Kit.formatMs(tonumber(summary.average) :: number)
			end
			-- Builder only: how often racers find each kind of secret.
			if type(summary.found) == "table" then
				local order = 0
				for kind, pct in summary.found do
					order -= 1
					Kit.label(
						string.format(
							"%s found by %d%% of racers",
							SECRET_NAMES[kind] or kind,
							tonumber(pct) or 0
						),
						{
							Size = UDim2.new(1, -8, 0, 28),
							LayoutOrder = order,
							TextColor3 = Theme.Primary,
							Font = Theme.BodyFont,
							Parent = leaderboardList,
						}
					)
				end
			end
		end
		leaderboardTitle.Text = title
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
				Position = UDim2.fromScale(0.15, 0.15),
				Size = UDim2.fromScale(0.36, 0.7),
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Theme.BodyFont,
				Parent = r,
			})
			Kit.label(Kit.formatMs(tonumber(entry.ms) or 0), {
				Position = UDim2.fromScale(0.52, 0.15),
				Size = UDim2.fromScale(0.26, 0.7),
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = r,
			})
			local racer = tonumber(entry.userId) or 0
			Kit.button("Watch", Theme.Accent, function()
				openModal(nil)
				GhostController.watch(ownerId, racer)
			end, {
				Position = UDim2.fromScale(0.8, 0.12),
				Size = UDim2.fromScale(0.18, 0.76),
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

-- One line comparing a race to everyone else's: the rarest secret found, else the average.
function UIController.raceHint(ms: number, info: { [string]: any }): string
	local finishes = tonumber(info.finishes) or 0
	local rarest, rarestPct = nil, 101
	if type(info.used) == "table" and type(info.foundPct) == "table" then
		for _, kind in info.used do
			local pct = if finishes > 0 then tonumber(info.foundPct[kind]) or 0 else 0
			if SECRET_NAMES[kind] and pct < rarestPct then
				rarest, rarestPct = kind, pct
			end
		end
	end
	if rarest and finishes >= 5 then
		return string.format("You found %s! Only %d%% of racers do.", SECRET_NAMES[rarest], rarestPct)
	elseif rarest then
		return string.format("You found %s!", SECRET_NAMES[rarest])
	end
	local builderMs = tonumber(info.builderMs)
	if builderMs then
		local diff = (ms - builderMs) / 1000
		return if diff <= 0
			then string.format("You beat the builder by %.1fs!", -diff)
			else string.format("%.1fs behind the builder", diff)
	end
	local average = tonumber(info.average)
	if average then
		local diff = (ms - average) / 1000
		return if diff <= 0
			then string.format("%.1fs faster than average", -diff)
			else string.format("%.1fs slower than average", diff)
	end
	return ""
end

local function showResult(
	ok: boolean,
	ms: number,
	improved: boolean,
	message: string?,
	previous: number?,
	canLike: boolean,
	info: { [string]: any }?
)
	resultHint.Text = ""
	if not ok then
		if message then -- invalid run; a plain quit shows nothing
			setResultTitle("Not this time")
			resultTime.Text = "No time"
			resultNote.Text = message
			resultTimesButton.Visible = false
			resultLikeButton.Visible = false
			openModal("Results")
		end
		return
	end
	local own = State.runOwner == player.UserId
	setResultTitle("Finished!")
	resultTime.Text = Kit.formatMs(ms)
	resultNote.Text = if own
		then "Tower verified! You can publish it now."
		elseif improved and previous then string.format(
			"New personal best! (was %s)",
			Kit.formatMs(previous)
		)
		elseif improved then "New personal best!"
		elseif previous then string.format("Your best: %s", Kit.formatMs(previous))
		else "Not your best this time."
	resultTimesButton.Visible = not own
	resultLikeButton.Visible = not own and canLike
	if info then
		resultHint.Text = UIController.raceHint(ms, info)
	end
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
	local count = 0
	for _, piece in if State.tower then State.tower.pieces else {} do
		local def = PieceDefs.byId[piece.t]
		if def and not def.decor then
			count += 1
		end
	end
	local selectedDef = PieceDefs.byId[State.selected]
	pieceHint.Text = if State.deleting
		then "Tap a piece to delete it"
		elseif selectedDef and selectedDef.hint then selectedDef.hint
		else ""
	budgetLabel.Text = string.format("Pieces %d/%d", count, State.budget)
	budgetLabel.TextColor3 = if count >= State.budget then Theme.Danger else Theme.Text
	levelLabel.Text = string.format("Lv %d", State.level)
	bricksLabel.Text = string.format("%d Bricks", State.bricks)
	local span = math.max(State.nextXp - State.levelXp, 1)
	xpFill.Size = UDim2.fromScale(math.clamp((State.xp - State.levelXp) / span, 0, 1), 1)

	local settingKey, settingRange = State.settingOf(State.selected)
	settingButton.Visible = settingKey ~= nil and not State.deleting
	if settingKey and settingRange then
		local value = State.props[settingKey] or settingRange[1]
		settingButton.Text = string.format("%s %d", if settingKey == "ch" then "Channel" else "Power", value)
	end
	deleteButton.BackgroundColor3 = if State.deleting then Theme.Danger else Theme.PanelLight
	Kit.setEnabled(publishButton, State.verified, Theme.Primary)
	Kit.setEnabled(publishConfirm, State.verified, Theme.Primary)
	local hasFinish = false
	for _, piece in if State.tower then State.tower.pieces else {} do
		if piece.t == PieceDefs.FINISH_ID then
			hasFinish = true
		end
	end
	hintLabel.Text = if count == 0
		then "Tap the grid to place pieces and build upwards"
		elseif not hasFinish then "Top it off with a Finish piece, then Test Run"
		else ""
	hintLabel.Visible = hintLabel.Text ~= ""

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
			then "Verified! Menu → Publish"
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
	buildProfileBadge()
	buildRunHud()
	buildPublish()
	buildBrowse()
	buildLeaderboard()
	buildResults()
	buildTowerMenu()
	gui.Parent = player:WaitForChild("PlayerGui")
	render()
end

function UIController.start()
	State.Changed:Connect(render)

	local knownLevel: number? = nil
	Remotes.event("Progress").OnClientEvent:Connect(function(p)
		if type(p) == "table" then
			if type(p.level) == "number" then
				if knownLevel and p.level > knownLevel then
					Sounds.play("LevelUp")
					SocialController.toast(
						string.format("Level %d! Piece budget is now %d", p.level, tonumber(p.budget) or 0)
					)
				end
				knownLevel = p.level
			end
			local patch = {}
			for _, k in { "xp", "bricks", "level", "budget", "levelXp", "nextXp", "activeSlot", "slots" } do
				if type(p[k]) == "number" then
					patch[k] = p[k]
				end
			end
			if type(p.material) == "string" then
				patch.material = p.material
			end
			if type(p.unlocked) == "table" then
				patch.unlocked = p.unlocked
			end
			if type(p.theme) == "string" then
				patch.theme = p.theme
			end
			State.trail = if type(p.trail) == "string" then p.trail else nil
			State.set(patch)
			if openModalName == "TowerMenu" then
				renderTowerMenu()
			end
		end
	end)
	Remotes.event("TowerChanged").OnClientEvent:Connect(function(tower, verified)
		State.set({ tower = tower, verified = verified == true })
	end)
	Remotes.event("RunStarted").OnClientEvent:Connect(function(ownerId, name)
		if openModalName then
			openModal(nil)
		end
		State.set({ mode = "run", runOwner = ownerId, runName = tostring(name), runStartedAt = os.clock() })
	end)
	Remotes.event("RunResult").OnClientEvent
		:Connect(function(ok, ms, improved, message, previous, canLike, info)
			State.set({ mode = "build" })
			showResult(
				ok == true,
				tonumber(ms) or 0,
				improved == true,
				if type(message) == "string" then message else nil,
				if type(previous) == "number" then previous else nil,
				canLike == true,
				if type(info) == "table" then info else nil
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

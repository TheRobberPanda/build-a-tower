--!strict
-- Social UI: inbox toasts, co-build invites, the players panel (visit / invite)
-- and the "back to my plot" button while helping someone build.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)

local SocialController = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local toast: TextLabel
local invitePanel: Frame
local inviteText: TextLabel
local playersPanel: Frame
local playersList: ScrollingFrame
local leaveButton: TextButton
local pendingInviteFrom = 0
local toastQueue: { string } = {}
local showingToast = false

local function showNextToast()
	if showingToast or #toastQueue == 0 then
		return
	end
	showingToast = true
	toast.Text = table.remove(toastQueue, 1) :: string
	toast.Visible = true
	task.delay(4, function()
		toast.Visible = false
		showingToast = false
		showNextToast()
	end)
end

function SocialController.toast(text: string)
	table.insert(toastQueue, text)
	showNextToast()
end

local function invoke(name: string, ...: any): boolean
	local args = table.pack(...)
	local ok, result = pcall(function()
		return Remotes.func(name):InvokeServer(table.unpack(args, 1, args.n))
	end)
	return ok and result == true
end

local function refreshPlayers()
	for _, child in playersList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local order = 0
	for _, other in Players:GetPlayers() do
		if other == player then
			continue
		end
		order += 1
		local r = Kit.new("Frame", {
			BackgroundColor3 = Theme.PanelLight,
			Size = UDim2.new(1, -8, 0, 48),
			LayoutOrder = order,
			Parent = playersList,
		}, { Kit.corner(0.2) })
		Kit.label(other.DisplayName, {
			Position = UDim2.fromScale(0.03, 0.15),
			Size = UDim2.fromScale(0.45, 0.7),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = r,
		})
		local id = other.UserId
		Kit.button("Visit", Theme.Accent, function()
			playersPanel.Visible = false
			invoke("VisitPlot", id)
		end, { Position = UDim2.fromScale(0.5, 0.12), Size = UDim2.fromScale(0.22, 0.76), Parent = r })
		Kit.button("Invite", Theme.Primary, function()
			if invoke("InviteBuilder", id) then
				SocialController.toast("Invited " .. other.DisplayName .. " to build with you")
			end
		end, { Position = UDim2.fromScale(0.75, 0.12), Size = UDim2.fromScale(0.22, 0.76), Parent = r })
	end
	if order == 0 then
		Kit.label(
			"Nobody else here yet",
			{ Size = UDim2.new(1, 0, 0, 40), Font = Theme.BodyFont, Parent = playersList }
		)
	end
end

function SocialController.openPlayers()
	playersPanel.Visible = not playersPanel.Visible
	if playersPanel.Visible then
		refreshPlayers()
	end
end

function SocialController.init()
	gui = Kit.new("ScreenGui", {
		Name = "SocialUI",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 5,
		Parent = player:WaitForChild("PlayerGui"),
	})
	toast = Kit.label("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.22),
		Size = UDim2.fromScale(0.6, 0.05),
		TextColor3 = Theme.Primary,
		Visible = false,
		Parent = gui,
	})

	invitePanel = Kit.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromScale(0.4, 0.16),
		Visible = false,
		Parent = gui,
	})
	inviteText = Kit.label("", {
		Position = UDim2.fromScale(0.05, 0.05),
		Size = UDim2.fromScale(0.9, 0.4),
		Font = Theme.BodyFont,
		Parent = invitePanel,
	})
	Kit.button("Join", Theme.Success, function()
		invitePanel.Visible = false
		invoke("JoinBuild", pendingInviteFrom)
	end, { Position = UDim2.fromScale(0.05, 0.52), Size = UDim2.fromScale(0.42, 0.4), Parent = invitePanel })
	Kit.button("No thanks", Theme.PanelLight, function()
		invitePanel.Visible = false
	end, { Position = UDim2.fromScale(0.53, 0.52), Size = UDim2.fromScale(0.42, 0.4), Parent = invitePanel })

	playersPanel = Kit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.45, 0.6),
		Visible = false,
		Parent = gui,
	})
	Kit.label(
		"Players",
		{ Size = UDim2.fromScale(0.8, 0.1), Position = UDim2.fromScale(0.05, 0.02), Parent = playersPanel }
	)
	Kit.button("X", Theme.Danger, function()
		playersPanel.Visible = false
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.98, 0.02),
		Size = UDim2.fromScale(0.1, 0.1),
		Parent = playersPanel,
	})
	playersList = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.03, 0.15),
		Size = UDim2.fromScale(0.94, 0.82),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		BorderSizePixel = 0,
		Parent = playersPanel,
	})
	Kit.new(
		"UIListLayout",
		{ Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = playersList }
	)

	leaveButton = Kit.button("Back to my plot", Theme.Danger, function()
		invoke("JoinBuild", 0)
	end, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.08),
		Size = UDim2.fromScale(0.22, 0.06),
		Visible = false,
		Parent = gui,
	})
end

function SocialController.start()
	Remotes.event("Inbox").OnClientEvent:Connect(function(messages)
		if type(messages) ~= "table" then
			return
		end
		for _, m in messages do
			if type(m) == "table" and type(m.text) == "string" then
				SocialController.toast(m.text)
			end
		end
	end)
	Remotes.event("BuildInvite").OnClientEvent:Connect(function(fromId, fromName)
		if type(fromId) == "number" and type(fromName) == "string" then
			pendingInviteFrom = fromId
			inviteText.Text = fromName .. " invited you to build with them"
			invitePanel.Visible = true
		end
	end)
	Remotes.event("BuildTarget").OnClientEvent:Connect(function(ownerId)
		local id = if type(ownerId) == "number" then ownerId else 0
		State.set({ buildOwner = id })
		leaveButton.Visible = id ~= 0
		if id ~= 0 then
			SocialController.toast("Building together. Only the owner can test and publish.")
		end
	end)
	Players.PlayerAdded:Connect(function()
		if playersPanel.Visible then
			refreshPlayers()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if playersPanel.Visible then
			task.defer(refreshPlayers)
		end
	end)
end

return SocialController

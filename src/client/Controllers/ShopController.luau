--!strict
-- Shop: game passes, Bricks packs, trails (Bricks) and VIP plot themes.
-- Items whose Roblox id is still 0 in Config are hidden.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)

local ShopController = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local panel: Frame
local list: ScrollingFrame
local status: TextLabel
local passes: { [string]: boolean } = {}

local PASS_TEXT: { [string]: string } = {
	BuilderPass = "Builder Pass: +100 pieces, 2 more tower slots, Glass and Foil",
	VIP = "VIP: island themes (Lava, Space, Candy)",
}

local function header(text: string, order: number)
	Kit.label(text, {
		Size = UDim2.new(1, -8, 0, 30),
		LayoutOrder = order,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = list,
	})
end

local function item(order: number, text: string, buttonText: string, color: Color3, onClick: (() -> ())?)
	local r = Kit.new("Frame", {
		BackgroundColor3 = Theme.PanelLight,
		Size = UDim2.new(1, -8, 0, 52),
		LayoutOrder = order,
		Parent = list,
	}, { Kit.corner(0.2) })
	Kit.label(text, {
		Position = UDim2.fromScale(0.03, 0.1),
		Size = UDim2.fromScale(0.62, 0.8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Font = Theme.BodyFont,
		Parent = r,
	})
	local button = Kit.button(buttonText, color, function()
		if onClick then
			onClick()
		end
	end, { Position = UDim2.fromScale(0.68, 0.12), Size = UDim2.fromScale(0.3, 0.76), Parent = r })
	Kit.setEnabled(button, onClick ~= nil, color)
end

local function call(name: string, ...: any): (boolean, any)
	local args = table.pack(...)
	local ok, a, b = pcall(function()
		return Remotes.func(name):InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok then
		return false, "Could not reach the server"
	end
	return a == true, b
end

local function render()
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local anyPass = false
	for name, id in Config.GAME_PASSES do
		if id ~= 0 then
			if not anyPass then
				header("Passes", nextOrder())
				anyPass = true
			end
			local owned = passes[name] == true
			item(
				nextOrder(),
				PASS_TEXT[name] or name,
				if owned then "Owned" else "Buy",
				if owned then Theme.Success else Theme.Primary,
				if owned
					then nil
					else function()
						MarketplaceService:PromptGamePassPurchase(player, id)
					end
			)
		end
	end

	local packs = {}
	for id, bricks in Config.BRICK_PRODUCTS do
		table.insert(packs, { id = id, bricks = bricks })
	end
	table.sort(packs, function(a, b)
		return a.bricks < b.bricks
	end)
	if #packs > 0 then
		header("Coins", nextOrder())
		for _, pack in packs do
			item(nextOrder(), string.format("%d Coins", pack.bricks), "Buy", Theme.Primary, function()
				MarketplaceService:PromptProductPurchase(player, pack.id)
			end)
		end
	end

	header("Trails", nextOrder())
	item(
		nextOrder(),
		"No trail",
		if State.trail == nil then "Equipped" else "Use",
		Theme.Accent,
		if State.trail
			then function()
				call("EquipTrail", "")
				State.set({ trail = nil })
			end
			else nil
	)
	for _, def in Cosmetics.trails do
		local owned = State.unlocked[def.key] == true
		local equipped = State.trail == def.key
		item(
			nextOrder(),
			def.name,
			if equipped then "Equipped" elseif owned then "Use" else def.bricks .. " Coins",
			if equipped then Theme.Success elseif owned then Theme.Accent else Theme.Primary,
			if equipped
				then nil
				else function()
					local ok, err = call("BuyTrail", def.key)
					status.Text = if ok then def.name .. " equipped" else tostring(err or "Could not buy")
				end
		)
	end

	if Config.GAME_PASSES.VIP ~= 0 then
		header("Plot themes (VIP)", nextOrder())
		for _, def in Cosmetics.themes do
			local equipped = State.theme == def.key
			item(
				nextOrder(),
				def.name,
				if equipped then "Equipped" elseif passes.VIP then "Use" else "VIP",
				if equipped then Theme.Success else Theme.Accent,
				if equipped or not passes.VIP
					then nil
					else function()
						if call("SetTheme", def.key) then
							State.set({ theme = def.key })
						end
					end
			)
		end
	end
end

function ShopController.toggle()
	panel.Visible = not panel.Visible
	if panel.Visible then
		status.Text = ""
		render()
	end
end

function ShopController.init()
	gui = Kit.new("ScreenGui", {
		Name = "ShopUI",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = 6,
		Parent = player:WaitForChild("PlayerGui"),
	})
	panel = Kit.panel({
		FreeCursor = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.75),
		Visible = false,
		Parent = gui,
	})
	Kit.new(
		"UISizeConstraint",
		{ MinSize = Vector2.new(300, 0), MaxSize = Vector2.new(560, math.huge), Parent = panel }
	)
	Kit.label(
		"Shop",
		{ Position = UDim2.fromScale(0.04, 0.02), Size = UDim2.fromScale(0.7, 0.08), Parent = panel }
	)
	Kit.button("X", Theme.Danger, function()
		panel.Visible = false
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.97, 0.02),
		Size = UDim2.fromScale(0.1, 0.08),
		Parent = panel,
	})
	status = Kit.label("", {
		Position = UDim2.fromScale(0.04, 0.1),
		Size = UDim2.fromScale(0.92, 0.05),
		Font = Theme.BodyFont,
		TextColor3 = Theme.Primary,
		Parent = panel,
	})
	list = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.03, 0.16),
		Size = UDim2.fromScale(0.94, 0.82),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		BorderSizePixel = 0,
		Parent = panel,
	})
	Kit.new(
		"UIListLayout",
		{ Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list }
	)
end

function ShopController.start()
	Remotes.event("Passes").OnClientEvent:Connect(function(owned)
		if type(owned) == "table" then
			passes = owned
			if panel.Visible then
				render()
			end
		end
	end)
	State.Changed:Connect(function()
		if panel.Visible then
			render()
		end
	end)
end

return ShopController

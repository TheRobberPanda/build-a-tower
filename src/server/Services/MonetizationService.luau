--!strict
-- Game passes, Bricks packs (dev products), trails, running animations and VIP
-- plot themes. Also puts the glider wings on every character.
-- Everything sold is cosmetic or convenience; times and leaderboards never are.
-- Ids live in Config; 0 / missing = not created yet, so nothing is offered.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local ProgressionService = require(script.Parent.ProgressionService)

local MonetizationService = {}

local changed = Instance.new("BindableEvent")
MonetizationService.Changed = changed.Event -- (player) when pass ownership changes

local passes: { [Player]: { [string]: boolean } } = {}
local limiter = RateLimiter.new(5, 1)

function MonetizationService.hasPass(player: Player, name: string): boolean
	local owned = passes[player]
	return owned ~= nil and owned[name] == true
end

local function refreshPasses(player: Player)
	local owned: { [string]: boolean } = {}
	for name, id in Config.GAME_PASSES do
		if id ~= 0 then
			local ok, has =
				pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
			owned[name] = ok and has == true
		end
	end
	if player.Parent then
		passes[player] = owned
		Remotes.event("Passes"):FireClient(player, owned)
		changed:Fire(player)
	end
end

-- The equipped running animation (the character's Animate script picks up the
-- change); the avatar's own run when none is equipped.
local function applyRun(player: Player)
	local data = DataService.get(player)
	local character = player.Character
	local animate = character and character:WaitForChild("Animate", 5)
	local run = animate and animate:FindFirstChild("run")
	local anim = run and run:FindFirstChildOfClass("Animation")
	if not anim then
		return
	end
	if anim:GetAttribute("Own") == nil then
		anim:SetAttribute("Own", anim.AnimationId)
	end
	local def = data and data.run and Cosmetics.runByKey[data.run]
	anim.AnimationId = if def then def.anim else anim:GetAttribute("Own") :: string
end

-- Glider wings on the back (MovementController flies with them).
local function addWings(character: Model)
	local torso = character:WaitForChild("UpperTorso", 5)
	if not torso or not torso:IsA("BasePart") or character:FindFirstChild("Wing") then
		return
	end
	for _, side in { -1, 1 } do
		local wing = Instance.new("WedgePart")
		wing.Name = "Wing"
		wing.Size = Vector3.new(0.15, 2.2, 3) -- thin; the triangle spreads sideways
		wing.Color = Color3.fromRGB(150, 190, 245)
		wing.Material = Enum.Material.SmoothPlastic
		wing.CanCollide = false
		wing.CanQuery = false
		wing.CanTouch = false
		wing.Massless = true
		local weld = Instance.new("Weld")
		weld.Part0 = torso
		weld.Part1 = wing
		-- Straight edge along the top, tapering down towards the spine, tilted back.
		weld.C0 = CFrame.new(side * 1.75, 0.3, torso.Size.Z / 2 + 0.15)
			* CFrame.Angles(math.rad(-10), 0, 0)
			* CFrame.Angles(0, side * math.pi / 2, 0)
			* CFrame.Angles(math.pi, 0, 0)
		weld.Parent = wing
		wing.Parent = character
	end
end

local function applyTrail(player: Player)
	local data = DataService.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local old = root:FindFirstChild("RunTrail")
	if old then
		old:Destroy()
	end
	local def = data and data.trail and Cosmetics.trailByKey[data.trail]
	if not def then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "RunTrail"
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.8, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.8, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.5
	trail.LightEmission = 0.5
	local keypoints = {}
	for i, c in def.colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(#def.colors - 1, 1), c))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, def.colors[1]))
	end
	trail.Color = ColorSequence.new(keypoints)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Parent = folder
	folder.Parent = root
	-- Attachments must live under the root; tie their lifetime to the folder.
	folder.Destroying:Connect(function()
		a0:Destroy()
		a1:Destroy()
	end)
end

-- Puts on a trail or running animation (nil key = take that kind off).
local function wear(player: Player, data: Types.PlayerData, isRun: boolean, key: string?)
	if isRun then
		data.run = key
		task.spawn(applyRun, player)
	else
		data.trail = key
		applyTrail(player)
	end
	ProgressionService.refresh(player)
end

-- Trails and running animations, bought with Coins (Bricks) and equipped.
local function onBuyTrail(player: Player, key: any): (boolean, string?)
	local data = DataService.get(player)
	local def = if type(key) == "string" then Cosmetics.trailByKey[key] or Cosmetics.runByKey[key] else nil
	if not limiter:allow(player) or not data or not def then
		return false, "bad request"
	end
	if not data.unlocked[def.key] then
		if not ProgressionService.spend(player, def.bricks) then
			return false, "not enough Coins"
		end
		data.unlocked[def.key] = true
	end
	wear(player, data, Cosmetics.runByKey[def.key] ~= nil, def.key)
	return true, nil
end

-- key "" = no trail, Cosmetics.DEFAULT_RUN = the avatar's own run.
local function onEquipTrail(player: Player, key: any): boolean
	local data = DataService.get(player)
	if not limiter:allow(player) or not data or type(key) ~= "string" then
		return false
	end
	if key == "" or key == Cosmetics.DEFAULT_RUN then
		wear(player, data, key ~= "", nil)
		return true
	end
	if not ((Cosmetics.trailByKey[key] or Cosmetics.runByKey[key]) and data.unlocked[key]) then
		return false
	end
	wear(player, data, Cosmetics.runByKey[key] ~= nil, key)
	return true
end

local function applyTheme(player: Player)
	local data = DataService.get(player)
	local key = if data and MonetizationService.hasPass(player, "VIP")
		then data.theme
		else Cosmetics.DEFAULT_THEME
	local def = Cosmetics.themeByKey[key] or Cosmetics.themeByKey[Cosmetics.DEFAULT_THEME]
	PlotService.configure(player, def.key, if data then data.plotSize else Config.PLOT_CELLS_X)
end
MonetizationService.applyTheme = applyTheme

local function onSetTheme(player: Player, key: any): boolean
	local data = DataService.get(player)
	if
		not limiter:allow(player)
		or not data
		or type(key) ~= "string"
		or not Cosmetics.themeByKey[key]
		or not MonetizationService.hasPass(player, "VIP")
	then
		return false
	end
	data.theme = key
	applyTheme(player)
	return true
end

-- Bricks packs. Grants once per purchase id, and only reports success once the
-- grant is saved, so Roblox retries if a server dies mid-purchase.
local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local bricks = Config.BRICK_PRODUCTS[receipt.ProductId]
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local data = player and DataService.get(player)
	if not bricks or not player or not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local id = tostring(receipt.PurchaseId)
	if table.find(data.receipts, id) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	data.bricks += bricks
	table.insert(data.receipts, id)
	while #data.receipts > Config.RECEIPTS_KEPT do
		table.remove(data.receipts, 1)
	end
	if not DataService.saveNow(player) then
		data.bricks -= bricks
		table.remove(data.receipts, table.find(data.receipts, id) :: number)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	ProgressionService.refresh(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.init()
	ProgressionService.setPassCheck(function(player: Player): boolean
		return MonetizationService.hasPass(player, "BuilderPass")
	end)
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, _passId: number, bought: boolean)
			if bought then
				refreshPasses(player)
				applyTheme(player)
			end
		end
	)
	DataService.Loaded:Connect(function(player: Player)
		task.spawn(function()
			refreshPasses(player)
			applyTheme(player)
			applyTrail(player)
			applyRun(player)
		end)
		player.CharacterAdded:Connect(function(character)
			task.defer(applyTrail, player)
			task.spawn(applyRun, player)
			task.spawn(addWings, character)
		end)
		if player.Character then
			task.spawn(addWings, player.Character)
		end
	end)
	Remotes.func("BuyTrail").OnServerInvoke = onBuyTrail
	Remotes.func("EquipTrail").OnServerInvoke = onEquipTrail
	Remotes.func("SetTheme").OnServerInvoke = onSetTheme
	Players.PlayerRemoving:Connect(function(player)
		passes[player] = nil
		limiter:forget(player)
	end)
end

return MonetizationService

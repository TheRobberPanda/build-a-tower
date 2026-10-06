--!strict
-- Client-only juice for building: new pieces drop into place with a little
-- bounce and a dust puff instead of popping in. Fills cascade one by one.
-- Purely visual; the server's pieces end exactly where they were placed.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PlacementFxController = {}

local DROP = 3 -- studs above the final spot
local TIME = 0.28
local STAGGER = 0.03 -- per piece in the same burst (fills)
local MAX_ANIMATED = 64 -- bigger bursts are loads (slot switch, join): no animation

local burst = 0
local readyAt: { [Instance]: number } = {} -- Pieces folder -> when its first load is over

local function puff(at: Vector3)
	local a = Instance.new("Attachment")
	a.WorldPosition = at
	a.Parent = workspace.Terrain
	local p = Instance.new("ParticleEmitter")
	p.Texture = "rbxasset://textures/particles/smoke_main.dds"
	p.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	p.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	p.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3) })
	p.Lifetime = NumberRange.new(0.35, 0.5)
	p.Speed = NumberRange.new(6, 9)
	p.SpreadAngle = Vector2.new(180, 10)
	p.Drag = 6
	p.Enabled = false
	p.Parent = a
	p:Emit(8)
	task.delay(0.8, function()
		a:Destroy()
	end)
end

local function animate(piece: Instance, delay: number)
	-- Pieces are a root part (or model) with anchored decoration parts inside:
	-- move every part by the same offset from where the server put it.
	local parts: { BasePart } = {}
	local finals: { CFrame } = {}
	if piece:IsA("BasePart") then
		table.insert(parts, piece)
	end
	for _, d in piece:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	if #parts == 0 then
		return
	end
	local low = math.huge
	local mid = Vector3.zero
	for i, p in parts do
		finals[i] = p.CFrame
		low = math.min(low, p.Position.Y - p.Size.Y / 2)
		mid += p.Position
	end
	mid /= #parts
	local value = Instance.new("NumberValue")
	value.Value = DROP
	local function apply()
		if piece.Parent == nil then
			return
		end
		local lift = Vector3.new(0, value.Value, 0)
		for i, p in parts do
			p.CFrame = finals[i] + lift
		end
	end
	apply()
	local conn = value.Changed:Connect(apply)
	task.delay(delay, function()
		local tween = TweenService:Create(
			value,
			TweenInfo.new(TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Value = 0 }
		)
		tween.Completed:Once(function()
			conn:Disconnect()
			value.Value = 0
			apply()
			value:Destroy()
		end)
		tween:Play()
		task.delay(TIME * 0.6, puff, Vector3.new(mid.X, low, mid.Z))
	end)
end

local function watch(folder: Instance)
	if readyAt[folder] then
		return
	end
	readyAt[folder] = os.clock() + 1.5 -- the plot's initial load
	folder.ChildAdded:Connect(function(child)
		if os.clock() < (readyAt[folder] or math.huge) then
			return
		end
		burst += 1
		if burst <= MAX_ANIMATED then
			animate(child, (burst - 1) * STAGGER)
		end
	end)
	folder.Destroying:Connect(function()
		readyAt[folder] = nil
	end)
end

function PlacementFxController.start()
	RunService.Heartbeat:Connect(function()
		burst = 0
	end)
	local plots = workspace:WaitForChild("Plots")
	local function onAdded(d: Instance)
		if d.Name == "Pieces" and d:IsA("Folder") then
			watch(d)
		end
	end
	plots.DescendantAdded:Connect(onAdded)
	for _, d in plots:GetDescendants() do
		onAdded(d)
	end
end

return PlacementFxController

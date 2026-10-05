--!strict
-- Ghosts and replays. During a race the record holder's run plays as a
-- translucent ghost from the start signal. "Watch" plays a saved run on your
-- plot with the camera following it. Checkpoint splits show a toast compared to
-- the ghost's split at the same checkpoint.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PathCodec = require(ReplicatedStorage.Shared.PathCodec)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)

local GhostController = {}

local player = Players.LocalPlayer

type Playback =
	{ points: { Vector3 }, origin: Vector3, startedAt: number, splits: { number }, watch: boolean }

local playback: Playback? = nil
local ghost: Model? = nil
local gui: ScreenGui
local splitLabel: TextLabel
local stopButton: TextButton
local playToken = 0

local function plotOrigin(): Vector3?
	local plots = workspace:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot_" .. player.UserId)
	local origin = plot and plot:GetAttribute("Origin")
	return if typeof(origin) == "Vector3" then origin else nil
end

local function makeGhost(color: Color3?): Model
	local model = Instance.new("Model")
	model.Name = "Ghost"
	local function part(name: string, size: Vector3, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Shape = shape or Enum.PartType.Block
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.ForceField
		p.Color = color or Color3.fromRGB(120, 220, 255)
		p.Parent = model
		return p
	end
	local torso = part("Torso", Vector3.new(2, 2, 1))
	part("Head", Vector3.new(1.3, 1.3, 1.3), Enum.PartType.Ball)
	model.PrimaryPart = torso
	return model
end

local function stop()
	playToken += 1
	local wasWatching = playback and playback.watch
	playback = nil
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	stopButton.Visible = false
	local camera = workspace.CurrentCamera
	if wasWatching and camera then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

local function play(replay: any, watch: boolean)
	stop()
	local points = PathCodec.decode(replay and replay.path, Config.PATH_MAX_SAMPLES * 2)
	local origin = plotOrigin()
	if not points or #points < 2 or not origin then
		return
	end
	local splits = {}
	if type(replay.splits) == "table" then
		for _, v in replay.splits do
			if type(v) == "number" then
				table.insert(splits, v)
			end
		end
	end
	playback = { points = points, origin = origin, startedAt = os.clock(), splits = splits, watch = watch }
	local model = makeGhost()
	model.Parent = workspace
	ghost = model
	if watch then
		stopButton.Visible = true
		local camera = workspace.CurrentCamera
		if camera and model.PrimaryPart then
			camera.CameraSubject = model.PrimaryPart
		end
	end
end

local function step()
	local pb = playback
	local model = ghost
	if not pb or not model then
		return
	end
	local t = (os.clock() - pb.startedAt) / Config.PATH_SAMPLE_SECONDS
	local i = math.floor(t) + 1
	if i >= #pb.points then
		if pb.watch then
			stop() -- replay over
		else
			model:PivotTo(CFrame.new(pb.origin + pb.points[#pb.points])) -- ghost waits at the top
		end
		return
	end
	local a, b = pb.points[i], pb.points[i + 1]
	local pos = pb.origin + a:Lerp(b, t - (i - 1))
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local cf = if flat.Magnitude > 0.05 then CFrame.lookAt(pos, pos + flat) else CFrame.new(pos)
	local torso = model:FindFirstChild("Torso") :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart
	torso.CFrame = cf
	head.CFrame = cf * CFrame.new(0, 1.7, 0)
end

local function showSplit(index: number, ms: number)
	local text = string.format("Checkpoint %d  %s", index, Kit.formatMs(ms))
	local pb = playback
	local ref = pb and pb.splits[index]
	if ref then
		local diff = (ms - ref) / 1000
		text ..= string.format("  %s%.2fs", if diff <= 0 then "-" else "+", math.abs(diff))
		splitLabel.TextColor3 = if diff <= 0 then Theme.Success else Theme.Danger
	else
		splitLabel.TextColor3 = Theme.Text
	end
	splitLabel.Text = text
	splitLabel.Visible = true
	local token = playToken
	task.delay(3, function()
		if playToken == token then
			splitLabel.Visible = false
		end
	end)
end

-- A translucent ghost model (also used for live race opponents).
function GhostController.newGhost(color: Color3?): Model
	return makeGhost(color)
end

-- Called from the leaderboard: watch a saved run (racerId 0 = record).
function GhostController.watch(ownerId: number, racerId: number)
	task.spawn(function()
		local ok, replay = pcall(function()
			return Remotes.func("WatchReplay"):InvokeServer(ownerId, racerId)
		end)
		if ok and replay then
			play(replay, true)
		end
	end)
end

function GhostController.init()
	gui = Kit.new("ScreenGui", {
		Name = "GhostUI",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Parent = player:WaitForChild("PlayerGui"),
	})
	splitLabel = Kit.label("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.15),
		Size = UDim2.fromScale(0.4, 0.05),
		Visible = false,
		Parent = gui,
	})
	stopButton = Kit.button("Stop watching", Theme.Danger, function()
		stop()
		Remotes.event("StopWatch"):FireServer()
	end, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.03),
		Size = UDim2.fromScale(0.22, 0.07),
		Visible = false,
		Parent = gui,
	})
end

function GhostController.start()
	Remotes.event("RunStarted").OnClientEvent:Connect(function(ownerId)
		stop()
		if type(ownerId) ~= "number" or ownerId == player.UserId then
			return
		end
		local token = playToken
		task.spawn(function()
			local ok, replay = pcall(function()
				return Remotes.func("GetReplay"):InvokeServer(ownerId, 0)
			end)
			if ok and replay and playToken == token then
				play(replay, false)
				local pb = playback
				if pb then
					pb.startedAt -= 0.1 -- rough latency allowance; the ghost is only a guide
				end
			end
		end)
	end)
	Remotes.event("RunResult").OnClientEvent:Connect(function()
		stop()
	end)
	Remotes.event("Split").OnClientEvent:Connect(function(index, ms)
		if type(index) == "number" and type(ms) == "number" then
			showSplit(index, ms)
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return GhostController

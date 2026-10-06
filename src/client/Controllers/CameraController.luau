--!strict
-- The normal Roblox camera everywhere: first person by default, scroll / pinch
-- to zoom out to third person, right drag / swipe to look around. While
-- building (the Camera button toggles it) it starts zoomed out and zooms much
-- further. Blocks between you and the camera turn see-through instead of
-- pushing it in (DevCameraOcclusionMode = Invisicam on StarterPlayer, in the
-- project file). Walk (or glide) to wherever you want to build.

local Players = game:GetService("Players")

local State = require(script.Parent.Parent.State)

local CameraController = {}

local player = Players.LocalPlayer
local MIN_ZOOM = 0.5
local PLAY_MAX = 40
local BUILD_MAX = 400
local BUILD_ZOOM = 70

local active = false
local manualOff = false -- the player turned the build camera off for this build session

local changed = Instance.new("BindableEvent")
CameraController.Changed = changed.Event -- (active)

-- Moves the zoom to `d` (min = max = d for a moment), then frees it again.
local function zoomTo(d: number, max: number)
	player.CameraMaxZoomDistance = math.max(d, max)
	player.CameraMinZoomDistance = d
	task.delay(0.1, function()
		player.CameraMinZoomDistance = MIN_ZOOM
		player.CameraMaxZoomDistance = max
	end)
end

function CameraController.isActive(): boolean
	return active
end

-- Building right now: your round tower in the build phase, or free building.
local function building(): boolean
	return State.mode == "build"
		and (if State.inRound then State.roundPhase == "build" else State.lobbyMode == "free")
end

function CameraController.set(on: boolean)
	if on == active then
		return
	end
	active = on
	if on then
		zoomTo(BUILD_ZOOM, BUILD_MAX)
	else
		zoomTo(MIN_ZOOM, PLAY_MAX)
	end
	changed:Fire(active)
end

function CameraController.toggle()
	manualOff = active
	CameraController.set(not active)
end

function CameraController.start()
	player.CameraMode = Enum.CameraMode.Classic
	zoomTo(MIN_ZOOM, PLAY_MAX) -- start in first person
	-- On while building (unless turned off).
	local wasBuilding = false
	local function sync()
		local now = building()
		if now ~= wasBuilding then
			manualOff = false -- each build session starts with the build camera
			wasBuilding = now
		end
		CameraController.set(now and not manualOff)
	end
	State.Changed:Connect(sync)
	sync()
end

return CameraController

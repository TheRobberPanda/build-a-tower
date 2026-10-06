-- Studio command bar (Edit mode or paused Play): stages a dramatic shot of the
-- first plot for store thumbnails. Hides GUIs, aims a low camera up the tower.
-- Usage: paste, run, then capture at 1920x1080 into marketing/raw/.
local Lighting = game:GetService("Lighting")
Lighting.ClockTime = 15
local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	or Instance.new("ColorCorrectionEffect", Lighting)
cc.Saturation = 0.25
cc.Contrast = 0.1
if not Lighting:FindFirstChildOfClass("SunRaysEffect") then
	Instance.new("SunRaysEffect", Lighting).Intensity = 0.08
end
for _, gui in game:GetService("StarterGui"):GetChildren() do
	if gui:IsA("ScreenGui") then
		gui.Enabled = false
	end
end
local plot = workspace:FindFirstChild("Plots") and workspace.Plots:GetChildren()[1]
assert(plot, "no plot: start Play once so a plot exists, then pause")
local cf, size = plot:GetBoundingBox()
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.FieldOfView = 60
local foot = cf.Position - Vector3.new(0, size.Y / 2, 0)
cam.CFrame = CFrame.lookAt(
	foot + Vector3.new(size.X * 0.9, 6, -size.Z * 0.9),
	cf.Position + Vector3.new(0, size.Y * 0.25, 0)
)
print("staged; capture now")

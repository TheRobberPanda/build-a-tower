-- Edit-mode only: builds the slot-0 plot island, world scenery and lighting into
-- workspace.EditorPreview so the map is visible in Studio. PlotService destroys
-- EditorPreview at runtime and builds the real thing. Re-run after builder changes.
local cache = {}
local function load(module)
	if cache[module] ~= nil then
		return cache[module]
	end
	local fn = assert(loadstring(module.Source, module:GetFullName()))
	setfenv(
		fn,
		setmetatable({
			script = module,
			require = function(m)
				if typeof(m) == "Instance" and m:IsA("ModuleScript") then
					return load(m)
				end
				return require(m)
			end,
		}, { __index = getfenv(1) })
	)
	cache[module] = fn()
	return cache[module]
end
local PlotBuilder = load(game.ServerScriptService.Server.Services.PlotBuilder)

for _, name in { "EditorPreview", "World" } do
	local old = workspace:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end
local folder = Instance.new("Folder")
folder.Name = "EditorPreview"
local plot = Instance.new("Model")
plot.Name = "Plot_Preview"
PlotBuilder.base(plot, Vector3.zero, 16)
PlotBuilder.build(plot, Vector3.zero, 16)
plot.Parent = folder
PlotBuilder.buildWorld()
workspace.World.Parent = folder
PlotBuilder.lighting()
folder.Parent = workspace
return "editor island built"

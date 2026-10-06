-- Edit-mode preview of a plot with the real builders (fresh module loads).
-- Builds workspace.Preview from a read-only copy of a saved tower and aims the
-- camera. Pass VIEW = "front" | "side" | "top" | "close". Remove with
-- workspace.Preview:Destroy() (tools/preview_cleanup).
local VIEW = VIEW or "front"
local SHOWCASE = SHOWCASE
local ALL = ALL -- true: one of every piece type in a grid (VIEW is ignored)
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
local Services = game.ServerScriptService.Server.Services
local PlotBuilder = load(Services.PlotBuilder)
local PieceFactory = load(game.ReplicatedStorage.Shared.PieceFactory)
local Config = load(game.ReplicatedStorage.Shared.Config)

local old = workspace:FindFirstChild("Preview")
if old then
	old:Destroy()
end
local origin = Vector3.new(3000, 0, 0)
local model = Instance.new("Model")
model.Name = "Preview"
PlotBuilder.base(model, origin, 16, nil, THEME)
PlotBuilder.build(model, origin, 16, nil, THEME)
if CORE or SHOWCASE then
	PlotBuilder.core(model, origin) -- the round tower frame
end
local raw = game:GetService("DataStoreService"):GetDataStore("Players_v1"):GetAsync("u_757790113")
local slot = raw and raw.data and raw.data.slots and raw.data.slots["1"]
local pieces = if ACTIVE and raw then raw.data.tower.pieces elseif slot then slot.tower.pieces else {}
if SHOWCASE then
	-- A hand-placed layout that shows off the premades around the frame.
	local function P(t, x, y, z, r, p)
		return { t = t, x = x, y = y, z = z, r = r or 0, p = p }
	end
	pieces = {
		P(19, 4, 0, 2),
		P(20, 4, 1, 4),
		P(19, 4, 2, 8),
		P(20, 4, 3, 10, 1),
		P(21, 11, 0, 0),
		P(2, 11, 2, 4),
		P(19, 12, 2, 6),
		P(20, 12, 3, 8),
		P(4, 13, 0, 13, 0, { power = 2 }),
		P(5, 2, 0, 12, 0, { ch = 1 }),
		P(5, 7, 6, 7, 0, { ch = 1 }),
		P(1, 13, 0, 3),
		P(1, 13, 1, 3),
		P(1, 14, 0, 3),
		P(3, 14, 0, 5, 2),
		P(6, 3, 0, 7),
		P(21, 6, 6, 1, 1),
		P(4, 11, 6, 12, 0, { power = 3 }),
		P(14, 2, 0, 2),
		P(8, 7, 30, 7),
		P(16, 1, 0, 14),
		P(15, 15, 0, 15),
	}
end
if ALL then
	pieces = {}
	local PieceDefs = load(game.ReplicatedStorage.Shared.PieceDefs)
	for i, def in PieceDefs.list do
		local p = nil
		for key, range in def.props do
			p = { [key] = if key == "power" then 2 else range[1] }
		end
		local n = i - 1
		table.insert(pieces, { t = def.id, x = n % 6 * 4, y = 0, z = 1 + n // 6 * 4, r = 0, p = p })
	end
end
local folder = Instance.new("Folder")
folder.Name = "Pieces"
local made = 0
for _, p in pieces do
	local ok = pcall(function()
		PieceFactory.make(p, origin).Parent = folder
	end)
	if ok then
		made += 1
	end
end
folder.Parent = model
model.Parent = workspace
if not workspace.Terrain:FindFirstChildOfClass("Clouds") then
	local clouds = Instance.new("Clouds") -- the game adds these at runtime too
	clouds.Name = "PreviewClouds"
	clouds.Cover = 0.55
	clouds.Density = 0.6
	clouds.Parent = workspace.Terrain
end
local G = Config.GRID_STUDS
local k = G / 4 -- views were tuned for 4-stud cells
local center = origin + Vector3.new(Config.PLOT_CELLS_X * G / 2, 30 * k, Config.PLOT_CELLS_Z * G / 2)
local cam = workspace.CurrentCamera
cam.FieldOfView = 60
local views = {
	front = CFrame.lookAt(center + Vector3.new(-20, 25, -95) * k, center + Vector3.new(0, 5, 0) * k),
	side = CFrame.lookAt(center + Vector3.new(95, 40, 30) * k, center),
	top = CFrame.lookAt(center + Vector3.new(0, 140, -60) * k, center - Vector3.new(0, 30, 0) * k),
	close = CFrame.lookAt(center + Vector3.new(-14, -16, -40) * k, center + Vector3.new(0, -20, 0) * k),
}
local view = if ALL
	then CFrame.lookAt(origin + Vector3.new(11, 11, -7) * G, origin + Vector3.new(11, 0, 10) * G)
	else views[VIEW]
cam.CFrame = view
cam.Focus = view * CFrame.new(0, 0, -60) -- without a Focus the unfocused edit camera snaps back
return string.format("preview built: %d/%d pieces, view %s", made, #pieces, VIEW)

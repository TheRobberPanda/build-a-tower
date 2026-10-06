--!strict
-- Live 3D hotbar icons: a ViewportFrame with the real piece model (same
-- PieceFactory the server uses), so icons always match what you place.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PieceDefs = require(ReplicatedStorage.Shared.PieceDefs)
local PieceFactory = require(ReplicatedStorage.Shared.PieceFactory)

local PieceIcon = {}

function PieceIcon.new(typeId: number, props: { [string]: any }): ViewportFrame
	local def = PieceDefs.byId[typeId]
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(170, 170, 185)
	vp.LightColor = Color3.fromRGB(255, 250, 240)
	vp.LightDirection = Vector3.new(-1, -2, -0.6)
	for k, v in props do
		(vp :: any)[k] = v
	end
	local p: { [string]: number }? = nil
	for k, range in def.props do
		p = { [k] = range[1] }
	end
	local ok, root = pcall(PieceFactory.make, { t = typeId, x = 0, y = 0, z = 0, r = 0, p = p }, Vector3.zero)
	if not ok then
		return vp
	end
	local model = Instance.new("Model")
	root.Parent = model
	for _, d in model:GetDescendants() do
		for _, tag in CollectionService:GetTags(d) do
			CollectionService:RemoveTag(d, tag) -- an icon must never act like a piece
		end
		if d == root and def.name == "InvisiblePlatform" then
			d.Transparency = 0.55 -- show invisible platforms as glass
			d.Color = Color3.fromRGB(200, 235, 255)
		elseif d:IsA("Light") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	model.Parent = vp
	local cf, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local dist = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	local dir = Vector3.new(-1, 0.85, -1.15).Unit
	camera.CFrame = CFrame.lookAt(cf.Position + dir * dist, cf.Position)
	camera.Parent = vp
	vp.CurrentCamera = camera
	return vp
end

return PieceIcon

--!strict
-- Hotbar icons: one cell of the piece icon sheet (assets/ui/piece_icons.png),
-- drawn in the same style the pieces are built to match (PieceVisuals). Pieces
-- past the sheet (traps, store decorations) show a live 3D view of the piece.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PieceDefs = require(ReplicatedStorage.Shared.PieceDefs)
local PieceFactory = require(ReplicatedStorage.Shared.PieceFactory)
local Theme = require(script.Parent.Theme)

local PieceIcon = {}

local SHEET_LAST = 25 -- highest piece id drawn on the sheet

local function viewport(typeId: number, props: { [string]: any }): ViewportFrame
	local vf = Instance.new("ViewportFrame")
	vf.BackgroundTransparency = 1
	vf.Ambient = Color3.fromRGB(200, 200, 200)
	vf.LightColor = Color3.fromRGB(255, 255, 255)
	vf.LightDirection = Vector3.new(-1, -2, -1)
	for k, v in props do
		(vf :: any)[k] = v
	end
	local def = PieceDefs.byId[typeId]
	local piece = { t = typeId, x = 0, y = 0, z = 0, r = 0, p = nil :: { [string]: number }? }
	for key, range in def.props do
		piece.p = { [key] = range[1] }
	end
	local part = PieceFactory.make(piece, Vector3.zero)
	-- Frame the whole piece (decoration children included) from above-front.
	local model = Instance.new("Model")
	part.Parent = model
	model.Parent = vf
	local cf, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local dist = size.Magnitude * 1.25
	camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(-0.6, 0.55, -0.8).Unit * dist, cf.Position)
	camera.Parent = vf
	vf.CurrentCamera = camera
	return vf
end

function PieceIcon.new(typeId: number, props: { [string]: any }): GuiObject
	if typeId > SHEET_LAST then
		return viewport(typeId, props)
	end
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Fit
	for k, v in props do
		(img :: any)[k] = v
	end
	local i = typeId - 1
	local cell = Theme.PieceIconCell
	img.Image = Theme.PieceIconSheet
	img.ImageRectSize = Vector2.new(cell, cell)
	img.ImageRectOffset = Vector2.new(i % Theme.PieceIconColumns * cell, i // Theme.PieceIconColumns * cell)
	return img
end

return PieceIcon

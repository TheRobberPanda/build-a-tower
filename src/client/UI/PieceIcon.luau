--!strict
-- Hotbar icons: one cell of the piece icon sheet (assets/ui/piece_icons.png),
-- drawn in the same style the pieces are built to match (PieceVisuals).

local Theme = require(script.Parent.Theme)

local PieceIcon = {}

function PieceIcon.new(typeId: number, props: { [string]: any }): ImageLabel
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

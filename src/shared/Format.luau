--!strict
-- Text formatting shared by server messages and client UI.

local Format = {}

-- 83456 -> "1:23.456"
function Format.ms(ms: number): string
	local minutes = ms // 60000
	local seconds = (ms % 60000) / 1000
	return string.format("%d:%06.3f", minutes, seconds)
end

return table.freeze(Format)

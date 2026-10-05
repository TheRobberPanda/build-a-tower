--!strict
-- Builder progression rules shared by server and client. XP comes from other
-- players finishing and liking your towers; Bricks are the soft currency.

local Config = require(script.Parent.Config)

local Progression = {}

-- Level 1 at 0 XP; each level costs 100 more XP than the last (100, 200, 300...).
function Progression.level(xp: number): number
	local level, need, total = 1, 100, 0
	while xp >= total + need and level < Config.MAX_LEVEL do
		total += need
		level += 1
		need += 100
	end
	return level
end

-- XP needed to reach `level` from zero.
function Progression.xpFor(level: number): number
	local total = 0
	for l = 1, level - 1 do
		total += l * 100
	end
	return total
end

-- Piece budget grows with level: 150 at level 1, +15 per level, capped.
-- The Builder Pass adds a flat bonus on top (and may exceed the level cap).
function Progression.budget(level: number, hasPass: boolean?): number
	local base = math.min(Config.PIECE_BUDGET + (level - 1) * 15, Config.PIECE_BUDGET_MAX)
	return base + (if hasPass then Config.PASS_EXTRA_BUDGET else 0)
end

function Progression.slots(hasPass: boolean?): number
	return Config.TOWER_SLOTS + (if hasPass then Config.PASS_EXTRA_SLOTS else 0)
end

return table.freeze(Progression)

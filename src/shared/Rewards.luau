--!strict
-- Round rewards and course trophies (pure, so the odds are testable).

local Config = require(script.Parent.Config)
local PieceDefs = require(script.Parent.PieceDefs)

local Rewards = {}

-- Chance of a prize after a round: base, more if you won a race, more per star
-- your tower got (average, 0-5).
function Rewards.chance(won: boolean, stars: number?): number
	return math.min(0.25 + (if won then 0.35 else 0) + (stars or 0) * 0.06, 0.95)
end

-- What a round gives: "expand" (bigger island), a store decoration id the
-- player doesn't own, or nil. `roll` and `pick` are uniform 0..1 numbers.
function Rewards.roll(
	won: boolean,
	stars: number?,
	owned: { [string]: boolean },
	plotSize: number,
	roll: number,
	pick: number
): (string | number)?
	if roll >= Rewards.chance(won, stars) then
		return nil
	end
	if plotSize < Config.PLOT_CELLS_MAX and pick < 0.25 then
		return "expand"
	end
	local options = {}
	for _, def in PieceDefs.list do
		if def.asset and not owned["decor_" .. def.id] then
			table.insert(options, def.id)
		end
	end
	if #options == 0 then
		return nil
	end
	return options[math.clamp(math.floor(pick * #options) + 1, 1, #options)]
end

-- Every course carries one store decoration you can take by finishing it,
-- the same one for every player (picked from the tower's hash).
function Rewards.trophyFor(hash: string): number
	local n = 0
	for i = 1, math.min(#hash, 16) do
		n = (n * 31 + string.byte(hash, i)) % 1000003
	end
	local ids = {}
	for _, def in PieceDefs.list do
		if def.asset then
			table.insert(ids, def.id)
		end
	end
	return ids[n % #ids + 1]
end

return table.freeze(Rewards)

--!strict
-- Calendar for live ops: monthly seasons, limited-time pieces and build contests.
-- All times are UTC unix seconds. Edit Config.EVENT_PIECES / Config.CONTESTS to
-- schedule; no code changes needed.

local Config = require(script.Parent.Config)

local Events = {}

-- "202610" for October 2026.
function Events.season(now: number): string
	local t = os.date("!*t", now)
	return string.format("%04d%02d", t.year, t.month)
end

-- Limited-time pieces can only be placed inside their window (placed ones stay).
function Events.pieceAvailable(typeId: number, now: number): boolean
	local window = Config.EVENT_PIECES[typeId]
	return window == nil or (now >= window[1] and now < window[2])
end

export type Contest = { id: string, theme: string, starts: number, votingFrom: number, ends: number }

-- The contest that is open for entries or voting at `now`, if any.
function Events.contest(now: number): (Contest?, "entries" | "voting" | nil)
	for _, c in Config.CONTESTS do
		if now >= c.starts and now < c.votingFrom then
			return c, "entries"
		elseif now >= c.votingFrom and now < c.ends then
			return c, "voting"
		end
	end
	return nil, nil
end

return table.freeze(Events)

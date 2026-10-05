--!strict
-- Pure tower logic: validation, sanitising on load, placement checks, hashing.
-- No Roblox services here so it can be unit tested in isolation.

local Config = require(script.Parent.Config)
local PieceDefs = require(script.Parent.PieceDefs)
local Types = require(script.Parent.Types)

type Piece = Types.Piece
type Tower = Types.Tower

local TowerCodec = {}

local function isInt(n: any, lo: number, hi: number): boolean
	return type(n) == "number" and n == n and n % 1 == 0 and n >= lo and n <= hi
end

-- Size in cells after rotation (odd rotations swap x and z).
function TowerCodec.extent(piece: Piece): (number, number, number)
	local def = PieceDefs.byId[piece.t]
	local sx, sy, sz = def.size[1], def.size[2], def.size[3]
	if piece.r % 2 == 1 then
		sx, sz = sz, sx
	end
	return sx, sy, sz
end

local function cellIndex(x: number, y: number, z: number): number
	return x + z * Config.PLOT_CELLS_X + y * Config.PLOT_CELLS_X * Config.PLOT_CELLS_Z
end

local function forEachCell(piece: Piece, fn: (number) -> ())
	local sx, sy, sz = TowerCodec.extent(piece)
	for dy = 0, sy - 1 do
		for dz = 0, sz - 1 do
			for dx = 0, sx - 1 do
				fn(cellIndex(piece.x + dx, piece.y + dy, piece.z + dz))
			end
		end
	end
end

-- Checks a single untrusted value and returns a clean copy (unknown fields dropped).
function TowerCodec.validatePiece(raw: any): (Piece?, string?)
	if type(raw) ~= "table" then
		return nil, "piece not a table"
	end
	local def = if isInt(raw.t, 1, 255) then PieceDefs.byId[raw.t] else nil
	if not def then
		return nil, "unknown piece type"
	end
	if not isInt(raw.r, 0, 3) then
		return nil, "bad rotation"
	end
	if not (isInt(raw.x, 0, 1e4) and isInt(raw.y, 0, 1e4) and isInt(raw.z, 0, 1e4)) then
		return nil, "bad position"
	end
	local piece: Piece = { t = raw.t, x = raw.x, y = raw.y, z = raw.z, r = raw.r }
	local sx, sy, sz = TowerCodec.extent(piece)
	if
		piece.x + sx > Config.PLOT_CELLS_X
		or piece.y + sy > Config.PLOT_CELLS_Y
		or piece.z + sz > Config.PLOT_CELLS_Z
	then
		return nil, "out of bounds"
	end

	if raw.p ~= nil then
		if type(raw.p) ~= "table" then
			return nil, "bad props"
		end
		local props: { [string]: number } = {}
		local count = 0
		for k, v in raw.p do
			local range = if type(k) == "string" then def.props[k] else nil
			if not range or not isInt(v, range[1], range[2]) then
				return nil, "bad prop"
			end
			props[k] = v
			count += 1
			if count > 4 then
				return nil, "too many props"
			end
		end
		if count > 0 then
			piece.p = props
		end
	end
	-- Fill in required props with their minimum so every piece is fully specified.
	for key, range in def.props do
		if not (piece.p and piece.p[key]) then
			local props = piece.p or {}
			props[key] = range[1]
			piece.p = props
		end
	end
	return piece, nil
end

export type PlaceState = {
	occupied: { [number]: boolean },
	counts: { [number]: number },
	total: number, -- pieces counting toward the budget
	decor: number, -- decorations (own cap, outside the budget)
	budget: number,
}

-- budget defaults to the largest any player can have (used when loading stored towers).
function TowerCodec.newPlaceState(budget: number?): PlaceState
	return { occupied = {}, counts = {}, total = 0, decor = 0, budget = budget or Config.PIECE_BUDGET_STORED }
end

-- Checks budget, per-type limits and overlap against the current state.
function TowerCodec.canAdd(state: PlaceState, piece: Piece): (boolean, string?)
	local def = PieceDefs.byId[piece.t]
	if def.decor then
		if state.decor >= Config.DECOR_MAX then
			return false, "decor limit"
		end
	elseif state.total >= state.budget then
		return false, "over budget"
	end
	if def.maxCount and (state.counts[piece.t] or 0) >= def.maxCount then
		return false, "type limit"
	end
	local overlap = false
	forEachCell(piece, function(i)
		if state.occupied[i] then
			overlap = true
		end
	end)
	if overlap then
		return false, "overlap"
	end
	return true, nil
end

function TowerCodec.add(state: PlaceState, piece: Piece)
	forEachCell(piece, function(i)
		state.occupied[i] = true
	end)
	state.counts[piece.t] = (state.counts[piece.t] or 0) + 1
	if PieceDefs.byId[piece.t].decor then
		state.decor += 1
	else
		state.total += 1
	end
end

function TowerCodec.remove(state: PlaceState, piece: Piece)
	forEachCell(piece, function(i)
		state.occupied[i] = nil
	end)
	state.counts[piece.t] -= 1
	if PieceDefs.byId[piece.t].decor then
		state.decor -= 1
	else
		state.total -= 1
	end
end

function TowerCodec.empty(): Tower
	return { v = Config.SCHEMA_VERSION, pieces = {} }
end

-- Lenient load path: keeps every valid piece, drops bad ones and anything past the
-- budget. Returns the clean tower and how many pieces were dropped. Returns nil
-- for data written by a newer schema so the caller can refuse to overwrite it.
function TowerCodec.sanitize(raw: any): (Tower?, number)
	if type(raw) ~= "table" or type(raw.pieces) ~= "table" then
		return TowerCodec.empty(), 0
	end
	if type(raw.v) ~= "number" or raw.v > Config.SCHEMA_VERSION then
		return nil, 0
	end
	-- (no older schemas exist yet; migrations go here keyed on raw.v)

	local tower = TowerCodec.empty()
	local state = TowerCodec.newPlaceState()
	for _, rawPiece in ipairs(raw.pieces) do
		local piece = TowerCodec.validatePiece(rawPiece)
		if piece and TowerCodec.canAdd(state, piece) then
			TowerCodec.add(state, piece)
			table.insert(tower.pieces, piece)
		end
	end
	-- Count every entry (ipairs stops at holes) so nothing is silently lost.
	local n = 0
	for _ in raw.pieces do
		n += 1
	end
	return tower, n - #tower.pieces
end

-- Strict path (publish): the whole tower must be valid as-is, with a finish.
function TowerCodec.validate(raw: any): (boolean, string?)
	local tower, dropped = TowerCodec.sanitize(raw)
	if not tower then
		return false, "unsupported version"
	end
	if dropped > 0 then
		return false, "invalid pieces"
	end
	for _, piece in tower.pieces do
		if piece.t == PieceDefs.FINISH_ID then
			return true, nil
		end
	end
	return false, "no finish"
end

function TowerCodec.buildState(tower: Tower, budget: number?): PlaceState
	local state = TowerCodec.newPlaceState(budget)
	for _, piece in tower.pieces do
		TowerCodec.add(state, piece)
	end
	return state
end

local function pieceString(piece: Piece): string
	local s = string.format("%d,%d,%d,%d,%d", piece.t, piece.x, piece.y, piece.z, piece.r)
	if piece.p then
		local keys = {}
		for k in piece.p do
			table.insert(keys, k)
		end
		table.sort(keys)
		for _, k in keys do
			s ..= string.format(",%s=%d", k, piece.p[k])
		end
	end
	return s
end

local function fnv1a(s: string, basis: number): number
	local h = basis
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		-- multiply by FNV prime 16777619 mod 2^32 without losing precision
		h = (bit32.lshift(h, 24) + h * 403) % 4294967296
	end
	return h
end

-- Order-independent content hash of the piece list. Any edit changes it.
function TowerCodec.hash(tower: Tower): string
	local parts = table.create(#tower.pieces)
	for i, piece in tower.pieces do
		parts[i] = pieceString(piece)
	end
	table.sort(parts)
	local s = table.concat(parts, ";")
	return string.format("%08x%08x-%d", fnv1a(s, 2166136261), fnv1a(s, 84696351), #parts)
end

return TowerCodec

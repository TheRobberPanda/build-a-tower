--!strict
-- Compact run paths for replays and ghosts. Positions are relative to the plot
-- origin (so a replay plays on any plot), sampled every Config.PATH_SAMPLE_SECONDS,
-- quantised to 1/4 stud, delta-encoded as int16 triples, then base64 so the
-- result is a plain DataStore-safe string. Format: "1:" .. base64.

local PathCodec = {}

local SCALE = 4 -- quarter studs
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DECODE: { [number]: number } = {}
for i = 1, #B64 do
	DECODE[string.byte(B64, i)] = i - 1
end

local function b64encode(data: string): string
	local out = table.create(math.ceil(#data / 3) * 4)
	for i = 1, #data, 3 do
		local a, b, c = string.byte(data, i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local chars = 2 + (if b then 1 else 0) + (if c then 1 else 0)
		for k = 1, 4 do
			if k <= chars then
				local v = (n // 64 ^ (4 - k)) % 64
				table.insert(out, string.sub(B64, v + 1, v + 1))
			else
				table.insert(out, "=")
			end
		end
	end
	return table.concat(out)
end

local function b64decode(text: string): string?
	if #text % 4 ~= 0 then
		return nil
	end
	local out = {}
	for i = 1, #text, 4 do
		local n, pad = 0, 0
		for k = 0, 3 do
			local ch = string.byte(text, i + k)
			local v = DECODE[ch]
			if ch == 61 then -- "="
				pad += 1
				v = 0
			elseif v == nil or pad > 0 then
				return nil
			end
			n = n * 64 + v
		end
		local bytes = string.char(n // 65536, (n // 256) % 256, n % 256)
		table.insert(out, string.sub(bytes, 1, 3 - pad))
	end
	return table.concat(out)
end

local function clamp16(v: number): number
	return math.clamp(v, -32768, 32767)
end

-- Encodes plot-relative positions. Big jumps (teleports) are split across
-- several deltas so nothing is clipped.
function PathCodec.encode(points: { Vector3 }): string
	local parts = {}
	local px, py, pz = 0, 0, 0
	for _, p in points do
		local x, y, z = math.round(p.X * SCALE), math.round(p.Y * SCALE), math.round(p.Z * SCALE)
		repeat
			local dx, dy, dz = clamp16(x - px), clamp16(y - py), clamp16(z - pz)
			table.insert(parts, string.pack("<hhh", dx, dy, dz))
			px += dx
			py += dy
			pz += dz
		until px == x and py == y and pz == z
	end
	return "1:" .. b64encode(table.concat(parts))
end

-- Returns nil for anything malformed (stored data is untrusted).
function PathCodec.decode(text: any, maxPoints: number?): { Vector3 }?
	if type(text) ~= "string" or string.sub(text, 1, 2) ~= "1:" then
		return nil
	end
	local data = b64decode(string.sub(text, 3))
	if not data or #data % 6 ~= 0 then
		return nil
	end
	local limit = maxPoints or 100000
	if #data // 6 > limit then
		return nil
	end
	local points = table.create(#data // 6)
	local x, y, z = 0, 0, 0
	for i = 1, #data, 6 do
		local dx, dy, dz = string.unpack("<hhh", data, i)
		x += dx
		y += dy
		z += dz
		table.insert(points, Vector3.new(x, y, z) / SCALE)
	end
	return points
end

return PathCodec

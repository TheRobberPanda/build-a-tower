return function()
	local PathCodec = require(game:GetService("ReplicatedStorage").Shared.PathCodec)

	local function near(a: Vector3, b: Vector3): boolean
		return (a - b).Magnitude < 0.2
	end

	it("round-trips a path within a quarter stud", function()
		local path = {}
		for i = 1, 300 do
			table.insert(path, Vector3.new(math.sin(i / 10) * 20, i * 0.3, i * 0.17))
		end
		local out = PathCodec.decode(PathCodec.encode(path)) :: { Vector3 }
		expect(#out).to.equal(#path)
		for i, p in path do
			expect(near(out[i], p)).to.equal(true)
		end
	end)

	it("splits huge jumps instead of clipping them", function()
		local path = { Vector3.new(0, 0, 0), Vector3.new(20000, -9000, 0) }
		local out = PathCodec.decode(PathCodec.encode(path)) :: { Vector3 }
		expect(near(out[#out], path[2])).to.equal(true)
	end)

	it("handles every base64 padding length and rejects garbage", function()
		for n = 0, 4 do
			local path = {}
			for i = 1, n do
				table.insert(path, Vector3.new(i, i, i))
			end
			expect(#(PathCodec.decode(PathCodec.encode(path)) :: any)).to.equal(n)
		end
		expect(PathCodec.decode("1:!!!!")).to.equal(nil)
		expect(PathCodec.decode("2:AAAA")).to.equal(nil)
		expect(PathCodec.decode(42)).to.equal(nil)
		expect(PathCodec.decode(PathCodec.encode({ Vector3.one, Vector3.one * 2 }), 1)).to.equal(nil)
	end)
end

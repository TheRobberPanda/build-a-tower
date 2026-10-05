return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ReplayStore = require(game:GetService("ServerScriptService").Server.Lib.ReplayStore)
	local PathCodec = require(ReplicatedStorage.Shared.PathCodec)
	local FakeDataStore = require(script.Parent.FakeDataStore)

	local function new()
		return ReplayStore.new({ store = FakeDataStore.new(), wait = function() end })
	end
	local path = PathCodec.encode({ Vector3.zero, Vector3.new(1, 2, 3) })

	it("keeps only the faster run per racer", function()
		local rs = new()
		rs:save(7, "abc", 1, 20000, path, { 5000 })
		rs:save(7, "abc", 1, 25000, "1:", {})
		local r = rs:get(7, "abc", 1) :: any
		expect(r.ms).to.equal(20000)
		expect(r.splits[1]).to.equal(5000)
		rs:save(7, "abc", 1, 15000, path, {})
		expect((rs:get(7, "abc", 1) :: any).ms).to.equal(15000)
	end)

	it("returns nil for missing or corrupt replays", function()
		local rs = new()
		expect(rs:get(7, "abc", 2)).to.equal(nil)
		rs._deps.store.data[ReplayStore.key(7, "abc", 3)] = { ms = 1, path = "garbage" }
		expect(rs:get(7, "abc", 3)).to.equal(nil)
	end)
end

return function()
	local ServerScriptService = game:GetService("ServerScriptService")
	local TowerStats = require(ServerScriptService.Server.Lib.TowerStats)
	local FakeDataStore = require(script.Parent.FakeDataStore)

	local function new()
		local deps = {
			stats = FakeDataStore.new(),
			popular = FakeDataStore.new(),
			hardest = FakeDataStore.new(),
			wait = function() end,
		}
		return TowerStats.new(deps), deps
	end

	it("labels difficulty from completion rate once there is enough data", function()
		expect(TowerStats.difficulty(5, 0)).to.equal("New")
		expect(TowerStats.difficulty(10, 8)).to.equal("Easy")
		expect(TowerStats.difficulty(10, 4)).to.equal("Medium")
		expect(TowerStats.difficulty(10, 1)).to.equal("Hard")
		expect(TowerStats.difficulty(100, 2)).to.equal("Insane")
		expect(TowerStats.hardScore(5, 0)).to.equal(0)
		expect(TowerStats.hardScore(100, 2) > TowerStats.hardScore(10, 8)).to.equal(true)
	end)

	it("batches counters and keeps the record", function()
		local ts, deps = new()
		for _ = 1, 3 do
			ts:addStart(7, "h1")
		end
		ts:addFinish(7, "h1", 1, 20000)
		ts:addFinish(7, "h1", 2, 15000)
		ts:addLike(7, "h1")
		expect(deps.stats.writes).to.equal(0)
		ts:flush()
		local s = ts:get(7, "h1")
		expect(s.starts).to.equal(3)
		expect(s.finishes).to.equal(2)
		expect(s.likes).to.equal(1)
		expect(s.best).to.equal(15000)
		expect(s.bestBy).to.equal(2)
		expect(deps.popular.data["7"]).to.equal(7)
		ts:addFinish(7, "h1", 3, 30000)
		ts:flush()
		expect(ts:get(7, "h1").best).to.equal(15000)
	end)

	it("resets counters for a new tower version", function()
		local ts = new()
		ts:addStart(7, "h1")
		ts:flush()
		ts:addStart(7, "h2")
		ts:flush()
		expect(ts:get(7, "h2").starts).to.equal(1)
		expect(ts:get(7, "h1").starts).to.equal(0) -- stored record is for h2 now
	end)

	it("keeps pending counts when a flush fails", function()
		local ts, deps = new()
		ts:addStart(7, "h1")
		deps.stats.failNext = 99
		ts:flush()
		deps.stats.failNext = 0
		ts:addStart(7, "h1")
		ts:flush()
		expect(ts:get(7, "h1").starts).to.equal(2)
	end)
end

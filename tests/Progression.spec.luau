return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Config = require(ReplicatedStorage.Shared.Config)
	local Progression = require(ReplicatedStorage.Shared.Progression)
	local CreditStore = require(game:GetService("ServerScriptService").Server.Lib.CreditStore)
	local FakeDataStore = require(script.Parent.FakeDataStore)

	it("levels up on a growing XP curve", function()
		expect(Progression.level(0)).to.equal(1)
		expect(Progression.level(99)).to.equal(1)
		expect(Progression.level(100)).to.equal(2)
		expect(Progression.level(299)).to.equal(2)
		expect(Progression.level(300)).to.equal(3)
		expect(Progression.xpFor(3)).to.equal(300)
		expect(Progression.level(1e12)).to.equal(Config.MAX_LEVEL)
	end)

	it("grows the budget with level up to the cap", function()
		expect(Progression.budget(1)).to.equal(Config.PIECE_BUDGET)
		expect(Progression.budget(2)).to.equal(Config.PIECE_BUDGET + 15)
		expect(Progression.budget(1000)).to.equal(Config.PIECE_BUDGET_MAX)
	end)

	it("credits offline builders, caps bricks per day, and claims once", function()
		local t = 86400 * 100
		local cs = CreditStore.new({
			store = FakeDataStore.new(),
			now = function()
				return t
			end,
			wait = function() end,
		})
		cs:add(7, 50, Config.BRICKS_DAILY_CAP - 10)
		cs:add(7, 50, 100) -- only 10 bricks left today
		local xp, bricks = cs:claim(7)
		expect(xp).to.equal(100)
		expect(bricks).to.equal(Config.BRICKS_DAILY_CAP)
		expect(select(2, cs:claim(7))).to.equal(0)
		cs:add(7, 0, 5) -- still capped today, even after claiming
		expect(select(2, cs:claim(7))).to.equal(0)
		t += 86400
		cs:add(7, 0, 5)
		expect(select(2, cs:claim(7))).to.equal(5)
	end)
end

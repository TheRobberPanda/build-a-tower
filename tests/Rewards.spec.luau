return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Config = require(ReplicatedStorage.Shared.Config)
	local PieceDefs = require(ReplicatedStorage.Shared.PieceDefs)
	local Rewards = require(ReplicatedStorage.Shared.Rewards)

	describe("Rewards", function()
		it("winning and stars raise the odds", function()
			expect(Rewards.chance(true, nil) > Rewards.chance(false, nil)).to.equal(true)
			expect(Rewards.chance(false, 5) > Rewards.chance(false, 1)).to.equal(true)
			expect(Rewards.chance(true, 5) <= 0.95).to.equal(true)
		end)
		it("rolls nothing above the chance, expansions only below the max size", function()
			expect(Rewards.roll(false, nil, {}, 16, 0.99, 0)).to.equal(nil)
			expect(Rewards.roll(false, nil, {}, 16, 0, 0.1)).to.equal("expand")
			local r = Rewards.roll(false, nil, {}, Config.PLOT_CELLS_MAX, 0, 0.1)
			expect(type(r)).to.equal("number")
			expect(PieceDefs.byId[r :: number].asset ~= nil).to.equal(true)
		end)
		it("never gives a decoration you own", function()
			local owned = {}
			for _, def in PieceDefs.list do
				if def.asset and def.id ~= 40 then
					owned["decor_" .. def.id] = true
				end
			end
			expect(Rewards.roll(true, 5, owned, Config.PLOT_CELLS_MAX, 0, 0.99)).to.equal(40)
		end)
		it("gives each course a fixed store decoration", function()
			local a = Rewards.trophyFor("deadbeef12345678-40")
			expect(a).to.equal(Rewards.trophyFor("deadbeef12345678-40"))
			expect(PieceDefs.byId[a].asset ~= nil).to.equal(true)
		end)
	end)
end

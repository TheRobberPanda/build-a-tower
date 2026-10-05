return function()
	local MovementCheck = require(game:GetService("ServerScriptService").Server.Lib.MovementCheck)

	local limits =
		{ walkSpeed = 16, maxRiseSpeed = 60, speedFactor = 1.5, speedSlack = 6, teleportRadius = 10 }
	local o = Vector3.zero

	it("flags hovering but not jumps, falls or pad launches", function()
		local h = {}
		-- normal jump: rises briefly, then falls
		expect(MovementCheck.hover(h, true, 5, 0, false, 1)).to.equal(nil)
		expect(MovementCheck.hover(h, true, 2, 0.2, false, 1)).to.equal(nil)
		expect(MovementCheck.hover(h, true, -3, 0.4, false, 1)).to.equal(nil)
		expect(h.since).to.equal(nil)
		-- hovering in place
		for t = 1, 5 do
			expect(MovementCheck.hover(h, true, 0, t * 0.2, false, 1)).to.equal(nil)
		end
		expect(MovementCheck.hover(h, true, 0, 1.6, false, 1)).to.be.ok()
		-- launched by a pad: allowed
		local p = {}
		for t = 0, 10 do
			expect(MovementCheck.hover(p, true, 2, t * 0.2, true, 1)).to.equal(nil)
		end
		-- standing: never
		expect(MovementCheck.hover({ since = 0 }, false, 0, 5, false, 1)).to.equal(nil)
	end)

	it("allows walking and normal jumps", function()
		local a = MovementCheck.newAllowance()
		expect(MovementCheck.check(o, Vector3.new(3, 0, 0), 0.2, 1, a, limits)).to.equal(nil)
		expect(MovementCheck.check(o, Vector3.new(0, 10, 0), 0.2, 1, a, limits)).to.equal(nil)
	end)

	it("flags speed hacks and flying up", function()
		local a = MovementCheck.newAllowance()
		expect(MovementCheck.check(o, Vector3.new(10, 0, 0), 0.2, 1, a, limits)).to.be.ok()
		expect(MovementCheck.check(o, Vector3.new(0, 20, 0), 0.2, 1, a, limits)).to.be.ok()
	end)

	it("allows falling fast", function()
		local a = MovementCheck.newAllowance()
		expect(MovementCheck.check(o, Vector3.new(0, -50, 0), 0.2, 1, a, limits)).to.equal(nil)
	end)

	it("allows a registered jump pad launch only within its window", function()
		local a = MovementCheck.newAllowance()
		a.launchSpeed = 120
		a.launchUntil = 2
		expect(MovementCheck.check(o, Vector3.new(0, 30, 0), 0.2, 1, a, limits)).to.equal(nil)
		expect(MovementCheck.check(o, Vector3.new(0, 30, 0), 0.2, 3, a, limits)).to.be.ok()
	end)

	it("allows a registered teleport once, and only to its destination", function()
		local a = MovementCheck.newAllowance()
		a.teleportTo = Vector3.new(0, 100, 0)
		a.teleportUntil = 5
		expect(MovementCheck.check(o, Vector3.new(200, 0, 0), 0.2, 1, a, limits)).to.be.ok()
		expect(MovementCheck.check(o, Vector3.new(0, 102, 0), 0.2, 1, a, limits)).to.equal(nil)
		expect(MovementCheck.check(o, Vector3.new(0, 102, 0), 0.2, 1, a, limits)).to.be.ok()
	end)
end

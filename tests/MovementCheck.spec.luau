return function()
	local MovementCheck = require(game:GetService("ServerScriptService").Server.Lib.MovementCheck)

	local limits =
		{ walkSpeed = 16, maxRiseSpeed = 60, speedFactor = 1.5, speedSlack = 6, teleportRadius = 10 }
	local o = Vector3.zero

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

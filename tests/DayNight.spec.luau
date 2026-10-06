--!strict
return function()
	local DayNightService =
		require(game:GetService("ServerScriptService").Server.Services.DayNightService) :: any

	it("treats 6:00-17:59 as day", function()
		expect(DayNightService.isDay(5.99)).to.equal(false)
		expect(DayNightService.isDay(6)).to.equal(true)
		expect(DayNightService.isDay(17.99)).to.equal(true)
		expect(DayNightService.isDay(18)).to.equal(false)
	end)
end

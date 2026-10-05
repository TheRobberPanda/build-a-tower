return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Config = require(ReplicatedStorage.Shared.Config)
	local Events = require(ReplicatedStorage.Shared.Events)

	it("names monthly seasons in UTC", function()
		expect(Events.season(1791763200)).to.equal("202610") -- 2026-10-12
		expect(Events.season(1793750400)).to.equal("202611") -- 2026-11-04
	end)

	it("limits event pieces to their window", function()
		local window = Config.EVENT_PIECES[18]
		expect(Events.pieceAvailable(18, window[1] - 1)).to.equal(false)
		expect(Events.pieceAvailable(18, window[1])).to.equal(true)
		expect(Events.pieceAvailable(18, window[2])).to.equal(false)
		expect(Events.pieceAvailable(1, 0)).to.equal(true) -- normal pieces always
	end)

	it("moves a contest from entries to voting to closed", function()
		local c = Config.CONTESTS[1]
		expect(select(2, Events.contest(c.starts))).to.equal("entries")
		expect(select(2, Events.contest(c.votingFrom))).to.equal("voting")
		expect(Events.contest(c.ends)).to.equal(nil)
	end)
end

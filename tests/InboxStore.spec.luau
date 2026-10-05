return function()
	local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
	local InboxStore = require(game:GetService("ServerScriptService").Server.Lib.InboxStore)
	local FakeDataStore = require(script.Parent.FakeDataStore)

	it("delivers messages once, newest last, capped", function()
		local inbox = InboxStore.new({
			store = FakeDataStore.new(),
			now = function()
				return 1
			end,
			wait = function() end,
		})
		for i = 1, Config.INBOX_MAX + 3 do
			inbox:push(5, "msg " .. i)
		end
		local got = inbox:take(5)
		expect(#got).to.equal(Config.INBOX_MAX)
		expect(got[#got].text).to.equal("msg " .. (Config.INBOX_MAX + 3))
		expect(#inbox:take(5)).to.equal(0)
	end)
end

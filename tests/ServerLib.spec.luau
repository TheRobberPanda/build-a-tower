return function()
	local ServerScriptService = game:GetService("ServerScriptService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Lib = ServerScriptService.Server.Lib
	local Config = require(ReplicatedStorage.Shared.Config)
	local TowerCodec = require(ReplicatedStorage.Shared.TowerCodec)
	local ProfileStore = require(Lib.ProfileStore)
	local PublishedStore = require(Lib.PublishedStore)
	local RateLimiter = require(Lib.RateLimiter)
	local Retry = require(Lib.Retry)
	local SessionLock = require(Lib.SessionLock)
	local FakeDataStore = require(script.Parent.FakeDataStore)

	local clock = 1000
	local function now()
		return clock
	end
	local function noWait() end

	local function newProfiles(store, jobId)
		return ProfileStore.new({ store = store, jobId = jobId, now = now, wait = noWait })
	end

	describe("Retry", function()
		it("retries then succeeds, with capped backoff", function()
			local waits = {}
			local n = 0
			local ok, v = Retry.call({
				attempts = 5,
				baseDelay = 1,
				maxDelay = 4,
				wait = function(s)
					table.insert(waits, s)
				end,
			}, function()
				n += 1
				if n < 4 then
					error("boom")
				end
				return "done"
			end)
			expect(ok).to.equal(true)
			expect(v).to.equal("done")
			expect(table.concat(waits, ",")).to.equal("1,2,4")
		end)
		it("gives up after the last attempt", function()
			local ok = Retry.call({ attempts = 2, baseDelay = 1, maxDelay = 1, wait = noWait }, function()
				error("always")
			end)
			expect(ok).to.equal(false)
		end)
	end)

	describe("SessionLock", function()
		it("blocks fresh foreign locks and allows stale ones", function()
			expect(SessionLock.canAcquire({ j = "A", t = 100 }, "B", 110, 600)).to.equal(false)
			expect(SessionLock.canAcquire({ j = "A", t = 100 }, "B", 800, 600)).to.equal(true)
			expect(SessionLock.canAcquire({ j = "A", t = 100 }, "A", 110, 600)).to.equal(true)
			expect(SessionLock.canAcquire(nil, "B", 0, 600)).to.equal(true)
		end)
	end)

	describe("RateLimiter", function()
		it("allows a burst then refills", function()
			local t = 0
			local rl = RateLimiter.new(2, 1, function()
				return t
			end)
			expect(rl:allow("p")).to.equal(true)
			expect(rl:allow("p")).to.equal(true)
			expect(rl:allow("p")).to.equal(false)
			t = 1
			expect(rl:allow("p")).to.equal(true)
		end)
	end)

	describe("ProfileStore", function()
		beforeEach(function()
			clock = 1000
		end)

		it("creates a default profile and round-trips a save", function()
			local store = FakeDataStore.new()
			local ps = newProfiles(store, "A")
			local data = ps:load(1) :: any
			expect(data).to.be.ok()
			table.insert(data.tower.pieces, { t = 1, x = 0, y = 0, z = 0, r = 0 })
			expect(ps:save(1, data, true)).to.equal(true)
			local again = newProfiles(store, "B"):load(1) :: any
			expect(#again.tower.pieces).to.equal(1)
		end)

		it("refuses to load while another server holds a fresh lock", function()
			local store = FakeDataStore.new()
			newProfiles(store, "A"):load(1)
			local data, err = newProfiles(store, "B"):load(1)
			expect(data).to.equal(nil)
			expect(err).to.equal("locked")
		end)

		it("takes over a stale lock", function()
			local store = FakeDataStore.new()
			newProfiles(store, "A"):load(1)
			clock += Config.LOCK_STALE_SECONDS + 1
			expect(newProfiles(store, "B"):load(1)).to.be.ok()
		end)

		it("does not save after losing the lock", function()
			local store = FakeDataStore.new()
			local a = newProfiles(store, "A")
			local data = a:load(1) :: any
			clock += Config.LOCK_STALE_SECONDS + 1
			local bData = newProfiles(store, "B"):load(1) :: any
			table.insert(bData.tower.pieces, { t = 1, x = 0, y = 0, z = 0, r = 0 })
			local ok, err = a:save(1, data, false)
			expect(ok).to.equal(false)
			expect(err).to.equal("lost")
		end)

		it("releases the lock on final save", function()
			local store = FakeDataStore.new()
			local a = newProfiles(store, "A")
			a:save(1, a:load(1) :: any, true)
			expect(store.data.u_1.lock).to.equal(nil)
			expect(newProfiles(store, "B"):load(1)).to.be.ok()
		end)

		it("reports a datastore failure instead of a fresh profile", function()
			local store = FakeDataStore.new()
			store.failNext = 100
			local data, err = newProfiles(store, "A"):load(1)
			expect(data).to.equal(nil)
			expect(err).to.equal("datastore")
		end)

		it("survives transient failures", function()
			local store = FakeDataStore.new()
			store.failNext = 2
			expect(newProfiles(store, "A"):load(1)).to.be.ok()
		end)

		it("will not touch data written by a newer schema", function()
			local store = FakeDataStore.new()
			store.data.u_1 = { v = Config.SCHEMA_VERSION + 1, data = { secret = true } }
			local data, err = newProfiles(store, "A"):load(1)
			expect(data).to.equal(nil)
			expect(err).to.equal("newer")
			expect(store.data.u_1.data.secret).to.equal(true)
		end)

		it("quarantines the original when bad pieces are dropped", function()
			local store = FakeDataStore.new()
			store.data.u_1 = {
				v = 1,
				data = {
					tower = {
						v = 1,
						pieces = {
							{ t = 1, x = 0, y = 0, z = 0, r = 0 },
							{ t = 99, x = 0, y = 0, z = 0, r = 0 },
						},
					},
				},
			}
			local data = newProfiles(store, "A"):load(1) :: any
			expect(#data.tower.pieces).to.equal(1)
			expect(#store.data.u_1.quarantine.tower.pieces).to.equal(2)
		end)

		it("drops verification that no longer matches the tower", function()
			local store = FakeDataStore.new()
			store.data.u_1 = { v = 1, data = { tower = { v = 1, pieces = {} }, verifiedHash = "stale" } }
			local data = newProfiles(store, "A"):load(1) :: any
			expect(data.verifiedHash).to.equal(nil)
		end)
	end)

	describe("PublishedStore", function()
		local function newPublished()
			local boards = {}
			local deps = {
				published = FakeDataStore.new(),
				browse = FakeDataStore.new(),
				leaderboard = function(name)
					boards[name] = boards[name] or FakeDataStore.new()
					return boards[name]
				end,
				now = now,
				wait = noWait,
			}
			return PublishedStore.new(deps), deps
		end
		local tower = {
			v = 1,
			pieces = { { t = 1, x = 0, y = 0, z = 0, r = 0 }, { t = 8, x = 0, y = 1, z = 0, r = 0 } },
		}

		it("publishes, lists and reads back a tower", function()
			local ps = newPublished()
			local ok, hash = ps:publish(7, "Spire", tower)
			expect(ok).to.equal(true)
			expect(hash).to.equal(TowerCodec.hash(tower))
			local page = ps:browsePage(10) :: any
			expect(page[1].key).to.equal("7")
			expect((ps:get(7) :: any).name).to.equal("Spire")
		end)

		it("rejects towers without a finish", function()
			local ps = newPublished()
			expect(ps:publish(7, "x", { v = 1, pieces = {} })).to.equal(false)
		end)

		it("keeps only a racer's best time and sorts ascending", function()
			local ps = newPublished()
			local h = TowerCodec.hash(tower)
			expect(ps:submitTime(7, h, 1, 20000)).to.equal(true)
			expect(ps:submitTime(7, h, 1, 25000)).to.equal(false)
			expect(ps:submitTime(7, h, 1, 15000)).to.equal(true)
			expect(ps:submitTime(7, h, 2, 18000)).to.equal(true)
			local top = ps:topTimes(7, h, 10) :: any
			expect(top[1].value).to.equal(15000)
			expect(top[2].value).to.equal(18000)
		end)

		it("rejects implausible times", function()
			local ps = newPublished()
			local h = TowerCodec.hash(tower)
			expect(ps:submitTime(7, h, 1, 10)).to.equal(false)
			expect(ps:submitTime(7, h, 1, 0 / 0)).to.equal(false)
			expect(ps:submitTime(7, h, 1, 1500.5)).to.equal(false)
		end)
	end)
end

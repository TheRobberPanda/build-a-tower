return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Config = require(ReplicatedStorage.Shared.Config)
	local TowerCodec = require(ReplicatedStorage.Shared.TowerCodec)

	local function p(t, x, y, z, r, props)
		return { t = t, x = x, y = y, z = z, r = r or 0, p = props }
	end

	describe("validatePiece", function()
		it("accepts a valid block", function()
			expect(TowerCodec.validatePiece(p(1, 0, 0, 0))).to.be.ok()
		end)
		it("rejects unknown types, bad rotation, NaN, inf, fractions", function()
			expect(TowerCodec.validatePiece(p(99, 0, 0, 0))).never.to.be.ok()
			expect(TowerCodec.validatePiece(p(1, 0, 0, 0, 4))).never.to.be.ok()
			expect(TowerCodec.validatePiece(p(1, 0 / 0, 0, 0))).never.to.be.ok()
			expect(TowerCodec.validatePiece(p(1, math.huge, 0, 0))).never.to.be.ok()
			expect(TowerCodec.validatePiece(p(1, 0.5, 0, 0))).never.to.be.ok()
			expect(TowerCodec.validatePiece("x")).never.to.be.ok()
		end)
		it("keeps pieces out of the frame's pillars and floors, but not its hollow middle", function()
			local c = Config.CORE
			local r = { core = true }
			expect(TowerCodec.validatePiece(p(1, c.x0, 0, c.z0), r)).to.equal(nil) -- pillar
			expect(TowerCodec.validatePiece(p(1, c.x0 + 2, c.level - 1, c.z0 + 2), r)).to.equal(nil) -- floor
			expect(TowerCodec.validatePiece(p(1, c.x0 + 2, 0, c.z0 + 2), r)).to.be.ok() -- inside, ground level
			expect(TowerCodec.validatePiece(p(1, c.x0 + 2, c.level, c.z0 + 2), r)).to.be.ok() -- standing on a floor
			expect(TowerCodec.validatePiece(p(1, c.x0 - 1, 3, c.z0), r)).to.be.ok() -- next to a pillar
			expect(TowerCodec.validatePiece(p(1, c.x0, c.height, c.z0), r)).to.be.ok() -- above the roof
			expect(TowerCodec.validatePiece(p(1, c.x0, 0, c.z0))).to.be.ok() -- home island: no frame
		end)
		it("grows the bounds with the island size", function()
			local edge = Config.PLOT_CELLS_X
			expect(TowerCodec.validatePiece(p(1, edge, 0, 0))).never.to.be.ok()
			expect(TowerCodec.validatePiece(p(1, edge, 0, 0), { size = edge + 2 })).to.be.ok()
		end)

		it("checks bounds using the rotated footprint", function()
			local edge = Config.PLOT_CELLS_X - 1
			-- LongRamp is 1x2x4: fits at the x edge unrotated, not when rotated
			expect(TowerCodec.validatePiece(p(21, edge, 0, 0, 0))).to.be.ok()
			expect(TowerCodec.validatePiece(p(21, edge, 0, 0, 1))).never.to.be.ok()
			expect(TowerCodec.validatePiece(p(1, 0, Config.PLOT_CELLS_Y, 0))).never.to.be.ok()
		end)
		it("measures support: grounded, overhang, floating", function()
			local x, z = Config.PLOT_CELLS_X - 4, Config.PLOT_CELLS_Z - 4
			local d = TowerCodec.support({
				p(1, x, 0, z), -- on the ground
				p(1, x, 1, z), -- stacked
				p(1, x + 1, 1, z), -- one hop out
				p(1, x + 2, 1, z), -- two hops out
				p(1, x, 5, z), -- floating
				p(16, x, 9, z), -- floating lamp: decor never collapses
			})
			expect(d[1]).to.equal(0)
			expect(d[2]).to.equal(0)
			expect(d[3]).to.equal(1)
			expect(d[4]).to.equal(2)
			expect(d[5]).to.equal(math.huge)
			expect(d[6]).to.equal(0)
		end)
		it("validates props and fills defaults", function()
			expect(TowerCodec.validatePiece(p(4, 0, 0, 0, 0, { power = 9 }))).never.to.be.ok()
			expect(TowerCodec.validatePiece(p(1, 0, 0, 0, 0, { power = 1 }))).never.to.be.ok()
			local pad = TowerCodec.validatePiece(p(4, 0, 0, 0))
			expect(pad and pad.p and pad.p.power).to.equal(1)
		end)
	end)

	describe("placement", function()
		it("rejects overlap including multi-cell pieces", function()
			local s = TowerCodec.newPlaceState()
			local plat = TowerCodec.validatePiece(p(2, 0, 0, 0)) :: any -- 2x1x2
			TowerCodec.add(s, plat)
			expect(TowerCodec.canAdd(s, TowerCodec.validatePiece(p(1, 1, 0, 1)) :: any)).to.equal(false)
			expect(TowerCodec.canAdd(s, TowerCodec.validatePiece(p(1, 2, 0, 0)) :: any)).to.equal(true)
			TowerCodec.remove(s, plat)
			expect(TowerCodec.canAdd(s, TowerCodec.validatePiece(p(1, 1, 0, 1)) :: any)).to.equal(true)
		end)
		it("allows only one finish", function()
			local s = TowerCodec.newPlaceState()
			TowerCodec.add(s, TowerCodec.validatePiece(p(8, 0, 0, 0)) :: any)
			expect(TowerCodec.canAdd(s, TowerCodec.validatePiece(p(8, 5, 0, 0)) :: any)).to.equal(false)
		end)
	end)

	describe("sanitize", function()
		it("drops bad pieces and counts them, including holes", function()
			-- selene: allow(mixed_table)
			local tower, dropped = TowerCodec.sanitize({
				v = 1,
				pieces = { p(1, 0, 0, 0), p(99, 1, 0, 0), p(1, 0, 0, 0), [5] = p(1, 3, 0, 0) },
			})
			expect(tower and #tower.pieces).to.equal(1)
			expect(dropped).to.equal(3)
		end)
		it("uses the given budget and keeps decorations outside it", function()
			local state = TowerCodec.newPlaceState(2)
			TowerCodec.add(state, p(1, 0, 0, 0))
			TowerCodec.add(state, p(1, 1, 0, 0))
			expect(TowerCodec.canAdd(state, p(1, 2, 0, 0))).to.equal(false)
			expect(TowerCodec.canAdd(state, p(15, 2, 0, 0))).to.equal(true) -- plant
			TowerCodec.add(state, p(15, 2, 0, 0))
			TowerCodec.remove(state, p(15, 2, 0, 0))
			expect(state.decor).to.equal(0)
			expect(state.total).to.equal(2)
		end)
		it("trims towers over budget", function()
			local pieces = {}
			for i = 0, Config.PIECE_BUDGET_STORED + 9 do
				table.insert(pieces, p(1, i % 16, i // 256, (i // 16) % 16))
			end
			local tower, dropped = TowerCodec.sanitize({ v = 1, pieces = pieces })
			expect(tower and #tower.pieces).to.equal(Config.PIECE_BUDGET_STORED)
			expect(dropped).to.equal(10)
		end)
		it("refuses data from a newer schema", function()
			expect(TowerCodec.sanitize({ v = Config.SCHEMA_VERSION + 1, pieces = {} })).to.equal(nil)
		end)
		it("treats garbage as empty", function()
			local tower = TowerCodec.sanitize(nil)
			expect(tower and #tower.pieces).to.equal(0)
		end)
	end)

	describe("validate (publish)", function()
		it("requires a finish", function()
			expect(TowerCodec.validate({ v = 1, pieces = { p(1, 0, 0, 0) } })).to.equal(false)
			expect(TowerCodec.validate({ v = 1, pieces = { p(1, 0, 0, 0), p(8, 0, 1, 0) } })).to.equal(true)
		end)
	end)

	describe("hash", function()
		local a = { v = 1, pieces = { p(1, 0, 0, 0), p(4, 1, 0, 0, 0, { power = 2 }) } }
		it("ignores piece order", function()
			local b = { v = 1, pieces = { a.pieces[2], a.pieces[1] } }
			expect(TowerCodec.hash(a)).to.equal(TowerCodec.hash(b))
		end)
		it("changes on any edit", function()
			local h = TowerCodec.hash(a)
			local moved = { v = 1, pieces = { p(1, 0, 0, 1), a.pieces[2] } }
			local rotated = { v = 1, pieces = { p(1, 0, 0, 0, 1), a.pieces[2] } }
			local prop = { v = 1, pieces = { a.pieces[1], p(4, 1, 0, 0, 0, { power = 3 }) } }
			expect(TowerCodec.hash(moved)).never.to.equal(h)
			expect(TowerCodec.hash(rotated)).never.to.equal(h)
			expect(TowerCodec.hash(prop)).never.to.equal(h)
			expect(TowerCodec.hash({ v = 1, pieces = { a.pieces[1] } })).never.to.equal(h)
		end)
	end)
end

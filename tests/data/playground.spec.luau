--!strict
local Playground = Harness.load("src/shared/data/playground")

describe("playground data", function()
	it("is the 400-stud field with the real ceiling (D-013)", function()
		expect(Playground.fieldRadius).toBe(200)
		expect(Playground.ceilingHeight).toBe(350)
		expect(Playground.killVolume.y).toBe(-50)
		expect(Playground.rim.cloudRingDrop).toBe(200)
		expect(Playground.rim.pillarDistance).toBeGreaterThan(Playground.fieldRadius)
		expect(Playground.rim.pillarHeight).toBeGreaterThanOrEqual(Playground.ceilingHeight)
		expect(Playground.lightingPreset).toBe("Floor1")
		expect(Playground.respawnSeconds).toBe(20)
	end)

	it("spawns three boar packs and two kobolds inside their rings", function()
		local counts = {}
		for _, spawn in Playground.spawns do
			counts[spawn.enemy] = (counts[spawn.enemy] or 0) + 1
			local distance = Playground.distanceFromCenter(spawn.position)
			local ring = Playground.ringFor(spawn.enemy)
			expect(ring).toBeTruthy()
			expect(distance).toBeGreaterThanOrEqual(ring.min)
			expect(distance).toBeLessThanOrEqual(ring.max)
			expect(distance).toBeLessThan(Playground.fieldRadius)
			expect(spawn.position[2]).toBe(0)
			expect(spawn.packSize.min).toBeGreaterThanOrEqual(1)
			expect(spawn.packSize.max).toBeGreaterThanOrEqual(spawn.packSize.min)
		end
		expect(counts.FrenzyBoar).toBe(3)
		expect(counts.KoboldAxeman).toBe(2)
		expect(Playground.spawnRings.FrenzyBoar).toEqual({ min = 40, max = 120 })
		expect(Playground.spawnRings.KoboldAxeman).toEqual({ min = 60, max = 100 })
		expect(Playground.ringFor("DireWolf")).toBeNil()
	end)

	it("boar packs can be pairs; kobolds spawn alone", function()
		for _, spawn in Playground.spawns do
			if spawn.enemy == "FrenzyBoar" then
				expect(spawn.packSize).toEqual({ min = 1, max = 2 })
			else
				expect(spawn.packSize).toEqual({ min = 1, max = 1 })
			end
		end
	end)

	it("the loadout is a level-1 Trialist who can use the four Phase 0 Arts", function()
		local loadout = Playground.loadout
		expect(loadout.weapon).toBe("TrialistSword")
		expect(loadout.level).toBe(1)
		expect(loadout.str).toBe(10)
		expect(loadout.agi).toBe(10)
		expect(loadout.proficiency.OneHandedSword).toBe(150)
		expect(loadout.armor.Chest).toBe("TrialistTunic")
		expect(loadout.armor.Boots).toBe("TrialistBoots")
		expect(loadout.artSlots).toEqual({
			"OneHandedSword.Horizontal",
			"OneHandedSword.Vertical",
			"OneHandedSword.RisingArc",
			"OneHandedSword.SharpNail",
		})
	end)

	it("spawns keep clear of every living fighter (D-170)", function()
		local spacing = Playground.spawnSpacing
		expect(spacing.minStuds).toBe(12) -- two boars, 5.6 studs from root to snout, at any facing
		expect(spacing.tries).toBeGreaterThanOrEqual(1)
		expect(spacing.widenStuds).toBeGreaterThan(0)
		-- The widest disc reaches past one spacing, so a second packmate always has room.
		expect(Playground.spawnScatterRadius + spacing.widenings * spacing.widenStuds).toBeGreaterThanOrEqual(
			spacing.minStuds
		)
	end)

	it("measures distance on the field plane", function()
		expect(Playground.distanceFromCenter({ 3, 50, 4 })).toBeCloseTo(5)
	end)
end)

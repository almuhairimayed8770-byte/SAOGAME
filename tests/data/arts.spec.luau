--!strict
local Arts = Harness.load("src/shared/data/arts")

-- Section 8 rows: unlock, hits, startup, total, postMotion (plus root motion where the note gives it).
local SECTION_8 = {
	["OneHandedSword.Horizontal"] = { 0, 1, 0.25, 0.6, 0.4 },
	["OneHandedSword.Vertical"] = { 0, 1, 0.25, 0.6, 0.4 },
	["OneHandedSword.RisingArc"] = { 50, 2, 0.3, 0.9, 0.5 },
	["OneHandedSword.SharpNail"] = { 150, 3, 0.3, 1.1, 0.6 },
	["OneHandedSword.SonicLeap"] = { 250, 1, 0.35, 0.8, 0.6, 14 },
	["OneHandedSword.LanceThrust"] = { 400, 1, 0.5, 0.9, 0.9, 6 },
	["OneHandedSword.HowlingOctave"] = { 650, 8, 0.4, 2.2, 1.2 },
	["OneHandedSword.NovaAscension"] = { 900, 10, 0.5, 2.8, 1.4 },
	["Rapier.Linear"] = { 0, 1, 0.22, 0.5, 0.35, 6 },
	["Rapier.Oblique"] = { 50, 1, 0.22, 0.5, 0.35, 6 },
	["Rapier.QuadruplePain"] = { 150, 4, 0.3, 1.0, 0.6 },
	["Rapier.FlashingPenetrator"] = { 350, 1, 0.4, 0.7, 0.8, 20 },
	["Rapier.Neutron"] = { 900, 5, 0.45, 1.5, 1.2 },
	["TwoHandedSword.Avalanche"] = { 0, 1, 0.4, 1.0, 0.7 },
	["TwoHandedSword.TitanPress"] = { 700, 4, 0.6, 2.0, 1.3 },
	["TwoHandedSword.RagnarokWheel"] = { 900, 6, 0.6, 2.6, 1.6 },
	["Katana.IaiCut"] = { 0, 1, 0.2, 0.45, 0.5 },
	["Katana.ScarletFan"] = { 900, 7, 0.5, 2.2, 1.4 },
	["Dagger.RapidBite"] = { 0, 2, 0.2, 0.5, 0.3 },
	["Dagger.ThousandCuts"] = { 900, 12, 0.4, 2.4, 1.3 },
	["Spear.Pierce"] = { 0, 1, 0.3, 0.7, 0.5 },
	["Spear.SkewerTempest"] = { 900, 7, 0.5, 2.4, 1.4 },
	["Axe.Cleave"] = { 0, 1, 0.35, 0.8, 0.6 },
	["Mace.Cleave"] = { 0, 1, 0.35, 0.8, 0.6 },
	["Axe.DoomSpiral"] = { 900, 5, 0.6, 2.4, 1.5 },
	["TwinFang.DoubleCircular"] = { 0, 2, 0.3, 0.7, 0.3 },
	["TwinFang.CrossBlock"] = { 100, 0, 0.15, 0.4, 0.2 },
	["TwinFang.TwinLance"] = { 550, 2, 0.4, 0.9, 0.7, 8 },
	["TwinFang.MeteorCascade"] = { 500, 16, 0.5, 4.2, 1.6 },
	["TwinFang.UmbralReign"] = { 1000, 27, 0.6, 7.0, 2.4 },
}

describe("arts data", function()
	it("matches the section 8 table on every spot-checked row", function()
		for id, row in SECTION_8 do
			local art = Arts.byId(id)
			expect(art).toBeTruthy()
			expect(art.unlock).toBe(row[1])
			expect(art.hits).toBe(row[2])
			expect(art.startup).toBeCloseTo(row[3], 1e-9)
			expect(art.total).toBeCloseTo(row[4], 1e-9)
			expect(art.postMotion).toBeCloseTo(row[5], 1e-9)
			if row[6] ~= nil then
				expect(art.rootMotion).toBe(row[6])
			end
		end
	end)

	it("Meteor Cascade is 16 hits over 4.2 s with a 1.6 s lock, Umbral Reign 27 over 7.0 s with 2.4 s", function()
		local meteor = Arts.byId("TwinFang.MeteorCascade")
		expect(meteor.hits).toBe(16)
		expect(meteor.total).toBe(4.2)
		expect(meteor.postMotion).toBe(1.6)
		expect(meteor.ultimate).toBe(true)
		local umbral = Arts.byId("TwinFang.UmbralReign")
		expect(umbral.hits).toBe(27)
		expect(umbral.total).toBe(7.0)
		expect(umbral.postMotion).toBe(2.4)
		expect(umbral.unlock).toBe(1000)
	end)

	it("holds every category with the expected row counts", function()
		expect(Arts.count()).toBe(70)
		expect(Arts.count("OneHandedSword")).toBe(8)
		expect(Arts.count("Rapier")).toBe(7)
		expect(Arts.count("TwoHandedSword")).toBe(6)
		expect(Arts.count("Katana")).toBe(6)
		expect(Arts.count("Dagger")).toBe(6)
		expect(Arts.count("Spear")).toBe(5)
		expect(Arts.count("Axe")).toBe(5)
		expect(Arts.count("Mace")).toBe(5)
		expect(Arts.count("TwinFang")).toBe(7)
		expect(Arts.count("MartialArts")).toBe(5)
		expect(Arts.count("Shield")).toBe(5)
		expect(Arts.count("AegisBlade")).toBe(5)
		expect(#Arts.weapons()).toBe(12)
	end)

	it("ids, names and clips follow the naming rule", function()
		for key, art in Arts.rows do
			expect(art.id).toBe(key)
			local bare = art.name:gsub(" ", "")
			expect(art.id).toBe(art.weapon .. "." .. bare)
			expect(art.clip).toBe("player/" .. art.weapon .. "/" .. bare)
		end
		expect(Arts.byId("OneHandedSword.SharpNail").clip).toBe("player/OneHandedSword/SharpNail")
	end)

	it("every row keeps startup inside total and locks after a hit", function()
		for _, art in Arts.rows do
			expect(art.startup).toBeGreaterThan(0)
			expect(art.startup).toBeLessThanOrEqual(art.total)
			expect(art.hits).toBeGreaterThanOrEqual(0)
			if art.hits > 0 then
				expect(art.postMotion).toBeGreaterThan(0)
				expect(art.multiplier).toBeGreaterThan(0)
			else
				expect(art.effect).toBe("Guard")
			end
		end
	end)

	it("Axe and Mace share the section 8 rows", function()
		for _, axeArt in Arts.list("Axe") do
			local maceArt = Arts.byId("Mace." .. axeArt.name:gsub(" ", ""))
			expect(maceArt).toBeTruthy()
			expect(maceArt.unlock).toBe(axeArt.unlock)
			expect(maceArt.hits).toBe(axeArt.hits)
			expect(maceArt.total).toBe(axeArt.total)
			expect(maceArt.gaugeDamage).toBe(axeArt.gaugeDamage)
		end
	end)

	it("lists a weapon's Arts sorted by unlock and filters by proficiency", function()
		local list = Arts.list("OneHandedSword")
		expect(#list).toBe(8)
		for index = 2, #list do
			expect(list[index].unlock).toBeGreaterThanOrEqual(list[index - 1].unlock)
		end
		expect(list[1].name).toBe("Horizontal")
		expect(list[2].name).toBe("Vertical")
		expect(list[8].name).toBe("Nova Ascension")

		expect(#Arts.forProficiency("OneHandedSword", 0)).toBe(2)
		expect(#Arts.forProficiency("OneHandedSword", 149)).toBe(3)
		expect(#Arts.forProficiency("OneHandedSword", 150)).toBe(4)
		expect(#Arts.forProficiency("OneHandedSword", 1000)).toBe(8)
		expect(#Arts.forProficiency("TwinFang", 500)).toBe(5)
		expect(#Arts.forProficiency("TwinFang", 1000)).toBe(7)
	end)

	it("returns nil for unknown ids and does not leak its cache", function()
		expect(Arts.byId("OneHandedSword.Nope")).toBeNil()
		expect(Arts.byId("")).toBeNil()
		local first = Arts.list("Rapier")
		table.remove(first, 1)
		expect(#Arts.list("Rapier")).toBe(7)
	end)

	it(
		"scales damage with unlock: a tier-1 hit is 1.0, combos split a bigger total, ultimates are the biggest",
		function()
			expect(Arts.byId("OneHandedSword.Horizontal").multiplier).toBe(1.0)
			expect(Arts.byId("OneHandedSword.SharpNail").multiplier).toBeLessThan(1.0)
			local function totalOf(id)
				local art = Arts.byId(id)
				return art.hits * art.multiplier
			end
			expect(totalOf("OneHandedSword.SharpNail")).toBeGreaterThan(totalOf("OneHandedSword.Horizontal"))
			expect(totalOf("OneHandedSword.HowlingOctave")).toBeGreaterThan(totalOf("OneHandedSword.SharpNail"))
			expect(totalOf("OneHandedSword.NovaAscension")).toBeGreaterThan(totalOf("OneHandedSword.HowlingOctave"))
			for _, weapon in Arts.weapons() do
				local best = 0
				local ultimateTotal = 0
				for _, art in Arts.list(weapon) do
					best = math.max(best, art.hits * art.multiplier)
					if art.ultimate then
						ultimateTotal = math.max(ultimateTotal, art.hits * art.multiplier)
					end
				end
				expect(ultimateTotal).toBeCloseTo(best, 1e-9)
			end
		end
	)

	it("marks gauge-heavy Arts", function()
		expect(Arts.byId("OneHandedSword.Vertical").gaugeDamage).toBeGreaterThan(
			Arts.byId("OneHandedSword.Horizontal").gaugeDamage
		)
		expect(Arts.byId("Axe.Cleave").gaugeDamage).toBeGreaterThanOrEqual(40)
		local titan = Arts.byId("TwoHandedSword.TitanPress")
		for _, art in Arts.list("TwoHandedSword") do
			expect(art.gaugeDamage).toBeLessThanOrEqual(titan.gaugeDamage)
		end
		expect(Arts.byId("TwinFang.CrossBlock").gaugeDamage).toBe(0)
	end)

	it("carries the preconditions the notes imply", function()
		expect(Arts.byId("OneHandedSword.SonicLeap").preconditions).toEqual({ "Moving" })
		expect(Arts.byId("Rapier.FlashingPenetrator").preconditions).toEqual({ "Moving" })
		expect(Arts.byId("Katana.Tsujikaze").preconditions).toEqual({ "Moving" })
		expect(Arts.byId("Katana.IaiCut").preconditions).toEqual({ "Standing" })
		expect(Arts.byId("MartialArts.FallingComet").preconditions).toEqual({ "Airborne" })
		expect(Arts.byId("AegisBlade.VowStrike").preconditions).toEqual({ "AfterParry" })
		expect(Arts.byId("OneHandedSword.Horizontal").preconditions).toBeNil()
		expect(Arts.allowedFrom(Arts.byId("OneHandedSword.Horizontal"), "Airborne")).toBe(true)
		expect(Arts.allowedFrom(Arts.byId("OneHandedSword.SonicLeap"), "Standing")).toBe(false)
		expect(Arts.allowedFrom(Arts.byId("OneHandedSword.SonicLeap"), "Moving")).toBe(true)
	end)

	it("applies the statuses from the notes", function()
		expect(Arts.byId("Rapier.QuadruplePain").status).toBe("Bleed")
		expect(Arts.byId("Dagger.VenomFang").status).toBe("Poison")
		expect(Arts.byId("Rapier.Crucifixion").status).toBe("Stun")
		expect(Arts.byId("Axe.SkullCrack").status).toBe("Stun")
		expect(Arts.byId("OneHandedSword.Horizontal").status).toBeNil()
	end)

	it("proficiency gain falls from 3 to 1 across the bar and the Twin Fang rules are data", function()
		expect(Arts.proficiencyGain(0)).toBe(3)
		expect(Arts.proficiencyGain(500)).toBe(2)
		expect(Arts.proficiencyGain(1000)).toBe(1)
		expect(Arts.proficiencyGain(5000)).toBe(1)
		expect(Arts.rules.twinFangActivationHold).toBe(0.2)
		expect(Arts.rules.twinFangGaugeMultiplier).toBe(2.5)
		expect(Arts.rules.proficiencyPerParry).toBe(2)
	end)
end)

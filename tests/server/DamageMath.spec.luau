local DamageMath = Harness.load("src/server/combat/DamageMath")
local Combat = Harness.load("src/shared/data/combat")

-- Phase 0 reference numbers (enemies.luau header): Trialist Sword attack 18, STR 10, Horizontal 1.0.
local SWORD = 18
local STR = 10
local BOAR_DEFENSE = 2

describe("DamageMath.damage", function()
	it("follows the section 6 formula: attack * multiplier * (1 + STR * scale) - defense, rounded", function()
		local expected = SWORD * 1.0 * (1 + STR * Combat.strDamageScale) - BOAR_DEFENSE
		expect(DamageMath.damage(SWORD, 1.0, STR, false, BOAR_DEFENSE)).toBe(math.floor(expected + 0.5))
	end)

	it("a level-1 Horizontal takes 6 to 8 hits to drop a 120 HP boar (section 9 tuning)", function()
		local perHit = DamageMath.damage(SWORD, 1.0, STR, false, BOAR_DEFENSE)
		local hits = math.ceil(120 / perHit)
		expect(hits).toBeGreaterThanOrEqual(6)
		expect(hits).toBeLessThanOrEqual(8)
	end)

	it("multiplies the attack side by the crit multiplier", function()
		local plain = DamageMath.attackValue(SWORD, 1.0, STR, false)
		local crit = DamageMath.attackValue(SWORD, 1.0, STR, true)
		expect(crit).toBeCloseTo(plain * Combat.critMultiplier, 1e-9)
	end)

	it("never drops below the minimum damage", function()
		expect(DamageMath.damage(1, 0.1, 0, false, 1000)).toBe(Combat.minimumDamage)
	end)

	it("doubles what gets through defense on a target in Break", function()
		local normal = DamageMath.damage(SWORD, 1.0, STR, false, BOAR_DEFENSE)
		local broken = DamageMath.damage(SWORD, 1.0, STR, false, BOAR_DEFENSE, { inBreak = true })
		expect(broken).toBe(math.floor(normal * Combat.breakDamageMultiplier + 0.5))
	end)

	it("applies the Switch bonus and capped Tempo stacks to the attack side", function()
		local base = DamageMath.attackValue(SWORD, 1.0, STR, false)
		expect(DamageMath.attackValue(SWORD, 1.0, STR, false, { switch = true })).toBeCloseTo(
			base * (1 + Combat.switchDamageBonus),
			1e-9
		)
		local maxed = DamageMath.attackValue(SWORD, 1.0, STR, false, { tempo = Combat.tempoMaxStacks + 3 })
		expect(maxed).toBeCloseTo(base * (1 + Combat.tempoMaxStacks * Combat.tempoDamagePerStack), 1e-9)
	end)

	it("a guard removes 70% and a shield 85% of the final number", function()
		local raw = DamageMath.attackValue(40, 1.0, 0, false)
		local open = DamageMath.resolve(raw, 0)
		local guarded = DamageMath.resolve(raw, 0, { guarded = true })
		local shielded = DamageMath.resolve(raw, 0, { guarded = true, hasShield = true })
		expect(guarded).toBe(math.floor(open * (1 - Combat.guardReduction) + 0.5))
		expect(shielded).toBe(math.floor(open * (1 - Combat.shieldReduction) + 0.5))
		expect(shielded).toBeLessThan(guarded)
	end)

	it("negative STR and defense are treated as zero", function()
		expect(DamageMath.attackValue(SWORD, 1.0, -50, false)).toBeCloseTo(SWORD, 1e-9)
		expect(DamageMath.resolve(SWORD, -10)).toBe(SWORD)
	end)
end)

describe("DamageMath basics and enemies", function()
	it("a basic hit is the Art formula at the basic multiplier", function()
		expect(DamageMath.basicDamage(SWORD, STR, false, BOAR_DEFENSE)).toBe(
			DamageMath.damage(SWORD, Combat.basicAttackMultiplier, STR, false, BOAR_DEFENSE)
		)
	end)

	it("an enemy strike has no STR and no crit", function()
		-- Frenzy Boar charge: attack 14 x 1.6 against the Trialist cloth set (defense 2+1+1+1 = 5).
		expect(DamageMath.enemyDamage(14, 1.6, 5)).toBe(math.floor(14 * 1.6 - 5 + 0.5))
	end)

	it("basic attacks deal a tenth of the Art's gauge damage", function()
		expect(DamageMath.gaugeDamage(20, false)).toBe(20)
		expect(DamageMath.gaugeDamage(20, true)).toBeCloseTo(20 * Combat.basicAttackGaugeFraction, 1e-9)
	end)

	it("guard drain follows the drain fraction", function()
		expect(DamageMath.guardDrain(30)).toBeCloseTo(30 * Combat.guardGaugeDrainFraction, 1e-9)
	end)
end)

describe("DamageMath.critChance", function()
	it("rises with AGI and caps", function()
		expect(DamageMath.critChance(0)).toBe(0)
		expect(DamageMath.critChance(100)).toBeCloseTo(100 * Combat.critChancePerAgi, 1e-9)
		expect(DamageMath.critChance(100000)).toBe(Combat.critChanceMax)
		expect(DamageMath.critChance(-5)).toBe(0)
	end)

	it("rollCrit matches the chance within a few percent over many rolls", function()
		local random = Random.new(42)
		local agi = 50
		local hits = 0
		local rolls = 20000
		for _ = 1, rolls do
			if DamageMath.rollCrit(random, agi) then
				hits += 1
			end
		end
		expect(hits / rolls).toBeCloseTo(DamageMath.critChance(agi), 0.02)
	end)
end)

describe("DamageMath guard geometry", function()
	it("the parry window is open from the raise for parryWindow seconds, never before", function()
		expect(DamageMath.parryWindowOpen(nil, 10)).toBe(false)
		expect(DamageMath.parryWindowOpen(10, 10)).toBe(true)
		expect(DamageMath.parryWindowOpen(10, 10 + Combat.parryWindow)).toBe(true)
		expect(DamageMath.parryWindowOpen(10, 10 + Combat.parryWindow + 0.001)).toBe(false)
		expect(DamageMath.parryWindowOpen(10, 9.9)).toBe(false)
	end)

	it("guard cone and reduction widen with a shield", function()
		expect(DamageMath.guardCone(false)).toBe(Combat.guardConeDegrees)
		expect(DamageMath.guardCone(true)).toBe(Combat.shieldConeDegrees)
		expect(DamageMath.guardReduction(false)).toBe(Combat.guardReduction)
		expect(DamageMath.guardReduction(true)).toBe(Combat.shieldReduction)
	end)

	it("inCone accepts targets inside the half-angle and rejects the flanks and the back", function()
		local origin = Vector3.new(0, 0, 0)
		local facing = Vector3.new(0, 0, -1)
		-- 120-degree cone: 50 degrees off is in, 70 degrees off is out.
		local function at(degrees: number): Vector3
			local radians = math.rad(degrees)
			return Vector3.new(math.sin(radians) * 10, 0, -math.cos(radians) * 10)
		end
		expect(DamageMath.inCone(origin, facing, at(0), 120)).toBe(true)
		expect(DamageMath.inCone(origin, facing, at(50), 120)).toBe(true)
		expect(DamageMath.inCone(origin, facing, at(-50), 120)).toBe(true)
		expect(DamageMath.inCone(origin, facing, at(70), 120)).toBe(false)
		expect(DamageMath.inCone(origin, facing, at(180), 120)).toBe(false)
		-- A shield's 180 degrees takes the whole front half.
		expect(DamageMath.inCone(origin, facing, at(85), 180)).toBe(true)
		expect(DamageMath.inCone(origin, facing, at(95), 180)).toBe(false)
	end)

	it("inCone ignores height and treats a target on the origin as inside", function()
		local origin = Vector3.new(0, 0, 0)
		local facing = Vector3.new(0, -0.9, -1)
		expect(DamageMath.inCone(origin, facing, Vector3.new(0, 30, -5), 60)).toBe(true)
		expect(DamageMath.inCone(origin, facing, Vector3.new(0, 3, 0), 60)).toBe(true)
		expect(DamageMath.inCone(origin, Vector3.new(0, 1, 0), Vector3.new(0, 0, -5), 60)).toBe(false)
	end)

	it("staggerDirection names the side the attacker struck from in the target's frame", function()
		local target = CFrame.new(10, 0, 10) -- faces -Z
		expect(DamageMath.staggerDirection(Vector3.new(10, 0, 4), target)).toBe("Front")
		expect(DamageMath.staggerDirection(Vector3.new(10, 0, 16), target)).toBe("Back")
		expect(DamageMath.staggerDirection(Vector3.new(16, 0, 10), target)).toBe("Right")
		expect(DamageMath.staggerDirection(Vector3.new(4, 0, 10), target)).toBe("Left")
		-- A target turned to face +X: an attacker at +X is in front of it.
		local turned = CFrame.lookAt(Vector3.new(0, 0, 0), Vector3.new(5, 0, 0))
		expect(DamageMath.staggerDirection(Vector3.new(5, 0, 0), turned)).toBe("Front")
	end)

	it("hitStopTier escalates Normal -> Final -> Kill", function()
		expect(DamageMath.hitStopTier(false, false)).toBe("Normal")
		expect(DamageMath.hitStopTier(true, false)).toBe("Final")
		expect(DamageMath.hitStopTier(false, true)).toBe("Kill")
		expect(DamageMath.hitStopTier(true, true)).toBe("Kill")
	end)
end)

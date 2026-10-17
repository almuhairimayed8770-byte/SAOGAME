--!strict
--[[
	DamageMath: the pure numbers of section 6, Lune-tested.

	Damage per hit = weapon attack * Art multiplier * (1 + STR * strScale) * crit - target defense,
	floored at combat.minimumDamage. Switch and Tempo multiply the attack side (Phase 1); Break
	doubles what gets through defense; a guard takes 70% (85% behind a shield) off the final number.
	Every constant comes from src/shared/data/combat.luau; this file holds no number of its own.

	The geometry helpers (guard cone, stagger direction) take Vector3 / CFrame, so they run on the
	server and under Lune alike; nothing here touches an Instance.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Combat = require(ReplicatedStorage.Shared.data.combat)
local Types = require(ReplicatedStorage.Shared.types)

export type Extra = {
	switch: boolean?, -- the hit landed inside a partner's Switch window (+25%)
	tempo: number?, -- party Tempo stacks (+4% each, capped)
	inBreak: boolean?, -- the target is in Break (x2)
	guarded: boolean?, -- the target guarded the hit (reduction applies)
	hasShield: boolean?, -- the guard is a shield (wider cone, bigger reduction)
}

export type StaggerDirection = "Front" | "Back" | "Left" | "Right"

local DamageMath = {}

local function round(value: number): number
	return math.floor(value + 0.5)
end

--- The attack side of a hit before defense: attack * multiplier * STR scale * crit (* Switch, Tempo).
function DamageMath.attackValue(
	weaponAttack: number,
	artMultiplier: number,
	str: number,
	crit: boolean,
	extra: Extra?
): number
	local value = weaponAttack * artMultiplier * (1 + math.max(str, 0) * Combat.strDamageScale)
	if crit then
		value *= Combat.critMultiplier
	end
	if extra ~= nil then
		if extra.switch then
			value *= 1 + Combat.switchDamageBonus
		end
		local tempo = extra.tempo
		if tempo ~= nil and tempo > 0 then
			value *= 1 + math.min(tempo, Combat.tempoMaxStacks) * Combat.tempoDamagePerStack
		end
	end
	return value
end

--- The defense side: subtracts flat defense, applies guard reduction and the Break doubling, rounds,
--- and floors at combat.minimumDamage so a hit that connects always shows a number.
function DamageMath.resolve(attackValue: number, targetDefense: number, extra: Extra?): number
	local value = attackValue - math.max(targetDefense, 0)
	if extra ~= nil then
		if extra.guarded then
			value *= 1 - DamageMath.guardReduction(extra.hasShield == true)
		end
		if extra.inBreak then
			value *= Combat.breakDamageMultiplier
		end
	end
	return math.max(Combat.minimumDamage, round(value))
end

--- Full section 6 damage: attackValue then resolve.
function DamageMath.damage(
	weaponAttack: number,
	artMultiplier: number,
	str: number,
	crit: boolean,
	targetDefense: number,
	extra: Extra?
): number
	return DamageMath.resolve(
		DamageMath.attackValue(weaponAttack, artMultiplier, str, crit, extra),
		targetDefense,
		extra
	)
end

--- A basic attack: the Art formula at combat.basicAttackMultiplier.
function DamageMath.basicDamage(
	weaponAttack: number,
	str: number,
	crit: boolean,
	targetDefense: number,
	extra: Extra?
): number
	return DamageMath.damage(weaponAttack, Combat.basicAttackMultiplier, str, crit, targetDefense, extra)
end

--- An enemy strike: attack * multiplier with no STR and no crit, minus the player's defense.
function DamageMath.enemyDamage(attack: number, multiplier: number, targetDefense: number, extra: Extra?): number
	return DamageMath.damage(attack, multiplier, 0, false, targetDefense, extra)
end

--- Crit chance from AGI: critChancePerAgi per point, capped at critChanceMax.
function DamageMath.critChance(agi: number): number
	return math.clamp(math.max(agi, 0) * Combat.critChancePerAgi, 0, Combat.critChanceMax)
end

--- Rolls a crit on the given generator (server-seeded; never the client's).
function DamageMath.rollCrit(random: Random, agi: number): boolean
	return random:NextNumber() < DamageMath.critChance(agi)
end

--- Fraction of damage a guard removes: 70%, or 85% behind a shield.
function DamageMath.guardReduction(hasShield: boolean): number
	return if hasShield then Combat.shieldReduction else Combat.guardReduction
end

--- Degrees of the guard cone: 120, or 180 with a shield.
function DamageMath.guardCone(hasShield: boolean): number
	return if hasShield then Combat.shieldConeDegrees else Combat.guardConeDegrees
end

--- Guard Gauge damage of a hit: the Art's value, or a tenth of it for a basic attack.
function DamageMath.gaugeDamage(artGauge: number, isBasic: boolean): number
	return artGauge * (if isBasic then Combat.basicAttackGaugeFraction else 1)
end

--- Guard Gauge drained from a guarding player by a guarded hit.
function DamageMath.guardDrain(gaugeDamage: number): number
	return gaugeDamage * Combat.guardGaugeDrainFraction
end

--- True when the guard raised at `guardSince` still counts as a parry for a hit landing at `hitTime`.
function DamageMath.parryWindowOpen(guardSince: number?, hitTime: number): boolean
	if guardSince == nil then
		return false
	end
	local elapsed = hitTime - guardSince
	return elapsed >= -1e-6 and elapsed <= Combat.parryWindow + 1e-6
end

--- Horizontal (XZ) unit vector of `v`, or nil when it has no horizontal component.
local function flat(v: Vector3): Vector3?
	local horizontal = Vector3.new(v.X, 0, v.Z)
	if horizontal.Magnitude < 1e-6 then
		return nil
	end
	return horizontal.Unit
end

--- True when `targetPos` lies inside the horizontal cone of `coneDegrees` opened around `facing` at `origin`.
--- A target standing on the origin counts as inside (it is touching, not behind).
function DamageMath.inCone(origin: Vector3, facing: Vector3, targetPos: Vector3, coneDegrees: number): boolean
	local toTarget = flat(targetPos - origin)
	local forward = flat(facing)
	if toTarget == nil then
		return true
	end
	if forward == nil then
		return false
	end
	local cosine = forward:Dot(toTarget)
	local limit = math.cos(math.rad(math.clamp(coneDegrees, 0, 360) / 2))
	return cosine >= limit - 1e-6
end

--- Which side of the target the attacker struck from, in the target's own frame (-Z is its front).
function DamageMath.staggerDirection(attackerPos: Vector3, targetCFrame: CFrame): StaggerDirection
	local localPos = targetCFrame:PointToObjectSpace(attackerPos)
	if math.abs(localPos.Z) >= math.abs(localPos.X) then
		return if localPos.Z <= 0 then "Front" else "Back"
	end
	return if localPos.X > 0 then "Right" else "Left"
end

--- Hit-stop tier for a landed hit: Kill when it killed, Final on an Art's last window, else Normal.
function DamageMath.hitStopTier(isLastWindow: boolean, killed: boolean): Types.HitStopTier
	if killed then
		return "Kill"
	end
	return if isLastWindow then "Final" else "Normal"
end

return DamageMath

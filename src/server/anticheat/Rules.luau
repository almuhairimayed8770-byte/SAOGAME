--!strict
--[[
	Anti-cheat rules (section 17): the pure arithmetic behind AntiCheatService, so the policy runs
	and is tested under Lune without an engine.

	- allowedDistance: how far a fighter may legitimately travel in one sample interval. The sprint
	  cap (combat.maxSpeedStudsPerSecond) times combat.speedMargin always applies over the interval,
	  plus whatever lag credit the caller passes (D-052: physics and replication carry an honest root
	  a little past the cap in some samples, and with no margin a long sprint drained the credit). Mid-Art the Art's rootMotion plus combat.rootMotionSlack is added; mid-Dodge
	  combat.dodgeDistance is added. Only the horizontal plane is judged (the engine owns falling,
	  and the kill volume owns the rim).
	- maxCredit / nextCredit: the section 17 lag budget (combat.lagAllowance) as a per-player credit
	  of maxCredit studs (the sprint cap over the lag). The client sprints at exactly the cap and the
	  server reads its root through replication, whose jitter can put one reading up to the lag
	  ahead of the last; it does not accumulate, so over many samples an honest root travels at most
	  the cap over the elapsed time plus one lag. The credit is spent by a sample that travels past
	  its allowance without credit and refills only when a sample travels less, never above
	  maxCredit, so a sustained walk over the cap times the margin drains it within a few samples
	  and is flagged, while an honest sprint refills it on every sample by the margin's share.
	- evaluate: compares a sampled delta with its allowance. Inside the allowance nothing happens; a
	  delta beyond combat.teleportFlagDistance is a teleport anomaly weighted by how many
	  teleport distances the unexplained part (delta minus allowance) spans, at least one and
	  capped at world.anticheat.teleportWeightCapFraction of the kick threshold so no single
	  anomaly can ever kick; anything else beyond the allowance is an over-speed anomaly of weight
	  world.anticheat.speedWeight.
	- prune / weight / shouldShadow / shouldKick: the sliding combat.anomalyWindow. A kick needs at
	  least world.anticheat.minimumAnomalies separate anomalies AND a total weight at or above
	  combat.anomalyKickThreshold inside the window; the shadow flag comes at
	  world.anticheat.shadowFraction of that weight.

	Every number comes from combat.luau and world.luau; the callers pass the combat table so a test
	can hand in its own.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.types)
local Combat = require(Shared.data.combat)
local World = require(Shared.data.world)
local Arts = require(Shared.data.arts)
local Weapons = require(Shared.data.weapons)

--- One anomaly inside a player's window.
export type Flag = {
	at: number, -- server time it was recorded
	weight: number, -- anomaly weight (a plain over-speed sample is world.anticheat.speedWeight)
	reason: string, -- what happened, for the log
}

--- The part of an EntityRecord the rules read (tests pass a plain table).
export type RecordLike = {
	state: Types.EntityState | string,
	weaponId: string?,
}

--- The combat numbers the rules read (tests pass their own table).
export type CombatLike = {
	maxSpeedStudsPerSecond: number,
	speedMargin: number, -- tolerance on the sprint cap per sample (D-052)
	lagAllowance: number, -- seconds of replication lag; the sprint cap over it is the lag credit (section 17)
	rootMotionSlack: number,
	dodgeDistance: number,
	teleportFlagDistance: number,
	anomalyKickThreshold: number,
	anomalyWindow: number,
}

export type VerdictKind = "ok" | "speed" | "teleport"

export type Verdict = {
	kind: VerdictKind,
	delta: number,
	allowed: number,
	weight: number, -- 0 when ok
	reason: string,
}

local Rules = {}

local STATE_ART: { [string]: boolean } = { Art = true, PostMotion = true }
local STATE_DODGE = "Dodge"

local maxMotionCache: { [string]: number } = {}

--- The largest rootMotion of any Art the weapon category knows, or of every Art when the category is nil.
--- The fallback allowance when CombatService cannot say which Art is running.
function Rules.maxRootMotion(category: Types.WeaponCategory?): number
	local key = if category ~= nil then category else "*"
	local cached = maxMotionCache[key]
	if cached ~= nil then
		return cached
	end
	local categories: { Types.WeaponCategory } = if category ~= nil then { category } else Arts.weapons()
	local best = 0
	for _, weapon in categories do
		for _, art in Arts.list(weapon) do
			best = math.max(best, art.rootMotion)
		end
	end
	maxMotionCache[key] = best
	return best
end

--- The weapon category of a record's equipped weapon, or nil.
function Rules.categoryOf(record: RecordLike): Types.WeaponCategory?
	local weaponId = record.weaponId
	if weaponId == nil then
		return nil
	end
	return Weapons.category(weaponId)
end

--- Studs a fighter in `record`'s state may travel in `interval` seconds, plus `credit` studs of
--- lag credit (nil is none). `artRootMotion` is the running Art's rootMotion when the caller knows
--- it (0 for a basic swing); nil falls back to the largest Art of the fighter's weapon category so
--- an unknown Art never flags an honest player.
function Rules.allowedDistance(
	interval: number,
	record: RecordLike,
	combat: CombatLike,
	artRootMotion: number?,
	credit: number?
): number
	local allowed = combat.maxSpeedStudsPerSecond * combat.speedMargin * math.max(interval, 0)
		+ math.max(credit or 0, 0)
	local state = record.state :: string
	if STATE_ART[state] then
		local motion = artRootMotion
		if motion == nil then
			motion = Rules.maxRootMotion(Rules.categoryOf(record))
		end
		allowed += (motion :: number) + combat.rootMotionSlack
	elseif state == STATE_DODGE then
		allowed += combat.dodgeDistance
	end
	return allowed
end

--- The full lag credit, in studs: the sprint cap over the section 17 lag budget. A player starts
--- with it, and again after every sample reset (death, respawn, a new character).
function Rules.maxCredit(combat: CombatLike): number
	return combat.maxSpeedStudsPerSecond * math.max(combat.lagAllowance, 0)
end

--- The lag credit after a sample that travelled `delta` studs against `base` studs allowed without
--- credit (the Art or Dodge grant included): what the sample left unused refills it, what it
--- travelled past `base` spends it, clamped to 0..maxCredit.
function Rules.nextCredit(credit: number, base: number, delta: number, combat: CombatLike): number
	return math.clamp(credit + base - delta, 0, Rules.maxCredit(combat))
end

--- The anomaly weight of a teleport of `delta` studs when `allowed` of them were legitimate: one per
--- teleportFlagDistance of unexplained distance (at least one), capped at
--- world.anticheat.teleportWeightCapFraction of the kick threshold so a single anomaly can never
--- reach it on its own.
function Rules.teleportWeight(delta: number, combat: CombatLike, allowed: number?): number
	local excess = delta - (allowed or 0)
	local spans = math.ceil(excess / combat.teleportFlagDistance)
	local cap = math.max(1, math.floor(combat.anomalyKickThreshold * World.anticheat.teleportWeightCapFraction))
	return math.clamp(spans, 1, cap)
end

--- Judges one sample: `delta` studs travelled against `allowed` studs.
function Rules.evaluate(delta: number, allowed: number, combat: CombatLike): Verdict
	local reasons = World.anticheat.reasons
	if delta <= allowed then
		return { kind = "ok", delta = delta, allowed = allowed, weight = 0, reason = "" }
	end
	if delta > combat.teleportFlagDistance then
		return {
			kind = "teleport",
			delta = delta,
			allowed = allowed,
			weight = Rules.teleportWeight(delta, combat, allowed),
			reason = ("%s: %.1f studs in one sample (allowed %.1f)"):format(reasons.teleport, delta, allowed),
		}
	end
	return {
		kind = "speed",
		delta = delta,
		allowed = allowed,
		weight = World.anticheat.speedWeight,
		reason = ("%s: %.1f studs in one sample (allowed %.1f)"):format(reasons.speed, delta, allowed),
	}
end

--- Horizontal distance between two positions (Y is the engine's: falls and jumps are not judged).
function Rules.horizontalDistance(from: Vector3, to: Vector3): number
	local dx = to.X - from.X
	local dz = to.Z - from.Z
	return math.sqrt(dx * dx + dz * dz)
end

--- Drops every flag older than the anomaly window, in place; returns the list.
function Rules.prune(flags: { Flag }, now: number, combat: CombatLike?): { Flag }
	local window = (combat or Combat).anomalyWindow
	local cutoff = now - window
	local index = 1
	while index <= #flags do
		if flags[index].at <= cutoff then
			table.remove(flags, index)
		else
			index += 1
		end
	end
	return flags
end

--- Total anomaly weight of the flags inside the window ending at `now`.
function Rules.weight(flags: { Flag }, now: number, combat: CombatLike?): number
	local window = (combat or Combat).anomalyWindow
	local cutoff = now - window
	local total = 0
	for _, flag in flags do
		if flag.at > cutoff then
			total += flag.weight
		end
	end
	return total
end

--- How many separate anomalies sit inside the window ending at `now`.
function Rules.count(flags: { Flag }, now: number, combat: CombatLike?): number
	local window = (combat or Combat).anomalyWindow
	local cutoff = now - window
	local total = 0
	for _, flag in flags do
		if flag.at > cutoff then
			total += 1
		end
	end
	return total
end

--- True once the window's weight reaches world.anticheat.shadowFraction of the kick threshold: the
--- player is shadow-flagged.
function Rules.shouldShadow(flags: { Flag }, now: number, combat: CombatLike?): boolean
	local threshold = (combat or Combat).anomalyKickThreshold
	return Rules.weight(flags, now, combat) >= threshold * World.anticheat.shadowFraction
end

--- True once the window holds at least world.anticheat.minimumAnomalies separate anomalies whose
--- weight reaches the kick threshold. Never true for a single anomaly, however large.
function Rules.shouldKick(flags: { Flag }, now: number, combat: CombatLike?): boolean
	local threshold = (combat or Combat).anomalyKickThreshold
	if Rules.count(flags, now, combat) < World.anticheat.minimumAnomalies then
		return false
	end
	return Rules.weight(flags, now, combat) >= threshold
end

return Rules

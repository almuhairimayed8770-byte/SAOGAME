--!strict
--[[
	ContactPredictor: the frame the local fighter's blade first touches an enemy's body (section 6
	"Authority and feel", issue 4). The client predicts the hit-stop and the camera instantly so the
	swing feels local; the server's sweep still decides every hit and the number.

	While a damage window of the local clip is open, `step(clipTime)` runs once per rendered frame,
	after the rig's step and the root motion (CharacterController's render step), and sweeps the
	blade the trails draw (TrailStart, the guard, to TrailEnd, the tip; BladeContact) from where the
	last frame showed it to where this frame shows it. It does not take the chord between the two:
	sub-samples between the frames interpolate the root and every joint's Transform (BladeContact.
	blade), so a snap that carries the blade through most of its cut in one frame follows the arc
	and cannot skip a target. Sub-samples are spaced so neither end of the blade moves more than
	combat.luau sweepMaxTipStep between two of them, at most contact.maxSubdivisions a frame, as
	the server's sweep spaces its own. Only the part of the frame inside a window is swept: a frame
	that opens a window starts at its open time, one that closes it stops at its close time.

	At each sub-sample the blade, grown by combat.hitSphereRadius, is tested against the box of
	every queryable part (CanQuery or CanCollide) of every fighter it may damage, the server's
	overlap rule: never the local character's own rig, a player (no PvP, as the server's
	mayDamage), a dead fighter, or one this swing already predicted dead. A fighter counts once per
	window, and a window touches at most combat.maxTargetsPerWindow of them. A hit the server
	already confirmed before the blade got there (`confirmed`) is not predicted again.

	Each touch is a Contact: the fighter, the window, the hit point, and the hit-stop tier the
	server will give it: Kill when ContactPredictor.provesKill says the hit cannot leave the enemy
	standing, Final on the move's final hit (every Art's last window; a basic chain's last swing),
	else Normal. Replication.contact plays it; HitConfirmed later brings the number and any upgrade.

	Pure apart from reading the Instances it is handed and the fighters `deps.targets` lists; specs
	drive it on real rigs in Lune.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Combat = require(Shared.data.combat)
local Enemies = require(Shared.data.enemies)
local Types = require(Shared.types)
local BladeContact = require(Shared.choreo.BladeContact)
local ClipSampler = require(Shared.choreo.ClipSampler)

export type Tier = "Normal" | "Final" | "Kill"

--- One swing or Art of the local fighter, as the controller starts it.
export type Swing = {
	model: Model, -- the local character: its blade sweeps, its own rig is never a target
	clip: Types.ClipDef,
	artId: string?, -- nil for a basic swing
	finalHit: boolean, -- the last window is the move's final hit (every Art; the chain's last basic)
	multiplier: number, -- the Art's multiplier, or combat.basicAttackMultiplier (the kill rule)
	weaponAttack: number, -- the equipped weapon's attack (the kill rule)
}

--- A predicted hit: the blade touched this fighter in this window on this frame.
export type Contact = {
	targetId: number,
	model: Model,
	windowIndex: number, -- 1-based, in the clip's order (HitConfirmed's hitIndex)
	artId: string?,
	tier: Tier,
	killed: boolean, -- predicted to kill (tier Kill)
	position: Vector3, -- the point of the touched part's box nearest the blade
}

export type Deps = {
	-- Every fighter this client tracks (EntityTracker.all): records with id, model, kind, state,
	-- hp, maxHp, defId and elite.
	targets: () -> { any },
	-- True when the server already confirmed this hit (HitConfirmed came first): it is not predicted.
	confirmed: ((targetId: number, windowIndex: number, artId: string?) -> boolean)?,
}

type Window = { open: number, close: number }

type Candidate = { record: any, parts: { BasePart } }

export type Predictor = {
	begin: (self: Predictor, swing: Swing) -> boolean,
	stop: (self: Predictor) -> (),
	active: (self: Predictor) -> boolean,
	step: (self: Predictor, clipTime: number, jumped: boolean?) -> { Contact },
}

local ContactPredictor = {}
ContactPredictor.__index = ContactPredictor

local NONE: { Contact } = table.freeze({}) :: any
local RADIUS: number = Combat.hitSphereRadius
local MAX_STEP: number = Combat.sweepMaxTipStep
local MAX_SUBDIVISIONS: number = Combat.contact.maxSubdivisions
local MAX_TARGETS: number = Combat.maxTargetsPerWindow

-- ------------------------------------------------------------------ rules (pure)

--- The hit-stop tier the server gives a hit of window `windowIndex` of `windowCount`
--- (DamageMath.hitStopTier, EntityService.applyHit): Kill on a kill, Final on the move's final hit.
function ContactPredictor.tierFor(windowIndex: number, windowCount: number, finalHit: boolean, killed: boolean): Tier
	if killed then
		return "Kill"
	elseif finalHit and windowIndex >= windowCount then
		return "Final"
	end
	return "Normal"
end

--- The least a hit by `weaponAttack` x `multiplier` can do to an enemy record: the section 6
--- formula with STR at 0, no crit, no Switch, Tempo or Break (each of them only adds), less the
--- enemy's defense (its def scaled by tier, Elite when the record is), rounded and at least
--- combat.minimumDamage. Nil for a record whose defense the client cannot know (not an enemy, an
--- unknown def).
function ContactPredictor.leastDamage(record: any, weaponAttack: number, multiplier: number): number?
	if record == nil or record.kind ~= "Enemy" then
		return nil
	end
	local base = Enemies.byId(record.defId or "")
	if base == nil then
		return nil
	end
	local def = Enemies.scaled(base)
	if record.elite == true then
		def = Enemies.variant(def, "Elite")
	end
	local value = weaponAttack * multiplier - math.max(def.defense, 0)
	return math.max(Combat.minimumDamage, math.floor(value + 0.5))
end

--- True only when the hit cannot leave the enemy standing: its least damage reaches the enemy's
--- replicated HP plus half a point (the HP attribute is rounded) plus what out-of-combat regen gives
--- back in combat.luau contact.killRegenSeconds. A record without a known def, or with no HP
--- left to take (the server's kill is on its way), is never predicted.
function ContactPredictor.provesKill(record: any, weaponAttack: number, multiplier: number): boolean
	local least = ContactPredictor.leastDamage(record, weaponAttack, multiplier)
	if least == nil then
		return false
	end
	local hp, maxHp = record.hp, record.maxHp
	if typeof(hp) ~= "number" or typeof(maxHp) ~= "number" or hp <= 0 then
		return false
	end
	local margin = 0.5 + math.max(maxHp, 0) * Combat.outOfCombatRegenPerSecond * Combat.contact.killRegenSeconds
	return least >= hp + margin
end

-- ------------------------------------------------------------------ the predictor

--- A predictor reading its fighters from `deps`.
function ContactPredictor.new(deps: Deps): Predictor
	local self = setmetatable({
		deps = deps,
		swing = nil :: Swing?,
		chain = nil :: BladeContact.Chain?,
		windows = {} :: { Window },
		current = nil :: BladeContact.Pose?,
		previous = nil :: BladeContact.Pose?,
		time = nil :: number?,
		windowHits = {} :: { [number]: { [number]: boolean } },
		windowCounts = {} :: { [number]: number },
		killed = {} :: { [number]: boolean },
		parts = (setmetatable({}, { __mode = "k" }) :: any) :: { [Instance]: { BasePart } },
	}, ContactPredictor)
	return (self :: any) :: Predictor
end

--- Starts predicting one swing (a new swing ends the last). False when the rig has no blade to
--- sweep (no TrailStart and TrailEnd on one jointed part) or the clip has no damage window.
function ContactPredictor.begin(self: any, swing: Swing): boolean
	self:stop()
	local windows: { Window } = ClipSampler.hitWindows(swing.clip)
	if #windows == 0 then
		return false
	end
	local chain = BladeContact.chain(swing.model)
	if chain == nil then
		return false
	end
	self.swing = swing
	self.chain = chain
	self.windows = windows
	return true
end

--- Stops predicting: the swing ended, was refused, or the body was taken from it.
function ContactPredictor.stop(self: any)
	self.swing = nil
	self.chain = nil
	self.windows = {}
	self.current = nil
	self.previous = nil
	self.time = nil
	table.clear(self.windowHits)
	table.clear(self.windowCounts)
	table.clear(self.killed)
	table.clear(self.parts)
end

--- True while a swing is being predicted.
function ContactPredictor.active(self: any): boolean
	return self.swing ~= nil
end

-- The queryable parts of a fighter's model (read once per swing).
local function partsOf(self: any, model: Model): { BasePart }
	local list = self.parts[model]
	if list == nil then
		list = {}
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") and BladeContact.queryable(descendant :: BasePart) then
				table.insert(list, descendant :: BasePart)
			end
		end
		self.parts[model] = list
	end
	return list
end

-- The fighters the blade may damage this frame whose parts come near the blade's swept sphere.
local function candidatesNear(self: any, center: Vector3, reach: number): { Candidate }
	local swing = self.swing :: Swing
	local found: { Candidate } = {}
	for _, record in self.deps.targets() do
		local model = record.model
		if
			model == nil
			or model == swing.model
			or record.kind == "Player"
			or record.state == "Dead"
			or self.killed[record.id]
		then
			continue
		end
		local near: { BasePart } = {}
		for _, part in partsOf(self, model) do
			if (part.CFrame.Position - center).Magnitude <= reach + part.Size.Magnitude * 0.5 then
				table.insert(near, part)
			end
		end
		if #near > 0 then
			table.insert(found, { record = record, parts = near })
		end
	end
	return found
end

--- Sweeps this frame's blade (the clip at `clipTime`, the rig as it was just stepped) from last
--- frame's and returns the contacts it made, earliest first. The first frame of a swing, a frame
--- whose clip did not move (a hit-stop, the Art hold), and the wake of a render stall's jump
--- (`jumped`: poses a stall apart say nothing of the path the blade took, so the gap is never
--- swept and the server's word plays any hit in it whole) only record where the blade is.
function ContactPredictor.step(self: any, clipTime: number, jumped: boolean?): { Contact }
	local swing: Swing? = self.swing
	local chain: BladeContact.Chain? = self.chain
	if swing == nil or chain == nil then
		return NONE
	end
	local current = BladeContact.read(chain, self.current)
	self.current = current
	local previous: BladeContact.Pose? = self.previous
	local from: number? = self.time
	self.time = clipTime
	if previous == nil or from == nil or clipTime <= from or jumped == true then
		self.previous = BladeContact.copy(current, previous)
		return NONE
	end
	local t0 = from :: number
	local span = clipTime - t0
	local contacts: { Contact } = {}
	local budget = MAX_SUBDIVISIONS
	for index, window in self.windows do
		local lo = math.max(t0, window.open)
		local hi = math.min(clipTime, window.close)
		if hi < lo or hi <= t0 or budget <= 0 then
			continue
		end
		local hits = self.windowHits[index]
		if hits == nil then
			hits = {}
			self.windowHits[index] = hits
		end
		if (self.windowCounts[index] or 0) >= MAX_TARGETS then
			continue
		end
		local alphaLo, alphaHi = (lo - t0) / span, (hi - t0) / span
		local guardLo, tipLo = BladeContact.blade(chain, current, previous, alphaLo)
		local guardHi, tipHi = BladeContact.blade(chain, current, previous, alphaHi)
		local count = math.min(BladeContact.steps(guardLo, tipLo, guardHi, tipHi, MAX_STEP, budget), budget)
		budget -= count
		-- Everything this stretch of the swing can reach: the four ends, the arc's bulge (at most
		-- half the longest chord) and the hit radius.
		local center = (guardLo + tipLo + guardHi + tipHi) / 4 -- unit: the mean of the four ends
		local reach = math.max(
			(guardLo - center).Magnitude,
			(tipLo - center).Magnitude,
			(guardHi - center).Magnitude,
			(tipHi - center).Magnitude
		) + 0.5 * math.max((tipHi - tipLo).Magnitude, (guardHi - guardLo).Magnitude) + RADIUS
		local candidates = candidatesNear(self, center, reach)
		if #candidates == 0 then
			continue
		end
		-- A window that opened inside this frame is tested from its open instant; one already open
		-- was tested at t0 by the frame before.
		local first = if lo > t0 then 0 else 1
		for k = first, count do
			local alpha = alphaLo + (alphaHi - alphaLo) * k / count
			local guard, tip
			if k == 0 then
				guard, tip = guardLo, tipLo
			elseif k == count then
				guard, tip = guardHi, tipHi
			else
				guard, tip = BladeContact.blade(chain, current, previous, alpha)
			end
			for _, candidate in candidates do
				local record = candidate.record
				local id = record.id
				if hits[id] or self.killed[id] then
					continue
				end
				local touched, at = BladeContact.touch(guard, tip, candidate.parts, RADIUS)
				if not touched or at == nil then
					continue
				end
				hits[id] = true
				self.windowCounts[index] = (self.windowCounts[index] or 0) + 1
				local confirmed = self.deps.confirmed
				if confirmed ~= nil and confirmed(id, index, swing.artId) then
					continue
				end
				local killed = ContactPredictor.provesKill(record, swing.weaponAttack, swing.multiplier)
				if killed then
					self.killed[id] = true
				end
				table.insert(contacts, {
					targetId = id,
					model = record.model,
					windowIndex = index,
					artId = swing.artId,
					tier = ContactPredictor.tierFor(index, #self.windows, swing.finalHit, killed),
					killed = killed,
					position = at :: Vector3,
				})
				if (self.windowCounts[index] or 0) >= MAX_TARGETS then
					break
				end
			end
			if (self.windowCounts[index] or 0) >= MAX_TARGETS then
				break
			end
		end
	end
	self.previous = BladeContact.copy(current, previous)
	return contacts
end

return ContactPredictor

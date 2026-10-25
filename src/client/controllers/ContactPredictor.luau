--!strict
--[[
	ContactPredictor: the frame the local fighter's blade first touches an enemy's body (section 6
	"Authority and feel", issue 4). The client predicts the hit-stop and the camera instantly so the
	swing feels local; the server's sweep still decides every hit and the number.

	While a damage window of the local clip is open, `step(clipTime)` runs once per rendered frame,
	after the rig's step and the root motion (CharacterController's render step), and sweeps the
	blade the trails draw (TrailStart, the guard, to TrailEnd, the tip; BladeContact) from where the
	last frame showed it to where this frame shows it. It does not take the chord between the two,
	nor a blend of the two frames' joints: a sub-sample between the frames poses the swing's own
	clip at its clip time, as the server's sweep solves its sub-samples (fix F2), carrying what the
	frames show beyond the clip (a layer over it, a blend still running) across the frame from one
	end to the other, and the root interpolated between the frames. So the blade follows the arc
	the clip draws through its keys, the one the server sweeps: a joint blend between two frames
	that straddle a snap key cuts that key's corner, and at 30 fps once drew a touch 0.57 studs
	past the true blade, a hit the server never counts. Sub-samples are split where the blade
	moves farthest until neither end moves more than combat.luau sweepMaxTipStep between two of
	them, at most contact.maxSubdivisions a frame, as the server's followArc spaces its own. Only
	the part of the frame inside a window is swept: a frame that opens a window starts at its open
	time, posed as the clip has it there, and one that closes it stops at its close time.

	At each sub-sample the blade, grown by combat.hitSphereRadius, is tested against the box of
	every queryable part (CanQuery or CanCollide) of every fighter it may damage, the server's
	overlap rule: never the local character's own rig, a player (no PvP, as the server's
	mayDamage), a dead fighter, or one this swing already predicted dead. A fighter counts once per
	window, and a window touches at most combat.maxTargetsPerWindow of them. A hit the server
	already confirmed before the blade got there (`confirmed`) is not predicted again. A part the
	body is drawn away from (`hidden`: the root a rush draws the body ahead of, D-171) is not where
	the body shows, and is not tested.

	Each touch is a Contact: the fighter, the window, the swing's sequence number (the request
	carried it and HitConfirmed echoes it), the hit point, and the hit-stop tier the server will
	give it: Kill when ContactPredictor.provesKill says the hit cannot leave the enemy
	standing, Final on the move's final hit (every Art's last window; a basic chain's last swing),
	else Normal. Replication.contact plays it; HitConfirmed later brings the number and any upgrade.

	A touch never plays before its strike's key pose (fix F1, the point-blank rule). Every window
	opens on its snap's first frame (D-043), so a target already inside the start pose's blade, or
	one the first expo-out step reaches, is touched while the frame still shows the blade before
	the cut. Such a touch is kept, and the frame the clip reaches the snap's key (the strike snap
	key whose segment opens the window, ClipSampler.isStrikeSnap) plays it: the clip runs its 2 to
	4 snap frames with the smear, and the hit-stop, the impact picture and the camera hold the
	key pose, the blade through the body. A touch on or after the key plays on its own frame as
	before. The kept touch is checked against `confirmed` and the kill rule when it plays, and its
	hit point is taken from the blade the key frame shows. A render stall's jump, or a stop, drops
	what is kept: the server's word plays that hit whole.

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
	swing: number?, -- the sequence number its request carried (ArtRequest / BasicAttackRequest swing)
}

--- A predicted hit: the blade touched this fighter in this window on this frame.
export type Contact = {
	targetId: number,
	model: Model,
	windowIndex: number, -- 1-based, in the clip's order (HitConfirmed's hitIndex)
	artId: string?,
	swing: number?, -- the swing's sequence number (HitConfirmed's swing)
	tier: Tier,
	killed: boolean, -- predicted to kill (tier Kill)
	position: Vector3, -- the point of the touched part's box nearest the blade
}

export type Deps = {
	-- Every fighter this client tracks (EntityTracker.live, read each frame: never copy it per
	-- call): records with id, model, kind, state, hp, maxHp, defId and elite.
	targets: () -> { any },
	-- True when the server already confirmed this hit (HitConfirmed came first): it is not predicted.
	confirmed: ((targetId: number, windowIndex: number, artId: string?, swing: number?) -> boolean)?,
	-- True for a part the body is drawn away from (Replication.drawnAway): it is not tested.
	hidden: ((part: BasePart) -> boolean)?,
}

-- A damage window and its strike's key: the clip time of the snap key that window's snap lands
-- on (the window's open when the clip has no strike snap in it: nothing is kept back).
type Window = { open: number, close: number, key: number }

type Candidate = { record: any, parts: { BasePart } }

-- A touch found before its strike's key, kept for the key frame.
type Pending = { record: any, parts: { BasePart }, windowIndex: number, position: Vector3 }

-- The frame being swept: the clip times of its two ends and, once a sub-sample needs them, what
-- each end shows beyond the swing's clip (per chain link, the clip's Transform's inverse times
-- the drawn one).
type Sweep = {
	from: number,
	to: number,
	residuals: boolean,
	residualFrom: { CFrame },
	residualTo: { CFrame },
}

-- One blade sample of a frame: its place in the frame (0 its start, 1 its end) and its two ends.
type Sample = { alpha: number, guard: Vector3, tip: Vector3 }

--- The Art stand-off (fix F1, ContactPredictor.standOff): step the body `distance` studs along
--- `away` (flat, unit) between clip times `from` and `to` (AimLogic.standOffAt).
export type StandOff = { distance: number, away: Vector3, from: number, to: number }

export type Predictor = {
	begin: (self: Predictor, swing: Swing) -> boolean,
	stop: (self: Predictor) -> (),
	active: (self: Predictor) -> boolean,
	step: (self: Predictor, clipTime: number, jumped: boolean?) -> { Contact },
	awaitsKey: (self: Predictor, windowIndex: number, artId: string?, swing: number?) -> boolean,
}

local ContactPredictor = {}
ContactPredictor.__index = ContactPredictor

local NONE: { Contact } = table.freeze({}) :: any
local RADIUS: number = Combat.hitSphereRadius
local MAX_STEP: number = Combat.sweepMaxTipStep
local MAX_SUBDIVISIONS: number = Combat.contact.maxSubdivisions
local MAX_TARGETS: number = Combat.maxTargetsPerWindow
-- Clip times compare within this (combat.luau contact.keyEpsilon): a clock summed from 60 fps
-- steps lands a hair short of a key written to four decimals.
local KEY_EPSILON: number = Combat.contact.keyEpsilon
local STAND_OFF = Combat.contact.standOff
local MIN_FACE_DISTANCE: number = Combat.aim.minFaceDistance
-- How deep a blade must pass into a body for the server's sweep to promise the hit (HitSweep:
-- every point the blade passes lies within half a step of a sample).
local PROMISE: number = RADIUS - MAX_STEP / 2
-- Samples of a damage window the stand-off checks the cut still reaches the body at.
local REACH_SAMPLES: number = STAND_OFF.reachSamples

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
		pending = {} :: { Pending },
		parts = (setmetatable({}, { __mode = "k" }) :: any) :: { [Instance]: { BasePart } },
		sweep = { from = 0, to = 0, residuals = false, residualFrom = {}, residualTo = {} } :: Sweep,
		arcPose = { root = CFrame.identity, transforms = {} } :: BladeContact.Pose,
	}, ContactPredictor)
	return (self :: any) :: Predictor
end

--- The clip time of the strike's key for a damage window: the first strike snap key
--- (ClipSampler.isStrikeSnap) after the window opens and by its close; the window's open when it
--- has none.
function ContactPredictor.strikeKey(clip: Types.ClipDef, window: { open: number, close: number }): number
	local keys = clip.keys
	for index = 2, #keys do
		local time = keys[index].time
		if time > window.open + KEY_EPSILON and time <= window.close + KEY_EPSILON then
			if ClipSampler.isStrikeSnap(clip, index) then
				return time
			end
		end
	end
	return window.open
end

--- Starts predicting one swing (a new swing ends the last). False when the rig has no blade to
--- sweep (no TrailStart and TrailEnd on one jointed part) or the clip has no damage window.
function ContactPredictor.begin(self: any, swing: Swing): boolean
	self:stop()
	local windows: { Window } = {}
	for _, window in ClipSampler.hitWindows(swing.clip) do
		table.insert(
			windows,
			{ open = window.open, close = window.close, key = ContactPredictor.strikeKey(swing.clip, window) }
		)
	end
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
	table.clear(self.pending)
	table.clear(self.parts)
end

--- True while a swing is being predicted.
function ContactPredictor.active(self: any): boolean
	return self.swing ~= nil
end

--- True while hit `windowIndex` of the swing being predicted (its Art and, when both carry one, its
--- request's sequence number) has yet to show its strike's key on this client's clip: the clip has
--- not reached it, or a touch of it waits for it (F1). Replication holds the server's word for
--- that hit until then (D-267), so the hold starts on the key frame whichever comes first.
function ContactPredictor.awaitsKey(self: any, windowIndex: number, artId: string?, swing: number?): boolean
	local current = self.swing
	if current == nil or current.artId ~= artId then
		return false
	end
	if swing ~= nil and current.swing ~= nil and current.swing ~= swing then
		return false
	end
	local window = self.windows[windowIndex]
	if window == nil then
		return false
	end
	local time: number? = self.time
	return time == nil or time < window.key - KEY_EPSILON
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
		local hidden = self.deps.hidden
		for _, part in partsOf(self, model) do
			if hidden ~= nil and hidden(part) then
				continue -- the body is drawn away from it (a rush's root, D-171)
			end
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

-- Plays one touch of window `index` into `contacts`: nothing when the server already confirmed it;
-- the kill rule and the tier as the record stands now.
local function emit(self: any, contacts: { Contact }, record: any, index: number, position: Vector3)
	local swing = self.swing :: Swing
	local id = record.id
	local confirmed = self.deps.confirmed
	if confirmed ~= nil and confirmed(id, index, swing.artId, swing.swing) then
		return
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
		swing = swing.swing,
		tier = ContactPredictor.tierFor(index, #self.windows, swing.finalHit, killed),
		killed = killed,
		position = position,
	})
end

-- The swing clip's own Transform of each chain link at `time` (identity where the clip keys none).
local function clipTransforms(chain: BladeContact.Chain, clip: Types.ClipDef, time: number, into: { CFrame })
	local offsets = ClipSampler.sample(clip, time)
	for index, link in chain.links do
		local offset = offsets[link.joint.Name]
		into[index] = if offset ~= nil then ClipSampler.toCFrame(offset) else CFrame.identity
	end
end

-- What a drawn pose shows beyond the clip at `time`, per link: clip^-1 * drawn.
local function residualsOf(
	chain: BladeContact.Chain,
	clip: Types.ClipDef,
	time: number,
	pose: BladeContact.Pose,
	into: { CFrame }
)
	clipTransforms(chain, clip, time, into)
	for index in chain.links do
		into[index] = into[index]:Inverse() * (pose.transforms[index] or CFrame.identity)
	end
end

-- The blade `alpha` of the way through this frame (0 the last frame's pose, 1 this one's): between
-- the two, the clip posed at that clip time with the frames' residuals carried across, from the
-- root interpolated between the frames (fix F2).
local function arcBlade(
	self: any,
	chain: BladeContact.Chain,
	current: BladeContact.Pose,
	previous: BladeContact.Pose,
	alpha: number
): (Vector3, Vector3)
	if alpha >= 1 then
		return BladeContact.blade(chain, current)
	elseif alpha <= 0 then
		return BladeContact.blade(chain, previous)
	end
	local sweep: Sweep = self.sweep
	local clip = (self.swing :: Swing).clip
	if not sweep.residuals then
		sweep.residuals = true
		residualsOf(chain, clip, sweep.from, previous, sweep.residualFrom)
		residualsOf(chain, clip, sweep.to, current, sweep.residualTo)
	end
	local pose: BladeContact.Pose = self.arcPose
	local transforms = pose.transforms
	clipTransforms(chain, clip, sweep.from + (sweep.to - sweep.from) * alpha, transforms)
	for index in chain.links do
		transforms[index] = transforms[index] * sweep.residualFrom[index]:Lerp(sweep.residualTo[index], alpha)
	end
	pose.root = previous.root:Lerp(current.root, alpha)
	return BladeContact.blade(chain, pose)
end

-- The blade samples of one stretch of the frame, from `lo` to `hi` (both given), in order: the
-- interval whose ends move farthest is split at its middle until no end of the blade moves more
-- than sweepMaxTipStep between two samples or `budget` splits are spent. Returns them and the
-- splits spent.
local function arcSamples(
	self: any,
	chain: BladeContact.Chain,
	current: BladeContact.Pose,
	previous: BladeContact.Pose,
	lo: Sample,
	hi: Sample,
	budget: number
): ({ Sample }, number)
	local samples: { Sample } = { lo, hi }
	local spent = 0
	while spent < budget do
		local worst, at = MAX_STEP, 0
		for index = 1, #samples - 1 do
			local a, b = samples[index], samples[index + 1]
			local travel = math.max((b.guard - a.guard).Magnitude, (b.tip - a.tip).Magnitude)
			if travel > worst then
				worst, at = travel, index
			end
		end
		if at == 0 then
			break
		end
		local alpha = (samples[at].alpha + samples[at + 1].alpha) * 0.5
		local guard, tip = arcBlade(self, chain, current, previous, alpha)
		table.insert(samples, at + 1, { alpha = alpha, guard = guard, tip = tip })
		spent += 1
	end
	return samples, spent
end

--- The Art stand-off (fix F1): a target already inside the blade's start pose for the first
--- damage window would be cut before the swing moves (the review's "sword raised, pause, pop"), so
--- the body steps straight away from it over the anticipation, from clip time `from` (the hold
--- pose the Art is released from) to the window's open: the least multiple of standOff.stepStuds
--- that leaves the start pose's blade standOff.clearStuds from every queryable part of `target`,
--- at most standOff.maxStuds. `rootCFrame` is the root at `from`, facing where the Art cuts; the
--- clip's own root motion carries it on to the open. Nil when the start pose already clears the
--- body, when no step within maxStuds clears it, or when a window's cut that passed within the
--- sweep's promise (the hit radius less half of sweepMaxTipStep) would then pass shallower: a
--- stand-off never costs a hit. Pure: it poses the clip itself and reads only the parts' boxes.
function ContactPredictor.standOff(
	model: Model,
	clip: Types.ClipDef,
	from: number,
	rootCFrame: CFrame,
	target: Model
): StandOff?
	local window = ClipSampler.hitWindows(clip)[1]
	local chain = BladeContact.chain(model)
	local targetRoot = target.PrimaryPart
	if window == nil or chain == nil or targetRoot == nil or window.open <= from then
		return nil
	end
	local parts: { BasePart } = {}
	for _, descendant in target:GetDescendants() do
		if descendant:IsA("BasePart") and BladeContact.queryable(descendant :: BasePart) then
			table.insert(parts, descendant :: BasePart)
		end
	end
	if #parts == 0 then
		return nil
	end
	-- Straight away from the target; from one too close to give a direction (combat.luau
	-- aim.minFaceDistance), straight back from where the Art faces.
	local offset = rootCFrame.Position - targetRoot.CFrame.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local away = if flat.Magnitude >= MIN_FACE_DISTANCE
		then flat.Unit
		else -Vector3.new(rootCFrame.LookVector.X, 0, rootCFrame.LookVector.Z).Unit
	local start = ClipSampler.rootMotionAt(clip, from)
	local pose: BladeContact.Pose = { root = rootCFrame, transforms = {} }
	-- The nearest the blade comes to the body at clip time `time` with the body stepped `back`.
	local function gap(time: number, back: number): number
		local motion = ClipSampler.rootMotionAt(clip, time)
		pose.root = rootCFrame * CFrame.new(motion[1] - start[1], motion[2] - start[2], motion[3] - start[3])
			+ away * back
		clipTransforms(chain, clip, time, pose.transforms)
		local guard, tip = BladeContact.blade(chain, pose)
		local best = math.huge
		for _, part in parts do
			local distance = BladeContact.segmentBoxDistance(guard, tip, part.CFrame, part.Size)
			best = math.min(best, distance)
		end
		return best
	end
	local clear: number = STAND_OFF.clearStuds
	if gap(window.open, 0) >= clear then
		return nil
	end
	local stepStuds: number = STAND_OFF.stepStuds
	local need: number? = nil
	for k = 1, math.floor(STAND_OFF.maxStuds / stepStuds + 1e-6) do
		if gap(window.open, k * stepStuds) >= clear then
			need = k * stepStuds
			break
		end
	end
	if need == nil then
		return nil
	end
	-- The body stays stepped for the rest of the Art, so every window that cut within the promise
	-- from where the body stood must still do so from where it stepped to (the first one did: its
	-- start pose is in the body).
	local function reaches(each: { open: number, close: number }, back: number): boolean
		for k = 0, REACH_SAMPLES do
			local time = each.open + (each.close - each.open) * k / REACH_SAMPLES
			if gap(time, back) <= PROMISE then
				return true
			end
		end
		return false
	end
	for index, each in ClipSampler.hitWindows(clip) do
		if not reaches(each, need :: number) and (index == 1 or reaches(each, 0)) then
			return nil
		end
	end
	return { distance = need :: number, away = away, from = from, to = window.open }
end

-- The point of `parts` nearest the blade from `guard` to `tip`, or `fallback` with no parts.
local function nearestPoint(parts: { BasePart }, guard: Vector3, tip: Vector3, fallback: Vector3): Vector3
	local best, at = math.huge, fallback
	for _, part in parts do
		local distance, point = BladeContact.segmentBoxDistance(guard, tip, part.CFrame, part.Size)
		if distance < best then
			best, at = distance, point
		end
	end
	return at
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
		if jumped == true then
			-- The stall says nothing of where the blade was at the key: the server's word plays it.
			table.clear(self.pending)
		end
		self.previous = BladeContact.copy(current, previous)
		return NONE
	end
	local t0 = from :: number
	local span = clipTime - t0
	local contacts: { Contact } = {}
	local sweep: Sweep = self.sweep
	sweep.from, sweep.to, sweep.residuals = t0, clipTime, false
	-- Touches kept for their strike's key play on the first frame that shows it (F1).
	local pending: { Pending } = self.pending
	if #pending > 0 then
		local guard, tip = BladeContact.blade(chain, current)
		local index = 1
		while index <= #pending do
			local entry = pending[index]
			local window = self.windows[entry.windowIndex]
			if window == nil or clipTime >= window.key - KEY_EPSILON then
				table.remove(pending, index)
				local record = entry.record
				if window ~= nil and record.state ~= "Dead" then
					emit(
						self,
						contacts,
						record,
						entry.windowIndex,
						nearestPoint(entry.parts, guard, tip, entry.position)
					)
				end
			else
				index += 1
			end
		end
	end
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
		local guardLo, tipLo = arcBlade(self, chain, current, previous, alphaLo)
		local guardHi, tipHi = arcBlade(self, chain, current, previous, alphaHi)
		-- Everything this stretch of the swing can reach: the four ends, the arc's bulge (taken as
		-- the longest chord: an arc through a key can bow farther than half of it) and the hit radius.
		local center = (guardLo + tipLo + guardHi + tipHi) / 4 -- unit: the mean of the four ends
		local reach = math.max(
			(guardLo - center).Magnitude,
			(tipLo - center).Magnitude,
			(guardHi - center).Magnitude,
			(tipHi - center).Magnitude
		) + math.max((tipHi - tipLo).Magnitude, (guardHi - guardLo).Magnitude) + RADIUS
		local candidates = candidatesNear(self, center, reach)
		if #candidates == 0 then
			budget -= 1
			continue
		end
		local samples, spent = arcSamples(
			self,
			chain,
			current,
			previous,
			{ alpha = alphaLo, guard = guardLo, tip = tipLo },
			{ alpha = alphaHi, guard = guardHi, tip = tipHi },
			budget
		)
		budget -= math.max(spent, 1)
		-- A window that opened inside this frame is tested from its open instant; one already open
		-- was tested at t0 by the frame before.
		local first = if lo > t0 then 1 else 2
		for k = first, #samples do
			local guard, tip = samples[k].guard, samples[k].tip
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
				if clipTime < window.key - KEY_EPSILON then
					-- Before the strike's key: this frame still shows the cut to come (F1).
					table.insert(
						pending,
						{ record = record, parts = candidate.parts, windowIndex = index, position = at :: Vector3 }
					)
				else
					emit(self, contacts, record, index, at :: Vector3)
				end
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

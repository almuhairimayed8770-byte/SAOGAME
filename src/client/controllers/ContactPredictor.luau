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
	every queryable part (CanQuery or CanCollide) of every fighter it may damage but the weapon it
	holds (BladeContact.hurtbox: the kobold's club clashes, it never wounds, D-277), the server's
	overlap rule: never the local character's own rig, a player (no PvP, as the server's
	mayDamage), a dead fighter, or one this swing already predicted dead. A fighter counts once per
	window, and a window touches at most combat.maxTargetsPerWindow of them. A hit the server
	already confirmed before the blade got there (`confirmed`) is not predicted again. A part the
	body is drawn away from (`hidden`: the root a rush draws the body ahead of, D-171) is not where
	the body shows, and is not tested. A fighter beside the swing (D-275: its root outside the aim
	assist's cone, combat.aim.assistConeDegrees, around the body's look as the window opens) is
	touched only where the drawn blade itself crosses its body, as the server's sweep counts it:
	the blade grown by combat.besideHitRadius instead, following the drawn arc between two
	sub-samples (split while an end moves farther than combat.besideFollowStep, at most
	combat.besideMaxSubdivisions a frame, BladeContact.followTouch), so a cut that ends short of an
	enemy at its side never plays a hit the server would not count, at 30 fps as at 144.

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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Combat = require(Shared.data.combat)
local ChoreoData = require(Shared.data.choreo)
local Enemies = require(Shared.data.enemies)
local ImpactData = require(Shared.data.impact)
local World = require(Shared.data.world)
local Rigs = require(Shared.data.rigs)
local WeaponModels = require(Shared.data.weaponModels)
local Types = require(Shared.types)
local BladeContact = require(Shared.choreo.BladeContact)
local ClipSampler = require(Shared.choreo.ClipSampler)
local Joints = require(Shared.choreo.Joints)
local AimLogic = require(script.Parent.AimLogic)

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
--- `away` (flat, unit) between clip times `from` and `to` (AimLogic.standOffAt). `from` is where
--- the step starts: the end of the clip's activation hold, or as much before it as the speed
--- needs, never before the clip time the plan was made at (D-604); that clip time itself for a
--- plan with no step. `room`, when the plan was made against the world: how far of a further
--- `distance` the root at `rootCFrame` may still step before the world (ContactPredictor.room),
--- for the frames that take the step.
export type StandOff = {
	distance: number,
	away: Vector3,
	from: number,
	to: number,
	-- With `clipTime` (the swing's clock as the step is taken; the clip time the plan was made at when nil) the room
	-- also keeps the gap for every pose the clip still has to show from then on (D-534).
	room: ((rootCFrame: CFrame, distance: number, clipTime: number?) -> number)?,
	-- The keep-out (D-314, StandOffOptions.keepOut): how much farther along `away` the body stands
	-- at a clip time than the step above puts it, and the clip time past which that changes no more.
	keep: ((clipTime: number) -> number)?,
	keepUntil: number?,
	-- The clip time the swing's activation hold ends when the plan was made before it (D-604): the
	-- tell holds still, so the step and the reach's first step wait for it (as far as the speed
	-- lets them), and a frame that still draws a pose at or before it shows the plan's move with the
	-- pose that leaves it (CharacterController, D-496). Nil for a swing with no activation hold (a
	-- basic) or one made past it, and for a held stance's plan (StandOffOptions.stance): it takes
	-- no step and no reach and is done by the hold pose, so it waits for no hold (D-617).
	still: number?,
	-- And how far the keep-out holds the body aside at a clip time, along `side` (flat, unit, square
	-- to `away`), off the face over a part the target holds (D-315); `roomSide` is `room` along it.
	-- Nil when the target holds nothing the body stands beside.
	side: Vector3?,
	keepSide: ((clipTime: number) -> number)?,
	roomSide: ((rootCFrame: CFrame, distance: number, clipTime: number?) -> number)?,
	-- How deep the column (the root, the torsos and the head as they stand now relative to the
	-- root, the pose the frame draws) stands in the world behind along `away` with the root at
	-- `rootCFrame`: the most any of them steps back toward the target to stand clear, 0 when every
	-- one stands clear (D-680). Nil with no world cast.
	depth: ((rootCFrame: CFrame) -> number)?,
	-- A held stance's (StandOffOptions.stance) wait, in clip seconds (D-691): its pose waits on
	-- its first pose that long while the body steps out first, so `keep`, `keepSide` and
	-- `keepUntil` run on the stance's clock, the clip time plus the time it waited (up to this).
	-- Nil for none.
	wait: number?,
}

--- What a stand-off plan covers (ContactPredictor.standOff). With neither field it is the Art's
--- blade step alone.
export type StandOffOptions = {
	-- Plan the keep-out too (D-314): a plan comes back whenever the target has a blocker.
	keepOut: boolean?,
	-- false: no blade step (a basic swing; its first cut is the key rule's alone).
	step: boolean?,
	-- Seconds of clip time the pose the screen draws runs behind the root (D-535): a frame's
	-- length times impact.luau poseLagFrames (a root write shows on its own frame, a pose that many
	-- frames later, D-342). The keep-out holds the hands and arms out of the target as drawn too.
	-- Nil: a 60 Hz frame's (keepOut.sampleSeconds); 0: as posed alone.
	poseLag: number?,
	-- How the target moves on through the swing (D-565, ContactPredictor.targetMotion): the
	-- keep-out holds the hands and arms, and the reach the blade, out of the body parts where the
	-- target's clips carry them, not where they stood when the plan was made. Nil: as they stand.
	target: TargetMotion?,
	-- The held start pose of an Art (D-606): the keep-out only, up to this clip time (the pose
	-- the hold freezes at), with no strike's reach and no blade: the body and its hands and arms
	-- kept out of the target as the stance forms. Nil: the whole clip.
	stance: number?,
	-- The Additive clips the swinger's own rig plays on top of the swing (D-683,
	-- ContactPredictor.ownLayers): the keep-out poses the body with each of them on from its clock,
	-- as the rig draws it. The player's Breathe never stops (Choreo plays it from the frame the rig
	-- appears): its waist, shoulder, wrist and sword keys carried Basic1's blade up to 0.023 into
	-- the PC's flinching kobold on the settle, where the bare clip the plan posed held it 0.005.
	-- Nil: the swing's clip alone.
	own: { OwnLayer }?,
}

--- A clip the target plays on through a swing, as its rig's mixer holds it when the plan is made:
--- the clip, its clock and its speed (ContactPredictor.targetMotion).
export type TargetTrack = { clip: Types.ClipDef, time: number, speed: number }

--- How the target moves on while a swing plays (D-565, StandOffOptions.target): the clip its
--- Base layer shows (a held enemy's idle loop, on from its clock), and the additive reaction a cut
--- plays on it (its flinch, from the side the swing comes from) from each strike's key once the
--- key's hold is over, as Replication plays it on the hit's word.
export type TargetMotion = { base: TargetTrack?, flinch: Types.ClipDef? }

--- An Additive clip the swinger's own rig plays on top of a swing, as its mixer holds it when the
--- plan is made (D-683, ContactPredictor.ownLayers): the clip, its clock, its speed, the weight it
--- shows at, its per-joint mask (Mixer PlayOptions.mask) and whether it gives way under the swing's
--- strikes (Mixer PlayOptions.yields: the rig's breathing, D-685).
export type OwnLayer = {
	clip: Types.ClipDef,
	time: number,
	speed: number,
	weight: number,
	mask: { [string]: number }?,
	yields: boolean?,
}

--- A box cast for the stand-off: how far the box `size` at `start` moves along `vector` before it
--- meets the world, nil when it never does (ContactPredictor.worldCast).
export type BoxCast = (start: CFrame, size: Vector3, vector: Vector3) -> number?

--- The engine's Blockcast as worldCast makes it: through every part that can collide, never one
--- under `exclude`; like the engine's, it never meets a part the box starts in.
export type Blockcast = (start: CFrame, size: Vector3, vector: Vector3, exclude: { Instance }) -> number?

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
-- D-275: the reach, and the step, of the blade against a fighter beside the swing, and how closely
-- its test follows the drawn arc between two sub-samples.
local BESIDE_RADIUS: number = Combat.besideHitRadius
local BESIDE_FOLLOW_STEP: number = Combat.besideFollowStep
local BESIDE_MAX_SUBDIVISIONS: number = Combat.besideMaxSubdivisions
local ASSIST_CONE: number = Combat.aim.assistConeDegrees
local MAX_STEP: number = Combat.sweepMaxTipStep
local MAX_SUBDIVISIONS: number = Combat.contact.maxSubdivisions
local MAX_TARGETS: number = Combat.maxTargetsPerWindow
-- Clip times compare within this (combat.luau contact.keyEpsilon): a clock summed from 60 fps
-- steps lands a hair short of a key written to four decimals.
local KEY_EPSILON: number = Combat.contact.keyEpsilon
local STAND_OFF = Combat.contact.standOff
-- A colliding part the engine collides by a hull inside its box, braced by its box less this on
-- every side (standOff.hullInsetStuds, D-680).
local HULL_INSETS: { [string]: number } = Combat.contact.standOff.hullInsetStuds
-- The depth the brace leaves a drawn body in the world behind (D-680), and an aside a part
-- standing in it (D-696).
local BRACE_STUDS: number = Combat.contact.standOff.braceStuds
-- The fastest the reach (D-424) carries the body back: the sprint cap outside root motion, the
-- speed the stand-off's own step keeps under over the shortest anticipation.
local SPRINT: number = Combat.maxSpeedStudsPerSecond
local MIN_FACE_DISTANCE: number = Combat.aim.minFaceDistance
-- How deep a blade must pass into a body for the server's sweep to promise the hit (HitSweep:
-- every point the blade passes lies within half a step of a sample).
local PROMISE: number = RADIUS - MAX_STEP / 2
-- Samples of a damage window the stand-off checks the cut still reaches the body at.
local REACH_SAMPLES: number = STAND_OFF.reachSamples
local KEEP_OUT = STAND_OFF.keepOut
-- The longest an Art's start pose stands frozen (the hold up to its cancel time, the release's
-- wait inside it): how long a stance's plan keeps the hands out of a target that moves on (D-606).
local HOLD_SECONDS: number = Combat.activationCancelTime
-- How far the pose the screen draws runs behind the root, for a plan asked with no frame time: a
-- root write shows on its own frame and a pose impact.luau poseLagFrames later (D-342), and the
-- keep-out's samples stand a 60 Hz frame apart (D-535).
local DEFAULT_POSE_LAG: number = KEEP_OUT.sampleSeconds * ImpactData.poseLagFrames
-- The piece the body's speed is read over (item 285): a keep-out sample over keepOut.speedPieces.
local SPEED_PIECE: number = KEEP_OUT.sampleSeconds / KEEP_OUT.speedPieces
-- What the stand-off keeps between the root's box and the world (D-235 amended).
local WALL_GAP: number = STAND_OFF.wallGapStuds
local FIGHTER_FOLDERS: { string } = { World.playground.folders.enemies, World.playground.folders.entities }

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
		aims = {} :: { [number]: CFrame }, -- D-275: per window, the root as it opened
		beside = {} :: { [number]: { [number]: boolean } }, -- D-275: per window, per fighter
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
	table.clear(self.aims)
	table.clear(self.beside)
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

-- The parts of a fighter's model a blade may wound (read once per swing): queryable, and not a
-- weapon it holds (BladeContact.hurtbox, D-277).
local function partsOf(self: any, model: Model): { BasePart }
	local list = self.parts[model]
	if list == nil then
		list = {}
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") and BladeContact.hurtbox(descendant :: BasePart) then
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

-- D-275: whether `record` stands beside window `index` of the swing: its root outside the aim
-- assist's cone around `aim` (the root as the window opened). Judged once per window and kept, as
-- the server's sweep judges it.
local function besideSwing(self: any, index: number, aim: CFrame, record: any): boolean
	local judged = self.beside[index]
	if judged == nil then
		judged = {}
		self.beside[index] = judged
	end
	local known = judged[record.id]
	if known == nil then
		local root = record.model.PrimaryPart
		known = root ~= nil
			and BladeContact.beside(aim.Position, aim.LookVector, root.CFrame.Position, ASSIST_CONE, MIN_FACE_DISTANCE)
		judged[record.id] = known
	end
	return known
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
-- root interpolated between the frames (fix F2) along the clip's own root motion (D-275).
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
	local time = sweep.from + (sweep.to - sweep.from) * alpha
	clipTransforms(chain, clip, time, transforms)
	for index in chain.links do
		transforms[index] = transforms[index] * sweep.residualFrom[index]:Lerp(sweep.residualTo[index], alpha)
	end
	-- The root between the frames moves the way the clip carries it (D-275: a lunge accelerates
	-- through a frame), the rest of its travel (a stand-off, a slide) straight.
	local root = previous.root:Lerp(current.root, alpha)
	pose.root = root + BladeContact.rootBow(clip, sweep.from, sweep.to, time, root.Rotation)
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

local castParams: RaycastParams? = nil

-- workspace:Blockcast through every part that can collide (a trail, an effect or a trigger is not
-- a wall), never one under `exclude`.
local function engineBlockcast(start: CFrame, size: Vector3, vector: Vector3, exclude: { Instance }): number?
	local params = castParams
	if params == nil then
		local created = RaycastParams.new()
		created.FilterType = Enum.RaycastFilterType.Exclude
		created.RespectCanCollide = true
		castParams = created
		params = created
	end
	local query = params :: RaycastParams
	query.FilterDescendantsInstances = exclude
	local result = workspace:Blockcast(start, size, vector, query)
	return if result ~= nil then result.Distance else nil
end

--- What the stand-off's world cast never meets (D-235 amended): the body `model` itself, the
--- fighters' folders under `scene` (workspace by default; world.luau playground.folders enemies
--- and entities) and every player's character (`players`, Players:GetPlayers() by default). A
--- fighter is not a wall: the stand-off steps away from it, and the server's body collision
--- settles the rest.
function ContactPredictor.fighters(model: Model, scene: Instance?, players: { any }?): { Instance }
	local list: { Instance } = { model }
	local root: Instance = scene or workspace
	for _, name in FIGHTER_FOLDERS do
		local folder = root:FindFirstChild(name)
		if folder ~= nil then
			table.insert(list, folder)
		end
	end
	local everyone = players
	if everyone == nil then
		local ok, listed = pcall(function(): { any }
			return Players:GetPlayers()
		end)
		everyone = if ok and typeof(listed) == "table" then listed else {}
	end
	for _, player in everyone :: { any } do
		local character = player.Character
		if typeof(character) == "Instance" and character ~= model then
			table.insert(list, character)
		end
	end
	return list
end

--- The world the stand-off of `model` may not step into: `blockcast` (the engine's Blockcast by
--- default) through every part that can collide, leaving out `exclude` (ContactPredictor.fighters
--- by default, read once here: a plan lasts one anticipation).
function ContactPredictor.worldCast(model: Model, blockcast: Blockcast?, exclude: { Instance }?): BoxCast
	local cast: Blockcast = blockcast or engineBlockcast
	local leave = exclude or ContactPredictor.fighters(model)
	return function(start: CFrame, size: Vector3, vector: Vector3): number?
		return cast(start, size, vector, leave)
	end
end

-- ContactPredictor.room's cast, for a box at `frame`. A box turned to `away` (a leaning torso,
-- D-517) shrinks along it by more than the gap, and that is counted back, so the gap holds at any
-- turn. With `inside` the cast starts a whole box ahead (toward the target, its own depth along
-- `away`), so a world part the box already stands in is met at once (no room) instead of missed:
-- the engine's Blockcast never meets a part it starts in.
local function boxRoom(
	frame: CFrame,
	size: Vector3,
	away: Vector3,
	distance: number,
	cast: BoxCast,
	inside: boolean
): number
	if distance <= 0 then
		return 0
	end
	local shrunk = Vector3.new(
		math.max(size.X - 2 * WALL_GAP, WALL_GAP),
		math.max(size.Y - 2 * WALL_GAP, WALL_GAP),
		math.max(size.Z - 2 * WALL_GAP, WALL_GAP)
	)
	local right, up, look =
		math.abs(frame.RightVector:Dot(away)), math.abs(frame.UpVector:Dot(away)), math.abs(frame.LookVector:Dot(away))
	-- How far the shrunk box's face along `away` stands inside the box's own (the gap, square on).
	local short = (size.X - shrunk.X) / 2 * right + (size.Y - shrunk.Y) / 2 * up + (size.Z - shrunk.Z) / 2 * look
	local lead = if inside then size.X * right + size.Y * up + size.Z * look else 0
	local hit = cast(frame - away * lead, shrunk, away * (lead + distance + WALL_GAP + short))
	if hit == nil then
		return distance
	end
	return math.clamp(hit - lead - WALL_GAP - short, 0, distance)
end

--- How far a body whose root's box is `size` at `rootCFrame` may step along `away` (flat, unit),
--- at most `distance`, and still stand combat.contact.standOff.wallGapStuds short of the world
--- `cast` meets: the box is cast shrunk by that gap on every side, so a body already touching a
--- wall (or a hair into it) still finds it, and the step stops the gap short of where the box
--- would touch. 0 when there is no room at all.
function ContactPredictor.room(
	rootCFrame: CFrame,
	size: Vector3,
	away: Vector3,
	distance: number,
	cast: BoxCast
): number
	return boxRoom(rootCFrame, size, away, distance, cast, false)
end

-- The parts of `model` that collide with the world (keepOut.parts: the root, the torsos and the
-- head), the root first.
local function columnOf(model: Model): { BasePart }
	local list: { BasePart } = {}
	local rootPart = model.PrimaryPart
	if rootPart ~= nil then
		table.insert(list, rootPart)
	end
	for _, name in KEEP_OUT.parts do
		local found = model:FindFirstChild(name)
		if found ~= nil and found:IsA("BasePart") and found ~= rootPart then
			table.insert(list, found :: BasePart)
		end
	end
	return list
end

-- How deep a box `size` at `frame` stands in the world `cast` meets along `along` (unit): how far it
-- steps back along -along to stand clear, 0 when it stands clear (D-680). Cast from a box-depth
-- back along it, since the engine's Blockcast never meets a part it starts in.
local function worldDepth(frame: CFrame, size: Vector3, along: Vector3, cast: BoxCast): number
	local lead = size.X * math.abs(frame.RightVector:Dot(along))
		+ size.Y * math.abs(frame.UpVector:Dot(along))
		+ size.Z * math.abs(frame.LookVector:Dot(along))
	local hit = cast(frame - along * lead, size, along * lead)
	return if hit ~= nil then lead - hit else 0
end

-- The room one part of the column leaves a step along `along`: boxRoom's cast from a box-depth back
-- (D-517). With `line` (the plan's `away`) the step is an aside off it (D-696): a part that
-- stands in the world behind along the line (as the brace reads it, its box less `inset`, D-680)
-- is kept out of it only past standOff.braceStuds along the line, the depth the brace leaves a
-- drawn body, and where the cast from where it stands meets more world. The cast from a box-depth
-- back along the aside met a pillar's side face at once where a part stood past its narrow face
-- (a wall's broad face reads none: the cast starts in it): Horizontal's Head at clip 0.383, 0.046
-- past the face of a pillar 0.3 behind the press and carried along the face, held a stance's
-- aside off a kobold's axe to 0.119 of its 0.261, the frozen rows 0.011 in its blockers.
local function asideRoom(
	frame: CFrame,
	size: Vector3,
	inset: number,
	along: Vector3,
	line: Vector3?,
	distance: number,
	cast: BoxCast
): number
	local room = boxRoom(frame, size, along, distance, cast, true)
	if room >= distance or line == nil then
		return room
	end
	local hull = size - Vector3.one * (2 * inset)
	local behind = worldDepth(frame, hull, line, cast)
	if behind <= 0 then
		return room
	end
	if worldDepth(frame + along * distance, hull, line, cast) > BRACE_STUDS then
		return room
	end
	return boxRoom(frame, size, along, distance, cast, false)
end

-- ContactPredictor.room for the whole column (D-517): the root's box, and each torso and the head
-- posed where it stands now relative to `rootPart`, cast along `along` from the root at `at`; the
-- least room any leaves. Each is cast from a box-depth ahead, so a part the clip has leant, or the
-- engine has pressed, into the world leaves none: the step never carries it deeper. The root too
-- (D-560): the engine's Blockcast never meets a part it starts in, and a root box pressed past
-- the gap into a pillar, the torsos and head turned beside it, read no world and stepped on in.
-- With `line` the step is an aside off it (asideRoom, D-696).
local function columnRoom(
	rootPart: BasePart,
	column: { BasePart },
	at: CFrame,
	along: Vector3,
	distance: number,
	cast: BoxCast,
	line: Vector3?
): number
	local most = distance
	local rootFrame = rootPart.CFrame
	for _, part in column do
		if most <= 0 then
			return 0
		end
		local frame = if part == rootPart then at else at * rootFrame:ToObjectSpace(part.CFrame)
		most = asideRoom(frame, part.Size, HULL_INSETS[part.Name] or 0, along, line, most, cast)
	end
	return most
end

-- How deep the column stands in the world along `along` (flat, unit) with the root at `at`, each
-- part posed where it stands now relative to `rootPart` (columnRoom's column): the most any of them
-- steps back along -along to stand clear of what `cast` meets, 0 when every one stands clear
-- (D-680). Each box is cast from a box-depth back along it, since the engine's Blockcast never
-- meets a part it starts in; a part the engine collides by a hull inside its box (the Head) is
-- cast as its box less standOff.hullInsetStuds on every side.
local function columnDepth(rootPart: BasePart, column: { BasePart }, at: CFrame, along: Vector3, cast: BoxCast): number
	local deepest = 0
	local rootFrame = rootPart.CFrame
	for _, part in column do
		local frame = if part == rootPart then at else at * rootFrame:ToObjectSpace(part.CFrame)
		local size = part.Size - Vector3.one * (2 * (HULL_INSETS[part.Name] or 0))
		deepest = math.max(deepest, worldDepth(frame, size, along, cast))
	end
	return deepest
end

-- The rigs.luau PlayerR15 joint the sword hangs from in the hand (RightHand -> Weapon) and its C0.
local GRIP: any = nil
for _, joint in Rigs.PlayerR15.joints do
	if joint.name == WeaponModels.motorName then
		GRIP = joint
	end
end
local GRIP_C0: CFrame? = if GRIP ~= nil then ClipSampler.toCFrame(GRIP.c0) else nil

-- The blade as the swing holds it (D-537): BladeContact.chain, with the Weapon motor on the hand
-- at its rigs.luau C0 even while this client hangs the sword on its back mount (WeaponMount
-- rewrites that motor's Part0 and C0 here only; the server and the hit matrix keep it in the
-- hand). A plan made on a frame that still drew the sword on the back read the blade off it: the
-- PC's plan probe gave the third basic no keep-out at 3.2 to 3.75 studs from a held kobold, and
-- the first none at 3.5 (1.30 to 0.75 and 1.05 with the sword in the hand). C1 is the motor's own.
local function swingChain(model: Model): BladeContact.Chain?
	local chain = BladeContact.chain(model)
	if chain == nil or GRIP == nil or #chain.links == 0 then
		return chain
	end
	local last = chain.links[#chain.links]
	local motor = last.joint
	if motor.Name ~= WeaponModels.motorName or not motor:IsA("Motor6D") then
		return chain
	end
	local part0 = (motor :: Motor6D).Part0
	if part0 ~= nil and part0.Name == GRIP.part0 then
		return chain
	end
	local hand = model:FindFirstChild(GRIP.part0)
	if hand == nil or not hand:IsA("BasePart") then
		return chain
	end
	local joints = Joints.collect(model)
	local placing: { [BasePart]: Joints.Resolved } = {}
	for _, resolved in joints do
		if placing[resolved.part1] == nil then
			placing[resolved.part1] = resolved
		end
	end
	local reversed: { BladeContact.Link } = {}
	local at: BasePart = hand :: BasePart
	while at ~= chain.root do
		local resolved = placing[at]
		-- A path longer than the rig has joints is a loop: keep the chain as read.
		if resolved == nil or resolved.joint == motor or #reversed >= #joints then
			return chain
		end
		table.insert(reversed, { joint = resolved.joint, c0 = resolved.c0, c1Inverse = resolved.c1:Inverse() })
		at = resolved.part0
	end
	local links: { BladeContact.Link } = table.create(#reversed + 1)
	for index = #reversed, 1, -1 do
		table.insert(links, reversed[index])
	end
	table.insert(links, { joint = motor, c0 = GRIP_C0 :: CFrame, c1Inverse = last.c1Inverse })
	return { root = chain.root, links = links, start = chain.start, finish = chain.finish }
end

-- The Art's tell (section 7, Activation: the blade lit and a 0.1 s hold): the clip time a clip's
-- first ActivationHold ends, its time plus its data.hold (combat.luau activationHold without one);
-- nil for a clip with none (a basic swing).
local function holdEndOf(clip: Types.ClipDef): number?
	local first: Types.ClipEvent? = nil
	for _, event in clip.events do
		if event.kind == "ActivationHold" and (first == nil or event.time < (first :: Types.ClipEvent).time) then
			first = event
		end
	end
	if first == nil then
		return nil
	end
	local data = first.data
	local hold: number = if data ~= nil and typeof(data.hold) == "number" then data.hold else Combat.activationHold
	return first.time + hold
end

-- The fastest the blade step `distance` moves the body when taken from clip time `start` to `to`
-- on standOff.easing, read as the keep-out reads the body's speed (item 285): each SPEED_PIECE's
-- move over its length.
local function stepSpeed(distance: number, start: number, to: number): number
	if to <= start then
		return math.huge
	end
	local fastest, before, at = 0, 0, start
	while at < to do
		local after = AimLogic.standOffAt(distance, start, to, at + SPEED_PIECE, STAND_OFF.easing)
		fastest = math.max(fastest, (after - before) / SPEED_PIECE)
		before, at = after, at + SPEED_PIECE
	end
	return fastest
end

--- Where the Art's blade step of `distance` studs, due by clip time `to` (the first window's open),
--- starts for a clip released at `from` (D-604; pure). The activation hold is the tell: the pose
--- holds still with the blade lit, then the strike explodes out of it, so the step waits for the
--- hold to end and the body moves with the strike's wind-up. A step too long to take from there
--- within keepOut.maxSpeedStudsPerSecond starts as late before it as that speed allows (whole speed
--- pieces back from the hold's end, or from `to` when the hold ends at or past it), never before
--- `from`. `from` for a clip with no activation hold, one released past it, and a step that even
--- `from` leaves faster than that (the longest it can take).
function ContactPredictor.stepStart(clip: Types.ClipDef, from: number, to: number, distance: number): number
	local holdEnd = holdEndOf(clip)
	if holdEnd == nil or holdEnd <= from then
		return from
	end
	local start = math.min(holdEnd, to)
	while start > from do
		if stepSpeed(distance, start, to) <= KEEP_OUT.maxSpeedStudsPerSecond then
			return start
		end
		start -= SPEED_PIECE
	end
	return from
end

-- The Art's blade step (fix F1, ContactPredictor.standOff): the step along `away` that leaves the
-- first cut's start pose clear of `parts`, nil for none (see standOff).
local function bladeStep(
	model: Model,
	clip: Types.ClipDef,
	from: number,
	rootCFrame: CFrame,
	parts: { BasePart },
	away: Vector3,
	room: ((at: CFrame, distance: number, clipTime: number?) -> number)?
): number?
	local window = ClipSampler.hitWindows(clip)[1]
	local chain = swingChain(model)
	if window == nil or chain == nil or window.open <= from or #parts == 0 then
		return nil
	end
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
	local most = math.floor(STAND_OFF.maxStuds / stepStuds + 1e-6)
	local fits = if room ~= nil then math.floor(room(rootCFrame, most * stepStuds) / stepStuds + 1e-6) else most
	local need: number? = nil
	for k = 1, most do
		if gap(window.open, k * stepStuds) >= clear then
			-- Past what the world leaves: the longest step that fits, the cut as clear as it gets.
			need = math.min(k, fits) * stepStuds
			break
		end
	end
	if need == nil or need <= 0 then
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
	return need
end

-- How deep two boxes overlap: the least push along any of the fifteen axes that can part two
-- boxes; 0 or less when they are apart.
local function boxDepth(a: CFrame, aSize: Vector3, b: CFrame, bSize: Vector3): number
	local aX, aY, aZ = a.RightVector, a.UpVector, a.LookVector
	local bX, bY, bZ = b.RightVector, b.UpVector, b.LookVector
	local aHalf, bHalf = aSize * 0.5, bSize * 0.5
	local between = b.Position - a.Position
	local least = math.huge
	local function along(axis: Vector3)
		local length = axis.Magnitude
		if length < 1e-6 then
			return
		end
		local unit = axis / length
		local reach = math.abs(aX:Dot(unit)) * aHalf.X
			+ math.abs(aY:Dot(unit)) * aHalf.Y
			+ math.abs(aZ:Dot(unit)) * aHalf.Z
			+ math.abs(bX:Dot(unit)) * bHalf.X
			+ math.abs(bY:Dot(unit)) * bHalf.Y
			+ math.abs(bZ:Dot(unit)) * bHalf.Z
		least = math.min(least, reach - math.abs(between:Dot(unit)))
	end
	for _, u in { aX, aY, aZ } do
		along(u)
		for _, v in { bX, bY, bZ } do
			along(u:Cross(v))
		end
	end
	along(bX)
	along(bY)
	along(bZ)
	return least
end

-- How deep the segment `a` to `b` reaches into the box `frame` (`half`: half its size): its
-- deepest point's least distance in from a face, 0 or less when it stays out. Each face's distance
-- is linear along the segment, so the deepest point is an end or where two of them meet.
local function segmentDepth(a: Vector3, b: Vector3, frame: CFrame, half: Vector3): number
	local p, q = frame:PointToObjectSpace(a), frame:PointToObjectSpace(b)
	local d = q - p
	local c0 = { half.X - p.X, half.X + p.X, half.Y - p.Y, half.Y + p.Y, half.Z - p.Z, half.Z + p.Z }
	local c1 = { -d.X, d.X, -d.Y, d.Y, -d.Z, d.Z }
	local function at(s: number): number
		local least = math.huge
		for face, base in c0 do
			least = math.min(least, base + c1[face] * s)
		end
		return least
	end
	local deepest = math.max(at(0), at(1))
	for i = 1, #c0 - 1 do
		for j = i + 1, #c0 do
			local slope = c1[i] - c1[j]
			if math.abs(slope) > 1e-6 then
				local s = (c0[j] - c0[i]) / slope
				if s > 0 and s < 1 then
					deepest = math.max(deepest, at(s))
				end
			end
		end
	end
	return deepest
end

-- The least step at or past `from` along `away` (flat, unit) that leaves the box `aSize` as it
-- passes from `a0` to `a1` (the hull of the two: what a part sweeps between two poses), both moved
-- by `shift` first, at most `allowed` deep in the box `b` (`bSize`), math.huge for none. Two convex shapes are that far apart
-- along an axis once their centres stand both reaches less `allowed` apart along it, and past that
-- point a further step only parts them more along it; the hull's reach along an axis is the span
-- of the two boxes' together. The axes are both boxes' own, b's and each crossed with b's: apart
-- along any of them is apart, so the step is never short (with a0 = a1 it is exact).
local function stepOut(
	a0: CFrame,
	a1: CFrame,
	aSize: Vector3,
	b: CFrame,
	bSize: Vector3,
	away: Vector3,
	from: number,
	allowed: number,
	shift: Vector3
): number
	local aHalf, bHalf = aSize * 0.5, bSize * 0.5
	local bX, bY, bZ = b.RightVector, b.UpVector, b.LookVector
	local bPosition = b.Position
	local p0, p1 = a0.Position + shift, a1.Position + shift
	local x0, y0, z0 = a0.RightVector, a0.UpVector, a0.LookVector
	local x1, y1, z1 = a1.RightVector, a1.UpVector, a1.LookVector
	local least = math.huge
	local function along(axis: Vector3)
		local length = axis.Magnitude
		if length < 1e-6 or least <= from then
			return
		end
		local unit = axis / length
		local r0 = math.abs(x0:Dot(unit)) * aHalf.X
			+ math.abs(y0:Dot(unit)) * aHalf.Y
			+ math.abs(z0:Dot(unit)) * aHalf.Z
		local r1 = math.abs(x1:Dot(unit)) * aHalf.X
			+ math.abs(y1:Dot(unit)) * aHalf.Y
			+ math.abs(z1:Dot(unit)) * aHalf.Z
		local c0, c1 = p0:Dot(unit), p1:Dot(unit)
		local low, high = math.min(c0 - r0, c1 - r1), math.max(c0 + r0, c1 + r1)
		local reach = (high - low) / 2
			+ math.abs(bX:Dot(unit)) * bHalf.X
			+ math.abs(bY:Dot(unit)) * bHalf.Y
			+ math.abs(bZ:Dot(unit)) * bHalf.Z
			- allowed
		-- Stepped `t` along `away`, the centres stand `centre - t * slope` apart along the axis.
		local centre = bPosition:Dot(unit) - (low + high) / 2
		local slope = away:Dot(unit)
		if math.abs(centre - from * slope) >= reach then
			least = from
		elseif math.abs(slope) > 1e-6 then
			least = math.min(least, (centre + (if slope > 0 then reach else -reach)) / slope)
		end
	end
	for _, v in { bX, bY, bZ } do
		along(v)
	end
	for _, u in { x0, y0, z0, x1, y1, z1 } do
		along(u)
		for _, v in { bX, bY, bZ } do
			along(u:Cross(v))
		end
	end
	return least
end

-- stepOut for a sweep against a part that moves (D-565): `a0` and `a1` are the sweep's ends as
-- they stand to the box `b` (each end carried with the part from its own clip time to where the
-- sweep leaves it), so a step along `away` in the world moves each end along its own direction
-- there (`away0`, `away1`), and `shift` likewise (`shift0`, `shift1`): a part that turns 9 degrees
-- in a sample (a kobold's flinch) turns a 1.2 stud keep 0.19 studs off its line. Along each axis
-- the hull of the two ends is apart from `b` once both ends stand past one side of it; each end
-- moves on its own line, so the steps that part them there are the span both ends' bounds leave.
local function stepOutMoving(
	a0: CFrame,
	a1: CFrame,
	aSize: Vector3,
	b: CFrame,
	bSize: Vector3,
	away0: Vector3,
	away1: Vector3,
	from: number,
	allowed: number,
	shift0: Vector3,
	shift1: Vector3
): number
	local aHalf, bHalf = aSize * 0.5, bSize * 0.5
	local bX, bY, bZ = b.RightVector, b.UpVector, b.LookVector
	local bPosition = b.Position
	local p0, p1 = a0.Position + shift0, a1.Position + shift1
	local x0, y0, z0 = a0.RightVector, a0.UpVector, a0.LookVector
	local x1, y1, z1 = a1.RightVector, a1.UpVector, a1.LookVector
	local least = math.huge
	-- The least t at or past `from` with `c + t * slope` at or past `bound` on the side `sign` says
	-- (1: at or above, -1: at or below) for both ends: an interval of t, intersected.
	local function side(c0: number, s0: number, c1: number, s1: number, bound: number, sign: number): number
		local low, high = from, math.huge
		for _, line in { { c0, s0 }, { c1, s1 } } do
			local gap = (line[1] - bound) * sign
			local slope = line[2] * sign
			if slope == 0 then
				if gap < 0 then
					return math.huge
				end
			elseif slope > 0 then
				low = math.max(low, -gap / slope)
			else
				high = math.min(high, -gap / slope)
			end
		end
		return if low <= high then low else math.huge
	end
	local function along(axis: Vector3)
		local length = axis.Magnitude
		if length < 1e-6 or least <= from then
			return
		end
		local unit = axis / length
		local r0 = math.abs(x0:Dot(unit)) * aHalf.X
			+ math.abs(y0:Dot(unit)) * aHalf.Y
			+ math.abs(z0:Dot(unit)) * aHalf.Z
		local r1 = math.abs(x1:Dot(unit)) * aHalf.X
			+ math.abs(y1:Dot(unit)) * aHalf.Y
			+ math.abs(z1:Dot(unit)) * aHalf.Z
		local c0, c1 = p0:Dot(unit), p1:Dot(unit)
		local s0, s1 = away0:Dot(unit), away1:Dot(unit)
		local centre = bPosition:Dot(unit)
		local rb = math.abs(bX:Dot(unit)) * bHalf.X
			+ math.abs(bY:Dot(unit)) * bHalf.Y
			+ math.abs(bZ:Dot(unit)) * bHalf.Z
		-- Past b's far side (both ends' low bounds at or above it), or short of its near side.
		local above = side(c0 - r0, s0, c1 - r1, s1, centre + rb - allowed, 1)
		local below = side(c0 + r0, s0, c1 + r1, s1, centre - rb + allowed, -1)
		least = math.min(least, above, below)
	end
	for _, v in { bX, bY, bZ } do
		along(v)
	end
	for _, u in { x0, y0, z0, x1, y1, z1 } do
		along(u)
		for _, v in { bX, bY, bZ } do
			along(u:Cross(v))
		end
	end
	return least
end

-- One part of the body the engine collides (combat.contact.standOff.keepOut.parts): its size and
-- the joints from the root part out to it, and where on that part a box of its own sits (the
-- blade: keepOut.bladeDepthStuds), nil for the part's own box.
type BodyPart = { size: Vector3, links: { BladeContact.Link }, offset: CFrame? }

-- Each of `parts`' joint path from the model's root part (paths[i] for parts[i]; none for a part
-- no joint path reaches, an empty one for the root part itself).
local function jointPaths(model: Model, parts: { BasePart }): { [number]: { BladeContact.Link } }
	local root = model.PrimaryPart
	local paths: { [number]: { BladeContact.Link } } = {}
	if root == nil then
		return paths
	end
	local resolved = Joints.collect(model)
	local placing: { [BasePart]: Joints.Resolved } = {}
	for _, each in resolved do
		if placing[each.part1] == nil then
			placing[each.part1] = each
		end
	end
	for index, part in parts do
		local reversed: { BladeContact.Link } = {}
		local at: BasePart = part
		while at ~= root and #reversed <= #resolved do
			local joint = placing[at]
			if joint == nil then
				break
			end
			table.insert(reversed, { joint = joint.joint, c0 = joint.c0, c1Inverse = joint.c1:Inverse() })
			at = joint.part0
		end
		if at == root then
			local links: { BladeContact.Link } = {}
			for each = #reversed, 1, -1 do
				table.insert(links, reversed[each])
			end
			paths[index] = links
		end
	end
	return paths
end

-- The parts named `names` the model has, each with its joint path from the root part (a part no
-- joint path reaches is left out; the root part itself has none).
local function bodyParts(model: Model, names: { string }): { BodyPart }
	local found: { BasePart } = {}
	for _, name in names do
		local part = model:FindFirstChild(name)
		if part ~= nil and part:IsA("BasePart") then
			table.insert(found, part :: BasePart)
		end
	end
	local paths = jointPaths(model, found)
	local list: { BodyPart } = {}
	for index, part in found do
		local links = paths[index]
		if links ~= nil then
			table.insert(list, { size = part.Size, links = links })
		end
	end
	return list
end

-- The blade the trails draw (BladeContact.chain: TrailStart, the guard, to TrailEnd, the tip) as a
-- box with no width along it, on its part's joint path as the swing holds it (swingChain, D-537);
-- nil when the model holds none.
local function bladePart(model: Model): BodyPart?
	local blade = swingChain(model)
	if blade == nil then
		return nil
	end
	local guard, tip = blade.start.Position, blade.finish.Position
	local length = (tip - guard).Magnitude
	if length < 1e-6 then
		return nil
	end
	-- Its own Z along the blade (a frame built square to it, off whichever of the part's up and
	-- right axes the blade is nearer square to: lookAt has no answer for a blade along the part's
	-- up axis, as a sword's is).
	local look = (tip - guard) / length
	local helper = if math.abs(look.Y) < 0.5 then Vector3.new(0, 1, 0) else Vector3.new(1, 0, 0)
	local right = look:Cross(helper).Unit
	return {
		size = Vector3.new(0, 0, length),
		links = blade.links,
		offset = CFrame.fromMatrix((guard + tip) / 2, right, right:Cross(look), -look),
	}
end

-- The blade's own part (the Weapon part the trail's ends sit on, as the PC's logger reads it) as
-- a box on the same joint path (D-566); nil when the model holds none.
local function weaponBox(model: Model): BodyPart?
	local blade = swingChain(model)
	if blade == nil or #blade.links == 0 then
		return nil
	end
	local motor = blade.links[#blade.links].joint
	for _, resolved in Joints.collect(model) do
		if resolved.joint == motor then
			return { size = resolved.part1.Size, links = blade.links }
		end
	end
	return nil
end

-- A keep-out plan (keepOutOf): how far back along `away`, and aside along `side`, the body stands
-- at a clip time.
type KeepOut = {
	keep: (clipTime: number) -> number,
	side: Vector3?,
	keepSide: ((clipTime: number) -> number)?,
	-- How long a stance's pose waits on its first pose (D-691), in clip seconds.
	wait: number,
}

-- Poses `list` (from its `first`-th on, all by default) with the root at `rootFrame` and the clip's
-- joints at `offsets` into `into`.
local function placeParts(
	list: { BodyPart },
	rootFrame: CFrame,
	offsets: ClipSampler.Offsets,
	into: { CFrame },
	first: number?
)
	for index = first or 1, #list do
		local body = list[index]
		local frame = rootFrame
		for _, link in body.links do
			local offset = offsets[link.joint.Name]
			local transform = if offset ~= nil then ClipSampler.toCFrame(offset) else CFrame.identity
			frame = frame * link.c0 * transform * link.c1Inverse
		end
		into[index] = if body.offset ~= nil then frame * body.offset else frame
	end
end

-- `offsets` (the swing `clip`'s own sample at clip time `at`) with the swinger's own Additive layers
-- on top (D-683), each `elapsed` seconds of its clock on from where the plan found it (a loop round
-- its cycle; a one-shot past its end adds nothing), at its weight and mask as the rig's mixer adds
-- it, one that yields giving way under the swing's strike there (D-685). A new table.
local function withOwn(
	offsets: ClipSampler.Offsets,
	layers: { OwnLayer },
	elapsed: number,
	clip: Types.ClipDef,
	at: number
): ClipSampler.Offsets
	local result = offsets
	local share = ClipSampler.breathYield(clip, at)
	for _, layer in layers do
		local duration = layer.clip.duration
		local clock = layer.time + elapsed * layer.speed
		if layer.clip.loop and duration > 0 then
			clock %= duration
		elseif clock > duration then
			continue
		end
		local sample = ClipSampler.sample(layer.clip, clock)
		local mask = if layer.yields == true then ClipSampler.yieldMask(share, layer.mask) else layer.mask
		if mask == nil then
			result = ClipSampler.add(result, sample, layer.weight)
		else
			for name, offset in sample do
				result = ClipSampler.add(result, { [name] = offset }, layer.weight * (mask[name] or 1))
			end
		end
	end
	return result
end

-- A strike the reach is kept out at (keepOutOf): the clip time its hit-stop holds (`key`), and the
-- span the body takes its step over (`start` to `ready`: from the strike before, or the release,
-- to where its snap begins), and the step once it is known, with the aside it was found at.
type Strike = { key: number, start: number, ready: number, need: number?, aside: number }

-- The keep-out (D-314) of a swing whose body stands at `rootCFrame` at clip time `from` and steps
-- `distance` along `away` from clip time `stepFrom` to `to` (the blade step, D-604): how much farther along `away` the
-- body stands at each clip time, and how far aside, so that no colliding part goes deeper into the
-- target's blocker (as its faces stood when the plan was made) than at `from`, and none deeper
-- than depthEpsilon from the first cut's key on (item 286: a freeze holds no overlap; a stance's
-- from its start, D-687). The body's face (keepOut.bodyFace) holds the body back along `away`. A face over a part the target holds
-- (keepOut.heldFace, D-315: a kobold's axe, which hangs beside a body at its front) holds it back
-- or aside, whichever is the shorter step: aside along `side`, square to `away` and off the held
-- face nearest the root (a lean into an axe beside the body is undone by a step off it, not by
-- backing past its far end). Both only ever grow, so a freeze holds where the body stands, and the
-- step, the back and the aside together stay within keepOut.maxStuds. The clip is posed every
-- sampleSeconds, each clip time once, as the swing first asks for it (a frame pays for one pose,
-- not the release for the whole clip); each sample keeps out what every part sweeps from the
-- sample before (the hull of the two poses), and a clip time between two samples reads one sample
-- ahead, so the body is back before the pose goes in; a sample whose parts turn fast (a spin) is
-- swept in pieces, none turning more than maxTurnDegrees, so the hulls hold the arc.
--
-- The reach (D-424): at each strike's key (ContactPredictor.strikeKey, the pose the hit-stop
-- holds) the blade (BladeContact.chain, guard to tip) stands no deeper in any of the target's body
-- parts (`hurt`: what the blade may wound, as they stood when the plan was made) than
-- keepOut.bladeDepthStuds, or than it stood at `from` when a touch at the start pose put it
-- deeper, and no hand or arm (keepOut.limbs) deeper than it stood at `from`: the cut meets the
-- body at its surface and never sinks to its root. The body takes that step back over the strike's
-- anticipation, from the strike before (or the release) to where its snap begins, on
-- standOff.easing, as the blade step does, and is still through the hit-stop; the step a key posed
-- again in its cut calls for (an aside that grew there) is taken in the frames left to it. The
-- reach never carries the body back faster than the sprint cap (maxSpeedStudsPerSecond, with the
-- aside's step that sample counted in), and no key steps farther than it reaches by then. A step
-- has a price, a keepOut.stepPerDepth-th of a stud of depth for each stud of ground: of the steps
-- of standOff.stepStuds, at most standOff.maxStuds a strike, the plan takes the one whose price
-- and the depth it leaves past those come to least (the least step that keeps the key out, unless
-- a shorter one leaves it a hair deep for far less ground, or none that short does: a blade beside
-- the body whose step back carries it into the torso, or along an arm whose end is a stud and more
-- away). The key is posed when the swing first reaches that strike's anticipation, and again when
-- the aside grows before the key. The reach is a ramp of its own and needs no head start, so a
-- frame reads it at its own clip time, not a sample ahead.
--
-- The hands (D-501): on every sample, as the colliding parts are, no hand or arm (keepOut.limbs)
-- stands deeper than depthEpsilon in any of those body parts through all it sweeps from the
-- sample before (a hand or arm that swings fast is cut into pieces, as a spin is): the reach is
-- priced at the keys, where a blade deep at every step hid a hand under its price, and nothing
-- held a hand out between keys. Nil when the target has no blocker.
local function keepOutOf(
	model: Model,
	clip: Types.ClipDef,
	from: number,
	rootCFrame: CFrame,
	target: Model,
	away: Vector3,
	distance: number,
	to: number,
	stepFrom: number,
	hurt: { BasePart },
	poseLag: number,
	motion: TargetMotion?,
	stance: number?,
	stillUntil: number?,
	own: { OwnLayer }?
): KeepOut?
	-- The faces as they stand now: a frame, a size and whether it is over a held part, each.
	local faceFrames: { CFrame } = {}
	local faceSizes: { Vector3 } = {}
	local faceHeld: { boolean } = {}
	for _, child in target:GetChildren() do
		if child:IsA("BasePart") and (child.Name == KEEP_OUT.bodyFace or child.Name == KEEP_OUT.heldFace) then
			table.insert(faceFrames, (child :: BasePart).CFrame)
			table.insert(faceSizes, (child :: BasePart).Size)
			table.insert(faceHeld, child.Name == KEEP_OUT.heldFace)
		end
	end
	if #faceFrames == 0 then
		return nil
	end
	local parts = bodyParts(model, KEEP_OUT.parts)
	local budget: number = KEEP_OUT.maxStuds
	local most = math.max(0, budget - distance)
	if #parts == 0 or most <= 0 then
		return nil
	end
	-- A stance's start pose blends in over the clip's blendIn from the pose the body stood in, the
	-- drawn idle, whose 0 s pose every Art's first pose is (D-694): until the blend is over the
	-- screen draws the colliding parts between the two, so the stance keeps them out in its first
	-- pose too, on each sample's root (parts[formed + 1] on: the same parts again). Its step and the
	-- clip's own motion parted the clip's pose from the axe's blocker while that first pose stood
	-- up to 0.020 in it on the same rows, and the drawn Head 0.006 at 144 Hz (Horizontal at 2.65,
	-- square ahead of a kobold turned 8).
	local formed = #parts
	local blendIn: number = clip.blendIn or ChoreoData.blendIn
	if stance ~= nil and blendIn > 0 then
		for index = 1, formed do
			table.insert(parts, parts[index])
		end
	end
	local firstOffsets = ClipSampler.sample(clip, from)
	-- Aside: square to `away`, off the held face nearest the root (none when the root stands square
	-- in front of it).
	local side: Vector3? = nil
	local nearest = math.huge
	local square = Vector3.new(-away.Z, 0, away.X)
	for face, faceFrame in faceFrames do
		if faceHeld[face] then
			local offset = faceFrame:PointToObjectSpace(rootCFrame.Position)
			local half = faceSizes[face] * 0.5
			local gap =
				Vector3.new(math.max(math.abs(offset.X) - half.X, 0), 0, math.max(math.abs(offset.Z) - half.Z, 0))
			local lean = (rootCFrame.Position - faceFrame.Position):Dot(square)
			if gap.Magnitude < nearest and math.abs(lean) > 1e-6 then
				nearest = gap.Magnitude
				side = if lean > 0 then square else -square
			end
		end
	end
	local start = ClipSampler.rootMotionAt(clip, from)
	local frames: { CFrame } = table.create(#parts)
	-- The parts as the sample before stood, then as each piece of the way between the two stands
	-- (what each sweeps through: chain[1] to chain[pieces + 1], the last the sample itself).
	local before: { CFrame } = table.create(#parts)
	local chain: { { CFrame } } = { before }
	local pieces = 1
	-- The reach: the hands and arms, then the blade, against the target's body parts as they stand
	-- now (none when it has none), and the strikes it is kept out at.
	local reach: { BodyPart } = {}
	local hurtFrames: { CFrame } = {}
	local hurtSizes: { Vector3 } = {}
	for _, part in hurt do
		table.insert(hurtFrames, part.CFrame)
		table.insert(hurtSizes, part.Size)
	end
	-- The target moves on through the swing (D-565: told how, options.target).
	local targetRoot = target.PrimaryPart
	local moving = motion ~= nil
		and (motion.base ~= nil or motion.flinch ~= nil)
		and targetRoot ~= nil
		and #hurtFrames > 0
	local bladeIndex = 0
	local weaponIndex = 0
	local strikes: { Strike } = {}
	-- A stance (D-606) plans no strike: its clip ends at the hold pose.
	local endTime = math.min(clip.duration, stance or math.huge)
	if #hurtFrames > 0 then
		reach = bodyParts(model, KEEP_OUT.limbs)
		local blade = if stance == nil then bladePart(model) else nil
		if blade ~= nil then
			table.insert(reach, blade)
			bladeIndex = #reach
			-- The blade's own part, held out between the cuts of a swing at a target that moves on
			-- onto it (D-566); a still body is the clip's own follow-through's to leave (D-493).
			local box = if moving then weaponBox(model) else nil
			if box ~= nil then
				table.insert(reach, box)
				weaponIndex = #reach
			end
		end
		-- An Art's first strike takes its step once the activation hold is over, as the blade step
		-- does (D-604): from the first sample at or past the hold's end, so a frame between two
		-- samples in the hold reads none of it (the speed's lead below starts a long one sooner).
		local holdEnd = holdEndOf(clip)
		local sample: number = KEEP_OUT.sampleSeconds
		local last = if holdEnd ~= nil and holdEnd > from
			then from + math.ceil((holdEnd - from) / sample - KEY_EPSILON) * sample
			else from
		for _, window in ClipSampler.hitWindows(clip) do
			local key = ContactPredictor.strikeKey(clip, window)
			if key > from + KEY_EPSILON and key <= endTime then
				-- Where the strike's snap begins: the key before its own (the window's open for a
				-- window with no snap); the step is taken before it, or through the snap when the
				-- strike follows the one before with no anticipation between.
				local snap = window.open
				for index = 2, #clip.keys do
					if
						math.abs(clip.keys[index].time - key) <= KEY_EPSILON and ClipSampler.isStrikeSnap(clip, index)
					then
						snap = clip.keys[index - 1].time
					end
				end
				local ready = if snap > last + KEY_EPSILON then math.min(snap, key) else key
				table.insert(strikes, { key = key, start = last, ready = ready, aside = 0 })
				last = key
			end
		end
	end
	-- The clip's authored holds after its strike snaps (ClipSampler.strikeHoldAfter), as clip-time
	-- spans: a contact's hit-stop stands in for one, and the step after the hit-stop skips it in a
	-- single frame (Mixer.hitStop), so what the series grew across one would land in that frame
	-- (D-427: Sharp Nail stepped back 0.50 studs in the frame after its second cut's freeze at
	-- 60 Hz). The series grows none of its way inside them.
	local stills: { { number } } = {}
	local keys = clip.keys
	for index = 3, #keys do -- index: a hold key, after its snap key and the key before that
		if keys[index].easing == "Hold" and ClipSampler.isStrikeSnap(clip, index - 1) then
			table.insert(stills, { keys[index - 1].time, keys[index].time })
		end
	end
	-- The clip time from `first` to `last` outside those holds.
	local function openBetween(first: number, last: number): number
		local open = last - first
		for _, span in stills do
			open -= math.max(0, math.min(last, span[2]) - math.max(first, span[1]))
		end
		return math.max(open, 0)
	end
	-- And outside the activation hold a swing planned before its end waits for (StandOff.still,
	-- D-604): the tell holds still in every direction, so the keep-out grows none of its way, back or
	-- aside, before `stillUntil` (D-631). The target's clock still runs through it (openBetween).
	local function growBetween(first: number, last: number): number
		if stillUntil == nil or last <= first then
			return openBetween(first, last)
		end
		return openBetween(math.clamp(stillUntil, first, last), last)
	end
	-- The target as its clips carry it on through the swing (D-565, StandOffOptions.target): each
	-- body part on its joint path from the target's root, posed at a clip time of the swing by the
	-- Base clip on from its clock (the target's clock stands still through a hit-stop, as the
	-- swing's does, and runs on through the hold the step after it skips, so it runs the swing's
	-- clock outside those holds) and the flinch from the latest strike's key on (Replication plays
	-- it on the hit's word, which comes inside the key's hold: it starts as the hold ends), times
	-- what the part stood off that pose when the plan was made (a part as it stands at the start).
	-- The PC's held kobold idled and flinched through the swing at its walk-in rests: Basic3's right
	-- arm 0.12-0.20 studs into its torso, Horizontal's 0.053 (item 461), against a plan that held
	-- the hands out of the torso as it stood when the swing began.
	-- Its root as it stands now, as its parts are read (the plan is posed lazily, frames later).
	local targetFrame: CFrame = if targetRoot ~= nil then targetRoot.CFrame else CFrame.identity
	local hurtLinks: { [number]: { BladeContact.Link } } = {}
	local hurtFixes: { CFrame } = {}
	local function targetOffsets(time: number): ClipSampler.Offsets
		local moves = motion :: TargetMotion
		local offsets: ClipSampler.Offsets = {}
		local base = moves.base
		if base ~= nil then
			local duration = base.clip.duration
			local clock = base.time + openBetween(from, time) * base.speed
			clock = if base.clip.loop and duration > 0 then clock % duration else math.clamp(clock, 0, duration)
			offsets = ClipSampler.sample(base.clip, clock)
		end
		local flinch = moves.flinch
		if flinch ~= nil then
			local struck: number? = nil
			for _, strike in strikes do
				if strike.key <= time + KEY_EPSILON then
					struck = strike.key
				end
			end
			if struck ~= nil then
				local into = openBetween(struck, time)
				if into < flinch.duration then
					offsets = ClipSampler.add(offsets, ClipSampler.sample(flinch, into), 1)
				end
			end
		end
		return offsets
	end
	-- The target's body parts at clip time `time` (no earlier than `from`) into `into`.
	local function placeTarget(time: number, into: { CFrame })
		local offsets = targetOffsets(math.max(time, from))
		for part in hurtFrames do
			local frame = targetFrame
			local links = hurtLinks[part]
			if links ~= nil then
				for _, link in links do
					local offset = offsets[link.joint.Name]
					local transform = if offset ~= nil then ClipSampler.toCFrame(offset) else CFrame.identity
					frame = frame * link.c0 * transform * link.c1Inverse
				end
			end
			into[part] = frame * (hurtFixes[part] or CFrame.identity)
		end
	end
	if moving then
		hurtLinks = jointPaths(target, hurt)
		local posed: { CFrame } = table.create(#hurtFrames)
		placeTarget(from, posed)
		for part, frame in hurtFrames do
			hurtFixes[part] = posed[part]:Inverse() * frame
		end
	end
	-- The target at clip time `time`: a fresh table while it moves, its parts as they stand else.
	local function targetAt(time: number): { CFrame }
		if not moving then
			return hurtFrames
		end
		local into: { CFrame } = table.create(#hurtFrames)
		placeTarget(time, into)
		return into
	end
	-- The blade's own part between the cuts (D-566), at a target that moves on: from
	-- keepOut.bladeOutSeconds after a strike's hold (its key when it has none: the follow-through's
	-- exit, D-484) to the next strike's snap or the clip's end, no point of it stands deeper than
	-- depthEpsilon in a body part, on every sample, as posed and as drawn (the clip-time spans
	-- `outs`). The reach holds only the trail's line, and only at the keys: Basic1's blade stood
	-- 0.19-0.40 studs into the PC's idling, flinching kobold at clip 0.283, after its cut, and still
	-- in at the clip's end (item 464). A body that stands still is left to the clip: its
	-- follow-through carries the blade out by itself (FollowThrough's Late rule, D-493).
	local outs: { { number } } = {}
	if weaponIndex > 0 then
		local cuts: { { number } } = {}
		for _, window in ClipSampler.hitWindows(clip) do
			local key = ContactPredictor.strikeKey(clip, window)
			local snap = window.open
			for index = 2, #keys do
				if math.abs(keys[index].time - key) <= KEY_EPSILON and ClipSampler.isStrikeSnap(clip, index) then
					snap = keys[index - 1].time
				end
			end
			local hold = ClipSampler.strikeHoldAfter(clip, key)
			table.insert(cuts, { snap, if hold ~= nil then keys[hold].time else key })
		end
		for index, cut in cuts do
			local after = cuts[index + 1]
			table.insert(outs, { cut[2] + KEEP_OUT.bladeOutSeconds, if after ~= nil then after[1] else math.huge })
		end
	end
	-- True when clip times `first` to `last` lie wholly in one of those spans.
	local function betweenCuts(first: number, last: number): boolean
		for _, span in outs do
			if first >= span[1] - KEY_EPSILON and last <= span[2] + KEY_EPSILON then
				return true
			end
		end
		return false
	end
	-- Poses the colliding parts at clip time `time` (the clip's root motion and the blade step)
	-- into `into`, and the reach into `reachInto`; with `lag`, the joints as they stood that long
	-- before (no earlier than `from`) on the root of `time`: what the screen draws then (D-535).
	-- The swinger's own Additive layers go on top (D-683), each on from its clock by the swing's
	-- clock outside the authored holds a hit-stop skips (their clocks stand still through the
	-- freeze with the swing's and skip none of it after: openBetween, as the target's base runs).
	local function pose(time: number, into: { CFrame }?, reachInto: { CFrame }?, lag: number?)
		local motion = ClipSampler.rootMotionAt(clip, time)
		local stepped = AimLogic.standOffAt(distance, stepFrom, to, time, STAND_OFF.easing)
		local rootFrame = rootCFrame * CFrame.new(motion[1] - start[1], motion[2] - start[2], motion[3] - start[3])
			+ away * stepped
		local at = if lag ~= nil then math.max(time - lag, from) else time
		local offsets = ClipSampler.sample(clip, at)
		if own ~= nil then
			offsets = withOwn(offsets, own, openBetween(from, at), clip, at)
		end
		if into ~= nil then
			placeParts(parts, rootFrame, offsets, into)
			if #parts > formed and time - from < blendIn then
				placeParts(parts, rootFrame, firstOffsets, into, formed + 1)
			end
		end
		if reachInto ~= nil then
			placeParts(reach, rootFrame, offsets, reachInto)
		end
	end
	local reachFrames: { CFrame } = table.create(#reach)
	pose(from, frames, if #reach > 0 then reachFrames else nil)
	local deepest = 0
	for index, body in parts do
		for face, faceFrame in faceFrames do
			deepest = math.max(deepest, boxDepth(frames[index], body.size, faceFrame, faceSizes[face]))
		end
	end
	-- How deep a part may stand: as deep as the swing found it until its first cut's key, and out
	-- (depthEpsilon) from then on (item 286): a freeze holds the body where its key stands, and an
	-- overlap held there is the engine's to push out through the freeze (Rising Arc at a side-on
	-- boar crept 0.034-0.038 studs a frame in Studio). The lead below starts that step early.
	-- A stance (D-606) allows depthEpsilon from the start (D-687): its hold is a freeze too, and
	-- the engine pushed a part the press found in the target's blocker out on the stance's rows
	-- along that face, toward the target with it where the face stands turned to the line (the
	-- axe's beside a kobold, 0.07-0.14 of the push), so the press steps the part out itself as the
	-- start pose forms, never toward the target, within the keep-out's speed.
	-- It holds them to keepOut.stanceDepthStuds (D-691): under the held rows' bar with room for
	-- a pose drawn between two samples, which bows off their sweep (Rising Arc's torso 0.0004 past
	-- it at 144 Hz).
	local startAllowed = if stance ~= nil then KEEP_OUT.stanceDepthStuds else deepest + KEEP_OUT.depthEpsilon
	local allowed = startAllowed
	local firstKey = math.huge
	for _, window in ClipSampler.hitWindows(clip) do
		local key = ContactPredictor.strikeKey(clip, window)
		if key > from + KEY_EPSILON then
			firstKey = math.min(firstKey, key)
		end
	end
	-- How deep a piece of the reach, posed at `frame` and moved by `moved`, stands in body part
	-- `part` (as `against` has the target's parts): a hand or an arm the boxes' overlap (boxDepth),
	-- the blade its deepest point's distance in from the part's nearest face (segmentDepth), how
	-- buried it looks: a blade along a thin arm a hair under its skin is not one through it.
	local function depthIn(index: number, frame: CFrame, moved: Vector3, part: number, against: { CFrame }): number
		local hurtFrame = against[part]
		if index ~= bladeIndex then
			return boxDepth(frame + moved, reach[index].size, hurtFrame, hurtSizes[part])
		end
		local half = frame.LookVector * (reach[index].size.Z * 0.5)
		local middle = frame.Position + moved
		return segmentDepth(middle - half, middle + half, hurtFrame, hurtSizes[part] * 0.5)
	end
	-- How deep each piece of the reach may stand in each body part (reachAllowed[index][part]),
	-- read off the start pose the first time a strike's key brings the two near each other.
	local startFrames = table.clone(reachFrames)
	local reachAllowed: { { number } } = table.create(#reach)
	for index in reach do
		reachAllowed[index] = {}
	end
	local function allowedOf(index: number, part: number): number
		local known = reachAllowed[index][part]
		if known ~= nil then
			return known
		end
		local floor: number = if index == bladeIndex then KEEP_OUT.bladeDepthStuds else 0
		local depth = math.max(depthIn(index, startFrames[index], Vector3.zero, part, hurtFrames), floor)
			+ KEEP_OUT.depthEpsilon
		reachAllowed[index][part] = depth
		return depth
	end
	-- Each piece's and each body part's bounding radius: a pair whose spheres never meet over a
	-- strike's steps stands apart at every one of them (no depth), so its key leaves it out.
	local reachRadii: { number } = table.create(#reach)
	for index, piece in reach do
		reachRadii[index] = piece.size.Magnitude * 0.5
	end
	local hurtRadii: { number } = table.create(#hurtSizes)
	for part, size in hurtSizes do
		hurtRadii[part] = size.Magnitude * 0.5
	end
	-- The hands and arms on every sample (D-501): as the sample before stood, then as each piece of
	-- the way between the two stands, as `chain` holds the colliding parts.
	local limbBefore: { CFrame } = table.clone(reachFrames)
	local limbChain: { { CFrame } } = { limbBefore }
	local limbNow: { CFrame } = table.clone(reachFrames)
	-- And as the screen draws them (D-535): a frame draws the pose of `poseLag` before on the root
	-- of now (a root write shows on its own frame, a pose a frame later, D-342), so through a lunge
	-- the root carries the hands that far past where the pose has them: Horizontal's right arm at
	-- the kobold's walk-in rest stood 0.001 studs in as posed and 0.065 in as drawn at 60 Hz (0.103
	-- turned 10.35 degrees; the PC read 0.090). Its own pieces (`drawnPieces`), as `pieces` are.
	local drawn = #reach > 0 and poseLag > 0
	local drawnBefore: { CFrame } = table.clone(reachFrames)
	local drawnChain: { { CFrame } } = { drawnBefore }
	local drawnNow: { CFrame } = table.clone(reachFrames)
	local drawnPieces = 1
	-- The least step back at or past `at` (with the body `shift` aside) that leaves every hand and
	-- arm, through all it sweeps from the sample before, at most depthEpsilon deep in any of the
	-- target's body parts: a follow-through or a snap between two strike keys carries a hand as
	-- deep as a key does (item 331(a): 0.31-0.54 studs in a side-on boar's torso after Horizontal,
	-- Rising Arc and Sharp Nail cuts) with no key there to step it, and a hold pose drawn in at the
	-- shell's rest starts one inside (Rising Arc's right hand 0.21 studs in a side-on boar's torso),
	-- which the first samples step out of at the speed cap. A pair whose bounding spheres stand
	-- apart at `at` stands apart (the step is `at`).
	--
	-- While the target moves (D-565) each sweep is of the two bodies' relative motion: the
	-- target's parts at each piece's clip time (`targetChain`, and `drawnTargetChain` as the screen
	-- draws them, the pose `poseLag` before), and the blade's own part joins the hands between the
	-- cuts (D-566: `weaponOut`, `drawnWeaponOut`).
	local targetChain: { { CFrame } }? = nil
	local drawnTargetChain: { { CFrame } }? = nil
	local weaponOut, drawnWeaponOut = false, false
	local function limbOut(at: number, shift: Vector3): number
		local need = at
		local moved = away * at + shift
		-- One sweep (`links`, `count` pieces) of one hand or arm past one body part.
		local function sweepOut(
			links: { { CFrame } },
			count: number,
			index: number,
			piece: BodyPart,
			part: number,
			targets: { { CFrame } }?
		)
			local hurtFrame = if targets ~= nil then targets[count + 1][part] else hurtFrames[part]
			local reachOf = reachRadii[index] + hurtRadii[part]
			local near = false
			for each = 1, count + 1 do
				local centre = if targets ~= nil then targets[each][part].Position else hurtFrame.Position
				if (links[each][index].Position + moved - centre).Magnitude <= reachOf then
					near = true
					break
				end
			end
			if not near then
				return
			end
			local deep: number = KEEP_OUT.depthEpsilon
			if targets == nil then
				for each = 1, count do
					need = math.max(
						need,
						stepOut(
							links[each][index],
							links[each + 1][index],
							piece.size,
							hurtFrame,
							hurtSizes[part],
							away,
							at,
							deep,
							shift
						)
					)
				end
				return
			end
			-- Each end as it stands to the part at its own clip time, carried with the part to where
			-- the sweep leaves it, the step and the aside turned with it.
			local carry = hurtFrame * targets[1][part]:Inverse()
			local first, firstAway, firstShift =
				carry * links[1][index], carry:VectorToWorldSpace(away), carry:VectorToWorldSpace(shift)
			for each = 1, count do
				carry = hurtFrame * targets[each + 1][part]:Inverse()
				local last, lastAway, lastShift =
					carry * links[each + 1][index], carry:VectorToWorldSpace(away), carry:VectorToWorldSpace(shift)
				need = math.max(
					need,
					stepOutMoving(
						first,
						last,
						piece.size,
						hurtFrame,
						hurtSizes[part],
						firstAway,
						lastAway,
						at,
						deep,
						firstShift,
						lastShift
					)
				)
				first, firstAway, firstShift = last, lastAway, lastShift
			end
		end
		for index, piece in reach do
			local isWeapon = index == weaponIndex
			if index == bladeIndex or (isWeapon and not weaponOut and not drawnWeaponOut) then
				continue
			end
			for part in hurtFrames do
				if weaponOut or not isWeapon then
					sweepOut(limbChain, pieces, index, piece, part, targetChain)
				end
				if drawn and (drawnWeaponOut or not isWeapon) then
					sweepOut(drawnChain, drawnPieces, index, piece, part, drawnTargetChain)
				end
			end
		end
		return need
	end
	-- The pairs a strike's key could bring together (piece, part, flattened), its allowed depth each.
	local nearPieces: { number } = {}
	local nearParts: { number } = {}
	local nearAllowed: { number } = {}
	-- How much deeper than allowed the near pairs, as posed in reachFrames, stand at their worst with
	-- the body stepped `back` and `shift` aside (0 or less when each is within its depth), or the
	-- first excess at or past `enough` (a step that can do no better than one already found). A
	-- depth moves no farther than the body does (each is a least distance to a face along unit
	-- axes), so a pair last found well under the worst at a step nearby is not posed again: what it
	-- was, plus how far the body has moved since, bounds it. The pair that was worst last time is
	-- tried first: it is most often the one that settles it.
	local worstPair = 1
	-- The target's parts at the key being priced (strikeStep): where its clips carry them by then.
	local keyHurt: { CFrame } = hurtFrames
	local pairExcess: { number } = {}
	local pairBack: { number } = {}
	local function reachExcess(back: number, shift: Vector3, enough: number): number
		local moved = away * back + shift
		local function excessOf(pair: number): number
			local index = nearPieces[pair]
			local excess = depthIn(index, reachFrames[index], moved, nearParts[pair], keyHurt) - nearAllowed[pair]
			pairExcess[pair], pairBack[pair] = excess, back
			return excess
		end
		local worst = excessOf(worstPair)
		if worst >= enough then
			return worst
		end
		for pair in nearPieces do
			if pair == worstPair then
				continue
			end
			local known = pairExcess[pair]
			if known ~= nil and known + math.abs(back - pairBack[pair]) <= math.max(worst, 0) then
				continue
			end
			local excess = excessOf(pair)
			if excess > worst then
				worst, worstPair = excess, pair
				if worst >= enough then
					return worst
				end
			end
		end
		return worst
	end
	-- The step back at or past `at`, and no farther than `top`, a strike's key calls for (see
	-- above): of the steps of stepStuds, the one whose depth past what the key may (0 when within)
	-- and price (a stepPerDepth-th of the ground it covers) come to least, the shorter on a tie. A
	-- step that clears the key ends the search (each farther one costs more), and so does one whose
	-- price alone comes to the least found.
	local reachStep: number = STAND_OFF.stepStuds
	local reachMost: number = STAND_OFF.maxStuds
	local reachPrice: number = KEEP_OUT.stepPerDepth
	local function strikeStep(key: number, at: number, shift: Vector3, top: number): number
		pose(key, nil, reachFrames)
		keyHurt = targetAt(key)
		local steps = math.floor(math.max(math.min(reachMost, most - at, top - at), 0) / reachStep + 1e-6)
		-- The pairs whose spheres meet somewhere along the steps; none: the key is clear as it is.
		table.clear(nearPieces)
		table.clear(nearParts)
		table.clear(nearAllowed)
		local reachLine = away * (steps * reachStep)
		for index, frame in reachFrames do
			if index == weaponIndex then
				continue
			end
			local first = frame.Position + away * at + shift
			for part, hurtFrame in keyHurt do
				local along = math.clamp(
					(hurtFrame.Position - first):Dot(reachLine) / math.max(reachLine:Dot(reachLine), 1e-6),
					0,
					1
				)
				local gap = (first + reachLine * along - hurtFrame.Position).Magnitude
				if gap <= reachRadii[index] + hurtRadii[part] then
					table.insert(nearPieces, index)
					table.insert(nearParts, part)
					table.insert(nearAllowed, allowedOf(index, part))
				end
			end
		end
		if #nearPieces == 0 then
			return at
		end
		worstPair = 1
		table.clear(pairExcess)
		table.clear(pairBack)
		local best, bestCost = at, math.huge
		for k = 0, steps do
			local price = k * reachStep / reachPrice
			if price >= bestCost - 1e-6 then
				break
			end
			local back = at + k * reachStep
			local excess = reachExcess(back, shift, bestCost - price - 1e-6)
			if math.max(excess, 0) + price < bestCost - 1e-6 then
				best, bestCost = back, math.max(excess, 0) + price
			end
			if excess <= 0 then
				break
			end
		end
		return best
	end
	local step: number = KEEP_OUT.sampleSeconds
	local count = math.max(0, math.ceil((endTime - from) / step - 1e-6))
	-- back[k + 1], aside[k + 1]: the keep-out at sample k (clip time from + k * step); sample 0 is
	-- the start.
	local back: { number } = { 0 }
	local aside: { number } = { 0 }
	local currentBack, currentAside = 0, 0
	local done = false
	-- The least step along `direction` at or past `at` that leaves every part's sweep clear of the
	-- face (`shift`: where the other keep-out already put it).
	local function stepOf(face: number, direction: Vector3, at: number, shift: Vector3): number
		local need = at
		for piece = 1, pieces do
			local fromFrames, toFrames = chain[piece], chain[piece + 1]
			for index, body in parts do
				need = math.max(
					need,
					stepOut(
						fromFrames[index],
						toFrames[index],
						body.size,
						faceFrames[face],
						faceSizes[face],
						direction,
						at,
						allowed,
						shift
					)
				)
			end
		end
		return need
	end
	-- The most any part turns between two poses (its axes' largest angle), in degrees: a part that
	-- turns sweeps out past the hull of its two boxes, by a hair for a small turn.
	local function turnOf(a: { CFrame }, b: { CFrame }, n: number, extra: number?): number
		local most = 1
		for count = 1, if extra ~= nil then n + 1 else n do
			local index = if count > n then extra :: number else count
			local x, y = a[index], b[index]
			most = math.min(
				most,
				x.RightVector:Dot(y.RightVector),
				x.UpVector:Dot(y.UpVector),
				x.LookVector:Dot(y.LookVector)
			)
		end
		return math.deg(math.acos(math.clamp(most, -1, 1)))
	end
	-- How far back the reach holds the body at clip time `time` with the body `sideways` aside:
	-- each strike's step, taken over its anticipation (a strike's key is posed the first time a
	-- sample reaches its start, and again, from the step it found, when the aside grows before the
	-- key: a step aside can carry the blade deeper), never faster than the sprint cap from `body`,
	-- where the body stood `span` seconds before, with what the aside took this sample
	-- (`sidestep`) spent of it. A key is stepped no farther than the cap reaches by then: an aside
	-- that grows in the cut leaves its step only the frames to the key.
	local function reachAt(
		time: number,
		at: number,
		sideways: number,
		body: number,
		span: number,
		sidestep: number
	): number
		local held = 0
		for _, strike in strikes do
			if time < strike.start - KEY_EPSILON then
				break
			end
			local shift = if side ~= nil then side * sideways else Vector3.zero
			local top = body + SPRINT * (strike.key - time + span)
			if strike.need == nil then
				strike.need = strikeStep(strike.key, math.max(at, held), shift, top)
				strike.aside = sideways
			elseif sideways > strike.aside + 1e-6 and time <= strike.key + KEY_EPSILON then
				strike.need = strikeStep(strike.key, math.max(strike.need :: number, held), shift, top)
				strike.aside = sideways
			end
			local need = strike.need :: number
			held = held + AimLogic.standOffAt(need - held, strike.start, strike.ready, time, STAND_OFF.easing)
		end
		local stride = SPRINT * span
		return math.min(held, body + math.sqrt(math.max(stride * stride - sidestep * sidestep, 0)))
	end
	-- How many pieces a sweep from clip time `first` to `last` takes for the target's own motion
	-- (D-565), its parts at `start` and `finish`: their turn on top of `turn` (the turn of the
	-- sweep's own parts: the two bodies' relative turn is at most both), and enough that the bow of
	-- their path off the straight line, read at the middle, is at most depthEpsilon a piece (a bow
	-- shrinks as the square of the pieces). A kobold's flinch swings its arm 9 degrees and bends
	-- its torso's path 0.011 studs in one 60 Hz sample.
	local function targetPieces(
		start: { CFrame },
		finish: { CFrame },
		first: number,
		last: number,
		turn: number
	): number
		local bow = 0
		for part, frame in targetAt((first + last) / 2) do
			bow = math.max(bow, (frame.Position - (start[part].Position + finish[part].Position) * 0.5).Magnitude)
		end
		local count = math.max(
			math.ceil((turn + turnOf(start, finish, #hurtFrames)) / KEEP_OUT.maxTurnDegrees),
			math.ceil(math.sqrt(bow / KEEP_OUT.depthEpsilon))
		)
		return math.clamp(count, 1, KEEP_OUT.maxPieces)
	end
	-- Out of the body's face first, then the held ones, then the body's again for what an aside step
	-- changed: a few rounds settle it. From back `b` and aside `a`, over the sweep `chain` holds.
	local function facesOut(b: number, a: number): (number, number)
		for _ = 1, KEEP_OUT.rounds do
			local wasBack, wasAside = b, a
			for face in faceFrames do
				local sideways = if side ~= nil then side * a else Vector3.zero
				local backward = stepOf(face, away, b, sideways)
				if faceHeld[face] and side ~= nil then
					local sideStep = stepOf(face, side, a, away * b)
					if sideStep - a < backward - b then
						a = sideStep
						continue
					end
				end
				b = backward
			end
			if b == wasBack and a == wasAside then
				break
			end
		end
		return b, a
	end
	-- The poses an Art's activation hold plays after its hold pose, up to the hold's end (D-671):
	-- the release runs the clip on through them inside the tell, and a swing planned there takes
	-- only a hold sample's own need out on the hold rows (D-631), so a stance (D-606), planned to
	-- the hold pose, keeps them out as well: the hold pose's step back takes their need with it.
	-- Horizontal's hold opens the free hand on toward the target: at item 522's rests it went from
	-- 0.005 to 0.0105 into the kobold's torso, and the release stepped that out on the hold rows at
	-- the clip's pace (the PC: 0.8-1.3 studs/s, 0.05-0.09 in all, item 539(a)). Each piece of the
	-- way is swept as fill sweeps a sample, against the target where it stands and, while it moves
	-- on (D-565), where its clips carry it over the hold window the stance's sweep below covers,
	-- the hold's own poses added.
	local holdPosesEnd: number = if stance ~= nil then holdEndOf(clip) or 0 else 0
	local function holdPosesOut(time: number, b: number, a: number): (number, number)
		local wasChain, wasPieces = chain, pieces
		local wasLimb, wasTarget = limbChain, targetChain
		local wasDrawn, wasDrawnPieces, wasDrawnTarget = drawnChain, drawnPieces, drawnTargetChain
		local stoods: { { CFrame } } = {}
		if moving and #reach > 0 then
			local holdStep: number = KEEP_OUT.stanceSampleSeconds
			for j = 0, math.ceil((HOLD_SECONDS + holdPosesEnd - from) / holdStep - 1e-6) do
				table.insert(stoods, targetAt(time + j * holdStep))
			end
		end
		local partsBefore, limbsBefore = frames, limbNow
		local at = time
		while at < holdPosesEnd - KEY_EPSILON do
			local upTo = math.min(at + step, holdPosesEnd)
			local partsAt: { CFrame } = table.create(#parts)
			local limbsAt: { CFrame } = table.create(#reach)
			pose(upTo, partsAt, if #reach > 0 then limbsAt else nil)
			local turn = turnOf(partsBefore, partsAt, #parts)
			if #reach > 0 then
				turn = math.max(turn, turnOf(limbsBefore, limbsAt, #reach))
			end
			local ways = math.clamp(math.ceil(turn / KEEP_OUT.maxTurnDegrees), 1, KEEP_OUT.maxPieces)
			local partsWay: { { CFrame } } = { partsBefore }
			local limbsWay: { { CFrame } } = { limbsBefore }
			for piece = 1, ways - 1 do
				local partsPiece: { CFrame } = table.create(#parts)
				local limbsPiece: { CFrame } = table.create(#reach)
				pose(at + (upTo - at) * piece / ways, partsPiece, if #reach > 0 then limbsPiece else nil)
				table.insert(partsWay, partsPiece)
				table.insert(limbsWay, limbsPiece)
			end
			table.insert(partsWay, partsAt)
			table.insert(limbsWay, limbsAt)
			chain, pieces = partsWay, ways
			b, a = facesOut(b, a)
			if #reach > 0 then
				limbChain, drawnChain, drawnPieces = limbsWay, limbsWay, ways
				local shift = if side ~= nil then side * a else Vector3.zero
				if #stoods == 0 then
					targetChain, drawnTargetChain = nil, nil
					b = limbOut(b, shift)
				else
					for _, stood in stoods do
						local still: { { CFrame } } = table.create(ways + 1, stood)
						targetChain, drawnTargetChain = still, still
						b = limbOut(b, shift)
					end
				end
			end
			partsBefore, limbsBefore, at = partsAt, limbsAt, upTo
		end
		chain, pieces = wasChain, wasPieces
		limbChain, targetChain = wasLimb, wasTarget
		drawnChain, drawnPieces, drawnTargetChain = wasDrawn, wasDrawnPieces, wasDrawnTarget
		return b, a
	end
	local function fill(last: number)
		for k = #back, math.min(last, count) do
			if not done then
				table.move(frames, 1, #parts, 1, before)
				table.move(limbNow, 1, #reach, 1, limbBefore)
				if drawn then
					table.move(drawnNow, 1, #reach, 1, drawnBefore)
				end
				local time = math.min(from + k * step, endTime)
				local previous = math.min(from + (k - 1) * step, endTime)
				-- The sample whose sweep reaches the first key is the first held out.
				allowed = if time >= firstKey - KEY_EPSILON then KEEP_OUT.depthEpsilon else startAllowed
				pose(time, frames, if #reach > 0 then limbNow else nil)
				-- A fast turn (a spin) is cut into pieces no part turns more than maxTurnDegrees in.
				-- The hands and arms count too: a limb swung fast leaves the hull of its two poses.
				local turn = turnOf(before, frames, #parts)
				weaponOut = betweenCuts(previous, time)
				local limbCount = if bladeIndex > 0 then bladeIndex - 1 else #reach
				if #reach > 0 then
					turn =
						math.max(turn, turnOf(limbBefore, limbNow, limbCount, if weaponOut then weaponIndex else nil))
				end
				pieces = math.clamp(math.ceil(turn / KEEP_OUT.maxTurnDegrees), 1, KEEP_OUT.maxPieces)
				-- And as the target's own motion asks (D-565).
				local targetStart: { CFrame } = if targetChain ~= nil then targetChain[#targetChain] else hurtFrames
				local targetEnd: { CFrame } = hurtFrames
				if moving and #reach > 0 then
					targetEnd = targetAt(time)
					pieces = math.max(pieces, targetPieces(targetStart, targetEnd, previous, time, turn))
				end
				for piece = 1, pieces - 1 do
					local into = chain[piece + 1]
					if into == nil or into == frames then
						into = table.create(#parts)
						chain[piece + 1] = into
					end
					local limbInto = limbChain[piece + 1]
					if #reach > 0 and (limbInto == nil or limbInto == limbNow) then
						limbInto = table.create(#reach)
						limbChain[piece + 1] = limbInto
					end
					pose(previous + (time - previous) * piece / pieces, into, if #reach > 0 then limbInto else nil)
				end
				chain[pieces + 1] = frames
				limbChain[pieces + 1] = limbNow
				-- The target's parts at the same clip times (D-565).
				if moving and #reach > 0 then
					local times: { { CFrame } } = { targetStart }
					for piece = 1, pieces - 1 do
						table.insert(times, targetAt(previous + (time - previous) * piece / pieces))
					end
					table.insert(times, targetEnd)
					targetChain = times
				end
				-- The hands and arms as the screen draws them over the same stretch (D-535).
				if drawn then
					pose(time, nil, drawnNow, poseLag)
					drawnWeaponOut = betweenCuts(math.max(previous - poseLag, from), math.max(time - poseLag, from))
					local drawnTurn =
						turnOf(drawnBefore, drawnNow, limbCount, if drawnWeaponOut then weaponIndex else nil)
					drawnPieces = math.clamp(math.ceil(drawnTurn / KEEP_OUT.maxTurnDegrees), 1, KEEP_OUT.maxPieces)
					local drawnStart: { CFrame } = if drawnTargetChain ~= nil
						then drawnTargetChain[#drawnTargetChain]
						else hurtFrames
					local drawnEnd: { CFrame } = hurtFrames
					if moving then
						drawnEnd = targetAt(time - poseLag)
						drawnPieces = math.max(
							drawnPieces,
							targetPieces(drawnStart, drawnEnd, previous - poseLag, time - poseLag, drawnTurn)
						)
					end
					for piece = 1, drawnPieces - 1 do
						local into = drawnChain[piece + 1]
						if into == nil or into == drawnNow then
							into = table.create(#reach)
							drawnChain[piece + 1] = into
						end
						pose(previous + (time - previous) * piece / drawnPieces, nil, into, poseLag)
					end
					drawnChain[drawnPieces + 1] = drawnNow
					if moving then
						local times: { { CFrame } } = { drawnStart }
						for piece = 1, drawnPieces - 1 do
							table.insert(times, targetAt(previous + (time - previous) * piece / drawnPieces - poseLag))
						end
						table.insert(times, drawnEnd)
						drawnTargetChain = times
					end
				end
				local b, a = facesOut(currentBack, currentAside)
				local facedBack, facedAside = b, a
				-- Then the reach, no nearer than the strikes call for (a step back only parts the
				-- colliding parts from the faces more), as it stands a sample before: the series is
				-- read a sample ahead, and the reach is a ramp of its own that needs no head start,
				-- so a frame shows it at its own clip time (the first frame never takes two samples
				-- of it), and its sprint is counted from the sample before's.
				if #strikes > 0 then
					local span = previous - math.min(from + (k - 2) * step, endTime)
					b = math.max(b, reachAt(previous, b, a, currentBack, span, math.max(a - currentAside, 0)))
				end
				-- And no hand or arm deeper in the body than it stood at the start, on any sample.
				if #reach > 0 then
					b = limbOut(b, if side ~= nil then side * a else Vector3.zero)
				end
				-- And a stance keeps out the poses its hold plays too (D-671).
				if stance ~= nil and k == count and holdPosesEnd > time + KEY_EPSILON then
					b, a = holdPosesOut(time, b, a)
				end
				-- A stance stands still through its hold (D-606) while the target moves on: from
				-- its last sample the hands are kept out of the target for as long as the pose can
				-- stay frozen, the pose as that sample has it: the hold, up to
				-- combat.activationCancelTime after the press, then the release's wait, as long as
				-- the clip time it froze at (ActionLogic.syncPlan). The kobold's idle carried its
				-- torso 0.009-0.015 studs onto a still Horizontal stance over a 0.4-1.0 s hold.
				if stance ~= nil and k == count and moving and #reach > 0 then
					local still: { { CFrame } } = { limbNow, limbNow }
					local wasLimb, wasPieces, wasTarget = limbChain, pieces, targetChain
					local wasDrawn, wasDrawnPieces, wasDrawnTarget = drawnChain, drawnPieces, drawnTargetChain
					local stood = targetAt(time)
					local holdStep: number = KEEP_OUT.stanceSampleSeconds
					for j = 1, math.ceil((HOLD_SECONDS + time - from) / holdStep - 1e-6) do
						local later = targetAt(time + j * holdStep)
						limbChain, pieces, targetChain = still, 1, { stood, later }
						drawnChain, drawnPieces, drawnTargetChain = still, 1, { stood, later }
						b = limbOut(b, if side ~= nil then side * a else Vector3.zero)
						stood = later
					end
					limbChain, pieces, targetChain = wasLimb, wasPieces, wasTarget
					drawnChain, drawnPieces, drawnTargetChain = wasDrawn, wasDrawnPieces, wasDrawnTarget
				end
				-- A step back past the faces' own (the reach's, the hands', the hold's) can carry a
				-- colliding part along a held face turned to `away` into it, so the faces are kept
				-- out again from there, and the hands after what that moved, for a few rounds
				-- (D-690): Sharp Nail pressed beside a kobold's axe, its torso stepped aside 0.150
				-- off the axe's blocker, then 0.127 back for the hands, stood 0.029 in it again, and
				-- 0.028 as solved.
				if b > facedBack or a > facedAside then
					for _ = 1, KEEP_OUT.rounds do
						local wasBack, wasAside = b, a
						b, a = facesOut(b, a)
						if b == wasBack and a == wasAside then
							break
						end
						if #reach > 0 then
							b = limbOut(b, if side ~= nil then side * a else Vector3.zero)
						end
					end
				end
				-- Back and aside are square to each other: together with the step, one distance.
				local backMost = math.sqrt(math.max(budget * budget - currentAside * currentAside, 0)) - distance
				currentBack = math.max(currentBack, math.min(b, backMost))
				local asideMost = math.sqrt(math.max(budget * budget - (distance + currentBack) ^ 2, 0))
				currentAside = math.max(currentAside, math.min(a, asideMost))
				done = (distance + currentBack) ^ 2 + currentAside * currentAside >= budget * budget - 1e-6
			end
			back[k + 1] = currentBack
			aside[k + 1] = currentAside
		end
	end
	-- What the body shows (D-426): the series above as the engine would have it, eased so that the
	-- root never moves back or aside faster than keepOut.maxSpeedStudsPerSecond, the clip's own
	-- root motion and the blade step counted in (a lunge the keep-out holds still is no move), and
	-- led by keepOut.leadSeconds: each sample stands as far back as any sample that far ahead
	-- calls for, less what the speed covers in between, so the step back starts early instead of
	-- landing in one frame. The keep-out and the reach still only grow, the sprint cap still
	-- holds, and a sample is never farther back than one within the lead calls for. The first
	-- sample is the start (the swing's first frame moves no more than the speed allows).
	local speed: number = KEEP_OUT.maxSpeedStudsPerSecond
	local lead = math.max(1, math.ceil(KEEP_OUT.leadSeconds / step - 1e-6))
	local speedPieces: number = KEEP_OUT.speedPieces
	local shownBack: { number } = { 0 }
	local shownAside: { number } = { 0 }
	-- room[k]: the most the series may grow into sample k, back and aside, as read between clip
	-- times from + (k - 2) * step and from + (k - 1) * step (a sample ahead).
	local backRoom: { [number]: number } = {}
	local asideRoom: { [number]: number } = {}
	-- How far back along `away` and aside along `side` the clip and the step carry the root at a
	-- clip time, from where it stood at `from`.
	local function carried(time: number): (number, number)
		local motion = ClipSampler.rootMotionAt(clip, time)
		local moved =
			rootCFrame:VectorToWorldSpace(Vector3.new(motion[1] - start[1], motion[2] - start[2], motion[3] - start[3]))
		local stepped = AimLogic.standOffAt(distance, stepFrom, to, time, STAND_OFF.easing)
		return moved:Dot(away) + stepped, if side ~= nil then moved:Dot(side) else 0
	end
	local function roomOf(k: number): (number, number)
		local known = backRoom[k]
		if known ~= nil then
			return known, asideRoom[k]
		end
		local first = math.min(from + (k - 2) * step, endTime)
		local last = math.min(from + (k - 1) * step, endTime)
		-- The clip's fastest move back and aside over the stretch, in pieces.
		local fastestBack, fastestAside = -math.huge, -math.huge
		local wasBack, wasAside = carried(first)
		local piece = (last - first) / speedPieces
		for index = 1, speedPieces do
			local nowBack, nowAside = carried(first + piece * index)
			if piece > 0 then
				fastestBack = math.max(fastestBack, (nowBack - wasBack) / piece)
				fastestAside = math.max(fastestAside, (nowAside - wasAside) / piece)
			end
			wasBack, wasAside = nowBack, nowAside
		end
		if fastestBack == -math.huge then
			fastestBack, fastestAside = 0, 0
		end
		local roomBack = math.clamp((speed - fastestBack) * step, 0, SPRINT * step)
		local roomAside = math.clamp((speed - fastestAside) * step, 0, SPRINT * step)
		-- Only the share of the stretch outside the strikes' holds (D-427).
		if last > first then
			local share = openBetween(first, last) / (last - first)
			roomBack *= share
			roomAside *= share
		end
		backRoom[k], asideRoom[k] = roomBack, roomAside
		return roomBack, roomAside
	end
	-- The share of sample k's stretch (as roomOf reads it) the lead may grow in: none of it before
	-- `stillUntil`, the activation hold a swing planned before its end waits for (D-631).
	local function leadShare(k: number): number
		if stillUntil == nil then
			return 1
		end
		local first = math.min(from + (k - 2) * step, endTime)
		local last = math.min(from + (k - 1) * step, endTime)
		local open = openBetween(first, last)
		return if open > 0 then growBetween(first, last) / open else 1
	end
	-- A stance's pose waits on its first pose for `wait` samples while the body steps out first
	-- (D-691), so the series runs that much longer (`total` samples): its sample k is the clip's
	-- sample k - wait, and each sample of the wait keeps out what the clip's first sample sweeps.
	local wait = 0
	local total = count
	local function poseOf(k: number): number
		return if k <= wait then math.min(k, 1) else k - wait
	end
	local function show(last: number)
		for k = #shownBack, math.min(last, total) do
			local ahead = math.min(k + lead, total)
			fill(poseOf(ahead))
			local wasBack, wasAside = shownBack[k], shownAside[k]
			if k == 1 then
				shownBack[2], shownAside[2] = 0, 0
				continue
			end
			-- As far as any sample within the lead calls for, less what the speed covers to it. In
			-- the activation hold the tell holds still (D-604, D-631): a sample there grows only
			-- to what it needs itself (the held pose's hands out of a target that walked in on it;
			-- at a lock the stance took that before the hold, D-606), never toward a later sample,
			-- and the lead starts with the hold's end, at the speed from there on.
			local wantBack, wantAside = back[poseOf(k) + 1], aside[poseOf(k) + 1]
			local roomBack, roomAside = roomOf(math.max(k - wait, 2))
			local share = leadShare(math.max(k - wait, 2))
			if share <= 0 and from + k * step > (stillUntil :: number) + KEY_EPSILON then
				-- A pose past the hold's end, a sample ahead: it waits for the hold's end too.
				wantBack, wantAside = wasBack, wasAside
			elseif share > 0 then
				local spentBack, spentAside = 0, 0
				for j = k + 1, ahead do
					local nextBack, nextAside = roomOf(math.max(j - wait, 2))
					local nextShare = leadShare(math.max(j - wait, 2))
					spentBack += nextBack * nextShare
					spentAside += nextAside * nextShare
					wantBack = math.max(wantBack, back[poseOf(j) + 1] - spentBack)
					wantAside = math.max(wantAside, aside[poseOf(j) + 1] - spentAside)
				end
				roomBack *= share
				roomAside *= share
			end
			local grewAside = math.clamp(wantAside - wasAside, 0, roomAside)
			-- Back and aside are one slide: together within the sprint cap; a stance's within the
			-- speed itself, the flat cap the body takes it at (D-674), so the root stands where the
			-- series puts it on every frame and the pose the frame's physics solves is kept out
			-- there (D-686). Grown each to the speed, a stance's aside fell behind its series:
			-- Rising Arc's Head stood 0.065-0.39 in the kobold's axe on the press's first frames.
			local slide = (if stance ~= nil then speed else SPRINT) * step
			roomBack = math.min(roomBack, math.sqrt(math.max(slide * slide - grewAside * grewAside, 0)))
			shownBack[k + 1] = wasBack + math.clamp(wantBack - wasBack, 0, roomBack)
			shownAside[k + 1] = wasAside + grewAside
		end
	end
	-- A series read at a clip time, a sample ahead (a stance's at its clock, D-691).
	local function reader(series: { number }): (clipTime: number) -> number
		return function(clipTime: number): number
			if clipTime <= from then
				return 0
			end
			local position = math.min((clipTime - from) / step + 1, total)
			local index = math.floor(position)
			show(index + 1)
			if index >= total then
				return series[total + 1]
			end
			local below = series[index + 1]
			-- Between two samples the series moves on with the clip time outside the strikes'
			-- holds (D-427), so a hold the hit-stop skips carries none of it, nor the activation hold.
			local fraction = position - index
			if wait == 0 and (#stills > 0 or stillUntil ~= nil) then
				local first = from + (index - 1) * step
				local whole = growBetween(first, first + step)
				if whole > 0 and whole < step then
					fraction = math.clamp(growBetween(first, clipTime) / whole, 0, 1)
				end
			end
			return below + (series[index + 2] - below) * fraction
		end
	end
	-- A stance's start pose forms only as fast as the body can step it out (D-691): where the
	-- series at the speed falls behind what a sample's pose needs from the press's first frame on
	-- (the pose moving off its first sample, the root still on the press), the pose waits on its
	-- first one, the root stepping out at the speed meanwhile, the fewest samples that leave no
	-- sample behind, at most keepOut.stanceWaitSeconds (the fewest that leave it least behind when
	-- none do). The release's clock is the clip's own (ActionLogic.syncPlan), so the server's
	-- timeline and the strike's timing are untouched: the hold pose comes that much later under the
	-- held key. Rising Arc pressed facing a kobold's axe with its Head 0.103 in the axe's blocker,
	-- formed its start pose 0.43 studs into the axe's way in 0.033 s, and its Head stood 0.12 in on
	-- the press's first rows at 144 Hz while the body stepped at the speed.
	if stance ~= nil and count > 0 then
		fill(count)
		local most = math.floor(KEEP_OUT.stanceWaitSeconds / step + 1e-6)
		local bestWait, bestShort = 0, math.huge
		for tried = 0, most do
			wait, total = tried, count + tried
			table.clear(shownBack)
			table.clear(shownAside)
			shownBack[1], shownAside[1] = 0, 0
			show(total)
			local short = 0
			for k = tried + 1, total do
				local behindBack = math.max(back[poseOf(k) + 1] - shownBack[k + 1], 0)
				local behindAside = math.max(aside[poseOf(k) + 1] - shownAside[k + 1], 0)
				short = math.max(short, math.sqrt(behindBack * behindBack + behindAside * behindAside))
			end
			if short < bestShort - 1e-6 then
				bestWait, bestShort = tried, short
			end
			if short <= 1e-6 then
				break
			end
		end
		if wait ~= bestWait then
			wait, total = bestWait, count + bestWait
			table.clear(shownBack)
			table.clear(shownAside)
			shownBack[1], shownAside[1] = 0, 0
			show(total)
		end
	end
	return {
		keep = reader(shownBack),
		side = side,
		keepSide = if side ~= nil then reader(shownAside) else nil,
		wait = wait * step,
	}
end

--- What StandOffOptions.target asks for (D-565), read off the target rig's mixer handles
--- (Mixer.handles, as they stand when the plan is made): the Base clip that shows most (none done,
--- fading out or held), on from its clock at its speed, and `flinch`, the reaction a cut plays on
--- it (Replication: the rig's "Flinch" clip from the side the swing comes from). Nil for neither.
function ContactPredictor.targetMotion(handles: { any }, flinch: Types.ClipDef?): TargetMotion?
	local shown: any = nil
	local most = 0
	for _, handle in handles do
		if
			typeof(handle) == "table"
			and handle.layer == "Base"
			and handle.done ~= true
			and handle.stopping ~= true
			and typeof(handle.clip) == "table"
			and typeof(handle.time) == "number"
		then
			local weight = (if typeof(handle.fade) == "number" then handle.fade else 1)
				* (if typeof(handle.weight) == "number" then handle.weight else 1)
			if weight > most then
				shown, most = handle, weight
			end
		end
	end
	local base: TargetTrack? = nil
	if shown ~= nil then
		local speed = if shown.held == true then 0 elseif typeof(shown.speed) == "number" then shown.speed else 1
		base = { clip = shown.clip, time = shown.time, speed = speed }
	end
	if base == nil and flinch == nil then
		return nil
	end
	return { base = base, flinch = flinch }
end

--- What StandOffOptions.own asks for (D-683), read off the swinger's own mixer handles (Mixer.handles,
--- as they stand when the plan is made): each Additive clip that shows (none done, fading out or at
--- no weight), on from its clock at its speed, at the weight it shows (fade times weight), its
--- mask and whether it yields (D-685): the rig's Breathe, a flinch it took. Nil for none.
function ContactPredictor.ownLayers(handles: { any }): { OwnLayer }?
	local layers: { OwnLayer } = {}
	for _, handle in handles do
		if
			typeof(handle) == "table"
			and handle.layer == "Additive"
			and handle.done ~= true
			and handle.stopping ~= true
			and typeof(handle.clip) == "table"
			and typeof(handle.time) == "number"
		then
			local weight = (if typeof(handle.fade) == "number" then handle.fade else 1)
				* (if typeof(handle.weight) == "number" then handle.weight else 1)
			if weight > 0 then
				table.insert(layers, {
					clip = handle.clip,
					time = handle.time,
					speed = if handle.held == true
						then 0
						elseif typeof(handle.speed) == "number" then handle.speed
						else 1,
					weight = weight,
					mask = if typeof(handle.mask) == "table" then handle.mask else nil,
					yields = handle.yields == true,
				})
			end
		end
	end
	return if #layers > 0 then layers else nil
end

-- The column's own poses over the rest of a swing (D-534): each colliding part (keepOut.parts)
-- as the clip poses it relative to the root, every keepOut.sampleSeconds from `from` to the clip's
-- end, and for a direction the sample from each one on that carries each part farthest along it.
-- A step back stays taken for the rest of the swing, so the room it may take is the least any of
-- those poses leaves: the clips lean the torso and the head back and forth (Basic1 leans forward
-- at clip 0.117, back at 0.133), and a 0.125 step into the room the forward lean opened put the
-- body up to 0.165 into a wall flush behind one frame later, for the engine to push it back out
-- toward the target (item 431). Posed on the first ask (a swing with no world behind it pays
-- nothing).
type Ahead = {
	parts: { BodyPart },
	-- each part's standOff.hullInsetStuds (0 for a part the engine collides by its box)
	insets: { number },
	times: { number },
	frames: { { CFrame } },
	-- direction key -> best[k][i]: the sample from k on that carries part i farthest along it
	best: { [string]: { { number } } },
}

local function aheadOf(model: Model, clip: Types.ClipDef, from: number): Ahead
	local list: { BodyPart } = {}
	local insets: { number } = {}
	for _, name in KEEP_OUT.parts do
		for _, body in bodyParts(model, { name }) do
			table.insert(list, body)
			table.insert(insets, HULL_INSETS[name] or 0)
		end
	end
	local times: { number } = {}
	local frames: { { CFrame } } = {}
	local sample: number = KEEP_OUT.sampleSeconds
	local time = math.min(from, clip.duration)
	while true do
		local poses: { CFrame } = {}
		placeParts(list, CFrame.identity, ClipSampler.sample(clip, time), poses)
		table.insert(times, time)
		table.insert(frames, poses)
		if time >= clip.duration then
			break
		end
		time = math.min(time + sample, clip.duration)
	end
	return { parts = list, insets = insets, times = times, frames = frames, best = {} }
end

-- How far a box `size` at `frame` (in the root's space) reaches along `along` (root space, unit).
local function reachAlong(frame: CFrame, size: Vector3, along: Vector3): number
	return frame.Position:Dot(along)
		+ size.X / 2 * math.abs(frame.RightVector:Dot(along))
		+ size.Y / 2 * math.abs(frame.UpVector:Dot(along))
		+ size.Z / 2 * math.abs(frame.LookVector:Dot(along))
end

-- The room `columnRoom` leaves, cast again with each part at the farthest the clip carries it
-- along `along` (world, flat, unit; `local` the same in the root's space) from `clipTime` on.
-- With `line` the step is an aside off it (asideRoom, D-696).
local function aheadRoom(
	ahead: Ahead,
	key: string,
	along: Vector3,
	localAlong: Vector3,
	at: CFrame,
	distance: number,
	clipTime: number,
	cast: BoxCast,
	line: Vector3?
): number
	local times, frames, parts = ahead.times, ahead.frames, ahead.parts
	local best = ahead.best[key]
	if best == nil then
		local built: { { number } } = {}
		local count = #times
		for k = count, 1, -1 do
			local row: { number } = {}
			for index, body in ahead.parts do
				local farthest = k
				if k < count then
					local later = built[k + 1][index]
					if
						reachAlong(frames[later][index], body.size, localAlong)
						> reachAlong(frames[k][index], body.size, localAlong)
					then
						farthest = later
					end
				end
				row[index] = farthest
			end
			built[k] = row
		end
		ahead.best[key] = built
		best = built
	end
	-- The sample at or before the clip time, so the pose now is in.
	local k = 1
	while k < #times and times[k + 1] <= clipTime + KEY_EPSILON do
		k += 1
	end
	local most = distance
	for index, body in parts do
		if most <= 0 then
			return 0
		end
		if #body.links > 0 then
			local frame = at * frames[best[k][index]][index]
			most = asideRoom(frame, body.size, ahead.insets[index], along, line, most, cast)
		end
	end
	return most
end

--- The Art stand-off (fix F1): a target already inside the blade's start pose for the first
--- damage window would be cut before the swing moves (the review's "sword raised, pause, pop"), so
--- the body steps straight away from it over the anticipation, from the end of the clip's
--- activation hold (D-604: the tell holds still; the plan's `from`, ContactPredictor.stepStart) to the
--- window's open: the least multiple of standOff.stepStuds
--- that leaves the start pose's blade standOff.clearStuds from every part of `target` it may
--- wound (BladeContact.hurtbox: not the weapon it holds), at most standOff.maxStuds. `from` is the
--- clip time the Art is released from (its hold pose) and `rootCFrame` the root then, facing where the Art cuts; the
--- clip's own root motion carries it on to the open. Nil when the start pose already clears the
--- body, when no step within maxStuds clears it, or when a window's cut that passed within the
--- sweep's promise (the hit radius less half of sweepMaxTipStep) would then pass shallower: a
--- stand-off never costs a hit. With `cast` (ContactPredictor.worldCast) the step never goes into
--- the world (D-235 amended): the root's box is cast back along it, and a wall or a pillar nearer
--- than the step the target calls for takes the longest whole step that keeps standOff.
--- wallGapStuds from it (none when even one step does not fit); the plan's `room` holds that
--- world for the frames that take the step. Pure apart from `cast`: it poses the clip itself and
--- reads only the parts' boxes.
---
--- With `options.keepOut` the plan also keeps the body out of the target (D-314): `keep` says how
--- much farther along `away` the body stands at each clip time, and `keepSide` how far along
--- `side` (off a part the target holds, D-315), so that the swing's own motion never carries a
--- colliding part (standOff.keepOut.parts) deeper into the target's blocker than the swing found
--- it (posed lazily, a sample a frame as the clip gets there), and a plan comes back whenever the
--- target has a blocker (`distance` 0 for a keep-out alone; `keep` may stay 0).
--- `options.step` false plans no blade step (a basic swing). `options.target`: how the target
--- moves on through the swing (ContactPredictor.targetMotion, D-565). `options.stance`: an Art's
--- held start pose up to that clip time, the keep-out alone (D-606).
function ContactPredictor.standOff(
	model: Model,
	clip: Types.ClipDef,
	from: number,
	rootCFrame: CFrame,
	target: Model,
	cast: BoxCast?,
	options: StandOffOptions?
): StandOff?
	local targetRoot = target.PrimaryPart
	if targetRoot == nil then
		return nil
	end
	local parts: { BasePart } = {}
	for _, descendant in target:GetDescendants() do
		if descendant:IsA("BasePart") and BladeContact.hurtbox(descendant :: BasePart) then
			table.insert(parts, descendant :: BasePart)
		end
	end
	-- Straight away from the target; from one too close to give a direction (combat.luau
	-- aim.minFaceDistance), straight back from where the Art faces.
	local offset = rootCFrame.Position - targetRoot.CFrame.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local away = if flat.Magnitude >= MIN_FACE_DISTANCE
		then flat.Unit
		else -Vector3.new(rootCFrame.LookVector.X, 0, rootCFrame.LookVector.Z).Unit
	-- How far the world behind lets the body go: each colliding part (keepOut.parts, the root, the
	-- torsos and the head) cast back along the step from where it stands as the step is taken
	-- (D-517). The root's box alone let a step carry the drawn idle's UpperTorso, 0.26 behind it,
	-- into a wall flush behind, and the engine then pushed the body along the wall.
	-- And with a clip time, each of them again as the clip poses it from then to the swing's end
	-- (D-534): a step back stays, so it never takes room a lean still to come needs.
	local room: ((at: CFrame, distance: number, clipTime: number?) -> number)? = nil
	local rootPart = model.PrimaryPart
	local column = columnOf(model)
	local ahead: Ahead? = nil
	local function roomAlong(key: string, along: Vector3): (at: CFrame, distance: number, clipTime: number?) -> number
		local localAlong = rootCFrame:VectorToObjectSpace(along)
		return function(at: CFrame, distance: number, clipTime: number?): number
			local world = cast :: BoxCast
			local line = if key == "side" then away else nil
			local most = columnRoom(rootPart :: BasePart, column, at, along, distance, world, line)
			if most <= 0 then
				return 0
			end
			if ahead == nil then
				ahead = aheadOf(model, clip, from)
			end
			return aheadRoom(ahead :: Ahead, key, along, localAlong, at, most, clipTime or from, world, line)
		end
	end
	if cast ~= nil and rootPart ~= nil then
		room = roomAlong("away", away)
	end
	local opts: StandOffOptions = options or {}
	local distance = if opts.step == false then nil else bladeStep(model, clip, from, rootCFrame, parts, away, room)
	local window = ClipSampler.hitWindows(clip)[1]
	local to = if distance ~= nil and window ~= nil then window.open else from
	-- The step waits for the activation hold to end (D-604).
	local stepFrom = if distance ~= nil then ContactPredictor.stepStart(clip, from, to, distance) else from
	local holdEnd = holdEndOf(clip)
	local still = if holdEnd ~= nil and holdEnd > from and opts.stance == nil then holdEnd else nil
	local keepOut = if opts.keepOut == true
		then keepOutOf(
			model,
			clip,
			from,
			rootCFrame,
			target,
			away,
			distance or 0,
			to,
			stepFrom,
			parts,
			math.max(opts.poseLag or DEFAULT_POSE_LAG, 0),
			opts.target,
			opts.stance,
			still,
			opts.own
		)
		else nil
	if distance == nil and keepOut == nil then
		return nil
	end
	local side = if keepOut ~= nil then keepOut.side else nil
	local roomSide: ((at: CFrame, distance: number, clipTime: number?) -> number)? = nil
	if side ~= nil and cast ~= nil and rootPart ~= nil then
		roomSide = roomAlong("side", side)
	end
	local depth: ((at: CFrame) -> number)? = nil
	if cast ~= nil and rootPart ~= nil then
		depth = function(at: CFrame): number
			return columnDepth(rootPart :: BasePart, column, at, away, cast :: BoxCast)
		end
	end
	return {
		distance = distance or 0,
		away = away,
		from = stepFrom,
		to = to,
		still = still,
		room = room,
		keep = if keepOut ~= nil then keepOut.keep else nil,
		keepUntil = if keepOut ~= nil then math.min(clip.duration, opts.stance or math.huge) + keepOut.wait else nil,
		side = side,
		keepSide = if keepOut ~= nil then keepOut.keepSide else nil,
		roomSide = roomSide,
		depth = depth,
		wait = if keepOut ~= nil and keepOut.wait > 0 then keepOut.wait else nil,
	}
end

-- The colliding parts (keepOut.parts) of each body kept standing out (keepStanding), by model.
local standingParts: { [Model]: { BodyPart } } = setmetatable({} :: any, { __mode = "k" })

-- A blocker face as it stands now: its frame and size.
type Face = { frame: CFrame, size: Vector3 }

-- The faces of `enemy` a standing body is kept out of (keepStanding): its body face and each face
-- over a part it holds, while its body face collides (a rushing body's and a shattered corpse's
-- do not, as WalkShell reads them); none for a model with no root.
local function standingFaces(enemy: Model): { Face }
	local faces: { Face } = {}
	local body = enemy:FindFirstChild(KEEP_OUT.bodyFace)
	if enemy.PrimaryPart == nil or body == nil or not body:IsA("BasePart") or not (body :: BasePart).CanCollide then
		return faces
	end
	for _, child in enemy:GetChildren() do
		if child:IsA("BasePart") and (child.Name == KEEP_OUT.bodyFace or child.Name == KEEP_OUT.heldFace) then
			table.insert(faces, { frame = (child :: BasePart).CFrame, size = (child :: BasePart).Size })
		end
	end
	return faces
end

-- How far along `along` (flat, unit) the body whose parts (`parts`, posed at `placed`) stand must
-- step for none to stand deeper than `allowed` in any of `faces`: each part's stepOut off each
-- face, again from the farthest until none asks for more (a step off one face can carry a part
-- into another), math.huge when keepOut.rounds passes do not settle it or no step along it does.
local function standingNeed(
	parts: { BodyPart },
	placed: { CFrame },
	faces: { Face },
	along: Vector3,
	allowed: number
): number
	local need = 0
	for _ = 1, KEEP_OUT.rounds do
		local most = need
		for _, face in faces do
			for index, frame in placed do
				local size = parts[index].size
				most = math.max(
					most,
					stepOut(frame, frame, size, face.frame, face.size, along, need, allowed, Vector3.zero)
				)
			end
		end
		if most == need or most == math.huge then
			return most
		end
		need = most
	end
	return math.huge
end

--- A body standing free at an enemy (D-692): the flat step its root takes this frame so that no
--- colliding part (keepOut.parts) of `model`, its root at `rootCFrame` in the pose `offsets` draws
--- (the mixer's), stands deeper than keepOut.stanceDepthStuds in the blockers (keepOut.bodyFace
--- and heldFace) of the enemy among `enemies` (the tracker's records, each with its `model`) it
--- stands deepest in, at most `studs` (keepOut.maxSpeedStudsPerSecond over the frame). Of
--- keepOut.standingDirections directions each side of straight back from that enemy's root, square
--- to that line at the last, the one with the shortest step out; never toward the enemy, and no
--- farther than the world `cast` meets (ContactPredictor.worldCast's, by default) leaves room for
--- the column, as a stance's step. Zero when it stands in none past that.
function ContactPredictor.keepStanding(
	model: Model,
	rootCFrame: CFrame,
	offsets: ClipSampler.Offsets,
	enemies: { any },
	studs: number,
	cast: BoxCast?
): Vector3
	if studs <= 0 then
		return Vector3.zero
	end
	local parts = standingParts[model]
	if parts == nil then
		parts = bodyParts(model, KEEP_OUT.parts)
		standingParts[model] = parts
	end
	local placed: { CFrame } = {}
	placeParts(parts, rootCFrame, offsets, placed)
	local allowed: number = KEEP_OUT.stanceDepthStuds
	local deepest, faces, from = allowed, nil :: { Face }?, nil :: Vector3?
	for _, record in enemies do
		local enemy = if typeof(record) == "table" then record.model else nil
		if typeof(enemy) ~= "Instance" or enemy == model or not enemy:IsA("Model") then
			continue
		end
		local list = standingFaces(enemy :: Model)
		for _, face in list do
			for index, frame in placed do
				local size = parts[index].size
				if (frame.Position - face.frame.Position).Magnitude < (size.Magnitude + face.size.Magnitude) / 2 then
					local depth = boxDepth(frame, size, face.frame, face.size)
					if depth > deepest then
						deepest, faces, from = depth, list, ((enemy :: Model).PrimaryPart :: BasePart).CFrame.Position
					end
				end
			end
		end
	end
	if faces == nil or from == nil then
		return Vector3.zero
	end
	local back = rootCFrame.Position - from
	back = Vector3.new(back.X, 0, back.Z)
	if back.Magnitude < 1e-6 then
		local look = rootCFrame.LookVector
		back = -Vector3.new(look.X, 0, look.Z)
		if back.Magnitude < 1e-6 then
			return Vector3.zero
		end
	end
	back = back.Unit
	local across = Vector3.new(-back.Z, 0, back.X)
	local count: number = KEEP_OUT.standingDirections
	local best, way = math.huge, back
	for index = 0, 2 * count do
		-- 0, then 1 and -1, 2 and -2 ...: on a tie the way nearer straight back.
		local turn = if index == 0 then 0 elseif index % 2 == 1 then (index + 1) / 2 else -index / 2
		local angle = math.rad(90 * turn / count)
		local along = back * math.cos(angle) + across * math.sin(angle)
		local need = standingNeed(parts, placed, faces :: { Face }, along, allowed)
		if need < best - 1e-6 then
			best, way = need, along
		end
	end
	if best == math.huge or best <= 0 then
		return Vector3.zero
	end
	local move = math.min(best, studs)
	local world = cast or ContactPredictor.worldCast(model)
	for index, frame in placed do
		move = boxRoom(frame, parts[index].size, way, move, world, true)
		if move <= 0 then
			return Vector3.zero
		end
	end
	return way * move
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
	-- D-275: the beside test's arc splits left this frame, and the blade posed between the frames.
	local arcsLeft = BESIDE_MAX_SUBDIVISIONS
	local function arcAt(alpha: number): (Vector3?, Vector3?)
		return arcBlade(self, chain, current, previous, alpha)
	end
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
		-- Where the body stands and looks as the window opens (D-275): the root interpolated to the
		-- open, or this frame's start when the predictor came in after it.
		local aim: CFrame = self.aims[index] or previous.root:Lerp(current.root, alphaLo)
		self.aims[index] = aim
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
				local touched: boolean, at: Vector3?
				if not besideSwing(self, index, aim, record) then
					touched, at = BladeContact.touch(guard, tip, candidate.parts, RADIUS)
				elseif k == 1 then
					-- The window's open instant, beside the swing: the blade itself (D-275).
					touched, at = BladeContact.touch(guard, tip, candidate.parts, BESIDE_RADIUS)
				else
					-- Beside the swing: the blade's move from the sample before, along the drawn arc.
					local before = samples[k - 1]
					local arcsSpent
					touched, at, arcsSpent = BladeContact.followTouch(
						before.guard,
						before.tip,
						before.alpha,
						guard,
						tip,
						samples[k].alpha,
						candidate.parts,
						BESIDE_RADIUS,
						BESIDE_FOLLOW_STEP,
						arcAt,
						arcsLeft
					)
					arcsLeft -= arcsSpent
				end
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

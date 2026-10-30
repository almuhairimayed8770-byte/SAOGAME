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
local Enemies = require(Shared.data.enemies)
local World = require(Shared.data.world)
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
--- `away` (flat, unit) between clip times `from` and `to` (AimLogic.standOffAt). `room`, when the
--- plan was made against the world: how far of a further `distance` the root at `rootCFrame` may
--- still step before the world (ContactPredictor.room), for the frames that take the step.
export type StandOff = {
	distance: number,
	away: Vector3,
	from: number,
	to: number,
	room: ((rootCFrame: CFrame, distance: number) -> number)?,
	-- The keep-out (D-314, StandOffOptions.keepOut): how much farther along `away` the body stands
	-- at a clip time than the step above puts it, and the clip time past which that changes no more.
	keep: ((clipTime: number) -> number)?,
	keepUntil: number?,
	-- And how far the keep-out holds the body aside at a clip time, along `side` (flat, unit, square
	-- to `away`), off the face over a part the target holds (D-315); `roomSide` is `room` along it.
	-- Nil when the target holds nothing the body stands beside.
	side: Vector3?,
	keepSide: ((clipTime: number) -> number)?,
	roomSide: ((rootCFrame: CFrame, distance: number) -> number)?,
}

--- What a stand-off plan covers (ContactPredictor.standOff). With neither field it is the Art's
--- blade step alone.
export type StandOffOptions = {
	-- Plan the keep-out too (D-314): a plan comes back whenever the target has a blocker.
	keepOut: boolean?,
	-- false: no blade step (a basic swing; its first cut is the key rule's alone).
	step: boolean?,
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
	if distance <= 0 then
		return 0
	end
	local shrunk = Vector3.new(
		math.max(size.X - 2 * WALL_GAP, WALL_GAP),
		math.max(size.Y - 2 * WALL_GAP, WALL_GAP),
		math.max(size.Z - 2 * WALL_GAP, WALL_GAP)
	)
	local hit = cast(rootCFrame, shrunk, away * (distance + 2 * WALL_GAP))
	if hit == nil then
		return distance
	end
	return math.clamp(hit - 2 * WALL_GAP, 0, distance)
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
	room: ((at: CFrame, distance: number) -> number)?
): number?
	local window = ClipSampler.hitWindows(clip)[1]
	local chain = BladeContact.chain(model)
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

-- One part of the body the engine collides (combat.contact.standOff.keepOut.parts): its size and
-- the joints from the root part out to it, and where on that part a box of its own sits (the
-- blade: keepOut.bladeDepthStuds), nil for the part's own box.
type BodyPart = { size: Vector3, links: { BladeContact.Link }, offset: CFrame? }

-- The parts named `names` the model has, each with its joint path from the root part (a part no
-- joint path reaches is left out; the root part itself has none).
local function bodyParts(model: Model, names: { string }): { BodyPart }
	local root = model.PrimaryPart
	local list: { BodyPart } = {}
	if root == nil then
		return list
	end
	local resolved = Joints.collect(model)
	local placing: { [BasePart]: Joints.Resolved } = {}
	for _, each in resolved do
		if placing[each.part1] == nil then
			placing[each.part1] = each
		end
	end
	for _, name in names do
		local found = model:FindFirstChild(name)
		if found == nil or not found:IsA("BasePart") then
			continue
		end
		local part = found :: BasePart
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
			for index = #reversed, 1, -1 do
				table.insert(links, reversed[index])
			end
			table.insert(list, { size = part.Size, links = links })
		end
	end
	return list
end

-- The blade the trails draw (BladeContact.chain: TrailStart, the guard, to TrailEnd, the tip) as a
-- box with no width along it, on its part's joint path; nil when the model holds none.
local function bladePart(model: Model): BodyPart?
	local blade = BladeContact.chain(model)
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

-- A keep-out plan (keepOutOf): how far back along `away`, and aside along `side`, the body stands
-- at a clip time.
type KeepOut = {
	keep: (clipTime: number) -> number,
	side: Vector3?,
	keepSide: ((clipTime: number) -> number)?,
}

-- Poses `list` with the root at `rootFrame` and the clip's joints at `offsets` into `into`.
local function placeParts(list: { BodyPart }, rootFrame: CFrame, offsets: ClipSampler.Offsets, into: { CFrame })
	for index, body in list do
		local frame = rootFrame
		for _, link in body.links do
			local offset = offsets[link.joint.Name]
			local transform = if offset ~= nil then ClipSampler.toCFrame(offset) else CFrame.identity
			frame = frame * link.c0 * transform * link.c1Inverse
		end
		into[index] = if body.offset ~= nil then frame * body.offset else frame
	end
end

-- A strike the reach is kept out at (keepOutOf): the clip time its hit-stop holds (`key`), and the
-- span the body takes its step over (`start` to `ready`: from the strike before, or the release,
-- to where its snap begins), and the step once it is known, with the aside it was found at.
type Strike = { key: number, start: number, ready: number, need: number?, aside: number }

-- The keep-out (D-314) of a swing whose body stands at `rootCFrame` at clip time `from` and steps
-- `distance` along `away` by clip time `to` (the blade step): how much farther along `away` the
-- body stands at each clip time, and how far aside, so that no colliding part goes deeper into the
-- target's blocker (as its faces stood when the plan was made) than at `from`, and none deeper
-- than depthEpsilon from the first cut's key on (item 286: a freeze holds no overlap). The body's face
-- (keepOut.bodyFace) holds the body back along `away`. A face over a part the target holds
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
-- frame reads it at its own clip time, not a sample ahead. Nil when the target has no blocker.
local function keepOutOf(
	model: Model,
	clip: Types.ClipDef,
	from: number,
	rootCFrame: CFrame,
	target: Model,
	away: Vector3,
	distance: number,
	to: number,
	hurt: { BasePart }
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
	local bladeIndex = 0
	local strikes: { Strike } = {}
	if #hurtFrames > 0 then
		reach = bodyParts(model, KEEP_OUT.limbs)
		local blade = bladePart(model)
		if blade ~= nil then
			table.insert(reach, blade)
			bladeIndex = #reach
		end
		local last = from
		for _, window in ClipSampler.hitWindows(clip) do
			local key = ContactPredictor.strikeKey(clip, window)
			if key > from + KEY_EPSILON then
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
	-- Poses the colliding parts at clip time `time` (the clip's root motion and the blade step)
	-- into `into`, and the reach into `reachInto`.
	local function pose(time: number, into: { CFrame }?, reachInto: { CFrame }?)
		local motion = ClipSampler.rootMotionAt(clip, time)
		local stepped = AimLogic.standOffAt(distance, from, to, time, STAND_OFF.easing)
		local rootFrame = rootCFrame * CFrame.new(motion[1] - start[1], motion[2] - start[2], motion[3] - start[3])
			+ away * stepped
		local offsets = ClipSampler.sample(clip, time)
		if into ~= nil then
			placeParts(parts, rootFrame, offsets, into)
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
	local startAllowed = deepest + KEEP_OUT.depthEpsilon
	local allowed = startAllowed
	local firstKey = math.huge
	for _, window in ClipSampler.hitWindows(clip) do
		local key = ContactPredictor.strikeKey(clip, window)
		if key > from + KEY_EPSILON then
			firstKey = math.min(firstKey, key)
		end
	end
	-- How deep a piece of the reach, posed at `frame` and moved by `moved`, stands in body part
	-- `part`: a hand or an arm the boxes' overlap (boxDepth), the blade its deepest point's distance
	-- in from the part's nearest face (segmentDepth), how buried it looks: a blade along a thin arm
	-- a hair under its skin is not one through it.
	local function depthIn(index: number, frame: CFrame, moved: Vector3, part: number): number
		local hurtFrame = hurtFrames[part]
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
		local depth = math.max(depthIn(index, startFrames[index], Vector3.zero, part), floor) + KEEP_OUT.depthEpsilon
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
	local pairExcess: { number } = {}
	local pairBack: { number } = {}
	local function reachExcess(back: number, shift: Vector3, enough: number): number
		local moved = away * back + shift
		local function excessOf(pair: number): number
			local index = nearPieces[pair]
			local excess = depthIn(index, reachFrames[index], moved, nearParts[pair]) - nearAllowed[pair]
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
		local steps = math.floor(math.max(math.min(reachMost, most - at, top - at), 0) / reachStep + 1e-6)
		-- The pairs whose spheres meet somewhere along the steps; none: the key is clear as it is.
		table.clear(nearPieces)
		table.clear(nearParts)
		table.clear(nearAllowed)
		local reachLine = away * (steps * reachStep)
		for index, frame in reachFrames do
			local first = frame.Position + away * at + shift
			for part, hurtFrame in hurtFrames do
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
	local count = math.max(0, math.ceil((clip.duration - from) / step - 1e-6))
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
	local function turnOf(a: { CFrame }, b: { CFrame }): number
		local most = 1
		for index in parts do
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
	local function fill(last: number)
		for k = #back, math.min(last, count) do
			if not done then
				table.move(frames, 1, #parts, 1, before)
				local time = math.min(from + k * step, clip.duration)
				local previous = math.min(from + (k - 1) * step, clip.duration)
				-- The sample whose sweep reaches the first key is the first held out.
				allowed = if time >= firstKey - KEY_EPSILON then KEEP_OUT.depthEpsilon else startAllowed
				pose(time, frames)
				-- A fast turn (a spin) is cut into pieces no part turns more than maxTurnDegrees in.
				pieces = math.clamp(math.ceil(turnOf(before, frames) / KEEP_OUT.maxTurnDegrees), 1, KEEP_OUT.maxPieces)
				for piece = 1, pieces - 1 do
					local into = chain[piece + 1]
					if into == nil or into == frames then
						into = table.create(#parts)
						chain[piece + 1] = into
					end
					pose(previous + (time - previous) * piece / pieces, into)
				end
				chain[pieces + 1] = frames
				local b, a = currentBack, currentAside
				-- Out of the body's face first, then the held ones, then the body's again for what an
				-- aside step changed: a few rounds settle it.
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
				-- Then the reach, no nearer than the strikes call for (a step back only parts the
				-- colliding parts from the faces more), as it stands a sample before: the series is
				-- read a sample ahead, and the reach is a ramp of its own that needs no head start,
				-- so a frame shows it at its own clip time (the first frame never takes two samples
				-- of it), and its sprint is counted from the sample before's.
				if #strikes > 0 then
					local span = previous - math.min(from + (k - 2) * step, clip.duration)
					b = math.max(b, reachAt(previous, b, a, currentBack, span, math.max(a - currentAside, 0)))
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
		local stepped = AimLogic.standOffAt(distance, from, to, time, STAND_OFF.easing)
		return moved:Dot(away) + stepped, if side ~= nil then moved:Dot(side) else 0
	end
	local function roomOf(k: number): (number, number)
		local known = backRoom[k]
		if known ~= nil then
			return known, asideRoom[k]
		end
		local first = math.min(from + (k - 2) * step, clip.duration)
		local last = math.min(from + (k - 1) * step, clip.duration)
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
	local function show(last: number)
		for k = #shownBack, math.min(last, count) do
			local ahead = math.min(k + lead, count)
			fill(ahead)
			local wasBack, wasAside = shownBack[k], shownAside[k]
			if k == 1 then
				shownBack[2], shownAside[2] = 0, 0
				continue
			end
			-- As far as any sample within the lead calls for, less what the speed covers to it.
			local wantBack, wantAside = back[k + 1], aside[k + 1]
			local spentBack, spentAside = 0, 0
			for j = k + 1, ahead do
				local roomBack, roomAside = roomOf(j)
				spentBack += roomBack
				spentAside += roomAside
				wantBack = math.max(wantBack, back[j + 1] - spentBack)
				wantAside = math.max(wantAside, aside[j + 1] - spentAside)
			end
			local roomBack, roomAside = roomOf(k)
			local grewAside = math.clamp(wantAside - wasAside, 0, roomAside)
			-- Back and aside are one slide: together within the sprint cap.
			local sprint = SPRINT * step
			roomBack = math.min(roomBack, math.sqrt(math.max(sprint * sprint - grewAside * grewAside, 0)))
			shownBack[k + 1] = wasBack + math.clamp(wantBack - wasBack, 0, roomBack)
			shownAside[k + 1] = wasAside + grewAside
		end
	end
	-- A series read at a clip time, a sample ahead.
	local function reader(series: { number }): (clipTime: number) -> number
		return function(clipTime: number): number
			if clipTime <= from then
				return 0
			end
			local position = math.min((clipTime - from) / step + 1, count)
			local index = math.floor(position)
			show(index + 1)
			if index >= count then
				return series[count + 1]
			end
			local below = series[index + 1]
			-- Between two samples the series moves on with the clip time outside the strikes'
			-- holds (D-427), so a hold the hit-stop skips carries none of it.
			local fraction = position - index
			if #stills > 0 then
				local first = from + (index - 1) * step
				local whole = openBetween(first, first + step)
				if whole > 0 and whole < step then
					fraction = math.clamp(openBetween(first, clipTime) / whole, 0, 1)
				end
			end
			return below + (series[index + 2] - below) * fraction
		end
	end
	return {
		keep = reader(shownBack),
		side = side,
		keepSide = if side ~= nil then reader(shownAside) else nil,
	}
end

--- The Art stand-off (fix F1): a target already inside the blade's start pose for the first
--- damage window would be cut before the swing moves (the review's "sword raised, pause, pop"), so
--- the body steps straight away from it over the anticipation, from clip time `from` (the hold
--- pose the Art is released from) to the window's open: the least multiple of standOff.stepStuds
--- that leaves the start pose's blade standOff.clearStuds from every part of `target` it may
--- wound (BladeContact.hurtbox: not the weapon it holds), at most standOff.maxStuds. `rootCFrame` is the root at `from`, facing where the Art cuts; the
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
--- `options.step` false plans no blade step (a basic swing).
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
	-- How far the world behind lets the body go (the root's own box, cast back along the step).
	local room: ((at: CFrame, distance: number) -> number)? = nil
	local rootPart = model.PrimaryPart
	if cast ~= nil and rootPart ~= nil then
		local size = rootPart.Size
		room = function(at: CFrame, distance: number): number
			return ContactPredictor.room(at, size, away, distance, cast)
		end
	end
	local opts: StandOffOptions = options or {}
	local distance = if opts.step == false then nil else bladeStep(model, clip, from, rootCFrame, parts, away, room)
	local window = ClipSampler.hitWindows(clip)[1]
	local to = if distance ~= nil and window ~= nil then window.open else from
	local keepOut = if opts.keepOut == true
		then keepOutOf(model, clip, from, rootCFrame, target, away, distance or 0, to, parts)
		else nil
	if distance == nil and keepOut == nil then
		return nil
	end
	local side = if keepOut ~= nil then keepOut.side else nil
	local roomSide: ((at: CFrame, distance: number) -> number)? = nil
	if side ~= nil and cast ~= nil and rootPart ~= nil then
		local size = rootPart.Size
		roomSide = function(at: CFrame, distance: number): number
			return ContactPredictor.room(at, size, side, distance, cast)
		end
	end
	return {
		distance = distance or 0,
		away = away,
		from = from,
		to = to,
		room = room,
		keep = if keepOut ~= nil then keepOut.keep else nil,
		keepUntil = if keepOut ~= nil then clip.duration else nil,
		side = side,
		keepSide = if keepOut ~= nil then keepOut.keepSide else nil,
		roomSide = roomSide,
	}
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

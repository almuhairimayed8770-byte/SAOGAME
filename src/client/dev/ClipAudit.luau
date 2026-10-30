--!strict
--[[
	ClipAudit: the body review of a clip (section 10 "Review loop"; section 21 gate line 4: "No
	T-pose, A-pose, frozen rig, popping limb or sliding foot appears in any clip").

	ReviewMarkers reads a clip's data; this module plays it. A clip is traced through the real Mixer
	(and so the real ClipSampler) on a real rig (the player character the game builds, RigBuilder's
	boar and kobold) the way the game plays it, with root motion applied, at a sample rate (60 Hz,
	and 240 Hz: every frame of the 0.25x review), and every sampled pose is solved with Pose (the
	server's forward kinematics) and measured. dev.luau review.audit holds every number and every
	part group.

	The plans (ClipAudit.plans): "Lab", the clip cut in over the rig's idle as the ClipLab shows
	it; then the game's own contexts: an attack or a one-shot blended in with its own blendIn over
	the drawn idle (the player) or the idle (an enemy) at points of its cycle, an attack out of the
	drawn run over the gait hand-off (GaitHandOff, D-404), a basic chained after the swing before it
	on that swing's beat and mashed (one BasicAttackRequest refill after it, the earliest the client
	sends it), and the rig's cancels (review.audit.rigs.<rig>.cancels: an Art, the guard or a dodge
	cutting a swing, a dodge cutting the guard or an Art's start-pose hold), each played over the
	cancel hand-over (choreo.luau handOver, D-408) whose first cancel.snapFrames frames are the
	cut's snap. A clip
	whose body the server carries (the boar's rush, an enemy's walk) is traced with its root carried
	along its facing at the game's speed. Every non-looping clip ends the way the game ends it: the
	Mixer stops it with its blendOut and the rig settles into what plays under it.

	The measures (ClipAudit.measure), per 60 Hz frame:
	- Pops: how far every body part turns in one frame, in the root part's frame (a torso twist
	  carries the arm with it, as a viewer sees it), from the clip's first frame (the blend in) to
	  its end. A strike's snap is the fastest motion in the game on purpose (section 10 beat 2): a
	  step that touches a strike's snap is not judged. The Lab plan cuts the clip in, so its first
	  step is not judged either.
	- Overlaps: how deep a body part sinks into another it is not jointed to (oriented boxes of the
	  rig's part sizes, a part drawn smaller than its box at its drawn size; the depth is the
	  separating-axis overlap, the shortest push that frees them), for the pairs review.audit.rigs
	  lists, and how deep the weapon sinks into the body (the hand on the hilt and its forearm
	  aside) while it is in the hand; while the clip blends in, an overlap no deeper than the pose
	  before it had is that pose's.
	- Feet: a foot corner is grounded while it is within the stride code's contact band of the
	  field (choreo.luau locomotion.stride.contact) or below it. A grounded foot's slide in one frame
	  is how far its least-moving corner, grounded through the frame, travels across the field (a
	  foot that rolls onto its toe keeps the toe corners still and does not slide); a plant's drift
	  is how far that corner gets from where it touched down; the sink is the deepest corner below
	  the field. The lowest-corner travel (what a per-part CFrame log gives: it jumps about a foot's
	  length when the lowest corner changes from heel to toe) is kept beside it to compare a log.
	  Slides and plants are judged once the clip's blend in is done (a foot carried from a run's
	  stride to the clip's stance is the hand-over), and not for a clip played in the air or one
	  the controller slides on purpose (review.audit.rigs `airborne`, `slideFree`).
	- The strikes: the weapon tip's path (the rig's `tip`). For each strike, its anticipation (the
	  beats table's Anticipation for the first, the key segment before the snap for the others)
	  against the strike: a cosine of their chords, the anticipation's travel and peak speed, the
	  snap's peak speed, and the share of the anticipation the tip spends behind the body from the
	  gameplay camera (camera.luau orbit.Default) at each view the rig lists (review.audit.rigs.<rig>
	  .views: Behind the player; in Front of an enemy, where the player stands), the worst of them
	  judged (D-414). The rules read the first strike's (one anticipation an attack); the later
	  strikes' are reported.
	- The return: the tip's distance from the end pose to the settled pose, in the root's frame, and
	  the largest part step of the blend-out (degrees a frame).
	- The Recovery: the share of its frames with the blade in front of the face.

	ClipAudit.findings turns a report into review lines with the thresholds of review.audit, each
	with a kind (review.audit.kinds). tools/animation-review.luau writes them into the Problems
	column and tests/choreo/ClipAudit.spec.luau fails on them.

	Roblox datatypes (CFrame, Vector3) only; the rig is read once (Pose.chain), so the ClipLab can
	audit a live rig in Studio and the Lune tools a built one.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared.types)
local Pose = require(Shared.choreo.Pose)
local ClipSampler = require(Shared.choreo.ClipSampler)
local ChoreoData = require(Shared.data.choreo)
local CameraData = require(Shared.data.camera)
local RigData = require(Shared.data.rigs)
local Enemies = require(Shared.data.enemies)
local AI = require(Shared.data.ai)
local Dev = require(Shared.data.dev)
local World = require(Shared.data.world)
local RushWorld = require(Shared.choreo.RushWorld)
local Mixer = require(script.Parent.Parent.choreo.Mixer)
local GaitHandOff = require(script.Parent.Parent.choreo.GaitHandOff)
local ReviewMarkers = require(script.Parent.ReviewMarkers)
local ContactPredictor = require(script.Parent.Parent.controllers.ContactPredictor)

local Audit = Dev.review.audit
local RigConfigs: { [string]: any } = Audit.rigs :: any
local RigTable: { [string]: any } = RigData :: any
local EPSILON = 1e-6
local FPS = Dev.review.fps -- the frame the audit judges and labels by (60 fps)
-- The client sends the next basic as soon as this request refills (a mashed chain).
local BASIC_REFILL_PER_SECOND = World.anticheat.remoteRates.BasicAttackRequest.perSecond

export type Pair = { a: string, b: string }

--- A rig read once for the audit: its joints (Pose.chain), where it stands, the sizes of the parts
--- the audit measures and the groups review.audit.rigs names for it.
export type Body = {
	rig: string,
	model: Model,
	chain: Pose.Chain,
	base: CFrame, -- the root standing on the field, facing -Z
	fieldTop: number,
	sizes: { [string]: Vector3 }, -- every body and weapon part the audit measures
	visible: { [string]: Vector3 }, -- the drawn size of a part smaller than its box (the head)
	bodyParts: { string }, -- the visible body (pops, occluders, the weapon's no-go list)
	pairs: { Pair }, -- body parts that must stay out of each other (never jointed together)
	weaponParts: { string },
	weaponFree: { [string]: boolean }, -- body parts the weapon may touch (the hand on the hilt)
	tip: { part: string, offset: CFrame }?,
	feet: { string },
	corners: { [string]: { Vector3 } }, -- each foot's eight corners in its own frame
	radii: { [string]: number }, -- each measured part's bounding sphere
	-- The gameplay camera's views of this rig (review.audit.rigs.<rig>.views): "Behind" (the
	-- player's own) or "Front" (an enemy's, where the player squares up to it).
	views: { string },
}

--- One clip played into a trace (Plan.plays).
export type Play = {
	clip: Types.ClipDef,
	at: number, -- seconds after the trace starts
	startTime: number?,
	blendIn: number?, -- nil: the clip's own
	blendOut: number?,
	weight: number?,
	coexist: boolean?,
	fallback: boolean?,
	measured: boolean?, -- the clip the trace audits (exactly one)
}

--- A blend-space weight the trace retargets at a time (a run handing over to the idle).
export type Retarget = { at: number, clipId: string, weight: number }

--- A clip the trace stops at a time (the guard a reaction plays out of), with that blend-out.
export type Stop = { at: number, clipId: string, blendOut: number }

--- The root carried along its facing at `speed` studs a second while the measured clip's time is
--- inside [from, to] (the server moves the body; the clip carries no root). A rush (`length` and
--- `strike` set) is carried on the timeline its body is drawn on (RushWorld.distanceAt: the rush
--- speed to the strike beat, then the skid over the rest of the run), from `from` (the launch).
export type Travel = { from: number, to: number, speed: number, length: number?, strike: number? }

--- How a clip is played for the audit: what plays under it and around it.
export type Plan = {
	label: string,
	plays: { Play },
	retargets: { Retarget }?,
	stops: { Stop }?,
	travel: Travel?,
	-- Seconds the trace runs on after the measured clip's handle is gone (its blend-out done).
	settle: number,
	-- The measured clip starts on a cut (the ClipLab): its first step is not judged.
	cutIn: boolean?,
	-- The ClipLab's hit-stop preview: pause `frames` on the frame the measured clip's clock reaches
	-- each damage window's strike key (ContactPredictor.strikeKey), where the game freezes it.
	hitStopFrames: number?,
	-- The Mixer's time scale (the ClipLab's 0.25x).
	timeScale: number?,
	-- The gait clip the measured attack cuts (the drawn run): its clock stands from the attack's
	-- start and the attack takes the body over GaitHandOff's blends, as Locomotion hands a moving
	-- gait to an attack (D-404).
	handOff: string?,
	-- The measured clip cuts a live action (a cancel, D-408): it plays with Mixer's handOver, and a
	-- stop due as it starts is a clip it cancels on another layer (the basic the guard cuts). Its
	-- first review.audit.cancel.snapFrames frames are the cancel's snap: no pop is judged there,
	-- and no part turns back inside it by more than review.audit.reportDegrees.
	handOver: boolean?,
}

--- One sampled pose.
export type Frame = {
	time: number, -- seconds into the trace
	clipTime: number?, -- the measured clip's clock (nil before it plays and once it is gone)
	ended: boolean, -- the measured clip reached its end (it is blending out or gone)
	-- The measured clip is still blending in over what played before it (its envelope below 1).
	blendingIn: boolean,
	solved: Pose.Solved,
	root: CFrame,
}

export type Pop = { part: string, degrees: number, time: number, clipTime: number? }
export type Overlap = { a: string, b: string, depth: number, from: number, to: number, at: number }
export type Slide = { foot: string, studs: number, time: number, clipTime: number? }
export type Strike = {
	index: number,
	snap: ReviewMarkers.Span,
	anticipation: ReviewMarkers.Span,
	cosine: number, -- anticipation chord against the strike chord
	firstCosine: number, -- anticipation chord against the snap's first frame
	travel: number, -- studs the tip moves over the anticipation (its chord)
	anticipationPeak: number, -- studs a frame
	snapPeak: number, -- studs a frame
	snapPeakAt: number, -- clip time of the snap's peak frame
	hidden: number, -- share of the anticipation's samples with the tip behind the body (worst view)
	hiddenViews: { [string]: number }, -- that share from each view the rig lists
}

export type Report = {
	clipId: string,
	label: string,
	hz: number,
	pops: { Pop }, -- the worst step of each part outside the snaps (above reportDegrees)
	overlaps: { Overlap }, -- one per pair and run of overlapping samples
	weapon: { Overlap }, -- the weapon in the body
	slides: { Slide }, -- the worst one-frame slide of each grounded foot
	drifts: { Slide }, -- the worst plant drift of each foot
	jumps: { Slide }, -- the worst one-frame lowest-corner travel of each grounded foot
	sink: { Slide }, -- the deepest each foot goes below the field
	strikes: { Strike },
	returnTip: number?, -- studs from the end pose's tip to the settled tip (root frame)
	returnPeak: Pop?, -- the largest part step of the blend-out (degrees a frame)
	turnBacks: { Pop }?, -- a cancel's hand-over: each part's worst turn back inside it (degrees; nil off a cancel)
	recoveryFaceShare: number?, -- share of the Recovery's samples with the blade across the face
}

local ClipAudit = {}

-- ---------------------------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------------------------

-- Degrees between two rotations (0 to 180: the trace of the relative rotation, so a turn past a
-- half turn reads as the shorter way round, as the eye sees it).
local function angleBetween(a: CFrame, b: CFrame): number
	local _, _, _, r00, _, _, _, r11, _, _, _, r22 = a:ToObjectSpace(b):GetComponents()
	return math.deg(math.acos(math.clamp((r00 + r11 + r22 - 1) * 0.5, -1, 1)))
end

-- The turn from `a` to `b` as one vector: its axis (in a's frame) times its degrees.
local function turnOf(a: CFrame, b: CFrame): Vector3
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = a:ToObjectSpace(b):GetComponents()
	local degrees = math.deg(math.acos(math.clamp((r00 + r11 + r22 - 1) * 0.5, -1, 1)))
	local axis = Vector3.new(r21 - r12, r02 - r20, r10 - r01)
	if axis.Magnitude < EPSILON then
		return Vector3.zero
	end
	return axis.Unit * degrees
end

--- How deep two oriented boxes overlap: the least overlap over the 15 separating axes (the
--- shortest push that frees them), 0 when they are apart or only touch.
function ClipAudit.overlapDepth(aFrame: CFrame, aSize: Vector3, bFrame: CFrame, bSize: Vector3): number
	local offset = bFrame.Position - aFrame.Position
	if offset.Magnitude >= (aSize.Magnitude + bSize.Magnitude) * 0.5 then
		return 0
	end
	local axesA = { aFrame.RightVector, aFrame.UpVector, aFrame.LookVector }
	local axesB = { bFrame.RightVector, bFrame.UpVector, bFrame.LookVector }
	local halfA = { aSize.X * 0.5, aSize.Y * 0.5, aSize.Z * 0.5 }
	local halfB = { bSize.X * 0.5, bSize.Y * 0.5, bSize.Z * 0.5 }
	local least = math.huge
	local function along(axis: Vector3): boolean
		local length = axis.Magnitude
		if length < 1e-6 then
			return true -- parallel edges: the face axes already decide
		end
		local unit = axis / length
		local reach = 0
		for index = 1, 3 do
			reach += math.abs(axesA[index]:Dot(unit)) * halfA[index]
			reach += math.abs(axesB[index]:Dot(unit)) * halfB[index]
		end
		local overlap = reach - math.abs(offset:Dot(unit))
		if overlap <= 0 then
			return false
		end
		least = math.min(least, overlap)
		return true
	end
	for index = 1, 3 do
		if not along(axesA[index]) or not along(axesB[index]) then
			return 0
		end
	end
	for i = 1, 3 do
		for j = 1, 3 do
			if not along(axesA[i]:Cross(axesB[j])) then
				return 0
			end
		end
	end
	return if least == math.huge then 0 else least
end

-- True when the segment from `from` to `to` passes through the box.
local function segmentHitsBox(from: Vector3, to: Vector3, frame: CFrame, size: Vector3): boolean
	local a = frame:PointToObjectSpace(from)
	local b = frame:PointToObjectSpace(to)
	local origin = { a.X, a.Y, a.Z }
	local direction = { b.X - a.X, b.Y - a.Y, b.Z - a.Z }
	local half = { size.X * 0.5, size.Y * 0.5, size.Z * 0.5 }
	local enter, leave = 0, 1
	for axis = 1, 3 do
		if math.abs(direction[axis]) < 1e-9 then
			if math.abs(origin[axis]) > half[axis] then
				return false
			end
		else
			local t1 = (-half[axis] - origin[axis]) / direction[axis]
			local t2 = (half[axis] - origin[axis]) / direction[axis]
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			enter = math.max(enter, t1)
			leave = math.min(leave, t2)
			if enter > leave then
				return false
			end
		end
	end
	return true
end

local function boxCorners(size: Vector3): { Vector3 }
	local half = size * 0.5
	local list = {}
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				table.insert(list, Vector3.new(half.X * x, half.Y * y, half.Z * z))
			end
		end
	end
	return list
end

local function flat(vector: Vector3): number
	return math.sqrt(vector.X * vector.X + vector.Z * vector.Z)
end

-- ---------------------------------------------------------------------------------------------
-- The body
-- ---------------------------------------------------------------------------------------------

local function vec(values: { number }): Vector3
	return Vector3.new(values[1], values[2], values[3])
end

local function findPart(model: Model, name: string): BasePart?
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") and item.Name == name then
			return item
		end
	end
	return nil
end

local function findAttachment(model: Model, name: string): Attachment?
	for _, item in model:GetDescendants() do
		if item:IsA("Attachment") and item.Name == name then
			return item
		end
	end
	return nil
end

--- The rig groups review.audit.rigs holds for `rig` (nil when the audit has none).
function ClipAudit.config(rig: string): any
	return RigConfigs[rig]
end

--- Reads a rig for the audit: `model` standing with its root at `base`, its feet on a field whose
--- top face is at `fieldTop`. The groups come from review.audit.rigs[rig].
function ClipAudit.body(model: Model, rig: string, base: CFrame, fieldTop: number): Body
	local config = RigConfigs[rig]
	assert(config ~= nil, "dev.luau review.audit.rigs has no " .. rig)
	local chain = Pose.chain(model)
	local jointed: { [string]: boolean } = {}
	for _, link in chain.links do
		jointed[link.part0 .. "|" .. link.part1] = true
		jointed[link.part1 .. "|" .. link.part0] = true
	end
	local sizes: { [string]: Vector3 } = {}
	local function sizeOf(name: string): Vector3
		local part = findPart(model, name)
		assert(part ~= nil, ("%s has no part %s"):format(rig, name))
		sizes[name] = part.Size
		return part.Size
	end
	local bodyParts: { string } = {}
	for _, name in config.body do
		sizeOf(name)
		table.insert(bodyParts, name)
	end
	local visible: { [string]: Vector3 } = {}
	for name, share in config.visible or {} do
		local size = sizes[name] or sizeOf(name)
		visible[name] = size * vec(share)
	end
	local pairList: { Pair } = {}
	local seen: { [string]: boolean } = {}
	for _, group in config.pairs do
		for _, a in group.a do
			for _, b in group.b do
				local key = if a < b then a .. "|" .. b else b .. "|" .. a
				if a ~= b and not jointed[a .. "|" .. b] and not seen[key] then
					seen[key] = true
					table.insert(pairList, { a = a, b = b })
				end
			end
		end
	end
	local weaponParts: { string } = {}
	for _, name in config.weapon or {} do
		sizeOf(name)
		table.insert(weaponParts, name)
	end
	local weaponFree: { [string]: boolean } = {}
	for _, name in config.weaponFree or {} do
		weaponFree[name] = true
	end
	local tip: { part: string, offset: CFrame }? = nil
	local tipConfig = config.tip
	if tipConfig ~= nil then
		if tipConfig.attachment ~= nil then
			local attachment = findAttachment(model, tipConfig.attachment)
			assert(attachment ~= nil, ("%s has no %s attachment"):format(rig, tipConfig.attachment))
			local parent = attachment.Parent :: BasePart
			tip = { part = parent.Name, offset = attachment.CFrame }
		else
			tip = { part = tipConfig.part, offset = CFrame.new(vec(tipConfig.offset)) }
		end
	end
	local feetCorners: { [string]: { Vector3 } } = {}
	for _, name in config.feet do
		feetCorners[name] = boxCorners(sizeOf(name))
	end
	local radii: { [string]: number } = {}
	for name, size in sizes do
		radii[name] = (visible[name] or size).Magnitude * 0.5
	end
	return {
		rig = rig,
		model = model,
		chain = chain,
		base = base,
		fieldTop = fieldTop,
		sizes = sizes,
		visible = visible,
		bodyParts = bodyParts,
		pairs = pairList,
		weaponParts = weaponParts,
		weaponFree = weaponFree,
		tip = tip,
		feet = config.feet,
		corners = feetCorners,
		radii = radii,
		views = table.clone(config.views),
	}
end

--- The height of a box's top face (a part standing on a turned field reads its real top).
function ClipAudit.topOf(frame: CFrame, size: Vector3): number
	local half = size * 0.5
	return frame.Position.Y
		+ math.abs(frame.RightVector.Y) * half.X
		+ math.abs(frame.UpVector.Y) * half.Y
		+ math.abs(frame.LookVector.Y) * half.Z
end

--- An enemy rig as the game stands it (RigBuilder.build's model): its root's bottom face at the
--- rig's hipHeight above a field whose top is at 0, facing -Z.
function ClipAudit.standingBody(model: Model, rig: string): Body
	local primary = model.PrimaryPart
	assert(primary ~= nil, rig .. " has no PrimaryPart")
	local height = RigTable[rig].hipHeight + primary.Size.Y * 0.5
	return ClipAudit.body(model, rig, CFrame.new(0, height, 0), 0)
end

-- ---------------------------------------------------------------------------------------------
-- Plans: how the game plays a clip
-- ---------------------------------------------------------------------------------------------

--- Studs `travel` has carried the root by the measured clip's time `clipTime`.
function ClipAudit.travelled(travel: Travel, clipTime: number): number
	if travel.length ~= nil and travel.strike ~= nil then
		return RushWorld.distanceAt(
			travel.speed,
			travel.length :: number,
			travel.strike :: number,
			clipTime - travel.from
		)
	end
	return travel.speed * (math.clamp(clipTime, travel.from, travel.to) - travel.from)
end

--- Where the server carries the body while `clip` plays (nil when the clip stands in place): an
--- enemy's walk at its rig's walkSpeed (the walk is paced to it, Locomotion's RigDriver), a
--- Charger's rush from its wind-up (the launch) on the timeline RushDraw draws its body on
--- (RushWorld.distanceAt: AI.rushSpeed to the strike beat, then the skid over the line's reach and
--- the overshoot).
function ClipAudit.travelOf(clip: Types.ClipDef): Travel?
	local config = RigConfigs[clip.rig]
	if config == nil then
		return nil
	end
	if config.walk == clip.id then
		local rig = RigTable[clip.rig]
		return { from = 0, to = math.huge, speed = rig.walkSpeed }
	end
	local rush = if config.rush ~= nil then config.rush[clip.id] else nil
	if rush ~= nil then
		local def = Enemies.byId(rush.enemy)
		assert(def ~= nil, "enemies.luau has no " .. rush.enemy)
		for _, attack in def.attacks do
			if attack.id == rush.attack then
				local speed = AI.rushSpeed(attack)
				local length = attack.reach + AI.archetypes.Charger.overshoot
				local strike = attack.strike
				return {
					from = attack.windUp,
					to = attack.windUp + RushWorld.timeAt(speed, length, strike, length),
					speed = speed,
					length = length,
					strike = strike,
				}
			end
		end
		error(("%s has no attack %s"):format(rush.enemy, rush.attack))
	end
	return nil
end

--- The plans a clip is audited under (see the header). `library` maps a clip id to its clip
--- (ClipLibrary.get).
function ClipAudit.plans(clip: Types.ClipDef, library: (string) -> Types.ClipDef): { Plan }
	local config = RigConfigs[clip.rig]
	assert(config ~= nil, "dev.luau review.audit.rigs has no " .. clip.rig)
	local plans: { Plan } = {}
	local settle = Audit.settleSeconds
	local lead = Audit.leadSeconds
	local travel = ClipAudit.travelOf(clip)
	-- The rig's idle (and the player's breathing) under everything, as Choreo stands a rig.
	local function under(phase: number?): { Play }
		local list: { Play } = {}
		if config.idle ~= nil and config.idle ~= clip.id then
			local idle = library(config.idle)
			table.insert(list, {
				clip = idle,
				at = 0,
				startTime = (phase or 0) % idle.duration,
				fallback = true,
				blendIn = 0,
			})
		end
		if config.breathing ~= nil and config.breathing ~= clip.id then
			table.insert(list, { clip = library(config.breathing), at = 0, coexist = true, blendIn = 0 })
		end
		return list
	end
	-- As the ClipLab shows it: cut in over the idle.
	do
		local plays = under()
		table.insert(plays, { clip = clip, at = lead, blendIn = 0, measured = true })
		table.insert(plans, { label = "Lab", plays = plays, travel = travel, settle = settle, cutIn = true })
	end
	if clip.loop then
		return plans
	end
	local drawnIdle = config.drawnIdle
	-- The clip the game plays it out of (a guard reaction out of the guard), stopped as it starts.
	local overId = if config.over ~= nil then config.over[clip.id] else nil
	for _, phase in Audit.idlePhases do
		-- Over the stance the game stands it in: the drawn idle at full weight (the player), the idle.
		local plays = under(phase)
		if drawnIdle ~= nil then
			local stance = library(drawnIdle)
			table.insert(plays, {
				clip = stance,
				at = 0,
				startTime = phase % stance.duration,
				coexist = true,
				weight = 1,
				blendIn = 0,
			})
		end
		local stops: { Stop }? = nil
		if overId ~= nil then
			local over = library(overId)
			table.insert(plays, { clip = over, at = 0, startTime = phase % over.duration, blendIn = 0 })
			stops = { { at = lead, clipId = over.id, blendOut = clip.blendIn or ChoreoData.blendIn } }
		end
		table.insert(plays, { clip = clip, at = lead, measured = true })
		table.insert(plans, {
			label = ("Stand@%g"):format(phase),
			plays = plays,
			stops = stops,
			travel = travel,
			settle = settle,
		})
	end
	if clip.attack and config.drawnRun ~= nil and drawnIdle ~= nil then
		-- Out of the drawn run: the run hands its weight to the drawn idle as the attack starts.
		local run = library(config.drawnRun)
		for _, share in Audit.runPhases do
			local plays = under()
			table.insert(plays, { clip = library(drawnIdle), at = 0, coexist = true, weight = 0, blendIn = 0 })
			table.insert(plays, {
				clip = run,
				at = 0,
				startTime = (share * run.duration - lead) % run.duration,
				coexist = true,
				weight = 1,
				blendIn = 0,
			})
			table.insert(plays, { clip = clip, at = lead, measured = true })
			table.insert(plans, {
				label = ("Run@%g"):format(share),
				plays = plays,
				retargets = {
					{ at = lead, clipId = run.id, weight = 0 },
					{ at = lead, clipId = drawnIdle, weight = 1 },
				},
				handOff = run.id,
				travel = travel,
				settle = settle,
			})
		end
	end
	-- Chained after the attack before it (the basic chain): on the swing's beat (chainSeconds), and
	-- mashed, one BasicAttackRequest refill after it (CharacterController.basicAttack starts the
	-- next basic as soon as the request refills: the earliest the game starts it).
	local before = if config.chain ~= nil then config.chain[clip.id] else nil
	if before ~= nil and drawnIdle ~= nil then
		local name = before:match("[^/]+$") or before
		local chains = {
			{ label = "After " .. name, seconds = Audit.chainSeconds },
			{ label = "Mash after " .. name, seconds = 1 / BASIC_REFILL_PER_SECOND },
		}
		for _, chain in chains do
			local plays = under()
			table.insert(plays, { clip = library(drawnIdle), at = 0, coexist = true, weight = 1, blendIn = 0 })
			table.insert(plays, { clip = library(before), at = lead })
			table.insert(plays, { clip = clip, at = lead + chain.seconds, measured = true })
			-- The next basic cuts the one before it while it plays: a cancel (D-408).
			table.insert(
				plans,
				{ label = chain.label, plays = plays, travel = travel, settle = settle, handOver = true }
			)
		end
	end
	-- Cutting a live action (a cancel, D-408): each of the rig's `cancels` this clip cuts in on,
	-- `gap` seconds into the clip it cuts, played the way the game plays a cancel. A clip on another
	-- layer than the one it cuts (the guard over a basic, a dodge over the guard) cancels it as it
	-- starts, as CharacterController does.
	if config.cancels ~= nil and drawnIdle ~= nil then
		for _, cancel in config.cancels do
			if cancel.clip == clip.id then
				local over = library(cancel.over)
				local name = cancel.over:match("[^/]+$") or cancel.over
				local plays = under()
				table.insert(plays, { clip = library(drawnIdle), at = 0, coexist = true, weight = 1, blendIn = 0 })
				table.insert(plays, { clip = over, at = lead })
				table.insert(plays, { clip = clip, at = lead + cancel.gap, measured = true })
				local stops: { Stop }? = nil
				if over.layer ~= clip.layer then
					stops = { { at = lead + cancel.gap, clipId = over.id, blendOut = ChoreoData.handOver.seconds } }
				end
				table.insert(plans, {
					label = ("Cancel %s@%g"):format(name, cancel.gap),
					plays = plays,
					stops = stops,
					travel = travel,
					settle = settle,
					handOver = true,
				})
			end
		end
	end
	return plans
end

-- ---------------------------------------------------------------------------------------------
-- Tracing
-- ---------------------------------------------------------------------------------------------

--- Plays a plan through a real Mixer stepped at `hz` and solves every sampled pose on the body.
function ClipAudit.trace(body: Body, plan: Plan, hz: number): { Frame }
	local mixer = Mixer.new()
	local scale = plan.timeScale or 1
	if scale ~= 1 then
		mixer:setTimeScale(scale)
	end
	local dt = 1 / hz
	local frames: { Frame } = {}
	local pending = table.clone(plan.plays)
	table.sort(pending, function(a, b)
		return a.at < b.at
	end)
	local retargets = table.clone(plan.retargets or {})
	local stops = table.clone(plan.stops or {})
	local handles: { [string]: Mixer.Handle } = {}
	local measured: Mixer.Handle? = nil
	local measuredClip: Types.ClipDef? = nil
	local root = body.base
	local time = 0
	local goneAt: number? = nil
	local travel = plan.travel
	local lastClipTime: number? = nil
	-- The strike keys a hit-stop plan freezes on, in clip time, and the next one due.
	local strikeKeys: { number } = {}
	local nextStrike = 1
	local played = 0 -- clip seconds the measured clip has run (a loop's wrap included)
	local ended = false
	while time <= Audit.maxTraceSeconds / scale do
		-- Start what is due: a play starts in the step that ends at its `at` + dt, as a play from
		-- input shows its first step in the frame it was pressed.
		while #pending > 0 and pending[1].at <= time + EPSILON do
			local play = table.remove(pending, 1) :: Play
			-- A cancel takes what a stop due now would let go (the guard over a basic, D-408).
			local handOver = plan.handOver == true and play.measured == true
			local cancels: { Mixer.Handle }? = nil
			if handOver then
				local list: { Mixer.Handle } = {}
				for index = #stops, 1, -1 do
					local stop = stops[index]
					if stop.at <= time + EPSILON then
						local cut = handles[stop.clipId]
						if cut ~= nil then
							table.insert(list, cut)
						end
						table.remove(stops, index)
					end
				end
				cancels = list
			end
			local handle = mixer:play(play.clip, {
				startTime = play.startTime,
				blendIn = play.blendIn,
				blendOut = play.blendOut,
				weight = play.weight,
				coexist = play.coexist,
				fallback = play.fallback,
				handOver = handOver,
				cancels = cancels,
			})
			handles[play.clip.id] = handle
			if play.measured then
				measured = handle
				measuredClip = play.clip
				if plan.hitStopFrames ~= nil then
					strikeKeys = ClipAudit.strikeKeys(play.clip)
					nextStrike = 1
				end
				-- Locomotion's hand-off from a moving gait: the gait stands, the attack takes
				-- the body joint by joint (D-404).
				local gait = if plan.handOff ~= nil then handles[plan.handOff] else nil
				if gait ~= nil and GaitHandOff.applies(play.clip) then
					mixer:hold(gait)
					mixer:handOff(handle, GaitHandOff.blends(play.clip))
				end
			end
		end
		for index = #stops, 1, -1 do
			local stop = stops[index]
			if stop.at <= time + EPSILON then
				local handle = handles[stop.clipId]
				if handle ~= nil and not handle.stopping and not handle.done then
					mixer:stop(handle, stop.blendOut)
				end
				table.remove(stops, index)
			end
		end
		for index = #retargets, 1, -1 do
			local retarget = retargets[index]
			if retarget.at <= time + EPSILON then
				local handle = handles[retarget.clipId]
				if handle ~= nil then
					mixer:setWeight(handle, retarget.weight)
				end
				table.remove(retargets, index)
			end
		end
		local result = mixer:step(if #frames == 0 then 0 else dt)
		local delta = result.rootDelta
		root = root * CFrame.new(delta[1], delta[2], delta[3])
		local current = measured
		local clipTime: number? = nil
		local blendingIn = false
		if current ~= nil and not current.done then
			clipTime = current.time
			blendingIn = mixer:blendingIn(current) and not current.ended
			if current.ended or current.stopping then
				ended = true
			end
			if lastClipTime ~= nil then
				local moved = current.time - (lastClipTime :: number)
				if moved < -EPSILON and measuredClip ~= nil then
					moved += (measuredClip :: Types.ClipDef).duration -- a loop wrapped
				end
				played += math.max(0, moved)
				if travel ~= nil and moved > 0 then
					local before = ClipAudit.travelled(travel, lastClipTime :: number)
					local carried = ClipAudit.travelled(travel, lastClipTime :: number + moved) - before
					if carried > 0 then
						root = root * CFrame.new(0, 0, -carried)
					end
				end
			end
			lastClipTime = current.time
			-- The game freezes on the frame the clock reaches the strike key (the contact rule);
			-- the Mixer's hit-stop then stands in for the authored Hold after it.
			local strike = strikeKeys[nextStrike]
			if plan.hitStopFrames ~= nil and strike ~= nil and current.time >= strike - EPSILON then
				nextStrike += 1
				mixer:hitStop(plan.hitStopFrames)
			end
		elseif current ~= nil and current.done and goneAt == nil then
			goneAt = time
			ended = true
		end
		table.insert(frames, {
			time = time,
			clipTime = clipTime,
			ended = ended,
			blendingIn = blendingIn,
			solved = Pose.solve(body.model, root, result.offsets, body.chain),
			root = root,
		})
		if goneAt ~= nil and time >= (goneAt :: number) + plan.settle then
			break
		end
		if measuredClip ~= nil and (measuredClip :: Types.ClipDef).loop then
			-- A loop runs one whole cycle and on past its wrap.
			if played >= (measuredClip :: Types.ClipDef).duration + Audit.loopOverSeconds then
				break
			end
		end
		time += dt
	end
	return frames
end

--- The clip times a swing's hit-stops freeze on: each damage window's strike key
--- (ContactPredictor.strikeKey, the strike snap's landing; the window's open when it has none).
function ClipAudit.strikeKeys(clip: Types.ClipDef): { number }
	local keys = {}
	for _, window in ClipSampler.hitWindows(clip) do
		table.insert(keys, ContactPredictor.strikeKey(clip, window))
	end
	return keys
end

-- ---------------------------------------------------------------------------------------------
-- Measuring
-- ---------------------------------------------------------------------------------------------

-- The strike snaps of an attack and the anticipation before each (the beats table's for the
-- first; the key segment ending at the snap's start for the others).
local function strikeSpans(clip: Types.ClipDef): { { snap: ReviewMarkers.Span, anticipation: ReviewMarkers.Span } }
	local list = {}
	if not clip.attack then
		return list
	end
	local beats: any = clip.beats
	for index, snap in ReviewMarkers.strikeSnaps(clip) do
		local anticipation: ReviewMarkers.Span? = nil
		if index == 1 and beats ~= nil and beats.Anticipation ~= nil then
			anticipation = { start = beats.Anticipation.start, finish = beats.Anticipation.finish }
		else
			for keyIndex = 2, #clip.keys do
				if math.abs(clip.keys[keyIndex].time - snap.start) < EPSILON then
					anticipation = { start = clip.keys[keyIndex - 1].time, finish = snap.start }
					break
				end
			end
		end
		if anticipation ~= nil then
			table.insert(list, { snap = snap, anticipation = anticipation })
		end
	end
	return list
end

-- True when the clip-time step from `previous` to `clipTime` touches a snap.
local function inSnap(clipTime: number?, previous: number?, snaps: { ReviewMarkers.Span }): boolean
	if clipTime == nil or previous == nil then
		return false
	end
	local from, to = math.min(previous, clipTime), math.max(previous, clipTime)
	for _, snap in snaps do
		if to > snap.start - EPSILON and from < snap.finish + EPSILON then
			return true
		end
	end
	return false
end

-- The gameplay camera on a root: camera.luau follow and orbit.Default behind it ("Behind"), or the
-- same orbit turned round to look at it from its front ("Front": an enemy, where the player stands).
local function cameraAt(root: CFrame, view: string): Vector3
	local orbit = CameraData.orbit.Default
	local facing = if view == "Front" then root * CFrame.Angles(0, math.pi, 0) else root
	local pivot = facing * CFrame.new(orbit.side, CameraData.follow.focusHeight + orbit.height, 0)
	local pitch = math.rad(orbit.pitch)
	return (pivot * CFrame.new(0, orbit.distance * math.sin(pitch), orbit.distance * math.cos(pitch))).Position
end

local function tipOf(body: Body, frame: Frame): Vector3?
	local tip = body.tip
	if tip == nil then
		return nil
	end
	local part = frame.solved[tip.part]
	return if part ~= nil then (part * tip.offset).Position else nil
end

local function hiddenFrom(body: Body, frame: Frame, point: Vector3, view: string): boolean
	local eye = cameraAt(frame.root, view)
	for _, name in body.bodyParts do
		local part = frame.solved[name]
		if part ~= nil and segmentHitsBox(eye, point, part, body.visible[name] or body.sizes[name]) then
			return true
		end
	end
	return false
end

-- The first frame at or after a clip time, or nil.
local function frameAt(frames: { Frame }, clipTime: number): number?
	for index, frame in frames do
		if frame.clipTime ~= nil and not frame.ended and frame.clipTime >= clipTime - EPSILON then
			return index
		end
	end
	return nil
end

-- The worst step of each body part between two samples, in the root's frame.
local function partSteps(body: Body, before: Frame, now: Frame, into: (string, number) -> ())
	local rootName = body.chain.rootName
	local rootNow, rootBefore = now.solved[rootName], before.solved[rootName]
	for _, name in body.bodyParts do
		local a, b = before.solved[name], now.solved[name]
		if a ~= nil and b ~= nil then
			into(name, angleBetween(rootBefore:ToObjectSpace(a), rootNow:ToObjectSpace(b)))
		end
	end
end

--- The parts a clip moves: every part below a joint it keys (or all of them when it carries the
--- root, or the server carries the body under it). What it does not key is what plays under it
--- (an UpperBody guard leaves the legs to the idle), so the audit leaves those parts to that clip.
function ClipAudit.owned(body: Body, clip: Types.ClipDef, carried: boolean): { [string]: boolean }
	local keyed: { [string]: boolean } = {}
	local all = carried
	for _, key in clip.keys do
		for name in key.joints do
			keyed[name] = true
		end
		if key.root ~= nil then
			all = true
		end
	end
	local parentLink: { [string]: Pose.Link } = {}
	for _, link in body.chain.links do
		parentLink[link.part1] = link
	end
	local owned: { [string]: boolean } = {}
	local function owns(part: string): boolean
		local known = owned[part]
		if known ~= nil then
			return known
		end
		local link = parentLink[part]
		local result = all or (link ~= nil and (keyed[link.name] == true or owns(link.part0)))
		owned[part] = result
		return result
	end
	for name in body.sizes do
		owns(name)
	end
	return owned
end

-- The clip time a frame shows, nil once the clip is blending out (a finding's "blend-out").
local function shownTime(frame: Frame): number?
	return if frame.ended then nil else frame.clipTime
end

--- Measures a trace of `clip` (traced with `plan` at `hz`).
function ClipAudit.measure(body: Body, clip: Types.ClipDef, plan: Plan, frames: { Frame }, hz: number): Report
	local step = math.max(1, math.floor(hz / FPS + 0.5)) -- samples in one 60 Hz frame
	local snaps: { ReviewMarkers.Span } = if clip.attack then ReviewMarkers.strikeSnaps(clip) else {}
	local config = RigConfigs[body.rig]
	local owned = ClipAudit.owned(body, clip, plan.travel ~= nil)
	local report: Report = {
		clipId = clip.id,
		label = plan.label,
		hz = hz,
		pops = {},
		overlaps = {},
		weapon = {},
		slides = {},
		drifts = {},
		jumps = {},
		sink = {},
		strikes = {},
	}
	-- The audited stretch: from the measured clip's first sample to the end of the trace.
	local first = 1
	while first <= #frames and frames[first].clipTime == nil do
		first += 1
	end
	if first > #frames then
		return report
	end
	local endIndex: number? = nil
	for index = first, #frames do
		if frames[index].ended then
			endIndex = index
			break
		end
	end
	-- The first frame after the clip is gone (the settle), if the trace reached it.
	local goneIndex = #frames + 1
	for index = first, #frames do
		if frames[index].clipTime == nil then
			goneIndex = index
			break
		end
	end
	-- What the poses around the clip already have is theirs: a measure no larger than the pose
	-- before it had (while it blends in) or than the pose it settles into has (while it blends
	-- out) is not the clip's. `measureOf` reads a frame; the two bounds are returned.
	local function context(measureOf: (Frame) -> number): (number, number)
		local before = if first > 1 and not plan.cutIn then measureOf(frames[first - 1]) else 0
		local after = 0
		for index = goneIndex, #frames do
			after = math.max(after, measureOf(frames[index]))
		end
		return before, after
	end
	local function theirs(frame: Frame, value: number, before: number, after: number): boolean
		return (frame.blendingIn and value <= before + EPSILON) or (frame.ended and value <= after + EPSILON)
	end

	-- A cancel's hand-over (D-408): its first cancel.snapFrames frames are the cut's snap.
	local handOverEnd: number? = nil
	if plan.handOver == true and frames[first].clipTime ~= nil then
		handOverEnd = (frames[first].clipTime :: number) + Audit.cancel.snapFrames / FPS
	end
	local function inHandOver(clipTime: number?): boolean
		return handOverEnd ~= nil and clipTime ~= nil and clipTime <= (handOverEnd :: number) + EPSILON
	end

	-- Pops: from the blend in (the Lab's cut aside) to the clip's end.
	local worstPop: { [string]: Pop } = {}
	local popFrom = if plan.cutIn then first + step else first
	local popTo = if endIndex ~= nil then (endIndex :: number) - 1 else #frames
	for index = math.max(popFrom, step + 1), popTo do
		local now, before = frames[index], frames[index - step]
		if inSnap(now.clipTime, before.clipTime, snaps) or inHandOver(now.clipTime) then
			continue
		end
		partSteps(body, before, now, function(name: string, degrees: number)
			local worst = worstPop[name]
			if owned[name] and degrees >= Audit.reportDegrees and (worst == nil or degrees > worst.degrees) then
				worstPop[name] = { part = name, degrees = degrees, time = now.time, clipTime = shownTime(now) }
			end
		end)
	end
	for _, pop in worstPop do
		table.insert(report.pops, pop)
	end
	table.sort(report.pops, function(a, b)
		return a.degrees > b.degrees
	end)

	-- Inside a cancel's hand-over no part turns back: each 60 Hz frame's turn of a part (an axis
	-- times degrees, in the root's frame) against the frame's before it.
	if handOverEnd ~= nil then
		local rootName = body.chain.rootName
		local lastTurn: { [string]: Vector3 } = {}
		local worstBack: { [string]: Pop } = {}
		local index = first + step
		while index <= #frames and inHandOver(frames[index].clipTime) do
			local now, before = frames[index], frames[index - step]
			for _, name in body.bodyParts do
				local a, b = before.solved[name], now.solved[name]
				if owned[name] and a ~= nil and b ~= nil then
					local turn = turnOf(before.solved[rootName]:ToObjectSpace(a), now.solved[rootName]:ToObjectSpace(b))
					local last = lastTurn[name]
					if last ~= nil and last.Magnitude > EPSILON then
						local back = -turn:Dot(last.Unit)
						local worst = worstBack[name]
						if back >= Audit.reportDegrees and (worst == nil or back > worst.degrees) then
							worstBack[name] =
								{ part = name, degrees = back, time = now.time, clipTime = shownTime(now) }
						end
					end
					lastTurn[name] = turn
				end
			end
			index += step
		end
		local turnBacks: { Pop } = {}
		for _, back in worstBack do
			table.insert(turnBacks, back)
		end
		table.sort(turnBacks, function(a, b)
			return a.degrees > b.degrees
		end)
		report.turnBacks = turnBacks
	end

	-- Overlaps (body against body, the weapon against the body), as runs of samples while the
	-- clip plays (its blend-out included), less what the poses around it already have (a run's
	-- crossing legs while it blends in).
	local function runs(into: { Overlap }, a: string, b: string, depthOf: (Frame) -> number)
		local before, after = context(depthOf)
		local open: Overlap? = nil
		for index = first, #frames do
			local frame = frames[index]
			local depth = if frame.clipTime ~= nil then depthOf(frame) else 0
			if theirs(frame, depth, before, after) then
				depth = 0
			end
			local at = frame.clipTime or clip.duration
			if depth > EPSILON then
				if open == nil then
					open = { a = a, b = b, depth = depth, from = at, to = at, at = at }
				else
					local run = open :: Overlap
					run.to = at
					if depth > run.depth then
						run.depth = depth
						run.at = at
					end
				end
			elseif open ~= nil then
				table.insert(into, open)
				open = nil
			end
		end
		if open ~= nil then
			table.insert(into, open)
		end
	end
	local function sizeOf(name: string): Vector3
		return body.visible[name] or body.sizes[name]
	end
	for _, pair in body.pairs do
		if not owned[pair.a] and not owned[pair.b] then
			continue
		end
		local sizeA, sizeB = sizeOf(pair.a), sizeOf(pair.b)
		runs(report.overlaps, pair.a, pair.b, function(frame: Frame): number
			local a, b = frame.solved[pair.a], frame.solved[pair.b]
			if a == nil or b == nil then
				return 0
			end
			return ClipAudit.overlapDepth(a, sizeA, b, sizeB)
		end)
	end
	local endMount = ReviewMarkers.mountAt(clip, clip.duration)
	for _, weaponPart in body.weaponParts do
		for _, name in body.bodyParts do
			if body.weaponFree[name] or not (owned[weaponPart] or owned[name]) then
				continue
			end
			local size = sizeOf(name)
			runs(report.weapon, weaponPart, name, function(frame: Frame): number
				local mount = if frame.clipTime ~= nil
					then ReviewMarkers.mountAt(clip, frame.clipTime :: number)
					else endMount
				if mount ~= "Hand" then
					return 0
				end
				local a, b = frame.solved[weaponPart], frame.solved[name]
				if a == nil or b == nil then
					return 0
				end
				return ClipAudit.overlapDepth(a, body.sizes[weaponPart], b, size)
			end)
		end
	end

	-- Feet (not for a clip played in the air), while the clip plays. A foot carried to the clip's
	-- stance while it blends in is the hand-over from what played before (a run's stride), so a
	-- slide and a plant are judged once the blend in is done (the Lab's cut has none); a clip the
	-- controller slides on purpose (`slideFree`: the skid) is judged for its sink only.
	local airborne = config.airborne ~= nil and table.find(config.airborne, clip.id) ~= nil
	local slideFree = config.slideFree ~= nil and table.find(config.slideFree, clip.id) ~= nil
	local contact = ChoreoData.locomotion.stride.contact
	for _, foot in if airborne then {} else body.feet do
		if not owned[foot] then
			continue
		end
		local localCorners = body.corners[foot]
		local worstSlide: Slide? = nil
		local worstJump: Slide? = nil
		local worstDrift: Slide? = nil
		local deepest: Slide? = nil
		local planted: { [number]: Vector3 } = {} -- corner -> where it touched down
		local cache: { [number]: { points: { Vector3 }, grounded: { boolean } } } = {}
		local function at(index: number): ({ Vector3 }, { boolean })
			local entry = cache[index]
			if entry == nil then
				local part = frames[index].solved[foot]
				local points, grounded = {}, {}
				for corner, offset in localCorners do
					local point = part * offset
					points[corner] = point
					grounded[corner] = point.Y - body.fieldTop <= contact
				end
				entry = { points = points, grounded = grounded }
				cache[index] = entry
			end
			local found = entry :: { points: { Vector3 }, grounded: { boolean } }
			return found.points, found.grounded
		end
		local function lowestOf(list: { Vector3 }): Vector3
			local best = list[1]
			for _, point in list do
				if point.Y < best.Y then
					best = point
				end
			end
			return best
		end
		local sinkBefore, sinkAfter = context(function(frame: Frame): number
			local part = frame.solved[foot]
			local least = math.huge
			for _, offset in localCorners do
				least = math.min(least, (part * offset).Y)
			end
			return math.max(0, body.fieldTop - least)
		end)
		for index = first, #frames do
			local frame = frames[index]
			if frame.clipTime == nil then
				break -- the clip is gone: what stands now is the settle
			end
			local points, grounded = at(index)
			local lowest = lowestOf(points).Y - body.fieldTop
			if
				lowest < 0
				and not theirs(frame, -lowest, sinkBefore, sinkAfter)
				and (deepest == nil or -lowest > (deepest :: Slide).studs)
			then
				deepest = { foot = foot, studs = -lowest, time = frame.time, clipTime = shownTime(frame) }
			end
			if slideFree or (frame.blendingIn and not plan.cutIn) then
				planted = {}
				continue
			end
			-- Plant drift: the least-moving corner grounded since it touched down.
			for corner, point in points do
				if grounded[corner] then
					if planted[corner] == nil then
						planted[corner] = point
					end
				else
					planted[corner] = nil
				end
			end
			local drift = math.huge
			for corner, down in planted do
				drift = math.min(drift, flat(points[corner] - down))
			end
			if drift < math.huge and (worstDrift == nil or drift > (worstDrift :: Slide).studs) then
				worstDrift = { foot = foot, studs = drift, time = frame.time, clipTime = shownTime(frame) }
			end
			if index - step < first or (frames[index - step].blendingIn and not plan.cutIn) then
				continue
			end
			-- One 60 Hz frame: the least travel of a corner grounded at every sample of it.
			local slide = math.huge
			for corner = 1, #points do
				local held = true
				for back = index - step, index do
					local _, wasGrounded = at(back)
					if not wasGrounded[corner] then
						held = false
						break
					end
				end
				if held then
					local before = at(index - step)
					slide = math.min(slide, flat(points[corner] - before[corner]))
				end
			end
			if slide < math.huge and (worstSlide == nil or slide > (worstSlide :: Slide).studs) then
				worstSlide = { foot = foot, studs = slide, time = frame.time, clipTime = shownTime(frame) }
			end
			-- The lowest corner's travel while the foot is grounded at both ends.
			local beforePoints, groundedBefore = at(index - step)
			local anyNow, anyBefore = false, false
			for corner = 1, #points do
				anyNow = anyNow or grounded[corner]
				anyBefore = anyBefore or groundedBefore[corner]
			end
			if anyNow and anyBefore then
				local jump = flat(lowestOf(points) - lowestOf(beforePoints))
				if worstJump == nil or jump > (worstJump :: Slide).studs then
					worstJump = { foot = foot, studs = jump, time = frame.time, clipTime = shownTime(frame) }
				end
			end
		end
		if worstSlide ~= nil then
			table.insert(report.slides, worstSlide)
		end
		if worstDrift ~= nil then
			table.insert(report.drifts, worstDrift)
		end
		if worstJump ~= nil then
			table.insert(report.jumps, worstJump)
		end
		if deepest ~= nil then
			table.insert(report.sink, deepest)
		end
	end

	-- The strikes.
	if body.tip ~= nil then
		for index, span in strikeSpans(clip) do
			local a0, a1 = frameAt(frames, span.anticipation.start), frameAt(frames, span.anticipation.finish)
			local s0, s1 = frameAt(frames, span.snap.start), frameAt(frames, span.snap.finish)
			if a0 == nil or a1 == nil or s0 == nil or s1 == nil then
				continue
			end
			local tips: { [number]: Vector3 } = {}
			local function tipAt(frameIndex: number): Vector3
				local cached = tips[frameIndex]
				if cached == nil then
					cached = tipOf(body, frames[frameIndex]) :: Vector3
					tips[frameIndex] = cached
				end
				return cached :: Vector3
			end
			local anticipation = tipAt(a1 :: number) - tipAt(a0 :: number)
			local strike = tipAt(s1 :: number) - tipAt(s0 :: number)
			local firstStep = tipAt(math.min((s0 :: number) + step, #frames)) - tipAt(s0 :: number)
			local function cosine(u: Vector3, v: Vector3): number
				if u.Magnitude < 1e-6 or v.Magnitude < 1e-6 then
					return 0
				end
				return u.Unit:Dot(v.Unit)
			end
			local anticipationPeak, snapPeak, snapPeakAt, count = 0, 0, span.snap.start, 0
			local hiddenCounts: { [string]: number } = {}
			for frameIndex = a0 :: number, a1 :: number do
				count += 1
				for _, view in body.views do
					if hiddenFrom(body, frames[frameIndex], tipAt(frameIndex), view) then
						hiddenCounts[view] = (hiddenCounts[view] or 0) + 1
					end
				end
				if frameIndex - step >= (a0 :: number) then
					anticipationPeak =
						math.max(anticipationPeak, (tipAt(frameIndex) - tipAt(frameIndex - step)).Magnitude)
				end
			end
			for frameIndex = (s0 :: number) + 1, math.min((s1 :: number) + step, #frames) do
				if frameIndex - step >= 1 then
					local speed = (tipAt(frameIndex) - tipAt(frameIndex - step)).Magnitude
					if speed > snapPeak then
						snapPeak = speed
						snapPeakAt = frames[frameIndex].clipTime or snapPeakAt
					end
				end
			end
			local hiddenViews: { [string]: number } = {}
			local hidden = 0
			for _, view in body.views do
				local share = if count > 0 then (hiddenCounts[view] or 0) / count else 0
				hiddenViews[view] = share
				hidden = math.max(hidden, share)
			end
			table.insert(report.strikes, {
				index = index,
				snap = span.snap,
				anticipation = span.anticipation,
				cosine = cosine(anticipation, strike),
				firstCosine = cosine(anticipation, firstStep),
				travel = anticipation.Magnitude,
				anticipationPeak = anticipationPeak,
				snapPeak = snapPeak,
				snapPeakAt = snapPeakAt,
				hidden = hidden,
				hiddenViews = hiddenViews,
			})
		end
	end

	-- The return to what plays under it (not judged on the Lab's cut).
	if endIndex ~= nil and not plan.cutIn then
		local last = math.max(first, (endIndex :: number) - 1)
		local endTip = tipOf(body, frames[last])
		local settledTip = tipOf(body, frames[#frames])
		if endTip ~= nil and settledTip ~= nil then
			-- In the root's frame: root motion carried during the blend is not the pose's return.
			report.returnTip = (
				frames[last].root:PointToObjectSpace(endTip :: Vector3)
				- frames[#frames].root:PointToObjectSpace(settledTip :: Vector3)
			).Magnitude
		end
		local peak: Pop? = nil
		for index = math.max(endIndex :: number, step + 1), #frames do
			local now = frames[index]
			partSteps(body, frames[index - step], now, function(name: string, degrees: number)
				if peak == nil or degrees > (peak :: Pop).degrees then
					peak = { part = name, degrees = degrees, time = now.time, clipTime = nil }
				end
			end)
		end
		report.returnPeak = peak
	end

	-- The blade across the face over the Recovery: the share of the Recovery's samples with the
	-- blade's long axis in front of the face (in the head's frame: inside the face's width and
	-- height, ahead of its front), where it hides the face from the front.
	local beats: any = clip.beats
	local headName = config.head
	if clip.attack and beats ~= nil and beats.Recovery ~= nil and headName ~= nil and #body.weaponParts > 0 then
		local head = headName :: string
		local half = sizeOf(head) * 0.5
		local bladeName = body.weaponParts[1]
		local bladeSize = body.sizes[bladeName]
		local steps = Audit.segmentSamples
		local covered, count = 0, 0
		for index = first, #frames do
			local frame = frames[index]
			local clipTime = frame.clipTime
			if clipTime == nil or frame.ended or clipTime < beats.Recovery.start - EPSILON then
				continue
			end
			count += 1
			local blade = frame.solved[bladeName]
			local headFrame = frame.solved[head]
			local axis = blade.UpVector * (bladeSize.Y * 0.5)
			local from, to = blade.Position - axis, blade.Position + axis
			for sample = 0, steps do
				local point = headFrame:PointToObjectSpace(from:Lerp(to, sample / steps))
				if math.abs(point.X) <= half.X and math.abs(point.Y) <= half.Y and point.Z < -half.Z then
					covered += 1
					break
				end
			end
		end
		if count > 0 then
			report.recoveryFaceShare = covered / count
		end
	end
	return report
end

--- Traces and measures one clip under one plan at one rate.
function ClipAudit.run(body: Body, clip: Types.ClipDef, plan: Plan, hz: number): Report
	return ClipAudit.measure(body, clip, plan, ClipAudit.trace(body, plan, hz), hz)
end

-- ---------------------------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------------------------

--- One review finding: what broke a review.audit rule, where, and by how much.
export type Finding = {
	kind: string, -- one of review.audit.kinds
	what: string, -- the subject, with no number in it ("RightLowerArm into UpperTorso")
	size: number, -- the measure (degrees, studs, a cosine, a share)
	limit: number, -- the rule's bound
	excess: number, -- how far past the bound (always above 0)
	at: string, -- the clip frame or frames ("f23", "f7-27", "blend-out")
	plan: string,
	hz: number,
	text: string, -- one line for a reader
}

local function frameLabel(clipTime: number?): string
	if clipTime == nil then
		return "blend-out"
	end
	return ("f%d"):format(math.floor((clipTime :: number) * FPS + 0.5))
end

local function spanLabel(from: number, to: number): string
	local a, b = math.floor(from * FPS + 0.5), math.floor(to * FPS + 0.5)
	return if a == b then ("f%d"):format(a) else ("f%d-%d"):format(a, b)
end

--- The review findings of one report against review.audit's thresholds.
function ClipAudit.findings(clip: Types.ClipDef, report: Report): { Finding }
	local found: { Finding } = {}
	local function add(
		kind: string,
		what: string,
		size: number,
		limit: number,
		above: boolean,
		at: string,
		text: string
	)
		local excess = if above then size - limit else limit - size
		if excess <= EPSILON then
			return
		end
		table.insert(found, {
			kind = kind,
			what = what,
			size = size,
			limit = limit,
			excess = excess,
			at = at,
			plan = report.label,
			hz = report.hz,
			text = ("%s %s: %s at %s (%s %d Hz)"):format(kind, what, text, at, report.label, report.hz),
		})
	end
	for _, pop in report.pops do
		add(
			"Pop",
			pop.part,
			pop.degrees,
			Audit.popDegrees,
			true,
			frameLabel(pop.clipTime),
			("turns %.0f deg in one frame (max %d)"):format(pop.degrees, Audit.popDegrees)
		)
	end
	for _, back in report.turnBacks or {} do
		add(
			"Pop",
			back.part .. " back",
			back.degrees,
			Audit.reportDegrees,
			true,
			frameLabel(back.clipTime),
			("turns back %.0f deg inside the cancel's hand-over (max %d)"):format(back.degrees, Audit.reportDegrees)
		)
	end
	for _, overlap in report.overlaps do
		add(
			"Overlap",
			("%s into %s"):format(overlap.a, overlap.b),
			overlap.depth,
			Audit.overlapStuds,
			true,
			spanLabel(overlap.from, overlap.to),
			("%.2f deep (max %.2f)"):format(overlap.depth, Audit.overlapStuds)
		)
	end
	for _, overlap in report.weapon do
		add(
			"Weapon",
			("%s into %s"):format(overlap.a, overlap.b),
			overlap.depth,
			Audit.weaponStuds,
			true,
			spanLabel(overlap.from, overlap.to),
			("%.2f deep (max %.2f)"):format(overlap.depth, Audit.weaponStuds)
		)
	end
	for _, slide in report.slides do
		add(
			"Slide",
			slide.foot,
			slide.studs,
			Audit.footSlideStuds,
			true,
			frameLabel(slide.clipTime),
			("slides %.2f in one frame while planted (max %.2f)"):format(slide.studs, Audit.footSlideStuds)
		)
	end
	for _, drift in report.drifts do
		add(
			"Drift",
			drift.foot,
			drift.studs,
			Audit.footDriftStuds,
			true,
			frameLabel(drift.clipTime),
			("drifts %.2f over one plant (max %.2f)"):format(drift.studs, Audit.footDriftStuds)
		)
	end
	for _, sink in report.sink do
		add(
			"Sink",
			sink.foot,
			sink.studs,
			Audit.footSinkStuds,
			true,
			frameLabel(sink.clipTime),
			("%.2f below the field (max %.2f)"):format(sink.studs, Audit.footSinkStuds)
		)
	end
	local rules = Audit.anticipation
	for _, strike in report.strikes do
		if strike.index > 1 then
			continue -- one anticipation an attack (section 10 beat 1); a later strike's is reported only
		end
		local span = spanLabel(strike.anticipation.start, strike.anticipation.finish)
		local label = ("strike %d"):format(strike.index)
		add(
			"Anticipation",
			label .. " direction",
			strike.cosine,
			rules.maxCosine,
			true,
			span,
			("runs cos %+.2f against the cut (want <= %+.2f)"):format(strike.cosine, rules.maxCosine)
		)
		add(
			"Anticipation",
			label .. " travel",
			strike.travel,
			rules.minTravel,
			false,
			span,
			("moves the tip %.2f (want >= %.2f)"):format(strike.travel, rules.minTravel)
		)
		if strike.snapPeak > 0 then
			local share = strike.anticipationPeak / strike.snapPeak
			add(
				"Anticipation",
				label .. " speed",
				share,
				rules.maxSpeedShare,
				true,
				span,
				("peaks %.2f a frame, %.0f%% of the snap's %.2f (max %.0f%%)"):format(
					strike.anticipationPeak,
					share * 100,
					strike.snapPeak,
					rules.maxSpeedShare * 100
				)
			)
		end
		add(
			"Anticipation",
			label .. " hidden",
			strike.hidden,
			rules.maxHiddenShare,
			true,
			span,
			("tip behind the body from the gameplay camera %.0f%% of the beat (max %.0f%%)"):format(
				strike.hidden * 100,
				rules.maxHiddenShare * 100
			)
		)
	end
	local peak = report.returnPeak
	if peak ~= nil then
		add(
			"Return",
			peak.part,
			peak.degrees,
			Audit.popDegrees,
			true,
			"blend-out",
			("the blend back turns it %.0f deg in one frame (max %d)"):format(peak.degrees, Audit.popDegrees)
		)
	end
	if clip.attack and report.returnTip ~= nil then
		add(
			"Return",
			"tip",
			report.returnTip :: number,
			Audit.returnStuds,
			true,
			"blend-out",
			("ends %.2f from where the blend back puts it (max %.2f)"):format(
				report.returnTip :: number,
				Audit.returnStuds
			)
		)
	end
	if report.recoveryFaceShare ~= nil then
		local beats: any = clip.beats
		add(
			"Recovery",
			"blade across the face",
			report.recoveryFaceShare :: number,
			Audit.recoveryFaceShare,
			true,
			spanLabel(beats.Recovery.start, beats.Recovery.finish),
			("hides the face %.0f%% of the Recovery (max %.0f%%)"):format(
				(report.recoveryFaceShare :: number) * 100,
				Audit.recoveryFaceShare * 100
			)
		)
	end
	return found
end

--- The worst finding of each kind and subject (the largest excess), in review.audit.kinds order.
function ClipAudit.worst(findings: { Finding }): { Finding }
	local byKey: { [string]: Finding } = {}
	local order: { string } = {}
	for _, finding in findings do
		local key = finding.kind .. "|" .. finding.what
		local held = byKey[key]
		if held == nil then
			table.insert(order, key)
			byKey[key] = finding
		elseif finding.excess > held.excess + EPSILON then
			byKey[key] = finding
		end
	end
	local rank: { [string]: number } = {}
	for index, kind in Audit.kinds do
		rank[kind] = index
	end
	local list: { Finding } = {}
	for _, key in order do
		table.insert(list, byKey[key])
	end
	table.sort(list, function(a, b)
		local ra, rb = rank[a.kind] or math.huge, rank[b.kind] or math.huge
		if ra ~= rb then
			return ra < rb
		end
		return a.what < b.what
	end)
	return list
end

local function sizeText(finding: Finding): string
	if finding.kind == "Pop" or (finding.kind == "Return" and finding.what ~= "tip") then
		return ("%.0f deg"):format(finding.size)
	elseif
		finding.kind == "Recovery"
		or finding.what:find("hidden", 1, true)
		or finding.what:find("speed", 1, true)
	then
		return ("%.0f%%"):format(finding.size * 100)
	elseif finding.what:find("direction", 1, true) then
		return ("cos %+.2f"):format(finding.size)
	end
	return ("%.2f"):format(finding.size)
end

--- One short line a kind for a review table: the finding of each kind that is furthest past its
--- bound ("Pop RightHand 79 deg at f1 (Lab)"), in review.audit.kinds order.
function ClipAudit.problemLines(findings: { Finding }): { string }
	local worstOf: { [string]: Finding } = {}
	for _, finding in findings do
		local held = worstOf[finding.kind]
		if held == nil or finding.excess > held.excess + EPSILON then
			worstOf[finding.kind] = finding
		end
	end
	local lines: { string } = {}
	for _, kind in Audit.kinds do
		local finding = worstOf[kind]
		if finding ~= nil then
			table.insert(
				lines,
				("%s %s %s at %s (%s)"):format(kind, finding.what, sizeText(finding), finding.at, finding.plan)
			)
		end
	end
	return lines
end

--- The kinds a list of findings has, in review.audit.kinds order.
function ClipAudit.kindsOf(findings: { Finding }): { string }
	local seen: { [string]: boolean } = {}
	for _, finding in findings do
		seen[finding.kind] = true
	end
	local list: { string } = {}
	for _, kind in Audit.kinds do
		if seen[kind] then
			table.insert(list, kind)
		end
	end
	return list
end

--- Every plan of a clip at every audit rate: the reports and the findings of each.
function ClipAudit.audit(body: Body, clip: Types.ClipDef, library: (string) -> Types.ClipDef): ({ Report }, { Finding })
	local reports: { Report } = {}
	local findings: { Finding } = {}
	for _, plan in ClipAudit.plans(clip, library) do
		for _, hz in Audit.sampleHz do
			local report = ClipAudit.run(body, clip, plan, hz)
			table.insert(reports, report)
			for _, finding in ClipAudit.findings(clip, report) do
				table.insert(findings, finding)
			end
		end
	end
	return reports, findings
end

return ClipAudit

--!strict
--[[
	LocomotionState: the pure locomotion state machine (section 10 "Locomotion"). No Instances,
	no engine: Locomotion.luau feeds it numbers each frame and applies what comes back.

	In:  the move direction in the character's frame (forward, right), speed, sprinting,
	     grounded, drawn, the turning angle to the desired facing (when the caller knows it), the
	     yaw rate, the vertical velocity and the fall height on landing. Standing still, the yaw
	     rate is integrated: once the body has turned turnInPlaceDegrees since the last turn
	     clip a TurnLeft / TurnRight one-shot fires, so a rig that is rotated by lock-on (the
	     controller turns the root to a held lock and gives no angle, D-112) or by the engine (no
	     desired-facing input) still steps round instead of pivoting on a planted foot.
	     With the stick pushed no turn clip fires: the first steps take the turn.
	Out: target weights for the Base-layer clips (the 8-direction walk blend space, Run, Sprint,
	     Idle or IdleDrawn; with the weapon drawn the walks, Run and Sprint are the ...Drawn set,
	     sheathed the plain set), the one-shot to start this frame (Jump, Fall, Land with its squash
	     weight, none on the move, TurnLeft/TurnRight, Skid), the lean into the turn and the drawn-sprint additive
	     weight. A stop from above the skid threshold plays Skid; below it the root itself slows
	     over two steps (CharacterController carries it), so the gait just follows the speed.

	The gait is picked by cadence, not by fixed speeds. Each gait clip has a ground speed: how fast
	its planted foot moves back under the root at rate 1 (data/choreo.luau locomotion.stride,
	measured by tests/choreo/Stride.spec.luau). The walk shows alone up to its ground speed, Run
	alone at Run's and Sprint alone at Sprint's; between two gaits the share is the one at which the
	blend's cycle is its natural one. Below the walk's ground speed the walk slows to stride.rateFloor
	and then hands weight to Idle, which shortens the stride; above Sprint's the sprint speeds up.
	Each set has its own speeds, so the sheathed and drawn walks blend at their own points.
	Run's and Sprint's feet push along the facing. While the body turns to its move that is the
	move, but with the facing held off it (a lock-on strafe, D-112: no angle, a slow yaw) Run takes
	only the share whose foot stays on the move and the side walk carries the part across the
	facing; by runSpeed the cadence shares are back. Locomotion paces every gait clip to the root's
	real speed on one shared phase.

	Also the raycast foot IK math (two-bone legs, pelvis drop) as a pure function.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local ChoreoData = require(Shared.data.choreo)
local ClipSampler = require(Shared.choreo.ClipSampler)
local ClipLibrary = require(script.Parent.ClipLibrary)

local Config = ChoreoData.locomotion
local Stride = Config.stride

export type Input = {
	forward: number, -- move direction component along the facing (-1..1)
	right: number, -- move direction component to the right (-1..1)
	speed: number, -- horizontal studs per second
	sprinting: boolean,
	grounded: boolean,
	drawn: boolean,
	turning: number, -- signed degrees from the facing to the desired facing (+ = left)
	yawRate: number, -- degrees per second the facing is changing (+ = left)
	verticalVelocity: number,
	fallHeight: number?, -- studs fallen, meaningful on the frame grounded turns true
}

export type Phase = "Idle" | "Move" | "Stopping" | "Air"

--- What the two-step stop reads of the gait: the shared phase and, for each foot, the shared phase
--- of the walk's Footstep and the cycles after it at which that foot is over its Idle spot.
export type StopGait = { phase: number, leftStep: number, leftAfter: number, rightStep: number, rightAfter: number }

export type Output = {
	weights: { [string]: number },
	oneShot: string?,
	oneShotWeight: number,
	lean: number,
	drawnSprint: number,
	phase: Phase,
	airborne: boolean,
}

--- Where a clip has one foot: studs from the root (forward, right) and, for a gait clip, the cycle
--- fraction of that foot's Footstep (data/choreo.luau stride.touchdown).
export type Foot = { forward: number, right: number, at: number }

--- A gait clip at rate 1: its ground speed (studs per second its planted foot moves back under
--- the root), its cycle (the clip's duration), the ground one cycle covers (stride), the axis its
--- feet travel along in the character's frame (forward, right), whether it is a walk (paced along
--- its own axis), its phase offset (the cycle fraction of its left Footstep) and its feet.
export type Gait = {
	groundSpeed: number,
	duration: number,
	stride: number,
	forward: number,
	right: number,
	walk: boolean,
	offset: number,
	leftFoot: Foot,
	rightFoot: Foot,
}

export type State = {
	phase: Phase,
	previousSpeed: number,
	stopTimer: number,
	turnTimer: number,
	turnAccumulated: number, -- degrees of yaw turned while standing since the last turn clip
	lean: number,
	wasGrounded: boolean,
	airTime: number,
	update: (self: State, dt: number, input: Input) -> Output,
}

local LocomotionState = {}
LocomotionState.__index = LocomotionState

-- The Base-layer clips the blend space weighs: the sheathed set under the plain names, the drawn
-- set under the ...Drawn names (data/choreo.luau locomotion.clips).
local WEIGHT_NAMES = {
	"Idle",
	"IdleDrawn",
	"WalkForward",
	"WalkBack",
	"WalkLeft",
	"WalkRight",
	"Run",
	"Sprint",
	"WalkForwardDrawn",
	"WalkBackDrawn",
	"WalkLeftDrawn",
	"WalkRightDrawn",
	"RunDrawn",
	"SprintDrawn",
}
LocomotionState.WEIGHT_NAMES = WEIGHT_NAMES

-- The gait clips (every weighed clip but the idles): Locomotion paces these to the root.
local GAIT_NAMES = {
	"WalkForward",
	"WalkBack",
	"WalkLeft",
	"WalkRight",
	"Run",
	"Sprint",
	"WalkForwardDrawn",
	"WalkBackDrawn",
	"WalkLeftDrawn",
	"WalkRightDrawn",
	"RunDrawn",
	"SprintDrawn",
}
LocomotionState.GAIT_NAMES = GAIT_NAMES

-- A plain clip name -> its drawn-set name.
local DRAWN: { [string]: string } = {
	Idle = "IdleDrawn",
	WalkForward = "WalkForwardDrawn",
	WalkBack = "WalkBackDrawn",
	WalkLeft = "WalkLeftDrawn",
	WalkRight = "WalkRightDrawn",
	Run = "RunDrawn",
	Sprint = "SprintDrawn",
}

-- The axis each gait's feet travel along, in the character's frame (forward, right).
local AXIS: { [string]: { number } } = {
	WalkForward = { 1, 0 },
	WalkBack = { -1, 0 },
	WalkLeft = { 0, -1 },
	WalkRight = { 0, 1 },
	Run = { 1, 0 },
	Sprint = { 1, 0 },
}

-- The four walk clips in direction order (0 forward, 90 right, 180 back, 270 left).
local WALK_NAMES = { "WalkForward", "WalkRight", "WalkBack", "WalkLeft" }

--- The clip that carries a plain locomotion name in the set `drawn` picks (Run -> RunDrawn).
function LocomotionState.clipFor(name: string, drawn: boolean): string
	return if drawn then DRAWN[name] or name else name
end
local clipFor = LocomotionState.clipFor

local function clamp01(value: number): number
	return math.clamp(value, 0, 1)
end

local function zeroWeights(): { [string]: number }
	local weights = {}
	for _, name in WEIGHT_NAMES do
		weights[name] = 0
	end
	return weights
end

-- The cycle fraction of a clip's Footstep for `foot` ("Left" or "Right"; 0 when it has none): the
-- shared phase is 0 when every gait clip plants its left foot.
local function stepAt(clip: any, foot: string): number
	for _, event in clip.events do
		if event.kind == "Footstep" and event.data ~= nil and event.data.foot == foot then
			return event.time / clip.duration
		end
	end
	return 0
end

-- A clip's foot from data/choreo.luau stride.touchdown.
local function touchdownFoot(name: string, side: string, at: number): Foot
	local row = Stride.touchdown[name]
	assert(row ~= nil, "data/choreo.luau locomotion.stride.touchdown has no " .. name)
	local spot = if side == "left" then row.left else row.right
	return { forward = spot[1], right = spot[2], at = at }
end

local idleFeet: { [string]: { leftFoot: Foot, rightFoot: Foot } } = {}

--- Where an Idle clip ("Idle" or "IdleDrawn") stands each foot.
function LocomotionState.idleFeet(name: string): { leftFoot: Foot, rightFoot: Foot }
	local feet = idleFeet[name]
	if feet == nil then
		feet = { leftFoot = touchdownFoot(name, "left", 0), rightFoot = touchdownFoot(name, "right", 0) }
		idleFeet[name] = feet
	end
	return feet
end

local gaitTable: { [string]: Gait }? = nil

--- Every gait clip as a Gait: the ground speed from data, the cycle and the left Footstep from the
--- clip. Read once.
function LocomotionState.gaits(): { [string]: Gait }
	local gaits = gaitTable
	if gaits == nil then
		local built: { [string]: Gait } = {}
		for _, name in GAIT_NAMES do
			local groundSpeed = Stride.groundSpeed[name]
			assert(
				groundSpeed ~= nil and groundSpeed > 0,
				"data/choreo.luau locomotion.stride.groundSpeed has no " .. name
			)
			local clip = ClipLibrary.get(Config.clipPrefix .. Config.clips[name])
			local plain = name:gsub("Drawn$", "")
			local axis = AXIS[plain]
			built[name] = {
				groundSpeed = groundSpeed,
				duration = clip.duration,
				stride = groundSpeed * clip.duration,
				forward = axis[1],
				right = axis[2],
				walk = plain ~= "Run" and plain ~= "Sprint",
				offset = stepAt(clip, "Left"),
				leftFoot = touchdownFoot(name, "left", stepAt(clip, "Left")),
				rightFoot = touchdownFoot(name, "right", stepAt(clip, "Right")),
			}
		end
		gaitTable = built
		gaits = built
	end
	return gaits :: { [string]: Gait }
end

--- Direction weights for the four walk clips from a move direction in the character's frame.
--- 0 degrees is forward, 90 right, 180 back, 270 left; a diagonal splits between its neighbours.
function LocomotionState.directionWeights(forward: number, right: number): { [string]: number }
	local weights = { WalkForward = 0, WalkRight = 0, WalkBack = 0, WalkLeft = 0 }
	if math.abs(forward) < 1e-6 and math.abs(right) < 1e-6 then
		weights.WalkForward = 1
		return weights
	end
	local angle = math.deg(math.atan2(right, forward)) % 360
	local sector = angle / 90 -- unit: 90-degree sectors
	local lower = math.floor(sector)
	local alpha = sector - lower
	local count = #WALK_NAMES
	local first = WALK_NAMES[(lower % count) + 1]
	local second = WALK_NAMES[((lower + 1) % count) + 1]
	weights[first] += 1 - alpha
	weights[second] += alpha
	return weights
end

-- The two walks (plain names) a move direction splits between and their shares in a set; a zero
-- direction counts as forward. No allocation.
local function walkPair(forward: number, right: number, drawn: boolean): (string, number, string, number)
	if math.abs(forward) < 1e-6 and math.abs(right) < 1e-6 then
		return "WalkForward", 1, "WalkRight", 0
	end
	local angle = math.deg(math.atan2(right, forward)) % 360
	local sector = angle / 90 -- unit: 90-degree sectors
	local lower = math.floor(sector)
	local theta = (sector - lower) * math.pi / 2
	local count = #WALK_NAMES
	local first = WALK_NAMES[(lower % count) + 1]
	local second = WALK_NAMES[((lower + 1) % count) + 1]
	local gaits = LocomotionState.gaits()
	local toFirst = math.cos(theta) / gaits[clipFor(first, drawn)].stride
	local toSecond = math.sin(theta) / gaits[clipFor(second, drawn)].stride
	local total = toFirst + toSecond
	return first, toFirst / total, second, toSecond / total
end

--- Walk weights for a move direction in the character's frame (0 degrees forward, 90 right, 180
--- back, 270 left) in a set. A diagonal splits between its two neighbouring walks so the blend's
--- planted foot travels straight back along the move, not along a skew: each walk's foot moves
--- along its own axis by its stride per cycle, so the shares go as the angle's cosine (sine) over
--- that walk's stride. With equal strides this is the plain angle split.
function LocomotionState.walkWeights(forward: number, right: number, drawn: boolean): { [string]: number }
	local weights = { WalkForward = 0, WalkRight = 0, WalkBack = 0, WalkLeft = 0 }
	local first, firstShare, second, secondShare = walkPair(forward, right, drawn)
	weights[first] += firstShare
	weights[second] += secondShare
	return weights
end

--- Studs along a move direction (forward, right: a unit vector in the character's frame) from the
--- root to where clip `name` has the planted foot at shared phase `phase`: the foot whose Footstep
--- came last (the left one from phase 0, the right one from 0.5). A gait clip's foot moves back
--- along its axis by its stride per cycle from its Footstep; an Idle's stays where it stands.
function LocomotionState.plantedAlong(name: string, phase: number, forward: number, right: number): number
	local leftFoot = phase < 0.5
	local gait = LocomotionState.gaits()[name]
	if gait == nil then
		local feet = LocomotionState.idleFeet(name)
		local foot = if leftFoot then feet.leftFoot else feet.rightFoot
		return foot.forward * forward + foot.right * right
	end
	local foot = if leftFoot then gait.leftFoot else gait.rightFoot
	local since = ((phase + gait.offset) % 1 - foot.at) % 1
	if since > 0.5 then
		since -= 1 -- not down yet: still ahead of its touchdown
	end
	local back = gait.stride * since
	return (foot.forward - gait.forward * back) * forward + (foot.right - gait.right * back) * right
end

-- Cycles after its Footstep at which a two-walk blend's foot (one foot of each walk, shares a and
-- b) is over the Idle foot `rest`, along the move (forward, right), within half a cycle.
local function settleAfter(
	one: Gait,
	oneFoot: Foot,
	a: number,
	two: Gait,
	twoFoot: Foot,
	b: number,
	rest: Foot,
	forward: number,
	right: number
): number
	local reach = a * (oneFoot.forward * forward + oneFoot.right * right)
		+ b * (twoFoot.forward * forward + twoFoot.right * right)
	local perCycle = a * one.stride * (one.forward * forward + one.right * right)
		+ b * two.stride * (two.forward * forward + two.right * right)
	if perCycle <= 1e-6 then
		return 0
	end
	return math.clamp((reach - (rest.forward * forward + rest.right * right)) / perCycle, 0, 0.5)
end

--- Where the set's walk for a move direction has its planted foot over the spot the set's Idle
--- stands it on: for the left foot, then the right, the shared phase of its Footstep and the cycles
--- after it. A stop that ends there hands the feet over to Idle with the least slide (the two-step
--- stop). A foot that gets there only within stopHandOverCycles of the other foot's Footstep would
--- leave that foot coming down mid hand-over and skating to its own Idle spot, so its stop goes on
--- to the other foot's settle point half a cycle on (an after past half a cycle). No allocation.
function LocomotionState.settlePoints(forward: number, right: number, drawn: boolean): (number, number, number, number)
	local length = math.sqrt(forward * forward + right * right)
	if length < 1e-6 then
		forward, right, length = 1, 0, 1
	end
	forward /= length
	right /= length
	local first, a, second, b = walkPair(forward, right, drawn)
	local gaits = LocomotionState.gaits()
	local one, two = gaits[clipFor(first, drawn)], gaits[clipFor(second, drawn)]
	local rest = LocomotionState.idleFeet(clipFor("Idle", drawn))
	local leftAfter = settleAfter(one, one.leftFoot, a, two, two.leftFoot, b, rest.leftFoot, forward, right)
	local rightStep = a * ((one.rightFoot.at - one.offset) % 1) + b * ((two.rightFoot.at - two.offset) % 1)
	local rightAfter = settleAfter(one, one.rightFoot, a, two, two.rightFoot, b, rest.rightFoot, forward, right)
	local leftLate = leftAfter > rightStep - Config.stopHandOverCycles
	local rightLate = rightAfter > 1 - rightStep - Config.stopHandOverCycles
	if leftLate and not rightLate then
		leftAfter = rightStep + rightAfter
	elseif rightLate and not leftLate then
		rightAfter = 1 - rightStep + leftAfter
	end
	return 0, leftAfter, rightStep, rightAfter
end

--- The walk of a move direction as one gait: the ground speed along the move of the set's four
--- walks weighted by `direction` (each walk's planted foot moves along its own axis, so a diagonal
--- covers the component of the blend along the move), and the weighted cycle. (forward, right) is
--- the move direction; a zero one counts as forward.
function LocomotionState.walkGait(
	direction: { [string]: number },
	forward: number,
	right: number,
	drawn: boolean
): (number, number)
	if math.abs(forward) < 1e-6 and math.abs(right) < 1e-6 then
		forward = 1
	end
	local length = math.sqrt(forward * forward + right * right)
	forward /= length
	right /= length
	local gaits = LocomotionState.gaits()
	local along, duration = 0, 0
	for name, share in direction do
		if share > 0 then
			local gait = gaits[clipFor(name, drawn)]
			along += share * gait.groundSpeed * (gait.forward * forward + gait.right * right)
			duration += share * gait.duration
		end
	end
	return math.max(along, Stride.minGroundSpeed), duration
end

--- The speed (studs a second) from which the walk of a move direction shows alone: below it
--- gaitWeights slows the walk to stride.rateFloor and hands weight to Idle. (forward, right) is the
--- move direction in the character's frame.
function LocomotionState.wholeWalkSpeed(forward: number, right: number, drawn: boolean): number
	local walkSpeed =
		LocomotionState.walkGait(LocomotionState.walkWeights(forward, right, drawn), forward, right, drawn)
	return Stride.rateFloor * walkSpeed
end

-- The share of gait b at `speed`, between gaits a (slower) and b (faster), at which the blend's
-- cycle is its natural one: speed x the blended duration equals the blended stride.
local function cadenceShare(speed: number, aDuration: number, aStride: number, b: Gait): number
	local fromA = speed * aDuration - aStride -- >= 0 at or above a's ground speed
	local fromB = speed * b.duration - b.stride -- <= 0 at or below b's ground speed
	local span = fromA - fromB
	if span <= 0 then
		return if fromA > 0 then 1 else 0
	end
	return clamp01(fromA / span)
end

--- Gait shares (walk, run, sprint, idle; they sum to 1) for a speed, given the walk's ground speed
--- and cycle (LocomotionState.walkGait) and the set's Run and Sprint. Each gait shows alone at its
--- own ground speed; between two gaits the shares are the ones at which the blend plays at its
--- natural cadence. Below the walk's ground speed the walk slows down to stride.rateFloor and
--- below that hands weight to Idle, so a slow walk takes shorter steps rather than slower ones.
--- With no Run and Sprint (a move into the back half, where their feet would push the wrong way)
--- the walk alone speeds up past its ground speed; with no Sprint (not sprinting) Run does.
function LocomotionState.gaitWeights(
	speed: number,
	walkSpeed: number,
	walkDuration: number,
	run: Gait?,
	sprint: Gait?
): (number, number, number, number)
	if speed <= walkSpeed or run == nil then
		local share = clamp01(speed / (Stride.rateFloor * walkSpeed))
		return share, 0, 0, 1 - share
	end
	if speed <= run.groundSpeed or sprint == nil then
		local share = cadenceShare(speed, walkDuration, walkSpeed * walkDuration, run)
		return 1 - share, share, 0, 0
	end
	if speed <= sprint.groundSpeed then
		local share = cadenceShare(speed, run.duration, run.stride, sprint)
		return 0, 1 - share, share, 0
	end
	return 0, 0, 1, 0
end

-- True when Run and Sprint may carry a move: one into the forward half, or one the body is turning
-- to face (the controller's angle to the stick past turnInPlaceDegrees, or a facing turning faster
-- than stride.turnYawRate on a rig that gives no angle). A move held behind the facing (lock-on,
-- where CharacterController also holds the speed to a walk, D-112) stays with the walks, whose feet
-- push the right way.
local function runsAhead(input: Input): boolean
	if input.forward > 1e-6 or (math.abs(input.forward) <= 1e-6 and math.abs(input.right) <= 1e-6) then
		return true
	end
	return math.abs(input.turning) > Config.turnInPlaceDegrees or math.abs(input.yawRate) > Stride.turnYawRate
end

-- True when the body is turning to face its move: the controller gives the angle to it, or the
-- facing turns faster than stride.turnYawRate. The controller gives no angle while a lock holds the
-- facing (D-112) or a swing holds it, and Locomotion.humanoidTracker's rigs give none.
local function turningToMove(input: Input): boolean
	return math.abs(input.turning) > 1e-6 or math.abs(input.yawRate) > Stride.turnYawRate
end

--- How far along the move one stud of Run's or Sprint's stride carries: their planted feet go
--- straight back along the facing. While the body turns to its move it faces it within a step, so
--- the whole stride counts; with the facing held off the move (a lock-on strafe, D-112) only the
--- move's part along the facing does. Locomotion paces the gait clips with it.
function LocomotionState.runAlong(input: Input): number
	local length = math.sqrt(input.forward * input.forward + input.right * input.right)
	if length < 1e-6 or turningToMove(input) then
		return 1
	end
	return input.forward / length
end

-- A move into the forward half with a part across the facing, which the body is not turning to:
-- the shares of the forward walk, the side walk and Run (they sum to 1) at which the blend's planted
-- foot goes straight back along the move. The forward walk's and Run's feet go back along the
-- facing and the side walk's across it, so each axis covers its part of the move: forward share x
-- stride + Run share x stride = speed x along x cycle, side share x stride = speed x across x
-- cycle, the cycle being the shares' mean duration (the blend's natural cadence). Where that would
-- need a negative forward walk (the side walk cannot cover its part at its natural cadence: a
-- quick strafe) it is Run and the side walk alone, in the ratio that keeps the foot on the move,
-- played faster; where it would need a negative Run (a slow move) the two walks alone. No
-- allocation.
local function heldShares(
	speed: number,
	along: number,
	across: number,
	forwardWalk: Gait,
	sideWalk: Gait,
	run: Gait
): (number, number, number)
	local a1 = forwardWalk.stride - speed * along * forwardWalk.duration
	local b1 = -speed * along * sideWalk.duration
	local c1 = run.stride - speed * along * run.duration
	local a2 = -speed * across * forwardWalk.duration
	local b2 = sideWalk.stride - speed * across * sideWalk.duration
	local c2 = -speed * across * run.duration
	local determinant = a1 * (b2 - c2) - b1 * (a2 - c2) + c1 * (a2 - b2)
	local forwardShare, sideShare, runShare = -1, 0, 0
	if math.abs(determinant) > 1e-6 then
		forwardShare = (b1 * c2 - c1 * b2) / determinant
		sideShare = (c1 * a2 - a1 * c2) / determinant
		runShare = (a1 * b2 - b1 * a2) / determinant
		if forwardShare >= 0 and sideShare >= 0 and runShare >= 0 then
			return forwardShare, sideShare, runShare
		end
	end
	if forwardShare < 0 then
		local runAcross = run.stride * across
		local sideAlong = sideWalk.stride * along
		return 0, runAcross / (runAcross + sideAlong), sideAlong / (runAcross + sideAlong)
	end
	local forwardPart = along / forwardWalk.stride
	local sidePart = across / sideWalk.stride
	return forwardPart / (forwardPart + sidePart), sidePart / (forwardPart + sidePart), 0
end

-- Writes the weights of a moving frame into `weights` (the set's walks by direction, Run, Sprint
-- and Idle by cadence) and returns the Sprint share. Sprint shows only while sprinting, and then
-- as soon as the speed clears Run's ground speed.
local function moveWeights(weights: { [string]: number }, speed: number, input: Input): number
	local drawn = input.drawn
	local direction = LocomotionState.walkWeights(input.forward, input.right, drawn)
	local walkSpeed, walkDuration = LocomotionState.walkGait(direction, input.forward, input.right, drawn)
	local gaits = LocomotionState.gaits()
	local ahead = runsAhead(input)
	local runGait = if ahead then gaits[clipFor("Run", drawn)] else nil
	local sprintGait = if ahead and input.sprinting then gaits[clipFor("Sprint", drawn)] else nil
	local walk, run, sprint, idle = LocomotionState.gaitWeights(speed, walkSpeed, walkDuration, runGait, sprintGait)
	if input.sprinting and runGait ~= nil and speed > runGait.groundSpeed then
		run, sprint = 0, run + sprint
	end
	for name, share in direction do
		weights[clipFor(name, drawn)] = share * walk
	end
	weights[clipFor("Run", drawn)] = run
	weights[clipFor("Sprint", drawn)] = sprint
	weights[clipFor("Idle", drawn)] = idle
	-- A move with a part across a facing held off it (a lock-on strafe, D-112), past the walks'
	-- own ground speed: Run's feet push along the facing, so Run takes only as much as keeps the
	-- planted foot on the move and the side walk carries the rest (heldShares). That holds at
	-- walkSpeed (the speed a lock holds the body to) and hands back to the cadence shares above
	-- by runSpeed: a running body turns into its move, and a rig whose facing lags its velocity by a
	-- few degrees keeps its run.
	local length = math.sqrt(input.forward * input.forward + input.right * input.right)
	if runGait ~= nil and speed > walkSpeed and not turningToMove(input) and length > 1e-6 then
		local along, across = input.forward / length, math.abs(input.right) / length
		local held = clamp01((Config.runSpeed - speed) / (Config.runSpeed - Config.walkSpeed))
		if along > 1e-6 and across > 1e-6 and held > 0 then
			local forwardName = clipFor("WalkForward", drawn)
			local sideName = clipFor(if input.right > 0 then "WalkRight" else "WalkLeft", drawn)
			local runName = clipFor("Run", drawn)
			local forwardShare, sideShare, runShare =
				heldShares(speed, along, across, gaits[forwardName], gaits[sideName], runGait)
			for name, weight in weights do
				weights[name] = weight * (1 - held)
			end
			weights[forwardName] += held * forwardShare
			weights[sideName] += held * sideShare
			weights[runName] += held * runShare
			sprint *= 1 - held
		end
	end
	return sprint
end

--- Landing squash weight from the fall height (data: minSquash .. 1 at fullSquashHeight).
function LocomotionState.landingWeight(fallHeight: number?): number
	if fallHeight == nil then
		return Config.landing.minSquash
	end
	return math.clamp(fallHeight / Config.landing.fullSquashHeight, Config.landing.minSquash, 1)
end

--- Creates a state machine standing still, sheathed, on the ground.
function LocomotionState.new(): State
	local self = setmetatable({
		phase = "Idle",
		previousSpeed = 0,
		stopTimer = 0,
		turnTimer = 0,
		turnAccumulated = 0,
		lean = 0,
		wasGrounded = true,
		airTime = 0,
	}, LocomotionState)
	return (self :: any) :: State
end

function LocomotionState.update(self: any, dt: number, input: Input): Output
	local weights = zeroWeights()
	local oneShot: string? = nil
	local oneShotWeight = 1
	local speed = math.max(0, input.speed)
	local moving = speed > Config.idleSpeedThreshold

	-- Lean into turns while moving; decays to zero standing still.
	local leanTarget = 0
	if moving then
		leanTarget = math.clamp(input.yawRate * Config.lean.degreesPerYawRate, -Config.lean.max, Config.lean.max)
	end
	self.lean += (leanTarget - self.lean) * math.min(1, dt * Config.lean.rate)

	self.turnTimer = math.max(0, self.turnTimer - dt)

	if not input.grounded then
		if self.wasGrounded then
			self.airTime = 0
			oneShot = if input.verticalVelocity > Config.jumpVelocity then "Jump" else "Fall"
		end
		self.airTime += dt
		self.phase = "Air"
		self.wasGrounded = false
		self.previousSpeed = speed
		-- Keep the gait weights alive underneath so the landing blends back into motion.
		if moving then
			moveWeights(weights, speed, input)
		else
			weights[clipFor("Idle", input.drawn)] = 1
		end
		return {
			weights = weights,
			oneShot = oneShot,
			oneShotWeight = 1,
			lean = self.lean,
			drawnSprint = 0,
			phase = "Air",
			airborne = true,
		}
	end

	if not self.wasGrounded then
		-- Landing frame. On the move the gait carries the landing: the squash's legs would slide
		-- under the root, so Land shows no weight (it still sounds).
		oneShot = "Land"
		oneShotWeight = if moving then 0 else LocomotionState.landingWeight(input.fallHeight)
		self.wasGrounded = true
		self.phase = if moving then "Move" else "Idle"
	end

	-- Stop detection: a sharp drop in speed from above the skid threshold plays Skid (a skid is
	-- meant to slide: the root stops under it). Below the threshold the root slows down by itself
	-- (CharacterController's two-step stop), so the gait simply follows the speed.
	local dropped = self.previousSpeed - speed
	if moving then
		if dropped > Config.stopSpeedDrop and self.previousSpeed > Config.skidSpeedThreshold then
			oneShot = oneShot or "Skid"
		end
		self.phase = "Move"
	elseif self.phase == "Move" then
		-- The frame the character stops.
		if self.previousSpeed > Config.skidSpeedThreshold then
			oneShot = oneShot or "Skid"
			self.phase = "Stopping"
			self.stopTimer = Config.stopStepsSeconds
		else
			self.phase = "Idle"
		end
	elseif self.phase == "Stopping" then
		self.stopTimer -= dt
		if self.stopTimer <= 0 then
			self.phase = "Idle"
		end
	else
		self.phase = "Idle"
	end
	self.previousSpeed = speed

	local drawnSprint = 0
	if moving then
		local sprint = moveWeights(weights, speed, input)
		if input.drawn then
			drawnSprint = sprint
		end
		self.turnAccumulated = 0
	else
		weights[clipFor("Idle", input.drawn)] = 1
		-- Turn in place when the body wants to face elsewhere (or has already turned that far
		-- on the spot) and nothing else is playing. With the stick pushed the root is about to
		-- move, so the first steps take the turn.
		local pushed = input.forward ~= 0 or input.right ~= 0
		self.turnAccumulated = if pushed then 0 else self.turnAccumulated + input.yawRate * dt
		local turn = if math.abs(input.turning) > Config.turnInPlaceDegrees then input.turning else self.turnAccumulated
		if oneShot == nil and not pushed and math.abs(turn) > Config.turnInPlaceDegrees and self.turnTimer <= 0 then
			oneShot = if turn > 0 then "TurnLeft" else "TurnRight"
			self.turnTimer = Config.turnClipDuration
			self.turnAccumulated = 0
		end
	end

	return {
		weights = weights,
		oneShot = oneShot,
		oneShotWeight = oneShotWeight,
		lean = self.lean,
		drawnSprint = drawnSprint,
		phase = self.phase,
		airborne = false,
	}
end

-- ---------------------------------------------------------------------------------------------
-- Foot IK (two-bone legs; pure)
-- ---------------------------------------------------------------------------------------------

local IK = Config.footIK

local function legBend(lift: number): (number, number, number)
	local a = IK.thighLength
	local b = IK.shinLength
	local target = math.max(math.abs(a - b) + 1e-6, a + b - math.clamp(lift, 0, IK.maxAdjust))
	local kneeInterior = math.acos(math.clamp((a * a + b * b - target * target) / (2 * a * b), -1, 1))
	local kneeBend = math.deg(math.pi - kneeInterior)
	local hipPitch = math.deg(math.acos(math.clamp((a * a + target * target - b * b) / (2 * a * target), -1, 1)))
	return hipPitch, kneeBend, kneeBend - hipPitch
end

--- Joint offsets that plant both feet on uneven ground. `leftDelta` / `rightDelta` are the ground
--- heights under each foot relative to the ground the character stands on (positive = higher; nil
--- = no hit). The pelvis drops by the lower foot's deficit, each leg bends to lift its foot by the
--- rest, and the ankles keep the feet level. `weight` scales the whole result.
function LocomotionState.footIK(leftDelta: number?, rightDelta: number?, weight: number): ClipSampler.Offsets
	local left = leftDelta or 0
	local right = rightDelta or 0
	local drop = math.clamp(-math.min(left, right, 0), 0, IK.maxAdjust)
	local offsets: ClipSampler.Offsets = {}
	if weight <= 0 then
		return offsets
	end
	local w = clamp01(weight)
	offsets.Root = { pos = { 0, -drop * w, 0 }, rot = { 0, 0, 0 } }
	for _, side in { { "Left", left }, { "Right", right } } do
		local name = side[1] :: string
		local delta = side[2] :: number
		local lift = math.clamp(delta + drop, 0, IK.maxAdjust)
		local hip, knee, ankle = legBend(lift)
		offsets[name .. "Hip"] = { pos = { 0, 0, 0 }, rot = { hip * w, 0, 0 } }
		offsets[name .. "Knee"] = { pos = { 0, 0, 0 }, rot = { -knee * w, 0, 0 } }
		offsets[name .. "Ankle"] = { pos = { 0, 0, 0 }, rot = { ankle * w, 0, 0 } }
	end
	return offsets
end

--- Weight of the foot IK for a speed: full when standing, gone at footIK.fadeSpeed.
function LocomotionState.footIKWeight(speed: number, grounded: boolean): number
	if not grounded then
		return 0
	end
	return clamp01(1 - speed / IK.fadeSpeed)
end

--- Additive lean offsets (degrees of roll into the turn): the waist leans and the head cancels
--- lean.neckCounterFraction of it.
function LocomotionState.leanOffsets(lean: number): ClipSampler.Offsets
	return {
		Waist = { pos = { 0, 0, 0 }, rot = { 0, 0, lean } },
		Neck = { pos = { 0, 0, 0 }, rot = { 0, 0, -lean * Config.lean.neckCounterFraction } },
	}
end

return LocomotionState

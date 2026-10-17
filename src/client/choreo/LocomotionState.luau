--!strict
--[[
	LocomotionState: the pure locomotion state machine (section 10 "Locomotion"). No Instances,
	no engine: Locomotion.luau feeds it numbers each frame and applies what comes back.

	In:  the move direction in the character's frame (forward, right), speed, sprinting,
	     grounded, drawn, the turning angle to the desired facing (when the caller knows it), the
	     yaw rate, the vertical velocity and the fall height on landing. Standing still, the yaw
	     rate is integrated: once the body has turned turnInPlaceDegrees since the last turn
	     clip a TurnLeft / TurnRight one-shot fires, so a rig that is rotated by lock-on or by the
	     engine (no desired-facing input) still steps round instead of pivoting on a planted foot.
	Out: target weights for the Base-layer clips (the 8-direction walk blend space, Run, Sprint,
	     Idle or IdleDrawn), the one-shot to start this frame (Jump, Fall, Land with its squash
	     weight, TurnLeft/TurnRight, Skid), the lean into the turn and the drawn-sprint additive
	     weight. The two-step stop decays a virtual speed through the walk gait; a stop from above
	     the skid threshold plays Skid instead.

	Also the raycast foot IK math (two-bone legs, pelvis drop) as a pure function.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local ChoreoData = require(Shared.data.choreo)
local ClipSampler = require(Shared.choreo.ClipSampler)

local Config = ChoreoData.locomotion

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

export type Output = {
	weights: { [string]: number },
	oneShot: string?,
	oneShotWeight: number,
	lean: number,
	drawnSprint: number,
	phase: Phase,
	airborne: boolean,
}

export type State = {
	phase: Phase,
	previousSpeed: number,
	virtualSpeed: number,
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

local WEIGHT_NAMES = { "Idle", "IdleDrawn", "WalkForward", "WalkBack", "WalkLeft", "WalkRight", "Run", "Sprint" }
LocomotionState.WEIGHT_NAMES = WEIGHT_NAMES

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

--- Direction weights for the four walk clips from a move direction in the character's frame.
--- 0 degrees is forward, 90 right, 180 back, 270 left; a diagonal splits between its neighbours.
function LocomotionState.directionWeights(forward: number, right: number): { [string]: number }
	local weights = { WalkForward = 0, WalkRight = 0, WalkBack = 0, WalkLeft = 0 }
	if math.abs(forward) < 1e-6 and math.abs(right) < 1e-6 then
		weights.WalkForward = 1
		return weights
	end
	local angle = math.deg(math.atan2(right, forward)) % 360
	local names = { "WalkForward", "WalkRight", "WalkBack", "WalkLeft" }
	local sector = angle / 90 -- unit: 90-degree sectors
	local lower = math.floor(sector)
	local alpha = sector - lower
	local count = #names
	local first = names[(lower % count) + 1]
	local second = names[((lower + 1) % count) + 1]
	weights[first] += 1 - alpha
	weights[second] += alpha
	return weights
end

--- Gait weights (walk, run, sprint shares summing to 1) for a speed.
function LocomotionState.gaitWeights(speed: number): (number, number, number)
	if speed <= Config.walkSpeed then
		return 1, 0, 0
	elseif speed <= Config.runSpeed then
		local alpha = (speed - Config.walkSpeed) / (Config.runSpeed - Config.walkSpeed)
		return 1 - alpha, alpha, 0
	end
	local alpha = clamp01((speed - Config.runSpeed) / (Config.sprintSpeed - Config.runSpeed))
	return 0, 1 - alpha, alpha
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
		virtualSpeed = 0,
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

	-- Lean into turns while moving; decays to zero standing still.
	local leanTarget = 0
	if speed > Config.idleSpeedThreshold then
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
		self.virtualSpeed = speed
		-- Keep the gait weights alive underneath so the landing blends back into motion.
		local walk, run, sprint = LocomotionState.gaitWeights(speed)
		if speed > Config.idleSpeedThreshold then
			for name, share in LocomotionState.directionWeights(input.forward, input.right) do
				weights[name] = share * walk
			end
			weights.Run = run
			weights.Sprint = sprint
		else
			weights[if input.drawn then "IdleDrawn" else "Idle"] = 1
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
		-- Landing frame
		oneShot = "Land"
		oneShotWeight = LocomotionState.landingWeight(input.fallHeight)
		self.wasGrounded = true
		self.phase = if speed > Config.idleSpeedThreshold then "Move" else "Idle"
	end

	-- Stop detection: a sharp drop in speed from a run plays Skid; any stop from a walk or run
	-- decays a virtual speed through the walk gait (the two-step stop).
	local dropped = self.previousSpeed - speed
	if speed > Config.idleSpeedThreshold then
		if dropped > Config.stopSpeedDrop and self.previousSpeed > Config.skidSpeedThreshold then
			oneShot = oneShot or "Skid"
		end
		self.phase = "Move"
		self.virtualSpeed = speed
	elseif self.phase == "Move" then
		-- The frame the character stops.
		if self.previousSpeed > Config.skidSpeedThreshold then
			oneShot = oneShot or "Skid"
			self.phase = "Stopping"
			self.stopTimer = Config.stopStepsSeconds
			self.virtualSpeed = 0
		elseif self.previousSpeed > Config.walkSpeed * 0.5 then
			self.phase = "Stopping"
			self.stopTimer = Config.stopStepsSeconds
			self.virtualSpeed = self.previousSpeed
		else
			self.phase = "Idle"
		end
	elseif self.phase == "Stopping" then
		self.stopTimer -= dt
		if self.stopTimer <= 0 then
			self.phase = "Idle"
			self.virtualSpeed = 0
		else
			-- Decay toward zero across the stop so the gait passes through the walk clips.
			self.virtualSpeed = math.max(0, self.virtualSpeed - dt * (self.previousSpeed / Config.stopStepsSeconds))
		end
	else
		self.phase = "Idle"
		self.virtualSpeed = 0
	end

	local gaitSpeed = if self.phase == "Stopping" then self.virtualSpeed else speed
	local drawnSprint = 0
	if gaitSpeed > Config.idleSpeedThreshold then
		local walk, run, sprint = LocomotionState.gaitWeights(gaitSpeed)
		if input.sprinting and gaitSpeed > Config.runSpeed then
			-- Sprinting reads as sprint as soon as the speed clears run speed.
			run, sprint = 0, run + sprint
		end
		local direction = if self.phase == "Stopping"
			then { WalkForward = 1, WalkRight = 0, WalkBack = 0, WalkLeft = 0 }
			else LocomotionState.directionWeights(input.forward, input.right)
		for name, share in direction do
			weights[name] = share * walk
		end
		weights.Run = run
		weights.Sprint = sprint
		if input.drawn then
			drawnSprint = sprint
		end
	else
		weights[if input.drawn then "IdleDrawn" else "Idle"] = 1
		-- Turn in place when the body wants to face elsewhere (or has already turned that far
		-- on the spot) and nothing else is playing.
		self.turnAccumulated += input.yawRate * dt
		local turn = if math.abs(input.turning) > Config.turnInPlaceDegrees then input.turning else self.turnAccumulated
		if oneShot == nil and math.abs(turn) > Config.turnInPlaceDegrees and self.turnTimer <= 0 then
			oneShot = if turn > 0 then "TurnLeft" else "TurnRight"
			self.turnTimer = Config.turnClipDuration
			self.turnAccumulated = 0
		end
	end
	if gaitSpeed > Config.idleSpeedThreshold then
		self.turnAccumulated = 0
	end

	if self.phase ~= "Stopping" then
		self.previousSpeed = speed
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

--- Additive lean offsets (degrees of roll into the turn): the waist leans, the head stays level.
function LocomotionState.leanOffsets(lean: number): ClipSampler.Offsets
	return {
		Waist = { pos = { 0, 0, 0 }, rot = { 0, 0, lean } },
		Neck = { pos = { 0, 0, 0 }, rot = { 0, 0, -lean * 0.5 } },
	}
end

return LocomotionState

--!strict
--[[
	Locomotion: the engine binding of the locomotion blend space (section 10 "Locomotion").

		local locomotion = Locomotion.new(animator, character)
		locomotion:update(dt, { moveDir = Vector3, speed = n, sprinting = b, grounded = b,
		                        drawn = b, turning = degrees, fallHeight = n? })
		locomotion:setDrawn(true)
		locomotion:destroy()

	It keeps one Base-layer handle per locomotion clip (Idle, IdleDrawn, the four walks, Run,
	Sprint) and drives their weights from LocomotionState every frame; one-shots (Jump, Fall,
	Land, TurnLeft, TurnRight, Skid) play on the FullBody layer; the lean into turns, the drawn
	sprint "weapon low and back" pose and the raycast foot IK ride as procedural additive channels.
	The raycast is injected so the IK math stays pure and tested; the default uses workspace.

	For rigs the local CharacterController does not own (other players, enemies),
	Locomotion.attach(animator, character) runs a driver off the animator's own step: a player rig
	gets this same blend space fed by Locomotion.humanoidTracker (MoveDirection, velocity, floor
	contact, fall height); an enemy rig gets its data Idle / Walk pair (data/choreo.luau rigs)
	crossfaded by speed with the walk clip paced to the rig's walkSpeed, so no foot slides.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local ChoreoData = require(Shared.data.choreo)
local Rigs = require(Shared.data.rigs)
local ClipSampler = require(Shared.choreo.ClipSampler)
local LocomotionState = require(script.Parent.LocomotionState)

local Config = ChoreoData.locomotion

export type State = {
	moveDir: Vector3, -- world-space move direction (any length; zero when still)
	speed: number, -- horizontal studs per second
	sprinting: boolean,
	grounded: boolean,
	drawn: boolean?, -- overrides setDrawn when given
	turning: number, -- signed degrees from the facing to the desired facing (+ = left)
	fallHeight: number?, -- studs fallen, on the landing frame
	verticalVelocity: number?,
}

export type Raycast = (origin: Vector3, direction: Vector3) -> Vector3?

export type Dependencies = {
	raycast: Raycast?,
	footIK: boolean?, -- default true
	tracker: ((dt: number) -> State?)?, -- attach only: the state source (default humanoidTracker)
}

export type Locomotion = {
	update: (self: Locomotion, dt: number, state: State) -> LocomotionState.Output,
	setDrawn: (self: Locomotion, drawn: boolean) -> (),
	destroy: (self: Locomotion) -> (),
}

local Locomotion = {}
Locomotion.__index = Locomotion

local function clipId(name: string): string
	return Config.clipPrefix .. Config.clips[name]
end

local function wrapDegrees(angle: number): number
	return (angle + 180) % 360 - 180
end

local function yawOf(cframe: CFrame): number
	local look = cframe.LookVector
	return math.deg(math.atan2(-look.X, -look.Z))
end

-- The drawn-sprint data pose as full offsets (pos filled with zero) so the mixer can add it.
local function poseOffsets(pose: { [string]: { pos: { number }?, rot: { number }? } }): ClipSampler.Offsets
	local offsets: ClipSampler.Offsets = {}
	for name, key in pose do
		offsets[name] = { pos = key.pos or { 0, 0, 0 }, rot = key.rot or { 0, 0, 0 } }
	end
	return offsets
end

local DRAWN_SPRINT = poseOffsets(Config.drawnSprintPose)

local function defaultRaycast(character: Model): Raycast
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	return function(origin: Vector3, direction: Vector3): Vector3?
		local result = workspace:Raycast(origin, direction, params)
		return if result then result.Position else nil
	end
end

-- Enemy rig driver (data Idle / Walk pair), defined below Locomotion; declared here so
-- Locomotion.destroy can dispatch to it.
local RigDriver = {}

--- Creates the locomotion driver for an animator and its character model.
function Locomotion.new(animator: any, character: Model, deps: Dependencies?): Locomotion
	local dependencies: Dependencies = deps or {}
	local self = setmetatable({
		animator = animator,
		character = character,
		state = LocomotionState.new(),
		handles = {} :: { [string]: any },
		fallHandle = nil :: any,
		jumpHandle = nil :: any,
		drawn = false,
		lastYaw = nil :: number?,
		raycast = dependencies.raycast,
		footIK = dependencies.footIK ~= false,
		hipHeight = (Rigs[animator.rigId] or Rigs.PlayerR15).hipHeight,
		destroyed = false,
	}, Locomotion)
	if self.raycast == nil and self.footIK then
		self.raycast = defaultRaycast(character)
	end
	for _, name in LocomotionState.WEIGHT_NAMES do
		self.handles[name] = animator:play(clipId(name), { coexist = true, weight = 0, blendIn = 0 })
	end
	animator:setWeight(self.handles.Idle, 1, true)
	return (self :: any) :: Locomotion
end

function Locomotion.setDrawn(self: any, drawn: boolean)
	self.drawn = drawn
end

local function playOneShot(self: any, name: string, weight: number?)
	return self.animator:play(clipId(name), { weight = weight })
end

local function footDeltas(self: any, root: BasePart): (number?, number?)
	local raycast: Raycast = self.raycast
	local ik = Config.footIK
	local expectedGround = root.Position.Y - self.hipHeight - root.Size.Y * 0.5
	local rightVector = root.CFrame.RightVector
	local function probe(side: number): number?
		local base = root.Position + rightVector * (side * ik.footSpacing)
		local origin = Vector3.new(base.X, expectedGround + ik.rayStart, base.Z)
		local hit = raycast(origin, Vector3.new(0, -(ik.rayStart + ik.rayLength), 0))
		return if hit then hit.Y - expectedGround else nil
	end
	return probe(-1), probe(1)
end

function Locomotion.update(self: any, dt: number, state: State): LocomotionState.Output
	local animator = self.animator
	local root: BasePart? = self.character.PrimaryPart or self.character:FindFirstChild("HumanoidRootPart") :: any
	local forward, right = 0, 0
	local yawRate = 0
	if root ~= nil then
		local cframe = root.CFrame
		local move = Vector3.new(state.moveDir.X, 0, state.moveDir.Z)
		if move.Magnitude > 0 then
			move = move.Unit
			forward = move:Dot(cframe.LookVector)
			right = move:Dot(cframe.RightVector)
		end
		local yaw = yawOf(cframe)
		if self.lastYaw ~= nil and dt > 0 then
			yawRate = wrapDegrees(yaw - self.lastYaw) / dt
		end
		self.lastYaw = yaw
	end
	if state.drawn ~= nil then
		self.drawn = state.drawn
	end

	local output = self.state:update(dt, {
		forward = forward,
		right = right,
		speed = state.speed,
		sprinting = state.sprinting,
		grounded = state.grounded,
		drawn = self.drawn,
		turning = state.turning,
		yawRate = yawRate,
		verticalVelocity = state.verticalVelocity or 0,
		fallHeight = state.fallHeight,
	})

	for name, weight in output.weights do
		animator:setWeight(self.handles[name], weight)
	end

	local oneShot = output.oneShot
	if oneShot == "Jump" then
		local handle = playOneShot(self, "Jump")
		self.jumpHandle = handle
		-- Fall takes over when the jump clip ends, if still airborne.
		animator.finished:Once(function(finished: any)
			if finished == handle and not self.destroyed and self.state.phase == "Air" then
				self.fallHandle = playOneShot(self, "Fall")
			end
		end)
	elseif oneShot == "Fall" then
		self.fallHandle = playOneShot(self, "Fall")
	elseif oneShot == "Land" then
		if self.fallHandle ~= nil then
			animator:stop(self.fallHandle, ChoreoData.oneShotBlendIn)
			self.fallHandle = nil
		end
		if self.jumpHandle ~= nil then
			animator:stop(self.jumpHandle, ChoreoData.oneShotBlendIn)
			self.jumpHandle = nil
		end
		playOneShot(self, "Land", output.oneShotWeight)
	elseif oneShot ~= nil then
		playOneShot(self, oneShot)
	end

	animator:setProcedural("lean", LocomotionState.leanOffsets(output.lean), ChoreoData.additiveWeights.lean)
	animator:setProcedural("drawnSprint", DRAWN_SPRINT, output.drawnSprint * ChoreoData.additiveWeights.drawnSprint)

	if self.footIK and root ~= nil then
		local weight = LocomotionState.footIKWeight(state.speed, state.grounded) * ChoreoData.additiveWeights.footIK
		if weight > 0 then
			local leftDelta, rightDelta = footDeltas(self, root)
			animator:setProcedural("footIK", LocomotionState.footIK(leftDelta, rightDelta, weight))
		else
			animator:setProcedural("footIK", nil)
		end
	end
	return output
end

function Locomotion.destroy(self: any)
	if getmetatable(self) == RigDriver then
		-- An enemy rig driver (Locomotion.attach) has its own teardown.
		RigDriver.destroy(self)
		return
	end
	if self.destroyed then
		return
	end
	self.destroyed = true
	if self.unhook ~= nil then
		self.unhook()
		self.unhook = nil
	end
	for _, handle in self.handles do
		self.animator:stop(handle)
	end
	if self.fallHandle ~= nil then
		self.animator:stop(self.fallHandle)
	end
	for _, name in { "lean", "drawnSprint", "footIK" } do
		self.animator:setProcedural(name, nil)
	end
	table.clear(self.handles)
end

-- ---------------------------------------------------------------------------------------------
-- Remote rigs
-- ---------------------------------------------------------------------------------------------

-- An enemy rig's locomotion: its data Idle and Walk crossfaded by speed, the walk paced to the
-- rig's walkSpeed. Reactions and attacks ride above on FullBody / Additive as on every rig.
RigDriver.__index = RigDriver

local function newRigDriver(animator: any, idleId: string, walkId: string, walkSpeed: number): any
	local self = setmetatable({
		animator = animator,
		handles = {} :: { [string]: any },
		walkSpeed = math.max(walkSpeed, Config.idleSpeedThreshold),
		unhook = nil :: (() -> ())?,
		destroyed = false,
	}, RigDriver)
	self.handles.Idle = animator:play(idleId, { coexist = true, weight = 1, blendIn = 0 })
	self.handles.Walk = animator:play(walkId, { coexist = true, weight = 0, blendIn = 0 })
	return self
end

function RigDriver.update(self: any, _dt: number, state: State): LocomotionState.Output
	local speed = math.max(0, state.speed)
	local walk = if speed > Config.idleSpeedThreshold then math.clamp(speed / self.walkSpeed, 0, 1) else 0
	self.animator:setWeight(self.handles.Walk, walk)
	self.animator:setWeight(self.handles.Idle, 1 - walk)
	if walk > 0 then
		self.animator:setSpeed(self.handles.Walk, speed / self.walkSpeed)
	end
	return {
		weights = { Idle = 1 - walk, Walk = walk },
		oneShot = nil,
		oneShotWeight = 1,
		lean = 0,
		drawnSprint = 0,
		phase = if walk > 0 then "Move" else "Idle",
		airborne = not state.grounded,
	}
end

function RigDriver.setDrawn(_self: any, _drawn: boolean) end

function RigDriver.destroy(self: any)
	if self.destroyed then
		return
	end
	self.destroyed = true
	if self.unhook ~= nil then
		self.unhook()
		self.unhook = nil
	end
	for _, handle in self.handles do
		self.animator:stop(handle)
	end
	table.clear(self.handles)
end

--- Drives a rig the local controller does not own from the animator's own step. The state comes
--- from deps.tracker (default Locomotion.humanoidTracker(character)); a frame with no state (the
--- Humanoid or root is gone) is skipped. A player rig runs the full blend space; an enemy rig its
--- data Idle / Walk pair. Destroy it when the rig leaves (the animator's own destroy drops the hook).
function Locomotion.attach(animator: any, character: Model, deps: Dependencies?): Locomotion
	local dependencies: Dependencies = deps or {}
	local tracker = dependencies.tracker or Locomotion.humanoidTracker(character)
	local rigId: string = animator.rigId
	local driver: any
	if rigId == "PlayerR15" then
		driver = Locomotion.new(animator, character, dependencies)
	else
		local rigClips = ChoreoData.rigs[rigId]
		assert(
			rigClips ~= nil and rigClips.walk ~= nil,
			("Locomotion.attach: data/choreo.luau rigs.%s needs idle and walk clip ids"):format(rigId)
		)
		local rig = Rigs[rigId]
		driver = newRigDriver(animator, rigClips.idle, rigClips.walk, (rig and rig.walkSpeed) or Config.walkSpeed)
	end
	driver.unhook = animator:onStep(function(dt: number)
		if driver.destroyed then
			return
		end
		local state = tracker(dt)
		if state ~= nil then
			driver:update(dt, state)
		end
	end)
	return (driver :: any) :: Locomotion
end

--- A per-frame state source for rigs driven by a Humanoid (other players, enemies): returns a
--- function(dt) -> State that reads MoveDirection, velocity, floor contact and tracks fall height.
function Locomotion.humanoidTracker(character: Model): (dt: number) -> State?
	local peakY: number? = nil
	local wasGrounded = true
	return function(_dt: number): State?
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart") :: any
		if humanoid == nil or root == nil then
			return nil
		end
		local velocity: Vector3 = (root :: BasePart).AssemblyLinearVelocity
		local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		local y = (root :: BasePart).Position.Y
		local fallHeight: number? = nil
		if not grounded then
			peakY = math.max(peakY or y, y)
		elseif not wasGrounded then
			fallHeight = math.max(0, (peakY or y) - y)
			peakY = nil
		end
		wasGrounded = grounded
		local drawn = character:GetAttribute("Drawn")
		return {
			moveDir = humanoid.MoveDirection,
			speed = horizontal.Magnitude,
			sprinting = horizontal.Magnitude > Config.runSpeed,
			grounded = grounded,
			drawn = if typeof(drawn) == "boolean" then drawn else nil,
			turning = 0,
			fallHeight = fallHeight,
			verticalVelocity = velocity.Y,
		}
	end
end

return Locomotion

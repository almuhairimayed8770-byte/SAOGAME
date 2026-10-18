--!strict
--[[
	Locomotion: the engine binding of the locomotion blend space (section 10 "Locomotion").

		local locomotion = Locomotion.new(animator, character)
		locomotion:update(dt, { moveDir = Vector3, speed = n, sprinting = b, grounded = b,
		                        drawn = b, turning = degrees, fallHeight = n? })
		locomotion:setDrawn(true)
		locomotion:destroy()

	It keeps one Base-layer handle per locomotion clip (Idle, IdleDrawn, and the walks, Run and
	Sprint twice: the sheathed set under the plain names, the drawn set under the ...Drawn names)
	and drives their weights from LocomotionState every frame; both sets start together, so a walk
	and its drawn twin stay in step. One-shots (Jump, Fall, Land, TurnLeft, TurnRight, Skid) play
	on the FullBody layer; the lean into turns, the drawn sprint "weapon low and back" pose and the
	raycast foot IK ride as procedural additive channels. The raycast is injected so the IK math
	stays pure and tested; the default uses workspace.

	The sheathed sword (a player rig whose weapon category has a weaponModels.luau sheaths row):
	`drawn` is the target (the server's Drawn attribute, or the local player's prediction). Before
	every animator step a hook feeds SheathState from the live clips and the target, plays or
	stops the Draw and Sheathe clips, and tells WeaponMount where the sword goes; the WeaponDraw and
	WeaponSheathe clip events move it mid-clip. Only the live clip's own event counts: a Draw or
	Sheathe that was stopped still runs through its fade, and its late event changes nothing. An
	attack, Guard, GuardHit or Parry clip pulls the sword to the hand before its first frame is
	posed (a draw-cut). The walk set follows the target at once; the Draw and Sheathe clips cover
	the arms. A clip above them that keys the right arm (a turn, a landing, a dodge, a stagger)
	hides the hand from the hilt, so the sword waits for it (SheathState "covered"). Nothing starts
	while the State attribute is Dead. A rig that cannot sheathe keeps the sword in the hand.

	The Drawn and State attributes are followed through their change signals, so no step reads
	them (`serverDrawn()` gives the Drawn attribute to the character controller). An instance with
	no signals (a Lune test rig) falls back to reading them once a step.

	The drawn sprint pose follows SprintDrawn's live weight, so it fades with the blend space
	instead of jumping when the target flips. It is off while the sword is on its sheath and gives
	way to a Draw or Sheathe clip, so the hand meets the hilt at the handoff.

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
local WeaponModels = require(Shared.data.weaponModels)
local Types = require(Shared.types)
local ClipSampler = require(Shared.choreo.ClipSampler)
local Easing = require(Shared.util.Easing)
local ClipLibrary = require(script.Parent.ClipLibrary)
local LocomotionState = require(script.Parent.LocomotionState)
local SheathState = require(script.Parent.SheathState)
local WeaponMount = require(script.Parent.WeaponMount)

local Config = ChoreoData.locomotion
local Sheath = ChoreoData.sheath

local DRAWN_ATTRIBUTE = "Drawn"
local STATE_ATTRIBUTE = "State"
local DEAD: Types.EntityState = "Dead"
local DRAW_EVENT = "WeaponDraw"
local SHEATHE_EVENT = "WeaponSheathe"

-- The Draw and Sheathe clip ids.
local DRAW_ID = Config.clipPrefix .. Sheath.clips.draw
local SHEATHE_ID = Config.clipPrefix .. Sheath.clips.sheathe

local function sheathClipId(clip: SheathState.Clip): string
	return if clip == "Draw" then DRAW_ID else SHEATHE_ID
end

-- Clip names (the id's last segment) that start with the sword in the hand, besides attacks.
local DRAW_CUT_NAMES: { [string]: boolean } = {}
for _, name in Sheath.drawCutClips do
	DRAW_CUT_NAMES[name] = true
end
local drawCutById: { [string]: boolean } = {}

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
	-- The change signal of an attribute on the character (default GetAttributeChangedSignal).
	attributeSignal: ((instance: Instance, name: string) -> any)?,
}

export type Locomotion = {
	update: (self: Locomotion, dt: number, state: State) -> LocomotionState.Output,
	setDrawn: (self: Locomotion, drawn: boolean) -> (),
	serverDrawn: (self: Locomotion) -> boolean,
	destroy: (self: Locomotion) -> (),
}

-- True for a clip that starts with the sword in the hand: an attack or a sheath.drawCutClips name.
local function isDrawCut(clip: Types.ClipDef): boolean
	local cached = drawCutById[clip.id]
	if cached == nil then
		cached = clip.attack == true or DRAW_CUT_NAMES[clip.id:match("[^/]+$") or clip.id] == true
		drawCutById[clip.id] = cached
	end
	return cached :: boolean
end

-- The arm joints the Draw and Sheathe clips move (the sword's own joint left out). Read once from
-- the clips; empty when a build has neither clip.
local sheathArm: { [string]: boolean }? = nil
local function sheathArmJoints(): { [string]: boolean }
	local joints = sheathArm
	if joints == nil then
		local found: { [string]: boolean } = {}
		for _, id in { DRAW_ID, SHEATHE_ID } do
			if ClipLibrary.has(id) then
				for _, key in ClipLibrary.get(id).keys do
					for name in key.joints do
						if name ~= WeaponModels.motorName then
							found[name] = true
						end
					end
				end
			end
		end
		sheathArm = found
		joints = found
	end
	return joints :: { [string]: boolean }
end

-- Clip id -> whether the clip keys one of the sheath clips' arm joints.
local keysArmById: { [string]: boolean } = {}

-- True when a handle hides the hand from the hilt: a clip that outranks Draw and Sheathe on the
-- arm (any FullBody clip, or a higher UpperBody one) and keys an arm joint they move.
local function coversArm(handle: any): boolean
	local above = handle.layer == "FullBody"
		or (handle.layer == "UpperBody" and handle.priority > ChoreoData.priority.Sheath)
	if not above then
		return false
	end
	local clip: Types.ClipDef = handle.clip
	local keysArm = keysArmById[clip.id]
	if keysArm == nil then
		keysArm = false
		local arm = sheathArmJoints()
		for _, key in clip.keys do
			for name in key.joints do
				if arm[name] then
					keysArm = true
					break
				end
			end
			if keysArm then
				break
			end
		end
		keysArmById[clip.id] = keysArm
	end
	return keysArm :: boolean
end

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

local function defaultAttributeSignal(instance: Instance, name: string): any
	return instance:GetAttributeChangedSignal(name)
end

-- Copies the character's Drawn and State attributes onto the driver.
local function readAttributes(self: any)
	self.attributeDrawn = self.character:GetAttribute(DRAWN_ATTRIBUTE) == true
	self.dead = self.character:GetAttribute(STATE_ATTRIBUTE) == DEAD
end

-- Follows the Drawn and State attributes through their change signals. When the character has no
-- signals (Lune), `pollAttributes` is set and the step reads them instead.
local function followAttributes(self: any, signalOf: (instance: Instance, name: string) -> any)
	readAttributes(self)
	for _, name in { DRAWN_ATTRIBUTE, STATE_ATTRIBUTE } do
		local ok, connection = pcall(function()
			return signalOf(self.character, name):Connect(function()
				readAttributes(self)
			end)
		end)
		if ok and connection ~= nil then
			table.insert(self.attributeConnections, connection)
		else
			self.pollAttributes = true
		end
	end
end

-- What the live clips say this step: a draw-cut, a clip that hides the arm, the Draw clip, the
-- Sheathe clip; and the target. Also returns how much of the Draw and Sheathe clips the limbs show
-- (stopping ones included), for the drawn sprint pose.
local function scanClips(self: any): (SheathState.Input, number)
	local cut, covered, drawing, sheathing = false, false, false, false
	local sheathWeight = 0
	for _, handle in self.animator.mixer:handles() do
		if handle.done then
			continue
		end
		local isSheathClip = handle.clipId == DRAW_ID or handle.clipId == SHEATHE_ID
		if isSheathClip then
			local shown = Easing.evaluate(ChoreoData.blendEasing, handle.fade) * handle.weight
			sheathWeight = math.max(sheathWeight, shown)
		end
		if handle.stopping then
			continue
		end
		if handle.clipId == DRAW_ID then
			drawing = true
		elseif handle.clipId == SHEATHE_ID then
			sheathing = true
		else
			if isDrawCut(handle.clip) then
				cut = true
			end
			if coversArm(handle) then
				covered = true
			end
		end
	end
	local input: SheathState.Input = {
		target = self.drawn,
		cut = cut,
		covered = covered,
		drawing = drawing,
		sheathing = sheathing,
		hold = self.dead,
	}
	return input, sheathWeight
end

-- True when an event comes from the live clip of that id: one that is not stopping and whose
-- clock has reached the event. A stopped Draw or Sheathe still runs through its fade, and a new
-- one may already have started, so the stopped clip's late event moves nothing.
local function fromLiveClip(self: any, clipId: string, time: number): boolean
	for _, handle in self.animator.mixer:handles() do
		if handle.clipId == clipId and not handle.stopping and not handle.done and handle.time >= time then
			return true
		end
	end
	return false
end

local function sheathInput(self: any): SheathState.Input
	local input = scanClips(self)
	return input
end

-- The place the target asks for with no clip in between.
local function targetPlace(self: any): WeaponMount.Place
	return if self.drawn then "Hand" else "Back"
end

-- Plays a sheath clip; a build without the clip moves the sword at once instead.
local function playSheathClip(self: any, clip: SheathState.Clip)
	local id = sheathClipId(clip)
	if ClipLibrary.has(id) then
		self.animator:play(id)
	else
		self.sheath.place = if clip == "Draw" then "Hand" else "Back"
	end
end

-- The sheath step: runs before the mixer, so the sword's move and the clip pose land together.
-- The mount's own step hook runs right after this one and puts the sword where it is wished.
local function stepSheath(self: any, dt: number)
	if self.pollAttributes then
		readAttributes(self)
	end
	local mount = self.mount
	if not mount:sheathable() then
		return
	end
	local generation = mount:generation()
	if generation ~= self.mountGeneration then
		-- A new sword motor (an equip, a respawn, a late stream): snap to the target, no clip.
		self.mountGeneration = generation
		self.sheath.place = targetPlace(self)
	end
	local input, sheathWeight = scanClips(self)
	self.sheathClipWeight = sheathWeight
	local out = self.sheath:step(dt, input)
	if out.stop ~= nil then
		self.animator:stop(sheathClipId(out.stop), Sheath.stopBlend)
	end
	if out.play ~= nil then
		playSheathClip(self, out.play)
	end
	if mount:get() ~= self.sheath.place then
		mount:set(self.sheath.place)
	end
end

-- A WeaponDraw or WeaponSheathe event from the live clip moves the sword mid-clip, when it still
-- fits the target.
local function onClipEvent(self: any, clipId: string, event: Types.ClipEvent)
	local kind = event.kind :: string
	if self.destroyed or (kind ~= DRAW_EVENT and kind ~= SHEATHE_EVENT) or not self.mount:sheathable() then
		return
	end
	if not fromLiveClip(self, clipId, event.time) then
		return
	end
	local place = self.sheath:onEvent(kind, sheathInput(self))
	if place ~= nil then
		self.mount:set(place)
	end
end

--- Creates the locomotion driver for a player rig's animator and its character model.
function Locomotion.new(animator: any, character: Model, deps: Dependencies?): Locomotion
	local dependencies: Dependencies = deps or {}
	local self = setmetatable({
		animator = animator,
		character = character,
		state = LocomotionState.new(),
		handles = {} :: { [string]: any },
		fallHandle = nil :: any,
		jumpHandle = nil :: any,
		drawn = character:GetAttribute(DRAWN_ATTRIBUTE) == true,
		lastYaw = nil :: number?,
		raycast = dependencies.raycast,
		footIK = dependencies.footIK ~= false,
		hipHeight = (Rigs[animator.rigId] or Rigs.PlayerR15).hipHeight,
		mount = nil :: any,
		sheath = nil :: any,
		mountGeneration = 0,
		sheathClipWeight = 0, -- how much of the Draw and Sheathe clips the limbs showed last step
		unhookSheath = nil :: (() -> ())?,
		clipEvents = nil :: any,
		attributeDrawn = false, -- the Drawn attribute (the server's word), kept by its change signal
		dead = false, -- the State attribute is Dead, kept by its change signal
		attributeConnections = {} :: { any },
		pollAttributes = false, -- the character has no attribute signals: the step reads them
		destroyed = false,
	}, Locomotion)
	if self.raycast == nil and self.footIK then
		self.raycast = defaultRaycast(character)
	end
	followAttributes(self, dependencies.attributeSignal or defaultAttributeSignal)
	for _, name in LocomotionState.WEIGHT_NAMES do
		self.handles[name] = animator:play(clipId(name), { coexist = true, weight = 0, blendIn = 0 })
	end
	animator:setWeight(self.handles[LocomotionState.clipFor("Idle", self.drawn)], 1, true)

	-- The sword starts where the target wants it, with no clip.
	self.mount = WeaponMount.new(animator, character)
	self.sheath = SheathState.new(targetPlace(self), Sheath)
	self.mountGeneration = self.mount:generation()
	if self.mount:sheathable() then
		self.mount:set(self.sheath.place)
	end
	self.unhookSheath = animator:onStep(function(dt: number)
		if not self.destroyed then
			stepSheath(self, dt)
		end
	end)
	self.clipEvents = animator.events:Connect(function(eventClipId: string, event: Types.ClipEvent)
		onClipEvent(self, eventClipId, event)
	end)
	return (self :: any) :: Locomotion
end

function Locomotion.setDrawn(self: any, drawn: boolean)
	self.drawn = drawn
end

--- The character's Drawn attribute (the server's word, nil read as false), kept by its change
--- signal so the caller reads no attribute per frame.
function Locomotion.serverDrawn(self: any): boolean
	if self.pollAttributes then
		readAttributes(self)
	end
	return self.attributeDrawn
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

-- How much of the drawn sprint pose ("weapon low and back") shows. It rides on SprintDrawn's live
-- weight, which the mixer moves at the blend-space rate, so it never jumps when the target flips.
-- It holds a sword in the hand: off while the sword is on its sheath, and it gives way to a Draw or
-- Sheathe clip moving the arm, so the hand is on the hilt when the sword changes hands.
local function drawnSprintWeight(self: any): number
	local handle = self.handles.SprintDrawn
	local weight: number = if handle ~= nil then handle.weight else 0
	if weight <= 0 then
		return 0
	end
	if self.sheath.place == "Back" and self.mount:sheathable() then
		return 0
	end
	return weight * (1 - math.clamp(self.sheathClipWeight, 0, 1))
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
	animator:setProcedural(
		"drawnSprint",
		DRAWN_SPRINT,
		drawnSprintWeight(self) * ChoreoData.additiveWeights.drawnSprint
	)

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
	if self.unhookSheath ~= nil then
		self.unhookSheath()
		self.unhookSheath = nil
	end
	if self.clipEvents ~= nil then
		self.clipEvents:Disconnect()
		self.clipEvents = nil
	end
	for _, connection in self.attributeConnections do
		connection:Disconnect()
	end
	table.clear(self.attributeConnections)
	self.mount:destroy()
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

function RigDriver.serverDrawn(_self: any): boolean
	return false
end

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
	local tracker = dependencies.tracker
	local rigId: string = animator.rigId
	local driver: any
	if rigId == "PlayerR15" then
		driver = Locomotion.new(animator, character, dependencies)
		if tracker == nil then
			-- The driver already follows the Drawn attribute; the tracker reads it from there.
			tracker = Locomotion.humanoidTracker(character, function(): boolean
				return driver:serverDrawn()
			end)
		end
	else
		local rigClips = ChoreoData.rigs[rigId]
		assert(
			rigClips ~= nil and rigClips.walk ~= nil,
			("Locomotion.attach: data/choreo.luau rigs.%s needs idle and walk clip ids"):format(rigId)
		)
		local rig = Rigs[rigId]
		driver = newRigDriver(animator, rigClips.idle, rigClips.walk, (rig and rig.walkSpeed) or Config.walkSpeed)
	end
	local source: (dt: number) -> State? = tracker or Locomotion.humanoidTracker(character)
	driver.unhook = animator:onStep(function(dt: number)
		if driver.destroyed then
			return
		end
		local state = source(dt)
		if state ~= nil then
			driver:update(dt, state)
		end
	end)
	return (driver :: any) :: Locomotion
end

--- A per-frame state source for rigs driven by a Humanoid (other players, enemies): returns a
--- function(dt) -> State that reads MoveDirection, velocity, floor contact, the Drawn attribute
--- (from `drawnOf` when given, else from the character) and tracks fall height.
function Locomotion.humanoidTracker(character: Model, drawnOf: (() -> boolean)?): (dt: number) -> State?
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
		return {
			moveDir = humanoid.MoveDirection,
			speed = horizontal.Magnitude,
			sprinting = horizontal.Magnitude > Config.runSpeed,
			grounded = grounded,
			-- A missing attribute means sheathed (the server writes it on player characters only).
			drawn = if drawnOf ~= nil then drawnOf() else character:GetAttribute(DRAWN_ATTRIBUTE) == true,
			turning = 0,
			fallHeight = fallHeight,
			verticalVelocity = velocity.Y,
		}
	end
end

return Locomotion

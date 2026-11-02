--!strict
--[[
	WeaponMount: moves one rig's sword between the hand and its back mount, on this client only.

		local mount = WeaponMount.new(animator, character, { atStepPose = FrameClock.atStepPose })
		mount:set("Back")      -- the sword rides on its sheath; set("Hand") puts it back in the hand
		mount:set("Hand", true) -- from a step: the move shows with the pose that step writes
		mount:get()            -- the place last asked for
		mount:sheathable()     -- false when the weapon's category has no sheath row
		mount:destroy()        -- back to the hand, unpinned, hook removed

	The server builds the Weapon Motor6D on the right hand and never moves it (WeaponBuilder), so
	hits and the hit matrix always see the sword in the hand. Here the client rewrites only that
	motor's Part0 and C0: the hand frame comes from rigs.luau (the same math the server used) and
	the back frame from the category's weaponModels.luau `sheaths` row. Both frames come from data,
	never from the instance, so a re-created motor, a respawn or a late stream lands on the same
	frames. C1
	is never touched. On the back the Weapon joint is pinned at rest (Choreo `pin`), so no clip,
	additive or procedural key can swing the sheathed sword.

	A move asked from inside the animator's step (`set(place, true)`: a draw-cut, a WeaponDraw or
	WeaponSheathe event) belongs to the pose that step writes, and a pose shows a frame after its
	step (impact.poseLagFrames), while a Part0 or C0 write puts the blade on its new part at once,
	from that part as physics last solved it (measured on the owner's PC, AG 376(b)): moved in the
	step, the sword hung for one frame in the hand of the pose before (the tip 4.1 studs on, the
	hand 0.003). So such a move waits for deps.atStepPose (FrameClock.atStepPose), the first frame
	that draws its step's pose, and lands there, before that frame draws (D-555); until then the
	sword stays where it is, the back pin included. The pin goes first, then Part0 and C0, so the
	blade lands from the Transform its new place wants: the pose's Weapon key in the hand, rest on
	the back. A move asked outside a step (a new mount, an equip), one with no deps.atStepPose, or
	one onto a motor this mount has not placed yet lands at once.

	A step hook re-reads the joint before every animator step: a new motor (an equip, a respawn,
	streaming) or a Part0 or C0 that moved since this mount wrote it gets its place again, in the
	same frame as the clip pose; a new motor takes the wished place at once, a move still waiting
	included. C0 is compared with the value read back after the write,
	so an engine that stores the frame at lower precision is not rewritten every frame. The hand
	and the back part are looked up once per new motor, never per step.
	`generation()` counts the new motors seen, so an owner can snap its own state when the sword
	is rebuilt.

	One mount drives an animator at a time. A second mount on the same animator takes over until it
	is destroyed; then the one before it takes the sword back.

	A piece the back mount needs that is not there yet (the weapon Model or its category attribute,
	the sheath row's body part) is looked for again on every step until it comes (D-519):
	the mount used to work this out once per new motor, so a motor seen before the rest of its
	weapon or body kept the sword in the hand for good. A category with no sheath row, or a joint
	that is no Motor6D, is final.

	A log aid (D-519, like D-362's TrailOwner): the driving mount writes on the character Model,
	on this client only, weaponModels.attributes.mount ("Back" or "Hand": where this client hangs
	the blade now, the motor's Part0) and attributes.mountWhy (why the sword cannot go on the back,
	nil while it can). destroy clears both.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared.types)
local Rigs = require(Shared.data.rigs)
local WeaponModels = require(Shared.data.weaponModels)
local ClipSampler = require(Shared.choreo.ClipSampler)

export type Place = "Hand" | "Back"

export type Deps = {
	-- FrameClock.atStepPose (D-343): runs `fn` on the first rendered frame that draws the pose a
	-- rig's step writes now, and returns its cancel. Nil: every move lands at once.
	atStepPose: ((fn: () -> ()) -> () -> ())?,
}

export type WeaponMount = {
	set: (self: WeaponMount, place: Place, withPose: boolean?) -> (),
	get: (self: WeaponMount) -> Place,
	sheathable: (self: WeaponMount) -> boolean,
	refresh: (self: WeaponMount) -> (),
	generation: (self: WeaponMount) -> number,
	destroy: (self: WeaponMount) -> (),
}

local MOTOR = WeaponModels.motorName
local MOUNT_ATTRIBUTE = WeaponModels.attributes.mount
local WHY_ATTRIBUTE = WeaponModels.attributes.mountWhy

local WeaponMount = {}
WeaponMount.__index = WeaponMount

-- animator -> its mounts, oldest first; the last one drives the sword.
local stacks: { [any]: { any } } = setmetatable({}, { __mode = "k" }) :: any

local function gripJoint(): Rigs.PlaceholderJoint
	for _, joint in Rigs.PlayerR15.joints :: { Rigs.PlaceholderJoint } do
		if joint.name == MOTOR then
			return joint
		end
	end
	error("WeaponMount: rigs.luau PlayerR15 has no " .. MOTOR .. " joint")
end

local GRIP = gripJoint()
local HAND_FRAME = ClipSampler.toCFrame(GRIP.c0)
local backFrames: { [string]: CFrame } = {}

--- The Weapon joint's C0 in the hand: the rigs.luau PlayerR15 Weapon joint's c0.
function WeaponMount.handFrame(): CFrame
	return HAND_FRAME
end

--- The body part that carries a category's sheathed weapon and the Weapon joint's C0 on it, or
--- nil when the category's weapon stays in the hand.
function WeaponMount.backFrame(category: Types.WeaponCategory): (string?, CFrame?)
	local row = WeaponModels.sheath(category)
	if row == nil then
		return nil, nil
	end
	local frame = backFrames[category]
	if not frame then
		frame = ClipSampler.toCFrame(row.mount)
		backFrames[category] = frame
	end
	return row.part, frame
end

local function isTop(self: any): boolean
	local stack = stacks[self.animator]
	return stack ~= nil and stack[#stack] == self
end

-- The weapon Model the motor belongs to (the blade's parent), else the character's Weapon model.
local function weaponModelOf(model: Model, motor: Motor6D): Instance?
	local blade = motor.Part1
	local owner = if blade ~= nil then blade.Parent else nil
	if owner ~= nil and owner:IsA("Model") and owner:GetAttribute(WeaponModels.attributes.category) ~= nil then
		return owner
	end
	local named = model:FindFirstChild(WeaponModels.modelName)
	return if named ~= nil and named:IsA("Model") then named else nil
end

-- Works out whether the current joint can go on the back. Returns why not (nil when it can) and
-- whether that may still change (a piece not there yet: looked for again on the next sync).
local function resolve(self: any): (string?, boolean)
	self.canSheathe = false
	self.handPart = nil
	self.backPart = nil
	self.backC0 = nil
	local joint = self.joint
	if joint == nil then
		return "no Weapon joint", false
	end
	if not joint:IsA("Motor6D") then
		return "the Weapon joint is not a Motor6D", false
	end
	local weapon = weaponModelOf(self.model, joint :: Motor6D)
	local category = if weapon ~= nil then weapon:GetAttribute(WeaponModels.attributes.category) else nil
	if typeof(category) ~= "string" then
		return "no weapon category", true
	end
	local partName, frame = WeaponMount.backFrame(category :: Types.WeaponCategory)
	if partName == nil or frame == nil then
		return "no sheath row for " .. category, false
	end
	local part = self.model:FindFirstChild(partName)
	if part == nil or not part:IsA("BasePart") then
		return "no " .. partName, true
	end
	local hand = self.model:FindFirstChild(GRIP.part0)
	self.handPart = if hand ~= nil and hand:IsA("BasePart") then hand else nil
	self.backPart = part
	self.backC0 = frame
	self.canSheathe = true
	return nil, false
end

-- Drops a move waiting for its pose's frame (D-555); the sword stays where it is shown.
local function cancelWait(self: any)
	local cancel = self.waitCancel
	self.waitToken = nil
	self.waitCancel = nil
	if cancel ~= nil then
		cancel()
	end
end

-- Re-reads the joint; on a new one, works out again whether it can go on the back, and while a
-- piece it needs is missing, looks for it again (D-519).
local function sync(self: any)
	local joint = self.animator:joint(MOTOR)
	if joint == self.joint then
		if self.retry then
			self.why, self.retry = resolve(self)
		end
		return
	end
	self.joint = joint
	self.appliedPlace = nil
	self.appliedC0 = nil
	if joint ~= nil then
		self.generationCount += 1
	end
	-- A new motor has shown no place of this mount's yet: it takes the wish at once.
	cancelWait(self)
	self.shown = self.wish
	self.why, self.retry = resolve(self)
end

-- The log aid (D-519): where this client hangs the blade and why it cannot go on the back, on
-- the character Model, written only when it changes. Nil clears both.
local function publish(self: any, place: Place?, why: string?)
	if self.published == place and self.publishedWhy == why then
		return
	end
	self.published = place
	self.publishedWhy = why
	self.model:SetAttribute(MOUNT_ATTRIBUTE, place)
	self.model:SetAttribute(WHY_ATTRIBUTE, why)
end

-- Puts the motor where the sword is shown (the wish, once a move waiting for its pose's frame has
-- landed). A rig that cannot sheathe keeps its sword in the hand as the server built it: nothing
-- is written, only the pin is let go. The pin goes before Part0 and C0: either write puts the
-- blade on its part at once from the joint's Transform as it stands (D-555).
local function apply(self: any)
	if not self.canSheathe then
		self.animator:pin(MOTOR, false)
		publish(self, if self.joint ~= nil then "Hand" else nil, self.why)
		return
	end
	local motor = self.joint :: Motor6D
	local place: Place = self.shown
	local back = place == "Back"
	self.animator:pin(MOTOR, back)
	local part: BasePart? = if back then self.backPart else self.handPart
	if part ~= nil and motor.Part0 ~= part then
		motor.Part0 = part
	end
	if self.appliedPlace ~= place or motor.C0 ~= self.appliedC0 then
		motor.C0 = if back then self.backC0 else WeaponMount.handFrame()
		self.appliedC0 = motor.C0
		self.appliedPlace = place
	end
	publish(self, place, nil)
end

--- Creates the mount for an animator and its character model; the sword starts in the hand.
--- deps.atStepPose holds a move asked from a step until the frame that draws its pose (D-555).
function WeaponMount.new(animator: any, model: Model, deps: Deps?): WeaponMount
	local self = setmetatable({
		animator = animator,
		model = model,
		atStepPose = if deps ~= nil then deps.atStepPose else nil,
		wish = "Hand" :: Place,
		shown = "Hand" :: Place, -- where the motor is put: the wish, once a waiting move landed
		waitToken = nil :: {}?, -- the move waiting for its pose's frame (D-555)
		waitCancel = nil :: (() -> ())?,
		joint = nil :: Instance?,
		canSheathe = false,
		handPart = nil :: BasePart?, -- looked up once per new motor
		backPart = nil :: BasePart?,
		backC0 = nil :: CFrame?,
		appliedPlace = nil :: Place?, -- the place this mount last wrote onto the joint
		appliedC0 = nil :: CFrame?, -- the joint's C0 as read back after that write
		why = nil :: string?, -- why the sword cannot go on the back (nil when it can)
		retry = false, -- a piece the back mount needs is missing: looked for again on every sync
		published = nil :: Place?, -- the log aid as last written (D-519)
		publishedWhy = nil :: string?,
		generationCount = 0,
		unhook = nil :: (() -> ())?,
		destroyed = false,
	}, WeaponMount)
	local stack = stacks[animator]
	if stack == nil then
		stack = {}
		stacks[animator] = stack
	end
	table.insert(stack, self)
	self.unhook = animator:onStep(function()
		self:refresh()
	end)
	self:refresh()
	return (self :: any) :: WeaponMount
end

--- Records where the sword should be and puts it there when this mount drives the rig: now, or,
--- `withPose` (asked from inside the animator's step), on the first frame that draws the pose
--- that step writes (deps.atStepPose, D-555). A wish that turns back before then moves nothing.
function WeaponMount.set(self: any, place: Place, withPose: boolean?)
	if self.destroyed then
		self.wish = place
		return
	end
	self.wish = place
	local gate = self.atStepPose
	local waits = false
	if withPose == true and gate ~= nil and place ~= self.shown and isTop(self) then
		-- Only a motor this mount has placed (and can sheathe) has a place to keep until then.
		sync(self)
		waits = self.canSheathe and self.appliedPlace ~= nil and place ~= self.shown
	end
	if not waits then
		cancelWait(self)
		self.shown = place
		self:refresh()
		return
	end
	if self.waitToken ~= nil then
		return
	end
	local token = {}
	self.waitToken = token
	local cancel = (gate :: (fn: () -> ()) -> () -> ())(function()
		if self.waitToken ~= token or self.destroyed then
			return
		end
		self.waitToken = nil
		self.waitCancel = nil
		self.shown = self.wish
		self:refresh()
	end)
	if self.waitToken == token then
		self.waitCancel = cancel
	end
end

--- The place last asked for (the sword may still be in the hand when the rig cannot sheathe).
function WeaponMount.get(self: any): Place
	return self.wish
end

--- True when the Weapon joint is a Motor6D, its weapon's category has a sheath row and the rig
--- has that row's part.
function WeaponMount.sheathable(self: any): boolean
	if self.destroyed then
		return false
	end
	sync(self)
	return self.canSheathe
end

--- Re-reads the Weapon joint and puts the sword back where the wish says if anything moved it.
function WeaponMount.refresh(self: any)
	if self.destroyed or not isTop(self) then
		return
	end
	sync(self)
	apply(self)
end

--- How many new Weapon joints this mount has seen (an equip, a respawn or a stream adds one).
function WeaponMount.generation(self: any): number
	return self.generationCount
end

--- Puts the sword back in the hand, lets go of the pin and removes the hook. A model that has
--- already left the world (a respawn) is not written to.
function WeaponMount.destroy(self: any)
	if self.destroyed then
		return
	end
	local wasTop = isTop(self)
	self.destroyed = true
	cancelWait(self)
	if self.unhook ~= nil then
		self.unhook()
		self.unhook = nil
	end
	local stack = stacks[self.animator]
	if stack ~= nil then
		local index = table.find(stack, self)
		if index ~= nil then
			table.remove(stack, index)
		end
		if #stack == 0 then
			stacks[self.animator] = nil
		end
	end
	if not wasTop then
		return
	end
	if self.model.Parent ~= nil then
		sync(self)
		if self.canSheathe then
			self.wish = "Hand"
			self.shown = "Hand"
			apply(self)
		end
		publish(self, nil, nil)
	end
	self.animator:pin(MOTOR, false)
	local below = if stack ~= nil then stack[#stack] else nil
	if below ~= nil then
		below:refresh()
	end
end

return WeaponMount

--!strict
--[[
	WeaponMount: moves one rig's sword between the hand and its back mount, on this client only.

		local mount = WeaponMount.new(animator, character)
		mount:set("Back")      -- the sword rides on its sheath; set("Hand") puts it back in the hand
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

	A step hook re-reads the joint before every animator step: a new motor (an equip, a respawn,
	streaming) or a Part0 or C0 that moved since this mount wrote it gets the wished place again,
	in the same frame as the clip pose. C0 is compared with the value read back after the write,
	so an engine that stores the frame at lower precision is not rewritten every frame. The hand
	and the back part are looked up once per new motor, never per step.
	`generation()` counts the new motors seen, so an owner can snap its own state when the sword
	is rebuilt.

	One mount drives an animator at a time. A second mount on the same animator takes over until it
	is destroyed; then the one before it takes the sword back.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Shared.types)
local Rigs = require(Shared.data.rigs)
local WeaponModels = require(Shared.data.weaponModels)
local ClipSampler = require(Shared.choreo.ClipSampler)

export type Place = "Hand" | "Back"

export type WeaponMount = {
	set: (self: WeaponMount, place: Place) -> (),
	get: (self: WeaponMount) -> Place,
	sheathable: (self: WeaponMount) -> boolean,
	refresh: (self: WeaponMount) -> (),
	generation: (self: WeaponMount) -> number,
	destroy: (self: WeaponMount) -> (),
}

local MOTOR = WeaponModels.motorName

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

-- Re-reads the joint; on a new one, works out again whether it can go on the back.
local function sync(self: any)
	local joint = self.animator:joint(MOTOR)
	if joint == self.joint then
		return
	end
	self.joint = joint
	self.canSheathe = false
	self.handPart = nil
	self.backPart = nil
	self.backC0 = nil
	self.appliedPlace = nil
	self.appliedC0 = nil
	if joint == nil then
		return
	end
	self.generationCount += 1
	if not joint:IsA("Motor6D") then
		return
	end
	local weapon = weaponModelOf(self.model, joint :: Motor6D)
	local category = if weapon ~= nil then weapon:GetAttribute(WeaponModels.attributes.category) else nil
	if typeof(category) ~= "string" then
		return
	end
	local partName, frame = WeaponMount.backFrame(category :: Types.WeaponCategory)
	if partName == nil or frame == nil then
		return
	end
	local part = self.model:FindFirstChild(partName)
	if part == nil or not part:IsA("BasePart") then
		return
	end
	local hand = self.model:FindFirstChild(GRIP.part0)
	self.handPart = if hand ~= nil and hand:IsA("BasePart") then hand else nil
	self.backPart = part
	self.backC0 = frame
	self.canSheathe = true
end

-- Puts the motor where the wish says. A rig that cannot sheathe keeps its sword in the hand as
-- the server built it: nothing is written, only the pin is let go.
local function apply(self: any)
	if not self.canSheathe then
		self.animator:pin(MOTOR, false)
		return
	end
	local motor = self.joint :: Motor6D
	local place: Place = self.wish
	local back = place == "Back"
	local part: BasePart? = if back then self.backPart else self.handPart
	if part ~= nil and motor.Part0 ~= part then
		motor.Part0 = part
	end
	if self.appliedPlace ~= place or motor.C0 ~= self.appliedC0 then
		motor.C0 = if back then self.backC0 else WeaponMount.handFrame()
		self.appliedC0 = motor.C0
		self.appliedPlace = place
	end
	self.animator:pin(MOTOR, back)
end

--- Creates the mount for an animator and its character model; the sword starts in the hand.
function WeaponMount.new(animator: any, model: Model): WeaponMount
	local self = setmetatable({
		animator = animator,
		model = model,
		wish = "Hand" :: Place,
		joint = nil :: Instance?,
		canSheathe = false,
		handPart = nil :: BasePart?, -- looked up once per new motor
		backPart = nil :: BasePart?,
		backC0 = nil :: CFrame?,
		appliedPlace = nil :: Place?, -- the place this mount last wrote onto the joint
		appliedC0 = nil :: CFrame?, -- the joint's C0 as read back after that write
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

--- Records where the sword should be and puts it there now when this mount drives the rig.
function WeaponMount.set(self: any, place: Place)
	self.wish = place
	self:refresh()
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
			apply(self)
		end
	end
	self.animator:pin(MOTOR, false)
	local below = if stack ~= nil then stack[#stack] else nil
	if below ~= nil then
		below:refresh()
	end
end

return WeaponMount

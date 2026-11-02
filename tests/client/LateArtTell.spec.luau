--!strict
--[[
	A watcher's copy of an Art that joins it in its hold cuts to the hold's pose (D-635, AS 516(d)).

	A remote Art's ActionStarted carries its release (the server's start), so on a watcher at lag
	0.1 the network catch-up starts Vertical 0.13 to 0.18 s in: inside its ActivationHold (0.15 to
	0.25), the still tell. The clip came in over its own blend-in (0.08 s) from what the copy drew
	before (IdleDrawn), so the "held" blade swept from the idle pose into the tell: the PC's tip
	stepped 4.83 / 4.81 a row at 30, 2.39 / 2.76 at 60 and 1.10 to 1.22 at 144, the rows the hold
	should stand still on (516(d)'s bar is 0.02).

	Now a clip's blend-in ends where its hold begins: a copy that starts before the hold blends in
	over no more than the clip time left to it, and one that starts in the hold or past it cuts to
	its pose on its first drawn frame. A copy that starts early enough for its whole blend keeps it.

	The real path: a RigBuilder player rig with its drawn WeaponBuilder sword, a real Choreo animator,
	the real ClipLibrary clip, ActionStarted through the real Replication (atStepPose and
	atStepPoseSolve on the real FrameClock, its PreSimulation step), and the real Trails on their
	render steps. The tip is read as each frame starts: the pose that frame draws (D-342).
]]

local function frameSignal(): any
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
end
Harness.stubService("RunService", {
	RenderStepped = frameSignal(),
	Heartbeat = frameSignal(),
	PreSimulation = frameSignal(),
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
})

local Choreo = Harness.load("src/client/choreo/Choreo")
local Locomotion = Harness.load("src/client/choreo/Locomotion")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local FrameClock = Harness.load("src/client/fx/FrameClock")
local Replication = Harness.load("src/client/controllers/Replication")
local Trails = Harness.load("src/client/fx/Trails")
local Engine = Harness.load("src/client/fx/Engine")
local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Rigs = Harness.load("src/shared/data/rigs")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local WeaponBuilder = Harness.load("src/server/world/WeaponBuilder")
local WeaponModels = Harness.load("src/shared/data/weaponModels")
local Weapons = Harness.load("src/shared/data/weapons")

local VERTICAL = ChoreoData.locomotion.clipPrefix .. "Vertical"
local VERTICAL_ART = "OneHandedSword.Vertical"
local RATES = { 30, 60, 144 }
-- Vertical's ActivationHold: the tell from 0.15 to the hold's end at 0.25.
local HOLD_START, HOLD_END = 0.15, 0.25
-- A held row steps the tip no more than this many studs a second times its frame: the breathing
-- under the hold (Breathe's micro-motion, section 10 beat 6, about 1 stud a second on this rig at
-- its quickest), never a sweep.
local STILL_SPEED = 1.5
-- The first row's tip lies this close to the on-time copy's tell: Breathe's sway between the two
-- moments.
local TELL = 0.25

local clock = 100
local frame = 0
Choreo.configure({
	now = function(): number
		return clock
	end,
	cameraPosition = function(): Vector3
		return Vector3.zero
	end,
})

local function recorder(): any
	return setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
end

-- A player rig with its sword, on the back mount (sheathed) or in the hand (drawn).
local function build(drawn: boolean): Model
	local model = Instance.new("Model")
	model.Name = "Ren"
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", drawn)
	model:SetAttribute("State", "Idle")
	local parts: { [string]: BasePart } = {}
	local function part(name: string): BasePart
		if parts[name] == nil then
			local created = Instance.new("Part")
			created.Name = name
			created.Size = Vector3.new(1, 1, 1)
			created.CFrame = CFrame.new(0, 3, 0)
			created.Position = Vector3.new(0, 3, 0)
			created.AssemblyLinearVelocity = Vector3.zero
			created.Parent = model
			parts[name] = created
		end
		return parts[name]
	end
	for _, joint in Rigs.PlayerR15.joints do
		if joint.name ~= WeaponModels.motorName then
			local motor = Instance.new("Motor6D")
			motor.Name = joint.name
			motor.Part0 = part(joint.part0)
			motor.Part1 = part(joint.part1)
			motor.C0 = RigBuilder.frameOf(joint.c0)
			motor.Parent = motor.Part1
		end
	end
	model.PrimaryPart = parts.HumanoidRootPart
	local humanoid = Instance.new("Humanoid")
	humanoid.MoveDirection = Vector3.zero
	humanoid.FloorMaterial = Enum.Material.Plastic
	humanoid.Parent = model
	WeaponBuilder.equip(model, Weapons.byId("TrialistSword"))
	local world = Instance.new("Folder")
	model.Parent = world
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			local ok = pcall(function(): Vector3
				return item.Position
			end)
			if not ok then
				item.Position = Vector3.new(0, 3, 0)
			end
		end
	end
	return model
end

type Take = {
	shown: { number }, -- per row from the dispatch, the clip time it draws
	tips: { Vector3 }, -- per row, the tip it draws
	blendIn: number, -- the handle's blend-in as it starts
	start: number, -- the clip time the catch-up started it at
}

-- Plays A's Vertical on its drawn copy at `fps`, its ActionStarted `late` seconds after the
-- server's start (A's release); returns the rows from the dispatch on.
local function take(fps: number, late: number): Take
	local model = build(true)
	local record =
		{ id = 2, model = model, kind = "Player", rig = "PlayerR15", weaponId = "TrialistSword", name = "Ren" }
	local hooks: { [string]: any } = {}
	local function hook(key: string)
		return function(fn: any): () -> ()
			hooks[key] = fn
			return function()
				hooks[key] = nil
			end
		end
	end
	FrameClock.bind({
		now = function(): number
			return clock
		end,
		onFrameStart = hook("start"),
		onPosed = hook("posed"),
		onFrameEnd = hook("finish"),
		onPreSimulation = hook("preSimulation"),
		onHeartbeat = function(): () -> ()
			return function() end
		end,
	} :: any)
	Engine.setViewer(function(): Vector3
		return Vector3.new(0, 5, 10)
	end)
	Engine.setClock(function(): number
		return clock
	end)
	Trails.start()
	Trails.bind({
		now = function(): number
			return clock
		end,
		onRender = hook("readers"),
		onDrawn = hook("drawn"),
		onWatch = function(): () -> ()
			return function() end
		end,
		clear = function() end,
		held = function(target: Instance): boolean
			local found: any = Choreo.find(target :: any)
			return found ~= nil and found:heldShown() == true
		end,
		animator = function(target: Instance): any
			return Choreo.find(target :: any)
		end,
	})
	Replication.bind({
		net = { on = function() end },
		entities = {
			get = function(id: number): any
				return if id == 2 then record else nil
			end,
		},
		localId = function(): number
			return 1
		end,
		locomotion = {
			-- Foot IK off: Lune casts no rays, and the blade is the spec's subject.
			attach = function(animator: any, rigName: any, options: any): any
				local withoutIK = table.clone(options or {})
				withoutIK.footIK = false
				return Locomotion.attach(animator, rigName, withoutIK)
			end,
			destroy = Locomotion.destroy,
			humanoidTracker = Locomotion.humanoidTracker,
		},
		choreo = Choreo,
		clipLibrary = ClipLibrary,
		trails = Trails,
		smear = recorder(),
		shatter = recorder(),
		sparks = recorder(),
		telegraphs = recorder(),
		outline = recorder(),
		switchRing = recorder(),
		digits = recorder(),
		hud = recorder(),
		systemLine = recorder(),
		sfx = recorder(),
		impact = recorder(),
		camera = recorder(),
		weaponCategory = function(): string
			return "OneHandedSword"
		end,
		trailToken = function(): string
			return "TrailCyanWhite"
		end,
		positionOf = function(): Vector3
			return Vector3.zero
		end,
		schedule = function() end,
		now = function(): number
			return clock
		end,
		atPose = FrameClock.atPose,
		atStepPose = FrameClock.atStepPose,
		atStepPoseSolve = FrameClock.atStepPoseSolve,
	} :: any)
	Replication.watch(record)
	local animator: any = Choreo.get(model)
	local tipAttachment = model:FindFirstChild("TrailEnd", true) :: Attachment
	tipAttachment.WorldPosition = Vector3.new(0, 3, 0)
	local result: Take = { shown = {}, tips = {}, blendIn = -1, start = -1 }
	local handle: any = nil
	local dt = 1 / fps
	local function step()
		frame += 1
		clock += dt
		hooks.start(dt)
		if handle ~= nil then
			-- The pose this frame draws: the joints the rigs' step of the frame before wrote.
			local chain = BladeContact.chain(model :: any)
			local _, tip = BladeContact.blade(chain, BladeContact.read(chain))
			table.insert(result.shown, handle.time)
			table.insert(result.tips, tip)
		end
		if hooks.drawn ~= nil then
			hooks.drawn(0)
		end
		animator:step(dt)
		hooks.posed(dt)
		local posed = BladeContact.chain(model :: any)
		local _, posedTip = BladeContact.blade(posed, BladeContact.read(posed))
		tipAttachment.WorldPosition = posedTip
		if hooks.readers ~= nil then
			hooks.readers(0)
		end
		hooks.finish(dt)
		if hooks.preSimulation ~= nil then
			hooks.preSimulation(dt)
		end
	end
	local ok, err = pcall(function()
		for _ = 1, 60 do
			step()
		end
		Replication.dispatch("ActionStarted", {
			entityId = 2,
			clipId = VERTICAL,
			serverTime = clock - late,
			facing = { 0, 0, -1 },
			artId = VERTICAL_ART,
		})
		handle = animator.mixer:find(VERTICAL)
		result.start = handle.time
		result.blendIn = handle.blendIn
		for _ = 1, math.ceil(0.35 * fps) do
			step()
		end
	end)
	Replication.unwatch(record)
	Trails.bind(nil)
	Trails.reset()
	Engine.setViewer(nil)
	Engine.setClock(nil)
	Choreo.release(model)
	FrameClock.bind(nil)
	if not ok then
		error(err, 0)
	end
	return result
end

-- The tip steps of the rows drawing the hold: from the row after `from` (the first row drawing
-- the clip at `from` or past it) to the last row drawing HOLD_END or less; returns the largest
-- and its row's drawn clip.
local function holdSteps(result: Take, from: number): (number, number)
	local worst, at = 0, -1
	local first: number? = nil
	for index, shown in result.shown do
		if first == nil and shown > result.start and shown >= from - 1e-6 then
			first = index
		elseif first ~= nil and shown <= HOLD_END + 1e-6 then
			local stepped = (result.tips[index] - result.tips[index - 1]).Magnitude
			if stepped > worst then
				worst, at = stepped, shown
			end
		end
	end
	return worst, at
end

-- The clip time the copy's first drawn row shows.
local function firstShown(result: Take): number
	for _, shown in result.shown do
		if shown > result.start then
			return shown
		end
	end
	error("no row draws the clip")
end

-- The tip on the first row drawing the clip at `at` or past it.
local function tipAt(result: Take, at: number): Vector3
	for index, shown in result.shown do
		if shown > result.start and shown >= at - 1e-6 then
			return result.tips[index]
		end
	end
	error("no row draws " .. at)
end

describe("Replication: a watcher's copy that joins an Art in its hold cuts to the tell (D-635)", function()
	it("draws the hold's pose still from its first row to the hold's end, at 30, 60 and 144", function()
		-- Lag 0.1's catch-ups (the PC: L drew 0.15 to 0.22) and one at the hold's end. Before: the
		-- first rows swept in from IdleDrawn over the clip's 0.08 s blend-in, stepping the tip 4.29 a
		-- row at 30, 2.59 at 60 and 1.12 at 144 (the PC 4.83, 2.76 and 1.22), the first row 4.69,
		-- 6.42 and 6.97 off the tell.
		local problems = {}
		for _, fps in RATES do
			local onTime = take(fps, 0)
			for _, late in { 0.15, 0.17, 0.2, 0.23 } do
				local result = take(fps, late)
				local label = ("%d fps, catch-up %.2f"):format(fps, late)
				local worst, at = holdSteps(result, 0)
				if worst > STILL_SPEED / fps then
					table.insert(problems, ("%s: the tip steps %.3f on the row drawing %.4f"):format(label, worst, at))
				end
				-- Its first row, where it draws the hold, draws the tell the on-time copy holds.
				local first = firstShown(result)
				if first <= HOLD_END then
					local off = (tipAt(result, 0) - tipAt(onTime, first)).Magnitude
					if off > TELL then
						table.insert(problems, ("%s: its first row's tip %.3f off the tell"):format(label, off))
					end
				end
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("blends in before the hold when it starts short of it: the hold's rows still", function()
		-- Lag 0.1's earliest catch-ups. Before: the 0.08 s blend ran on into the hold (the tip
		-- stepped 0.50 to 4.29 a row at 30, 1.91 to 2.59 at 60, 0.81 to 1.12 at 144).
		local problems = {}
		for _, fps in RATES do
			for _, late in { 0.1, 0.12, 0.14 } do
				local result = take(fps, late)
				local worst, at = holdSteps(result, HOLD_START)
				if worst > STILL_SPEED / fps then
					table.insert(
						problems,
						("%d fps, catch-up %.2f: the tip steps %.3f on the row drawing %.4f"):format(
							fps,
							late,
							worst,
							at
						)
					)
				end
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("keeps the clip's own blend-in for a copy that starts in time for it", function()
		-- Lag 0's catch-ups (0.013 to 0.07): the blend ends before the hold, as before.
		for _, fps in RATES do
			for _, late in { 0, 0.03, 0.06 } do
				local result = take(fps, late)
				expect({ fps, late, result.blendIn }).toEqual({
					fps,
					late,
					ClipLibrary.get(VERTICAL).blendIn or ChoreoData.blendIn,
				})
			end
		end
	end)
end)

--!strict
--[[
	A late remote basic's back-filled stroke starts where the swinger's own screen starts it (AU
	542(d), D-550, D-670).

	The swinger's own screen draws its stroke live (Trails bladeAt): the clip at the window's open,
	with what the frame shows on top of the clip carried across. A watcher whose ActionStarted came
	in late back-fills the stroke from the open on the clip's own blade at its full weight
	(clipBladeAt, D-550), because the frame there still blends the pose from before the jump. That
	left out the procedural channels the body always shows on top of every clip: the stand height
	(D-506: an avatar whose Humanoid holds its root higher or lower than its bind-pose soles stand
	is lowered or raised onto the floor), the foot IK's pelvis drop, the lean, the turn plant's yaw.
	The PC on d310ca7, S542_60_A_1: A's own first point 0.121 below A's root, the watcher's late
	copies at root height (+0.004), 0.163 apart, mostly height. Now the back-fill adds the rig's
	channels as its last step added them, so both screens draw the slash from the same start.

	The real path, as LateRemoteRibbon's: a real Choreo animator on a RigBuilder player rig with its
	WeaponBuilder sword, the real ClipLibrary clip and the real Trails and TrailRibbon on their render
	steps. The swinger's own rig as CharacterController drives it: Replication watches it (its trail
	and its clip events) with no driver, Locomotion.new with the controller's deps updated before the
	rig's step, and Basic1 played as basicAttack plays it. The watcher's copy through the real
	Replication's ActionStarted, `late` seconds after the server's start, its Locomotion attached by
	Replication. Both with foot IK on over a flat floor (Lune casts no rays: the floor is handed in)
	and a Humanoid that holds the root `lift` off its bind-pose soles.
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
local TrailRibbon = Harness.load("src/client/fx/TrailRibbon")
local Engine = Harness.load("src/client/fx/Engine")
local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local Pose = Harness.load("src/shared/choreo/Pose")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Rigs = Harness.load("src/shared/data/rigs")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local WeaponBuilder = Harness.load("src/server/world/WeaponBuilder")
local WeaponModels = Harness.load("src/shared/data/weaponModels")
local Weapons = Harness.load("src/shared/data/weapons")

local BASIC1 = ChoreoData.locomotion.clipPrefix .. "Basic1"
local ROOT = CFrame.new(0, 3, 0)
-- The PC's gap (S542_60_A_1 against the late copies): A's own first point 0.121 below its root,
-- the late ones 0.004 above it.
local LIFT = -0.125
-- AU 542(d): the late copies' first points within 0.05 of A's own.
local BAR = 0.05

local clock = 100
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

-- The bind pose's soles below the root's center (Locomotion's standDepth, D-506).
local function soles(model: Model): number
	local solved = Pose.solve(model, CFrame.new(), {})
	local lowest = math.huge
	for _, name in { "LeftFoot", "RightFoot" } do
		local part = model:FindFirstChild(name) :: BasePart
		local frame = solved[name]
		for _, sx in { -0.5, 0.5 } do
			for _, sz in { -0.5, 0.5 } do
				lowest = math.min(
					lowest,
					(frame * CFrame.new(sx * part.Size.X, -0.5 * part.Size.Y, sz * part.Size.Z)).Position.Y
				)
			end
		end
	end
	return -lowest
end

-- A player rig with its sword on the back (sheathed) or in the hand (drawn), its root at ROOT,
-- its Humanoid holding the root `lift` below where its bind-pose soles stand it on the floor.
local function build(drawn: boolean, lift: number): Model
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
			created.CFrame = ROOT
			created.Position = ROOT.Position
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
	-- floorDepth (HipHeight + half the root) = soles - lift.
	humanoid.HipHeight = soles(model) - lift - parts.HumanoidRootPart.Size.Y * 0.5
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
				item.Position = ROOT.Position
			end
		end
	end
	return model
end

-- A flat floor under the rig, where its Humanoid stands it: the foot IK finds no step.
local function floorUnder(model: Model): (origin: Vector3, direction: Vector3) -> Vector3?
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model.PrimaryPart :: BasePart
	local floor = ROOT.Position.Y - (humanoid.HipHeight + root.Size.Y * 0.5)
	return function(origin: Vector3, direction: Vector3): Vector3?
		if direction.Y >= 0 or origin.Y < floor or origin.Y + direction.Y > floor then
			return nil
		end
		return Vector3.new(origin.X, floor, origin.Z)
	end
end

type Take = { guard: Vector3?, tip: Vector3?, stand: number }

-- Plays Basic1 at `fps` on the swinger's own rig (`late` nil) or on a watcher's copy whose
-- ActionStarted comes `late` seconds after the server's start; returns the stroke's first sample
-- in the root's space and the stand height the rig's Root showed on top of the clip.
local function take(drawn: boolean, late: number?, fps: number): Take
	local model = build(drawn, LIFT)
	local own = late == nil
	local record = {
		id = if own then 1 else 2,
		model = model,
		kind = "Player",
		rig = "PlayerR15",
		weaponId = "TrialistSword",
		name = "Ren",
	}
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
	local floor = floorUnder(model)
	Replication.bind({
		net = { on = function() end },
		entities = {
			get = function(id: number): any
				return if id == record.id then record else nil
			end,
		},
		localId = function(): number
			return 1
		end,
		locomotion = {
			attach = function(animator: any, rigName: any, options: any): any
				local withFloor = table.clone(options or {})
				withFloor.footIK = true
				withFloor.raycast = floor
				return Locomotion.attach(animator, rigName, withFloor)
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
		atStepPose = FrameClock.atStepPose,
	} :: any)
	Replication.watch(record)
	local animator: any = Choreo.get(model)
	-- The swinger's own rig: the deps CharacterController hands Locomotion.new, updated before
	-- the rig's step.
	local locomotion: any = nil
	if own then
		locomotion = Locomotion.new(
			animator,
			model,
			{
				raycast = floor,
				atStepPose = FrameClock.atStepPose,
				atStepPoseSolve = FrameClock.atStepPoseSolve,
				stepsAhead = true,
			} :: any
		)
	end
	local tipAttachment = model:FindFirstChild("TrailEnd", true) :: Attachment
	tipAttachment.WorldPosition = ROOT.Position
	local result: Take = { guard = nil, tip = nil, stand = 0 }
	local recording = false
	local realPush = TrailRibbon.push
	TrailRibbon.push = function(ribbon: any, guard: Vector3, tip: Vector3, born: number, joined: boolean): boolean
		local ok = realPush(ribbon, guard, tip, born, joined)
		if recording and ok and result.tip == nil then
			result.guard = ROOT:PointToObjectSpace(guard)
			result.tip = ROOT:PointToObjectSpace(tip)
		end
		return ok
	end
	local dt = 1 / fps
	local function step()
		clock += dt
		hooks.start(dt)
		if hooks.drawn ~= nil then
			hooks.drawn(0)
		end
		if locomotion ~= nil then
			locomotion:update(dt, {
				moveDir = Vector3.zero,
				speed = 0,
				sprinting = false,
				grounded = true,
				drawn = true,
				turning = 0,
			})
		end
		animator:step(dt)
		local channel = animator.mixer._procedural.standHeight
		if channel ~= nil and recording then
			result.stand = channel.offsets.Root.pos[2] * channel.weight
		end
		hooks.posed(dt)
		local posed = BladeContact.chain(model :: any)
		local _, posedTip = BladeContact.blade(posed, BladeContact.read(posed))
		tipAttachment.WorldPosition = posedTip
		if hooks.readers ~= nil then
			hooks.readers(0)
		end
		hooks.finish(dt)
	end
	local ok, err = pcall(function()
		for _ = 1, 90 do
			step()
		end
		recording = true
		if own then
			animator:play(BASIC1, { handOver = true })
		else
			Replication.dispatch(
				"ActionStarted",
				{ entityId = record.id, clipId = BASIC1, serverTime = clock - (late :: number), facing = { 0, 0, -1 } }
			)
		end
		for _ = 1, math.ceil(0.4 * fps) do
			step()
		end
	end)
	TrailRibbon.push = realPush
	if locomotion ~= nil then
		locomotion:destroy()
	end
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

describe("a late remote basic's stroke starts where the swinger's own does (AU 542(d), D-670)", function()
	it("within 0.05 in the root's space, the body held 0.125 under its bind pose, at 60 and 144", function()
		-- Before: 0.093 apart at 60 and 0.165 at 144, the late copy at the clip's own height and the
		-- swinger's own 0.125 lower, where its stand height holds the body (D-506).
		local worst, worstAt = 0, ""
		for _, fps in { 60, 144 } do
			for _, drawn in { false, true } do
				local own = take(drawn, nil, fps)
				local ownTip = own.tip
				expect(ownTip ~= nil).toBe(true)
				expect(math.abs(own.stand - LIFT) < 1e-6).toBe(true)
				for _, late in { 0.1, 0.12, 0.14 } do
					local copy = take(drawn, late, fps)
					local label = ("%d fps, %s, %.2f s late"):format(fps, if drawn then "drawn" else "sheathed", late)
					local copyTip = copy.tip
					expect({ label, copyTip ~= nil }).toEqual({ label, true })
					local apart = ((copyTip :: Vector3) - (ownTip :: Vector3)).Magnitude
					if apart > worst then
						worst, worstAt =
							apart, ("%s: own %s, late %s"):format(label, tostring(ownTip), tostring(copyTip))
					end
				end
			end
		end
		print(("[542(d)] the late first point within %.4f of the swinger's own (%s)"):format(worst, worstAt))
		expect(worst <= BAR).toBe(true)
	end)
end)

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
	rig's step, Basic1 played as basicAttack plays it, and its root carried by the clip's root motion
	after the rig's step, as the controller's step carries it (Basic1's lunge: 0.10 by clip 0.1083,
	0.17 by 0.1167).

	Each first point is read in the root its own screen drew it on (D-684): the watcher's copy draws
	on the root it shows (the server's, which has not taken the lunge at the late start), the
	swinger's own screen on its root at the window's open, between the rows before and on its first
	Core (Trails bladeAt: the two rows' roots, the share of the frame's drawn clip step at which the
	window opens). Read on the root of the row it first shows a Core, the swinger's own point stands
	that frame's lunge behind it: AU 571(a) on 577a59a, 0.117 / 0.087 from the late points, 0.112 /
	0.084 of it along the root's back (Lune 0.090 at 60, 0.083 along it). The watcher's copy through the real
	Replication's ActionStarted, `late` seconds after the server's start, its Locomotion attached by
	Replication. Both with foot IK on over a flat floor (Lune casts no rays: the floor is handed in)
	and a Humanoid that holds the root `lift` off its bind-pose soles.

	Both rigs breathe (Choreo plays Breathe from the frame a rig appears), each from its own start,
	and the back-fill draws none of it: a watcher cannot know the swinger's breath. The breath now
	gives way under the strike (D-685): the blade's joints are out of it by the window's open, so
	the swinger's own first point is the clip's with the body's channels at any point of its breath.
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
-- The player rig's breath, which Choreo plays from the frame the rig appears (rigs.PlayerR15).
local BREATHE = ClipLibrary.get(ChoreoData.rigs.PlayerR15.breathing)
-- Points of the swinger's breath cycle its swing starts at.
local BREATH_PHASES = 16
-- Frames the rig idles before the swing starts.
local WARM_UP = 90
local ROOT = CFrame.new(0, 3, 0)
-- The PC's gap (S542_60_A_1 against the late copies): A's own first point 0.121 below its root,
-- the late ones 0.004 above it.
local LIFT = -0.125
-- AU 542(d): the late copies' first points within 0.05 of A's own.
local BAR = 0.05
-- Where the stroke starts: Basic1's TrailOn.
local OPEN = 0
for _, event in ClipLibrary.get(BASIC1).events do
	if event.kind == "TrailOn" then
		OPEN = event.time
	end
end

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

-- The first sample's tip in the root its screen drew it on (`tip`) and in the root of the row it
-- first shows on (`onRow`).
type Take = { guard: Vector3?, tip: Vector3?, onRow: Vector3?, stand: number, breath: number }

-- Plays Basic1 at `fps` on the swinger's own rig (`late` nil) or on a watcher's copy whose
-- ActionStarted comes `late` seconds after the server's start; returns the stroke's first sample
-- in the root's space, the stand height the rig's Root showed on top of the clip and the rig's
-- breath clock at the start. `breath`: the rig idles on, its breath running from the frame it
-- appeared, until its breath stands there (to the nearest frame) before the swing.
local function take(drawn: boolean, late: number?, fps: number, breath: number?): Take
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
	local result: Take = { guard = nil, tip = nil, onRow = nil, stand = 0, breath = 0 }
	local recording = false
	local rootPart = model.PrimaryPart :: BasePart
	-- Basic1's clock now, and on the rows before: a row draws the pose of the step before (D-342).
	local function clockNow(): number
		for _, handle in animator:handles() do
			if handle.clip.id == BASIC1 then
				return handle.time
			end
		end
		return 0
	end
	local roots: { CFrame } = { rootPart.CFrame, rootPart.CFrame }
	local clocks: { number } = { 0, 0 }
	local realPush = TrailRibbon.push
	TrailRibbon.push = function(ribbon: any, guard: Vector3, tip: Vector3, born: number, joined: boolean): boolean
		local ok = realPush(ribbon, guard, tip, born, joined)
		if recording and ok and result.tip == nil then
			-- The root at the window's open: this row's and the row before's, by the share of the
			-- clip step between the poses they draw (the clocks a step before each) it opens at.
			local before, now = clocks[2], clocks[1]
			local share = if now > before then math.clamp((OPEN - before) / (now - before), 0, 1) else 1
			local drawnOn = roots[1]:Lerp(rootPart.CFrame, share)
			result.guard = drawnOn:PointToObjectSpace(guard)
			result.tip = drawnOn:PointToObjectSpace(tip)
			result.onRow = rootPart.CFrame:PointToObjectSpace(tip)
		end
		return ok
	end
	local dt = 1 / fps
	local function step()
		-- The row before's root, and the clocks the row before and this one draw.
		roots[1] = rootPart.CFrame
		clocks[2], clocks[1] = clocks[1], clockNow()
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
		if own then
			-- CharacterController's step: the clip's root motion, along the facing, after the rig's.
			rootPart.CFrame += rootPart.CFrame:VectorToWorldSpace(animator:currentRootMotionDelta())
		end
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
	local frames = WARM_UP
	if breath ~= nil then
		frames += math.round(((breath - WARM_UP * dt) % BREATHE.duration) * fps)
	end
	local ok, err = pcall(function()
		for _ = 1, frames do
			step()
		end
		for _, handle in animator:handles() do
			if handle.clip.id == BREATHE.id then
				result.breath = handle.time
			end
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
	it("within 0.05 in the root it was drawn on, the body held 0.125 under its bind pose, at 60 and 144", function()
		-- Before D-670: 0.093 apart at 60 and 0.165 at 144, the late copy at the clip's own height
		-- and the swinger's own 0.125 lower, where its stand height holds the body (D-506). On the
		-- root of the row each first shows on, the swinger's own lunge parts them (AU 571(a),
		-- D-684): 0.090 / 0.056 at 60 / 144, 0.083 / 0.031 of it along the root's back. With the
		-- swinger's breath 1.5 s in, 0.0475 at 144 before the breath gave way under the strike
		-- (D-685), 0.0045 since.
		local worst, worstAt = 0, ""
		-- The same points read on the root of the row each first shows on (571(a)'s first reading).
		local onRow: { [number]: number } = { [60] = 0, [144] = 0 }
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
					onRow[fps] = math.max(onRow[fps], ((copy.onRow :: Vector3) - (own.onRow :: Vector3)).Magnitude)
					if apart > worst then
						worst, worstAt =
							apart, ("%s: own %s, late %s"):format(label, tostring(ownTip), tostring(copyTip))
					end
				end
			end
		end
		print(
			("[542(d)] the late first point within %.4f of the swinger's own (%s); on the rows' roots %.4f / %.4f at 60 / 144"):format(
				worst,
				worstAt,
				onRow[60],
				onRow[144]
			)
		)
		expect(worst <= BAR).toBe(true)
	end)
	it("within 0.05 with the swinger breathing from every point of its cycle, at 60 and 144 (AU 571(a))", function()
		-- Every player rig breathes (Choreo plays Breathe from the frame it appears, never
		-- stopping), each screen from its own start, and a hit-stop pauses it: no watcher knows
		-- the swinger's breath. The back-fill draws the clip's blade with the body's channels and
		-- no breath; the swinger's own screen drew it with the breath on, whose waist, shoulder,
		-- wrist and sword keys carried the first point 0.023-0.120 from the late copies' at 60,
		-- 11 of 16 points of the cycle over 0.05, and 0.023-0.124 at 144. Since the breath gives way
		-- under the strike (D-685), out of the blade's joints by the open: within 0.0000 / 0.0117
		-- at 60 / 144 (what is left of it on the 144 Hz frame short of the open).
		local worst: { [number]: number } = { [60] = 0, [144] = 0 }
		local worstAt: { [number]: string } = {}
		local over: { [number]: number } = { [60] = 0, [144] = 0 }
		for _, fps in { 60, 144 } do
			for _, drawn in { false, true } do
				local copies: { Vector3 } = {}
				for _, late in { 0.1, 0.12, 0.14 } do
					local copy = take(drawn, late, fps)
					expect(copy.tip ~= nil).toBe(true)
					table.insert(copies, copy.tip :: Vector3)
				end
				for step = 0, BREATH_PHASES - 1 do
					local breath = BREATHE.duration * step / BREATH_PHASES
					local own = take(drawn, nil, fps, breath)
					local label = ("%d fps, %s, breath at %.3f s (%.4f)"):format(
						fps,
						if drawn then "drawn" else "sheathed",
						breath,
						own.breath
					)
					expect({ label, own.tip ~= nil }).toEqual({ label, true })
					local apart = 0
					for _, copyTip in copies do
						apart = math.max(apart, (copyTip - (own.tip :: Vector3)).Magnitude)
					end
					if apart > BAR then
						over[fps] += if drawn then 0 else 1
					end
					if apart > worst[fps] then
						worst[fps], worstAt[fps] = apart, label
					end
				end
			end
		end
		print(
			("[571(a)] breathing: the late first point within %.4f / %.4f of the swinger's own at 60 / 144 (%s; %s), sheathed phases over %.2f: %d / %d"):format(
				worst[60],
				worst[144],
				worstAt[60] or "",
				worstAt[144] or "",
				BAR,
				over[60],
				over[144]
			)
		)
		expect(math.max(worst[60], worst[144]) <= BAR).toBe(true)
	end)
end)

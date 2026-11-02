--!strict
--[[
	The sword reaches the hand on the frame that draws the hand's grab (AG 376(b), D-555).

	What the screen shows (measured on the owner's PC, AG 376(b) and the render check): a frame
	draws BasePart.CFrame, the pose physics solved from the joints as the rigs' step of the frame
	before wrote them; and a Motor6D whose Part0 or C0 is written during a frame's render steps puts
	its Part1 on the new Part0 at once, from that part as physics last solved it and the joint's
	Transform as it stands. The spec's screen is that model: each frame runs FrameClock's first
	render step, the rig's step, FrameClock's posed mark, then logs the row item 397's logger reads
	at Last+2 (the hand, the blade's guard and tip, the Weapon motor's Part0), then FrameClock's last
	step, then "physics" solves every part from the joints. A Part0 or C0 change is put on its part
	when it is seen: after the first render step, inside the rig's step (just before the mixer) and
	after it.

	Before, WeaponMount moved the Weapon motor inside the step that wrote the attack's first pose,
	so for one row the sword hung in the hand of the pose before (the PC: the tip on 4.10 to 4.14
	studs, the hand 0.000 to 0.003; Lune 5.99 and 0.0016 at 60 fps), and the grab showed a row
	later. Now the move waits for FrameClock.atStepPose and lands on the row that draws that pose.

	The real path: a real Choreo animator on a RigBuilder player rig with its WeaponBuilder sword,
	the real ClipLibrary clips, the real Locomotion (SheathState, WeaponMount), the real FrameClock
	on fake render steps, and for a remote rig the real Replication's ActionStarted (its network
	catch-up and the atStepPose it hands the rig's Locomotion). The caster's own rig gets the deps
	CharacterController hands Locomotion.new (atStepPose; foot IK off, as Lune casts no rays) and
	its clips as the controller plays them.
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
local Joints = Harness.load("src/shared/choreo/Joints")
local Accents = Harness.load("src/shared/data/accents")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Rigs = Harness.load("src/shared/data/rigs")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local WeaponBuilder = Harness.load("src/server/world/WeaponBuilder")
local WeaponModels = Harness.load("src/shared/data/weaponModels")
local Weapons = Harness.load("src/shared/data/weapons")

local PREFIX = ChoreoData.locomotion.clipPrefix
local BASIC1 = PREFIX .. "Basic1"
local RATES = { 30, 60, 144 }
local LAGS = { 0, 0.1, 0.25 }
local SETTLE = 1.5 -- seconds in the start state before the press
-- A row whose hand moved less than this many times the most it moved on any of the idle rows
-- before the press shows the pose from before the press.
local STILL_FACTOR = 5
local IDLE_ROWS = 10

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

-- A player rig with its sword, on the back mount (sheathed) or in the hand (drawn).
local function build(drawn: boolean): (Model, any, BasePart)
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
	local weaponMotor: any = nil
	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") and item.Name == WeaponModels.motorName then
			weaponMotor = item
		elseif item:IsA("BasePart") then
			local ok = pcall(function(): Vector3
				return item.Position
			end)
			if not ok then
				item.Position = Vector3.new(0, 3, 0)
			end
		end
	end
	return model, weaponMotor, parts.RightHand
end

-- What the screen shows: each part's CFrame as physics last solved it, and the Weapon motor's
-- Part0 and C0 that solve (or the last at-once placement) used.
type Screen = { parts: { [any]: CFrame }, part0: any, c0: CFrame? }

-- Physics: every part solved outward from the root part through the joints as they stand.
local function solve(screen: Screen, model: Model, motor: any)
	local root = model.PrimaryPart :: BasePart
	local parts: { [any]: CFrame } = { [root] = root.CFrame }
	local resolved = Joints.collect(model)
	local progressed = true
	while progressed do
		progressed = false
		for _, joint in resolved do
			if parts[joint.part1] == nil and parts[joint.part0] ~= nil then
				parts[joint.part1] = parts[joint.part0] * joint.c0 * (joint.joint :: any).Transform * joint.c1:Inverse()
				progressed = true
			end
		end
	end
	screen.parts = parts
	screen.part0 = motor.Part0
	screen.c0 = motor.C0
end

-- A Part0 or C0 write puts the blade on its new part at once, from that part as physics last
-- solved it and the joint's Transform as it stands.
local function place(screen: Screen, motor: any)
	if motor.Part0 ~= screen.part0 or motor.C0 ~= screen.c0 then
		local base = screen.parts[motor.Part0]
		if base ~= nil then
			screen.parts[motor.Part1] = base * motor.C0 * motor.Transform * motor.C1:Inverse()
		end
		screen.part0 = motor.Part0
		screen.c0 = motor.C0
	end
end

-- One logged row: what the frame draws (`hand`, `guard`, `tip`, `inHand`: the Weapon motor's Part0
-- is the hand), and the pose the frame's physics then solved from the step's joints (`posed*`).
type Row = {
	hand: Vector3,
	guard: Vector3,
	tip: Vector3,
	inHand: boolean,
	posedHand: Vector3,
	posedGuard: Vector3,
	posedTip: Vector3,
}

type Rig = {
	model: Model,
	motor: any,
	hand: BasePart,
	start: Attachment,
	tip: Attachment,
	animator: any,
	screen: Screen,
	update: ((dt: number) -> ())?,
	readers: ((dt: number) -> ())?,
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

local function bindClock()
	clock = 100
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
end

local function prepare(model: Model, motor: any, hand: BasePart): Rig
	local animator: any = Choreo.get(model)
	local rig: Rig = {
		model = model,
		motor = motor,
		hand = hand,
		start = model:FindFirstChild("TrailStart", true) :: Attachment,
		tip = model:FindFirstChild("TrailEnd", true) :: Attachment,
		animator = animator,
		screen = { parts = {}, part0 = nil, c0 = nil },
		update = nil,
		readers = nil,
	}
	-- The oldest hook runs last: after Locomotion's and WeaponMount's, just before the mixer.
	animator:onStep(function()
		place(rig.screen, motor)
	end)
	solve(rig.screen, model, motor)
	return rig
end

local function frame(rig: Rig, dt: number): Row
	clock += dt
	hooks.start(dt)
	place(rig.screen, rig.motor)
	local update = rig.update
	if update ~= nil then
		update(dt)
	end
	rig.animator:step(dt)
	place(rig.screen, rig.motor)
	hooks.posed(dt)
	local readers = rig.readers
	if readers ~= nil then
		readers(dt)
	end
	local parts = rig.screen.parts
	local blade = parts[rig.motor.Part1]
	local hand = parts[rig.hand].Position
	local guard = (blade * rig.start.CFrame).Position
	local tip = (blade * rig.tip.CFrame).Position
	local inHand = rig.motor.Part0 == rig.hand
	hooks.finish(dt)
	solve(rig.screen, rig.model, rig.motor)
	local posed = rig.screen.parts
	local posedBlade = posed[rig.motor.Part1]
	return {
		hand = hand,
		guard = guard,
		tip = tip,
		inHand = inHand,
		posedHand = posed[rig.hand].Position,
		posedGuard = (posedBlade * rig.start.CFrame).Position,
		posedTip = (posedBlade * rig.tip.CFrame).Position,
	}
end

-- A take: `rows` from the first frame on, `pressed` the last row before the press (the press comes
-- between that frame and the next, so row pressed + 1 is the step that writes its first pose).
type Take = { rows: { Row }, pressed: number, fps: number, off: number? }

-- A remote rig's sheathed opener: Basic1's ActionStarted `late` seconds after the server's start,
-- through the real Replication. `gate` false binds Replication with no atStepPose (the sword moves
-- inside the step, as before). With `trails`, the real Trails samples the blade, and the take
-- reads its swing direction against the blade's own chord over the snap frames from the first row
-- in the hand (D-473; Lune derives no WorldPosition, so TrailEnd goes where the step posed it
-- before the readers run, as LateRemoteRibbon.spec has it).
local function remoteTake(late: number, fps: number, gate: boolean, trails: boolean?): Take
	bindClock()
	local model, motor, hand = build(false)
	local record =
		{ id = 2, model = model, kind = "Player", rig = "PlayerR15", weaponId = "TrialistSword", name = "Ren" }
	local rig = prepare(model, motor, hand)
	local tipAttachment = rig.tip
	if trails then
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
			held = function(): boolean
				return false
			end,
			animator = function(target: Instance): any
				return Choreo.find(target :: any)
			end,
		})
		tipAttachment.WorldPosition = Vector3.new(0, 3, 0)
		rig.readers = function(dt: number)
			local chain = BladeContact.chain(model :: any)
			local _, posedTip = BladeContact.blade(chain, BladeContact.read(chain))
			tipAttachment.WorldPosition = posedTip
			if hooks.readers ~= nil then
				hooks.readers(dt)
			end
		end
	end
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
			attach = function(animator: any, rigModel: any, options: any): any
				local withoutIK = table.clone(options or {})
				withoutIK.footIK = false
				return Locomotion.attach(animator, rigModel, withoutIK)
			end,
			destroy = Locomotion.destroy,
			humanoidTracker = Locomotion.humanoidTracker,
		},
		choreo = Choreo,
		clipLibrary = ClipLibrary,
		trails = if trails then Trails else recorder(),
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
		atStepPose = if gate then FrameClock.atStepPose else nil,
	} :: any)
	Replication.watch(record)
	local take: Take = { rows = {}, pressed = 0, fps = fps, off = nil }
	local dt = 1 / fps
	local ok, err = pcall(function()
		for _ = 1, math.ceil(SETTLE * fps) do
			table.insert(take.rows, frame(rig, dt))
		end
		take.pressed = #take.rows
		Replication.dispatch(
			"ActionStarted",
			{ entityId = 2, clipId = BASIC1, serverTime = clock - late, facing = { 0, 0, -1 } }
		)
		local snapFrames = Accents.swing.snapFrames
		local inHandTips: { Vector3 } = {}
		for _ = 1, math.ceil(0.4 * fps) do
			local row = frame(rig, dt)
			table.insert(take.rows, row)
			if trails and row.inHand and take.off == nil then
				table.insert(inHandTips, tipAttachment.WorldPosition)
				if #inHandTips == snapFrames + 1 then
					local measured = Trails.swingDirection(model)
					local truth = (inHandTips[#inHandTips] - inHandTips[1]).Unit
					take.off = if measured ~= nil
						then math.deg(math.acos(math.clamp((measured :: Vector3):Dot(truth), -1, 1)))
						else 180
				end
			end
		end
	end)
	Replication.unwatch(record)
	if trails then
		Trails.bind(nil)
		Trails.reset()
		Engine.setViewer(nil)
		Engine.setClock(nil)
		hooks.readers = nil
		hooks.drawn = nil
	end
	Choreo.release(model)
	FrameClock.bind(nil)
	if not ok then
		error(err, 0)
	end
	return take
end

-- The caster's own rig, as CharacterController drives it: Locomotion.new with the controller's
-- deps (atStepPose, or none with `gate` false), its update before the rig's step with the Drawn
-- target the controller predicts, and the press's clip played between frames. `drawn` is the
-- start state; `act` plays the press's clips, and the target becomes `to`.
local function localTake(
	fps: number,
	drawn: boolean,
	to: boolean,
	act: ((animator: any) -> ())?,
	seconds: number,
	gate: boolean
): Take
	bindClock()
	local model, motor, hand = build(drawn)
	local rig = prepare(model, motor, hand)
	local locomotion: any = Locomotion.new(
		rig.animator,
		model,
		{ footIK = false, atStepPose = if gate then FrameClock.atStepPose else nil } :: any
	)
	local target = drawn
	rig.update = function(dt: number)
		locomotion:update(dt, {
			moveDir = Vector3.zero,
			speed = 0,
			sprinting = false,
			grounded = true,
			drawn = target,
			turning = 0,
		})
	end
	local take: Take = { rows = {}, pressed = 0, fps = fps, off = nil }
	local dt = 1 / fps
	local ok, err = pcall(function()
		for _ = 1, math.ceil(SETTLE * fps) do
			table.insert(take.rows, frame(rig, dt))
		end
		take.pressed = #take.rows
		if act ~= nil then
			act(rig.animator)
		end
		target = to
		for _ = 1, math.ceil(seconds * fps) do
			table.insert(take.rows, frame(rig, dt))
		end
	end)
	locomotion:destroy()
	Choreo.release(model)
	FrameClock.bind(nil)
	if not ok then
		error(err, 0)
	end
	return take
end

-- The caster's sheathed opener: Basic1 played as CharacterController.basicAttack plays it, the
-- target drawn with it (predictDraw).
local function localOpener(fps: number, gate: boolean): Take
	return localTake(fps, false, true, function(animator: any)
		animator:play(BASIC1, { handOver = true })
	end, 0.4, gate)
end

local function moved(rows: { Row }, index: number, key: string): number
	return ((rows[index] :: any)[key] - (rows[index - 1] :: any)[key]).Magnitude
end

-- The most the hand moved on any of the idle rows before the press.
local function idleMove(take: Take): number
	local most = 0
	for index = take.pressed - IDLE_ROWS + 1, take.pressed do
		most = math.max(most, moved(take.rows, index, "hand"))
	end
	return most
end

-- Row P: the first row after the press whose Weapon motor's Part0 reads the hand.
local function rowP(take: Take): number?
	for index = take.pressed + 1, #take.rows do
		if take.rows[index].inHand then
			return index
		end
	end
	return nil
end

-- Every row after the press where the sword shows in a hand that has not moved from the pose
-- before (its hand moved under STILL_FACTOR times the idle's most), with the tip moving over a
-- stud or the sword just landing in that hand. Each as "row (from P): hand, tip".
local function stillHandRows(take: Take): { string }
	local rows = take.rows
	local still = STILL_FACTOR * idleMove(take)
	local found: { string } = {}
	local p = rowP(take) or 0
	for index = take.pressed + 1, #rows do
		local hand = moved(rows, index, "hand")
		local tip = moved(rows, index, "tip")
		local landed = rows[index].inHand and not rows[index - 1].inHand
		if (landed or tip > 1) and hand < still then
			table.insert(found, ("row P%+d: hand %.4f, tip %.3f"):format(index - p, hand, tip))
		end
	end
	return found
end

-- Rows where the screen with the move held for its pose (`held`) does not draw what the step
-- before posed with the move made inside the step (`inStep`): the same pose a frame late, the
-- sword's place included. Each as "row: studs off".
local function lateByOne(held: Take, inStep: Take): { string }
	local found: { string } = {}
	for index = 2, math.min(#held.rows, #inStep.rows) do
		local shown, posed = held.rows[index], inStep.rows[index - 1]
		local off = math.max(
			(shown.hand - posed.posedHand).Magnitude,
			(shown.guard - posed.posedGuard).Magnitude,
			(shown.tip - posed.posedTip).Magnitude
		)
		if off > 1e-4 then
			table.insert(found, ("row %d (press +%d): %.4f"):format(index, index - held.pressed, off))
		end
	end
	return found
end

describe("The sword reaches the hand on the frame that draws the grab (AG 376(b), D-555)", function()
	it("a remote sheathed opener at lags 0, 0.1 and 0.25, at 30, 60 and 144: row P draws the grab", function()
		-- Before: row P was the row of the opener's own step: its hand moved 0.0031 / 0.0016 / 0.0007
		-- (30 / 60 / 144) while the tip went 5.99 studs. Now P is the next row, the one that draws
		-- that step's pose: the hand moves 0.13 to 0.41 / 0.038 to 0.106 / 0.0072 to 0.019.
		for _, fps in RATES do
			for _, late in LAGS do
				local take = remoteTake(late, fps, true)
				local label = ("%d fps, %.2f s late"):format(fps, late)
				local p = rowP(take)
				expect({ label, p }).toEqual({ label, take.pressed + 2 })
				local hand = moved(take.rows, p :: number, "hand")
				expect({ label, hand >= STILL_FACTOR * idleMove(take) }).toEqual({ label, true })
				if fps == 60 then
					expect({ label, hand >= 0.03 }).toEqual({ label, true })
				end
				expect({ label, moved(take.rows, p :: number, "tip") > 4 }).toEqual({ label, true })
				expect({ label, stillHandRows(take) }).toEqual({ label, {} })
			end
		end
	end)

	it(
		"the caster's own sheathed opener at 30, 60 and 144, on the deps CharacterController hands Locomotion",
		function()
			-- Before: the hand 0.0031 / 0.0016 / 0.0007 on row P; now 0.21 / 0.089 / 0.030.
			for _, fps in RATES do
				local take = localOpener(fps, true)
				local label = ("%d fps"):format(fps)
				local p = rowP(take)
				expect({ label, p }).toEqual({ label, take.pressed + 2 })
				local hand = moved(take.rows, p :: number, "hand")
				expect({ label, hand >= STILL_FACTOR * idleMove(take) }).toEqual({ label, true })
				if fps == 60 then
					expect({ label, hand >= 0.03 }).toEqual({ label, true })
				end
				expect({ label, stillHandRows(take) }).toEqual({ label, {} })
			end
		end
	)

	it(
		"draws each step's pose a frame late, the sword's place included: openers, Draw, Sheathe, the sheathed guard, a dodge",
		function()
			-- The move held for its pose against the move made inside the step: every row draws what
			-- the step before posed, as SheathTip, GroundClearance and the hit matrix read the pose
			-- (the joints right after the step), so their pass lines hold on the screen too. Before,
			-- the move's own row drew the sword placed on the pose before: 5.99 studs off for an
			-- opener, 0.50 to 0.66 for a Draw (alone, over a guard or after a dodge), 0.52 to 0.53
			-- for a Sheathe.
			local GUARD = PREFIX .. "Guard"
			local DODGE = PREFIX .. "DodgeForward"
			local cases: { { name: string, run: (fps: number, gate: boolean) -> Take } } = {
				{
					name = "the caster's opener",
					run = localOpener,
				},
				{
					name = "Draw",
					run = function(fps: number, gate: boolean): Take
						return localTake(fps, false, true, nil, 1.2, gate)
					end,
				},
				{
					name = "Sheathe",
					run = function(fps: number, gate: boolean): Take
						return localTake(fps, true, false, nil, 2.0, gate)
					end,
				},
				{
					name = "a guard raised sheathed",
					run = function(fps: number, gate: boolean): Take
						return localTake(fps, false, true, function(animator: any)
							animator:play(GUARD, { handOver = true })
						end, 1.2, gate)
					end,
				},
				{
					-- A lock-on pressed with a dodge out of the sheathed stance: the Draw waits for
					-- the dodge to give the arm back.
					name = "a dodge out of the sheathed stance, drawn with it",
					run = function(fps: number, gate: boolean): Take
						return localTake(fps, false, true, function(animator: any)
							animator:play(DODGE, { handOver = true })
						end, 1.6, gate)
					end,
				},
			}
			for _, late in LAGS do
				table.insert(cases, {
					name = ("a remote opener %.2f s late"):format(late),
					run = function(fps: number, gate: boolean): Take
						return remoteTake(late, fps, gate)
					end,
				})
			end
			for _, case in cases do
				for _, fps in RATES do
					local label = ("%s, %d fps"):format(case.name, fps)
					local held = case.run(fps, true)
					local inStep = case.run(fps, false)
					-- The sword changed place in the take (none in a dodge that keeps it sheathed).
					local swapped = false
					for index = held.pressed + 1, #held.rows do
						if held.rows[index].inHand ~= held.rows[held.pressed].inHand then
							swapped = true
						end
					end
					expect({ label, swapped }).toEqual({ label, true })
					expect({ label, lateByOne(held, inStep) }).toEqual({ label, {} })
				end
			end
		end
	)

	it("D-473 in the game's frame order: a remote sheathed opener's swing is read in the hand", function()
		-- With atStepPose bound (the late stroke lit on the frame that draws the clip, D-538), the
		-- sword used to land in the step and the ring took its first hand sample a frame before the
		-- stroke's own pose: 15.6, 13.4 and 12.1 degrees off at 85, 100 and 120 ms. Now 0.00 to 0.02.
		for _, late in { 0.085, 0.1, 0.12, 0.15, 0.2, 0.25 } do
			local take = remoteTake(late, 60, true, true)
			local label = ("%.3f s late"):format(late)
			expect({ label, take.off ~= nil and (take.off :: number) < 10 }).toEqual({ label, true })
		end
	end)
end)

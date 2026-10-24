--!strict
--[[
	CharacterController's engine glue, loaded fresh with fakes around it: a Humanoid whose Move sets
	MoveDirection (as the engine's does), a root part, stub Choreo modules (Siblings), the render
	step captured from BindToRenderStep, and Net.client() recording every request. A frame runs the
	way the engine runs it: the control script's Move with the stick first, then the controller's
	step, then physics moves the root at the Humanoid's move and WalkSpeed (so the step reads the
	velocity of the frame before, as it does in the engine). The Humanoid records every property
	write (each one fires Changed, and a client WalkSpeed write is networked), and an optional fake
	fx.Impact sibling records the director calls the controller makes.
]]

local luau = require("@lune/luau")

local Signal = Harness.load("src/shared/util/Signal")
local Siblings = Harness.load("src/client/controllers/Siblings")
local ChoreoData = Harness.load("src/shared/data/choreo")
local AimLogic = Harness.load("src/client/controllers/AimLogic")

local CONTROLLER_PATH = "src/client/controllers/CharacterController"
local FRAME = 1 / 60

type Rig = {
	controller: any,
	sent: { { name: string, payload: any } },
	-- One frame with the stick at a world direction (zero for none).
	frame: (stick: Vector3) -> (),
	-- One frame with the display asleep: the clock moves and Heartbeat fires, no render step runs.
	heartbeat: () -> (),
	humanoid: any,
	model: any,
	-- Every Humanoid property write, in order ({ key, value }).
	writes: { { key: string, value: any } },
	-- The sends and the fake Impact's calls in one ordered list ({ kind = "send" | "impact", name, args }).
	log: { { kind: string, name: string, args: { any } } },
	-- The HumanoidRootPart (CFrame and Position kept in step, as on a part).
	root: any,
	-- Locks an enemy standing at `position` (nil: no lock).
	setLock: (position: Vector3?) -> (),
	-- The enemies the soft assist sees: { id, position }.
	setEnemies: (enemies: { { id: number, position: Vector3 } }) -> (),
	-- The last input the controller handed Locomotion.update.
	locomotionInput: () -> any,
	-- Every scale the controller handed the animator's setTimeScale, in order (options.animator).
	timeScales: { number },
	-- The root motion the animator hands out each frame (options.animator), in the root's space.
	setRootMotion: (delta: Vector3) -> (),
	-- The server refuses the local action (Replication.rejected).
	reject: (action: string) -> (),
	-- The character goes and comes back (CharacterRemoving, then CharacterAdded with the same model).
	respawn: () -> (),
}

type Options = {
	-- The fake Locomotion's stopGait, with the gait phase moving on by this much per call (0 holds
	-- it still). It starts at 0.1, the left foot plants at 0 and the right at 0.5, each 0.3 of a
	-- cycle before it is over its Idle spot: a carry that starts there runs 0.7 of a cycle.
	stopGait: number?,
	-- Hand the controller a recording fx.Impact sibling instead of a stub.
	impact: boolean?,
	-- Hand the controller a Choreo whose animator records setTimeScale and hands out root motion.
	animator: boolean?,
	-- The place is a capture place (workspace DevCapture attribute, dev.luau attributes.capture).
	capture: boolean?,
	-- false: the place runs on a live server, not in Studio (RunService:IsStudio()); default Studio.
	studio: boolean?,
}

local IMPACT_CALLS = { "guardRaise", "dodge", "release", "cancelActivation", "activation" }

local function load(options: Options?): Rig
	local opts: Options = options or {}
	local clock = 0
	local step: ((dt: number) -> ())? = nil
	local sent: { { name: string, payload: any } } = {}
	local writes: { { key: string, value: any } } = {}
	local log: { { kind: string, name: string, args: { any } } } = {}
	local props: { [string]: any } = {
		WalkSpeed = 16,
		JumpPower = 0,
		JumpHeight = 0,
		AutoRotate = true,
		MoveDirection = Vector3.zero,
		FloorMaterial = Enum.Material.Grass,
	}
	function props.Move(self: any, direction: Vector3)
		self.MoveDirection = if direction.Magnitude > 0 then direction.Unit else Vector3.zero
	end
	local humanoid: any = setmetatable({}, {
		__index = props,
		__newindex = function(_self: any, key: string, value: any)
			table.insert(writes, { key = key, value = value })
			props[key] = value
		end,
	})
	local rootState: { [string]: any } = { CFrame = CFrame.new(), AssemblyLinearVelocity = Vector3.zero }
	local root: any = setmetatable({}, {
		__index = function(_self: any, key: string): any
			if key == "Position" then
				return rootState.CFrame.Position
			end
			return rootState[key]
		end,
		__newindex = function(_self: any, key: string, value: any)
			if key == "Position" then
				rootState.CFrame = rootState.CFrame.Rotation + value
			else
				rootState[key] = value
			end
		end,
	})
	local lockRecord: any = nil
	local enemies: { { id: number, position: Vector3 } } = {}
	local lastInput: any = nil
	local model = {
		WaitForChild = function(_self: any, name: string): any
			return if name == "Humanoid" then humanoid else root
		end,
		GetAttribute = function(): any
			return nil
		end,
		GetAttributeChangedSignal = function(): any
			return Signal.new()
		end,
	}
	local gaitPhase = 0.1 - (opts.stopGait or 0)
	local locomotion = {
		new = function(): any
			return {
				serverDrawn = function(): boolean
					return false
				end,
				update = function(_self: any, _dt: number, input: any)
					lastInput = input
				end,
				stopGait = if opts.stopGait ~= nil
					then function(_self: any, into: any)
						gaitPhase = (gaitPhase + (opts.stopGait :: number)) % 1
						into.phase, into.leftStep, into.leftAfter, into.rightStep, into.rightAfter =
							gaitPhase, 0, 0.3, 0.5, 0.3
					end
					else nil,
			}
		end,
	}
	local timeScales: { number } = {}
	local rootMotion = Vector3.zero
	local animator = {
		play = function(_self: any, clipId: string): any
			return { clipId = clipId }
		end,
		stop = function() end,
		setTimeScale = function(_self: any, scale: number)
			table.insert(timeScales, scale)
		end,
		currentRootMotionDelta = function(_self: any): Vector3
			return rootMotion
		end,
	}
	local choreo = {
		get = function(): any
			return animator
		end,
		setLocalModel = function() end,
	}
	local impact: { [string]: any } = {}
	for _, name in IMPACT_CALLS do
		impact[name] = function(...: any)
			table.insert(log, { kind = "impact", name = name, args = { ... } })
		end
	end
	-- TargetController, through Siblings: the lock and the soft assist's candidates.
	local targetController = {
		current = function(): any
			return lockRecord
		end,
		assistCandidates = function(origin: Vector3, look: Vector3): { any }
			local list = {}
			for _, enemy in enemies do
				local dx, dz = enemy.position.X - origin.X, enemy.position.Z - origin.Z
				table.insert(list, {
					id = enemy.id,
					distance = math.sqrt(dx * dx + dz * dz),
					bearing = AimLogic.bearing(look.X, look.Z, dx, dz),
				})
			end
			return list
		end,
	}
	local fakes: { [string]: any } = {
		Net = {
			client = function(): any
				return {
					fire = function(name: string, payload: any)
						table.insert(sent, { name = name, payload = payload })
						table.insert(log, { kind = "send", name = name, args = { payload } })
					end,
					on = function() end,
				}
			end,
		},
		EntityTracker = {
			localRecord = function(): any
				return nil
			end,
			peekLocalId = function(): any
				return nil
			end,
			changed = Signal.new(),
			localChanged = Signal.new(),
		},
		Replication = { rejected = Signal.new(), hit = Signal.new(), clipEvent = Signal.new() },
		CameraController = { fovKick = function() end },
		Siblings = {
			load = function(_parent: any, path: string): (any, boolean)
				if path == "choreo.Locomotion" then
					return locomotion, true
				end
				if path == "fx.Impact" and opts.impact then
					return impact, true
				end
				if path == "choreo.Choreo" and opts.animator then
					return choreo, true
				end
				if path == "controllers.TargetController" then
					return targetController, true
				end
				return Siblings.stub(), false
			end,
			call = Siblings.call,
			stub = Siblings.stub,
		},
	}
	local heartbeat = Signal.new()
	local localPlayer = { CharacterAdded = Signal.new(), CharacterRemoving = Signal.new(), Character = model }
	local services: { [string]: any } = {
		RunService = {
			BindToRenderStep = function(_self: any, _name: string, _priority: number, fn: (dt: number) -> ())
				step = fn
			end,
			Heartbeat = heartbeat,
			IsStudio = function(_self: any): boolean
				return opts.studio ~= false
			end,
		},
		Players = { LocalPlayer = localPlayer },
		ReplicatedStorage = Harness.game():GetService("ReplicatedStorage"),
	}
	local env = Harness.environment()
	env.script = Harness.node(CONTROLLER_PATH)
	env.require = function(target: any): any
		return fakes[target.Name] or Harness.loadModule(target)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			return services[name]
		end,
	}
	local attributes: { [string]: any } = { DevCapture = opts.capture }
	env.workspace = {
		GetServerTimeNow = function(): number
			return clock
		end,
		GetAttribute = function(_self: any, name: string): any
			return attributes[name]
		end,
	}
	env.os = {
		clock = function(): number
			return clock
		end,
	}
	env.task = { delay = function() end }
	local controller = luau.load(
		Harness.readFile(CONTROLLER_PATH .. ".luau"),
		{ debugName = CONTROLLER_PATH, environment = env :: any }
	)()
	controller.start()
	assert(step ~= nil, "the controller bound no render step")
	return {
		controller = controller,
		sent = sent,
		humanoid = humanoid,
		model = model,
		writes = writes,
		log = log,
		root = root,
		setLock = function(position: Vector3?)
			lockRecord = if position ~= nil
				then { id = 1, kind = "Enemy", state = "Idle", model = { PrimaryPart = { Position = position } } }
				else nil
		end,
		setEnemies = function(list: { { id: number, position: Vector3 } })
			enemies = list
		end,
		locomotionInput = function(): any
			return lastInput
		end,
		timeScales = timeScales,
		setRootMotion = function(delta: Vector3)
			rootMotion = delta
		end,
		reject = function(action: string)
			fakes.Replication.rejected:Fire(action)
		end,
		respawn = function()
			localPlayer.CharacterRemoving:Fire()
			localPlayer.CharacterAdded:Fire(model)
		end,
		heartbeat = function()
			clock += FRAME
			heartbeat:Fire(FRAME)
		end,
		frame = function(stick: Vector3)
			clock += FRAME
			humanoid:Move(stick)
			local runStep = step :: (dt: number) -> ()
			runStep(FRAME)
			root.AssemblyLinearVelocity = humanoid.MoveDirection * humanoid.WalkSpeed
			root.Position += root.AssemblyLinearVelocity * FRAME
			local move = humanoid.MoveDirection
			if props.AutoRotate and move.Magnitude > 0 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + Vector3.new(move.X, 0, move.Z))
			end
			heartbeat:Fire(FRAME) -- after the render step and the physics, as in a frame
		end,
	}
end

local function lastDodge(rig: Rig): Vector3?
	for index = #rig.sent, 1, -1 do
		local entry = rig.sent[index]
		if entry.name == "DodgeRequest" then
			local d = entry.payload.direction
			return Vector3.new(d[1], d[2], d[3])
		end
	end
	return nil
end

local FORWARD = Vector3.new(0, 0, -1) -- the root's look (CFrame.new() faces -Z)

describe("CharacterController dodge direction", function()
	it("with the stick held forward the dodge goes forward", function()
		local rig = load()
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		rig.controller.dodge()
		local direction = lastDodge(rig)
		expect(direction).never.toBeNil()
		expect((direction :: Vector3).Z).toBeCloseTo(FORWARD.Z, 1e-6)
		expect((direction :: Vector3).X).toBeCloseTo(0, 1e-6)
	end)

	it("a dodge pressed during the two-step stop steps back: the stick let go", function()
		local rig = load()
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		-- The stick lets go: the two-step stop carries the Humanoid along the last move.
		rig.frame(Vector3.zero)
		rig.frame(Vector3.zero)
		expect(rig.humanoid.MoveDirection.Z).toBeCloseTo(FORWARD.Z, 1e-6)
		rig.controller.dodge()
		local direction = lastDodge(rig)
		expect(direction).never.toBeNil()
		expect((direction :: Vector3).Z).toBeCloseTo(-FORWARD.Z, 1e-6)
		expect((direction :: Vector3).X).toBeCloseTo(0, 1e-6)
	end)

	it("after the stop has run out the Humanoid is still and the dodge steps back", function()
		local rig = load()
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		local frames = math.ceil(ChoreoData.locomotion.stopStepsSeconds / FRAME) + 2
		for _ = 1, frames do
			rig.frame(Vector3.zero)
		end
		expect(rig.humanoid.MoveDirection.Magnitude).toBe(0)
		rig.controller.dodge()
		local direction = lastDodge(rig)
		expect(direction).never.toBeNil()
		expect((direction :: Vector3).Z).toBeCloseTo(-FORWARD.Z, 1e-6)
		expect((direction :: Vector3).X).toBeCloseTo(0, 1e-6)
	end)
end)

-- Humanoid writes of `key` from write index `from` on.
local function writesOf(rig: Rig, key: string, from: number): { any }
	local values = {}
	for index = from, #rig.writes do
		local entry = rig.writes[index]
		if entry.key == key then
			table.insert(values, entry.value)
		end
	end
	return values
end

describe("CharacterController's two-step stop", function()
	it("holds the speed it had through Humanoid.WalkSpeed while the gait has not walked on", function()
		-- The fake gait's phase holds still, so the stop's next Footstep never comes: the carry holds
		-- the run speed along the last move until stopStepsSeconds. Without Locomotion.stopGait the
		-- carry would fall over stopStepsSeconds instead (about 9.3 after 30 frames).
		local rig = load({ stopGait = 0 })
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		for _ = 1, 30 do
			rig.frame(Vector3.zero)
		end
		expect(rig.humanoid.WalkSpeed).toBe(ChoreoData.locomotion.runSpeed)
		expect(rig.humanoid.MoveDirection.Z).toBeCloseTo(FORWARD.Z, 1e-6)
		expect(rig.humanoid.MoveDirection.X).toBeCloseTo(0, 1e-6)
	end)

	it("slows the Humanoid as the gait walks on to the planted foot, never under stopEndSpeed", function()
		-- 0.02 of a cycle a frame: the first carry frame keeps the run speed (16) with 0.7 of a cycle
		-- to go; on carry frame k, (0.7 - 0.02 (k - 1)) is left and the speed is 16 x that / 0.7.
		local rig = load({ stopGait = 0.02 })
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		local run = ChoreoData.locomotion.runSpeed
		local seen: { [number]: number } = {}
		for frame = 1, 30 do
			rig.frame(Vector3.zero)
			seen[frame] = rig.humanoid.WalkSpeed
			expect(rig.humanoid.MoveDirection.Z).toBeCloseTo(FORWARD.Z, 1e-6)
		end
		expect(seen[1]).toBeCloseTo(run, 1e-6)
		expect(seen[15]).toBeCloseTo(run * (0.7 - 0.02 * 14) / 0.7, 1e-6)
		expect(seen[30]).toBeCloseTo(ChoreoData.locomotion.stopEndSpeed, 1e-6)
	end)

	it("writes WalkSpeed once a frame at most and AutoRotate only when the lock changes", function()
		-- Each write fires the Humanoid's Changed handlers, and a client WalkSpeed write replicates.
		local rig = load({ stopGait = 0.02 })
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		-- Walking: one WalkSpeed write and one AutoRotate write in all (the first frame).
		expect(writesOf(rig, "WalkSpeed", 1)).toEqual({ ChoreoData.locomotion.runSpeed })
		expect(writesOf(rig, "AutoRotate", 1)).toEqual({ true })
		local most, autoRotate, frames = 0, 0, 0
		repeat
			local from = #rig.writes + 1
			rig.frame(Vector3.zero)
			frames += 1
			most = math.max(most, #writesOf(rig, "WalkSpeed", from))
			autoRotate += #writesOf(rig, "AutoRotate", from)
		until rig.humanoid.MoveDirection.Magnitude == 0 or frames > 200
		expect(most).toBe(1)
		expect(autoRotate).toBe(0)
		-- The carry is over: the Humanoid has its own speed back, written once.
		expect(rig.humanoid.WalkSpeed).toBe(ChoreoData.locomotion.runSpeed)
		local from = #rig.writes + 1
		rig.frame(Vector3.zero)
		rig.frame(FORWARD)
		rig.frame(FORWARD)
		expect(writesOf(rig, "WalkSpeed", from)).toEqual({})
		-- A steady carry (the gait holding still) writes nothing after its first frame.
		local steady = load({ stopGait = 0 })
		for _ = 1, 10 do
			steady.frame(FORWARD)
		end
		local after = #steady.writes + 1
		for _ = 1, 30 do
			steady.frame(Vector3.zero)
		end
		expect(writesOf(steady, "WalkSpeed", after)).toEqual({})
		expect(writesOf(steady, "AutoRotate", after)).toEqual({})
		-- A locked state flips AutoRotate once each way.
		local before = #steady.writes + 1
		steady.controller.dodge()
		for _ = 1, 40 do
			steady.frame(Vector3.zero)
		end
		expect(writesOf(steady, "AutoRotate", before)).toEqual({ false, true })
	end)

	it("hands the Humanoid back its own speed once the carry ends", function()
		local rig = load()
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		local frames = math.ceil(ChoreoData.locomotion.stopStepsSeconds / FRAME) + 2
		for _ = 1, frames do
			rig.frame(Vector3.zero)
		end
		expect(rig.humanoid.MoveDirection.Magnitude).toBe(0)
		expect(rig.humanoid.WalkSpeed).toBe(ChoreoData.locomotion.runSpeed)
	end)
end)

-- The fake Impact's calls named `name`, in order.
local function impactCalls(rig: Rig, name: string): { { any } }
	local calls = {}
	for _, entry in rig.log do
		if entry.kind == "impact" and entry.name == name then
			table.insert(calls, entry.args)
		end
	end
	return calls
end

local function sends(rig: Rig, name: string): number
	local count = 0
	for _, entry in rig.sent do
		if entry.name == name then
			count += 1
		end
	end
	return count
end

-- The index in rig.log of the first entry of `kind` named `name`, or nil.
local function firstIndex(rig: Rig, kind: string, name: string): number?
	for index, entry in rig.log do
		if entry.kind == kind and entry.name == name then
			return index
		end
	end
	return nil
end

describe("CharacterController's impact director calls", function()
	it("a predicted guard raise sounds once, before its GuardRequest; a release or a refused raise does not", function()
		local rig = load({ impact = true })
		rig.frame(Vector3.zero)
		rig.controller.setGuard(true)
		local raises = impactCalls(rig, "guardRaise")
		expect(#raises).toBe(1)
		expect(raises[1][1]).toBe(rig.model)
		expect(raises[1][2]).toBe(true)
		local raiseAt = firstIndex(rig, "impact", "guardRaise") :: number
		local requestAt = firstIndex(rig, "send", "GuardRequest") :: number
		expect(raiseAt < requestAt).toBe(true)
		for _ = 1, 30 do
			rig.frame(Vector3.zero)
		end
		rig.controller.setGuard(false)
		expect(#impactCalls(rig, "guardRaise")).toBe(1)
		-- A raise the controller refuses (mid-dodge) predicts nothing and sounds nothing.
		for _ = 1, 30 do
			rig.frame(Vector3.zero)
		end
		rig.controller.dodge()
		rig.controller.setGuard(true)
		expect(rig.controller.state()).toBe("Dodge")
		expect(#impactCalls(rig, "guardRaise")).toBe(1)
	end)

	it("a local dodge out of the two-step stop plays one Dodge cue and sends one DodgeRequest", function()
		local rig = load({ impact = true, stopGait = 0 })
		for _ = 1, 10 do
			rig.frame(FORWARD)
		end
		rig.frame(Vector3.zero)
		rig.frame(Vector3.zero)
		rig.controller.dodge()
		local dodges = impactCalls(rig, "dodge")
		expect(#dodges).toBe(1)
		expect(dodges[1][1]).toBe(rig.model)
		expect(dodges[1][2]).toBe(true)
		expect(sends(rig, "DodgeRequest")).toBe(1)
		-- A second press inside the cooldown does neither.
		rig.frame(Vector3.zero)
		rig.controller.dodge()
		expect(#impactCalls(rig, "dodge")).toBe(1)
		expect(sends(rig, "DodgeRequest")).toBe(1)
	end)

	it("an Art release hands the director the clip and its freeze time, once, with the ArtRequest", function()
		local Combat = Harness.load("src/shared/data/combat")
		local rig = load({ impact = true })
		rig.frame(Vector3.zero)
		rig.controller.beginArt(1)
		expect(rig.controller.state()).toBe("Holding")
		local held = 0
		for _ = 1, 12 do
			rig.frame(Vector3.zero)
			held += FRAME
		end
		expect(held < Combat.activationCancelTime).toBe(true)
		rig.controller.releaseArt(1, held)
		expect(rig.controller.state()).toBe("Art")
		local releases = impactCalls(rig, "release")
		expect(#releases).toBe(1)
		local art = rig.controller.slots()[1]
		expect(releases[1][1]).toBe(rig.model)
		expect(releases[1][2]).toBe(art.clip)
		-- No ActivationHold froze the clip (the stub animator fires no events): the freeze is the
		-- whole time the key was down, and the clip waits that long again.
		expect(releases[1][3]).toBeCloseTo(held, 1e-9)
		expect(releases[1][4]).toBeCloseTo(held, 1e-9)
		expect(sends(rig, "ArtRequest")).toBe(1)
		expect(#impactCalls(rig, "cancelActivation")).toBe(0)
	end)

	it("every way a hold ends without a launch cancels the activation once", function()
		-- Let go past the cancel time.
		local Combat = Harness.load("src/shared/data/combat")
		local rig = load({ impact = true })
		rig.frame(Vector3.zero)
		rig.controller.beginArt(1)
		rig.controller.releaseArt(1, Combat.activationCancelTime + 0.05)
		expect(rig.controller.state()).toBe("Idle")
		local cancels = impactCalls(rig, "cancelActivation")
		expect(#cancels).toBe(1)
		expect(cancels[1][1]).toBe(rig.model)
		expect(#impactCalls(rig, "release")).toBe(0)
		expect(sends(rig, "ArtRequest")).toBe(0)
		-- The hold timed out (InputController's cancel).
		rig.frame(Vector3.zero)
		rig.controller.beginArt(1)
		rig.controller.cancelArt(1)
		expect(#impactCalls(rig, "cancelActivation")).toBe(2)
		-- A dodge out of the hold.
		rig.frame(Vector3.zero)
		rig.controller.beginArt(1)
		rig.controller.dodge()
		expect(rig.controller.state()).toBe("Dodge")
		expect(#impactCalls(rig, "cancelActivation")).toBe(3)
		-- Nothing held: a cancel is a no-op.
		rig.controller.cancelArt(1)
		expect(#impactCalls(rig, "cancelActivation")).toBe(3)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Aim (D-112): the body faces a held lock; a swing snaps the rest by at most aim.snapDegrees
-- ------------------------------------------------------------------------------------------

local Combat = Harness.load("src/shared/data/combat")
local AIM = Combat.aim
local ACCEPTANCE = math.deg(math.acos(1 - Combat.facingTolerance)) -- 49.46

-- The root's yaw (degrees, + = left of -Z).
local function yawOf(rig: Rig): number
	local look = rig.root.CFrame.LookVector
	return AimLogic.yawOf(look.X, look.Z)
end

-- A point `distance` studs from the root at `bearing` degrees (+ = left) from its look.
local function pointAt(rig: Rig, bearing: number, distance: number): Vector3
	local direction = CFrame.Angles(0, math.rad(yawOf(rig) + bearing), 0).LookVector
	return rig.root.Position + direction * distance
end

-- Degrees (+ = left) from the root's look to a point.
local function bearingOf(rig: Rig, point: Vector3): number
	local look = rig.root.CFrame.LookVector
	local offset = point - rig.root.Position
	return AimLogic.bearing(look.X, look.Z, offset.X, offset.Z)
end

-- The facing of the last request named `name`, as a yaw.
local function sentYaw(rig: Rig, name: string): number?
	for index = #rig.sent, 1, -1 do
		local entry = rig.sent[index]
		if entry.name == name then
			local f = entry.payload.facing
			return AimLogic.yawOf(f[1], f[3])
		end
	end
	return nil
end

local function wrapped(degrees: number): number
	return (degrees + 180) % 360 - 180
end

local STILL = Vector3.zero

-- Frames enough for a snap's whip (aim.snapTurnSeconds) to finish showing on the body.
local function settle(rig: Rig)
	for _ = 1, math.ceil(AIM.snapTurnSeconds / FRAME) + 1 do
		rig.frame(STILL)
	end
end

describe("CharacterController aim: the body faces a held lock (D-112)", function()
	it("a body walked away from the target turns back to it at lockTurnRate once it is locked", function()
		local rig = load()
		-- Backing off with S: AutoRotate turns the body to the stick, away from where it looked.
		for _ = 1, 10 do
			rig.frame(Vector3.new(0, 0, 1))
		end
		local frames = math.ceil(ChoreoData.locomotion.stopStepsSeconds / FRAME) + 2
		for _ = 1, frames do
			rig.frame(STILL)
		end
		expect(math.abs(wrapped(yawOf(rig)))).toBeCloseTo(180, 1e-6)
		local boar = pointAt(rig, 165, 5) -- the Play-test's 165 degrees
		rig.setLock(boar)
		local before = #rig.writes + 1
		local turned = 0
		local previous = yawOf(rig)
		for _ = 1, 30 do
			rig.frame(STILL)
			local now = yawOf(rig)
			local step = math.abs(wrapped(now - previous))
			-- CFrames hold single-precision floats: 1e-4 of slack.
			expect(step <= AIM.lockTurnRate * FRAME + 1e-4).toBe(true)
			if step > 1e-4 then
				turned += 1
			end
			previous = now
		end
		-- 165 degrees at 12 a frame: 14 frames, then it holds on the target.
		expect(turned).toBe(14)
		expect(bearingOf(rig, boar)).toBeCloseTo(0, 1e-4)
		-- AutoRotate went off once, on the first locked frame, and was not written again.
		expect(writesOf(rig, "AutoRotate", before)).toEqual({ false })
		-- The turn is the body's own: Locomotion hears no stick angle to turn in place on.
		expect(rig.locomotionInput().turning).toBe(0)
		-- Unlocked, AutoRotate comes back once.
		rig.setLock(nil)
		local after = #rig.writes + 1
		rig.frame(STILL)
		rig.frame(STILL)
		expect(writesOf(rig, "AutoRotate", after)).toEqual({ true })
	end)

	it("strafes around the lock at walk speed, still facing it", function()
		local rig = load()
		rig.frame(STILL)
		local boar = pointAt(rig, 0, 6)
		rig.setLock(boar)
		for _ = 1, 30 do
			rig.frame(Vector3.new(1, 0, 0))
			expect(math.abs(bearingOf(rig, boar)) < 3).toBe(true)
			expect(rig.humanoid.AutoRotate).toBe(false)
			expect(rig.humanoid.WalkSpeed).toBe(ChoreoData.locomotion.walkSpeed)
			expect(rig.locomotionInput().turning).toBe(0)
		end
		-- The strafe moved the body sideways; the walk set shows it (D-054).
		expect(rig.humanoid.MoveDirection.X).toBeCloseTo(1, 1e-6)
	end)

	it("sprinting hands the facing back to the stick; letting go of sprint faces the lock again", function()
		local rig = load()
		rig.frame(STILL)
		local boar = pointAt(rig, 0, 8)
		rig.setLock(boar)
		rig.frame(STILL)
		expect(rig.humanoid.AutoRotate).toBe(false)
		rig.controller.setSprinting(true)
		-- Sprint held while standing still is not a sprint: the body keeps facing the lock.
		rig.frame(STILL)
		expect(rig.humanoid.AutoRotate).toBe(false)
		for _ = 1, 10 do
			rig.frame(Vector3.new(1, 0, 0))
		end
		expect(rig.humanoid.AutoRotate).toBe(true)
		expect(rig.humanoid.WalkSpeed).toBe(ChoreoData.locomotion.sprintSpeed)
		expect(math.abs(bearingOf(rig, boar)) > 45).toBe(true) -- the body follows the stick
		rig.controller.setSprinting(false)
		for _ = 1, 15 do
			rig.frame(Vector3.new(1, 0, 0))
		end
		expect(rig.humanoid.AutoRotate).toBe(false)
		expect(math.abs(bearingOf(rig, boar)) < 3).toBe(true)
	end)

	it("a raised guard and the held Art stance turn to the lock; a dodge or a swing does not", function()
		local rig = load()
		rig.frame(STILL)
		rig.setLock(pointAt(rig, 90, 5))
		rig.controller.setGuard(true)
		for _ = 1, 10 do
			rig.frame(STILL)
		end
		expect(rig.controller.state()).toBe("Guard")
		-- The server's guard cone follows the replicated root, so the guard now covers the target.
		expect(math.abs(yawOf(rig) - 90) < 1e-4).toBe(true)
		rig.controller.setGuard(false)

		local held = load()
		held.frame(STILL)
		held.controller.beginArt(1)
		expect(held.controller.state()).toBe("Holding")
		held.setLock(pointAt(held, -60, 5))
		for _ = 1, 10 do
			held.frame(STILL)
		end
		expect(math.abs(yawOf(held) + 60) < 1e-4).toBe(true)

		local dodging = load()
		for _ = 1, 40 do
			dodging.frame(STILL)
		end
		dodging.setLock(pointAt(dodging, 120, 5))
		dodging.controller.dodge()
		local start = yawOf(dodging)
		for _ = 1, 5 do
			dodging.frame(STILL)
		end
		expect(dodging.controller.state()).toBe("Dodge")
		expect(yawOf(dodging)).toBeCloseTo(start, 1e-9)
	end)
end)

describe("CharacterController aim: a swing turns the rest of the way, at most aim.snapDegrees (D-112)", function()
	-- A rig that has stood still long enough for its basic swing to be ready and the lag window to
	-- hold one yaw.
	local function standing(): Rig
		local rig = load()
		for _ = 1, 30 do
			rig.frame(STILL)
		end
		return rig
	end

	it("a basic swing with the lock 30 degrees off faces the target and sends that facing", function()
		local rig = standing()
		local boar = pointAt(rig, 30, 5)
		rig.setLock(boar) -- no frame in between: the body has not turned yet
		rig.controller.basicAttack()
		expect(rig.controller.state()).toBe("Basic")
		expect(sentYaw(rig, "BasicAttackRequest")).toBeCloseTo(30, 1e-4)
		settle(rig)
		expect(bearingOf(rig, boar)).toBeCloseTo(0, 1e-4)
	end)

	it("with the lock 120 degrees off the swing turns 40 and no more", function()
		local rig = standing()
		rig.setLock(pointAt(rig, 120, 5))
		rig.controller.basicAttack()
		settle(rig)
		expect(yawOf(rig)).toBeCloseTo(AIM.snapDegrees, 1e-4)
		expect(sentYaw(rig, "BasicAttackRequest")).toBeCloseTo(AIM.snapDegrees, 1e-4)
		local right = standing()
		right.setLock(pointAt(right, -165, 5))
		right.controller.basicAttack()
		expect(sentYaw(right, "BasicAttackRequest")).toBeCloseTo(-AIM.snapDegrees, 1e-4)
	end)

	it(
		"mid-turn, the swing turns only as far as the server can still accept from where it last saw the body",
		function()
			local rig = standing()
			rig.setLock(pointAt(rig, 120, 5))
			for _ = 1, 3 do
				rig.frame(STILL) -- the lock turn: 36 degrees inside the lag window
			end
			expect(yawOf(rig)).toBeCloseTo(36, 1e-4)
			rig.controller.basicAttack()
			-- 13 more: the facing sits snap + margin (49) from the yaw the window began with, inside 49.46.
			local facing = sentYaw(rig, "BasicAttackRequest") :: number
			expect(facing).toBeCloseTo(AIM.snapDegrees + AIM.replicationMarginDegrees, 1e-4)
			expect(facing <= ACCEPTANCE).toBe(true)
		end
	)

	it("a swing deep in the lock's acquisition turn faces back just enough for the server to accept it", function()
		local rig = standing()
		rig.setLock(pointAt(rig, 165, 5))
		for _ = 1, 7 do
			rig.frame(STILL) -- 84 degrees round in 7 frames, all inside the lag window
		end
		expect(yawOf(rig)).toBeCloseTo(84, 1e-4)
		rig.controller.basicAttack()
		-- No snap: the body already left the server's acceptance of where the window began.
		expect(yawOf(rig)).toBeCloseTo(84, 1e-4)
		-- The request faces 49 from that yaw, not 84: it comes out instead of being refused.
		local facing = sentYaw(rig, "BasicAttackRequest") :: number
		expect(facing).toBeCloseTo(AIM.snapDegrees + AIM.replicationMarginDegrees, 1e-4)
		expect(facing <= ACCEPTANCE).toBe(true)
		-- Once the turn has settled for a lag window, the request faces where the body does.
		local settled = standing()
		settled.setLock(pointAt(settled, 165, 5))
		for _ = 1, 30 do
			settled.frame(STILL)
		end
		settled.controller.basicAttack()
		expect(sentYaw(settled, "BasicAttackRequest")).toBeCloseTo(yawOf(settled), 1e-4)
		expect(math.abs(wrapped(yawOf(settled) - 165)) < 1e-3).toBe(true)
	end)

	it("an Art release snaps the same way and its ArtRequest carries the facing", function()
		local rig = standing()
		rig.controller.beginArt(1)
		for _ = 1, 12 do
			rig.frame(STILL)
		end
		local boar = pointAt(rig, -25, 5)
		rig.setLock(boar)
		rig.controller.releaseArt(1, 12 * FRAME)
		expect(rig.controller.state()).toBe("Art")
		expect(sentYaw(rig, "ArtRequest")).toBeCloseTo(-25, 1e-4)
		settle(rig)
		expect(bearingOf(rig, boar)).toBeCloseTo(0, 1e-4)
	end)

	it("with no lock the soft assist aims at the best enemy in the cone, by at most the snap", function()
		local rig = standing()
		rig.setEnemies({ { id = 4, position = pointAt(rig, 30, 5) } })
		rig.controller.basicAttack()
		expect(sentYaw(rig, "BasicAttackRequest")).toBeCloseTo(30, 1e-4)

		-- Behind the cone (the Play-test's 165): no unanimated half turn; F is for that.
		local behind = standing()
		behind.setEnemies({ { id = 4, position = pointAt(behind, 165, 5) } })
		behind.controller.basicAttack()
		expect(sentYaw(behind, "BasicAttackRequest")).toBeCloseTo(0, 1e-9)
		expect(yawOf(behind)).toBeCloseTo(0, 1e-9)

		-- Past the assist range: nothing to aim at.
		local far = standing()
		far.setEnemies({ { id = 4, position = pointAt(far, 30, AIM.assistRange + 1) } })
		far.controller.basicAttack()
		expect(sentYaw(far, "BasicAttackRequest")).toBeCloseTo(0, 1e-9)

		-- The nearer of two, angle priced in: 5 studs at 40 beats 9 studs at 10.
		local two = standing()
		two.setEnemies({
			{ id = 1, position = pointAt(two, -10, 9) },
			{ id = 2, position = pointAt(two, 40, 5) },
		})
		two.controller.basicAttack()
		expect(sentYaw(two, "BasicAttackRequest")).toBeCloseTo(40, 1e-4)
	end)

	it(
		"with the display asleep, a turn made on Heartbeat that has settled for a lag window sends the body's own look",
		function()
			-- Studio with its display asleep runs Heartbeat 60 times a second and RenderStepped never
			-- (measured 2026-10-23), so the render step records no yaw. The dev aim hook's "face" turns
			-- the root on Heartbeat at the lock turn's rate, waits, then swings: the server has long seen
			-- that root, so the request must face where the body does.
			local rig = standing()
			local turned = 0
			while turned < 150 do
				local step = math.min(AIM.lockTurnRate * FRAME, 150 - turned)
				local frame = rig.root.CFrame
				rig.root.CFrame = CFrame.new(frame.Position) * CFrame.Angles(0, math.rad(step), 0) * frame.Rotation
				turned += step
				rig.heartbeat()
			end
			for _ = 1, math.ceil(2 * Combat.lagAllowance / FRAME) do
				rig.heartbeat()
			end
			expect(yawOf(rig)).toBeCloseTo(150, 1e-3)
			rig.controller.basicAttack()
			expect(rig.controller.state()).toBe("Basic")
			expect(sentYaw(rig, "BasicAttackRequest")).toBeCloseTo(150, 1e-3)
		end
	)

	it("a held lock wins over the assist", function()
		local rig = standing()
		rig.setEnemies({ { id = 4, position = pointAt(rig, 30, 4) } })
		rig.setLock(pointAt(rig, -20, 6))
		rig.controller.basicAttack()
		expect(sentYaw(rig, "BasicAttackRequest")).toBeCloseTo(-20, 1e-4)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The snap's whip (item 102): the request faces the whole snap at once; the body shows it over
-- aim.snapTurnSeconds on aim.snapTurnEasing instead of in one frame
-- ------------------------------------------------------------------------------------------

local Easing = Harness.load("src/shared/util/Easing")

-- Frames in which a whip of aim.snapTurnSeconds turns the body, `scale` the capture's time scale.
local function whipFrames(scale: number): number
	return math.ceil(AIM.snapTurnSeconds / scale / FRAME - 1e-9)
end

describe("CharacterController aim: the snap shows as a whip, not a pop (item 102)", function()
	local function standing(options: Options?): Rig
		local rig = load(options)
		for _ = 1, 30 do
			rig.frame(STILL)
		end
		return rig
	end

	-- Runs frames until the whip is over; returns the yaw step of every frame.
	local function whip(rig: Rig, frames: number): { number }
		local steps = {}
		local previous = yawOf(rig)
		for _ = 1, frames do
			rig.frame(STILL)
			local now = yawOf(rig)
			table.insert(steps, wrapped(now - previous))
			previous = now
		end
		return steps
	end

	it("sends the whole snap at once; the body whips round over a few frames, never most of it in one", function()
		-- The Studio case: unlocked, the boar 35 degrees off at 4 studs, one basic swing.
		local rig = standing()
		rig.setEnemies({ { id = 4, position = pointAt(rig, 35, 4) } })
		rig.controller.basicAttack()
		expect(rig.controller.state()).toBe("Basic")
		-- The server sweeps where the request faces (D-113): the whole snap, now.
		expect(sentYaw(rig, "BasicAttackRequest")).toBeCloseTo(35, 1e-4)
		-- The body shows none of it before the next frame...
		expect(yawOf(rig)).toBeCloseTo(0, 1e-4)
		local steps = whip(rig, whipFrames(1) + 3)
		-- ...then turns on every frame of the whip, never back, and holds once it is over.
		local turning, biggest = 0, 0
		for index, step in steps do
			expect(step >= -1e-4).toBe(true)
			if step > 1e-4 then
				turning += 1
				expect(index <= whipFrames(1)).toBe(true)
			end
			biggest = math.max(biggest, step)
		end
		expect(turning).toBe(whipFrames(1))
		expect(turning >= 3).toBe(true)
		expect(biggest < 35 / 2).toBe(true)
		-- The first frame shows the curve one frame in.
		expect(steps[1]).toBeCloseTo(35 * Easing.evaluate(AIM.snapTurnEasing, FRAME / AIM.snapTurnSeconds), 1e-3)
		expect(yawOf(rig)).toBeCloseTo(35, 1e-3)
	end)

	it("with the display asleep the whip still ends on time, on Heartbeat", function()
		-- Studio with its display asleep: Heartbeat 60 a second, RenderStepped never (D-117).
		local rig = standing()
		rig.setEnemies({ { id = 4, position = pointAt(rig, 35, 4) } })
		rig.controller.basicAttack()
		for _ = 1, whipFrames(1) do
			rig.heartbeat()
		end
		expect(yawOf(rig)).toBeCloseTo(35, 1e-3)
	end)

	it("the clip's root motion carries the body along the facing the request carried, mid-whip too", function()
		local rig = standing({ animator = true })
		rig.setEnemies({ { id = 4, position = pointAt(rig, 35, 4) } })
		local start = rig.root.Position
		rig.controller.basicAttack()
		rig.setRootMotion(Vector3.new(0, 0, -0.1)) -- a tenth of a stud forward a frame
		whip(rig, whipFrames(1))
		local moved = rig.root.Position - start
		expect(moved.Magnitude).toBeCloseTo(0.1 * whipFrames(1), 1e-3)
		expect(AimLogic.yawOf(moved.X, moved.Z)).toBeCloseTo(35, 1e-3)
	end)

	it("a request mid-whip faces from where the last one left the body, and the whip carries on", function()
		local rig = standing()
		local boar = pointAt(rig, 35, 5)
		rig.setLock(boar)
		rig.controller.basicAttack()
		rig.frame(STILL)
		local first = yawOf(rig)
		expect(first > 1 and first < 35 / 2).toBe(true)
		-- An Art may start from a basic swing: its stance waits for the whip, not the lock turn.
		rig.controller.beginArt(1)
		expect(rig.controller.state()).toBe("Holding")
		rig.frame(STILL)
		local before = yawOf(rig)
		rig.controller.releaseArt(1, FRAME)
		expect(sentYaw(rig, "ArtRequest")).toBeCloseTo(35, 1e-3)
		-- No pop at the release: the rest of the turn keeps whipping.
		expect(yawOf(rig)).toBeCloseTo(before, 1e-4)
		local steps = whip(rig, whipFrames(1) + 3)
		for _, step in steps do
			expect(step >= -1e-4 and step <= first + 1e-3).toBe(true)
		end
		expect(bearingOf(rig, boar)).toBeCloseTo(0, 1e-3)
	end)

	it("a swing refused mid-whip ends on the lock without overshooting it", function()
		local rig = standing()
		local boar = pointAt(rig, 35, 5)
		rig.setLock(boar)
		rig.controller.basicAttack()
		rig.frame(STILL)
		rig.reject("BasicAttack")
		expect(rig.controller.state()).toBe("Idle")
		local most = yawOf(rig)
		for _ = 1, 20 do
			rig.frame(STILL)
			most = math.max(most, yawOf(rig))
		end
		expect(most <= 35 + 1e-3).toBe(true)
		expect(bearingOf(rig, boar)).toBeCloseTo(0, 1e-3)
	end)

	it("a dodge mid-whip steps relative to the facing the swing carried", function()
		local rig = standing()
		rig.setLock(pointAt(rig, 35, 5))
		rig.controller.basicAttack()
		rig.frame(STILL)
		rig.controller.dodge() -- no stick: back
		local direction = lastDodge(rig) :: Vector3
		expect(direction).never.toBeNil()
		expect(AimLogic.yawOf(-direction.X, -direction.Z)).toBeCloseTo(35, 1e-3)
	end)

	it("a respawn mid-whip drops the rest of the turn", function()
		local rig = standing()
		rig.setLock(pointAt(rig, 35, 5))
		rig.controller.basicAttack()
		rig.frame(STILL)
		local shown = yawOf(rig)
		rig.setLock(nil)
		rig.respawn()
		for _ = 1, whipFrames(1) + 3 do
			rig.frame(STILL)
		end
		expect(yawOf(rig)).toBeCloseTo(shown, 1e-4)
	end)

	it("hands DevAim the facing the last request carried", function()
		local rig = standing()
		expect(rig.controller.lastFacing()).toBeNil()
		rig.setEnemies({ { id = 4, position = pointAt(rig, 35, 4) } })
		rig.controller.basicAttack()
		local facing = rig.controller.lastFacing()
		expect(facing).never.toBeNil()
		expect(AimLogic.yawOf(facing[1], facing[3])).toBeCloseTo(35, 1e-4)
		expect(sentYaw(rig, "BasicAttackRequest")).toBeCloseTo(35, 1e-4)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Capture slow motion (dev.luau timeScale): the local body moves on the capture's clock
-- ------------------------------------------------------------------------------------------

describe("CharacterController in a slowed capture", function()
	local RUN = ChoreoData.locomotion.runSpeed

	local function last(list: { number }): number?
		return list[#list]
	end

	it("walks the body at the capture's scale, so the slowed walk's feet keep their ground", function()
		local rig = load({ capture = true })
		rig.frame(STILL)
		expect(rig.controller.setCaptureTimeScale(0.25)).toBe(true)
		local start = rig.root.Position
		for _ = 1, 30 do
			rig.frame(FORWARD)
			expect(rig.humanoid.WalkSpeed).toBeCloseTo(RUN * 0.25, 1e-9)
		end
		expect((rig.root.Position - start).Magnitude).toBeCloseTo(30 * FRAME * RUN * 0.25, 1e-6)
		-- Locomotion hears the root's own speed: it paces the slowed clips from it (their clock
		-- runs at the same scale), so the walk plants its feet.
		expect(rig.locomotionInput().speed).toBeCloseTo(RUN * 0.25, 1e-6)
		-- ... and the clock it moves on, so the blend reads that speed at 1x: the run, not a walk.
		expect(rig.locomotionInput().clockScale).toBe(0.25)
		expect(rig.controller.setCaptureTimeScale(1)).toBe(true)
		rig.frame(FORWARD)
		expect(rig.humanoid.WalkSpeed).toBe(RUN)
		expect(rig.locomotionInput().clockScale).toBe(1)
	end)

	it("outside a capture place, or at a scale the capture does not offer, nothing slows", function()
		local live = load()
		live.frame(STILL)
		expect(live.controller.setCaptureTimeScale(0.25)).toBe(false)
		for _ = 1, 5 do
			live.frame(FORWARD)
		end
		expect(live.humanoid.WalkSpeed).toBe(RUN)
		local capture = load({ capture = true })
		capture.frame(STILL)
		for _, bad in { 0.3, 2, 0, -1, 0 / 0 } do
			expect(capture.controller.setCaptureTimeScale(bad)).toBe(false)
		end
		for _ = 1, 5 do
			capture.frame(FORWARD)
		end
		expect(capture.humanoid.WalkSpeed).toBe(RUN)
	end)

	it("a capture place played live (the published Playground, not Studio) never slows the body", function()
		-- STUDIO_TASKS 19 publishes places/Playground.rbxl, whose Workspace carries DevCapture, as
		-- the start place: Capture.client runs there too, but the body is a dev-only path.
		local live = load({ capture = true, studio = false, animator = true })
		live.frame(STILL)
		local scales = #live.timeScales
		expect(live.controller.setCaptureTimeScale(0.25)).toBe(false)
		for _ = 1, 5 do
			live.frame(FORWARD)
		end
		expect(live.humanoid.WalkSpeed).toBe(RUN)
		-- Refused, it leaves the animator alone too (Capture.client then slows the clips itself).
		expect(#live.timeScales).toBe(scales)
	end)

	it("turns to the lock and whips a snap on the capture's clock; the request still faces at once", function()
		local rig = load({ capture = true })
		for _ = 1, 30 do
			rig.frame(STILL)
		end
		expect(rig.controller.setCaptureTimeScale(0.25)).toBe(true)
		rig.setLock(pointAt(rig, 120, 5))
		rig.frame(STILL)
		expect(yawOf(rig)).toBeCloseTo(AIM.lockTurnRate * FRAME * 0.25, 1e-4)

		local swing = load({ capture = true })
		for _ = 1, 30 do
			swing.frame(STILL)
		end
		swing.controller.setCaptureTimeScale(0.25)
		swing.setEnemies({ { id = 4, position = pointAt(swing, 35, 4) } })
		swing.controller.basicAttack()
		expect(sentYaw(swing, "BasicAttackRequest")).toBeCloseTo(35, 1e-4)
		local turning = 0
		local previous = yawOf(swing)
		for _ = 1, whipFrames(0.25) + 3 do
			swing.frame(STILL)
			if yawOf(swing) - previous > 1e-4 then
				turning += 1
			end
			previous = yawOf(swing)
		end
		expect(turning).toBe(whipFrames(0.25))
		expect(yawOf(swing)).toBeCloseTo(35, 1e-3)
	end)

	it("runs the two-step stop on the capture's clock, never faster than the slowed body", function()
		local function carry(scale: number): (number, number)
			local rig = load({ capture = true })
			rig.frame(STILL)
			rig.controller.setCaptureTimeScale(scale)
			for _ = 1, 20 do
				rig.frame(FORWARD)
			end
			local frames, fastest = 0, 0
			for _ = 1, 400 do
				rig.frame(STILL)
				if rig.humanoid.MoveDirection.Magnitude > 0 then
					frames += 1
					fastest = math.max(fastest, rig.humanoid.WalkSpeed)
				end
			end
			return frames, fastest
		end
		local full, fullFastest = carry(1)
		local slow, slowFastest = carry(0.25)
		expect(full > 0).toBe(true)
		expect(fullFastest <= RUN + 1e-9).toBe(true)
		expect(slow >= 4 * full - 4).toBe(true)
		expect(slow <= 4 * full + 4).toBe(true)
		expect(slowFastest <= RUN * 0.25 + 1e-9).toBe(true)
	end)

	it("keeps a frozen Art stance frozen, and a hold let go returns to the capture's scale", function()
		local rig = load({ capture = true, animator = true })
		rig.frame(STILL)
		expect(rig.controller.setCaptureTimeScale(0.25)).toBe(true)
		expect(last(rig.timeScales)).toBe(0.25)
		rig.controller.beginArt(1)
		rig.controller.freezeHold()
		expect(last(rig.timeScales)).toBe(0)
		-- The capture panel cycles (or re-applies) the scale while the stance glows.
		rig.controller.setCaptureTimeScale(0.5)
		expect(last(rig.timeScales)).toBe(0)
		rig.controller.cancelArt(1)
		expect(last(rig.timeScales)).toBe(0.5)
		-- A respawned body comes back on the capture's clock.
		rig.respawn()
		expect(last(rig.timeScales)).toBe(0.5)
	end)
end)

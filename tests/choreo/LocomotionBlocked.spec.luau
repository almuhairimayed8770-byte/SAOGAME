--!strict
--[[
	A body held off its stick (D-144, data/choreo.luau locomotion.stride.blocked): walking into an
	enemy or a wall, or slid along its flank. The real Locomotion and Choreo animator on a Lune rig
	at 60 Hz (the engine's frame), the root moved by its velocity. The velocity reaches Locomotion
	in the state (Locomotion.humanoidTracker's rigs) or on the root part (the local
	CharacterController gives none, and Locomotion reads the root's own).

	1. Blocked: a velocity off a settled stick blocks the body. It stands while the velocity jostles
	   about nothing, and its gait follows a real slide's direction, paced by the root's speed
	   along it. It holds until the stick lets go, the body leaves the ground, or the velocity runs
	   along the stick at a whole walk; it waits for the stick to settle; it needs the velocity to
	   be the reading the speed came from.
	2. Open ground, frame for frame: with the root's velocity known, a start, a stop, a strafe
	   under a held facing (D-129), turns and reversals (the velocity a frame behind the stick, or
	   easing round), camera pans, a sprint, a jump and a slowed capture (D-127) give exactly what
	   they give with none (as before D-144): every weight, clip clock and speed, the shared phase
	   and pace, and the state's output.
	Tests/choreo/Stride.spec.luau measures the feet of the blocked body on the posed body.
	The runner shares one module cache across spec files, so this file sorts after
	Choreo.spec.luau: that spec must be the first to load Choreo, under its own RunService stubs.
]]

local function fakeSignal()
	local signal = {}
	function signal:Connect()
		return { Disconnect = function() end }
	end
	return signal
end
Harness.stubService("RunService", {
	RenderStepped = fakeSignal(),
	Heartbeat = fakeSignal(),
	PreSimulation = fakeSignal(),
	-- Choreo's rig step (bound before every reader of a pose, D-211): the spec steps the rigs itself.
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
})

local Choreo = Harness.load("src/client/choreo/Choreo")
Choreo.configure({
	now = function()
		return 0
	end,
	cameraPosition = function()
		return Vector3.zero
	end,
})
local Locomotion = Harness.load("src/client/choreo/Locomotion")
local LocomotionState = Harness.load("src/client/choreo/LocomotionState")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Rigs = Harness.load("src/shared/data/rigs")

local FRAME = 1 / 60
local Config = ChoreoData.locomotion
local Stride = Config.stride
-- Read through `any` so a build without the table fails each test, not the whole file.
local Blocked: any = (Stride :: any).blocked

local FORWARD = Vector3.new(0, 0, -1)
local RIGHT = Vector3.new(1, 0, 0)

local function buildRig(): any
	local model = Instance.new("Model")
	model.Name = "PlayerR15"
	model:SetAttribute("Rig", "PlayerR15")
	local parts = {}
	local function part(name: string): any
		local existing = parts[name]
		if existing then
			return existing
		end
		local created = Instance.new("Part")
		created.Name = name
		created.Position = Vector3.zero
		created.Parent = model
		parts[name] = created
		return created
	end
	for _, joint in Rigs.PlayerR15.joints do
		part(joint.part0)
		local motor = Instance.new("Motor6D")
		motor.Name = joint.name
		motor.Parent = part(joint.part1)
	end
	model.PrimaryPart = parts.HumanoidRootPart
	return model
end

-- A frame of a scripted body: the stick (a world direction, zero for none), the root's velocity
-- (world, real studs a second) and the root's facing (degrees of yaw, 0 facing -Z).
type Frame = {
	stick: Vector3,
	velocity: Vector3,
	facing: number?,
	grounded: boolean?,
	sprinting: boolean?,
	drawn: boolean?,
	turning: number?,
	speed: number?, -- the speed the caller gives, when it is not the velocity's (default |velocity|)
}

-- How the velocity reaches Locomotion: in the state, on the root part, or not at all.
type Source = "state" | "root" | "none"

-- Drives a fresh rig through `frames` frames of `script` and returns each frame's record (every
-- weight, clip clock and speed, the shared phase and pace, the state's output) and the driver.
local function drive(
	script: (frame: number) -> Frame,
	frames: number,
	source: Source,
	clockScale: number?,
	each: ((locomotion: any, frame: number) -> ())?
): ({ string }, any, () -> ())
	local model = buildRig()
	local animator: any = Choreo.get(model)
	local locomotion = Locomotion.new(animator, model, { footIK = false }) :: any
	if clockScale ~= nil then
		animator.mixer:setTimeScale(clockScale)
	end
	local root = model.PrimaryPart
	local position = Vector3.zero
	local records = {}
	local names = {}
	for name in locomotion.handles do
		table.insert(names, name)
	end
	table.sort(names)
	for frame = 1, frames do
		local step = script(frame)
		position += step.velocity * FRAME
		root.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(step.facing or 0), 0)
		local horizontal = Vector3.new(step.velocity.X, 0, step.velocity.Z).Magnitude
		local state: any = {
			moveDir = step.stick,
			speed = step.speed or horizontal,
			sprinting = step.sprinting == true,
			grounded = step.grounded ~= false,
			drawn = step.drawn == true,
			turning = step.turning or 0,
			verticalVelocity = step.velocity.Y,
			clockScale = clockScale,
		}
		if source == "state" then
			state.velocity = step.velocity
		elseif source == "root" then
			root.AssemblyLinearVelocity = step.velocity
		end
		local output = locomotion:update(FRAME, state)
		animator:step(FRAME)
		if each ~= nil then
			each(locomotion, frame)
		end
		local parts = {
			("phase %.17g pace %.17g out %s %s %.17g %.17g"):format(
				locomotion.gaitPhase,
				locomotion.gaitPace or -1,
				output.phase,
				tostring(output.oneShot),
				output.oneShotWeight,
				output.lean
			),
		}
		local weightNames = {}
		for name in output.weights do
			table.insert(weightNames, name)
		end
		table.sort(weightNames)
		for _, name in weightNames do
			table.insert(parts, ("%s=%.17g"):format(name, output.weights[name]))
		end
		for _, name in names do
			local handle = locomotion.handles[name]
			table.insert(
				parts,
				("%s w%.17g t%.17g f%.17g c%.17g s%.17g"):format(
					name,
					handle.weight,
					handle.targetWeight or -1,
					handle.fade,
					handle.time,
					handle.speed
				)
			)
		end
		table.insert(records, table.concat(parts, " "))
	end
	return records, locomotion, function()
		locomotion:destroy()
		Choreo.release(model)
	end
end

-- The first frame at which the body differs with its velocity known (in the state, and on the
-- root) from the body with none, or nil.
local function firstDifference(script: (frame: number) -> Frame, frames: number, clockScale: number?): string?
	local without, _, releaseWithout = drive(script, frames, "none", clockScale)
	releaseWithout()
	for _, source: Source in { "state", "root" } do
		local with, _, release = drive(script, frames, source, clockScale)
		release()
		for frame = 1, frames do
			if with[frame] ~= without[frame] then
				return ("%s, frame %d:\n  with    %s\n  without %s"):format(source, frame, with[frame], without[frame])
			end
		end
	end
	return nil
end

local function rotated(direction: Vector3, degrees: number): Vector3
	return CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(direction)
end

-- The yaw (degrees, 0 facing -Z) that faces a horizontal direction.
local function yawOf(direction: Vector3): number
	return math.deg(math.atan2(-direction.X, -direction.Z))
end

-- A body walking into a wall ahead at `speed` until `contact` (frames), then held there with its
-- velocity jostling about nothing (a seeded 0 .. `jostle` studs a second in any direction).
local function intoWall(speed: number, contact: number, jostle: number, seed: number): (frame: number) -> Frame
	local random = Random.new(seed)
	return function(frame: number): Frame
		if frame < contact then
			return { stick = FORWARD, velocity = FORWARD * speed }
		end
		local angle = random:NextNumber() * math.pi * 2
		local size = random:NextNumber() * jostle
		return { stick = FORWARD, velocity = Vector3.new(math.cos(angle), 0, math.sin(angle)) * size }
	end
end

local function gaitShown(locomotion: any): number
	local shown = 0
	for name, handle in locomotion.handles do
		if LocomotionState.gaits()[name] ~= nil then
			shown += handle.weight
		end
	end
	return shown
end

describe("Locomotion: a body held off its stick (D-144)", function()
	it("stands while the velocity jostles about nothing against a wall, at 1x and slowed", function()
		for _, scale in { 1, 0.25 } do
			for _, source: Source in { "state", "root" } do
				for _, drawn in { false, true } do
					local contact = math.floor(60 / scale)
					local script = intoWall(Config.walkSpeed * scale, contact, 0.5 * scale, 7)
					local shown = 0
					local _, locomotion, release = drive(
						function(frame: number): Frame
							local step = script(frame)
							step.drawn = drawn
							return step
						end,
						math.floor(180 / scale),
						source,
						if scale < 1 then scale else nil,
						function(driven: any, frame: number)
							-- From a third of a second (at 1x) after the contact: the weights have settled.
							if frame >= contact + 20 / scale then
								shown = math.max(shown, gaitShown(driven))
							end
						end
					)
					expect(locomotion.blocked).toBe(true)
					expect(shown).toBe(0)
					release()
				end
			end
		end
	end)

	it("walks the way a slide along a flank goes, paced by its speed along it", function()
		for _, source: Source in { "state", "root" } do
			local slide = Vector3.new(0.6, 0, 0.8) * 3 -- right and back, across a stick held ahead
			local _, locomotion, release = drive(function(frame: number): Frame
				if frame < 60 then
					return { stick = FORWARD, velocity = FORWARD * Config.walkSpeed }
				end
				return { stick = FORWARD, velocity = slide }
			end, 150, source)
			expect(locomotion.blocked).toBe(true)
			-- The walks of the slide's direction (back and right of the facing), whole at its speed.
			local direction = LocomotionState.walkWeights(-0.8, 0.6, false)
			for name, handle in locomotion.handles do
				expect(handle.targetWeight or 0).toBeCloseTo(direction[name] or 0, 1e-4)
			end
			expect(locomotion.travelForward).toBeCloseTo(-0.8, 1e-4)
			expect(locomotion.travelRight).toBeCloseTo(0.6, 1e-4)
			-- Paced by the root's whole speed: the slide runs along its own direction.
			expect(locomotion.speed).toBeCloseTo(3, 1e-4)
			release()
		end
	end)

	it("stays blocked until the stick lets go, the body leaves the ground, or it walks free", function()
		local function blockedAfter(tail: (frame: number) -> Frame): boolean
			local _, locomotion, release = drive(function(frame: number): Frame
				if frame < 60 then
					return { stick = FORWARD, velocity = FORWARD * Config.walkSpeed }
				elseif frame < 90 then
					return { stick = FORWARD, velocity = RIGHT * 2 }
				end
				return tail(frame)
			end, 100, "state")
			local blocked = locomotion.blocked == true
			release()
			return blocked
		end
		-- Still pressed against the wall: blocked.
		expect(blockedAfter(function(): Frame
			return { stick = FORWARD, velocity = Vector3.zero }
		end)).toBe(true)
		-- Creeping along the stick below a whole walk: still blocked.
		local whole = LocomotionState.wholeWalkSpeed(1, 0, false)
		expect(blockedAfter(function(): Frame
			return { stick = FORWARD, velocity = FORWARD * (whole * 0.9) }
		end)).toBe(true)
		expect(blockedAfter(function(frame: number): Frame
			return { stick = if frame == 95 then Vector3.zero else FORWARD, velocity = Vector3.zero }
		end)).toBe(false)
		expect(blockedAfter(function(frame: number): Frame
			return { stick = FORWARD, velocity = RIGHT * 2, grounded = frame ~= 95 }
		end)).toBe(false)
		expect(blockedAfter(function(): Frame
			return { stick = FORWARD, velocity = FORWARD * (whole * 1.01) }
		end)).toBe(false)
	end)

	it("waits for the stick to settle before a velocity off it blocks the body", function()
		local settle = math.ceil(Blocked.settleSeconds / FRAME)
		-- The stick turns a right angle at frame 60; the velocity keeps the old way for `lag` frames,
		-- the last of them the last frame driven.
		local function blockedWithLag(lag: number): boolean
			local _, locomotion, release = drive(function(frame: number): Frame
				if frame < 60 then
					return { stick = FORWARD, velocity = FORWARD * Config.walkSpeed }
				end
				return {
					stick = RIGHT,
					velocity = (if frame < 60 + lag then FORWARD else RIGHT) * Config.walkSpeed,
					facing = yawOf(RIGHT),
				}
			end, 59 + lag, "state")
			local blocked = locomotion.blocked == true
			release()
			return blocked
		end
		expect(blockedWithLag(settle - 1)).toBe(false)
		expect(blockedWithLag(settle + 2)).toBe(true)
		-- A stick panning faster than degrees / settleSeconds never settles.
		local pan = Blocked.degrees / Blocked.settleSeconds * 1.5
		local _, locomotion, release = drive(function(frame: number): Frame
			local stick = rotated(FORWARD, pan * frame * FRAME)
			-- The velocity five frames behind the stick: off it by more than `degrees`.
			return { stick = stick, velocity = rotated(stick, -pan * 5 * FRAME - Blocked.degrees) * 8 }
		end, 120, "state")
		expect(locomotion.blocked).toBe(false)
		release()
	end)

	it("needs the velocity to be the reading the speed came from", function()
		for _, source: Source in { "state", "root" } do
			local _, locomotion, release = drive(function(frame: number): Frame
				if frame < 60 then
					return { stick = FORWARD, velocity = FORWARD * Config.walkSpeed }
				end
				return { stick = FORWARD, velocity = RIGHT * 2, speed = 2 + Blocked.matchSpeed * 2 }
			end, 90, source)
			expect(locomotion.blocked).toBe(false)
			release()
		end
		-- A root part whose velocity cannot be read (a Lune test rig) is tried once.
		local _, locomotion, release = drive(function(): Frame
			return { stick = FORWARD, velocity = RIGHT * 2 }
		end, 30, "none")
		expect(locomotion.blocked).toBe(false)
		expect(locomotion.unreadableRoot).toBeTruthy()
		release()
	end)

	it("a humanoid-driven rig's tracker gives the root's velocity", function()
		local humanoid = { MoveDirection = FORWARD, FloorMaterial = Enum.Material.Plastic }
		local root = { AssemblyLinearVelocity = Vector3.new(3, -1, 4), Position = Vector3.zero }
		local character = {
			PrimaryPart = root,
			FindFirstChildOfClass = function()
				return humanoid
			end,
			FindFirstChild = function()
				return root
			end,
			GetAttribute = function()
				return nil
			end,
		}
		local state: any = Locomotion.humanoidTracker(character :: any)(FRAME)
		expect(state.velocity).toBe(root.AssemblyLinearVelocity)
		expect(state.speed).toBeCloseTo(5, 1e-9)
	end)
end)

describe("Locomotion: open ground, frame for frame with the velocity known (D-144)", function()
	-- The root's velocity a frame behind the stick (the engine moves the root after the frame).
	local function lagged(stickAt: (frame: number) -> Vector3, speedAt: (frame: number) -> number): (number) -> Vector3
		return function(frame: number): Vector3
			local before = stickAt(frame - 1)
			if before.Magnitude == 0 then
				return Vector3.zero
			end
			return before.Unit * speedAt(frame - 1)
		end
	end
	local function constant(value: number): (number) -> number
		return function(): number
			return value
		end
	end

	it("starts, sprints and stops", function()
		for _, drawn in { false, true } do
			for _, speed in { Config.walkSpeed, Config.runSpeed, Config.sprintSpeed } do
				local function stickAt(frame: number): Vector3
					return if frame >= 30 and frame < 150 then FORWARD else Vector3.zero
				end
				-- The stop slows over a third of a second, as the two-step stop does.
				local function speedAt(frame: number): number
					return if frame < 150 then speed else math.max(0, speed * (1 - (frame - 150) / 20))
				end
				local function velocityAt(frame: number): Vector3
					if frame >= 150 then
						return FORWARD * speedAt(frame)
					end
					return lagged(stickAt, constant(speed))(frame)
				end
				local problem = firstDifference(function(frame: number): Frame
					return {
						stick = stickAt(frame),
						velocity = velocityAt(frame),
						drawn = drawn,
						sprinting = speed == Config.sprintSpeed,
					}
				end, 200)
				expect(problem).toBeNil()
				-- A body easing up to speed along its stick over a fifth of a second.
				problem = firstDifference(function(frame: number): Frame
					local stick = if frame >= 30 then FORWARD else Vector3.zero
					local eased = math.clamp((frame - 30) / 12, 0, 1) * speed
					return { stick = stick, velocity = FORWARD * eased, drawn = drawn }
				end, 90)
				expect(problem).toBeNil()
			end
		end
	end)

	it("strafes and backs off under a held facing (D-129)", function()
		for _, drawn in { false, true } do
			for _, heading in { 90, -90, 45, -45, 135, 180, -135 } do
				for _, speed in { Config.walkSpeed * 0.5, Config.walkSpeed, Config.runSpeed } do
					local move = rotated(FORWARD, heading)
					local function stickAt(frame: number): Vector3
						-- Swung to the other side half way.
						return if frame < 20 then Vector3.zero elseif frame < 90 then move else rotated(move, 180)
					end
					local problem = firstDifference(function(frame: number): Frame
						return {
							stick = stickAt(frame),
							velocity = lagged(stickAt, constant(speed))(frame),
							facing = 0,
							drawn = drawn,
						}
					end, 150)
					expect(problem).toBeNil()
				end
			end
		end
	end)

	it("turns and reverses, the velocity a frame behind or easing round", function()
		for _, drawn in { false, true } do
			for _, turn in { 45, 90, 135, 180, -90 } do
				local after = rotated(FORWARD, turn)
				local function stickAt(frame: number): Vector3
					return if frame < 60 then FORWARD else after
				end
				-- The body turns to its stick at 720 degrees a second.
				local function facingAt(frame: number): number
					if frame < 60 then
						return 0
					end
					local swung = math.min(math.abs(turn), 720 * (frame - 60) * FRAME)
					return if turn > 0 then swung else -swung
				end
				for _, speed in { Config.walkSpeed, Config.runSpeed } do
					local problem = firstDifference(function(frame: number): Frame
						local facing = facingAt(frame)
						return {
							stick = stickAt(frame),
							velocity = lagged(stickAt, constant(speed))(frame),
							facing = facing,
							turning = turn - facing,
							drawn = drawn,
						}
					end, 120)
					expect(problem).toBeNil()
					-- The velocity easing round over just under settleSeconds (through a stop on a
					-- reversal).
					local ease = math.floor(Blocked.settleSeconds / FRAME) - 1
					problem = firstDifference(function(frame: number): Frame
						local share = math.clamp((frame - 60) / ease, 0, 1)
						local velocity = (FORWARD * (1 - share) + after * share) * speed
						return {
							stick = stickAt(frame),
							velocity = velocity,
							facing = facingAt(frame),
							drawn = drawn,
						}
					end, 120)
					expect(problem).toBeNil()
				end
			end
		end
	end)

	it("follows a camera pan, slow or fast, the velocity a frame or more behind", function()
		for _, rate in { 10, 90, 400 } do
			for _, lag in { 1, 3 } do
				local slowEnough = rate * lag * FRAME < Blocked.degrees
				local fastEnough = rate > Blocked.degrees / Blocked.settleSeconds
				if slowEnough or fastEnough then
					local function stickAt(frame: number): Vector3
						return rotated(FORWARD, rate * frame * FRAME)
					end
					local problem = firstDifference(function(frame: number): Frame
						local behind = stickAt(frame - lag) * Config.walkSpeed
						return { stick = stickAt(frame), velocity = behind, facing = yawOf(stickAt(frame)) }
					end, 120)
					expect(problem).toBeNil()
				end
			end
		end
	end)

	it("jumps, knocked aside in the air", function()
		local problem = firstDifference(function(frame: number): Frame
			local airborne = frame >= 40 and frame < 80
			local velocity = if airborne then RIGHT * 6 + Vector3.new(0, 10, 0) else FORWARD * Config.walkSpeed
			return { stick = FORWARD, velocity = velocity, grounded = not airborne }
		end, 120)
		expect(problem).toBeNil()
	end)

	it("in a slowed capture (D-127)", function()
		for _, scale in { 0.5, 0.25 } do
			local function stickAt(frame: number): Vector3
				return if frame < 20 then Vector3.zero elseif frame < 120 then FORWARD else RIGHT
			end
			local problem = firstDifference(function(frame: number): Frame
				return {
					stick = stickAt(frame),
					velocity = lagged(stickAt, constant(Config.walkSpeed * scale))(frame),
					facing = 0,
				}
			end, 240, scale)
			expect(problem).toBeNil()
		end
	end)
end)

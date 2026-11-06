--!strict
--[[
	Locomotion's travel slip lets go of a lasting bias (the "slip leak": d-result DG1, D-334).
	Locomotion.stepTravel keeps a running difference between the root's own travel and what its
	speed carries (speed x dt), clamped to locomotion.stride.travelSlipSeconds of travel, and moves
	the gait phase on by each frame's change of it so the planted foot holds the ground on the
	engine's whole 1/240 s steps. The difference never decays: a root that travels a fraction more
	than its speed reads (0.6% in the owner's own sheathed run log over 1.18 s) pins it at the clamp
	after about 5.5 s, and from then on every long physics frame goes uncompensated: a flat foot
	moves 0.15 studs a frame at sprint (Stride.spec's own runs last 4.5 s, so it never shows).

	This is Stride.spec's engine-steps case (the real Locomotion and Choreo animator posing the hit
	matrix's player at the root physics left) run for 20 s on a root that travels 0.6% off the
	speed it reports: the owner PC's frame and step tables looped (0.58% short), and a steady clock
	with the root 0.6% fast and 0.6% slow. A
	flat foot (its centre within stride.flatBand of its height standing) moves no more than
	stride.frameBar between two frames and no more than slideBar over the time it is flat, from
	1.5 s to the end. The bounds are Stride.spec's own; none moves.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

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
local ChoreoData = Harness.load("src/shared/data/choreo")
local Rigs = Harness.load("src/shared/data/rigs")
local Pose = Harness.load("src/shared/choreo/Pose")

local Config = ChoreoData.locomotion
-- Read through `any` so a build without the stride table fails each test, not the whole file.
local Stride: any = (Config :: any).stride

local root = Harness.repoRoot()
local function loadTool(path: string): any
	local source = fs.readFile(root .. "/" .. path .. ".luau")
	local env = {
		require = function(target: string): any
			assert(target:sub(1, 6) == "@lune/", "HitMatrix may require only Lune libraries")
			return require(target)
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end
local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")

local FEET = { "LeftFoot", "RightFoot" }
local LEG_PARTS = {
	LowerTorso = true,
	LeftUpperLeg = true,
	LeftLowerLeg = true,
	LeftFoot = true,
	RightUpperLeg = true,
	RightLowerLeg = true,
	RightFoot = true,
}

type Body = {
	model: any,
	base: any, -- the root's CFrame standing on the field
	fieldTop: number,
	chain: any, -- legs only: the feet are all this measures
	corners: { [string]: { any } }, -- each foot's eight corners in its own frame
	footLength: number,
	forward: any,
	right: any,
}

local cachedBody: Body? = nil
local function body(): Body
	if cachedBody == nil then
		local avatar, field = HitMatrix.standing(Harness)
		local half = field.Size * 0.5
		local frame = field.CFrame
		local fieldTop = frame.Position.Y
			+ math.abs(frame.RightVector.Y) * half.X
			+ math.abs(frame.UpVector.Y) * half.Y
			+ math.abs(frame.LookVector.Y) * half.Z
		local full = Pose.chain(avatar.model)
		local links = {}
		for _, link in full.links do
			if LEG_PARTS[link.part1] then
				table.insert(links, link)
			end
		end
		local corners = {}
		local footLength = 0
		for _, foot in FEET do
			local size = avatar.model:FindFirstChild(foot).Size
			footLength = math.max(footLength, size.Z)
			local half = size * 0.5
			local list = {}
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						table.insert(list, Vector3.new(x * half.X, y * half.Y, z * half.Z))
					end
				end
			end
			corners[foot] = list
		end
		cachedBody = {
			model = avatar.model,
			base = avatar.base,
			fieldTop = fieldTop,
			chain = { rootName = full.rootName, links = links },
			corners = corners,
			footLength = footLength,
			forward = avatar.base.LookVector,
			right = avatar.base.RightVector,
		}
	end
	return cachedBody :: Body
end

-- ------------------------------------------------------------------ paced on a Lune rig

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

type Case = {
	direction: any, -- unit move in the body's frame (the body faces forward)
	-- The root's speed this frame; it may read the rig's Locomotion (the two-step stop does).
	speed: (t: number, dt: number, locomotion: any) -> number,
	drawn: (t: number) -> boolean,
	moving: ((t: number) -> boolean)?, -- the stick is held (default: speed > 0)
	sprinting: boolean?,
	duration: number,
	measureFrom: number,
	measureTo: number?,
	start: ((animator: any) -> ())?,
	-- A body held off its stick (D-144): the root's velocity (world, studs a second) moves it in
	-- place of direction x speed, with the stick (default `direction`) held while `moving`. The
	-- velocity reaches Locomotion in the state, or with `readRoot` on the root part (the local
	-- controller gives none).
	velocity: ((t: number) -> any)?,
	stick: any?,
	readRoot: boolean?,
	-- A slowed capture's own body (D-127): the clips and the root both run at this scale, and
	-- Locomotion hears it as clockScale.
	clockScale: number?,
}

local function drawnLabel(drawn: boolean): string
	return if drawn then "drawn" else "sheathed"
end

-- ------------------------------------------------------------------ specs

describe("the travel slip lets go of a lasting bias (D-334)", function()
	local PC_STEPS = {
		4,
		4,
		4,
		4,
		4,
		4,
		4,
		4,
		4,
		2,
		4,
		4,
		4,
		4,
		4,
		4,
		6,
		4,
		2,
		6,
		4,
		4,
		2,
		6,
		4,
		2,
		6,
		2,
		4,
		6,
		4,
		2,
		4,
		4,
		4,
		6,
		4,
		2,
		4,
		4,
		4,
		6,
		4,
		4,
		4,
		4,
		4,
		4,
		4,
		2,
		6,
		2,
		6,
		4,
		2,
		6,
		4,
		2,
		4,
		4,
		4,
		4,
		4,
		4,
		6,
		4,
		2,
		6,
		4,
		2,
		4,
		4,
	}
	local PC_MS = {
		15.6,
		17.7,
		16.5,
		17.2,
		16.2,
		16.5,
		16.9,
		16.7,
		16.6,
		16.4,
		16.1,
		17.3,
		15.7,
		16.8,
		17.1,
		17.0,
		16.9,
		16.0,
		17.7,
		16.1,
		16.5,
		16.7,
		17.1,
		16.5,
		16.0,
		17.0,
		16.4,
		17.0,
		16.8,
		16.6,
		16.0,
		17.7,
		15.4,
		17.7,
		17.2,
		15.9,
		16.1,
		17.4,
		15.9,
		17.2,
		17.2,
		16.6,
		17.0,
		15.9,
		16.7,
		17.4,
		15.9,
		16.8,
		16.2,
		17.3,
		15.9,
		16.9,
		17.1,
		15.9,
		16.7,
		17.5,
		15.9,
		16.7,
		17.4,
		15.7,
	}
	type Clock = (frame: number) -> (number, number) -- a rendered frame's dt, and its physics steps

	local function pcClock(): Clock
		return function(frame: number): (number, number)
			return PC_MS[(frame - 1) % #PC_MS + 1] / 1000, PC_STEPS[(frame - 1) % #PC_STEPS + 1]
		end
	end

	-- A 60 Hz render clock jittered by `jitter`; physics catches up in whole quanta of `quantum`
	-- steps, its boundary `lead` of a quantum off the render clock's.
	local function jitterClock(seed: number, jitter: number, quantum: number, lead: number): Clock
		local random = Random.new(seed)
		local wall, sim = 0, 0
		local q = quantum / 240
		return function(): (number, number)
			local dt = (1 / 60) * (1 + jitter * (random:NextNumber() * 2 - 1))
			wall += dt
			local count = math.max(0, math.floor((wall - sim) / q + lead))
			sim += count * q
			return dt, count * quantum
		end
	end

	local function state(direction: any, speed: number, drawn: boolean, sprinting: boolean): any
		return {
			moveDir = if speed > 0 then direction else Vector3.zero,
			speed = speed,
			sprinting = sprinting,
			grounded = true,
			drawn = drawn,
			turning = 0,
			verticalVelocity = 0,
			velocity = direction * speed,
		}
	end

	-- The foot centre's height above the field standing still (Idle, sheathed).
	local cachedRest: number? = nil
	local function restHeight(): number
		if cachedRest == nil then
			local shape = body()
			local model = buildRig()
			local animator: any = Choreo.get(model)
			local locomotion = Locomotion.new(animator, model, { footIK = false }) :: any
			for _ = 1, 30 do
				locomotion:update(1 / 60, state(Vector3.zero, 0, false, false))
				animator:step(1 / 60)
			end
			local solved = Pose.solve(shape.model, shape.base, animator.mixer:lastOffsets(), shape.chain)
			locomotion:destroy()
			Choreo.release(model)
			cachedRest = solved.LeftFoot.Position.Y - shape.fieldTop
		end
		return cachedRest :: number
	end

	type Flat = { frame: number, net: number, runs: number }

	-- The worst flat frame-to-frame move and flat net over 3 s, after 1.5 s to settle.
	local function engineSteps(
		direction: any,
		speed: number,
		drawn: boolean,
		sprinting: boolean,
		clock: Clock,
		bias: number,
		seconds: number
	): Flat
		local shape = body()
		local rest = restHeight()
		local model = buildRig()
		local animator: any = Choreo.get(model)
		local locomotion = Locomotion.new(animator, model, { footIK = false }) :: any
		local position = Vector3.zero
		local t, frame = 0, 0
		local result: Flat = { frame = 0, net = 0, runs = 0 }
		local open: { [string]: { net: any, frames: number, worst: number }? } = {}
		local previous: { [string]: any } = {}
		while t < seconds do
			frame += 1
			local dt, steps = clock(frame)
			t += dt
			position += direction * (speed * (1 + bias) * steps / 240)
			model.PrimaryPart.CFrame = CFrame.new(position)
			locomotion:update(dt, state(direction, speed, drawn, sprinting))
			animator:step(dt)
			local rootFrame = CFrame.new(shape.base.Position + position)
			local solved = Pose.solve(shape.model, rootFrame, animator.mixer:lastOffsets(), shape.chain)
			for _, foot in FEET do
				local centre = solved[foot].Position
				local run = open[foot]
				if centre.Y - shape.fieldTop <= rest + Stride.flatBand then
					if run == nil then
						open[foot] = { net = Vector3.zero, frames = 1, worst = 0 }
					elseif previous[foot] ~= nil then
						local moved = centre - previous[foot]
						local flat = Vector3.new(moved.X, 0, moved.Z)
						run.net += flat
						run.frames += 1
						run.worst = math.max(run.worst, flat.Magnitude)
					end
				elseif run ~= nil then
					if t >= 1.5 and run.frames >= 2 then
						result.frame = math.max(result.frame, run.worst)
						result.net = math.max(result.net, run.net.Magnitude)
						result.runs += 1
					end
					open[foot] = nil
				end
				previous[foot] = centre
			end
		end
		locomotion:destroy()
		Choreo.release(model)
		return result
	end

	-- A lasting mismatch between the root's travel and speed x dt: the owner PC's frame times and
	-- physics steps looped (its 60 frame times average 16.65 ms, its 72 step counts 16.55 ms of
	-- physics: the root runs 0.58% short of its speed, the mismatch DG1 looped), and a steady 60 Hz
	-- clock of 4 physics steps a frame with the root carried 0.6% fast and 0.6% slow (the owner's
	-- sheathed run log: 0.6% over 1.18 s), and the jittered clock (whose physics catches up with
	-- the wall clock) with the root 0.6% off its speed.
	local function steadyClock(): Clock
		return function(): (number, number)
			return 1 / 60, 4
		end
	end
	local CASES = {
		{ name = "PC steps looped", make = pcClock, bias = 0 },
		{ name = "steady, root +0.6%", make = steadyClock, bias = 0.006 },
		{ name = "steady, root -0.6%", make = steadyClock, bias = -0.006 },
		{
			name = "jitter 5%, root +0.6%",
			make = function(): Clock
				return jitterClock(7, 0.05, 2, 0.02)
			end,
			bias = 0.006,
		},
		{
			name = "jitter 5%, root -0.6%",
			make = function(): Clock
				return jitterClock(7, 0.05, 2, 0.02)
			end,
			bias = -0.006,
		},
	}
	local SECONDS = 20

	it("walk, run and sprint, both sets, for 20 s on a root that travels 0.6% off its speed", function()
		local shape = body()
		local gaits = {
			{ name = "walk", direction = shape.forward, speed = Config.walkSpeed },
			{ name = "run", direction = shape.forward, speed = Config.runSpeed },
			{ name = "sprint", direction = shape.forward, speed = Config.sprintSpeed, sprinting = true },
		}
		local problems = {}
		for _, drawn in { false, true } do
			for _, gait in gaits do
				for _, case in CASES do
					local label = ("%s %s, %s"):format(gait.name, drawnLabel(drawn), case.name)
					local flat = engineSteps(
						gait.direction,
						gait.speed,
						drawn,
						gait.sprinting == true,
						case.make(),
						case.bias,
						SECONDS
					)
					if flat.runs < 4 then
						table.insert(problems, ("%s: %d flat feet"):format(label, flat.runs))
					end
					if flat.frame > Stride.frameBar then
						table.insert(
							problems,
							("%s: moved %.3f in a frame, limit %.3f"):format(label, flat.frame, Stride.frameBar)
						)
					end
					if flat.net > Stride.slideBar then
						table.insert(
							problems,
							("%s: slid %.3f flat, limit %.3f"):format(label, flat.net, Stride.slideBar)
						)
					end
				end
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)
end)

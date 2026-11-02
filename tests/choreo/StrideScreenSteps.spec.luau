--!strict
--[[
	The locked drawn walk's planted foot on screen, on the PC's physics step clocks (item 530,
	D-343, D-651). The screen draws the pose a render step writes on the root that frame's
	physics then moves. So each frame the real Locomotion and Choreo animator pose the hit matrix's
	player on the root where the frame before's physics left it, and the feet are read on the root
	after this frame's steps: the BasePart read of items 477 and 530. (Stride.spec's engine-steps
	block reads the chain order, the pose on the root physics already moved, and stands as it is.)

	The clocks are drawn to item 530's counts on the owner's PC (97cea9d): the engine plans whole
	1/240 s steps on its own frame clock and takes one step more for every 64 it plans (4.063 a
	frame at 60 fps, 1.693 at 144), every clock the code reads runs that 1.5% short, and the render
	dt carries up to 6 ms of work jitter (4 ms at 240). D-334's take-up alone reads the root's
	travel up to the render step, so the foot shows each frame's change of steps: 0.020-0.033 at
	60 fps as the seed falls, 0.051 at 144 (the PC: 0.047 and 0.050).

	The read: each foot's least-moving grounded corner (within stride.contact of the field on this
	frame and the one before), frame to frame, walking at walkSpeed for 9 s, from 1.5 s.
]]

local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

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

local clock = 0
local Choreo = Harness.load("src/client/choreo/Choreo")
Choreo.configure({
	now = function()
		return clock
	end,
	cameraPosition = function()
		return Vector3.zero
	end,
})
local Locomotion = Harness.load("src/client/choreo/Locomotion")
local Pose = Harness.load("src/shared/choreo/Pose")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ChoreoData = Harness.load("src/shared/data/choreo")

local root = Harness.repoRoot()
local function loadTool(path: string): any
	local source = fs.readFile(root .. "/" .. path .. ".luau")
	local env = {
		require = function(target: string): any
			return require(target)
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end
local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")

local Config = ChoreoData.locomotion
local Stride = Config.stride
local TakeUp = Stride.takeUp
local FEET = { "LeftFoot", "RightFoot" }

type Clock = { dt: { number }, steps: { number } }

-- Item 530's engine: `fps` frames whose length jitters by up to frameJitMs (telescoping), whole
-- steps planned on that frame clock in `pair`s, one more every `extraEvery` planned (0: none),
-- and a render dt that also carries up to workMs of work jitter (telescoping).
local function engine530(
	rows: number,
	fps: number,
	frameJitMs: number,
	workMs: number,
	seed: number,
	extraEvery: number,
	pair: number
): Clock
	local random = Random.new(seed)
	local acc = (0.3 + 0.4 * random:NextNumber()) / 240 * pair
	local count = math.floor(random:NextNumber() * math.max(1, extraEvery))
	local vPrev = random:NextNumber() * frameJitMs / 1000
	local wPrev = random:NextNumber() * workMs / 1000
	local dts, steps = {}, {}
	for i = 1, rows do
		local v = random:NextNumber() * frameJitMs / 1000
		local f = 1 / fps + v - vPrev
		vPrev = v
		acc += f
		local planned = 0
		while acc >= pair / 240 - 1e-12 do
			acc -= pair / 240
			planned += pair
		end
		local extra = 0
		if extraEvery > 0 then
			count += planned
			while count >= extraEvery do
				count -= extraEvery
				extra += 1
			end
		end
		local w = random:NextNumber() * workMs / 1000
		dts[i] = f + w - wPrev
		wPrev = w
		steps[i] = planned + extra
	end
	return { dt = dts, steps = steps }
end

-- Item 282's frames and steps (Stride.spec's PC clock), looped.
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
local function pc282(rows: number): Clock
	local dts, steps = {}, {}
	for i = 1, rows do
		dts[i] = PC_MS[(i - 1) % #PC_MS + 1] / 1000
		steps[i] = PC_STEPS[(i - 1) % #PC_STEPS + 1]
	end
	return { dt = dts, steps = steps }
end

-- F2h's 60 Hz model: the steps fall 0.06 a frame behind a frame clock that jitters by 0.5 ms
-- without telescoping, and the render dt carries 1 ms of work jitter.
local function drifting(rows: number, seed: number): Clock
	local random = Random.new(seed)
	local acc = random:NextNumber() / 240
	local wPrev = random:NextNumber() / 1000
	local dts, steps = {}, {}
	for i = 1, rows do
		local f = (1000 / 60 + (random:NextNumber() * 2 - 1) * 0.5) / 1000
		acc += f + 0.06 / 240
		local count = 0
		while acc >= 1 / 240 - 1e-12 do
			acc -= 1 / 240
			count += 1
		end
		local w = random:NextNumber() / 1000
		dts[i] = f + w - wPrev
		wPrev = w
		steps[i] = count
	end
	return { dt = dts, steps = steps }
end

local function bottom(frame: any, size: any): { any }
	local out = {}
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			table.insert(out, (frame * CFrame.new(sx * size.X / 2, -size.Y / 2, sz * size.Z / 2)).Position)
		end
	end
	return out
end

local function flat(v: any): any
	return Vector3.new(v.X, 0, v.Z)
end

type Walk = { p90: number, largest: number, low: { number } }

-- The drawn walk at walkSpeed, locked straight ahead, on `steps`'s clock for 9 s, read on screen:
-- the step p90 and the largest step of the least-moving grounded corner from 1.5 s, and each
-- foot's share of frames with its lowest corner within stride.contact of the field.
local function walk(steps: Clock, ahead: boolean): Walk
	local avatar, field = HitMatrix.standing(Harness)
	local model = avatar.model
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", true)
	local top = ClipAudit.topOf(field.CFrame, field.Size)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: any
	local primary = model.PrimaryPart
	humanoid.HipHeight = avatar.rootHeight - primary.Size.Y / 2
	primary.CFrame = avatar.base
	primary.Position = avatar.base.Position
	local animator: any = Choreo.get(model)
	local locomotion: any = Locomotion.new(animator, model, {
		stepsAhead = ahead,
		raycast = function(origin: any, direction: any): any
			if origin.Y >= top and origin.Y + direction.Y <= top then
				return Vector3.new(origin.X, top, origin.Z)
			end
			return nil
		end,
	})
	local chain = Pose.chain(model)
	local speed = Config.walkSpeed
	local way = Vector3.new(0, 0, -1)
	local state = {
		moveDir = way,
		speed = speed,
		sprinting = false,
		grounded = true,
		drawn = true,
		turning = 0,
		verticalVelocity = 0,
		velocity = way * speed,
	}
	local travelled = Vector3.zero
	local t, frame, rows = 0, 0, 0
	local moves: { number } = {}
	local largest = 0
	local last: { [string]: any } = {}
	local low = { 0, 0 }
	while t < 9 do
		frame += 1
		local i = (frame - 1) % #steps.dt + 1
		local dt = steps.dt[i]
		clock += dt
		t += dt
		-- The render step: the root where the frame before's physics left it.
		local at = avatar.base * CFrame.new(travelled)
		primary.CFrame = at
		primary.Position = at.Position
		locomotion:update(dt, state)
		animator:step(dt)
		-- This frame's physics, then the screen.
		travelled += way * (speed * steps.steps[i] / 240)
		local solved = Pose.solve(model, avatar.base * CFrame.new(travelled), animator.mixer:lastOffsets(), chain)
		if t > 1.5 then
			rows += 1
			for f, name in FEET do
				local now = bottom(solved[name], (model:FindFirstChild(name) :: any).Size)
				local grounded = {}
				local lowest = math.huge
				for k = 1, 4 do
					grounded[k] = now[k].Y - top <= Stride.contact
					lowest = math.min(lowest, now[k].Y - top)
				end
				if math.abs(lowest) <= Stride.contact then
					low[f] += 1
				end
				local before = last[name]
				if before ~= nil then
					local least = math.huge
					for k = 1, 4 do
						if grounded[k] and before.grounded[k] then
							least = math.min(least, (flat(now[k]) - flat(before.now[k])).Magnitude)
						end
					end
					if least < math.huge then
						table.insert(moves, least)
						largest = math.max(largest, least)
					end
				end
				last[name] = { now = now, grounded = grounded }
			end
		end
	end
	locomotion:destroy()
	Choreo.release(model)
	table.sort(moves)
	return {
		p90 = moves[math.max(1, math.floor(#moves * 0.9))],
		largest = largest,
		low = { low[1] / rows, low[2] / rows },
	}
end

local SEEDS = { 1, 2, 3, 4, 5 }

describe("the locked drawn walk on screen, on the PC's step clocks (item 530, D-343, D-651)", function()
	it("at 60 and 144 fps, with the take-up: the step p90 under stride.takeUp.p90Bar on every seed", function()
		local problems = {}
		for _, rate in { { fps = 60, rows = 900 }, { fps = 144, rows = 2000 } } do
			for _, seed in SEEDS do
				local result = walk(engine530(rate.rows, rate.fps, 0.3, 6, seed, 64, 1), true)
				if result.p90 > TakeUp.p90Bar then
					table.insert(
						problems,
						("%d fps seed %d: step p90 %.4f (largest %.4f), bar %.3f"):format(
							rate.fps,
							seed,
							result.p90,
							result.largest,
							TakeUp.p90Bar
						)
					)
				end
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it(
		"at 240 fps, with no drift step, in pairs, on item 282's 2-6 pattern and on a drifting jittered clock: what passes with D-334 alone still passes, and nothing gets worse",
		function()
			local clocks: { { name: string, make: (seed: number) -> Clock } } = {
				{
					name = "240 fps",
					make = function(seed: number): Clock
						return engine530(3000, 240, 0.3, 4, seed, 64, 1)
					end,
				},
				{
					name = "60 fps, no drift",
					make = function(seed: number): Clock
						return engine530(900, 60, 0.3, 6, seed, 0, 1)
					end,
				},
				{
					name = "144 fps, no drift",
					make = function(seed: number): Clock
						return engine530(2000, 144, 0.3, 6, seed, 0, 1)
					end,
				},
				{
					name = "144 fps in pairs",
					make = function(seed: number): Clock
						return engine530(2000, 144, 0.3, 6, seed, 0, 2)
					end,
				},
				{
					name = "60 fps, steady",
					make = function(seed: number): Clock
						return engine530(900, 60, 0, 0, seed, 0, 1)
					end,
				},
				{
					name = "60 fps drifting off a jittered frame",
					make = function(seed: number): Clock
						return drifting(900, seed + 1)
					end,
				},
			}
			local problems = {}
			for _, entry in clocks do
				for _, seed in SEEDS do
					local steps = entry.make(seed)
					local alone = walk(steps, false)
					local result = walk(steps, true)
					local label = ("%s seed %d"):format(entry.name, seed)
					if alone.p90 <= TakeUp.p90Bar and result.p90 > TakeUp.p90Bar then
						table.insert(
							problems,
							("%s: step p90 %.4f over the bar (D-334 alone %.4f)"):format(label, result.p90, alone.p90)
						)
					end
					if alone.p90 > TakeUp.p90Bar and result.p90 > alone.p90 then
						table.insert(
							problems,
							("%s: step p90 %.4f, D-334 alone %.4f"):format(label, result.p90, alone.p90)
						)
					end
				end
			end
			local alone = walk(pc282(1200), false)
			local result = walk(pc282(1200), true)
			if result.p90 > alone.p90 or result.largest > alone.largest then
				table.insert(
					problems,
					("item 282: step p90 %.4f largest %.4f, D-334 alone %.4f and %.4f"):format(
						result.p90,
						result.largest,
						alone.p90,
						alone.largest
					)
				)
			end
			expect(table.concat(problems, "; ")).toBe("")
		end
	)
end)

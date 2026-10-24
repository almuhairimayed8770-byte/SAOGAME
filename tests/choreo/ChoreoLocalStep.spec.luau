--!strict
--[[
	The local rig's step (D-139) and an animator's seek (D-138), on a fresh copy of Choreo (its own
	registry and frame loops) whose frame signals and clock are the spec's: the owner of a driven
	local rig steps it with Choreo.stepLocal, RenderStepped and Heartbeat leave it alone, and
	PreSimulation still writes its pose again over the engine's reset (D-053).
]]

local luau = require("@lune/luau")

local ChoreoData = Harness.load("src/shared/data/choreo")
local Rigs = Harness.load("src/shared/data/rigs")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")

local CHOREO_PATH = "src/client/choreo/Choreo"
local FRAME = 1 / 60
local HORIZONTAL = "player/OneHandedSword/Horizontal"
local GUARD = "player/OneHandedSword/Guard"

-- A frame signal that runs its handlers at once and lets their errors through.
local function frameSignal(): any
	local handlers: { (...any) -> () } = {}
	local signal = {}
	function signal.Connect(_self: any, handler: (...any) -> ()): any
		table.insert(handlers, handler)
		return {
			Disconnect = function()
				local index = table.find(handlers, handler)
				if index ~= nil then
					table.remove(handlers, index)
				end
			end,
		}
	end
	function signal.Fire(_self: any, ...: any)
		for _, handler in table.clone(handlers) do
			handler(...)
		end
	end
	return signal
end

type World = {
	choreo: any,
	clock: number,
	renderStepped: any,
	heartbeat: any,
	preSimulation: any,
}

-- A fresh Choreo on the spec's clock, the camera at the origin.
local function newWorld(): World
	local renderStepped = frameSignal()
	local bound: { [string]: any } = {}
	local runService = {
		RenderStepped = renderStepped,
		Heartbeat = frameSignal(),
		PreSimulation = frameSignal(),
		-- The rigs' render step (bound just before the camera's) runs on the spec's frame signal.
		BindToRenderStep = function(_self: any, name: string, _priority: number, fn: (dt: number) -> ())
			bound[name] = renderStepped:Connect(fn)
		end,
		UnbindFromRenderStep = function(_self: any, name: string)
			if bound[name] ~= nil then
				bound[name].Disconnect()
				bound[name] = nil
			end
		end,
	}
	local env = Harness.environment()
	env.script = Harness.node(CHOREO_PATH)
	env.require = function(target: any): any
		return Harness.loadModule(target)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			if name == "RunService" then
				return runService
			end
			return Harness.game():GetService(name)
		end,
	}
	local choreo =
		luau.load(Harness.readFile(CHOREO_PATH .. ".luau"), { debugName = CHOREO_PATH, environment = env :: any })()
	local world: World = {
		choreo = choreo,
		clock = 1000,
		renderStepped = runService.RenderStepped,
		heartbeat = runService.Heartbeat,
		preSimulation = runService.PreSimulation,
	}
	choreo.configure({
		now = function(): number
			return world.clock
		end,
		cameraPosition = function(): Vector3
			return Vector3.zero
		end,
		connect = function(): any
			return nil
		end,
		defer = function(fn: () -> ())
			fn()
		end,
	})
	return world
end

-- A PlayerR15 model at `position`: one Part per rig part, one Motor6D per joint. With
-- `engineAnimator` it carries a Humanoid with the engine's Animator (D-053).
local function buildRig(position: Vector3?, engineAnimator: boolean?): any
	local model = Instance.new("Model")
	model.Name = "PlayerR15"
	model:SetAttribute("Rig", "PlayerR15")
	local parts: { [string]: any } = {}
	local function part(name: string): any
		local existing = parts[name]
		if existing then
			return existing
		end
		local created = Instance.new("Part")
		created.Name = name
		created.Position = position or Vector3.zero
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
	if engineAnimator then
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = model
		local animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return model
end

local function motorOf(model: any, name: string): any
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Name == name then
			return descendant
		end
	end
	return nil
end

-- Counts an animator's steps.
local function stepCounter(animator: any): () -> number
	local steps = 0
	animator:onStep(function()
		steps += 1
	end)
	return function(): number
		return steps
	end
end

type EventRow = { clipId: string, kind: string, jumped: boolean }

local function eventRecorder(animator: any): { EventRow }
	local rows: { EventRow } = {}
	animator.events:Connect(function(clipId: string, event: any, jumped: boolean)
		table.insert(rows, { clipId = clipId, kind = event.kind, jumped = jumped })
	end)
	return rows
end

local function kindsOf(rows: { EventRow }, from: number?): { string }
	local list = {}
	for index = from or 1, #rows do
		table.insert(list, rows[index].kind)
	end
	return list
end

-- The clip's events with times in (from, to], in order.
local function eventsBetween(clipId: string, from: number, to: number): { string }
	local list = {}
	for _, event in ClipLibrary.get(clipId).events do
		if event.time > from and event.time <= to then
			table.insert(list, event.kind)
		end
	end
	return list
end

local function rootAt(clipId: string, clipTime: number): Vector3
	local offset = ClipSampler.rootMotionAt(ClipLibrary.get(clipId), clipTime)
	return Vector3.new(offset[1], offset[2], offset[3])
end

describe("Choreo.stepLocal (D-139)", function()
	it("a driven local rig is its owner's to step, once a frame; RenderStepped steps the others", function()
		local world = newWorld()
		local mine = buildRig()
		local other = buildRig()
		local myAnimator = world.choreo.get(mine)
		local otherAnimator = world.choreo.get(other)
		local mySteps = stepCounter(myAnimator)
		local otherSteps = stepCounter(otherAnimator)
		world.choreo.setLocalModel(mine, true)
		for frame = 1, 10 do
			world.clock += FRAME
			-- Either order of the owner's render step and Choreo's RenderStepped.
			if frame % 2 == 0 then
				world.choreo.stepLocal(FRAME)
				world.renderStepped:Fire(FRAME)
			else
				world.renderStepped:Fire(FRAME)
				world.choreo.stepLocal(FRAME)
			end
			expect(mySteps()).toBe(frame)
			expect(otherSteps()).toBe(frame)
		end
		-- RenderStepped alone leaves it be.
		world.clock += FRAME
		world.renderStepped:Fire(FRAME)
		expect(mySteps()).toBe(10)
		expect(otherSteps()).toBe(11)
	end)

	it("undriven (the ClipLab's way) RenderStepped steps the local rig and stepLocal does nothing", function()
		local world = newWorld()
		local mine = buildRig()
		local animator = world.choreo.get(mine)
		local steps = stepCounter(animator)
		world.choreo.setLocalModel(mine)
		world.clock += FRAME
		world.renderStepped:Fire(FRAME)
		world.choreo.stepLocal(FRAME)
		expect(steps()).toBe(1)

		-- Driven, then let go: no local model is stepped by stepLocal, and RenderStepped has it back.
		world.choreo.setLocalModel(mine, true)
		world.clock += FRAME
		world.renderStepped:Fire(FRAME)
		expect(steps()).toBe(1)
		world.choreo.setLocalModel(nil)
		world.choreo.stepLocal(FRAME)
		expect(steps()).toBe(1)
		world.clock += FRAME
		world.renderStepped:Fire(FRAME)
		expect(steps()).toBe(2)
		-- A driven flag does not outlive the model it came with.
		world.choreo.setLocalModel(mine, true)
		world.choreo.setLocalModel(mine)
		world.clock += FRAME
		world.renderStepped:Fire(FRAME)
		world.choreo.stepLocal(FRAME)
		expect(steps()).toBe(3)
	end)

	it("a driven local rig far from the camera stays full rate: Heartbeat never steps it either", function()
		local world = newWorld()
		local far = buildRig(Vector3.new(ChoreoData.quality.High.nearRadius * 10, 0, 0))
		local animator = world.choreo.get(far)
		local steps = stepCounter(animator)
		world.choreo.setLocalModel(far, true)
		for _ = 1, 30 do
			world.clock += FRAME
			world.renderStepped:Fire(FRAME)
			world.heartbeat:Fire(FRAME)
		end
		expect(steps()).toBe(0)
		world.choreo.stepLocal(FRAME)
		expect(steps()).toBe(1)
	end)

	it("a released local rig is not stepped", function()
		local world = newWorld()
		local mine = buildRig()
		local animator = world.choreo.get(mine)
		local steps = stepCounter(animator)
		world.choreo.setLocalModel(mine, true)
		world.choreo.release(mine)
		world.clock += FRAME
		world.choreo.stepLocal(FRAME)
		expect(steps()).toBe(0)
	end)

	it("a stepLocal that comes back from a render stall is a jump: marked events, no root motion", function()
		for _, handed in { FRAME, 1.2 } do
			local world = newWorld()
			local mine = buildRig()
			local animator = world.choreo.get(mine)
			world.choreo.setLocalModel(mine, true)
			local rows = eventRecorder(animator)
			local handle = animator:play(HORIZONTAL, { blendIn = 0 })
			for _ = 1, 3 do
				world.clock += FRAME
				world.choreo.stepLocal(FRAME)
			end
			local before = handle.time
			local from = #rows + 1
			-- The display sleeps 1.2 s: no render step at all, then one that hands back `handed`.
			world.clock += 1.2
			world.choreo.stepLocal(handed)
			expect(handle.time).toBeCloseTo(math.min(before + 1.2, handle.clip.duration), 1e-9)
			expect(animator:currentRootMotionDelta()).toBe(Vector3.zero)
			local crossed = kindsOf(rows, from)
			expect(#crossed > 0).toBe(true)
			for index = from, #rows do
				expect(rows[index].jumped).toBe(true)
			end
		end
	end)

	it("PreSimulation still writes a driven rig's pose again after the engine's reset (D-053)", function()
		local world = newWorld()
		local mine = buildRig(nil, true)
		local animator = world.choreo.get(mine)
		world.choreo.setLocalModel(mine, true)
		animator:play(GUARD, { blendIn = 0 })
		for _ = 1, 3 do
			world.clock += FRAME
			world.choreo.stepLocal(FRAME)
			world.renderStepped:Fire(FRAME)
			local shoulder = motorOf(mine, "RightShoulder")
			local posed = shoulder.Transform
			expect(posed == CFrame.identity).toBe(false)
			shoulder.Transform = CFrame.identity -- the engine's Animator resets every joint
			world.preSimulation:Fire(FRAME)
			expect(shoulder.Transform == posed).toBe(true)
		end
	end)
end)

describe("Animator:seek (D-138)", function()
	it("moves a playing clip on at once: its crossed events fire once, unmarked, and its root goes nowhere", function()
		local world = newWorld()
		local mine = buildRig()
		local animator = world.choreo.get(mine)
		world.choreo.setLocalModel(mine, true)
		local rows = eventRecorder(animator)
		local handle = animator:play(HORIZONTAL, { blendIn = 0 })
		world.clock += FRAME
		world.choreo.stepLocal(FRAME)
		local from = #rows + 1
		-- Frozen (the Art hold), then moved on past the root's first step (0.35 to 0.4).
		animator:setTimeScale(0)
		animator:seek(handle, 0.45)
		expect(handle.time).toBe(0.45)
		expect(kindsOf(rows, from)).toEqual(eventsBetween(HORIZONTAL, FRAME, 0.45))
		expect(table.find(kindsOf(rows, from), "ActivationHold")).never.toBeNil()
		for index = from, #rows do
			expect(rows[index].clipId).toBe(HORIZONTAL)
			expect(rows[index].jumped).toBe(false)
		end
		-- The next step shows the seek's pose and moves nothing: the clip holds at scale zero.
		local reference = buildRig()
		local referenceAnimator = world.choreo.get(reference)
		referenceAnimator:setTimeScale(0)
		referenceAnimator:play(HORIZONTAL, { blendIn = 0, startTime = 0.45 })
		local seen = #rows
		world.clock += FRAME
		world.choreo.stepLocal(FRAME)
		referenceAnimator:step(FRAME)
		expect(#rows).toBe(seen)
		expect(handle.time).toBe(0.45)
		expect(animator:currentRootMotionDelta()).toBe(Vector3.zero)
		for _, name in { "RightShoulder", "LeftHip", "Waist" } do
			local got = motorOf(mine, name).Transform
			local want = motorOf(reference, name).Transform
			expect((got.Position - want.Position).Magnitude < 1e-6).toBe(true)
			expect((got.LookVector - want.LookVector).Magnitude < 1e-5).toBe(true)
			expect((got.UpVector - want.UpVector).Magnitude < 1e-5).toBe(true)
		end
		-- Let go, the clip runs on from 0.45: the root delta is this frame's, not the seek's gap.
		expect((rootAt(HORIZONTAL, 0.45) - rootAt(HORIZONTAL, FRAME)).Magnitude > 0.01).toBe(true)
		animator:setTimeScale(1)
		world.clock += FRAME
		world.choreo.stepLocal(FRAME)
		local expected = rootAt(HORIZONTAL, 0.45 + FRAME) - rootAt(HORIZONTAL, 0.45)
		expect((animator:currentRootMotionDelta() - expected).Magnitude < 1e-5).toBe(true)
		expect(kindsOf(rows, seen + 1)).toEqual(eventsBetween(HORIZONTAL, 0.45, 0.45 + FRAME))
	end)

	it("never moves a clip back; an engine Animation's handle and a released animator are left alone", function()
		local world = newWorld()
		local mine = buildRig()
		local animator = world.choreo.get(mine)
		world.choreo.setLocalModel(mine, true)
		local rows = eventRecorder(animator)
		local handle = animator:play(HORIZONTAL, { blendIn = 0 })
		for _ = 1, 20 do
			world.clock += FRAME
			world.choreo.stepLocal(FRAME)
		end
		local at = handle.time
		local seen = #rows
		animator:seek(handle, 0.1)
		expect(handle.time).toBe(at)
		expect(#rows).toBe(seen)

		-- An engine Animation's handle has no clip clock to move.
		local track = { rbx = {}, clipId = "rbxassetid://1", time = 0 }
		animator:seek(track, 0.5)
		expect(track.time).toBe(0)
		expect(#rows).toBe(seen)

		world.choreo.release(mine)
		animator:seek(handle, 0.9)
		expect(handle.time).toBe(at)
		expect(#rows).toBe(seen)
	end)
end)

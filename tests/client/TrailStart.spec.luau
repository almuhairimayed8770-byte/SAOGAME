--!strict
--[[
	The trail ribbon's stroke starts where the window opens and follows the clip between frames
	(D-269 amended). On the real player rig (the hit matrix's avatar posed by a real Choreo
	animator) a window opens between two rendered frames; the frame before shows the wind-up. The
	stroke used to start on that frame's blade, so its first segment pointed back along the cut
	(95 to 175 degrees against it: Basic3's first sample 5.8, 3.3 and 1.4 studs from the blade at the
	open at 30, 60 and 144 fps, Rising Arc's 2.3, 1.4 and 0.6), and its in-betweens interpolated the
	two frames' joints, not the clip (the true tip path up to 2.2 studs off the ribbon at 60 fps).
	Now the first sample is the clip's blade at the open and each in-between is the clip's pose at
	its own clock between the frames, with what the frames show on top of it carried across.

	Trails reads the rig's animator (Trails.bind's `animator`); the clip events route to
	Trails.setActive as Replication.routeClipEvent routes them.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

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
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Fx = Harness.load("src/shared/data/fx")
local Trails = Harness.load("src/client/fx/Trails")
local TrailRibbon = Harness.load("src/client/fx/TrailRibbon")
local Engine = Harness.load("src/client/fx/Engine")

local clock = 0
Choreo.configure({
	now = function(): number
		return clock
	end,
	cameraPosition = function(): Vector3
		return Vector3.zero
	end,
})

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

local PREFIX = ChoreoData.locomotion.clipPrefix
local CORE = Fx.trail.ribbon.layers[2].fraction
-- The true path's sample rate: a snap's tip moves under 0.07 studs between two of its samples.
local TRUTH_HZ = 2880
local LIGHTS = { TrailOn = "Art", HitWindowOpen = "Art", SmearOn = "Smear" }
local OUTS = { TrailOff = "Art", HitWindowClose = "Art", SmearOff = "Smear" }

local function rig(): Model
	local avatar = HitMatrix.standing(Harness)
	local model = avatar.model
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", true)
	local primary = model.PrimaryPart :: BasePart
	primary.CFrame = avatar.base
	primary.Position = avatar.base.Position
	for _, item in model:GetDescendants() do
		-- Lune derives neither Position from CFrame nor WorldPosition; the trail's budget and the
		-- tip ring (swingDirection) read them.
		if item:IsA("BasePart") then
			local ok = pcall(function(): Vector3
				return item.Position
			end)
			if not ok then
				item.Position = item.CFrame.Position
			end
		elseif item:IsA("Attachment") then
			local ok = pcall(function(): Vector3
				return item.WorldPosition
			end)
			if not ok then
				item.WorldPosition = primary.CFrame.Position
			end
		end
	end
	return model
end

local function segmentDistance(point: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local lengthSquared = ab:Dot(ab)
	local t = if lengthSquared > 0 then math.clamp((point - a):Dot(ab) / lengthSquared, 0, 1) else 0
	return (point - (a + ab * t)).Magnitude
end

type Truth = { times: { number }, tips: { Vector3 } }

-- The clip's own blade, played alone at TRUTH_HZ: each sample's clip time and tip.
local function truth(name: string): Truth
	local model = rig()
	local animator: any = Choreo.get(model)
	local clipId = PREFIX .. name
	local clip = ClipLibrary.get(clipId)
	animator:play(clipId)
	local chain = BladeContact.chain(model :: any) :: any
	local times, tips = {}, {}
	local dt = 1 / TRUTH_HZ
	for step = 1, math.ceil(clip.duration / dt) do
		clock += dt
		animator:step(dt)
		local handle = animator.mixer:find(clipId)
		if handle == nil then
			break
		end
		local _, tip = BladeContact.blade(chain, BladeContact.read(chain))
		times[step], tips[step] = handle.time, tip
	end
	Choreo.release(model)
	return { times = times, tips = tips }
end

-- The clip's blade core at exactly `clipTime` (played alone, its last step landing there).
local function coreAt(name: string, clipTime: number): Vector3
	local model = rig()
	local animator: any = Choreo.get(model)
	animator:play(PREFIX .. name)
	local steps = math.ceil(clipTime * TRUTH_HZ)
	for _ = 1, steps do
		clock += clipTime / steps
		animator:step(clipTime / steps)
	end
	local chain = BladeContact.chain(model :: any) :: any
	local guard, tip = BladeContact.blade(chain, BladeContact.read(chain))
	Choreo.release(model)
	return guard:Lerp(tip, CORE)
end

type Push = { guard: Vector3, tip: Vector3, joined: boolean, frame: number }
type Stroke = { light: number, out: number, pushes: { Push }, lastTime: number }

-- Plays `name` at `fps` (its first frame `phase` of a frame long) through the real path, the
-- ribbon's samples recorded as Trails pushes them: per stroke, the clip time it lit at, the time
-- it went out, its samples and the clip time of its last frame.
local function play(name: string, fps: number, phase: number): { Stroke }
	local model = rig()
	local renderFn: ((dt: number) -> ())? = nil
	Engine.setViewer(function(): Vector3
		return (model.PrimaryPart :: BasePart).Position
	end)
	Engine.setClock(function(): number
		return clock
	end)
	Trails.start()
	Trails.bind({
		now = function(): number
			return clock
		end,
		onRender = function(fn: (dt: number) -> ()): () -> ()
			renderFn = fn
			return function()
				renderFn = nil
			end
		end,
		onWatch = function(_fn: (dt: number) -> ()): () -> ()
			return function() end
		end,
		clear = function(_trail: Trail) end,
		held = function(_model: Instance): boolean
			return false
		end,
		animator = function(target: Instance): any
			return Choreo.find(target :: any)
		end,
	})
	Trails.attach(model)
	local animator: any = Choreo.get(model)
	local clipId = PREFIX .. name
	local strokes: { Stroke } = {}
	local lit: { [string]: boolean } = {}
	animator.events:Connect(function(_id: string, event: any, _jumped: boolean)
		local kind = LIGHTS[event.kind]
		if kind ~= nil then
			if next(lit) == nil then
				table.insert(strokes, { light = event.time, out = math.huge, pushes = {}, lastTime = event.time })
			end
			lit[kind] = true
			Trails.setActive(model, true, kind :: any)
		end
		local off = OUTS[event.kind]
		if off ~= nil then
			lit[off] = nil
			if next(lit) == nil and #strokes > 0 then
				strokes[#strokes].out = event.time
			end
			Trails.setActive(model, false, off :: any)
		end
	end)
	local frame = 0
	local realPush = TrailRibbon.push
	TrailRibbon.push = function(ribbon: any, guard: Vector3, tip: Vector3, born: number, joined: boolean): boolean
		local stroke = strokes[#strokes]
		if stroke ~= nil then
			table.insert(stroke.pushes, { guard = guard, tip = tip, joined = joined, frame = frame })
		end
		return realPush(ribbon, guard, tip, born, joined)
	end
	local ok, err = pcall(function()
		animator:play(clipId)
		local dt = 1 / fps
		local stepDt = dt * phase
		for index = 1, 600 do
			frame = index
			clock += stepDt
			animator:step(stepDt)
			local handle = animator.mixer:find(clipId)
			assert(renderFn ~= nil, "Trails connected no render step");
			(renderFn :: (dt: number) -> ())(stepDt)
			stepDt = dt
			if handle == nil or handle.done then
				break
			end
			local stroke = strokes[#strokes]
			if stroke ~= nil and #stroke.pushes > 0 and stroke.pushes[#stroke.pushes].frame == frame then
				stroke.lastTime = handle.time
			end
		end
	end)
	TrailRibbon.push = realPush
	Trails.bind(nil)
	Trails.reset()
	Engine.setViewer(nil)
	Engine.setClock(nil)
	Choreo.release(model)
	if not ok then
		error(err, 0)
	end
	return strokes
end

local PHASES = { 0.3, 0.9 }

describe("the trail ribbon starts at the window's open and follows the clip (D-269 amended)", function()
	it("takes its first sample at the clip's blade where the window opens, at 30, 60 and 144 fps", function()
		for _, name in { "Basic3", "RisingArc" } do
			local cores: { [number]: Vector3 } = {}
			for _, fps in { 30, 60, 144 } do
				for _, phase in PHASES do
					local strokes = play(name, fps, phase)
					expect(#strokes > 0).toBe(true)
					for index, stroke in strokes do
						local first = stroke.pushes[1]
						expect(first ~= nil and not first.joined).toBe(true)
						cores[index] = cores[index] or coreAt(name, stroke.light)
						local reach = (first.guard:Lerp(first.tip, CORE) - cores[index]).Magnitude
						if reach > 0.1 then
							error(
								("%s at %d fps (phase %.1f), stroke %d: its first sample is %.2f studs from the blade at the open"):format(
									name,
									fps,
									phase,
									index,
									reach
								)
							)
						end
					end
				end
			end
		end
	end)

	it("never points its first segment back along the cut", function()
		for _, name in { "Basic3", "RisingArc", "SharpNail" } do
			for _, fps in { 30, 60, 144 } do
				for _, phase in PHASES do
					for index, stroke in play(name, fps, phase) do
						local pushes = stroke.pushes
						local first = pushes[1].guard:Lerp(pushes[1].tip, CORE)
						-- The cut's way: from the first sample to the last of the stroke's first frame.
						local cut: Vector3? = nil
						for _, push in pushes do
							local point = push.guard:Lerp(push.tip, CORE)
							if push.frame == pushes[1].frame + 1 then
								break
							end
							if (point - first).Magnitude > 0.05 then
								cut = cut or (point - first)
							end
						end
						local truthWay = coreAt(name, stroke.light + 1 / 240) - coreAt(name, stroke.light)
						if cut ~= nil and truthWay.Magnitude > 1e-3 then
							local angle =
								math.deg(math.acos(math.clamp((cut :: Vector3).Unit:Dot(truthWay.Unit), -1, 1)))
							if angle >= 90 then
								error(
									("%s at %d fps (phase %.1f), stroke %d: the first segment runs %.0f degrees against the cut"):format(
										name,
										fps,
										phase,
										index,
										angle
									)
								)
							end
						end
					end
				end
			end
		end
	end)

	it("keeps the clip's true tip path on the ribbon between frames", function()
		-- Up to the ribbon's sub-step cap a frame (fx.trail.ribbon.maxSubsteps): the chords between
		-- the clip's own poses cut a fast snap's curve by a little more at 30 fps.
		local limits = { [30] = 0.35, [60] = 0.15, [144] = 0.15 }
		for _, name in { "Basic3", "RisingArc", "Vertical" } do
			local path = truth(name)
			for _, fps in { 30, 60, 144 } do
				for _, phase in PHASES do
					for index, stroke in play(name, fps, phase) do
						local worst = 0
						for sample, at in path.times do
							if at >= stroke.light and at <= stroke.lastTime then
								local best = math.huge
								for k = 2, #stroke.pushes do
									local a, b = stroke.pushes[k - 1].tip, stroke.pushes[k].tip
									best = math.min(best, segmentDistance(path.tips[sample], a, b))
								end
								worst = math.max(worst, best)
							end
						end
						if worst > limits[fps] then
							error(
								("%s at %d fps (phase %.1f), stroke %d: the true tip passes %.2f studs off the ribbon"):format(
									name,
									fps,
									phase,
									index,
									worst
								)
							)
						end
					end
				end
			end
		end
	end)
end)

--!strict
--[[
	A clip event's cues show on the first rendered frame that draws its step's pose (D-479, after
	D-342 to D-345). An event fires inside its rig's step, and a frame draws the pose its rigs' step
	of the frame before wrote (impact.poseLagFrames), while a light, a Beam, a Highlight, a sound
	or the FOV shows on the frame it is set. Routed at once, the Art's activation (blade light,
	glow, weapon flash, chime, FOV kick, riser or contour), the trail, the clip sounds (whoosh,
	voice) and the footsteps all came a frame before the pose that makes them, and the ribbon drew
	the blade a frame ahead of the one beside it.

	The real path: a real Choreo animator plays the real clips on the hit matrix's player rig, its
	events reach Replication.watch's routing, FrameClock runs on hand-driven render steps and a fake
	clock (its start at First, the rigs' step, its posed mark, the local rig's step, its end), and
	Trails runs on its own render steps (the drawn pose's at a frame's start, the pose readers').
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
local FrameClock = Harness.load("src/client/fx/FrameClock")
local FlashBudget = Harness.load("src/client/fx/FlashBudget")
local Replication = Harness.load("src/client/controllers/Replication")
local Trails = Harness.load("src/client/fx/Trails")
local TrailRibbon = Harness.load("src/client/fx/TrailRibbon")
local Engine = Harness.load("src/client/fx/Engine")
local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local ChoreoData = Harness.load("src/shared/data/choreo")
local ImpactData = Harness.load("src/shared/data/impact")
local Fx = Harness.load("src/shared/data/fx")

local LAG = ImpactData.poseLagFrames
local PREFIX = ChoreoData.locomotion.clipPrefix
local TOKEN = "TrailCyanWhite"
local LOCAL_ID, REMOTE_ID = 1, 2
local RATES = { 30, 60, 144 }
local PHASES = { 0.3, 0.9 }

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

-- The hit matrix's player avatar, drawn, its positions filled in where Lune derives none.
local function rig(): Model
	local avatar = HitMatrix.standing(Harness)
	local model = avatar.model
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", true)
	local primary = model.PrimaryPart :: BasePart
	primary.CFrame = avatar.base
	primary.Position = avatar.base.Position
	for _, item in model:GetDescendants() do
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

-- The weapon part the blade light and glow hang on (a rig's "Weapon" Model holds a "Weapon" part).
local function weaponPart(model: Model): BasePart
	for _, item in model:GetDescendants() do
		if item.Name == "Weapon" and item:IsA("BasePart") then
			return item
		end
	end
	error("the rig has no weapon part")
end

type Call = { module: string, fn: string, args: { any }, frame: number }

-- The frame being drawn: counted at each frame's start, before anything of it runs.
local frame = 0

-- FrameClock on hand-driven render steps; `frameStep` runs one rendered frame of `dt`, the remote
-- rigs stepped in the rigs' step (before the posed mark) and the local one in the controller's.
type Loop = {
	frameStep: (dt: number, remote: { any }, localRig: any?) -> (),
	peek: (() -> ())?, -- the spec's own look at the pose this frame draws, at its start
	drawnPose: any?, -- what `peek` saw
	drawn: (() -> ())?, -- Trails' drawn pose step (First + 1), when bound
	readers: (() -> ())?, -- Trails' pose readers' step (Character + 4), when bound
}

local function clockLoop(): Loop
	local hooks: { [string]: any } = {}
	local function hook(name: string)
		return function(fn: any): () -> ()
			hooks[name] = fn
			return function()
				hooks[name] = nil
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
	local loop: Loop = {} :: any
	loop.frameStep = function(dt: number, remote: { any }, localRig: any?)
		frame += 1
		clock += dt
		hooks.start(dt)
		if loop.peek ~= nil then
			(loop.peek :: () -> ())()
		end
		if loop.drawn ~= nil then
			(loop.drawn :: () -> ())()
		end
		for _, animator in remote do
			animator:step(dt)
		end
		hooks.posed(dt)
		if localRig ~= nil then
			localRig:step(dt)
		end
		if loop.readers ~= nil then
			(loop.readers :: () -> ())()
		end
		hooks.finish(dt)
	end
	return loop
end

-- Every call a fake package gets, with the frame it came on.
local function recorder(name: string, calls: { Call }): any
	return setmetatable({}, {
		__index = function(_, key: string)
			return function(...)
				table.insert(calls, { module = name, fn = key, args = { ... }, frame = frame })
			end
		end,
	})
end

-- Replication on fake packages (the trails package real when given), the two fighters' records.
local function bindReplication(calls: { Call }, records: { [number]: any }, trails: any?)
	local function none(): any
		return nil
	end
	Replication.bind({
		net = { on = function() end },
		entities = {
			get = function(id: number): any
				return records[id]
			end,
			all = function(): any
				return {}
			end,
			localChanged = { Connect = function() end },
		},
		localId = function(): number
			return LOCAL_ID
		end,
		locomotion = { attach = none },
		choreo = Choreo,
		clipLibrary = ClipLibrary,
		trails = trails or recorder("trails", calls),
		smear = recorder("smear", calls),
		shatter = recorder("shatter", calls),
		sparks = recorder("sparks", calls),
		telegraphs = recorder("telegraphs", calls),
		outline = recorder("outline", calls),
		switchRing = recorder("switchRing", calls),
		digits = recorder("digits", calls),
		hud = recorder("hud", calls),
		systemLine = recorder("systemLine", calls),
		sfx = recorder("sfx", calls),
		impact = recorder("impact", calls),
		camera = recorder("camera", calls),
		weaponCategory = function(): string
			return "OneHandedSword"
		end,
		trailToken = function(): string
			return TOKEN
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
end

local function record(id: number, model: Model): any
	return {
		id = id,
		model = model,
		kind = "Player",
		rig = "PlayerR15",
		weaponId = "TrialistSword",
		name = if id == LOCAL_ID then "Mira" else "Ren",
	}
end

type Expect = { module: string, fn: string, test: (args: { any }) -> boolean, label: string }

local function cue(module: string, fn: string, label: string, test: ((args: { any }) -> boolean)?): Expect
	return {
		module = module,
		fn = fn,
		label = label,
		test = test or function(): boolean
			return true
		end,
	}
end

local function trail(on: boolean, smear: boolean): Expect
	return cue(
		"trails",
		"setActive",
		("trail %s%s"):format(if on then "on" else "off", if smear then " (smear)" else ""),
		function(args)
			return args[2] == on and (args[3] == "Smear") == smear
		end
	)
end

local function light(on: boolean): Expect
	return cue("trails", "activationLight", if on then "blade light on" else "blade light off", function(args)
		return args[2] == on
	end)
end

-- What each clip event shows, by kind.
local function cuesOf(event: any, isLocal: boolean): { Expect }
	local kind = event.kind
	if kind == "ActivationHold" then
		local list = {
			light(true),
			cue("sfx", "play", "chime", function(args)
				return args[1] == "artChime." .. TOKEN
			end),
			cue("impact", "activation", if isLocal then "contour" else "riser"),
		}
		if isLocal then
			table.insert(list, cue("camera", "fovKick", "FOV kick"))
		end
		return list
	elseif kind == "Sfx" or kind == "Voice" then
		local name = event.data.name
		return {
			cue("sfx", "play", name, function(args)
				return args[1] == name
			end),
		}
	elseif kind == "TrailOn" then
		return { trail(true, false) }
	elseif kind == "HitWindowOpen" then
		return { trail(true, false), light(false) }
	elseif kind == "SmearOn" then
		return {
			trail(true, true),
			cue("smear", "apply", "smear on", function(args)
				return args[2] == true
			end),
		}
	elseif kind == "SmearOff" then
		return {
			trail(false, true),
			cue("smear", "apply", "smear off", function(args)
				return args[2] == false
			end),
		}
	elseif kind == "HitWindowClose" or kind == "TrailOff" then
		return { trail(false, false) }
	elseif kind == "PostMotionStart" then
		return { light(false), trail(false, false) }
	elseif kind == "Footstep" then
		return { cue("sfx", "footstep", "footstep") }
	end
	return {}
end

-- Plays `name` on a fighter (the local one or a remote one) at `fps`, its first frame `phase` of a
-- frame long, for `seconds`: the events its steps crossed (with the frame each fired on) and every
-- call the packages got.
local function play(name: string, fps: number, phase: number, isLocal: boolean, seconds: number): ({ any }, { Call })
	local calls: { Call } = {}
	local model = rig()
	local fighter = record(if isLocal then LOCAL_ID else REMOTE_ID, model)
	bindReplication(calls, { [fighter.id] = fighter })
	local loop = clockLoop()
	Replication.watch(fighter)
	local animator: any = Choreo.get(model)
	local fired: { any } = {}
	animator.events:Connect(function(_clipId: string, event: any, jumped: boolean?)
		table.insert(fired, { event = event, frame = frame, jumped = jumped == true })
	end)
	local ok, err = pcall(function()
		animator:play(PREFIX .. name)
		local dt = 1 / fps
		local count = math.ceil(seconds * fps) + LAG + 2
		for index = 1, count do
			local step = if index == 1 then dt * phase else dt
			if isLocal then
				loop.frameStep(step, {}, animator)
			else
				loop.frameStep(step, { animator }, nil)
			end
		end
	end)
	Replication.unwatch(fighter)
	Choreo.release(model)
	FrameClock.bind(nil)
	if not ok then
		error(err, 0)
	end
	return fired, calls
end

-- Each fired event's cues, matched in order to the calls: every one on the frame its step's pose
-- is first drawn (the step's frame + poseLagFrames). Returns the problems found.
local function misplaced(fired: { any }, calls: { Call }, isLocal: boolean): { string }
	local used: { [number]: boolean } = {}
	local problems: { string } = {}
	for _, item in fired do
		if item.jumped then
			continue
		end
		local drawnOn = item.frame + LAG
		for _, want in cuesOf(item.event, isLocal) do
			local found: Call? = nil
			for index, call in calls do
				if not used[index] and call.module == want.module and call.fn == want.fn and want.test(call.args) then
					used[index] = true
					found = call
					break
				end
			end
			if found == nil then
				table.insert(problems, ("%s @%.3f: no %s"):format(item.event.kind, item.event.time, want.label))
			elseif (found :: Call).frame ~= drawnOn then
				table.insert(
					problems,
					("%s @%.3f: %s on frame %d, its pose first drawn on %d"):format(
						item.event.kind,
						item.event.time,
						want.label,
						(found :: Call).frame,
						drawnOn
					)
				)
			end
		end
	end
	return problems
end

describe("a clip event's cues show on the first frame that draws its pose (D-479)", function()
	it(
		"an Art's activation, its sounds, trail, smear and light out, local and remote, at 30, 60 and 144 fps",
		function()
			local report: { string } = {}
			for _, isLocal in { true, false } do
				for _, fps in RATES do
					for _, phase in PHASES do
						local fired, calls = play("Vertical", fps, phase, isLocal, 0.7)
						expect(#fired).toBeGreaterThan(8)
						for _, problem in misplaced(fired, calls, isLocal) do
							table.insert(
								report,
								("%s %d fps phase %.1f: %s"):format(
									if isLocal then "local" else "remote",
									fps,
									phase,
									problem
								)
							)
						end
					end
				end
			end
			if #report > 0 then
				error(("%d cues off their drawn frame:\n%s"):format(#report, table.concat(report, "\n")))
			end
		end
	)

	it("footsteps sound on the frame that draws the foot down, local and remote", function()
		local report: { string } = {}
		for _, isLocal in { true, false } do
			for _, fps in RATES do
				for _, phase in PHASES do
					local fired, calls = play("Run", fps, phase, isLocal, 1.3)
					local steps = 0
					for _, item in fired do
						if item.event.kind == "Footstep" then
							steps += 1
						end
					end
					expect(steps).toBeGreaterThanOrEqual(3)
					for _, problem in misplaced(fired, calls, isLocal) do
						table.insert(
							report,
							("%s %d fps phase %.1f: %s"):format(
								if isLocal then "local" else "remote",
								fps,
								phase,
								problem
							)
						)
					end
				end
			end
		end
		if #report > 0 then
			error(("%d footsteps off their drawn frame:\n%s"):format(#report, table.concat(report, "\n")))
		end
	end)

	it(
		"a late start's skipped sounds and hold play on the first frame that draws the clip, from where it is there",
		function()
			local clip = ClipLibrary.get(PREFIX .. "Vertical")
			local holdAt, whooshAt = math.huge, math.huge
			for _, event in clip.events do
				if event.kind == "ActivationHold" then
					holdAt = math.min(holdAt, event.time)
				elseif event.kind == "Sfx" then
					whooshAt = math.min(whooshAt, event.time)
				end
			end
			for _, fps in RATES do
				local calls: { Call } = {}
				local model = rig()
				local fighter = record(REMOTE_ID, model)
				bindReplication(calls, { [REMOTE_ID] = fighter })
				local loop = clockLoop()
				Replication.watch(fighter)
				local animator: any = Choreo.get(model)
				local dt = 1 / fps
				local ok, err = pcall(function()
					for _ = 1, 3 do
						loop.frameStep(dt, { animator }, nil)
					end
					-- The word arrives between frames, 0.25 s after the server started the clip.
					local heardOn = frame
					Replication.dispatch(
						"ActionStarted",
						{ entityId = REMOTE_ID, clipId = PREFIX .. "Vertical", serverTime = clock - 0.25, speed = 1 }
					)
					local handle = animator.mixer:find(PREFIX .. "Vertical")
					expect(handle).never.toBeNil()
					-- The next frame's rigs' step writes the clip's first pose; the one after draws it.
					loop.frameStep(dt, { animator }, nil)
					local shown = handle.time
					loop.frameStep(dt, { animator }, nil)
					loop.frameStep(dt, { animator }, nil)
					local drawnOn = heardOn + 1 + LAG
					local function only(fn: string, test: (args: { any }) -> boolean): Call
						local found: { Call } = {}
						for _, call in calls do
							if call.fn == fn and test(call.args) then
								table.insert(found, call)
							end
						end
						expect(#found).toBe(1)
						return found[1]
					end
					local chime = only("playLate", function(args)
						return args[1] == "artChime." .. TOKEN
					end)
					local whoosh = only("playLate", function(args)
						return args[1] == "whoosh.Large"
					end)
					local lit = only("activationLight", function(args)
						return args[2] == true
					end)
					local riser = only("activation", function()
						return true
					end)
					for _, call in { chime, whoosh, lit, riser } do
						if call.frame ~= drawnOn then
							error(
								("%d fps: %s %s on frame %d, the clip first drawn on %d"):format(
									fps,
									call.fn,
									tostring(call.args[1]),
									call.frame,
									drawnOn
								)
							)
						end
					end
					-- From where the clip stands on that frame: the pose the step before it wrote.
					expect(chime.args[2]).toBeCloseTo(shown - holdAt, 1e-6)
					expect(whoosh.args[2]).toBeCloseTo(shown - whooshAt, 1e-6)
					expect(riser.args[6]).toBeCloseTo(shown - holdAt, 1e-6)
				end)
				Replication.unwatch(fighter)
				Choreo.release(model)
				FrameClock.bind(nil)
				if not ok then
					error(err, 0)
				end
			end
		end
	)
end)

-- ---------------------------------------------------------------------------------------------
-- The real Trails: the ribbon, the light, the glow and the flash
-- ---------------------------------------------------------------------------------------------

-- `segment`: the ribbon kept it joined to the sample before (a Beam between them shows).
type Push = { tip: Vector3, frame: number, segment: boolean }
type Shown = { light: boolean, glow: boolean, flash: boolean, flashBudget: number }

-- Plays `name` through Replication into the real Trails at `fps`: each frame's ribbon pushes, the
-- blade each frame draws (the Transforms its start held, D-342, on the root as it stands), what
-- the weapon showed at each frame's end, and the frames the window's events fired on.
local function playTrails(
	name: string,
	fps: number,
	phase: number,
	isLocal: boolean
): ({ Push }, { [number]: Vector3 }, { [number]: Shown }, { any })
	local calls: { Call } = {}
	local model = rig()
	local fighter = record(if isLocal then LOCAL_ID else REMOTE_ID, model)
	local loop = clockLoop()
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
			loop.readers = function()
				fn(0)
			end
			return function()
				loop.readers = nil
			end
		end,
		onDrawn = function(fn: (dt: number) -> ()): () -> ()
			loop.drawn = function()
				fn(0)
			end
			return function()
				loop.drawn = nil
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
	bindReplication(calls, { [fighter.id] = fighter }, Trails)
	Replication.watch(fighter)
	local animator: any = Choreo.get(model)
	local fired: { any } = {}
	animator.events:Connect(function(_clipId: string, event: any)
		table.insert(fired, { event = event, frame = frame })
	end)
	local pushes: { Push } = {}
	local drawnTips: { [number]: Vector3 } = {}
	local shown: { [number]: Shown } = {}
	local realPush = TrailRibbon.push
	TrailRibbon.push = function(ribbon: any, guard: Vector3, tip: Vector3, born: number, joined: boolean): boolean
		local push: Push = { tip = tip, frame = frame, segment = false }
		table.insert(pushes, push)
		local kept = realPush(ribbon, guard, tip, born, joined)
		push.segment = kept and joined
		return kept
	end
	local weapon = weaponPart(model)
	local chain = BladeContact.chain(model :: any) :: any
	-- The blade this frame draws: the Transforms as it starts, before any rig steps.
	loop.peek = function()
		loop.drawnPose = BladeContact.read(chain)
	end
	local ok, err = pcall(function()
		animator:play(PREFIX .. name)
		local dt = 1 / fps
		for index = 1, math.ceil(0.9 * fps) do
			local step = if index == 1 then dt * phase else dt
			if isLocal then
				loop.frameStep(step, {}, animator)
			else
				loop.frameStep(step, { animator }, nil)
			end
			local pose = loop.drawnPose
			if pose ~= nil then
				pose.root = chain.root.CFrame
				local _, tip = BladeContact.blade(chain, pose)
				drawnTips[frame] = tip
			end
			local glowOn = false
			for _, child in weapon:GetChildren() do
				if
					child:IsA("Beam")
					and child.Name:find(Fx.activationLight.glow.name, 1, true) == 1
					and child.Enabled
				then
					glowOn = true
				end
			end
			local flash = weapon:FindFirstChild(Fx.activationLight.flashName)
			local pointLight = weapon:FindFirstChildOfClass("PointLight")
			shown[frame] = {
				light = pointLight ~= nil and pointLight.Enabled,
				glow = glowOn,
				flash = flash ~= nil and (flash :: Highlight).Enabled,
				flashBudget = FlashBudget.used(clock),
			}
		end
	end)
	TrailRibbon.push = realPush
	Replication.unwatch(fighter)
	Trails.bind(nil)
	Trails.reset()
	Engine.setViewer(nil)
	Engine.setClock(nil)
	Choreo.release(model)
	FrameClock.bind(nil)
	if not ok then
		error(err, 0)
	end
	return pushes, drawnTips, shown, fired
end

local function firstFired(fired: { any }, kind: string): any
	for _, item in fired do
		if item.event.kind == kind then
			return item
		end
	end
	return nil
end

describe("the trail and the blade light on the frames that draw them (D-479)", function()
	it("lights the ribbon on the window's first drawn frame, its head on the blade that frame draws", function()
		local report: { string } = {}
		for _, name in { "Basic1", "Vertical" } do
			for _, isLocal in { true, false } do
				for _, fps in RATES do
					for _, phase in PHASES do
						local pushes, drawnTips, _, fired = playTrails(name, fps, phase, isLocal)
						local label = ("%s %s %d fps phase %.1f"):format(
							name,
							if isLocal then "local" else "remote",
							fps,
							phase
						)
						local on = firstFired(fired, "TrailOn")
						local off = firstFired(fired, "TrailOff")
						expect(on).never.toBeNil()
						expect(off).never.toBeNil()
						expect(#pushes).toBeGreaterThan(0)
						local first, last = pushes[1].frame, pushes[#pushes].frame
						if first ~= on.frame + LAG then
							table.insert(
								report,
								("%s: the ribbon lit on frame %d, the window's first drawn frame is %d"):format(
									label,
									first,
									on.frame + LAG
								)
							)
						end
						-- The stroke may end sooner, where the drawn tip turns back (D-335), never after the
						-- window's last drawn frame.
						if last > off.frame + LAG - 1 then
							table.insert(
								report,
								("%s: the ribbon's last push on frame %d, after the window's last drawn frame %d"):format(
									label,
									last,
									off.frame + LAG - 1
								)
							)
						end
						-- Each frame's newest sample is the tip that frame draws.
						local worst, at = 0, 0
						for index, push in pushes do
							local nextPush = pushes[index + 1]
							if nextPush == nil or nextPush.frame ~= push.frame then
								local drawn = drawnTips[push.frame]
								if drawn ~= nil then
									local gap = (push.tip - drawn).Magnitude
									if gap > worst then
										worst, at = gap, push.frame
									end
								end
							end
						end
						if worst > 1e-3 then
							table.insert(
								report,
								("%s: the ribbon's head %.3f studs off the drawn tip on frame %d"):format(
									label,
									worst,
									at
								)
							)
						end
					end
				end
			end
		end
		if #report > 0 then
			error(("%d ribbon frames off the drawn blade:\n%s"):format(#report, table.concat(report, "\n")))
		end
	end)

	it(
		"puts the blade light, glow and weapon flash up on the hold's first drawn frame, the flash for its frames, spending no flash budget",
		function()
			local report: { string } = {}
			for _, isLocal in { true, false } do
				for _, fps in RATES do
					for _, phase in PHASES do
						local _, _, shown, fired = playTrails("Vertical", fps, phase, isLocal)
						local label = ("%s %d fps phase %.1f"):format(if isLocal then "local" else "remote", fps, phase)
						local hold = firstFired(fired, "ActivationHold")
						local open = firstFired(fired, "HitWindowOpen")
						expect(hold).never.toBeNil()
						expect(open).never.toBeNil()
						local lit = hold.frame + LAG
						local out = open.frame + LAG
						local flashFrames = 0
						for at, state in shown do
							local wantLight = at >= lit and at < out
							if state.light ~= wantLight or state.glow ~= wantLight then
								table.insert(
									report,
									("%s: frame %d light %s glow %s, wanted %s (hold drawn from %d, window from %d)"):format(
										label,
										at,
										tostring(state.light),
										tostring(state.glow),
										tostring(wantLight),
										lit,
										out
									)
								)
							end
							if state.flash then
								flashFrames += 1
								if at < lit then
									table.insert(
										report,
										("%s: the weapon flash on frame %d, before the hold's %d"):format(
											label,
											at,
											lit
										)
									)
								end
							end
							-- The weapon's flash is a Highlight slot, not a screen flash: FlashBudget (3 a
							-- second) counts the same flashes as before, none of them this.
							if state.flashBudget ~= 0 then
								table.insert(
									report,
									("%s: the flash budget spent %s on frame %d"):format(
										label,
										tostring(state.flashBudget),
										at
									)
								)
							end
						end
						if flashFrames ~= Fx.activationLight.flashFrames then
							table.insert(
								report,
								("%s: the weapon flash showed on %d frames, wanted %d"):format(
									label,
									flashFrames,
									Fx.activationLight.flashFrames
								)
							)
						end
					end
				end
			end
			if #report > 0 then
				error(("%d light frames off:\n%s"):format(#report, table.concat(report, "\n")))
			end
		end
	)

	it("hands the light to the ribbon: a window drawn a hair past its open keeps it to the first segment", function()
		-- At 60 fps Vertical's open (0.35 s) is 21 frames in, so a clip on the frame grid crosses it
		-- by a sliver: the snap's first 0.1 ms moves the tip under trail.minLength (0.05), and the
		-- window's first drawn frame lit the ribbon with no segment while the light and glow went
		-- out (the PC's V467_60_air1 row 63: TrailLit true, 0 Beams, the light out). Before: the
		-- light out on that frame, the first segment the next. Now the light goes out on the frame
		-- the first segment shows (D-558), and a window whose first frame lays one is unchanged.
		local report: { string } = {}
		for _, isLocal in { true, false } do
			for _, delta in { 0, 1e-5, 5e-5, 1e-3 } do
				local phase = math.max(delta * 60, 1e-9)
				local pushes, _, shown, fired = playTrails("Vertical", 60, phase, isLocal)
				local label = ("%s, crossed %.5f s past the open"):format(if isLocal then "local" else "remote", delta)
				local open = firstFired(fired, "HitWindowOpen")
				expect(open).never.toBeNil()
				local firstSegment: number? = nil
				for _, push in pushes do
					if push.segment and firstSegment == nil then
						firstSegment = push.frame
					end
				end
				expect({ label, firstSegment ~= nil }).toEqual({ label, true })
				local windowDrawn = open.frame + LAG
				local out = firstSegment :: number
				-- A sliver past the open lays the first segment a frame later; a millisecond lays it at once.
				local wantOut = if delta < 1e-4 then windowDrawn + 1 else windowDrawn
				if out ~= wantOut then
					table.insert(
						report,
						("%s: first segment on frame %d, wanted %d (the window's first drawn frame %d)"):format(
							label,
							out,
							wantOut,
							windowDrawn
						)
					)
				end
				for at = windowDrawn - 1, out + 1 do
					local state = shown[at]
					local want = at < out
					if state ~= nil and (state.light ~= want or state.glow ~= want) then
						table.insert(
							report,
							("%s: frame %d light %s glow %s, wanted %s (window drawn from %d, first segment %d)"):format(
								label,
								at,
								tostring(state.light),
								tostring(state.glow),
								tostring(want),
								windowDrawn,
								out
							)
						)
					end
				end
			end
		end
		if #report > 0 then
			error(("%d light frames off the ribbon's first segment:\n%s"):format(#report, table.concat(report, "\n")))
		end
	end)

	it(
		"a cancel between the hold's step and its drawn frame leaves the blade dark (no light, glow or chime)",
		function()
			local calls: { Call } = {}
			local model = rig()
			local fighter = record(REMOTE_ID, model)
			local loop = clockLoop()
			Trails.start()
			Trails.bind({
				now = function(): number
					return clock
				end,
				onRender = function(_fn: (dt: number) -> ()): () -> ()
					return function() end
				end,
				onWatch = function(fn: (dt: number) -> ()): () -> ()
					loop.readers = function()
						fn(1 / 60)
					end
					return function() end
				end,
				clear = function(_trail: Trail) end,
			})
			bindReplication(calls, { [REMOTE_ID] = fighter }, Trails)
			Replication.watch(fighter)
			local animator: any = Choreo.get(model)
			local weapon = weaponPart(model)
			local ok, err = pcall(function()
				animator:play(PREFIX .. "Vertical")
				local held = false
				animator.events:Connect(function(_clipId: string, event: any)
					if event.kind == "ActivationHold" then
						held = true
					end
				end)
				for _ = 1, 60 do
					loop.frameStep(1 / 60, { animator }, nil)
					if held then
						break
					end
				end
				expect(held).toBe(true)
				-- The hold is taken back after its step, before the frame that would draw it lit.
				Trails.activationLight(model, false, TOKEN, true)
				for _ = 1, 30 do
					loop.frameStep(1 / 60, {}, nil)
				end
				local pointLight = weapon:FindFirstChildOfClass("PointLight")
				expect(pointLight ~= nil and pointLight.Enabled).toBe(false)
				for _, child in weapon:GetChildren() do
					if child:IsA("Beam") and child.Name:find(Fx.activationLight.glow.name, 1, true) == 1 then
						expect(child.Enabled).toBe(false)
					end
				end
				for _, call in calls do
					expect(call.fn == "play" and call.args[1] == "artChime." .. TOKEN).toBe(false)
				end
			end)
			Replication.unwatch(fighter)
			Trails.bind(nil)
			Trails.reset()
			Choreo.release(model)
			FrameClock.bind(nil)
			if not ok then
				error(err, 0)
			end
		end
	)
end)

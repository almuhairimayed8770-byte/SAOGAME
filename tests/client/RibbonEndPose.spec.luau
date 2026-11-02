--!strict
--[[
	The ribbon ends on the frame that shows its stroke's end pose (D-539, AG 383 and 384; 382(e):
	"no new ribbon segment appears after the frame that shows the stroke's end pose"). The end pose
	is where the stroke's strike snap lands (ClipSampler.strikeLandingAt: Vertical's at 0.4 s, its
	window 0.35 to 0.48). Before, the window's ribbon kept sampling the blade through the strike's
	hold and the settle after it until HitWindowClose: one more segment after the end pose at 30
	and 60 fps, two at 144, on the caster's own rig and on a remote one, with or without a hit's
	freeze at or before the landing (the PC saw +2 on the frame after the hit-stop at 30, +4 in the
	settle at 144 and +4 after the end pose on the watcher at 60).

	The real path: the hit matrix's player rig, a real Choreo animator playing the real clip, its
	events through Replication.watch's routing (atStepPose on the real FrameClock), and the real
	Trails and TrailRibbon on their render steps (the drawn pose's at a frame's start, the pose
	readers' after the rigs' step), on hand-driven frames and a fake clock. A hit's freeze is the
	animator's own hitStop (what Replication's HitConfirmed asks for), from the frame the clip
	crosses the contact time, or `word` frames after it on a remote rig.
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
local Replication = Harness.load("src/client/controllers/Replication")
local Trails = Harness.load("src/client/fx/Trails")
local TrailRibbon = Harness.load("src/client/fx/TrailRibbon")
local Engine = Harness.load("src/client/fx/Engine")
local ChoreoData = Harness.load("src/shared/data/choreo")
local combat = Harness.load("src/shared/data/combat")

local PREFIX = ChoreoData.locomotion.clipPrefix
local TOKEN = "TrailCyanWhite"
local LOCAL_ID, REMOTE_ID = 1, 2
local RATES = { 30, 60, 144 }
local PHASES = { 0.3, 0.9 }
local FREEZE = combat.hitStopFrames.Normal

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

type Loop = {
	frameStep: (dt: number, remote: { any }, localRig: any?) -> (),
	drawn: (() -> ())?, -- Trails' drawn pose step (First + 1)
	readers: (() -> ())?, -- Trails' pose readers' step (Character + 4)
}

-- The frame being drawn: counted at each frame's start, before anything of it runs.
local frame = 0

-- FrameClock on hand-driven render steps; `frameStep` runs one rendered frame of `dt`, the remote
-- rigs stepped in the rigs' step (before the posed mark) and the local one in the controller's.
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

local function recorder(): any
	return setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
end

local function bindReplication(fighter: any)
	Replication.bind({
		net = { on = function() end },
		entities = {
			get = function(id: number): any
				return if id == fighter.id then fighter else nil
			end,
			all = function(): any
				return {}
			end,
			localChanged = { Connect = function() end },
		},
		localId = function(): number
			return LOCAL_ID
		end,
		locomotion = {
			attach = function(): any
				return nil
			end,
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

type Swing = {
	endFrame: number?, -- the first frame that shows the clip at its end pose or past it
	lastFrame: number?, -- the last frame the ribbon added a segment on
	segments: number, -- the segments the swing added
	after: number, -- those added on frames after endFrame
}

-- Plays `name` on the local fighter or a remote one at `fps` (its first frame `phase` of a frame
-- long) for 0.9 s; with a `contact` time, the hit's freeze comes `word` frames after the frame
-- whose step crossed it. `landing` is the clip time of the stroke's end pose.
local function swing(
	name: string,
	landing: number,
	fps: number,
	phase: number,
	isLocal: boolean,
	contact: number?,
	word: number
): Swing
	local model = rig()
	local fighter = {
		id = if isLocal then LOCAL_ID else REMOTE_ID,
		model = model,
		kind = "Player",
		rig = "PlayerR15",
		weaponId = "TrialistSword",
		name = if isLocal then "Mira" else "Ren",
	}
	local loop = clockLoop()
	Engine.setViewer(function(): Vector3
		return (model.PrimaryPart :: BasePart).Position + Vector3.new(0, 2, 12)
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
		animator = function(target: Instance): any
			return Choreo.find(target :: any)
		end,
	})
	bindReplication(fighter)
	Replication.watch(fighter)
	local animator: any = Choreo.get(model)
	local added: { [number]: number } = {}
	local realPush = TrailRibbon.push
	TrailRibbon.push = function(ribbon: any, guard: Vector3, tip: Vector3, born: number, joined: boolean): boolean
		local ok = realPush(ribbon, guard, tip, born, joined)
		if ok then
			added[frame] = (added[frame] or 0) + 1
		end
		return ok
	end
	local result: Swing = { endFrame = nil, lastFrame = nil, segments = 0, after = 0 }
	local ok, err = pcall(function()
		local handle = animator:play(PREFIX .. name)
		local dt = 1 / fps
		local crossed: number? = nil
		local frozen = false
		-- The clip clock each frame shows: its rig's step of the frame before (poseLagFrames 1).
		local shown: { [number]: number } = {}
		local first = frame + 1
		for index = 1, math.ceil(0.9 * fps) do
			shown[frame + 1] = handle.time
			local before = handle.time
			local step = if index == 1 then dt * phase else dt
			if isLocal then
				loop.frameStep(step, {}, animator)
			else
				loop.frameStep(step, { animator }, nil)
			end
			if contact ~= nil and crossed == nil and before < contact and handle.time >= contact then
				crossed = frame
			end
			if crossed ~= nil and not frozen and frame - (crossed :: number) >= word then
				frozen = true
				animator:hitStop(FREEZE)
			end
		end
		for f = first, frame do
			if result.endFrame == nil and shown[f] ~= nil and shown[f] >= landing - 1e-9 then
				result.endFrame = f
			end
			local count = added[f] or 0
			if count > 0 then
				result.segments += count
				result.lastFrame = f
				if result.endFrame ~= nil and f > (result.endFrame :: number) then
					result.after += count
				end
			end
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
	return result
end

local function check(label: string, result: Swing)
	expect({ label, result.endFrame ~= nil, result.segments > 0 }).toEqual({ label, true, true })
	-- Its last segment is on the frame that shows the end pose; none after.
	expect({ label, result.after, result.lastFrame }).toEqual({ label, 0, result.endFrame })
end

describe("Trails: the ribbon ends on the frame that shows the stroke's end pose (D-539)", function()
	local VERTICAL_LANDING = 0.4

	it("on the caster's own rig at 30, 60 and 144, with no hit or a hit's freeze at 0.37 to 0.4 s", function()
		-- Before: +1 segment after the end pose at 30 and 60 fps, +2 at 144 (no hit at 30: 0).
		for _, fps in RATES do
			for _, phase in PHASES do
				for _, contact in { false, 0.37, 0.39, 0.4 } do
					local at = if contact == false then nil else contact :: number
					local result = swing("Vertical", VERTICAL_LANDING, fps, phase, true, at, 0)
					check(("local %d fps phase %.1f contact %s"):format(fps, phase, tostring(contact)), result)
				end
			end
		end
	end)

	it("on a remote rig at 30, 60 and 144, its hit's freeze 0 to 6 frames after the contact", function()
		-- Before: +1 at 60, +2 at 144 (30: 0).
		for _, fps in RATES do
			for _, phase in PHASES do
				for _, word in { 0, 2, 4, 6 } do
					local result = swing("Vertical", VERTICAL_LANDING, fps, phase, false, 0.38, word)
					check(("remote %d fps phase %.1f word +%d"):format(fps, phase, word), result)
				end
				check(
					("remote %d fps phase %.1f, no hit"):format(fps, phase),
					swing("Vertical", VERTICAL_LANDING, fps, phase, false, nil, 0)
				)
			end
		end
	end)

	it("a basic's ribbon ends where its snap lands too (Basic1 at 0.15 s)", function()
		for _, fps in RATES do
			for _, phase in PHASES do
				for _, isLocal in { true, false } do
					local result = swing("Basic1", 0.15, fps, phase, isLocal, nil, 0)
					check(
						("Basic1 %s %d fps phase %.1f"):format(if isLocal then "local" else "remote", fps, phase),
						result
					)
				end
			end
		end
	end)
end)

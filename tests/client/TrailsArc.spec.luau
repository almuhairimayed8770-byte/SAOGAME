--!strict
--[[
	The Art trail reads as an arc at the blade's height that sweeps round the body and goes soon
	after the cut (D-335; shot 2, art-horizontal, filmed from the staged Side camera).

	On the real player rig (the hit matrix's avatar posed by a real Choreo animator) Horizontal plays
	at 60 fps, its clip events routed to Trails.setActive as Replication.routeClipEvent routes them.
	The Side camera is laid as CameraController lays a staged view (CameraMath: the middle of the
	player and a kobold 3.5 studs ahead, 90 degrees round from the line between them, at the rest
	field of view). The ribbon's Beams face the camera; a horizontal cut is seen almost edge-on
	from there, so each Beam's width stands straight up on the screen.

	Before: the band was 2.16 studs (247 to 269 px at 1080p) tall for 16 frames, its lower edge
	down to the floor (-0.04 studs), and the blade's settle after the cut laid fresh full-width
	samples back over the cut's end for 3 more frames.

	A rig's first swing (shot 9, kill-shatter: Basic1) draws from its first frame too (D-273, D-336).
	In play nothing attaches a rig to Trails ahead of its first trail event: Trails.setActive
	attaches it on the frame its TrailOn fires, so that frame has no pose from the frame before.
	Before: its first Beam showed a frame late at 30, 60 and 144 fps, the cut's first frame of arc
	was missing, and the stroke (with no clip to follow) drew the settle after the cut.
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
local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local ChoreoData = Harness.load("src/shared/data/choreo")
local CameraData = Harness.load("src/shared/data/camera")
local CameraMath = Harness.load("src/client/camera/CameraMath")
local Dev = Harness.load("src/shared/data/dev")
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
local LIGHTS = { TrailOn = "Art", HitWindowOpen = "Art", SmearOn = "Smear" }
local OUTS = { TrailOff = "Art", HitWindowClose = "Art", SmearOff = "Smear" }
local FPS = 60
local SCREEN_HEIGHT = 1080
-- Shot 2 (art-horizontal): the kobold stands this far ahead, the camera on this side of the line.
local SHOT = "art-horizontal"
-- The cut is over on the first frame its tip moves less than this after the window opened.
local STOPPED = 0.25

-- The bars (studs, pixels at 1080p, frames at 60 fps).
local FLOOR_GAP = 0.25 -- the band's lower edge above the floor, every frame
local BAND_PIXELS_STOPPED = 100 -- the band's height on screen once the cut has stopped
local FRAMES_AFTER_STOP = 8 -- the last Beam shows at most this many frames after the cut stops
local ARC_DEGREES = 120 -- the stroke sweeps at least this far round the body
local REACH = 3 -- at the blade's reach: every point at least this far from the root's axis

local function shotOf(id: string): any
	for _, shot in Dev.capture.shots do
		if shot.id == id then
			return shot
		end
	end
	error("no shot " .. id)
end

local function vec(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

local function toVector(v: { number }): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

type Options = {
	fps: number?, -- FPS unless given
	lazy: boolean?, -- no Trails.attach ahead of the swing: its first setActive attaches the rig
}

type Take = {
	floor: number, -- the field's top
	start: CFrame, -- the root where the take starts
	camera: CFrame,
	focal: number, -- pixels per stud at one stud's depth, 1080p
	frames: { Frame },
	opened: number?, -- the frame the window opened on
	stopped: number?, -- the first frame after it whose tip moved under STOPPED
	pushedAfterStop: number, -- samples the ribbon kept after the cut stopped
}

type End = { point: Vector3, width: number }
type Frame = { ends: { End }, beams: number }

-- Plays `name` at FPS on the real path and records, per rendered frame, the Body layer's Beam ends
-- (world point and width) and how many Beams show on any layer. A TrailOn's data.kind picks the
-- trail kind, as Replication.resolveTrailKind does.
local function play(name: string, options: Options?): Take
	local fps = if options ~= nil and options.fps ~= nil then options.fps else FPS
	local lazy = options ~= nil and options.lazy == true
	local shot = shotOf(SHOT)
	local enemy = shot.stage.enemies[1]
	local avatar, field = HitMatrix.standing(Harness)
	local half = field.Size * 0.5
	local floor = field.CFrame.Position.Y
		+ math.abs(field.CFrame.UpVector.Y) * half.Y
		+ math.abs(field.CFrame.RightVector.Y) * half.X
		+ math.abs(field.CFrame.LookVector.Y) * half.Z
	local model = avatar.model
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", true)
	local primary = model.PrimaryPart :: BasePart
	primary.CFrame = avatar.base
	primary.Position = avatar.base.Position
	for _, item in model:GetDescendants() do
		-- Lune derives neither Position from CFrame nor WorldPosition; the trail's budget and the
		-- tip ring read them.
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

	-- The staged camera as CameraController lays it (CameraMath, dev.luau capture.cameras).
	local view = Dev.capture.cameras[shot.camera]
	local player = avatar.base.Position
	local target = player + avatar.base.LookVector * enemy.distance
	local anchor = CameraMath.stageAnchor(view.anchor, vec(player), vec(target))
	local reference = CameraMath.stageReference(view.reference, view.anchor, vec(player), vec(target), nil)
	assert(reference ~= nil, "the Side view has a reference")
	local bearing = (reference :: number) + shot.cameraSide * view.degrees
	local cameraAt = toVector(CameraMath.twoShotCamera(anchor, bearing, view.distance, view.height))
	local aim = toVector(CameraMath.twoShotLook(vec(player), vec(target), view.focusBias, view.lookHeight))
	local camera = CFrame.lookAt(cameraAt, aim)
	local focal = (SCREEN_HEIGHT / 2) / math.tan(math.rad(CameraData.fov.rest / 2))

	local renderFn: ((dt: number) -> ())? = nil
	Engine.setViewer(function(): Vector3
		return cameraAt
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
	if not lazy then
		Trails.attach(model)
	end
	local animator: any = Choreo.get(model)
	local take: Take = {
		floor = floor,
		start = avatar.base,
		camera = camera,
		focal = focal,
		frames = {},
		opened = nil,
		stopped = nil,
		pushedAfterStop = 0,
	}
	local frame = 0
	animator.events:Connect(function(_id: string, event: any, _jumped: boolean)
		local named = if typeof(event.data) == "table" then event.data.kind else nil
		local kind = LIGHTS[event.kind]
		if kind ~= nil then
			take.opened = take.opened or frame
			Trails.setActive(model, true, (if kind ~= "Smear" and named ~= nil then named else kind) :: any)
		end
		local off = OUTS[event.kind]
		if off ~= nil then
			Trails.setActive(model, false, (if off ~= "Smear" and named ~= nil then named else off) :: any)
		end
	end)
	local realPush = TrailRibbon.push
	TrailRibbon.push = function(ribbon: any, guard: Vector3, tip: Vector3, born: number, joined: boolean): boolean
		local kept = realPush(ribbon, guard, tip, born, joined)
		if kept and take.stopped ~= nil and frame > (take.stopped :: number) then
			take.pushedAfterStop += 1
		end
		return kept
	end
	local chain = BladeContact.chain(model :: any) :: any
	local clipId = PREFIX .. name
	local ok, err = pcall(function()
		animator:play(clipId)
		local dt = 1 / fps
		local lastTip: Vector3? = nil
		for index = 1, 600 do
			frame = index
			clock += dt
			animator:step(dt)
			local handle = animator.mixer:find(clipId)
			local _, tip = BladeContact.blade(chain, BladeContact.read(chain))
			local moved = if lastTip ~= nil then (tip - lastTip :: Vector3).Magnitude else math.huge
			lastTip = tip
			if take.opened ~= nil and index > (take.opened :: number) and take.stopped == nil and moved < STOPPED then
				take.stopped = index
			end
			assert(renderFn ~= nil, "Trails connected no render step");
			(renderFn :: (dt: number) -> ())(dt)
			local record: Frame = { ends = {}, beams = 0 }
			local ribbon = Trails.ribbonOf(model)
			if ribbon ~= nil then
				for layer, beams in ribbon.beams do
					record.beams += #beams
					if layer == 1 then
						for _, beam in beams do
							for _, pair in { { beam.Attachment0, beam.Width0 }, { beam.Attachment1, beam.Width1 } } do
								local attachment = pair[1] :: Attachment
								table.insert(record.ends, {
									point = ribbon.host.Position + attachment.Position,
									width = pair[2] :: number,
								})
							end
						end
					end
				end
			end
			take.frames[index] = record
			if (handle == nil or handle.done) and record.beams == 0 then
				break
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
	return take
end

-- How tall an end's width stands on the screen at 1080p (the Beam faces the camera).
local function pixels(take: Take, at: End): number
	local depth = -take.camera:PointToObjectSpace(at.point).Z
	return at.width * take.focal / math.max(depth, 1e-3)
end

local horizontal: Take? = nil
local function horizontalTake(): Take
	if horizontal == nil then
		horizontal = play("Horizontal")
	end
	return horizontal :: Take
end

describe("the Art trail is an arc at the blade's height that goes soon after the cut (D-335)", function()
	it("sweeps round the body at the blade's reach", function()
		local take = horizontalTake()
		local low, high = math.huge, -math.huge
		local drawn = 0
		for _, record in take.frames do
			for _, at in record.ends do
				local local_ = take.start:PointToObjectSpace(at.point)
				local reach = Vector3.new(local_.X, 0, local_.Z).Magnitude
				expect(reach).toBeGreaterThan(REACH)
				local bearing = math.deg(math.atan2(local_.X, -local_.Z))
				low, high = math.min(low, bearing), math.max(high, bearing)
				drawn += 1
			end
		end
		expect(drawn).toBeGreaterThan(0)
		if high - low < ARC_DEGREES then
			error(("the stroke sweeps %.0f degrees round the body, under %d"):format(high - low, ARC_DEGREES))
		end
	end)

	it("never hangs down to the floor", function()
		local take = horizontalTake()
		for index, record in take.frames do
			for _, at in record.ends do
				local edge = at.point.Y - at.width / 2 - take.floor
				if edge < FLOOR_GAP then
					error(
						("frame %d: the band's lower edge is %.2f studs above the floor, under %.2f"):format(
							index,
							edge,
							FLOOR_GAP
						)
					)
				end
			end
		end
	end)

	it("is a thin arc, not a band, once the cut has stopped, and lays nothing back over it", function()
		local take = horizontalTake()
		local stopped = take.stopped
		expect(stopped).never.toBeNil()
		for index = stopped :: number, #take.frames do
			for _, at in take.frames[index].ends do
				local tall = pixels(take, at)
				if tall > BAND_PIXELS_STOPPED then
					error(
						("frame %d (the cut stopped on %d): the band is %.0f px tall at 1080p, over %d"):format(
							index,
							stopped :: number,
							tall,
							BAND_PIXELS_STOPPED
						)
					)
				end
			end
		end
		expect(take.pushedAfterStop).toBe(0)
	end)

	it("is gone soon after the cut stops", function()
		local take = horizontalTake()
		local stopped = take.stopped :: number
		local last = 0
		for index, record in take.frames do
			if record.beams > 0 then
				last = index
			end
		end
		expect(last).toBeGreaterThan(stopped - 1)
		if last - stopped > FRAMES_AFTER_STOP then
			error(
				("the last Beam shows %d frames after the cut stopped (frame %d), over %d"):format(
					last - stopped,
					stopped,
					FRAMES_AFTER_STOP
				)
			)
		end
	end)
end)

describe("a rig's first swing draws on the frame its window opens (shot 9, D-273, D-336)", function()
	for _, fps in { 30, 60, 144 } do
		it(("Basic1 attached by its own TrailOn draws what an attached rig draws, at %d fps"):format(fps), function()
			local attached = play("Basic1", { fps = fps })
			local first = play("Basic1", { fps = fps, lazy = true })
			local opened = first.opened
			expect(opened).never.toBeNil()
			expect(opened).toBe(attached.opened)
			local frame = opened :: number
			-- (At 30 fps Basic1's window opens on the last instant of its frame: nothing to draw yet.)
			if first.frames[frame].beams ~= attached.frames[frame].beams then
				error(
					("frame %d, the window's first: %d Beams show, an attached rig shows %d"):format(
						frame,
						first.frames[frame].beams,
						attached.frames[frame].beams
					)
				)
			end
			-- The same ribbon as the attached rig's, from the clip's open on: its first frame of arc
			-- is there, and the stroke ends where the cut does.
			for index = frame, math.min(#first.frames, #attached.frames) do
				local mine, theirs = first.frames[index].ends, attached.frames[index].ends
				if #mine ~= #theirs then
					error(("frame %d: %d Beam ends, an attached rig has %d"):format(index, #mine, #theirs))
				end
				for slot, at in mine do
					local gap = (at.point - theirs[slot].point).Magnitude
					if gap > 0.05 then
						error(("frame %d, Beam end %d: %.3f studs from the attached rig's"):format(index, slot, gap))
					end
				end
			end
		end)
	end
end)

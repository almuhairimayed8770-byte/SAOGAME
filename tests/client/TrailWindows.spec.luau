--!strict
--[[
	Each hit window draws its own crisp arc (shots 4 and 5, art-sharp-nail and art-rising-arc), and
	the part of a cut seen edge-on draws a streak at the blade's height, not a slab (shot 2,
	art-horizontal, D-360 and D-361).

	On the real player rig (the hit matrix's avatar posed by a real Choreo animator) every Art and
	the basic chain play at 30, 60 and 144 fps. Their clip events go to Trails.setActive as
	Replication.routeClipEvent routes them: a TrailOn or HitWindowOpen lights the kind the clip's
	TrailOn names, a HitWindowClose or TrailOff puts it out, SmearOn and SmearOff add the Smear kind.
	Each window's hit holds the rig as a connected hit does (Normal, the Art's last window Final,
	from the snap's end), and Trails reads that hold from the real animator.

	Before (cebade4, the hold on): every window of every cut still drew 8 to 10 frames (at 60 fps
	time, at 30, 60 and 144) after it went out, so Sharp Nail's three arcs and Rising Arc's two ran
	together with no clear frame between them; round D's DG2 cut that to 2 to 7 frames (3 and 5
	clear frames in Sharp Nail's two gaps at 60 fps). From the staged Side camera the Horizontal cut's band stood 145 to
	148 px tall at 1080p where the cut is seen within 10 degrees of edge-on (the far side of the
	arc, receding from the camera: a flat slab on the ground), for 19 frames at 60 fps (6 frames,
	the Final hold, with DG2).
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
local ChoreoData = Harness.load("src/shared/data/choreo")
local Combat = Harness.load("src/shared/data/combat")
local CameraData = Harness.load("src/shared/data/camera")
local CameraMath = Harness.load("src/client/camera/CameraMath")
local Dev = Harness.load("src/shared/data/dev")
local Trails = Harness.load("src/client/fx/Trails")
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
local SCREEN_HEIGHT = 1080
local RATES = { 30, 60, 144 }
local CUTS = { "Horizontal", "Vertical", "SharpNail", "RisingArc", "Basic1", "Basic2", "Basic3" }

-- The bars. A window's arc may fade for up to two 60 fps frames after the last frame that drew it
-- lit ("a fade of a frame or two"); from the third (50 ms on, at any rate) until the next window
-- lights nothing shows.
local CLOSE_BAR_SECONDS = 3 / 60
-- Where a cut is seen within EDGE_DEGREES of edge-on (the sheet the blade sweeps there, from the
-- ribbon's own body and core points, against the line to the camera) its band is a streak at most
-- STREAK_PIXELS tall at 1080p on every frame, the smear frames and the hold included. A vertical
-- cut faces the Side camera and keeps the ribbon's full thickness: at least THICK_PIXELS.
local EDGE_DEGREES = 10
local STREAK_PIXELS = 60
local THICK_PIXELS = 150

type End = {
	pixels: number, -- how tall it stands on the screen at 1080p (the Beam faces the camera)
	facing: number?, -- |cos| between its sample's swept sheet and the line to the camera (0 edge-on)
}

type Frame = {
	lit: boolean, -- the trail is on (Trails.isEnabled)
	beams: number, -- Beams showing on any layer
	smear: boolean, -- inside SmearOn..SmearOff
	tallest: number, -- the Body layer's tallest Beam end on the screen, px at 1080p
	ends: { End }, -- the Body layer's Beam ends (a camera given)
}

type Options = {
	fps: number,
	freezes: boolean?, -- hold the rig on each window's hit (Normal, the last window Final)
	camera: CFrame?, -- the viewer (Trails' budget and the ribbon's facing); none: 10 studs off
}

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

-- The rig standing on the field, its parts placed where Lune can read them.
local function standing(): (any, any)
	local avatar, field = HitMatrix.standing(Harness)
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
	return avatar, field
end

-- The staged Side camera of shot 2 as CameraController lays it (CameraMath, dev.luau
-- capture.cameras): the middle of the player and a kobold ahead, 90 degrees round.
local function sideCamera(avatar: any): CFrame
	local shot = shotOf("art-horizontal")
	local enemy = shot.stage.enemies[1]
	local view = Dev.capture.cameras[shot.camera]
	local player = avatar.base.Position
	local target = player + avatar.base.LookVector * enemy.distance
	local anchor = CameraMath.stageAnchor(view.anchor, vec(player), vec(target))
	local reference = CameraMath.stageReference(view.reference, view.anchor, vec(player), vec(target), nil)
	assert(reference ~= nil, "the Side view has a reference")
	local bearing = (reference :: number) + shot.cameraSide * view.degrees
	local cameraAt = toVector(CameraMath.twoShotCamera(anchor, bearing, view.distance, view.height))
	local aim = toVector(CameraMath.twoShotLook(vec(player), vec(target), view.focusBias, view.lookHeight))
	return CFrame.lookAt(cameraAt, aim)
end

local FOCAL = (SCREEN_HEIGHT / 2) / math.tan(math.rad(CameraData.fov.rest / 2))

local function key(point: Vector3): string
	return ("%.5f,%.5f,%.5f"):format(point.X, point.Y, point.Z)
end

-- Each live sample's facing from `eye`, keyed by its Body point: the sheet the blade sweeps there
-- is the blade (Body to Core point) crossed with the way the Core point moved through it.
local function facings(view: any, eye: Vector3): { [string]: number }
	local body: { Vector3 } = view.points[1]
	local core: { Vector3 } = view.points[2]
	local out: { [string]: number } = {}
	for index = 1, #body do
		local before = core[index - 1]
		local after = core[index + 1]
		local motion = if before ~= nil then core[index] - before elseif after ~= nil then after - core[index] else nil
		if motion ~= nil then
			local normal = (core[index] - body[index]):Cross(motion)
			local toEye = eye - body[index]
			local scale = normal.Magnitude * toEye.Magnitude
			if scale > 1e-9 then
				out[key(body[index])] = math.abs(normal:Dot(toEye)) / scale
			end
		end
	end
	return out
end

-- Plays `name` on the real path and records each rendered frame.
local function play(name: string, options: Options): { Frame }
	local avatar = standing()
	local model = avatar.model
	local camera = options.camera
	if camera == "side" :: any then
		camera = sideCamera(avatar)
	end
	local viewer = if camera ~= nil then (camera :: CFrame).Position else avatar.base.Position + Vector3.new(10, 3, 0)
	local renderFn: ((dt: number) -> ())? = nil
	Engine.setViewer(function(): Vector3
		return viewer
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
		held = function(target: Instance): boolean
			local animator = Choreo.find(target :: any)
			return animator ~= nil and animator:isPaused()
		end,
		animator = function(target: Instance): any
			return Choreo.find(target :: any)
		end,
	})
	Trails.attach(model)
	local animator: any = Choreo.get(model)
	local clipId = PREFIX .. name
	local basic = string.find(name, "Basic", 1, true) ~= nil
	-- Replication.resolveTrailKind: the kind the clip's TrailOn names, else Basic for a basic.
	local kind = if basic then "Basic" else "Art"
	local windows, total = 0, 0
	local smear = false
	local freeze: number? = nil
	animator.events:Connect(function(_id: string, event: any, _jumped: boolean)
		local named = if typeof(event.data) == "table" then event.data.kind else nil
		if typeof(named) == "string" then
			kind = named
		end
		local what = event.kind
		if what == "TrailOn" or what == "HitWindowOpen" then
			if what == "HitWindowOpen" then
				windows += 1
			end
			Trails.setActive(model, true, kind :: any)
		elseif what == "TrailOff" or what == "HitWindowClose" or what == "PostMotionStart" then
			Trails.setActive(model, false, kind :: any)
		elseif what == "SmearOn" then
			smear = true
			Trails.setActive(model, true, "Smear")
		elseif what == "SmearOff" then
			smear = false
			Trails.setActive(model, false, "Smear")
			if options.freezes then
				local tier = if not basic and windows == total then "Final" else "Normal"
				freeze = Combat.hitStopFrames[tier]
			end
		end
	end)
	local frames: { Frame } = {}
	local ok, err = pcall(function()
		local handle = animator:play(clipId)
		for _, event in handle.clip.events do
			if event.kind == "HitWindowOpen" then
				total += 1
			end
		end
		local dt = 1 / options.fps
		for index = 1, 4000 do
			clock += dt
			animator:step(dt)
			if freeze ~= nil then
				animator:hitStop(freeze)
				freeze = nil
			end
			assert(renderFn ~= nil, "Trails connected no render step");
			(renderFn :: (dt: number) -> ())(dt)
			local record: Frame = { lit = Trails.isEnabled(model), beams = 0, smear = smear, tallest = 0, ends = {} }
			local ribbon = Trails.ribbonOf(model)
			if ribbon ~= nil then
				local facing = if camera ~= nil then facings(ribbon, (camera :: CFrame).Position) else {}
				for layer, beams in ribbon.beams do
					record.beams += #beams
					if layer == 1 and camera ~= nil then
						for _, beam in beams do
							for _, pair in { { beam.Attachment0, beam.Width0 }, { beam.Attachment1, beam.Width1 } } do
								local attachment = pair[1] :: Attachment
								local point = ribbon.host.Position + attachment.Position
								local depth = -(camera :: CFrame):PointToObjectSpace(point).Z
								local tall = (pair[2] :: number) * FOCAL / math.max(depth, 1e-3)
								record.tallest = math.max(record.tallest, tall)
								table.insert(record.ends, { pixels = tall, facing = facing[key(point)] })
							end
						end
					end
				end
			end
			frames[index] = record
			local current = animator.mixer:find(clipId)
			if (current == nil or current.done) and record.beams == 0 then
				break
			end
		end
	end)
	Trails.bind(nil)
	Trails.reset()
	Engine.setViewer(nil)
	Engine.setClock(nil)
	Choreo.release(model)
	if not ok then
		error(err, 0)
	end
	return frames
end

type Window = { first: number, last: number } -- frames the trail was lit, first to last

local function windowsOf(frames: { Frame }): { Window }
	local list: { Window } = {}
	local index = 1
	while index <= #frames do
		if frames[index].lit then
			local first = index
			while index <= #frames and frames[index].lit do
				index += 1
			end
			table.insert(list, { first = first, last = index - 1 })
		else
			index += 1
		end
	end
	return list
end

describe("each hit window draws its own arc, gone before the next lights (shots 4 and 5)", function()
	for _, name in CUTS do
		for _, fps in RATES do
			it(
				("%s at %d fps: nothing of a window shows %.0f ms after it goes out"):format(
					name,
					fps,
					CLOSE_BAR_SECONDS * 1000
				),
				function()
					local frames = play(name, { fps = fps, freezes = true })
					local windows = windowsOf(frames)
					expect(#windows).toBeGreaterThan(0)
					for number, window in windows do
						local nextFirst = if windows[number + 1] ~= nil then windows[number + 1].first else #frames + 1
						for index = window.last + 1, nextFirst - 1 do
							local after = (index - window.last) / fps
							if after >= CLOSE_BAR_SECONDS - 1e-9 and frames[index].beams > 0 then
								error(
									("window %d (lit f%d-%d): %d Beams still show on f%d, %.1f frames at 60 fps after it went out%s"):format(
										number,
										window.first,
										window.last,
										frames[index].beams,
										index,
										after * 60,
										if windows[number + 1] ~= nil
											then (" (the next window lights on f%d)"):format(nextFirst)
											else ""
									)
								)
							end
						end
					end
				end
			)
		end
	end

	it("Sharp Nail draws three arcs and Rising Arc two, each with a clear frame before the next", function()
		for _, case in { { "SharpNail", 3 }, { "RisingArc", 2 } } do
			for _, fps in RATES do
				local frames = play(case[1] :: string, { fps = fps, freezes = true })
				local windows = windowsOf(frames)
				expect(#windows).toBe(case[2])
				for number = 1, #windows - 1 do
					local clear = 0
					for index = windows[number].last + 1, windows[number + 1].first - 1 do
						if frames[index].beams == 0 then
							clear += 1
						end
					end
					if clear == 0 then
						error(
							("%s at %d fps: no clear frame between windows %d and %d"):format(
								case[1] :: string,
								fps,
								number,
								number + 1
							)
						)
					end
				end
			end
		end
	end)
end)

describe("the part of a cut seen edge-on draws a streak at the blade's height, not a slab (shot 2)", function()
	local edgeOn = math.sin(math.rad(EDGE_DEGREES))
	for _, fps in RATES do
		it(
			("Horizontal from the staged Side camera at %d fps: a streak where seen edge-on, smear and hold included"):format(
				fps
			),
			function()
				local frames = play("Horizontal", { fps = fps, camera = "side" :: any, freezes = true })
				local seen = 0
				for index, frame in frames do
					for _, at in frame.ends do
						if at.facing ~= nil and (at.facing :: number) <= edgeOn then
							seen += 1
							if at.pixels > STREAK_PIXELS then
								error(
									("f%d%s: where the cut is seen %.1f degrees off edge-on its band is %.0f px tall at 1080p, over %d"):format(
										index,
										if frame.smear then " (a smear frame)" else "",
										math.deg(math.asin(at.facing :: number)),
										at.pixels,
										STREAK_PIXELS
									)
								)
							end
						end
					end
				end
				-- The arc's far side recedes from the camera edge-on (the bar is not empty).
				expect(seen).toBeGreaterThan(0)
			end
		)
	end

	it("Vertical faces the same camera and keeps the ribbon's full thickness (guard)", function()
		for _, fps in RATES do
			local frames = play("Vertical", { fps = fps, camera = "side" :: any, freezes = true })
			local thickest = 0
			for _, frame in frames do
				if frame.lit then
					thickest = math.max(thickest, frame.tallest)
				end
			end
			if thickest < THICK_PIXELS then
				error(
					("Vertical at %d fps: its band is at most %.0f px tall, under %d"):format(
						fps,
						thickest,
						THICK_PIXELS
					)
				)
			end
		end
	end)
end)

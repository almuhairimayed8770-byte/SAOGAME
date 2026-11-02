--!strict
--[[
	A remote basic whose ActionStarted comes in late (D-538, AG 376(a)). The network catch-up
	starts the clip `late` seconds in (Mixer.catchUpStart), and the Mixer's first step fires the
	clip's events from there on: Basic1's TrailOn and HitWindowOpen are at 0.1 s, so at 0.1 s of
	lag or more nothing ever lit its trail, and the watcher saw no ribbon at all for a swing whose
	strike was still to come (its snap lands at 0.15 s). Now the window the start jumped into
	lights on the first frame that draws the clip, and the ribbon draws the part of the stroke
	still ahead, from the clip's own blade where it came in: never a streak from the back mount, or
	from the pose before the jump. A window with none of its stroke left (the snap landed, or the
	window closed) stays dark.

	The stroke is back-filled (D-550): on the first frame that draws the late clip, the ribbon
	draws the stroke from the window's open (Basic1's TrailOn at 0.1 s) up to the clip time that
	frame shows, on the clip's own blade at its full weight (the clip is still fading in over the
	rig's pose), each sample aged as if drawn at its own clip time, then goes on with the clip as
	it plays, up to the strike's landing (D-539). So the watcher sees the slash the on-time stroke
	draws, less what has faded by then. A rig the late clip's first step finds frozen (a hit-stop)
	draws nothing until its clip moves.

	The real path: a real Choreo animator on a RigBuilder player rig with its WeaponBuilder sword
	(sheathed on the back, or drawn), the real ClipLibrary clip, the remote's ActionStarted through
	the real Replication (atStepPose on the real FrameClock), and the real Trails and TrailRibbon on
	their render steps: the drawn pose's at a frame's start, the pose readers' after the rigs'
	step. Lune derives no WorldPosition, so TrailEnd goes where the rig's joints pose it
	(BladeContact) before the readers run, as the engine would.
]]

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
local Locomotion = Harness.load("src/client/choreo/Locomotion")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local FrameClock = Harness.load("src/client/fx/FrameClock")
local Replication = Harness.load("src/client/controllers/Replication")
local Trails = Harness.load("src/client/fx/Trails")
local TrailRibbon = Harness.load("src/client/fx/TrailRibbon")
local Engine = Harness.load("src/client/fx/Engine")
local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Rigs = Harness.load("src/shared/data/rigs")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local WeaponBuilder = Harness.load("src/server/world/WeaponBuilder")
local WeaponModels = Harness.load("src/shared/data/weaponModels")
local Weapons = Harness.load("src/shared/data/weapons")

local BASIC1 = ChoreoData.locomotion.clipPrefix .. "Basic1"
local RATES = { 30, 60, 144 }

local clock = 100
local frame = 0
Choreo.configure({
	now = function(): number
		return clock
	end,
	cameraPosition = function(): Vector3
		return Vector3.zero
	end,
})

local function recorder(): any
	return setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
end

-- A player rig with its sword, on the back mount (sheathed) or in the hand (drawn).
local function build(drawn: boolean): (Model, any, BasePart)
	local model = Instance.new("Model")
	model.Name = "Ren"
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", drawn)
	model:SetAttribute("State", "Idle")
	local parts: { [string]: BasePart } = {}
	local function part(name: string): BasePart
		if parts[name] == nil then
			local created = Instance.new("Part")
			created.Name = name
			created.Size = Vector3.new(1, 1, 1)
			created.CFrame = CFrame.new(0, 3, 0)
			created.Position = Vector3.new(0, 3, 0)
			created.AssemblyLinearVelocity = Vector3.zero
			created.Parent = model
			parts[name] = created
		end
		return parts[name]
	end
	for _, joint in Rigs.PlayerR15.joints do
		if joint.name ~= WeaponModels.motorName then
			local motor = Instance.new("Motor6D")
			motor.Name = joint.name
			motor.Part0 = part(joint.part0)
			motor.Part1 = part(joint.part1)
			motor.C0 = RigBuilder.frameOf(joint.c0)
			motor.Parent = motor.Part1
		end
	end
	model.PrimaryPart = parts.HumanoidRootPart
	local humanoid = Instance.new("Humanoid")
	humanoid.MoveDirection = Vector3.zero
	humanoid.FloorMaterial = Enum.Material.Plastic
	humanoid.Parent = model
	WeaponBuilder.equip(model, Weapons.byId("TrialistSword"))
	local world = Instance.new("Folder")
	model.Parent = world
	local weaponMotor: any = nil
	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") and item.Name == WeaponModels.motorName then
			weaponMotor = item
		elseif item:IsA("BasePart") then
			local ok = pcall(function(): Vector3
				return item.Position
			end)
			if not ok then
				item.Position = Vector3.new(0, 3, 0)
			end
		end
	end
	return model, weaponMotor, parts.RightHand
end

type Push = { frame: number, tip: Vector3, born: number }

type Take = {
	added: { { frame: number, from: Vector3, tip: Vector3 } }, -- the ribbon's new segments
	pushes: { Push }, -- every sample the ribbon kept, with the ribbon-clock time it stands for
	preJump: Vector3, -- the tip the frame before the clip drew (the back mount, or the idle hand)
	firstInHand: Vector3?, -- the tip on the first frame that drew the sword in the hand
	shown: { [number]: number }, -- per frame, the clip time it draws (its rig's step of the frame before)
	stood: { [number]: boolean }, -- per frame, the step it draws left the clip where it was (a freeze)
	drawClock: { [number]: number }, -- per frame, the ribbon clock the ribbon was laid for
	start: number, -- the clip time the catch-up started the clip at
}

-- When the rig's hit-stop comes: right after the ActionStarted (before the clip's first step), or
-- after the first frame that draws the clip; `frames` long.
type Freeze = { at: "dispatch" | "drawn", frames: number }

-- Plays Basic1 on a remote rig whose ActionStarted comes `late` seconds after the server's start,
-- at `fps`; returns the ribbon segments the swing added and the tips around the jump.
local function take(drawn: boolean, late: number, fps: number, freeze: Freeze?): Take
	local model, weaponMotor, hand = build(drawn)
	local record =
		{ id = 2, model = model, kind = "Player", rig = "PlayerR15", weaponId = "TrialistSword", name = "Ren" }
	local hooks: { [string]: any } = {}
	local function hook(key: string)
		return function(fn: any): () -> ()
			hooks[key] = fn
			return function()
				hooks[key] = nil
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
	Engine.setViewer(function(): Vector3
		return Vector3.new(0, 5, 10)
	end)
	Engine.setClock(function(): number
		return clock
	end)
	Trails.start()
	Trails.bind({
		now = function(): number
			return clock
		end,
		onRender = hook("readers"),
		onDrawn = hook("drawn"),
		onWatch = function(): () -> ()
			return function() end
		end,
		clear = function() end,
		-- The rig's hold as the frame draws it, as the game binds it (Choreo heldShown).
		held = function(target: Instance): boolean
			local found: any = Choreo.find(target :: any)
			return found ~= nil and found:heldShown() == true
		end,
		animator = function(target: Instance): any
			return Choreo.find(target :: any)
		end,
	})
	Replication.bind({
		net = { on = function() end },
		entities = {
			get = function(id: number): any
				return if id == 2 then record else nil
			end,
		},
		localId = function(): number
			return 1
		end,
		locomotion = {
			-- Foot IK off: Lune casts no rays, and the swing's blade is the spec's subject.
			attach = function(animator: any, rigName: any, options: any): any
				local withoutIK = table.clone(options or {})
				withoutIK.footIK = false
				return Locomotion.attach(animator, rigName, withoutIK)
			end,
			destroy = Locomotion.destroy,
			humanoidTracker = Locomotion.humanoidTracker,
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
			return "TrailCyanWhite"
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
	Replication.watch(record)
	local animator: any = Choreo.get(model)
	local tipAttachment = model:FindFirstChild("TrailEnd", true) :: Attachment
	tipAttachment.WorldPosition = Vector3.new(0, 3, 0)
	local result: Take = {
		added = {},
		pushes = {},
		preJump = Vector3.zero,
		firstInHand = nil,
		shown = {},
		stood = {},
		drawClock = {},
		start = -1,
	}
	local recording = false
	local lastPush: Vector3? = nil
	local realPush = TrailRibbon.push
	TrailRibbon.push = function(ribbon: any, guard: Vector3, tip: Vector3, born: number, joined: boolean): boolean
		local ok = realPush(ribbon, guard, tip, born, joined)
		if recording and ok and lastPush ~= nil then
			table.insert(result.added, { frame = frame, from = lastPush :: Vector3, tip = tip })
		end
		if recording and ok then
			lastPush = tip
			table.insert(result.pushes, { frame = frame, tip = tip, born = born })
		end
		return ok
	end
	local handle: any = nil
	local realDraw = TrailRibbon.draw
	TrailRibbon.draw = function(ribbon: any, ribbonClock: number, style: any)
		if recording then
			result.drawClock[frame] = ribbonClock
		end
		realDraw(ribbon, ribbonClock, style)
	end
	local drawnTip = Vector3.zero
	local inHand = false
	local dt = 1 / fps
	local function step()
		frame += 1
		clock += dt
		hooks.start(dt)
		if handle ~= nil then
			result.shown[frame] = handle.time
		end
		-- The pose this frame draws: the joints the rigs' step of the frame before wrote.
		local chain = BladeContact.chain(model :: any)
		local _, tip = BladeContact.blade(chain, BladeContact.read(chain))
		drawnTip = tip
		inHand = weaponMotor.Part0 == hand
		if hooks.drawn ~= nil then
			hooks.drawn(0)
		end
		local before = if handle ~= nil then handle.time else nil
		animator:step(dt)
		if handle ~= nil then
			result.stood[frame + 1] = handle.time == before
		end
		hooks.posed(dt)
		local posed = BladeContact.chain(model :: any)
		local _, posedTip = BladeContact.blade(posed, BladeContact.read(posed))
		tipAttachment.WorldPosition = posedTip
		if hooks.readers ~= nil then
			hooks.readers(0)
		end
		hooks.finish(dt)
	end
	local ok, err = pcall(function()
		for _ = 1, 90 do
			step()
		end
		expect(inHand).toBe(drawn)
		result.preJump = drawnTip
		recording = true
		Replication.dispatch(
			"ActionStarted",
			{ entityId = 2, clipId = BASIC1, serverTime = clock - late, facing = { 0, 0, -1 } }
		)
		handle = animator.mixer:find(BASIC1)
		result.start = handle.time
		if freeze ~= nil and freeze.at == "dispatch" then
			animator:hitStop(freeze.frames)
		end
		for _ = 1, math.ceil(0.5 * fps) do
			step()
			if inHand and result.firstInHand == nil then
				result.firstInHand = drawnTip
			end
			local pending = freeze
			if pending ~= nil and pending.at == "drawn" and (result.shown[frame] or -1) > result.start then
				freeze = nil
				animator:hitStop(pending.frames)
			end
		end
	end)
	TrailRibbon.push = realPush
	TrailRibbon.draw = realDraw
	Replication.unwatch(record)
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

local function length(segments: { { from: Vector3, tip: Vector3 } }): number
	local total = 0
	for _, segment in segments do
		total += (segment.tip - segment.from).Magnitude
	end
	return total
end

-- The distance from `point` to the polyline through `tips`.
local function offPath(point: Vector3, tips: { Vector3 }): number
	local best = if #tips > 0 then (point - tips[1]).Magnitude else math.huge
	for index = 2, #tips do
		local a, b = tips[index - 1], tips[index]
		local along = b - a
		local span = along:Dot(along)
		local t = if span > 1e-12 then math.clamp((point - a):Dot(along) / span, 0, 1) else 0
		best = math.min(best, (point - (a + along * t)).Magnitude)
	end
	return best
end

local function tipsOf(result: Take): { Vector3 }
	local tips = {}
	for _, push in result.pushes do
		table.insert(tips, push.tip)
	end
	return tips
end

-- Basic1's TrailOn and HitWindowOpen: the window's open, where the on-time stroke starts.
local WINDOW_OPEN = 0.1
-- Studs a late stroke's sample may lie off the on-time stroke: what the frames show on top of the
-- clip (the on-time blade beside the clip's own: 0.03 to 0.18) and the sub-steps' chords.
local ON_PATH = 0.3
-- No segment of a late stroke is longer than this (D-538's bar: the back mount is 6 studs away).
local BAR = 1.5

-- The on-time stroke per (drawn, fps): the slash a late one back-fills.
local onTime: { [string]: Take } = {}
local function reference(drawn: boolean, fps: number): Take
	local key = ("%s/%d"):format(tostring(drawn), fps)
	if onTime[key] == nil then
		onTime[key] = take(drawn, 0, fps)
	end
	return onTime[key]
end

-- Checks a late take's stroke is the on-time slash: as long (less a tenth), on its path, from its
-- first point, every segment under the bar; returns the label's problems.
local function slashProblems(result: Take, ref: Take): { string }
	local problems = {}
	local refTips = tipsOf(ref)
	local refLength = length(ref.added)
	local drawnLength = length(result.added)
	if #result.pushes == 0 then
		return { "no ribbon" }
	end
	if drawnLength < 0.9 * refLength then
		table.insert(problems, ("%.2f studs of the on-time %.2f"):format(drawnLength, refLength))
	end
	local first = result.pushes[1].tip
	if (first - refTips[1]).Magnitude > ON_PATH then
		table.insert(problems, ("first point %.2f from the on-time first"):format((first - refTips[1]).Magnitude))
	end
	local worst = 0
	for _, push in result.pushes do
		worst = math.max(worst, offPath(push.tip, refTips))
	end
	if worst > ON_PATH then
		table.insert(problems, ("a sample %.2f off the on-time stroke"):format(worst))
	end
	for _, segment in result.added do
		local long = (segment.tip - segment.from).Magnitude
		if long >= BAR then
			table.insert(problems, ("a %.2f stud segment"):format(long))
		end
	end
	return problems
end

describe("Trails: a remote basic whose start came in late (D-538)", function()
	it("draws the stroke still to come at 0.1 to 0.134 s of lag, sheathed or drawn, at 30, 60 and 144", function()
		-- Before: no segment at all from 0.11 s on (the window lit before the clip's start).
		-- D-538: 0.06 to 3.6 studs, shorter the later it came in; since D-550 the whole slash, 5.36
		-- to 5.40 studs (the back-fill below).
		for _, drawn in { false, true } do
			for _, fps in RATES do
				for _, late in { 0.1, 0.11, 0.12, 0.134 } do
					local result = take(drawn, late, fps)
					local label = ("drawn %s, %d fps, %.3f s late"):format(tostring(drawn), fps, late)
					expect({ label, #result.added > 0 }).toEqual({ label, true })
				end
			end
		end
	end)

	it("starts on the clip's own blade, never a streak from the back mount", function()
		-- The back mount's tip is 6 studs from the hand's: no segment comes near that long, and the
		-- first starts on the sword in the hand, not on the back: since D-550 at the window's open,
		-- where the on-time stroke starts (D-538 had it start where the clip came in, within 1.5
		-- studs of the first tip drawn in the hand; the back-fill starts 2.4 to 3.0 from that tip,
		-- which the clip's fade-in still holds near the pose before the jump).
		for _, fps in RATES do
			local ref = reference(false, fps)
			for _, late in { 0.11, 0.12, 0.134 } do
				local result = take(false, late, fps)
				local label = ("%d fps, %.3f s late"):format(fps, late)
				expect({ label, #result.added > 0 }).toEqual({ label, true })
				local firstInHand = result.firstInHand :: Vector3
				expect((result.preJump - firstInHand).Magnitude > 5).toBe(true)
				local first = result.added[1]
				expect({ label, (first.from - result.preJump).Magnitude > 5 }).toEqual({ label, true })
				expect({ label, (first.from - ref.pushes[1].tip).Magnitude < ON_PATH }).toEqual({ label, true })
				for _, segment in result.added do
					expect({ label, (segment.tip - segment.from).Magnitude < 1.5 }).toEqual({ label, true })
				end
			end
		end
	end)

	it(
		"draws nothing when none of the stroke is left: its snap landed (0.15 s) or its window closed (0.25 s)",
		function()
			for _, drawn in { false, true } do
				for _, fps in RATES do
					for _, late in { 0.15, 0.2, 0.25 } do
						local result = take(drawn, late, fps)
						local label = ("drawn %s, %d fps, %.3f s late"):format(tostring(drawn), fps, late)
						expect({ label, length(result.added) }).toEqual({ label, 0 })
					end
				end
			end
		end
	)
end)

describe("Trails: a late remote basic's stroke is back-filled from its window's open (D-550)", function()
	it("draws the on-time slash at 0.10 to 0.149 s of lag, sheathed or drawn, at 30, 60 and 144", function()
		-- Before (D-538 alone): only what was still ahead, 0.06 to 4.2 studs of the on-time 5.4,
		-- from where it came in.
		for _, drawn in { false, true } do
			for _, fps in RATES do
				local ref = reference(drawn, fps)
				for _, late in { 0.1, 0.11, 0.12, 0.134, 0.149 } do
					local result = take(drawn, late, fps)
					local label = ("drawn %s, %d fps, %.3f s late"):format(tostring(drawn), fps, late)
					expect({ label, slashProblems(result, ref) }).toEqual({ label, {} })
					-- All of it on the first frame that draws the clip.
					local firstFrame: number? = nil
					for f = 1, frame do
						if firstFrame == nil and (result.shown[f] or -1) > result.start then
							firstFrame = f
						end
					end
					expect({ label, result.pushes[1].frame }).toEqual({ label, firstFrame })
				end
			end
		end
	end)

	it("ages each back-filled sample as if it was drawn at its own clip time", function()
		-- The window's open sample on the first frame is as old as the clip time the frame shows
		-- is past the open (Basic1 plays at speed 1); before, it was a frame old at most.
		for _, drawn in { false, true } do
			for _, fps in RATES do
				for _, late in { 0.11, 0.134, 0.149 } do
					local result = take(drawn, late, fps)
					local label = ("drawn %s, %d fps, %.3f s late"):format(tostring(drawn), fps, late)
					expect({ label, #result.pushes > 0 }).toEqual({ label, true })
					local first = result.pushes[1]
					local age = result.drawClock[first.frame] - first.born
					local want = result.shown[first.frame] - WINDOW_OPEN
					expect({ label, math.abs(age - want) < 1e-6 }).toEqual({ label, true })
					for index = 2, #result.pushes do
						expect({ label, result.pushes[index].born >= result.pushes[index - 1].born }).toEqual({
							label,
							true,
						})
					end
				end
			end
		end
	end)

	it("never draws through a freeze the rig is in: none while its clip stands, the slash once it moves", function()
		-- A hit-stop before the clip's first step (the rig holds the pose from before the jump) or
		-- on the frame after the first that draws it. Before (D-538 alone), a freeze on the first
		-- step started a stroke with no clip from the frozen pose, and it drew the blend in and the
		-- settle.
		for _, drawn in { false, true } do
			for _, fps in RATES do
				local ref = reference(drawn, fps)
				for _, late in { 0.11, 0.134 } do
					for _, freeze: Freeze in
						{
							{ at = "dispatch", frames = 3 },
							{ at = "dispatch", frames = 6 },
							{ at = "drawn", frames = 3 },
						}
					do
						local result = take(drawn, late, fps, freeze)
						local label = ("drawn %s, %d fps, %.3f s late, freeze %s %d"):format(
							tostring(drawn),
							fps,
							late,
							freeze.at,
							freeze.frames
						)
						local through = 0
						for _, push in result.pushes do
							if result.stood[push.frame] == true then
								through += 1
							end
						end
						expect({ label, through }).toEqual({ label, 0 })
						expect({ label, slashProblems(result, ref) }).toEqual({ label, {} })
					end
				end
			end
		end
	end)
end)

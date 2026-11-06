--!strict
--[[
	A watcher's copy draws a remote basic's ribbon after a late one's (D-634, AS 517(b)).

	The PC's section AS (517(b)): on B, a sheathed remote Basic1 at 30 fps and lag 0 showed no
	ribbon at all on 3 of 4 takes. TrailLit was true on 5 to 6 rows, and all 96 Beams read Enabled
	false on every row. Those takes' first rows drew clip 0.0853 to 0.0866 (catch-up 0.052 to
	0.053); the take that showed a ribbon drew 0.1023 on its first row. The rig had played the
	late takes before (517's lag-0.1 takes, back-filled, D-550), and a back-filled stroke marks
	itself `lateFull` until its clip has faded in. A stroke ended by its strike's landing (D-539)
	never cleared the mark, so the next stroke that did not come in late went down the back-fill's
	path: on the last stroke's cut, already done, with no stroke begun. It laid nothing. A take
	whose first row was past the window's open (0.1023) came in late itself, and its own back-fill
	drew it.

	Now a stroke that starts drops the last stroke's mark, so the back-fill path is taken only by
	the stroke that came in late.

	The real path: a RigBuilder player rig with its WeaponBuilder sword (sheathed on the back, or
	drawn), a real Choreo animator, the real ClipLibrary clip, ActionStarted through the real
	Replication (atStepPose and atStepPoseSolve on the real FrameClock, its PreSimulation step), and
	the real Trails and TrailRibbon on their render steps. Lune derives no WorldPosition, so TrailEnd
	goes where the rig's joints pose it (BladeContact) before the readers run, as the engine would.
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
-- The PC's lag-0 catch-up (517(b)): 0.052 to 0.053.
local LAG_ZERO = 0.052
-- The late takes before (back-filled, D-550): past Basic1's open at 0.1, short of its snap's
-- landing at 0.15.
local LATE = { 0.107, 0.14 }
-- Seconds between two swings' starts: each clip is over and its trail out.
local GAP = 1.2

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
local function build(drawn: boolean): Model
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
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			local ok = pcall(function(): Vector3
				return item.Position
			end)
			if not ok then
				item.Position = Vector3.new(0, 3, 0)
			end
		end
	end
	return model
end

type Swing = {
	length: number, -- studs of ribbon the swing's stroke laid (its joined segments)
	samples: number, -- the samples its ribbon kept
	litRows: number, -- rows drawn with the trail lit
	coreRows: number, -- of those, rows showing a Core beam
	start: number, -- the clip time the catch-up started it at
}

-- Plays Basic1 on one remote rig once per entry of `lags` (each ActionStarted that many seconds
-- after the server's start, GAP apart), at `fps`; returns each swing's ribbon.
local function take(drawn: boolean, fps: number, lags: { number }): { Swing }
	local model = build(drawn)
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
		onPreSimulation = hook("preSimulation"),
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
		atPose = FrameClock.atPose,
		atStepPose = FrameClock.atStepPose,
		atStepPoseSolve = FrameClock.atStepPoseSolve,
	} :: any)
	Replication.watch(record)
	local animator: any = Choreo.get(model)
	local tipAttachment = model:FindFirstChild("TrailEnd", true) :: Attachment
	tipAttachment.WorldPosition = Vector3.new(0, 3, 0)
	local swings: { Swing } = {}
	local current: Swing? = nil
	local lastTip: Vector3? = nil
	local realPush = TrailRibbon.push
	TrailRibbon.push = function(ribbon: any, guard: Vector3, tip: Vector3, born: number, joined: boolean): boolean
		local ok = realPush(ribbon, guard, tip, born, joined)
		local swing = current
		if swing ~= nil and ok then
			swing.samples += 1
			if joined and lastTip ~= nil then
				swing.length += (tip - (lastTip :: Vector3)).Magnitude
			end
			lastTip = tip
		end
		return ok
	end
	local handle: any = nil
	local dt = 1 / fps
	local function step()
		frame += 1
		clock += dt
		hooks.start(dt)
		local swing = current
		if hooks.drawn ~= nil then
			hooks.drawn(0)
		end
		animator:step(dt)
		hooks.posed(dt)
		local posed = BladeContact.chain(model :: any)
		local _, posedTip = BladeContact.blade(posed, BladeContact.read(posed))
		tipAttachment.WorldPosition = posedTip
		if hooks.readers ~= nil then
			hooks.readers(0)
		end
		if swing ~= nil and Trails.isEnabled(model) then
			swing.litRows += 1
			local view = Trails.ribbonOf(model)
			if view ~= nil and #view.beams[#view.beams] > 0 then
				swing.coreRows += 1
			end
		end
		hooks.finish(dt)
		if hooks.preSimulation ~= nil then
			hooks.preSimulation(dt)
		end
	end
	local ok, err = pcall(function()
		for _ = 1, 60 do
			step()
		end
		for _, lag in lags do
			local swing: Swing = { length = 0, samples = 0, litRows = 0, coreRows = 0, start = 0 }
			table.insert(swings, swing)
			current = swing
			lastTip = nil
			Replication.dispatch(
				"ActionStarted",
				{ entityId = 2, clipId = BASIC1, serverTime = clock - lag, facing = { 0, 0, -1 } }
			)
			handle = animator.mixer:find(BASIC1)
			swing.start = handle.time
			for _ = 1, math.ceil(GAP * fps) do
				step()
			end
		end
	end)
	TrailRibbon.push = realPush
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
	return swings
end

describe("Trails: a remote basic after a late, back-filled one (D-634)", function()
	it("draws the next swing's slash at lag 0, sheathed or drawn, at 30, 60 and 144", function()
		-- Before: the swing at lag 0.052 after a back-filled one laid no sample on all 12 takes
		-- (no Core beam on any of its 4 lit rows at 30, 9 at 60, 21 at 144).
		-- After: as long as the same swing on a rig that played nothing before (within a tenth).
		local problems = {}
		for _, drawn in { false, true } do
			for _, fps in RATES do
				local alone = take(drawn, fps, { LAG_ZERO })[1]
				expect(alone.length > 1).toBe(true)
				for _, late in LATE do
					local swings = take(drawn, fps, { late, LAG_ZERO })
					local label = ("%s %d, after lag %.3f"):format(if drawn then "drawn" else "sheathed", fps, late)
					local before, after = swings[1], swings[2]
					if before.samples == 0 then
						table.insert(problems, label .. ": the late swing drew nothing")
					end
					if after.samples == 0 or after.coreRows == 0 then
						table.insert(
							problems,
							("%s: no ribbon (%d samples, %d of %d lit rows show a Core beam, catch-up %.4f)"):format(
								label,
								after.samples,
								after.coreRows,
								after.litRows,
								after.start
							)
						)
					elseif after.length < 0.9 * alone.length then
						table.insert(
							problems,
							("%s: %.2f studs of the %.2f alone"):format(label, after.length, alone.length)
						)
					end
				end
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("still back-fills a late swing after a late one", function()
		-- The mark goes with the stroke, so the next late stroke sets its own (D-550).
		local problems = {}
		for _, fps in RATES do
			local alone = take(false, fps, { LATE[1] })[1]
			local swings = take(false, fps, { LATE[2], LATE[1] })
			local after = swings[2]
			if after.length < 0.9 * alone.length then
				table.insert(problems, ("%d: %.2f studs of the %.2f alone"):format(fps, after.length, alone.length))
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)
end)

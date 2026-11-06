--!strict
--[[
	An enemy attack's wait (D-652, D-663, D-664) through the real path, with the remotes as the
	owner's PC delivered them (AV 556 on d310ca7, the PC rows of 556).

	The Telegraph (with the wind-up's origin) and the ActionStarted (with the clip) go through the
	real Replication to the real locomotion driver (Replication.watch) on a RigBuilder rig posed by
	a real Choreo animator. The server's body walks to the wind-up's origin at the rig's walk speed
	and stands there from the wind-up on. The replicated root draws it LAG behind (the PC's 0.13 to
	0.27 s), and both remotes are heard LATENCY after the wind-up. The clip decides on its first
	rig step whether it waits.

	On the PC no attack ever waited: on all 20 takes the clip's first row read held false and its
	clock ran a frame a row. On d310ca7 this path reads the same in two ways the PC's rows allow:
	- the 60 Hz replicated root steps back on the decision row (its rows' sample times uneven), so
	  its last move heads away from the origin: the kobold 1.683 to 1.783 from it, the boar 2.357 to
	  2.497;
	- the ActionStarted is handled before the row's rig step and the Telegraph after it, on the same
	  logged row (a handler is stamped with the logged row, whose interval holds the next rig step).
	Either way the clip must wait: held, its clock standing, from its first row, for at most
	enemy.gait.attackWaitSeconds, and then run.

	On 577a59a the PC's attacks still never waited (AW 566(f): held false on all 20 takes, the
	Telegraph heard first on 19). The client meets a spawned enemy before its parts: the tag
	replicates before the model's descendants (442, D-543) and its PrimaryPart reference after them
	(D-571), and Replication.watch attaches the driver in the tag's handler. So the last block
	watches an empty model with the rig's attributes, then its parts arrive (Choreo's
	DescendantAdded fired for each, as the engine does) and its PrimaryPart resolves.
]]

-- Fresh modules, as when this spec runs alone.
Harness.reset()

local function frameSignal()
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
	-- Choreo's rig step (bound just before the camera's): the spec steps the rig itself.
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
})

local Choreo = Harness.load("src/client/choreo/Choreo")
local Replication = Harness.load("src/client/controllers/Replication")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local Enemies = Harness.load("src/shared/data/enemies")
local ChoreoData = Harness.load("src/shared/data/choreo")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local Locomotion = Harness.load("src/client/choreo/Locomotion")
local Rigs = Harness.load("src/shared/data/rigs")

-- The PC's lag views (the drawn root 0.13 to 0.27 s behind the server's body, AV 556) and how
-- long after the wind-up began both remotes are heard.
local LAG: { [number]: number } = { [60] = 0.2, [144] = 0.17 }
local LATENCY = 0.03
-- A 60 Hz replicated root's uneven sample times, in rows, by row: on the decision row it stands
-- further from the origin than on the row before.
local UNEVEN_ROWS = { 0.6, -0.4, 0.9, -0.7, 0.2, -0.6 }
-- Rows read from the clip's first: the wait must hold all of them.
local HELD_ROWS = 3
local WAIT_SECONDS: number = ChoreoData.enemy.gait.attackWaitSeconds

local clock = 0
-- The engine's instance signals Choreo connects (the harness's instances fire none): the late
-- block fires DescendantAdded as each part arrives.
local engineSignals: { [any]: { [string]: { (...any) -> () } } } = {}
local function fire(instance: any, eventName: string, ...: any)
	local list = engineSignals[instance]
	if list ~= nil and list[eventName] ~= nil then
		for _, fn in list[eventName] do
			fn(...)
		end
	end
end
Choreo.configure({
	now = function()
		return clock
	end,
	cameraPosition = function()
		return Vector3.zero
	end,
	connect = function(instance: any, eventName: string, fn: (...any) -> ()): any
		local list = engineSignals[instance] or {}
		engineSignals[instance] = list
		list[eventName] = list[eventName] or {}
		table.insert(list[eventName], fn)
		return { Disconnect = function() end }
	end,
})

local function recorder(): any
	return setmetatable({}, {
		__index = function(_self: any, _key: string): any
			return function(): any
				return nil
			end
		end,
	})
end

local function vec(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

type Row = { time: number, held: boolean, fadeHeld: boolean }
type Result = {
	rows: { Row },
	-- The replicated root's distance from the origin on the row before the decision, and on it.
	before: number,
	decision: number,
	-- The seconds the clip read held, and whether its clock ran after.
	waited: number,
	ran: boolean,
}

local function take(
	rigName: string,
	defId: string,
	hz: number,
	uneven: boolean,
	telegraphAfterStep: boolean,
	late: boolean?
): Result
	local dt = 1 / hz
	local lag = LAG[hz]
	clock = 100
	local def = Enemies.byId(defId)
	local attack = def.attacks[1]
	local built = RigBuilder.build(rigName)
	local model = built
	local root = built.PrimaryPart :: BasePart
	root.LocalTransparencyModifier = 0
	local humanoid = built:FindFirstChildOfClass("Humanoid") :: any
	humanoid.MoveDirection = Vector3.zero
	humanoid.FloorMaterial = Enum.Material.Grass
	if late == true then
		-- Watched before its parts: the model the tag's handler meets, with the rig's attributes.
		model = Instance.new("Model")
		model.Name = built.Name
		for name, value in built:GetAttributes() do
			model:SetAttribute(name, value)
		end
	end
	local folder = Instance.new("Folder")
	model.Parent = folder
	local record = {
		id = 5,
		model = model,
		kind = "Enemy",
		defId = def.id,
		rig = def.skin,
		state = "Idle",
		hp = 100,
		maxHp = 120,
	}
	local mine = { id = 1, model = Instance.new("Model"), kind = "Player", state = "Idle", weaponId = "TrialistSword" }
	Replication.bind({
		net = { on = function() end },
		entities = {
			get = function(id: number): any
				return if id == 5 then record elseif id == 1 then mine else nil
			end,
		},
		localId = function(): number?
			return 1
		end,
		locomotion = Locomotion,
		choreo = {
			get = function(target: any): any
				return Choreo.get(target)
			end,
		},
		clipLibrary = ClipLibrary,
		trails = recorder(),
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
		serverNow = function(): number
			return clock
		end,
	} :: any)
	-- The server's body walks along -Z at the walk speed and stands at the origin from the wind-up.
	local rig = Rigs[rigName]
	local speed: number = rig.walkSpeed
	local height: number = rig.hipHeight + rig.parts[rig.rootPart].size[2] / 2
	local function bodyAt(t: number): Vector3
		return Vector3.new(0, height, -speed * math.min(t, 0))
	end
	local windUpAt = clock + 1.0
	local rowIndex = 0
	local function place()
		rowIndex += 1
		local t = clock - lag - windUpAt
		if uneven then
			t += UNEVEN_ROWS[rowIndex % #UNEVEN_ROWS + 1] * dt
		end
		local p = bodyAt(t)
		-- The spec's parts keep CFrame and Position apart: both are written.
		root.CFrame = CFrame.lookAt(p, p + Vector3.new(0, 0, -1))
		root.Position = p
		root.AssemblyLinearVelocity = if t < 0 then Vector3.new(0, 0, -speed) else Vector3.zero
		humanoid.MoveDirection = if t < 0 then Vector3.new(0, 0, -1) else Vector3.zero
	end
	place()
	Replication.watch(record)
	if late == true then
		-- Its parts arrive (each one's DescendantAdded, its descendants' too), then its PrimaryPart.
		for _, child in built:GetChildren() do
			child.Parent = model
			fire(model, "DescendantAdded", child)
			for _, descendant in child:GetDescendants() do
				fire(model, "DescendantAdded", descendant)
			end
		end
		model.PrimaryPart = root
	end
	local animator = Choreo.get(model)
	animator:step(dt)
	local origin = bodyAt(0)
	local telegraph = {
		entityId = 5,
		attackId = attack.id,
		kind = attack.telegraph,
		windUp = attack.windUp,
		serverTime = windUpAt,
		origin = vec(origin),
		facing = vec(Vector3.new(0, 0, -1)),
	}
	local actionStarted = {
		entityId = 5,
		clipId = "enemy/" .. def.skin .. "/" .. attack.clip,
		serverTime = windUpAt,
		facing = vec(Vector3.new(0, 0, -1)),
	}
	local result: Result = { rows = {}, before = 0, decision = 0, waited = 0, ran = false }
	local sent = false
	local shown: any = nil
	for _ = 1, math.ceil(2.0 * hz) do
		clock += dt
		local decides = false
		if not sent and clock >= windUpAt + LATENCY then
			sent, decides = true, true
			result.before = (root.Position - origin).Magnitude
			if not telegraphAfterStep then
				Replication.dispatch("Telegraph", telegraph)
			end
			Replication.dispatch("ActionStarted", actionStarted)
		end
		place()
		if decides then
			result.decision = (root.Position - origin).Magnitude
		end
		animator:step(dt)
		if decides and telegraphAfterStep then
			Replication.dispatch("Telegraph", telegraph)
		end
		if sent then
			if shown == nil then
				for _, handle in animator.mixer:handles() do
					if handle.clip.attack == true and not handle.done then
						shown = handle
					end
				end
			end
			if shown ~= nil and not shown.done and not result.ran then
				if #result.rows < HELD_ROWS then
					table.insert(
						result.rows,
						{ time = shown.time, held = shown.held == true, fadeHeld = shown.fadeHeld == true }
					)
				end
				if shown.held == true then
					result.waited += dt
				else
					result.ran = true
				end
			end
		end
	end
	Replication.unwatch(record)
	return result
end

local function expectWaits(result: Result, hz: number)
	expect(#result.rows).toBe(HELD_ROWS)
	for _, row in result.rows do
		expect(row.held).toBe(true)
		expect(row.fadeHeld).toBe(true)
		expect(row.time).toBeCloseTo(result.rows[1].time, 1e-9)
	end
	expect(result.waited).toBeLessThanOrEqual(WAIT_SECONDS + 1 / hz + 1e-6)
	expect(result.ran).toBe(true)
end

local RIGS = {
	{ rig = "Kobold", def = "KoboldAxeman" },
	{ rig = "Boar", def = "FrenzyBoar" },
}

local function report(label: string, result: Result)
	local first = result.rows[1]
	print(
		("%s: root %.3f then %.3f from the origin, first row time %.3f held %s, waited %.3f s"):format(
			label,
			result.before,
			result.decision,
			if first ~= nil then first.time else -1,
			tostring(first ~= nil and first.held),
			result.waited
		)
	)
end

describe("EnemyAttackWait: the 60 Hz replicated root steps back on the decision row (AV 556; D-664)", function()
	for _, case in RIGS do
		it(("the %s's attack waits though its root steps back on the row it decides"):format(case.rig), function()
			local result = take(case.rig, case.def, 60, true, false)
			report(case.rig .. " @60 uneven", result)
			-- The root's last move heads away from the origin.
			expect(result.decision).toBeGreaterThan(result.before)
			expectWaits(result, 60)
		end)
	end
end)

describe("EnemyAttackWait: the Telegraph handled after the clip's first step, on its row (AV 556; D-663)", function()
	for _, case in RIGS do
		for _, hz in { 60, 144 } do
			it(("the %s's attack waits at %d Hz"):format(case.rig, hz), function()
				local result = take(case.rig, case.def, hz, false, true)
				report(("%s @%d Telegraph after the step"):format(case.rig, hz), result)
				expectWaits(result, hz)
			end)
		end
	end
end)

describe("EnemyAttackWait: a rig the client met before its parts (AW 566(f); D-677)", function()
	for _, case in RIGS do
		for _, hz in { 60, 144 } do
			it(("the %s's attack waits at %d Hz, its Telegraph heard first"):format(case.rig, hz), function()
				local result = take(case.rig, case.def, hz, false, false, true)
				report(("%s @%d met before its parts"):format(case.rig, hz), result)
				expectWaits(result, hz)
			end)
		end
	end
end)

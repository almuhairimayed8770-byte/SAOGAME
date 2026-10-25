--!strict
--[[
	TargetController's engine glue, loaded fresh with fakes around it: EntityTracker records with
	models and root parts, a recording CameraController and OutlineManager, Net.client() recording
	every TargetRequest, the lock key as a Signal, a fake clock for the TargetRequest pacer, and the
	local character's root. Covers TargetController.lockOn (the dev aim helper's and any caller's
	way to lock a named enemy through the F key's path), the soft assist's candidates (D-112) and
	the lock across the local character's death and respawn (the tracker's local id and the local
	record's State), and the shot held through a death until the shatter (F4).
]]

local luau = require("@lune/luau")

local Signal = Harness.load("src/shared/util/Signal")
local CameraData = Harness.load("src/shared/data/camera")
local TrailingSend = Harness.load("src/shared/net/TrailingSend")
local Combat = Harness.load("src/shared/data/combat")
local Moments = Harness.load("src/shared/data/moments")

local CONTROLLER_PATH = "src/client/controllers/TargetController"

type Fixture = {
	controller: any,
	records: { [number]: any },
	-- Adds a tracked record at a world position (nil: no PrimaryPart).
	add: (id: number, kind: string, position: Vector3?, state: string?) -> any,
	requests: { { entityId: number? } },
	cameraLocks: { any },
	-- Seconds of every CameraController.holdLock (the shot held after a death, F4).
	cameraHolds: { number },
	outlines: { { model: any, importance: string } },
	changes: { any },
	-- Moves the fake clock past the TargetRequest pacer's gap.
	wait: () -> (),
	lockToggle: any,
	-- The fake EntityTracker: its removed, changed and localChanged signals.
	tracker: any,
	-- Sets the tracker's local id and fires localChanged the way EntityTracker does.
	setLocal: (id: number?) -> (),
	-- Marks a record's State and fires changed the way EntityTracker does.
	setState: (record: any, state: string) -> (),
	-- Runs the controller's per-heartbeat lock check.
	heartbeat: () -> (),
}

local function load(origin: Vector3, cameraLook: Vector3): Fixture
	local clock = 100
	local records: { [number]: any } = {}
	local requests: { { entityId: number? } } = {}
	local cameraLocks: { any } = {}
	local cameraHolds: { number } = {}
	local outlines: { { model: any, importance: string } } = {}
	local lockToggle = Signal.new()
	local localId: number? = nil
	local onHeartbeat: ((number) -> ())? = nil
	local root = {
		Position = origin,
		IsA = function(_self: any, name: string): boolean
			return name == "BasePart"
		end,
	}
	local character = {
		FindFirstChild = function(_self: any, name: string): any
			return if name == "HumanoidRootPart" then root else nil
		end,
	}
	local fakes: { [string]: any } = {
		Net = {
			client = function(): any
				return {
					fire = function(name: string, payload: any)
						if name == "TargetRequest" then
							table.insert(requests, { entityId = payload.entityId })
						end
					end,
				}
			end,
		},
		EntityTracker = {
			all = function(): { any }
				local list = {}
				for _, record in records do
					table.insert(list, record)
				end
				table.sort(list, function(a, b)
					return a.id < b.id
				end)
				return list
			end,
			get = function(id: number): any
				return records[id]
			end,
			removed = Signal.new(),
			changed = Signal.new(),
			localChanged = Signal.new(),
			peekLocalId = function(): number?
				return localId
			end,
			isLocal = function(id: number?): boolean
				return id ~= nil and id == localId
			end,
			localRecord = function(): any
				return if localId ~= nil then records[localId] else nil
			end,
		},
		InputController = { lockToggle = lockToggle },
		CameraController = {
			setLockTarget = function(model: any)
				table.insert(cameraLocks, model or false)
			end,
			holdLock = function(seconds: number)
				table.insert(cameraHolds, seconds)
			end,
		},
		Siblings = {
			load = function(_parent: any, path: string): (any, boolean)
				if path == "fx.OutlineManager" then
					return {
						setImportance = function(model: any, importance: string)
							table.insert(outlines, { model = model, importance = importance })
						end,
					},
						true
				end
				return {}, false
			end,
		},
	}
	local services: { [string]: any } = {
		RunService = {
			Heartbeat = {
				Connect = function(_self: any, fn: (number) -> ())
					onHeartbeat = fn
				end,
			},
		},
		Players = { LocalPlayer = { Character = character } },
		ReplicatedStorage = Harness.game():GetService("ReplicatedStorage"),
	}
	local env = Harness.environment()
	env.script = Harness.node(CONTROLLER_PATH)
	env.require = function(target: any): any
		return fakes[target.Name] or Harness.loadModule(target)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			return services[name]
		end,
	}
	env.workspace = { CurrentCamera = { CFrame = CFrame.lookAt(origin, origin + cameraLook) } }
	env.os = {
		clock = function(): number
			return clock
		end,
	}
	env.task = { delay = function() end }
	local controller = luau.load(
		Harness.readFile(CONTROLLER_PATH .. ".luau"),
		{ debugName = CONTROLLER_PATH, environment = env :: any }
	)()
	controller.start()
	local changes: { any } = {}
	controller.targetChanged:Connect(function(record: any)
		table.insert(changes, record or false)
	end)
	return {
		controller = controller,
		records = records,
		add = function(id: number, kind: string, position: Vector3?, state: string?): any
			local model =
				{ Name = kind .. tostring(id), PrimaryPart = if position ~= nil then { Position = position } else nil }
			local record = { id = id, kind = kind, state = state or "Idle", model = model }
			records[id] = record
			return record
		end,
		requests = requests,
		cameraLocks = cameraLocks,
		cameraHolds = cameraHolds,
		outlines = outlines,
		changes = changes,
		wait = function()
			clock += TrailingSend.gapOf("TargetRequest") + 0.01
		end,
		lockToggle = lockToggle,
		tracker = fakes.EntityTracker,
		setLocal = function(id: number?)
			localId = id
			fakes.EntityTracker.localChanged:Fire(id)
		end,
		setState = function(record: any, state: string)
			record.state = state
			fakes.EntityTracker.changed:Fire(record, "State", state)
		end,
		heartbeat = function()
			if onHeartbeat ~= nil then
				onHeartbeat(1 / 60)
			end
		end,
	}
end

local ORIGIN = Vector3.new(0, 3, 0)
local AHEAD = Vector3.new(0, 0, -1)

describe("TargetController.lockOn", function()
	it("locks a named live enemy the way the F key does: camera, outline, TargetRequest, signal", function()
		local fixture = load(ORIGIN, AHEAD)
		local boar = fixture.add(7, "Enemy", Vector3.new(0, 1, -5))
		expect(fixture.controller.lockOn(7)).toBe(true)
		expect(fixture.controller.current()).toBe(boar)
		expect(fixture.cameraLocks[#fixture.cameraLocks]).toBe(boar.model)
		expect(fixture.outlines[#fixture.outlines].model).toBe(boar.model)
		expect(fixture.outlines[#fixture.outlines].importance).toBe("Lock")
		expect(fixture.requests).toEqual({ { entityId = 7 } })
		expect(fixture.changes).toEqual({ boar })
		-- The same lock again changes nothing and sends nothing.
		expect(fixture.controller.lockOn(7)).toBe(true)
		expect(#fixture.requests).toBe(1)
		expect(#fixture.changes).toBe(1)
	end)

	it("locks an enemy behind the camera too: the caller named it, so the F key's cone does not apply", function()
		local fixture = load(ORIGIN, AHEAD)
		local behind = fixture.add(3, "Enemy", Vector3.new(1, 1, 5))
		-- F would not offer it (outside the camera cone)...
		fixture.lockToggle:Fire()
		expect(fixture.controller.current()).toBeNil()
		-- ...but lockOn takes it.
		expect(fixture.controller.lockOn(3)).toBe(true)
		expect(fixture.controller.current()).toBe(behind)
	end)

	it("refuses an id that is not a live, lockable enemy and keeps the lock it had", function()
		local fixture = load(ORIGIN, AHEAD)
		local boar = fixture.add(1, "Enemy", Vector3.new(0, 1, -5))
		fixture.add(2, "Player", Vector3.new(0, 3, -4))
		fixture.add(3, "Enemy", Vector3.new(0, 1, -6), "Dead")
		fixture.add(4, "Enemy", nil)
		fixture.add(5, "Enemy", Vector3.new(0, 1, -(CameraData.lock.range + 1)))
		expect(fixture.controller.lockOn(1)).toBe(true)
		for _, id in { 2, 3, 4, 5, 99 } do
			expect(fixture.controller.lockOn(id)).toBe(false)
			expect(fixture.controller.current()).toBe(boar)
		end
		expect(fixture.requests).toEqual({ { entityId = 1 } })
	end)

	it("nil clears the lock through the same path", function()
		local fixture = load(ORIGIN, AHEAD)
		fixture.add(1, "Enemy", Vector3.new(0, 1, -5))
		fixture.controller.lockOn(1)
		fixture.wait()
		expect(fixture.controller.lockOn(nil)).toBe(true)
		expect(fixture.controller.current()).toBeNil()
		expect(fixture.cameraLocks[#fixture.cameraLocks]).toBe(false)
		expect(fixture.requests).toEqual({ { entityId = 1 }, { entityId = nil } })
		expect(fixture.changes[#fixture.changes]).toBe(false)
		-- Clearing with nothing locked is still a success and sends nothing new.
		expect(fixture.controller.lockOn(nil)).toBe(true)
		expect(#fixture.requests).toBe(2)
	end)
end)

describe("TargetController.assistCandidates", function()
	it("lists living enemies flat from the body with the signed bearing from its look", function()
		local fixture = load(ORIGIN, AHEAD)
		fixture.add(1, "Enemy", Vector3.new(-4, 1, -4)) -- ahead-left, 45 degrees, lower than the root
		fixture.add(2, "Enemy", Vector3.new(3, 5, 0)) -- right, 90 degrees
		fixture.add(3, "Player", Vector3.new(0, 3, -2))
		fixture.add(4, "Enemy", Vector3.new(0, 1, -3), "Dead")
		fixture.add(5, "Enemy", nil)
		local list = fixture.controller.assistCandidates(ORIGIN, AHEAD)
		expect(#list).toBe(2)
		expect(list[1].id).toBe(1)
		expect(list[1].distance).toBeCloseTo(math.sqrt(32), 1e-6)
		expect(list[1].bearing).toBeCloseTo(45, 1e-6)
		expect(list[2].id).toBe(2)
		expect(list[2].distance).toBeCloseTo(3, 1e-6)
		expect(list[2].bearing).toBeCloseTo(-90, 1e-6)
		-- Measured from the look it is given, not the camera's.
		local turned = fixture.controller.assistCandidates(ORIGIN, Vector3.new(1, 0, 0))
		expect(turned[2].bearing).toBeCloseTo(0, 1e-6)
	end)
end)

describe("TargetController across the local character's death and respawn", function()
	-- A player record for the local character, made the tracker's local id, and a boar locked.
	local function lockedWhileAlive(): (Fixture, any, any)
		local fixture = load(ORIGIN, AHEAD)
		local me = fixture.add(50, "Player", ORIGIN)
		fixture.setLocal(50)
		local boar = fixture.add(7, "Enemy", Vector3.new(0, 1, -5))
		expect(fixture.controller.lockOn(7)).toBe(true)
		fixture.wait()
		return fixture, me, boar
	end

	it("clears the lock when the local character dies: outline, TargetRequest, signal; the shot holds", function()
		local fixture, me, boar = lockedWhileAlive()
		fixture.setState(me, "Dead")
		expect(fixture.controller.current()).toBeNil()
		-- The camera keeps the framing through the freeze and lets go at the shatter (F4).
		expect(fixture.cameraLocks).toEqual({ boar.model })
		expect(fixture.cameraHolds).toEqual({ Moments.deathDuckDelay() + Combat.deathFreeze })
		expect(fixture.outlines[#fixture.outlines].model).toBe(boar.model)
		expect(fixture.outlines[#fixture.outlines].importance).toBe("Normal")
		expect(fixture.requests).toEqual({ { entityId = 7 }, { entityId = nil } })
		expect(fixture.changes[#fixture.changes]).toBe(false)
	end)

	it("keeps the lock on another player's death and on the local record's other states", function()
		local fixture, me, boar = lockedWhileAlive()
		fixture.setState(fixture.add(60, "Player", Vector3.new(4, 3, 0)), "Dead")
		fixture.setState(me, "Stagger")
		fixture.tracker.changed:Fire(me, "Hp", 0)
		expect(fixture.controller.current()).toBe(boar)
		expect(fixture.requests).toEqual({ { entityId = 7 } })
	end)

	it("clears the lock when a respawn replaces the local record (old id to a new id, no nil between)", function()
		-- The new character's record can arrive before the old one is untracked, so the tracker
		-- goes from the old id straight to the new one: the measured case, a boar 70 studs off
		-- (inside the 80-stud break distance) still locked on the new character.
		local fixture, _, boar = lockedWhileAlive()
		boar.model.PrimaryPart.Position = Vector3.new(0, 1, -70)
		fixture.add(51, "Player", ORIGIN)
		fixture.setLocal(51)
		expect(fixture.controller.current()).toBeNil()
		expect(fixture.cameraLocks[#fixture.cameraLocks]).toBe(false)
		expect(fixture.requests).toEqual({ { entityId = 7 }, { entityId = nil } })
		expect(fixture.changes[#fixture.changes]).toBe(false)
	end)

	it("starts the respawned character unlocked when the old rig goes first (old id, nil, new id)", function()
		local fixture, me = lockedWhileAlive()
		fixture.setState(me, "Dead")
		fixture.wait()
		fixture.setLocal(nil)
		fixture.add(51, "Player", ORIGIN)
		fixture.setLocal(51)
		expect(fixture.controller.current()).toBeNil()
		expect(fixture.requests).toEqual({ { entityId = 7 }, { entityId = nil } })
	end)

	it("sends a lock taken before the first record arrives again when it does (nil to an id)", function()
		local fixture = load(ORIGIN, AHEAD)
		local boar = fixture.add(7, "Enemy", Vector3.new(0, 1, -5))
		expect(fixture.controller.lockOn(7)).toBe(true)
		fixture.wait()
		fixture.add(50, "Player", ORIGIN)
		fixture.setLocal(50)
		expect(fixture.controller.current()).toBe(boar)
		expect(fixture.requests).toEqual({ { entityId = 7 }, { entityId = 7 } })
	end)

	it("sends a lock again when the same local id comes back, and keeps it", function()
		local fixture, _, boar = lockedWhileAlive()
		fixture.setLocal(50)
		expect(fixture.controller.current()).toBe(boar)
		expect(fixture.requests).toEqual({ { entityId = 7 }, { entityId = 7 } })
	end)

	it("takes no lock while the local character is dead: neither the F key nor lockOn", function()
		local fixture = load(ORIGIN, AHEAD)
		local me = fixture.add(50, "Player", ORIGIN)
		fixture.setLocal(50)
		fixture.add(7, "Enemy", Vector3.new(0, 1, -5))
		fixture.setState(me, "Dead")
		fixture.lockToggle:Fire()
		expect(fixture.controller.current()).toBeNil()
		expect(fixture.controller.lockOn(7)).toBe(false)
		expect(fixture.controller.current()).toBeNil()
		expect(fixture.requests).toEqual({})
		expect(fixture.changes).toEqual({})
		-- Clearing is still allowed, and the respawned character locks again.
		expect(fixture.controller.lockOn(nil)).toBe(true)
		fixture.add(51, "Player", ORIGIN)
		fixture.setLocal(51)
		fixture.lockToggle:Fire()
		expect(fixture.controller.current()).toBe(fixture.records[7])
	end)
end)

describe("TargetController measures an enemy where its body is drawn (D-193)", function()
	-- A rush draws a Charger's body ahead of its hidden root part (D-171): the lock's range, its
	-- break distance and the soft assist measure the body the player sees.
	local function drawAway(record: any, root: Vector3, offset: CFrame)
		local DrawnBody = Harness.load("src/client/choreo/DrawnBody")
		record.model.PrimaryPart.CFrame = CFrame.new(root)
		DrawnBody.publish(record.model, offset)
	end

	local function clear(record: any)
		local DrawnBody = Harness.load("src/client/choreo/DrawnBody")
		DrawnBody.publish(record.model, nil)
	end

	it("locks a boar drawn inside the lock range whose root is still outside it", function()
		local fixture = load(ORIGIN, AHEAD)
		local far = Vector3.new(0, 1, -(CameraData.lock.range + 6))
		local boar = fixture.add(1, "Enemy", far)
		-- Drawn 10 studs nearer than its root, down the root's own look (-Z).
		drawAway(boar, far, CFrame.new(0, 0, 10))
		expect(fixture.controller.lockOn(1)).toBe(true)
		expect(fixture.controller.current()).toBe(boar)
		local listed = fixture.controller.candidates()
		expect(#listed).toBe(1)
		expect(listed[1].distance).toBeCloseTo(
			(Vector3.new(0, 1, -(CameraData.lock.range - 4)) - ORIGIN).Magnitude,
			1e-3
		)
		clear(boar)
	end)

	it("breaks the lock when the drawn body runs past the break distance, not when the root does", function()
		local fixture = load(ORIGIN, AHEAD)
		local near = Vector3.new(0, 1, -10)
		local boar = fixture.add(1, "Enemy", near)
		expect(fixture.controller.lockOn(1)).toBe(true)
		-- The root lags well inside the break distance; the drawn body is already beyond it.
		local beyond = CameraData.lock.breakDistance + 5
		drawAway(boar, near, CFrame.new(0, 0, -(beyond - 10)))
		fixture.heartbeat()
		expect(fixture.controller.current()).toBeNil()
		clear(boar)
		-- And the other way: a root past the break distance under a body drawn near holds the lock.
		local again = fixture.add(2, "Enemy", near)
		fixture.wait()
		expect(fixture.controller.lockOn(2)).toBe(true)
		local farRoot = Vector3.new(0, 1, -(CameraData.lock.breakDistance + 5))
		again.model.PrimaryPart.Position = farRoot
		drawAway(again, farRoot, CFrame.new(0, 0, CameraData.lock.breakDistance - 5))
		fixture.heartbeat()
		expect(fixture.controller.current()).toBe(again)
		clear(again)
	end)

	it("gives the soft assist the drawn body's bearing and distance", function()
		local fixture = load(ORIGIN, AHEAD)
		local root = Vector3.new(0, 1, -12)
		local boar = fixture.add(1, "Enemy", root)
		-- Drawn 4 studs to the root's right (+X) and 8 nearer.
		drawAway(boar, root, CFrame.new(4, 0, 8))
		local list = fixture.controller.assistCandidates(ORIGIN, AHEAD)
		expect(#list).toBe(1)
		expect(list[1].distance).toBeCloseTo(math.sqrt(4 * 4 + 4 * 4), 1e-3)
		expect(list[1].bearing).toBeCloseTo(-45, 1e-3)
		clear(boar)
	end)
end)

describe("TargetController holds the shot through a death until the shatter (F4)", function()
	local SHATTER = Moments.deathDuckDelay() + Combat.deathFreeze

	local function locked(): (Fixture, any)
		local fixture = load(ORIGIN, AHEAD)
		local boar = fixture.add(7, "Enemy", Vector3.new(0, 1, -5))
		expect(fixture.controller.lockOn(7)).toBe(true)
		fixture.wait()
		return fixture, boar
	end

	it("ends the lock on the target's death but holds the camera's framing until the shatter", function()
		local fixture, boar = locked()
		fixture.setState(boar, "Dead")
		-- The lock itself ends now: outline, the server's lock, the signal.
		expect(fixture.controller.current()).toBeNil()
		expect(fixture.outlines[#fixture.outlines].model).toBe(boar.model)
		expect(fixture.outlines[#fixture.outlines].importance).toBe("Normal")
		expect(fixture.requests).toEqual({ { entityId = 7 }, { entityId = nil } })
		expect(fixture.changes[#fixture.changes]).toBe(false)
		-- The shot does not: no pull-back to the free camera through the freeze.
		expect(fixture.cameraLocks).toEqual({ boar.model })
		expect(fixture.cameraHolds).toEqual({ SHATTER })
		expect(SHATTER).toBeGreaterThanOrEqual(Combat.deathFreeze)
	end)

	it("holds the same way when the heartbeat check finds the target Dead first", function()
		local fixture, boar = locked()
		boar.state = "Dead" -- the attribute landed without a changed event yet
		fixture.heartbeat()
		expect(fixture.controller.current()).toBeNil()
		expect(fixture.cameraLocks).toEqual({ boar.model })
		expect(fixture.cameraHolds).toEqual({ SHATTER })
	end)

	it("lets the shot go at once on the key, on the break distance and when the target is removed", function()
		local fixture, boar = locked()
		fixture.controller.clear()
		expect(fixture.cameraLocks).toEqual({ boar.model, false })

		fixture, boar = locked()
		boar.model.PrimaryPart.Position = Vector3.new(0, 1, -(CameraData.lock.breakDistance + 5))
		fixture.heartbeat()
		expect(fixture.controller.current()).toBeNil()
		expect(fixture.cameraLocks).toEqual({ boar.model, false })

		fixture, boar = locked()
		fixture.tracker.removed:Fire(boar)
		expect(fixture.cameraLocks).toEqual({ boar.model, false })
		expect(fixture.cameraHolds).toEqual({})
	end)

	it("holds nothing when no lock was taken", function()
		local fixture = load(ORIGIN, AHEAD)
		local boar = fixture.add(7, "Enemy", Vector3.new(0, 1, -5))
		fixture.setState(boar, "Dead")
		expect(fixture.cameraLocks).toEqual({})
		expect(fixture.cameraHolds).toEqual({})
	end)

	it("takes a new lock during the hold through the key, and the camera takes it over", function()
		local fixture, boar = locked()
		local kobold = fixture.add(8, "Enemy", Vector3.new(2, 1, -6))
		fixture.setState(boar, "Dead")
		fixture.lockToggle:Fire()
		expect(fixture.controller.current()).toBe(kobold)
		expect(fixture.cameraLocks).toEqual({ boar.model, kobold.model })
	end)
end)

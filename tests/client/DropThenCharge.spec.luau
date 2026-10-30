--!strict
--[[
	A wind-up begun right after the server dropped one (RushEnded "Dropped", D-254) is a new attack
	and reads as one on this client. The DevCombat Studio hooks (D-333) drop and begin in one go:
	"enemy" (or "hold") on a boar mid-wind-up drops its attack, and a "charge" right after starts a
	fresh one in the same server instant, well before the dropped wind-up would have ended. The
	game does the same when a sleeping enemy wakes inside the wind-up it dropped. The guard that
	keeps the dropped attack's own late Telegraph and ActionStarted from showing (D-222, D-260)
	cut at the dropped wind-up's end, so the new attack's tell and clip were thrown away too: in
	the end-to-end probe (the real server's hooks, the real Replication, RushDraw and Choreo) the
	charge drew no tell and no crouch, and the run started from the idle pose (0.93 studs in one
	frame at 0 lag, 0.47 a frame otherwise). The dropped attack began before the drop, a new one
	at or after it, so the drop's own time is the cut.
]]
local Replication = Harness.load("src/client/controllers/Replication")
local Enemies = Harness.load("src/shared/data/enemies")

local function recorder(moduleName: string, calls: { any }): any
	return setmetatable({}, {
		__index = function(_, key)
			return function(...)
				table.insert(calls, { module = moduleName, fn = key, args = { ... } })
			end
		end,
	})
end

local function fakeSignal(): any
	local handlers: { (...any) -> () } = {}
	return {
		Connect = function(_, handler)
			table.insert(handlers, handler)
			return { Disconnect = function() end }
		end,
		Fire = function(_, ...)
			for _, handler: any in handlers do
				handler(...)
			end
		end,
	}
end

local function attackOf(defId: string, attackId: string): any
	for _, attack in Enemies.byId(defId).attacks do
		if attack.id == attackId then
			return attack
		end
	end
	error("no attack " .. attackId)
end

local function setup(): any
	local calls: { any } = {}
	local state = { clock = 50, server = 100 }
	local models = { me = Instance.new("Model"), axeman = Instance.new("Model") }
	local records: { [number]: any } = {
		[1] = { id = 1, model = models.me, kind = "Player", rig = "PlayerR15", weaponId = "TrialistSword" },
		[8] = { id = 8, model = models.axeman, kind = "Enemy", rig = "Kobold", defId = "KoboldAxeman" },
	}
	local animators = {}
	local deps: any = {
		net = { on = function() end },
		entities = {
			get = function(id)
				return records[id]
			end,
			all = function()
				return {}
			end,
			localChanged = fakeSignal(),
		},
		localId = function()
			return 1
		end,
		locomotion = recorder("locomotion", calls),
		choreo = {
			get = function(model)
				local animator = animators[model]
				if animator == nil then
					local name = if (model :: any) == models.axeman then "axeman" else "me"
					animator = { name = name, events = fakeSignal(), handles = 0 }
					function animator.play(self, clipId, opts)
						table.insert(calls, { module = "animator:" .. name, fn = "play", args = { clipId, opts } })
						self.handles += 1
						return { name = "handle" .. self.handles, clipId = clipId }
					end
					function animator.stop(_, handle, blendOut)
						table.insert(calls, { module = "animator:" .. name, fn = "stop", args = { handle, blendOut } })
					end
					function animator.hitStop() end
					animators[model] = animator
				end
				return animator
			end,
		},
		clipLibrary = {
			has = function()
				return true
			end,
		},
		trails = recorder("trails", calls),
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
		weaponCategory = function()
			return "OneHandedSword"
		end,
		trailToken = function()
			return "TrailCyanWhite"
		end,
		positionOf = function()
			return Vector3.zero
		end,
		schedule = function() end,
		now = function()
			return state.clock
		end,
		serverNow = function()
			return state.server
		end,
	}
	Replication.bind(deps)
	local function count(moduleName: string, fn: string): number
		local found = 0
		for _, call in calls do
			if call.module == moduleName and call.fn == fn then
				found += 1
			end
		end
		return found
	end
	return { state = state, count = count }
end

local OVERHEAD = attackOf("KoboldAxeman", "Overhead")
local CLIP = "enemy/" .. Enemies.byId("KoboldAxeman").skin .. "/" .. OVERHEAD.clip

local function telegraph(serverTime: number): any
	return {
		entityId = 8,
		attackId = "Overhead",
		kind = OVERHEAD.telegraph,
		windUp = OVERHEAD.windUp,
		serverTime = serverTime,
		origin = { 0, 3.3, 0 },
		facing = { 0, 0, -1 },
		shape = { kind = OVERHEAD.groundShape, length = OVERHEAD.reach, width = OVERHEAD.arc },
	}
end

local function started(serverTime: number): any
	return { entityId = 8, clipId = CLIP, serverTime = serverTime, facing = { 0, 0, -1 } }
end

local function dropped(beat: number, serverTime: number): any
	return { entityId = 8, launchedAt = beat, serverTime = serverTime, distance = 0, reason = "Dropped" }
end

describe("a wind-up begun at a drop is a new attack (D-254, the DevCombat hooks)", function()
	it("shows its tell and plays its clip; the dropped one's late messages still show nothing", function()
		local t = setup()
		Replication.dispatch("Telegraph", telegraph(100))
		Replication.dispatch("ActionStarted", started(100))
		-- "enemy" 0.2 s into the wind-up drops it, and "charge" begins the next in the same instant.
		local at = 100.2
		expect(at < 100 + OVERHEAD.windUp).toBe(true)
		t.state.server = at
		Replication.dispatch("RushEnded", dropped(100 + OVERHEAD.windUp, at))
		expect(t.count("telegraphs", "hide")).toBe(1)
		Replication.dispatch("Telegraph", telegraph(at))
		Replication.dispatch("ActionStarted", started(at))
		expect(t.count("telegraphs", "show")).toBe(2)
		expect(t.count("animator:axeman", "play")).toBe(2)
		-- The dropped wind-up's own Telegraph (unreliable) and clip heard late show nothing.
		Replication.dispatch("Telegraph", telegraph(100))
		Replication.dispatch("ActionStarted", started(100))
		expect(t.count("telegraphs", "show")).toBe(2)
		expect(t.count("animator:axeman", "play")).toBe(2)
	end)

	it("a new wind-up heard before the drop it follows keeps its tell and its clip", function()
		local t = setup()
		Replication.dispatch("Telegraph", telegraph(100))
		Replication.dispatch("ActionStarted", started(100))
		-- The unreliable Telegraph of the new attack overtakes the reliable RushEnded.
		local at = 100.2
		t.state.server = at
		Replication.dispatch("Telegraph", telegraph(at))
		Replication.dispatch("ActionStarted", started(at))
		Replication.dispatch("RushEnded", dropped(100 + OVERHEAD.windUp, at))
		expect(t.count("telegraphs", "hide")).toBe(0)
		expect(t.count("animator:axeman", "stop")).toBe(0)
	end)

	it("a drop in the wind-up still takes down the attack it drops, and a wake after it plays", function()
		local t = setup()
		Replication.dispatch("Telegraph", telegraph(100))
		Replication.dispatch("ActionStarted", started(100))
		t.state.server = 100.5
		Replication.dispatch("RushEnded", dropped(100 + OVERHEAD.windUp, 100.5))
		expect(t.count("telegraphs", "hide")).toBe(1)
		expect(t.count("animator:axeman", "stop")).toBe(1)
		Replication.dispatch("Telegraph", telegraph(103))
		Replication.dispatch("ActionStarted", started(103))
		expect(t.count("telegraphs", "show")).toBe(2)
		expect(t.count("animator:axeman", "play")).toBe(2)
	end)
end)

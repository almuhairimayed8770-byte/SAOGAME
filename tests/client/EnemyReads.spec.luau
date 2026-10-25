--!strict
-- How an enemy's beats read on this client (F7, F11, F8, F16 and the rush leftovers): what
-- Replication hands the telegraphs, the rigs and the reactions for an enemy's wind-up, strike and
-- parry, dispatched at fake modules on a fake server clock.
local Replication = Harness.load("src/client/controllers/Replication")
local Enemies = Harness.load("src/shared/data/enemies")

-- A recorder module: every field is a function that logs its call.
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
	local handlers = {}
	return {
		Connect = function(_, handler)
			table.insert(handlers, handler)
			return { Disconnect = function() end }
		end,
		Fire = function(_, ...)
			for _, handler in handlers do
				handler(...)
			end
		end,
	}
end

local function fakeAnimator(name: string, calls: { any }): any
	local animator: any = { name = name, events = fakeSignal(), handles = 0 }
	local function log(fn: string, ...)
		table.insert(calls, { module = "animator:" .. name, fn = fn, args = { ... } })
	end
	function animator.hitStop(_, frames)
		log("hitStop", frames)
	end
	function animator.play(self, clipId, opts)
		log("play", clipId, opts)
		self.handles += 1
		return { name = "handle" .. self.handles, clipId = clipId }
	end
	function animator.stop(_, handle, blendOut)
		log("stop", handle, blendOut)
	end
	return animator
end

local function attackOf(defId: string, attackId: string): any
	for _, attack in Enemies.byId(defId).attacks do
		if attack.id == attackId then
			return attack
		end
	end
	error("no attack " .. attackId)
end

-- options.groundY: the world's ground under every probe (a world cast); nil: no world to ask.
-- options.defence: the local fighter's defence (D-258); nil: the dependency is left out.
local function setup(options: { groundY: number?, defence: (() -> (string, number?))? }?): any
	local opts = options or {}
	local calls: { any } = {}
	local state = { clock = 50, server = 100 }
	local models = {
		me = Instance.new("Model"),
		boar = Instance.new("Model"),
		axeman = Instance.new("Model"),
	}
	local records = {
		[1] = { id = 1, model = models.me, kind = "Player", rig = "PlayerR15", weaponId = "TrialistSword" },
		[7] = { id = 7, model = models.boar, kind = "Enemy", rig = "Boar", defId = "FrenzyBoar" },
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
					local name = "?"
					for key, candidate in models do
						if candidate == model then
							name = key
						end
					end
					animator = fakeAnimator(name, calls)
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
	if opts.defence ~= nil then
		deps.localDefence = opts.defence
	end
	local groundY = opts.groundY
	if groundY ~= nil then
		deps.worldCast = function(start: CFrame, size: Vector3, vector: Vector3): (number?, Vector3?)
			local fall = start.Position.Y - size.Y / 2 - groundY
			if vector.Y < 0 and fall >= 0 and fall <= -vector.Y then
				return fall, Vector3.yAxis
			end
			return nil, nil
		end
	end
	Replication.bind(deps)
	local function find(moduleName: string, fn: string): { any }
		local found = {}
		for _, call in calls do
			if call.module == moduleName and call.fn == fn then
				table.insert(found, call)
			end
		end
		return found
	end
	return { calls = calls, state = state, models = models, records = records, find = find, deps = deps }
end

local function telegraph(entityId: number, attackId: string, serverTime: number, origin: { number }): any
	local defId = if entityId == 7 then "FrenzyBoar" else "KoboldAxeman"
	local attack = attackOf(defId, attackId)
	return {
		entityId = entityId,
		attackId = attackId,
		kind = attack.telegraph,
		windUp = attack.windUp,
		serverTime = serverTime,
		origin = origin,
		facing = { 0, 0, -1 },
		shape = { kind = attack.groundShape, length = attack.reach, width = attack.arc },
	}
end

describe("an enemy's tell (F7, F11)", function()
	it("a blow's tell is told its strike, so it holds to the snap; a rush's line is not", function()
		local t = setup()
		Replication.dispatch("Telegraph", telegraph(8, "Overhead", 100, { 0, 3.3, 0 }))
		local shows = t.find("telegraphs", "show")
		expect(#shows).toBe(1)
		expect(shows[1].args[8]).toBe(attackOf("KoboldAxeman", "Overhead").strike)
		Replication.dispatch("Telegraph", telegraph(7, "Charge", 100.5, { 10, 2.4, 0 }))
		shows = t.find("telegraphs", "show")
		expect(#shows).toBe(2)
		expect(shows[2].args[8]).toBe(nil)
	end)

	it("the ground shape lies on the ground under the enemy, not at its root's height", function()
		local t = setup({ groundY = 0.25 })
		Replication.dispatch("Telegraph", telegraph(8, "Overhead", 100, { 4, 3.3, -2 }))
		local origin = t.find("telegraphs", "show")[1].args[4] :: Vector3
		expect(origin.X).toBeCloseTo(4)
		expect(origin.Z).toBeCloseTo(-2)
		expect(origin.Y).toBeCloseTo(0.25, 1e-6)
	end)

	it("with no world to ask it stands on the root's hover below the root", function()
		local t = setup()
		local model = t.models.axeman
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Parent = model
		model.PrimaryPart = root
		local humanoid = Instance.new("Humanoid")
		humanoid.HipHeight = 2.3
		humanoid.Parent = model
		Replication.dispatch("Telegraph", telegraph(8, "Overhead", 100, { 0, 3.3, 0 }))
		local origin = t.find("telegraphs", "show")[1].args[4] :: Vector3
		expect(origin.Y).toBeCloseTo(3.3 - 2.3 - 1, 1e-6)
	end)
end)

local function clipOf(defId: string, attackId: string): string
	local def = Enemies.byId(defId)
	return "enemy/" .. def.skin .. "/" .. attackOf(defId, attackId).clip
end

local function started(entityId: number, clipId: string, serverTime: number): any
	return { entityId = entityId, clipId = clipId, serverTime = serverTime, facing = { 0, 0, -1 } }
end

local function dropped(entityId: number, beat: number, serverTime: number): any
	return {
		entityId = entityId,
		launchedAt = beat,
		serverTime = serverTime,
		distance = 0,
		reason = "Dropped",
	}
end

-- Item 5 (D-254): a hold or a sleep in the wind-up dropped the attack without a word to the clients:
-- the Kobold's tell stayed lit and its chop played on.
describe("an attack the server dropped, and its messages heard late (items 5 and 8)", function()
	it("a blow dropped in its wind-up takes its tell down and fades its swing out", function()
		local t = setup()
		local overhead = attackOf("KoboldAxeman", "Overhead")
		local clip = clipOf("KoboldAxeman", "Overhead")
		Replication.dispatch("Telegraph", telegraph(8, "Overhead", 100, { 0, 3.3, 0 }))
		Replication.dispatch("ActionStarted", started(8, clip, 100))
		local handle = t.find("animator:axeman", "play")[1]
		expect(handle ~= nil).toBe(true)
		t.state.server = 100.5
		Replication.dispatch("RushEnded", dropped(8, 100 + overhead.windUp, 100.5))
		local hides = t.find("telegraphs", "hide")
		expect(#hides).toBe(1)
		expect(hides[1].args[1]).toBe(t.models.axeman)
		local stops = t.find("animator:axeman", "stop")
		expect(#stops).toBe(1)
		expect(stops[1].args[1].name).toBe("handle1")
		-- Its Telegraph or ActionStarted heard after the drop shows nothing.
		Replication.dispatch("ActionStarted", started(8, clip, 100))
		Replication.dispatch("Telegraph", telegraph(8, "Overhead", 100, { 0, 3.3, 0 }))
		expect(#t.find("animator:axeman", "play")).toBe(1)
		expect(#t.find("telegraphs", "show")).toBe(1)
		-- The next attack, after the wake, plays as any other.
		Replication.dispatch("Telegraph", telegraph(8, "Overhead", 103, { 0, 3.3, 0 }))
		Replication.dispatch("ActionStarted", started(8, clip, 103))
		expect(#t.find("animator:axeman", "play")).toBe(2)
		expect(#t.find("telegraphs", "show")).toBe(2)
	end)

	it("a drop told for an older attack leaves a newer one lit", function()
		local t = setup()
		local clip = clipOf("KoboldAxeman", "Overhead")
		Replication.dispatch("Telegraph", telegraph(8, "Overhead", 103, { 0, 3.3, 0 }))
		Replication.dispatch("ActionStarted", started(8, clip, 103))
		Replication.dispatch("RushEnded", dropped(8, 101, 101.2))
		expect(#t.find("telegraphs", "hide")).toBe(0)
		expect(#t.find("animator:axeman", "stop")).toBe(0)
	end)

	it("a rush's clip heard after its own RushStarted is not played from the middle of its run", function()
		local t = setup()
		local charge = attackOf("FrenzyBoar", "Charge")
		Replication.dispatch("RushStarted", {
			entityId = 7,
			attackId = "Charge",
			serverTime = 100 + charge.windUp,
			origin = { 10, 2.4, 0 },
			direction = { 0, 0, -1 },
			speed = 28,
			duration = 1,
		})
		Replication.dispatch("ActionStarted", started(7, clipOf("FrenzyBoar", "Charge"), 100))
		expect(#t.find("animator:boar", "play")).toBe(0)
		-- The next wind-up's clip plays.
		Replication.dispatch("ActionStarted", started(7, clipOf("FrenzyBoar", "Charge"), 104))
		expect(#t.find("animator:boar", "play")).toBe(1)
	end)
end)

-- F8 (REVIEW issue 10): the parry's answer waited out a 3-frame hold of both rigs behind the
-- Inverted frame, then popped in on the 4th.
describe("a parry's answer starts on the clash frame (F8)", function()
	local function parried()
		Replication.dispatch("StateChanged", { entityId = 8, state = "Stagger", duration = 1 })
		Replication.dispatch("HitConfirmed", {
			attackerId = 8,
			targetId = 1,
			damage = 0,
			crit = false,
			gaugeDamage = 0,
			killed = false,
			broke = false,
			hitStop = "Normal",
			position = { 0, 3, -2 },
			parried = true,
			guarded = false,
			hitIndex = 1,
		})
	end

	it("holds neither rig: the stagger and the deflect play from the clash", function()
		local t = setup()
		local clip = clipOf("KoboldAxeman", "Overhead")
		Replication.dispatch("Telegraph", telegraph(8, "Overhead", 100, { 0, 3.3, 0 }))
		Replication.dispatch("ActionStarted", started(8, clip, 100))
		parried()
		expect(#t.find("animator:axeman", "hitStop")).toBe(0)
		expect(#t.find("animator:me", "hitStop")).toBe(0)
		-- The clash picture itself still shows.
		expect(#t.find("impact", "hit")).toBe(1)
		local stagger, parry = false, false
		for _, call in t.find("animator:axeman", "play") do
			stagger = stagger or call.args[1] == "enemy/Kobold/Stagger"
		end
		for _, call in t.find("animator:me", "play") do
			parry = parry or call.args[1] == "player/OneHandedSword/Parry"
		end
		expect(stagger).toBe(true)
		expect(parry).toBe(true)
	end)

	it("an open hit still holds both rigs (the hold is the parry's alone to skip)", function()
		local t = setup()
		Replication.dispatch("HitConfirmed", {
			attackerId = 8,
			targetId = 1,
			damage = 20,
			crit = false,
			gaugeDamage = 0,
			killed = false,
			broke = false,
			hitStop = "Normal",
			position = { 0, 3, -2 },
			parried = false,
			guarded = false,
			hitIndex = 1,
		})
		expect(#t.find("animator:axeman", "hitStop")).toBe(1)
		expect(#t.find("animator:me", "hitStop")).toBe(1)
	end)
end)

-- Stands a model's root at `position` looking along `look` (flat).
local function place(model: Model, position: Vector3, look: Vector3)
	local root = model.PrimaryPart
	if root == nil then
		local part = Instance.new("Part")
		part.Name = "HumanoidRootPart"
		part.Size = Vector3.new(2, 2, 1)
		part.Parent = model
		model.PrimaryPart = part
		root = part
	end
	(root :: BasePart).CFrame = CFrame.lookAt(position, position + look)
end

local function confirmed(fields: { [string]: any }?): any
	local payload: { [string]: any } = {
		attackerId = 8,
		targetId = 1,
		damage = 30,
		crit = false,
		gaugeDamage = 0,
		killed = false,
		broke = false,
		hitStop = "Normal",
		position = { 0, 3, -4 },
		parried = false,
		guarded = false,
		hitIndex = 1,
	}
	for key, value in fields or {} do
		payload[key] = value
	end
	return payload
end

-- F16 (D-258): the kobold's blow on the local fighter showed 3 to 4 frames after the axe arrived,
-- waiting for the server. Its reaction (flinch, white flash, the hit's sound) now shows on the
-- strike's server frame when this client can see nothing that would stop it; HP waits for the
-- server, and a server miss takes the flinch back.
describe("an enemy's blow on the local fighter, shown on its strike frame (F16)", function()
	local overhead = attackOf("KoboldAxeman", "Overhead")
	local lands = 100 + overhead.windUp + overhead.strike
	local FLINCH = "player/OneHandedSword/FlinchFront"

	local function plays(t: any, clipId: string): { any }
		local found = {}
		for _, call in t.find("animator:me", "play") do
			if call.args[1] == clipId then
				table.insert(found, call)
			end
		end
		return found
	end

	-- The kobold at the origin facing -Z, the local fighter `distance` studs in front facing it,
	-- `side` studs off its line; the Overhead heard from its start.
	local function stage(state: string, leftAt: number?, distance: number?, side: number?): any
		local t
		t = setup({
			defence = function()
				return t.state.defence, t.state.leftAt
			end,
		})
		t.state.defence = state
		t.state.leftAt = leftAt
		place(t.models.axeman, Vector3.new(0, 3, 0), Vector3.new(0, 0, -1))
		place(t.models.me, Vector3.new(side or 0, 3, -(distance or 3.5)), Vector3.new(0, 0, 1))
		Replication.dispatch("Telegraph", telegraph(8, "Overhead", 100, { 0, 3, 0 }))
		Replication.dispatch("ActionStarted", started(8, clipOf("KoboldAxeman", "Overhead"), 100))
		local moments = {}
		t.deps.impact = setmetatable({
			hit = function(info, previous)
				table.insert(moments, { info = info, previous = previous })
				return if info.guarded then "Guarded" else "Hit"
			end,
		}, { __index = t.deps.impact })
		t.moments = moments
		return t
	end

	local function at(t: any, serverTime: number)
		t.state.server = serverTime
		Replication.stepStrikes()
	end

	it("shows the flinch, the white flash and the hit's sound on the strike's server frame", function()
		local t = stage("Idle")
		at(t, lands - 0.02)
		expect(#plays(t, FLINCH)).toBe(0)
		at(t, lands + 0.004)
		expect(#plays(t, FLINCH)).toBe(1)
		local flashes = t.find("outline", "flash")
		expect(#flashes).toBe(1)
		expect(flashes[1].args[1]).toBe(t.models.me)
		expect(#t.moments).toBe(1)
		expect(t.moments[1].info.target).toBe(t.models.me)
		expect(t.moments[1].info.involved).toBe(true)
		-- HP waits for the server: no number, no red flash yet.
		expect(#t.find("digits", "show")).toBe(0)
		expect(#t.find("hud", "flashHp")).toBe(0)
		-- Once per blow.
		at(t, lands + 0.03)
		expect(#plays(t, FLINCH)).toBe(1)
	end)

	it("the server's word then brings the number and nothing that already played", function()
		local t = stage("Basic")
		at(t, lands + 0.004)
		t.state.server = lands + 0.06
		Replication.dispatch("StateChanged", { entityId = 1, state = "Stagger", duration = 0.4, direction = "Front" })
		Replication.dispatch("HitConfirmed", confirmed())
		expect(#plays(t, FLINCH)).toBe(1)
		expect(#t.find("animator:me", "stop")).toBe(0)
		expect(#t.find("animator:me", "hitStop")).toBe(0)
		expect(#t.find("outline", "flash")).toBe(1)
		expect(#t.moments).toBe(2)
		expect(t.moments[2].previous).toBe("Hit")
		local digits = t.find("digits", "show")
		expect(#digits).toBe(1)
		expect(digits[1].args[3]).toBe("Taken")
		expect(#t.find("hud", "flashHp")).toBe(1)
	end)

	it("a guard, a dodge, or a guard let go a moment ago shows nothing before the server", function()
		for _, case in { { "Guard", nil }, { "Dodge", nil }, { "Idle", 49.9 }, { "Stagger", nil } } do
			local t = stage(case[1], case[2])
			at(t, lands + 0.004)
			expect(#plays(t, FLINCH)).toBe(0)
			expect(#t.moments).toBe(0)
		end
		-- Let go long enough ago, it is open.
		local t = stage("Idle", 49)
		at(t, lands + 0.004)
		expect(#plays(t, FLINCH)).toBe(1)
	end)

	it("a body near the shape's edge or outside it waits for the server", function()
		for _, spot in { { 5.5, 0 }, { 8, 0 }, { 3, 2.5 }, { -3, 0 } } do
			local t = stage("Idle", nil, spot[1], spot[2])
			at(t, lands + 0.004)
			expect(#plays(t, FLINCH)).toBe(0)
		end
	end)

	it("a server miss takes the flinch back", function()
		local t = stage("Idle")
		at(t, lands + 0.004)
		local flinch = plays(t, FLINCH)[1]
		expect(flinch ~= nil).toBe(true)
		t.state.clock += 0.2
		at(t, lands + 0.2)
		expect(#t.find("animator:me", "stop")).toBe(0)
		t.state.clock += 1
		at(t, lands + 1.2)
		local stops = t.find("animator:me", "stop")
		expect(#stops).toBe(1)
		expect(stops[1].args[1].clipId).toBe(FLINCH)
		expect(#t.find("digits", "show")).toBe(0)
	end)

	it("a guarded word takes the flinch back and plays the block in full", function()
		local t = stage("Idle")
		at(t, lands + 0.004)
		Replication.dispatch("HitConfirmed", confirmed({ damage = 9, guarded = true }))
		local stops = t.find("animator:me", "stop")
		expect(#stops).toBe(1)
		expect(stops[1].args[1].clipId).toBe(FLINCH)
		expect(t.moments[2].info.guarded).toBe(true)
		expect(t.moments[2].previous).toBe(nil)
	end)

	it("the server's word heard before the strike frame leaves nothing to show after it", function()
		local t = stage("Idle")
		t.state.server = lands - 0.01
		Replication.dispatch("HitConfirmed", confirmed())
		at(t, lands + 0.004)
		expect(#plays(t, FLINCH)).toBe(0)
		expect(#t.moments).toBe(1)
	end)

	it("without the local defence nothing is shown before the server", function()
		local t = setup()
		place(t.models.axeman, Vector3.new(0, 3, 0), Vector3.new(0, 0, -1))
		place(t.models.me, Vector3.new(0, 3, -3.5), Vector3.new(0, 0, 1))
		Replication.dispatch("Telegraph", telegraph(8, "Overhead", 100, { 0, 3, 0 }))
		Replication.dispatch("ActionStarted", started(8, clipOf("KoboldAxeman", "Overhead"), 100))
		t.state.server = lands + 0.004
		Replication.stepStrikes()
		expect(#t.find("animator:me", "play")).toBe(0)
	end)
end)

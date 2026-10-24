--!strict
local Replication = Harness.load("src/client/controllers/Replication")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Impact = Harness.load("src/client/fx/Impact")
local combat = Harness.load("src/shared/data/combat")
local fx = Harness.load("src/shared/data/fx")
local sfx = Harness.load("src/shared/data/sfx")
local ui = Harness.load("src/shared/data/ui")
local moments = Harness.load("src/shared/data/moments")

-- A payload override that removes the field (a basic swing carries no artId).
local NONE = table.freeze({})

-- A recorder module: every field is a function that logs its call.
local function recorder(moduleName, calls)
	return setmetatable({}, {
		__index = function(_, key)
			return function(...)
				table.insert(calls, { module = moduleName, fn = key, args = { ... } })
			end
		end,
	})
end

local function fakeSignal()
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

local function fakeAnimator(name, calls)
	local animator = { name = name, events = fakeSignal(), handles = 0 }
	local function log(fn, ...)
		table.insert(calls, { module = "animator:" .. name, fn = fn, args = { ... } })
	end
	function animator:hitStop(frames)
		log("hitStop", frames)
	end
	function animator:play(clipId, opts)
		log("play", clipId, opts)
		self.handles += 1
		return "handle" .. self.handles
	end
	function animator:stop(handle, blendOut)
		log("stop", handle, blendOut)
	end
	function animator:setTimeScale(scale)
		log("setTimeScale", scale)
	end
	return animator
end

-- A fake Locomotion: attach hands back a driver token; both calls are logged like the recorders.
local function fakeLocomotion(calls)
	local attached = 0
	return {
		attach = function(animator, model, options)
			attached += 1
			local driver = { animator = animator, model = model, index = attached }
			table.insert(
				calls,
				{ module = "locomotion", fn = "attach", args = { animator, model, options }, driver = driver }
			)
			return driver
		end,
		-- A stand-in phase a test can read back: the entity id in hundredths of a loop.
		idlePhase = function(id: number): number
			return id / 100
		end,
		destroy = function(driver)
			table.insert(calls, { module = "locomotion", fn = "destroy", args = { driver } })
		end,
	}
end

-- A fake impact director: every call is logged; hiddenSeconds, ownsHighlight and shatterCue answer
-- from `state` and the moments table; afterHidden runs its callback at once when nothing hides
-- the world (state.hidden 0), else schedules it for state.hidden seconds.
local function fakeImpact(calls, state, schedule)
	local function log(fn, ...)
		table.insert(calls, { module = "impact", fn = fn, args = { ... } })
	end
	local answers = {
		hiddenSeconds = function()
			log("hiddenSeconds")
			return state.hidden
		end,
		afterHidden = function(fn)
			log("afterHidden", fn)
			if state.hidden > 0 then
				schedule(state.hidden, fn)
			else
				fn()
			end
		end,
		ownsHighlight = function(info)
			log("ownsHighlight", info)
			return state.ownsHighlight
		end,
		-- The moment the director played (what Replication.contact remembers for the upgrade).
		hit = function(...)
			log("hit", ...)
			return state.moment
		end,
		shatterCue = function(boss, heavy)
			log("shatterCue", boss, heavy)
			return moments.rows[moments.deathFor(boss, heavy)].shatterCue
		end,
	}
	return setmetatable(answers, {
		__index = function(_, key)
			return function(...)
				log(key, ...)
			end
		end,
	})
end

-- options.unknownLocal: the tracker has not resolved the local id yet (localId() -> nil).
-- options.localCharacter: the models key the client already knows as its own character.
local function setup(options)
	options = options or {}
	local calls = {}
	local scheduled = {}
	local state = { hidden = 0, ownsHighlight = false, clock = 100 }
	local models = {
		me = Instance.new("Model"),
		boar = Instance.new("Model"),
		ally = Instance.new("Model"),
		axeman = Instance.new("Model"),
		elite = Instance.new("Model"),
	}
	local records = {
		[1] = {
			id = 1,
			model = models.me,
			kind = "Player",
			rig = "PlayerR15",
			weaponId = "TrialistSword",
			name = "Mira",
		},
		[7] = { id = 7, model = models.boar, kind = "Enemy", rig = "Boar", defId = "FrenzyBoar", name = "Frenzy Boar" },
		[8] = {
			id = 8,
			model = models.axeman,
			kind = "Enemy",
			rig = "Kobold",
			defId = "KoboldAxeman",
			name = "Kobold Axeman",
		},
		-- A spawn-time Elite variant, once the tracker carries the mark (record.elite).
		[9] = {
			id = 9,
			model = models.elite,
			kind = "Enemy",
			rig = "Kobold",
			defId = "KoboldAxeman",
			name = "Elite Kobold Axeman",
			elite = true,
		},
		[2] = {
			id = 2,
			model = models.ally,
			kind = "Player",
			rig = "PlayerR15",
			weaponId = "TrialistSword",
			name = "Ren",
		},
	}
	local animators = {}
	local choreo = {
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
	}
	local localIdValue = if options.unknownLocal then nil else 1
	local localChanged = fakeSignal()
	local localCharacter = nil
	if options.localCharacter ~= nil then
		localCharacter = function()
			return models[options.localCharacter]
		end
	end
	local deps = {
		net = { on = function() end },
		entities = {
			get = function(id)
				return records[id]
			end,
			all = function()
				return {}
			end,
			localChanged = localChanged,
		},
		localId = function()
			return localIdValue
		end,
		localCharacter = localCharacter,
		locomotion = fakeLocomotion(calls),
		choreo = choreo,
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
		impact = fakeImpact(calls, state, function(seconds, fn)
			table.insert(scheduled, { seconds = seconds, fn = fn })
		end),
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
		schedule = function(seconds, fn)
			table.insert(scheduled, { seconds = seconds, fn = fn })
		end,
		now = function()
			return state.clock
		end,
	}
	Replication.bind(deps)
	local function find(moduleName, fn)
		local found = {}
		for _, call in calls do
			if call.module == moduleName and call.fn == fn then
				table.insert(found, call)
			end
		end
		return found
	end
	return {
		calls = calls,
		scheduled = scheduled,
		state = state,
		models = models,
		records = records,
		find = find,
		deps = deps,
		localChanged = localChanged,
		setLocalId = function(id)
			localIdValue = id
		end,
	}
end

-- The shatter cues played straight through SfxPool so far (a death with no rig left).
local function shatterCues(t)
	local found = {}
	for _, call in t.find("sfx", "cue") do
		for _, cue in sfx.shatterCues do
			if call.args[1] == cue then
				table.insert(found, call)
				break
			end
		end
	end
	return found
end

-- The one impact.hit info of the HitConfirmed dispatched last.
local function lastInfo(t)
	local hits = t.find("impact", "hit")
	expect(#hits).toBeGreaterThan(0)
	return hits[#hits].args[1]
end

-- Runs everything scheduled so far, earliest first (stable for equal delays), and clears it.
local function runScheduled(t)
	local list = table.clone(t.scheduled)
	table.clear(t.scheduled)
	local order = {}
	for index in list do
		table.insert(order, index)
	end
	table.sort(order, function(a, b)
		if list[a].seconds ~= list[b].seconds then
			return list[a].seconds < list[b].seconds
		end
		return a < b
	end)
	for _, index in order do
		list[index].fn()
	end
end

-- Replaces the spec's scheduler with a clock-driven one: each scheduled fn runs at its own time,
-- the fake clock set to it. Returns runUntil(at), which runs everything due by `at`, in time order.
local function timedScheduler(t): (at: number) -> ()
	local queue = {}
	t.deps.schedule = function(seconds, fn)
		table.insert(queue, { at = t.state.clock + seconds, fn = fn })
	end
	return function(at: number)
		while true do
			local first = nil
			for index, item in queue do
				if item.at <= at + 1e-9 and (first == nil or item.at < queue[first].at) then
					first = index
				end
			end
			if first == nil then
				break
			end
			local item = table.remove(queue, first)
			t.state.clock = item.at
			item.fn()
		end
		t.state.clock = at
	end
end

local function hit(overrides)
	local payload = {
		attackerId = 1,
		targetId = 7,
		damage = 42,
		crit = false,
		gaugeDamage = 20,
		killed = false,
		broke = false,
		hitStop = "Normal",
		position = { 3, 2, -5 },
		parried = false,
		guarded = false,
		reflected = false,
		artId = "OneHandedSword.Horizontal",
		hitIndex = 1,
	}
	for key, value in overrides or {} do
		payload[key] = if value == NONE then nil else value
	end
	return payload
end

describe("Replication", function()
	it("HitConfirmed: hit-stop on both rigs, a digit, a white flash, nudge and shake for the attacker", function()
		local t = setup()
		Replication.dispatch("HitConfirmed", hit())
		-- Only a parry throws the spark burst; an ordinary hit never does.
		expect(#t.find("sparks", "parry")).toBe(0)
		local attackerStops = t.find("animator:me", "hitStop")
		local targetStops = t.find("animator:boar", "hitStop")
		expect(#attackerStops).toBe(1)
		expect(attackerStops[1].args[1]).toBe(combat.hitStopFrames.Normal)
		expect(#targetStops).toBe(1)
		expect(targetStops[1].args[1]).toBe(combat.hitStopFrames.Normal)
		local digits = t.find("digits", "show")
		expect(#digits).toBe(1)
		expect(digits[1].args[1]).toBe(Vector3.new(3, 2, -5))
		expect(digits[1].args[2]).toBe(42)
		expect(digits[1].args[3]).toBe("Normal")
		local flashes = t.find("outline", "flash")
		expect(#flashes).toBe(1)
		expect(flashes[1].args[1]).toBe(t.models.boar)
		expect(flashes[1].args[2]).toBe("SystemWhite")
		expect(flashes[1].args[3]).toBe(combat.highlightFlashFrames)
		local nudges = t.find("camera", "nudge")
		expect(#nudges).toBe(1)
		expect(nudges[1].args[1]).toBe(Vector3.new(3, 2, -5))
		expect(nudges[1].args[2]).toBe(combat.cameraNudgeStuds)
		local shakes = t.find("camera", "shake")
		expect(#shakes).toBe(1)
		expect(shakes[1].args[1]).toBe("Normal")
		expect(#t.find("hud", "flashHp")).toBe(0)
		-- The local attacker hears the hit-stop tick (2D); the hit's own sound is the director's cue.
		local sounds = {}
		for _, call in t.find("sfx", "play") do
			table.insert(sounds, call.args[1])
		end
		expect(sounds).toEqual({ "hitStopTick.Normal" })
		expect(#t.find("sfx", "cue")).toBe(0)
		-- One impact.hit per confirmation, with everything the director selects on.
		local hits = t.find("impact", "hit")
		expect(#hits).toBe(1)
		local info = hits[1].args[1]
		expect(info.tier).toBe("Normal")
		expect(info.position).toBe(Vector3.new(3, 2, -5))
		expect(info.attacker).toBe(t.models.me)
		expect(info.target).toBe(t.models.boar)
		expect(info.involved).toBe(true)
		expect(info.localAttacker).toBe(true)
		expect(info.trailToken).toBe("TrailCyanWhite")
		expect(info.art).toBe(true)
		for _, flag in { "parried", "guarded", "crit", "isSwitch", "killed" } do
			expect(info[flag]).toBe(false)
		end
		expect(info.partner).toBeNil()
		-- The hit Signal fires after the reactions, so the character controller sees every hit.
		local seen = {}
		Replication.hit:Connect(function(payload)
			table.insert(seen, payload)
		end)
		Replication.dispatch("HitConfirmed", hit({ hitStop = "Final" }))
		expect(#seen).toBe(1)
		expect(seen[1].hitStop).toBe("Final")
	end)

	it("every sound name it plays exists in sfx.luau", function()
		local names = {}
		local function collect(value)
			if typeof(value) == "table" then
				for _, inner in value do
					collect(inner)
				end
			else
				table.insert(names, value)
			end
		end
		collect(Replication.SOUNDS)
		expect(#names).toBeGreaterThan(0)
		for _, name in names do
			local family, entryName = name:match("^([^.]+)%.(.+)$")
			expect(family).never.toBeNil()
			expect(function()
				sfx.get(family, entryName)
			end).never.toThrow()
		end
		expect(function()
			sfx.get("artChime", "TrailCyanWhite")
		end).never.toThrow()
		-- The hit, parry, block, guard, Switch land and shatter sounds are the director's now.
		for _, key in { "impact", "parry", "block", "guardBreak", "shatterCrack", "switchLand" } do
			expect(Replication.SOUNDS[key]).toBeNil()
		end
		-- The death vocals it plays through Sfx.vocalName.
		expect(sfx.vocalName("Charger", "Death")).toBe("enemy.ChargerDeath")
		expect(sfx.vocalName("Brute", "Death")).toBe("enemy.BruteDeath")
	end)

	it("footsteps go through SfxPool.footstep so the surface comes from the floor", function()
		local t = setup()
		Replication.routeClipEvent(t.records[2], "player/OneHandedSword/Run", { time = 0.2, kind = "Footstep" })
		local steps = t.find("sfx", "footstep")
		expect(#steps).toBe(1)
		expect(steps[1].args[1]).toBe(t.models.ally)
		expect(steps[1].args[2]).toBeNil()
		Replication.routeClipEvent(
			t.records[2],
			"player/OneHandedSword/Run",
			{ time = 0.5, kind = "Footstep", data = { surface = "Stone" } }
		)
		expect(t.find("sfx", "footstep")[2].args[2]).toBe("Stone")
		expect(#t.find("sfx", "play")).toBe(0)
	end)

	it("HitConfirmed: the Kill tier gives 10 frames and a Kill shake; crit and Switch pick the digit kind", function()
		local t = setup()
		Replication.dispatch("HitConfirmed", hit({ hitStop = "Kill", killed = true, crit = true }))
		expect(t.find("animator:boar", "hitStop")[1].args[1]).toBe(combat.hitStopFrames.Kill)
		expect(t.find("camera", "shake")[1].args[1]).toBe("Kill")
		expect(t.find("digits", "show")[1].args[3]).toBe("Crit")

		local switch = setup()
		Replication.dispatch("HitConfirmed", hit({ hitStop = "Final", isSwitch = true, crit = true }))
		expect(switch.find("animator:me", "hitStop")[1].args[1]).toBe(combat.hitStopFrames.Final)
		expect(switch.find("digits", "show")[1].args[3]).toBe("Switch")
		-- The blades' white flash and the land sound are the director's Switch row now.
		expect(#switch.find("trails", "flashWhite")).toBe(0)
		expect(#switch.find("sfx", "play")).toBe(1)
		local info = lastInfo(switch)
		expect(info.isSwitch).toBe(true)
		expect(info.crit).toBe(true)
		expect(info.tier).toBe("Final")
	end)

	it("HitConfirmed: a Switch inside a window names the opener as the partner whose blade flashes too", function()
		local t = setup()
		Replication.dispatch(
			"SwitchWindow",
			{ entityId = 7, openerId = 2, position = { 1, 1, 1 }, duration = 0.8, serverTime = 1 }
		)
		Replication.dispatch("HitConfirmed", hit({ isSwitch = true }))
		expect(lastInfo(t).partner).toBe(t.models.ally)
		-- The window is spent by the Switch that landed in it.
		Replication.dispatch("HitConfirmed", hit({ isSwitch = true }))
		expect(lastInfo(t).partner).toBeNil()
		-- A window that closes unused is forgotten when it closes (and never outlives a newer one).
		Replication.dispatch(
			"SwitchWindow",
			{ entityId = 7, openerId = 2, position = { 1, 1, 1 }, duration = 0.8, serverTime = 2 }
		)
		local closes = {}
		for _, item in t.scheduled do
			if item.seconds == 0.8 then
				table.insert(closes, item)
			end
		end
		expect(#closes).toBe(2)
		closes[1].fn()
		Replication.dispatch("HitConfirmed", hit({ isSwitch = true }))
		expect(lastInfo(t).partner).toBe(t.models.ally)
		Replication.dispatch(
			"SwitchWindow",
			{ entityId = 7, openerId = 2, position = { 1, 1, 1 }, duration = 0.8, serverTime = 3 }
		)
		t.scheduled[#t.scheduled].fn()
		Replication.dispatch("HitConfirmed", hit({ isSwitch = true }))
		expect(lastInfo(t).partner).toBeNil()
		-- A hit that is not a Switch never takes a partner.
		Replication.dispatch(
			"SwitchWindow",
			{ entityId = 7, openerId = 2, position = { 1, 1, 1 }, duration = 0.8, serverTime = 4 }
		)
		Replication.dispatch("HitConfirmed", hit())
		expect(lastInfo(t).partner).toBeNil()
	end)

	it("HitConfirmed: damage taken by the local player flashes the HP bar and reads as Taken", function()
		local t = setup()
		Replication.dispatch("HitConfirmed", hit({ attackerId = 7, targetId = 1, crit = true }))
		expect(t.find("digits", "show")[1].args[3]).toBe("Taken")
		expect(#t.find("hud", "flashHp")).toBe(1)
		expect(#t.find("camera", "nudge")).toBe(1)
		expect(#t.find("animator:me", "hitStop")).toBe(1)
		expect(#t.find("animator:boar", "hitStop")).toBe(1)
	end)

	it("HitConfirmed: a hit between two other fighters never moves the local camera or HUD", function()
		local t = setup()
		Replication.dispatch("HitConfirmed", hit({ attackerId = 2, targetId = 7 }))
		expect(#t.find("animator:ally", "hitStop")).toBe(1)
		expect(#t.find("animator:boar", "hitStop")).toBe(1)
		expect(#t.find("camera", "nudge")).toBe(0)
		expect(#t.find("camera", "shake")).toBe(0)
		expect(#t.find("hud", "flashHp")).toBe(0)
		expect(#t.find("digits", "show")).toBe(1)
	end)

	it("HitConfirmed: a parry shows no number, sparks the parrier, rings and shakes Normal", function()
		local t = setup()
		Replication.dispatch("HitConfirmed", hit({ attackerId = 7, targetId = 1, damage = 0, parried = true }))
		expect(#t.find("digits", "show")).toBe(0)
		expect(#t.find("hud", "flashHp")).toBe(0)
		local whiteFlashes = t.find("trails", "flashWhite")
		expect(#whiteFlashes).toBe(1)
		expect(whiteFlashes[1].args[1]).toBe(t.models.me)
		-- The spark burst leaves from the clash point the server sent.
		local bursts = t.find("sparks", "parry")
		expect(#bursts).toBe(1)
		expect(bursts[1].args[1]).toBe(Vector3.new(3, 2, -5))
		-- The ring is the director's Parry cue: Replication plays no parry sound of its own.
		expect(#t.find("sfx", "play")).toBe(0)
		local hits = t.find("impact", "hit")
		expect(#hits).toBe(1)
		expect(hits[1].args[1].parried).toBe(true)
		expect(hits[1].args[1].involved).toBe(true)
		expect(t.find("camera", "shake")[1].args[1]).toBe("Normal")
		expect(#t.find("camera", "nudge")).toBe(0)
		local plays = t.find("animator:me", "play")
		expect(#plays).toBe(1)
		expect(plays[1].args[1]).toBe("player/OneHandedSword/Parry")
	end)

	it("HitConfirmed: a parry's blade flash and sparks wait while the inverted frame hides the world", function()
		local t = setup()
		t.state.hidden = 0.05
		Replication.dispatch("HitConfirmed", hit({ attackerId = 7, targetId = 1, damage = 0, parried = true }))
		-- The director plays first (its frame is what hides the world), then Replication asks.
		local hitAt, askedAt = 0, 0
		for index, call in t.calls do
			if call.module == "impact" and call.fn == "hit" then
				hitAt = index
			elseif call.module == "impact" and call.fn == "afterHidden" then
				askedAt = index
			end
		end
		expect(hitAt).toBeLessThan(askedAt)
		expect(#t.find("trails", "flashWhite")).toBe(0)
		expect(#t.find("sparks", "parry")).toBe(0)
		-- The reaction and the shake do not wait.
		expect(#t.find("animator:me", "play")).toBe(1)
		expect(#t.find("camera", "shake")).toBe(1)
		expect(#t.scheduled).toBe(1)
		expect(t.scheduled[1].seconds).toBe(0.05)
		t.scheduled[1].fn()
		expect(t.find("trails", "flashWhite")[1].args[1]).toBe(t.models.me)
		expect(t.find("sparks", "parry")[1].args[1]).toBe(Vector3.new(3, 2, -5))
	end)

	it("HitConfirmed: an enemy plays its additive directional flinch without replacing its reaction clip", function()
		local t = setup()
		Replication.dispatch("HitConfirmed", hit({ staggerDirection = "Left" }))
		local plays = t.find("animator:boar", "play")
		expect(#plays).toBe(1)
		expect(plays[1].args[1]).toBe("enemy/Boar/FlinchLeft")
		-- A Break kneel keeps playing under the flinch: nothing is stopped.
		Replication.dispatch("StateChanged", { entityId = 7, state = "Break", duration = 3 })
		Replication.dispatch("HitConfirmed", hit({ staggerDirection = "Back" }))
		plays = t.find("animator:boar", "play")
		expect(#plays).toBe(3)
		expect(plays[2].args[1]).toBe("enemy/Boar/Break")
		expect(plays[3].args[1]).toBe("enemy/Boar/FlinchBack")
		expect(#t.find("animator:boar", "stop")).toBe(0)
		-- No flinch on the killing hit, the breaking hit, a parry, a hit with no direction, or a player.
		Replication.dispatch("HitConfirmed", hit({ staggerDirection = "Front", killed = true, hitStop = "Kill" }))
		Replication.dispatch("HitConfirmed", hit({ staggerDirection = "Front", broke = true }))
		Replication.dispatch("HitConfirmed", hit())
		expect(#t.find("animator:boar", "play")).toBe(3)
		-- None of those hits (flinching, killing, breaking or plain) threw a parry spark.
		expect(#t.find("sparks", "parry")).toBe(0)
		-- A parried enemy plays its Parry reaction (the reaction slot), never a flinch on top.
		Replication.dispatch("HitConfirmed", hit({ staggerDirection = "Front", parried = true, damage = 0 }))
		expect(#t.find("sparks", "parry")).toBe(1)
		plays = t.find("animator:boar", "play")
		expect(#plays).toBe(4)
		expect(plays[4].args[1]).toBe("enemy/Boar/Parry")
		Replication.dispatch("HitConfirmed", hit({ attackerId = 7, targetId = 2, staggerDirection = "Right" }))
		expect(#t.find("animator:ally", "play")).toBe(0)
	end)

	it("ActionStarted plays the clip on other rigs at the server clock and skips the local player's own", function()
		local t = setup()
		Replication.dispatch("ActionStarted", {
			entityId = 7,
			clipId = "enemy/Boar/Charge",
			serverTime = 123.5,
			facing = { 0, 0, -1 },
			speed = 1.2,
		})
		local plays = t.find("animator:boar", "play")
		expect(#plays).toBe(1)
		expect(plays[1].args[1]).toBe("enemy/Boar/Charge")
		expect(plays[1].args[2]).toEqual({ serverTime = 123.5, speed = 1.2 })
		Replication.dispatch("ActionStarted", {
			entityId = 1,
			clipId = "player/OneHandedSword/Horizontal",
			serverTime = 124,
			facing = { 0, 0, -1 },
		})
		expect(#t.find("animator:me", "play")).toBe(0)
	end)

	it("Telegraph forwards the wind-up to the telegraph FX with Vector3s", function()
		local t = setup()
		local shape = { kind = "Cone", length = 12, width = 60 }
		Replication.dispatch("Telegraph", {
			entityId = 7,
			attackId = "Charge",
			kind = "Unblockable",
			windUp = 0.6,
			serverTime = 1,
			origin = { 1, 0, 1 },
			facing = { 0, 0, -1 },
			shape = shape,
		})
		local shows = t.find("telegraphs", "show")
		expect(#shows).toBe(1)
		expect(shows[1].args[1]).toBe(t.models.boar)
		expect(shows[1].args[2]).toBe("Unblockable")
		expect(shows[1].args[3]).toBe(0.6)
		expect(shows[1].args[4]).toBe(Vector3.new(1, 0, 1))
		expect(shows[1].args[5]).toBe(Vector3.new(0, 0, -1))
		expect(shows[1].args[6]).toBe(shape)
	end)

	it("StateChanged plays directional flinches, staggers, guard breaks and breaks", function()
		local t = setup()
		Replication.dispatch("StateChanged", { entityId = 7, state = "Stagger", duration = 0.5, direction = "Left" })
		expect(t.find("animator:boar", "play")[1].args[1]).toBe("enemy/Boar/FlinchLeft")
		Replication.dispatch("StateChanged", { entityId = 7, state = "Stagger", duration = 1 })
		local plays = t.find("animator:boar", "play")
		expect(plays[2].args[1]).toBe("enemy/Boar/Stagger")
		-- The previous reaction clip is stopped with the locomotion blend.
		local stops = t.find("animator:boar", "stop")
		expect(#stops).toBe(1)
		expect(stops[1].args[1]).toBe("handle1")
		expect(stops[1].args[2]).toBe(combat.locomotionBlendOut)
		Replication.dispatch("StateChanged", { entityId = 7, state = "Break", duration = 3 })
		expect(t.find("animator:boar", "play")[3].args[1]).toBe("enemy/Boar/Break")
		-- Stagger and Break interrupt the strike, so the wind-up telegraph comes down each time.
		local hides = t.find("telegraphs", "hide")
		expect(#hides).toBe(3)
		expect(hides[3].args[1]).toBe(t.models.boar)
		Replication.dispatch("StateChanged", { entityId = 7, state = "Idle" })
		expect(#t.find("animator:boar", "stop")).toBe(3)
		expect(#t.find("telegraphs", "hide")).toBe(3)

		Replication.dispatch("StateChanged", { entityId = 2, state = "GuardBroken", duration = 1.2 })
		expect(t.find("animator:ally", "play")[1].args[1]).toBe("player/OneHandedSword/GuardBreak")
		local flashes = t.find("outline", "flash")
		expect(#flashes).toBe(1)
		expect(flashes[1].args[2]).toBe("HPRed")
		expect(#t.find("telegraphs", "hide")).toBe(4)
		-- The guard break's crack is the director's GuardBreak cue, at the fighter, for everyone.
		local breaks = t.find("impact", "guardBreak")
		expect(#breaks).toBe(1)
		expect(breaks[1].args[1]).toBe(t.models.ally)
		expect(breaks[1].args[2]).toBe(false)
		expect(#t.find("sfx", "play")).toBe(0)
		Replication.dispatch("StateChanged", { entityId = 1, state = "GuardBroken", duration = 1.2 })
		expect(t.find("impact", "guardBreak")[2].args[1]).toBe(t.models.me)
		expect(t.find("impact", "guardBreak")[2].args[2]).toBe(true)
		-- Guard on another player plays their guard pose and the raise; the local player's guard
		-- (pose and raise) is predicted locally.
		Replication.dispatch("StateChanged", { entityId = 2, state = "Guard" })
		expect(t.find("animator:ally", "play")[2].args[1]).toBe("player/OneHandedSword/Guard")
		local raises = t.find("impact", "guardRaise")
		expect(#raises).toBe(1)
		expect(raises[1].args[1]).toBe(t.models.ally)
		expect(raises[1].args[2]).toBe(false)
		local mine = #t.find("animator:me", "play")
		Replication.dispatch("StateChanged", { entityId = 1, state = "Guard" })
		expect(#t.find("animator:me", "play")).toBe(mine)
		expect(#t.find("impact", "guardRaise")).toBe(1)
		expect(#t.find("telegraphs", "hide")).toBe(5)
		-- A death takes a half-shown telegraph down at once, not when the shatter starts.
		Replication.dispatch("StateChanged", { entityId = 7, state = "Dead" })
		expect(#t.find("telegraphs", "hide")).toBe(6)
		expect(t.find("telegraphs", "hide")[6].args[1]).toBe(t.models.boar)
	end)

	it("EntityDied freezes the rig, ducks Music, SFX and UI after the kill's hit-stop, then shatters", function()
		local t = setup()
		local lead = moments.deathDuckDelay()
		Replication.dispatch(
			"EntityDied",
			{ entityId = 7, shatter = "Beast", position = { 0, 0, 0 }, name = "Frenzy Boar" }
		)
		expect(t.find("animator:boar", "play")[1].args[1]).toBe("enemy/Boar/DeathFreeze")
		expect(t.find("animator:boar", "setTimeScale")[1].args[1]).toBe(0)
		-- The boar's death scream starts with the kill (the silence chops its tail).
		local vocals = t.find("sfx", "play")
		expect(#vocals).toBe(1)
		expect(vocals[1].args[1]).toBe("enemy.ChargerDeath")
		expect(vocals[1].args[2]).toBe(Vector3.zero)
		-- The silence waits the kill's hit-stop, so the kill's crack and frames are heard first.
		expect(#t.find("sfx", "duck")).toBe(0)
		expect(#t.find("shatter", "play")).toBe(0)
		-- An enemy's death reads no line: the duck and the shatter are scheduled.
		expect(#t.scheduled).toBe(2)
		expect(t.scheduled[1].seconds).toBe(lead)
		expect(t.scheduled[2].seconds).toBeCloseTo(lead + combat.deathFreeze, 1e-12)
		t.scheduled[1].fn()
		-- Freeze and silence: SfxPool.duck lowers Music, SFX and UI together for the freeze.
		local ducks = t.find("sfx", "duck")
		expect(#ducks).toBe(1)
		expect(ducks[1].args[1]).toBe(combat.deathDuckDb)
		expect(ducks[1].args[2]).toBe(combat.deathFreeze)
		-- The silence spares the local player's own new sounds (issue 9).
		expect(ducks[1].args[3]).toBe(true)
		expect(#t.find("shatter", "play")).toBe(0)
		t.scheduled[2].fn()
		local shatters = t.find("shatter", "play")
		expect(#shatters).toBe(1)
		expect(shatters[1].args[1]).toBe(t.models.boar)
		expect(shatters[1].args[2]).toBe("Beast")
		expect(shatters[1].args[3]).toBe(sfx.shatterCues.normal)
		-- The director blooms the mix as the shatter starts.
		local deaths = t.find("impact", "death")
		expect(#deaths).toBe(1)
		expect(deaths[1].args[1]).toBe(t.models.boar)
		expect(deaths[1].args[2]).toBe(Vector3.zero)
		expect(deaths[1].args[3]).toBe(false)
		expect(deaths[1].args[4]).toBe(false)
		expect(#t.find("systemLine", "show")).toBe(0)

		-- Another player: the heavy shatter, and the name line after the shatter, not with it.
		table.clear(t.scheduled)
		Replication.dispatch("EntityDied", { entityId = 2, shatter = "Humanoid", position = { 0, 0, 0 }, name = "Ren" })
		expect(#t.scheduled).toBe(3)
		expect(t.scheduled[1].seconds).toBe(lead)
		expect(t.scheduled[2].seconds).toBeCloseTo(lead + combat.deathFreeze, 1e-12)
		expect(t.scheduled[3].seconds).toBeCloseTo(lead + combat.deathFreeze + fx.shatter.duration, 1e-12)
		-- A player screams nothing here (their vocal is the clip's).
		expect(#t.find("sfx", "play")).toBe(1)
		t.scheduled[1].fn()
		t.scheduled[2].fn()
		expect(#t.find("shatter", "play")).toBe(2)
		expect(t.find("shatter", "play")[2].args[3]).toBe(sfx.shatterCues.heavy)
		expect(t.find("impact", "death")[2].args[4]).toBe(true)
		expect(#t.find("systemLine", "show")).toBe(0)
		t.scheduled[3].fn()
		local lines = t.find("systemLine", "show")
		expect(#lines).toBe(1)
		expect(lines[1].args[1]).toBe("Ren has been struck from the Roll")
		expect(lines[1].args[1]).toBe(ui.systemLine.deathOther:format("Ren"))
		expect(lines[1].args[2]).toBe("SystemWhite")
		expect(lines[1].args[3]).toBe("ui.SystemLine")

		-- The dying player reads their own line (section 6), after their own heavy shatter.
		table.clear(t.scheduled)
		Replication.dispatch(
			"EntityDied",
			{ entityId = 1, shatter = "Humanoid", position = { 0, 0, 0 }, name = "Mira" }
		)
		expect(#t.scheduled).toBe(3)
		expect(t.scheduled[3].seconds).toBeCloseTo(lead + combat.deathFreeze + fx.shatter.duration, 1e-12)
		runScheduled(t)
		expect(t.find("shatter", "play")[3].args[3]).toBe(sfx.shatterCues.heavy)
		lines = t.find("systemLine", "show")
		expect(#lines).toBe(2)
		expect(lines[2].args[1]).toBe("Your name has been struck from the Roll.")
		expect(lines[2].args[1]).toBe(ui.systemLine.deathSelf)
	end)

	it("EntityDied picks the shatter's weight: a boss's, a player's or an Elite's heavy one, else a mob's", function()
		local t = setup()
		local function cueFor(payload)
			table.clear(t.scheduled)
			t.state.clock += 1 -- separate deaths, never one sweep's
			Replication.dispatch("EntityDied", payload)
			runScheduled(t)
			local shatters = t.find("shatter", "play")
			return shatters[#shatters].args[3]
		end
		expect(cueFor({ entityId = 8, shatter = "Humanoid", position = { 0, 0, 0 }, name = "Kobold Axeman" })).toBe(
			sfx.shatterCues.normal
		)
		expect(cueFor({ entityId = 9, shatter = "Humanoid", position = { 0, 0, 0 }, name = "Elite" })).toBe(
			sfx.shatterCues.heavy
		)
		expect(cueFor({ entityId = 7, shatter = "Boss", position = { 0, 0, 0 }, name = "King" })).toBe(
			sfx.shatterCues.boss
		)
		-- A boss's shatter runs longer: its line (none for an enemy) and its bloom follow it.
		expect(t.find("impact", "death")[3].args[3]).toBe(true)
		-- Each Kobold screams its archetype's death on the kill.
		local vocals = {}
		for _, call in t.find("sfx", "play") do
			table.insert(vocals, call.args[1])
		end
		expect(vocals).toEqual({ "enemy.BruteDeath", "enemy.BruteDeath", "enemy.ChargerDeath" })
	end)

	it("marks the local fighter's sounds and the hits they are in as their own; nobody else's (issue 9)", function()
		local t = setup()
		-- A pool with asOwn: each play remembers whether it started inside it.
		local depth = 0
		local plays: { { name: string, own: boolean } } = {}
		local function note(name)
			table.insert(plays, { name = name, own = depth > 0 })
		end
		t.deps.sfx = {
			asOwn = function(fn)
				depth += 1
				fn()
				depth -= 1
			end,
			play = note,
			cue = note,
			footstep = function()
				note("footstep")
			end,
			playLate = note,
			duck = function() end,
		}
		Replication.bind(t.deps)
		local me, boar = t.records[1], t.records[7]
		local swing = { time = 0.1, kind = "Sfx", data = { name = "whoosh.Medium" } }
		Replication.routeClipEvent(me, "player/OneHandedSword/Basic1", swing)
		Replication.routeClipEvent(me, "player/OneHandedSword/Run", { time = 0.2, kind = "Footstep" })
		Replication.routeClipEvent(boar, "enemy/Boar/Charge", swing)
		Replication.routeClipEvent(boar, "enemy/Boar/Walk", { time = 0.2, kind = "Footstep" })
		-- The hit-stop tick of a hit the local player lands, and of one they take.
		Replication.dispatch("HitConfirmed", hit())
		Replication.dispatch("HitConfirmed", hit({ attackerId = 7, targetId = 1 }))
		local seen = {}
		for _, play in plays do
			table.insert(seen, play.name .. (if play.own then ":own" else ""))
		end
		expect(seen).toEqual({
			"whoosh.Medium:own",
			"footstep:own",
			"whoosh.Medium",
			"footstep",
			"hitStopTick.Normal:own",
			"hitStopTick.Normal:own",
		})
	end)

	it("EntityDied with a director that is not loaded still shatters with the plain cue", function()
		local t = setup()
		t.deps.impact = setmetatable({}, {
			__index = function()
				return function()
					return {} -- a Siblings stub answers with a table, never a cue name
				end
			end,
		})
		Replication.bind(t.deps)
		Replication.dispatch("EntityDied", { entityId = 7, shatter = "Beast", position = { 0, 0, 0 }, name = "Boar" })
		runScheduled(t)
		expect(t.find("shatter", "play")[1].args[3]).toBe(sfx.shatterCues.normal)
		Replication.dispatch("EntityDied", { entityId = 7, shatter = "Boss", position = { 0, 0, 0 }, name = "Boar" })
		runScheduled(t)
		expect(t.find("shatter", "play")[2].args[3]).toBe(sfx.shatterCues.boss)
	end)

	it("ActionRejected becomes the rejected Signal and nothing else", function()
		local t = setup()
		local rejected = {}
		Replication.rejected:Connect(function(action, reason, clientTime)
			table.insert(rejected, { action = action, reason = reason, clientTime = clientTime })
		end)
		Replication.dispatch("ActionRejected", { action = "Art", reason = "locked", clientTime = 5 })
		expect(#rejected).toBe(1)
		expect(rejected[1].action).toBe("Art")
		expect(rejected[1].reason).toBe("locked")
		expect(#t.find("digits", "show")).toBe(0)
	end)

	it("SystemLine and SwitchWindow reach the HUD", function()
		local t = setup()
		Replication.dispatch(
			"SystemLine",
			{ text = "Warded Object", token = "WardedPurple", chime = "ui.SystemLineWarded" }
		)
		local lines = t.find("systemLine", "show")
		expect(#lines).toBe(1)
		expect(lines[1].args[1]).toBe("Warded Object")
		expect(lines[1].args[2]).toBe("WardedPurple")
		Replication.dispatch(
			"SwitchWindow",
			{ entityId = 7, openerId = 2, position = { 1, 1, 1 }, duration = 0.8, serverTime = 1 }
		)
		local rings = t.find("switchRing", "show")
		expect(#rings).toBe(1)
		expect(rings[1].args[1]).toBe(Vector3.new(1, 1, 1))
		expect(rings[1].args[2]).toBe(0.8)
		-- No showSwitchPrompt on this HUD: the prompt falls back to a cyan system line.
		expect(#t.find("systemLine", "show")).toBe(2)
		expect(t.find("systemLine", "show")[2].args[1]).toBe("SWITCH")
		-- The opener does not get a prompt for their own window.
		Replication.dispatch(
			"SwitchWindow",
			{ entityId = 7, openerId = 1, position = { 1, 1, 1 }, duration = 0.8, serverTime = 1 }
		)
		expect(#t.find("systemLine", "show")).toBe(2)
		expect(#t.find("switchRing", "show")).toBe(2)
	end)

	it("SwitchWindow anchors the HUD prompt over the enemy when the HUD can show one", function()
		local t = setup()
		local prompts = {}
		t.deps.hud = {
			showSwitchPrompt = function(duration, target, callerName)
				table.insert(prompts, { duration = duration, target = target, callerName = callerName })
			end,
		}
		Replication.bind(t.deps)
		Replication.dispatch(
			"SwitchWindow",
			{ entityId = 7, openerId = 2, position = { 1, 1, 1 }, duration = 0.8, serverTime = 1 }
		)
		expect(#prompts).toBe(1)
		expect(prompts[1].duration).toBe(0.8)
		expect(prompts[1].target).toBe(t.models.boar)
		expect(prompts[1].callerName).toBeNil()
		expect(#t.find("systemLine", "show")).toBe(0)
		expect(t.find("sfx", "play")[1].args[1]).toBe("ui.SwitchPrompt")
	end)

	it("routes clip events to trails, smear and the activation light", function()
		local t = setup()
		local me = t.records[1]
		Replication.routeClipEvent(me, "player/OneHandedSword/Horizontal", { time = 0.15, kind = "ActivationHold" })
		local lights = t.find("trails", "activationLight")
		expect(#lights).toBe(1)
		expect(lights[1].args[1]).toBe(t.models.me)
		expect(lights[1].args[2]).toBe(true)
		expect(lights[1].args[3]).toBe("TrailCyanWhite")
		expect(#t.find("camera", "fovKick")).toBe(1)
		expect(t.find("sfx", "play")[1].args[1]).toBe("artChime.TrailCyanWhite")

		Replication.routeClipEvent(me, "player/OneHandedSword/Horizontal", { time = 0.3, kind = "HitWindowOpen" })
		local actives = t.find("trails", "setActive")
		expect(#actives).toBe(1)
		expect(actives[1].args[2]).toBe(true)
		expect(actives[1].args[3]).toBe("Art")
		expect(#t.find("trails", "activationLight")).toBe(2)
		expect(t.find("trails", "activationLight")[2].args[2]).toBe(false)

		Replication.routeClipEvent(
			me,
			"player/OneHandedSword/Horizontal",
			{ time = 0.3, kind = "SmearOn", data = { axis = "X" } }
		)
		Replication.routeClipEvent(
			me,
			"player/OneHandedSword/Horizontal",
			{ time = 0.34, kind = "SmearOff", data = { axis = "X" } }
		)
		local smears = t.find("smear", "apply")
		expect(#smears).toBe(2)
		expect(smears[1].args[2]).toBe(true)
		expect(smears[1].args[3]).toBe("X")
		expect(smears[2].args[2]).toBe(false)
		-- The smear frames turn the full-width Smear trail kind on and off beside the mesh scale.
		actives = t.find("trails", "setActive")
		expect(#actives).toBe(3)
		expect(actives[2].args[1]).toBe(t.models.me)
		expect(actives[2].args[2]).toBe(true)
		expect(actives[2].args[3]).toBe("Smear")
		expect(actives[3].args[2]).toBe(false)
		expect(actives[3].args[3]).toBe("Smear")

		Replication.routeClipEvent(me, "player/OneHandedSword/Horizontal", { time = 0.4, kind = "HitWindowClose" })
		expect(t.find("trails", "setActive")[4].args[2]).toBe(false)
		expect(t.find("trails", "setActive")[4].args[3]).toBe("Art")

		-- Basic swings get the thinner trail; other rigs' activation never kicks the local FOV.
		Replication.routeClipEvent(t.records[2], "player/OneHandedSword/Basic1", { time = 0.1, kind = "TrailOn" })
		expect(t.find("trails", "setActive")[5].args[3]).toBe("Basic")
		Replication.routeClipEvent(
			t.records[2],
			"player/OneHandedSword/Horizontal",
			{ time = 0.15, kind = "ActivationHold" }
		)
		expect(#t.find("camera", "fovKick")).toBe(1)
	end)

	it("an event a jump crossed (a render stall's gap, D-132) closes what it closes and starts nothing", function()
		local t = setup()
		local me = t.records[1]
		local seen = {}
		Replication.clipEvent:Connect(function(record, _clipId, event, jumped)
			table.insert(seen, { record = record, kind = event.kind, jumped = jumped })
		end)
		local art = "player/OneHandedSword/Horizontal"
		local crossed = {
			{ time = 0.15, kind = "ActivationHold", data = { hold = 0.1 } },
			{ time = 0.29, kind = "Sfx", data = { name = "whoosh.Medium" } },
			{ time = 0.3, kind = "Voice", data = { name = "enemy.ChargerWindUp" } },
			{ time = 0.35, kind = "TrailOn", data = { kind = "Art" } },
			{ time = 0.35, kind = "SmearOn", data = { axis = "X" } },
			{ time = 0.35, kind = "HitWindowOpen", data = { hit = 1 } },
			{ time = 0.36, kind = "Footstep" },
			{ time = 0.3833, kind = "SmearOff", data = { axis = "X" } },
			{ time = 0.48, kind = "HitWindowClose", data = { hit = 1 } },
			{ time = 0.52, kind = "TrailOff" },
			{ time = 0.6, kind = "PostMotionStart" },
		}
		for _, event in crossed do
			Replication.routeClipEvent(me, art, event, true)
		end
		-- No sound, chime, riser, FOV kick, footstep, smear or trail starts.
		expect(#t.find("sfx", "play")).toBe(0)
		expect(#t.find("sfx", "footstep")).toBe(0)
		expect(#t.find("camera", "fovKick")).toBe(0)
		expect(#t.find("impact", "activation")).toBe(0)
		for _, call in t.find("trails", "setActive") do
			expect(call.args[2]).toBe(false)
		end
		for _, call in t.find("trails", "activationLight") do
			expect(call.args[2]).toBe(false)
		end
		for _, call in t.find("smear", "apply") do
			expect(call.args[2]).toBe(false)
		end
		-- What closes still closes: the smear, the window's and the trail's Art kind, the light.
		expect(#t.find("smear", "apply")).toBe(1)
		local offs = {}
		for _, call in t.find("trails", "setActive") do
			table.insert(offs, call.args[3])
		end
		expect(offs).toEqual({ "Smear", "Art", "Art", "Art" })
		expect(#t.find("trails", "activationLight")).toBe(2)
		-- Every event still reaches clipEvent listeners (the Art hold's freeze is state), marked.
		expect(#seen).toBe(#crossed)
		for _, entry in seen do
			expect(entry.record).toBe(me)
			expect(entry.jumped).toBe(true)
		end
		-- An unmarked event is a plain one: it starts as ever, and listeners see jumped = false.
		Replication.routeClipEvent(me, art, { time = 0.15, kind = "ActivationHold" })
		expect(#t.find("camera", "fovKick")).toBe(1)
		expect(seen[#seen].jumped).toBe(false)
	end)

	it("a TrailOn's data.kind picks the trail kind for the rest of that clip's trail events", function()
		local t = setup()
		local boar = t.records[7]
		local charge = "enemy/Boar/Charge"
		Replication.routeClipEvent(boar, charge, { time = 0.62, kind = "TrailOn", data = { kind = "Basic" } })
		Replication.routeClipEvent(boar, charge, { time = 1.05, kind = "HitWindowOpen", data = { hit = 1 } })
		Replication.routeClipEvent(boar, charge, { time = 1.2, kind = "HitWindowClose", data = { hit = 1 } })
		Replication.routeClipEvent(boar, charge, { time = 1.22, kind = "TrailOff" })
		Replication.routeClipEvent(boar, charge, { time = 1.25, kind = "PostMotionStart" })
		local actives = t.find("trails", "setActive")
		expect(#actives).toBe(5)
		local expected = { true, true, false, false, false }
		for index, on in expected do
			expect(actives[index].args[1]).toBe(t.models.boar)
			expect(actives[index].args[2]).toBe(on)
			expect(actives[index].args[3]).toBe("Basic")
		end
		-- PostMotionStart ends the clip's memory: a later event with no kind falls back to the clip id.
		Replication.routeClipEvent(boar, charge, { time = 1.05, kind = "HitWindowOpen" })
		expect(t.find("trails", "setActive")[6].args[3]).toBe("Art")

		-- The memory belongs to the clip that named it: a Basic swing's kind never leaks into an Art.
		local ally = t.records[2]
		Replication.routeClipEvent(
			ally,
			"player/OneHandedSword/Basic1",
			{ time = 0.09, kind = "TrailOn", data = { kind = "Basic" } }
		)
		Replication.routeClipEvent(ally, "player/OneHandedSword/Horizontal", { time = 0.36, kind = "HitWindowOpen" })
		actives = t.find("trails", "setActive")
		expect(actives[7].args[3]).toBe("Basic")
		expect(actives[8].args[3]).toBe("Art")
		-- A kind outside Art / Basic is ignored rather than handed to Trails.
		Replication.routeClipEvent(
			ally,
			"player/OneHandedSword/Vertical",
			{ time = 0.3, kind = "TrailOn", data = { kind = "Glow" } }
		)
		expect(t.find("trails", "setActive")[9].args[3]).toBe("Art")
	end)

	it("clip Sfx and Voice events play their sfx.luau sound at the rig", function()
		local t = setup()
		local boar = t.records[7]
		Replication.routeClipEvent(
			boar,
			"enemy/Boar/Charge",
			{ time = 0.1, kind = "Voice", data = { name = "enemy.ChargerWindUp" } }
		)
		Replication.routeClipEvent(
			boar,
			"enemy/Boar/Charge",
			{ time = 0.6, kind = "Sfx", data = { name = "whoosh.Large" } }
		)
		local plays = t.find("sfx", "play")
		expect(#plays).toBe(2)
		expect(plays[1].args[1]).toBe("enemy.ChargerWindUp")
		expect(plays[1].args[2]).toBe(Vector3.zero)
		expect(plays[2].args[1]).toBe("whoosh.Large")
		-- An event without a name plays nothing.
		Replication.routeClipEvent(boar, "enemy/Boar/Charge", { time = 0.7, kind = "Sfx" })
		expect(#t.find("sfx", "play")).toBe(2)
		-- The names used here are real registry entries.
		expect(function()
			sfx.get("enemy", "ChargerWindUp")
			sfx.get("whoosh", "Large")
		end).never.toThrow()
	end)

	it("watches rigs through their animator events and registers outlines", function()
		local t = setup()
		local boar = t.records[7]
		Replication.watch(boar)
		expect(t.find("outline", "register")[1].args[1]).toBe(t.models.boar)
		expect(t.find("trails", "attach")[1].args[1]).toBe(t.models.boar)
		local animator = t.deps.choreo.get(t.models.boar)
		local seen = {}
		Replication.clipEvent:Connect(function(record, clipId, event)
			table.insert(seen, { record = record, clipId = clipId, event = event })
		end)
		animator.events:Fire("enemy/Boar/Charge", { time = 0.5, kind = "HitWindowOpen" })
		expect(#seen).toBe(1)
		expect(seen[1].record).toBe(boar)
		expect(#t.find("trails", "setActive")).toBe(1)
		Replication.unwatch(boar)
		expect(t.find("outline", "unregister")[1].args[1]).toBe(t.models.boar)
	end)

	it("watch attaches a locomotion driver to a remote rig and unwatch destroys it", function()
		local t = setup()
		local boar = t.records[7]
		Replication.watch(boar)
		local attaches = t.find("locomotion", "attach")
		expect(#attaches).toBe(1)
		expect(attaches[1].args[1]).toBe(t.deps.choreo.get(t.models.boar))
		expect(attaches[1].args[2]).toBe(t.models.boar)
		-- Watching twice never doubles the driver.
		Replication.watch(boar)
		expect(#t.find("locomotion", "attach")).toBe(1)
		expect(#t.find("locomotion", "destroy")).toBe(0)
		Replication.unwatch(boar)
		local destroys = t.find("locomotion", "destroy")
		expect(#destroys).toBe(1)
		expect(destroys[1].args[1]).toBe(attaches[1].driver)
		-- Another player's rig runs a driver too (the full blend space, picked by Locomotion).
		Replication.watch(t.records[2])
		expect(#t.find("locomotion", "attach")).toBe(2)
		expect(t.find("locomotion", "attach")[2].args[2]).toBe(t.models.ally)
	end)

	it("an enemy rig's driver starts its idle and walk at its own id's phase", function()
		local t = setup()
		Replication.watch(t.records[7])
		Replication.watch(t.records[8])
		local attaches = t.find("locomotion", "attach")
		expect(attaches[1].args[3].phase).toBe(0.07)
		expect(attaches[2].args[3].phase).toBe(0.08)
	end)

	it("the local player's rig gets no driver: the character controller owns its locomotion", function()
		local t = setup()
		Replication.watch(t.records[1])
		expect(#t.find("locomotion", "attach")).toBe(0)
		expect(t.find("outline", "register")[1].args[1]).toBe(t.models.me)
		Replication.unwatch(t.records[1])
		expect(#t.find("locomotion", "destroy")).toBe(0)
	end)

	it("a local record watched before its id is known is told apart by the character model", function()
		local t = setup({ unknownLocal = true, localCharacter = "me" })
		Replication.watch(t.records[1])
		expect(#t.find("locomotion", "attach")).toBe(0)
		-- A remote rig still gets its driver while the local id is unknown.
		Replication.watch(t.records[2])
		expect(#t.find("locomotion", "attach")).toBe(1)
		expect(t.find("locomotion", "attach")[1].args[2]).toBe(t.models.ally)
	end)

	it("a driver that reached the local rig before the id resolved is dropped on localChanged", function()
		local t = setup({ unknownLocal = true })
		Replication.watch(t.records[1])
		Replication.watch(t.records[7])
		local attaches = t.find("locomotion", "attach")
		expect(#attaches).toBe(2)
		expect(attaches[1].args[2]).toBe(t.models.me)
		t.setLocalId(1)
		t.localChanged:Fire(1)
		local destroys = t.find("locomotion", "destroy")
		expect(#destroys).toBe(1)
		expect(destroys[1].args[1]).toBe(attaches[1].driver)
		-- The boar keeps its driver; the local rig has nothing left to destroy on unwatch.
		Replication.unwatch(t.records[1])
		expect(#t.find("locomotion", "destroy")).toBe(1)
		Replication.unwatch(t.records[7])
		expect(#t.find("locomotion", "destroy")).toBe(2)
		expect(t.find("locomotion", "destroy")[2].args[1]).toBe(attaches[2].driver)
		-- Watched again with the id known, the local rig gets no driver.
		Replication.watch(t.records[1])
		expect(#t.find("locomotion", "attach")).toBe(2)
	end)

	it("unwatch releases the rig's trail, telegraph highlight, smear and reaction clip", function()
		local t = setup()
		local boar = t.records[7]
		Replication.watch(boar)
		Replication.dispatch("StateChanged", { entityId = 7, state = "Stagger", duration = 1 })
		expect(#t.find("animator:boar", "play")).toBe(1)
		Replication.unwatch(boar)
		expect(t.find("trails", "detach")[1].args[1]).toBe(t.models.boar)
		expect(t.find("telegraphs", "forget")[1].args[1]).toBe(t.models.boar)
		expect(t.find("smear", "reset")[1].args[1]).toBe(t.models.boar)
		expect(t.find("outline", "unregister")[1].args[1]).toBe(t.models.boar)
		-- The reaction clip handle is forgotten: the next reaction stops nothing stale.
		Replication.dispatch("StateChanged", { entityId = 7, state = "Stagger", duration = 1 })
		expect(#t.find("animator:boar", "play")).toBe(2)
		expect(#t.find("animator:boar", "stop")).toBe(0)
	end)

	it(
		"EntityDied plays the shatter cue once: through the shatter with a rig, directly when the rig is gone",
		function()
			local t = setup()
			Replication.dispatch(
				"EntityDied",
				{ entityId = 7, shatter = "Beast", position = { 1, 2, 3 }, name = "Frenzy Boar" }
			)
			runScheduled(t)
			expect(#t.find("shatter", "play")).toBe(1)
			expect(#shatterCues(t)).toBe(0)

			-- No record for the id: nothing to shatter, the shatter cue still sounds where the server
			-- said, and the director still blooms the mix there.
			Replication.dispatch(
				"EntityDied",
				{ entityId = 99, shatter = "Beast", position = { 1, 2, 3 }, name = "Gone" }
			)
			-- No rig, no scream.
			expect(#t.find("sfx", "play")).toBe(1)
			runScheduled(t)
			expect(#t.find("shatter", "play")).toBe(1)
			local played = shatterCues(t)
			expect(#played).toBe(1)
			expect(played[1].args[1]).toBe(sfx.shatterCues.normal)
			expect(played[1].args[2]).toBe(Vector3.new(1, 2, 3))
			local deaths = t.find("impact", "death")
			expect(deaths[2].args[1]).toBeNil()
			expect(deaths[2].args[2]).toBe(Vector3.new(1, 2, 3))
			expect(#t.find("systemLine", "show")).toBe(0)
			-- A boss gone before its shatter still sounds the boss's cue.
			Replication.dispatch(
				"EntityDied",
				{ entityId = 98, shatter = "Boss", position = { 1, 2, 3 }, name = "Gone" }
			)
			runScheduled(t)
			expect(shatterCues(t)[2].args[1]).toBe(sfx.shatterCues.boss)
			-- The old crack is not played any more.
			for _, call in t.find("sfx", "play") do
				expect(call.args[1]).never.toBe("shatter.Crack")
			end
		end
	)

	it("EntityDied: one sweep's deaths share one silence, and each shatter cracks with it released", function()
		local t = setup()
		local runUntil = timedScheduler(t)
		-- Two deaths of one sweep, a frame apart (Sharp Nail hits land closer than deathFreeze).
		local start = t.state.clock
		Replication.dispatch(
			"EntityDied",
			{ entityId = 7, shatter = "Beast", position = { 1, 2, 3 }, name = "Frenzy Boar" }
		)
		t.state.clock += moments.sweep.mergeSeconds * 0.5
		Replication.dispatch("EntityDied", { entityId = 99, shatter = "Beast", position = { 4, 5, 6 }, name = "Gone" })
		-- One silence, the newer death's, after the kill's hit-stop.
		local lead = moments.deathDuckDelay()
		runUntil(start + lead + moments.sweep.mergeSeconds)
		local ducks = t.find("sfx", "duck")
		expect(#ducks).toBe(1)
		expect(ducks[1].args[1]).toBe(combat.deathDuckDb)
		expect(ducks[1].args[2]).toBe(combat.deathFreeze)

		-- The first shatter: its silence ends within the sweep's window, so a release (0 dB, at once)
		-- is recorded before Shatter.play.
		runUntil(start + lead + combat.deathFreeze)
		local releaseAt, shatterAt = nil, nil
		for index, call in t.calls do
			if call.module == "sfx" and call.fn == "duck" and call.args[1] == 0 and call.args[2] == 0 then
				releaseAt = releaseAt or index
			elseif call.module == "shatter" and call.fn == "play" then
				shatterAt = shatterAt or index
			end
		end
		expect(releaseAt).never.toBeNil()
		expect(shatterAt).never.toBeNil()
		expect(releaseAt :: number).toBeLessThan(shatterAt :: number)
		expect(#t.find("sfx", "duck")).toBe(2)

		-- The second death has no rig: its own release comes before the cue it plays directly.
		runUntil(start + lead + combat.deathFreeze + moments.sweep.mergeSeconds)
		ducks = t.find("sfx", "duck")
		expect(#ducks).toBe(3)
		expect(ducks[3].args[1]).toBe(0)
		expect(ducks[3].args[2]).toBe(0)
		local lastRelease, cueAt = 0, 0
		for index, call in t.calls do
			if call.module == "sfx" and call.fn == "duck" then
				lastRelease = index
			elseif call.module == "sfx" and call.fn == "cue" then
				cueAt = index
			end
		end
		expect(#shatterCues(t)).toBe(1)
		expect(lastRelease).toBeLessThan(cueAt)
	end)

	it("HitConfirmed: a basic swing is no Art's; its third swing keeps the Final hit-stop and tick", function()
		local t = setup()
		Replication.dispatch("HitConfirmed", hit({ artId = NONE, hitStop = "Final", hitIndex = 3 }))
		local info = lastInfo(t)
		expect(info.art).toBe(false)
		expect(info.tier).toBe("Final")
		expect(t.find("animator:boar", "hitStop")[1].args[1]).toBe(combat.hitStopFrames.Final)
		expect(t.find("sfx", "play")[1].args[1]).toBe("hitStopTick.Final")
		-- An enemy's strike is neither an Art nor a player's basic swing.
		Replication.dispatch("HitConfirmed", hit({ attackerId = 7, targetId = 1, artId = NONE }))
		expect(lastInfo(t).art).toBeNil()
		-- An attacker this client does not track: unknown, never a basic swing.
		Replication.dispatch("HitConfirmed", hit({ attackerId = 50, targetId = 7, artId = NONE }))
		expect(lastInfo(t).art).toBeNil()
		expect(lastInfo(t).attacker).toBeNil()
		expect(lastInfo(t).trailToken).toBe("SystemWhite")
		-- An Art's hit carries its artId.
		Replication.dispatch("HitConfirmed", hit({ attackerId = 2 }))
		expect(lastInfo(t).art).toBe(true)
		expect(lastInfo(t).involved).toBe(false)
	end)

	it("HitConfirmed: with the real director a basic swing plays the basic hit's cue", function()
		local t = setup()
		local directorCalls = {}
		local recorders = {}
		for _, name in { "impactFrames", "glint", "slashArc", "speedLines", "trails", "sfx", "camera", "outline" } do
			recorders[name] = recorder(name, directorCalls)
		end
		recorders.clipLibrary = { get = function() end }
		recorders.now = function()
			return t.state.clock
		end
		recorders.viewerPosition = function()
			return Vector3.zero
		end
		recorders.positionOf = function()
			return Vector3.zero
		end
		Impact.bind(recorders)
		t.deps.impact = Impact
		Replication.bind(t.deps)
		Replication.dispatch("HitConfirmed", hit({ artId = NONE, hitStop = "Final", hitIndex = 3 }))
		local cues = {}
		for _, call in directorCalls do
			if call.module == "sfx" and call.fn == "cue" then
				table.insert(cues, call.args[1])
			end
		end
		expect(cues).toEqual({ moments.rows.BasicHit.cue })
		-- Basics stay weak: no impact frames, no punch.
		for _, call in directorCalls do
			expect(call.module .. "." .. call.fn).never.toBe("impactFrames.play")
			expect(call.module .. "." .. call.fn).never.toBe("camera.punch")
		end
		-- Replication still flashes the target white (BasicHit has no Highlight of its own).
		expect(#t.find("outline", "flash")).toBe(1)
		Impact.bind({})
	end)

	it("HitConfirmed: the hit that breaks a player's guard ticks Final for the people in it", function()
		local t = setup()
		-- The boar breaks the local player's guard.
		Replication.dispatch("HitConfirmed", hit({ attackerId = 7, targetId = 1, guarded = true, broke = true }))
		expect(t.find("sfx", "play")[1].args[1]).toBe("hitStopTick.Final")
		-- The local player breaks another player's guard (each blow its own swing, never one sweep).
		t.state.clock += 1
		Replication.dispatch("HitConfirmed", hit({ attackerId = 1, targetId = 2, guarded = true, broke = true }))
		expect(t.find("sfx", "play")[2].args[1]).toBe("hitStopTick.Final")
		-- An enemy's Break is not a guard break; a kill keeps its own tick.
		t.state.clock += 1
		Replication.dispatch("HitConfirmed", hit({ broke = true }))
		expect(t.find("sfx", "play")[3].args[1]).toBe("hitStopTick.Normal")
		t.state.clock += 1
		Replication.dispatch(
			"HitConfirmed",
			hit({ attackerId = 7, targetId = 1, broke = true, killed = true, hitStop = "Kill" })
		)
		expect(t.find("sfx", "play")[4].args[1]).toBe("hitStopTick.Kill")
		-- A bystander hears no tick at all.
		Replication.dispatch("HitConfirmed", hit({ attackerId = 7, targetId = 2, broke = true }))
		expect(#t.find("sfx", "play")).toBe(4)
	end)

	it("HitConfirmed: the blow that breaks a player's guard lands on the guard for the director", function()
		local t = setup()
		-- The server's guard break: the blow goes through the guard (guarded false, broke true).
		-- StateChanged GuardBroken already played the break's crack; the blow is the guarded thud
		-- under it, never a second clean hit (4 layers, not 7).
		Replication.dispatch("HitConfirmed", hit({ attackerId = 8, targetId = 1, broke = true, artId = NONE }))
		local info = lastInfo(t)
		expect(info.guarded).toBe(true)
		expect(moments.selectFor(info)).toBe("Guarded")
		-- The rig plays the guard break's reaction (StateChanged), not a guard hit.
		for _, call in t.find("animator:me", "play") do
			expect(string.find(call.args[1], "GuardHit", 1, true)).toBeNil()
		end
		-- An enemy's Break (its gauge, not a guard) and a death through the guard stay what they are.
		Replication.dispatch("HitConfirmed", hit({ broke = true }))
		expect(lastInfo(t).guarded).toBe(false)
		Replication.dispatch(
			"HitConfirmed",
			hit({ attackerId = 8, targetId = 1, broke = true, killed = true, hitStop = "Kill", artId = NONE })
		)
		expect(moments.selectFor(lastInfo(t))).toBe("Kill")
	end)

	it("HitConfirmed: the blow that breaks a player's guard leaves the guard break's red fill showing", function()
		local t = setup()
		local function fills(): { string }
			local tokens = {}
			for _, call in t.find("outline", "flash") do
				if call.args[1] == t.models.me then
					table.insert(tokens, call.args[2])
				end
			end
			return tokens
		end
		-- The server's order: StateChanged GuardBroken, then the blow's HitConfirmed, one frame.
		Replication.dispatch("StateChanged", { entityId = 1, state = "GuardBroken", duration = 1.2 })
		Replication.dispatch("HitConfirmed", hit({ attackerId = 8, targetId = 1, broke = true, artId = NONE }))
		expect(fills()).toEqual({ "HPRed" })
		-- A guarded blow that breaks nothing, and a clean hit, still flash white.
		t.state.clock += 1
		Replication.dispatch("HitConfirmed", hit({ attackerId = 8, targetId = 1, guarded = true, artId = NONE }))
		t.state.clock += 1
		Replication.dispatch("HitConfirmed", hit({ attackerId = 8, targetId = 1, artId = NONE }))
		expect(fills()).toEqual({ "HPRed", "SystemWhite", "SystemWhite" })
	end)

	it(
		"HitConfirmed: one sweep ticks once; a stronger tier's tick takes over, a weaker one after it is not heard",
		function()
			local t = setup()
			local function ticks(): { string }
				local names = {}
				for _, call in t.find("sfx", "play") do
					table.insert(names, call.args[1])
				end
				return names
			end
			-- A kill confirmed first: the final hits of the same sweep add no Final tick under it.
			Replication.dispatch("HitConfirmed", hit({ hitStop = "Kill", killed = true }))
			Replication.dispatch("HitConfirmed", hit({ hitStop = "Final" }))
			Replication.dispatch("HitConfirmed", hit({ hitStop = "Final" }))
			expect(ticks()).toEqual({ "hitStopTick.Kill" })
			-- The next sweep: final hits first, then a kill, which is heard.
			t.state.clock += moments.sweep.mergeSeconds * 1.01
			Replication.dispatch("HitConfirmed", hit({ hitStop = "Final" }))
			Replication.dispatch("HitConfirmed", hit({ hitStop = "Final" }))
			Replication.dispatch("HitConfirmed", hit({ hitStop = "Kill", killed = true }))
			expect(ticks()).toEqual({ "hitStopTick.Kill", "hitStopTick.Final", "hitStopTick.Kill" })
			-- Past the window the same tier ticks again; binding again forgets the sweep.
			t.state.clock += moments.sweep.mergeSeconds * 1.01
			Replication.dispatch("HitConfirmed", hit({ hitStop = "Normal" }))
			Replication.bind(t.deps)
			Replication.dispatch("HitConfirmed", hit({ hitStop = "Normal" }))
			expect(ticks()).toEqual({
				"hitStopTick.Kill",
				"hitStopTick.Final",
				"hitStopTick.Kill",
				"hitStopTick.Normal",
				"hitStopTick.Normal",
			})
		end
	)

	it("EntityDied: deaths that land together scream once; a later death screams again", function()
		local t = setup()
		local function vocals(): number
			return #t.find("sfx", "play")
		end
		-- One sweep kills two boars and a kobold in the same frame: one scream per voice.
		Replication.dispatch("EntityDied", { entityId = 7, shatter = "Beast", position = { 0, 0, 0 }, name = "Boar" })
		Replication.dispatch("EntityDied", { entityId = 7, shatter = "Beast", position = { 20, 0, 0 }, name = "Boar" })
		Replication.dispatch(
			"EntityDied",
			{ entityId = 8, shatter = "Beast", position = { 40, 0, 0 }, name = "Kobold" }
		)
		local names = {}
		for _, call in t.find("sfx", "play") do
			table.insert(names, call.args[1])
		end
		expect(names).toEqual({ "enemy.ChargerDeath", "enemy.BruteDeath" })
		-- Inside the window it is still the same sweep's deaths; past it, a new death.
		t.state.clock += moments.sweep.mergeSeconds * 0.5
		Replication.dispatch("EntityDied", { entityId = 7, shatter = "Beast", position = { 0, 0, 0 }, name = "Boar" })
		expect(vocals()).toBe(2)
		t.state.clock += moments.sweep.mergeSeconds * 1.01
		Replication.dispatch("EntityDied", { entityId = 7, shatter = "Beast", position = { 0, 0, 0 }, name = "Boar" })
		expect(vocals()).toBe(3)
		-- Every death still freezes, ducks and shatters (the shatter's own sound merges in SfxPool).
		runScheduled(t)
		expect(#t.find("shatter", "play")).toBe(5)
	end)

	it(
		"HitConfirmed: one sweep through many targets nudges the camera once and hands every hit to the director",
		function()
			local t = setup()
			for _ = 1, 12 do
				Replication.dispatch("HitConfirmed", hit())
			end
			expect(#t.find("camera", "nudge")).toBe(1)
			expect(#t.find("impact", "hit")).toBe(12)
			expect(#t.find("digits", "show")).toBe(12)
			-- The next swing nudges again.
			t.state.clock += moments.sweep.mergeSeconds * 1.01
			Replication.dispatch("HitConfirmed", hit())
			expect(#t.find("camera", "nudge")).toBe(2)
			-- Inside the window, still the same sweep.
			t.state.clock += moments.sweep.mergeSeconds * 0.5
			Replication.dispatch("HitConfirmed", hit())
			expect(#t.find("camera", "nudge")).toBe(2)
			-- Binding again forgets the last nudge.
			Replication.bind(t.deps)
			Replication.dispatch("HitConfirmed", hit())
			expect(#t.find("camera", "nudge")).toBe(3)
		end
	)

	it("HitConfirmed: the director's own white flash replaces Replication's", function()
		local t = setup()
		t.state.ownsHighlight = true
		Replication.dispatch("HitConfirmed", hit({ hitStop = "Final" }))
		expect(#t.find("outline", "flash")).toBe(0)
		expect(t.find("impact", "ownsHighlight")[1].args[1]).toBe(lastInfo(t))
		-- A Siblings stub (no director loaded) answers with a table: Replication flashes itself.
		t.state.ownsHighlight = {}
		Replication.dispatch("HitConfirmed", hit({ hitStop = "Final" }))
		expect(#t.find("outline", "flash")).toBe(1)
	end)

	it("ActionStarted: another fighter's dodge is the director's, the local dodge the controller's", function()
		local t = setup()
		Replication.dispatch("ActionStarted", {
			entityId = 2,
			clipId = "player/OneHandedSword/DodgeBack",
			serverTime = 5,
			facing = { 0, 0, -1 },
		})
		local dodges = t.find("impact", "dodge")
		expect(#dodges).toBe(1)
		expect(dodges[1].args[1]).toBe(t.models.ally)
		expect(dodges[1].args[2]).toBe(false)
		Replication.dispatch("ActionStarted", {
			entityId = 1,
			clipId = "player/OneHandedSword/DodgeLeft",
			serverTime = 6,
			facing = { 0, 0, -1 },
		})
		Replication.dispatch("ActionStarted", {
			entityId = 2,
			clipId = "player/OneHandedSword/Horizontal",
			serverTime = 7,
			facing = { 0, 0, -1 },
		})
		expect(#t.find("impact", "dodge")).toBe(1)
	end)

	it("ActionStarted: a remote dodge the catch-up started late hands the director its lateness", function()
		local t = setup()
		-- The Mixer started the dodge 0.1 s into its clip at speed 1.25: its cue (the whoosh and the
		-- landing at dodgeDuration) is 0.08 s of real time behind, so the landing keeps the clip's
		-- clock instead of sounding after the clip's own footstep.
		local handle: any =
			{ clipId = "player/OneHandedSword/DodgeBack", clip = { events = {} }, time = 0.1, speed = 1.25 }
		local animator = t.deps.choreo.get(t.models.ally)
		function animator.play(_self: any, clipId: string, opts: any): any
			table.insert(t.calls, { module = "animator:ally", fn = "play", args = { clipId, opts } })
			return handle
		end
		Replication.dispatch("ActionStarted", {
			entityId = 2,
			clipId = "player/OneHandedSword/DodgeBack",
			serverTime = 99.9,
			speed = 1.25,
			facing = { 0, 0, -1 },
		})
		local dodges = t.find("impact", "dodge")
		expect(#dodges).toBe(1)
		expect(dodges[1].args[1]).toBe(t.models.ally)
		expect(dodges[1].args[2]).toBe(false)
		expect(dodges[1].args[3]).toBeCloseTo(0.1 / 1.25, 1e-12)
		-- On time, or a handle with no clip clock (an engine Animation): no lateness.
		handle = { clipId = "player/OneHandedSword/DodgeLeft", clip = { events = {} }, time = 0, speed = 1 }
		Replication.dispatch(
			"ActionStarted",
			{ entityId = 2, clipId = "player/OneHandedSword/DodgeLeft", serverTime = 100 }
		)
		handle = { clipId = "player/OneHandedSword/DodgeRight", rbx = {}, speed = 1 }
		Replication.dispatch(
			"ActionStarted",
			{ entityId = 2, clipId = "player/OneHandedSword/DodgeRight", serverTime = 99 }
		)
		dodges = t.find("impact", "dodge")
		expect(#dodges).toBe(3)
		expect(dodges[2].args[3]).toBeNil()
		expect(dodges[3].args[3]).toBeNil()
	end)

	it("ActionStarted: the clip sounds a late start jumped over play from where they would be by now", function()
		local t = setup()
		-- A clip the network catch-up starts 0.05 s in, at speed 1.25: the whoosh at 0 and the vocal
		-- at 0.03 were jumped over; the Mixer's first step fires the one at 0.05 itself.
		local clip = {
			events = {
				{ time = 0, kind = "Sfx", data = { name = "whoosh.Basic" } },
				{ time = 0.03, kind = "Voice", data = { name = "enemy.ChargerWindUp" } },
				{ time = 0.04, kind = "Footstep" },
				{ time = 0.05, kind = "Sfx", data = { name = "whoosh.Medium" } },
				{ time = 0.2, kind = "Sfx", data = { name = "whoosh.Large" } },
			},
		}
		local handle: any = { clipId = "player/OneHandedSword/Basic1", clip = clip, time = 0.05, speed = 1.25 }
		local animator = t.deps.choreo.get(t.models.ally)
		function animator.play(_self: any, clipId: string, opts: any): any
			table.insert(t.calls, { module = "animator:ally", fn = "play", args = { clipId, opts } })
			return handle
		end
		Replication.dispatch(
			"ActionStarted",
			{ entityId = 2, clipId = "player/OneHandedSword/Basic1", serverTime = 99.96, speed = 1.25 }
		)
		local late = t.find("sfx", "playLate")
		expect(#late).toBe(2)
		expect(late[1].args[1]).toBe("whoosh.Basic")
		expect(late[1].args[2]).toBeCloseTo(0.05 / 1.25, 1e-12)
		expect(late[1].args[3]).toBe(Vector3.zero)
		expect(late[2].args[1]).toBe("enemy.ChargerWindUp")
		expect(late[2].args[2]).toBeCloseTo(0.02 / 1.25, 1e-12)
		expect(#t.find("sfx", "play")).toBe(0)
		-- A clip started on time replays nothing, nor does a handle with no clip clock (an engine
		-- Animation) or a looping clip.
		handle.time = 0
		Replication.dispatch(
			"ActionStarted",
			{ entityId = 2, clipId = "player/OneHandedSword/Basic1", serverTime = 100 }
		)
		handle = { clipId = "rbxassetid://1", rbx = {}, speed = 1 }
		Replication.dispatch("ActionStarted", { entityId = 2, clipId = "rbxassetid://1", serverTime = 99 })
		handle = { clipId = "x", clip = { loop = true, events = clip.events }, time = 0.1, speed = 1 }
		Replication.dispatch("ActionStarted", { entityId = 2, clipId = "x", serverTime = 99.9 })
		expect(#t.find("sfx", "playLate")).toBe(2)
	end)

	it("ActionStarted: an Art's hold a late start jumped over still lights, chimes and rises", function()
		local t = setup()
		local clipId = "player/OneHandedSword/Horizontal"
		local horizontal = Harness.load("src/shared/clips/player/OneHandedSword/Horizontal")
		local holdAt, windowAt = 0, 0
		for _, event in horizontal.events do
			if event.kind == "ActivationHold" then
				holdAt = event.time
			elseif event.kind == "HitWindowOpen" and windowAt == 0 then
				windowAt = event.time
			end
		end
		expect(windowAt > holdAt + 0.1).toBe(true)
		-- The network catch-up starts the clip 0.1 s past its hold, at speed 1.25.
		local handle: any = { clipId = clipId, clip = horizontal, time = holdAt + 0.1, speed = 1.25 }
		local animator = t.deps.choreo.get(t.models.ally)
		function animator.play(_self: any, _clipId: string, _opts: any): any
			return handle
		end
		Replication.dispatch("ActionStarted", { entityId = 2, clipId = clipId, serverTime = 99.9, speed = 1.25 })
		local holds = t.find("impact", "activation")
		expect(#holds).toBe(1)
		expect(holds[1].args[1]).toBe(t.models.ally)
		expect(holds[1].args[2]).toBe(clipId)
		expect(holds[1].args[3]).toBe("TrailCyanWhite")
		expect(holds[1].args[4]).toBe(false)
		expect(holds[1].args[5]).toBe(1.25)
		expect(holds[1].args[6]).toBeCloseTo(0.1 / 1.25, 1e-12)
		local lights = t.find("trails", "activationLight")
		expect(#lights).toBe(1)
		expect(lights[1].args[2]).toBe(true)
		local chimes = {}
		for _, call in t.find("sfx", "playLate") do
			if string.find(call.args[1], "artChime.", 1, true) == 1 then
				table.insert(chimes, call)
			end
		end
		expect(#chimes).toBe(1)
		expect(chimes[1].args[1]).toBe("artChime.TrailCyanWhite")
		expect(chimes[1].args[2]).toBeCloseTo(0.1 / 1.25, 1e-12)
		-- Started past the first damage window: the hold is over, nothing replays for it; started
		-- before the hold, the Mixer fires it itself.
		for _, time in { windowAt, windowAt + 0.05, holdAt } do
			handle = { clipId = clipId, clip = horizontal, time = time, speed = 1 }
			Replication.dispatch("ActionStarted", { entityId = 2, clipId = clipId, serverTime = 99 })
		end
		expect(#t.find("impact", "activation")).toBe(1)
		expect(#t.find("trails", "activationLight")).toBe(1)
	end)

	it("ActivationHold: the director times the riser by the clip's speed from ActionStarted", function()
		local t = setup()
		Replication.dispatch("ActionStarted", {
			entityId = 2,
			clipId = "player/OneHandedSword/Horizontal",
			serverTime = 5,
			facing = { 0, 0, -1 },
			speed = 1.25,
		})
		Replication.routeClipEvent(
			t.records[2],
			"player/OneHandedSword/Horizontal",
			{ time = 0.15, kind = "ActivationHold" }
		)
		local holds = t.find("impact", "activation")
		expect(#holds).toBe(1)
		expect(holds[1].args[1]).toBe(t.models.ally)
		expect(holds[1].args[2]).toBe("player/OneHandedSword/Horizontal")
		expect(holds[1].args[3]).toBe("TrailCyanWhite")
		expect(holds[1].args[4]).toBe(false)
		expect(holds[1].args[5]).toBe(1.25)
		-- Another clip's hold has no speed of its own; the local hold is the local fighter's.
		Replication.routeClipEvent(
			t.records[2],
			"player/OneHandedSword/Vertical",
			{ time = 0.15, kind = "ActivationHold" }
		)
		expect(t.find("impact", "activation")[2].args[5]).toBeNil()
		Replication.routeClipEvent(
			t.records[1],
			"player/OneHandedSword/Horizontal",
			{ time = 0.15, kind = "ActivationHold" }
		)
		expect(t.find("impact", "activation")[3].args[4]).toBe(true)
		-- unwatch forgets the speed.
		Replication.unwatch(t.records[2])
		Replication.routeClipEvent(
			t.records[2],
			"player/OneHandedSword/Horizontal",
			{ time = 0.15, kind = "ActivationHold" }
		)
		expect(t.find("impact", "activation")[4].args[5]).toBeNil()
	end)

	it("HitConfirmed: a trade is two sweeps, each with its own nudge and hit-stop tick", function()
		local t = setup()
		local function ticks(): { string }
			local names = {}
			for _, call in t.find("sfx", "play") do
				if string.find(call.args[1], "hitStopTick", 1, true) then
					table.insert(names, call.args[1])
				end
			end
			return names
		end
		-- The local player's basic hit on the boar, then 20 ms later the axeman's strike on them.
		Replication.dispatch("HitConfirmed", hit({ attackerId = 1, targetId = 7, artId = NONE }))
		t.state.clock += 0.02
		Replication.dispatch("HitConfirmed", hit({ attackerId = 8, targetId = 1, artId = NONE }))
		expect(#t.find("camera", "nudge")).toBe(2)
		expect(ticks()).toEqual({ "hitStopTick.Normal", "hitStopTick.Normal" })
		-- An Art's final hit, then a weaker strike taken 20 ms later: the blow taken still ticks.
		t.state.clock += 1
		Replication.dispatch("HitConfirmed", hit({ attackerId = 1, targetId = 7, hitStop = "Final" }))
		t.state.clock += 0.02
		Replication.dispatch("HitConfirmed", hit({ attackerId = 8, targetId = 1, artId = NONE }))
		expect(ticks()).toEqual({
			"hitStopTick.Normal",
			"hitStopTick.Normal",
			"hitStopTick.Final",
			"hitStopTick.Normal",
		})
		-- The same attacker's sweep still nudges and ticks once; unwatch forgets its sweep.
		t.state.clock += 1
		Replication.dispatch("HitConfirmed", hit({ attackerId = 8, targetId = 1, artId = NONE }))
		Replication.dispatch("HitConfirmed", hit({ attackerId = 8, targetId = 1, artId = NONE }))
		expect(#t.find("camera", "nudge")).toBe(5)
		expect(#ticks()).toBe(5)
		Replication.unwatch(t.records[8])
		Replication.dispatch("HitConfirmed", hit({ attackerId = 8, targetId = 1, artId = NONE }))
		expect(#t.find("camera", "nudge")).toBe(6)
	end)

	it("EntityDied: a death inside another's silence is heard; an older shatter never ends it", function()
		local t = setup()
		local runUntil = timedScheduler(t)
		local function ducks(): { number }
			local list = {}
			for _, call in t.find("sfx", "duck") do
				table.insert(list, call.args[1])
			end
			return list
		end
		local lead = moments.deathDuckDelay()
		local start = t.state.clock
		Replication.dispatch("EntityDied", { entityId = 7, shatter = "Beast", position = { 0, 0, 0 }, name = "Boar" })
		runUntil(start + lead + 0.01)
		expect(ducks()).toEqual({ combat.deathDuckDb })
		-- The Kobold dies inside the Boar's silence: the groups come back at once for its kill.
		local second = start + lead + combat.deathFreeze * 0.5
		runUntil(second)
		Replication.dispatch("EntityDied", { entityId = 8, shatter = "Beast", position = { 4, 0, 0 }, name = "Kobold" })
		expect(ducks()).toEqual({ combat.deathDuckDb, 0 })
		-- Its own silence follows its hit-stop; the Boar's shatter inside it restores nothing.
		runUntil(second + lead + combat.deathFreeze * 0.5)
		expect(ducks()).toEqual({ combat.deathDuckDb, 0, combat.deathDuckDb })
		expect(#t.find("shatter", "play")).toBe(1)
		runUntil(second + lead + combat.deathFreeze)
		expect(ducks()).toEqual({ combat.deathDuckDb, 0, combat.deathDuckDb, 0 })
		expect(#t.find("shatter", "play")).toBe(2)

		-- A death inside another's hit-stop lead (past one sweep's window): only the newer one's
		-- silence comes, and the older shatter inside it restores nothing.
		local third = t.state.clock + 2
		local gap = (lead + moments.sweep.mergeSeconds) * 0.5
		expect(gap).toBeGreaterThan(moments.sweep.mergeSeconds)
		expect(gap).toBeLessThan(lead)
		runUntil(third)
		Replication.dispatch("EntityDied", { entityId = 7, shatter = "Beast", position = { 0, 0, 0 }, name = "Boar" })
		runUntil(third + gap)
		Replication.dispatch("EntityDied", { entityId = 8, shatter = "Beast", position = { 4, 0, 0 }, name = "Kobold" })
		runUntil(third + gap + lead + combat.deathFreeze + 0.01)
		expect(ducks()).toEqual({ combat.deathDuckDb, 0, combat.deathDuckDb, 0, combat.deathDuckDb, 0 })
		expect(#t.find("shatter", "play")).toBe(4)
	end)

	it("dispatch rejects unknown remotes", function()
		setup()
		expect(function()
			Replication.dispatch("Nope", {})
		end).toThrow("no handler")
	end)
end)

describe("Replication: the local fighter's contact (issue 4)", function()
	local ART = "OneHandedSword.Horizontal"
	local FRAME = ChoreoData.frameSeconds

	local function contact(overrides: { [string]: any }?): any
		local entry: { [string]: any } = {
			targetId = 7,
			windowIndex = 1,
			artId = ART,
			tier = "Normal",
			killed = false,
			position = Vector3.new(1, 2, -3),
		}
		for key, value in overrides or {} do
			entry[key] = if value == NONE then nil else value
		end
		return entry
	end

	local function count(t: any, moduleName: string, fn: string): number
		return #t.find(moduleName, fn)
	end

	local function ticks(t: any): { string }
		local names = {}
		for _, call in t.find("sfx", "play") do
			if string.find(call.args[1], "hitStopTick", 1, true) then
				table.insert(names, call.args[1])
			end
		end
		return names
	end

	it("plays the hit on contact: hit-stop on both rigs, white flash, nudge, shake, tick, moment; no number", function()
		local t = setup()
		t.state.moment = "Hit"
		expect(Replication.contact(contact())).toBe(true)
		expect(t.find("animator:me", "hitStop")[1].args[1]).toBe(combat.hitStopFrames.Normal)
		expect(t.find("animator:boar", "hitStop")[1].args[1]).toBe(combat.hitStopFrames.Normal)
		local flash = t.find("outline", "flash")
		expect(#flash).toBe(1)
		expect(flash[1].args[1]).toBe(t.models.boar)
		expect(flash[1].args[2]).toBe("SystemWhite")
		expect(flash[1].args[3]).toBe(combat.highlightFlashFrames)
		local nudge = t.find("camera", "nudge")
		expect(#nudge).toBe(1)
		expect(nudge[1].args[1]).toBe(Vector3.new(1, 2, -3))
		expect(t.find("camera", "shake")[1].args[1]).toBe("Normal")
		expect(ticks(t)).toEqual({ "hitStopTick.Normal" })
		local info = lastInfo(t)
		expect(info.tier).toBe("Normal")
		expect(info.attacker).toBe(t.models.me)
		expect(info.target).toBe(t.models.boar)
		expect(info.involved).toBe(true)
		expect(info.localAttacker).toBe(true)
		expect(info.art).toBe(true)
		for _, flag in { "parried", "guarded", "crit", "isSwitch", "killed" } do
			expect(info[flag]).toBe(false)
		end
		-- The number and the HP change are the server's.
		expect(count(t, "digits", "show")).toBe(0)
		expect(count(t, "hud", "flashHp")).toBe(0)
		-- A basic swing is no Art's; a proven kill is the Kill moment.
		Replication.contact(contact({ artId = NONE, windowIndex = 2 }))
		expect(lastInfo(t).art).toBe(false)
		Replication.contact(contact({ targetId = 8, tier = "Kill", killed = true }))
		expect(lastInfo(t).killed).toBe(true)
		expect(t.find("animator:axeman", "hitStop")[1].args[1]).toBe(combat.hitStopFrames.Kill)
	end)

	it("its confirmation shows the number and the reactions and replays nothing", function()
		local t = setup()
		t.state.moment = "Hit"
		Replication.contact(contact())
		local before = #t.calls
		t.state.clock += 6 * FRAME
		local seen = {}
		Replication.hit:Connect(function(payload)
			table.insert(seen, payload)
		end)
		Replication.dispatch("HitConfirmed", hit({ crit = true, staggerDirection = "Left" }))
		local digits = t.find("digits", "show")
		expect(#digits).toBe(1)
		expect(digits[1].args[2]).toBe(42)
		expect(digits[1].args[3]).toBe("Crit")
		expect(#seen).toBe(1)
		local after = {}
		for index = before + 1, #t.calls do
			local call = t.calls[index]
			table.insert(after, call.module .. "." .. call.fn)
		end
		for _, name in after do
			for _, banned in
				{
					"animator:me.hitStop",
					"animator:boar.hitStop",
					"outline.flash",
					"camera.nudge",
					"camera.shake",
					"impact.hit",
					"sfx.play",
				}
			do
				if name == banned then
					error("the confirmation replayed " .. name)
				end
			end
		end
		-- The flinch is the server's: it plays with the confirmation.
		local plays = t.find("animator:boar", "play")
		expect(#plays).toBe(1)
		-- A second confirmation of the same hit has no contact left: it plays whole.
		Replication.dispatch("HitConfirmed", hit())
		expect(count(t, "animator:boar", "hitStop")).toBe(2)
	end)

	it("a stronger tier holds its length from the contact, never restarted, and plays what it adds", function()
		local t = setup()
		t.state.moment = "Hit"
		Replication.contact(contact())
		t.state.clock += 2 * FRAME
		Replication.dispatch("HitConfirmed", hit({ hitStop = "Kill", killed = true }))
		local meStops = t.find("animator:me", "hitStop")
		local boarStops = t.find("animator:boar", "hitStop")
		expect(#meStops).toBe(2)
		expect(#boarStops).toBe(2)
		-- 10 frames from the contact, 2 of them gone while the contact's 3 still hold: 8 more.
		expect(math.abs(meStops[2].args[1] - (combat.hitStopFrames.Kill - 2))).toBeLessThan(1e-6)
		expect(math.abs(boarStops[2].args[1] - (combat.hitStopFrames.Kill - 2))).toBeLessThan(1e-6)
		local shakes = t.find("camera", "shake")
		expect(shakes[#shakes].args[1]).toBe("Kill")
		expect(ticks(t)).toEqual({ "hitStopTick.Normal", "hitStopTick.Kill" })
		-- The contact gave the nudge and the flash.
		expect(count(t, "camera", "nudge")).toBe(1)
		expect(count(t, "outline", "flash")).toBe(1)
		local hits = t.find("impact", "hit")
		expect(#hits).toBe(2)
		expect(hits[2].args[1].killed).toBe(true)
		expect(hits[2].args[1].tier).toBe("Kill")
		expect(hits[2].args[2]).toBe("Hit")
		expect(#t.find("digits", "show")).toBe(1)

		-- A contact's Final the server makes a Kill 4 frames on: 6 more of the 10.
		local final = setup()
		Replication.contact(contact({ windowIndex = 3, tier = "Final" }))
		final.state.clock += 4 * FRAME
		Replication.dispatch("HitConfirmed", hit({ hitStop = "Kill", killed = true, hitIndex = 3 }))
		local finalStops = final.find("animator:me", "hitStop")
		expect(#finalStops).toBe(2)
		expect(math.abs(finalStops[2].args[1] - (combat.hitStopFrames.Kill - 4))).toBeLessThan(1e-6)

		-- A confirmation after the contact's own hold let go never stops the rig again (one hold per
		-- hit), even with frames of the stronger tier's length left; what the tier adds still plays.
		for _, case in
			{ { tier = "Normal", after = 4, server = "Kill" }, { tier = "Normal", after = 12, server = "Final" } }
		do
			local late = setup()
			Replication.contact(contact({ windowIndex = 3, tier = case.tier }))
			late.state.clock += case.after * FRAME
			Replication.dispatch("HitConfirmed", hit({ hitStop = case.server, hitIndex = 3 }))
			expect(#late.find("animator:me", "hitStop")).toBe(1)
			expect(#late.find("animator:boar", "hitStop")).toBe(1)
			expect(#late.find("impact", "hit")).toBe(2)
			local lateShakes = late.find("camera", "shake")
			expect(lateShakes[#lateShakes].args[1]).toBe(case.server)
		end
	end)

	it("matches the hit by target, window and Art, oldest first, within contact.confirmSeconds", function()
		local t = setup()
		Replication.contact(contact())
		-- Another window, another Art, another target: each is a hit of its own and plays whole.
		for _, other in { { hitIndex = 2 }, { artId = "OneHandedSword.Vertical" }, { artId = NONE }, { targetId = 8 } } do
			local stops = count(t, "animator:me", "hitStop")
			Replication.dispatch("HitConfirmed", hit(other))
			expect(count(t, "animator:me", "hitStop")).toBe(stops + 1)
		end
		-- The contact's own confirmation still finds it.
		local stops = count(t, "animator:me", "hitStop")
		Replication.dispatch("HitConfirmed", hit())
		expect(count(t, "animator:me", "hitStop")).toBe(stops)

		-- A contact the server never confirmed in time shows nothing; a confirmation after that
		-- plays the hit whole.
		local stale = setup()
		Replication.contact(contact())
		stale.state.clock += combat.contact.confirmSeconds + 0.01
		expect(#stale.find("digits", "show")).toBe(0)
		Replication.dispatch("HitConfirmed", hit())
		expect(#stale.find("animator:me", "hitStop")).toBe(2)
		expect(#stale.find("outline", "flash")).toBe(2)
	end)

	it("a hit the server confirmed first answers confirmedAlready once, and goes stale", function()
		local t = setup()
		Replication.dispatch("HitConfirmed", hit({ hitIndex = 2 }))
		expect(Replication.confirmedAlready(7, 1, ART)).toBe(false)
		expect(Replication.confirmedAlready(7, 2, "OneHandedSword.Vertical")).toBe(false)
		expect(Replication.confirmedAlready(7, 2, ART)).toBe(true)
		expect(Replication.confirmedAlready(7, 2, ART)).toBe(false)
		Replication.dispatch("HitConfirmed", hit({ hitIndex = 2 }))
		t.state.clock += combat.contact.confirmSeconds + 0.01
		expect(Replication.confirmedAlready(7, 2, ART)).toBe(false)
		-- Someone else's hit, and a hit the local player took, are never the local fighter's.
		Replication.dispatch("HitConfirmed", hit({ attackerId = 2 }))
		Replication.dispatch("HitConfirmed", hit({ attackerId = 8, targetId = 1, artId = NONE }))
		expect(Replication.confirmedAlready(7, 1, ART)).toBe(false)
		expect(Replication.confirmedAlready(1, 1, nil)).toBe(false)
	end)

	it("plays nothing for a target or a local fighter this client does not track yet", function()
		local t = setup()
		expect(Replication.contact(contact({ targetId = 99 }))).toBe(false)
		expect(Replication.contact(contact({ targetId = 1 }))).toBe(false)
		local unknown = setup({ unknownLocal = true })
		expect(Replication.contact(contact())).toBe(false)
		for _, world in { t, unknown } do
			expect(#world.calls).toBe(0)
		end
	end)

	it("leaves everyone else's hits as they were: another player's hit on the same enemy plays whole", function()
		local t = setup()
		Replication.contact(contact())
		Replication.dispatch("HitConfirmed", hit({ attackerId = 2 }))
		expect(#t.find("animator:ally", "hitStop")).toBe(1)
		expect(#t.find("animator:boar", "hitStop")).toBe(2)
		expect(#t.find("impact", "hit")).toBe(2)
		expect(#t.find("digits", "show")).toBe(1)
		-- The local contact still waits for its own confirmation.
		local stops = #t.find("animator:boar", "hitStop")
		Replication.dispatch("HitConfirmed", hit())
		expect(#t.find("animator:boar", "hitStop")).toBe(stops)
	end)
end)

-- A remote player on the real Choreo and Locomotion: a Lune rig with the server's sword, a
-- Humanoid standing still on the ground for the default tracker, and foot IK off (no raycast in
-- Lune). Everything else is a recorder (each call stamped with the spec clock in `at`), and
-- Replication reads the spec clock. A handler that throws inside a Signal only warns, so every
-- test here checks `live.handlerErrors()` too. `liveOptions.isLocal` makes the rig the local
-- player's own (no locomotion driver: the character controller owns that one).
local function liveRemote(liveOptions: { isLocal: boolean? }?)
	local isLocal = liveOptions ~= nil and liveOptions.isLocal == true
	local function frameSignal()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end
	Harness.stubService(
		"RunService",
		{ RenderStepped = frameSignal(), Heartbeat = frameSignal(), PreSimulation = frameSignal() }
	)
	local Choreo = Harness.load("src/client/choreo/Choreo")
	local Locomotion = Harness.load("src/client/choreo/Locomotion")
	local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
	local Rigs = Harness.load("src/shared/data/rigs")
	local RigBuilder = Harness.load("src/server/world/RigBuilder")
	local WeaponBuilder = Harness.load("src/server/world/WeaponBuilder")
	local WeaponModels = Harness.load("src/shared/data/weaponModels")
	local Weapons = Harness.load("src/shared/data/weapons")
	local clock = 100
	Choreo.configure({
		now = function()
			return clock
		end,
		cameraPosition = function()
			return Vector3.zero
		end,
	})

	local model = Instance.new("Model")
	model.Name = "Ren"
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", false)
	model:SetAttribute("State", "Idle")
	local parts = {}
	local function part(name)
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
	local weapon = nil
	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") and item.Name == WeaponModels.motorName then
			weapon = item
		end
	end

	local record =
		{ id = 2, model = model, kind = "Player", rig = "PlayerR15", weaponId = "TrialistSword", name = "Ren" }
	local calls = {}
	local warningsBefore = #Harness.warnings()
	local function stamped(moduleName)
		return setmetatable({}, {
			__index = function(_, key)
				return function(...)
					table.insert(calls, { module = moduleName, fn = key, args = { ... }, at = clock })
				end
			end,
		})
	end
	Replication.bind({
		net = { on = function() end },
		entities = {
			get = function(id)
				return if id == 2 then record else nil
			end,
		},
		localId = function()
			return if isLocal then 2 else 1
		end,
		locomotion = {
			attach = function(animator, rig, options)
				local withoutIK = table.clone(options or {})
				withoutIK.footIK = false
				return Locomotion.attach(animator, rig, withoutIK)
			end,
			destroy = Locomotion.destroy,
			humanoidTracker = Locomotion.humanoidTracker,
		},
		choreo = Choreo,
		clipLibrary = ClipLibrary,
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
		impact = stamped("impact"),
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
			return clock
		end,
	})
	Replication.watch(record)
	local animator = Choreo.get(model)
	local drawId = ChoreoData.locomotion.clipPrefix .. ChoreoData.sheath.clips.draw
	local live = {
		record = record,
		model = model,
		animator = animator,
		drawSteps = 0, -- steps that showed a Draw clip
		firstDraw = nil :: number?, -- the step that first showed one
		steps = 0,
	}
	-- One 60 Hz frame; records whether a Draw clip is on the rig.
	function live.step()
		clock += 1 / 60
		live.steps += 1
		animator:step(1 / 60)
		for _, handle in animator.mixer:handles() do
			if handle.clipId == drawId then
				live.drawSteps += 1
				live.firstDraw = live.firstDraw or live.steps
				break
			end
		end
	end
	-- Time passing with no frame rendered (a render stall): the clock moves, nothing steps.
	function live.advance(seconds: number)
		clock += seconds
	end
	function live.inHand(): boolean
		return weapon ~= nil and weapon.Part0 == parts.RightHand
	end
	function live.now(): number
		return clock
	end
	-- The calls the recorders took for `module.fn`, in order.
	function live.calls(moduleName: string, fn: string): { any }
		local found = {}
		for _, call in calls do
			if call.module == moduleName and call.fn == fn then
				table.insert(found, call)
			end
		end
		return found
	end
	-- Signal handler errors warned since this rig was built (a throw inside Replication's handlers).
	function live.handlerErrors(): { string }
		local found = {}
		local warnings = Harness.warnings()
		for index = warningsBefore + 1, #warnings do
			if warnings[index]:find("[Signal] handler error", 1, true) then
				table.insert(found, warnings[index])
			end
		end
		return found
	end
	function live.release()
		Replication.unwatch(record)
		Choreo.release(model)
		Choreo.configure({
			now = function()
				return 0
			end,
		})
	end
	return live
end

describe("Replication on a remote player's rig", function()
	it("an attack whose ActionStarted lands up to three frames behind its Drawn draw-cuts with no Draw", function()
		local horizontal = ChoreoData.locomotion.clipPrefix .. "Horizontal"
		for late = 0, 3 do
			local live = liveRemote()
			for _ = 1, 60 do
				live.step()
			end
			expect(live.inHand()).toBe(false)
			live.model:SetAttribute("Drawn", true)
			for _ = 1, late do
				live.step()
			end
			local dispatchedAt = live.now()
			Replication.dispatch(
				"ActionStarted",
				{ entityId = 2, clipId = horizontal, serverTime = dispatchedAt - 0.1, facing = { 0, 0, -1 } }
			)
			live.step()
			-- The sword is in the hand on the Art's first posed frame, and no Draw ever played.
			expect(live.inHand()).toBe(true)
			for _ = 1, 90 do
				live.step()
			end
			expect(live.drawSteps).toBe(0)
			expect(live.inHand()).toBe(true)
			-- The clip's ActivationHold (0.15, the clip starting 0.1 in) reached the impact director
			-- once, on the frame the clip crossed it, as a remote rig at the clip's own speed.
			expect(live.handlerErrors()).toEqual({})
			local activations = live.calls("impact", "activation")
			expect(#activations).toBe(1)
			local call = activations[1]
			expect(call.args[1]).toBe(live.model)
			expect(call.args[2]).toBe(horizontal)
			expect(call.args[4]).toBe(false)
			expect(call.args[5]).toBeNil()
			expect(call.at).toBeGreaterThanOrEqual(dispatchedAt + 0.05 - 1e-9)
			expect(call.at).toBeLessThanOrEqual(dispatchedAt + 0.05 + 1 / 60 + 1e-9)
			live.release()
		end
	end)

	it("with no attack, the Draw starts once the rise has held remoteDrawDelay", function()
		local live = liveRemote()
		for _ = 1, 60 do
			live.step()
		end
		live.model:SetAttribute("Drawn", true)
		for _ = 1, 60 do
			live.step()
		end
		local delaySteps = math.ceil(ChoreoData.sheath.remoteDrawDelay * 60 - 1e-6)
		expect(live.firstDraw).toBe(60 + delaySteps)
		expect(live.inHand()).toBe(true)
		expect(live.handlerErrors()).toEqual({})
		live.release()
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Render stalls (D-132). Measured in Studio on 6437d91: with the display asleep RenderStepped runs
-- 0 times a second while Heartbeat runs 60, and the first RenderStepped dt after waking is the
-- whole gap. After a kill and Art swings made while it slept, the wake played the art chime at
-- +0.17 s, a whoosh at +0.32 s and footsteps, and moved the root: the clips replayed.
-- ------------------------------------------------------------------------------------------

describe("Replication across a render stall", function()
	local horizontal = ChoreoData.locomotion.clipPrefix .. "Horizontal"
	local ClipLibraryForSpec = Harness.load("src/client/choreo/ClipLibrary")

	-- Every start a recorder took so far, counted by name: a sound, a footstep, a cue, the FOV kick,
	-- an activation riser, a trail kind, the activation light or the smear turned on.
	local function starts(live: any): { [string]: number }
		local counts: { [string]: number } = {}
		local function add(key: string)
			counts[key] = (counts[key] or 0) + 1
		end
		for _, fn in { "play", "playLate", "footstep", "cue" } do
			for _, call in live.calls("sfx", fn) do
				add("sfx." .. fn .. " " .. tostring(call.args[1]))
			end
		end
		for _ in live.calls("camera", "fovKick") do
			add("camera.fovKick")
		end
		for _ in live.calls("impact", "activation") do
			add("impact.activation")
		end
		for _, call in live.calls("trails", "setActive") do
			if call.args[2] == true then
				add("trails.on " .. tostring(call.args[3]))
			end
		end
		for _, call in live.calls("trails", "activationLight") do
			if call.args[2] == true then
				add("trails.light")
			end
		end
		for _, call in live.calls("smear", "apply") do
			if call.args[2] == true then
				add("smear.on")
			end
		end
		return counts
	end

	-- What started between two counts, as sorted "name x count" lines.
	local function since(before: { [string]: number }, after: { [string]: number }): { string }
		local lines = {}
		for key, total in after do
			local added = total - (before[key] or 0)
			if added > 0 then
				table.insert(lines, ("%s x%d"):format(key, added))
			end
		end
		table.sort(lines)
		return lines
	end

	-- Four Horizontals swung while nothing renders (the local controller plays each at once; a remote
	-- rig's arrive as ActionStarted), then, with `kill`, the kill's HitConfirmed. Then the wake: one
	-- step of `wakeDt` (the whole gap by default; one frame for an engine that does not report the
	-- gap) and two seconds at 60 Hz. Returns what started after the wake and the root motion the
	-- animator reported from the wake on.
	local function sleepThenWake(
		isLocal: boolean,
		kill: boolean,
		gap: number,
		wakeDt: number?
	): ({ string }, number, any)
		local live = liveRemote({ isLocal = isLocal })
		for _ = 1, 60 do
			live.step()
		end
		local clockBefore = live.now()
		for _ = 1, 4 do
			if isLocal then
				live.animator:play(horizontal) -- CharacterController.beginArt
			else
				Replication.dispatch(
					"ActionStarted",
					{ entityId = 2, clipId = horizontal, serverTime = live.now() - 0.05, facing = { 0, 0, -1 } }
				)
			end
			live.advance(gap / 5)
		end
		if kill then
			Replication.dispatch("HitConfirmed", {
				attackerId = 2,
				targetId = 7,
				hitStop = "Kill",
				damage = 10,
				killed = true,
				artId = "OneHandedSword.Horizontal",
				position = { 0, 0, -3 },
			})
		end
		live.advance(gap / 5)
		expect(live.now() - clockBefore).toBeCloseTo(gap, 1e-9)
		local before = starts(live)
		local root = 0
		live.animator:step(wakeDt or gap)
		root += live.animator:currentRootMotionDelta().Magnitude
		for _ = 1, 120 do
			live.step()
			root += live.animator:currentRootMotionDelta().Magnitude
		end
		local started = since(before, starts(live))
		expect(live.handlerErrors()).toEqual({})
		return started, root, live
	end

	for _, case in
		{
			{ name = "the local fighter, a kill's hit-stop asked for in the stall", isLocal = true, kill = true },
			{ name = "the local fighter, no hit-stop pending", isLocal = true, kill = false },
			{ name = "a remote player, a kill's hit-stop asked for in the stall", isLocal = false, kill = true },
			{ name = "a remote player, no hit-stop pending", isLocal = false, kill = false },
		}
	do
		it(case.name .. ": nothing replays at the wake and the root stays put", function()
			for _, gap in { 5.4, 56 } do
				-- The wake's dt is the whole gap (as measured) or, on an engine that resets it, one frame.
				for _, wakeDt in { gap, 1 / 60 } do
					local started, root, live = sleepThenWake(case.isLocal, case.kill, gap, wakeDt)
					expect(table.concat(started, ", ")).toBe("")
					expect(root).toBe(0)
					-- What the gap crossed still closed: the Art's trail is off, its light out.
					local offs = 0
					for _, call in live.calls("trails", "setActive") do
						if call.args[2] == false and call.args[3] == "Art" then
							offs += 1
						end
					end
					expect(offs > 0).toBe(true)
					expect(live.animator:isPlaying(horizontal)).toBe(false)
					live.release()
				end
			end
		end)
	end

	-- An action that starts just before the wake (the key press that wakes the display, or a
	-- remote's ActionStarted arriving then) is the present: the wake shows it at its age and what is
	-- still ahead of it plays, once, after the wake.
	for _, case in
		{
			{ name = "the local fighter's Art", isLocal = true, clip = "Horizontal" },
			{ name = "a remote player's Art", isLocal = false, clip = "Horizontal" },
			{ name = "the local fighter's dodge", isLocal = true, clip = "DodgeForward" },
			{ name = "a remote player's basic swing", isLocal = false, clip = "Basic1" },
		}
	do
		it(case.name .. " started 0.1 s before the wake plays on from there", function()
			local clipId = ChoreoData.locomotion.clipPrefix .. case.clip
			local clipEvents = ClipLibraryForSpec.get(clipId).events
			for _, gap in { 5.4, 56 } do
				for _, wakeDt in { gap, 1 / 60 } do
					local live = liveRemote({ isLocal = case.isLocal })
					for _ = 1, 60 do
						live.step()
					end
					live.advance(gap - 0.1)
					if case.isLocal then
						live.animator:play(clipId)
					else
						Replication.dispatch(
							"ActionStarted",
							{ entityId = 2, clipId = clipId, serverTime = live.now(), facing = { 0, 0, -1 } }
						)
					end
					live.advance(0.1)
					local seen = {}
					local connection = Replication.clipEvent:Connect(function(_record, eventClipId, event, jumped)
						if eventClipId == clipId then
							table.insert(seen, { kind = event.kind, jumped = jumped })
						end
					end)
					local root = 0
					live.animator:step(wakeDt)
					root += live.animator:currentRootMotionDelta().Magnitude
					expect(live.animator:isPlaying(clipId)).toBe(true)
					for _ = 1, 120 do
						live.step()
						root += live.animator:currentRootMotionDelta().Magnitude
					end
					connection:Disconnect()
					-- Every event of the clip, once, none of them marked as a jump.
					local kinds = {}
					for _, entry in seen do
						expect(entry.jumped).toBe(false)
						table.insert(kinds, entry.kind)
					end
					local expected = {}
					for _, event in clipEvents do
						table.insert(expected, event.kind)
					end
					expect(kinds).toEqual(expected)
					-- The dodge still carries the body (its root motion is the dodge).
					if case.clip == "DodgeForward" then
						expect(root > 1).toBe(true)
					end
					expect(live.handlerErrors()).toEqual({})
					live.release()
				end
			end
		end)
	end
end)

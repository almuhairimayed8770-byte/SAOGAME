local Replication = Harness.load("src/client/controllers/Replication")
local combat = Harness.load("src/shared/data/combat")
local sfx = Harness.load("src/shared/data/sfx")

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
		attach = function(animator, model)
			attached += 1
			local driver = { animator = animator, model = model, index = attached }
			table.insert(calls, { module = "locomotion", fn = "attach", args = { animator, model }, driver = driver })
			return driver
		end,
		destroy = function(driver)
			table.insert(calls, { module = "locomotion", fn = "destroy", args = { driver } })
		end,
	}
end

-- options.unknownLocal: the tracker has not resolved the local id yet (localId() -> nil).
-- options.localCharacter: the models key the client already knows as its own character.
local function setup(options)
	options = options or {}
	local calls = {}
	local scheduled = {}
	local models = { me = Instance.new("Model"), boar = Instance.new("Model"), ally = Instance.new("Model") }
	local records = {
		[1] = {
			id = 1,
			model = models.me,
			kind = "Player",
			rig = "PlayerR15",
			weaponId = "TrialistSword",
			name = "Mira",
		},
		[7] = { id = 7, model = models.boar, kind = "Enemy", rig = "Boar", name = "Frenzy Boar" },
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
		telegraphs = recorder("telegraphs", calls),
		outline = recorder("outline", calls),
		switchRing = recorder("switchRing", calls),
		digits = recorder("digits", calls),
		hud = recorder("hud", calls),
		systemLine = recorder("systemLine", calls),
		sfx = recorder("sfx", calls),
		music = recorder("music", calls),
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

-- The shatter.Crack plays the reactions made so far.
local function cracks(t)
	local found = {}
	for _, call in t.find("sfx", "play") do
		if call.args[1] == "shatter.Crack" then
			table.insert(found, call)
		end
	end
	return found
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
		payload[key] = value
	end
	return payload
end

describe("Replication", function()
	it("HitConfirmed: hit-stop on both rigs, a digit, a white flash, nudge and shake for the attacker", function()
		local t = setup()
		Replication.dispatch("HitConfirmed", hit())
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
		-- The local attacker hears the hit-stop tick (2D) and the impact at the hit.
		local sounds = {}
		for _, call in t.find("sfx", "play") do
			table.insert(sounds, call.args[1])
		end
		expect(sounds).toContain("hitStopTick.Normal")
		expect(sounds).toContain("impact.Flesh")
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
		local whiteFlashes = switch.find("trails", "flashWhite")
		expect(#whiteFlashes).toBe(1)
		expect(whiteFlashes[1].args[1]).toBe(switch.models.me)
		expect(whiteFlashes[1].args[2]).toBe(combat.highlightFlashFrames)
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
		local sparks = t.find("trails", "flashWhite")
		expect(#sparks).toBe(1)
		expect(sparks[1].args[1]).toBe(t.models.me)
		local sounds = t.find("sfx", "play")
		expect(#sounds).toBe(1)
		expect(sounds[1].args[1]).toBe("guard.Parry")
		expect(t.find("camera", "shake")[1].args[1]).toBe("Normal")
		expect(#t.find("camera", "nudge")).toBe(0)
		local plays = t.find("animator:me", "play")
		expect(#plays).toBe(1)
		expect(plays[1].args[1]).toBe("player/OneHandedSword/Parry")
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
		Replication.dispatch("StateChanged", { entityId = 7, state = "Idle" })
		expect(#t.find("animator:boar", "stop")).toBe(3)

		Replication.dispatch("StateChanged", { entityId = 2, state = "GuardBroken", duration = 1.2 })
		expect(t.find("animator:ally", "play")[1].args[1]).toBe("player/OneHandedSword/GuardBreak")
		local flashes = t.find("outline", "flash")
		expect(#flashes).toBe(1)
		expect(flashes[1].args[2]).toBe("HPRed")
		-- Guard on another player plays their guard pose; the local player's guard is predicted locally.
		Replication.dispatch("StateChanged", { entityId = 2, state = "Guard" })
		expect(t.find("animator:ally", "play")[2].args[1]).toBe("player/OneHandedSword/Guard")
		Replication.dispatch("StateChanged", { entityId = 1, state = "Guard" })
		expect(#t.find("animator:me", "play")).toBe(0)
	end)

	it("EntityDied freezes the rig, ducks the music, then shatters (and reads a player's name)", function()
		local t = setup()
		Replication.dispatch(
			"EntityDied",
			{ entityId = 7, shatter = "Beast", position = { 0, 0, 0 }, name = "Frenzy Boar" }
		)
		expect(t.find("animator:boar", "play")[1].args[1]).toBe("enemy/Boar/DeathFreeze")
		expect(t.find("animator:boar", "setTimeScale")[1].args[1]).toBe(0)
		local ducks = t.find("music", "duck")
		expect(#ducks).toBe(1)
		expect(ducks[1].args[2]).toBe(combat.deathFreeze)
		expect(#t.find("shatter", "play")).toBe(0)
		expect(#t.scheduled).toBe(1)
		expect(t.scheduled[1].seconds).toBe(combat.deathFreeze)
		t.scheduled[1].fn()
		local shatters = t.find("shatter", "play")
		expect(#shatters).toBe(1)
		expect(shatters[1].args[1]).toBe(t.models.boar)
		expect(shatters[1].args[2]).toBe("Beast")
		expect(#t.find("systemLine", "show")).toBe(0)

		Replication.dispatch("EntityDied", { entityId = 2, shatter = "Humanoid", position = { 0, 0, 0 }, name = "Ren" })
		t.scheduled[2].fn()
		local lines = t.find("systemLine", "show")
		expect(#lines).toBe(1)
		expect(lines[1].args[1]).toBe("Ren has been struck from the Roll")
		expect(lines[1].args[2]).toBe("SystemWhite")
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

		Replication.routeClipEvent(me, "player/OneHandedSword/Horizontal", { time = 0.4, kind = "HitWindowClose" })
		expect(t.find("trails", "setActive")[2].args[2]).toBe(false)

		-- Basic swings get the thinner trail; other rigs' activation never kicks the local FOV.
		Replication.routeClipEvent(t.records[2], "player/OneHandedSword/Basic1", { time = 0.1, kind = "TrailOn" })
		expect(t.find("trails", "setActive")[3].args[3]).toBe("Basic")
		Replication.routeClipEvent(
			t.records[2],
			"player/OneHandedSword/Horizontal",
			{ time = 0.15, kind = "ActivationHold" }
		)
		expect(#t.find("camera", "fovKick")).toBe(1)
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

	it("EntityDied plays the crack once: through the shatter with a rig, directly when the rig is gone", function()
		local t = setup()
		Replication.dispatch(
			"EntityDied",
			{ entityId = 7, shatter = "Beast", position = { 1, 2, 3 }, name = "Frenzy Boar" }
		)
		t.scheduled[1].fn()
		expect(#t.find("shatter", "play")).toBe(1)
		expect(#cracks(t)).toBe(0)

		-- No record for the id: nothing to shatter, the crack still sounds where the server said.
		Replication.dispatch("EntityDied", { entityId = 99, shatter = "Beast", position = { 1, 2, 3 }, name = "Gone" })
		t.scheduled[2].fn()
		expect(#t.find("shatter", "play")).toBe(1)
		local played = cracks(t)
		expect(#played).toBe(1)
		expect(played[1].args[2]).toBe(Vector3.new(1, 2, 3))
		expect(#t.find("systemLine", "show")).toBe(0)
	end)

	it("dispatch rejects unknown remotes", function()
		setup()
		expect(function()
			Replication.dispatch("Nope", {})
		end).toThrow("no handler")
	end)
end)

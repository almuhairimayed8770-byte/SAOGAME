--!strict
--[[
	The guard stays up through a blocked hit and a parry (D-419).

	A guarded hit plays GuardHit (UpperBody, priority 12) and a parry plays Parry (14) on the
	defender's animator. The Mixer stops every UpperBody clip at or under a new one's priority, so
	either stops the Guard loop (10) the defender is holding; GuardHit runs 0.35 s and Parry 0.4 s,
	and nothing played Guard again, so the arms came down while the key was still held (through
	this path before D-419: Guard weight 1 before the hit and 0 a second after it, 4 of 4 cases).

	Here the defender's animator is a real Mixer (the clips from src/shared/clips), the Guard loop
	played the way CharacterController plays it for the local player and the way Replication
	plays it for a remote one (StateChanged Guard), and the server's HitConfirmed is dispatched
	through Replication. Once the reaction is over, a Guard loop shows at full weight again.
]]
local Replication = Harness.load("src/client/controllers/Replication")
local moments = Harness.load("src/shared/data/moments")

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

local Mixer = Harness.load("src/client/choreo/Mixer")
local CLIPS = "src/shared/clips/"
local FRAME = 1 / 60

-- A defender's animator over a real Mixer: Replication's calls reach the Mixer; anything else it
-- asks of an animator is a no-op.
local function realAnimator(mixer: any): any
	local animator = {
		mixer = mixer,
		events = fakeSignal(),
	}
	function animator:play(clipId: string, opts: any): any
		return mixer:play(Harness.load(CLIPS .. clipId), opts)
	end
	function animator:stop(handle: any, blendOut: number?)
		mixer:stop(handle, blendOut)
	end
	function animator:hitStop(frames: number)
		mixer:hitStop(frames)
	end
	function animator:setTimeScale(scale: number)
		mixer:setTimeScale(scale)
	end
	return setmetatable(animator, {
		__index = function()
			return function() end
		end,
	})
end

-- The Guard loop's weight on screen now (0 when no Guard handle is live).
local function guardWeight(mixer: any): number
	local weight = 0
	for _, handle in mixer:handles() do
		if handle.clipId == "player/OneHandedSword/Guard" and not handle.done then
			local shown = handle.weight * (if handle.stopping then handle.fade else 1)
			weight = math.max(weight, shown)
		end
	end
	return weight
end

local function blocked(fields: { [string]: any }): any
	local payload: { [string]: any } = {
		attackerId = 8,
		targetId = 1,
		damage = 0,
		crit = false,
		gaugeDamage = 4,
		killed = false,
		broke = false,
		hitStop = "Normal",
		position = { 0, 3, -2 },
		parried = false,
		guarded = true,
		hitIndex = 1,
	}
	for key, value in fields do
		payload[key] = value
	end
	return payload
end

describe("the guard stays up through a blocked hit (D-419)", function()
	local cases = {
		{ name = "the local player's guard takes a blocked hit", target = 1, parried = false },
		{ name = "the local player's guard parries", target = 1, parried = true },
		{ name = "a remote player's guard takes a blocked hit", target = 2, parried = false },
		{ name = "a remote player's guard parries", target = 2, parried = true },
	}
	for _, case in cases do
		it(case.name .. ": the Guard pose is back at full weight once the reaction is over", function()
			local t = setup()
			local record = t.records[case.target]
			local mixer = Mixer.new()
			local animators = {}
			local inner = t.deps.choreo.get
			t.deps.choreo.get = function(model)
				if model == record.model then
					local found = animators[model]
					if found == nil then
						found = realAnimator(mixer)
						animators[model] = found
					end
					return found
				end
				return inner(model)
			end
			if case.target == 1 then
				-- CharacterController plays the local guard itself.
				mixer:play(Harness.load(CLIPS .. "player/OneHandedSword/Guard"))
			else
				Replication.dispatch("StateChanged", { entityId = record.id, state = "Guard" })
			end
			for _ = 1, 30 do
				mixer:step(FRAME)
			end
			expect(guardWeight(mixer)).toBeCloseTo(1, 1e-3)
			Replication.dispatch(
				"HitConfirmed",
				blocked({ targetId = record.id, parried = case.parried, guarded = not case.parried })
			)
			-- The longer reaction (Parry, 0.4 s) and its blend out, at 60 fps: the key is held throughout.
			local lowest = 1
			for _ = 1, 60 do
				mixer:step(FRAME)
				lowest = math.min(lowest, guardWeight(mixer))
			end
			-- Under the reaction the Guard stays on (its weight never drops): the reaction lays over it.
			expect(lowest).toBeCloseTo(1, 1e-3)
			expect(guardWeight(mixer)).toBeCloseTo(1, 1e-3)
		end)
	end
end)

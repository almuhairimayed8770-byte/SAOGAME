--!strict
--[[
	A contact's hold waits for its word (D-312, Studio items 255 and 256), and a kill's word that
	comes inside it upgrades the hold in place (D-313).

	Studio (owner's PC, before round B): with 0.05 and 0.1 s of incoming lag, Sharp Nail, Rising
	Arc and the basic chain at 1.8 studs froze 1 to 3 frames, and the damage number showed 2 frames
	(0.05 s) or 5 frames (0.1 s) after the freeze began, often after it ended; a point-blank kill at
	0.05 s froze 2 predicted frames, moved on, and never held 10. Round B already made every hold
	count its full tier (D-271). Through the real path below, before this change: the number came
	4 frames after the contact at 0.1 s (60 fps), 8 at 144, after a 3-frame hold (7 at 144); a kill
	whose word came 4 frames after the contact froze 3 frames and its silence came 14 frames after
	the contact.

	The path: a Mixer posing the hit matrix's body, ContactPredictor and Replication (contact,
	HitConfirmed, EntityDied, the Heartbeat), the server's word sent on the server frame that
	counts the hit (the client's touch, less the hit-stops the client held so far) and heard
	`latency` later, before the frame's render step or after it. A frame is frozen when the rig's
	Mixer holds it (StepResult.paused).

	- The freeze starts on the contact frame (the frames after it hold its pose) and lasts at least
	  its tier; while the word has not come it holds on, one frame at a time, at most
	  contact.wordHoldSeconds from the contact. The frame that first shows the server's number is a
	  frozen frame, at 0 to 0.1 s of latency and a frame more, at 60 and 144 fps.
	- Past the cap the rigs go on, the number shows when the word comes, and nothing freezes again.
	  A hit the server never counts freezes to the cap and shows no number; a word for a later
	  window of the swing lets an earlier hold still waiting go at once.
	- A kill's word that comes inside the hold makes it one unbroken Kill hold from the contact
	  frame; the silence and the shatter keep the contact's beat (the Kill hold after the contact,
	  then combat.deathFreeze), as when the word comes first; the blade is never sought back.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Combat = Harness.load("src/shared/data/combat")
local Dev = Harness.load("src/shared/data/dev")
local Enemies = Harness.load("src/shared/data/enemies")
local Weapons = Harness.load("src/shared/data/weapons")
local Arts = Harness.load("src/shared/data/arts")
local Rigs = Harness.load("src/shared/data/rigs")
local World = Harness.load("src/shared/data/world")
local Playground = Harness.load("src/shared/data/playground")
local Moments = Harness.load("src/shared/data/moments")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")
local Joints = Harness.load("src/shared/choreo/Joints")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
local Mixer = Harness.load("src/client/choreo/Mixer")
local ContactPredictor = Harness.load("src/client/controllers/ContactPredictor")
local Replication = Harness.load("src/client/controllers/Replication")

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
local avatar = HitMatrix.standing(Harness)
local WEAPON = Weapons.byId(Playground.loadout.weapon)

local function setupOf(id: string): any
	for _, setup in Dev.hitMatrix.setups do
		if setup.id == id then
			return setup
		end
	end
	error("no hit matrix setup " .. id)
end

-- An enemy's rig in its rest pose, its root `distance` ahead of the player's, facing the player.
local function place(setupId: string, distance: number): (any, any)
	local setup = setupOf(setupId)
	local def = Enemies.byId(setup.enemy)
	local model = RigBuilder.build(def.skin)
	local height =
		PlaygroundLayout.rootHeight(Rigs[def.skin].hipHeight, model.PrimaryPart.Size.Y, World.spawn.groundEpsilon)
	local frame = avatar.base
		* CFrame.new(0, height - avatar.rootHeight, -distance)
		* CFrame.Angles(0, math.pi + math.rad(setup.yaw), 0)
	for name, solved in Pose.solve(model, frame, {}) do
		local part = model:FindFirstChild(name)
		if part ~= nil and part:IsA("BasePart") then
			part.CFrame = solved
		end
	end
	return model, def
end

local function recorder(): any
	return setmetatable({}, {
		__index = function(): any
			return function(): any
				return nil
			end
		end,
	})
end

type Contact = { frame: number, window: number, tier: string }
type Log = {
	frames: number,
	paused: { [number]: boolean },
	times: { [number]: number },
	contacts: { Contact },
	numbers: { [number]: number }, -- window -> the first frame that shows its number
	death: number?, -- the frame the enemy's death freeze shows on
	silence: number?,
	shatter: number?,
}

-- Plays one move through the real path. options: refuse (a window the server never counts),
-- killAt (the window the server's sweep kills on), afterRender (words are heard after the
-- frame's render step, before its Heartbeat), lateWord = { window, frame } (a word for a window
-- the blade has yet to reach, heard on that frame).
local function play(name: string, enemy: any, def: any, fps: number, latency: number, options: any?): Log
	local opts = options or {}
	local clip = Harness.load("src/shared/clips/player/OneHandedSword/" .. name)
	local windows = ClipSampler.hitWindows(clip)
	local art = if name:sub(1, 5) == "Basic" then nil else Arts.byId("OneHandedSword." .. name)
	local chainIndex = if art == nil then tonumber(name:sub(6)) :: number else 0
	local finalHit = art ~= nil or chainIndex >= Combat.basicChainLength
	local clock = 100
	local handlers: { [string]: any } = {}
	local heartbeat: any = nil
	local scheduled: { { at: number, fn: () -> () } } = {}
	local mixer = Mixer.new()
	local enemyMixer = Mixer.new()
	local frame = 0
	local phase = "render"
	local log: Log = { frames = 0, paused = {}, times = {}, contacts = {}, numbers = {} }
	-- The frame a call made now first shows on: this one before its render step, else the next.
	local function shownOn(): number
		return if phase == "before" then frame else frame + 1
	end
	local currentWindow = 0
	local animators: { [any]: any } = {
		[avatar.model] = {
			hitStop = function(_self: any, frames: number)
				mixer:hitStop(frames)
			end,
			pauseRemaining = function(_self: any): number
				return mixer:pauseRemaining()
			end,
			play = function() end,
		},
		[enemy] = {
			hitStop = function(_self: any, frames: number)
				enemyMixer:hitStop(frames)
			end,
			pauseRemaining = function(_self: any): number
				return enemyMixer:pauseRemaining()
			end,
			play = function() end,
			stop = function() end,
			setTimeScale = function(_self: any, scale: number)
				if scale == 0 and log.death == nil then
					log.death = shownOn()
				end
			end,
		},
	}
	local scaled = Enemies.scaled(def)
	local records: { [number]: any } = {
		[1] = { id = 1, model = avatar.model, kind = "Player", state = "Art", weaponId = WEAPON.id },
		[5] = {
			id = 5,
			model = enemy,
			kind = "Enemy",
			state = "Idle",
			defId = def.id,
			hp = scaled.hp,
			maxHp = scaled.hp,
			elite = false,
			rig = def.skin,
		},
	}
	local impact = {
		hit = function(info: any): string
			return Moments.selectFor(info)
		end,
		ownsHighlight = function(info: any): boolean
			return Moments.byId(Moments.selectFor(info)).highlight ~= nil
		end,
	}
	setmetatable(impact, { __index = recorder() })
	local digits = {
		show = function()
			if log.numbers[currentWindow] == nil then
				log.numbers[currentWindow] = shownOn()
			end
		end,
	}
	local sfx = setmetatable({
		duck = function(db: number)
			if db ~= 0 and log.silence == nil then
				log.silence = frame
			end
		end,
	}, { __index = recorder() })
	local shatter = setmetatable({
		play = function()
			log.shatter = log.shatter or frame
		end,
	}, { __index = recorder() })
	local predictor: any = nil
	Replication.bind({
		net = {
			on = function(remote: string, handler: any)
				handlers[remote] = handler
			end,
		},
		entities = {
			get = function(id: number): any
				return records[id]
			end,
			all = function(): { any }
				return {}
			end,
		},
		localId = function(): number?
			return 1
		end,
		locomotion = recorder(),
		choreo = {
			get = function(model: any): any
				return animators[model]
			end,
		},
		clipLibrary = recorder(),
		trails = recorder(),
		smear = recorder(),
		shatter = shatter,
		sparks = recorder(),
		telegraphs = recorder(),
		outline = recorder(),
		switchRing = recorder(),
		digits = digits,
		hud = recorder(),
		systemLine = recorder(),
		sfx = sfx,
		impact = impact,
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
		-- Scheduled work runs at the start of the first frame at or past its time.
		schedule = function(delay: number, fn: () -> ())
			table.insert(scheduled, { at = clock + delay, fn = fn })
		end,
		now = function(): number
			return clock
		end,
		onHeartbeat = function(fn: any)
			heartbeat = fn
		end,
		keyAhead = function(windowIndex: number, artId: string?, swing: number?): boolean
			local method = predictor ~= nil and predictor.awaitsKey or nil
			return method ~= nil and method(predictor, windowIndex, artId, swing) == true
		end,
	} :: any)
	Replication.subscribe()
	-- Which window's word is playing (a held word plays from inside Replication.contact).
	local confirm = Replication.handlers.HitConfirmed
	Replication.handlers.HitConfirmed = function(payload: any)
		local was = currentWindow
		currentWindow = payload.hitIndex
		confirm(payload)
		currentWindow = was
	end
	predictor = ContactPredictor.new({
		targets = function(): { any }
			return { records[1], records[5] }
		end,
		confirmed = Replication.confirmedAlready,
	})
	avatar.root.CFrame = avatar.base
	local handle = mixer:play(clip)
	assert(predictor:begin({
		model = avatar.model,
		clip = clip,
		artId = if art ~= nil then art.id else nil,
		finalHit = finalHit,
		multiplier = if art ~= nil then art.multiplier else Combat.basicAttackMultiplier,
		weaponAttack = WEAPON.attack,
	}))
	local words: { any } = {}
	local sent: { [number]: boolean } = {}
	local dead = false
	local held = 0
	local function word(index: number, at: number, killed: boolean)
		if killed then
			-- The server kills before it confirms: EntityDied comes just before the kill's word.
			table.insert(words, {
				at = at,
				death = true,
				payload = { entityId = 5, shatter = "Beast", position = { 0, 3, -2 }, name = "Kobold", byPlayer = true },
			})
		end
		table.insert(words, {
			at = at,
			payload = {
				attackerId = 1,
				targetId = 5,
				damage = 10,
				crit = false,
				gaugeDamage = 1,
				killed = killed,
				broke = false,
				hitStop = if killed then "Kill" else ContactPredictor.tierFor(index, #windows, finalHit, false),
				position = { 0, 3, -2 },
				parried = false,
				guarded = false,
				artId = if art ~= nil then art.id else nil,
				hitIndex = index,
				swing = nil,
			},
		})
	end
	local function send(index: number, at: number)
		if sent[index] or dead then
			return
		end
		sent[index] = true
		if opts.refuse == index then
			return
		end
		dead = opts.killAt == index
		word(index, at, dead)
	end
	local function deliver()
		local index = 1
		while index <= #words do
			if clock >= words[index].at - 1e-9 then
				local entry = table.remove(words, index)
				if entry.death then
					records[5].state = "Dead"
					handlers.EntityDied(entry.payload)
				else
					Replication.handlers.HitConfirmed(entry.payload)
				end
			else
				index += 1
			end
		end
	end
	while frame < 400 do
		frame += 1
		local dt = 1 / fps
		clock += dt
		phase = "before"
		local s = 1
		while s <= #scheduled do
			if clock >= scheduled[s].at - 1e-9 then
				(table.remove(scheduled, s) :: { at: number, fn: () -> () }).fn()
			else
				s += 1
			end
		end
		if opts.lateWord ~= nil and opts.lateWord.frame == frame then
			word(opts.lateWord.window, clock, false)
		end
		if not opts.afterRender then
			deliver()
		end
		phase = "render"
		local before = handle.time
		local stepped = mixer:step(dt)
		enemyMixer:step(dt)
		log.paused[frame] = stepped.paused
		log.times[frame] = handle.time
		if frame > 1 and handle.time <= before + 1e-9 and stepped.paused then
			held += dt
		end
		for _, joint in Joints.list(avatar.model) do
			local offset = stepped.offsets[joint.Name]
			joint.Transform = if offset ~= nil then ClipSampler.toCFrame(offset) else CFrame.identity
		end
		local delta = stepped.rootDelta
		avatar.root.CFrame = avatar.root.CFrame + Vector3.new(delta[1], delta[2], delta[3])
		local contacts = predictor:step(handle.time)
		-- The server counts a hit on the frame this client's blade first touches it, on its own
		-- clock: ahead of this client by the hit-stops held so far.
		for _, entry in predictor.pending do
			send(entry.windowIndex, clock - held + latency)
		end
		for _, contact in contacts do
			send(contact.windowIndex, clock - held + latency)
			table.insert(log.contacts, { frame = frame, window = contact.windowIndex, tier = contact.tier })
			Replication.contact(contact)
		end
		phase = "after"
		if opts.afterRender then
			deliver()
		end
		if heartbeat ~= nil then
			heartbeat(dt)
		end
		if handle.done and #words == 0 and #scheduled == 0 then
			break
		end
	end
	predictor:stop()
	Replication.handlers.HitConfirmed = confirm
	avatar.root.CFrame = avatar.base
	log.frames = frame
	return log
end

-- The frames a hold of `frames` (at 60) freezes at `fps`: the nearest whole count (D-271).
local function framesAt(frames: number, fps: number): number
	return math.floor(frames / 60 * fps + 0.5)
end

-- The frozen frames from the frame after `contact` on, without a break.
local function runFrom(log: Log, contact: number): number
	local length = 0
	while log.paused[contact + 1 + length] do
		length += 1
	end
	return length
end

local MOVES = { "SharpNail", "RisingArc", "Basic1", "Basic2", "Basic3" }
local FRAME = 1 / 60

describe("a contact's hold waits for its word (D-312)", function()
	it("holds its full tier from the contact and on until the word: the number shows inside the freeze", function()
		local enemy, def = place("Kobold", 1.8)
		local cap = Combat.contact.wordHoldSeconds
		local checked, waited = 0, 0
		for _, name in MOVES do
			for _, fps in { 60, 144 } do
				for _, latency in { 0, 0.05, 0.1, 0.1 + FRAME } do
					for _, afterRender in { false, true } do
						local log = play(name, enemy, def, fps, latency, { afterRender = afterRender })
						for _, contact in log.contacts do
							local where = ("%s %d fps %d ms%s, window %d"):format(
								name,
								fps,
								math.floor(latency * 1000 + 0.5),
								if afterRender then " (heard after the render step)" else "",
								contact.window
							)
							local run = runFrom(log, contact.frame)
							local tier = framesAt(Combat.hitStopFrames[contact.tier], fps)
							if run < tier then
								error(("%s: froze %d frames, its tier is %d"):format(where, run, tier))
							end
							if run > math.max(tier, math.floor(cap * fps + 1e-6)) then
								error(("%s: froze %d frames, past the cap"):format(where, run))
							end
							local shown = log.numbers[contact.window]
							if shown == nil then
								error(where .. ": no number")
							end
							if shown < contact.frame or shown > contact.frame + run then
								error(
									("%s: the number showed on frame %d, the freeze held frames %d to %d"):format(
										where,
										shown,
										contact.frame,
										contact.frame + run
									)
								)
							end
							checked += 1
							if run > tier then
								waited += 1
							end
						end
					end
				end
			end
		end
		expect(checked >= #MOVES * 2 * 4 * 2).toBe(true)
		-- The lags past a Normal's three frames are what held on.
		expect(waited > 0).toBe(true)
	end)

	it("past the cap the rigs go on, the number shows when it comes, and nothing freezes again", function()
		local enemy, def = place("Kobold", 1.8)
		for _, fps in { 60, 144 } do
			local log = play("Basic1", enemy, def, fps, 0.25)
			local contact = log.contacts[1]
			expect(contact ~= nil).toBe(true)
			local run = runFrom(log, contact.frame)
			expect(run).toBe(math.floor(Combat.contact.wordHoldSeconds * fps + 1e-6))
			local shown = log.numbers[1] :: number
			expect(shown > contact.frame + run).toBe(true)
			for f = contact.frame + run + 1, log.frames do
				expect(log.paused[f]).toBe(false)
			end
		end
	end)

	it("a hit the server never counts freezes to the cap and shows no number", function()
		local enemy, def = place("Kobold", 1.8)
		for _, fps in { 60, 144 } do
			local log = play("Basic1", enemy, def, fps, 0.05, { refuse = 1 })
			local contact = log.contacts[1]
			expect(contact ~= nil).toBe(true)
			expect(runFrom(log, contact.frame)).toBe(math.floor(Combat.contact.wordHoldSeconds * fps + 1e-6))
			expect(next(log.numbers)).toBe(nil)
			for f = contact.frame + runFrom(log, contact.frame) + 1, log.frames do
				expect(log.paused[f]).toBe(false)
			end
		end
	end)

	it("a word for a later window of the swing lets an earlier hold still waiting go at once", function()
		local enemy, def = place("Kobold", 1.8)
		-- Sharp Nail's first cut is never counted; the word for its second comes 5 frames after
		-- the first contact (the server runs ahead), before the blade gets there.
		local first = play("SharpNail", enemy, def, 60, 0.05, { refuse = 1 })
		local contact = first.contacts[1]
		expect(contact.window).toBe(1)
		local log = play("SharpNail", enemy, def, 60, 0.05, {
			refuse = 1,
			lateWord = { window = 2, frame = contact.frame + 5 },
		})
		expect(log.contacts[1].frame).toBe(contact.frame)
		-- The tier's three frames, the two it held on for, and the frame the word came on.
		expect(runFrom(log, contact.frame)).toBe(5)
	end)

	it("without a Heartbeat nothing waits: the hold is its tier", function()
		-- Replication.contact on a client that ticks no Heartbeat (deps.onHeartbeat absent).
		local mixer = Mixer.new()
		local enemyMixer = Mixer.new()
		local enemy = place("Kobold", 1.8)
		local animators: { [any]: any } = {
			[avatar.model] = {
				hitStop = function(_self: any, frames: number)
					mixer:hitStop(frames)
				end,
				pauseRemaining = function(_self: any): number
					return mixer:pauseRemaining()
				end,
			},
			[enemy] = {
				hitStop = function(_self: any, frames: number)
					enemyMixer:hitStop(frames)
				end,
				pauseRemaining = function(_self: any): number
					return enemyMixer:pauseRemaining()
				end,
			},
		}
		local records: { [number]: any } = {
			[1] = { id = 1, model = avatar.model, kind = "Player" },
			[5] = { id = 5, model = enemy, kind = "Enemy", defId = "KoboldAxeman" },
		}
		local impact = setmetatable({
			hit = function(): string
				return "BasicHit"
			end,
		}, { __index = recorder() })
		Replication.bind({
			net = { on = function() end },
			entities = {
				get = function(id: number): any
					return records[id]
				end,
				all = function(): { any }
					return {}
				end,
			},
			localId = function(): number?
				return 1
			end,
			locomotion = recorder(),
			choreo = {
				get = function(model: any): any
					return animators[model]
				end,
			},
			clipLibrary = recorder(),
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
			impact = impact,
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
				return 100
			end,
		} :: any)
		expect(Replication.contact({
			targetId = 5,
			windowIndex = 1,
			tier = "Normal",
			position = Vector3.zero,
		})).toBe(true)
		expect(mixer:pauseRemaining()).toBeCloseTo(Combat.hitStopFrames.Normal * FRAME, 1e-9)
	end)
end)

describe("a kill's word inside the hold upgrades it in place (D-313)", function()
	it("one unbroken Kill hold from the contact frame, the silence and shatter on its beat, no seek back", function()
		local enemy, def = place("Kobold", 1.8)
		local kills = 0
		for _, name in { "Basic1", "Basic2", "SharpNail", "RisingArc" } do
			for _, fps in { 60, 144 } do
				for _, latency in { 0.05, 0.1, 0.1 + FRAME } do
					for _, afterRender in { false, true } do
						local log = play(name, enemy, def, fps, latency, { killAt = 1, afterRender = afterRender })
						local contact = log.contacts[1]
						if contact == nil then
							-- The word came before the key (D-267): HitWord.spec covers that kill.
							continue
						end
						kills += 1
						local where = ("%s %d fps %d ms%s"):format(
							name,
							fps,
							math.floor(latency * 1000 + 0.5),
							if afterRender then " (heard after the render step)" else ""
						)
						local run = runFrom(log, contact.frame)
						local kill = framesAt(Combat.hitStopFrames.Kill, fps)
						if run ~= kill then
							error(("%s: the kill froze %d frames from the contact, not %d"):format(where, run, kill))
						end
						-- Never a second freeze, never the blade sought back.
						for f = contact.frame + run + 1, log.frames do
							if log.paused[f] then
								error(("%s: frame %d froze again"):format(where, f))
							end
						end
						for f = 2, log.frames do
							if log.times[f] < log.times[f - 1] - 1e-9 then
								error(("%s: the clip went back on frame %d"):format(where, f))
							end
						end
						-- The death's freeze shows inside the hold; the silence comes as the Kill hold
						-- counted from the contact ends, the shatter combat.deathFreeze after it.
						local death = log.death :: number
						expect(death >= contact.frame and death <= contact.frame + run).toBe(true)
						local silence = log.silence :: number
						local beat = Moments.deathDuckDelay()
						local want = contact.frame + math.ceil(beat * fps - 1e-6)
						if silence ~= want then
							error(("%s: the silence came on frame %d, not %d"):format(where, silence, want))
						end
						local shatter = log.shatter :: number
						expect(math.abs(shatter - (contact.frame + (beat + Combat.deathFreeze) * fps)) <= 1).toBe(true)
						expect(log.numbers[1] ~= nil and log.numbers[1] <= contact.frame + run).toBe(true)
					end
				end
			end
		end
		expect(kills >= 16).toBe(true)
	end)

	it("a kill's word past the cap freezes nothing more; its silence waits the Kill hold from the death", function()
		local enemy, def = place("Kobold", 1.8)
		for _, fps in { 60, 144 } do
			local log = play("Basic1", enemy, def, fps, 0.25, { killAt = 1 })
			local contact = log.contacts[1]
			local run = runFrom(log, contact.frame)
			expect(run).toBe(math.floor(Combat.contact.wordHoldSeconds * fps + 1e-6))
			for f = contact.frame + run + 1, log.frames do
				expect(log.paused[f]).toBe(false)
			end
			local death = log.death :: number
			expect(death > contact.frame + run).toBe(true)
			expect(math.abs((log.silence :: number) - (death + Moments.deathDuckDelay() * fps)) <= 1).toBe(true)
		end
	end)
end)

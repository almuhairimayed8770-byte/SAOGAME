--!strict
--[[
	The server's word waits for the strike's key (D-267, fix F1 at real latency). The key rule
	(D-227) keeps a touch found before its strike's key for the key frame, but the server sweeps
	the same arc on its own clock: it counts a point-blank hit at the window's open, and from the
	second window on it runs ahead of this client by the hit-stops the client held (its Art clock
	never pauses). Its HitConfirmed then came before the blade showed the key and, with no contact
	played yet, held the rig at once: at 50 to 67 ms of latency (the owner's Studio) 24 to 31 of
	80 holds froze inside the snap (Sharp Nail hits 2 and 3, Rising Arc's Final), and at 0 to 33 ms
	every one did, the review's "sword raised, pause, pop".

	Through the real path as StrikeKey.spec drives it (a Mixer posing the hit matrix's body,
	ContactPredictor, Replication.contact), plus the server's word: sent on the server frame that
	counts the hit (the client's touch, less the hit-stops the client held so far) and heard
	`latency` later, then Heartbeat after each rendered frame. No hold starts before its strike's
	key, every word the server sent holds the rig once, and a word with nothing to wait for (a
	swing that stopped, one past its wait) plays when it comes.

	A kill's word waits too, with its EntityDied (D-267 amended): before, a kill's word played when
	it came, and its death with it, so the Kill hold and the death freeze started inside the snap,
	before the key (30 kills each at 30, 60 and 144 fps: 29, 30 and 30 at 0 ms, 8, 8 and 8 at 67
	ms, still 8, 6 and 3 at 100 ms). Now the death plays on the key frame and the hold from the
	frame after, at 30, 60 and 144 fps and 0 to 100 ms, with the same wait and the same release.
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

-- An enemy's rig in its rest pose, its root `distance` from the player's at `bearing` degrees to
-- the right of the player's look, turned to face the player (and by the setup's yaw).
local function place(setupId: string, distance: number, bearing: number): (any, any)
	local setup = setupOf(setupId)
	local def = Enemies.byId(setup.enemy)
	local model = RigBuilder.build(def.skin)
	local height =
		PlaygroundLayout.rootHeight(Rigs[def.skin].hipHeight, model.PrimaryPart.Size.Y, World.spawn.groundEpsilon)
	local b = math.rad(bearing)
	local frame = avatar.base
		* CFrame.new(math.sin(b) * distance, height - avatar.rootHeight, -math.cos(b) * distance)
		* CFrame.Angles(0, math.pi - b + math.rad(setup.yaw), 0)
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

local WINDOWS_OF: { [string]: any } = {}
local function clipOf(name: string): any
	local clip = Harness.load("src/shared/clips/player/OneHandedSword/" .. name)
	WINDOWS_OF[name] = WINDOWS_OF[name] or ClipSampler.hitWindows(clip)
	return clip
end

type Window = { key: number, hold: number?, holdFrame: number?, keyFrame: number?, sent: boolean? }
-- A word the server sends, heard `at`: a HitConfirmed, or (death) an EntityDied.
type Word = { at: number, payload: any, death: boolean? }

-- Plays one move through the real path with the server's word `latency` after the server counts
-- each hit; `extraWords` adds words for windows the blade never touches (sent at their open).
-- Returns per window: its key, the clip time the first held frame showed and its frame.
local function play(
	name: string,
	enemy: any,
	def: any,
	fps: number,
	latency: number,
	options: any?
): { [number]: Window }
	local opts = options or {}
	local clip = clipOf(name)
	local art = if name:sub(1, 5) == "Basic" then nil else Arts.byId("OneHandedSword." .. name)
	local chainIndex = if art == nil then tonumber(name:sub(6)) :: number else 0
	local finalHit = art ~= nil or chainIndex >= Combat.basicChainLength
	local windows = WINDOWS_OF[name]
	local clock = 100
	local handlers: { [string]: any } = {}
	local heartbeat: any = nil
	local mixer = Mixer.new()
	local enemyMixer = Mixer.new()
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
			play = function() end,
			stop = function() end,
			-- EntityDied freezes the dying rig (time scale 0): the frame its death plays.
			setTimeScale = function(_self: any, scale: number)
				if scale == 0 and opts.deathFrame == nil then
					opts.deathFrame = opts.frame
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
			return clock
		end,
		onHeartbeat = function(fn: any)
			heartbeat = fn
		end,
		-- CharacterController.awaitsKey, as Replication.start binds it.
		keyAhead = function(windowIndex: number, artId: string?, swing: number?): boolean
			if opts.keyNever then
				return true
			end
			local method = predictor ~= nil and predictor.awaitsKey or nil
			return method ~= nil and method(predictor, windowIndex, artId, swing) == true
		end,
	} :: any)
	Replication.subscribe()
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
	local result: { [number]: Window } = {}
	for index in windows do
		result[index] = { key = ContactPredictor.strikeKey(clip, windows[index]) }
	end
	local words: { Word } = {}
	local sent: { [number]: boolean } = {}
	local held = 0
	local function send(index: number, at: number, killed: boolean?)
		sent[index] = true
		if killed then
			-- The server kills before it confirms: EntityDied (and the Dead state) come just before
			-- the kill's HitConfirmed.
			table.insert(words, {
				at = at,
				death = true,
				payload = { entityId = 5, shatter = "Beast", position = { 0, 3, -2 }, name = "Boar", byPlayer = true },
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
				killed = killed == true,
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
	local frame = 0
	local last = handle.time
	while not handle.done and frame < 600 do
		frame += 1
		opts.frame = frame
		local dt = 1 / fps
		clock += dt
		-- `loneDeathFrame`: another fighter's kill, an EntityDied no word of this fighter's follows.
		if opts.loneDeathFrame == frame then
			table.insert(words, {
				at = clock,
				death = true,
				payload = { entityId = 5, shatter = "Beast", position = { 0, 3, -2 }, name = "Boar", byPlayer = true },
			})
		end
		-- The words heard by this frame (before the render step).
		local index = 1
		while index <= #words do
			if clock >= words[index].at - 1e-9 then
				local word = table.remove(words, index) :: Word
				if word.death then
					opts.deathCame = opts.deathCame or frame
					records[5].state = "Dead"
					handlers.EntityDied(word.payload)
				else
					handlers.HitConfirmed(word.payload)
				end
			else
				index += 1
			end
		end
		-- The render step: the rig, the root motion, the blade's contacts.
		local before = handle.time
		local stepped = mixer:step(dt)
		enemyMixer:step(dt)
		if handle.time <= before + 1e-9 and frame > 1 then
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
		-- `killAt`: the server's sweep kills on that window, and counts nothing after it.
		for _, entry in predictor.pending do
			if not sent[entry.windowIndex] and not opts.dead then
				opts.dead = opts.killAt == entry.windowIndex
				send(entry.windowIndex, clock - held + latency, opts.dead)
			end
		end
		for _, contact in contacts do
			if not sent[contact.windowIndex] and not opts.dead then
				opts.dead = opts.killAt == contact.windowIndex
				send(contact.windowIndex, clock - held + latency, opts.dead)
			end
			Replication.contact(contact)
		end
		for index2, window in windows do
			if opts.wordAtOpen == index2 and not sent[index2] and handle.time >= window.open then
				send(index2, clock - held + latency, opts.killed)
			end
			local entry = result[index2]
			if entry.keyFrame == nil and handle.time >= entry.key - 1e-4 then
				entry.keyFrame = frame
			end
		end
		-- A held frame: the clock did not move since the last rendered frame.
		if frame > 1 and handle.time <= last + 1e-9 then
			local newest: number? = nil
			for index2 in windows do
				if sent[index2] and result[index2].hold == nil then
					newest = index2
					break
				end
			end
			if newest ~= nil then
				result[newest].hold = handle.time
				result[newest].holdFrame = frame
			end
		end
		last = handle.time
		if heartbeat ~= nil then
			heartbeat(dt)
		end
		if opts.stopAt ~= nil and handle.time >= opts.stopAt then
			predictor:stop()
			opts.stopAt = nil
		end
	end
	predictor:stop()
	avatar.root.CFrame = avatar.base
	for index2 in result do
		result[index2].sent = sent[index2] == true
	end
	return result
end

local MOVES_SHORT = { "Horizontal", "RisingArc", "SharpNail", "Basic1", "Basic2" }
local PLACES = {
	{ setup = "Kobold", distance = 1.8, bearing = 0 },
	{ setup = "BoarSide", distance = 2.3, bearing = 0 },
	{ setup = "BoarFacing", distance = 7, bearing = 0 },
}

describe("the server's word waits for the strike's key (D-267)", function()
	it("no word starts a hold before its strike's key, at 0 and 50 ms of latency and 30, 60, 144 fps", function()
		local holds = 0
		for _, placement in PLACES do
			local enemy, def = place(placement.setup, placement.distance, placement.bearing)
			for _, name in MOVES_SHORT do
				for _, fps in { 30, 60, 144 } do
					for _, latency in { 0, 0.05 } do
						for index, window in play(name, enemy, def, fps, latency) do
							if not (window :: any).sent then
								continue
							end
							-- Every hit the server counted holds the rig once, on or after its key.
							if window.hold == nil then
								error(
									("%s %s@%.1f %d fps %d ms: window %d was counted and never held"):format(
										name,
										placement.setup,
										placement.distance,
										fps,
										latency * 1000,
										index
									)
								)
							end
							holds += 1
							if (window.hold :: number) < window.key - 1e-4 then
								error(
									("%s %s@%.1f %d fps %d ms: window %d held at clip %.4f, its key is %.4f"):format(
										name,
										placement.setup,
										placement.distance,
										fps,
										latency * 1000,
										index,
										window.hold :: number,
										window.key
									)
								)
							end
						end
					end
				end
			end
		end
		expect(holds > #PLACES * #MOVES_SHORT * 3).toBe(true)
	end)

	it("a word for a hit the blade never draws waits for the key frame, then holds it", function()
		-- The kobold far out of reach: the server's word for Horizontal's cut comes at the open.
		local enemy, def = place("Kobold", 9, 0)
		for _, latency in { 0, 1 / 60 } do
			local result = play("Horizontal", enemy, def, 60, latency, { wordAtOpen = 1 })
			local window = result[1]
			expect((window :: any).sent).toBe(true)
			expect(window.hold ~= nil).toBe(true)
			expect((window.hold :: number) >= window.key - 1e-4).toBe(true)
			-- Held from the frame after the key frame: the key pose is what freezes.
			expect(window.holdFrame).toBe((window.keyFrame :: number) + 1)
		end
	end)

	it("a kill's word waits for the key with its death: the kill freeze starts on the key frame", function()
		local enemy, def = place("Kobold", 9, 0)
		for _, fps in { 30, 60, 144 } do
			for _, latency in { 0, 1 / 60 } do
				local opts: any = { wordAtOpen = 1, killed = true }
				local window = play("Horizontal", enemy, def, fps, latency, opts)[1]
				expect(opts.deathCame ~= nil).toBe(true)
				expect(opts.deathCame <= (window.keyFrame :: number)).toBe(true)
				-- The death plays on the key frame (its freeze, silence and shatter start there) and
				-- the Kill hold from the frame after: the key pose is what freezes.
				expect(opts.deathFrame).toBe(window.keyFrame)
				expect(window.holdFrame).toBe((window.keyFrame :: number) + 1)
			end
		end
	end)

	it("no kill freezes before its strike's key, at 30, 60, 144 fps and 0 to 100 ms of latency", function()
		local kills = 0
		for _, placement in PLACES do
			local enemy, def = place(placement.setup, placement.distance, placement.bearing)
			for _, name in MOVES_SHORT do
				clipOf(name)
				for killAt in WINDOWS_OF[name] do
					for _, fps in { 30, 60, 144 } do
						for _, latency in { 0, 0.05, 0.1 } do
							local opts: any = { killAt = killAt }
							local window = play(name, enemy, def, fps, latency, opts)[killAt]
							if not (window :: any).sent then
								continue
							end
							kills += 1
							local where = ("%s %s@%.1f %d fps %d ms, kill on window %d"):format(
								name,
								placement.setup,
								placement.distance,
								fps,
								latency * 1000,
								killAt
							)
							if window.hold == nil or (window.hold :: number) < window.key - 1e-4 then
								error(where .. ": the Kill hold started before the key")
							end
							local keyFrame = window.keyFrame :: number
							-- The death plays on the key frame when it came before it, else when it comes.
							local want = math.max(keyFrame, opts.deathCame :: number)
							if opts.deathFrame ~= want then
								error(
									("%s: the death came on frame %d and played on %s, the key frame is %d"):format(
										where,
										opts.deathCame,
										tostring(opts.deathFrame),
										keyFrame
									)
								)
							end
						end
					end
				end
			end
		end
		expect(kills > #PLACES * #MOVES_SHORT * 3).toBe(true)
	end)

	it("a death no word holds plays on the frame it comes", function()
		local enemy, def = place("Kobold", 9, 0)
		local opts: any = { loneDeathFrame = 4 }
		play("Horizontal", enemy, def, 60, 0, opts)
		expect(opts.deathCame).toBe(4)
		expect(opts.deathFrame).toBe(4)
	end)

	it("a kill's word for a swing that stopped plays when it comes, with its death", function()
		local enemy, def = place("Kobold", 9, 0)
		clipOf("Horizontal")
		local open = WINDOWS_OF.Horizontal[1].open
		local opts: any = { wordAtOpen = 1, killed = true, stopAt = open }
		local window = play("Horizontal", enemy, def, 60, 2 / 60, opts)[1]
		expect(window.hold ~= nil).toBe(true)
		expect((window.hold :: number) < window.key - 1e-4).toBe(true)
		expect(opts.deathFrame).toBe(opts.deathCame)
	end)

	it("a kill's word and its death wait at most combat.contact.wordWaitSeconds", function()
		local enemy, def = place("Kobold", 9, 0)
		for _, fps in { 30, 60, 144 } do
			-- A key that never comes: the word and its death play once the wait runs out.
			local opts: any = { wordAtOpen = 1, killed = true, keyNever = true }
			local window = play("Horizontal", enemy, def, fps, 0, opts)[1]
			expect(window.hold ~= nil).toBe(true)
			local waited = (opts.deathFrame - opts.deathCame) / fps
			expect(waited >= Combat.contact.wordWaitSeconds - 1e-9).toBe(true)
			expect(waited <= Combat.contact.wordWaitSeconds + 1 / fps + 1e-9).toBe(true)
			expect(window.holdFrame).toBe(opts.deathFrame + 1)
		end
	end)

	it("a word for a swing that stopped plays when it comes", function()
		local enemy, def = place("Kobold", 9, 0)
		clipOf("Horizontal")
		local open = WINDOWS_OF.Horizontal[1].open
		local result = play("Horizontal", enemy, def, 60, 2 / 60, { wordAtOpen = 1, stopAt = open })
		local window = result[1]
		expect(window.hold ~= nil).toBe(true)
		expect((window.hold :: number) < window.key - 1e-4).toBe(true)
	end)

	it("waits at most combat.contact.wordWaitSeconds", function()
		expect(typeof(Combat.contact.wordWaitSeconds)).toBe("number")
		-- Longer than the longest wait a word can have: a Normal hold still running, then the
		-- window's open to its key (at most four frames, section 10's snap).
		local wait = Combat.contact.wordWaitSeconds
		expect(wait >= (Combat.hitStopFrames.Normal + 4 + 1) / 60).toBe(true)
		expect(wait <= Combat.lagAllowance + 0.15).toBe(true)
	end)
end)

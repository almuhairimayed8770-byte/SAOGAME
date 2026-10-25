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
	swing that stopped, a kill, one past its wait) plays when it comes.
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

type Window = { key: number, hold: number?, holdFrame: number?, keyFrame: number? }

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
	local words: { { at: number, payload: any } } = {}
	local sent: { [number]: boolean } = {}
	local held = 0
	local function send(index: number, at: number, killed: boolean?)
		sent[index] = true
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
		local dt = 1 / fps
		clock += dt
		-- The words heard by this frame (before the render step).
		local index = 1
		while index <= #words do
			if clock >= words[index].at - 1e-9 then
				handlers.HitConfirmed(table.remove(words, index).payload)
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
		for _, entry in predictor.pending do
			if not sent[entry.windowIndex] then
				send(entry.windowIndex, clock - held + latency)
			end
		end
		for _, contact in contacts do
			if not sent[contact.windowIndex] then
				send(contact.windowIndex, clock - held + latency)
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

	it("a kill's word plays when it comes (its death comes with it)", function()
		local enemy, def = place("Kobold", 9, 0)
		local result = play("Horizontal", enemy, def, 60, 0, { wordAtOpen = 1, killed = true })
		local window = result[1]
		expect(window.hold ~= nil).toBe(true)
		expect((window.hold :: number) < window.key - 1e-4).toBe(true)
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

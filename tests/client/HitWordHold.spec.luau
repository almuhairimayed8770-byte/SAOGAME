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
	- The hold waits a frame at a time on the frame's own length, whatever step the Heartbeat
	  reports (Studio's is the simulation's: whole 1/240 s substeps, D-346), so it never lets go
	  and freezes again before its word or the cap.
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
local FrameClock = Harness.load("src/client/fx/FrameClock")
local Impact = Harness.load("src/client/fx/Impact")
local ImpactFrames = Harness.load("src/client/fx/ImpactFrames")
local FlashBudget = Harness.load("src/client/fx/FlashBudget")

-- The engine draws a pose on the frame after the step that wrote it (D-342): its Animator puts the
-- rig back to rest after the draw and Choreo writes it again on PreSimulation. Measured on the
-- PC on 1cf87aa (m1-m3): on a Final the blade moved on the first two frames the hold flagged and
-- stood still from the third; on a kill at no lag the white flash came on the frame before the
-- blade stopped. This is the engine's lag, not impact.poseLagFrames (the code's model of it).
local ENGINE_LAG = 1

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
type Hit = { frame: number, window: number, name: string, previous: string?, late: boolean? }
type Log = {
	frames: number,
	paused: { [number]: boolean },
	times: { [number]: number },
	-- What the PC's logger reads at Last + 1 (Choreo isPaused): the local rig still holds.
	flags: { [number]: boolean },
	-- What a reader of the hold as drawn asks then (Mixer:heldShown, D-353).
	shownHeld: { [number]: boolean },
	-- The local root after each frame's step.
	roots: { [number]: CFrame },
	-- The clip time of the pose the frame draws: the one written ENGINE_LAG steps before.
	drawn: { [number]: number },
	-- The target's step held (its Mixer paused).
	targetPaused: { [number]: boolean },
	-- window -> cue -> the first frame it shows on: flash (the white Highlight), moment (the
	-- director's hit: picture, sound, accents, punch), camera (nudge, shake), tick, number.
	cues: { [number]: { [string]: number } },
	hits: { Hit }, -- every Impact.hit, in order
	contacts: { Contact },
	numbers: { [number]: number }, -- window -> the first frame that shows its number
	-- With `pictures`: the overlay's look each frame draws (ImpactFrames.look after its render
	-- step: "Black", "Dark", "Ink"... or "Reduced" for the soft dim; absent when it shows nothing).
	looks: { [number]: string },
	death: number?, -- the frame the enemy's death freeze shows on
	silence: number?,
	shatter: number?,
}

-- Plays one move through the real path. options: refuse (a window the server never counts),
-- killAt (the window the server's sweep kills on), afterRender (words are heard after the
-- frame's render step, before its Heartbeat), lateWord = { window, frame } (a word for a window
-- the blade has yet to reach, heard on that frame), renderDt = fn(frame) (each frame's length,
-- else 1 / fps) and beatDt = fn(frame) (the step the frame's Heartbeat reports, else the frame's
-- length), warm (both rigs step that many frames of the same pacing, empty, before the move),
-- pictures (the real Impact director and ImpactFrames overlay play the moments, logging looks).
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
	local log: Log = {
		frames = 0,
		paused = {},
		times = {},
		flags = {},
		shownHeld = {},
		roots = {},
		drawn = {},
		targetPaused = {},
		cues = {},
		hits = {},
		contacts = {},
		numbers = {},
		looks = {},
	}
	-- The frame a call made now first shows on: this one up to the end of its render steps, else
	-- the next.
	local function shownOn(): number
		return if phase == "after" then frame + 1 else frame
	end
	local currentWindow = 0
	-- The window a cue that waited for its frame (deps.atPose) was asked for.
	local running: number? = nil
	local function windowNow(): number
		return if running ~= nil then running else currentWindow
	end
	local function cue(kind: string)
		local window = windowNow()
		local row = log.cues[window]
		if row == nil then
			row = {}
			log.cues[window] = row
		end
		if row[kind] == nil then
			row[kind] = shownOn()
		end
	end
	-- The real FrameClock on this loop's render steps: its start (First), its posed mark (after
	-- the rigs' step) and its end (Last), and its watchdog on the Heartbeat.
	local clockStart: ((dt: number) -> ())? = nil
	local clockPosed: ((dt: number) -> ())? = nil
	local clockEnd: ((dt: number) -> ())? = nil
	local clockWatch: ((dt: number) -> ())? = nil
	FrameClock.bind({
		now = function(): number
			return clock
		end,
		onFrameStart = function(fn: any): () -> ()
			clockStart = fn
			return function()
				clockStart = nil
			end
		end,
		onPosed = function(fn: any): () -> ()
			clockPosed = fn
			return function()
				clockPosed = nil
			end
		end,
		onFrameEnd = function(fn: any): () -> ()
			clockEnd = fn
			return function()
				clockEnd = nil
			end
		end,
		onHeartbeat = function(fn: any): () -> ()
			clockWatch = fn
			return function()
				clockWatch = nil
			end
		end,
	} :: any)
	-- Bind its steps now, so its frames are this loop's.
	FrameClock.after(1, function() end)()
	local gate = (FrameClock :: any).atPose
	-- The controller's step right after its contacts (CharacterController.afterContacts).
	local afterContacts: { (dt: number) -> () } = {}
	-- Each rig's animator, as Choreo's forwards to its Mixer (hitStop, pauseRemaining and the
	-- counted holds' heldCount, holdPace and holdSteps, D-354).
	local animators: { [any]: any } = {
		[avatar.model] = {
			hitStop = function(_self: any, frames: number)
				mixer:hitStop(frames)
			end,
			pauseRemaining = function(_self: any): number
				return mixer:pauseRemaining()
			end,
			heldCount = function(_self: any): number
				return mixer:heldCount()
			end,
			holdPace = function(_self: any): number?
				return mixer:holdPace()
			end,
			holdSteps = function(_self: any, steps: number)
				mixer:holdSteps(steps)
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
			heldCount = function(_self: any): number
				return enemyMixer:heldCount()
			end,
			holdPace = function(_self: any): number?
				return enemyMixer:holdPace()
			end,
			holdSteps = function(_self: any, steps: number)
				enemyMixer:holdSteps(steps)
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
		hit = function(info: any, previous: string?): string
			local name = Moments.selectFor(info)
			cue("moment")
			table.insert(
				log.hits,
				{ frame = shownOn(), window = windowNow(), name = name, previous = previous, late = info.late }
			)
			return name
		end,
		ownsHighlight = function(info: any): boolean
			return Moments.byId(Moments.selectFor(info)).highlight ~= nil
		end,
	}
	setmetatable(impact, { __index = recorder() })
	-- With `pictures`, the real director and the real overlay on this loop's clock and render step
	-- (fx.luau renderOrder.impactFrames, after the controller's), and the real flash budget.
	local overlayStep: ((dt: number) -> ())? = nil
	local overlayWatch: ((dt: number) -> ())? = nil
	if opts.pictures then
		ImpactFrames.bind({
			now = function(): number
				return clock
			end,
			onRender = function(step: (dt: number) -> ()): () -> ()
				overlayStep = step
				return function()
					if overlayStep == step then
						overlayStep = nil
					end
				end
			end,
			onHeartbeat = function(step: (dt: number) -> ()): () -> ()
				overlayWatch = step
				return function()
					if overlayWatch == step then
						overlayWatch = nil
					end
				end
			end,
			playerGui = function()
				return Instance.new("Folder")
			end,
			camera = function()
				return nil
			end,
			project = function()
				return nil
			end,
			aspect = function()
				return 16 / 9
			end,
			quality = function()
				return "High"
			end,
			random = Random.new(3),
			pace = (FrameClock :: any).pace,
		} :: any)
		FlashBudget.reset()
		Impact.bind({
			impactFrames = ImpactFrames,
			glint = recorder(),
			slashArc = recorder(),
			speedLines = recorder(),
			trails = recorder(),
			-- The director's own sound, camera and Highlight calls stay out of this run's cue log
			-- (the Replication-side cues below log it).
			sfx = recorder(),
			camera = recorder(),
			outline = recorder(),
			now = function(): number
				return clock
			end,
			viewerPosition = function(): Vector3
				return Vector3.new(0, 5, 10)
			end,
			positionOf = function(): Vector3
				return Vector3.zero
			end,
			delay = function(seconds: number, fn: () -> ())
				table.insert(scheduled, { at = clock + seconds, fn = fn })
			end,
		} :: any)
		impact = setmetatable({
			hit = function(info: any, previous: string?): string
				local name = Impact.hit(info, previous)
				cue("moment")
				table.insert(
					log.hits,
					{ frame = shownOn(), window = windowNow(), name = name, previous = previous, late = info.late }
				)
				return name
			end,
		}, { __index = Impact }) :: any
	end
	local digits = {
		show = function()
			cue("number")
			if log.numbers[windowNow()] == nil then
				log.numbers[windowNow()] = shownOn()
			end
		end,
	}
	local sfx = setmetatable({
		duck = function(db: number)
			if db ~= 0 and log.silence == nil then
				log.silence = frame
			end
		end,
		play = function()
			cue("tick")
		end,
	}, { __index = recorder() })
	local outline = setmetatable({
		flash = function()
			cue("flash")
		end,
	}, { __index = recorder() })
	local camera = setmetatable({}, {
		__index = function(): any
			return function()
				cue("camera")
			end
		end,
	})
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
		outline = outline,
		switchRing = recorder(),
		digits = digits,
		hud = recorder(),
		systemLine = recorder(),
		sfx = sfx,
		impact = impact,
		camera = camera,
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
		-- FrameClock.atPose, telling which window each cue was asked for.
		atPose = if gate ~= nil
			then function(fn: () -> ()): () -> ()
				local window = windowNow()
				return gate(function()
					local was = running
					running = window
					fn()
					running = was
				end)
			end
			else nil,
		onFrame = function(fn: (dt: number) -> ())
			table.insert(afterContacts, fn)
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
	for step = 1, opts.warm or 0 do
		local dt = if opts.renderDt ~= nil then opts.renderDt(step - (opts.warm :: number)) else 1 / fps
		mixer:step(dt)
		enemyMixer:step(dt)
	end
	local handle = mixer:play(clip)
	local startTime = handle.time
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
		local dt = if opts.renderDt ~= nil then opts.renderDt(frame) else 1 / fps
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
		-- The frame's render steps: FrameClock's start, the rigs' (the enemy), FrameClock's posed
		-- mark, the controller's (the local rig, its contacts, then what runs after them).
		phase = "render"
		if clockStart ~= nil then
			clockStart(dt)
		end
		log.targetPaused[frame] = enemyMixer:step(dt).paused
		if clockPosed ~= nil then
			clockPosed(dt)
		end
		local before = handle.time
		local stepped = mixer:step(dt)
		log.paused[frame] = stepped.paused
		log.times[frame] = handle.time
		log.drawn[frame] = log.times[frame - ENGINE_LAG] or startTime
		if frame > 1 and handle.time <= before + 1e-9 and stepped.paused then
			held += dt
		end
		for _, joint in Joints.list(avatar.model) do
			local offset = stepped.offsets[joint.Name]
			joint.Transform = if offset ~= nil then ClipSampler.toCFrame(offset) else CFrame.identity
		end
		local delta = stepped.rootDelta
		avatar.root.CFrame = avatar.root.CFrame + Vector3.new(delta[1], delta[2], delta[3])
		log.roots[frame] = avatar.root.CFrame
		local contacts = predictor:step(handle.time)
		-- The server counts a hit on the frame this client's blade first touches it, on its own
		-- clock: ahead of this client by the hit-stops held so far.
		for _, entry in predictor.pending do
			send(entry.windowIndex, clock - held + latency)
		end
		for _, contact in contacts do
			send(contact.windowIndex, clock - held + latency)
			table.insert(log.contacts, { frame = frame, window = contact.windowIndex, tier = contact.tier })
			local was = currentWindow
			currentWindow = contact.windowIndex
			Replication.contact(contact)
			currentWindow = was
		end
		for _, after in afterContacts do
			after(dt)
		end
		-- The overlay's render step (after the controller's and the camera's), then what it shows.
		if overlayStep ~= nil then
			overlayStep(dt)
		end
		if opts.pictures then
			local look = ImpactFrames.look()
			if look ~= nil then
				log.looks[frame] = look
			end
		end
		if clockEnd ~= nil then
			clockEnd(dt)
		end
		-- The PC's logger, after every render step (Last + 1): does the rig still hold?
		log.flags[frame] = mixer:pauseRemaining() > 0
		-- And what a reader of the hold as drawn asks there (D-353).
		local shown = (mixer :: any).heldShown
		log.shownHeld[frame] = if typeof(shown) == "function" then shown(mixer) else log.flags[frame]
		phase = "after"
		if opts.afterRender then
			deliver()
		end
		local beat = if opts.beatDt ~= nil then opts.beatDt(frame) else dt
		if heartbeat ~= nil then
			heartbeat(beat)
		end
		if clockWatch ~= nil then
			clockWatch(beat)
		end
		if overlayWatch ~= nil then
			overlayWatch(beat)
		end
		if handle.done and #words == 0 and #scheduled == 0 and not ImpactFrames.isShowing() then
			break
		end
	end
	if opts.pictures then
		ImpactFrames.bind(nil)
		FlashBudget.reset()
		Impact.bind({})
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

	it("a hold waiting for its word holds every frame, whatever step the Heartbeat reports", function()
		-- Studio (the PC's recorder dry run): PreSimulation and PostSimulation fire once a rendered
		-- frame, but the simulation steps whole 1/240 s substeps, so a frame's Heartbeat may report
		-- 1/120 s or 1/40 s (in pairs: a 15.8 ms frame that ran 1/120, then a 17.9 ms one that ran
		-- 1/40). Item 255 at 0.25 s of lag on cebade4: Normals froze, let go and froze again;
		-- Finals froze once (their words come in time). Here each pair comes every six frames at
		-- every offset, and a frame that runs one substep (then seven) as well (D-346).
		local enemy, def = place("Kobold", 1.8)
		local cap = Combat.contact.wordHoldSeconds
		local SHORT, LONG = 0.0158, 0.0179
		local stepPairs: { [string]: { number } } = {
			["1/120 then 1/40"] = { 2 / 240, 6 / 240 },
			["1/240 then 7/240"] = { 1 / 240, 7 / 240 },
		}
		-- Every move as a hit, and a kill on a basic's cut and on an Art's last.
		local cases: { { name: string, killAt: number? } } = {}
		for _, name in MOVES do
			table.insert(cases, { name = name })
		end
		table.insert(cases, { name = "Basic1", killAt = 1 })
		table.insert(cases, { name = "SharpNail", killAt = 3 })
		local checked, waited = 0, 0
		for label, steps in stepPairs do
			for offset = 0, 5 do
				local function renderDt(f: number): number
					local k = (f + offset) % 6
					return if k == 0 then SHORT elseif k == 1 then LONG else FRAME
				end
				local function beatDt(f: number): number
					local k = (f + offset) % 6
					return if k == 0 then steps[1] elseif k == 1 then steps[2] else FRAME
				end
				for _, case in cases do
					for _, latency in { 0.1, 0.25 } do
						local log = play(case.name, enemy, def, 60, latency, {
							renderDt = renderDt,
							beatDt = beatDt,
							warm = 40,
							killAt = case.killAt,
						})
						for index, contact in log.contacts do
							local where = ("%s%s %d ms, Heartbeat %s at offset %d, window %d"):format(
								case.name,
								if case.killAt ~= nil then " (a kill)" else "",
								math.floor(latency * 1000 + 0.5),
								label,
								offset,
								contact.window
							)
							local run = runFrom(log, contact.frame)
							local tier = Combat.hitStopFrames[contact.tier]
							if run < tier then
								error(("%s: froze %d frames, its tier is %d"):format(where, run, tier))
							end
							if run > math.max(tier, Combat.hitStopFrames.Kill, math.floor(cap * 60 + 1e-6)) then
								error(("%s: froze %d frames, past the cap"):format(where, run))
							end
							-- One freeze: nothing holds again before the next hit (its contact, or a kill's
							-- word that waited for its key with no contact of its own, D-267).
							local nextContact = log.contacts[index + 1]
							local stop = if nextContact ~= nil then nextContact.frame else log.frames
							for window, frame in log.numbers do
								if window > contact.window then
									stop = math.min(stop, frame - 1)
								end
							end
							for f = contact.frame + run + 1, stop do
								if log.paused[f] then
									error(
										("%s: froze frames %d to %d, let go, and froze again on frame %d"):format(
											where,
											contact.frame + 1,
											contact.frame + run,
											f
										)
									)
								end
							end
							local shown = log.numbers[contact.window]
							if shown == nil then
								error(where .. ": no number")
							end
							-- A word inside the cap shows inside the freeze.
							if latency < cap and shown > contact.frame + run then
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
		expect(checked >= 2 * 6 * #cases * 2).toBe(true)
		expect(waited > 0).toBe(true)
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

-- The pacings a hit's cues are checked at: plain frames, and Studio's (D-346), whose Heartbeat
-- reports whole 1/240 s substeps in pairs (a 15.8 ms frame that ran 1/120, then a 17.9 ms one
-- that ran 1/40).
local PACINGS: { [string]: { renderDt: ((f: number) -> number)?, beatDt: ((f: number) -> number)? } } = {
	plain = {},
	studio = {
		renderDt = function(f: number): number
			local k = f % 6
			return if k == 0 then 0.0158 elseif k == 1 then 0.0179 else FRAME
		end,
		beatDt = function(f: number): number
			local k = f % 6
			return if k == 0 then 2 / 240 elseif k == 1 then 6 / 240 else FRAME
		end,
	},
}

local HitSweep = Harness.load("src/server/combat/HitSweep")
local TRAIL_START, TRAIL_END = HitSweep.trailAttachments(avatar.model)

-- How far the blade tip moves from clip time `from` to `to`, the root carried by the clip's motion.
local function tipTravel(clip: any, from: number, to: number): number
	local start = ClipSampler.rootMotionAt(clip, 0)
	local function tip(time: number): Vector3
		local motion = ClipSampler.rootMotionAt(clip, time)
		local frame = avatar.base * CFrame.new(motion[1] - start[1], motion[2] - start[2], motion[3] - start[3])
		local sample = HitSweep.bladeAt(avatar.model, frame, clip, time, TRAIL_START :: any, TRAIL_END :: any)
		return (sample :: any).finish
	end
	return (tip(to) - tip(from)).Magnitude
end

local function caseName(name: string, fps: number, latency: number, afterRender: boolean, pacing: string): string
	return ("%s %d fps %d ms%s%s"):format(
		name,
		fps,
		math.floor(latency * 1000 + 0.5),
		if afterRender then " (heard after the render step)" else "",
		if pacing == "plain" then "" else " (" .. pacing .. " pacing)"
	)
end

describe("a hit's cues land on the first frame that draws its contact pose (D-342)", function()
	it("the flash, the moment, the camera, the tick and the number never come before it", function()
		local enemy, def = place("Kobold", 1.8)
		local checked = 0
		for _, name in MOVES do
			for _, fps in { 30, 60, 144 } do
				for pacing, pace in PACINGS do
					if pacing ~= "plain" and fps ~= 60 then
						continue
					end
					for _, latency in { 0, 0.05, 0.1, 0.25 } do
						for _, afterRender in { false, true } do
							local log = play(name, enemy, def, fps, latency, {
								afterRender = afterRender,
								renderDt = pace.renderDt,
								beatDt = pace.beatDt,
								warm = if pace.renderDt ~= nil then 40 else nil,
							})
							for _, contact in log.contacts do
								local where = caseName(name, fps, latency, afterRender, pacing)
									.. (", window %d"):format(contact.window)
								local c = contact.frame
								-- The step that touched moved the blade, and the next frame is the first to
								-- draw where it touched; the target holds from that frame on.
								if not (log.times[c] > log.times[c - 1] + 1e-9) then
									error(where .. ": the contact's step did not move the blade")
								end
								if log.drawn[c + 1] ~= log.times[c] or log.drawn[c] == log.times[c] then
									error(
										where .. ": the contact pose is not first drawn on the frame after the contact"
									)
								end
								expect(log.targetPaused[c + 1]).toBe(true)
								local row = log.cues[contact.window] or {}
								local due = c + 1
								for _, kind in { "moment", "camera", "tick" } do
									if row[kind] ~= due then
										error(
											("%s: the %s showed on frame %s, the contact pose on %d"):format(
												where,
												kind,
												tostring(row[kind]),
												due
											)
										)
									end
								end
								-- A basic contact's own white flash (a final hit's and a kill's are the
								-- moment's, after its picture).
								if contact.tier == "Normal" and row.flash ~= due then
									error(
										("%s: the white flash showed on frame %s, the contact pose on %d"):format(
											where,
											tostring(row.flash),
											due
										)
									)
								end
								if row.flash ~= nil and row.flash < due then
									error(("%s: the white flash came before the contact pose"):format(where))
								end
								local number = row.number
								if number == nil or number < due then
									error(("%s: the number showed on frame %s"):format(where, tostring(number)))
								end
								-- A word heard by then shows its number with the hit.
								if latency == 0 and number ~= due then
									error(("%s: the number showed on frame %d, not %d"):format(where, number, due))
								end
								checked += 1
							end
						end
					end
				end
			end
		end
		expect(checked >= #MOVES * (3 * 4 * 2 + 4 * 2)).toBe(true)
	end)

	it("the wait for the word is one freeze, in the hold's flag and on screen, from the contact to the word", function()
		-- PC m2 on 1cf87aa at 0.05 s: the flag stood 3 frames, fell for one, stood 6 more, while the
		-- pose stood still throughout (the Heartbeat's one more step came after the logger).
		local enemy, def = place("Kobold", 1.8)
		local cap = Combat.contact.wordHoldSeconds
		local waited = 0
		for _, name in MOVES do
			for _, fps in { 30, 60, 144 } do
				for pacing, pace in PACINGS do
					if pacing ~= "plain" and fps ~= 60 then
						continue
					end
					for _, latency in { 0.05, 0.1, 0.1 + FRAME, 0.25 } do
						for _, afterRender in { false, true } do
							local log = play(name, enemy, def, fps, latency, {
								afterRender = afterRender,
								renderDt = pace.renderDt,
								beatDt = pace.beatDt,
								warm = if pace.renderDt ~= nil then 40 else nil,
							})
							for _, contact in log.contacts do
								local where = caseName(name, fps, latency, afterRender, pacing)
									.. (", window %d"):format(contact.window)
								local c = contact.frame
								local run = runFrom(log, c)
								local tier = framesAt(Combat.hitStopFrames[contact.tier], fps)
								if run > tier then
									waited += 1
								end
								-- The flag stands from the contact's step to the last frozen step's eve.
								for f = c, c + run - 1 do
									if not log.flags[f] then
										error(
											("%s: the hold's flag fell on frame %d inside the freeze (%d to %d)"):format(
												where,
												f,
												c + 1,
												c + run
											)
										)
									end
								end
								if log.flags[c + run] then
									error(("%s: the flag stood past the freeze"):format(where))
								end
								-- The screen holds the contact pose from the frame after the contact to the
								-- one after the last frozen step.
								for f = c + 1, c + run + ENGINE_LAG do
									if log.drawn[f] ~= log.times[c] then
										error(("%s: frame %d did not draw the contact pose"):format(where, f))
									end
								end
								-- The number of a word inside the cap shows on a frozen frame.
								local number = log.numbers[contact.window]
								if latency < cap and (number == nil or number > c + run + ENGINE_LAG) then
									error(
										("%s: the number showed on frame %s, the screen held %d to %d"):format(
											where,
											tostring(number),
											c + 1,
											c + run + ENGINE_LAG
										)
									)
								end
							end
						end
					end
				end
			end
		end
		expect(waited > 0).toBe(true)
	end)

	it(
		"a kill heard on the frame after its contact plays whole on the contact pose: no white before its picture (D-349)",
		function()
			-- PC m1 on 1cf87aa, no lag: the white flash showed on the contact frame and the next, the
			-- kill's picture on the next (its word came a frame after the contact); the basic contact
			-- could not prove the kill (D-313's margin). Here the word comes 3 frames after the server
			-- counted the touch, the frame after the client's contact on the strike key.
			local enemy, def = place("Kobold", 1.8)
			local kills = 0
			for _, name in { "Basic1", "Basic2", "SharpNail" } do
				for _, afterRender in { false, true } do
					local latency = if afterRender then 2 * FRAME else 3 * FRAME
					local log = play(name, enemy, def, 60, latency, { killAt = 1, afterRender = afterRender })
					local contact = log.contacts[1]
					local where = caseName(name, 60, latency, afterRender, "plain")
					if contact == nil or contact.window ~= 1 then
						error(where .. ": no contact on the first window")
					end
					do
						kills += 1
						local row = log.cues[1] or {}
						if row.flash ~= nil then
							error(("%s: a white flash on frame %d before the kill's picture"):format(where, row.flash))
						end
						local hits: { Hit } = {}
						for _, hit in log.hits do
							if hit.window == 1 then
								table.insert(hits, hit)
							end
						end
						if #hits ~= 1 or hits[1].name ~= "Kill" or hits[1].previous ~= nil then
							error(
								("%s: window 1 played %d moments, the first %s after %s"):format(
									where,
									#hits,
									if hits[1] ~= nil then hits[1].name else "none",
									if hits[1] ~= nil then tostring(hits[1].previous) else "none"
								)
							)
						end
						expect(hits[1].frame).toBe(contact.frame + 1)
						expect(log.numbers[1]).toBe(contact.frame + 1)
					end
				end
			end
			expect(kills).toBe(6)
		end
	)

	it("a kill word past the cap plays late: no re-freeze, its number and death, no picture (D-348)", function()
		local enemy, def = place("Kobold", 1.8)
		for _, fps in { 30, 60, 144 } do
			for _, latency in { 0.1, 0.25 } do
				local log = play("Basic1", enemy, def, fps, latency, { killAt = 1 })
				local where = caseName("Basic1", fps, latency, false, "plain")
				local contact = log.contacts[1]
				local run = runFrom(log, contact.frame)
				local kill: Hit? = nil
				for _, hit in log.hits do
					if hit.window == 1 and hit.name == "Kill" then
						kill = hit
					end
				end
				if kill == nil then
					error(where .. ": no kill played")
				end
				-- While the hold is on the kill upgrades it in place and draws the picture; once it let
				-- go (past the cap) the bodies moved on, and the kill shows its sound, flash, number
				-- and death but no picture.
				local late = (log.numbers[1] :: number) > contact.frame + run
				-- (At 30 fps a 0.25 s word still lands on the cap's last frozen step.)
				if fps >= 60 then
					expect(late).toBe(latency > Combat.contact.wordHoldSeconds)
				end
				if (kill :: Hit).late ~= late then
					error(("%s: the kill's late is %s"):format(where, tostring((kill :: Hit).late)))
				end
				-- A late word always finds its contact's moment played (in time, it may take it over).
				if late then
					expect((kill :: Hit).previous).toBe("BasicHit")
				end
				expect(log.numbers[1] ~= nil).toBe(true)
				expect(log.death ~= nil).toBe(true)
				for f = contact.frame + run + 1, log.frames do
					if log.paused[f] then
						error(("%s: frame %d froze again"):format(where, f))
					end
				end
				-- The step after the freeze is no pop: the clip goes on from the contact (past the part
				-- of its own hold after the key that the freeze absorbed, D-154, which holds still),
				-- and the blade moves about as far as the swing's own fastest frame after the key
				-- (PC m1: 1.0 stud at r6 at 0.1 s; Basic1's follow-through is 0, 0.23, then 0.86 studs
				-- a 60 fps frame after its key).
				local c = contact.frame
				local clip = Harness.load("src/shared/clips/player/OneHandedSword/Basic1")
				local released = tipTravel(clip, log.times[c], log.times[c + run + 1])
				local fastest = 0
				local t = log.times[c]
				while t < log.times[c] + 0.3 do
					fastest = math.max(fastest, tipTravel(clip, t, t + 1 / fps))
					t += 1 / 240
				end
				-- (Measured: 0.99 against 0.96 at 60 fps, 1.12 against 1.15 at 30: the frame after the
				-- release carries the absorbed hold's end and the follow-through's fastest frame.)
				if released > 1.1 * fastest then
					error(
						("%s: the blade jumped %.2f studs on release; the swing's fastest frame is %.2f"):format(
							where,
							released,
							fastest
						)
					)
				end
			end
		end
	end)
	-- A stronger tier's word heard late inside the wait (a Kill at 0.12 to 0.2 s) starts its picture
	-- when the freeze it joins is nearly done: the bodies would move on under its last frames (on
	-- the HM tree at 60 fps, 1 to 4 of the Kill's 6; at 144, up to 13 of 15). The anime holds its
	-- ink frames on the struck pose: the word holds the bodies over its picture (D-350), every
	-- frame of it drawn on the contact pose, one freeze, let go on the frame after the picture.
	-- Through the real director and overlay (ImpactFrames counts its looks at the screen's pace).
	it("a kill heard late inside the wait draws its whole picture on the struck pose (D-350)", function()
		local enemy, def = place("Kobold", 1.8)
		local IMPACT_LOOKS = Harness.load("src/shared/data/impact").looks
		local checked = 0
		for _, case in { { "Basic1", 1 }, { "Basic2", 1 }, { "SharpNail", 1 }, { "RisingArc", 2 } } do
			local name, killAt = case[1] :: string, case[2] :: number
			for _, fps in { 30, 60, 144 } do
				for _, latency in { 0.05, 0.1, 0.12, 0.15, 0.18, 0.2 } do
					for _, afterRender in { false, true } do
						local log = play(
							name,
							enemy,
							def,
							fps,
							latency,
							{ killAt = killAt, afterRender = afterRender, pictures = true }
						)
						local where = caseName(name, fps, latency, afterRender, "plain")
						local contact: Contact? = nil
						for _, entry in log.contacts do
							if entry.window == killAt then
								contact = entry
							end
						end
						local kill: Hit? = nil
						for _, hit in log.hits do
							if hit.window == killAt and hit.name == "Kill" then
								kill = hit
							end
						end
						if kill == nil then
							error(where .. ": no kill played")
						end
						-- No contact: the word came first and played whole at the key (D-267, its own
						-- hold from there); past the cap: no picture (D-348).
						if contact == nil or (kill :: Hit).late then
							continue
						end
						checked += 1
						local c = (contact :: Contact).frame
						local pose = log.times[c]
						local first, last = nil, nil
						for f = c, log.frames do
							local look = log.looks[f]
							if look ~= nil and IMPACT_LOOKS[look] ~= nil then
								first = first or f
								last = f
								if log.drawn[f] ~= pose then
									error(
										("%s: the %s look on frame %d drew a body that moved on (the contact on %d, the kill's word on %d)"):format(
											where,
											look,
											f,
											c,
											(kill :: Hit).frame
										)
									)
								end
							end
						end
						if first == nil then
							error(where .. ": the kill showed no picture")
						end
						-- One freeze: the flag never comes back once it fell.
						local fell: number? = nil
						for f = c, log.frames do
							if not log.flags[f] then
								fell = fell or f
							elseif fell ~= nil then
								error(("%s: froze again on frame %d after letting go on %d"):format(where, f, fell))
							end
						end
						-- Let go on the frame after the picture, or where the hold lets go without one
						-- (the Kill hold from the contact, D-313, or the wait for the word, D-312) if later.
						local function stillTo(run: Log): number
							local f = c
							while run.drawn[f + 1] == run.times[c] do
								f += 1
							end
							return f
						end
						local bare =
							play(name, enemy, def, fps, latency, { killAt = killAt, afterRender = afterRender })
						local want = math.max(last :: number, stillTo(bare))
						if stillTo(log) ~= want then
							error(
								("%s: held still to frame %d, the picture ended on %d and the hold without it on %d (contact %d, kill %d)"):format(
									where,
									stillTo(log),
									last :: number,
									stillTo(bare),
									c,
									(kill :: Hit).frame
								)
							)
						end
					end
				end
			end
		end
		expect(checked).toBeGreaterThan(100)
	end)
end)

-- The blade tip a frame draws (its pose written ENGINE_LAG steps before, on that step's root).
local function drawnTip(log: Log, clip: any, f: number): Vector3?
	local time = log.drawn[f]
	local root = log.roots[f - ENGINE_LAG]
	if time == nil or root == nil then
		return nil
	end
	local sample = HitSweep.bladeAt(avatar.model, root, clip, time, TRAIL_START :: any, TRAIL_END :: any)
	return if sample ~= nil then (sample :: any).finish else nil
end

-- Studio's pacing at 60 Hz: render frames of 15.8 to 17.9 ms and a Heartbeat of whole 1/240 s
-- substeps (2, 6, then 4); at 144 Hz render frames of 1/144 s and substeps of 1, 2, 2.
local function studioRender(fps: number): (f: number) -> number
	if fps == 60 then
		return function(f: number): number
			local k = f % 6
			return if k == 0 then 0.0158 elseif k == 1 then 0.0179 else FRAME
		end
	end
	return function(): number
		return 1 / fps
	end
end
local function studioBeat(fps: number): (f: number) -> number
	if fps == 60 then
		return function(f: number): number
			local k = f % 6
			return if k == 0 then 2 / 240 elseif k == 1 then 6 / 240 else FRAME
		end
	end
	return function(f: number): number
		return if f % 3 == 0 then 1 / 240 else 2 / 240
	end
end

describe("a hold reads as held on the frames that draw it held (D-353, 288(b))", function()
	-- The PC read Choreo isPaused after every render step (Last + 1) and logged the blade moving on
	-- a hold's first two flagged frames: Finals 0.35 to 0.56 studs a frame, a Final in M3 4.7 then
	-- 2.1 to 2.7. The flag rises on the contact's own step, whose picture still shows the step
	-- before, so it leads the hold as drawn by impact.poseLagFrames: before D-353 a flagged frame
	-- here moved 4.52 studs (Horizontal at 60 Hz), 2.24 (Basic3), 4.26 (Sharp Nail), 5.64 (Rising
	-- Arc). Mixer:heldShown() says whether this frame draws the pose the frame before drew.
	local STILL = 1e-3 -- studs: a drawn blade that moved less than this between two frames is still
	for _, name in { "Basic3", "Horizontal", "SharpNail", "RisingArc" } do
		it(name .. ": heldShown is true exactly on the frames whose drawn blade is still", function()
			local enemy, def = place("Kobold", 1.8)
			local clip = Harness.load("src/shared/clips/player/OneHandedSword/" .. name)
			local checked = 0
			for _, fps in { 60, 144 } do
				for _, pacing in { "plain", "studio" } do
					for _, latency in { 0, 0.1 } do
						local options: any = {}
						if pacing == "studio" then
							options.renderDt = studioRender(fps)
							options.beatDt = studioBeat(fps)
							options.warm = 40
						end
						local log = play(name, enemy, def, fps, latency, options)
						for _, contact in log.contacts do
							local c = contact.frame
							local run = runFrom(log, c)
							for f = c - 1, c + run + 2 do
								local a, b = drawnTip(log, clip, f - 1), drawnTip(log, clip, f)
								if a == nil or b == nil then
									continue
								end
								local moved = ((b :: Vector3) - (a :: Vector3)).Magnitude
								local shown = log.shownHeld[f] == true
								if shown ~= (moved < STILL) then
									error(
										("%s, window %d (contact frame %d, hold %d): frame %s reads %s but its blade moved %.2f studs"):format(
											caseName(name, fps, latency, false, pacing),
											contact.window,
											c,
											run,
											if f == c then "c" elseif f < c then "c-1" else "c+" .. tostring(f - c),
											if shown then "held" else "moving",
											moved
										),
										0
									)
								end
								checked += 1
							end
						end
					end
				end
			end
			expect(checked).toBeGreaterThan(0)
		end)
	end
end)

-- A kill's word inside the hold at 30 fps (D-354). On the hit-moment tree a kill whose word came
-- 0.1 to 0.15 s after the contact froze 6 frames, not the Kill tier's 5 (framesAt(10, 30)): the
-- upgrade took what the hold had shown as the seconds the Normal asked (0.05) less what was left,
-- not the 2 frames (0.067 s) a 30 fps rig rounds that Normal up to (D-271), so the rest came out
-- 1/60 s long and the tie rule added a frame. The D-313 grid checks 60 and 144 fps only, where
-- the count is exact.
describe("a kill's word inside the hold at 30 fps freezes the Kill tier (D-354, D-313)", function()
	it("freezes exactly the Kill tier's frames from the contact, one freeze", function()
		local enemy, def = place("Kobold", 1.8)
		local kills = 0
		for _, name in { "Basic1", "Basic2", "SharpNail", "RisingArc" } do
			for _, latency in { 0.05, 0.1, 0.1 + FRAME, 0.12, 0.15 } do
				for _, setting in { { false, 0 }, { true, 0 }, { false, 40 }, { true, 40 } } do
					local afterRender, warm = setting[1] :: boolean, setting[2] :: number
					local killAt = if name == "RisingArc" then 2 else 1
					-- From the rig's first steps (its holds reckoned on the steps it has), and on a
					-- rig that has its pace (D-327: its holds counted in frames).
					local log = play(name, enemy, def, 30, latency, {
						killAt = killAt,
						afterRender = afterRender,
						warm = if warm > 0 then warm else nil,
					})
					local contact = nil
					for _, entry in log.contacts do
						if entry.window == killAt then
							contact = entry
						end
					end
					if contact == nil then
						-- The word came before the key (D-267): it plays whole there.
						continue
					end
					local late = false
					local wordFrame: number? = nil
					for _, hit in log.hits do
						if hit.window == killAt and hit.late then
							late = true
						end
						if hit.window == killAt and hit.name == "Kill" then
							wordFrame = hit.frame
						end
					end
					if late then
						-- Past the cap: no re-freeze (D-348), covered above.
						continue
					end
					kills += 1
					local where = ("%s 30 fps %d ms%s%s"):format(
						name,
						math.floor(latency * 1000 + 0.5),
						if afterRender then " (heard after the render step)" else "",
						if warm > 0 then " on a paced rig" else ""
					)
					local run = runFrom(log, contact.frame)
					-- The wait for the word may hold longer than the tier, never the upgrade's
					-- arithmetic: a word heard inside the tier freezes the tier.
					local want = math.max(
						framesAt(Combat.hitStopFrames.Kill, 30),
						if wordFrame ~= nil then (wordFrame :: number) - contact.frame - 1 else 0
					)
					if run ~= want then
						error(("%s: the kill froze %d frames from the contact, not %d"):format(where, run, want), 0)
					end
					for f = contact.frame + run + 1, log.frames do
						if log.paused[f] then
							error(("%s: frame %d froze again"):format(where, f), 0)
						end
					end
				end
			end
		end
		expect(kills >= 16).toBe(true)
	end)
end)

-- A kill's picture is drawn over still bodies to its last frame (D-354, D-350). holdOverPicture
-- turned the frames the Kill's picture still hides into seconds at FrameClock.pace (the median
-- frame) and asked the rig's Mixer for them; a rig counts its steps at its own pace (the mean of
-- its steps, D-327), so under uneven frames (a 45 fps cap alternating 1/60 and 2/60 s, or hitches
-- of 2 and 3 frames) the hold ran out before the picture's frames did. Before D-354 through this
-- path: the Ink look on Basic1's frame 15 at 200 ms (alt45, the word heard after the render step)
-- drew a body that had moved on.
local JITTER: { [string]: { renderDt: (f: number) -> number, beatDt: (f: number) -> number } } = {
	alt45 = {
		renderDt = function(f: number): number
			return if f % 2 == 0 then FRAME else 2 * FRAME
		end,
		beatDt = function(f: number): number
			return if f % 2 == 0 then FRAME else 2 * FRAME
		end,
	},
	alt45b = {
		renderDt = function(f: number): number
			return if f % 2 == 0 then 2 * FRAME else FRAME
		end,
		beatDt = function(f: number): number
			return if f % 2 == 0 then 2 * FRAME else FRAME
		end,
	},
	hitchy = {
		renderDt = function(f: number): number
			local k = f % 5
			return if k == 0 then 3 * FRAME elseif k == 3 then 2 * FRAME else FRAME
		end,
		beatDt = function(f: number): number
			local k = f % 5
			return if k == 0 then 3 * FRAME elseif k == 3 then 2 * FRAME else FRAME
		end,
	},
}

describe("a kill's picture is drawn over still bodies under uneven frames (D-354, D-350)", function()
	it("every frame of the Kill's picture shows the contact's still pose", function()
		local enemy, def = place("Kobold", 1.8)
		local looks = Harness.load("src/shared/data/impact").looks
		local total = 0
		for pacingName, pacing in JITTER do
			for _, case in { { "Basic1", 1 }, { "Basic2", 1 }, { "SharpNail", 1 }, { "RisingArc", 2 } } do
				local name, killAt = case[1] :: string, case[2] :: number
				for _, latency in { 0.05, 0.1, 0.15, 0.2 } do
					for _, afterRender in { false, true } do
						local log = play(name, enemy, def, 60, latency, {
							killAt = killAt,
							afterRender = afterRender,
							pictures = true,
							renderDt = pacing.renderDt,
							beatDt = pacing.beatDt,
							warm = 40,
						})
						local contact = nil
						for _, entry in log.contacts do
							if entry.window == killAt then
								contact = entry
							end
						end
						local kill = nil
						for _, hit in log.hits do
							if hit.window == killAt and hit.name == "Kill" then
								kill = hit
							end
						end
						if contact == nil or kill == nil or kill.late then
							continue
						end
						total += 1
						local pose = log.times[contact.frame]
						for f = contact.frame, log.frames do
							local look = log.looks[f]
							if look ~= nil and looks[look] ~= nil and log.drawn[f] ~= pose then
								error(
									("%s %s %d ms%s: contact %d, kill word %d, the %s look on frame %d draws a body that moved on"):format(
										pacingName,
										name,
										math.floor(latency * 1000 + 0.5),
										if afterRender then " (heard after the render step)" else "",
										contact.frame,
										kill.frame,
										look,
										f
									),
									0
								)
							end
						end
					end
				end
			end
		end
		expect(total).toBeGreaterThan(0)
	end)
end)

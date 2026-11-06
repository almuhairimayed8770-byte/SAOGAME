--!strict
--[[
	The hold on a hit, through the real path (issues 4 and 6): Sharp Nail's first cut kills a Frenzy
	Boar. The review saw the swing stand still about 23 frames and then snap 2 jump in one frame:
	the hit-stop started at the server's confirmation (frames after the blade got there) and
	stacked on the clip's own authored hold after the snap.

	Here the local fighter is the hit matrix's body (the engine-style R15 with its sword), posed
	each 60 fps frame from a real Mixer as Choreo poses it, its root carried by the clip's root
	motion; the boar is a RigBuilder rig at real-fight range. Each frame runs as the character
	controller's render step does: the rig's step, the root motion, then ContactPredictor sweeps the
	blade it shows, and a touch goes to the real Replication.contact (whose animator is that Mixer).
	The server's HitConfirmed arrives a few frames after the contact, as a round trip brings it.
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
local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
local Mixer = Harness.load("src/client/choreo/Mixer")
local ContactPredictor = Harness.load("src/client/controllers/ContactPredictor")
local Replication = Harness.load("src/client/controllers/Replication")

local FRAME = 1 / 60
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
local SHARP = Harness.load("src/shared/clips/player/OneHandedSword/SharpNail")
local ART = Arts.byId("OneHandedSword.SharpNail")
local BOAR = Enemies.byId("FrenzyBoar")

-- The boar's rig in its rest pose `distance` in front of the player, side on (HitMatrix's BoarSide).
local function placeBoar(distance: number): any
	local setup = nil
	for _, candidate in Dev.hitMatrix.setups do
		if candidate.id == "BoarSide" then
			setup = candidate
		end
	end
	assert(setup ~= nil, "no BoarSide setup")
	local rig = Rigs[BOAR.skin]
	local model = RigBuilder.build(BOAR.skin)
	local height = PlaygroundLayout.rootHeight(rig.hipHeight, model.PrimaryPart.Size.Y, World.spawn.groundEpsilon)
	local frame = avatar.base
		* CFrame.new(0, height - avatar.rootHeight, -distance)
		* CFrame.Angles(0, math.pi + math.rad(setup.yaw), 0)
	for name, solved in Pose.solve(model, frame, {}) do
		local part = model:FindFirstChild(name)
		if part ~= nil and part:IsA("BasePart") then
			part.CFrame = solved
		end
	end
	return model
end

local function recorder(calls: { any }, name: string): any
	return setmetatable({}, {
		__index = function(_self: any, key: string): any
			return function(...: any): any
				table.insert(calls, { module = name, fn = key, args = { ... } })
				return nil
			end
		end,
	})
end

type Run = {
	-- Per rendered frame: the clip time it shows, the blade tip, and what happened.
	times: { number },
	tips: { Vector3 },
	contactFrame: number?,
	contacts: { any },
	calls: { any },
	mixer: any,
}

-- Plays Sharp Nail from its start at 60 fps on the hit matrix's body against the boar (HP `hp`),
-- the server's confirmation (`serverTier`, a kill) arriving `confirmFrames` after the contact.
local function play(hp: number, serverTier: string, confirmFrames: number, distance: number?): Run
	local boar = placeBoar(distance or 3.5)
	local calls: { any } = {}
	local clock = 100
	local mixer = Mixer.new()
	local boarMixer = Mixer.new()
	local animators: { [any]: any } = {
		[avatar.model] = {
			hitStop = function(_self: any, frames: number)
				table.insert(calls, { module = "animator:me", fn = "hitStop", args = { frames } })
				mixer:hitStop(frames)
			end,
			pauseRemaining = function(_self: any): number
				return mixer:pauseRemaining()
			end,
			play = function() end,
		},
		[boar] = {
			hitStop = function(_self: any, frames: number)
				table.insert(calls, { module = "animator:boar", fn = "hitStop", args = { frames } })
				boarMixer:hitStop(frames)
			end,
			play = function() end,
		},
	}
	local scaled = Enemies.scaled(BOAR)
	local records: { [number]: any } = {
		[1] = { id = 1, model = avatar.model, kind = "Player", state = "Art", weaponId = WEAPON.id },
		[5] = {
			id = 5,
			model = boar,
			kind = "Enemy",
			state = "Idle",
			defId = BOAR.id,
			hp = hp,
			maxHp = scaled.hp,
			elite = false,
			rig = BOAR.skin,
		},
	}
	local impact = recorder(calls, "impact")
	local impactAnswers = {
		hit = function(info: any, previous: string?): string
			table.insert(calls, { module = "impact", fn = "hit", args = { info, previous } })
			return Moments.selectFor(info)
		end,
		ownsHighlight = function(info: any): boolean
			return Moments.byId(Moments.selectFor(info)).highlight ~= nil
		end,
	}
	setmetatable(impactAnswers, { __index = impact })
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
		locomotion = recorder(calls, "locomotion"),
		choreo = {
			get = function(model: any): any
				return animators[model]
			end,
		},
		clipLibrary = recorder(calls, "clipLibrary"),
		trails = recorder(calls, "trails"),
		smear = recorder(calls, "smear"),
		shatter = recorder(calls, "shatter"),
		sparks = recorder(calls, "sparks"),
		telegraphs = recorder(calls, "telegraphs"),
		outline = recorder(calls, "outline"),
		switchRing = recorder(calls, "switchRing"),
		digits = recorder(calls, "digits"),
		hud = recorder(calls, "hud"),
		systemLine = recorder(calls, "systemLine"),
		sfx = recorder(calls, "sfx"),
		impact = impactAnswers,
		camera = recorder(calls, "camera"),
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
	} :: any)

	local predictor = ContactPredictor.new({
		targets = function(): { any }
			return { records[1], records[5] }
		end,
		confirmed = Replication.confirmedAlready,
	})
	avatar.root.CFrame = avatar.base
	local handle = mixer:play(SHARP)
	assert(
		predictor:begin({
			model = avatar.model,
			clip = SHARP,
			artId = ART.id,
			finalHit = true,
			multiplier = ART.multiplier,
			weaponAttack = WEAPON.attack,
		}),
		"the predictor refused the swing"
	)
	local chain = BladeContact.chain(avatar.model) :: any
	local run: Run = { times = {}, tips = {}, contactFrame = nil, contacts = {}, calls = calls, mixer = mixer }
	local confirmed = false
	for frame = 1, 75 do
		clock += FRAME
		-- The server's word arrives between frames.
		local contactFrame = run.contactFrame
		if not confirmed and contactFrame ~= nil and frame == contactFrame + confirmFrames then
			confirmed = true
			if serverTier == "Kill" then
				-- The tracker's State and HP attributes come with it: the boar is down.
				records[5].state = "Dead"
				records[5].hp = 0
			end
			Replication.dispatch("HitConfirmed", {
				attackerId = 1,
				targetId = 5,
				damage = 9,
				crit = false,
				gaugeDamage = 0,
				killed = serverTier == "Kill",
				broke = false,
				hitStop = serverTier,
				position = { 0, 3, -3 },
				parried = false,
				guarded = false,
				reflected = false,
				artId = ART.id,
				hitIndex = 1,
			})
		end
		-- The rig's step (Choreo writes each joint's Transform), then the root motion.
		local result = mixer:step(FRAME)
		boarMixer:step(FRAME)
		for _, joint in Joints.list(avatar.model) do
			local offset = result.offsets[joint.Name]
			joint.Transform = if offset ~= nil then ClipSampler.toCFrame(offset) else CFrame.identity
		end
		local delta = result.rootDelta
		avatar.root.CFrame = avatar.root.CFrame + Vector3.new(delta[1], delta[2], delta[3])
		-- The controller's sweep of the pose this frame shows.
		for _, contact in predictor:step(handle.time) do
			table.insert(run.contacts, contact)
			if Replication.contact(contact) and run.contactFrame == nil then
				run.contactFrame = frame
			end
		end
		table.insert(run.times, handle.time)
		local _, tip = BladeContact.blade(chain, BladeContact.read(chain))
		table.insert(run.tips, tip)
	end
	predictor:stop()
	avatar.root.CFrame = avatar.base
	return run
end

-- The runs of rendered frames that show the blade where the frame before showed it, as
-- { first frame, length }.
local function stills(run: Run): { { number } }
	local runs = {}
	local current: { number }? = nil
	for frame = 2, #run.tips do
		if (run.tips[frame] - run.tips[frame - 1]).Magnitude < 1e-4 then
			if current == nil then
				current = { frame, 0 }
				table.insert(runs, current :: { number })
			end
			(current :: { number })[2] += 1
		else
			current = nil
		end
	end
	return runs
end

local WINDOWS = ClipSampler.hitWindows(SHARP)
-- Where snap 1's authored hold ends (the still beat a whiff shows after the cut).
local HOLD_END = SHARP.keys[ClipSampler.strikeHoldAfter(SHARP, WINDOWS[1].open) :: number].time

-- The lengths of the still runs that start after frame `after` at clip times in [from, before).
local function stillsIn(run: Run, after: number, from: number, before: number): { number }
	local lengths = {}
	for _, entry in stills(run) do
		local time = run.times[entry[1]]
		if entry[1] > after and time >= from - 1e-9 and time < before then
			table.insert(lengths, entry[2])
		end
	end
	return lengths
end

-- The hit's holds: the still runs after the contact, up to where snap 1's own hold ends.
local function holdsBeforeSnap2(run: Run): { number }
	return stillsIn(run, run.contactFrame :: number, 0, HOLD_END)
end

-- The largest share of snap 2's tip travel one rendered frame shows.
local function snap2Worst(run: Run): number
	local from, to = 0.58, 0.63
	local steps = {}
	local total = 0
	for frame = 2, #run.tips do
		local a, b = run.times[frame - 1], run.times[frame]
		if b > from and a < to then
			local step = (run.tips[frame] - run.tips[frame - 1]).Magnitude
			table.insert(steps, step)
			total += step
		end
	end
	local worst = 0
	for _, step in steps do
		worst = math.max(worst, step / total)
	end
	return worst
end

local function count(run: Run, moduleName: string, fn: string): { any }
	local found = {}
	for _, call in run.calls do
		if call.module == moduleName and call.fn == fn then
			table.insert(found, call)
		end
	end
	return found
end

describe("The hold on a kill through the real path (issue 6)", function()
	it("a kill the replicated HP proves holds 10 frames from the frame after contact, once", function()
		-- 1 HP: the first cut cannot leave the boar standing.
		local run = play(1, "Kill", 6)
		expect(run.contactFrame).never.toBeNil()
		expect(#run.contacts).toBe(1)
		expect(run.contacts[1].tier).toBe("Kill")
		expect(run.contacts[1].windowIndex).toBe(1)
		-- The contact frame shows the blade arriving; the rig holds from the next frame for the
		-- Kill's 10 frames, then moves on: no second hold before snap 2.
		expect(holdsBeforeSnap2(run)).toEqual({ Combat.hitStopFrames.Kill })
		local first = stills(run)[1]
		expect(first[1]).toBe((run.contactFrame :: number) + 1)
		-- The confirmation 6 frames on stops nothing again and replays nothing.
		expect(#count(run, "animator:me", "hitStop")).toBe(1)
		expect(#count(run, "impact", "hit")).toBe(1)
		expect(#count(run, "digits", "show")).toBe(1)
		-- Snap 2 reads over its frames: no frame shows most of it.
		expect(snap2Worst(run) <= 0.6).toBe(true)
	end)

	it("a kill the HP cannot prove: the contact's 3 frames run on to 10 when the word comes in time", function()
		local scaled = Enemies.scaled(BOAR)
		local least = ContactPredictor.leastDamage(
			{ kind = "Enemy", defId = BOAR.id, elite = false },
			WEAPON.attack,
			ART.multiplier
		) :: number
		-- HP the cut takes exactly: a kill on the server, not provable here (rounding, regen).
		local run = play(least, "Kill", 2)
		expect(least < scaled.hp).toBe(true)
		expect(run.contacts[1].tier).toBe("Normal")
		expect(holdsBeforeSnap2(run)).toEqual({ Combat.hitStopFrames.Kill })
		expect(#count(run, "animator:me", "hitStop")).toBe(2)
		-- The Kill's cue, picture, cut and punch come with the word, after the contact's moment.
		local hits = count(run, "impact", "hit")
		expect(#hits).toBe(2)
		expect(hits[2].args[2]).toBe("Hit")
		expect(hits[2].args[1].killed).toBe(true)
	end)

	it("a word that comes after the contact's hold let go never stops the swing a second time", function()
		local scaled = Enemies.scaled(BOAR)
		local run = play(scaled.hp * 0.5, "Kill", 6)
		expect(run.contacts[1].tier).toBe("Normal")
		expect(holdsBeforeSnap2(run)).toEqual({ Combat.hitStopFrames.Normal })
		expect(#count(run, "animator:me", "hitStop")).toBe(1)
		expect(snap2Worst(run) <= 0.6).toBe(true)
	end)

	it("the whole hit, contact to snap 2, stands still no longer than its hold", function()
		-- The review counted about 23 still frames. A whiff stands still for snap 1's authored hold
		-- (and whatever its settle shows); a kill on the first cut for the Kill's 10 frames in its
		-- place: the hit-stop is the hold, never the two in a row.
		local whiff = play(1, "Kill", 6, 40)
		expect(whiff.contactFrame).toBeNil()
		local function sum(list: { number }): number
			local total = 0
			for _, length in list do
				total += length
			end
			return total
		end
		local authored = sum(stillsIn(whiff, 0, WINDOWS[1].open, HOLD_END))
		expect(authored >= 2).toBe(true)
		local run = play(1, "Kill", 6)
		expect(sum(holdsBeforeSnap2(run))).toBe(Combat.hitStopFrames.Kill)
		-- And snap 2 comes that much sooner after the contact than hold, authored hold and all.
		local reached: number? = nil
		for frame, time in run.times do
			if reached == nil and time >= WINDOWS[2].open then
				reached = frame
			end
		end
		local whiffReached: number? = nil
		for frame, time in whiff.times do
			if whiffReached == nil and time >= WINDOWS[2].open then
				whiffReached = frame
			end
		end
		expect((reached :: number) - (whiffReached :: number)).toBe(Combat.hitStopFrames.Kill - authored)
	end)
end)

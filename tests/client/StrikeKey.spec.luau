--!strict
--[[
	The hit lands on the strike's key (fix F1) and holds exactly its count (fix F6), through the
	real path: a Mixer poses the hit matrix's body each frame as Choreo does (joint Transforms, the
	root carried by the clip's root motion), ContactPredictor sweeps the blade it shows, and a touch
	goes to the real Replication.contact, whose hold stops that Mixer.

	F1: every window opens on its snap's first frame (D-043), so a target inside the start pose's
	blade, or one the first expo-out step reaches, was touched while the frame still showed the
	blade before the cut; the hold then froze the start pose (the review saw "sword raised, pause,
	pop"). Here the targets stand point-blank and at the shoulder, and the swing runs at 30, 60 and
	144 fps: no contact plays on a frame before its strike's key, and a touch kept for the key plays
	on the first frame that shows it.

	F6: a rendered frame a hair shorter than 1/60 left a sliver of pause that froze one more frame
	(7 on a Final, 4 on a Normal in about a third of casts at 5% frame-time jitter). Here the frame
	times jitter by up to 8% and every hold still counts exactly its frames.
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
local ReviewMarkers = Harness.load("src/client/dev/ReviewMarkers")

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

local MOVES = { "Horizontal", "Vertical", "RisingArc", "SharpNail", "Basic1", "Basic2", "Basic3" }

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

type Contact = { window: number, frame: number, time: number, before: number, still: number, tier: string }

-- Plays one move from its start through the real path at frame times from `nextDt`, against the
-- enemy; returns its contacts: the window, the frame that played it, the clip time that frame and
-- the frame before showed, the still frames right after it, and its tier.
local function play(name: string, enemy: any, def: any, nextDt: () -> number): { Contact }
	local clip = Harness.load("src/shared/clips/player/OneHandedSword/" .. name)
	local art = if name:sub(1, 5) == "Basic" then nil else Arts.byId("OneHandedSword." .. name)
	local chainIndex = if art == nil then tonumber(name:sub(6)) :: number else 0
	local clock = 100
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
	local handle = mixer:play(clip)
	assert(predictor:begin({
		model = avatar.model,
		clip = clip,
		artId = if art ~= nil then art.id else nil,
		finalHit = art ~= nil or chainIndex >= Combat.basicChainLength,
		multiplier = if art ~= nil then art.multiplier else Combat.basicAttackMultiplier,
		weaponAttack = WEAPON.attack,
	}))
	local chain = BladeContact.chain(avatar.model) :: any
	local times, tips = {}, {}
	local found: { { window: number, frame: number, tier: string } } = {}
	local frame = 0
	while not handle.done and frame < 400 do
		frame += 1
		local dt = nextDt()
		clock += dt
		local result = mixer:step(dt)
		enemyMixer:step(dt)
		for _, joint in Joints.list(avatar.model) do
			local offset = result.offsets[joint.Name]
			joint.Transform = if offset ~= nil then ClipSampler.toCFrame(offset) else CFrame.identity
		end
		local delta = result.rootDelta
		avatar.root.CFrame = avatar.root.CFrame + Vector3.new(delta[1], delta[2], delta[3])
		for _, contact in predictor:step(handle.time) do
			if Replication.contact(contact) then
				table.insert(found, { window = contact.windowIndex, frame = frame, tier = contact.tier })
			end
		end
		table.insert(times, handle.time)
		local _, tip = BladeContact.blade(chain, BladeContact.read(chain))
		table.insert(tips, tip)
	end
	predictor:stop()
	avatar.root.CFrame = avatar.base
	local contacts: { Contact } = {}
	for _, entry in found do
		local still = 0
		for g = entry.frame + 1, #tips do
			if (tips[g] - tips[g - 1]).Magnitude < 1e-4 then
				still += 1
			else
				break
			end
		end
		table.insert(contacts, {
			window = entry.window,
			frame = entry.frame,
			time = times[entry.frame],
			before = if entry.frame > 1 then times[entry.frame - 1] else 0,
			still = still,
			tier = entry.tier,
		})
	end
	return contacts
end

local function steady(fps: number): () -> number
	return function(): number
		return 1 / fps
	end
end

-- Placements where the start pose's blade or the snap's first step reaches the body: root
-- distances from the bodies touching (Kobold 1.28, BoarSide 1.78) to a stud and a half past it.
local PLACEMENTS = {
	{ setup = "Kobold", distance = 1.8, bearing = 0 },
	{ setup = "Kobold", distance = 2.8, bearing = 0 },
	{ setup = "Kobold", distance = 2.6, bearing = 55 },
	{ setup = "BoarSide", distance = 2.3, bearing = -55 },
	{ setup = "BoarSide", distance = 2.3, bearing = 0 },
}

describe("a hit lands on its strike's key (F1)", function()
	it("no contact plays before its strike's key, ahead or at the shoulder, at 30, 60 and 144 fps", function()
		local played = 0
		for _, placement in PLACEMENTS do
			local enemy, def = place(placement.setup, placement.distance, placement.bearing)
			for _, name in MOVES do
				local clip = Harness.load("src/shared/clips/player/OneHandedSword/" .. name)
				local windows = ClipSampler.hitWindows(clip)
				local snaps = ReviewMarkers.strikeSnaps(clip)
				for _, fps in { 30, 60, 144 } do
					for _, contact in play(name, enemy, def, steady(fps)) do
						played += 1
						local key = snaps[contact.window].finish
						expect(windows[contact.window].open < key).toBe(true)
						if contact.time < key - 1e-4 then
							error(
								("%s %s@%.1f bearing %d, %d fps: window %d played at clip %.4f, its key is %.4f"):format(
									name,
									placement.setup,
									placement.distance,
									placement.bearing,
									fps,
									contact.window,
									contact.time,
									key
								)
							)
						end
					end
				end
			end
		end
		-- The placements are close: nearly every window of every move touches.
		expect(played > #PLACEMENTS * #MOVES * 3).toBe(true)
	end)

	it("a touch at the start pose plays on the first frame that shows the key, and holds the key pose", function()
		-- The kobold half a stud from the body: every move's first window touches at once.
		local enemy, def = place("Kobold", 1.8, 0)
		for _, name in MOVES do
			local clip = Harness.load("src/shared/clips/player/OneHandedSword/" .. name)
			local key = ReviewMarkers.strikeSnaps(clip)[1].finish
			local contacts = play(name, enemy, def, steady(60))
			expect(#contacts > 0).toBe(true)
			local first = contacts[1]
			expect(first.window).toBe(1)
			-- On the key's frame: this frame shows the key, the one before it the cut still running.
			expect(math.abs(first.time - key) < 1e-4).toBe(true)
			expect(first.before < key - 1e-4).toBe(true)
			-- Then the hold, at its tier's count, on the key pose.
			expect(first.still).toBe(Combat.hitStopFrames[first.tier])
		end
	end)

	it("the strike's key of each window is its snap's landing; a window with no snap keys at its open", function()
		local sharp = Harness.load("src/shared/clips/player/OneHandedSword/SharpNail")
		local windows = ClipSampler.hitWindows(sharp)
		expect(ContactPredictor.strikeKey(sharp, windows[1])).toBe(0.3833)
		expect(ContactPredictor.strikeKey(sharp, windows[2])).toBe(0.63)
		expect(ContactPredictor.strikeKey(sharp, windows[3])).toBe(0.9)
		local window = { open = 1.2, close = 1.3 }
		expect(ContactPredictor.strikeKey(sharp, window)).toBe(1.2)
	end)
end)

describe("a hold counts exactly its frames (F6)", function()
	it("Normal holds 3 frames and Final 6 when 60 fps frame times jitter by up to 8%", function()
		local enemy, def = place("Kobold", 3.5, 0)
		local rng = Random.new(20261025)
		local function jittered(): number
			return (1 / 60) * (1 + (rng:NextNumber() * 2 - 1) * 0.08)
		end
		local counted: { [string]: { [number]: number } } = {}
		for _ = 1, 30 do
			for _, name in { "Horizontal", "SharpNail", "Basic1", "Basic3" } do
				for _, contact in play(name, enemy, def, jittered) do
					local byTier = counted[contact.tier] or {}
					byTier[contact.still] = (byTier[contact.still] or 0) + 1
					counted[contact.tier] = byTier
				end
			end
		end
		for tier, byCount in counted do
			for still, times in byCount do
				if still ~= Combat.hitStopFrames[tier] then
					error(
						("%s held %d frames on %d hits (it holds %d)"):format(
							tier,
							still,
							times,
							Combat.hitStopFrames[tier]
						)
					)
				end
			end
		end
		expect(counted.Normal ~= nil and counted.Final ~= nil).toBe(true)
	end)
end)

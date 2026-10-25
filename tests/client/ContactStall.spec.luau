--!strict
--[[
	The local hit's contact and its confirmation across holds and stalls (issues 4 and 6).

	- A confirmation's stronger tier runs on only the hold its own contact put on the rig: once a
	  later strike's hold has started on the local rig (the contact's own hold over by then), the
	  word for the earlier hit stretches nothing.
	- An engine hitch between the contact and its confirmation counts as at most a jump
	  (choreo.luau stall.jumpSeconds) toward combat.luau contact.confirmSeconds, so the word still
	  finds its contact and plays nothing twice, whichever of the network and the Heartbeat comes
	  first in the wake's frame. Steady play ages it on the clock as before.
	- A render stall's wake frame re-baselines ContactPredictor: the blade is not swept across the
	  gap (the poses a second apart say nothing of where it went), so no contact is predicted on a
	  path the rig never showed; the server's word plays such a hit whole.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Combat = Harness.load("src/shared/data/combat")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Dev = Harness.load("src/shared/data/dev")
local Enemies = Harness.load("src/shared/data/enemies")
local Weapons = Harness.load("src/shared/data/weapons")
local Arts = Harness.load("src/shared/data/arts")
local Rigs = Harness.load("src/shared/data/rigs")
local World = Harness.load("src/shared/data/world")
local Playground = Harness.load("src/shared/data/playground")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")
local Joints = Harness.load("src/shared/choreo/Joints")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
local Mixer = Harness.load("src/client/choreo/Mixer")
local ContactPredictor = Harness.load("src/client/controllers/ContactPredictor")
local Replication = Harness.load("src/client/controllers/Replication")

local FRAME = 1 / 60
local ART = "OneHandedSword.SharpNail"

-- ------------------------------------------------------------------ Replication on fake rigs

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

type Fixture = {
	calls: { any },
	me: any, -- the local fighter's Mixer
	-- One rendered frame: the clock moves a frame, the Heartbeat (when bound) fires, the rigs step.
	frames: (count: number) -> (),
	-- An engine hitch: the clock moves and nothing runs.
	hitch: (seconds: number) -> (),
	-- The Heartbeat alone (the wake's, when it comes before the network).
	heartbeat: () -> (),
	contact: (targetId: number, windowIndex: number, tier: string) -> (),
	confirm: (targetId: number, windowIndex: number, tier: string) -> (),
	count: (moduleName: string, fn: string) -> number,
}

local function fixture(options: { heartbeat: boolean? }?): Fixture
	local opts = options or {}
	local calls: { any } = {}
	local clock = 200
	local mixers: { [any]: any } = {}
	local animators: { [any]: any } = {}
	local records: { [number]: any } = {}
	for _, entry in { { 1, "Player" }, { 5, "Enemy" }, { 6, "Enemy" } } do
		local id, kind = entry[1], entry[2]
		local model = Instance.new("Model")
		model.Name = kind .. id
		local mixer = Mixer.new()
		mixers[id] = mixer
		local label = if id == 1 then "animator:me" else "animator:" .. id
		animators[model] = setmetatable({
			hitStop = function(_self: any, frames: number)
				table.insert(calls, { module = label, fn = "hitStop", args = { frames } })
				mixer:hitStop(frames)
			end,
			pauseRemaining = function(_self: any): number
				return mixer:pauseRemaining()
			end,
		}, {
			__index = function(): any
				return function() end
			end,
		})
		records[id] = {
			id = id,
			model = model,
			kind = kind,
			state = "Idle",
			defId = if kind == "Enemy" then "FrenzyBoar" else nil,
			weaponId = if kind == "Player" then Playground.loadout.weapon else nil,
			hp = 100,
			maxHp = 100,
		}
	end
	local beats: { (dt: number) -> () } = {}
	local deps: { [string]: any } = {
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
		impact = setmetatable({
			hit = function(info: any, previous: string?): string
				table.insert(calls, { module = "impact", fn = "hit", args = { info, previous } })
				return "Hit"
			end,
			ownsHighlight = function(): boolean
				return false
			end,
		}, { __index = recorder(calls, "impact") }),
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
	}
	if opts.heartbeat then
		deps.onHeartbeat = function(fn: (dt: number) -> ())
			table.insert(beats, fn)
		end
	end
	Replication.bind(deps :: any)
	local function beat()
		for _, fn in beats do
			fn(FRAME)
		end
	end
	return {
		calls = calls,
		me = mixers[1],
		frames = function(count: number)
			for _ = 1, count do
				clock += FRAME
				beat()
				for _, mixer in mixers do
					mixer:step(FRAME)
				end
			end
		end,
		hitch = function(seconds: number)
			clock += seconds
		end,
		heartbeat = beat,
		contact = function(targetId: number, windowIndex: number, tier: string)
			assert(
				Replication.contact({
					targetId = targetId,
					windowIndex = windowIndex,
					artId = ART,
					tier = tier,
					killed = tier == "Kill",
					position = Vector3.new(0, 3, -3),
				}),
				"the contact played nothing"
			)
		end,
		confirm = function(targetId: number, windowIndex: number, tier: string)
			Replication.dispatch("HitConfirmed", {
				attackerId = 1,
				targetId = targetId,
				damage = 9,
				crit = false,
				gaugeDamage = 0,
				killed = tier == "Kill",
				broke = false,
				hitStop = tier,
				position = { 0, 3, -3 },
				parried = false,
				guarded = false,
				reflected = false,
				artId = ART,
				hitIndex = windowIndex,
			})
		end,
		count = function(moduleName: string, fn: string): number
			local total = 0
			for _, call in calls do
				if call.module == moduleName and call.fn == fn then
					total += 1
				end
			end
			return total
		end,
	}
end

local function frames(count: number): number
	return count * ChoreoData.frameSeconds
end

describe("A confirmation's stronger tier and the hold on the local rig", function()
	it("never stretches a later strike's hold once the contact's own hold is over", function()
		local f = fixture()
		f.contact(5, 1, "Normal")
		f.frames(10)
		expect(f.me:pauseRemaining()).toBe(0)
		-- The next cut lands: its own hold runs (its frames less the shave that keeps a short
		-- frame from freezing one more, F6).
		f.contact(5, 2, "Normal")
		f.frames(1)
		local left = f.me:pauseRemaining()
		expect(left).toBeCloseTo(frames(Combat.hitStopFrames.Normal - Combat.hitStopShaveFrames - 1), 1e-9)
		-- The word for the first cut: a kill. Its moment still plays what the Kill adds...
		f.confirm(5, 1, "Kill")
		expect(f.count("impact", "hit")).toBe(3)
		-- ...but the second cut's hold runs its own length, no longer.
		expect(f.me:pauseRemaining()).toBeCloseTo(left, 1e-9)
		expect(f.count("animator:me", "hitStop")).toBe(2)
	end)

	it("still runs the contact's own hold on to the stronger tier from the contact (guard)", function()
		local f = fixture()
		f.contact(5, 1, "Normal")
		f.frames(1)
		f.confirm(5, 1, "Kill")
		expect(f.me:pauseRemaining()).toBeCloseTo(
			frames(Combat.hitStopFrames.Kill - Combat.hitStopShaveFrames - 1),
			1e-9
		)
		expect(f.count("animator:5", "hitStop")).toBe(2)
	end)

	it("runs it on when the same cut's second target joined the hold (guard)", function()
		local f = fixture()
		f.contact(5, 1, "Normal")
		f.contact(6, 1, "Normal")
		f.frames(1)
		f.confirm(5, 1, "Kill")
		expect(f.me:pauseRemaining()).toBeCloseTo(
			frames(Combat.hitStopFrames.Kill - Combat.hitStopShaveFrames - 1),
			1e-9
		)
	end)

	it("never stretches the hold of a hit the local fighter took after the contact's hold", function()
		local f = fixture()
		f.contact(5, 1, "Normal")
		f.frames(5)
		-- The boar's blow lands on the local fighter: its own hold on the rig.
		Replication.dispatch("HitConfirmed", {
			attackerId = 6,
			targetId = 1,
			damage = 4,
			crit = false,
			gaugeDamage = 0,
			killed = false,
			broke = false,
			hitStop = "Normal",
			position = { 0, 3, 0 },
			parried = false,
			guarded = false,
			reflected = false,
			hitIndex = 1,
		})
		local left = f.me:pauseRemaining()
		f.confirm(5, 1, "Kill")
		expect(f.me:pauseRemaining()).toBeCloseTo(left, 1e-9)
	end)
end)

describe("A confirmation across an engine hitch", function()
	for _, order in { "network first", "Heartbeat first" } do
		it(("finds its contact after a 1.2 s hitch (%s): nothing plays twice"):format(order), function()
			local f = fixture({ heartbeat = true })
			f.frames(3)
			f.contact(5, 1, "Normal")
			f.frames(2)
			f.hitch(1.2)
			if order == "Heartbeat first" then
				f.heartbeat()
			end
			f.confirm(5, 1, "Normal")
			expect(f.count("impact", "hit")).toBe(1)
			expect(f.count("animator:me", "hitStop")).toBe(1)
			expect(f.count("digits", "show")).toBe(1)
			-- It answered its contact: the predictor is not told it came first.
			expect(Replication.confirmedAlready(5, 1, ART)).toBe(false)
		end)
	end

	it("keeps a word that came before the blade across a hitch: the late contact is skipped", function()
		local f = fixture({ heartbeat = true })
		f.frames(3)
		f.confirm(5, 1, "Normal")
		f.hitch(1.2)
		expect(Replication.confirmedAlready(5, 1, ART)).toBe(true)
	end)

	it("in steady play a word later than contact.confirmSeconds still plays the hit whole (guard)", function()
		local f = fixture({ heartbeat = true })
		f.frames(3)
		f.contact(5, 1, "Normal")
		f.frames(math.ceil((Combat.contact.confirmSeconds + 0.2) / FRAME))
		f.confirm(5, 1, "Normal")
		expect(f.count("impact", "hit")).toBe(2)
	end)

	it("without a Heartbeat bound the clock alone ages it, as before (guard)", function()
		local f = fixture()
		f.contact(5, 1, "Normal")
		f.frames(2)
		f.hitch(1.2)
		f.confirm(5, 1, "Normal")
		expect(f.count("impact", "hit")).toBe(2)
	end)
end)

-- ------------------------------------------------------------------ ContactPredictor on real rigs

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
local BOAR = Enemies.byId("FrenzyBoar")

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

local function poseAt(clip: any, time: number)
	local offsets = ClipSampler.sample(clip, time)
	for _, joint in Joints.list(avatar.model) do
		local offset = offsets[joint.Name]
		joint.Transform = if offset ~= nil then ClipSampler.toCFrame(offset) else CFrame.identity
	end
	local start = ClipSampler.rootMotionAt(clip, 0)
	local now = ClipSampler.rootMotionAt(clip, time)
	avatar.root.CFrame = avatar.base * CFrame.new(now[1] - start[1], now[2] - start[2], now[3] - start[3])
end

describe("ContactPredictor across a render stall's jump", function()
	local boar = placeBoar(3.5)
	local targets = {
		{ id = 5, model = boar, kind = "Enemy", state = "Idle", defId = BOAR.id, hp = 1e6, maxHp = 1e6 },
	}
	local art = Arts.byId(ART)
	local function predictor(): any
		local made = ContactPredictor.new({
			targets = function(): { any }
				return targets
			end,
		})
		assert(
			made:begin({
				model = avatar.model,
				clip = SHARP,
				artId = ART,
				finalHit = true,
				multiplier = art.multiplier,
				weaponAttack = WEAPON.attack,
			}),
			"begin refused"
		)
		return made
	end
	-- Steps a fresh predictor at clip time 0, then at `wake` (the jump's frame, flagged or not).
	local function jumpTo(wake: number, jumped: boolean?): (any, { any })
		local made = predictor()
		poseAt(SHARP, 0)
		made:step(0)
		poseAt(SHARP, wake)
		return made, made:step(wake, jumped)
	end
	local windows = ClipSampler.hitWindows(SHARP)

	it("predicts nothing on the wake frame of a jump: the gap's path is not swept", function()
		-- A wake inside a later window whose unflagged sweep from the stall's start would predict.
		local wake: number? = nil
		local t = windows[1].close + FRAME
		while t < SHARP.duration and wake == nil do
			local _, found = jumpTo(t)
			if #found > 0 then
				wake = t
			end
			t += FRAME
		end
		expect(wake).never.toBeNil()
		local _, found = jumpTo(wake :: number, true)
		expect(#found).toBe(0)
	end)

	it("sweeps on from the wake's pose: the next frame is what an unbroken run from there sees", function()
		for index = 1, #windows do
			local wake = windows[index].open + 0.25 * (windows[index].close - windows[index].open)
			local jumpedPredictor = jumpTo(wake, true)
			local fresh = predictor()
			poseAt(SHARP, wake)
			fresh:step(wake)
			local nextTime = wake + FRAME
			poseAt(SHARP, nextTime)
			local after = jumpedPredictor:step(nextTime)
			local reference = fresh:step(nextTime)
			expect(#after).toBe(#reference)
			for k, contact in after do
				expect(contact.windowIndex).toBe(reference[k].windowIndex)
				expect((contact.position - reference[k].position).Magnitude < 1e-9).toBe(true)
			end
		end
	end)

	it("an unflagged step sweeps as before (guard)", function()
		local made = predictor()
		poseAt(SHARP, 0)
		made:step(0)
		local found = 0
		local time = 0
		while time < SHARP.duration do
			time += FRAME
			poseAt(SHARP, time)
			found += #made:step(time, false)
		end
		expect(found >= 1).toBe(true)
	end)
end)

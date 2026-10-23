--!strict
-- The impact director (fx/Impact.luau) against recording fakes: which moment each hit is, what
-- each moment fires, who sees it (involved, a bystander in range, past the range), the 3D accents
-- waiting for the impact frames, the swing tangent's fallbacks, the activation riser's timing from
-- a clip (remote on the hold, local from the release), the dodge's local-only speed lines, the
-- death contour, and a missing or broken dependency logging once.
local Impact = Harness.load("src/client/fx/Impact")
local ActionLogic = Harness.load("src/client/controllers/ActionLogic")
local moments = Harness.load("src/shared/data/moments")
local combat = Harness.load("src/shared/data/combat")
local accents = Harness.load("src/shared/data/accents")

local TILT = accents.slashArc.tilt

local TOKEN = "TrailCyanWhite"
local HIT_POINT = Vector3.new(0, 3, -4)

type Call = { fn: string, args: { any } }

-- A fake world: every dependency records its calls; positions, the swing, the camera and the
-- clock are fields a test sets.
local function newWorld(): any
	local world: any = {
		calls = {} :: { Call },
		swing = nil :: Vector3?,
		viewer = Vector3.new(0, 5, 8) :: Vector3?,
		right = Vector3.new(1, 0, 0) :: Vector3?,
		clock = 12.5,
		hidden = 0, -- what ImpactFrames.hiddenSeconds answers
		hiddenAfterPlay = 0, -- what it answers once impactFrames.play has run
		scheduled = {} :: { { seconds: number, fn: () -> () } },
		positions = {} :: { [any]: Vector3 },
		clips = {} :: { [string]: any },
		attacker = { name = "attacker" },
		target = { name = "target" },
		partner = { name = "partner" },
	}
	local function log(fn: string): (...any) -> ()
		return function(...: any)
			table.insert(world.calls, { fn = fn, args = table.pack(...) })
		end
	end
	world.positions[world.attacker] = Vector3.new(0, 3, 0)
	world.positions[world.target] = Vector3.new(0, 3, -6)
	world.positions[world.partner] = Vector3.new(4, 3, -2)
	world.deps = {
		impactFrames = {
			play = function(...: any): number
				log("impactFrames.play")(...)
				world.hidden = world.hiddenAfterPlay
				return 0.1
			end,
			hiddenSeconds = function(): number
				return world.hidden
			end,
		},
		glint = { play = log("glint.play") },
		slashArc = { play = log("slashArc.play"), line = log("slashArc.line") },
		speedLines = { play = log("speedLines.play") },
		trails = {
			swingDirection = function(model: any): Vector3?
				log("trails.swingDirection")(model)
				return world.swing
			end,
			flashWhite = log("trails.flashWhite"),
		},
		sfx = {
			cue = log("sfx.cue"),
			contour = log("sfx.contour"),
			play = log("sfx.play"),
			playEndingAt = log("sfx.playEndingAt"),
		},
		camera = { punch = log("camera.punch") },
		outline = { flash = log("outline.flash") },
		clipLibrary = {
			get = function(id: string): any
				local clip = world.clips[id]
				if clip == nil then
					error("unknown clip " .. id)
				end
				return clip
			end,
		},
		now = function(): number
			return world.clock
		end,
		viewerPosition = function(): Vector3?
			return world.viewer
		end,
		cameraRight = function(): Vector3?
			return world.right
		end,
		screenDirection = function(position: Vector3, direction: Vector3): Vector2?
			log("screenDirection")(position, direction)
			return Vector2.new(0.8, -0.6)
		end,
		positionOf = function(model: any): Vector3?
			return world.positions[model]
		end,
		delay = function(seconds: number, fn: () -> ())
			table.insert(world.scheduled, { seconds = seconds, fn = fn })
		end,
	}
	return world
end

-- Runs what the director scheduled, in order; returns the delays it asked for. The waits are
-- over, so the impact frames are down by then, unless `stillHidden` says a picture still hides
-- the world for that long.
local function flush(world: any, stillHidden: number?): { number }
	local delays = {}
	local list = world.scheduled
	world.scheduled = {}
	world.hidden = stillHidden or 0
	for _, item in list do
		table.insert(delays, item.seconds)
		item.fn()
	end
	return delays
end

local function bind(world: any): any
	Impact.bind(world.deps)
	return world
end

-- A hit with every flag off: a basic hit by the local player.
local function hitInfo(world: any, changes: { [string]: any }?): any
	local info: any = {
		tier = "Normal",
		position = HIT_POINT,
		attacker = world.attacker,
		target = world.target,
		involved = true,
		localAttacker = true,
		trailToken = TOKEN,
		parried = false,
		guarded = false,
		crit = false,
		isSwitch = false,
		killed = false,
		partner = nil,
	}
	for key, value in changes or {} do
		info[key] = value
	end
	return info
end

local function callsTo(world: any, fn: string): { { any } }
	local found = {}
	for _, call in world.calls do
		if call.fn == fn then
			table.insert(found, call.args)
		end
	end
	return found
end

local function only(world: any, fn: string): { any }
	local found = callsTo(world, fn)
	if #found ~= 1 then
		error(("expected one %s call, got %d"):format(fn, #found), 2)
	end
	return found[1]
end

local function none(world: any, fn: string)
	local found = callsTo(world, fn)
	if #found ~= 0 then
		error(("expected no %s call, got %d"):format(fn, #found), 2)
	end
end

local function expectVector(actual: any, expected: Vector3)
	expect(typeof(actual)).toBe("Vector3")
	expect((actual - expected).Magnitude).toBeLessThan(1e-6)
end

-- Vector3 is single precision: a turned normal is near, not on, its double-precision answer.
local function expectNear(actual: any, expected: Vector3)
	expect(typeof(actual)).toBe("Vector3")
	expect((actual - expected).Magnitude).toBeLessThan(1e-5)
end

-- Degrees between a crescent's face (either side of its plane) and the direction to the camera.
local function faceOff(normal: Vector3, toCamera: Vector3): number
	return math.deg(math.acos(math.clamp(math.abs(normal.Unit:Dot(toCamera.Unit)), 0, 1)))
end

-- Warnings the harness captured since `from` (Harness.warnings() keeps the whole run's).
local function warningsSince(from: number, needle: string): number
	local count = 0
	local all = Harness.warnings()
	for index = from + 1, #all do
		if string.find(all[index], needle, 1, true) then
			count += 1
		end
	end
	return count
end

describe("Impact moment selection", function()
	it("picks each moment in the moments.luau priority order", function()
		local world = bind(newWorld())
		local cases = {
			{ { parried = true, guarded = true, killed = true, tier = "Kill" }, "Parry" },
			-- A blow through a guard that kills is a kill: frames, cut and punch, not a block.
			{ { guarded = true, killed = true, tier = "Kill", crit = true }, "Kill" },
			{ { guarded = true, tier = "Kill" }, "Kill" },
			{ { killed = true, tier = "Final", crit = true, isSwitch = true }, "Kill" },
			{ { tier = "Kill" }, "Kill" },
			{ { guarded = true, tier = "Final", art = true }, "Guarded" },
			{ { tier = "Final", art = true, crit = true, isSwitch = true }, "FinalHit" },
			-- A basic chain's last swing rides the Final hit-stop but stays a basic hit.
			{ { tier = "Final", crit = true }, "Crit" },
			{ { tier = "Final", isSwitch = true }, "Switch" },
			{ { tier = "Final" }, "Hit" },
			{ { crit = true, isSwitch = true }, "Crit" },
			{ { isSwitch = true }, "Switch" },
			-- A player's basic swing: BasicHit, the third swing's Final hit-stop too, unless a
			-- parry, a kill, a guard or a crit claims it first.
			{ { art = false }, "BasicHit" },
			{ { art = false, tier = "Final" }, "BasicHit" },
			{ { art = false, parried = true }, "Parry" },
			{ { art = false, killed = true, tier = "Kill" }, "Kill" },
			{ { art = false, guarded = true }, "Guarded" },
			{ { art = false, crit = true, tier = "Final" }, "Crit" },
			-- An enemy's strike (art nil) and an Art's non-final hit stay Hit.
			{ { tier = "Normal", art = true }, "Hit" },
			{ {}, "Hit" },
		}
		for _, case in cases do
			expect(Impact.select(hitInfo(world, case[1]))).toBe(case[2])
		end
		expect(Impact.hit(hitInfo(world, { tier = "Final", art = true }))).toBe("FinalHit")
	end)

	it("a basic chain's last swing gets the basic hit's treatment, never the Art's", function()
		local world = bind(newWorld())
		world.swing = Vector3.new(1, 0, 0)
		expect(Impact.hit(hitInfo(world, { tier = "Final", art = false }))).toBe("BasicHit")
		expect(only(world, "glint.play")[2]).toBe("Small")
		-- Its own 4-layer hit, the crack and the body down (sfx HitBasic).
		local cue = only(world, "sfx.cue")
		expect(cue[1]).toBe("HitBasic")
		expectVector(cue[2], HIT_POINT)
		for _, fn in { "impactFrames.play", "sfx.contour", "camera.punch", "slashArc.play", "slashArc.line" } do
			none(world, fn)
		end
		-- Replication's white flash stays.
		none(world, "outline.flash")
		expect(Impact.ownsHighlight(hitInfo(world, { tier = "Final", art = false }))).toBe(false)
	end)

	it("an enemy's strike (no Art, no basic swing) plays the plain hit", function()
		local world = bind(newWorld())
		expect(Impact.hit(hitInfo(world, { art = nil, localAttacker = false }))).toBe("Hit")
		expect(only(world, "sfx.cue")[1]).toBe("HitNormal")
		expect(only(world, "glint.play")[2]).toBe("Small")
	end)
end)

describe("Impact.hit, involved", function()
	it("a basic hit: the small glint and the HitNormal cue at the hit, nothing full screen", function()
		local world = bind(newWorld())
		Impact.hit(hitInfo(world))
		local glint = only(world, "glint.play")
		expectVector(glint[1], HIT_POINT)
		expect(glint[2]).toBe("Small")
		expect(glint[3]).toBeNil()
		local cue = only(world, "sfx.cue")
		expect(cue[1]).toBe("HitNormal")
		expectVector(cue[2], HIT_POINT)
		for _, fn in { "impactFrames.play", "sfx.contour", "camera.punch", "slashArc.play", "slashArc.line" } do
			none(world, fn)
		end
		none(world, "outline.flash")
		expect(Impact.ownsHighlight(hitInfo(world))).toBe(false)
	end)

	it("a crit: the medium glint and HitCrit", function()
		local world = bind(newWorld())
		Impact.hit(hitInfo(world, { crit = true }))
		expect(only(world, "glint.play")[2]).toBe("Medium")
		expect(only(world, "sfx.cue")[1]).toBe("HitCrit")
	end)

	it("a guarded hit: the small glint dimmed toward ink and the block cue", function()
		local world = bind(newWorld())
		Impact.hit(hitInfo(world, { guarded = true }))
		local glint = only(world, "glint.play")
		expect(glint[2]).toBe("Small")
		expect(glint[3]).toBe("OutlineInk")
		expect(only(world, "sfx.cue")[1]).toBe("Block")
		none(world, "impactFrames.play")
	end)

	it("an Art's final hit fires the whole row in the Art's color, and the white hit flash", function()
		local world = bind(newWorld())
		world.swing = Vector3.new(1, 0, 0)
		Impact.hit(hitInfo(world, { tier = "Final", art = true }))

		local glint = only(world, "glint.play")
		expect(glint[2]).toBe("Large")
		expect(glint[3]).toBe(TOKEN)

		local arc = only(world, "slashArc.play")
		expectVector(arc[1], HIT_POINT)
		expectVector(arc[2], Vector3.new(1, 0, 0))
		-- The true swing plane: radius (0, 0, -1) x tangent (1, 0, 0) = (0, -1, 0), a flat swing
		-- whose crescent bulges away from the attacker (tangent x normal = the radius). The camera
		-- (0, 5, 8) looks at it nearly edge-on, so it turns about the tangent toward the camera by
		-- the cap.
		local turn = math.rad(TILT.maxDegrees)
		expectNear(arc[3], Vector3.new(0, -math.cos(turn), -math.sin(turn)))
		-- It still bulges away from the attacker, now leaning toward the camera.
		local outward = (arc[2] :: Vector3):Cross(arc[3] :: Vector3)
		expect(outward:Dot(Vector3.new(0, 0, -1))).toBeCloseTo(math.cos(turn), 1e-5)
		expect(faceOff(arc[3], Vector3.new(0, 5, 8) - HIT_POINT)).toBeLessThan(90 - TILT.maxDegrees + 1)
		expect(arc[4]).toBe(TOKEN)
		expect(arc[5]).toBe("Medium")
		local line = only(world, "slashArc.line")
		expectVector(line[2], Vector3.new(1, 0, 0))
		expect(line[3]).toBe("Medium")

		local frames = only(world, "impactFrames.play")
		expect(frames[1]).toBe("Final")
		expect(#frames[2]).toBe(2)
		expect(frames[2][1]).toBe(world.attacker)
		expect(frames[2][2]).toBe(world.target)
		local opts = frames[3]
		expect(opts.now).toBe(12.5)
		-- Vector2 is single precision.
		expect(opts.slashDirection.X).toBeCloseTo(0.8, 1e-6)
		expect(opts.slashDirection.Y).toBeCloseTo(-0.6, 1e-6)
		-- The strokes' direction is the same tangent, projected through the camera at the hit.
		local projected = only(world, "screenDirection")
		expectVector(projected[1], HIT_POINT)
		expectVector(projected[2], Vector3.new(1, 0, 0))

		expect(only(world, "sfx.cue")[1]).toBe("HitFinal")
		expect(only(world, "sfx.contour")[1]).toBe("FinalHit")
		expect(only(world, "camera.punch")[1]).toBe("Final")
		-- Section 10 beat 4: the target's Highlight flashes white for 2 frames.
		local flash = only(world, "outline.flash")
		expect(flash[1]).toBe(world.target)
		expect(flash[2]).toBe("SystemWhite")
		expect(flash[3]).toBe(combat.highlightFlashFrames)
		expect(Impact.ownsHighlight(hitInfo(world, { tier = "Final", art = true }))).toBe(true)
	end)

	it("a kill: the biggest accents untinted, the Kill frames, the bass cut and the Kill punch", function()
		local world = bind(newWorld())
		world.swing = Vector3.new(0, 0, -1)
		Impact.hit(hitInfo(world, { tier = "Kill", killed = true }))
		local glint = only(world, "glint.play")
		expect(glint[2]).toBe("Large")
		expect(glint[3]).toBeNil()
		expect(only(world, "slashArc.play")[5]).toBe("Large")
		expect(only(world, "slashArc.line")[3]).toBe("Large")
		expect(only(world, "impactFrames.play")[1]).toBe("Kill")
		expect(only(world, "sfx.cue")[1]).toBe("HitKill")
		expect(only(world, "sfx.contour")[1]).toBe("KillCut")
		expect(only(world, "camera.punch")[1]).toBe("Kill")
		-- The kill takes the white flash over, so it can wait for the impact frames.
		local flash = only(world, "outline.flash")
		expect(flash[2]).toBe("SystemWhite")
		expect(flash[3]).toBe(combat.highlightFlashFrames)
		expect(Impact.ownsHighlight(hitInfo(world, { killed = true }))).toBe(true)
	end)

	it("a parry: the parry glint, one inverted frame, the parry cue and its ring; no crescent", function()
		local world = bind(newWorld())
		Impact.hit(hitInfo(world, { parried = true }))
		expect(only(world, "glint.play")[2]).toBe("Parry")
		expect(only(world, "impactFrames.play")[1]).toBe("Parry")
		expect(only(world, "sfx.cue")[1]).toBe("Parry")
		expect(only(world, "sfx.contour")[1]).toBe("ParryRing")
		none(world, "slashArc.play")
		none(world, "slashArc.line")
		none(world, "camera.punch")
	end)

	it("a Switch: the medium glint, both blades' trails flash white and the land sound plays", function()
		local world = bind(newWorld())
		Impact.hit(hitInfo(world, { isSwitch = true, partner = world.partner }))
		expect(only(world, "glint.play")[2]).toBe("Medium")
		local flashes = callsTo(world, "trails.flashWhite")
		expect(#flashes).toBe(2)
		expect(flashes[1][1]).toBe(world.attacker)
		expect(flashes[2][1]).toBe(world.partner)
		expect(flashes[1][2]).toBe(combat.highlightFlashFrames)
		local sound = only(world, "sfx.play")
		expect(sound[1]).toBe("ui.SwitchLand")
		expect(only(world, "sfx.cue")[1]).toBe("HitNormal")
	end)

	it("a Switch that is also an Art's final hit plays the final hit and still flashes both trails", function()
		local world = bind(newWorld())
		expect(Impact.hit(hitInfo(world, { tier = "Final", art = true, isSwitch = true, partner = world.partner }))).toBe(
			"FinalHit"
		)
		expect(#callsTo(world, "trails.flashWhite")).toBe(2)
		expect(only(world, "sfx.play")[1]).toBe("ui.SwitchLand")
		expect(only(world, "impactFrames.play")[1]).toBe("Final")
	end)
end)

describe("Impact.hit, bystanders", function()
	it("a bystander in range sees the accents but gets no impact frames, contour or punch", function()
		local world = bind(newWorld())
		world.swing = Vector3.new(1, 0, 0)
		world.viewer = HIT_POINT + Vector3.new(0, 0, moments.rangeOf("FinalHit") - 1)
		Impact.hit(hitInfo(world, { tier = "Final", art = true, involved = false, localAttacker = false }))
		expect(only(world, "glint.play")[2]).toBe("Large")
		only(world, "slashArc.play")
		only(world, "slashArc.line")
		only(world, "outline.flash")
		expect(only(world, "sfx.cue")[1]).toBe("HitFinal")
		none(world, "impactFrames.play")
		none(world, "sfx.contour")
		none(world, "camera.punch")
	end)

	it("past a moment's own range nothing but the sound plays", function()
		local world = bind(newWorld())
		world.swing = Vector3.new(1, 0, 0)
		-- Between the basic hit's range and the final hit's: the final hit shows, the basic hit does not.
		local between = (moments.rangeOf("Hit") + moments.rangeOf("FinalHit")) / 2
		expect(moments.rangeOf("Hit")).toBeLessThan(moments.rangeOf("FinalHit"))
		world.viewer = HIT_POINT + Vector3.new(between, 0, 0)
		Impact.hit(hitInfo(world, { involved = false, localAttacker = false }))
		none(world, "glint.play")
		expect(only(world, "sfx.cue")[1]).toBe("HitNormal")
		table.clear(world.calls)
		world.clock += 1 -- the next swing, not the same sweep
		Impact.hit(hitInfo(world, { tier = "Final", art = true, involved = false, localAttacker = false }))
		only(world, "glint.play")

		table.clear(world.calls)
		world.clock += 1
		world.viewer = HIT_POINT + Vector3.new(moments.rangeOf("FinalHit") + 1, 0, 0)
		Impact.hit(
			hitInfo(world, { tier = "Final", art = true, involved = false, localAttacker = false, isSwitch = true })
		)
		local fns = {}
		for _, call in world.calls do
			table.insert(fns, call.fn)
		end
		table.sort(fns)
		-- The white hit flash is everyone's, as Replication's was: never lost past the range.
		expect(fns).toEqual({ "outline.flash", "sfx.cue", "sfx.play" })
	end)

	it("with no camera a bystander gets only the sound; the people in the fight still get it all", function()
		local world = bind(newWorld())
		world.viewer = nil
		Impact.hit(hitInfo(world, { tier = "Final", art = true, involved = false }))
		none(world, "glint.play")
		only(world, "sfx.cue")
		table.clear(world.calls)
		Impact.hit(hitInfo(world, { tier = "Final", art = true, involved = true }))
		only(world, "glint.play")
		only(world, "impactFrames.play")
	end)
end)

describe("Impact.hit, after the impact frames", function()
	it("holds the 3D accents while the frames hide the world; the sound, contour and punch start at once", function()
		local world = bind(newWorld())
		world.swing = Vector3.new(1, 0, 0)
		world.hiddenAfterPlay = 0.1
		Impact.hit(hitInfo(world, { killed = true, tier = "Kill", isSwitch = true, partner = world.partner }))
		only(world, "sfx.cue")
		only(world, "impactFrames.play")
		only(world, "sfx.contour")
		only(world, "camera.punch")
		-- The Switch land sound plays with the hit; the blades' flash waits.
		expect(only(world, "sfx.play")[1]).toBe("ui.SwitchLand")
		for _, fn in { "glint.play", "slashArc.play", "slashArc.line", "outline.flash", "trails.flashWhite" } do
			none(world, fn)
		end
		expect(flush(world)).toEqual({ 0.1 })
		only(world, "glint.play")
		only(world, "slashArc.play")
		only(world, "slashArc.line")
		expect(only(world, "outline.flash")[2]).toBe("SystemWhite")
		expect(#callsTo(world, "trails.flashWhite")).toBe(2)
	end)

	it("holds the earlier hits' accents too when a stronger picture of the same sweep takes over", function()
		local world = bind(newWorld())
		world.swing = Vector3.new(1, 0, 0)
		-- A final hit draws its two frames; the kill confirmed in the same frame turns the picture
		-- into the kill's, which hides the world for longer.
		world.hiddenAfterPlay = 2 / 60
		Impact.hit(hitInfo(world, { tier = "Final", art = true }))
		world.hiddenAfterPlay = 6 / 60
		Impact.hit(hitInfo(world, { tier = "Kill", killed = true }))
		none(world, "glint.play")
		-- The final hit's wait is over while the kill's frames are still up: it waits for them.
		local delays = flush(world, 4 / 60)
		expect(delays[1]).toBeCloseTo(2 / 60, 1e-12)
		expect(delays[2]).toBeCloseTo(6 / 60, 1e-12)
		none(world, "glint.play")
		none(world, "outline.flash")
		delays = flush(world)
		expect(#delays).toBe(2)
		expect(delays[1]).toBeCloseTo(4 / 60, 1e-12)
		expect(#callsTo(world, "glint.play")).toBe(2)
		expect(#callsTo(world, "outline.flash")).toBe(2)
		expect(#world.scheduled).toBe(0)
	end)

	it("plays the accents at once when nothing hides the world (no frames, or the soft dim)", function()
		local world = bind(newWorld())
		world.swing = Vector3.new(1, 0, 0)
		world.hiddenAfterPlay = 0
		Impact.hit(hitInfo(world, { tier = "Final", art = true }))
		expect(#world.scheduled).toBe(0)
		only(world, "glint.play")
		only(world, "outline.flash")
	end)

	it("a bystander's accents wait too while the local player's own frames are up", function()
		local world = bind(newWorld())
		world.hidden = 0.05
		world.viewer = HIT_POINT + Vector3.new(0, 0, 10)
		Impact.hit(hitInfo(world, { crit = true, involved = false, localAttacker = false }))
		only(world, "sfx.cue")
		none(world, "glint.play")
		expect(flush(world)).toEqual({ 0.05 })
		expect(only(world, "glint.play")[2]).toBe("Medium")
	end)

	it("an impact-frames module without hiddenSeconds still plays the accents", function()
		local world = newWorld()
		world.deps.impactFrames.hiddenSeconds = nil
		bind(world)
		Impact.hit(hitInfo(world, { tier = "Final", art = true }))
		only(world, "glint.play")
	end)

	it("never holds the accents for impact frames no frame drew (the display asleep)", function()
		-- The real overlay on a hand clock: Heartbeat runs, RenderStepped does not.
		local ImpactFrames = Harness.load("src/client/fx/ImpactFrames")
		local FlashBudget = Harness.load("src/client/fx/FlashBudget")
		local ImpactSequence = Harness.load("src/client/fx/ImpactSequence")
		local F = combat.hitStopFrameSeconds
		local world = newWorld()
		local heartbeat: ((dt: number) -> ())? = nil
		local render: ((dt: number) -> ())? = nil
		local timers: { { at: number, fn: () -> () } } = {}
		ImpactFrames.bind({
			now = function(): number
				return world.clock
			end,
			onRender = function(step: (dt: number) -> ())
				render = step
				return function()
					render = nil
				end
			end,
			onHeartbeat = function(step: (dt: number) -> ())
				heartbeat = step
				return function()
					if heartbeat == step then
						heartbeat = nil
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
		})
		FlashBudget.reset()
		world.deps.impactFrames = ImpactFrames
		world.deps.delay = function(seconds: number, fn: () -> ())
			table.insert(timers, { at = world.clock + seconds, fn = fn })
		end
		bind(world)
		-- One 60 fps engine frame with nothing rendered: the clock, Heartbeat, then due timers.
		local function beat()
			world.clock += F
			if heartbeat ~= nil then
				(heartbeat :: (dt: number) -> ())(F)
			end
			for index = #timers, 1, -1 do
				local timer = timers[index]
				if timer.at <= world.clock + 1e-9 then
					table.remove(timers, index)
					timer.fn()
				end
			end
		end
		local ok, err = pcall(function()
			world.swing = Vector3.new(1, 0, 0)
			local hitAt = world.clock
			Impact.hit(hitInfo(world, { tier = "Kill", killed = true }))
			expect(ImpactFrames.look()).toBe("Black")
			none(world, "glint.play")
			local playedAt: number? = nil
			for _ = 1, 120 do
				beat()
				if playedAt == nil and #callsTo(world, "glint.play") > 0 then
					playedAt = world.clock
				end
			end
			-- Played while the window still slept, at the first ask after the picture gave up its
			-- wait for a first drawn frame (its hit-stop, D-122; a frame drawn inside it would still
			-- hide the world, so the accents wait that long): never held for the whole stall, so
			-- never shown after it for a hit long gone.
			expect(playedAt).never.toBeNil()
			local latest = ImpactSequence.capSeconds("Kill") + ImpactSequence.seconds("Kill") + F + 1e-9
			expect((playedAt :: number) - hitAt).toBeLessThanOrEqual(latest)
			expect((playedAt :: number) - hitAt).toBeGreaterThan(ImpactSequence.capSeconds("Kill"))
			expect(ImpactFrames.isShowing()).toBe(false)
			-- The display wakes: no picture and no second round of accents.
			if render ~= nil then
				(render :: (dt: number) -> ())(F)
			end
			expect(ImpactFrames.isShowing()).toBe(false)
			expect(#callsTo(world, "glint.play")).toBe(1)
			expect(#timers).toBe(0)
		end)
		ImpactFrames.bind(nil)
		FlashBudget.reset()
		if not ok then
			error(err, 0)
		end
	end)
end)

describe("Impact swing tangent", function()
	it("uses the blade's swing direction when Trails knows it", function()
		local world = bind(newWorld())
		world.swing = Vector3.new(0, -3, 4)
		expectVector(Impact.swingTangent(hitInfo(world)) :: Vector3, Vector3.new(0, -0.6, 0.8))
		expect(only(world, "trails.swingDirection")[1]).toBe(world.attacker)
	end)

	it("falls back to the horizontal direction from attacker to target, then to the camera's right", function()
		local world = bind(newWorld())
		world.swing = nil
		world.positions[world.attacker] = Vector3.new(0, 0, 0)
		world.positions[world.target] = Vector3.new(3, 5, 4)
		expectVector(Impact.swingTangent(hitInfo(world)) :: Vector3, Vector3.new(0.6, 0, 0.8))
		-- A still blade counts as unknown too.
		world.swing = Vector3.zero
		expectVector(Impact.swingTangent(hitInfo(world)) :: Vector3, Vector3.new(0.6, 0, 0.8))
		-- Target straight above: no horizontal direction, so the camera's right.
		world.positions[world.target] = Vector3.new(0, 6, 0)
		world.right = Vector3.new(0, 0, 2)
		expectVector(Impact.swingTangent(hitInfo(world)) :: Vector3, Vector3.new(0, 0, 1))
		world.right = nil
		expect(Impact.swingTangent(hitInfo(world, { attacker = nil }))).toBeNil()
	end)

	it("the fallback tangent drives the crescent on a final hit", function()
		local world = bind(newWorld())
		world.swing = nil
		world.positions[world.attacker] = Vector3.new(0, 0, 0)
		world.positions[world.target] = Vector3.new(-4, 1, 0)
		Impact.hit(hitInfo(world, { tier = "Final", art = true }))
		local arc = only(world, "slashArc.play")
		expectVector(arc[2], Vector3.new(-1, 0, 0))
		-- The radius (0, 3, -4) / 5 x (-1, 0, 0) = (0, 0.8, 0.6), already facing the camera
		-- within tilt.faceDegrees: no turn.
		expectNear(arc[3], Vector3.new(0, 0.8, 0.6))
		expect(faceOff(arc[3], Vector3.new(0, 5, 8) - HIT_POINT)).toBeLessThan(TILT.faceDegrees)
	end)

	it("a vertical swing takes the camera's right vector as the crescent's normal", function()
		local world = bind(newWorld())
		world.right = Vector3.new(0, 0, -3)
		expectVector(Impact.planeNormal(Vector3.new(0, 1, 0)) :: Vector3, Vector3.new(0, 0, -1))
		-- (0, 0, 1) x (0, 1, 0) = (-1, 0, 0)
		expectVector(Impact.planeNormal(Vector3.new(0, 0, 1)) :: Vector3, Vector3.new(-1, 0, 0))
		world.right = nil
		expect(Impact.planeNormal(Vector3.new(0, -1, 0))).toBeNil()
	end)
end)

describe("Impact.activation", function()
	local function artClip(hold: number?, windows: { number }): any
		local events = { { time = 0.05, kind = "TrailOn", data = { kind = "Art" } } }
		if hold ~= nil then
			table.insert(events, { time = hold, kind = "ActivationHold", data = { hold = 0.1 } })
		end
		for index, time in windows do
			table.insert(events, { time = time, kind = "HitWindowOpen", data = { hit = index } })
		end
		-- Out of order on purpose: the director reads times, not positions in the list.
		table.sort(events, function(a, b)
			return a.time > b.time
		end)
		return { id = "player/OneHandedSword/Fake", duration = 1.2, events = events }
	end

	it("ends the riser on the first damage window after the hold", function()
		local world = bind(newWorld())
		world.clips["player/OneHandedSword/Fake"] = artClip(0.15, { 0.3333, 0.58, 0.85 })
		Impact.activation(world.target, "player/OneHandedSword/Fake", TOKEN, false)
		local riser = only(world, "sfx.playEndingAt")
		expect(riser[1]).toBe("whoosh.Riser")
		expect(riser[2]).toBeCloseTo(0.1833, 1e-9)
		expectVector(riser[3], world.positions[world.target])
		-- The wind-up contour is the fighter's own.
		none(world, "sfx.contour")
		expect(Impact.riserLead(world.clips["player/OneHandedSword/Fake"])).toBeCloseTo(0.1833, 1e-9)
	end)

	it("the local fighter's hold: the wind-up contour now, no riser (the clip waits for the release)", function()
		local world = bind(newWorld())
		world.clips["player/OneHandedSword/Fake"] = artClip(0.15, { 0.3333 })
		Impact.activation(world.attacker, "player/OneHandedSword/Fake", TOKEN, true)
		none(world, "sfx.playEndingAt")
		expect(only(world, "sfx.contour")[1]).toBe("WindUp")
	end)

	it("the local release ends the riser on the first damage frame, and the highs come back there", function()
		local world = bind(newWorld())
		local clip = artClip(0.15, { 0.3333, 0.58 })
		world.clips["player/OneHandedSword/Fake"] = clip
		for _, releasedAt in { 0.15, 0.4, 1.0 } do
			table.clear(world.calls)
			-- The controller: the clip froze at its hold (0.15) and stays frozen syncPlan's
			-- freezeClipTime after the release, then plays on at speed 1.
			local plan = ActionLogic.syncPlan(0, 0.15, releasedAt)
			Impact.release(world.attacker, "player/OneHandedSword/Fake", 0.15, plan.freezeClipTime, 1)
			local firstDamage = plan.resumeAt + (0.3333 - 0.15)
			local riser = only(world, "sfx.playEndingAt")
			expect(riser[1]).toBe("whoosh.Riser")
			expect(releasedAt + riser[2]).toBeCloseTo(firstDamage, 1e-9)
			expect(riser[3]).toBeNil()
			none(world, "sfx.contour")
			local delays = flush(world)
			expect(#delays).toBe(1)
			expect(delays[1]).toBeCloseTo(riser[2], 1e-9)
			expect(only(world, "sfx.contour")[1]).toBe(moments.rows.Activation.releaseContour)
		end
	end)

	it("a release scales the clip time by the speed and finds the window after where the clip waits", function()
		local world = bind(newWorld())
		world.clips["player/OneHandedSword/Fake"] = artClip(0.15, { 0.3333, 0.58 })
		Impact.release(world.attacker, "player/OneHandedSword/Fake", 0.15, 0.15, 2)
		expect(only(world, "sfx.playEndingAt")[2]).toBeCloseTo(0.15 + 0.1833 / 2, 1e-9)
		table.clear(world.calls)
		-- Frozen by the fallback timer past the first window: the next window is the one.
		Impact.release(world.attacker, "player/OneHandedSword/Fake", 0.4, 0.4, 1)
		expect(only(world, "sfx.playEndingAt")[2]).toBeCloseTo(0.4 + 0.18, 1e-9)
		table.clear(world.calls)
		world.scheduled = {}
		-- No window after it: no riser, and the highs come back at once.
		Impact.release(world.attacker, "player/OneHandedSword/Fake", 0.7, 0.7, 1)
		none(world, "sfx.playEndingAt")
		expect(only(world, "sfx.contour")[1]).toBe(moments.rows.Activation.releaseContour)
	end)

	it("letting a hold go past the cancel time brings the highs back at once", function()
		local world = bind(newWorld())
		Impact.cancelActivation(world.attacker)
		expect(only(world, "sfx.contour")[1]).toBe(moments.rows.Activation.releaseContour)
		none(world, "sfx.playEndingAt")
	end)

	it("scales the lead by the clip's speed and skips a lead under the minimum", function()
		local world = bind(newWorld())
		local minimum = moments.rows.Activation.riser.minLeadSeconds
		world.clips["player/OneHandedSword/Fake"] = artClip(0.15, { 0.15 + minimum * 3 })
		Impact.activation(world.target, "player/OneHandedSword/Fake", TOKEN, false, 2)
		expect(only(world, "sfx.playEndingAt")[2]).toBeCloseTo(minimum * 1.5, 1e-9)
		table.clear(world.calls)
		Impact.activation(world.target, "player/OneHandedSword/Fake", TOKEN, false, 4)
		none(world, "sfx.playEndingAt")
		table.clear(world.calls)
		world.clips["player/OneHandedSword/Fake"] = artClip(0.15, { 0.15 + minimum * 0.9 })
		Impact.activation(world.target, "player/OneHandedSword/Fake", TOKEN, false)
		none(world, "sfx.playEndingAt")
	end)

	it("a hold a late start jumped over still ends the riser on the first damage frame", function()
		local world = bind(newWorld())
		local minimum = moments.rows.Activation.riser.minLeadSeconds
		world.clips["player/OneHandedSword/Fake"] = artClip(0.15, { 0.15 + minimum * 4 })
		-- At speed 2 the window comes minimum * 2 after the hold; heard minimum * 0.5 late, it is
		-- minimum * 1.5 away.
		Impact.activation(world.target, "player/OneHandedSword/Fake", TOKEN, false, 2, minimum * 0.5)
		expect(only(world, "sfx.playEndingAt")[2]).toBeCloseTo(minimum * 1.5, 1e-9)
		table.clear(world.calls)
		-- Too close to the window for a riser to build.
		Impact.activation(world.target, "player/OneHandedSword/Fake", TOKEN, false, 2, minimum * 1.5)
		none(world, "sfx.playEndingAt")
	end)

	it("plays no riser for a clip with no hold, no window after it, or no clip at all", function()
		local world = bind(newWorld())
		world.clips["player/OneHandedSword/Basic1"] = artClip(nil, { 0.2 })
		Impact.activation(world.target, "player/OneHandedSword/Basic1", TOKEN, false)
		world.clips["player/OneHandedSword/Late"] = artClip(0.5, { 0.3 })
		Impact.activation(world.target, "player/OneHandedSword/Late", TOKEN, false)
		Impact.activation(world.target, "player/OneHandedSword/Missing", TOKEN, false)
		none(world, "sfx.playEndingAt")
		expect(Impact.riserLead({ events = {} })).toBeNil()
		expect(Impact.riserLead(nil)).toBeNil()
	end)
end)

describe("Impact.dodge", function()
	it("draws speed lines only on the dodging fighter's own screen", function()
		local world = bind(newWorld())
		Impact.dodge(world.attacker, true)
		expect(only(world, "speedLines.play")[1]).toBe("Dodge")
		local cue = only(world, "sfx.cue")
		expect(cue[1]).toBe("Dodge")
		expectVector(cue[2], world.positions[world.attacker])
	end)

	it("another fighter's dodge: the cue in range, nothing past it, never the lines", function()
		local world = bind(newWorld())
		world.viewer = world.positions[world.target] + Vector3.new(moments.rangeOf("Dodge") - 1, 0, 0)
		Impact.dodge(world.target, false)
		none(world, "speedLines.play")
		expect(only(world, "sfx.cue")[1]).toBe("Dodge")
		table.clear(world.calls)
		world.viewer = world.positions[world.target] + Vector3.new(moments.rangeOf("Dodge") + 1, 0, 0)
		Impact.dodge(world.target, false)
		expect(#world.calls).toBe(0)
	end)

	it("hands the cue a remote catch-up's lateness, and none when the dodge started on time", function()
		local world = bind(newWorld())
		Impact.dodge(world.target, false, 0.08)
		local cue = only(world, "sfx.cue")
		expect(cue[1]).toBe("Dodge")
		expectVector(cue[2], world.positions[world.target])
		expect(cue[3]).toBe(0.08)
		table.clear(world.calls)
		Impact.dodge(world.target, false)
		expect(only(world, "sfx.cue")[3]).toBeNil()
	end)
end)

describe("Impact.death", function()
	it("blooms the mix for a death in range and never plays the shatter's own cue", function()
		local world = bind(newWorld())
		Impact.death(world.target, HIT_POINT, false)
		expect(only(world, "sfx.contour")[1]).toBe("ShatterBloom")
		none(world, "sfx.cue")
		none(world, "sfx.play")
		table.clear(world.calls)
		Impact.death(nil, HIT_POINT, true)
		expect(only(world, "sfx.contour")[1]).toBe("BossShatterBloom")
	end)

	it("a death past its range leaves the mix alone", function()
		local world = bind(newWorld())
		world.viewer = HIT_POINT + Vector3.new(0, 0, moments.rangeOf("Death") + 1)
		Impact.death(world.target, HIT_POINT, false)
		none(world, "sfx.contour")
	end)
end)

describe("Impact swing plane", function()
	it("lies in the true swing plane: the radius crossed with the swing, bulging away from the attacker", function()
		local world = bind(newWorld())
		world.right = nil
		-- A flat swing in front: the plane is flat, the crescent bulges outward along the radius.
		local flat = Impact.planeNormal(Vector3.new(1, 0, 0), Vector3.new(0, 0, -5)) :: Vector3
		expectNear(flat, Vector3.new(0, -1, 0))
		expectNear(Vector3.new(1, 0, 0):Cross(flat), Vector3.new(0, 0, -1))
		-- An overhead chop: the plane stands upright through the attacker, never the camera's.
		local chop = Impact.planeNormal(Vector3.new(0, -1, 0), Vector3.new(0, 0, -3)) :: Vector3
		expectNear(chop, Vector3.new(-1, 0, 0))
		expectNear(Vector3.new(0, -1, 0):Cross(chop), Vector3.new(0, 0, -1))
		-- A rising diagonal keeps its own tilt.
		local rising = Impact.planeNormal(Vector3.new(1, 1, 0).Unit, Vector3.new(0, 0, -2)) :: Vector3
		expect(math.abs(rising:Dot(Vector3.new(1, 1, 0).Unit))).toBeLessThan(1e-5)
		expectNear(Vector3.new(1, 1, 0).Unit:Cross(rising), Vector3.new(0, 0, -1))
	end)

	it("a thrust (a swing along its radius) stands upright along the swing", function()
		local world = bind(newWorld())
		world.right = nil
		expectNear(Impact.planeNormal(Vector3.new(0, 0, -1), Vector3.new(0, 0, -3)) :: Vector3, Vector3.new(1, 0, 0))
		-- Just inside asin(minPlaneSine) of the radius is still a thrust.
		local angle = math.asin(TILT.minPlaneSine) * 0.9
		local near = Vector3.new(math.sin(angle), 0, -math.cos(angle))
		expectNear(Impact.planeNormal(Vector3.new(0, 0, -1), near * 3) :: Vector3, Vector3.new(1, 0, 0))
		-- Just past it, the swing has a plane of its own.
		local past = math.asin(TILT.minPlaneSine) * 1.1
		local across = Vector3.new(math.sin(past), 0, -math.cos(past))
		local normal = Impact.planeNormal(Vector3.new(0, 0, -1), across) :: Vector3
		expectNear(normal, across:Cross(Vector3.new(0, 0, -1)).Unit)
		-- No attacker: tangent x up, as before.
		expectNear(Impact.planeNormal(Vector3.new(0, 0, 1)) :: Vector3, Vector3.new(-1, 0, 0))
	end)

	it("turns toward the camera only as far as the face needs, and never past the cap", function()
		local world = bind(newWorld())
		world.right = nil
		local t = Vector3.new(1, 0, 0)
		local radial = Vector3.new(0, 0, -4)
		-- Facing the camera already: unchanged.
		expectNear(Impact.planeNormal(t, radial, Vector3.new(0, -3, 0)) :: Vector3, Vector3.new(0, -1, 0))
		expectNear(Impact.planeNormal(t, radial, Vector3.new(0, 3, -1)) :: Vector3, Vector3.new(0, -1, 0))
		-- 60 degrees off: turned to exactly faceDegrees off, about the swing (the tangent stays).
		local sixty = Vector3.new(0, -math.cos(math.rad(60)), -math.sin(math.rad(60)))
		local turned = Impact.planeNormal(t, radial, sixty) :: Vector3
		expect(faceOff(turned, sixty)).toBeCloseTo(TILT.faceDegrees, 1e-3)
		expect(math.abs(turned:Dot(t))).toBeLessThan(1e-6)
		-- Edge-on: the cap, toward the camera.
		local edge = Vector3.new(0, 0, 5)
		local capped = Impact.planeNormal(t, radial, edge) :: Vector3
		expect(faceOff(capped, edge)).toBeCloseTo(90 - TILT.maxDegrees, 1e-3)
		expect(math.abs(capped:Dot(t))).toBeLessThan(1e-6)
		-- The same from the other side of the plane, and from below.
		local under = Vector3.new(0, 0.2, -5)
		expect(faceOff(Impact.planeNormal(t, radial, under) :: Vector3, under)).toBeLessThan(
			faceOff(Vector3.new(0, -1, 0), under)
		)
		-- Looking straight along the swing: nothing to turn toward.
		expectNear(Impact.planeNormal(t, radial, Vector3.new(7, 0, 0)) :: Vector3, Vector3.new(0, -1, 0))
	end)
end)

describe("Impact sweep", function()
	local function sweepOf(world: any, count: number, changes: { [string]: any }): { any }
		local targets = {}
		for index = 1, count do
			local target = { name = "target" .. index }
			world.positions[target] = Vector3.new(index * 2, 3, -6)
			table.insert(targets, target)
		end
		for index, target in targets do
			local info = hitInfo(world, changes)
			info.target = target
			info.position = Vector3.new(index * 2, 3, -5)
			Impact.hit(info)
		end
		return targets
	end

	it(
		"twelve targets of one swing are one cue, one contour and one punch; every target's accents still play",
		function()
			local world = bind(newWorld())
			world.swing = Vector3.new(1, 0, 0)
			world.hiddenAfterPlay = 2 * combat.hitStopFrameSeconds -- the picture shows
			sweepOf(world, 12, { tier = "Final", art = true })
			expect(only(world, "sfx.cue")[1]).toBe("HitFinal")
			expect(only(world, "sfx.contour")[1]).toBe("FinalHit")
			expect(only(world, "camera.punch")[1]).toBe("Final")
			-- ImpactFrames joins the twelve plays into one picture (its own spec).
			expect(#callsTo(world, "impactFrames.play")).toBe(12)
			flush(world)
			expect(#callsTo(world, "glint.play")).toBe(12)
			expect(#callsTo(world, "outline.flash")).toBe(12)
		end
	)

	it(
		"a kill among the sweep's hits adds its own cue and takes the mix over; a later final hit never undoes it",
		function()
			local world = bind(newWorld())
			world.swing = Vector3.new(1, 0, 0)
			sweepOf(world, 3, { tier = "Final", art = true })
			sweepOf(world, 1, { tier = "Kill", killed = true })
			sweepOf(world, 3, { tier = "Final", art = true })
			local cues = {}
			for _, args in callsTo(world, "sfx.cue") do
				table.insert(cues, args[1])
			end
			expect(cues).toEqual({ "HitFinal", "HitKill" })
			local contours = {}
			for _, args in callsTo(world, "sfx.contour") do
				table.insert(contours, args[1])
			end
			expect(contours).toEqual({ "FinalHit", "KillCut" })
			local punches = {}
			for _, args in callsTo(world, "camera.punch") do
				table.insert(punches, args[1])
			end
			expect(punches).toEqual({ "Final", "Kill" })
		end
	)

	it(
		"a sweep's cues sound at its first hit, so the layers they share play once; a weaker cue after the kill adds none",
		function()
			local world = bind(newWorld())
			world.swing = Vector3.new(1, 0, 0)
			-- A kill confirmed first: the final hits of the same sweep add no cue under it.
			sweepOf(world, 1, { tier = "Kill", killed = true })
			sweepOf(world, 3, { tier = "Final", art = true })
			local cues = callsTo(world, "sfx.cue")
			expect(#cues).toBe(1)
			expect(cues[1][1]).toBe("HitKill")
			-- The next swing: a final hit at one end, the kill at the far end (farther apart than
			-- SfxPool's same-spot dedupe reaches). Both cues play, the kill's at the sweep's first
			-- hit, so the crack and the flesh they share are one sound.
			world.clock += 1
			table.clear(world.calls)
			local near = hitInfo(world, { tier = "Final", art = true, position = Vector3.new(-10, 3, -5) })
			local far = hitInfo(world, { tier = "Kill", killed = true, position = Vector3.new(10, 3, -5) })
			Impact.hit(near)
			Impact.hit(far)
			cues = callsTo(world, "sfx.cue")
			expect(#cues).toBe(2)
			expect(cues[1][1]).toBe("HitFinal")
			expect(cues[2][1]).toBe("HitKill")
			expectVector(cues[1][2], near.position)
			expectVector(cues[2][2], near.position)
			-- The kill's other accents stay at its own target.
			flush(world)
			local glints = callsTo(world, "glint.play")
			expectVector(glints[#glints][1], far.position)
		end
	)

	it("a sweep confirmed over several frames draws one picture; only a stronger hit draws again", function()
		local world = bind(newWorld())
		world.swing = Vector3.new(1, 0, 0)
		-- The server confirms a wide sweep's targets over a few frames; the first picture (two
		-- frames) is over before the last of them arrive.
		local frame = combat.hitStopFrameSeconds
		Impact.hit(hitInfo(world, { tier = "Final", art = true }))
		expect(#callsTo(world, "impactFrames.play")).toBe(1)
		world.clock += 2 * frame
		Impact.hit(hitInfo(world, { tier = "Final", art = true }))
		world.clock += frame
		Impact.hit(hitInfo(world, { tier = "Final", art = true }))
		expect(#callsTo(world, "impactFrames.play")).toBe(1)
		-- One cue, one contour, one punch for the whole sweep.
		only(world, "sfx.cue")
		only(world, "sfx.contour")
		only(world, "camera.punch")
		-- A kill among them is a stronger moment: its picture plays; a final hit after it does not.
		world.clock += frame
		Impact.hit(hitInfo(world, { tier = "Kill", killed = true }))
		world.clock += frame
		Impact.hit(hitInfo(world, { tier = "Final", art = true }))
		local plays = callsTo(world, "impactFrames.play")
		expect(#plays).toBe(2)
		expect(plays[2][1]).toBe("Kill")
		-- Every target's accents still play.
		flush(world)
		expect(#callsTo(world, "glint.play")).toBe(5)
	end)

	it("the local player's own hit is its own sweep: heard at the player, never folded into another's", function()
		local world = bind(newWorld())
		local ally = { name = "ally" }
		local me = { name = "me" }
		world.positions[ally] = Vector3.new(6, 3, 0)
		world.positions[me] = Vector3.new(-2, 3, 0)
		local allyPoint = Vector3.new(6, 3, 0)
		local myPoint = Vector3.new(-2, 3, 0)
		local function strike(target: any, point: Vector3, changes: { [string]: any })
			local info = hitInfo(world, changes)
			info.target = target
			info.position = point
			info.localAttacker = false
			info.art = nil
			Impact.hit(info)
		end
		-- An enemy's cleave in one frame: the ally guards it, the local player takes it clean.
		strike(ally, allyPoint, { involved = false, guarded = true })
		strike(me, myPoint, { involved = true })
		local cues = callsTo(world, "sfx.cue")
		expect(#cues).toBe(2)
		expect(cues[1][1]).toBe("Block")
		expectVector(cues[1][2], allyPoint)
		expect(cues[2][1]).toBe("HitNormal")
		expectVector(cues[2][2], myPoint)
		-- The next cleave kills the ally and hits the player: the player's hit is not dropped
		-- behind the ally's kill.
		world.clock += 1
		table.clear(world.calls)
		strike(ally, allyPoint, { involved = false, tier = "Kill", killed = true })
		strike(me, myPoint, { involved = true })
		cues = callsTo(world, "sfx.cue")
		expect(#cues).toBe(2)
		expect(cues[1][1]).toBe("HitKill")
		expectVector(cues[1][2], allyPoint)
		expect(cues[2][1]).toBe("HitNormal")
		expectVector(cues[2][2], myPoint)
	end)

	it("a parry or a block sounds after a kill of the same strike, in either order", function()
		local world = bind(newWorld())
		local ally = { name = "ally" }
		local other = { name = "other" }
		world.positions[ally] = Vector3.new(6, 3, 0)
		world.positions[other] = Vector3.new(-6, 3, 0)
		local function strike(target: any, changes: { [string]: any })
			local info = hitInfo(world, changes)
			info.target = target
			info.position = world.positions[target] or HIT_POINT
			info.localAttacker = false
			info.art = nil
			Impact.hit(info)
		end
		local function cueNames(): { string }
			local names = {}
			for _, args in callsTo(world, "sfx.cue") do
				table.insert(names, args[1])
			end
			return names
		end
		-- The strike kills the ally, then the local player parries it.
		strike(ally, { involved = false, tier = "Kill", killed = true })
		strike(world.target, { involved = true, parried = true })
		expect(cueNames()).toEqual({ "HitKill", "Parry" })
		-- The strike kills the ally, then another fighter blocks it (both seen from outside).
		world.clock += 1
		table.clear(world.calls)
		strike(ally, { involved = false, tier = "Kill", killed = true })
		strike(other, { involved = false, guarded = true })
		expect(cueNames()).toEqual({ "HitKill", "Block" })
		-- The other way round gives the same sounds.
		world.clock += 1
		table.clear(world.calls)
		strike(other, { involved = false, guarded = true })
		strike(ally, { involved = false, tier = "Kill", killed = true })
		expect(cueNames()).toEqual({ "Block", "HitKill" })
	end)

	it("another attacker's hit in the same frame is its own sound", function()
		local world = bind(newWorld())
		Impact.hit(hitInfo(world))
		Impact.hit(hitInfo(world, { attacker = world.partner, localAttacker = false }))
		expect(#callsTo(world, "sfx.cue")).toBe(2)
	end)

	it("the next swing (past the merge window) sounds again; a Switch's land sound plays once per sweep", function()
		local world = bind(newWorld())
		Impact.hit(hitInfo(world, { isSwitch = true, partner = world.partner }))
		Impact.hit(hitInfo(world, { isSwitch = true, partner = world.partner }))
		expect(#callsTo(world, "sfx.cue")).toBe(1)
		expect(#callsTo(world, "sfx.play")).toBe(1)
		world.clock += moments.sweep.mergeSeconds * 0.5
		Impact.hit(hitInfo(world))
		expect(#callsTo(world, "sfx.cue")).toBe(1)
		world.clock += moments.sweep.mergeSeconds * 1.01
		Impact.hit(hitInfo(world))
		expect(#callsTo(world, "sfx.cue")).toBe(2)
		-- Binding again forgets every sweep.
		bind(world)
		Impact.hit(hitInfo(world))
		expect(#callsTo(world, "sfx.cue")).toBe(3)
	end)

	it("an effect this client did not get does not use up the sweep's", function()
		local world = bind(newWorld())
		world.swing = Vector3.new(1, 0, 0)
		-- One swing through a mob and the local player: the mob's hit is a bystander's view (no
		-- contour, no punch), the player's own hit then gets both, and its own cue at its point.
		Impact.hit(hitInfo(world, { tier = "Final", art = true, involved = false, localAttacker = false }))
		none(world, "sfx.contour")
		none(world, "camera.punch")
		local mine = hitInfo(world, {
			tier = "Final",
			art = true,
			involved = true,
			localAttacker = false,
			position = Vector3.new(-3, 3, -4),
		})
		Impact.hit(mine)
		expect(only(world, "sfx.contour")[1]).toBe("FinalHit")
		expect(only(world, "camera.punch")[1]).toBe("Final")
		local cues = callsTo(world, "sfx.cue")
		expect(#cues).toBe(2)
		expect(cues[2][1]).toBe("HitFinal")
		expectVector(cues[2][2], mine.position)
	end)
end)

describe("Impact guard and death sounds", function()
	it("a guard break plays the GuardBreak cue at the fighter for everyone", function()
		local world = bind(newWorld())
		Impact.guardBreak(world.target, false)
		local cue = only(world, "sfx.cue")
		expect(cue[1]).toBe("GuardBreak")
		expectVector(cue[2], world.positions[world.target])
		table.clear(world.calls)
		Impact.guardBreak(world.attacker, true)
		expect(only(world, "sfx.cue")[1]).toBe("GuardBreak")
	end)

	it("a guard going up plays the raise near it, and on the guarding fighter's own client", function()
		local world = bind(newWorld())
		Impact.guardRaise(world.attacker, true)
		local sound = only(world, "sfx.play")
		expect(sound[1]).toBe("guard.GuardRaise")
		expectVector(sound[2], world.positions[world.attacker])
		table.clear(world.calls)
		world.viewer = world.positions[world.target] + Vector3.new(moments.rangeOf("GuardRaise") + 1, 0, 0)
		Impact.guardRaise(world.target, false)
		none(world, "sfx.play")
		table.clear(world.calls)
		world.viewer = world.positions[world.target] + Vector3.new(moments.rangeOf("GuardRaise") - 1, 0, 0)
		Impact.guardRaise(world.target, false)
		only(world, "sfx.play")
	end)

	it("names the shatter's cue: the boss's, a player's or an Elite's heavy one, else a mob's", function()
		bind(newWorld())
		expect(Impact.shatterCue(true)).toBe("BossShatter")
		expect(Impact.shatterCue(true, true)).toBe("BossShatter")
		expect(Impact.shatterCue(false, true)).toBe("ShatterHeavy")
		expect(Impact.shatterCue(false, false)).toBe("Shatter")
		expect(Impact.shatterCue(false)).toBe("Shatter")
	end)

	it("a heavy death blooms the mix like any death", function()
		local world = bind(newWorld())
		Impact.death(world.target, HIT_POINT, false, true)
		expect(only(world, "sfx.contour")[1]).toBe(moments.rows.HeavyDeath.contour)
		none(world, "sfx.cue")
	end)

	it("reports how long the impact frames still hide the world, 0 without the module", function()
		local world = bind(newWorld())
		world.hidden = 0.08
		expect(Impact.hiddenSeconds()).toBe(0.08)
		world.hidden = -1
		expect(Impact.hiddenSeconds()).toBe(0)
		world.deps.impactFrames = nil
		bind(world)
		expect(Impact.hiddenSeconds()).toBe(0)
	end)
end)

describe("Impact start order", function()
	-- Main.client.luau's SIBLING_ORDER, in order.
	local function siblingOrder(): { string }
		local source = Harness.readFile("src/client/Main.client.luau")
		local block = source:match("local SIBLING_ORDER = (%b{})")
		expect(block).never.toBeNil()
		local order = {}
		for path in (block :: string):gmatch('"([%w%.]+)"') do
			table.insert(order, path)
		end
		return order
	end

	it("Main starts the director after everything it fires, and the ambience right after the pool", function()
		local order = siblingOrder()
		local function at(path: string): number
			local index = table.find(order, path)
			if index == nil then
				error(path .. " is not in SIBLING_ORDER", 2)
			end
			return index :: number
		end
		local impact = at("fx.Impact")
		for _, path in
			{
				"audio.SfxPool",
				"fx.OutlineManager",
				"fx.Trails",
				"fx.Shatter",
				"fx.ImpactFrames",
				"fx.Glint",
				"fx.SlashArc",
				"fx.SpeedLines",
			}
		do
			expect(at(path)).toBeLessThan(impact)
		end
		expect(at("audio.Ambience")).toBe(at("audio.SfxPool") + 1)
		expect(at("fx.Quality")).toBe(1)
	end)
end)

describe("Impact dependencies", function()
	it("a missing module logs once and the moment's other effects still play", function()
		local world = newWorld()
		world.deps.slashArc = nil
		bind(world)
		local before = #Harness.warnings()
		Impact.hit(hitInfo(world, { tier = "Final", art = true }))
		world.clock += 1
		Impact.hit(hitInfo(world, { tier = "Final", art = true }))
		expect(warningsSince(before, "slashArc")).toBe(1)
		expect(#callsTo(world, "glint.play")).toBe(2)
		expect(#callsTo(world, "sfx.cue")).toBe(2)
		expect(#callsTo(world, "impactFrames.play")).toBe(2)
	end)

	it("a module without the function logs once too", function()
		local world = newWorld()
		world.deps.sfx.contour = nil
		bind(world)
		local before = #Harness.warnings()
		Impact.hit(hitInfo(world, { killed = true }))
		world.clock += 1
		Impact.hit(hitInfo(world, { killed = true }))
		expect(warningsSince(before, "sfx.contour")).toBe(1)
		expect(#callsTo(world, "camera.punch")).toBe(2)
	end)

	it("an effect that errors is logged once and never stops the others", function()
		local world = newWorld()
		world.deps.glint.play = function()
			error("no glint today")
		end
		bind(world)
		local before = #Harness.warnings()
		Impact.hit(hitInfo(world))
		world.clock += 1
		Impact.hit(hitInfo(world))
		expect(warningsSince(before, "glint.play failed")).toBe(1)
		expect(#callsTo(world, "sfx.cue")).toBe(2)
	end)

	it("binding again forgets what was logged", function()
		local world = newWorld()
		world.deps.camera = nil
		bind(world)
		local before = #Harness.warnings()
		Impact.hit(hitInfo(world, { killed = true }))
		bind(world)
		Impact.hit(hitInfo(world, { killed = true }))
		expect(warningsSince(before, "camera is not available")).toBe(2)
	end)
end)

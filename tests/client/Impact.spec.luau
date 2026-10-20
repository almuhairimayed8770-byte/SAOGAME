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

-- Runs what the director scheduled, in order; returns the delays it asked for.
local function flush(world: any): { number }
	local delays = {}
	local list = world.scheduled
	world.scheduled = {}
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
		expect(Impact.hit(hitInfo(world, { tier = "Final" }))).toBe("Hit")
		expect(only(world, "glint.play")[2]).toBe("Small")
		expect(only(world, "sfx.cue")[1]).toBe("HitNormal")
		for _, fn in { "impactFrames.play", "sfx.contour", "camera.punch", "slashArc.play", "slashArc.line" } do
			none(world, fn)
		end
		-- Replication's white flash stays.
		none(world, "outline.flash")
		expect(Impact.ownsHighlight(hitInfo(world, { tier = "Final" }))).toBe(false)
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
		-- tangent x up: (1, 0, 0) x (0, 1, 0) = (0, 0, 1)
		expectVector(arc[3], Vector3.new(0, 0, 1))
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
		Impact.hit(hitInfo(world, { tier = "Final", art = true, involved = false, localAttacker = false }))
		only(world, "glint.play")

		table.clear(world.calls)
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
		-- (-1, 0, 0) x (0, 1, 0) = (0, 0, -1)
		expectVector(arc[3], Vector3.new(0, 0, -1))
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

describe("Impact dependencies", function()
	it("a missing module logs once and the moment's other effects still play", function()
		local world = newWorld()
		world.deps.slashArc = nil
		bind(world)
		local before = #Harness.warnings()
		Impact.hit(hitInfo(world, { tier = "Final", art = true }))
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

--!strict
-- accents.luau and its validator (tools/validators/accents.luau). The real table must be clean;
-- each case below breaks one rule on a deep copy and expects the validator to name it.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local accents = Harness.load("src/shared/data/accents")
local combat = Harness.load("src/shared/data/combat")
local fx = Harness.load("src/shared/data/fx")
local palette = Harness.load("src/shared/data/palette")

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = deepCopy(inner)
	end
	return copy
end

-- Runs the validator with whole tables swapped by path; a nil moments override means "no file".
local function runValidator(overrides: { [string]: any }?, noMoments: boolean?): { string }
	local path = "tools/validators/accents.luau"
	local chunk = luau.load(
		fs.readFile(Harness.repoRoot() .. "/" .. path),
		{ debugName = path, environment = Harness.environment() :: any }
	)
	local validate = chunk()
	return validate({
		load = function(modulePath: string): any
			if overrides ~= nil and overrides[modulePath] ~= nil then
				return overrides[modulePath]
			end
			if noMoments and modulePath == "src/shared/data/moments" then
				error("no moments.luau in this case")
			end
			return Harness.load(modulePath)
		end,
		listFiles = Harness.listFiles,
		readFile = Harness.readFile,
		repoRoot = Harness.repoRoot(),
	})
end

local function mentions(problems: { string }, needle: string): boolean
	for _, problem in problems do
		if problem:find(needle, 1, true) then
			return true
		end
	end
	return false
end

-- A deep copy of accents.luau with `change` applied, run through the validator.
local function broken(change: (any) -> ()): { string }
	local copy = deepCopy(accents)
	change(copy)
	return runValidator({ ["src/shared/data/accents"] = copy }, true)
end

describe("accents data", function()
	it("passes its validator", function()
		local problems = runValidator(nil, true)
		if #problems > 0 then
			error(table.concat(problems, "\n"), 0)
		end
	end)

	it("passes its validator against moments.luau when the director's table is there", function()
		local problems = runValidator(nil, false)
		if #problems > 0 then
			error(table.concat(problems, "\n"), 0)
		end
	end)

	it("has every size and kind the shared contract names, in palette colors", function()
		for _, name in { "Small", "Medium", "Large", "Parry" } do
			expect(accents.glint.sizes[name]).never.toBeNil()
		end
		for _, name in { "Medium", "Large" } do
			expect(accents.slashArc.sizes[name]).never.toBeNil()
			expect(accents.slashLine.sizes[name]).never.toBeNil()
		end
		for _, name in { "Dodge", "Dash" } do
			expect(accents.speedLines.kinds[name]).never.toBeNil()
		end
		expect(accents.glint.coreToken).toBe("SystemWhite")
		expect(accents.glint.edgeTokens).toEqual({ "TrailRose", "SystemCyan" })
		expect(accents.slashLine.coreToken).toBe("SystemWhite")
		expect(accents.slashLine.edgeTokens).toEqual({ "TrailRose", "SystemCyan" })
		expect(accents.slashArc.innerToken).toBe("SystemWhite")
		for _, token in { accents.slashArc.defaultToken, accents.speedLines.token } do
			expect(palette.tokens[token]).never.toBeNil()
		end
	end)

	it("ties its clock and limits to combat.luau and has a row per fx.luau quality tier", function()
		expect(accents.frameSeconds).toBe(combat.hitStopFrameSeconds)
		expect(accents.limits.fullFrames).toBe(combat.hitStopFrames.Kill)
		expect(accents.speedLines.kinds.Dodge.seconds).toBe(combat.dodgeDuration)
		expect(accents.seconds(6)).toBeCloseTo(6 * combat.hitStopFrameSeconds, 1e-12)
		for tier in fx.quality do
			expect(accents.quality[tier]).never.toBeNil()
			expect(accents.tier(tier)).toBe(accents.quality[tier])
		end
		expect(accents.tier("Ultra")).toBe(accents.quality.High)
	end)

	it("turns a crescent toward the camera by a bounded angle and knows a thrust from a swing", function()
		local tilt = accents.slashArc.tilt
		-- A face more than faceDegrees off the camera turns, by at most maxDegrees: a full turn
		-- from edge-on (90) leaves it no nearer than faceDegrees, so the swing plane still reads.
		expect(tilt.maxDegrees).toBeGreaterThan(0)
		expect(tilt.faceDegrees).toBeGreaterThan(0)
		expect(tilt.faceDegrees).toBeLessThan(90)
		expect(90 - tilt.maxDegrees).toBeGreaterThanOrEqual(tilt.faceDegrees)
		-- The sine of the smallest angle between a swing and its radius that still has a plane.
		expect(tilt.minPlaneSine).toBeGreaterThan(0)
		expect(tilt.minPlaneSine).toBeLessThan(1)
	end)

	it("remembers a swing long enough for a late confirmation and never into the next swing", function()
		local memory = accents.swing.memorySeconds
		expect(memory).toBeGreaterThan(accents.swing.samples * combat.hitStopFrameSeconds)
		-- A basic chain's next swing starts within a second; the memory never reaches that far.
		expect(memory).toBeLessThan(1)
	end)

	it("reads a strike's snap over the smear's frames, well inside the memory", function()
		expect(accents.swing.snapFrames).toBe(fx.smear.frames)
		expect(accents.swing.snapFrames).toBeGreaterThanOrEqual(1)
		expect(accents.swing.snapFrames * accents.frameSeconds).toBeLessThan(accents.swing.memorySeconds)
	end)
end)

describe("accents validator", function()
	it("rejects a color that is not a palette token", function()
		local problems = broken(function(copy)
			copy.glint.edgeTokens[2] = "Rainbow"
		end)
		expect(mentions(problems, "glint.edgeTokens[2] 'Rainbow' is not a palette token")).toBe(true)
		expect(mentions(
			broken(function(copy)
				copy.speedLines.token = "#FFFFFF"
			end),
			"speedLines.token"
		)).toBe(true)
	end)

	it("rejects a missing contract size and a default that names nothing", function()
		local problems = broken(function(copy)
			copy.glint.sizes.Parry = nil
			copy.slashArc.defaultSize = "Huge"
		end)
		expect(mentions(problems, "glint.sizes is missing Parry")).toBe(true)
		expect(mentions(problems, "slashArc.defaultSize 'Huge' is not a size")).toBe(true)
		expect(mentions(
			broken(function(copy)
				copy.speedLines.kinds.Dash = nil
			end),
			"speedLines.kinds is missing Dash"
		)).toBe(true)
	end)

	it("rejects an effect at full strength past the kill hit-stop, or fading too long", function()
		local tooLong = broken(function(copy)
			copy.glint.sizes.Parry.holdFrames = accents.limits.fullFrames
		end)
		expect(mentions(tooLong, "glint.sizes.Parry is at full strength")).toBe(true)
		local slowFade = broken(function(copy)
			copy.slashLine.sizes.Large.thinFrames = accents.limits.maxFadeFrames + 1
		end)
		expect(mentions(slowFade, "slashLine.sizes.Large fades over")).toBe(true)
		local arcHold = broken(function(copy)
			copy.slashArc.sizes.Medium.holdFrames = accents.limits.fullFrames
		end)
		expect(mentions(arcHold, "slashArc.sizes.Medium is at full strength")).toBe(true)
		local lines = broken(function(copy)
			copy.speedLines.kinds.Dodge.outFrames = 1
		end)
		expect(mentions(lines, "speedLines.kinds.Dodge is at full strength")).toBe(true)
		local dodge = broken(function(copy)
			copy.speedLines.kinds.Dodge.seconds = 0.5
		end)
		expect(mentions(dodge, "Dodge.seconds must be combat.dodgeDuration")).toBe(true)
	end)

	it("rejects a linear or unknown easing", function()
		local problems = broken(function(copy)
			copy.glint.punchEasing = "Linear"
			copy.slashArc.wipeEasing = "Wobble"
		end)
		expect(mentions(problems, "glint.punchEasing must ease")).toBe(true)
		expect(mentions(problems, "slashArc.wipeEasing 'Wobble' is not a util/Easing curve")).toBe(true)
	end)

	it("rejects sizes out of order and a Parry glint that is not the biggest and longest", function()
		local problems = broken(function(copy)
			copy.glint.sizes.Parry.studs = accents.glint.sizes.Small.studs
			copy.glint.sizes.Parry.fadeFrames = 1
		end)
		expect(mentions(problems, "glint Parry must be bigger than Large")).toBe(true)
		expect(mentions(problems, "the Parry glint must last longest")).toBe(true)
		expect(mentions(
			broken(function(copy)
				copy.slashArc.sizes.Large.width = accents.slashArc.sizes.Medium.width
			end),
			"the Large crescent must be longer and wider"
		)).toBe(true)
	end)

	it("rejects a canvas with no room for the punch's overshoot", function()
		expect(mentions(
			broken(function(copy)
				copy.glint.canvasScale = 1
			end),
			"glint.canvasScale"
		)).toBe(true)
	end)

	it("rejects speed lines that reach into the middle third, cover too much, or sit over the HUD", function()
		local problems = broken(function(copy)
			copy.speedLines.kinds.Dodge.innerReach.min = -0.2
			copy.speedLines.clearFraction = 0.2
		end)
		expect(mentions(problems, "speedLines.kinds.Dodge.innerReach")).toBe(true)
		expect(mentions(problems, "clearFraction must keep at least the middle third clear")).toBe(true)
		local thick = broken(function(copy)
			copy.speedLines.kinds.Dash.thicknessPixels = 12
		end)
		expect(mentions(thick, "speedLines.kinds.Dash covers up to")).toBe(true)
		local over = broken(function(copy)
			copy.speedLines.displayOrder = 50
		end)
		expect(mentions(over, "must sit under the HUD")).toBe(true)
		local crossing = broken(function(copy)
			copy.speedLines.kinds.Dash.angleJitter = 0.6
		end)
		expect(mentions(crossing, "rays never cross")).toBe(true)
	end)

	it("rejects a missing tier, counts that grow toward Low, and a pool past the draw-call share", function()
		local missing = broken(function(copy)
			copy.quality.Medium = nil
		end)
		expect(mentions(missing, "quality.Medium is missing")).toBe(true)
		local growing = broken(function(copy)
			copy.quality.Low.glints = accents.quality.High.glints + 1
		end)
		expect(mentions(growing, "quality.Low.glints is above quality.Medium's")).toBe(true)
		local heavy = broken(function(copy)
			copy.quality.High.glints = 40
		end)
		expect(mentions(heavy, "quality.High can draw")).toBe(true)
		local extra = broken(function(copy)
			copy.quality.Ultra = deepCopy(accents.quality.High)
		end)
		expect(mentions(extra, "quality.Ultra is not an fx.luau tier")).toBe(true)
	end)

	it("rejects a swing ring too short to have a direction", function()
		local problems = broken(function(copy)
			copy.swing.samples = 1
			copy.swing.minTravel = accents.swing.maxTravel + 1
		end)
		expect(mentions(problems, "swing.samples must be at least 2")).toBe(true)
		expect(mentions(problems, "minTravel < maxTravel")).toBe(true)
	end)

	it("rejects a size the director's moments.luau names that accents.luau does not have", function()
		local moments = {
			BasicHit = { glint = "Small", slashArc = { size = "Medium" } },
			Kill = { glintSize = "Enormous", slashLine = "Large", nested = { arcSize = "Tiny" } },
			Dodge = { speedLines = { kind = "Roll" } },
			Ignored = { line = "Anything", label = "glint" },
		}
		local problems = runValidator({ ["src/shared/data/moments"] = moments })
		expect(mentions(problems, "moments.Kill.glintSize names glint size 'Enormous'")).toBe(true)
		expect(mentions(problems, "moments.Kill.nested.arcSize names slash crescent size 'Tiny'")).toBe(true)
		expect(mentions(problems, "moments.Dodge.speedLines names speed-line kind 'Roll'")).toBe(true)
		expect(mentions(problems, "BasicHit")).toBe(false)
		expect(mentions(problems, "Ignored")).toBe(false)
		expect(#problems).toBe(3)
	end)
end)
